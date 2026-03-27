{-# LANGUAGE BangPatterns #-}

-- | CLI driver functions for Rex tools.
--
-- This module contains all command-line interface entry points,
-- keeping core modules as pure library code.

module Rex.CLI
    ( lexMain
    , treeMain
    , rexMain
    , checkMain
    , prettyRexMain
    )
where

import System.IO (hIsTerminalDevice, stdout)

import Rex.Lex   (Span(..), lexRex, bsplit, Tok(..), ty, lin, col, off, len, text)
import Rex.Tree2 (parseRex, ppTree)
import Rex.Rex   (rexFromBlockTree, ppRex, collectRexErrors)
import Rex.Error (RexError(..), BadReason(..))
import Rex.PrintRex (printRexWith, PrintConfig(..), ColorScheme(..))


-- Lex -------------------------------------------------------------------------

-- | Tokenize stdin and print token stream
lexMain :: IO ()
lexMain = getContents >>= putStrLn . ppToks . bsplit . lexRex

ppToks :: [Tok] -> String
ppToks ts =
  let wTy  = maximum (3 : map (length . show . ty) ts)
      wLin = maximum (1 : map (length . show . lin) ts)
      wCol = maximum (1 : map (length . show . col) ts)
  in concatMap (ppTok wTy wLin wCol) ts

ppTok :: Int -> Int -> Int -> Tok -> String
ppTok wTy wLin wCol t =
  let hdr = padR wTy (show (ty t))
         ++ "  "
         ++ padL wLin (show (lin t))
         ++ ":"
         ++ padL wCol (show (col t))
         ++ "  "
         ++ padL 4 (show (off t))
         ++ "  "
         ++ padL 3 (show (len t))
         ++ "  "
      shown = show (text t)
      ls    = lines shown
  in case ls of
       []     -> hdr ++ "\"\"" ++ "\n"
       (l:rs) -> hdr ++ l ++ "\n"
              ++ concatMap (\x -> replicate (length hdr) ' ' ++ x ++ "\n") rs

padR :: Int -> String -> String
padR w x = x ++ replicate (max 0 (w - length x)) ' '

padL :: Int -> String -> String
padL w x = replicate (max 0 (w - length x)) ' ' ++ x


-- Tree ------------------------------------------------------------------------

-- | Parse stdin and print structural tree
treeMain :: IO ()
treeMain = do
  src <- getContents
  let results = parseRex src
  mapM_ (\(s, t) -> do
    putStrLn $ "--- input: " ++ show s
    putStrLn $ ppTree t
    ) results


-- Rex -------------------------------------------------------------------------

-- | Parse stdin and print Rex IR
rexMain :: IO ()
rexMain = do
  src <- getContents
  let results = parseRex src
  mapM_ (\(slice, tree) ->
    case rexFromBlockTree slice tree of
      Nothing -> pure ()
      Just r  -> putStrLn (ppRex r)
    ) results


-- Check -----------------------------------------------------------------------

-- | Parse stdin and report any errors (BAD tokens)
checkMain :: IO ()
checkMain = do
    src <- getContents
    let results = parseRex src
        allErrors = concatMap (\(slice, tree) ->
            case rexFromBlockTree slice tree of
                Nothing -> []
                Just r  -> collectRexErrors r
            ) results
    if null allErrors
       then putStrLn "No errors found."
       else mapM_ (putStrLn . formatError (Just src)) allErrors
  where
    formatError mSrc (RexError sp reason txt) =
        let loc = show (spanLin sp) ++ ":" ++ show (spanCol sp)
            msg = reasonMessage reason
            preview = case mSrc of
                Nothing  -> show txt
                Just s -> showContext s sp
        in loc ++ ": error: " ++ msg ++ "\n" ++ preview

    reasonMessage InvalidChar       = "invalid character"
    reasonMessage UnclosedTrad      = "unclosed string literal"
    reasonMessage UnclosedUgly      = "unclosed multi-line string"
    reasonMessage MismatchedBracket = "mismatched bracket"
    reasonMessage InvalidPage       = "invalid page string indentation"
    reasonMessage InvalidSpan       = "invalid span string indentation"

    showContext src sp =
        let srcLines = lines src
            lineNum = spanLin sp
            colNum = spanCol sp
        in if lineNum > 0 && lineNum <= length srcLines
           then let line = srcLines !! (lineNum - 1)
                    pointer = replicate (colNum - 1) ' ' ++ "^"
                in "  " ++ line ++ "\n  " ++ pointer
           else ""


-- Pretty ----------------------------------------------------------------------

-- | Read Rex source from stdin, parse to Rex, and pretty-print using
-- the PDoc layout engine. Each top-level input is separated by a blank line.
-- Uses colors when stdout is a terminal.
prettyRexMain :: Bool -> IO ()
prettyRexMain debug = do
    isTty <- hIsTerminalDevice stdout
    let colors = if isTty then BoldColors else NoColors
    let cfg = PrintConfig colors debug 30 50
    src <- getContents
    -- Force full input before parsing (avoid lazy IO issues with interactive input)
    let !_ = length src
    let results = parseRex src
    mapM_ (\(slice, tree) ->
        case rexFromBlockTree slice tree of
            Nothing  -> pure ()
            Just rex -> do
                putStrLn (printRexWith cfg 80 rex)
                putStrLn ""
        ) results
