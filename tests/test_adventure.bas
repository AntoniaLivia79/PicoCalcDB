' test_adventure.bas - tests for the adventure framework, using the
' view's capture mode (no keyboard or screen needed).
' Run: OPTION EXPLICIT + OPTION DEFAULT NONE + dblib_min.bas +
' adv_model.bas + adv_view.bas + adv_ctrl.bas + this file, in MMB4L,
' with sdcard/adv/world.jsonl copied to /tmp/advt/world.jsonl.

DIM Fail% = 0
RANDOMIZE 2468
CONST W$ = "/tmp/advt/world.jsonl"
SUB Bad m$
  PRINT "FAIL: "; m$ : INC Fail%
END SUB
' Is t$ in the output? (also across a line break made by wrapping)
FUNCTION Has%(t$)
  LOCAL i%
  FOR i% = 0 TO GvLogN% - 1
    IF INSTR(GvLog$(i%), t$) THEN Has% = 1 : EXIT FUNCTION
    IF i% < GvLogN% - 1 THEN
      IF INSTR(GvLog$(i%) + " " + GvLog$(i% + 1), t$) THEN Has% = 1 : EXIT FUNCTION
    ENDIF
  NEXT
END FUNCTION
SUB DumpLog
  LOCAL i%
  FOR i% = 0 TO GvLogN% - 1 : PRINT "   |"; GvLog$(i%) : NEXT
END SUB
SUB Expect t$, tag$
  IF Has%(t$) = 0 THEN Bad tag$ + ": [" + t$ + "] not in output" : DumpLog
END SUB
' One command, with its output captured fresh
SUB Turn c$
  GvLogN% = 0
  GcDo c$
END SUB
SUB CmdExpect c$, t$
  Turn c$
  Expect t$, c$
END SUB
' Queue commands (separated by |) for GcRun
SUB Queue s$
  LOCAL i%
  GvInN% = 0 : GvInP% = 0 : GvLogN% = 0
  FOR i% = 1 TO 60
    IF FIELD$(s$, i%, "|") = "" THEN EXIT FOR
    GvIn$(GvInN%) = FIELD$(s$, i%, "|") : INC GvInN%
  NEXT
END SUB

DIM i%, n%, ok%, s$, f$, id$
GvCap% = 1
DbInit "/tmp/advt"

PRINT "V1 new game"
GvLogN% = 0
IF GcNew%(W$) = 0 THEN Bad "new game: " + GmErr$
Expect "The Lighthouse", "title"
Expect "== Beach ==", "room heading"
Expect "You can see a soggy note.", "item list"
Expect "Exits: north and east.", "exit list"
IF GmAt$() <> "r.beach" OR GmNum%("score") <> 0 THEN Bad "start state"

PRINT "V2 parser and built-in verbs"
CmdExpect "read the soggy note", "Oil is kept below the tower"
CmdExpect "LOOK AT NOTE", "Something is written on it"
CmdExpect "x note", "Something is written on it"
CmdExpect "pick up the note", "Taken."
IF GmLoc$("i.note") <> "player" THEN Bad "note not carried"
CmdExpect "i", "You are carrying a soggy note."
CmdExpect "drop note", "Dropped."
CmdExpect "drop note", "You are not carrying it."
CmdExpect "", "Pardon?"
CmdExpect "dance", "I don't know how to dance."
CmdExpect "take unicorn", "You can't see any unicorn here."
CmdExpect "go west", "You can't go that way."
CmdExpect "go", "Go where?"
CmdExpect "take", "What do you want to take?"
CmdExpect "xyzzy", "A hollow voice says"
CmdExpect "eat note", "You can't eat that."
CmdExpect "score", "You have scored 0 in"

