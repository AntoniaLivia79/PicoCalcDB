[Home](Home.md) › Data model

# Data model

## One record per CSV row

```
CSV:    2026-10-01,Thu,Month,October - Old English 'Winterfylleth' ...,Bede's ...,"Good October, ...",England,fixed
record: {"_id":"2026-10-01.02","cat":"Month","event":"October - ...","detail":"Bede's ...",
         "place":"England","cert":"fixed","lore":"Good October, ..."}
```

| CSV column | Field | Notes |
|---|---|---|
| `date` | – | Part of the `_id` |
| `weekday` | – | Not stored; computed from the date ([Dates](Dates.md)) |
| `category` | `cat` | Omitted if empty |
| `event` | `event` | Always stored |
| `detail` | `detail` | Always stored; the field the search uses |
| `place` | `place` | Omitted if empty |
| `certainty` | `cert` | Omitted if empty |
| `saying_or_lore` | `lore` | Omitted if empty; may go in a companion record (below) |

## Why it is shaped this way

The library limits a record to 255 characters, and the supplied CSV was measured against that before the model was chosen. Stored with the CSV's own column names, 157 of its 854 rows would be too long, the longest by 100 characters. The model removes the waste without losing any text:

- **The date is in the `_id`**, so it isn't stored twice, and the weekday is computed.
- **Field names are short** (`cat`, `cert`), because every name is repeated in every record.
- With those changes all but 31 rows fit. The 31 that don't all have a long saying.

## The `_id`: date plus sequence

```
2026-10-01.01   2026-10-01.02   2026-10-02.01 ...
```

- **Ids sort by date**, because `YYYY-MM-DD` sorts correctly as text, and the two-digit sequence keeps a day's entries in file order (`.10` would sort before `.2` without the leading zero).
- **A day is one index range.** `_id LIKE '2026-10-01.%'` is answered from the primary index, reading only that day's records.
- **The first and last records give the date range** (`AmOpen%`).
- The sequence number is the lowest free one for that date, so rows sharing a date need not be next to each other in the CSV.

## Companion records for long sayings

When adding the saying would make a record too long, it goes in a second record whose `_id` is the first one plus `L`:

```
{"_id":"2027-07-01.01","cat":"Month","event":"July - Old English ...","detail":"Bede's ...",...}
{"_id":"2027-07-01.01L","lore":"If July's first day be rainy weather, 'twill rain more or less for four weeks."}
```

`L` sorts after the digits and before the next sequence number, so the companion comes straight after its record in `_id` order. A day's query returns both, in the right order. The browse screen shows a companion's saying under the entry before it, and the search ignores companions because they have no `detail`.

## Metadata

After an import, `AmImport%` stores properties in the collection's metadata with `DbMetaSet%`:

| Property | Example |
|---|---|
| `source` | `B:/almanac.csv` |
| `rows` | `854` |
| `first`, `last` | `2026-10-01`, `2027-12-31` |
| `loaded` | `11-10-2026 14:05` (from `DATE$` and `TIME$`) |

The Maintain screen shows `loaded` and `source`.

## Capacity

The supplied file makes 854 + 31 = 885 records. The library's default limit is 1,000 records per collection (`IX_MAX`), so at the supplied file's density of about 59 rows a month, roughly 17 months of data fit. An import stops with `collection full` at the limit.

---
Previous: [Program structure](Program-Structure.md) · Next: [CSV import](CSV-Import.md)
