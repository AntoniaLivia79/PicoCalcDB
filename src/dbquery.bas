' =====================================================================
' dbquery.bas - Query tokenizer + parser (needs dbcore.bas for RcIsNum%)
' ---------------------------------------------------------------------
' Grammar (keywords are case-insensitive; ; at the end is optional):
'   [EXPLAIN] SELECT * | COUNT(*) | f1, f2 ... FROM c [WHERE cond]
'             [ORDER BY f [ASC|DESC]] [LIMIT n [OFFSET m]]
'   INSERT INTO c (f1, f2 ...) VALUES (v1, v2 ...)
'   UPDATE c [SET f = v, ...] [UNSET f, ...] [WHERE cond]
'   DELETE FROM c [WHERE cond]
'   CREATE COLLECTION c        DROP COLLECTION c
'   CREATE INDEX ON c (f)      DROP INDEX ON c (f)
'   SHOW COLLECTIONS           DESCRIBE c          VACUUM c
' cond: f op value | f [NOT] LIKE 'pat' | f IS [NOT] NULL
'       | NOT cond | cond AND cond | cond OR cond | ( cond )
'   op: = <> != < <= > >=     LIKE wildcards: % and _
' value: 'text' ('' = quote) | number | TRUE | FALSE | NULL
' Field names: letters, digits, _ ; anything else (or a reserved
' word) in double quotes: "first name", "order".
' IS NULL is true when the field is missing or null.
' ---------------------------------------------------------------------
' Output ("the plan"), valid when QParse%() returns 1:
'   QCmd$  SELECT INSERT UPDATE DELETE "CREATE COLLECTION"
'          "DROP COLLECTION" "CREATE INDEX" "DROP INDEX" SHOW
'          DESCRIBE VACUUM            QExplain% = 1 for EXPLAIN
'   QCol$  collection     QAgg% = 1 for COUNT(*)
'   QFld$(0..QFN%-1)      SELECT list (QFN% = 0 means *), INSERT/
'                         UPDATE fields, or the CREATE/DROP INDEX field
'   QVal$(), QVT%()       INSERT/UPDATE values; QVT% 1 string,
'                         2 literal, 0 = UNSET (remove the field)
'   QOrd$, QDesc%, QLim% (-1 = none), QOff%
'   WHERE as RPN in nodes 0..QNN%-1:
'     QnOp%  QO_* code. Leaves: compare QnF$ with QnV$ (type QnT%).
'            AND / OR pop two results, NOT pops one.
'     QnTop% 1 on a leaf that is a top-level AND term: the executor
'            may use an index for it (the whole WHERE implies it).
' =====================================================================

CONST TK_MAX = 128, QN_MAX = 24, QF_MAX = 16, QV_LEN = 128, QNV_LEN = 64
CONST TK_END = 0, TK_ID = 1, TK_NUM = 2, TK_STR = 3, TK_SYM = 4, TK_QID = 5
CONST QO_EQ = 1, QO_NE = 2, QO_LT = 3, QO_LE = 4, QO_GT = 5, QO_GE = 6
CONST QO_LIKE = 7, QO_NULL = 8, QO_NNULL = 9
CONST QO_AND = 20, QO_OR = 21, QO_NOT = 22

DIM TkT%(TK_MAX - 1), TkP%(TK_MAX - 1), TkL%(TK_MAX - 1), TkN%
DIM QText$, QErr$, QPos%
DIM QCmd$, QCol$, QExplain%, QAgg%, QFN%, QOrd$, QDesc%, QLim%, QOff%
DIM QFld$(QF_MAX - 1) LENGTH 24
DIM QVal$(QF_MAX - 1) LENGTH QV_LEN, QVT%(QF_MAX - 1)
DIM QNN%, QnOp%(QN_MAX - 1), QnT%(QN_MAX - 1), QnTop%(QN_MAX - 1)
DIM QnF$(QN_MAX - 1) LENGTH 24, QnV$(QN_MAX - 1) LENGTH QNV_LEN

DIM QRES$ = " SELECT FROM WHERE AND OR NOT LIKE IS NULL ORDER BY LIMIT OFFSET ASC DESC"
QRES$ = QRES$ + " INSERT INTO VALUES UPDATE SET UNSET DELETE CREATE DROP COLLECTION"
QRES$ = QRES$ + " INDEX ON SHOW COLLECTIONS DESCRIBE VACUUM COUNT TRUE FALSE EXPLAIN "
DIM QIDCH$ = "ABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789"

