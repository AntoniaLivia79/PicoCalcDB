[Home](Home.md) › Query parser

# Query parser (`dbquery.bas`, `Tk…` and `Q…`)

`QParse%(s$)` turns one statement of the query language into a **plan**: a set of global variables and arrays that describe it. The parser never touches data; the [executor](Executor.md) runs the plan. The grammar is listed in the comment at the top of `dbquery.bas`, and the user-level description is in the user guide.

## Tokens without copies

`QLex%(s$)` splits the text into tokens, but does not copy them. It keeps the text in `QText$` and records each token as three numbers:

| Array | Holds |
|---|---|
| `TkT%(i)` | Type: `TK_ID` word, `TK_NUM` number, `TK_STR` 'text', `TK_SYM` symbol, `TK_QID` "quoted name", `TK_END` |
| `TkP%(i)` | Start position in `QText$` |
| `TkL%(i)` | Length |

`TkRaw$(i)` returns the token's text with `MID$`. A query has at most 255 characters and therefore at most about 128 tokens, so three small integer arrays replace what would otherwise be 128 strings. The positions also give error messages their column numbers.

The lexer's rules:

- **Words** start with a letter or `_`. Keywords are not separate tokens: they are words compared case-insensitively when the parser expects them.
- **Numbers** may start with `-`, and must pass `RcIsNum%` (so `.5` is rejected; write `0.5`).
- **Text** is in single quotes, with `''` for a quote.
- **Field names** in double quotes may contain anything except `"`.
- **Symbols:** `<=`, `>=`, `<>` and `!=` are two-character tokens; `=<>(),*;` are single.

## Recursive descent with a sticky error

The parser is a set of small FUNCTIONs, one per grammar rule, sharing a cursor `QPos%` into the token arrays.

The helpers `QKw%`, `QSym%`, `QName$`, `QValue%` and `QInt%` consume one token if it is what they expect. **Once `QErr$` is set, every helper does nothing and reports failure.** So statement parsers can call helpers in a row without checking each result:

```basic
x% = QNeedKw%("INTO")
QCol$ = QColName$()
x% = QNeedSym%("(") : x% = QNames%(0) : x% = QNeedSym%(")")
```

The first problem is the one reported. `QFail m$` adds the column of the current token (`" at col 27"`) and never overwrites an earlier error.

## WHERE clauses become RPN

A condition is compiled into **postfix (RPN)** nodes, which the executor evaluates with a simple stack and no recursion:

```
age >= 18 AND (name LIKE 'A%' OR vip = true)
→  age >= 18 ; name LIKE 'A%' ; vip = true ; OR ; AND
```

| Array | Holds |
|---|---|
| `QnOp%(i)` | Operator: `QO_EQ` … `QO_GE`, `QO_LIKE`, `QO_NULL`, `QO_NNULL` for comparisons ("leaves"); `QO_AND`, `QO_OR`, `QO_NOT` |
| `QnF$(i)`, `QnV$(i)`, `QnT%(i)` | For a leaf: field, value, value type (1 text, 2 literal) |
| `QnTop%(i)` | 1 if this leaf is a top-level AND term (see below) |
| `QNN%` | Number of nodes |

`QNode%` appends a node. A leaf is appended when it has been parsed, and an operator after its operands, which is exactly postfix order.

### Parsing a condition without recursion

The precedence levels are `OR` (lowest), `AND`, `NOT`, then single comparisons. `QLeaf%` parses one comparison: `f op value`, `f [NOT] LIKE 'pattern'` or `f IS [NOT] NULL`. `NOT LIKE` is emitted as a `LIKE` leaf followed by a `NOT` node.

`QCond%` parses the whole condition with the **shunting-yard** algorithm: one loop and an explicit operator stack, `os%()`, with no recursion:

```basic
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
      ' release waiting operators: all of them back to the bracket for
      ' ")", otherwise those of equal or higher precedence
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
```

- When an operand is expected (`opnd% = 1`), a `NOT` or `(` is pushed onto the stack; anything else must be a comparison, parsed by `QLeaf%` and emitted at once.
- When an operator is expected, `AND` or `OR` first releases (emits) the waiting operators of equal or higher precedence, then waits itself. That ordering makes `a OR b AND c` come out as `a b c AND OR`, and keeps `a AND b AND c` left-associative: `a b AND c AND`. A `)` releases everything back to its `(`.
- At the end, the remaining operators are released; a leftover `(` is the error `expected )`.
- Brackets may be nested 12 deep (`par%`).

Why not the usual recursive descent, with one function per precedence level calling the next? Earlier versions did that, and it failed on a real PicoCalc. Every nested SUB or FUNCTION call uses part of the PicoMite's small stack, so the parser's call depth rose with each `AND`, `OR`, `NOT` and bracket, on top of the depth of whatever program was running the query. The shunting-yard parser's depth is the same for every condition. See [MMBasic notes](MMBasic-Notes.md#the-call-stack-is-small).

### Index-eligible terms: `QnTop%`

A leaf whose result decides the whole condition through ANDs only – `age >= 18` in the example above – can be answered from an index: every matching record must satisfy it. A leaf under an `OR` or `NOT` cannot.

The flags are set after parsing, from the finished RPN, by `QTopFlags`:

```basic
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
```

A first pass finds every node's parent: a stack of node numbers, where an operator pops its operands and becomes their parent. In RPN a parent always comes after its children, so a second pass backwards from the root can give each node its flag: a node is a top-level term if its parent is one and the parent is an `AND`. Brackets need no special handling: `(a AND b) AND c` keeps all three flags.

## The plan

After a successful `QParse%`:

| Variable | Meaning |
|---|---|
| `QCmd$` | `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `CREATE COLLECTION`, `DROP COLLECTION`, `CREATE INDEX`, `DROP INDEX`, `SHOW`, `DESCRIBE`, `VACUUM` |
| `QExplain%` | 1 if the statement started with `EXPLAIN` |
| `QCol$` | The collection |
| `QAgg%` | 1 for `COUNT(*)` |
| `QFld$()`, `QFN%` | Field list: the SELECT list (0 = `*`), INSERT/UPDATE fields, or the index field |
| `QVal$()`, `QVT%()` | INSERT/UPDATE values and types; `QVT% = 0` marks an `UNSET` field |
| `QOrd$`, `QDesc%` | ORDER BY field and direction |
| `QLim%`, `QOff%` | LIMIT (`-1` = none) and OFFSET |
| `QnOp%()` … `QNN%` | The WHERE clause, as above |

Statement parsers (`QSelect`, `QInsert`, `QUpdate`, `QIndexDef`) fill these in. They also apply rules a plain grammar cannot express: INSERT value count equals field count, no duplicate fields, `_id` must be text and cannot be changed by UPDATE, and so on.

`QPlan$()` and `QNodeTxt$(i)` turn the plan back into text, for `EXPLAIN`.

## Names and reserved words

`QRES$` lists the keywords. A bare field name may not be one of them; `"order"` in double quotes may. Collection names must be plain identifiers that are not keywords, so that they never need quoting.

---
Previous: [Storage engine](Storage-Engine.md) · Next: [Executor](Executor.md)
