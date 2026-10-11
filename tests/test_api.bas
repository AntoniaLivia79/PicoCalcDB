' test_api.bas - tests for the library API (dbapi.bas)
' Run: OPTION EXPLICIT + OPTION DEFAULT NONE + dblib.bas + this file.
' WARNING: deletes every file in /tmp/dbl/ (change DbInit below).

' ======================= LIBRARY API HARNESS =========================
DIM Fail% = 0
RANDOMIZE 2468
SUB Bad m$
  PRINT "FAIL: "; m$ : INC Fail%
END SUB
SUB Ck c%, m$
  IF c% = 0 THEN Bad m$ + "  [DbErr: " + DbErr$() + "]"
END SUB
DIM r$, i%, n%, ok%, x$, f$
' User routines named like library locals (rec$, id$, old$): the
' library build renames its locals, so these must not clash.
SUB Rec a$
END SUB
FUNCTION Id$(a$)
  Id$ = a$
END FUNCTION
SUB Old
END SUB

PRINT "A1 setup and collections"
DbInit "/tmp/dbl"
f$ = DIR$("/tmp/dbl/*", FILE)
DO WHILE f$ <> "" : KILL "/tmp/dbl/" + f$ : f$ = DIR$("/tmp/dbl/*", FILE) : LOOP
Ck StDir$ = "/tmp/dbl/", "DbInit adds /"
Ck DbCreate%("people"), "create"
Ck DbCreate%("pets"), "create 2"
Ck DbCreate%("people") = 0, "dup create must fail"
Ck DbErr$() = "exists", "dup error text: " + DbErr$()
Ck DbList%() = 2, "list count"
Ck DbListName$(0) = "people" AND DbListName$(1) = "pets", "list names"
Ck DbListName$(5) = "", "list out of range"
Ck DbOpen%("nope") = 0, "open missing"
Ck DbOpen%("people"), "open"
Ck DbCurrent$() = "people", "current"
Ck DbCount%() = 0, "empty"

PRINT "A2 record strings"
r$ = DbNew$("p1")
r$ = DbWithText$(r$, "name", "Ann " + CHR$(34) + "Q" + CHR$(34) + " O'Neil")
r$ = DbWithNum$(r$, "age", 34)
r$ = DbWithNum$(r$, "height", 1.68)
r$ = DbWithNum$(r$, "big", 123456789012)
r$ = DbWithRaw$(r$, "vip", "true")
r$ = DbWithText$(r$, "zip", "0123")
Ck DbValid%(r$), "valid: " + r$
Ck DbStr$(r$, "name") = "Ann " + CHR$(34) + "Q" + CHR$(34) + " O'Neil", "text roundtrip"
Ck DbNum!(r$, "age") = 34 AND DbNum!(r$, "height") = 1.68, "numbers"
Ck DbStr$(r$, "big") = "123456789012", "big whole number exact: " + DbStr$(r$, "big")
Ck DbNum!(r$, "zip") = 0, "text is not a number"
Ck DbKind$(r$, "name") = "S" AND DbKind$(r$, "age") = "N" AND DbKind$(r$, "vip") = "L", "kinds"
Ck DbKind$(r$, "nope") = "" AND DbHas%(r$, "nope") = 0 AND DbHas%(r$, "vip"), "has/missing"
Ck DbFieldCount%(r$) = 7, "field count"
Ck DbFieldName$(r$, 0) = "_id" AND DbFieldName$(r$, 2) = "age" AND DbFieldValue$(r$, 2) = "34", "nth field"
Ck DbFieldName$(r$, 99) = "", "nth beyond end"
Ck DbStr$(DbWithout$(r$, "vip"), "vip") = "" AND DbFieldCount%(DbWithout$(r$, "vip")) = 6, "without"
Ck DbWithRaw$(r$, "bad", "12abc") = "" AND DbErr$() <> "", "bad literal rejected"
x$ = DbWithText$(r$, "pad", STRING$(240, "x"))
Ck x$ = "" AND DbErr$() = "too long", "too long rejected: " + DbErr$()
Ck DbNumStr$(-0.5) = "-0.5" AND DbNumStr$(0) = "0" AND DbNumStr$(-7) = "-7", "numstr"
Ck RcIsNum%(DbNumStr$(1.5E-7)) AND RcIsNum%(DbNumStr$(3E20)), "numstr exponent forms"

