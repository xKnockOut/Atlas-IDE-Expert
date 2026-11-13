unit Atlas.Common.Rules.Catalog.Data.De.Packages;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesDePackages: array[0..57] of string = (
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
    '    },',
    '{',
    '      "id": "dunitx-testcase-mismatch",',
    '      "name": "TestCase passt nicht zur Methode",',
    '      "description": "Ein [TestCase], dessen Werte DUnitX der Methode nicht übergeben kann, was erst beim Testlauf auffällt: Die Zahl der Werte weicht von der Zahl der Parameter ab (DUnitX ruft über R' +
    'TTI auf, Vorgabewerte zählen nicht), ein Wert passt nicht zum Typ seines Parameters, oder die Methode hat gar keine Parameter. Geteilt wird wie bei DUnitX: an jedem Zeichen des Trennzeichens (drittes ' +
    'Argument, Vorgabe Komma; keine Anführungszeichen), ein leerer Text ergibt keinen Wert. Geprüfte Typen: Ganzzahlen (dezimal oder hex, $FF, 0xFF), Gleitkomma (Punkt oder Komma als Dezimaltrenner, DUnitX' +
    ' macht aus dem Komma einen Punkt), Boolean (True oder False) und Aufzählungen derselben Datei (über ihre Namen); andere Typen prüft die Regel nicht, ebenso Werte, die kein String-Literal sind (eine Ko' +
    'nstante, ''a'' + ''b''). Neben TestCase(''Name'', ''Werte''[, ''Trenner'']) kennt sie die neueren Formen TestCase(''Werte''[, ''Trenner''[, Trim]]) und NamedTestCase(''Name'', ''Werte''). Nur in Testunits (uses DUnitX.' +
    'TestFramework, TestFramework oder TestInsight.*). Sicherheit hoch. Keine Schnellkorrektur: Was gemeint war, ist offen."',
    '    },',
    '{',
    '      "id": "dunitx-fixture-not-registered",',
    '      "name": "DUnitX-Testklasse nie registriert",',
    '      "description": "Eine Testklasse, die DUnitX nie zu sehen bekommt: Ihre Tests fehlen still. DUnitX findet Testklassen über RegisterTestFixture oder, wenn der Runner der .dpr UseRTTI := True setzt' +
    ' (Projektvorlage von DUnitX), über das Attribut [TestFixture]. 1. Nicht registriert: eine Klasse mit [Test]- bzw. [TestCase]-Methoden, die weder der initialization-Abschnitt der Unit noch eine Routine' +
    ' der Unit, die von dort aufgerufen wird, nennt (TDUnitX.RegisterTestFixture(TKlasse), eigene Helfer wie Registriere([TA, TB])) und keine andere Unit ihrer Projekte nennt, und die außerdem kein [TestFi' +
    'xture] hat oder zu einem Projekt gehört, dessen .dpr einen Runner (TDUnitX.CreateRunner) ohne UseRTTI := True anlegt. Ein Aufruf aus der Option registrationCalls in initialization (eigene Registrierfu' +
    'nktion, die alle Klassen findet) zählt für alle Klassen der Unit. Generische und abstrakte Klassen sowie Vorfahren anderer Klassen der Datei bleiben still. Schnellkorrekturen: TDUnitX.RegisterTestFixt' +
    'ure(TKlasse); in initialization ergänzen, den Abschnitt bei Bedarf anlegen; bei einem Runner mit RTTI auch [TestFixture] vor die Klasse setzen. 2. Unit in keinem Testprojekt: Die Gruppe hat Testprojek' +
    'te, aber keines enthält die Unit. Schnellkorrektur bei genau einem Testprojekt: Unit in uses der .dpr und als DCCReference in die .dproj eintragen. Nur in Testunits und nur mit bekannten Projekten der' +
    ' Gruppe; ohne sie schweigt die Regel. Sicherheit mittel.",',
    '      "options": [',
    '        {',
    '          "name": "registrationCalls",',
    '          "description": "Eigene Registrierfunktionen, die alle Testklassen einer Unit registrieren, wenn initialization sie aufruft, als Name oder Klasse.Name."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "dunitx-istrue-equality",',
    '      "name": "Assert.IsTrue mit Vergleich statt AreEqual",',
    '      "description": "Assert.IsTrue(A = B), Assert.IsFalse(A <> B), Assert.IsTrue(X = nil), Assert.IsTrue(Assigned(X)) und dasselbe mit not: Schlägt der Test fehl, meldet DUnitX nur, dass die Bedingun' +
    'g nicht gilt, ohne die verglichenen Werte. Assert.AreEqual bzw. AreNotEqual zeigt erwartet und erhalten, IsNull und IsNotNull sagen, was vorlag. Korrektur (sicher): AreEqual bzw. AreNotEqual mit der K' +
    'onstante oder dem Literal vorn als erwartetem Wert, IsNull bzw. IsNotNull bei nil und Assigned; ein Meldungsargument bleibt erhalten. Angeboten nur, wenn eine Überladung sicher passt: beide Seiten str' +
    'ing, Boolean oder eine Ganzzahl bis Integer, bei nil und Assigned eine Klasse, ein Interface oder ein Zeiger. Gleitkomma (AreEqual braucht eine Toleranz), Cardinal, Int64, NativeInt (Length eines dyna' +
    'mischen Arrays), Aufzählungen, Mengen, Records, Methodenzeiger und unbekannte Typen bekommen den Hinweis ohne Korrektur. Nur in Testunits (uses DUnitX.TestFramework, TestFramework oder TestInsight.*).' +
    ' Sicherheit hoch."',
    '    },',
    '{',
    '      "id": "dunitx-swapped-expected",',
    '      "name": "Erwarteter und erhaltener Wert vertauscht",',
    '      "description": "Assert.AreEqual, AreNotEqual, AreSame oder AreNotSame, deren erstes Argument weder Literal noch Konstante ist, das zweite aber schon: DUnitX erwartet den erwarteten Wert zuerst, ' +
    'die Meldung beim Fehlschlag nennt deshalb die Konstante als erhaltenen und den berechneten Wert als erwarteten Wert und führt in die Irre. Als Konstante zählen Literale, True, False, nil, deklarierte ' +
    'Konstanten und Aufzählungswerte, auch mit Vorzeichen oder über Operatoren verknüpft. Korrektur (sicher): die beiden Argumente tauschen; weitere Argumente (Meldung, Toleranz) bleiben. Aufrufe mit zwei ' +
    'Konstanten oder zwei berechneten Werten bleiben still. Nur in Testunits (uses DUnitX.TestFramework, TestFramework oder TestInsight.*). Sicherheit hoch."',
    '    },',
    '{',
    '      "id": "dunitx-leak-monitor",',
    '      "name": "DUnitX-Testprogramm ohne Leckmonitor",',
    '      "description": "Ein Programm (.dpr), das DUnitX.TestFramework, aber keinen Leckmonitor von DUnitX (DUnitX.MemoryLeakMonitor.FastMM4 oder .FastMM5) verwendet: Ohne ihn misst DUnitX keine Lecks je' +
    ' Test, die Testmarken im Editor zeigen sie nie. DUnitX.MemoryLeakMonitor.Default zählt nicht, er misst nichts. Gemeldet am Eintrag DUnitX.TestFramework. Korrektur (sicher): den Monitor ins uses eintra' +
    'gen, DUnitX.MemoryLeakMonitor.FastMM5, wenn das Programm FastMM5 verwendet, sonst DUnitX.MemoryLeakMonitor.FastMM4, der auch mit dem Speichermanager der RTL ohne FastMM4.pas arbeitet. Units bleiben st' +
    'ill. Sicherheit hoch."',
    '    }');

implementation

end.
