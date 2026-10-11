"""Generate sdcard/db/help/dbhelp.jsonl, the explorer's help topics, from the
topic list below, checking that every line fits 255 characters and every
topic fits the help screen.  python3 tools/make_help.py [output.jsonl]"""
import json, os, sys

# (topic id, title, keywords, [paragraphs])  - order = order shown
T = [
("0100", "Getting started", "start run begin intro overview quit exit",
 ["This program stores collections of records on the SD card and lets you browse, search and edit them.",
  "You start in the Collections list. Press Enter to open a collection, N to make a new one.",
  "Inside a collection you see its records. Enter shows one record's fields, which you can edit.",
  "Press F1 at any time to search this help. Press Esc to go back a step. Esc in the Collections list asks whether to quit."]),
("0110", "The screen", "screen layout title bar status hints line",
 ["Top line: where you are, for example 'people  3/46' (record 3 of 46).",
  "Middle: the list. The highlighted line is the current selection.",
  "Second line from the bottom: messages, and the input line when you type something.",
  "Bottom line: the keys you can use right now."]),
("0120", "Keys that work everywhere", "keys keyboard arrows page home end escape f1 f2 slash",
 ["Up/Down: move one line. Left/Right or PgUp/PgDn: move a page (in the record detail Left/Right change record).",
  "Home/End: jump to the first/last line.",
  "F1: help search. F2 or /: the SQL command line. Esc: back, cancel, or clear a filter."]),
("0130", "Typing on the input line", "input edit line typing backspace cursor history cancel",
 ["Left/Right move the cursor, Home/End jump to the start/end, Backspace deletes to the left, Del deletes under the cursor.",
  "Enter accepts what you typed. Esc cancels.",
  "In the SQL command line Up/Down bring back your last 8 commands."]),
("0200", "Collections", "collection table create new open drop delete name list",
 ["A collection is a set of records, like a table. Each one is a file on the SD card (see 'Where your data is').",
  "N: new collection. Names use letters, digits and _ only, up to 16 characters, and cannot be SQL words such as order or select.",
  "Enter: open the highlighted collection. Del: drop it, which deletes all its records after you answer y.",
  "The open collection is marked (open)."]),
("0300", "The record list", "records list browse preview scroll position",
 ["Each line shows a record: its _id first, then its fields as name:value, as far as the screen allows.",
  "The title shows the collection, your position and the record count. Records are listed in _id order.",
  "Enter shows the highlighted record. D describes the collection (fields, types, indexes)."]),
("0310", "Adding a record", "new add create record insert id auto",
 ["In the record list press N and type an _id, or just press Enter to get the next automatic number (000001, 000002 ...).",
  "An _id is text of up to 16 characters and must be unique in the collection.",
  "The new record opens straight away: press A to add fields."]),
("0320", "Deleting a record", "delete remove record del",
 ["Highlight the record in the list, press Del, then y. This cannot be undone from the program."]),
("0330", "Filtering records", "filter search find where query condition",
 ["In the record list press F and type a condition, for example: age > 30 AND name LIKE 'A%'",
  "Only matching records are listed and the title shows the condition in [ ].",
  "Press F again to change the condition, or Esc to show all records again.",
  "See 'Conditions (WHERE)' for what you can write. Error messages give the column where the problem is."]),
("0400", "The record detail", "detail record fields view next previous",
 ["One line per field: name, then value. The first line is the _id.",
  "Left/Right show the previous/next record of the list, so you can step through records.",
  "Esc goes back to the list."]),
("0410", "Editing a value", "edit change value field text number type quote",
 ["Highlight a field and press Enter. Change the value and press Enter to save, or Esc to cancel.",
  "Text stays text. Any other value is saved as a number, true, false or null when it looks like one, otherwise as text.",
  "To store something that looks like a number as text, type it in single quotes, for example '0123'.",
  "Text that looks like a number is shown in quotes so you can tell it apart."]),
("0420", "Adding and removing fields", "add field remove delete unset new field",
 ["A: add a field. Type its name, then its value. If the field exists you edit it instead.",
  "Del: remove the highlighted field (answer y).",
  "Field names starting with _ are reserved. _id cannot be changed or removed."]),
("0500", "Kinds of values", "types value text number boolean true false null nested",
 ["Text: any characters. Numbers: like 42, -1.5 or 2e3. Also true, false and null.",
  "Records made by other programs may hold lists or nested objects. They are shown as {..} or [..] and cannot be edited here.",
  "Different records may hold different fields; no field is required except _id."]),
("0600", "The SQL command line", "sql command console query f2 slash statement",
 ["Press F2 or / and type a command. Keywords can be upper or lower case; a ; at the end is optional.",
  "SELECT results open in the record list, marked [query]; Esc returns to all records.",
  "COUNT shows its answer on the message line. SHOW, DESCRIBE and EXPLAIN open a text page.",
  "Commands work on any collection by name, not only the open one."]),
("0610", "SELECT", "select query fields columns from",
 ["SELECT * FROM people shows all records.",
  "SELECT name, age FROM people WHERE age > 30 shows only those fields in the list.",
  "Add ORDER BY and LIMIT as needed (see 'Sorting and limits')."]),
("0620", "Conditions (WHERE)", "where condition compare operator and or not equal less greater",
 ["Compare a field with a value: =, <> (or !=), <, <=, >, >=. Example: age >= 18",
  "Text values go in single quotes: name = 'Ann'. Write two quotes for an apostrophe: 'O''Brien'.",
  "Combine with AND, OR and NOT. AND goes before OR: a = 1 OR b = 2 AND c = 3 means a = 1 OR (b = 2 AND c = 3).",
  "Use ( ) to group differently: (a = 1 OR b = 2) AND c > 0",
  "A field name with spaces, or that is an SQL word, goes in double quotes: \"first name\" = 'Al'."]),
("0630", "Matching text with LIKE", "like pattern wildcard percent underscore match starts contains",
 ["% stands for any number of characters, _ for exactly one.",
  "name LIKE 'A%' starts with A. name LIKE '%son' ends with son. code LIKE 'A_1' is A, any one character, then 1.",
  "LIKE is case-sensitive: 'a%' does not match Ann. Use NOT LIKE for the opposite. LIKE only matches text, never numbers."]),
("0640", "Missing fields and NULL", "null missing empty is null absent field not set",
 ["A record without a field never matches a comparison on it, not even <>.",
  "Use IS NULL to find records where a field is missing or null, and IS NOT NULL for the others.",
  "Example: SELECT * FROM people WHERE phone IS NULL"]),
("0650", "How values compare", "compare numbers text case order alphabetical types mixed",
 ["Numbers compare by value, so 1e3 = 1000. Text compares character by character, so capitals come before small letters.",
  "A number and text are never equal, never smaller or larger; only <> is true between them. '5' in quotes is text, 5 is a number."]),
("0660", "Sorting and limits", "order by sort desc ascending descending limit offset first page",
 ["ORDER BY age sorts by one field; add DESC for largest first.",
  "Numbers come before text. Records without the field come last (first with DESC).",
  "LIMIT 10 keeps the first 10 results; LIMIT 10 OFFSET 20 skips 20 first.",
  "Without ORDER BY results come in _id order, or in the order of an index the query used."]),
("0670", "Counting", "count how many number of records total",
 ["SELECT COUNT(*) FROM people counts all records; add WHERE to count only matches."]),
("0680", "INSERT: add records", "insert add new record values",
 ["INSERT INTO people (_id, name, age) VALUES ('p1', 'Ann', 34)",
  "Leave out _id to get an automatic number; the message line shows the _id given.",
  "The _id must be text and must not exist yet."]),
("0690", "UPDATE: change records", "update change set unset modify many",
 ["UPDATE people SET age = 35, city = 'Leeds' WHERE _id = 'p1'",
  "UNSET removes fields: UPDATE people UNSET phone WHERE age > 90",
  "Without WHERE every record is changed, and there is no 'are you sure' question."]),
("0700", "DELETE: remove records", "delete remove records many",
 ["DELETE FROM people WHERE age < 18 removes the matching records.",
  "DELETE FROM people without WHERE removes every record, without asking. The collection itself stays."]),
("0710", "Indexes: faster searches", "index speed fast slow performance create index drop index",
 ["CREATE INDEX ON people (age) makes conditions on age much faster. DROP INDEX ON people (age) removes it.",
  "Up to 4 fields per collection can be indexed. _id is always indexed.",
  "An index helps with =, <, <=, >, >= and LIKE 'abc%' when the condition is not inside OR or NOT.",
  "Indexes use memory: one entry per record that has the field."]),
("0720", "EXPLAIN: is it using an index?", "explain plan index full scan slow",
 ["Put EXPLAIN in front of a SELECT, UPDATE or DELETE to see how it would run, without running it.",
  "'full scan' reads every record; 'index on age' or '_id range' reads only candidates.",
  "Conditions marked ^ are ones an index could serve."]),
("0730", "DESCRIBE and SHOW", "describe show collections fields types info",
 ["DESCRIBE people (or D in the record list) lists record count, dead lines, indexes and every field seen with its kind:",
  "S text, N number, L true/false/null, O list or nested object, X mixed (different kinds in different records).",
  "SHOW COLLECTIONS lists all collections. CREATE COLLECTION and DROP COLLECTION do the same as N and Del in the list."]),
("0800", "VACUUM: reclaim space", "vacuum compact space dead lines file size tidy shrink",
 ["Changing or deleting a record adds a line to the file and leaves the old one as a dead line. DESCRIBE shows how many.",
  "VACUUM people rewrites the file with live records only. Run it now and then, and before copying files to a PC.",
  "It is safe if the power fails while it runs."]),
("0810", "Power loss and crashes", "power crash battery safe recovery repair torn ctrl-c break",
 ["Records are only ever added to the end of a file, so a power cut can damage at most the last line.",
  "On the next open the program repairs this and tells you (repaired torn last line, or n bad line(s) skipped).",
  "Stopping the program with Ctrl-C is safe; the index is rebuilt or caught up next time."]),
("0820", "Where your data is", "files sd card folder location backup copy jsonl idx meta",
 ["Everything is in the folder db on the SD card (B:/db/). For a collection called people:",
  "people.jsonl holds the records, people.idx a saved index, people.meta field and index settings.",
  "To back up, copy the db folder. The .idx files can be deleted at any time; they are rebuilt."]),
("0830", "Using your data on a PC", "pc computer export json lines python spreadsheet interop",
 ["Each .jsonl file has one record per line in JSON format, readable by most programming languages and many tools.",
  "Run VACUUM first: then every line is one current record. Otherwise an _id can appear more than once (the last line wins) and lines with \"_del\" mark deleted records."]),
("0840", "Editing files on a PC", "pc edit external file editor import change outside",
 ["You may edit a .jsonl file with a text editor or your own programs.",
  "Keep one record per line, at most 255 characters, each with a unique text \"_id\" of up to 16 characters.",
  "Afterwards delete the matching .idx file so the index is rebuilt. Lines the program cannot read are skipped and reported when the collection is opened.",
  "Use plain ASCII characters; others may not display correctly on the PicoCalc."]),
("0900", "Limits", "limits maximum size how many records fields length",
 ["A record is at most 255 characters as stored. An _id is up to 16 characters.",
  "Up to 1000 records per collection, 4 indexed fields, and 1000 index entries in total per collection.",
  "A command is at most 255 characters. Field names in commands are up to 24 characters; text values in conditions up to 64.",
  "DESCRIBE lists up to 24 different field names per collection."]),
("0910", "Common messages", "error message duplicate not found full too long expected col reserved",
 ["duplicate _id: that _id is already used. not found: no record with that _id.",
  "too long: the record would exceed 255 characters. collection full / index space full: a limit was reached (see Limits).",
  "expected ... at col 12: a typing mistake in a command; col counts characters from the start.",
  "reserved word 'order' (quote it): write \"order\" in double quotes."]),
("0950", "Searching this help", "help search f1 find topic words",
 ["F1 asks for words. Topics that contain all of them, in any case, are listed. Press Enter with nothing typed for the full list.",
  "Enter reads a topic, Esc goes back. If only one topic matches it opens directly. Try short words: index, like, null, delete.",
  "The help is the file db/help/dbhelp.jsonl; you can add your own topics to it with any text editor."]),
]

