# Trailing Rune Dropped in Debug Output

## Issue
In the debug test "trailing rune after slot", the trailing `+` rune appears to be dropped:

```
Input:  (a b , 4 +)
Output: («a b» , «4»)
```

The expected semantic would be `4 +` as a trailing rune expression, but it's being printed as just `«4»`.

## Location
- Test file: `src/hs/ex/print-rex/debug.tests`
- Test name: "trailing rune after slot"

## Notes
This may be an issue in the Rex IR construction (rexFromBlockTree) rather than the printer.
The trailing rune might not be captured properly in the Rex representation.

## To Investigate
1. Check what Rex structure is actually produced for `(a b , 4 +)`
2. Verify if NEST with trailing rune is being constructed correctly
3. Compare with Test.hs expected output which showed `NEST ns CLEAR "+" [lf "4"]`
