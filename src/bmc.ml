(*
 * BMC STUFF
 *
 * BMC_utils:
 *    - pretty printers
 * BMC_normalize: 
 *    - normalize core file
 *)

open Global_ocaml
open Core
open Core_ctype
open Lem_pervasives
open Z3
open Z3.Arithmetic

open Mem
open Ocaml_mem
open Bmc_utils
open Bmc_normalize
open Bmc_sorts

open Ocaml_implementation
open Pp_core
(* ========== Type definitions ========== *)

type ksym_table = (int, Expr.expr) Pmap.map

(* Pointer state: 
 * For every variable of Core type pointer, 
 *    - Map it to set of addresses it refers to
 *    - int (core symbol) -> PointerState = Set of addresses
 *
 * An address consists of a unique allocation
 *    - fun: is_eq (check if same address)
 *    - map from int to symbol?
 *    - type ? 
 *
 * For let x: pointer = Create...
 *    - Create a new address
 *    - Don't insert into bmc_state?
 *    - Add it to pointer state
 *    - "x: SMT ptr sort" = address
 *
 * For let y: pointer = x
 *    - pointer state
 *    - "y : SMT ptr sort" = x (address)
 *
 * For store:
 *    - create fresh var for the address and assign it to a value
 *
 * For load:
 *    - lookup address variable points to, assign it current value in z3
 *
 * bmc_state:
 *    - map from address -> cur_value (int?)
 *    - pointer state: symbol -> PointerState map
 *)


(* "Symbol: @int_int" *)
type kbmc_address = {
  addr        : Address.addr;
  seq_ctr     : int ref;
  hist        : ((int, Expr.expr) Pmap.map) ref;
  sort        : Sort.sort
}

type kheap = (Address.addr, Expr.expr) Pmap.map

type bmc_state = {
  ctx         : context;
  solver      : Solver.solver;
  sym_table   : ksym_table ref;
  sym_supply  : ksym_supply ref;

  (* Make fresh allocations using Address.mk_fresh *)
  addr_gen    : Address.addr ref;

  (* Map from int -> address *)
  addr_map    : (Address.addr, kbmc_address) Pmap.map ref;

  (* ------------- *)
  
  (* Map from address to Z3 symbol representing value *)
  heap        : (Address.addr, Expr.expr) Pmap.map;

  (* Map from Core symbol to set of addresses *)
  (*
  ptr_map     : (int, Address.addr list) Pmap.map;
  *)

  vcs         : Expr.expr list;
}

(* TODO: get rid of this. unnecessary *)
type bmc_ret = Expr.expr option


(* PPrinters *)

(*
let print_ptr_map (map : (int, Address.addr list) Pmap.map) =
  Pmap.mapi (fun k v-> (Printf.printf "%d -> " k;
            List.iter(fun s -> Printf.printf "%s " (Address.to_string s)) v)) map
*)

let print_heap (heap: (Address.addr, Expr.expr) Pmap.map) =
  Printf.printf "HEAP\n";
  Pmap.iter (fun k v-> (Printf.printf "E: %s -> %s\n" 
                  (Address.to_string k) (Expr.to_string v))) heap ;
  Printf.printf "END_HEAP\n"





(* ========== BMC ========== *)

let check_solver (solver: Solver.solver) =
  begin
  let status = Solver.check solver [] in
  Printf.printf "Status: %s\n" (Solver.string_of_status status);
  begin
  if status = UNKNOWN then
    Printf.printf "Unknown: %s\n" (Solver.get_reason_unknown solver)
  end;
  if status != SATISFIABLE then
    Printf.printf "NOT SAT :) \n"
  else
    begin 
    Printf.printf "SAT :( \n";
    let model = Solver.get_model solver in
      match model with
      | Some m -> Printf.printf "Model: \n%s\n" (Model.to_string m)
      | None -> Printf.printf "No model\n"
    ;
    end
  end

let get_last_seqnum (ctx: context) (bmc_address : kbmc_address) =
  (!(bmc_address.seq_ctr))

let mk_next_seq_symbol (ctx: context) (bmc_address : kbmc_address) =
  bmc_address.seq_ctr := succ (!(bmc_address.seq_ctr));
  (mk_sym ctx ("@" ^ (Address.to_string (bmc_address.addr)) ^ "_" ^ 
              (string_of_int (!(bmc_address.seq_ctr)))),
   get_last_seqnum(ctx) (bmc_address))


let ctor_to_z3 (state: bmc_state) (ctor: typed_ctor) 
               (pes: Expr.expr list) (sort: Sort.sort) =
  match ctor with
  | Cnil _ (* empty list *)
  | Ccons -> 
      assert false
  | Ctuple ->
      assert (List.length pes = Tuple.get_num_fields sort);
      let mk_decl = Tuple.get_mk_decl sort in
      FuncDecl.apply mk_decl pes
  | Carray ->
      assert false(* C array *)
  | Civmax ->
      assert false
  | Civmin ->
      assert false
  | Civsizeof ->
      assert false (* sizeof value *)
  | Civalignof ->
      assert false(* alignof value *)
  | CivCOMPL ->
      assert false (* bitwise complement *)
  | CivAND ->
      assert false (* bitwise AND *)
  | CivOR ->
      assert false (* bitwise OR *)
  | CivXOR ->
      assert false (* bitwise XOR *) 
  | Cspecified ->
      assert (List.length pes = 1);

      let expr = List.hd pes in
        (* TODO: Do generically... *)
        if (Sort.equal sort (LoadedInteger.mk_sort state.ctx)) then
          LoadedInteger.mk_loaded state.ctx expr
        else if (Sort.equal sort (LoadedPointer.mk_sort state.ctx)) then
          (
          Printf.printf "TODO: pointers\n";
          LoadedPointer.mk_loaded state.ctx expr 
          )
        else 
          assert false
  | Cunspecified (* unspecified value *) ->
      if (Sort.equal sort (LoadedInteger.mk_sort state.ctx)) then
        LoadedInteger.mk_unspec state.ctx 
      else if (Sort.equal sort (LoadedPointer.mk_sort state.ctx)) then
        LoadedPointer.mk_unspec state.ctx 
      else
        assert false
  | Cfvfromint (* cast integer to floating value *)
  | Civfromfloat (* cast floating to integer value *) ->
      assert false

