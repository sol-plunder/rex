{-# LANGUAGE LambdaCase #-}
{-# OPTIONS_GHC -Wall -Wno-x-partial #-}

module Rex.Tree2 where

import Rex.Lex


-- Parse Tree ------------------------------------------------------------------

data Leaf
  = L_WORD String
  | L_TRAD String
  | L_UGLY String
  | L_SLUG String
  | L_BAD  String
  deriving (Eq, Show)

data Node = N_RUNE !Span String | N_LEAF !Span Leaf | N_CHILD Tree
  deriving (Eq, Show)

data Bracket = Paren | Brack | Curly | Clear
  deriving (Eq, Show)

data Shape = S_NEST Bracket | S_CLUMP | S_QUIP | S_POEM | S_BLOCK | S_ITEM
  deriving (Eq, Show)

data Tree = Tree
  { treeShape :: !Shape
  , treeSpan  :: !Span
  , treeNodes :: [Node]
  } deriving (Eq, Show)

-- Compatibility accessors
treePos :: Tree -> Int
treePos = spanCol . treeSpan

treeOff :: Tree -> Int
treeOff = spanOff . treeSpan

treeLen :: Tree -> Int
treeLen = spanLen . treeSpan


-- Contexts and Stack ----------------------------------------------------------

data CtxTy = CT_NEST !Bracket | CT_CLUMP | CT_POEM | CT_BLOCK | CT_ITEM
  deriving (Eq, Show)

-- cxOff uses maxBound as a sentinel for "not yet set" (root contexts).
-- It gets set on the first substantive appendNode.
data Ctx = Ctx
  { cxTy       :: !CtxTy
  , cxLin      :: !Int        -- start line
  , cxPos      :: !Int        -- start column
  , cxOff      :: !Int        -- start offset (maxBound = unset)
  , cxEnd      :: !Int        -- end offset of last substantive token
  , cxNodesRev :: [Node]
  , cxFirstCol :: !(Maybe Int)
  , cxRuneCnt  :: !Int
  , cxLastRune :: !Bool
  } deriving (Eq, Show)

data StackEntry = SE_CTX !Ctx | SE_QUIP !Int !Int !Int  -- line, col, offset
  deriving (Eq, Show)

type Stack = [StackEntry]

data P = P { pStk :: !Stack, pOut :: [(String, Tree)] } deriving (Eq, Show)


-- Helpers ---------------------------------------------------------------------

nodeCol :: Node -> Int
nodeCol = \case N_RUNE sp _ -> spanCol sp; N_LEAF sp _ -> spanCol sp; N_CHILD t -> treePos t

mkCtx :: CtxTy -> Int -> Int -> Int -> Ctx
mkCtx t l p o = Ctx t l p o o [] Nothing 0 False

-- | Root context with unset offset (will be set by first content).
mkRootCtx :: Ctx
mkRootCtx = Ctx (CT_NEST Clear) 1 0 maxBound 0 [] Nothing 0 False

ctxEmpty :: Ctx -> Bool
ctxEmpty = null . cxNodesRev

ctxNodes :: Ctx -> [Node]
ctxNodes = reverse . cxNodesRev

-- | Append a node. nlin=node line, noff=node start offset, end=node end offset.
-- Updates cxOff/cxLin on first push (for root contexts with sentinel).
appendNode :: Node -> Int -> Int -> Int -> Ctx -> Ctx
appendNode n nlin noff end c =
  c { cxNodesRev = n : cxNodesRev c
    , cxLin      = if cxOff c == maxBound then nlin else cxLin c
    , cxOff      = if cxOff c == maxBound then noff else cxOff c
    , cxEnd      = max (cxEnd c) end
    , cxFirstCol = case cxFirstCol c of Nothing -> Just (nodeCol n); j -> j
    , cxRuneCnt  = cxRuneCnt c + if isR then 1 else 0
    , cxLastRune = isR
    }
  where isR = case n of N_RUNE{} -> True; _ -> False

finalize :: Ctx -> Tree
finalize c = Tree sh (Span (cxLin c) (cxPos c) o (max 0 (cxEnd c - o))) (ctxNodes c)
  where
    sh = case cxTy c of
           CT_NEST bk -> S_NEST bk; CT_CLUMP -> S_CLUMP
           CT_POEM -> S_POEM; CT_BLOCK -> S_BLOCK; CT_ITEM -> S_ITEM
    o  = if cxOff c == maxBound then 0 else cxOff c

isLeafTy :: TokTy -> Bool
isLeafTy = \case WORD -> True; TRAD -> True; UGLY -> True
                 SLUG -> True; BAD  -> True; _    -> False

mkLeaf :: Tok -> Node
mkLeaf t = N_LEAF (tokSpan t) $ case ty t of
    WORD -> L_WORD s; TRAD -> L_TRAD s; UGLY -> L_UGLY s
    SLUG -> L_SLUG s; _    -> L_BAD s
  where s = text t

tokEnd :: Tok -> Int
tokEnd t = off t + len t

freePos :: Tok -> Int
freePos tok = (col tok - 1) + len tok

freeNode :: Tok -> Node
freeNode tok = N_RUNE (Span (lin tok) (freePos tok) (off tok) (len tok)) (text tok)

clmpNode :: Tok -> Node
clmpNode tok = N_RUNE (tokSpan tok) (text tok)


-- Finalization ----------------------------------------------------------------

pop :: Stack -> Stack

-- Quip capture: wrap child in S_QUIP, deliver via pushLeaf
pop (SE_CTX k : SE_QUIP qlin qcol qoff : rest) =
    let tree = finalize k
        quip = Tree S_QUIP (Span qlin qcol qoff (cxEnd k - qoff)) [N_CHILD tree]
    in pushLeaf (N_CHILD quip) qlin qoff (cxEnd k) rest

-- Empty block: discard
pop (SE_CTX k : rest)
    | cxTy k == CT_BLOCK, ctxEmpty k = rest

-- Nest: deliver via pushLeaf (enables juxtaposition)
pop (SE_CTX k : rest)
    | case cxTy k of CT_NEST{} -> True; _ -> False
    = let t = finalize k in pushLeaf (N_CHILD t) (spanLin (treeSpan t)) (treeOff t) (cxEnd k) rest

-- Everything else: deliver via pushInto
pop (SE_CTX k : rest) =
    let t = finalize k in pushInto (N_CHILD t) (spanLin (treeSpan t)) (treeOff t) (cxEnd k) rest

pop _ = error "pop: cannot pop root"

popAll :: Stack -> Stack
popAll st@[SE_CTX _] = st
popAll st            = popAll (pop st)


-- Pushing into the stack ------------------------------------------------------
-- nlin = node line, noff = node start offset, end = node end offset

pushInto :: Node -> Int -> Int -> Int -> Stack -> Stack
pushInto n nlin noff end (SE_CTX c : rest)          = SE_CTX (appendNode n nlin noff end c) : rest
pushInto n nlin noff end (q@(SE_QUIP _ _ _) : rest) = q : pushInto n nlin noff end rest
pushInto _ _    _    _   []                         = error "pushInto: empty stack"

pushLeaf :: Node -> Int -> Int -> Int -> Stack -> Stack
pushLeaf node nlin noff end st = pushInto node nlin noff end (openClump nlin (nodeCol node) noff st)

openClump :: Int -> Int -> Int -> Stack -> Stack
openClump _   _   _    st@(SE_CTX c : _) | cxTy c == CT_CLUMP = st
openClump lin col coff st = SE_CTX (mkCtx CT_CLUMP lin col coff) : st


-- Context Dispatch ------------------------------------------------------------

step :: P -> Tok -> P
step p t = case ty t of
    EOF -> emitRoot True p
    EOB -> emitRoot True p
    _   -> p { pStk = dispatch t (pStk p) }

dispatch :: Tok -> Stack -> Stack
dispatch tok (SE_CTX c : rest) = case cxTy c of
    CT_CLUMP   -> stepClump  tok c rest
    CT_POEM    -> stepPoem   tok c rest
    CT_BLOCK   -> stepBlock  tok c rest
    CT_ITEM    -> stepItem   tok c rest
    CT_NEST{}  -> stepSpaced tok c rest
dispatch tok (SE_QUIP ql qc qo : rest) = stepQuip tok ql qc qo rest
dispatch _   [] = error "dispatch: empty stack"


-- Clump -----------------------------------------------------------------------

stepClump :: Tok -> Ctx -> Stack -> Stack
stepClump tok ctx rest = case ty tok of
    _ | isLeafTy (ty tok) ->
        SE_CTX (appendNode (mkLeaf tok) (lin tok) (off tok) (tokEnd tok) ctx) : rest
    CLMP ->
        SE_CTX (appendNode (clmpNode tok) (lin tok) (off tok) (tokEnd tok) ctx) : rest
    BEGIN ->
        let bk = case text tok of "(" -> Paren; "[" -> Brack
                                  "{" -> Curly; _   -> Paren
        in SE_CTX (mkCtx (CT_NEST bk) (lin tok) (col tok) (off tok))
         : SE_CTX ctx : rest
    QUIP ->
        SE_QUIP (lin tok) (col tok) (off tok) : SE_CTX ctx : rest
    _ -> dispatch tok (pop (SE_CTX ctx : rest))


-- Quip ------------------------------------------------------------------------

stepQuip :: Tok -> Int -> Int -> Int -> Stack -> Stack
stepQuip tok qlin qcol qoff rest = case ty tok of
    _ | isLeafTy (ty tok) ->
        pushInto (mkLeaf tok) (lin tok) (off tok) (tokEnd tok)
          (openClump (lin tok) (col tok) (off tok) (SE_QUIP qlin qcol qoff : rest))
    CLMP ->
        pushInto (clmpNode tok) (lin tok) (off tok) (tokEnd tok)
          (openClump (lin tok) (col tok) (off tok) (SE_QUIP qlin qcol qoff : rest))
    FREE ->
        pushInto (freeNode tok) (lin tok) (off tok) (tokEnd tok)
          (openClump (lin tok) (col tok) (off tok) (SE_QUIP qlin qcol qoff : rest))
    BEGIN ->
        let bk = case text tok of "(" -> Paren; "[" -> Brack
                                  "{" -> Curly; _   -> Paren
        in SE_CTX (mkCtx (CT_NEST bk) (lin tok) (col tok) (off tok))
         : openClump (lin tok) (col tok) (off tok) (SE_QUIP qlin qcol qoff : rest)
    QUIP ->
        SE_QUIP (lin tok) (col tok) (off tok)
          : openClump (lin tok) (col tok) (off tok) (SE_QUIP qlin qcol qoff : rest)
    WYTE -> dispatch tok rest
    EOL  -> dispatch tok rest
    END  -> dispatch tok rest
    _    -> dispatch tok rest


-- Poem ------------------------------------------------------------------------

stepPoem :: Tok -> Ctx -> Stack -> Stack
stepPoem tok ctx rest
    -- Pop if token is before the poem's child column, BUT
    -- allow FREE runes that would be heirs (same freePos as poem)
    | isReal, col tok < cxPos ctx, not (isHeirRune tok ctx) =
        dispatch tok (pop (SE_CTX ctx : rest))
    | otherwise = case ty tok of
    _ | isLeafTy (ty tok) ->
        pushLeaf (mkLeaf tok) (lin tok) (off tok) (tokEnd tok) (SE_CTX ctx : rest)
    CLMP ->
        pushInto (clmpNode tok) (lin tok) (off tok) (tokEnd tok)
          (openClump (lin tok) (col tok) (off tok) (SE_CTX ctx : rest))
    FREE ->
        let pos = freePos tok
        in pushInto (freeNode tok) (lin tok) (off tok) (tokEnd tok)
         $ SE_CTX (mkCtx CT_POEM (lin tok) pos (off tok))
         : closeClump (SE_CTX ctx : rest)
    BEGIN ->
        let bk = case text tok of "(" -> Paren; "[" -> Brack
                                  "{" -> Curly; _   -> Paren
        in SE_CTX (mkCtx (CT_NEST bk) (lin tok) (col tok) (off tok))
         : openClump (lin tok) (col tok) (off tok) (SE_CTX ctx : rest)
    QUIP ->
        SE_QUIP (lin tok) (col tok) (off tok) : closeClump (SE_CTX ctx : rest)
    END ->
        dispatch tok (pop (SE_CTX ctx : rest))
    WYTE -> closeClump (SE_CTX ctx : rest)
    EOL  -> closeClump (SE_CTX ctx : rest)
    _ -> SE_CTX ctx : rest
  where
    isReal = isLeafTy (ty tok) || ty tok == CLMP || ty tok == FREE
          || ty tok == BEGIN || ty tok == QUIP || ty tok == END

    -- A FREE rune is an heir if its freePos equals the poem's cxPos
    -- (meaning both runes start at the same column)
    isHeirRune t c = ty t == FREE && freePos t == cxPos c


-- Spaced (Nest) ---------------------------------------------------------------

stepSpaced :: Tok -> Ctx -> Stack -> Stack
stepSpaced tok ctx rest = case ty tok of
    SLUG ->
        -- Slug starts a poem context at its column, like a FREE rune
        pushInto (mkLeaf tok) (lin tok) (off tok) (tokEnd tok)
         $ SE_CTX (mkCtx CT_POEM (lin tok) (col tok) (off tok))
         : closeClump (SE_CTX ctx : rest)
    _ | isLeafTy (ty tok) ->
        pushLeaf (mkLeaf tok) (lin tok) (off tok) (tokEnd tok) (SE_CTX ctx : rest)
    CLMP ->
        pushInto (clmpNode tok) (lin tok) (off tok) (tokEnd tok)
          (openClump (lin tok) (col tok) (off tok) (SE_CTX ctx : rest))
    FREE
        | ctxEmpty ctx || cxLastRune ctx ->
            let pos = freePos tok
            in pushInto (freeNode tok) (lin tok) (off tok) (tokEnd tok)
             $ SE_CTX (mkCtx CT_POEM (lin tok) pos (off tok))
             : closeClump (SE_CTX ctx : rest)
        | otherwise ->
            SE_CTX (appendNode (freeNode tok) (lin tok) (off tok) (tokEnd tok) ctx) : rest
    BEGIN ->
        let bk = case text tok of "(" -> Paren; "[" -> Brack
                                  "{" -> Curly; _   -> Paren
        in SE_CTX (mkCtx (CT_NEST bk) (lin tok) (col tok) (off tok))
         : openClump (lin tok) (col tok) (off tok) (SE_CTX ctx : rest)
    END ->
        -- Include closing bracket in nest's extent, then pop.
        let st = closeClump (SE_CTX ctx : rest)
            st' = updateTopEnd (tokEnd tok) st
        in pop st'
    QUIP ->
        SE_QUIP (lin tok) (col tok) (off tok) : closeClump (SE_CTX ctx : rest)
    WYTE -> closeClump (SE_CTX ctx : rest)
    EOL  -> tryOpenBlock (closeClump (SE_CTX ctx : rest))
    _ -> SE_CTX ctx : rest


-- Item ------------------------------------------------------------------------

stepItem :: Tok -> Ctx -> Stack -> Stack
stepItem tok ctx rest
    | isReal, col tok < cxPos ctx =
        dispatch tok (pop (SE_CTX ctx : rest))
    | isReal, col tok == cxPos ctx, not (ctxEmpty ctx) =
        dispatch tok (pop (SE_CTX ctx : rest))
    | ty tok == END =
        dispatch tok (pop (SE_CTX ctx : rest))
    | otherwise = stepSpaced tok ctx rest
  where
    isReal = isLeafTy (ty tok) || ty tok == CLMP || ty tok == FREE
          || ty tok == BEGIN || ty tok == QUIP


-- Block -----------------------------------------------------------------------

stepBlock :: Tok -> Ctx -> Stack -> Stack
stepBlock tok ctx rest
    | isReal, col tok < cxPos ctx =
        dispatch tok (pop (SE_CTX ctx : rest))
    | isReal, col tok >= cxPos ctx =
        let st = SE_CTX (mkCtx CT_ITEM (lin tok) (col tok) (off tok))
               : SE_CTX (ctx { cxPos = col tok })
               : rest
        in dispatch tok st
    | ty tok == END =
        dispatch tok (pop (SE_CTX ctx : rest))
    | otherwise = SE_CTX ctx : rest
  where
    isReal = isLeafTy (ty tok) || ty tok == CLMP || ty tok == FREE
          || ty tok == BEGIN || ty tok == QUIP


-- Block Trigger ---------------------------------------------------------------

tryOpenBlock :: Stack -> Stack
tryOpenBlock st@(SE_CTX c : _)
    | case cxTy c of CT_NEST{} -> True; CT_ITEM -> True; _ -> False
    , not (ctxEmpty c)
    , cxLastRune c
    , cxRuneCnt c == 1
    , Just firstCol <- cxFirstCol c
    = SE_CTX (mkCtx CT_BLOCK (cxLin c) (1 + firstCol) (cxEnd c)) : st
tryOpenBlock st = st

closeClump :: Stack -> Stack
closeClump st@(SE_CTX c : _) | cxTy c == CT_CLUMP = pop st
closeClump st = st

updateTopEnd :: Int -> Stack -> Stack
updateTopEnd end (SE_CTX c : rest) = SE_CTX (c { cxEnd = max (cxEnd c) end }) : rest
updateTopEnd _   st                = st


-- Emit Root -------------------------------------------------------------------

emitRoot :: Bool -> P -> P
emitRoot reset (P st outRev) = case popAll st of
    st'@(SE_CTX r : _) -> P stNext (("", finalize r) : outRev)
      where stNext = if reset then [SE_CTX mkRootCtx] else st'
    _ -> error "no root after popAll"

parseTree :: [Tok] -> [Tree]
parseTree toks = map snd $ reverse $ pOut $ foldl step (P [SE_CTX mkRootCtx] []) toks


-- High-level API --------------------------------------------------------------

parseRex :: String -> [(String, Tree)]
parseRex src =
    let toks  = bsplit (lexRex src)
        trees = reverse $ pOut $ foldl step (P [SE_CTX mkRootCtx] []) toks
    in [ (slice (treeOff t) (treeLen t), t) | (_, t) <- trees ]
  where
    slice o n = take n (drop o src)


-- Pretty Printer --------------------------------------------------------------

ppTree :: Tree -> String
ppTree = go 0
 where
  go i (Tree sh sp nodes) =
    indent i ++ showShape sh ++ " " ++ ppSpan sp ++ "\n"
    ++ concatMap (ppNode (i+2)) nodes

  ppSpan (Span l c o n) = show l ++ ":" ++ show c ++ " [" ++ show o ++ "+" ++ show n ++ "]"

  showShape = \case
    S_NEST Paren -> "PAREN"; S_NEST Brack -> "BRACK"
    S_NEST Curly -> "CURLY"; S_NEST Clear -> "CLEAR"
    S_CLUMP -> "CLUMP"; S_QUIP -> "QUIP"
    S_POEM -> "POEM"; S_BLOCK -> "BLOCK"; S_ITEM -> "ITEM"

  ppNode :: Int -> Node -> String
  ppNode i = \case
    N_RUNE sp r  -> indent i ++ "RUNE " ++ ppSpan sp ++ " " ++ show r ++ "\n"
    N_LEAF sp lf -> indent i ++ leafTag lf ++ " " ++ ppSpan sp ++ " "
                             ++ show (leafText lf) ++ "\n"
    N_CHILD tr   -> go i tr

  leafTag = \case
    L_WORD{} -> "WORD"; L_TRAD{} -> "TRAD"; L_UGLY{} -> "UGLY"
    L_SLUG{} -> "SLUG"; L_BAD{}  -> "BAD"

  leafText = \case
    L_WORD s -> s; L_TRAD s -> s; L_UGLY s -> s
    L_SLUG s -> s; L_BAD  s -> s

  indent n = replicate n ' '
