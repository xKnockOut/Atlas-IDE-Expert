unit Atlas.Core.Diagnostics.Guard;

// Absturzsicherheit (#493), Teil ohne Windows und Open Tools API:
// - TAtlasGuard.Run: jeder Einstiegspunkt aus der IDE (Timer, Notifier,
//   Zeichnen, Tasten) läuft hierüber. Exceptions verlassen Atlas nie in
//   Richtung IDE; sie werden protokolliert und dem Feature angerechnet.
// - Sicherung: 3 Fehler eines Features innerhalb von 5 Minuten schalten nur
//   dieses Feature ab (Run tut dann nichts mehr), mit einer Warnung über
//   OnWarning und OnTripped (Eintrag in der Benachrichtigungszentrale).
//   Wieder einschalten über Reset (Menü Atlas).
// - Ein Feature je sichtbarer Funktion: Früher teilten sich rund 40 Units die
//   Sicherung „Editorbefehle“, und ein Zeichenfehler der Minimap schaltete
//   Gliederung, Brotkrumen, Sticky Scroll und den Rest mit ab. EditorCommands
//   gilt nur noch für ausdrücklich aufgerufene Editorbefehle.
// - Derselbe Fehler (Klasse und Stelle) eines Features innerhalb von RepeatMs
//   nach dem zuletzt gezählten zählt nicht erneut und steht nicht einzeln im
//   Protokoll: Ein Zeichendurchlauf meldet einen Fehler sonst für jede Zeile
//   und löste die Sicherung in einer Millisekunde aus. Die nächste gezählte
//   Zeile nennt, wie oft er seit der letzten Meldung übergangen wurde.
// - Sicherung je Quelle (Provider): ReportProvider zählt Fehler einer
//   einzelnen Datenquelle, etwa der Vervollständigung vom Server; nach 3
//   Fehlern in 5 Minuten fällt nur diese Quelle aus, die übrigen laufen weiter.
// - Langsame Quelle: Eine Zeitüberschreitung ist kein Fehler und zählt nicht
//   zur Sicherung (früher schaltete ein beschäftigter Rechner so Quellen ab).
//   ReportProviderSlow schreibt je Quelle höchstens eine Zeile je
//   SlowLogSeconds mit der Zahl der übergangenen Meldungen.
// - TAtlasRotatingLog: Protokoll unter %LOCALAPPDATA%\Atlas\Logs, höchstens
//   5 Dateien à 1 MB. Jede Fehlerzeile nennt Atlas-Version, Feature bzw.
//   Quelle, Fehlerklasse, Meldung (eine Zeile, gekürzt) und den Stack-Trace;
//   nie Quelltext aus dem Editor. Den Stack-Trace liefert Exception.StackTrace
//   (falls ein Anbieter installiert ist), sonst der Haken StackOf
//   (Atlas.IDE.Diagnostics.StackCapture: Mitschnitt beim Auslösen).
// - Schreibfehler des Protokolls (Bericht M4): Früher verschluckte Add jeden
//   Fehler, und ein Fehler beim Rotieren verhinderte auch das Anhängen (das
//   erklärt Lücken wie die ab dem 21.10. 21:29, belegt ist es nicht). Jetzt sperrt ein
//   benannter Mutex je Ordner Rotieren und Schreiben über alle IDE-Prozesse
//   (Marcos IDE und die von Claude-Compile gestarteten teilen den Ordner;
//   ohne Sperre öffneten zwei Schreiber dieselbe Datei exklusiv). Scheitert
//   das Rotieren, wird trotzdem angehängt und der Grund einmal vermerkt.
//   Scheitert das Anhängen, zählt Add die verlorenen Zeilen, meldet den
//   ersten Fehler (und jeden neuen Grund) über OnError und schreibt beim
//   nächsten Gelingen eine Zeile über die Lücke.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections;

