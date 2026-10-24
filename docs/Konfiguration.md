# Konfiguration: atlas.json

<!-- Erzeugt von Tools/Update-ConfigDoc.ps1 aus schemas/atlas.schema.json. Nicht von Hand bearbeiten. -->

Einstellungen für Atlas. Jeder Schlüssel hat genau einen Ort (x-scope): "project" in atlas.json im Projektordner (Atlas › Projekt-Einstellungen), "global" in %APPDATA%\Atlas\settings.json für alle Projekte (Tools › Optionen › Atlas). "both" an beiden Orten: Die globale Datei gilt für alle Projekte, atlas.json übersteuert je Glied (rules: je Regel). Ein Schlüssel am falschen Ort wird ignoriert und gemeldet.

Jeder Schlüssel hat genau einen Ort (Spalte „Ort“): Projekt-Schlüssel stehen in `atlas.json` im Projektordner (im Plugin *Atlas › Projekt-Einstellungen*), globale in `%APPDATA%\Atlas\settings.json` für alle Projekte (im Plugin *Tools › Optionen › Atlas*). Ausnahme `rules`: Prüfregeln gehen an beiden Orten, global für alle Projekte, `atlas.json` übersteuert je Regel. Ein Schlüssel am falschen Ort wird ignoriert und als Warnung gemeldet. Fehlende Schlüssel nehmen den Standardwert. In der IDE bestimmt die laufende IDE die Delphi-Version (`delphiVersion` gilt dort nicht). Die Prüfregeln stehen in [Regeln.md](Regeln.md).

