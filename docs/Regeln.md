# Prüfregeln

Erzeugt von `Tools/Update-RuleCatalog.ps1` aus dem Regelkatalog. Nicht von Hand ändern.

## Gruppen

| Gruppe | Regeln |
|---|---|
| [Fehler finden](#gruppe-find-bugs) | 37 |
| [Exceptions](#gruppe-exceptions) | 5 |
| [Threads](#gruppe-threads) | 7 |
| [Robustheit und Muster](#gruppe-robustness) | 2 |
| [Performance](#gruppe-performance) | 3 |
| [Sicherheit](#gruppe-security) | 11 |
| [Komponenten](#gruppe-components) | 8 |
| [Formulare und Daten](#gruppe-forms) | 10 |
| [Architektur](#gruppe-architecture) | 3 |
| [Stil und Metriken](#gruppe-style) | 18 |
| [Packages und Tests](#gruppe-packages) | 1 |
| [Atlas intern](#gruppe-internal) | 3 |

<a id="gruppe-find-bugs"></a>
### Fehler finden

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`syntax`](#syntax) | Syntaxfehler | Bug | Fehler |
| [`result-not-set`](#result-not-set) | Funktionsergebnis eventuell nicht gesetzt | Bug | Warnung |
| [`possibly-uninitialized`](#possibly-uninitialized) | Variable eventuell nicht initialisiert | Bug | Warnung |
| [`unreachable-code`](#unreachable-code) | Unerreichbarer Code | Bug | Warnung |
| [`declared-not-implemented`](#declared-not-implemented) | Deklariert, aber nicht implementiert | Bug | Fehler |
| [`implemented-not-declared`](#implemented-not-declared) | Implementiert, aber nicht deklariert | Bug | Fehler |
| [`destroy-without-override`](#destroy-without-override) | Destroy ohne override | Bug | Warnung |
| [`setter-recursion`](#setter-recursion) | Setter oder Getter ruft sich selbst auf | Bug | Fehler |
| [`hides-virtual`](#hides-virtual) | Methode verdeckt virtuelle Methode | Bug | Warnung |
| [`virtual-instead-of-override`](#virtual-instead-of-override) | virtual statt override | Bug | Warnung |
| [`captured-loop-variable`](#captured-loop-variable) | Erfasste Schleifenvariable | Bug | Warnung |
| [`interface-guid`](#interface-guid) | Interface ohne GUID | Bug | Warnung |
| [`duplicate-interface-guid`](#duplicate-interface-guid) | Zwei Interfaces mit derselben GUID | Bug | Fehler |
| [`self-assignment`](#self-assignment) | Zuweisung an sich selbst | Bug | Warnung |
| [`for-high-to-low`](#for-high-to-low) | for-Schleife zählt mit to abwärts | Bug | Warnung |
| [`exception-not-raised`](#exception-not-raised) | Exception erzeugt, aber nicht ausgelöst | Bug | Warnung |
| [`assert-side-effect`](#assert-side-effect) | Assert mit Seiteneffekt | Bug | Warnung |
| [`ifthen-side-effect`](#ifthen-side-effect) | IfThen wertet beide Zweige aus | Bug | Warnung |
| [`int32-mul-overflow`](#int32-mul-overflow) | Int32-Multiplikation an Int64 zugewiesen | Bug | Warnung |
| [`sizeof-pointer`](#sizeof-pointer) | SizeOf eines Zeigers in Move oder FillChar | Bug | Fehler |
| [`char-to-pchar`](#char-to-pchar) | Char nach PChar umgewandelt | Bug | Fehler |
| [`float-equality`](#float-equality) | Gleitkommavergleich mit = oder <> | Bug | Hinweis |
| [`constructor-on-instance`](#constructor-on-instance) | Konstruktor auf einer Instanz aufgerufen | Bug | Warnung |
| [`unresolved-identifier`](#unresolved-identifier) | Nicht deklarierter Bezeichner | Bug | Warnung |
| [`type-used-before-declaration`](#type-used-before-declaration) | Typ vor seiner Deklaration benutzt | Bug | Fehler |
| [`field-not-freed`](#field-not-freed) | Feld erzeugt, aber nie freigegeben | Bug | Warnung |
| [`owned-field-free-unclear`](#owned-field-free-unclear) | Unklar, ob ein erzeugtes Feld freigegeben werden muss | Bug | Hinweis |
| [`operator-precedence`](#operator-precedence) | Vorrang von not übersehen | Bug | Warnung |
| [`empty-statement`](#empty-statement) | Leere Anweisung nach then, do oder else | Bug | Warnung |
| [`loop-off-by-one`](#loop-off-by-one) | Schleife läuft einen Schritt zu weit | Bug | Warnung |
| [`collection-modified-in-loop`](#collection-modified-in-loop) | Liste in der eigenen Schleife verändert | Bug | Warnung |
| [`use-after-free`](#use-after-free) | Objekt nach Free weiter benutzt | Bug | Fehler |
| [`deref-before-nil-check`](#deref-before-nil-check) | Erst benutzt, dann auf nil geprüft | Bug | Warnung |
| [`field-free-without-nil`](#field-free-without-nil) | Feld freigegeben, Verweis bleibt stehen | Bug | Warnung |
| [`missing-inherited`](#missing-inherited) | Konstruktor oder Destruktor ohne inherited | Bug | Warnung |
| [`destroy-called-directly`](#destroy-called-directly) | Destroy statt Free aufgerufen | Bug | Warnung |
| [`managed-type-raw-memory`](#managed-type-raw-memory) | FillChar, Move oder GetMem auf verwaltete Typen | Bug | Fehler |

<a id="gruppe-exceptions"></a>
### Exceptions

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`empty-except`](#empty-except) | Leerer except-Block | Code Smell | Warnung |
| [`generic-exception-raised`](#generic-exception-raised) | Allgemeine Exception ausgelöst | Code Smell | Hinweis |
| [`catch-all-without-raise`](#catch-all-without-raise) | Exception-Handler ohne erneutes raise | Code Smell | Warnung |
| [`exception-freed`](#exception-freed) | Exception-Objekt manuell freigegeben | Bug | Fehler |
| [`raise-in-finally`](#raise-in-finally) | raise in einem finally-Block | Bug | Warnung |

<a id="gruppe-threads"></a>
### Threads

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`thread-vcl-access`](#thread-vcl-access) | VCL-Zugriff aus einem Thread | Bug | Warnung |
| [`lock-without-finally`](#lock-without-finally) | Sperre ohne try/finally | Bug | Warnung |
| [`thread-use-after-free-on-terminate`](#thread-use-after-free-on-terminate) | Thread nach dem Start mit FreeOnTerminate benutzt | Bug | Warnung |
| [`thread-free-with-free-on-terminate`](#thread-free-with-free-on-terminate) | Free auf einem Thread mit FreeOnTerminate | Bug | Fehler |
| [`synchronize-in-destructor`](#synchronize-in-destructor) | Synchronize im Destruktor eines Threads | Bug | Warnung |
| [`thread-resume-suspend`](#thread-resume-suspend) | Veraltetes TThread.Resume/Suspend | Code Smell | Warnung |
| [`threadvar-managed`](#threadvar-managed) | threadvar mit verwaltetem Typ | Bug | Warnung |

<a id="gruppe-robustness"></a>
### Robustheit und Muster

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`random-without-randomize`](#random-without-randomize) | Random ohne Randomize | Code Smell | Hinweis |
| [`format-without-settings`](#format-without-settings) | Formatierung abhängig vom Gebietsschema | Code Smell | Hinweis |

<a id="gruppe-performance"></a>
### Performance

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`string-concat-in-loop`](#string-concat-in-loop) | String-Verkettung in einer Schleife | Code Smell | Hinweis |
| [`loop-invariant-call`](#loop-invariant-call) | Teurer Aufruf in der Schleifenbedingung | Code Smell | Hinweis |
| [`missing-begin-update`](#missing-begin-update) | Hinzufügen in einer Schleife ohne BeginUpdate | Code Smell | Hinweis |

<a id="gruppe-security"></a>
### Sicherheit

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`bidi-control`](#bidi-control) | Bidirektionales Steuerzeichen | Schwachstelle | Fehler |
| [`invisible-char`](#invisible-char) | Unsichtbares Zeichen | Sicherheits-Hotspot | Warnung |
| [`control-char`](#control-char) | Steuerzeichen | Bug | Fehler |
| [`confusable-identifier`](#confusable-identifier) | Verwechselbarer Bezeichner | Sicherheits-Hotspot | Warnung |
| [`security-command-injection`](#security-command-injection) | Befehlsinjektion | Schwachstelle | Warnung |
| [`security-path-traversal`](#security-path-traversal) | Pfad-Traversal | Schwachstelle | Warnung |
| [`security-weak-crypto`](#security-weak-crypto) | Schwache Kryptografie | Sicherheits-Hotspot | Hinweis |
| [`security-tls-verification-disabled`](#security-tls-verification-disabled) | TLS-Zertifikatsprüfung abgeschaltet | Schwachstelle | Warnung |
| [`security-insecure-http`](#security-insecure-http) | Unverschlüsselte http://-URL | Sicherheits-Hotspot | Hinweis |
| [`security-insecure-random`](#security-insecure-random) | Random für sicherheitsrelevante Werte | Sicherheits-Hotspot | Warnung |
| [`security-sql-injection`](#security-sql-injection) | SQL-Text aus zusammengesetzten Werten (SQL-Injection) | Schwachstelle | Warnung |

<a id="gruppe-components"></a>
### Komponenten

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`component-create-without-override`](#component-create-without-override) | Komponentenkonstruktor ohne override | Bug | Warnung |
| [`component-missing-inherited`](#component-missing-inherited) | Komponentenmethode ohne inherited | Bug | Warnung |
| [`component-default-mismatch`](#component-default-mismatch) | default passt nicht zum Konstruktor | Bug | Warnung |
| [`component-missing-free-notification`](#component-missing-free-notification) | Komponentenreferenz ohne FreeNotification | Bug | Warnung |
| [`component-setter-without-invalidate`](#component-setter-without-invalidate) | Setter ohne Invalidate | Code Smell | Hinweis |
| [`component-fixed-pixels`](#component-fixed-pixels) | Feste Pixelwerte | Code Smell | Warnung |
| [`component-hardcoded-color`](#component-hardcoded-color) | Feste Farbe in Paint | Code Smell | Hinweis |
| [`component-palette-icon`](#component-palette-icon) | Registrierte Komponente ohne Palettensymbol | Code Smell | Hinweis |

<a id="gruppe-forms"></a>
### Formulare und Daten

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`form-field-without-object`](#form-field-without-object) | Formularfeld ohne Objekt | Bug | Warnung |
| [`form-object-without-field`](#form-object-without-field) | Formularobjekt ohne Feld | Bug | Warnung |
| [`form-field-type-mismatch`](#form-field-type-mismatch) | Feldtyp weicht vom Formularobjekt ab | Bug | Warnung |
| [`dfm-circular-datasource`](#dfm-circular-datasource) | Zirkuläre Master-Detail- bzw. DataSource-Verknüpfung | Bug | Warnung |
| [`dfm-master-without-fields`](#dfm-master-without-fields) | Master-Detail ohne MasterFields | Bug | Warnung |
| [`dfm-required-field-without-control`](#dfm-required-field-without-control) | Pflichtfeld ohne sichtbares Eingabe-Control | Bug | Warnung |
| [`dfm-control-field-type-mismatch`](#dfm-control-field-type-mismatch) | Datensensitives Control passt nicht zum Feldtyp | Bug | Warnung |
| [`dfm-duplicate-binding`](#dfm-duplicate-binding) | Zwei Controls an demselben Feld | Bug | Warnung |
| [`dfm-property`](#dfm-property) | Komponenten-Property verletzt eine Eigenschaftsregel | Code Smell | Warnung |
| [`foreign-form-control-access`](#foreign-form-control-access) | Zugriff auf Controls eines anderen Formulars | Code Smell | Warnung |

<a id="gruppe-architecture"></a>
### Architektur

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`forbidden-uses`](#forbidden-uses) | Verbotene uses-Beziehung | Code Smell | Fehler |
| [`architecture-role-import`](#architecture-role-import) | Import verletzt die Rollenmatrix | Code Smell | Warnung |
| [`architecture-contract-content`](#architecture-contract-content) | Klasse in einer Contract-Unit | Code Smell | Warnung |

<a id="gruppe-style"></a>
### Stil und Metriken

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`unused-local`](#unused-local) | Ungenutzte lokale Variable | Code Smell | Hinweis |
| [`unused-parameter`](#unused-parameter) | Ungenutzter Parameter | Code Smell | Hinweis |
| [`unused-assignment`](#unused-assignment) | Zugewiesener Wert ungenutzt | Code Smell | Hinweis |
| [`file-header`](#file-header) | Dateikopf fehlt oder weicht ab | Code Smell | Hinweis |
| [`hardcoded-string`](#hardcoded-string) | Text im Code statt resourcestring | Code Smell | Hinweis |
| [`bool-compare`](#bool-compare) | Vergleich mit True oder False | Code Smell | Hinweis |
| [`redundant-assigned-free`](#redundant-assigned-free) | Assigned-Prüfung vor Free | Code Smell | Hinweis |
| [`redundant-parens`](#redundant-parens) | Überflüssige Klammern | Code Smell | Hinweis |
| [`redundant-begin-end`](#redundant-begin-end) | begin … end um eine einzelne Anweisung | Code Smell | Hinweis |
| [`with-statement`](#with-statement) | with-Anweisung | Code Smell | Hinweis |
| [`metric-method-length`](#metric-method-length) | Methode zu lang | Code Smell | Hinweis |
| [`metric-nesting-depth`](#metric-nesting-depth) | Zu tief verschachtelt | Code Smell | Hinweis |
| [`metric-cyclomatic-complexity`](#metric-cyclomatic-complexity) | Zyklomatische Komplexität zu hoch | Code Smell | Hinweis |
| [`metric-cognitive-complexity`](#metric-cognitive-complexity) | Kognitive Komplexität zu hoch | Code Smell | Hinweis |
| [`metric-parameter-count`](#metric-parameter-count) | Zu viele Parameter | Code Smell | Hinweis |
| [`todo-comment`](#todo-comment) | Offener TODO-Kommentar | Code Smell | Hinweis |
| [`deprecated-symbol`](#deprecated-symbol) | Veraltetes Symbol | Code Smell | Hinweis |
| [`unneeded-forward-declaration`](#unneeded-forward-declaration) | Überflüssige Forward-Deklaration | Code Smell | Hinweis |

<a id="gruppe-packages"></a>
### Packages und Tests

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`implicit-package-import`](#implicit-package-import) | Implizit eingebundene Unit | Code Smell | Warnung |

<a id="gruppe-internal"></a>
### Atlas intern

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`unused-suppression`](#unused-suppression) | Ungenutzte Unterdrückung | Code Smell | Hinweis |
| [`unknown-rule-id`](#unknown-rule-id) | Unbekannte Regelkennung | Code Smell | Hinweis |
| [`slash-command`](#slash-command) | Schnellbefehl nicht ausgeführt | Code Smell | Hinweis |

## Regeln

<a id="syntax"></a>
### syntax

**Syntaxfehler** · Bug · Fehler · Gruppe Fehler finden

Der Parser konnte den Quelltext nicht lesen.

Mit Treffer:

```pascal
procedure Foo;
begin
  if X then
end;
```

Richtig:

```pascal
procedure Foo;
begin
  if X then
    Bar;
end;
```

<a id="unused-suppression"></a>
### unused-suppression

**Ungenutzte Unterdrückung** · Code Smell · Hinweis · Gruppe Atlas intern

Ein lsp-ignore-Kommentar unterdrückt keinen Treffer und kann entfernt werden.

Mit Treffer:

```pascal
// lsp-ignore: empty-except
X := 1;
```

Richtig:

```pascal
X := 1;
```

<a id="unknown-rule-id"></a>
### unknown-rule-id

**Unbekannte Regelkennung** · Code Smell · Hinweis · Gruppe Atlas intern

Ein lsp-ignore-Kommentar nennt eine Regelkennung, die es nicht gibt, und unterdrückt deshalb nichts. Die Meldung schlägt die ähnlichste bekannte Kennung vor (Tippfehler); ein solcher Kommentar zählt nicht zusätzlich als unused-suppression.

Mit Treffer:

```pascal
// lsp-ignore: empty-exept
try X; except end;
```

Richtig:

```pascal
// lsp-ignore: empty-except
try X; except end;
```

<a id="bidi-control"></a>
### bidi-control

**Bidirektionales Steuerzeichen** · Schwachstelle · Fehler · Gruppe Sicherheit

Bidirektionale Steuerzeichen können Code anders anzeigen, als er kompiliert wird (Trojan Source); auch in Formulardateien. Richtungsmarken in RTL-Text nur mit niedriger Konfidenz.

Mit Treffer:

```pascal
if IsAdmin then { U+202E } begin
```

Richtig:

```pascal
if IsAdmin then begin
```

<a id="invisible-char"></a>
### invisible-char

**Unsichtbares Zeichen** · Sicherheits-Hotspot · Warnung · Gruppe Sicherheit

Unsichtbare oder Nullbreiten-Zeichen im Quelltext und in Formulardateien; in Strings und Kommentaren mittlere Konfidenz.

Mit Treffer:

```pascal
Count{U+200B} := 0;
```

Richtig:

```pascal
Count := 0;
```

<a id="control-char"></a>
### control-char

**Steuerzeichen** · Bug · Fehler · Gruppe Sicherheit

NUL- und Steuerzeichen oder ungültige UTF-8-Bytes im Quelltext und in der Formulardatei; ungültige Bytes mit genauer Zeile und Spalte.

Mit Treffer:

```pascal
S := 'abc{U+0000}';
```

Richtig:

```pascal
S := 'abc' + #0;
```

<a id="confusable-identifier"></a>
### confusable-identifier

**Verwechselbarer Bezeichner** · Sicherheits-Hotspot · Warnung · Gruppe Sicherheit

Bezeichner mit Zeichen aus mehreren Schriften oder Nicht-ASCII-Zeichen sind mit anderen verwechselbar.

Mit Treffer:

```pascal
var Pаssword: string; { Cyrillic 'а' }
```

Richtig:

```pascal
var Password: string;
```

<a id="forbidden-uses"></a>
### forbidden-uses

**Verbotene uses-Beziehung** · Code Smell · Fehler · Gruppe Architektur

Ein uses-Eintrag verletzt eine Schichtregel unter "layers" in atlas.json, z. B. darf *.Common.* nicht Vcl.* verwenden.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `layers` | json | `[]` | Schichtregeln: [{"from": Glob, "deny": [Globs], "allow": [Globs]}]. |

Mit Treffer:

```pascal
unit App.Common.Model;
interface
uses Vcl.Forms;
```

Richtig:

```pascal
unit App.Common.Model;
interface
uses System.Classes;
```

<a id="architecture-role-import"></a>
### architecture-role-import

**Import verletzt die Rollenmatrix** · Code Smell · Warnung · Gruppe Architektur

Ein uses-Eintrag verletzt die Importmatrix des Rollenkonzepts (Ausgabeartefakt, Feature, Rolle: Contract, Internals, Providers, Adapters, Composition, Hosting). Standardmäßig aus; in atlas.json mit der Option "prefixes" einschalten. Genehmigte Ausnahmen stehen unter "allow" als "Quelle -> Ziel"-Globs.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `prefixes` | string-list | `[]` | Präfixe der Ausgabeartefakte, z. B. "Atlas.Common"; ohne Angabe meldet die Regel nichts. |
| `hostRoles` | string-list | `["Foundation","Core","Shell","Adapters","Platform"]` | Erste Namenssegmente der Host-Units ohne Präfix. |
| `allow` | string-list | `[]` | Genehmigte Ausnahmen "Quelle -> Ziel" (beide Globs). |

Mit Treffer:

```pascal
unit Atlas.Common.Logging.Contract;
interface
uses Atlas.Common.Logging.Providers.Logger;
```

Richtig:

```pascal
unit Atlas.Common.Logging.Contract;
interface
uses System.SysUtils;
```

<a id="architecture-contract-content"></a>
### architecture-contract-content

**Klasse in einer Contract-Unit** · Code Smell · Warnung · Gruppe Architektur

Eine Contract-Unit deklariert im interface eine Klasse. Contracts enthalten nur Records, Interfaces, Aufzählungen und Ausnahmen. Standardmäßig aus; in atlas.json mit der Option "prefixes" einschalten. Genehmigte Ausnahmen stehen unter "allow" als "Unit.Typ"-Globs.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `prefixes` | string-list | `[]` | Präfixe der Ausgabeartefakte, z. B. "Atlas.Common". |
| `allow` | string-list | `[]` | Genehmigte Ausnahmen "Unit.Typ" als Glob. |

Mit Treffer:

```pascal
unit App.Orders.Contract;
interface
type
  TOrderList = class
  end;
```

Richtig:

```pascal
unit App.Orders.Contract;
interface
type
  IOrderList = interface
  end;
```

<a id="thread-vcl-access"></a>
### thread-vcl-access

**VCL-Zugriff aus einem Thread** · Bug · Warnung · Gruppe Threads

TThread.Execute, TThread.CreateAnonymousThread oder TTask greift außerhalb von Synchronize oder Queue auf die VCL zu (Application, Screen, ShowMessage, MessageDlg …). Die VCL ist nicht threadsicher.

Mit Treffer:

```pascal
procedure TWorker.Execute;
begin
  Application.Title := 'Done';
end;
```

Richtig:

```pascal
procedure TWorker.Execute;
begin
  TThread.Queue(nil, procedure begin Application.Title := 'Done' end);
end;
```

<a id="lock-without-finally"></a>
### lock-without-finally

**Sperre ohne try/finally** · Bug · Warnung · Gruppe Threads

Auf eine Sperre (TCriticalSection.Enter/Acquire, TMonitor.Enter, BeginRead/BeginWrite, TSpinLock.Enter, TMutex.Acquire, EnterCriticalSection oder ein Paar aus der Option lockPairs) folgt kein try/finally mit der Freigabe. Eine Ausnahme lässt die Sperre gesetzt.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `lockPairs` | json | `[]` | Weitere Sperrpaare als [["Sperren", "Freigeben"]]. |

Mit Treffer:

```pascal
CS.Enter;
DoWork;
CS.Leave;
```

Richtig:

```pascal
CS.Enter;
try
  DoWork;
finally
  CS.Leave;
end;
```

<a id="thread-use-after-free-on-terminate"></a>
### thread-use-after-free-on-terminate

**Thread nach dem Start mit FreeOnTerminate benutzt** · Bug · Warnung · Gruppe Threads

Ein Thread mit FreeOnTerminate := True kann sich gleich nach dem Start selbst freigeben; danach greift die Variable womöglich auf ein freigegebenes Objekt zu.

Mit Treffer:

```pascal
T.FreeOnTerminate := True;
T.Start;
Log(T.ThreadID);
```

Richtig:

```pascal
Log(T.ThreadID);
T.FreeOnTerminate := True;
T.Start;
```

<a id="thread-free-with-free-on-terminate"></a>
### thread-free-with-free-on-terminate

**Free auf einem Thread mit FreeOnTerminate** · Bug · Fehler · Gruppe Threads

Free auf einem Thread mit FreeOnTerminate := True gibt ihn doppelt frei.

Mit Treffer:

```pascal
T.FreeOnTerminate := True;
T.Start;
T.Free;
```

Richtig:

```pascal
T.FreeOnTerminate := True;
T.Start;
```

<a id="synchronize-in-destructor"></a>
### synchronize-in-destructor

**Synchronize im Destruktor eines Threads** · Bug · Warnung · Gruppe Threads

Synchronize im Destruktor eines TThread-Nachfahren (oder in einer Methode, die er aufruft) verklemmt sich: Der Hauptthread wartet in WaitFor, der Thread auf Synchronize.

Mit Treffer:

```pascal
destructor TWorker.Destroy;
begin
  Synchronize(Notify);
  inherited;
end;
```

Richtig:

```pascal
destructor TWorker.Destroy;
begin
  inherited;
end;
```

<a id="thread-resume-suspend"></a>
### thread-resume-suspend

**Veraltetes TThread.Resume/Suspend** · Code Smell · Warnung · Gruppe Threads

TThread.Resume und Suspend sind veraltet. Einen erzeugten Thread mit Start starten; Suspend hat keinen sicheren Ersatz, stattdessen mit einem Ereignis warten.

Mit Treffer:

```pascal
FWorker.Resume;
```

Richtig:

```pascal
FWorker.Start;
```

<a id="result-not-set"></a>
### result-not-set

**Funktionsergebnis eventuell nicht gesetzt** · Bug · Warnung · Gruppe Fehler finden

Ein Pfad durch die Funktion endet, ohne Result zuzuweisen. Der Aufrufer liest dann einen undefinierten Wert.

Mit Treffer:

```pascal
function Find: Integer;
begin
  if Ok then
    Result := 1;
end;
```

Richtig:

```pascal
function Find: Integer;
begin
  Result := 0;
  if Ok then
    Result := 1;
end;
```

<a id="possibly-uninitialized"></a>
### possibly-uninitialized

**Variable eventuell nicht initialisiert** · Bug · Warnung · Gruppe Fehler finden

Eine lokale Variable wird auf einem Pfad gelesen, auf dem ihr nie ein Wert zugewiesen wurde.

Mit Treffer:

```pascal
var I: Integer;
begin
  if Ok then
    I := 1;
  Writeln(I);
end;
```

Richtig:

```pascal
var I: Integer;
begin
  I := 0;
  if Ok then
    I := 1;
  Writeln(I);
end;
```

<a id="unreachable-code"></a>
### unreachable-code

**Unerreichbarer Code** · Bug · Warnung · Gruppe Fehler finden

Eine Anweisung nach Exit, raise, Abort, Halt, Break, Continue oder goto wird nie ausgeführt. Meist ein Rest oder ein falsch gesetzter Sprung. Gemeldet wird nur die erste Anweisung eines unerreichbaren Abschnitts.

Mit Treffer:

```pascal
procedure Save;
begin
  Exit;
  Store;
end;
```

Richtig:

```pascal
procedure Save;
begin
  if not Ready then
    Exit;
  Store;
end;
```

<a id="unused-local"></a>
### unused-local

**Ungenutzte lokale Variable** · Code Smell · Hinweis · Gruppe Stil und Metriken

Eine lokale Variable ist deklariert, wird aber nie verwendet. Wie Compilerhinweis H2164, aber schon beim Tippen.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `ignore` | string-list | `[]` | Namensmuster, die nie gemeldet werden (* und ?). |

Mit Treffer:

```pascal
procedure Foo;
var
  I, Count: Integer;
begin
  I := 1;
  Bar(I);
end;
```

Richtig:

```pascal
procedure Foo;
var
  I: Integer;
begin
  I := 1;
  Bar(I);
end;
```

<a id="unused-parameter"></a>
### unused-parameter

**Ungenutzter Parameter** · Code Smell · Hinweis · Gruppe Stil und Metriken

Ein Parameter wird im Rumpf der Routine nicht verwendet. Ausgenommen sind überschriebene und virtuelle Methoden, Ereignis-Handler, published-Methoden, Interface-Implementierungen und Callbacks.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `ignore` | string-list | `[]` | Namensmuster, die nie gemeldet werden (* und ?). |

Mit Treffer:

```pascal
function Twice(A, B: Integer): Integer;
begin
  Result := 2 * A;
end;
```

Richtig:

```pascal
function Twice(A: Integer): Integer;
begin
  Result := 2 * A;
end;
```

<a id="unused-assignment"></a>
### unused-assignment

**Zugewiesener Wert ungenutzt** · Code Smell · Hinweis · Gruppe Stil und Metriken

Ein einer lokalen Variable zugewiesener Wert wird überschrieben oder die Routine endet, bevor er gelesen wird. Wie Compilerhinweis H2077.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `ignore` | string-list | `[]` | Namensmuster, die nie gemeldet werden (* und ?). |

Mit Treffer:

```pascal
procedure Foo;
var
  I: Integer;
begin
  I := 0;
  I := Calc;
  Bar(I);
end;
```

Richtig:

```pascal
procedure Foo;
var
  I: Integer;
begin
  I := Calc;
  Bar(I);
end;
```

<a id="declared-not-implemented"></a>
### declared-not-implemented

**Deklariert, aber nicht implementiert** · Bug · Fehler · Gruppe Fehler finden

Eine Methode ist in einer Klasse, einem Record oder Objekt deklariert, hat aber keinen Rumpf im implementation-Abschnitt. Der Compiler meldet das erst beim Kompilieren (E2065).

Mit Treffer:

```pascal
type
  TFoo = class
    procedure Run;
  end;

implementation

end.
```

Richtig:

```pascal
type
  TFoo = class
    procedure Run;
  end;

implementation

procedure TFoo.Run;
begin
end;

end.
```

<a id="implemented-not-declared"></a>
### implemented-not-declared

**Implementiert, aber nicht deklariert** · Bug · Fehler · Gruppe Fehler finden

Ein Methodenrumpf TFoo.Bar hat keine passende Deklaration im Typ.

Mit Treffer:

```pascal
type
  TFoo = class
  end;

implementation

procedure TFoo.Run;
begin
end;
```

Richtig:

```pascal
type
  TFoo = class
  private
    procedure Run;
  end;

implementation

procedure TFoo.Run;
begin
end;
```

<a id="destroy-without-override"></a>
### destroy-without-override

**Destroy ohne override** · Bug · Warnung · Gruppe Fehler finden

Ein destructor Destroy ist ohne override deklariert. Free ruft TObject.Destroy auf, dieser Destruktor läuft also nie.

Mit Treffer:

```pascal
type
  TFoo = class
    destructor Destroy;
  end;
```

Richtig:

```pascal
type
  TFoo = class
    destructor Destroy; override;
  end;
```

<a id="setter-recursion"></a>
### setter-recursion

**Setter oder Getter ruft sich selbst auf** · Bug · Fehler · Gruppe Fehler finden

Ein Setter weist an die eigene Property zu (Name := Value in SetName) oder ein Getter liest sie (Result := Name in GetName). Das ergibt eine Endlosrekursion und einen Stapelüberlauf zur Laufzeit; der Compiler schweigt. Schnellkorrektur: das Feld verwenden (das Feld aus der Property-Deklaration, sonst F und der Name, wenn die Klasse es hat). Früher recursive-property-accessor; Einstellungen und Unterdrückungen mit der alten Kennung wirken weiter.

Mit Treffer:

```pascal
procedure TKunde.SetName(const Value: string);
begin
  if Name <> Value then
    Name := Value;
end;
```

Richtig:

```pascal
procedure TKunde.SetName(const Value: string);
begin
  if FName <> Value then
    FName := Value;
end;
```

<a id="component-create-without-override"></a>
### component-create-without-override

**Komponentenkonstruktor ohne override** · Bug · Warnung · Gruppe Komponenten

Ein TComponent-Nachfahre deklariert constructor Create(AOwner: TComponent) ohne override. Beim Laden aus der Formulardatei wird der virtuelle Konstruktor benutzt und dieser übergangen.

Mit Treffer:

```pascal
type
  TMyPanel = class(TCustomPanel)
    constructor Create(AOwner: TComponent);
  end;
```

Richtig:

```pascal
type
  TMyPanel = class(TCustomPanel)
    constructor Create(AOwner: TComponent); override;
  end;
```

<a id="hides-virtual"></a>
### hides-virtual

**Methode verdeckt virtuelle Methode** · Bug · Warnung · Gruppe Fehler finden

Eine Methode heißt wie eine virtuelle Methode eines Vorfahren, überschreibt sie aber weder noch führt sie sie neu ein (Compilerwarnung W1010).

Mit Treffer:

```pascal
type
  TBase = class
    procedure Run; virtual;
  end;
  TFoo = class(TBase)
    procedure Run;
  end;
```

Richtig:

```pascal
type
  TBase = class
    procedure Run; virtual;
  end;
  TFoo = class(TBase)
    procedure Run; override;
  end;
```

<a id="virtual-instead-of-override"></a>
### virtual-instead-of-override

**virtual statt override** · Bug · Warnung · Gruppe Fehler finden

Ein Nachfahre deklariert eine Methode als virtual, obwohl der Vorfahr schon eine virtuelle Methode mit derselben Signatur hat; das beginnt eine neue Kette statt zu überschreiben.

Mit Treffer:

```pascal
type
  TFoo = class(TBase)
    procedure Run; virtual;
  end;
```

Richtig:

```pascal
type
  TFoo = class(TBase)
    procedure Run; override;
  end;
```

<a id="captured-loop-variable"></a>
### captured-loop-variable

**Erfasste Schleifenvariable** · Bug · Warnung · Gruppe Fehler finden

Eine anonyme Methode, die an eine verzögert ausführende API (TThread.Queue, TTask.Run …) geht, erfasst eine Variable, die sich vor dem Aufruf noch ändert, etwa die Variable einer for-in-Schleife. Delphi erfasst die Variable, nicht ihren Wert.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `deferredApis` | string-list | `[]` | Weitere verzögerte APIs (zusätzlich zu TThread.Queue, TTask.Run u. a.). |

Mit Treffer:

```pascal
for S in List do
  TThread.Queue(nil, procedure begin Memo1.Lines.Add(S); end);
```

Richtig:

```pascal
function CaptureS(const AValue: string): TProc;
begin
  Result := procedure begin Memo1.Lines.Add(AValue); end;
end;
...
for S in List do
  TThread.Queue(nil, CaptureS(S));
```

<a id="component-missing-inherited"></a>
### component-missing-inherited

**Komponentenmethode ohne inherited** · Bug · Warnung · Gruppe Komponenten

Ein überschriebenes Loaded, CreateParams, CreateWnd, Notification, SetParent, Destroy oder Paint einer Komponente ruft inherited nicht auf; die VCL überspringt dann ihre eigene Arbeit. Bei Paint ist die Konfidenz niedrig, weil TCustomControl.Paint nur den Rahmen im Designer zeichnet.

Mit Treffer:

```pascal
procedure TMyControl.Loaded;
begin
  UpdateLayout;
end;
```

Richtig:

```pascal
procedure TMyControl.Loaded;
begin
  inherited;
  UpdateLayout;
end;
```

<a id="component-default-mismatch"></a>
### component-default-mismatch

**default passt nicht zum Konstruktor** · Bug · Warnung · Gruppe Komponenten

Eine Eigenschaft gibt einen default-Wert an, der Konstruktor setzt das Feld aber auf ein anderes Literal. Werte gleich default speichert die DFM nicht, deshalb wird die Eigenschaft falsch geladen.

Mit Treffer:

```pascal
property Size: Integer read FSize write FSize default 5;
...
FSize := 10;
```

Richtig:

```pascal
property Size: Integer read FSize write FSize default 10;
...
FSize := 10;
```

<a id="component-missing-free-notification"></a>
### component-missing-free-notification

**Komponentenreferenz ohne FreeNotification** · Bug · Warnung · Gruppe Komponenten

Eine Eigenschaft verweist auf eine andere Komponente, ihr Setter ruft aber FreeNotification nicht auf. Wird die andere Komponente freigegeben, bleibt ein ungültiger Zeiger zurück. Im Konstruktor erzeugte Unterkomponenten sind ausgenommen.

Mit Treffer:

```pascal
procedure TMyControl.SetLink(const Value: TControl);
begin
  FLink := Value;
end;
```

Richtig:

```pascal
procedure TMyControl.SetLink(const Value: TControl);
begin
  FLink := Value;
  if Value <> nil then Value.FreeNotification(Self);
end;
```

<a id="component-setter-without-invalidate"></a>
### component-setter-without-invalidate

**Setter ohne Invalidate** · Code Smell · Hinweis · Gruppe Komponenten

Ein Setter ändert ein Feld, das Paint liest, ruft aber weder Invalidate noch Repaint, Refresh oder Changed auf. Das Steuerelement zeigt weiter den alten Zustand.

Mit Treffer:

```pascal
procedure TMyControl.SetColor(const Value: TColor);
begin
  FColor := Value;
end;
```

Richtig:

```pascal
procedure TMyControl.SetColor(const Value: TColor);
begin
  FColor := Value;
  Invalidate;
end;
```

<a id="component-fixed-pixels"></a>
### component-fixed-pixels

**Feste Pixelwerte** · Code Smell · Warnung · Gruppe Komponenten

Paint oder Resize verwenden feste Pixelwerte, die über 96 dpi zu klein sind. Werte über ScaleValue oder MulDiv, 0, 1 und -1 sowie Faktoren von Multiplikationen und Divisionen werden nicht gemeldet.

Mit Treffer:

```pascal
Canvas.FillRect(Rect(0, 0, 16, 16));
```

Richtig:

```pascal
Canvas.FillRect(Rect(0, 0, ScaleValue(16), ScaleValue(16)));
```

<a id="component-hardcoded-color"></a>
### component-hardcoded-color

**Feste Farbe in Paint** · Code Smell · Hinweis · Gruppe Komponenten

Paint verwendet ein RGB-Literal, eine $00BBGGRR-Konstante oder einen TColor-Cast. Solche Farben ignorieren VCL-Styles; Systemfarben wie clBtnFace sind in Ordnung.

Mit Treffer:

```pascal
Canvas.Brush.Color := $00FF8000;
```

Richtig:

```pascal
Canvas.Brush.Color := StyleServices.GetSystemColor(clHighlight);
```

<a id="form-field-without-object"></a>
### form-field-without-object

**Formularfeld ohne Objekt** · Bug · Warnung · Gruppe Formulare und Daten

Ein published-Komponentenfeld der Formularklasse hat kein Objekt in der .dfm/.fmx neben der Unit. Nach dem Laden bleibt das Feld nil. Felder außerhalb von published werden nicht geprüft.

Mit Treffer:

```pascal
Edit1: TEdit;  // object Edit1 was deleted from the form
```

Richtig:

```pascal
// remove the field or restore the object
```

<a id="form-object-without-field"></a>
### form-object-without-field

**Formularobjekt ohne Feld** · Bug · Warnung · Gruppe Formulare und Daten

Ein Objekt der Formulardatei hat kein Feld in der Formularklasse. Geerbte Objekte, Objekte in inline-Frames, namenlose Komponenten und Collection-Einträge werden übergangen. Die Korrektur ergänzt das Feld.

Mit Treffer:

```pascal
object Button2: TButton  // no Button2 in TForm1
```

Richtig:

```pascal
Button2: TButton;
```

<a id="form-field-type-mismatch"></a>
### form-field-type-mismatch

**Feldtyp weicht vom Formularobjekt ab** · Bug · Warnung · Gruppe Formulare und Daten

Der Typ des Felds weicht von der Klasse des Objekts in der Formulardatei ab. Ohne Quelltext der Klasse aus der Formulardatei wird nicht verglichen. Die Korrektur ändert den Feldtyp.

Mit Treffer:

```pascal
Edit1: TEdit;  // object Edit1: TMaskEdit
```

Richtig:

```pascal
Edit1: TMaskEdit;
```

<a id="security-command-injection"></a>
### security-command-injection

**Befehlsinjektion** · Schwachstelle · Warnung · Gruppe Sicherheit

ShellExecute, ShellExecuteEx, CreateProcess oder WinExec erhält ein Argument, das mit +, Format oder Concat aus nicht konstanten Werten zusammengesetzt ist. Eingaben könnten weitere Befehle einschleusen. Ohne Datenflussanalyse wird nur dieses einfache Muster erkannt (mittlere Konfidenz).

Mit Treffer:

```pascal
ShellExecute(0, 'open', PChar('cmd /c ' + Edit1.Text), nil, nil, SW_SHOW);
```

Richtig:

```pascal
ShellExecute(0, 'open', 'tool.exe', PChar(QuotedArgument), nil, SW_SHOW);  // validated
```

<a id="security-path-traversal"></a>
### security-path-traversal

**Pfad-Traversal** · Schwachstelle · Warnung · Gruppe Sicherheit

Ein Dateizugriff (TFileStream.Create, LoadFromFile, AssignFile, TFile.*) verwendet einen Pfad aus Eingabedaten (Text, ParamStr, Request) ohne Prüfung über TPath.GetFullPath. Experimentell, bis die Datenflussanalyse verfügbar ist.

Mit Treffer:

```pascal
List.LoadFromFile('C:\Data\' + Edit1.Text);
```

Richtig:

```pascal
Path := TPath.GetFullPath(TPath.Combine(Root, Edit1.Text));  // then check it starts with Root
```

<a id="security-weak-crypto"></a>
### security-weak-crypto

**Schwache Kryptografie** · Sicherheits-Hotspot · Hinweis · Gruppe Sicherheit

MD5, SHA-1, DES oder RC4 wird verwendet. Für Prüfsummen ist das in Ordnung, für Kennwörter und Signaturen nicht. Niedrige Konfidenz, mittlere, wenn die Anweisung ein Kennwort, Geheimnis oder eine Signatur nennt.

Mit Treffer:

```pascal
Stored := THashSHA1.GetHashString(PasswordText);
```

Richtig:

```pascal
Stored := THashSHA2.GetHashString(Salt + PasswordText);
```

<a id="security-tls-verification-disabled"></a>
### security-tls-verification-disabled

**TLS-Zertifikatsprüfung abgeschaltet** · Schwachstelle · Warnung · Gruppe Sicherheit

Indy SSLOptions.VerifyMode := [], ein OnVerifyPeer-Handler, der immer True liefert, oder ein ValidateServerCertificate-Handler, der Accepted := True ohne Prüfung setzt.

Mit Treffer:

```pascal
IdSSL.SSLOptions.VerifyMode := [];
```

Richtig:

```pascal
IdSSL.SSLOptions.VerifyMode := [sslvrfPeer];
```

<a id="security-insecure-http"></a>
### security-insecure-http

**Unverschlüsselte http://-URL** · Sicherheits-Hotspot · Hinweis · Gruppe Sicherheit

Ein String enthält eine http://-URL. XML-Namensräume und Schema-URIs, Kommentare sowie localhost, 127.0.0.1 und [::1] sind ausgenommen. Die Korrektur ersetzt http:// durch https://.

Mit Treffer:

```pascal
Client.Get('http://api.example.com/data');
```

Richtig:

```pascal
Client.Get('https://api.example.com/data');
```

<a id="security-insecure-random"></a>
### security-insecure-random

**Random für sicherheitsrelevante Werte** · Sicherheits-Hotspot · Warnung · Gruppe Sicherheit

Random wird einem Token, Kennwort, Salt, Nonce oder Schlüssel zugewiesen. Random ist vorhersagbar; einen kryptografischen Zufallsgenerator verwenden. Fehlendes Randomize behandelt #153.

Mit Treffer:

```pascal
Token := IntToStr(Random(MaxInt));
```

Richtig:

```pascal
Token := TNetEncoding.Base64URL.EncodeBytesToString(CryptoRandomBytes(32));
```

<a id="dfm-circular-datasource"></a>
### dfm-circular-datasource

**Zirkuläre Master-Detail- bzw. DataSource-Verknüpfung** · Bug · Warnung · Gruppe Formulare und Daten

MasterSource/DataSource-Verknüpfungen der Formulardatei bilden einen Kreis (tblA → dsB → tblB → dsA → tblA). Das Öffnen der Datasets läuft in eine Rekursion oder zeigt keine stimmigen Daten.

Mit Treffer:

```pascal
tblA.MasterSource = dsB; tblB.MasterSource = dsA
```

Richtig:

```pascal
tblB.MasterSource = dsA  // tblA has no master
```

<a id="dfm-master-without-fields"></a>
### dfm-master-without-fields

**Master-Detail ohne MasterFields** · Bug · Warnung · Gruppe Formulare und Daten

Ein Dataset hat MasterSource, aber keine MasterFields. Das Detail wird nicht gefiltert und zeigt alle Datensätze.

Mit Treffer:

```pascal
MasterSource = dsKunden
```

Richtig:

```pascal
MasterSource = dsKunden; MasterFields = 'KundenID'
```

<a id="dfm-required-field-without-control"></a>
### dfm-required-field-without-control

**Pflichtfeld ohne sichtbares Eingabe-Control** · Bug · Warnung · Gruppe Formulare und Daten

Ein persistentes Feld mit Required = True ist an kein sichtbares datensensitives Control gebunden (ein Gitter ohne DataField zählt für alle Felder). Der Anwender kann es nicht füllen, Post schlägt fehl.

Mit Treffer:

```pascal
tblKundenName: Required = True, no TDBEdit for Name
```

Richtig:

```pascal
edName: TDBEdit; DataSource = dsKunden; DataField = 'Name'
```

<a id="dfm-control-field-type-mismatch"></a>
### dfm-control-field-type-mismatch

**Datensensitives Control passt nicht zum Feldtyp** · Bug · Warnung · Gruppe Formulare und Daten

Das Control passt nicht zum persistenten Feld, z. B. TDBEdit an einem TBooleanField oder Blob-Feld, TDBImage an einem Feld ohne Grafik.

Mit Treffer:

```pascal
edAktiv: TDBEdit; DataField = 'Aktiv'  // TBooleanField
```

Richtig:

```pascal
cbAktiv: TDBCheckBox; DataField = 'Aktiv'
```

<a id="dfm-duplicate-binding"></a>
### dfm-duplicate-binding

**Zwei Controls an demselben Feld** · Bug · Warnung · Gruppe Formulare und Daten

Zwei Eingabe-Controls nutzen dieselbe DataSource und dasselbe DataField. Meist ein Kopierfehler. Anzeige-Controls (TDBText, TDBImage) zählen nicht.

Mit Treffer:

```pascal
ed1, ed2: DataSource = dsA; DataField = 'Name'
```

Richtig:

```pascal
ed1: DataField = 'Name'; ed2: DataField = 'Vorname'
```

<a id="dfm-property"></a>
### dfm-property

**Komponenten-Property verletzt eine Eigenschaftsregel** · Code Smell · Warnung · Gruppe Formulare und Daten

Eine Komponenten-Property in der Formulardatei erfüllt eine Regel aus dfmPropertyRules in atlas.json nicht (Klasse, Property, Bedingung, Wert). Nicht gespeicherte Properties zählen mit ihrem default-Wert; Objekte aus dem Vorfahrenformular werden nur gemeldet, wenn dieses Formular den Wert selbst setzt. Die Schnellkorrektur setzt den Wert in der Formulardatei (fix: auto auch mit source.fixAll); der Befehl "Eigenschaftsregeln anwenden" korrigiert ein Formular, das Projekt oder die Gruppe mit Vorschau.

Mit Treffer:

```pascal
// dfmPropertyRules: TLabel.Transparent = True
object Label1: TLabel
  Caption = 'Name'
end
```

Richtig:

```pascal
object Label1: TLabel
  Caption = 'Name'
  Transparent = True
end
```

<a id="foreign-form-control-access"></a>
### foreign-form-control-access

**Zugriff auf Controls eines anderen Formulars** · Code Smell · Warnung · Gruppe Formulare und Daten

Code greift über die globale Variable auf ein Feld eines Formulars oder Frames aus einer anderen Unit zu (Form2.Edit1.Text). Das koppelt die Units eng; besser eine Methode oder Property des Formulars nutzen.

Mit Treffer:

```pascal
Form2.Edit1.Text := 'x';
```

Richtig:

```pascal
Form2.Kundenname := 'x';
```

<a id="security-sql-injection"></a>
### security-sql-injection

**SQL-Text aus zusammengesetzten Werten (SQL-Injection)** · Schwachstelle · Warnung · Gruppe Sicherheit

SQL.Text, SQL.Add, CommandText, ExecSQL oder Open erhalten Text, der per + oder Format aus Nicht-Konstanten zusammengesetzt ist. Benutzereingaben könnten SQL einschleusen. Parameter verwenden (:Name, ParamByName). Konstanten, resourcestrings, IntToStr und QuotedStr zählen nicht; Benutzereingaben (TEdit.Text, TMemo.Lines) heben die Konfidenz auf hoch.

Mit Treffer:

```pascal
Q.SQL.Text := 'select * from K where N = ''' + Edit1.Text + '''';
```

Richtig:

```pascal
Q.SQL.Text := 'select * from K where N = :N';
Q.ParamByName('N').AsString := Edit1.Text;
```

<a id="slash-command"></a>
### slash-command

**Schnellbefehl nicht ausgeführt** · Code Smell · Hinweis · Gruppe Atlas intern

Eine Zeile, die mit /name beginnt, wurde nicht ausgeführt und steht noch im Code: Der Befehl ist unbekannt, abgeschaltet (slashCommands.disabled) oder passt an dieser Stelle nicht. Die Meldung nennt den Grund. "/ignore regel" meldet sie auch, wenn diese Regel in der Zeile darunter nichts findet.

Mit Treffer:

```pascal
/gibtsnicht X
```

Richtig:

```pascal
/uses System.Classes
```

<a id="empty-except"></a>
### empty-except

**Leerer except-Block** · Code Smell · Warnung · Gruppe Exceptions

Ein except-Block ohne Anweisung verschluckt jede Ausnahme. Ein Block, der nur einen Kommentar enthält, gilt als begründet und wird nicht gemeldet.

Mit Treffer:

```pascal
try
  Save;
except
end;
```

Richtig:

```pascal
try
  Save;
except
  on E: EInOutError do
    Log(E.Message);
end;
```

<a id="interface-guid"></a>
### interface-guid

**Interface ohne GUID** · Bug · Warnung · Gruppe Fehler finden

Ein Interface deklariert keine GUID. Supports, as und QueryInterface brauchen eine. Die Konfidenz ist hoch, wenn das Interface in derselben Datei damit verwendet wird, sonst niedrig. Die Schnellkorrektur fügt eine neue GUID ein.

Mit Treffer:

```pascal
type
  ISaver = interface
    procedure Save;
  end;
```

Richtig:

```pascal
type
  ISaver = interface
    ['{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}']
    procedure Save;
  end;
```

<a id="duplicate-interface-guid"></a>
### duplicate-interface-guid

**Zwei Interfaces mit derselben GUID** · Bug · Fehler · Gruppe Fehler finden

Zwei Interfaces der Datei deklarieren dieselbe GUID, meist nach dem Kopieren einer Deklaration. Supports und as verwechseln sie dann. Die Schnellkorrektur erzeugt eine neue GUID.

Mit Treffer:

```pascal
ILoader = interface
  ['{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}']
end;
ISaver = interface
  ['{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}']
end;
```

Richtig:

```pascal
ILoader = interface
  ['{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}']
end;
ISaver = interface
  ['{0B9E4F21-7C6D-4A3E-8F15-2D9C7B6A4E31}']
end;
```

<a id="file-header"></a>
### file-header

**Dateikopf fehlt oder weicht ab** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die Datei beginnt nicht mit dem Kopf aus der Regeloption "template". Standardmäßig aus; in atlas.json mit einer Vorlage einschalten. Die Schnellkorrektur fügt den Kopf ein.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `template` | string | `""` | Erwarteter Dateikopf; Platzhalter wie dokumentiert. |

Mit Treffer:

```pascal
unit Tools;
```

Richtig:

```pascal
// Copyright (c) Example GmbH
unit Tools;
```

<a id="hardcoded-string"></a>
### hardcoded-string

**Text im Code statt resourcestring** · Code Smell · Hinweis · Gruppe Stil und Metriken

In einer Anweisung steht ein String mit Wörtern für Menschen. In einen resourcestring auslagern, damit er übersetzt werden kann. Standardmäßig aus, niedrige Konfidenz.

Mit Treffer:

```pascal
ShowMessage('File not found');
```

Richtig:

```pascal
resourcestring
  SFileNotFound = 'File not found';
...
ShowMessage(SFileNotFound);
```

<a id="self-assignment"></a>
### self-assignment

**Zuweisung an sich selbst** · Bug · Warnung · Gruppe Fehler finden

Einer Variablen, einem Feld oder einer Property wird der eigene Wert zugewiesen. Gemeint ist meist ein anderer Wert, etwa ein Parameter oder ein anderes Feld. Verdeckt ein Parameter oder eine lokale Variable ein gleichnamiges Feld (Name := Name), bietet Atlas Self.Name := Name als Korrektur an.

Mit Treffer:

```pascal
FName := FName;
```

Richtig:

```pascal
FName := AName;
```

<a id="for-high-to-low"></a>
### for-high-to-low

**for-Schleife zählt mit to abwärts** · Bug · Warnung · Gruppe Fehler finden

Die Schleife beginnt beim oberen Wert (High, Count - 1) und endet beim unteren, verwendet aber to. Sie läuft nie; gemeint war downto.

Mit Treffer:

```pascal
for I := High(A) to Low(A) do
  Save(A[I]);
```

Richtig:

```pascal
for I := High(A) downto Low(A) do
  Save(A[I]);
```

<a id="exception-not-raised"></a>
### exception-not-raised

**Exception erzeugt, aber nicht ausgelöst** · Bug · Warnung · Gruppe Fehler finden

Ein Exception-Objekt wird als eigene Anweisung erzeugt. Ohne raise passiert nichts, und das Objekt bleibt als Speicherleck zurück.

Mit Treffer:

```pascal
if X = nil then
  EArgumentException.Create('X missing');
```

Richtig:

```pascal
if X = nil then
  raise EArgumentException.Create('X missing');
```

<a id="assert-side-effect"></a>
### assert-side-effect

**Assert mit Seiteneffekt** · Bug · Warnung · Gruppe Fehler finden

Das Argument von Assert verändert Daten (Inc, Dec, eine Try…-Funktion mit out-Parameter oder eine Methode aus der Option mutatingMethods). Mit {$C-} entfernt der Compiler den ganzen Aufruf samt Seiteneffekt.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `mutatingMethods` | string-list | `["Add","Delete","Remove","Extract","Clear","Insert"]` | Methoden, die ihr Objekt verändern. |

Mit Treffer:

```pascal
Assert(List.Remove(X) >= 0);
```

Richtig:

```pascal
Index := List.Remove(X);
Assert(Index >= 0);
```

<a id="ifthen-side-effect"></a>
### ifthen-side-effect

**IfThen wertet beide Zweige aus** · Bug · Warnung · Gruppe Fehler finden

IfThen ist eine Funktion: Beide Zweige werden vor dem Aufruf ausgewertet. Ein Nil-Zugriff oder Funktionsaufruf im nicht gewählten Zweig passiert trotzdem. Hohe Konfidenz, wenn ein Zweig einen in der Bedingung geprüften Namen dereferenziert, mittlere bei einem Funktionsaufruf.

Mit Treffer:

```pascal
S := IfThen(Assigned(X), X.Name, '');
```

Richtig:

```pascal
if Assigned(X) then S := X.Name else S := '';
```

<a id="random-without-randomize"></a>
### random-without-randomize

**Random ohne Randomize** · Code Smell · Hinweis · Gruppe Robustheit und Muster

Random wird verwendet, aber die Unit ruft nie Randomize auf; jeder Start liefert dieselbe Folge. Randomize steht oft in der .dpr, deshalb ist die Regel standardmäßig aus und hat niedrige Konfidenz.

Mit Treffer:

```pascal
Dice := Random(6) + 1;
```

Richtig:

```pascal
Randomize; // once at program start
...
Dice := Random(6) + 1;
```

<a id="int32-mul-overflow"></a>
### int32-mul-overflow

**Int32-Multiplikation an Int64 zugewiesen** · Bug · Warnung · Gruppe Fehler finden

Beide Operanden haben höchstens 32 Bit; das Produkt wird in 32 Bit gerechnet und läuft über, bevor es der Int64-Variablen zugewiesen wird. Einen Operanden nach Int64 umwandeln.

Mit Treffer:

```pascal
Total := Width * Height; // Total: Int64; Width, Height: Integer
```

Richtig:

```pascal
Total := Int64(Width) * Height;
```

<a id="sizeof-pointer"></a>
### sizeof-pointer

**SizeOf eines Zeigers in Move oder FillChar** · Bug · Fehler · Gruppe Fehler finden

SizeOf eines Zeigers, Strings oder dynamischen Arrays ist die Größe des Verweises (4 oder 8 Byte), nicht die der Daten. Move und FillChar kopieren bzw. löschen dann zu wenig.

Mit Treffer:

```pascal
FillChar(Buffer[0], SizeOf(Buffer), 0); // Buffer: TBytes
```

Richtig:

```pascal
FillChar(Buffer[0], Length(Buffer) * SizeOf(Buffer[0]), 0);
```

<a id="char-to-pchar"></a>
### char-to-pchar

**Char nach PChar umgewandelt** · Bug · Fehler · Gruppe Fehler finden

PChar(C) mit einer Char-Variablen macht aus dem Zeichencode eine Adresse. Gemeint war ein String.

Mit Treffer:

```pascal
ShowMessage(PChar(C)); // C: Char
```

Richtig:

```pascal
ShowMessage(PChar(string(C)));
```

<a id="float-equality"></a>
### float-equality

**Gleitkommavergleich mit = oder <>** · Bug · Hinweis · Gruppe Fehler finden

Gleitkommawerte sind nach Berechnungen selten exakt gleich. Mit SameValue aus System.Math und einer Toleranz vergleichen. Vergleiche mit 0 werden nicht gemeldet.

Mit Treffer:

```pascal
if Total = Expected then
```

Richtig:

```pascal
if SameValue(Total, Expected) then
```

<a id="constructor-on-instance"></a>
### constructor-on-instance

**Konstruktor auf einer Instanz aufgerufen** · Bug · Warnung · Gruppe Fehler finden

Create wird auf einer Variablen statt auf der Klasse aufgerufen. Das legt kein neues Objekt an; mit nicht zugewiesener Variable stürzt es ab. Klassenreferenzen (class of …) werden nicht gemeldet.

Mit Treffer:

```pascal
List.Create; // List: TStringList
```

Richtig:

```pascal
List := TStringList.Create;
```

<a id="format-without-settings"></a>
### format-without-settings

**Formatierung abhängig vom Gebietsschema** · Code Smell · Hinweis · Gruppe Robustheit und Muster

Format mit %f, %n, %m, %g oder %e und Funktionen wie FloatToStr, StrToFloat oder DateToStr ohne TFormatSettings-Parameter verwenden das Gebietsschema des Benutzers (Dezimaltrenner, Datumsformat). Für Dateien, Protokolle und Logs feste TFormatSettings übergeben. Format('%d', …) wird nicht gemeldet.

Mit Treffer:

```pascal
Line := Format('%.2f', [Amount]);
```

Richtig:

```pascal
Line := Format('%.2f', [Amount], TFormatSettings.Invariant);
```

<a id="generic-exception-raised"></a>
### generic-exception-raised

**Allgemeine Exception ausgelöst** · Code Smell · Hinweis · Gruppe Exceptions

Wer die Basisklasse Exception auslöst, nimmt Aufrufern die Möglichkeit, den Fehler gezielt zu behandeln. Besser eine eigene Exception-Klasse deklarieren.

Mit Treffer:

```pascal
raise Exception.Create('Customer missing');
```

Richtig:

```pascal
raise ECustomerMissing.Create('Customer missing');
```

<a id="catch-all-without-raise"></a>
### catch-all-without-raise

**Exception-Handler ohne erneutes raise** · Code Smell · Warnung · Gruppe Exceptions

Ein Handler für Exception, der weder erneut auslöst noch das Programm beendet, verschluckt jeden Fehler, auch Programmierfehler. Standardmäßig aus; gedacht für Bibliothekscode.

Mit Treffer:

```pascal
except
  on E: Exception do
    Log(E.Message);
end;
```

Richtig:

```pascal
except
  on E: Exception do
  begin
    Log(E.Message);
    raise;
  end;
end;
```

<a id="exception-freed"></a>
### exception-freed

**Exception-Objekt manuell freigegeben** · Bug · Fehler · Gruppe Exceptions

Die RTL gibt ein Exception-Objekt nach seinem Handler bzw. nach raise selbst frei. Manuelles Freigeben führt zur doppelten Freigabe.

Mit Treffer:

```pascal
on E: Exception do
  E.Free;
```

Richtig:

```pascal
on E: Exception do
  Log(E.Message);
```

<a id="string-concat-in-loop"></a>
### string-concat-in-loop

**String-Verkettung in einer Schleife** · Code Smell · Hinweis · Gruppe Performance

Eine String-Variable wird in einer Schleife schrittweise verlängert. Delphi vergrößert Strings meist an Ort und Stelle, deshalb nur mit niedriger Konfidenz und standardmäßig aus; bei vielen Durchläufen ist TStringBuilder schneller.

Mit Treffer:

```pascal
for I := 1 to 10000 do
  S := S + IntToStr(I);
```

Richtig:

```pascal
Builder := TStringBuilder.Create;
try
  for I := 1 to 10000 do
    Builder.Append(I);
  S := Builder.ToString;
finally
  Builder.Free;
end;
```

<a id="loop-invariant-call"></a>
### loop-invariant-call

**Teurer Aufruf in der Schleifenbedingung** · Code Smell · Hinweis · Gruppe Performance

Die Bedingung von while und until wird bei jedem Durchlauf ausgewertet. Aufrufe wie Trim, Format oder FileExists und Eigenschaften wie Lines.Text werden dort jedes Mal neu berechnet; besser einmal vor der Schleife. Die Grenzen von for werden nur einmal ausgewertet und nicht gemeldet. Standardmäßig aus.

Mit Treffer:

```pascal
while I < Length(Trim(Memo.Lines.Text)) do
  Inc(I);
```

Richtig:

```pascal
Text := Trim(Memo.Lines.Text);
while I < Length(Text) do
  Inc(I);
```

<a id="missing-begin-update"></a>
### missing-begin-update

**Hinzufügen in einer Schleife ohne BeginUpdate** · Code Smell · Hinweis · Gruppe Performance

Items.Add, Lines.Add und ähnliche Aufrufe in einer Schleife zeichnen das Steuerelement bei jedem Aufruf neu. Die Schleife mit BeginUpdate und try … finally EndUpdate umschließen. Standardmäßig aus.

Mit Treffer:

```pascal
for I := 1 to 1000 do
  ListBox1.Items.Add(IntToStr(I));
```

Richtig:

```pascal
ListBox1.Items.BeginUpdate;
try
  for I := 1 to 1000 do
    ListBox1.Items.Add(IntToStr(I));
finally
  ListBox1.Items.EndUpdate;
end;
```

<a id="bool-compare"></a>
### bool-compare

**Vergleich mit True oder False** · Code Smell · Hinweis · Gruppe Stil und Metriken

Ein Vergleich eines Boolean mit True oder False ist überflüssig; den Ausdruck oder not direkt verwenden.

Mit Treffer:

```pascal
if Visible = True then
  Show;
```

Richtig:

```pascal
if Visible then
  Show;
```

<a id="redundant-assigned-free"></a>
### redundant-assigned-free

**Assigned-Prüfung vor Free** · Code Smell · Hinweis · Gruppe Stil und Metriken

Free prüft selbst auf nil, eine Assigned-Prüfung vor Free oder FreeAndNil ist überflüssig.

Mit Treffer:

```pascal
if Assigned(List) then
  List.Free;
```

Richtig:

```pascal
List.Free;
```

<a id="raise-in-finally"></a>
### raise-in-finally

**raise in einem finally-Block** · Bug · Warnung · Gruppe Exceptions

Eine im finally-Block ausgelöste Exception ersetzt die gerade laufende Exception, die dadurch verloren geht.

Mit Treffer:

```pascal
try
  Work;
finally
  raise Exception.Create('Fehler');
end;
```

Richtig:

```pascal
try
  Work;
finally
  Cleanup;
end;
```

<a id="redundant-parens"></a>
### redundant-parens

**Überflüssige Klammern** · Code Smell · Hinweis · Gruppe Stil und Metriken

Klammern um eine ganze Bedingung oder einen einzelnen Bezeichner bringen nichts. Standardmäßig aus.

Mit Treffer:

```pascal
if (Done) then
  Exit;
```

Richtig:

```pascal
if Done then
  Exit;
```

<a id="redundant-begin-end"></a>
### redundant-begin-end

**begin … end um eine einzelne Anweisung** · Code Smell · Hinweis · Gruppe Stil und Metriken

Ein begin … end-Block mit genau einer Anweisung kann entfallen. Standardmäßig aus.

Mit Treffer:

```pascal
if Done then
begin
  Exit;
end;
```

Richtig:

```pascal
if Done then
  Exit;
```

<a id="with-statement"></a>
### with-statement

**with-Anweisung** · Code Smell · Hinweis · Gruppe Stil und Metriken

In einem with-Block ist unklar, zu welchem Objekt ein Bezeichner gehört, und ein neues Mitglied des with-Objekts ändert still die Bedeutung. Den Ausdruck ausschreiben oder eine lokale Variable verwenden.

Mit Treffer:

```pascal
with Customer do
  Name := Edit.Text;
```

Richtig:

```pascal
Customer.Name := Edit.Text;
```

<a id="metric-method-length"></a>
### metric-method-length

**Methode zu lang** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die Methode hat mehr Codezeilen als der Grenzwert (Vorgabe 60). Leerzeilen, Kommentare, Compiler-Direktiven und lokale Routinen zählen nicht mit. Die Methode in kleinere aufteilen. Den Grenzwert setzt die Option max, z. B. "rules": {"metric-method-length": {"max": 80}}.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `60` | Höchstens so viele Anweisungszeilen. |

Mit Treffer:

```pascal
procedure TImport.Run;
begin
  // 120 lines: read, check, convert and save
end;
```

Richtig:

```pascal
procedure TImport.Run;
begin
  Read;
  Check;
  Convert;
  Save;
end;
```

<a id="metric-nesting-depth"></a>
### metric-nesting-depth

**Zu tief verschachtelt** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die Methode verschachtelt if, case, Schleifen und try tiefer als der Grenzwert (Vorgabe 4). else if bleibt auf der Ebene seines if. Mit Exit oder Continue früh verlassen oder innere Teile in eigene Methoden auslagern. Den Grenzwert setzt die Option max.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `4` | Höchste erlaubte Schachtelungstiefe. |

Mit Treffer:

```pascal
for Item in Items do
  if Item.Active then
    for Line in Item.Lines do
      if Line.Valid then
        try
          Save(Line);
        except
          Log;
        end;
```

Richtig:

```pascal
for Item in Items do
  if Item.Active then
    SaveLines(Item);
```

<a id="metric-cyclomatic-complexity"></a>
### metric-cyclomatic-complexity

**Zyklomatische Komplexität zu hoch** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die zyklomatische Komplexität der Methode liegt über dem Grenzwert (Vorgabe 15). Sie beginnt bei 1 und steigt um 1 je if, while, repeat und for, je case-Zweig ohne else, je and/or in einer Bedingung und je except on; ein except ohne on zählt einmal. Viele Pfade brauchen viele Tests. Den Grenzwert setzt die Option max.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `15` | Höchste erlaubte zyklomatische Komplexität. |

Mit Treffer:

```pascal
case Kind of
  1: A;
  2: B;
  // ... 20 branches
end;
```

Richtig:

```pascal
Handlers[Kind]();
```

<a id="metric-cognitive-complexity"></a>
### metric-cognitive-complexity

**Kognitive Komplexität zu hoch** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die kognitive Komplexität der Methode liegt über dem Grenzwert (Vorgabe 15). Nach SonarSource zählen if, case, Schleifen und except-Behandler 1 plus ihre Schachtelungsebene; else, else if, goto und jede Folge gleicher logischer Operatoren zählen 1. Verschachtelter Code ist schwerer zu lesen als Code hintereinander. Den Grenzwert setzt die Option max.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `15` | Höchste erlaubte kognitive Komplexität. |

Mit Treffer:

```pascal
if A then
  for I := 0 to N do
    if B and C or D then
      while E do
        F;
```

Richtig:

```pascal
if not A then
  Exit;
for I := 0 to N do
  ProcessItem(I);
```

<a id="metric-parameter-count"></a>
### metric-parameter-count

**Zu viele Parameter** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die Methode hat mehr Parameter als der Grenzwert (Vorgabe 6). Zusammengehörige Werte in einem Record oder einer Klasse bündeln. Den Grenzwert setzt die Option max.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `6` | Höchstens so viele Parameter. |

Mit Treffer:

```pascal
procedure Book(const AName, AStreet, ACity, AZip: string; AAmount: Currency; ADate: TDate; ANote: string);
```

Richtig:

```pascal
procedure Book(const AAddress: TAddress; const AOrder: TOrder);
```

<a id="todo-comment"></a>
### todo-comment

**Offener TODO-Kommentar** · Code Smell · Hinweis · Gruppe Stil und Metriken

Ein Kommentar beginnt mit einer Marke für offene Arbeit: // TODO, // FIXME oder das Format der IDE-To-Do-Liste { TODO 1 -oPerson -cKategorie : Text }. Der Hinweis zeigt Marke, Priorität, Kategorie, Person und Text, damit offene Arbeit in der Problemliste erscheint. In der Vorgabe aus; in atlas.json einschalten, z. B. "rules": {"todo-comment": {"severity": "hint"}}. Erledigte Einträge ({ DONE … }) meldet die Regel nie. Die Option keywords legt die Marken fest (Vorgabe ["TODO", "FIXME"]); sie gilt auch für get_todos und --todos.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `keywords` | string-list | `["TODO","FIXME"]` | Marken offener TODO-Einträge (nur Buchstaben). |

Mit Treffer:

```pascal
// TODO 1 -oMarco -cGUI : set focus
Edit.Text := '';
```

Richtig:

```pascal
Edit.Text := '';
Edit.SetFocus;
```

<a id="component-palette-icon"></a>
### component-palette-icon

**Registrierte Komponente ohne Palettensymbol** · Code Smell · Hinweis · Gruppe Komponenten

Jede an RegisterComponents übergebene Klasse braucht in einer per {$R} eingebundenen .dcr oder .res eine Bitmap mit dem Klassennamen in Großbuchstaben. Ab Delphi 11 werden zusätzlich die Größen 16, 24 und 32 px (NAME16, NAME24, NAME32) erwartet. Ohne lesbare eingebundene Ressourcendatei schweigt die Regel.

Mit Treffer:

```pascal
{$R *.dcr} // without TMYBUTTON
RegisterComponents('Samples', [TMyButton]);
```

Richtig:

```pascal
{$R *.dcr} // with TMYBUTTON16, TMYBUTTON24, TMYBUTTON32
RegisterComponents('Samples', [TMyButton]);
```

<a id="unresolved-identifier"></a>
### unresolved-identifier

**Nicht deklarierter Bezeichner** · Bug · Warnung · Gruppe Fehler finden

Ein Bezeichner in einer Anweisung ist weder in der Unit noch in den eingebundenen Units deklariert (wie Compilerfehler E2003). Geprüft beim Tippen, ohne Compiler; with-Blöcke, asm und anonyme Methoden werden übersprungen.

Mit Treffer:

```pascal
procedure Foo;
begin
  Lst.Add('x');
end;
```

Richtig:

```pascal
procedure Foo;
var
  Lst: TStringList;
begin
  Lst := TStringList.Create;
  Lst.Add('x');
end;
```

<a id="deprecated-symbol"></a>
### deprecated-symbol

**Veraltetes Symbol** · Code Smell · Hinweis · Gruppe Stil und Metriken

Eine Routine, ein Typ, eine Konstante oder ein Mitglied mit deprecated, platform oder experimental wird verwendet (wie Compilerwarnungen W1000, W1002 und W1003). Der Editor streicht den Namen durch; die Meldung nennt den Grund aus deprecated 'Grund'. Die Deklaration und der Kopf ihrer Implementierung werden nicht gemeldet.

Mit Treffer:

```pascal
procedure Old; deprecated 'Use New';
...
Old;
```

Richtig:

```pascal
procedure New;
...
New;
```

<a id="implicit-package-import"></a>
### implicit-package-import

**Implizit eingebundene Unit** · Code Smell · Warnung · Gruppe Packages und Tests

In einem Package (.dpk) verwendet eine Unit aus contains eine Unit, die weder in contains steht noch von einem Package aus requires geliefert wird. Der Compiler zieht sie implizit hinein (W1033), was später zu doppelten Units führt, wenn ein anderes Package sie ebenfalls enthält. Die Schnellkorrektur nimmt die Unit in contains auf.

Mit Treffer:

```pascal
package Werkzeuge;
requires rtl;
contains
  uHaupt in 'uHaupt.pas';  // uHaupt uses uMathe
end.
```

Richtig:

```pascal
package Werkzeuge;
requires rtl;
contains
  uHaupt in 'uHaupt.pas',
  uMathe in 'uMathe.pas';
end.
```

<a id="type-used-before-declaration"></a>
### type-used-before-declaration

**Typ vor seiner Deklaration benutzt** · Bug · Fehler · Gruppe Fehler finden

Eine Klasse, ein Interface, ein Record oder ein anderer Typ wird in einer Typdeklaration (Feld, Parameter, Ergebnis, Property, generisches Argument, class of) benutzt, ist aber erst weiter unten im selben Gültigkeitsbereich deklariert (wie Compilerfehler E2003). Vorfahren, Aliase und Zeigertypen werden nicht gemeldet. Schnellkorrekturen: Forward-Deklaration am Anfang des type-Blocks ergänzen, type-Blöcke zusammenlegen (const-, var- und label-Abschnitte dazwischen wandern vor den ersten Block) oder einen Record vor seinen ersten Verwender verschieben; ohne sichere Korrektur nennt die Meldung den Grund.

Mit Treffer:

```pascal
type
  TTree = class
    FRoot: TNode;
  end;
  TNode = class
  end;
```

Richtig:

```pascal
type
  TNode = class;
  TTree = class
    FRoot: TNode;
  end;
  TNode = class
  end;
```

<a id="unneeded-forward-declaration"></a>
### unneeded-forward-declaration

**Überflüssige Forward-Deklaration** · Code Smell · Hinweis · Gruppe Stil und Metriken

Eine Forward-Deklaration, deren Typ im selben type-Block vor der vollständigen Deklaration nicht benutzt wird. Schnellkorrektur: entfernen.

Mit Treffer:

```pascal
type
  TNode = class;
  TNode = class
  end;
```

Richtig:

```pascal
type
  TNode = class
  end;
```

<a id="field-not-freed"></a>
### field-not-freed

**Feld erzeugt, aber nie freigegeben** · Bug · Warnung · Gruppe Fehler finden

Ein Objektfeld, das der Konstruktor (oder eine von ihm aufgerufene private Methode) mit TKlasse.Create erzeugt, wird in der Klasse nirgends freigegeben (kein Free, FreeAndNil, Destroy oder DisposeOf): ein Speicherleck. Ausgenommen sind Komponenten mit einem Owner ungleich nil, Interface- und Record-Felder sowie die Klassen aus der Option ignoreTypes; TObjectList- und TObjectDictionary-Felder sind normale Felder. Konfidenz mittel. Schnellkorrekturen: das Feld im Destruktor freigeben oder alle eigenen Objekte der Klasse freigeben; ein fehlender Destruktor wird mit override und inherited angelegt. Die Freigaben stehen vor inherited in umgekehrter Erzeugungsreihenfolge, als Free oder FreeAndNil (refactoring.freeFieldsStyle). Bis #918 hieß die Regel owned-field-not-freed; Einstellungen und Unterdrückungen mit dieser Kennung wirken weiter.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `ignoreTypes` | string-list | `[]` | Klassen, die anderswo freigegeben werden; generische Typen treffen ohne Typparameter. |

Mit Treffer:

```pascal
constructor TImport.Create;
begin
  FZeilen := TStringList.Create;
  FFehler := TStringList.Create;
end;

destructor TImport.Destroy;
begin
  FZeilen.Free;
  inherited;
end;
```

Richtig:

```pascal
destructor TImport.Destroy;
begin
  FFehler.Free;
  FZeilen.Free;
  inherited;
end;
```

<a id="owned-field-free-unclear"></a>
### owned-field-free-unclear

**Unklar, ob ein erzeugtes Feld freigegeben werden muss** · Bug · Hinweis · Gruppe Fehler finden

Ein im Konstruktor erzeugtes, nicht freigegebenes Objektfeld wird auch zurückgegeben (Result := FFeld, Exit(FFeld)), an eine Property eines anderen Objekts oder an dessen Add…, Insert…, Register…, Attach…, Push oder Enqueue übergeben, ohne Create zugewiesen oder ist über eine Property (write FFeld) schreibbar. Ob die Klasse das Objekt noch besitzt, entscheidet der Entwickler; deshalb gibt es keine Schnellkorrektur.

Mit Treffer:

```pascal
function TCache.Take: TList;
begin
  Result := FList;  // created in Create, never freed
end;
```

Richtig:

```pascal
function TCache.Take: TList;
begin
  Result := FList;
  FList := nil;  // ownership passes to the caller
end;
```

<a id="operator-precedence"></a>
### operator-precedence

**Vorrang von not übersehen** · Bug · Warnung · Gruppe Fehler finden

In Pascal bindet not stärker als in und Vergleiche: not X in Menge heißt (not X) in Menge, not A = B heißt (not A) = B, bei Ganzzahlen wird not bitweise. Die Regel meldet diese Formen, wenn der deklarierte Typ des Operanden zeigt, dass es nicht gemeint sein kann (kein Boolean). Schnellkorrektur: Klammern setzen, not (X in Menge).

Mit Treffer:

```pascal
if not Zustand in [zsOffen, zsGesperrt] then
  Bearbeiten;
```

Richtig:

```pascal
if not (Zustand in [zsOffen, zsGesperrt]) then
  Bearbeiten;
```

<a id="empty-statement"></a>
### empty-statement

**Leere Anweisung nach then, do oder else** · Bug · Warnung · Gruppe Fehler finden

Ein Semikolon direkt nach then, do oder else beendet die Anweisung: Die folgende Zeile läuft dann immer bzw. die Schleife dreht leer. Ein leerer Block begin … end nach then, do oder else wird ebenfalls gemeldet, außer er enthält einen erklärenden Kommentar (Option allowCommented). Ein Semikolon direkt vor end, until, except oder finally ändert nichts und bleibt unbeanstandet. Schnellkorrektur: Semikolon entfernen.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `allowCommented` | boolean | `true` | begin { absichtlich leer } end nicht melden. |

Mit Treffer:

```pascal
if Liste.Count = 0 then;
  raise EKeineDaten.Create('Keine Daten');
```

Richtig:

```pascal
if Liste.Count = 0 then
  raise EKeineDaten.Create('Keine Daten');
```

<a id="loop-off-by-one"></a>
### loop-off-by-one

**Schleife läuft einen Schritt zu weit** · Bug · Warnung · Gruppe Fehler finden

for I := 0 to Liste.Count oder to Length(A) über nullbasierte Listen und Arrays greift im letzten Durchlauf hinter das Ende, wenn der Rumpf Liste[I] bzw. A[I] liest. Bei einsbasierten Strings umgekehrt: S[0] und for I := 0 to Length(S) greifen vor das erste Zeichen; {$ZEROBASEDSTRINGS ON} wird beachtet. Schnellkorrektur: - 1 ergänzen bzw. High(A) verwenden, bei Strings Low(S) und High(S). Die Option countNames nennt die Namen, die eine Anzahl liefern.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `countNames` | string-list | `["Count","Length"]` | Namen, die eine Anzahl liefern (Property wie Count oder Funktion wie Length). |

Mit Treffer:

```pascal
for I := 0 to Kunden.Count do
  Ausgabe(Kunden[I].Name);
```

Richtig:

```pascal
for I := 0 to Kunden.Count - 1 do
  Ausgabe(Kunden[I].Name);
```

<a id="collection-modified-in-loop"></a>
### collection-modified-in-loop

**Liste in der eigenen Schleife verändert** · Bug · Warnung · Gruppe Fehler finden

Delete, Remove, Add oder eine andere Methode aus der Option mutatingMethods wird auf der Liste aufgerufen, über die die Schleife gerade vorwärts per Index oder mit for … in läuft. Vorwärts überspringt Delete das nächste Element und läuft über das Ende, Add wird nicht mehr durchlaufen und Insert liefert dasselbe Element zweimal; mit for … in wirft die RTL eine Exception. Ein Break oder Exit direkt nach dem Aufruf beendet die Schleife und bleibt still, downto-Schleifen ebenso. Schnellkorrektur bei Indexschleifen: rückwärts mit downto; bei for … in die Elemente sammeln und die Liste nach der Schleife ändern.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `mutatingMethods` | string-list | `["Add","Insert","Delete","Remove","Extract","Clear"]` | Methoden, die die Liste verändern. |

Mit Treffer:

```pascal
for I := 0 to Liste.Count - 1 do
  if Liste[I].Erledigt then
    Liste.Delete(I);
```

Richtig:

```pascal
for I := Liste.Count - 1 downto 0 do
  if Liste[I].Erledigt then
    Liste.Delete(I);
```

<a id="use-after-free"></a>
### use-after-free

**Objekt nach Free weiter benutzt** · Bug · Fehler · Gruppe Fehler finden

Nach X.Free, X.Destroy, X.DisposeOf, FreeAndNil(X) oder Dispose(X) wird X ohne neue Zuweisung wieder benutzt: Methode, Feld, Index oder X^, with X, nach Free auch Assigned(X) (immer True) oder ein zweites Free. Die Regel folgt dem Datenfluss der Routine; eine Zuweisung an X, die Übergabe von X an eine Routine, @X und nach FreeAndNil eine Abfrage auf nil beenden den Weg, Wege nur über eine mögliche Ausnahme bleiben aus. Konfidenz hoch, wenn Freigabe und Zugriff im selben Block nacheinander stehen, sonst mittel. Keine automatische Korrektur; die Aktion springt zur Freigabe.

Mit Treffer:

```pascal
Bericht.Free;
Protokoll.Add('Seiten: ' + IntToStr(Bericht.Seiten));
```

Richtig:

```pascal
Protokoll.Add('Seiten: ' + IntToStr(Bericht.Seiten));
Bericht.Free;
```

<a id="deref-before-nil-check"></a>
### deref-before-nil-check

**Erst benutzt, dann auf nil geprüft** · Bug · Warnung · Gruppe Fehler finden

X wird dereferenziert (X.Feld, X.Methode, X^) und erst danach mit Assigned(X), X <> nil oder X = nil geprüft. Entweder ist die Prüfung überflüssig oder der Zugriff davor kann knallen. Gemeldet wird nur, wenn jeder Weg zur Prüfung durch den Zugriff führt und X vorher nicht geprüft wurde; eine neue Zuweisung, die Übergabe von X an eine Routine und bei Feldern und globalen Variablen jeder Aufruf dazwischen beenden den Weg. Konfidenz mittel. Ist die Prüfung ein if ohne else direkt nach dem Zugriff im selben Block, zieht die Schnellkorrektur den Zugriff hinein.

Mit Treffer:

```pascal
Titel := Kunde.Name;
if Assigned(Kunde) then
  Anzeigen(Kunde);
```

Richtig:

```pascal
if Assigned(Kunde) then
begin
  Titel := Kunde.Name;
  Anzeigen(Kunde);
end;
```

<a id="field-free-without-nil"></a>
### field-free-without-nil

**Feld freigegeben, Verweis bleibt stehen** · Bug · Warnung · Gruppe Fehler finden

FFeld.Free in einer Methode außerhalb des Destruktors, und ein Weg zum Ende der Methode setzt das Feld nicht neu. Ein späterer Zugriff oder ein zweites Free trifft freigegebenen Speicher. Neu setzt eine Zuweisung oder der Aufruf einer Methode derselben Klasse, die das Feld zuweist. Felder sind die der Klassendeklaration in der Unit. Ausgenommen sind Destruktoren, Methoden mit [TearDown] oder [TearDownFixture], Methoden, die nur aus diesen aufgerufen werden, und die Methoden aus der Option ignoreMethods. Konfidenz mittel. Schnellkorrektur: FreeAndNil(FFeld).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `ignoreMethods` | string-list | `["Destroy","BeforeDestruction"]` | Methoden, in denen Free ohne nil erlaubt ist. |

Mit Treffer:

```pascal
procedure TImport.Zuruecksetzen;
begin
  FCache.Free;
end;
```

Richtig:

```pascal
procedure TImport.Zuruecksetzen;
begin
  FreeAndNil(FCache);
end;
```

<a id="missing-inherited"></a>
### missing-inherited

**Konstruktor oder Destruktor ohne inherited** · Bug · Warnung · Gruppe Fehler finden

Ein Konstruktor oder ein override von Destroy, AfterConstruction oder BeforeDestruction ruft inherited nicht auf, in jeder Klasse, deren Vorfahr nicht TObject ist. Konstruktoren werden nur gemeldet, wenn ein Vorfahr einen eigenen Konstruktor deklariert (Datei, Index oder bekannte RTL-/VCL-Klasse) und der Konstruktor keinen anderen Konstruktor derselben Klasse aufruft. Bei Komponenten meldet Destroy nur component-missing-inherited. Konfidenz hoch. Schnellkorrektur: inherited; am Ende von Destroy und BeforeDestruction, am Anfang von Konstruktoren und AfterConstruction; ein Konstruktor mit Parametern ohne override bekommt inherited Create;.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `methods` | string-list | `["Create","Destroy","AfterConstruction","BeforeDestruction"]` | Geprüfte Methoden; Create steht für alle Konstruktoren, deren Name mit Create beginnt. |

Mit Treffer:

```pascal
destructor TExport.Destroy;
begin
  FDatei.Free;
end;
```

Richtig:

```pascal
destructor TExport.Destroy;
begin
  FDatei.Free;
  inherited;
end;
```

<a id="destroy-called-directly"></a>
### destroy-called-directly

**Destroy statt Free aufgerufen** · Bug · Warnung · Gruppe Fehler finden

Obj.Destroy wird direkt als Anweisung aufgerufen. Ist Obj nil, knallt der Aufruf; Free prüft vorher auf nil und ist der übliche Weg, ein Objekt freizugeben. inherited Destroy und Aufrufe eines Destruktors mit Argumenten sind ausgenommen. Konfidenz hoch. Schnellkorrektur: aus Destroy wird Free.

Mit Treffer:

```pascal
Verbindung.Destroy;
```

Richtig:

```pascal
Verbindung.Free;
```

<a id="managed-type-raw-memory"></a>
### managed-type-raw-memory

**FillChar, Move oder GetMem auf verwaltete Typen** · Bug · Fehler · Gruppe Fehler finden

FillChar, ZeroMemory, FillMemory, Move, CopyMemory, GetMem oder FreeMem auf eine Variable, deren Typ Strings, Interfaces, dynamische Arrays oder Variants enthält (Records, statische Arrays und Aliasse werden in der Datei und im Index aufgelöst). Referenzzähler werden überschrieben oder übergangen: Lecks, doppelte Freigabe, Zugriffsverletzungen. Geprüft werden nur einfache Variablen (X, @X, P^); Array-Elemente wie S[1] und Typen, die sich nicht auflösen lassen, bleiben still. Konfidenz hoch. Schnellkorrekturen: aus FillChar(X, SizeOf(X), 0) wird X := Default(T), aus Move(A, B, SizeOf(T)) wird B := A, aus GetMem(P, SizeOf(T)) wird New(P) und aus FreeMem(P) wird Dispose(P); sonst helfen Initialize und Finalize.

Mit Treffer:

```pascal
FillChar(Adresse, SizeOf(Adresse), 0);
```

Richtig:

```pascal
Adresse := Default(TAdresse);
```

<a id="threadvar-managed"></a>
### threadvar-managed

**threadvar mit verwaltetem Typ** · Bug · Warnung · Gruppe Threads

Delphi finalisiert threadvar-Variablen nicht. Ein String, Interface, dynamisches Array oder Variant in einer threadvar (auch in einem Record oder statischen Array) leckt in jedem Thread, der endet. Typen werden in der Datei und im Index aufgelöst. Konfidenz hoch. Keine Schnellkorrektur: den Wert am Thread-Ende freigeben (etwa in TThread.Execute auf '' bzw. nil setzen) oder stattdessen einen Zeiger bzw. Puffer fester Größe ablegen.

Mit Treffer:

```pascal
threadvar
  LetzteMeldung: string;
```

Richtig:

```pascal
threadvar
  LetzteMeldung: PChar;
```
