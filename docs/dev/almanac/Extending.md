[Home](Home.md) › Extending

# Extending the almanac

## Different file locations or collection name

Change `AM_CSV$`, `AM_DIR$` and `AM_COL$` at the top of `almanac.bas`. Using the same `AM_DIR$` as the explorer (`B:/db`) lets the explorer browse and query the almanac collection as well.

## Searching other fields

`AmFind%` reads `detail` only. To search more fields, build the text to search from several of them:

```basic
det$ = LCASE$(DbStr$(r$, "event") + " " + DbStr$(r$, "detail"))
```

Keep the combined length under 255 characters. With the supplied data, `event` and `detail` are each at most 80 characters, so together they fit. Also change the title `"Search almanac (detail)"` and the user guide.

## Filtering by category

The category is in every record (`cat`), so a category search fits the existing search screen. Collect `_id`s with a query instead of the loop:

```basic
IF DbQuery%("SELECT * FROM almanac WHERE cat = 'Moon Phase'") THEN
  FOR i% = 0 TO DbRows%() - 1
    AmHit$(i%) = DbStr$(DbRow$(i%), "_id")
  NEXT
ENDIF
```

For speed with large collections, add an index once after importing: `ok% = DbIndexAdd%("cat")`. Unlike `LIKE`, `=` on text is exact, so the category must match in case.

## More CSV columns

1. In `AmImport%`, add a `CASE` for the column name in the header loop, with a new column variable such as `cX%` (initialised to -1).
2. Add the field when building the record, before the saying, so that the saying stays the field moved to a companion record when space runs out.
3. Show it in `AmBuildDay`.

Remember the 255-character record limit. Longer optional text should use the companion-record pattern (`_id` + a letter), which keeps it next to its record in `_id` order.

## More data than one collection holds

At about 59 rows a month, the default 1,000-record limit holds about 17 months. Options:

- Raise `IX_MAX` (and, if indexes are added, `SX_MAX`) in the library. This costs memory, and suits a Pico 2.
- Use one collection per year, for example `almanac2027`. `AmOpen%` and `AmBuildDay` would then choose the collection from the date. Opening another collection rebuilds its index, so switching should happen only when the date moves into another year.

## A screen of your own

Follow the pattern of the existing screens: a SUB with a `DO` loop that calls `AmTitle`, draws its rows with `AmLine`, calls `AmHints` and then `AmDone`, and waits with `HalKey%()`. Esc should `EXIT SUB`. Call it from the menu, and make sure it cannot lead back into a screen that is already running ([Program structure](Program-Structure.md#flow-between-screens)).

---
Previous: [Screens](Screens.md) · [Home](Home.md)
