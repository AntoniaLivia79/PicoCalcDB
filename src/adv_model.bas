' =====================================================================
' adv_model.bas - MODEL of the text adventure framework (prefix Gm).
' The only module that touches the database (through the Db… API).
' ---------------------------------------------------------------------
' The world and the game state are one collection, GM_COL$, holding
' typed records told apart by their _id prefix:
'   r.<room>   {"_id":"r.hall","name":"Hall","desc":"...","n":"r.yard"}
'              exits are fields n s e w u d holding a room _id
'   i.<item>   {"_id":"i.lamp","name":"a brass lamp","words":"lamp brass",
'              "loc":"r.hall","desc":"...","fixed":true}
'              loc: a room _id, "player" (carried) or "nowhere"
'   w.<word>   {"_id":"w.get","is":"take"}               vocabulary
'   rules      {"_id":"a.10","verb":"open","noun":"desk","if":"...",
'              "do":"...","say":"...","no":"..."}  (see adv_ctrl.bas)
'   s.game     {"_id":"s.game","at":"r.hall","moves":0,"score":0,...}
'   s.flags    one field per flag that is set, e.g. {"door_open":1}
' Every change is written straight away, so the game is always saved.
' =====================================================================

CONST GM_COL$ = "adv"
CONST GM_FN = 6                         ' file number for the world file
CONST GM_MAXL = 40                      ' items in one list
DIM GmList$(GM_MAXL - 1) LENGTH 16, GmListN%
DIM GmErr$

' ---------------- whole games ----------------------------------------

' 1 if the collection holds a game that can be continued
FUNCTION GmHave%()
  LOCAL i%
  FOR i% = 0 TO DbList%() - 1
    IF DbListName$(i%) = GM_COL$ THEN
      IF DbOpen%(GM_COL$) THEN GmHave% = DbExists%("s.game")
    ENDIF
  NEXT
END FUNCTION

' Start a new game: recreate the collection from a world file
' (JSON Lines, one record per line; blank lines and lines starting
' with # are ignored). Returns 0 with GmErr$ set on any bad line.
FUNCTION GmNewGame%(world$)
  LOCAL ln$, x$ = "?", lno% = 0, ok%, i%
  GmErr$ = ""
  ON ERROR SKIP 1
  x$ = DIR$(world$, FILE)
  IF x$ = "" OR x$ = "?" THEN GmErr$ = world$ + " not found" : EXIT FUNCTION
  FOR i% = 0 TO DbList%() - 1
    IF DbListName$(i%) = GM_COL$ THEN
      DbClose : ok% = DbDrop%(GM_COL$)
    ENDIF
  NEXT
  IF DbCreate%(GM_COL$) = 0 THEN GmErr$ = DbErr$() : EXIT FUNCTION
  IF DbOpen%(GM_COL$) = 0 THEN GmErr$ = DbErr$() : EXIT FUNCTION
  OPEN world$ FOR INPUT AS #GM_FN
  DO WHILE NOT EOF(#GM_FN)
    ln$ = CHR$(1) : INC lno%
    ON ERROR SKIP 1
    LINE INPUT #GM_FN, ln$
    IF ln$ = CHR$(1) THEN GmErr$ = "line " + STR$(lno%) + " too long" : EXIT DO
    IF ln$ <> "" AND LEFT$(ln$, 1) <> "#" THEN
      IF DbInsert%(ln$) = 0 THEN GmErr$ = "line " + STR$(lno%) + ": " + DbErr$() : EXIT DO
    ENDIF
  LOOP
  CLOSE #GM_FN
  IF GmErr$ = "" AND DbExists%("s.game") = 0 THEN GmErr$ = "the world has no s.game record"
  IF GmErr$ <> "" THEN EXIT FUNCTION
  IF DbExists%("s.flags") = 0 THEN ok% = DbInsert%(DbNew$("s.flags"))
  ok% = DbIndexAdd%("loc") + DbIndexAdd%("verb")
  DbFlush
  GmNewGame% = 1
END FUNCTION

' Compact the file now and then (each move appends a line)
SUB GmTidy
  LOCAL ok%
  IF DbDead%() > 300 THEN ok% = DbVacuum%()
END SUB

SUB GmClose
  DbClose
END SUB

' ---------------- records and fields ---------------------------------

FUNCTION GmGet$(id$)
  GmGet$ = DbGet$(id$)
END FUNCTION

FUNCTION GmField$(id$, f$)
  GmField$ = DbStr$(DbGet$(id$), f$)
END FUNCTION

' ---------------- game state -----------------------------------------

FUNCTION GmAt$()
  GmAt$ = GmField$("s.game", "at")
END FUNCTION

SUB GmSetAt room$
  LOCAL ok% = DbSetText%("s.game", "at", room$)
END SUB

FUNCTION GmNum%(f$)
  GmNum% = DbNum!(DbGet$("s.game"), f$)
END FUNCTION

SUB GmAddNum f$, n%
  LOCAL ok% = DbSetNum%("s.game", f$, GmNum%(f$) + n%)
END SUB

FUNCTION GmFlag%(f$)
  GmFlag% = DbHas%(DbGet$("s.flags"), f$)
END FUNCTION

SUB GmSetFlag f$, on%
  LOCAL ok%
  IF on% THEN
    ok% = DbSetRaw%("s.flags", f$, "1")
  ELSEIF GmFlag%(f$) THEN
    ok% = DbUnset%("s.flags", f$)
  ENDIF
END SUB

' ---------------- world ----------------------------------------------

FUNCTION GmLoc$(item$)
  GmLoc$ = GmField$(item$, "loc")
END FUNCTION

SUB GmMove item$, loc$
  LOCAL ok% = DbSetText%(item$, "loc", loc$)
END SUB

' Destination of an exit ("" if none)
FUNCTION GmExit$(room$, dir$)
  GmExit$ = GmField$(room$, dir$)
END FUNCTION

SUB GmSetExit room$, dir$, dest$
  LOCAL ok%
  IF dest$ = "" THEN ok% = DbUnset%(room$, dir$) ELSE ok% = DbSetText%(room$, dir$, dest$)
END SUB

' Items at loc$ (a room _id or "player") -> GmList$(); returns count.
' add% = 1 appends to the current list instead of replacing it.
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

' Vocabulary: the word a synonym stands for (or the word itself)
FUNCTION GmWord$(w$)
  LOCAL r$
  GmWord$ = w$
  IF LEN(w$) > 14 THEN EXIT FUNCTION
  r$ = DbGet$("w." + w$)
  IF r$ <> "" THEN GmWord$ = DbStr$(r$, "is")
END FUNCTION

' Rules for verb$ and noun$ ("" = rules without a noun), in _id
' order. Read them with DbRows%() / DbRow$(i%).
FUNCTION GmRules%(verb$, noun$)
  LOCAL q$ = "SELECT * FROM " + GM_COL$ + " WHERE verb = '" + verb$ + "' AND "
  IF noun$ = "" THEN q$ = q$ + "noun IS NULL" ELSE q$ = q$ + "noun = '" + noun$ + "'"
  IF DbQuery%(q$) THEN GmRules% = DbRows%()
END FUNCTION
