open Optitrust
open Prelude

let _ = Run.script_cpp (fun _ ->
  let (f1, _) = find_var "f1" [] in
  !! Specialize_basic.funcalls f1 [false] [cTopFunDef "main"; cCall "f"];

)
