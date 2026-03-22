{-# LANGUAGE LambdaCase #-}
{-# OPTIONS_GHC -Wno-x-partial #-}

module Rex.Lex where

import Data.Char (isAlphaNum)
import Data.List (intercalate)
import Data.List (sortBy, nubBy)

-- Token Types -----------------------------------------------------------------

data TokTy = BAD | EOL | EOF | WYTE | BEGIN | END | CLMP | FREE | WORD | TRAD
           | QUIP | UGLY | SLUG | EOB
  deriving (Eq, Show)

data Tok = Tok
  { ty   :: !TokTy
  , col  :: !Int
  , off  :: !Int      -- character offset into source
  , len  :: !Int      -- length in characters
  , text :: !String
  } deriving (Eq, Show)


-- Lexer -----------------------------------------------------------------------

lexRex :: String -> [Tok]
lexRex = go 0 0
 where
  go _ o [] = [Tok EOF 0 o 0 ""]
  go c o s@(x:xs)
    | x=='\n'          = Tok EOL 0 o 1 "\n" : go 0 (o+1) xs
    | x==' '||x=='\t'  = let (w,r)=span (`elem`" \t") s; n=length w
                         in Tok WYTE (c+1) o n w : go (c+n) (o+n) r
    | x `elem` "([{"   = Tok BEGIN (c+1) o 1 [x] : go (c+1) (o+1) xs
    | x `elem` ")]}"   = Tok END   (c+1) o 1 [x] : go (c+1) (o+1) xs
    | x=='"'           = let (t,r,c',o')=trad (c+1) (o+1) xs in t : go c' o' r
    | x=='\''          = let (ts,r,c',o')=tick (c+1) (o+1) xs in ts ++ go c' o' r
    | rune x           = let (r,rst)=span rune s; n=length r
                             k = if isFree rst then FREE else CLMP
                         in Tok k (c+1) o n r : go (c+n) (o+n) rst
    | word x           = let (w,rst)=span word s; n=length w
                         in Tok WORD (c+1) o n w : go (c+n) (o+n) rst
    | otherwise        = Tok BAD  (c+1) o 1 [x] : go (c+1) (o+1) xs

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
-- sc = start column of opening ", so = offset of first body char (after ")
trad :: Int -> Int -> String -> (Tok, String, Int, Int)
trad sc so = go "\"" sc so
 where
  tokOff = so - 1  -- offset of the opening "
  go acc c o = \case
    []            -> (Tok BAD sc tokOff (o - tokOff) acc, [], c, o)
    '"':'"':rest  -> go (acc++"\"\"") (c+2) (o+2) rest
    '"':rest      -> let raw = acc ++ "\""
                     in (Tok TRAD sc tokOff (o + 1 - tokOff) raw, rest, c+1, o+1)
    ch:rest       -> go (acc++[ch]) (c+1) (o+1) rest

-- Tick dispatch: QUIP / SLUG / UGLY / NOTE
tick :: Int -> Int -> String -> ([Tok], String, Int, Int)
tick tcol to rest =
  let tickOff = to - 1   -- the tick itself
  in case rest of
    [] -> ([Tok QUIP tcol tickOff 1 "'"], [], tcol, to)

    c:_ | c == ' ' || c == '\n' ->
            let (tok, rest') = lexSlug tcol tickOff rest
            in ([tok], rest', tcol + len tok, tickOff + len tok)
        | c == '\'' ->
            let (qs, body0) = span (=='\'') rest
                n           = 1 + length qs
                col0        = tcol + n
                off0        = to + length qs
                (tok, r, c', o')= lexUgly tcol tickOff n col0 off0 body0
            in ([tok], r, c', o')
        | c `elem` ")]}" ->
            let (tok, r, c', o') = lexNote tcol tickOff rest to
            in ([tok], r, c', o')
        | otherwise ->
            ([Tok QUIP tcol tickOff 1 "'"], rest, tcol, to)

isQuipChar :: Char -> Bool
isQuipChar = (`notElem` "()[]{}\n\t ")

lexNote :: Int -> Int -> String -> Int -> (Tok, String, Int, Int)
lexNote sc so xs xo =
    let (ln,r) = break (=='\n') xs
        raw    = '\'':ln
        n      = length raw
    in ( Tok WYTE sc so n raw
       , r
       , if null r then sc+length ln else 0
       , xo + length ln
       )

-- UGLY strings
lexUgly :: Int -> Int -> Int -> Int -> Int -> String -> (Tok, String, Int, Int)
lexUgly tcol tokOff n col0 off0 xs =
  let (lit, rest, poison, colEnd, offEnd) = scan False ud 0 (col0-1) (off0-1) xs
      ty' = if poison then BAD else UGLY
      raw = replicate n '\'' ++ lit
  in (Tok ty' tcol tokOff (offEnd - tokOff) raw, rest, colEnd, offEnd)
 where
  ud = case xs of
         ('\n':_) -> tcol
         _        -> col0

  scan :: Bool -> Int -> Int -> Int -> Int -> String -> (String, String, Bool, Int, Int)
  scan poison' ud' run col' off' = \case
    [] -> ([], [], True, col', off')
    ch:cs ->
      let col'' = if ch=='\n' then 0 else col'+1
          off'' = off' + 1
          poison'' = poison' || (col' < ud' && ch/=' ' && ch/='\n')
      in if ch=='\''
           then let run' = run+1
                in if run' == n
                     then let startCol  = col' - n + 1
                              poisonEnd = poison'' || (ud'==tcol && startCol /= tcol)
                          in (replicate n '\'', cs, poisonEnd, col'', off'')
                     else let (a,b,p,k,o) = scan poison'' ud' run' col'' off'' cs
                          in (ch:a, b, p, k, o)
           else let (a,b,p,k,o) = scan poison'' ud' 0 col'' off'' cs
                in (ch:a, b, p, k, o)

-- SLUG strings
lexSlug :: Int -> Int -> String -> (Tok, String)
lexSlug tcol tokOff rest =
  let (raw, rest') = go "'" rest
  in (Tok SLUG tcol tokOff (length raw) raw, rest')
 where
  go acc xs =
    let (line, rest1) = break (== '\n') xs
        acc'          = acc ++ line
    in case rest1 of
         []        -> (acc', [])
         ('\n':rs) ->
           case shouldContinue tcol rs of
             Just rs' -> go (acc' ++ "\n" ++ "'") rs'
             Nothing  -> (acc', '\n':rs)

  shouldContinue t s =
    let (sp, rest2) = span (== ' ') s
        col'        = 1 + length sp
    in case rest2 of
         ('\'':xs) | col' == t -> Just xs
         _                     -> Nothing


-- Block Splitting -------------------------------------------------------------

data BMode = OUTSIDE | SINGLE_LN | BLK
  deriving (Eq, Show)

bsplit :: [Tok] -> [Tok]
bsplit = go OUTSIDE [] 0 False
  where
    go :: BMode -> [Char] -> Int -> Bool -> [Tok] -> [Tok]
    go _ _ _ _ [] = []
    go mode stk eol wasRune (t:ts) =
      let (t1, stk1) = stepNest stk t
          eol1       = if ty t1 == EOL then eol + 1 else 0
          (out, mode1) = stepMode mode stk1 eol1 wasRune t1
          wasRune'   = ty t1 == CLMP || ty t1 == FREE
      in out ++ go mode1 stk1 eol1 wasRune' ts

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

    stepMode :: BMode -> [Char] -> Int -> Bool -> Tok -> ([Tok], BMode)
    stepMode mode stk eol wasRune t =
      case mode of
        OUTSIDE ->
          let mode' | ty t == FREE     = BLK
                    | isContent (ty t) = SINGLE_LN
                    | otherwise        = OUTSIDE
          in ([t], mode')

        SINGLE_LN
          | null stk && ty t == EOL && eol == 1 ->
              if wasRune then ([t], BLK)
              else ([Tok EOB 0 (off t) 0 ""], OUTSIDE)
          | otherwise -> ([t], SINGLE_LN)

        BLK
          | null stk && ty t == EOL && eol == 2 ->
              ([Tok EOB 0 (off t) 0 ""], OUTSIDE)
          | otherwise -> ([t], BLK)

isContent :: TokTy -> Bool
isContent = \case EOL -> False; WYTE -> False; EOF -> False; EOB -> False; _ -> True


-- Main ------------------------------------------------------------------------

ppToks :: [Tok] -> String
ppToks ts =
  let wTy  = maximum (3 : map (length . show . ty) ts)
      wCol = maximum (1 : map (length . show . col) ts)
  in concatMap (ppTok wTy wCol) ts

ppTok :: Int -> Int -> Tok -> String
ppTok wTy wCol t =
  let hdr = padR wTy (show (ty t))
         ++ "  "
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

padR, padL :: Int -> String -> String
padR w x = x ++ replicate (max 0 (w - length x)) ' '
padL w x = replicate (max 0 (w - length x)) ' ' ++ x

lexMain :: IO ()
lexMain = getContents >>= putStrLn . ppToks . bsplit . lexRex