' ---------------- tokenizer ------------------------------------------

' Split s$ into tokens. Returns 1, or 0 with QErr$ set.
FUNCTION QLex%(s$)
  LOCAL i% = 1, j%, n% = LEN(s$), c$, d$
  QText$ = s$ : TkN% = 0
  DO
    DO WHILE i% <= n%
      IF ASC(MID$(s$, i%, 1)) > 32 THEN EXIT DO
      INC i%
    LOOP
    IF TkN% >= TK_MAX THEN QErr$ = "query too complex" : EXIT FUNCTION
    TkP%(TkN%) = i% : TkL%(TkN%) = 0
    IF i% > n% THEN TkT%(TkN%) = TK_END : INC TkN% : QLex% = 1 : EXIT FUNCTION
    c$ = MID$(s$, i%, 1) : d$ = MID$(s$, i% + 1, 1) : j% = i% + 1
    IF INSTR(LEFT$(QIDCH$, 27), UCASE$(c$)) > 0 THEN
      ' identifier or keyword: starts with a letter or _
      DO WHILE j% <= n%
        IF INSTR(QIDCH$, UCASE$(MID$(s$, j%, 1))) = 0 THEN EXIT DO
        INC j%
      LOOP
      TkT%(TkN%) = TK_ID
    ELSEIF INSTR("0123456789", c$) > 0 OR (c$ = "-" AND d$ <> "" AND INSTR("0123456789", d$) > 0) THEN
      DO WHILE j% <= n%
        c$ = MID$(s$, j%, 1)
        IF INSTR("0123456789.eE", c$) = 0 THEN
          IF INSTR("+-", c$) = 0 OR INSTR("eE", MID$(s$, j% - 1, 1)) = 0 THEN EXIT DO
        ENDIF
        INC j%
      LOOP
      IF RcIsNum%(MID$(s$, i%, j% - i%)) = 0 THEN QErr$ = "bad number at col " + STR$(i%) : EXIT FUNCTION
      TkT%(TkN%) = TK_NUM
    ELSEIF c$ = "'" THEN
      DO
        IF j% > n% THEN QErr$ = "unclosed string at col " + STR$(i%) : EXIT FUNCTION
        j% = INSTR(j%, s$, "'")
        IF j% = 0 THEN QErr$ = "unclosed string at col " + STR$(i%) : EXIT FUNCTION
        IF MID$(s$, j% + 1, 1) <> "'" THEN EXIT DO
        INC j%, 2
      LOOP
      INC j%
      TkT%(TkN%) = TK_STR
    ELSEIF c$ = CHR$(34) THEN
      j% = 0
      IF i% < n% THEN j% = INSTR(i% + 1, s$, CHR$(34))
      IF j% = 0 THEN QErr$ = "unclosed name at col " + STR$(i%) : EXIT FUNCTION
      IF j% = i% + 1 THEN QErr$ = "empty name at col " + STR$(i%) : EXIT FUNCTION
      INC j%
      TkT%(TkN%) = TK_QID
    ELSE
      d$ = c$ + d$
      IF d$ = "<=" OR d$ = ">=" OR d$ = "<>" OR d$ = "!=" THEN
        j% = i% + 2
      ELSEIF INSTR("=<>(),*;", c$) = 0 THEN
        QErr$ = "unexpected '" + c$ + "' at col " + STR$(i%) : EXIT FUNCTION
      ENDIF
      TkT%(TkN%) = TK_SYM
    ENDIF
    TkL%(TkN%) = j% - i% : INC TkN% : i% = j%
  LOOP
END FUNCTION

FUNCTION TkRaw$(i%)
  TkRaw$ = MID$(QText$, TkP%(i%), TkL%(i%))
END FUNCTION

' ---------------- parser helpers -------------------------------------

SUB QFail m$
  IF QErr$ = "" THEN QErr$ = m$ + " at col " + STR$(TkP%(QPos%))
END SUB

