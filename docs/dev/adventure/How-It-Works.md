[Home](Home.md) › How it works

# How it works

## One command, start to finish

The game loop, `GcRun`, reads a command with the view's `GvAsk$` and hands it to the controller:

```basic
SUB GcDo cmd$
  LOCAL id$, key$
  GcParse cmd$
  IF GcVerb$ = "" THEN GvSay "Pardon?" : EXIT SUB
  IF GcMeta%() THEN EXIT SUB
  key$ = GcNoun$
  IF GcNoun$ <> "" AND GcVerb$ <> "go" THEN id$ = GcFind$(GcNoun$)
  IF id$ <> "" THEN key$ = MID$(id$, 3)
  IF GcRules%(key$) = 0 THEN
    IF GcBuiltIn%(id$) = 0 THEN
      IF GcNoun$ = "" THEN
        GvSay "I don't know how to " + GcVerb$ + "."
      ELSEIF id$ = "" THEN
        GvSay "You can't see any " + GcNoun$ + " here."
      ELSE
        GvSay "You can't " + GcVerb$ + " that."
      ENDIF
    ENDIF
  ENDIF
  GmAddNum "moves", 1
  GmTidy
END SUB
```

1. **Parse** (`GcParse`): the command becomes a verb, a noun and an optional "with" noun.
2. **Meta commands** (`help`, `score`, `save`, `quit`, `restart`) are handled by `GcMeta%` and do not count as moves.
3. **Resolve the noun** to a visible item (`GcFind$`). The rules are looked up with the item's short name, so "open drawer" finds the rules for `desk` when `drawer` is one of the desk's words.
4. **Rules first** (`GcRules%`), then **built-in verbs** (`GcBuiltIn%`), then a "can't" message.
5. **Count the move** in the model, and let the model tidy its file.

## The controller (`adv_ctrl.bas`)

### Parsing

`GcParse` keeps only letters, digits and spaces, lower-cases them, drops `the`, `a` and `an`, and translates the first word through the vocabulary (`GmWord$`). Then:

- **Directions:** a direction alone (`n`, `north`) becomes `go n`.
- **"look at":** `look at x` becomes `examine x`, and a leading `at`, `to`, `in`, `into` or `on` is skipped.
- **Adjectives:** the noun is the **last** word before `with`, so adjectives are ignored: `take the brass lamp` → take / lamp.
- **"with":** the last word after `with` goes in `GcWith$` (`unlock door with key`). Rules usually check `have:key` instead of reading it.

Because the parser keeps only letters, digits and spaces, a command can never put a quote into the SQL queries built from it.

### Finding the item a word means

```basic
FUNCTION GcFind$(w$)
  LOCAL i%, n%, id$
  IF w$ = "" THEN EXIT FUNCTION
  n% = GmItemsAt%(GmAt$(), 0)
  n% = GmItemsAt%("player", 1)
  FOR i% = 0 TO n% - 1
    id$ = GmList$(i%)
    IF MID$(id$, 3) = w$ OR INSTR(" " + GmField$(id$, "words") + " ", " " + w$ + " ") THEN
      GcFind$ = id$ : EXIT FUNCTION
    ENDIF
  NEXT
END FUNCTION
```

The visible items are the room's and the player's, collected by two model queries. A word matches an item's short name or any of its `words`. The `" " + … + " "` padding makes `INSTR` match whole words only.

### The rule engine

```basic
FUNCTION GcRules%(key$)
  LOCAL i%, n%, r$, no$
  n% = GmRules%(GcVerb$, key$)
  FOR i% = 0 TO n% - 1
    r$ = DbRow$(i%)
    IF GcTest%(DbStr$(r$, "if")) THEN
      IF DbStr$(r$, "say") <> "" THEN GvSay DbStr$(r$, "say")
      GcEffects DbStr$(r$, "do")
      GcRules% = 1 : EXIT FUNCTION
    ENDIF
    IF no$ = "" THEN no$ = DbStr$(r$, "no")
  NEXT
  IF no$ <> "" THEN GvSay no$ : GcRules% = 1
END FUNCTION
```

`GmRules%` runs the query for this verb and noun (both indexed fields). The rows come back in `_id` order. The loop takes the first rule whose conditions hold, remembering the first `no` message in case none does. When no rule matches and there is no `no` message, `GcRules%` returns 0 and the built-in verbs get the command.

The rule is read into `r$` before its effects run. That matters because effects can start new queries, for example `look` lists the room's items, and a new query replaces `DbRow$`'s results.

```basic
FUNCTION GcTest%(c$)
  LOCAL i%, p$, k$, a$, neg%, ok%, l$
  FOR i% = 1 TO 12
    p$ = FIELD$(c$, i%, ";")
    IF p$ = "" THEN EXIT FOR
    neg% = (LEFT$(p$, 1) = "!")
    IF neg% THEN p$ = MID$(p$, 2)
    k$ = FIELD$(p$, 1, ":") : a$ = FIELD$(p$, 2, ":")
    SELECT CASE k$
      CASE "have" : ok% = (GmLoc$("i." + a$) = "player")
      CASE "here"
        l$ = GmLoc$("i." + a$)
        ok% = (l$ = "player") OR (l$ = GmAt$())
      CASE "at" : ok% = (GmAt$() = "r." + a$)
      CASE "flag" : ok% = GmFlag%(a$)
      CASE ELSE : ok% = 0
    END SELECT
    IF neg% THEN ok% = 1 - ok%
    IF ok% = 0 THEN EXIT FUNCTION
  NEXT
  GcTest% = 1
END FUNCTION
```

