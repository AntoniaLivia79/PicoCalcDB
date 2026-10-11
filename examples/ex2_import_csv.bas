' ex2_import_csv.bas - load a CSV file into a collection.
' First line = field names. A column called _id gives the record ids,
' otherwise automatic ids are used. Numbers become numbers.
' (Simple CSV: no commas or quotes inside values.)
OPTION EXPLICIT
OPTION DEFAULT NONE
#INCLUDE "dblib.bas"

CONST CSV$ = "B:/db/plants.csv"
CONST COL$ = "plants"
DIM hdr$, ln$, r$, f$, v$, id$, nf%, i%, n% = 0, bad% = 0, ok%

DbInit "B:/db"

' Make a small sample file the first time, so the example runs as is
IF DIR$(CSV$, FILE) = "" THEN
  OPEN CSV$ FOR OUTPUT AS #5
  PRINT #5, "_id,name,water_days,height_cm,indoor"
  PRINT #5, "fern,Boston fern,3,40,true"
  PRINT #5, "cact,Barrel cactus,21,15,true"
  PRINT #5, "rose,Climbing rose,2,250,false"
  PRINT #5, "mint,Mint,2,30,false"
  CLOSE #5
ENDIF

IF DbOpen%(COL$) = 0 THEN
  IF DbCreate%(COL$) = 0 THEN PRINT DbErr$() : END
  ok% = DbOpen%(COL$)
ENDIF

OPEN CSV$ FOR INPUT AS #5
LINE INPUT #5, hdr$
nf% = 1
DO WHILE FIELD$(hdr$, nf% + 1, ",") <> "" : INC nf% : LOOP

DO WHILE NOT EOF(#5)
  LINE INPUT #5, ln$
  IF ln$ <> "" THEN
    id$ = ""
    FOR i% = 1 TO nf%
      IF FIELD$(hdr$, i%, ",") = "_id" THEN id$ = FIELD$(ln$, i%, ",")
    NEXT
    IF id$ = "" THEN id$ = DbNewId$()
    r$ = DbNew$(id$)
    FOR i% = 1 TO nf%
      f$ = FIELD$(hdr$, i%, ",") : v$ = FIELD$(ln$, i%, ",")
      IF f$ <> "_id" AND f$ <> "" AND v$ <> "" AND r$ <> "" THEN r$ = DbWithAuto$(r$, f$, v$)
    NEXT
    ok% = 0
    IF r$ <> "" THEN ok% = DbPut%(r$)
    IF ok% THEN
      INC n%
    ELSE
      INC bad% : PRINT id$; ": "; DbErr$()
    ENDIF
  ENDIF
LOOP
CLOSE #5
PRINT n%; " imported,"; bad%; " failed; collection has"; DbCount%()
ok% = DbMetaSet%("source", CSV$)
DbClose
