open Optitrust
open Target


let _ = Run.script_cpp (fun _ ->

  !! Function_basic.dps_def [cFunDef "f"];

)
