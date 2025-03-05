open Ast
open Trm
open Typ
open Mark
open Resource_formula

(* ---- RESOURCE-RELATED TRM CONSTRUCTORS and INVERTERS ---- *)

(** Primitive function that turns off resource computation and checking from that point onwards.
    Resource computation resumes upon meeting an outer postcondition which will be admitted. *)
let var_admitted = toplevel_var "__admitted"
let var_justif = toplevel_var "justif"

let ghost_call_inv t =
  Pattern.pattern_match t [
    Pattern.(trm_apps !__ nil !__ !__) (fun ghost_fn ghost_args ghost_bind () ->
      if not (trm_has_attribute GhostInstr t) then raise_notrace Pattern.Next;
      Some { ghost_fn; ghost_args; ghost_bind }
    );
    Pattern.__ (fun () -> None)
  ]

let var_ghost_begin = toplevel_var "__ghost_begin"
let var_ghost_end = toplevel_var "__ghost_end"

let var_ghost_ret = toplevel_typvar "__ghost_ret"
let typ_ghost_ret: typ = typ_var var_ghost_ret
let var_ghost_fn = toplevel_typvar "__ghost_fn"
let typ_ghost_fn: typ = typ_var var_ghost_fn

let is_typ_ghost_ret (ty: typ): bool =
  match typ_var_inv ty with
  | Some v when var_eq v var_ghost_ret -> true
  | _ -> false

let var_with_reverse = toplevel_var "__with_reverse"

let ghost_pair_fresh_id = Tools.fresh_generator ()
let generate_ghost_pair_var ?name () =
  match name with
  | Some name -> new_var name
  | None -> new_var (sprintf "__ghost_pair_%d" (ghost_pair_fresh_id ()))

let void_when_resource_typing_disabled (f : unit -> trm) : trm =
  if !Flags.resource_typing_enabled
    then f ()
    else Nobrace.trm_seq_nomarks []

let ghost (g : ghost_call): trm =
  void_when_resource_typing_disabled (fun () -> Trm.trm_ghost_force g)

let ghost_begin (ghost_pair_var: var) (ghost_call: ghost_call) : trm =
  void_when_resource_typing_disabled (fun () ->
    trm_add_attribute GhostInstr (trm_let (ghost_pair_var, typ_ghost_fn)
      (trm_apps (trm_var var_ghost_begin) [ghost ghost_call])))

let ghost_end (ghost_pair_var: var): trm =
  void_when_resource_typing_disabled (fun () ->
    trm_add_attribute GhostInstr (trm_apps (trm_var var_ghost_end) [trm_var ghost_pair_var]))

let ghost_pair ?(name: string option) (ghost_call: ghost_call) : var * trm * trm =
  let ghost_pair_var = generate_ghost_pair_var ?name () in
  (ghost_pair_var,
   ghost_begin ghost_pair_var ghost_call,
   ghost_end ghost_pair_var)

let ghost_custom_pair ?(name: string option) (forward_fn: trm) (backward_fn: trm): var * trm * trm =
  let ghost_pair_var = generate_ghost_pair_var ?name () in
  let ghost_with_reverse = trm_apps (trm_var var_with_reverse) [forward_fn; backward_fn] in
  (ghost_pair_var,
   ghost_begin ghost_pair_var { ghost_fn = ghost_with_reverse; ghost_args = []; ghost_bind = [] },
   ghost_end ghost_pair_var)

let ghost_scope ?(pair_name: string option) (ghost_call: ghost_call) (t: trm): trm =
  let _, ghost_begin, ghost_end = ghost_pair ?name:pair_name ghost_call in
  Nobrace.trm_seq_nomarks [ghost_begin; t; ghost_end]

let ghost_begin_inv (t: trm): (var * ghost_call) option =
  Pattern.pattern_match t [
    Pattern.(trm_let !__ __ (trm_apps1 (trm_specific_var var_ghost_begin) (trm_apps !__ nil !__ !__))) (fun pair_var ghost_fn ghost_args ghost_bind () ->
      Some (pair_var, { ghost_fn; ghost_args; ghost_bind })
    );
    Pattern.__ (fun () -> None)
  ]

let ghost_end_inv (t: trm): var option =
  Pattern.pattern_match t [
    Pattern.(trm_apps1 (trm_specific_var var_ghost_end) (trm_var !__)) (fun pair_var () -> Some pair_var);
    Pattern.__ (fun () -> None)
  ]

let admitted ?(justif: trm option) (): trm =
  let ghost_args = match justif with
    | None -> []
    | Some j -> [var_justif, j]
  in
  trm_apps (trm_var var_admitted) [] ~ghost_args

