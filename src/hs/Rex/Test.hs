{-# LANGUAGE LambdaCase #-}

module Rex.Test (testMain) where

import Rex.Lex (lexRex, bsplit, Span(..))
import Rex.Tree2 hiding (treeMain)
import Rex.Rex hiding (rexMain)

-- | No span (for test expected values)
ns :: Span
ns = noSpan

-- Test Harness ----------------------------------------------------------------

data Test = Test String String [Tree] Rex  -- name, input, tree, rex

parse :: String -> [Tree]
parse = parseTree . bsplit . lexRex

-- | Strip span details to compare just structure + column
--   Zeroes: line, offset, length. Preserves: column.
stripSpan :: Span -> Span
stripSpan s = s { spanLin = 0, spanOff = 0, spanLen = 0 }

stripTree :: Tree -> Tree
stripTree (Tree sh s ns) = Tree sh (stripSpan s) (map stripNode ns)

stripNode :: Node -> Node
stripNode (N_CHILD t)  = N_CHILD (stripTree t)
stripNode (N_LEAF s l) = N_LEAF (stripSpan s) l
stripNode (N_RUNE s r) = N_RUNE (stripSpan s) r

toRex :: String -> Rex
toRex src = case parseRex src of
    [(slice, tree)] -> case rexFromBlockTree slice tree of
                         Just r  -> stripRex r
                         Nothing -> EXPR ns CLEAR []
    _ -> error "toRex: expected exactly one input"

-- | Strip spans from Rex for structural comparison
stripRex :: Rex -> Rex
stripRex = \case
    LEAF _ sh s         -> LEAF ns sh s
    NEST _ c r kids     -> NEST ns c r (map stripRex kids)
    EXPR _ c kids       -> EXPR ns c (map stripRex kids)
    PREF _ r child      -> PREF ns r (stripRex child)
    TYTE _ r kids       -> TYTE ns r (map stripRex kids)
    JUXT _ kids         -> JUXT ns (map stripRex kids)
    HEIR _ kids         -> HEIR ns (map stripRex kids)
    BLOC _ c r hd items -> BLOC ns c r (stripRex hd) (map stripRex items)
    OPEN _ r kids       -> OPEN ns r (map stripRex kids)

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

sp :: Int -> Span;             sp c = Span 0 c 0 0

cle :: [Node] -> Tree;         cle = Tree (S_NEST Clear) (sp 0)
par :: Int -> [Node] -> Tree;  par c = Tree (S_NEST Paren) (sp c)
clu :: Int -> [Node] -> Tree;  clu c = Tree S_CLUMP (sp c)
pom :: Int -> [Node] -> Tree;  pom c = Tree S_POEM (sp c)
blk :: Int -> [Node] -> Tree;  blk c = Tree S_BLOCK (sp c)
itm :: Int -> [Node] -> Tree;  itm c = Tree S_ITEM (sp c)

lw :: Int -> String -> Node;   lw c s = N_LEAF (sp c) (L_WORD s)
lt :: Int -> String -> Node;   lt c s = N_LEAF (sp c) (L_TRAD s)
lu :: Int -> String -> Node;   lu c s = N_LEAF (sp c) (L_UGLY s)
ru :: Int -> String -> Node;   ru c r = N_RUNE (sp c) r
ch :: Tree -> Node;            ch = N_CHILD
cw :: Int -> String -> Node;   cw c s = ch $ clu c [lw c s]
cwt :: Int -> String -> Node;  cwt c s = ch $ clu c [lt c s]
cwu :: Int -> String -> Node;  cwu c s = ch $ clu c [lu c s]

lf :: String -> Rex;           lf = LEAF ns WORD
lfC :: String -> Rex;          lfC = LEAF ns CORD
lfP :: String -> Rex;          lfP = LEAF ns PAGE
lfS :: String -> Rex;          lfS = LEAF ns SPAN


-- Tests -----------------------------------------------------------------------
--
-- These tests verify behavior that CANNOT be tested via round-trip printing:
-- - Whitespace sensitivity (space placement changes semantics)
-- - Column sensitivity (poem/heir behavior depends on columns)
-- - String content extraction (verify escape handling produces correct content)
-- - Tree structure (verifies parsing produces expected Tree shapes)

tests :: [Test]
tests =

  ---- STRING CONTENT EXTRACTION -----------------------------------------------
  -- These verify that string literals extract to the correct content

  [ Test "escaped quotes in string" "\"He said \"\"Hello\"\"\""
      [cle [cwt 1 "\"He said \"\"Hello\"\"\""]]
      (lfC "He said \"Hello\"")

  , Test "span strips content" "'''hello'''"
      [cle [cwu 1 "'''hello'''"]]
      (lfS "hello")

  , Test "span with quotes extracts quotes" "'''say \"hello\"'''"
      [cle [cwu 1 "'''say \"hello\"'''"]]
      (lfS "say \"hello\"")

  , Test "span multiline strips indent" "'''line one\n   line two'''"
      [cle [cwu 1 "'''line one\n   line two'''"]]
      (lfS "line one\nline two")

  , Test "page strips content" "'''\nhello\n'''"
      [cle [cwu 1 "'''\nhello\n'''"]]
      (lfP "hello")

  , Test "page multiline joins lines" "'''\nline one\nline two\n'''"
      [cle [cwu 1 "'''\nline one\nline two\n'''"]]
      (lfP "line one\nline two")

  ---- WHITESPACE SENSITIVITY --------------------------------------------------
  -- Space placement determines whether runes are prefix or infix

  , Test "3 +4 is prefix clump" "3 +4"
      [cle [cw 1 "3", ch $ clu 3 [ru 3 "+", lw 4 "4"]]]
      (EXPR ns CLEAR [lf "3", PREF ns "+" (lf "4")])

  , Test "3+ 4 is infix" "3+ 4"
      [cle [cw 1 "3", ru 2 "+", cw 4 "4"]]
      (NEST ns CLEAR "+" [lf "3", lf "4"])

  , Test "clumped runes not infix" "(a ,b +c)"
      [cle [ch $ clu 1 [ch $ par 1
        [ cw 2 "a"
        , ch $ clu 4 [ru 4 ",", lw 5 "b"]
        , ch $ clu 7 [ru 7 "+", lw 8 "c"]
        ]]]]
      (EXPR ns PAREN [lf "a", PREF ns "," (lf "b"), PREF ns "+" (lf "c")])

  ---- COLUMN SENSITIVITY ------------------------------------------------------
  -- Poem and heir behavior depends on column positions

  , Test "poem: same col stays inside" "+ a\nb"
      [cle [ch $ pom 1 [ru 1 "+", cw 3 "a", cw 1 "b"]]]
      (HEIR ns [OPEN ns "+" [lf "a"], lf "b"])

  , Test "poem heir" "+ a\n+ b"
      [cle [ch $ pom 1
        [ ru 1 "+", cw 3 "a"
        , ch $ pom 1 [ru 1 "+", cw 3 "b"]
        ]]]
      (HEIR ns [OPEN ns "+" [lf "a"], OPEN ns "+" [lf "b"]])

  , Test "poem heir with children" "+ a\n+ b\n  c"
      [cle [ch $ pom 1
        [ ru 1 "+", cw 3 "a"
        , ch $ pom 1 [ru 1 "+", cw 3 "b", cw 3 "c"]
        ]]]
      (HEIR ns [OPEN ns "+" [lf "a"], OPEN ns "+" [lf "b", lf "c"]])

  , Test "poem in parens, low col" "(+ a\nb)"
      [cle [ch $ clu 1 [ch $ par 1
        [ch $ pom 2 [ru 2 "+", cw 4 "a"], cw 1 "b"]]]]
      (EXPR ns PAREN [OPEN ns "+" [lf "a"], lf "b"])

  , Test "block: poem eats items" "f =\n  + a\n  b\n  c"
      [cle [cw 1 "f", ru 3 "=", ch $ blk 3
        [ch $ itm 3 [ch $ pom 3
          [ru 3 "+", cw 5 "a", cw 3 "b", cw 3 "c"]]]]]
      (BLOC ns CLEAR "=" (lf "f")
        [HEIR ns [OPEN ns "+" [lf "a"], lf "b", lf "c"]])

  ---- STRUCTURE VERIFICATION --------------------------------------------------
  -- Tests that verify specific parsing rules

  , Test "two runes don't trigger block" "a + b =\n  x"
      [cle [cw 1 "a", ru 3 "+", cw 5 "b", ru 7 "=", cw 3 "x"]]
      (NEST ns CLEAR "=" [NEST ns CLEAR "+" [lf "a", lf "b"], lf "x"])

  , Test "trailing rune after slot" "(a b , 4 +)"
      [cle [ch $ clu 1 [ch $ par 1
        [ cw 2 "a", cw 4 "b"
        , ru 6 ","
        , cw 8 "4"
        , ru 10 "+"
        ]]]]
      (NEST ns PAREN "," [EXPR ns CLEAR [lf "a", lf "b"],
                        NEST ns CLEAR "+" [lf "4"]])

  ]
