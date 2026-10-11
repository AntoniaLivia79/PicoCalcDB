' test_query.bas - tests for dbquery.bas
' Run: OPTION EXPLICIT + dbcore.bas + dbquery.bas + this file.

' ======================= PARSER HARNESS ==============================
DIM Fail% = 0
RANDOMIZE 4242
SUB Bad m$
  PRINT "FAIL: "; m$ : INC Fail%
END SUB
DIM QQ$ = CHR$(34)
SUB OkCase q$, want$
  IF QParse%(q$) = 0 THEN
    Bad "parse error " + QErr$ : PRINT "   q    "; q$ : EXIT SUB
  ENDIF
  IF QPlan$() <> want$ THEN
    Bad "plan mismatch" : PRINT "   q    "; q$ : PRINT "   got  "; QPlan$() : PRINT "   want "; want$
  ENDIF
END SUB
SUB ErrCase q$, want$
  IF QParse%(q$) THEN Bad "accepted [" + q$ + "] " + QPlan$() : EXIT SUB
  IF INSTR(QErr$, want$) = 0 THEN Bad "err [" + q$ + "] got " + QErr$ + " want " + want$
  IF INSTR(QErr$, " at col ") = 0 THEN Bad "no col [" + q$ + "] " + QErr$
END SUB

PRINT "P1 table"
DIM big$, want$, it%
OkCase "SELECT * FROM people", "SELECT|people||||-1,0"
OkCase "select name, age from people where age >= 18 and name like 'a%' order by age desc limit 10 offset 5;", "SELECT|people|name,age|^age >= 18;^name LIKE 'a%';AND|age DESC|10,5"
OkCase "SELECT COUNT(*) FROM p WHERE a = 1 OR b = 2", "SELECT|p|COUNT|a = 1;b = 2;OR||-1,0"
OkCase "SELECT * FROM p WHERE (a = 1 OR b = 2) AND c = 'x'", "SELECT|p||a = 1;b = 2;OR;^c = 'x';AND||-1,0"
OkCase "SELECT * FROM p WHERE NOT a IS NULL AND b IS NOT NULL", "SELECT|p||a IS NULL;NOT;^b IS NOT NULL;AND||-1,0"
OkCase "SELECT * FROM p WHERE name NOT LIKE 'x_' ", "SELECT|p||name LIKE 'x_';NOT||-1,0"
OkCase "SELECT * FROM p WHERE " + QQ$ + "first name" + QQ$ + " = 'it''s' AND " + QQ$ + "order" + QQ$ + " != -2.5e1", "SELECT|p||^first name = 'it's';^order <> -2.5e1;AND||-1,0"
OkCase "SELECT * FROM p WHERE flag = TRUE", "SELECT|p||^flag = true||-1,0"
OkCase "INSERT INTO p (_id, name, age) VALUES ('x1', 'Al', 40)", "INSERT|p|_id='x1',name='Al',age=40|||-1,0"
OkCase "UPDATE p SET age = 41, vip = true UNSET old, tmp WHERE _id = 'x1'", "UPDATE|p|age=41,vip=true,-old,-tmp|^_id = 'x1'||-1,0"
OkCase "UPDATE p UNSET a", "UPDATE|p|-a|||-1,0"
OkCase "DELETE FROM p WHERE age < 0", "DELETE|p||^age < 0||-1,0"
OkCase "DELETE FROM p", "DELETE|p||||-1,0"
OkCase "create collection people", "CREATE COLLECTION|people||||-1,0"
OkCase "DROP COLLECTION people", "DROP COLLECTION|people||||-1,0"
OkCase "CREATE INDEX ON p (age)", "CREATE INDEX|p|age|||-1,0"
OkCase "DROP INDEX ON p(" + QQ$ + "first name" + QQ$ + ")", "DROP INDEX|p|first name|||-1,0"
OkCase "SHOW COLLECTIONS", "SHOW|||||-1,0"
OkCase "DESCRIBE p", "DESCRIBE|p||||-1,0"
OkCase "VACUUM p;", "VACUUM|p||||-1,0"
OkCase "EXPLAIN SELECT * FROM p WHERE a=1", "SELECT|p||^a = 1||-1,0"
IF QExplain% <> 1 THEN Bad "explain flag"
OkCase "SELECT * FROM p WHERE a=1 AND (b=2 AND c=3)", "SELECT|p||^a = 1;^b = 2;^c = 3;AND;AND||-1,0"
OkCase "SELECT * FROM p WHERE a<-5", "SELECT|p||^a < -5||-1,0"
OkCase "SELECT * FROM p WHERE a = 1 AND b = 2 OR c = 3", "SELECT|p||a = 1;b = 2;AND;c = 3;OR||-1,0"
OkCase "SELECT * FROM p WHERE NOT NOT a = 1", "SELECT|p||a = 1;NOT;NOT||-1,0"
OkCase "SELECT a FROM p ORDER BY a ASC LIMIT 0", "SELECT|p|a||a|0,0"
IF QExplain% <> 0 THEN Bad "explain flag stuck"
big$ = "SELECT * FROM p WHERE ((a=1))"
FOR it% = 2 TO 7 : big$ = big$ + " AND ((a=1))" : NEXT
want$ = "SELECT|p||^a = 1"
FOR it% = 2 TO 7 : want$ = want$ + ";^a = 1;AND" : NEXT
OkCase big$, want$ + "||-1,0"

