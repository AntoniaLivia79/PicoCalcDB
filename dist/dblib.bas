' =====================================================================
' dblib.bas - PicoCalc DB library (engine + public Db* API), merged from
' dbcore, dbstore, dbquery, dbexec and dbapi by build.py. See LIBRARY.md.
' Use:  #INCLUDE "dblib.bas"  near the top of your program, or load
' dblib_min.bas and type LIBRARY SAVE to keep it in flash for all programs.
' Contains no OPTION statements and no main code: put OPTION EXPLICIT /
' OPTION DEFAULT NONE in your own program, before the #INCLUDE.
' =====================================================================
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
FUNCTION RcSkip%(z_r$, z_i%)
  LOCAL z_j% = z_i%
  DO WHILE z_j% <= LEN(z_r$)
    IF ASC(MID$(z_r$, z_j%, 1)) > 32 THEN EXIT DO
    INC z_j%
  LOOP
  RcSkip% = z_j%
END FUNCTION

' Decode the JSON string whose opening quote is at i% into s$.
' Returns position after the closing quote, or -1 if malformed.
FUNCTION RcStr%(z_r$, z_i%, z_s$)
  LOCAL z_j% = z_i% + 1, z_q%, z_b%, z_c$, z_a%
  z_s$ = ""
  DO
    z_q% = INSTR(z_j%, z_r$, CHR$(34))
    IF z_q% = 0 THEN RcStr% = -1 : EXIT FUNCTION
    z_b% = INSTR(z_j%, z_r$, "\")
    IF z_b% = 0 OR z_b% > z_q% THEN
      z_s$ = z_s$ + MID$(z_r$, z_j%, z_q% - z_j%)
      RcStr% = z_q% + 1
      EXIT FUNCTION
    ENDIF
    z_s$ = z_s$ + MID$(z_r$, z_j%, z_b% - z_j%)
    z_c$ = MID$(z_r$, z_b% + 1, 1)
    z_j% = z_b% + 2
    SELECT CASE z_c$
      CASE "n" : z_s$ = z_s$ + CHR$(10)
      CASE "t" : z_s$ = z_s$ + CHR$(9)
      CASE "r" : z_s$ = z_s$ + CHR$(13)
      CASE "b" : z_s$ = z_s$ + CHR$(8)
      CASE "f" : z_s$ = z_s$ + CHR$(12)
      CASE "u"
        z_a% = VAL("&H" + MID$(z_r$, z_b% + 2, 4))
        IF z_a% > 255 THEN z_s$ = z_s$ + "?" ELSE z_s$ = z_s$ + CHR$(z_a%)
        z_j% = z_b% + 6
      CASE ELSE : z_s$ = z_s$ + z_c$   ' \" \\ \/
    END SELECT
  LOOP
END FUNCTION

' Skip a nested {...} or [...] starting at i%; returns pos after it
FUNCTION RcNest%(z_r$, z_i%)
  LOCAL z_j% = z_i%, z_d% = 0, z_c$, z_s$
  DO WHILE z_j% <= LEN(z_r$)
    z_c$ = MID$(z_r$, z_j%, 1)
    IF z_c$ = CHR$(34) THEN
      z_j% = RcStr%(z_r$, z_j%, z_s$)
      IF z_j% < 0 THEN EXIT DO
    ELSE
      IF z_c$ = "{" OR z_c$ = "[" THEN INC z_d%
      IF z_c$ = "}" OR z_c$ = "]" THEN INC z_d%, -1
      INC z_j%
      IF z_d% = 0 THEN RcNest% = z_j% : EXIT FUNCTION
    ENDIF
  LOOP
  RcNest% = -1
END FUNCTION

' Field iterator. Start with ip% = 1; pass back the returned value.
' Returns next position (>0) with k$, v$, t% filled in,
' 0 at end of record, -1 if the record is malformed or truncated.
FUNCTION RcNext%(z_r$, z_ip%, z_k$, z_v$, z_t%)
  LOCAL z_i%, z_e%, z_c$
  z_i% = RcSkip%(z_r$, z_ip%)
  z_c$ = MID$(z_r$, z_i%, 1)
  IF z_ip% = 1 THEN
    IF z_c$ <> "{" THEN RcNext% = -1 : EXIT FUNCTION
  ELSEIF z_c$ = "}" THEN
    RcNext% = 0 : EXIT FUNCTION
  ELSEIF z_c$ <> "," THEN
    RcNext% = -1 : EXIT FUNCTION
  ENDIF
  z_i% = RcSkip%(z_r$, z_i% + 1)
  z_c$ = MID$(z_r$, z_i%, 1)
  IF z_c$ = "}" AND z_ip% = 1 THEN RcNext% = 0 : EXIT FUNCTION
  IF z_c$ <> CHR$(34) THEN RcNext% = -1 : EXIT FUNCTION
  RcKS% = z_i%
  z_i% = RcStr%(z_r$, z_i%, z_k$)
  IF z_i% < 0 THEN RcNext% = -1 : EXIT FUNCTION
  z_i% = RcSkip%(z_r$, z_i%)
  IF MID$(z_r$, z_i%, 1) <> ":" THEN RcNext% = -1 : EXIT FUNCTION
  z_i% = RcSkip%(z_r$, z_i% + 1)
  RcVS% = z_i%
  z_c$ = MID$(z_r$, z_i%, 1)
  IF z_c$ = CHR$(34) THEN
    z_i% = RcStr%(z_r$, z_i%, z_v$) : z_t% = 1
  ELSEIF z_c$ = "{" OR z_c$ = "[" THEN
    z_i% = RcNest%(z_r$, z_i%) : z_t% = 3
    IF z_i% > 0 THEN z_v$ = MID$(z_r$, RcVS%, z_i% - RcVS%)
  ELSE
    z_e% = z_i%
    DO WHILE z_e% <= LEN(z_r$)
      z_c$ = MID$(z_r$, z_e%, 1)
      IF z_c$ = "," OR z_c$ = "}" OR ASC(z_c$) <= 32 THEN EXIT DO
      INC z_e%
    LOOP
    IF z_e% = z_i% THEN RcNext% = -1 : EXIT FUNCTION
    z_v$ = MID$(z_r$, z_i%, z_e% - z_i%) : z_t% = 2 : z_i% = z_e%
  ENDIF
  RcVE% = z_i%
  RcNext% = z_i%
END FUNCTION

' Value of field k$ ("" if absent; check RcFound% and RcT%)
FUNCTION RcGet$(z_r$, z_k$)
  LOCAL z_ip% = 1, z_fk$, z_fv$, z_ft%
  RcFound% = 0 : RcT% = 0 : RcErr$ = ""
  DO
    z_ip% = RcNext%(z_r$, z_ip%, z_fk$, z_fv$, z_ft%)
    IF z_ip% <= 0 THEN EXIT DO
    IF z_fk$ = z_k$ THEN
      RcFound% = 1 : RcT% = z_ft% : RcGet$ = z_fv$
      EXIT FUNCTION
    ENDIF
  LOOP
  IF z_ip% < 0 THEN RcErr$ = "bad record"
END FUNCTION

' Number of fields, or -1 if malformed (use to skip torn lines)
FUNCTION RcCheck%(z_r$)
  LOCAL z_ip% = 1, z_n% = 0, z_fk$, z_fv$, z_ft%
  DO
    z_ip% = RcNext%(z_r$, z_ip%, z_fk$, z_fv$, z_ft%)
    IF z_ip% <= 0 THEN EXIT DO
    INC z_n%
  LOOP
  IF z_ip% < 0 THEN RcCheck% = -1 ELSE RcCheck% = z_n%
END FUNCTION

' JSON-quote a string; "" + RcErr$ if the result would exceed 255
FUNCTION RcEnc$(z_s$)
  LOCAL z_i%, z_a%, z_o$, z_c$
  z_o$ = CHR$(34)
  FOR z_i% = 1 TO LEN(z_s$)
    z_a% = ASC(MID$(z_s$, z_i%, 1))
    SELECT CASE z_a%
      CASE 34 : z_c$ = "\" + CHR$(34)
      CASE 92 : z_c$ = "\\"
      CASE 10 : z_c$ = "\n"
      CASE 9  : z_c$ = "\t"
      CASE 13 : z_c$ = "\r"
      CASE IS < 32 : z_c$ = "\u00" + HEX$(z_a%, 2)
      CASE ELSE : z_c$ = CHR$(z_a%)
    END SELECT
    IF LEN(z_o$) + LEN(z_c$) > 254 THEN
      RcErr$ = "too long" : RcEnc$ = "" : EXIT FUNCTION
    ENDIF
    z_o$ = z_o$ + z_c$
  NEXT
  RcEnc$ = z_o$ + CHR$(34)
END FUNCTION

' 1 if s$ is a valid JSON number
FUNCTION RcIsNum%(z_s$)
  LOCAL z_i% = 1, z_n% = LEN(z_s$), z_d% = 0
  IF MID$(z_s$, 1, 1) = "-" THEN z_i% = 2
  DO WHILE z_i% <= z_n% AND INSTR("0123456789", MID$(z_s$, z_i%, 1)) > 0
    INC z_i% : INC z_d%
  LOOP
  IF z_d% = 0 THEN EXIT FUNCTION
  IF MID$(z_s$, z_i%, 1) = "." THEN
    INC z_i% : z_d% = 0
    DO WHILE z_i% <= z_n% AND INSTR("0123456789", MID$(z_s$, z_i%, 1)) > 0
      INC z_i% : INC z_d%
    LOOP
    IF z_d% = 0 THEN EXIT FUNCTION
  ENDIF
  IF UCASE$(MID$(z_s$, z_i%, 1)) = "E" THEN
    INC z_i% : z_d% = 0
    IF INSTR("+-", MID$(z_s$, z_i%, 1)) > 0 AND z_i% <= z_n% THEN INC z_i%
    DO WHILE z_i% <= z_n% AND INSTR("0123456789", MID$(z_s$, z_i%, 1)) > 0
      INC z_i% : INC z_d%
    LOOP
    IF z_d% = 0 THEN EXIT FUNCTION
  ENDIF
  RcIsNum% = (z_i% > z_n%)
END FUNCTION

' 1 if s$ may be stored unquoted (number, true, false, null)
FUNCTION RcLit%(z_s$)
  RcLit% = RcIsNum%(z_s$) OR z_s$ = "true" OR z_s$ = "false" OR z_s$ = "null"
END FUNCTION

' Set field k$ to v$. t%: 1 string, 2 literal, 3 raw JSON.
' Replaces in place, else appends. Returns "" + RcErr$ on failure.
FUNCTION RcSet$(z_r$, z_k$, z_v$, z_t%)
  LOCAL z_ev$, z_ek$, z_x$, z_p%, z_j%
  z_x$ = RcGet$(z_r$, z_k$)
  IF RcErr$ <> "" THEN EXIT FUNCTION
  IF z_t% = 1 THEN
    z_ev$ = RcEnc$(z_v$)
    IF z_ev$ = "" THEN EXIT FUNCTION
  ELSE
    IF z_t% = 2 AND RcLit%(z_v$) = 0 THEN RcErr$ = "bad literal" : EXIT FUNCTION
    z_ev$ = z_v$
  ENDIF
  IF RcFound% THEN
    IF LEN(z_r$) - (RcVE% - RcVS%) + LEN(z_ev$) > RC_MAXLEN THEN
      RcErr$ = "too long" : EXIT FUNCTION
    ENDIF
    RcSet$ = LEFT$(z_r$, RcVS% - 1) + z_ev$ + MID$(z_r$, RcVE%)
    EXIT FUNCTION
  ENDIF
  z_ek$ = RcEnc$(z_k$)
  IF z_ek$ = "" THEN EXIT FUNCTION
  z_p% = LEN(z_r$)
  DO WHILE z_p% > 1 AND MID$(z_r$, z_p%, 1) <> "}" : INC z_p%, -1 : LOOP
  z_j% = z_p% - 1
  DO WHILE z_j% > 1 AND ASC(MID$(z_r$, z_j%, 1)) <= 32 : INC z_j%, -1 : LOOP
  IF MID$(z_r$, z_j%, 1) <> "{" THEN z_ek$ = "," + z_ek$
  IF LEN(z_r$) + LEN(z_ek$) + 1 + LEN(z_ev$) > RC_MAXLEN THEN
    RcErr$ = "too long" : EXIT FUNCTION
  ENDIF
  RcSet$ = LEFT$(z_r$, z_j%) + z_ek$ + ":" + z_ev$ + MID$(z_r$, z_j% + 1)
END FUNCTION

' Remove field k$ (returns r$ unchanged if absent)
FUNCTION RcDel$(z_r$, z_k$)
  LOCAL z_x$, z_a%, z_b%, z_j%
  z_x$ = RcGet$(z_r$, z_k$)
  IF RcFound% = 0 THEN RcDel$ = z_r$ : EXIT FUNCTION
  z_a% = RcKS% : z_b% = RcVE%
  z_j% = z_a% - 1
  DO WHILE z_j% > 1 AND ASC(MID$(z_r$, z_j%, 1)) <= 32 : INC z_j%, -1 : LOOP
  IF MID$(z_r$, z_j%, 1) = "," THEN
    z_a% = z_j%
  ELSE
    z_j% = RcSkip%(z_r$, z_b%)
    IF MID$(z_r$, z_j%, 1) = "," THEN z_b% = RcSkip%(z_r$, z_j% + 1)
  ENDIF
  RcDel$ = LEFT$(z_r$, z_a% - 1) + MID$(z_r$, z_b%)
END FUNCTION

' New empty record with an _id
FUNCTION RcNew$(z_id$)
  RcNew$ = "{" + RcEnc$("_id") + ":" + RcEnc$(z_id$) + "}"
END FUNCTION

' 1 if r$ is a tombstone
FUNCTION RcIsDel%(z_r$)
  LOCAL z_x$
  IF INSTR(z_r$, CHR$(34) + "_del" + CHR$(34)) = 0 THEN EXIT FUNCTION
  z_x$ = RcGet$(z_r$, "_del")
  RcIsDel% = RcFound% AND z_x$ <> "0" AND z_x$ <> "false"
END FUNCTION

' =====================================================================
' INDEX MANAGER
' =====================================================================

' Binary search over a$(0..n%-1): first i with a$(i) >= k$
' (gt% = 0) or a$(i) > k$ (gt% = 1)
FUNCTION IxBound%(z_a$(), z_n%, z_k$, z_gt%)
  LOCAL z_lo% = 0, z_hi% = z_n%, z_m%
  DO WHILE z_lo% < z_hi%
    z_m% = (z_lo% + z_hi%) \ 2
    IF z_a$(z_m%) < z_k$ OR (z_gt% AND z_a$(z_m%) = z_k$) THEN
      z_lo% = z_m% + 1
    ELSE
      z_hi% = z_m%
    ENDIF
  LOOP
  IxBound% = z_lo%
END FUNCTION

SUB IxClear
  IxN% = 0 : SxN% = 0 : IxErr$ = "" : IxBad% = 0
END SUB

' Offset of record k$, or -1
FUNCTION IxGet%(z_k$)
  LOCAL z_i% = IxBound%(IxK$(), IxN%, z_k$, 0)
  IxGet% = -1
  IF z_i% < IxN% THEN
    IF IxK$(z_i%) = z_k$ THEN IxGet% = IxO%(z_i%)
  ENDIF
END FUNCTION

' 1 if k$ is usable as a primary key
FUNCTION IxKeyOk%(z_k$)
  IxKeyOk% = 0
  IF LEN(z_k$) = 0 OR LEN(z_k$) > IX_KLEN THEN IxErr$ = "bad key length" : EXIT FUNCTION
  IF INSTR(z_k$, CHR$(10)) OR INSTR(z_k$, CHR$(13)) OR INSTR(z_k$, CHR$(9)) THEN
    IxErr$ = "bad key char" : EXIT FUNCTION
  ENDIF
  IxKeyOk% = 1
END FUNCTION

' Insert or update key -> offset. Returns 1 ok, 0 error (IxErr$)
FUNCTION IxPut%(z_k$, z_off%)
  LOCAL z_i%, z_j%
  IF IxKeyOk%(z_k$) = 0 THEN EXIT FUNCTION
  z_i% = IxBound%(IxK$(), IxN%, z_k$, 0)
  IF z_i% < IxN% THEN
    IF IxK$(z_i%) = z_k$ THEN IxO%(z_i%) = z_off% : IxPut% = 1 : EXIT FUNCTION
  ENDIF
  IF IxN% >= IX_MAX THEN IxErr$ = "index full" : EXIT FUNCTION
  FOR z_j% = IxN% TO z_i% + 1 STEP -1
    IxK$(z_j%) = IxK$(z_j% - 1) : IxO%(z_j%) = IxO%(z_j% - 1)
  NEXT
  IxK$(z_i%) = z_k$ : IxO%(z_i%) = z_off% : INC IxN%
  IxPut% = 1
END FUNCTION

' Remove key. Returns 1 if it existed
FUNCTION IxRemove%(z_k$)
  LOCAL z_i% = IxBound%(IxK$(), IxN%, z_k$, 0), z_j%
  IF z_i% >= IxN% THEN EXIT FUNCTION
  IF IxK$(z_i%) <> z_k$ THEN EXIT FUNCTION
  FOR z_j% = z_i% TO IxN% - 2
    IxK$(z_j%) = IxK$(z_j% + 1) : IxO%(z_j%) = IxO%(z_j% + 1)
  NEXT
  INC IxN%, -1
  IxRemove% = 1
END FUNCTION

' Exact range on _id for op$ (= < <= > >=). Rows lo%..hi%-1.
SUB IxRange z_op$, z_k$, z_lo%, z_hi%
  z_lo% = 0 : z_hi% = IxN%
  SELECT CASE z_op$
    CASE "="  : z_lo% = IxBound%(IxK$(), IxN%, z_k$, 0) : z_hi% = IxBound%(IxK$(), IxN%, z_k$, 1)
    CASE ">"  : z_lo% = IxBound%(IxK$(), IxN%, z_k$, 1)
    CASE ">=" : z_lo% = IxBound%(IxK$(), IxN%, z_k$, 0)
    CASE "<"  : z_hi% = IxBound%(IxK$(), IxN%, z_k$, 0)
    CASE "<=" : z_hi% = IxBound%(IxK$(), IxN%, z_k$, 1)
    CASE ELSE : z_lo% = -1 : z_hi% = -1
  END SELECT
END SUB

' ---------- secondary indexes ----------------------------------------

FUNCTION SxSlot%(z_fn$)
  LOCAL z_s%
  SxSlot% = -1
  FOR z_s% = 0 TO SX_SLOTS - 1
    IF SxF$(z_s%) = z_fn$ AND z_fn$ <> "" THEN SxSlot% = z_s% : EXIT FUNCTION
  NEXT
END FUNCTION

' Sortable, lossy key: slot char + "N"/"S" + 11-char value.
' Numbers map to floor(n) + 5e10, zero padded, clamped to +-4.9e10.
FUNCTION SxEnc$(z_s%, z_v$, z_t%)
  LOCAL z_n!, z_e%
  IF z_t% = 2 AND RcIsNum%(z_v$) THEN
    z_n! = VAL(z_v$)
    IF z_n! > 4.9E10 THEN z_n! = 4.9E10
    IF z_n! < -4.9E10 THEN z_n! = -4.9E10
    z_e% = INT(z_n!) + 50000000000
    SxEnc$ = CHR$(65 + z_s%) + "N" + RIGHT$("00000000000" + STR$(z_e%), SX_PW)
  ELSE
    SxEnc$ = CHR$(65 + z_s%) + "S" + LEFT$(z_v$, SX_PW)
  ENDIF
END FUNCTION

FUNCTION SxAdd%(z_s%, z_v$, z_t%, z_off%)
  LOCAL z_k$ = SxEnc$(z_s%, z_v$, z_t%), z_i%, z_j%
  IF SxN% >= SX_MAX THEN IxErr$ = "sec index full" : EXIT FUNCTION
  z_i% = IxBound%(SxV$(), SxN%, z_k$, 1)
  FOR z_j% = SxN% TO z_i% + 1 STEP -1
    SxV$(z_j%) = SxV$(z_j% - 1) : SxO%(z_j%) = SxO%(z_j% - 1)
  NEXT
  SxV$(z_i%) = z_k$ : SxO%(z_i%) = z_off% : INC SxN%
  SxAdd% = 1
END FUNCTION

FUNCTION SxRemove%(z_s%, z_v$, z_t%, z_off%)
  LOCAL z_k$ = SxEnc$(z_s%, z_v$, z_t%), z_i%, z_j%
  z_i% = IxBound%(SxV$(), SxN%, z_k$, 0)
  DO WHILE z_i% < SxN%
    IF SxV$(z_i%) <> z_k$ THEN EXIT DO
    IF SxO%(z_i%) = z_off% THEN
      FOR z_j% = z_i% TO SxN% - 2
        SxV$(z_j%) = SxV$(z_j% + 1) : SxO%(z_j%) = SxO%(z_j% + 1)
      NEXT
      INC SxN%, -1 : SxRemove% = 1 : EXIT FUNCTION
    ENDIF
    INC z_i%
  LOOP
END FUNCTION

' Candidate rows lo%..hi%-1 in SxO%() for "field op v$".
' op$: = < <= > >= LIKE (prefix, v$ without %). lo% = -1: unusable.
' Keys are lossy: the caller MUST re-test each fetched record.
SUB SxRange z_s%, z_op$, z_v$, z_t%, z_lo%, z_hi%
  LOCAL z_k$, z_p$, z_rs%, z_re%
  z_k$ = SxEnc$(z_s%, z_v$, z_t%)
  z_p$ = LEFT$(z_k$, 2)
  z_rs% = IxBound%(SxV$(), SxN%, z_p$, 0)
  z_re% = IxBound%(SxV$(), SxN%, LEFT$(z_p$, 1) + CHR$(ASC(MID$(z_p$, 2)) + 1), 0)
  z_lo% = z_rs% : z_hi% = z_re%
  SELECT CASE z_op$
    CASE "="        : z_lo% = IxBound%(SxV$(), SxN%, z_k$, 0) : z_hi% = IxBound%(SxV$(), SxN%, z_k$, 1)
    CASE ">", ">="  : z_lo% = IxBound%(SxV$(), SxN%, z_k$, 0)
    CASE "<", "<="  : z_hi% = IxBound%(SxV$(), SxN%, z_k$, 1)
    CASE "LIKE"
      z_k$ = SxEnc$(z_s%, z_v$, 1)
      z_lo% = IxBound%(SxV$(), SxN%, z_k$, 0)
      z_hi% = IxBound%(SxV$(), SxN%, z_k$ + STRING$(SX_PW, 255), 1)
    CASE ELSE : z_lo% = -1 : z_hi% = -1
  END SELECT
END SUB

' ---------- maintenance ----------------------------------------------

' Keep the index in step after the storage engine appends rec$ at
' off%. old$ = previous version of the record ("" if new).
FUNCTION IxApply%(z_rec$, z_off%, z_old$)
  LOCAL z_id$, z_v$, z_s%, z_oo%, z_ft%
  z_id$ = RcGet$(z_rec$, "_id")
  IF RcFound% = 0 THEN IxErr$ = "no _id" : EXIT FUNCTION
  IF IxKeyOk%(z_id$) = 0 THEN EXIT FUNCTION
  z_oo% = IxGet%(z_id$)
  IF z_oo% > 0 AND z_old$ <> "" THEN
    FOR z_s% = 0 TO SX_SLOTS - 1
      IF SxF$(z_s%) <> "" THEN
        z_v$ = RcGet$(z_old$, SxF$(z_s%)) : z_ft% = RcT%
        IF RcFound% THEN z_v$ = STR$(SxRemove%(z_s%, z_v$, z_ft%, z_oo%))
      ENDIF
    NEXT
  ENDIF
  IF RcIsDel%(z_rec$) THEN z_v$ = STR$(IxRemove%(z_id$)) : IxApply% = 1 : EXIT FUNCTION
  IF IxPut%(z_id$, z_off%) = 0 THEN EXIT FUNCTION
  FOR z_s% = 0 TO SX_SLOTS - 1
    IF SxF$(z_s%) <> "" THEN
      z_v$ = RcGet$(z_rec$, SxF$(z_s%)) : z_ft% = RcT%
      IF RcFound% THEN
        IF SxAdd%(z_s%, z_v$, z_ft%, z_off%) = 0 THEN EXIT FUNCTION
      ENDIF
    ENDIF
  NEXT
  IxApply% = 1
END FUNCTION

' Read one line from open file #fnum%. A line over 255 chars (or one
' that grows past it when LINE INPUT expands TABs) would be a fatal
' error, so it is trapped: returns CHR$(1) and sets IxLong% = 1.
FUNCTION IxLine$(z_fnum%)
  LOCAL z_r$ = CHR$(1)
  IxLong% = 0
  ON ERROR SKIP 1
  LINE INPUT #z_fnum%, z_r$
  IF z_r$ = CHR$(1) THEN IxLong% = 1
  IxLine$ = z_r$
END FUNCTION

' Read the line at offset off% ("" if it is unreadable)
FUNCTION IxReadAt$(z_fnum%, z_off%)
  LOCAL z_r$
  SEEK #z_fnum%, z_off%
  z_r$ = IxLine$(z_fnum%)
  IF IxLong% THEN z_r$ = ""
  IxReadAt$ = z_r$
END FUNCTION

' Sort IxK$/IxO% and merge duplicates: the highest |offset| (latest
' line) wins; tombstones (negative offsets) are then dropped.
SUB IxCompact
  LOCAL z_ix%(IX_MAX - 1), z_tmp%(IX_MAX - 1), z_i%, z_j%, z_w%, z_b%
  IF IxN% = 0 THEN EXIT SUB
  SORT IxK$(), z_ix%(), , 0, IxN%
  FOR z_i% = 0 TO IxN% - 1 : z_tmp%(z_i%) = IxO%(z_ix%(z_i%)) : NEXT
  z_i% = 0 : z_w% = 0
  DO WHILE z_i% < IxN%
    z_j% = z_i% : z_b% = z_tmp%(z_i%)
    DO WHILE z_j% + 1 < IxN%
      IF IxK$(z_j% + 1) <> IxK$(z_i%) THEN EXIT DO
      INC z_j%
      IF ABS(z_tmp%(z_j%)) > ABS(z_b%) THEN z_b% = z_tmp%(z_j%)
    LOOP
    IF z_b% > 0 THEN IxK$(z_w%) = IxK$(z_i%) : IxO%(z_w%) = z_b% : INC z_w%
    z_i% = z_j% + 1
  LOOP
  IxN% = z_w%
END SUB

' Scan open file #fnum% from offset from% and merge into the primary
' index. Bad/torn lines are skipped and counted in IxBad%.
FUNCTION IxScan%(z_fnum%, z_from%)
  LOCAL z_r$, z_id$, z_off%, z_frag% = 0
  IF z_from% > LOF(#z_fnum%) THEN IxScan% = 1 : EXIT FUNCTION
  SEEK #z_fnum%, z_from%
  DO WHILE NOT EOF(#z_fnum%)
    z_off% = LOC(#z_fnum%)
    z_r$ = IxLine$(z_fnum%)
    ' after an over-long line, its leftover tail comes back as the
    ' next "line": discard it too, it may look like a valid record
    IF IxLong% THEN
      INC IxBad% : z_frag% = 1
    ELSEIF z_frag% THEN
      z_frag% = 0
    ELSEIF RcCheck%(z_r$) < 0 THEN
      IF LEN(z_r$) > 0 THEN INC IxBad%
    ELSE
      z_id$ = RcGet$(z_r$, "_id")
      IF RcFound% AND LEN(z_id$) > 0 AND LEN(z_id$) <= IX_KLEN THEN
        IF IxN% >= IX_MAX THEN IxCompact
        IF IxN% >= IX_MAX THEN IxErr$ = "index full" : EXIT FUNCTION
        IxK$(IxN%) = z_id$
        IF RcIsDel%(z_r$) THEN IxO%(IxN%) = -z_off% ELSE IxO%(IxN%) = z_off%
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
FUNCTION SxRebuild%(z_fnum%)
  LOCAL z_ix%(SX_MAX - 1), z_tmp%(SX_MAX - 1), z_i%, z_s%, z_r$, z_v$
  SxN% = 0
  FOR z_i% = 0 TO IxN% - 1
    z_r$ = IxReadAt$(z_fnum%, IxO%(z_i%))
    FOR z_s% = 0 TO SX_SLOTS - 1
      IF SxF$(z_s%) <> "" THEN
        z_v$ = RcGet$(z_r$, SxF$(z_s%))
        IF RcFound% THEN
          IF SxN% >= SX_MAX THEN IxErr$ = "sec index full" : EXIT FUNCTION
          SxV$(SxN%) = SxEnc$(z_s%, z_v$, RcT%) : SxO%(SxN%) = IxO%(z_i%)
          INC SxN%
        ENDIF
      ENDIF
    NEXT
  NEXT
  IF SxN% > 0 THEN
    SORT SxV$(), z_ix%(), , 0, SxN%
    FOR z_i% = 0 TO SxN% - 1 : z_tmp%(z_i%) = SxO%(z_ix%(z_i%)) : NEXT
    FOR z_i% = 0 TO SxN% - 1 : SxO%(z_i%) = z_tmp%(z_i%) : NEXT
  ENDIF
  SxRebuild% = 1
END FUNCTION

' Save the primary index. Line 1: "IX1," + data-file length, then
' "offset,key" lines. (Not TAB: LINE INPUT turns TABs into spaces.)
FUNCTION IxSave%(z_ipath$, z_fnum%, z_dlen%)
  LOCAL z_i%
  OPEN z_ipath$ FOR OUTPUT AS #z_fnum%
  PRINT #z_fnum%, "IX1," + STR$(z_dlen%)
  FOR z_i% = 0 TO IxN% - 1
    PRINT #z_fnum%, STR$(IxO%(z_i%)) + "," + IxK$(z_i%)
  NEXT
  CLOSE #z_fnum%
  IxSave% = 1
END FUNCTION

' Load a saved index; returns the data length it covers, or -1
FUNCTION IxLoad%(z_ipath$, z_fnum%)
  LOCAL z_r$, z_p%, z_k$, z_dl%, z_ixcorrupt% = 0
  IxLoad% = -1 : IxN% = 0
  IF DIR$(z_ipath$, FILE) = "" THEN EXIT FUNCTION
  OPEN z_ipath$ FOR INPUT AS #z_fnum%
  LINE INPUT #z_fnum%, z_r$
  IF LEFT$(z_r$, 4) = "IX1," THEN
    z_dl% = VAL(MID$(z_r$, 5))
    DO WHILE NOT EOF(#z_fnum%)
      LINE INPUT #z_fnum%, z_r$
      z_p% = INSTR(z_r$, ",") : z_k$ = MID$(z_r$, z_p% + 1)
      IF z_p% < 2 OR IxN% >= IX_MAX OR IxKeyOk%(z_k$) = 0 THEN z_ixcorrupt% = 1 : EXIT DO
      IF IxN% > 0 THEN
        IF z_k$ <= IxK$(IxN% - 1) THEN z_ixcorrupt% = 1 : EXIT DO
      ENDIF
      IxK$(IxN%) = z_k$ : IxO%(IxN%) = VAL(LEFT$(z_r$, z_p% - 1)) : INC IxN%
    LOOP
    IF z_ixcorrupt% THEN IxN% = 0 ELSE IxLoad% = z_dl%
  ENDIF
  CLOSE #z_fnum%
END FUNCTION

' Open a collection: use the saved index if valid, scan only the
' tail appended since, then rebuild secondary slots (set SxF$ first).
FUNCTION IxOpen%(z_dpath$, z_ipath$, z_fnum%)
  LOCAL z_dl%, z_ok%
  IxClear
  z_dl% = IxLoad%(z_ipath$, z_fnum%)
  OPEN z_dpath$ FOR INPUT AS #z_fnum%
  IF z_dl% < 0 OR z_dl% > LOF(#z_fnum%) THEN IxN% = 0 : z_dl% = 0
  z_ok% = IxScan%(z_fnum%, z_dl% + 1)
  IF z_ok% THEN z_ok% = SxRebuild%(z_fnum%)
  CLOSE #z_fnum%
  IxOpen% = z_ok%
END FUNCTION

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

SUB StWarnAdd z_m$
  IF StWarn$ <> "" THEN StWarn$ = StWarn$ + "; "
  StWarn$ = StWarn$ + z_m$
END SUB

FUNCTION StPath$(z_ext$)
  StPath$ = StDir$ + StCol$ + z_ext$
END FUNCTION

FUNCTION StExists%(z_p$)
  StExists% = (DIR$(z_p$, FILE) <> "")
END FUNCTION

SUB StKill z_p$
  IF StExists%(z_p$) THEN KILL z_p$
END SUB

FUNCTION StNameOk%(z_n$)
  LOCAL z_i%, z_c$
  StNameOk% = 0
  IF LEN(z_n$) = 0 OR LEN(z_n$) > 16 THEN StErr$ = "bad name" : EXIT FUNCTION
  FOR z_i% = 1 TO LEN(z_n$)
    z_c$ = UCASE$(MID$(z_n$, z_i%, 1))
    IF INSTR("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_", z_c$) = 0 THEN
      StErr$ = "bad name" : EXIT FUNCTION
    ENDIF
  NEXT
  StNameOk% = 1
END FUNCTION

' ---------------- catalog --------------------------------------------

' Fill StCat$() with collection names, sorted. Returns the count.
FUNCTION StList%()
  LOCAL z_f$
  StCatN% = 0
  z_f$ = DIR$(StDir$ + "*.jsonl", FILE)
  DO WHILE z_f$ <> "" AND StCatN% < ST_CATMAX
    IF LEN(z_f$) <= 22 THEN
      StCat$(StCatN%) = LEFT$(z_f$, LEN(z_f$) - 6) : INC StCatN%
    ENDIF
    z_f$ = DIR$()
  LOOP
  IF StCatN% > 1 THEN SORT StCat$(), , , 0, StCatN%
  StList% = StCatN%
END FUNCTION

FUNCTION StCreate%(z_n$)
  LOCAL z_sv$ = StCol$
  StErr$ = ""
  IF StNameOk%(z_n$) = 0 THEN EXIT FUNCTION
  IF StExists%(StDir$ + z_n$ + ".jsonl") THEN StErr$ = "exists" : EXIT FUNCTION
  IF z_sv$ <> "" THEN StClose
  OPEN StDir$ + z_n$ + ".jsonl" FOR OUTPUT AS #ST_TMP : CLOSE #ST_TMP
  StCol$ = z_n$ : MtClear : MtSave : StCol$ = ""
  StCreate% = 1
  IF z_sv$ <> "" THEN StCreate% = StOpen%(z_sv$)
END FUNCTION

FUNCTION StDrop%(z_n$)
  StErr$ = ""
  IF StNameOk%(z_n$) = 0 THEN EXIT FUNCTION
  IF StExists%(StDir$ + z_n$ + ".jsonl") = 0 THEN StErr$ = "no such collection" : EXIT FUNCTION
  IF z_n$ = StCol$ THEN StRdClose : StCol$ = "" : IxClear
  StKill StDir$ + z_n$ + ".jsonl"
  StKill StDir$ + z_n$ + ".idx"
  StKill StDir$ + z_n$ + ".meta"
  StKill StDir$ + z_n$ + ".vtmp"
  StDrop% = 1
END FUNCTION

' ---------------- metadata -------------------------------------------

SUB MtClear
  LOCAL z_s%
  MtN% = 0 : MtSeq% = 0 : MtDead% = 0 : MtDirty% = 0
  MtUser$ = "{" + CHR$(34) + "_id" + CHR$(34) + ":" + CHR$(34) + "@user" + CHR$(34) + "}"
  FOR z_s% = 0 TO SX_SLOTS - 1 : SxF$(z_s%) = "" : NEXT
END SUB

SUB MtLoad
  LOCAL z_r$, z_id$, z_v$, z_s%
  MtClear
  IF StExists%(StPath$(".meta")) = 0 THEN MtDirty% = 1 : EXIT SUB
  OPEN StPath$(".meta") FOR INPUT AS #ST_TMP
  DO WHILE NOT EOF(#ST_TMP)
    LINE INPUT #ST_TMP, z_r$
    z_id$ = RcGet$(z_r$, "_id")
    IF z_id$ = "@" THEN
      MtSeq% = VAL(RcGet$(z_r$, "seq")) : MtDead% = VAL(RcGet$(z_r$, "dead"))
      FOR z_s% = 0 TO SX_SLOTS - 1
        z_v$ = RcGet$(z_r$, "i" + STR$(z_s%))
        IF RcFound% THEN SxF$(z_s%) = z_v$
      NEXT
    ELSEIF z_id$ = "@user" THEN
      MtUser$ = z_r$
    ELSEIF z_id$ <> "" AND LEFT$(z_id$, 1) <> "@" AND MtN% < MT_MAX THEN
      MtF$(MtN%) = z_id$ : MtT$(MtN%) = LEFT$(RcGet$(z_r$, "t") + "X", 1) : INC MtN%
    ENDIF
  LOOP
  CLOSE #ST_TMP
END SUB

SUB MtSave
  LOCAL z_r$, z_i%
  z_r$ = RcNew$("@")
  z_r$ = RcSet$(z_r$, "seq", STR$(MtSeq%), 2)
  z_r$ = RcSet$(z_r$, "dead", STR$(MtDead%), 2)
  FOR z_i% = 0 TO SX_SLOTS - 1
    IF SxF$(z_i%) <> "" THEN z_r$ = RcSet$(z_r$, "i" + STR$(z_i%), SxF$(z_i%), 1)
  NEXT
  OPEN StPath$(".meta") FOR OUTPUT AS #ST_TMP
  PRINT #ST_TMP, z_r$
  IF RcCheck%(MtUser$) > 1 THEN PRINT #ST_TMP, MtUser$
  FOR z_i% = 0 TO MtN% - 1
    PRINT #ST_TMP, RcSet$(RcNew$(MtF$(z_i%)), "t", MtT$(z_i%), 1)
  NEXT
  CLOSE #ST_TMP
  MtDirty% = 0
END SUB

' Record the fields and value types seen in rec$
SUB MtNote z_rec$
  LOCAL z_ip% = 1, z_k$, z_v$, z_t%, z_ty$, z_i%, z_j%
  DO
    z_ip% = RcNext%(z_rec$, z_ip%, z_k$, z_v$, z_t%)
    IF z_ip% <= 0 THEN EXIT DO
    IF LEFT$(z_k$, 1) <> "_" AND LEFT$(z_k$, 1) <> "@" AND LEN(z_k$) <= 24 THEN
      IF z_t% = 1 THEN
        z_ty$ = "S"
      ELSEIF z_t% = 3 THEN
        z_ty$ = "O"
      ELSEIF RcIsNum%(z_v$) THEN
        z_ty$ = "N"
      ELSE
        z_ty$ = "L"
      ENDIF
      z_j% = -1
      FOR z_i% = 0 TO MtN% - 1
        IF MtF$(z_i%) = z_k$ THEN z_j% = z_i% : EXIT FOR
      NEXT
      IF z_j% < 0 THEN
        IF MtN% < MT_MAX THEN
          MtF$(MtN%) = z_k$ : MtT$(MtN%) = z_ty$ : INC MtN% : MtDirty% = 1
        ENDIF
      ELSEIF MtT$(z_j%) <> z_ty$ AND MtT$(z_j%) <> "X" THEN
        MtT$(z_j%) = "X" : MtDirty% = 1
      ENDIF
    ENDIF
  LOOP
END SUB

' ---------------- open / close ---------------------------------------

SUB StRdClose
  IF StRdOpen% THEN CLOSE #ST_RD : StRdOpen% = 0
END SUB

' Read the line at offset off% of the open collection
FUNCTION StRead$(z_off%)
  IF StRdOpen% = 0 THEN
    OPEN StPath$(".jsonl") FOR INPUT AS #ST_RD : StRdOpen% = 1
  ENDIF
  StRead$ = IxReadAt$(ST_RD, z_off%)
END FUNCTION

' Make sure the data file ends with a line break, so a torn last
' line (power loss mid-write) is not glued onto the next record.
SUB StFixTail
  LOCAL z_c$, z_n%
  OPEN StPath$(".jsonl") FOR INPUT AS #ST_TMP
  z_n% = LOF(#ST_TMP)
  IF z_n% > 0 THEN SEEK #ST_TMP, z_n% : z_c$ = INPUT$(1, #ST_TMP)
  CLOSE #ST_TMP
  IF z_n% > 0 AND z_c$ <> CHR$(10) THEN
    OPEN StPath$(".jsonl") FOR APPEND AS #ST_TMP : PRINT #ST_TMP, "" : CLOSE #ST_TMP
    StWarnAdd "repaired torn last line"
  ENDIF
END SUB

' Spot-check a loaded index against the file (catches external edits)
FUNCTION StVerify%()
  LOCAL z_i%, z_j%, z_r$
  StVerify% = 1
  FOR z_j% = 0 TO 7
    IF IxN% = 0 THEN EXIT FUNCTION
    z_i% = (IxN% - 1) * z_j% \ 7
    z_r$ = StRead$(IxO%(z_i%))
    IF RcGet$(z_r$, "_id") <> IxK$(z_i%) OR RcIsDel%(z_r$) THEN StVerify% = 0 : EXIT FUNCTION
  NEXT
END FUNCTION

FUNCTION StOpen%(z_n$)
  LOCAL z_ok%
  StErr$ = "" : StWarn$ = ""
  IF StNameOk%(z_n$) = 0 THEN EXIT FUNCTION
  IF StCol$ <> "" THEN StClose
  StCol$ = z_n$
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
  z_ok% = IxOpen%(StPath$(".jsonl"), StPath$(".idx"), ST_TMP)
  IF z_ok% THEN
    IF StVerify%() = 0 THEN
      StRdClose
      StKill StPath$(".idx")
      StWarnAdd "stale index rebuilt"
      z_ok% = IxOpen%(StPath$(".jsonl"), StPath$(".idx"), ST_TMP)
    ENDIF
  ENDIF
  IF z_ok% = 0 THEN StErr$ = IxErr$ : StRdClose : StCol$ = "" : IxClear : EXIT FUNCTION
  IF IxBad% > 0 THEN StWarnAdd STR$(IxBad%) + " bad line(s) skipped"
  StOpen% = 1
END FUNCTION

' Persist metadata and the primary index
SUB StFlush
  LOCAL z_n%
  IF StCol$ = "" THEN EXIT SUB
  StRdClose
  IF MtDirty% THEN MtSave
  OPEN StPath$(".jsonl") FOR INPUT AS #ST_TMP : z_n% = LOF(#ST_TMP) : CLOSE #ST_TMP
  z_n% = IxSave%(StPath$(".idx"), ST_TMP, z_n%)
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
FUNCTION StAt$(z_i%)
  IF z_i% >= 0 AND z_i% < IxN% THEN StAt$ = StRead$(IxO%(z_i%))
END FUNCTION

FUNCTION StFetch$(z_id$)
  LOCAL z_o% = IxGet%(z_id$)
  StErr$ = ""
  IF z_o% < 0 THEN StErr$ = "not found" ELSE StFetch$ = StRead$(z_o%)
END FUNCTION

' ---------------- writing --------------------------------------------

' Append one line; returns its offset
FUNCTION StAppend%(z_r$)
  StRdClose
  OPEN StPath$(".jsonl") FOR APPEND AS #ST_WR
  StAppend% = LOC(#ST_WR)
  PRINT #ST_WR, z_r$
  CLOSE #ST_WR
END FUNCTION

' Count secondary-index entries rec$ needs
FUNCTION StSxNeed%(z_rec$)
  LOCAL z_s%, z_v$
  FOR z_s% = 0 TO SX_SLOTS - 1
    IF SxF$(z_s%) <> "" THEN
      z_v$ = RcGet$(z_rec$, SxF$(z_s%))
      IF RcFound% THEN INC StSxNeed%
    ENDIF
  NEXT
END FUNCTION

' Write a whole record. md%: 0 upsert, 1 insert only, 2 update only
FUNCTION StWrite%(z_rec$, z_md%)
  LOCAL z_id$, z_oo%, z_old$, z_off%
  StErr$ = ""
  IF StCol$ = "" THEN StErr$ = "no collection open" : EXIT FUNCTION
  IF RcCheck%(z_rec$) < 0 OR INSTR(z_rec$, CHR$(10)) OR INSTR(z_rec$, CHR$(13)) THEN
    StErr$ = "bad record" : EXIT FUNCTION
  ENDIF
  z_id$ = RcGet$(z_rec$, "_id")
  IF RcFound% = 0 OR RcT% <> 1 THEN StErr$ = "_id must be a string" : EXIT FUNCTION
  IF IxKeyOk%(z_id$) = 0 THEN StErr$ = IxErr$ : EXIT FUNCTION
  IF RcIsDel%(z_rec$) THEN StErr$ = "_del is reserved" : EXIT FUNCTION
  z_oo% = IxGet%(z_id$)
  IF z_md% = 1 AND z_oo% > 0 THEN StErr$ = "duplicate _id" : EXIT FUNCTION
  IF z_md% = 2 AND z_oo% < 0 THEN StErr$ = "not found" : EXIT FUNCTION
  IF z_oo% < 0 AND IxN% >= IX_MAX THEN StErr$ = "collection full" : EXIT FUNCTION
  IF z_oo% > 0 THEN z_old$ = StRead$(z_oo%)
  IF SxN% + StSxNeed%(z_rec$) - StSxNeed%(z_old$) > SX_MAX THEN
    StErr$ = "index space full" : EXIT FUNCTION
  ENDIF
  z_off% = StAppend%(z_rec$)
  IF IxApply%(z_rec$, z_off%, z_old$) = 0 THEN StErr$ = IxErr$ + " (reopen to rebuild)" : EXIT FUNCTION
  MtNote z_rec$
  IF z_oo% > 0 THEN INC MtDead% : MtDirty% = 1
  StWrite% = 1
END FUNCTION

FUNCTION StDelete%(z_id$)
  LOCAL z_oo%, z_old$, z_tb$, z_off%
  StErr$ = ""
  z_oo% = IxGet%(z_id$)
  IF z_oo% < 0 THEN StErr$ = "not found" : EXIT FUNCTION
  z_old$ = StRead$(z_oo%)
  z_tb$ = RcSet$(RcNew$(z_id$), "_del", "1", 2)
  z_off% = StAppend%(z_tb$)
  IF IxApply%(z_tb$, z_off%, z_old$) = 0 THEN StErr$ = IxErr$ : EXIT FUNCTION
  INC MtDead%, 2 : MtDirty% = 1
  StDelete% = 1
END FUNCTION

' Set (t% 1 string, 2 literal) or remove (t% = 0) one field
FUNCTION StSetField%(z_id$, z_f$, z_v$, z_t%)
  LOCAL z_r$
  IF LEFT$(z_f$, 1) = "_" THEN StErr$ = "reserved field" : EXIT FUNCTION
  z_r$ = StFetch$(z_id$)
  IF StErr$ <> "" THEN EXIT FUNCTION
  IF z_t% = 0 THEN z_r$ = RcDel$(z_r$, z_f$) ELSE z_r$ = RcSet$(z_r$, z_f$, z_v$, z_t%)
  IF z_r$ = "" THEN StErr$ = RcErr$ : EXIT FUNCTION
  StSetField% = StWrite%(z_r$, 2)
END FUNCTION

' Next free auto _id: zero padded so _id order = insertion order
FUNCTION StNewId$()
  LOCAL z_k$
  DO
    INC MtSeq% : MtDirty% = 1
    z_k$ = STR$(MtSeq%, 6, 0, "0")
  LOOP UNTIL IxGet%(z_k$) < 0
  StNewId$ = z_k$
END FUNCTION

' ---------------- maintenance ----------------------------------------

' Rewrite live records only, in _id order. Crash-safe via .vtmp.
FUNCTION StVacuum%()
  LOCAL z_i%, z_r$
  StErr$ = ""
  IF StCol$ = "" THEN StErr$ = "no collection open" : EXIT FUNCTION
  StRdClose
  OPEN StPath$(".vtmp") FOR OUTPUT AS #ST_WR
  OPEN StPath$(".jsonl") FOR INPUT AS #ST_RD
  FOR z_i% = 0 TO IxN% - 1
    PRINT #ST_WR, IxReadAt$(ST_RD, IxO%(z_i%))
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

FUNCTION StIndexAdd%(z_f$)
  LOCAL z_s%, z_ok%
  StErr$ = ""
  IF StCol$ = "" THEN StErr$ = "no collection open" : EXIT FUNCTION
  IF z_f$ = "" OR LEFT$(z_f$, 1) = "_" OR LEN(z_f$) > 24 THEN StErr$ = "bad field" : EXIT FUNCTION
  IF SxSlot%(z_f$) >= 0 THEN StErr$ = "already indexed" : EXIT FUNCTION
  FOR z_s% = 0 TO SX_SLOTS - 1
    IF SxF$(z_s%) = "" THEN EXIT FOR
  NEXT
  IF z_s% >= SX_SLOTS THEN StErr$ = "no free index slot" : EXIT FUNCTION
  SxF$(z_s%) = z_f$
  StRdClose
  OPEN StPath$(".jsonl") FOR INPUT AS #ST_TMP
  z_ok% = SxRebuild%(ST_TMP)
  IF z_ok% = 0 THEN
    StErr$ = IxErr$ : SxF$(z_s%) = "" : z_ok% = SxRebuild%(ST_TMP) : z_ok% = 0
  ENDIF
  CLOSE #ST_TMP
  IF z_ok% THEN MtDirty% = 1
  StIndexAdd% = z_ok%
END FUNCTION

FUNCTION StIndexDrop%(z_f$)
  LOCAL z_s% = SxSlot%(z_f$), z_p$, z_i%, z_w% = 0
  StErr$ = ""
  IF z_s% < 0 THEN StErr$ = "not indexed" : EXIT FUNCTION
  SxF$(z_s%) = "" : z_p$ = CHR$(65 + z_s%)
  FOR z_i% = 0 TO SxN% - 1
    IF LEFT$(SxV$(z_i%), 1) <> z_p$ THEN SxV$(z_w%) = SxV$(z_i%) : SxO%(z_w%) = SxO%(z_i%) : INC z_w%
  NEXT
  SxN% = z_w% : MtDirty% = 1
  StIndexDrop% = 1
END FUNCTION

' =====================================================================
' dbquery.bas - Query tokenizer + parser (needs dbcore.bas for RcIsNum%)
' ---------------------------------------------------------------------
' Grammar (keywords are case-insensitive; ; at the end is optional):
'   [EXPLAIN] SELECT * | COUNT(*) | f1, f2 ... FROM c [WHERE cond]
'             [ORDER BY f [ASC|DESC]] [LIMIT n [OFFSET m]]
'   INSERT INTO c (f1, f2 ...) VALUES (v1, v2 ...)
'   UPDATE c [SET f = v, ...] [UNSET f, ...] [WHERE cond]
'   DELETE FROM c [WHERE cond]
'   CREATE COLLECTION c        DROP COLLECTION c
'   CREATE INDEX ON c (f)      DROP INDEX ON c (f)
'   SHOW COLLECTIONS           DESCRIBE c          VACUUM c
' cond: f op value | f [NOT] LIKE 'pat' | f IS [NOT] NULL
'       | NOT cond | cond AND cond | cond OR cond | ( cond )
'   op: = <> != < <= > >=     LIKE wildcards: % and _
' value: 'text' ('' = quote) | number | TRUE | FALSE | NULL
' Field names: letters, digits, _ ; anything else (or a reserved
' word) in double quotes: "first name", "order".
' IS NULL is true when the field is missing or null.
' ---------------------------------------------------------------------
' Output ("the plan"), valid when QParse%() returns 1:
'   QCmd$  SELECT INSERT UPDATE DELETE "CREATE COLLECTION"
'          "DROP COLLECTION" "CREATE INDEX" "DROP INDEX" SHOW
'          DESCRIBE VACUUM            QExplain% = 1 for EXPLAIN
'   QCol$  collection     QAgg% = 1 for COUNT(*)
'   QFld$(0..QFN%-1)      SELECT list (QFN% = 0 means *), INSERT/
'                         UPDATE fields, or the CREATE/DROP INDEX field
'   QVal$(), QVT%()       INSERT/UPDATE values; QVT% 1 string,
'                         2 literal, 0 = UNSET (remove the field)
'   QOrd$, QDesc%, QLim% (-1 = none), QOff%
'   WHERE as RPN in nodes 0..QNN%-1:
'     QnOp%  QO_* code. Leaves: compare QnF$ with QnV$ (type QnT%).
'            AND / OR pop two results, NOT pops one.
'     QnTop% 1 on a leaf that is a top-level AND term: the executor
'            may use an index for it (the whole WHERE implies it).
' =====================================================================

CONST TK_MAX = 128, QN_MAX = 24, QF_MAX = 16, QV_LEN = 128, QNV_LEN = 64
CONST TK_END = 0, TK_ID = 1, TK_NUM = 2, TK_STR = 3, TK_SYM = 4, TK_QID = 5
CONST QO_EQ = 1, QO_NE = 2, QO_LT = 3, QO_LE = 4, QO_GT = 5, QO_GE = 6
CONST QO_LIKE = 7, QO_NULL = 8, QO_NNULL = 9
CONST QO_AND = 20, QO_OR = 21, QO_NOT = 22

DIM TkT%(TK_MAX - 1), TkP%(TK_MAX - 1), TkL%(TK_MAX - 1), TkN%
DIM QText$, QErr$, QPos%, QDepth%
DIM QCmd$, QCol$, QExplain%, QAgg%, QFN%, QOrd$, QDesc%, QLim%, QOff%
DIM QFld$(QF_MAX - 1) LENGTH 24
DIM QVal$(QF_MAX - 1) LENGTH QV_LEN, QVT%(QF_MAX - 1)
DIM QNN%, QnOp%(QN_MAX - 1), QnT%(QN_MAX - 1), QnTop%(QN_MAX - 1)
DIM QnF$(QN_MAX - 1) LENGTH 24, QnV$(QN_MAX - 1) LENGTH QNV_LEN

DIM QRES$ = " SELECT FROM WHERE AND OR NOT LIKE IS NULL ORDER BY LIMIT OFFSET ASC DESC"
QRES$ = QRES$ + " INSERT INTO VALUES UPDATE SET UNSET DELETE CREATE DROP COLLECTION"
QRES$ = QRES$ + " INDEX ON SHOW COLLECTIONS DESCRIBE VACUUM COUNT TRUE FALSE EXPLAIN "
DIM QIDCH$ = "ABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789"

' ---------------- tokenizer ------------------------------------------

' Split s$ into tokens. Returns 1, or 0 with QErr$ set.
FUNCTION QLex%(z_s$)
  LOCAL z_i% = 1, z_j%, z_n% = LEN(z_s$), z_c$, z_d$
  QText$ = z_s$ : TkN% = 0
  DO
    DO WHILE z_i% <= z_n%
      IF ASC(MID$(z_s$, z_i%, 1)) > 32 THEN EXIT DO
      INC z_i%
    LOOP
    IF TkN% >= TK_MAX THEN QErr$ = "query too complex" : EXIT FUNCTION
    TkP%(TkN%) = z_i% : TkL%(TkN%) = 0
    IF z_i% > z_n% THEN TkT%(TkN%) = TK_END : INC TkN% : QLex% = 1 : EXIT FUNCTION
    z_c$ = MID$(z_s$, z_i%, 1) : z_d$ = MID$(z_s$, z_i% + 1, 1) : z_j% = z_i% + 1
    IF INSTR(LEFT$(QIDCH$, 27), UCASE$(z_c$)) > 0 THEN
      ' identifier or keyword: starts with a letter or _
      DO WHILE z_j% <= z_n%
        IF INSTR(QIDCH$, UCASE$(MID$(z_s$, z_j%, 1))) = 0 THEN EXIT DO
        INC z_j%
      LOOP
      TkT%(TkN%) = TK_ID
    ELSEIF INSTR("0123456789", z_c$) > 0 OR (z_c$ = "-" AND z_d$ <> "" AND INSTR("0123456789", z_d$) > 0) THEN
      DO WHILE z_j% <= z_n%
        z_c$ = MID$(z_s$, z_j%, 1)
        IF INSTR("0123456789.eE", z_c$) = 0 THEN
          IF INSTR("+-", z_c$) = 0 OR INSTR("eE", MID$(z_s$, z_j% - 1, 1)) = 0 THEN EXIT DO
        ENDIF
        INC z_j%
      LOOP
      IF RcIsNum%(MID$(z_s$, z_i%, z_j% - z_i%)) = 0 THEN QErr$ = "bad number at col " + STR$(z_i%) : EXIT FUNCTION
      TkT%(TkN%) = TK_NUM
    ELSEIF z_c$ = "'" THEN
      DO
        IF z_j% > z_n% THEN QErr$ = "unclosed string at col " + STR$(z_i%) : EXIT FUNCTION
        z_j% = INSTR(z_j%, z_s$, "'")
        IF z_j% = 0 THEN QErr$ = "unclosed string at col " + STR$(z_i%) : EXIT FUNCTION
        IF MID$(z_s$, z_j% + 1, 1) <> "'" THEN EXIT DO
        INC z_j%, 2
      LOOP
      INC z_j%
      TkT%(TkN%) = TK_STR
    ELSEIF z_c$ = CHR$(34) THEN
      z_j% = 0
      IF z_i% < z_n% THEN z_j% = INSTR(z_i% + 1, z_s$, CHR$(34))
      IF z_j% = 0 THEN QErr$ = "unclosed name at col " + STR$(z_i%) : EXIT FUNCTION
      IF z_j% = z_i% + 1 THEN QErr$ = "empty name at col " + STR$(z_i%) : EXIT FUNCTION
      INC z_j%
      TkT%(TkN%) = TK_QID
    ELSE
      z_d$ = z_c$ + z_d$
      IF z_d$ = "<=" OR z_d$ = ">=" OR z_d$ = "<>" OR z_d$ = "!=" THEN
        z_j% = z_i% + 2
      ELSEIF INSTR("=<>(),*;", z_c$) = 0 THEN
        QErr$ = "unexpected '" + z_c$ + "' at col " + STR$(z_i%) : EXIT FUNCTION
      ENDIF
      TkT%(TkN%) = TK_SYM
    ENDIF
    TkL%(TkN%) = z_j% - z_i% : INC TkN% : z_i% = z_j%
  LOOP
END FUNCTION

FUNCTION TkRaw$(z_i%)
  TkRaw$ = MID$(QText$, TkP%(z_i%), TkL%(z_i%))
END FUNCTION

' ---------------- parser helpers -------------------------------------

SUB QFail z_m$
  IF QErr$ = "" THEN QErr$ = z_m$ + " at col " + STR$(TkP%(QPos%))
END SUB

' Consume keyword kwd$ (upper case) if it is next
FUNCTION QKw%(z_kwd$)
  IF QErr$ <> "" THEN EXIT FUNCTION
  IF TkT%(QPos%) = TK_ID THEN
    IF UCASE$(TkRaw$(QPos%)) = z_kwd$ THEN INC QPos% : QKw% = 1
  ENDIF
END FUNCTION

FUNCTION QNeedKw%(z_kwd$)
  QNeedKw% = QKw%(z_kwd$)
  IF QNeedKw% = 0 THEN QFail "expected " + z_kwd$
END FUNCTION

' Consume symbol s$ if next ("!=" counts as "<>")
FUNCTION QSym%(z_s$)
  LOCAL z_r$
  IF QErr$ <> "" THEN EXIT FUNCTION
  IF TkT%(QPos%) = TK_SYM THEN
    z_r$ = TkRaw$(QPos%)
    IF z_r$ = "!=" THEN z_r$ = "<>"
    IF z_r$ = z_s$ THEN INC QPos% : QSym% = 1
  ENDIF
END FUNCTION

FUNCTION QNeedSym%(z_s$)
  QNeedSym% = QSym%(z_s$)
  IF QNeedSym% = 0 THEN QFail "expected " + z_s$
END FUNCTION

' A field name (plain or "quoted")
FUNCTION QName$()
  LOCAL z_r$
  IF QErr$ <> "" THEN EXIT FUNCTION
  z_r$ = TkRaw$(QPos%)
  IF TkT%(QPos%) = TK_QID THEN
    z_r$ = MID$(z_r$, 2, LEN(z_r$) - 2)
  ELSEIF TkT%(QPos%) = TK_ID THEN
    IF INSTR(QRES$, " " + UCASE$(z_r$) + " ") THEN QFail "reserved word '" + z_r$ + "' (quote it)" : EXIT FUNCTION
  ELSE
    QFail "expected a field name" : EXIT FUNCTION
  ENDIF
  IF LEN(z_r$) > 24 THEN QFail "name too long" : EXIT FUNCTION
  INC QPos%
  QName$ = z_r$
END FUNCTION

' A collection name: plain identifier, max 16 chars
FUNCTION QColName$()
  LOCAL z_r$
  IF QErr$ <> "" THEN EXIT FUNCTION
  z_r$ = TkRaw$(QPos%)
  IF TkT%(QPos%) <> TK_ID OR INSTR(QRES$, " " + UCASE$(z_r$) + " ") > 0 THEN
    QFail "expected a collection name" : EXIT FUNCTION
  ENDIF
  IF LEN(z_r$) > 16 THEN QFail "collection name too long" : EXIT FUNCTION
  INC QPos%
  QColName$ = z_r$
END FUNCTION

' A literal value. t% = 1 string, 2 number/true/false/null
FUNCTION QValue%(z_v$, z_t%)
  LOCAL z_r$, z_i%
  IF QErr$ <> "" THEN EXIT FUNCTION
  z_r$ = TkRaw$(QPos%) : z_v$ = ""
  SELECT CASE TkT%(QPos%)
    CASE TK_STR
      z_r$ = MID$(z_r$, 2, LEN(z_r$) - 2) : z_t% = 1
      DO
        z_i% = INSTR(z_r$, "''")
        IF z_i% = 0 THEN EXIT DO
        z_v$ = z_v$ + LEFT$(z_r$, z_i%) : z_r$ = MID$(z_r$, z_i% + 2)
      LOOP
      z_v$ = z_v$ + z_r$
    CASE TK_NUM
      z_v$ = z_r$ : z_t% = 2
    CASE TK_ID
      z_v$ = LCASE$(z_r$) : z_t% = 2
      IF z_v$ <> "true" AND z_v$ <> "false" AND z_v$ <> "null" THEN QFail "expected a value" : EXIT FUNCTION
    CASE ELSE
      QFail "expected a value" : EXIT FUNCTION
  END SELECT
  INC QPos%
  QValue% = 1
END FUNCTION

' A whole number for LIMIT / OFFSET
FUNCTION QInt%()
  LOCAL z_r$ = TkRaw$(QPos%), z_i%
  IF QErr$ <> "" THEN EXIT FUNCTION
  IF TkT%(QPos%) = TK_NUM AND LEN(z_r$) <= 6 THEN
    FOR z_i% = 1 TO LEN(z_r$)
      IF INSTR("0123456789", MID$(z_r$, z_i%, 1)) = 0 THEN EXIT FOR
    NEXT
    IF z_i% > LEN(z_r$) THEN QInt% = VAL(z_r$) : INC QPos% : EXIT FUNCTION
  ENDIF
  QFail "expected a whole number"
END FUNCTION

' 1 if field f$ is already in QFld$()
FUNCTION QHas%(z_f$)
  LOCAL z_i%
  FOR z_i% = 0 TO QFN% - 1
    IF QFld$(z_i%) = z_f$ THEN QHas% = 1 : EXIT FUNCTION
  NEXT
END FUNCTION

' Comma separated field names into QFld$(); returns count
FUNCTION QNames%(z_dup%)
  LOCAL z_f$
  DO
    z_f$ = QName$()
    IF QErr$ <> "" THEN EXIT FUNCTION
    IF QFN% >= QF_MAX THEN QFail "too many fields" : EXIT FUNCTION
    IF z_dup% = 0 AND QHas%(z_f$) THEN QFail "duplicate field '" + z_f$ + "'" : EXIT FUNCTION
    QFld$(QFN%) = z_f$ : QVT%(QFN%) = 0 : INC QFN%
  LOOP WHILE QSym%(",")
  QNames% = QFN%
END FUNCTION

' Store value v$ for field slot i%
FUNCTION QSetVal%(z_i%, z_v$, z_t%)
  IF LEN(z_v$) > QV_LEN THEN QFail "value too long" : EXIT FUNCTION
  QVal$(z_i%) = z_v$ : QVT%(z_i%) = z_t% : QSetVal% = 1
END FUNCTION

' ---------------- WHERE expression -> RPN ----------------------------

FUNCTION QNode%(z_op%, z_f$, z_v$, z_t%)
  IF QErr$ <> "" THEN EXIT FUNCTION
  IF QNN% >= QN_MAX THEN QFail "condition too complex" : EXIT FUNCTION
  IF LEN(z_v$) > QNV_LEN THEN QFail "value too long" : EXIT FUNCTION
  QnOp%(QNN%) = z_op% : QnF$(QNN%) = z_f$ : QnV$(QNN%) = z_v$ : QnT%(QNN%) = z_t%
  QnTop%(QNN%) = (z_op% < QO_AND)
  INC QNN%
  QNode% = 1
END FUNCTION

' Leaves from node st% on are not top-level AND terms
SUB QNotTop z_st%
  LOCAL z_i%
  FOR z_i% = z_st% TO QNN% - 1 : QnTop%(z_i%) = 0 : NEXT
END SUB

' NOTE: these recursive functions must not use DO/FOR loops: MMBasic
' tracks loops by program position, so a loop re-entered through
' recursion ("a AND (b AND c)") breaks the outer one.
FUNCTION QOr%()
  LOCAL z_st% = QNN%
  IF QAnd%() = 0 THEN EXIT FUNCTION
  IF QKw%("OR") THEN
    QOr% = QOrRest%()
    QNotTop z_st%
  ELSE
    QOr% = (QErr$ = "")
  ENDIF
END FUNCTION

' After an OR: operand, emit OR, repeat (keeps left associativity)
FUNCTION QOrRest%()
  IF QAnd%() = 0 THEN EXIT FUNCTION
  IF QNode%(QO_OR, "", "", 0) = 0 THEN EXIT FUNCTION
  IF QKw%("OR") THEN QOrRest% = QOrRest%() ELSE QOrRest% = (QErr$ = "")
END FUNCTION

FUNCTION QAnd%()
  IF QNot%() = 0 THEN EXIT FUNCTION
  IF QKw%("AND") THEN QAnd% = QAndRest%() ELSE QAnd% = (QErr$ = "")
END FUNCTION

FUNCTION QAndRest%()
  IF QNot%() = 0 THEN EXIT FUNCTION
  IF QNode%(QO_AND, "", "", 0) = 0 THEN EXIT FUNCTION
  IF QKw%("AND") THEN QAndRest% = QAndRest%() ELSE QAndRest% = (QErr$ = "")
END FUNCTION

FUNCTION QNot%()
  LOCAL z_st% = QNN%
  IF QKw%("NOT") THEN
    INC QDepth%
    IF QDepth% > 12 THEN QFail "too deeply nested" : EXIT FUNCTION
    IF QNot%() = 0 THEN EXIT FUNCTION
    INC QDepth%, -1
    QNot% = QNode%(QO_NOT, "", "", 0)
    QNotTop z_st%
  ELSE
    QNot% = QPrim%()
  ENDIF
END FUNCTION

FUNCTION QPrim%()
  LOCAL z_f$, z_v$, z_t%, z_op%, z_neg%, z_st% = QNN%
  IF QErr$ <> "" THEN EXIT FUNCTION
  INC QDepth%
  IF QDepth% > 12 THEN QFail "too deeply nested" : EXIT FUNCTION
  IF QSym%("(") THEN
    IF QOr%() = 0 THEN EXIT FUNCTION
    IF QNeedSym%(")") = 0 THEN EXIT FUNCTION
    INC QDepth%, -1 : QPrim% = 1 : EXIT FUNCTION
  ENDIF
  z_f$ = QName$()
  IF QErr$ <> "" THEN EXIT FUNCTION
  IF QKw%("IS") THEN
    z_neg% = QKw%("NOT")
    IF QNeedKw%("NULL") = 0 THEN EXIT FUNCTION
    IF z_neg% THEN z_op% = QO_NNULL ELSE z_op% = QO_NULL
  ELSE
    z_neg% = QKw%("NOT")
    IF z_neg% THEN
      IF QNeedKw%("LIKE") = 0 THEN EXIT FUNCTION
      z_op% = QO_LIKE
    ELSEIF QKw%("LIKE") THEN
      z_op% = QO_LIKE
    ELSE
      IF TkT%(QPos%) = TK_SYM THEN
        SELECT CASE TkRaw$(QPos%)
          CASE "="       : z_op% = QO_EQ
          CASE "<>", "!=" : z_op% = QO_NE
          CASE "<"       : z_op% = QO_LT
          CASE "<="      : z_op% = QO_LE
          CASE ">"       : z_op% = QO_GT
          CASE ">="      : z_op% = QO_GE
        END SELECT
      ENDIF
      IF z_op% = 0 THEN QFail "expected an operator" : EXIT FUNCTION
      INC QPos%
    ENDIF
    IF QValue%(z_v$, z_t%) = 0 THEN EXIT FUNCTION
    IF z_op% = QO_LIKE AND z_t% <> 1 THEN QFail "LIKE needs a 'text' pattern" : EXIT FUNCTION
  ENDIF
  IF QNode%(z_op%, z_f$, z_v$, z_t%) = 0 THEN EXIT FUNCTION
  IF z_neg% AND z_op% = QO_LIKE THEN
    IF QNode%(QO_NOT, "", "", 0) = 0 THEN EXIT FUNCTION
    QNotTop z_st%
  ENDIF
  INC QDepth%, -1
  QPrim% = 1
END FUNCTION

' ---------------- statements -----------------------------------------

SUB QReset
  QErr$ = "" : QPos% = 0 : QDepth% = 0 : QCmd$ = "" : QCol$ = ""
  QExplain% = 0 : QAgg% = 0 : QFN% = 0 : QNN% = 0
  QOrd$ = "" : QDesc% = 0 : QLim% = -1 : QOff% = 0
END SUB

SUB QSelect
  LOCAL z_x%
  IF QKw%("COUNT") THEN
    z_x% = QNeedSym%("(") : z_x% = QNeedSym%("*") : z_x% = QNeedSym%(")")
    QAgg% = 1
  ELSEIF QSym%("*") = 0 THEN
    z_x% = QNames%(1)
  ENDIF
  z_x% = QNeedKw%("FROM")
  QCol$ = QColName$()
  IF QKw%("WHERE") THEN z_x% = QOr%()
  IF QKw%("ORDER") THEN
    z_x% = QNeedKw%("BY")
    QOrd$ = QName$()
    IF QKw%("DESC") THEN QDesc% = 1 ELSE z_x% = QKw%("ASC")
  ENDIF
  IF QKw%("LIMIT") THEN
    QLim% = QInt%()
    IF QKw%("OFFSET") THEN QOff% = QInt%()
  ENDIF
END SUB

SUB QInsert
  LOCAL z_x%, z_i%, z_v$, z_t%
  z_x% = QNeedKw%("INTO")
  QCol$ = QColName$()
  z_x% = QNeedSym%("(") : z_x% = QNames%(0) : z_x% = QNeedSym%(")")
  z_x% = QNeedKw%("VALUES") : z_x% = QNeedSym%("(")
  FOR z_i% = 0 TO QFN% - 1
    IF QErr$ <> "" THEN EXIT SUB
    IF z_i% > 0 THEN
      IF QNeedSym%(",") = 0 THEN QErr$ = "" : QFail "fewer values than fields" : EXIT SUB
    ENDIF
    IF QValue%(z_v$, z_t%) THEN z_x% = QSetVal%(z_i%, z_v$, z_t%)
    IF QFld$(z_i%) = "_id" AND z_t% <> 1 AND QErr$ = "" THEN QFail "_id must be 'text'"
  NEXT
  IF QErr$ = "" AND QSym%(",") THEN QFail "more values than fields" : EXIT SUB
  z_x% = QNeedSym%(")")
END SUB

SUB QUpdate
  LOCAL z_x%, z_f$, z_v$, z_t%, z_i%
  QCol$ = QColName$()
  IF QKw%("SET") THEN
    DO
      z_f$ = QName$()
      IF z_f$ = "_id" THEN QFail "_id cannot be changed"
      IF QHas%(z_f$) THEN QFail "duplicate field '" + z_f$ + "'"
      z_x% = QNeedSym%("=")
      IF QValue%(z_v$, z_t%) = 0 THEN EXIT SUB
      IF QFN% >= QF_MAX THEN QFail "too many fields" : EXIT SUB
      QFld$(QFN%) = z_f$ : z_x% = QSetVal%(QFN%, z_v$, z_t%) : INC QFN%
    LOOP WHILE QSym%(",")
  ENDIF
  IF QKw%("UNSET") THEN
    z_i% = QFN%
    z_x% = QNames%(0)
    FOR z_i% = z_i% TO QFN% - 1
      IF QFld$(z_i%) = "_id" THEN QFail "_id cannot be removed"
    NEXT
  ENDIF
  IF QFN% = 0 THEN QFail "expected SET or UNSET"
  IF QKw%("WHERE") THEN z_x% = QOr%()
END SUB

SUB QIndexDef z_c$
  LOCAL z_x%
  QCmd$ = z_c$ + " INDEX"
  z_x% = QNeedKw%("ON") : QCol$ = QColName$()
  z_x% = QNeedSym%("(") : QFld$(0) = QName$() : QFN% = 1 : z_x% = QNeedSym%(")")
  IF LEFT$(QFld$(0), 1) = "_" AND QErr$ = "" THEN QFail "cannot index _ fields"
END SUB

' Parse one statement. Returns 1 if valid, else 0 with QErr$ set.
FUNCTION QParse%(z_s$)
  LOCAL z_x%, z_c$
  QReset
  IF QLex%(z_s$) = 0 THEN EXIT FUNCTION
  QExplain% = QKw%("EXPLAIN")
  IF TkT%(QPos%) = TK_ID THEN z_c$ = UCASE$(TkRaw$(QPos%))
  IF INSTR(" SELECT INSERT UPDATE DELETE CREATE DROP SHOW DESCRIBE VACUUM ", " " + z_c$ + " ") = 0 OR z_c$ = "" THEN
    QFail "unknown command" : EXIT FUNCTION
  ENDIF
  INC QPos% : QCmd$ = z_c$
  SELECT CASE z_c$
    CASE "SELECT" : QSelect
    CASE "INSERT" : QInsert
    CASE "UPDATE" : QUpdate
    CASE "DELETE"
      z_x% = QNeedKw%("FROM") : QCol$ = QColName$()
      IF QKw%("WHERE") THEN z_x% = QOr%()
    CASE "CREATE", "DROP"
      IF QKw%("COLLECTION") THEN
        QCmd$ = z_c$ + " COLLECTION" : QCol$ = QColName$()
      ELSEIF QKw%("INDEX") THEN
        QIndexDef z_c$
      ELSE
        QFail "expected COLLECTION or INDEX"
      ENDIF
    CASE "SHOW" : z_x% = QNeedKw%("COLLECTIONS")
    CASE ELSE : QCol$ = QColName$()
  END SELECT
  IF QErr$ = "" THEN
    z_x% = QSym%(";")
    IF TkT%(QPos%) <> TK_END THEN QFail "unexpected '" + TkRaw$(QPos%) + "'"
  ENDIF
  QParse% = (QErr$ = "")
END FUNCTION

FUNCTION QOpName$(z_op%)
  SELECT CASE z_op%
    CASE QO_EQ : QOpName$ = "="
    CASE QO_NE : QOpName$ = "<>"
    CASE QO_LT : QOpName$ = "<"
    CASE QO_LE : QOpName$ = "<="
    CASE QO_GT : QOpName$ = ">"
    CASE QO_GE : QOpName$ = ">="
    CASE QO_LIKE : QOpName$ = "LIKE"
    CASE QO_NULL : QOpName$ = "IS NULL"
    CASE QO_NNULL : QOpName$ = "IS NOT NULL"
    CASE QO_AND : QOpName$ = "AND"
    CASE QO_OR : QOpName$ = "OR"
    CASE QO_NOT : QOpName$ = "NOT"
  END SELECT
END FUNCTION

' Text of WHERE node i%; "^" marks an index-eligible top-level term
FUNCTION QNodeTxt$(z_i%)
  LOCAL z_p$
  IF QnOp%(z_i%) >= QO_AND THEN QNodeTxt$ = QOpName$(QnOp%(z_i%)) : EXIT FUNCTION
  z_p$ = QnF$(z_i%) + " " + QOpName$(QnOp%(z_i%))
  IF QnOp%(z_i%) < QO_NULL THEN
    IF QnT%(z_i%) = 1 THEN z_p$ = z_p$ + " '" + QnV$(z_i%) + "'" ELSE z_p$ = z_p$ + " " + QnV$(z_i%)
  ENDIF
  IF QnTop%(z_i%) THEN z_p$ = "^" + z_p$
  QNodeTxt$ = z_p$
END FUNCTION

' Readable plan, for EXPLAIN and testing (truncated at 255 chars)
FUNCTION QPlan$()
  LOCAL z_s$, z_p$, z_i%
  z_s$ = QCmd$ + "|" + QCol$ + "|"
  IF QAgg% THEN z_s$ = z_s$ + "COUNT"
  FOR z_i% = 0 TO QFN% - 1
    z_p$ = QFld$(z_i%)
    IF QCmd$ = "INSERT" OR QCmd$ = "UPDATE" THEN
      IF QVT%(z_i%) = 0 THEN
        z_p$ = "-" + z_p$
      ELSEIF QVT%(z_i%) = 1 THEN
        z_p$ = z_p$ + "='" + QVal$(z_i%) + "'"
      ELSE
        z_p$ = z_p$ + "=" + QVal$(z_i%)
      ENDIF
    ENDIF
    IF z_i% > 0 THEN z_p$ = "," + z_p$
    IF LEN(z_s$) + LEN(z_p$) > 250 THEN QPlan$ = z_s$ + "~" : EXIT FUNCTION
    z_s$ = z_s$ + z_p$
  NEXT
  z_s$ = z_s$ + "|"
  FOR z_i% = 0 TO QNN% - 1
    z_p$ = QNodeTxt$(z_i%)
    IF z_i% > 0 THEN z_p$ = ";" + z_p$
    IF LEN(z_s$) + LEN(z_p$) > 250 THEN QPlan$ = z_s$ + "~" : EXIT FUNCTION
    z_s$ = z_s$ + z_p$
  NEXT
  z_p$ = "|" + QOrd$
  IF QDesc% THEN z_p$ = z_p$ + " DESC"
  z_p$ = z_p$ + "|" + STR$(QLim%) + "," + STR$(QOff%)
  IF LEN(z_s$) + LEN(z_p$) > 255 THEN QPlan$ = z_s$ + "~" : EXIT FUNCTION
  QPlan$ = z_s$ + z_p$
END FUNCTION

' =====================================================================
' dbexec.bas - Query executor (needs dbcore, dbstore, dbquery)
' ---------------------------------------------------------------------
' ExRun%(q$) parses and runs one statement. Returns 1 or 0 (ExErr$).
' Results, by ExKind$:
'   "ROWS"  ExR%(0..ExN%-1) = file offsets of matching records; read
'           one with StRead$(ExR%(i)). Fields to show: QFld$(0..QFN%-1)
'           (QFN% = 0 means all). Snapshot: re-run after any write.
'   "COUNT" ExCnt%
'   "TEXT"  ExOut$(0..ExOutN%-1): SHOW, DESCRIBE, EXPLAIN output
'   "OK"    writes and admin commands
' ExMsg$ is a one-line summary; ExWarn$ any warning from opening.
' ---------------------------------------------------------------------
' Semantics (schemaless, SQL-like):
' - A comparison on a missing field is false (also <>). Use IS NULL.
' - Number vs number compares numerically ('1e3' = 1000); text vs
'   text compares by character code (case-sensitive), as does LIKE.
'   Mismatched types are never =, <, >; they are <>.
' - Without ORDER BY rows come in _id order (or in index order when
'   an index on another field was used). ORDER BY: missing values
'   last (first with DESC); numbers before text.
' =====================================================================

CONST EX_OUTMAX = 40, EX_W = 52
DIM ExR%(IX_MAX - 1), ExN%, ExCnt%
DIM ExKind$, ExMsg$, ExErr$, ExWarn$, ExPath$
DIM ExOut$(EX_OUTMAX - 1) LENGTH EX_W, ExOutN%
DIM ExSrc%, ExLo%, ExHi%
DIM ExSt%(QN_MAX - 1)

SUB ExSay z_s$
  IF ExOutN% < EX_OUTMAX THEN ExOut$(ExOutN%) = LEFT$(z_s$, EX_W) : INC ExOutN%
END SUB

' ---------------- matching -------------------------------------------

' SQL LIKE: % any run, _ any one char. Case-sensitive.
FUNCTION ExLike%(z_s$, z_p$)
  LOCAL z_i% = 1, z_j% = 1, z_si% = 0, z_sj% = 0, z_ls% = LEN(z_s$), z_lp% = LEN(z_p$), z_c$
  DO WHILE z_i% <= z_ls%
    z_c$ = MID$(z_p$, z_j%, 1)
    IF z_j% <= z_lp% AND z_c$ <> "%" AND (z_c$ = "_" OR z_c$ = MID$(z_s$, z_i%, 1)) THEN
      INC z_i% : INC z_j%
    ELSEIF z_j% <= z_lp% AND z_c$ = "%" THEN
      z_sj% = z_j% : z_si% = z_i% : INC z_j%
    ELSEIF z_sj% > 0 THEN
      INC z_si% : z_i% = z_si% : z_j% = z_sj% + 1
    ELSE
      EXIT FUNCTION
    ENDIF
  LOOP
  DO WHILE z_j% <= z_lp%
    IF MID$(z_p$, z_j%, 1) <> "%" THEN EXIT FUNCTION
    INC z_j%
  LOOP
  ExLike% = 1
END FUNCTION

' Literal prefix of a LIKE pattern (up to the first wildcard)
FUNCTION ExPrefix$(z_p$)
  LOCAL z_i%
  FOR z_i% = 1 TO LEN(z_p$)
    IF INSTR("%_", MID$(z_p$, z_i%, 1)) THEN EXIT FOR
  NEXT
  ExPrefix$ = LEFT$(z_p$, z_i% - 1)
END FUNCTION

' Evaluate leaf node k% against rec$ (1/0)
FUNCTION ExLeaf%(z_rec$, z_k%)
  LOCAL z_x$, z_v$ = QnV$(z_k%), z_op% = QnOp%(z_k%), z_t%, z_c% = 2, z_nx%, z_nv%
  z_x$ = RcGet$(z_rec$, QnF$(z_k%)) : z_t% = RcT%
  IF z_op% = QO_NULL OR z_op% = QO_NNULL THEN
    z_c% = (RcFound% = 0) OR (z_t% = 2 AND z_x$ = "null")
    IF z_op% = QO_NULL THEN ExLeaf% = z_c% ELSE ExLeaf% = 1 - z_c%
    EXIT FUNCTION
  ENDIF
  IF RcFound% = 0 THEN EXIT FUNCTION
  IF z_op% = QO_LIKE THEN
    IF z_t% = 1 THEN ExLeaf% = ExLike%(z_x$, z_v$)
    EXIT FUNCTION
  ENDIF
  IF z_t% = 2 AND QnT%(z_k%) = 2 THEN
    z_nx% = RcIsNum%(z_x$) : z_nv% = RcIsNum%(z_v$)
    IF z_nx% AND z_nv% THEN
      z_c% = SGN(VAL(z_x$) - VAL(z_v$))
    ELSEIF z_nx% = 0 AND z_nv% = 0 THEN
      z_c% = (z_x$ > z_v$) - (z_x$ < z_v$)
    ENDIF
  ELSEIF z_t% = 1 AND QnT%(z_k%) = 1 THEN
    z_c% = (z_x$ > z_v$) - (z_x$ < z_v$)
  ENDIF
  SELECT CASE z_op%
    CASE QO_EQ : ExLeaf% = (z_c% = 0)
    CASE QO_NE : ExLeaf% = (z_c% <> 0)
    CASE QO_LT : ExLeaf% = (z_c% = -1)
    CASE QO_LE : ExLeaf% = (z_c% = -1 OR z_c% = 0)
    CASE QO_GT : ExLeaf% = (z_c% = 1)
    CASE QO_GE : ExLeaf% = (z_c% = 1 OR z_c% = 0)
  END SELECT
END FUNCTION

' Evaluate the whole WHERE (RPN) against rec$
FUNCTION ExMatch%(z_rec$)
  LOCAL z_k%, z_sp% = 0
  IF QNN% = 0 THEN ExMatch% = 1 : EXIT FUNCTION
  FOR z_k% = 0 TO QNN% - 1
    SELECT CASE QnOp%(z_k%)
      CASE QO_AND : INC z_sp%, -1 : ExSt%(z_sp% - 1) = ExSt%(z_sp% - 1) AND ExSt%(z_sp%)
      CASE QO_OR  : INC z_sp%, -1 : ExSt%(z_sp% - 1) = ExSt%(z_sp% - 1) OR ExSt%(z_sp%)
      CASE QO_NOT : ExSt%(z_sp% - 1) = 1 - ExSt%(z_sp% - 1)
      CASE ELSE   : ExSt%(z_sp%) = ExLeaf%(z_rec$, z_k%) : INC z_sp%
    END SELECT
  NEXT
  ExMatch% = ExSt%(0)
END FUNCTION

' ---------------- access path ----------------------------------------

' Pick the narrowest index range among top-level AND terms.
' ExSrc%: 0 full scan, 1 _id range, 2 secondary index range.
SUB ExPlanPath
  LOCAL z_k%, z_s%, z_op%, z_lo%, z_hi%, z_ok%, z_v$, z_t%
  ExSrc% = 0 : ExLo% = 0 : ExHi% = IxN% : ExPath$ = "full scan"
  FOR z_k% = 0 TO QNN% - 1
    z_op% = QnOp%(z_k%) : z_v$ = QnV$(z_k%) : z_t% = QnT%(z_k%) : z_ok% = 0
    IF QnTop%(z_k%) AND z_op% <= QO_LIKE AND z_op% <> QO_NE THEN
      IF z_op% = QO_LIKE THEN z_v$ = ExPrefix$(z_v$)
      IF QnF$(z_k%) = "_id" THEN
        IF z_op% = QO_LIKE AND z_v$ <> "" THEN
          z_lo% = IxBound%(IxK$(), IxN%, z_v$, 0)
          z_hi% = IxBound%(IxK$(), IxN%, z_v$ + STRING$(IX_KLEN, 255), 1)
          z_ok% = 1
        ELSEIF z_op% <> QO_LIKE AND z_t% = 1 THEN
          IxRange QOpName$(z_op%), z_v$, z_lo%, z_hi% : z_ok% = (z_lo% >= 0)
        ENDIF
        IF z_ok% AND z_hi% - z_lo% < ExHi% - ExLo% + (ExSrc% = 0) THEN
          ExSrc% = 1 : ExLo% = z_lo% : ExHi% = z_hi% : ExPath$ = "_id range"
        ENDIF
      ELSE
        z_s% = SxSlot%(QnF$(z_k%))
        IF z_s% >= 0 THEN
          IF z_op% = QO_LIKE THEN
            IF z_v$ <> "" THEN SxRange z_s%, "LIKE", z_v$, 1, z_lo%, z_hi% : z_ok% = 1
          ELSEIF z_t% = 1 OR RcIsNum%(z_v$) OR z_op% = QO_EQ THEN
            SxRange z_s%, QOpName$(z_op%), z_v$, z_t%, z_lo%, z_hi% : z_ok% = (z_lo% >= 0)
          ENDIF
          IF z_ok% AND z_hi% - z_lo% < ExHi% - ExLo% + (ExSrc% = 0) THEN
            ExSrc% = 2 : ExLo% = z_lo% : ExHi% = z_hi% : ExPath$ = "index on " + QnF$(z_k%)
          ENDIF
        ENDIF
      ENDIF
    ENDIF
  NEXT
END SUB

' Collect matching offsets into ExR%; stop after lim% (-1 = all)
SUB ExCollect z_lim%
  LOCAL z_i%, z_off%
  ExN% = 0
  IF z_lim% = 0 THEN EXIT SUB
  FOR z_i% = ExLo% TO ExHi% - 1
    IF ExSrc% = 2 THEN z_off% = SxO%(z_i%) ELSE z_off% = IxO%(z_i%)
    IF ExMatch%(StRead$(z_off%)) THEN
      ExR%(ExN%) = z_off% : INC ExN%
      IF z_lim% > 0 AND ExN% >= z_lim% THEN EXIT SUB
    ENDIF
  NEXT
END SUB

' ---------------- ordering -------------------------------------------

' Sortable key: "1"+number (11 int + 4 frac digits), "2"+text, "3" none
FUNCTION ExSortKey$(z_rec$, z_f$)
  LOCAL z_x$ = RcGet$(z_rec$, z_f$), z_e!, z_ip%, z_fr%
  IF RcFound% = 0 OR (RcT% = 2 AND z_x$ = "null") THEN ExSortKey$ = "3" : EXIT FUNCTION
  IF RcT% = 2 AND RcIsNum%(z_x$) THEN
    z_e! = VAL(z_x$)
    IF z_e! > 4.9E10 THEN z_e! = 4.9E10
    IF z_e! < -4.9E10 THEN z_e! = -4.9E10
    z_e! = z_e! + 5E10 : z_ip% = INT(z_e!) : z_fr% = INT((z_e! - z_ip%) * 10000)
    ExSortKey$ = "1" + RIGHT$("0000000000" + STR$(z_ip%), 11) + RIGHT$("000" + STR$(z_fr%), 4)
  ELSE
    ExSortKey$ = "2" + LEFT$(z_x$, 15)
  ENDIF
END FUNCTION

SUB ExReverse
  LOCAL z_i%, z_j% = ExN% - 1, z_t%
  FOR z_i% = 0 TO ExN% \ 2 - 1
    z_t% = ExR%(z_i%) : ExR%(z_i%) = ExR%(z_j% - z_i%) : ExR%(z_j% - z_i%) = z_t%
  NEXT
END SUB

SUB ExSort
  IF ExN% < 2 THEN EXIT SUB
  IF QOrd$ = "_id" AND ExSrc% <> 2 THEN
    IF QDesc% THEN ExReverse
    EXIT SUB
  ENDIF
  LOCAL z_k$(ExN% - 1) LENGTH 16, z_ix%(ExN% - 1), z_tmp%(ExN% - 1), z_i%
  FOR z_i% = 0 TO ExN% - 1 : z_k$(z_i%) = ExSortKey$(StRead$(ExR%(z_i%)), QOrd$) : NEXT
  SORT z_k$(), z_ix%(), QDesc%
  FOR z_i% = 0 TO ExN% - 1 : z_tmp%(z_i%) = ExR%(z_ix%(z_i%)) : NEXT
  FOR z_i% = 0 TO ExN% - 1 : ExR%(z_i%) = z_tmp%(z_i%) : NEXT
END SUB

' Keep rows QOff%.. (at most QLim% of them)
SUB ExSlice
  LOCAL z_i%, z_n%
  z_n% = ExN% - QOff%
  IF z_n% < 0 THEN z_n% = 0
  IF QLim% >= 0 AND z_n% > QLim% THEN z_n% = QLim%
  IF QOff% > 0 THEN
    FOR z_i% = 0 TO z_n% - 1 : ExR%(z_i%) = ExR%(z_i% + QOff%) : NEXT
  ENDIF
  ExN% = z_n%
END SUB

' ---------------- statements -----------------------------------------

FUNCTION ExUse%(z_c$)
  IF StCol$ = z_c$ AND z_c$ <> "" THEN ExUse% = 1 : EXIT FUNCTION
  ExUse% = StOpen%(z_c$)
  IF StWarn$ <> "" THEN ExWarn$ = StWarn$
  IF ExUse% = 0 THEN ExErr$ = StErr$
END FUNCTION

SUB ExExplain
  LOCAL z_i%
  ExKind$ = "TEXT"
  ExSay QCmd$ + " " + QCol$ + ": " + ExPath$ + " (" + STR$(ExHi% - ExLo%) + " of " + STR$(IxN%) + ")"
  IF ExSrc% = 2 THEN ExSay "  index is approximate: rows are re-checked"
  FOR z_i% = 0 TO QNN% - 1 : ExSay "  " + QNodeTxt$(z_i%) : NEXT
  IF QOrd$ <> "" AND QDesc% THEN ExSay "order by " + QOrd$ + " desc"
  IF QOrd$ <> "" AND QDesc% = 0 THEN ExSay "order by " + QOrd$
  IF QLim% >= 0 THEN ExSay "limit " + STR$(QLim%) + " offset " + STR$(QOff%)
  ExMsg$ = "plan"
END SUB

SUB ExSelect
  LOCAL z_lim% = -1
  IF QAgg% AND QNN% = 0 THEN
    ExKind$ = "COUNT" : ExCnt% = IxN% : ExMsg$ = STR$(ExCnt%) : EXIT SUB
  ENDIF
  IF QOrd$ = "" AND QLim% >= 0 AND QAgg% = 0 THEN z_lim% = QOff% + QLim%
  ExCollect z_lim%
  IF QAgg% THEN
    ExKind$ = "COUNT" : ExCnt% = ExN% : ExN% = 0 : ExMsg$ = STR$(ExCnt%) : EXIT SUB
  ENDIF
  IF QOrd$ <> "" THEN ExSort
  ExSlice
  ExKind$ = "ROWS" : ExMsg$ = STR$(ExN%) + " row(s)"
END SUB

SUB ExInsert
  LOCAL z_r$, z_id$, z_i%
  FOR z_i% = 0 TO QFN% - 1
    IF QFld$(z_i%) = "_id" THEN z_id$ = QVal$(z_i%)
  NEXT
  IF z_id$ = "" THEN z_id$ = StNewId$()
  z_r$ = RcNew$(z_id$)
  FOR z_i% = 0 TO QFN% - 1
    IF QFld$(z_i%) <> "_id" AND z_r$ <> "" THEN z_r$ = RcSet$(z_r$, QFld$(z_i%), QVal$(z_i%), QVT%(z_i%))
  NEXT
  IF z_r$ = "" THEN ExErr$ = "record " + RcErr$ : EXIT SUB
  IF StWrite%(z_r$, 1) = 0 THEN ExErr$ = StErr$ : EXIT SUB
  ExMsg$ = "inserted " + z_id$
END SUB

' UPDATE and DELETE: match first, then write (offsets stay valid
' because the file is append-only).
SUB ExModify
  LOCAL z_i%, z_j%, z_n% = 0, z_r$, z_id$
  ExCollect -1
  FOR z_i% = 0 TO ExN% - 1
    z_r$ = StRead$(ExR%(z_i%))
    z_id$ = RcGet$(z_r$, "_id")
    IF QCmd$ = "DELETE" THEN
      IF StDelete%(z_id$) = 0 THEN EXIT FOR
    ELSE
      FOR z_j% = 0 TO QFN% - 1
        IF z_r$ <> "" THEN
          IF QVT%(z_j%) = 0 THEN z_r$ = RcDel$(z_r$, QFld$(z_j%)) ELSE z_r$ = RcSet$(z_r$, QFld$(z_j%), QVal$(z_j%), QVT%(z_j%))
        ENDIF
      NEXT
      IF z_r$ = "" THEN StErr$ = z_id$ + ": record " + RcErr$ : EXIT FOR
      IF StWrite%(z_r$, 2) = 0 THEN EXIT FOR
    ENDIF
    INC z_n%
  NEXT
  IF z_n% < ExN% THEN ExErr$ = STR$(z_n%) + " of " + STR$(ExN%) + " done; " + StErr$
  IF QCmd$ = "DELETE" THEN ExMsg$ = STR$(z_n%) + " deleted" ELSE ExMsg$ = STR$(z_n%) + " updated"
  ExN% = 0
END SUB

SUB ExDescribe
  LOCAL z_i%, z_s$
  ExKind$ = "TEXT"
  ExSay QCol$ + ": " + STR$(IxN%) + " records, " + STR$(MtDead%) + " dead lines"
  z_s$ = ""
  FOR z_i% = 0 TO SX_SLOTS - 1
    IF SxF$(z_i%) <> "" THEN z_s$ = z_s$ + " " + SxF$(z_i%)
  NEXT
  ExSay "indexes: _id" + z_s$
  FOR z_i% = 0 TO MtN% - 1
    z_s$ = "  " + MtF$(z_i%) + " " + MtT$(z_i%)
    IF SxSlot%(MtF$(z_i%)) >= 0 THEN z_s$ = z_s$ + " (indexed)"
    ExSay z_s$
  NEXT
  IF MtN% >= MT_MAX THEN ExSay "  (field list full)"
  ExMsg$ = STR$(MtN%) + " field(s)"
END SUB

' Run one statement
FUNCTION ExRun%(z_q$)
  LOCAL z_i%, z_ok%
  ExErr$ = "" : ExWarn$ = "" : ExMsg$ = "" : ExKind$ = "OK"
  ExN% = 0 : ExCnt% = 0 : ExOutN% = 0
  IF QParse%(z_q$) = 0 THEN ExErr$ = QErr$ : EXIT FUNCTION
  SELECT CASE QCmd$
    CASE "SELECT", "UPDATE", "DELETE"
      IF ExUse%(QCol$) = 0 THEN EXIT FUNCTION
      ExPlanPath
      IF QExplain% THEN
        ExExplain
      ELSEIF QCmd$ = "SELECT" THEN
        ExSelect
      ELSE
        ExModify
      ENDIF
    CASE "INSERT"
      IF ExUse%(QCol$) THEN ExInsert
    CASE "CREATE COLLECTION"
      IF StCreate%(QCol$) THEN ExMsg$ = "created " + QCol$ ELSE ExErr$ = StErr$
    CASE "DROP COLLECTION"
      IF StDrop%(QCol$) THEN ExMsg$ = "dropped " + QCol$ ELSE ExErr$ = StErr$
    CASE "CREATE INDEX", "DROP INDEX"
      IF ExUse%(QCol$) = 0 THEN EXIT FUNCTION
      IF QCmd$ = "CREATE INDEX" THEN z_ok% = StIndexAdd%(QFld$(0)) ELSE z_ok% = StIndexDrop%(QFld$(0))
      IF z_ok% THEN
        StFlush : ExMsg$ = "ok"
      ELSE
        ExErr$ = StErr$
      ENDIF
    CASE "SHOW"
      ExKind$ = "TEXT"
      FOR z_i% = 0 TO StList%() - 1 : ExSay StCat$(z_i%) : NEXT
      ExMsg$ = STR$(StCatN%) + " collection(s)"
    CASE "DESCRIBE"
      IF ExUse%(QCol$) THEN ExDescribe
    CASE "VACUUM"
      IF ExUse%(QCol$) THEN
        IF StVacuum%() THEN ExMsg$ = "vacuumed, " + STR$(IxN%) + " live" ELSE ExErr$ = StErr$
      ENDIF
  END SELECT
  ExRun% = (ExErr$ = "")
END FUNCTION

' ---------------- display helpers ------------------------------------

' Display text of field f$ ("" if missing)
FUNCTION ExVal$(z_rec$, z_f$)
  LOCAL z_x$ = RcGet$(z_rec$, z_f$)
  IF RcT% = 3 THEN z_x$ = LEFT$(z_x$, 1) + ".." + RIGHT$(z_x$, 1)
  ExVal$ = z_x$
END FUNCTION

' One result row as "f=v f=v" for the selected fields (or all)
FUNCTION ExRowText$(z_rec$)
  LOCAL z_s$, z_p$, z_i%, z_ip% = 1, z_k$, z_v$, z_t%
  IF QFN% = 0 THEN
    DO
      z_ip% = RcNext%(z_rec$, z_ip%, z_k$, z_v$, z_t%)
      IF z_ip% <= 0 THEN EXIT DO
      IF z_t% = 3 THEN z_v$ = LEFT$(z_v$, 1) + ".." + RIGHT$(z_v$, 1)
      z_p$ = z_k$ + "=" + z_v$ + " "
      IF LEN(z_s$) + LEN(z_p$) > 255 THEN EXIT DO
      z_s$ = z_s$ + z_p$
    LOOP
  ELSE
    FOR z_i% = 0 TO QFN% - 1
      z_p$ = QFld$(z_i%) + "=" + ExVal$(z_rec$, QFld$(z_i%)) + " "
      IF LEN(z_s$) + LEN(z_p$) > 255 THEN EXIT FOR
      z_s$ = z_s$ + z_p$
    NEXT
  ENDIF
  ExRowText$ = z_s$
END FUNCTION

' =====================================================================
' dbapi.bas - Public API of the PicoCalc DB library.
' Needs dbcore, dbstore, dbquery and dbexec (dblib.bas = all of them).
' Everything a script needs starts with "Db". Functions that change
' something return 1 on success, 0 on failure; then DbErr$() says why.
' Library uses file numbers #1-#3 and names starting with Rc Ix Sx St
' Mt Tk Q Ex Db (and constants RC_ IX_ SX_ ST_ MT_ TK_ QO_ QN_ QF_ QV_
' QNV_ EX_): avoid those in your own programs.
' =====================================================================

DIM DbE$                              ' last error message

' Reason the last call failed, or "" after a success
FUNCTION DbErr$()
  DbErr$ = DbE$
END FUNCTION

' Internal: record the outcome of a call (ok% 1/0, error text)
FUNCTION DbOk%(z_ok%, z_e$)
  IF z_ok% THEN DbE$ = "" ELSE DbE$ = z_e$
  DbOk% = (z_ok% <> 0)
END FUNCTION

' ---------------- setup and collections ------------------------------

' Use folder d$ for all collections (created if missing)
SUB DbInit z_d$
  LOCAL z_p$ = z_d$
  IF z_p$ <> "" AND RIGHT$(z_p$, 1) <> "/" THEN z_p$ = z_p$ + "/"
  IF StCol$ <> "" THEN StClose
  StDir$ = z_p$ : DbE$ = ""
  IF z_p$ = "" OR z_p$ = "/" THEN EXIT SUB
  ON ERROR SKIP 1
  MKDIR LEFT$(z_p$, LEN(z_p$) - 1)
END SUB

' Create an empty collection (letters, digits, _; up to 16 characters)
FUNCTION DbCreate%(z_c$)
  DbCreate% = DbOk%(StCreate%(z_c$), StErr$)
END FUNCTION

' Drop a collection and all its files
FUNCTION DbDrop%(z_c$)
  DbDrop% = DbOk%(StDrop%(z_c$), StErr$)
END FUNCTION

' Open collection c$ (closes the one open before). One open at a time.
FUNCTION DbOpen%(z_c$)
  IF StCol$ = z_c$ AND z_c$ <> "" THEN DbOpen% = DbOk%(1, "") : EXIT FUNCTION
  DbOpen% = DbOk%(StOpen%(z_c$), StErr$)
END FUNCTION

' Save the index and metadata and close. Call before your program ends.
SUB DbClose
  StClose
END SUB

' Save the index and metadata without closing
SUB DbFlush
  StFlush
END SUB

' Name of the open collection, or ""
FUNCTION DbCurrent$()
  DbCurrent$ = StCol$
END FUNCTION

' Warning from the last open ("" if none), e.g. "repaired torn last line"
FUNCTION DbWarn$()
  DbWarn$ = StWarn$
END FUNCTION

' Number of collections; names via DbListName$(0 .. n-1), sorted
FUNCTION DbList%()
  DbList% = StList%()
END FUNCTION

' Name of collection i% from the last DbList% (0-based, sorted)
FUNCTION DbListName$(z_i%)
  IF z_i% >= 0 AND z_i% < StCatN% THEN DbListName$ = StCat$(z_i%)
END FUNCTION

' ---------------- reading records (open collection) ------------------

' Number of records in the open collection
FUNCTION DbCount%()
  DbCount% = IxN%
END FUNCTION

' Record at position i% (0 .. DbCount%()-1) in _id order
FUNCTION DbAt$(z_i%)
  IF z_i% < 0 OR z_i% >= IxN% THEN DbE$ = "position out of range" : EXIT FUNCTION
  DbAt$ = StAt$(z_i%) : DbE$ = ""
END FUNCTION

' Record with _id id$, or "" (DbErr$() = "not found")
FUNCTION DbGet$(z_id$)
  DbGet$ = StFetch$(z_id$)
  DbE$ = StErr$
END FUNCTION

' 1 if a record with this _id exists (an index lookup, no file read)
FUNCTION DbExists%(z_id$)
  DbExists% = (IxGet%(z_id$) > 0)
END FUNCTION

' Position of id$ in _id order (for DbAt$), or -1
FUNCTION DbPos%(z_id$)
  LOCAL z_i% = IxBound%(IxK$(), IxN%, z_id$, 0)
  DbPos% = -1
  IF z_i% < IxN% THEN
    IF IxK$(z_i%) = z_id$ THEN DbPos% = z_i%
  ENDIF
END FUNCTION

' ---------------- writing records ------------------------------------

' Add a new record (its _id must not exist)
FUNCTION DbInsert%(z_rec$)
  DbInsert% = DbOk%(StWrite%(z_rec$, 1), StErr$)
END FUNCTION

' Replace an existing record (same _id)
FUNCTION DbUpdate%(z_rec$)
  DbUpdate% = DbOk%(StWrite%(z_rec$, 2), StErr$)
END FUNCTION

' Insert or replace
FUNCTION DbPut%(z_rec$)
  DbPut% = DbOk%(StWrite%(z_rec$, 0), StErr$)
END FUNCTION

' Delete a record
FUNCTION DbDelete%(z_id$)
  DbDelete% = DbOk%(StDelete%(z_id$), StErr$)
END FUNCTION

' Next free automatic _id ("000001", "000002", ...)
FUNCTION DbNewId$()
  DbNewId$ = StNewId$()
END FUNCTION

' Change one field of a stored record
FUNCTION DbSetText%(z_id$, z_f$, z_v$)
  DbSetText% = DbOk%(StSetField%(z_id$, z_f$, z_v$, 1), StErr$)
END FUNCTION

' Set one field of a stored record to a number
FUNCTION DbSetNum%(z_id$, z_f$, z_n!)
  DbSetNum% = DbOk%(StSetField%(z_id$, z_f$, DbNumStr$(z_n!), 2), StErr$)
END FUNCTION

' Literal: a number as text ("1.5"), true, false or null
FUNCTION DbSetRaw%(z_id$, z_f$, z_lit$)
  DbSetRaw% = DbOk%(StSetField%(z_id$, z_f$, z_lit$, 2), StErr$)
END FUNCTION

' Remove one field from a stored record
FUNCTION DbUnset%(z_id$, z_f$)
  DbUnset% = DbOk%(StSetField%(z_id$, z_f$, "", 0), StErr$)
END FUNCTION

' ---------------- record strings (no file access) --------------------
' A record is a JSON line such as {"_id":"p1","name":"Ann","age":34}.

' A new record string holding only _id
FUNCTION DbNew$(z_id$)
  DbNew$ = RcNew$(z_id$)
END FUNCTION

' Number as JSON text; whole numbers keep all digits
FUNCTION DbNumStr$(z_n!)
  LOCAL z_i%
  DbNumStr$ = STR$(z_n!)
  IF z_n! < 1E15 AND z_n! > -1E15 THEN
    IF z_n! = INT(z_n!) THEN z_i% = z_n! : DbNumStr$ = STR$(z_i%)
  ENDIF
END FUNCTION

' Value of field f$ as text ("" if missing; check DbHas%)
FUNCTION DbStr$(z_rec$, z_f$)
  DbStr$ = RcGet$(z_rec$, z_f$)
END FUNCTION

' Value of field f$ as a number (0 if missing or not a number)
FUNCTION DbNum!(z_rec$, z_f$)
  LOCAL z_v$ = RcGet$(z_rec$, z_f$)
  IF RcT% = 2 AND RcIsNum%(z_v$) THEN DbNum! = VAL(z_v$)
END FUNCTION

' 1 if rec$ has field f$
FUNCTION DbHas%(z_rec$, z_f$)
  LOCAL z_v$ = RcGet$(z_rec$, z_f$)
  DbHas% = RcFound%
END FUNCTION

' Kind of field f$: "S" text, "N" number, "L" true/false/null,
' "O" list/object (read-only), "" missing
FUNCTION DbKind$(z_rec$, z_f$)
  LOCAL z_v$ = RcGet$(z_rec$, z_f$)
  IF RcFound% = 0 THEN EXIT FUNCTION
  SELECT CASE RcT%
    CASE 1 : DbKind$ = "S"
    CASE 3 : DbKind$ = "O"
    CASE ELSE
      IF RcIsNum%(z_v$) THEN DbKind$ = "N" ELSE DbKind$ = "L"
  END SELECT
END FUNCTION

' Copies of rec$ with one field set or removed ("" + DbErr$ if the
' result would be over 255 characters)
FUNCTION DbWithText$(z_rec$, z_f$, z_v$)
  DbWithText$ = RcSet$(z_rec$, z_f$, z_v$, 1) : DbE$ = RcErr$
END FUNCTION

' Copy of rec$ with field f$ set to a number
FUNCTION DbWithNum$(z_rec$, z_f$, z_n!)
  DbWithNum$ = RcSet$(z_rec$, z_f$, DbNumStr$(z_n!), 2) : DbE$ = RcErr$
END FUNCTION

' Copy of rec$ with field f$ set to a literal: number text, true, false or null
FUNCTION DbWithRaw$(z_rec$, z_f$, z_lit$)
  DbWithRaw$ = RcSet$(z_rec$, z_f$, z_lit$, 2) : DbE$ = RcErr$
END FUNCTION

' Number, true, false or null if v$ looks like one, otherwise text
' (handy when importing CSV or serial data)
FUNCTION DbWithAuto$(z_rec$, z_f$, z_v$)
  IF RcLit%(z_v$) THEN DbWithAuto$ = RcSet$(z_rec$, z_f$, z_v$, 2) ELSE DbWithAuto$ = RcSet$(z_rec$, z_f$, z_v$, 1)
  DbE$ = RcErr$
END FUNCTION

' Copy of rec$ without field f$
FUNCTION DbWithout$(z_rec$, z_f$)
  DbWithout$ = RcDel$(z_rec$, z_f$)
END FUNCTION

' 1 if rec$ is a well-formed record line
FUNCTION DbValid%(z_rec$)
  DbValid% = (RcCheck%(z_rec$) >= 0)
END FUNCTION

' Number of fields in rec$ (including _id)
FUNCTION DbFieldCount%(z_rec$)
  DbFieldCount% = MAX(0, RcCheck%(z_rec$))
END FUNCTION

' Name / value of the i%-th field (0-based) of rec$
FUNCTION DbFieldName$(z_rec$, z_i%)
  LOCAL z_k$, z_v$
  IF DbNth%(z_rec$, z_i%, z_k$, z_v$) THEN DbFieldName$ = z_k$
END FUNCTION

' Value of the i%-th field of rec$, as text
FUNCTION DbFieldValue$(z_rec$, z_i%)
  LOCAL z_k$, z_v$
  IF DbNth%(z_rec$, z_i%, z_k$, z_v$) THEN DbFieldValue$ = z_v$
END FUNCTION

' Internal: find the i%-th field; name and value returned in k$ and v$
FUNCTION DbNth%(z_rec$, z_i%, z_k$, z_v$)
  LOCAL z_ip% = 1, z_n% = 0, z_t%
  DO
    z_ip% = RcNext%(z_rec$, z_ip%, z_k$, z_v$, z_t%)
    IF z_ip% <= 0 THEN EXIT FUNCTION
    IF z_n% = z_i% THEN DbNth% = 1 : EXIT FUNCTION
    INC z_n%
  LOOP
END FUNCTION

' ---------------- queries --------------------------------------------

' Run one SQL-like statement (see the user guide). Then:
'   SELECT        DbRows%(), DbRow$(i)  (rows stay readable until VACUUM)
'   COUNT(*)      DbResult%()
'   SHOW/DESCRIBE/EXPLAIN  DbLines%(), DbLine$(i)
'   others        DbMsg$()  e.g. "3 updated", "inserted 000012"
' The collection named in the statement becomes the open one.
FUNCTION DbQuery%(z_sql$)
  DbQuery% = DbOk%(ExRun%(z_sql$), ExErr$)
END FUNCTION

' Number of rows from the last SELECT
FUNCTION DbRows%()
  DbRows% = ExN%
END FUNCTION

' Row i% of the last SELECT: the record as it was when the query ran
FUNCTION DbRow$(z_i%)
  IF z_i% >= 0 AND z_i% < ExN% THEN DbRow$ = StRead$(ExR%(z_i%))
END FUNCTION

' Result of the last SELECT COUNT(*)
FUNCTION DbResult%()
  DbResult% = ExCnt%
END FUNCTION

' Number of text lines from the last SHOW, DESCRIBE or EXPLAIN
FUNCTION DbLines%()
  DbLines% = ExOutN%
END FUNCTION

' Text line i% from the last SHOW, DESCRIBE or EXPLAIN
FUNCTION DbLine$(z_i%)
  IF z_i% >= 0 AND z_i% < ExOutN% THEN DbLine$ = ExOut$(z_i%)
END FUNCTION

' Summary of the last statement, e.g. "3 updated", "inserted 000012"
FUNCTION DbMsg$()
  DbMsg$ = ExMsg$
END FUNCTION

' ---------------- metadata (open collection) -------------------------

' Fields seen in the collection: DbFields%(), then for i = 0 .. n-1
' DbFieldInfo$(i) = name and DbFieldType$(i) = S N L O or X (mixed)
FUNCTION DbFields%()
  DbFields% = MtN%
END FUNCTION

' Name of known field i% of the open collection
FUNCTION DbFieldInfo$(z_i%)
  IF z_i% >= 0 AND z_i% < MtN% THEN DbFieldInfo$ = MtF$(z_i%)
END FUNCTION

' Kind of known field i%: S, N, L, O or X (mixed)
FUNCTION DbFieldType$(z_i%)
  IF z_i% >= 0 AND z_i% < MtN% THEN DbFieldType$ = MtT$(z_i%)
END FUNCTION

' Indexed fields as a comma list, e.g. "age,name"
FUNCTION DbIndexes$()
  LOCAL z_i%, z_s$
  FOR z_i% = 0 TO SX_SLOTS - 1
    IF SxF$(z_i%) <> "" THEN
      IF z_s$ <> "" THEN z_s$ = z_s$ + ","
      z_s$ = z_s$ + SxF$(z_i%)
    ENDIF
  NEXT
  DbIndexes$ = z_s$
END FUNCTION

' 1 if field f$ is indexed
FUNCTION DbIsIndexed%(z_f$)
  DbIsIndexed% = (SxSlot%(z_f$) >= 0)
END FUNCTION

' Index field f$ (up to 4 per collection); saved at once
FUNCTION DbIndexAdd%(z_f$)
  DbIndexAdd% = DbOk%(StIndexAdd%(z_f$), StErr$)
  IF DbIndexAdd% THEN StFlush
END FUNCTION

' Remove the index on field f$; saved at once
FUNCTION DbIndexDrop%(z_f$)
  DbIndexDrop% = DbOk%(StIndexDrop%(z_f$), StErr$)
  IF DbIndexDrop% THEN StFlush
END FUNCTION

' Superseded/deleted lines in the file (VACUUM removes them)
FUNCTION DbDead%()
  DbDead% = MtDead%
END FUNCTION

' Rewrite the data file without dead lines
FUNCTION DbVacuum%()
  DbVacuum% = DbOk%(StVacuum%(), StErr$)
END FUNCTION

' Your own collection properties, kept in the .meta file (all of them
' together at most about 230 characters). Saved by DbFlush / DbClose.
FUNCTION DbMetaGet$(z_k$)
  DbMetaGet$ = RcGet$(MtUser$, z_k$)
END FUNCTION

' Set a property (text); saved by DbFlush / DbClose
FUNCTION DbMetaSet%(z_k$, z_v$)
  LOCAL z_r$
  IF StCol$ = "" THEN DbMetaSet% = DbOk%(0, "no collection open") : EXIT FUNCTION
  IF LEFT$(z_k$, 1) = "_" OR z_k$ = "" THEN DbMetaSet% = DbOk%(0, "bad property name") : EXIT FUNCTION
  z_r$ = RcSet$(MtUser$, z_k$, z_v$, 1)
  IF z_r$ = "" THEN DbMetaSet% = DbOk%(0, RcErr$) : EXIT FUNCTION
  MtUser$ = z_r$ : MtDirty% = 1
  DbMetaSet% = DbOk%(1, "")
END FUNCTION

' Remove a property
FUNCTION DbMetaDel%(z_k$)
  IF StCol$ = "" THEN DbMetaDel% = DbOk%(0, "no collection open") : EXIT FUNCTION
  IF LEFT$(z_k$, 1) = "_" THEN DbMetaDel% = DbOk%(0, "bad property name") : EXIT FUNCTION
  MtUser$ = RcDel$(MtUser$, z_k$) : MtDirty% = 1
  DbMetaDel% = DbOk%(1, "")
END FUNCTION

' Property names: DbMetaName$(0), (1) ... until ""
FUNCTION DbMetaName$(z_i%)
  DbMetaName$ = DbFieldName$(MtUser$, z_i% + 1)
END FUNCTION

