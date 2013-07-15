structure Lexer : sig

(* TODO: lexFile : filename -> t list *)
val lexStr : string -> {line : int, col: int} Token.t list

end =
struct

fun takeWhile p xs =
    let
       fun takeWhile' acc [] = (rev acc, [])
         | takeWhile' acc (all as x::xs) =
           if p x
              then takeWhile' (x::acc) xs
           else (rev acc, all)
    in
       takeWhile' [] xs
    end

fun getDigit chars =
    let
       val (numStr, rest) = takeWhile Char.isDigit chars
    in
       (Int.fromString (String.implode numStr), length numStr, rest)
    end

fun notDelim #"(" = false
  | notDelim #")" = false
  | notDelim #"," = false
  | notDelim #"|" = false
  | notDelim ch = not (Char.isSpace ch)

fun isSpecial x = notDelim x andalso Char.isPunct x
fun isValid x = Char.isAlphaNum x orelse x = #"_"

fun getWord (chars as x :: xs) =
    let
       val (id, rest) =
           if isSpecial x then
              takeWhile isSpecial chars
           else takeWhile isValid chars
    in
       (String.implode id, rest)
    end
  | getWord [] = ("", [])

exception LexicalError of string

(* TODO: needs to be a Set build by previous infix declarations *)
fun isInfix "+" = true
  | isInfix "-" = true
  | isInfix "*" = true
  | isInfix "/" = true
  | isInfix _ = false

(*
 * list-based lexical analyzer, probably pretty slow
 *)
fun lexStr (s : string) : AST.pos Token.t list =
    let
       val line = ref 1
       val col = ref 1
       fun get () = {line = !line, col = !col}
       fun incrLine n = get () before line := !line + n
       fun incrCol n = get () before col := !col + n

       fun lexStr' (acc, #"(" :: rest) = lexStr' (Token.LParen (incrCol 1) :: acc, rest)
         | lexStr' (acc, #")" :: rest) = lexStr' (Token.RParen (incrCol 1):: acc, rest)
         | lexStr' (acc, #"|" :: rest) = lexStr' (Token.Bar (incrCol 1) :: acc, rest)
         | lexStr' (acc, #"," :: rest) = lexStr' (Token.Comma (incrCol 1) :: acc, rest)
         | lexStr' (acc, #"\n" :: rest) = (incrLine 1; lexStr' (acc, rest))
         | lexStr' (acc, all as c :: cs) =
           if Char.isDigit c
              then case getDigit all of
                       (SOME n, len, rest) => lexStr' (Token.Num (incrCol len, n) :: acc, rest)
                     | (NONE, _, _) =>
                       raise LexicalError ("error lexing num: " ^ String.implode all)
           else if Char.isSpace c
                   then (incrCol 1; lexStr' (acc, cs))
           else if c = #"'" then
              (case getWord cs of
                   ("", rest) => raise LexicalError "expected type var"
                 | (v, rest) => lexStr' (Token.TypeVar (incrCol (String.size v + 1), v) :: acc, rest))
                else (case getWord all of
                         ("if", rest) => lexStr' (Token.If (incrCol 2) :: acc, rest)
                       | ("then", rest) => lexStr' (Token.Then (incrCol 4) :: acc, rest)
                       | ("else", rest) => lexStr' (Token.Else (incrCol 4) :: acc, rest)
                       | ("true", rest) => lexStr' (Token.Bool (incrCol 4, true) :: acc, rest)
                       | ("false", rest) => lexStr' (Token.Bool (incrCol 5, false) :: acc, rest)
                       | ("fn", rest) => lexStr' (Token.Fn (incrCol 2) :: acc, rest)
                       | ("let", rest) => lexStr' (Token.Let (incrCol 3) :: acc, rest)
                       | ("in", rest) => lexStr' (Token.In (incrCol 2) :: acc, rest)
                       | ("end", rest) => lexStr' (Token.End (incrCol 3) :: acc, rest)
                       | ("case", rest) => lexStr' (Token.Match (incrCol 4) :: acc, rest)
                       | ("with", rest) => lexStr' (Token.With (incrCol 4) :: acc, rest)
                       | ("datatype", rest) => lexStr' (Token.Datatype (incrCol 8) :: acc, rest)
                       | ("of", rest) => lexStr' (Token.Of (incrCol 2) :: acc, rest)
                       | ("val", rest) => lexStr' (Token.Val (incrCol 3) :: acc, rest)

                       | ("=", rest) => lexStr' (Token.Eqls (incrCol 1) :: acc, rest)
                       | ("=>", rest) => lexStr' (Token.DArrow (incrCol 2) :: acc, rest)
                       | ("->", rest) => lexStr' (Token.TArrow (incrCol 2) :: acc, rest)

                       | ("", _) =>
                         raise LexicalError ("error lexing: " ^ String.implode all)

                       | (id, rest) =>
                         if Char.isUpper (String.sub (id, 0))
                            then lexStr' ((Token.Ctor (incrCol (String.size id), id)) :: acc, rest)
                         else if isInfix id
                            then lexStr' ((Token.Infix (incrCol (String.size id), id)) :: acc, rest)
                         else lexStr' ((Token.Id (incrCol (String.size id), id)) :: acc, rest))
         | lexStr' (acc, []) = rev acc
    in
       lexStr' ([], String.explode s)
    end
end
