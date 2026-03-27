{-# LANGUAGE LambdaCase #-}
{-# OPTIONS_GHC -Wno-x-partial #-}

module Rex.Rex
    ( Rex(..), LeafShape(..), Color(..), ppRex
    , rexSpan, noSpan
    , rexFromTree, rexFromBlockTree
    , collectRexErrors
    )
where

import qualified Rex.Tree2 as Tr
import qualified Rex.String as Str

import Rex.Lex    (Span (..))
import Rex.Tree2  (Bracket (..), Leaf (..), Node (..), Shape (..), Tree (..), treePos)
import Rex.Error  (BadReason(..), RexError(..))
import Data.List  (nubBy, sortBy)


-- Rex Data Model --------------------------------------------------------------

data LeafShape = WORD | QUIP | CORD | TAPE | PAGE | SPAN | SLUG | BAD BadReason
  deriving (Eq, Show)

data Color = PAREN | BRACK | CURLY | CLEAR
  deriving (Eq, Show)

data Rex
    = LEAF Span LeafShape String
    | NEST Span Color String [Rex]           -- (x + y), {a | b}
    | EXPR Span Color [Rex]                  -- [f x], (x), ()
    | PREF Span String Rex                   -- :x, -y
    | TYTE Span String [Rex]                 -- x.y, a:b
    | BLOC Span Color String Rex [Rex]       -- head rune:\n  a\n  b
    | OPEN Span String [Rex]                 -- + x y (layout prefix)
    | JUXT Span [Rex]                        -- f(x), f(x)[1]
    | HEIR Span [Rex]                        -- + x\n+ y\nz
  deriving (Eq, Show)

-- | Get the span of a Rex node
rexSpan :: Rex -> Span
rexSpan (LEAF sp _ _)     = sp
rexSpan (NEST sp _ _ _)   = sp
rexSpan (EXPR sp _ _)     = sp
rexSpan (PREF sp _ _)     = sp
rexSpan (TYTE sp _ _)     = sp
rexSpan (BLOC sp _ _ _ _) = sp
rexSpan (OPEN sp _ _)     = sp
rexSpan (JUXT sp _)       = sp
rexSpan (HEIR sp _)       = sp

-- | Empty span (for synthetic nodes)
noSpan :: Span
noSpan = Span 0 0 0 0


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

leafToRex :: Span -> Leaf -> Rex
leafToRex sp = \case
    L_WORD s -> LEAF sp WORD s
    L_TRAD s -> tradToRex sp s
    L_UGLY s -> uglyToRex sp s
    L_SLUG s -> LEAF sp SLUG (Str.stripSlug s)
    L_BAD  s -> classifyBadLeaf sp s

-- | Classify a BAD leaf from the lexer by examining its content
classifyBadLeaf :: Span -> String -> Rex
classifyBadLeaf sp s = LEAF sp (BAD reason) s
  where
    reason
        | "\"" `isPrefixOf` s && not ("\"" `isSuffixOf` s) = UnclosedTrad
        | "''" `isPrefixOf` s && not ("''" `isSuffixOf` s) = UnclosedUgly
        | otherwise = InvalidChar

    isPrefixOf [] _          = True
    isPrefixOf _  []         = False
    isPrefixOf (x:xs) (y:ys) = x == y && isPrefixOf xs ys

    isSuffixOf xs ys = isPrefixOf (reverse xs) (reverse ys)

-- | Convert a TRAD string to Rex, using Rex.String for extraction
tradToRex :: Span -> String -> Rex
tradToRex sp s = case Str.stripTrad sp s of
    (True,  Str.StripOK content) -> LEAF sp TAPE content
    (False, Str.StripOK content) -> LEAF sp CORD content
    (_,     Str.StripBad reason) -> LEAF sp (BAD reason) s

-- | Convert an UGLY string to Rex, using Rex.String for extraction
uglyToRex :: Span -> String -> Rex
uglyToRex sp s = case Str.stripUgly sp s of
    (True,  Str.StripOK content) -> LEAF sp PAGE content
    (False, Str.StripOK content) -> LEAF sp SPAN content
    (_,     Str.StripBad reason) -> LEAF sp (BAD reason) s


-- Quip Conversion -------------------------------------------------------------
--
-- A quip (S_QUIP) is converted by extracting its underlying source
-- text (using treeOff/treeLen relative to the block's source slice)
-- and producing a LEAF QUIP.
--
-- For multi-line quips, we normalize indentation by stripping the minimum
-- indent from all non-empty continuation lines. This allows "jagged" input:
--
--   foo = 'html{
--     <body>
--   }
--
-- to be equivalent to the canonical form:
--
--   foo = 'html{
--         <body>
--         }
--
-- Blank lines are ignored when computing minimum indent.

quipToRex :: String -> Int -> Tree -> Rex
quipToRex src blockOff tree@(Tree S_QUIP sp _) =
    let qoff = Tr.treeOff tree
        qlen = Tr.treeLen tree
        s = take qlen (drop (qoff - blockOff) src)
        s' = Str.normalizeQuipIndent s
    in LEAF sp QUIP s'
quipToRex _ _ t = error $ "quipToRex: not a quip: " ++ show (treeShape t)


-- Top-Level Conversion --------------------------------------------------------
--
-- All conversion functions thread (src, blockOff) for quip extraction.
-- src is the source slice for this block; blockOff is the absolute
-- offset where it starts in the original source.

convertWith :: String -> Int -> Tree -> Rex
convertWith src blockOff tree@(Tree shape sp nodes) = case shape of
    S_NEST bk -> convertNest src blockOff sp bk nodes
    S_CLUMP   -> convertClump src blockOff sp nodes
    S_POEM    -> convertPoem src blockOff sp (treePos tree) nodes
    S_ITEM    -> convertSpaced src blockOff sp CLEAR nodes
    S_QUIP    -> quipToRex src blockOff tree
    S_BLOCK   -> error "S_BLOCK: should be consumed by enclosing context"


-- Spaced Node Lists -----------------------------------------------------------

convertSpaced :: String -> Int -> Span -> Color -> [Node] -> Rex
convertSpaced src blockOff sp color nodes = case extractBlock nodes of
    Just (headNodes, rune, blockChildren) ->
        let hd    = spacedHead src blockOff headNodes
            items = map (convertWith src blockOff) blockChildren
        in BLOC sp color rune hd items
    Nothing ->
        spacedGroup src blockOff sp color nodes

spacedHead :: String -> Int -> [Node] -> Rex
spacedHead _   _        []  = EXPR noSpan CLEAR []
spacedHead src blockOff [n] = convertNode src blockOff n
spacedHead src blockOff ns  = spacedGroup src blockOff noSpan CLEAR ns

spacedGroup :: String -> Int -> Span -> Color -> [Node] -> Rex
spacedGroup src blockOff sp color nodes =
    let elems = mergeBlocks src blockOff (map (nodeToElem src blockOff) nodes)
        runes = nubBy (==) $ sortBy runeCmp [r | E_RUNE r <- elems]
    in case runes of
         [] -> case [r | E_REX r <- elems] of
                 []  -> EXPR sp color []
                 [r] -> applyColor sp color r
                 rs  -> EXPR sp color rs
         _  -> let rex = infixRecur sp runes elems
               in applyColor sp color rex

-- | Merge E_BLOCK elements with their preceding rune and head.
-- Pattern: [E_REX head, E_RUNE rune, E_BLOCK items] -> [E_REX (BLOC CLEAR rune head items)]
mergeBlocks :: String -> Int -> [Elem] -> [Elem]
mergeBlocks src blockOff = go []
  where
    go acc [] = reverse acc
    go acc (E_REX hd : E_RUNE r : E_BLOCK _ items : rest) =
        let bloc = BLOC noSpan CLEAR r hd (map (convertWith src blockOff) items)
        in go (E_REX bloc : acc) rest
    go acc (E_RUNE r : E_BLOCK _ items : rest) =
        -- Block with no head - just use empty EXPR as head
        let bloc = BLOC noSpan CLEAR r (EXPR noSpan CLEAR []) (map (convertWith src blockOff) items)
        in go (E_REX bloc : acc) rest
    go acc (e : rest) = go (e : acc) rest

applyColor :: Span -> Color -> Rex -> Rex
applyColor _  CLEAR rex = rex
applyColor sp color rex = case rex of
    NEST _ CLEAR r kids     -> NEST sp color r kids
    EXPR _ CLEAR kids       -> EXPR sp color kids
    BLOC _ CLEAR r hd items -> BLOC sp color r hd items
    _                       -> EXPR sp color [rex]


-- Block Extraction ------------------------------------------------------------

extractBlock :: [Node] -> Maybe ([Node], String, [Tree])
extractBlock nodes =
    case reverse nodes of
      (N_CHILD (Tree S_BLOCK _ blockNodes) : N_RUNE _ rune : revHead) ->
          let items = [t | N_CHILD t <- blockNodes]
          in Just (reverse revHead, rune, items)
      _ -> Nothing


-- Nest Conversion -------------------------------------------------------------

convertNest :: String -> Int -> Span -> Bracket -> [Node] -> Rex
convertNest src blockOff sp bk nodes =
    let color = toColor bk
    in case nodes of
         []  -> EXPR sp color []
         [n] -> applyColor sp color (convertNode src blockOff n)
         _   -> convertSpaced src blockOff sp color nodes

toColor :: Bracket -> Color
toColor Paren = PAREN
toColor Brack = BRACK
toColor Curly = CURLY
toColor Clear = CLEAR


-- Clump Conversion ------------------------------------------------------------

convertClump :: String -> Int -> Span -> [Node] -> Rex
convertClump _   _        _  []    = error "empty clump"
convertClump src blockOff sp nodes = top (nodeToElem src blockOff <$> nodes)
  where
    top :: [Elem] -> Rex
    top [E_REX r] = r
    top (E_RUNE r : rest) = PREF sp r (top rest)
    top es = case juxt [] es of [E_REX r] -> r
                                collapsed -> tight collapsed

    tight :: [Elem] -> Rex
    tight elems =
        case nubBy (==) $ sortBy runeCmp [r | E_RUNE r <- elems] of
             [] -> case [r | E_REX r <- elems] of
                     [r] -> r
                     rs  -> EXPR sp CLEAR rs
             rs -> go rs elems

    go :: [String] -> [Elem] -> Rex
    go _      [E_REX r] = r
    go []     elems     = case [r | E_REX r <- elems] of
                              [r] -> r
                              rs  -> EXPR sp CLEAR rs
    go (r:rs) elems     = case go rs <$> splitOnRune r elems of
                              [k]  -> k
                              kids -> TYTE sp r kids

    juxt :: [Rex] -> [Elem] -> [Elem]
    juxt acc []                    = flush acc []
    juxt acc (e@(E_RUNE _) : rest) = flush acc (e : juxt [] rest)
    juxt acc (E_REX r : rest)      = juxt (acc ++ [r]) rest
    juxt acc (E_BLOCK _ _ : rest)  = juxt acc rest  -- shouldn't happen; mergeBlocks handles these

    flush :: [Rex] -> [Elem] -> [Elem]
    flush []  rest = rest
    flush [r] rest = E_REX r : rest
    flush rs  rest = E_REX (JUXT sp rs) : rest


-- Poem Conversion -------------------------------------------------------------

convertPoem :: String -> Int -> Span -> Int -> [Node] -> Rex
convertPoem _   _        _  _   [] = error "empty poem"
convertPoem src blockOff sp pos (N_RUNE _ r : rest) =
    let (children, heirNodes) = splitHeir pos rest
        open = OPEN sp r (map (convertNode src blockOff) children)
    in case heirNodes of
         [] -> open
         _  -> mkHeir sp (open : concatMap (flattenHeir . convertNode src blockOff) heirNodes)
-- Poem starting with SLUG: flatten everything into a HEIR
convertPoem src blockOff sp pos (N_LEAF leafSp lf : rest) =
    let slug = leafToRex leafSp lf
        -- Flatten all children and heir nodes together
        allNodes = rest
        flattened = concatMap (flattenHeir . convertNode src blockOff) allNodes
    in mkHeir sp (slug : flattened)
convertPoem _ _ _ _ _ = error "poem must start with a rune or leaf"

splitHeir :: Int -> [Node] -> ([Node], [Node])
splitHeir pos = go []
  where
    go acc [] = (reverse acc, [])
    go acc rest@(n:_)
      | Tr.nodeCol n <= pos = (reverse acc, rest)
      | otherwise           = go (n : acc) (tail rest)

mkHeir :: Span -> [Rex] -> Rex
mkHeir _  [r] = r
mkHeir sp rs  = HEIR sp rs

flattenHeir :: Rex -> [Rex]
flattenHeir (HEIR _ rs) = rs
flattenHeir r           = [r]


-- Node Conversion -------------------------------------------------------------

convertNode :: String -> Int -> Node -> Rex
convertNode _   _        (N_LEAF sp lf) = leafToRex sp lf
convertNode src blockOff (N_CHILD tree) = convertWith src blockOff tree
convertNode _   _        (N_RUNE _ r)   = error $ "convertNode: bare rune: " ++ r


-- Intermediate Elements -------------------------------------------------------

data Elem = E_RUNE String | E_REX Rex | E_BLOCK String [Tree]

nodeToElem :: String -> Int -> Node -> Elem
nodeToElem _   _        (N_RUNE _ r)   = E_RUNE r
nodeToElem _   _        (N_LEAF sp lf) = E_REX (leafToRex sp lf)
nodeToElem src blockOff (N_CHILD tree) = case tree of
    Tree S_BLOCK _ blockNodes ->
        -- Extract the rune that precedes this block by looking at context
        -- For now, we'll handle this in the grouping phase
        E_BLOCK "" [t | N_CHILD t <- blockNodes]
    _ -> E_REX (convertWith src blockOff tree)


-- Infix Precedence Grouping ---------------------------------------------------

infixRecur :: Span -> [String] -> [Elem] -> Rex

infixRecur _ _ [E_REX r] = r

infixRecur sp [] elems =
    case [r | E_REX r <- elems] of
        [r] -> r
        rs  -> EXPR sp CLEAR rs

infixRecur sp (rune:runes) elems =
    case splitOnRune rune elems of
        [g] -> infixRecur sp runes g
        gs  -> NEST sp CLEAR rune $ infixRecur sp runes <$> filter (not . null) gs


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
    Tree (S_NEST Clear) _ [] -> Nothing
    Tree (S_NEST Clear) sp ns -> Just $ convertSpaced src (Tr.treeOff tree) sp CLEAR ns
    _ -> error "top level tree is always Clear"


-- Pretty Printer --------------------------------------------------------------

ppRex :: Rex -> String
ppRex = go 0
  where
    ind n = replicate n ' '
    ppSpan (Span l c o n) = show l ++ ":" ++ show c ++ " [" ++ show o ++ "+" ++ show n ++ "]"

    go i = \case
        LEAF sp sh s ->
            ind i ++ show sh ++ " " ++ ppSpan sp ++ " " ++ show s ++ "\n"

        NEST sp c r kids ->
            ind i ++ "NEST " ++ show c ++ " " ++ show r ++ " " ++ ppSpan sp ++ "\n"
            ++ concatMap (go (i+2)) kids

        EXPR sp c kids ->
            ind i ++ "EXPR " ++ show c ++ " " ++ ppSpan sp ++ "\n"
            ++ concatMap (go (i+2)) kids

        PREF sp r child ->
            ind i ++ "PREF " ++ show r ++ " " ++ ppSpan sp ++ "\n"
            ++ go (i+2) child

        TYTE sp r kids ->
            ind i ++ "TYTE " ++ show r ++ " " ++ ppSpan sp ++ "\n"
            ++ concatMap (go (i+2)) kids

        JUXT sp kids ->
            ind i ++ "JUXT " ++ ppSpan sp ++ "\n"
            ++ concatMap (go (i+2)) kids

        HEIR sp kids ->
            ind i ++ "HEIR " ++ ppSpan sp ++ "\n"
            ++ concatMap (go (i+2)) kids

        BLOC sp c r hd items ->
            ind i ++ "BLOC " ++ show c ++ " " ++ show r ++ " " ++ ppSpan sp ++ "\n"
            ++ go (i+2) hd
            ++ concatMap (go (i+2)) items

        OPEN sp r kids ->
            ind i ++ "OPEN " ++ show r ++ " " ++ ppSpan sp ++ "\n"
            ++ concatMap (go (i+2)) kids


-- Error Collection -------------------------------------------------------------

-- | Collect all errors from a Rex tree
collectRexErrors :: Rex -> [RexError]
collectRexErrors = go
  where
    go = \case
        LEAF sp (BAD reason) s -> [RexError sp reason s]
        LEAF _ _ _             -> []
        NEST _ _ _ kids        -> concatMap go kids
        EXPR _ _ kids          -> concatMap go kids
        PREF _ _ child         -> go child
        TYTE _ _ kids          -> concatMap go kids
        JUXT _ kids            -> concatMap go kids
        HEIR _ kids            -> concatMap go kids
        BLOC _ _ _ hd items    -> go hd ++ concatMap go items
        OPEN _ _ kids          -> concatMap go kids
