open Ast

(* [insert ty tg] expects the target [ŧg] to point to a get operation
    then it will cast the current type to [ty]
*)
let insert (ty : typ) : Target.Transfo.t =
  Target.apply_on_targets (Cast_core.insert ty)


  