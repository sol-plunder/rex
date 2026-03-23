{-# LANGUAGE LambdaCase #-}

-- Copyright (c) 2026 Benjamin Summers
-- SPDX-License-Identifier: MIT
-- See LICENSE for full terms.
--
-- Test cases for Rex.PrintTree.

module Rex.PrintTreeTest (printTreeTestMain) where

import Rex.Tree2
import Rex.PrintTree


-- Test Harness ----------------------------------------------------------------

data Test = Test
    { testName     :: String
    , testWidth    :: Int
    , testTree     :: Tree
    , testExpected :: String
    }

run :: Test -> (Bool, String)
run (Test name width tree expected) =
    let actual = printTree width tree
        ok     = actual == expected
    in if ok
       then (True,  "  OK  " ++ name)
       else (False, unlines
               [ "  FAIL " ++ name
               , "    width:    " ++ show width
               , "    expected: " ++ show expected
               , "    actual:   " ++ show actual
               ])

printTreeTestMain :: IO ()
printTreeTestMain = do
    let results = map run tests
        fails   = filter (not . fst) results
        total   = length results
        passed  = length (filter fst results)
    mapM_ (putStrLn . snd) results
    putStrLn ""
    putStrLn $ show passed ++ "/" ++ show total ++ " passed"
    if null fails
        then pure ()
        else putStrLn $ show (length fails) ++ " FAILED"


-- Shorthand Constructors (mirroring Test.hs) ----------------------------------

cle :: [Node] -> Tree;  cle = Tree (S_NEST Clear) 0 0 0
par :: Int -> [Node] -> Tree;  par p = Tree (S_NEST Paren) p 0 0
bra :: Int -> [Node] -> Tree;  bra p = Tree (S_NEST Brack) p 0 0
cur :: Int -> [Node] -> Tree;  cur p = Tree (S_NEST Curly) p 0 0
clu :: Int -> [Node] -> Tree;  clu p = Tree S_CLUMP p 0 0
pom :: Int -> [Node] -> Tree;  pom p = Tree S_POEM p 0 0
blk :: Int -> [Node] -> Tree;  blk p = Tree S_BLOCK p 0 0
itm :: Int -> [Node] -> Tree;  itm p = Tree S_ITEM p 0 0
qup :: Int -> [Node] -> Tree;  qup p = Tree S_QUIP p 0 0

lw :: Int -> String -> Node;  lw c s = N_LEAF c (L_WORD s)
lt :: Int -> String -> Node;  lt c s = N_LEAF c (L_TRAD s)
ru :: Int -> String -> Node;  ru = N_RUNE
ch :: Tree -> Node;           ch = N_CHILD
cw :: Int -> String -> Node;  cw c s = ch $ clu c [lw c s]


-- Tests -----------------------------------------------------------------------

tests :: [Test]
tests =

  ---- LEAVES ------------------------------------------------------------------

  [ Test "single word" 80
      (cle [cw 1 "hello"])
      "hello"

  , Test "trad string" 80
      (cle [ch $ clu 1 [lt 1 "\"hello\""]])
      "\"hello\""

  ---- CLUMPS ------------------------------------------------------------------

  , Test "tight infix a.b" 80
      (cle [ch $ clu 1 [lw 1 "a", ru 2 ".", lw 3 "b"]])
      "a.b"

  , Test "tight prefix -x" 80
      (cle [ch $ clu 1 [ru 1 "-", lw 2 "x"]])
      "-x"

  , Test "tight prefix + tight infix: -x.y" 80
      (cle [ch $ clu 1 [ru 1 "-", lw 2 "x", ru 3 ".", lw 4 "y"]])
      "-x.y"

  , Test "juxtaposition f(x)" 80
      (cle [ch $ clu 1 [lw 1 "f", ch $ par 2 [cw 3 "x"]]])
      "f(x)"

  ---- NESTS -------------------------------------------------------------------

  , Test "empty parens" 80
      (cle [ch $ clu 1 [ch $ par 1 []]])
      "()"

  , Test "empty brackets" 80
      (cle [ch $ clu 1 [ch $ bra 1 []]])
      "[]"

  , Test "empty curlies" 80
      (cle [ch $ clu 1 [ch $ cur 1 []]])
      "{}"

  , Test "simple parens" 80
      (cle [ch $ clu 1 [ch $ par 1 [cw 2 "a", cw 4 "b"]]])
      "(a b)"

  , Test "infix in parens" 80
      (cle [ch $ clu 1 [ch $ par 1 [cw 2 "a", ru 4 "+", cw 6 "b"]]])
      "(a + b)"

  , Test "brackets with words" 80
      (cle [ch $ clu 1 [ch $ bra 1 [cw 2 "x", cw 4 "y", cw 6 "z"]]])
      "[x y z]"

  -- Wrapping: narrow width forces expansion, items indent to bracket column
  , Test "parens wrap on narrow width" 5
      (cle [ch $ clu 1 [ch $ par 1 [cw 2 "foo", cw 6 "bar", cw 10 "baz"]]])
      "(foo\n bar\n baz)"

  ---- QUIPS -------------------------------------------------------------------

  , Test "quip of word" 80
      (cle [ch $ clu 1 [ch $ qup 1 [ch $ clu 2 [lw 2 "x"]]]])
      "'x"

  , Test "quip of tight form" 80
      (cle [ch $ clu 1 [ch $ qup 1
        [ch $ clu 2 [lw 2 "a", ru 3 ".", lw 4 "b"]]]])
      "'a.b"

  ---- POEMS -------------------------------------------------------------------

  , Test "simple poem" 80
      (cle [ch $ pom 1 [ru 1 "+", cw 3 "a", cw 5 "b"]])
      "+ a b"

  , Test "poem with three children" 80
      (cle [ch $ pom 1 [ru 1 "+", cw 3 "a", cw 5 "b", cw 7 "c"]])
      "+ a b c"

  , Test "nested poem" 80
      (cle [ch $ pom 1
        [ ru 1 "+"
        , cw 3 "a"
        , ch $ pom 5 [ru 5 "*", cw 7 "b", cw 9 "c"]
        ]])
      "+ a * b c"

  ---- BLOCKS ------------------------------------------------------------------

  -- Items are indented under the block start (PDent anchors to block column)
  , Test "simple block" 80
      (cle [ cw 1 "f"
           , ru 3 "="
           , ch $ blk 3
               [ ch $ itm 3 [cw 3 "a"]
               , ch $ itm 3 [cw 3 "b"]
               ]
           ])
      "f = a\n    b"

  , Test "block with expressions" 80
      (cle [ cw 1 "f"
           , ru 3 "="
           , ch $ blk 3
               [ ch $ itm 3 [cw 3 "a", ru 5 "+", cw 7 "b"]
               , ch $ itm 3 [cw 3 "c", ru 5 "+", cw 7 "d"]
               ]
           ])
      "f = a + b\n    c + d"

  ]
