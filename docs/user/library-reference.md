# PicoCalc DB Library

Use PicoCalc DB collections from your own PicoMite BASIC programs. You can read and write records, run queries, and read or set collection metadata.

The library uses the same files as the PicoCalc DB application, so data written by a script can be browsed in the app, and the other way round. For the file format, the query language and the limits, see the [user guide](dbapp-user-guide.md).

---

## 1. Installing

The library comes in two forms, both in the repository's `dist/` folder:

| File | Use |
|---|---|
| `dblib.bas` | The library with comments. Include it in your program. |
| `dblib_min.bas` | The same library without comments, for `LIBRARY SAVE` or to save memory. |

### Option A: include it in your program

Copy `dblib.bas` next to your program on the SD card, then start the program like this:

```basic
OPTION EXPLICIT
OPTION DEFAULT NONE
#INCLUDE "dblib.bas"
' ... your code ...
```

`#INCLUDE` works when the program is loaded from a file with `RUN "prog.bas"` or `LOAD "prog.bas"`. Put the `OPTION` lines before it. The library itself contains no `OPTION` statements and no main code.

### Option B: keep it in flash for every program

At the `>` prompt type:

```
NEW
LOAD "dblib_min.bas"
LIBRARY SAVE
```

From then on, every program can call the `Db…` functions without an `#INCLUDE`. `LIBRARY LIST` shows the library, and `LIBRARY DELETE` removes it.

---

## 2. A first program

```basic
OPTION EXPLICIT
OPTION DEFAULT NONE
#INCLUDE "dblib.bas"
DIM r$, i%

DbInit "B:/db"                              ' folder holding the collections
IF DbOpen%("contacts") = 0 THEN             ' open, or create the first time
  IF DbCreate%("contacts") = 0 THEN PRINT DbErr$() : END
  i% = DbOpen%("contacts")
ENDIF

r$ = DbNew$("ann")                          ' build a record in memory ...
r$ = DbWithText$(r$, "name", "Ann Smith")
r$ = DbWithNum$(r$, "age", 34)
IF DbPut%(r$) = 0 THEN PRINT DbErr$()       ' ... then store it

FOR i% = 0 TO DbCount%() - 1                ' every record, in _id order
  r$ = DbAt$(i%)
  PRINT DbStr$(r$, "_id"), DbStr$(r$, "name"), DbNum!(r$, "age")
NEXT

IF DbQuery%("SELECT * FROM contacts WHERE age > 30 ORDER BY name") THEN
  FOR i% = 0 TO DbRows%() - 1 : PRINT DbStr$(DbRow$(i%), "name") : NEXT
ENDIF

DbClose                                     ' always close at the end
```

There are three complete examples in the repository's `examples/` folder:

- **`ex1_quickstart.bas`:** creating a collection, writes, reads and queries.
- **`ex2_import_csv.bas`:** importing a CSV file.
- **`ex3_report.bas`:** metadata, statistics and exporting to CSV.

`ex2` reads `B:/db/plants.csv`. Copy the repository's `sdcard/db/plants.csv` there, or edit it to import your own data: the first line names the fields, an `_id` column gives the record ids, and values must not contain commas or quotes. If the file is missing, `ex2` writes the same four-plant sample itself.

Run `ex2` before `ex3`, because `ex3` reports on the collection that `ex2` imports. All three can be run again and again: `ex1` checks before adding its automatic-id record.

---

## 3. How it works, in five points

1. **A record is a string.** It is one JSON line, such as `{"_id":"ann","name":"Ann Smith","age":34}`, at most 255 characters long. You read and build records with string functions (`DbStr$`, `DbWithText$`, …) and then store them.
2. **One collection is open at a time.** `DbOpen%` closes the previous one. `DbQuery%` opens the collection named in the statement.
3. **Results come back as success flags.** Functions that change something return `1` for success and `0` for failure; `DbErr$()` then says why. Functions that return text return `""` when there is nothing to return.
4. **Close before your program ends.** `DbClose` saves the index and metadata. If you forget, nothing is lost, but the next open takes longer while the index is caught up.
5. **Values have a kind:** text (`S`), number (`N`), `true`/`false`/`null` (`L`), or a nested list/object written by another program (`O`, read-only).

---

## 4. Reference

### Setup and collections

| Function | Returns / does |
|---|---|
| `DbInit dir$` | *(SUB)* Use folder `dir$`, for example `"B:/db"`. It is created if missing. Closes any open collection. |
| `DbCreate%(c$)` | Create a collection. Names use letters, digits and `_`, up to 16 characters. |
| `DbDrop%(c$)` | Delete a collection and all its files. |
| `DbOpen%(c$)` | Open a collection, closing the previous one. |
| `DbClose` | *(SUB)* Save the index and metadata, then close. |
| `DbFlush` | *(SUB)* Save the index and metadata, staying open. |
| `DbCurrent$()` | Name of the open collection, or `""`. |
| `DbWarn$()` | Warning from the last open, such as `repaired torn last line` or `stale index rebuilt`. |
| `DbList%()` | Number of collections in the folder. |
| `DbListName$(i%)` | Name of collection `i%` (0-based, sorted). |

