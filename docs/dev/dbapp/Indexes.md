[Home](Home.md) › Indexes

# Indexes (`dbcore.bas`, `Ix…` and `Sx…`)

The open collection has two kinds of in-memory index, both kept as **sorted arrays** and searched by binary search. There are no trees: insertion shifts array elements, and bulk building uses MMBasic's built-in `SORT`, which is fast because it runs in C.

## The primary index

| Array | Holds |
|---|---|
| `IxK$(i)` | The `_id` of record `i`, sorted (`LENGTH IX_KLEN`) |
| `IxO%(i)` | The offset of that record's current line |
| `IxN%` | Number of entries in use (= live records) |

So `IxK$()` is also the list of all live records in `_id` order: browsing a collection is a walk over these arrays.

### Binary search

One function serves every sorted array in the engine (primary keys and secondary values), because MMBasic can pass arrays to a FUNCTION:

```basic
FUNCTION IxBound%(a$(), n%, k$, gt%)
  LOCAL lo% = 0, hi% = n%, m%
  DO WHILE lo% < hi%
    m% = (lo% + hi%) \ 2
    IF a$(m%) < k$ OR (gt% AND a$(m%) = k$) THEN
      lo% = m% + 1
    ELSE
      hi% = m%
    ENDIF
  LOOP
  IxBound% = lo%
END FUNCTION
```

It returns the first position whose key is `>= k$` (`gt% = 0`) or `> k$` (`gt% = 1`). With those two bounds every lookup is a range:

- `IxGet%(k$)`: lower bound; a hit if the key there equals `k$`.
- `IxRange op$, k$, lo%, hi%`: rows `lo%` to `hi% - 1` satisfy `_id op k$`. For `=` it is `[lower, upper)`; for `>` it is `[upper, IxN%)`, and so on.

### Updates

`IxPut%` updates the offset in place if the key exists. Otherwise it shifts the tail of both arrays up by one and inserts. `IxRemove%` shifts down. A single insert therefore costs up to `IxN%` element moves, which is fine one record at a time but far too slow for loading a whole file; that uses the bulk path below.

`IxKeyOk%` rejects keys that are empty, longer than `IX_KLEN`, or contain CR, LF or TAB (they would break the `.idx` file).

## Secondary indexes

Up to `SX_SLOTS` (4) fields can be indexed. Rather than one array per field (which would need memory reserved for each), **all indexed fields share one sorted pool**:

| Array | Holds |
|---|---|
| `SxF$(s)` | The field indexed in slot `s` (`""` = unused) |
| `SxV$(i)` | An encoded key: slot letter + type letter + value prefix |
| `SxO%(i)` | The offset of the record the entry belongs to |
| `SxN%` | Entries in use |

### Key encoding

```basic
FUNCTION SxEnc$(s%, v$, t%)
  LOCAL n!, e%
  IF t% = 2 AND RcIsNum%(v$) THEN
    n! = VAL(v$)
    IF n! > 4.9E10 THEN n! = 4.9E10
    IF n! < -4.9E10 THEN n! = -4.9E10
    e% = INT(n!) + 50000000000
    SxEnc$ = CHR$(65 + s%) + "N" + RIGHT$("00000000000" + STR$(e%), SX_PW)
  ELSE
    SxEnc$ = CHR$(65 + s%) + "S" + LEFT$(v$, SX_PW)
  ENDIF
END FUNCTION
```

A key is `CHR$(65 + slot)` (`A` for slot 0, `B` for slot 1 …), then `N` for numbers or `S` for anything else, then 11 characters:

- **Numbers** become `floor(n) + 5E10`, zero-padded to 11 digits, after clamping to ±4.9E10. Zero-padding makes string order equal numeric order, so one string `SORT` serves both types.
- **Text** keeps its first 11 characters.

Because the slot letter comes first, each field's entries are one contiguous block of the pool, and inside it numbers (`N`) sort before text (`S`).

### Lossy keys and re-checking

The encoding throws information away: `2.25` and `2.75` both encode as `2`, and two texts sharing their first 11 characters encode the same. An index lookup therefore returns **candidates**, and the caller must re-test each candidate record against the real condition. The executor always does this.

The ranges are chosen so that no matching record is ever missed. `SxRange` computes them:

