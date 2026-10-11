# PicoCalc DB – User Guide

PicoCalc DB is a small document database for the PicoCalc. It keeps **collections** of **records** on the SD card and lets you browse, search and edit them with the keyboard, or with simple SQL-like commands.

Each record is a set of named fields, such as a name, an age or a phone number. Different records may have different fields. The data files are plain text in the widely used JSON Lines format, so you can also read and edit them on a PC.

Your own PicoMite programs can read and write the same collections with the **PicoCalc DB library**; see the [library reference](library-reference.md).

This guide is for people who **use** the program. The same information is built into the program: press **F1** and type a word to search it.

---

## Contents

1. [Installing](#1-installing)
2. [Starting and quitting](#2-starting-and-quitting)
3. [The screen](#3-the-screen)
4. [Keys](#4-keys)
5. [Collections](#5-collections)
6. [Records](#6-records)
7. [Editing a record](#7-editing-a-record)
8. [Filtering records](#8-filtering-records)
9. [The SQL command line](#9-the-sql-command-line)
10. [Writing conditions](#10-writing-conditions)
11. [Sorting, limits and counting](#11-sorting-limits-and-counting)
12. [Indexes: making searches faster](#12-indexes-making-searches-faster)
13. [Looking after your data](#13-looking-after-your-data)
14. [Using your data on a PC](#14-using-your-data-on-a-pc)
15. [The built-in help](#15-the-built-in-help)
16. [Limits](#16-limits)
17. [Messages and troubleshooting](#17-messages-and-troubleshooting)
18. [Quick reference](#18-quick-reference)

---

## 1. Installing

You need a PicoCalc running PicoMite MMBasic, and an SD card.

1. Copy **`dbapp_min.bas`** (in the repository's `dist/` folder) to the root of the SD card.

   `dbapp.bas` is the same program with explanatory comments. It works too, but uses more memory.
2. On the SD card, create the folder **`db`**, and inside it the folder **`help`**.
3. Copy **`dbhelp.jsonl`** into `db/help/`. The repository's `sdcard/` folder already has this layout, so you can copy its `db` folder as it is.

The SD card should then look like this:

```
dbapp_min.bas
db/
  help/
    dbhelp.jsonl
```

The program creates the `db` folder itself if it is missing. Without the help file, F1 shows only a short key summary.

## 2. Starting and quitting

At the PicoCalc `>` prompt type:

```
DRIVE "B:"
RUN "dbapp_min.bas"
```

The program starts in the **Collections** list.

To quit, press **Esc** in the Collections list and answer **y**. Stopping the program with **Ctrl-C** is also safe: nothing is lost (see [Power loss and crashes](#power-loss-and-crashes)).

## 3. The screen

```
+----------------------------------------+
| people  3/46  [age > 30]               |  <- title: where you are
| p01 age:34 name:Ann                    |
| p02 age:41 name:Bob                    |
| p03 age:52 name:Cy        <-- selected |  <- the list
| ...                                    |
| 3 row(s)                               |  <- messages / input line
| Ent view F filter N new Del D / Esc    |  <- keys you can use now
+----------------------------------------+
```

- **Title line:** the collection, your position and the number of records, for example `people  3/46`. When a filter is active it is shown in `[ ]`.
- **List:** the highlighted line is the current selection.
- **Message line:** results and errors. You also type here when the program asks for something.
- **Hint line:** the most useful keys for the current screen.

There are four kinds of screen: the **Collections** list, the **Records** list, the **Record detail**, and **text pages**. Text pages are used for help, descriptions and query plans.

## 4. Keys

### Everywhere

| Key | Action |
|---|---|
| Up / Down | Move one line |
| Left / Right, PgUp / PgDn | Move one page (in the record detail, Left/Right change record) |
| Home / End | First / last line |
| **F1** | Search the help |
| **F2** or **/** | Open the SQL command line |
| **Esc** | Back, cancel, or clear a filter |

### Collections list

| Key | Action |
|---|---|
| Enter | Open the collection |
| N | New collection |
| Del | Drop the collection: deletes all its records, after you answer y |
| Esc | Quit (asks first) |

### Records list

| Key | Action |
|---|---|
| Enter | Show the record |
| F | Filter: show only records matching a condition |
| N | New record |
| Del | Delete the record (asks first) |
| D | Describe the collection: fields, types and indexes |
| Esc | Clear the filter, or go back to the collections |

### Record detail

| Key | Action |
|---|---|
| Enter | Edit the highlighted value |
| A | Add a field |
| Del | Remove the highlighted field (asks first) |
| Left / Right | Previous / next record |
| Esc | Back to the list |

### Typing on the input line

| Key | Action |
|---|---|
| Left / Right, Home / End | Move the cursor |
| Backspace / Del | Delete left of / under the cursor |
| Up / Down | Earlier commands (SQL command line only; the last 8 are kept) |
| Enter / Esc | Accept / cancel |

## 5. Collections

A collection is a set of records, rather like a table or a card-index box. Each collection is stored in its own file on the SD card.

- **Create:** press **N** in the Collections list and type a name. A name can use letters, digits and `_`, up to 16 characters. It cannot be one of the SQL command words, such as `order` or `select`.
- **Open:** highlight the collection and press **Enter**. The open collection is marked `(open)`.
- **Drop:** press **Del** and answer **y**. This deletes the collection and all its records.

## 6. Records

Every record has an **`_id`**: a short text of up to 16 characters that is unique within its collection. Besides that, a record can have any fields you like.

The record list shows one line per record: the `_id`, then `name:value` pairs for as many fields as fit on the screen. Records are listed in `_id` order.

**Add a record:** press **N** in the record list. Type an `_id`, or just press Enter to get the next automatic number (`000001`, `000002`, …). The new record opens straight away; press **A** to add fields.

**Delete a record:** highlight it, press **Del**, and answer **y**.

## 7. Editing a record

Press **Enter** on a record to see its fields, one per line. The first line is always its `_id`.

- **Edit a value:** highlight the field, press **Enter**, change the text, then press Enter to save or Esc to cancel.
- **Add a field:** press **A**, type the field name, then its value. If the field already exists, you edit it instead.
- **Remove a field:** highlight it, press **Del** and answer **y**.
- **Step through records:** use **Left / Right**.

### Kinds of values

| Kind | Examples |
|---|---|
| Text | `Ann`, `12 High Street` |
| Number | `42`, `-1.5`, `2e3` |
| Yes/no and empty | `true`, `false`, `null` |

When you save a value, the program decides its kind as follows:

- A field that already holds **text stays text**, whatever you type.
- Otherwise, a value that looks like a number, `true`, `false` or `null` is stored as one, and anything else is stored as text.
- To store something that looks like a number **as text**, put it in single quotes, for example `'0123'` for a code with a leading zero. Text that looks like a number is shown in quotes so that you can tell it apart.

Field names starting with `_` are reserved, and `_id` cannot be changed or removed. Records created by other programs may contain lists or nested values. These are shown as `{..}` or `[..]` and cannot be edited on the PicoCalc.

## 8. Filtering records

In the record list press **F** and type a condition:

```
age > 30 AND name LIKE 'A%'
```

Only matching records are listed, and the title shows the condition. Press **F** again to change it, or **Esc** to see all records again.

If you make a typing mistake, the message line says what was expected and at which column, for example `expected a value at col 7`. See [Writing conditions](#10-writing-conditions) for everything you can write.

## 9. The SQL command line

Press **F2** or **/** to type a command. Keywords can be in upper or lower case, and a `;` at the end is optional. Commands can work on any collection by name, not only the one that is open.

What happens to the result depends on the command:

- **SELECT** opens its results in the record list, marked `[query]`. Esc returns to all records.
- **COUNT** shows its answer on the message line.
- **SHOW**, **DESCRIBE** and **EXPLAIN** open a text page.
- **Other commands** report what they did, for example `3 updated`.

| Command | What it does |
|---|---|
| `SELECT * FROM people` | All records |
| `SELECT name, age FROM people WHERE age > 30` | Matching records, showing only these fields |
| `SELECT COUNT(*) FROM people WHERE city = 'Leeds'` | Count matching records |
| `INSERT INTO people (_id, name, age) VALUES ('p1', 'Ann', 34)` | Add a record (leave out `_id` for an automatic one) |
| `UPDATE people SET age = 35, city = 'York' WHERE _id = 'p1'` | Change fields |
| `UPDATE people UNSET phone WHERE age > 90` | Remove fields |
| `DELETE FROM people WHERE age < 18` | Delete records |
| `CREATE COLLECTION people` / `DROP COLLECTION people` | Make / delete a collection |
| `CREATE INDEX ON people (age)` / `DROP INDEX ON people (age)` | Add / remove an index |
| `SHOW COLLECTIONS` | List collections |
| `DESCRIBE people` | Record count, dead lines, indexes, fields and their kinds |
| `VACUUM people` | Tidy the file (see [VACUUM](#vacuum-reclaiming-space)) |
| `EXPLAIN SELECT …` | Show how a command would run, without running it |

> **Careful:** `UPDATE` and `DELETE` without `WHERE` change or delete **every** record in the collection, and the command line does not ask "are you sure?".

## 10. Writing conditions

Conditions are used after `WHERE`, and in the filter (**F**).

### Comparing

| Write | Meaning |
|---|---|
| `age = 30` | equal |
| `age <> 30` or `age != 30` | not equal |
| `age < 30`, `age <= 30`, `age > 30`, `age >= 30` | smaller / larger |

- Put text values in single quotes: `name = 'Ann'`. For an apostrophe, write two quotes: `'O''Brien'`.
- A field name that contains spaces, or is an SQL word, goes in double quotes: `"first name" = 'Al'`, `"order" > 5`.

### Combining

Combine conditions with `AND`, `OR` and `NOT`. `AND` goes before `OR`, so

```
a = 1 OR b = 2 AND c = 3
```

means `a = 1 OR (b = 2 AND c = 3)`. Use brackets to group differently: `(a = 1 OR b = 2) AND c > 0`.

### Matching text with LIKE

| Write | Matches |
|---|---|
| `name LIKE 'A%'` | starts with A |
| `name LIKE '%son'` | ends with son |
| `code LIKE 'A_1'` | A, any one character, then 1 |
| `name NOT LIKE 'A%'` | does not start with A |

`%` stands for any number of characters, and `_` for exactly one. LIKE is **case-sensitive** (`'a%'` does not match `Ann`), and it only matches text, never numbers.

### Missing fields and NULL

A record that doesn't have a field **never matches a comparison on that field, not even `<>`**.

- Use `phone IS NULL` to find records where the field is missing or `null`.
- Use `phone IS NOT NULL` to find the others.

### How values compare

- **Numbers** compare by value, so `1e3 = 1000`.
- **Text** compares character by character, so capital letters come before small ones.
- **A number and a text are never equal,** and never smaller or larger than each other; only `<>` is true between them. `'5'` in quotes is text; `5` is a number.

## 11. Sorting, limits and counting

```
SELECT * FROM people WHERE age > 18 ORDER BY age DESC LIMIT 10 OFFSET 20
```

- **`ORDER BY field`** sorts by one field; add **`DESC`** for largest first. Numbers come before text. Records without the field come last (first with `DESC`).
- **`LIMIT 10`** keeps the first 10 results, and **`OFFSET 20`** skips 20 first.
- **Without `ORDER BY`,** results come in `_id` order, or in the order of an index the command used.
- **`SELECT COUNT(*) FROM people WHERE …`** counts the matches.

## 12. Indexes: making searches faster

Without an index, a search reads every record in the collection. An index lets the program jump straight to the likely matches.

```
CREATE INDEX ON people (age)
DROP INDEX ON people (age)
```

- **What gets indexed:** `_id` always is. You can index up to **4 other fields** per collection.
- **When an index is used:** for `=`, `<`, `<=`, `>`, `>=` and `LIKE 'abc%'` (text starting with something), as long as the condition is not inside `OR` or `NOT`.
- **Cost:** an index uses memory, one entry for every record that has the field.

To check whether a command will use an index, put **EXPLAIN** in front of it:

```
EXPLAIN SELECT * FROM people WHERE age > 30 AND name = 'Ann'
```

The answer says `full scan` (every record is read) or names the index used, such as `index on age` or `_id range`. Conditions marked `^` are ones an index could serve.

## 13. Looking after your data

### DESCRIBE

`DESCRIBE people`, or **D** in the record list, shows the number of records, the number of dead lines (see VACUUM), the indexes, and every field seen so far with its kind:

| Letter | Kind |
|---|---|
| S | text |
| N | number |
| L | true / false / null |
| O | list or nested value (from other programs) |
| X | mixed: different kinds in different records |

### VACUUM: reclaiming space

To keep your data safe, changing or deleting a record never overwrites the file. Instead, a new line is added and the old one becomes a **dead line**. Over time the file grows.

`VACUUM people` rewrites the file with only the current records. Run it now and then, and always before copying files to a PC. It is safe even if the power fails while it runs.

### Power loss and crashes

Because records are only ever added to the end of a file, a power cut can damage at most the last line. The next time you open the collection, the program repairs this and tells you on the message line:

- **`repaired torn last line`:** the last line was incomplete and has been repaired.
- **`2 bad line(s) skipped`:** that many lines couldn't be read and were ignored.

Stopping the program with Ctrl-C is safe; the index is rebuilt or brought up to date the next time the collection is opened.

### Backups

All data is in the **`db`** folder on the SD card. Copy that folder to back everything up.

## 14. Using your data on a PC

For a collection called `people`, the `db` folder holds:

| File | Contents |
|---|---|
| `people.jsonl` | The records, one per line |
| `people.idx` | A saved index. It can be deleted at any time and is rebuilt automatically |
| `people.meta` | Field kinds and index settings |

A `.jsonl` file looks like this:

```
{"_id":"p01","name":"Ann","age":34}
{"_id":"p02","name":"Bob","age":41,"city":"Leeds"}
```

This is **JSON Lines**, one JSON object per line. It can be read by Python, JavaScript and many data tools, and it converts easily to a spreadsheet.

**Run `VACUUM` before copying files to a PC.** Without it, a file can contain old versions of records: if an `_id` appears more than once, the **last** line is the current one, and lines containing `"_del"` mark deleted records.

### Editing files on a PC

You can edit a `.jsonl` file with a text editor or your own programs, as long as you follow these rules:

- One record per line, at most **255 characters**.
- Every record has a unique text `"_id"` of up to 16 characters.
- Plain ASCII characters only. Others may not display correctly on the PicoCalc.
- **After editing, delete the matching `.idx` file** so the index is rebuilt.

Lines the program cannot read are skipped, and reported when the collection is opened.

## 15. The built-in help

Press **F1** anywhere and type one or more words, such as `index`, `like`, `null` or `delete`.

- Topics containing **all** the words, in any upper/lower case, are listed. If only one topic matches, it opens directly.
- Press Enter without typing anything to see all topics.
- Press **Enter** to read a topic and **Esc** to go back.

The help lives in `db/help/dbhelp.jsonl`, which is a JSON Lines file like your data. You can add your own topics with a text editor, one paragraph per line:

```
{"_id":"5000.1","title":"Our club rules","kw":"club rules members","text":"First paragraph."}
{"_id":"5000.2","text":"Second paragraph."}
```

- Lines whose `_id` starts with the same part before the `.` form one topic.
- The title and keywords go on the first line of a topic.
- Topics appear in the order they are in the file.
- Keep each line under 255 characters, and each topic short enough to fit about 35 screen lines.

## 16. Limits

| Item | Limit |
|---|---|
| Record size, as stored | 255 characters |
| `_id` | 16 characters, unique |
| Collection name | 16 characters: letters, digits, `_` |
| Records per collection | 1000 |
| Indexed fields per collection | 4 (plus `_id`) |
| Index entries per collection | 1000 in total, across all indexed fields |
| Command length | 255 characters |
| Field name in a command | 24 characters |
| Text value in a condition | 64 characters |
| Fields listed by DESCRIBE | 24 |

## 17. Messages and troubleshooting

| Message | Meaning / what to do |
|---|---|
| `duplicate _id` | That `_id` is already used in this collection |
| `not found` | No record with that `_id` |
| `too long` / `record too long` | The record would exceed 255 characters |
| `collection full` | 1000 records reached. Split the data or tidy up |
| `index space full` | Too many indexed values. Drop an index |
| `no free index slot` | 4 fields are already indexed |
| `expected … at col 12` | Typing mistake in a command; col counts characters from the start |
| `reserved word 'order' (quote it)` | Write the field name in double quotes: `"order"` |
| `bad name` | Collection names use letters, digits and `_` only, up to 16 characters |
| `… is an SQL word; choose another name` | Collection names cannot be SQL words |
| `stale index rebuilt` | The file was changed outside the program; the index was rebuilt |
| `repaired torn last line`, `n bad line(s) skipped` | See [Power loss and crashes](#power-loss-and-crashes) |
| `nested values are read-only` | Lists and nested values can only be changed on a PC |

**Searches are slow:** add an index on the field you search by, and check the result with `EXPLAIN`.

**F1 only shows a key summary:** the help file is missing. Check that it is at `db/help/dbhelp.jsonl` on the SD card.

**Smaller text, more lines:** open the program file and change `CONST HAL_FONT = 1` to `CONST HAL_FONT = 7`. This gives 53 × 40 characters instead of 40 × 26.

## 18. Quick reference

```
LISTS     Up/Dn move  Lt/Rt page  Home/End  Enter open  Esc back
COLLECT.  N new  Del drop  Esc quit
RECORDS   F filter  N new  Del delete  D describe
DETAIL    Enter edit  A add field  Del remove  Lt/Rt prev/next
ALWAYS    F1 help search   F2 or / SQL command line

SELECT * | COUNT(*) | f1, f2 FROM c [WHERE cond]
       [ORDER BY f [DESC]] [LIMIT n [OFFSET m]]
INSERT INTO c (f1, f2) VALUES (v1, v2)
UPDATE c [SET f = v, ...] [UNSET f, ...] [WHERE cond]
DELETE FROM c [WHERE cond]
CREATE | DROP  COLLECTION c
CREATE | DROP  INDEX ON c (f)
SHOW COLLECTIONS   DESCRIBE c   VACUUM c   EXPLAIN <command>

cond:  f = v   f <> v   f < v   f <= v   f > v   f >= v
       f LIKE 'a%'   f NOT LIKE '_b'   f IS NULL   f IS NOT NULL
       NOT cond   cond AND cond   cond OR cond   ( cond )
value: 'text'   'it''s'   42   -1.5   2e3   true   false   null
```