(* core_base_type to z3 sort *)
let rec cbt_to_z3 (state: bmc_state) (cbt : core_base_type) : Sort.sort =
  let ctx = state.ctx in
  match cbt with
   | BTy_unit  -> 
        UnitSort.mk_sort ctx
   | BTy_boolean ->
        Boolean.mk_sort ctx
   | BTy_ctype -> 
        (* TODO *)
        ctypeSort ctx
   | BTy_list _ -> assert false
   | BTy_tuple cbt_list ->
       (*
       let tmp = Tuple.mk_sort ctx (mk_sym ctx "(ctype)") [(mk_sym ctx "#1")]
       [(tmpSort ctx)] in

       Printf.printf "XX %s\n" (Sort.to_string tmp);
       Printf.printf "XX %d\n" (Tuple.get_num_fields tmp);
       assert false
       *)
        let sort_to_string = fun t -> pp_to_string
                              (Pp_core.Basic.pp_core_base_type t) in
        let sort_name = sort_to_string cbt in
        let sort_symbol = mk_sym state.ctx sort_name in

        let sym_list = List.mapi 
            (fun i _ -> mk_sym state.ctx 
                  ( "#" ^ (string_of_int i)))
            cbt_list in
        let sort_list = List.map (fun t -> cbt_to_z3 state t) cbt_list in
        Tuple.mk_sort ctx sort_symbol sym_list sort_list 
   | BTy_object obj_type ->
       core_object_type_to_z3_sort ctx obj_type
   | BTy_loaded obj_type ->
       (* TODO do generically *)
       begin
         match obj_type with
          | OTy_integer -> 
              LoadedInteger.mk_sort ctx
          | OTy_pointer -> 
              LoadedPointer.mk_sort ctx
          | _ -> assert false
       end

let initial_bmc_state (supply : ksym_supply) : bmc_state = 
  let cfg = [("model", "true"); ("proof", "false")] in
  let ctx = mk_context cfg in
  {
    ctx = ctx;
    solver = Solver.mk_solver ctx None;
    sym_table = ref (Pmap.empty Pervasives.compare);
    sym_supply = ref supply;

    addr_gen = ref (Address.mk_initial);
    addr_map = ref (Pmap.empty Pervasives.compare);

    heap = Pmap.empty Pervasives.compare;
    (*
    ptr_map = Pmap.empty Pervasives.compare;
    *)

    vcs = []
  }

(*
let add_func_constraints (st : bmc_state) =
  Solver.add st.solver (sizeof_ibty_goals st.ctx) ;
  Solver.add st.solver (ivmin_goals st.ctx) 
*)

let integer_value_to_z3 (ctx: context) ival =
  let maybe_ival = eval_integer_value ival in
  match maybe_ival with
  | None -> assert false
  | Some i -> Integer.mk_numeral_i ctx (Nat_big_num.to_int i)


let object_value_to_z3 (ctx: context) = function
  | OVinteger ival -> integer_value_to_z3 ctx ival
  | OVfloating _
  | OVpointer _
  | OVcfunction _
  | OVarray _ 
  | OVstruct _
  | OVunion _ 
  | OVcomposite _ ->
      assert false

let ctype_to_z3 (ctx: context) (ctype: ctype0) =
  let _ =  (* TODO: safeguard for unimplemented stuff *)
    match ctype with
    | Void0 -> assert false
    | Basic0 (Integer i) ->
        begin
        match i with
        | Char -> assert false
        | Bool -> ()
        | Unsigned ibty (* Fall through *)
        | Signed ibty -> 
          begin
          match ibty with
          | Ichar | Short | Int_ | Long | LongLong | Intmax_t | Intptr_t -> ()
          | _ -> assert false
          end
        | _ -> assert false
        end
    | _ -> assert false
  in
  ctype_to_expr ctype ctx


let rec value_to_z3 (ctx: context) (cval: value) (typ: core_base_type) =
  match cval with
  | Vunit -> UnitSort.mk_unit ctx
  | Vtrue -> Boolean.mk_true ctx
  | Vfalse -> Boolean.mk_false ctx
  | Vlist (_, cvals) ->
      assert false;
  | Vtuple cvals ->
      assert false
  | Vctype ty ->
      ctype_to_z3 ctx ty      
  | Vobject oval ->
      object_value_to_z3 ctx oval
  | Vloaded lval ->
      match lval with
      | LVspecified ov  ->
          begin
          match ov with
          | OVinteger ival ->
            let iexpr = integer_value_to_z3 ctx ival in
            LoadedInteger.mk_loaded ctx iexpr
          | _ -> assert false
          end
      | LVunspecified _ -> 
          (* TODO *)
          begin
          match typ with
          | BTy_loaded OTy_integer -> LoadedInteger.mk_unspec ctx
          | _ -> assert false 
          end

