open Ast
open Trm
open Typ
open Contextualized_error
open Mark
open Matrix_trm

(** list of (offset, size) *)
type nd_tile = (trm * trm) list

(** list of (start, end) *)
type nd_range = (trm * trm) list

(* TODO?
(** [tile_none]: special tile value where the dimension should be kept fully *)
let tile_all: trm * trm = trm_int 1, trm_int 0

(** [tile_none]: special tile value where the dimension should be dropped *)
let tile_none: trm * trm = trm_int 0, trm_int 0
*)

let let_alloc ?(annot : trm_annot = trm_annot_default) ?(zero_init = false) (v : var) (ty : typ) (dims : trms) : trm =
  trm_let (v, typ_ptr ty) (alloc ~zero_init ty dims)

let let_alloc_inv (t : trm) : (var * typ * trms * bool) option =
  Option.bind (trm_let_inv t) (fun (v, _, init) ->
  Option.bind (alloc_inv init) (fun (elem_t, dims, zeroinit) ->
    Some (v, elem_t, dims, zeroinit)
  ))

let let_alloc_uninit_inv (t : trm) : (var * typ * trms) option =
  Option.bind (trm_let_inv t) (fun (v, _, init) ->
  Option.bind (alloc_uninit_inv init) (fun (elem_t, dims) ->
    Some (v, elem_t, dims)
  ))

let mmemcpy_var typ =
  toplevel_var (sprintf "MMEMCPY_%s" (Ast_to_c.typ_to_string typ))

(** [memcpy dest d_offset d_dims src s_offset s_dims copy_dims elem_size] uses a series
    of [matrixN_contiguous] and [mindexN_contiguous] ghosts to issue a [MMEMCPY] from
    matrix [dest] at [d_offset] to matrix [src] at [s_offset].

    Preconditions:
    - [dest] has dims [d_dims] and [(len d_offset) <= (len d_dims)]
    - [src] has dims [s_dims] and [(len s_offset) <= (len s_dims)]
    - [(len d_dims) - (len d_offset) = (len s_dims) - (len s_offset) = (len copy_dims)]
    - [take_last (len copy_dims) d_dims = take_last (len copy_dims) s_dims]
  *)
let memcpy ~(typ: typ)
  (dest : trm) (d_offset : trm list) (d_dims : trm list)
   (src : trm) (s_offset : trm list) (s_dims : trm list)
  (copy_dims : trm list) : trm =
  let dol = List.length d_offset in
  let ddl = List.length d_dims in
  let sol = List.length s_offset in
  let sdl = List.length s_dims in
  let cdl = List.length copy_dims in
  assert (dol <= ddl && sol <= sdl);
  assert (ddl - dol == cdl && sdl - sol == cdl);
  if copy_dims = [] then Nobrace.trm_seq_nomarks [] else

  let compute_flat_offset offset offset_length dims =
    (* N1 ... NO ... NM
       o1 ... oO
       o1*N2*...*NM + ... + oO*N{O-1}*...*NM
      *)
    (* if offset = [] then trm_int 0 else *)
    let (sum_terms, _) = List.fold_left (fun (sum_terms, multipliers) dim_offset ->
      let multipliers = List.drop_one_or_else (fun () -> []) multipliers in
      let sum_term = List.fold_left trm_mul_int dim_offset multipliers in
      let sum_terms = sum_terms @ [sum_term] in
      (sum_terms, multipliers)
    ) ([], dims) offset in
    List.fold_right trm_add_int sum_terms (trm_int 0)
  in
  let d_flat_offset = compute_flat_offset d_offset dol d_dims in
  let s_flat_offset = compute_flat_offset s_offset sol s_dims in
  let flat_elems = List.reduce_left trm_mul_int copy_dims in
  let t = trm_apps (trm_var (mmemcpy_var typ))
    [dest; d_flat_offset; src; s_flat_offset; flat_elems] in

  let scoped_mindex_contiguous_write mat_trm dims offset t =
    if dims < 2 then t else
    let a = Matrix_trm.mindex_contiguous_ghost_call dims "_uninit" ["matrix", mat_trm] in
    let b = Matrix_trm.mindex_contiguous_rev_ghost_call dims "" ["matrix", mat_trm] in
    Nobrace.trm_seq_nomarks Resource_trm.[ghost a; t; ghost b]
  in
  let scoped_mindex_contiguous_read mat_trm dims offset t =
    if dims < 2 then t else
    Resource_trm.ghost_scope (Matrix_trm.mindex_contiguous_ghost_call
     dims "_ro" ["matrix", mat_trm]
    ) t
  in
  let t = scoped_mindex_contiguous_write dest ddl d_offset t in
  let t = scoped_mindex_contiguous_read src sdl s_offset t in
  (* TODO: call matrixN_contiguous on copy_dims *)
  t

