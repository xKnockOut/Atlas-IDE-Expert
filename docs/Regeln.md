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
| [`thread-vcl-access`](#thread-vcl-access) | VCL-Zugriff aus einem Thread | Bug | Warnung |
| [`lock-without-finally`](#lock-without-finally) | Sperre ohne try/finally | Bug | Warnung |
| [`thread-use-after-free-on-terminate`](#thread-use-after-free-on-terminate) | Thread nach dem Start mit FreeOnTerminate benutzt | Bug | Warnung |
| [`thread-free-with-free-on-terminate`](#thread-free-with-free-on-terminate) | Free auf einem Thread mit FreeOnTerminate | Bug | Fehler |
| [`synchronize-in-destructor`](#synchronize-in-destructor) | Synchronize im Destruktor eines Threads | Bug | Warnung |
| [`thread-resume-suspend`](#thread-resume-suspend) | Veraltetes TThread.Resume/Suspend | Code Smell | Warnung |
| [`result-not-set`](#result-not-set) | Funktionsergebnis eventuell nicht gesetzt | Bug | Warnung |
| [`possibly-uninitialized`](#possibly-uninitialized) | Variable eventuell nicht initialisiert | Bug | Warnung |
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
| [`foreign-form-control-access`](#foreign-form-control-access) | Zugriff auf Controls eines anderen Formulars | Code Smell | Warnung |
| [`security-sql-injection`](#security-sql-injection) | SQL-Text aus zusammengesetzten Werten (SQL-Injection) | Schwachstelle | Warnung |

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

Ein uses-Eintrag verletzt eine Schichtregel unter "layers" in argus.json, z. B. darf *.Common.* nicht Vcl.* verwenden.

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
