(* open Cerb_frontend *)
open Cerb_frontend.Annot
open Resultat
open Effectful.Make(Resultat)
open TypeErrors
open Pp
module Cn = Cerb_frontend.Cn


module Loc = Locations

(* the character @ is not a separator in C, so supporting @start as a
   legacy syntax requires special hacks *)
let fiddle_at_hack string =
  let ss = String.split_on_char '@' string in
  let starts_start s = String.length s >= String.length "start"
    && String.equal (String.sub s 0 (String.length "start")) "start" in
  let rec fix = function
    | [] -> ""
    | [s] -> s
    | (s1 :: s2 :: ss) -> if starts_start s2
        then fix ((s1 ^ "%" ^ s2) :: ss)
        else fix ((s1 ^ "@" ^ s2) :: ss)
  in
  fix ss

let diagnostic_get_tokens string =
  C_lexer.internal_state.inside_cn <- true;
  let lexbuf = Lexing.from_string string in
  let rec f xs = try begin match C_lexer.lexer lexbuf with
    | Tokens.EOF -> List.rev ("EOF" :: xs)
    | t -> f (Tokens.string_of_token t :: xs)
  end with C_lexer.Error err -> List.rev (CF.Pp_errors.string_of_cparser_cause err :: xs)
  in
  f []

(* adapting from core_parser_driver.ml *)

let parse parser_start (loc, string) =
  let string = fiddle_at_hack string in
  C_lexer.internal_state.inside_cn <- true;
  let lexbuf = Lexing.from_string string in
  let () = 
    let open Cerb_location in
    Lexing.set_position lexbuf
      (* revisit *)
      begin match Cerb_location.to_raw loc with
      | Loc_unknown -> lexbuf.lex_curr_p
      | Loc_other _ -> lexbuf.lex_curr_p
      | Loc_point pos -> pos
      (* start, end, cursor *)
      | Loc_region (pos, _, _ ) -> pos
      | Loc_regions ([],_) -> lexbuf.lex_curr_p 
      | Loc_regions ((pos,_) :: _, _) -> pos
      end
  in
  let () = match Cerb_location.get_filename loc with
    | Some filename -> lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname= filename }
    | None -> () 
  in
  let@ parsed_spec =
    try return (parser_start C_lexer.lexer lexbuf) with
    | C_lexer.Error err ->
       let loc = Cerb_location.point @@ Lexing.lexeme_start_p lexbuf in
       fail {loc; msg = Parser err}
    | C_parser.Error ->
       let loc = Cerb_location.(region (Lexing.lexeme_start_p lexbuf, Lexing.lexeme_end_p lexbuf) NoCursor) in
       Pp.debug 6 (lazy (
           let toks = try diagnostic_get_tokens string
             with C_lexer.Error _ -> ["(re-parse error)"] in
           Pp.item "failed to parse tokens" (Pp.braces (Pp.list Pp.string toks))));
       fail {loc; msg = Generic (Pp.string ("Unexpected token " ^ Lexing.lexeme lexbuf))}
  in
  return parsed_spec


let parse_function_spec (Attrs attributes) =
  let attributes = List.rev attributes in
  let@ conditions =
    ListM.concat_mapM (fun attr ->
        let k = (Option.value ~default:"<>" (Option.map Id.s attr.attr_ns), Id.s attr.attr_id) in
        (* FIXME (TS): I'm not sure if the check against cerb::magic was strange,
            or if it was checking the wrong thing the whole time *)
        let use = List.exists (fun (x, y) -> String.equal x (fst k) && String.equal y (snd k))
            [("cerb", "magic"); ("cn", "requires"); ("cn", "ensures");
                ("cn", "accesses"); ("cn", "trusted")] in
        if use then ListM.mapM (fun (loc, arg, _) ->
               parse C_parser.function_spec (loc, arg)
             ) attr.attr_args
        else return []
      ) attributes
  in
  ListM.fold_leftM (fun acc cond ->
    match cond, acc with
    | (Cn.CN_trusted loc), (_, [], [], [], []) ->
       return (Mucore.Trusted loc, [], [], [], [])
    | (Cn.CN_trusted loc), _ ->
       fail {loc; msg= Generic !^"Please specify 'trusted' before other conditions"}
    | (CN_accesses (loc, ids)), (trusted, accs, [], [], ex) ->
       return (trusted, accs @ List.map (fun id -> (loc, id)) ids, [], [], ex)
    | (CN_accesses (loc, _)), _ ->
       fail { loc; msg= Generic !^"Please specify 'accesses' before any 'requires' and 'ensures'" }
    | (CN_requires (loc, cond)), (trusted, accs, reqs, [], ex) ->
       return (trusted, accs, reqs @ List.map (fun c -> (loc, c)) cond, [], ex)
    | (CN_requires (loc, _)), _ ->
       fail {loc; msg = Generic !^"Please specify 'requires' before any 'ensures'"}
    | (CN_ensures (loc, cond)), (trusted, accs, reqs, enss, ex) ->
       return (trusted, accs, reqs, enss @ List.map (fun c -> (loc, c)) cond, ex)
    | (CN_mk_function (loc, nm)), (trusted, accs, reqs, enss, ex) ->
       return (trusted, accs, reqs, enss, ex @ [(loc, Mucore.Make_Logical_Function nm)])
    )
    (Mucore.Checked, [], [], [], []) conditions

let parse_inv_spec (Attrs attributes) =
  ListM.concat_mapM (fun attr ->
      match Option.map Id.s (attr.attr_ns), Id.s (attr.attr_id) with
      | Some "cerb", "magic" ->
         ListM.concat_mapM (fun (loc, arg, _) ->
             let@ (Cn.CN_inv (_loc, conds)) = parse C_parser.loop_spec (loc, arg) in
             return conds
           ) attr.attr_args
      | _ ->
         return []
    ) attributes


