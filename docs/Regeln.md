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
| [`unit-name-mismatch`](#unit-name-mismatch) | Unit-Name passt nicht zum Dateinamen | Bug | Warnung |
| [`forbidden-uses`](#forbidden-uses) | Verbotene uses-Beziehung | Code Smell | Fehler |
| [`lock-without-finally`](#lock-without-finally) | Sperre ohne try/finally | Bug | Warnung |
| [`thread-used-after-start`](#thread-used-after-start) | Thread nach dem Start mit FreeOnTerminate benutzt | Bug | Warnung |
| [`synchronize-in-destructor`](#synchronize-in-destructor) | Synchronize im Destruktor | Bug | Warnung |
| [`deprecated-suspend-resume`](#deprecated-suspend-resume) | Veraltetes TThread.Suspend/Resume | Code Smell | Hinweis |
| [`thread-free-without-waitfor`](#thread-free-without-waitfor) | Thread ohne WaitFor freigegeben | Bug | Hinweis |

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

<a id="unit-name-mismatch"></a>
## unit-name-mismatch

**Unit-Name passt nicht zum Dateinamen** · Bug · Warnung

Der Name in der unit-Zeile weicht vom Dateinamen ab; der Compiler findet die Unit dann über uses nicht.

Mit Treffer:

```pascal
{ Helpers.pas }
unit Tools;
```

Richtig:

```pascal
{ Helpers.pas }
unit Helpers;
```

<a id="forbidden-uses"></a>
## forbidden-uses

**Verbotene uses-Beziehung** · Code Smell · Fehler

Ein uses-Eintrag verletzt eine Schichtregel unter "layers" in delphi-lsp.json, z. B. darf *.Common.* nicht Vcl.* verwenden.

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

<a id="lock-without-finally"></a>
## lock-without-finally

**Sperre ohne try/finally** · Bug · Warnung

Auf eine Sperre (Enter, Acquire, BeginWrite, BeginRead, LockList, Lock, TMonitor.Enter) folgt kein try/finally mit der Freigabe. Eine Ausnahme lässt die Sperre gesetzt.

Mit Treffer:

```pascal
FLock.Enter;
DoWork;
FLock.Leave;
```

Richtig:

```pascal
FLock.Enter;
try
  DoWork;
finally
  FLock.Leave;
end;
```

<a id="thread-used-after-start"></a>
## thread-used-after-start

**Thread nach dem Start mit FreeOnTerminate benutzt** · Bug · Warnung

Ein Thread mit FreeOnTerminate := True kann sich gleich nach dem Start selbst freigeben; danach greift die Variable womöglich auf ein freigegebenes Objekt zu.

Mit Treffer:

```pascal
T.FreeOnTerminate := True;
T.Start;
T.WaitFor;
```

Richtig:

```pascal
T.FreeOnTerminate := True;
T.Start;
T := nil;
```

<a id="synchronize-in-destructor"></a>
## synchronize-in-destructor

**Synchronize im Destruktor** · Bug · Warnung

Synchronize im Destruktor verklemmt sich, wenn der Hauptthread auf die Freigabe wartet.

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

<a id="deprecated-suspend-resume"></a>
## deprecated-suspend-resume

**Veraltetes TThread.Suspend/Resume** · Code Smell · Hinweis

TThread.Resume und Suspend sind veraltet. Einen erzeugten Thread mit Start starten, statt Suspend mit einem Ereignis warten.

Mit Treffer:

```pascal
FWorker.Resume;
```

Richtig:

```pascal
FWorker.Start;
```

<a id="thread-free-without-waitfor"></a>
## thread-free-without-waitfor

**Thread ohne WaitFor freigegeben** · Bug · Hinweis

Eine Thread-Variable wird ohne vorheriges WaitFor in derselben Routine freigegeben. TThread.Destroy wartet zwar selbst, Fehler und Ende des Threads bleiben aber unbemerkt. Experimentell.

Mit Treffer:

```pascal
FWorkerThread.Free;
```

Richtig:

```pascal
FWorkerThread.Terminate;
FWorkerThread.WaitFor;
FWorkerThread.Free;
```
