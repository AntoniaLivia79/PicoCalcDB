' test_exec.bas - end-to-end SQL tests for dbexec.bas vs a reference model
' Run: OPTION EXPLICIT + dbcore + dbstore + dbquery + dbexec + this file.
' WARNING: deletes every file in StDir$ (set below to /tmp/dbx/).

' ======================= EXECUTOR HARNESS ============================
DIM Fail% = 0
RANDOMIZE 9090
SUB Bad m$
  PRINT "FAIL: "; m$ : INC Fail%
END SUB
' ---- model --------------------------------------------------------
CONST MM = 199
DIM mky$(MM) LENGTH 16, mrec$(MM), mn% = 0
FUNCTION MFind%(id$)
  LOCAL i%
  MFind% = -1
  FOR i% = 0 TO mn% - 1
    IF mky$(i%) = id$ THEN MFind% = i% : EXIT FUNCTION
  NEXT
END FUNCTION
' ---- random condition trees ---------------------------------------
DIM GOp%(40), GF$(40) LENGTH 8, GV$(40) LENGTH 20, GT%(40), GA%(40), GB%(40), GNn%
FUNCTION RVal$(f$, t%)
  LOCAL k% = INT(RND * 10)
  IF f$ = "_id" THEN
    t% = 1 : RVal$ = "r" + STR$(INT(RND * 30)) : EXIT FUNCTION
  ENDIF
  IF k% < 4 OR (f$ = "age" AND k% < 7) THEN
    t% = 2
    SELECT CASE INT(RND * 4)
      CASE 0 : RVal$ = STR$(INT(RND * 20) - 3)
      CASE 1 : RVal$ = STR$(INT(RND * 40) / 2 - 3)
      CASE 2 : RVal$ = "1E1"
      CASE ELSE : RVal$ = "-0.25"
    END SELECT
  ELSEIF k% < 9 THEN
    t% = 1 : RVal$ = MID$("ab'a'bba", 1 + INT(RND * 6), 1 + INT(RND * 3))
  ELSE
    t% = 2 : IF RND < 0.5 THEN RVal$ = "true" ELSE RVal$ = "null"
  ENDIF
END FUNCTION
FUNCTION GCond%(d%)
  LOCAL n% = GNn%, k% = INT(RND * 10)
  INC GNn%
  IF d% >= 2 OR k% < 5 OR GNn% > 30 THEN
    GF$(n%) = MID$("age   name  tag   _id   ", 1 + 6 * INT(RND * 4), 6)
    GF$(n%) = LEFT$(GF$(n%), INSTR(GF$(n%) + " ", " ") - 1)
    GOp%(n%) = 1 + INT(RND * 9)
    IF GOp%(n%) = QO_LIKE THEN
      GT%(n%) = 1
      IF RND < 0.7 THEN GF$(n%) = "name"
      GV$(n%) = MID$("a%|%b|_ |a_%|%'%|r1%|r2_|%  |__  |_b  |a_  |%_a ", 1 + 4 * INT(RND * 12), 4)
      GV$(n%) = LEFT$(GV$(n%), INSTR(GV$(n%) + " ", " ") - 1)
      IF INSTR(GV$(n%), "|") THEN GV$(n%) = LEFT$(GV$(n%), INSTR(GV$(n%), "|") - 1)
    ELSE
      GV$(n%) = RVal$(GF$(n%), GT%(n%))
    ENDIF
  ELSE
    GOp%(n%) = QO_AND + INT(RND * 3)
    GA%(n%) = GCond%(d% + 1)
    IF GOp%(n%) <> QO_NOT THEN GB%(n%) = GCond%(d% + 1)
  ENDIF
  GCond% = n%
END FUNCTION
FUNCTION SqlVal$(v$, t%)
  LOCAL i%, s$
  IF t% = 2 THEN SqlVal$ = v$ : EXIT FUNCTION
  FOR i% = 1 TO LEN(v$)
    s$ = s$ + MID$(v$, i%, 1)
    IF MID$(v$, i%, 1) = "'" THEN s$ = s$ + "'"
  NEXT
  SqlVal$ = "'" + s$ + "'"
