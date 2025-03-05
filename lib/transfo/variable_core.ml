open Prelude

(** [fold_decl_at fold_at index t]: fold the targeted variable definition,
      [fold_at] - target where folding should be performed, if left empty
                  then folding is applied everywhere,
      [index] - the index of the targeted definition on its surroudinig sequence,
      [t] - ast of the sequence that contains the targeted definition. *)
let fold_decl_at (fold_at : target) (index : int) (t : trm) : trm =
  let error = "Variable_core.fold_decl_at: expected a sequence" in
  let tl, result = trm_inv ~error trm_seq_inv t in
  let binding = ref None in
  let f_update (t : trm) : trm =
    begin match t.desc with
    | Trm_let ((x, tx), dx) -> binding := Some (x, dx)
    | _ -> trm_fail t "Variable_core.fold_decl_at: expected a variable declaration"
    end;
    t
  in
  let f_update_further (t : trm) : trm =
    let x, dx = Option.get !binding in
    Internal.change_trm ~change_at:[fold_at] dx (trm_var x) t
  in
  let new_tl = Mlist.update_at_index_and_fix_beyond index f_update f_update_further tl in
  trm_seq ~annot:t.annot ?result new_tl

(** [rename_at new_name index t]: renames all the occurences of the variable declared on the targeted declaration,
      [new_name] - the new name for the targeted variable,
      [index] - index of the targeted declaration inside its surrounding sequence,
      [t] - ast of the sequence that contains the targeted declaration. *)
let rename_at (new_name : string) (index : int) (t : trm) : trm =
  let error = "Variable_core.rename_at: expected a target inside a sequence." in
  let tl, _ = trm_inv ~error trm_seq_inv t in
  let old_var, _, _ = trm_inv ~error:"Variable_core.rename_at: expected a target to a variable declaration." trm_let_inv (Mlist.nth tl index) in
  let new_var = if is_toplevel_var old_var
    then toplevel_var ~namespaces:old_var.namespaces new_name
    else { old_var with name = new_name }
  in
  trm_rename_vars (fun () var -> if var_eq var old_var then new_var else var) () t

(** [init_detach_on t]: detaches the targeted variable declaration,
      [t] - ast of the targeted variable declaration. *)
let init_detach_on (t : trm) : trm =
  let error = "Variable_core.init_detach_on: variable could not be matched, make sure your path is correct." in
  let (x, tx, init) = trm_inv ~error trm_let_inv t in
  let init = match trm_ref_inv_init init with
    | Some init -> init
    | _ -> trm_fail t "init_detach_on: can't detach an uninitialized or constant declaration"
  in
  let var_decl = trm_let_mut_uninit ~annot:t.annot (x, Option.unsome ~error:"expected init type" init.typ) in
  (* Check if variable was declared as a reference *)
  let var_assgn = trm_set (trm_var ~typ:tx x) init in
  trm_seq_nobrace_nomarks [var_decl; var_assgn]

(** [Init_attach_no_occurrences]: raised by [init_attach_at]. *)
exception Init_attach_no_occurrences

(** [Init_attach_occurrence_below_control]: raised by [init_attach_at]. *)
exception Init_attach_occurrence_below_control


(** [init_attach_at t]: attaches a variable declaration to its succeeding write operation,
      [index] - index of the targeted instruction inside its surrounding sequence,
      [t] - ast of the surrounding sequence of the variable declaration.
 *)
let init_attach_at (index : int) (t : trm) : trm =
  let error = "expected the surrounding sequence." in
  let instrs, result = trm_inv ~error trm_seq_inv t in
  let lfront, decl, lback  = Mlist.get_item_and_its_relatives index instrs in
  let (x, tx) = Pattern.pattern_match decl [
    Pattern.(trm_let !__ __ (trm_ref_uninit !__)) (fun x tx () -> (x, tx));
    Pattern.__ (fun () -> trm_fail decl "expected a mutable variable declaration")
  ] in
  let _, next, lback = Mlist.get_item_and_its_relatives 0 lback in
  let init2 = Pattern.pattern_match next [
    Pattern.(trm_set (trm_var (eq x)) !__) (fun init2 () -> init2);
    Pattern.__ (fun () -> trm_fail next "expected a succeeding set on that variable")
  ] in
  let new_decl = trm_let_mut ~annot:decl.annot (x, tx) init2 in
  trm_seq_helper ~annot:t.annot ?result [TrmMlist lfront; Trm new_decl; TrmMlist lback]

