' =====================================================================
' dbgui.bas - Explorer GUI (needs dbcore, dbstore, dbquery, dbexec and
' a HAL: dbhal.bas on the PicoCalc). Character-cell layout:
'   row 0        title bar
'   rows 1..H-3  list (collections, records, fields or text)
'   row H-2      messages and the input line
'   row H-1      key hints
' Views: Collections -> Records -> Record detail; Text; Help topics
' Keys everywhere: arrows, PgUp/PgDn (or Left/Right in lists),
'   Home/End, F1 help search, F2 or / SQL console, Esc back.
' Help topics come from StDir$ + "help/dbhelp.jsonl" (JSON Lines:
'   {"_id":"0300.1","title":"..","kw":"..","text":".."}; records whose
'   _id share the part before "." form one topic, in file order).
' Collections: Enter open, N new, Del drop
' Records:     Enter detail, F filter (WHERE ...), N new, Del delete,
'              D describe, Esc clear filter / back
' Detail:      Enter edit, A add field, Del remove field,
'              Left/Right previous/next record, Esc back
' Editing a value: text fields stay text; other values are stored as
'   numbers/true/false/null when they look like one ('...' = text).
' =====================================================================

CONST UK_UP = 128, UK_DN = 129, UK_LT = 130, UK_RT = 131, UK_HOME = 134
CONST UK_END = 135, UK_PU = 136, UK_PD = 137, UK_F1 = 145, UK_F2 = 146
CONST UK_ESC = 27, UK_ENT = 13, UK_BS = 8, UK_DEL = 212, UK_DEL2 = 127
CONST US_N = 0, US_TITLE = 1, US_SEL = 2, US_MSG = 3, US_ERR = 4, US_HINT = 5
CONST UV_COLL = 1, UV_RECS = 2, UV_DET = 3, UV_TEXT = 4, UV_HELP = 5
CONST HP_MAX = 64, HP_FN = 4

DIM UiV% = UV_COLL, UiSel%(5), UiTop%(5), UiBackV% = UV_COLL
DIM HpId$(HP_MAX - 1) LENGTH 8, HpTitle$(HP_MAX - 1) LENGTH 40
DIM HpN%, HpQ$, HpBackV% = UV_COLL
DIM UiPV%, UiPSel%, UiPTop%, UiFull% = 1
DIM UiMsg$, UiMsgSt%, UiQuit%, UiOk%
DIM UiRes%, UiQuery$, UiWhere$, UiCols$, UiTxtT$
DIM DtRec$, DtN%
DIM UiHist$(7) LENGTH 128, UiHistN%

' ---------------- drawing --------------------------------------------

FUNCTION UiBodyH%()
  UiBodyH% = HalH% - 3
END FUNCTION

' Replace control characters so they cannot upset the display
FUNCTION UiClean$(s$)
  LOCAL i%, a%, o$
  FOR i% = 1 TO LEN(s$)
    a% = ASC(MID$(s$, i%, 1))
    IF a% < 32 OR a% = 127 THEN o$ = o$ + "?" ELSE o$ = o$ + CHR$(a%)
  NEXT
  UiClean$ = o$
END FUNCTION

' Draw a full-width line
SUB UiLine r%, s$, st%
  HalText 0, r%, LEFT$(LEFT$(s$, HalW%) + SPACE$(HalW%), HalW%), st%
END SUB

SUB UiSay m$, st%
  UiMsg$ = m$ : UiMsgSt% = st%
  UiLine HalH% - 2, UiClean$(LEFT$(m$, HalW%)), st%
END SUB

SUB UiGo v%
  UiV% = v% : UiFull% = 1
END SUB

FUNCTION UiCount%()
  SELECT CASE UiV%
    CASE UV_COLL : UiCount% = StCatN%
    CASE UV_RECS
      IF UiRes% THEN UiCount% = ExN% ELSE UiCount% = IxN%
    CASE UV_DET : UiCount% = DtN%
    CASE UV_HELP : UiCount% = HpN%
    CASE ELSE : UiCount% = ExOutN%
  END SELECT
END FUNCTION

