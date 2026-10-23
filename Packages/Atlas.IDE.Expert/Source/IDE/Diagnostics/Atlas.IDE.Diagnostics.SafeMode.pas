unit Atlas.IDE.Diagnostics.SafeMode;

// Abgesicherter Start (#722) in der IDE:
// - Start: Marken früherer Sitzungen in %LOCALAPPDATA%\Atlas\Session prüfen
//   (Prozess beendet oder Nummer neu vergeben = Absturz), Taste beim Laden
//   (GetAsyncKeyState), Kommandozeile -AtlasSafeMode bzw. ATLAS_SAFE_MODE
//   auswerten, entscheiden (TAtlasSafeMode.Decide) und die eigene Marke
//   schreiben. Abgesichert bzw. minimal schaltet alle Schnellschalter (#604)
//   für diese Sitzung aus; die Composition meldet danach nur an, was die
//   Stufe erlaubt.
// - Hinweis: nicht modal (TAtlasSafeModeNotice) mit Rückfrage bzw. Knöpfen,
//   dazu eine gelbe Zeile „Abgesichert gestartet“ im Atlas-Statusfeld (#591),
//   die den Hinweis wieder öffnet.
// - Loaded: Ladezeit in die Marke (für „Details“ nach einem Absturz). Ein
//   langsamer Start ist kein Absturz (Bericht N4); was Atlas daran hatte,
//   meldet die Composition mit den Startanteilen.
// - RecordFailure: Fehler je Feature (#493) in die Marke.
// - Stop (sauberes Entladen): Marke löschen, Absturzzähler zurücksetzen.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.SafeMode,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.UI.Diagnostics.SafeModeNotice;

type
  TAtlasIdeSafeMode = class(TComponent)
  public const
    StatusId = 'atlas.safemode';
    StatusOrder = 2;
    /// <summary>Höchstens so viele Zeilen des Protokolls in „Details“.</summary>
    MaxLogLines = 200;
  private
    FLock: TCriticalSection;
    FFolder: string;
    FMarker: TAtlasSessionMarker;
    FStarted: Boolean;
    FDecision: TAtlasSafeDecision;
    FLevel: TAtlasSafeLevel;
    FAnswered: Boolean;
    FCrashed: TAtlasSessionMarker;
    FHasCrashed: Boolean;
    FStartedLocal: TDateTime;
    FChangedKeys: TArray<string>;
    FRegistry: IAtlasStatusRegistry;
    FLine: TAtlasStatusLine;
    FLineRef: IAtlasStatusItem;
    FNotice: TAtlasSafeModeNotice;
    FOnShowToggles: TProc;
    FOnExportLog: TProc;
    FOnBugReport: TProc;
    class function Options: TAtlasSafeOptions; static;
    class function Alive(AProcessId: Cardinal; AStartedAt: TDateTime): Boolean; static;
    class function KeyDown(AKey: TAtlasStartupKey): TAtlasStartupKey; static;
    class function Forced: Boolean; static;
    class function EnabledFeatures: TArray<string>; static;
    class function NowUtc: TDateTime; static;
    class procedure Warn(const AText: string); static;
    procedure WriteMarker;
    procedure ShowLine;
    procedure HideLine;
    function NoticeText(AKind: TAtlasSafeNoticeKind): string;
    function Suggestion: string;
    function RestoreCaption: string;
    function DetailLines: TArray<string>;
    procedure Restore;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>%LOCALAPPDATA%\Atlas\Session.</summary>
    class function DefaultFolder: string; static;
    /// <summary>Beim Laden des Packages, vor allen anderen Teilen: entscheiden, Marke schreiben, ggf.
    /// Sitzungswerte setzen und den Hinweis vormerken.</summary>
    procedure Start(const AFolder: string; const ARegistry: IAtlasStatusRegistry);
    /// <summary>Nachrichtenschleife frei nach ALoadMs.</summary>
    procedure Loaded(ALoadMs: Int64); reintroduce;
    /// <summary>Sauberes Entladen.</summary>
    procedure Stop;
    /// <summary>Fehler eines Features (#493); aus jedem Thread.</summary>
    procedure RecordFailure(AFeature: TAtlasFeature);
    /// <summary>Aktive Funktionen nach einer Änderung der Einstellungen in die Marke.</summary>
    procedure UpdateFeatures;
    /// <summary>„Normal starten“ bzw. „Normal weiterarbeiten“: Sitzungswerte zurück, alle Funktionen an.</summary>
    procedure Leave;
    /// <summary>Hinweis (wieder) zeigen; im normalen Betrieb nichts.</summary>
    procedure ShowNotice;
    property Level: TAtlasSafeLevel read FLevel;
    property Decision: TAtlasSafeDecision read FDecision;
    property Notice: TAtlasSafeModeNotice read FNotice;
    property OnShowToggles: TProc read FOnShowToggles write FOnShowToggles;
    property OnExportLog: TProc read FOnExportLog write FOnExportLog;
    /// <summary>Fehlerbericht (#108); ohne Zuweisung kein Knopf.</summary>
    property OnBugReport: TProc read FOnBugReport write FOnBugReport;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Winapi.Windows,
  System.Types,
  System.IOUtils,
  System.DateUtils,
  System.TypInfo,
  Vcl.Forms,
  Atlas.Core.Product.Version,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.QuickToggles,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings;