END FUNCTION
FUNCTION GSql$(n%)
  SELECT CASE GOp%(n%)
    CASE QO_AND : GSql$ = "(" + GSql$(GA%(n%)) + ") AND (" + GSql$(GB%(n%)) + ")"
    CASE QO_OR  : GSql$ = "(" + GSql$(GA%(n%)) + ") OR (" + GSql$(GB%(n%)) + ")"
    CASE QO_NOT : GSql$ = "NOT (" + GSql$(GA%(n%)) + ")"
    CASE QO_NULL : GSql$ = GF$(n%) + " IS NULL"
    CASE QO_NNULL : GSql$ = GF$(n%) + " IS NOT NULL"
    CASE QO_LIKE : GSql$ = GF$(n%) + " LIKE " + SqlVal$(GV$(n%), 1)
    CASE ELSE : GSql$ = GF$(n%) + " " + QOpName$(GOp%(n%)) + " " + SqlVal$(GV$(n%), GT%(n%))
  END SELECT
END FUNCTION
' reference LIKE: recursive, independent of ExLike%
FUNCTION RLike%(s$, p$)
  IF p$ = "" THEN RLike% = (s$ = "") : EXIT FUNCTION
  IF LEFT$(p$, 1) = "%" THEN
    IF RLike%(s$, MID$(p$, 2)) THEN RLike% = 1 : EXIT FUNCTION
    IF s$ <> "" THEN RLike% = RLike%(MID$(s$, 2), p$)
    EXIT FUNCTION
  ENDIF
  IF s$ = "" THEN EXIT FUNCTION
  IF LEFT$(p$, 1) = "_" OR LEFT$(p$, 1) = LEFT$(s$, 1) THEN RLike% = RLike%(MID$(s$, 2), MID$(p$, 2))
END FUNCTION
FUNCTION MEv%(n%, r$)
  LOCAL x$, t%, fnd%, c% = 2, a!, b!
  SELECT CASE GOp%(n%)
    CASE QO_AND : MEv% = MEv%(GA%(n%), r$) AND MEv%(GB%(n%), r$) : EXIT FUNCTION
    CASE QO_OR  : MEv% = MEv%(GA%(n%), r$) OR MEv%(GB%(n%), r$) : EXIT FUNCTION
    CASE QO_NOT : MEv% = 1 - MEv%(GA%(n%), r$) : EXIT FUNCTION
  END SELECT
  x$ = RcGet$(r$, GF$(n%)) : t% = RcT% : fnd% = RcFound%
  IF GOp%(n%) = QO_NULL THEN MEv% = (fnd% = 0) OR (x$ = "null" AND t% = 2) : EXIT FUNCTION
  IF GOp%(n%) = QO_NNULL THEN MEv% = 1 - ((fnd% = 0) OR (x$ = "null" AND t% = 2)) : EXIT FUNCTION
  IF fnd% = 0 THEN EXIT FUNCTION
  IF GOp%(n%) = QO_LIKE THEN
    IF t% = 1 THEN MEv% = RLike%(x$, GV$(n%))
    EXIT FUNCTION
  ENDIF
  IF t% = 1 AND GT%(n%) = 1 THEN
    IF x$ < GV$(n%) THEN c% = -1 ELSE c% = (x$ > GV$(n%))
  ELSEIF t% = 2 AND GT%(n%) = 2 THEN
    IF RcIsNum%(x$) AND RcIsNum%(GV$(n%)) THEN
      a! = VAL(x$) : b! = VAL(GV$(n%))
      IF a! < b! THEN c% = -1 ELSE c% = (a! > b!)
    ELSEIF RcIsNum%(x$) = 0 AND RcIsNum%(GV$(n%)) = 0 THEN
      IF x$ < GV$(n%) THEN c% = -1 ELSE c% = (x$ > GV$(n%))
    ENDIF
  ENDIF
  SELECT CASE GOp%(n%)
    CASE QO_EQ : MEv% = (c% = 0)
    CASE QO_NE : MEv% = (c% <> 0)
    CASE QO_LT : MEv% = (c% = -1)
    CASE QO_LE : MEv% = (c% = -1 OR c% = 0)
    CASE QO_GT : MEv% = (c% = 1)
    CASE QO_GE : MEv% = (c% = 1 OR c% = 0)
  END SELECT
