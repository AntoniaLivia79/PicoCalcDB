[Home](Home.md) › Storage engine

# Storage engine (`dbstore.bas`, `St…` and `Mt…`)

The storage engine turns files into collections. It is the only module that opens the data files, and it guarantees that the index in memory always describes the file on the card.

## State

| Variable | Meaning |
|---|---|
| `StDir$` | The database folder, ending in `/` |
| `StCol$` | The open collection (`""` if none) |
| `StErr$`, `StWarn$` | Last error; warnings from the last open |
| `StRdOpen%` | 1 while the data file is open for reading on `#1` |
| `StCat$()`, `StCatN%` | The collection list from the last `StList%` |
| `MtF$()`, `MtT$()`, `MtN%` | Field names seen and their kinds |
| `MtSeq%`, `MtDead%` | Auto-id counter, dead-line count |
| `MtUser$` | The `@user` metadata line (program-defined properties) |
| `MtDirty%` | Metadata changed since it was last saved |

`StPath$(ext$)` builds a file name: `StDir$ + StCol$ + ext$`.

## Collections

- `StList%()` fills `StCat$()` from `DIR$(StDir$ + "*.jsonl", FILE)` and sorts it.
- `StCreate%(n$)` writes an empty data file and a fresh `.meta`. If another collection is open it is closed first (because `MtSave` works on the open collection's variables) and reopened afterwards.
- `StDrop%(n$)` deletes all four possible files.
- `StNameOk%` allows letters, digits and `_`, up to 16 characters, so that every name is a valid file name and fits `StCat$()`.

## Opening a collection

```basic
FUNCTION StOpen%(n$)
  LOCAL ok%
  StErr$ = "" : StWarn$ = ""
  IF StNameOk%(n$) = 0 THEN EXIT FUNCTION
  IF StCol$ <> "" THEN StClose
  StCol$ = n$
  ' recover from a VACUUM interrupted between KILL and RENAME
  IF StExists%(StPath$(".vtmp")) THEN
    IF StExists%(StPath$(".jsonl")) THEN
      KILL StPath$(".vtmp")
    ELSE
      RENAME StPath$(".vtmp") AS StPath$(".jsonl")
      StKill StPath$(".idx")
    ENDIF
  ENDIF
  IF StExists%(StPath$(".jsonl")) = 0 THEN StErr$ = "no such collection" : StCol$ = "" : EXIT FUNCTION
  MtLoad
  StFixTail
  ok% = IxOpen%(StPath$(".jsonl"), StPath$(".idx"), ST_TMP)
  IF ok% THEN
    IF StVerify%() = 0 THEN
      StRdClose
      StKill StPath$(".idx")
      StWarnAdd "stale index rebuilt"
      ok% = IxOpen%(StPath$(".jsonl"), StPath$(".idx"), ST_TMP)
    ENDIF
  ENDIF
  IF ok% = 0 THEN StErr$ = IxErr$ : StRdClose : StCol$ = "" : IxClear : EXIT FUNCTION
  IF IxBad% > 0 THEN StWarnAdd STR$(IxBad%) + " bad line(s) skipped"
  StOpen% = 1
END FUNCTION
```

The steps, in order:

1. **Finish an interrupted vacuum.** A vacuum writes `.vtmp`, deletes `.jsonl`, then renames `.vtmp` to `.jsonl`. If `.vtmp` exists and `.jsonl` does not, the power failed between the last two steps: finish the rename. If both exist, the copy was incomplete: delete it.
2. **Load metadata** (`MtLoad`). This also sets `SxF$()`, the indexed fields, so the secondary indexes are built on open.
3. **Repair a torn tail** (`StFixTail`). If the file does not end with a line feed, the last write was cut off. A line break is appended, so the broken fragment stays a separate (skipped) line instead of being glued onto the next record.
4. **Build the index** (`IxOpen%`: load the saved index, scan the new tail, rebuild secondary indexes).
5. **Verify** (`StVerify%`). Eight entries spread through the index are read back; each must be a live record with the expected `_id`. A file edited by another program, even to the same length, almost always fails this check, and the index is rebuilt from scratch.

Warnings collect in `StWarn$` (`StWarnAdd`) for the caller to show.

`StFlush` saves metadata (if dirty) and the primary index with the current file length; `StClose` flushes and clears the state.

## Reading

```basic
FUNCTION StRead$(off%)
  IF StRdOpen% = 0 THEN
    OPEN StPath$(".jsonl") FOR INPUT AS #ST_RD : StRdOpen% = 1
  ENDIF
  StRead$ = IxReadAt$(ST_RD, off%)
END FUNCTION
```

The data file stays open on `#1` between reads, so walking through many records does not open and close the file each time. It is closed (`StRdClose`) before any write, and reopened on the next read, so reads always see what was written.

`StAt$(i%)` reads the record at index position `i%` (`_id` order), and `StFetch$(id$)` looks the `_id` up first.

## Writing a record

Every change goes through `StWrite%` (or `StDelete%`), which validates everything **before** touching the file:

```basic
FUNCTION StWrite%(rec$, md%)
  LOCAL id$, oo%, old$, off%
  StErr$ = ""
  IF StCol$ = "" THEN StErr$ = "no collection open" : EXIT FUNCTION
  IF RcCheck%(rec$) < 0 OR INSTR(rec$, CHR$(10)) OR INSTR(rec$, CHR$(13)) THEN
    StErr$ = "bad record" : EXIT FUNCTION
  ENDIF
  id$ = RcGet$(rec$, "_id")
  IF RcFound% = 0 OR RcT% <> 1 THEN StErr$ = "_id must be a string" : EXIT FUNCTION
  IF IxKeyOk%(id$) = 0 THEN StErr$ = IxErr$ : EXIT FUNCTION
  IF RcIsDel%(rec$) THEN StErr$ = "_del is reserved" : EXIT FUNCTION
  oo% = IxGet%(id$)
  IF md% = 1 AND oo% > 0 THEN StErr$ = "duplicate _id" : EXIT FUNCTION
  IF md% = 2 AND oo% < 0 THEN StErr$ = "not found" : EXIT FUNCTION
  IF oo% < 0 AND IxN% >= IX_MAX THEN StErr$ = "collection full" : EXIT FUNCTION
  IF oo% > 0 THEN old$ = StRead$(oo%)
  IF SxN% + StSxNeed%(rec$) - StSxNeed%(old$) > SX_MAX THEN
    StErr$ = "index space full" : EXIT FUNCTION
  ENDIF
  off% = StAppend%(rec$)
  IF IxApply%(rec$, off%, old$) = 0 THEN StErr$ = IxErr$ + " (reopen to rebuild)" : EXIT FUNCTION
  MtNote rec$
  IF oo% > 0 THEN INC MtDead% : MtDirty% = 1
  StWrite% = 1
END FUNCTION
```

1. The record must parse, contain no line breaks, and have a text `_id` that is a valid key. `_del` is reserved for tombstones.
2. The mode is enforced: `md%` = 1 insert only, 2 update only, 0 either.
3. **Capacity is checked first.** A new `_id` needs a free primary slot. For secondary entries, the old version's entries will be freed and the new version's added, so the net change is checked against `SX_MAX`. Because of this, `IxApply%` can never fail halfway through, which would leave the file and the index out of step.
4. Only then is the line appended (`StAppend%`, which returns the new line's offset from `LOC`), and the index updated.
5. `MtNote` records any new field names or kinds, and a replaced version counts as a dead line.

`StDelete%` appends a tombstone `{"_id":"…","_del":1}` and counts two dead lines (the old record and the tombstone).

`StSetField%(id$, f$, v$, t%)` is the convenience used by the explorer and the API: fetch the record, change one field with `RcSet$` (or remove it with `RcDel$` when `t% = 0`), and write it back in update mode.

### Automatic `_id`s

```basic
FUNCTION StNewId$()
  LOCAL k$
  DO
    INC MtSeq% : MtDirty% = 1
    k$ = STR$(MtSeq%, 6, 0, "0")
  LOOP UNTIL IxGet%(k$) < 0
  StNewId$ = k$
END FUNCTION
```

Ids are the counter `MtSeq%` zero-padded to 6 digits, so `_id` order is insertion order. The loop skips any number already used (for example after a crash lost the saved counter).

## Metadata

- `MtNote rec$` walks a record's fields with `RcNext%`. Each field not starting with `_` or `@` is added to `MtF$()` with its kind (`S`, `N`, `L` or `O`); a field seen with two different kinds becomes `X`. At most `MT_MAX` names are kept.
- `MtLoad` and `MtSave` read and write the `.meta` lines described in [Data format](Data-Format.md#metadata-namemeta). `MtSave` writes the whole file each time; it is small.
- `MtUser$` holds program-defined properties as a record string, so the API reads and writes them with the ordinary codec functions.

## Vacuum

```basic
FUNCTION StVacuum%()
  LOCAL i%, r$
  StErr$ = ""
  IF StCol$ = "" THEN StErr$ = "no collection open" : EXIT FUNCTION
  StRdClose
  OPEN StPath$(".vtmp") FOR OUTPUT AS #ST_WR
  OPEN StPath$(".jsonl") FOR INPUT AS #ST_RD
  FOR i% = 0 TO IxN% - 1
    PRINT #ST_WR, IxReadAt$(ST_RD, IxO%(i%))
  NEXT
  CLOSE #ST_RD : CLOSE #ST_WR
  KILL StPath$(".jsonl")
  RENAME StPath$(".vtmp") AS StPath$(".jsonl")
  StKill StPath$(".idx")
  MtDead% = 0 : MtDirty% = 1
  IF IxOpen%(StPath$(".jsonl"), StPath$(".idx"), ST_TMP) = 0 THEN StErr$ = IxErr$ : EXIT FUNCTION
  StFlush
  StVacuum% = 1
END FUNCTION
```

Live records are copied in `_id` order to `.vtmp` (reading by offset, so dead lines are simply never visited). Then the old file is deleted, `.vtmp` renamed, the stale `.idx` deleted, the index rebuilt from the new file, and everything flushed. Recovery from a power cut at any point is handled by step 1 of opening.

## Index administration

- `StIndexAdd%(f$)` puts the field in a free slot of `SxF$()` and rebuilds the secondary pool from the file. If that fails (the pool is full), the slot is cleared and the pool rebuilt without it.
- `StIndexDrop%(f$)` clears the slot and removes its entries from the pool in one pass. It does not need to read the file.

Both mark the metadata dirty, so the change is saved with the next flush.

---
Previous: [Indexes](Indexes.md) · Next: [Query parser](Query-Parser.md)
