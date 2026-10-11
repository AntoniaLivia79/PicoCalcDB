' test_almanac.bas - tests for almanac.bas with a mock display/keyboard.
' 1. python3 almanac_testprep.py almanac.csv   (writes /tmp/alm/...)
' 2. Run: OPTION EXPLICIT + OPTION DEFAULT NONE + dblib_min.bas + almanac.bas
'    (paths changed to /tmp/alm/, main call removed) + this file, in MMB4L.

' ======================= ALMANAC HARNESS (mock HAL) ==================
DIM Fail% = 0
RANDOMIZE 8642
SUB Bad m$
  PRINT "FAIL: "; m$ : INC Fail%
END SUB
' ---- mock HAL ------------------------------------------------------
DIM HalW% = 40, HalH% = 26
DIM Scr$(25) LENGTH 40, ScrSt%(25), Snap$(25) LENGTH 40, MkQ$, MkUnder%, Keys%
SUB HalInit
END SUB
SUB HalCls
  LOCAL r%
  FOR r% = 0 TO HalH% - 1 : Scr$(r%) = SPACE$(HalW%) : NEXT
END SUB
SUB HalText c%, r%, s$, st%
  IF r% < 0 OR r% >= HalH% OR c% < 0 OR c% + LEN(s$) > HalW% THEN Bad "draw outside screen r" + STR$(r%) : EXIT SUB
  Scr$(r%) = LEFT$(Scr$(r%), c%) + s$ + MID$(Scr$(r%), c% + LEN(s$) + 1)
  ScrSt%(r%) = st%
END SUB
' CHR$(1) in the key queue = take a snapshot of the screen
FUNCTION HalKey%()
  LOCAL r%
  INC Keys%
  FOR r% = 0 TO HalH% - 1
    IF AmDrawn%(r%) = 0 THEN Bad "row" + STR$(r%) + " not drawn this frame"
  NEXT
  DO WHILE LEFT$(MkQ$, 1) = CHR$(1)
    FOR r% = 0 TO HalH% - 1 : Snap$(r%) = Scr$(r%) : NEXT
    MkQ$ = MID$(MkQ$, 2)
  LOOP
  IF MkQ$ = "" THEN INC MkUnder% : HalKey% = 27 : EXIT FUNCTION
  HalKey% = ASC(MkQ$) : MkQ$ = MID$(MkQ$, 2)
END FUNCTION
CONST KE$ = CHR$(13), KX$ = CHR$(27), KU$ = CHR$(128), KD$ = CHR$(129)
CONST KL$ = CHR$(130), KR$ = CHR$(131), KH$ = CHR$(134), KN$ = CHR$(135), KS$ = CHR$(1)
' Run the app from the main menu with a key script; it unwinds with Esc
SUB RunKeys s$
  MkQ$ = s$ : MkUnder% = 0
  AmMenu
END SUB
FUNCTION SnapHas%(t$)
  LOCAL r%
  FOR r% = 0 TO HalH% - 1
    IF INSTR(Snap$(r%), t$) THEN SnapHas% = r% + 1 : EXIT FUNCTION
  NEXT
END FUNCTION
SUB DumpSnap
  LOCAL r%
  FOR r% = 0 TO HalH% - 1 : PRINT "   |"; Snap$(r%); "|" : NEXT
END SUB
SUB Expect t$, tag$
  IF SnapHas%(t$) = 0 THEN Bad tag$ + ": [" + t$ + "] not on screen" : DumpSnap
END SUB
SUB WriteCsv p$, a$, b$, c$, d$, e$
  OPEN p$ FOR OUTPUT AS #7
  PRINT #7, a$ : IF b$ <> "" THEN PRINT #7, b$
  IF c$ <> "" THEN PRINT #7, c$
  IF d$ <> "" THEN PRINT #7, d$
  IF e$ <> "" THEN PRINT #7, e$
  CLOSE #7
END SUB