END FUNCTION
' reference sort order: category then value; returns -1/0/1
FUNCTION RCmp%(ra$, rb$, f$)
  LOCAL xa$, xb$, ca%, cb%
  xa$ = RcGet$(ra$, f$) : ca% = 2
  IF RcFound% = 0 OR (RcT% = 2 AND xa$ = "null") THEN
    ca% = 3
  ELSEIF RcT% = 2 AND RcIsNum%(xa$) THEN
    ca% = 1
  ENDIF
  xb$ = RcGet$(rb$, f$) : cb% = 2
  IF RcFound% = 0 OR (RcT% = 2 AND xb$ = "null") THEN
    cb% = 3
  ELSEIF RcT% = 2 AND RcIsNum%(xb$) THEN
    cb% = 1
  ENDIF
  IF ca% <> cb% THEN RCmp% = SGN(ca% - cb%) : EXIT FUNCTION
  IF ca% = 1 THEN RCmp% = SGN(VAL(xa$) - VAL(xb$)) : EXIT FUNCTION
  IF ca% = 2 THEN RCmp% = (xa$ > xb$) - (xa$ < xb$)
END FUNCTION
' ---- helpers --------------------------------------------------------
FUNCTION Go%(q$)
  Go% = ExRun%(q$)
  IF Go% = 0 THEN Bad "exec [" + LEFT$(q$, 120) + "] " + ExErr$
END FUNCTION
DIM full%(MM), fullN%
DIM paths$ = "", np%(2)
FUNCTION RowId$(i%)
  RowId$ = RcGet$(StRead$(ExR%(i%)), "_id")
END FUNCTION
SUB CheckSelect
  LOCAL c%, w$, i%, j%, n% = 0, k%, ord$, desc%, lim%, off%, q$, exp%
  GNn% = 0 : c% = GCond%(0) : w$ = GSql$(c%)
  q$ = "SELECT * FROM p WHERE " + w$
  IF LEN(q$) > 200 THEN EXIT SUB
  FOR i% = 0 TO mn% - 1
    IF MEv%(c%, mrec$(i%)) THEN INC n%
  NEXT
  ' COUNT
  IF Go%("SELECT COUNT(*) FROM p WHERE " + w$) = 0 THEN EXIT SUB
  IF ExCnt% <> n% THEN Bad "count " + STR$(ExCnt%) + " want " + STR$(n%) + " [" + LEFT$(w$, 150) + "]"
  ' full result: same set, rows really match
  IF Go%(q$) = 0 THEN EXIT SUB
  IF INSTR(ExPath$, "index") THEN
    INC np%(2)
  ELSEIF INSTR(ExPath$, "_id") THEN
    INC np%(1)
  ELSE
    INC np%(0)
  ENDIF
  IF ExN% <> n% THEN Bad "rows " + STR$(ExN%) + " want " + STR$(n%) + " via " + ExPath$ + " [" + LEFT$(w$, 140) + "]" : EXIT SUB
  fullN% = ExN%
  FOR i% = 0 TO ExN% - 1
    full%(i%) = ExR%(i%)
    k% = MFind%(RowId$(i%))
    IF k% < 0 THEN Bad "row not in model" : EXIT SUB
    IF MEv%(c%, mrec$(k%)) = 0 THEN Bad "row does not match"
    IF StRead$(ExR%(i%)) <> mrec$(k%) THEN Bad "stale row"
    IF i% > 0 AND INSTR(ExPath$, "index") = 0 THEN
      IF RowId$(i% - 1) >= RowId$(i%) THEN Bad "not in _id order"
    ENDIF
  NEXT
  ' LIMIT/OFFSET without ORDER BY = slice of the full result
  lim% = INT(RND * 5) : off% = INT(RND * 4)
  IF Go%(q$ + " LIMIT " + STR$(lim%) + " OFFSET " + STR$(off%)) = 0 THEN EXIT SUB
  exp% = MIN(lim%, MAX(0, fullN% - off%))
  IF ExN% <> exp% THEN Bad "limit count" : EXIT SUB
  FOR i% = 0 TO ExN% - 1
    IF ExR%(i%) <> full%(i% + off%) THEN Bad "limit slice"
  NEXT
  ' ORDER BY: same set, monotonic
  ord$ = MID$("age name tag  _id  ", 1 + 5 * INT(RND * 4), 5)
  ord$ = LEFT$(ord$, INSTR(ord$ + " ", " ") - 1)
  desc% = INT(RND * 2)
  q$ = q$ + " ORDER BY " + ord$
  IF desc% THEN q$ = q$ + " DESC"
  lim% = -1
  IF RND < 0.4 THEN lim% = INT(RND * 6) : q$ = q$ + " LIMIT " + STR$(lim%)
  IF Go%(q$) = 0 THEN EXIT SUB
  IF lim% < 0 THEN exp% = n% ELSE exp% = MIN(lim%, n%)
  IF ExN% <> exp% THEN Bad "order count" : EXIT SUB
  FOR i% = 1 TO ExN% - 1
    j% = RCmp%(StRead$(ExR%(i% - 1)), StRead$(ExR%(i%)), ord$)
    IF (desc% = 0 AND j% > 0) OR (desc% AND j% < 0) THEN Bad "order " + ord$ + STR$(desc%)
  NEXT
