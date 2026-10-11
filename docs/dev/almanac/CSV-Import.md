[Home](Home.md) › CSV import

# CSV import

`AmImport%(csv$)` replaces the `almanac` collection with the contents of a CSV file. The Maintain screen calls it for both Create and Drop/Recreate: dropping first is part of the import.

## Reading lines safely

```basic
FUNCTION AmReadLine$()
  LOCAL r$ = CHR$(1)
  ON ERROR SKIP 1
  LINE INPUT #AM_FN, r$
  AmLong% = (r$ = CHR$(1))
  IF AmLong% THEN r$ = ""
  AmReadLine$ = r$
END FUNCTION
```

`LINE INPUT` stops the program on a line over 255 characters. `ON ERROR SKIP 1` turns that into a skipped statement, and the sentinel `CHR$(1)` reveals that nothing was read. The import counts such a line as skipped, and also discards the next "line", which is the long line's leftover tail.

## Splitting a line into fields

```basic
FUNCTION AmCsv%(ln$)
  LOCAL i% = 1, j%, n% = LEN(ln$), v$
  AmFN% = 0
  DO
    IF AmFN% > 15 THEN EXIT FUNCTION
    IF MID$(ln$, i%, 1) = CHR$(34) THEN
      v$ = "" : INC i%
      DO
        j% = INSTR(i%, ln$, CHR$(34))
        IF j% = 0 THEN EXIT FUNCTION
        v$ = v$ + MID$(ln$, i%, j% - i%)
        IF MID$(ln$, j% + 1, 1) = CHR$(34) THEN
          v$ = v$ + CHR$(34) : i% = j% + 2
        ELSE
          i% = j% + 1 : EXIT DO
        ENDIF
      LOOP
      AmF$(AmFN%) = v$ : INC AmFN%
      IF i% > n% THEN EXIT DO
      IF MID$(ln$, i%, 1) <> "," THEN EXIT FUNCTION
      INC i%
    ELSE
      j% = INSTR(i%, ln$, ",")
      IF j% = 0 THEN
        AmF$(AmFN%) = MID$(ln$, i%) : INC AmFN% : EXIT DO
      ENDIF
      AmF$(AmFN%) = MID$(ln$, i%, j% - i%) : INC AmFN% : i% = j% + 1
    ENDIF
    IF i% > n% THEN AmF$(AmFN%) = "" : INC AmFN% : EXIT DO
  LOOP
  AmCsv% = 1
END FUNCTION
```

The parser fills `AmF$(0 … AmFN%-1)` and returns 0 for a malformed line:

- **An unquoted field** runs to the next comma, found with `INSTR`.
- **A quoted field** is assembled piece by piece: copy up to the next `"`; if another `"` follows, it was an escaped quote (`""`), so add one `"` and continue; otherwise the field has ended, and must be followed by a comma or the end of the line.
- A comma at the very end of the line produces a final empty field.

Using `INSTR` to jump from comma to comma or quote to quote, instead of examining every character, matters on the Pico: an 854-line file is about 117,000 characters.

## Header

The first line names the columns, and its byte-order mark (`EF BB BF`, which spreadsheets add when saving UTF-8) is removed. The positions of the known column names go into `cD%`, `cE%`, `cT%` (date, event, detail: required), `cC%`, `cL%`, `cP%`, `cK%` (optional; -1 when absent). Columns may therefore be in any order, and unknown columns such as `weekday` are ignored.

## The import loop