Conditions and effects are split with `FIELD$` (by `;`, then `:`), and an effect's target with `>` and `.`. Each condition is one model call (`GmLoc$`, `GmAt$`, `GmFlag%`), none of them a query, so testing a rule never disturbs the rule list being looped over.

### Built-in verbs

`GcBuiltIn%` implements `look`, `inventory`, `go`, `take`, `drop` and `examine` from the model's data alone:
- `go` reads the exit field of the current room;
- `take` refuses `fixed` items;
- `examine` shows `desc`.

`GcLook` builds the "You can see …" and "Exits: …" lists as `|`-separated strings and passes them to the view's `GvList`.

### The game loop

`GcRun` offers to continue if the collection holds a game (`GmHave%`), otherwise starts one (`GcNew%`). A game that has already been won or lost is never continued. The loop then reads and runs commands until `quit`, handling `restart` and the end of a game.

## The model (`adv_model.bas`)

The model wraps the `Db…` API in game terms, so the controller never builds a query or a record itself:

| Routine | Does |
|---|---|
| `GmNewGame%(world$)` | Drop and recreate the collection from a world file, then index `loc` and `verb` |
| `GmHave%()` | 1 if there is a game to continue (opens it) |
| `GmAt$()`, `GmSetAt` | The player's room |
| `GmNum%`, `GmAddNum` | Numbers in `s.game` (`moves`, `score`) |
| `GmFlag%`, `GmSetFlag` | Flags: fields of `s.flags` |
| `GmLoc$`, `GmMove` | Where an item is; move it |
| `GmExit$`, `GmSetExit` | Read and change a room's exits |
| `GmItemsAt%(loc$, add%)` | Item ids at a place, into `GmList$()` |
| `GmWord$(w$)` | Vocabulary lookup |
| `GmRules%(verb$, noun$)` | The rules for a command |
| `GmTidy`, `GmClose` | Compact the file when needed; close |

```basic
FUNCTION GmItemsAt%(loc$, add%)
  LOCAL i%
  IF add% = 0 THEN GmListN% = 0
  IF DbQuery%("SELECT * FROM " + GM_COL$ + " WHERE loc = '" + loc$ + "'") THEN
    FOR i% = 0 TO DbRows%() - 1
      IF GmListN% < GM_MAXL THEN GmList$(GmListN%) = DbStr$(DbRow$(i%), "_id") : INC GmListN%
    NEXT
  ENDIF
  GmItemsAt% = GmListN%
END FUNCTION
```

### Saving is the database's job

Each model call that changes something writes immediately (`DbSetText%`, `DbSetNum%`, `DbSetRaw%`). There is no save command and no save file: the collection *is* the saved game. The library's append-only storage makes every write crash-safe, so a game can be interrupted at any point and continued.

Every move appends at least one line (the move counter), so the file grows. `GmTidy` compacts it with `DbVacuum%` once there are more than 300 dead lines, which keeps the file a small multiple of the world's size however long the game runs.

```basic
SUB GmTidy
  LOCAL ok%
  IF DbDead%() > 300 THEN ok% = DbVacuum%()
END SUB
```

A new game is simply the world file loaded again: `GmNewGame%` drops the collection and inserts every record.

## The view (`adv_view.bas`)

| Routine | Does |
|---|---|
| `GvInit` | Works out the console width (`MM.HRES \ MM.INFO(FONTWIDTH)`), keeping 40 if it can't |
| `GvSay s$` | Word-wraps text to the width |
| `GvTitle s$` | A room heading |
| `GvList label$, items$, n%` | "label a, b and c." |
| `GvAsk$(prompt$)` | Reads a command |
| `GvOut s$` | One line of output: every other routine ends here |

`GvSay` wraps one character short of the console width, because the console starts a new line itself after a full-width line, which would leave a blank line.

### Capture mode

With `GvCap% = 1`, `GvOut` stores lines in `GvLog$()` instead of printing, and `GvAsk$` takes commands from `GvIn$()` (answering `quit` when they run out). A program can then play the game by itself and inspect what it printed. This is how the framework's tests work, and it is useful for checking a world: queue a walkthrough and look for the winning message.

## Extending the framework

### A new condition or effect

Add a `CASE` to `GcTest%` or `GcEffects`. For example, a `carry:` effect could move an item to the player only if there's room, or a `count` condition could compare a field of `s.game`. Keep the work in the model: add a `Gm…` routine if the effect needs new data access.

### A new built-in verb

Add a `CASE` to `GcBuiltIn%`. For example, `wait` could simply say "Time passes." Put the verb in the help text too. A world can still override it with rules, as it can any built-in verb.

### A different display

Change only `adv_view.bas`. For example, `GvTitle` could draw the room name in colour, or a status line could show the score: add a `GvStatus` routine, and call it from `GcRun` after each command, passing the text. The view must still not call the model.

### Naming your routines

MMBasic refuses a program in which a SUB or FUNCTION has the same name as a local variable anywhere ([MMBasic notes](../dbapp/MMBasic-Notes.md#names)). The library's locals are renamed to avoid this, but the framework's are not, because the framework is meant to be read and edited. Its locals are short names such as `cmd$`, `id$`, `r$` and `n%`. So give your own routines a prefix of their own (`MyScore`, `XxDraw`), never a bare word like `Cmd` or `Id`.