END SUB
SUB CheckAll tag$
  LOCAL i%
  IF StCount%() <> mn% THEN Bad tag$ + " count " + STR$(StCount%()) + " vs " + STR$(mn%)
  FOR i% = 0 TO mn% - 1
    IF StFetch$(mky$(i%)) <> mrec$(i%) THEN Bad tag$ + " record " + mky$(i%)
  NEXT
END SUB
SUB DoInsert
  LOCAL id$, r$, q$, f$, v$, t%, flds$, vals$, k%, auto%, ok%, nf% = 0
  LOCAL ef$(2), ev$(2), et%(2)
  auto% = (RND < 0.3)
  IF auto% = 0 THEN
    id$ = "r" + STR$(INT(RND * 30)) : flds$ = "_id" : vals$ = "'" + id$ + "'"
  ENDIF
  FOR k% = 0 TO 2
    f$ = FIELD$("age,name,tag", k% + 1, ",")
    IF RND < 0.75 OR (k% = 2 AND nf% = 0) THEN
      v$ = RVal$(f$, t%)
      IF flds$ <> "" THEN flds$ = flds$ + ", " : vals$ = vals$ + ", "
      flds$ = flds$ + f$ : vals$ = vals$ + SqlVal$(v$, t%)
      ef$(nf%) = f$ : ev$(nf%) = v$ : et%(nf%) = t% : INC nf%
    ENDIF
  NEXT
  q$ = "INSERT INTO p (" + flds$ + ") VALUES (" + vals$ + ")"
  ok% = ExRun%(q$)
  IF auto% THEN
    IF ok% = 0 THEN Bad "auto insert " + ExErr$ : EXIT SUB
    id$ = MID$(ExMsg$, 10)
    IF MFind%(id$) >= 0 THEN Bad "auto id reused " + id$ : EXIT SUB
  ELSEIF MFind%(id$) >= 0 THEN
    IF ok% OR INSTR(ExErr$, "duplicate") = 0 THEN Bad "dup insert: " + ExErr$
    EXIT SUB
  ELSEIF ok% = 0 THEN
    Bad "insert " + ExErr$ : EXIT SUB
  ENDIF
  r$ = RcNew$(id$)
  FOR k% = 0 TO nf% - 1 : r$ = RcSet$(r$, ef$(k%), ev$(k%), et%(k%)) : NEXT
  mky$(mn%) = id$ : mrec$(mn%) = r$ : INC mn%
END SUB
SUB DoUpdate
  LOCAL c%, w$, i%, n% = 0, v$, t%, r$, q$
  GNn% = 0 : c% = GCond%(1) : w$ = GSql$(c%)
  v$ = RVal$("age", t%)
  q$ = "UPDATE p SET age = " + SqlVal$(v$, t%)
  IF RND < 0.5 THEN q$ = q$ + " UNSET tag"
  q$ = q$ + " WHERE " + w$
  FOR i% = 0 TO mn% - 1
    IF MEv%(c%, mrec$(i%)) THEN
      r$ = RcSet$(mrec$(i%), "age", v$, t%)
      IF INSTR(q$, "UNSET") THEN r$ = RcDel$(r$, "tag")
      mrec$(i%) = r$ : INC n%
    ENDIF
  NEXT
  IF Go%(q$) = 0 THEN EXIT SUB
  IF VAL(ExMsg$) <> n% THEN Bad "updated " + ExMsg$ + " want " + STR$(n%)
