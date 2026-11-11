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
// - Zeitmessung (Diagnose-Fenster, Reiter „Hauptthread“): Ist Timing gesetzt,
//   meldet Run Beginn und Ende jedes Aufrufs, ReportProviderSlow jede langsame
//   Quelle. Ohne Diagnosemodus ist Timing nil, und Run prüft nur dieses Feld.
//   Timing ist eine abstrakte Klasse, damit diese Unit den Rekorder
//   (Atlas.Core.Diagnostics.PluginTimings) nicht kennen muss.
// - RunIde: Arbeit der IDE innerhalb eines Atlas-Aufrufs (Projekt öffnen).
//   Ihre Zeit zählt wie ein modaler Dialog nicht als Zeit von Atlas; vorher
//   stand das Projektladen als 13,9 s der Willkommensseite da (#1987).
//   Exceptions laufen unverändert zum äußeren Run.
// - Laufende Funktion für den Einfrier-Wächter (#1988): Run legt das Feature
//   im Hauptthread auf einen kleinen Stapel fester Größe (ohne Sperre und
//   ohne Speicher), RunIde einen Eintrag „IDE“. CurrentFeatureName liest ihn
//   aus dem Wächter-Thread; vorher nannte ein Hänger nur Aktionen mit
//   TAtlasActivity.Scope, und die meisten Einstiegspunkte (Zeichnen, Timer,
//   Notifier) liefen als „ohne Atlas“.
// - Disable schaltet ein Feature wie die Sicherung ab, auf Wunsch aus dem
//   Diagnose-Fenster; wieder an wie nach der Sicherung (Menü Atlas).
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
//   (die IDE des Benutzers und eine Bau-IDE teilen den Ordner;
//   ohne Sperre öffneten zwei Schreiber dieselbe Datei exklusiv). Scheitert
//   das Rotieren, wird trotzdem angehängt und der Grund einmal vermerkt.
//   Scheitert das Anhängen, zählt Add die verlorenen Zeilen, meldet den
//   ersten Fehler (und jeden neuen Grund) über OnError und schreibt beim
//   nächsten Gelingen eine Zeile über die Lücke.
// - Anonym (#1478): Jede Zeile läuft vor dem Schreiben durch
//   TAtlasLogRedactor (Atlas.Core.Diagnostics.LogRedaction). Namen, Pfade und
//   fremder Text sind an der Stelle gekennzeichnet, an der die Zeile entsteht
//   (Atlas.Text.LogMarks); die Meldung einer Exception kennzeichnet ErrorText
//   bzw. ErrorLine. Klarnamen nur mit diagnostics.log.names (Redactor.Names).
//   Warnungen an die Oberfläche gehen ohne Kennzeichen im Klartext.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Core.Diagnostics.LogRedaction;

