open CpAil

let map_exp f s exp =
  match exp with
  | UNARY (o, e) -> UNARY (o, f e)
  | BINARY (o, e1, e2) -> BINARY (o, f e1, f e2)
  | ASSIGN (o, e1, e2) -> ASSIGN (o, f e1, f e2)
  | QUESTION (e1, e2, e3) -> QUESTION (f e1, f e2, f e3)
  | CAST (t, e) -> CAST (t, f e)
  | CALL (e, es) -> CALL (f e, List.map f es)
  | CONSTANT c -> CONSTANT c
  | VARIABLE id -> VARIABLE (s id)
  | SIZEOF t -> SIZEOF t
  | ALIGNOF t -> ALIGNOF t

let fold_exp_left f a exp =
  match exp with
  | UNARY (o, e) -> f a e
  | BINARY (o, e1, e2) -> f (f a e1) e2
  | ASSIGN (o, e1, e2) -> f (f a e1) e2
  | QUESTION (e1, e2, e3) -> f (f (f a e1) e2) e3
  | CAST (t, e) -> f a e
  | CALL (e, es) -> List.fold_left f a es
  | CONSTANT c -> a
  | VARIABLE id -> a
  | SIZEOF t -> a
  | ALIGNOF t -> a

let map_stmt fs fe sub stmt =
  match stmt with
  | EXPRESSION e -> EXPRESSION (fe e)
  | BLOCK (ids, sl) ->
      BLOCK (List.map sub ids, List.map fs sl)
  | IF (e, s1, s2) -> IF (fe e, fs s1, fs s2)
  | WHILE (e, s) -> WHILE (fe e, fs s)
  | DO (e, s) -> DO (fe e, fs s)
  | RETURN_EXPRESSION e -> RETURN_EXPRESSION (fe e)
  | SWITCH (e, s) -> SWITCH (fe e, fs s)
  | CASE (c, s) -> CASE (c, fs s)
  | DEFAULT s -> DEFAULT (fs s)
  | LABEL (id, s) -> LABEL (sub id, fs s)
  | DECLARATION dl ->
      DECLARATION (List.map (fun (id, e) -> sub id, fe e) dl)
  | SKIP -> SKIP
  | BREAK -> BREAK
  | CONTINUE -> CONTINUE
  | RETURN_VOID -> RETURN_VOID
  | GOTO id -> GOTO (sub id)

let fold_stmt_left fs fe a stmt =
  match stmt with
  | EXPRESSION e -> fe a e
  | BLOCK (ids, sl) -> List.fold_left fs a sl
  | IF (e, s1, s2) -> fs (fs (fe a e) s1) s2
  | WHILE (e, s) -> fs (fe a e) s
  | DO (e, s) -> fs (fe a e) s
  | RETURN_EXPRESSION e -> fe a e
  | SWITCH (e, s) -> fs (fe a e) s
  | CASE (c, s) -> fs a s
  | DEFAULT s -> fs a s
  | LABEL (id, s) -> fs a s
  | DECLARATION dl -> List.fold_left (fun a (_, e) -> fe a e) a dl
  | SKIP -> a
  | BREAK -> a
  | CONTINUE -> a
  | RETURN_VOID -> a
  | GOTO id -> a

let rec map_type f t =
  match t with
  | BASE _ -> t
  | POINTER (q, t) -> POINTER (q, f t)
  | ARRAY (t, size) -> ARRAY (f t, size)
  | FUNCTION (t, ts) -> FUNCTION (f t, List.map f ts)

let rec for_all_type p t =
  match t with
  | BASE _ -> true
  | POINTER (_, t) -> p t
  | ARRAY (t, _) -> p t
  | FUNCTION (t, ts) -> p t && List.for_all p ts