' File offset of the record on list row i%
FUNCTION UiOff%(i%)
  IF UiRes% THEN UiOff% = ExR%(i%) ELSE UiOff% = IxO%(i%)
END FUNCTION

' Field i% (0-based) of the record shown in the detail view
FUNCTION DtField%(i%, k$, v$, t%)
  LOCAL ip% = 1, n% = 0
  DO
    ip% = RcNext%(DtRec$, ip%, k$, v$, t%)
    IF ip% <= 0 THEN EXIT FUNCTION
    IF n% = i% THEN DtField% = 1 : EXIT FUNCTION
    INC n%
  LOOP
END FUNCTION

SUB DtLoad r$
  DtRec$ = r$ : DtN% = MAX(0, RcCheck%(r$))
END SUB

' One-line record summary: _id then fields (or the SELECTed ones)
FUNCTION UiPreview$(r$)
  LOCAL s$, ip% = 1, k$, v$, t%, i%
  s$ = RcGet$(r$, "_id")
  IF UiCols$ = "" THEN
    DO
      ip% = RcNext%(r$, ip%, k$, v$, t%)
      IF ip% <= 0 OR LEN(s$) >= HalW% THEN EXIT DO
      IF LEFT$(k$, 1) <> "_" THEN s$ = s$ + " " + LEFT$(k$, HalW%) + ":" + LEFT$(v$, HalW%)
    LOOP
  ELSE
    FOR i% = 1 TO QF_MAX
      k$ = FIELD$(UiCols$, i%, ",")
      IF k$ = "" OR LEN(s$) >= HalW% THEN EXIT FOR
      v$ = RcGet$(r$, k$)
      IF RcFound% AND k$ <> "_id" THEN s$ = s$ + " " + LEFT$(k$, HalW%) + ":" + LEFT$(v$, HalW%)
    NEXT
  ENDIF
  UiPreview$ = UiClean$(LEFT$(s$, HalW%))
END FUNCTION

FUNCTION UiRowText$(i%)
  LOCAL k$, v$, t%
  SELECT CASE UiV%
    CASE UV_COLL
      UiRowText$ = StCat$(i%)
      IF StCat$(i%) = StCol$ THEN UiRowText$ = StCat$(i%) + "  (open)"
    CASE UV_RECS
      UiRowText$ = UiPreview$(StRead$(UiOff%(i%)))
    CASE UV_DET
      IF DtField%(i%, k$, v$, t%) THEN
        IF t% = 1 AND RcLit%(v$) THEN v$ = "'" + v$ + "'"
        k$ = LEFT$(k$, HalW%)
        IF LEN(k$) < 10 THEN k$ = LEFT$(k$ + SPACE$(10), 10)
        UiRowText$ = UiClean$(LEFT$(k$ + ": " + LEFT$(v$, HalW%), HalW%))
      ENDIF
    CASE UV_HELP
      UiRowText$ = HpTitle$(i%)
    CASE ELSE
      UiRowText$ = ExOut$(i%)
  END SELECT
END FUNCTION

' Draw list entry i% (absolute index) in its body row
SUB UiDrawRow i%
  LOCAL r% = i% - UiTop%(UiV%) + 1, st% = US_N
  IF r% < 1 OR r% > UiBodyH%() THEN EXIT SUB
  IF i% = UiSel%(UiV%) AND UiV% <> UV_TEXT THEN st% = US_SEL
  IF i% < UiCount%() THEN UiLine r%, UiRowText$(i%), st% ELSE UiLine r%, "", US_N
END SUB

FUNCTION UiTitle$()
  LOCAL s$, n% = UiCount%()
  SELECT CASE UiV%
    CASE UV_COLL : s$ = "Collections (" + STR$(n%) + ")"
    CASE UV_RECS
      s$ = StCol$ + "  " + STR$(MIN(UiSel%(UV_RECS) + 1, n%)) + "/" + STR$(n%)
      IF UiRes% THEN s$ = s$ + "  [" + UiWhere$ + "]"
    CASE UV_DET : s$ = StCol$ + " > " + RcGet$(DtRec$, "_id")
    CASE UV_HELP
      IF HpQ$ = "" THEN s$ = "Help: contents" ELSE s$ = "Help: " + HpQ$
      s$ = s$ + " (" + STR$(n%) + ")"
    CASE ELSE : s$ = UiTxtT$
  END SELECT
  UiTitle$ = UiClean$(LEFT$(s$, HalW%))