' Consume keyword kwd$ (upper case) if it is next
FUNCTION QKw%(kwd$)
  IF QErr$ <> "" THEN EXIT FUNCTION
  IF TkT%(QPos%) = TK_ID THEN
    IF UCASE$(MID$(QText$, TkP%(QPos%), TkL%(QPos%))) = kwd$ THEN INC QPos% : QKw% = 1
  ENDIF
END FUNCTION

FUNCTION QNeedKw%(kwd$)
  QNeedKw% = QKw%(kwd$)
  IF QNeedKw% = 0 THEN QFail "expected " + kwd$
END FUNCTION

' Consume symbol s$ if next ("!=" counts as "<>")
FUNCTION QSym%(s$)
  LOCAL r$
  IF QErr$ <> "" THEN EXIT FUNCTION
  IF TkT%(QPos%) = TK_SYM THEN
    r$ = MID$(QText$, TkP%(QPos%), TkL%(QPos%))
    IF r$ = "!=" THEN r$ = "<>"
    IF r$ = s$ THEN INC QPos% : QSym% = 1
  ENDIF
END FUNCTION

FUNCTION QNeedSym%(s$)
  QNeedSym% = QSym%(s$)
  IF QNeedSym% = 0 THEN QFail "expected " + s$
END FUNCTION

' A field name (plain or "quoted")
FUNCTION QName$()
  LOCAL r$
  IF QErr$ <> "" THEN EXIT FUNCTION
  r$ = MID$(QText$, TkP%(QPos%), TkL%(QPos%))
  IF TkT%(QPos%) = TK_QID THEN
    r$ = MID$(r$, 2, LEN(r$) - 2)
  ELSEIF TkT%(QPos%) = TK_ID THEN
    IF INSTR(QRES$, " " + UCASE$(r$) + " ") THEN QFail "reserved word '" + r$ + "' (quote it)" : EXIT FUNCTION
  ELSE
    QFail "expected a field name" : EXIT FUNCTION
  ENDIF
  IF LEN(r$) > 24 THEN QFail "name too long" : EXIT FUNCTION
  INC QPos%
  QName$ = r$
END FUNCTION

' A collection name: plain identifier, max 16 chars
FUNCTION QColName$()
  LOCAL r$
  IF QErr$ <> "" THEN EXIT FUNCTION
  r$ = MID$(QText$, TkP%(QPos%), TkL%(QPos%))
  IF TkT%(QPos%) <> TK_ID OR INSTR(QRES$, " " + UCASE$(r$) + " ") > 0 THEN
    QFail "expected a collection name" : EXIT FUNCTION
  ENDIF
  IF LEN(r$) > 16 THEN QFail "collection name too long" : EXIT FUNCTION
  INC QPos%
  QColName$ = r$
END FUNCTION

' A literal value. t% = 1 string, 2 number/true/false/null
FUNCTION QValue%(v$, t%)
  LOCAL r$, i%
  IF QErr$ <> "" THEN EXIT FUNCTION
  r$ = MID$(QText$, TkP%(QPos%), TkL%(QPos%)) : v$ = ""
  SELECT CASE TkT%(QPos%)
    CASE TK_STR
      r$ = MID$(r$, 2, LEN(r$) - 2) : t% = 1
      DO
        i% = INSTR(r$, "''")
        IF i% = 0 THEN EXIT DO
        v$ = v$ + LEFT$(r$, i%) : r$ = MID$(r$, i% + 2)
      LOOP
      v$ = v$ + r$
    CASE TK_NUM
      v$ = r$ : t% = 2
    CASE TK_ID
      v$ = LCASE$(r$) : t% = 2
      IF v$ <> "true" AND v$ <> "false" AND v$ <> "null" THEN QFail "expected a value" : EXIT FUNCTION
    CASE ELSE
      QFail "expected a value" : EXIT FUNCTION
  END SELECT
  INC QPos%
  QValue% = 1
END FUNCTION

' A whole number for LIMIT / OFFSET
FUNCTION QInt%()
  LOCAL r$ = MID$(QText$, TkP%(QPos%), TkL%(QPos%)), i%
  IF QErr$ <> "" THEN EXIT FUNCTION
  IF TkT%(QPos%) = TK_NUM AND LEN(r$) <= 6 THEN
    FOR i% = 1 TO LEN(r$)
      IF INSTR("0123456789", MID$(r$, i%, 1)) = 0 THEN EXIT FOR
    NEXT
    IF i% > LEN(r$) THEN QInt% = VAL(r$) : INC QPos% : EXIT FUNCTION
  ENDIF
  QFail "expected a whole number"