### Reading records (open collection)

| Function | Returns |
|---|---|
| `DbCount%()` | Number of records. |
| `DbAt$(i%)` | Record at position `i%` (0 … `DbCount%()-1`) in `_id` order. |
| `DbGet$(id$)` | The record with that `_id`, or `""` (`DbErr$()` = `not found`). |
| `DbExists%(id$)` | 1 if the record exists. |
| `DbPos%(id$)` | Its position for `DbAt$`, or -1. |

### Writing records (open collection)

| Function | Does |
|---|---|
| `DbInsert%(rec$)` | Add a record. Its `_id` must be new. |
| `DbUpdate%(rec$)` | Replace an existing record with the same `_id`. |
| `DbPut%(rec$)` | Insert or replace. |
| `DbDelete%(id$)` | Delete a record. |
| `DbNewId$()` | Next free automatic `_id`: `000001`, `000002`, … |
| `DbSetText%(id$, f$, v$)` | Set one field of a stored record to text. |
| `DbSetNum%(id$, f$, n!)` | … to a number. |
| `DbSetRaw%(id$, f$, lit$)` | … to a literal: a number written as text, `true`, `false` or `null`. |
| `DbUnset%(id$, f$)` | Remove one field. |

Each `DbSet…%` call reads the record, changes it and writes it back. To change several fields of the same record, it is quicker to `DbGet$` it, apply several `DbWith…$` calls, and `DbUpdate%` once.

### Record strings (no file access)

| Function | Returns |
|---|---|
| `DbNew$(id$)` | A new record holding only `_id`. |
| `DbStr$(rec$, f$)` | Value of field `f$` as text (`""` if missing). |
| `DbNum!(rec$, f$)` | Value as a number (0 if missing or not a number). |
| `DbHas%(rec$, f$)` | 1 if the field exists. |
| `DbKind$(rec$, f$)` | `S`, `N`, `L`, `O`, or `""` if missing. |
| `DbWithText$(rec$, f$, v$)` | Copy of `rec$` with the field set to text. |
| `DbWithNum$(rec$, f$, n!)` | … set to a number. Whole numbers keep all their digits. |
| `DbWithRaw$(rec$, f$, lit$)` | … set to a literal (`true`, `false`, `null`, or number text). |
| `DbWithAuto$(rec$, f$, v$)` | … set to a number or literal if `v$` looks like one, otherwise text. Handy for imports. |
| `DbWithout$(rec$, f$)` | … with the field removed. |
| `DbValid%(rec$)` | 1 if `rec$` is a well-formed record. |
| `DbFieldCount%(rec$)` | Number of fields, including `_id`. |
| `DbFieldName$(rec$, i%)` | Name of field `i%` (0-based); field 0 is `_id`. |
| `DbFieldValue$(rec$, i%)` | Value of field `i%`. |
| `DbNumStr$(n!)` | A number as JSON text. |

The `DbWith…$` functions return `""` and set `DbErr$()` if the result would exceed 255 characters, or if a literal is invalid. Check for `""` before storing.

### Queries

`DbQuery%(sql$)` runs one statement of the query language: SELECT, INSERT, UPDATE, DELETE, CREATE/DROP, SHOW, DESCRIBE, VACUUM or EXPLAIN. The collection named in the statement becomes the open one.

What you read afterwards depends on the statement:

| After | Read with |
|---|---|
| `SELECT …` | `DbRows%()`, then `DbRow$(i%)` for `i%` = 0 … `DbRows%()-1` |
| `SELECT COUNT(*) …` | `DbResult%()` |
| `SHOW`, `DESCRIBE`, `EXPLAIN` | `DbLines%()`, then `DbLine$(i%)` |
| INSERT / UPDATE / DELETE / admin | `DbMsg$()`, e.g. `3 updated`, `inserted 000012` |

`SELECT` results remain readable while you write. You can loop over `DbRow$(i%)` and update or delete those records, because data files are only appended to. `DbRow$` returns each record as it was when the query ran. The results become invalid after `DbVacuum%` or another `DbQuery%`.

Text values in SQL go in single quotes, written twice inside the text: `"… WHERE name = 'O''Brien'"`. When you build a statement from a variable, double any `'` in it first.

### Finding records without SQL

For a single condition, `DbFind%` is simpler and lighter than a query. It works on the open collection, uses an index when there is one, and returns the number of matches. Read the records with `DbRows%()` and `DbRow$(i%)`, as after a SELECT.

| Function | Finds records where |
|---|---|
| `DbFind%(f$, op$, v$)` | field `f$` compared with the **text** `v$` |
| `DbFindNum%(f$, op$, n!)` | field `f$` compared with the **number** `n!` |

`op$` is one of `=`, `<>`, `<`, `<=`, `>`, `>=`, or `STARTS` (text beginning with `v$`; `%` and `_` in `v$` act as wildcards). The rules are those of a WHERE clause: a record without the field never matches, and text never equals a number.

