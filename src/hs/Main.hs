-- Copyright (c) 2026 xoCore Technologies
-- SPDX-License-Identifier: MIT
-- See LICENSE for full terms.
module Main (main) where

import System.Exit    (exitFailure)
import System.IO      (hPutStrLn, stderr)
import System.Environment (getArgs)

import qualified Rex.Lex   as Lex
import qualified Rex.Tree2 as Tree2
import qualified Rex.Rex   as Rex
import qualified Rex.Print as Print
import qualified Rex.PrintRex      as PrintRex
import qualified Rex.PrintRexTest  as PrintRexTest
import qualified Rex.Test          as Test

usage :: String
usage = unlines
    [ "Usage: rex <command>"
    , ""
    , "Commands:"
    , "  lex         Tokenize stdin and print token stream"
    , "  tree        Parse stdin and print structural tree"
    , "  rex         Parse stdin and print Rex IR"
    , "  print       Parse stdin and pretty-print as Rex notation (old)"
    , "  pretty-rex  Parse stdin and pretty-print using new layout engine (Rex)"
    , "  test        Run Rex parser test suite"
    , "  rex-test    Run Rex pretty-printer test suite"
    ]

main :: IO ()
main = do
    args <- getArgs
    case args of
        ["lex"]        -> Lex.lexMain
        ["tree"]       -> Tree2.treeMain
        ["rex"]        -> Rex.rexMain
        ["print"]      -> Print.printMain
        ["pretty-rex"] -> PrintRex.prettyRexMain
        ["test"]       -> Test.testMain
        ["rex-test"]   -> PrintRexTest.printRexTestMain
        _              -> hPutStrLn stderr usage >> exitFailure
