[Home](Home.md) › MMBasic notes

# MMBasic notes

PicoMite MMBasic behaves differently from other BASICs in ways that shaped this code. Each point below was met while writing or testing it. Keep them in mind when changing anything.

## Strings

- **255 characters maximum.** This is why a record is at most 255 characters. Building a longer string is a run-time error, so code that concatenates data checks the length first (`RcSet$`, `RcEnc$`, `ExRowText$`).
- **Declare string arrays with `LENGTH`.** Otherwise every element reserves 256 bytes. The indexes use `LENGTH IX_KLEN` and `LENGTH SX_PW + 2`.
- **No escape for `"` inside a literal.** `""` does not work; the code uses `CHR$(34)`.
- **`STR$` adds no leading space** (unlike `PRINT`): `"rows:" + STR$(5)` gives `rows:5`. `STR$(n%, 6, 0, "0")` pads with zeros (`000012`), which is how automatic ids and sort keys are built. A float gives about 10 significant digits; see `DbNumStr$`.
- **Comparison operators return 1 or 0**, so they can be used as numbers: `c% = (x$ > v$) - (x$ < v$)` in `ExLeaf%`.

## Conditions

- **`AND` and `OR` have the same precedence**, evaluated left to right: `1 OR 1 AND 0` is 0. Every mixed condition in the code is bracketed.
- **No short-circuit evaluation.** Both sides of `AND`/`OR` are always evaluated. This matters in two ways:
  - `IF i% < n% AND a$(i%) = k$` fails with an index error when `i% = n%`. The code nests the IFs instead (see `IxGet%`).
  - `IF AmHaveCol%() = 0 OR AmAsk%("Drop?")` asks the question even when the first part is already true. A function with a side effect must be called in its own IF.
- **A one-line `IF … THEN a : b ELSE c` is not accepted.** Use a block `IF … ELSE … ENDIF`. One-line IFs without ELSE, or with single statements, are fine.

## Names

- **One namespace for routines and variables, ignoring the type suffix.** A SUB `Rec` clashes with any `rec$` or `rec%`, global or LOCAL, and the error appears only when the clashing routine runs. Within the code base, routine names use module prefixes and never match a local. The library renames its locals to `z_…` ([Library and API](Library-and-API.md#why-the-library-renames-its-local-variables)).
- **Reserved words** include `RUN`, `PLAY`, `TEXT`, `LINE`, `SET`, `VAR`, `DRIVE`, `SEEK` and `MAP` as commands. Functions such as `POS` and `FIELD$` are recognised anywhere in an expression. Prefixed names avoid all of them.
- **A FUNCTION with no parameters must be declared and called with `()`**, as in `StList%()`. Without them, MMBasic treats the name as a variable.

## Parameters

- **Variables are passed by reference.** A FUNCTION that assigns to a parameter changes the caller's variable. The code uses this deliberately for extra results (`RcNext%` fills `k$`, `v$`, `t%`; `UiType%` may strip quotes from `v$`). Elsewhere it copies a parameter to a LOCAL before changing it (`RcSkip%`). An expression argument (`RcSkip%(r$, i% + 1)`) is passed by value.
- **Arrays can be passed to FUNCTIONs** (`IxBound%(a$(), …)`), which is how one binary search serves every index.

## Loops and recursion

- **A running `DO` loop is identified by its position in the program.** If a routine containing a `DO` loop is re-entered by recursion while its loop is running, the inner loop's exit breaks the outer one ("LOOP without a matching DO"). The recursive parser functions therefore contain no loops; they use tail recursion (`QOrRest%`, `QAndRest%`).
- **Leaving a loop with `EXIT FUNCTION` or `EXIT SUB` is safe.** When a routine returns, the firmware removes that routine's FOR and DO entries (`ClearVars` in `MMBasic.c`). `CONTINUE DO` continues the innermost running loop.

## Files

- **`LINE INPUT` expands tabs to spaces.** The saved index uses commas, not tabs.
- **`LINE INPUT` stops the program on a line over 255 characters** ("Line is too long"), after consuming 256 characters of it. The code traps this with `ON ERROR SKIP 1` and a sentinel value (`IxLine$`, `AmReadLine$`). The next `LINE INPUT` returns the rest of the long line, which is discarded too.
- **`DIR$(path$, FILE)` raises an error if a folder in the path does not exist**, instead of returning `""`. Existence tests that may meet a missing folder use `ON ERROR SKIP 1` with a sentinel (`HpFind%`, `AmFileExists%`). A sentinel is more reliable than checking `MM.ERRNO`, which can keep an old value.
- **`LOC(#n)` and `SEEK #n` count from 1** and refer to the same positions. `LOC` is correct in INPUT mode too (the firmware accounts for its read buffer), so the offset of a line is `LOC` taken just before reading it.
- **Program lines are limited to 255 characters**, so long string constants are built over several lines (`QRES$`).

## Sorting

`SORT a$(), ix%(), flags, start, count` sorts part of an array and fills `ix%()` with the original positions, so parallel arrays can be rearranged to match (`IxCompact`, `SxRebuild%`, `ExSort`). Flag 1 reverses the order. Strings sort by character code, the same order as `<` and `>`, which is what keeps binary search and `SORT` consistent.

---
Previous: [Library and API](Library-and-API.md) · Next: [Extending](Extending.md)
