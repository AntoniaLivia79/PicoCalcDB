[Home](Home.md) › Library and API

# Library and API (`dbapi.bas`, `dblib.bas`)

The library lets any PicoMite program use PicoCalc DB collections. It is the same engine as the explorer – `dbcore`, `dbstore`, `dbquery`, `dbexec` – plus `dbapi.bas`, a thin layer of `Db…` routines that gives programs a stable, documented interface. The almanac is built on it. The [library reference](../../user/library-reference.md) is the user-facing reference; this page explains how it works.

## Composition

```
dblib.bas = dbcore.bas + dbstore.bas + dbquery.bas + dbexec.bas + dbapi.bas
```

The library contains no `OPTION` statements and no main program. Only `CONST`/`DIM` lines run at top level, followed by SUBs and FUNCTIONs. A program uses it in one of two ways:

- **`#INCLUDE "dblib.bas"`** in the program. The firmware inserts the file when the program is loaded, so the result is one program, as with the explorer.
- **`LIBRARY SAVE`** keeps the library in flash. When any program runs, the firmware first executes the library's top-level code (in `Commands.c`: "run anything that might be in the library"), which dimensions the engine's arrays, then the program. This is why the library must not contain an `END`: it would stop before the program started.

## Design of the API layer

`dbapi.bas` adds almost no logic of its own. Each routine:

1. calls the engine routine that does the work;
2. records the outcome in one place, `DbE$`, read by `DbErr$()`;
3. returns 1/0, or a string.

```basic
FUNCTION DbOk%(ok%, e$)
  IF ok% THEN DbE$ = "" ELSE DbE$ = e$
  DbOk% = (ok% <> 0)
END FUNCTION
```

```basic
FUNCTION DbInsert%(rec$)
  DbInsert% = DbOk%(StWrite%(rec$, 1), StErr$)
END FUNCTION
```

So a program only ever has to check one error source, whichever layer failed. Some API routines exist mainly to give a clear name to a codec function (`DbWithText$` is `RcSet$` with type 1) or to hide an internal array (`DbListName$` reads `StCat$()`).

A few routines add behaviour:

```basic
FUNCTION DbOpen%(c$)
  IF StCol$ = c$ AND c$ <> "" THEN DbOpen% = DbOk%(1, "") : EXIT FUNCTION
  DbOpen% = DbOk%(StOpen%(c$), StErr$)
END FUNCTION
```

`DbOpen%` returns at once if the collection is already open, so programs can call it freely before each use.

```basic
FUNCTION DbNumStr$(n!)
  LOCAL i%
  DbNumStr$ = STR$(n!)
  IF n! < 1E15 AND n! > -1E15 THEN
    IF n! = INT(n!) THEN i% = n! : DbNumStr$ = STR$(i%)
  ENDIF
END FUNCTION
```

`STR$` on a float gives about 10 significant digits (`1.234567891e+08`), so whole numbers are converted through an integer and keep every digit. The exponent forms `STR$` produces (`1e+20`, `1.5e-07`) are valid JSON numbers.

### Program-defined metadata

`DbMetaSet%`/`DbMetaGet$` store properties in the collection's `.meta` file, using the storage engine's `MtUser$`. That variable is itself a record string (`{"_id":"@user","title":"…"}`), so the API manipulates it with the codec, and `MtSave` writes it as one more line:

```basic
FUNCTION DbMetaSet%(k$, v$)
  LOCAL r$
  IF StCol$ = "" THEN DbMetaSet% = DbOk%(0, "no collection open") : EXIT FUNCTION
  IF LEFT$(k$, 1) = "_" OR k$ = "" THEN DbMetaSet% = DbOk%(0, "bad property name") : EXIT FUNCTION
  r$ = RcSet$(MtUser$, k$, v$, 1)
  IF r$ = "" THEN DbMetaSet% = DbOk%(0, RcErr$) : EXIT FUNCTION
  MtUser$ = r$ : MtDirty% = 1
  DbMetaSet% = DbOk%(1, "")
END FUNCTION
```

All properties share one line, so together they are limited to the 255-character record size.

### Query results

