(* grammar:
 *   exprs  -> expr expr
 *   expr   -> if expr then expr else expr
 *   expr   -> fn id => expr
 *   expr   -> let id = expr in expr
 *   expr   -> term expr'
 *   expr'  -> + term expr'
 *   expr'  -> - term expr'
 *   expr'  ->
 *   term   -> factor term'
 *   term'  -> * factor term'
 *   term'  -> / factor term'
 *   term'  ->
 *   factor -> ( expr )
 *   factor -> id
 *   factor -> num
 *   factor -> bool
 *)
structure Parser : sig 

datatype t = Num of int
           | Bool of bool
           | Id of string
           | Add of t * t
           | Mul of t * t
           | Div of t * t
           | Sub of t * t
           | App of t * t (* TODO: curried function application, ie "f g x" ~> "App (App (f, g), x)" *)
           | If of t * t * t
           | Fn of string * t
           | Let of string * t * t (* TODO: multi let *)

val show : t -> string
val parse : Lexer.t list -> t

end =
struct

structure L = Lexer

datatype t = Num of int
           | Bool of bool
           | Id of string
           | Add of t * t
           | Mul of t * t
           | Div of t * t
           | Sub of t * t
           | App of t * t
           | If of t * t * t
           | Fn of string * t
           | Let of string * t * t

fun show (Num n) = "Num " ^ Int.toString n
  | show (Bool b) = "Bool " ^ Bool.toString b
  | show (Id s) = "Id " ^ s
  | show (Add (lhs, rhs)) = "Add (" ^ show lhs ^ "," ^ show rhs ^ ")"
  | show (Sub (lhs, rhs)) = "Sub (" ^ show lhs ^ "," ^ show rhs ^ ")"
  | show (Mul (lhs, rhs)) = "Mul (" ^ show lhs ^ "," ^ show rhs ^ ")"
  | show (Div (lhs, rhs)) = "Div (" ^ show lhs ^ "," ^ show rhs ^ ")"
  | show (App (e1, e2)) = "App (" ^ show e1 ^ "," ^ show e2 ^ ")"
  | show (If (e1, e2, e3)) = "If (" ^ show e1 ^ "," ^ show e2 ^ "," ^ show e3 ^ ")"
  | show (Fn (x, e)) = "Fn (" ^ x ^ "," ^ show e ^ ")"
  | show (Let (x, e1, e2)) = "Let (" ^ x ^ "," ^ show e1 ^ "," ^ show e2 ^ ")"

exception SyntaxError of string

fun parse toks =
    let
       val rest = ref toks
       fun has () = not (null (!rest))
       fun adv () = rest := tl (!rest)
       fun next () = hd (!rest) before adv ()
       fun getNext () = if has () then SOME (next ()) else NONE
       fun peek () = hd (!rest)
       fun err s = raise SyntaxError ("err " ^ s)
       fun expected s t = raise SyntaxError ("expected " ^ s ^ ", got " ^ L.show t)

       (* flip this to print the grammar productions at each step *)
       val debug = false
       fun log s =
           let val t = if has () then L.show (peek ()) else ".."
           in if debug
                 then print (s ^ "(" ^ t ^ ")\n")
              else ()
           end

       fun expr () : t =
           (log "expr";
            case peek () of
                L.If =>
                (adv ()
                ; let val e1 = exprs ()
                  in case peek () of
                         L.Then => (adv ()
                                   ; let val e2 = exprs ()
                                     in case peek () of
                                            L.Else => (adv ()
                                                      ; If (e1, e2, exprs ()))
                                          | t => expected "else" t
                                     end)
                       | t => expected "then" t
                  end)
              | L.Fn =>
                (adv ()
                ; case peek () of
                      L.Id x => (adv ()
                                ; case peek () of
                                      L.Arrow => (adv (); Fn (x, exprs ()))
                                    | t => expected "=>" t)
                    | t => err ("expected formal arg in fn expr, got " ^ L.show t))
              | L.Let =>
                (adv ()
                ; case peek () of
                      L.Id x => (adv ()
                                ; case peek () of
                                      L.Eqls => (adv ()
                                              ; let val bound = exprs ()
                                                in case peek () of
                                                       L.In => (adv (); Let (x, bound, exprs ()))
                                                     | t => expected "in" t
                                                end)
                                    | t => expected "=" t)
                    | t => err ("expected bound var in let expr, got " ^ L.show t))
              | _ => expr' (term ()))

       and term () : t =
           (log "term";
            let
               val lhs = factor ()
            in
               term' lhs
            end)

       and expr' (lhs : t) : t =
           (log "expr'";
           if has ()
              then case peek () of
                       L.Add => (next (); expr' (Add (lhs, term ())))
                     | L.Sub => (next (); expr' (Sub (lhs, term ())))
                     | _ => lhs
           else lhs)

       and term' (lhs : t) : t =
           (log "term'";
           if has ()
              then case peek () of
                       L.Mul => (next (); term' (Mul (lhs, factor ())))
                     | L.Div => (next (); term' (Div (lhs, factor ())))
                     | _ => lhs
           else lhs)

       and factor () : t =
           (log "factor";
            case getNext () of
                SOME L.LParen => let val ast = exprs ()
                                 in case getNext () of
                                        SOME L.RParen => ast
                                      | SOME t => expected ")" t
                                      | _ => err "unexpected end of input, expected )"
                                 end
              | SOME (L.Num n) => Num n
              | SOME (L.Bool b) => Bool b
              | SOME (L.Id s) => Id s
              | SOME t => expected "bool, num or id" t
              | _ => err "unexpected end of input, expected bool, num or id")

       and exprs () : t =
           let
              (* check if token is in FIRST(expr) *)
              fun FIRSTexpr (L.Id _) = true
                | FIRSTexpr (L.Num _) = true
                | FIRSTexpr (L.Bool _) = true
                | FIRSTexpr L.If = true
                | FIRSTexpr L.Fn = true
                | FIRSTexpr L.Let = true
                | FIRSTexpr L.LParen = true
                | FIRSTexpr _ = false

              val ast1 = expr ()
           in
              if has () andalso FIRSTexpr (peek ())
                 then App (ast1, expr ())
              else ast1
           end
    in
       exprs ()
    end

end
