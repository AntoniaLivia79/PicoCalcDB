' =====================================================================
' dbstore.bas - Storage engine + catalog/metadata (needs dbcore.bas)
' ---------------------------------------------------------------------
' One open collection at a time. Files in StDir$ per collection:
'   name.jsonl  data, append-only JSON Lines (readable by anything)
'   name.idx    saved primary index (optional, rebuilt if stale)
'   name.meta   metadata, also JSON Lines:
'                 {"_id":"@","seq":12,"dead":3,"i0":"age","i1":"name"}
'                 {"_id":"age","t":"N"}   one line per known field
'                 {"_id":"@user",...}     script-defined properties
' Field types: S string, N number, L true/false/null, O nested, X mixed
' File numbers 1-3 are reserved for this module.
' =====================================================================

CONST ST_RD = 1, ST_WR = 2, ST_TMP = 3
CONST MT_MAX = 24                  ' max tracked fields per collection
CONST ST_CATMAX = 32               ' max collections listed

DIM StDir$ = "B:/db/"              ' set before use; must end with /
DIM StCol$, StErr$, StWarn$        ' open collection, error, warning
DIM StRdOpen% = 0
DIM MtF$(MT_MAX - 1) LENGTH 24, MtT$(MT_MAX - 1) LENGTH 1
DIM MtN%, MtSeq%, MtDead%, MtDirty%, MtUser$
DIM StCat$(ST_CATMAX - 1) LENGTH 16, StCatN%

SUB StWarnAdd m$
  IF StWarn$ <> "" THEN StWarn$ = StWarn$ + "; "
  StWarn$ = StWarn$ + m$
END SUB

FUNCTION StPath$(ext$)
  StPath$ = StDir$ + StCol$ + ext$
END FUNCTION

FUNCTION StExists%(p$)
  StExists% = (DIR$(p$, FILE) <> "")
END FUNCTION

SUB StKill p$
  IF StExists%(p$) THEN KILL p$
END SUB

FUNCTION StNameOk%(n$)
  LOCAL i%, c$
  StNameOk% = 0
  IF LEN(n$) = 0 OR LEN(n$) > 16 THEN StErr$ = "bad name" : EXIT FUNCTION
  FOR i% = 1 TO LEN(n$)
    c$ = UCASE$(MID$(n$, i%, 1))
    IF INSTR("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_", c$) = 0 THEN
      StErr$ = "bad name" : EXIT FUNCTION
    ENDIF
  NEXT
  StNameOk% = 1
END FUNCTION

' ---------------- catalog --------------------------------------------

' Fill StCat$() with collection names, sorted. Returns the count.
FUNCTION StList%()
  LOCAL f$
  StCatN% = 0
  f$ = DIR$(StDir$ + "*.jsonl", FILE)
  DO WHILE f$ <> "" AND StCatN% < ST_CATMAX
    IF LEN(f$) <= 22 THEN
      StCat$(StCatN%) = LEFT$(f$, LEN(f$) - 6) : INC StCatN%
    ENDIF
    f$ = DIR$()
  LOOP
  IF StCatN% > 1 THEN SORT StCat$(), , , 0, StCatN%
  StList% = StCatN%
END FUNCTION

' Writes the empty data file and the initial metadata line directly,
' so the open collection (if any) is left alone.
FUNCTION StCreate%(n$)
  LOCAL q$ = CHR$(34)
  StErr$ = ""
  IF StNameOk%(n$) = 0 THEN EXIT FUNCTION
  IF StExists%(StDir$ + n$ + ".jsonl") THEN StErr$ = "exists" : EXIT FUNCTION
  OPEN StDir$ + n$ + ".jsonl" FOR OUTPUT AS #ST_TMP : CLOSE #ST_TMP
  OPEN StDir$ + n$ + ".meta" FOR OUTPUT AS #ST_TMP
  PRINT #ST_TMP, "{" + q$ + "_id" + q$ + ":" + q$ + "@" + q$ + "," + q$ + "seq" + q$ + ":0," + q$ + "dead" + q$ + ":0}"
  CLOSE #ST_TMP
  StCreate% = 1
END FUNCTION

