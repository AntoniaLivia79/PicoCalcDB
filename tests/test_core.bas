' test_core.bas - randomized tests for dbcore.bas
' Run: OPTION EXPLICIT + dbcore.bas + this file, as one program.
' Uses /tmp/c.jsonl - change DF$/XF$ to e.g. B:/ paths on a PicoCalc.

' ======================= TEST HARNESS ================================
DIM Fail% = 0
RANDOMIZE 12345
SUB Bad m$
  PRINT "FAIL: "; m$ : INC Fail%
END SUB

FUNCTION RndStr$(mx%)
  LOCAL i%, n% = INT(RND * (mx% + 1)), s$, c%
  FOR i% = 1 TO n%
    c% = INT(RND * 12)
    SELECT CASE c%
      CASE 0 : s$ = s$ + CHR$(34)
      CASE 1 : s$ = s$ + "\"
      CASE 2 : s$ = s$ + CHR$(10)
      CASE 3 : s$ = s$ + CHR$(9)
      CASE 4 : s$ = s$ + CHR$(1 + INT(RND * 30))
      CASE 5 : s$ = s$ + CHR$(128 + INT(RND * 128))
      CASE 6 : s$ = s$ + ","
      CASE 7 : s$ = s$ + "}"
      CASE ELSE : s$ = s$ + CHR$(97 + INT(RND * 4))
    END SELECT
  NEXT
  RndStr$ = s$
END FUNCTION

FUNCTION RndNum$()
  LOCAL c% = INT(RND * 6)
  SELECT CASE c%
    CASE 0 : RndNum$ = STR$(INT(RND * 101) - 50)
    CASE 1 : RndNum$ = STR$(INT(RND * 400) / 4 - 50)
    CASE 2 : RndNum$ = STR$(INT(RND * 9) + 1) + "e" + STR$(INT(RND * 3))
    CASE 3 : RndNum$ = "-" + STR$(INT(RND * 9)) + "." + STR$(INT(RND * 99)) + "E-1"
    CASE 4 : RndNum$ = "60000000000"
    CASE ELSE : RndNum$ = STR$(INT(RND * 7))
  END SELECT
END FUNCTION

' ---------------- T1: codec fuzz -------------------------------------
PRINT "T1 codec"
DIM mk$(15), mv$(15), mt%(15), mn%, it%, r$, r2$, x$, i%, j%, k$, v$, t%, op%
DIM nset% = 0, nlong% = 0
FOR it% = 1 TO 1500
  mn% = 1 : mk$(0) = "_id" : mv$(0) = "id" + STR$(it%) : mt%(0) = 1
  r$ = RcNew$(mv$(0))
  FOR op% = 1 TO 12
    j% = INT(RND * 8)
    IF RND < 0.3 THEN k$ = RndStr$(4) ELSE k$ = "f" + STR$(INT(RND * 6))
    IF RND < 0.5 THEN
      v$ = RndStr$(40) : t% = 1
    ELSE
      v$ = RndNum$() : t% = 2
    ENDIF
    IF j% = 0 AND mn% > 1 THEN
      i% = 1 + INT(RND * (mn% - 1))
      r2$ = RcDel$(r$, mk$(i%))
      r$ = r2$
      FOR j% = i% TO mn% - 2 : mk$(j%) = mk$(j% + 1) : mv$(j%) = mv$(j% + 1) : mt%(j%) = mt%(j% + 1) : NEXT
      INC mn%, -1
    ELSE
      r2$ = RcSet$(r$, k$, v$, t%)
      IF r2$ = "" THEN
        IF RcErr$ <> "too long" THEN Bad "set err " + RcErr$
        INC nlong%
      ELSE
        r$ = r2$ : INC nset%
        i% = -1
        FOR j% = 0 TO mn% - 1
          IF mk$(j%) = k$ THEN i% = j%
        NEXT
        IF i% < 0 THEN
          IF mn% > 15 THEN Bad "model full" : EXIT FOR
          i% = mn% : INC mn%
        ENDIF
        mk$(i%) = k$ : mv$(i%) = v$ : mt%(i%) = t%
      ENDIF
    ENDIF
    IF LEN(r$) > 255 THEN Bad "len>255"
    IF RcCheck%(r$) <> mn% THEN Bad "count " + STR$(RcCheck%(r$)) + " vs " + STR$(mn%) + " " + r$
    FOR i% = 0 TO mn% - 1
      x$ = RcGet$(r$, mk$(i%))
      IF RcFound% = 0 OR x$ <> mv$(i%) OR RcT% <> mt%(i%) THEN Bad "get " + mk$(i%) + " in " + r$
    NEXT
  NEXT
  FOR i% = 1 TO 3
    j% = 1 + INT(RND * (LEN(r$) - 1))
    IF RcCheck%(LEFT$(r$, j%)) >= 0 THEN
      IF RIGHT$(LEFT$(r$, j%), 1) <> "}" THEN Bad "trunc accepted " + LEFT$(r$, j%)
    ENDIF
  NEXT
