' =====================================================================
' adv_ctrl.bas - CONTROLLER of the text adventure framework (prefix Gc).
' Turns commands into changes to the model and output for the view.
' ---------------------------------------------------------------------
' A command is parsed into a verb, a noun and an optional "with" noun:
'   "unlock the iron door with the key" -> unlock / door / key
' Words are first translated through the world's vocabulary (w.<word>
' records), so "get" can mean "take". Then:
'   1. Rules: records with "verb" (and "noun") fields, tried in _id
'      order. The first whose conditions ("if") hold runs: it shows
'      "say" and applies the effects in "do". If none hold, the first
'      "no" message among them is shown; with no "no" message, the
'      command falls through to step 2. So rules can override or
'      refine built-in verbs.
'   2. Built-in verbs: look, inventory, go, take, drop, examine.
' Conditions ("if"), separated by ";" and all required; ! negates:
'   have:item   carried          here:item  carried or in this room
'   at:room     player is there  flag:name  flag is set
' Effects ("do"), separated by ";", applied in order:
'   set:flag   clear:flag   score:n   look   go:room
'   move:item>place   (place: a room, player, here, nowhere)
'   exit:room.dir>room   (no room after > removes the exit)
'   end:win   end:lose
' Rooms and items are written without their r. / i. prefix.
' =====================================================================

DIM GcVerb$, GcNoun$, GcWith$, GcOver%, GcQuit%, GcRestart%
' Work left for GcDo to do once the command has been handled: running
' it there, rather than from deep inside a rule or a verb, keeps the
' call chains short (the PicoMite has a small stack).
DIM GcDoEff$, GcLookNow%, GcInvNow%

' n, s, e, w, u or d for a direction word, else ""
FUNCTION GcDirOf$(w$)
  SELECT CASE w$
    CASE "n", "north" : GcDirOf$ = "n"
    CASE "s", "south" : GcDirOf$ = "s"
    CASE "e", "east" : GcDirOf$ = "e"
    CASE "w", "west" : GcDirOf$ = "w"
    CASE "u", "up" : GcDirOf$ = "u"
    CASE "d", "down" : GcDirOf$ = "d"
  END SELECT
END FUNCTION

FUNCTION GcDirName$(d$)
  GcDirName$ = FIELD$("north,south,east,west,up,down", INSTR("nsewud", d$), ",")
END FUNCTION

' ---------------- parsing --------------------------------------------

SUB GcParse cmd$
  LOCAL t$, c$, w$, ws$(7), n% = 0, i%, j%
  GcVerb$ = "" : GcNoun$ = "" : GcWith$ = ""
  FOR i% = 1 TO LEN(cmd$)
    c$ = LCASE$(MID$(cmd$, i%, 1))
    IF INSTR("abcdefghijklmnopqrstuvwxyz0123456789", c$) THEN t$ = t$ + c$ ELSE t$ = t$ + " "
  NEXT
  FOR i% = 1 TO 30
    w$ = FIELD$(t$, i%, " ")
    IF w$ <> "" AND w$ <> "the" AND w$ <> "a" AND w$ <> "an" AND n% < 8 THEN ws$(n%) = w$ : INC n%
  NEXT
  IF n% = 0 THEN EXIT SUB
  GcVerb$ = GmWord$(ws$(0))
  IF GcDirOf$(GcVerb$) <> "" THEN GcNoun$ = GcDirOf$(GcVerb$) : GcVerb$ = "go" : EXIT SUB
  j% = 1
  IF j% < n% THEN
    IF GcVerb$ = "look" AND ws$(1) = "at" THEN GcVerb$ = "examine" : j% = 2
  ENDIF
  IF j% < n% THEN
    IF INSTR(" at to in into on ", " " + ws$(j%) + " ") THEN INC j%
  ENDIF
  ' the noun is the last word before "with" ("brass lamp" -> lamp)
  FOR i% = j% TO n% - 1
    IF ws$(i%) = "with" THEN
      IF i% + 1 < n% THEN GcWith$ = ws$(n% - 1)
      EXIT FOR
    ENDIF
    GcNoun$ = ws$(i%)
  NEXT
  IF GcVerb$ = "go" AND GcDirOf$(GcNoun$) <> "" THEN GcNoun$ = GcDirOf$(GcNoun$)
END SUB

' ---------------- items ----------------------------------------------

' The visible item (carried or in this room) a word refers to, or ""
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

FUNCTION GcName$(id$)
  GcName$ = GmField$(id$, "name")
  IF GcName$ = "" THEN GcName$ = MID$(id$, 3)
END FUNCTION

' ---------------- built-in verbs -------------------------------------

SUB GcLook
  LOCAL room$ = GmAt$(), r$, s$, n%, k% = 0, i%, d%, rec$
  r$ = GmGet$(room$)
  GvTitle DbStr$(r$, "name")
  GvSay DbStr$(r$, "desc")
  n% = GmItemsAt%(room$, 0)
  FOR i% = 0 TO n% - 1
    rec$ = GmGet$(GmList$(i%))
    IF DbHas%(rec$, "fixed") = 0 AND LEN(s$) < 200 THEN s$ = s$ + DbStr$(rec$, "name") + "|" : INC k%
  NEXT
  IF k% THEN GvList "You can see ", s$, k%
  s$ = "" : k% = 0
  FOR d% = 1 TO 6
    IF DbStr$(r$, MID$("nsewud", d%, 1)) <> "" THEN s$ = s$ + GcDirName$(MID$("nsewud", d%, 1)) + "|" : INC k%
  NEXT
  IF k% THEN GvList "Exits: ", s$, k% ELSE GvSay "There is no way out."
END SUB

SUB GcInventory
  LOCAL n% = GmItemsAt%("player", 0), i%, s$
  IF n% = 0 THEN GvSay "You are carrying nothing." : EXIT SUB
  FOR i% = 0 TO n% - 1
    IF LEN(s$) < 200 THEN s$ = s$ + GcName$(GmList$(i%)) + "|"
  NEXT
  GvList "You are carrying ", s$, n%
END SUB

' Built-in verbs; returns 0 if the verb is not one of them.
' id$ is the item the noun refers to ("" if none is visible).
FUNCTION GcBuiltIn%(id$)
  LOCAL dest$
  GcBuiltIn% = 1
  SELECT CASE GcVerb$
    CASE "look"
      IF GcNoun$ = "" THEN GcLookNow% = 1 : EXIT FUNCTION
      GcVerb$ = "examine"
    CASE "inventory" : GcInvNow% = 1 : EXIT FUNCTION
    CASE "go"
      IF GcNoun$ = "" THEN GvSay "Go where?" : EXIT FUNCTION
      IF GcDirOf$(GcNoun$) <> "" THEN dest$ = GmExit$(GmAt$(), GcNoun$)
      IF dest$ = "" THEN GvSay "You can't go that way." : EXIT FUNCTION
      GmSetAt dest$ : GcLookNow% = 1 : EXIT FUNCTION
    CASE "take", "drop", "examine"
    CASE ELSE
      GcBuiltIn% = 0 : EXIT FUNCTION
  END SELECT
  IF GcNoun$ = "" THEN GvSay "What do you want to " + GcVerb$ + "?" : EXIT FUNCTION
  IF id$ = "" THEN GvSay "You can't see any " + GcNoun$ + " here." : EXIT FUNCTION
  SELECT CASE GcVerb$
    CASE "take"
      IF GmLoc$(id$) = "player" THEN
        GvSay "You already have it."
      ELSEIF DbHas%(GmGet$(id$), "fixed") THEN
        GvSay "You can't take that."
      ELSE
        GmMove id$, "player" : GvSay "Taken."
      ENDIF
    CASE "drop"
      IF GmLoc$(id$) <> "player" THEN
        GvSay "You are not carrying it."
      ELSE
        GmMove id$, GmAt$() : GvSay "Dropped."
      ENDIF
    CASE "examine"
      dest$ = GmField$(id$, "desc")
      IF dest$ = "" THEN dest$ = "You see nothing special about " + GcName$(id$) + "."
      GvSay dest$
  END SELECT
END FUNCTION

' ---------------- rules ----------------------------------------------

' Where "place" in move:item>place means
FUNCTION GcPlace$(p$)
  SELECT CASE p$
    CASE "player", "nowhere" : GcPlace$ = p$
    CASE "here" : GcPlace$ = GmAt$()
    CASE ELSE : GcPlace$ = "r." + p$
  END SELECT
END FUNCTION

' 1 if every condition in c$ holds
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

' Apply the effects in e$
SUB GcEffects e$
  LOCAL i%, p$, k$, a$, b$
  FOR i% = 1 TO 12
    p$ = FIELD$(e$, i%, ";")
    IF p$ = "" THEN EXIT FOR
    k$ = FIELD$(p$, 1, ":") : a$ = FIELD$(p$, 2, ":")
    SELECT CASE k$
      CASE "set" : GmSetFlag a$, 1
      CASE "clear" : GmSetFlag a$, 0
      CASE "score" : GmAddNum "score", VAL(a$)
      CASE "move" : GmMove "i." + FIELD$(a$, 1, ">"), GcPlace$(FIELD$(a$, 2, ">"))
      CASE "exit"
        b$ = FIELD$(a$, 2, ">")
        IF b$ <> "" THEN b$ = "r." + b$
        GmSetExit "r." + FIELD$(FIELD$(a$, 1, ">"), 1, "."), FIELD$(FIELD$(a$, 1, ">"), 2, "."), b$
      CASE "go" : GmSetAt "r." + a$ : GcLookNow% = 1
      CASE "look" : GcLookNow% = 1
      CASE "end" : GmSetFlag "end_" + a$, 1 : GcOver% = 1
    END SELECT
  NEXT
END SUB

' Try the rules for the current verb and noun key$. Returns 1 if a
' rule (or a rule's "no" message) handled the command. The chosen
' rule's effects are left in GcDoEff$ for GcDo to apply.
FUNCTION GcRules%(key$)
  LOCAL i%, n%, r$, no$
  n% = GmRules%(GcVerb$, key$)
  FOR i% = 0 TO n% - 1
    r$ = GmGet$(GmList$(i%))
    IF GcTest%(DbStr$(r$, "if")) THEN
      IF DbStr$(r$, "say") <> "" THEN GvSay DbStr$(r$, "say")
      GcDoEff$ = DbStr$(r$, "do")
      GcRules% = 1 : EXIT FUNCTION
    ENDIF
    IF no$ = "" THEN no$ = DbStr$(r$, "no")
  NEXT
  IF no$ <> "" THEN GvSay no$ : GcRules% = 1
