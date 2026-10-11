' =====================================================================
' dbapi.bas - Public API of the PicoCalc DB library.
' Needs dbcore, dbstore, dbquery and dbexec (dblib.bas = all of them).
' Everything a script needs starts with "Db". Functions that change
' something return 1 on success, 0 on failure; then DbErr$() says why.
' Library uses file numbers #1-#3 and names starting with Rc Ix Sx St
' Mt Tk Q Ex Db (and constants RC_ IX_ SX_ ST_ MT_ TK_ QO_ QN_ QF_ QV_
' QNV_ EX_): avoid those in your own programs.
' =====================================================================

DIM DbE$                              ' last error message

' Reason the last call failed, or "" after a success
FUNCTION DbErr$()
  DbErr$ = DbE$
END FUNCTION

' Internal: record the outcome of a call (ok% 1/0, error text)
FUNCTION DbOk%(ok%, e$)
  IF ok% THEN DbE$ = "" ELSE DbE$ = e$
  DbOk% = (ok% <> 0)
END FUNCTION

' ---------------- setup and collections ------------------------------

' Use folder d$ for all collections (created if missing)
SUB DbInit d$
  LOCAL p$ = d$
  IF p$ <> "" AND RIGHT$(p$, 1) <> "/" THEN p$ = p$ + "/"
  IF StCol$ <> "" THEN StClose
  StDir$ = p$ : DbE$ = ""
  IF p$ = "" OR p$ = "/" THEN EXIT SUB
  ON ERROR SKIP 1
  MKDIR LEFT$(p$, LEN(p$) - 1)
END SUB

' Create an empty collection (letters, digits, _; up to 16 characters)
FUNCTION DbCreate%(c$)
  DbCreate% = DbOk%(StCreate%(c$), StErr$)
END FUNCTION

' Drop a collection and all its files
FUNCTION DbDrop%(c$)
  DbDrop% = DbOk%(StDrop%(c$), StErr$)
END FUNCTION

' Open collection c$ (closes the one open before). One open at a time.
FUNCTION DbOpen%(c$)
  IF StCol$ = c$ AND c$ <> "" THEN DbOpen% = DbOk%(1, "") : EXIT FUNCTION
  DbOpen% = DbOk%(StOpen%(c$), StErr$)
END FUNCTION

' Save the index and metadata and close. Call before your program ends.
SUB DbClose
  StClose
END SUB

' Save the index and metadata without closing
SUB DbFlush
  StFlush
END SUB

' Name of the open collection, or ""
FUNCTION DbCurrent$()
  DbCurrent$ = StCol$
END FUNCTION

' Warning from the last open ("" if none), e.g. "repaired torn last line"
FUNCTION DbWarn$()
  DbWarn$ = StWarn$
END FUNCTION

' Number of collections; names via DbListName$(0 .. n-1), sorted
FUNCTION DbList%()
  DbList% = StList%()
END FUNCTION

' Name of collection i% from the last DbList% (0-based, sorted)
FUNCTION DbListName$(i%)
  IF i% >= 0 AND i% < StCatN% THEN DbListName$ = StCat$(i%)
END FUNCTION

' ---------------- reading records (open collection) ------------------

' Number of records in the open collection
FUNCTION DbCount%()
  DbCount% = IxN%
END FUNCTION

' Record at position i% (0 .. DbCount%()-1) in _id order
FUNCTION DbAt$(i%)
  IF i% < 0 OR i% >= IxN% THEN DbE$ = "position out of range" : EXIT FUNCTION
  DbAt$ = StAt$(i%) : DbE$ = ""
END FUNCTION

' Record with _id id$, or "" (DbErr$() = "not found")
FUNCTION DbGet$(id$)
  DbGet$ = StFetch$(id$)
  DbE$ = StErr$
END FUNCTION

' 1 if a record with this _id exists (an index lookup, no file read)
FUNCTION DbExists%(id$)
  DbExists% = (IxGet%(id$) > 0)
END FUNCTION