NEXT
PRINT "  sets"; nset%; " too-long rejects"; nlong%
' foreign formatting
r$ = "  { " + CHR$(34) + "_id" + CHR$(34) + " : " + CHR$(34) + "a\u0041\/" + CHR$(34)
r$ = r$ + " , " + CHR$(34) + "tags" + CHR$(34) + ":[1,{" + CHR$(34) + "x}" + CHR$(34) + ":2}] ,"
r$ = r$ + CHR$(34) + "n" + CHR$(34) + ": -1.5e2 , " + CHR$(34) + "ok" + CHR$(34) + ":true }"
IF RcCheck%(r$) <> 4 THEN Bad "foreign count"
IF RcGet$(r$, "_id") <> "aA/" THEN Bad "foreign id"
x$ = RcGet$(r$, "tags") : IF RcT% <> 3 THEN Bad "nested type " + x$
IF RcGet$(r$, "n") <> "-1.5e2" OR RcT% <> 2 THEN Bad "foreign num"
r2$ = RcSet$(r$, "n", "7", 2) : IF RcGet$(r2$, "tags") <> x$ THEN Bad "nested kept"
r2$ = RcDel$(r2$, "tags") : IF RcCheck%(r2$) <> 3 THEN Bad "del nested " + r2$
r2$ = RcDel$(RcDel$(RcDel$(r2$, "_id"), "ok"), "n")
IF RcCheck%(r2$) <> 0 THEN Bad "del all " + r2$
r2$ = RcSet$(r2$, "z", "1", 2) : IF RcCheck%(r2$) <> 1 THEN Bad "set into empty " + r2$
IF RcSet$("{}", "a", "1x", 2) <> "" THEN Bad "bad literal accepted"
PRINT "  fails so far"; Fail%

' ---------------- T2: primary index model ----------------------------
PRINT "T2 primary index"
DIM rk$(999) LENGTH 16, ro%(999), rn% = 0, o%
IxClear
FOR it% = 1 TO 3000
  k$ = "k" + STR$(INT(RND * 300))
  IF RND < 0.2 THEN k$ = CHR$(65 + INT(RND * 2)) + k$
  i% = -1
  FOR j% = 0 TO rn% - 1
    IF rk$(j%) = k$ THEN i% = j%
  NEXT
  IF RND < 0.35 THEN
    IF IxRemove%(k$) <> (i% >= 0) THEN Bad "remove ret"
    IF i% >= 0 THEN rk$(i%) = rk$(rn% - 1) : ro%(i%) = ro%(rn% - 1) : INC rn%, -1
  ELSE
    o% = it%
    IF IxPut%(k$, o%) = 0 THEN Bad "put " + IxErr$
    IF i% < 0 THEN i% = rn% : INC rn%
    rk$(i%) = k$ : ro%(i%) = o%
  ENDIF
  IF IxGet%(k$) <> -1 AND i% < 0 THEN Bad "ghost"
  IF it% MOD 250 = 0 THEN
    IF IxN% <> rn% THEN Bad "count"
    FOR j% = 1 TO IxN% - 1
      IF IxK$(j% - 1) >= IxK$(j%) THEN Bad "order"
    NEXT
    FOR j% = 0 TO rn% - 1
      IF IxGet%(rk$(j%)) <> ro%(j%) THEN Bad "lookup " + rk$(j%)
    NEXT
  ENDIF
NEXT
' SORT order must equal < order for compaction to be correct
IxN% = 0
FOR i% = 0 TO 199 : IxK$(i%) = RndStr$(5) : IF IxK$(i%) = "" THEN IxK$(i%) = "q"
  IxO%(i%) = i% + 1 : INC IxN% : NEXT
IxCompact
FOR j% = 1 TO IxN% - 1
  IF IxK$(j% - 1) >= IxK$(j%) THEN Bad "sort/compare mismatch"
NEXT
PRINT "  fails so far"; Fail%