END FUNCTION

' 1 if field f$ is already in QFld$()
FUNCTION QHas%(f$)
  LOCAL i%
  FOR i% = 0 TO QFN% - 1
    IF QFld$(i%) = f$ THEN QHas% = 1 : EXIT FUNCTION
  NEXT
END FUNCTION

' Comma separated field names into QFld$(); returns count
FUNCTION QNames%(dup%)
  LOCAL f$
  DO
    f$ = QName$()
    IF QErr$ <> "" THEN EXIT FUNCTION
    IF QFN% >= QF_MAX THEN QFail "too many fields" : EXIT FUNCTION
    IF dup% = 0 AND QHas%(f$) THEN QFail "duplicate field '" + f$ + "'" : EXIT FUNCTION
    QFld$(QFN%) = f$ : QVT%(QFN%) = 0 : INC QFN%
  LOOP WHILE QSym%(",")
  QNames% = QFN%
END FUNCTION

' Store value v$ for field slot i%
FUNCTION QSetVal%(i%, v$, t%)
  IF LEN(v$) > QV_LEN THEN QFail "value too long" : EXIT FUNCTION
  QVal$(i%) = v$ : QVT%(i%) = t% : QSetVal% = 1
END FUNCTION

' ---------------- WHERE expression -> RPN ----------------------------
' The condition is parsed iteratively (shunting-yard) with an explicit
' operator stack: no recursion, so the call depth does not grow with
' the length or nesting of the condition. MMBasic programs run on a
' small fixed stack, and every nested SUB/FUNCTION call uses part of it.

FUNCTION QNode%(op%, f$, v$, t%)
  IF QErr$ <> "" THEN EXIT FUNCTION
  IF QNN% >= QN_MAX THEN QFail "condition too complex" : EXIT FUNCTION
  IF LEN(v$) > QNV_LEN THEN QFail "value too long" : EXIT FUNCTION
  QnOp%(QNN%) = op% : QnF$(QNN%) = f$ : QnV$(QNN%) = v$ : QnT%(QNN%) = t%
  QnTop%(QNN%) = 0
  INC QNN%
  QNode% = 1
END FUNCTION

' One comparison: f op value | f [NOT] LIKE 'p' | f IS [NOT] NULL
FUNCTION QLeaf%()
  LOCAL f$, v$, t%, op%, neg%, r$
  f$ = QName$()
  IF QErr$ <> "" THEN EXIT FUNCTION
  IF QKw%("IS") THEN
    neg% = QKw%("NOT")
    IF QNeedKw%("NULL") = 0 THEN EXIT FUNCTION
    IF neg% THEN op% = QO_NNULL ELSE op% = QO_NULL
  ELSE
    neg% = QKw%("NOT")
    IF neg% THEN
      IF QNeedKw%("LIKE") = 0 THEN EXIT FUNCTION
      op% = QO_LIKE
    ELSEIF QKw%("LIKE") THEN
      op% = QO_LIKE
    ELSE
      IF TkT%(QPos%) = TK_SYM THEN
        r$ = MID$(QText$, TkP%(QPos%), TkL%(QPos%))
        SELECT CASE r$
          CASE "="       : op% = QO_EQ
          CASE "<>", "!=" : op% = QO_NE
          CASE "<"       : op% = QO_LT
          CASE "<="      : op% = QO_LE
          CASE ">"       : op% = QO_GT
          CASE ">="      : op% = QO_GE
        END SELECT
      ENDIF
      IF op% = 0 THEN QFail "expected an operator" : EXIT FUNCTION
      INC QPos%
    ENDIF
    IF QValue%(v$, t%) = 0 THEN EXIT FUNCTION
    IF op% = QO_LIKE AND t% <> 1 THEN QFail "LIKE needs a 'text' pattern" : EXIT FUNCTION
  ENDIF
  IF QNode%(op%, f$, v$, t%) = 0 THEN EXIT FUNCTION
  IF neg% AND op% = QO_LIKE THEN
    IF QNode%(QO_NOT, "", "", 0) = 0 THEN EXIT FUNCTION
  ENDIF
  QLeaf% = 1
