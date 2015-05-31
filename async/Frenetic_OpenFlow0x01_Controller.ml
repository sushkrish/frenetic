open Core.Std
open Async.Std
open Frenetic_OpenFlow0x01
open Async_parallel

type event = [
  | `Connect of switchId * SwitchFeatures.t
  | `Disconnect of switchId
  | `Message of switchId * Frenetic_OpenFlow_Header.t * Message.t
]

module Impl = struct
  let (events, events_writer) = Pipe.create ()

  let openflow_events (r:Reader.t) : (Frenetic_OpenFlow_Header.t * Message.t) Pipe.Reader.t =

    let reader,writer = Pipe.create () in

    let rec loop () =
      let header_str = String.create Frenetic_OpenFlow_Header.size in
      Reader.really_read r header_str >>= function 
      | `Eof _ -> 
        Pipe.close writer;
        return ()
      | `Ok -> 
        let header = Frenetic_OpenFlow_Header.parse (Cstruct.of_string header_str) in
        let body_len = header.length - Frenetic_OpenFlow_Header.size in
        let body_str = String.create body_len in
        Reader.really_read r body_str >>= function
        | `Eof _ -> 
          Pipe.close writer;
          return ()
        | `Ok -> 
          let _,message = Message.parse header body_str in
          Pipe.write_without_pushback writer (header,message);
          loop () in 
    don't_wait_for (loop ());
    reader

  type switchState =
    { features : SwitchFeatures.t;
      send : xid -> Message.t -> unit;
      send_txn : Message.t -> (Message.t list) Deferred.t }

  let switches : (switchId, switchState) Hashtbl.Poly.t =
    Hashtbl.Poly.create ()

  type threadState =
    { switchId : switchId;
      txns : (xid, Message.t list Ivar.t * Message.t list) Hashtbl.t }

  type state =
    | Initial
    | SentSwitchFeatures
    | Connected of threadState

  let client_handler (a:Socket.Address.Inet.t) (r:Reader.t) (w:Writer.t) : unit Deferred.t =
    let open Message in 

    let serialize (xid:xid) (msg:Message.t) : unit = 
      let header = Message.header_of xid msg in 
      let buf = Cstruct.create header.length in 
      Frenetic_OpenFlow_Header.marshal buf header;
      Message.marshal_body msg (Cstruct.shift buf Frenetic_OpenFlow_Header.size);
      Async_cstruct.schedule_write w buf in 

    let my_events = openflow_events r in

    let rec loop (state:state) : unit Deferred.t =
      Pipe.read my_events >>= fun next_event ->
      match state, next_event with
      (* EchoRequest messages *)
      | _, `Ok (hdr,EchoRequest bytes) ->
        serialize 0l (EchoReply bytes);
        loop state

      (* Initial *)
      | Initial, `Eof -> 
        return () 
      | Initial, `Ok (hdr,Hello bytes) ->
        (* TODO(jnf): check version? *)
        serialize 0l SwitchFeaturesRequest;
        loop SentSwitchFeatures
      | Initial, `Ok(hdr,msg) -> 
        assert false

      (* SentSwitchFeatures *)
      | SentSwitchFeatures, `Eof -> 
        return ()
      | SentSwitchFeatures, `Ok (hdr, SwitchFeaturesReply features) ->
        let switchId = features.switch_id in
        let txns = Hashtbl.Poly.create () in 
        let xid_cell = ref 0l in 
        let next_uid () = xid_cell := Int32.(!xid_cell + 1l); !xid_cell in 
        let threadState = { switchId; txns } in
        let send xid msg = serialize xid msg in 
        let send_txn msg =
          let xid = next_uid () in 
          let ivar = Ivar.create () in 
          Hashtbl.Poly.add_exn txns ~key:xid ~data:(ivar,[]);
          Ivar.read ivar in
        Hashtbl.Poly.add_exn switches ~key:switchId ~data:{ features; send; send_txn };
        Pipe.write_without_pushback events_writer (`Connect (switchId, features));
        loop (Connected threadState)
      | SentSwitchFeatures, `Ok (hdr,msg) -> 
        assert false

      (* Connected *)
      | Connected threadState, `Eof ->
        (* TODO(jnf): log disconnection *)
        Hashtbl.Poly.remove switches threadState.switchId;
        Pipe.write_without_pushback events_writer (`Disconnect threadState.switchId);
        return ()
      | Connected threadState, `Ok (hdr, msg) ->
        Pipe.write_without_pushback events_writer (`Message (threadState.switchId, hdr, msg));
        (match Hashtbl.Poly.find threadState.txns hdr.xid with 
         | None -> ()
         | Some (ivar,msgs) -> 
           Hashtbl.Poly.remove threadState.txns hdr.xid;
           Ivar.fill ivar (msg::msgs));
        loop state in

    serialize 0l (Hello (Cstruct.create 0));
    loop Initial

  let get_switches () = 
    Hashtbl.Poly.keys switches

  let get_switch_features switchId = 
    match Hashtbl.Poly.find switches switchId with 
    | Some switchState -> Some switchState.features
    | None -> None

  let send switchId xid msg = 
    match Hashtbl.Poly.find switches switchId with
    | Some switchState -> 
      switchState.send xid msg; 
      `Ok
    | None ->
      `Eof

  let send_txn switchId msg = 
    match Hashtbl.Poly.find switches switchId with
    | Some switchState -> 
      `Ok (switchState.send_txn msg)
    | None -> 
      `Eof

  let init port h =
    don't_wait_for 
      (Tcp.Server.create
         ~on_handler_error:`Raise
         (Tcp.on_port port)
         client_handler >>= fun _ -> 
       return ());
    Pipe.iter (Hub.listen_simple h) ~f:(fun (id,msg) -> match msg with
        | `Get_switches ->
          return (Hub.send h id (`Get_switches_resp (get_switches ())))
        | `Get_switch_features sw_id ->
          return (Hub.send h id (`Get_switch_features_resp (get_switch_features sw_id)))
        | `Send (sw_id, xid, msg) -> return (Hub.send h id (`Send_resp (send sw_id xid msg)))
        | `Events -> begin
            Intf.hub ~buffer_age_limit:`Unlimited ()
            >>= fun new_h ->
            Deferred.don't_wait_for (Pipe.read (Hub.listen_simple new_h)
                                     >>= function
                                     | `Ok (id, msg) ->
                                       (Pipe.iter_without_pushback events
                                          ~f:(Hub.send new_h id)));
            Hub.open_channel new_h
            >>| fun chan -> Hub.send h id (`Events_resp chan)
          end
        | `Send_txn (swid, msg) ->
          match send_txn swid msg with
          | `Eof -> return (Hub.send h id (`Send_txn_resp `Eof))
          | `Ok def ->
            begin
              Intf.hub ~buffer_age_limit:`Unlimited ()
              >>= fun new_h ->
              Deferred.don't_wait_for (def >>| Hub.send new_h id);
            Hub.open_channel new_h
            >>| fun chan -> Hub.send h id (`Send_txn_resp (`Ok chan))
          end
      )
