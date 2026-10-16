# Prüfregeln

Erzeugt von `Tools/Update-RuleCatalog.ps1` aus dem Regelkatalog. Nicht von Hand ändern.

| Regel | Name | Kategorie | Schweregrad |
|---|---|---|---|
| [`syntax`](#syntax) | Syntaxfehler | Bug | Fehler |
| [`unused-suppression`](#unused-suppression) | Ungenutzte Unterdrückung | Code Smell | Hinweis |
| [`bidi-control`](#bidi-control) | Bidirektionales Steuerzeichen | Schwachstelle | Fehler |
| [`invisible-char`](#invisible-char) | Unsichtbares Zeichen | Sicherheits-Hotspot | Warnung |
| [`control-char`](#control-char) | Steuerzeichen | Bug | Fehler |
| [`confusable-identifier`](#confusable-identifier) | Verwechselbarer Bezeichner | Sicherheits-Hotspot | Warnung |
| [`forbidden-uses`](#forbidden-uses) | Verbotene uses-Beziehung | Code Smell | Fehler |
| [`architecture-role-import`](#architecture-role-import) | Import verletzt die Rollenmatrix | Code Smell | Warnung |
| [`architecture-contract-content`](#architecture-contract-content) | Klasse in einer Contract-Unit | Code Smell | Warnung |
| [`thread-vcl-access`](#thread-vcl-access) | VCL-Zugriff aus einem Thread | Bug | Warnung |
| [`lock-without-finally`](#lock-without-finally) | Sperre ohne try/finally | Bug | Warnung |
| [`thread-use-after-free-on-terminate`](#thread-use-after-free-on-terminate) | Thread nach dem Start mit FreeOnTerminate benutzt | Bug | Warnung |
| [`thread-free-with-free-on-terminate`](#thread-free-with-free-on-terminate) | Free auf einem Thread mit FreeOnTerminate | Bug | Fehler |
| [`synchronize-in-destructor`](#synchronize-in-destructor) | Synchronize im Destruktor eines Threads | Bug | Warnung |
| [`thread-resume-suspend`](#thread-resume-suspend) | Veraltetes TThread.Resume/Suspend | Code Smell | Warnung |
| [`result-not-set`](#result-not-set) | Funktionsergebnis eventuell nicht gesetzt | Bug | Warnung |
| [`possibly-uninitialized`](#possibly-uninitialized) | Variable eventuell nicht initialisiert | Bug | Warnung |
| [`unreachable-code`](#unreachable-code) | Unerreichbarer Code | Bug | Warnung |
| [`unused-local`](#unused-local) | Ungenutzte lokale Variable | Code Smell | Hinweis |
| [`unused-parameter`](#unused-parameter) | Ungenutzter Parameter | Code Smell | Hinweis |
| [`unused-assignment`](#unused-assignment) | Zugewiesener Wert ungenutzt | Code Smell | Hinweis |
| [`declared-not-implemented`](#declared-not-implemented) | Deklariert, aber nicht implementiert | Bug | Fehler |
| [`implemented-not-declared`](#implemented-not-declared) | Implementiert, aber nicht deklariert | Bug | Fehler |
| [`destroy-without-override`](#destroy-without-override) | Destroy ohne override | Bug | Warnung |
| [`component-create-without-override`](#component-create-without-override) | Komponentenkonstruktor ohne override | Bug | Warnung |
| [`hides-virtual`](#hides-virtual) | Methode verdeckt virtuelle Methode | Bug | Warnung |
| [`virtual-instead-of-override`](#virtual-instead-of-override) | virtual statt override | Bug | Warnung |
| [`captured-loop-variable`](#captured-loop-variable) | Erfasste Schleifenvariable | Bug | Warnung |
| [`component-missing-inherited`](#component-missing-inherited) | Komponentenmethode ohne inherited | Bug | Warnung |
| [`component-default-mismatch`](#component-default-mismatch) | default passt nicht zum Konstruktor | Bug | Warnung |
| [`component-missing-free-notification`](#component-missing-free-notification) | Komponentenreferenz ohne FreeNotification | Bug | Warnung |
| [`component-setter-without-invalidate`](#component-setter-without-invalidate) | Setter ohne Invalidate | Code Smell | Hinweis |
| [`component-fixed-pixels`](#component-fixed-pixels) | Feste Pixelwerte | Code Smell | Warnung |
| [`component-hardcoded-color`](#component-hardcoded-color) | Feste Farbe in Paint | Code Smell | Hinweis |
| [`form-field-without-object`](#form-field-without-object) | Formularfeld ohne Objekt | Bug | Warnung |
| [`form-object-without-field`](#form-object-without-field) | Formularobjekt ohne Feld | Bug | Warnung |
| [`form-field-type-mismatch`](#form-field-type-mismatch) | Feldtyp weicht vom Formularobjekt ab | Bug | Warnung |
| [`security-command-injection`](#security-command-injection) | Befehlsinjektion | Schwachstelle | Warnung |
| [`security-path-traversal`](#security-path-traversal) | Pfad-Traversal | Schwachstelle | Warnung |
| [`security-weak-crypto`](#security-weak-crypto) | Schwache Kryptografie | Sicherheits-Hotspot | Hinweis |
| [`security-tls-verification-disabled`](#security-tls-verification-disabled) | TLS-Zertifikatsprüfung abgeschaltet | Schwachstelle | Warnung |
| [`security-insecure-http`](#security-insecure-http) | Unverschlüsselte http://-URL | Sicherheits-Hotspot | Hinweis |
| [`security-insecure-random`](#security-insecure-random) | Random für sicherheitsrelevante Werte | Sicherheits-Hotspot | Warnung |
| [`dfm-circular-datasource`](#dfm-circular-datasource) | Zirkuläre Master-Detail- bzw. DataSource-Verknüpfung | Bug | Warnung |
| [`dfm-master-without-fields`](#dfm-master-without-fields) | Master-Detail ohne MasterFields | Bug | Warnung |
| [`dfm-required-field-without-control`](#dfm-required-field-without-control) | Pflichtfeld ohne sichtbares Eingabe-Control | Bug | Warnung |
| [`dfm-control-field-type-mismatch`](#dfm-control-field-type-mismatch) | Datensensitives Control passt nicht zum Feldtyp | Bug | Warnung |
| [`dfm-duplicate-binding`](#dfm-duplicate-binding) | Zwei Controls an demselben Feld | Bug | Warnung |
| [`dfm-property`](#dfm-property) | Komponenten-Property verletzt eine Eigenschaftsregel | Code Smell | Warnung |
| [`foreign-form-control-access`](#foreign-form-control-access) | Zugriff auf Controls eines anderen Formulars | Code Smell | Warnung |
| [`security-sql-injection`](#security-sql-injection) | SQL-Text aus zusammengesetzten Werten (SQL-Injection) | Schwachstelle | Warnung |
| [`slash-command`](#slash-command) | Schnellbefehl nicht ausgeführt | Code Smell | Hinweis |
| [`empty-except`](#empty-except) | Leerer except-Block | Code Smell | Warnung |
| [`interface-guid`](#interface-guid) | Interface ohne GUID | Bug | Warnung |
| [`duplicate-interface-guid`](#duplicate-interface-guid) | Zwei Interfaces mit derselben GUID | Bug | Fehler |
| [`file-header`](#file-header) | Dateikopf fehlt oder weicht ab | Code Smell | Hinweis |
| [`hardcoded-string`](#hardcoded-string) | Text im Code statt resourcestring | Code Smell | Hinweis |
| [`self-assignment`](#self-assignment) | Zuweisung an sich selbst | Bug | Warnung |
| [`for-high-to-low`](#for-high-to-low) | for-Schleife zählt mit to abwärts | Bug | Warnung |
| [`exception-not-raised`](#exception-not-raised) | Exception erzeugt, aber nicht ausgelöst | Bug | Warnung |
| [`assert-side-effect`](#assert-side-effect) | Assert mit Seiteneffekt | Bug | Warnung |
| [`ifthen-side-effect`](#ifthen-side-effect) | IfThen wertet beide Zweige aus | Bug | Warnung |
| [`random-without-randomize`](#random-without-randomize) | Random ohne Randomize | Code Smell | Hinweis |
| [`int32-mul-overflow`](#int32-mul-overflow) | Int32-Multiplikation an Int64 zugewiesen | Bug | Warnung |
| [`sizeof-pointer`](#sizeof-pointer) | SizeOf eines Zeigers in Move oder FillChar | Bug | Fehler |
| [`char-to-pchar`](#char-to-pchar) | Char nach PChar umgewandelt | Bug | Fehler |
| [`float-equality`](#float-equality) | Gleitkommavergleich mit = oder <> | Bug | Hinweis |
| [`constructor-on-instance`](#constructor-on-instance) | Konstruktor auf einer Instanz aufgerufen | Bug | Warnung |
| [`format-without-settings`](#format-without-settings) | Formatierung abhängig vom Gebietsschema | Code Smell | Hinweis |
| [`generic-exception-raised`](#generic-exception-raised) | Allgemeine Exception ausgelöst | Code Smell | Hinweis |
| [`catch-all-without-raise`](#catch-all-without-raise) | Exception-Handler ohne erneutes raise | Code Smell | Warnung |
| [`exception-freed`](#exception-freed) | Exception-Objekt manuell freigegeben | Bug | Fehler |
| [`string-concat-in-loop`](#string-concat-in-loop) | String-Verkettung in einer Schleife | Code Smell | Hinweis |
| [`loop-invariant-call`](#loop-invariant-call) | Teurer Aufruf in der Schleifenbedingung | Code Smell | Hinweis |
| [`missing-begin-update`](#missing-begin-update) | Hinzufügen in einer Schleife ohne BeginUpdate | Code Smell | Hinweis |
| [`bool-compare`](#bool-compare) | Vergleich mit True oder False | Code Smell | Hinweis |
| [`redundant-assigned-free`](#redundant-assigned-free) | Assigned-Prüfung vor Free | Code Smell | Hinweis |
| [`raise-in-finally`](#raise-in-finally) | raise in einem finally-Block | Bug | Warnung |
| [`redundant-parens`](#redundant-parens) | Überflüssige Klammern | Code Smell | Hinweis |
| [`redundant-begin-end`](#redundant-begin-end) | begin … end um eine einzelne Anweisung | Code Smell | Hinweis |
| [`with-statement`](#with-statement) | with-Anweisung | Code Smell | Hinweis |
| [`metric-method-length`](#metric-method-length) | Methode zu lang | Code Smell | Hinweis |
| [`metric-nesting-depth`](#metric-nesting-depth) | Zu tief verschachtelt | Code Smell | Hinweis |
| [`metric-cyclomatic-complexity`](#metric-cyclomatic-complexity) | Zyklomatische Komplexität zu hoch | Code Smell | Hinweis |
| [`metric-cognitive-complexity`](#metric-cognitive-complexity) | Kognitive Komplexität zu hoch | Code Smell | Hinweis |
| [`metric-parameter-count`](#metric-parameter-count) | Zu viele Parameter | Code Smell | Hinweis |
| [`todo-comment`](#todo-comment) | Offener TODO-Kommentar | Code Smell | Hinweis |
| [`component-palette-icon`](#component-palette-icon) | Registrierte Komponente ohne Palettensymbol | Code Smell | Hinweis |
| [`unresolved-identifier`](#unresolved-identifier) | Nicht deklarierter Bezeichner | Bug | Warnung |

<a id="syntax"></a>
## syntax

**Syntaxfehler** · Bug · Fehler

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
## unused-suppression

**Ungenutzte Unterdrückung** · Code Smell · Hinweis

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

<a id="bidi-control"></a>
## bidi-control

**Bidirektionales Steuerzeichen** · Schwachstelle · Fehler

Bidirektionale Steuerzeichen können Code anders anzeigen, als er kompiliert wird (Trojan Source).

Mit Treffer:

```pascal
if IsAdmin then { U+202E } begin
```

Richtig:

```pascal
if IsAdmin then begin
```

<a id="invisible-char"></a>
## invisible-char

**Unsichtbares Zeichen** · Sicherheits-Hotspot · Warnung

Unsichtbare oder Nullbreiten-Zeichen im Quelltext.

Mit Treffer:

```pascal
Count{U+200B} := 0;
```

Richtig:

```pascal
Count := 0;
```

<a id="control-char"></a>
## control-char

**Steuerzeichen** · Bug · Fehler

NUL- und Steuerzeichen oder ungültige Bytes (U+FFFD) im Quelltext.

Mit Treffer:

```pascal
S := 'abc{U+0000}';
```

Richtig:

```pascal
S := 'abc' + #0;
```

<a id="confusable-identifier"></a>
## confusable-identifier

**Verwechselbarer Bezeichner** · Sicherheits-Hotspot · Warnung

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
## forbidden-uses

**Verbotene uses-Beziehung** · Code Smell · Fehler

Ein uses-Eintrag verletzt eine Schichtregel unter "layers" in atlas.json, z. B. darf *.Common.* nicht Vcl.* verwenden.

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
## architecture-role-import

**Import verletzt die Rollenmatrix** · Code Smell · Warnung

Ein uses-Eintrag verletzt die Importmatrix des Rollenkonzepts (Ausgabeartefakt, Feature, Rolle: Contract, Internals, Providers, Adapters, Composition, Hosting). Standardmäßig aus; in atlas.json mit der Option "prefixes" einschalten. Genehmigte Ausnahmen stehen unter "allow" als "Quelle -> Ziel"-Globs.

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
## architecture-contract-content

**Klasse in einer Contract-Unit** · Code Smell · Warnung

Eine Contract-Unit deklariert im interface eine Klasse. Contracts enthalten nur Records, Interfaces, Aufzählungen und Ausnahmen. Standardmäßig aus; in atlas.json mit der Option "prefixes" einschalten. Genehmigte Ausnahmen stehen unter "allow" als "Unit.Typ"-Globs.

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
## thread-vcl-access

**VCL-Zugriff aus einem Thread** · Bug · Warnung

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
## lock-without-finally

**Sperre ohne try/finally** · Bug · Warnung

Auf eine Sperre (TCriticalSection.Enter/Acquire, TMonitor.Enter, BeginRead/BeginWrite, TSpinLock.Enter, TMutex.Acquire, EnterCriticalSection oder ein Paar aus der Option lockPairs) folgt kein try/finally mit der Freigabe. Eine Ausnahme lässt die Sperre gesetzt.

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
## thread-use-after-free-on-terminate

**Thread nach dem Start mit FreeOnTerminate benutzt** · Bug · Warnung

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
## thread-free-with-free-on-terminate

**Free auf einem Thread mit FreeOnTerminate** · Bug · Fehler

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
## synchronize-in-destructor

**Synchronize im Destruktor eines Threads** · Bug · Warnung

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
## thread-resume-suspend

**Veraltetes TThread.Resume/Suspend** · Code Smell · Warnung

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
## result-not-set

**Funktionsergebnis eventuell nicht gesetzt** · Bug · Warnung

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
## possibly-uninitialized

**Variable eventuell nicht initialisiert** · Bug · Warnung

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
## unreachable-code

**Unerreichbarer Code** · Bug · Warnung

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
## unused-local

**Ungenutzte lokale Variable** · Code Smell · Hinweis

Eine lokale Variable ist deklariert, wird aber nie verwendet. Wie Compilerhinweis H2164, aber schon beim Tippen.

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
## unused-parameter

**Ungenutzter Parameter** · Code Smell · Hinweis

Ein Parameter wird im Rumpf der Routine nicht verwendet. Ausgenommen sind überschriebene und virtuelle Methoden, Ereignis-Handler, published-Methoden, Interface-Implementierungen und Callbacks.

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
## unused-assignment

**Zugewiesener Wert ungenutzt** · Code Smell · Hinweis

Ein einer lokalen Variable zugewiesener Wert wird überschrieben oder die Routine endet, bevor er gelesen wird. Wie Compilerhinweis H2077.

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
## declared-not-implemented

**Deklariert, aber nicht implementiert** · Bug · Fehler

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
## implemented-not-declared

**Implementiert, aber nicht deklariert** · Bug · Fehler

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
## destroy-without-override

**Destroy ohne override** · Bug · Warnung

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

<a id="component-create-without-override"></a>
## component-create-without-override

**Komponentenkonstruktor ohne override** · Bug · Warnung

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
## hides-virtual

**Methode verdeckt virtuelle Methode** · Bug · Warnung

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
## virtual-instead-of-override

**virtual statt override** · Bug · Warnung

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
## captured-loop-variable

**Erfasste Schleifenvariable** · Bug · Warnung

Eine anonyme Methode, die an eine verzögert ausführende API (TThread.Queue, TTask.Run …) geht, erfasst eine Variable, die sich vor dem Aufruf noch ändert, etwa die Variable einer for-in-Schleife. Delphi erfasst die Variable, nicht ihren Wert.

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
## component-missing-inherited

**Komponentenmethode ohne inherited** · Bug · Warnung

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
## component-default-mismatch

**default passt nicht zum Konstruktor** · Bug · Warnung

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
## component-missing-free-notification

**Komponentenreferenz ohne FreeNotification** · Bug · Warnung

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
## component-setter-without-invalidate

**Setter ohne Invalidate** · Code Smell · Hinweis

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
## component-fixed-pixels

**Feste Pixelwerte** · Code Smell · Warnung

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
## component-hardcoded-color

**Feste Farbe in Paint** · Code Smell · Hinweis

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
## form-field-without-object

**Formularfeld ohne Objekt** · Bug · Warnung

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
## form-object-without-field

**Formularobjekt ohne Feld** · Bug · Warnung

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
## form-field-type-mismatch

**Feldtyp weicht vom Formularobjekt ab** · Bug · Warnung

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
## security-command-injection

**Befehlsinjektion** · Schwachstelle · Warnung

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
## security-path-traversal

**Pfad-Traversal** · Schwachstelle · Warnung

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
## security-weak-crypto

**Schwache Kryptografie** · Sicherheits-Hotspot · Hinweis

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
## security-tls-verification-disabled

**TLS-Zertifikatsprüfung abgeschaltet** · Schwachstelle · Warnung

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
## security-insecure-http

**Unverschlüsselte http://-URL** · Sicherheits-Hotspot · Hinweis

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
## security-insecure-random

**Random für sicherheitsrelevante Werte** · Sicherheits-Hotspot · Warnung

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
## dfm-circular-datasource

**Zirkuläre Master-Detail- bzw. DataSource-Verknüpfung** · Bug · Warnung

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
## dfm-master-without-fields

**Master-Detail ohne MasterFields** · Bug · Warnung

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
## dfm-required-field-without-control

**Pflichtfeld ohne sichtbares Eingabe-Control** · Bug · Warnung

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
## dfm-control-field-type-mismatch

**Datensensitives Control passt nicht zum Feldtyp** · Bug · Warnung

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
## dfm-duplicate-binding

**Zwei Controls an demselben Feld** · Bug · Warnung

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
## dfm-property

**Komponenten-Property verletzt eine Eigenschaftsregel** · Code Smell · Warnung

Eine Komponenten-Property in der Formulardatei erfüllt eine Regel aus dfmPropertyRules in atlas.json nicht (Klasse, Property, Bedingung, Wert). Nicht gespeicherte Properties zählen mit ihrem default-Wert; Objekte aus dem Vorfahrenformular werden nur gemeldet, wenn dieses Formular den Wert selbst setzt.

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
## foreign-form-control-access

**Zugriff auf Controls eines anderen Formulars** · Code Smell · Warnung

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
## security-sql-injection

**SQL-Text aus zusammengesetzten Werten (SQL-Injection)** · Schwachstelle · Warnung

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
## slash-command

**Schnellbefehl nicht ausgeführt** · Code Smell · Hinweis

Eine Zeile, die mit /name beginnt, wurde nicht ausgeführt und steht noch im Code: Der Befehl ist unbekannt, abgeschaltet (slashCommands.disabled) oder passt an dieser Stelle nicht. Die Meldung nennt den Grund.

Mit Treffer:

```pascal
/gibtsnicht X
```

Richtig:

```pascal
/uses System.Classes
```

<a id="empty-except"></a>
## empty-except

**Leerer except-Block** · Code Smell · Warnung

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
## interface-guid

**Interface ohne GUID** · Bug · Warnung

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
## duplicate-interface-guid

**Zwei Interfaces mit derselben GUID** · Bug · Fehler

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
## file-header

**Dateikopf fehlt oder weicht ab** · Code Smell · Hinweis

Die Datei beginnt nicht mit dem Kopf aus der Regeloption "template". Standardmäßig aus; in atlas.json mit einer Vorlage einschalten. Die Schnellkorrektur fügt den Kopf ein.

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
## hardcoded-string

**Text im Code statt resourcestring** · Code Smell · Hinweis

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
## self-assignment

**Zuweisung an sich selbst** · Bug · Warnung

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
## for-high-to-low

**for-Schleife zählt mit to abwärts** · Bug · Warnung

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
## exception-not-raised

**Exception erzeugt, aber nicht ausgelöst** · Bug · Warnung

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
## assert-side-effect

**Assert mit Seiteneffekt** · Bug · Warnung

Das Argument von Assert verändert Daten (Inc, Dec, eine Try…-Funktion mit out-Parameter oder eine Methode aus der Option mutatingMethods). Mit {$C-} entfernt der Compiler den ganzen Aufruf samt Seiteneffekt.

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
## ifthen-side-effect

**IfThen wertet beide Zweige aus** · Bug · Warnung

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
## random-without-randomize

**Random ohne Randomize** · Code Smell · Hinweis

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
## int32-mul-overflow

**Int32-Multiplikation an Int64 zugewiesen** · Bug · Warnung

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
## sizeof-pointer

**SizeOf eines Zeigers in Move oder FillChar** · Bug · Fehler

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
## char-to-pchar

**Char nach PChar umgewandelt** · Bug · Fehler

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
## float-equality

**Gleitkommavergleich mit = oder <>** · Bug · Hinweis

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
## constructor-on-instance

**Konstruktor auf einer Instanz aufgerufen** · Bug · Warnung

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
## format-without-settings

**Formatierung abhängig vom Gebietsschema** · Code Smell · Hinweis

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
## generic-exception-raised

**Allgemeine Exception ausgelöst** · Code Smell · Hinweis

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
## catch-all-without-raise

**Exception-Handler ohne erneutes raise** · Code Smell · Warnung

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
## exception-freed

**Exception-Objekt manuell freigegeben** · Bug · Fehler

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
## string-concat-in-loop

**String-Verkettung in einer Schleife** · Code Smell · Hinweis

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
## loop-invariant-call

**Teurer Aufruf in der Schleifenbedingung** · Code Smell · Hinweis

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
## missing-begin-update

**Hinzufügen in einer Schleife ohne BeginUpdate** · Code Smell · Hinweis

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
## bool-compare

**Vergleich mit True oder False** · Code Smell · Hinweis

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
## redundant-assigned-free

**Assigned-Prüfung vor Free** · Code Smell · Hinweis

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
## raise-in-finally

**raise in einem finally-Block** · Bug · Warnung

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
## redundant-parens

**Überflüssige Klammern** · Code Smell · Hinweis

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
## redundant-begin-end

**begin … end um eine einzelne Anweisung** · Code Smell · Hinweis

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
## with-statement

**with-Anweisung** · Code Smell · Hinweis

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
## metric-method-length

**Methode zu lang** · Code Smell · Hinweis

Die Methode hat mehr Codezeilen als der Grenzwert (Vorgabe 60). Leerzeilen, Kommentare, Compiler-Direktiven und lokale Routinen zählen nicht mit. Die Methode in kleinere aufteilen. Den Grenzwert setzt die Option max, z. B. "rules": {"metric-method-length": {"max": 80}}.

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
## metric-nesting-depth

**Zu tief verschachtelt** · Code Smell · Hinweis

Die Methode verschachtelt if, case, Schleifen und try tiefer als der Grenzwert (Vorgabe 4). else if bleibt auf der Ebene seines if. Mit Exit oder Continue früh verlassen oder innere Teile in eigene Methoden auslagern. Den Grenzwert setzt die Option max.

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
## metric-cyclomatic-complexity

**Zyklomatische Komplexität zu hoch** · Code Smell · Hinweis

Die zyklomatische Komplexität der Methode liegt über dem Grenzwert (Vorgabe 15). Sie beginnt bei 1 und steigt um 1 je if, while, repeat und for, je case-Zweig ohne else, je and/or in einer Bedingung und je except on; ein except ohne on zählt einmal. Viele Pfade brauchen viele Tests. Den Grenzwert setzt die Option max.

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
## metric-cognitive-complexity

**Kognitive Komplexität zu hoch** · Code Smell · Hinweis

Die kognitive Komplexität der Methode liegt über dem Grenzwert (Vorgabe 15). Nach SonarSource zählen if, case, Schleifen und except-Behandler 1 plus ihre Schachtelungsebene; else, else if, goto und jede Folge gleicher logischer Operatoren zählen 1. Verschachtelter Code ist schwerer zu lesen als Code hintereinander. Den Grenzwert setzt die Option max.

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
## metric-parameter-count

**Zu viele Parameter** · Code Smell · Hinweis

Die Methode hat mehr Parameter als der Grenzwert (Vorgabe 6). Zusammengehörige Werte in einem Record oder einer Klasse bündeln. Den Grenzwert setzt die Option max.

Mit Treffer:

```pascal
procedure Book(const AName, AStreet, ACity, AZip: string; AAmount: Currency; ADate: TDate; ANote: string);
```

Richtig:

```pascal
procedure Book(const AAddress: TAddress; const AOrder: TOrder);
```

<a id="todo-comment"></a>
## todo-comment

**Offener TODO-Kommentar** · Code Smell · Hinweis

Ein Kommentar beginnt mit einer Marke für offene Arbeit: // TODO, // FIXME oder das Format der IDE-To-Do-Liste { TODO 1 -oPerson -cKategorie : Text }. Der Hinweis zeigt Marke, Priorität, Kategorie, Person und Text, damit offene Arbeit in der Problemliste erscheint. In der Vorgabe aus; in atlas.json einschalten, z. B. "rules": {"todo-comment": {"severity": "hint"}}. Erledigte Einträge ({ DONE … }) meldet die Regel nie. Die Option keywords legt die Marken fest (Vorgabe ["TODO", "FIXME"]); sie gilt auch für get_todos und --todos.

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
## component-palette-icon

**Registrierte Komponente ohne Palettensymbol** · Code Smell · Hinweis

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
## unresolved-identifier

**Nicht deklarierter Bezeichner** · Bug · Warnung

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
