{-# LANGUAGE LambdaCase #-}

module Rex.Error
    ( BadReason(..)
    , RexError(..)
    , collectErrors
    , formatError
    , formatErrors
    , hasErrors
    ) where

import Rex.Lex (Span(..))

-- | Reasons why a token or node is marked BAD
data BadReason
    = InvalidChar          -- ^ Unrecognized character in input
    | UnclosedTrad         -- ^ TRAD string ("...") not closed before EOF
    | UnclosedUgly         -- ^ UGLY string ('''...''') not closed before EOF
    | MismatchedBracket    -- ^ Closing bracket doesn't match opening
    | InvalidPage          -- ^ PAGE string has invalid indentation
    | InvalidSpan          -- ^ SPAN string has invalid indentation on continuation line
    deriving (Eq, Show)

-- | A located error with span, reason, and offending text
data RexError = RexError
    { errSpan   :: !Span
    , errReason :: !BadReason
    , errText   :: !String
    } deriving (Eq, Show)

-- | Human-readable description of error reason
reasonMessage :: BadReason -> String
reasonMessage = \case
    InvalidChar       -> "invalid character"
    UnclosedTrad      -> "unclosed string literal"
    UnclosedUgly      -> "unclosed multi-line string"
    MismatchedBracket -> "mismatched bracket"
    InvalidPage       -> "invalid page string indentation"
    InvalidSpan       -> "invalid span string indentation"

-- | Format a single error for display
formatError :: Maybe String -> RexError -> String
formatError mSrc (RexError sp reason txt) =
    let loc = show (spanLin sp) ++ ":" ++ show (spanCol sp)
        msg = reasonMessage reason
        preview = case mSrc of
            Nothing  -> show txt
            Just src -> showContext src sp
    in loc ++ ": error: " ++ msg ++ "\n" ++ preview

-- | Show context around error location
showContext :: String -> Span -> String
showContext src sp =
    let srcLines = lines src
        lineNum = spanLin sp
        colNum = spanCol sp
    in if lineNum > 0 && lineNum <= length srcLines
       then let line = srcLines !! (lineNum - 1)
                pointer = replicate (colNum - 1) ' ' ++ "^"
            in "  " ++ line ++ "\n  " ++ pointer
       else ""

-- | Format multiple errors
formatErrors :: Maybe String -> [RexError] -> String
formatErrors mSrc errs = unlines (map (formatError mSrc) errs)

-- | Check if there are any errors
hasErrors :: [RexError] -> Bool
hasErrors = not . null

-- | Collect all errors from a Rex tree
-- This is a placeholder that will be filled in once Rex imports this module
collectErrors :: a -> [RexError]
collectErrors _ = []
