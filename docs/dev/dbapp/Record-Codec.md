[Home](Home.md) › Record codec

# Record codec (`dbcore.bas`, `Rc…`)

The codec works on **record strings**: a record is never turned into a data structure, because MMBasic has none. Instead, functions find a field inside the string, or produce a new string with one field changed. Everything above the codec – storage, executor, GUI, API – handles records this way.

## Parsing: one iterator

All reading goes through one function, `RcNext%`, which returns the next field of a record:

```basic
FUNCTION RcNext%(r$, ip%, k$, v$, t%)
  LOCAL i%, e%, c$
  i% = RcSkip%(r$, ip%)
  c$ = MID$(r$, i%, 1)
  IF ip% = 1 THEN
    IF c$ <> "{" THEN RcNext% = -1 : EXIT FUNCTION
  ELSEIF c$ = "}" THEN
    RcNext% = 0 : EXIT FUNCTION
  ELSEIF c$ <> "," THEN
    RcNext% = -1 : EXIT FUNCTION
  ENDIF
  i% = RcSkip%(r$, i% + 1)
  c$ = MID$(r$, i%, 1)
  IF c$ = "}" AND ip% = 1 THEN RcNext% = 0 : EXIT FUNCTION
  IF c$ <> CHR$(34) THEN RcNext% = -1 : EXIT FUNCTION
  RcKS% = i%
  i% = RcStr%(r$, i%, k$)
  IF i% < 0 THEN RcNext% = -1 : EXIT FUNCTION
  i% = RcSkip%(r$, i%)
  IF MID$(r$, i%, 1) <> ":" THEN RcNext% = -1 : EXIT FUNCTION
  i% = RcSkip%(r$, i% + 1)
  RcVS% = i%
  c$ = MID$(r$, i%, 1)
  IF c$ = CHR$(34) THEN
    i% = RcStr%(r$, i%, v$) : t% = 1
  ELSEIF c$ = "{" OR c$ = "[" THEN
    i% = RcNest%(r$, i%) : t% = 3
    IF i% > 0 THEN v$ = MID$(r$, RcVS%, i% - RcVS%)
  ELSE
    e% = i%
    DO WHILE e% <= LEN(r$)
      c$ = MID$(r$, e%, 1)
      IF c$ = "," OR c$ = "}" OR ASC(c$) <= 32 THEN EXIT DO
      INC e%
    LOOP
    IF e% = i% THEN RcNext% = -1 : EXIT FUNCTION
    v$ = MID$(r$, i%, e% - i%) : t% = 2 : i% = e%
  ENDIF
  RcVE% = i%
  RcNext% = i%
END FUNCTION
```

How it works:

- `ip%` is a position in the string. Start with `1`; each call returns the position after the field it read, or `0` at the closing `}`, or `-1` if the record is malformed or cut short.
- The field's name, value and type come back through the by-reference parameters `k$`, `v$`, `t%`. Types: `1` text (already unescaped), `2` literal (number, `true`, `false`, `null`, as written), `3` a nested list or object, returned verbatim.
- As side effects it records where the field is in the string: `RcKS%` (start of the key), `RcVS%` and `RcVE%` (start and end of the value). The editing functions use these to splice.

`RcStr%` decodes a quoted string (`\"`, `\\`, `\n`, `\t`, `\uXXXX`, …), using `INSTR` to jump between quotes and backslashes rather than looping over every character. `RcNest%` skips a nested value by counting brackets, stepping over strings so that a `}` inside text is not miscounted.

The typical loop over all fields:

```basic
ip% = 1
DO
  ip% = RcNext%(r$, ip%, k$, v$, t%)
  IF ip% <= 0 THEN EXIT DO
  ' ... use k$, v$, t% ...
LOOP
IF ip% < 0 THEN ' malformed record
```

Built on it:

- `RcGet$(r$, k$)` returns the value of one field and sets `RcFound%` and `RcT%`.
- `RcCheck%(r$)` returns the number of fields, or `-1` for a malformed line. The scanner uses it to skip damaged lines.

## Editing by splicing

`RcSet$` and `RcDel$` never rebuild a record. They find the field with `RcGet$`, then cut the string at the positions `RcNext%` recorded:

```basic
FUNCTION RcSet$(r$, k$, v$, t%)
  LOCAL ev$, ek$, x$, p%, j%
  x$ = RcGet$(r$, k$)
  IF RcErr$ <> "" THEN EXIT FUNCTION
  IF t% = 1 THEN
    ev$ = RcEnc$(v$)
    IF ev$ = "" THEN EXIT FUNCTION
  ELSE
    IF t% = 2 AND RcLit%(v$) = 0 THEN RcErr$ = "bad literal" : EXIT FUNCTION
    ev$ = v$
  ENDIF
  IF RcFound% THEN
    IF LEN(r$) - (RcVE% - RcVS%) + LEN(ev$) > RC_MAXLEN THEN
      RcErr$ = "too long" : EXIT FUNCTION
    ENDIF
    RcSet$ = LEFT$(r$, RcVS% - 1) + ev$ + MID$(r$, RcVE%)
    EXIT FUNCTION
  ENDIF
  ek$ = RcEnc$(k$)
  IF ek$ = "" THEN EXIT FUNCTION
  p% = LEN(r$)
  DO WHILE p% > 1 AND MID$(r$, p%, 1) <> "}" : INC p%, -1 : LOOP
  j% = p% - 1
  DO WHILE j% > 1 AND ASC(MID$(r$, j%, 1)) <= 32 : INC j%, -1 : LOOP
  IF MID$(r$, j%, 1) <> "{" THEN ek$ = "," + ek$
  IF LEN(r$) + LEN(ek$) + 1 + LEN(ev$) > RC_MAXLEN THEN
    RcErr$ = "too long" : EXIT FUNCTION
  ENDIF
  RcSet$ = LEFT$(r$, j%) + ek$ + ":" + ev$ + MID$(r$, j% + 1)
END FUNCTION
```

- **Replace:** keep everything before the old value, insert the new value, keep everything after it.
- **Add:** insert `,"key":value` before the closing `}` (no comma if the record is `{}`).
- **Remove** (`RcDel$`): cut from the key to the end of the value, plus one neighbouring comma.

Because only the edited field changes, fields the code does not understand – nested values, unusual spacing from another program – survive untouched.

The length is checked arithmetically **before** concatenating. Building a string longer than 255 characters is a run-time error in MMBasic, so the code must never attempt it; `RcSet$` returns `""` with `RcErr$ = "too long"` instead.

## Values

`t%` in `RcSet$` says how to store `v$`:

| `t%` | Stored as | Check |
|---|---|---|
| 1 | Text: quoted and escaped by `RcEnc$` | Result must fit in 255 characters |
| 2 | A literal, unquoted | `RcLit%`: a valid JSON number, `true`, `false` or `null` |
| 3 | Raw JSON, unchanged | None (used for nested values) |

`RcIsNum%` is a small state machine for JSON number syntax (`-`, digits, optional fraction, optional exponent). `RcEnc$` escapes `"`, `\` and control characters.

## Other helpers

| Function | Returns |
|---|---|
| `RcNew$(id$)` | `{"_id":"…"}` |
| `RcIsDel%(r$)` | 1 for a tombstone. A quick `INSTR` for `"_del"` avoids parsing most records |
| `RcSkip%(r$, i%)` | Position of the next non-blank character |

---
Previous: [Data format](Data-Format.md) · Next: [Indexes](Indexes.md)
