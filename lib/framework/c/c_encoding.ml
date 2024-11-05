open Ast
open Trm
open Typ
open Contextualized_error

type style = {
  typing : Style.typing_style;
  cstyle : Ast_to_c.style;
}

let style_of_output_style (style : Style.output_style) : style =
  match style.print with
  | Lang_C s -> { typing = style.typing; cstyle = s }
  | _ -> { typing = style.typing; cstyle = Ast_to_c.default_style () }

let default_style () : style =
  style_of_output_style (Style.default_style ())

let debug = false

let debug_before_after_trm (msg : string) (f : trm -> trm) : trm -> trm =
  if debug then (fun t ->
    File.put_contents (sprintf "/tmp/%s_before.txt" msg) (Ast_to_text.ast_to_string t);
    let t2 = f t in
    File.put_contents (sprintf "/tmp/%s_after.txt" msg) (Ast_to_text.ast_to_string t2);
    t2
  ) else f

let debug_current_stage (msg: string) : unit =
  if debug then Tools.debug "%s" msg

(*

  t[i]  =  get(array_access(t,i))  = array_read(t,i)
       // array_read_inv also
       // array_access(t,i) corresponds to the C code t+i, which is the same as (( void* )t)+i*(sizeof(typeof(t[0]))

  t->f  =  get(struct_access(t,f)) = struct_read(t,f)
       // struct_access(t,f)  corresponds to the C code for   t + offset(f)

  ( *t ).f  =  t->f

  t.f  where t is not a get(.)    -> struct_get(t,"f")

   Recall: struct_get(t,f)  means  trm_apps (Prim_unop (unop_struct_get "f")) [t] *)

(** [mutability]: type for the mutability of the variable *)
type mutability =
  | Var_immutable (* const variables *)
  | Var_mutable   (* non-const stack-allocated variable. *)

(** [env]: a map for storing all the variables as keys, and their mutability as values *)
type env = mutability Var_map.t

(** [env_empty]: empty environment *)
let env_empty =
  Var_map.empty

(** [get_mutability env x]: gets the mutability of variable [x]
   Note: Functions that come from an external library are set to immutable by default *)
let get_mutability (env : env) (x : var) : mutability =
  match Var_map.find_opt x env with
  | Some m -> m
  | _ -> Var_immutable

(** [is_var_mutable env x]: checks if variable [x] is mutable or not *)
let is_var_mutable (env : env) (x : var) : bool =
  get_mutability env x = Var_mutable

(** [env_extend env e mutability]: adds variable [e] into environment [env] *)
let env_extend (env : env) (e : var) (mutability : mutability) : env =
  Var_map.add e mutability env

(** [add_var env x xm]: adds variable [x] into environemnt [env] with value [xm] *)
let add_var (env : env ref) (x : var) (xm : mutability) : unit =
  env := env_extend !env x xm

(** [trm_address_of t]: adds the "&" operator before [t]
    Note: if for example t = *a then [trm_address_of t] = &( *a) = a *)
let trm_address_of (t : trm) : trm =
  let u = trm_address_of t in
  trm_simplify_addressof_and_get u

(** [trm_get t]: adds the "*" operator before [t]
    Note: if for example t = &a then [trm_get t] = *( &a) = a *)
let trm_get ?(typ: typ option) (t : trm) : trm =
  let u = trm_get ?typ t in
  trm_simplify_addressof_and_get u

(** [onscope env t f]: applies function [f] on [t] without loosing [env]
   Note: This function is used for keeping track of opened scopes *)
let onscope (env : env ref) (t : trm) (f : trm -> trm) : trm =
    let saved_env = !env in
    let res = f t in
    env := saved_env;
    res

(** [create_env]: creates an empty environment *)
let create_env () = ref env_empty


(** [stackvar_elim t]: applies the following encodings
    - [int a = 5] with [int* a = ref int(5)]
    - a variable occurrence [a] becomes [* a]
    - [const int c = 5] becomes [int c = 5]
    - simplify patterns of the form [&*p] and [*&p] into [p].
    - [int& b = a] becomes [<annotation:reference> int* b = &*a] which simplifies to [<annot..>int* b = a]
    - [int& x = t[i]] becomes [<annotation:reference> int* x = &(t[i])] if t has type [int* const].
    - More complicated example: [int a = 5; int* b = &a] becomes [int* a = ref int(5); int** b = ref int*(a);]
    TODO: specify and improve support for arrays

   Note: "reference" annotation is added to allow decoding *)
 (* TODO: properly deal with const/mut array allocations on stack using Prim_ref_array *)
let stackvar_elim (t : trm) : trm =
  debug_current_stage "stackvar_elim";
  let env = create_env () in
  let extract_constness (ty: typ): typ * mutability =
    Pattern.pattern_match ty [
      Pattern.(typ_const !__) (fun ty () -> ty, Var_immutable);
      Pattern.(typ_array (typ_const !__) !__) (fun ty size () -> typ_array ?size ty, Var_immutable);
      Pattern.(typ_fun __ __) (fun () -> ty, Var_immutable);
      Pattern.__ (fun () -> ty, Var_mutable)
    ]
  in
  let rec aux (t : trm) : trm =
    let t = match t.desc with
    | Trm_var x ->
      if is_var_mutable !env x
        then trm_like ~old:t (trm_get ?typ:t.typ (trm_var ?typ:(Option.map typ_ptr t.typ) x))
        else t
    | Trm_let ((x, ty), tbody) ->
      (* is the type of x (or elements of x in case it is a fixed-size array) a const type? *)
      let ty, xm = extract_constness ty in
      add_var env x xm; (* Note: the onscope function will take care to remove this *)
      (* is the type of x a reference type? *)
      begin match typ_ref_inv ty with
      | Some ty1 ->
        begin match xm with
        | Var_immutable -> trm_fail t "C_encoding.stackvar_elim: unsupported references on const variables"
        | _ ->
          (* generate a pointer type, with suitable annotations *)
          trm_add_cstyle Reference (trm_replace (Trm_let ((x, typ_ptr ty1), trm_address_of (aux tbody))) t)
        end
      | None ->
        begin match xm with
        | Var_mutable ->
          (* TODO: document the case that corresponds to Constructed_init *)
          let new_body = if trm_has_cstyle Constructed_init tbody then aux tbody else trm_ref ty (aux tbody) in
          trm_replace (Trm_let ((x, typ_ptr ty), new_body)) t
        | Var_immutable ->
          let new_body = aux tbody in
          trm_replace (Trm_let ((x, ty), new_body)) t
        end
      end
    | Trm_let_mult bs ->
      let bs = List.map (fun ((x, ty), tbody) ->
          let ty, xm = extract_constness ty in
          add_var env x xm;
          match xm with
          | Var_immutable -> ((x, ty), aux tbody)
          | Var_mutable -> ((x, typ_ptr ty), trm_ref ty (aux tbody))
        ) bs
      in
      trm_replace (Trm_let_mult bs) t
    | Trm_seq (_, result) when not (trm_is_nobrace_seq t) ->
      onscope env t (fun t ->
        let t = trm_map aux t in
        match result with
        | Some r when is_var_mutable !env r -> trm_fail t "C_encoding.stackvar_elim: the result of a sequence cannot be a mutable variable"
        | _ -> t
      )
    | Trm_for (range, _, _) ->
        onscope env t (fun t -> add_var env range.index Var_immutable; trm_map aux t)
    | Trm_for_c _ ->
        onscope env t (fun t -> trm_map aux t)
    | _ -> trm_map aux t
    in
    let t = trm_simplify_addressof_and_get t in
    let ty = Option.map (fun ty -> fst (extract_constness ty)) t.typ in
    { t with typ = ty }
   in
   debug_before_after_trm "stackvar_elim" aux t


