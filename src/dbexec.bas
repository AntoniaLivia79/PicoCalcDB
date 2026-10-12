' =====================================================================
' dbexec.bas - Query executor (needs dbcore, dbstore, dbquery)
' ---------------------------------------------------------------------
' ExRun%(q$) parses and runs one statement. Returns 1 or 0 (ExErr$).
' Results, by ExKind$:
'   "ROWS"  ExR%(0..ExN%-1) = file offsets of matching records; read
'           one with StRead$(ExR%(i)). Fields to show: QFld$(0..QFN%-1)
'           (QFN% = 0 means all). Snapshot: re-run after any write.
'   "COUNT" ExCnt%
'   "TEXT"  ExOut$(0..ExOutN%-1): SHOW, DESCRIBE, EXPLAIN output
'   "OK"    writes and admin commands
' ExMsg$ is a one-line summary; ExWarn$ any warning from opening.
' ---------------------------------------------------------------------
' Semantics (schemaless, SQL-like):
' - A comparison on a missing field is false (also <>). Use IS NULL.
' - Number vs number compares numerically ('1e3' = 1000); text vs
'   text compares by character code (case-sensitive), as does LIKE.
'   Mismatched types are never =, <, >; they are <>.
' - Without ORDER BY rows come in _id order (or in index order when
'   an index on another field was used). ORDER BY: missing values
'   last (first with DESC); numbers before text.
' =====================================================================

CONST EX_OUTMAX = 40, EX_W = 52
DIM ExR%(IX_MAX - 1), ExN%, ExCnt%
DIM ExKind$, ExMsg$, ExErr$, ExWarn$, ExPath$
DIM ExOut$(EX_OUTMAX - 1) LENGTH EX_W, ExOutN%
DIM ExSrc%, ExLo%, ExHi%
DIM ExSt%(QN_MAX - 1)

SUB ExSay s$
  IF ExOutN% < EX_OUTMAX THEN ExOut$(ExOutN%) = LEFT$(s$, EX_W) : INC ExOutN%
END SUB

' ---------------- matching -------------------------------------------

' SQL LIKE: % any run, _ any one char. Case-sensitive.
FUNCTION ExLike%(s$, p$)
  LOCAL i% = 1, j% = 1, si% = 0, sj% = 0, ls% = LEN(s$), lp% = LEN(p$), c$
  DO WHILE i% <= ls%
    c$ = MID$(p$, j%, 1)
    IF j% <= lp% AND c$ <> "%" AND (c$ = "_" OR c$ = MID$(s$, i%, 1)) THEN
      INC i% : INC j%
    ELSEIF j% <= lp% AND c$ = "%" THEN
      sj% = j% : si% = i% : INC j%
    ELSEIF sj% > 0 THEN
      INC si% : i% = si% : j% = sj% + 1
    ELSE
      EXIT FUNCTION
    ENDIF
  LOOP
  DO WHILE j% <= lp%
    IF MID$(p$, j%, 1) <> "%" THEN EXIT FUNCTION
    INC j%
  LOOP
  ExLike% = 1
END FUNCTION

' Literal prefix of a LIKE pattern (up to the first wildcard)
FUNCTION ExPrefix$(p$)
  LOCAL i%
  FOR i% = 1 TO LEN(p$)
    IF INSTR("%_", MID$(p$, i%, 1)) THEN EXIT FOR
  NEXT
  ExPrefix$ = LEFT$(p$, i% - 1)
END FUNCTION

