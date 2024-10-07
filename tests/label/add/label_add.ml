open Optitrust
open Prelude

let _ = Run.script_cpp (fun _ ->

   !! Label_basic.add "start" [cWriteVar "x"] ;
   !! Label_basic.add "cond" [cIf ()];
   !! Label_basic.add "incr_1" [cIf (); sInstr "x++"];
   !! Label_basic.add "incr_2" [cIf (); sInstr "x--" ];
   !! Label_basic.add "stop" [cReturn ()];

)