(** [stackvar_intro t]: is the inverse of [stackvar_elim], hence it applies the following decodings:
     - [int *a = ref int(5)] with [int a = 5]
     - [const int c = 5] remains unchanged
     - [<annotation:reference> int* b = a] becomes [int& b = *&(a)], which simplifies as [int& b = a]
        where &a is obtained after translating [a]
     - [<annotation:reference> int* x = &t[i]] becomes [int& x = *(&t[i])], where t has type [const int*]
       which simplifies to x = t[i]
     - [x] where [x] is mutable becomes [&x] *)
 (* TODO: some marks are lost in the printing, and this needs to be fixed,
    typically [*x] in the optitrust ast is printed as [x], and if the star operation
    was carrying a mark, then it is currently not displayed! *)
let stackvar_intro (t : trm) : trm =
  debug_current_stage "stackvar_intro";
  let env = create_env () in
  let add_const (ty: typ) : typ =
    Pattern.pattern_match ty [
      Pattern.(typ_array !__ !__) (fun ty size () -> typ_array ?size (typ_const ty));
      Pattern.__ (fun () -> typ_const ty)
    ]
  in
  let rec aux (t : trm) : trm =
    trm_simplify_addressof_and_get
    begin match t.desc with
    | Trm_var x ->
      if is_var_mutable !env x
        then trm_address_of t
        else t
    | Trm_let ((x, tx), tbody) ->
      begin match typ_ptr_inv tx, trm_ref_inv tbody with
      | _, Some (tx1, tbody1)  ->
        add_var env x Var_mutable;
        trm_replace (Trm_let ((x, tx1), aux tbody1)) t
      | Some tx1, None when trm_has_cstyle Reference t ->
        add_var env x Var_mutable;
        trm_rem_cstyle Reference { t with desc = Trm_let ((x, typ_ref tx1), trm_get (aux tbody))}
      | Some tx1, None when trm_has_cstyle Constructed_init tbody ->
        add_var env x Var_mutable;
        trm_replace (Trm_let ((x, tx1), aux tbody)) t
      | _ ->
        add_var env x Var_immutable;
        trm_replace (Trm_let ((x, add_const tx), aux tbody)) t
      end
    | Trm_let_mult bs ->
      (* FIXME: Is it possible to handle C++ references and Constructed_init in let_mult ? *)
      let bs = List.map (fun ((x, tx), tbody) ->
        match typ_ptr_inv tx, trm_ref_inv tbody with
        | Some tx1, Some (_, tbody1)  ->
          add_var env x Var_mutable;
          ((x, tx1), aux tbody1)
        | _ ->
          add_var env x Var_immutable;
          ((x, add_const tx), aux tbody)
      ) bs in
      trm_replace (Trm_let_mult bs) t
    | Trm_seq _ when not (trm_is_nobrace_seq t) ->
      onscope env t (trm_map aux)
    | Trm_for (range, _, _) ->
      onscope env t (fun t -> begin add_var env range.index Var_immutable; trm_map aux t end)
    | Trm_for_c _ -> onscope env t (fun t -> trm_map aux t)
    | Trm_apps ({desc = Trm_prim (_, Prim_unop Unop_get);_}, [{desc = Trm_var x; _} as t1], _) when is_var_mutable !env x  -> t1
    | _ -> trm_map aux t
    end in
   aux t


(** [caddress_elim t]: applies the following encodings
     - [get(t).f] becomes get(t + offset(f))
     - [t.f] becomes t + offset(f) -- nothing to do in the code of the translation
     - [get(t)[i] ] becomes [get (t + i)]
     - [t[i]] becomes [t + i] -- nothing to do in the code of the translation
     Note: [t + i] is represented in OptiTrust as [Trm_apps (Trm_prim (Prim_array_access, [t; i]))]
           [t + offset(f)] is represented in OptiTrust as [Trm_apps (Trm_prim (Prim_struct_access "f"),[t])] *)
 (* TODO: properly deal with const/mut array allocations on stack using Prim_ref_array *)
let caddress_elim (t : trm) : trm =
  debug_current_stage "caddress_elim";
  let rec aux t =
    trm_simplify_addressof_and_get
      (Pattern.pattern_match t [
        Pattern.(trm_struct_get !__ !__) (fun t1 field () ->
          let field_typ = t.typ in
          let u1 = aux t1 in
          match trm_get_inv u1 with
          | Some base ->
            (* struct_get (get(t1), f) is encoded as get(struct_access(t1,f)) where get is a hidden '*' operator,
                in terms of C syntax: ( *t).f is compiled into *(t + offset(f)) *)
            if trm_has_cstyle No_struct_get_arrow t then
              trm_like ~old:(trm_rem_cstyle No_struct_get_arrow t) (trm_get (trm_add_cstyle No_struct_get_arrow (trm_struct_access ?loc:t.loc ?field_typ base field)))
            else
              trm_like ~old:t (trm_get (trm_struct_access ?loc:t.loc ?field_typ base field))
          | None -> trm_like ~old:t (trm_struct_get ?loc:t.loc ?field_typ u1 field)
        );
        Pattern.(trm_array_get !__ !__) (fun t1 t2 () ->
            let u1 = aux t1 in
            let u2 = aux t2 in
            trm_like ~old:t (trm_get (trm_array_access ?loc:t.loc u1 u2))
        );
        Pattern.__ (fun () -> trm_map aux t)
      ])
  in
  debug_before_after_trm "caddress_elim" aux t

(** [is_access t]: checks if trm [t] is a struct access or an array access *)
let is_access (t : trm) : bool =
  match t.desc with
  | Trm_apps (tprim, _, _) ->
    begin match trm_prim_inv tprim with
    | Some (_, Prim_unop (Unop_struct_access _) | (_, Prim_binop (Binop_array_access))) -> true
    | _ -> false
    end
  | _ -> false

(** [caddress_intro_aux t]: is the inverse of [caddress_elim], hence if applies the following decodings:
     - [get(t + offset(f))] becomes [get(t).f]
     - [t + offset(f)] becomes [t.f]
     - [get (t + i)] becomes [get(t)[i]]
     - [t + i] becomes [t[i]]

     Note: [t + i] is represented in OptiTrust as [Trm_apps (Trm_prim (Prim_array_access, [t; i]))]
           [t + offset(f)] is represented in OptiTrust as [Trm_apps (Trm_prim (Prim_struct_access "f"),[ŧ])] *)
let caddress_intro_aux (t : trm) : trm =
  let rec aux t = (* recursive calls for rvalues *)
    trm_simplify_addressof_and_get
      (if is_access t then
        (* [access(..)] becomes [& ...] *)
        trm_address_of (access t)
      else trm_map aux t)
  and access t =  (* recursive calls for lvalues *)
    trm_simplify_addressof_and_get (* Note: might not be needed *)
      (Pattern.pattern_match t [
        Pattern.(trm_struct_access !__ !__) (fun t1 f () ->
          (* struct_access (f, t1) is reverted to struct_get (f, access t1) *)
          let u1 = access t1 in
          trm_like ~old:t (trm_struct_get u1 f)
        );
        Pattern.(trm_array_access !__ !__) (fun t1 t2 () ->
          (* array_access (t1, t2) is reverted to array_get (aux t1, aux t2) *)
          let u1 = aux t1 in
          let u2 = aux t2 in
          trm_like ~old:t (trm_array_get u1 u2)
        );
        Pattern.__ (fun () -> trm_get (aux t))
      ])
  in
  aux t

