unit Atlas.Common.Rules.Catalog.Data.En.Database;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesEnDatabase: array[0..89] of string = (
    '{',
    '      "id": "dataset-loop-without-next",',
    '      "name": "Dataset loop without Next",',
    '      "category": "bug",',
    '      "severity": "error",',
    '      "group": "database",',
    '      "description": "while not Q.Eof do without Q.Next in the body, or with Next only on some of the paths that continue the loop (an if without else, Continue before Next). The loop spins forever on' +
    ' the same record. Delete, MoveBy, Last, Close, FindNext and Free also count as moving on; Break, Exit, Abort and raise end the loop. Nested while and for loops are not trusted to run. When Q is passed' +
    ' on in the body (argument, assignment, with), the called code may move the record pointer and the rule stays silent. High confidence when Next is missing entirely, medium when only some paths miss it.' +
    ' Quick fix: insert Q.Next; at the end of the begin … end body (only when Next is missing entirely).",',
    '      "bad": "qryPositionen.First;\nwhile not qryPositionen.Eof do\nbegin\n  Summe := Summe + qryPositionen.FieldByName(''Betrag'').AsCurrency;\nend;",',
    '      "good": "qryPositionen.First;\nwhile not qryPositionen.Eof do\nbegin\n  Summe := Summe + qryPositionen.FieldByName(''Betrag'').AsCurrency;\n  qryPositionen.Next;\nend;",',
    '      "safeFix": false',
    '    },',
    '{',
    '      "id": "dataset-edit-without-post",',
    '      "name": "Edit or Append without Post",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "database",',
    '      "description": "After Edit, Append or Insert (without arguments) on a dataset, the same routine calls neither Post nor Cancel (nor CheckBrowseMode). The change stays open and is silently lost on' +
    ' scrolling or saved unexpectedly later; on an exception in between, nothing cancels it. Silent when another routine of the unit posts or cancels the same dataset (an Edit button with a separate Save b' +
    'utton) and when the dataset is passed on after Edit (argument, assignment, with). Medium confidence. Quick fix: wrap the following statements that use the dataset in try … except, with Post at the end' +
    ' of the try part and Cancel; raise; in the except part.",',
    '      "bad": "tblKunde.Edit;\ntblKunde.FieldByName(''Status'').AsInteger := Ord(ksAktiv);\nProtokollieren;",',
    '      "good": "tblKunde.Edit;\ntry\n  tblKunde.FieldByName(''Status'').AsInteger := Ord(ksAktiv);\n  tblKunde.Post;\nexcept\n  tblKunde.Cancel;\n  raise;\nend;\nProtokollieren;",',
    '      "safeFix": false',
    '    },',
    '{',
    '      "id": "transaction-without-rollback",',
    '      "name": "Transaction without Rollback",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "database",',
    '      "description": "StartTransaction without Rollback in the except part of the try that directly follows. On an exception the transaction stays open and holds locks. Recognized for FireDAC (TFDConn' +
    'ection, TFDTransaction), IBX and dbExpress (StartTransaction/Commit/Rollback), dbExpress from XE (BeginTransaction/CommitFreeAndNil/RollbackFreeAndNil, also as T := Conn.BeginTransaction) and ADO (Beg' +
    'inTrans/CommitTrans/RollbackTrans). The option pairs replaces these pairs with your own. The Rollback may sit in a try … except inside a try … finally that follows directly. Silent when another routin' +
    'e of the unit rolls back the same connection (transaction across several events). High confidence. Quick fix: wrap the statements up to the Commit of the same block in try … except with Rollback (with' +
    ' the arguments of the Commit) and raise; only when a Commit follows in the same block.",',
    '      "bad": "Verbindung.StartTransaction;\nBuchen(Auftrag);\nVerbindung.Commit;",',
    '      "good": "Verbindung.StartTransaction;\ntry\n  Buchen(Auftrag);\n  Verbindung.Commit;\nexcept\n  Verbindung.Rollback;\n  raise;\nend;",',
    '      "options": [',
    '        {',
    '          "name": "pairs",',
    '          "type": "json",',
    '          "default": [',
    '            {',
    '              "start": "StartTransaction",',
    '              "commit": "Commit",',
    '              "rollback": "Rollback"',
    '            },',
    '            {',
    '              "start": "BeginTransaction",',
    '              "commit": "CommitFreeAndNil",',
    '              "rollback": "RollbackFreeAndNil"',
    '            },',
    '            {',
    '              "start": "BeginTrans",',
    '              "commit": "CommitTrans",',
    '              "rollback": "RollbackTrans"',
    '            }',
    '          ],',
    '          "description": "Transaction methods per library as [{\"start\": …, \"commit\": …, \"rollback\": …}]; replaces the built-in pairs."',
    '        }',
    '      ],',
    '      "safeFix": false',
    '    },',
    '{',
    '      "id": "sql-write-without-where",',
    '      "name": "UPDATE or DELETE without WHERE",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "database",',
    '      "description": "An UPDATE or DELETE without WHERE in a string literal, SQL.Text, SQL.Add, CommandText, the first argument of ExecSQL, ExecSQLScalar, Open, ExecuteDirect or Execute, or in SQL.Str' +
    'ings/CommandText of the form file. It affects every row of the table; usually the condition was forgotten. The rule assembles the SQL text per query within a routine (Clear and a new Text start over) ' +
    'and substitutes constants and local values. JOIN, TOP, LIMIT and ROWS restrict the rows as well; a WHERE in a subquery or comment does not count. Unknown parts behind the table name (variables, calls ' +
    'at the place of a clause) keep the statement silent; a dynamic table name reports with medium confidence. Silent when the routine passes the SQL on or another routine of the unit adds to it; form file' +
    ' SQL only counts when the unit does not change it. Literals outside SQL properties count only with DELETE or UPDATE in capitals, so message texts stay silent. High confidence, no quick fix; tables tha' +
    't are emptied on purpose go into allowTables.",',
    '      "bad": "qry.SQL.Text := ''DELETE FROM Warenkorb'';\nqry.ExecSQL;",',
    '      "good": "qry.SQL.Text := ''DELETE FROM Warenkorb WHERE Kunde = :Kunde'';\nqry.ParamByName(''Kunde'').AsInteger := KundeId;\nqry.ExecSQL;",',
    '      "options": [',
    '        {',
    '          "name": "allowTables",',
    '          "type": "string-list",',
    '          "default": [],',
    '          "description": "Tables that are deliberately emptied or changed completely, with or without schema."',
    '        }',
    '      ],',
    '      "safeFix": false',
    '    },',
    '{',
    '      "id": "sql-select-star",',
    '      "name": "SELECT * in code",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "database",',
    '      "description": "SELECT * or SELECT alias.* in a column list, in the same places as sql-write-without-where: string literals, SQL.Text, SQL.Add, CommandText, the first argument of ExecSQL, Open a' +
    'nd similar calls, constants, local values and SQL.Strings/CommandText of the form file. New columns silently change the dataset, persistent fields no longer match, and more data is transferred than ne' +
    'eded. Subqueries count; EXISTS (SELECT * …) and COUNT(*) stay silent, as does a column list from a variable. Literals outside SQL properties count only with SELECT in capitals and a FROM, so message t' +
    'exts stay silent. Off by default (enable in the rules settings or with the strict profile). High confidence. Quick fix: when the star stands in a single literal and the dataset has persistent fields i' +
    'n the form file, replace * with their FieldName list (without calculated and lookup fields).",',
    '      "bad": "qry.SQL.Text := ''SELECT * FROM Kunden WHERE Ort = :Ort'';",',
    '      "good": "qry.SQL.Text := ''SELECT Id, Name, Ort FROM Kunden WHERE Ort = :Ort'';",',
    '      "safeFix": false,',
    '      "profiles": [',
    '        "strict"',
    '      ]',
    '    }');

implementation

end.