END FUNCTION

FUNCTION UiHints$()
  SELECT CASE UiV%
    CASE UV_COLL : UiHints$ = "Ent open N new Del drop / sql F1"
    CASE UV_RECS : UiHints$ = "Ent view F filter N new Del D / Esc"
    CASE UV_DET : UiHints$ = "Ent edit A add Del rm <> rec Esc"
    CASE UV_HELP : UiHints$ = "Ent read  F1 search  Esc back"
    CASE ELSE : UiHints$ = "Up/Dn scroll  Esc back"
  END SELECT
END FUNCTION

' Repaint what changed (everything after UiFull% = 1)
SUB UiPaint
  LOCAL i%, n% = UiCount%(), h% = UiBodyH%(), v% = UiV%
  IF UiSel%(v%) > n% - 1 THEN UiSel%(v%) = n% - 1
  IF UiSel%(v%) < 0 THEN UiSel%(v%) = 0
  IF v% = UV_TEXT THEN
    IF UiSel%(v%) > MAX(0, n% - h%) THEN UiSel%(v%) = MAX(0, n% - h%)
    UiTop%(v%) = UiSel%(v%)
  ELSE
    IF UiSel%(v%) < UiTop%(v%) THEN UiTop%(v%) = UiSel%(v%)
    IF UiSel%(v%) >= UiTop%(v%) + h% THEN UiTop%(v%) = UiSel%(v%) - h% + 1
    IF UiTop%(v%) > MAX(0, n% - h%) THEN UiTop%(v%) = MAX(0, n% - h%)
  ENDIF
  IF UiPV% <> v% OR UiPTop% <> UiTop%(v%) THEN UiFull% = 1
  UiLine 0, UiTitle$(), US_TITLE
  IF UiFull% THEN
    FOR i% = UiTop%(v%) TO UiTop%(v%) + h% - 1 : UiDrawRow i% : NEXT
    UiLine HalH% - 2, UiClean$(LEFT$(UiMsg$, HalW%)), UiMsgSt%
    UiLine HalH% - 1, UiHints$(), US_HINT
  ELSEIF UiPSel% <> UiSel%(v%) THEN
    UiDrawRow UiPSel%
    UiDrawRow UiSel%(v%)
  ENDIF
  UiFull% = 0 : UiPV% = v% : UiPSel% = UiSel%(v%) : UiPTop% = UiTop%(v%)
END SUB

' ---------------- input ----------------------------------------------

FUNCTION UiAsk%(q$)
  LOCAL k%
  UiLine HalH% - 2, UiClean$(q$) + " (y/n)", US_ERR
  k% = HalKey%()
  UiAsk% = (k% = 89 OR k% = 121)
  UiFull% = 1
END FUNCTION

