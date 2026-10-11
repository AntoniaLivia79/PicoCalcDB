' test_gui.bas - GUI tests with a mock display/keyboard (no PicoCalc needed)
' Run: OPTION EXPLICIT + dbcore + dbstore + dbquery + dbexec + dbgui + this file
' (NOT dbhal.bas - this file provides a mock HAL). Uses /tmp/dbg/ and
' expects a copy of help/dbhelp.jsonl at /tmp/dbhelp.jsonl.

' ======================= GUI HARNESS (mock HAL) ======================
DIM Fail% = 0
RANDOMIZE 31337
SUB Bad m$
  PRINT "FAIL: "; m$ : INC Fail%
END SUB
' ---- mock HAL: 40x26 character grid + scripted keys --------------
DIM HalW% = 40, HalH% = 26
DIM Scr$(25) LENGTH 40, ScrSt%(25), MkQ$, MkUnder%
SUB HalInit
END SUB
SUB HalCls
  LOCAL r%
  FOR r% = 0 TO HalH% - 1 : Scr$(r%) = SPACE$(HalW%) : ScrSt%(r%) = 0 : NEXT
END SUB
SUB HalText c%, r%, s$, st%
  IF r% < 0 OR r% >= HalH% OR c% < 0 THEN Bad "draw outside screen r" + STR$(r%) : EXIT SUB
  IF c% + LEN(s$) > HalW% THEN Bad "draw past right edge r" + STR$(r%) + " c" + STR$(c%) : EXIT SUB
  Scr$(r%) = LEFT$(Scr$(r%), c%) + s$ + MID$(Scr$(r%), c% + LEN(s$) + 1)
  IF c% = 0 AND LEN(s$) = HalW% THEN ScrSt%(r%) = st%
END SUB
FUNCTION HalKey%()
  IF MkQ$ = "" THEN INC MkUnder% : HalKey% = 27 : EXIT FUNCTION
  HalKey% = ASC(MkQ$) : MkQ$ = MID$(MkQ$, 2)
END FUNCTION
' ---- helpers --------------------------------------------------------
CONST KE$ = CHR$(13), KX$ = CHR$(27), KU$ = CHR$(128), KD$ = CHR$(129)
CONST KL$ = CHR$(130), KR$ = CHR$(131), KH$ = CHR$(134), KN$ = CHR$(135)
CONST KPD$ = CHR$(137), KDEL$ = CHR$(212), KBS$ = CHR$(8), KF1$ = CHR$(145)
DIM Seen%(5)
DIM Snap$(25) LENGTH 40, SnapSt%(25), CheckPaint% = 1, Fuzz% = 0
SUB PaintCheck
  LOCAL r%
  FOR r% = 0 TO HalH% - 1 : Snap$(r%) = Scr$(r%) : SnapSt%(r%) = ScrSt%(r%) : NEXT
  UiFull% = 1 : UiPaint
  FOR r% = 0 TO HalH% - 1
    IF Snap$(r%) <> Scr$(r%) OR SnapSt%(r%) <> ScrSt%(r%) THEN
      Bad "incremental paint differs on row" + STR$(r%) + " view" + STR$(UiV%)
      PRINT "   inc ["; Snap$(r%); "]"; SnapSt%(r%) : PRINT "   full["; Scr$(r%); "]"; ScrSt%(r%)
      EXIT SUB
    ENDIF
  NEXT
END SUB
SUB Invariants
  LOCAL n% = UiCount%(), s% = UiSel%(UiV%), r%
  IF n% > 0 AND (s% < 0 OR s% >= n%) THEN Bad "sel out of range"
  IF UiV% <> UV_TEXT AND n% > 0 THEN
    r% = s% - UiTop%(UiV%) + 1
    IF r% < 1 OR r% > UiBodyH%() THEN Bad "selection not visible" : EXIT SUB
    IF ScrSt%(r%) <> US_SEL THEN Bad "selected row not highlighted view" + STR$(UiV%)
  ENDIF
  FOR r% = 1 TO UiBodyH%()
    IF ScrSt%(r%) = US_SEL AND UiV% <> UV_DET + 10 THEN
      IF r% <> s% - UiTop%(UiV%) + 1 THEN Bad "two highlighted rows"
    ENDIF
  NEXT
