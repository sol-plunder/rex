-- Copyright (c) 2026 xoCore Technologies
-- SPDX-License-Identifier: MIT
-- See LICENSE for full terms.
module Main (main) where

import System.Exit    (exitFailure)
import System.IO      (hPutStrLn, stderr)
import System.Environment (getArgs)

import qualified Rex.CLI          as CLI
import qualified Rex.PrintRexTest as PrintRexTest

usage :: String
usage = unlines
    [ "Usage: rex <command>"
    , ""
    , "Commands:"
    , "  lex              Tokenize stdin and print token stream"
    , "  tree             Parse stdin and print structural tree"
    , "  rex              Parse stdin and print Rex IR"
    , "  check            Parse stdin and report any errors (BAD tokens)"
    , "  pretty [--debug] Parse stdin and pretty-print using layout engine"
    , "  rex-test         Run Rex pretty-printer test suite"
    ]

main :: IO ()
main = do
    args <- getArgs
    case args of
        ["lex"]               -> CLI.lexMain
        ["tree"]              -> CLI.treeMain
        ["rex"]               -> CLI.rexMain
        ["check"]             -> CLI.checkMain
        ["pretty"]            -> CLI.prettyRexMain False
        ["pretty", "--debug"] -> CLI.prettyRexMain True
        ["rex-test"]          -> PrintRexTest.printRexTestMain
        _                     -> hPutStrLn stderr usage >> exitFailure
