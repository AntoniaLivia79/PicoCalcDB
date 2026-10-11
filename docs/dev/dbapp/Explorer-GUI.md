[Home](Home.md) › Explorer GUI

# Explorer GUI (`dbgui.bas`, `dbhal.bas`, `dbmain.bas`)

The explorer is a keyboard-driven, character-cell user interface over the engine. It reads records through the storage engine and runs SQL through the executor, like any other client.

## The display layer: `dbhal.bas`

The GUI never draws pixels or reads the keyboard itself. It calls four routines and two variables:

| Name | Does |
|---|---|
| `HalInit` | Selects the font, computes `HalW%` × `HalH%` (character columns × rows), sets the colours |
| `HalCls` | Clears the screen |
| `HalText c%, r%, s$, st%` | Draws `s$` at column `c%`, row `r%` in style `st%` |
| `HalKey%()` | Waits for a key and returns its code |

```basic
SUB HalText c%, r%, s$, st%
  IF s$ = "" THEN EXIT SUB
  TEXT c% * HalFW%, r% * HalFH%, s$, "LT", HAL_FONT, 1, HalFg%(st%), HalBg%(st%)
END SUB
```

Styles are indexes into the colour arrays `HalFg%()`/`HalBg%()`: 0 normal, 1 title bar, 2 selection, 3 message, 4 error, 5 hint bar, 6 dim text, 7 heading (6 and 7 are used by the almanac). The font is `HAL_FONT`: font 1 gives 40 × 26 cells on the PicoCalc's 320 × 320 screen, font 7 gives 53 × 40.

Key codes are PicoMite's: arrows 128–131, Home 134, End 135, PgUp/PgDn 136/137, F1 145, F2 146, Enter 13, Esc 27, Backspace 8. Delete is **212 on the PicoCalc** build of the firmware and 127 elsewhere, so the GUI accepts both (`UK_DEL`, `UK_DEL2`).

Because everything goes through these routines, the GUI can be moved to another screen by replacing this one file, or driven by a stand-in that records the screen as text.

## Program entry: `dbmain.bas`

```basic
' =====================================================================
' dbmain.bas - program entry. Load order: dbcore, dbstore, dbquery,
' dbexec, dbhal, dbgui, then this file (dbapp.bas is all of them
' merged; dbapp_min.bas is the same without comments, to save space).
' =====================================================================
StDir$ = "B:/db/"                 ' database folder on the SD card
ON ERROR SKIP 1
MKDIR "B:/db"
UiMain
END
```

`UiMain` initialises the display, lists the collections, then runs `UiStep` until `UiQuit%` is set:

```basic
SUB UiStep
  LOCAL k% = HalKey%()
  IF UiMsg$ <> "" THEN UiSay "", US_N
  UiKey k%
  UiPaint
END SUB
```

One key press is one step: clear the previous message, handle the key, repaint.

## Screen layout

```
row 0          title bar        UiTitle$()
rows 1..H-3    list             UiDrawRow / UiRowText$()
row H-2        message / input  UiSay, UiInput$, UiAsk%
row H-1        key hints        UiHints$()
```

`UiLine r%, s$, st%` draws a full-width line: it truncates or pads `s$` to `HalW%`, so each row is drawn completely with one `TEXT` call and no separate clearing is needed. `UiClean$` replaces control characters, which could otherwise upset the display.

## Views

The explorer is a small state machine. `UiV%` is the current view:

| View | Constant | List items |
|---|---|---|
| Collections | `UV_COLL` | `StCat$()` |
| Records | `UV_RECS` | records of the open collection |
| Record detail | `UV_DET` | fields of `DtRec$` |
| Text | `UV_TEXT` | `ExOut$()`: describe, query text, help topics |
| Help topics | `UV_HELP` | `HpTitle$()` |

Every view is a list, so the drawing and navigation code is shared. Each view keeps its own selection and scroll position in `UiSel%(v)` and `UiTop%(v)`, so returning to a view puts the cursor where it was. Three functions hide the differences between views:

- `UiCount%()`: number of items in the current view;
- `UiRowText$(i%)`: text of item `i%`;
- `UiTitle$()` and `UiHints$()`: the top and bottom lines.

### Records: all, or a query result

The records view shows either the whole collection in `_id` order, or the result of a filter or SELECT:

```basic
FUNCTION UiOff%(i%)
  IF UiRes% THEN UiOff% = ExR%(i%) ELSE UiOff% = IxO%(i%)
END FUNCTION
```

`UiRes%` selects the source: the executor's result offsets `ExR%()` or the primary index `IxO%()`. Either way the list holds offsets, and a row's text is built when it is drawn (`UiPreview$`: the `_id`, then `name:value` pairs that fit). Only the visible rows are ever read from the card, so a 1,000-record collection scrolls as fast as a 10-record one.

After a write, a result list may point at old versions, so `UiReload` re-runs the stored query (`UiQuery$`). `UiFind%(id$)` then finds the record's new row by comparing offsets with `IxGet%`, which needs no file reads.

## Painting only what changed

Redrawing the whole screen on the PicoCalc's SPI display is slow enough to see, so `UiPaint` redraws as little as possible:

