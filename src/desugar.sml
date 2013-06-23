(*
 * A desugared intermediate form that is close to the object language
 *
 *   - replaces pattern matching with simpler `case` expressions
 *   - other desugarings?
 *)
structure Desugar =
struct

structure A = Abstract
type eqxn = Pattern.Complex.t list * A.t
exception Assert of string

(*
 * check if eqxn starts with a var or ctor
 *)
fun isVar (Pattern.Complex.Var _ :: _, _) = true
  | isVar (Pattern.Complex.Ctor _ :: _, _) = false
  | isVar _ = raise Assert "isVar: eqxn has empty pat list"

val isCtor : eqxn -> bool = not o isVar

(*
 * get the ctor (if this eqxn starts with one)
 *)
fun getCtor (Pattern.Complex.Ctor (c, ps') :: ps, e) = c
  | getCtor _ = raise Assert "getCtor: eqxn has empty pat list"

exception UnknownCtor
fun ctors "Cons" = ["Cons", "Nil"]
  | ctors "Nil" = ["Cons", "Nil"]
  | ctors "Branch" = ["Branch", "Leaf"]
  | ctors "Leaf" = ["Branch", "Leaf"]
  | ctors _ = raise UnknownCtor

fun arity "Cons" = 2
  | arity "Nil" = 0
  | arity "Branch" = 2
  | arity "Leaf" = 1
  | arity _ = raise UnknownCtor

local
   val g = ref 0
in
   (* TODO: should have a symbol table by now, can generate truly unique gensyms *)
   fun gensym s = s ^ Int.toString (!g) before g := (!g) + 1
end

(*
 * substitute e2 for x in e1
 * this doesn't need to be so hairy if gensym can generate truly unique ids
 *)
fun subst (e1 : A.t, x : string, e2 : string) : A.t =
    case e1 of
        n as A.Num _ => n
      | b as A.Bool _ => b
      | A.Add (e3, e4) => A.Add (subst (e3, x, e2), subst (e4, x, e2))
      | A.Mul (e3, e4) => A.Mul (subst (e3, x, e2), subst (e4, x, e2))
      | A.Div (e3, e4) => A.Div (subst (e3, x, e2), subst (e4, x, e2))
      | A.Sub (e3, e4) => A.Sub (subst (e3, x, e2), subst (e4, x, e2))
      | A.App (e3, e4) => A.App (subst (e3, x, e2), subst (e4, x, e2))
      | A.If (e3, e4, e5) => A.If (subst (e3, x, e2), subst (e4, x, e2), subst (e5, x, e2))

      | id as A.Id x' => if x = x' then A.Id e2 else id

      (* have to be careful about bound vars *)
      | f as A.Fn (x', e) =>
        if x = x'
           then f
        else A.Fn (x', subst (e, x, e2))

      | l as A.Let (x', e3, e4)  =>
        if x = x'
           then l
        else A.Let (x', subst (e3, x, e2), subst (e3, x, e2))

      (* match also binds new vars... *)
      | m as A.Match (e3, qs) =>
        let
           fun occurs (Pattern.Complex.Var v) = v = x
             | occurs (Pattern.Complex.Ctor (_, ps)) = List.exists occurs ps
           fun subst' (p, e) = if occurs p then (p, e) else (p, subst (e, x, e2))
        in
           A.Match (subst (e3, x, e2), map subst' qs)
        end

fun tack (x, xss) = (x :: hd xss) :: tl xss

fun partition f [] = []
  | partition f [x] = [[x]]
  | partition f (x :: x' :: xs) =
    if f x = f x'
       then tack (x, (partition f (x' :: xs)))
    else [x] :: partition f (x' :: xs)

(*
 * Given a list of eqxns with patterns all starting with the same ctor,
 * return the eqxns created by reducing the first pattern to its subpatterns,
 * then appending those subpatterns to the rest of the patterns in that equation
 *)
fun subpats (ctor : string, eqxns : eqxn list) : eqxn list =
    let
       fun subpats' (Pattern.Complex.Ctor (c, ps') :: ps, e) =
           if c <> ctor
              then raise Assert "subpats: non-matching ctors in eqxns"
           else (ps' @ ps, e)
         | subpats' _ = raise Assert "subpats: pat vars in eqxns"
    in
       map subpats' eqxns
    end

(*
 * returns all eqxns that begin with ctor
 *)
fun choose (ctor, qs) =
    List.filter (fn q => getCtor q = ctor) qs

fun match ((u::us) : A.t list, qs : eqxn list, def : A.t) : A.t =
    foldr (fn (qs, acc) => matchVarCon (u::us, qs, acc)) def (partition isVar qs)
  | match ([], qs, def) = foldr A.Bar def (map (fn ([], e) => e) qs)

and matchVarCon (us : A.t list, (q::qs) : eqxn list, def : A.t) : A.t =
    if isVar q
       then matchVar (us, q::qs, def)
    else matchCtor (us, q::qs, def)

and matchVar ((u::us) : A.t list, qs : eqxn list, def : A.t) : A.t =
    let
       val u' = gensym "_u"
       fun matchVar' (Pattern.Complex.Var v :: ps, e) = (ps, subst (e, v, u'))
    in
       A.Let (u', u, match (us, map matchVar' qs, def))
    end
  | matchVar ([], _, _) = raise Assert "matchVar: empty list of eqxns"

(*
 * Return a case clause (pat * expr) for this ctor, exprs, eqxns, default
 * where the expr is the result of recursively compiling the rest of the pattern match
 *)
and matchClause (ctor : string, (u::us) : A.t list, qs : eqxn list, def : A.t) : (Pattern.Simple.t * A.t) =
    let
       val us' = List.tabulate (arity ctor, fn _ => gensym "_u")
    in
       (Pattern.Simple.Ctor (ctor, us'), match ((map A.Id us') @ us, subpats (ctor, qs), def))
    end
  | matchClause (_, [], _, _) = raise Assert "matchClause: empty list of exprs"

and matchCtor ((u::us) : A.t list, (q::qs) : eqxn list, def : A.t) : A.t =
    let
       val ctors = ctors (getCtor q)
    in
       A.Case (u, map (fn ctor => matchClause (ctor, u::us, choose (ctor, q::qs), def)) ctors)
    end
  | matchCtor ([], _, _) = raise Assert "matchCtor: empty list of exprs"
  | matchCtor (_, [], _) = raise Assert "matchCtor: empty list of eqxns"

end