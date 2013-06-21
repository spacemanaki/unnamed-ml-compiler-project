structure ParserTests =
struct
open QCheck
structure P = Parser
fun test _ =
    let
       fun c name = check (List.getItem, SOME (Show.pair (fn x => x, P.show)))
                          (name, pred (fn (s, ast) => (P.parse (Lexer.lexStr s)) = ast))
    in
       (
         c "parser/exprs"
           [
             ("0",               P.Num 0)
            ,("foo",             P.Id "foo")
            ,("1 + 2",           P.Add (P.Num 1, P.Num 2))
            ,("1 * 2 + 3",       P.Add (P.Mul (P.Num 1, P.Num 2), P.Num 3))
            ,("1 - 2 / 3",       P.Sub (P.Num 1, P.Div (P.Num 2, P.Num 3)))
            ,("(1 - 2) * 3",     P.Mul (P.Sub (P.Num 1, P.Num 2), P.Num 3))
            ,("(1 - 2) * (3)",   P.Mul (P.Sub (P.Num 1, P.Num 2), P.Num 3))
            ,("(bar - 2) / foo", P.Div (P.Sub (P.Id "bar", P.Num 2), P.Id "foo"))
            ,("1 - 2 + 3 - 4",   P.Sub (P.Add (P.Sub (P.Num 1, P.Num 2), P.Num 3), P.Num 4))
           ]
       ; c "parser/fns"
           [
             ("fn x=>x",           P.Fn ("x", P.Id "x"))
            ,("fn x => fn y => y", P.Fn ("x", P.Fn ("y", P.Id "y")))
            ,("fn x => x + x",     P.Fn ("x", P.Add (P.Id "x", P.Id "x")))
            ,("fn x=>x+x",         P.Fn ("x", P.Add (P.Id "x", P.Id "x")))
           ]
       ; c "parser/parens"
           [
             ("(1)",                           P.Num 1)
            ,("(x)",                           P.Id "x")
            ,("(true)",                        P.Bool true)
            ,("if (true) then (x) else ((y))", P.If (P.Bool true, P.Id "x", P.Id "y"))
           ]
       ; c "parser/app"
           [
             ("x y",                              P.App (P.Id "x", P.Id "y"))
            ,("(x y)",                            P.App (P.Id "x", P.Id "y"))
            ,("(fn x => x) 1",                    P.App (P.Fn ("x", P.Id "x"), P.Num 1))
            ,("(fn f => f 1)",                    P.Fn ("f", P.App (P.Id "f", P.Num 1)))
            ,("if not true then false else true", P.If (P.App (P.Id "not", P.Bool true), P.Bool false, P.Bool true))
            ,("if true then not false else true", P.If (P.Bool true, P.App (P.Id "not", P.Bool false), P.Bool true))
            ,("if true then false else not true", P.If (P.Bool true, P.Bool false, P.App (P.Id "not", P.Bool true)))
            ,("let f = fn x => x in f 1",         P.Let ("f", P.Fn ("x", P.Id "x"), P.App (P.Id "f", P.Num 1)))
           ]
       )
    end

end