let caddress_intro =
  debug_current_stage "caddress_intro";
  caddress_intro_aux

(** [expr_in_seq_elim t]: updates [t] in such a way that all instructions appearing in sequences
   have type [unit] by inserting calls to [ignore] whenever necessary.
   This might not be the case when ignoring the result of an effectful expression.
   For example [x++;] is transformed into [ignore(x++)]. *)
let rec expr_in_seq_elim (t : trm) : trm =
  match trm_seq_inv t with
  | Some (ts, result) ->
    let ts = Mlist.map (fun u ->
        let u = expr_in_seq_elim u in
        match u.typ with
        | None -> u
        | Some typ when is_typ_unit typ -> u
        | Some _ -> trm_ignore ~annot:u.annot (trm_alter ~annot:trm_annot_default u)
      ) ts
    in
    trm_like ~old:t (trm_seq ?result ts)
  | None ->
    trm_map expr_in_seq_elim t

(** [expr_in_seq_intro t]: remove calls to [ignore]
   For example [ignore(x++);] is transformed into [x++]. *)
let rec expr_in_seq_intro (t : trm) : trm =
  Pattern.pattern_match t [
    Pattern.(trm_apps1 (trm_var (var_eq var_ignore)) !__) (fun expr () ->
      let annot = { expr.annot with
        trm_annot_stringrepr = Option.or_ t.annot.trm_annot_stringrepr expr.annot.trm_annot_stringrepr;
        trm_annot_marks = t.annot.trm_annot_marks @ expr.annot.trm_annot_marks;
        trm_annot_labels = t.annot.trm_annot_labels;
        trm_annot_pragma = t.annot.trm_annot_pragma @ expr.annot.trm_annot_pragma;
      } in
      expr_in_seq_intro (trm_alter ~annot expr)
    );
    Pattern.__ (fun () -> trm_map expr_in_seq_intro t)
  ]

let var_exact_div = toplevel_var "exact_div"

(** [infix_elim t]: encode unary and binary operators as Caml functions, for instance
    - [x++] becomes [++(&x)]
    - [x = y] becomes [=(&x, y)]
    - [x += y] becomes [+=(&x,y)]

  also, [exact_div(a, b)] becomes the primitive equivalent.
  *)
let infix_elim (t : trm) : trm =
  debug_current_stage "infix_elim";
  let rec aux (t : trm) : trm =
    match t.desc with
    (* Convert [ x += y ]  into [ (+=)(&x, y) ]
         represented as [Trm_apps (Prim_compound_assign_op binop) [trm_addressof(x),y]],
       likewise for [ x -= y]*)
    | Trm_apps ({desc = Trm_prim (_, Prim_compound_assign_op binop)} as op, [tl; tr], _) ->
      trm_alter ~typ:typ_unit ~desc:(Trm_apps(op, [trm_address_of tl; tr], [])) t
    (* Convert [ x++ ] into [ (++)(&x) ], where [(++)] is like the [incr] function in OCaml *)
    | Trm_apps ({desc = Trm_prim (_, Prim_unop unop); _} as op, [base], _) when is_unary_compound_assign unop ->
      trm_replace (Trm_apps(op, [trm_address_of base], [])) t
    (* Convert [ x = y ] into [ (=)(&x, y) ] *)
    | Trm_apps ({desc = Trm_prim (_, Prim_binop Binop_set)} as op, [tl; tr], _) ->
      trm_replace (Trm_apps (op, [trm_address_of tl; tr], [])) t
    (* Recognize exact_div primitive *)
    | Trm_apps ({desc = Trm_var v}, [tl; tr], _) when var_eq v var_exact_div ->
      (* FIXME: this should probably not happen here *)
      trm_replace (Trm_apps (trm_prim (Option.value ~default:typ_int tl.typ) (Prim_binop Binop_exact_div), [tl; tr], [])) t
    | _ -> trm_map aux t
  in
  debug_before_after_trm "infix_elim" aux t

(** [infix_intro t]: decodes unary and binary oeprators back to C++ unary and binary operators
    [++(&x)] becomes [++x]
    [+=(&x, y)] becomes [x += y]
    [=(&x, y)] becomes [x = y]*)
let infix_intro (t : trm) : trm =
  debug_current_stage "infix_intro";
  let rec aux (t : trm) : trm =
    match t.desc with
    | Trm_apps ({desc = Trm_prim (_, Prim_compound_assign_op binop)} as op, [tl; tr], _) ->
      trm_replace (Trm_apps(op, [trm_get tl; tr], [])) t
    | Trm_apps ({desc = Trm_prim (_, Prim_unop unop); _} as op, [base], _) when is_unary_compound_assign unop ->
      trm_replace (Trm_apps(op, [trm_get base], [])) t
    | Trm_apps ({desc = Trm_prim (_, Prim_binop Binop_set)} as op, [tl; tr], _) ->
      trm_replace (Trm_apps (op, [trm_get tl; tr], [])) t
    | _ -> trm_map aux t
  in aux t


(** [method_elim t]: encodes class method calls.  *)
let method_call_elim (t : trm) : trm =
  debug_current_stage "method_call_elim";
  let rec aux (t : trm) : trm =
    match t.desc with
    | Trm_apps ({desc = Trm_apps ({desc = Trm_prim (class_typ, Prim_unop (Unop_struct_get f))}, [base], _)} as _tr, args, ghost_args) ->
      (* LATER: Manage templated class *)
      let class_var =
        match typ_var_inv class_typ with
        | Some class_var -> class_var
        | None -> failwith "C_encoding.method_call_elim: unsupported base: %s\n" (Ast_to_text.ast_to_string base)
      in
      let class_var = remove_typ_namespace class_var in
      let namespaces = class_var.namespaces @ [class_var.name] in
      let t_var = trm_var (name_to_var ~namespaces f) in
      trm_add_cstyle Method_call (trm_apps ~ghost_args (t_var) ([trm_address_of base] @ args))
    | _ -> trm_map aux t
   in
   debug_before_after_trm "mcall" aux t

(** [method_call_intro t]: decodes class methods calls. *)
let method_call_intro (t : trm) : trm =
  debug_current_stage "method_call_intro";
  let rec aux (t : trm) : trm =
    match t.desc with
    | Trm_apps (f, args, ghost_args) when trm_has_cstyle Method_call t ->
      if List.length args < 1 then trm_fail t "C_encoding.method_call_intro: bad encodings.";
      let base, args = List.uncons args in
      let struct_access =
        begin match f.desc with
        | Trm_var f -> trm_struct_get (trm_get base) f.name
        (* Special case when function_beta transformation is applied. *)
        | _ -> failwith "DEPRECATED?" (* f *)
        end in
      trm_alter ~desc:(Trm_apps (struct_access, args, ghost_args)) t
    | _ -> trm_map aux t
     in aux t

