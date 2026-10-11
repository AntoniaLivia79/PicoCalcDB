' =====================================================================
' dbcore.bas - Record codec + index manager for a PicoMite/PicoCalc DB
' ---------------------------------------------------------------------
' Data files are JSON Lines: one flat JSON object per line, max 255
' chars, every record has an "_id" (string, max IX_KLEN chars).
' Deletes are appended tombstones: {"_id":"x","_del":1}
' Offsets are 1-based byte positions as used by LOC() and SEEK.
' Requires OPTION BASE 0 (the default).
' =====================================================================

' ---------- tunables: size these to your Pico's free RAM -------------
CONST IX_MAX = 1000      ' max live records per open collection
CONST IX_KLEN = 16       ' max _id length
CONST SX_MAX = 1000      ' total secondary-index entries (all slots)
CONST SX_SLOTS = 4       ' max indexed fields per collection
CONST SX_PW = 11         ' indexed value prefix width (chars)
CONST RC_MAXLEN = 255

' ---------- codec state ----------------------------------------------
DIM RcErr$               ' last codec error ("" = ok)
DIM RcFound%, RcT%       ' set by RcGet$: found flag, value type
DIM RcKS%, RcVS%, RcVE%  ' set by RcNext%: key start, value start/end
' value types: 1 = string, 2 = literal (number/true/false/null),
'              3 = nested object/array kept verbatim (read-only)

' ---------- index state ----------------------------------------------
DIM IxK$(IX_MAX - 1) LENGTH IX_KLEN   ' sorted _id keys
DIM IxO%(IX_MAX - 1)                  ' record offsets
DIM IxN%, IxErr$, IxBad%, IxLong%     ' count, error, bad lines, flag
DIM SxF$(SX_SLOTS - 1) LENGTH 32      ' indexed field per slot
DIM SxV$(SX_MAX - 1) LENGTH SX_PW + 2 ' slot char + type char + value
DIM SxO%(SX_MAX - 1), SxN%

' =====================================================================
' RECORD CODEC
' =====================================================================

' Skip whitespace in r$ from position i%; returns first non-space pos
FUNCTION RcSkip%(r$, i%)
  LOCAL j% = i%
  DO WHILE j% <= LEN(r$)
    IF ASC(MID$(r$, j%, 1)) > 32 THEN EXIT DO
    INC j%
  LOOP
  RcSkip% = j%
END FUNCTION

