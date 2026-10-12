[Home](Home.md) › Screens

# Screens

## Drawing frames

Every screen is redrawn after each key press, so the drawing has to be cheap. Clearing the LCD first would make it flicker. Instead, each row is written exactly once per frame:

```basic
SUB AmTitle t$
  LOCAL r%
  FOR r% = 0 TO HalH% - 1 : AmDrawn%(r%) = 0 : NEXT
  AmLine 0, t$, AS_TITLE
END SUB
```

```basic
SUB AmLine r%, s$, st%
  HalText 0, r%, LEFT$(LEFT$(s$, HalW%) + SPACE$(HalW%), HalW%), st%
  AmDrawn%(r%) = 1
END SUB
```

```basic
SUB AmDone
  LOCAL r%
  IF AmPend$ <> "" THEN AmSay AmPend$, AmPendSt% : AmPend$ = ""
  FOR r% = 1 TO HalH% - 1
    IF AmDrawn%(r%) = 0 THEN AmLine r%, "", AS_N
  NEXT
END SUB
```

- `AmTitle` starts a frame: it marks every row as not yet drawn, then draws the title bar.
- The screen draws the rows it needs with `AmLine`, which pads each to the full width (overwriting whatever was there) and marks it drawn.
- `AmDone`, called just before waiting for a key, blanks every row the frame did not draw.

Rows are never left showing a previous screen, and none is drawn twice. `HalCls` is only used when the program starts and ends.

## Messages

The second-to-last row is the message line (`AmSay`). It has two uses:

- **During work:** progress such as `Read 425 rows …` or `Searching 300 of 885` is drawn immediately with `AmSay`.
- **After an action:** a result or error that should survive the next redraw is passed to `AmNote`. `AmDone` shows it in the next frame and then forgets it, so it stays visible until the user presses a key. (A message drawn just before a screen is redrawn would vanish too quickly to read.)

```basic
SUB AmNote m$, st%
  AmPend$ = m$ : AmPendSt% = st%
END SUB
```

## Prompts

`AmAsk%(q$)` shows a question with `(y/n)` and returns 1 for y or Y. `AmInput$(p$, init$, mx%)` is a minimal line editor on the message line: printable characters are added, Backspace or Delete removes the last character, Enter accepts (`AmOk% = 1`), Esc cancels (`AmOk% = 0`).

## Main menu

`AmMenu` loops: open the collection, draw the menu and the loaded date range, wait for `1`, `2`, `3` or Esc. Browse starts on today if `AmToday%` falls inside the almanac, otherwise on the first day. If no data is loaded, `2` and `3` leave a note instead of opening their screens.

## Maintain

`AmMaintain` shows the CSV's presence, the collection's size and date range, and the metadata from the last import. `C` and `R` both import. When data exists, the user is asked to confirm first:

```basic
k% = 1
IF AmHaveCol%() THEN k% = AmAsk%("Drop and reload all data?")
IF k% THEN
```

This is written as two statements on purpose. `IF AmHaveCol%() = 0 OR AmAsk%(…)` looks equivalent, but MMBasic evaluates both sides of `OR`, so it would ask the question even on a fresh install, and then ignore the answer.