`atlas.json` liegt im Repository und gilt für alle im Team (#486). Zugangsdaten (Schlüssel wie `token`, `password`, `user` auf jeder Ebene, Adressen wie `https://user:pw@…` oder `?token=…`) und absolute Pfade (Laufwerk oder UNC) in den Pfad-Einstellungen (`project`, `testUnits.folder`, `testUnits.project`, `exclude`, `index.exclude`, `overrides[].files`) werden beim Lesen ignoriert und als Warnung gemeldet. Glob-Muster ab dem Projektordner (`/Generated/**`) und relative Pfade (`..\Tests`) bleiben erlaubt. Die globale `settings.json` ist persönlich und davon ausgenommen. Die Team-Einstellungen des Plugins stehen in der eigenen Projektdatei `.atlas` (siehe [Einstellungen.md](Einstellungen.md)).

## Schlüssel

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `delphiVersion` | global (settings.json) | string | – | z. B. `"37.0"`, `"23.0"` | Delphi-Version als Produktnummer ("13", "12", "10.4") oder wie in der Registry ("37.0" für Delphi 13, "23.0" für Delphi 12). Leer: passend zur ProjectVersion der .dproj, sonst die nächsthöhere, sonst die neueste installierte Version. Ist die eingestellte Version nicht installiert, warnt das Serverprotokoll mit der Stelle in settings.json, und die automatische Wahl greift. In der IDE gilt immer die laufende IDE. |
| `minDelphiVersion` | Projekt (atlas.json) | string | – | z. B. `"23.0"`, `"22.0"` | Älteste Delphi-Version, mit der das Projekt übersetzen muss, als Produktnummer ("12", "11") oder wie in der Registry ("23.0"). Atlas meldet Sprachmerkmale neuerer Versionen (Regel language-feature, z. B. "is not" oder If-Ausdruck bei "12"), und Code-Aktionen, Schnellbefehle und Formatieren erzeugen sie nicht. Gilt die ältere aus dieser und der gewählten Version (delphiVersion bzw. laufende IDE). Leer: nur die gewählte Version. |
| `language` | global (settings.json) | string | `"de"` | `"de"`, `"en"` | Sprache der Meldungen. |
| `encoding` | Projekt (atlas.json) | string | `"utf-8"` | z. B. `"utf-8"`, `"windows-1252"`, `"windows-1250"` | Vorgabe-Kodierung für Dateien ohne BOM, wenn die Erkennung nicht entscheidet (reines ASCII, ungültiges UTF-8): "utf-8" oder eine ANSI-Codepage wie "windows-1250". Binäre Formulare werden nie geändert. |
| `project` | Projekt (atlas.json) | string | – |  | Projektdatei (.dproj) relativ zu diesem Ordner. Leer: automatisch suchen. |
| `config` | Projekt (atlas.json) | string | – | z. B. `"Debug"`, `"Release"` | Build-Konfiguration, z. B. Debug oder Release. |
| `platform` | Projekt (atlas.json) | string | – | z. B. `"Win32"`, `"Win64"` | Zielplattform. |
| `rules` | global und Projekt | object | – |  | Prüfregeln einzeln einstellen: Regel-ID → Schweregrad oder Objekt mit "severity" und Optionen. Hauptschalter je Gruppe der Einstellungsseite (#909): "group:<gruppe>": "off" schaltet alle Regeln der Gruppe ab (Gruppen siehe Regeln.md, z. B. "group:threads"). Die Gruppe „Compiler vorab“ nimmt auch ein Objekt (#1024): "group:compiler": {"severity": "off", "typeLevel": "off"}; "typeLevel": "off" schaltet nur die Regeln der Stufe T ab, die Ausdruckstypen brauchen (Stufen siehe Regeln.md). Die Konfidenz eines Treffers begrenzt den Schweregrad auch hier: Bei mittlerer Konfidenz bleibt ein Treffer höchstens eine Warnung, bei niedriger höchstens ein Hinweis, auch mit "error". |
| `profile` | Projekt (atlas.json) |  | `"standard"` | z. B. `"fast"`, `"strict"` | Regelprofil: standard, fast (nur Bugs und Schwachstellen), strict (experimentelle Regeln an, minConfidence low), security, style oder ein eigenes aus "profiles". Als Objekt getrennt für Editor und Kommandozeile. |
| `profiles` | Projekt (atlas.json) | object | – |  | Eigene Regelprofile: Name → { "extends": eingebautes oder eigenes Profil, "categories": nur diese Kategorien, "rules": Regel-ID → Schweregrad }. |
| `overrides` | Projekt (atlas.json) | array<object> | – |  | Pfadregeln: Schweregrade für Dateien, die eines der Glob-Muster treffen, z. B. Tests oder generierten Code herabstufen. Regel-ID "*" steht für alle Regeln; spätere Einträge haben Vorrang. |
| `excludeTests` | Projekt (atlas.json) | boolean | `false` |  | Test-Units und Testprojekte (uses DUnitX.TestFramework, TestFramework oder TestInsight.*) nicht prüfen. |
| `testProfile` | Projekt (atlas.json) | string | – | z. B. `"fast"` | Regelprofil für Test-Units und Testprojekte; leer: wie "profile". |
| `compiler` | global (settings.json) | object | – |  | Compiler-Anbindung: Kommandozeilen-Compiler (dcc32/dcc64) oder eine eigene IDE über cc.ps1. |
| `vcs` | global (settings.json) | object | – |  | Versionsverwaltung (Git, SVN) für geänderte Dateien, Branch und Revision. |
| `completion` | gemischt, siehe unten | object | – |  | Code-Vervollständigung. |
| `refactoring` | Projekt (atlas.json) | object | – |  | Code, den Atlas erzeugt. |
| `usesCommand` | global (settings.json) | boolean | `true` |  | Eine Zeile "/uses Unit1, Unit2" wird nach Enter gelöscht und die Units kommen ins passende uses. |
| `completeBlocks` | global (settings.json) | object | – |  | Eingabehilfen, die beim Tippen Code ergänzen. |
| `metrics` | global (settings.json) | boolean | `true` |  | Kennzahlen überhaupt: false schaltet die Kennzahlen über den Methoden (codeLens.metrics) und alle Regeln metric-* für alle Projekte ab. Ein Projekt übersteuert das je Regel, indem es sie in atlas.json unter "rules" ausdrücklich setzt, z. B. "metric-method-length": "warning". |
| `experimental` | global (settings.json) | object | – |  | Experimentelle Funktionen (#834): riskant oder noch unreif, abschaltbar, als „Experimentell“ gekennzeichnet und nach der Installation aus. |
| `slashCommands` | global (settings.json) | object | – |  | Schnellbefehle: Eine Zeile, die mit /name beginnt, wird nach Enter ausgeführt und verschwindet. Nach / schlägt die Vervollständigung alle Befehle vor. |
| `sortUses` | Projekt (atlas.json) | boolean string | `false` | `true`, `false`, `"alphabetic"`, `"namespace"` | "uses aufräumen" (source.organizeImports, z. B. beim Speichern) sortiert die uses: true oder "alphabetic" alphabetisch, "namespace" nach Namespace gruppiert (System, Vcl, ... und Units ohne Namespace zuletzt). Achtung: Die Reihenfolge bestimmt die Initialisierung der Units. |
| `usesKeep` | Projekt (atlas.json) | array<string> | `` |  | Units, die "ungenutzte uses entfernen" nie entfernt, zusätzlich zu allen Units mit initialization-Abschnitt. |
| `deadCode` | Projekt (atlas.json) | object | – |  | Toter Code: Elemente, die als verwendet gelten, obwohl ihr Name im Code nicht vorkommt (RTTI, Serialisierung, Plugins). Gilt für unused-private-member, unused-public-member und unused-declaration, zusätzlich zu den Optionen keepAttributes und keepPatterns der Regeln. |
| `dfmPropertyRules` | Projekt (atlas.json) | array<object> | `` |  | Eigenschaftsregeln für Formulardateien: Vorgaben für Komponenten-Properties, gemeldet als dfm-property am Feld der Komponente in der Unit. Nicht gespeicherte Properties gelten mit ihrem default-Wert. |
| `memoryBudgetMb` | global (settings.json) | integer | `768` | 0… | Obergrenze für den Symbolindex im Arbeitsspeicher in MB. Darüber werden zuerst die Verwendungen ausgelagert (sie bleiben im Cache auf der Platte), dann Bibliotheks-Units (RTL, VCL) und zuletzt Projekt-Units kompakt gehalten (nur interface-Symbole). 0: unbegrenzt. |
| `index` | gemischt, siehe unten | object | – |  | Umfang des Symbolindex. Standard: alle Projekte der Projektgruppe, alle Units der Projekt-Suchpfade und alle Units der Bibliotheks- und Suchpfade der Delphi-Installation, auch wenn keine Unit sie einbindet. Reihenfolge: aktives Projekt, übrige Projekte, Suchpfade, Bibliothek; alles im Hintergrund, die Bibliothek aus dem gemeinsamen Cache. |
| `architecture` | gemischt, siehe unten | object | – |  | Architekturübersicht aus dem Index: zentrale Units, Teilsysteme, Zyklen und Querverbindungen im Fenster „Atlas-Architektur“, als Bericht (Markdown oder HTML, auch AtlasServer --architecture) und im MCP-Werkzeug get_architecture. |
| `requestTimeoutMs` | global (settings.json) | integer | `10000` | 1000… | Zeitlimit für Anfragen in Millisekunden. Länger laufende Anfragen werden abgebrochen und im Log gemeldet. |
| `diagnostics` | gemischt, siehe unten | object | – |  | Anonymisiertes Diagnoselog des Servers (je Anfrage Dauer, Ergebnis und Grundcode, je Lauf Start und Ende mit Grund). Es enthält keine Pfade, keine Projekt-, Unit- oder Bezeichnernamen und keinen Quelltext und lässt sich über „Diagnoselog exportieren“ weitergeben. |
| `highlight` | global (settings.json) | object | – |  | Zusammengehörige Schlüsselwörter hervorheben, wenn der Cursor auf einem steht. |
| `inlayHints` | global (settings.json) | object | – |  | Inlay Hints im Editor. |
| `codeLens` | global (settings.json) | object | – |  | Code Lens im Editor. |
| `references` | global (settings.json) | object | – |  | Treffersicherheit von Verwendungen, Aufrufhierarchie und Umbenennen: Neben den sicheren (eindeutig aufgelösten) Stellen erscheinen erschlossene mit Grund, etwa Aufrufe über ein Interface oder in einem inaktiven {$IFDEF}-Zweig. Umbenennen ändert nur sichere Stellen und listet die erschlossenen. |
| `hints` | global (settings.json) | object | – |  | Anzeige von XMLDoc-Kommentaren (///) und Begründungen (// WHY: …, #1123) im Hover-Tooltip und im Detailpanel der Vervollständigung des IDE-Plugins. Der Server bereitet die Doku immer vollständig auf; die Werte steuern nur die Anzeige. Ohne Angabe gelten die Werte aus Tools › Optionen › Drittanbieter › Atlas. |
| `directives` | global (settings.json) | object | – |  | Hilfen in Compiler-Direktiven: Vervollständigung und Hover für Direktiven wie {$R+} oder {$WARN …} und für bedingte Symbole in {$IFDEF}, {$IFNDEF}, {$IF Defined(…)}, {$DEFINE} und {$UNDEF}. |
| `stringLiteral` | Projekt (atlas.json) | object | – |  | Code-Aktionen „Als String-Literal“ und „Als Klartext kopieren“. |
| `memberOrder` | Projekt (atlas.json) | object | – |  | Code-Aktion „Klassenmitglieder ordnen“: Reihenfolge der Sichtbarkeitsabschnitte und der Mitglieder darin. |
| `testUnits` | Projekt (atlas.json) | object | – |  | Testunits anlegen und zwischen Unit und Testunit wechseln: Namensmuster, Ordner neuer Testunits und Testprojekt. |
| `minConfidence` | Projekt (atlas.json) | string | `"medium"` | `"low"`, `"medium"`, `"high"` | Regeltreffer unter dieser Konfidenz ausblenden. |
| `exclude` | Projekt (atlas.json) | array<string> | – | z. B. `["ThirdParty/**","Generated/*.pas"]` | Ordner und Dateien, die nicht geprüft werden (Glob-Muster relativ zu diesem Ordner: *, **, ?). |
| `mcp` | gemischt, siehe unten | object | – | z. B. `{"disabledTools":["rename_symbol","apply_code_action"]}`, `{"globalSettings":false}` | MCP-Modus (--mcp) für KI-Assistenten. |
| `format` | Projekt (atlas.json) | object | – |  | Formatierung (Dokument und Auswahl formatieren). Gesetzte Werte haben Vorrang vor .editorconfig. |
| `logLevel` | global (settings.json) | string | `"info"` | `"debug"`, `"info"`, `"warning"`, `"error"` | Mindeststufe der Meldungen im Ausgabefenster und in der Logdatei. Gilt ab dem nächsten Start; die Kommandozeilenoption --log-level hat Vorrang. |
| `logFile` | global (settings.json) | string | `""` |  | Optionale Logdatei des Servers (Rotation bei 10 MB). Gilt ab dem nächsten Start; --log hat Vorrang. |
| `traceFile` | global (settings.json) | string | `""` |  | Optionaler Mitschnitt aller JSON-Nachrichten zur Fehlersuche. Gilt ab dem nächsten Start; --trace hat Vorrang. |

## compiler

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `compiler.onSave` | global (settings.json) | boolean | `false` |  | Nach dem Speichern einer Quelldatei das Projekt im Hintergrund kompilieren und die Meldungen anzeigen. Nur mit dem Kommandozeilen-Compiler; über die IDE (backend ide) kompiliert Atlas wegen ihrer Startzeit nur auf den Befehl „Projekt kompilieren“ (atlas.server.compile). |
| `compiler.backend` | global (settings.json) | string | `"auto"` | `"auto"`, `"dcc"`, `"ide"`, `"off"` | Weg zum Compiler. auto: Atlas erkennt vorher je Delphi-Installation, ob dcc32/dcc64 vorhanden und nutzbar ist (die Starter und Community Edition melden einen Lizenztext statt zu kompilieren), merkt sich das und nimmt dann dcc, sonst ide (wenn ideCommand eingerichtet ist), sonst off. dcc: nur der Kommandozeilen-Compiler. ide: eine eigene IDE über cc.ps1 (ideCommand), immer mit eigener Instanz; die IDE des Benutzers wird nie angesprochen. off: Atlas kompiliert nie selbst. Ist kein Compiler nutzbar, meldet Atlas das einmal mit Grund und Ausweg, zeigt es im Status (atlas.server.status) und der Befehl „Projekt kompilieren“ antwortet mit dem Grund. |
| `compiler.ideCommand` | global (settings.json) | string | `""` | z. B. `"C:\Projekte\IDE-Plugins\Claude-Compile\cc.ps1"` | Pfad zu cc.ps1 (Claude-Compile) für den Weg über die IDE; leer = nicht eingerichtet. Atlas startet damit eine eigene Scratch-IDE (-Instance), nutzt sie für weitere Läufe wieder und beendet sie mit dem Server. |

## vcs

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `vcs.provider` | global (settings.json) | string | `"auto"` | `"auto"`, `"git"`, `"svn"`, `"off"` | auto: nach gefundener Arbeitskopie (.git oder .svn, die nächstliegende gilt, bei Gleichstand Git). git bzw. svn: nur diese Art. off: ohne Versionsverwaltung. Git und SVN über die Kommandozeile (git bzw. svn, TortoiseSVN mit Kommandozeilenwerkzeugen genügt); fehlt das Programm, meldet Atlas das einmal und arbeitet ohne Versionsangaben weiter. |

## completion

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `completion.matching` | global (settings.json) | string | `"fuzzy"` | `"fuzzy"`, `"prefix"` | Auswahl der Vorschläge: unscharf (Teilfolgen, Kürzel wie TSL für TStringList) oder nur nach Präfix, falls ein Editor nachträglich strikt filtert. |
| `completion.interfaceSection` | Projekt (atlas.json) | string | `"public"` | `"private"`, `"protected"`, `"public"` | Abschnitt der Klasse, in den „Interface implementieren“ die Deklarationen fehlender Interface-Methoden schreibt. |
| `completion.senderCast` | Projekt (atlas.json) | string | `"as"` | `"as"`, `"cast"` | Form der Typumwandlung, wenn nach Sender. ein Member der zugewiesenen Komponenten gewählt wird: "as" schreibt (Sender as TButton), "cast" schreibt TButton(Sender). |
| `completion.offerTryFinally` | global (settings.json) | boolean | `true` |  | Nach Übernahme eines Konstruktors in "Liste := TStringList.Create;" anbieten, den folgenden Code in try…finally mit Freigabe einzuschließen. |
| `completion.freeStyle` | Projekt (atlas.json) | string | `"free"` | `"free"`, `"freeAndNil"` | Freigabe im finally von „Freigabe absichern“: "free" schreibt Liste.Free, "freeAndNil" schreibt FreeAndNil(Liste). |
| `completion.keywords` | global (settings.json) | boolean | `true` |  | Schlüsselwörter passend zur Stelle vorschlagen (in Anweisungen begin, try …, im Klassenrumpf property, private …, nach ":" string, array …), sobald ein Zeichen getippt ist. |
| `completion.postfixTemplates` | global (settings.json) | boolean | `true` |  | Postfix-Vorlagen hinter einem Ausdruck anbieten: Liste.for wird zu for var Item in Liste do, FKunde.notnil zu if Assigned(FKunde) then, dazu tryf, ifa, fmt, nil, not, if, forin, free, try, var, exit und eigene Vorlagen mit "postfix: true". |
| `completion.genericConstraints` | global (settings.json) | boolean | `true` |  | Nach "TObjectList<" nur Typen vorschlagen, die die Constraints des Typparameters erfüllen (class, record, constructor, Interface oder Klasse), mit Überschrift „T: class · nur Klassen“ und den ausgeblendeten Arten in der Fußzeile. |
| `completion.createAccessors` | Projekt (atlas.json) | boolean | `true` |  | Nach read bzw. write einer Eigenschaftsdeklaration oben in der Liste „Feld FName anlegen“, „GetName anlegen“ und „SetName anlegen“ anbieten: Feld im private-Abschnitt (strict private, wenn die Klasse ihn nutzt), Methoden im Abschnitt nach accessorSection, Setter mit Änderungsprüfung. |
| `completion.accessorSection` | Projekt (atlas.json) | string | `"private"` | `"private"`, `"protected"` | Abschnitt der Klasse, in den „GetName anlegen“ und „SetName anlegen“ die Zugriffsmethoden schreiben. |
| `completion.resourceStrings` | global (settings.json) | boolean | `true` |  | Strg+Leertaste in einem String-Literal bietet „Als resourcestring auslagern“ an: Name aus den ersten Wörtern (S + CamelCase, Umlaute ersetzt), Eintrag im resourcestring-Abschnitt; gibt es den Text schon, zusätzlich „Vorhandenen verwenden“. Nicht in Konstanten, Attributen, case-Marken und Parametervorgaben. |
| `completion.resourceStringUnit` | Projekt (atlas.json) | string | `""` |  | Unit, in deren interface-Teil ausgelagerte resourcestrings kommen (etwa App.Texte); sie wird bei Bedarf in uses eingetragen. Leer: implementation-Teil der eigenen Unit. |
| `completion.typeConversion` | global (settings.json) | string | `"off"` | `"off"`, `"helper"`, `"function"` | **Experimentell (Vorgabe aus; wirkt nur mit `experimental.enabled`).** Passt ein Eintrag nicht zum erwarteten Typ (Zuweisung, Argument), schlägt Atlas die übliche Umwandlung als weiteren Eintrag direkt über dem Original vor, etwa Count.ToString für eine String-Zuweisung: Zahl, Boolean, Datum und Aufzählung nach string, string nach Zahl. helper: Helper-Stil (X.ToString, X.ToInteger), wo es einen gibt, sonst Funktion; function: Funktionsstil (IntToStr(X), StrToInt(X)); off: aus. Benötigte Units kommen ins uses. Für Gleitkomma nach Ganzzahl nur ein Hinweis auf Round und Trunc im Detailpanel. |
| `completion.assignAllFields` | global (settings.json) | boolean | `false` |  | **Experimentell (Vorgabe aus; wirkt nur mit `experimental.enabled`).** Hinter einem Record- oder Klassenausdruck mit Punkt am Anfang einer Anweisung (Opts.) steht „Alle Felder zuweisen (n)“ ganz oben: je öffentlich beschreibbarem Feld und jeder Property eine Zeile Opts.Feld := Platzhalter; in Deklarationsreihenfolge, mit 0, '', False, nil oder dem ersten Aufzählungswert als Vorgabe im Platzhalter-Modus. Felder, die die folgenden Zeilen schon zuweisen, fallen weg. Bei mehr als 15 Feldern zuerst eine Liste mit Kontrollkästchen. |
| `completion.usesDetails` | global (settings.json) | boolean | `true` |  | Im uses-Abschnitt: schon eingebundene Units ausblenden (die Fußzeile nennt sie), Units nach Projekt, RTL/VCL und Drittanbietern gruppieren, Kurzformen auf den Namespace ergänzen (Classes → System.Classes), Units aus dem anderen Abschnitt mit „bereits im interface-Teil“ bzw. „… implementation-Teil“ und im interface-Teil Units mit Zirkelbezug markieren; im Detailpanel Pfad und die ersten exportierten Typen. Aus: alle Units des Index als schlichte Liste. |
| `completion.inheritedCall` | global (settings.json) | boolean | `true` |  | Nach „inherited “ zuerst den vollständigen Aufruf der gleichnamigen Vorfahrmethode mit den Parametern der eigenen Methode anbieten (Marke „gleiche Parameter“), dann ihre übrigen Überladungen, in Konstruktoren und Destruktoren auch die übrigen Konstruktoren bzw. Destruktoren der Vorfahren. Abstrakte Vorfahrmethoden fehlen, die Fußzeile nennt sie. In Funktionen ergänzt die Übernahme „Result := “, wenn vor inherited nichts in der Zeile steht. Aus: nur die Namen der Vorfahrmethoden. |
| `completion.attributes` | global (settings.json) | boolean | `true` |  | Nach „[“ vor einer Typ-, Methoden-, Feld-, Property- oder Parameterdeklaration nur Attributklassen (Nachfahren von TCustomAttribute) ohne die Endung Attribute anbieten; bekannte zuerst (DUnitX Test, TestCase, TestFixture, Setup, TearDown, JSONName, JSONMarshalled, die Compiler-Attribute weak, unsafe, volatile, Ref), rechts die Parameter des Konstruktors bzw. die Unit, aus nicht eingebundenen Units mit uses-Eintrag. Nach „(“ zeigt der Parameter-Hint den Konstruktor. Aus: die gewöhnliche Liste. |
| `completion.anonymousMethods` | global (settings.json) | boolean | `true` |  | Erwartet ein Argument oder eine Zuweisung einen Methodenreferenztyp (reference to procedure/function, z. B. TProc, TFunc<T>, TPredicate<T> oder ein eigener), oben in der Liste ein Gerüst mit passender Signatur anbieten: procedure(const Value: TKunde) bzw. function(const Value: TKunde): Boolean mit begin/end und Cursor im Rumpf. Die Parameter Arg1, Arg2 der generischen RTL-Typen heißen Value bzw. nach ihrem Typ, mit dem Parameterpräfix des Projekts. Nach „(“ erscheint das Gerüst von selbst. Aus: kein Gerüst. |
| `completion.withOrigin` | global (settings.json) | boolean | `true` |  | In with-Blöcken Mitglieder des with-Objekts kennzeichnen: Marke „aus qryOrders“ (bei verschachtelten with das innerste passende Objekt, wie der Compiler), und wenn das Mitglied einen gleichnamigen lokalen Namen oder ein Mitglied von Self verdeckt, die Warnmarke „verdeckt Self.Name“ mit Warnfläche. Das Detailpanel nennt beide Bedeutungen. Aus: Mitglieder ohne Herkunft. |
| `completion.exceptionClasses` | global (settings.json) | boolean | `true` |  | Nach „raise “ und „on E: “ nur Exception-Klassen anbieten. Nach raise Projektklassen vor denen der Bibliotheken, Übernahme als EFoo.Create('') mit dem Cursor zwischen den Anführungszeichen, dazu je Klasse ein Eintrag EFoo.CreateFmt. Nach „on E: “ zuerst die Gruppe „Aus dem try-Block“ mit den Klassen aus <exception cref> der dort aufgerufenen Routinen (und bekannten Fällen der RTL wie StrToInt → EConvertError), darunter „Allgemein“; im selben except schon behandelte Klassen fehlen, Klassen, die ein früherer Zweig schon fängt, tragen die Warnung „nie erreicht“. Aus: die gewöhnliche Liste. |
| `completion.syntaxNotice` | global (settings.json) | boolean | `true` |  | Hinweis bei unvollständigem Code: Steht vor dem Cursor in der aktuellen Routine bzw. Klassendeklaration ein Syntaxfehler, zeigt die Liste oben die Warnleiste „Ergebnisse möglicherweise unvollständig · Syntaxfehler in Zeile n“; Klick auf die Zeilenangabe springt dorthin. Ohne Vorschläge zeigt der leere Zustand den Fehler. Fehler in anderen Routinen und die Stelle, an der gerade getippt wird, zählen nicht. Aus: kein Hinweis. |
| `completion.sameNameVariants` | global (settings.json) | boolean | `true` |  | Kommt ein Name in mehreren Units vor, jede Variante mit ihrer Unit zeigen; die Variante, die der Compiler nach den uses wählt (letzte Unit gewinnt), steht zuerst mit „aktiv“, das Detailpanel nennt alle Units, die den Namen deklarieren. Aus: nur die aktive Variante. |
| `completion.sameNameInsert` | global (settings.json) | string | `"prefix"` | `"prefix"`, `"uses"` | Übernahme einer nicht aktiven Variante: prefix fügt den Unit-Präfix ein (Vcl.Graphics.TBitmap), uses verschiebt die Unit in ihrer uses-Liste nach hinten bzw. ergänzt sie; das Detailpanel warnt dann, dass andere Stellen ihre Bedeutung ändern können. |
| `completion.showFmxUnits` | global (settings.json) | boolean | `false` |  | Varianten aus FireMonkey-Units (FMX.*) zeigen. Aus: Die Fußzeile nennt sie als ausgeblendet. |
| `completion.nameSuggestions` | global (settings.json) | boolean | `true` |  | An der Namensposition einer Deklaration mit bekanntem Typ (var-Abschnitt, Inline-var, Feld, Parameter) Namen aus dem Typ vorschlagen: TCustomerList ergibt Customers, CustomerList und List, mit F, A bzw. L, wenn mindestens 60 % der Deklarationen dieser Art im Projekt das Präfix tragen oder die Projektdatei .atlas es unter naming vorgibt. |

## refactoring

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `refactoring.inlineVar` | Projekt (atlas.json) | boolean | `true` |  | Inline-Variablen (for var Item in …, var Name := …) erzeugen, wenn die Delphi-Version sie kennt (ab 10.3). Aus: Atlas trägt die Variable in den var-Abschnitt der Routine ein. |
| `refactoring.changeSignature` | Projekt (atlas.json) | boolean | `true` |  | Code-Aktion „Signatur ändern …“: Parameter hinzufügen, entfernen, umsortieren und umbenennen samt Aufrufern, Überschreibungen, Interfaces und gebundenen Ereignissen. |
| `refactoring.newParameter` | Projekt (atlas.json) | string | `"overload"` | `"overload"`, `"updateCallers"` | Neue Parameter: overload behält die alte Signatur als Überladung, die mit dem angegebenen Wert weiterreicht (Aufrufer bleiben); updateCallers ändert alle Aufrufer. Interface-Methoden und gebundene Handler gehen nur mit updateCallers. Standardwerte erzeugt Atlas nie. |
| `refactoring.virtualOverload` | Projekt (atlas.json) | boolean | `false` |  | Die Überladung mit der alten Signatur bei virtuellen Methoden ebenfalls virtual machen. |
| `refactoring.syncSignatures` | Projekt (atlas.json) | boolean | `true` |  | Weichen Deklaration und Implementierung voneinander ab, die Aktionen „Implementierung an Deklaration angleichen“ und umgekehrt anbieten. |
| `refactoring.forwardDeclaration` | Projekt (atlas.json) | boolean | `true` |  | Typen, die im type-Abschnitt vor ihrer Deklaration benutzt werden, melden und „Forward-Deklaration ergänzen“, „type-Blöcke zusammenlegen“ bzw. „Deklaration nach oben verschieben“ anbieten; überflüssige Forward-Deklarationen melden. |
| `refactoring.propertyFromAccessors` | Projekt (atlas.json) | boolean | `true` |  | Code-Aktionen „Property X anlegen“ auf einer Zugriffsmethode und „Fehlende Properties anlegen (n)“ auf der Kopfzeile einer Klasse: Zu Methoden wie GetX/SetX (auch indiziert, IsX/HasX für Boolean) ohne Property X legt Atlas die Property an, mit read FX, wenn der Getter nur das Feld liefert. Vorschau vor dem Übernehmen. |
| `refactoring.propertyFromAccessorsPrefixes` | Projekt (atlas.json) | array<string> | `["Get","Set","Is","Has"]` |  | Präfixe der Zugriffsmethoden. Is und Has gelten nur für Getter mit Ergebnis Boolean, Get nur für Getter, Set nur für Setter, eigene Präfixe für beide. |
| `refactoring.propertyFromAccessorsReplaceCalls` | Projekt (atlas.json) | string | `"ask"` | `"ask"`, `"always"`, `"never"` | Aufrufe im ganzen Projekt auf die Property umstellen (X.GetCaption → X.Caption, X.SetCaption(V) → X.Caption := V); Übergaben als Methodenzeiger bleiben. ask: beide Aktionen anbieten, mit und ohne Umstellen; always: immer umstellen; never: nie. |
| `refactoring.propertyFromAccessorsSection` | Projekt (atlas.json) | string | `"accessor"` | `"accessor"`, `"public"`, `"published"` | Abschnitt der neuen Property: accessor wie die sichtbarste Zugriffsmethode, public bzw. published mindestens dort. |
| `refactoring.propertyFromAccessorsHideAccessors` | Projekt (atlas.json) | string | `"off"` | `"off"`, `"private"`, `"protected"` | Zugriffsmethoden nach dem Anlegen nach private bzw. protected verschieben, wenn sie danach außerhalb ihrer Klasse nicht mehr benutzt werden (virtuelle und überschriebene bleiben). off: nie. |
| `refactoring.freeFields` | Projekt (atlas.json) | boolean | `true` |  | Im Konstruktor (oder einer von ihm aufgerufenen privaten Methode) mit TKlasse.Create erzeugte Objektfelder, die die Klasse nirgends freigibt, melden (field-not-freed, bis #918 owned-field-not-freed) und die Code-Aktionen „Im Destruktor freigeben“ am Feld und „Alle eigenen Objekte freigeben (n)“ an der Klasse anbieten. Fehlt der Destruktor, legt Atlas ihn mit override und inherited an. Ausgenommen sind Komponenten mit Owner sowie Interface- und Record-Felder; zurückgegebene oder weitergereichte Felder meldet Atlas als unklar (owned-field-free-unclear). |
| `refactoring.freeFieldsStyle` | Projekt (atlas.json) | string | `"free"` | `"free"`, `"freeAndNil"` | Form der Freigabe im Destruktor: free schreibt FFeld.Free, freeAndNil schreibt FreeAndNil(FFeld). |
| `refactoring.invertBoolean` | Projekt (atlas.json) | boolean | `true` |  | Code-Aktion „Bedeutung umkehren (X → Y)“ auf einer Boolean-Variablen, einem Feld, einer Konstanten, einer Property, einem Parameter oder einer Boolean-Funktion des Projekts: neuer Name mit der Gegenbedeutung, jede Stelle so verneint, dass das Programm gleich bleibt (X := True → Y := False, if not X → if Y, X = False → Y). Funktionen liefern im Rumpf das Gegenteil, Properties nehmen Feld, Getter, Setter und default mit, Überschreibungen und Interfaces folgen. Vorschau mit Warnungen (var/out-Übergaben, @X, Zeichenketten für RTTI), je Datei ein Rückgängig-Schritt. |
| `refactoring.invertBooleanAntonyms` | Projekt (atlas.json) | object | `{}` |  | Eigene Gegensatzpaare für den Namensvorschlag, z. B. {"Verbose": "Silent"}; gelten in beiden Richtungen und vor den eingebauten (Hidden ↔ Visible, Enabled ↔ Disabled, IsEmpty ↔ HasItems, Valid ↔ Invalid, Locked ↔ Unlocked …). |
| `refactoring.invertBooleanFallbackPrefix` | Projekt (atlas.json) | string | `"Not"` |  | Präfix, wenn kein Gegensatzpaar passt: FReady → FNotReady, IsReady → IsNotReady; ein vorhandenes Präfix fällt weg (IsNotReady → IsReady). |
| `refactoring.invertBooleanIncludeDfm` | Projekt (atlas.json) | boolean | `true` |  | Published Properties auch in den Formularen (.dfm, .fmx) der Klasse und ihrer Nachfahren umkehren: Name und Wert (Hidden = True → Visible = False); der default der Property wird mit umgedreht. Aus: Formulare bleiben, die Vorschau warnt. |
| `refactoring.tryFinally` | Projekt (atlas.json) | boolean | `true` |  | Code-Aktion „try/finally ergänzen“ nach X := TFoo.Create(…) für lokale Variablen (bei Result: try/except, das nur im Fehlerfall freigibt). Der try-Block schließt die folgenden Anweisungen bis zum Blockende bzw. bis zum Ende der Auswahl ein. |
| `refactoring.classActions` | Projekt (atlas.json) | boolean | `true` |  | Code-Aktionen in einer Klassendeklaration: „Getter, Setter und Feld erzeugen“ auf einer Property ohne read/write, „Methoden von IFoo implementieren“ und „Name überschreiben“ für virtuelle Methoden der Vorfahren. |
| `refactoring.explicitType` | Projekt (atlas.json) | boolean | `true` |  | Code-Aktion „Typ ausschreiben“ auf dem Namen von var X := …, const X = … und for var X in … ohne Typangabe: fügt den abgeleiteten Typ ein (var Count: Integer := Lines.Count) und trägt seine Unit bei Bedarf ins uses ein. |
| `refactoring.extract` | Projekt (atlas.json) | boolean | `true` |  | Code-Aktionen „Methode extrahieren“ (markierte Anweisungen werden eine neue Methode bzw. Routine; Parameter nach Datenfluss: nur gelesen const, geschrieben und danach gelesen var bzw. out, nur innen lokale Variable), „Variable einführen“ (auch für alle textgleichen Vorkommen im Block) und „Konstante extrahieren“ (in der Routine oder in der Unit). Inline-Variable oder var-Abschnitt nach inlineVar. |
| `refactoring.completeCase` | Projekt (atlas.json) | boolean | `true` |  | Code-Aktion „case vervollständigen“: ergänzt bei case über einem Aufzählungstyp genau die fehlenden Werte als leere Zweige in Deklarationsreihenfolge. Mit else heißt sie „Fehlende Werte vor else ergänzen“ und ist nicht die bevorzugte Aktion. |
| `refactoring.resolveWith` | Projekt (atlas.json) | boolean | `true` |  | Code-Aktion „with auflösen“: Bezeichner im with-Rumpf, die zu einem Mitglied eines with-Ausdrucks gehören, bekommen diesen Ausdruck vorangestellt (innerstes Element zuerst); aufwendige Ausdrücke vom Klassentyp kommen vorher in eine lokale Variable. Ist ein Bezeichner nicht eindeutig auflösbar, gibt es die Aktion nicht. |
| `refactoring.inline` | Projekt (atlas.json) | boolean | `false` |  | **Experimentell (Vorgabe aus; wirkt nur mit `experimental.enabled`).** Code-Aktionen „Variable einbetten“ und „Methode einbetten“ auf einer lokalen Variablen bzw. einem Aufruf: Die Variable verschwindet, ihre Stellen bekommen den Ausdruck; der Aufruf wird durch den Rumpf ersetzt (lokale Namen eindeutig umbenannt, Argumente eingesetzt oder in Hilfsvariablen, Mitglieder mit dem Empfänger, das Ergebnis direkt oder in einer Variablen wie AddResult). Angeboten nur, wenn Datenfluss und Namensauflösung zeigen, dass sich die Bedeutung nicht ändert. Hilfsvariablen als Inline-Variable oder im var-Abschnitt nach refactoring.inlineVar. |
| `refactoring.moveClass` | Projekt (atlas.json) | boolean | `false` |  | **Experimentell (Vorgabe aus; wirkt nur mit `experimental.enabled`).** Code-Aktion „Klasse in eigene Unit verschieben …“ auf der ersten Zeile einer Klassen- oder Record-Deklaration: Die Deklaration samt Attributen, Kommentar und Methodenrümpfen kommt in eine neue Unit neben der alten (Name aus dem Klassennamen ohne T, im Dialog änderbar). Die neue Unit steht danach in .dpr bzw. .dpk und .dproj; ihre uses entstehen aus den benötigten Namen, und alle Units, die die Klasse verwenden, binden sie ein. Nicht angeboten bei Zugriff auf Namen aus dem implementation-Teil der alten Unit, Kreisverweis, Formularklassen und bedingter Übersetzung. |
| `refactoring.unitRenameFollowUp` | Projekt (atlas.json) | string | `"off"` | `"ask"`, `"off"` | **Experimentell (Vorgabe aus; wirkt nur mit `experimental.enabled`).** Nach dem Umbenennen einer Unit in der Projektverwaltung (die IDE passt nur .dpr und .dproj an) meldet Atlas in der Benachrichtigungszentrale, wie viele Units den alten Namen noch verwenden, und bietet an, uses-Einträge und qualifizierte Bezeichner (Alt.TKlasse) im Projekt oder in der Projektgruppe nachzuziehen, mit Vorschau und rückgängig machbar. ask: anbieten; off: aus. |
| `refactoring.createMethod` | Projekt (atlas.json) | boolean | `true` |  | Methode aus Aufruf anlegen: Nach "(" hinter einem unbekannten Namen und mit Strg+Leer auf einem solchen Aufruf bietet Atlas an, die Methode (in einer Methode der Klasse) bzw. freie Routine anzulegen; bei Obj.Name(…) in der Klasse von Obj, sofern sie zum Projekt gehört (auch als Code-Aktion). Parametertypen aus den Argumenten, Rückgabetyp aus der Zuweisung bzw. dem erwarteten Typ; ohne Zuweisung eine Prozedur. |
| `refactoring.createMethodSection` | Projekt (atlas.json) | string | `"private"` | `"private"`, `"protected"`, `"public"` | Abschnitt der neuen Methode, wenn die Klasse in derselben Unit steht. In einer anderen Unit kommt sie immer nach public, damit der Aufruf übersetzt. |
| `refactoring.createMethodCaret` | Projekt (atlas.json) | string | `"call"` | `"call"`, `"body"` | Wo der Cursor nach „Methode anlegen“ in der Vervollständigung steht: an der Aufrufstelle (call) oder in der leeren Zeile des neuen Rumpfs (body). |
| `refactoring.constParameters` | Projekt (atlas.json) | boolean | `true` |  | Erzeugte Parameter für Strings, Records und Interfaces mit const (Methode aus Aufruf anlegen). |

## completeBlocks

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `completeBlocks.docComment` | global (settings.json) | boolean | `true` |  | Gerüst des Dokumentationskommentars nach dem dritten / über einer Deklaration erzeugen (summary, typeparam, param, returns), dazu die Code-Aktionen „Dokumentationskommentar erzeugen“ und „Dokumentation an die Signatur anpassen“. Überzählige param werden dabei als <!-- entfernt: Name --> markiert, nicht gelöscht. false: /// bleibt, wie getippt. |

## experimental

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `experimental.enabled` | global (settings.json) | boolean | `false` |  | Hauptschalter: false = keine experimentelle Funktion wirkt, auch wenn ihr eigener Schalter an ist; die Einzelschalter behalten ihren Wert. true = die Einzelschalter (Kennzeichen „Experimentell“, Vorgabe aus) gelten. |

## slashCommands

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `slashCommands.enabled` | global (settings.json) | boolean | `true` |  | Schnellbefehle auswerten. |
| `slashCommands.disabled` | global (settings.json) | array<string> | `` |  | Abgeschaltete Befehle ohne /, z. B. ["uses"]. usesCommand: false wirkt wie "uses" in dieser Liste. |
| `slashCommands.headerTemplate` | global (settings.json) | string | `""` |  | Vorlage für /header mit den Platzhaltern {unit}, {jahr} und {autor}. Leer: die Vorlage der Regel file-header, sonst ein einfacher Kopf. |
| `slashCommands.logCall` | global (settings.json) | string | `""` |  | Protokollaufruf für /log, /except und /measure: ein Routinenname wie "Log.Debug" bekommt den Text als Argument, {text} setzt ihn an diese Stelle, z. B. "Logger.Send(TLogLevel.Debug, {text})". Leer: OutputDebugString(PChar(…)). |
| `slashCommands.componentPalette` | global (settings.json) | string | `"Eigene"` |  | Palettenseite, auf der /component die neue Komponente mit RegisterComponents einträgt. |
| `slashCommands.todoOwner` | global (settings.json) | string | `""` |  | Name hinter -o, den /todo einträgt. Leer: user.name aus der git-Konfiguration (Repository, dann Benutzerordner), sonst der Anmeldename. /todo -oName in der Zeile geht vor. |
| `slashCommands.todoCategory` | global (settings.json) | string | `""` |  | Kategorie hinter -c, die /todo einträgt. Leer: keine. /todo -cKategorie in der Zeile geht vor. |
| `slashCommands.sortUsesRemoveUnused` | global (settings.json) | boolean | `true` |  | /sortuses streicht auch ungenutzte Units laut Index. Units mit initialization oder finalization und die aus usesKeep bleiben. |
| `slashCommands.enumHelper` | global (settings.json) | boolean | `true` |  | /helper für eine Aufzählung legt die Namenstabelle cNames sowie ToString und FromString an. Aus: ein leerer record helper wie bei anderen Typen. |
| `slashCommands.setHelper` | global (settings.json) | boolean | `true` |  | /helper für eine Menge (set of) legt Contains, ToText, Toggle und All an. Aus: ein leerer record helper wie bei anderen Typen. |

## deadCode

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `deadCode.keepAttributes` | Projekt (atlas.json) | array<string> | `` |  | Attributnamen ohne "Attribute", z. B. "JsonName": Alle Mitglieder eines Typs mit diesem Attribut gelten als verwendet. |
| `deadCode.keepPatterns` | Projekt (atlas.json) | array<string> | `` |  | Namensmuster mit * und ?, auch als Typ.Name, z. B. "*Handler" oder "TPlugin.*": Passende Elemente gelten als verwendet. |

## index

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `index.projectGroup` | global (settings.json) | boolean | `true` |  | Alle Projekte der Projektgruppe indizieren; aus = nur das Projekt der geöffneten Datei. |
| `index.searchPaths` | global (settings.json) | boolean | `true` |  | Alle Units der Projekt-Suchpfade indizieren; aus = nur über uses erreichbare. |
| `index.libraryPaths` | global (settings.json) | boolean | `false` |  | Alle Units der Bibliotheks- und Suchpfade der Installation indizieren (RTL, VCL, Komponenten); aus = nur über uses erreichbare. |
| `index.usages` | global (settings.json) | boolean | `true` |  | Verwendungen der Bezeichner in Projekt-Units mit indizieren (Verwendungsbeispiele); aus = nur Deklarationen, kleinerer Index. |
| `index.removeOrphans` | global (settings.json) | boolean | `true` |  | Index-Caches gelöschter Projekte (z. B. entfernter Branch-Ordner) und Caches im alten Format beim Laden eines Projekts löschen. Liegt das Projekt auf einem gerade nicht verbundenen Laufwerk, bleibt der Cache. |
| `index.cacheMaxAgeDays` | global (settings.json) | integer | `14` | 0…3650 | Index-Caches löschen, die so viele Tage nicht benutzt wurden (Laden des Projekts zählt als Benutzung); 0 = aus. Das betrifft auch die Bibliotheks-Caches deinstallierter Delphi-Versionen. |
| `index.cacheMaxMb` | global (settings.json) | integer | `256` | 0…1048576 | Höchstgröße des Cache-Ordners in MB; darüber gehen die am längsten nicht benutzten Caches zuerst. 0 = ohne Grenze. |
| `index.exclude` | Projekt (atlas.json) | array<string> | `` | z. B. `["**/Demos/**","**/Samples/**"]` | Ordner oder Dateien, die nicht indiziert werden (Glob-Muster gegen den vollen Pfad: *, **, ?). |

## architecture

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `architecture.enabled` | global (settings.json) | boolean | `true` |  | Hauptschalter: false = kein Fenster, kein Menüeintrag, kein Bericht, kein get_architecture. |
| `architecture.scope` | global (settings.json) | string | `"projectGroup"` | `"project"`, `"projectGroup"` | Umfang der Auswertung: nur das aktive Projekt oder die ganze Projektgruppe. |
| `architecture.includeLibraryUnits` | global (settings.json) | boolean | `false` |  | Units aus RTL, VCL und den Bibliothekspfaden mitzählen; aus = nur Units der Projekte und ihrer Suchpfade. |
| `architecture.centralUnits` | global (settings.json) | integer | `15` | 5…100 | Wie viele zentrale Units Fenster, Bericht und get_architecture zeigen. |
| `architecture.exclude` | Projekt (atlas.json) | array<string> | `` | z. B. `["Tests/**","*.Tests"]` | Units, die nicht in die Auswertung eingehen: Glob-Muster auf den Unit-Namen oder den Pfad relativ zum Projekt (*, **, ?). |
| `architecture.baseline` | Projekt (atlas.json) | string | `""` | z. B. `"architektur-main.json"` | Gespeicherter Architekturstand (JSON aus AtlasServer --architecture <Datei.json> oder „Stand speichern …“), Pfad relativ zum Projekt: Fenster, Bericht und get_architecture vergleichen automatisch damit. Leer = kein Vergleich. |
| `architecture.failOn` | Projekt (atlas.json) | array<string> | `"newCycle"` |  | Welche Abweichungen AtlasServer --compare als Fehler meldet (Exitcode 1), wenn --fail-on fehlt: neue Zyklen, neue Querverbindungen, Units mit Teilsystemwechsel, zentrale Units mit stark gewachsener Abhängigkeit. |

## diagnostics

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `diagnostics.log` | global (settings.json) | boolean | `true` |  | Anonymisiertes Diagnoselog schreiben (%LOCALAPPDATA%\Atlas\Logs\Diagnose). |
| `diagnostics.logDays` | global (settings.json) | integer | `7` | 1…365 | Aufbewahrung des Diagnoselogs in Tagen. |
| `diagnostics.logMapFile` | global (settings.json) | boolean | `false` |  | Zuordnung Kurz-ID (doc#4) → Pfad lokal speichern, nur für die eigene Analyse. Der Export nimmt sie nie mit. |
| `diagnostics.usesCycleLive` | Projekt (atlas.json) | boolean | `true` |  | Zirkuläre Unit-Referenz schon beim Tippen melden (Regel uses-cycle): Ein Zyklus, in dem jede Kante im interface-Teil liegt, ist ein Fehler am auslösenden uses-Eintrag mit dem kürzesten Pfad; jede Unit im Hover springt an ihren uses-Eintrag. Schnellkorrektur „In implementation-uses verschieben“, wenn kein Bezeichner der Unit im interface-Teil gebraucht wird, sonst Sprung zu diesen Bezeichnern und „Graph zeigen“. Berücksichtigt den ungespeicherten Stand offener Units. false: keine Meldung im Editor; die projektweite Prüfung (--check, find_unused_code) bleibt. |
| `diagnostics.usesCycleImplementation` | Projekt (atlas.json) | boolean | `false` |  | Im Editor auch Zyklen mit mindestens einer implementation-Kante melden, als Hinweis (der Compiler erlaubt sie). Braucht usesCycleLive. |

## highlight

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `highlight.blockPairs` | global (settings.json) | boolean | `true` |  | Blockpaare (begin/end, try/finally/except/end, case/of/end, repeat/until, if/then/else, Typen) und Routinen hervorheben. |
| `highlight.directives` | global (settings.json) | boolean | `true` |  | Zusammengehörige {$IF…}/{$ELSE}/{$ENDIF} sowie {$REGION}/{$ENDREGION} hervorheben. |
| `highlight.exitPoints` | global (settings.json) | boolean | `true` |  | Ausstiegspunkte der Routine sowie Kopf und Ende der Schleife bei Break/Continue hervorheben. |
| `highlight.exitKeywords` | global (settings.json) | array<string> | `["Exit","raise","Abort","Halt"]` |  | Was als Ausstiegspunkt gilt; eigene Routinen, die immer eine Exception auslösen, lassen sich ergänzen. |

## inlayHints

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `inlayHints.parameterNames` | global (settings.json) | boolean | `true` |  | Parameternamen vor den Argumenten eines Aufrufs. |
| `inlayHints.inferredTypes` | global (settings.json) | boolean | `true` |  | Abgeleiteter Typ hinter var X := …, const X = … und for var X in … (im Plugin als Typmarke am Zeilenende). |
| `inlayHints.endMarkers` | global (settings.json) | boolean | `true` |  | Hinter dem end langer Blöcke anzeigen, was dort endet. |
| `inlayHints.endMarkerMinLines` | global (settings.json) | integer | `20` | 1… | Mindestlänge eines Blocks in Zeilen für eine Endmarkierung. |
| `inlayHints.includeDefines` | global (settings.json) | boolean | `true` |  | Hinter {$I datei.inc} die Symbole, die die Include-Datei setzt und die eine Bedingung der Unit prüft ("definiert COMPLIB_VCL"). |
| `inlayHints.controlChars` | global (settings.json) | boolean | `true` |  | Hinter Steuerzeichen wie ^C oder ^[ im Wert einer Konstanten ihr Code (#3, #27). |

## codeLens

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `codeLens.metrics` | global (settings.json) | boolean | `true` |  | Kennzahlen über jeder Methode: Länge in Codezeilen, Verschachtelungstiefe, zyklomatische und kognitive Komplexität, Parameteranzahl. Die Grenzwerte stehen bei den Regeln metric-* unter "max". |

## references

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `references.inferred` | global (settings.json) | boolean | `true` |  | Erschlossene Treffer zeigen: über ein Interface, das die Klasse umsetzt, über die überschriebene Methode eines Vorfahren, nicht eindeutige Überladungen, gleicher Name mit unbekanntem Typ (with, unbekannter Ausdruck) und Stellen in inaktiven Zweigen; aus = nur sichere Treffer wie bisher. |
| `references.textMatches` | global (settings.json) | boolean | `false` |  | Auch den Namen in String-Literalen als erschlossen melden, etwa für RTTI oder MethodAddress('Speichern'). |

## hints

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `hints.xmlDocExpand` | global (settings.json) | string | `"last"` | `"collapsed"`, `"last"`, `"expanded"` | XMLDoc beim Öffnen (#770): "collapsed" zeigt nur Deklaration, Summary und „Mehr anzeigen“, "last" wie zuletzt in dieser Sitzung (getrennt für Tooltip und Detailpanel, nach dem Neustart zugeklappt), "expanded" alle Abschnitte mit Überschrift (Parameter, Rückgabe, Ausnahmen, Hinweise, Beispiel …). |
| `hints.xmlDocFull` | global (settings.json) | boolean | – |  | Veraltet (#770), ersetzt durch xmlDocExpand: true wirkt wie "expanded", false wie "collapsed", solange xmlDocExpand fehlt. |
| `hints.xmlDocMaxLines` | global (settings.json) | integer | `0` | 0…50 | Höchstzahl der Doku-Zeilen, bevor der Inhalt mit dem Mausrad scrollt (0 = unbegrenzt, nur durch Bildschirm bzw. Popup begrenzt). |
| `hints.publishedMembers` | global (settings.json) | boolean | `true` |  | Hover über einer Komponentenklasse (#110): published-Properties und Ereignisse samt geerbter in Tabellen mit Typ, Vorgabe (default, implizit, nodefault, stored) und deklarierender Klasse, Filter für geerbte und nur mit Vorgabe, die Standard-Property einer Array-Property und „Liste kopieren“ mit Strg+C. Aus: nur Deklaration, Doku und Vererbung. |
| `hints.rationale` | global (settings.json) | boolean | `true` |  | Begründungen im Hover und in get_declaration (#1123): Kommentare wie // WHY: …, // HACK: … oder { NOTE: … } direkt über einer Deklaration (höchstens eine Leerzeile dazwischen) und im Rumpf einer Routine erscheinen im Abschnitt „Begründung“ unter Deklaration und XMLDoc, ab vier Einträgen hinter „Mehr anzeigen“. ADR-0007 öffnet die Datei aus adrFolder, #312 das Issue (Tracker der Willkommensseite), URLs den Browser. Aus: Atlas zeigt keine Begründungen; get_rationale bleibt über mcp.disabledTools abschaltbar. |
| `hints.rationaleMarkers` | global (settings.json) | array<string> | `["NOTE","WHY","HACK","IMPORTANT","RATIONALE"]` |  | Marken, die als Begründung gelten (#1123), Groß-/Kleinschreibung egal; die Liste ersetzt die Vorgabe. Nach der Marke folgt ein Doppelpunkt; ohne Doppelpunkt zählt sie nur in Großbuchstaben (// NOTE das …). TODO und FIXME bleiben bei der TODO-Übersicht (todo-comment) und erscheinen hier nie. |
| `hints.adrFolder` | global (settings.json) | string | `"docs/adr"` |  | Ordner der Architekturentscheidungen (#1123), relativ zum Projekt (Ordner der atlas.json): ADR-0007 bzw. ADR 7 in einer Begründung öffnet die Datei, deren Name mit 0007 (auch ADR-0007) beginnt, z. B. docs/adr/0007-threads.md. Ohne passende Datei ist der Verweis nicht anklickbar. |

## directives

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `directives.completion` | global (settings.json) | boolean | `true` |  | In {$ die Direktivennamen, nach {$WARN die Warnungsbezeichner und nach {$IFDEF, {$IFNDEF, {$DEFINE, {$UNDEF und in Defined( die bedingten Symbole vorschlagen, jeweils mit Herkunft (Konfiguration, Plattform, Compiler-Vorgabe, {$DEFINE} mit Zeile). |
| `directives.hover` | global (settings.json) | boolean | `true` |  | Hover über Schaltern wie {$R+} erklärt die Direktive mit DocWiki-Link; über {$IFDEF X} und Co. nennt er, ob X an dieser Stelle aktiv ist und wo es definiert wird (Projekt, Konfiguration und Plattform aus der .dproj, Compiler-Vorgabe, {$DEFINE} mit Datei und Zeile, auch aus Include-Dateien). Über {$IF}, {$ELSEIF} und {$IFOPT} nennt er den Wert der Bedingung mit Teilwerten und Herkunft (SizeOf nach Zielplattform, RTLVersion111 nach Delphi-Version, Declared aus dem Index, Schalter aus der .dproj oder einem {$R-} davor), über {$PUSHOPT}/{$POPOPT} das Gegenstück (#847). |

## stringLiteral

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `stringLiteral.style` | Projekt (atlas.json) | string | `"auto"` | `"auto"`, `"multiline"`, `"concat"` | auto: mehrzeiliger String mit ''', wenn die Delphi-Version ihn kennt (ab Delphi 12), sonst Verkettung. |
| `stringLiteral.lineBreak` | Projekt (atlas.json) | string | `"sLineBreak"` | `"sLineBreak"`, `"#13#10"`, `"#10"`, `"space"`, `"none"` | Was bei Verkettung zwischen den Zeilen steht; space z. B. für SQL, das einzeilig ankommen soll. |
| `stringLiteral.maxLineLength` | Projekt (atlas.json) | integer | `0` | 0… | Bei Verkettung lange Zeilen zusätzlich umbrechen (0 = nicht umbrechen). |

## memberOrder

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `memberOrder.sections` | Projekt (atlas.json) | array<string> | `["strict private","private","strict protected","protected","public","published"]` |  | Zielreihenfolge der Sichtbarkeitsabschnitte; nicht genannte kommen ans Ende. |
| `memberOrder.members` | Projekt (atlas.json) | array<string> | `["field","constructor","destructor","method","property"]` |  | Zielreihenfolge der Mitglieder in einem Abschnitt; innerhalb einer Art bleibt die Reihenfolge. |
| `memberOrder.sortFields` | Projekt (atlas.json) | boolean | `false` |  | Abschnitte mit Feldern auch dann verschieben, wenn sich dadurch die Reihenfolge der Felder (Speicherlayout) ändert. |
| `memberOrder.sortPublished` | Projekt (atlas.json) | boolean | `false` |  | Auch published-Abschnitte umsortieren; ihre Reihenfolge bestimmt Streaming und Objektinspektor. |

## testUnits

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `testUnits.pattern` | Projekt (atlas.json) | string | `"{unit}.Tests"` |  | Name der Testunit; {unit} steht für den Namen der getesteten Unit, z. B. "{unit}.Tests" oder "Test.{unit}". |
| `testUnits.folder` | Projekt (atlas.json) | string | `""` |  | Ordner für neue Testunits relativ zur Wurzel; leer: Ordner des Testprojekts. |
| `testUnits.project` | Projekt (atlas.json) | string | `""` |  | Testprojekt (.dproj oder .dpr) relativ zur Wurzel; leer: das Projekt im Arbeitsbereich, dessen .dpr DUnitX oder DUnit verwendet. |

## mcp

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `mcp.disabledTools` | global (settings.json) | array<string> | `` |  | Werkzeuge, die der MCP-Server nicht anbietet, z. B. rename_symbol oder apply_code_action. Im eingeschränkten Modus (--restricted) sind schreibende Werkzeuge immer aus. |
| `mcp.globalSettings` | Projekt (atlas.json) | boolean | `true` |  | Der MCP-Server liest wie der LSP-Server und der Linter die globale Datei %APPDATA%\Atlas\settings.json (z. B. mcp.disabledTools, Index, Hints). false: nur atlas.json, etwa für reproduzierbare Ergebnisse im Team. |

## format

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `format.indentSize` | Projekt (atlas.json) | integer | `2` | 1…16 | Breite einer Einrückungsebene. |
| `format.useTabs` | Projekt (atlas.json) | boolean | `false` |  | Mit Tabs statt Leerzeichen einrücken. |
| `format.keywordCase` | Projekt (atlas.json) | string | `"preserve"` | `"preserve"`, `"lower"`, `"upper"` | Schreibweise reservierter Wörter. |
| `format.trimTrailingWhitespace` | Projekt (atlas.json) | boolean | `true` |  | Leerzeichen am Zeilenende entfernen. |
| `format.insertFinalNewline` | Projekt (atlas.json) | boolean | `false` |  | Datei mit einem Zeilenende abschließen. |
| `format.spaceAroundAssignment` | Projekt (atlas.json) | boolean | `true` |  | Genau ein Leerzeichen vor und nach :=. |
| `format.spaceAfterComma` | Projekt (atlas.json) | boolean | `true` |  | Genau ein Leerzeichen nach Kommas. |
| `format.endOfLine` | Projekt (atlas.json) | string | – | `"lf"`, `"crlf"` | Zeilenenden vereinheitlichen; ohne Angabe bleiben sie. |
| `format.reindent` | Projekt (atlas.json) | boolean | `true` |  | Zeilen nach der Blockstruktur einrücken (begin/end, try, case, repeat, Abschnitte). Ausgeschaltet bleibt die vorhandene Einrückung und nur Tabs und Leerzeichen werden umgerechnet. |
| `format.beginPlacement` | Projekt (atlas.json) | string | `"preserve"` | `"preserve"`, `"newLine"`, `"sameLine"` | begin nach then, else und do: wie vorhanden, in einer eigenen Zeile oder in derselben Zeile. |
| `format.elsePlacement` | Projekt (atlas.json) | string | `"preserve"` | `"preserve"`, `"newLine"`, `"sameLine"` | else nach end: wie vorhanden, in einer eigenen Zeile oder in derselben Zeile (end else). |
| `format.maxLineLength` | Projekt (atlas.json) | integer | `0` | 0…1000 | Längere Zeilen nach einem Komma oder vor einem Operator umbrechen; 0 = nie. Gesetzt hat es Vorrang vor max_line_length aus .editorconfig. |
| `format.alignAssignments` | Projekt (atlas.json) | boolean | `false` |  | := untereinander stehender Zuweisungen ausrichten. |
| `format.alignDeclarations` | Projekt (atlas.json) | boolean | `false` |  | Doppelpunkte bzw. = untereinander stehender Deklarationen (var, const, Felder, Parameter) ausrichten. |
| `format.alignComments` | Projekt (atlas.json) | boolean | `false` |  | Kommentare am Zeilenende untereinander stehender Zeilen ausrichten. |

## Beispiel

```json
{
  "$schema": "https://raw.githubusercontent.com/xKnockOut/Atlas/main/schemas/atlas.schema.json",
  "project": "App.dproj",
  "config": "Debug",
  "platform": "Win64",
  "rules": { "empty-except": "error" },
  "exclude": ["ThirdParty/**"]
}
```