const
  // Winapi.Windows kennt die Konstante nicht (ab Windows Vista).
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;

{ TAtlasIdeSafeMode }

constructor TAtlasIdeSafeMode.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLock := TCriticalSection.Create;
  FLevel := TAtlasSafeLevel.Normal;
end;

destructor TAtlasIdeSafeMode.Destroy;
begin
  HideLine;
  FLock.Free;
  inherited Destroy;
end;

procedure TAtlasIdeSafeMode.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FNotice) then
    FNotice := nil;
end;

class function TAtlasIdeSafeMode.DefaultFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), 'Session');
end;

class function TAtlasIdeSafeMode.Options: TAtlasSafeOptions;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Stored;
  Result := TAtlasSafeOptions.Create(Settings.SafeAskAfterCrash, Settings.SafeAutoAfterRepeatedCrash,
    TAtlasSafeMode.KeyOf(Settings.SafeStartupKey));
end;

class function TAtlasIdeSafeMode.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasIdeSafeMode.Alive(AProcessId: Cardinal; AStartedAt: TDateTime): Boolean;
var
  Process: THandle;
  Code: DWORD;
  Creation, ExitTime, KernelTime, UserTime: TFileTime;
  Started: TSystemTime;
begin
  Process := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, AProcessId);
  if Process = 0 then
    // Kein Zugriff heißt: Den Prozess gibt es (andere Anmeldung); sonst ist er beendet.
    Exit(GetLastError = ERROR_ACCESS_DENIED);
  try
    Result := GetExitCodeProcess(Process, Code) and (Code = STILL_ACTIVE);
    // Später gestartet als die Marke: Die Nummer gehört einem neuen Prozess.
    if Result and GetProcessTimes(Process, Creation, ExitTime, KernelTime, UserTime) and
      FileTimeToSystemTime(Creation, Started) then
      Result := SystemTimeToDateTime(Started) <= AStartedAt;
  finally
    CloseHandle(Process);
  end;
end;

class function TAtlasIdeSafeMode.KeyDown(AKey: TAtlasStartupKey): TAtlasStartupKey;
begin
  Result := TAtlasStartupKey.None;
  case AKey of
    TAtlasStartupKey.Shift:
      if GetAsyncKeyState(VK_SHIFT) < 0 then
        Result := AKey;
    TAtlasStartupKey.Ctrl:
      if GetAsyncKeyState(VK_CONTROL) < 0 then
        Result := AKey;
  end;
end;

class function TAtlasIdeSafeMode.Forced: Boolean;
var
  Args: TArray<string>;
  Index: Integer;
begin
  Args := nil;
  for Index := 1 to ParamCount do
    Args := Args + [ParamStr(Index)];
  Result := TAtlasSafeMode.IsForced(GetEnvironmentVariable(TAtlasSafeMode.EnvironmentName), Args);
end;

class function TAtlasIdeSafeMode.EnabledFeatures: TArray<string>;
var
  Toggle: TAtlasQuickToggle;
  Settings: TAtlasPluginSettings;
  Value: Boolean;