type
{$SCOPEDENUMS ON}
  TAtlasFeature = (Completion, Signature, Hover, Pairs, Problems, Reloader, Palette, CheckOnSave, Watchdog, Server,
    Settings, Menu, Files, InlayHints, Results, EditorCommands, Forms, Build, Status, WelcomePage, ShortcutTips,
    Notes, Bookmarks, Notifications, Breadcrumbs, Outline, StickyScroll, Minimap, LineChanges, GutterColumn,
    RecursionMarkers, OverviewRuler, SelectionMatches, MultiCursor, LinkedEditing, CodeLens, NavHistory, Peek,
    SmartPaste, WrapSelection, Unwrap, Hide, Search, UnitSearch, Generate, ContinueLines, SlashCommands,
    GoToDefinition, EditorToolbar, QuickBookmarks, StatusBar, Architecture, UnitRelations, SymbolPath, Tasks, Debugger);
{$SCOPEDENUMS OFF}

  TAtlasFeatures = set of TAtlasFeature;

  /// <summary>Protokoll gestört: Grund des Schreibfehlers; '' = schreibt wieder.</summary>
  TAtlasLogError = reference to procedure(const AMessage: string);

  TAtlasRotatingLog = class
  private
    FFolder: string;
    FMaxBytes: Int64;
    FMaxFiles: Integer;
    FLock: TCriticalSection;
    /// <summary>Seit dem letzten gelungenen Schreiben verlorene Zeilen.</summary>
    FFailed: Integer;
    /// <summary>Verlorene Zeilen seit dem Start.</summary>
    FLost: Integer;
    FLastError: string;
    FRotateError: string;
    FOnError: TAtlasLogError;
    procedure Rotate;
    function AppendLine(const ALine: string): string;
    function Clean(const AText: string): string;
  public
    /// <summary>So lange wartet Add auf einen anderen Prozess, der gerade schreibt; danach schreibt es trotzdem.
    /// </summary>
    const LockTimeoutMs = 2000;
    constructor Create(const AFolder: string; AMaxBytes: Int64 = 1024 * 1024; AMaxFiles: Integer = 5);
    destructor Destroy; override;
    /// <summary>Zeile mit Zeitstempel anhängen. Wirft nie; ein Schreibfehler zählt die Zeile als verloren und meldet
    /// sich über OnError.</summary>
    procedure Add(const AText: string);
    /// <summary>Name des benannten Mutex für AFolder (Groß-/Kleinschreibung und Schlussstrich egal).</summary>
    class function MutexName(const AFolder: string): string; static;
    /// <summary>Aktuelle Datei (atlas.log); ältere heißen atlas.1.log … atlas.4.log.</summary>
    function FileName: string;
    /// <summary>Ordner der Protokolldateien (Tests stellen ihn um).</summary>
    property Folder: string read FFolder write FFolder;
    /// <summary>Seit dem Start verlorene Zeilen.</summary>
    property Lost: Integer read FLost;
    /// <summary>Grund des letzten Schreibfehlers; '' = das letzte Schreiben gelang.</summary>
    property LastError: string read FLastError;
    /// <summary>Erster Schreibfehler nach einem gelungenen Schreiben und jeder neue Grund; '' sobald wieder
    /// geschrieben wird. Läuft außerhalb der Sperren im Thread des Schreibers und darf selbst protokollieren.
    /// </summary>
    property OnError: TAtlasLogError read FOnError write FOnError;
    /// <summary>%LOCALAPPDATA%\Atlas\Logs.</summary>
    class function DefaultFolder: string; static;
  end;

  TAtlasFuse = class
  public const
    Limit = 3;
    WindowMinutes = 5;
    /// <summary>Derselbe Fehler eines Features so kurz nach dem zuletzt gezählten zählt nicht erneut.</summary>
    RepeatMs = 1000;
    /// <summary>Langsame Quelle: höchstens eine Protokollzeile je Quelle in diesem Abstand.</summary>
    SlowLogSeconds = 60;
  private
    FFailures: array[TAtlasFeature] of TArray<TDateTime>;
    // Zuletzt gezählter Fehler je Feature (Schlüssel, Zeit) und übergangene Wiederholungen seitdem.
    FLastKey: array[TAtlasFeature] of string;
    FLastCounted: array[TAtlasFeature] of TDateTime;
    FRepeats: array[TAtlasFeature] of Integer;
    FTripped: TAtlasFeatures;
    FProviderFailures: TDictionary<string, TArray<TDateTime>>;
    // Kleingeschriebener Name → Name wie gemeldet.
    FProvidersTripped: TDictionary<string, string>;
    // Langsame Quellen, kleingeschriebener Name → Zeit der letzten Protokollzeile bzw. seitdem übergangene.
    FSlowLogged: TDictionary<string, TDateTime>;
    FSlowSkipped: TDictionary<string, Integer>;
    FClock: TFunc<TDateTime>;
    FLock: TCriticalSection;
    /// <summary>Zählt einen Fehler zu AStamps; True, wenn es Limit Fehler im Zeitfenster sind.</summary>
    function Count(var AStamps: TArray<TDateTime>): Boolean;
  public
    constructor Create(const AClock: TFunc<TDateTime> = nil);
    destructor Destroy; override;
    /// <summary>Fehler zählen; True, wenn die Sicherung dadurch gerade auslöst.</summary>
    function Failed(AFeature: TAtlasFeature): Boolean; overload;
    /// <summary>Wie Failed, mit dem Schlüssel des Fehlers (Klasse und Stelle). Derselbe Schlüssel innerhalb von
    /// RepeatMs nach dem zuletzt gezählten zählt nicht (ARepeat = True). ASkipped: so viele Wiederholungen des
    /// zuletzt gezählten Fehlers wurden seitdem übergangen.</summary>
    function Failed(AFeature: TAtlasFeature; const AKey: string; out ARepeat: Boolean;
      out ASkipped: Integer): Boolean; overload;
    function Tripped(AFeature: TAtlasFeature): Boolean;
    function TrippedSet: TAtlasFeatures;
    procedure Reset(AFeature: TAtlasFeature);
    /// <summary>Wie Failed, für eine einzelne Quelle (Name ohne Groß-/Kleinschreibung).</summary>
    function ProviderFailed(const AName: string): Boolean;
    function ProviderTripped(const AName: string): Boolean;
    function TrippedProviders: TArray<string>;
    procedure ResetProvider(const AName: string);
    /// <summary>Langsame Antwort der Quelle AName, kein Fehler: True, wenn eine Protokollzeile fällig ist (die
    /// erste, danach höchstens eine je SlowLogSeconds). ASkipped: seit der letzten Zeile übergangene Meldungen.
    /// </summary>
    function ProviderSlow(const AName: string; out ASkipped: Integer): Boolean;
    /// <summary>Alle Features und Quellen.</summary>
    procedure ResetAll;
  end;

  TAtlasGuardMessage = reference to procedure(const AText: string);
  /// <summary>Stacktrace zur gerade behandelten Ausnahme; '' ohne.</summary>
  TAtlasGuardStackFunc = reference to function(E: Exception): string;
  /// <summary>Sicherung eines Features hat ausgelöst; AMessage ist die letzte Fehlermeldung (gekürzt).</summary>
  TAtlasGuardTripped = reference to procedure(AFeature: TAtlasFeature; const AMessage: string);

  TAtlasGuard = class
  private class var
    FFuse: TAtlasFuse;
    FLog: TAtlasRotatingLog;
    FOnWarning: TAtlasGuardMessage;
    FOnFailure: TProc<TAtlasFeature>;
    FStackOf: TAtlasGuardStackFunc;
    FOnTripped: TAtlasGuardTripped;
    class procedure Warn(const AText: string); static;
    class function ErrorLine(const AWhere: string; E: Exception): string; static;
    /// <summary>Klasse und Stelle (ExceptAddr) des gerade behandelten Fehlers; ohne Stelle Klasse und Meldung.
    /// </summary>
    class function FailureKey(E: Exception): string; static;
  public
    /// <summary>Höchstlänge einer Fehlermeldung im Protokoll; mehr könnte Quelltext enthalten.</summary>
    const MaxMessageLength = 300;
    class constructor Create;
    class destructor Destroy;
    /// <summary>Führt AProc geschützt aus; False bei Fehler oder abgeschaltetem Feature.</summary>
    class function Run(AFeature: TAtlasFeature; const AProc: TProc): Boolean; static;
    /// <summary>Fehler aus einem eigenen except-Block melden (zählt wie in Run).</summary>
    class procedure Report(AFeature: TAtlasFeature; E: Exception); static;
    /// <summary>Feature durch die Sicherung abgeschaltet?</summary>
    class function Disabled(AFeature: TAtlasFeature): Boolean; static;
    class procedure Enable(AFeature: TAtlasFeature); static;
    class procedure EnableAll; static;
    class function DisabledSet: TAtlasFeatures; static;
    /// <summary>Protokolliert eine Zeile ins rotierende Protokoll.</summary>
    class procedure Log(const AText: string); static;
    class function FeatureName(AFeature: TAtlasFeature): string; static;
    /// <summary>Fehler der Quelle AName melden; nach 3 in 5 Minuten fällt nur sie aus.</summary>
    class procedure ReportProvider(const AName: string; E: Exception); overload; static;
    class procedure ReportProvider(const AName, AMessage: string); overload; static;
    /// <summary>Quelle AName war zu langsam (Zeitlimit überschritten oder vorige Anfrage läuft noch): zählt nicht
    /// zur Sicherung; eine Protokollzeile je Quelle und SlowLogSeconds mit der Zahl der übergangenen.</summary>
    class procedure ReportProviderSlow(const AName, AText: string); static;
    /// <summary>Führt AProc für die Quelle AName geschützt aus; False bei Fehler oder abgeschalteter Quelle.</summary>
    class function RunProvider(const AName: string; const AProc: TProc): Boolean; static;
    class function ProviderDisabled(const AName: string): Boolean; static;
    class procedure EnableProvider(const AName: string); static;
    class function DisabledProviders: TArray<string>; static;
    /// <summary>Meldung einzeilig und gekürzt, damit kein Quelltext ins Protokoll gelangt.</summary>
    class function SafeMessage(const AText: string): string; static;
    /// <summary>Warnungen für die Meldungsansicht (nie als Dialog).</summary>
    class property OnWarning: TAtlasGuardMessage read FOnWarning write FOnWarning;
    /// <summary>Nach jedem gezählten Fehler eines Features, aus jedem Thread (Startmarke des abgesicherten
    /// Starts, #722).</summary>
    class property OnFailure: TProc<TAtlasFeature> read FOnFailure write FOnFailure;
    /// <summary>Stacktrace für Fehlerzeilen, wenn E.StackTrace leer ist (im except-Block aufgerufen).</summary>
    class property StackOf: TAtlasGuardStackFunc read FStackOf write FStackOf;
    /// <summary>Nach dem Auslösen der Sicherung eines Features (Benachrichtigungszentrale), im Thread des Fehlers.
    /// </summary>
    class property OnTripped: TAtlasGuardTripped read FOnTripped write FOnTripped;
    class property Fuse: TAtlasFuse read FFuse;
    class property RotatingLog: TAtlasRotatingLog read FLog;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.Product.Version;