```basic
SUB UiPaint
  LOCAL i%, n% = UiCount%(), h% = UiBodyH%(), v% = UiV%
  IF UiSel%(v%) > n% - 1 THEN UiSel%(v%) = n% - 1
  IF UiSel%(v%) < 0 THEN UiSel%(v%) = 0
  IF v% = UV_TEXT THEN
    IF UiSel%(v%) > MAX(0, n% - h%) THEN UiSel%(v%) = MAX(0, n% - h%)
    UiTop%(v%) = UiSel%(v%)
  ELSE
    IF UiSel%(v%) < UiTop%(v%) THEN UiTop%(v%) = UiSel%(v%)
    IF UiSel%(v%) >= UiTop%(v%) + h% THEN UiTop%(v%) = UiSel%(v%) - h% + 1
    IF UiTop%(v%) > MAX(0, n% - h%) THEN UiTop%(v%) = MAX(0, n% - h%)
  ENDIF
  IF UiPV% <> v% OR UiPTop% <> UiTop%(v%) THEN UiFull% = 1
  UiLine 0, UiTitle$(), US_TITLE
  IF UiFull% THEN
    FOR i% = UiTop%(v%) TO UiTop%(v%) + h% - 1 : UiDrawRow i% : NEXT
    UiLine HalH% - 2, UiClean$(LEFT$(UiMsg$, HalW%)), UiMsgSt%
    UiLine HalH% - 1, UiHints$(), US_HINT
  ELSEIF UiPSel% <> UiSel%(v%) THEN
    UiDrawRow UiPSel%
    UiDrawRow UiSel%(v%)
  ENDIF
  UiFull% = 0 : UiPV% = v% : UiPSel% = UiSel%(v%) : UiPTop% = UiTop%(v%)
END SUB
```

- It first clamps the selection and scrolls so that it is visible.
- If the view or the scroll position changed, or something set `UiFull% = 1`, it redraws all rows plus the message and hint lines.
- Otherwise only the previously selected row and the newly selected row are redrawn (moving the highlight), plus the title, which shows the position.

Any code that changes what is listed (editing, deleting, a new query, a prompt that used the message row) sets `UiFull% = 1`. `UiPV%`, `UiPSel%` and `UiPTop%` remember the last painted state.

## Keys

```basic
SUB UiKey k%
  IF k% >= 97 AND k% <= 122 THEN k% = k% - 32
  IF k% = UK_DEL2 THEN k% = UK_DEL
  IF UiV% <> UV_DET THEN
    IF k% = UK_LT THEN k% = UK_PU
    IF k% = UK_RT THEN k% = UK_PD
  ENDIF
  IF UiNav%(k%) THEN EXIT SUB
  IF k% = UK_F1 THEN UiHelp : EXIT SUB
  IF k% = UK_F2 OR k% = 47 THEN UiConsole : EXIT SUB
  SELECT CASE UiV%
    CASE UV_COLL : UiKeyColl k%
    CASE UV_RECS : UiKeyRecs k%
    CASE UV_DET : UiKeyDet k%
    CASE UV_HELP
      IF k% = UK_ENT THEN HpShow UiSel%(UV_HELP)
      IF k% = UK_ESC THEN UiGo HpBackV%
    CASE ELSE
      IF k% = UK_ESC OR k% = UK_ENT THEN UiGo UiBackV%
  END SELECT
END SUB
```

Keys are normalised (lower-case letters to upper case, both Delete codes to `UK_DEL`; Left/Right become page keys in the lists), then handled in a fixed order: navigation (`UiNav%`, shared by all views), F1 help, F2 or `/` console, and finally the current view's handler (`UiKeyColl`, `UiKeyRecs`, `UiKeyDet`).

Prompts are **modal**: `UiInput$` (a line editor with cursor movement and, for the console, an 8-entry history) and `UiAsk%` (y/n) call `HalKey%` themselves until they finish, then set `UiFull%` so the message row is restored.

## Editing records

The detail view shows `DtRec$`, a copy of the record. `DtField%(i%, …)` finds field `i%` by walking `RcNext%` from the start each time. That is quadratic in the number of fields, but a record has at most a few dozen, and it avoids storing a parsed copy.

Saving goes through `UiSave`, which calls `StSetField%`, re-reads the record, reloads the list and re-finds the record's row. The type of an edited value comes from `UiType%`:

```basic
FUNCTION UiType%(v$, ot%)
  UiType% = 1
  IF ot% = 1 THEN EXIT FUNCTION
  IF LEN(v$) >= 2 AND LEFT$(v$, 1) = "'" AND RIGHT$(v$, 1) = "'" THEN
    v$ = MID$(v$, 2, LEN(v$) - 2) : EXIT FUNCTION
  ENDIF
  IF RcLit%(v$) THEN UiType% = 2
END FUNCTION
```

A field that was text stays text, so an edit cannot accidentally turn the code `0123` into the number 123. Otherwise a valid literal is stored as one, and `'quotes'` force text. In the list, text that looks like a literal is shown in quotes so the difference is visible.

## The SQL console

`UiConsole` reads a statement with `UiInput$` and runs it with `ExRun%`:

- **ROWS** become the records view's source (`UiRes% = 1`, `UiQuery$` = the statement). The SELECT list becomes `UiCols$`, so only those fields are previewed.
- **COUNT** and **OK** results go to the message line. The message is saved *before* refreshing any list, because the refresh runs another query that overwrites `ExMsg$`.
- **TEXT** results open the text view.

A command may have changed or dropped collections, so the console refreshes the collection list and, if needed, the open view.

## Help

F1 runs `UiHelp`: it asks for words and calls `HpFind%`, which reads `help/dbhelp.jsonl` line by line. For each topic, a bitmask (`mask%`) records which search words have been found in its title, keywords or text. A topic is listed when all bits are set (`full% = (1 << nw%) - 1`), so words can match in different paragraphs. `HpShow` gathers a topic's paragraphs and word-wraps them into `ExOut$()` with `UiWrap`, then opens the text view.

If the help folder is missing, `DIR$` raises an error rather than returning `""`, so the existence test is wrapped in `ON ERROR SKIP` with a sentinel value. Without a help file, `UiHelpKeys` shows a built-in key summary.

---
Previous: [Executor](Executor.md) · Next: [Library and API](Library-and-API.md)
