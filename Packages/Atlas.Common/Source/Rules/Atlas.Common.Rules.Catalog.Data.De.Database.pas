unit Atlas.Common.Rules.Catalog.Data.De.Database;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesDeDatabase: array[0..36] of string = (
    '{',
    '      "id": "dataset-loop-without-next",',
    '      "name": "Datenmengen-Schleife ohne Next",',
    '      "description": "while not Q.Eof do ohne Q.Next im Rumpf oder mit Next nur auf einem Teil der Wege, die die Schleife fortsetzen (if ohne else, Continue vor Next). Die Schleife dreht endlos auf de' +
    'mselben Datensatz. Delete, MoveBy, Last, Close, FindNext und Free zählen ebenfalls als Weiterbewegen; Break, Exit, Abort und raise beenden die Schleife. Innere while- und for-Schleifen laufen vielleic' +
    'ht nie und zählen nicht. Wird Q im Rumpf weitergegeben (Argument, Zuweisung, with), kann der Aufgerufene den Zeiger bewegen, und die Regel bleibt still. Konfidenz hoch, wenn Next ganz fehlt, mittel, w' +
    'enn nur einzelne Wege es auslassen. Korrektur: Q.Next; am Ende des begin … end-Rumpfs einfügen (nur, wenn Next ganz fehlt)."',
    '    },',
    '{',
    '      "id": "dataset-edit-without-post",',
    '      "name": "Edit oder Append ohne Post",',
    '      "description": "Nach Edit, Append oder Insert (ohne Argumente) einer Datenmenge ruft dieselbe Routine weder Post noch Cancel (noch CheckBrowseMode) auf. Die Änderung bleibt offen und geht beim S' +
    'crollen still verloren oder wird später unerwartet gespeichert; bei einer Exception dazwischen bricht sie niemand ab. Still, wenn eine andere Routine der Unit dieselbe Datenmenge postet oder abbricht ' +
    '(Bearbeiten-Knopf mit eigenem Speichern-Knopf), und wenn die Datenmenge nach Edit weitergegeben wird (Argument, Zuweisung, with). Konfidenz mittel. Korrektur: die folgenden Anweisungen, die die Datenm' +
    'enge benutzen, in try … except einschließen, mit Post am Ende des try-Teils und Cancel; raise; im except-Teil."',
    '    },',
    '{',
    '      "id": "transaction-without-rollback",',
    '      "name": "Transaktion ohne Rollback",',
    '      "description": "StartTransaction ohne Rollback im except des unmittelbar folgenden try. Bei einer Exception bleibt die Transaktion offen und hält Sperren. Erkannt für FireDAC (TFDConnection, TFD' +
    'Transaction), IBX und dbExpress (StartTransaction/Commit/Rollback), dbExpress ab XE (BeginTransaction/CommitFreeAndNil/RollbackFreeAndNil, auch als T := Conn.BeginTransaction) und ADO (BeginTrans/Comm' +
    'itTrans/RollbackTrans). Die Option pairs ersetzt diese Paare durch eigene. Das Rollback darf in einem try … except innerhalb eines direkt folgenden try … finally stehen. Still, wenn eine andere Routin' +
    'e der Unit dieselbe Verbindung zurückrollt (Transaktion über mehrere Ereignisse). Konfidenz hoch. Korrektur: die Anweisungen bis zum Commit desselben Blocks in try … except mit Rollback (mit den Argum' +
    'enten des Commit) und raise; einschließen; nur, wenn im selben Block ein Commit folgt.",',
    '      "options": [',
    '        {',
    '          "name": "pairs",',
    '          "description": "Transaktionsmethoden je Bibliothek als [{\"start\": …, \"commit\": …, \"rollback\": …}]; ersetzt die eingebauten Paare."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "sql-write-without-where",',
    '      "name": "UPDATE oder DELETE ohne WHERE",',
    '      "description": "UPDATE oder DELETE ohne WHERE in einem String-Literal, in SQL.Text, SQL.Add, CommandText, im ersten Argument von ExecSQL, ExecSQLScalar, Open, ExecuteDirect oder Execute oder in ' +
    'SQL.Strings/CommandText der Formulardatei. Das betrifft alle Zeilen der Tabelle; meist ist die Bedingung vergessen. Die Regel setzt den SQL-Text je Query innerhalb einer Routine zusammen (Clear und ei' +
    'n neuer Text beginnen von vorn) und setzt Konstanten und lokale Werte ein. JOIN, TOP, LIMIT und ROWS schränken die Zeilen ebenfalls ein; ein WHERE in einer Unterabfrage oder einem Kommentar zählt nich' +
    't. Unbekannte Teile hinter dem Tabellennamen (Variablen, Aufrufe an der Stelle einer Klausel) lassen die Anweisung still; ein dynamischer Tabellenname meldet mit mittlerer Konfidenz. Still, wenn die R' +
    'outine den SQL-Text weitergibt oder eine andere Routine der Unit ihn ergänzt; SQL der Formulardatei zählt nur, solange die Unit es nicht verändert. Literale außerhalb von SQL-Eigenschaften zählen nur ' +
    'mit DELETE bzw. UPDATE in Großbuchstaben, damit Meldungstexte still bleiben. Konfidenz hoch, keine Korrektur; Tabellen, die absichtlich geleert werden, gehören in allowTables.",',
    '      "options": [',
    '        {',
    '          "name": "allowTables",',
    '          "description": "Tabellen, die absichtlich ganz geleert bzw. geändert werden, mit oder ohne Schema."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "sql-select-star",',
    '      "name": "SELECT * im Code",',
    '      "description": "SELECT * oder SELECT Alias.* in einer Spaltenliste, an denselben Stellen wie bei sql-write-without-where: String-Literale, SQL.Text, SQL.Add, CommandText, das erste Argument von ' +
    'ExecSQL, Open und ähnlichen Aufrufen, Konstanten, lokale Werte und SQL.Strings/CommandText der Formulardatei. Neue Spalten ändern still die Datenmenge, persistente Felder passen nicht mehr, und es wer' +
    'den mehr Daten übertragen als nötig. Unterabfragen zählen; EXISTS (SELECT * …) und COUNT(*) bleiben still, ebenso eine Spaltenliste aus einer Variablen. Literale außerhalb von SQL-Eigenschaften zählen' +
    ' nur mit SELECT in Großbuchstaben und einem FROM, damit Meldungstexte still bleiben. Standardmäßig aus (in den Regeleinstellungen oder mit dem Profil strict einschalten). Konfidenz hoch. Schnellkorrek' +
    'tur: Steht der Stern in einem einzelnen Literal und hat die Datenmenge persistente Felder in der Formulardatei, ersetzt sie * durch deren FieldName-Liste (ohne berechnete und Nachschlagefelder)."',
    '    }');

implementation

end.
