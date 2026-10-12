' =====================================================================
' dbmain.bas - program entry. Load order: dbcore, dbstore, dbquery,
' dbexec, dbhal, dbgui, then this file (dbapp.bas is all of them
' merged; dbapp_min.bas is the same without comments, to save space).
' The main loop is here at the top level rather than in a SUB, so the
' explorer's calls start one level less deep (small PicoMite stack).
' =====================================================================
StDir$ = "B:/db/"                 ' database folder on the SD card
ON ERROR SKIP 1
MKDIR "B:/db"
HalInit
HalCls
UiListColl ""
UiGo UV_COLL
UiPaint
DO WHILE UiQuit% = 0
  UiStep
LOOP
StClose
HalCls
END
