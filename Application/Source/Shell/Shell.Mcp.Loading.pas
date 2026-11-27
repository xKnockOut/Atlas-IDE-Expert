unit Shell.Mcp.Loading;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Laden der Projektgruppe im Hintergrund (#3099). Clients wie Claude Code
// warten höchstens 30 s auf die Antwort auf initialize; Konfiguration und Projekte einer großen Gruppe zu laden
// dauert länger. Deshalb beantwortet der Server initialize und die Listen sofort und lädt die Gruppe in einem
// eigenen Thread, sobald die Verbindung steht.
//
// - Ensure wartet vor jedem Werkzeugaufruf, Prompt und jeder Ressource höchstens die Frist auf das Laden und meldet
//   danach „Projekt wird noch geladen“ als Fehler des Aufrufs (EMcpToolError), statt den Client hängen zu lassen.
// - Den Namen des Clients aus initialize bekommt die Gruppe erst nach dem Laden: Load legt die übrigen
//   Arbeitsbereiche an, SetClient geht über sie; beides gleichzeitig wäre ein Wettlauf um dieselbe Liste.
// - Ein Fehler beim Laden steht im Log; die Werkzeuge laufen danach mit dem, was geladen ist.
// - Finish wartet auf den Thread, bevor der Aufrufer die Gruppe anhält und freigibt.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Common.Logging.Contract;

type
  /// <summary>Lädt die Projektgruppe einmal im Hintergrund und lässt Aufrufe bis zum Ende warten.</summary>
  TMcpLoading = class
  public const
    /// <summary>So lange wartet ein Werkzeugaufruf auf das Laden, bevor er „wird noch geladen“ meldet; mit Abstand
    /// unter dem Zeitlimit üblicher Clients für einen Aufruf.</summary>
    cToolWaitMs = 20000;
  private
    FLoad: TProc;
    FSetClient: TProc<string>;
    FLogger: ILogger;
    FLoaded: TEvent;
    FLock: TObject;
    FThread: TThread;
    FDone: Boolean;
    FPendingClient: string;
    FMilliseconds: Int64;
    procedure Run;
    procedure Completed;
  public
    /// <summary>ALoad lädt die Gruppe (läuft im eigenen Thread); ASetClient gibt ihr den Namen des Clients, erst
    /// nach dem Laden.</summary>
    constructor Create(const ALoad: TProc; const ASetClient: TProc<string>; const ALogger: ILogger);
    destructor Destroy; override;
    /// <summary>Startet das Laden; ein zweiter Aufruf tut nichts, auch nach Finish.</summary>
    procedure Start;
    /// <summary>Ist das Laden fertig (auch mit Fehler)? Wartet höchstens ATimeoutMs.</summary>
    function WaitLoaded(ATimeoutMs: Cardinal): Boolean;
    /// <summary>Wie WaitLoaded mit cToolWaitMs; sonst EMcpToolError mit der Bitte, es gleich erneut zu
    /// versuchen.</summary>
    procedure Ensure; overload;
    procedure Ensure(ATimeoutMs: Cardinal); overload;
    /// <summary>Name des Clients aus initialize: sofort an die Gruppe, wenn sie geladen ist, sonst nach dem
    /// Laden.</summary>
    procedure SetClient(const AClient: string);
    /// <summary>Wartet, bis der Thread fertig ist, und gibt ihn frei (vor Stop und Free der Gruppe).</summary>
    procedure Finish;
    /// <summary>Dauer des Ladens in Millisekunden; 0, solange es läuft.</summary>
    property Milliseconds: Int64 read FMilliseconds;
  end;

implementation

uses
  System.Diagnostics,
  Mcp.Server,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  TMcpLoadingText = (StillLoading, Loaded, LoadFailed);

const
  cTexts: array[TMcpLoadingText] of TAtlasText = (
    (De: 'Atlas lädt das Projekt noch (Konfiguration und Projekte der Gruppe). Den Aufruf in einigen Sekunden ' +
      'wiederholen.';
     En: 'Atlas is still loading the project (configuration and the projects of the group). Repeat the call in a ' +
      'few seconds.'),
    (De: 'Projektgruppe geladen nach %d ms'; En: 'Project group loaded after %d ms'),
    (De: 'Laden der Projektgruppe fehlgeschlagen: %s: %s'; En: 'Loading the project group failed: %s: %s'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Thread, der TMcpLoading.Run einmal ausführt.</summary>
  TMcpLoadThread = class(TThread)
  private
    FRun: TProc;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARun: TProc);
  end;

{ TMcpLoadThread }

constructor TMcpLoadThread.Create(const ARun: TProc);
begin
  FRun := ARun;
  inherited Create(False);
end;

procedure TMcpLoadThread.Execute;
begin
  FRun();
end;

{ TMcpLoading }

constructor TMcpLoading.Create(const ALoad: TProc; const ASetClient: TProc<string>; const ALogger: ILogger);
begin
  inherited Create;
  FLoad := ALoad;
  FSetClient := ASetClient;
  FLogger := ALogger;
  FLoaded := TEvent.Create(nil, True, False, '');
  FLock := TObject.Create;
end;

destructor TMcpLoading.Destroy;
begin
  Finish;
  FLock.Free;
  FLoaded.Free;
  inherited;
end;

procedure TMcpLoading.Start;
var
  mSelf: TMcpLoading;
begin
  // Einmal: auch nach Finish (Thread schon freigegeben) nicht noch einmal laden.
  if (FThread <> nil) or (FLoaded.WaitFor(0) = wrSignaled) then
  begin
    Exit;
  end;
  mSelf := Self;
  FThread := TMcpLoadThread.Create(
    procedure
    begin
      mSelf.Run;
    end);
end;

procedure TMcpLoading.Run;
var
  mWatch: TStopwatch;
begin
  mWatch := TStopwatch.StartNew;
  try
    FLoad();
    FMilliseconds := mWatch.ElapsedMilliseconds;
    FLogger.Info(cTexts[TMcpLoadingText.Loaded].Fmt([FMilliseconds]));
  except
    // Grenze des Threads: Eine Ausnahme dort beendete ihn still, und jeder Aufruf wartete auf ein Ende, das nie
    // kommt. Die Werkzeuge laufen mit dem, was geladen ist.
    on E: Exception do
    begin
      FMilliseconds := mWatch.ElapsedMilliseconds;
      FLogger.Error(cTexts[TMcpLoadingText.LoadFailed].Fmt([E.ClassName, E.Message]));
    end;
  end;
  Completed;
end;

/// <summary>Markiert das Laden als fertig und gibt einen vorgemerkten Client an die Gruppe.</summary>
procedure TMcpLoading.Completed;
var
  mClient: string;
begin
  System.TMonitor.Enter(FLock);
  try
    FDone := True;
    mClient := FPendingClient;
    FPendingClient := '';
  finally
    System.TMonitor.Exit(FLock);
  end;
  if mClient <> '' then
  begin
    FSetClient(mClient);
  end;
  FLoaded.SetEvent;
end;

function TMcpLoading.WaitLoaded(ATimeoutMs: Cardinal): Boolean;
begin
  Result := FLoaded.WaitFor(ATimeoutMs) = wrSignaled;
end;

procedure TMcpLoading.Ensure;
begin
  Ensure(cToolWaitMs);
end;

procedure TMcpLoading.Ensure(ATimeoutMs: Cardinal);
begin
  if not WaitLoaded(ATimeoutMs) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpLoadingText.StillLoading].Text);
  end;
end;

procedure TMcpLoading.SetClient(const AClient: string);
var
  mNow: Boolean;
begin
  System.TMonitor.Enter(FLock);
  try
    mNow := FDone;
    if not mNow then
    begin
      FPendingClient := AClient;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
  if mNow then
  begin
    FSetClient(AClient);
  end;
end;

procedure TMcpLoading.Finish;
begin
  // Warten und gleich freigeben: Danach hält nichts mehr die Gruppe, und Destroy hat nichts mehr zu tun.
  if FThread <> nil then
  begin
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Mcp.Loading', cTexts);

end.