END SUB
SUB Keys s$
  MkQ$ = s$
  DO WHILE MkQ$ <> "" AND UiQuit% = 0
    UiStep
    INC Seen%(UiV%)
    Invariants
    IF CheckPaint% THEN PaintCheck
  LOOP
  IF MkUnder% AND Fuzz% = 0 THEN Bad "key script ran short"
  MkUnder% = 0
END SUB
FUNCTION OnScr%(t$)
  LOCAL r%
  FOR r% = 0 TO HalH% - 1
    IF INSTR(Scr$(r%), t$) THEN OnScr% = r% + 1 : EXIT FUNCTION
  NEXT
END FUNCTION
SUB Expect t$, tag$
  IF OnScr%(t$) = 0 THEN Bad tag$ + ": [" + t$ + "] not on screen" : DumpScr
END SUB
SUB DumpScr
  LOCAL r%
  FOR r% = 0 TO HalH% - 1 : PRINT "   |"; Scr$(r%); "|"; ScrSt%(r%) : NEXT
END SUB
FUNCTION SelText$()
  SelText$ = Scr$(UiSel%(UiV%) - UiTop%(UiV%) + 1)
END FUNCTION

' ---------------------------------------------------------------------
StDir$ = "/tmp/dbg/"
DIM f$, i%, r$, ok%
ON ERROR SKIP 1 : MKDIR "/tmp/dbg"
f$ = DIR$("/tmp/dbg/*", FILE)
DO WHILE f$ <> "" : KILL "/tmp/dbg/" + f$ : f$ = DIR$("/tmp/dbg/*", FILE) : LOOP
HalCls
UiListColl "" : UiGo UV_COLL : UiPaint

PRINT "G1 collections"
Expect "Collections (0)", "start"
Keys "N" + "people" + KE$
Keys "n" + "zoo" + KE$
Expect "Collections (2)", "after create"
IF INSTR(SelText$(), "zoo") = 0 THEN Bad "new collection not selected"
Keys "N" + "bad name" + KE$
IF UiMsgSt% <> US_ERR THEN Bad "bad name not reported"
Keys KU$ + KE$
IF UiV% <> UV_RECS OR StCol$ <> "people" THEN Bad "open people"
Expect "people  0/0", "empty title"

PRINT "G2 new record + fields"
Keys "N" + "a1" + KE$
IF UiV% <> UV_DET THEN Bad "detail after new"
Keys "A" + "age" + KE$ + "41" + KE$
Keys "A" + "name" + KE$ + "Al" + KE$
Keys "A" + "zip" + KE$ + "'0123'" + KE$
r$ = StFetch$("a1")
IF RcGet$(r$, "age") <> "41" OR RcT% <> 2 THEN Bad "age not numeric: " + r$
IF RcGet$(r$, "zip") <> "0123" OR RcT% <> 1 THEN Bad "zip not text: " + r$
Expect "zip       : '0123'", "zip shown"
Keys KX$
IF UiV% <> UV_RECS THEN Bad "esc to recs"
Expect "a1 age:41 name:Al zip:0123", "preview"

PRINT "G3 bulk via console + paging"
FOR i% = 1 TO 45
  Keys "/" + "INSERT INTO people (_id, age, name) VALUES ('p" + STR$(i%, 2, 0, "0") + "', " + STR$(i%) + ", 'n" + STR$(i%) + "')" + KE$
NEXT
IF IxN% <> 46 THEN Bad "insert count " + STR$(IxN%)
Keys KH$
Expect "people  1/46", "home"
Keys KPD$
Expect "people  24/46", "pgdn"
Keys KR$ + KR$ + KR$
Expect "people  46/46", "right pages to end"
IF INSTR(SelText$(), "p45") = 0 THEN Bad "last row should be p45: " + SelText$()
Keys KH$ + KD$ + KD$
IF INSTR(SelText$(), "p02") = 0 THEN Bad "row 3 should be p02: " + SelText$()