END FUNCTION

' A whole condition. Operators wait on os%() until an operator of
' lower precedence (or the end, or a closing bracket) releases them:
' NOT 3, AND 2, OR 1; 0 on the stack marks an open bracket.
FUNCTION QCond%()
  LOCAL os%(TK_MAX \ 2), on% = 0, opnd% = 1, op%, k%, par% = 0
  DO
    IF QErr$ <> "" THEN EXIT FUNCTION
    IF opnd% THEN
      IF QKw%("NOT") THEN
        os%(on%) = QO_NOT : INC on%
      ELSEIF QSym%("(") THEN
        INC par%
        IF par% > 12 THEN QFail "too deeply nested" : EXIT FUNCTION
        os%(on%) = 0 : INC on%
      ELSE
        IF QLeaf%() = 0 THEN EXIT FUNCTION
        opnd% = 0
      ENDIF
    ELSE
      op% = 0
      IF QKw%("AND") THEN
        op% = QO_AND
      ELSEIF QKw%("OR") THEN
        op% = QO_OR
      ELSEIF par% > 0 THEN
        IF QSym%(")") THEN op% = -1
      ENDIF
      IF op% = 0 THEN EXIT DO
      ' release waiting operators: all of them back to the bracket for
      ' ")", otherwise those of equal or higher precedence
      DO WHILE on% > 0
        k% = os%(on% - 1)
        IF k% = 0 THEN EXIT DO
        IF op% > 0 THEN
          IF (k% = QO_NOT) * 3 + (k% = QO_AND) * 2 + (k% = QO_OR) < (op% = QO_AND) * 2 + (op% = QO_OR) THEN EXIT DO
        ENDIF
        IF QNode%(k%, "", "", 0) = 0 THEN EXIT FUNCTION
        INC on%, -1
      LOOP
      IF op% = -1 THEN
        INC on%, -1 : INC par%, -1
      ELSE
        os%(on%) = op% : INC on% : opnd% = 1
      ENDIF
    ENDIF
  LOOP
  DO WHILE on% > 0
    k% = os%(on% - 1)
    IF k% = 0 THEN QFail "expected )" : EXIT FUNCTION
    IF QNode%(k%, "", "", 0) = 0 THEN EXIT FUNCTION
    INC on%, -1
  LOOP
  QTopFlags
  QCond% = (QErr$ = "")
END FUNCTION

' Mark the leaves that are top-level AND terms (QnTop% = 1): those
' whose ancestors in the expression tree are all ANDs. Parents are
' found from the RPN with a stack; a parent always follows its
' children, so one backward pass sets every flag.
SUB QTopFlags
  LOCAL pa%(QN_MAX - 1), sk%(QN_MAX - 1), stp% = 0, i%
  IF QNN% = 0 THEN EXIT SUB
  FOR i% = 0 TO QNN% - 1
    IF QnOp%(i%) = QO_AND OR QnOp%(i%) = QO_OR THEN
      pa%(sk%(stp% - 1)) = i% : pa%(sk%(stp% - 2)) = i% : INC stp%, -2
    ELSEIF QnOp%(i%) = QO_NOT THEN
      pa%(sk%(stp% - 1)) = i% : INC stp%, -1
    ENDIF
    sk%(stp%) = i% : INC stp%
  NEXT
  QnTop%(QNN% - 1) = (QnOp%(QNN% - 1) <> QO_OR AND QnOp%(QNN% - 1) <> QO_NOT)
  FOR i% = QNN% - 2 TO 0 STEP -1
    QnTop%(i%) = QnTop%(pa%(i%)) AND (QnOp%(pa%(i%)) = QO_AND)
  NEXT
END SUB

' ---------------- statements -----------------------------------------

SUB QReset
  QErr$ = "" : QPos% = 0 : QCmd$ = "" : QCol$ = ""
  QExplain% = 0 : QAgg% = 0 : QFN% = 0 : QNN% = 0
  QOrd$ = "" : QDesc% = 0 : QLim% = -1 : QOff% = 0
END SUB

