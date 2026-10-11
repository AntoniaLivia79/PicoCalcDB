[Home](Home.md) › Executor

# Executor (`dbexec.bas`, `Ex…`)

`ExRun%(q$)` parses a statement with `QParse%`, then carries out the plan against the collection it names. It is the single entry point used by both the explorer's SQL command line and the library's `DbQuery%`.

## Results

| `ExKind$` | Produced by | Read |
|---|---|---|
| `ROWS` | SELECT | `ExR%(0 … ExN%-1)`: **file offsets** of the matching records |
| `COUNT` | SELECT COUNT(*) | `ExCnt%` |
| `TEXT` | SHOW, DESCRIBE, EXPLAIN | `ExOut$(0 … ExOutN%-1)`, written with `ExSay` |
| `OK` | writes and admin commands | `ExMsg$`, such as `3 updated` |

`ExErr$` holds the error, `ExMsg$` a one-line summary, `ExWarn$` any warning from opening the collection.

Rows are offsets rather than copies of records: 1,000 records would not fit in memory as strings, while 1,000 offsets take 8 KB. Because the data file is append-only, an offset keeps pointing at the same line even after the record is changed. A result list is therefore a stable snapshot, and the caller reads each row with `StRead$(ExR%(i))`.

## Dispatch

`ExRun%` resets the result variables, calls `QParse%`, then:

- SELECT, UPDATE and DELETE open the collection (`ExUse%`, which does nothing if it is already open), choose an access path (`ExPlanPath`), then run `ExExplain`, `ExSelect` or `ExModify`.
- INSERT goes to `ExInsert`, which builds the record from `QFld$()`/`QVal$()` and writes it with `StWrite%` in insert mode. A missing `_id` gets `StNewId$()`.
- Admin statements call the matching storage function (`StCreate%`, `StIndexAdd%`, `StVacuum%` …), `ExDescribe` or `StList%`.

## Choosing an access path

```basic
SUB ExPlanPath
  LOCAL k%, s%, op%, lo%, hi%, ok%, v$, t%
  ExSrc% = 0 : ExLo% = 0 : ExHi% = IxN% : ExPath$ = "full scan"
  FOR k% = 0 TO QNN% - 1
    op% = QnOp%(k%) : v$ = QnV$(k%) : t% = QnT%(k%) : ok% = 0
    IF QnTop%(k%) AND op% <= QO_LIKE AND op% <> QO_NE THEN
      IF op% = QO_LIKE THEN v$ = ExPrefix$(v$)
      IF QnF$(k%) = "_id" THEN
        IF op% = QO_LIKE AND v$ <> "" THEN
          lo% = IxBound%(IxK$(), IxN%, v$, 0)
          hi% = IxBound%(IxK$(), IxN%, v$ + STRING$(IX_KLEN, 255), 1)
          ok% = 1
        ELSEIF op% <> QO_LIKE AND t% = 1 THEN
          IxRange QOpName$(op%), v$, lo%, hi% : ok% = (lo% >= 0)
        ENDIF
        IF ok% AND hi% - lo% < ExHi% - ExLo% + (ExSrc% = 0) THEN
          ExSrc% = 1 : ExLo% = lo% : ExHi% = hi% : ExPath$ = "_id range"
        ENDIF
      ELSE
        s% = SxSlot%(QnF$(k%))
        IF s% >= 0 THEN
          IF op% = QO_LIKE THEN
            IF v$ <> "" THEN SxRange s%, "LIKE", v$, 1, lo%, hi% : ok% = 1
          ELSEIF t% = 1 OR RcIsNum%(v$) OR op% = QO_EQ THEN
            SxRange s%, QOpName$(op%), v$, t%, lo%, hi% : ok% = (lo% >= 0)
          ENDIF
          IF ok% AND hi% - lo% < ExHi% - ExLo% + (ExSrc% = 0) THEN
            ExSrc% = 2 : ExLo% = lo% : ExHi% = hi% : ExPath$ = "index on " + QnF$(k%)
          ENDIF
        ENDIF
      ENDIF
    ENDIF
  NEXT
END SUB
```