begin
  Result := nil;
  Settings := TAtlasIdeSettings.Current;
  for Toggle in TAtlasIdeSettings.QuickToggles do
    if TAtlasQuickToggles.GetFlag(Settings, Toggle.Key, Value) and Value then
      Result := Result + [Toggle.Key];
end;

class procedure TAtlasIdeSafeMode.Warn(const AText: string);
var
  Warning: TAtlasGuardMessage;
begin
  TAtlasGuard.Log(AText);
  Warning := TAtlasGuard.OnWarning;
  if Assigned(Warning) then
    Warning(AText);
end;

procedure TAtlasIdeSafeMode.WriteMarker;
begin
  if not FStarted then
    Exit;
  try
    TAtlasSessionFiles.WriteMarker(FFolder, FMarker);
  except
    // Ohne Marke erkennt der nächste Start den Absturz nicht; die IDE stört das nicht.
    on Exception do
      ;
  end;
end;

procedure TAtlasIdeSafeMode.Start(const AFolder: string; const ARegistry: IAtlasStatusRegistry);
var
  State: TAtlasSafeState;
  Crashed: TArray<TAtlasSessionMarker>;
  SafeOptions: TAtlasSafeOptions;
  StartedAt: TDateTime;
  Show: TThreadProcedure;
begin
  FFolder := AFolder;
  FRegistry := ARegistry;
  StartedAt := NowUtc;
  FStartedLocal := Now;
  SafeOptions := Options;
  try
    State := TAtlasSessionFiles.ReadState(FFolder);
    Crashed := TAtlasSessionFiles.TakeCrashed(FFolder, GetCurrentProcessId,
      function(AProcessId: Cardinal; AStartedAt: TDateTime): Boolean
      begin
        Result := Alive(AProcessId, AStartedAt);
      end);
  except
    on Exception do
    begin
      State := Default(TAtlasSafeState);
      Crashed := nil;
    end;
  end;
  // Für den Vorschlag: Was die letzte gespeicherte Änderung umgestellt hat.
  try
    FChangedKeys := TAtlasIdeSettings.History.LastChangedKeys(TAtlasIdeSettings.Stored);
  except
    on Exception do
      FChangedKeys := nil;
  end;
  FDecision := TAtlasSafeMode.Decide(State, Crashed, StartedAt, SafeOptions, KeyDown(SafeOptions.StartupKey),
    Forced);
  FLevel := FDecision.Level;
  FAnswered := not FDecision.Ask;
  // Nur die Marke dieses Absturzes, nicht die eines früheren aus dem Zustand.
  FHasCrashed := (Length(Crashed) > 0) and (State.CrashedMarker <> '') and
    TAtlasSessionMarker.FromJson(State.CrashedMarker, FCrashed);
  try
    TAtlasSessionFiles.WriteState(FFolder, State);
  except
    on Exception do
      ;
  end;
  if FLevel <> TAtlasSafeLevel.Normal then
    TAtlasIdeSettings.SetSession(TAtlasSafeMode.SafeSession(TAtlasIdeSettings.QuickToggles));
  FMarker := TAtlasSessionMarker.Create(GetCurrentProcessId, TAtlasPluginVersion.Version, StartedAt);
  FMarker.Level := FLevel;
  FMarker.Features := EnabledFeatures;
  FStarted := True;
  WriteMarker;
  TAtlasGuard.Log(Format('Atlas gestartet (%s), Stufe %s, Grund %s', [TAtlasPluginVersion.Version,
    GetEnumName(TypeInfo(TAtlasSafeLevel), Ord(FLevel)),
    GetEnumName(TypeInfo(TAtlasSafeReason), Ord(FDecision.Reason))]));
  if FLevel = TAtlasSafeLevel.Normal then
    Exit;
  ShowLine;
  // Erst wenn die IDE steht: Das Hauptfenster gibt es beim Laden der Packages evtl. noch nicht.
  Show :=
    procedure
    begin
      ShowNotice;
    end;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Settings, Show);
end;

procedure TAtlasIdeSafeMode.Loaded(ALoadMs: Int64);
begin
  if not FStarted then
    Exit;
  FLock.Enter;
  try
    FMarker.Loaded := True;
    FMarker.LoadMs := ALoadMs;
    WriteMarker;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasIdeSafeMode.Stop;