' Evaluate leaf node k% against rec$ (1/0)
FUNCTION ExLeaf%(rec$, k%)
  LOCAL x$, v$ = QnV$(k%), op% = QnOp%(k%), t%, c% = 2, nx%, nv%
  x$ = RcGet$(rec$, QnF$(k%)) : t% = RcT%
  IF op% = QO_NULL OR op% = QO_NNULL THEN
    c% = (RcFound% = 0) OR (t% = 2 AND x$ = "null")
    IF op% = QO_NULL THEN ExLeaf% = c% ELSE ExLeaf% = 1 - c%
    EXIT FUNCTION
  ENDIF
  IF RcFound% = 0 THEN EXIT FUNCTION
  IF op% = QO_LIKE THEN
    IF t% = 1 THEN ExLeaf% = ExLike%(x$, v$)
    EXIT FUNCTION
  ENDIF
  IF t% = 2 AND QnT%(k%) = 2 THEN
    nx% = RcIsNum%(x$) : nv% = RcIsNum%(v$)
    IF nx% AND nv% THEN
      c% = SGN(VAL(x$) - VAL(v$))
    ELSEIF nx% = 0 AND nv% = 0 THEN
      c% = (x$ > v$) - (x$ < v$)
    ENDIF
  ELSEIF t% = 1 AND QnT%(k%) = 1 THEN
    c% = (x$ > v$) - (x$ < v$)
  ENDIF
  SELECT CASE op%
    CASE QO_EQ : ExLeaf% = (c% = 0)
    CASE QO_NE : ExLeaf% = (c% <> 0)
    CASE QO_LT : ExLeaf% = (c% = -1)
    CASE QO_LE : ExLeaf% = (c% = -1 OR c% = 0)
    CASE QO_GT : ExLeaf% = (c% = 1)
    CASE QO_GE : ExLeaf% = (c% = 1 OR c% = 0)
  END SELECT
END FUNCTION


' ---------------- access path ----------------------------------------

' Pick the narrowest index range among top-level AND terms.
' ExSrc%: 0 full scan, 1 _id range, 2 secondary index range.
SUB ExPlanPath
  LOCAL k%, s%, op%, lo%, hi%, ok%, v$, t%
  ExSrc% = 0 : ExLo% = 0 : ExHi% = IxN% : ExPath$ = "full scan"
  FOR k% = 0 TO QNN% - 1
    op% = QnOp%(k%) : v$ = QnV$(k%) : t% = QnT%(k%) : ok% = 0
    IF QnTop%(k%) AND op% <= QO_LIKE AND op% <> QO_NE THEN
      IF op% = QO_LIKE THEN v$ = ExPrefix$(v$)
      IF QnF$(k%) = "_id" THEN
        IF op% = QO_LIKE AND v$ <> "" THEN
          lo% = IxBound%(IxK$(), IxN%, v$, 0)
          hi% = IxBound%(IxK$(), IxN%, v$ + STRING$(IX_KLEN, 255), 1)
          ok% = 1
        ELSEIF op% <> QO_LIKE AND t% = 1 THEN
          IxRange QOpName$(op%), v$, lo%, hi% : ok% = (lo% >= 0)
        ENDIF
        IF ok% AND hi% - lo% < ExHi% - ExLo% + (ExSrc% = 0) THEN
          ExSrc% = 1 : ExLo% = lo% : ExHi% = hi% : ExPath$ = "_id range"
        ENDIF
      ELSE
        s% = SxSlot%(QnF$(k%))
        IF s% >= 0 THEN
          IF op% = QO_LIKE THEN
            IF v$ <> "" THEN SxRange s%, "LIKE", v$, 1, lo%, hi% : ok% = 1
          ELSEIF t% = 1 OR RcIsNum%(v$) OR op% = QO_EQ THEN
            SxRange s%, QOpName$(op%), v$, t%, lo%, hi% : ok% = (lo% >= 0)
          ENDIF
          IF ok% AND hi% - lo% < ExHi% - ExLo% + (ExSrc% = 0) THEN
            ExSrc% = 2 : ExLo% = lo% : ExHi% = hi% : ExPath$ = "index on " + QnF$(k%)
          ENDIF
        ENDIF
      ENDIF
    ENDIF
  NEXT
END SUB

