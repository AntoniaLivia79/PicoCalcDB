' =====================================================================
' almanac.bas - Almanac browser for the PicoCalc, built on the DB
' library (dblib.bas) and the display layer (dbhal.bas).
' almanac_app.bas = dblib + dbhal + this file, ready to RUN.
' ---------------------------------------------------------------------
' Data: B:/almanac.csv, columns (by name, any order):
'   date (YYYY-MM-DD), event, detail     required
'   category, saying_or_lore, place, certainty, weekday   optional
' Stored in collection "almanac" in B:/db/, one record per CSV row:
'   {"_id":"2026-10-01.01","cat":"..","event":"..","detail":"..",
'    "lore":"..","place":"..","cert":".."}
' _id = date + "." + 2-digit sequence, so records sort by date and a
' day's events are one fast _id range. A saying too long to fit in its
' record goes in a companion record "<_id>L" {"_id":"..L","lore":".."}.
' Weekdays are computed from the date.
' =====================================================================

CONST AM_CSV$ = "B:/almanac.csv"
CONST AM_DIR$ = "B:/db"
CONST AM_COL$ = "almanac"
CONST AM_FN = 5                        ' file number for the CSV (library uses 1-3)
CONST AM_MAXL = 120                    ' lines in the day view
CONST AM_MAXHIT = 300                  ' search results kept

CONST AK_UP = 128, AK_DN = 129, AK_LT = 130, AK_RT = 131, AK_HOME = 134
CONST AK_END = 135, AK_PU = 136, AK_PD = 137, AK_ESC = 27, AK_ENT = 13
CONST AK_BS = 8, AK_DEL = 212, AK_DEL2 = 127
CONST AS_N = 0, AS_TITLE = 1, AS_SEL = 2, AS_MSG = 3, AS_ERR = 4, AS_HINT = 5
CONST AS_DIM = 6, AS_HEAD = 7

DIM AmL$(AM_MAXL - 1) LENGTH 53, AmLs%(AM_MAXL - 1), AmLN%
DIM AmHit$(AM_MAXHIT - 1) LENGTH 16, AmHitN%
DIM AmF$(15), AmFN%, AmMsg$, AmOk%, AmLong%
DIM AmFirst%, AmLast%                  ' day numbers of the first/last entry
DIM AmDrawn%(60)                       ' rows drawn in the current frame
DIM AmPend$, AmPendSt%                 ' message kept until the next key
DIM AmMon$ = "JanFebMarAprMayJunJulAugSepOctNovDec"
DIM AmWk$ = "SunMonTueWedThuFriSat"

' ---------------- dates ----------------------------------------------
' Day numbers count days from 1970-01-01 (a Thursday).

FUNCTION AmDim%(y%, m%)
  AmDim% = VAL(MID$("312831303130313130313031", m% * 2 - 1, 2))
  IF m% = 2 AND ((y% MOD 4 = 0 AND y% MOD 100 <> 0) OR y% MOD 400 = 0) THEN AmDim% = 29
END FUNCTION

' Day number of "YYYY-MM-DD", or -1 if it is not a valid date
FUNCTION AmDays%(d$)
  LOCAL y%, m%, dd%, i%, era%, yoe%, doy%, mp%
  AmDays% = -1
  IF LEN(d$) <> 10 OR MID$(d$, 5, 1) <> "-" OR MID$(d$, 8, 1) <> "-" THEN EXIT FUNCTION
  FOR i% = 1 TO 10
    IF i% <> 5 AND i% <> 8 AND INSTR("0123456789", MID$(d$, i%, 1)) = 0 THEN EXIT FUNCTION
  NEXT
  y% = VAL(LEFT$(d$, 4)) : m% = VAL(MID$(d$, 6, 2)) : dd% = VAL(RIGHT$(d$, 2))
  IF y% < 1971 OR m% < 1 OR m% > 12 OR dd% < 1 THEN EXIT FUNCTION
  IF dd% > AmDim%(y%, m%) THEN EXIT FUNCTION
  IF m% <= 2 THEN y% = y% - 1
  era% = y% \ 400 : yoe% = y% - era% * 400
  IF m% > 2 THEN mp% = m% - 3 ELSE mp% = m% + 9
  doy% = (153 * mp% + 2) \ 5 + dd% - 1
  AmDays% = era% * 146097 + yoe% * 365 + yoe% \ 4 - yoe% \ 100 + doy% - 719468