(** [class_member_elim t]: encodes class members. *)
let class_member_elim (t : trm) : trm =
  debug_current_stage "class_member_elim";
  (* workaround to substitute untyped 'this' variables with typed 'this' variables required by 'method_call_elim' *)
  let to_subst = ref Var_map.empty in

  let get_class_typ (current_class : var option) (method_var : var) : typ =
    let current_class = match current_class with
    | Some current_class -> current_class
    | None -> failwith "unsupported member definition outside of class structure when serializing"
    in
    typ_ptr (typ_var current_class)
  in
  let rec aux (current_class : var option) (t : trm) : trm =
    Pattern.pattern_match t [
      Pattern.(trm_typedef !__) (fun td () ->
        let current_class = Some td.typedef_name in
        trm_map (aux current_class) t
      );
      Pattern.(trm_let_fun !__ !__ !__ !__ !__) (fun v ty vl body contract () ->
        if trm_has_cstyle Method t then begin
          let var_this = new_var "this" in
          let this_typ = get_class_typ current_class v in
          let typed_this = trm_var ~typ:this_typ var_this in
          to_subst := Var_map.add var_this typed_this !to_subst;
          trm_like ~old:t (trm_let_fun v ty ((var_this, this_typ) :: vl) body ~contract)
        end else if is_class_constructor t then begin
          let var_this = new_var "this" in
          let this_typ = get_class_typ current_class v in
          let this_body = trm_apps (trm_toplevel_var "malloc") [trm_sizeof this_typ] in
          let this_alloc = trm_let (var_this, this_typ) this_body in
          let typed_this = trm_var ~typ:this_typ var_this in
          to_subst := Var_map.add var_this typed_this !to_subst;
          begin match body.desc with
          | Trm_seq (tl, None) ->
            let new_tl = Mlist.map (trm_subst_var var_this typed_this) tl in
            let new_tl = Mlist.push_front this_alloc new_tl in
            let new_body = trm_alter ~desc:(Trm_seq (new_tl, Some var_this)) t in
            trm_like ~old:t (trm_let_fun v this_typ vl new_body ~contract)
          | Trm_lit (Lit_uninitialized _) ->  t
          | _ -> trm_fail t "C_encoding.class_member_elim: ill defined class constructor."
          end
        end else raise Pattern.Next
      );
      Pattern.__ (fun () -> trm_map (aux current_class) t)
    ]
  in
  let on_subst old_t new_t =
    (* keep implicit this annotations etc *)
    trm_alter ~annot:old_t.annot ~loc:old_t.loc new_t
  in
  debug_before_after_trm "cmember" (fun t ->
    aux None t |> Scope_computation.infer_var_ids ~check_uniqueness:false |> trm_subst ~on_subst !to_subst
  ) t