PRINT "G4 filter"
Keys "F" + "age >= 40 AND name LIKE 'n4%'" + KE$
IF UiRes% <> 1 OR ExN% <> 6 THEN Bad "filter rows " + STR$(ExN%)
Expect "people  1/6  [age >= 40 AND", "filter title"
Keys "F" + KH$ + "age > " + KE$
IF INSTR(UiMsg$, "at col 7") = 0 THEN Bad "filter error col: " + UiMsg$
Keys KX$
IF UiRes% THEN Bad "esc should clear filter"
Expect "people  1/46", "unfiltered"

PRINT "G5 detail edit, type rules, navigation"
Keys KH$ + KD$ + KE$
IF RcGet$(DtRec$, "_id") <> "p01" THEN Bad "detail of p01: " + DtRec$
Keys KD$ + KD$ + KE$ + KBS$ + KBS$ + "77" + KE$
IF RcGet$(StFetch$("p01"), "name") <> "77" OR RcT% <> 1 THEN Bad "text field must stay text: " + StFetch$("p01")
Expect "'77'", "literal-looking text quoted"
Keys KU$ + KE$ + KBS$ + "9" + KE$
IF RcGet$(StFetch$("p01"), "age") <> "9" OR RcT% <> 2 THEN Bad "age edit"
Keys KR$
IF RcGet$(DtRec$, "_id") <> "p02" THEN Bad "right -> p02"
Keys KL$ + KL$
IF RcGet$(DtRec$, "_id") <> "a1" THEN Bad "left twice -> a1"
Keys KL$
IF RcGet$(DtRec$, "_id") <> "a1" THEN Bad "left at start stays"
Keys KH$ + KE$
IF UiMsgSt% <> US_ERR THEN Bad "_id edit must be refused"
Keys KN$ + KDEL$ + "n"
IF RcCheck%(StFetch$("a1")) <> 4 THEN Bad "remove declined but changed"
Keys KDEL$ + "y"
IF RcCheck%(StFetch$("a1")) <> 3 THEN Bad "remove field"
Keys KX$

PRINT "G6 delete record, describe, help, console text"
Keys KH$ + KDEL$ + "y"
IF IxGet%("a1") >= 0 THEN Bad "a1 not deleted"
Expect "people  1/45", "count after delete"
Keys "D"
IF UiV% <> UV_TEXT THEN Bad "describe view"
Expect "45 records", "describe text"
Keys KX$
IF UiV% <> UV_RECS THEN Bad "back from describe"
Keys KF1$ + KPD$ + KX$
IF UiV% <> UV_RECS THEN Bad "back from help"
Keys "/" + "SELECT name FROM people WHERE age < 3 ORDER BY age DESC" + KE$
Expect "p02 name:n2", "projection"
IF INSTR(Scr$(1), "p02") = 0 THEN Bad "desc order first row: " + Scr$(1)
Keys "/" + "SELECT COUNT(*) FROM people" + KE$
Expect "count = 45", "count"
Keys "/" + "SELEC" + KE$
IF UiMsgSt% <> US_ERR THEN Bad "console error"
Keys "/" + KU$ + KU$ + KE$
Expect "count = 45", "history recall"
Keys "/" + "UPDATE people SET flag = true WHERE age > 40" + KE$
Expect "5 updated", "update msg"
Keys KX$ + KX$
IF UiV% <> UV_COLL THEN Bad "back to collections"

PRINT "G7 drop collection from list + quit"
Keys KN$ + KDEL$ + "y"
Expect "Collections (1)", "after drop"
Keys KX$ + "n"
IF UiQuit% THEN Bad "quit declined"
Keys KX$ + "y"
IF UiQuit% = 0 THEN Bad "quit"
UiQuit% = 0
PRINT "  fails so far"; Fail%

