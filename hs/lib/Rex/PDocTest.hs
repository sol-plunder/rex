-- Copyright (c) 2026 xoCore Technologies
-- SPDX-License-Identifier: MIT
-- See LICENSE for full terms.
--
-- Tests for Rex.PDoc, focused on the PFlow layout combinator.

module Rex.PDocTest
    ( pdocTestMainIO
    , runPDocTests
    ) where

import Rex.PDoc

--------------------------------------------------------------------------------
-- Test Infrastructure
--------------------------------------------------------------------------------

data Test = Test
    { tName     :: String
    , tWidth    :: Int
    , tDoc      :: PDoc
    , tExpected :: String
    }

runTest :: Test -> (Bool, String)
runTest t =
    let actual = render (tWidth t) (tDoc t)
    in if actual == tExpected t
       then (True, "OK   " ++ tName t)
       else (False, unlines
           [ "FAIL " ++ tName t
           , "  Expected:"
           , indent 4 (tExpected t)
           , "  Got:"
           , indent 4 actual
           ])
  where
    indent n s = unlines $ map (replicate n ' ' ++) (lines s)

runTests :: [Test] -> IO Bool
runTests tests = do
    let results = map runTest tests
        (passed, failed) = foldr categorize ([], []) results
    mapM_ putStrLn (map snd passed)
    mapM_ putStrLn (map snd failed)
    let total = length tests
        passCount = length passed
    putStrLn $ "\n" ++ show passCount ++ "/" ++ show total ++ " passed"
    return (null failed)
  where
    categorize (True, msg) (ps, fs) = ((True, msg):ps, fs)
    categorize (False, msg) (ps, fs) = (ps, (False, msg):fs)

--------------------------------------------------------------------------------
-- PFlow Tests
--------------------------------------------------------------------------------

-- Helper to build text items
t :: String -> PDoc
t = pdocText

-- Helper to build flow documents
flow :: Int -> [String] -> PDoc
flow maxW strs = pdocFlow maxW (map pdocText strs)

pflowTests :: [Test]
pflowTests =
    [ -- Basic flow packing
      Test "flow: single item"
           80
           (flow 20 ["hello"])
           "hello"

    , Test "flow: two small items fit"
           80
           (flow 20 ["hello", "world"])
           "hello world"

    , Test "flow: many items pack onto lines"
           30
           (flow 10 ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"])
           "a b c d e f g h i j k l"

    , Test "flow: wrap when line full"
           20
           (flow 10 ["alpha", "beta", "gamma", "delta", "epsilon"])
           "alpha beta gamma\ndelta epsilon"

    , Test "flow: respect maxW for item classification"
           40
           (flow 5 ["ab", "cd", "abcdefghij", "ef", "gh"])
           "ab cd\nabcdefghij\nef gh"

    -- Items with newlines get own line
    , Test "flow: item with newline gets own line"
           40
           (pdocFlow 20 [t "before", PCat (t "line1") (PCat PLine (t "line2")), t "after"])
           "before\nline1\nline2\nafter"

    -- Flow inside indentation
    , Test "flow: indented flow"
           30
           (PCat (t "prefix ") (PDent (flow 10 ["one", "two", "three", "four"])))
           "prefix one two three four"

    , Test "flow: indented flow wraps at indent"
           20
           (PCat (t "prefix ") (PDent (flow 10 ["one", "two", "three", "four"])))
           "prefix one two three\n       four"

    -- Empty and single-item edge cases
    , Test "flow: empty list"
           80
           (pdocFlow 20 [])
           ""

    , Test "flow: pdocFlow with single item uses single item"
           80
           (pdocFlow 20 [t "only"])
           "only"

    -- Flow followed by more content
    , Test "flow: content after flow"
           30
           (PCat (flow 10 ["a", "b", "c"]) (PCat PLine (t "end")))
           "a b c\nend"

    -- Flow starting at non-zero column
    , Test "flow: flow after text on same line"
           30
           (PCat (t "start: ") (flow 5 ["x", "y", "z", "w"]))
           "start: x y z w"

    , Test "flow: flow after text wraps correctly"
           15
           (PCat (t "start: ") (flow 5 ["x", "y", "z", "w"]))
           "start: x y z w"

    , Test "flow: flow after text, some wrap"
           12
           (PCat (t "start: ") (flow 5 ["aa", "bb", "cc", "dd"]))
           "start: aa bb\ncc dd"

    -- Large items that exceed maxW
    , Test "flow: large item alone"
           80
           (flow 5 ["thisisaverylongword"])
           "thisisaverylongword"

    , Test "flow: large item between small ones"
           40
           (flow 5 ["a", "b", "verylongword", "c", "d"])
           "a b\nverylongword\nc d"

    -- Nested flows (unusual but should work)
    , Test "flow: nested flow"
           30
           (pdocFlow 15 [t "outer1", pdocFlow 5 [t "in1", t "in2"], t "outer2"])
           "outer1 in1 in2 outer2"

    -- Flow with choice (PChoice)
    , Test "flow: item with choice prefers flat"
           40
           (pdocFlow 20 [t "a", PChoice (t "short") (PCat (t "long") (PCat PLine (t "form"))), t "b"])
           "a short b"

    , Test "flow: item with choice falls back when needed"
           15
           (pdocFlow 5 [t "a", PChoice (t "short") (PCat (t "lo") (PCat PLine (t "ng"))), t "b"])
           "a short b"
    ]

--------------------------------------------------------------------------------
-- Additional PDoc Tests (for completeness)
--------------------------------------------------------------------------------

otherPDocTests :: [Test]
otherPDocTests =
    [ Test "basic: empty"
           80
           PEmpty
           ""

    , Test "basic: text"
           80
           (t "hello")
           "hello"

    , Test "basic: newline"
           80
           (PCat (t "line1") (PCat PLine (t "line2")))
           "line1\nline2"

    , Test "basic: indent"
           80
           (PCat (t "a ") (PDent (PCat (t "b") (PCat PLine (t "c")))))
           "a b\n  c"

    , Test "choice: fits"
           80
           (PChoice (t "short") (PCat (t "longer") (PCat PLine (t "form"))))
           "short"

    , Test "choice: doesn't fit"
           5
           (PChoice (t "toolong") (t "ok"))
           "ok"

    , Test "nofit: forces fallback"
           80
           (PChoice (PNoFit (t "never")) (t "always"))
           "always"
    ]

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

allTests :: [Test]
allTests = pflowTests ++ otherPDocTests

runPDocTests :: IO Bool
runPDocTests = runTests allTests

pdocTestMainIO :: IO Bool
pdocTestMainIO = do
    putStrLn "=== PDoc Tests ==="
    runPDocTests
