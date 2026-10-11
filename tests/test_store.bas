' test_store.bas - randomized tests for dbstore.bas
' Run: OPTION EXPLICIT + dbcore.bas + dbstore.bas + this file.
' WARNING: deletes every file in StDir$ (set below to /tmp/dbt/).

' ======================= STORAGE HARNESS =============================
DIM Fail% = 0, Nops% = 0, Nrej% = 0
RANDOMIZE 777
SUB Bad m$
  PRINT "FAIL: "; m$ : INC Fail%
END SUB
CONST MM = 299
DIM mky$(MM) LENGTH 16, mrec$(MM), mn% = 0
FUNCTION MFind%(id$)
  LOCAL i%
  MFind% = -1
  FOR i% = 0 TO mn% - 1
    IF mky$(i%) = id$ THEN MFind% = i% : EXIT FUNCTION
  NEXT
END FUNCTION
SUB MPut id$, r$
  LOCAL i% = MFind%(id$)
  IF i% < 0 THEN i% = mn% : INC mn%
  mky$(i%) = id$ : mrec$(i%) = r$
END SUB
SUB MDel id$
  LOCAL i% = MFind%(id$)
  IF i% >= 0 THEN mky$(i%) = mky$(mn% - 1) : mrec$(i%) = mrec$(mn% - 1) : INC mn%, -1
END SUB
FUNCTION RNum$()
  IF RND < 0.5 THEN RNum$ = STR$(INT(RND * 90)) ELSE RNum$ = STR$(INT(RND * 40) / 4 - 3)
END FUNCTION
FUNCTION RName$()
  LOCAL i%, s$
  FOR i% = 1 TO 1 + INT(RND * 13) : s$ = s$ + MID$("abq" + CHR$(34), 1 + INT(RND * 4), 1) : NEXT
  RName$ = s$
END FUNCTION
FUNCTION RRec$(id$)
  LOCAL r$ = RcNew$(id$)
  IF RND < 0.85 THEN r$ = RcSet$(r$, "age", RNum$(), 2)
  IF RND < 0.85 THEN r$ = RcSet$(r$, "name", RName$(), 1)
  IF RND < 0.5 THEN r$ = RcSet$(r$, "note", RName$() + RName$(), 1)
  RRec$ = r$
END FUNCTION

SUB Churn n%
  LOCAL it%, op%, id$, r$, ok%, i%, f$, v$, t%
  FOR it% = 1 TO n%
    op% = INT(RND * 10)
    IF RND < 0.7 THEN id$ = "r" + STR$(INT(RND * 120)) ELSE id$ = "x" + STR$(INT(RND * 60))
    i% = MFind%(id$)
    SELECT CASE op%
      CASE 0, 1
        id$ = StNewId$() : r$ = RRec$(id$)
        IF MFind%(id$) >= 0 THEN Bad "newid collides " + id$
        ok% = StWrite%(r$, 1)
        IF ok% THEN MPut id$, r$
      CASE 2, 3
        r$ = RRec$(id$) : ok% = StWrite%(r$, 0)
        IF ok% THEN MPut id$, r$
      CASE 4
        r$ = RRec$(id$) : ok% = StWrite%(r$, 1)
        IF i% >= 0 AND ok% THEN Bad "dup insert accepted"
        IF ok% THEN MPut id$, r$
      CASE 5
        r$ = RRec$(id$) : ok% = StWrite%(r$, 2)
        IF i% < 0 AND ok% THEN Bad "update of missing accepted"
        IF ok% THEN MPut id$, r$
      CASE 6, 7
        IF RND < 0.5 THEN
          f$ = "age" : v$ = RNum$() : t% = 2
        ELSE
          f$ = "name" : v$ = RName$() : t% = 1
        ENDIF
        IF RND < 0.2 THEN t% = 0
        ok% = StSetField%(id$, f$, v$, t%)
        IF i% < 0 AND ok% THEN Bad "setfield on missing"
        IF ok% THEN
          IF t% = 0 THEN r$ = RcDel$(mrec$(i%), f$) ELSE r$ = RcSet$(mrec$(i%), f$, v$, t%)
          mrec$(i%) = r$
        ENDIF
      CASE ELSE
        ok% = StDelete%(id$)
        IF (i% >= 0) <> ok% THEN Bad "delete result " + id$
        IF ok% THEN MDel id$
    END SELECT
    IF ok% THEN INC Nops% ELSE INC Nrej%
    IF ok% = 0 AND StErr$ = "" THEN Bad "failure without StErr$ op" + STR$(op%)
  NEXT
END SUB