END FUNCTION

' ---------------- commands -------------------------------------------

' Commands about the game itself; returns 1 if c$ was one
FUNCTION GcMeta%()
  GcMeta% = 1
  SELECT CASE GcVerb$
    CASE "help"
      GvSay "Type commands like: look, n (north), take lamp, drop lamp, examine desk, inventory (i), open door, unlock door with key."
      GvSay "Also: score, restart, quit. The game is saved after every move."
    CASE "score" : GvSay "You have scored " + STR$(GmNum%("score")) + " in " + STR$(GmNum%("moves")) + " moves."
    CASE "save" : GvSay "The game is saved after every move."
    CASE "quit" : GvSay "Your game is saved. Goodbye." : GcQuit% = 1
    CASE "restart" : GcRestart% = 1
    CASE ELSE : GcMeta% = 0
  END SELECT
END FUNCTION

' Carry out one command
SUB GcDo cmd$
  LOCAL id$, key$
  GcParse cmd$
  IF GcVerb$ = "" THEN GvSay "Pardon?" : EXIT SUB
  IF GcMeta%() THEN EXIT SUB
  GcDoEff$ = "" : GcLookNow% = 0 : GcInvNow% = 0
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
  IF GcDoEff$ <> "" THEN GcEffects GcDoEff$
  IF GcLookNow% THEN GcLook
  IF GcInvNow% THEN GcInventory
  GmAddNum "moves", 1
  GmTidy