The executor never trusts an index to give the answer, only to narrow the search. `ExPlanPath` looks at every leaf with `QnTop% = 1` (see [Query parser](Query-Parser.md#index-eligible-terms-qntop)) and computes the range of index rows that could match it:

- **`_id` conditions** use the primary index: an exact range for `=`, `<`, `<=`, `>`, `>=`, or the prefix range for `LIKE 'abc%'`.
- **Conditions on an indexed field** use `SxRange`: text values, numbers, `=` with `true`/`false`/`null`, or a `LIKE` with a literal prefix.
- `<>` and conditions under `OR` or `NOT` are never used.

The narrowest range wins. Any index range beats a full scan, which is the default: `ExSrc% = 0` with the range `0 … IxN%` of the primary index. The result is three numbers: `ExSrc%` (0 full scan, 1 `_id` range, 2 secondary range), `ExLo%` and `ExHi%`.

## Collecting matches

```basic
SUB ExCollect lim%
  LOCAL i%, off%
  ExN% = 0
  IF lim% = 0 THEN EXIT SUB
  FOR i% = ExLo% TO ExHi% - 1
    IF ExSrc% = 2 THEN off% = SxO%(i%) ELSE off% = IxO%(i%)
    IF ExMatch%(StRead$(off%)) THEN
      ExR%(ExN%) = off% : INC ExN%
      IF lim% > 0 AND ExN% >= lim% THEN EXIT SUB
    ENDIF
  NEXT
END SUB
```

Every candidate record in the chosen range is read and tested against the **whole** WHERE clause with `ExMatch%`. This one step makes lossy secondary keys safe, and applies all the other conditions. `lim%` lets a query stop early: without ORDER BY, `LIMIT 10 OFFSET 20` needs only the first 30 matches.

### Evaluating RPN

```basic
FUNCTION ExMatch%(rec$)
  LOCAL k%, sp% = 0
  IF QNN% = 0 THEN ExMatch% = 1 : EXIT FUNCTION
  FOR k% = 0 TO QNN% - 1
    SELECT CASE QnOp%(k%)
      CASE QO_AND : INC sp%, -1 : ExSt%(sp% - 1) = ExSt%(sp% - 1) AND ExSt%(sp%)
      CASE QO_OR  : INC sp%, -1 : ExSt%(sp% - 1) = ExSt%(sp% - 1) OR ExSt%(sp%)
      CASE QO_NOT : ExSt%(sp% - 1) = 1 - ExSt%(sp% - 1)
      CASE ELSE   : ExSt%(sp%) = ExLeaf%(rec$, k%) : INC sp%
    END SELECT
  NEXT
  ExMatch% = ExSt%(0)
END FUNCTION
```

A leaf pushes its result (0 or 1) onto `ExSt%()`; `AND`/`OR` pop two and push one; `NOT` flips the top. Because the parser produced valid postfix, the final result is `ExSt%(0)`. The stack is a global array (`QN_MAX` deep), so no memory is allocated per record.

### Comparing values

```basic
FUNCTION ExLeaf%(rec$, k%)
  LOCAL x$, v$ = QnV$(k%), op% = QnOp%(k%), t%, c% = 2, nx%, nv%
  x$ = RcGet$(rec$, QnF$(k%)) : t% = RcT%
  IF op% = QO_NULL OR op% = QO_NNULL THEN
    c% = (RcFound% = 0) OR (t% = 2 AND x$ = "null")
    IF op% = QO_NULL THEN ExLeaf% = c% ELSE ExLeaf% = 1 - c%
    EXIT FUNCTION
  ENDIF
  IF RcFound% = 0 THEN EXIT FUNCTION
  IF op% = QO_LIKE THEN
    IF t% = 1 THEN ExLeaf% = ExLike%(x$, v$)
    EXIT FUNCTION
  ENDIF
  IF t% = 2 AND QnT%(k%) = 2 THEN
    nx% = RcIsNum%(x$) : nv% = RcIsNum%(v$)
    IF nx% AND nv% THEN
      c% = SGN(VAL(x$) - VAL(v$))
    ELSEIF nx% = 0 AND nv% = 0 THEN
      c% = (x$ > v$) - (x$ < v$)
    ENDIF
  ELSEIF t% = 1 AND QnT%(k%) = 1 THEN
    c% = (x$ > v$) - (x$ < v$)
  ENDIF
  SELECT CASE op%
    CASE QO_EQ : ExLeaf% = (c% = 0)
    CASE QO_NE : ExLeaf% = (c% <> 0)
    CASE QO_LT : ExLeaf% = (c% = -1)
    CASE QO_LE : ExLeaf% = (c% = -1 OR c% = 0)
    CASE QO_GT : ExLeaf% = (c% = 1)
    CASE QO_GE : ExLeaf% = (c% = 1 OR c% = 0)
  END SELECT
END FUNCTION
```

The comparison rules are deliberately simple and SQL-like:

- **A missing field fails every comparison**, including `<>`. Only `IS NULL` (missing or `null`) and `IS NOT NULL` look at absence.
- `c%` is the comparison result: -1, 0 or 1, or **2 for "not comparable"**. Two numbers compare numerically (`VAL`), two texts by character code, and two non-numeric literals (`true`, `null`) as text. Mixed types stay at 2, so they are never `=`, `<` or `>`, but are `<>`.
- `(x$ > v$) - (x$ < v$)` turns two MMBasic comparisons (each 1 or 0) into -1, 0 or 1 without an IF.

### LIKE

```basic
FUNCTION ExLike%(s$, p$)
  LOCAL i% = 1, j% = 1, si% = 0, sj% = 0, ls% = LEN(s$), lp% = LEN(p$), c$
  DO WHILE i% <= ls%
    c$ = MID$(p$, j%, 1)
    IF j% <= lp% AND c$ <> "%" AND (c$ = "_" OR c$ = MID$(s$, i%, 1)) THEN
      INC i% : INC j%
    ELSEIF j% <= lp% AND c$ = "%" THEN
      sj% = j% : si% = i% : INC j%
    ELSEIF sj% > 0 THEN
      INC si% : i% = si% : j% = sj% + 1
    ELSE
      EXIT FUNCTION
    ENDIF
  LOOP
  DO WHILE j% <= lp%
    IF MID$(p$, j%, 1) <> "%" THEN EXIT FUNCTION
    INC j%
  LOOP
  ExLike% = 1
END FUNCTION
```

This is the standard two-pointer wildcard algorithm. On a `%` it remembers where it was (`si%`, `sj%`). When a later character fails, it backtracks to just after that `%` and lets it absorb one more character. It runs in a single loop with no recursion. Matching is case-sensitive, which keeps it consistent with the byte-ordered indexes used for `LIKE 'abc%'`.

## Sorting

`ORDER BY _id` on a primary-index path needs no sorting: rows are already in `_id` order, and DESC just reverses them (`ExReverse`). Otherwise `ExSort` builds a sort key for every matching row and uses the built-in `SORT` with an index array:

```basic
FUNCTION ExSortKey$(rec$, f$)
  LOCAL x$ = RcGet$(rec$, f$), e!, ip%, fr%
  IF RcFound% = 0 OR (RcT% = 2 AND x$ = "null") THEN ExSortKey$ = "3" : EXIT FUNCTION
  IF RcT% = 2 AND RcIsNum%(x$) THEN
    e! = VAL(x$)
    IF e! > 4.9E10 THEN e! = 4.9E10
    IF e! < -4.9E10 THEN e! = -4.9E10
    e! = e! + 5E10 : ip% = INT(e!) : fr% = INT((e! - ip%) * 10000)
    ExSortKey$ = "1" + RIGHT$("0000000000" + STR$(ip%), 11) + RIGHT$("000" + STR$(fr%), 4)
  ELSE
    ExSortKey$ = "2" + LEFT$(x$, 15)
  ENDIF
END FUNCTION
```

The first character groups values (`1` numbers, `2` text and other literals, `3` missing or `null`), so numbers sort before text and missing values last. Numbers are offset and zero-padded (11 integer and 4 fraction digits) so that string order equals numeric order. `SORT k$(), ix%(), QDesc%` reverses everything for DESC, which is why missing values come *first* in descending order. The key arrays are `LOCAL`, sized to the number of rows, and freed on return.

`ExSlice` then applies OFFSET and LIMIT by shifting the row list.

## UPDATE and DELETE

```basic
SUB ExModify
  LOCAL i%, j%, n% = 0, r$, id$
  ExCollect -1
  FOR i% = 0 TO ExN% - 1
    r$ = StRead$(ExR%(i%))
    id$ = RcGet$(r$, "_id")
    IF QCmd$ = "DELETE" THEN
      IF StDelete%(id$) = 0 THEN EXIT FOR
    ELSE
      FOR j% = 0 TO QFN% - 1
        IF r$ <> "" THEN
          IF QVT%(j%) = 0 THEN r$ = RcDel$(r$, QFld$(j%)) ELSE r$ = RcSet$(r$, QFld$(j%), QVal$(j%), QVT%(j%))
        ENDIF
      NEXT
      IF r$ = "" THEN StErr$ = id$ + ": record " + RcErr$ : EXIT FOR
      IF StWrite%(r$, 2) = 0 THEN EXIT FOR
    ENDIF
    INC n%
  NEXT
  IF n% < ExN% THEN ExErr$ = STR$(n%) + " of " + STR$(ExN%) + " done; " + StErr$
  IF QCmd$ = "DELETE" THEN ExMsg$ = STR$(n%) + " deleted" ELSE ExMsg$ = STR$(n%) + " updated"
  ExN% = 0
END SUB
```

All matches are collected **before** anything is written, and the stored offsets are used afterwards. Changing a record appends a new line and changes the index, but the old offsets still point at the versions that matched. So a statement whose SET changes the field its WHERE tests, such as `UPDATE c SET age = 40 WHERE age < 40`, can never see its own changes, and no record is skipped or changed twice. Each record's SET/UNSET changes are applied with `RcSet$`/`RcDel$` in field order, then written with `StWrite%` in update mode. If one write fails, the loop stops and the message says how many records were changed.

## EXPLAIN and DESCRIBE

`ExExplain` reports the access path chosen and the number of candidate rows, then lists the RPN nodes with `QNodeTxt$` (index-eligible leaves marked `^`). `ExDescribe` formats the storage engine's metadata: record count, dead lines, indexes, and each field with its kind.

---
Previous: [Query parser](Query-Parser.md) · Next: [Explorer GUI](Explorer-GUI.md)
