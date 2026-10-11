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

### Grammar functions

The precedence levels are `OR` (lowest), `AND`, `NOT`, and primaries (a comparison or a parenthesised condition). `QPrim%` handles `f op value`, `f [NOT] LIKE 'pattern'` and `f IS [NOT] NULL`. `NOT LIKE` is emitted as a `LIKE` leaf followed by a `NOT` node.

The OR level:

```basic
FUNCTION QOr%()
  LOCAL st% = QNN%
  IF QAnd%() = 0 THEN EXIT FUNCTION
  IF QKw%("OR") THEN
    QOr% = QOrRest%()
    QNotTop st%
  ELSE
    QOr% = (QErr$ = "")
  ENDIF
END FUNCTION
```

```basic
FUNCTION QOrRest%()
  IF QAnd%() = 0 THEN EXIT FUNCTION
  IF QNode%(QO_OR, "", "", 0) = 0 THEN EXIT FUNCTION
  IF QKw%("OR") THEN QOrRest% = QOrRest%() ELSE QOrRest% = (QErr$ = "")
END FUNCTION
```

The natural way to write this is a loop: "parse an AND-term; while the next word is OR, parse another and emit OR". It is written with **tail recursion** instead, because a `DO` loop does not work here. MMBasic identifies a running `DO` loop by its position in the program. In `a AND (b AND c)`, the parenthesised part re-enters the same functions while the outer loop is still running, and the inner loop's exit removes the outer loop's entry, giving "LOOP without a matching DO". `QOrRest%` and `QAndRest%` emit each operator after its right operand, which keeps `a OR b OR c` left-associative: `a b OR c OR`.

Nesting is limited by `QDepth%` (12 levels), so a pathological query cannot exhaust the interpreter's stack.

### Index-eligible terms: `QnTop%`

A leaf whose result decides the whole condition through ANDs only – `age >= 18` in the example above – can be answered from an index: every matching record must satisfy it. A leaf under an `OR` or `NOT` cannot.

Every leaf starts with `QnTop% = 1`. When `QOr%` has actually parsed an `OR`, or `QNot%` a `NOT`, it calls `QNotTop st%` to clear the flag on all nodes emitted since it started (`st%` = the node count on entry). Parentheses need no special handling: `(a AND b) AND c` keeps all three flags.

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