(*let memcpy_inv (t : trm) : (trm * trm * trm * trm * trm) option =
  Pattern.pattern_match_opt t [
    Pattern.(trm_apps (trm_specific_var mmemcpy_var) (!__ ^:: !__ ^:: !__ ^:: !__ ^:: !__ ^:: nil) __) (fun dest d_flat_offset src s_flat_offset flat_elems () ->
      (dest, d_flat_offset, src, s_flat_offset, flat_elems)
    )
  ]*)

(** [map_all_accesses v dims map_indices mark t] maps all accesses to [v] in [t],
    using the [map_access] function.

    Fails if [v] occurs in a sub-term that is not an access to [v], as this could mean some
    accesses are hidden (e.g. behind a function call).

    - the dimensions and type of the matrix [v] are stored in [ret_dims_and_typ] if provided.
    *)
let map_all_accesses (v : var) ?(ret_dims_and_typ : (trms * typ) option ref option)
  (map_access : trms -> trms -> trm) (t : trm) : trm =
  let rec aux (t : trm) : trm =
    match access_inv t with
    | Some (f, dims, indices) ->
      begin match trm_var_inv f with
      | Some x when var_eq x v ->
        Option.iter (fun rdt ->
          if Option.is_none !rdt then begin
            let typ = Option.get (typ_ptr_inv (Option.get f.typ)) in
            rdt := Some (dims, typ);
          end;
        ) ret_dims_and_typ;
        map_access dims indices
      | _ -> trm_map aux t
      end
    | None ->
      begin match trm_var_inv t with
      | Some x when x = v ->
        trm_fail t "map_all_accesses: variable access is not covered"
      | _ -> trm_map aux t
      end
  in
  aux t

(** [replace_all_accesses prev_v v dims map_indices mark t] replaces all accesses to [prev_v]
    in [t] with accesses to [v], using new [dims] and changing indices with [map_indices].
    *)
let replace_all_accesses (prev_v : var) (v : var) (dims : trm list)
  ?(ret_dims_and_typ : (trms * typ) option ref option)
  (map_indices : (trm -> trm) list) (mark : mark) (t : trm) : trm =
  map_all_accesses prev_v ?ret_dims_and_typ (fun prev_dims prev_indices ->
    let indices = List.map2 (fun m i -> m i) map_indices prev_indices in
    let typ = Option.bind ret_dims_and_typ (fun dt ->
      (* best effort type recovery .. *)
      Option.map (fun (d, t) -> t) !dt
    ) in
    trm_add_mark mark (access (trm_var ?typ v) dims indices)
  ) t

(** [pointwise_fors ?reads ?writes ?modifies ranges body] creates nested loops
  with [ranges] over the main body [body].
  The body has the given [reads], [writes], and [preserves].
  Each loop contract adds a layer of pointwise Group resources.
  *)
let pointwise_fors
  ?(reads: formula list = [])
  ?(writes: formula list = [])
  ?(preserves: formula list = [])
  (ranges : loop_range list) (body : trm) : trm =
  let (t, _, _, _) = List.fold_right (fun range (t, reads, writes, preserves) ->
    let push_clauses clause formulas contract =
      List.fold_left (fun contract formula ->
        let res = (Resource_formula.new_anon_hyp (), formula) in
        Resource_contract.push_loop_contract_clause clause res contract
      ) contract formulas
    in
    let contract = empty_strict_loop_contract
      |> push_clauses (Exclusive Reads) reads
      |> push_clauses (Exclusive Writes) writes
      |> push_clauses (Exclusive Preserves) preserves
    in
    let t' = trm_for ~contract range (if (is_trm_seq t) then t else trm_seq_nomarks [t]) in
    let reads' = List.map (Resource_formula.formula_group_range range) reads in
    let writes' = List.map (Resource_formula.formula_group_range range) writes in
    let preserves' = List.map (Resource_formula.formula_group_range range) preserves in
    (t', reads', writes', preserves')
  ) ranges (body, reads, writes, preserves)
  in
  t


(****************************************************************************************************)
(*                        Core transformations on C matrices                                        *)
(****************************************************************************************************)

(** [reorder_dims_aux order t]: reorders the dimensions in a call to MSIZE or MINDEX,
      [order] - a list of indices based on which the elements in dims should be ordered,
      [t] - ast of the call to MSIZE or MINDEX. *)
let reorder_dims_aux (rotate_n : int) (order : int list) (t : trm) : trm =
  let dims, indices =
    match mindex_inv t with
    | Some (dims, indices) -> dims, Some indices
    | None -> match msize_inv t with
      | Some dims -> dims, None
      | None -> trm_fail t "Matrix_core.reorder_dims_aux: expected a function call to MSIZE or MINDEX"
  in
  let nb = List.length dims in
  let order = if rotate_n <> 0
    then let id_perm = List.range 0 (nb - 1) in
          List.rotate rotate_n id_perm
    else
      begin match order with
    | [] -> trm_fail t "Matrix_core.reorder_dims_aux: permuation order of indices and dims should be given or ~rotate_n argument should be used"
    | _ -> order
    end in
  begin try List.check_permutation nb order with | List.Invalid_permutation -> trm_fail t "Matrix_core.order is not a permutation of indices" end;
  let reordered_dims = List.reorder order dims in
  match indices with
  | Some indices ->
    let reordered_indices = List.reorder order indices in
    mindex reordered_dims reordered_indices
  | None ->
    msize reordered_dims