ErrCase "", "unknown command"
ErrCase "SELEC * FROM p", "unknown command"
ErrCase "SELECT * FROM", "expected a collection name"
ErrCase "SELECT * p", "expected FROM"
ErrCase "SELECT * FROM p WHERE", "expected a field name"
ErrCase "SELECT * FROM p WHERE a", "expected an operator"
ErrCase "SELECT * FROM p WHERE a =", "expected a value"
ErrCase "SELECT * FROM p WHERE a = 'x", "unclosed string"
ErrCase "SELECT * FROM p WHERE (a = 1", "expected )"
ErrCase "SELECT * FROM p WHERE a = 1)", "unexpected ')'"
ErrCase "SELECT * FROM p WHERE a LIKE 5", "LIKE needs"
ErrCase "SELECT * FROM p WHERE order = 1", "reserved word"
ErrCase "SELECT * FROM p WHERE a = 1e", "bad number"
ErrCase "SELECT * FROM p WHERE a # 1", "unexpected '#'"
ErrCase "SELECT * FROM p LIMIT 2.5", "whole number"
ErrCase "SELECT * FROM p WHERE " + QQ$ + QQ$ + " = 1", "empty name"
ErrCase "SELECT * FROM p WHERE " + QQ$ + "abc = 1", "unclosed name"
ErrCase "INSERT INTO p (a, b) VALUES (1)", "fewer values"
ErrCase "INSERT INTO p (a) VALUES (1, 2)", "more values"
ErrCase "INSERT INTO p (a, a) VALUES (1, 2)", "duplicate field"
ErrCase "INSERT INTO p (_id) VALUES (5)", "_id must be"
ErrCase "UPDATE p SET _id = 'x'", "_id cannot be changed"
ErrCase "UPDATE p WHERE a = 1", "expected SET or UNSET"
ErrCase "UPDATE p SET a = 1 UNSET a", "duplicate field"
ErrCase "CREATE TABLE p", "expected COLLECTION or INDEX"
ErrCase "CREATE INDEX ON p (_id)", "cannot index"
ErrCase "SELECT * FROM averyveryverylongname1", "too long"
ErrCase "SELECT * FROM p WHERE " + STRING$(13, "(") + "a=1" + STRING$(13, ")"), "too deeply nested"
big$ = "SELECT * FROM p WHERE a=1"
DO WHILE LEN(big$) < 230 : big$ = big$ + " AND a=1" : LOOP
ErrCase big$, "too complex"
ErrCase "SELECT * FROM p WHERE a ! 1", "unexpected '!' at col 25"
ErrCase "SELECT * FROM p WHERE a = '" + STRING$(70, "x") + "'", "value too long"
PRINT "  fails so far"; Fail%

' ---------------- P2: grammar round trip -----------------------------
PRINT "P2 grammar round trip"
DIM GK%, GLeaves%
FUNCTION Pick$(lst$)
  LOCAL n% = 1, i%
  FOR i% = 1 TO LEN(lst$)
    IF MID$(lst$, i%, 1) = "|" THEN INC n%
  NEXT
  Pick$ = FIELD$(lst$, 1 + INT(RND * n%), "|")
END FUNCTION
FUNCTION RCase$(k$)
  LOCAL r = RND
  IF r < 0.33 THEN
    RCase$ = LCASE$(k$)
  ELSEIF r < 0.66 THEN
    RCase$ = k$
  ELSE
    RCase$ = LEFT$(k$, 1) + LCASE$(MID$(k$, 2))
  ENDIF
END FUNCTION
FUNCTION Sp$()
  IF RND < 0.8 THEN Sp$ = " " ELSE Sp$ = "  "