var
  State: TAtlasSafeState;
begin
  if not FStarted then
    Exit;
  FStarted := False;
  if FNotice <> nil then
    FreeAndNil(FNotice);
  HideLine;
  try
    TAtlasSessionFiles.DeleteMarker(FFolder, FMarker.ProcessId);
    State := TAtlasSessionFiles.ReadState(FFolder);
    TAtlasSafeMode.CleanExit(State);
    TAtlasSessionFiles.WriteState(FFolder, State);
  except
    on Exception do
      ;
  end;
end;

procedure TAtlasIdeSafeMode.RecordFailure(AFeature: TAtlasFeature);
begin
  FLock.Enter;
  try
    FMarker.AddFailure(GetEnumName(TypeInfo(TAtlasFeature), Ord(AFeature)));
    WriteMarker;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasIdeSafeMode.UpdateFeatures;
var
  Features: TArray<string>;
begin
  Features := EnabledFeatures;
  FLock.Enter;
  try
    FMarker.Features := Features;
    FMarker.Level := FLevel;
    WriteMarker;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasIdeSafeMode.ShowLine;
var
  Action: TProc;
begin
  if (FRegistry = nil) or (FLineRef <> nil) then
    Exit;
  Action :=
    procedure
    begin
      ShowNotice;
    end;
  FLine := TAtlasStatusLine.Create(FRegistry, StatusId, StatusOrder, Action);
  FLineRef := FLine;
  FLine.Update(TAtlasStrings.Text(TAtlasTextId.SafeStatusLine), TAtlasStatusState.Yellow,
    TAtlasStrings.Text(TAtlasTextId.SafeStatusSummary));
  FRegistry.Add(FLineRef);
end;

procedure TAtlasIdeSafeMode.HideLine;
begin
  if FLineRef = nil then
    Exit;
  FLine.Detach;
  if FRegistry <> nil then
    FRegistry.Remove(StatusId);
  FLine := nil;
  FLineRef := nil;
end;

procedure TAtlasIdeSafeMode.Leave;
begin
  if FLevel = TAtlasSafeLevel.Normal then
    Exit;
  FLevel := TAtlasSafeLevel.Normal;
  FAnswered := True;
  if FNotice <> nil then
    FNotice.Close;
  HideLine;
  // Die Composition meldet über OnChanged der Einstellungen alles Weitere an.
  TAtlasIdeSettings.SetSession(Default(TAtlasToggleSession));
  UpdateFeatures;
  Warn(TAtlasStrings.Text(TAtlasTextId.SafeLeft));
end;

function TAtlasIdeSafeMode.NoticeText(AKind: TAtlasSafeNoticeKind): string;
begin
  if AKind = TAtlasSafeNoticeKind.Ask then
    Exit(TAtlasStrings.Text(TAtlasTextId.SafeAskText));
  case FDecision.Reason of
    TAtlasSafeReason.StartupKey:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SafeMinimalText, [TAtlasStrings.Text(TAtlasTextId.SafeReasonKey)]);
    TAtlasSafeReason.Forced:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SafeMinimalText,
        [TAtlasStrings.Text(TAtlasTextId.SafeReasonForced)]);
    TAtlasSafeReason.RepeatedCrash:
      Result := TAtlasStrings.Text(TAtlasTextId.SafeRepeatedText) + sLineBreak + sLineBreak +
        TAtlasStrings.Text(TAtlasTextId.SafeActiveText);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.SafeActiveText);
  end;
end;

function TAtlasIdeSafeMode.Suggestion: string;
var
  Toggles: TArray<TAtlasQuickToggle>;
  Toggle: TAtlasQuickToggle;
  Key: string;
  Names: TArray<string>;
begin
  Result := '';
  if not FDecision.Crashed then
    Exit;
  Toggles := TAtlasIdeSettings.QuickToggles;
  Names := nil;
  for Key in TAtlasSafeMode.Suggest(Toggles, FChangedKeys, FCrashed) do
    if TAtlasQuickToggles.Find(Toggles, Key, Toggle) then
      Names := Names + [Toggle.Caption];
  if Length(Names) > 0 then
    Result := TAtlasStrings.Fmt(TAtlasTextId.SafeSuggest, [string.Join(', ', Names)]);