SUB Verify tag$
  LOCAL i%, j%, r$, f$, op$, v$, t%, lo%, hi%, q%, s%, hit%, x$
  LOCAL ops$(4) = ("=", "<", "<=", ">", ">=")
  IF StCount%() <> mn% THEN Bad tag$ + " count " + STR$(StCount%()) + " vs " + STR$(mn%)
  FOR i% = 0 TO mn% - 1
    r$ = StFetch$(mky$(i%))
    IF r$ <> mrec$(i%) THEN Bad tag$ + " fetch " + mky$(i%) + " got " + r$
  NEXT
  FOR i% = 1 TO StCount%() - 1
    IF IxK$(i% - 1) >= IxK$(i%) THEN Bad tag$ + " order"
  NEXT
  IF StCount%() > 0 THEN
    i% = INT(RND * StCount%())
    IF RcGet$(StAt$(i%), "_id") <> IxK$(i%) THEN Bad tag$ + " StAt"
  ENDIF
  FOR q% = 1 TO 15
    IF RND < 0.5 THEN
      f$ = "age" : v$ = RNum$() : t% = 2
    ELSE
      f$ = "name" : v$ = RName$() : t% = 1
    ENDIF
    op$ = ops$(INT(RND * 5))
    s% = SxSlot%(f$)
    IF s% < 0 THEN EXIT FOR
    SxRange s%, op$, v$, t%, lo%, hi%
    FOR i% = 0 TO mn% - 1
      x$ = RcGet$(mrec$(i%), f$)
      IF RcFound% AND RcT% = t% THEN
        IF t% = 2 THEN
          hit% = CmpN%(op$, VAL(x$), VAL(v$))
        ELSE
          hit% = CmpS%(op$, x$, v$)
        ENDIF
        IF hit% THEN
          hit% = 0
          FOR j% = lo% TO hi% - 1
            IF SxO%(j%) = IxGet%(mky$(i%)) THEN hit% = 1 : EXIT FOR
          NEXT
          IF hit% = 0 THEN Bad tag$ + " index miss " + f$ + op$ + v$
        ENDIF
      ENDIF
    NEXT
  NEXT
END SUB
FUNCTION CmpN%(op$, a!, b!)
  SELECT CASE op$
    CASE "=" : CmpN% = (a! = b!)
    CASE "<" : CmpN% = (a! < b!)
    CASE "<=" : CmpN% = (a! <= b!)
    CASE ">" : CmpN% = (a! > b!)
    CASE ">=" : CmpN% = (a! >= b!)
  END SELECT
END FUNCTION
FUNCTION CmpS%(op$, a$, b$)
  SELECT CASE op$
    CASE "=" : CmpS% = (a$ = b$)
    CASE "<" : CmpS% = (a$ < b$)
    CASE "<=" : CmpS% = (a$ <= b$)
    CASE ">" : CmpS% = (a$ > b$)
    CASE ">=" : CmpS% = (a$ >= b$)
  END SELECT
