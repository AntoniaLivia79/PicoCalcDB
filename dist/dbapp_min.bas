OPTION EXPLICIT
OPTION DEFAULT NONE
CONST IX_MAX = 1000
CONST IX_KLEN = 16
CONST SX_MAX = 1000
CONST SX_SLOTS = 4
CONST SX_PW = 11
CONST RC_MAXLEN = 255
DIM RcErr$
DIM RcFound%, RcT%
DIM RcKS%, RcVS%, RcVE%
DIM IxK$(IX_MAX - 1) LENGTH IX_KLEN
DIM IxO%(IX_MAX - 1)
DIM IxN%, IxErr$, IxBad%, IxLong%
DIM SxF$(SX_SLOTS - 1) LENGTH 32
DIM SxV$(SX_MAX - 1) LENGTH SX_PW + 2
DIM SxO%(SX_MAX - 1), SxN%
FUNCTION RcSkip%(r$, i%)
LOCAL j% = i%
DO WHILE j% <= LEN(r$)
IF ASC(MID$(r$, j%, 1)) > 32 THEN EXIT DO
INC j%
LOOP
RcSkip% = j%
END FUNCTION
FUNCTION RcNext%(r$, ip%, k$, v$, t%)
LOCAL i% = ip%, n% = LEN(r$), e%, c$, s$, q%, b%, a%, d%, part%
DO WHILE i% <= n%
IF ASC(MID$(r$, i%, 1)) > 32 THEN EXIT DO
INC i%
LOOP
c$ = MID$(r$, i%, 1)
IF ip% = 1 THEN
IF c$ <> "{" THEN RcNext% = -1 : EXIT FUNCTION
ELSEIF c$ = "}" THEN
RcNext% = 0 : EXIT FUNCTION
ELSEIF c$ <> "," THEN
RcNext% = -1 : EXIT FUNCTION
ENDIF
INC i%
DO WHILE i% <= n%
IF ASC(MID$(r$, i%, 1)) > 32 THEN EXIT DO
INC i%
LOOP
c$ = MID$(r$, i%, 1)
IF c$ = "}" AND ip% = 1 THEN RcNext% = 0 : EXIT FUNCTION
IF c$ <> CHR$(34) THEN RcNext% = -1 : EXIT FUNCTION
RcKS% = i%
part% = 1
DO
s$ = "" : e% = i% + 1
DO
q% = INSTR(e%, r$, CHR$(34))
IF q% = 0 THEN RcNext% = -1 : EXIT FUNCTION
b% = INSTR(e%, r$, "\")
IF b% = 0 OR b% > q% THEN s$ = s$ + MID$(r$, e%, q% - e%) : i% = q% + 1 : EXIT DO
s$ = s$ + MID$(r$, e%, b% - e%)
c$ = MID$(r$, b% + 1, 1)
e% = b% + 2
SELECT CASE c$
CASE "n" : s$ = s$ + CHR$(10)
CASE "t" : s$ = s$ + CHR$(9)
CASE "r" : s$ = s$ + CHR$(13)
CASE "b" : s$ = s$ + CHR$(8)
CASE "f" : s$ = s$ + CHR$(12)
CASE "u"
a% = VAL("&H" + MID$(r$, b% + 2, 4))
IF a% > 255 THEN s$ = s$ + "?" ELSE s$ = s$ + CHR$(a%)
e% = b% + 6
CASE ELSE : s$ = s$ + c$
END SELECT
LOOP
IF part% = 2 THEN v$ = s$ : t% = 1 : EXIT DO
k$ = s$
DO WHILE i% <= n%
IF ASC(MID$(r$, i%, 1)) > 32 THEN EXIT DO
INC i%
LOOP
IF MID$(r$, i%, 1) <> ":" THEN RcNext% = -1 : EXIT FUNCTION
INC i%
DO WHILE i% <= n%
IF ASC(MID$(r$, i%, 1)) > 32 THEN EXIT DO
INC i%
LOOP
RcVS% = i%
c$ = MID$(r$, i%, 1)
IF c$ = CHR$(34) THEN
part% = 2
ELSEIF c$ = "{" OR c$ = "[" THEN
d% = 0
DO WHILE i% <= n%
c$ = MID$(r$, i%, 1)
IF c$ = CHR$(34) THEN
INC i%
DO WHILE i% <= n%
c$ = MID$(r$, i%, 1)
IF c$ = "\" THEN
INC i%, 2
ELSEIF c$ = CHR$(34) THEN
EXIT DO
ELSE
INC i%
ENDIF
LOOP
IF i% > n% THEN RcNext% = -1 : EXIT FUNCTION
INC i%
ELSE
IF c$ = "{" OR c$ = "[" THEN INC d%
IF c$ = "}" OR c$ = "]" THEN INC d%, -1
INC i%
IF d% = 0 THEN EXIT DO
ENDIF
LOOP
IF d% <> 0 THEN RcNext% = -1 : EXIT FUNCTION
v$ = MID$(r$, RcVS%, i% - RcVS%) : t% = 3
EXIT DO
ELSE
e% = i%
DO WHILE e% <= n%
c$ = MID$(r$, e%, 1)
IF c$ = "," OR c$ = "}" OR ASC(c$) <= 32 THEN EXIT DO
INC e%
LOOP
IF e% = i% THEN RcNext% = -1 : EXIT FUNCTION
v$ = MID$(r$, i%, e% - i%) : t% = 2 : i% = e%
EXIT DO
ENDIF
LOOP
RcVE% = i%
RcNext% = i%
END FUNCTION
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
FUNCTION RcCheck%(r$)
LOCAL ip% = 1, n% = 0, fk$, fv$, ft%
DO
ip% = RcNext%(r$, ip%, fk$, fv$, ft%)
IF ip% <= 0 THEN EXIT DO
INC n%
LOOP
IF ip% < 0 THEN RcCheck% = -1 ELSE RcCheck% = n%
END FUNCTION
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
FUNCTION RcLit%(s$)
RcLit% = RcIsNum%(s$) OR s$ = "true" OR s$ = "false" OR s$ = "null"
END FUNCTION
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
FUNCTION RcNew$(id$)
RcNew$ = "{" + RcEnc$("_id") + ":" + RcEnc$(id$) + "}"
END FUNCTION
FUNCTION RcIsDel%(r$)
LOCAL x$
IF INSTR(r$, CHR$(34) + "_del" + CHR$(34)) = 0 THEN EXIT FUNCTION
x$ = RcGet$(r$, "_del")
RcIsDel% = RcFound% AND x$ <> "0" AND x$ <> "false"
END FUNCTION
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
FUNCTION IxGet%(k$)
LOCAL i% = IxBound%(IxK$(), IxN%, k$, 0)
IxGet% = -1
IF i% < IxN% THEN
IF IxK$(i%) = k$ THEN IxGet% = IxO%(i%)
ENDIF
END FUNCTION
FUNCTION IxKeyOk%(k$)
IxKeyOk% = 0
IF LEN(k$) = 0 OR LEN(k$) > IX_KLEN THEN IxErr$ = "bad key length" : EXIT FUNCTION
IF INSTR(k$, CHR$(10)) OR INSTR(k$, CHR$(13)) OR INSTR(k$, CHR$(9)) THEN
IxErr$ = "bad key char" : EXIT FUNCTION
ENDIF
IxKeyOk% = 1
END FUNCTION
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
FUNCTION SxSlot%(fn$)
LOCAL s%
SxSlot% = -1
FOR s% = 0 TO SX_SLOTS - 1
IF SxF$(s%) = fn$ AND fn$ <> "" THEN SxSlot% = s% : EXIT FUNCTION
NEXT
END FUNCTION
FUNCTION SxEnc$(s%, v$, t%)
LOCAL n!, e%
IF t% = 2 AND v$ <> "true" AND v$ <> "false" AND v$ <> "null" THEN
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
SxAdd% = SxAddK%(SxEnc$(s%, v$, t%), off%)
END FUNCTION
FUNCTION SxAddK%(k$, off%)
LOCAL i%, j%
IF SxN% >= SX_MAX THEN IxErr$ = "sec index full" : EXIT FUNCTION
i% = IxBound%(SxV$(), SxN%, k$, 1)
FOR j% = SxN% TO i% + 1 STEP -1
SxV$(j%) = SxV$(j% - 1) : SxO%(j%) = SxO%(j% - 1)
NEXT
SxV$(i%) = k$ : SxO%(i%) = off% : INC SxN%
SxAddK% = 1
END FUNCTION
FUNCTION SxRemove%(s%, v$, t%, off%)
SxRemove% = SxRemoveK%(SxEnc$(s%, v$, t%), off%)
END FUNCTION
FUNCTION SxRemoveK%(k$, off%)
LOCAL i%, j%
i% = IxBound%(SxV$(), SxN%, k$, 0)
DO WHILE i% < SxN%
IF SxV$(i%) <> k$ THEN EXIT DO
IF SxO%(i%) = off% THEN
FOR j% = i% TO SxN% - 2
SxV$(j%) = SxV$(j% + 1) : SxO%(j%) = SxO%(j% + 1)
NEXT
INC SxN%, -1 : SxRemoveK% = 1 : EXIT FUNCTION
ENDIF
INC i%
LOOP
END FUNCTION
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
IF RcFound% THEN v$ = STR$(SxRemoveK%(SxEnc$(s%, v$, ft%), oo%))
ENDIF
NEXT
ENDIF
IF INSTR(rec$, CHR$(34) + "_del" + CHR$(34)) THEN
v$ = RcGet$(rec$, "_del")
IF RcFound% AND v$ <> "0" AND v$ <> "false" THEN v$ = STR$(IxRemove%(id$)) : IxApply% = 1 : EXIT FUNCTION
ENDIF
IF IxPut%(id$, off%) = 0 THEN EXIT FUNCTION
FOR s% = 0 TO SX_SLOTS - 1
IF SxF$(s%) <> "" THEN
v$ = RcGet$(rec$, SxF$(s%)) : ft% = RcT%
IF RcFound% THEN
IF SxAddK%(SxEnc$(s%, v$, ft%), off%) = 0 THEN EXIT FUNCTION
ENDIF
ENDIF
NEXT
IxApply% = 1
END FUNCTION
FUNCTION IxLine$(fnum%)
LOCAL r$ = CHR$(1)
IxLong% = 0
ON ERROR SKIP 1
LINE INPUT #fnum%, r$
IF r$ = CHR$(1) THEN IxLong% = 1
IxLine$ = r$
END FUNCTION
FUNCTION IxReadAt$(fnum%, off%)
LOCAL r$ = CHR$(1)
SEEK #fnum%, off%
ON ERROR SKIP 1
LINE INPUT #fnum%, r$
IF r$ = CHR$(1) THEN r$ = ""
IxReadAt$ = r$
END FUNCTION
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
FUNCTION IxScan%(fnum%, from%)
LOCAL r$, id$, off%, frag% = 0
IF from% > LOF(#fnum%) THEN IxScan% = 1 : EXIT FUNCTION
SEEK #fnum%, from%
DO WHILE NOT EOF(#fnum%)
off% = LOC(#fnum%)
r$ = IxLine$(fnum%)
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
IxO%(IxN%) = off%
IF INSTR(r$, CHR$(34) + "_del" + CHR$(34)) THEN
id$ = RcGet$(r$, "_del")
IF RcFound% AND id$ <> "0" AND id$ <> "false" THEN IxO%(IxN%) = -off%
ENDIF
INC IxN%
ELSE
INC IxBad%
ENDIF
ENDIF
LOOP
IxCompact
IxScan% = 1
END FUNCTION
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
CONST ST_RD = 1, ST_WR = 2, ST_TMP = 3
CONST MT_MAX = 24
CONST ST_CATMAX = 32
DIM StDir$ = "B:/db/"
DIM StCol$, StErr$, StWarn$
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
SUB StRdClose
IF StRdOpen% THEN CLOSE #ST_RD : StRdOpen% = 0
END SUB
FUNCTION StRead$(off%)
IF StRdOpen% = 0 THEN
OPEN StPath$(".jsonl") FOR INPUT AS #ST_RD : StRdOpen% = 1
ENDIF
StRead$ = IxReadAt$(ST_RD, off%)
END FUNCTION
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
FUNCTION StCount%()
StCount% = IxN%
END FUNCTION
FUNCTION StAt$(i%)
IF i% >= 0 AND i% < IxN% THEN StAt$ = StRead$(IxO%(i%))
END FUNCTION
FUNCTION StFetch$(id$)
LOCAL o% = IxGet%(id$)
StErr$ = ""
IF o% < 0 THEN StErr$ = "not found" ELSE StFetch$ = StRead$(o%)
END FUNCTION
FUNCTION StAppend%(r$)
StRdClose
OPEN StPath$(".jsonl") FOR APPEND AS #ST_WR
StAppend% = LOC(#ST_WR)
PRINT #ST_WR, r$
CLOSE #ST_WR
END FUNCTION
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
FUNCTION StSetField%(id$, f$, v$, t%)
LOCAL r$
IF LEFT$(f$, 1) = "_" THEN StErr$ = "reserved field" : EXIT FUNCTION
r$ = StFetch$(id$)
IF StErr$ <> "" THEN EXIT FUNCTION
IF t% = 0 THEN r$ = RcDel$(r$, f$) ELSE r$ = RcSet$(r$, f$, v$, t%)
IF r$ = "" THEN StErr$ = RcErr$ : EXIT FUNCTION
StSetField% = StWrite%(r$, 2)
END FUNCTION
FUNCTION StNewId$()
LOCAL k$
DO
INC MtSeq% : MtDirty% = 1
k$ = STR$(MtSeq%, 6, 0, "0")
LOOP UNTIL IxGet%(k$) < 0
StNewId$ = k$
END FUNCTION
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
CONST TK_MAX = 128, QN_MAX = 24, QF_MAX = 16, QV_LEN = 128, QNV_LEN = 64
CONST TK_END = 0, TK_ID = 1, TK_NUM = 2, TK_STR = 3, TK_SYM = 4, TK_QID = 5
CONST QO_EQ = 1, QO_NE = 2, QO_LT = 3, QO_LE = 4, QO_GT = 5, QO_GE = 6
CONST QO_LIKE = 7, QO_NULL = 8, QO_NNULL = 9
CONST QO_AND = 20, QO_OR = 21, QO_NOT = 22
DIM TkT%(TK_MAX - 1), TkP%(TK_MAX - 1), TkL%(TK_MAX - 1), TkN%
DIM QText$, QErr$, QPos%
DIM QCmd$, QCol$, QExplain%, QAgg%, QFN%, QOrd$, QDesc%, QLim%, QOff%
DIM QFld$(QF_MAX - 1) LENGTH 24
DIM QVal$(QF_MAX - 1) LENGTH QV_LEN, QVT%(QF_MAX - 1)
DIM QNN%, QnOp%(QN_MAX - 1), QnT%(QN_MAX - 1), QnTop%(QN_MAX - 1)
DIM QnF$(QN_MAX - 1) LENGTH 24, QnV$(QN_MAX - 1) LENGTH QNV_LEN
DIM QRES$ = " SELECT FROM WHERE AND OR NOT LIKE IS NULL ORDER BY LIMIT OFFSET ASC DESC"
QRES$ = QRES$ + " INSERT INTO VALUES UPDATE SET UNSET DELETE CREATE DROP COLLECTION"
QRES$ = QRES$ + " INDEX ON SHOW COLLECTIONS DESCRIBE VACUUM COUNT TRUE FALSE EXPLAIN "
DIM QIDCH$ = "ABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789"
FUNCTION QLex%(s$)
LOCAL i% = 1, j%, n% = LEN(s$), c$, d$
QText$ = s$ : TkN% = 0
DO
DO WHILE i% <= n%
IF ASC(MID$(s$, i%, 1)) > 32 THEN EXIT DO
INC i%
LOOP
IF TkN% >= TK_MAX THEN QErr$ = "query too complex" : EXIT FUNCTION
TkP%(TkN%) = i% : TkL%(TkN%) = 0
IF i% > n% THEN TkT%(TkN%) = TK_END : INC TkN% : QLex% = 1 : EXIT FUNCTION
c$ = MID$(s$, i%, 1) : d$ = MID$(s$, i% + 1, 1) : j% = i% + 1
IF INSTR(LEFT$(QIDCH$, 27), UCASE$(c$)) > 0 THEN
DO WHILE j% <= n%
IF INSTR(QIDCH$, UCASE$(MID$(s$, j%, 1))) = 0 THEN EXIT DO
INC j%
LOOP
TkT%(TkN%) = TK_ID
ELSEIF INSTR("0123456789", c$) > 0 OR (c$ = "-" AND d$ <> "" AND INSTR("0123456789", d$) > 0) THEN
DO WHILE j% <= n%
c$ = MID$(s$, j%, 1)
IF INSTR("0123456789.eE", c$) = 0 THEN
IF INSTR("+-", c$) = 0 OR INSTR("eE", MID$(s$, j% - 1, 1)) = 0 THEN EXIT DO
ENDIF
INC j%
LOOP
IF RcIsNum%(MID$(s$, i%, j% - i%)) = 0 THEN QErr$ = "bad number at col " + STR$(i%) : EXIT FUNCTION
TkT%(TkN%) = TK_NUM
ELSEIF c$ = "'" THEN
DO
IF j% > n% THEN QErr$ = "unclosed string at col " + STR$(i%) : EXIT FUNCTION
j% = INSTR(j%, s$, "'")
IF j% = 0 THEN QErr$ = "unclosed string at col " + STR$(i%) : EXIT FUNCTION
IF MID$(s$, j% + 1, 1) <> "'" THEN EXIT DO
INC j%, 2
LOOP
INC j%
TkT%(TkN%) = TK_STR
ELSEIF c$ = CHR$(34) THEN
j% = 0
IF i% < n% THEN j% = INSTR(i% + 1, s$, CHR$(34))
IF j% = 0 THEN QErr$ = "unclosed name at col " + STR$(i%) : EXIT FUNCTION
IF j% = i% + 1 THEN QErr$ = "empty name at col " + STR$(i%) : EXIT FUNCTION
INC j%
TkT%(TkN%) = TK_QID
ELSE
d$ = c$ + d$
IF d$ = "<=" OR d$ = ">=" OR d$ = "<>" OR d$ = "!=" THEN
j% = i% + 2
ELSEIF INSTR("=<>(),*;", c$) = 0 THEN
QErr$ = "unexpected '" + c$ + "' at col " + STR$(i%) : EXIT FUNCTION
ENDIF
TkT%(TkN%) = TK_SYM
ENDIF
TkL%(TkN%) = j% - i% : INC TkN% : i% = j%
LOOP
END FUNCTION
FUNCTION TkRaw$(i%)
TkRaw$ = MID$(QText$, TkP%(i%), TkL%(i%))
END FUNCTION
SUB QFail m$
IF QErr$ = "" THEN QErr$ = m$ + " at col " + STR$(TkP%(QPos%))
END SUB
FUNCTION QKw%(kwd$)
IF QErr$ <> "" THEN EXIT FUNCTION
IF TkT%(QPos%) = TK_ID THEN
IF UCASE$(MID$(QText$, TkP%(QPos%), TkL%(QPos%))) = kwd$ THEN INC QPos% : QKw% = 1
ENDIF
END FUNCTION
FUNCTION QNeedKw%(kwd$)
QNeedKw% = QKw%(kwd$)
IF QNeedKw% = 0 THEN QFail "expected " + kwd$
END FUNCTION
FUNCTION QSym%(s$)
LOCAL r$
IF QErr$ <> "" THEN EXIT FUNCTION
IF TkT%(QPos%) = TK_SYM THEN
r$ = MID$(QText$, TkP%(QPos%), TkL%(QPos%))
IF r$ = "!=" THEN r$ = "<>"
IF r$ = s$ THEN INC QPos% : QSym% = 1
ENDIF
END FUNCTION
FUNCTION QNeedSym%(s$)
QNeedSym% = QSym%(s$)
IF QNeedSym% = 0 THEN QFail "expected " + s$
END FUNCTION
FUNCTION QName$()
LOCAL r$
IF QErr$ <> "" THEN EXIT FUNCTION
r$ = MID$(QText$, TkP%(QPos%), TkL%(QPos%))
IF TkT%(QPos%) = TK_QID THEN
r$ = MID$(r$, 2, LEN(r$) - 2)
ELSEIF TkT%(QPos%) = TK_ID THEN
IF INSTR(QRES$, " " + UCASE$(r$) + " ") THEN QFail "reserved word '" + r$ + "' (quote it)" : EXIT FUNCTION
ELSE
QFail "expected a field name" : EXIT FUNCTION
ENDIF
IF LEN(r$) > 24 THEN QFail "name too long" : EXIT FUNCTION
INC QPos%
QName$ = r$
END FUNCTION
FUNCTION QColName$()
LOCAL r$
IF QErr$ <> "" THEN EXIT FUNCTION
r$ = MID$(QText$, TkP%(QPos%), TkL%(QPos%))
IF TkT%(QPos%) <> TK_ID OR INSTR(QRES$, " " + UCASE$(r$) + " ") > 0 THEN
QFail "expected a collection name" : EXIT FUNCTION
ENDIF
IF LEN(r$) > 16 THEN QFail "collection name too long" : EXIT FUNCTION
INC QPos%
QColName$ = r$
END FUNCTION
FUNCTION QValue%(v$, t%)
LOCAL r$, i%
IF QErr$ <> "" THEN EXIT FUNCTION
r$ = MID$(QText$, TkP%(QPos%), TkL%(QPos%)) : v$ = ""
SELECT CASE TkT%(QPos%)
CASE TK_STR
r$ = MID$(r$, 2, LEN(r$) - 2) : t% = 1
DO
i% = INSTR(r$, "''")
IF i% = 0 THEN EXIT DO
v$ = v$ + LEFT$(r$, i%) : r$ = MID$(r$, i% + 2)
LOOP
v$ = v$ + r$
CASE TK_NUM
v$ = r$ : t% = 2
CASE TK_ID
v$ = LCASE$(r$) : t% = 2
IF v$ <> "true" AND v$ <> "false" AND v$ <> "null" THEN QFail "expected a value" : EXIT FUNCTION
CASE ELSE
QFail "expected a value" : EXIT FUNCTION
END SELECT
INC QPos%
QValue% = 1
END FUNCTION
FUNCTION QInt%()
LOCAL r$ = MID$(QText$, TkP%(QPos%), TkL%(QPos%)), i%
IF QErr$ <> "" THEN EXIT FUNCTION
IF TkT%(QPos%) = TK_NUM AND LEN(r$) <= 6 THEN
FOR i% = 1 TO LEN(r$)
IF INSTR("0123456789", MID$(r$, i%, 1)) = 0 THEN EXIT FOR
NEXT
IF i% > LEN(r$) THEN QInt% = VAL(r$) : INC QPos% : EXIT FUNCTION
ENDIF
QFail "expected a whole number"
END FUNCTION
FUNCTION QHas%(f$)
LOCAL i%
FOR i% = 0 TO QFN% - 1
IF QFld$(i%) = f$ THEN QHas% = 1 : EXIT FUNCTION
NEXT
END FUNCTION
FUNCTION QNames%(dup%)
LOCAL f$
DO
f$ = QName$()
IF QErr$ <> "" THEN EXIT FUNCTION
IF QFN% >= QF_MAX THEN QFail "too many fields" : EXIT FUNCTION
IF dup% = 0 AND QHas%(f$) THEN QFail "duplicate field '" + f$ + "'" : EXIT FUNCTION
QFld$(QFN%) = f$ : QVT%(QFN%) = 0 : INC QFN%
LOOP WHILE QSym%(",")
QNames% = QFN%
END FUNCTION
FUNCTION QSetVal%(i%, v$, t%)
IF LEN(v$) > QV_LEN THEN QFail "value too long" : EXIT FUNCTION
QVal$(i%) = v$ : QVT%(i%) = t% : QSetVal% = 1
END FUNCTION
FUNCTION QNode%(op%, f$, v$, t%)
IF QErr$ <> "" THEN EXIT FUNCTION
IF QNN% >= QN_MAX THEN QFail "condition too complex" : EXIT FUNCTION
IF LEN(v$) > QNV_LEN THEN QFail "value too long" : EXIT FUNCTION
QnOp%(QNN%) = op% : QnF$(QNN%) = f$ : QnV$(QNN%) = v$ : QnT%(QNN%) = t%
QnTop%(QNN%) = 0
INC QNN%
QNode% = 1
END FUNCTION
FUNCTION QLeaf%()
LOCAL f$, v$, t%, op%, neg%, r$
f$ = QName$()
IF QErr$ <> "" THEN EXIT FUNCTION
IF QKw%("IS") THEN
neg% = QKw%("NOT")
IF QNeedKw%("NULL") = 0 THEN EXIT FUNCTION
IF neg% THEN op% = QO_NNULL ELSE op% = QO_NULL
ELSE
neg% = QKw%("NOT")
IF neg% THEN
IF QNeedKw%("LIKE") = 0 THEN EXIT FUNCTION
op% = QO_LIKE
ELSEIF QKw%("LIKE") THEN
op% = QO_LIKE
ELSE
IF TkT%(QPos%) = TK_SYM THEN
r$ = MID$(QText$, TkP%(QPos%), TkL%(QPos%))
SELECT CASE r$
CASE "="       : op% = QO_EQ
CASE "<>", "!=" : op% = QO_NE
CASE "<"       : op% = QO_LT
CASE "<="      : op% = QO_LE
CASE ">"       : op% = QO_GT
CASE ">="      : op% = QO_GE
END SELECT
ENDIF
IF op% = 0 THEN QFail "expected an operator" : EXIT FUNCTION
INC QPos%
ENDIF
IF QValue%(v$, t%) = 0 THEN EXIT FUNCTION
IF op% = QO_LIKE AND t% <> 1 THEN QFail "LIKE needs a 'text' pattern" : EXIT FUNCTION
ENDIF
IF QNode%(op%, f$, v$, t%) = 0 THEN EXIT FUNCTION
IF neg% AND op% = QO_LIKE THEN
IF QNode%(QO_NOT, "", "", 0) = 0 THEN EXIT FUNCTION
ENDIF
QLeaf% = 1
END FUNCTION
FUNCTION QCond%()
LOCAL os%(TK_MAX \ 2), on% = 0, opnd% = 1, op%, k%, par% = 0
DO
IF QErr$ <> "" THEN EXIT FUNCTION
IF opnd% THEN
IF QKw%("NOT") THEN
os%(on%) = QO_NOT : INC on%
ELSEIF QSym%("(") THEN
INC par%
IF par% > 12 THEN QFail "too deeply nested" : EXIT FUNCTION
os%(on%) = 0 : INC on%
ELSE
IF QLeaf%() = 0 THEN EXIT FUNCTION
opnd% = 0
ENDIF
ELSE
op% = 0
IF QKw%("AND") THEN
op% = QO_AND
ELSEIF QKw%("OR") THEN
op% = QO_OR
ELSEIF par% > 0 THEN
IF QSym%(")") THEN op% = -1
ENDIF
IF op% = 0 THEN EXIT DO
DO WHILE on% > 0
k% = os%(on% - 1)
IF k% = 0 THEN EXIT DO
IF op% > 0 THEN
IF (k% = QO_NOT) * 3 + (k% = QO_AND) * 2 + (k% = QO_OR) < (op% = QO_AND) * 2 + (op% = QO_OR) THEN EXIT DO
ENDIF
IF QNode%(k%, "", "", 0) = 0 THEN EXIT FUNCTION
INC on%, -1
LOOP
IF op% = -1 THEN
INC on%, -1 : INC par%, -1
ELSE
os%(on%) = op% : INC on% : opnd% = 1
ENDIF
ENDIF
LOOP
DO WHILE on% > 0
k% = os%(on% - 1)
IF k% = 0 THEN QFail "expected )" : EXIT FUNCTION
IF QNode%(k%, "", "", 0) = 0 THEN EXIT FUNCTION
INC on%, -1
LOOP
QTopFlags
QCond% = (QErr$ = "")
END FUNCTION
SUB QTopFlags
LOCAL pa%(QN_MAX - 1), sk%(QN_MAX - 1), stp% = 0, i%
IF QNN% = 0 THEN EXIT SUB
FOR i% = 0 TO QNN% - 1
IF QnOp%(i%) = QO_AND OR QnOp%(i%) = QO_OR THEN
pa%(sk%(stp% - 1)) = i% : pa%(sk%(stp% - 2)) = i% : INC stp%, -2
ELSEIF QnOp%(i%) = QO_NOT THEN
pa%(sk%(stp% - 1)) = i% : INC stp%, -1
ENDIF
sk%(stp%) = i% : INC stp%
NEXT
QnTop%(QNN% - 1) = (QnOp%(QNN% - 1) <> QO_OR AND QnOp%(QNN% - 1) <> QO_NOT)
FOR i% = QNN% - 2 TO 0 STEP -1
QnTop%(i%) = QnTop%(pa%(i%)) AND (QnOp%(pa%(i%)) = QO_AND)
NEXT
END SUB
SUB QReset
QErr$ = "" : QPos% = 0 : QCmd$ = "" : QCol$ = ""
QExplain% = 0 : QAgg% = 0 : QFN% = 0 : QNN% = 0
QOrd$ = "" : QDesc% = 0 : QLim% = -1 : QOff% = 0
END SUB
SUB QSelect
LOCAL x%
IF QKw%("COUNT") THEN
x% = QNeedSym%("(") : x% = QNeedSym%("*") : x% = QNeedSym%(")")
QAgg% = 1
ELSEIF QSym%("*") = 0 THEN
x% = QNames%(1)
ENDIF
x% = QNeedKw%("FROM")
QCol$ = QColName$()
IF QKw%("WHERE") THEN x% = QCond%()
IF QKw%("ORDER") THEN
x% = QNeedKw%("BY")
QOrd$ = QName$()
IF QKw%("DESC") THEN QDesc% = 1 ELSE x% = QKw%("ASC")
ENDIF
IF QKw%("LIMIT") THEN
QLim% = QInt%()
IF QKw%("OFFSET") THEN QOff% = QInt%()
ENDIF
END SUB
SUB QInsert
LOCAL x%, i%, v$, t%
x% = QNeedKw%("INTO")
QCol$ = QColName$()
x% = QNeedSym%("(") : x% = QNames%(0) : x% = QNeedSym%(")")
x% = QNeedKw%("VALUES") : x% = QNeedSym%("(")
FOR i% = 0 TO QFN% - 1
IF QErr$ <> "" THEN EXIT SUB
IF i% > 0 THEN
IF QNeedSym%(",") = 0 THEN QErr$ = "" : QFail "fewer values than fields" : EXIT SUB
ENDIF
IF QValue%(v$, t%) THEN x% = QSetVal%(i%, v$, t%)
IF QFld$(i%) = "_id" AND t% <> 1 AND QErr$ = "" THEN QFail "_id must be 'text'"
NEXT
IF QErr$ = "" AND QSym%(",") THEN QFail "more values than fields" : EXIT SUB
x% = QNeedSym%(")")
END SUB
SUB QUpdate
LOCAL x%, f$, v$, t%, i%
QCol$ = QColName$()
IF QKw%("SET") THEN
DO
f$ = QName$()
IF f$ = "_id" THEN QFail "_id cannot be changed"
IF QHas%(f$) THEN QFail "duplicate field '" + f$ + "'"
x% = QNeedSym%("=")
IF QValue%(v$, t%) = 0 THEN EXIT SUB
IF QFN% >= QF_MAX THEN QFail "too many fields" : EXIT SUB
QFld$(QFN%) = f$ : x% = QSetVal%(QFN%, v$, t%) : INC QFN%
LOOP WHILE QSym%(",")
ENDIF
IF QKw%("UNSET") THEN
i% = QFN%
x% = QNames%(0)
FOR i% = i% TO QFN% - 1
IF QFld$(i%) = "_id" THEN QFail "_id cannot be removed"
NEXT
ENDIF
IF QFN% = 0 THEN QFail "expected SET or UNSET"
IF QKw%("WHERE") THEN x% = QCond%()
END SUB
SUB QIndexDef c$
LOCAL x%
QCmd$ = c$ + " INDEX"
x% = QNeedKw%("ON") : QCol$ = QColName$()
x% = QNeedSym%("(") : QFld$(0) = QName$() : QFN% = 1 : x% = QNeedSym%(")")
IF LEFT$(QFld$(0), 1) = "_" AND QErr$ = "" THEN QFail "cannot index _ fields"
END SUB
FUNCTION QParse%(s$)
LOCAL x%, c$
QReset
IF QLex%(s$) = 0 THEN EXIT FUNCTION
QExplain% = QKw%("EXPLAIN")
IF TkT%(QPos%) = TK_ID THEN c$ = UCASE$(MID$(QText$, TkP%(QPos%), TkL%(QPos%)))
IF INSTR(" SELECT INSERT UPDATE DELETE CREATE DROP SHOW DESCRIBE VACUUM ", " " + c$ + " ") = 0 OR c$ = "" THEN
QFail "unknown command" : EXIT FUNCTION
ENDIF
INC QPos% : QCmd$ = c$
SELECT CASE c$
CASE "SELECT" : QSelect
CASE "INSERT" : QInsert
CASE "UPDATE" : QUpdate
CASE "DELETE"
x% = QNeedKw%("FROM") : QCol$ = QColName$()
IF QKw%("WHERE") THEN x% = QCond%()
CASE "CREATE", "DROP"
IF QKw%("COLLECTION") THEN
QCmd$ = c$ + " COLLECTION" : QCol$ = QColName$()
ELSEIF QKw%("INDEX") THEN
QIndexDef c$
ELSE
QFail "expected COLLECTION or INDEX"
ENDIF
CASE "SHOW" : x% = QNeedKw%("COLLECTIONS")
CASE ELSE : QCol$ = QColName$()
END SELECT
IF QErr$ = "" THEN
x% = QSym%(";")
IF TkT%(QPos%) <> TK_END THEN QFail "unexpected '" + MID$(QText$, TkP%(QPos%), TkL%(QPos%)) + "'"
ENDIF
QParse% = (QErr$ = "")
END FUNCTION
FUNCTION QOpName$(op%)
SELECT CASE op%
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
FUNCTION QNodeTxt$(i%)
LOCAL p$
IF QnOp%(i%) >= QO_AND THEN QNodeTxt$ = QOpName$(QnOp%(i%)) : EXIT FUNCTION
p$ = QnF$(i%) + " " + QOpName$(QnOp%(i%))
IF QnOp%(i%) < QO_NULL THEN
IF QnT%(i%) = 1 THEN p$ = p$ + " '" + QnV$(i%) + "'" ELSE p$ = p$ + " " + QnV$(i%)
ENDIF
IF QnTop%(i%) THEN p$ = "^" + p$
QNodeTxt$ = p$
END FUNCTION
FUNCTION QPlan$()
LOCAL s$, p$, i%
s$ = QCmd$ + "|" + QCol$ + "|"
IF QAgg% THEN s$ = s$ + "COUNT"
FOR i% = 0 TO QFN% - 1
p$ = QFld$(i%)
IF QCmd$ = "INSERT" OR QCmd$ = "UPDATE" THEN
IF QVT%(i%) = 0 THEN
p$ = "-" + p$
ELSEIF QVT%(i%) = 1 THEN
p$ = p$ + "='" + QVal$(i%) + "'"
ELSE
p$ = p$ + "=" + QVal$(i%)
ENDIF
ENDIF
IF i% > 0 THEN p$ = "," + p$
IF LEN(s$) + LEN(p$) > 250 THEN QPlan$ = s$ + "~" : EXIT FUNCTION
s$ = s$ + p$
NEXT
s$ = s$ + "|"
FOR i% = 0 TO QNN% - 1
p$ = QNodeTxt$(i%)
IF i% > 0 THEN p$ = ";" + p$
IF LEN(s$) + LEN(p$) > 250 THEN QPlan$ = s$ + "~" : EXIT FUNCTION
s$ = s$ + p$
NEXT
p$ = "|" + QOrd$
IF QDesc% THEN p$ = p$ + " DESC"
p$ = p$ + "|" + STR$(QLim%) + "," + STR$(QOff%)
IF LEN(s$) + LEN(p$) > 255 THEN QPlan$ = s$ + "~" : EXIT FUNCTION
QPlan$ = s$ + p$
END FUNCTION
CONST EX_OUTMAX = 40, EX_W = 52
DIM ExR%(IX_MAX - 1), ExN%, ExCnt%
DIM ExKind$, ExMsg$, ExErr$, ExWarn$, ExPath$
DIM ExOut$(EX_OUTMAX - 1) LENGTH EX_W, ExOutN%
DIM ExSrc%, ExLo%, ExHi%
DIM ExSt%(QN_MAX - 1)
SUB ExSay s$
IF ExOutN% < EX_OUTMAX THEN ExOut$(ExOutN%) = LEFT$(s$, EX_W) : INC ExOutN%
END SUB
FUNCTION ExLike%(s$, p$)
LOCAL i% = 1, j% = 1, si% = 0, sj% = 0, ls% = LEN(s$), lp% = LEN(p$), c$
DO WHILE i% <= ls%
c$ = MID$(p$, j%, 1)
IF j% <= lp% AND c$ <> "%" AND (c$ = "_" OR c$ = MID$(s$, i%, 1)) THEN
INC i% : INC j%
ELSEIF j% <= lp% AND c$ = "%" THEN
sj% = j% : si% = i% : INC j%
ELSEIF sj% > 0 THEN
INC si% : i% = si% : j% = sj% + 1
ELSE
EXIT FUNCTION
ENDIF
LOOP
DO WHILE j% <= lp%
IF MID$(p$, j%, 1) <> "%" THEN EXIT FUNCTION
INC j%
LOOP
ExLike% = 1
END FUNCTION
FUNCTION ExPrefix$(p$)
LOCAL i%
FOR i% = 1 TO LEN(p$)
IF INSTR("%_", MID$(p$, i%, 1)) THEN EXIT FOR
NEXT
ExPrefix$ = LEFT$(p$, i% - 1)
END FUNCTION
FUNCTION ExLeaf%(rec$, k%)
LOCAL x$, v$ = QnV$(k%), op% = QnOp%(k%), t%, c% = 2, nx%, nv%
x$ = RcGet$(rec$, QnF$(k%)) : t% = RcT%
IF op% = QO_NULL OR op% = QO_NNULL THEN
c% = (RcFound% = 0) OR (t% = 2 AND x$ = "null")
IF op% = QO_NULL THEN ExLeaf% = c% ELSE ExLeaf% = 1 - c%
EXIT FUNCTION
ENDIF
IF RcFound% = 0 THEN EXIT FUNCTION
IF op% = QO_LIKE THEN
IF t% = 1 THEN ExLeaf% = ExLike%(x$, v$)
EXIT FUNCTION
ENDIF
IF t% = 2 AND QnT%(k%) = 2 THEN
nx% = RcIsNum%(x$) : nv% = RcIsNum%(v$)
IF nx% AND nv% THEN
c% = SGN(VAL(x$) - VAL(v$))
ELSEIF nx% = 0 AND nv% = 0 THEN
c% = (x$ > v$) - (x$ < v$)
ENDIF
ELSEIF t% = 1 AND QnT%(k%) = 1 THEN
c% = (x$ > v$) - (x$ < v$)
ENDIF
SELECT CASE op%
CASE QO_EQ : ExLeaf% = (c% = 0)
CASE QO_NE : ExLeaf% = (c% <> 0)
CASE QO_LT : ExLeaf% = (c% = -1)
CASE QO_LE : ExLeaf% = (c% = -1 OR c% = 0)
CASE QO_GT : ExLeaf% = (c% = 1)
CASE QO_GE : ExLeaf% = (c% = 1 OR c% = 0)
END SELECT
END FUNCTION
SUB ExPlanPath
LOCAL k%, s%, op%, lo%, hi%, ok%, v$, t%
ExSrc% = 0 : ExLo% = 0 : ExHi% = IxN% : ExPath$ = "full scan"
FOR k% = 0 TO QNN% - 1
op% = QnOp%(k%) : v$ = QnV$(k%) : t% = QnT%(k%) : ok% = 0
IF QnTop%(k%) AND op% <= QO_LIKE AND op% <> QO_NE THEN
IF op% = QO_LIKE THEN v$ = ExPrefix$(v$)
IF QnF$(k%) = "_id" THEN
IF op% = QO_LIKE AND v$ <> "" THEN
lo% = IxBound%(IxK$(), IxN%, v$, 0)
hi% = IxBound%(IxK$(), IxN%, v$ + STRING$(IX_KLEN, 255), 1)
ok% = 1
ELSEIF op% <> QO_LIKE AND t% = 1 THEN
IxRange QOpName$(op%), v$, lo%, hi% : ok% = (lo% >= 0)
ENDIF
IF ok% AND hi% - lo% < ExHi% - ExLo% + (ExSrc% = 0) THEN
ExSrc% = 1 : ExLo% = lo% : ExHi% = hi% : ExPath$ = "_id range"
ENDIF
ELSE
s% = SxSlot%(QnF$(k%))
IF s% >= 0 THEN
IF op% = QO_LIKE THEN
IF v$ <> "" THEN SxRange s%, "LIKE", v$, 1, lo%, hi% : ok% = 1
ELSEIF t% = 1 OR RcIsNum%(v$) OR op% = QO_EQ THEN
SxRange s%, QOpName$(op%), v$, t%, lo%, hi% : ok% = (lo% >= 0)
ENDIF
IF ok% AND hi% - lo% < ExHi% - ExLo% + (ExSrc% = 0) THEN
ExSrc% = 2 : ExLo% = lo% : ExHi% = hi% : ExPath$ = "index on " + QnF$(k%)
ENDIF
ENDIF
ENDIF
ENDIF
NEXT
END SUB
SUB ExCollect lim%
LOCAL i%, off%, r$, m%, k%, stp%
ExN% = 0
IF lim% = 0 THEN EXIT SUB
FOR i% = ExLo% TO ExHi% - 1
IF ExSrc% = 2 THEN off% = SxO%(i%) ELSE off% = IxO%(i%)
r$ = StRead$(off%) : m% = 1
IF QNN% > 0 THEN
stp% = 0
FOR k% = 0 TO QNN% - 1
SELECT CASE QnOp%(k%)
CASE QO_AND : INC stp%, -1 : ExSt%(stp% - 1) = ExSt%(stp% - 1) AND ExSt%(stp%)
CASE QO_OR  : INC stp%, -1 : ExSt%(stp% - 1) = ExSt%(stp% - 1) OR ExSt%(stp%)
CASE QO_NOT : ExSt%(stp% - 1) = 1 - ExSt%(stp% - 1)
CASE ELSE   : ExSt%(stp%) = ExLeaf%(r$, k%) : INC stp%
END SELECT
NEXT
m% = ExSt%(0)
ENDIF
IF m% THEN
ExR%(ExN%) = off% : INC ExN%
IF lim% > 0 AND ExN% >= lim% THEN EXIT SUB
ENDIF
NEXT
END SUB
FUNCTION ExSortKey$(rec$, f$)
LOCAL x$ = RcGet$(rec$, f$), e!, ip%, fr%
IF RcFound% = 0 OR (RcT% = 2 AND x$ = "null") THEN ExSortKey$ = "3" : EXIT FUNCTION
IF RcT% = 2 AND RcIsNum%(x$) THEN
e! = VAL(x$)
IF e! > 4.9E10 THEN e! = 4.9E10
IF e! < -4.9E10 THEN e! = -4.9E10
e! = e! + 5E10 : ip% = INT(e!) : fr% = INT((e! - ip%) * 10000)
ExSortKey$ = "1" + RIGHT$("0000000000" + STR$(ip%), 11) + RIGHT$("000" + STR$(fr%), 4)
ELSE
ExSortKey$ = "2" + LEFT$(x$, 15)
ENDIF
END FUNCTION
SUB ExReverse
LOCAL i%, j% = ExN% - 1, t%
FOR i% = 0 TO ExN% \ 2 - 1
t% = ExR%(i%) : ExR%(i%) = ExR%(j% - i%) : ExR%(j% - i%) = t%
NEXT
END SUB
SUB ExSort
IF ExN% < 2 THEN EXIT SUB
IF QOrd$ = "_id" AND ExSrc% <> 2 THEN
IF QDesc% THEN ExReverse
EXIT SUB
ENDIF
LOCAL k$(ExN% - 1) LENGTH 16, ix%(ExN% - 1), tmp%(ExN% - 1), i%
FOR i% = 0 TO ExN% - 1 : k$(i%) = ExSortKey$(StRead$(ExR%(i%)), QOrd$) : NEXT
SORT k$(), ix%(), QDesc%
FOR i% = 0 TO ExN% - 1 : tmp%(i%) = ExR%(ix%(i%)) : NEXT
FOR i% = 0 TO ExN% - 1 : ExR%(i%) = tmp%(i%) : NEXT
END SUB
SUB ExSlice
LOCAL i%, n%
n% = ExN% - QOff%
IF n% < 0 THEN n% = 0
IF QLim% >= 0 AND n% > QLim% THEN n% = QLim%
IF QOff% > 0 THEN
FOR i% = 0 TO n% - 1 : ExR%(i%) = ExR%(i% + QOff%) : NEXT
ENDIF
ExN% = n%
END SUB
FUNCTION ExUse%(c$)
IF StCol$ = c$ AND c$ <> "" THEN ExUse% = 1 : EXIT FUNCTION
ExUse% = StOpen%(c$)
IF StWarn$ <> "" THEN ExWarn$ = StWarn$
IF ExUse% = 0 THEN ExErr$ = StErr$
END FUNCTION
SUB ExExplain
LOCAL i%
ExKind$ = "TEXT"
ExSay QCmd$ + " " + QCol$ + ": " + ExPath$ + " (" + STR$(ExHi% - ExLo%) + " of " + STR$(IxN%) + ")"
IF ExSrc% = 2 THEN ExSay "  index is approximate: rows are re-checked"
FOR i% = 0 TO QNN% - 1 : ExSay "  " + QNodeTxt$(i%) : NEXT
IF QOrd$ <> "" AND QDesc% THEN ExSay "order by " + QOrd$ + " desc"
IF QOrd$ <> "" AND QDesc% = 0 THEN ExSay "order by " + QOrd$
IF QLim% >= 0 THEN ExSay "limit " + STR$(QLim%) + " offset " + STR$(QOff%)
ExMsg$ = "plan"
END SUB
SUB ExSelect
LOCAL lim% = -1
IF QAgg% AND QNN% = 0 THEN
ExKind$ = "COUNT" : ExCnt% = IxN% : ExMsg$ = STR$(ExCnt%) : EXIT SUB
ENDIF
IF QOrd$ = "" AND QLim% >= 0 AND QAgg% = 0 THEN lim% = QOff% + QLim%
ExCollect lim%
IF QAgg% THEN
ExKind$ = "COUNT" : ExCnt% = ExN% : ExN% = 0 : ExMsg$ = STR$(ExCnt%) : EXIT SUB
ENDIF
IF QOrd$ <> "" THEN ExSort
ExSlice
ExKind$ = "ROWS" : ExMsg$ = STR$(ExN%) + " row(s)"
END SUB
SUB ExInsert
LOCAL r$, id$, i%
FOR i% = 0 TO QFN% - 1
IF QFld$(i%) = "_id" THEN id$ = QVal$(i%)
NEXT
IF id$ = "" THEN id$ = StNewId$()
r$ = RcNew$(id$)
FOR i% = 0 TO QFN% - 1
IF QFld$(i%) <> "_id" AND r$ <> "" THEN r$ = RcSet$(r$, QFld$(i%), QVal$(i%), QVT%(i%))
NEXT
IF r$ = "" THEN ExErr$ = "record " + RcErr$ : EXIT SUB
IF StWrite%(r$, 1) = 0 THEN ExErr$ = StErr$ : EXIT SUB
ExMsg$ = "inserted " + id$
END SUB
SUB ExModify
LOCAL i%, j%, n% = 0, r$, id$
ExCollect -1
FOR i% = 0 TO ExN% - 1
r$ = StRead$(ExR%(i%))
id$ = RcGet$(r$, "_id")
IF QCmd$ = "DELETE" THEN
IF StDelete%(id$) = 0 THEN EXIT FOR
ELSE
FOR j% = 0 TO QFN% - 1
IF r$ <> "" THEN
IF QVT%(j%) = 0 THEN r$ = RcDel$(r$, QFld$(j%)) ELSE r$ = RcSet$(r$, QFld$(j%), QVal$(j%), QVT%(j%))
ENDIF
NEXT
IF r$ = "" THEN StErr$ = id$ + ": record " + RcErr$ : EXIT FOR
IF StWrite%(r$, 2) = 0 THEN EXIT FOR
ENDIF
INC n%
NEXT
IF n% < ExN% THEN ExErr$ = STR$(n%) + " of " + STR$(ExN%) + " done; " + StErr$
IF QCmd$ = "DELETE" THEN ExMsg$ = STR$(n%) + " deleted" ELSE ExMsg$ = STR$(n%) + " updated"
ExN% = 0
END SUB
SUB ExDescribe
LOCAL i%, s$
ExKind$ = "TEXT"
ExSay QCol$ + ": " + STR$(IxN%) + " records, " + STR$(MtDead%) + " dead lines"
s$ = ""
FOR i% = 0 TO SX_SLOTS - 1
IF SxF$(i%) <> "" THEN s$ = s$ + " " + SxF$(i%)
NEXT
ExSay "indexes: _id" + s$
FOR i% = 0 TO MtN% - 1
s$ = "  " + MtF$(i%) + " " + MtT$(i%)
IF SxSlot%(MtF$(i%)) >= 0 THEN s$ = s$ + " (indexed)"
ExSay s$
NEXT
IF MtN% >= MT_MAX THEN ExSay "  (field list full)"
ExMsg$ = STR$(MtN%) + " field(s)"
END SUB
FUNCTION ExRun%(q$)
LOCAL i%, ok%
ExErr$ = "" : ExWarn$ = "" : ExMsg$ = "" : ExKind$ = "OK"
ExN% = 0 : ExCnt% = 0 : ExOutN% = 0
IF QParse%(q$) = 0 THEN ExErr$ = QErr$ : EXIT FUNCTION
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
IF QCmd$ = "CREATE INDEX" THEN ok% = StIndexAdd%(QFld$(0)) ELSE ok% = StIndexDrop%(QFld$(0))
IF ok% THEN
StFlush : ExMsg$ = "ok"
ELSE
ExErr$ = StErr$
ENDIF
CASE "SHOW"
ExKind$ = "TEXT"
FOR i% = 0 TO StList%() - 1 : ExSay StCat$(i%) : NEXT
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
FUNCTION ExVal$(rec$, f$)
LOCAL x$ = RcGet$(rec$, f$)
IF RcT% = 3 THEN x$ = LEFT$(x$, 1) + ".." + RIGHT$(x$, 1)
ExVal$ = x$
END FUNCTION
FUNCTION ExRowText$(rec$)
LOCAL s$, p$, i%, ip% = 1, k$, v$, t%
IF QFN% = 0 THEN
DO
ip% = RcNext%(rec$, ip%, k$, v$, t%)
IF ip% <= 0 THEN EXIT DO
IF t% = 3 THEN v$ = LEFT$(v$, 1) + ".." + RIGHT$(v$, 1)
p$ = k$ + "=" + v$ + " "
IF LEN(s$) + LEN(p$) > 255 THEN EXIT DO
s$ = s$ + p$
LOOP
ELSE
FOR i% = 0 TO QFN% - 1
p$ = QFld$(i%) + "=" + ExVal$(rec$, QFld$(i%)) + " "
IF LEN(s$) + LEN(p$) > 255 THEN EXIT FOR
s$ = s$ + p$
NEXT
ENDIF
ExRowText$ = s$
END FUNCTION
CONST HAL_FONT = 1
DIM HalW%, HalH%, HalFW%, HalFH%
DIM HalFg%(7), HalBg%(7)
SUB HalInit
FONT HAL_FONT
HalFW% = MM.INFO(FONTWIDTH) : HalFH% = MM.INFO(FONTHEIGHT)
HalW% = MM.HRES \ HalFW% : HalH% = MM.VRES \ HalFH%
IF HalW% > 53 THEN HalW% = 53
HalFg%(0) = RGB(WHITE)  : HalBg%(0) = RGB(BLACK)
HalFg%(1) = RGB(BLACK)  : HalBg%(1) = RGB(0, 170, 255)
HalFg%(2) = RGB(BLACK)  : HalBg%(2) = RGB(255, 210, 0)
HalFg%(3) = RGB(GREEN)  : HalBg%(3) = RGB(BLACK)
HalFg%(4) = RGB(WHITE)  : HalBg%(4) = RGB(170, 0, 0)
HalFg%(5) = RGB(160, 160, 160) : HalBg%(5) = RGB(0, 0, 80)
HalFg%(6) = RGB(150, 150, 150) : HalBg%(6) = RGB(BLACK)
HalFg%(7) = RGB(255, 210, 0)   : HalBg%(7) = RGB(BLACK)
END SUB
SUB HalCls
CLS HalBg%(0)
END SUB
SUB HalText c%, r%, s$, st%
IF s$ = "" THEN EXIT SUB
TEXT c% * HalFW%, r% * HalFH%, s$, "LT", HAL_FONT, 1, HalFg%(st%), HalBg%(st%)
END SUB
FUNCTION HalKey%()
LOCAL k$
DO
k$ = INKEY$
LOOP UNTIL k$ <> ""
HalKey% = ASC(k$)
END FUNCTION
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
DIM UiPend%, UiPendQ$, UiReloadNow%, UiReselect$
DIM UiHist$(7) LENGTH 128, UiHistN%
FUNCTION UiBodyH%()
UiBodyH% = HalH% - 3
END FUNCTION
FUNCTION UiClean$(s$)
LOCAL i%, a%, o$
FOR i% = 1 TO LEN(s$)
a% = ASC(MID$(s$, i%, 1))
IF a% < 32 OR a% = 127 THEN o$ = o$ + "?" ELSE o$ = o$ + CHR$(a%)
NEXT
UiClean$ = o$
END FUNCTION
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
FUNCTION UiOff%(i%)
IF UiRes% THEN UiOff% = ExR%(i%) ELSE UiOff% = IxO%(i%)
END FUNCTION
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
FUNCTION UiAsk%(q$)
LOCAL k%
UiLine HalH% - 2, UiClean$(q$) + " (y/n)", US_ERR
k% = HalKey%()
UiAsk% = (k% = 89 OR k% = 121)
UiFull% = 1
END FUNCTION
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
FUNCTION UiType%(v$, ot%)
UiType% = 1
IF ot% = 1 THEN EXIT FUNCTION
IF LEN(v$) >= 2 AND LEFT$(v$, 1) = "'" AND RIGHT$(v$, 1) = "'" THEN
v$ = MID$(v$, 2, LEN(v$) - 2) : EXIT FUNCTION
ENDIF
IF RcLit%(v$) THEN UiType% = 2
END FUNCTION
SUB UiListColl sel$
LOCAL i%, n% = StList%()
FOR i% = 0 TO n% - 1
IF StCat$(i%) = sel$ THEN UiSel%(UV_COLL) = i%
NEXT
UiFull% = 1
END SUB
SUB UiReload
IF UiRes% THEN
IF ExRun%(UiQuery$) = 0 OR ExKind$ <> "ROWS" THEN
UiRes% = 0 : UiSay "filter cleared: " + ExErr$, US_ERR
ENDIF
ENDIF
UiFull% = 1
END SUB
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
IF UiOk% THEN UiPend% = 2 : UiPendQ$ = id$
CASE 78
id$ = UiInput$("New _id (blank = auto): ", "", 0)
IF UiOk% = 0 THEN EXIT SUB
IF id$ = "" THEN id$ = StNewId$()
IF StWrite%(RcNew$(id$), 1) = 0 THEN UiSay StErr$, US_ERR : EXIT SUB
UiReloadNow% = 1 : UiReselect$ = id$
DtLoad StFetch$(id$) : UiGo UV_DET
UiSay "created " + id$ + " - A adds fields", US_MSG
CASE UK_DEL
IF UiCount%() = 0 THEN EXIT SUB
id$ = RcGet$(StRead$(UiOff%(UiSel%(UV_RECS))), "_id")
IF UiAsk%("Delete " + id$ + "?") THEN
IF StDelete%(id$) THEN
UiReloadNow% = 1 : UiSay "deleted " + id$, US_MSG
ELSE
UiSay StErr$, US_ERR
ENDIF
ENDIF
CASE 68 : UiPend% = 3
CASE UK_ESC
IF UiRes% THEN
UiRes% = 0 : UiWhere$ = "" : UiCols$ = "" : UiFull% = 1
ELSE
UiListColl StCol$ : UiGo UV_COLL
ENDIF
END SELECT
END SUB
SUB UiSave k$, v$, t%
LOCAL id$ = RcGet$(DtRec$, "_id"), x%
IF StSetField%(id$, k$, v$, t%) = 0 THEN UiSay StErr$, US_ERR : EXIT SUB
DtLoad StFetch$(id$)
UiReloadNow% = 1 : UiReselect$ = id$
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
CASE UK_ESC : UiReloadNow% = 1 : UiGo UV_RECS
END SELECT
END SUB
SUB UiConsole
LOCAL q$
q$ = UiInput$("sql> ", "", 1)
IF UiOk% AND q$ <> "" THEN UiPend% = 1 : UiPendQ$ = q$
END SUB
SUB UiConsoleRun q$
LOCAL i%, id$
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
UiReloadNow% = 1
IF UiV% = UV_DET THEN
IF IxGet%(id$) < 0 THEN UiGo UV_RECS ELSE DtLoad StFetch$(id$)
ENDIF
ENDIF
UiFull% = 1 : UiSay q$, US_MSG
END SELECT
END SUB
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
SUB UiStep
LOCAL k% = HalKey%(), x%
IF UiMsg$ <> "" THEN UiSay "", US_N
UiKey k%
SELECT CASE UiPend%
CASE 1 : UiConsoleRun UiPendQ$
CASE 2 : UiFilter UiPendQ$
CASE 3
IF ExRun%("DESCRIBE " + StCol$) THEN UiText "Describe " + StCol$ ELSE UiSay ExErr$, US_ERR
END SELECT
UiPend% = 0
IF UiReloadNow% THEN
UiReloadNow% = 0 : UiReload
IF UiReselect$ <> "" THEN
x% = UiFind%(UiReselect$)
IF x% >= 0 THEN UiSel%(UV_RECS) = x%
ENDIF
ENDIF
UiReselect$ = ""
UiPaint
END SUB
StDir$ = "B:/db/"
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
