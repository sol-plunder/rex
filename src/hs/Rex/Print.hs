{-# LANGUAGE LambdaCase #-}

module Rex.Print (printRex, printMain) where

import qualified Rex.Lex    as Lx
import qualified Rex.Tree2  as Tr

import Rex.Tree2  (Bracket (..), Leaf (..), Node (..), Shape (..), Tree (..))
import Data.List  (intercalate, nubBy, sortBy)
import Data.Maybe (catMaybes)

import Rex.Rex


-- Rex Printer (prints Rex as Rex notation) ------------------------------------
--
-- Column-aware printer. Tracks the current column to produce
-- correct layout for OPEN, HEIR, and BLOC forms.
--
-- go col rex = (output_string, ending_column)

printRex :: Rex -> String
printRex rex = fst (go 0 rex)

go :: Int -> Rex -> (String, Int)
go col = \case
    LEAF WORD s -> (s, col + length s)
    LEAF QUIP s -> (s, col + length s)
    LEAF TRAD s -> endCol col s
    LEAF UGLY s -> endCol col s
    LEAF SLUG s -> endCol col s

    NEST c r kids ->
        let (open, close) = brackets c
            sep = " " ++ r ++ " "
        in case kids of
             -- Empty: shouldn't happen, but handle gracefully
             [] -> (open ++ close, col + length open + length close)
             -- Single element with trailing rune: (f ,)
             [k] -> let col1 = col + length open
                        (s, col2) = go col1 k
                        trail = " " ++ r
                    in (open ++ s ++ trail ++ close, col2 + length trail + length close)
             -- Normal infix: (a , b , c)
             _  -> let col1 = col + length open
                       (strs, colEnd) = goSep sep col1 kids
                   in (open ++ strs ++ close, colEnd + length close)

    EXPR c kids ->
        let (open, close) = brackets c
            col1 = col + length open
            (strs, colEnd) = goSep " " col1 kids
        in (open ++ strs ++ close, colEnd + length close)

    PREF r child ->
        let col1 = col + length r
            (s, col2) = go col1 child
        in (r ++ s, col2)

    TYTE r kids ->
        goTightSep r col kids

    JUXT kids ->
        goJuxtAll col kids

    HEIR kids ->
        -- Each element on its own line at the same column.
        case kids of
          []     -> ("", col)
          [k]    -> go col k
          (k:ks) ->
            let (s0, _) = go col k
                rest = concatMap (\r ->
                    let pad = "\n" ++ replicate col ' '
                        (sr, _) = go col r
                    in pad ++ sr) ks
            in (s0 ++ rest, col)

    BLOC c r hd items ->
        -- Print as: head rune\n  item1\n  item2
        -- The head and rune are on the current line.
        -- Items are indented from the start of head.
        let (open, close) = brackets c
            col1 = col + length open
            (sHd, colHd) = go col1 hd
            sRune = " " ++ r
            colAfterRune = colHd + length sRune
            itemIndent = col1 + 4
            sItems = concatMap (\item ->
                let pad = "\n" ++ replicate itemIndent ' '
                    (si, _) = go itemIndent item
                in pad ++ si) items
            body = sHd ++ sRune ++ sItems
        in case c of
             CLEAR -> (body, itemIndent)
             _     -> (open ++ body ++ "\n" ++ replicate col ' ' ++ close,
                       col + length close)

    OPEN r kids ->
        -- Rune at current column, first child after space,
        -- remaining children each on own line indented past rune.
        let rlen = length r
            childIndent = col + rlen + 2
        in case kids of
             [] -> (r, col + rlen)
             [k] ->
               let (s, col2) = go (col + rlen + 1) k
               in (r ++ " " ++ s, col2)
             (k:ks) ->
               let (s0, _) = go (col + rlen + 1) k
                   rest = concatMap (\c ->
                       let pad = "\n" ++ replicate childIndent ' '
                           (sc, _) = go childIndent c
                       in pad ++ sc) ks
               in (r ++ " " ++ s0 ++ rest, childIndent)

-- Compute ending column for multiline strings
endCol :: Int -> String -> (String, Int)
endCol col s =
    let ls = lines s
    in (s, if length ls > 1 then length (last ls) else col + length s)

-- Print kids separated by a string (for NEST and EXPR)
goSep :: String -> Int -> [Rex] -> (String, Int)
goSep _   col []     = ("", col)
goSep _   col [k]    = go col k
goSep sep col (k:ks) =
    let (s, col1) = go col k
        (rest, colEnd) = goSep sep (col1 + length sep) ks
    in (s ++ sep ++ rest, colEnd)

-- Print kids with tight separator
goTightSep :: String -> Int -> [Rex] -> (String, Int)
goTightSep _   col []     = ("", col)
goTightSep _   col [k]    = goTight col k
goTightSep sep col (k:ks) =
    let (s, col1) = goTight col k
        (rest, colEnd) = goTightSep sep (col1 + length sep) ks
    in (s ++ sep ++ rest, colEnd)

goTight :: Int -> Rex -> (String, Int)
goTight col rex = case rex of
    LEAF _ _ -> go col rex
    JUXT _   -> go col rex
    _        -> let (s, col2) = go (col+1) rex
                in ("(" ++ s ++ ")", col2 + 1)

goJuxtAll :: Int -> [Rex] -> (String, Int)
goJuxtAll col []     = ("", col)
goJuxtAll col [k]    = goJuxt col k
goJuxtAll col (k:ks) =
    let (s, col1) = goJuxt col k
        (rest, colEnd) = goJuxtAll col1 ks
    in (s ++ rest, colEnd)

goJuxt :: Int -> Rex -> (String, Int)
goJuxt col rex = case rex of
    LEAF _ _      -> go col rex
    NEST _ _ _    -> go col rex
    EXPR _ _      -> go col rex
    TYTE _ _      -> go col rex
    PREF _ _      -> go col rex
    _             -> let (s, col2) = go (col+1) rex
                     in ("(" ++ s ++ ")", col2 + 1)

brackets :: Color -> (String, String)
brackets PAREN = ("(", ")")
brackets BRACK = ("[", "]")
brackets CURLY = ("{", "}")
-- ckets CLEAR = ("", "")
brackets CLEAR = ("❰", "❱") -- for debugging only


--- Main ------------------------------------------------------------------------

printMain :: IO ()
printMain = do
    src <- getContents
    let results = Tr.parseRex src
    mapM_ (\(slice, tree) ->
        case rexFromBlockTree slice tree of
            Nothing -> pure ()
            Just r  -> putStrLn (printRex r)
        ) results