' ---------------- T3: file-backed with secondary indexes -------------
PRINT "T3 storage + secondary"
CONST DF$ = "/tmp/c.jsonl", XF$ = "/tmp/c.idx"
DIM live$(150), dlen%, lo%, hi%, n%, c%, ok%
FUNCTION Store%(r$)
  LOCAL id$ = RcGet$(r$, "_id"), oo% = IxGet%(id$), old$, off%
  IF oo% > 0 THEN
    OPEN DF$ FOR INPUT AS #3 : old$ = IxReadAt$(3, oo%) : CLOSE #3
  ENDIF
  OPEN DF$ FOR APPEND AS #2
  off% = LOC(#2)
  PRINT #2, r$
  CLOSE #2
  Store% = IxApply%(r$, off%, old$)
END FUNCTION
FUNCTION LiveIdx%(id$)
  LiveIdx% = VAL(MID$(id$, 2))
END FUNCTION
FUNCTION Match%(r$, f$, op$, v$, t%)
  LOCAL x$ = RcGet$(r$, f$), a!, b!
  IF RcFound% = 0 THEN EXIT FUNCTION
  IF t% = 2 THEN
    IF RcT% <> 2 THEN EXIT FUNCTION
    a! = VAL(x$) : b! = VAL(v$)
    IF a! > 4.9E10 THEN a! = 4.9E10
    IF b! > 4.9E10 THEN b! = 4.9E10
  ENDIF
  SELECT CASE op$
    CASE "="  : IF t% = 2 THEN Match% = (a! = b!) ELSE Match% = (x$ = v$)
    CASE "<"  : IF t% = 2 THEN Match% = (a! < b!) ELSE Match% = (x$ < v$)
    CASE "<=" : IF t% = 2 THEN Match% = (a! <= b!) ELSE Match% = (x$ <= v$)
    CASE ">"  : IF t% = 2 THEN Match% = (a! > b!) ELSE Match% = (x$ > v$)
    CASE ">=" : IF t% = 2 THEN Match% = (a! >= b!) ELSE Match% = (x$ >= v$)
    CASE "LIKE" : Match% = (LEFT$(x$, LEN(v$)) = v$)
  END SELECT
END FUNCTION
FUNCTION RndName$()
  LOCAL i%, s$
  FOR i% = 1 TO 1 + INT(RND * 14) : s$ = s$ + MID$("ab", 1 + INT(RND * 2), 1) : NEXT
  RndName$ = s$
END FUNCTION
SUB CheckIndexes tag$
  LOCAL i%, j%, s%, q%, f$, op$, v$, t%, lo%, hi%, cnt%, hit%, r$, nl% = 0
  LOCAL ops$(5) = ("=", "<", "<=", ">", ">=", "LIKE")
  FOR i% = 0 TO 150
    IF live$(i%) <> "" THEN INC nl%
  NEXT
  IF nl% <> IxN% THEN Bad tag$ + " live count " + STR$(nl%) + " vs " + STR$(IxN%)
  OPEN DF$ FOR INPUT AS #4
  FOR i% = 0 TO IxN% - 1
    r$ = IxReadAt$(4, IxO%(i%))
    IF r$ <> live$(LiveIdx%(IxK$(i%))) THEN Bad tag$ + " stale primary " + IxK$(i%)
  NEXT
  ' every secondary entry must point at a live offset
  FOR i% = 0 TO SxN% - 1
    hit% = 0
    FOR j% = 0 TO IxN% - 1
      IF IxO%(j%) = SxO%(i%) THEN hit% = 1 : EXIT FOR
    NEXT
    IF hit% = 0 THEN Bad tag$ + " stale secondary " + SxV$(i%)
  NEXT
  FOR q% = 1 TO 40
    IF RND < 0.5 THEN
      f$ = "age" : v$ = RndNum$() : t% = 2 : op$ = ops$(INT(RND * 5))
    ELSE
      f$ = "name" : v$ = RndName$() : t% = 1 : op$ = ops$(INT(RND * 6))
      IF op$ = "LIKE" THEN v$ = LEFT$(v$, 1 + INT(RND * 13))
    ENDIF
    s% = SxSlot%(f$)
    SxRange s%, op$, v$, t%, lo%, hi%
    FOR i% = 0 TO 150
      IF live$(i%) <> "" THEN
        IF Match%(live$(i%), f$, op$, v$, t%) THEN
          hit% = 0
          FOR j% = lo% TO hi% - 1
            IF IxReadAt$(4, SxO%(j%)) = live$(i%) THEN hit% = 1 : EXIT FOR
          NEXT
          IF hit% = 0 THEN Bad tag$ + " missed " + f$ + op$ + v$ + " " + live$(i%)
        ENDIF
      ENDIF
    NEXT
  NEXT
  CLOSE #4
END SUB
SUB SnapEq tag$, ak$(), ao%(), an%, sv$(), so%(), sn%
  LOCAL i%, j%, hit%
  IF an% <> IxN% THEN Bad tag$ + " primary count" : EXIT SUB
  FOR i% = 0 TO an% - 1
    IF ak$(i%) <> IxK$(i%) OR ao%(i%) <> IxO%(i%) THEN Bad tag$ + " primary diff " + ak$(i%)
  NEXT
  IF sn% <> SxN% THEN Bad tag$ + " sec count" : EXIT SUB
  FOR i% = 0 TO sn% - 1
    hit% = 0
    FOR j% = 0 TO SxN% - 1
      IF sv$(i%) = SxV$(j%) AND so%(i%) = SxO%(j%) THEN hit% = 1 : EXIT FOR
    NEXT
    IF hit% = 0 THEN Bad tag$ + " sec diff " + sv$(i%)
  NEXT
END SUB
SUB Churn n%
  LOCAL it%, i%, r$
  FOR it% = 1 TO n%
    i% = INT(RND * 151)
    IF RND < 0.15 AND live$(i%) <> "" THEN
      r$ = RcSet$(RcNew$("r" + STR$(i%)), "_del", "1", 2)
      IF Store%(r$) = 0 THEN Bad "store del " + IxErr$
      live$(i%) = ""
    ELSE
      IF live$(i%) = "" THEN r$ = RcNew$("r" + STR$(i%)) ELSE r$ = live$(i%)
      IF RND < 0.8 THEN r$ = RcSet$(r$, "age", RndNum$(), 2) ELSE r$ = RcDel$(r$, "age")
      IF RND < 0.8 THEN r$ = RcSet$(r$, "name", RndName$(), 1) ELSE r$ = RcDel$(r$, "name")
      r$ = RcSet$(r$, "note", RndStr$(20), 1)
      IF r$ = "" THEN Bad "churn set" : CONTINUE FOR
      IF Store%(r$) = 0 THEN Bad "store " + IxErr$
      live$(i%) = r$
    ENDIF
  NEXT
END SUB

IF DIR$(DF$, FILE) <> "" THEN KILL DF$
IF DIR$(XF$, FILE) <> "" THEN KILL XF$
OPEN DF$ FOR OUTPUT AS #2 : CLOSE #2
IxClear
SxF$(0) = "age" : SxF$(2) = "name"
Churn 600
CheckIndexes "incremental"
PRINT "  live"; IxN%; " sec entries"; SxN%; " fails"; Fail%

' snapshot, then full rebuild from file must match
DIM ak$(IX_MAX - 1) LENGTH IX_KLEN, ao%(IX_MAX - 1), an%
DIM sv$(SX_MAX - 1) LENGTH SX_PW + 2, so%(SX_MAX - 1), sn%
SUB Snap
  LOCAL i%
  an% = IxN% : FOR i% = 0 TO IxN% - 1 : ak$(i%) = IxK$(i%) : ao%(i%) = IxO%(i%) : NEXT
  sn% = SxN% : FOR i% = 0 TO SxN% - 1 : sv$(i%) = SxV$(i%) : so%(i%) = SxO%(i%) : NEXT
END SUB
Snap
ok% = IxOpen%(DF$, XF$, 5)
IF ok% = 0 THEN Bad "rebuild " + IxErr$
SnapEq "rebuild", ak$(), ao%(), an%, sv$(), so%(), sn%

' save, churn more, reopen via catch-up
OPEN DF$ FOR INPUT AS #5 : dlen% = LOF(#5) : CLOSE #5
ok% = IxSave%(XF$, 5, dlen%) : IF IxLoad%(XF$, 5) <> dlen% THEN Bad "saved idx not loadable"
ok% = IxOpen%(DF$, XF$, 5)
Churn 300
Snap
ok% = IxOpen%(DF$, XF$, 5)
IF ok% = 0 THEN Bad "catchup " + IxErr$
SnapEq "catchup", ak$(), ao%(), an%, sv$(), so%(), sn%
CheckIndexes "catchup"

' corrupt index file -> must fall back to full rebuild
OPEN XF$ FOR OUTPUT AS #5 : PRINT #5, "IX1" + CHR$(9) + "10" : PRINT #5, "5" + CHR$(9) + "zz" : PRINT #5, "3" + CHR$(9) + "aa" : CLOSE #5
ok% = IxOpen%(DF$, XF$, 5)
SnapEq "corrupt-idx", ak$(), ao%(), an%, sv$(), so%(), sn%

' torn / garbage lines are skipped and counted
OPEN DF$ FOR APPEND AS #2 : PRINT #2, "{" + CHR$(34) + "_id" + CHR$(34) + ":" + CHR$(34) + "r999" : PRINT #2, "garbage" : CLOSE #2
ok% = IxOpen%(DF$, "/tmp/none.idx", 5)
IF IxBad% <> 2 THEN Bad "bad lines" + STR$(IxBad%)
SnapEq "torn", ak$(), ao%(), an%, sv$(), so%(), sn%

' drop & re-add a slot
SxF$(2) = "" : ok% = IxOpen%(DF$, XF$, 5)
FOR i% = 0 TO SxN% - 1
  IF LEFT$(SxV$(i%), 1) <> "A" THEN Bad "slot not dropped"
NEXT
SxF$(2) = "name" : ok% = IxOpen%(DF$, XF$, 5)
CheckIndexes "reopen"
PRINT "TOTAL FAILS:"; Fail%
