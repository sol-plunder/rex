{-# LANGUAGE LambdaCase #-}
{-# OPTIONS_GHC -Wno-x-partial #-}

module Rex.Lex
    ( TokTy(..), Tok(..), Span(..)
    , lexRex, bsplit, tokSpan
    )
where

import Data.Char (isAlphaNum)
import Data.List (intercalate)
import Data.List (sortBy, nubBy)

-- Token Types -----------------------------------------------------------------

data TokTy = BAD | EOL | EOF | WYTE | BEGIN | END | CLMP | FREE | WORD | TRAD
           | QUIP | UGLY | SLUG | EOB
  deriving (Eq, Show)

-- | Source span: line, column, byte offset, byte length
data Span = Span
  { spanLin :: !Int   -- 1-indexed line number
  , spanCol :: !Int   -- 1-indexed column
  , spanOff :: !Int   -- byte offset into source
  , spanLen :: !Int   -- length in bytes
  } deriving (Eq, Show)

data Tok = Tok
  { ty   :: !TokTy
  , lin  :: !Int      -- 1-indexed line number
  , col  :: !Int      -- 1-indexed column
  , off  :: !Int      -- character offset into source
  , len  :: !Int      -- length in characters
  , text :: !String
  } deriving (Eq, Show)

tokSpan :: Tok -> Span
tokSpan t = Span (lin t) (col t) (off t) (len t)


-- Lexer -----------------------------------------------------------------------

lexRex :: String -> [Tok]
lexRex = go 1 0 0   -- line=1, col=0, offset=0
 where
  go _ _ o [] = [Tok EOF 1 0 o 0 ""]
  go l c o s@(x:xs)
    | x=='\n'          = Tok EOL l 0 o 1 "\n" : go (l+1) 0 (o+1) xs
    | x==' '||x=='\t'  = let (w,r)=span (`elem`" \t") s; n=length w
                         in Tok WYTE l (c+1) o n w : go l (c+n) (o+n) r
    | x `elem` "([{"   = Tok BEGIN l (c+1) o 1 [x] : go l (c+1) (o+1) xs
    | x `elem` ")]}"   = Tok END   l (c+1) o 1 [x] : go l (c+1) (o+1) xs
    | x=='"'           = let (t,r,c',o',l')=trad l (c+1) (o+1) xs in t : go l' c' o' r
    | x=='\''          = let (ts,r,c',o',l')=tick l (c+1) (o+1) xs in ts ++ go l' c' o' r
    | rune x           = let (r,rst)=span rune s; n=length r
                             k = if isFree rst then FREE else CLMP
                         in Tok k l (c+1) o n r : go l (c+n) (o+n) rst
    | word x           = let (w,rst)=span word s; n=length w
                         in Tok WORD l (c+1) o n w : go l (c+n) (o+n) rst
    | otherwise        = Tok BAD  l (c+1) o 1 [x] : go l (c+1) (o+1) xs

-- | A rune is FREE when followed by space, newline, close bracket, or EOF.
isFree :: String -> Bool
isFree []    = True
isFree (c:_) = c == ' ' || c == '\n' || c == ')' || c == ']' || c == '}'

listToMaybe :: [a] -> Maybe a
listToMaybe []    = Nothing
listToMaybe (a:_) = Just a

word :: Char -> Bool
word ch = isAlphaNum ch || ch=='_'

rune :: Char -> Bool
rune ch = ch `elem` (";,:#$`~@?\\|^&=!<>+-*/%!." :: String)

-- TRAD strings
-- sl = start line, sc = start column of opening ", so = offset of first body char (after ")
trad :: Int -> Int -> Int -> String -> (Tok, String, Int, Int, Int)
trad sl sc so = go "\"" sl sc so
 where
  tokOff = so - 1  -- offset of the opening "
  go acc l c o = \case
    []            -> (Tok BAD sl sc tokOff (o - tokOff) acc, [], c, o, l)
    '"':'"':rest  -> go (acc++"\"\"") l (c+2) (o+2) rest
    '"':rest      -> let raw = acc ++ "\""
                     in (Tok TRAD sl sc tokOff (o + 1 - tokOff) raw, rest, c+1, o+1, l)
    '\n':rest     -> go (acc++"\n") (l+1) 0 (o+1) rest
    ch:rest       -> go (acc++[ch]) l (c+1) (o+1) rest

-- Tick dispatch: QUIP / SLUG / UGLY / NOTE
tick :: Int -> Int -> Int -> String -> ([Tok], String, Int, Int, Int)
tick tlin tcol to rest =
  let tickOff = to - 1   -- the tick itself
  in case rest of
    [] -> ([Tok QUIP tlin tcol tickOff 1 "'"], [], tcol, to, tlin)

    c:_ | c == ' ' || c == '\n' ->
            let (tok, rest', consumed, lin') = lexSlug tlin tcol tickOff rest
            in ([tok], rest', tcol + len tok, tickOff + consumed, lin')
        | c == '\'' ->
            let (qs, body0) = span (=='\'') rest
                n           = 1 + length qs
                col0        = tcol + n
                off0        = to + length qs
                (tok, r, c', o', l') = lexUgly tlin tcol tickOff n col0 off0 body0
            in ([tok], r, c', o', l')
        | c `elem` ")]}" ->
            let (tok, r, c', o', l') = lexNote tlin tcol tickOff rest to
            in ([tok], r, c', o', l')
        | otherwise ->
            ([Tok QUIP tlin tcol tickOff 1 "'"], rest, tcol, to, tlin)

isQuipChar :: Char -> Bool
isQuipChar = (`notElem` "()[]{}\n\t ")

lexNote :: Int -> Int -> Int -> String -> Int -> (Tok, String, Int, Int, Int)
lexNote sl sc so xs xo =
    let (ln,r) = break (=='\n') xs
        raw    = '\'':ln
        n      = length raw
    in ( Tok WYTE sl sc so n raw
       , r
       , if null r then sc+length ln else 0
       , xo + length ln
       , sl  -- line doesn't change, note stays on one line
       )

-- UGLY strings ('''-delimited, either block or inline form)
-- The lexer just matches tick sequences; validation happens in Rex loading.
lexUgly :: Int -> Int -> Int -> Int -> Int -> Int -> String -> (Tok, String, Int, Int, Int)
lexUgly tlin tcol tokOff n col0 off0 xs =
  let (lit, rest, closed, colEnd, offEnd, linEnd) = scanUgly 0 tlin (col0-1) (off0-1) xs
      ty' = if closed then UGLY else BAD
      raw = replicate n '\'' ++ lit
  in (Tok ty' tlin tcol tokOff (offEnd - tokOff) raw, rest, colEnd, offEnd, linEnd)
 where
  scanUgly :: Int -> Int -> Int -> Int -> String -> (String, String, Bool, Int, Int, Int)
  scanUgly run lin' col' off' = \case
    [] -> ([], [], False, col', off', lin')  -- unclosed = BAD
    ch:cs ->
      let (col'', lin'') = if ch=='\n' then (0, lin'+1) else (col'+1, lin')
          off'' = off' + 1
      in if ch=='\''
           then let run' = run+1
                in if run' == n
                     then (replicate n '\'', cs, True, col'', off'', lin'')
                     else let (a,b,closed,k,o,l) = scanUgly run' lin'' col'' off'' cs
                          in (a, b, closed, k, o, l)
           else let pending = replicate run '\''
                    (a,b,closed,k,o,l) = scanUgly 0 lin'' col'' off'' cs
                in (pending ++ ch:a, b, closed, k, o, l)

-- SLUG strings
-- Returns (token, remaining_string, bytes_consumed, end_line)
lexSlug :: Int -> Int -> Int -> String -> (Tok, String, Int, Int)
lexSlug tlin tcol tokOff rest =
  let (raw, rest', consumed, linEnd) = go "'" 1 tlin rest  -- 1 for the initial tick
  in (Tok SLUG tlin tcol tokOff (length raw) raw, rest', consumed, linEnd)
 where
  -- acc = accumulated content, consumed = bytes consumed from input, lin' = current line
  go acc consumed lin' xs =
    let (line, rest1) = break (== '\n') xs
        acc'          = acc ++ line
        consumed'     = consumed + length line
    in case rest1 of
         []        -> (acc', [], consumed', lin')
         ('\n':rs) ->
           case shouldContinue tcol rs of
             Just (skip, rs') -> go (acc' ++ "\n" ++ "'") (consumed' + 1 + skip + 1) (lin'+1) rs'
                                 -- +1 for newline, +skip for spaces, +1 for tick
             Nothing  -> (acc', '\n':rs, consumed', lin')

  -- Returns Just (spaces_skipped, rest_after_tick) or Nothing
  shouldContinue t s =
    let (sp, rest2) = span (== ' ') s
        col'        = 1 + length sp
    in case rest2 of
         -- Only continue if ' is followed by space or newline (slug), not other chars (quip)
         ('\'':' ':xs) | col' == t -> Just (length sp, ' ':xs)
         ('\'':'\n':xs) | col' == t -> Just (length sp, '\n':xs)
         ('\'':xs) | col' == t, null xs -> Just (length sp, xs)
         _                     -> Nothing


-- Block Splitting -------------------------------------------------------------

data BMode = OUTSIDE | SINGLE_LN | BLK
  deriving (Eq, Show)

bsplit :: [Tok] -> [Tok]
bsplit = go OUTSIDE [] 0 False False
  where
    go :: BMode -> [Char] -> Int -> Bool -> Bool -> [Tok] -> [Tok]
    go _ _ _ _ _ [] = []
    go mode stk eol wasRune wasSlug (t:ts) =
      let (t1, stk1) = stepNest stk t
          eol1       = if ty t1 == EOL then eol + 1 else 0
          (out, mode1) = stepMode mode stk1 eol1 wasRune wasSlug t1
          wasRune'   = ty t1 == CLMP || ty t1 == FREE
          wasSlug'   = ty t1 == SLUG
      in out ++ go mode1 stk1 eol1 wasRune' wasSlug' ts

    stepNest :: [Char] -> Tok -> (Tok, [Char])
    stepNest stk t
      | ty t == BEGIN =
          let close = case text t of { "("->')'; "["->']'; "{"->'}'; _->')' }
          in (t, close : stk)
      | ty t == END =
          case (stk, text t) of
            (c:cs, [x]) | x == c -> (t, cs)
            _                    -> (t { ty = BAD }, stk)
      | otherwise = (t, stk)

    stepMode :: BMode -> [Char] -> Int -> Bool -> Bool -> Tok -> ([Tok], BMode)
    stepMode mode stk eol wasRune wasSlug t =
      case mode of
        OUTSIDE ->
          let mode' | ty t == FREE     = BLK
                    | isContent (ty t) = SINGLE_LN
                    | otherwise        = OUTSIDE
          in ([t], mode')

        SINGLE_LN
          | null stk && ty t == EOL && eol == 1 ->
              -- Treat SLUG like trailing rune: continue into BLK mode
              if wasRune || wasSlug then ([t], BLK)
              else ([Tok EOB (lin t) 0 (off t) 0 ""], OUTSIDE)
          | otherwise -> ([t], SINGLE_LN)

        BLK
          | null stk && ty t == EOL && eol == 2 ->
              ([Tok EOB (lin t) 0 (off t) 0 ""], OUTSIDE)
          | otherwise -> ([t], BLK)

isContent :: TokTy -> Bool
isContent = \case EOL -> False; WYTE -> False; EOF -> False; EOB -> False; _ -> True
