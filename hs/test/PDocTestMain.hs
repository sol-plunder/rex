module Main (main) where

import System.Exit (exitFailure, exitSuccess)
import Rex.PDocTest (pdocTestMainIO)

main :: IO ()
main = do
    success <- pdocTestMainIO
    if success then exitSuccess else exitFailure
