open Optitrust
open Target

let _ = Run.script_cpp (fun _ ->

  !! Omp.ordered  [] [tBefore; cCall "printf"];
  !! Omp.parallel_for [Ordered_c 0; Schedule (Dynamic,"0")] [tBefore; cFor "i"];
)
