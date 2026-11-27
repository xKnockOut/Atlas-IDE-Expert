unit Rules.Catalog.Data.De.Internal;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesDeInternal: array[0..24] of string = (
    '{',
    '      "id": "unused-suppression",',
    '      "name": "Ungenutzte Unterdrückung",',
    '      "description": "Ein lsp-ignore-Kommentar unterdrückt keinen Treffer und kann entfernt werden."',
    '    },',
    '{',
    '      "id": "unknown-rule-id",',
    '      "name": "Unbekannte Regelkennung",',
    '      "description": "Ein lsp-ignore-Kommentar nennt eine Regelkennung, die es nicht gibt, und unterdrückt deshalb nichts. Die Meldung schlägt die ähnlichste bekannte Kennung vor (Tippfehler); ein sol' +
    'cher Kommentar zählt nicht zusätzlich als unused-suppression."',
    '    },',
    '{',
    '      "id": "unit-too-deep",',
    '      "name": "Unit zu tief für die Prüfung",',
    '      "description": "Der Syntaxbaum der Unit ist mehr als 100000 Ebenen tief; die Prüfregeln laufen für sie nicht. So tiefe Bäume entstehen nur aus Ketten mit ebenso vielen Gliedern wie X := A - B - ' +
    'C - … Der Hinweis markiert die tiefste Stelle; wer die Kette in Teilausdrücke aufteilt, macht die Unit wieder prüfbar."',
    '    },',
    '{',
    '      "id": "rule-failed",',
    '      "name": "Prüfregel gescheitert",',
    '      "description": "Eine Prüfregel ist an dieser Unit mit einer Ausnahme abgebrochen, ihre Befunde fehlen. Der Fehler steht an Zeile 1 und nennt Regel und Ausnahmeklasse; ohne ihn sähe die Unit saub' +
    'er aus. Er lässt sich nicht per Kommentar unterdrücken. Das ist ein Fehler in Atlas: bitte mit der Unit oder einem kleinen Beispiel melden."',
    '    },',
    '{',
    '      "id": "slash-command",',
    '      "name": "Schnellbefehl nicht ausgeführt",',
    '      "description": "Eine Zeile, die mit /name beginnt, wurde nicht ausgeführt und steht noch im Code: Der Befehl ist unbekannt, abgeschaltet (slashCommands.disabled) oder passt an dieser Stelle nich' +
    't. Die Meldung nennt den Grund. \"/ignore regel\" meldet sie auch, wenn diese Regel in der Zeile darunter nichts findet."',
    '    }');

implementation

end.