(** [delocalize_at array_size ops index t]: see [Variable_basic.delocalize],
      [array_size] - size of the arrays to be declared inside the targeted sequence,
      [ops] - delocalize operation representing the unitary element used for initialization
             and the fold_lefting operation used for the reduction,
      [index] - the index for the two added loops,
      [t] - the ast of the sequence generated after applying the local_name transformation. *)
let delocalize_at (array_size : trm) (ops : local_ops) (index : string) (t : trm) : trm =
  let index = new_var index in
  let error = "Variable_core.delocalize_aux: expected the nobrace sequence." in
  let tl, result = trm_inv ~error trm_seq_inv t in
  (* Should we rule out sequences with result value ? *)
  if Mlist.length tl <> 3 then trm_fail t "delocalize_aux: the targeted sequence does not have the correct shape";
  let def = Mlist.nth tl 0 in
  let snd_instr = Mlist.nth tl 1 in
  begin match def.desc with
  | Trm_let ((x, tx), init) ->
    let local_var = x in
    let curr_var_trm = match trm_ref_inv_init init with
      | Some init1 -> init1
      | _ -> trm_fail def "delocalize_aux: couldn't get the value of the current variable " in
    let curr_var_trm = get_operation_arg curr_var_trm in
    let var_type = (get_inner_ptr_type tx) in
    let init_trm, op = begin match ops with
      | Local_arith (li, op) ->
          trm_lit li, (trm_compound_assign op
                              curr_var_trm
                              (trm_get (trm_array_access (trm_var_get ~typ:var_type local_var) (trm_var index))))
      | Local_obj (clear_f, transfer_f, _) ->
          trm_apps ~typ:typ_unit (trm_var clear_f) [],
          trm_apps ~typ:typ_unit (trm_var transfer_f)
            [trm_get curr_var_trm ;
            trm_get (trm_array_access (trm_var_get ~typ:var_type local_var) (trm_var index))]
    end in
    let new_first_trm = trm_seq_nobrace_nomarks [
        trm_let_mut_uninit (local_var, (typ_array var_type ~size:array_size));
        trm_set (trm_array_access (trm_var_get ~typ:var_type local_var) (trm_int 0)) (trm_get curr_var_trm);
        trm_copy (trm_for { index; start = trm_int 1; direction = DirUp; stop = array_size; step = trm_step_one () }
        (trm_seq_nomarks [trm_set (trm_array_access (trm_var_get ~typ:var_type local_var) (trm_var index)) init_trm]))]
        in
    let new_snd_instr = trm_subst_var local_var  (trm_array_access (trm_var_get ~typ:var_type local_var) (trm_apps (trm_var (name_to_var "ANY")) [array_size])) snd_instr  in
    let new_thrd_trm = trm_seq_nobrace_nomarks [
                    trm_set (curr_var_trm) (trm_get (trm_array_access (trm_var_get ~typ:var_type local_var) (trm_int 0)));
                    trm_for { index; start = trm_int 1; direction = DirUp; stop = array_size; step = trm_step_one () } (trm_seq_nomarks [op])
                    ] in
    let new_tl = (Mlist.of_list [new_first_trm; new_snd_instr; new_thrd_trm]) in
    { t with desc = Trm_seq (new_tl, result) }
    (* trm_seq ~annot:t.annot ?result (Mlist.of_list [new_first_trm; new_snd_instr; new_thrd_trm]) *)

  | _ -> trm_fail t "Variable_core.delocalize_aux: first instruction in the sequence should be the declaration of local variable"
  end