' Line editor on the message row. UiOk% = 1 on Enter, 0 on Esc.
' hist% = 1: Up/Down recall earlier entries.
FUNCTION UiInput$(p$, init$, hist%)
  LOCAL s$ = init$, cp% = LEN(init$) + 1, off% = 1, w%, k%, hp% = UiHistN%, c$
  w% = HalW% - LEN(p$) - 1
  DO
    IF cp% < off% THEN off% = cp%
    IF cp% >= off% + w% THEN off% = cp% - w% + 1
    UiLine HalH% - 2, p$ + UiClean$(MID$(s$, off%, w%)), US_MSG
    c$ = MID$(s$, cp%, 1)
    IF c$ = "" THEN c$ = " "
    HalText LEN(p$) + cp% - off%, HalH% - 2, UiClean$(c$), US_SEL
    k% = HalKey%()
    SELECT CASE k%
      CASE UK_ENT : UiOk% = 1 : EXIT DO
      CASE UK_ESC : UiOk% = 0 : EXIT DO
      CASE UK_BS
        IF cp% > 1 THEN s$ = LEFT$(s$, cp% - 2) + MID$(s$, cp%) : INC cp%, -1
      CASE UK_DEL, UK_DEL2 : s$ = LEFT$(s$, cp% - 1) + MID$(s$, cp% + 1)
      CASE UK_LT : cp% = MAX(1, cp% - 1)
      CASE UK_RT : cp% = MIN(LEN(s$) + 1, cp% + 1)
      CASE UK_HOME : cp% = 1
      CASE UK_END : cp% = LEN(s$) + 1
      CASE UK_UP, UK_DN
        IF hist% AND UiHistN% > 0 THEN
          IF k% = UK_UP THEN hp% = MAX(0, hp% - 1) ELSE hp% = MIN(UiHistN%, hp% + 1)
          IF hp% < UiHistN% THEN s$ = UiHist$(hp%) ELSE s$ = ""
          cp% = LEN(s$) + 1
        ENDIF
      CASE 32 TO 126, 160 TO 255
        IF LEN(s$) < 255 THEN s$ = LEFT$(s$, cp% - 1) + CHR$(k%) + MID$(s$, cp%) : INC cp%
    END SELECT
  LOOP
  IF UiOk% AND hist% AND s$ <> "" AND LEN(s$) <= 128 THEN
    IF UiHistN% > 7 THEN
      FOR k% = 0 TO 6 : UiHist$(k%) = UiHist$(k% + 1) : NEXT
      UiHistN% = 7
    ENDIF
    UiHist$(UiHistN%) = s$ : INC UiHistN%
  ENDIF
  UiFull% = 1
  UiInput$ = s$
END FUNCTION

' Type for an edited value: text stays text; '...' forces text
FUNCTION UiType%(v$, ot%)
  UiType% = 1
  IF ot% = 1 THEN EXIT FUNCTION
  IF LEN(v$) >= 2 AND LEFT$(v$, 1) = "'" AND RIGHT$(v$, 1) = "'" THEN
    v$ = MID$(v$, 2, LEN(v$) - 2) : EXIT FUNCTION
  ENDIF
  IF RcLit%(v$) THEN UiType% = 2
END FUNCTION

' ---------------- list maintenance -----------------------------------

SUB UiListColl sel$
  LOCAL i%, n% = StList%()
  FOR i% = 0 TO n% - 1
    IF StCat$(i%) = sel$ THEN UiSel%(UV_COLL) = i%
  NEXT
  UiFull% = 1
END SUB

' Re-run the active filter so offsets are current after a write
SUB UiReload
  IF UiRes% THEN
    IF ExRun%(UiQuery$) = 0 OR ExKind$ <> "ROWS" THEN
      UiRes% = 0 : UiSay "filter cleared: " + ExErr$, US_ERR
    ENDIF
  ENDIF
  UiFull% = 1
END SUB

' List row holding record id$, or -1
FUNCTION UiFind%(id$)
  LOCAL i%, o% = IxGet%(id$)
  UiFind% = -1
  IF o% < 0 THEN EXIT FUNCTION
  FOR i% = 0 TO UiCount%() - 1
    IF UiOff%(i%) = o% THEN UiFind% = i% : EXIT FUNCTION
  NEXT
END FUNCTION

SUB UiFilter w$
  LOCAL q$, e$, p%
  IF w$ = "" THEN
    UiRes% = 0 : UiWhere$ = "" : UiCols$ = "" : UiFull% = 1 : EXIT SUB
  ENDIF
  q$ = "SELECT * FROM " + StCol$ + " WHERE "
  IF ExRun%(q$ + w$) THEN
    UiRes% = 1 : UiQuery$ = q$ + w$ : UiWhere$ = w$ : UiCols$ = ""
    UiSel%(UV_RECS) = 0 : UiFull% = 1 : UiSay ExMsg$, US_MSG
  ELSE
    e$ = ExErr$ : p% = INSTR(e$, " at col ")
    IF p% THEN e$ = LEFT$(e$, p% + 7) + STR$(VAL(MID$(e$, p% + 8)) - LEN(q$))
    UiSay e$, US_ERR
  ENDIF
END SUB

