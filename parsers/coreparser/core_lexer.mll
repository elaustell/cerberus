{
open Pervasives_

module T = Core_parser_util
type token = T.token

let keywords =
  List.fold_left
    (fun m (k, e) -> Pmap.add k e m)
    (Pmap.empty Pervasives.compare)
    [
      (* ctype tokens *)
      ("_Atomic",     T.ATOMIC);
      ("short",       T.SHORT);
      ("int",         T.INT);
      ("long",        T.LONG);
      ("long_long",   T.LONG_LONG);
      ("_Bool",       T.BOOL);
      ("signed",      T.SIGNED);
      ("unsigned",    T.UNSIGNED);
      ("float",       T.FLOAT);
      ("double",      T.DOUBLE);
      ("long_double", T.LONG_DOUBLE);
(*      ("_Complex",    T.COMPLEX); *)
      ("char",        T.CHAR);
      ("ichar",       T.ICHAR);
      ("void",        T.VOID);
      ("struct",      T.STRUCT);
      ("union",       T.UNION);
      ("enum",        T.ENUM);
      ("size_t",      T.SIZE_T);
      ("intptr_t",    T.INTPTR_T);
      ("wchar_t",     T.WCHAR_T);
      ("char16_t",    T.CHAR16_T);
      ("char32_t",    T.CHAR32_T);
      
      (* for Core.core_base_type *)
      ("integer",  T.INTEGER  );
      ("boolean",  T.BOOLEAN  );
      ("address",  T.ADDRESS  );
      ("ctype",    T.CTYPE    );
      ("unit",     T.UNIT     );
      ("function", T.FUNCTION );
(*    | Tuple of list core_base_type *)
      
      (* for Core.expr *)
      ("null",   T.NULL     );
      ("true",   T.TRUE);
      ("false",  T.FALSE);
(*  | Econst of Cmm_aux.constant *)
(*  | Ectype of ctype *)
(*  | Eaddr of Memory.mem_addr *)
(*  | Esym of sym *)
(*  | Eimpl of Implementation_.implementation_constant *)
(*  | Etuple of list (expr 'a) *)
      ("not", T.NOT);
(*  | Eop of binop * expr 'a * expr 'a *)
(*  | Ecall of name * list (expr 'a) *)
      ("undef", T.UNDEF);
      ("error", T.ERROR);
      ("skip", T.SKIP);
      ("let", T.LET);
      ("in", T.IN);
      ("if", T.IF);
      ("then", T.THEN);
      ("else", T.ELSE);
(*  | Eproc of set 'a * name * list (expr 'a) *)
(*  | Eaction of paction 'a *)
(*  | Eunseq of list (expr 'a) *)
      ("weak", T.WEAK);
      ("strong", T.STRONG);
      ("atom", T.ATOM);
      ("save", T.SAVE);
      ("run", T.RUN);
      ("indet", T.INDET);
      ("return", T.RETURN);
  
(*  | End of list (expr 'a) *)
(*  | Epar of list (expr 'a) *)

      
      (* for Core.action_ *)
      ("create",                  T.CREATE                 );
      ("alloc",                   T.ALLOC                  );
      ("kill",                    T.KILL                   );
      ("store",                   T.STORE                  );
      ("load",                    T.LOAD                   );
      ("compare_exchange_strong", T.COMPARE_EXCHANGE_STRONG);
      ("compare_exchange_weak",   T.COMPARE_EXCHANGE_WEAK  );

      
      
      ("def",     T.DEF     ); (* for implementation files only *)
      ("fun",     T.FUN     );
      ("proc",    T.PROC     );
      
      
      ("end",     T.END     );
      ("case",    T.CASE    );
      ("of",      T.OF      );
      ("seq_cst", T.SEQ_CST );
      ("relaxed", T.RELAXED );
      ("release", T.RELEASE );
      ("acquire", T.ACQUIRE );
      ("consume", T.CONSUME );
      ("acq_rel", T.ACQ_REL );

      ("case_ty",   T.CASE_TY         );
      ("Signed",    T.SIGNED_PATTERN  );
      ("Unsigned",  T.UNSIGNED_PATTERN);
      ("Array",     T.ARRAY_PATTERN   );
      ("Pointer",   T.POINTER_PATTERN );
      ("Atomic",    T.ATOMIC_PATTERN  );


(* TODO: temporary *)
      ("is_scalar",   T.IS_SCALAR  );
      ("is_integer",  T.IS_INTEGER );
      ("is_signed",   T.IS_SIGNED  );
      ("is_unsigned", T.IS_UNSIGNED);
    ]

let scan_sym lexbuf =
  let id = Lexing.lexeme lexbuf in
  try
    Pmap.find id keywords
  with Not_found ->
    T.SYM id

let scan_impl lexbuf =
  let id = Lexing.lexeme lexbuf in
  try
    T.IMPL (Pmap.find id Implementation_.impl_map)
  with Not_found ->
    failwith ("Found an invalid impl_name: " ^ id)

let scan_ub lexbuf =
  let id = Lexing.lexeme lexbuf in
  try
    T.UB (Pmap.find id Undefined.ub_map)
  with Not_found ->
    failwith ("Found an invalid undefined-behaviour: " ^ id)




let lex_comment remainder lexbuf =
  let ch = Lexing.lexeme_char lexbuf 0 in
  let prefix = Int64.of_int (Char.code ch) in
  if ch = '\n' then Lexing.new_line lexbuf;
  prefix :: remainder lexbuf

}


let ub_name = "<<" ['A'-'Z' 'a'-'z' '_' '0'-'9']* ">>"
let impl_name = '<' ['A'-'Z' 'a'-'z' '_' '.']* '>'
let symbolic_name = ['_' 'a'-'z']['0'-'9' 'A'-'Z' 'a'-'z' '_']*


rule main = parse
  (* beginning of a comment *)
  | "{-"
      { let _ = comment lexbuf in main lexbuf }
  
  (* single-line comment *)
  | "--"
      { let _ = onelinecomment lexbuf in Lexing.new_line lexbuf; main lexbuf }
  
  (* skip spaces *)
  | [' ' '\t']+
      { main lexbuf }
  
  (* integer constants *)
  | ('-'?)['0'-'9']+ as integer
      { T.INT_CONST (Big_int.big_int_of_string integer) }
  
  (* binary operators *)
  | '+'   { T.PLUS }
  | '-'   { T.MINUS }
  | '*'   { T.STAR }
  | '/'   { T.SLASH }
  | '%'   { T.PERCENT }
  | '='   { T.EQ }
  | '<'   { T.LT }
  | "<="  { T.LE }
  | "/\\" { T.SLASH_BACKSLASH }
  | "\\/" { T.BACKSLASH_SLASH }
  
  (* negative action *)
  | '~' { T.TILDE }
  
  | "||"  { T.PIPE_PIPE }
  | "|||"  { T.PIPES }
  
  (* pattern symbols *)
  | "_"  { T.UNDERSCORE }
  
  | "| "  { T.PIPE }
  | "-> " { T.MINUS_GT }
  | '('   { T.LPAREN }
  | ')'   { T.RPAREN }
  | '{'   { T.LBRACE }
  | '}'   { T.RBRACE }
  | "{{{" { T.LBRACES }
  | "}}}" { T.RBRACES }
  | '['	  { T.LBRACKET }
  | ']'	  { T.RBRACKET }
  | '<'	  { T.LANGLE }
  | '>'	  { T.RANGLE }
  | '.'   { T.DOT }
  | "..." { T.DOTS }
  | ','   { T.COMMA }
  | ':'   { T.COLON }
  | ":="  { T.COLON_EQ }
  | "\""  { T.DQUOTE }
  
  | "=> " { T.EQ_GT }


  | ub_name { scan_ub lexbuf }
  | impl_name { scan_impl lexbuf }
  | symbolic_name { scan_sym lexbuf }
  | '\n' {Lexing.new_line lexbuf; main lexbuf}
  | eof  {T.EOF}
  | _
    { raise_error ("Unexpected symbol \""
                   ^ Lexing.lexeme lexbuf ^ "\" in "
                   ^ Position.lines_to_string (Position.from_lexbuf lexbuf)
                   ^ ".\n")
    }


and comment = parse
  | "-}"
      { [] }
  | _
      {lex_comment comment lexbuf}


and onelinecomment = parse
  | '\n' | eof
      { [] }
  | _
      { lex_comment onelinecomment lexbuf }