SUB QSelect
  LOCAL x%
  IF QKw%("COUNT") THEN
    x% = QNeedSym%("(") : x% = QNeedSym%("*") : x% = QNeedSym%(")")
    QAgg% = 1
  ELSEIF QSym%("*") = 0 THEN
    x% = QNames%(1)
  ENDIF
  x% = QNeedKw%("FROM")
  QCol$ = QColName$()
  IF QKw%("WHERE") THEN x% = QCond%()
  IF QKw%("ORDER") THEN
    x% = QNeedKw%("BY")
    QOrd$ = QName$()
    IF QKw%("DESC") THEN QDesc% = 1 ELSE x% = QKw%("ASC")
  ENDIF
  IF QKw%("LIMIT") THEN
    QLim% = QInt%()
    IF QKw%("OFFSET") THEN QOff% = QInt%()
  ENDIF
END SUB

SUB QInsert
  LOCAL x%, i%, v$, t%
  x% = QNeedKw%("INTO")
  QCol$ = QColName$()
  x% = QNeedSym%("(") : x% = QNames%(0) : x% = QNeedSym%(")")
  x% = QNeedKw%("VALUES") : x% = QNeedSym%("(")
  FOR i% = 0 TO QFN% - 1
    IF QErr$ <> "" THEN EXIT SUB
    IF i% > 0 THEN
      IF QNeedSym%(",") = 0 THEN QErr$ = "" : QFail "fewer values than fields" : EXIT SUB
    ENDIF
    IF QValue%(v$, t%) THEN x% = QSetVal%(i%, v$, t%)
    IF QFld$(i%) = "_id" AND t% <> 1 AND QErr$ = "" THEN QFail "_id must be 'text'"
  NEXT
  IF QErr$ = "" AND QSym%(",") THEN QFail "more values than fields" : EXIT SUB
  x% = QNeedSym%(")")
END SUB

SUB QUpdate
  LOCAL x%, f$, v$, t%, i%
  QCol$ = QColName$()
  IF QKw%("SET") THEN
    DO
      f$ = QName$()
      IF f$ = "_id" THEN QFail "_id cannot be changed"
      IF QHas%(f$) THEN QFail "duplicate field '" + f$ + "'"
      x% = QNeedSym%("=")
      IF QValue%(v$, t%) = 0 THEN EXIT SUB
      IF QFN% >= QF_MAX THEN QFail "too many fields" : EXIT SUB
      QFld$(QFN%) = f$ : x% = QSetVal%(QFN%, v$, t%) : INC QFN%
    LOOP WHILE QSym%(",")
  ENDIF
  IF QKw%("UNSET") THEN
    i% = QFN%
    x% = QNames%(0)
    FOR i% = i% TO QFN% - 1
      IF QFld$(i%) = "_id" THEN QFail "_id cannot be removed"
    NEXT
  ENDIF
  IF QFN% = 0 THEN QFail "expected SET or UNSET"
  IF QKw%("WHERE") THEN x% = QCond%()
END SUB

SUB QIndexDef c$
  LOCAL x%
  QCmd$ = c$ + " INDEX"
  x% = QNeedKw%("ON") : QCol$ = QColName$()
  x% = QNeedSym%("(") : QFld$(0) = QName$() : QFN% = 1 : x% = QNeedSym%(")")
  IF LEFT$(QFld$(0), 1) = "_" AND QErr$ = "" THEN QFail "cannot index _ fields"
END SUB