SUB UiText t$
  IF UiV% <> UV_TEXT THEN UiBackV% = UiV%
  UiTxtT$ = t$ : UiSel%(UV_TEXT) = 0 : UiGo UV_TEXT
END SUB

SUB UiHelpKeys
  ExOutN% = 0
  ExSay "(no help file: " + StDir$ + "help/)"
  ExSay "Arrows move, PgUp/PgDn page, Home/End"
  ExSay "F2 or /  SQL console (Up/Dn: history)"
  ExSay "Esc      back"
  ExSay ""
  ExSay "Collections: Ent open, N new, Del drop"
  ExSay "Records: Ent view, F filter, N new,"
  ExSay "  Del delete, D describe, Esc unfilter"
  ExSay "Detail: Ent edit, A add, Del remove,"
  ExSay "  Left/Right previous/next record"
  ExSay "  Text stays text; 'x' forces text"
  ExSay ""
  ExSay "SELECT */COUNT(*)/f,.. FROM c"
  ExSay "  WHERE f = 1 AND g LIKE 'a%' OR"
  ExSay "  h IS NULL ORDER BY f DESC LIMIT 9"
  ExSay "INSERT INTO c (f, g) VALUES (1, 'x')"
  ExSay "UPDATE c SET f = 2 UNSET g WHERE .."
  ExSay "DELETE FROM c WHERE .."
  ExSay "CREATE/DROP COLLECTION c"
  ExSay "CREATE/DROP INDEX ON c (f)"
  ExSay "SHOW COLLECTIONS  DESCRIBE c"
  ExSay "VACUUM c   EXPLAIN SELECT .."
  UiText "Help: keys"
END SUB

' Topic of a help record: its _id up to the first "."
FUNCTION HpTopic$(id$)
  LOCAL p% = INSTR(id$, ".")
  IF p% THEN HpTopic$ = LEFT$(id$, p% - 1) ELSE HpTopic$ = id$
END FUNCTION

SUB HpAdd tp$, ttl$, mask%, full%
  IF tp$ = "" OR mask% <> full% OR HpN% >= HP_MAX THEN EXIT SUB
  IF ttl$ = "" THEN ttl$ = tp$
  HpId$(HpN%) = LEFT$(tp$, 8) : HpTitle$(HpN%) = UiClean$(LEFT$(ttl$, 40))
  INC HpN%
END SUB