{ TAtlasRotatingLog }

constructor TAtlasRotatingLog.Create(const AFolder: string; AMaxBytes: Int64; AMaxFiles: Integer);
begin
  inherited Create;
  FFolder := AFolder;
  FMaxBytes := AMaxBytes;
  FMaxFiles := AMaxFiles;
  FLock := TCriticalSection.Create;
end;

destructor TAtlasRotatingLog.Destroy;
begin
  FLock.Free;
  inherited;
end;

class function TAtlasRotatingLog.MutexName(const AFolder: string): string;
var
  Key: string;
  Hash: Cardinal;
  Index: Integer;
begin
  // FNV-1a über den Ordner; ein Mutexname darf außer nach „Local\“ keinen Backslash enthalten.
  Key := UpperCase(ExcludeTrailingPathDelimiter(AFolder));
  Hash := 2166136261;
  for Index := 1 to Length(Key) do
    Hash := Cardinal((UInt64(Hash xor Ord(Key[Index])) * 16777619) and $FFFFFFFF);
  Result := 'Local\Atlas.Log.' + IntToHex(Hash, 8);
end;

class function TAtlasRotatingLog.DefaultFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), 'Logs');
end;

function TAtlasRotatingLog.FileName: string;
begin
  Result := TPath.Combine(FFolder, 'atlas.log');