(** [class_member_intro t]: decodes class members. *)
let class_member_intro (t : trm) : trm =
  debug_current_stage "class_member_intro";
  let rec aux (t : trm) : trm =
    match trm_let_fun_inv t with
    | Some (qv, ty, vl, body, contract) when trm_has_cstyle Method t ->
      let ((v_this, _), vl') = List.uncons vl in
      let rec fix_body t =
        match trm_var_inv t with
        | Some x when var_eq x v_this && (not (trm_has_cstyle Implicit_this t)) ->
          trm_like ~old:t (trm_this ())
        | _ -> trm_map fix_body t
      in
      let body' = fix_body body in
      trm_like ~old:t (trm_let_fun qv ty vl' body' ~contract)
    | Some (qv, ty, vl, body, contract) when is_class_constructor t ->
      begin match body.desc with
      | Trm_seq (tl, result) ->
        if Mlist.is_empty tl
          then t
          else
            (* FIXME: Here we should check that the first instruction is indeed the allocation *)
            let tl = Mlist.pop_front tl in
            let new_body = trm_alter ~desc:(Trm_seq (tl, None)) body in
            trm_like ~old:t (trm_let_fun qv typ_unit vl new_body ~contract)
      | _ -> trm_map aux t
      end
   | _ -> trm_map aux t
in aux t

(********************** Decode return ***************************)

let rec return_elim (t: trm): trm =
  let open Option.Monad in
  let rec replace_terminal_return (t: trm) : trm option =
    match t.desc with
    | Trm_abort (Ret expr) -> expr
    | Trm_seq (instrs, None) ->
      let* last_instr = Mlist.last instrs in
      let* terminal_expr = replace_terminal_return last_instr in
      let* typ = terminal_expr.typ in
      let other_instrs = Mlist.pop_back instrs in
      let is_bound_in_seq (v: var) =
        List.exists (fun instr -> match trm_let_inv instr with
          | Some (x, _, _) when var_eq x v -> true
          | _ -> false
        ) (Mlist.to_list other_instrs)
      in
      begin match trm_var_inv terminal_expr with
      | Some v when is_bound_in_seq v ->
        Some (trm_alter ~typ ~desc:(Trm_seq (other_instrs, Some v)) t)
      | _ ->
        let res_var = new_var "__res" in
        let new_last_instr = trm_like ~old:last_instr (trm_let (res_var, typ) terminal_expr) in
        Some (trm_alter ~typ ~desc:(Trm_seq (Mlist.push_back new_last_instr other_instrs, Some res_var)) t)
      end
    | Trm_if (tcond, tthen, telse) ->
      let* tthen = replace_terminal_return tthen in
      let* telse = replace_terminal_return telse in
      let* typ = tthen.typ in
      Some (trm_alter ~typ ~desc:(Trm_if (tcond, tthen, telse)) t)
    | _ -> None
  in
  let t = trm_map return_elim t in
  match t.desc with
  | Trm_fun (args, ret, body, contract) ->
    begin match replace_terminal_return body with
    | None -> t
    | Some body -> trm_like ~old:t (trm_fun args ret body ~contract)
    end
  | _ -> t

let rec return_intro (t: trm): trm =
  let rec add_terminal_return t =
    match t.desc with
    | Trm_seq (instrs, Some v) ->
      begin match Mlist.last instrs with
      | Some last_instr when v.name = "__res" ->
        begin match trm_let_inv last_instr with
        | Some (x, _, expr) when var_eq x v ->
          let last_instr = match into_returning_instr expr with
          | Some t -> t
          | None -> trm_like ~old:last_instr (trm_ret (Some expr))
          in
          trm_like ~old:t (trm_seq (Mlist.push_back last_instr (Mlist.pop_back instrs)))
        | _ -> trm_like ~old:t (trm_seq (Mlist.push_back (trm_ret (Some (trm_var v))) instrs))
        end
      | _ -> trm_like ~old:t (trm_seq (Mlist.push_back (trm_ret (Some (trm_var v))) instrs))
      end
    | _ -> t
  and into_returning_instr t =
    match t.desc with
    | Trm_seq (_, Some _) -> Some (add_terminal_return t)
    | Trm_if (tcond, tthen, telse) when not (trm_has_cstyle Ternary_cond t || trm_has_cstyle Shortcircuit_and t || trm_has_cstyle Shortcircuit_or t) ->
      let process_branch t =
        match into_returning_instr t with
        | Some t -> t
        | None -> trm_ret (Some t)
      in
      let tthen = process_branch tthen in
      let telse = process_branch telse in
      Some (trm_like ~old:t (trm_if tcond tthen telse))
    | _ -> None
  in
  let t = trm_map return_intro t in
  match t.desc with
  | Trm_fun (args, ret, body, contract) ->
    trm_like ~old:t (trm_fun args ret (add_terminal_return body) ~contract)
  | _ -> t

(********************** Decode ghost arguments for applications ***************************)

open Resource_formula

let parse_ghost_args ghost_args_str =
  try
    Resource_cparser.ghost_arg_list Resource_clexer.lex_resources (Lexing.from_string ghost_args_str)
  with Resource_cparser.Error ->
    failwith "Failed to parse ghost arguments: %s" ghost_args_str

let trm_var_with_name (name: string) = Pattern.(trm_var (check (fun v -> var_has_name v name)))

let rec ghost_args_elim (t: trm): trm =
  Pattern.pattern_match t [
    Pattern.(trm_apps2 (trm_var_with_name "__call_with") (trm_apps !__ !__ nil) (trm_string !__)) (fun fn args ghost_args_str () ->
        let fn = ghost_args_elim fn in
        let args = List.map ghost_args_elim args in
        let ghost_args = parse_ghost_args ghost_args_str in
        trm_alter ~desc:(Trm_apps (fn, args, ghost_args)) t
      );
    Pattern.(trm_apps2 (trm_var_with_name "__ghost") !__ (trm_string !__)) (fun ghost_fn ghost_args_str () ->
        let ghost_fn = ghost_args_elim ghost_fn in
        let ghost_args = parse_ghost_args ghost_args_str in
        trm_alter ~annot:{t.annot with trm_annot_attributes = [GhostCall]} ~desc:(Trm_apps (ghost_fn, [], ghost_args)) t
      );
    Pattern.(trm_apps2 (trm_var_with_name "__ghost_begin") !__ (trm_string !__)) (fun ghost_fn ghost_args_str () ->
        let ghost_fn = ghost_args_elim ghost_fn in
        let ghost_args = parse_ghost_args ghost_args_str in
        trm_apps (trm_var Resource_trm.var_ghost_begin) [
          trm_alter ~annot:{t.annot with trm_annot_attributes = [GhostCall]} ~desc:(Trm_apps (ghost_fn, [], ghost_args)) t
        ]
      );
    Pattern.(trm_seq !__ !__) (fun seq result () -> trm_alter ~desc:(Trm_seq (Mlist.of_list (ghost_args_elim_in_seq (Mlist.to_list seq)), result)) t);
    Pattern.__ (fun () -> trm_map ghost_args_elim t)
  ]

and ghost_args_elim_in_seq (ts: trm list): trm list =
  match ts with
  | [] -> []
  | t :: ts ->
    let grab_ghost_args ts =
      Pattern.pattern_match ts [
        Pattern.(trm_apps1 (trm_var_with_name "__with") (trm_string !__) ^:: !__)
          (fun ghost_args_str ts () -> (parse_ghost_args ghost_args_str, ts));
        Pattern.__ (fun () -> ([], ts))
      ]
    in

    let t = ghost_args_elim t in
    let t, ts = Pattern.pattern_match t [
      Pattern.(trm_apps !__ !__ nil) (fun f args () ->
        let ghost_args, ts = grab_ghost_args ts in
        (trm_alter ~desc:(Trm_apps (f, args, ghost_args)) t, ts)
      );
      Pattern.(trm_let !__ !__ !(trm_apps !__ !__ nil)) (fun var typ body f args () ->
        let ghost_args, ts = grab_ghost_args ts in
        (trm_alter ~desc:(Trm_let ((var, typ), trm_alter ~desc:(Trm_apps (f,args,ghost_args)) body)) t, ts));
      Pattern.__ (fun () -> (t, ts))
    ]
    in
    t :: ghost_args_elim_in_seq ts

let formula_to_string (style : style) (f: formula) : string =
  Ast_to_c.ast_to_string ~width:PPrint.infinity ~style:style.cstyle f

let var__with = trm_var (name_to_var "__with")
let var__call_with = trm_var (name_to_var "__call_with")
let var__ghost = trm_var (name_to_var "__ghost")

let ghost_args_intro (style: style) (t: trm) : trm =
  let rec aux t =
    let ghost_args_to_trm_string ghost_args =
      trm_string (String.concat ", " (List.map (fun (ghost_var, ghost_formula) -> sprintf "%s := %s" (ghost_var.name) (formula_to_string style ghost_formula)) ghost_args))
    in

    match t.desc with
    | Trm_apps (fn, args, (_ :: _ as ghost_args)) ->
      (* Outside sequence add __call_with *)
      let t = trm_map aux t in
      trm_apps var__call_with [t; ghost_args_to_trm_string ghost_args]
    | Trm_seq (seq, result) ->
      (* Inside sequence add __with *)
      Nobrace.enter ();
      let seq = Mlist.map (fun t -> Pattern.pattern_match t [
        Pattern.(trm_apps !__ nil !__) (fun fn ghost_args () ->
          if not (trm_has_attribute GhostCall t) then raise_notrace Pattern.Next;
          let fn = aux fn in
          trm_like ~old:t (trm_apps var__ghost [fn; ghost_args_to_trm_string ghost_args])
        );
        Pattern.(trm_apps __ __ !(__ ^:: __)) (fun ghost_args () ->
          let t = trm_map aux t in
          Nobrace.trm_seq_nomarks [t; trm_apps var__with [ghost_args_to_trm_string ghost_args]]
        );
        Pattern.(trm_let !__ !__ !(trm_apps __ __ !(__ ^:: __))) (fun var typ call ghost_args () ->
          let call = trm_map aux call in
          Nobrace.trm_seq_nomarks [trm_like ~old:t (trm_let (var, typ) call); trm_apps var__with [ghost_args_to_trm_string ghost_args]]
        );
        Pattern.(trm_let !__ !__ (trm_apps1 (trm_var (var_eq Resource_trm.var_ghost_begin)) !(trm_apps !__ nil !__))) (fun ghost_pair typ ghost_call ghost_fn ghost_args () ->
          let ghost_fn = aux ghost_fn in
          trm_like ~old:(trm_error_merge ~from:ghost_call t) (trm_let (ghost_pair, typ) (trm_apps (trm_var Resource_trm.var_ghost_begin) [ghost_fn; ghost_args_to_trm_string ghost_args]))
        );
        Pattern.__ (fun () -> trm_map aux t)
      ]) seq in
      let nobrace_id = Nobrace.exit () in
      let seq = Nobrace.flatten_seq nobrace_id seq in
      trm_alter ~desc:(Trm_seq (seq, result)) t
    | _ -> trm_map aux t
  in
  aux t

let ghost_remove (t : trm) : trm =
  Nobrace.remove_after_trm_op (Resource_trm.delete_annots_on ~delete_contracts:false ~delete_ghost:true) t

let ghost_args_intro_or_remove_ghost (style: style) (t: trm) : trm =
  if style.typing.typing_ghost
    then ghost_args_intro style t
    else ghost_remove t


(********************** Decode contract annotations ***************************)

open Resource_contract

(* These pseudo-variables will never get an id since they disappear before *)
let __pure = name_to_var "__pure"
let __requires = name_to_var "__requires"
let __ensures = name_to_var "__ensures"
let __reads = name_to_var "__reads"
let __writes = name_to_var "__writes"
let __modifies = name_to_var "__modifies"
let __consumes = name_to_var "__consumes"
let __produces = name_to_var "__produces"

let __xrequires = name_to_var "__xrequires"
let __xensures = name_to_var "__xensures"
let __xreads = name_to_var "__xreads"
let __xwrites = name_to_var "__xwrites"
let __xmodifies = name_to_var "__xmodifies"
let __xconsumes = name_to_var "__xconsumes"
let __xproduces = name_to_var "__xproduces"
let __invariant = name_to_var "__invariant"
let __smodifies = name_to_var "__smodifies"
let __sreads = name_to_var "__sreads"
let __strict = name_to_var "__strict"

let __reverts = name_to_var "__reverts"

let __ctx_res = name_to_var "__ctx_res"
let __produced_res = name_to_var "__produced_res"
let __used_res = name_to_var "__used_res"
let __framed_res = name_to_var "__framed_res"
let __joined_res = name_to_var "__joined_res"
let __contract_inst = name_to_var "__contract_inst"
let __post_inst = name_to_var "__post_inst"

let fun_clause_type_inv (clause: var) : fun_contract_clause_type option =
  match clause.name with
  | "__pure" -> Some Requires
  | "__requires" -> Some Requires
  | "__ensures" -> Some Ensures
  | "__reads" -> Some Reads
  | "__writes" -> Some Writes
  | "__modifies" -> Some Modifies
  | "__consumes" -> Some Consumes
  | "__produces" -> Some Produces
  | "__xrequires" | "__xensures" | "__xreads" | "__xwrites" | "__xmodifies"
  | "__xconsumes" | "__xproduces" | "__invariant" | "__sreads" | "__smodifies" | "__strict" ->
    failwith "Found the loop contract clause '%s' in a function contract" clause.name
  | _ -> None

let loop_clause_type_inv (clause: var) : loop_contract_clause_type option =
  match clause.name with
  | "__requires" -> Some LoopVars
  | "__xrequires" -> Some (Exclusive Requires)
  | "__xensures" -> Some (Exclusive Ensures)
  | "__xreads" -> Some (Exclusive Reads)
  | "__xwrites" -> Some (Exclusive Writes)
  | "__xmodifies" -> Some (Exclusive Modifies)
  | "__xconsumes" -> Some (Exclusive Consumes)
  | "__xproduces" -> Some (Exclusive Produces)
  | "__invariant" -> Some Invariant
  | "__sreads" -> Some SharedReads
  | "__smodifies" -> Some SharedModifies
  | "__strict" -> Some Strict
  | "__pure" | "__ensures" | "__reads" | "__writes" | "__modifies" | "__consumes" | "__produces" ->
    failwith "Found the function contract clause '%s' in a loop contract" clause.name
  | _ -> None

let encoded_clause_inv (clause_type_inv: var -> 'clause_type option) (t: trm): ('clause_type * string) option =
  let open Option.Monad in
  let* fn, args = trm_apps_inv t in
  let* fn_var = trm_var_inv fn in
  let* clause = clause_type_inv fn_var in
  let arg = Option.value ~default:(trm_string "") (List.nth_opt args 0) in
  let* arg = trm_lit_inv arg in
  let* arg =
    match arg with
    | Lit_string s -> Some s
    | _ -> None
  in
  Some (clause, arg)

let rec extract_encoded_contract_clauses (clause_type_inv: var -> 'clause_type option) (seq: trm mlist):
  ('clause_type * string) list * trm mlist =
  match Option.bind (Mlist.nth_opt seq 0) (encoded_clause_inv clause_type_inv) with
  | Some contract ->
    let cont, seq = extract_encoded_contract_clauses clause_type_inv (Mlist.pop_front seq) in
    contract::cont, seq
  | None -> [], seq

let extract_fun_contract (seq: trm mlist) : fun_contract option * trm mlist =
  let enc_contract, seq = extract_encoded_contract_clauses fun_clause_type_inv seq in
  match enc_contract with
  | [] -> None, seq
  | _ -> Some (parse_contract_clauses empty_fun_contract push_fun_contract_clause enc_contract), seq

let encoded_reverts_inv (t: trm): var option =
  Pattern.pattern_match t [
    Pattern.(trm_apps1 (trm_var (check (fun v -> v.name = "__reverts"))) (trm_var !__)) (fun revert_fn () ->
      Some revert_fn
    );
    Pattern.__ (fun () -> None)
  ]

let extract_fun_spec (seq: trm mlist) : fun_spec * trm mlist =
  match Option.bind (Mlist.nth_opt seq 0) encoded_reverts_inv with
  | Some reverts_fn -> FunSpecReverts reverts_fn, Mlist.pop_front seq
  | None ->
    let contract_opt, seq = extract_fun_contract seq in
    match contract_opt with
    | None -> FunSpecUnknown, seq
    | Some c -> FunSpecContract c, seq


let extract_loop_contract (seq: trm mlist) : loop_contract * trm mlist =
  let enc_contract, seq = extract_encoded_contract_clauses loop_clause_type_inv seq in
  let is_strict = ref false in
  let enc_contract = List.filter (fun (clause_type, _) ->
    if clause_type = Strict then
      (is_strict := true; false)
    else true) enc_contract in
  let start_contract = if !is_strict then empty_strict_loop_contract else empty_loop_contract in
  parse_contract_clauses start_contract push_loop_contract_clause enc_contract, seq


let contract_elim (t: trm): trm =
  debug_current_stage "contract_elim";
  let rec aux t =
  match t.desc with
  | Trm_fun (args, ty, body, spec) ->
    assert (spec = FunSpecUnknown);
    begin match trm_seq_inv body with
    | Some (body_seq, result) ->
      let spec, new_body = extract_fun_spec body_seq in
      let new_body = Mlist.map aux new_body in
      trm_alter ~desc:(Trm_fun (args, ty, trm_seq ?result new_body, spec)) t
    | None -> trm_map aux t
    end

  | Trm_for (range, body, contract) ->
    assert (contract = empty_loop_contract);
    begin match trm_seq_inv body with
    | Some (body_seq, result) ->
      let contract, new_body = extract_loop_contract body_seq in
      let new_body = Mlist.map aux new_body in
      trm_alter ~desc:(Trm_for (range, trm_seq ?result new_body, contract)) t
    | None -> trm_map aux t
    end

  | _ -> trm_map aux t
  in aux t

let named_formula_to_string (style: style) ?(used_vars = Var_set.empty) (hyp, formula): string =
  let sformula = formula_to_string style formula in
  if not (style.typing.print_generated_res_ids || Var_set.mem hyp used_vars) && String.starts_with ~prefix:"#" hyp.name
    then Printf.sprintf "%s" sformula
    else begin
      let hyp_s = if style.cstyle.print_var_id then var_to_string hyp else hyp.name in
      Printf.sprintf "%s: %s" hyp_s sformula
    end

(** [seq_push code t]: inserts trm [code] at the begining of sequence [t],
    [code] - instruction to be added,
    [t] - ast of the outer sequence where the insertion will be performed. *)
let seq_push (code : trm) (t : trm) : trm =
  let error = "seq_push: expected a sequence where insertion is performed." in
  let tl, result = trm_inv ~error trm_seq_inv t in
  let new_tl = Mlist.push_front code tl in
  trm_replace (Trm_seq (new_tl, result)) t

let trm_array_of_string list =
  trm_array ~typ:typ_string (Mlist.of_list (List.map trm_string list))

let ctx_resources_to_trm (style: style) (res: resource_set) : trm =
  let used_vars = Resource_set.used_vars res in
  let spure = trm_array_of_string (List.map (named_formula_to_string style ~used_vars) res.pure) in
  let slin = trm_array_of_string (List.map (named_formula_to_string style) res.linear) in
  trm_apps (trm_var __ctx_res) [spure; slin]

let ctx_used_res_item_to_string (style: style) (res: used_resource_item) : string =
  let sinst = formula_to_string style res.inst_by in
  let sformula = formula_to_string style res.used_formula in
  Printf.sprintf "%s := %s : %s" res.hyp.name sinst sformula

let ctx_used_res_to_trm (style: style) ~(clause: var) (used_res: used_resource_set) : trm =
  let spure = trm_array_of_string (List.map (ctx_used_res_item_to_string style) used_res.used_pure) in
  let slin = trm_array_of_string (List.map (ctx_used_res_item_to_string style) used_res.used_linear) in
  trm_apps (trm_var clause) [spure; slin]

let ctx_produced_res_item_to_string (style: style) (res: produced_resource_item) : string =
  let sformula = formula_to_string style res.produced_formula in
  Printf.sprintf "%s := %s : %s" res.produced_hyp.name res.post_hyp.name sformula

let ctx_produced_res_to_trm (style: style) (produced_res: produced_resource_set) : trm =
  let spure = trm_array_of_string (List.map (ctx_produced_res_item_to_string style) produced_res.produced_pure) in
  let slin = trm_array_of_string (List.map (ctx_produced_res_item_to_string style) produced_res.produced_linear) in
  trm_apps (trm_var __produced_res) [spure; slin]

let ctx_usage_map_to_strings res_used =
  List.map (function
    | hyp, Required -> sprintf "%s" hyp.name
    | hyp, Ensured -> sprintf "Ensured %s" hyp.name
    | hyp, ArbitrarilyChosen -> sprintf "Arbitrary %s" hyp.name
    | hyp, ConsumedFull -> sprintf "Full %s" hyp.name
    | hyp, ConsumedUninit -> sprintf "Uninit %s" hyp.name
    | hyp, SplittedFrac -> sprintf "Subfrac %s" hyp.name
    | hyp, JoinedFrac -> sprintf "JoinFrac %s" hyp.name
    | hyp, Produced -> sprintf "Produced %s" hyp.name)
    (Var_map.bindings res_used)

let debug_ctx_before = false

let display_ctx_resources (style: style) (t: trm): trm list =
  let t =
    match t.desc with
    | Trm_let (_, body) -> { t with ctx = { body.ctx with ctx_resources_before = t.ctx.ctx_resources_before; ctx_resources_after = t.ctx.ctx_resources_after } }
    | _ -> t
  in
  let tl_used =
    if style.typing.typing_used_res
      then Option.to_list (Option.map (fun res_used ->
        let s_used = ctx_usage_map_to_strings res_used in
        trm_apps (trm_var __used_res) (List.map trm_string s_used)) t.ctx.ctx_resources_usage)
      else []
    in
  let tl = match t.ctx.ctx_resources_contract_invoc with
    | None -> [t]
    | Some contract_invoc ->
      (* TODO: use a combinator to factorize the pattern "if then else []" *)
      let tl_frame =
        if style.typing.typing_framed_res
          then [ trm_apps (trm_var __framed_res) (List.map trm_string (List.map (named_formula_to_string style) contract_invoc.contract_frame)) ]
          else []
        in
      let tl_inst =
        if style.typing.typing_contract_inst
          then [ctx_used_res_to_trm style ~clause:__contract_inst contract_invoc.contract_inst]
          else [] in
      let tl_produced =
        if style.typing.typing_produced_res
          then [ctx_produced_res_to_trm style contract_invoc.contract_produced ]
          else [] in
      let tl_joined =
        if style.typing.typing_joined_res
          then [trm_apps (trm_var __joined_res) (List.map trm_string
                  (List.map (fun (x, y) -> sprintf "%s <-- %s" x.name y.name)
                   contract_invoc.contract_joined_resources)) ]
          else [] in
      tl_frame @ tl_inst @ [ t ] @ tl_produced @ tl_joined
  in
  let tl_before =
    if debug_ctx_before (* TODO : assert == *)
      then Option.to_list (Option.map (ctx_resources_to_trm style) t.ctx.ctx_resources_before)
      else []
    in
  let tl_after =
    if style.typing.typing_ctx_res
      then Option.to_list (Option.map (ctx_resources_to_trm style) t.ctx.ctx_resources_after)
      else []
    in
  (tl_before @ tl_used @ tl @ tl_after)

let computed_resources_intro (style: style) (t: trm): trm =
  let rec aux t =
    match t.desc with
    | Trm_seq (instrs, result) when not (trm_is_mainfile t) ->
      let tl_before =
        if style.typing.typing_ctx_res
          then Option.to_list (Option.map (ctx_resources_to_trm style) t.ctx.ctx_resources_before)
          else []
        in
      let tl_post_inst =
        if style.typing.typing_used_res
          then Option.to_list (Option.map (ctx_used_res_to_trm style ~clause:__post_inst) t.ctx.ctx_resources_post_inst)
          else []
        in
      let process_instr instr = Mlist.of_list (display_ctx_resources style (aux instr)) in
      let tl_instrs = Mlist.concat_map process_instr instrs in
      trm_like ~old:t (trm_seq ?result (Mlist.merge_list [Mlist.of_list tl_before; tl_instrs; Mlist.of_list tl_post_inst]))
    | _ -> trm_map ~keep_ctx:true aux t
  in
  aux t

let rec contract_intro (style: style) (t: trm): trm =
  if not style.typing.typing_contracts then t else

  (* debug_current_stage "contract_intro"; *)
  let push_named_formulas (contract_prim: var) ?(used_vars: Var_set.t option) (named_formulas: resource_item list) (t: trm): trm =
    List.fold_right (fun named_formula t ->
      let sres = named_formula_to_string style ?used_vars named_formula in
      let tres = trm_apps (trm_var contract_prim) [trm_string sres] in
      seq_push tres t) named_formulas t
  in

  let push_common_clauses ?(reads_clause: var option) ~(modifies_clause: var) ?(writes_clause: var option) (pure_with_fracs: resource_item list) (pre_linear: resource_item list) (post_linear: resource_item list) (t: trm): resource_item list * resource_item list * resource_item list * trm =
    let common_linear, pre_linear, post_linear = Resource_formula.filter_common_resources pre_linear post_linear in

    (* FIXME: This turns two reads formulas with a shared id into reads formulas with distinct id.
       Maybe this is not a problem in practice. *)
    let frac_to_remove = Hashtbl.create (List.length common_linear) in
    let reads_res, modifies_res =
      if reads_clause = None then
        [], common_linear
      else
        List.partition_map (fun (h, formula) ->
          match formula_read_only_inv formula with
          | Some { frac; formula = ro_formula } ->
            begin match trm_var_inv frac with
            | Some frac_atom ->
              Hashtbl.add frac_to_remove frac_atom ();
              Left (h, ro_formula)
            | None -> Right (h, formula)
            end
          | None -> Right (h, formula)) common_linear
    in

    let hyp_not_mem_before_pop (hyp, _) =
      if Hashtbl.mem frac_to_remove hyp then (
        Hashtbl.remove frac_to_remove hyp;
        false
      ) else true
    in
    let pre_pure = List.filter hyp_not_mem_before_pop pure_with_fracs in
    if (Hashtbl.length frac_to_remove != 0) then
      Tools.warn "Some fractions should have been discarded but they were not found in context: %s" (String.concat ", " (Hashtbl.fold (fun frac () acc -> frac.name :: acc) frac_to_remove []));

    let t = match reads_clause with
      | Some reads_clause -> push_named_formulas reads_clause reads_res t
      | None -> t
    in
    let t, pre_linear, post_linear = match writes_clause with
      | Some writes_prim ->
        let writes_res, pre_linear, post_linear = Resource_formula.filter_common_resources ~filter_map_left:formula_uninit_inv pre_linear post_linear in
        push_named_formulas writes_prim writes_res t, pre_linear, post_linear
      | None -> t, pre_linear, post_linear
    in
    let t = push_named_formulas modifies_clause modifies_res t in
    (pre_pure, pre_linear, post_linear, t)
  in
  let push_common_clauses ?(force=false) = if style.cstyle.print_contract_internal_repr && not force then
    fun ?reads_clause ~modifies_clause ?writes_clause pure_with_fracs pre_linear post_linear t -> (pure_with_fracs, pre_linear, post_linear, t)
    else push_common_clauses
  in

  (* TODO: Inline into Trm_fun branch when Trm_let_fun disappears *)
  let add_contract_to_fun_body body contract =
    let body = contract_intro style body in
    match contract with
    | FunSpecContract contract when contract = empty_fun_contract ->
      seq_push (trm_apps (trm_var __pure) []) body
    | FunSpecContract contract ->
      let used_vars = fun_contract_used_vars contract in
      let pre_pure, pre_linear, post_linear, body =
        push_common_clauses ~reads_clause:__reads ~modifies_clause:__modifies ~writes_clause:__writes contract.pre.pure contract.pre.linear contract.post.linear body
      in
      let body = push_named_formulas __produces post_linear body in
      let body = push_named_formulas __ensures ~used_vars contract.post.pure body in
      let body = push_named_formulas __consumes pre_linear body in
      let body = push_named_formulas __requires ~used_vars pre_pure body in
      body
    | FunSpecReverts reverted_fn ->
      seq_push (trm_apps (trm_var __reverts) [trm_var reverted_fn]) body
    | FunSpecUnknown -> body
  in

  match t.desc with
  | Trm_fun (args, ty, body0, contract) ->
    let body = add_contract_to_fun_body body0 contract in
    if body == body0
      then t
      else trm_like ~old:t (trm_fun args ty body)

  | Trm_for (range, body0, contract) ->
    let body = contract_intro style body0 in
    let used_vars = loop_contract_used_vars contract in
    let loop_ghosts, pre_linear, post_linear, body =
      push_common_clauses ~reads_clause:__xreads ~modifies_clause:__xmodifies ~writes_clause:__xwrites
        contract.loop_ghosts contract.iter_contract.pre.linear contract.iter_contract.post.linear body
    in
    let body = push_named_formulas __xproduces post_linear body in
    let body = push_named_formulas __xensures ~used_vars contract.iter_contract.post.pure body in
    let body = push_named_formulas __xconsumes pre_linear body in
    let body = push_named_formulas __xrequires ~used_vars contract.iter_contract.pre.pure body in
    List.iter (fun (_, formula) -> if formula_read_only_inv formula = None then failwith "parallel_reads contains non RO resources") contract.parallel_reads;
    let loop_ghosts, _, _, body =
      push_common_clauses ~force:true ~reads_clause:__sreads ~modifies_clause:__sreads
        loop_ghosts contract.parallel_reads contract.parallel_reads body
    in
    let body = push_named_formulas __smodifies ~used_vars contract.invariant.linear body in
    let body = push_named_formulas __invariant ~used_vars contract.invariant.pure body in
    let body = push_named_formulas __requires ~used_vars loop_ghosts body in
    let body = if contract.strict
      then seq_push (trm_apps (trm_var __strict) []) body
      else body in
    if body == body0
      then t
      else trm_like ~old:t (trm_for range body)

  | Trm_seq (instrs, result) ->
    trm_like ~old:t (trm_seq ?result (Mlist.map (contract_intro style) instrs))

  | _ -> trm_map (contract_intro style) t


(*************************************** Formula syntactic sugar *********************************************)

let rec formula_sugar_elim (t: trm): trm =
  if trm_has_cstyle ResourceFormula t then
    desugar_formula t
  else
    trm_map formula_sugar_elim t

let rec formula_sugar_intro (t: trm): trm =
  if trm_has_cstyle ResourceFormula t then
    encode_formula t
  else
    trm_map formula_sugar_intro t


(****************************** Alpha renaming of autogen variables ***************************************)

let autogen_alpha_rename style (t : trm) : trm =
  let map_binder (highest_h, renaming) var predecl =
    let return_next_name () =
      let new_v = { var with name = ("#_" ^ string_of_int (highest_h + 1)) } in
      (highest_h + 1, Var_map.add var new_v renaming), new_v
    in

    if String.starts_with ~prefix:"#" var.name then
      if String.starts_with ~prefix:"#_" var.name then begin
        let var_hnum = String.sub var.name 2 (String.length var.name - 2) in
        match int_of_string_opt var_hnum with
        | None -> (highest_h, renaming), var
        | Some n when n > highest_h -> (n, renaming), var
        | Some n -> return_next_name ()
      end else
        return_next_name ()
    else
      (highest_h, renaming), var
  in

  let map_var (highest_h, renamings) v =
    match Var_map.find_opt v renamings with
    | Some v' -> v'
    | None -> v
  in

  if style.typing.print_generated_res_ids
    then t (* When we want to print generated ids we prefer to keep them in sync with internal names *)
    else trm_rename_vars ~map_binder map_var (0, Var_map.empty) t


(*************************************** Main entry points *********************************************)

(** [cfeatures_elim t] converts a raw ast as produced by a C parser into an ast with OptiTrust semantics.
   It assumes [t] to be a full program or a right value. *)
let cfeatures_elim: trm -> trm =
  debug_before_after_trm "cfeatures_elim" (fun t ->
  contract_elim t |>
  ghost_args_elim |>
  class_member_elim |>
  method_call_elim |>
  Scope_computation.infer_var_ids ~check_uniqueness:false |>
  infix_elim |>
  stackvar_elim |>
  caddress_elim |>
  return_elim |>
  expr_in_seq_elim |>
  formula_sugar_elim |>
  Scope_computation.infer_var_ids)

(** [cfeatures_intro t] converts an OptiTrust ast into a raw C that can be pretty-printed in C syntax *)
let cfeatures_intro (style : style) : trm -> trm =
  debug_before_after_trm "cfeatures_intro" (fun t ->
  Scope_computation.infer_var_ids t |>
  formula_sugar_intro |>
  expr_in_seq_intro |>
  return_intro |>
  caddress_intro |>
  stackvar_intro |>
  infix_intro |>
  method_call_intro |>
  class_member_intro |>
  autogen_alpha_rename style |>
  ghost_args_intro_or_remove_ghost style |>
  autogen_alpha_rename style |>
  contract_intro style
  )

(** [meta_intro t] adds into [t] all the "for-typing" operations
    and the contracts as C calls using the "__" prefix *)
let meta_intro ?(skip_var_ids = false) (style: style) : trm -> trm =
  fun t ->
  (if skip_var_ids then t else Scope_computation.infer_var_ids ~failure_allowed:false t) |>
  formula_sugar_intro |>
  autogen_alpha_rename style |>
  ghost_args_intro_or_remove_ghost style |>
  autogen_alpha_rename style |>
  contract_intro style



(* Note: recall that currently const references are not supported
   Argument of why const ref is not so useful
before:
  const vect v = {0,1}
  f(v.x, v.x, v.x)

after:
  const vect v = {0,1}
  const int& a = v.x;
  f(a,a,a)

but it is equivalent to:
  const vect v = {0,1}
  const int a = v.x;
  f(a,a,a)

*)

(*

source:
T x(args)

before encoding
T x = (new(T,args)@ annot_constructor_arg)

after encoding
T* x = (T(args)@annot_new)


source
constructor T(a, b) : field1(a) { field2 = b;}


before encoding, with treating "this" as const variable

before encoding
void T(a, b) { @annot_constructor

  this->field1 = a;  @annot_member_initializer
  (this@annot_implicit_this) ->field2 = b;

}



after encoding
T* T(a, b) {


  T* this = alloc(size_of(T)); @annot_dont_encode
  this->field1 = a;  @annot_member_initializer
  (this@annot_implicit_this) ->field2 = b;

  return this; } @annot_constructor


*)
