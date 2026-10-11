# PicoCalc DB

A small document database for the [PicoCalc](https://www.clockworkpi.com/picocalc), written in PicoMite MMBasic, with three ways to use it:

- **Explorer (dbapp):** browse, search and edit collections of records with the keyboard, or with a small SQL dialect.
- **Library (dblib):** use the same collections from your own PicoMite programs through a `Db…` API.
- **Almanac:** an application built on the library that loads an almanac from a CSV file and lets you browse it by day and search it.

Data is stored as plain [JSON Lines](https://jsonlines.org/) files on the SD card, one record per line, so it can also be read and edited on a PC.

## Quick start

All three need a PicoCalc running PicoMite MMBasic, and an SD card.

**Explorer**

1. Copy `dist/dbapp_min.bas` to the SD card, and the `sdcard/db` folder (it holds the help topics) to the card's root.
2. At the `>` prompt: `DRIVE "B:"` then `RUN "dbapp_min.bas"`.

**Almanac**

1. Copy `dist/almanac_app.bas` and `sdcard/almanac.csv` to the root of the SD card.
2. Run `almanac_app.bas`, choose **1 Maintain database**, then **C** to load the CSV.

**Library**

Copy `dist/dblib.bas` next to your program and add `#INCLUDE "dblib.bas"` near its top, or load `dist/dblib_min.bas` and type `LIBRARY SAVE` to keep it in flash for every program. See the [library reference](docs/user/library-reference.md) and the [examples](examples/).

## Repository layout

```
src/                  BASIC modules: the files to edit
  dbcore.bas            record codec and indexes
  dbstore.bas           storage engine and metadata
  dbquery.bas           query tokenizer and parser
  dbexec.bas            query executor
  dbapi.bas             library API (Db…)
  dbhal.bas             display and keyboard layer
  dbgui.bas             explorer screens
  dbmain.bas            explorer entry point
  almanac.bas           almanac application
dist/                 generated, ready-to-run files
  dbapp.bas, dbapp_min.bas        explorer (with / without comments)
  dblib.bas, dblib_min.bas        library
  almanac_app.bas                 almanac
sdcard/               files to copy to the SD card, in the card's layout
  db/help/dbhelp.jsonl            explorer help topics
  db/plants.csv                   sample data for examples/ex2_import_csv.bas
  almanac.csv                     almanac data (Oct 2026 to Dec 2027)
examples/             three example programs using the library
docs/user/            user guides
docs/dev/             developer guides (wikis)
tests/                automated tests, run on a PC with MMB4L
tools/                build.py, run_tests.py, make_help.py
```

## Documentation

| For | Read |
|---|---|
| Using the explorer | [Explorer user guide](docs/user/dbapp-user-guide.md) |
| Writing programs with the library | [Library reference](docs/user/library-reference.md) |
| Using the almanac | [Almanac user guide](docs/user/almanac-user-guide.md) |
| How the database and explorer code works | [Developer guide: dbapp](docs/dev/dbapp/Home.md) |
| How the almanac code works | [Developer guide: almanac](docs/dev/almanac/Home.md) |

## Working on the code

Edit the modules in `src/`, then regenerate `dist/`:

```
python3 tools/build.py
```

The tests run on a PC in [MMB4L](https://github.com/thwill1000/mmb4l), the Linux port of MMBasic. Set `MMBASIC` to the interpreter's path, then:

```
python3 tools/run_tests.py            # all suites
python3 tools/run_tests.py api gui    # selected suites
```

`tools/make_help.py` regenerates the explorer's help topics.

## Status

The code has been developed and tested on a PC with MMB4L, and its use of PicoMite-specific features was checked against the PicoMite firmware source. It has not yet been run on a real PicoCalc: speed on the SD card, memory use on an RP2040 Pico, and the screen colours still need confirming on the device.