end;

procedure TAtlasRotatingLog.Rotate;
var
  Index: Integer;
  Older, Newer: string;
begin
  // atlas.log → atlas.1.log → … → atlas.(Max-1).log; die älteste fällt weg.
  for Index := FMaxFiles - 1 downto 1 do
  begin
    Older := TPath.Combine(FFolder, Format('atlas.%d.log', [Index]));
    if Index = 1 then
      Newer := FileName
    else
      Newer := TPath.Combine(FFolder, Format('atlas.%d.log', [Index - 1]));
    if TFile.Exists(Older) then
      TFile.Delete(Older);
    if TFile.Exists(Newer) then
      TFile.Move(Newer, Older);
  end;
end;

/// <summary>Fehlermeldung fürs Protokoll: ohne den Ordner (enthält den Benutzernamen), einzeilig und gekürzt.</summary>
function TAtlasRotatingLog.Clean(const AText: string): string;
begin
  Result := TAtlasGuard.SafeMessage(StringReplace(AText, ExcludeTrailingPathDelimiter(FFolder), 'Logs',
    [rfReplaceAll, rfIgnoreCase]));
end;

/// <summary>Rotieren und Anhängen unter der prozessübergreifenden Sperre; '' = geschrieben, sonst der Grund. Nur
/// unter FLock.</summary>
function TAtlasRotatingLog.AppendLine(const ALine: string): string;
var
  Lock: TMutex;
  Owned: Boolean;
  Stamp, Lines: string;
