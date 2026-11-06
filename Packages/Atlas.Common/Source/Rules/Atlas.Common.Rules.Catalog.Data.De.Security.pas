unit Atlas.Common.Rules.Catalog.Data.De.Security;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  CatalogLinesDeSecurity: array[0..54] of string = (
    '{',
    '      "id": "bidi-control",',
    '      "name": "Bidirektionales Steuerzeichen",',
    '      "description": "Bidirektionale Steuerzeichen können Code anders anzeigen, als er kompiliert wird (Trojan Source); auch in Formulardateien. Richtungsmarken in RTL-Text nur mit niedriger Konfidenz' +
    '."',
    '    },',
    '{',
    '      "id": "invisible-char",',
    '      "name": "Unsichtbares Zeichen",',
    '      "description": "Unsichtbare oder Nullbreiten-Zeichen im Quelltext und in Formulardateien; in Strings und Kommentaren mittlere Konfidenz."',
    '    },',
    '{',
    '      "id": "control-char",',
    '      "name": "Steuerzeichen",',
    '      "description": "NUL- und Steuerzeichen oder ungültige UTF-8-Bytes im Quelltext und in der Formulardatei; ungültige Bytes mit genauer Zeile und Spalte. Wie dcc gilt eine Datei ohne BOM nur als UT' +
    'F-8, wenn sie ganz gültiges UTF-8 ist; eine ANSI-Datei wird nur dann auf ungültige Bytes geprüft, wenn ihre gültigen UTF-8-Folgen überwiegen. U+FFFD ist im Code ein Fehler, im String ein Hinweis, im K' +
    'ommentar kein Befund."',
    '    },',
    '{',
    '      "id": "confusable-identifier",',
    '      "name": "Verwechselbarer Bezeichner",',
    '      "description": "Bezeichner mit Zeichen aus mehreren Schriften oder Nicht-ASCII-Zeichen sind mit anderen verwechselbar."',
    '    },',
    '{',
    '      "id": "security-command-injection",',
    '      "name": "Befehlsinjektion",',
    '      "description": "ShellExecute, ShellExecuteEx, CreateProcess oder WinExec erhält ein Argument, das mit +, Format oder Concat aus nicht konstanten Werten zusammengesetzt ist. Eingaben könnten weit' +
    'ere Befehle einschleusen. Ohne Datenflussanalyse wird nur dieses einfache Muster erkannt (mittlere Konfidenz)."',
    '    },',
    '{',
    '      "id": "security-path-traversal",',
    '      "name": "Pfad-Traversal",',
    '      "description": "Ein Dateizugriff (TFileStream.Create, LoadFromFile, AssignFile, TFile.*) verwendet einen Pfad aus Eingabedaten (Text, ParamStr, Request) ohne Prüfung über TPath.GetFullPath. Expe' +
    'rimentell, bis die Datenflussanalyse verfügbar ist."',
    '    },',
    '{',
    '      "id": "security-weak-crypto",',
    '      "name": "Schwache Kryptografie",',
    '      "description": "MD5, SHA-1, DES oder RC4 wird verwendet. Für Prüfsummen ist das in Ordnung, für Kennwörter und Signaturen nicht. Niedrige Konfidenz, mittlere, wenn die Anweisung ein Kennwort, Ge' +
    'heimnis oder eine Signatur nennt."',
    '    },',
    '{',
    '      "id": "security-tls-verification-disabled",',
    '      "name": "TLS-Zertifikatsprüfung abgeschaltet",',
    '      "description": "Indy SSLOptions.VerifyMode := [], ein OnVerifyPeer-Handler, der immer True liefert, oder ein ValidateServerCertificate-Handler, der Accepted := True ohne Prüfung setzt."',
    '    },',
    '{',
    '      "id": "security-insecure-http",',
    '      "name": "Unverschlüsselte http://-URL",',
    '      "description": "Ein String enthält eine http://-URL. XML-Namensräume und Schema-URIs, Kommentare sowie localhost, 127.0.0.1 und [::1] sind ausgenommen. Die Korrektur ersetzt http:// durch https:' +
    '//."',
    '    },',
    '{',
    '      "id": "security-insecure-random",',
    '      "name": "Random für sicherheitsrelevante Werte",',
    '      "description": "Random wird einem Token, Kennwort, Salt, Nonce oder Schlüssel zugewiesen. Random ist vorhersagbar; einen kryptografischen Zufallsgenerator verwenden. Fehlendes Randomize behandel' +
    't #153."',
    '    },',
    '{',
    '      "id": "security-sql-injection",',
    '      "name": "SQL-Text aus zusammengesetzten Werten (SQL-Injection)",',
    '      "description": "SQL.Text, SQL.Add, CommandText, ExecSQL oder Open erhalten Text, der per + oder Format aus Nicht-Konstanten zusammengesetzt ist. Benutzereingaben könnten SQL einschleusen. Parame' +
    'ter verwenden (:Name, ParamByName). Konstanten, resourcestrings, IntToStr und QuotedStr zählen nicht; Benutzereingaben (TEdit.Text, TMemo.Lines) heben die Konfidenz auf hoch."',
    '    }');

implementation

end.