' Decode the JSON string whose opening quote is at i% into s$.
' Returns position after the closing quote, or -1 if malformed.
FUNCTION RcStr%(r$, i%, s$)
  LOCAL j% = i% + 1, q%, b%, c$, a%
  s$ = ""
  DO
    q% = INSTR(j%, r$, CHR$(34))
    IF q% = 0 THEN RcStr% = -1 : EXIT FUNCTION
    b% = INSTR(j%, r$, "\")
    IF b% = 0 OR b% > q% THEN
      s$ = s$ + MID$(r$, j%, q% - j%)
      RcStr% = q% + 1
      EXIT FUNCTION
    ENDIF
    s$ = s$ + MID$(r$, j%, b% - j%)
    c$ = MID$(r$, b% + 1, 1)
    j% = b% + 2
    SELECT CASE c$
      CASE "n" : s$ = s$ + CHR$(10)
      CASE "t" : s$ = s$ + CHR$(9)
      CASE "r" : s$ = s$ + CHR$(13)
      CASE "b" : s$ = s$ + CHR$(8)
      CASE "f" : s$ = s$ + CHR$(12)
      CASE "u"
        a% = VAL("&H" + MID$(r$, b% + 2, 4))
        IF a% > 255 THEN s$ = s$ + "?" ELSE s$ = s$ + CHR$(a%)
        j% = b% + 6
      CASE ELSE : s$ = s$ + c$   ' \" \\ \/
    END SELECT
  LOOP
END FUNCTION

' Skip a nested {...} or [...] starting at i%; returns pos after it
FUNCTION RcNest%(r$, i%)
  LOCAL j% = i%, d% = 0, c$, s$
  DO WHILE j% <= LEN(r$)
    c$ = MID$(r$, j%, 1)
    IF c$ = CHR$(34) THEN
      j% = RcStr%(r$, j%, s$)
      IF j% < 0 THEN EXIT DO
    ELSE
      IF c$ = "{" OR c$ = "[" THEN INC d%
      IF c$ = "}" OR c$ = "]" THEN INC d%, -1
      INC j%
      IF d% = 0 THEN RcNest% = j% : EXIT FUNCTION
    ENDIF
  LOOP
  RcNest% = -1
END FUNCTION

' Field iterator. Start with ip% = 1; pass back the returned value.
' Returns next position (>0) with k$, v$, t% filled in,
' 0 at end of record, -1 if the record is malformed or truncated.
FUNCTION RcNext%(r$, ip%, k$, v$, t%)
  LOCAL i%, e%, c$
  i% = RcSkip%(r$, ip%)
  c$ = MID$(r$, i%, 1)
  IF ip% = 1 THEN
    IF c$ <> "{" THEN RcNext% = -1 : EXIT FUNCTION
  ELSEIF c$ = "}" THEN
    RcNext% = 0 : EXIT FUNCTION
  ELSEIF c$ <> "," THEN
    RcNext% = -1 : EXIT FUNCTION
  ENDIF
  i% = RcSkip%(r$, i% + 1)
  c$ = MID$(r$, i%, 1)
  IF c$ = "}" AND ip% = 1 THEN RcNext% = 0 : EXIT FUNCTION
  IF c$ <> CHR$(34) THEN RcNext% = -1 : EXIT FUNCTION
  RcKS% = i%
  i% = RcStr%(r$, i%, k$)
  IF i% < 0 THEN RcNext% = -1 : EXIT FUNCTION
  i% = RcSkip%(r$, i%)
  IF MID$(r$, i%, 1) <> ":" THEN RcNext% = -1 : EXIT FUNCTION
  i% = RcSkip%(r$, i% + 1)
  RcVS% = i%
  c$ = MID$(r$, i%, 1)
  IF c$ = CHR$(34) THEN
    i% = RcStr%(r$, i%, v$) : t% = 1
  ELSEIF c$ = "{" OR c$ = "[" THEN
    i% = RcNest%(r$, i%) : t% = 3
    IF i% > 0 THEN v$ = MID$(r$, RcVS%, i% - RcVS%)
  ELSE
    e% = i%
    DO WHILE e% <= LEN(r$)
      c$ = MID$(r$, e%, 1)
      IF c$ = "," OR c$ = "}" OR ASC(c$) <= 32 THEN EXIT DO
      INC e%
    LOOP
    IF e% = i% THEN RcNext% = -1 : EXIT FUNCTION
    v$ = MID$(r$, i%, e% - i%) : t% = 2 : i% = e%
  ENDIF
  RcVE% = i%
  RcNext% = i%
END FUNCTION

' Value of field k$ ("" if absent; check RcFound% and RcT%)
FUNCTION RcGet$(r$, k$)
  LOCAL ip% = 1, fk$, fv$, ft%
  RcFound% = 0 : RcT% = 0 : RcErr$ = ""
  DO
    ip% = RcNext%(r$, ip%, fk$, fv$, ft%)
    IF ip% <= 0 THEN EXIT DO
    IF fk$ = k$ THEN
      RcFound% = 1 : RcT% = ft% : RcGet$ = fv$
      EXIT FUNCTION
    ENDIF
  LOOP
  IF ip% < 0 THEN RcErr$ = "bad record"
END FUNCTION

' Number of fields, or -1 if malformed (use to skip torn lines)
FUNCTION RcCheck%(r$)
  LOCAL ip% = 1, n% = 0, fk$, fv$, ft%
  DO
    ip% = RcNext%(r$, ip%, fk$, fv$, ft%)
    IF ip% <= 0 THEN EXIT DO
    INC n%
  LOOP
  IF ip% < 0 THEN RcCheck% = -1 ELSE RcCheck% = n%
END FUNCTION

' JSON-quote a string; "" + RcErr$ if the result would exceed 255
FUNCTION RcEnc$(s$)
  LOCAL i%, a%, o$, c$
  o$ = CHR$(34)
  FOR i% = 1 TO LEN(s$)
    a% = ASC(MID$(s$, i%, 1))
    SELECT CASE a%
      CASE 34 : c$ = "\" + CHR$(34)
      CASE 92 : c$ = "\\"
      CASE 10 : c$ = "\n"
      CASE 9  : c$ = "\t"
      CASE 13 : c$ = "\r"
      CASE IS < 32 : c$ = "\u00" + HEX$(a%, 2)
      CASE ELSE : c$ = CHR$(a%)
    END SELECT
    IF LEN(o$) + LEN(c$) > 254 THEN
      RcErr$ = "too long" : RcEnc$ = "" : EXIT FUNCTION
    ENDIF
    o$ = o$ + c$
  NEXT
  RcEnc$ = o$ + CHR$(34)
END FUNCTION

' 1 if s$ is a valid JSON number
FUNCTION RcIsNum%(s$)
  LOCAL i% = 1, n% = LEN(s$), d% = 0
  IF MID$(s$, 1, 1) = "-" THEN i% = 2
  DO WHILE i% <= n% AND INSTR("0123456789", MID$(s$, i%, 1)) > 0
    INC i% : INC d%
  LOOP
  IF d% = 0 THEN EXIT FUNCTION
  IF MID$(s$, i%, 1) = "." THEN
    INC i% : d% = 0
    DO WHILE i% <= n% AND INSTR("0123456789", MID$(s$, i%, 1)) > 0
      INC i% : INC d%
    LOOP
    IF d% = 0 THEN EXIT FUNCTION
  ENDIF
  IF UCASE$(MID$(s$, i%, 1)) = "E" THEN
    INC i% : d% = 0
    IF INSTR("+-", MID$(s$, i%, 1)) > 0 AND i% <= n% THEN INC i%
    DO WHILE i% <= n% AND INSTR("0123456789", MID$(s$, i%, 1)) > 0
      INC i% : INC d%
    LOOP
    IF d% = 0 THEN EXIT FUNCTION
  ENDIF
  RcIsNum% = (i% > n%)
END FUNCTION

' 1 if s$ may be stored unquoted (number, true, false, null)
FUNCTION RcLit%(s$)
  RcLit% = RcIsNum%(s$) OR s$ = "true" OR s$ = "false" OR s$ = "null"
END FUNCTION

' Set field k$ to v$. t%: 1 string, 2 literal, 3 raw JSON.
' Replaces in place, else appends. Returns "" + RcErr$ on failure.
FUNCTION RcSet$(r$, k$, v$, t%)
  LOCAL ev$, ek$, x$, p%, j%
  x$ = RcGet$(r$, k$)
  IF RcErr$ <> "" THEN EXIT FUNCTION
  IF t% = 1 THEN
    ev$ = RcEnc$(v$)
    IF ev$ = "" THEN EXIT FUNCTION
  ELSE
    IF t% = 2 AND RcLit%(v$) = 0 THEN RcErr$ = "bad literal" : EXIT FUNCTION
    ev$ = v$
  ENDIF
  IF RcFound% THEN
    IF LEN(r$) - (RcVE% - RcVS%) + LEN(ev$) > RC_MAXLEN THEN
      RcErr$ = "too long" : EXIT FUNCTION
    ENDIF
    RcSet$ = LEFT$(r$, RcVS% - 1) + ev$ + MID$(r$, RcVE%)
    EXIT FUNCTION
  ENDIF
  ek$ = RcEnc$(k$)
  IF ek$ = "" THEN EXIT FUNCTION
  p% = LEN(r$)
  DO WHILE p% > 1 AND MID$(r$, p%, 1) <> "}" : INC p%, -1 : LOOP
  j% = p% - 1
  DO WHILE j% > 1 AND ASC(MID$(r$, j%, 1)) <= 32 : INC j%, -1 : LOOP
  IF MID$(r$, j%, 1) <> "{" THEN ek$ = "," + ek$
  IF LEN(r$) + LEN(ek$) + 1 + LEN(ev$) > RC_MAXLEN THEN
    RcErr$ = "too long" : EXIT FUNCTION
  ENDIF
  RcSet$ = LEFT$(r$, j%) + ek$ + ":" + ev$ + MID$(r$, j% + 1)
END FUNCTION

' Remove field k$ (returns r$ unchanged if absent)
FUNCTION RcDel$(r$, k$)
  LOCAL x$, a%, b%, j%
  x$ = RcGet$(r$, k$)
  IF RcFound% = 0 THEN RcDel$ = r$ : EXIT FUNCTION
  a% = RcKS% : b% = RcVE%
  j% = a% - 1
  DO WHILE j% > 1 AND ASC(MID$(r$, j%, 1)) <= 32 : INC j%, -1 : LOOP
  IF MID$(r$, j%, 1) = "," THEN
    a% = j%
  ELSE
    j% = RcSkip%(r$, b%)
    IF MID$(r$, j%, 1) = "," THEN b% = RcSkip%(r$, j% + 1)
  ENDIF
  RcDel$ = LEFT$(r$, a% - 1) + MID$(r$, b%)
END FUNCTION

' New empty record with an _id
FUNCTION RcNew$(id$)
  RcNew$ = "{" + RcEnc$("_id") + ":" + RcEnc$(id$) + "}"
END FUNCTION

' 1 if r$ is a tombstone
FUNCTION RcIsDel%(r$)
  LOCAL x$
  IF INSTR(r$, CHR$(34) + "_del" + CHR$(34)) = 0 THEN EXIT FUNCTION
  x$ = RcGet$(r$, "_del")
  RcIsDel% = RcFound% AND x$ <> "0" AND x$ <> "false"
END FUNCTION

' =====================================================================
' INDEX MANAGER
' =====================================================================

' Binary search over a$(0..n%-1): first i with a$(i) >= k$
' (gt% = 0) or a$(i) > k$ (gt% = 1)
FUNCTION IxBound%(a$(), n%, k$, gt%)
  LOCAL lo% = 0, hi% = n%, m%
  DO WHILE lo% < hi%
    m% = (lo% + hi%) \ 2
    IF a$(m%) < k$ OR (gt% AND a$(m%) = k$) THEN
      lo% = m% + 1
    ELSE
      hi% = m%
    ENDIF
  LOOP
  IxBound% = lo%
END FUNCTION

SUB IxClear
  IxN% = 0 : SxN% = 0 : IxErr$ = "" : IxBad% = 0
END SUB

' Offset of record k$, or -1
FUNCTION IxGet%(k$)
  LOCAL i% = IxBound%(IxK$(), IxN%, k$, 0)
  IxGet% = -1
  IF i% < IxN% THEN
    IF IxK$(i%) = k$ THEN IxGet% = IxO%(i%)
  ENDIF
END FUNCTION

' 1 if k$ is usable as a primary key
FUNCTION IxKeyOk%(k$)
  IxKeyOk% = 0
  IF LEN(k$) = 0 OR LEN(k$) > IX_KLEN THEN IxErr$ = "bad key length" : EXIT FUNCTION
  IF INSTR(k$, CHR$(10)) OR INSTR(k$, CHR$(13)) OR INSTR(k$, CHR$(9)) THEN
    IxErr$ = "bad key char" : EXIT FUNCTION
  ENDIF
  IxKeyOk% = 1
END FUNCTION

' Insert or update key -> offset. Returns 1 ok, 0 error (IxErr$)
FUNCTION IxPut%(k$, off%)
  LOCAL i%, j%
  IF IxKeyOk%(k$) = 0 THEN EXIT FUNCTION
  i% = IxBound%(IxK$(), IxN%, k$, 0)
  IF i% < IxN% THEN
    IF IxK$(i%) = k$ THEN IxO%(i%) = off% : IxPut% = 1 : EXIT FUNCTION
  ENDIF
  IF IxN% >= IX_MAX THEN IxErr$ = "index full" : EXIT FUNCTION
  FOR j% = IxN% TO i% + 1 STEP -1
    IxK$(j%) = IxK$(j% - 1) : IxO%(j%) = IxO%(j% - 1)
  NEXT
  IxK$(i%) = k$ : IxO%(i%) = off% : INC IxN%
  IxPut% = 1
END FUNCTION

' Remove key. Returns 1 if it existed
FUNCTION IxRemove%(k$)
  LOCAL i% = IxBound%(IxK$(), IxN%, k$, 0), j%
  IF i% >= IxN% THEN EXIT FUNCTION
  IF IxK$(i%) <> k$ THEN EXIT FUNCTION
  FOR j% = i% TO IxN% - 2
    IxK$(j%) = IxK$(j% + 1) : IxO%(j%) = IxO%(j% + 1)
  NEXT
  INC IxN%, -1
  IxRemove% = 1
END FUNCTION

' Exact range on _id for op$ (= < <= > >=). Rows lo%..hi%-1.
SUB IxRange op$, k$, lo%, hi%
  lo% = 0 : hi% = IxN%
  SELECT CASE op$
    CASE "="  : lo% = IxBound%(IxK$(), IxN%, k$, 0) : hi% = IxBound%(IxK$(), IxN%, k$, 1)
    CASE ">"  : lo% = IxBound%(IxK$(), IxN%, k$, 1)
    CASE ">=" : lo% = IxBound%(IxK$(), IxN%, k$, 0)
    CASE "<"  : hi% = IxBound%(IxK$(), IxN%, k$, 0)
    CASE "<=" : hi% = IxBound%(IxK$(), IxN%, k$, 1)
    CASE ELSE : lo% = -1 : hi% = -1
  END SELECT
END SUB

' ---------- secondary indexes ----------------------------------------

FUNCTION SxSlot%(fn$)
  LOCAL s%
  SxSlot% = -1
  FOR s% = 0 TO SX_SLOTS - 1
    IF SxF$(s%) = fn$ AND fn$ <> "" THEN SxSlot% = s% : EXIT FUNCTION
  NEXT
END FUNCTION

' Sortable, lossy key: slot char + "N"/"S" + 11-char value.
' Numbers map to floor(n) + 5e10, zero padded, clamped to +-4.9e10.
FUNCTION SxEnc$(s%, v$, t%)
  LOCAL n!, e%
  IF t% = 2 AND RcIsNum%(v$) THEN
    n! = VAL(v$)
    IF n! > 4.9E10 THEN n! = 4.9E10
    IF n! < -4.9E10 THEN n! = -4.9E10
    e% = INT(n!) + 50000000000
    SxEnc$ = CHR$(65 + s%) + "N" + RIGHT$("00000000000" + STR$(e%), SX_PW)
  ELSE
    SxEnc$ = CHR$(65 + s%) + "S" + LEFT$(v$, SX_PW)
  ENDIF
END FUNCTION

FUNCTION SxAdd%(s%, v$, t%, off%)
  LOCAL k$ = SxEnc$(s%, v$, t%), i%, j%
  IF SxN% >= SX_MAX THEN IxErr$ = "sec index full" : EXIT FUNCTION
  i% = IxBound%(SxV$(), SxN%, k$, 1)
  FOR j% = SxN% TO i% + 1 STEP -1
    SxV$(j%) = SxV$(j% - 1) : SxO%(j%) = SxO%(j% - 1)
  NEXT
  SxV$(i%) = k$ : SxO%(i%) = off% : INC SxN%
  SxAdd% = 1
END FUNCTION

FUNCTION SxRemove%(s%, v$, t%, off%)
  LOCAL k$ = SxEnc$(s%, v$, t%), i%, j%
  i% = IxBound%(SxV$(), SxN%, k$, 0)
  DO WHILE i% < SxN%
    IF SxV$(i%) <> k$ THEN EXIT DO
    IF SxO%(i%) = off% THEN
      FOR j% = i% TO SxN% - 2
        SxV$(j%) = SxV$(j% + 1) : SxO%(j%) = SxO%(j% + 1)
      NEXT
      INC SxN%, -1 : SxRemove% = 1 : EXIT FUNCTION
    ENDIF
    INC i%
  LOOP
END FUNCTION

' Candidate rows lo%..hi%-1 in SxO%() for "field op v$".
' op$: = < <= > >= LIKE (prefix, v$ without %). lo% = -1: unusable.
' Keys are lossy: the caller MUST re-test each fetched record.
SUB SxRange s%, op$, v$, t%, lo%, hi%
  LOCAL k$, p$, rs%, re%
  k$ = SxEnc$(s%, v$, t%)
  p$ = LEFT$(k$, 2)
  rs% = IxBound%(SxV$(), SxN%, p$, 0)
  re% = IxBound%(SxV$(), SxN%, LEFT$(p$, 1) + CHR$(ASC(MID$(p$, 2)) + 1), 0)
  lo% = rs% : hi% = re%
  SELECT CASE op$
    CASE "="        : lo% = IxBound%(SxV$(), SxN%, k$, 0) : hi% = IxBound%(SxV$(), SxN%, k$, 1)
    CASE ">", ">="  : lo% = IxBound%(SxV$(), SxN%, k$, 0)
    CASE "<", "<="  : hi% = IxBound%(SxV$(), SxN%, k$, 1)
    CASE "LIKE"
      k$ = SxEnc$(s%, v$, 1)
      lo% = IxBound%(SxV$(), SxN%, k$, 0)
      hi% = IxBound%(SxV$(), SxN%, k$ + STRING$(SX_PW, 255), 1)
    CASE ELSE : lo% = -1 : hi% = -1
  END SELECT
END SUB

' ---------- maintenance ----------------------------------------------

' Keep the index in step after the storage engine appends rec$ at
' off%. old$ = previous version of the record ("" if new).
FUNCTION IxApply%(rec$, off%, old$)
  LOCAL id$, v$, s%, oo%, ft%
  id$ = RcGet$(rec$, "_id")
  IF RcFound% = 0 THEN IxErr$ = "no _id" : EXIT FUNCTION
  IF IxKeyOk%(id$) = 0 THEN EXIT FUNCTION
  oo% = IxGet%(id$)
  IF oo% > 0 AND old$ <> "" THEN
    FOR s% = 0 TO SX_SLOTS - 1
      IF SxF$(s%) <> "" THEN
        v$ = RcGet$(old$, SxF$(s%)) : ft% = RcT%
        IF RcFound% THEN v$ = STR$(SxRemove%(s%, v$, ft%, oo%))
      ENDIF
    NEXT
  ENDIF
  IF RcIsDel%(rec$) THEN v$ = STR$(IxRemove%(id$)) : IxApply% = 1 : EXIT FUNCTION
  IF IxPut%(id$, off%) = 0 THEN EXIT FUNCTION
  FOR s% = 0 TO SX_SLOTS - 1
    IF SxF$(s%) <> "" THEN
      v$ = RcGet$(rec$, SxF$(s%)) : ft% = RcT%
      IF RcFound% THEN
        IF SxAdd%(s%, v$, ft%, off%) = 0 THEN EXIT FUNCTION
      ENDIF
    ENDIF
  NEXT
  IxApply% = 1
END FUNCTION

' Read one line from open file #fnum%. A line over 255 chars (or one
' that grows past it when LINE INPUT expands TABs) would be a fatal
' error, so it is trapped: returns CHR$(1) and sets IxLong% = 1.
FUNCTION IxLine$(fnum%)
  LOCAL r$ = CHR$(1)
  IxLong% = 0
  ON ERROR SKIP 1
  LINE INPUT #fnum%, r$
  IF r$ = CHR$(1) THEN IxLong% = 1
  IxLine$ = r$
END FUNCTION

' Read the line at offset off% ("" if it is unreadable)
FUNCTION IxReadAt$(fnum%, off%)
  LOCAL r$
  SEEK #fnum%, off%
  r$ = IxLine$(fnum%)
  IF IxLong% THEN r$ = ""
  IxReadAt$ = r$
END FUNCTION

' Sort IxK$/IxO% and merge duplicates: the highest |offset| (latest
' line) wins; tombstones (negative offsets) are then dropped.
SUB IxCompact
  LOCAL ix%(IX_MAX - 1), tmp%(IX_MAX - 1), i%, j%, w%, b%
  IF IxN% = 0 THEN EXIT SUB
  SORT IxK$(), ix%(), , 0, IxN%
  FOR i% = 0 TO IxN% - 1 : tmp%(i%) = IxO%(ix%(i%)) : NEXT
  i% = 0 : w% = 0
  DO WHILE i% < IxN%
    j% = i% : b% = tmp%(i%)
    DO WHILE j% + 1 < IxN%
      IF IxK$(j% + 1) <> IxK$(i%) THEN EXIT DO
      INC j%
      IF ABS(tmp%(j%)) > ABS(b%) THEN b% = tmp%(j%)
    LOOP
    IF b% > 0 THEN IxK$(w%) = IxK$(i%) : IxO%(w%) = b% : INC w%
    i% = j% + 1
  LOOP
  IxN% = w%
END SUB

' Scan open file #fnum% from offset from% and merge into the primary
' index. Bad/torn lines are skipped and counted in IxBad%.
FUNCTION IxScan%(fnum%, from%)
  LOCAL r$, id$, off%, frag% = 0
  IF from% > LOF(#fnum%) THEN IxScan% = 1 : EXIT FUNCTION
  SEEK #fnum%, from%
  DO WHILE NOT EOF(#fnum%)
    off% = LOC(#fnum%)
    r$ = IxLine$(fnum%)
    ' after an over-long line, its leftover tail comes back as the
    ' next "line": discard it too, it may look like a valid record
    IF IxLong% THEN
      INC IxBad% : frag% = 1
    ELSEIF frag% THEN
      frag% = 0
    ELSEIF RcCheck%(r$) < 0 THEN
      IF LEN(r$) > 0 THEN INC IxBad%
    ELSE
      id$ = RcGet$(r$, "_id")
      IF RcFound% AND LEN(id$) > 0 AND LEN(id$) <= IX_KLEN THEN
        IF IxN% >= IX_MAX THEN IxCompact
        IF IxN% >= IX_MAX THEN IxErr$ = "index full" : EXIT FUNCTION
        IxK$(IxN%) = id$
        IF RcIsDel%(r$) THEN IxO%(IxN%) = -off% ELSE IxO%(IxN%) = off%
        INC IxN%
      ELSE
        INC IxBad%
      ENDIF
    ENDIF
  LOOP
  IxCompact
  IxScan% = 1
END FUNCTION

' Rebuild every secondary slot from the records in open file #fnum%
FUNCTION SxRebuild%(fnum%)
  LOCAL ix%(SX_MAX - 1), tmp%(SX_MAX - 1), i%, s%, r$, v$
  SxN% = 0
  FOR i% = 0 TO IxN% - 1
    r$ = IxReadAt$(fnum%, IxO%(i%))
    FOR s% = 0 TO SX_SLOTS - 1
      IF SxF$(s%) <> "" THEN
        v$ = RcGet$(r$, SxF$(s%))
        IF RcFound% THEN
          IF SxN% >= SX_MAX THEN IxErr$ = "sec index full" : EXIT FUNCTION
          SxV$(SxN%) = SxEnc$(s%, v$, RcT%) : SxO%(SxN%) = IxO%(i%)
          INC SxN%
        ENDIF
      ENDIF
    NEXT
  NEXT
  IF SxN% > 0 THEN
    SORT SxV$(), ix%(), , 0, SxN%
    FOR i% = 0 TO SxN% - 1 : tmp%(i%) = SxO%(ix%(i%)) : NEXT
    FOR i% = 0 TO SxN% - 1 : SxO%(i%) = tmp%(i%) : NEXT
  ENDIF
  SxRebuild% = 1
END FUNCTION

' Save the primary index. Line 1: "IX1," + data-file length, then
' "offset,key" lines. (Not TAB: LINE INPUT turns TABs into spaces.)
FUNCTION IxSave%(ipath$, fnum%, dlen%)
  LOCAL i%
  OPEN ipath$ FOR OUTPUT AS #fnum%
  PRINT #fnum%, "IX1," + STR$(dlen%)
  FOR i% = 0 TO IxN% - 1
    PRINT #fnum%, STR$(IxO%(i%)) + "," + IxK$(i%)
  NEXT
  CLOSE #fnum%
  IxSave% = 1
END FUNCTION

' Load a saved index; returns the data length it covers, or -1
FUNCTION IxLoad%(ipath$, fnum%)
  LOCAL r$, p%, k$, dl%, ixcorrupt% = 0
  IxLoad% = -1 : IxN% = 0
  IF DIR$(ipath$, FILE) = "" THEN EXIT FUNCTION
  OPEN ipath$ FOR INPUT AS #fnum%
  LINE INPUT #fnum%, r$
  IF LEFT$(r$, 4) = "IX1," THEN
    dl% = VAL(MID$(r$, 5))
    DO WHILE NOT EOF(#fnum%)
      LINE INPUT #fnum%, r$
      p% = INSTR(r$, ",") : k$ = MID$(r$, p% + 1)
      IF p% < 2 OR IxN% >= IX_MAX OR IxKeyOk%(k$) = 0 THEN ixcorrupt% = 1 : EXIT DO
      IF IxN% > 0 THEN
        IF k$ <= IxK$(IxN% - 1) THEN ixcorrupt% = 1 : EXIT DO
      ENDIF
      IxK$(IxN%) = k$ : IxO%(IxN%) = VAL(LEFT$(r$, p% - 1)) : INC IxN%
    LOOP
    IF ixcorrupt% THEN IxN% = 0 ELSE IxLoad% = dl%
  ENDIF
  CLOSE #fnum%
END FUNCTION

' Open a collection: use the saved index if valid, scan only the
' tail appended since, then rebuild secondary slots (set SxF$ first).
FUNCTION IxOpen%(dpath$, ipath$, fnum%)
  LOCAL dl%, ok%
  IxClear
  dl% = IxLoad%(ipath$, fnum%)
  OPEN dpath$ FOR INPUT AS #fnum%
  IF dl% < 0 OR dl% > LOF(#fnum%) THEN IxN% = 0 : dl% = 0
  ok% = IxScan%(fnum%, dl% + 1)
  IF ok% THEN ok% = SxRebuild%(fnum%)
  CLOSE #fnum%
  IxOpen% = ok%
END FUNCTION
