open Optitrust
open Prelude
let _ = Run.script_cpp( fun() ->
  Matrix_basic.memset [cFor "i" ])
