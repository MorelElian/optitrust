open Optitrust
open Prelude


let _ = Run.script_cpp (fun () ->

  !! Align.alloc (lit "64") [cCall "MALLOC1"];
  !! Align.alloc (lit "64") [cCall "MALLOC3"];
  !!! (); (* TODO: Find how to eliminate this reparse *)

)