END SUB
SUB DoDelete
  LOCAL c%, w$, i%, n% = 0
  GNn% = 0 : c% = GCond%(1) : w$ = GSql$(c%)
  i% = 0
  DO WHILE i% < mn%
    IF MEv%(c%, mrec$(i%)) THEN
      mky$(i%) = mky$(mn% - 1) : mrec$(i%) = mrec$(mn% - 1) : INC mn%, -1 : INC n%
    ELSE
      INC i%
    ENDIF
  LOOP
  IF Go%("DELETE FROM p WHERE " + w$) = 0 THEN EXIT SUB
  IF VAL(ExMsg$) <> n% THEN Bad "deleted " + ExMsg$ + " want " + STR$(n%)
END SUB

' ---------------------------------------------------------------------
StDir$ = "/tmp/dbx/"
DIM it%, f$, ok%, i%
ON ERROR SKIP 1 : MKDIR "/tmp/dbx"
f$ = DIR$("/tmp/dbx/*", FILE)
DO WHILE f$ <> "" : KILL "/tmp/dbx/" + f$ : f$ = DIR$("/tmp/dbx/*", FILE) : LOOP

PRINT "E1 admin"
ok% = Go%("CREATE COLLECTION p")
IF ExRun%("CREATE COLLECTION p") THEN Bad "dup create"
IF ExRun%("SELECT * FROM nope") THEN Bad "select missing coll"
IF ExRun%("SELEC x") OR INSTR(ExErr$, "col") = 0 THEN Bad "parse error not reported"
ok% = Go%("CREATE INDEX ON p (age)")
ok% = Go%("CREATE INDEX ON p (name)")

PRINT "E2 random workload"
FOR it% = 1 TO 260
  SELECT CASE INT(RND * 10)
    CASE 0 TO 3 : DoInsert
    CASE 4 : DoUpdate
    CASE 5 : IF RND < 0.25 THEN DoDelete
    CASE ELSE : CheckSelect
  END SELECT
  IF it% = 130 THEN
    StClose
    ok% = Go%("DROP INDEX ON p (name)")
    CheckSelect : CheckSelect
    ok% = Go%("CREATE INDEX ON p (tag)")
    ok% = Go%("VACUUM p")
  ENDIF
  IF it% MOD 65 = 0 THEN CheckAll "it" + STR$(it%)
  IF Fail% > 25 THEN EXIT FOR
NEXT
CheckAll "end"
PRINT "  live"; mn%; "  paths full/_id/index:"; np%(0); np%(1); np%(2); "  fails"; Fail%

PRINT "E3 explain / describe / show"
ok% = Go%("EXPLAIN SELECT * FROM p WHERE age > 3 AND name = 'a'")
IF ExKind$ <> "TEXT" OR INSTR(ExOut$(0), "index on age") = 0 THEN Bad "explain " + ExOut$(0)
FOR i% = 0 TO ExOutN% - 1 : PRINT "  | "; ExOut$(i%) : NEXT
ok% = Go%("DESCRIBE p")
FOR i% = 0 TO ExOutN% - 1 : PRINT "  | "; ExOut$(i%) : NEXT
ok% = Go%("SHOW COLLECTIONS")
IF ExOutN% <> 1 OR ExOut$(0) <> "p" THEN Bad "show"
ok% = Go%("SELECT name, age FROM p WHERE age IS NOT NULL ORDER BY age LIMIT 2")
FOR i% = 0 TO ExN% - 1 : PRINT "  row: "; ExRowText$(StRead$(ExR%(i%))) : NEXT
ok% = Go%("DROP COLLECTION p")
IF ExRun%("SELECT * FROM p") THEN Bad "dropped still readable"
PRINT "TOTAL FAILS:"; Fail%
