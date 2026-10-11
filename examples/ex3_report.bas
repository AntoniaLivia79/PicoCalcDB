' ex3_report.bas - describe a collection, summarise a numeric field
' and export everything as CSV. Run ex2_import_csv.bas first.
OPTION EXPLICIT
OPTION DEFAULT NONE
#INCLUDE "dblib.bas"

CONST COL$ = "plants", NUMF$ = "water_days", OUT$ = "B:/db/plants_out.csv"
DIM r$, hdr$, ln$, i%, j%, n% = 0, ok%
DIM tot!, lo! = 1E30, hi! = -1E30

DbInit "B:/db"
IF DbOpen%(COL$) = 0 THEN PRINT DbErr$() : END

' Metadata: fields and their kinds, indexes, your own properties
PRINT COL$; ":"; DbCount%(); " records,"; DbDead%(); " dead lines"
PRINT "indexes: _id "; DbIndexes$()
FOR i% = 0 TO DbFields%() - 1
  PRINT "  "; DbFieldInfo$(i%); " ("; DbFieldType$(i%); ")"
NEXT
i% = 0
DO WHILE DbMetaName$(i%) <> ""
  PRINT "  property "; DbMetaName$(i%); " = "; DbMetaGet$(DbMetaName$(i%))
  INC i%
LOOP

' Summary of one numeric field
FOR i% = 0 TO DbCount%() - 1
  r$ = DbAt$(i%)
  IF DbKind$(r$, NUMF$) = "N" THEN
    INC n% : tot! = tot! + DbNum!(r$, NUMF$)
    lo! = MIN(lo!, DbNum!(r$, NUMF$)) : hi! = MAX(hi!, DbNum!(r$, NUMF$))
  ENDIF
NEXT
IF n% > 0 THEN PRINT NUMF$; ": n="; n%; " avg="; tot! / n%; " min="; lo!; " max="; hi!

' Export: one column per known field, _id first
hdr$ = "_id"
FOR j% = 0 TO DbFields%() - 1 : hdr$ = hdr$ + "," + DbFieldInfo$(j%) : NEXT
OPEN OUT$ FOR OUTPUT AS #5
PRINT #5, hdr$
FOR i% = 0 TO DbCount%() - 1
  r$ = DbAt$(i%)
  ln$ = DbStr$(r$, "_id")
  FOR j% = 0 TO DbFields%() - 1
    IF LEN(ln$) < 200 THEN ln$ = ln$ + "," + DbStr$(r$, DbFieldInfo$(j%))
  NEXT
  PRINT #5, ln$
NEXT
CLOSE #5
PRINT "exported to "; OUT$
DbClose