(** [insert_alloc_dim_aux new_dim t]: adds a new dimension at the beginning of the list of dimension,
     [new_dim]: the new dimension which is going to be inserted into the list of dims in an allocation,
     [t]: ast of the allocation. *)
let insert_alloc_dim_aux ?(last : bool = false) (new_dim : trm) (t : trm) : trm =
  match alloc_inv t with
  | Some (ty, dims, zero_init) ->
    let new_dims = if last then dims @ [new_dim] else new_dim :: dims in
    alloc ~zero_init ty new_dims
  | None -> trm_fail t "Matrix_core.insert_alloc_dim_aux: expected a matrix allocation"

(** [insert_access_dim_index_aux new_dim new_index t]: add a new dimension at the beginning of the list of dimension
     and add a new index at the begining of the list of indices in the call to MINDEX inside the
     targeted array access.
      [new_dim]: the new dimension which is goin to be inserted into the list of dims in call to MINDEX,
      [new_index]: the new index which is goin to be inserted into the list of indices in call to MINDEX,
      [t]: ast of the array_access with the updated list of args in the call to MINDEX. *)
let insert_access_dim_index_aux ?(last : bool = false) (new_dim : trm) (new_index : trm) (t : trm) : trm =
  match access_inv t with
  | Some (base, dims, indices) ->
    let new_dims = if last then dims @ [new_dim] else new_dim :: dims in
    let new_indices = if last then indices @ [new_index] else new_index :: indices in
    access base new_dims new_indices
  | None -> trm_fail t "Matrix_core.insert_access_dim_index_aux: expected an array access "

(** [local_name_aux mark var local_var malloc_trms var_type t] insert a local matrix declaration with name [local_var] and copy the content
      from the matrix [var] to [local_var] and replace all the accesses of that matrix inside the targeted insturction [t].
      [mark] - an optional mark at the final generated sequence,
      [var] - the name of the current matrix used in instruction [t],
      [new_var] - the name of the local matrix which replaces all the current accesses of [var],
      [t] - ast of thee instuction which contains accesses to [var]. *)
(* TODO: superseded by tile version *)
let local_name_aux (mark : mark)
  (var : var) (local_var : string)
  (dims : trms) (elem_type : typ) (indices : string list)
  (local_ops : local_ops) (t : trm) : trm =
  let local_var = new_var local_var in
  let fst_instr = let_alloc local_var elem_type dims in
  let indices_list = begin match indices with
  | [] -> List.mapi (fun i _ -> "i" ^ (string_of_int (i + 1))) dims | _ as l -> l  end in
  let indices_list = List.map new_var indices_list in
  let indices = List.map (fun ind -> trm_var ind) indices_list in
  let nested_loop_range = List.map2 (fun dim ind-> { index = ind; start = (trm_int 0); direction = DirUp; stop = dim; step = trm_step_one () }) dims indices_list in
  begin match local_ops with
    | Local_arith _ ->
      let write_on_local_var =
        trm_set (access (trm_var local_var) dims indices) (trm_get (access (trm_var var) dims indices)) in
      let write_on_var =
        trm_set (access (trm_var var) dims indices) (trm_get (access (trm_var local_var) dims indices)) in
      let snd_instr = trm_copy (trm_fors nested_loop_range write_on_local_var) in
      let new_t = trm_subst_var var (trm_var local_var) t in
      let thrd_instr = trm_copy (trm_fors nested_loop_range write_on_var) in
      let last_instr = free (trm_var local_var) in
      let final_trm = Nobrace.trm_seq_nomarks [fst_instr; snd_instr; new_t; thrd_instr; last_instr] in
      trm_add_mark mark final_trm
    | Local_obj (init, swap, free_fn) ->
      let write_on_local_var =
        trm_apps (trm_var init)  [access (trm_var local_var) dims indices] in
      let write_on_var =
        trm_apps (trm_var swap) [access (trm_var var) dims indices; access (trm_var local_var) dims indices] in
      let free_local_var =
        trm_apps (trm_var free_fn)  [access (trm_var local_var) dims indices] in
      let snd_instr = trm_copy (trm_fors nested_loop_range write_on_local_var) in
      let new_t = trm_subst_var var (trm_var local_var) t in
      let thrd_instr = trm_copy (trm_fors nested_loop_range write_on_var) in
      let frth_instr = trm_copy (trm_fors nested_loop_range free_local_var) in
      let last_instr = free (trm_var local_var) in
      let final_trm = Nobrace.trm_seq_nomarks [fst_instr; snd_instr; new_t; thrd_instr; frth_instr; last_instr] in
      trm_add_mark mark final_trm
    end
