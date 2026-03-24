{-# LANGUAGE LambdaCase #-}

-- Copyright (c) 2026 Benjamin Summers
-- SPDX-License-Identifier: MIT
-- See LICENSE for full terms.
--
-- Round-trip test cases for Rex.PrintRex.
--
-- Tests are loaded from src/hs/ex/print-rex/*.tests in the format:
--   === test name | width
--   code that should round-trip exactly...

module Rex.PrintRexTest (printRexTestMain, printRexTestMainIO) where

import Rex.Tree2
import Rex.Rex
import Rex.PrintRex
import Data.List (isPrefixOf, stripPrefix, dropWhileEnd, sort)
import Data.Char (isSpace)
import System.IO (hPutStrLn, stderr)
import System.Directory (listDirectory)
import System.FilePath ((</>), takeExtension)


-- Test Data Structure ---------------------------------------------------------

data Test = Test
    { testName  :: String
    , testWidth :: Int
    , testCode  :: String
    }


-- Test File Parser ------------------------------------------------------------

parseTestFile :: String -> Either String [Test]
parseTestFile content = parseTests (lines content) 1

parseTests :: [String] -> Int -> Either String [Test]
parseTests [] _ = Right []
parseTests ls lineNum
    | all isBlankOrComment ls = Right []
    | otherwise = case dropWhile isBlankOrComment ls of
        [] -> Right []
        (headerLine:rest) ->
            let newLineNum = lineNum + length (takeWhile isBlankOrComment ls)
            in case parseHeader headerLine of
                Nothing -> Left $ "Line " ++ show newLineNum
                               ++ ": expected '=== name | width', got: "
                               ++ headerLine
                Just (name, width) ->
                    let (codeLines, remaining) = break isHeaderLine rest
                        -- Strip trailing blank/comment lines from code
                        codeLines' = dropWhileEnd isBlankOrComment codeLines
                        code = unlines' codeLines'
                        test = Test name width code
                        nextLine = newLineNum + 1 + length codeLines
                    in case parseTests remaining nextLine of
                        Left err -> Left err
                        Right ts -> Right (test : ts)

parseHeader :: String -> Maybe (String, Int)
parseHeader s = case stripPrefix "=== " s of
    Nothing -> Nothing
    Just rest -> case break (== '|') rest of
        (_, []) -> Nothing
        (namePart, '|':widthPart) ->
            case reads (dropWhile isSpace widthPart) of
                [(w, trailing)] | all isSpace trailing ->
                    Just (trimEnd namePart, w)
                _ -> Nothing
        _ -> Nothing

isHeaderLine :: String -> Bool
isHeaderLine s = "=== " `isPrefixOf` s

isBlankOrComment :: String -> Bool
isBlankOrComment s = all isSpace s || "--" `isPrefixOf` s

trimEnd :: String -> String
trimEnd = reverse . dropWhile isSpace . reverse

-- Join lines without trailing newline (like unlines but no final \n)
unlines' :: [String] -> String
unlines' [] = ""
unlines' xs = init (unlines xs)


-- Test Runner -----------------------------------------------------------------

run :: Test -> (Bool, String)
run (Test name width code) =
    case parseRex code of
        [] -> (False, unlines
            [ "  FAIL " ++ name
            , "    parse returned no trees for: " ++ show code
            ])
        [(slice, tree)] ->
            case rexFromBlockTree slice tree of
                Nothing -> (False, unlines
                    [ "  FAIL " ++ name
                    , "    rexFromBlockTree returned Nothing for: " ++ show code
                    ])
                Just rex ->
                    let actual = printRex width rex
                        ok     = actual == code
                    in if ok
                       then (True, "  OK   " ++ name)
                       else (False, unlines
                               [ "  FAIL " ++ name
                               , "    width:    " ++ show width
                               , "    code:     " ++ show code
                               , "    printed:  " ++ show actual
                               ])
        results -> (False, unlines
            [ "  FAIL " ++ name
            , "    parse returned multiple trees (" ++ show (length results)
              ++ ") for: " ++ show code
            ])


-- | Run tests and print results (for use in rex executable)
printRexTestMain :: IO ()
printRexTestMain = printRexTestMainIO >>= \_ -> pure ()

-- | Run tests, print results, and return success status
printRexTestMainIO :: IO Bool
printRexTestMainIO = do
    let testDir = "src/hs/ex/print-rex"
    files <- listDirectory testDir
    let testFiles = sort [f | f <- files, takeExtension f == ".tests"]
    results <- mapM (runTestFile testDir) testFiles
    let allResults = concat results
        fails      = filter (not . fst) allResults
        total      = length allResults
        passed     = length (filter fst allResults)
    putStrLn ""
    putStrLn $ show passed ++ "/" ++ show total ++ " passed"
    if null fails
        then return True
        else do
            putStrLn $ show (length fails) ++ " FAILED"
            return False

runTestFile :: FilePath -> FilePath -> IO [(Bool, String)]
runTestFile dir file = do
    let path = dir </> file
    content <- readFile path
    putStrLn $ "-- " ++ file ++ " --"
    case parseTestFile content of
        Left err -> do
            hPutStrLn stderr $ "Error parsing " ++ file ++ ": " ++ err
            return [(False, "  FAIL (parse error)")]
        Right tests -> do
            let results = map run tests
            mapM_ (putStrLn . snd) results
            return results
