# Extract String Processing Module

## Issue
String stripping and unescaping logic is currently embedded in `Rex.Rex` (in `rexFromBlockTree` and related functions). This should be factored out into a dedicated module.

## Current Location
- `src/hs/Rex/Rex.hs` - contains `extractCord`, `extractTape`, `extractSpan`, `extractPage`, `extractSlug`, and escape handling logic

## Proposed Module
`Rex.String` or `Rex.Leaf` - dedicated module for:
- String content extraction (strip delimiters, handle escapes)
- Quote escaping/unescaping
- Multiline string normalization (indent stripping for SPAN/PAGE)
- Validation of string literals

## Benefits
- Single responsibility: Rex.hs focuses on tree structure, not string parsing details
- Easier to test string extraction in isolation
- Clearer separation of concerns