PRINT "G9 help"
Fuzz% = 0
ok% = StCreate%("people")
UiListColl "" : UiGo UV_COLL : UiPaint
' no help file yet -> built-in key summary
Keys KF1$ + KE$
IF UiV% <> UV_TEXT OR INSTR(ExOut$(0), "no help file") = 0 THEN Bad "fallback help"
Keys KX$
IF UiV% <> UV_COLL THEN Bad "back from fallback"
MKDIR "/tmp/dbg/help"
COPY "/tmp/dbhelp.jsonl" TO "/tmp/dbg/help/dbhelp.jsonl"
SUB HelpCase q$, n%, first$
  UiGo UV_COLL : UiPaint
  Keys KF1$ + q$ + KE$
  IF n% = 0 THEN
    IF UiV% <> UV_COLL OR INSTR(UiMsg$, "no help topics") = 0 THEN Bad "no-match [" + q$ + "]"
    EXIT SUB
  ENDIF
  IF HpN% <> n% THEN Bad "help [" + q$ + "] found" + STR$(HpN%) + " want" + STR$(n%)
  IF HpTitle$(0) <> first$ THEN Bad "help [" + q$ + "] first " + HpTitle$(0)
  IF n% = 1 AND UiV% <> UV_TEXT THEN Bad "single match should open topic"
  IF n% > 1 AND UiV% <> UV_HELP THEN Bad "list view for [" + q$ + "]"
END SUB
HelpCase "", 35, "Getting started"
HelpCase "INDEX speed", 1, "Indexes: faster searches"
HelpCase "like", 7, "Collections"
HelpCase "null missing", 1, "Missing fields and NULL"
HelpCase "vacuum", 2, "VACUUM: reclaim space"
HelpCase "zzz", 0, ""
HelpCase "power CRASH", 1, "Power loss and crashes"

' read a topic, check wrapping and navigation
UiGo UV_COLL : UiPaint
Keys KF1$ + KE$
Expect "Help: contents (35)", "contents title"
DIM j%
FOR j% = 0 TO HpN% - 1
  HpShow j%
  IF ExOutN% >= EX_OUTMAX THEN Bad "topic too long " + HpTitle$(j%)
  FOR i% = 0 TO ExOutN% - 1
    IF LEN(ExOut$(i%)) > HalW% THEN Bad "line too wide in " + HpTitle$(j%)
  NEXT
  UiGo UV_HELP
NEXT
UiPaint
Keys KN$ + KE$
Expect "Searching this help", "last topic title"
Expect "F1 asks for words.", "topic text"
Keys KX$
IF UiV% <> UV_HELP THEN Bad "esc from topic -> list"
Keys KX$
IF UiV% <> UV_COLL THEN Bad "esc from help list -> collections"
' help from detail returns to detail
Keys KE$ + "N" + "h1" + KE$
Keys KF1$ + "insert" + KE$ + KE$
IF UiV% <> UV_TEXT THEN Bad "topic from detail"
DO WHILE UiV% = UV_TEXT OR UiV% = UV_HELP : Keys KX$ : LOOP
IF UiV% <> UV_DET THEN Bad "help should return to detail, view" + STR$(UiV%)
Keys KX$ + KX$
Keys "N" + "order" + KE$
IF INSTR(UiMsg$, "SQL word") = 0 THEN Bad "reserved collection name accepted"
PRINT "G8 random keys"
Fuzz% = 1
FOR i% = 1 TO 5 : Seen%(i%) = 0 : NEXT
DIM keyset$ = KU$ + KD$ + KL$ + KR$ + KH$ + KN$ + KPD$ + CHR$(136) + KE$ + KX$ + KDEL$ + KBS$ + KF1$ + "/NADFynab1 '%=<"
DIM it%, q$
FOR it% = 1 TO 120
  q$ = ""
  FOR i% = 1 TO 25 : q$ = q$ + MID$(keyset$, 1 + INT(RND * LEN(keyset$)), 1) : NEXT
  Keys q$
  MkUnder% = 0
  IF UiQuit% THEN UiQuit% = 0
  IF StList%() = 0 THEN ok% = StCreate%("people") : UiListColl ""
  IF Fail% > 15 THEN EXIT FOR
NEXT
PRINT "  keys sent"; (it% - 1) * 25; "  steps in coll/recs/detail/text/help:"; Seen%(1); Seen%(2); Seen%(3); Seen%(4); Seen%(5)
PRINT "TOTAL FAILS:"; Fail%
