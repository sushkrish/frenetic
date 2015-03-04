open Core.Std
open Async.Std


let main () : unit = match Sys.argv |> Array.to_list with
  | _ :: "compile-server" :: args -> Compile_Server.main args
  | _ :: "http-controller" :: args -> Http_Controller.main args
  | _ ->
    printf "Invalid arguments.\n";
    Shutdown.shutdown 0

let () = 
  let str = "{ \"type\" : \"union\",
\"pols\" : [ { \"type\" : \"seq\", \"pols\" : [  { \"type\" : \"filter\", \"pred\" :
{ \"type\" : \"test\", \"header\" : \"switch\", \"value\" : \"1\" } }, { \"type\" :
\"union\", \"pols\" : [ { \"type\" : \"seq\", \"pols\" : [  { \"type\" : \"filter\",
\"pred\" : { \"type\" : \"and\", \"preds\" : [ { \"type\" : \"test\", \"header\" :
\"ipSrc\", \"value\" : \"10.0.0.1\" }] } }, { \"type\" : \"mod\", \"header\"
: \"port\", \"value\" : \"2\" }] } , { \"type\" : \"seq\", \"pols\" : [  { \"type\"
: \"filter\", \"pred\" : { \"type\" : \"and\", \"preds\" : [ { \"type\" : \"test\",
\"header\" : \"ipSrc\", \"value\" : \"10.0.0.1\" }] } }, { \"type\" :
\"mod\", \"header\" : \"port\", \"value\" : \"1\" }] } , { \"type\" : \"seq\",
\"pols\" : [  { \"type\" : \"filter\", \"pred\" : { \"type\" : \"and\", \"preds\" :
[ { \"type\" : \"test\", \"header\" : \"ipSrc\", \"value\" : \"10.0.0.2\" }]
} }, { \"type\" : \"mod\", \"header\" : \"port\", \"value\" : \"3\" }] } , {
\"type\" : \"seq\", \"pols\" : [  { \"type\" : \"filter\", \"pred\" : { \"type\" :
\"and\", \"preds\" : [ { \"type\" : \"test\", \"header\" : \"ipSrc\", \"value\" :
\"10.0.0.3\" }] } }, { \"type\" : \"mod\", \"header\" : \"port\", \"value\"
: \"3\" }] } , { \"type\" : \"seq\", \"pols\" : [  { \"type\" : \"filter\", \"pred\"
: { \"type\" : \"and\", \"preds\" : [ { \"type\" : \"test\", \"header\" : \"ipSrc\",
\"value\" : \"10.0.0.3\" }] } }, { \"type\" : \"mod\", \"header\" :
\"port\", \"value\" : \"2\" }] }] }] } , { \"type\" : \"seq\", \"pols\" : [  {
\"type\" : \"filter\", \"pred\" : { \"type\" : \"test\", \"header\" : \"switch\",
\"value\" : \"2\" } }, { \"type\" : \"union\", \"pols\" : [ { \"type\" : \"seq\",
\"pols\" : [  { \"type\" : \"filter\", \"pred\" : { \"type\" : \"and\", \"preds\" :
[ { \"type\" : \"test\", \"header\" : \"ipSrc\", \"value\" : \"10.0.0.2\" }]
} }, { \"type\" : \"mod\", \"header\" : \"port\", \"value\" : \"2\" }] } , {
\"type\" : \"seq\", \"pols\" : [  { \"type\" : \"filter\", \"pred\" : { \"type\" :
\"and\", \"preds\" : [ { \"type\" : \"test\", \"header\" : \"ipSrc\", \"value\" :
\"10.0.0.2\" }] } }, { \"type\" : \"mod\", \"header\" : \"port\", \"value\"
: \"2\" }] } , { \"type\" : \"seq\", \"pols\" : [  { \"type\" : \"filter\", \"pred\"
: { \"type\" : \"and\", \"preds\" : [ { \"type\" : \"test\", \"header\" : \"ipSrc\",
\"value\" : \"10.0.0.1\" }] } }, { \"type\" : \"mod\", \"header\" :
\"port\", \"value\" : \"5\" }] } , { \"type\" : \"seq\", \"pols\" : [  { \"type\" :
\"filter\", \"pred\" : { \"type\" : \"and\", \"preds\" : [ { \"type\" : \"test\",
\"header\" : \"ipSrc\", \"value\" : \"10.0.0.3\" }] } }, { \"type\" :
\"mod\", \"header\" : \"port\", \"value\" : \"5\" }] } , { \"type\" : \"seq\",
\"pols\" : [  { \"type\" : \"filter\", \"pred\" : { \"type\" : \"and\", \"preds\" :
[ { \"type\" : \"test\", \"header\" : \"ipSrc\", \"value\" : \"10.0.0.3\" }]
} }, { \"type\" : \"mod\", \"header\" : \"port\", \"value\" : \"1\" }] }] }] } , {
\"type\" : \"seq\", \"pols\" : [  { \"type\" : \"filter\", \"pred\" : { \"type\" :
\"test\", \"header\" : \"switch\", \"value\" : \"4\" } }, { \"type\" : \"union\",
\"pols\" : [ { \"type\" : \"seq\", \"pols\" : [  { \"type\" : \"filter\", \"pred\" :
{ \"type\" : \"and\", \"preds\" : [ { \"type\" : \"test\", \"header\" : \"ipSrc\",
\"value\" : \"10.0.0.3\" }] } }, { \"type\" : \"mod\", \"header\" :
\"port\", \"value\" : \"1\" }] } , { \"type\" : \"seq\", \"pols\" : [  { \"type\" :
\"filter\", \"pred\" : { \"type\" : \"and\", \"preds\" : [ { \"type\" : \"test\",
\"header\" : \"ipSrc\", \"value\" : \"10.0.0.3\" }] } }, { \"type\" :
\"mod\", \"header\" : \"port\", \"value\" : \"3\" }] } , { \"type\" : \"seq\",
\"pols\" : [  { \"type\" : \"filter\", \"pred\" : { \"type\" : \"and\", \"preds\" :
[ { \"type\" : \"test\", \"header\" : \"ipSrc\", \"value\" : \"10.0.0.1\" }]
} }, { \"type\" : \"mod\", \"header\" : \"port\", \"value\" : \"5\" }] } , {
\"type\" : \"seq\", \"pols\" : [  { \"type\" : \"filter\", \"pred\" : { \"type\" :
\"and\", \"preds\" : [ { \"type\" : \"test\", \"header\" : \"ipSrc\", \"value\" :
\"10.0.0.2\" }] } }, { \"type\" : \"mod\", \"header\" : \"port\", \"value\"
: \"5\" }] } , { \"type\" : \"seq\", \"pols\" : [  { \"type\" : \"filter\", \"pred\"
: { \"type\" : \"and\", \"preds\" : [ { \"type\" : \"test\", \"header\" : \"ipSrc\",
\"value\" : \"10.0.0.2\" }] } }, { \"type\" : \"mod\", \"header\" :
\"port\", \"value\" : \"3\" }] }] }] } , { \"type\" : \"seq\", \"pols\" : [  {
\"type\" : \"filter\", \"pred\" : { \"type\" : \"test\", \"header\" : \"switch\",
\"value\" : \"5\" } }, { \"type\" : \"union\", \"pols\" : [ { \"type\" : \"seq\",
\"pols\" : [  { \"type\" : \"filter\", \"pred\" : { \"type\" : \"and\", \"preds\" :
[ { \"type\" : \"test\", \"header\" : \"ipSrc\", \"value\" : \"10.0.0.2\" }]
} }, { \"type\" : \"mod\", \"header\" : \"port\", \"value\" : \"1\" }] } , {
\"type\" : \"seq\", \"pols\" : [  { \"type\" : \"filter\", \"pred\" : { \"type\" :
\"and\", \"preds\" : [ { \"type\" : \"test\", \"header\" : \"ipSrc\", \"value\" :
\"10.0.0.1\" }] } }, { \"type\" : \"mod\", \"header\" : \"port\", \"value\"
: \"2\" }] } , { \"type\" : \"seq\", \"pols\" : [  { \"type\" : \"filter\", \"pred\"
: { \"type\" : \"and\", \"preds\" : [ { \"type\" : \"test\", \"header\" : \"ipSrc\",
\"value\" : \"10.0.0.3\" }] } }, { \"type\" : \"mod\", \"header\" :
\"port\", \"value\" : \"1\" }] }] }] }] }" in
  Printf.printf "%s"
    (Yojson.Basic.to_string ~std:true
       (NetKAT_Json.policy_to_json (NetKAT_Json.policy_from_json_string str)))

let () =
  never_returns (Scheduler.go_main ~max_num_open_file_descrs:4096 ~main ())