' Position of id$ in _id order (for DbAt$), or -1
FUNCTION DbPos%(id$)
  LOCAL i% = IxBound%(IxK$(), IxN%, id$, 0)
  DbPos% = -1
  IF i% < IxN% THEN
    IF IxK$(i%) = id$ THEN DbPos% = i%
  ENDIF
END FUNCTION

' ---------------- writing records ------------------------------------

' Add a new record (its _id must not exist)
FUNCTION DbInsert%(rec$)
  DbInsert% = DbOk%(StWrite%(rec$, 1), StErr$)
END FUNCTION

' Replace an existing record (same _id)
FUNCTION DbUpdate%(rec$)
  DbUpdate% = DbOk%(StWrite%(rec$, 2), StErr$)
END FUNCTION

' Insert or replace
FUNCTION DbPut%(rec$)
  DbPut% = DbOk%(StWrite%(rec$, 0), StErr$)
END FUNCTION

' Delete a record
FUNCTION DbDelete%(id$)
  DbDelete% = DbOk%(StDelete%(id$), StErr$)
END FUNCTION

' Next free automatic _id ("000001", "000002", ...)
FUNCTION DbNewId$()
  DbNewId$ = StNewId$()
END FUNCTION

' Change one field of a stored record
FUNCTION DbSetText%(id$, f$, v$)
  DbSetText% = DbOk%(StSetField%(id$, f$, v$, 1), StErr$)
END FUNCTION

' Set one field of a stored record to a number
FUNCTION DbSetNum%(id$, f$, n!)
  DbSetNum% = DbOk%(StSetField%(id$, f$, DbNumStr$(n!), 2), StErr$)
END FUNCTION

' Literal: a number as text ("1.5"), true, false or null
FUNCTION DbSetRaw%(id$, f$, lit$)
  DbSetRaw% = DbOk%(StSetField%(id$, f$, lit$, 2), StErr$)
END FUNCTION

' Remove one field from a stored record
FUNCTION DbUnset%(id$, f$)
  DbUnset% = DbOk%(StSetField%(id$, f$, "", 0), StErr$)
END FUNCTION

' ---------------- record strings (no file access) --------------------
' A record is a JSON line such as {"_id":"p1","name":"Ann","age":34}.

' A new record string holding only _id
FUNCTION DbNew$(id$)
  DbNew$ = RcNew$(id$)
END FUNCTION

' Number as JSON text; whole numbers keep all digits
FUNCTION DbNumStr$(n!)
  LOCAL i%
  DbNumStr$ = STR$(n!)
  IF n! < 1E15 AND n! > -1E15 THEN
    IF n! = INT(n!) THEN i% = n! : DbNumStr$ = STR$(i%)
  ENDIF
END FUNCTION

' Value of field f$ as text ("" if missing; check DbHas%)
FUNCTION DbStr$(rec$, f$)
  DbStr$ = RcGet$(rec$, f$)
END FUNCTION

' Value of field f$ as a number (0 if missing or not a number)
FUNCTION DbNum!(rec$, f$)
  LOCAL v$ = RcGet$(rec$, f$)
  IF RcT% = 2 AND RcIsNum%(v$) THEN DbNum! = VAL(v$)
END FUNCTION

' 1 if rec$ has field f$
FUNCTION DbHas%(rec$, f$)
  LOCAL v$ = RcGet$(rec$, f$)
  DbHas% = RcFound%
END FUNCTION

' Kind of field f$: "S" text, "N" number, "L" true/false/null,
' "O" list/object (read-only), "" missing
FUNCTION DbKind$(rec$, f$)
  LOCAL v$ = RcGet$(rec$, f$)
  IF RcFound% = 0 THEN EXIT FUNCTION
  SELECT CASE RcT%
    CASE 1 : DbKind$ = "S"
    CASE 3 : DbKind$ = "O"
    CASE ELSE
      IF RcIsNum%(v$) THEN DbKind$ = "N" ELSE DbKind$ = "L"
  END SELECT
END FUNCTION

' Copies of rec$ with one field set or removed ("" + DbErr$ if the
' result would be over 255 characters)
FUNCTION DbWithText$(rec$, f$, v$)
  DbWithText$ = RcSet$(rec$, f$, v$, 1) : DbE$ = RcErr$