(** [insert_at index const name typ value t]: inserts a variable declaration on sequence [t],
      [index] - location where the declaration is going to be inserted,
      [const] - a flag on the mutability of the variable [name],
      [name] - name of the inserted variable,
      [typ] - the type of the inserted variable,
      [value] - the initial value of the inserted variable [name],
      [t] - ast of the sequence where the insertion is performed. *)
let insert_at (index : int) (const : bool) (name : string) (typ : typ) (value : trm option) (t : trm) : trm =
  let error = "Variable_core.insert_at: expected the sequence where the declaration is oing to be inserted" in
  let tl, result = trm_inv ~error trm_seq_inv t in
  let new_decl = match const, value with
    | true, Some value -> trm_let (new_var name, typ) value
    | true, None -> failwith "Variable_core.insert_at: cannot create a constant variable with no initial value"
    | false, Some value -> trm_let_mut (new_var name, typ) value
    | false, None -> trm_let_mut_uninit (new_var name, typ)
  in
  let new_tl = Mlist.insert_at index new_decl tl in
  trm_seq ~annot:t.annot ?result new_tl


(** [change_type_at new_type t]: changes the current type of the targeted variable,
      [new_type] - the new type replacing the current one entered as a string,
      [t] - ast of the sequence that contains the targeted declaration. *)
let change_type_at (new_type : string) (index : int) (t : trm) : trm =
  let new_type = typ_arbitrary new_type in
  match t.desc with
  | Trm_seq (tl, result) ->
    let f_update (t : trm) : trm =
      let error = "Variable_core.change_type_aux: expected a target to a variable declaration." in
      let (x, tx, init) = trm_inv ~error trm_let_inv t in
        Internal.change_typ (get_inner_ptr_type tx) new_type t
     in
    let f_update_further (t : trm) : trm =
      let dl = Mlist.nth tl index in
      let error = "Variable_core.change_type_aux: expected a target to a variable declaration." in
      let (x, tx, _) = trm_inv ~error trm_let_inv dl in
        Internal.change_typ (get_inner_ptr_type tx) new_type ~change_at:[[cVarId x]] t
      in
    let new_tl = Mlist.update_at_index_and_fix_beyond index f_update f_update_further tl in
    trm_seq ~annot:t.annot ?result new_tl
  | _ -> trm_fail t "Variable_core.change_type_aux: expected the surrounding sequence"

(** [bind_at index fresh_name const p_local t]: binds the variable [fresh_name] to the targeted trm,
      [mark_let] - an optional mark attached to the new binding instruction
      [mark_occ] - an optional mark attached to the occurrences of [fresh_name] that are inserted
      [my_mark] - a mark to be left on the bound term, inside the new let-binding definition
      [index] - index of the instruction containing the targeted function call,
      [fresh_name] - name of the variable which going to be binded to the function call,
      [const] - a flag for the mutability of the binded variable,
      [p_local] - the local path from the instruction containing the targeted node
                  to the targeted node,
      [t] - ast of the sequence containing the targeted node. *)
      (* LATER: cleanup this code, and pull out into auxiliary functions the tooling needed
         to handle arrays *)
let bind_at ?(mark_let: mark = no_mark) ?(mark_occ: mark = no_mark) ?(mark_body: mark = no_mark) (index : int) (fresh_name : string) ?(const : bool = true) ?(typ : typ option) (p_local : path) (t : trm) : trm =
  let tl, result = trm_inv ~error:"Variable_core.bind_aux: expected the surrounding sequence" trm_seq_inv t in
  let f_update (t : trm) : trm =
    let targeted_node = Path.resolve_path p_local t in
    let has_reference_type = if (Str.string_before fresh_name 1) = "&" then true else false in
    let fresh_name = if has_reference_type then (Str.string_after fresh_name 1) else fresh_name in
    let node_type = match targeted_node.typ with
      | Some ty -> ty
      | _ -> typ_auto
    in
    let fresh_var = new_var fresh_name in
    let replacement_node = trm_add_mark mark_occ (
      trm_var_possibly_get ~const ~typ:node_type fresh_var) in
    let node_to_change =
      Path.apply_on_path (fun _tsub -> replacement_node) t p_local in
    let targeted_node = trm_add_mark mark_body targeted_node in
    let decl_to_insert =
      let node_type = match typ with | Some ty -> ty | _ -> node_type in
      if const
        then trm_let (fresh_var, node_type) targeted_node
        else trm_let_mut (fresh_var, node_type) targeted_node
    in
    let decl_to_insert = trm_add_mark mark_let decl_to_insert in
    trm_seq_nobrace_nomarks [decl_to_insert; node_to_change]
  in
  let new_tl = Mlist.update_nth index f_update tl in
  let r = trm_seq ~annot:t.annot ?result new_tl in
  r