```basic
SUB SxRange s%, op$, v$, t%, lo%, hi%
  LOCAL k$, p$, rs%, re%
  k$ = SxEnc$(s%, v$, t%)
  p$ = LEFT$(k$, 2)
  rs% = IxBound%(SxV$(), SxN%, p$, 0)
  re% = IxBound%(SxV$(), SxN%, LEFT$(p$, 1) + CHR$(ASC(MID$(p$, 2)) + 1), 0)
  lo% = rs% : hi% = re%
  SELECT CASE op$
    CASE "="        : lo% = IxBound%(SxV$(), SxN%, k$, 0) : hi% = IxBound%(SxV$(), SxN%, k$, 1)
    CASE ">", ">="  : lo% = IxBound%(SxV$(), SxN%, k$, 0)
    CASE "<", "<="  : hi% = IxBound%(SxV$(), SxN%, k$, 1)
    CASE "LIKE"
      k$ = SxEnc$(s%, v$, 1)
      lo% = IxBound%(SxV$(), SxN%, k$, 0)
      hi% = IxBound%(SxV$(), SxN%, k$ + STRING$(SX_PW, 255), 1)
    CASE ELSE : lo% = -1 : hi% = -1
  END SELECT
END SUB
```

- It first finds the block for this slot and type (`rs%` to `re%`), so a range never runs into another field's entries.
- For `>` and `>=` it starts at the *lower* bound of the encoded value, and for `<` and `<=` it ends at the *upper* bound. These are conservative on purpose: with a lossy key, `> 2.5` must include everything encoded as `2`.
- `LIKE` takes the literal prefix of the pattern and returns every key starting with it (up to the prefix followed by `CHR$(255)` characters).
- `<>` returns `lo% = -1`, meaning "no useful range".

`SxAdd%` inserts with the *upper* bound, so equal keys stay in insertion order; `SxRemove%` searches the block of equal keys for the matching offset.

## Keeping the indexes in step: `IxApply%`

After the storage engine appends a line, it calls `IxApply%(rec$, off%, old$)`, passing the previous version of the record (or `""`):

```basic
FUNCTION IxApply%(rec$, off%, old$)
  LOCAL id$, v$, s%, oo%, ft%
  id$ = RcGet$(rec$, "_id")
  IF RcFound% = 0 THEN IxErr$ = "no _id" : EXIT FUNCTION
  IF IxKeyOk%(id$) = 0 THEN EXIT FUNCTION
  oo% = IxGet%(id$)
  IF oo% > 0 AND old$ <> "" THEN
    FOR s% = 0 TO SX_SLOTS - 1
      IF SxF$(s%) <> "" THEN
        v$ = RcGet$(old$, SxF$(s%)) : ft% = RcT%
        IF RcFound% THEN v$ = STR$(SxRemove%(s%, v$, ft%, oo%))
      ENDIF
    NEXT
  ENDIF
  IF RcIsDel%(rec$) THEN v$ = STR$(IxRemove%(id$)) : IxApply% = 1 : EXIT FUNCTION
  IF IxPut%(id$, off%) = 0 THEN EXIT FUNCTION
  FOR s% = 0 TO SX_SLOTS - 1
    IF SxF$(s%) <> "" THEN
      v$ = RcGet$(rec$, SxF$(s%)) : ft% = RcT%
      IF RcFound% THEN
        IF SxAdd%(s%, v$, ft%, off%) = 0 THEN EXIT FUNCTION
      ENDIF
    ENDIF
  NEXT
  IxApply% = 1
END FUNCTION
```

1. If there was an old version, its secondary entries are removed. They are found by encoding the *old* values with the *old* offset.
2. A tombstone removes the primary entry, and that is all.
3. Otherwise the primary entry is inserted or pointed at the new offset, and a secondary entry is added for each indexed field the record has.

