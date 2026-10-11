' =====================================================================
' dbmain.bas - program entry. Load order: dbcore, dbstore, dbquery,
' dbexec, dbhal, dbgui, then this file (dbapp.bas is all of them
' merged; dbapp_min.bas is the same without comments, to save space).
' =====================================================================
StDir$ = "B:/db/"                 ' database folder on the SD card
ON ERROR SKIP 1
MKDIR "B:/db"
UiMain
END