begin
  Result := '';
  try
    ForceDirectories(FFolder);
    // Je Zeile öffnen statt im Objekt halten: Der Ordner kann wechseln (Tests stellen ihn um), und eine gehaltene
    // Sperre bliebe samt Pfad stehen.
    Lock := TMutex.Create(nil, False, MutexName(FFolder));
    try
      // Abgebrochen heißt: Ein anderer Prozess endete beim Schreiben; die Sperre gehört dann uns.
      Owned := Lock.WaitFor(LockTimeoutMs) in [wrSignaled, wrAbandoned];
      try
        Stamp := FormatDateTime('yyyy-mm-dd hh":"nn":"ss.zzz', Now) + ' ';
        Lines := '';
        if TFile.Exists(FileName) and (TFile.GetSize(FileName) >= FMaxBytes) then
          try
            Rotate;
            FRotateError := '';
          except
            // Rotieren gescheitert (z. B. eine ältere Datei ist woanders gesperrt): trotzdem anhängen, die Datei wird
            // dann größer. Früher ging dabei auch die Zeile verloren, bei jedem Versuch wieder.
            on E: Exception do
              if E.Message <> FRotateError then
              begin
                FRotateError := E.Message;
                Lines := Stamp + 'Protokoll: Rotieren gescheitert (' + E.ClassName + ': ' + Clean(E.Message) +
                  '); schreibe weiter in atlas.log' + sLineBreak;
              end;
          end;
        if FFailed > 0 then
          Lines := Lines + Stamp + Format('Protokoll: %d Zeilen nicht geschrieben (zuletzt: %s)',
            [FFailed, Clean(FLastError)]) + sLineBreak;
        TFile.AppendAllText(FileName, Lines + ALine, TEncoding.UTF8);
      finally
        if Owned then
          Lock.Release;
      end;
    finally
      Lock.Free;
    end;
  except
    on E: Exception do
      Result := E.ClassName + ': ' + E.Message;
  end;
end;

procedure TAtlasRotatingLog.Add(const AText: string);
var
  Failure, Error: string;
  Notify: Boolean;
begin
  FLock.Enter;
  try
    Failure := AppendLine(FormatDateTime('yyyy-mm-dd hh":"nn":"ss.zzz', Now) + ' ' + AText + sLineBreak);
    if Failure = '' then
    begin
      Notify := FFailed > 0;
      FFailed := 0;
      FLastError := '';
    end
    else
    begin
      Inc(FFailed);
      Inc(FLost);
      Notify := Failure <> FLastError;
      FLastError := Failure;
    end;
    Error := FLastError;
  finally
    FLock.Leave;
  end;
  // Außerhalb der Sperren: Der Empfänger darf selbst protokollieren.
  if Notify and Assigned(FOnError) then
    FOnError(Error);
end;

{ TAtlasFuse }

constructor TAtlasFuse.Create(const AClock: TFunc<TDateTime>);
begin
  inherited Create;
  FClock := AClock;
  if not Assigned(FClock) then
    FClock :=
      function: TDateTime
      begin
        Result := Now;
      end;
  FLock := TCriticalSection.Create;
  FProviderFailures := TDictionary<string, TArray<TDateTime>>.Create;
  FProvidersTripped := TDictionary<string, string>.Create;
  FSlowLogged := TDictionary<string, TDateTime>.Create;
  FSlowSkipped := TDictionary<string, Integer>.Create;
end;

destructor TAtlasFuse.Destroy;
begin
  FSlowSkipped.Free;
  FSlowLogged.Free;
  FProvidersTripped.Free;
  FProviderFailures.Free;
  FLock.Free;
  inherited;
end;

function TAtlasFuse.Count(var AStamps: TArray<TDateTime>): Boolean;
var
  Time, Stamp: TDateTime;
  Recent: TArray<TDateTime>;
begin
  Time := FClock;
  Recent := nil;
  for Stamp in AStamps do
    if MinutesBetween(Time, Stamp) < WindowMinutes then
      Recent := Recent + [Stamp];
  Recent := Recent + [Time];
  AStamps := Recent;
  Result := Length(Recent) >= Limit;
end;

function TAtlasFuse.Failed(AFeature: TAtlasFeature): Boolean;
var
  Repeated: Boolean;
  Skipped: Integer;
begin
  Result := Failed(AFeature, '', Repeated, Skipped);
end;

function TAtlasFuse.Failed(AFeature: TAtlasFeature; const AKey: string; out ARepeat: Boolean;
  out ASkipped: Integer): Boolean;
var
  Time: TDateTime;
begin
  FLock.Enter;
  try
    Result := False;
    ARepeat := False;
    ASkipped := 0;
    Time := FClock;
    // Fester Abstand ab dem zuletzt gezählten, nicht gleitend: Ein Fehler, der bei jedem Zeichnen kommt, zählt so
    // einmal je RepeatMs und löst die Sicherung weiterhin aus.
    if (AKey <> '') and (AKey = FLastKey[AFeature]) and
      (MilliSecondsBetween(Time, FLastCounted[AFeature]) < RepeatMs) then
    begin
      ARepeat := True;
      Inc(FRepeats[AFeature]);
      Exit;
    end;
    ASkipped := FRepeats[AFeature];
    FLastKey[AFeature] := AKey;
    FLastCounted[AFeature] := Time;
    FRepeats[AFeature] := 0;
    if AFeature in FTripped then
      Exit;
    if Count(FFailures[AFeature]) then
    begin
      Include(FTripped, AFeature);
      Result := True;
    end;
  finally
    FLock.Leave;
  end;