`DbQuery%` is `ExRun%`. `DbRows%`/`DbRow$` read the executor's `ExN%`/`ExR%()`, `DbResult%` reads `ExCnt%`, and `DbLines%`/`DbLine$` read `ExOut$()`. The offset-based design described in [Executor](Executor.md#results) is what makes it safe to loop over `DbRow$(i%)` and update or delete those same records. The rows remain readable until the next `DbQuery%` or a vacuum, and each one shows the record as it was when the query ran.

## Finding records without SQL

Most lookups in a program are a single condition: the items in a room, the entries for a day, the record with this name. `DbFind%` does these without the SQL parser:

```basic
FUNCTION DbFind%(f$, op$, v$)
  LOCAL opc%, t% = DbFT%
  DbFT% = 1 : DbE$ = "" : ExN% = 0
  IF StCol$ = "" THEN DbE$ = "no collection open" : EXIT FUNCTION
  SELECT CASE op$
    CASE "=" : opc% = QO_EQ
    CASE "<>" : opc% = QO_NE
    CASE "<" : opc% = QO_LT
    CASE "<=" : opc% = QO_LE
    CASE ">" : opc% = QO_GT
    CASE ">=" : opc% = QO_GE
    CASE "STARTS" : opc% = QO_LIKE
    CASE ELSE : DbE$ = "bad operator " + op$ : EXIT FUNCTION
  END SELECT
  IF opc% = QO_LIKE AND t% <> 1 THEN DbE$ = "STARTS needs text" : EXIT FUNCTION
  IF LEN(f$) = 0 OR LEN(f$) > 24 OR LEN(v$) > QNV_LEN - 1 THEN DbE$ = "field or value too long" : EXIT FUNCTION
  ' a one-condition plan, as the parser would have made it
  QCmd$ = "SELECT" : QAgg% = 0 : QFN% = 0 : QOrd$ = "" : QLim% = -1 : QOff% = 0
  QNN% = 1 : QnOp%(0) = opc% : QnF$(0) = f$ : QnV$(0) = v$ : QnT%(0) = t% : QnTop%(0) = 1
  IF opc% = QO_LIKE THEN QnV$(0) = v$ + "%"
  ExKind$ = "ROWS"
  ExPlanPath
  ExCollect -1
  DbFind% = ExN%
END FUNCTION
```

It fills in the same plan variables the parser would produce for `SELECT * FROM c WHERE f op v`: one leaf node, flagged as index-eligible. Then it calls the executor's own `ExPlanPath` and `ExCollect`. So the results, the comparison rules and the use of indexes are exactly those of the equivalent SQL, and rows are read back with `DbRows%()`/`DbRow$()` as usual. `STARTS` becomes `LIKE` with a `%` added, so it uses the `_id` or secondary index prefix range. A `%` or `_` inside the value would act as a wildcard.

The value is text unless `DbFindNum%` is used. That sets `DbFT%` to 2 and passes the number as text, so the comparison is numeric.