def enc(rec):
    s = json.dumps(rec, separators=(',', ':'), ensure_ascii=True)
    return s

def wrap(s, w):
    out = []
    while len(s) > w:
        b = w  # index of char at position w+1 (0-based w)
        while b > 0 and s[b] != ' ':
            b -= 1
        if b <= 0:
            out.append(s[:w]); s = s[w:]
        else:
            out.append(s[:b]); s = s[b+1:]
    if s: out.append(s)
    return out

lines = []
ok = True
for tid, title, kw, paras in T:
    assert len(title) <= 40, title
    nlines = 0
    for i, p in enumerate(paras):
        assert all(32 <= ord(c) < 127 for c in p), p
        rec = {"_id": f"{tid}.{i+1}"}
        if i == 0:
            rec["title"] = title
            rec["kw"] = kw
        rec["text"] = p
        line = enc(rec)
        if len(line) > 255:
            print("TOO LONG", tid, i, len(line)); ok = False
        lines.append(line)
        if i: nlines += 1
        nlines += len(wrap(p, 40))
    if nlines > 40:
        print("TOPIC TOO TALL", tid, nlines); ok = False
open(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'sdcard', 'db', 'help', 'dbhelp.jsonl'), 'w', newline='\r\n').write('\n'.join(lines) + '\n')
print(len(T), "topics,", len(lines), "records, longest",
      max(len(l) for l in lines), "chars", "OK" if ok else "PROBLEMS")