end;

function TAtlasFuse.ProviderFailed(const AName: string): Boolean;
var
  Key: string;
  Stamps: TArray<TDateTime>;
begin
  Key := AnsiLowerCase(AName);
  FLock.Enter;
  try
    Result := False;
    if FProvidersTripped.ContainsKey(Key) then
      Exit;
    if not FProviderFailures.TryGetValue(Key, Stamps) then
      Stamps := nil;
    if Count(Stamps) then
    begin
      FProvidersTripped.Add(Key, AName);
      Result := True;
    end;
    FProviderFailures.AddOrSetValue(Key, Stamps);
  finally
    FLock.Leave;
  end;
end;

function TAtlasFuse.ProviderSlow(const AName: string; out ASkipped: Integer): Boolean;
var
  Key: string;
  Time, Logged: TDateTime;
begin
  Key := AnsiLowerCase(AName);
  FLock.Enter;
  try
    Time := FClock;
    if not FSlowSkipped.TryGetValue(Key, ASkipped) then
      ASkipped := 0;
    Result := not FSlowLogged.TryGetValue(Key, Logged) or (SecondsBetween(Time, Logged) >= SlowLogSeconds);
    if Result then
    begin
      FSlowLogged.AddOrSetValue(Key, Time);
      FSlowSkipped.AddOrSetValue(Key, 0);
    end
    else
    begin
      FSlowSkipped.AddOrSetValue(Key, ASkipped + 1);
      ASkipped := 0;
    end;
  finally
    FLock.Leave;
  end;
end;

function TAtlasFuse.ProviderTripped(const AName: string): Boolean;
begin
  FLock.Enter;
  try
    Result := FProvidersTripped.ContainsKey(AnsiLowerCase(AName));
  finally
    FLock.Leave;
  end;
end;

function TAtlasFuse.TrippedProviders: TArray<string>;
begin
  FLock.Enter;
  try
    Result := FProvidersTripped.Values.ToArray;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasFuse.ResetProvider(const AName: string);
var
  Key: string;
begin
  Key := AnsiLowerCase(AName);
  FLock.Enter;
  try
    FProvidersTripped.Remove(Key);
    FProviderFailures.Remove(Key);
  finally
    FLock.Leave;
  end;
end;

function TAtlasFuse.Tripped(AFeature: TAtlasFeature): Boolean;
begin
  FLock.Enter;
  try
    Result := AFeature in FTripped;
  finally
    FLock.Leave;
  end;
end;

function TAtlasFuse.TrippedSet: TAtlasFeatures;
begin
  FLock.Enter;
  try
    Result := FTripped;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasFuse.Reset(AFeature: TAtlasFeature);
begin
  FLock.Enter;
  try
    Exclude(FTripped, AFeature);
    FFailures[AFeature] := nil;
    FLastKey[AFeature] := '';
    FRepeats[AFeature] := 0;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasFuse.ResetAll;
var
  Feature: TAtlasFeature;
begin
  for Feature := Low(TAtlasFeature) to High(TAtlasFeature) do
    Reset(Feature);
  FLock.Enter;
  try
    FProvidersTripped.Clear;
    FProviderFailures.Clear;
    FSlowLogged.Clear;
    FSlowSkipped.Clear;
  finally
    FLock.Leave;
  end;
end;

{ TAtlasGuard }

class constructor TAtlasGuard.Create;
begin
  FFuse := TAtlasFuse.Create;
  FLog := TAtlasRotatingLog.Create(TAtlasRotatingLog.DefaultFolder);
end;

class destructor TAtlasGuard.Destroy;
begin
  FOnWarning := nil;
  FStackOf := nil;
  FOnTripped := nil;
  FreeAndNil(FLog);
  FreeAndNil(FFuse);
end;