Skipping the parser makes `DbFind%` cheaper in time and, more importantly on a PicoMite, in stack: at most 5 nested calls instead of 8 ([MMBasic notes](MMBasic-Notes.md#the-call-stack-is-small)). The almanac and the adventure framework use it for all their lookups.

## Why the library renames its local variables

MMBasic gives SUB and FUNCTION names and local variable names one shared namespace. If a program has `SUB Rec` and any routine anywhere declares `LOCAL rec$`, the program stops with "A function/subroutine has the same name: REC". It does so only when that routine runs, which may be long after start-up. The engine has dozens of short local names (`rec$`, `id$`, `ok%`, `old$`, `lo%` …), each of which would be a trap for a program using the library.

So in the generated `dblib.bas`, every local variable and parameter of every SUB and FUNCTION is renamed with a `z_` prefix:

```basic
FUNCTION RcGet$(z_r$, z_k$)
  LOCAL z_ip% = 1, z_fk$, z_fv$, z_ft%
```

The renaming is per routine and whole-identifier only: text inside strings, numeric literals such as `4.9E10`, and global names are left alone. The module sources keep their readable names; only the merged library is transformed. User programs' global variables and constants do not need protecting, because a `LOCAL` simply shadows a global of the same name.

## API reference

Generated from the routines and comments in `dbapi.bas`, grouped as in the source. Internal helpers (`DbOk%`, `DbNth%`) are included for completeness.

| `DbErr$()` | Reason the last call failed, or "" after a success |
| `DbOk%(ok%, e$)` | Internal: record the outcome of a call (ok% 1/0, error text) |

### Setup and collections

| Routine | Description |
|---|---|
| `DbInit d$` | *(SUB)* Use folder d$ for all collections (created if missing) |
| `DbCreate%(c$)` | Create an empty collection (letters, digits, _; up to 16 characters) |
| `DbDrop%(c$)` | Drop a collection and all its files |
| `DbOpen%(c$)` | Open collection c$ (closes the one open before). One open at a time. |
| `DbClose` | *(SUB)* Save the index and metadata and close. Call before your program ends. |
| `DbFlush` | *(SUB)* Save the index and metadata without closing |
| `DbCurrent$()` | Name of the open collection, or "" |
| `DbWarn$()` | Warning from the last open ("" if none), e.g. "repaired torn last line" |
| `DbList%()` | Number of collections; names via DbListName$(0 .. n-1), sorted |
| `DbListName$(i%)` | Name of collection i% from the last DbList% (0-based, sorted) |

### Reading records (open collection)

| Routine | Description |
|---|---|
| `DbCount%()` | Number of records in the open collection |
| `DbAt$(i%)` | Record at position i% (0 .. DbCount%()-1) in _id order |
| `DbGet$(id$)` | Record with _id id$, or "" (DbErr$() = "not found") |
| `DbExists%(id$)` | 1 if a record with this _id exists (an index lookup, no file read) |
| `DbPos%(id$)` | Position of id$ in _id order (for DbAt$), or -1 |

### Writing records

| Routine | Description |
|---|---|
| `DbInsert%(rec$)` | Add a new record (its _id must not exist) |
| `DbUpdate%(rec$)` | Replace an existing record (same _id) |
| `DbPut%(rec$)` | Insert or replace |
| `DbDelete%(id$)` | Delete a record |
| `DbNewId$()` | Next free automatic _id ("000001", "000002", ...) |
| `DbSetText%(id$, f$, v$)` | Change one field of a stored record |
| `DbSetNum%(id$, f$, n!)` | Set one field of a stored record to a number |
| `DbSetRaw%(id$, f$, lit$)` | Literal: a number as text ("1.5"), true, false or null |
| `DbUnset%(id$, f$)` | Remove one field from a stored record |

### Record strings (no file access)

| Routine | Description |
|---|---|
| `DbNew$(id$)` | A new record string holding only _id |
| `DbNumStr$(n!)` | Number as JSON text; whole numbers keep all digits |
| `DbStr$(rec$, f$)` | Value of field f$ as text ("" if missing; check DbHas%) |
| `DbNum!(rec$, f$)` | Value of field f$ as a number (0 if missing or not a number) |
| `DbHas%(rec$, f$)` | 1 if rec$ has field f$ |
| `DbKind$(rec$, f$)` | Kind of field f$: "S" text, "N" number, "L" true/false/null, "O" list/object (read-only), "" missing |
| `DbWithText$(rec$, f$, v$)` | Copies of rec$ with one field set or removed ("" + DbErr$ if the result would be over 255 characters) |
| `DbWithNum$(rec$, f$, n!)` | Copy of rec$ with field f$ set to a number |
| `DbWithRaw$(rec$, f$, lit$)` | Copy of rec$ with field f$ set to a literal: number text, true, false or null |
| `DbWithAuto$(rec$, f$, v$)` | Number, true, false or null if v$ looks like one, otherwise text (handy when importing CSV or serial data) |
| `DbWithout$(rec$, f$)` | Copy of rec$ without field f$ |
| `DbValid%(rec$)` | 1 if rec$ is a well-formed record line |
| `DbFieldCount%(rec$)` | Number of fields in rec$ (including _id) |
| `DbFieldName$(rec$, i%)` | Name / value of the i%-th field (0-based) of rec$ |
| `DbFieldValue$(rec$, i%)` | Value of the i%-th field of rec$, as text |
| `DbNth%(rec$, i%, k$, v$)` | Internal: find the i%-th field; name and value returned in k$ and v$ |

### Queries

| Routine | Description |
|---|---|
| `DbQuery%(sql$)` | Run one SQL-like statement (see the user guide). Then: SELECT        DbRows%(), DbRow$(i)  (rows stay readable until VACUUM) COUNT(*)      DbResult%() SHOW/DESCRIBE/EXPLAIN  DbLines%(), DbLine$(i) others        DbMsg$()  e.g. "3 updated", "inserted 000012" The collection named in the statement becomes the open one. |
| `DbFind%(f$, op$, v$)` | Number of rows from the last SELECT Find records where field f$ op$ v$, without SQL. op$: = <> < <= > >= or STARTS (text beginning with v$). v$ is compared as text; use DbFindNum% for numbers. Uses an index when there is one. Results as for SELECT: DbRows%() and DbRow$(). Much shallower than DbQuery%: it skips the SQL parser, which matters on the PicoMite's small stack. |
| `DbFindNum%(f$, op$, n!)` | — |
| `DbRows%()` | — |
| `DbRow$(i%)` | Row i% of the last SELECT: the record as it was when the query ran |
| `DbResult%()` | Result of the last SELECT COUNT(*) |
| `DbLines%()` | Number of text lines from the last SHOW, DESCRIBE or EXPLAIN |
| `DbLine$(i%)` | Text line i% from the last SHOW, DESCRIBE or EXPLAIN |
| `DbMsg$()` | Summary of the last statement, e.g. "3 updated", "inserted 000012" |

### Metadata (open collection)

| Routine | Description |
|---|---|
| `DbFields%()` | Fields seen in the collection: DbFields%(), then for i = 0 .. n-1 DbFieldInfo$(i) = name and DbFieldType$(i) = S N L O or X (mixed) |
| `DbFieldInfo$(i%)` | Name of known field i% of the open collection |
| `DbFieldType$(i%)` | Kind of known field i%: S, N, L, O or X (mixed) |
| `DbIndexes$()` | Indexed fields as a comma list, e.g. "age,name" |
| `DbIsIndexed%(f$)` | 1 if field f$ is indexed |
| `DbIndexAdd%(f$)` | Index field f$ (up to 4 per collection); saved at once |
| `DbIndexDrop%(f$)` | Remove the index on field f$; saved at once |
| `DbDead%()` | Superseded/deleted lines in the file (VACUUM removes them) |
| `DbVacuum%()` | Rewrite the data file without dead lines |
| `DbMetaGet$(k$)` | Your own collection properties, kept in the .meta file (all of them together at most about 230 characters). Saved by DbFlush / DbClose. |
| `DbMetaSet%(k$, v$)` | Set a property (text); saved by DbFlush / DbClose |
| `DbMetaDel%(k$)` | Remove a property |
| `DbMetaName$(i%)` | Property names: DbMetaName$(0), (1) ... until "" |

## Rules for programs using the library

- Use file numbers `#4` to `#10`; the engine uses `#1` to `#3`.
- Don't name your own SUBs, FUNCTIONs or global variables with the engine's prefixes (`Db`, `Rc`, `Ix`, `Sx`, `St`, `Mt`, `Tk`, `Q`, `Ex`) or names starting with `z_`.
- Only one collection is open at a time; `DbQuery%` opens the collection its statement names.
- Call `Db…` routines from shallow places in your program, and prefer `DbFind%` to `DbQuery%` for single conditions. PicoMite's stack allows only about 15 nested calls on a Pico 2, and fewer on an RP2040. The library itself uses up to 8 ([MMBasic notes](MMBasic-Notes.md#the-call-stack-is-small)).
- Call `DbClose` (or `DbFlush`) before the program ends. Nothing is lost if you don't, but the next open has to catch the index up.
- Records are limited to 255 characters. The `DbWith…$` functions return `""` (and set `DbErr$()`) instead of building a longer one, so check for `""` before writing.

---
Previous: [Explorer GUI](Explorer-GUI.md) · Next: [MMBasic notes](MMBasic-Notes.md)