' Collect matching offsets into ExR%; stop after lim% (-1 = all)
SUB ExCollect lim%
  LOCAL i%, off%, r$, m%, k%, stp%
  ExN% = 0
  IF lim% = 0 THEN EXIT SUB
  FOR i% = ExLo% TO ExHi% - 1
    IF ExSrc% = 2 THEN off% = SxO%(i%) ELSE off% = IxO%(i%)
    ' evaluate the WHERE (RPN) on a stack; inlined here rather than a
    ' separate function, to keep the call depth low
    r$ = StRead$(off%) : m% = 1
    IF QNN% > 0 THEN
      stp% = 0
      FOR k% = 0 TO QNN% - 1
        SELECT CASE QnOp%(k%)
          CASE QO_AND : INC stp%, -1 : ExSt%(stp% - 1) = ExSt%(stp% - 1) AND ExSt%(stp%)
          CASE QO_OR  : INC stp%, -1 : ExSt%(stp% - 1) = ExSt%(stp% - 1) OR ExSt%(stp%)
          CASE QO_NOT : ExSt%(stp% - 1) = 1 - ExSt%(stp% - 1)
          CASE ELSE   : ExSt%(stp%) = ExLeaf%(r$, k%) : INC stp%
        END SELECT
      NEXT
      m% = ExSt%(0)
    ENDIF
    IF m% THEN
      ExR%(ExN%) = off% : INC ExN%
      IF lim% > 0 AND ExN% >= lim% THEN EXIT SUB
    ENDIF
  NEXT
END SUB

' ---------------- ordering -------------------------------------------

' Sortable key: "1"+number (11 int + 4 frac digits), "2"+text, "3" none
FUNCTION ExSortKey$(rec$, f$)
  LOCAL x$ = RcGet$(rec$, f$), e!, ip%, fr%
  IF RcFound% = 0 OR (RcT% = 2 AND x$ = "null") THEN ExSortKey$ = "3" : EXIT FUNCTION
  IF RcT% = 2 AND RcIsNum%(x$) THEN
    e! = VAL(x$)
    IF e! > 4.9E10 THEN e! = 4.9E10
    IF e! < -4.9E10 THEN e! = -4.9E10
    e! = e! + 5E10 : ip% = INT(e!) : fr% = INT((e! - ip%) * 10000)
    ExSortKey$ = "1" + RIGHT$("0000000000" + STR$(ip%), 11) + RIGHT$("000" + STR$(fr%), 4)
  ELSE
    ExSortKey$ = "2" + LEFT$(x$, 15)
  ENDIF
END FUNCTION

SUB ExReverse
  LOCAL i%, j% = ExN% - 1, t%
  FOR i% = 0 TO ExN% \ 2 - 1
    t% = ExR%(i%) : ExR%(i%) = ExR%(j% - i%) : ExR%(j% - i%) = t%
  NEXT
END SUB

SUB ExSort
  IF ExN% < 2 THEN EXIT SUB
  IF QOrd$ = "_id" AND ExSrc% <> 2 THEN
    IF QDesc% THEN ExReverse
    EXIT SUB
  ENDIF
  LOCAL k$(ExN% - 1) LENGTH 16, ix%(ExN% - 1), tmp%(ExN% - 1), i%
  FOR i% = 0 TO ExN% - 1 : k$(i%) = ExSortKey$(StRead$(ExR%(i%)), QOrd$) : NEXT
  SORT k$(), ix%(), QDesc%
  FOR i% = 0 TO ExN% - 1 : tmp%(i%) = ExR%(ix%(i%)) : NEXT
  FOR i% = 0 TO ExN% - 1 : ExR%(i%) = tmp%(i%) : NEXT
END SUB

' Keep rows QOff%.. (at most QLim% of them)
SUB ExSlice
  LOCAL i%, n%
  n% = ExN% - QOff%
  IF n% < 0 THEN n% = 0
  IF QLim% >= 0 AND n% > QLim% THEN n% = QLim%
  IF QOff% > 0 THEN
    FOR i% = 0 TO n% - 1 : ExR%(i%) = ExR%(i% + QOff%) : NEXT
  ENDIF
  ExN% = n%
END SUB

' ---------------- statements -----------------------------------------

FUNCTION ExUse%(c$)
  IF StCol$ = c$ AND c$ <> "" THEN ExUse% = 1 : EXIT FUNCTION
  ExUse% = StOpen%(c$)
  IF StWarn$ <> "" THEN ExWarn$ = StWarn$
  IF ExUse% = 0 THEN ExErr$ = StErr$
END FUNCTION

