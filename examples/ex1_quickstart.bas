' ex1_quickstart.bas - PicoCalc DB library: the basics.
' Needs dblib.bas next to this file (or the library saved with
' LIBRARY SAVE - then delete the #INCLUDE line).
OPTION EXPLICIT
OPTION DEFAULT NONE
#INCLUDE "dblib.bas"

DIM r$, i%, ok%

DbInit "B:/db"

' Open the collection, creating it (with an index) the first time
IF DbOpen%("contacts") = 0 THEN
  IF DbCreate%("contacts") = 0 THEN PRINT "create: "; DbErr$() : END
  ok% = DbOpen%("contacts")
  ok% = DbIndexAdd%("city")
  ok% = DbMetaSet%("title", "My contacts")
ENDIF
PRINT DbMetaGet$("title"); ":"; DbCount%(); " records"

' Build records in memory, then store them. DbPut% inserts or replaces.
r$ = DbNew$("ann")
r$ = DbWithText$(r$, "name", "Ann Smith")
r$ = DbWithNum$(r$, "age", 34)
r$ = DbWithText$(r$, "city", "Leeds")
IF DbPut%(r$) = 0 THEN PRINT "put: "; DbErr$()

r$ = DbWithText$(DbWithNum$(DbNew$("bob"), "age", 41), "city", "York")
r$ = DbWithText$(r$, "name", "Bob Jones")
IF DbPut%(r$) = 0 THEN PRINT "put: "; DbErr$()

' Automatic _id. Check first, so running the program again does not
' add another copy.
ok% = DbQuery%("SELECT COUNT(*) FROM contacts WHERE name = 'Cy Lee'")
IF DbResult%() = 0 THEN
  r$ = DbNew$(DbNewId$())
  r$ = DbWithText$(DbWithText$(r$, "name", "Cy Lee"), "city", "Leeds")
  IF DbInsert%(r$) = 0 THEN PRINT "insert: "; DbErr$()
ENDIF

' Read one record and its fields
r$ = DbGet$("ann")
PRINT DbStr$(r$, "name"); " is"; DbNum!(r$, "age")

' Change single fields of a stored record
ok% = DbSetNum%("ann", "age", 35)
ok% = DbSetRaw%("bob", "vip", "true")

' Every record, in _id order
FOR i% = 0 TO DbCount%() - 1
  r$ = DbAt$(i%)
  PRINT DbStr$(r$, "_id"), DbStr$(r$, "name"), DbStr$(r$, "city")
NEXT

' A query (uses the index on city)
IF DbQuery%("SELECT * FROM contacts WHERE city = 'Leeds' ORDER BY name") THEN
  PRINT DbRows%(); " in Leeds:"
  FOR i% = 0 TO DbRows%() - 1
    PRINT "  "; DbStr$(DbRow$(i%), "name")
  NEXT
ELSE
  PRINT "query: "; DbErr$()
ENDIF

IF DbQuery%("SELECT COUNT(*) FROM contacts WHERE age IS NULL") THEN
  PRINT DbResult%(); " without an age"
ENDIF

DbClose                                       ' saves index + metadata
