-- Test driver for cabal test
module Main (main) where

import System.Exit (exitFailure, exitSuccess)
import Rex.PrintTreeTest (printTreeTestMainIO)

main :: IO ()
main = do
    ok <- printTreeTestMainIO
    if ok then exitSuccess else exitFailure