(** [remove_get_operations_on_var x t]: removes one layer of get operations on variable [x].
     i.e. if [x] was a pointer to [v], [get x] becomes [v].
   *)
let remove_get_operations_on_var (x : var) (t : trm) : trm =
  (* returns (adress_became_value, new_term) *)
  let rec aux (t : trm) : bool * trm =
    let aux_unwrap (t : trm) : trm =
      let _, t' = aux t in t'
    in
    let fix_typ t =
      Option.bind t.typ typ_ptr_inv
    in
    match t.desc with
    | Trm_var y when y = x -> (true, { t with typ = fix_typ t })
    | Trm_apps (_, [t1], _, _) when is_get_operation t ->
      let r, t1' = aux t1 in
      (false, if r then t1' else trm_get ~annot:t.annot t1')
    | Trm_apps ({desc = Trm_prim (struct_typ, Prim_unop (Unop_struct_access f))}, [t1], _, _) ->
      let field_typ = Option.bind t.typ typ_ptr_inv in
      let r, t1' = aux t1 in
      if r then (true, trm_struct_get ?field_typ ~struct_typ ~annot:t.annot t1' f)
      else (false, trm_struct_access ?field_typ ~struct_typ ~annot:t.annot t1' f)
    | Trm_apps ({desc = Trm_prim (_typ, Prim_binop (Binop_array_access))}, [t1; t2], _, _) ->
      let elem_typ = Option.bind t.typ typ_ptr_inv in
      let r, t1' = aux t1 in
      let _, t2' = aux t2 in
      if r then (true, trm_array_get ?typ:elem_typ ~annot:t.annot t1' t2')
      else (false, trm_array_access ?elem_typ ~annot:t.annot t1' t2')
    | _ -> false, trm_map aux_unwrap t
  in
  snd (aux t)


(** [to_nonconst_at index t]: transforms a constant into a mutable variable.
      [index] - the index of the targeted declaration inside its surrounding sequence,
      [t] - ast of the sequence that contains the targeted declaration. *)
let to_nonconst_at (index : int) (t : trm) : trm =
  let tl, result = trm_inv ~error:"Variable_core.to_nonconst: expected the sequence that contains the targeted declaration" trm_seq_inv t in
  let lfront, dl, lback = Mlist.get_item_and_its_relatives index tl in
  let x, tx, init = trm_inv ~error:"Variable_core.to_nonconst: the main target should point to a variable declaration" trm_let_inv dl in
  match trm_ref_inv_init init with
  | Some _ -> t
  | None ->
    let init_type = get_inner_const_type tx in
    let new_dl = trm_pass_marks dl (trm_let_mut (x, init_type) init) in
    let new_lback = Mlist.map (trm_subst_var x (trm_var_get ~typ:init_type x)) lback in
    let result, res_let = match result with
      | Some r when var_eq r x ->
        let new_res = new_var "__res" in
        Some new_res, [trm_let (new_res, init_type) (trm_var_get ~typ:init_type x)]
      | _ -> result, []
    in
    trm_seq_helper ~annot:t.annot ?result [TrmMlist lfront; Trm new_dl; TrmMlist new_lback; TrmList res_let]

(** [to_const_at index t]: transform a mutable variable without explicit writes into a constant,
      [index] - the index of the targeted declaration inside its surrounding sequence,
      [t] - ast of the sequence that contains the targeted declaration. *)
let to_const_at (index : int) (t : trm) : trm =
  let tl, result = trm_inv ~error:"Variable_core.to_mut_aux: expected the sequence that contains the targeted declaration" trm_seq_inv t in
  let lfront, dl, lback = Mlist.get_item_and_its_relatives index tl in
  let x, tx, init = trm_inv ~error:"Variable_core.to_const: the main target should point to a variable declaration" trm_let_inv dl in
  match trm_ref_inv_init init with
  | None -> t
  | Some init_val ->
    (* Search if there are any write operations on variable x *)
    Mlist.iter (fun t1 ->
      begin match t1.desc with
      | Trm_apps (_, [ls; _rs], _, _) when is_set_operation t1 ->
        begin match ls.desc with
        | Trm_var y when y = x -> trm_fail ls "Variable_core.to_const: variables with one or more write operations can't be converted to immutable ones"
        | _ ->
          (* if contains_occurrence x ls
                    then trm_fail ls "Variable_core.to_const: struct instances with
                            one or more write operations can't be conveted to immutable ones."
                    else () *)
          ()
        end
      | _ -> ()
      end
    ) lback;
    (* replace all get(x) with x *)
    let init_type = Option.unsome ~error:"expected ptr type" (typ_ptr_inv tx) in
    let new_dl = trm_pass_marks dl (trm_let (x, init_type) init_val) in
    let new_lback = Mlist.map (fun t1 -> remove_get_operations_on_var x t1) lback in
    trm_seq_helper ~annot:t.annot ?result [TrmMlist lfront; Trm new_dl; TrmMlist new_lback]

(** [simpl_deref_on t]: checks if [t] is of the form *(&b) or *(&b),
    if that's the case then simplify that expression and return it,
       [indepth] - search indepth for the targeted expressions,
       [t] - trm that represents one of the epxressions *(&b) or &( *b). *)
let simpl_deref_on (indepth : bool) (t : trm) : trm =
  let aux = trm_simplify_addressof_and_get in
  if indepth then trm_map aux t else aux t

(** [ref_to_pointer_at index t]: transforms the targeted declaration from a reference to a poitner,
      [index] - index of that targeted declaration in its surrounding block,
      [t] - ast of the sequence that contains the targeted declaration. *)
let ref_to_pointer_at (index : int) (t : trm) : trm =
  let error = "Variable_core.ref_to_pointer_aux: expected the surrounding sequence of the targeted reference declaration." in
  let tl, result = trm_inv ~error trm_seq_inv t in
  let var_name = ref dummy_var in
  let var_typ = ref typ_auto in
  let f_update (t : trm) : trm =
    match t.desc with
    | Trm_let ((x, tx), init) when trm_has_cstyle Reference t ->
      var_name := x;
      let tx = get_inner_ptr_type tx in
      var_typ := tx;
      trm_let_mut (x, typ_ptr tx) init
    | _ -> trm_fail t "Variable_core.ref_to_pointer_aux: expected a target to a variable declaration"
    in
  let f_update_further (t : trm) : trm =
    trm_subst_var !var_name (trm_var_get ~typ:!var_typ !var_name) t in

  let new_tl = Mlist.update_at_index_and_fix_beyond index f_update f_update_further tl in
  trm_seq ~annot:t.annot ?result new_tl

(** [ref_to_var_on t]: converts a reference variable to a simple stack var variable
     [t] - ast of the refernce declaration *)
let ref_to_var_on (t : trm) : trm =
  match t.desc with
  | Trm_let ((x, tx), init) when trm_has_cstyle Reference t ->
    let t_annot = trm_rem_cstyle Reference t in
    (trm_let ~annot:t_annot.annot (x, tx) (trm_ref (get_inner_ptr_type tx) (trm_get init)))
  | _ -> trm_fail t "Variable_core.ref_to_var_aux: expected a target to a reference declaration"