SUB ExExplain
  LOCAL i%
  ExKind$ = "TEXT"
  ExSay QCmd$ + " " + QCol$ + ": " + ExPath$ + " (" + STR$(ExHi% - ExLo%) + " of " + STR$(IxN%) + ")"
  IF ExSrc% = 2 THEN ExSay "  index is approximate: rows are re-checked"
  FOR i% = 0 TO QNN% - 1 : ExSay "  " + QNodeTxt$(i%) : NEXT
  IF QOrd$ <> "" AND QDesc% THEN ExSay "order by " + QOrd$ + " desc"
  IF QOrd$ <> "" AND QDesc% = 0 THEN ExSay "order by " + QOrd$
  IF QLim% >= 0 THEN ExSay "limit " + STR$(QLim%) + " offset " + STR$(QOff%)
  ExMsg$ = "plan"
END SUB

SUB ExSelect
  LOCAL lim% = -1
  IF QAgg% AND QNN% = 0 THEN
    ExKind$ = "COUNT" : ExCnt% = IxN% : ExMsg$ = STR$(ExCnt%) : EXIT SUB
  ENDIF
  IF QOrd$ = "" AND QLim% >= 0 AND QAgg% = 0 THEN lim% = QOff% + QLim%
  ExCollect lim%
  IF QAgg% THEN
    ExKind$ = "COUNT" : ExCnt% = ExN% : ExN% = 0 : ExMsg$ = STR$(ExCnt%) : EXIT SUB
  ENDIF
  IF QOrd$ <> "" THEN ExSort
  ExSlice
  ExKind$ = "ROWS" : ExMsg$ = STR$(ExN%) + " row(s)"
END SUB

SUB ExInsert
  LOCAL r$, id$, i%
  FOR i% = 0 TO QFN% - 1
    IF QFld$(i%) = "_id" THEN id$ = QVal$(i%)
  NEXT
  IF id$ = "" THEN id$ = StNewId$()
  r$ = RcNew$(id$)
  FOR i% = 0 TO QFN% - 1
    IF QFld$(i%) <> "_id" AND r$ <> "" THEN r$ = RcSet$(r$, QFld$(i%), QVal$(i%), QVT%(i%))
  NEXT
  IF r$ = "" THEN ExErr$ = "record " + RcErr$ : EXIT SUB
  IF StWrite%(r$, 1) = 0 THEN ExErr$ = StErr$ : EXIT SUB
  ExMsg$ = "inserted " + id$
END SUB

' UPDATE and DELETE: match first, then write (offsets stay valid
' because the file is append-only).
SUB ExModify
  LOCAL i%, j%, n% = 0, r$, id$
  ExCollect -1
  FOR i% = 0 TO ExN% - 1
    r$ = StRead$(ExR%(i%))
    id$ = RcGet$(r$, "_id")
    IF QCmd$ = "DELETE" THEN
      IF StDelete%(id$) = 0 THEN EXIT FOR
    ELSE
      FOR j% = 0 TO QFN% - 1
        IF r$ <> "" THEN
          IF QVT%(j%) = 0 THEN r$ = RcDel$(r$, QFld$(j%)) ELSE r$ = RcSet$(r$, QFld$(j%), QVal$(j%), QVT%(j%))
        ENDIF
      NEXT
      IF r$ = "" THEN StErr$ = id$ + ": record " + RcErr$ : EXIT FOR
      IF StWrite%(r$, 2) = 0 THEN EXIT FOR
    ENDIF
    INC n%
  NEXT
  IF n% < ExN% THEN ExErr$ = STR$(n%) + " of " + STR$(ExN%) + " done; " + StErr$
  IF QCmd$ = "DELETE" THEN ExMsg$ = STR$(n%) + " deleted" ELSE ExMsg$ = STR$(n%) + " updated"
  ExN% = 0
END SUB

