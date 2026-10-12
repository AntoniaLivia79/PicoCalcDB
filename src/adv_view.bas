' =====================================================================
' adv_view.bas - VIEW of the text adventure framework (prefix Gv).
' The only module that prints or reads the keyboard. It knows nothing
' about the database: the controller passes it plain text.
' ---------------------------------------------------------------------
' Output is word-wrapped to the console width. For automated tests,
' GvCap% = 1 sends output to GvLog$() and takes input from GvIn$().
' To give the game a different look (colours, a status line, the
' graphics display), change this file only.
' =====================================================================

CONST GV_LOGMAX = 200
DIM GvW% = 40                           ' console width in characters
DIM GvCap% = 0                          ' 1 = capture mode (tests)
DIM GvLog$(GV_LOGMAX - 1) LENGTH 80, GvLogN%
DIM GvIn$(GV_LOGMAX - 1) LENGTH 80, GvInN%, GvInP%

' Work out the console width (keeps 40 if it cannot be read)
SUB GvInit
  LOCAL w% = 0
  ON ERROR SKIP 1
  w% = MM.HRES \ MM.INFO(FONTWIDTH)
  IF w% >= 20 AND w% <= 100 THEN GvW% = w%
END SUB

' One line of output
SUB GvOut s$
  IF GvCap% THEN
    IF GvLogN% < GV_LOGMAX THEN GvLog$(GvLogN%) = LEFT$(s$, 80) : INC GvLogN%
  ELSE
    PRINT s$
  ENDIF
END SUB

' Text, word-wrapped. A line exactly as wide as the console is
' avoided, because the console would add its own line break.
SUB GvSay s$
  LOCAL t$ = s$, w% = GvW% - 1, b%
  IF t$ = "" THEN GvOut "" : EXIT SUB
  DO WHILE LEN(t$) > w%
    b% = w% + 1
    DO WHILE b% > 1 AND MID$(t$, b%, 1) <> " " : INC b%, -1 : LOOP
    IF b% <= 1 THEN b% = w% + 1
    GvOut LEFT$(t$, b% - 1)
    t$ = MID$(t$, b%)
    IF LEFT$(t$, 1) = " " THEN t$ = MID$(t$, 2)
  LOOP
  IF t$ <> "" THEN GvOut t$
END SUB

' A room heading
SUB GvTitle s$
  GvOut ""
  GvOut "== " + s$ + " =="
END SUB

' "label item1, item2 and item3." from a list separated by |
SUB GvList label$, items$, n%
  LOCAL s$ = label$, i%
  FOR i% = 1 TO n%
    s$ = s$ + FIELD$(items$, i%, "|")
    IF i% < n% - 1 THEN s$ = s$ + ", "
    IF i% = n% - 1 THEN s$ = s$ + " and "
  NEXT
  GvSay s$ + "."
END SUB

' Read a command (in capture mode, the next queued one; "quit" when
' the queue is empty, so a test can never wait for a keyboard)
FUNCTION GvAsk$(p$)
  LOCAL s$
  IF GvCap% THEN
    IF GvInP% < GvInN% THEN
      s$ = GvIn$(GvInP%) : INC GvInP%
    ELSE
      s$ = "quit"
    ENDIF
    GvOut p$ + s$
  ELSE
    LINE INPUT p$, s$
  ENDIF
  GvAsk$ = s$
END FUNCTION
