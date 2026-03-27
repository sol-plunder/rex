{-# LANGUAGE LambdaCase #-}

-- Copyright (c) 2026 Benjamin Summers
-- SPDX-License-Identifier: MIT
-- See LICENSE for full terms.
--
-- Round-trip test cases for Rex.PrintRex.
--
-- Tests are loaded from ex/*.tests in the format:
--   === test name | width
--   code that should round-trip exactly...
--
-- Or with explicit expected output:
--   === test name | width
--   input code
--   ---
--   expected output

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
    { testName     :: String
    , testWidth    :: Int
    , testDebug    :: Bool     -- whether to use debug mode
    , testInput    :: String
    , testExpected :: String  -- same as input for round-trip tests
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
                               ++ ": expected '=== name | width' or '=== name | width | debug', got: "
                               ++ headerLine
                Just (name, width, debug) ->
                    let (codeLines, remaining) = break isHeaderLine rest
                        -- Strip trailing blank/comment lines from code
                        codeLines' = dropWhileEnd isBlankOrComment codeLines
                        (input, expected) = splitInputExpected codeLines'
                        test = Test name width debug input expected
                        nextLine = newLineNum + 1 + length codeLines
                    in case parseTests remaining nextLine of
                        Left err -> Left err
                        Right ts -> Right (test : ts)

-- | Split code lines into input and expected output.
-- If "---" separator is present, splits there; otherwise both are the same.
splitInputExpected :: [String] -> (String, String)
splitInputExpected ls =
    case break (== "---") ls of
        (inputLines, []) ->
            let code = unlines' inputLines
            in (code, code)  -- round-trip test
        (inputLines, _:expectedLines) ->
            let expectedLines' = dropWhileEnd isBlankOrComment expectedLines
            in (unlines' inputLines, unlines' expectedLines')

-- | Parse header: "=== name | width" or "=== name | width | debug"
parseHeader :: String -> Maybe (String, Int, Bool)
parseHeader s = case stripPrefix "=== " s of
    Nothing -> Nothing
    Just rest -> case break (== '|') rest of
        (_, []) -> Nothing
        (namePart, '|':afterName) ->
            -- Split on '|' to get width and optional "debug"
            let parts = splitOn '|' afterName
            in case parts of
                [widthStr] ->
                    case reads (trim widthStr) of
                        [(w, "")] -> Just (trimEnd namePart, w, False)
                        _         -> Nothing
                [widthStr, flagStr] ->
                    case reads (trim widthStr) of
                        [(w, "")] | trim flagStr == "debug" ->
                            Just (trimEnd namePart, w, True)
                        _         -> Nothing
                _ -> Nothing
        _ -> Nothing

-- | Split a string on a delimiter
splitOn :: Char -> String -> [String]
splitOn _   "" = [""]
splitOn del s  = case break (== del) s of
    (part, [])    -> [part]
    (part, _:rst) -> part : splitOn del rst

-- | Trim leading and trailing whitespace
trim :: String -> String
trim = reverse . dropWhile isSpace . reverse . dropWhile isSpace

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
run (Test name width debug input expected) =
    case parseRex input of
        [] -> (False, unlines
            [ "  FAIL " ++ name
            , "    parse returned no trees for: " ++ show input
            ])
        results ->
            let rexResults = [ rexFromBlockTree slice tree
                             | (slice, tree) <- results ]
            in case sequence rexResults of
                Nothing -> (False, unlines
                    [ "  FAIL " ++ name
                    , "    rexFromBlockTree returned Nothing"
                    ])
                Just rexes ->
                    let cfg     = if debug then debugConfig else defaultConfig
                        actuals = map (printRexWith cfg width) rexes
                        actual  = joinBlankLines actuals
                        ok      = actual == expected
                    in if ok
                       then (True, "  OK   " ++ name)
                       else (False, unlines
                               [ "  FAIL " ++ name
                               , "    width:    " ++ show width
                               , "    debug:    " ++ show debug
                               , "    input:    " ++ show input
                               , "    expected: " ++ show expected
                               , "    actual:   " ++ show actual
                               ])

-- | Join multiple outputs with blank lines (for multi-input tests)
joinBlankLines :: [String] -> String
joinBlankLines []  = ""
joinBlankLines [x] = x
joinBlankLines xs  = foldr1 (\a b -> a ++ "\n\n" ++ b) xs


-- | Run tests and print results (for use in rex executable)
printRexTestMain :: IO ()
printRexTestMain = printRexTestMainIO >>= \_ -> pure ()

-- | Run tests, print results, and return success status
printRexTestMainIO :: IO Bool
printRexTestMainIO = do
    let testDir = "ex"
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