' Find help topics containing every word of q$ (any case) in their
' title, keywords or text. Returns the count, or -1 if no help file.
FUNCTION HpFind%(q$)
  LOCAL r$, tp$, cur$, ttl$, a$, b$, c$, w$(7), x$, nw%, i%, mask%, full%
  HpN% = 0 : HpQ$ = q$
  FOR i% = 1 TO 16
    x$ = FIELD$(LCASE$(q$), i%, " ")
    IF x$ <> "" AND nw% < 8 THEN w$(nw%) = x$ : INC nw%
  NEXT
  full% = (1 << nw%) - 1
  HpFind% = -1
  x$ = "?"
  ON ERROR SKIP 1
  x$ = DIR$(StDir$ + "help/dbhelp.jsonl", FILE)
  IF x$ = "" OR x$ = "?" THEN EXIT FUNCTION
  OPEN StDir$ + "help/dbhelp.jsonl" FOR INPUT AS #HP_FN
  DO WHILE NOT EOF(#HP_FN)
    r$ = IxLine$(HP_FN)
    IF IxLong% = 0 AND RcCheck%(r$) > 0 THEN
      tp$ = HpTopic$(RcGet$(r$, "_id"))
      a$ = RcGet$(r$, "title")
      IF tp$ <> cur$ THEN
        HpAdd cur$, ttl$, mask%, full%
        cur$ = tp$ : ttl$ = a$ : mask% = 0
      ENDIF
      a$ = LCASE$(a$) : b$ = LCASE$(RcGet$(r$, "kw")) : c$ = LCASE$(RcGet$(r$, "text"))
      FOR i% = 0 TO nw% - 1
        IF INSTR(a$, w$(i%)) OR INSTR(b$, w$(i%)) OR INSTR(c$, w$(i%)) THEN mask% = mask% OR (1 << i%)
      NEXT
    ENDIF
  LOOP
  HpAdd cur$, ttl$, mask%, full%
  CLOSE #HP_FN
  HpFind% = HpN%
END FUNCTION

' Word-wrap s$ into ExOut$ lines of at most w% characters
SUB UiWrap s$, w%
  LOCAL b%
  DO WHILE LEN(s$) > w%
    b% = w% + 1
    DO WHILE b% > 1 AND MID$(s$, b%, 1) <> " " : INC b%, -1 : LOOP
    IF b% <= 1 THEN
      ExSay LEFT$(s$, w%) : s$ = MID$(s$, w% + 1)
    ELSE
      ExSay LEFT$(s$, b% - 1) : s$ = MID$(s$, b% + 1)
    ENDIF
  LOOP
  IF s$ <> "" THEN ExSay s$
END SUB

' Show help topic i% of the current topic list
SUB HpShow i%
  LOCAL r$, t$, n% = 0
  IF i% < 0 OR i% >= HpN% THEN EXIT SUB
  ExOutN% = 0
  OPEN StDir$ + "help/dbhelp.jsonl" FOR INPUT AS #HP_FN
  DO WHILE NOT EOF(#HP_FN)
    r$ = IxLine$(HP_FN)
    IF IxLong% = 0 THEN
      IF HpTopic$(RcGet$(r$, "_id")) = HpId$(i%) THEN
        t$ = UiClean$(RcGet$(r$, "text"))
        IF n% > 0 AND t$ <> "" THEN ExSay ""
        IF t$ <> "" THEN UiWrap t$, MIN(HalW%, EX_W)
        INC n%
      ENDIF
    ENDIF
  LOOP
  CLOSE #HP_FN
  UiText HpTitle$(i%)
END SUB

' F1: search the help topics
SUB UiHelp
  LOCAL q$, n%
  q$ = UiInput$("Help search (Enter = all): ", "", 0)
  IF UiOk% = 0 THEN EXIT SUB
  n% = HpFind%(q$)
  IF n% < 0 THEN UiHelpKeys : EXIT SUB
  IF n% = 0 THEN UiSay "no help topics match: " + q$, US_ERR : EXIT SUB
  IF UiV% <> UV_HELP AND UiV% <> UV_TEXT THEN HpBackV% = UiV%
  IF UiV% = UV_TEXT AND UiBackV% <> UV_HELP THEN HpBackV% = UiBackV%
  UiSel%(UV_HELP) = 0 : UiGo UV_HELP
  IF n% = 1 THEN HpShow 0
END SUB

' ---------------- views ----------------------------------------------

SUB UiKeyColl k%
  LOCAL n$
  SELECT CASE k%
    CASE UK_ENT
      IF StCatN% = 0 THEN EXIT SUB
      IF StOpen%(StCat$(UiSel%(UV_COLL))) = 0 THEN UiSay StErr$, US_ERR : EXIT SUB
      UiRes% = 0 : UiCols$ = "" : UiWhere$ = "" : UiSel%(UV_RECS) = 0
      UiGo UV_RECS
      IF StWarn$ <> "" THEN UiSay StWarn$, US_MSG
    CASE 78
      n$ = UiInput$("New collection: ", "", 0)
      IF INSTR(QRES$, " " + UCASE$(n$) + " ") AND n$ <> "" THEN
        UiSay n$ + " is an SQL word; choose another name", US_ERR : EXIT SUB
      ENDIF
      IF UiOk% AND n$ <> "" THEN
        IF StCreate%(n$) THEN UiListColl n$ ELSE UiSay StErr$, US_ERR
      ENDIF
    CASE UK_DEL
      IF StCatN% = 0 THEN EXIT SUB
      n$ = StCat$(UiSel%(UV_COLL))
      IF UiAsk%("Drop " + n$ + " and its data?") THEN
        IF StDrop%(n$) THEN UiListColl "" ELSE UiSay StErr$, US_ERR
      ENDIF
    CASE UK_ESC
      IF UiAsk%("Quit?") THEN UiQuit% = 1
  END SELECT
END SUB

SUB UiOpenDet i%
  IF i% < 0 OR i% >= UiCount%() THEN EXIT SUB
  UiSel%(UV_RECS) = i%
  DtLoad StRead$(UiOff%(i%))
  UiGo UV_DET
END SUB

SUB UiKeyRecs k%
  LOCAL id$, x%
  SELECT CASE k%
    CASE UK_ENT : UiOpenDet UiSel%(UV_RECS)
    CASE 70
      id$ = UiInput$("WHERE ", UiWhere$, 1)
      IF UiOk% THEN UiFilter id$
    CASE 78
      id$ = UiInput$("New _id (blank = auto): ", "", 0)
      IF UiOk% = 0 THEN EXIT SUB
      IF id$ = "" THEN id$ = StNewId$()
      IF StWrite%(RcNew$(id$), 1) = 0 THEN UiSay StErr$, US_ERR : EXIT SUB
      UiReload
      x% = UiFind%(id$)
      IF x% >= 0 THEN UiSel%(UV_RECS) = x%
      DtLoad StFetch$(id$) : UiGo UV_DET
      UiSay "created " + id$ + " - A adds fields", US_MSG
    CASE UK_DEL
      IF UiCount%() = 0 THEN EXIT SUB
      id$ = RcGet$(StRead$(UiOff%(UiSel%(UV_RECS))), "_id")
      IF UiAsk%("Delete " + id$ + "?") THEN
        IF StDelete%(id$) THEN
          UiReload : UiSay "deleted " + id$, US_MSG
        ELSE
          UiSay StErr$, US_ERR
        ENDIF
      ENDIF
    CASE 68
      IF ExRun%("DESCRIBE " + StCol$) THEN UiText "Describe " + StCol$ ELSE UiSay ExErr$, US_ERR
    CASE UK_ESC
      IF UiRes% THEN
        UiFilter ""
      ELSE
        UiListColl StCol$ : UiGo UV_COLL
      ENDIF
  END SELECT
END SUB

' Save one field of the detail record (t% = 0 removes it)
SUB UiSave k$, v$, t%
  LOCAL id$ = RcGet$(DtRec$, "_id"), x%
  IF StSetField%(id$, k$, v$, t%) = 0 THEN UiSay StErr$, US_ERR : EXIT SUB
  DtLoad StFetch$(id$)
  UiReload
  x% = UiFind%(id$)
  IF x% >= 0 THEN UiSel%(UV_RECS) = x%
  UiFull% = 1 : UiSay "saved", US_MSG
END SUB

SUB UiKeyDet kc%
  LOCAL k$, v$, t%, ok%
  ok% = DtField%(UiSel%(UV_DET), k$, v$, t%)
  SELECT CASE kc%
    CASE UK_ENT
      IF ok% = 0 THEN EXIT SUB
      IF LEFT$(k$, 1) = "_" THEN UiSay k$ + " cannot be edited", US_ERR : EXIT SUB
      IF t% = 3 THEN UiSay "nested values are read-only", US_ERR : EXIT SUB
      v$ = UiInput$(LEFT$(k$, 12) + ": ", v$, 0)
      IF UiOk% THEN t% = UiType%(v$, t%) : UiSave k$, v$, t%
    CASE 65
      k$ = UiInput$("Field name: ", "", 0)
      IF UiOk% = 0 OR k$ = "" THEN EXIT SUB
      IF LEFT$(k$, 1) = "_" THEN UiSay "names starting with _ are reserved", US_ERR : EXIT SUB
      v$ = RcGet$(DtRec$, k$) : t% = RcT%
      v$ = UiInput$(LEFT$(k$, 12) + ": ", v$, 0)
      IF UiOk% THEN t% = UiType%(v$, t%) : UiSave k$, v$, t%
    CASE UK_DEL
      IF ok% = 0 THEN EXIT SUB
      IF LEFT$(k$, 1) = "_" THEN UiSay k$ + " cannot be removed", US_ERR : EXIT SUB
      IF UiAsk%("Remove " + LEFT$(k$, 20) + "?") THEN UiSave k$, "", 0
    CASE UK_LT : UiOpenDet UiSel%(UV_RECS) - 1
    CASE UK_RT : UiOpenDet UiSel%(UV_RECS) + 1
    CASE UK_ESC : UiReload : UiGo UV_RECS
  END SELECT
END SUB

SUB UiConsole
  LOCAL q$, i%, id$
  q$ = UiInput$("sql> ", "", 1)
  IF UiOk% = 0 OR q$ = "" THEN EXIT SUB
  IF ExRun%(q$) = 0 THEN UiSay ExErr$, US_ERR : EXIT SUB
  SELECT CASE ExKind$
    CASE "ROWS"
      UiRes% = 1 : UiQuery$ = q$ : UiWhere$ = "query" : UiCols$ = ""
      FOR i% = 0 TO QFN% - 1
        IF i% > 0 THEN UiCols$ = UiCols$ + ","
        UiCols$ = UiCols$ + QFld$(i%)
      NEXT
      UiSel%(UV_RECS) = 0 : UiGo UV_RECS
      UiSay ExMsg$, US_MSG
    CASE "COUNT" : UiSay "count = " + STR$(ExCnt%), US_MSG
    CASE "TEXT" : UiText UiClean$(LEFT$(q$, HalW%))
    CASE ELSE
      q$ = ExMsg$ : i% = StList%()
      IF UiV% = UV_DET THEN id$ = RcGet$(DtRec$, "_id")
      IF StCol$ = "" AND UiV% <> UV_COLL THEN
        UiRes% = 0 : UiGo UV_COLL
      ELSEIF UiV% = UV_RECS OR UiV% = UV_DET THEN
        UiReload
        IF UiV% = UV_DET THEN
          IF IxGet%(id$) < 0 THEN UiGo UV_RECS ELSE DtLoad StFetch$(id$)
        ENDIF
      ENDIF
      UiFull% = 1 : UiSay q$, US_MSG
  END SELECT
END SUB

' ---------------- main loop ------------------------------------------

SUB UiKey k%
  IF k% >= 97 AND k% <= 122 THEN k% = k% - 32
  IF k% = UK_DEL2 THEN k% = UK_DEL
  IF UiV% <> UV_DET THEN
    IF k% = UK_LT THEN k% = UK_PU
    IF k% = UK_RT THEN k% = UK_PD
  ENDIF
  IF UiNav%(k%) THEN EXIT SUB
  IF k% = UK_F1 THEN UiHelp : EXIT SUB
  IF k% = UK_F2 OR k% = 47 THEN UiConsole : EXIT SUB
  SELECT CASE UiV%
    CASE UV_COLL : UiKeyColl k%
    CASE UV_RECS : UiKeyRecs k%
    CASE UV_DET : UiKeyDet k%
    CASE UV_HELP
      IF k% = UK_ENT THEN HpShow UiSel%(UV_HELP)
      IF k% = UK_ESC THEN UiGo HpBackV%
    CASE ELSE
      IF k% = UK_ESC OR k% = UK_ENT THEN UiGo UiBackV%
  END SELECT
END SUB

FUNCTION UiNav%(k%)
  LOCAL n% = UiCount%(), s% = UiSel%(UiV%), h% = UiBodyH%()
  SELECT CASE k%
    CASE UK_UP : INC s%, -1
    CASE UK_DN : INC s%
    CASE UK_PU : INC s%, -h%
    CASE UK_PD : INC s%, h%
    CASE UK_HOME : s% = 0
    CASE UK_END : s% = n% - 1
    CASE ELSE : EXIT FUNCTION
  END SELECT
  UiSel%(UiV%) = MAX(0, MIN(s%, n% - 1))
  UiNav% = 1
END FUNCTION

' Process one key press
SUB UiStep
  LOCAL k% = HalKey%()
  IF UiMsg$ <> "" THEN UiSay "", US_N
  UiKey k%
  UiPaint
END SUB

SUB UiMain
  HalInit
  HalCls
  UiListColl ""
  UiGo UV_COLL
  UiPaint
  DO WHILE UiQuit% = 0 : UiStep : LOOP
  StClose
  HalCls
END SUB