' Parse one statement. Returns 1 if valid, else 0 with QErr$ set.
FUNCTION QParse%(s$)
  LOCAL x%, c$
  QReset
  IF QLex%(s$) = 0 THEN EXIT FUNCTION
  QExplain% = QKw%("EXPLAIN")
  IF TkT%(QPos%) = TK_ID THEN c$ = UCASE$(MID$(QText$, TkP%(QPos%), TkL%(QPos%)))
  IF INSTR(" SELECT INSERT UPDATE DELETE CREATE DROP SHOW DESCRIBE VACUUM ", " " + c$ + " ") = 0 OR c$ = "" THEN
    QFail "unknown command" : EXIT FUNCTION
  ENDIF
  INC QPos% : QCmd$ = c$
  SELECT CASE c$
    CASE "SELECT" : QSelect
    CASE "INSERT" : QInsert
    CASE "UPDATE" : QUpdate
    CASE "DELETE"
      x% = QNeedKw%("FROM") : QCol$ = QColName$()
      IF QKw%("WHERE") THEN x% = QCond%()
    CASE "CREATE", "DROP"
      IF QKw%("COLLECTION") THEN
        QCmd$ = c$ + " COLLECTION" : QCol$ = QColName$()
      ELSEIF QKw%("INDEX") THEN
        QIndexDef c$
      ELSE
        QFail "expected COLLECTION or INDEX"
      ENDIF
    CASE "SHOW" : x% = QNeedKw%("COLLECTIONS")
    CASE ELSE : QCol$ = QColName$()
  END SELECT
  IF QErr$ = "" THEN
    x% = QSym%(";")
    IF TkT%(QPos%) <> TK_END THEN QFail "unexpected '" + MID$(QText$, TkP%(QPos%), TkL%(QPos%)) + "'"
  ENDIF
  QParse% = (QErr$ = "")
END FUNCTION

FUNCTION QOpName$(op%)
  SELECT CASE op%
    CASE QO_EQ : QOpName$ = "="
    CASE QO_NE : QOpName$ = "<>"
    CASE QO_LT : QOpName$ = "<"
    CASE QO_LE : QOpName$ = "<="
    CASE QO_GT : QOpName$ = ">"
    CASE QO_GE : QOpName$ = ">="
    CASE QO_LIKE : QOpName$ = "LIKE"
    CASE QO_NULL : QOpName$ = "IS NULL"
    CASE QO_NNULL : QOpName$ = "IS NOT NULL"
    CASE QO_AND : QOpName$ = "AND"
    CASE QO_OR : QOpName$ = "OR"
    CASE QO_NOT : QOpName$ = "NOT"
  END SELECT
END FUNCTION

' Text of WHERE node i%; "^" marks an index-eligible top-level term
FUNCTION QNodeTxt$(i%)
  LOCAL p$
  IF QnOp%(i%) >= QO_AND THEN QNodeTxt$ = QOpName$(QnOp%(i%)) : EXIT FUNCTION
  p$ = QnF$(i%) + " " + QOpName$(QnOp%(i%))
  IF QnOp%(i%) < QO_NULL THEN
    IF QnT%(i%) = 1 THEN p$ = p$ + " '" + QnV$(i%) + "'" ELSE p$ = p$ + " " + QnV$(i%)
  ENDIF
  IF QnTop%(i%) THEN p$ = "^" + p$
  QNodeTxt$ = p$
END FUNCTION

' Readable plan, for EXPLAIN and testing (truncated at 255 chars)
FUNCTION QPlan$()
  LOCAL s$, p$, i%
  s$ = QCmd$ + "|" + QCol$ + "|"
  IF QAgg% THEN s$ = s$ + "COUNT"
  FOR i% = 0 TO QFN% - 1
    p$ = QFld$(i%)
    IF QCmd$ = "INSERT" OR QCmd$ = "UPDATE" THEN
      IF QVT%(i%) = 0 THEN
        p$ = "-" + p$
      ELSEIF QVT%(i%) = 1 THEN
        p$ = p$ + "='" + QVal$(i%) + "'"
      ELSE
        p$ = p$ + "=" + QVal$(i%)
      ENDIF
    ENDIF
    IF i% > 0 THEN p$ = "," + p$
    IF LEN(s$) + LEN(p$) > 250 THEN QPlan$ = s$ + "~" : EXIT FUNCTION
    s$ = s$ + p$
  NEXT
  s$ = s$ + "|"
  FOR i% = 0 TO QNN% - 1
    p$ = QNodeTxt$(i%)
    IF i% > 0 THEN p$ = ";" + p$
    IF LEN(s$) + LEN(p$) > 250 THEN QPlan$ = s$ + "~" : EXIT FUNCTION
    s$ = s$ + p$
  NEXT
  p$ = "|" + QOrd$
  IF QDesc% THEN p$ = p$ + " DESC"
  p$ = p$ + "|" + STR$(QLim%) + "," + STR$(QOff%)
  IF LEN(s$) + LEN(p$) > 255 THEN QPlan$ = s$ + "~" : EXIT FUNCTION
  QPlan$ = s$ + p$
END FUNCTION
