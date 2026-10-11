# PicoCalc DB – Developer Guide

This wiki explains how the PicoCalc DB code works: the explorer application (**dbapp**), the database engine underneath it, and the **library** that lets other PicoMite BASIC programs use the same collections. It is written for someone who wants to read, change or extend the BASIC code.

For using the program, see the [user guide](../../user/dbapp-user-guide.md); for calling the library from a script, the [library reference](../../user/library-reference.md) is the quick reference.

## Pages

| Page | What it covers |
|---|---|
| [Architecture](Architecture.md) | Layers, modules, load order, naming, error conventions, memory |
| [Data format](Data-Format.md) | The files on the SD card and what each line means |
| [Record codec](Record-Codec.md) | `dbcore.bas` part 1: reading and editing JSON records as strings |
| [Indexes](Indexes.md) | `dbcore.bas` part 2: the primary and secondary indexes |
| [Storage engine](Storage-Engine.md) | `dbstore.bas`: collections, writes, recovery, metadata |
| [Query parser](Query-Parser.md) | `dbquery.bas`: tokenizer, grammar, the query plan |
| [Executor](Executor.md) | `dbexec.bas`: access paths, evaluation, sorting, writes |
| [Explorer GUI](Explorer-GUI.md) | `dbgui.bas`, `dbhal.bas`, `dbmain.bas`: screens, keys, painting, help |
| [Library and API](Library-and-API.md) | `dbapi.bas` and `dblib.bas`: the `Db…` API for other programs |
| [MMBasic notes](MMBasic-Notes.md) | PicoMite language behaviour the code is written around |
| [Extending](Extending.md) | Where to make common changes |

## The code at a glance

| File | Prefix | Lines | Role |
|---|---|---|---|
| `dbcore.bas` | `Rc` `Ix` `Sx` | 622 | Record codec and index manager |
| `dbstore.bas` | `St` `Mt` | 421 | Storage engine, catalogue, metadata |
| `dbquery.bas` | `Tk` `Q` | 545 | Query tokenizer and parser |
| `dbexec.bas` | `Ex` | 388 | Query executor |
| `dbapi.bas` | `Db` | 398 | Public API for other programs |
| `dbhal.bas` | `Hal` | 46 | Display and keyboard layer |
| `dbgui.bas` | `Ui` `Dt` `Hp` | 644 | Explorer screens |
| `dbmain.bas` | | 10 | Program entry |

`dbapp.bas` is the explorer (all modules except `dbapi.bas`, merged into one file) and `dblib.bas` is the library (`dbcore` + `dbstore` + `dbquery` + `dbexec` + `dbapi`). Both are generated from the module files, which are the ones to edit. In the repository the modules are in `src/` and the generated files in `dist/`.

## Reading order

If you are new to the code, read [Architecture](Architecture.md), then [Data format](Data-Format.md), then follow the layers upwards: codec → indexes → storage engine → parser → executor → GUI. Each layer only calls the ones below it.