END FUNCTION

' Copy of rec$ with field f$ set to a number
FUNCTION DbWithNum$(rec$, f$, n!)
  DbWithNum$ = RcSet$(rec$, f$, DbNumStr$(n!), 2) : DbE$ = RcErr$
END FUNCTION

' Copy of rec$ with field f$ set to a literal: number text, true, false or null
FUNCTION DbWithRaw$(rec$, f$, lit$)
  DbWithRaw$ = RcSet$(rec$, f$, lit$, 2) : DbE$ = RcErr$
END FUNCTION

' Number, true, false or null if v$ looks like one, otherwise text
' (handy when importing CSV or serial data)
FUNCTION DbWithAuto$(rec$, f$, v$)
  IF RcLit%(v$) THEN DbWithAuto$ = RcSet$(rec$, f$, v$, 2) ELSE DbWithAuto$ = RcSet$(rec$, f$, v$, 1)
  DbE$ = RcErr$
END FUNCTION

' Copy of rec$ without field f$
FUNCTION DbWithout$(rec$, f$)
  DbWithout$ = RcDel$(rec$, f$)
END FUNCTION

' 1 if rec$ is a well-formed record line
FUNCTION DbValid%(rec$)
  DbValid% = (RcCheck%(rec$) >= 0)
END FUNCTION

' Number of fields in rec$ (including _id)
FUNCTION DbFieldCount%(rec$)
  DbFieldCount% = MAX(0, RcCheck%(rec$))
END FUNCTION

' Name / value of the i%-th field (0-based) of rec$
FUNCTION DbFieldName$(rec$, i%)
  LOCAL k$, v$
  IF DbNth%(rec$, i%, k$, v$) THEN DbFieldName$ = k$
END FUNCTION

' Value of the i%-th field of rec$, as text
FUNCTION DbFieldValue$(rec$, i%)
  LOCAL k$, v$
  IF DbNth%(rec$, i%, k$, v$) THEN DbFieldValue$ = v$
END FUNCTION

' Internal: find the i%-th field; name and value returned in k$ and v$
FUNCTION DbNth%(rec$, i%, k$, v$)
  LOCAL ip% = 1, n% = 0, t%
  DO
    ip% = RcNext%(rec$, ip%, k$, v$, t%)
    IF ip% <= 0 THEN EXIT FUNCTION
    IF n% = i% THEN DbNth% = 1 : EXIT FUNCTION
    INC n%
  LOOP
END FUNCTION

' ---------------- queries --------------------------------------------

' Run one SQL-like statement (see the user guide). Then:
'   SELECT        DbRows%(), DbRow$(i)  (rows stay readable until VACUUM)
'   COUNT(*)      DbResult%()
'   SHOW/DESCRIBE/EXPLAIN  DbLines%(), DbLine$(i)
'   others        DbMsg$()  e.g. "3 updated", "inserted 000012"
' The collection named in the statement becomes the open one.
FUNCTION DbQuery%(sql$)
  DbQuery% = DbOk%(ExRun%(sql$), ExErr$)
END FUNCTION

' Number of rows from the last SELECT
FUNCTION DbRows%()
  DbRows% = ExN%
END FUNCTION

' Row i% of the last SELECT: the record as it was when the query ran
FUNCTION DbRow$(i%)
  IF i% >= 0 AND i% < ExN% THEN DbRow$ = StRead$(ExR%(i%))
END FUNCTION

' Result of the last SELECT COUNT(*)
FUNCTION DbResult%()
  DbResult% = ExCnt%
END FUNCTION

' Number of text lines from the last SHOW, DESCRIBE or EXPLAIN
FUNCTION DbLines%()
  DbLines% = ExOutN%
END FUNCTION

' Text line i% from the last SHOW, DESCRIBE or EXPLAIN
FUNCTION DbLine$(i%)
  IF i% >= 0 AND i% < ExOutN% THEN DbLine$ = ExOut$(i%)
