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
    L_PAGE s -> pdocText s
    L_SPAN s -> pdocText s
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
-- Block children force a line break — the rune stays on the head's line,
-- and block items start on the next line indented.
nodeSep :: [Node] -> PDoc
nodeSep []     = PEmpty
nodeSep [n]    = printNode n
nodeSep (n:ns)
    | isBlockNode (head ns) = PCat (printNode n) (nodeSep ns)
    | otherwise             = pdocSpaceOrLine (printNode n) (nodeSep ns)

isBlockNode :: Node -> Bool
isBlockNode (N_CHILD (Tree S_BLOCK _ _ _ _)) = True
isBlockNode _ = False

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
-- Layout strategy:
--   Flat:     RUNE child1 child2 child3
--   Vertical: RUNE child1
--                  child2
--                  child3
--
-- The vertical form uses PDent after RUNE+space so that children on
-- subsequent lines align to the column after the rune and its space.
--
-- A poem is inlineable if all children except possibly the last are closed
-- (not poems/blocks), and the last is either closed or itself inlineable.
-- If inlineable, we offer a PChoice between flat and vertical.

poemDoc :: [Node] -> PDoc
poemDoc [] = PEmpty
poemDoc (N_RUNE runeCol rune : children) =
    let runeDoc  = pdocText rune
        flat     = PCat runeDoc (PCat pdocSpace (poemChildrenFlat children))
        vertical = PCat runeDoc (PCat pdocSpace (PDent (poemChildrenVertical children)))
    in if poemInlineable runeCol children
       then PChoice flat vertical
       else vertical
poemDoc nodes = nodeSep nodes  -- fallback: shouldn't happen in well-formed tree

-- A list of poem children is inlineable if all but the last are closed,
-- and the last is closed or inlineable. Additionally, no child poem can be
-- an heir (same column as the parent rune) — heirs must stay vertically aligned.
poemInlineable :: Int -> [Node] -> Bool
poemInlineable _       []     = True
poemInlineable runeCol [n]    = not (isOpen n) || poemNodeInlineable runeCol n
poemInlineable runeCol (n:ns) = not (isOpen n) && poemInlineable runeCol ns

poemNodeInlineable :: Int -> Node -> Bool
poemNodeInlineable runeCol (N_CHILD (Tree S_POEM pos _ _ (N_RUNE _ _ : children)))
    | pos == runeCol = False  -- heir: same column as parent rune, cannot inline
    | otherwise      = poemInlineable pos children  -- check with child's rune column
poemNodeInlineable _ n = not (isOpen n)

-- Flat rendering: all children space-separated on one line.
poemChildrenFlat :: [Node] -> PDoc
poemChildrenFlat []     = PEmpty
poemChildrenFlat [n]    = printNode n
poemChildrenFlat (n:ns) = PCat (printNode n) (PCat pdocSpace (poemChildrenFlat ns))

-- Vertical rendering: first child on same line as rune, rest on new lines.
-- PDent is set by the caller (poemDoc) so PLine aligns to rune+space column.
--
-- Open children (poems/blocks) use pdocBackstep so that earlier siblings
-- are indented further right than later ones — the "staircase" pattern.
-- This is required because a rune poem's parsing box captures everything
-- indented more than its starting column. If two sibling poems were at
-- the same column, the first would consume the second. Backstep renders
-- later siblings first to determine their indent, then pushes earlier
-- siblings further right.
--
-- Closed children (words, strings, brackets) have no vertical extent
-- and cannot capture siblings, so they just use PLine at the same column.
poemChildrenVertical :: [Node] -> PDoc
poemChildrenVertical []     = PEmpty
poemChildrenVertical [n]    = printNode n
poemChildrenVertical (n:ns)
    | isOpen n  = pdocBackstep (printNode n) (poemOpenRest ns)
    | otherwise = PCat (printNode n) (PCat PLine (poemChildrenVertical ns))

-- Continuation after an open sibling. Every child here needs PLine before
-- it (to separate from the preceding open sibling's multi-line content).
-- Open children still use backstep for the staircase; closed ones just
-- get PLine.
poemOpenRest :: [Node] -> PDoc
poemOpenRest []     = PEmpty
poemOpenRest [n]    = PCat PLine (printNode n)
poemOpenRest (n:ns)
    | isOpen n  = pdocBackstep (printNode n) (poemOpenRest ns)
    | otherwise = PCat PLine (PCat (printNode n) (poemOpenRest ns))

-- An "open" node is one that may expand vertically (poem or block).
isOpen :: Node -> Bool
isOpen (N_CHILD (Tree S_POEM  _ _ _ _)) = True
isOpen (N_CHILD (Tree S_BLOCK _ _ _ _)) = True
isOpen _                                = False


-- Block -----------------------------------------------------------------------
--
-- A block contains items. The block always starts on a new line, with
-- items indented relative to the enclosing context. The rune that opens
-- the block stays on the head's line; blockDoc handles only the items.
--
-- Layout: newline, 4-space indent, then items separated by newlines.
-- PDent captures the column after the indent spaces, so subsequent
-- PLines within items align correctly.

blockDoc :: [Node] -> PDoc
blockDoc []     = PEmpty
blockDoc nodes  = PCat PLine (PCat (pdocText "    ") (PDent (blockItems nodes)))

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