class function TAtlasGuard.FeatureName(AFeature: TAtlasFeature): string;
const
  Names: array[TAtlasFeature] of string = ('Vervollständigung', 'Parameter-Hint', 'Tooltip', 'Klammerpaare',
    'Probleme', 'Neuladen', 'Befehlspalette', 'Prüfung beim Speichern', 'Wächter', 'Server', 'Einstellungen', 'Menü',
    'Dateien', 'Inlay-Hints', 'Ergebnisfenster', 'Editorbefehle', 'Formulare', 'Compile-Ereignisse', 'Statusfeld',
    'Willkommensseite', 'Tastenkürzel-Tipps', 'Notizen', 'Lesezeichen',
    'Benachrichtigungen', 'Brotkrumenleiste', 'Gliederung', 'Mitlaufender Kopf', 'Minimap', 'Änderungsmarken',
    'Atlas-Spalte', 'Rekursionssymbole', 'Übersichtsleiste', 'Gleichen Text hervorheben', 'Mehrere Einfügemarken',
    'Bezeichner mitziehen', 'Code Lens', 'Navigationsverlauf', 'Definition einblenden', 'Einfügen mit uses-Ergänzung',
    'Markierung umschließen', 'Umschließung entfernen', 'Ausblenden am Element', 'Atlas-Suche', 'Units suchen',
    'Erzeugen-Menü', 'Kommentar und Muster fortsetzen', 'Schnellbefehle', 'Gehe zu Definition', 'Editorleiste',
    'Schnelle Lesezeichen', 'Atlas-Statusleiste', 'Architekturübersicht', 'Unit-Beziehungen',
    'Weg zwischen Symbolen', 'Projektaufgaben', 'Debuggen');
begin
  Result := Names[AFeature];
end;

class procedure TAtlasGuard.Log(const AText: string);
begin
  if FLog <> nil then
    FLog.Add(AText);
end;

class function TAtlasGuard.SafeMessage(const AText: string): string;
var
  Builder: TStringBuilder;
  Ch: Char;
  Space: Boolean;