END FUNCTION
' Leaf: returns SQL text, sets rp$ (expected plan entries)
FUNCTION GLeaf$(top%, rp$)
  LOCAL f$, fp$, op$, opn$, v$, vp$, k%, s$, tp% = top%
  k% = INT(RND * 6)
  SELECT CASE k%
    CASE 0 : f$ = "age" : fp$ = f$
    CASE 1 : f$ = "Name_2" : fp$ = f$
    CASE 2 : f$ = "_id" : fp$ = f$
    CASE 3 : f$ = QQ$ + "first name" + QQ$ : fp$ = "first name"
    CASE 4 : f$ = QQ$ + "order" + QQ$ : fp$ = "order"
    CASE ELSE : f$ = "z" : fp$ = f$
  END SELECT
  k% = INT(RND * 12)
  IF k% <= 6 THEN
    op$ = Pick$("=|<>|!=|<|<=|>|>=") : opn$ = op$
    IF op$ = "!=" THEN opn$ = "<>"
    SELECT CASE INT(RND * 7)
      CASE 0 : v$ = "'ab'" : vp$ = "'ab'"
      CASE 1 : v$ = "'it''s'" : vp$ = "'it's'"
      CASE 2 : v$ = "42" : vp$ = v$
      CASE 3 : v$ = "-3.5" : vp$ = v$
      CASE 4 : v$ = "1E3" : vp$ = v$
      CASE 5 : v$ = RCase$("TRUE") : vp$ = "true"
      CASE ELSE : v$ = RCase$("NULL") : vp$ = "null"
    END SELECT
    IF RND < 0.3 THEN s$ = f$ + op$ + v$ ELSE s$ = f$ + Sp$() + op$ + Sp$() + v$
    rp$ = fp$ + " " + opn$ + " " + vp$
  ELSEIF k% <= 8 THEN
    v$ = Pick$("a%|_b|it''s%|")
    vp$ = v$
    IF v$ = "it''s%" THEN vp$ = "it's%"
    IF k% = 7 THEN
      s$ = f$ + Sp$() + RCase$("LIKE") + Sp$() + "'" + v$ + "'"
      rp$ = fp$ + " LIKE '" + vp$ + "'"
    ELSE
      s$ = f$ + Sp$() + RCase$("NOT") + Sp$() + RCase$("LIKE") + Sp$() + "'" + v$ + "'"
      rp$ = fp$ + " LIKE '" + vp$ + "';NOT"
      tp% = 0
    ENDIF
  ELSE
    IF k% = 9 THEN
      s$ = f$ + Sp$() + RCase$("IS") + Sp$() + RCase$("NULL") : rp$ = fp$ + " IS NULL"
    ELSE
      s$ = f$ + Sp$() + RCase$("IS") + Sp$() + RCase$("NOT") + Sp$() + RCase$("NULL") : rp$ = fp$ + " IS NOT NULL"
    ENDIF
  ENDIF
  IF tp% THEN rp$ = "^" + rp$
  INC GLeaves%
  GLeaf$ = s$
END FUNCTION
' Expression tree. GK% returns the kind: 0 leaf, 1 AND, 2 OR, 3 NOT
FUNCTION GExpr$(d%, top%, rp$)
  LOCAL k%, l$, r$, lr$, rr$, lk%, rk%, s$
  k% = INT(RND * 4)
  IF d% >= 3 OR GLeaves% >= 5 THEN k% = 0
  SELECT CASE k%
    CASE 0
      s$ = GLeaf$(top%, rp$) : GK% = 0
    CASE 1, 2
      IF k% = 1 THEN
        l$ = GExpr$(d% + 1, top%, lr$) : lk% = GK%
        r$ = GExpr$(d% + 1, top%, rr$) : rk% = GK%
        IF lk% = 2 THEN l$ = "(" + l$ + ")"
        IF rk% = 1 OR rk% = 2 THEN r$ = "(" + r$ + ")"
        s$ = l$ + Sp$() + RCase$("AND") + Sp$() + r$ : rp$ = lr$ + ";" + rr$ + ";AND"
      ELSE
        l$ = GExpr$(d% + 1, 0, lr$) : lk% = GK%
        r$ = GExpr$(d% + 1, 0, rr$) : rk% = GK%
        IF rk% = 2 THEN r$ = "(" + r$ + ")"
        s$ = l$ + Sp$() + RCase$("OR") + Sp$() + r$ : rp$ = lr$ + ";" + rr$ + ";OR"
      ENDIF
      GK% = k%
    CASE 3
      l$ = GExpr$(d% + 1, 0, lr$) : lk% = GK%
      IF lk% = 1 OR lk% = 2 THEN l$ = "(" + l$ + ")"
      s$ = RCase$("NOT") + Sp$() + l$ : rp$ = lr$ + ";NOT" : GK% = 3
  END SELECT
  IF RND < 0.1 THEN s$ = "(" + Sp$() + s$ + Sp$() + ")"
  GExpr$ = s$
