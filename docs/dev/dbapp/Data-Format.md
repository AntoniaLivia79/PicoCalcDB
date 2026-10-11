[Home](Home.md) › Data format

# Data format

All data lives in one folder, `StDir$` (`B:/db/` by default, set in `dbmain.bas` or by `DbInit`). Each collection is a group of files sharing its name:

| File | Written by | Contents |
|---|---|---|
| `name.jsonl` | every write | The records. The only file that matters: everything else can be rebuilt from it |
| `name.idx` | `StFlush` / `StClose` | A saved copy of the primary index, so opening is fast |
| `name.meta` | `MtSave` | Metadata: auto-id counter, dead-line count, indexed fields, field kinds, user properties |
| `name.vtmp` | `StVacuum%` | Temporary file while vacuuming; normally absent |

The collection list (`StList%`) is simply every `*.jsonl` file in the folder.

## Records: `name.jsonl`

Each line is one record: a flat JSON object, at most 255 characters, with a text `_id` of at most 16 characters:

```
{"_id":"p01","name":"Ann","age":34,"vip":true}
```

- Values are text (`"…"`), numbers, `true`, `false` or `null`. Lists and nested objects written by other programs are kept unchanged but treated as read-only.
- The 255-character limit is MMBasic's maximum string length: a record must fit in one string variable.

### Append-only

The file is never rewritten in place. Every insert, update and delete **appends** a line:

```
{"_id":"p01","name":"Ann","age":34}        <- inserted
{"_id":"p02","name":"Bob"}                 <- inserted
{"_id":"p01","name":"Ann","age":35}        <- p01 updated: the first line is now dead
{"_id":"p02","_del":1}                     <- p02 deleted: a "tombstone"
```

For each `_id`, the **last** line wins; a tombstone (a line with `"_del"`) means the record is deleted. Superseded lines and tombstones are *dead lines*; `VACUUM` removes them by rewriting the file (see [Storage engine](Storage-Engine.md#vacuum)).

Append-only writing is what makes the engine safe and simple on an SD card:

- **A power cut can damage only the last line.** `StFixTail` repairs the file on the next open, and the scanner skips a torn line.
- **A record's position never changes.** An *offset* (see below) stays valid until the next vacuum, so result lists can hold offsets while records are being changed.
- **No free-space management.** There is nothing to reuse or defragment.

### Offsets

Records are located by **offset**: the 1-based byte position of the start of their line, exactly as returned by `LOC(#n)` and accepted by `SEEK #n`. The index maps each `_id` to the offset of its current line, and `IxReadAt$(fnum%, off%)` reads it back with one `SEEK` and one `LINE INPUT`.

## Saved index: `name.idx`

```
IX1,10927
1,000001
58,000002
104,p01
```

The first line is a format tag and the length of the data file when the index was saved. Each further line is `offset,_id`, in `_id` order. The separator is a comma, not a tab: `LINE INPUT` turns tabs into spaces.

On open, if the data file is now longer than the saved length, only the new tail is scanned; if it is shorter, the index is discarded and rebuilt. See [Indexes](Indexes.md#saving-loading-and-catching-up).

## Metadata: `name.meta`

Also JSON lines, so the same codec reads it:

```
{"_id":"@","seq":12,"dead":3,"i0":"age","i1":"name"}
{"_id":"@user","title":"Club members"}
{"_id":"name","t":"S"}
{"_id":"age","t":"N"}
```

| Line | Meaning |
|---|---|
| `@` | `seq`: last automatic `_id` number; `dead`: dead lines in the data file; `i0`…`i3`: indexed fields |
| `@user` | Properties set by programs through `DbMetaSet%` (only written when there are some) |
| any other `_id` | A field seen in the records, with its kind `t`: `S` text, `N` number, `L` true/false/null, `O` list/object, `X` mixed |

Field names starting with `@` are therefore not tracked as fields. The dead-line count is approximate: it is only saved when metadata is saved, and is reset to 0 by `VACUUM`.

## Help topics: `help/dbhelp.jsonl`

The explorer's help is also a JSON Lines file, in the subfolder `help/` so that it does not appear as a collection:

```
{"_id":"0630.1","title":"Matching text with LIKE","kw":"like pattern wildcard","text":"% stands for ..."}
{"_id":"0630.2","text":"name LIKE 'A%' starts with A ..."}
```

Records whose `_id` share the part before the `.` form one topic, shown in file order. See [Explorer GUI](Explorer-GUI.md#help).

---
Previous: [Architecture](Architecture.md) · Next: [Record codec](Record-Codec.md)