SUB ExDescribe
  LOCAL i%, s$
  ExKind$ = "TEXT"
  ExSay QCol$ + ": " + STR$(IxN%) + " records, " + STR$(MtDead%) + " dead lines"
  s$ = ""
  FOR i% = 0 TO SX_SLOTS - 1
    IF SxF$(i%) <> "" THEN s$ = s$ + " " + SxF$(i%)
  NEXT
  ExSay "indexes: _id" + s$
  FOR i% = 0 TO MtN% - 1
    s$ = "  " + MtF$(i%) + " " + MtT$(i%)
    IF SxSlot%(MtF$(i%)) >= 0 THEN s$ = s$ + " (indexed)"
    ExSay s$
  NEXT
  IF MtN% >= MT_MAX THEN ExSay "  (field list full)"
  ExMsg$ = STR$(MtN%) + " field(s)"
END SUB

' Run one statement
FUNCTION ExRun%(q$)
  LOCAL i%, ok%
  ExErr$ = "" : ExWarn$ = "" : ExMsg$ = "" : ExKind$ = "OK"
  ExN% = 0 : ExCnt% = 0 : ExOutN% = 0
  IF QParse%(q$) = 0 THEN ExErr$ = QErr$ : EXIT FUNCTION
  SELECT CASE QCmd$
    CASE "SELECT", "UPDATE", "DELETE"
      IF ExUse%(QCol$) = 0 THEN EXIT FUNCTION
      ExPlanPath
      IF QExplain% THEN
        ExExplain
      ELSEIF QCmd$ = "SELECT" THEN
        ExSelect
      ELSE
        ExModify
      ENDIF
    CASE "INSERT"
      IF ExUse%(QCol$) THEN ExInsert
    CASE "CREATE COLLECTION"
      IF StCreate%(QCol$) THEN ExMsg$ = "created " + QCol$ ELSE ExErr$ = StErr$
    CASE "DROP COLLECTION"
      IF StDrop%(QCol$) THEN ExMsg$ = "dropped " + QCol$ ELSE ExErr$ = StErr$
    CASE "CREATE INDEX", "DROP INDEX"
      IF ExUse%(QCol$) = 0 THEN EXIT FUNCTION
      IF QCmd$ = "CREATE INDEX" THEN ok% = StIndexAdd%(QFld$(0)) ELSE ok% = StIndexDrop%(QFld$(0))
      IF ok% THEN
        StFlush : ExMsg$ = "ok"
      ELSE
        ExErr$ = StErr$
      ENDIF
    CASE "SHOW"
      ExKind$ = "TEXT"
      FOR i% = 0 TO StList%() - 1 : ExSay StCat$(i%) : NEXT
      ExMsg$ = STR$(StCatN%) + " collection(s)"
    CASE "DESCRIBE"
      IF ExUse%(QCol$) THEN ExDescribe
    CASE "VACUUM"
      IF ExUse%(QCol$) THEN
        IF StVacuum%() THEN ExMsg$ = "vacuumed, " + STR$(IxN%) + " live" ELSE ExErr$ = StErr$
      ENDIF
  END SELECT
  ExRun% = (ExErr$ = "")
END FUNCTION

' ---------------- display helpers ------------------------------------

' Display text of field f$ ("" if missing)
FUNCTION ExVal$(rec$, f$)
  LOCAL x$ = RcGet$(rec$, f$)
  IF RcT% = 3 THEN x$ = LEFT$(x$, 1) + ".." + RIGHT$(x$, 1)
  ExVal$ = x$
END FUNCTION

' One result row as "f=v f=v" for the selected fields (or all)
FUNCTION ExRowText$(rec$)
  LOCAL s$, p$, i%, ip% = 1, k$, v$, t%
  IF QFN% = 0 THEN
    DO
      ip% = RcNext%(rec$, ip%, k$, v$, t%)
      IF ip% <= 0 THEN EXIT DO
      IF t% = 3 THEN v$ = LEFT$(v$, 1) + ".." + RIGHT$(v$, 1)
      p$ = k$ + "=" + v$ + " "
      IF LEN(s$) + LEN(p$) > 255 THEN EXIT DO
      s$ = s$ + p$
    LOOP
  ELSE
    FOR i% = 0 TO QFN% - 1
      p$ = QFld$(i%) + "=" + ExVal$(rec$, QFld$(i%)) + " "
      IF LEN(s$) + LEN(p$) > 255 THEN EXIT FOR
      s$ = s$ + p$
    NEXT
  ENDIF
  ExRowText$ = s$
END FUNCTION
