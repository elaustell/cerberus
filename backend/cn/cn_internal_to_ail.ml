module CF=Cerb_frontend
(* module CB=Cerb_backend
open CB.Pipeline
open Setup *)
open CF.Cn
open Compile
open Executable_spec_utils
open PPrint
module A=CF.AilSyntax
module C=CF.Ctype
module BT=BaseTypes

(* TODO: Change to use internal  *)

module ConstructorPattern = struct
  type t = C.union_tag 
  let compare (x : t) y = Sym.compare_sym x y
end

module PatternMap = Map.Make(ConstructorPattern)

let generic_cn_dt_sym = Sym.fresh_pretty "cn_datatype"

let rec bt_to_cn_base_type = function
| BT.Unit -> CN_unit
| BT.Bool -> CN_bool
| BT.Integer -> CN_integer
| BT.Real -> CN_real
| BT.CType -> failwith "TODO"
| BT.Loc -> CN_loc
| BT.Struct tag -> CN_struct tag
| BT.Datatype tag -> CN_datatype tag
| BT.Record member_types -> failwith "TODO"
  (* CN_record (List.map_snd of_basetype member_types) *)
| BT.Map (bt1, bt2) -> CN_map (bt_to_cn_base_type bt1, bt_to_cn_base_type bt2)
| BT.List bt -> CN_list (bt_to_cn_base_type bt)
| BT.Tuple bts -> CN_tuple (List.map bt_to_cn_base_type bts)
| BT.Set bt -> CN_set (bt_to_cn_base_type bt)