END FUNCTION

' "YYYY-MM-DD" for a day number
FUNCTION AmDate$(n%)
  LOCAL z% = n% + 719468, era%, doe%, yoe%, y%, doy%, mp%, d%, m%
  era% = z% \ 146097 : doe% = z% - era% * 146097
  yoe% = (doe% - doe% \ 1460 + doe% \ 36524 - doe% \ 146096) \ 365
  y% = yoe% + era% * 400
  doy% = doe% - (365 * yoe% + yoe% \ 4 - yoe% \ 100)
  mp% = (5 * doy% + 2) \ 153
  d% = doy% - (153 * mp% + 2) \ 5 + 1
  IF mp% < 10 THEN m% = mp% + 3 ELSE m% = mp% - 9
  IF m% <= 2 THEN y% = y% + 1
  AmDate$ = STR$(y%) + "-" + STR$(m%, 2, 0, "0") + "-" + STR$(d%, 2, 0, "0")
END FUNCTION

FUNCTION AmWeekday$(n%)
  AmWeekday$ = MID$(AmWk$, ((n% + 4) MOD 7) * 3 + 1, 3)
END FUNCTION

' "Thu 1 Oct 2026"
FUNCTION AmLongDate$(n%)
  LOCAL d$ = AmDate$(n%)
  AmLongDate$ = AmWeekday$(n%) + " " + STR$(VAL(RIGHT$(d$, 2))) + " " + MID$(AmMon$, VAL(MID$(d$, 6, 2)) * 3 - 2, 3) + " " + LEFT$(d$, 4)
END FUNCTION

' "01 Oct 26"
FUNCTION AmShortDate$(d$)
  AmShortDate$ = RIGHT$(d$, 2) + " " + MID$(AmMon$, VAL(MID$(d$, 6, 2)) * 3 - 2, 3) + " " + MID$(d$, 3, 2)
END FUNCTION

' Today from the clock (DATE$ is DD-MM-YYYY), or -1
FUNCTION AmToday%()
  LOCAL d$ = DATE$
  AmToday% = AmDays%(RIGHT$(d$, 4) + "-" + MID$(d$, 4, 2) + "-" + LEFT$(d$, 2))
END FUNCTION

' ---------------- screen helpers -------------------------------------

SUB AmLine r%, s$, st%
  HalText 0, r%, LEFT$(LEFT$(s$, HalW%) + SPACE$(HalW%), HalW%), st%
  AmDrawn%(r%) = 1
END SUB

' Start a screen: draw the title; rows not drawn by AmDone are blanked
SUB AmTitle t$
  LOCAL r%
  FOR r% = 0 TO HalH% - 1 : AmDrawn%(r%) = 0 : NEXT
  AmLine 0, t$, AS_TITLE
END SUB

' Show m$ on the message line until the next key press
SUB AmNote m$, st%
  AmPend$ = m$ : AmPendSt% = st%
END SUB

' Finish a screen: show any pending note, blank every row not drawn
SUB AmDone
  LOCAL r%
  IF AmPend$ <> "" THEN AmSay AmPend$, AmPendSt% : AmPend$ = ""
  FOR r% = 1 TO HalH% - 1
    IF AmDrawn%(r%) = 0 THEN AmLine r%, "", AS_N
  NEXT
END SUB

SUB AmHints h$
  AmLine HalH% - 1, h$, AS_HINT
END SUB

SUB AmSay m$, st%
  AmLine HalH% - 2, m$, st%
END SUB

