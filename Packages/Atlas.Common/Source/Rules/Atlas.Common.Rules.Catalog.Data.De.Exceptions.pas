unit Atlas.Common.Rules.Catalog.Data.De.Exceptions;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  CatalogLinesDeExceptions: array[0..39] of string = (
    '{',
    '      "id": "empty-except",',
    '      "name": "Leerer except-Block",',
    '      "description": "Ein except-Block ohne Anweisung verschluckt jede Ausnahme. Ein Block, der nur einen Kommentar enthält, gilt als begründet und wird nicht gemeldet."',
    '    },',
    '{',
    '      "id": "generic-exception-raised",',
    '      "name": "Allgemeine Exception ausgelöst",',
    '      "description": "Wer die Basisklasse Exception auslöst, nimmt Aufrufern die Möglichkeit, den Fehler gezielt zu behandeln. Besser eine eigene Exception-Klasse deklarieren."',
    '    },',
    '{',
    '      "id": "catch-all-without-raise",',
    '      "name": "Exception-Handler ohne erneutes raise",',
    '      "description": "Ein Handler für Exception, der weder erneut auslöst noch das Programm beendet, verschluckt jeden Fehler, auch Programmierfehler. Standardmäßig aus; gedacht für Bibliothekscode."',
    '    },',
    '{',
    '      "id": "exception-freed",',
    '      "name": "Exception-Objekt manuell freigegeben",',
    '      "description": "Die RTL gibt ein Exception-Objekt nach seinem Handler bzw. nach raise selbst frei. Manuelles Freigeben führt zur doppelten Freigabe."',
    '    },',
    '{',
    '      "id": "raise-in-finally",',
    '      "name": "raise in einem finally-Block",',
    '      "description": "Eine im finally-Block ausgelöste Exception ersetzt die gerade laufende Exception, die dadurch verloren geht."',
    '    },',
    '{',
    '      "id": "exception-in-destructor",',
    '      "name": "raise im Destruktor",',
    '      "description": "raise in einem Destruktor (auch class destructor), das kein except im Destruktor abfängt. Die Ausnahme bricht die Freigabe ab: inherited Destroy läuft nicht mehr, das Objekt blei' +
    'bt halb freigegeben, und in einem finally des Aufrufers überdeckt sie die ursprüngliche Ausnahme. Ein raise im try-Teil eines try..except ist abgefangen; raise im except- oder finally-Teil, auch ein e' +
    'rneutes raise;, wird gemeldet. Eingebettete Routinen und anonyme Methoden sind ausgenommen. Aufrufen, die ihrerseits auslösen, folgt die Regel nicht. Konfidenz hoch. Keine Schnellkorrektur: den Zustan' +
    'd protokollieren oder ohne Ausnahme freigeben."',
    '    },',
    '{',
    '      "id": "except-handler-order",',
    '      "name": "Allgemeiner Exception-Handler vor speziellem",',
    '      "description": "In einem try..except mit mehreren on-Handlern gewinnt der erste passende. Ein Handler für eine Klasse, die ein früherer Handler schon fängt, wird nie erreicht: Sein Code ist tot ' +
    'und die Sonderbehandlung läuft nie. Gemeldet, wenn ein früherer Handler dieselbe Klasse, einen Vorfahren davon, Exception (deckt jede Exception-Klasse ab) oder TObject nennt. Vorfahren kommen aus der ' +
    'Unit, dem Projektindex und einer Tabelle bekannter RTL-, VCL- und FireDAC-Exceptions (etwa EStreamError > EFOpenError, EIntError > ERangeError); unbekannte Klassen werden nur mit Exception und TObject' +
    ' verglichen. Korrektur: den speziellen Handler vor den allgemeinen verschieben (nur, wenn beide Handler auf eigenen Zeilen stehen). Ein doppelter Handler für dieselbe Klasse wird ohne Korrektur gemeld' +
    'et."',
    '    },',
    '{',
    '      "id": "reraise-exception-object",',
    '      "name": "raise E statt raise im Handler",',
    '      "description": "raise E; in einem Handler on E: … löst das gefangene Exception-Objekt als neues raise aus. Die RTL gibt das Objekt nicht doppelt frei, aber die Ausnahme beginnt jetzt im Handler:' +
    ' ExceptAddr und die Aufrufliste von Werkzeugen wie madExcept oder JclDebug zeigen auf den Handler statt auf den ursprünglichen Fehler, die Absprungstelle geht verloren. raise; wirft die aktuelle Excep' +
    'tion unverändert weiter. Auch raise E at … wird gemeldet, dann ohne Korrektur. Still, wenn der Handler das Objekt mit AcquireExceptionObject übernimmt oder der Variablen ein neues Objekt zuweist, in a' +
    'nonymen Methoden und bei Handlern ohne Variablennamen. Konfidenz hoch. Korrektur: raise E; → raise;."',
    '    }');

implementation

end.