let binop_to_constraints (ctx: context) (pe1: Expr.expr) (pe2: Expr.expr) = function
  | OpAdd -> Arithmetic.mk_add ctx [ pe1; pe2 ]
  | OpSub -> Arithmetic.mk_sub ctx [ pe1; pe2 ]
  | OpMul -> Arithmetic.mk_mul ctx [ pe1; pe2 ]
  | OpDiv -> Arithmetic.mk_div ctx pe1 pe2
  | OpRem_t -> assert false
  | OpRem_f -> Integer.mk_mod ctx pe1 pe2 (* TODO: Flooring remainder? *)
  | OpExp -> assert false
  | OpEq -> Boolean.mk_eq ctx pe1 pe2   
  | OpLt -> Arithmetic.mk_lt ctx pe1 pe2
  | OpLe -> Arithmetic.mk_le ctx pe1 pe2 
  | OpGt -> Arithmetic.mk_gt ctx pe1 pe2
  | OpGe -> Arithmetic.mk_ge ctx pe1 pe2
  | OpAnd -> Boolean.mk_and ctx [ pe1; pe2 ] 
  | OpOr -> Boolean.mk_or ctx [ pe1; pe2 ]


let mk_eq_expr (state: bmc_state) (m_sym: ksym option) 
               (ty : core_base_type) (bmc_expr : bmc_ret) =
  match m_sym with
  | None -> Boolean.mk_true state.ctx (* Do nothing *)
  | Some sym -> 
      let sym_id = symbol_to_int sym in
      let pat_sym = symbol_to_z3 state.ctx sym in
      (* TODO: case on bmc_expr instead *)
      begin
      match ty with
      | BTy_unit -> assert false
      | BTy_ctype (* Fall through *)
      | BTy_boolean -> 
          (* TODO: duplicated code *)
          let sort = cbt_to_z3 state ty in
          let expr_pat = Expr.mk_const state.ctx pat_sym sort in
          state.sym_table := Pmap.add sym_id expr_pat (!(state.sym_table));
          begin
          match bmc_expr with
          | Some expr ->
              (Boolean.mk_eq state.ctx expr_pat expr)
          | _ -> assert false
          end
      | BTy_tuple ty_list -> 
          assert false
          (*
          (* TODO: duplicate *)
          begin
          match bmc_expr with
          | Some expr ->
              let sort = cbt_to_z3 state ty in
              let expr_pat = Expr.mk_const state.ctx pat_sym sort in
              state.sym_table := Pmap.add sym_id expr_pat (!(state.sym_table));
              (Boolean.mk_eq state.ctx expr_pat expr)
          | _ -> assert false
          end
          *)
      | BTy_list _ -> assert false
      | BTy_object OTy_pointer -> 
          (* Pointer equality *)
          begin
          match bmc_expr with
          (*
          | BmcAddress addr ->
              assert false; 
              (* let x: pointer = Create... *)
              (* TODO: Z3 equality of address *)

              (* Add symbol to sym_table: x -> Pointer x *)
              (* |x|: PointerSort *)
              let expr_pat = Expr.mk_const state.ctx pat_sym
                             (PointerSort.mk_sort state.ctx)
              in
              state.sym_table := Pmap.add sym_id expr_pat (!(state.sym_table));
              (* Create concrete pointer value with addr *)
              
              let new_addr = PointerSort.mk_addr state.ctx addr.addr in

              Printf.printf "TODO!!! \n";
              Boolean.mk_eq state.ctx 
                (PointerSort.get_addr state.ctx expr_pat)
                (PointerSort.mk_ptr state.ctx new_addr)   
              , state

              (* Map sym_id to address *)
              (* TODO *)
              (* 
              Boolean.mk_true state.ctx, 
                ({state with ptr_map = (Pmap.add sym_id [ addr.addr ]
                                      state.ptr_map)})
*)
              *)
          | Some expr ->
              assert (Sort.equal (Expr.get_sort expr) 
                                 (PointerSort.mk_sort state.ctx));
              (*
              let addr_list = 
                match Pmap.lookup ptr_id state.ptr_map with
                | Some z -> z
                | None -> assert false
              in
              *)
              (* Create a new symbol for the pattern pointer *)
              let sym_id = symbol_to_int sym in
              let pat_sym = symbol_to_z3 state.ctx sym in
              let expr_pat = 
                  Expr.mk_const state.ctx pat_sym (PointerSort.mk_sort state.ctx)
              in
              (* Add to sym table *)
              state.sym_table := Pmap.add sym_id expr_pat (!(state.sym_table));

              (* Assert that get_addr expr_pat == get_addr expr *)
              Boolean.mk_eq state.ctx 
                (PointerSort.get_addr state.ctx expr_pat)
                (PointerSort.get_addr state.ctx expr)   
          | _ -> assert false
          end
      | BTy_object _ -> 
          (* TODO: duplicated *)
          begin
          match bmc_expr with
          | Some expr ->
              let sort = cbt_to_z3 state ty in
              let expr_pat = Expr.mk_const state.ctx pat_sym sort in
              state.sym_table := Pmap.add sym_id expr_pat (!(state.sym_table));
              (Boolean.mk_eq state.ctx expr_pat expr)
          | _ -> assert false
          end
      | BTy_loaded cot ->
          (* TODO duplicated code: should case on bmc_expr instead maybe *)
          let pat_symbol = symbol_to_z3 state.ctx sym in
          let z3_sort = cbt_to_z3 state ty in
          let expr_pat = Expr.mk_const state.ctx pat_symbol z3_sort in
          state.sym_table := Pmap.add (symbol_to_int sym) expr_pat 
                                      (!(state.sym_table));
          begin
          match bmc_expr with
          | None -> Boolean.mk_true state.ctx
          | Some expr ->
              begin
              (Boolean.mk_eq state.ctx expr_pat expr)
              end
          end
        end

