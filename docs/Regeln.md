# Prüfregeln

Erzeugt von `Tools/Update-RuleCatalog.ps1` aus dem Regelkatalog. Nicht von Hand ändern.

## Gruppen

| Gruppe | Regeln |
|---|---|
| [Fehler finden](#gruppe-find-bugs) | 56 |
| [Exceptions](#gruppe-exceptions) | 8 |
| [Threads](#gruppe-threads) | 13 |
| [Datenbank](#gruppe-database) | 4 |
| [Compiler vorab](#gruppe-compiler) | 18 |
| [Robustheit und Muster](#gruppe-robustness) | 3 |
| [Performance](#gruppe-performance) | 4 |
| [Sicherheit](#gruppe-security) | 11 |
| [Komponenten](#gruppe-components) | 8 |
| [Formulare und Daten](#gruppe-forms) | 10 |
| [Architektur](#gruppe-architecture) | 3 |
| [Stil und Metriken](#gruppe-style) | 28 |
| [Packages und Tests](#gruppe-packages) | 3 |
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
| [`pchar-of-temporary`](#pchar-of-temporary) | PChar auf einen temporären String | Bug | Warnung |
| [`out-param-read`](#out-param-read) | out-Parameter gelesen, bevor er gesetzt ist | Bug | Warnung |
| [`stringlist-unsorted`](#stringlist-unsorted) | Find oder Duplicates auf einer unsortierten TStringList | Bug | Warnung |
| [`writeln-in-gui-app`](#writeln-in-gui-app) | Writeln in einem Programm ohne Konsole | Bug | Warnung |
| [`duplicate-condition`](#duplicate-condition) | Doppelte Bedingung oder gleiche Zweige | Bug | Warnung |
| [`case-missing-enum-value`](#case-missing-enum-value) | case über Aufzählung ohne alle Werte | Bug | Warnung |
| [`pair-without-finally`](#pair-without-finally) | Paarige Aufrufe ohne try/finally | Bug | Warnung |
| [`unchecked-conversion`](#unchecked-conversion) | Umwandlung einer Benutzereingabe ohne Prüfung | Bug | Hinweis |
| [`dictionary-get-without-check`](#dictionary-get-without-check) | Dictionary-Zugriff ohne Prüfung des Schlüssels | Bug | Hinweis |
| [`event-call-without-assigned`](#event-call-without-assigned) | Ereignis ohne Assigned-Prüfung aufgerufen | Bug | Warnung |
| [`owned-item-freed`](#owned-item-freed) | Element einer besitzenden Liste zusätzlich freigegeben | Bug | Fehler |
| [`create-without-assignment`](#create-without-assignment) | Objekt erzeugt und sofort verloren | Bug | Warnung |
| [`message-handler-without-inherited`](#message-handler-without-inherited) | Message-Handler ohne inherited | Bug | Warnung |
| [`string-index-base`](#string-index-base) | String-Index ab 0 oder Pos-Ergebnis mit -1 verglichen | Bug | Warnung |
| [`delimited-text-without-strict`](#delimited-text-without-strict) | DelimitedText ohne StrictDelimiter | Bug | Warnung |
| [`self-as-interface-in-constructor`](#self-as-interface-in-constructor) | Self während der Konstruktion als Interface weitergegeben | Bug | Warnung |
| [`unchecked-enum-cast`](#unchecked-enum-cast) | Zahl ungeprüft in Aufzählung umgewandelt | Bug | Hinweis |
| [`createprocess-readonly-commandline`](#createprocess-readonly-commandline) | CreateProcess mit unveränderlicher Befehlszeile | Bug | Fehler |
| [`form-access-before-create`](#form-access-before-create) | Zugriff auf ein Formular, das noch nicht erzeugt ist | Bug | Warnung |

<a id="gruppe-exceptions"></a>
### Exceptions

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`empty-except`](#empty-except) | Leerer except-Block | Code Smell | Warnung |
| [`generic-exception-raised`](#generic-exception-raised) | Allgemeine Exception ausgelöst | Code Smell | Hinweis |
| [`catch-all-without-raise`](#catch-all-without-raise) | Exception-Handler ohne erneutes raise | Code Smell | Warnung |
| [`exception-freed`](#exception-freed) | Exception-Objekt manuell freigegeben | Bug | Fehler |
| [`raise-in-finally`](#raise-in-finally) | raise in einem finally-Block | Bug | Warnung |
| [`exception-in-destructor`](#exception-in-destructor) | raise im Destruktor | Bug | Warnung |
| [`except-handler-order`](#except-handler-order) | Allgemeiner Exception-Handler vor speziellem | Bug | Warnung |
| [`reraise-exception-object`](#reraise-exception-object) | raise E statt raise im Handler | Code Smell | Warnung |

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
| [`processmessages-in-loop`](#processmessages-in-loop) | Application.ProcessMessages in Schleifen | Code Smell | Hinweis |
| [`queue-nil-in-package`](#queue-nil-in-package) | TThread.Queue(nil, …) in einem Package | Bug | Warnung |
| [`blocking-call-in-main-thread`](#blocking-call-in-main-thread) | Blockierender Aufruf im Hauptthread | Code Smell | Warnung |
| [`thread-loop-without-terminated`](#thread-loop-without-terminated) | Thread-Schleife ohne Terminated | Bug | Warnung |
| [`anonymous-thread-not-started`](#anonymous-thread-not-started) | Anonymer Thread nie gestartet | Bug | Warnung |
| [`task-exception-unobserved`](#task-exception-unobserved) | Exception in TTask geht verloren | Code Smell | Hinweis |

<a id="gruppe-database"></a>
### Datenbank

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`dataset-loop-without-next`](#dataset-loop-without-next) | Datenmengen-Schleife ohne Next | Bug | Fehler |
| [`dataset-edit-without-post`](#dataset-edit-without-post) | Edit oder Append ohne Post | Bug | Warnung |
| [`transaction-without-rollback`](#transaction-without-rollback) | Transaktion ohne Rollback | Bug | Warnung |
| [`sql-write-without-where`](#sql-write-without-where) | UPDATE oder DELETE ohne WHERE | Bug | Warnung |

<a id="gruppe-compiler"></a>
### Compiler vorab

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`signature-mismatch`](#signature-mismatch) | Implementierung weicht von der Deklaration ab | Bug | Fehler |
| [`interface-not-implemented`](#interface-not-implemented) | Interface-Methode fehlt in der Klasse | Bug | Fehler |
| [`uses-unit-not-found`](#uses-unit-not-found) | Unit in uses nicht gefunden | Bug | Fehler |
| [`unresolved-attribute`](#unresolved-attribute) | Attribut nicht gefunden und still ignoriert | Bug | Fehler |
| [`comparison-as-statement`](#comparison-as-statement) | Vergleich statt Zuweisung als Anweisung | Bug | Fehler |
| [`duplicate-case-label`](#duplicate-case-label) | Doppelte case-Marke | Bug | Fehler |
| [`field-after-method`](#field-after-method) | Feld nach Methoden im selben Abschnitt | Bug | Fehler |
| [`overload-directive-missing`](#overload-directive-missing) | Überladung ohne overload oder mit gleicher Signatur | Bug | Fehler |
| [`duplicate-declaration`](#duplicate-declaration) | Bezeichner doppelt deklariert | Bug | Fehler |
| [`conditional-directive-unbalanced`](#conditional-directive-unbalanced) | Bedingte Direktiven unvollständig oder unbekannt | Bug | Fehler |
| [`override-target-missing`](#override-target-missing) | override ohne passende virtuelle Methode | Bug | Fehler |
| [`abstract-class-instantiated`](#abstract-class-instantiated) | Instanz einer Klasse mit abstrakten Methoden | Bug | Warnung |
| [`property-accessor-invalid`](#property-accessor-invalid) | Getter oder Setter einer Property ungültig | Bug | Fehler |
| [`assign-to-property-member`](#assign-to-property-member) | Zuweisung an ein Feld eines Property-Records | Bug | Fehler |
| [`readonly-property-assigned`](#readonly-property-assigned) | Zuweisung an eine Property ohne write | Bug | Fehler |
| [`comparison-always-constant`](#comparison-always-constant) | Vergleich immer wahr oder immer falsch | Bug | Warnung |
| [`constant-initializer-mismatch`](#constant-initializer-mismatch) | Initialisierung einer Konstanten passt nicht | Bug | Fehler |
| [`case-selector-not-ordinal`](#case-selector-not-ordinal) | case oder for ohne ordinalen Typ | Bug | Fehler |

<a id="gruppe-robustness"></a>
### Robustheit und Muster

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`random-without-randomize`](#random-without-randomize) | Random ohne Randomize | Code Smell | Hinweis |
| [`format-without-settings`](#format-without-settings) | Formatierung abhängig vom Gebietsschema | Code Smell | Hinweis |
| [`null-compare`](#null-compare) | Vergleich mit Null statt VarIsNull oder IsNull | Code Smell | Warnung |

<a id="gruppe-performance"></a>
### Performance

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`string-concat-in-loop`](#string-concat-in-loop) | String-Verkettung in einer Schleife | Code Smell | Hinweis |
| [`loop-invariant-call`](#loop-invariant-call) | Teurer Aufruf in der Schleifenbedingung | Code Smell | Hinweis |
| [`missing-begin-update`](#missing-begin-update) | Hinzufügen in einer Schleife ohne BeginUpdate | Code Smell | Hinweis |
| [`case-insensitive-compare`](#case-insensitive-compare) | Vergleich über UpperCase oder LowerCase | Code Smell | Hinweis |

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
| [`shadowed-name`](#shadowed-name) | Lokaler Name verdeckt Feld oder Property | Code Smell | Hinweis |
| [`boolean-assign-if`](#boolean-assign-if) | if, das nur True oder False zuweist | Code Smell | Hinweis |
| [`magic-number`](#magic-number) | Zahl ohne Namen im Code | Code Smell | Hinweis |
| [`line-length`](#line-length) | Zeile zu lang | Code Smell | Hinweis |
| [`metric-class-size`](#metric-class-size) | Klasse mit zu vielen Membern | Code Smell | Hinweis |
| [`metric-unit-length`](#metric-unit-length) | Unit zu lang | Code Smell | Hinweis |
| [`metric-uses-count`](#metric-uses-count) | Zu viele Units im uses | Code Smell | Hinweis |
| [`public-field`](#public-field) | Öffentliches Feld | Code Smell | Hinweis |
| [`global-variable`](#global-variable) | Globale Variable im interface | Code Smell | Hinweis |
| [`commented-out-code`](#commented-out-code) | Auskommentierter Code | Code Smell | Hinweis |

<a id="gruppe-packages"></a>
### Packages und Tests

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`implicit-package-import`](#implicit-package-import) | Implizit eingebundene Unit | Code Smell | Warnung |
| [`ota-notifier-not-removed`](#ota-notifier-not-removed) | IDE-Notifier ohne RemoveNotifier | Bug | Warnung |
| [`dunitx-test-without-assert`](#dunitx-test-without-assert) | DUnitX-Test ohne Assert | Code Smell | Hinweis |

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

Eine Methode ist in einer Klasse, einem Record oder Objekt deklariert, hat aber keinen Rumpf im implementation-Abschnitt. Der Compiler meldet das erst beim Kompilieren (E2065). Einen Rumpf gleichen Namens mit anderem Kopf meldet stattdessen signature-mismatch.

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

Ein Methodenrumpf TFoo.Bar hat keine Deklaration dieses Namens im Typ. Eine gleichnamige Deklaration mit anderem Kopf meldet stattdessen signature-mismatch.

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

<a id="pchar-of-temporary"></a>
### pchar-of-temporary

**PChar auf einen temporären String** · Bug · Warnung · Gruppe Fehler finden

PChar (PWideChar, PAnsiChar) eines temporären Strings, etwa einer Verkettung mit einem String (S + '.bak') oder eines Funktionsergebnisses (IntToStr(N)), wird in einer Variablen, einem Feld oder Result gemerkt oder an PostMessage, PostThreadMessage, SendNotifyMessage oder SendMessageCallback übergeben (auch hinter LPARAM(…)). Der temporäre String wird nach der Anweisung freigegeben, der Zeiger zeigt dann ins Leere. Die Übergabe an einen gewöhnlichen Aufruf wie CopyFile ist in Ordnung. Konfidenz hoch. Schnellkorrektur für lokale Variablen: das Zwischenergebnis in eine Inline-String-Variable legen.

Mit Treffer:

```pascal
Ziel := PChar(Pfad + '.bak');
CopyFile(PChar(Pfad), Ziel, False);
```

Richtig:

```pascal
var ZielText: string := Pfad + '.bak';
Ziel := PChar(ZielText);
CopyFile(PChar(Pfad), Ziel, False);
```

<a id="out-param-read"></a>
### out-param-read

**out-Parameter gelesen, bevor er gesetzt ist** · Bug · Warnung · Gruppe Fehler finden

Ein out-Parameter wird auf einem Weg durch den Kontrollfluss gelesen, bevor die Routine ihn setzt. Bei verwalteten Typen (string, Interfaces, dynamische Arrays, Variant) hat der Aufrufer ihn schon geleert, der alte Wert ist weg; bei anderen Typen ist der Wert undefiniert. Gemeint war meist var. Verwendungen, denen der Kontrollflussgraph nicht folgen kann (Übergabe an eine Routine, Setzen eines Felds, @Param), bleiben still. Konfidenz hoch. Schnellkorrektur: aus out wird var in Implementierung und Deklaration.

Mit Treffer:

```pascal
procedure Anhaengen(out Text: string);
begin
  Text := Text + sLineBreak + 'Ende';
end;
```

Richtig:

```pascal
procedure Anhaengen(var Text: string);
begin
  Text := Text + sLineBreak + 'Ende';
end;
```

<a id="stringlist-unsorted"></a>
### stringlist-unsorted

**Find oder Duplicates auf einer unsortierten TStringList** · Bug · Warnung · Gruppe Fehler finden

Find auf einer TStringList oder THashedStringList, die in der Unit erzeugt, aber nie sortiert wird: Find sucht binär und liefert auf einer unsortierten Liste falsche Ergebnisse. Ebenso wirkt Duplicates := dupIgnore oder dupError nur bei sortierten Listen. Als sortiert gelten Sorted := True (oder jeder Wert außer False), Sort, CustomSort, Create(Duplicates, True, ...) und with Liste do. Eine Liste, die an eine Routine übergeben oder einer anderen Variablen zugewiesen wird, bleibt still. Lokale Variablen gelten je Routine, Felder in der ganzen Unit. Konfidenz mittel. Schnellkorrekturen: Sorted := True nach dem Erzeugen (nicht, wenn die Liste Insert, Move oder Exchange benutzt, die bei sortierten Listen eine Ausnahme auslösen) und bei if Liste.Find(S, I) then die Form I := Liste.IndexOf(S) mit if I >= 0.

Mit Treffer:

```pascal
Namen := TStringList.Create;
Namen.LoadFromFile(Datei);
if Namen.Find(Suche, Index) then
  Namen.Delete(Index);
```

Richtig:

```pascal
Namen := TStringList.Create;
Namen.Sorted := True;
Namen.LoadFromFile(Datei);
if Namen.Find(Suche, Index) then
  Namen.Delete(Index);
```

<a id="writeln-in-gui-app"></a>
### writeln-in-gui-app

**Writeln in einem Programm ohne Konsole** · Bug · Warnung · Gruppe Fehler finden

Write, Writeln, Read oder Readln auf die Standardein- oder -ausgabe in einem Programm ohne Konsole: zur Laufzeit löst Writeln EInOutError aus (E/A-Fehler 105), Readln E/A-Fehler 104. Die Anwendungsart kommt aus DCC_ConsoleTarget der .dproj und {$APPTYPE CONSOLE} der .dpr (auch in {$IFDEF}); Units werden nur geprüft, wenn sie zum geladenen Projekt gehören, eine .dpr ohne Projekt für sich. Bibliotheken und Packages bleiben still. Ausgenommen sind Aufrufe mit einer Textdatei als erstem Argument, Aufrufe unter if IsConsole, gleichnamige Routinen der Unit und Read/Write in Methoden (TStream.Read). Konfidenz hoch. Schnellkorrektur für Write und Writeln: Ersatz durch OutputDebugString(PChar(...)) und Winapi.Windows im uses; Zahlen und Boolean über IntToStr, FloatToStr und BoolToStr. Die Option replacement setzt ein anderes Ziel, z. B. Log.Info oder Logger.Log(TLogLevel.Info, %s). Keine Korrektur bei Breitenangaben (X:5) oder Argumenten unbekannten Typs.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `replacement` | string | `"OutputDebugString"` | Ersatz für Write und Writeln in der Schnellkorrektur; %s steht für den Text. |

Mit Treffer:

```pascal
procedure TfrmHaupt.btnStartClick(Sender: TObject);
begin
  Writeln('Start: ', TimeToStr(Now));
end;
```

Richtig:

```pascal
procedure TfrmHaupt.btnStartClick(Sender: TObject);
begin
  OutputDebugString(PChar('Start: ' + TimeToStr(Now)));
end;
```

<a id="exception-in-destructor"></a>
### exception-in-destructor

**raise im Destruktor** · Bug · Warnung · Gruppe Exceptions

raise in einem Destruktor (auch class destructor), das kein except im Destruktor abfängt. Die Ausnahme bricht die Freigabe ab: inherited Destroy läuft nicht mehr, das Objekt bleibt halb freigegeben, und in einem finally des Aufrufers überdeckt sie die ursprüngliche Ausnahme. Ein raise im try-Teil eines try..except ist abgefangen; raise im except- oder finally-Teil, auch ein erneutes raise;, wird gemeldet. Eingebettete Routinen und anonyme Methoden sind ausgenommen. Aufrufen, die ihrerseits auslösen, folgt die Regel nicht. Konfidenz hoch. Keine Schnellkorrektur: den Zustand protokollieren oder ohne Ausnahme freigeben.

Mit Treffer:

```pascal
destructor TSitzung.Destroy;
begin
  if FOffen then
    raise ESitzung.Create('Sitzung noch offen');
  inherited;
end;
```

Richtig:

```pascal
destructor TSitzung.Destroy;
begin
  if FOffen then
    Schliessen;
  inherited;
end;
```

<a id="duplicate-condition"></a>
### duplicate-condition

**Doppelte Bedingung oder gleiche Zweige** · Bug · Warnung · Gruppe Fehler finden

Dieselbe Bedingung zweimal in einer if … else if-Kette (der spätere Zweig wird nie erreicht), gleiche then- und else-Zweige, derselbe Operand zweimal in einer and-, or- oder xor-Kette und Vergleiche eines Ausdrucks mit sich selbst (X = X, X < X). Meist ein Kopierfehler. Verglichen werden die Token ohne Leerraum, Kommentare und Groß-/Kleinschreibung. Ketten mit Aufrufen, die Zustand ändern können (alles außer SameText, Length, Assigned, Pos und ähnlichen reinen Funktionen, dazu Read, Next, Pop, Random …), bleiben still, ebenso Gleitkomma-Vergleiche mit sich selbst (NaN-Prüfung X <> X) und Vergleiche über Klassenmitglieder wie TFoo.Shared = TFoo.Shared. Konfidenz hoch. Keine Schnellkorrektur; die Aktion springt zum ersten Vorkommen.

Mit Treffer:

```pascal
if Betrag > 1000 then
  Stufe := 3
else if Betrag > 500 then
  Stufe := 2
else if Betrag > 1000 then
  Stufe := 1;
```

Richtig:

```pascal
if Betrag > 1000 then
  Stufe := 3
else if Betrag > 500 then
  Stufe := 2
else if Betrag > 100 then
  Stufe := 1;
```

<a id="case-missing-enum-value"></a>
### case-missing-enum-value

**case über Aufzählung ohne alle Werte** · Bug · Warnung · Gruppe Fehler finden

Ein case über einen Aufzählungstyp ohne else deckt nicht alle Werte ab; ein später ergänzter Wert fällt still durch. Die Meldung nennt die fehlenden Werte. Den Typ des Selektors (Variable, Parameter, Feld oder Kette A.B) liefert die Namensauflösung, die Werte der Index bzw. die Unit selbst; Aliase werden verfolgt. Bereiche (bsNeu..bsBezahlt) und Listen zählen als vorhanden. Selektoren mit Aufrufen, Ganzzahlen und unbekannte Typen bleiben still. Mit der Option requireElse wird auch ein case mit else gemeldet. Konfidenz hoch. Schnellkorrektur „Fehlende Werte ergänzen (n)“ ergänzt leere Zweige in Deklarationsreihenfolge vor else bzw. end, mit Typpräfix, wenn die Marken einen tragen ({$SCOPEDENUMS ON}).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `requireElse` | boolean | `false` | Auch case-Anweisungen mit else melden, wenn Werte fehlen. |

Mit Treffer:

```pascal
case Bestellung.Status of
  bsNeu: Anlegen;
  bsBezahlt: Versenden;
end;
```

Richtig:

```pascal
case Bestellung.Status of
  bsNeu: Anlegen;
  bsBezahlt: Versenden;
  bsStorniert: ;
  bsZurueck: ;
end;
```

<a id="pair-without-finally"></a>
### pair-without-finally

**Paarige Aufrufe ohne try/finally** · Bug · Warnung · Gruppe Fehler finden

Verallgemeinert lock-without-finally (dessen Sperrpaare dort bleiben) auf andere Paare: DisableControls/EnableControls, BeginUpdate/EndUpdate, FindFirst/FindClose (auch in if FindFirst(...) = 0 then begin ... end), Reset, Rewrite oder Append/CloseFile, GetMem oder AllocMem/FreeMem und Screen.Cursor := ... mit einem späteren Screen.Cursor := .... Gemeldet wird, wenn das Schließen später ungeschützt in derselben Anweisungsliste steht und mindestens eine Anweisung dazwischen liegt; eine Exception dort lässt den Zustand hängen. Beide Aufrufe müssen denselben Empfänger bzw. dasselbe Argument haben. Überlappende Paare meldet die Regel zusammen. Konfidenz hoch. Schnellkorrektur: die Anweisungen dazwischen in try/finally mit den schließenden Aufrufen einschließen, wenn diese direkt aufeinander folgen. Die Option pairs ergänzt eigene Paare.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `pairs` | json | `[]` | Weitere Paare als [{"open": "Einfrieren", "close": "Auftauen"}], wahlweise mit openArg/closeArg. |

Mit Treffer:

```pascal
Screen.Cursor := crHourGlass;
Tabelle.DisableControls;
Importieren;
Tabelle.EnableControls;
Screen.Cursor := crDefault;
```

Richtig:

```pascal
Screen.Cursor := crHourGlass;
Tabelle.DisableControls;
try
  Importieren;
finally
  Tabelle.EnableControls;
  Screen.Cursor := crDefault;
end;
```

<a id="processmessages-in-loop"></a>
### processmessages-in-loop

**Application.ProcessMessages in Schleifen** · Code Smell · Hinweis · Gruppe Threads

Application.ProcessMessages in einer for-, while- oder repeat-Schleife oder direkt in einem Ereignis-Handler (Methode mit Parameter Sender) öffnet die Tür für Wiedereintritt: Der Benutzer klickt erneut, schließt das Formular oder startet den Vorgang doppelt. Aufrufe in anonymen Methoden überlässt die Regel thread-vcl-access; ProcessMessages anderer Objekte zählt nicht. Konfidenz mittel, keine Schnellkorrektur: die Arbeit in einen Thread oder TTask auslagern oder den Auslöser bis zum Ende sperren. Die Option allowIn nennt Methoden, in denen es erlaubt ist.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `allowIn` | string-list | `[]` | Methoden, in denen ProcessMessages erlaubt ist, als Name oder Klasse.Name. |

Mit Treffer:

```pascal
while not Done do
begin
  Step;
  Application.ProcessMessages;
end;
```

Richtig:

```pascal
StartButton.Enabled := False;
TTask.Run(
  procedure
  begin
    while not Done do
      Step;
    TThread.Queue(nil, procedure begin StartButton.Enabled := True; end);
  end);
```

<a id="unchecked-conversion"></a>
### unchecked-conversion

**Umwandlung einer Benutzereingabe ohne Prüfung** · Bug · Hinweis · Gruppe Fehler finden

StrToInt, StrToInt64, StrToFloat, StrToDate, StrToDateTime oder StrToCurr direkt auf einer Benutzereingabe (Edit.Text, Grid.Cells[...], Memo.Lines[...], auch in Trim) außerhalb des try-Teils eines try/except. Eine Fehleingabe löst EConvertError mit englischer Meldung aus. try/finally gilt nicht als Schutz. Konfidenz mittel. Schnellkorrektur für X := StrToInt(Edit.Text); als eigene Anweisung, wenn X eine Variable oder ein Feld des passenden Typs ist: if not TryStrToInt(Edit.Text, X) then raise EConvertError.Create('X ist keine Zahl'). format-without-settings meldet zusätzlich landesabhängige Umwandlungen ohne TFormatSettings. Die Optionen functions und sources wählen die geprüften Umwandlungen und die Eigenschaften, die als Eingabe gelten.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `functions` | string-list | `["StrToInt","StrToInt64","StrToFloat","StrToDate","StrToDateTime","StrToCurr"]` | Geprüfte Umwandlungen. |
| `sources` | string-list | `["Text","Cells","Lines"]` | Eigenschaften, die als Benutzereingabe gelten. |

Mit Treffer:

```pascal
Menge := StrToInt(edtMenge.Text);
```

Richtig:

```pascal
if not TryStrToInt(edtMenge.Text, Menge) then
  raise EConvertError.Create('Menge ist keine Zahl');
```

<a id="dictionary-get-without-check"></a>
### dictionary-get-without-check

**Dictionary-Zugriff ohne Prüfung des Schlüssels** · Bug · Hinweis · Gruppe Fehler finden

Dict[Key] bzw. Dict.Items[Key] wird auf einem TDictionary oder TObjectDictionary (auch über einen Typalias der Datei) gelesen, obwohl weder ContainsKey noch TryGetValue denselben Schlüssel vorher in der Routine geprüft hat. Still bleibt die Regel, wenn die Routine das Dictionary vorher selbst füllt (Add, AddOrSetValue, TryAdd, Dict[K] := ...) oder der Schlüssel aus Keys bzw. den Paaren stammt (for K in Dict.Keys, Namen := Dict.Keys.ToArray, for Pair in Dict mit K := Pair.Key). Fehlt der Schlüssel, folgt EListError. Konfidenz mittel. Schnellkorrektur für X := Dict[Key]; als eigene Anweisung, wenn X eine Variable vom Wertetyp ist: if not Dict.TryGetValue(Key, X) then X := 0 (bzw. '', False, Default(T)).

Mit Treffer:

```pascal
Preis := Preise[Artikel.Nummer];
```

Richtig:

```pascal
if not Preise.TryGetValue(Artikel.Nummer, Preis) then
  Preis := 0;
```

<a id="shadowed-name"></a>
### shadowed-name

**Lokaler Name verdeckt Feld oder Property** · Code Smell · Hinweis · Gruppe Stil und Metriken

Ein Parameter, eine lokale oder Inline-Variable heißt wie ein Feld oder eine Property der Klasse (auch geerbt und dort sichtbar, aufgelöst über die Datei und den Symbolindex) oder wie eine globale Variable der Unit, die vor der Routine deklariert ist. In Formularmethoden besonders tückisch: Caption, Name, Tag, Left. Steht die VCL nicht im Index, kennt die Regel die Mitglieder von TComponent und TControl, wenn die Vorfahrenkette an einer VCL-Grundklasse endet. Parameter von Ereignis-Handlern (mit Sender) bleiben außen vor, weil der Ereignistyp die Signatur vorgibt. Konfidenz hoch. Schnellkorrektur: in der Routine in AName (Parameter, auch in der Deklaration) bzw. LName (lokale Variable) umbenennen. Die Option ignore nennt Namensmuster, die nie gemeldet werden (Vorgabe Sender, Value).

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `ignore` | string-list | `["Sender","Value"]` | Namensmuster (* und ?), die nie gemeldet werden. |

Mit Treffer:

```pascal
procedure TfrmKunde.Laden(const Caption: string);
begin
  Caption := Caption + ' (geladen)';
end;
```

Richtig:

```pascal
procedure TfrmKunde.Laden(const ACaption: string);
begin
  Caption := ACaption + ' (geladen)';
end;
```

<a id="boolean-assign-if"></a>
### boolean-assign-if

**if, das nur True oder False zuweist** · Code Smell · Hinweis · Gruppe Stil und Metriken

if B then X := True else X := False (auch mit begin/end und vertauschten Werten), if B then Exit(True) else Exit(False) sowie if B then Exit(True); gefolgt von Exit(False); lassen sich direkt schreiben. Ergänzt bool-compare. Konfidenz hoch. Schnellkorrektur: X := B, X := not B bzw. Exit(B); Verneinungen werden vereinfacht (aus not B wird B), zusammengesetzte Bedingungen eingeklammert. Ohne Korrektur, wenn Kommentare im if stehen.

Mit Treffer:

```pascal
if Betrag > 0 then
  Result := True
else
  Result := False;
```

Richtig:

```pascal
Result := Betrag > 0;
```

<a id="case-insensitive-compare"></a>
### case-insensitive-compare

**Vergleich über UpperCase oder LowerCase** · Code Smell · Hinweis · Gruppe Performance

UpperCase(A) = UpperCase(B), LowerCase(A) <> 'x', AnsiUpperCase(...) oder A.ToUpper = B.ToUpper erzeugt zwei Strings für einen Vergleich. SameText (AnsiSameText bei den Ansi-Funktionen und den Unicode-String-Helfern) ist kürzer und schneller. Ein Literal zählt nur, wenn die Umwandlung es nicht ändert; UpperCase(A) = LowerCase(B) und UpperCase(A) = 'ja' bleiben unberührt, weil das andere Fehler sind. Ersetzt nicht die String-Helper-Modernisierung aus #71. Konfidenz hoch. Schnellkorrektur: SameText(A, B) bzw. not SameText(A, B).

Mit Treffer:

```pascal
if UpperCase(Land) = UpperCase(Standard) then
```

Richtig:

```pascal
if SameText(Land, Standard) then
```

<a id="magic-number"></a>
### magic-number

**Zahl ohne Namen im Code** · Code Smell · Hinweis · Gruppe Stil und Metriken

Zahlenliterale (dezimal, $hex, Gleitkomma, mit Vorzeichen) in Anweisungen, außerhalb von const-Abschnitten, Typen, Array-Grenzen und Teilbereichen. Erlaubte Werte sind einstellbar; DFM-Koordinaten und Tests lassen sich über exclude ausnehmen. Standard aus und niedrige Konfidenz: Treffer erscheinen, wenn die Regel eingeschaltet und minConfidence low ist. Schnellkorrektur: Konstante einführen (#50) im const-Abschnitt der Routine.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `allowed` | number-list | `[0,1,-1,2,10,100]` | Zahlen, die nie gemeldet werden. |

Mit Treffer:

```pascal
if Tage > 42 then
  Mahnen;
```

Richtig:

```pascal
const
  Mahnfrist = 42;
...
if Tage > Mahnfrist then
  Mahnen;
```

<a id="line-length"></a>
### line-length

**Zeile zu lang** · Code Smell · Hinweis · Gruppe Stil und Metriken

Zeilen über der Grenze max (Vorgabe 120 Zeichen, passend zu den Linealen aus #710). Tabs zählen bis zur nächsten Tabstelle nach format.indentSize. Zeilen, die nur wegen eines Strings oder, mit ignoreComments, eines Kommentars zu lang sind, werden nicht gemeldet. Zeilen über 1023 Zeichen meldet die Regel unabhängig von max immer als Fehler, weil der Compiler dort abbricht (F2069). Standard aus. Schnellkorrektur: Zeile umbrechen hinter Kommas bzw. vor zweistelligen Operatoren, wenn die Stücke danach passen.

Entspricht der Compilermeldung `F2069`.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `120` | Höchstlänge einer Zeile in Zeichen. |
| `ignoreStrings` | boolean | `true` | Zeilen, die nur wegen eines Strings zu lang sind, nicht melden. |
| `ignoreComments` | boolean | `false` | Zeilen, die nur wegen eines Kommentars zu lang sind, nicht melden. |

Mit Treffer:

```pascal
Ergebnis := Rechner.Berechne(Kunde.Rabattstufe, Bestellung.Positionen, Lager.Verfuegbarkeit(Artikel), Steuer.Satz(Land));
```

Richtig:

```pascal
Ergebnis := Rechner.Berechne(Kunde.Rabattstufe, Bestellung.Positionen, Lager.Verfuegbarkeit(Artikel),
  Steuer.Satz(Land));
```

<a id="metric-class-size"></a>
### metric-class-size

**Klasse mit zu vielen Membern** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die Klasse hat mehr Member als der Grenzwert (Vorgabe 40): Feldnamen, Methoden, Properties mit eigenem Typ und class var. Properties, die nur die Sichtbarkeit anheben (property Align;), und geschachtelte Typen zählen nicht; eine geschachtelte Klasse wird für sich gemessen. Erscheint auch in der Metrik-Linse über der Klasse. Die Klasse aufteilen oder Teile in Hilfsklassen auslagern; „Klasse in eigene Unit verschieben“ (#103) hilft, wenn auch die Unit voll ist.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `40` | Höchstzahl der Member je Klasse. |

Mit Treffer:

```pascal
type
  TfrmHaupt = class(TForm)
    { 87 members }
  end;
```

Richtig:

```pascal
type
  TfrmHaupt = class(TForm)
    { 25 members; data access in TKundenDaten }
  end;
```

<a id="metric-unit-length"></a>
### metric-unit-length

**Unit zu lang** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die Unit hat mehr Zeilen als der Grenzwert (Vorgabe 2000), gezählt bis zum abschließenden end. Gemessen werden nur Units, keine Programme oder Packages. Erscheint auch in der Metrik-Linse über dem Unit-Namen. Klassen mit „Klasse in eigene Unit verschieben“ (#103) auslagern.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `2000` | Höchstzahl der Zeilen je Unit. |

Mit Treffer:

```pascal
unit Kasse.Haupt;  { 2140 lines }
```

Richtig:

```pascal
unit Kasse.Haupt;  { 900 lines; TBeleg in Kasse.Beleg }
```

<a id="metric-uses-count"></a>
### metric-uses-count

**Zu viele Units im uses** · Code Smell · Hinweis · Gruppe Stil und Metriken

Die Unit bindet mehr Units ein als der Grenzwert (Vorgabe 30), interface und implementation zusammen. Der Befund steht auf dem ersten uses. Programme und Bibliotheken werden nicht geprüft, weil ihr uses die Units des Projekts aufzählt. Erscheint auch in der Metrik-Linse über uses. Viele Abhängigkeiten heißen meist, dass die Unit zu viel tut; „Klasse in eigene Unit verschieben“ (#103) teilt sie.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `max` | integer | `30` | Höchstzahl der Units in allen uses-Klauseln. |

Mit Treffer:

```pascal
uses
  { 34 units in interface and implementation }
```

Richtig:

```pascal
uses
  { 12 units; reports in Kasse.Berichte }
```

<a id="public-field"></a>
### public-field

**Öffentliches Feld** · Code Smell · Hinweis · Gruppe Stil und Metriken

Felder im public- oder published-Abschnitt einer Klasse. Der Abschnitt ohne Sichtbarkeitswort zählt nur bei Klassen ohne Vorfahren oder mit TObject, weil der Formulardesigner dort seine Felder anlegt. Records sind ausgenommen, außer mit includeRecords; class var wird nicht gemeldet. Standard aus. Schnellkorrektur: Feld kapseln legt das Feld als FName in einen private-Abschnitt am Ende der Klasse und ergänzt im alten Abschnitt property Name read FName write FName; Zugriffe von außen bleiben gültig.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `includeRecords` | boolean | `false` | Auch Felder von Records melden. |

Mit Treffer:

```pascal
TKunde = class
public
  Name: string;
end;
```

Richtig:

```pascal
TKunde = class
private
  FName: string;
public
  property Name: string read FName write FName;
end;
```

<a id="global-variable"></a>
### global-variable

**Globale Variable im interface** · Code Smell · Hinweis · Gruppe Stil und Metriken

var oder threadvar im interface-Teil einer Unit: Jede Unit, die sie einbindet, kann den Wert lesen und ändern. Die Formularvariable des Designers (frmHaupt: TfrmHaupt, bei Nachfahren von TForm, TFrame, TDataModule oder jeder Klasse einer Unit mit Formulardatei) ist ausgenommen, außer mit includeFormVariables. Standard aus. Die Variable in den implementation-Teil verschieben und eine Funktion oder Property anbieten.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `includeFormVariables` | boolean | `false` | Auch die Formularvariablen des Designers melden. |

Mit Treffer:

```pascal
interface
var
  AktuellerBenutzer: TBenutzer;
```

Richtig:

```pascal
interface
function AktuellerBenutzer: TBenutzer;
implementation
var
  GBenutzer: TBenutzer;
```

<a id="commented-out-code"></a>
### commented-out-code

**Auskommentierter Code** · Code Smell · Hinweis · Gruppe Stil und Metriken

Mindestens minLines aufeinanderfolgende Kommentarzeilen (// je Zeile oder ein mehrzeiliger { }-Kommentar), die sich als Anweisungen, Deklarationen oder Klassenmitglieder parsen lassen. Prosa am Anfang und Ende des Blocks bleibt außen vor, mindestens die Hälfte der Zeilen muss nach Code aussehen (;, :=, begin, end, then, do). XMLDoc (///) und Kommentare vor dem ersten Token (Lizenzköpfe) meldet die Regel nie. Sicherheit mittel. Die Versionsverwaltung bewahrt den alten Code auf; die Korrektur entfernt die Zeilen.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `minLines` | integer | `3` | Mindestzahl aufeinanderfolgender auskommentierter Codezeilen. |

Mit Treffer:

```pascal
Speichern;
// if Kunde.Aktiv then
//   Kunde.Speichern;
// Log('gespeichert');
```

Richtig:

```pascal
Speichern;
```

<a id="queue-nil-in-package"></a>
### queue-nil-in-package

**TThread.Queue(nil, …) in einem Package** · Bug · Warnung · Gruppe Threads

TThread.Queue(nil, …) oder TThread.ForceQueue(nil, …) in einer Unit eines Design-Time- oder Laufzeit-Packages: Der Eintrag gehört keinem Thread, beim Entladen des Packages räumt ihn niemand weg, und CheckSynchronize ruft ihn womöglich danach in fremdem Speicher auf. Package-Units erkennt die Regel über die .dpk bzw. .dproj des geladenen Projekts (eine .dpk ohne Projekt für sich). Eine Zeile mit dem Kommentar aus okMarker (Vorgabe mainthread-ok) ist ausgenommen. Sicherheit hoch. Korrektur: auf den Wrapper aus der Option wrapper umschreiben (Vorgabe TAtlasMainThread.Queue, bei ForceQueue ForceQueue); mit Klammer steht der Text so vor den übrigen Argumenten. ForceQueue mit Verzögerung bekommt keine Korrektur. Der Kommandozeilen-Linter liest die .dpk-Dateien unter dem geprüften Ordner. Leistet für jedes Plugin-Projekt dasselbe wie Tools/Check-MainThreadQueue.ps1; das Skript bleibt für Prüfungen ohne Atlas-Server.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `wrapper` | string | `"TAtlasMainThread.Queue"` | Ersatz für TThread.Queue(nil, in der Schnellkorrektur. |
| `okMarker` | string | `"mainthread-ok"` | Kommentar, der eine Zeile ausnimmt. |

Mit Treffer:

```pascal
TThread.Queue(nil,
  procedure
  begin
    FPanel.Aktualisieren;
  end);
```

Richtig:

```pascal
TAtlasMainThread.Queue(
  procedure
  begin
    FPanel.Aktualisieren;
  end);
```

<a id="ota-notifier-not-removed"></a>
### ota-notifier-not-removed

**IDE-Notifier ohne RemoveNotifier** · Bug · Warnung · Gruppe Packages und Tests

AddNotifier an IOTAServices, IOTAEditorServices, IOTAModule usw. (oder ein anderes Paar aus registerPairs), dessen Index nie an RemoveNotifier geht: Der Aufruf steht als Anweisung ohne Zuweisung, oder die Variable, der er zugewiesen wird, erhält in der Unit kein RemoveNotifier (in finalization, im Destruktor oder in Destroyed). Die IDE ruft den Notifier dann nach dem Entladen des Packages in fremdem Speicher auf. Register…-Aufrufe in der Prozedur Register sind ausgenommen: Diese Wizards entfernt die IDE selbst. Sicherheit mittel. Korrektur in Methoden: Index in ein Feld legen (FNotifierIndex im private-Abschnitt) und RemoveNotifier im Destruktor ergänzen, der bei Bedarf angelegt wird; in Prozeduren der Unit: globale Variable mit -1 und RemoveNotifier in finalization. Keine Korrektur, wenn der Empfänger ein Parameter oder eine lokale Variable ist.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `registerPairs` | json | `[{"open":"AddNotifier","close":"RemoveNotifier"},{"open":"RegisterPackageWizard","close":"RemoveWizard"}]` | Paare der Open Tools API als [{"open": "AddNotifier", "close": "RemoveNotifier"}]; ersetzt die Vorgabe. |

Mit Treffer:

```pascal
procedure Register;
begin
  (BorlandIDEServices as IOTAServices).AddNotifier(TSpeicherNotifier.Create);
end;
```

Richtig:

```pascal
var
  NotifierIndex: Integer = -1;

procedure Register;
begin
  NotifierIndex := (BorlandIDEServices as IOTAServices).AddNotifier(TSpeicherNotifier.Create);
end;

initialization

finalization
  if NotifierIndex >= 0 then
    (BorlandIDEServices as IOTAServices).RemoveNotifier(NotifierIndex);
```

<a id="dunitx-test-without-assert"></a>
### dunitx-test-without-assert

**DUnitX-Test ohne Assert** · Code Smell · Hinweis · Gruppe Packages und Tests

Eine [Test]- oder [TestCase]-Methode, die keine Prüfung aufruft, weder selbst noch über Methoden derselben Klasse oder Routinen der Unit: Sie ist immer grün. Als Prüfung zählen Aufrufe nach assertPatterns (Vorgabe Assert.*, WillRaise*, Check*), System.Assert und Aufrufe an Klassen mit Assert im Namen (TRuleAssert.Reports). Tests mit [WillRaise] oder [Ignore] bleiben still. Sicherheit hoch. Korrekturen: Assert.Pass als Platzhalter einfügen oder zur Methode springen.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `assertPatterns` | string-list | `["Assert.*","WillRaise*","Check*"]` | Aufrufe, die als Prüfung zählen, als Muster mit * und ?; ersetzt die Vorgabe. |

Mit Treffer:

```pascal
[Test]
procedure TImportTests.LeereDateiWirdGelesen;
begin
  FImport.Laden('leer.csv');
end;
```

Richtig:

```pascal
[Test]
procedure TImportTests.LeereDateiWirdGelesen;
begin
  FImport.Laden('leer.csv');
  Assert.AreEqual(0, FImport.Anzahl);
end;
```

<a id="event-call-without-assigned"></a>
### event-call-without-assigned

**Ereignis ohne Assigned-Prüfung aufgerufen** · Bug · Warnung · Gruppe Fehler finden

FOnChange(Self) oder OnChange(Self) wird in einer Methode der Klasse aufgerufen, ohne dass Assigned(FOnChange) oder FOnChange <> nil den Aufruf schützt: Ohne Handler folgt eine Zugriffsverletzung. Ereignisse sind Felder und Properties der Klasse mit Methodenzeiger- oder Referenztyp (procedure … of object, reference to …, TNotifyEvent, TProc/TFunc, Typen auf Event, prozedurale Typen der Unit oder des Index). Schutz: der then-Zweig einer Bedingung mit Assigned (auch while), der else-Zweig von not Assigned, "Assigned(F) and" vor dem Aufruf oder "if not Assigned(F) then Exit/raise" davor, auch über einen Merker oder eine Methode der Klasse ohne Parameter, deren Result Assigned(F) enthält. Still bleiben Felder, die ein Konstruktor mit einem Wert belegt (eingereichte Abhängigkeiten wie FReadText := AReadText), Properties darauf und gleichnamige lokale Namen. Sicherheit hoch. Korrektur: den Aufruf in "if Assigned(F) then" einschließen, wenn er als eigene Anweisung in einem Block steht.

Mit Treffer:

```pascal
procedure TZaehler.Erhoehen;
begin
  Inc(FWert);
  FOnChange(Self);
end;
```

Richtig:

```pascal
procedure TZaehler.Erhoehen;
begin
  Inc(FWert);
  if Assigned(FOnChange) then
    FOnChange(Self);
end;
```

<a id="owned-item-freed"></a>
### owned-item-freed

**Element einer besitzenden Liste zusätzlich freigegeben** · Bug · Fehler · Gruppe Fehler finden

Ein Element einer TObjectList/TObjectList<T> (OwnsObjects, Vorgabe True) oder eines TObjectDictionary mit doOwnsValues wird mit Free, FreeAndNil, Destroy oder DisposeOf freigegeben, direkt (Liste[I].Free, Liste.Items[I].Free) oder über eine Variable aus Liste[I], Liste.First/Last oder einer for-in-Schleife über die Liste bzw. Dictionary.Values. Die Liste gibt das Element selbst frei: bei Delete, Remove, Clear, einer Zuweisung an Liste[I] oder spätestens beim Freigeben, also doppelt. Besitzend ist eine Liste, wenn die Unit sie so erzeugt (TObjectList ohne False, TObjectDictionary mit doOwnsValues) oder ohne Erzeugung als TObjectList deklariert, und kein OwnsObjects := False folgt. Extract in derselben Routine lässt die Regel schweigen. Sicherheit hoch. Korrekturen: Free entfernen (die ganze Schleife, wenn sie nur freigibt), Delete bzw. Remove statt Free, Extract statt Remove.

Mit Treffer:

```pascal
Auftraege := TObjectList<TAuftrag>.Create;
…
Auftraege[I].Free;
Auftraege.Delete(I);
```

Richtig:

```pascal
Auftraege := TObjectList<TAuftrag>.Create;
…
Auftraege.Delete(I);
```

<a id="create-without-assignment"></a>
### create-without-assignment

**Objekt erzeugt und sofort verloren** · Bug · Warnung · Gruppe Fehler finden

TStringList.Create; als eigene Anweisung: Das Objekt wird erzeugt, aber nirgends gespeichert und nie freigegeben (Speicherleck). Still bleiben Komponenten mit Owner (erstes Argument Self, Owner, AOwner, Application oder ein Nachfahr von TComponent mit einem Argument ungleich nil), Threads (geben sich mit FreeOnTerminate selbst frei), Records, unbekannte Klassen mit Argumenten und Klassen aus selfRegistering. Sicherheit hoch. Korrektur: Zuweisung an eine neue lokale Variable, die folgenden Anweisungen des Blocks in try/finally mit Free.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `selfRegistering` | string-list | `[]` | Klassen, die sich im Konstruktor selbst registrieren, als Muster mit * und ?; Create als Anweisung bleibt für sie still. |

Mit Treffer:

```pascal
procedure TImport.Starten;
begin
  TImportProtokoll.Create;
  Laden;
end;
```

Richtig:

```pascal
procedure TImport.Starten;
var
  ImportProtokoll: TImportProtokoll;
begin
  ImportProtokoll := TImportProtokoll.Create;
  try
    Laden;
  finally
    ImportProtokoll.Free;
  end;
end;
```

<a id="message-handler-without-inherited"></a>
### message-handler-without-inherited

**Message-Handler ohne inherited** · Bug · Warnung · Gruppe Fehler finden

Eine Methode mit message WM_… oder CM_… ruft weder inherited noch DefaultHandler (bzw. DefWindowProc, CallWindowProc) auf. Die Standardbehandlung der VCL bzw. von Windows fällt weg: kein Neuausrichten bei WM_SIZE, kein Schließen bei WM_CLOSE, kein Zeichnen bei WM_PAINT. Die Meldung nennt für gängige Nachrichten die Folge. Still bleiben Klassen ohne Vorfahr, Nachrichten aus swallow (Vorgabe WM_ERASEBKGND) und Handler, die Msg.Result selbst setzen (bewusste Antwort wie MA_NOACTIVATE). Sicherheit mittel. Korrektur: inherited; am Anfang einfügen.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `swallow` | string-list | `["WM_ERASEBKGND"]` | Nachrichten, die ohne inherited behandelt werden dürfen; ersetzt die Vorgabe. |

Mit Treffer:

```pascal
procedure TfrmHaupt.WMSize(var Msg: TWMSize);
begin
  AnordnungAnpassen;
end;
```

Richtig:

```pascal
procedure TfrmHaupt.WMSize(var Msg: TWMSize);
begin
  inherited;
  AnordnungAnpassen;
end;
```

<a id="string-index-base"></a>
### string-index-base

**String-Index ab 0 oder Pos-Ergebnis mit -1 verglichen** · Bug · Warnung · Gruppe Fehler finden

Die klassischen String-Routinen zählen ab 1: Copy(S, 0, N) und Insert(T, S, 0) wirken nur zufällig wie 1, Delete(S, 0, N) löscht nichts. Der String muss bekannt sein: deklarierter Typ in der Datei, Literal oder .Text/.Caption; dynamische Arrays (ab 0) bleiben still. Pos, PosEx und AnsiPos liefern 0 bei keinem Treffer: Pos(…) > -1, >= 0 und <> -1 sind immer wahr, = -1 und < 0 nie. Umgekehrt übersieht S.IndexOf(…) > 0 bzw. >= 1 den Treffer am Anfang, < 1 bzw. <= 0 zählt ihn als nicht gefunden (Sicherheit mittel; LastIndexOf bleibt still, dort heißt > 0 meist „nicht am Anfang“). Sicherheit hoch für Delete und Pos. Korrektur: Startwert 1 bzw. der richtige Vergleich (> 0, = 0, >= 0, < 0).

Mit Treffer:

```pascal
if Pos(';', Zeile) > -1 then
  Felder := Copy(Zeile, 0, Pos(';', Zeile) - 1);
```

Richtig:

```pascal
if Pos(';', Zeile) > 0 then
  Felder := Copy(Zeile, 1, Pos(';', Zeile) - 1);
```

<a id="delimited-text-without-strict"></a>
### delimited-text-without-strict

**DelimitedText ohne StrictDelimiter** · Bug · Warnung · Gruppe Fehler finden

Liste.DelimitedText := … nach Liste.Delimiter := … in derselben Routine, ohne dass StrictDelimiter gesetzt wird: DelimitedText trennt dann auch an Leerzeichen, 'Max Muster;Berlin' ergibt drei statt zwei Einträge. Bei Feldern zählt StrictDelimiter in der ganzen Unit (oft im Konstruktor); StrictDelimiter := False ist bewusst und bleibt still, ebenso DelimitedText ohne eigenen Delimiter. Sicherheit hoch. Korrektur: StrictDelimiter := True; vor der Zuweisung einfügen.

Mit Treffer:

```pascal
Teile.Delimiter := ';';
Teile.DelimitedText := Zeile;
```

Richtig:

```pascal
Teile.Delimiter := ';';
Teile.StrictDelimiter := True;
Teile.DelimitedText := Zeile;
```

<a id="self-as-interface-in-constructor"></a>
### self-as-interface-in-constructor

**Self während der Konstruktion als Interface weitergegeben** · Bug · Warnung · Gruppe Fehler finden

Self wird als Interface weitergegeben, während die Referenzzählung das Objekt schon freigeben kann. Gemeldet werden nur zwei echte Fehlerfälle: (1) Eine Klasse mit eigener Referenzzählung (ein _Release in der Klassenkette gibt das Objekt frei, keine Klasse überschreibt NewInstance, die Kette ist bis TObject bekannt) gibt Self im Konstruktor oder in AfterConstruction als Interface weiter: Der Zähler steigt von 0 auf 1 und fällt wieder auf 0, das Objekt wird freigegeben, bevor die Konstruktion endet. (2) Ein Nachfahr von TInterfacedObject gibt Self in AfterConstruction nach inherited als Interface weiter: inherited AfterConstruction hat den Schutzzähler aus NewInstance schon abgebaut. Im Konstruktor eines TInterfacedObject-Nachfahren ist Self geschützt, die Regel bleibt still. Als Weitergabe zählen Self as IX, IX(Self), ein Argument, dessen Parameter in allen bekannten Überladungen ein Interface ist, und die Zuweisung an eine Interface-Variable. Sicherheit hoch. Korrektur in Fall 2: die Anweisung vor inherited verschieben.

Mit Treffer:

```pascal
procedure TBeobachter.AfterConstruction;
begin
  inherited;
  FQuelle.Anmelden(Self);
end;
```

Richtig:

```pascal
procedure TBeobachter.AfterConstruction;
begin
  FQuelle.Anmelden(Self);
  inherited;
end;
```

<a id="null-compare"></a>
### null-compare

**Vergleich mit Null statt VarIsNull oder IsNull** · Code Smell · Warnung · Gruppe Robustheit und Muster

X = Null bzw. X <> Null vergleicht einen Variant mit Null. Das Ergebnis hängt von der globalen Einstellung System.Variants.NullEqualityRule ab: Mit der Vorgabe ncrLoose vergleicht er wie erwartet, mit ncrStrict ist er nie wahr, mit ncrError löst er eine Exception aus. Eine Bibliothek, ein Testrahmen oder ein anderer Teil des Projekts kann die Einstellung ändern. VarIsNull(X) und Feld.IsNull prüfen unabhängig davon. Gemeldet wird nur, wo der Vergleich für sich steht (Bedingung, Argument, Zuweisung); not X = Null bindet als (not X) = Null und bekommt keine Korrektur. Sicherheit hoch. Korrektur: Feld.IsNull bei X.Value auf FieldByName, FindField, Fields[…], ParamByName, Params[…] oder einem Feld vom Typ T…Field/T…Param, sonst VarIsNull(X); bei <> mit not davor.

Mit Treffer:

```pascal
if qryKunde.FieldByName('Geburtstag').Value = Null then
  Alter := 0;
```

Richtig:

```pascal
if qryKunde.FieldByName('Geburtstag').IsNull then
  Alter := 0;
```

<a id="unchecked-enum-cast"></a>
### unchecked-enum-cast

**Zahl ungeprüft in Aufzählung umgewandelt** · Bug · Hinweis · Gruppe Fehler finden

TStatus(N) mit einem Aufzählungstyp aus der Datei oder dem Index, wenn N aus einem Aufruf der Option sources stammt (FieldByName, ReadInteger, AsInteger, StrToInt): direkt im Argument oder über eine Variable, die zwischen Zuweisung und Umwandlung nicht gelesen (geprüft) wird. Ein Wert außerhalb des Bereichs ergibt einen ungültigen Aufzählungswert, der in case durchfällt. EnsureRange, Min oder Max im Argument gelten als Prüfung; Konstanten, Rechnungen und unbekannte Typen bleiben still. Bei Aufzählungen mit eigenen Ordinalwerten nennt die Meldung den Bereich als Ord(Low(T))..Ord(High(T)). Sicherheit mittel. Korrektur bei direkter Quelle in einer eigenen Anweisung: Hilfsvariable, InRange-Prüfung mit raise EConvertError davor, System.Math in uses.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `sources` | string-list | `["FieldByName","ReadInteger","AsInteger","StrToInt"]` | Aufrufe, deren Ergebnis als ungeprüft gilt. |

Mit Treffer:

```pascal
Status := TStatus(qry.FieldByName('Status').AsInteger);
```

Richtig:

```pascal
Wert := qry.FieldByName('Status').AsInteger;
if not InRange(Wert, Ord(Low(TStatus)), Ord(High(TStatus))) then
  raise EConvertError.CreateFmt('Ungültiger Wert %d für TStatus', [Wert]);
Status := TStatus(Wert);
```

<a id="createprocess-readonly-commandline"></a>
### createprocess-readonly-commandline

**CreateProcess mit unveränderlicher Befehlszeile** · Bug · Fehler · Gruppe Fehler finden

CreateProcess (CreateProcessW) und CreateProcessAsUser schreiben in den Puffer von lpCommandLine. Ein PChar auf Speicher, der nicht beschreibbar ist, führt zu einer Zugriffsverletzung. Gemeldet wird PChar(…)/PWideChar(…) auf: ein String-Literal oder eine Konstante; eine Verkettung aus genau einem Literal und einem Wert (ist der Wert leer, liefert die RTL das Literal selbst); eine lokale String-Variable, deren letzte Zuweisung vor dem Aufruf eines davon ist, ohne UniqueString danach; einen String-Parameter (Sicherheit mittel, der Aufrufer kann ein Literal übergeben). Funktionsergebnisse wie Format und Verkettungen aus mehreren Teilen sind beschreibbare Heap-Strings und bleiben still, ebenso CreateProcessA, das die Befehlszeile selbst kopiert. Korrektur: Befehlszeile in eine lokale Variable kopieren und UniqueString aufrufen; bei einer Variablen UniqueString vor der Anweisung. In Schleifenbedingungen keine Korrektur.

Mit Treffer:

```pascal
CreateProcess(nil, PChar('notepad.exe ' + Datei), nil, nil, False, 0, nil, nil, SI, PI);
```

Richtig:

```pascal
Befehl := 'notepad.exe ' + Datei;
UniqueString(Befehl);
CreateProcess(nil, PChar(Befehl), nil, nil, False, 0, nil, nil, SI, PI);
```

<a id="form-access-before-create"></a>
### form-access-before-create

**Zugriff auf ein Formular, das noch nicht erzeugt ist** · Bug · Warnung · Gruppe Fehler finden

Der Konstruktor, AfterConstruction oder der OnCreate-Handler eines automatisch erzeugten Formulars bzw. Datenmoduls benutzt die globale Variable eines anderen Formulars, das die .dpr erst danach mit Application.CreateForm erzeugt. Die Variable ist dort noch nil. Die Reihenfolge stammt aus der .dpr des Projekts, zu dem die Unit gehört; der OnCreate-Handler aus der Formulardatei (ohne Eintrag FormCreate bzw. DataModuleCreate). Still, wenn die Routine die Variable prüft (Assigned, Vergleich mit nil), selbst zuweist, mit CreateForm erzeugt oder einen gleichnamigen lokalen Namen deklariert, und bei Formularen, die nicht automatisch erzeugt werden. Jede Variable wird je Routine einmal gemeldet. Sicherheit mittel. Keine Korrektur: die Reihenfolge in der .dpr ändern oder den Zugriff nach OnShow verlegen.

Mit Treffer:

```pascal
procedure TfrmHaupt.FormCreate(Sender: TObject);
begin
  lblNutzer.Caption := dmDaten.Benutzer;
end;
```

Richtig:

```pascal
// .dpr: Application.CreateForm(TdmDaten, dmDaten) before TfrmHaupt
procedure TfrmHaupt.FormCreate(Sender: TObject);
begin
  lblNutzer.Caption := dmDaten.Benutzer;
end;
```

<a id="except-handler-order"></a>
### except-handler-order

**Allgemeiner Exception-Handler vor speziellem** · Bug · Warnung · Gruppe Exceptions

In einem try..except mit mehreren on-Handlern gewinnt der erste passende. Ein Handler für eine Klasse, die ein früherer Handler schon fängt, wird nie erreicht: Sein Code ist tot und die Sonderbehandlung läuft nie. Gemeldet, wenn ein früherer Handler dieselbe Klasse, einen Vorfahren davon, Exception (deckt jede Exception-Klasse ab) oder TObject nennt. Vorfahren kommen aus der Unit, dem Projektindex und einer Tabelle bekannter RTL-, VCL- und FireDAC-Exceptions (etwa EStreamError > EFOpenError, EIntError > ERangeError); unbekannte Klassen werden nur mit Exception und TObject verglichen. Korrektur: den speziellen Handler vor den allgemeinen verschieben (nur, wenn beide Handler auf eigenen Zeilen stehen). Ein doppelter Handler für dieselbe Klasse wird ohne Korrektur gemeldet.

Mit Treffer:

```pascal
except
  on E: Exception do
    Protokoll(E.Message);
  on E: EConvertError do
    ShowMessage('Ungültige Zahl');
end;
```

Richtig:

```pascal
except
  on E: EConvertError do
    ShowMessage('Ungültige Zahl');
  on E: Exception do
    Protokoll(E.Message);
end;
```

<a id="reraise-exception-object"></a>
### reraise-exception-object

**raise E statt raise im Handler** · Code Smell · Warnung · Gruppe Exceptions

raise E; in einem Handler on E: … löst das gefangene Exception-Objekt als neues raise aus. Die RTL gibt das Objekt nicht doppelt frei, aber die Ausnahme beginnt jetzt im Handler: ExceptAddr und die Aufrufliste von Werkzeugen wie madExcept oder JclDebug zeigen auf den Handler statt auf den ursprünglichen Fehler, die Absprungstelle geht verloren. raise; wirft die aktuelle Exception unverändert weiter. Auch raise E at … wird gemeldet, dann ohne Korrektur. Still, wenn der Handler das Objekt mit AcquireExceptionObject übernimmt oder der Variablen ein neues Objekt zuweist, in anonymen Methoden und bei Handlern ohne Variablennamen. Konfidenz hoch. Korrektur: raise E; → raise;.

Mit Treffer:

```pascal
except
  on E: EDatenbank do
  begin
    Protokoll(E.Message);
    raise E;
  end;
end;
```

Richtig:

```pascal
except
  on E: EDatenbank do
  begin
    Protokoll(E.Message);
    raise;
  end;
end;
```

<a id="blocking-call-in-main-thread"></a>
### blocking-call-in-main-thread

**Blockierender Aufruf im Hauptthread** · Code Smell · Warnung · Gruppe Threads

Sleep, WaitFor, WaitForSingleObject, WaitForMultipleObjects oder Wait in Methoden von Formularen und Frames (Klassen, die von TForm, TCustomForm, TFrame oder TCustomFrame erben) und in Ereignis-Handlern (Methoden mit Parameter Sender) außerhalb von Thread-Klassen. Die Oberfläche friert ein, solange der Aufruf wartet; wartet der andere Thread auf Synchronize, hängt das Programm. WaitFor ohne Timeout auf einer Variablen nennt die Gefahr der Synchronize-Verklemmung. Sleep, WaitForSingleObject und WaitForMultipleObjects zählen nur ohne Empfänger (oder mit Winapi.Windows), WaitFor und Wait nur mit Empfänger. Ein Literal-Timeout unter maxSleepMs (Sleep(10), WaitForSingleObject(H, 0)) bleibt still, außer ein kurzes Sleep in einer Warteschleife ohne Application.ProcessMessages. Anonyme Methoden sind ausgenommen (TTask.Run, TThread.Queue), eingebettete Routinen gehören zu ihrer Methode. Konfidenz mittel. Keine Schnellkorrektur: die Arbeit in TTask.Run auslagern und das Ergebnis mit TThread.Queue melden.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `maxSleepMs` | integer | `50` | Literal-Timeouts unter diesem Wert (Millisekunden) werden nicht gemeldet; ein kurzes Sleep in einer Warteschleife schon. |
| `calls` | string-list | `["Sleep","WaitFor","WaitForSingleObject","WaitForMultipleObjects","Wait"]` | Aufrufe, die blockieren. Andere Namen werden unabhängig von ihren Argumenten gemeldet. |

Mit Treffer:

```pascal
procedure TfrmHaupt.btnExportClick(Sender: TObject);
begin
  FExport.Start;
  FExport.WaitFor;
end;
```

Richtig:

```pascal
procedure TfrmHaupt.btnExportClick(Sender: TObject);
begin
  btnExport.Enabled := False;
  TTask.Run(
    procedure
    begin
      FExport.Ausfuehren;
      TThread.Queue(nil, procedure begin btnExport.Enabled := True; end);
    end);
end;
```

<a id="thread-loop-without-terminated"></a>
### thread-loop-without-terminated

**Thread-Schleife ohne Terminated** · Bug · Warnung · Gruppe Threads

Eine while- oder repeat-Schleife in TThread.Execute oder in einer Methode der Thread-Klasse, die nur von dort aufgerufen wird (auch über andere solche Methoden, eingebettete Routinen eingeschlossen), prüft Terminated nicht. Terminate wirkt dann nicht, und WaitFor bzw. Free hängen beim Beenden. Gemeldet für Endlosschleifen (while True, until False) und für Warteschleifen mit Sleep, WaitFor, WaitForSingleObject, WaitForMultipleObjects, MsgWaitForMultipleObjects, Wait oder Yield, deren Bedingung und Rumpf Terminated bzw. CheckTerminated nie erwähnen. Thread-Klassen kommen aus der Unit und dem Index. Begrenzte Schleifen, for-Schleifen, anonyme Methoden und Klassen, die TerminatedSet überschreiben (sie beenden ihre Schleifen auf anderem Weg), bleiben still. Konfidenz hoch. Korrektur: Terminated in die Schleifenbedingung aufnehmen (while True → while not Terminated, sonst and not Terminated; until False → until Terminated, sonst or Terminated).

Mit Treffer:

```pascal
procedure TPoller.Execute;
begin
  while True do
  begin
    Abfragen;
    Sleep(1000);
  end;
end;
```

Richtig:

```pascal
procedure TPoller.Execute;
begin
  while not Terminated do
  begin
    Abfragen;
    Sleep(1000);
  end;
end;
```

<a id="anonymous-thread-not-started"></a>
### anonymous-thread-not-started

**Anonymer Thread nie gestartet** · Bug · Warnung · Gruppe Threads

TThread.CreateAnonymousThread(…) legt den Thread angehalten und mit FreeOnTerminate an. Ohne Start läuft er nie, und weil er nie endet, wird er auch nie freigegeben. Gemeldet für den Aufruf als eigene Anweisung und für eine lokale Variable (auch Inline-Variable), die weder mit Start oder Resume gestartet noch weitergegeben wird (Argument, Zuweisung, Result, Feld). Eigenschaften wie FreeOnTerminate oder OnTerminate zu setzen gilt nicht als Weitergabe. Konfidenz hoch. Korrektur: .Start anhängen; bei einer Variablen T.Start; nach der letzten Anweisung desselben Blocks, die sie erwähnt.

Mit Treffer:

```pascal
TThread.CreateAnonymousThread(
  procedure
  begin
    Synchronisieren;
  end);
```

Richtig:

```pascal
TThread.CreateAnonymousThread(
  procedure
  begin
    Synchronisieren;
  end).Start;
```

<a id="task-exception-unobserved"></a>
### task-exception-unobserved

**Exception in TTask geht verloren** · Code Smell · Hinweis · Gruppe Threads

TTask.Run(…) bzw. TTask.Create(…).Start, dessen Ergebnis nicht gespeichert und nie mit Wait, Status o. ä. abgefragt wird und dessen anonyme Methode kein try … except hat. Eine Exception im Task verschwindet still. Auch gemeldet für eine lokale Variable, die nie wieder vorkommt (bei TTask.Create nur in V.Start). Still bei gespeicherten Ergebnissen (Felder, Result, jede andere Verwendung der Variablen) und bei Methodenzeigern, deren Rumpf die Regel nicht sieht. Konfidenz mittel. Korrektur: den Rumpf in try … except einschließen und die Meldung über TThread.Queue mit ShowMessage im Hauptthread zeigen (ergänzt Vcl.Dialogs, in FireMonkey-Units FMX.Dialogs, und System.SysUtils im uses, wenn sie fehlen); nur, wenn begin und end der anonymen Methode auf eigenen Zeilen stehen.

Mit Treffer:

```pascal
TTask.Run(
  procedure
  begin
    Importieren(Datei);
  end);
```

Richtig:

```pascal
TTask.Run(
  procedure
  begin
    try
      Importieren(Datei);
    except
      on E: Exception do
      begin
        var Fehler := E.Message;
        TThread.Queue(nil,
          procedure
          begin
            ShowMessage(Fehler);
          end);
      end;
    end;
  end);
```

<a id="dataset-loop-without-next"></a>
### dataset-loop-without-next

**Datenmengen-Schleife ohne Next** · Bug · Fehler · Gruppe Datenbank

while not Q.Eof do ohne Q.Next im Rumpf oder mit Next nur auf einem Teil der Wege, die die Schleife fortsetzen (if ohne else, Continue vor Next). Die Schleife dreht endlos auf demselben Datensatz. Delete, MoveBy, Last, Close, FindNext und Free zählen ebenfalls als Weiterbewegen; Break, Exit, Abort und raise beenden die Schleife. Innere while- und for-Schleifen laufen vielleicht nie und zählen nicht. Wird Q im Rumpf weitergegeben (Argument, Zuweisung, with), kann der Aufgerufene den Zeiger bewegen, und die Regel bleibt still. Konfidenz hoch, wenn Next ganz fehlt, mittel, wenn nur einzelne Wege es auslassen. Korrektur: Q.Next; am Ende des begin … end-Rumpfs einfügen (nur, wenn Next ganz fehlt).

Mit Treffer:

```pascal
qryPositionen.First;
while not qryPositionen.Eof do
begin
  Summe := Summe + qryPositionen.FieldByName('Betrag').AsCurrency;
end;
```

Richtig:

```pascal
qryPositionen.First;
while not qryPositionen.Eof do
begin
  Summe := Summe + qryPositionen.FieldByName('Betrag').AsCurrency;
  qryPositionen.Next;
end;
```

<a id="dataset-edit-without-post"></a>
### dataset-edit-without-post

**Edit oder Append ohne Post** · Bug · Warnung · Gruppe Datenbank

Nach Edit, Append oder Insert (ohne Argumente) einer Datenmenge ruft dieselbe Routine weder Post noch Cancel (noch CheckBrowseMode) auf. Die Änderung bleibt offen und geht beim Scrollen still verloren oder wird später unerwartet gespeichert; bei einer Exception dazwischen bricht sie niemand ab. Still, wenn eine andere Routine der Unit dieselbe Datenmenge postet oder abbricht (Bearbeiten-Knopf mit eigenem Speichern-Knopf), und wenn die Datenmenge nach Edit weitergegeben wird (Argument, Zuweisung, with). Konfidenz mittel. Korrektur: die folgenden Anweisungen, die die Datenmenge benutzen, in try … except einschließen, mit Post am Ende des try-Teils und Cancel; raise; im except-Teil.

Mit Treffer:

```pascal
tblKunde.Edit;
tblKunde.FieldByName('Status').AsInteger := Ord(ksAktiv);
Protokollieren;
```

Richtig:

```pascal
tblKunde.Edit;
try
  tblKunde.FieldByName('Status').AsInteger := Ord(ksAktiv);
  tblKunde.Post;
except
  tblKunde.Cancel;
  raise;
end;
Protokollieren;
```

<a id="transaction-without-rollback"></a>
### transaction-without-rollback

**Transaktion ohne Rollback** · Bug · Warnung · Gruppe Datenbank

StartTransaction ohne Rollback im except des unmittelbar folgenden try. Bei einer Exception bleibt die Transaktion offen und hält Sperren. Erkannt für FireDAC (TFDConnection, TFDTransaction), IBX und dbExpress (StartTransaction/Commit/Rollback), dbExpress ab XE (BeginTransaction/CommitFreeAndNil/RollbackFreeAndNil, auch als T := Conn.BeginTransaction) und ADO (BeginTrans/CommitTrans/RollbackTrans). Die Option pairs ersetzt diese Paare durch eigene. Das Rollback darf in einem try … except innerhalb eines direkt folgenden try … finally stehen. Still, wenn eine andere Routine der Unit dieselbe Verbindung zurückrollt (Transaktion über mehrere Ereignisse). Konfidenz hoch. Korrektur: die Anweisungen bis zum Commit desselben Blocks in try … except mit Rollback (mit den Argumenten des Commit) und raise; einschließen; nur, wenn im selben Block ein Commit folgt.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `pairs` | json | `[{"start":"StartTransaction","commit":"Commit","rollback":"Rollback"},{"start":"BeginTransaction","commit":"CommitFreeAndNil","rollback":"RollbackFreeAndNil"},{"start":"BeginTrans","commit":"CommitTrans","rollback":"RollbackTrans"}]` | Transaktionsmethoden je Bibliothek als [{"start": …, "commit": …, "rollback": …}]; ersetzt die eingebauten Paare. |

Mit Treffer:

```pascal
Verbindung.StartTransaction;
Buchen(Auftrag);
Verbindung.Commit;
```

Richtig:

```pascal
Verbindung.StartTransaction;
try
  Buchen(Auftrag);
  Verbindung.Commit;
except
  Verbindung.Rollback;
  raise;
end;
```

<a id="sql-write-without-where"></a>
### sql-write-without-where

**UPDATE oder DELETE ohne WHERE** · Bug · Warnung · Gruppe Datenbank

UPDATE oder DELETE ohne WHERE in einem String-Literal, in SQL.Text, SQL.Add, CommandText, im ersten Argument von ExecSQL, ExecSQLScalar, ExecuteDirect oder Execute oder in SQL.Strings/CommandText der Formulardatei. Das betrifft alle Zeilen der Tabelle; meist ist die Bedingung vergessen. Die Regel setzt den SQL-Text je Query innerhalb einer Routine zusammen (Clear und ein neuer Text beginnen von vorn) und setzt Konstanten und lokale Werte ein. JOIN, TOP, LIMIT und ROWS schränken die Zeilen ebenfalls ein; ein WHERE in einer Unterabfrage oder einem Kommentar zählt nicht. Unbekannte Teile hinter dem Tabellennamen (Variablen, Aufrufe an der Stelle einer Klausel) lassen die Anweisung still; ein dynamischer Tabellenname meldet mit mittlerer Konfidenz. Still, wenn die Routine den SQL-Text weitergibt oder eine andere Routine der Unit ihn ergänzt; SQL der Formulardatei zählt nur, solange die Unit es nicht verändert. Literale außerhalb von SQL-Eigenschaften zählen nur mit DELETE bzw. UPDATE in Großbuchstaben, damit Meldungstexte still bleiben. Konfidenz hoch, keine Korrektur; Tabellen, die absichtlich geleert werden, gehören in allowTables.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `allowTables` | string-list | `[]` | Tabellen, die absichtlich ganz geleert bzw. geändert werden, mit oder ohne Schema. |

Mit Treffer:

```pascal
qry.SQL.Text := 'DELETE FROM Warenkorb';
qry.ExecSQL;
```

Richtig:

```pascal
qry.SQL.Text := 'DELETE FROM Warenkorb WHERE Kunde = :Kunde';
qry.ParamByName('Kunde').AsInteger := KundeId;
qry.ExecSQL;
```

<a id="signature-mismatch"></a>
### signature-mismatch

**Implementierung weicht von der Deklaration ab** · Bug · Fehler · Gruppe Compiler vorab

Der Kopf im implementation-Teil hat andere Parameter (Anzahl, Name, Typ, const/var/out), einen anderen Ergebnistyp, procedure statt function oder eine andere Aufrufkonvention als die Deklaration im Typ (wie E2037). Bei Überladungen wird die nächstliegende Deklaration verglichen (Parameteranzahl, dann Typen, Namen und Modifizierer); ist sie nicht eindeutig, melden declared-not-implemented und implemented-not-declared beide Seiten. Ein Rumpf darf Parameterliste, Ergebnistyp und Aufrufkonvention weglassen. Methoden in {$IF}-Blöcken werden übergangen; mit Include-Dateien ist die Konfidenz mittel. Korrektur: Kopf der Implementierung an die Deklaration angleichen oder als zweite Aktion die Deklaration an die Implementierung (Standardwerte bleiben in der Deklaration). refactoring.syncSignatures = false entfernt nur die Korrekturen.

Entspricht der Compilermeldung `E2037`, `E2211`, `E2065`.

Mit Treffer:

```pascal
procedure Buchen(const Betrag: Currency; Datum: TDate);
…
procedure TKonto.Buchen(Betrag: Currency; Datum: TDateTime);
```

Richtig:

```pascal
procedure Buchen(const Betrag: Currency; Datum: TDate);
…
procedure TKonto.Buchen(const Betrag: Currency; Datum: TDate);
```

<a id="interface-not-implemented"></a>
### interface-not-implemented

**Interface-Methode fehlt in der Klasse** · Bug · Fehler · Gruppe Compiler vorab

Eine Klasse nennt ein Interface, implementiert aber nicht alle seine Methoden, auch die der Vorfahr-Interfaces (wie E2291). Eine gleichnamige Methode der Klasse mit anderer Signatur wird an dieser Methode gemeldet (wie E2211). Geerbte Methoden der Vorfahrklassen, Methodenzuordnungen (procedure IFoo.Bar = Baz) und Properties mit implements zählen; ebenso die öffentlichen Methoden von TObject und die IInterface-Methoden von TInterfacedObject und ähnlichen RTL-Basen. Endet die Kette der Vorfahrklassen bei einer unbekannten Klasse oder ist das Interface unbekannt, bleibt die Regel still. Gemeldet wird auch eine Methodenzuordnung für ein Interface, das die Klasse nicht nennt (wie E2265). Klassen in {$IF}-Blöcken werden übergangen. Korrektur: fehlende Methoden deklarieren und leer implementieren (nicht bei abweichendem Kopf).

Entspricht der Compilermeldung `E2291`, `E2211`, `E2265`.

Mit Treffer:

```pascal
TDateiLog = class(TInterfacedObject, ILogger)
public
  procedure Info(const Text: string);
end;
```

Richtig:

```pascal
TDateiLog = class(TInterfacedObject, ILogger)
public
  procedure Info(const Text: string);
  procedure Warnung(const Text: string);
  procedure Fehler(const Text: string);
end;
```

<a id="uses-unit-not-found"></a>
### uses-unit-not-found

**Unit in uses nicht gefunden** · Bug · Fehler · Gruppe Compiler vorab

Eine Unit aus uses oder contains liegt weder im Projekt noch in den Ordnern, die der Compiler durchsucht: Ordner der verwendenden Datei, Projektordner, Suchpfade und DCU-Ausgabeordner der .dproj, Bibliothekspfade der Installation, jeweils als .pas oder .dcu und mit jedem Unit-Namespace davor (SysUtils → System.SysUtils); bei Packages zusätzlich die Units der requires-Packages (wie F2613). Ebenso gemeldet: eine Datei aus in '…', die es nicht gibt (F1026), ein Package aus requires, das weder als .dpk noch als .dcp gefunden wird (E2202), eine Unit, die sich selbst einbindet (F2092), und einmal eine fehlende Unit System, also ein fehlender Bibliothekspfad, statt einer Meldung je Unit (F1027). Einträge in {$IF}-Blöcken werden übergangen; ohne bekannte Installation, mit offenem Makro in einem Suchpfad oder einem requires-Package mit unbekanntem Inhalt bleibt die Regel still. Die Meldung nennt ähnliche Units. Korrekturen: die Unit mit Namespace (Forms → Vcl.Forms) bzw. eine ähnlich geschriebene einsetzen oder den Ordner unter dem Projekt, in dem die Unit liegt, in DCC_UnitSearchPath der Basiskonfiguration der .dproj aufnehmen.

Entspricht der Compilermeldung `F2613`, `F1027`, `F1026`, `E2202`, `F2092`.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `searchPaths` | string | `"project"` | Wo Units gesucht werden: project (wie der Compiler: Projekt, Suchpfade der .dproj, Bibliothekspfade, .pas und .dcu), atlas (was Atlas kennt: Index und Quellpfade der Installation) oder both. |

Mit Treffer:

```pascal
uses
  System.SysUtils, Vcl.Forms, Kunden.Daten, Rechnungs.Druck;
```

Richtig:

```pascal
uses
  System.SysUtils, Vcl.Forms, Kunden.Daten, Rechnung.Druck;
```

<a id="unresolved-attribute"></a>
### unresolved-attribute

**Attribut nicht gefunden und still ignoriert** · Bug · Fehler · Gruppe Compiler vorab

Ein Attribut [Name] lässt sich weder einer Klasse NameAttribute noch Name zuordnen, meist weil eine Unit in uses fehlt. Delphi warnt nur (W1074) und übergeht das Attribut: DUnitX-Tests laufen dann nicht, JSON- oder ORM-Zuordnungen fehlen. Die Meldung nennt die Unit, die das Attribut im Index deklariert; eine Fassaden-Unit, die den Typ aus einer anderen Kandidatin weiterreicht (DUnitX.TestFramework statt DUnitX.Attributes), geht vor, und die DUnitX-Attribute sind auch ohne DUnitX im Index bekannt. Attribute des Compilers wie Weak, Unsafe, Ref und Volatile zählen immer. Still ohne die Unit System im Index, wenn eine Unit aus uses nicht im Index steht (sie könnte das Attribut deklarieren), in {$IF}-Blöcken und bei unbekanntem Vorfahren der umgebenden Klasse; mit Include-Dateien ist die Konfidenz mittel. Korrektur: Unit in uses aufnehmen.

Entspricht der Compilermeldung `W1074`, `E2289`.

Mit Treffer:

```pascal
uses
  System.SysUtils;
type
  [TestFixture]
  TKundeTests = class
```

Richtig:

```pascal
uses
  System.SysUtils, DUnitX.TestFramework;
type
  [TestFixture]
  TKundeTests = class
```

<a id="comparison-as-statement"></a>
### comparison-as-statement

**Vergleich statt Zuweisung als Anweisung** · Bug · Fehler · Gruppe Compiler vorab

Ein Vergleich wie Result = 0; oder FAktiv = True; steht als eigene Anweisung; gemeint war :=. Delphi meldet E2014 erst beim Übersetzen. Bei = mit zuweisbarer linker Seite (Variable, Feld, Element, Ziel eines Zeigers) ersetzt die Korrektur = durch :=. Andere Vergleiche und Ausdrücke, deren Wert verfällt (A <> B;, A + B;, not A;, ein Literal), meldet die Regel ohne Korrektur, ebenso einen Aufruf links.

Entspricht der Compilermeldung `E2014`.

Mit Treffer:

```pascal
Result = 0;
```

Richtig:

```pascal
Result := 0;
```

<a id="duplicate-case-label"></a>
### duplicate-case-label

**Doppelte case-Marke** · Bug · Fehler · Gruppe Compiler vorab

Zwei Marken einer case-Anweisung decken denselben Wert ab (wie E2030), auch über Bereiche (1..5 und 3), Konstanten mit gleichem Wert, Zeichen ('a' und #97) und Bereiche von Aufzählungswerten. Gleiches gilt für die Marken eines varianten Record-Teils (wie E2027). Die Werte ergeben sich aus Zahlen, Zeichen, Konstanten und Aufzählungswerten über die Namensauflösung; Marken mit unbekanntem Wert vergleicht die Regel nur über den Text. Gemeldet wird eine Marke nur, wenn die frühere immer mit übersetzt wird: verschiedene Zweige desselben {$IF} stoßen nie zusammen. Korrektur: den doppelten Wert aus dem späteren Zweig entfernen bzw. den ganzen Zweig, wenn es seine einzige Marke war; eine teilweise Überschneidung von Bereichen meldet die Regel ohne Korrektur.

Entspricht der Compilermeldung `E2030`, `E2027`.

Mit Treffer:

```pascal
case Status of
  stNeu, stOffen: Bearbeiten;
  stGeschlossen: Archivieren;
  stOffen: Erinnern;
end;
```

Richtig:

```pascal
case Status of
  stNeu, stOffen: Bearbeiten;
  stGeschlossen: Archivieren;
end;
```

<a id="field-after-method"></a>
### field-after-method

**Feld nach Methoden im selben Abschnitt** · Bug · Fehler · Gruppe Compiler vorab

In einem Sichtbarkeitsabschnitt einer Klasse, eines Objekts oder Records folgt eine Felddeklaration auf eine Methode oder Property. Delphi verlangt Felder zuerst oder einen neuen Abschnitt bzw. var (E2169); FPC übersetzt das. Korrekturen: das Feld samt Attributen und Kommentaren an den Anfang des Abschnitts verschieben oder var davor setzen. In Records steht var vorn, weil das Verschieben das Speicherlayout ändert. Gemeldet wird ein Feld nur, wenn eine Methode davor immer mit übersetzt wird, wenn das Feld übersetzt wird; mit bedingten Zweigen dazwischen gibt es nur var.

Entspricht der Compilermeldung `E2169`.

Mit Treffer:

```pascal
TKunde = class
private
  function GetName: string;
  FName: string;
end;
```

Richtig:

```pascal
TKunde = class
private
  FName: string;
  function GetName: string;
end;
```

<a id="overload-directive-missing"></a>
### overload-directive-missing

**Überladung ohne overload oder mit gleicher Signatur** · Bug · Fehler · Gruppe Compiler vorab

Zwei Routinen oder Methoden gleichen Namens im selben Gültigkeitsbereich (ein Typ, die Unit über interface und implementation, die in einer Routine verschachtelten Routinen), von denen mindestens eine kein overload trägt (wie E2254, bzw. E2267, wenn es der früheren fehlt), oder zwei Überladungen mit gleichen Parameterarten und -typen (wie E2252, bzw. E2301 mit auch gleichem Ergebnistyp). Ein Rumpf zu einer früheren Deklaration (interface, forward) zählt nicht. Operatoren, Methodenrümpfe und Deklarationen in verschiedenen Zweigen desselben {$IF} bleiben außen vor. Korrektur: overload; an alle Deklarationen ohne anhängen, vor den übrigen Direktiven.

Entspricht der Compilermeldung `E2254`, `E2267`, `E2252`, `E2301`.

Mit Treffer:

```pascal
procedure Laden(const Datei: string);
procedure Laden(Strom: TStream);
```

Richtig:

```pascal
procedure Laden(const Datei: string); overload;
procedure Laden(Strom: TStream); overload;
```

<a id="duplicate-declaration"></a>
### duplicate-declaration

**Bezeichner doppelt deklariert** · Bug · Fehler · Gruppe Compiler vorab

Ein Bezeichner ist im selben Gültigkeitsbereich zweimal deklariert (wie E2004): lokale Variable, Konstante, Typ oder Label und ein Parameter der Routine, zwei Felder, ein Feld und eine Methode oder Property eines Typs, zwei Typen, Konstante und Variable der Unit über interface und implementation hinweg. Ebenso eine Unit doppelt in uses oder in den uses-Klauseln von interface und implementation zugleich (Option checkUses). Überladungen und Rümpfe von Routinen, eine Vorwärtsdeklaration und ihr Typ, TList neben TList<T> und Deklarationen in verschiedenen Zweigen desselben {$IF} zählen nicht. Korrektur: zweite Deklaration entfernen (den ganzen var-, const-, type- oder label-Abschnitt, wenn sie seine einzige war; bei uses den doppelten Eintrag); keine bei Parametern, Methoden und Properties.

Entspricht der Compilermeldung `E2004`.

| Option | Typ | Vorgabe | Bedeutung |
|---|---|---|---|
| `checkUses` | boolean | `true` | Doppelte Einträge in uses-Klauseln melden. |

Mit Treffer:

```pascal
procedure TRechnung.Summieren(Betrag: Currency);
var
  Betrag: Currency;
begin
```

Richtig:

```pascal
procedure TRechnung.Summieren(Betrag: Currency);
begin
```

<a id="conditional-directive-unbalanced"></a>
### conditional-directive-unbalanced

**Bedingte Direktiven unvollständig oder unbekannt** · Bug · Fehler · Gruppe Compiler vorab

Ein {$IFDEF}, {$IFNDEF}, {$IFOPT} oder {$IF}, das nie geschlossen wird, sodass der Rest der Datei an seiner Bedingung hängt (wie E2095, bei {$IF} E2280); {$ELSE}, {$ELSEIF}, {$ENDIF} oder {$IFEND} ohne passendes {$IF…} oder nach {$ELSE} (wie E2279); {$IFDEF}, {$IFNDEF}, {$DEFINE} oder {$UNDEF} ohne gültiges Symbol (wie E2173); eine unbekannte Direktive oder ein unbekannter {$WARN}-Bezeichner (wie W1030), mit dem nächstliegenden bekannten Namen als Korrektur; {$POPOPT} ohne {$PUSHOPT} (wie W1078) oder {$PUSHOPT} ohne {$POPOPT} (wie W1079); ein ungültiger Wert für {$ALIGN} bzw. {$A} (wie E2573). Unbekannte Namen prüft die Regel nicht in Zweigen, deren Bedingung FPC abfragt, {$PUSHOPT}/{$POPOPT} nur, wenn keines davon in einem bedingten Zweig steht. Korrekturen: {$ENDIF} vor der ersten Leerzeile hinter dem offenen Block ergänzen, überzählige Direktive entfernen, Tippfehler korrigieren.

Entspricht der Compilermeldung `E2095`, `E2280`, `E2279`, `E2173`, `W1030`, `W1078`, `W1079`, `E2573`.

Mit Treffer:

```pascal
{$IFDEF DEBUG}
  Protokoll.Ausfuehrlich := True;

procedure TDienst.Starten;
```

Richtig:

```pascal
{$IFDEF DEBUG}
  Protokoll.Ausfuehrlich := True;
{$ENDIF}

procedure TDienst.Starten;
```

<a id="override-target-missing"></a>
### override-target-missing

**override ohne passende virtuelle Methode** · Bug · Fehler · Gruppe Compiler vorab

Eine Methode mit override, zu der kein Vorfahr eine virtuelle (oder dynamic, abstract) Methode mit gleichem Namen und gleichen Parametern hat (wie E2137): oft ein Tippfehler (Destory) oder im Vorfahren geänderte Parameter. Die Meldung nennt die nächstliegende virtuelle Methode des Vorfahren („dort heißt es Ausfuehren(const Modus: TModus)“) bzw. einen ähnlichen Namen. Außerdem: override auf eine statische Methode (wie E2170), auf eine finale (wie E2352) und Ableiten von einer sealed-Klasse (wie E2353). Vorfahren sucht die Regel in der Datei und im Symbolindex; bricht die Kette an einer unbekannten Klasse ab, bleibt sie still. Ohne System im Index gelten die virtuellen Methoden von TObject als vorhanden. Typparameter generischer Vorfahren, Typaliase und Synonyme wie Longint passen. Korrektur: Signatur des Vorfahren in Deklaration und Implementierung übernehmen.

Entspricht der Compilermeldung `E2137`, `E2170`, `E2352`, `E2353`.

Mit Treffer:

```pascal
TDienst = class
protected
  procedure Ausfuehren(const Modus: TModus); virtual;
end;
TImportDienst = class(TDienst)
protected
  procedure Ausfuehren(Modus: Integer); override;
end;
```

Richtig:

```pascal
TImportDienst = class(TDienst)
protected
  procedure Ausfuehren(const Modus: TModus); override;
end;
```

<a id="abstract-class-instantiated"></a>
### abstract-class-instantiated

**Instanz einer Klasse mit abstrakten Methoden** · Bug · Warnung · Gruppe Compiler vorab

Create auf einer Klasse, die abstrakte Methoden deklariert oder erbt, ohne sie zu überschreiben (wie W1020), oder auf einer als abstract deklarierten Klasse (wie E2402). Der Aufruf einer abstrakten Methode löst zur Laufzeit EAbstractError aus; die Meldung nennt die offenen Methoden. Klassen sucht die Regel in der Datei und im Symbolindex; Überladungen mit gleicher Parameterzahl gelten als eine Methode. Aufrufe über Klassenreferenzen, inherited Create und Konstruktor-Rümpfe prüft sie nicht. Korrektur für eine Klasse dieser Datei, die die abstrakten Methoden erbt: dort überschreiben (wie die Code-Aktion „überschreiben“).

Entspricht der Compilermeldung `W1020`, `E2402`.

Mit Treffer:

```pascal
Form := TForm.Create;
Gesamt := Gesamt + Form.Flaeche;
```

Richtig:

```pascal
Form := TKreis.Create;
Gesamt := Gesamt + Form.Flaeche;
```

<a id="property-accessor-invalid"></a>
### property-accessor-invalid

**Getter oder Setter einer Property ungültig** · Bug · Fehler · Gruppe Compiler vorab

Der Name hinter read oder write einer Property passt nicht: Er ist weder in der Klasse noch in ihren Vorfahren deklariert oder ist eine Property (wie E2168); Getter oder Setter haben die falsche Art, Parameter oder Typen (wie E2234); der Setter nimmt einen var- oder out-Parameter (wie E2282); die Zugriffsmethode ist überladen (wie E2271); eine Klassen-Property nutzt ein Instanzmitglied oder eine Klassenmethode ohne static (wie E2355), eine Instanz-Property ein Klassenmitglied (wie E2356); eine Array-Property oder eine Property mit index nutzt ein Feld (wie E2174); ein Feldselektor geht über ein Feld, das kein Record ist (wie E2459), nennt ein Mitglied, das kein Feld ist (wie E2461), oder ein Feld, das dem Record fehlt (wie E2562). Namen sucht die Regel in der Datei und für Vorfahren im Symbolindex; sie bleibt still, wenn die Kette der Vorfahren abbricht, der Name nur in einem inaktiven Zweig steht, die Klasse ihn nicht sieht oder Include-Dateien einbindet. Typen vergleicht sie nur, wenn beide eingebaut oder als eigener Typ deklariert sind. Korrektur für ein fehlendes F<Name>, Get<Name> oder Set<Name>: anlegen (wie die Vervollständigung hinter read/write, completion.accessorSection).

Entspricht der Compilermeldung `E2168`, `E2234`, `E2282`, `E2271`, `E2355`, `E2356`, `E2174`, `E2459`, `E2461`, `E2562`.

Mit Treffer:

```pascal
TKunde = class
private
  FName: string;
public
  property Name: string read FName write SetName;
end;
```

Richtig:

```pascal
TKunde = class
private
  FName: string;
  procedure SetName(const Value: string);
public
  property Name: string read FName write SetName;
end;
```

<a id="assign-to-property-member"></a>
### assign-to-property-member

**Zuweisung an ein Feld eines Property-Records** · Bug · Fehler · Gruppe Compiler vorab

Zuweisung an ein Feld eines Records, den eine Property mit Getter, eine Default- oder Array-Property oder ein Funktionsergebnis nur als Kopie liefert (wie E2064): Die Zuweisung hat keine Wirkung. Zuweisungen an untypisierte Konstanten meldet die Regel ebenso. Typen kommen aus der Namensauflösung; gemeldet wird nur bei sicher bekanntem Record-Typ. Liest die Property direkt ein Feld, schreibt Delphi in dieses Feld, und die Regel bleibt still. Korrektur bei einer Property mit write: über eine lokale Variable zuweisen und zurückschreiben; die Variable wird in der Routine deklariert, die Unit ihres Typs in uses ergänzt.

Entspricht der Compilermeldung `E2064`, `E2453`.

Mit Treffer:

```pascal
Rahmen.BoundsRect.Left := 0;
```

Richtig:

```pascal
R := Rahmen.BoundsRect;
R.Left := 0;
Rahmen.BoundsRect := R;
```

<a id="readonly-property-assigned"></a>
### readonly-property-assigned

**Zuweisung an eine Property ohne write** · Bug · Fehler · Gruppe Compiler vorab

Zuweisung an eine Property ohne write (wie E2129) bzw. Lesen einer Property ohne read (wie E2130). Die Regel meldet nur, wenn die Namensauflösung die Property sicher findet; Neudeklarationen ohne read und write (property Caption;) gelten als unbekannt. Korrekturen: Count := 0 wird Clear, wenn der Typ Clear hat; in einer Methode der deklarierenden Klasse das Feld hinter read zuweisen; für eine Property dieser Datei den Setter anlegen und write ergänzen.

Entspricht der Compilermeldung `E2129`, `E2130`.

Mit Treffer:

```pascal
Liste.Count := 0;
```

Richtig:

```pascal
Liste.Clear;
```

<a id="comparison-always-constant"></a>
### comparison-always-constant

**Vergleich immer wahr oder immer falsch** · Bug · Warnung · Gruppe Compiler vorab

Vergleich einer Variablen, eines Feldes, einer Property oder eines Funktionsergebnisses vom eingebauten Ganzzahltyp mit einer Konstanten außerhalb bzw. am Rand des Wertebereichs (wie W1021, W1022): Cardinal >= 0 ist immer wahr, Byte > 255 immer falsch. Ebenso case-Marken außerhalb des Bereichs des case-Ausdrucks (wie W1018). Gemeldet wird nur bei sicher bekanntem Typ, dessen Deklaration immer mit dem Vergleich übersetzt wird. NativeInt, LongInt und ihre vorzeichenlosen Gegenstücke gelten mit dem weitesten Bereich aller Plattformen; Teilbereichstypen meldet die Regel nicht. Length(…) < 0 und Length(…) >= 0 meldet sie ebenfalls, obwohl dcc dort nicht warnt; die Meldung sagt das dazu.

Entspricht der Compilermeldung `W1021`, `W1022`, `W1018`.

Mit Treffer:

```pascal
while Rest >= 0 do  // Rest: Cardinal
```

Richtig:

```pascal
while Rest > 0 do
```

<a id="constant-initializer-mismatch"></a>
### constant-initializer-mismatch

**Initialisierung einer Konstanten passt nicht** · Bug · Fehler · Gruppe Compiler vorab

Eine typisierte Konstante oder initialisierte Variable vom statischen Array-Typ hat mehr oder weniger Elemente als ihr Indexbereich (wie E2072), typisch nach einem neuen Wert in einer Aufzählung (array[TStatus] of string); geprüft je Dimension und auch für benannte Array-Typen der Datei. Ebenso Record-Konstanten, deren Felder in anderer Reihenfolge als deklariert stehen (wie E2083). Indexbereiche: Teilbereiche mit konstanten Grenzen, Aufzählungen ohne eigene Werte, Boolean, Byte, Char usw. Deklarationen mit bedingten Direktiven gelten als unsicher. Korrekturen: fehlende Einträge mit Platzhalter ergänzen (Name des Aufzählungswerts als Kommentar), Felder in die Reihenfolge der Deklaration bringen.

Entspricht der Compilermeldung `E2072`, `E2083`.

Mit Treffer:

```pascal
StatusText: array[TStatus] of string = ('Neu', 'Offen', 'Geschlossen');  // TStatus has 4 values
```

Richtig:

```pascal
StatusText: array[TStatus] of string = ('Neu', 'Offen', 'Geschlossen', ''{stArchiviert});
```

<a id="case-selector-not-ordinal"></a>
### case-selector-not-ordinal

**case oder for ohne ordinalen Typ** · Bug · Fehler · Gruppe Compiler vorab

case über einen nicht ordinalen Ausdruck (wie E2001): Strings, Gleitkommazahlen, Klassen und Interfaces; for-Schleife mit nicht ordinaler Zählvariable (wie E2032); case-Marken und Array-Grenzen, die Variablen, Felder, Properties, Parameter oder typisierte Konstanten statt Konstanten sind (wie E2026). Gemeldet wird nur bei sicher bekanntem Typ, dessen Deklaration immer mit der Anweisung übersetzt wird. Korrektur bei Strings mit lauter String-Literalen als Marken: case IndexStr(S, […]) of mit den Positionen als Marken, System.StrUtils kommt in die uses.

Entspricht der Compilermeldung `E2001`, `E2032`, `E2026`.

Mit Treffer:

```pascal
case Befehl of 'start': Starten; 'stop': Stoppen; end;  // Befehl: string
```

Richtig:

```pascal
case IndexStr(Befehl, ['start', 'stop']) of 0: Starten; 1: Stoppen; end;
```