PRINT "V3 walkthrough"
CmdExpect "n", "== Keeper's cottage =="
Expect "You can see a box of matches.", "fixed desk not listed"
CmdExpect "take the desk", "You can't take that."
CmdExpect "get matches", "Taken."
CmdExpect "open drawer", "Inside is a small iron key."
CmdExpect "open desk", "The drawer is already open."
CmdExpect "take key", "Taken."
IF GmNum%("score") <> 5 THEN Bad "key score " + STR$(GmNum%("score"))
CmdExpect "drop key", "Dropped."
CmdExpect "take key", "Taken."
IF GmNum%("score") <> 5 THEN Bad "key scored twice"
CmdExpect "south", "== Beach =="
CmdExpect "e", "== Lighthouse tower =="
CmdExpect "d", "The door in the floor is locked."
CmdExpect "open door", "The door is locked."
CmdExpect "u", "== Lantern room =="
CmdExpect "light lamp", "The lamp is dry."
CmdExpect "fill lamp", "You have nothing to fill it with."
CmdExpect "d", "== Lighthouse tower =="
CmdExpect "unlock the door with the key", "the door swings open"
CmdExpect "unlock door", "It is already unlocked."
CmdExpect "open door", "It is already open."
CmdExpect "look", "Exits: west, up and down."
CmdExpect "down", "== Cellar =="
CmdExpect "take can", "Taken."
CmdExpect "u", "== Lighthouse tower =="
CmdExpect "u", "== Lantern room =="
CmdExpect "refill the great lamp", "You pour the oil"
IF GmLoc$("i.oil") <> "nowhere" THEN Bad "oil not used up"
CmdExpect "fill lamp", "The lamp is already full."
IF GcOver% THEN Bad "game over too early"
CmdExpect "ignite lamp", "the ship turns away from the rocks"
IF GcOver% = 0 THEN Bad "game not over after winning"
IF GmNum%("score") <> 50 THEN Bad "final score " + STR$(GmNum%("score"))
IF GmFlag%("end_win") = 0 THEN Bad "win flag"

PRINT "V4 game loop, saving and continuing"
' a finished game is not continued: a new one starts
Queue "y|quit"
GcRun W$
ok% = GmHave%()                 ' GcRun closes the game on quit: reopen it to check
Expect "Loading the world", "ended game restarts"
IF GmAt$() <> "r.beach" OR GcQuit% = 0 THEN Bad "after restart"
Queue "y|n|take matches|s|quit"
GcRun W$
ok% = GmHave%()                 ' GcRun closes the game on quit: reopen it to check
Expect "Welcome back.", "continue"
Expect "Your game is saved. Goodbye.", "quit"
n% = GmNum%("moves")
IF GmLoc$("i.matches") <> "player" OR GmAt$() <> "r.beach" THEN Bad "state before close"
GmClose
Queue "y|look|quit"
GcRun W$
ok% = GmHave%()                 ' GcRun closes the game on quit: reopen it to check
Expect "Welcome back.", "continue after close"
IF GmLoc$("i.matches") <> "player" OR GmAt$() <> "r.beach" THEN Bad "state not kept across close"
IF GmNum%("moves") <> n% + 1 THEN Bad "moves " + STR$(GmNum%("moves")) + " expected " + STR$(n% + 1)
Queue "n|quit"
GcRun W$
ok% = GmHave%()                 ' GcRun closes the game on quit: reopen it to check
IF GmLoc$("i.matches") <> "r.cottage" OR GmNum%("moves") <> 0 THEN Bad "declining continue should start afresh"
Queue "n|restart|quit"
GcRun W$
ok% = GmHave%()                 ' GcRun closes the game on quit: reopen it to check
IF GmAt$() <> "r.beach" THEN Bad "restart command"
Queue "y|e|u|quit"
GcRun W$
ok% = GmHave%()                 ' GcRun closes the game on quit: reopen it to check
IF GmAt$() <> "r.lantern" THEN Bad "moves via the loop"
' winning inside the loop, then declining another game
GcOver% = 0
IF GcNew%(W$) = 0 THEN Bad "new"
Queue "n|n|take matches|open desk|take key|s|e|unlock door|d|take oil|u|u|fill lamp|light lamp|n"
GcRun W$
ok% = GmHave%()                 ' GcRun closes the game on quit: reopen it to check
Expect "*** You have won ***", "win in loop"
Expect "You scored 50 in", "final score line"
IF GcQuit% = 0 THEN Bad "declining another game should quit"