The storage engine checks capacity *before* appending, so in normal use `IxApply%` cannot run out of room halfway (see [Storage engine](Storage-Engine.md#writing-a-record)).

## Building from the file

Opening a collection without a usable saved index means reading the whole data file. `IxScan%(fnum%, from%)` reads lines from offset `from%`:

```basic
FUNCTION IxScan%(fnum%, from%)
  LOCAL r$, id$, off%, frag% = 0
  IF from% > LOF(#fnum%) THEN IxScan% = 1 : EXIT FUNCTION
  SEEK #fnum%, from%
  DO WHILE NOT EOF(#fnum%)
    off% = LOC(#fnum%)
    r$ = IxLine$(fnum%)
    ' after an over-long line, its leftover tail comes back as the
    ' next "line": discard it too, it may look like a valid record
    IF IxLong% THEN
      INC IxBad% : frag% = 1
    ELSEIF frag% THEN
      frag% = 0
    ELSEIF RcCheck%(r$) < 0 THEN
      IF LEN(r$) > 0 THEN INC IxBad%
    ELSE
      id$ = RcGet$(r$, "_id")
      IF RcFound% AND LEN(id$) > 0 AND LEN(id$) <= IX_KLEN THEN
        IF IxN% >= IX_MAX THEN IxCompact
        IF IxN% >= IX_MAX THEN IxErr$ = "index full" : EXIT FUNCTION
        IxK$(IxN%) = id$
        IF RcIsDel%(r$) THEN IxO%(IxN%) = -off% ELSE IxO%(IxN%) = off%
        INC IxN%
      ELSE
        INC IxBad%
      ENDIF
    ENDIF
  LOOP
  IxCompact
  IxScan% = 1
END FUNCTION
```

- `LOC(#fnum%)` before each `LINE INPUT` gives the line's offset.
- It does not insert in order. Each line's `_id` and offset are simply **appended** to the arrays; a tombstone is stored with a **negative** offset. Duplicates (older versions) are allowed at this stage.
- If the arrays fill up, `IxCompact` squeezes them and the scan continues.
- Lines are read with `IxLine$`, which traps the fatal "line too long" error that `LINE INPUT` raises for lines over 255 characters. After such a line, `LINE INPUT` returns the rest of it as the next "line"; that fragment could look like a valid record, so it is skipped too (`frag%`).

Then `IxCompact` turns the raw list into the index:

```basic
SUB IxCompact
  LOCAL ix%(IX_MAX - 1), tmp%(IX_MAX - 1), i%, j%, w%, b%
  IF IxN% = 0 THEN EXIT SUB
  SORT IxK$(), ix%(), , 0, IxN%
  FOR i% = 0 TO IxN% - 1 : tmp%(i%) = IxO%(ix%(i%)) : NEXT
  i% = 0 : w% = 0
  DO WHILE i% < IxN%
    j% = i% : b% = tmp%(i%)
    DO WHILE j% + 1 < IxN%
      IF IxK$(j% + 1) <> IxK$(i%) THEN EXIT DO
      INC j%
      IF ABS(tmp%(j%)) > ABS(b%) THEN b% = tmp%(j%)
    LOOP
    IF b% > 0 THEN IxK$(w%) = IxK$(i%) : IxO%(w%) = b% : INC w%
    i% = j% + 1
  LOOP
  IxN% = w%
END SUB
```

1. `SORT IxK$(), ix%(), , 0, IxN%` sorts the keys and fills `ix%()` with each key's original position, so the offsets can be permuted to match.
2. For each run of equal keys, the entry with the largest absolute offset is the latest line, so it wins.
3. If the winner is negative (a tombstone), the record is deleted and dropped.

`SxRebuild%` then reads every live record (by offset) and builds the secondary pool the same way: append everything, then one `SORT` with an index array.

## Saving, loading and catching up

`IxSave%` writes the primary index with the data file's length; `IxLoad%` reads it back and **validates** every line (format, key rules, strictly increasing order). Any problem discards it, so the worst case is a rebuild, never a wrong index.

`IxOpen%` combines these:

```basic
FUNCTION IxOpen%(dpath$, ipath$, fnum%)
  LOCAL dl%, ok%
  IxClear
  dl% = IxLoad%(ipath$, fnum%)
  OPEN dpath$ FOR INPUT AS #fnum%
  IF dl% < 0 OR dl% > LOF(#fnum%) THEN IxN% = 0 : dl% = 0
  ok% = IxScan%(fnum%, dl% + 1)
  IF ok% THEN ok% = SxRebuild%(fnum%)
  CLOSE #fnum%
  IxOpen% = ok%
END FUNCTION
```

- A saved index covering `dl%` bytes of a file that is now longer is still valid for those bytes. Only the tail `dl% + 1 … LOF` is scanned, and `IxCompact` merges it in (later lines win, as always).
- If the file is now *shorter*, it was replaced or vacuumed, and the index is rebuilt from scratch.
- Secondary indexes are not saved; they are rebuilt from the records on every open.

A length check cannot detect a file edited elsewhere to the same length. The storage engine adds a spot check for that (`StVerify%`, see [Storage engine](Storage-Engine.md#opening-a-collection)).

---
Previous: [Record codec](Record-Codec.md) · Next: [Storage engine](Storage-Engine.md)
