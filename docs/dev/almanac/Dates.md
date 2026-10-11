[Home](Home.md) › Dates

# Dates

Dates are stored and typed as `YYYY-MM-DD` text, but the program works with **day numbers**: the number of days since 1970-01-01. With day numbers, "next day" is `+ 1`, "30 days on" is `+ 30`, and the weekday is a remainder. There are no month or year carries to handle.

## Text to day number

```basic
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
```

1. **Validate the shape:** length 10, `-` in positions 5 and 8, digits elsewhere. Then validate the values: month 1–12, day 1 to the month's length (`AmDim%`, which handles leap years). Anything invalid returns -1, so the same function serves as the validator for CSV dates and typed dates.
2. **Convert** with the civil-calendar algorithm by Howard Hinnant. It treats March as the first month of the year, so that the leap day falls at the *end* of the year, and counts in 400-year eras of 146,097 days. Every step is integer arithmetic (`\` and `MOD`), and all values are positive for years after 1970, so MMBasic's truncating division gives the right answers.

## Day number to text

```basic
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
```

This is the inverse of the same algorithm. `STR$(m%, 2, 0, "0")` zero-pads the month and day.

## Weekdays and display forms

```basic
FUNCTION AmWeekday$(n%)
  AmWeekday$ = MID$(AmWk$, ((n% + 4) MOD 7) * 3 + 1, 3)
END FUNCTION
```

1970-01-01 was a Thursday, day 4 when counting from Sunday = 0, so the weekday of day `n` is `(n + 4) MOD 7`, used as an index into `"SunMonTueWed…"`. This agrees with the weekday column in the supplied CSV, which is why that column can be ignored on import.

| Function | Gives |
|---|---|
| `AmLongDate$(n%)` | `Thu 1 Oct 2026` (browse title, menu) |
| `AmShortDate$(d$)` | `01 Oct 26` (search results) |
| `AmToday%()` | Today's day number from `DATE$` (`DD-MM-YYYY`), or -1 |

`AmToday%` reorders `DATE$` into `YYYY-MM-DD` and reuses `AmDays%`. If the PicoCalc's clock is unset or outside the almanac, the browse screen starts at the first day instead.

---
Previous: [CSV import](CSV-Import.md) · Next: [Screens](Screens.md)
