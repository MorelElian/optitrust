open Optitrust
open Target

let _ = Run.script_cpp (fun _ ->

  !! Omp.for_ [Ordered_c 0] [tBefore; cFor "i"];
  !! Omp.ordered  [] [tBefore; occIndex ~nb:2 0; cCall "work"];
  !! Omp.ordered  [] [tBefore; occIndex ~nb:2 1; cCall "work"];
)
