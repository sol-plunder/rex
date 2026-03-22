{-# LANGUAGE LambdaCase #-}
{-# OPTIONS_GHC -Wno-x-partial #-}

module Rex.Rex
    ( Rex(..), LeafShape(..), Color(..), ppRex
    , rexFromTree, rexFromBlockTree
    , rexMain
    )
where

import qualified Rex.Tree2 as Tr
import qualified Rex.Lex  as Lx

import Rex.Tree2  (Bracket (..), Leaf (..), Node (..), Shape (..), Tree (..))
import Data.List  (nubBy, sortBy)
import Data.Maybe (catMaybes)


-- Rex Data Model --------------------------------------------------------------

data LeafShape = WORD | QUIP | TRAD | UGLY | SLUG
  deriving (Eq, Show)

data Color = PAREN | BRACK | CURLY | CLEAR
  deriving (Eq, Show)

data Rex
    = LEAF LeafShape String
    | NEST Color String [Rex]           -- (x + y), {a | b}
    | EXPR Color [Rex]                  -- [f x], (x), ()
    | PREF String Rex                   -- :x, -y
    | TYTE String [Rex]                 -- x.y, a:b
    | BLOC Color String Rex [Rex]       -- head rune:\n  a\n  b
    | OPEN String [Rex]                 -- + x y (layout prefix)
    | JUXT [Rex]                        -- f(x), f(x)[1]
    | HEIR [Rex]                        -- + x\n+ y\nz
  deriving (Eq, Show)


-- Rune Precedence -------------------------------------------------------------

runeSeq :: String
runeSeq = ";,:#$`~@?\\|^&=!<>+-*/%!."

runePrec :: Char -> Int
runePrec c = go 0 runeSeq
  where
    go n []     = n
    go n (x:xs) = if c == x then n else go (n+1) xs

packRune :: String -> Integer
packRune s =
    let codes = take 13 (map runePrec s ++ repeat 23)
    in foldr (\code acc -> acc * 25 + fromIntegral code) 0 codes

runeCmp :: String -> String -> Ordering
runeCmp a b = compare (packRune a) (packRune b)


-- Leaf Conversion -------------------------------------------------------------

leafToRex :: Leaf -> Rex
leafToRex = \case
    L_WORD s -> LEAF WORD s
    L_TRAD s -> LEAF TRAD s
    L_UGLY s -> LEAF UGLY s
    L_SLUG s -> LEAF SLUG s
    L_BAD  s -> LEAF WORD s


-- Quip Conversion -------------------------------------------------------------
--
-- A quip (S_QUIP) is converted by extracting its underlying source
-- text (using treeOff/treeLen relative to the block's source slice)
-- and producing a LEAF QUIP.

quipToRex :: String -> Int -> Tree -> Rex
quipToRex src blockOff (Tree S_QUIP _ qoff qlen _) =
    let s = take qlen (drop (qoff - blockOff) src)
    in LEAF QUIP s
quipToRex _ _ t = error $ "quipToRex: not a quip: " ++ show (treeShape t)


-- Top-Level Conversion --------------------------------------------------------
--
-- All conversion functions thread (src, blockOff) for quip extraction.
-- src is the source slice for this block; blockOff is the absolute
-- offset where it starts in the original source.

convertWith :: String -> Int -> Tree -> Rex
convertWith src blockOff tree@(Tree shape _pos _off _len nodes) = case shape of
    S_NEST bk -> convertNest src blockOff bk nodes
    S_CLUMP   -> convertClump src blockOff nodes
    S_POEM    -> convertPoem src blockOff (treePos tree) nodes
    S_ITEM    -> convertSpaced src blockOff CLEAR nodes
    S_QUIP    -> quipToRex src blockOff tree
    S_BLOCK   -> error "S_BLOCK: should be consumed by enclosing context"


-- Spaced Node Lists -----------------------------------------------------------

convertSpaced :: String -> Int -> Color -> [Node] -> Rex
convertSpaced src blockOff color nodes = case extractBlock nodes of
    Just (headNodes, rune, blockChildren) ->
        let hd    = spacedHead src blockOff headNodes
            items = map (convertWith src blockOff) blockChildren
        in BLOC color rune hd items
    Nothing ->
        spacedGroup src blockOff color nodes

spacedHead :: String -> Int -> [Node] -> Rex
spacedHead _   _        []  = EXPR CLEAR []
spacedHead src blockOff [n] = convertNode src blockOff n
spacedHead src blockOff ns  = spacedGroup src blockOff CLEAR ns

spacedGroup :: String -> Int -> Color -> [Node] -> Rex
spacedGroup src blockOff color nodes =
    let elems = map (nodeToElem src blockOff) nodes
        runes = nubBy (==) $ sortBy runeCmp [r | E_RUNE r <- elems]
    in case runes of
         [] -> case [r | E_REX r <- elems] of
                 []  -> EXPR color []
                 [r] -> applyColor color r
                 rs  -> EXPR color rs
         _  -> let rex = infixRecur runes elems
               in applyColor color rex

applyColor :: Color -> Rex -> Rex
applyColor CLEAR rex = rex
applyColor color rex = case rex of
    NEST CLEAR r kids     -> NEST color r kids
    EXPR CLEAR kids       -> EXPR color kids
    BLOC CLEAR r hd items -> BLOC color r hd items
    _                     -> EXPR color [rex]


-- Block Extraction ------------------------------------------------------------

extractBlock :: [Node] -> Maybe ([Node], String, [Tree])
extractBlock nodes =
    case reverse nodes of
      (N_CHILD (Tree S_BLOCK _ _ _ blockNodes) : N_RUNE _ rune : revHead) ->
          let items = [t | N_CHILD t <- blockNodes]
          in Just (reverse revHead, rune, items)
      _ -> Nothing


-- Nest Conversion -------------------------------------------------------------

convertNest :: String -> Int -> Bracket -> [Node] -> Rex
convertNest src blockOff bk nodes =
    let color = toColor bk
    in case nodes of
         []  -> EXPR color []
         [n] -> applyColor color (convertNode src blockOff n)
         _   -> convertSpaced src blockOff color nodes

toColor :: Bracket -> Color
toColor Paren = PAREN
toColor Brack = BRACK
toColor Curly = CURLY
toColor Clear = CLEAR


-- Clump Conversion ------------------------------------------------------------

convertClump :: String -> Int -> [Node] -> Rex
convertClump _   _        []    = error "empty clump"
convertClump src blockOff nodes = top (nodeToElem src blockOff <$> nodes)
  where
    top :: [Elem] -> Rex
    top [E_REX r] = r
    top (E_RUNE r : rest) = PREF r (top rest)
    top es = case juxt [] es of [E_REX r] -> r
                                collapsed -> tight collapsed

    tight :: [Elem] -> Rex
    tight elems =
        case nubBy (==) $ sortBy runeCmp [r | E_RUNE r <- elems] of
             [] -> case [r | E_REX r <- elems] of
                     [r] -> r
                     rs  -> EXPR CLEAR rs
             rs -> go rs elems

    go :: [String] -> [Elem] -> Rex
    go _      [E_REX r] = r
    go []     elems     = case [r | E_REX r <- elems] of
                              [r] -> r
                              rs  -> EXPR CLEAR rs
    go (r:rs) elems     = case go rs <$> splitOnRune r elems of
                              [k]  -> k
                              kids -> TYTE r kids

    juxt :: [Rex] -> [Elem] -> [Elem]
    juxt acc []                    = flush acc []
    juxt acc (e@(E_RUNE _) : rest) = flush acc (e : juxt [] rest)
    juxt acc (E_REX r : rest)      = juxt (acc ++ [r]) rest

    flush :: [Rex] -> [Elem] -> [Elem]
    flush []  rest = rest
    flush [r] rest = E_REX r : rest
    flush rs  rest = E_REX (JUXT rs) : rest


-- Poem Conversion -------------------------------------------------------------

convertPoem :: String -> Int -> Int -> [Node] -> Rex
convertPoem _   _        _   [] = error "empty poem"
convertPoem src blockOff pos (N_RUNE _ r : rest) =
    let (children, heirNodes) = splitHeir pos rest
        open = OPEN r (map (convertNode src blockOff) children)
    in case heirNodes of
         [] -> open
         _  -> mkHeir (open : concatMap (flattenHeir . convertNode src blockOff) heirNodes)
convertPoem _ _ _ _ = error "poem must start with a rune"

splitHeir :: Int -> [Node] -> ([Node], [Node])
splitHeir pos = go []
  where
    go acc [] = (reverse acc, [])
    go acc rest@(n:_)
      | Tr.nodeCol n <= pos = (reverse acc, rest)
      | otherwise           = go (n : acc) (tail rest)

mkHeir :: [Rex] -> Rex
mkHeir [r] = r
mkHeir rs  = HEIR rs

flattenHeir :: Rex -> [Rex]
flattenHeir (HEIR rs) = rs
flattenHeir r         = [r]


-- Node Conversion -------------------------------------------------------------

convertNode :: String -> Int -> Node -> Rex
convertNode _   _        (N_LEAF _ lf)  = leafToRex lf
convertNode src blockOff (N_CHILD tree) = convertWith src blockOff tree
convertNode _   _        (N_RUNE _ r)   = error $ "convertNode: bare rune: " ++ r


-- Intermediate Elements -------------------------------------------------------

data Elem = E_RUNE String | E_REX Rex

nodeToElem :: String -> Int -> Node -> Elem
nodeToElem _   _        (N_RUNE _ r)   = E_RUNE r
nodeToElem _   _        (N_LEAF _ lf)  = E_REX (leafToRex lf)
nodeToElem src blockOff (N_CHILD tree) = E_REX (convertWith src blockOff tree)


-- Infix Precedence Grouping ---------------------------------------------------

infixRecur :: [String] -> [Elem] -> Rex

infixRecur _ [E_REX r] = r

infixRecur [] elems =
    case [r | E_REX r <- elems] of
        [r] -> r
        rs  -> EXPR CLEAR rs

infixRecur (rune:runes) elems =
    case splitOnRune rune elems of
        [g] -> infixRecur runes g
        gs  -> NEST CLEAR rune $ infixRecur runes <$> filter (not . null) gs


splitOnRune :: String -> [Elem] -> [[Elem]]
splitOnRune rune = go []
  where
    go acc [] = [reverse acc]
    go acc (E_RUNE r : rest) | r == rune = reverse acc : go [] rest
    go acc (e : rest) = go (e:acc) rest


-- Public API ------------------------------------------------------------------

rexFromTree :: Tree -> Rex
rexFromTree = convertWith "" 0

rexFromBlockTree :: String -> Tree -> Maybe Rex
rexFromBlockTree src tree = case tree of
    Tree (S_NEST Clear) _ _ _ [] -> Nothing
    Tree (S_NEST Clear) _ o _ ns -> Just $ convertSpaced src o CLEAR ns
    _ -> error "top level tree is always Clear"


-- Pretty Printer --------------------------------------------------------------

ppRex :: Rex -> String
ppRex = go 0
  where
    ind n = replicate n ' '

    go i = \case
        LEAF sh s ->
            ind i ++ show sh ++ " " ++ show s ++ "\n"

        NEST c r kids ->
            ind i ++ "NEST " ++ show c ++ " " ++ show r ++ "\n"
            ++ concatMap (go (i+2)) kids

        EXPR c kids ->
            ind i ++ "EXPR " ++ show c ++ "\n"
            ++ concatMap (go (i+2)) kids

        PREF r child ->
            ind i ++ "PREF " ++ show r ++ "\n"
            ++ go (i+2) child

        TYTE r kids ->
            ind i ++ "TYTE " ++ show r ++ "\n"
            ++ concatMap (go (i+2)) kids

        JUXT kids ->
            ind i ++ "JUXT\n"
            ++ concatMap (go (i+2)) kids

        HEIR kids ->
            ind i ++ "HEIR\n"
            ++ concatMap (go (i+2)) kids

        BLOC c r hd items ->
            ind i ++ "BLOC " ++ show c ++ " " ++ show r ++ "\n"
            ++ go (i+2) hd
            ++ concatMap (go (i+2)) items

        OPEN r kids ->
            ind i ++ "OPEN " ++ show r ++ "\n"
            ++ concatMap (go (i+2)) kids


--- Main -----------------------------------------------------------------------

rexMain :: IO ()
rexMain = do
  src <- getContents
  let results = Tr.parseRex src
  mapM_ (\(slice, tree) ->
    case rexFromBlockTree slice tree of
      Nothing -> pure ()
      Just r  -> putStrLn (ppRex r)
    ) results
