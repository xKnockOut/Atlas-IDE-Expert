unit Atlas.Common.Rules.Catalog.Data.De1;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  CatalogLinesDe1: array[0..1189] of string = (
    '{',
    '  "rules": [',
    '    {',
    '      "id": "syntax",',
    '      "name": "Syntaxfehler",',
    '      "description": "Der Quelltext lässt sich nicht lesen. Die Meldung nennt wie der Compiler, was erwartet und was gefunden wurde („'';'' erwartet, aber ''end'' gefunden (wie E2029).“), und trägt den Co' +
    'mpilercode: fehlendes '';'' (E2066 zwischen Anweisungen, E2029 in Deklarationen), '';'' vor else (E2153), offener String (E2052) oder Kommentar mit Startzeile (E2057), Anweisungen im interface-Teil (E2050' +
    '), Bezeichner nach einem Punkt am Ende (E2372), strict ohne private oder protected (E2375), class vor etwas anderem als einer Routine, var oder property (E2123), eine Zahl mit leerem Exponenten wie 1.' +
    '5e (E2053), absolute mit einer Adresse statt einer Variablen (E2088), try ohne except oder finally (E2125), for ohne Variable (E2088). Prüfungen am fertigen Baum: procedure mit Ergebnistyp (E2025), De' +
    'klaration einer function ohne Ergebnistyp (E2023; die Kurzform der Implementierung ist erlaubt), Wertparameter ohne Typ (E2067), lokale Variable mit Anfangswert (E2195) oder mehrere Variablen mit eine' +
    'm Anfangswert (E2196), Klassen-, Interface- oder Objekttyp im var-Abschnitt (E2058, in einer Routine dazu E2059) oder lokal in einer Routine (E2059), class operator in einer Klasse, einem Interface od' +
    'er object-Typ (E2123; Operatoren gibt es nur in Records). Die Codes folgen Delphi 13; ältere Versionen meldeten stattdessen E2357, E2060 und E2061, label im interface-Teil (E2049) und goto auf eine ni' +
    'cht deklarierte Marke (E2031; eine Marke der umgebenden Routine meldet label-misuse als E2093). Nach einem offenen String oder Kommentar fallen die Folgefehler weg, weil der Compiler dort abbricht. In' +
    'aktive {$IFDEF}-Zweige werden nicht gemeldet. Korrekturen: '';'' vor else entfernen (sicher, auch beim Speichern), '';'' ergänzen, String schließen, Kommentar am Ende seiner ersten Zeile schließen."',
    '    },',
    '    {',
    '      "id": "language-feature",',
    '      "name": "Sprachmerkmal einer neueren Delphi-Version",',
    '      "description": "Der Code nutzt ein Sprachmerkmal, das der Sprachstand des Projekts noch nicht kennt: Inline-Variable und -Konstante (Delphi 10.3), Managed Record mit class operator Initialize/Fi' +
    'nalize (Delphi 10.4), Ziffern-Trennzeichen 1_000 und Binärliteral %1010 (Delphi 11), mehrzeiliger String '''''' (Delphi 12), If-Ausdruck, „is not“ und „not in“ (Delphi 13). Der Sprachstand ist die ältere' +
    ' aus delphiVersion und minDelphiVersion in atlas.json: minDelphiVersion nennt die älteste Delphi-Version, mit der das Projekt noch übersetzen muss (z. B. „12“ für Code, den Delphi 12 und 13 übersetzen' +
    '). Ohne beide Angaben meldet Atlas nichts. Inaktive Zweige {$IF CompilerVersion >= …} bleiben still, so kann Code für mehrere Versionen nebeneinander stehen. Gemeldet im Editor, von --check, check_cod' +
    'e und dem Claude-Code-Hook (hook_check). Code-Aktionen und Schnellbefehle erzeugen keine Merkmale über den Sprachstand hinaus."',
    '    },',
    '    {',
    '      "id": "asm-invalid",',
    '      "name": "Ungültige Anweisung im Inline-Assembler",',
    '      "description": "Anweisungen in asm-Blöcken, die dcc ablehnt: fehlender Operand (mov eax, ) und esp als Indexregister mit Faktor ([eax + esp * 2]) wie E2105, zwei Register verschiedener Größe (mo' +
    'v al, ebx), lea mit einer Zahl und eine Zahl als Ziel von mov wie E2107 (dcc meldet hier E2107 statt E2108 und E2116), db mit einer lokalen Variablen der Routine wie E2109, OFFSET a + OFFSET b wie E21' +
    '11, eine Zahl über 64 Bit wie E2113, eine Stringkonstante mit mehr als 4 Zeichen an einem 32-Bit-Register wie E2114 und Division durch null (/ 0, mod 0) wie E2118. Gemeldet werden nur mit dcc bestätig' +
    'te Formen, höchstens ein Befund je Anweisung. Anweisungen mit einer Compiler-Direktive oder einem { }-Kommentar in derselben Zeile (Free Pascal schreibt so ARM-Registerlisten), die übrigen Datenbefehl' +
    'e, Register von Win64 (rax, r8 …, unter Win32 mögliche Variablennamen) und Dateien für Free Pascal ({$MODE …}, {$ASMMODE …}) bleiben still."',
    '    },',
    '    {',
    '      "id": "unused-suppression",',
    '      "name": "Ungenutzte Unterdrückung",',
    '      "description": "Ein lsp-ignore-Kommentar unterdrückt keinen Treffer und kann entfernt werden."',
    '    },',
    '    {',
    '      "id": "unknown-rule-id",',
    '      "name": "Unbekannte Regelkennung",',
    '      "description": "Ein lsp-ignore-Kommentar nennt eine Regelkennung, die es nicht gibt, und unterdrückt deshalb nichts. Die Meldung schlägt die ähnlichste bekannte Kennung vor (Tippfehler); ein sol' +
    'cher Kommentar zählt nicht zusätzlich als unused-suppression."',
    '    },',
    '    {',
    '      "id": "unit-too-deep",',
    '      "name": "Unit zu tief für die Prüfung",',
    '      "description": "Der Syntaxbaum der Unit ist mehr als 100000 Ebenen tief; die Prüfregeln laufen für sie nicht. So tiefe Bäume entstehen nur aus Ketten mit ebenso vielen Gliedern wie X := A - B - ' +
    'C - … Der Hinweis markiert die tiefste Stelle; wer die Kette in Teilausdrücke aufteilt, macht die Unit wieder prüfbar."',
    '    },',
    '    {',
    '      "id": "bidi-control",',
    '      "name": "Bidirektionales Steuerzeichen",',
    '      "description": "Bidirektionale Steuerzeichen können Code anders anzeigen, als er kompiliert wird (Trojan Source); auch in Formulardateien. Richtungsmarken in RTL-Text nur mit niedriger Konfidenz' +
    '."',
    '    },',
    '    {',
    '      "id": "invisible-char",',
    '      "name": "Unsichtbares Zeichen",',
    '      "description": "Unsichtbare oder Nullbreiten-Zeichen im Quelltext und in Formulardateien; in Strings und Kommentaren mittlere Konfidenz."',
    '    },',
    '    {',
    '      "id": "control-char",',
    '      "name": "Steuerzeichen",',
    '      "description": "NUL- und Steuerzeichen oder ungültige UTF-8-Bytes im Quelltext und in der Formulardatei; ungültige Bytes mit genauer Zeile und Spalte. Wie dcc gilt eine Datei ohne BOM nur als UT' +
    'F-8, wenn sie ganz gültiges UTF-8 ist; eine ANSI-Datei wird nur dann auf ungültige Bytes geprüft, wenn ihre gültigen UTF-8-Folgen überwiegen. U+FFFD ist im Code ein Fehler, im String ein Hinweis, im K' +
    'ommentar kein Befund."',
    '    },',
    '    {',
    '      "id": "confusable-identifier",',
    '      "name": "Verwechselbarer Bezeichner",',
    '      "description": "Bezeichner mit Zeichen aus mehreren Schriften oder Nicht-ASCII-Zeichen sind mit anderen verwechselbar."',
    '    },',
    '    {',
    '      "id": "forbidden-uses",',
    '      "name": "Verbotene uses-Beziehung",',
    '      "description": "Ein uses-Eintrag verletzt eine Schichtregel unter \"layers\" in atlas.json, z. B. darf *.Common.* nicht Vcl.* verwenden.",',
    '      "options": [',
    '        {',
    '          "name": "layers",',
    '          "description": "Schichtregeln: [{\"from\": Glob, \"deny\": [Globs], \"allow\": [Globs]}]."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "uses-cycle",',
    '      "name": "Zirkuläre Unit-Referenz über uses",',
    '      "description": "Ein uses-Eintrag führt über die uses-Listen anderer Units zurück zur eigenen Unit. Liegt jede Kante des Zyklus im interface-Abschnitt, lehnt der Compiler ihn ab (wie F2047; eine ' +
    'Unit, die sich selbst nennt, wie F2092), und der Befund ist ein Fehler; nur dann nennt die Meldung den Code (#1383); Zyklen mit mindestens einer implementation-Kante erlaubt Delphi, sie koppeln die Un' +
    'its aber eng (Initialisierungsreihenfolge, Neuübersetzen, Testen) und erscheinen mit dem Schweregrad der Regel (Option implementation). Die Meldung zeigt den vollständigen kürzesten Pfad (A → B → C → ' +
    'A), der Befund-Hover jede Kante mit ihrem Abschnitt. Grundlage ist der gemeinsame Uses-Graph über den Symbolindex (#268), inaktive Zweige der bedingten Kompilierung ausgeblendet; die geprüfte Unit zäh' +
    'lt mit ihrem Editor-Stand. Still ohne Projekte (Linter, Datei ohne Projekt), solange Projekte laden oder der Index unvollständig ist, und für Units, die der Uses-Graph nicht kennt.",',
    '      "options": [',
    '        {',
    '          "name": "implementation",',
    '          "description": "Auch Zyklen mit mindestens einer Kante im implementation-Abschnitt melden (vom Compiler erlaubt)."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "architecture-role-import",',
    '      "name": "Import verletzt die Rollenmatrix",',
    '      "description": "Ein uses-Eintrag verletzt die Importmatrix des Rollenkonzepts (Ausgabeartefakt, Feature, Rolle: Contract, Internals, Providers, Adapters, Composition, Hosting). Standardmäßig aus' +
    '; in atlas.json mit der Option \"prefixes\" einschalten. Genehmigte Ausnahmen stehen unter \"allow\" als \"Quelle -> Ziel\"-Globs. Testunits (mit DUnitX, DUnit oder TestInsight im uses) prüft die Rege' +
    'l nicht.",',
    '      "options": [',
    '        {',
    '          "name": "prefixes",',
    '          "description": "Präfixe der Ausgabeartefakte, z. B. \"Atlas.Common\"; ohne Angabe meldet die Regel nichts."',
    '        },',
    '        {',
    '          "name": "hostRoles",',
    '          "description": "Erste Namenssegmente der Host-Units ohne Präfix."',
    '        },',
    '        {',
    '          "name": "allow",',
    '          "description": "Genehmigte Ausnahmen \"Quelle -> Ziel\" (beide Globs)."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "architecture-contract-content",',
    '      "name": "Klasse in einer Contract-Unit",',
    '      "description": "Eine Contract-Unit deklariert im interface eine Klasse. Contracts enthalten nur Records, Interfaces, Aufzählungen und Ausnahmen. Standardmäßig aus; in atlas.json mit der Option \' +
    '"prefixes\" einschalten. Genehmigte Ausnahmen stehen unter \"allow\" als \"Unit.Typ\"-Globs. Testunits prüft die Regel nicht.",',
    '      "options": [',
    '        {',
    '          "name": "prefixes",',
    '          "description": "Präfixe der Ausgabeartefakte, z. B. \"Atlas.Common\"."',
    '        },',
    '        {',
    '          "name": "allow",',
    '          "description": "Genehmigte Ausnahmen \"Unit.Typ\" als Glob."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "forbidden-symbol",',
    '      "name": "Verbotenes Symbol verwendet",',
    '      "description": "Eine Liste unter \"symbols\" in atlas.json verbietet Routinen, Typen, Konstanten, Felder, Properties, Aufzählungswerte oder Bezeichner, jeweils mit Meldung und Ersatz. Verglichen' +
    ' wird über die Namensauflösung, nicht über Text: System.SysUtils.FileExists trifft auch FileExists, aber nicht eine eigene Methode gleichen Namens. Ein Eintrag darf den Namen ab einer Punktgrenze kürz' +
    'en (TThread.Queue) und * enthalten. Bezeichner aus System ohne Quelltext (Writeln, Halt) gelten als System.<Name>. Ist der linke Teil eines qualifizierten Namens gar nicht auflösbar (Unit nicht indexi' +
    'ert), wird der geschriebene Name mit dem Ende des Eintrags verglichen. Je Eintrag: kind (routine, type, constant, field, property, enumValue, identifier = nach Namen ohne Auflösung), message, replacem' +
    'ent, severity, units (Muster der Unit-Namen, \"!\" schließt aus), firstArgument (nur mit diesem ersten Argument, z. B. nil) und allowFirstArgument (erlaubt mit diesem ersten Argument, z. B. ErrOutput)' +
    '; beide vergleichen den Text des Arguments oder den Namen seines Typs (TextFile). Standard aus und ohne Liste stumm; im Profil strict an. Sicherheit hoch. Schnellkorrektur: durch den konfigurierten Er' +
    'satz ersetzen.",',
    '      "options": [',
    '        {',
    '          "name": "symbols",',
    '          "description": "Tabelle der verbotenen Symbole, ein Objekt je Eintrag: name (qualifiziert, * erlaubt), kind (routine, type, constant, field, property, enumValue oder identifier), message, re' +
    'placement, severity, units (Muster, ! schließt aus), firstArgument und allowFirstArgument (Texte oder Typnamen des Arguments)."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "thread-vcl-access",',
    '      "name": "VCL-Zugriff aus einem Thread",',
    '      "description": "TThread.Execute, TThread.CreateAnonymousThread oder TTask greift außerhalb von Synchronize oder Queue auf die VCL zu (Application, Screen, ShowMessage, MessageDlg …). Die VCL ist' +
    ' nicht threadsicher."',
    '    },',
    '    {',
    '      "id": "lock-without-finally",',
    '      "name": "Sperre ohne try/finally",',
    '      "description": "Auf eine Sperre (TCriticalSection.Enter/Acquire, TMonitor.Enter, BeginRead/BeginWrite, TSpinLock.Enter, TMutex.Acquire, EnterCriticalSection oder ein Paar aus der Option lockPair' +
    's) folgt kein try/finally mit der Freigabe. Eine Ausnahme lässt die Sperre gesetzt.",',
    '      "options": [',
    '        {',
    '          "name": "lockPairs",',
    '          "description": "Weitere Sperrpaare als [[\"Sperren\", \"Freigeben\"]]."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "thread-use-after-free-on-terminate",',
    '      "name": "Thread nach dem Start mit FreeOnTerminate benutzt",',
    '      "description": "Ein Thread mit FreeOnTerminate := True kann sich gleich nach dem Start selbst freigeben; danach greift die Variable womöglich auf ein freigegebenes Objekt zu."',
    '    },',
    '    {',
    '      "id": "thread-free-with-free-on-terminate",',
    '      "name": "Free auf einem Thread mit FreeOnTerminate",',
    '      "description": "Free auf einem Thread mit FreeOnTerminate := True gibt ihn doppelt frei."',
    '    },',
    '    {',
    '      "id": "synchronize-in-destructor",',
    '      "name": "Synchronize im Destruktor eines Threads",',
    '      "description": "Synchronize im Destruktor eines TThread-Nachfahren (oder in einer Methode, die er aufruft) verklemmt sich: Der Hauptthread wartet in WaitFor, der Thread auf Synchronize."',
    '    },',
    '    {',
    '      "id": "thread-resume-suspend",',
    '      "name": "Veraltetes TThread.Resume/Suspend",',
    '      "description": "TThread.Resume und Suspend sind veraltet. Einen erzeugten Thread mit Start starten; Suspend hat keinen sicheren Ersatz, stattdessen mit einem Ereignis warten. Still, wenn der dek' +
    'larierte Typ des Empfängers eine vollständige Vorfahrenkette ohne TThread hat (eigene Klassen mit Methoden Resume/Suspend)."',
    '    },',
    '    {',
    '      "id": "result-not-set",',
    '      "name": "Funktionsergebnis eventuell nicht gesetzt",',
    '      "description": "Ein Pfad durch die Funktion endet, ohne Result zuzuweisen. Der Aufrufer liest dann einen undefinierten Wert."',
    '    },',
    '    {',
    '      "id": "possibly-uninitialized",',
    '      "name": "Variable eventuell nicht initialisiert",',
    '      "description": "Eine lokale Variable wird auf einem Pfad gelesen, auf dem ihr nie ein Wert zugewiesen wurde."',
    '    },',
    '    {',
    '      "id": "unreachable-code",',
    '      "name": "Unerreichbarer Code",',
    '      "description": "Eine Anweisung nach Exit, raise, Abort, Halt, Break, Continue oder goto wird nie ausgeführt. Meist ein Rest oder ein falsch gesetzter Sprung. Gemeldet wird nur die erste Anweisun' +
    'g eines unerreichbaren Abschnitts."',
    '    },',
    '    {',
    '      "id": "unused-local",',
    '      "name": "Ungenutzte lokale Variable",',
    '      "description": "Eine lokale Variable ist deklariert, wird aber nie verwendet. Wie Compilerhinweis H2164, aber schon beim Tippen.",',
    '      "options": [',
    '        {',
    '          "name": "ignore",',
    '          "description": "Namensmuster, die nie gemeldet werden (* und ?)."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "unused-parameter",',
    '      "name": "Ungenutzter Parameter",',
    '      "description": "Ein Parameter wird im Rumpf der Routine nicht verwendet. Ausgenommen sind überschriebene und virtuelle Methoden, Ereignis-Handler, published-Methoden, Interface-Implementierungen' +
    ' und Callbacks, auch Routinen in Tabellen von Routinen (typisierte Konstanten, Array-Literale). Eine Routine, die nur aus einer anonymen Methode aufgerufen wird, hat eine freie Signatur und wird gemel' +
    'det. Die Übergabe als Wert in einer anderen Unit sieht die Regel nicht; dort mit lsp-ignore und Grund unterdrücken.",',
    '      "options": [',
    '        {',
    '          "name": "ignore",',
    '          "description": "Namensmuster, die nie gemeldet werden (* und ?)."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "unused-assignment",',
    '      "name": "Zugewiesener Wert ungenutzt",',
    '      "description": "Ein einer lokalen Variable zugewiesener Wert wird überschrieben oder die Routine endet, bevor er gelesen wird. Wie Compilerhinweis H2077, den dcc nur für nicht verwaltete Typen g' +
    'ibt: Bei Strings, dynamischen Arrays, Variants und Records mit solchen Feldern sowie bei Variablen ohne Typangabe nennt die Meldung keinen Code (#1383). Variablen mit Interface-Typ sind ausgenommen: D' +
    'ie Zuweisung hält oder gibt eine Referenz frei (Bereichswächter, Writer := nil). Ebenso still bleibt das Leeren eines zuvor gesetzten Werts (X := nil, '''', Default(T), T.Empty): Es gibt Speicher und Re' +
    'ferenzen vorzeitig frei oder schützt nach Free. Leeren ohne vorherigen Wert wird weiter gemeldet.",',
    '      "options": [',
    '        {',
    '          "name": "ignore",',
    '          "description": "Namensmuster, die nie gemeldet werden (* und ?)."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "duplicate-assignment",',
    '      "name": "Feld oder Property wird zweimal gesetzt",',
    '      "description": "Dasselbe Feld oder dieselbe Property (Panel.Left, Self.FWert, P^.X) bekommt zweimal hintereinander einen Wert, ohne dass dazwischen gelesen oder etwas aufgerufen wird; meist soll' +
    'te die zweite Zeile ein anderes Ziel haben (Left/Top). Dazwischen dürfen nur Zuweisungen an andere Objekte stehen, deren Werte nichts aufrufen und das Ziel nicht nennen; der zweite Wert darf das Ziel ' +
    'nicht lesen. Lokale Variablen deckt unused-assignment ab, Ziele mit Index oder Aufruf zählen nicht. Still beim Wechsel False/True (stößt oft etwas an, etwa Active), bei einer zweiten Zuweisung, die nu' +
    'r unter einer weiteren Bedingung übersetzt wird ({$IFDEF DEBUG}), bei verschiedenen Zweigen desselben {$IFDEF} und bei Properties aus allowProperties. Fehlt das Gegenstück (Left/Top, Width/Height …) i' +
    'n der Folge, nennt die Meldung es als Vermutung. Konfidenz hoch. Keine Schnellkorrektur; Sprung zur ersten Zuweisung.",',
    '      "options": [',
    '        {',
    '          "name": "allowProperties",',
    '          "description": "Properties, bei denen doppeltes Setzen gewollt sein kann (Setter mit Nebenwirkung), Muster mit * und ?."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "declared-not-implemented",',
    '      "name": "Deklariert, aber nicht implementiert",',
    '      "description": "Eine Methode ist in einer Klasse, einem Record oder Objekt deklariert, hat aber keinen Rumpf im implementation-Abschnitt. Der Compiler meldet das erst beim Kompilieren (E2065). E' +
    'inen Rumpf gleichen Namens mit anderem Kopf meldet stattdessen signature-mismatch."',
    '    },',
    '    {',
    '      "id": "implemented-not-declared",',
    '      "name": "Implementiert, aber nicht deklariert",',
    '      "description": "Ein Methodenrumpf TFoo.Bar hat keine Deklaration dieses Namens im Typ. Eine gleichnamige Deklaration mit anderem Kopf meldet stattdessen signature-mismatch."',
    '    },',
    '    {',
    '      "id": "destroy-without-override",',
    '      "name": "Destroy ohne override",',
    '      "description": "Ein destructor Destroy ist ohne override deklariert. Free ruft TObject.Destroy auf, dieser Destruktor läuft also nie."',
    '    },',
    '    {',
    '      "id": "setter-recursion",',
    '      "name": "Setter oder Getter ruft sich selbst auf",',
    '      "description": "Ein Setter weist an die eigene Property zu (Name := Value in SetName) oder ein Getter liest sie (Result := Name in GetName). Das ergibt eine Endlosrekursion und einen Stapelüberl' +
    'auf zur Laufzeit; der Compiler schweigt. Schnellkorrektur: das Feld verwenden (das Feld aus der Property-Deklaration, sonst F und der Name, wenn die Klasse es hat). Früher recursive-property-accessor;' +
    ' Einstellungen und Unterdrückungen mit der alten Kennung wirken weiter."',
    '    },',
    '    {',
    '      "id": "component-create-without-override",',
    '      "name": "Komponentenkonstruktor ohne override",',
    '      "description": "Ein TComponent-Nachfahre deklariert constructor Create(AOwner: TComponent) ohne override. Beim Laden aus der Formulardatei wird der virtuelle Konstruktor benutzt und dieser überg' +
    'angen."',
    '    },',
    '    {',
    '      "id": "hides-virtual",',
    '      "name": "Methode verdeckt virtuelle Methode",',
    '      "description": "Eine Methode heißt wie eine virtuelle Methode eines Vorfahren, überschreibt sie aber weder noch führt sie sie neu ein (Compilerwarnung W1010)."',
    '    },',
    '    {',
    '      "id": "virtual-instead-of-override",',
    '      "name": "virtual statt override",',
    '      "description": "Ein Nachfahre deklariert eine Methode als virtual, obwohl der Vorfahr schon eine virtuelle Methode mit derselben Signatur hat; das beginnt eine neue Kette statt zu überschreiben.' +
    '"',
    '    },',
    '    {',
    '      "id": "captured-loop-variable",',
    '      "name": "Erfasste Schleifenvariable",',
    '      "description": "Eine anonyme Methode, die an eine verzögert ausführende API (TThread.Queue, TTask.Run …) geht, erfasst eine Variable, die sich vor dem Aufruf noch ändert, etwa die Variable einer' +
    ' for-in-Schleife. Delphi erfasst die Variable, nicht ihren Wert. Still, wenn die anonyme Methode die Variable selbst zuweist (Ereignisse, die einen Zustand fortschreiben).",',
    '      "options": [',
    '        {',
    '          "name": "deferredApis",',
    '          "description": "Weitere verzögerte APIs (zusätzlich zu TThread.Queue, TTask.Run u. a.)."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "component-missing-inherited",',
    '      "name": "Komponentenmethode ohne inherited",',
    '      "description": "Ein überschriebenes Loaded, CreateParams, CreateWnd, Notification, SetParent, Destroy oder Paint einer Komponente ruft inherited nicht auf; die VCL überspringt dann ihre eigene A' +
    'rbeit. Paint wird nur gemeldet, wenn das Paint eines Vorfahren selbst zeichnet (TCustomPanel, TImage, ein Grid oder eine Klasse aus Datei oder Index, die Paint deklariert), mit mittlerer Konfidenz; TC' +
    'ustomForm und TPaintBox lösen zur Laufzeit nur OnPaint aus, dort zählt ein Paint ohne inherited nur, wenn die Unit OnPaint benutzt oder eine Formulardatei hat; TCustomControl.Paint und TGraphicControl' +
    '.Paint sind leer, dort ist ein Paint ohne inherited üblich."',
    '    },',
    '    {',
    '      "id": "component-default-mismatch",',
    '      "name": "default passt nicht zum Konstruktor",',
    '      "description": "Eine Eigenschaft gibt einen default-Wert an, der Konstruktor setzt das Feld aber auf ein anderes Literal. Werte gleich default speichert die DFM nicht, deshalb wird die Eigenscha' +
    'ft falsch geladen."',
    '    },',
    '    {',
    '      "id": "component-missing-free-notification",',
    '      "name": "Komponentenreferenz ohne FreeNotification",',
    '      "description": "Eine Eigenschaft verweist auf eine andere Komponente, ihr Setter ruft aber FreeNotification nicht auf. Wird die andere Komponente freigegeben, bleibt ein ungültiger Zeiger zurück' +
    '. Im Konstruktor erzeugte Unterkomponenten sind ausgenommen."',
    '    },',
    '    {',
    '      "id": "component-setter-without-invalidate",',
    '      "name": "Setter ohne Invalidate",',
    '      "description": "Ein Setter ändert ein Feld, das Paint liest, ruft aber weder Invalidate noch Repaint, Refresh oder Changed auf. Das Steuerelement zeigt weiter den alten Zustand."',
    '    },',
    '    {',
    '      "id": "component-fixed-pixels",',
    '      "name": "Feste Pixelwerte",',
    '      "description": "Paint oder Resize verwenden feste Pixelwerte, die über 96 dpi zu klein sind. Werte über ScaleValue oder MulDiv oder über eine Methode der Klasse, die selbst skaliert (ruft ScaleV' +
    'alue, MulDiv oder eine Routine Scale… auf), 0, 1 und -1 sowie Faktoren von Multiplikationen und Divisionen werden nicht gemeldet."',
    '    },',
    '    {',
    '      "id": "component-hardcoded-color",',
    '      "name": "Feste Farbe in Paint",',
    '      "description": "Paint verwendet ein RGB-Literal, eine $00BBGGRR-Konstante oder einen TColor-Cast. Solche Farben ignorieren VCL-Styles; Systemfarben wie clBtnFace sind in Ordnung."',
    '    },',
    '    {',
    '      "id": "form-field-without-object",',
    '      "name": "Formularfeld ohne Objekt",',
    '      "description": "Ein published-Komponentenfeld der Formularklasse hat kein Objekt in der .dfm/.fmx neben der Unit. Nach dem Laden bleibt das Feld nil. Felder außerhalb von published werden nicht ' +
    'geprüft."',
    '    },',
    '    {',
    '      "id": "form-object-without-field",',
    '      "name": "Formularobjekt ohne Feld",',
    '      "description": "Ein Objekt der Formulardatei hat kein Feld in der Formularklasse. Geerbte Objekte, Objekte in inline-Frames, namenlose Komponenten und Collection-Einträge werden übergangen. Die ' +
    'Korrektur ergänzt das Feld."',
    '    },',
    '    {',
    '      "id": "form-field-type-mismatch",',
    '      "name": "Feldtyp weicht vom Formularobjekt ab",',
    '      "description": "Der Typ des Felds weicht von der Klasse des Objekts in der Formulardatei ab. Ohne Quelltext der Klasse aus der Formulardatei wird nicht verglichen. Die Korrektur ändert den Feldt' +
    'yp."',
    '    },',
    '    {',
    '      "id": "security-command-injection",',
    '      "name": "Befehlsinjektion",',
    '      "description": "ShellExecute, ShellExecuteEx, CreateProcess oder WinExec erhält ein Argument, das mit +, Format oder Concat aus nicht konstanten Werten zusammengesetzt ist. Eingaben könnten weit' +
    'ere Befehle einschleusen. Ohne Datenflussanalyse wird nur dieses einfache Muster erkannt (mittlere Konfidenz)."',
    '    },',
    '    {',
    '      "id": "security-path-traversal",',
    '      "name": "Pfad-Traversal",',
    '      "description": "Ein Dateizugriff (TFileStream.Create, LoadFromFile, AssignFile, TFile.*) verwendet einen Pfad aus Eingabedaten (Text, ParamStr, Request) ohne Prüfung über TPath.GetFullPath. Expe' +
    'rimentell, bis die Datenflussanalyse verfügbar ist."',
    '    },',
    '    {',
    '      "id": "security-weak-crypto",',
    '      "name": "Schwache Kryptografie",',
    '      "description": "MD5, SHA-1, DES oder RC4 wird verwendet. Für Prüfsummen ist das in Ordnung, für Kennwörter und Signaturen nicht. Niedrige Konfidenz, mittlere, wenn die Anweisung ein Kennwort, Ge' +
    'heimnis oder eine Signatur nennt."',
    '    },',
    '    {',
    '      "id": "security-tls-verification-disabled",',
    '      "name": "TLS-Zertifikatsprüfung abgeschaltet",',
    '      "description": "Indy SSLOptions.VerifyMode := [], ein OnVerifyPeer-Handler, der immer True liefert, oder ein ValidateServerCertificate-Handler, der Accepted := True ohne Prüfung setzt."',
    '    },',
    '    {',
    '      "id": "security-insecure-http",',
    '      "name": "Unverschlüsselte http://-URL",',
    '      "description": "Ein String enthält eine http://-URL. XML-Namensräume und Schema-URIs, Kommentare sowie localhost, 127.0.0.1 und [::1] sind ausgenommen. Die Korrektur ersetzt http:// durch https:' +
    '//."',
    '    },',
    '    {',
    '      "id": "security-insecure-random",',
    '      "name": "Random für sicherheitsrelevante Werte",',
    '      "description": "Random wird einem Token, Kennwort, Salt, Nonce oder Schlüssel zugewiesen. Random ist vorhersagbar; einen kryptografischen Zufallsgenerator verwenden. Fehlendes Randomize behandel' +
    't #153."',
    '    },',
    '    {',
    '      "id": "dfm-circular-datasource",',
    '      "name": "Zirkuläre Master-Detail- bzw. DataSource-Verknüpfung",',
    '      "description": "MasterSource/DataSource-Verknüpfungen der Formulardatei bilden einen Kreis (tblA → dsB → tblB → dsA → tblA). Das Öffnen der Datasets läuft in eine Rekursion oder zeigt keine stim' +
    'migen Daten."',
    '    },',
    '    {',
    '      "id": "dfm-master-without-fields",',
    '      "name": "Master-Detail ohne MasterFields",',
    '      "description": "Ein Dataset hat MasterSource, aber keine MasterFields. Das Detail wird nicht gefiltert und zeigt alle Datensätze."',
    '    },',
    '    {',
    '      "id": "dfm-required-field-without-control",',
    '      "name": "Pflichtfeld ohne sichtbares Eingabe-Control",',
    '      "description": "Ein persistentes Feld mit Required = True ist an kein sichtbares datensensitives Control gebunden (ein Gitter ohne DataField zählt für alle Felder). Der Anwender kann es nicht fü' +
    'llen, Post schlägt fehl."',
    '    },',
    '    {',
    '      "id": "dfm-control-field-type-mismatch",',
    '      "name": "Datensensitives Control passt nicht zum Feldtyp",',
    '      "description": "Das Control passt nicht zum persistenten Feld, z. B. TDBEdit an einem TBooleanField oder Blob-Feld, TDBImage an einem Feld ohne Grafik."',
    '    },',
    '    {',
    '      "id": "dfm-duplicate-binding",',
    '      "name": "Zwei Controls an demselben Feld",',
    '      "description": "Zwei Eingabe-Controls nutzen dieselbe DataSource und dasselbe DataField. Meist ein Kopierfehler. Anzeige-Controls (TDBText, TDBImage) zählen nicht."',
    '    },',
    '    {',
    '      "id": "dfm-property",',
    '      "name": "Komponenten-Property verletzt eine Eigenschaftsregel",',
    '      "description": "Eine Komponenten-Property in der Formulardatei erfüllt eine Regel aus dfmPropertyRules in atlas.json nicht (Klasse, Property, Bedingung, Wert). Nicht gespeicherte Properties zähl' +
    'en mit ihrem default-Wert; Objekte aus dem Vorfahrenformular werden nur gemeldet, wenn dieses Formular den Wert selbst setzt. Die Schnellkorrektur setzt den Wert in der Formulardatei (fix: auto auch m' +
    'it source.fixAll); der Befehl \"Eigenschaftsregeln anwenden\" korrigiert ein Formular, das Projekt oder die Gruppe mit Vorschau."',
    '    },',
    '    {',
    '      "id": "foreign-form-control-access",',
    '      "name": "Zugriff auf Controls eines anderen Formulars",',
    '      "description": "Code greift über die globale Variable auf ein Feld eines Formulars oder Frames aus einer anderen Unit zu (Form2.Edit1.Text). Das koppelt die Units eng; besser eine Methode oder P' +
    'roperty des Formulars nutzen."',
    '    },',
    '    {',
    '      "id": "security-sql-injection",',
    '      "name": "SQL-Text aus zusammengesetzten Werten (SQL-Injection)",',
    '      "description": "SQL.Text, SQL.Add, CommandText, ExecSQL oder Open erhalten Text, der per + oder Format aus Nicht-Konstanten zusammengesetzt ist. Benutzereingaben könnten SQL einschleusen. Parame' +
    'ter verwenden (:Name, ParamByName). Konstanten, resourcestrings, IntToStr und QuotedStr zählen nicht; Benutzereingaben (TEdit.Text, TMemo.Lines) heben die Konfidenz auf hoch."',
    '    },',
    '    {',
    '      "id": "slash-command",',
    '      "name": "Schnellbefehl nicht ausgeführt",',
    '      "description": "Eine Zeile, die mit /name beginnt, wurde nicht ausgeführt und steht noch im Code: Der Befehl ist unbekannt, abgeschaltet (slashCommands.disabled) oder passt an dieser Stelle nich' +
    't. Die Meldung nennt den Grund. \"/ignore regel\" meldet sie auch, wenn diese Regel in der Zeile darunter nichts findet."',
    '    },',
    '    {',
    '      "id": "empty-except",',
    '      "name": "Leerer except-Block",',
    '      "description": "Ein except-Block ohne Anweisung verschluckt jede Ausnahme. Ein Block, der nur einen Kommentar enthält, gilt als begründet und wird nicht gemeldet."',
    '    },',
    '    {',
    '      "id": "interface-guid",',
    '      "name": "Interface ohne GUID",',
    '      "description": "Ein Interface deklariert keine GUID. Supports, as und QueryInterface brauchen eine. Die Konfidenz ist hoch, wenn das Interface in derselben Datei damit verwendet wird, sonst nied' +
    'rig; mit einer solchen Verwendung meldet Delphi dort E2232 (wie E2232). Die Schnellkorrektur fügt eine neue GUID ein. Ein dispinterface ohne GUID übersetzt nicht; das meldet dispinterface-invalid."',
    '    },',
    '    {',
    '      "id": "duplicate-interface-guid",',
    '      "name": "Zwei Interfaces mit derselben GUID",',
    '      "description": "Zwei Interfaces der Datei deklarieren dieselbe GUID, meist nach dem Kopieren einer Deklaration. Supports und as verwechseln sie dann. Die Schnellkorrektur erzeugt eine neue GUID.' +
    '"',
    '    },',
    '    {',
    '      "id": "file-header",',
    '      "name": "Dateikopf fehlt oder weicht ab",',
    '      "description": "Die Datei beginnt nicht mit dem Kopf aus der Regeloption \"template\". Standardmäßig aus; in atlas.json mit einer Vorlage einschalten. Die Schnellkorrektur fügt den Kopf ein.",',
    '      "options": [',
    '        {',
    '          "name": "template",',
    '          "description": "Erwarteter Dateikopf; Platzhalter wie dokumentiert."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "hardcoded-string",',
    '      "name": "Text im Code statt resourcestring",',
    '      "description": "In einer Anweisung steht ein String mit Wörtern für Menschen. In einen resourcestring auslagern, damit er übersetzt werden kann. Standardmäßig aus, niedrige Konfidenz."',
    '    },',
    '    {',
    '      "id": "self-assignment",',
    '      "name": "Zuweisung an sich selbst",',
    '      "description": "Einer Variablen, einem Feld oder einer Property wird der eigene Wert zugewiesen. Gemeint ist meist ein anderer Wert, etwa ein Parameter oder ein anderes Feld. Verdeckt ein Parame' +
    'ter oder eine lokale Variable ein gleichnamiges Feld (Name := Name), bietet Atlas Self.Name := Name als Korrektur an."',
    '    },',
    '    {',
    '      "id": "for-high-to-low",',
    '      "name": "for-Schleife zählt mit to abwärts",',
    '      "description": "Die Schleife beginnt beim oberen Wert (High, Count - 1) und endet beim unteren, verwendet aber to. Sie läuft nie; gemeint war downto. Ebenso Schleifen mit konstanten Grenzen, die' +
    ' nie laufen, etwa for I := 10 to 1, auch mit Vorzeichen, Hex- oder Zeichenliteralen (wie H2135). Gleiche Grenzen, Ausdrücke, benannte Konstanten und aufsteigende Grenzen bleiben still. Korrektur: to d' +
    'urch downto ersetzen."',
    '    },',
    '    {',
    '      "id": "conditional-expression-version",',
    '      "name": "Bedingungsausdruck vor Delphi 13",',
    '      "description": "Den Bedingungsausdruck X := if C then A else B gibt es erst ab Delphi 13; ein Projekt, das noch mit Delphi 12 oder älter übersetzen muss, scheitert hier (wie E2029). Gemeldet wir' +
    'd der äußerste Ausdruck, nicht in Zweigen von {$IF}, die nach CompilerVersion, RTLVersion, VERnnn oder Declared fragen. Ohne bekannte Delphi-Version still. Korrektur (auch für die ganze Unit): in eine' +
    ' if-Anweisung umwandeln, die Anweisung je Zweig wiederholt; nicht angeboten, wenn der Rest der Anweisung Seiteneffekte hat."',
    '    },',
    '    {',
    '      "id": "exception-not-raised",',
    '      "name": "Exception erzeugt, aber nicht ausgelöst",',
    '      "description": "Ein Exception-Objekt wird als eigene Anweisung erzeugt. Ohne raise passiert nichts, und das Objekt bleibt als Speicherleck zurück."',
    '    },',
    '    {',
    '      "id": "assert-side-effect",',
    '      "name": "Assert mit Seiteneffekt",',
    '      "description": "Das Argument von Assert verändert Daten (Inc, Dec, eine Try…-Funktion mit out-Parameter oder eine Methode aus der Option mutatingMethods). Mit {$C-} entfernt der Compiler den gan' +
    'zen Aufruf samt Seiteneffekt.",',
    '      "options": [',
    '        {',
    '          "name": "mutatingMethods",',
    '          "description": "Methoden, die ihr Objekt verändern."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "ifthen-side-effect",',
    '      "name": "IfThen wertet beide Zweige aus",',
    '      "description": "IfThen ist eine Funktion: Beide Zweige werden vor dem Aufruf ausgewertet. Ein Nil-Zugriff oder Funktionsaufruf im nicht gewählten Zweig passiert trotzdem. Hohe Konfidenz, wenn ei' +
    'n Zweig einen in der Bedingung geprüften Namen dereferenziert, mittlere bei einem Funktionsaufruf."',
    '    },',
    '    {',
    '      "id": "random-without-randomize",',
    '      "name": "Random ohne Randomize",',
    '      "description": "Random wird verwendet, aber die Unit ruft nie Randomize auf; jeder Start liefert dieselbe Folge. Randomize steht oft in der .dpr, deshalb ist die Regel standardmäßig aus und hat ' +
    'niedrige Konfidenz."',
    '    },',
    '    {',
    '      "id": "int32-mul-overflow",',
    '      "name": "Int32-Multiplikation an Int64 zugewiesen",',
    '      "description": "Beide Operanden haben höchstens 32 Bit; das Produkt wird in 32 Bit gerechnet und läuft über, bevor es der Int64-Variablen zugewiesen wird. Einen Operanden nach Int64 umwandeln."',
    '    },',
    '    {',
    '      "id": "sizeof-pointer",',
    '      "name": "SizeOf eines Zeigers in Move oder FillChar",',
    '      "description": "SizeOf eines Zeigers, Strings oder dynamischen Arrays ist die Größe des Verweises (4 oder 8 Byte), nicht die der Daten. Move und FillChar kopieren bzw. löschen dann zu wenig."',
    '    },',
    '    {',
    '      "id": "char-to-pchar",',
    '      "name": "Char nach PChar umgewandelt",',
    '      "description": "PChar(C) mit einer Char-Variablen macht aus dem Zeichencode eine Adresse. Gemeint war ein String."',
    '    },',
    '    {',
    '      "id": "unrelated-class-cast",',
    '      "name": "Harte Umwandlung zwischen nicht verwandten Klassen",',
    '      "description": "TButton(Obj) prüft nichts. Ist der statische Typ von Obj weder Vorfahr noch Nachfahr von TButton (z. B. TEdit oder TForm), liest der Zugriff Speicher eines Objekts mit anderem Au' +
    'fbau. Gemeldet wird nur, wenn beide Typen sicher bekannt sind, beide Vererbungsketten bis TObject bekannt sind und beide Deklarationen immer mit der Umwandlung übersetzt werden. Interfaces, Zeiger, Za' +
    'hlen, TObject als Quelle und Umwandlungen in oder aus Klassenreferenzen (class of) bleiben still, ebenso der Zugriffsklassen-Trick: Das Ziel und seine Vorfahren bis zu einem gemeinsamen Vorfahren dekl' +
    'arieren weder Felder noch neue virtuelle Methoden (THackControl = class(TControl)), der Aufbau ist also derselbe. Sicherheit hoch. Korrektur: (Obj as TButton) prüft den Typ zur Laufzeit.",',
    '      "options": [',
    '        {',
    '          "name": "allowTypes",',
    '          "description": "Typen, die absichtlich hart umgewandelt werden: ein Typname (als Quelle oder Ziel) oder ein Paar \"Quelle=Ziel\"."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "first-char-address",',
    '      "name": "Adresse des ersten Zeichens über S[1]",',
    '      "description": "@S[1] und PChar(@S[1]) lösen bei leerem String mit {$R+} einen Bereichsfehler aus, ohne Bereichsprüfung ergibt sich nil oder Müll. Außerdem erzwingt der Indexzugriff eine eindeut' +
    'ige Kopie (UniqueString). PChar(S) und Pointer(S) sind auch für leere Strings sicher. Gilt für string, UnicodeString, WideString, AnsiString, RawByteString und UTF8String, auch S[Low(S)]; ShortString,' +
    ' Arrays und andere Indizes bleiben still. Gemeldet wird nur, wenn der Typ von S sicher bekannt ist. Sicherheit hoch. Korrektur bei const-Parametern: durch PChar(S) ersetzen (PAnsiChar bei AnsiString-T' +
    'ypen), ein umgebendes PChar(…), PAnsiChar(…), PWideChar(…), PByte(…) oder Pointer(…) wird als Ganzes ersetzt. Bei anderen Strings kann der Zeiger zum Schreiben dienen, dann ist die eigene Kopie gewoll' +
    't; dort gibt es keine Korrektur, die Meldung nennt UniqueString(S)."',
    '    },',
    '    {',
    '      "id": "float-equality",',
    '      "name": "Gleitkommavergleich mit = oder <>",',
    '      "description": "Gleitkommawerte sind nach Berechnungen selten exakt gleich. Mit SameValue aus System.Math und einer Toleranz vergleichen. Vergleiche mit 0 werden nicht gemeldet."',
    '    },',
    '    {',
    '      "id": "constructor-on-instance",',
    '      "name": "Konstruktor auf einer Instanz aufgerufen",',
    '      "description": "Create wird auf einer Variablen statt auf der Klasse aufgerufen. Das legt kein neues Objekt an; mit nicht zugewiesener Variable stürzt es ab. Klassenreferenzen (class of …) werde' +
    'n nicht gemeldet."',
    '    },',
    '    {',
    '      "id": "format-without-settings",',
    '      "name": "Formatierung abhängig vom Gebietsschema",',
    '      "description": "Format mit %f, %n, %m, %g oder %e und Funktionen wie FloatToStr, StrToFloat oder DateToStr ohne TFormatSettings-Parameter verwenden das Gebietsschema des Benutzers (Dezimaltrenne' +
    'r, Datumsformat). Für Dateien, Protokolle und Logs feste TFormatSettings übergeben. Format(''%d'', …) wird nicht gemeldet, ebenso wenig FormatDateTime und FormatFloat mit festem Bild ohne Trennzeichen (' +
    ': / . ,) wie ''yyyy\"-\"mm\"-\"dd'' oder ''ddddd t''."',
    '    },',
    '    {',
    '      "id": "format-args",',
    '      "name": "Formatstring passt nicht zu den Argumenten",',
    '      "description": "Format, FmtStr, FormatBuf, StrFmt, StrLFmt, WideFormat, WideFmtStr, Exception.CreateFmt bzw. CreateFmtHelp und TStringBuilder.AppendFormat mit bekanntem Formatstring (Literal, mi' +
    't + verbundene Literale, const oder resourcestring der Datei bzw. des Index), dessen Platzhalter nicht zur Argumentliste [...] passen: ungültiger Platzhalter (%q, ''%'' bzw. ''%5'' am Ende, %0: ohne Typbu' +
    'chstaben), weniger Argumente als Platzhalter oder ein Argument vom falschen Typ: %d %u %x nur Ganzzahlen, %e %f %g %n %m nur Gleitkommazahlen, %s Strings, Zeichen und Variants, %p Zeiger und Objekte, ' +
    'ein * für Breite bzw. Genauigkeit eine Ganzzahl; Variants passen überall. Boolean und Aufzählungswerte werden bei jedem Typbuchstaben gemeldet, mit Ord(...) bzw. BoolToStr(..., True) als Hinweis. All ' +
    'das löst zur Laufzeit EConvertError aus. Ein Argument hinter dem letzten verwendeten wird mit mittlerer Sicherheit gemeldet (nur ohne Index im Formatstring), es wird nie ausgegeben. Typen werden nur g' +
    'eprüft, wenn sie sicher bekannt sind; Formatstrings aus Variablen, Index * und Bereiche bleiben still. Eigene Routinen namens Format bleiben still, wenn die Namensauflösung sie findet. Teilt die Zerle' +
    'gung der Formatstrings mit format-without-settings. Keine Korrektur. Sicherheit hoch.",',
    '      "options": [',
    '        {',
    '          "name": "formatMethods",',
    '          "description": "Weitere Routinen mit Formatstring und folgender Argumentliste array of const, z. B. \"TLogger.LogFmt\" oder \"Protokoll\". Mit Punkt zählt ohne Namensauflösung der Methodenna' +
    'me hinter einem beliebigen Qualifizierer."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "generic-exception-raised",',
    '      "name": "Allgemeine Exception ausgelöst",',
    '      "description": "Wer die Basisklasse Exception auslöst, nimmt Aufrufern die Möglichkeit, den Fehler gezielt zu behandeln. Besser eine eigene Exception-Klasse deklarieren."',
    '    },',
    '    {',
    '      "id": "catch-all-without-raise",',
    '      "name": "Exception-Handler ohne erneutes raise",',
    '      "description": "Ein Handler für Exception, der weder erneut auslöst noch das Programm beendet, verschluckt jeden Fehler, auch Programmierfehler. Standardmäßig aus; gedacht für Bibliothekscode."',
    '    },',
    '    {',
    '      "id": "exception-freed",',
    '      "name": "Exception-Objekt manuell freigegeben",',
    '      "description": "Die RTL gibt ein Exception-Objekt nach seinem Handler bzw. nach raise selbst frei. Manuelles Freigeben führt zur doppelten Freigabe."',
    '    },',
    '    {',
    '      "id": "string-concat-in-loop",',
    '      "name": "String-Verkettung in einer Schleife",',
    '      "description": "Eine String-Variable wird in einer Schleife schrittweise verlängert. Delphi vergrößert Strings meist an Ort und Stelle, deshalb nur mit niedriger Konfidenz und standardmäßig aus;' +
    ' bei vielen Durchläufen ist TStringBuilder schneller."',
    '    },',
    '    {',
    '      "id": "loop-invariant-call",',
    '      "name": "Teurer Aufruf in der Schleifenbedingung",',
    '      "description": "Die Bedingung von while und until wird bei jedem Durchlauf ausgewertet. Aufrufe wie Trim, Format oder FileExists und Eigenschaften wie Lines.Text werden dort jedes Mal neu berech' +
    'net; besser einmal vor der Schleife. Die Grenzen von for werden nur einmal ausgewertet und nicht gemeldet. Standardmäßig aus."',
    '    },',
    '    {',
    '      "id": "missing-begin-update",',
    '      "name": "Hinzufügen in einer Schleife ohne BeginUpdate",',
    '      "description": "Items.Add, Lines.Add und ähnliche Aufrufe in einer Schleife zeichnen das Steuerelement bei jedem Aufruf neu. Die Schleife mit BeginUpdate und try … finally EndUpdate umschließen.' +
    ' Still bei Menüs (TMenuItem hat kein BeginUpdate) und bei for-Schleifen mit höchstens 10 Durchläufen (feste Grenzen oder ein statisches Array derselben Datei). Standardmäßig aus."',
    '    },',
    '    {',
    '      "id": "setlength-in-loop",',
    '      "name": "Array wächst in der Schleife um je ein Element",',
    '      "description": "SetLength(A, Length(A) + 1) in einer Schleife kopiert das dynamische Array bei jedem Durchlauf. Die Regel meldet nur, wenn A sicher ein dynamisches Array ist (array of, TArray<T>' +
    ', ein Array-Typ der Datei oder ein bekannter RTL-Typ wie TBytes), nie bei Strings. In einer for-Schleife ist die Anzahl bekannt: Die Meldung nennt sie, und ist A eine lokale Variable, die vor der Schl' +
    'eife nicht benutzt und darin nur als A[High(A)] bzw. A[Length(A) - 1] beschrieben wird, setzt die Schnellkorrektur die Länge einmal vor der Schleife und indiziert mit der Schleifenvariable. Sonst die ' +
    'Werte in einer TList<T> sammeln."',
    '    },',
    '    {',
    '      "id": "managed-param-without-const",',
    '      "name": "Verwalteter Parameter ohne const",',
    '      "description": "Ein Wertparameter vom Typ String, Interface, dynamisches oder offenes Array oder ein Record der Datei ab minRecordSize Byte, den die Routine nie verändert. Jeder Aufruf zahlt Ref' +
    'erenzzählung bzw. Kopie; const spart beides. Verändert heißt: zugewiesen, ein Teil zugewiesen (Zeichen, Felder, Elemente), an var oder out übergeben, @Parameter, Methodenaufruf an einem Record, Laufva' +
    'riable einer for-Schleife. Die Regel meldet nur, wenn das sicher ist: Aufrufe mit unbekannter Signatur (Methoden ohne Symbolindex, Überladungen), with-Blöcke, Einfangen in anonymen Methoden, inherited' +
    ' ohne Namen und asm lassen sie schweigen. Virtuelle, dynamische, abstrakte und message-Methoden, Aufrufkonventionen, external- und exportierte Routinen, Methoden von Klassen mit Interfaces, published-' +
    'Methoden und als Wert benutzte Methoden (Ereignisse, @Routine, Formulardatei) bleiben außen vor, weil ihre Signatur von außen vorgegeben ist; Overrides nur mit ignoreOverrides = false und dann ohne Ko' +
    'rrektur. Die Korrektur ergänzt const in Rumpf und Deklaration und teilt Parametergruppen bei Bedarf. Verweise als Methodenzeiger in anderen Units sieht die Regel nicht; die meldet nach der Korrektur d' +
    'er Compiler.",',
    '      "options": [',
    '        {',
    '          "name": "minRecordSize",',
    '          "description": "Record-Parameter ab dieser Größe in Byte melden."',
    '        },',
    '        {',
    '          "name": "ignoreOverrides",',
    '          "description": "Overrides nicht melden; ihre Signatur gibt der Vorfahr vor."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "bool-compare",',
    '      "name": "Vergleich mit True oder False",',
    '      "description": "Ein Vergleich eines Boolean mit True oder False ist überflüssig; den Ausdruck oder not direkt verwenden."',
    '    },',
    '    {',
    '      "id": "redundant-assigned-free",',
    '      "name": "Assigned-Prüfung vor Free",',
    '      "description": "Free prüft selbst auf nil, eine Assigned-Prüfung vor Free oder FreeAndNil ist überflüssig."',
    '    },',
    '    {',
    '      "id": "raise-in-finally",',
    '      "name": "raise in einem finally-Block",',
    '      "description": "Eine im finally-Block ausgelöste Exception ersetzt die gerade laufende Exception, die dadurch verloren geht."',
    '    },',
    '    {',
    '      "id": "redundant-parens",',
    '      "name": "Überflüssige Klammern",',
    '      "description": "Klammern um eine ganze Bedingung oder einen einzelnen Bezeichner bringen nichts. Standardmäßig aus."',
    '    },',
    '    {',
    '      "id": "redundant-cast",',
    '      "name": "Überflüssige Typumwandlung",',
    '      "description": "TStringList(Liste) mit Liste: TStringList, X as TFoo mit X: TFoo oder Integer(Anzahl) mit Anzahl: Integer ändern nichts. Ebenso TObject(Obj).Free: Free ruft den virtuellen Destru' +
    'ktor und braucht keine Umwandlung (Option checkFree). Gemeldet wird nur, wenn der Typ der Quelle sicher bekannt und genau mit dem Namen des Ziels deklariert ist; Aliase (TFarbIndex = Integer), Konstan' +
    'ten, Routinen ohne Aufruf, überladene Routinen als Quelle, Argumente überladener Aufrufe (die Umwandlung kann die Überladung wählen), as mit Interfaces (QueryInterface) und in der Klassenkette neu dek' +
    'lariertes Free bleiben still. Sicherheit hoch. Korrektur: die Umwandlung entfernen.",',
    '      "options": [',
    '        {',
    '          "name": "checkFree",',
    '          "description": "Auch eine Klassenumwandlung melden, die nur vor Free steht (CastAndFree)."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "redundant-begin-end",',
    '      "name": "begin … end um eine einzelne Anweisung",',
    '      "description": "Ein begin … end-Block mit genau einer Anweisung kann entfallen. Standardmäßig aus."',
    '    },',
    '    {',
    '      "id": "with-statement",',
    '      "name": "with-Anweisung",',
    '      "description": "In einem with-Block ist unklar, zu welchem Objekt ein Bezeichner gehört, und ein neues Mitglied des with-Objekts ändert still die Bedeutung. Den Ausdruck ausschreiben oder eine l' +
    'okale Variable verwenden."',
    '    },',
    '    {',
    '      "id": "metric-method-length",',
    '      "name": "Methode zu lang",',
    '      "description": "Die Methode hat mehr Codezeilen als der Grenzwert (Vorgabe 60). Leerzeilen, Kommentare, Compiler-Direktiven und lokale Routinen zählen nicht mit. Die Methode in kleinere aufteile' +
    'n. Den Grenzwert setzt die Option max, z. B. \"rules\": {\"metric-method-length\": {\"max\": 80}}.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstens so viele Anweisungszeilen."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "metric-nesting-depth",',
    '      "name": "Zu tief verschachtelt",',
    '      "description": "Die Methode verschachtelt if, case, Schleifen und try tiefer als der Grenzwert (Vorgabe 4). else if bleibt auf der Ebene seines if. Mit Exit oder Continue früh verlassen oder inn' +
    'ere Teile in eigene Methoden auslagern. Den Grenzwert setzt die Option max.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchste erlaubte Schachtelungstiefe."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "metric-cyclomatic-complexity",',
    '      "name": "Zyklomatische Komplexität zu hoch",',
    '      "description": "Die zyklomatische Komplexität der Methode liegt über dem Grenzwert (Vorgabe 15). Sie beginnt bei 1 und steigt um 1 je if, while, repeat und for, je case-Zweig ohne else, je and/o' +
    'r in einer Bedingung und je except on; ein except ohne on zählt einmal. Viele Pfade brauchen viele Tests. Den Grenzwert setzt die Option max.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchste erlaubte zyklomatische Komplexität."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "metric-cognitive-complexity",',
    '      "name": "Kognitive Komplexität zu hoch",',
    '      "description": "Die kognitive Komplexität der Methode liegt über dem Grenzwert (Vorgabe 15). Nach SonarSource zählen if, case, Schleifen und except-Behandler 1 plus ihre Schachtelungsebene; else' +
    ', else if, goto und jede Folge gleicher logischer Operatoren zählen 1. Verschachtelter Code ist schwerer zu lesen als Code hintereinander. Den Grenzwert setzt die Option max.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchste erlaubte kognitive Komplexität."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "metric-parameter-count",',
    '      "name": "Zu viele Parameter",',
    '      "description": "Die Methode hat mehr Parameter als der Grenzwert (Vorgabe 6). Zusammengehörige Werte in einem Record oder einer Klasse bündeln. Den Grenzwert setzt die Option max.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstens so viele Parameter."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "metric-boolean-operands",',
    '      "name": "Bedingung mit zu vielen Operanden",',
    '      "description": "Eine Bedingung von if, while, until oder einem Bedingungsausdruck verknüpft mehr Operanden mit and, or und xor als der Grenzwert (Vorgabe 5); Klammern und not zählen nicht, ein V' +
    'ergleich oder Aufruf ist ein Operand. Der Befund steht auf der Bedingung. Schnellkorrektur „Bedingung in Funktion auslagern“ (#50) macht aus der ganzen Bedingung eine Funktion mit Ergebnis Boolean (Me' +
    'thode der Klasse bzw. Routine vor der umgebenden), die gelesenen lokalen Namen werden const-Parameter. Erscheint auch in der Metrik-Linse.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstens so viele Operanden in einer Bedingung."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "metric-local-count",',
    '      "name": "Zu viele lokale Variablen",',
    '      "description": "Die Routine deklariert mehr lokale Variablen als der Grenzwert (Vorgabe 12): Namen im var-Abschnitt, Inline-Variablen und for var. Lokale Routinen und anonyme Methoden zählen für' +
    ' sich. Viele lokale Variablen heißen meist, dass die Routine mehreres tut; Teile in eigene Methoden auslagern. Erscheint auch in der Metrik-Linse.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstens so viele lokale Variablen."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "metric-exit-points",',
    '      "name": "Zu viele Ausstiege",',
    '      "description": "Die Routine wird öfter mit Exit und raise verlassen als der Grenzwert (Vorgabe 4); Exit(Wert) und raise; im except zählen mit. Lokale Routinen und anonyme Methoden zählen für sic' +
    'h. Viele Ausstiege machen den Ablauf schwer lesbar; Wächter zusammenfassen oder Teile auslagern. Erscheint auch in der Metrik-Linse.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstens so viele Exit und raise."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "todo-comment",',
    '      "name": "Offener TODO-Kommentar",',
    '      "description": "Ein Kommentar beginnt mit einer Marke für offene Arbeit: // TODO, // FIXME oder das Format der IDE-To-Do-Liste { TODO 1 -oPerson -cKategorie : Text }. Der Hinweis zeigt Marke, Pr' +
    'iorität, Kategorie, Person und Text, damit offene Arbeit in der Problemliste erscheint. In der Vorgabe aus; in atlas.json einschalten, z. B. \"rules\": {\"todo-comment\": {\"severity\": \"hint\"}}. Er' +
    'ledigte Einträge ({ DONE … }) meldet die Regel nie. Die Option keywords legt die Marken fest (Vorgabe [\"TODO\", \"FIXME\"]); sie gilt auch für get_todos und --todos.",',
    '      "options": [',
    '        {',
    '          "name": "keywords",',
    '          "description": "Marken offener TODO-Einträge (nur Buchstaben)."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "debug-display-placeholder",',
    '      "name": "Wertdarstellung nennt unbekanntes Mitglied",',
    '      "description": "Eine Regel für die Wertdarstellung beim Debuggen über einem Typ (// atlas-debug: ''{Name}, {Ort}'', [AtlasDebugDisplay(''…'')], // atlas-debug-children: Name, Ort oder [AtlasDebugChi' +
    'ldren(''…'')]) nennt einen Platzhalter oder ein Unterelement, das weder Feld noch Eigenschaft noch Methode des Typs oder eines Vorfahren ist, oder die Vorlage ist ungültig (offene oder leere Klammer). I' +
    'm Debugger bliebe ein solcher Platzhalter leer ({?Name}). Vorfahren kommen aus der Unit und dem Index; ist ein Vorfahr unbekannt, schweigt die Regel für den Typ. Mitglieder von TObject (ClassName, ToS' +
    'tring, …) gelten immer als bekannt."',
    '    },',
    '    {',
    '      "id": "component-palette-icon",',
    '      "name": "Registrierte Komponente ohne Palettensymbol",',
    '      "description": "Jede an RegisterComponents übergebene Klasse braucht in einer per {$R} eingebundenen .dcr oder .res eine Bitmap mit dem Klassennamen in Großbuchstaben. Ab Delphi 11 werden zusätz' +
    'lich die Größen 16, 24 und 32 px (NAME16, NAME24, NAME32) erwartet. Ohne lesbare eingebundene Ressourcendatei schweigt die Regel."',
    '    },',
    '    {',
    '      "id": "unresolved-identifier",',
    '      "name": "Nicht deklarierter Bezeichner",',
    '      "description": "Ein Bezeichner in einer Anweisung ist weder in der Unit noch in den eingebundenen Units deklariert (wie Compilerfehler E2003). Geprüft beim Tippen, ohne Compiler; with-Blöcke, as' +
    'm und anonyme Methoden werden übersprungen. Alte object-Syntax: In New(P, Init) und Dispose(P, Done) ist das zweite Argument ein Konstruktor bzw. Destruktor des object-Typs hinter P; fehlt er dort, me' +
    'ldet die Regel wie E2601 bzw. E2602, Fail außerhalb eines Konstruktors wie E2078."',
    '    },',
    '    {',
    '      "id": "deprecated-symbol",',
    '      "name": "Veraltetes oder gebundenes Symbol",',
    '      "description": "Eine Routine, ein Typ, eine Konstante oder ein Mitglied mit deprecated, experimental, platform oder library wird verwendet (wie W1000, W1003, W1002, W1001), oder eine Unit, deren' +
    ' Kopf einen dieser Hinweise trägt, steht in uses (wie W1006, W1007, W1005, W1004); auch der veraltete Abschnitt automated einer Klasse zählt als veraltetes Symbol (wie W1000). Gemeldet wird nur, was s' +
    'icher aufgelöst ist. Der Editor streicht veraltete Namen durch; die Meldung nennt den Grund aus deprecated ''Grund''. Die Deklaration und der Kopf ihrer Implementierung werden nicht gemeldet. Ob eine Ar' +
    't gemeldet wird, folgt wie bei dcc dem Stand der Warnung: ab Werk sind alle acht an, dann gilt die Projektoption der .dproj (DCC_SYMBOL_PLATFORM = false usw.), dann die Schalter {$WARN SYMBOL_DEPRECAT' +
    'ED OFF|ON|ERROR|DEFAULT}, {$WARN UNIT_PLATFORM …} usw. und {$WARNINGS OFF} ab ihrer Stelle; ein Schalter in einem {$IF}-Zweig, der nicht sicher mit übersetzt wird, hält die Stelle still. Die Option ki' +
    'nds schränkt die Arten zusätzlich ein. Die .NET-Direktive {$UNSAFECODE ON|OFF} meldet die Regel wie ein plattformspezifisches Symbol (wie W1002), so wie dcc für Windows. Korrektur: durch den Namen aus' +
    ' dem Grund ersetzen (bei IncludeTrailingBackslash und ExcludeTrailingBackslash durch die plattformunabhängige Routine), wenn genau ein Name passt, an der Stelle sichtbar ist und dieselbe Art hat. Ohne' +
    ' Projektindex prüft die Regel nur die Symbole der Datei selbst.",',
    '      "options": [',
    '        {',
    '          "name": "kinds",',
    '          "description": "Gemeldete Arten: deprecated, experimental, platform, library (Standard alle vier; eine im Projekt oder in der Datei abgeschaltete Warnung bleibt ohnehin still)."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "implicit-package-import",',
    '      "name": "Implizit eingebundene Unit",',
    '      "description": "In einem Package (.dpk) verwendet eine Unit aus contains eine Unit, die weder in contains steht noch von einem Package aus requires geliefert wird. Der Compiler zieht sie implizi' +
    't hinein (W1033), was später zu doppelten Units führt, wenn ein anderes Package sie ebenfalls enthält. Die Schnellkorrektur nimmt die Unit in contains auf."',
    '    },',
    '    {',
    '      "id": "type-used-before-declaration",',
    '      "name": "Typ vor seiner Deklaration benutzt",',
    '      "description": "Eine Klasse, ein Interface, ein Record oder ein anderer Typ wird in einer Typdeklaration (Feld, Parameter, Ergebnis, Property, generisches Argument, class of) benutzt, ist aber e' +
    'rst weiter unten im selben Gültigkeitsbereich deklariert (wie Compilerfehler E2003). Vorfahren, Aliase und Zeigertypen werden nicht gemeldet, ebenso wenig class of auf eine Klasse weiter unten im selb' +
    'en type-Block (das übersetzt dcc) und ein Name, der weiter unten nur als Alias des gleichnamigen Typs einer anderen Unit steht (TX = UnitY.TX: davor gilt UnitY.TX aus uses). Schnellkorrekturen: Forwar' +
    'd-Deklaration am Anfang des type-Blocks ergänzen, type-Blöcke zusammenlegen (const-, var- und label-Abschnitte dazwischen wandern vor den ersten Block) oder einen Record vor seinen ersten Verwender ve' +
    'rschieben; ohne sichere Korrektur nennt die Meldung den Grund."',
    '    },',
    '    {',
    '      "id": "unneeded-forward-declaration",',
    '      "name": "Überflüssige Forward-Deklaration",',
    '      "description": "Eine Forward-Deklaration, deren Typ im selben type-Block vor der vollständigen Deklaration nicht benutzt wird. Schnellkorrektur: entfernen."',
    '    },',
    '    {',
    '      "id": "field-not-freed",',
    '      "name": "Feld erzeugt, aber nie freigegeben",',
    '      "description": "Ein Objektfeld, das der Konstruktor (oder eine von ihm aufgerufene private Methode) mit TKlasse.Create erzeugt, wird in der Klasse nirgends freigegeben (kein Free, FreeAndNil, De' +
    'stroy oder DisposeOf): ein Speicherleck. Ausgenommen sind Komponenten mit einem Owner ungleich nil, Interface- und Record-Felder sowie die Klassen aus der Option ignoreTypes; TObjectList- und TObjectD' +
    'ictionary-Felder sind normale Felder. Konfidenz mittel. Schnellkorrekturen: das Feld im Destruktor freigeben oder alle eigenen Objekte der Klasse freigeben; ein fehlender Destruktor wird mit override ' +
    'und inherited angelegt. Die Freigaben stehen vor inherited in umgekehrter Erzeugungsreihenfolge, als Free oder FreeAndNil (refactoring.freeFieldsStyle). Bis #918 hieß die Regel owned-field-not-freed; ' +
    'Einstellungen und Unterdrückungen mit dieser Kennung wirken weiter.",',
    '      "options": [',
    '        {',
    '          "name": "ignoreTypes",',
    '          "description": "Klassen, die anderswo freigegeben werden; generische Typen treffen ohne Typparameter."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "owned-field-free-unclear",',
    '      "name": "Unklar, ob ein erzeugtes Feld freigegeben werden muss",',
    '      "description": "Ein im Konstruktor erzeugtes, nicht freigegebenes Objektfeld wird auch zurückgegeben (Result := FFeld, Exit(FFeld)), an eine Property eines anderen Objekts oder an dessen Add…, I' +
    'nsert…, Register…, Attach…, Push oder Enqueue übergeben, ohne Create zugewiesen oder ist über eine Property (write FFeld) schreibbar. Ob die Klasse das Objekt noch besitzt, entscheidet der Entwickler;' +
    ' deshalb gibt es keine Schnellkorrektur. Still bleibt die Regel, wenn der Empfänger seine Elemente besitzt: ein Feld vom Typ TObjectList, TObjectStack, TObjectQueue oder TComponentList, das nicht mit ' +
    'False erzeugt wird, oder ein Feld, dessen Klasse (aus der Datei oder dem Index) eine solche Liste für den Elementtyp hält. Felder vom Typ TArray<T> sind dynamische Arrays und werden nie gemeldet."',
    '    },',
    '    {',
    '      "id": "operator-precedence",',
    '      "name": "Vorrang von not übersehen",',
    '      "description": "In Pascal bindet not stärker als in und Vergleiche: not X in Menge heißt (not X) in Menge, not A = B heißt (not A) = B, bei Ganzzahlen wird not bitweise. Die Regel meldet diese F' +
    'ormen, wenn der deklarierte Typ des Operanden zeigt, dass es nicht gemeint sein kann (kein Boolean). Schnellkorrektur: Klammern setzen, not (X in Menge)."',
    '    },',
    '    {',
    '      "id": "empty-statement",',
    '      "name": "Leere Anweisung nach then, do oder else",',
    '      "description": "Ein Semikolon direkt nach then, do oder else beendet die Anweisung: Die folgende Zeile läuft dann immer bzw. die Schleife dreht leer. Ein leerer Block begin … end nach then, do o' +
    'der else wird ebenfalls gemeldet, außer er enthält einen erklärenden Kommentar (Option allowCommented). Ein Semikolon direkt vor end, until, except oder finally ändert nichts und bleibt unbeanstandet.' +
    ' Schnellkorrektur: Semikolon entfernen.",',
    '      "options": [',
    '        {',
    '          "name": "allowCommented",',
    '          "description": "begin { absichtlich leer } end nicht melden."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "loop-off-by-one",',
    '      "name": "Schleife läuft einen Schritt zu weit",',
    '      "description": "for I := 0 to Liste.Count oder to Length(A) über nullbasierte Listen und Arrays greift im letzten Durchlauf hinter das Ende, wenn der Rumpf Liste[I] bzw. A[I] liest. Bei einsbasi' +
    'erten Strings umgekehrt: S[0] (Delphi meldet E2157) und for I := 0 to Length(S) greifen vor das erste Zeichen; {$ZEROBASEDSTRINGS ON} wird beachtet. Schnellkorrektur: - 1 ergänzen bzw. High(A) verwend' +
    'en, bei Strings Low(S) und High(S). Die Option countNames nennt die Namen, die eine Anzahl liefern.",',
    '      "options": [',
    '        {',
    '          "name": "countNames",',
    '          "description": "Namen, die eine Anzahl liefern (Property wie Count oder Funktion wie Length)."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "collection-modified-in-loop",',
    '      "name": "Liste in der eigenen Schleife verändert",',
    '      "description": "Delete, Remove, Add oder eine andere Methode aus der Option mutatingMethods wird auf der Liste aufgerufen, über die die Schleife gerade vorwärts per Index oder mit for … in läuft' +
    '. Vorwärts überspringt Delete das nächste Element und läuft über das Ende, Add wird nicht mehr durchlaufen und Insert liefert dasselbe Element zweimal; mit for … in wirft die RTL eine Exception. Ein B' +
    'reak oder Exit ohne Bedingung nach dem Aufruf im selben Block beendet die Schleife und bleibt still (ein Break in einer inneren Schleife zählt nicht), downto-Schleifen ebenso. Schnellkorrektur bei Ind' +
    'exschleifen: rückwärts mit downto; bei for … in die Elemente sammeln und die Liste nach der Schleife ändern.",',
    '      "options": [',
    '        {',
    '          "name": "mutatingMethods",',
    '          "description": "Methoden, die die Liste verändern."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "use-after-free",',
    '      "name": "Objekt nach Free weiter benutzt",',
    '      "description": "Nach X.Free, X.Destroy, X.DisposeOf, FreeAndNil(X) oder Dispose(X) wird X ohne neue Zuweisung wieder benutzt: Methode, Feld, Index oder X^, with X, nach Free auch Assigned(X) (im' +
    'mer True) oder ein zweites Free. Die Regel folgt dem Datenfluss der Routine; eine Zuweisung an X, die Übergabe von X an eine Routine, @X und nach FreeAndNil eine Abfrage auf nil beenden den Weg, Wege ' +
    'nur über eine mögliche Ausnahme bleiben aus. Konfidenz hoch, wenn Freigabe und Zugriff im selben Block nacheinander stehen, sonst mittel. Keine automatische Korrektur; die Aktion springt zur Freigabe.' +
    '"',
    '    },',
    '    {',
    '      "id": "deref-before-nil-check",',
    '      "name": "Erst benutzt, dann auf nil geprüft",',
    '      "description": "X wird dereferenziert (X.Feld, X.Methode, X^) und erst danach mit Assigned(X), X <> nil oder X = nil geprüft. Entweder ist die Prüfung überflüssig oder der Zugriff davor kann kna' +
    'llen. Gemeldet wird nur, wenn jeder Weg zur Prüfung durch den Zugriff führt und X vorher nicht geprüft wurde; eine neue Zuweisung, FreeAndNil(X), die Übergabe von X oder eines seiner Felder oder Eleme' +
    'nte (X.Feld, X[I]) an eine Routine und bei Feldern und globalen Variablen jeder Aufruf dazwischen beenden den Weg. Konfidenz mittel. Ist die Prüfung ein if ohne else direkt nach dem Zugriff im selben ' +
    'Block, zieht die Schnellkorrektur den Zugriff hinein."',
    '    },',
    '    {',
    '      "id": "field-free-without-nil",',
    '      "name": "Feld freigegeben, Verweis bleibt stehen",',
    '      "description": "FFeld.Free in einer Methode außerhalb des Destruktors, und ein Weg zum Ende der Methode setzt das Feld nicht neu. Ein späterer Zugriff oder ein zweites Free trifft freigegebenen ' +
    'Speicher. Neu setzt eine Zuweisung oder der Aufruf einer Methode derselben Klasse, die das Feld zuweist. Felder sind die der Klassendeklaration in der Unit. Ausgenommen sind Destruktoren, Methoden mit' +
    ' [TearDown] oder [TearDownFixture], Methoden, die nur aus diesen aufgerufen werden, und die Methoden aus der Option ignoreMethods. Konfidenz mittel. Schnellkorrektur: FreeAndNil(FFeld).",',
    '      "options": [',
    '        {',
    '          "name": "ignoreMethods",',
    '          "description": "Methoden, in denen Free ohne nil erlaubt ist."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "missing-inherited",',
    '      "name": "Konstruktor oder Destruktor ohne inherited",',
    '      "description": "Ein Konstruktor oder ein override von Destroy, AfterConstruction oder BeforeDestruction ruft inherited nicht auf, in jeder Klasse, deren Vorfahr nicht TObject ist. Konstruktoren ' +
    'werden nur gemeldet, wenn ein Vorfahr einen eigenen Konstruktor deklariert (Datei, Index oder bekannte RTL-/VCL-Klasse) und der Konstruktor keinen anderen Konstruktor derselben Klasse aufruft. Bei Kom' +
    'ponenten meldet Destroy nur component-missing-inherited. Konfidenz hoch. Schnellkorrektur: inherited; am Ende von Destroy und BeforeDestruction, am Anfang von Konstruktoren und AfterConstruction; ein ' +
    'Konstruktor mit Parametern ohne override bekommt inherited Create;.",',
    '      "options": [',
    '        {',
    '          "name": "methods",',
    '          "description": "Geprüfte Methoden; Create steht für alle Konstruktoren, deren Name mit Create beginnt."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "inherited-order",',
    '      "name": "inherited an der falschen Stelle",',
    '      "description": "Im Destruktor steht inherited (inherited; bzw. inherited Destroy) als Anweisung des Rumpfs vor einer späteren Anweisung, die ein Feld der Klasse selbst freigibt (F.Free, F.Dispos' +
    'eOf, FreeAndNil(F), auch mit Self.): Der Vorfahr kann noch virtuelle Methoden aufrufen, die das Feld brauchen. Klassen, in deren Kette eine Klasse mit Thread im Namen steht, bleiben still, denn TThrea' +
    'd.Destroy wartet auf Execute und gehört dort an den Anfang. Im Konstruktor greifen die Anweisungen vor inherited auf ein Feld oder eine Property eines Vorfahren zu (aufgelöst über Datei und Index; eig' +
    'ene Felder, Parameter und lokale Variablen zählen nicht), solange der Vorfahr noch nicht angelegt ist. missing-inherited meldet fehlendes inherited, diese Regel die Reihenfolge. Konfidenz mittel. Schn' +
    'ellkorrektur: inherited an das Ende des Destruktors bzw. den Anfang des Konstruktors verschieben; nicht, wenn die Argumente von inherited Create vorher gesetzte lokale Variablen verwenden."',
    '    },',
    '    {',
    '      "id": "inherited-wrong-method",',
    '      "name": "inherited ruft eine andere Methode",',
    '      "description": "In der überschriebenen Methode Speichern steht inherited Laden(…) statt inherited Speichern(…), meist nach Kopieren einer Methode. Es zählen nur Aufrufe (inherited Name als Anwei' +
    'sung oder mit Klammern); inherited Caption ohne Klammern kann eine Property sein. Still in Konstruktoren (inherited Create(nil), CreateNew), in Methoden ohne override und wenn die Methode auch sich se' +
    'lbst im Vorfahren aufruft (inherited; bzw. inherited Speichern), denn dann ist der andere Aufruf gewollt. Paare aus der Option allowed bleiben still. Konfidenz hoch. Schnellkorrektur: den Namen durch ' +
    'den eigenen ersetzen, wenn die Zahl der Argumente zu ihren Parametern passt.",',
    '      "options": [',
    '        {',
    '          "name": "allowed",',
    '          "description": "Erlaubte Paare \"Methode>geerbte Methode\", Muster mit * und ?, z. B. \"Speichern>Pruefen\"."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "getter-side-effect",',
    '      "name": "Getter verändert den Zustand",',
    '      "description": "Die read-Methode einer Property weist Feldern oder Properties des eigenen Objekts zu (FAbrufe, Self.FWert, auch geerbte Felder), ruft Inc/Dec/Include/Exclude darauf auf oder über' +
    'gibt ein neu angelegtes Objekt an eine Methode eines Felds (FListe.Add(TEintrag.Create)). Der Debugger wertet Getter beim Anzeigen aus und ändert so den Zustand. Lazy-Initialisierung ist erlaubt: Ein ' +
    'umschließendes if prüft etwas, das sein Zweig zuweist (if FListe = nil then FListe := …, if Result = nil then … FListe := Result, if not FGeladen then … FGeladen := True). Still bei lokalen Variablen ' +
    'mit dem Namen eines Felds, Result, Methoden ohne Property und anonymen Methoden. Eine Meldung je Getter und Feld. Konfidenz mittel. Keine Schnellkorrektur.",',
    '      "options": [',
    '        {',
    '          "name": "allowLazyInit",',
    '          "description": "Lazy-Initialisierung im Getter erlauben (if FListe = nil then FListe := …)."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "equals-without-gethashcode",',
    '      "name": "Equals ohne GetHashCode",',
    '      "description": "Eine Klasse überschreibt Equals, aber nicht GetHashCode (oder umgekehrt). In TDictionary und THashSet mit Standard-Comparer finden gleiche Objekte sich dann nicht. Still, wenn ei' +
    'n Vorfahr das Gegenstück überschreibt, wenn die Vorfahrenkette nicht vollständig bekannt ist und bei Equals ohne override. Gilt ebenso für Records der Datei mit class operator Equal, die als Schlüssel' +
    ' von TDictionary, TObjectDictionary, THashSet oder TMultiMap ohne Comparer dienen (Create ohne Argumente oder nur mit Konstanten wie Kapazität oder Besitz): Der Standard-Comparer vergleicht Records By' +
    'te für Byte, was nur bei Feldern vom Typ string, Variant, Gleitkomma, Interface oder TArray falsch ist; Records mit nur ordinalen Feldern bleiben still. Konfidenz hoch. Schnellkorrektur für Klassen: G' +
    'etHashCode hinter Equals deklarieren und hinter dem Rumpf von Equals mit THashBobJenkins über die eigenen Felder umsetzen, die Equals vergleicht (ohne Groß-/Kleinschreibung über LowerCase, wenn Equals' +
    ' SameText nutzt), System.Hash in uses ergänzen."',
    '    },',
    '    {',
    '      "id": "destroy-called-directly",',
    '      "name": "Destroy statt Free aufgerufen",',
    '      "description": "Obj.Destroy wird direkt als Anweisung aufgerufen. Ist Obj nil, knallt der Aufruf; Free prüft vorher auf nil und ist der übliche Weg, ein Objekt freizugeben. inherited Destroy und' +
    ' Aufrufe eines Destruktors mit Argumenten sind ausgenommen. Konfidenz hoch. Schnellkorrektur: aus Destroy wird Free."',
    '    },',
    '    {',
    '      "id": "managed-type-raw-memory",',
    '      "name": "FillChar, Move oder GetMem auf verwaltete Typen",',
    '      "description": "FillChar, ZeroMemory, FillMemory, Move, CopyMemory, GetMem oder FreeMem auf eine Variable, deren Typ Strings, Interfaces, dynamische Arrays oder Variants enthält (Records, statis' +
    'che Arrays und Aliasse werden in der Datei und im Index aufgelöst). Referenzzähler werden überschrieben oder übergangen: Lecks, doppelte Freigabe, Zugriffsverletzungen. Geprüft werden nur einfache Var' +
    'iablen (X, @X, P^); Array-Elemente wie S[1] und Typen, die sich nicht auflösen lassen, bleiben still. Konfidenz hoch. Schnellkorrekturen: aus FillChar(X, SizeOf(X), 0) wird X := Default(T), aus Move(A' +
    ', B, SizeOf(T)) wird B := A, aus GetMem(P, SizeOf(T)) wird New(P) und aus FreeMem(P) wird Dispose(P); sonst helfen Initialize und Finalize."',
    '    },',
    '    {',
    '      "id": "threadvar-managed",',
    '      "name": "threadvar mit verwaltetem Typ",',
    '      "description": "Delphi finalisiert threadvar-Variablen nicht. Ein String, Interface, dynamisches Array oder Variant in einer threadvar (auch in einem Record oder statischen Array) leckt in jedem' +
    ' Thread, der endet. Typen werden in der Datei und im Index aufgelöst. Konfidenz hoch. Keine Schnellkorrektur: den Wert am Thread-Ende freigeben (etwa in TThread.Execute auf '''' bzw. nil setzen) oder st' +
    'attdessen einen Zeiger bzw. Puffer fester Größe ablegen."',
    '    },',
    '    {',
    '      "id": "pchar-of-temporary",',
    '      "name": "PChar auf einen temporären String",',
    '      "description": "PChar (PWideChar, PAnsiChar) eines temporären Strings, etwa einer Verkettung mit einem String (S + ''.bak'') oder eines Funktionsergebnisses (IntToStr(N)), wird in einer Variablen,' +
    ' einem Feld oder Result gemerkt oder an PostMessage, PostThreadMessage, SendNotifyMessage oder SendMessageCallback übergeben (auch hinter LPARAM(…)). Der temporäre String wird nach der Anweisung freig' +
    'egeben, der Zeiger zeigt dann ins Leere. Die Übergabe an einen gewöhnlichen Aufruf wie CopyFile ist in Ordnung. Konfidenz hoch. Schnellkorrektur für lokale Variablen: das Zwischenergebnis in eine Inli' +
    'ne-String-Variable legen."',
    '    },',
    '    {',
    '      "id": "out-param-read",',
    '      "name": "out-Parameter gelesen, bevor er gesetzt ist",',
    '      "description": "Ein out-Parameter wird auf einem Weg durch den Kontrollfluss gelesen, bevor die Routine ihn setzt. Bei verwalteten Typen (string, Interfaces, dynamische Arrays, Variant) hat der ' +
    'Aufrufer ihn schon geleert, der alte Wert ist weg; bei anderen Typen ist der Wert undefiniert. Gemeint war meist var. Verwendungen, denen der Kontrollflussgraph nicht folgen kann (Übergabe an eine Rou' +
    'tine, Setzen eines Felds, @Param), bleiben still. Konfidenz hoch. Schnellkorrektur: aus out wird var in Implementierung und Deklaration."',
    '    },',
    '    {',
    '      "id": "noreturn-returns",',
    '      "name": "noreturn-Routine kann normal zurückkehren",',
    '      "description": "Eine mit noreturn markierte Routine (ab Delphi 13) darf nur über raise, Abort, Halt, RunError oder den Aufruf einer anderen noreturn-Routine enden. Erreicht ein Weg das Ende des ' +
    'Rumpfs oder ein Exit, kehrt sie normal zurück; der Compiler hat den Code nach dem Aufruf weggelassen, das Verhalten ist undefiniert. Die Direktive zählt an der Implementierung und an der Deklaration (' +
    'interface, Klasse). Aufrufe, deren Ziel weder die Datei, die Standardroutinen noch der Symbolindex kennt, könnten selbst noreturn sein und beenden den Weg ebenfalls; gemeldet werden also nur Wege aus ' +
    'bekannten Anweisungen. Unvollständiger Kontrollfluss (asm, Syntaxfehler) bleibt still. Exit wird an der Anweisung gemeldet, das Ende des Rumpfs am Routinennamen. Konfidenz hoch. Keine Schnellkorrektur' +
    '."',
    '    },',
    '    {',
    '      "id": "stringlist-unsorted",',
    '      "name": "Find oder Duplicates auf einer unsortierten TStringList",',
    '      "description": "Find auf einer TStringList oder THashedStringList, die in der Unit erzeugt, aber nie sortiert wird: Find sucht binär und liefert auf einer unsortierten Liste falsche Ergebnisse. ' +
    'Ebenso wirkt Duplicates := dupIgnore oder dupError nur bei sortierten Listen. Als sortiert gelten Sorted := True (oder jeder Wert außer False), Sort, CustomSort, Create(Duplicates, True, ...) und with' +
    ' Liste do. Eine Liste, die an eine Routine übergeben oder einer anderen Variablen zugewiesen wird, bleibt still. Lokale Variablen gelten je Routine, Felder in der ganzen Unit. Konfidenz mittel. Schnel' +
    'lkorrekturen: Sorted := True nach dem Erzeugen (nicht, wenn die Liste Insert, Move oder Exchange benutzt, die bei sortierten Listen eine Ausnahme auslösen) und bei if Liste.Find(S, I) then die Form I ' +
    ':= Liste.IndexOf(S) mit if I >= 0."',
    '    },',
    '    {',
    '      "id": "writeln-in-gui-app",',
    '      "name": "Writeln in einem Programm ohne Konsole",',
    '      "description": "Write, Writeln, Read oder Readln auf die Standardein- oder -ausgabe in einem Programm ohne Konsole: zur Laufzeit löst Writeln EInOutError aus (E/A-Fehler 105), Readln E/A-Fehler ' +
    '104. Die Anwendungsart kommt aus DCC_ConsoleTarget der .dproj und {$APPTYPE CONSOLE} der .dpr (auch in {$IFDEF}); Units werden nur geprüft, wenn sie zum geladenen Projekt gehören, eine .dpr ohne Proje' +
    'kt für sich. Bibliotheken und Packages bleiben still. Ausgenommen sind Aufrufe mit einer Textdatei als erstem Argument, Aufrufe unter if IsConsole, gleichnamige Routinen der Unit und Read/Write in Met' +
    'hoden (TStream.Read). Konfidenz hoch. Schnellkorrektur für Write und Writeln: Ersatz durch OutputDebugString(PChar(...)) und Winapi.Windows im uses; Zahlen und Boolean über IntToStr, FloatToStr und Bo' +
    'olToStr. Die Option replacement setzt ein anderes Ziel, z. B. Log.Info oder Logger.Log(TLogLevel.Info, %s). Keine Korrektur bei Breitenangaben (X:5) oder Argumenten unbekannten Typs.",',
    '      "options": [',
    '        {',
    '          "name": "replacement",',
    '          "description": "Ersatz für Write und Writeln in der Schnellkorrektur; %s steht für den Text."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "exception-in-destructor",',
    '      "name": "raise im Destruktor",',
    '      "description": "raise in einem Destruktor (auch class destructor), das kein except im Destruktor abfängt. Die Ausnahme bricht die Freigabe ab: inherited Destroy läuft nicht mehr, das Objekt blei' +
    'bt halb freigegeben, und in einem finally des Aufrufers überdeckt sie die ursprüngliche Ausnahme. Ein raise im try-Teil eines try..except ist abgefangen; raise im except- oder finally-Teil, auch ein e' +
    'rneutes raise;, wird gemeldet. Eingebettete Routinen und anonyme Methoden sind ausgenommen. Aufrufen, die ihrerseits auslösen, folgt die Regel nicht. Konfidenz hoch. Keine Schnellkorrektur: den Zustan' +
    'd protokollieren oder ohne Ausnahme freigeben."',
    '    },',
    '    {',
    '      "id": "duplicate-condition",',
    '      "name": "Doppelte Bedingung oder gleiche Zweige",',
    '      "description": "Dieselbe Bedingung zweimal in einer if … else if-Kette (der spätere Zweig wird nie erreicht), gleiche then- und else-Zweige, derselbe Operand zweimal in einer and-, or- oder xor-' +
    'Kette und Vergleiche eines Ausdrucks mit sich selbst (X = X, X < X). Meist ein Kopierfehler. Verglichen werden die Token ohne Leerraum, Kommentare und Groß-/Kleinschreibung. Ketten mit Aufrufen, die Z' +
    'ustand ändern können (alles außer SameText, Length, Assigned, Pos und ähnlichen reinen Funktionen, dazu Read, Next, Pop, Random …), bleiben still, ebenso Gleitkomma-Vergleiche mit sich selbst (NaN-Prü' +
    'fung X <> X) und Vergleiche über Klassenmitglieder wie TFoo.Shared = TFoo.Shared. Konfidenz hoch. Keine Schnellkorrektur; die Aktion springt zum ersten Vorkommen."',
    '    },',
    '    {',
    '      "id": "case-missing-enum-value",',
    '      "name": "case über Aufzählung ohne alle Werte",',
    '      "description": "Ein case über einen Aufzählungstyp ohne else deckt nicht alle Werte ab; ein später ergänzter Wert fällt still durch. Die Meldung nennt die fehlenden Werte. Den Typ des Selektors ' +
    '(Variable, Parameter, Feld oder Kette A.B) liefert die Namensauflösung, die Werte der Index bzw. die Unit selbst; Aliase werden verfolgt. Bereiche (bsNeu..bsBezahlt) und Listen zählen als vorhanden. S' +
    'elektoren mit Aufrufen, Ganzzahlen und unbekannte Typen bleiben still. Mit der Option requireElse wird auch ein case mit else gemeldet. Konfidenz hoch. Schnellkorrektur „Fehlende Werte ergänzen (n)“ e' +
    'rgänzt leere Zweige in Deklarationsreihenfolge vor else bzw. end, mit Typpräfix, wenn die Marken einen tragen ({$SCOPEDENUMS ON}).",',
    '      "options": [',
    '        {',
    '          "name": "requireElse",',
    '          "description": "Auch case-Anweisungen mit else melden, wenn Werte fehlen."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "pair-without-finally",',
    '      "name": "Paarige Aufrufe ohne try/finally",',
    '      "description": "Verallgemeinert lock-without-finally (dessen Sperrpaare dort bleiben) auf andere Paare: DisableControls/EnableControls, BeginUpdate/EndUpdate, FindFirst/FindClose (auch in if Fin' +
    'dFirst(...) = 0 then begin ... end), Reset, Rewrite oder Append/CloseFile, GetMem oder AllocMem/FreeMem und Screen.Cursor := ... mit einem späteren Screen.Cursor := .... Gemeldet wird, wenn das Schlie' +
    'ßen später ungeschützt in derselben Anweisungsliste steht und mindestens eine Anweisung dazwischen liegt; eine Exception dort lässt den Zustand hängen. Beide Aufrufe müssen denselben Empfänger bzw. da' +
    'sselbe Argument haben. Überlappende Paare meldet die Regel zusammen. Konfidenz hoch. Schnellkorrektur: die Anweisungen dazwischen in try/finally mit den schließenden Aufrufen einschließen, wenn diese ' +
    'direkt aufeinander folgen. Die Option pairs ergänzt eigene Paare.",',
    '      "options": [',
    '        {',
    '          "name": "pairs",',
    '          "description": "Weitere Paare als [{\"open\": \"Einfrieren\", \"close\": \"Auftauen\"}], wahlweise mit openArg/closeArg."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "processmessages-in-loop",',
    '      "name": "Application.ProcessMessages in Schleifen",',
    '      "description": "Application.ProcessMessages in einer for-, while- oder repeat-Schleife oder direkt in einem Ereignis-Handler (Methode mit Parameter Sender) öffnet die Tür für Wiedereintritt: Der' +
    ' Benutzer klickt erneut, schließt das Formular oder startet den Vorgang doppelt. Aufrufe in anonymen Methoden überlässt die Regel thread-vcl-access; ProcessMessages anderer Objekte zählt nicht. Konfid' +
    'enz mittel, keine Schnellkorrektur: die Arbeit in einen Thread oder TTask auslagern oder den Auslöser bis zum Ende sperren. Die Option allowIn nennt Methoden, in denen es erlaubt ist.",',
    '      "options": [',
    '        {',
    '          "name": "allowIn",',
    '          "description": "Methoden, in denen ProcessMessages erlaubt ist, als Name oder Klasse.Name."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "unchecked-conversion",',
    '      "name": "Umwandlung einer Benutzereingabe ohne Prüfung",',
    '      "description": "StrToInt, StrToInt64, StrToFloat, StrToDate, StrToDateTime oder StrToCurr direkt auf einer Benutzereingabe (Edit.Text, Grid.Cells[...], Memo.Lines[...], auch in Trim) außerhalb d' +
    'es try-Teils eines try/except. Eine Fehleingabe löst EConvertError mit englischer Meldung aus. try/finally gilt nicht als Schutz. Konfidenz mittel. Schnellkorrektur für X := StrToInt(Edit.Text); als e' +
    'igene Anweisung, wenn X eine Variable oder ein Feld des passenden Typs ist: if not TryStrToInt(Edit.Text, X) then raise EConvertError.Create(''X ist keine Zahl''). format-without-settings meldet zusätzl' +
    'ich landesabhängige Umwandlungen ohne TFormatSettings. Die Optionen functions und sources wählen die geprüften Umwandlungen und die Eigenschaften, die als Eingabe gelten.",',
    '      "options": [',
    '        {',
    '          "name": "functions",',
    '          "description": "Geprüfte Umwandlungen."',
    '        },',
    '        {',
    '          "name": "sources",',
    '          "description": "Eigenschaften, die als Benutzereingabe gelten."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "dictionary-get-without-check",',
    '      "name": "Dictionary-Zugriff ohne Prüfung des Schlüssels",',
    '      "description": "Dict[Key] bzw. Dict.Items[Key] wird auf einem TDictionary oder TObjectDictionary (auch über einen Typalias der Datei) gelesen, obwohl weder ContainsKey noch TryGetValue denselben' +
    ' Schlüssel vorher in der Routine geprüft hat. Still bleibt die Regel, wenn die Routine das Dictionary vorher selbst füllt (Add, AddOrSetValue, TryAdd, Dict[K] := ...) oder der Schlüssel aus Keys bzw. ' +
    'den Paaren stammt (for K in Dict.Keys, Namen := Dict.Keys.ToArray, for Pair in Dict mit K := Pair.Key). Fehlt der Schlüssel, folgt EListError. Konfidenz mittel. Schnellkorrektur für X := Dict[Key]; al' +
    's eigene Anweisung, wenn X eine Variable vom Wertetyp ist: if not Dict.TryGetValue(Key, X) then X := 0 (bzw. '''', False, Default(T))."',
    '    },',
    '    {',
    '      "id": "shadowed-name",',
    '      "name": "Lokaler Name verdeckt Feld oder Property",',
    '      "description": "Ein Parameter, eine lokale oder Inline-Variable heißt wie ein Feld oder eine Property der Klasse (auch geerbt und dort sichtbar, aufgelöst über die Datei und den Symbolindex) ode' +
    'r wie eine globale Variable der Unit, die vor der Routine deklariert ist. In Formularmethoden besonders tückisch: Caption, Name, Tag, Left. Steht die VCL nicht im Index, kennt die Regel die Mitglieder' +
    ' von TComponent und TControl, wenn die Vorfahrenkette an einer VCL-Grundklasse endet. Mitglieder, die aus RTL, VCL oder einer anderen Bibliothek geerbt sind (Unit aus dem Bibliothekspfad), meldet die ' +
    'Regel nur, wo sie gemeint sein könnten: eine lokale Variable, die nur zugewiesen oder nur gelesen wird, ein Werteparameter, dem etwas zugewiesen wird. Hilfsvariablen wie Left, Text oder Name, die gele' +
    'sen und geschrieben werden, bleiben still; die Option frameworkMembers meldet sie wie früher. Parameter von Ereignis-Handlern (mit Sender) und von Methoden mit override oder message bleiben außen vor,' +
    ' weil der Ereignistyp, der Vorfahr bzw. die Botschaft die Signatur vorgibt. Konfidenz hoch. Schnellkorrektur: in der Routine in AName (Parameter, auch in der Deklaration) bzw. LName (lokale Variable) ' +
    'umbenennen; setzt die Projektdatei .atlas Präfixe (naming), gelten diese, z. B. mName. Die Option ignore nennt Namensmuster, die nie gemeldet werden (Vorgabe Sender, Value).",',
    '      "options": [',
    '        {',
    '          "name": "ignore",',
    '          "description": "Namensmuster (* und ?), die nie gemeldet werden."',
    '        },',
    '        {',
    '          "name": "frameworkMembers",',
    '          "description": "Jeden lokalen Namen melden, der ein aus RTL, VCL oder einer Bibliothek geerbtes Mitglied verdeckt, nicht nur verdächtige."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "naming-prefix",',
    '      "name": "Name ohne das Präfix seiner Art",',
    '      "description": "Einer lokalen Variable (auch Inline und for var), einem Feld (auch class var), einem Parameter oder einer Konstante (const, auch lokal, in Klassen und Inline; nicht resourcestrin' +
    'g) fehlt das Präfix ihrer Art. Standard: lokal m, Feld F, Parameter A, Konstante c; hinter einem Präfix, das auf einen Buchstaben endet, folgt ein Großbuchstabe oder eine Ziffer (mIndex, nicht menu). ' +
    'Globale Variablen prüft die Regel nicht. Je Art kommt das Präfix aus der Option in atlas.json, sonst aus der Projektdatei .atlas (naming, auch constant), sonst der Standard; ein leerer Wert schaltet d' +
    'ie Art ab. Standardmäßig aus: Die Regel läuft nur, wenn atlas.json sie einschaltet. Ausnahmen: Schleifenzähler aus einem Buchstaben, Sender, Self und Result, Namen nach ignore, öffentliche Felder (pub' +
    'lic, published und Felder eines Records vor seinem ersten Sichtbarkeitsabschnitt: Das F gilt nur für Felder hinter Properties, nicht für TPoint.X), Felder vor dem ersten Sichtbarkeitsabschnitt eines F' +
    'ormulars, Frames oder Datenmoduls (Komponenten), Parameter von Methoden mit override oder message, von published-Methoden, von Ereignis-Handlern (ein Parameter heißt Sender) und von Methoden, die eine' +
    ' Interface-Methode erfüllen (in der Datei oder im Symbolindex; unbekanntes Interface: still). Parameter werden nur an der Deklaration gemeldet. Schnellkorrektur: in den erwarteten Namen umbenennen, in' +
    ' der Routine bzw. im Block ab einer Inline-Deklaration, bei Parametern auch in Deklaration und Implementierung, bei privaten Feldern und Klassenkonstanten in der Klasse und ihren Methoden (auch Self.N' +
    'ame und TTyp.Name), bei Konstanten der implementation in der ganzen Unit. Keine Korrektur, wenn der neue Name dort schon vorkommt, wo umbenannt wird (Routine samt Parameterliste, bei Feldern die Klass' +
    'e und ihre Methoden, bei Konstanten der implementation die Datei), der Bereich with enthält, eine verschachtelte Routine den Namen neu deklariert oder der Name außerhalb der Datei sichtbar ist. Läuft ' +
    'die Regel, bilden andere Korrekturen und Refactorings neue Namen mit diesen Präfixen (Konstante einführen → cNewConstant, Variable einführen und with auflösen → mValue, Parameter von „Methode anlegen“' +
    ' → APreis), damit die Regel sie nicht gleich wieder meldet.",',
    '      "options": [',
    '        {',
    '          "name": "local",',
    '          "description": "Präfix lokaler Variablen; leer = nicht prüfen."',
    '        },',
    '        {',
    '          "name": "field",',
    '          "description": "Präfix von Feldern; leer = nicht prüfen."',
    '        },',
    '        {',
    '          "name": "parameter",',
    '          "description": "Präfix von Parametern; leer = nicht prüfen."',
    '        },',
    '        {',
    '          "name": "constant",',
    '          "description": "Präfix von Konstanten; leer = nicht prüfen."',
    '        },',
    '        {',
    '          "name": "ignore",',
    '          "description": "Namensmuster (* und ?), die nie gemeldet werden, z. B. Felder von API-Records."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "boolean-assign-if",',
    '      "name": "if, das nur True oder False zuweist",',
    '      "description": "if B then X := True else X := False (auch mit begin/end und vertauschten Werten), if B then Exit(True) else Exit(False) sowie if B then Exit(True); gefolgt von Exit(False); lasse' +
    'n sich direkt schreiben. Ergänzt bool-compare. Konfidenz hoch. Schnellkorrektur: X := B, X := not B bzw. Exit(B); Verneinungen werden vereinfacht (aus not B wird B), zusammengesetzte Bedingungen einge' +
    'klammert. Ohne Korrektur, wenn Kommentare im if stehen."',
    '    },',
    '    {',
    '      "id": "case-insensitive-compare",',
    '      "name": "Vergleich über UpperCase oder LowerCase",',
    '      "description": "UpperCase(A) = UpperCase(B), LowerCase(A) <> ''x'', AnsiUpperCase(...) oder A.ToUpper = B.ToUpper erzeugt zwei Strings für einen Vergleich. SameText (AnsiSameText bei den Ansi-Funk' +
    'tionen und den Unicode-String-Helfern) ist kürzer und schneller. Ein Literal zählt nur, wenn die Umwandlung es nicht ändert; UpperCase(A) = LowerCase(B) und UpperCase(A) = ''ja'' bleiben unberührt, weil' +
    ' das andere Fehler sind. Ersetzt nicht die String-Helper-Modernisierung aus #71. Konfidenz hoch. Schnellkorrektur: SameText(A, B) bzw. not SameText(A, B)."',
    '    },',
    '    {',
    '      "id": "magic-number",',
    '      "name": "Zahl ohne Namen im Code",',
    '      "description": "Zahlenliterale (dezimal, $hex, Gleitkomma, mit Vorzeichen) in Anweisungen, außerhalb von const-Abschnitten, Typen, Array-Grenzen und Teilbereichen. Erlaubte Werte sind einstellba' +
    'r; DFM-Koordinaten und Tests lassen sich über exclude ausnehmen. Standard aus und niedrige Konfidenz: Treffer erscheinen, wenn die Regel eingeschaltet und minConfidence low ist. Schnellkorrektur: Kons' +
    'tante einführen (#50) im const-Abschnitt der Routine.",',
    '      "options": [',
    '        {',
    '          "name": "allowed",',
    '          "description": "Zahlen, die nie gemeldet werden."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "line-length",',
    '      "name": "Zeile zu lang",',
    '      "description": "Zeilen über der Grenze max (Vorgabe 120 Zeichen, passend zu den Linealen aus #710). Tabs zählen bis zur nächsten Tabstelle nach format.indentSize. Zeilen, die nur wegen eines Str' +
    'ings oder, mit ignoreComments, eines Kommentars zu lang sind, werden nicht gemeldet. Zeilen über 1023 Zeichen meldet die Regel unabhängig von max immer als Warnung, weil der Compiler dort je nach Delp' +
    'hi-Version abbricht; Zeilen über 4095 Zeichen als Fehler, weil auch Delphi 13 dort abbricht (F2069). Standard aus. Schnellkorrektur: Zeile umbrechen hinter Kommas bzw. vor zweistelligen Operatoren, we' +
    'nn die Stücke danach passen.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstlänge einer Zeile in Zeichen."',
    '        },',
    '        {',
    '          "name": "ignoreStrings",',
    '          "description": "Zeilen, die nur wegen eines Strings zu lang sind, nicht melden."',
    '        },',
    '        {',
    '          "name": "ignoreComments",',
    '          "description": "Zeilen, die nur wegen eines Kommentars zu lang sind, nicht melden."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "metric-class-size",',
    '      "name": "Klasse mit zu vielen Membern",',
    '      "description": "Die Klasse hat mehr Member als der Grenzwert (Vorgabe 40): Feldnamen, Methoden, Properties mit eigenem Typ und class var. Properties, die nur die Sichtbarkeit anheben (property A' +
    'lign;), und geschachtelte Typen zählen nicht; eine geschachtelte Klasse wird für sich gemessen. Erscheint auch in der Metrik-Linse über der Klasse. Die Klasse aufteilen oder Teile in Hilfsklassen ausl' +
    'agern; „Klasse in eigene Unit verschieben“ (#103) hilft, wenn auch die Unit voll ist.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstzahl der Member je Klasse."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "metric-unit-length",',
    '      "name": "Unit zu lang",',
    '      "description": "Die Unit hat mehr Zeilen als der Grenzwert (Vorgabe 2000), gezählt bis zum abschließenden end. Gemessen werden nur Units, keine Programme oder Packages. Erscheint auch in der Met' +
    'rik-Linse über dem Unit-Namen. Klassen mit „Klasse in eigene Unit verschieben“ (#103) auslagern.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstzahl der Zeilen je Unit."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "metric-uses-count",',
    '      "name": "Zu viele Units im uses",',
    '      "description": "Die Unit bindet mehr Units ein als der Grenzwert (Vorgabe 30), interface und implementation zusammen. Der Befund steht auf dem ersten uses. Programme und Bibliotheken werden nich' +
    't geprüft, weil ihr uses die Units des Projekts aufzählt. Erscheint auch in der Metrik-Linse über uses. Viele Abhängigkeiten heißen meist, dass die Unit zu viel tut; „Klasse in eigene Unit verschieben' +
    '“ (#103) teilt sie.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstzahl der Units in allen uses-Klauseln."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "metric-inheritance-depth",',
    '      "name": "Zu tiefe Vererbung",',
    '      "description": "Die Klasse hat mehr eigene Vorfahren als der Grenzwert (Vorgabe 5). Vorfahren aus RTL, VCL, FMX und anderen Bibliotheken zählen nicht (am Unit-Namen oder weil der Index sie aus d' +
    'em Bibliothekspfad nachgeladen hat), TObject ebenso. Vorfahren werden in der Datei und im Symbolindex gesucht. Bricht die Kette an einem unbekannten Vorfahren ab, bevor sie eine Bibliothek erreicht, i' +
    'st der Wert eine Untergrenze und die Meldung sagt „mindestens“; gemeldet wird nur, wenn schon sie über der Grenze liegt. Units einer Bibliothek selbst werden nicht geprüft. Der Befund steht auf dem Kl' +
    'assennamen; die Metrik-Linse zeigt die Tiefe neben den Membern.",',
    '      "options": [',
    '        {',
    '          "name": "max",',
    '          "description": "Höchstens so viele eigene Vorfahren."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "public-field",',
    '      "name": "Öffentliches Feld",',
    '      "description": "Felder im public- oder published-Abschnitt einer Klasse. Der Abschnitt ohne Sichtbarkeitswort zählt nur bei Klassen ohne Vorfahren oder mit TObject, weil der Formulardesigner dor' +
    't seine Felder anlegt. Records sind ausgenommen, außer mit includeRecords; class var wird nicht gemeldet. Standard aus. Schnellkorrektur: Feld kapseln legt das Feld als FName in einen private-Abschnit' +
    't am Ende der Klasse und ergänzt im alten Abschnitt property Name read FName write FName; Zugriffe von außen bleiben gültig.",',
    '      "options": [',
    '        {',
    '          "name": "includeRecords",',
    '          "description": "Auch Felder von Records melden."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "legacy-tlist",',
    '      "name": "Ungenerische Liste mit Cast",',
    '      "description": "Eine ungenerische TList (System.Classes) oder TObjectList (System.Contnrs), deren Elemente mit Cast gelesen werden: T(Liste[I]), T(Liste.Items[I]), T(Liste.First), Liste[I] as T ' +
    'usw. TList<T> und TObjectList<T> aus System.Generics.Collections prüfen den Typ beim Übersetzen und brauchen keinen Cast. Die Regel meldet je Liste einmal, an ihrer Deklaration, wenn sie in der Datei ' +
    'steht, sonst am ersten Cast; bei mehreren Zieltypen nennt sie alle. Nur wenn die Namensauflösung Listentyp und Zieltyp sicher findet; Casts auf Pointer zählen nicht. Standard aus; für Code, der noch m' +
    'it alten Delphi-Versionen übersetzen muss, über exclude abschaltbar. Schnellkorrektur (#1105): wandelt die Liste in einem Schritt in TList<T> bzw. TObjectList<T> um: Deklaration, jedes Create (Argumen' +
    'te bleiben), jeden Cast und System.Generics.Collections im uses; Contnrs entfällt, wenn nichts anderes es braucht. Nur wenn alle Lesezugriffe denselben Cast haben, kein Mitglied ohne generisches Gegen' +
    'stück vorkommt (Sort mit TListSortCompare, Assign mit TListAssignOp, List), keine Pointer- oder Integer-Werte in der Liste stehen, Add, Extract, Remove und IndexOf T bekommen und die Liste nicht weite' +
    'rgegeben wird. Ist die Liste außerhalb der Unit sichtbar, schreibt die Korrektur die anderen Units der Projektgruppe mit um oder entfällt; solche Korrekturen wendet „Alle korrigieren“ (source.fixAll) ' +
    'nie an. Sonst nennt der Befund-Hover den Grund. Stapel und Warteschlangen: legacy-stack-queue."',
    '    },',
    '    {',
    '      "id": "legacy-stack-queue",',
    '      "name": "Ungenerischer Stapel oder ungenerische Warteschlange mit Cast",',
    '      "description": "Ein ungenerischer TStack, TQueue, TObjectStack oder TObjectQueue (System.Contnrs), dessen Elemente mit Cast gelesen werden: T(Stapel.Pop), T(Stapel.Peek), Schlange.Pop as T usw. ' +
    'TStack<T>, TQueue<T>, TObjectStack<T> und TObjectQueue<T> aus System.Generics.Collections prüfen den Typ beim Übersetzen und brauchen keinen Cast. Wie legacy-tlist meldet die Regel je Stapel bzw. Wart' +
    'eschlange einmal, an der Deklaration, wenn sie in der Datei steht, sonst am ersten Cast; bei mehreren Zieltypen nennt sie alle. Nur wenn die Namensauflösung Typ und Zieltyp sicher findet; Casts auf Po' +
    'inter zählen nicht. Standard aus; für Code, der noch mit alten Delphi-Versionen übersetzen muss, über exclude abschaltbar. Schnellkorrektur: wandelt in einem Schritt um wie legacy-tlist; bei Warteschl' +
    'angen wird Push zu Enqueue und Pop zu Dequeue. TObjectStack<T> und TObjectQueue<T> besitzen ihre Objekte, die Contnrs-Klassen nicht: Die Korrektur erzeugt sie deshalb mit Create(False) und liest mit E' +
    'xtract, weil Pop und Dequeue dort Prozeduren sind, die das Objekt freigeben. Ohne Create in der Unit, mit verschiedenen Casts oder mit Mitgliedern ohne generisches Gegenstück (AtLeast) gibt es keine K' +
    'orrektur; der Befund-Hover nennt den Grund."',
    '    },',
    '    {',
    '      "id": "global-variable",',
    '      "name": "Globale Variable im interface",',
    '      "description": "var oder threadvar im interface-Teil einer Unit: Jede Unit, die sie einbindet, kann den Wert lesen und ändern. Die Formularvariable des Designers (frmHaupt: TfrmHaupt, bei Nachfa' +
    'hren von TForm, TFrame, TDataModule oder jeder Klasse einer Unit mit Formulardatei) ist ausgenommen, außer mit includeFormVariables. Standard aus. Die Variable in den implementation-Teil verschieben u' +
    'nd eine Funktion oder Property anbieten.",',
    '      "options": [',
    '        {',
    '          "name": "includeFormVariables",',
    '          "description": "Auch die Formularvariablen des Designers melden."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "commented-out-code",',
    '      "name": "Auskommentierter Code",',
    '      "description": "Mindestens minLines aufeinanderfolgende Kommentarzeilen (// je Zeile oder ein mehrzeiliger { }-Kommentar), die sich als Anweisungen, Deklarationen oder Klassenmitglieder parsen l' +
    'assen. Prosa am Anfang und Ende des Blocks bleibt außen vor, mindestens die Hälfte der Zeilen muss nach Code aussehen (;, :=, begin, end, then, do). XMLDoc (///) und Kommentare vor dem ersten Token (L' +
    'izenzköpfe) meldet die Regel nie. Sicherheit mittel. Die Versionsverwaltung bewahrt den alten Code auf; die Korrektur entfernt die Zeilen.",',
    '      "options": [',
    '        {',
    '          "name": "minLines",',
    '          "description": "Mindestzahl aufeinanderfolgender auskommentierter Codezeilen."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "default-parameter",',
    '      "name": "Standardparameter statt Überladung",',
    '      "description": "Ein Parameter mit Vorgabewert (Anzahl: Integer = 10). Für Teams, die Überladungen bevorzugen: Vorgabewerte landen beim Aufrufer im Code, ändern sich nicht mit der Bibliothek und ' +
    'vertragen sich schlecht mit Überladungen. Gemeldet wird einmal je Deklaration (Klassenmitglied, interface-Teil, forward oder eine Routine nur im implementation-Teil); der Rumpf zu einer Deklaration ni' +
    'cht noch einmal. Die Schnellkorrektur fügt vor der Deklaration je weggelassenem Standardparameter am Ende eine Überladung ein, die mit dem Vorgabewert weiterreicht, entfernt die Vorgabewerte (auch im ' +
    'Rumpf wiederholte) und ergänzt overload. Keine Korrektur, wenn die Signatur von außen vorgegeben ist (virtual, dynamic, abstract, override, message, external, Interface-Typen), der Name als Wert benut' +
    'zt wird (@Routine, Methodenzeiger), es schon eine gleichnamige Überladung gibt, in bedingter Übersetzung oder wenn der Rumpf nicht eindeutig zu finden ist."',
    '    },',
    '    {',
    '      "id": "empty-routine",',
    '      "name": "Leere Methode",',
    '      "description": "Eine Methode oder Routine, deren Rumpf weder eine Anweisung noch einen Kommentar (noch eine Compiler-Direktive) enthält. Entweder fehlt der Inhalt oder die Methode kann weg. Nich' +
    't gemeldet werden virtuelle und dynamische Methoden (Ersatz für abstract in Basisklassen), Nachrichten-Handler, Methoden von Klassen mit Interfaces (der Compiler verlangt jede Interface-Methode), Erei' +
    'gnis-Handler, die in der Formulardatei stehen (die IDE entfernt leere beim Speichern), und Rümpfe mit Kommentar, etwa Überschreibungen, die bewusst nichts tun. Schnellkorrekturen: Kommentar zwischen b' +
    'egin und end einfügen; Methode entfernen (Deklaration samt XML-Doku und Rumpf) nur bei privaten Methoden und Routinen ohne Deklaration im interface-Teil, die sonst nirgends in der Datei vorkommen und ' +
    'keine Signatur von außen erfüllen."',
    '    },',
    '    {',
    '      "id": "trivial-accessor",',
    '      "name": "Zugriffsmethode liest bzw. setzt nur ein Feld",',
    '      "description": "Ein Getter, dessen Rumpf nur Result := FName; enthält (auch Exit(FName), Self.FName), oder ein Setter, dessen Rumpf nur FName := Value; enthält (mit refactoring.inlineAccessorEqu' +
    'alityCheck auch if FName <> Value then FName := Value;). Die Property kann direkt auf das Feld zeigen. Nur Methoden, die nicht virtual, dynamic, override oder abstract, keine class-Methoden, nicht übe' +
    'rladen oder generisch sind, keine Interface-Methode implementieren (auch nicht über eine Methodenzuordnung), keinen index haben und von keinem anderen Mitglied der Klasse benutzt werden; das Feld gehö' +
    'rt zur Klasse und hat den Typ der Property. Stumm, solange refactoring.inlineAccessorDiagnostic aus ist (Vorgabe) oder refactoring.inlineAccessor aus ist. Sicherheit mittel: Aufrufe in anderen Units s' +
    'ieht die Regel nicht. Keine Korrektur in der Regel; die Code-Aktion „Zugriffsmethode GetName durch Feld FName ersetzen“ an derselben Stelle prüft die Aufrufe mit der Referenzsuche und ersetzt."',
    '    },',
    '    {',
    '      "id": "write-only-property",',
    '      "name": "Property ohne read",',
    '      "description": "Eine Property hat write, aber kein read. Sie lässt sich nicht im Objektinspektor anzeigen, nicht im Debugger lesen und verwirrt Aufrufer. Properties ohne Typ bleiben außen vor (s' +
    'ie veröffentlichen eine geerbte Property neu, deren read vom Vorfahren kommt), ebenso Properties mit einem Attribut aus allowAttributes (mit oder ohne Endung Attribute). Schnellkorrektur: read FName e' +
    'rgänzen, wenn der Typ ein Feld FName gleichen Typs deklariert. Das Lesen einer solchen Property meldet readonly-property-assigned.",',
    '      "options": [',
    '        {',
    '          "name": "allowAttributes",',
    '          "description": "Attribute, die eine Property ohne read erlauben."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "xmldoc-mismatch",',
    '      "name": "XMLDoc passt nicht zur Signatur",',
    '      "description": "Ein ///-Kommentar passt nicht zu seiner Deklaration oder ist kein wohlgeformtes XML, wie die Compilerwarnungen W1201 bis W1208 mit eingeschalteter XML-Dokumentation. Einen Code n' +
    'ennt die Meldung nur, wo dcc ihn meldet (#1383): bei Kommentaren im interface-Teil einer Unit (nur die dokumentiert dcc) und unter den XML-Fehlern nur bei einem fremden Zeichen hinter dem Tagnamen (W1' +
    '205); ''<'' mit folgendem Leerzeichen, unbekannte Entitäten, leere Attributwerte und offene Tags übersetzt Delphi 13 ohne Warnung. Gemeldet werden: <param> zu einem Parameter, den es nicht gibt; fehlend' +
    'e <param>, wenn der Block überhaupt Parameter beschreibt (wie W1208, „but other parameters do“); mit checkReturns <returns> an einer Routine ohne Ergebnis und fehlendes <returns> an einer Funktion, de' +
    'ren Block Parameter beschreibt. <inheritdoc/> ergänzt, was fehlt. Außerdem ''<'' und ''&'' außerhalb von Tags und Entitäten, unbekannte Entitäten, Attributwerte ohne Anführungszeichen, nicht geschlossene ' +
    'und überzählige Endtags sowie cref-Ziele, die es nicht gibt (W1206, nur mit Index und wenn jede Unit aus uses bekannt ist; generische Ziele, Unit-Namen und Typen mit unbekannten Vorfahren bleiben stil' +
    'l). Mit requirePublic zusätzlich public- und published-Methoden und -Properties von Typen im interface ohne ///-Kommentar (nicht override, nicht Properties ohne Typ). Schnellkorrekturen: unbekannte <p' +
    'aram> der Reihe nach auf die fehlenden umbenennen, die übrigen als leere Zeilen in Signaturreihenfolge ergänzen, überzählige <param> und <returns> an Prozeduren entfernen; Zeichen maskieren, Anführung' +
    'szeichen setzen, Endtag ergänzen oder entfernen, ein fremdes leeres Tag wie TList<T> als Text schreiben; cref auf das ähnlichste Symbol setzen; Kommentargerüst erzeugen.",',
    '      "options": [',
    '        {',
    '          "name": "requirePublic",',
    '          "description": "Öffentliche Member ohne XMLDoc melden."',
    '        },',
    '        {',
    '          "name": "checkReturns",',
    '          "description": "<returns> prüfen."',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "queue-nil-in-package",',
    '      "name": "TThread.Queue(nil, …) in einem Package",',
    '      "description": "TThread.Queue(nil, …) oder TThread.ForceQueue(nil, …) in einer Unit eines Design-Time- oder Laufzeit-Packages: Der Eintrag gehört keinem Thread, beim Entladen des Packages räumt ' +
    'ihn niemand weg, und CheckSynchronize ruft ihn womöglich danach in fremdem Speicher auf. Package-Units erkennt die Regel über die .dpk bzw. .dproj des geladenen Projekts (eine .dpk ohne Projekt für si' +
    'ch). Eine Zeile mit dem Kommentar aus okMarker (Vorgabe mainthread-ok) ist ausgenommen. Sicherheit hoch. Korrektur: auf den Wrapper aus der Option wrapper umschreiben (Vorgabe TAtlasMainThread.Queue, ' +
    'bei ForceQueue ForceQueue); mit Klammer steht der Text so vor den übrigen Argumenten. ForceQueue mit Verzögerung bekommt keine Korrektur. Der Kommandozeilen-Linter liest die .dpk-Dateien unter dem gep' +
    'rüften Ordner. Leistet für jedes Plugin-Projekt dasselbe wie Tools/Check-MainThreadQueue.ps1; das Skript bleibt für Prüfungen ohne Atlas-Server.",',
    '      "options": [',
    '        {',
    '          "name": "wrapper",',
    '          "description": "Ersatz für TThread.Queue(nil, in der Schnellkorrektur."',
    '        },',
    '        {',
    '          "name": "okMarker",',
    '          "description": "Kommentar, der eine Zeile ausnimmt."',
    '        }');

implementation

end.