let rec mk_eq_pattern (state: bmc_state) (pattern: typed_pattern)
                      (ty: core_base_type) (bmc_expr: bmc_ret) =
  match pattern with
  | CaseBase(maybe_sym, typ) ->
      mk_eq_expr state maybe_sym typ bmc_expr
  | CaseCtor(ctor, patlist) -> 
      match ctor with
      | Cnil _
      | Ccons -> 
          assert false
      | Ctuple ->
          begin
          match ty with
          | BTy_tuple ty_list -> 
              (* let z3_sort = cbt_to_z3 state ty in *)
              let expr = ( match bmc_expr with 
                          | Some expr -> expr
                          | _ -> assert false) in
              let exprList = Expr.get_args expr in
              assert (Expr.get_num_args expr = List.length patlist);
              Printf.printf "Args: %d\n" (Expr.get_num_args expr);

              let zipped = List.combine ty_list patlist in
              Boolean.mk_and state.ctx 
                (List.mapi (fun i (ty, pat) -> 
                  mk_eq_pattern state pat ty 
                  (Some (List.nth exprList i))) zipped
                )

              (* TODO: get rid of fold *)
            
              (*
              let indices = List.mapi (fun i v -> i) ty_list in
              let zipped = List.combine ty_list patlist in
              let fields = Tuple.get_field_decls z3_sort in
              assert (List.length fields = List.length patlist);

              List.fold_left2 (fun (exp, s) (ty, pat) i ->
                let (e, s') = mk_eq_pattern s pat ty 
                              (BmcZ3Expr (Some (get_field i))) in
                (Boolean.mk_and s'.ctx [e; exp], s')
              ) (Boolean.mk_and state.ctx [], state) zipped indices;
              *)
          | _ -> assert false
          end
      | Carray (* C array *)
      | Civmax (* max integer value *)
      | Civmin (* min integer value *)
      | Civsizeof (* sizeof value *)
      | Civalignof (* alignof value *)
      | CivCOMPL (* bitwise complement *)
      | CivAND (* bitwise AND *)
      | CivOR (* bitwise OR *)
      | CivXOR -> assert false (* bitwise XOR *)
      | Cspecified -> (* non-unspecified loaded value *)
          begin
            match ty with
            | BTy_loaded OTy_integer -> 
                (* TODO: duplicated code *)
                begin
                match patlist with
                | (CaseBase(maybe_sym, BTy_object OTy_integer):: []) -> 
                    let expr = (match bmc_expr with
                      | Some expr -> expr
                      | _ -> assert false ) in
                    (* Guard by ensuring expr is constructed with loaded *)
                    let is_loaded = LoadedInteger.is_loaded state.ctx expr in
                    let loaded_value = LoadedInteger.get_loaded_value state.ctx expr

                    in     
                    let eq_expr = mk_eq_expr state maybe_sym
                                         (BTy_object OTy_integer) 
                                         (Some loaded_value) in
                    let guarded = Boolean.mk_implies state.ctx is_loaded eq_expr in
                    (guarded )
                | _ -> assert false
                end
          | BTy_loaded OTy_pointer -> 
                begin
                match patlist with
                | (CaseBase(maybe_sym, BTy_object OTy_pointer):: []) -> 
                    (* TODO: duplicated code *)
                    let expr = (match bmc_expr with
                      | Some expr -> expr
                      | _ -> assert false ) in
                    let is_loaded = LoadedPointer.is_loaded state.ctx expr in

                    let loaded_value = LoadedPointer.get_loaded_value state.ctx expr
                    in
                    let (eq_expr) = mk_eq_expr state maybe_sym
                                         (BTy_object OTy_pointer) 
                                         (Some loaded_value) in
                    let guarded = Boolean.mk_implies state.ctx is_loaded eq_expr
                    in
                    (guarded )
                | _ -> assert false
                end

          | _ -> assert false
        end
      | Cunspecified (* unspecified value *)
      | Cfvfromint (* cast integer to floating value *)
      | Civfromfloat (* cast floating to integer value *) ->
          assert false

let concat_vcs (state: bmc_state)
               (vc1: Expr.expr list)
               (vc2: Expr.expr list)
               (guard: Expr.expr) =
  let new_vc1 = List.map (fun vc -> Boolean.mk_implies state.ctx guard vc) vc1 in
  let new_vc2 = List.map (fun vc -> Boolean.mk_implies state.ctx 
                                        (Boolean.mk_not state.ctx guard) vc) vc2 in
  new_vc1 @ new_vc2


let rec bmc_pexpr (state: bmc_state) 
                  (Pexpr(bTy, pe) as pexpr : typed_pexpr) : 
                    Expr.expr option * bmc_state =
  let (z_pe, state') = match pe with
    | PEsym sym ->
        pp_to_stdout (Pp_core.Basic.pp_pexpr pexpr);
        Printf.printf "\n";
        let sym_expr = 
          match Pmap.lookup (symbol_to_int sym) (!(state.sym_table)) with
          | Some z -> z
          | None -> assert false
        in
        Some sym_expr, state
    | PEimpl _ -> assert false
    | PEval cval ->
        (Some (value_to_z3 state.ctx cval bTy), state)
    | PEconstrained _ ->
        assert false
    | PEundef _ ->
        let new_vcs = (Boolean.mk_false state.ctx) :: state.vcs in
        let new_state = {state with vcs = new_vcs} in
        None, new_state
    | PEerror _ -> 
        let new_vcs = (Boolean.mk_false state.ctx) :: state.vcs in
        let new_state = {state with vcs = new_vcs} in
        None, new_state
    | PEctor (ctor, pelist) -> 
        let sort = cbt_to_z3 state bTy in
        (* TODO: state needs to be propagated *) 
        (* BMC each expression *)
        let z3_pelist_tmp = List.map (fun pe -> bmc_pexpr state pe) pelist in
        let new_vcs = List.concat (List.map (fun (_, st) -> st.vcs) z3_pelist_tmp) in
        begin
        if ((List.exists (fun (a, _) -> match a with 
          | None -> true     
          | _ -> false)) z3_pelist_tmp)
        then

          (* TODO: extra vcs are unnecessary, for debugging *)
          None, ({state with vcs = ((Boolean.mk_false state.ctx) :: state.vcs)})
        else
          begin
            let z3_pelist = List.map (fun (a, _) -> match a with
                | None -> assert false
                | Some x -> x) z3_pelist_tmp in  
            let ret = ctor_to_z3 state ctor z3_pelist sort in
            Some ret,  state
          end
        end
    | PEcase (pe, ((pat1, pe1):: (pat2, pe2):: [])) -> 
        Printf.printf "TODO: PEcase";
        (* TODO: special case for now. c1 else c2 *)
        let (Pexpr(pe_type, pe_)) = pe in
        let (maybe_pe, st) = bmc_pexpr state pe in 
        let (eq_expr) = 
            mk_eq_pattern st pat1 pe_type (maybe_pe) in
        let (maybe_pe1, st1) = bmc_pexpr ({state with vcs = []}) pe1 in
        let (maybe_pe2, st2) = bmc_pexpr ({state with vcs = []}) pe2 in
        Solver.add state.solver [ eq_expr ];
        begin
        match (maybe_pe, maybe_pe1, maybe_pe2) with
        | (Some a, Some b, Some c) -> 
            let new_vc = st.vcs @ 
                         (concat_vcs state st1.vcs st2.vcs eq_expr) in
            Some (Boolean.mk_ite st.ctx eq_expr b c), ({st with vcs = new_vc})
        | _ -> assert false
        end
    | PEcase _ -> 
        Printf.printf "TODO: Properly handle PEcase\n";
        assert false
    | PEarray_shift _ -> assert false
    | PEmember_shift _ -> assert false
    | PEnot pe1 -> 
        let (maybe_pe1, state1) = bmc_pexpr state pe1 in  
        begin
          match maybe_pe1 with
          | Some x -> Some (Boolean.mk_not state.ctx x), state1
          | _ -> None, state1
        end
    | PEop (bop, pe1, pe2) ->
        let (maybe_pe1, state1) = bmc_pexpr state pe1 in
        let (maybe_pe2, state2) = bmc_pexpr state1 pe2 in
        begin
          match (maybe_pe1, maybe_pe2) with
          | (Some x, Some y) ->
              Some (binop_to_constraints (state2.ctx) x y bop), state2
          | _ -> None, state2
        end
    | PEstruct _
    | PEunion _ -> assert false
    | PEcall (Sym (Symbol(_, Some "conv_loaded_int")), (typ :: pe :: [])) -> 
        assert false;
        (* TODO: special case conv_loaded_int *)
        (* TODO: range check *)
        Printf.printf "TODO: conv_loaded_int\n";
        bmc_pexpr state pe 
    | PEcall (Sym (Symbol(_, Some "conv_int")), (typ :: pe :: [])) -> 
        assert false;
        (* TODO: special case conv_loaded_int *)
        (* TODO: range check *)
        Printf.printf "TODO: conv_int\n";
        bmc_pexpr state pe 

    | PEcall (Sym (Symbol(_, Some "catch_exceptional_condition")), (typ :: pe :: [])) -> 
        assert false;
        (* TODO: special case conv_loaded_int *)
        (* TODO: range check *)
        Printf.printf ("TODO: catch_exceptional_condition\n");
        bmc_pexpr state pe 
    | PEcall (Sym sym, _) -> 
        assert false

    | PEcall _ -> 
        Printf.printf ("TODO: implementation_constant treated as undef: ");
        pp_to_stdout (Pp_core.Basic.pp_pexpr pexpr);
        print_string"\n";
        let new_vcs = (Boolean.mk_false state.ctx) :: state.vcs in
        let new_state = {state with vcs = new_vcs} in
        None, new_state

    | PElet (CaseBase(Some sym, pat_ty), pe1, pe2) ->
        let (Pexpr(pat_type, _)) = pe1 in
        let z3_sort = cbt_to_z3 state pat_type in

        let (maybe_pe1, state1) = bmc_pexpr state pe1 in
        (* Add new symbol to sym_table *)
        let pat_symbol = symbol_to_z3 state.ctx sym in
        let expr_pat = Expr.mk_const (state.ctx) pat_symbol z3_sort in
        state1.sym_table := Pmap.add (symbol_to_int sym) expr_pat 
                                     (!(state1.sym_table));

        begin
          match maybe_pe1 with
          | Some pe -> 
              Solver.add (state1.solver) 
                                  [ Boolean.mk_eq (state1.ctx) expr_pat pe ]
          | None -> ()
        end;

        let (maybe_pe2, state2) = bmc_pexpr state1 pe2 in
        maybe_pe2, state2
    | PElet (CaseBase(None, pat_ty), pe1, pe2) ->
        let (maybe_pe1, state1) = bmc_pexpr state pe1 in
        let (maybe_pe2, state2) = bmc_pexpr state1 pe2 in
        maybe_pe2, state2
       
    | PElet (CaseCtor(ctor, patList), pe1, pe2) ->
        let (Pexpr(pat_type, _)) = pe1 in
        
        pp_to_stdout (Pp_core.Basic.pp_pexpr pe1);
        Printf.printf "PElet\n";
        let (maybe_pe1, state1) = bmc_pexpr state pe1 in

        Printf.printf "PElet1\n";
        let (eq_expr) = 
          mk_eq_pattern state1 (CaseCtor(ctor, patList)) 
                     pat_type maybe_pe1 in

        Printf.printf "PElet2\n";
        Solver.add state1.solver [ eq_expr ];

        Printf.printf "PElet3\n";
        bmc_pexpr state1 pe2
    | PEif (pe1, pe2, pe3) ->
        let (maybe_pe1, s1) = bmc_pexpr state pe1 in
        let (maybe_pe2, s2) = bmc_pexpr ({state with vcs = []}) pe2 in
        let (maybe_pe3, s3) = bmc_pexpr ({state with vcs = []}) pe3 in
        begin
          match (maybe_pe1, maybe_pe2, maybe_pe3) with
          | (None, _, _)  (* fall through *)
          | (Some _, None, None) ->
              (* Extra vcs for debugging *)
              None, ({s1 with vcs = (Boolean.mk_false s3.ctx) :: s1.vcs}) 
          | (Some a, Some b, None) ->
              let vc_guard = a in
              let new_vc = s1.vcs @ s2.vcs in
              Some b, ({s1 with vcs = vc_guard :: new_vc})
          | (Some a, None, Some b) ->
              let vc_guard = Boolean.mk_not s3.ctx a in
              let new_vc = s1.vcs @ s3.vcs in
              Some b, ({s1 with vcs = vc_guard :: new_vc})
          | (Some a, Some b, Some c) ->
              let new_vc = s1.vcs @ (concat_vcs state s2.vcs s3.vcs a) in
              Some (Boolean.mk_ite s3.ctx a b c), ({s1 with vcs = new_vc})
        end
    | PEis_scalar _ ->
        assert false
    | PEis_integer _ ->
        assert false
    | PEis_signed _ ->
        assert false
    | PEis_unsigned _ ->
        assert false
    | PEstd (str, pe) ->
        bmc_pexpr state pe;
  in
    z_pe, state'

let mk_bmc_address (addr : Address.addr) (sort: Sort.sort) =
  {addr = addr; 
   seq_ctr = ref 0; 
   hist = ref (Pmap.empty Pervasives.compare);
   sort = sort
  }

let ctype_to_sort (state: bmc_state) ty =
  match ty with
  | Void0 -> assert false
  | Basic0 ty -> 
    begin
    match ty with
    | Integer (Signed Int_) ->
        (* TODO Bit vector? *)
        LoadedInteger.mk_sort state.ctx
    | Integer _ -> assert false
    | Floating fTy -> assert false
    end
  | Array0 _ -> assert false
  | Function0 _ -> assert false
  | Pointer0 _ -> 
      LoadedPointer.mk_sort state.ctx 
  | Atomic0 _ -> assert false 
  | Struct0 _ 
  | Union0 _
  | Builtin0 _ -> assert false

let bmc_paction (state: bmc_state)
                (Paction(_, action) : 'a typed_paction) =
  let Action(_, _, action_) = action in
  match action_ with
  | Create (pe1, Pexpr(BTy_ctype, PEval (Vctype ty)), _) ->
      (* Ctype *)
      let sort = ctype_to_sort state ty in
      (* TODO: turns all integers into loaded integers *)
      (* Create a new addr *)
      let addr = Address.mk_fresh state.addr_gen in
      let bmc_addr : kbmc_address = mk_bmc_address addr sort in

      (* Add address to addr_map *)
      state.addr_map :=  Pmap.add addr bmc_addr (!(state.addr_map));

      (* Set it to an initial unspecified value @a_1 *)
      let (new_sym, seq_num) = mk_next_seq_symbol state.ctx bmc_addr in
      let initial_value = Expr.mk_const state.ctx new_sym sort in
      let new_heap = Pmap.add addr initial_value state.heap in

      (* Try: create a new pointer and return it instead *)
      let new_ptr = PointerSort.mk_ptr state.ctx 
                    (Address.mk_expr state.ctx addr) in
      Some new_ptr, ({state with heap = new_heap})

  | Create _ -> assert false
  | Alloc0 _ ->
      assert false
  | Kill _ ->
      (* TODO *)
      Printf.printf "TODO: KILL unit\n";
      None, state
  | Store0 (Pexpr(BTy_ctype, PEval (Vctype ty)), Pexpr(_, PEstd (_, Pexpr(_, PEsym sym))), p_value, _) 
    (* Fall through *)
  | Store0 (Pexpr(BTy_ctype, PEval (Vctype ty)), Pexpr(_, PEsym sym), p_value, _) ->
      (* Overview:
         For each possible address, 
         if (get_addr sym == @a) @a_i = p_value; @a_i = (cur value)
         update heap: @a_i

         This is extremely naiive and generates equations for every created
         address. 

         Need to check sorts are the same.
       *)
      let sort = ctype_to_sort state ty in 

      let (maybe_value, state1) = bmc_pexpr state p_value in
      
      let value = match maybe_value with | None -> assert false | Some x -> x in
      let sym_id = symbol_to_int sym in
      let z3_sym = match (Pmap.lookup sym_id (!(state.sym_table))) with
        | None -> assert false
        | Some x -> x
      in
      let update = (fun addr bmc_addr heap ->
            if (not(Sort.equal (bmc_addr.sort) sort)) then
              heap
            else
              begin
                let cur_value = match (Pmap.lookup addr heap) with
                    | None -> assert false
                    | Some x -> x in
                (* Create a fresh value *)
                let (new_sym, seq_num) = mk_next_seq_symbol state.ctx bmc_addr in
                let new_expr = Expr.mk_const state.ctx new_sym bmc_addr.sort in
                (* get_addr sym == @a *)
                let addr_eq = Boolean.mk_eq state.ctx 
                      (PointerSort.get_addr state.ctx z3_sym)
                      (Address.mk_expr state.ctx addr) in 
                (* @a_i = p_value *)
                let new_eq = Boolean.mk_eq state.ctx new_expr value in

                (* @a_i = (cur value) *)
                let old_eq = Boolean.mk_eq state.ctx new_expr cur_value in

                let ite = Boolean.mk_ite state.ctx addr_eq new_eq old_eq in
                Solver.add state.solver [ ite ];

                (* Update heap *)
                let new_heap = Pmap.add addr new_expr heap in

               (* Return new heap *) 
                new_heap
              end
        )
      in
      let new_heap = Pmap.fold update (!(state.addr_map)) state.heap in
      None, ({state1 with heap = new_heap})
       
  | Store0 _ -> assert false
  | Load0 (Pexpr(BTy_ctype, PEval (Vctype ty)), Pexpr(_, PEsym sym), _) -> 
      (* Overview: for each address, look up value in the heap.
       * Generate equation 
          (get_addr sym == addr => heap_value)
         TODO: assert that address is equal to something...
       * Return conjunction
       *)
       let sort = ctype_to_sort state ty in
       let sym_id = symbol_to_int sym in
       let z3_sym = match (Pmap.lookup sym_id (!(state.sym_table))) with
         | None -> assert false
         | Some x -> x
       in
       let ret_value = Expr.mk_fresh_const state.ctx
              ("load_" ^ (symbol_to_string sym)) sort in
       assert (Sort.equal (Expr.get_sort z3_sym) 
                          (PointerSort.mk_sort state.ctx));
       let iterate = (fun addr bmc_addr (expr_list, addr_list) ->
          let cur_value = match (Pmap.lookup addr state.heap) with
              | None -> assert false
              | Some x -> x in
          if (Sort.equal (Expr.get_sort cur_value) sort) then
            begin
              let addr_expr = Address.mk_expr state.ctx addr in
              let addr_eq_expr = Boolean.mk_eq state.ctx
                  (PointerSort.get_addr state.ctx z3_sym)
                  addr_expr in
              let impl_expr = Boolean.mk_implies state.ctx 
                    addr_eq_expr 
                    (Boolean.mk_eq state.ctx ret_value cur_value) in
              (impl_expr :: expr_list, addr_eq_expr :: addr_list)
            end
          else 
            (expr_list, addr_list)
       ) in
       Printf.printf "ENTER\n";
       let (expr_eqs, addr_eqs) = Pmap.fold iterate (!(state.addr_map)) 
                                        ([], []) in
       
       Printf.printf "EXIT\n";
       let ret = Boolean.mk_and state.ctx expr_eqs in
       let new_vc = Boolean.mk_or state.ctx addr_eqs in
       Solver.add state.solver [ ret ];
       (*
       Printf.printf "HERE 1 %s\n" (Expr.to_string ret);
       Printf.printf "HERE 2 %s\n" (Expr.to_string new_vc);
       *)
       Some ret_value, ({state with vcs = (new_vc) :: state.vcs})

  | Load0 _
  | RMW0 _
  | Fence0 _ ->
      assert false


(* if guard then heap1 else heap2 for all addresses in alist *)
let merge_heaps (state: bmc_state) 
                (heap1: kheap) (heap2: kheap) 
                (guard: Expr.expr) : kheap =
  Pmap.merge (
    fun k e1_ e2_ -> 
      let (e1, e2) = match (e1_, e2_) with
        | (Some x, Some y) -> (x, y)
        | _ -> (Printf.printf "TODO: Merge heaps properly\n"; assert false)
      in
      (* TODO: duplicated code *)
      let bmc_address = 
        match Pmap.lookup k (!(state.addr_map)) with
        | Some x -> x
        | None -> assert false
      in
      let (new_sym, seq_num) = mk_next_seq_symbol state.ctx bmc_address in
      (* TODO: sort should be in bmc_address *)
      assert (Sort.equal (Expr.get_sort e1) (Expr.get_sort e2));
      let sort = Expr.get_sort e1 in
      let new_expr = Expr.mk_const state.ctx new_sym sort in
      bmc_address.hist := Pmap.add seq_num new_expr (!(bmc_address.hist));
     
      (* Add equality *) 
      Solver.add state.solver 
        [ Boolean.mk_implies state.ctx guard 
            (Boolean.mk_eq state.ctx new_expr e1) ;
          Boolean.mk_implies state.ctx (Boolean.mk_not state.ctx guard)
            (Boolean.mk_eq state.ctx new_expr e2) 
        ];
      Some new_expr 
      ) heap1 heap2

let rec bmc_expr (state: bmc_state) 
                 (Expr(annot, expr_) : 'a typed_expr) =
  let (z_e, state') = match expr_ with
  | Epure pe ->
      let (maybe_ret1, state1)  = bmc_pexpr state pe in
      maybe_ret1, state1
  | Ememop (PtrValidForDeref, _) ->
      Printf.printf "TODO: Ememop PtrValidForDeref: currently always true\n";
      Some (Boolean.mk_true state.ctx), state
  | Ememop _ ->
      assert false
  | Eaction paction ->
      bmc_paction state paction
  | Ecase (pe, ((pat1, e1) :: (pat2, e2) :: [])) -> 
      Printf.printf "TODO: Ecase";
      let (Pexpr(pe_type, pe_)) = pe in
      let (maybe_pe, st) = bmc_pexpr state pe in 
      let (eq_expr) = 
            mk_eq_pattern st pat1 pe_type maybe_pe in
      let (bmc_e1, st1) = bmc_expr state e1 in
      let (bmc_e2, st2) = bmc_expr state e2 in
      Solver.add state.solver [ eq_expr ];
      (* Similar to Eif*)

      begin
        match (bmc_e1, bmc_e2) with
        | (None, None) -> 
            let new_vc = st.vcs @ (concat_vcs st st1.vcs st2.vcs eq_expr) in
            let new_heap = merge_heaps st st1.heap st2.heap eq_expr in
            None, ({st with vcs = new_vc; heap = new_heap})
        | (Some a1, Some a2) -> 
            let new_vc = st.vcs @ (concat_vcs st st1.vcs st2.vcs eq_expr) in
            let new_heap = merge_heaps st st1.heap st2.heap eq_expr in
            
            Some (Boolean.mk_ite st.ctx eq_expr a1 a2),
            ({st with heap = new_heap; vcs = new_vc})
        | _ -> (Printf.printf "TODO: Do ECase properly\n"; assert false)
      end

  | Ecase _ ->  
      Printf.printf "TODO: Do ECase properly \n"; 
      assert false
  | Eskip -> 
      (* TODO: Unit *)
      Printf.printf "TODO: unit\n";
      None, state 
  | Eproc _ -> assert false
  | Eccall _  -> assert false
  | Eunseq _ -> assert false
  | Eindet _ -> assert false
  | Ebound (_, e1) ->
      (* TODO: bound ignored *)
      bmc_expr state e1 
  | End elist ->
      Printf.printf "TODO ND sequencing: currrently treated as undef\n";
      let new_vcs = (Boolean.mk_false state.ctx) :: state.vcs in
      let new_state = {state with vcs = new_vcs} in
      Printf.printf "TODO: unit\n";
      None, new_state
  | Erun _
  | Epar _
  | Ewait _ -> assert false
  | Eif (pe, e1, e2) -> 
      let (maybe_pe, st) = bmc_pexpr state pe in
      let (bmc_e1, st1) = bmc_expr ({st with vcs = []}) e1 in
      let (bmc_e2, st2) = bmc_expr ({st with vcs = []}) e2 in

      Printf.printf "TODO: only heap/vcs are updated after Eif\n";
      let ret = 
        (* TODO: special cased *)
        match (maybe_pe, bmc_e1, bmc_e2) with
        | (Some pexpr, None, None) -> 
          let new_vc = st.vcs @ (concat_vcs state st1.vcs st2.vcs pexpr) in
          let new_heap = merge_heaps st st1.heap st2.heap pexpr in

          (* Return state conditional upon which store occurred *)
          (* TODO: record which addresses each state may have changed *) 
          (* TODO: ptr_map *)
          None, ({st with heap = new_heap; vcs = new_vc})
        | (Some pexpr, Some e1, Some e2) -> 
            (* TODO: duplicated *)
          let new_vc = st.vcs @ (concat_vcs state st1.vcs st2.vcs pexpr) in
          let new_heap = merge_heaps st st1.heap st2.heap pexpr in
          Some (Boolean.mk_ite state.ctx pexpr e1 e2),
            ({st with heap = new_heap; vcs = new_vc})
        | _ -> assert false
      in 
      ret    
  | Elet _ -> assert false
  | Easeq _ ->
      assert false
  | Ewseq (CaseBase(sym, typ), e1, e2) ->
      let (ret_e1, state1) = bmc_expr state e1 in
      let (eq_expr) = mk_eq_pattern state1 (CaseBase(sym, typ)) typ ret_e1 in
      Solver.add state1.solver [ eq_expr ];
      bmc_expr state1 e2
  | Ewseq _ -> assert false
  | Esseq (CaseBase(sym, typ), e1, e2) ->
      let (ret_e1, state1) = bmc_expr state e1 in
      let (eq_expr ) = mk_eq_pattern state1 (CaseBase(sym, typ)) typ ret_e1 in
      Solver.add state1.solver [ eq_expr ];
      bmc_expr state1 e2
  | Esseq _  ->
      assert false
  | Esave _  ->
      assert false
  in 
    (z_e, state')


(* TODO: only handles one function *)
let bmc_fun_map (state: bmc_state)
                (funs: ('a, 'b typed_fun_map_decl) Pmap.map) =
  Pmap.map (function
    | Fun (ty, params, pe) ->
        (* TODO: return vcs *)
        let (_, state1) = bmc_pexpr state pe in
        let not_vcs = List.map (fun a -> (Boolean.mk_not state1.ctx a))
                               state1.vcs 
        in
        Solver.add state1.solver [ Boolean.mk_or state1.ctx not_vcs ]
    | ProcDecl (ty, params) ->
        assert false
    | Proc (ty, params, e) ->        
        let (_, state1) = bmc_expr state e in
        Printf.printf "-----CONSTRAINTS ONLY\n";
        check_solver state1.solver;
        Printf.printf "-----WITH VCS \n";
        let not_vcs = List.map (fun a -> (Boolean.mk_not state1.ctx a))
                               state1.vcs
        in
        Solver.add state1.solver [ Boolean.mk_or state1.ctx not_vcs ] 
  ) funs


let bmc_file (file: 'a typed_file) (supply: ksym_supply) =
  let initial_state = initial_bmc_state supply in
  (*
  add_func_constraints initial_state;
  Printf.printf "Initial solver: \n %s \n" (Solver.to_string (initial_state.solver));
  check_solver (initial_state.solver);
  *)

  Printf.printf "Begin BMC\n";
  let _ = bmc_fun_map initial_state file.funs in
  (* TODO globals *)
  Printf.printf "\n-- Solver:\n%s\n" (Solver.to_string (initial_state.solver));
  Printf.printf "Checking sat\n";
  check_solver (initial_state.solver)

let (>>=) = Exception.except_bind

let run_bmc (core_file : 'a file) 
            (sym_supply: ksym_supply)    = 
  (* TODO: state monad with sym_supply *)
  print_string "ENTER: BMC PIPELINE \n";
  pp_file core_file;

  print_string "ENTER: NORMALIZING FILE\n";
  let (norm_file, norm_supply) = bmc_normalize_file core_file sym_supply in
  pp_file norm_file;

  print_string "EXIT: NORMALIZING FILE\n";

  print_string "Typechecking file\n";
  Core_typing.typecheck_program norm_file >>= fun typed_core ->
    Exception.except_return (
      bmc_file typed_core norm_supply;

      print_string "EXIT: BMC PIPELINE \n"
    )
    (*
      bmc_file (Core_sequentialise.sequentialise file typed_core ) norm_supply; 
      *)

  (*
  let (normalized_file, supply1) = normalize_file core_file sym_supply in
  pp_file normalized_file;

  print_string "Done normalization\n";
  bmc_file normalized_file supply1; 
  *)
  
  (*bmc_file core_file sym_supply; *)

