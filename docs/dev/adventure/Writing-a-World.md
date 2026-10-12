[Home](Home.md) › Writing a world

# Writing a world

A world is one text file of JSON Lines: one record per line. Blank lines and lines starting with `#` are ignored, so the file can be commented. Starting a new game drops the `adv` collection and loads every record from the file. A line that is not a valid record stops the load with its line number (`line 12: bad record`).

The sample world, `sdcard/adv/world.jsonl`, uses every feature described here.

## Record types

The `_id` prefix says what a record is. Ids are at most 16 characters.

### Game state: `s.game` (required)

```
{"_id":"s.game","at":"r.beach","moves":0,"score":0,"title":"The Lighthouse","intro":"A storm is coming..."}
```

`at` is the starting room. `title` and `intro` are shown when a game starts. The framework keeps the current room, moves and score in this record as the game is played. Flags go in a separate record, `s.flags`, which is created automatically.

### Rooms: `r.<name>`

```
{"_id":"r.tower","name":"Lighthouse tower","desc":"The ground floor of the tower...","w":"r.beach","u":"r.lantern"}
```

`name` is the heading and `desc` the description. The exits are the fields `n`, `s`, `e`, `w`, `u`, `d`, each holding the `_id` of the room it leads to. An exit can be added or removed during play by a rule (see `exit:` below). That is how a locked door opens.

### Items: `i.<name>`

```
{"_id":"i.matches","name":"a box of matches","words":"matches box match","loc":"r.cottage","desc":"A few dry matches rattle inside."}
{"_id":"i.desk","name":"a heavy desk","words":"desk drawer","loc":"r.cottage","fixed":true,"desc":"An old oak desk with a single drawer."}
```

| Field | Meaning |
|---|---|
| `name` | How it is listed: "You can see **a box of matches**." |
| `words` | Words the player may use for it, separated by spaces. Its name after `i.` always works too |
| `loc` | Where it is: a room `_id`, `player` (carried), or `nowhere` (not yet in the game) |
| `desc` | Shown by `examine` |
| `fixed` | `true` for scenery: never listed, cannot be taken. Describe it in the room's `desc` instead |

Items in `nowhere` can be brought into play by a rule (`move:key>here`), which is how hidden things are found.

### Vocabulary: `w.<word>`

```
{"_id":"w.get","is":"take"}
```

A synonym: the player's word is replaced by `is` before anything else happens. Synonyms work for every verb, including the built-in ones (`l`, `x`, `i` in the sample are synonyms for `look`, `examine`, `inventory`).

### Rules

```
{"_id":"a.05","verb":"unlock","noun":"door","if":"have:key;!flag:door_open",
 "do":"set:door_open;exit:tower.d>cellar","say":"The door swings open...","no":"The door is locked. You need a key."}
```

(One line in the file.) Any `_id` will do; rules are tried in `_id` order, so give them sortable ids such as `a.01`, `a.02` …

| Field | Meaning |
|---|---|
| `verb` | The verb, after synonyms are applied |
| `noun` | The item's name after `i.` (`door` for `i.door`), whichever word the player used for it. It can also be any word (`xyzzy`). Omit it for rules about a verb on its own |
| `if` | Conditions, all of which must hold (optional) |
| `do` | Effects, applied in order (optional) |
| `say` | Shown when the rule runs |
| `no` | Shown when no rule for this verb and noun can run (optional) |

#### How rules are chosen

For each command, the rules with its verb and noun are tried in `_id` order:

1. **The first rule whose conditions hold runs:** its `say` is shown and its `do` is applied.
2. **If none runs**, the first `no` message among them is shown.
3. **If none runs and none has a `no` message**, the command falls through to the built-in verbs.

This makes common patterns short:

- **State-dependent responses:** several rules for one command, from most to least specific (`fill lamp` with oil, then `fill lamp` when already full).
- **Overriding a built-in verb in one situation only:** the sample's `take key` rule awards points the first time. Afterwards its condition fails and it has no `no` message, so `take key` falls through to the ordinary `take`.
- **Blocking a direction with a message:** a `go` rule with noun `d` (directions are `n s e w u d`).

#### Conditions (`if`)

Separated by `;`. Put `!` in front of any condition to negate it.

| Condition | Holds when |
|---|---|
| `have:key` | `i.key` is carried |
| `here:key` | `i.key` is carried or in the current room |
| `at:tower` | The player is in `r.tower` |
| `flag:door_open` | The flag is set |

#### Effects (`do`)

Separated by `;`.

| Effect | Does |
|---|---|
| `set:door_open` / `clear:door_open` | Sets / clears a flag |
| `move:key>here` | Moves `i.key` to a room (`move:key>cellar`), `here`, `player` or `nowhere` |
| `exit:tower.d>cellar` | Gives `r.tower` an exit `d` to `r.cellar`; `exit:tower.d>` removes it |
| `go:cellar` | Moves the player to `r.cellar` and describes it |
| `look` | Describes the current room |
| `score:10` | Adds to the score |
| `end:win` / `end:lose` | Ends the game: shows the result and score, and offers a new game |

## Checklist for a new world

- **One `s.game` record**, whose `at` names an existing room.
- **Exits name rooms that exist.** An exit to a missing room leaves the player nowhere.
- **Every item `loc` is a room, `player` or `nowhere`.**
- **Each line is at most 255 characters**, and each `_id` at most 16. Long descriptions don't fit: say more in `examine` text, or in rules.
- **Rule order matters.** Put specific rules before general ones for the same verb and noun.
- **Test as you write.** The explorer can open the `adv` collection to inspect flags and item locations during play, and the game can be restarted with `restart`.
