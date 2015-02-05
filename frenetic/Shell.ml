open Core.Std
open Async.Std
open NetKAT_Types

module Controller = Async_NetKAT_Controller
module LC = NetKAT_LocalCompiler
module Field = NetKAT_FDD.Field
module Log = Async_OpenFlow.Log

module Parser = struct

    open MParser

    let field (f : Field.t) : (Field.t, bytes list) MParser.t =
      MParser.Tokens.symbol (Field.to_string f |> String.lowercase) >>
      return f

    let any_field : (Field.t, bytes list) MParser.t =
      field Field.Switch <|>
      field Field.Location <|>
      field Field.EthSrc <|>
      field Field.EthDst <|>
      field Field.Vlan <|>
      field Field.VlanPcp <|>
      field Field.EthType <|>
      field Field.IPProto <|>
      field Field.IP4Src <|>
      field Field.IP4Dst <|>
      field Field.TCPSrcPort <|>
      field Field.TCPDstPort

    let ord_symbol : (string, bytes list) MParser.t =
      Tokens.symbol "<"

    let ordering : (LC.order, bytes list) MParser.t =
      (Tokens.symbol "heuristic" >> return `Heuristic) <|>
      (Tokens.symbol "default" >> return `Default) <|>
      (sep_by1 any_field (Tokens.symbol "<") >>= 
	 fun fields -> return (`Static fields))

    let order : (LC.order, bytes list) MParser.t =
      Tokens.symbol "order" >>
      ordering

end

let compose f g x = f (g x)

let controller : (Controller.t option) ref = ref None

(* Use heuristic ordering by default *)
let order : LC.order ref = ref `Heuristic

let print_order () : unit =
  match !order with
  | `Heuristic -> print_endline "Ordering Mode: Heuristic"
  | `Default -> print_endline "Ordering Mode: Default"
  | `Static fields ->
     let strs = List.rev (List.map fields Field.to_string) in
     let cs = String.concat ~sep:" < " strs in
     printf "Ordering Mode: %s\n%!" cs

let set_order (o : LC.order) : unit = 
  match o with
  | `Heuristic -> 
     order := `Heuristic; 
     Controller.set_order (uw !controller) `Heuristic;
     print_order ()
  | `Default -> 
     order := `Default;
     Controller.set_order (uw !controller) `Default;
     print_order ()
  | `Static ls ->
     let curr_order = match !order with
                      | `Heuristic -> Field.all_fields
		      | `Default -> Field.all_fields
		      | `Static fields -> fields
     in
     let removed = List.filter curr_order (compose not (List.mem ls)) in
     let new_order = List.append (List.rev ls) removed in
     order := (`Static new_order); 
     Controller.set_order (uw !controller) (`Static new_order);
     print_order ()
  
let field_from_string (opp_str : string) : Field.t option = 
  match (String.lowercase opp_str) with
  | "switch" -> Some Switch
  | "location" -> Some Location
  | "ethsrc" -> Some EthSrc
  | "ethdst" -> Some EthDst
  | "vlan" -> Some Vlan
  | "vlanpcp" -> Some VlanPcp
  | "ethtype" -> Some EthType
  | "ipproto" -> Some IPProto
  | "ip4src" -> Some IP4Src
  | "ip4dst" -> Some IP4Dst
  | "tcpsrcport" -> Some TCPSrcPort
  | "tcpdstport" -> Some TCPDstPort
  | _ -> None

let string_of_position (p : Lexing.position) : string =
  sprintf "%s:%d:%d" p.pos_fname p.pos_lnum (p.pos_cnum - p.pos_bol)

let parse_policy ?(name = "") (pol_str : string) : (policy, string) Result.t =
  let lexbuf = Lexing.from_string pol_str in
  lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = name };
  try
    Ok (NetKAT_Parser.program NetKAT_Lexer.token lexbuf)
  with
    | Failure "lexing: empty token" ->
      Error (sprintf "error lexing policy at %s" (string_of_position lexbuf.lex_curr_p))
    | Parsing.Parse_error ->
      Error (sprintf "error parsing policy at %s" (string_of_position lexbuf.lex_curr_p))

type showable =
  | Ordering

type command =
  | Update of policy
  | Order of LC.order
  | Show of showable
  | Exit
  | Help

let with_error (msg : string) 
	       (to_string : 'a -> string) 
	       (f : 'a -> 'b option) 
	       (x : 'a) : 'b option =
  match f x with
  | Some result -> Some result
  | None -> 
     printf "%s: %s\n%!" msg (to_string x);
     None

let parse_command (line : string) : command option = 
  match (compose String.lstrip String.rstrip) (String.lowercase line) with
  | "help" -> Some Help
  | "exit" -> Some Exit
  | "order" -> Some (Show Ordering)
  | _ -> (match String.lsplit2 line ~on:' ' with
    | Some ("order", order_str) ->
       (match (MParser.parse_string Parser.ordering order_str []) with
	| Success order -> Some (Order order)
	| Failed (msg, e) -> (print_endline msg; None))
(*       (match parse_order order_str with
	| Some order -> Some (Order (`Static order))
	| None -> None) *)
    | Some ("update", pol_str) ->
      (match parse_policy pol_str with
       | Ok pol -> Some (Update pol)
       | Error msg -> (print_endline msg; None))
    | _ -> None)

let print_help () : unit =
  printf "Read source code for help.\n"

let rec repl (pol_writer : policy Pipe.Writer.t) : unit Deferred.t =
  printf "frenetic> %!";
  Reader.read_line (Lazy.force Reader.stdin) >>= fun input ->
  let handle line = 
    match line with
    | `Eof -> Shutdown.shutdown 0
    | `Ok line -> match parse_command line with
		  | Some Exit -> 
		     print_endline "Goodbye!";
		     Shutdown.shutdown 0
		  | Some (Show Ordering) -> print_order ()
		  | Some Help -> print_help ()
		  | Some (Update pol) -> Pipe.write_without_pushback pol_writer pol
		  | Some (Order order) -> set_order order
		  | None -> ()
  in handle input; repl pol_writer

let start_controller () : policy Pipe.Writer.t =
  let pipes = Async_NetKAT.PipeSet.empty in
  let (pol_reader, pol_writer) = Pipe.create () in
  let app = Async_NetKAT.Policy.create_async ~pipes:pipes drop
    (fun topo send () ->
       let pol_writer' = send.update in
       let _ = Pipe.transfer_id pol_reader pol_writer' in
       fun event ->
         printf "Got network event.\n%!";
         return None) in
  let () = don't_wait_for
    (Async_NetKAT_Controller.start app () >>= 
       (fun ctrl -> controller := Some ctrl;
	            Async_NetKAT_Controller.disable_discovery ctrl)) in
  pol_writer

let log_file = "frenetic.log"

let main (args : string list) : unit =
  Log.set_output [Async.Std.Log.Output.file `Text log_file];
  printf "Frenetic Shell\n%!";
  match args with
  | [] ->
    let pol_writer = start_controller () in
    let _ = repl pol_writer in
    ()
  | _ -> (printf "Invalid arguments to shell.\n"; Shutdown.shutdown 0)