END SUB

' ---------------- the game -------------------------------------------

' Start a new game from the world file
FUNCTION GcNew%(world$)
  GvSay "Loading the world..."
  IF GmNewGame%(world$) = 0 THEN GvSay "Cannot load the world: " + GmErr$ : EXIT FUNCTION
  GcOver% = 0
  GvTitle GmField$("s.game", "title")
  GvSay GmField$("s.game", "intro")
  GcLook
  GcNew% = 1
END FUNCTION

SUB GcEnding
  IF GmFlag%("end_win") THEN GvSay "*** You have won ***" ELSE GvSay "*** You have lost ***"
  GvSay "You scored " + STR$(GmNum%("score")) + " in " + STR$(GmNum%("moves")) + " moves."
END SUB

' The game loop: continue a saved game or start a new one
SUB GcRun world$
  LOCAL c$, ok% = 1
  GvInit
  GcQuit% = 0 : GcRestart% = 0 : GcOver% = 0
  IF GmHave%() THEN
    c$ = GvAsk$("Continue your saved game? (y/n) ")
    IF LCASE$(LEFT$(c$, 1)) = "n" OR GmFlag%("end_win") OR GmFlag%("end_lose") THEN
      ok% = GcNew%(world$)
    ELSE
      GvSay "Welcome back." : GcLook
    ENDIF
  ELSE
    ok% = GcNew%(world$)
  ENDIF
  IF ok% = 0 THEN EXIT SUB
  DO WHILE GcQuit% = 0
    c$ = GvAsk$("> ")
    GcDo c$
    IF GcRestart% THEN
      GcRestart% = 0
      IF GcNew%(world$) = 0 THEN EXIT DO
    ENDIF
    IF GcOver% THEN
      GcEnding
      c$ = GvAsk$("Play again? (y/n) ")
      IF LCASE$(LEFT$(c$, 1)) = "y" THEN
        IF GcNew%(world$) = 0 THEN EXIT DO
      ELSE
        GcQuit% = 1
      ENDIF
    ENDIF
  LOOP
  GmClose
END SUB
