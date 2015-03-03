open Core.Std
module T = Hashtbl.Poly

let tbl = T.create () ~size:10
let parse_pol s = NetKAT_Parser.program NetKAT_Lexer.token (Lexing.from_string s)
let parse_pred s = NetKAT_Parser.pred_program NetKAT_Lexer.token (Lexing.from_string s)
let get_pol key = T.find_exn tbl key |> parse_pol
let get_pred key = T.find_exn tbl key |> parse_pred 

let () =
  (* Physical Topology *)
  T.add_exn tbl ~key:"ptopo" ~data:"
    1@1=>5@1 | 5@1=>1@1 | (*  L1 *)
    1@2=>2@1 | 2@1=>1@2 | (*  L2 *)
    2@2=>4@1 | 4@1=>2@2 | (*  L3 *)
    2@3=>3@1 | 3@1=>2@3 | (*  L4 *)
    2@4=>7@1 | 7@1=>2@4 | (*  L5 *)
    4@2=>3@2 | 3@2=>4@2 | (*  L6 *)
    3@3=>6@1 | 6@1=>3@3 | (*  L7 *)
    4@3=>5@2 | 5@2=>4@3 | (*  L8 *)
    4@4=>7@2 | 7@2=>4@4 | (*  L9 *)
    6@2=>7@3 | 7@3=>6@2   (* L10 *)";
  T.add_exn tbl ~key:"pinout" ~data:"
    (switch=1 and port=3) or
    (switch=2 and port=5) or
    (switch=2 and port=6) or
    (switch=3 and port=4) or
    (switch=4 and port=5) or
    (switch=4 and port=6)";
  (* VNO 1 *)
  T.add_exn tbl ~key:"vno1-topo" ~data:"drop";
  T.add_exn tbl ~key:"vno1-vrel" ~data:"
    ((vswitch=1 and vport=1) and (switch=1 and port=3)) or
    ((vswitch=1 and vport=2) and (switch=2 and port=5)) or
    ((vswitch=1 and vport=3) and (switch=4 and port=5))";
  T.add_exn tbl ~key:"vno1-vinout" ~data:"
    (vswitch=1 and vport=1) or
    (vswitch=1 and vport=2) or
    (vswitch=1 and vport=3)";
  T.add_exn tbl ~key:"vno1-vingpol" ~data:"
    vswitch:=1;
    if switch=1 and port=3 then vport:=1 
    else if switch=2 and port=5 then vport:=2
    else if switch=4 and port=5 then vport:=3
    else drop";
  (* VNO2 *)
  T.add_exn tbl ~key:"vno2-topo" ~data:"
    1@3=>>2@2 | 2@2=>>1@3 |
    1@2=>>4@2 | 4@2=>>1@2 |
    2@3=>>3@3 | 3@3=>>2@3 |
    3@2=>>4@3 | 4@3=>>3@2";
  T.add_exn tbl ~key:"vno2-vrel" ~data:"
    ((vswitch=1 and vport=1) and (switch=1 and port=3)) or
    ((vswitch=2 and vport=1) and (switch=2 and port=6)) or
    ((vswitch=3 and vport=1) and (switch=3 and port=4)) or
    ((vswitch=4 and vport=1) and (switch=4 and port=6))";
  T.add_exn tbl ~key:"vno2-vinout" ~data:"
    (vswitch=1 and vport=1) or
    (vswitch=2 and vport=1) or
    (vswitch=3 and vport=1) or
    (vswitch=4 and vport=1)";
  T.add_exn tbl ~key:"vno2-vingpol" ~data:"
    vport:=1;
    if switch=1 and port=3 then vswitch:=1
    else if switch=2 and port=6 then vswitch:=2
    else if switch=3 and port=4 then vswitch:=3
    else if switch=4 and port=6 then vswitch:=4
    else drop";