DIM f$, i%, n%, ok%, r$, id$, v$, q$, x$, e$(7), dn%, split%
HalCls
DbInit "/tmp/alm/db"
f$ = DIR$("/tmp/alm/db/*", FILE)
DO WHILE f$ <> "" : KILL "/tmp/alm/db/" + f$ : f$ = DIR$("/tmp/alm/db/*", FILE) : LOOP

PRINT "L1 dates"
FOR dn% = AmDays%("1999-12-28") TO AmDays%("2032-03-05")
  IF AmDays%(AmDate$(dn%)) <> dn% THEN Bad "date round trip " + AmDate$(dn%) : EXIT FOR
NEXT
IF AmWeekday$(AmDays%("2026-10-01")) <> "Thu" THEN Bad "weekday"
IF AmDays%("2027-02-29") >= 0 OR AmDays%("2028-02-29") < 0 THEN Bad "leap years"
IF AmDays%("2026-13-01") >= 0 OR AmDays%("2026-1-01") >= 0 OR AmDays%("x026-10-01") >= 0 THEN Bad "invalid dates"
IF AmLongDate$(AmDays%("2026-10-01")) <> "Thu 1 Oct 2026" THEN Bad "long date " + AmLongDate$(AmDays%("2026-10-01"))

PRINT "L2 menu without data, then create via Maintain"
RunKeys KS$ + "2" + KS$
Expect "Load the data first", "browse refused before load"
RunKeys "1" + "C" + KS$ + KX$
Expect "854 stored, 0 skipped", "import summary"
Expect "885 records", "maintain record count"
Expect "Thu 1 Oct 2026 to", "maintain first date"
Expect "Fri 31 Dec 2027", "maintain last date"