```basic
n% = DbFind%("city", "=", "Leeds")
FOR i% = 0 TO n% - 1 : PRINT DbStr$(DbRow$(i%), "name") : NEXT
n% = DbFindNum%("age", ">=", 18)
n% = DbFind%("_id", "STARTS", "2026-10-")
```

Text values need no quoting, unlike in SQL. Rows from an index other than `_id` come in that index's order, not `_id` order.

### Metadata (open collection)

| Function | Returns / does |
|---|---|
| `DbFields%()` | Number of distinct field names seen in the collection (up to 24). |
| `DbFieldInfo$(i%)` | Name of known field `i%`. |
| `DbFieldType$(i%)` | Its kind: `S`, `N`, `L`, `O`, or `X` for mixed. |
| `DbIndexes$()` | Indexed fields as a comma list, such as `age,city` (`_id` is always indexed). |
| `DbIsIndexed%(f$)` | 1 if the field is indexed. |
| `DbIndexAdd%(f$)` / `DbIndexDrop%(f$)` | Add or remove an index. Up to 4 per collection. |
| `DbDead%()` | Dead lines left by updates and deletes. |
| `DbVacuum%()` | Rewrite the file without dead lines. |
| `DbMetaSet%(k$, v$)` | Set your own text property, such as a title or version. |
| `DbMetaGet$(k$)` | Read a property (`""` if not set). |
| `DbMetaDel%(k$)` | Remove a property. |
| `DbMetaName$(i%)` | Name of property `i%` (0-based), `""` after the last. |

Properties are stored in the collection's `.meta` file and saved by `DbFlush` or `DbClose`. All of a collection's properties together may use about 230 characters, and names may not start with `_`.

### Errors

`DbErr$()` returns the reason the last call failed, or `""` after a success. Common messages:

- `exists`, `no such collection`, `bad name`
- `duplicate _id`, `not found`, `too long`
- `collection full`, `index space full`, `no free index slot`
- `bad record`, `_id must be a string`
- query errors such as `expected a value at col 27`

---

## 5. Things to know

- **Reserved names.** Your program must not use the library's own names. Avoid names that start with `Db`, `Rc`, `Ix`, `Sx`, `St`, `Mt`, `Tk`, `Q` or `Ex`, and constants that start with `RC_`, `IX_`, `SX_`, `ST_`, `MT_`, `TK_`, `QO_`, `QN_`, `QF_`, `QV_`, `QNV_` or `EX_`. A clash shows up as an error such as `… already declared`.
- **Your SUB and FUNCTION names.** MMBasic refuses a SUB or FUNCTION with the same name as a local variable inside any other routine, and only says so when that routine runs. To make this safe, all local variables in `dblib.bas` start with `z_`. So apart from the prefixes above, the only names to avoid for your own SUBs and FUNCTIONs are those starting with `z_`. Your variables and constants can use any other names.
- **Field names starting with `@`.** These work in records, but are not listed by `DbFields%()`. The `.meta` file uses `@` for its own entries.
- **File numbers.** The library uses `#1`–`#3`. Use `#4` and above in your program.
- **Memory.** With default settings the library's indexes use about 47 KB. Sorting with `ORDER BY` needs about 32 bytes per matching row while it runs.
- **Speed.** Searching by `_id`, or by an indexed field with `=`, `<`, `>`, `LIKE 'abc%'` and so on, reads only the matching records. Other searches read every record. Prefix a query with `EXPLAIN` to see which way it will run.
- **Call depth.** PicoMite runs BASIC on a small stack: a program stops with `Stack overflow ... at depth N` if too many SUBs and FUNCTIONs are active at once (about 15 on a Pico 2, probably fewer on an RP2040). The library uses up to 8 levels itself for `DbQuery%`, and 5 for `DbFind%`. So call the library from shallow places in your program, avoid recursion, and use `DbFind%` for single conditions.
- **Single-line IF.** MMBasic does not accept `IF … THEN a : b ELSE c` on one line. Use a block `IF … ENDIF`.
- **AND and OR in BASIC.** In BASIC itself, AND and OR have the same precedence and are read left to right, so add brackets: `IF (a OR b) AND c`. The query language is different: there, AND goes before OR, as in SQL.
- **Sharing with the app.** Close the collection (`DbClose`) before the app or another program opens it. Files edited on a PC are fine: a changed file is detected and its index rebuilt.

---

## 6. Files

| File | Contents |
|---|---|
| `dist/dblib.bas` / `dist/dblib_min.bas` | The library: engine plus the `Db…` API |
| `src/dbapi.bas` | The API layer on its own. `dblib.bas` already contains it. |
| `examples/` | Three example programs |
| `tests/test_api.bas` | Automated tests of the API (run on a PC with MMB4L) |
| `tools/build.py` | Rebuilds the files in `dist/` from the modules in `src/` after a change (needs Python 3) |