' y/n question on the message line
FUNCTION AmAsk%(q$)
  LOCAL k%
  AmSay q$ + " (y/n)", AS_ERR
  k% = HalKey%()
  AmAsk% = (k% = 89 OR k% = 121)
  AmSay "", AS_N
END FUNCTION

' Line editor on the message line. AmOk% = 1 on Enter, 0 on Esc.
FUNCTION AmInput$(p$, init$, mx%)
  LOCAL s$ = init$, k%, w%
  w% = HalW% - LEN(p$) - 1
  DO
    AmSay p$ + RIGHT$(s$, w% - 1) + "_", AS_MSG
    k% = HalKey%()
    SELECT CASE k%
      CASE AK_ENT : AmOk% = 1 : EXIT DO
      CASE AK_ESC : AmOk% = 0 : EXIT DO
      CASE AK_BS, AK_DEL, AK_DEL2
        IF LEN(s$) > 0 THEN s$ = LEFT$(s$, LEN(s$) - 1)
      CASE 32 TO 126
        IF LEN(s$) < mx% THEN s$ = s$ + CHR$(k%)
    END SELECT
  LOOP
  AmSay "", AS_N
  AmInput$ = s$
END FUNCTION

' Add s$ to the day view, word-wrapped, each line indented by ind%
SUB AmAdd s$, ind%, st%
  LOCAL t$ = s$, w% = HalW% - ind%, b%
  DO WHILE t$ <> "" AND AmLN% < AM_MAXL
    IF LEN(t$) <= w% THEN
      b% = LEN(t$) + 1
    ELSE
      b% = w% + 1
      DO WHILE b% > 1 AND MID$(t$, b%, 1) <> " " : INC b%, -1 : LOOP
      IF b% <= 1 THEN b% = w% + 1
    ENDIF
    AmL$(AmLN%) = SPACE$(ind%) + LEFT$(t$, b% - 1) : AmLs%(AmLN%) = st% : INC AmLN%
    t$ = MID$(t$, b%)
    IF LEFT$(t$, 1) = " " THEN t$ = MID$(t$, 2)
  LOOP
END SUB

' ---------------- CSV import -----------------------------------------

' Split one CSV line into AmF$(0..AmFN%-1). Handles "quoted, fields"
' and "" inside quotes. Returns 0 if a quote is not closed.
FUNCTION AmCsv%(ln$)
  LOCAL i% = 1, j%, n% = LEN(ln$), v$
  AmFN% = 0
  DO
    IF AmFN% > 15 THEN EXIT FUNCTION
    IF MID$(ln$, i%, 1) = CHR$(34) THEN
      v$ = "" : INC i%
      DO
        j% = INSTR(i%, ln$, CHR$(34))
        IF j% = 0 THEN EXIT FUNCTION
        v$ = v$ + MID$(ln$, i%, j% - i%)
        IF MID$(ln$, j% + 1, 1) = CHR$(34) THEN
          v$ = v$ + CHR$(34) : i% = j% + 2
        ELSE
          i% = j% + 1 : EXIT DO
        ENDIF
      LOOP
      AmF$(AmFN%) = v$ : INC AmFN%
      IF i% > n% THEN EXIT DO
      IF MID$(ln$, i%, 1) <> "," THEN EXIT FUNCTION
      INC i%
    ELSE
      j% = INSTR(i%, ln$, ",")
      IF j% = 0 THEN
        AmF$(AmFN%) = MID$(ln$, i%) : INC AmFN% : EXIT DO
      ENDIF
      AmF$(AmFN%) = MID$(ln$, i%, j% - i%) : INC AmFN% : i% = j% + 1
    ENDIF
    IF i% > n% THEN AmF$(AmFN%) = "" : INC AmFN% : EXIT DO
  LOOP
  AmCsv% = 1
END FUNCTION