FUNCTION StDrop%(n$)
  StErr$ = ""
  IF StNameOk%(n$) = 0 THEN EXIT FUNCTION
  IF StExists%(StDir$ + n$ + ".jsonl") = 0 THEN StErr$ = "no such collection" : EXIT FUNCTION
  IF n$ = StCol$ THEN StRdClose : StCol$ = "" : IxClear
  StKill StDir$ + n$ + ".jsonl"
  StKill StDir$ + n$ + ".idx"
  StKill StDir$ + n$ + ".meta"
  StKill StDir$ + n$ + ".vtmp"
  StDrop% = 1
END FUNCTION

' ---------------- metadata -------------------------------------------

SUB MtClear
  LOCAL s%
  MtN% = 0 : MtSeq% = 0 : MtDead% = 0 : MtDirty% = 0
  MtUser$ = "{" + CHR$(34) + "_id" + CHR$(34) + ":" + CHR$(34) + "@user" + CHR$(34) + "}"
  FOR s% = 0 TO SX_SLOTS - 1 : SxF$(s%) = "" : NEXT
END SUB

SUB MtLoad
  LOCAL r$, id$, v$, s%
  MtClear
  IF StExists%(StPath$(".meta")) = 0 THEN MtDirty% = 1 : EXIT SUB
  OPEN StPath$(".meta") FOR INPUT AS #ST_TMP
  DO WHILE NOT EOF(#ST_TMP)
    LINE INPUT #ST_TMP, r$
    id$ = RcGet$(r$, "_id")
    IF id$ = "@" THEN
      MtSeq% = VAL(RcGet$(r$, "seq")) : MtDead% = VAL(RcGet$(r$, "dead"))
      FOR s% = 0 TO SX_SLOTS - 1
        v$ = RcGet$(r$, "i" + STR$(s%))
        IF RcFound% THEN SxF$(s%) = v$
      NEXT
    ELSEIF id$ = "@user" THEN
      MtUser$ = r$
    ELSEIF id$ <> "" AND LEFT$(id$, 1) <> "@" AND MtN% < MT_MAX THEN
      MtF$(MtN%) = id$ : MtT$(MtN%) = LEFT$(RcGet$(r$, "t") + "X", 1) : INC MtN%
    ENDIF
  LOOP
  CLOSE #ST_TMP
END SUB

' The lines are built directly as JSON text (not with RcSet$), which
' keeps the call depth low when a collection is closed from deep inside
' another operation.
SUB MtSave
  LOCAL r$, i%, q$ = CHR$(34)
  r$ = "{" + q$ + "_id" + q$ + ":" + q$ + "@" + q$ + "," + q$ + "seq" + q$ + ":" + STR$(MtSeq%)
  r$ = r$ + "," + q$ + "dead" + q$ + ":" + STR$(MtDead%)
  FOR i% = 0 TO SX_SLOTS - 1
    IF SxF$(i%) <> "" THEN r$ = r$ + "," + q$ + "i" + STR$(i%) + q$ + ":" + RcEnc$(SxF$(i%))
  NEXT
  OPEN StPath$(".meta") FOR OUTPUT AS #ST_TMP
  PRINT #ST_TMP, r$ + "}"
  IF MtUser$ <> "{" + q$ + "_id" + q$ + ":" + q$ + "@user" + q$ + "}" THEN PRINT #ST_TMP, MtUser$
  FOR i% = 0 TO MtN% - 1
    PRINT #ST_TMP, "{" + q$ + "_id" + q$ + ":" + RcEnc$(MtF$(i%)) + "," + q$ + "t" + q$ + ":" + q$ + MtT$(i%) + q$ + "}"
  NEXT
  CLOSE #ST_TMP
  MtDirty% = 0
END SUB

' Record the fields and value types seen in rec$
SUB MtNote rec$
  LOCAL ip% = 1, k$, v$, t%, ty$, i%, j%
  DO
    ip% = RcNext%(rec$, ip%, k$, v$, t%)
    IF ip% <= 0 THEN EXIT DO
    IF LEFT$(k$, 1) <> "_" AND LEFT$(k$, 1) <> "@" AND LEN(k$) <= 24 THEN
      IF t% = 1 THEN
        ty$ = "S"
      ELSEIF t% = 3 THEN
        ty$ = "O"
      ELSEIF RcIsNum%(v$) THEN
        ty$ = "N"
      ELSE
        ty$ = "L"
      ENDIF
      j% = -1
      FOR i% = 0 TO MtN% - 1
        IF MtF$(i%) = k$ THEN j% = i% : EXIT FOR
      NEXT
      IF j% < 0 THEN
        IF MtN% < MT_MAX THEN
          MtF$(MtN%) = k$ : MtT$(MtN%) = ty$ : INC MtN% : MtDirty% = 1
        ENDIF
      ELSEIF MtT$(j%) <> ty$ AND MtT$(j%) <> "X" THEN
        MtT$(j%) = "X" : MtDirty% = 1
      ENDIF
    ENDIF
  LOOP
END SUB

' ---------------- open / close ---------------------------------------

SUB StRdClose
  IF StRdOpen% THEN CLOSE #ST_RD : StRdOpen% = 0
END SUB

' Read the line at offset off% of the open collection
FUNCTION StRead$(off%)
  IF StRdOpen% = 0 THEN
    OPEN StPath$(".jsonl") FOR INPUT AS #ST_RD : StRdOpen% = 1
  ENDIF
  StRead$ = IxReadAt$(ST_RD, off%)
END FUNCTION

' Make sure the data file ends with a line break, so a torn last
' line (power loss mid-write) is not glued onto the next record.
SUB StFixTail
  LOCAL c$, n%
  OPEN StPath$(".jsonl") FOR INPUT AS #ST_TMP
  n% = LOF(#ST_TMP)
  IF n% > 0 THEN SEEK #ST_TMP, n% : c$ = INPUT$(1, #ST_TMP)
  CLOSE #ST_TMP
  IF n% > 0 AND c$ <> CHR$(10) THEN
    OPEN StPath$(".jsonl") FOR APPEND AS #ST_TMP : PRINT #ST_TMP, "" : CLOSE #ST_TMP
    StWarnAdd "repaired torn last line"
  ENDIF
END SUB

' Spot-check a loaded index against the file (catches external edits)
FUNCTION StVerify%()
  LOCAL i%, j%, r$
  StVerify% = 1
  FOR j% = 0 TO 7
    IF IxN% = 0 THEN EXIT FUNCTION
    i% = (IxN% - 1) * j% \ 7
    r$ = StRead$(IxO%(i%))
    IF RcGet$(r$, "_id") <> IxK$(i%) OR INSTR(r$, CHR$(34) + "_del" + CHR$(34)) > 0 THEN StVerify% = 0 : EXIT FUNCTION
  NEXT
END FUNCTION

FUNCTION StOpen%(n$)
  LOCAL ok%
  StErr$ = "" : StWarn$ = ""
  IF StNameOk%(n$) = 0 THEN EXIT FUNCTION
  IF StCol$ <> "" THEN StClose
  StCol$ = n$
  ' recover from a VACUUM interrupted between KILL and RENAME
  IF StExists%(StPath$(".vtmp")) THEN
    IF StExists%(StPath$(".jsonl")) THEN
      KILL StPath$(".vtmp")
    ELSE
      RENAME StPath$(".vtmp") AS StPath$(".jsonl")
      StKill StPath$(".idx")
    ENDIF
  ENDIF
  IF StExists%(StPath$(".jsonl")) = 0 THEN StErr$ = "no such collection" : StCol$ = "" : EXIT FUNCTION
  MtLoad
  StFixTail
  ok% = IxOpen%(StPath$(".jsonl"), StPath$(".idx"), ST_TMP)
  IF ok% THEN
    IF StVerify%() = 0 THEN
      StRdClose
      StKill StPath$(".idx")
      StWarnAdd "stale index rebuilt"
      ok% = IxOpen%(StPath$(".jsonl"), StPath$(".idx"), ST_TMP)
    ENDIF
  ENDIF
  IF ok% = 0 THEN StErr$ = IxErr$ : StRdClose : StCol$ = "" : IxClear : EXIT FUNCTION
  IF IxBad% > 0 THEN StWarnAdd STR$(IxBad%) + " bad line(s) skipped"
  StOpen% = 1
END FUNCTION

' Persist metadata and the primary index
SUB StFlush
  LOCAL n%
  IF StCol$ = "" THEN EXIT SUB
  StRdClose
  IF MtDirty% THEN MtSave
  OPEN StPath$(".jsonl") FOR INPUT AS #ST_TMP : n% = LOF(#ST_TMP) : CLOSE #ST_TMP
  n% = IxSave%(StPath$(".idx"), ST_TMP, n%)
END SUB

SUB StClose
  IF StCol$ = "" THEN EXIT SUB
  StFlush
  StCol$ = "" : IxClear
END SUB

' ---------------- reading --------------------------------------------

FUNCTION StCount%()
  StCount% = IxN%
END FUNCTION

' Record at primary-index position i% (0..StCount%()-1), in _id order
FUNCTION StAt$(i%)
  IF i% >= 0 AND i% < IxN% THEN StAt$ = StRead$(IxO%(i%))
END FUNCTION

FUNCTION StFetch$(id$)
  LOCAL o% = IxGet%(id$)
  StErr$ = ""
  IF o% < 0 THEN StErr$ = "not found" ELSE StFetch$ = StRead$(o%)
END FUNCTION

' ---------------- writing --------------------------------------------

' Append one line; returns its offset
FUNCTION StAppend%(r$)
  StRdClose
  OPEN StPath$(".jsonl") FOR APPEND AS #ST_WR
  StAppend% = LOC(#ST_WR)
  PRINT #ST_WR, r$
  CLOSE #ST_WR
END FUNCTION


' Write a whole record. md%: 0 upsert, 1 insert only, 2 update only
FUNCTION StWrite%(rec$, md%)
  LOCAL id$, oo%, old$, off%, n%, s%, x$
  StErr$ = ""
  IF StCol$ = "" THEN StErr$ = "no collection open" : EXIT FUNCTION
  IF RcCheck%(rec$) < 0 OR INSTR(rec$, CHR$(10)) OR INSTR(rec$, CHR$(13)) THEN
    StErr$ = "bad record" : EXIT FUNCTION
  ENDIF
  id$ = RcGet$(rec$, "_id")
  IF RcFound% = 0 OR RcT% <> 1 THEN StErr$ = "_id must be a string" : EXIT FUNCTION
  IF IxKeyOk%(id$) = 0 THEN StErr$ = IxErr$ : EXIT FUNCTION
  IF INSTR(rec$, CHR$(34) + "_del" + CHR$(34)) THEN StErr$ = "_del is reserved" : EXIT FUNCTION
  oo% = IxGet%(id$)
  IF md% = 1 AND oo% > 0 THEN StErr$ = "duplicate _id" : EXIT FUNCTION
  IF md% = 2 AND oo% < 0 THEN StErr$ = "not found" : EXIT FUNCTION
  IF oo% < 0 AND IxN% >= IX_MAX THEN StErr$ = "collection full" : EXIT FUNCTION
  IF oo% > 0 THEN old$ = StRead$(oo%)
  ' index entries needed by the new version minus those of the old one
  ' (counted here rather than in a function: one call level less)
  n% = 0
  FOR s% = 0 TO SX_SLOTS - 1
    IF SxF$(s%) <> "" THEN
      x$ = RcGet$(rec$, SxF$(s%)) : n% = n% + RcFound%
      IF old$ <> "" THEN x$ = RcGet$(old$, SxF$(s%)) : n% = n% - RcFound%
    ENDIF
  NEXT
  IF SxN% + n% > SX_MAX THEN
    StErr$ = "index space full" : EXIT FUNCTION
  ENDIF
  off% = StAppend%(rec$)
  IF IxApply%(rec$, off%, old$) = 0 THEN StErr$ = IxErr$ + " (reopen to rebuild)" : EXIT FUNCTION
  MtNote rec$
  IF oo% > 0 THEN INC MtDead% : MtDirty% = 1
  StWrite% = 1
END FUNCTION

FUNCTION StDelete%(id$)
  LOCAL oo%, old$, tb$, off%
  StErr$ = ""
  oo% = IxGet%(id$)
  IF oo% < 0 THEN StErr$ = "not found" : EXIT FUNCTION
  old$ = StRead$(oo%)
  tb$ = RcSet$(RcNew$(id$), "_del", "1", 2)
  off% = StAppend%(tb$)
  IF IxApply%(tb$, off%, old$) = 0 THEN StErr$ = IxErr$ : EXIT FUNCTION
  INC MtDead%, 2 : MtDirty% = 1
  StDelete% = 1
END FUNCTION

' Set (t% 1 string, 2 literal) or remove (t% = 0) one field
FUNCTION StSetField%(id$, f$, v$, t%)
  LOCAL r$
  IF LEFT$(f$, 1) = "_" THEN StErr$ = "reserved field" : EXIT FUNCTION
  r$ = StFetch$(id$)
  IF StErr$ <> "" THEN EXIT FUNCTION
  IF t% = 0 THEN r$ = RcDel$(r$, f$) ELSE r$ = RcSet$(r$, f$, v$, t%)
  IF r$ = "" THEN StErr$ = RcErr$ : EXIT FUNCTION
  StSetField% = StWrite%(r$, 2)
END FUNCTION

' Next free auto _id: zero padded so _id order = insertion order
FUNCTION StNewId$()
  LOCAL k$
  DO
    INC MtSeq% : MtDirty% = 1
    k$ = STR$(MtSeq%, 6, 0, "0")
  LOOP UNTIL IxGet%(k$) < 0
  StNewId$ = k$
END FUNCTION

' ---------------- maintenance ----------------------------------------

' Rewrite live records only, in _id order. Crash-safe via .vtmp.
FUNCTION StVacuum%()
  LOCAL i%, r$
  StErr$ = ""
  IF StCol$ = "" THEN StErr$ = "no collection open" : EXIT FUNCTION
  StRdClose
  OPEN StPath$(".vtmp") FOR OUTPUT AS #ST_WR
  OPEN StPath$(".jsonl") FOR INPUT AS #ST_RD
  FOR i% = 0 TO IxN% - 1
    PRINT #ST_WR, IxReadAt$(ST_RD, IxO%(i%))
  NEXT
  CLOSE #ST_RD : CLOSE #ST_WR
  KILL StPath$(".jsonl")
  RENAME StPath$(".vtmp") AS StPath$(".jsonl")
  StKill StPath$(".idx")
  MtDead% = 0 : MtDirty% = 1
  IF IxOpen%(StPath$(".jsonl"), StPath$(".idx"), ST_TMP) = 0 THEN StErr$ = IxErr$ : EXIT FUNCTION
  StFlush
  StVacuum% = 1
END FUNCTION

FUNCTION StIndexAdd%(f$)
  LOCAL s%, ok%
  StErr$ = ""
  IF StCol$ = "" THEN StErr$ = "no collection open" : EXIT FUNCTION
  IF f$ = "" OR LEFT$(f$, 1) = "_" OR LEN(f$) > 24 THEN StErr$ = "bad field" : EXIT FUNCTION
  IF SxSlot%(f$) >= 0 THEN StErr$ = "already indexed" : EXIT FUNCTION
  FOR s% = 0 TO SX_SLOTS - 1
    IF SxF$(s%) = "" THEN EXIT FOR
  NEXT
  IF s% >= SX_SLOTS THEN StErr$ = "no free index slot" : EXIT FUNCTION
  SxF$(s%) = f$
  StRdClose
  OPEN StPath$(".jsonl") FOR INPUT AS #ST_TMP
  ok% = SxRebuild%(ST_TMP)
  IF ok% = 0 THEN
    StErr$ = IxErr$ : SxF$(s%) = "" : ok% = SxRebuild%(ST_TMP) : ok% = 0
  ENDIF
  CLOSE #ST_TMP
  IF ok% THEN MtDirty% = 1
  StIndexAdd% = ok%
END FUNCTION

FUNCTION StIndexDrop%(f$)
  LOCAL s% = SxSlot%(f$), p$, i%, w% = 0
  StErr$ = ""
  IF s% < 0 THEN StErr$ = "not indexed" : EXIT FUNCTION
  SxF$(s%) = "" : p$ = CHR$(65 + s%)
  FOR i% = 0 TO SxN% - 1
    IF LEFT$(SxV$(i%), 1) <> p$ THEN SxV$(w%) = SxV$(i%) : SxO%(w%) = SxO%(i%) : INC w%
  NEXT
  SxN% = w% : MtDirty% = 1
  StIndexDrop% = 1
END FUNCTION