begin
  // Zeilenumbrüche und Steuerzeichen werden zu einem Leerzeichen; Folgen davon zu einem.
  Builder := TStringBuilder.Create;
  try
    Space := False;
    for Ch in AText do
      if CharInSet(Ch, [#0..#32]) then
        Space := True
      else
      begin
        if Space and (Builder.Length > 0) then
          Builder.Append(' ');
        Space := False;
        Builder.Append(Ch);
      end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
  if Length(Result) > MaxMessageLength then
    Result := Copy(Result, 1, MaxMessageLength) + '…';
end;

class function TAtlasGuard.ErrorLine(const AWhere: string; E: Exception): string;
var
  Trace: string;
begin
  Result := Format('Atlas %s · Fehler in %s: %s: %s', [TAtlasPluginVersion.Version, AWhere, E.ClassName,
    SafeMessage(E.Message)]);
  // E.StackTrace nur mit installiertem Anbieter (JCL, madExcept); sonst der Mitschnitt des Plugins.
  Trace := Trim(E.StackTrace);
  if (Trace = '') and Assigned(FStackOf) then
    try
      Trace := Trim(FStackOf(E));
    except
      // Sicherheitsnetz: Ein Fehler beim Auflösen darf die Fehlerzeile selbst nicht verhindern.
      on Inner: Exception do
        Trace := 'nicht verfügbar (' + Inner.ClassName + ')';
    end;
  if Trace <> '' then
    Result := Result + sLineBreak + '  Stack: ' + StringReplace(Trace, sLineBreak, sLineBreak + '  ', [rfReplaceAll]);
end;

class procedure TAtlasGuard.Warn(const AText: string);
begin
  Log(AText);
  if Assigned(FOnWarning) then
    try
      FOnWarning(AText);
    except
      // Auch die Warnung darf nicht in die IDE durchschlagen.
    end;
end;

class function TAtlasGuard.FailureKey(E: Exception): string;
begin
  // ExceptAddr gehört zur gerade behandelten Ausnahme; Report läuft in deren except-Block.
  if ExceptAddr <> nil then
    Result := Format('%s@%p', [E.ClassName, ExceptAddr])
  else
    Result := E.ClassName + ': ' + E.Message;
end;

class procedure TAtlasGuard.Report(AFeature: TAtlasFeature; E: Exception);
var
  Failure: TProc<TAtlasFeature>;
  Tripped: TAtlasGuardTripped;
  Fired, Repeated: Boolean;
  Skipped: Integer;
  Where: string;
begin
  Fired := False;
  Repeated := False;
  Skipped := 0;
  if FFuse <> nil then
    Fired := FFuse.Failed(AFeature, FailureKey(E), Repeated, Skipped);
  // Derselbe Fehler kurz nach dem gezählten (etwa für jede Zeile eines Zeichendurchlaufs): nicht noch einmal
  // protokollieren und nicht zählen; die nächste gezählte Zeile nennt die Zahl.
  if Repeated then
    Exit;
  Where := FeatureName(AFeature);
  if Skipped > 0 then
    Where := Format('%s (seit der letzten Meldung %d Wiederholungen übergangen)', [Where, Skipped]);
  Log(ErrorLine(Where, E));
  Failure := FOnFailure;
  if Assigned(Failure) then
    try
      Failure(AFeature);
    except
      // Die Meldung eines Fehlers darf selbst keinen auslösen.
    end;
  if not Fired then
    Exit;
  Warn(Format('Atlas: %s nach %d Fehlern in %d Minuten abgeschaltet (zuletzt: %s). ' +
    'Wieder einschalten unter Tools > Optionen > Drittanbieter > Atlas oder über Atlas > Abgeschaltete ' +
    'Funktionen einschalten.', [FeatureName(AFeature), TAtlasFuse.Limit, TAtlasFuse.WindowMinutes,
    SafeMessage(E.Message)]));
  Tripped := FOnTripped;
  if Assigned(Tripped) then
    try
      Tripped(AFeature, SafeMessage(E.Message));
    except
      // Auch der Eintrag in der Zentrale darf nicht in die IDE durchschlagen.
    end;
end;

class procedure TAtlasGuard.ReportProvider(const AName: string; E: Exception);
begin
  Log(ErrorLine('Quelle ' + AName, E));
  if (FFuse <> nil) and FFuse.ProviderFailed(AName) then
    Warn(Format('Atlas: Quelle „%s“ nach %d Fehlern in %d Minuten abgeschaltet (zuletzt: %s); die übrigen ' +
      'Quellen laufen weiter. Wieder einschalten unter Tools > Optionen > Drittanbieter > Atlas oder über ' +
      'Atlas > Abgeschaltete Funktionen einschalten.', [AName, TAtlasFuse.Limit, TAtlasFuse.WindowMinutes,
      SafeMessage(E.Message)]));
end;

class procedure TAtlasGuard.ReportProvider(const AName, AMessage: string);
var
  Error: Exception;
begin
  Error := Exception.Create(AMessage);
  try
    ReportProvider(AName, Error);
  finally
    Error.Free;
  end;
end;

class procedure TAtlasGuard.ReportProviderSlow(const AName, AText: string);
var
  Skipped: Integer;
  Suffix: string;
begin
  if (FFuse = nil) or not FFuse.ProviderSlow(AName, Skipped) then
    Exit;
  Suffix := '';
  if Skipped > 0 then
    Suffix := Format(' (dazu %d weitere seit der letzten Meldung)', [Skipped]);
  Log(Format('Quelle %s langsam: %s%s; zählt nicht als Fehler', [AName, SafeMessage(AText), Suffix]));
end;

class function TAtlasGuard.RunProvider(const AName: string; const AProc: TProc): Boolean;
begin
  if ProviderDisabled(AName) then
    Exit(False);
  try
    AProc();
    Result := True;
  except
    on E: EAbort do
      Result := False;
    on E: Exception do
    begin
      ReportProvider(AName, E);
      Result := False;
    end;
  end;
end;

class function TAtlasGuard.ProviderDisabled(const AName: string): Boolean;
begin
  Result := (FFuse <> nil) and FFuse.ProviderTripped(AName);
end;

class procedure TAtlasGuard.EnableProvider(const AName: string);
begin
  if FFuse <> nil then
    FFuse.ResetProvider(AName);
  Log(Format('Quelle %s wieder eingeschaltet', [AName]));
end;

class function TAtlasGuard.DisabledProviders: TArray<string>;
begin
  if FFuse = nil then
    Result := nil
  else
    Result := FFuse.TrippedProviders;
end;

class function TAtlasGuard.Run(AFeature: TAtlasFeature; const AProc: TProc): Boolean;
begin
  if Disabled(AFeature) then
    Exit(False);
  try
    AProc();
    Result := True;
  except
    on E: EAbort do
      Result := False;
    on E: Exception do
    begin
      Report(AFeature, E);
      Result := False;
    end;
  end;
end;

class function TAtlasGuard.Disabled(AFeature: TAtlasFeature): Boolean;
begin
  Result := (FFuse <> nil) and FFuse.Tripped(AFeature);
end;

class function TAtlasGuard.DisabledSet: TAtlasFeatures;
begin
  if FFuse = nil then
    Result := []
  else
    Result := FFuse.TrippedSet;
end;

class procedure TAtlasGuard.Enable(AFeature: TAtlasFeature);
begin
  if FFuse <> nil then
    FFuse.Reset(AFeature);
  Log(Format('%s wieder eingeschaltet', [FeatureName(AFeature)]));
end;

class procedure TAtlasGuard.EnableAll;
var
  Feature: TAtlasFeature;
  Name: string;
begin
  for Feature in DisabledSet do
    Enable(Feature);
  for Name in DisabledProviders do
    EnableProvider(Name);
end;

end.
