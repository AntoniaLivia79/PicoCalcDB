' =====================================================================
' dbhal.bas - PicoCalc display/keyboard layer for dbgui.bas
' The GUI only calls HalInit, HalCls, HalText and HalKey%, using
' character cells, so it can be tested with a mock and ported to
' other screens by replacing this file.
' =====================================================================

CONST HAL_FONT = 1          ' 1 = 8x12 (40x26 cells); 7 = 6x8 (53x40)
DIM HalW%, HalH%, HalFW%, HalFH%
DIM HalFg%(7), HalBg%(7)

SUB HalInit
  FONT HAL_FONT
  HalFW% = MM.INFO(FONTWIDTH) : HalFH% = MM.INFO(FONTHEIGHT)
  HalW% = MM.HRES \ HalFW% : HalH% = MM.VRES \ HalFH%
  IF HalW% > 53 THEN HalW% = 53
  ' styles: 0 normal, 1 title, 2 selection, 3 message, 4 error, 5 hints,
  '         6 dim text, 7 heading
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

' Draw s$ at character cell (c%, r%) in style st%
SUB HalText c%, r%, s$, st%
  IF s$ = "" THEN EXIT SUB
  TEXT c% * HalFW%, r% * HalFH%, s$, "LT", HAL_FONT, 1, HalFg%(st%), HalBg%(st%)
END SUB

' Wait for a key; returns its code (PicoCalc: Del = 212, F1 = 145)
FUNCTION HalKey%()
  LOCAL k$
  DO
    k$ = INKEY$
  LOOP UNTIL k$ <> ""
  HalKey% = ASC(k$)
END FUNCTION