```basic
FUNCTION AmImport%(csv$)
  LOCAL ln$, d$, id$, r$, r2$, lore$, h$, i%, n% = 0, done% = 0, nskip% = 0, split% = 0
  LOCAL cD% = -1, cE% = -1, cT% = -1, cC% = -1, cL% = -1, cP% = -1, cK% = -1
  LOCAL seq%, frag% = 0, first$, last$, why$
  AmMsg$ = ""
  IF AmFileExists%(csv$) = 0 THEN AmMsg$ = csv$ + " not found" : EXIT FUNCTION
  OPEN csv$ FOR INPUT AS #AM_FN
  ln$ = AmReadLine$()
  IF LEFT$(ln$, 3) = CHR$(239) + CHR$(187) + CHR$(191) THEN ln$ = MID$(ln$, 4)
  IF AmCsv%(ln$) = 0 THEN CLOSE #AM_FN : AmMsg$ = "bad header line" : EXIT FUNCTION
  FOR i% = 0 TO AmFN% - 1
    h$ = LCASE$(AmF$(i%))
    SELECT CASE h$
      CASE "date" : cD% = i%
      CASE "event" : cE% = i%
      CASE "detail" : cT% = i%
      CASE "category" : cC% = i%
      CASE "saying_or_lore", "lore" : cL% = i%
      CASE "place" : cP% = i%
      CASE "certainty" : cK% = i%
    END SELECT
  NEXT
  IF cD% < 0 OR cE% < 0 OR cT% < 0 THEN
    CLOSE #AM_FN : AmMsg$ = "CSV needs date, event and detail columns" : EXIT FUNCTION
  ENDIF
  IF AmHaveCol%() THEN
    DbClose
    IF DbDrop%(AM_COL$) = 0 THEN CLOSE #AM_FN : AmMsg$ = "drop: " + DbErr$() : EXIT FUNCTION
  ENDIF
  IF DbCreate%(AM_COL$) = 0 THEN CLOSE #AM_FN : AmMsg$ = "create: " + DbErr$() : EXIT FUNCTION
  IF DbOpen%(AM_COL$) = 0 THEN CLOSE #AM_FN : AmMsg$ = "open: " + DbErr$() : EXIT FUNCTION
  DO WHILE NOT EOF(#AM_FN)
    ln$ = AmReadLine$()
    IF AmLong% THEN
      INC n% : INC nskip% : frag% = 1 : why$ = "line too long" : CONTINUE DO
    ENDIF
    IF frag% THEN frag% = 0 : CONTINUE DO
    IF ln$ = "" THEN CONTINUE DO
    INC n%
    IF n% MOD 25 = 0 THEN AmProgress n%, done%, nskip%
    IF AmCsv%(ln$) = 0 THEN INC nskip% : why$ = "unclosed quote" : CONTINUE DO
    IF AmFN% <= MAX(cD%, cE%, cT%) THEN INC nskip% : why$ = "missing columns" : CONTINUE DO
    d$ = AmF$(cD%)
    IF AmDays%(d$) < 0 THEN INC nskip% : why$ = "bad date " + LEFT$(d$, 12) : CONTINUE DO
    seq% = 1
    DO WHILE DbExists%(d$ + "." + STR$(seq%, 2, 0, "0")) AND seq% < 99 : INC seq% : LOOP
    id$ = d$ + "." + STR$(seq%, 2, 0, "0")
    r$ = DbNew$(id$)
    IF cC% >= 0 AND cC% < AmFN% THEN
      IF AmF$(cC%) <> "" THEN r$ = DbWithText$(r$, "cat", AmF$(cC%))
    ENDIF
    r$ = DbWithText$(r$, "event", AmF$(cE%))
    IF r$ <> "" THEN r$ = DbWithText$(r$, "detail", AmF$(cT%))
    IF cP% >= 0 AND cP% < AmFN% AND r$ <> "" THEN
      IF AmF$(cP%) <> "" THEN r$ = DbWithText$(r$, "place", AmF$(cP%))
    ENDIF
    IF cK% >= 0 AND cK% < AmFN% AND r$ <> "" THEN
      IF AmF$(cK%) <> "" THEN r$ = DbWithText$(r$, "cert", AmF$(cK%))
    ENDIF
    IF r$ = "" THEN INC nskip% : why$ = "row too long" : CONTINUE DO
    lore$ = ""
    IF cL% >= 0 AND cL% < AmFN% THEN lore$ = AmF$(cL%)
    r2$ = ""
    IF lore$ <> "" THEN
      r2$ = DbWithText$(r$, "lore", lore$)
      IF r2$ <> "" THEN
        r$ = r2$ : r2$ = ""
      ELSE
        r2$ = DbWithText$(DbNew$(id$ + "L"), "lore", lore$)
      ENDIF
    ENDIF
    IF DbInsert%(r$) = 0 THEN
      why$ = DbErr$() : INC nskip%
      IF why$ = "collection full" THEN EXIT DO
      CONTINUE DO
    ENDIF
    IF r2$ <> "" THEN
      IF DbInsert%(r2$) THEN INC split% ELSE why$ = "saying: " + DbErr$()
    ENDIF
    INC done%
    IF first$ = "" OR d$ < first$ THEN first$ = d$
    IF d$ > last$ THEN last$ = d$
  LOOP
  CLOSE #AM_FN
  i% = DbMetaSet%("source", csv$) + DbMetaSet%("rows", STR$(done%))
  i% = DbMetaSet%("first", first$) + DbMetaSet%("last", last$)
  i% = DbMetaSet%("loaded", DATE$ + " " + LEFT$(TIME$, 5))
  DbFlush
  AmMsg$ = STR$(done%) + " stored, " + STR$(nskip%) + " skipped"
  IF nskip% > 0 THEN AmMsg$ = AmMsg$ + " (last: " + why$ + ")"
  AmImport% = 1
END FUNCTION
```

The order of work:

1. **Check before destroying.** The file must exist and its header must have the required columns *before* the old collection is dropped. A bad file never costs the user their data.
2. **Drop, create, open** the collection.
3. **For each data line:** skip it (counting `nskip%` and remembering the reason in `why$`) if it is too long, unparsable, short of columns, or has an invalid date. Then:
   - find the lowest free sequence number for the date with `DbExists%`, an in-memory index lookup;
   - build the record with `DbNew$` and `DbWithText$`, adding optional fields only when non-empty;
   - try adding the saying. If `DbWithText$` returns `""` (too long), build the companion record instead;
   - insert the record, then the companion. A `collection full` error stops the loop, because every later row would fail the same way.
4. **Record metadata** (`source`, `rows`, `first`, `last`, `loaded`) and `DbFlush`, which saves the index so the next open is fast.

`CONTINUE DO` skips to the next line from deep inside the loop body. It is safe even though the parser it just called left its own loops with `EXIT FUNCTION`, because the firmware discards a routine's loop entries when it returns.

`AmProgress` updates the message line every 25 rows, so the user can see a load of several hundred rows advancing.

## What the user sees

`AmMsg$` summarises the result: `854 stored, 0 skipped`, or for example `4 stored, 3 skipped (last: line too long)`. Only the last reason is kept, which is enough to find the problem in the file. The Maintain screen shows it until the user leaves the screen.

---
Previous: [Data model](Data-Model.md) · Next: [Dates](Dates.md)