PRINT "V5 bad world files"
OPEN "/tmp/advt/w1.jsonl" FOR OUTPUT AS #7 : PRINT #7, "{" + CHR$(34) + "_id" + CHR$(34) + ":" + CHR$(34) + "r.x" + CHR$(34) + "}" : CLOSE #7
IF GmNewGame%("/tmp/advt/w1.jsonl") OR INSTR(GmErr$, "no s.game") = 0 THEN Bad "missing s.game: " + GmErr$
OPEN "/tmp/advt/w2.jsonl" FOR OUTPUT AS #7 : PRINT #7, "# comment" : PRINT #7, "" : PRINT #7, "{broken" : CLOSE #7
IF GmNewGame%("/tmp/advt/w2.jsonl") OR INSTR(GmErr$, "line 3:") = 0 THEN Bad "bad line: " + GmErr$
IF GmNewGame%("/tmp/advt/none.jsonl") OR INSTR(GmErr$, "not found") = 0 THEN Bad "missing file: " + GmErr$
GvLogN% = 0
Queue "quit"
IF GcNew%("/tmp/advt/none.jsonl") THEN Bad "GcNew with missing file"
Expect "Cannot load the world", "load error shown"

PRINT "V6 the file is compacted as moves pile up"
IF GcNew%(W$) = 0 THEN Bad "new"
FOR i% = 1 TO 700
  Turn "look"
NEXT
IF DbDead%() > 301 THEN Bad "dead lines " + STR$(DbDead%())
IF GmNum%("moves") <> 700 THEN Bad "moves after compaction " + STR$(GmNum%("moves"))
IF GmAt$() <> "r.beach" THEN Bad "state after compaction"

PRINT "V7 random commands"
DIM verbs$ = "look|take|drop|x|open|unlock|fill|light|read|go|n|s|e|w|u|d|i|eat|score|xyzzy|help|pick"
DIM nouns$ = "|note|desk|drawer|matches|key|door|lamp|oil|can|unicorn|the|at|with key|up"
IF GcNew%(W$) = 0 THEN Bad "new"
FOR i% = 1 TO 600
  s$ = FIELD$(verbs$, 1 + INT(RND * 22), "|") + " " + FIELD$(nouns$, 1 + INT(RND * 15), "|")
  IF RND < 0.3 THEN s$ = s$ + " " + FIELD$(nouns$, 1 + INT(RND * 15), "|")
  Turn s$
  IF GvLogN% = 0 THEN Bad "no response to [" + s$ + "]"
  FOR n% = 0 TO GvLogN% - 1
    IF LEN(GvLog$(n%)) >= GvW% THEN Bad "line too wide: " + GvLog$(n%)
  NEXT
  IF GcOver% THEN ok% = GcNew%(W$)
  IF Fail% > 10 THEN EXIT FOR
NEXT
' world still consistent: every item somewhere real, player in a room
FOR i% = 0 TO DbCount%() - 1
  id$ = DbStr$(DbAt$(i%), "_id")
  IF LEFT$(id$, 2) = "i." THEN
    f$ = GmLoc$(id$)
    IF f$ <> "player" AND f$ <> "nowhere" AND DbExists%(f$) = 0 THEN Bad id$ + " is in " + f$
  ENDIF
NEXT
IF DbExists%(GmAt$()) = 0 THEN Bad "player is nowhere: " + GmAt$()
GmClose
PRINT "TOTAL FAILS:"; Fail%