' Read one line of the CSV; lines over 255 characters are trapped
' (AmLong% = 1) instead of stopping the program.
FUNCTION AmReadLine$()
  LOCAL r$ = CHR$(1)
  ON ERROR SKIP 1
  LINE INPUT #AM_FN, r$
  AmLong% = (r$ = CHR$(1))
  IF AmLong% THEN r$ = ""
  AmReadLine$ = r$
END FUNCTION

' 1 if the almanac collection exists
FUNCTION AmHaveCol%()
  LOCAL i%
  FOR i% = 0 TO DbList%() - 1
    IF DbListName$(i%) = AM_COL$ THEN AmHaveCol% = 1
  NEXT
END FUNCTION

FUNCTION AmFileExists%(p$)
  LOCAL x$ = "?"
  ON ERROR SKIP 1
  x$ = DIR$(p$, FILE)
  AmFileExists% = (x$ <> "" AND x$ <> "?")
END FUNCTION

' Progress during import (also updates the screen)
SUB AmProgress n%, done%, nskip%
  AmSay "Read " + STR$(n%) + " rows: " + STR$(done%) + " stored, " + STR$(nskip%) + " skipped", AS_MSG
END SUB

' Drop (if present) and recreate the collection from csv$.
' Returns 1 if the import ran; AmMsg$ holds the summary.
FUNCTION AmImport%(csv$)
  LOCAL ln$, d$, id$, r$, r2$, lore$, h$, i%, n% = 0, done% = 0, nskip% = 0, split% = 0
  LOCAL cD% = -1, cE% = -1, cT% = -1, cC% = -1, cL% = -1, cP% = -1, cK% = -1
  LOCAL seq%, frag% = 0, first$, last$, why$
  AmMsg$ = ""
  IF AmFileExists%(csv$) = 0 THEN AmMsg$ = csv$ + " not found" : EXIT FUNCTION
  OPEN csv$ FOR INPUT AS #AM_FN
  ln$ = AmReadLine$()
  IF LEFT$(ln$, 3) = CHR$(239) + CHR$(187) + CHR$(191) THEN ln$ = MID$(ln$, 4)
  IF AmCsv%(ln$) = 0 THEN CLOSE #AM_FN : AmMsg$ = "bad header line" : EXIT FUNCTION
  FOR i% = 0 TO AmFN% - 1
    h$ = LCASE$(AmF$(i%))
    SELECT CASE h$
      CASE "date" : cD% = i%
      CASE "event" : cE% = i%
      CASE "detail" : cT% = i%
      CASE "category" : cC% = i%
      CASE "saying_or_lore", "lore" : cL% = i%
      CASE "place" : cP% = i%
      CASE "certainty" : cK% = i%
    END SELECT
  NEXT
  IF cD% < 0 OR cE% < 0 OR cT% < 0 THEN
    CLOSE #AM_FN : AmMsg$ = "CSV needs date, event and detail columns" : EXIT FUNCTION
  ENDIF
  IF AmHaveCol%() THEN
    DbClose
    IF DbDrop%(AM_COL$) = 0 THEN CLOSE #AM_FN : AmMsg$ = "drop: " + DbErr$() : EXIT FUNCTION
  ENDIF
  IF DbCreate%(AM_COL$) = 0 THEN CLOSE #AM_FN : AmMsg$ = "create: " + DbErr$() : EXIT FUNCTION
  IF DbOpen%(AM_COL$) = 0 THEN CLOSE #AM_FN : AmMsg$ = "open: " + DbErr$() : EXIT FUNCTION
  DO WHILE NOT EOF(#AM_FN)
    ln$ = AmReadLine$()
    IF AmLong% THEN
      INC n% : INC nskip% : frag% = 1 : why$ = "line too long" : CONTINUE DO
    ENDIF
    IF frag% THEN frag% = 0 : CONTINUE DO
    IF ln$ = "" THEN CONTINUE DO
    INC n%
    IF n% MOD 25 = 0 THEN AmProgress n%, done%, nskip%
    IF AmCsv%(ln$) = 0 THEN INC nskip% : why$ = "unclosed quote" : CONTINUE DO
    IF AmFN% <= MAX(cD%, cE%, cT%) THEN INC nskip% : why$ = "missing columns" : CONTINUE DO
    d$ = AmF$(cD%)
    IF AmDays%(d$) < 0 THEN INC nskip% : why$ = "bad date " + LEFT$(d$, 12) : CONTINUE DO
    seq% = 1
    DO WHILE DbExists%(d$ + "." + STR$(seq%, 2, 0, "0")) AND seq% < 99 : INC seq% : LOOP
    id$ = d$ + "." + STR$(seq%, 2, 0, "0")
    r$ = DbNew$(id$)
    IF cC% >= 0 AND cC% < AmFN% THEN
      IF AmF$(cC%) <> "" THEN r$ = DbWithText$(r$, "cat", AmF$(cC%))
    ENDIF
    r$ = DbWithText$(r$, "event", AmF$(cE%))
    IF r$ <> "" THEN r$ = DbWithText$(r$, "detail", AmF$(cT%))
    IF cP% >= 0 AND cP% < AmFN% AND r$ <> "" THEN
      IF AmF$(cP%) <> "" THEN r$ = DbWithText$(r$, "place", AmF$(cP%))
    ENDIF
    IF cK% >= 0 AND cK% < AmFN% AND r$ <> "" THEN
      IF AmF$(cK%) <> "" THEN r$ = DbWithText$(r$, "cert", AmF$(cK%))
    ENDIF
    IF r$ = "" THEN INC nskip% : why$ = "row too long" : CONTINUE DO
    lore$ = ""
    IF cL% >= 0 AND cL% < AmFN% THEN lore$ = AmF$(cL%)
    r2$ = ""
    IF lore$ <> "" THEN
      r2$ = DbWithText$(r$, "lore", lore$)
      IF r2$ <> "" THEN
        r$ = r2$ : r2$ = ""
      ELSE
        r2$ = DbWithText$(DbNew$(id$ + "L"), "lore", lore$)
      ENDIF
    ENDIF
    IF DbInsert%(r$) = 0 THEN
      why$ = DbErr$() : INC nskip%
      IF why$ = "collection full" THEN EXIT DO
      CONTINUE DO
    ENDIF
    IF r2$ <> "" THEN
      IF DbInsert%(r2$) THEN INC split% ELSE why$ = "saying: " + DbErr$()
    ENDIF
    INC done%
    IF first$ = "" OR d$ < first$ THEN first$ = d$
    IF d$ > last$ THEN last$ = d$
  LOOP
  CLOSE #AM_FN
  i% = DbMetaSet%("source", csv$) + DbMetaSet%("rows", STR$(done%))
  i% = DbMetaSet%("first", first$) + DbMetaSet%("last", last$)
  i% = DbMetaSet%("loaded", DATE$ + " " + LEFT$(TIME$, 5))
  DbFlush
  AmMsg$ = STR$(done%) + " stored, " + STR$(nskip%) + " skipped"
  IF nskip% > 0 THEN AmMsg$ = AmMsg$ + " (last: " + why$ + ")"
  AmImport% = 1
END FUNCTION

' Open the collection and find its date range. Returns 0 if missing.
FUNCTION AmOpen%()
  LOCAL n%
  AmOpen% = 0
  IF AmHaveCol%() = 0 THEN EXIT FUNCTION
  IF DbOpen%(AM_COL$) = 0 THEN EXIT FUNCTION
  n% = DbCount%()
  IF n% = 0 THEN EXIT FUNCTION
  AmFirst% = AmDays%(LEFT$(AmIdAt$(0), 10))
  AmLast% = AmDays%(LEFT$(AmIdAt$(n% - 1), 10))
  IF AmFirst% < 0 OR AmLast% < 0 THEN EXIT FUNCTION
  AmOpen% = 1
END FUNCTION

' _id at a position (DbAt$ is in _id order)
FUNCTION AmIdAt$(i%)
  AmIdAt$ = DbStr$(DbAt$(i%), "_id")
END FUNCTION

' ---------------- 1. maintain ----------------------------------------

SUB AmMaintain
  LOCAL k%, r%
  DO
    AmTitle "Maintain database"
    r% = 2
    IF AmFileExists%(AM_CSV$) THEN
      AmLine r%, "CSV file: " + AM_CSV$, AS_N
    ELSE
      AmLine r%, "CSV file: " + AM_CSV$ + " - MISSING", AS_ERR
    ENDIF
    INC r%, 2
    IF AmOpen%() THEN
      AmLine r%, "Collection '" + AM_COL$ + "': " + STR$(DbCount%()) + " records", AS_N : INC r%
      AmLine r%, "  " + AmLongDate$(AmFirst%) + " to", AS_N : INC r%
      AmLine r%, "  " + AmLongDate$(AmLast%), AS_N : INC r%
      AmLine r%, "  loaded " + DbMetaGet$("loaded"), AS_DIM : INC r%
      AmLine r%, "  from " + DbMetaGet$("source"), AS_DIM : INC r%
    ELSE
      AmLine r%, "Collection '" + AM_COL$ + "': not created yet", AS_ERR : INC r%
    ENDIF
    INC r%
    IF AmHaveCol%() THEN
      AmLine r%, "R  Drop and recreate from the CSV", AS_HEAD
    ELSE
      AmLine r%, "C  Create from the CSV", AS_HEAD
    ENDIF
    AmLine r% + 1, "Esc  Back", AS_HEAD
    IF AmMsg$ <> "" THEN AmSay AmMsg$, AS_MSG
    AmHints "C/R load  Esc back"
    AmDone
    k% = HalKey%()
    SELECT CASE k%
      CASE 67, 99, 82, 114
        ' (MMBasic evaluates both sides of OR, so ask only when needed)
        k% = 1
        IF AmHaveCol%() THEN k% = AmAsk%("Drop and reload all data?")
        IF k% THEN
          AmSay "Loading " + AM_CSV$ + " ...", AS_MSG
          IF AmImport%(AM_CSV$) = 0 THEN AmMsg$ = "Failed: " + AmMsg$
        ENDIF
      CASE AK_ESC
        AmMsg$ = "" : EXIT SUB
    END SELECT
  LOOP
END SUB

' ---------------- 2. browse by day -----------------------------------

' Build the day view for day number dn% into AmL$()
SUB AmBuildDay dn%
  LOCAL i%, r$, id$, v$, d$ = AmDate$(dn%)
  AmLN% = 0
  IF DbQuery%("SELECT * FROM " + AM_COL$ + " WHERE _id LIKE '" + d$ + ".%'") = 0 THEN
    AmAdd "Error: " + DbErr$(), 0, AS_ERR : EXIT SUB
  ENDIF
  FOR i% = 0 TO DbRows%() - 1
    r$ = DbRow$(i%) : id$ = DbStr$(r$, "_id")
    IF RIGHT$(id$, 1) = "L" THEN
      v$ = DbStr$(r$, "lore")
      IF v$ <> "" THEN AmAdd CHR$(34) + v$ + CHR$(34), 2, AS_DIM
    ELSE
      IF AmLN% > 0 THEN AmL$(AmLN%) = "" : AmLs%(AmLN%) = AS_N : INC AmLN%
      v$ = DbStr$(r$, "cat")
      IF v$ = "" THEN v$ = "Event"
      AmAdd v$, 0, AS_HEAD
      AmAdd DbStr$(r$, "event"), 2, AS_N
      v$ = DbStr$(r$, "detail")
      IF v$ <> "" THEN AmAdd v$, 2, AS_N
      v$ = DbStr$(r$, "lore")
      IF v$ <> "" THEN AmAdd CHR$(34) + v$ + CHR$(34), 2, AS_DIM
      v$ = DbStr$(r$, "place")
      IF DbStr$(r$, "cert") <> "" THEN v$ = v$ + " (" + DbStr$(r$, "cert") + ")"
      IF v$ <> "" THEN AmAdd v$, 2, AS_DIM
    ENDIF
  NEXT
  IF AmLN% = 0 THEN AmAdd "Nothing recorded for this day.", 0, AS_DIM
END SUB

' Browse from day number dn%. Returns when the user presses Esc.
SUB AmBrowse dn%
  LOCAL k%, top% = 0, h% = HalH% - 3, d% = dn%, i%, s$, nd%
  IF d% < AmFirst% THEN d% = AmFirst%
  IF d% > AmLast% THEN d% = AmLast%
  AmBuildDay d%
  DO
    AmTitle AmLongDate$(d%)
    FOR i% = 0 TO h% - 1
      IF top% + i% < AmLN% THEN AmLine i% + 1, AmL$(top% + i%), AmLs%(top% + i%)
    NEXT
    IF AmLN% > h% THEN AmSay "Lines " + STR$(top% + 1) + "-" + STR$(MIN(top% + h%, AmLN%)) + " of " + STR$(AmLN%) + "  (Up/Dn)", AS_DIM
    AmHints "Lt/Rt day  +/- 30 days  G date  Esc"
    AmDone
    k% = HalKey%()
    nd% = d%
    SELECT CASE k%
      CASE AK_LT : nd% = d% - 1
      CASE AK_RT : nd% = d% + 1
      CASE AK_PU, 45 : nd% = d% - 30
      CASE AK_PD, 43, 61 : nd% = d% + 30
      CASE AK_HOME : nd% = AmFirst%
      CASE AK_END : nd% = AmLast%
      CASE AK_UP : top% = MAX(0, top% - 1)
      CASE AK_DN : top% = MAX(0, MIN(top% + 1, AmLN% - h%))
      CASE 84, 116
        nd% = AmToday%()
        IF nd% < AmFirst% OR nd% > AmLast% THEN nd% = d% : AmNote "Today is outside the almanac", AS_ERR
      CASE 71, 103
        s$ = AmInput$("Date (YYYY-MM-DD): ", AmDate$(d%), 10)
        IF AmOk% THEN
          nd% = AmDays%(s$)
          IF nd% < 0 THEN
            nd% = d% : AmNote "Not a valid date: " + s$, AS_ERR
          ELSEIF nd% < AmFirst% OR nd% > AmLast% THEN
            nd% = d% : AmNote "Outside " + AmDate$(AmFirst%) + " to " + AmDate$(AmLast%), AS_ERR
          ENDIF
        ENDIF
      CASE AK_ESC : EXIT SUB
    END SELECT
    nd% = MAX(AmFirst%, MIN(AmLast%, nd%))
    IF nd% <> d% THEN d% = nd% : top% = 0 : AmBuildDay d%
  LOOP
END SUB

' ---------------- 3. keyword search ----------------------------------

' Find records whose detail contains every word of q$ (any case).
' Matching _ids go into AmHit$(); returns the number found.
FUNCTION AmFind%(q$)
  LOCAL w$(7), x$, nw%, i%, j%, ok%, r$, det$, n% = DbCount%()
  AmHitN% = 0
  FOR i% = 1 TO 16
    x$ = FIELD$(LCASE$(q$), i%, " ")
    IF x$ <> "" AND nw% < 8 THEN w$(nw%) = x$ : INC nw%
  NEXT
  IF nw% = 0 THEN EXIT FUNCTION
  FOR i% = 0 TO n% - 1
    IF i% MOD 50 = 0 THEN AmSay "Searching " + STR$(i%) + " of " + STR$(n%), AS_MSG
    r$ = DbAt$(i%)
    det$ = LCASE$(DbStr$(r$, "detail"))
    IF det$ <> "" THEN
      ok% = 1
      FOR j% = 0 TO nw% - 1
        IF INSTR(det$, w$(j%)) = 0 THEN ok% = 0 : EXIT FOR
      NEXT
      IF ok% AND AmHitN% < AM_MAXHIT THEN AmHit$(AmHitN%) = DbStr$(r$, "_id") : INC AmHitN%
    ENDIF
  NEXT
  AmSay "", AS_N
  AmFind% = AmHitN%
END FUNCTION

SUB AmSearch
  LOCAL q$, k%, sel% = 0, top% = 0, h% = HalH% - 3, i%, r$, s$
  AmTitle "Search almanac (detail)"
  AmHints "Enter search  Esc back"
  AmDone
  q$ = AmInput$("Find: ", "", 40)
  IF AmOk% = 0 OR q$ = "" THEN EXIT SUB
  IF AmFind%(q$) = 0 THEN
    AmNote "No details contain: " + q$, AS_ERR : EXIT SUB
  ENDIF
  DO
    AmTitle "'" + q$ + "': " + STR$(AmHitN%) + " found"
    IF sel% < top% THEN top% = sel%
    IF sel% >= top% + h% THEN top% = sel% - h% + 1
    FOR i% = 0 TO h% - 1
      IF top% + i% < AmHitN% THEN
        r$ = DbGet$(AmHit$(top% + i%))
        s$ = AmShortDate$(LEFT$(AmHit$(top% + i%), 10)) + " " + DbStr$(r$, "detail")
        IF top% + i% = sel% THEN AmLine i% + 1, s$, AS_SEL ELSE AmLine i% + 1, s$, AS_N
      ENDIF
    NEXT
    IF AmHitN% = AM_MAXHIT THEN AmSay "Showing the first " + STR$(AM_MAXHIT), AS_DIM
    AmHints "Up/Dn select  Enter open day  Esc back"
    AmDone
    k% = HalKey%()
    SELECT CASE k%
      CASE AK_UP : sel% = MAX(0, sel% - 1)
      CASE AK_DN : sel% = MIN(AmHitN% - 1, sel% + 1)
      CASE AK_PU, AK_LT : sel% = MAX(0, sel% - h%)
      CASE AK_PD, AK_RT : sel% = MIN(AmHitN% - 1, sel% + h%)
      CASE AK_HOME : sel% = 0
      CASE AK_END : sel% = AmHitN% - 1
      CASE AK_ENT : AmBrowse AmDays%(LEFT$(AmHit$(sel%), 10))
      CASE AK_ESC : EXIT SUB
    END SELECT
  LOOP
END SUB

' ---------------- main menu ------------------------------------------

SUB AmMenu
  LOCAL k%, ok%, d%
  DO
    ok% = AmOpen%()
    AmTitle "Almanac"
    AmLine 3, "1  Maintain database", AS_HEAD
    AmLine 5, "2  Browse almanac by day", AS_HEAD
    AmLine 7, "3  Search almanac (detail)", AS_HEAD
    AmLine 9, "Esc  Quit", AS_HEAD
    IF ok% THEN
      AmLine 12, AmLongDate$(AmFirst%) + " to", AS_DIM
      AmLine 13, AmLongDate$(AmLast%) + ", " + STR$(DbCount%()) + " records", AS_DIM
    ELSE
      AmLine 12, "No almanac data yet: choose 1", AS_ERR
    ENDIF
    AmHints "1 2 3 choose  Esc quit"
    AmDone
    k% = HalKey%()
    SELECT CASE k%
      CASE 49 : AmMaintain
      CASE 50, 51
        IF ok% = 0 THEN
          AmNote "Load the data first (1 Maintain)", AS_ERR
        ELSEIF k% = 50 THEN
          d% = AmToday%()
          IF d% < AmFirst% OR d% > AmLast% THEN d% = AmFirst%
          AmBrowse d%
        ELSE
          AmSearch
        ENDIF
      CASE AK_ESC : EXIT SUB
    END SELECT
  LOOP
END SUB

SUB AmMain
  HalInit
  HalCls
  DbInit AM_DIR$
  AmMenu
  DbClose
  HalCls
END SUB

' ---- main ----
AmMain
