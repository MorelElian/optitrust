open Optitrust
open Prelude

let _ = Flags.check_validity := true
let _ = Flags.recompute_resources_between_steps := true

(** Reproducing a subset of the PIC case study *)

let _ = Run.script_cpp (fun () ->
  let ctx = cFunBody "simulate_single_cell" in
  let vect = typ_find_var "vect" [ctx] in
  let particle = typ_find_var "particle" [ctx] in

  bigstep "make local copies of field and particles";
  !! Matrix.local_name_tile ~var:"fieldAtCorners"
    ~elem_ty:vect ~uninit_post:true
    ~local_var:"lFieldAtCorners" [ctx; cFor "idStep"];
  (* !! Matrix.local_name_tile ~var:"particles"
    ~elem_ty:particle
    ~local_var:"lParticles" [ctx; cFor "idStep"]; *)

  bigstep "inline helper functions and reveal record fields";
  !! Function.inline_multi [ctx; cFuns ["cornerInterpolationCoeff"; "matrix_vect_mul"; "vect_add"; "vect_mul"]];
  !! Record.split_fields ~typ:particle [tSpanSeq [ctx]];
  !! Record.split_fields ~typ:vect [tSpanSeq [ctx]];
  !! Record.to_variables [ctx; cVarDefs ["fieldAtPos"; "pos2"; "speed2"; "accel"]];

(* TODO:
  let fieldFactor = trm_mul (trm_mul (var "deltaT") (var "deltaT")) (trm_div (var "pCharge") (var "pMass")) in
  !! Variable.insert "fieldFactor" fieldFactor [tBefore; cVarDef "lFieldAtCorners"];
  !! Accesses.scale ~factor:(var "fieldFactor") [nbMulti; cVarRe "fieldAtPos[XYZ]"];
  !! Accesses.scale ~factor:(var "fieldFactor") [nbMulti; cVarRe "speed2[XYZ]"];
  !! Accesses.scale ~factor:(var "deltaT") [nbMulti; sExprRe "particles\\.speed\\.[xyz]"];
  !! Accesses.scale_immut ~factor:(var "deltaT") [nbMulti; cVarRe "speed2[XYZ]"];
*)
  bigstep "scale field and particles";
  let pCharge = trm_find_var "pCharge" [ctx] in
  let pMass = trm_find_var "pMass" [ctx] in
  let deltaT = trm_find_var "deltaT" [ctx] in
  let fieldFactor = trm_mul (trm_div pCharge pMass) (trm_mul deltaT deltaT) in
  let scaleField d = Accesses.scale_var ~factor:fieldFactor [nbMulti; ctx; cVarDef ("fieldAtPos" ^ d)] in
  !! List.iter scaleField ["X"; "Y"; "Z"];
  let scaleSpeed d = Accesses.scale_immut ~factor:deltaT [nbMulti; ctx; cVarDef ("speed2" ^ d)] in
  !! List.iter scaleSpeed ["X"; "Y"; "Z"];

  let lFieldAtCorners = trm_find_var "lFieldAtCorners" [ctx] in
  let idx_evar = new_var "i" in
  let pattern_evars = Var_map.(singleton idx_evar None) in
  let address_pattern field = trm_struct_access (trm_array_access lFieldAtCorners (trm_var idx_evar)) field in
  !! Accesses.scale ~factor:fieldFactor ~address_pattern:(address_pattern "x") ~pattern_evars [tSpan [tAfter; cVarDef "lFieldAtCorners"] [tLast]];
  !! Accesses.scale ~factor:fieldFactor ~address_pattern:(address_pattern "y") ~pattern_evars [tSpan [tAfter; cVarDef "lFieldAtCorners"] [tLast]];
  !! Accesses.scale ~factor:fieldFactor ~address_pattern:(address_pattern "z") ~pattern_evars [tSpan [tAfter; cVarDef "lFieldAtCorners"] [tLast]];

  let particles = trm_find_var "particles" [ctx] in
  let address_pattern field = trm_struct_access (trm_struct_access (trm_array_access particles (trm_var idx_evar)) "speed") field in
  !! Accesses.scale ~factor:fieldFactor ~address_pattern:(address_pattern "x") ~pattern_evars [tSpan [tBefore; cFor "idStep"] [tLast]];
  !! Accesses.scale ~factor:fieldFactor ~address_pattern:(address_pattern "y") ~pattern_evars [tSpan [tBefore; cFor "idStep"] [tLast]];
  !! Accesses.scale ~factor:fieldFactor ~address_pattern:(address_pattern "z") ~pattern_evars [tSpan [tBefore; cFor "idStep"] [tLast]];

  bigstep "finish with style";
  !! Variable.inline [ctx; cVarDefs ["accelX"; "accelY"; "accelZ"; "pos2X"; "pos2Y"; "pos2Z"]];
  !!! Arith.(simpls_rec [expand; gather_rec]) [ctx];
  !! Function.use_infix_ops ~indepth:true [ctx];
  !! Cleanup.std ();

  (* TODO:
    - cleanup script
    - local name tile: get elem_ty from program / resources
    - inlines: regroup together, problem: phase ordering matters, need fixpoint?
    - set_explicit: regroup
    - avoid binding fieldAtPosTmp
    - allow writing C code for constructing factors, need to parse and put in correct context with local ids
    - insert var for scaleFieldFactor
    - bind pointer to lParticles cell?

    !! Variable.bind_multi ~const:true ~is_ptr:true ~dest:[tBefore; cVarDef "p"] "paddr" [nbMulti; ctx; cCellAccess ~base:[cVar "lParticles"] ()];

    - inline cornerInterpolationCoeff to allow array on stack
    - FIXME: reparse triggers access normalization
  *)
)
