{-# LANGUAGE LambdaCase #-}

-- Copyright (c) 2026 Benjamin Summers
-- SPDX-License-Identifier: MIT
-- See LICENSE for full terms.
--
-- Pretty printer for Rex.Tree2.Tree, producing Rex source notation.
-- Uses Rex.PDoc for layout.

module Rex.PrintTree
    ( printTree
    , printNode
    , printLeaf
    , prettyMain
    ) where

import Rex.Tree2
import Rex.PDoc


-- | Render a Tree to a String, fitting within the given page width.
printTree :: Int -> Tree -> String
printTree width = render width . treeDoc


-- Top-level Tree Dispatch -----------------------------------------------------

treeDoc :: Tree -> PDoc
treeDoc (Tree shape _pos _off _len nodes) = case shape of
    S_NEST bk -> nestDoc bk nodes
    S_CLUMP   -> clumpDoc nodes
    S_QUIP    -> quipDoc nodes
    S_POEM    -> poemDoc nodes
    S_BLOCK   -> blockDoc nodes
    S_ITEM    -> itemDoc nodes


-- Leaves and Nodes ------------------------------------------------------------

printLeaf :: Leaf -> PDoc
printLeaf = \case
    L_WORD s -> pdocText s
    L_TRAD s -> pdocText s
    L_UGLY s -> pdocText s
    L_SLUG s -> pdocText s
    L_BAD  s -> pdocText s   -- render bad tokens as-is

printNode :: Node -> PDoc
printNode = \case
    N_RUNE _ r  -> pdocText r
    N_LEAF _ lf -> printLeaf lf
    N_CHILD t   -> treeDoc t


-- Clump -----------------------------------------------------------------------
--
-- Tight adjacency: nodes concatenated with no spaces.

clumpDoc :: [Node] -> PDoc
clumpDoc = foldr (PCat . printNode) PEmpty


-- Nest ------------------------------------------------------------------------
--
-- Bracket forms. Content nodes are separated by spaces, with the choice
-- of fitting on one line or expanding.

nestDoc :: Bracket -> [Node] -> PDoc
nestDoc bk nodes =
    let (open, close) = bracketChars bk
        content       = nestContent nodes
    in case bk of
         Clear -> content
         _     -> PCat (PChar open) (PCat content (PChar close))

nestContent :: [Node] -> PDoc
nestContent []    = PEmpty
nestContent nodes = PDent (nodeSep nodes)

-- Separate nodes with space-or-newline, choosing the most compact layout.
-- Blocks and poems always start on their own line.
nodeSep :: [Node] -> PDoc
nodeSep []     = PEmpty
nodeSep [n]    = printNode n
nodeSep (n:ns) =
    let rest = nodeSep ns
    in case ns of
         (b:_) | isBlock b -> PCat (printNode n) (PCat PLine rest)
         _                 -> pdocSpaceOrLine (printNode n) rest

isBlock :: Node -> Bool
isBlock (N_CHILD (Tree S_BLOCK _ _ _ _)) = True
isBlock (N_CHILD (Tree S_POEM  _ _ _ ns)) =
    not (poemInlineable (drop 1 ns))  -- drop the leading rune node
isBlock _ = False

bracketChars :: Bracket -> (Char, Char)
bracketChars Paren = ('(', ')')
bracketChars Brack = ('[', ']')
bracketChars Curly = ('{', '}')
bracketChars Clear = (' ', ' ')  -- unused; Clear is handled above


-- Quip ------------------------------------------------------------------------
--
-- A quip is a tick followed immediately by its child, with no space.

quipDoc :: [Node] -> PDoc
quipDoc []    = pdocText "'()"   -- empty quip
quipDoc (n:_) = PCat (PChar '\'') (printNode n)


-- Poem ------------------------------------------------------------------------
--
-- A rune poem: a free rune followed by children gathered by indentation.
--
-- A poem is inlineable if all children except possibly the last are closed,
-- and the last is either closed or itself inlineable. If inlineable, we
-- offer a PChoice between flat and vertical. If not, we render vertically
-- unconditionally — no PChoice is offered.

poemDoc :: [Node] -> PDoc
poemDoc [] = PEmpty
poemDoc (N_RUNE _ rune : children) =
    let runeDoc  = pdocText rune
        vertical = PDent (PCat runeDoc (PCat pdocSpace (poemChildrenVertical children)))
    in if poemInlineable children
       then PChoice
                (PCat runeDoc (PCat pdocSpace (poemChildrenFlat children)))
                vertical
       else vertical
poemDoc nodes = nodeSep nodes  -- fallback: shouldn't happen in a well-formed tree

-- A list of poem children is inlineable if all but the last are closed,
-- and the last is closed or inlineable.
poemInlineable :: [Node] -> Bool
poemInlineable []     = True
poemInlineable [n]    = not (isOpen n) || poemNodeInlineable n
poemInlineable (n:ns) = not (isOpen n) && poemInlineable ns

poemNodeInlineable :: Node -> Bool
poemNodeInlineable (N_CHILD (Tree S_POEM _ _ _ (N_RUNE _ _ : children))) =
    poemInlineable children
poemNodeInlineable n = not (isOpen n)

-- Flat rendering: all children space-separated on one line.
poemChildrenFlat :: [Node] -> PDoc
poemChildrenFlat []     = PEmpty
poemChildrenFlat [n]    = printNode n
poemChildrenFlat (n:ns) = PCat (printNode n) (PCat pdocSpace (poemChildrenFlat ns))

-- Vertical rendering: open children use pdocBackstep, closed use space.
-- pdocBackstep already contains PLine internally — do not add extra PLines.
poemChildrenVertical :: [Node] -> PDoc
poemChildrenVertical []     = PEmpty
poemChildrenVertical [n]    = printNode n
poemChildrenVertical (n:ns)
    | isOpen n  = pdocBackstep (printNode n) (poemChildrenVertical ns)
    | otherwise = PCat (printNode n) (PCat pdocSpace (poemChildrenVertical ns))

-- An "open" node is one that may expand into a vertical poem structure,
-- requiring backstep alignment with its siblings.
isOpen :: Node -> Bool
isOpen (N_CHILD (Tree S_POEM  _ _ _ _)) = True
isOpen (N_CHILD (Tree S_BLOCK _ _ _ _)) = True
isOpen _                                = False


-- Block -----------------------------------------------------------------------
--
-- A block contains items, each on its own line at a fixed 4-space indent.

blockDoc :: [Node] -> PDoc
blockDoc []    = PEmpty
blockDoc items = PCat (pdocText "    ") (PDent (blockItems items))

blockItems :: [Node] -> PDoc
blockItems []     = PEmpty
blockItems [n]    = printNode n
blockItems (n:ns) = PCat (printNode n) (PCat PLine (blockItems ns))


-- Item ------------------------------------------------------------------------
--
-- An item is the content of one block entry, rendered like a nest.

itemDoc :: [Node] -> PDoc
itemDoc = nodeSep


-- Main ------------------------------------------------------------------------

-- | Read Rex source from stdin, parse to Tree, and pretty-print using
-- the new layout engine. Each top-level input is separated by a blank line.
prettyMain :: IO ()
prettyMain = do
    src <- getContents
    let results = parseRex src
    mapM_ (\(_slice, tree) -> do
        putStrLn (printTree 80 tree)
        putStrLn ""
        ) results
