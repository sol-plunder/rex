module Main (main) where

import System.Exit (exitFailure, exitSuccess)
import Rex.PrintRexTest (printRexTestMainIO)

main :: IO ()
main = do
    success <- printRexTestMainIO
    if success then exitSuccess else exitFailure