type
{$SCOPEDENUMS ON}
  TAtlasFeature = (Completion, Signature, Hover, Pairs, Problems, Reloader, Palette, CheckOnSave, Watchdog, Server,
    Settings, Menu, Files, InlayHints, Results, EditorCommands, Forms, Build, Status, WelcomePage, ShortcutTips,
    Notes, Bookmarks, Notifications, Breadcrumbs, Outline, StickyScroll, Minimap, LineChanges, GutterColumn,
    RecursionMarkers, OverviewRuler, SelectionMatches, MultiCursor, LinkedEditing, CodeLens, NavHistory, Peek,
    SmartPaste, WrapSelection, Unwrap, Hide, Search, UnitSearch, Generate, ContinueLines, SlashCommands,
    GoToDefinition, EditorToolbar, QuickBookmarks, StatusBar, Architecture, UnitRelations, SymbolPath, Tasks, Debugger,
    ExitPoints, Reassigned, ExpressionType, MethodPlacement, IssueLinks,
    BlameIssues, Query, Hotspots, DesignerBar, Tracker, WelcomeUpdates, RegionFolds, SmartIndent);
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
    FRedactor: TAtlasLogRedactor;
    procedure Rotate;
    /// <summary>Rotiert eine volle Datei; Zeile über ein gescheitertes Rotieren oder ''.</summary>
    function RotateIfFull(const AStamp: string): string;
    /// <summary>Schreibt ALine samt ausstehender Meldungen; die Sperre hält der Aufrufer.</summary>
    procedure WriteLocked(const ALine: string);
    function AppendLine(const ALine: string): string;
    function Clean(const AText: string): string;
  public
    /// <summary>So lange wartet Add auf einen anderen Prozess, der gerade schreibt; danach schreibt es trotzdem.
    /// </summary>
    const cLockTimeoutMs = 2000;
    constructor Create(const AFolder: string; AMaxBytes: Int64; AMaxFiles: Integer); overload;
    /// <summary>Wie oben mit AMaxFiles = 5.</summary>
    constructor Create(const AFolder: string; AMaxBytes: Int64); overload;
    /// <summary>Wie oben mit AMaxBytes = 1 MB und AMaxFiles = 5.</summary>
    constructor Create(const AFolder: string); overload;
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
    /// <summary>Anonymisiert jede Zeile vor dem Schreiben (#1478); gehört dem Protokoll.</summary>
    property Redactor: TAtlasLogRedactor read FRedactor;
  end;

  TAtlasFuse = class
  public const
    cLimit = 3;
    cWindowMinutes = 5;
    /// <summary>Derselbe Fehler eines Features so kurz nach dem zuletzt gezählten zählt nicht erneut.</summary>
    cRepeatMs = 1000;
    /// <summary>Langsame Quelle: höchstens eine Protokollzeile je Quelle in diesem Abstand.</summary>
    cSlowLogSeconds = 60;
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
    constructor Create(const AClock: TFunc<TDateTime>); overload;
    /// <summary>Wie oben mit AClock = nil.</summary>
    constructor Create; overload;
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
    /// <summary>Feature abschalten wie nach dem Auslösen, ohne Fehler zu zählen.</summary>
    procedure Trip(AFeature: TAtlasFeature);
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
  TAtlasGuardStackFunc = reference to function(AE: Exception): string;
  /// <summary>Sicherung eines Features hat ausgelöst; AMessage ist die letzte Fehlermeldung (gekürzt).</summary>
  TAtlasGuardTripped = reference to procedure(AFeature: TAtlasFeature; const AMessage: string);

  /// <summary>Messpunkte von Run und ReportProviderSlow; der Rekorder des Diagnose-Fensters leitet hiervon ab.
  /// </summary>
  TAtlasGuardTiming = class
  public
    /// <summary>Beginn eines Aufrufs; das Ergebnis geht unverändert an Leave.</summary>
    function Enter: Integer; virtual; abstract;
    /// <summary>Ende des Aufrufs, der mit Enter begann (auch nach einem Fehler).</summary>
    procedure Leave(AFeature: TAtlasFeature; AToken: Integer); virtual; abstract;
    /// <summary>Arbeit der IDE beginnt im laufenden Aufruf (RunIde); ohne Wirkung, wenn nicht überschrieben.
    /// </summary>
    procedure IdeBegin; virtual;
    /// <summary>Die mit IdeBegin begonnene Arbeit der IDE ist zu Ende (auch nach einem Fehler).</summary>
    procedure IdeEnd; virtual;
    /// <summary>Die Quelle AName war zu langsam (Zeitlimit oder vorige Anfrage läuft noch).</summary>
    procedure ProviderSlow(const AName: string); virtual; abstract;
  end;

  TAtlasGuard = class
  private const
    cRunningMax = 32;
    // Eintrag von RunIde: Arbeit der IDE, keine Funktion von Atlas.
    cRunningIde = -1;
  private class var
    // Nur der Hauptthread schreibt; der Wächter liest ohne Sperre (ganze Zahlen, Index begrenzt).
    FRunning: array[0..cRunningMax - 1] of Integer;
    FRunningDepth: Integer;
    FFuse: TAtlasFuse;
    FLog: TAtlasRotatingLog;
    FOnWarning: TAtlasGuardMessage;
    FOnFailure: TProc<TAtlasFeature>;
    FStackOf: TAtlasGuardStackFunc;
    FOnTripped: TAtlasGuardTripped;
    FTiming: TAtlasGuardTiming;
    /// <summary>Im Hauptthread AEntry (Ord eines Features oder cRunningIde) auflegen; Ergebnis für
    /// LeaveRunning, -1 in anderen Threads.</summary>
    class function EnterRunning(AEntry: Integer): Integer; static;
    class procedure LeaveRunning(ADepth: Integer); static;
    class procedure Warn(const AText: string); static;
    class function ErrorLine(const AWhere: string; AE: Exception): string; static;
    /// <summary>Klasse und Stelle (ExceptAddr) des gerade behandelten Fehlers; ohne Stelle Klasse und Meldung.
    /// </summary>
    class function FailureKey(AE: Exception): string; static;
  public
    /// <summary>Höchstlänge einer Fehlermeldung im Protokoll; mehr könnte Quelltext enthalten.</summary>
    const cMaxMessageLength = 300;
    class constructor Create;
    class destructor Destroy;
    /// <summary>Führt AProc geschützt aus; False bei Fehler oder abgeschaltetem Feature.</summary>
    class function Run(AFeature: TAtlasFeature; const AProc: TProc): Boolean; static;
    /// <summary>AProc ist Arbeit der IDE (etwa IOTAActionServices.OpenProject): Ihre Zeit zählt im
    /// Diagnosemodus nicht als Zeit von Atlas. Fängt keine Exception; dafür sorgt das äußere Run.</summary>
    class procedure RunIde(const AProc: TProc); static;
    /// <summary>Name der innersten Funktion, die im Hauptthread über Run läuft; '' ohne oder während
    /// RunIde. Aus jedem Thread, ohne Sperre (der Einfrier-Wächter fragt, während der Hauptthread steht).
    /// </summary>
    class function CurrentFeatureName: string; static;
    /// <summary>Fehler aus einem eigenen except-Block melden (zählt wie in Run).</summary>
    class procedure Report(AFeature: TAtlasFeature; AE: Exception); static;
    /// <summary>Feature durch die Sicherung abgeschaltet?</summary>
    class function Disabled(AFeature: TAtlasFeature): Boolean; static;
    class procedure Enable(AFeature: TAtlasFeature); static;
    class procedure EnableAll; static;
    /// <summary>Feature bis zum Neustart (oder bis Enable) abschalten, ohne Fehler; aus dem Diagnose-Fenster.
    /// </summary>
    class procedure Disable(AFeature: TAtlasFeature); static;
    class function DisabledSet: TAtlasFeatures; static;
    /// <summary>Protokolliert eine Zeile ins rotierende Protokoll.</summary>
    class procedure Log(const AText: string); static;
    /// <summary>„Klasse: Meldung“ mit gekennzeichneter, einzeiliger Meldung (#1478) für eine Protokollzeile.
    /// </summary>
    class function ErrorText(AE: Exception): string; static;
    /// <summary>AText einzeilig und gekürzt (SafeMessage), als fremder Text gekennzeichnet (#1478).</summary>
    class function MessageText(const AText: string): string; static;
    /// <summary>Klarnamen im Protokoll (diagnostics.log.names); Vorgabe aus.</summary>
    class procedure SetLogNames(AValue: Boolean); static;
    class function FeatureName(AFeature: TAtlasFeature): string; static;
    /// <summary>Fehler der Quelle AName melden; nach 3 in 5 Minuten fällt nur sie aus.</summary>
    class procedure ReportProvider(const AName: string; AE: Exception); overload; static;
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
    /// <summary>Messpunkte des Diagnose-Fensters; nil (Vorgabe) misst nichts. Gehört dem Setzenden.</summary>
    class property Timing: TAtlasGuardTiming read FTiming write FTiming;
    class property RotatingLog: TAtlasRotatingLog read FLog;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  Atlas.Text.LogMarks,
  Atlas.Core.Product.Version,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TGuardText = (FeatureTripped, SourceTripped);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TGuardText] of string = (
    ('Atlas: %s nach %d Fehlern in %d Minuten abgeschaltet (zuletzt: %s). Wieder einschalten unter Tools > Optionen > Drittanbieter > Atlas oder über Atlas > Abgeschaltete Funktionen einschalten.',
     'Atlas: Quelle „%s“ nach %d Fehlern in %d Minuten abgeschaltet (zuletzt: %s); die übrigen Quellen laufen weiter. Wieder einschalten unter Tools > Optionen > Drittanbieter > Atlas oder über Atlas > Abgeschaltete Funktionen einschalten.'),
    ('Atlas: %s switched off after %d errors in %d minutes (last: %s). Switch it on again under Tools > Options > Third Party > Atlas or via Atlas > Re-enable switched-off features.',
     'Atlas: source "%s" switched off after %d errors in %d minutes (last: %s); the other sources keep running. Switch it on again under Tools > Options > Third Party > Atlas or via Atlas > Re-enable switched-off features.'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TGuardText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

{ TAtlasRotatingLog }

constructor TAtlasRotatingLog.Create(const AFolder: string; AMaxBytes: Int64);
begin
  Create(AFolder, AMaxBytes, 5);
end;

constructor TAtlasRotatingLog.Create(const AFolder: string);
begin
  Create(AFolder, 1024 * 1024, 5);
end;

constructor TAtlasRotatingLog.Create(const AFolder: string; AMaxBytes: Int64; AMaxFiles: Integer);
begin
  inherited Create;
  FFolder := AFolder;
  FMaxBytes := AMaxBytes;
  FMaxFiles := AMaxFiles;
  FLock := TCriticalSection.Create;
  FRedactor := TAtlasLogRedactor.Create(TAtlasLogRedactor.EnvironmentIdentity);
end;

destructor TAtlasRotatingLog.Destroy;
begin
  FRedactor.Free;
  FLock.Free;
  inherited;
end;

class function TAtlasRotatingLog.MutexName(const AFolder: string): string;
var
  mKey: string;
  mHash: Cardinal;
  mIndex: Integer;
begin
  // FNV-1a über den Ordner; ein Mutexname darf außer nach „Local\“ keinen Backslash enthalten.
  mKey := UpperCase(ExcludeTrailingPathDelimiter(AFolder));
  mHash := 2166136261;
  for mIndex := 1 to Length(mKey) do
  begin
    mHash := Cardinal((UInt64(mHash xor Ord(mKey[mIndex])) * 16777619) and $FFFFFFFF);
  end;
  Result := 'Local\Atlas.Log.' + IntToHex(mHash, 8);
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
  mIndex: Integer;
  mOlder, mNewer: string;
begin
  // atlas.log → atlas.1.log → … → atlas.(Max-1).log; die älteste fällt weg.
  for mIndex := FMaxFiles - 1 downto 1 do
  begin
    mOlder := TPath.Combine(FFolder, Format('atlas.%d.log', [mIndex]));
    if mIndex = 1 then
    begin
      mNewer := FileName;
    end
    else
    begin
      mNewer := TPath.Combine(FFolder, Format('atlas.%d.log', [mIndex - 1]));
    end;
    if TFile.Exists(mOlder) then
    begin
      TFile.Delete(mOlder);
    end;
    if TFile.Exists(mNewer) then
    begin
      TFile.Move(mNewer, mOlder);
    end;
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
function TAtlasRotatingLog.RotateIfFull(const AStamp: string): string;
begin
  Result := '';
  if not TFile.Exists(FileName) or (TFile.GetSize(FileName) < FMaxBytes) then
  begin
    Exit;
  end;
  try
    Rotate;
    FRotateError := '';
  except
    // Rotieren gescheitert (z. B. eine ältere Datei ist woanders gesperrt): trotzdem anhängen, die Datei wird
    // dann größer. Früher ging dabei auch die Zeile verloren, bei jedem Versuch wieder.
    on E: Exception do
    begin
      if E.Message <> FRotateError then
      begin
        FRotateError := E.Message;
        Result := AStamp + 'Protokoll: Rotieren gescheitert (' + E.ClassName + ': ' + Clean(E.Message) +
          '); schreibe weiter in atlas.log' + sLineBreak;
      end;
    end;
  end;
end;

procedure TAtlasRotatingLog.WriteLocked(const ALine: string);
var
  mStamp, mLines: string;
begin
  mStamp := FormatDateTime('yyyy-mm-dd hh":"nn":"ss.zzz', Now) + ' ';
  mLines := RotateIfFull(mStamp);
  if FFailed > 0 then
  begin
    mLines := mLines + mStamp + Format('Protokoll: %d Zeilen nicht geschrieben (zuletzt: %s)',
      [FFailed, Clean(FLastError)]) + sLineBreak;
  end;
  TFile.AppendAllText(FileName, mLines + ALine, TEncoding.UTF8);
end;

function TAtlasRotatingLog.AppendLine(const ALine: string): string;
var
  mLock: TMutex;
  mOwned: Boolean;
begin
  Result := '';
  try
    ForceDirectories(FFolder);
    // Je Zeile öffnen statt im Objekt halten: Der Ordner kann wechseln (Tests stellen ihn um), und eine gehaltene
    // Sperre bliebe samt Pfad stehen.
    mLock := TMutex.Create(nil, False, MutexName(FFolder));
    try
      // Abgebrochen heißt: Ein anderer Prozess endete beim Schreiben; die Sperre gehört dann uns.
      mOwned := mLock.WaitFor(cLockTimeoutMs) in [wrSignaled, wrAbandoned];
      try
        WriteLocked(ALine);
      finally
        if mOwned then
        begin
          mLock.Release;
        end;
      end;
    finally
      mLock.Free;
    end;
  except
    on E: Exception do
    begin
      Result := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

procedure TAtlasRotatingLog.Add(const AText: string);
var
  mFailure, mError: string;
  mNotify: Boolean;
begin
  FLock.Enter;
  try
    mFailure := AppendLine(FormatDateTime('yyyy-mm-dd hh":"nn":"ss.zzz', Now) + ' ' + FRedactor.Redact(AText) +
      sLineBreak);
    if mFailure = '' then
    begin
      mNotify := FFailed > 0;
      FFailed := 0;
      FLastError := '';
    end
    else
    begin
      Inc(FFailed);
      Inc(FLost);
      mNotify := mFailure <> FLastError;
      FLastError := mFailure;
    end;
    mError := FLastError;
  finally
    FLock.Leave;
  end;
  // Außerhalb der Sperren: Der Empfänger darf selbst protokollieren.
  if mNotify and Assigned(FOnError) then
  begin
    FOnError(mError);
  end;
end;

{ TAtlasFuse }

constructor TAtlasFuse.Create;
begin
  Create(nil);
end;

constructor TAtlasFuse.Create(const AClock: TFunc<TDateTime>);
begin
  inherited Create;
  FClock := AClock;
  if not Assigned(FClock) then
  begin
    FClock :=
      function: TDateTime
      begin
        Result := Now;
      end;
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
  mTime, mStamp: TDateTime;
  mRecent: TArray<TDateTime>;
begin
  mTime := FClock;
  mRecent := nil;
  for mStamp in AStamps do
  begin
    if MinutesBetween(mTime, mStamp) < cWindowMinutes then
    begin
      mRecent := mRecent + [mStamp];
    end;
  end;
  mRecent := mRecent + [mTime];
  AStamps := mRecent;
  Result := Length(mRecent) >= cLimit;
end;

function TAtlasFuse.Failed(AFeature: TAtlasFeature): Boolean;
var
  mRepeated: Boolean;
  mSkipped: Integer;
begin
  Result := Failed(AFeature, '', mRepeated, mSkipped);
end;

function TAtlasFuse.Failed(AFeature: TAtlasFeature; const AKey: string; out ARepeat: Boolean;
  out ASkipped: Integer): Boolean;
var
  mTime: TDateTime;
begin
  FLock.Enter;
  try
    Result := False;
    ARepeat := False;
    ASkipped := 0;
    mTime := FClock;
    // Fester Abstand ab dem zuletzt gezählten, nicht gleitend: Ein Fehler, der bei jedem Zeichnen kommt, zählt so
    // einmal je RepeatMs und löst die Sicherung weiterhin aus.
    if (AKey <> '') and (AKey = FLastKey[AFeature]) and
      (MilliSecondsBetween(mTime, FLastCounted[AFeature]) < cRepeatMs) then
    begin
      ARepeat := True;
      Inc(FRepeats[AFeature]);
      Exit;
    end;
    ASkipped := FRepeats[AFeature];
    FLastKey[AFeature] := AKey;
    FLastCounted[AFeature] := mTime;
    FRepeats[AFeature] := 0;
    if AFeature in FTripped then
    begin
      Exit;
    end;
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
  mKey: string;
  mStamps: TArray<TDateTime>;
begin
  mKey := AnsiLowerCase(AName);
  FLock.Enter;
  try
    Result := False;
    if FProvidersTripped.ContainsKey(mKey) then
    begin
      Exit;
    end;
    if not FProviderFailures.TryGetValue(mKey, mStamps) then
    begin
      mStamps := nil;
    end;
    if Count(mStamps) then
    begin
      FProvidersTripped.Add(mKey, AName);
      Result := True;
    end;
    FProviderFailures.AddOrSetValue(mKey, mStamps);
  finally
    FLock.Leave;
  end;
end;

function TAtlasFuse.ProviderSlow(const AName: string; out ASkipped: Integer): Boolean;
var
  mKey: string;
  mTime, mLogged: TDateTime;
begin
  mKey := AnsiLowerCase(AName);
  FLock.Enter;
  try
    mTime := FClock;
    if not FSlowSkipped.TryGetValue(mKey, ASkipped) then
    begin
      ASkipped := 0;
    end;
    Result := not FSlowLogged.TryGetValue(mKey, mLogged) or (SecondsBetween(mTime, mLogged) >= cSlowLogSeconds);
    if Result then
    begin
      FSlowLogged.AddOrSetValue(mKey, mTime);
      FSlowSkipped.AddOrSetValue(mKey, 0);
    end
    else
    begin
      FSlowSkipped.AddOrSetValue(mKey, ASkipped + 1);
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
  mKey: string;
begin
  mKey := AnsiLowerCase(AName);
  FLock.Enter;
  try
    FProvidersTripped.Remove(mKey);
    FProviderFailures.Remove(mKey);
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

procedure TAtlasFuse.Trip(AFeature: TAtlasFeature);
begin
  FLock.Enter;
  try
    Include(FTripped, AFeature);
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasFuse.ResetAll;
var
  mFeature: TAtlasFeature;
begin
  for mFeature := Low(TAtlasFeature) to High(TAtlasFeature) do
  begin
    Reset(mFeature);
  end;
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
  cNames: array[TAtlasLanguage, TAtlasFeature] of string = (
    ('Vervollständigung', 'Parameter-Hint', 'Tooltip', 'Klammerpaare',
      'Probleme', 'Neuladen', 'Befehlspalette', 'Prüfung beim Speichern', 'Wächter', 'Server', 'Einstellungen', 'Menü',
      'Dateien', 'Inlay-Hints', 'Ergebnisfenster', 'Editorbefehle', 'Formulare', 'Compile-Ereignisse', 'Statusfeld',
      'Willkommensseite', 'Tastenkürzel-Tipps', 'Notizen', 'Lesezeichen',
      'Benachrichtigungen', 'Brotkrumenleiste', 'Gliederung', 'Mitlaufender Kopf', 'Minimap', 'Änderungsmarken',
      'Atlas-Spalte', 'Rekursionssymbole', 'Übersichtsleiste', 'Gleichen Text hervorheben', 'Mehrere Einfügemarken',
      'Bezeichner mitziehen', 'Code Lens', 'Navigationsverlauf', 'Definition einblenden', 'Einfügen mit uses-Ergänzung',
      'Markierung umschließen', 'Umschließung entfernen', 'Ausblenden am Element', 'Atlas-Suche', 'Units suchen',
      'Erzeugen-Menü', 'Kommentar und Muster fortsetzen', 'Schnellbefehle', 'Gehe zu Definition', 'Editorleiste',
      'Schnelle Lesezeichen', 'Atlas-Statusleiste', 'Architekturübersicht', 'Unit-Beziehungen',
      'Weg zwischen Symbolen', 'Projektaufgaben', 'Debuggen',
      'Austrittspunkte', 'Neu zugewiesene Variablen', 'Typ des Ausdrucks', 'Methodenreihenfolge',
      'Issue-Kennungen', 'Issues in der Zeilenhistorie', 'Code-Abfragen', 'Hotspots', 'Designer-Leiste', 'Tracker',
      'Willkommensseite: Aktualisieren', 'Regionen falten', 'Einrückung beim Tippen'),
    ('Completion', 'Parameter hint', 'Tooltip', 'Bracket pairs',
      'Problems', 'Reload', 'Command palette', 'Check on save', 'Watchdog', 'Server', 'Settings', 'Menu',
      'Files', 'Inlay hints', 'Results window', 'Editor commands', 'Forms', 'Compile events', 'Status field',
      'Welcome page', 'Shortcut tips', 'Notes', 'Bookmarks',
      'Notifications', 'Breadcrumbs', 'Outline', 'Sticky scroll', 'Minimap', 'Change marks',
      'Atlas column', 'Recursion markers', 'Overview ruler', 'Highlight same text', 'Multiple carets',
      'Linked identifier editing', 'Code Lens', 'Navigation history', 'Peek definition', 'Paste with uses completion',
      'Surround selection', 'Remove surrounding', 'Hide at element', 'Atlas Search', 'Search units',
      'Generate menu', 'Continue comment and pattern', 'Quick commands', 'Go to definition', 'Editor toolbar',
      'Quick bookmarks', 'Atlas status bar', 'Architecture overview', 'Unit relations',
      'Path between symbols', 'Project tasks', 'Debugging',
      'Exit points', 'Reassigned variables', 'Type of expression', 'Method order',
      'Issue keys', 'Issues in line history', 'Code queries', 'Hotspots', 'Designer bar', 'Tracker',
      'Welcome page: updates', 'Region folding', 'Indent while typing'));
begin
  Result := cNames[TAtlasTextLanguage.Current, AFeature];
end;

class procedure TAtlasGuard.Log(const AText: string);
begin
  if FLog <> nil then
  begin
    FLog.Add(AText);
  end;
end;

class function TAtlasGuard.ErrorText(AE: Exception): string;
begin
  Result := AE.ClassName + ': ' + MessageText(AE.Message);
end;

class function TAtlasGuard.MessageText(const AText: string): string;
begin
  Result := TLogMarks.Text(SafeMessage(AText));
end;

class procedure TAtlasGuard.SetLogNames(AValue: Boolean);
begin
  if FLog <> nil then
  begin
    FLog.Redactor.Names := AValue;
  end;
end;

class function TAtlasGuard.SafeMessage(const AText: string): string;
var
  mBuilder: TStringBuilder;
  mCh: Char;
  mSpace: Boolean;
begin
  // Zeilenumbrüche und Steuerzeichen werden zu einem Leerzeichen; Folgen davon zu einem.
  mBuilder := TStringBuilder.Create;
  try
    mSpace := False;
    for mCh in AText do
    begin
      if CharInSet(mCh, [#0..#32]) then
      begin
        mSpace := True;
      end
      else
      begin
        if mSpace and (mBuilder.Length > 0) then
        begin
          mBuilder.Append(' ');
        end;
        mSpace := False;
        mBuilder.Append(mCh);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
  if Length(Result) > cMaxMessageLength then
  begin
    Result := Copy(Result, 1, cMaxMessageLength) + '…';
  end;
end;

class function TAtlasGuard.ErrorLine(const AWhere: string; AE: Exception): string;
var
  mTrace: string;
begin
  Result := Format('Atlas %s · Fehler in %s: %s', [TAtlasPluginVersion.cVersion, AWhere, ErrorText(AE)]);
  // E.StackTrace nur mit installiertem Anbieter (JCL, madExcept); sonst der Mitschnitt des Plugins.
  mTrace := Trim(AE.StackTrace);
  if (mTrace = '') and Assigned(FStackOf) then
    try
      mTrace := Trim(FStackOf(AE));
    except
      // Sicherheitsnetz: Ein Fehler beim Auflösen darf die Fehlerzeile selbst nicht verhindern.
      on Inner: Exception do
        mTrace := 'nicht verfügbar (' + Inner.ClassName + ')';
    end;
  if mTrace <> '' then
  begin
    Result := Result + sLineBreak + '  Stack: ' + StringReplace(mTrace, sLineBreak, sLineBreak + '  ', [rfReplaceAll]);
  end;
end;

class procedure TAtlasGuard.Warn(const AText: string);
begin
  Log(AText);
  if Assigned(FOnWarning) then
    try
      FOnWarning(TLogMarks.Plain(AText));
    except
      // Auch die Warnung darf nicht in die IDE durchschlagen.
    end;
end;

class function TAtlasGuard.FailureKey(AE: Exception): string;
begin
  // ExceptAddr gehört zur gerade behandelten Ausnahme; Report läuft in deren except-Block.
  if ExceptAddr <> nil then
  begin
    Result := Format('%s@%p', [AE.ClassName, ExceptAddr]);
  end
  else
  begin
    Result := AE.ClassName + ': ' + AE.Message;
  end;
end;

class procedure TAtlasGuard.Report(AFeature: TAtlasFeature; AE: Exception);
var
  mFailure: TProc<TAtlasFeature>;
  mTripped: TAtlasGuardTripped;
  mFired, mRepeated: Boolean;
  mSkipped: Integer;
  mWhere: string;
begin
  mFired := False;
  mRepeated := False;
  mSkipped := 0;
  if FFuse <> nil then
  begin
    mFired := FFuse.Failed(AFeature, FailureKey(AE), mRepeated, mSkipped);
  end;
  // Derselbe Fehler kurz nach dem gezählten (etwa für jede Zeile eines Zeichendurchlaufs): nicht noch einmal
  // protokollieren und nicht zählen; die nächste gezählte Zeile nennt die Zahl.
  if mRepeated then
  begin
    Exit;
  end;
  mWhere := FeatureName(AFeature);
  if mSkipped > 0 then
  begin
    mWhere := Format('%s (seit der letzten Meldung %d Wiederholungen übergangen)', [mWhere, mSkipped]);
  end;
  Log(ErrorLine(mWhere, AE));
  mFailure := FOnFailure;
  if Assigned(mFailure) then
    try
      mFailure(AFeature);
    except
      // Die Meldung eines Fehlers darf selbst keinen auslösen.
    end;
  if not mFired then
  begin
    Exit;
  end;
  Warn(Format(UiText(TGuardText.FeatureTripped), [FeatureName(AFeature), TAtlasFuse.cLimit, TAtlasFuse.cWindowMinutes,
    TLogMarks.Text(SafeMessage(AE.Message))]));
  mTripped := FOnTripped;
  if Assigned(mTripped) then
    try
      mTripped(AFeature, SafeMessage(AE.Message));
    except
      // Auch der Eintrag in der Zentrale darf nicht in die IDE durchschlagen.
    end;
end;

class procedure TAtlasGuard.ReportProvider(const AName: string; AE: Exception);
begin
  Log(ErrorLine('Quelle ' + AName, AE));
  if (FFuse <> nil) and FFuse.ProviderFailed(AName) then
  begin
    Warn(Format(UiText(TGuardText.SourceTripped), [AName, TAtlasFuse.cLimit, TAtlasFuse.cWindowMinutes,
      TLogMarks.Text(SafeMessage(AE.Message))]));
  end;
end;

class procedure TAtlasGuard.ReportProvider(const AName, AMessage: string);
var
  mError: Exception;
begin
  mError := Exception.Create(AMessage);
  try
    ReportProvider(AName, mError);
  finally
    mError.Free;
  end;
end;

class procedure TAtlasGuard.ReportProviderSlow(const AName, AText: string);
var
  mSkipped: Integer;
  mSuffix: string;
  mTiming: TAtlasGuardTiming;
begin
  mTiming := FTiming;
  if mTiming <> nil then
  begin
    mTiming.ProviderSlow(AName);
  end;
  if (FFuse = nil) or not FFuse.ProviderSlow(AName, mSkipped) then
  begin
    Exit;
  end;
  mSuffix := '';
  if mSkipped > 0 then
  begin
    mSuffix := Format(' (dazu %d weitere seit der letzten Meldung)', [mSkipped]);
  end;
  Log(Format('Quelle %s langsam: %s%s; zählt nicht als Fehler', [AName, MessageText(AText), mSuffix]));
end;

class function TAtlasGuard.RunProvider(const AName: string; const AProc: TProc): Boolean;
begin
  if ProviderDisabled(AName) then
  begin
    Exit(False);
  end;
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
  begin
    FFuse.ResetProvider(AName);
  end;
  Log(Format('Quelle %s wieder eingeschaltet', [AName]));
end;

class function TAtlasGuard.DisabledProviders: TArray<string>;
begin
  if FFuse = nil then
  begin
    Result := nil;
  end
  else
  begin
    Result := FFuse.TrippedProviders;
  end;
end;

function RunGuarded(AFeature: TAtlasFeature; const AProc: TProc): Boolean;
begin
  try
    AProc();
    Result := True;
  except
    on E: EAbort do
      Result := False;
    on E: Exception do
    begin
      TAtlasGuard.Report(AFeature, E);
      Result := False;
    end;
  end;
end;

class function TAtlasGuard.EnterRunning(AEntry: Integer): Integer;
begin
  Result := -1;
  if TThread.CurrentThread.ThreadID <> MainThreadID then
  begin
    Exit;
  end;
  Result := FRunningDepth;
  // Erst der Eintrag, dann die Tiefe: Der Wächter liest nie einen alten Eintrag unter der neuen Tiefe.
  if Result < cRunningMax then
  begin
    FRunning[Result] := AEntry;
  end;
  FRunningDepth := Result + 1;
end;

class procedure TAtlasGuard.LeaveRunning(ADepth: Integer);
begin
  if ADepth >= 0 then
  begin
    FRunningDepth := ADepth;
  end;
end;

class function TAtlasGuard.CurrentFeatureName: string;
var
  mDepth, mEntry: Integer;
begin
  Result := '';
  mDepth := FRunningDepth;
  if mDepth <= 0 then
  begin
    Exit;
  end;
  if mDepth > cRunningMax then
  begin
    mDepth := cRunningMax;
  end;
  mEntry := FRunning[mDepth - 1];
  if (mEntry >= Ord(Low(TAtlasFeature))) and (mEntry <= Ord(High(TAtlasFeature))) then
  begin
    Result := FeatureName(TAtlasFeature(mEntry));
  end;
end;

class function TAtlasGuard.Run(AFeature: TAtlasFeature; const AProc: TProc): Boolean;
var
  mTiming: TAtlasGuardTiming;
  mToken, mDepth: Integer;
begin
  if Disabled(AFeature) then
  begin
    Exit(False);
  end;
  mDepth := EnterRunning(Ord(AFeature));
  try
    // Einmal lesen: Schaltet der Diagnosemodus mitten im Aufruf um, endet der Aufruf beim selben Rekorder.
    mTiming := FTiming;
    if mTiming = nil then
    begin
      Exit(RunGuarded(AFeature, AProc));
    end;
    mToken := mTiming.Enter;
    try
      Result := RunGuarded(AFeature, AProc);
    finally
      mTiming.Leave(AFeature, mToken);
    end;
  finally
    LeaveRunning(mDepth);
  end;
end;

class procedure TAtlasGuard.RunIde(const AProc: TProc);
var
  mTiming: TAtlasGuardTiming;
  mDepth: Integer;
begin
  mDepth := EnterRunning(cRunningIde);
  try
    mTiming := FTiming;
    if mTiming = nil then
    begin
      AProc();
      Exit;
    end;
    mTiming.IdeBegin;
    try
      AProc();
    finally
      mTiming.IdeEnd;
    end;
  finally
    LeaveRunning(mDepth);
  end;
end;

{ TAtlasGuardTiming }

procedure TAtlasGuardTiming.IdeBegin;
begin
  // Ohne Rekorder nichts zu tun.
end;

procedure TAtlasGuardTiming.IdeEnd;
begin
  // Ohne Rekorder nichts zu tun.
end;

class function TAtlasGuard.Disabled(AFeature: TAtlasFeature): Boolean;
begin
  Result := (FFuse <> nil) and FFuse.Tripped(AFeature);
end;

class function TAtlasGuard.DisabledSet: TAtlasFeatures;
begin
  if FFuse = nil then
  begin
    Result := [];
  end
  else
  begin
    Result := FFuse.TrippedSet;
  end;
end;

class procedure TAtlasGuard.Disable(AFeature: TAtlasFeature);
begin
  if FFuse <> nil then
  begin
    FFuse.Trip(AFeature);
  end;
  Log(Format('%s im Diagnose-Fenster bis zum Neustart ausgeschaltet', [FeatureName(AFeature)]));
end;

class procedure TAtlasGuard.Enable(AFeature: TAtlasFeature);
begin
  if FFuse <> nil then
  begin
    FFuse.Reset(AFeature);
  end;
  Log(Format('%s wieder eingeschaltet', [FeatureName(AFeature)]));
end;

class procedure TAtlasGuard.EnableAll;
var
  mFeature: TAtlasFeature;
  mName: string;
begin
  for mFeature in DisabledSet do
  begin
    Enable(mFeature);
  end;
  for mName in DisabledProviders do
  begin
    EnableProvider(mName);
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Diagnostics.Guard', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