`AmHaveCol%` looks for the collection in `DbList%`. (The API's `DbExists%` is for *records*, not collections.)

## Browse

### Building a day

```basic
SUB AmBuildDay dn%
  LOCAL i%, r$, id$, v$, d$ = AmDate$(dn%)
  AmLN% = 0
  ' a day's records are an _id range ("2026-10-01." ...); DbFind% reads
  ' it from the index without the SQL parser (a much shorter call chain)
  IF DbFind%("_id", "STARTS", d$ + ".") = 0 AND DbErr$() <> "" THEN
    AmAdd "Error: " + DbErr$(), 0, AS_ERR : EXIT SUB
  ENDIF
  FOR i% = 0 TO DbRows%() - 1
    r$ = DbRow$(i%) : id$ = DbStr$(r$, "_id")
    IF RIGHT$(id$, 1) = "L" THEN
      v$ = DbStr$(r$, "lore")
      IF v$ <> "" THEN AmAdd CHR$(34) + v$ + CHR$(34), 2, AS_DIM
    ELSE
      IF AmLN% > 0 THEN AmL$(AmLN%) = "" : AmLs%(AmLN%) = AS_N : INC AmLN%
      v$ = DbStr$(r$, "cat")
      IF v$ = "" THEN v$ = "Event"
      AmAdd v$, 0, AS_HEAD
      AmAdd DbStr$(r$, "event"), 2, AS_N
      v$ = DbStr$(r$, "detail")
      IF v$ <> "" THEN AmAdd v$, 2, AS_N
      v$ = DbStr$(r$, "lore")
      IF v$ <> "" THEN AmAdd CHR$(34) + v$ + CHR$(34), 2, AS_DIM
      v$ = DbStr$(r$, "place")
      IF DbStr$(r$, "cert") <> "" THEN v$ = v$ + " (" + DbStr$(r$, "cert") + ")"
      IF v$ <> "" THEN AmAdd v$, 2, AS_DIM
    ENDIF
  NEXT
  IF AmLN% = 0 THEN AmAdd "Nothing recorded for this day.", 0, AS_DIM
END SUB
```

- One `DbFind%` lookup fetches the day's records, in `_id` order, through the primary index, without the SQL parser.
- Each record becomes a block of wrapped lines in `AmL$()`, each with a style: the category as a heading, the event and detail, the saying in quotes, then place and certainty in grey. Blocks are separated by a blank line.
- A companion record (`_id` ending in `L`) adds only its saying, under the entry it belongs to.

```basic
SUB AmAdd s$, ind%, st%
  LOCAL t$ = s$, w% = HalW% - ind%, b%
  DO WHILE t$ <> "" AND AmLN% < AM_MAXL
    IF LEN(t$) <= w% THEN
      b% = LEN(t$) + 1
    ELSE
      b% = w% + 1
      DO WHILE b% > 1 AND MID$(t$, b%, 1) <> " " : INC b%, -1 : LOOP
      IF b% <= 1 THEN b% = w% + 1
    ENDIF
    AmL$(AmLN%) = SPACE$(ind%) + LEFT$(t$, b% - 1) : AmLs%(AmLN%) = st% : INC AmLN%
    t$ = MID$(t$, b%)
    IF LEFT$(t$, 1) = " " THEN t$ = MID$(t$, 2)
  LOOP
END SUB
```

`AmAdd` word-wraps text to the screen width minus the indent, breaking at the last space that fits, or mid-word if a word is longer than a line. The buffer holds `AM_MAXL` (120) lines, more than any day needs.

### The browse loop

`AmBrowse dn%` keeps two pieces of state: the day `d%` and the scroll position `top%`. Each key computes a new day `nd%`:

| Key | New day |
|---|---|
| Left / Right | `d% - 1` / `d% + 1` |
| `-` `+` (PgUp / PgDn) | `d% - 30` / `d% + 30` |
| Home / End | `AmFirst%` / `AmLast%` |
| `G` | A typed date, validated with `AmDays%` and checked against the range |
| `T` | `AmToday%()`, if it is in range |

`nd%` is then clamped to `AmFirst%`…`AmLast%`. Only if it differs from `d%` is the day rebuilt and the scroll reset. Up and Down change only `top%`. Because days are numbers, crossing a month or year end needs no special code, and a date with no entries simply shows "Nothing recorded for this day."

## Search

```basic
FUNCTION AmFind%(q$)
  LOCAL w$(7), x$, nw%, i%, j%, ok%, r$, det$, n% = DbCount%()
  AmHitN% = 0
  FOR i% = 1 TO 16
    x$ = FIELD$(LCASE$(q$), i%, " ")
    IF x$ <> "" AND nw% < 8 THEN w$(nw%) = x$ : INC nw%
  NEXT
  IF nw% = 0 THEN EXIT FUNCTION
  FOR i% = 0 TO n% - 1
    IF i% MOD 50 = 0 THEN AmSay "Searching " + STR$(i%) + " of " + STR$(n%), AS_MSG
    r$ = DbAt$(i%)
    det$ = LCASE$(DbStr$(r$, "detail"))
    IF det$ <> "" THEN
      ok% = 1
      FOR j% = 0 TO nw% - 1
        IF INSTR(det$, w$(j%)) = 0 THEN ok% = 0 : EXIT FOR
      NEXT
      IF ok% AND AmHitN% < AM_MAXHIT THEN AmHit$(AmHitN%) = DbStr$(r$, "_id") : INC AmHitN%
    ENDIF
  NEXT
  AmSay "", AS_N
  AmFind% = AmHitN%
END FUNCTION
```

- **Words:** the query is lower-cased and split on spaces with `FIELD$` (at most 8 words).
- **Matching:** every record is read in `_id` order. A record matches if its lower-cased `detail` contains every word (`INSTR`). This is done in BASIC rather than with SQL `LIKE`, because `LIKE` is case-sensitive and matches only one pattern.
- **Results:** matching `_id`s go into `AmHit$()`, at most `AM_MAXHIT`. Companion records have no `detail`, so they never match.
- **Progress** is shown every 50 records, since a search reads the whole collection.

`AmSearch` then shows the results as a scrolling, selectable list. Only the visible rows are fetched (with `DbGet$`), so a long result list costs nothing until it is scrolled. Enter calls `AmBrowse` with the selected record's date. When the user leaves the day, the search screen's loop continues with the selection unchanged.

---
Previous: [Dates](Dates.md) · Next: [Extending](Extending.md)