module Pattern = struct
  include Pattern

  let admitted justif_opt =
    let fghost_args k args =
      match args with
      | [] -> justif_opt k None
      | [(_, j)] -> justif_opt k (Some j)
      | _ -> raise Next
    in
    trm_apps (trm_specific_var var_admitted) nil fghost_args nil
end

let admitted_inv (t : trm) : (formula option) option =
  Pattern.pattern_match_opt t [
    Pattern.(admitted !__) (fun justif_opt () -> justif_opt)
  ]

let ghost_admitted ?(justif: trm option) (contract: fun_contract): trm =
  if Resource_set.is_empty contract.pre && Resource_set.is_empty contract.post
  then Nobrace.trm_seq_nomarks []
  else ghost (ghost_closure_call contract (trm_seq_nomarks [admitted ?justif ()]))

let ghost_rewrite (before: formula) (after: formula) (justif: formula): trm =
  let contract = {
    pre = Resource_set.make ~linear:[new_anon_hyp (), before] ();
    post = Resource_set.make ~linear:[new_anon_hyp (), after] ()
  } in
  ghost_admitted contract ~justif

let var_ghost_forget_init = toplevel_var "forget_init"

let ghost_forget_init (f: formula): trm =
  ghost (ghost_call var_ghost_forget_init ["H", f])

let var_assert_alias = toplevel_var "assert_alias"

let ghost_intro_alias (x : var) (t : trm) : trm =
  ghost (ghost_call var_assert_alias ["x", trm_var x; "y", t])

let may_ghost_intro_alias (x : var) (t : trm) (res : resource_set) : trm =
  if Var_map.mem x res.aliases
  then Nobrace.trm_seq_nomarks []
  else ghost_intro_alias x t

let is_ghost_alias (t : trm) : bool =
  begin match ghost_call_inv t with
  | Some { ghost_fn = g; _ } ->
    begin match trm_var_inv g with
    | Some v when var_eq var_assert_alias v -> true
    | _ -> false
    end
  | _ -> false
  end

let var_assert_eq = toplevel_var "assert_eq"

let var_ghost_hide = toplevel_var "hide"
let var_ghost_hide_rev = toplevel_var "hide_rev"

let ghost_pair_hide (f: formula): var * trm * trm =
  ghost_pair (ghost_call var_ghost_hide ["H", f])

let var_ghost_group_focus_subrange = toplevel_var "group_focus_subrange"
let var_ghost_group_focus_subrange_ro = toplevel_var "group_focus_subrange_ro"
let var_ghost_group_focus_subrange_uninit = toplevel_var "group_focus_subrange_uninit"

let var_ghost_matrix2_ro_focus = toplevel_var "matrix2_ro_focus"

let var_ghost_in_range_extend = toplevel_var "in_range_extend"

(* let var_ghost_subrange_to_group_in_range = toplevel_var "subrange_to_group_in_range" *)

let var_ghost_assume = toplevel_var "assume"

let assume (f: formula): trm =
  ghost (ghost_call var_ghost_assume ["P", f])

let var_ghost_to_prove = toplevel_var "to_prove"

let to_prove (f: formula): trm =
  ghost (ghost_call var_ghost_to_prove ["P", f])

(*****************************************************************************)
(* Contracts and annotations *)

let delete_annots_on
  ?(delete_contracts = true)
  ?(delete_ghost = true)
  ?(on_delete_to_prove: (formula -> unit) option)
  (t : trm) : trm =
  let rec aux t =
    let test_is_ghost t =
      if (trm_has_attribute GhostInstr t) then begin
        begin match on_delete_to_prove with
        | Some on_delete_to_prove ->
          Pattern.pattern_match t [
            Pattern.(trm_apps (trm_specific_var var_ghost_to_prove) nil (pair __ !__ ^:: nil) __) (fun prop_to_prove () ->
              on_delete_to_prove prop_to_prove
            );
            Pattern.__ (fun () -> ())
          ]
        | None -> ()
        end;
        true
      end else false
    in
    let t =
      if delete_ghost &&
        ((test_is_ghost t) ||
        (Option.is_some (ghost_begin_inv t)) ||
        (Option.is_some (ghost_end_inv t)))
      then Nobrace.trm_seq_nomarks []
      else t
    in
    let t =
      if not delete_contracts then t else
      begin match t.desc with
      | Trm_fun (args, ret_ty, body, contract) ->
        trm_replace (Trm_fun (args, ret_ty, body, FunSpecUnknown)) t
      | Trm_for (loop_range, body, contract) ->
        trm_replace (Trm_for (loop_range, body, empty_loop_contract)) t
      | Trm_for_c (start, cond, stop, body, contract) ->
        trm_replace (Trm_for_c (start, cond, stop, body, None)) t
      | _ -> t
      end in
    trm_map aux t
  in
  aux t