PRINT "L3 every CSV row round-trips, weekdays match"
ok% = AmOpen%()
IF DbCount%() <> 885 THEN Bad "record count " + STR$(DbCount%())
OPEN "/tmp/alm/expected.txt" FOR INPUT AS #8
n% = 0 : split% = 0
DO WHILE NOT EOF(#8)
  FOR i% = 0 TO 7 : LINE INPUT #8, e$(i%) : NEXT
  INC n%
  r$ = DbGet$(e$(0))
  IF r$ = "" THEN Bad "missing " + e$(0) : CONTINUE DO
  IF DbStr$(r$, "cat") <> e$(1) THEN Bad e$(0) + " cat"
  IF DbStr$(r$, "event") <> e$(2) THEN Bad e$(0) + " event"
  IF DbStr$(r$, "detail") <> e$(3) THEN Bad e$(0) + " detail"
  v$ = DbStr$(r$, "lore")
  IF v$ = "" AND e$(4) <> "" THEN v$ = DbStr$(DbGet$(e$(0) + "L"), "lore") : INC split%
  IF v$ <> e$(4) THEN Bad e$(0) + " lore [" + v$ + "]"
  IF DbStr$(r$, "place") <> e$(5) THEN Bad e$(0) + " place"
  IF DbStr$(r$, "cert") <> e$(6) THEN Bad e$(0) + " cert"
  IF AmWeekday$(AmDays%(LEFT$(e$(0), 10))) <> e$(7) THEN Bad e$(0) + " weekday " + AmWeekday$(AmDays%(LEFT$(e$(0), 10)))
LOOP
CLOSE #8
PRINT "  rows checked"; n%; "  sayings in companion records"; split%
IF DbMetaGet$("rows") <> "854" OR DbMetaGet$("first") <> "2026-10-01" OR DbMetaGet$("last") <> "2027-12-31" THEN Bad "metadata"

PRINT "L4 browse"
RunKeys "2" + KH$ + KS$
Expect "Thu 1 Oct 2026", "first day title"
Expect "Almanac Day", "category heading"
Expect "Sun up 07:00, down 18:37; day 11h36m", "event text"
Expect "Winterfylleth", "second event"
Expect "Good October, a good blast", "lore shown"
RunKeys "2" + KH$ + KL$ + KS$
Expect "Thu 1 Oct 2026", "left at first day stays"
RunKeys "2" + KH$ + "G" + KH$ + CHR$(8) + CHR$(8) + CHR$(8) + CHR$(8) + CHR$(8) + CHR$(8) + CHR$(8) + CHR$(8) + CHR$(8) + CHR$(8) + "2026-10-31" + KE$ + KR$ + KS$
Expect "Sun 1 Nov 2026", "right across month end"
RunKeys "2" + KN$ + KS$
Expect "Fri 31 Dec 2027", "end = last day"
Expect "Hogmanay", "last day event"
RunKeys "2" + KN$ + KR$ + KR$ + KS$
Expect "Fri 31 Dec 2027", "right at last day stays"
RunKeys "2" + KH$ + "+" + KS$
Expect "Sat 31 Oct 2026", "+ = 30 days"
RunKeys "2" + "G" + STRING$(10, CHR$(8)) + "2027-02-30" + KE$ + KS$
Expect "Not a valid date: 2027-02-30", "invalid goto"
RunKeys "2" + "G" + STRING$(10, CHR$(8)) + "2030-01-01" + KE$ + KS$
Expect "Outside 2026-10-01 to 2027-12-31", "goto outside"
RunKeys "2" + "G" + STRING$(10, CHR$(8)) + "2027-07-01" + KE$ + KS$
Expect "Thu 1 Jul 2027", "goto"
Expect "Aefterra Litha", "split-lore day event"
Expect "If July's first day be rainy weather", "companion-record saying shown"
' scrolling: find a day taller than the screen
DIM tall% = -1
FOR dn% = AmFirst% TO AmLast%
  AmBuildDay dn%
  IF AmLN% > HalH% - 3 THEN tall% = dn% : EXIT FOR
NEXT
IF tall% < 0 THEN
  PRINT "  (no day is taller than one screen)"
ELSE
  RunKeys "2" + "G" + STRING$(10, CHR$(8)) + AmDate$(tall%) + KE$ + KS$
  x$ = Snap$(1)
  RunKeys "2" + "G" + STRING$(10, CHR$(8)) + AmDate$(tall%) + KE$ + KD$ + KD$ + KS$
  IF Snap$(1) = x$ THEN Bad "Down did not scroll"
  Expect "Lines 3-", "scroll position shown"
ENDIF
' every day builds, all lines fit
FOR dn% = AmFirst% TO AmLast%
  AmBuildDay dn%
  IF AmLN% = 0 OR AmLN% >= AM_MAXL THEN Bad "day lines " + AmDate$(dn%) + STR$(AmLN%)
  FOR i% = 0 TO AmLN% - 1
    IF LEN(AmL$(i%)) > HalW% THEN Bad "line too wide " + AmDate$(dn%)
  NEXT
NEXT

PRINT "L5 search"
OPEN "/tmp/alm/search.txt" FOR INPUT AS #8
DO WHILE NOT EOF(#8)
  LINE INPUT #8, q$ : LINE INPUT #8, x$ : LINE INPUT #8, id$ : LINE INPUT #8, v$
  n% = AmFind%(q$)
  IF n% <> MIN(VAL(x$), AM_MAXHIT) THEN Bad "search [" + q$ + "] " + STR$(n%) + " want " + x$
  IF n% > 0 THEN
    IF AmHit$(0) <> id$ THEN Bad "search [" + q$ + "] first " + AmHit$(0)
    IF VAL(x$) <= AM_MAXHIT AND AmHit$(n% - 1) <> v$ THEN Bad "search [" + q$ + "] last " + AmHit$(n% - 1)
  ENDIF
LOOP
CLOSE #8
RunKeys "3" + "eclipse" + KE$ + KS$
Expect "'eclipse': 1 found", "search title"
Expect "02 Aug 27", "search row date"
RunKeys "3" + "eclipse" + KE$ + KE$ + KS$
Expect "Mon 2 Aug 2027", "enter opens the day"
RunKeys "3" + "zzzz" + KE$ + KS$
Expect "No details contain: zzzz", "no results"

PRINT "L6 drop and recreate"
RunKeys "1" + "R" + "n" + KS$
Expect "885 records", "declined reload keeps data"
RunKeys "1" + "R" + "y" + KS$
Expect "854 stored, 0 skipped", "reload summary"
ok% = AmOpen%()
IF DbCount%() <> 885 THEN Bad "count after reload " + STR$(DbCount%())

PRINT "L7 awkward CSV files"
DIM QT$ = CHR$(34)
' no BOM, columns in another order, quotes, "" escapes, LF only
OPEN "/tmp/alm/t1.csv" FOR OUTPUT AS #7
PRINT #7, "detail,event,date,saying_or_lore" + CHR$(10);
PRINT #7, QT$ + "a, b" + QT$ + ",E1,2027-03-01," + QT$ + "say " + QT$ + QT$ + "hi" + QT$ + QT$ + QT$ + CHR$(10);
PRINT #7, "d2,E2,2027-03-02," + CHR$(10);
PRINT #7, "d3,E3,2027-02-30,x" + CHR$(10);
PRINT #7, CHR$(10);
PRINT #7, "d4,E4,2027-03-01,"  + CHR$(10);
PRINT #7, "d5," + QT$ + "unclosed,2027-03-03," + CHR$(10);
PRINT #7, STRING$(200, "x");
PRINT #7, STRING$(40, "x") + ",{" + QT$ + "_id" + QT$ + ":1},2027-03-09," + CHR$(10);
PRINT #7, "d6,E6,2027-03-04" + CHR$(10);
CLOSE #7
IF AmImport%("/tmp/alm/t1.csv") = 0 THEN Bad "t1 import: " + AmMsg$
PRINT "  t1: "; AmMsg$
IF INSTR(AmMsg$, "4 stored, 3 skipped") = 0 THEN Bad "t1 summary " + AmMsg$
r$ = DbGet$("2027-03-01.01")
IF DbStr$(r$, "detail") <> "a, b" OR DbStr$(r$, "lore") <> "say " + QT$ + "hi" + QT$ THEN Bad "quoted fields: " + r$
IF DbStr$(DbGet$("2027-03-01.02"), "event") <> "E4" THEN Bad "repeated date gets next sequence"
IF DbHas%(DbGet$("2027-03-02.01"), "lore") THEN Bad "empty lore stored"
IF DbExists%("2027-03-04.01") = 0 THEN Bad "row after long line lost"
IF DbExists%("2027-03-09.01") THEN Bad "tail of over-long line imported"
WriteCsv "/tmp/alm/t2.csv", "date,event,weekday", "2027-01-01,x,Fri", "", "", ""
IF AmImport%("/tmp/alm/t2.csv") OR INSTR(AmMsg$, "needs date, event and detail") = 0 THEN Bad "missing column: " + AmMsg$
IF AmImport%("/tmp/alm/nope.csv") OR INSTR(AmMsg$, "not found") = 0 THEN Bad "missing file: " + AmMsg$
' restore the real data
IF AmImport%("/tmp/alm/almanac.csv") = 0 THEN Bad "reload real data"

PRINT "L8 random keys"
DIM keyset$ = KU$ + KD$ + KL$ + KR$ + KH$ + KN$ + KE$ + KX$ + CHR$(136) + CHR$(137) + CHR$(8) + "23GgTt+-anmo19 2026-1"
FOR i% = 1 TO 150
  q$ = ""
  FOR n% = 1 TO 20 : q$ = q$ + MID$(keyset$, 1 + INT(RND * LEN(keyset$)), 1) : NEXT
  RunKeys q$
  IF Fail% > 15 THEN EXIT FOR
NEXT
PRINT "  key presses"; Keys%
PRINT "TOTAL FAILS:"; Fail%