PRINT "A3 writes"
Ck DbInsert%(r$), "insert"
Ck DbInsert%(r$) = 0 AND DbErr$() = "duplicate _id", "dup insert"
Ck DbUpdate%(DbNew$("zz")) = 0 AND DbErr$() = "not found", "update missing"
Ck DbPut%(DbWithNum$(DbNew$("p2"), "age", 20)), "put new"
Ck DbPut%(DbWithNum$(DbNew$("p2"), "age", 21)), "put replace"
Ck DbNum!(DbGet$("p2"), "age") = 21, "put replaced"
Ck DbSetText%("p2", "name", "Bob"), "set text"
Ck DbSetNum%("p2", "age", 22), "set num"
Ck DbSetRaw%("p2", "vip", "false"), "set raw"
Ck DbSetRaw%("p2", "vip", "maybe") = 0, "set raw bad"
Ck DbUnset%("p2", "vip"), "unset"
Ck DbGet$("p2") = "{" + CHR$(34) + "_id" + CHR$(34) + ":" + CHR$(34) + "p2" + CHR$(34) + "," + CHR$(34) + "age" + CHR$(34) + ":22," + CHR$(34) + "name" + CHR$(34) + ":" + CHR$(34) + "Bob" + CHR$(34) + "}", "p2 text: " + DbGet$("p2")
Ck DbSetText%("nobody", "a", "b") = 0 AND DbErr$() = "not found", "set on missing"
Ck DbSetText%("p2", "_id", "x") = 0, "cannot set _id"
Ck DbInsert%("{bad json") = 0, "bad record rejected"
Ck DbInsert%(DbWithNum$("{}", "a", 1)) = 0, "record without _id rejected"
x$ = DbNewId$() : Ck x$ = "000001", "auto id " + x$
Ck DbInsert%(DbWithText$(DbNew$(x$), "name", "Cy")), "insert auto"
Ck DbNewId$() = "000002", "auto id advances"
Ck DbExists%("p1") AND DbExists%("zz") = 0, "exists"
Ck DbGet$("zz") = "" AND DbErr$() = "not found", "get missing"
Ck DbCount%() = 3, "count 3"
Ck DbAt$(0) = DbGet$("000001") AND DbAt$(2) = DbGet$("p2"), "DbAt in _id order"
Ck DbPos%("p1") = 1 AND DbPos%("p0") = -1, "pos"
Ck DbAt$(3) = "" AND DbErr$() <> "", "DbAt out of range"
Ck DbDelete%("000001"), "delete"
Ck DbDelete%("000001") = 0, "delete twice"
Ck DbCount%() = 2, "count after delete"

PRINT "A4 queries"
FOR i% = 1 TO 30
  ok% = DbPut%(DbWithText$(DbWithNum$(DbNew$("q" + STR$(i%, 2, 0, "0")), "age", i% * 3), "grp", CHR$(65 + i% MOD 3)))
NEXT
Ck DbQuery%("SELECT * FROM people WHERE age >= 60 ORDER BY age DESC"), "select"
Ck DbRows%() = 11, "rows " + STR$(DbRows%())
Ck DbNum!(DbRow$(0), "age") = 90 AND DbNum!(DbRow$(10), "age") = 60, "row order"
Ck DbRow$(11) = "", "row out of range"
Ck DbQuery%("SELECT COUNT(*) FROM people WHERE grp = 'A'"), "count"
Ck DbResult%() = 10, "count result " + STR$(DbResult%())
Ck DbQuery%("UPDATE people SET flag = true WHERE grp = 'B'"), "update"
Ck DbMsg$() = "10 updated", "update msg " + DbMsg$()
Ck DbQuery%("DESCRIBE people"), "describe"
Ck DbLines%() > 3 AND INSTR(DbLine$(0), "records") > 0, "describe lines"
Ck DbQuery%("SELEC") = 0 AND INSTR(DbErr$(), "col") > 0, "query error: " + DbErr$()
Ck DbQuery%("SELECT * FROM pets"), "query other collection"
Ck DbCurrent$() = "pets", "query switches collection"
Ck DbOpen%("people"), "reopen people"
' rows stay readable after writes (append-only)
Ck DbQuery%("SELECT * FROM people WHERE grp = 'C' ORDER BY age"), "select C"
n% = DbRows%()
FOR i% = 0 TO n% - 1
  r$ = DbRow$(i%)
  ok% = DbSetNum%(DbStr$(r$, "_id"), "age", DbNum!(r$, "age") + 1000)
