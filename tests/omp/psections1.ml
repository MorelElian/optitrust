open Optitrust
open Target

let _ = Run.script_cpp (fun _ ->

  !! Sequence_basic.intro 3 [cCall "XAXIS"];
  !! Omp.section [cCall "XAXIS"];
  !! Omp.section [cCall "YAXIS"];
  !! Omp.section [cCall "ZAXIS"];
  !! Omp.parallel_sections [cSeq ~args_pred:(target_list_one_st [cCall "XAXIS"])()];

)
