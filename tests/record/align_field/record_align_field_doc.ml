open Optitrust
open Prelude


let _ = Run.script_cpp (fun () ->

  (* (); *)
  !! Record.align_field (lit "16") "." [cTypDef "vect"];

)