END FUNCTION
DIM ex$, rp$, q$, ntried% = 0
FOR it% = 1 TO 1500
  GLeaves% = 0
  ex$ = GExpr$(0, 1, rp$)
  q$ = RCase$("SELECT") + " * " + RCase$("FROM") + " c " + RCase$("WHERE") + " " + ex$
  IF LEN(q$) <= 255 THEN
    INC ntried%
    want$ = "SELECT|c||" + rp$ + "||-1,0"
    IF LEN(want$) <= 250 THEN OkCase q$, want$
  ENDIF
  IF Fail% > 20 THEN EXIT FOR
NEXT
PRINT "  queries"; ntried%; " fails so far"; Fail%

' ---------------- P3/P4: garbage must never crash --------------------
PRINT "P3 token soup + random bytes"
FUNCTION RpnOk%()
  LOCAL i%, d% = 0
  FOR i% = 0 TO QNN% - 1
    IF QnOp%(i%) = QO_AND OR QnOp%(i%) = QO_OR THEN
      IF d% < 2 THEN EXIT FUNCTION
      INC d%, -1
    ELSEIF QnOp%(i%) = QO_NOT THEN
      IF d% < 1 THEN EXIT FUNCTION
    ELSE
      INC d%
    ENDIF
  NEXT
  RpnOk% = (d% = 1 OR (d% = 0 AND QNN% = 0))
END FUNCTION
DIM voc$ = "SELECT|INSERT|UPDATE|DELETE|FROM|WHERE|AND|OR|NOT|LIKE|IS|NULL|ORDER|BY|LIMIT|OFFSET|INTO|VALUES"
voc$ = voc$ + "|SET|UNSET|CREATE|DROP|INDEX|ON|COLLECTION|*|COUNT|(|)|,|=|<>|<|>=|'x'|'a''b'|'|" + QQ$
voc$ = voc$ + "|" + QQ$ + "f g" + QQ$ + "|12|-1.5|1e|TRUE|p|age|_id|;|!|#|-|.5|DESC"
DIM nok% = 0, nerr% = 0, i%, ok%, x$
FOR it% = 1 TO 3000
  q$ = ""
  FOR i% = 1 TO INT(RND * 18)
    x$ = Pick$(voc$)
    IF LEN(q$) + LEN(x$) + 1 > 255 THEN EXIT FOR
    IF RND < 0.85 THEN q$ = q$ + " " + x$ ELSE q$ = q$ + x$
  NEXT
  IF RND < 0.3 THEN q$ = "SELECT * FROM p WHERE" + LEFT$(q$, 230)
  ok% = QParse%(q$)
  IF ok% THEN
    INC nok%
    IF QErr$ <> "" THEN Bad "ok with error"
    IF RpnOk%() = 0 THEN Bad "bad rpn for [" + q$ + "]"
    x$ = QPlan$()
  ELSE
    INC nerr%
    IF INSTR(QErr$, " at col ") = 0 AND QErr$ <> "query too complex" THEN Bad "err without col [" + q$ + "] " + QErr$
  ENDIF
NEXT
FOR it% = 1 TO 1500
  q$ = ""
  FOR i% = 1 TO INT(RND * 40) : q$ = q$ + CHR$(1 + INT(RND * 255)) : NEXT
  ok% = QParse%(q$)
  IF ok% = 0 AND QErr$ = "" THEN Bad "fail without message"
NEXT
PRINT "  soup parsed"; nok%; " rejected"; nerr%
nok% = 0 : nerr% = 0
DIM p%
FOR it% = 1 TO 1500
  GLeaves% = 0
  q$ = "SELECT * FROM c WHERE " + GExpr$(0, 1, rp$)
  IF LEN(q$) > 240 THEN q$ = LEFT$(q$, 240)
  FOR i% = 1 TO 1 + INT(RND * 2)
    p% = 1 + INT(RND * LEN(q$))
    IF RND < 0.5 THEN
      q$ = LEFT$(q$, p% - 1) + MID$(q$, p% + 1 + INT(RND * 5))
    ELSE
      x$ = Pick$(voc$)
      IF LEN(q$) + LEN(x$) + 2 <= 255 THEN q$ = LEFT$(q$, p% - 1) + " " + x$ + " " + MID$(q$, p%)
    ENDIF
  NEXT
  ok% = QParse%(q$)
  IF ok% THEN
    INC nok%
    IF RpnOk%() = 0 THEN Bad "bad rpn" : PRINT "   q "; q$
  ELSE
    INC nerr%
    IF INSTR(QErr$, " at col ") = 0 AND QErr$ <> "query too complex" THEN Bad "err without col " + QErr$
  ENDIF
NEXT
PRINT "  mutated parsed"; nok%; " rejected"; nerr%
PRINT "TOTAL FAILS:"; Fail%