END FUNCTION

' Summary of the last statement, e.g. "3 updated", "inserted 000012"
FUNCTION DbMsg$()
  DbMsg$ = ExMsg$
END FUNCTION

' ---------------- metadata (open collection) -------------------------

' Fields seen in the collection: DbFields%(), then for i = 0 .. n-1
' DbFieldInfo$(i) = name and DbFieldType$(i) = S N L O or X (mixed)
FUNCTION DbFields%()
  DbFields% = MtN%
END FUNCTION

' Name of known field i% of the open collection
FUNCTION DbFieldInfo$(i%)
  IF i% >= 0 AND i% < MtN% THEN DbFieldInfo$ = MtF$(i%)
END FUNCTION

' Kind of known field i%: S, N, L, O or X (mixed)
FUNCTION DbFieldType$(i%)
  IF i% >= 0 AND i% < MtN% THEN DbFieldType$ = MtT$(i%)
END FUNCTION

' Indexed fields as a comma list, e.g. "age,name"
FUNCTION DbIndexes$()
  LOCAL i%, s$
  FOR i% = 0 TO SX_SLOTS - 1
    IF SxF$(i%) <> "" THEN
      IF s$ <> "" THEN s$ = s$ + ","
      s$ = s$ + SxF$(i%)
    ENDIF
  NEXT
  DbIndexes$ = s$
END FUNCTION

' 1 if field f$ is indexed
FUNCTION DbIsIndexed%(f$)
  DbIsIndexed% = (SxSlot%(f$) >= 0)
END FUNCTION

' Index field f$ (up to 4 per collection); saved at once
FUNCTION DbIndexAdd%(f$)
  DbIndexAdd% = DbOk%(StIndexAdd%(f$), StErr$)
  IF DbIndexAdd% THEN StFlush
END FUNCTION

' Remove the index on field f$; saved at once
FUNCTION DbIndexDrop%(f$)
  DbIndexDrop% = DbOk%(StIndexDrop%(f$), StErr$)
  IF DbIndexDrop% THEN StFlush
END FUNCTION

' Superseded/deleted lines in the file (VACUUM removes them)
FUNCTION DbDead%()
  DbDead% = MtDead%
END FUNCTION

' Rewrite the data file without dead lines
FUNCTION DbVacuum%()
  DbVacuum% = DbOk%(StVacuum%(), StErr$)
END FUNCTION

' Your own collection properties, kept in the .meta file (all of them
' together at most about 230 characters). Saved by DbFlush / DbClose.
FUNCTION DbMetaGet$(k$)
  DbMetaGet$ = RcGet$(MtUser$, k$)
END FUNCTION

' Set a property (text); saved by DbFlush / DbClose
FUNCTION DbMetaSet%(k$, v$)
  LOCAL r$
  IF StCol$ = "" THEN DbMetaSet% = DbOk%(0, "no collection open") : EXIT FUNCTION
  IF LEFT$(k$, 1) = "_" OR k$ = "" THEN DbMetaSet% = DbOk%(0, "bad property name") : EXIT FUNCTION
  r$ = RcSet$(MtUser$, k$, v$, 1)
  IF r$ = "" THEN DbMetaSet% = DbOk%(0, RcErr$) : EXIT FUNCTION
  MtUser$ = r$ : MtDirty% = 1
  DbMetaSet% = DbOk%(1, "")
END FUNCTION

' Remove a property
FUNCTION DbMetaDel%(k$)
  IF StCol$ = "" THEN DbMetaDel% = DbOk%(0, "no collection open") : EXIT FUNCTION
  IF LEFT$(k$, 1) = "_" THEN DbMetaDel% = DbOk%(0, "bad property name") : EXIT FUNCTION
  MtUser$ = RcDel$(MtUser$, k$) : MtDirty% = 1
  DbMetaDel% = DbOk%(1, "")
END FUNCTION

' Property names: DbMetaName$(0), (1) ... until ""
FUNCTION DbMetaName$(i%)
  DbMetaName$ = DbFieldName$(MtUser$, i% + 1)
END FUNCTION