END FUNCTION
FUNCTION LineCount%(p$)
  LOCAL r$
  OPEN p$ FOR INPUT AS #9
  DO WHILE NOT EOF(#9) : LINE INPUT #9, r$ : INC LineCount% : LOOP
  CLOSE #9
END FUNCTION

' ---------------------------------------------------------------------
StDir$ = "/tmp/dbt/"
DIM ok%, i%, r$, f$
ON ERROR SKIP 1 : MKDIR "/tmp/dbt"
f$ = DIR$("/tmp/dbt/*", FILE)
DO WHILE f$ <> "" : KILL "/tmp/dbt/" + f$ : f$ = DIR$("/tmp/dbt/*", FILE) : LOOP

PRINT "S1 catalog"
IF StCreate%("people") = 0 THEN Bad "create " + StErr$
IF StCreate%("alpha") = 0 THEN Bad "create2 " + StErr$
IF StCreate%("people") THEN Bad "dup create"
IF StCreate%("bad name") THEN Bad "bad name accepted"
IF StList%() <> 2 THEN Bad "list count"
IF StCat$(0) <> "alpha" OR StCat$(1) <> "people" THEN Bad "list order " + StCat$(0)
IF StOpen%("nope") THEN Bad "open missing"

PRINT "S2 churn"
IF StOpen%("people") = 0 THEN Bad "open " + StErr$
IF StIndexAdd%("age") = 0 THEN Bad "idx age " + StErr$
IF StIndexAdd%("age") THEN Bad "idx twice"
Churn 150
IF StIndexAdd%("name") = 0 THEN Bad "idx name " + StErr$
Churn 250
Verify "churn"
PRINT "  ops"; Nops%; " rejected"; Nrej%; " live"; mn%; " fails"; Fail%

PRINT "S3 reopen + meta"
DIM seq% = MtSeq%
StClose
IF StOpen%("people") = 0 THEN Bad "reopen " + StErr$
IF StWarn$ <> "" THEN Bad "unexpected warn " + StWarn$
IF SxSlot%("age") < 0 OR SxSlot%("name") < 0 THEN Bad "index defs lost"
IF MtSeq% <> seq% THEN Bad "seq lost"
FOR i% = 0 TO MtN% - 1
  IF MtF$(i%) = "age" AND MtT$(i%) <> "N" THEN Bad "age type " + MtT$(i%)
  IF MtF$(i%) = "name" AND MtT$(i%) <> "S" THEN Bad "name type"
NEXT
Verify "reopen"
StClose : KILL StDir$ + "people.idx"
IF StOpen%("people") = 0 THEN Bad "full rebuild open"
Verify "full-rebuild"
Churn 100
Verify "reopen-churn"

PRINT "S4 torn tail"
StClose
OPEN StDir$ + "people.jsonl" FOR APPEND AS #8 : PRINT #8, "{" + CHR$(34) + "_id" + CHR$(34) + ":" + CHR$(34) + "r1"; : CLOSE #8
IF StOpen%("people") = 0 THEN Bad "open torn " + StErr$
IF INSTR(StWarn$, "repaired") = 0 THEN Bad "no repair warn: " + StWarn$
Verify "torn"
Churn 60
StClose
IF StOpen%("people") = 0 THEN Bad "reopen torn"
Verify "torn-reopen"

PRINT "S6 vacuum"
ok% = StVacuum%()
IF ok% = 0 THEN Bad "vacuum " + StErr$
IF MtDead% <> 0 THEN Bad "dead not reset"
IF LineCount%(StDir$ + "people.jsonl") <> mn% THEN Bad "vacuum lines"
Verify "vacuum"
Churn 50
StClose
IF StOpen%("people") = 0 THEN Bad "open after vacuum"
Verify "vacuum-reopen"

PRINT "S5 external edit, same length"
ok% = StVacuum%()
StClose
DIM ln$(1000), nl% = 0
OPEN StDir$ + "people.jsonl" FOR INPUT AS #8
DO WHILE NOT EOF(#8) : LINE INPUT #8, ln$(nl%) : INC nl% : LOOP
CLOSE #8
OPEN StDir$ + "people.jsonl" FOR OUTPUT AS #8
FOR i% = nl% - 1 TO 0 STEP -1 : PRINT #8, ln$(i%) : NEXT
CLOSE #8
IF StOpen%("people") = 0 THEN Bad "open ext"
IF INSTR(StWarn$, "stale index rebuilt") = 0 THEN Bad "stale not detected: " + StWarn$
Verify "external"

PRINT "S7 interrupted vacuum"
StClose
OPEN StDir$ + "people.jsonl" FOR INPUT AS #8 : OPEN StDir$ + "people.vtmp" FOR OUTPUT AS #7
DO WHILE NOT EOF(#8) : LINE INPUT #8, r$ : PRINT #7, r$ : LOOP
CLOSE #8 : CLOSE #7
KILL StDir$ + "people.jsonl"
IF StOpen%("people") = 0 THEN Bad "recover vtmp " + StErr$
Verify "vtmp-recover"
StClose
OPEN StDir$ + "people.vtmp" FOR OUTPUT AS #8 : PRINT #8, "partial" : CLOSE #8
IF StOpen%("people") = 0 THEN Bad "recover vtmp2"
IF StExists%(StDir$ + "people.vtmp") THEN Bad "vtmp not removed"
Verify "vtmp-discard"

PRINT "S8 drop index / drop collection"
IF StIndexDrop%("name") = 0 THEN Bad "drop idx"
FOR i% = 0 TO SxN% - 1
  IF SxF$(ASC(SxV$(i%)) - 65) <> "age" THEN Bad "dropped entries remain"
NEXT
StClose
IF StOpen%("people") = 0 THEN Bad "reopen"
IF SxSlot%("name") >= 0 THEN Bad "drop not persisted"
Verify "dropidx"
IF StDrop%("alpha") = 0 THEN Bad "drop coll"
IF StList%() <> 1 THEN Bad "list after drop"
PRINT "S9 foreign file: long lines, tabs, junk"
StClose
OPEN StDir$ + "ext.jsonl" FOR OUTPUT AS #8
PRINT #8, "{" + CHR$(34) + "_id" + CHR$(34) + ":" + CHR$(34) + "a" + CHR$(34) + "," + CHR$(9) + CHR$(34) + "v" + CHR$(34) + ":1}"
PRINT #8, "{" + CHR$(34) + "_id" + CHR$(34) + ":" + CHR$(34) + "long" + CHR$(34) + "," + CHR$(34) + "pad" + CHR$(34) + ":" + CHR$(34) + STRING$(200, "p");
PRINT #8, STRING$(29, "p") + CHR$(34) + "," + CHR$(34) + "n" + CHR$(34) + ":";
PRINT #8, "{" + CHR$(34) + "_id" + CHR$(34) + ":" + CHR$(34) + "phantom" + CHR$(34) + "}}"
PRINT #8, "not json"
PRINT #8, ""
PRINT #8, "{" + CHR$(34) + "_id" + CHR$(34) + ":" + CHR$(34) + "b" + CHR$(34) + "}"
CLOSE #8
IF StOpen%("ext") = 0 THEN Bad "open ext " + StErr$
PRINT "  warn: "; StWarn$; "  count"; StCount%()
IF StCount%() <> 2 THEN Bad "ext count"
IF IxGet%("phantom") >= 0 THEN Bad "phantom indexed"
IF RcGet$(StFetch$("a"), "v") <> "1" THEN Bad "tab record"
IF StWrite%(RcSet$(RcNew$("c"), "w", "2", 2), 1) = 0 THEN Bad "write ext " + StErr$
StClose
IF StOpen%("ext") = 0 THEN Bad "reopen ext"
IF StCount%() <> 3 THEN Bad "ext count 2"
PRINT "TOTAL FAILS:"; Fail%