NEXT
Ck DbQuery%("SELECT COUNT(*) FROM people WHERE age > 1000"), "count updated"
Ck DbResult%() = n%, "update while iterating rows: " + STR$(DbResult%()) + " of " + STR$(n%)

PRINT "A5 metadata"
Ck DbIndexAdd%("age"), "index add"
Ck DbIndexAdd%("age") = 0, "index twice"
Ck DbIndexAdd%("grp"), "index add 2"
Ck DbIndexes$() = "age,grp", "indexes " + DbIndexes$()
Ck DbIsIndexed%("grp") AND DbIsIndexed%("name") = 0, "is indexed"
Ck DbQuery%("EXPLAIN SELECT * FROM people WHERE age > 10"), "explain"
Ck INSTR(DbLine$(0), "index on age") > 0, "explain uses index: " + DbLine$(0)
Ck DbFields%() >= 6, "fields " + STR$(DbFields%())
FOR i% = 0 TO DbFields%() - 1
  IF DbFieldInfo$(i%) = "age" THEN Ck DbFieldType$(i%) = "N", "age kind"
  IF DbFieldInfo$(i%) = "zip" THEN Ck DbFieldType$(i%) = "S", "zip kind"
  IF DbFieldInfo$(i%) = "vip" THEN Ck DbFieldType$(i%) = "L", "vip kind"
NEXT
Ck DbDead%() > 0, "dead lines"
Ck DbMetaSet%("title", "Club members"), "meta set"
Ck DbMetaSet%("version", "3"), "meta set 2"
Ck DbMetaSet%("_x", "no") = 0, "meta reserved"
Ck DbMetaGet$("title") = "Club members", "meta get"
Ck DbMetaName$(0) = "title" AND DbMetaName$(1) = "version" AND DbMetaName$(2) = "", "meta names"
Ck DbMetaDel%("version") AND DbMetaGet$("version") = "", "meta del"
DbClose
Ck DbCurrent$() = "", "closed"
Ck DbOpen%("people"), "reopen"
Ck DbMetaGet$("title") = "Club members", "meta persisted"
Ck DbIndexes$() = "age,grp", "indexes persisted"
Ck DbCount%() = 32, "count persisted " + STR$(DbCount%())
Ck DbVacuum%(), "vacuum"
Ck DbDead%() = 0, "dead after vacuum"
Ck DbMetaGet$("title") = "Club members", "meta kept by vacuum"
Ck DbOpen%("pets") AND DbMetaGet$("title") = "", "meta is per collection"
Ck DbMetaSet%("title", STRING$(240, "t")) = 0, "meta too long"
DbClose
Ck DbMetaSet%("a", "b") = 0, "meta needs open collection"
Ck DbDrop%("pets"), "drop"
Ck DbList%() = 1, "list after drop"
DbClose
PRINT "A6 edge cases"
Ck DbOpen%("people"), "open for edge cases"
Ck DbPut%(DbWithText$(DbNew$("e1"), "@user", "data field")), "field named @user"
DbClose
Ck DbOpen%("people"), "reopen after @user field"
Ck DbMetaGet$("title") = "Club members", "meta survives @user data field: " + DbMetaGet$("title")
FOR i% = 0 TO DbFields%() - 1
  Ck LEFT$(DbFieldInfo$(i%), 1) <> "@", "@ fields are not tracked"
NEXT
Ck DbStr$(DbGet$("e1"), "@user") = "data field", "@user value kept"
Rec "x" : Old : Ck Id$("ok") = "ok", "user routines usable"
DbClose
PRINT "TOTAL FAILS:"; Fail%