end

let chan = Ivar.create ()

let (events, events_writer) = Pipe.create ()

let channel_transfer chan writer =
  Deferred.forever () (fun _ -> Channel.read chan >>=
                        Pipe.write writer)

let init port =
  don't_wait_for (Intf.spawn (Impl.init port)
                  >>| fun (c,_) -> Ivar.fill chan c;
                  Channel.write c `Events;
                  don't_wait_for (
                    Channel.read c >>| function
                    | `Events_resp chan ->
                      Channel.write chan `Ready;
                      channel_transfer chan events_writer))

let read_outstanding = ref false
let read_finished = Condition.create ()

let rec clear_to_read () = if (!read_outstanding)
  then Condition.wait read_finished >>= clear_to_read
  else return (read_outstanding := true)

let signal_read () = read_outstanding := false; 
  Condition.broadcast read_finished ()

(* type t = ([`Get_switches *)
(*           | `Get_switch_features of switchId *)
(*           | `Send of switchId*xid*Message.t *)
(*           | `Send_txn of switchId*Message.t], *)
(*           [ `Get_switches_resp of switchId list *)
(*           | `Get_switch_features_resp of SwitchFeatures.t option *)
(*           | `Send_resp of [`Ok | `Eof] *)
(*           | `Send_txn_resp of [`Ok of (Message.t list) Deferred.t | `Eof]]) *)
         
let get_switches () =
  Ivar.read chan >>= fun t ->
  clear_to_read () >>= fun () ->
  Channel.write t `Get_switches;
  Channel.read t >>| function
  | `Get_switches_resp resp -> signal_read (); resp

let get_switch_features (switch_id : switchId) =
  Ivar.read chan >>= fun t ->
  clear_to_read () >>= fun () ->
  Channel.write t (`Get_switch_features switch_id);
  Channel.read t >>| function
  | `Get_switch_features_resp resp -> signal_read (); resp

let send swid xid msg =
  Ivar.read chan >>= fun t ->
  clear_to_read () >>= fun () ->
  Channel.write t (`Send (swid,xid,msg));
  Channel.read t >>| function
  | `Send_resp resp -> signal_read (); resp

let send_txn swid msg =
  Ivar.read chan >>= fun t ->
  clear_to_read () >>= fun () ->
  Channel.write t (`Send_txn (swid,msg));
  Channel.read t >>| function
  | `Send_txn_resp `Eof -> `Eof
  | `Send_txn_resp (`Ok chan) ->
    signal_read ();
    let return_ivar = Ivar.create () in
    don't_wait_for (Channel.read chan
                    >>| Ivar.fill return_ivar);
    `Ok (Ivar.read return_ivar)
