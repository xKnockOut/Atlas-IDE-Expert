# Schreiben

Zurück zum [README](../../../README_DE.md)

## Vervollständigung

**Vervollständigung** im eigenen Popup:

- Detailpanel mit eingefärbter Deklaration und Doku
- Filter-Chips, unscharfe Suche, lernende Reihenfolge
- Favoriten (Strg+D)
- Tippfehler-Vorschläge („Meintest du“)
- Vorschau im Editor
- Hinweis `+ Unit` für noch nicht eingebundene Units

### Passend zum Kontext

- Aufzählungswerte zuerst
- Mengenelemente zum Abhaken
- `case` mit allen oder fehlenden Werten
- nur Typen nach `:`
- Typargumente nach Constraints
- Attribute nach `[` ohne Endung `Attribute` (DUnitX und JSON zuerst, Konstruktor im Parameter-Hint, #465)
- Exception-Klassen (#483, `completion.exceptionClasses`):
  - nur Exception-Klassen nach `raise` und `on E:`, übernommen als `EFoo.Create('')` samt `CreateFmt`
  - nach `on E:` zuerst die Klassen, die der `try`-Block auslösen kann (XMLDoc `<exception cref>`, `StrToInt` → `EConvertError`)
  - Warnung, wenn ein früherer Zweig die Klasse schon fängt
- Mitglieder von `with`-Objekten mit „aus qryOrders“ und Warnung, wenn sie `Self.Name` oder einen lokalen Namen verdecken (#481, `completion.withOrigin`)
- Gerüste anonymer Methoden, wo eine Methodenreferenz erwartet wird (#468, `completion.anonymousMethods`):
  - `TTask.Run(` ergibt `procedure begin … end`
  - `TPredicate<TCustomer>` ergibt `function(const Value: TCustomer): Boolean`
- vollständiger `inherited`-Aufruf
- Feld- und Parameternamen in `FieldByName('`
- Komponenten des Formulars
- `Sender` mit passender Typumwandlung
- gleichnamige Symbole aus verschiedenen Units
- Helper-Methoden
- uses-Liste mit Gruppen

### Unvollständiger Code (#457)

- Schränkt ein Syntaxfehler vor dem Cursor in der aktuellen Routine bzw. Klassendeklaration den Kontext ein, meldet eine Warnleiste oben in der Liste „Ergebnisse möglicherweise unvollständig · Syntaxfehler in Zeile n“.
- Klick auf die Zeile springt dorthin.
- Ohne Vorschläge nennt der leere Zustand den Fehler.
- Fehler in anderen Routinen und die Stelle, an der gerade getippt wird, zählen nicht.

Einstellungen: `completion.syntaxNotice`

### Unbekannte Namen

- lokale Variable, Inline-Variable, Feld oder Methode direkt aus der Liste anlegen
- Namensvorschläge aus dem Typ

## Parameter-Hint (#451)

- mit allen Überladungen, aktivem Parameter und Auswahl nach Argumenttypen
- bei `Format` und anderen Formatroutinen:
  - nennt er den Platzhalter zum Argument am Cursor („Platzhalter 2 von 2 erwartet ganzzahlig“)
  - warnt vor überzähligen Argumenten, ungültigen Platzhaltern und Literalen vom falschen Typ
  - färbt jeden Platzhalter und sein Argument im Editor gleich ein
  - eigene Routinen über `formatFunctions` in `.atlas` oder `formatMethods` von `format-args`

Einstellungen: `completion.formatPlaceholders`

## Vorlagen und Befehle

- **Vorlagen:**
  - Code-Vorlagen (`tryf`, `forin`, `prop`, …)
  - eigene `*.atlas-snippet`-Dateien
  - die Live Templates der IDE
  - klassenbewusste Vorlagen (`prop`, `create`, `free`)
  - Postfix-Vorlagen (`Liste.forin`, `Obj.notnil`, `Obj.free`)
- **Schnellbefehle** nach Enter, etwa `/uses Unit`, `/extract`, `/inline`, `/fix`, `/explain`, `/case`, `/helper`, `/test`, `/component`, `/unit`, `/sortuses`, `/cleanuses`
- **Erzeugen-Menü** (Alt+Einfg): Konstruktor, Properties, überschriebene Methoden, Interface-Methoden, Umschließen, Vorlagen
- **Freigabe absichern:** nach `X := TFoo.Create;` ein Angebot für `try … finally X.Free; end;`

## Schreibhilfen im Editor

| Funktion | Tastenkürzel | Issue |
|---|---|---|
| Gleichen Text wie die Markierung hervorheben | | #709 |
| Austrittspunkte einer Routine hervorheben, F3 springt zwischen ihnen | F3 | #698 |
| neu zugewiesene Variablen unterstreichen, mit Anzahl im Hover und wahlweise „Als Konstante deklarieren“ | | #712 |
| Typ des markierten Ausdrucks mit Umwandlungen, gewählter Überladung und Wert konstanter Ausdrücke, erneutes Drücken erweitert | Strg+Umschalt+T | #689 |
| Blockkommentar umschalten | Umschalt+Alt+A | #703 |
| neue Zeile ober- oder unterhalb | Umschalt+Enter, Strg+Alt+Enter | #700 |
| Markierung beim Tippen umschließen | | #672 |
| Umschließung entfernen, mit Vorschau | Strg+Umschalt+Entf | #657 |
| Atlas-Spalte in der Zeilenleiste | | #768 |

- Methodenrümpfe in Deklarationsreihenfolge (#660):
  - neue Rümpfe aus der Klassenvervollständigung wandern im selben Rückgängig-Schritt an ihre Stelle
  - „implementation wie Klasse ordnen“ mit Vorschau
- var-Block pflegen (#644):
  - Variable an ihrer ersten Zuweisung zur Inline-Variablen machen und zurück
  - var-Abschnitt aufräumen (ungenutzte entfernen, nach erster Verwendung oder Namen sortieren, gleiche Typen zusammenfassen)
  - Kommentare wandern mit

## Sprachunterstützung

### Bedingte Kompilierung

- Gliederung, Hover, Gehe zu und Prüfungen sehen nur die aktiven `{$IFDEF}`-Zweige des Projekts.
- Die Gliederung zeigt die Bedingung des Zweigs (#845).
- `{$IF}` versteht `SizeOf`, `High`, `Low`, `RTLVersion111` und `Declared`.
- `{$IFOPT}` folgt den Schaltern der `.dproj` und lokalen `{$R-}`.
- Unbekannte Werte lassen beide Zweige aktiv.
- Der Hover auf einer Bedingung erklärt ihren Wert (#847).

### Defines aus Include-Dateien (#860)

- Ein `{$DEFINE}` aus einer per `{$I}` eingebundenen Datei gilt für Abblenden, Gliederung, Prüfungen und Linter.
- Ein Inlay Hint hinter `{$I}` nennt die Symbole, die die Datei definiert.

### Variante Records und Helfer

- **Variante Records**: Felder wie `TRect.Left` oder `TMessage.WParam` stehen in Vervollständigung, Hover, Gehe zu und Gliederung, mit ihrem Zweig als Marke (#846)
- **Helfer mit Vorfahr**: `class helper (TBaseHelper) for TFoo` wird als Helfer gelesen, und `Foo.` bietet auch die Mitglieder des Vorfahr-Helfers an (#848)

### Seltenere Syntax

Folgendes ergibt keine Syntaxfehler:

- mehrere Einschränkungen je Typparameter
- benannte OLE-Argumente (`Open(FileName := 'a.docx')`)
- Aufrufkonventionen ohne Semikolon, `cdecl varargs`, `assembler asm`
- lokale Routinen in anonymen Methoden
- `{$I datei.inc}` als Wert einer Konstanten
- lange `else if`-Ketten
- Sprungmarken wie `@@End` in `asm`-Blöcken (#861)
- Steuerzeichen wie `^C` und die Klammern `(.` `.)` (#862, mit Inlay Hint für den Code)
- Bezeichner mit `&&` wie Spring4Ds `&&op_Equality` (#1137)
- leere Record-Konstanten `= ()` (#1138)
- `class threadvar`, `class operator In` und `type AnsiString(1252)` (#1140)
- `end align 16`, Attribute im varianten Record-Teil, `IBaz<string>=nil` und `%_0101` (#1142)
- benannte Argumente mit reserviertem Wort wie `Foo(Type := 1)`, Aufrufkonventionen an anonymen Methoden und Attribute an Inline-Variablen (`var [Weak] Obj: IFoo := nil`, #1167)
- sowie Methodenzuordnungen von Funktionen wie `function IFoo.GetX = MyGetX` (#1134)

Außerdem (#849):

- Unter `{$SCOPEDENUMS ON}` brauchen Werte ihr Typpräfix.
- Mitglieder aus `{$I}` in einer Klasse gehören zur Klasse.

## Weitere Schreibhilfen

- **Dokumentationskommentare:** `///` erzeugt das XMLDoc-Gerüst mit Platzhaltern
- **Anweisung vervollständigen** (Strg+Umschalt+Enter)
- **Muster fortsetzen** als Schattentext
- **Kommentare fortsetzen** beim Enter
- **Formatieren** nach eigenen Regeln (Strg+Umschalt+Alt+L), weil RAD Studio 13 keinen Formatierer mehr hat:
  - Bereiche zwischen `// atlas-format: off` und `// atlas-format: on` bleiben unverändert.
  - Derselbe Formatierer läuft ohne IDE (`--format-check`, `--format-write`, MCP `format_code`, siehe [Formatieren ohne IDE](Kommandozeile.md#formatieren-ohne-ide)).
- **Zeilen verschieben und duplizieren** (Alt+↑/↓, Umschalt+Alt+↑/↓)
- **mehrere Einfügemarken** *(experimentell)*
- **Bezeichner live mitziehen** *(experimentell)*
- **Einfügen mit uses-Ergänzung** *(experimentell)*
