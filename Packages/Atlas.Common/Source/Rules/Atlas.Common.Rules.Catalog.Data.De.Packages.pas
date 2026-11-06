unit Atlas.Common.Rules.Catalog.Data.De.Packages;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesDePackages: array[0..26] of string = (
    '{',
    '      "id": "implicit-package-import",',
    '      "name": "Implizit eingebundene Unit",',
    '      "description": "In einem Package (.dpk) verwendet eine Unit aus contains eine Unit, die weder in contains steht noch von einem Package aus requires geliefert wird. Der Compiler zieht sie implizi' +
    't hinein (W1033), was später zu doppelten Units führt, wenn ein anderes Package sie ebenfalls enthält. Die Schnellkorrektur nimmt die Unit in contains auf."',
    '    },',
    '{',
    '      "id": "ota-notifier-not-removed",',
    '      "name": "IDE-Notifier ohne RemoveNotifier",',
    '      "description": "AddNotifier an IOTAServices, IOTAEditorServices, IOTAModule usw. (oder ein anderes Paar aus registerPairs), dessen Index nie an RemoveNotifier geht: Der Aufruf steht als Anweisun' +
    'g ohne Zuweisung, oder die Variable, der er zugewiesen wird, erhält in der Unit kein RemoveNotifier (in finalization, im Destruktor oder in Destroyed). Die IDE ruft den Notifier dann nach dem Entladen' +
    ' des Packages in fremdem Speicher auf. Register…-Aufrufe in der Prozedur Register sind ausgenommen: Diese Wizards entfernt die IDE selbst. Sicherheit mittel. Korrektur in Methoden: Index in ein Feld l' +
    'egen (FNotifierIndex im private-Abschnitt) und RemoveNotifier im Destruktor ergänzen, der bei Bedarf angelegt wird; in Prozeduren der Unit: globale Variable mit -1 und RemoveNotifier in finalization. ' +
    'Keine Korrektur, wenn der Empfänger ein Parameter oder eine lokale Variable ist.",',
    '      "options": [',
    '        {',
    '          "name": "registerPairs",',
    '          "description": "Paare der Open Tools API als [{\"open\": \"AddNotifier\", \"close\": \"RemoveNotifier\"}]; ersetzt die Vorgabe."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "dunitx-test-without-assert",',
    '      "name": "DUnitX-Test ohne Assert",',
    '      "description": "Eine [Test]- oder [TestCase]-Methode, die keine Prüfung aufruft, weder selbst noch über ihre lokalen Routinen, Methoden derselben Klasse, Routinen der Unit oder freie Routinen an' +
    'derer Units, die der Symbolindex kennt (AssertTextPair aus einer gemeinsamen Testunit): Sie ist immer grün. Als Prüfung zählen Aufrufe nach assertPatterns (Vorgabe Assert.*, WillRaise*, Check*), Syste' +
    'm.Assert und Aufrufe an Klassen mit Assert im Namen (TRuleAssert.Reports). Tests mit [WillRaise] oder [Ignore] bleiben still. Sicherheit hoch. Korrekturen: Assert.Pass als Platzhalter einfügen oder zu' +
    'r Methode springen.",',
    '      "options": [',
    '        {',
    '          "name": "assertPatterns",',
    '          "description": "Aufrufe, die als Prüfung zählen, als Muster mit * und ?; ersetzt die Vorgabe."',
    '        }',
    '      ]',
    '    }');

implementation

end.
