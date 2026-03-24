{-# LANGUAGE LambdaCase #-}

module Rex.Test (testMain) where

import Rex.Lex (lexRex, bsplit)
import Rex.Tree2 hiding (treeMain)
import Rex.Rex hiding (rexMain)

-- Test Harness ----------------------------------------------------------------

data Test
  = Test String String [Tree] Rex               -- name, input, tree, rex
  | ExtentTest String String [(String, String)]  -- name, input, slices
  | MultiRexTest String String [Rex]             -- name, input, rex per input

parse :: String -> [Tree]
parse = parseTree . bsplit . lexRex

stripTree :: Tree -> Tree
stripTree (Tree sh pos _ _ ns) = Tree sh pos 0 0 (map stripNode ns)

stripNode :: Node -> Node
stripNode (N_CHILD t) = N_CHILD (stripTree t)
stripNode n           = n

toRex :: String -> Rex
toRex src = case parseRex src of
    [(slice, tree)] -> case rexFromBlockTree slice tree of
                         Just r  -> r
                         Nothing -> EXPR CLEAR []
    _ -> error "toRex: expected exactly one input"

run :: Test -> (Bool, String)
run (Test name input expTree expRex) =
  let actTree = map stripTree (parse input)
      actRex  = toRex input
      treeOk  = actTree == expTree
      rexOk   = actRex == expRex
  in if treeOk && rexOk
     then (True, "  OK  " ++ name)
     else (False, unlines $ ["  FAIL " ++ name, "    input:    " ++ show input]
       ++ (if treeOk then []
           else [ "    tree expected:"
                , concatMap (indent4 . ppTree) expTree
                , "    tree actual:"
                , concatMap (indent4 . ppTree) actTree
                ])
       ++ (if rexOk then []
           else [ "    rex expected:"
                , indent4 (ppRex expRex)
                , "    rex actual:"
                , indent4 (ppRex actRex)
                ]))

run (ExtentTest name input expected) =
  let results = parseRex input
      actual  = [ (src, take (treeLen t) (drop (treeOff t) input))
                | (src, t) <- results ]
      ok = map fst actual == map fst expected
           && all (\(src, t) -> src == take (treeLen t) (drop (treeOff t) input)) results
  in if ok
     then (True, "  OK  " ++ name)
     else (False, unlines
       [ "  FAIL " ++ name
       , "    input:    " ++ show input
       , "    expected slices: " ++ show (map fst expected)
       , "    actual slices:   " ++ show (map fst actual)
       ])

run (MultiRexTest name input expected) =
  let results = parseRex input
      actual  = [ case rexFromBlockTree slice tree of
                    Just r  -> r
                    Nothing -> EXPR CLEAR []
                | (slice, tree) <- results ]
  in if actual == expected
     then (True, "  OK  " ++ name)
     else (False, unlines $
       [ "  FAIL " ++ name
       , "    input:    " ++ show input ]
       ++ zipWith (\i (e, a) ->
           if e == a then "    rex[" ++ show i ++ "]: OK"
           else "    rex[" ++ show i ++ "] expected:\n" ++ indent4 (ppRex e)
             ++ "    rex[" ++ show i ++ "] actual:\n" ++ indent4 (ppRex a)
         ) [0::Int ..] (zip expected actual)
       )

indent4 :: String -> String
indent4 = unlines . map ("      "++) . lines

testMain :: IO ()
testMain = do
  let results = map run tests
      fails   = filter (not . fst) results
      total   = length results
      passed  = length (filter fst results)
  mapM_ (putStrLn . snd) results
  putStrLn ""
  putStrLn $ show passed ++ "/" ++ show total ++ " passed"
  if null fails then pure () else putStrLn $ show (length fails) ++ " FAILED"


-- Shorthand Constructors ------------------------------------------------------

cle :: [Node] -> Tree;  cle = Tree (S_NEST Clear) 0 0 0
par :: Int -> [Node] -> Tree;  par p = Tree (S_NEST Paren) p 0 0
bra :: Int -> [Node] -> Tree;  bra p = Tree (S_NEST Brack) p 0 0
cur :: Int -> [Node] -> Tree;  cur p = Tree (S_NEST Curly) p 0 0
clu :: Int -> [Node] -> Tree;  clu p = Tree S_CLUMP p 0 0
pom :: Int -> [Node] -> Tree;  pom p = Tree S_POEM p 0 0
blk :: Int -> [Node] -> Tree;  blk p = Tree S_BLOCK p 0 0
itm :: Int -> [Node] -> Tree;  itm p = Tree S_ITEM p 0 0
qup :: Int -> [Node] -> Tree;  qup p = Tree S_QUIP p 0 0

lw :: Int -> String -> Node;   lw c s = N_LEAF c (L_WORD s)
lt :: Int -> String -> Node;   lt c s = N_LEAF c (L_TRAD s)
lu :: Int -> String -> Node;   lu c s = N_LEAF c (L_UGLY s)
ru :: Int -> String -> Node;   ru = N_RUNE
ch :: Tree -> Node;            ch = N_CHILD
cw :: Int -> String -> Node;   cw c s = ch $ clu c [lw c s]
cwt :: Int -> String -> Node;  cwt c s = ch $ clu c [lt c s]
cwu :: Int -> String -> Node;  cwu c s = ch $ clu c [lu c s]

lf :: String -> Rex;           lf = LEAF WORD
lfT :: String -> Rex;          lfT = LEAF TRAD
lfQ :: String -> Rex;          lfQ = LEAF QUIP
lfP :: String -> Rex;          lfP = LEAF PAGE
lfS :: String -> Rex;          lfS = LEAF SPAN


-- Tests -----------------------------------------------------------------------

tests :: [Test]
tests =

  ---- LEAVES ------------------------------------------------------------------

  [ Test "single word" "hello"
      [cle [cw 1 "hello"]]
      (lf "hello")

  , Test "two words" "a b"
      [cle [cw 1 "a", cw 3 "b"]]
      (EXPR CLEAR [lf "a", lf "b"])

  , Test "three words" "f x y"
      [cle [cw 1 "f", cw 3 "x", cw 5 "y"]]
      (EXPR CLEAR [lf "f", lf "x", lf "y"])

  , Test "string literal" "\"hi\""
      [cle [cwt 1 "\"hi\""]]
      (lfT "hi")

  , Test "escaped quotes in string" "\"He said \"\"Hello\"\"\""
      [cle [cwt 1 "\"He said \"\"Hello\"\"\""]]
      (lfT "He said \"Hello\"")

  -- SPAN (inline ugly) tests
  , Test "span simple" "'''hello'''"
      [cle [cwu 1 "'''hello'''"]]
      (lfS "hello")

  , Test "span with quotes" "'''say \"hello\"'''"
      [cle [cwu 1 "'''say \"hello\"'''"]]
      (lfS "say \"hello\"")

  , Test "span in tight context" "x+'''y'''"
      [cle [ch $ clu 1 [lw 1 "x", ru 2 "+", lu 3 "'''y'''"]]]
      (TYTE "+" [lf "x", lfS "y"])

  , Test "span in poem" "+ a '''hello'''"
      [cle [ch $ pom 1 [ru 1 "+", cw 3 "a", cwu 5 "'''hello'''"]]]
      (OPEN "+" [lf "a", lfS "hello"])

  , Test "span in parens" "(x, '''quoted''')"
      [cle [ch $ clu 1 [ch $ par 1
        [cw 2 "x", ru 3 ",", cwu 5 "'''quoted'''"]]]]
      (NEST PAREN "," [lf "x", lfS "quoted"])

  , Test "span multiline" "'''line one\n   line two'''"
      [cle [cwu 1 "'''line one\n   line two'''"]]
      (lfS "line one\nline two")

  , Test "span in nest infix" "(a + '''b''')"
      [cle [ch $ clu 1 [ch $ par 1
        [cw 2 "a", ru 4 "+", cwu 6 "'''b'''"]]]]
      (NEST PAREN "+" [lf "a", lfS "b"])

  , Test "span multiline in poem" "+ x '''line one\n       line two'''"
      [cle [ch $ pom 1 [ru 1 "+", cw 3 "x", cwu 5 "'''line one\n       line two'''"]]]
      (OPEN "+" [lf "x", lfS "line one\nline two"])

  , Test "span multiline in nest" "(a + '''line one\n        line two''')"
      [cle [ch $ clu 1 [ch $ par 1
        [cw 2 "a", ru 4 "+", cwu 6 "'''line one\n        line two'''"]]]]
      (NEST PAREN "+" [lf "a", lfS "line one\nline two"])

  -- PAGE (block ugly) tests
  , Test "page simple" "'''\nhello\n'''"
      [cle [cwu 1 "'''\nhello\n'''"]]
      (lfP "hello")

  , Test "page multiline" "'''\nline one\nline two\n'''"
      [cle [cwu 1 "'''\nline one\nline two\n'''"]]
      (lfP "line one\nline two")

  , Test "page in poem" "+ a '''\n    content\n    '''"
      [cle [ch $ pom 1 [ru 1 "+", cw 3 "a", cwu 5 "'''\n    content\n    '''"]]]
      (OPEN "+" [lf "a", lfP "content"])

  , Test "page in parens" "(x, '''\n    body\n    ''')"
      [cle [ch $ clu 1 [ch $ par 1
        [cw 2 "x", ru 3 ",", cwu 5 "'''\n    body\n    '''"]]]]
      (NEST PAREN "," [lf "x", lfP "body"])

  , Test "span in block" "f =\n  '''content'''"
      [cle [cw 1 "f", ru 3 "=", ch $ blk 3
        [ch $ itm 3 [cwu 3 "'''content'''"]]]]
      (BLOC CLEAR "=" (lf "f") [lfS "content"])

  , Test "page in block" "f =\n  '''\n  body\n  '''"
      [cle [cw 1 "f", ru 3 "=", ch $ blk 3
        [ch $ itm 3 [cwu 3 "'''\n  body\n  '''"]]]]
      (BLOC CLEAR "=" (lf "f") [lfP "body"])

  ---- CLUMPS ------------------------------------------------------------------

  , Test "tight infix: a.b" "a.b"
      [cle [ch $ clu 1 [lw 1 "a", ru 2 ".", lw 3 "b"]]]
      (TYTE "." [lf "a", lf "b"])

  , Test "prefix rune: -x" "-x"
      [cle [ch $ clu 1 [ru 1 "-", lw 2 "x"]]]
      (PREF "-" (lf "x"))

  , Test "prefix + tight infix: -x.y" "-x.y"
      [cle [ch $ clu 1 [ru 1 "-", lw 2 "x", ru 3 ".", lw 4 "y"]]]
      (PREF "-" (TYTE "." [lf "x", lf "y"]))

  , Test "juxtaposition: f(x)" "f(x)"
      [cle [ch $ clu 1 [lw 1 "f", ch $ par 2 [cw 3 "x"]]]]
      (JUXT [lf "f", EXPR PAREN [lf "x"]])

  , Test "chained juxt: f(x)[i]" "f(x)[i]"
      [cle [ch $ clu 1
        [lw 1 "f", ch $ par 2 [cw 3 "x"], ch $ bra 5 [cw 6 "i"]]]]
      (JUXT [lf "f", EXPR PAREN [lf "x"], EXPR BRACK [lf "i"]])

  , Test "prefix + parens: +(a)" "+(a)"
      [cle [ch $ clu 1 [ru 1 "+", ch $ par 2 [cw 3 "a"]]]]
      (PREF "+" (EXPR PAREN [lf "a"]))

  , Test "parens juxt: (a)(b)" "(a)(b)"
      [cle [ch $ clu 1
        [ch $ par 1 [cw 2 "a"], ch $ par 4 [cw 5 "b"]]]]
      (JUXT [EXPR PAREN [lf "a"], EXPR PAREN [lf "b"]])

  , Test "tight: x+word" "x+word"
      [cle [ch $ clu 1 [lw 1 "x", ru 2 "+", lw 3 "word"]]]
      (TYTE "+" [lf "x", lf "word"])

  , Test "tight: x+\"text\"" "x+\"text\""
      [cle [ch $ clu 1 [lw 1 "x", ru 2 "+", lt 3 "\"text\""]]]
      (TYTE "+" [lf "x", lfT "text"])

  , Test "tight: word+x" "word+x"
      [cle [ch $ clu 1 [lw 1 "word", ru 5 "+", lw 6 "x"]]]
      (TYTE "+" [lf "word", lf "x"])

  ---- SPACE / RUNE INTERACTION ------------------------------------------------

  , Test "3 +4 is prefix clump" "3 +4"
      [cle [cw 1 "3", ch $ clu 3 [ru 3 "+", lw 4 "4"]]]
      (EXPR CLEAR [lf "3", PREF "+" (lf "4")])

  , Test "3+ 4 is infix" "3+ 4"
      [cle [cw 1 "3", ru 2 "+", cw 4 "4"]]
      (NEST CLEAR "+" [lf "3", lf "4"])

  , Test "trailing rune in parens" "(a.b,)"
      [cle [ch $ clu 1 [ch $ par 1
        [ch $ clu 2 [lw 2 "a", ru 3 ".", lw 4 "b"], ru 5 ","]]]]
      (NEST PAREN "," [TYTE "." [lf "a", lf "b"]])

  ---- NESTS -------------------------------------------------------------------

  , Test "empty parens" "()"
      [cle [ch $ clu 1 [ch $ par 1 []]]]
      (EXPR PAREN [])

  , Test "empty brackets" "[]"
      [cle [ch $ clu 1 [ch $ bra 1 []]]]
      (EXPR BRACK [])

  , Test "empty curlies" "{}"
      [cle [ch $ clu 1 [ch $ cur 1 []]]]
      (EXPR CURLY [])

  , Test "simple parens" "(a b)"
      [cle [ch $ clu 1 [ch $ par 1 [cw 2 "a", cw 4 "b"]]]]
      (EXPR PAREN [lf "a", lf "b"])

  , Test "infix in parens" "(a + b)"
      [cle [ch $ clu 1 [ch $ par 1
        [cw 2 "a", ru 4 "+", cw 6 "b"]]]]
      (NEST PAREN "+" [lf "a", lf "b"])

  , Test "comma separated" "(a, b, c)"
      [cle [ch $ clu 1 [ch $ par 1
        [cw 2 "a", ru 3 ",", cw 5 "b", ru 6 ",", cw 8 "c"]]]]
      (NEST PAREN "," [lf "a", lf "b", lf "c"])

  , Test "trailing comma" "(3, 4,)"
      [cle [ch $ clu 1 [ch $ par 1
        [cw 2 "3", ru 3 ",", cw 5 "4", ru 6 ","]]]]
      (NEST PAREN "," [lf "3", lf "4"])

  , Test "just trailing comma" "(3,)"
      [cle [ch $ clu 1 [ch $ par 1
        [cw 2 "3", ru 3 ","]]]]
      (NEST PAREN "," [lf "3"])

  , Test "clumped runes not infix" "(a ,b +c)"
      [cle [ch $ clu 1 [ch $ par 1
        [ cw 2 "a"
        , ch $ clu 4 [ru 4 ",", lw 5 "b"]
        , ch $ clu 7 [ru 7 "+", lw 8 "c"]
        ]]]]
      (EXPR PAREN [lf "a", PREF "," (lf "b"), PREF "+" (lf "c")])

  , Test "nested parens" "((a))"
      [cle [ch $ clu 1 [ch $ par 1
        [ch $ clu 2 [ch $ par 2 [cw 3 "a"]]]]]]
      (EXPR PAREN [EXPR PAREN [lf "a"]])

  , Test "multiline parens" "(a\n b)"
      [cle [ch $ clu 1 [ch $ par 1 [cw 2 "a", cw 2 "b"]]]]
      (EXPR PAREN [lf "a", lf "b"])

  , Test "mixed brackets" "(a, [b], {c})"
      [cle [ch $ clu 1 [ch $ par 1
        [ cw 2 "a"
        , ru 3 ","
        , ch $ clu 5 [ch $ bra 5 [cw 6 "b"]]
        , ru 8 ","
        , ch $ clu 10 [ch $ cur 10 [cw 11 "c"]]
        ]]]]
      (NEST PAREN "," [lf "a", EXPR BRACK [lf "b"], EXPR CURLY [lf "c"]])

  , Test "solo trailing comma" "(foo ,)"
      [cle [ch $ clu 1 [ch $ par 1 [cw 2 "foo", ru 6 ","]]]]
      (NEST PAREN "," [lf "foo"])

  ---- POEMS -------------------------------------------------------------------

  , Test "simple poem" "+ a b"
      [cle [ch $ pom 1 [ru 1 "+", cw 3 "a", cw 5 "b"]]]
      (OPEN "+" [lf "a", lf "b"])

  , Test "poem continuation" "+ a\n  b"
      [cle [ch $ pom 1 [ru 1 "+", cw 3 "a", cw 3 "b"]]]
      (OPEN "+" [lf "a", lf "b"])

  , Test "poem: same col stays inside" "+ a\nb"
      [cle [ch $ pom 1 [ru 1 "+", cw 3 "a", cw 1 "b"]]]
      (HEIR [OPEN "+" [lf "a"], lf "b"])

  , Test "poem heir" "+ a\n+ b"
      [cle [ch $ pom 1
        [ ru 1 "+", cw 3 "a"
        , ch $ pom 1 [ru 1 "+", cw 3 "b"]
        ]]]
      (HEIR [OPEN "+" [lf "a"], OPEN "+" [lf "b"]])

  , Test "poem heir with children" "+ a\n+ b\n  c"
      [cle [ch $ pom 1
        [ ru 1 "+", cw 3 "a"
        , ch $ pom 1 [ru 1 "+", cw 3 "b", cw 3 "c"]
        ]]]
      (HEIR [OPEN "+" [lf "a"], OPEN "+" [lf "b", lf "c"]])

  , Test "consecutive runes -> poem" "(x, + a b)"
      [cle [ch $ clu 1 [ch $ par 1
        [ cw 2 "x"
        , ru 3 ","
        , ch $ pom 5 [ru 5 "+", cw 7 "a", cw 9 "b"]
        ]]]]
      (NEST PAREN "," [lf "x", OPEN "+" [lf "a", lf "b"]])

  , Test "poem closed by close paren" "(+ a b) c"
      [cle
        [ ch $ clu 1 [ch $ par 1
            [ch $ pom 2 [ru 2 "+", cw 4 "a", cw 6 "b"]]]
        , cw 9 "c"
        ]]
      (EXPR CLEAR [EXPR PAREN [OPEN "+" [lf "a", lf "b"]], lf "c"])

  , Test "poem in parens, low col" "(+ a\nb)"
      [cle [ch $ clu 1 [ch $ par 1
        [ch $ pom 2 [ru 2 "+", cw 4 "a"], cw 1 "b"]]]]
      (EXPR PAREN [OPEN "+" [lf "a"], lf "b"])

  , Test "rune+rune" "(a b , + 3)"
      [cle [ch $ clu 1 [ch $ par 1
        [ cw 2 "a", cw 4 "b"
        , ru 6 ","
        , ch $ pom 8 [ru 8 "+", cw 10 "3"]
        ]]]]
      (NEST PAREN "," [EXPR CLEAR [lf "a", lf "b"], OPEN "+" [lf "3"]])

  , Test "trailing rune after slot" "(a b , 4 +)"
      [cle [ch $ clu 1 [ch $ par 1
        [ cw 2 "a", cw 4 "b"
        , ru 6 ","
        , cw 8 "4"
        , ru 10 "+"
        ]]]]
      (NEST PAREN "," [EXPR CLEAR [lf "a", lf "b"],
                        NEST CLEAR "+" [lf "4"]])

  ---- BLOCKS ------------------------------------------------------------------

  , Test "simple block" "f =\n  a\n  b"
      [cle [cw 1 "f", ru 3 "=", ch $ blk 3
        [ch $ itm 3 [cw 3 "a"], ch $ itm 3 [cw 3 "b"]]]]
      (BLOC CLEAR "=" (lf "f") [lf "a", lf "b"])

  , Test "block with expressions" "f =\n  a + b\n  c + d"
      [cle [cw 1 "f", ru 3 "=", ch $ blk 3
        [ ch $ itm 3 [cw 3 "a", ru 5 "+", cw 7 "b"]
        , ch $ itm 3 [cw 3 "c", ru 5 "+", cw 7 "d"]
        ]]]
      (BLOC CLEAR "=" (lf "f")
        [NEST CLEAR "+" [lf "a", lf "b"],
         NEST CLEAR "+" [lf "c", lf "d"]])

  , Test "block: poem eats items" "f =\n  + a\n  b\n  c"
      [cle [cw 1 "f", ru 3 "=", ch $ blk 3
        [ch $ itm 3 [ch $ pom 3
          [ru 3 "+", cw 5 "a", cw 3 "b", cw 3 "c"]]]]]
      (BLOC CLEAR "=" (lf "f")
        [HEIR [OPEN "+" [lf "a"], lf "b", lf "c"]])

  , Test "nested block" "f =\n  g =\n    x\n  y"
      [cle [cw 1 "f", ru 3 "=", ch $ blk 3
        [ ch $ itm 3 [cw 3 "g", ru 5 "=", ch $ blk 5
            [ch $ itm 5 [cw 5 "x"]]]
        , ch $ itm 3 [cw 3 "y"]
        ]]]
      (BLOC CLEAR "=" (lf "f")
        [BLOC CLEAR "=" (lf "g") [lf "x"], lf "y"])

  , Test "trailing rune in item opens nested block"
      "f =\n  a +\n    b\n  c"
      [cle [cw 1 "f", ru 3 "=", ch $ blk 3
        [ ch $ itm 3 [cw 3 "a", ru 5 "+", ch $ blk 5
            [ch $ itm 5 [cw 5 "b"]]]
        , ch $ itm 3 [cw 3 "c"]
        ]]]
      (BLOC CLEAR "=" (lf "f")
        [BLOC CLEAR "+" (lf "a") [lf "b"], lf "c"])

  , Test "two runes don't trigger block" "a + b =\n  x"
      [cle [cw 1 "a", ru 3 "+", cw 5 "b", ru 7 "=", cw 3 "x"]]
      (NEST CLEAR "=" [NEST CLEAR "+" [lf "a", lf "b"], lf "x"])

  , Test "block in parens" "(f =\n   a\n   b)"
      [cle [ch $ clu 1 [ch $ par 1
        [cw 2 "f", ru 4 "=", ch $ blk 4
          [ch $ itm 4 [cw 4 "a"], ch $ itm 4 [cw 4 "b"]]]]]]
      (BLOC PAREN "=" (lf "f") [lf "a", lf "b"])

  , Test "block item with nested parens"
      "def foo(x, y):\n    x += y\n    return x"
      [cle
        [ cw 1 "def"
        , ch $ clu 5 [lw 5 "foo", ch $ par 8 [cw 9 "x", ru 10 ",", cw 12 "y"]]
        , ru 14 ":"
        , ch $ blk 5
          [ ch $ itm 5 [cw 5 "x", ru 8 "+=", cw 10 "y"]
          , ch $ itm 5 [cw 5 "return", cw 12 "x"]
          ]
        ]]
      (BLOC CLEAR ":"
        (EXPR CLEAR [lf "def", JUXT [lf "foo", NEST PAREN "," [lf "x", lf "y"]]])
        [NEST CLEAR "+=" [lf "x", lf "y"],
         EXPR CLEAR [lf "return", lf "x"]])

  ---- QUIPS -------------------------------------------------------------------

  , Test "quip of word" "'x"
      [cle [ch $ clu 1 [ch $ qup 1 [ch $ clu 2 [lw 2 "x"]]]]]
      (lfQ "'x")

  , Test "quip of tight form" "'a.b"
      [cle [ch $ clu 1 [ch $ qup 1
        [ch $ clu 2 [lw 2 "a", ru 3 ".", lw 4 "b"]]]]]
      (lfQ "'a.b")

  , Test "quip in expression" "f 'x y"
      [cle
        [ cw 1 "f"
        , ch $ clu 3 [ch $ qup 3 [ch $ clu 4 [lw 4 "x"]]]
        , cw 6 "y"
        ]]
      (EXPR CLEAR [lf "f", lfQ "'x", lf "y"])

  , Test "quip of parens" "'(a + b)"
      [cle [ch $ clu 1 [ch $ qup 1
        [ch $ clu 2 [ch $ par 2
          [cw 3 "a", ru 5 "+", cw 7 "b"]]]]]]
      (lfQ "'(a + b)")

  , Test "quip of poem" "'+ a b"
      [cle [ch $ clu 1 [ch $ qup 1
        [ch $ pom 2 [ru 2 "+", cw 4 "a", cw 6 "b"]]]]]
      (lfQ "'+ a b")

  , Test "quip with tight rune" "'Quip;Semi"
      [cle [ch $ clu 1 [ch $ qup 1
        [ch $ clu 2 [lw 2 "Quip", ru 6 ";", lw 7 "Semi"]]]]]
      (lfQ "'Quip;Semi")

  , Test "quip with trad" "'Quip\"Trad\""
      [cle [ch $ clu 1 [ch $ qup 1
        [ch $ clu 2 [lw 2 "Quip", lt 6 "\"Trad\""]]]]]
      (lfQ "'Quip\"Trad\"")

  , Test "nested quips" "'Quip'Quip"
      [cle
        [ ch $ clu 1 [ch $ qup 1 [ch $ clu 2 [lw 2 "Quip"]]]
        , ch $ clu 6 [ch $ qup 6 [ch $ clu 7 [lw 7 "Quip"]]]
        ]]
      (EXPR CLEAR [lfQ "'Quip", lfQ "'Quip"])

  , Test "quip of brackets" "'[b]"
      [cle [ch $ clu 1 [ch $ qup 1
        [ch $ clu 2 [ch $ bra 2 [cw 3 "b"]]]]]]
      (lfQ "'[b]")

  , Test "quip juxt" "('x(y))"
      [cle [ch $ clu 1 [ch $ par 1
        [ch $ clu 2 [ch $ qup 2
          [ch $ clu 3 [lw 3 "x", ch $ par 4 [cw 5 "y"]]]]]]]]
      (EXPR PAREN [lfQ "'x(y)"])

  ---- EDGE CASES --------------------------------------------------------------

  , Test "quip in nest with infix" "(a, 'b, c)"
      [cle [ch $ clu 1 [ch $ par 1
        [ cw 2 "a"
        , ru 3 ","
        , ch $ clu 5 [ch $ qup 5 [ch $ clu 6 [lw 6 "b"]]]
        , ru 7 ","
        , cw 9 "c"
        ]]]]
      (NEST PAREN "," [lf "a", lfQ "'b", lf "c"])

  , Test "top-level multi infix" "a + b * c"
      [cle [cw 1 "a", ru 3 "+", cw 5 "b", ru 7 "*", cw 9 "c"]]
      (NEST CLEAR "+" [lf "a", NEST CLEAR "*" [lf "b", lf "c"]])

  , Test "tight.infix mixed" "foo.x + bar.y"
      [cle
        [ ch $ clu 1 [lw 1 "foo", ru 4 ".", lw 5 "x"]
        , ru 7 "+"
        , ch $ clu 9 [lw 9 "bar", ru 12 ".", lw 13 "y"]
        ]]
      (NEST CLEAR "+" [TYTE "." [lf "foo", lf "x"],
                        TYTE "." [lf "bar", lf "y"]])

  ---- EXTENT TESTS ------------------------------------------------------------

  , ExtentTest "extent: single word" "hello"
      [("hello", "hello")]
  , ExtentTest "extent: two words" "a b"
      [("a b", "a b")]
  , ExtentTest "extent: tight infix" "a.b"
      [("a.b", "a.b")]
  , ExtentTest "extent: two inputs" "a\n\nb"
      [("a", "a"), ("b", "b")]
  , ExtentTest "extent: parens" "(a + b)"
      [("(a + b)", "(a + b)")]
  , ExtentTest "extent: block" "f =\n  a\n  b"
      [("f =\n  a\n  b", "f =\n  a\n  b")]
  , ExtentTest "extent: poem" "+ a b"
      [("+ a b", "+ a b")]
  , ExtentTest "extent: multiline block" "f =\n  a\n  b\n\ng =\n  c"
      [("f =\n  a\n  b", "f =\n  a\n  b"), ("g =\n  c", "g =\n  c")]
  , ExtentTest "extent: quip" "'x y"
      [("'x y", "'x y")]

  , ExtentTest "extent: quip multi-input" "a\n\n(b, 'c)"
      [("a", "a"), ("(b, 'c)", "(b, 'c)")]

  , MultiRexTest "multi-input quip" "a\n\n(b, 'c)"
      [lf "a", NEST PAREN "," [lf "b", lfQ "'c"]]

  , MultiRexTest "quip after lines with notes"
      "x.y ') basic\n\n(a, 'b)"
      [TYTE "." [lf "x", lf "y"], NEST PAREN "," [lf "a", lfQ "'b"]]

  , MultiRexTest "quip after many inputs with notes"
      "x.y ') a\n\nx\"y\".a\"b\" ') b\n\nfoo.x=bar.x ') c\n\n(a, b.c, 'd, \"e\") ') d"
      [ TYTE "." [lf "x", lf "y"]
      , TYTE "." [JUXT [lf "x", lfT "y"], JUXT [lf "a", lfT "b"]]
      , TYTE "=" [TYTE "." [lf "foo", lf "x"], TYTE "." [lf "bar", lf "x"]]
      , NEST PAREN "," [lf "a", TYTE "." [lf "b", lf "c"], lfQ "'d", lfT "e"]
      ]

  ]