end;

function TAtlasIdeSafeMode.RestoreCaption: string;
begin
  Result := '';
  try
    if TAtlasIdeSettings.History.Count > 0 then
      Result := TAtlasStrings.Fmt(TAtlasTextId.SafeRestore,
        [DateTimeToStr(TTimeZone.Local.ToLocalTime(TAtlasIdeSettings.History[0].ChangedAt), FormatSettings)]);
  except
    on Exception do
      Result := '';
  end;
end;

procedure TAtlasIdeSafeMode.Restore;
var
  At: string;
begin
  if TAtlasIdeSettings.History.Count = 0 then
    Exit;
  At := DateTimeToStr(TTimeZone.Local.ToLocalTime(TAtlasIdeSettings.History[0].ChangedAt), FormatSettings);
  TAtlasIdeSettings.Restore(0);
  UpdateFeatures;
  Warn(TAtlasStrings.Fmt(TAtlasTextId.SafeRestored, [At]));
end;

function ReadLog(const AFileName: string): TArray<string>;
begin
  Result := nil;
  try
    if TFile.Exists(AFileName) then
      Result := TFile.ReadAllLines(AFileName, TEncoding.UTF8);
  except
    on Exception do
      Result := nil;
  end;
end;

function TAtlasIdeSafeMode.DetailLines: TArray<string>;
var
  Lines, Log: TArray<string>;
  Line, Folder: string;
begin
  Result := nil;
  if not FHasCrashed then
  begin
    if FDecision.Crashed then
      Result := Result + [TAtlasStrings.Text(TAtlasTextId.SafeNoDetails)];
    Exit;
  end;
  Result := TAtlasSafeMode.Details(FCrashed);
  if TAtlasGuard.RotatingLog = nil then
    Exit;
  // Die Sitzung kann über eine Rotation reichen: erst die ältere Datei, dann die aktuelle.
  Folder := ExtractFileDir(TAtlasGuard.RotatingLog.FileName);
  Log := ReadLog(TPath.Combine(Folder, 'atlas.1.log')) + ReadLog(TAtlasGuard.RotatingLog.FileName);
  Lines := TAtlasSafeMode.LogLinesBetween(Log, TTimeZone.Local.ToLocalTime(FCrashed.StartedAt), FStartedLocal,
    MaxLogLines);
  Result := Result + ['', TAtlasStrings.Text(TAtlasTextId.SafeLogTitle)];
  // Anonym (#647): Pfade und Namen fallen weg.
  for Line in Lines do
    Result := Result + [TAtlasGuard.SafeMessage(Line)];
end;

procedure TAtlasIdeSafeMode.ShowNotice;
var
  Kind: TAtlasSafeNoticeKind;
  Area: TRect;
begin
  if FLevel = TAtlasSafeLevel.Normal then
    Exit;
  if FNotice <> nil then
  begin
    FNotice.BringToFront;
    Exit;
  end;
  if FAnswered then
    Kind := TAtlasSafeNoticeKind.Safe
  else
    Kind := TAtlasSafeNoticeKind.Ask;
  FNotice := TAtlasSafeModeNotice.CreateNotice(Self, Kind, NoticeText(Kind), Suggestion, RestoreCaption,
    DetailLines);
  FNotice.OnSafe :=
    procedure
    begin
      // Das geschlossene Fenster gibt sich selbst frei; das neue zeigt den abgesicherten Stand.
      FNotice := nil;
      FAnswered := True;
      ShowNotice;
    end;
  FNotice.OnNormal :=
    procedure
    begin
      Leave;
    end;
  FNotice.OnToggles := FOnShowToggles;
  FNotice.OnRestore :=
    procedure
    begin
      Restore;
    end;
  FNotice.OnExportLog := FOnExportLog;
  FNotice.OnBugReport := FOnBugReport;
  if Application.MainForm <> nil then
    Area := Application.MainForm.BoundsRect
  else
    Area := Screen.WorkAreaRect;
  FNotice.ShowIn(Area);
end;

end.