(* TODO: Complete *)
let rec cn_to_ail_base_type = 
  let generate_ail_array bt = C.(Array (Ctype ([], cn_to_ail_base_type bt), None)) in 
  function
  | CN_unit -> C.Void
  | CN_bool -> C.(Basic (Integer Bool))
  | CN_integer -> C.(Basic (Integer (Signed Int_))) (* TODO: Discuss integers *)
  (* | CN_real -> failwith "TODO" *)
  | CN_loc -> C.(Pointer (empty_qualifiers, Ctype ([], Void))) (* Casting all CN pointers to void star *)
  | CN_struct sym -> C.(Struct sym)
  (* | CN_record of list (cn_base_type 'a * Symbol.identifier) *)
  | CN_datatype sym -> C.(Pointer (empty_qualifiers, Ctype ([], Struct sym)))
  (* | CN_map of cn_base_type 'a * cn_base_type 'a *)
  | CN_list bt -> generate_ail_array bt (* TODO: What is the optional second pair element for? Have just put None for now *)
  (* | CN_tuple of list (cn_base_type 'a) *)
  | CN_set bt -> generate_ail_array bt
  | _ -> failwith "TODO"

let cn_to_ail_binop_internal = function
  | Terms.And -> A.And
  | Or -> A.Or
  (* | Impl *)
  | Add -> A.(Arithmetic Add)
  | Sub -> A.(Arithmetic Sub)
  | Mul 
  | MulNoSMT -> A.(Arithmetic Mul)
  | Div 
  | DivNoSMT -> A.(Arithmetic Div)
  (* | Exp
  | ExpNoSMT
  | Rem
  | RemNoSMT
  | Mod
  | ModNoSMT
  | XORNoSMT
  | BWAndNoSMT
  | BWOrNoSMT *)
  | LT -> A.Lt
  | LE -> A.Le
  (* | Min
  | Max *)
  | EQ -> A.Eq
  | _ -> failwith "TODO: CN internal AST binop translation to Ail"
  (* | LTPointer
  | LEPointer
  | SetUnion
  | SetIntersection
  | SetDifference
  | SetMember
  | Subset *)

  


let rec cn_to_ail_const_internal = function
  | Terms.Z z -> A.AilEconst (ConstantInteger (IConstant (z, Decimal, None)))
  | Q q -> A.AilEconst (ConstantFloating (Q.to_string q, None))
  | Pointer z -> A.AilEunary (Address, mk_expr (cn_to_ail_const_internal (Terms.Z z.addr)))
  | Bool b -> A.AilEconst (ConstantInteger (IConstant (Z.of_int (Bool.to_int b), Decimal, Some B)))
  | Unit -> A.AilEconst (ConstantIndeterminate C.(Ctype ([], Void)))
  | Null -> A.AilEconst (ConstantNull)
  (* TODO *)
  (* | CType_const of Sctypes.ctype *)
  (* | Default of BaseTypes.t  *)
  | _ -> failwith "TODO"

type 'a dest =
| Assert : (CF.GenTypes.genTypeCategory A.statement_ list) dest
| Return : (CF.GenTypes.genTypeCategory A.statement_ list) dest 
| AssignVar : C.union_tag -> (CF.GenTypes.genTypeCategory A.statement_ list) dest
| PassBack : (CF.GenTypes.genTypeCategory A.statement_ list * CF.GenTypes.genTypeCategory A.expression_) dest

let dest : type a. a dest -> CF.GenTypes.genTypeCategory A.statement_ list * CF.GenTypes.genTypeCategory A.expression_ -> a = 
  fun d (s, e) -> 
    match d with
    | Assert -> 
      let assert_stmt = A.(AilSexpr (mk_expr (AilEassert (mk_expr e)))) in
      s @ [assert_stmt]
    | Return ->
      let return_stmt = A.(AilSreturn (mk_expr e)) in
      s @ [return_stmt]
    | AssignVar x -> 
      let assign_stmt = A.(AilSdeclaration [(x, Some (mk_expr e))]) in
      s @ [assign_stmt]
    | PassBack -> (s, e)

let prefix : type a. a dest -> CF.GenTypes.genTypeCategory A.statement_ list -> a -> a = 
  fun d s1 u -> 
    match d, u with 
    | Assert, s2 -> s1 @ s2
    | Return, s2 -> s1 @ s2
    | AssignVar _, s2 -> s1 @ s2
    | PassBack, (s2, e) -> (s1 @ s2, e)

let create_id_from_sym ?(lowercase=false) sym =
  let str = Sym.pp_string sym in 
  let str = if lowercase then String.lowercase_ascii str else str in
  Id.id str

let create_sym_from_id id = 
  Sym.fresh_pretty (Id.pp_string id)


let generate_sym_with_suffix ?(suffix="_tag") ?(uppercase=false) ?(lowercase=false) constructor =  
  let doc = 
  CF.Pp_ail.pp_id ~executable_spec:true constructor ^^ (!^ suffix) in 
  let str = 
  CF.Pp_utils.to_plain_string doc in 
  let str = if uppercase then String.uppercase_ascii str else str in
  let str = if lowercase then String.lowercase_ascii str else str in
  (* Printf.printf "%s\n" str; *)
  Sym.fresh_pretty str

(* frontend/model/ail/ailSyntax.lem *)
(* ocaml_frontend/generated/ailSyntax.ml *)
(* TODO: Use mu_datatypes from Mucore program instead of cn_datatypes *)
let rec cn_to_ail_expr_aux_internal 
: type a. _ option -> (_ Cn.cn_datatype) list -> IT.t -> a dest -> a
= fun const_prop dts (IT (term_, basetype)) d ->
  (* let _cn_to_ail_expr_aux_internal_at_env : type a. _ cn_expr -> string -> a dest -> a
  = (fun e es d ->
      (match es with
        | start_evaluation_scope -> 
          (* let Symbol (digest, nat, _) = CF.Symbol.fresh () in *)
          (* TODO: Make general *)
          let s, ail_expr = cn_to_ail_expr_aux_internal const_prop dts e PassBack in
          let e_cur_nm =
          match ail_expr with
            | A.(AilEident sym) -> CF.Pp_symbol.to_string_pretty sym (* Should only be AilEident sym - function arguments only *)
            | _ -> failwith "Incorrect type of Ail expression"
          in
          let e_old_nm = e_cur_nm ^ "_old" in
          let sym_old = CF.Symbol.Symbol ("", 0, SD_CN_Id e_old_nm) in
          dest d (s, A.(AilEident sym_old))
          ))
  in *)
  match term_ with
  | Const const ->
    let ail_expr_ = cn_to_ail_const_internal const in
    dest d ([], ail_expr_)

  | Sym sym ->
    let ail_expr_ = 
      (match const_prop with
        | Some (sym2, cn_const) ->
            if CF.Symbol.equal_sym sym sym2 then
              cn_to_ail_const_internal cn_const
            else
              A.(AilEident sym)
        | None -> A.(AilEident sym)  (* TODO: Check. Need to do more work if this is only a CN var *)
      )
      in
      dest d ([], ail_expr_)

  | Binop (bop, t1, t2) ->
    let s1, e1 = cn_to_ail_expr_aux_internal const_prop dts t1 PassBack in
    let s2, e2 = cn_to_ail_expr_aux_internal const_prop dts t2 PassBack in
    let ail_expr_ = A.AilEbinary (mk_expr e1, cn_to_ail_binop_internal bop, mk_expr e2) in 
    dest d (s1 @ s2, ail_expr_) 

  | Not t -> 
    let s, e_ = cn_to_ail_expr_aux_internal const_prop dts t PassBack in
    let ail_expr_ = A.(AilEunary (Bnot, mk_expr e_)) in 
    dest d (s, ail_expr_)

  | ITE (t1, t2, t3) -> 
    let s1, e1_ = cn_to_ail_expr_aux_internal const_prop dts t1 PassBack in
    let s2, e2_ = cn_to_ail_expr_aux_internal const_prop dts t2 PassBack in
    let s3, e3_ = cn_to_ail_expr_aux_internal const_prop dts t3 PassBack in
    let ail_expr_ = A.AilEcond (mk_expr e1_, Some (mk_expr e2_), mk_expr e3_) in
    dest d (s1 @ s2 @ s3, ail_expr_)

  | EachI ((r_start, (sym, bt), r_end), t) -> 
    let rec create_list_from_range l_start l_end = 
      (if l_start > l_end then 
        []
      else
          l_start :: (create_list_from_range (l_start + 1) l_end)
      )
    in 
    let consts = create_list_from_range r_start r_end in
    let cn_consts = List.map (fun i -> Terms.Z (Z.of_int i)) consts in
    let stats_and_exprs = List.map (fun cn_const -> cn_to_ail_expr_aux_internal (Some (sym, cn_const)) dts t PassBack) cn_consts in
    let (ss, es_) = List.split stats_and_exprs in 
    let ail_expr =
      match es_ with
        | (ail_expr1 :: ail_exprs_rest) ->  List.fold_left (fun ae1 ae2 -> A.(AilEbinary (mk_expr ae1, And, mk_expr ae2))) ail_expr1 ail_exprs_rest
        | [] -> failwith "Cannot have empty expression in CN each expression"
    in 
    dest d (List.concat ss, ail_expr)

  (* add Z3's Distinct for separation facts  *)
  | Tuple ts -> failwith "TODO"
  | NthTuple (i, t) -> failwith "TODO"
  | Struct (tag, ms) -> failwith "TODO"
  | StructMember (t, m) -> failwith "TODO"
  | StructUpdate ((t1, m), t2) -> failwith "TODO"
  | Record ms -> failwith "TODO"
  | RecordMember (t, m) -> failwith "TODO"
  | RecordUpdate ((t1, m), t2) -> failwith "TODO"
  (* | DatatypeCons of Sym.t * 'bt term TODO: will be removed *)
  (* | DatatypeMember of 'bt term * Id.t TODO: will be removed *)
  (* | DatatypeIsCons of Sym.t * 'bt term TODO: will be removed *)
  | Constructor (nm, ms) -> failwith "TODO"
  | MemberShift (tag, _, m) -> failwith "TODO"
  | ArrayShift _ -> failwith "TODO"
  | Nil _ -> failwith "TODO"
  | Cons (x, xs) -> failwith "TODO"
  | Head xs -> failwith "TODO"
  | Tail xs -> failwith "TODO"
  | NthList (t1, t2, t3) -> failwith "TODO"
  | ArrayToList (t1, t2, t3) -> failwith "TODO"
  | Representable (ct, t) -> failwith "TODO"
  | Good (ct, t) -> failwith "TODO"
  | Aligned t_and_align -> failwith "TODO"
  | WrapI (ct, t) -> failwith "TODO"
  | MapConst (bt, t) -> failwith "TODO"
  | MapSet (t1, t2, t3) -> failwith "TODO"
  | MapGet (t1, t2) -> failwith "TODO"
  | MapDef ((sym, bt), t) -> failwith "TODO"
  | Apply (sym, ts) -> failwith "TODO"
  | Let ((var, t1), body) -> 
    let s1, e1 = cn_to_ail_expr_aux_internal const_prop dts t1 PassBack in
    let ail_assign = A.(AilSdeclaration [(var, Some (mk_expr e1))]) in
    prefix d (s1 @ [ail_assign]) (cn_to_ail_expr_aux_internal const_prop dts body d)

  | Match (t, ps) -> 
      (* PATTERN COMPILER *)
      (* TODO: Redo with pattern types Christopher has added *)
      failwith "TODO"

  | Cast (bt, t) -> failwith "TODO"
  | _ -> failwith "TODO"

let cn_to_ail_expr_internal
  : type a. (_ Cn.cn_datatype) list -> IT.t -> a dest -> a
  = fun dts cn_expr d ->
    cn_to_ail_expr_aux_internal None dts cn_expr d


type 'a ail_datatype = {
  structs: (C.union_tag * (CF.Annot.attributes * C.tag_definition)) list;
  decls: (C.union_tag * A.declaration) list;
  stats: ('a A.statement) list;
}



let cn_to_ail_datatype ?(first=false) (cn_datatype : cn_datatype) =
  let enum_sym = generate_sym_with_suffix cn_datatype.cn_dt_name in
  let constructor_syms = List.map fst cn_datatype.cn_dt_cases in
  let generate_enum_member sym = 
    let doc = CF.Pp_ail.pp_id ~executable_spec:true sym in 
    let str = CF.Pp_utils.to_plain_string doc in 
    let str = String.uppercase_ascii str in
    Id.id str
  in
  let enum_member_syms = List.map generate_enum_member constructor_syms in
  let attr : CF.Annot.attribute = {attr_ns = None; attr_id = Id.id "enum"; attr_args = []} in
  let attrs = CF.Annot.Attrs [attr] in
  let enum_members = List.map (fun sym -> (sym, (empty_attributes, None, empty_qualifiers, mk_ctype C.Void))) enum_member_syms in
  let enum_tag_definition = C.(UnionDef enum_members) in
  let enum = (enum_sym, (attrs, enum_tag_definition)) in
  let cntype_sym = Sym.fresh_pretty "cntype" in
  let create_member (ctype_, id) =
    (id, (empty_attributes, None, empty_qualifiers, mk_ctype ctype_))
  in
  let cntype_pointer = C.(Pointer (empty_qualifiers, mk_ctype (Struct cntype_sym))) in
  let extra_members tag_type = [
      (create_member (tag_type, Id.id "tag"));
      (create_member (cntype_pointer, Id.id "cntype"))]
  in
  let generate_tag_definition dt_members = 
    let ail_dt_members = List.map (fun (cn_type, id) -> (cn_to_ail_base_type cn_type, id)) dt_members in
    (* TODO: Check if something called tag already exists *)
    let members = List.map create_member ail_dt_members in
    C.(StructDef (members, None))
  in
  let generate_struct_definition (constructor, members) = 
    let lc_constructor_str = String.lowercase_ascii (Sym.pp_string constructor) in
    let lc_constructor = Sym.fresh_pretty lc_constructor_str in
    (lc_constructor, (empty_attributes, generate_tag_definition members))
  in
  let structs = List.map (fun c -> generate_struct_definition c) cn_datatype.cn_dt_cases in
  let structs = if first then 
    let generic_dt_struct = 
      (generic_cn_dt_sym, (empty_attributes, C.(StructDef (extra_members (C.(Basic (Integer (Signed Int_)))), None))))
    in
    let cntype_struct = (cntype_sym, (empty_attributes, C.(StructDef ([], None)))) in
    generic_dt_struct :: cntype_struct :: structs
  else
    (* TODO: Add members to cntype_struct as we go along? *)
    structs
  in
  let union_sym = generate_sym_with_suffix ~suffix:"_union" cn_datatype.cn_dt_name in
  let union_def_members = List.map (fun sym -> 
    let lc_sym = Sym.fresh_pretty (String.lowercase_ascii (Sym.pp_string sym)) in
    create_member (C.(Struct lc_sym), create_id_from_sym ~lowercase:true sym)) constructor_syms in
  let union_def = C.(UnionDef union_def_members) in
  let union_member = create_member (C.(Union union_sym), Id.id "u") in

  let structs = structs @ [(union_sym, (empty_attributes, union_def)); (cn_datatype.cn_dt_name, (empty_attributes, C.(StructDef ((extra_members (C.(Basic (Integer (Enum enum_sym))))) @ [union_member], None))))] in
  {structs = enum :: structs; decls = []; stats = []}



(* TODO: Finish with rest of function - maybe header file with A.Decl_function (cn.h?) *)
let cn_to_ail_function_internal (fn_sym, (def : LogicalFunctions.definition)) cn_datatypes = 
  let ail_func_body =
  match def.definition with
    | Def it ->
      let ss = cn_to_ail_expr_internal cn_datatypes it Return in
      List.map mk_stmt ss
    | _ -> [] (* TODO: Other cases *)
  in
  let ret_type = cn_to_ail_base_type (bt_to_cn_base_type def.return_bt) in
  let params = List.map (fun (sym, bt) -> (sym, mk_ctype (cn_to_ail_base_type (bt_to_cn_base_type bt)))) def.args in
  let (param_syms, param_types) = List.split params in
  let param_types = List.map (fun t -> (empty_qualifiers, t, false)) param_types in
  (* Generating function declaration *)
  let decl = (fn_sym, (Cerb_location.unknown, empty_attributes, A.(Decl_function (false, (empty_qualifiers, mk_ctype ret_type), param_types, false, false, false)))) in
  (* Generating function definition *)
  let def = (fn_sym, (Cerb_location.unknown, 0, empty_attributes, param_syms, mk_stmt A.(AilSblock ([], ail_func_body)))) in
  (decl, def)

(* let cn_to_ail_assertion assertion cn_datatypes = 
  match assertion with
  | CN_assert_exp e_ -> 
      (* TODO: Change type signature to keep declarations too *)
      let ss = cn_to_ail_expr_aux cn_datatypes e_ Assert in 
      List.map mk_stmt ss
  | CN_assert_qexp (ident, bTy, e1, e2) -> failwith "TODO" *)


(* let cn_to_ail_condition cn_condition type_map cn_datatypes = 
  match cn_condition with
  | CN_cletResource (loc, name, resource) -> ([A.AilSskip], None) (* TODO *)
  | CN_cletExpr (_, name, expr) -> 
    (* TODO: return declarations too *)
    let ss = cn_to_ail_expr_internal cn_datatypes expr (AssignVar name) in
    let sfb_type = SymTable.find type_map name in
    let basetype = SurfaceBaseTypes.to_basetype sfb_type in
    let cn_basetype = bt_to_cn_base_type basetype in
    let ctype = cn_to_ail_base_type cn_basetype in
    (ss, Some (mk_ctype ctype))
  | CN_cconstr (loc, constr) -> 
    let ail_constr = cn_to_ail_assertion constr cn_datatypes in
    let ail_stats_ = List.map rm_stmt ail_constr in
    (ail_stats_, None) *)