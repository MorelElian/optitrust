open Optitrust
open Prelude

let _ = Run.script_cpp (fun _ ->
  !! ();
  (* !! Accesses_basic.shift ~factor:(trm_float 5.0) [cVarDef "x"] (* [cRead ~addr:[cVar "x"]()] *) *)

)
