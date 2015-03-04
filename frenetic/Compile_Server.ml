open Core.Std
open Async.Std
open Cohttp_async
open NetKAT_Types
module Server = Cohttp_async.Server
open Common
open Baked_VNOS

let policy = ref NetKAT_Types.drop
let vno_pols = Array.of_list [NetKAT_Types.drop; NetKAT_Types.drop]

let rec virtualize_pred pred =
  match pred with
  | Test (Switch sw) -> Test (VSwitch sw)
  | Test (Location (Physical pt)) -> Test (VPort (Int64.of_int32 pt))
  | Test hv -> Test hv
  | And (a, b) -> And (virtualize_pred a, virtualize_pred b)
  | Or (a, b) -> Or (virtualize_pred a, virtualize_pred b)
  | Neg a -> Neg (virtualize_pred a)

let rec virtualize pol =
  match pol with
  | Filter pred -> Filter (virtualize_pred pred)
  | Mod (Location (Physical pt)) -> Mod (VPort (Int64.of_int32 pt))
  | Union (p, q) -> Union (virtualize p, virtualize q)
  | Seq (p, q) -> Seq (virtualize p, virtualize q)
  | Star p -> Star (virtualize p)
  | _ -> assert false

let vno_pol () =
  let pinout = get_pred "pinout" in
  let vno1 = NetKAT_VirtualCompiler.compile
    (Array.get vno_pols 0)
    (get_pred "vno1-vrel")
    (get_pol "vno1-topo")
    (get_pol "vno1-vingpol")
    (get_pred "vno1-vinout")
    (get_pred "vno1-vinout")
    (get_pol "ptopo")
    pinout
    pinout in
  let vno2 = NetKAT_VirtualCompiler.compile
    (Array.get vno_pols 1)
    (get_pred "vno2-vrel")
    (get_pol "vno2-topo")
    (get_pol "vno2-vingpol")
    (get_pred "vno2-vinout")
    (get_pred "vno2-vinout")
    (get_pol "ptopo")
    pinout
    pinout in
  let global =
    NetKAT_GlobalFDDCompiler.of_policy ~dedup:true ~ing:pinout ~remove_duplicates:true
      (Optimize.mk_union vno1 vno2)
  in
    NetKAT_GlobalFDDCompiler.to_local NetKAT_FDD.Field.Vlan (NetKAT_FDD.Value.of_int 0xffff) global


let handle_request
  ~(body : Cohttp_async.Body.t)
   (client_addr : Socket.Address.Inet.t)
   (request : Request.t) : Server.response Deferred.t =
  match request.meth, extract_path request with
    | `POST, ["compile"] ->
      printf "POST /compile";
      handle_parse_errors body
        (fun body ->
           Body.to_string body >>= fun str ->
           return (NetKAT_Json.policy_from_json_string str))
        (fun pol ->
         let fdd = NetKAT_LocalCompiler.compile pol in
         let sws = NetKAT_Misc.switches_of_policy pol in
         let sws = if List.length sws = 0 then [0L] else sws in
         let tbls = List.map sws ~f:(fun sw ->
          let tbl_json = NetKAT_SDN_Json.flowTable_to_json
            (NetKAT_LocalCompiler.to_table sw fdd) in
          `Assoc [("switch_id", `Int (Int64.to_int_exn sw));
                  ("tbl", tbl_json)]) in
         let resp = Yojson.Basic.to_string ~std:true (`List tbls) in
         Cohttp_async.Server.respond_with_string resp)
    | `POST, ["update"] ->
      printf "POST /update";
      handle_parse_errors body parse_update_json
        (fun p ->
           policy := p;
           Cohttp_async.Server.respond `OK)
    | `POST, ["update_vno"; vnoId] ->
      printf "POST /update_vno %s" vnoId;
      let vnoId = Int.of_string vnoId in
      handle_parse_errors body parse_update_json (fun p ->
        Array.set vno_pols (vnoId - 1) (virtualize p);
        Cohttp_async.Server.respond `OK)
    | `GET, [switchId; "flow_table"] ->
       let sw = Int64.of_string switchId in
       NetKAT_LocalCompiler.compile !policy |>
         NetKAT_LocalCompiler.to_table sw |>
         NetKAT_SDN_Json.flowTable_to_json |>
         Yojson.Basic.to_string ~std:true |>
         Cohttp_async.Server.respond_with_string
    | `GET, [switchId; "vno_flow_table"] ->
       let sw = Int64.of_string switchId in
       vno_pol() |>
         NetKAT_LocalCompiler.to_table sw |>
         NetKAT_SDN_Json.flowTable_to_json |>
         Yojson.Basic.to_string ~std:true |>
         Cohttp_async.Server.respond_with_string
    | _, _ ->
       printf "Malformed request from cilent";
       Cohttp_async.Server.respond `Not_found

let listen ?(port=9000) =
  NetKAT_FDD.Field.set_order
   [ Switch; Location; VSwitch; VPort; IP4Dst; Vlan; TCPSrcPort; TCPDstPort; IP4Src;
      EthType; EthDst; EthSrc; VlanPcp; IPProto ];
  ignore (Cohttp_async.Server.create (Tcp.on_port port) handle_request)

let main (args : string list) : unit = match args with
  | [ "--port"; p ] | [ "-p"; p ] ->
    listen ~port:(Int.of_string p)
  | [] -> listen ~port:9000
  |  _ -> (print_endline "Invalid command-line arguments"; Shutdown.shutdown 1)
