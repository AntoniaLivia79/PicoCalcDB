# Almanac – Developer Guide

The almanac is a PicoCalc application built on the PicoCalc DB library. It loads a CSV of almanac entries into a collection, then lets the user browse it day by day and search it. This wiki explains how its code (`almanac.bas`, 604 lines) works.

It assumes you know the library's API; the [library page of the dbapp guide](../dbapp/Library-and-API.md) explains it, and [MMBasic notes](../dbapp/MMBasic-Notes.md) covers the language behaviour referred to here. The user guide is the [almanac user guide](../../user/almanac-user-guide.md).

## Pages

| Page | What it covers |
|---|---|
| [Program structure](Program-Structure.md) | How the program is assembled, its state, and the flow between screens |
| [Data model](Data-Model.md) | How CSV rows become records, and why |
| [CSV import](CSV-Import.md) | Reading and parsing the CSV and loading the collection |
| [Dates](Dates.md) | Day numbers, validation, weekdays and formatting |
| [Screens](Screens.md) | Drawing, prompts, and each of the screens: menu, maintain, browse, search |
| [Extending](Extending.md) | Common changes |

## In one paragraph

`AmImport%` parses `B:/almanac.csv` and writes one record per row into the collection `almanac`, with ids made of the date and a sequence number (`2026-10-01.02`). Because ids sort by date, the browse screen fetches a day with one indexed lookup: `DbFind%("_id", "STARTS", "2026-10-01.")`. The search screen walks every record and checks the `detail` field itself, because the search must ignore upper/lower case and the library's text matching does not. Dates are handled as day numbers (days since 1970-01-01), so moving between days is plain arithmetic. All screen output goes through the library's display layer (`dbhal.bas`).
