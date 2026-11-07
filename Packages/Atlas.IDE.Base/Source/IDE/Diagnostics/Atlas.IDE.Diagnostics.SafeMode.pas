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
// - ATLAS_NO_SESSION_MARKER=1 (Bau-IDE von cc.ps1): kein Sitzungsbuch, also
//   keine Marke, keine Auswertung fremder Marken, Zustand unberührt
//   (TAtlasSessionBook); Taste und ATLAS_SAFE_MODE wirken weiter.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Contract,
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
    FBook: TAtlasSessionBook;
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
    procedure WriteMarker;
    procedure ShowLine;
    procedure HideLine;
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
  cPROCESS_QUERY_LIMITED_INFORMATION = $1000;

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
  begin
    FNotice := nil;
  end;
end;

class function TAtlasIdeSafeMode.DefaultFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), 'Session');
end;

function Options: TAtlasSafeOptions;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Stored;
  Result := TAtlasSafeOptions.Create(mSettings.SafeAskAfterCrash, mSettings.SafeAutoAfterRepeatedCrash,
    TAtlasSafeMode.KeyOf(mSettings.SafeStartupKey));
end;

function NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

function Alive(AProcessId: Cardinal; AStartedAt: TDateTime): Boolean;
var
  mProcess: THandle;
  mCode: DWORD;
  mCreation, mExitTime, mKernelTime, mUserTime: TFileTime;
  mStarted: TSystemTime;
begin
  mProcess := OpenProcess(cPROCESS_QUERY_LIMITED_INFORMATION, False, AProcessId);
  if mProcess = 0 then
  begin
    // Kein Zugriff heißt: Den Prozess gibt es (andere Anmeldung); sonst ist er beendet.
    Exit(GetLastError = ERROR_ACCESS_DENIED);
  end;
  try
    Result := GetExitCodeProcess(mProcess, mCode) and (mCode = STILL_ACTIVE);
    // Später gestartet als die Marke: Die Nummer gehört einem neuen Prozess.
    if Result and GetProcessTimes(mProcess, mCreation, mExitTime, mKernelTime, mUserTime) and
      FileTimeToSystemTime(mCreation, mStarted) then
    begin
      Result := SystemTimeToDateTime(mStarted) <= AStartedAt;
    end;
  finally
    CloseHandle(mProcess);
  end;
end;

function KeyDown(AKey: TAtlasStartupKey): TAtlasStartupKey;
begin
  Result := TAtlasStartupKey.None;
  case AKey of
    TAtlasStartupKey.Shift:
      if GetAsyncKeyState(VK_SHIFT) < 0 then
      begin
        Result := AKey;
      end;
    TAtlasStartupKey.Ctrl:
      if GetAsyncKeyState(VK_CONTROL) < 0 then
      begin
        Result := AKey;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

function Forced: Boolean;
var
  mArgs: TArray<string>;
  mIndex: Integer;
begin
  mArgs := nil;
  for mIndex := 1 to ParamCount do
  begin
    mArgs := mArgs + [ParamStr(mIndex)];
  end;
  Result := TAtlasSafeMode.IsForced(GetEnvironmentVariable(TAtlasSafeMode.EnvironmentName), mArgs);
end;

function EnabledFeatures: TArray<string>;
var
  mToggle: TAtlasQuickToggle;
  mSettings: TAtlasPluginSettings;
  mValue: Boolean;
begin
  Result := nil;
  mSettings := TAtlasIdeSettings.Current;
  for mToggle in TAtlasIdeSettings.QuickToggles do
  begin
    if TAtlasQuickToggles.GetFlag(mSettings, mToggle.Key, mValue) and mValue then
    begin
      Result := Result + [mToggle.Key];
    end;
  end;
end;

procedure Warn(const AText: string);
var
  mWarning: TAtlasGuardMessage;
begin
  TAtlasGuard.Log(AText);
  mWarning := TAtlasGuard.OnWarning;
  if Assigned(mWarning) then
  begin
    mWarning(AText);
  end;
end;

procedure TAtlasIdeSafeMode.WriteMarker;
begin
  if not FStarted then
  begin
    Exit;
  end;
  try
    FBook.SaveMarker(FMarker);
  except
    // Ohne Marke erkennt der nächste Start den Absturz nicht; die IDE stört das nicht.
    on Exception do
      ;
  end;
end;

/// <summary>Zustand und Marken abgestürzter Sitzungen aus ABook; leer ohne Buch oder wenn das Lesen
/// scheitert.</summary>
procedure ReadSessions(const ABook: TAtlasSessionBook; out AState: TAtlasSafeState;
  out ACrashed: TArray<TAtlasSessionMarker>);
begin
  try
    ABook.Open(
      function(AProcessId: Cardinal; AStartedAt: TDateTime): Boolean
      begin
        Result := Alive(AProcessId, AStartedAt);
      end, AState, ACrashed);
  except
    on Exception do
    begin
      AState := Default(TAtlasSafeState);
      ACrashed := nil;
    end;
  end;
end;

/// <summary>Für den Vorschlag: Was die letzte gespeicherte Änderung umgestellt hat.</summary>
function LastChangedKeys: TArray<string>;
begin
  try
    Result := TAtlasIdeSettings.History.LastChangedKeys(TAtlasIdeSettings.Stored);
  except
    on Exception do
      Result := nil;
  end;
end;

/// <summary>Zusatz der Startzeile im Protokoll, wenn die Sitzung kein Sitzungsbuch führt.</summary>
function NoBookNote(const ABook: TAtlasSessionBook): string;
begin
  Result := '';
  if not ABook.Tracked then
  begin
    Result := ', ohne Sitzungsmarke (' + TAtlasSafeMode.NoMarkerEnvironmentName + ')';
  end;
end;

procedure TAtlasIdeSafeMode.Start(const AFolder: string; const ARegistry: IAtlasStatusRegistry);
var
  mState: TAtlasSafeState;
  mCrashed: TArray<TAtlasSessionMarker>;
  mSafeOptions: TAtlasSafeOptions;
  mStartedAt: TDateTime;
  mShow: TThreadProcedure;
begin
  FBook := TAtlasSessionBook.Create(AFolder, GetCurrentProcessId,
    GetEnvironmentVariable(TAtlasSafeMode.NoMarkerEnvironmentName));
  FRegistry := ARegistry;
  mStartedAt := NowUtc;
  FStartedLocal := Now;
  mSafeOptions := Options;
  ReadSessions(FBook, mState, mCrashed);
  FChangedKeys := LastChangedKeys;
  FDecision := TAtlasSafeMode.Decide(mState, mCrashed, mStartedAt, mSafeOptions, KeyDown(mSafeOptions.StartupKey),
    Forced);
  FLevel := FDecision.Level;
  FAnswered := not FDecision.Ask;
  // Nur die Marke dieses Absturzes, nicht die eines früheren aus dem Zustand.
  FHasCrashed := (Length(mCrashed) > 0) and (mState.CrashedMarker <> '') and
    TAtlasSessionMarker.FromJson(mState.CrashedMarker, FCrashed);
  try
    FBook.SaveState(mState);
  except
    on Exception do
      ;
  end;
  if FLevel <> TAtlasSafeLevel.Normal then
  begin
    TAtlasIdeSettings.SetSession(TAtlasSafeMode.SafeSession(TAtlasIdeSettings.QuickToggles));
  end;
  FMarker := TAtlasSessionMarker.Create(GetCurrentProcessId, TAtlasPluginVersion.Version, mStartedAt);
  FMarker.Level := FLevel;
  FMarker.Features := EnabledFeatures;
  FStarted := True;
  WriteMarker;
  TAtlasGuard.Log(Format('Atlas gestartet (%s), Stufe %s, Grund %s%s', [TAtlasPluginVersion.Version,
    GetEnumName(TypeInfo(TAtlasSafeLevel), Ord(FLevel)),
    GetEnumName(TypeInfo(TAtlasSafeReason), Ord(FDecision.Reason)), NoBookNote(FBook)]));
  if FLevel = TAtlasSafeLevel.Normal then
  begin
    Exit;
  end;
  ShowLine;
  // Erst wenn die IDE steht: Das Hauptfenster gibt es beim Laden der Packages evtl. noch nicht.
  mShow :=
    procedure
    begin
      ShowNotice;
    end;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Settings, mShow);
end;

procedure TAtlasIdeSafeMode.Loaded(ALoadMs: Int64);
begin
  if not FStarted then
  begin
    Exit;
  end;
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
begin
  if not FStarted then
  begin
    Exit;
  end;
  FStarted := False;
  if FNotice <> nil then
  begin
    FreeAndNil(FNotice);
  end;
  HideLine;
  try
    FBook.Close;
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
  mFeatures: TArray<string>;
begin
  mFeatures := EnabledFeatures;
  FLock.Enter;
  try
    FMarker.Features := mFeatures;
    FMarker.Level := FLevel;
    WriteMarker;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasIdeSafeMode.ShowLine;
var
  mAction: TProc;
begin
  if (FRegistry = nil) or (FLineRef <> nil) then
  begin
    Exit;
  end;
  mAction :=
    procedure
    begin
      ShowNotice;
    end;
  FLine := TAtlasStatusLine.Create(FRegistry, StatusId, StatusOrder, mAction);
  FLineRef := FLine;
  FLine.Update(TAtlasStrings.Text(TAtlasTextId.SafeStatusLine), TAtlasStatusState.Yellow,
    TAtlasStrings.Text(TAtlasTextId.SafeStatusSummary));
  FRegistry.Add(FLineRef);
end;

procedure TAtlasIdeSafeMode.HideLine;
begin
  if FLineRef = nil then
  begin
    Exit;
  end;
  FLine.Detach;
  if FRegistry <> nil then
  begin
    FRegistry.Remove(StatusId);
  end;
  FLine := nil;
  FLineRef := nil;
end;

procedure TAtlasIdeSafeMode.Leave;
begin
  if FLevel = TAtlasSafeLevel.Normal then
  begin
    Exit;
  end;
  FLevel := TAtlasSafeLevel.Normal;
  FAnswered := True;
  if FNotice <> nil then
  begin
    FNotice.Close;
  end;
  HideLine;
  // Die Composition meldet über OnChanged der Einstellungen alles Weitere an.
  TAtlasIdeSettings.SetSession(Default(TAtlasToggleSession));
  UpdateFeatures;
  Warn(TAtlasStrings.Text(TAtlasTextId.SafeLeft));
end;

function NoticeText(AKind: TAtlasSafeNoticeKind; AReason: TAtlasSafeReason): string;
begin
  if AKind = TAtlasSafeNoticeKind.Ask then
  begin
    Exit(TAtlasStrings.Text(TAtlasTextId.SafeAskText));
  end;
  case AReason of
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

function Suggestion(const ADecision: TAtlasSafeDecision; const AChangedKeys: TArray<string>;
  const ACrashed: TAtlasSessionMarker): string;
var
  mToggles: TArray<TAtlasQuickToggle>;
  mToggle: TAtlasQuickToggle;
  mKey: string;
  mNames: TArray<string>;
begin
  Result := '';
  if not ADecision.Crashed then
  begin
    Exit;
  end;
  mToggles := TAtlasIdeSettings.QuickToggles;
  mNames := nil;
  for mKey in TAtlasSafeMode.Suggest(mToggles, AChangedKeys, ACrashed) do
  begin
    if TAtlasQuickToggles.Find(mToggles, mKey, mToggle) then
    begin
      mNames := mNames + [mToggle.Caption];
    end;
  end;
  if Length(mNames) > 0 then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.SafeSuggest, [string.Join(', ', mNames)]);
  end;
end;

function RestoreCaption: string;
begin
  Result := '';
  try
    if TAtlasIdeSettings.History.Count > 0 then
    begin
      Result := TAtlasStrings.Fmt(TAtlasTextId.SafeRestore,
        [DateTimeToStr(TTimeZone.Local.ToLocalTime(TAtlasIdeSettings.History[0].ChangedAt), FormatSettings)]);
    end;
  except
    on Exception do
      Result := '';
  end;
end;

procedure TAtlasIdeSafeMode.Restore;
var
  mAt: string;
begin
  if TAtlasIdeSettings.History.Count = 0 then
  begin
    Exit;
  end;
  mAt := DateTimeToStr(TTimeZone.Local.ToLocalTime(TAtlasIdeSettings.History[0].ChangedAt), FormatSettings);
  TAtlasIdeSettings.Restore(0);
  UpdateFeatures;
  Warn(TAtlasStrings.Fmt(TAtlasTextId.SafeRestored, [mAt]));
end;

function ReadLog(const AFileName: string): TArray<string>;
begin
  Result := nil;
  try
    if TFile.Exists(AFileName) then
    begin
      Result := TFile.ReadAllLines(AFileName, TEncoding.UTF8);
    end;
  except
    on Exception do
      Result := nil;
  end;
end;

function DetailLines(AHasCrashed: Boolean; const ADecision: TAtlasSafeDecision;
  const ACrashed: TAtlasSessionMarker; AStartedLocal: TDateTime): TArray<string>;
var
  mLines, mLog: TArray<string>;
  mLine, mFolder: string;
begin
  Result := nil;
  if not AHasCrashed then
  begin
    if ADecision.Crashed then
    begin
      Result := Result + [TAtlasStrings.Text(TAtlasTextId.SafeNoDetails)];
    end;
    Exit;
  end;
  Result := TAtlasSafeMode.Details(ACrashed);
  if TAtlasGuard.RotatingLog = nil then
  begin
    Exit;
  end;
  // Die Sitzung kann über eine Rotation reichen: erst die ältere Datei, dann die aktuelle.
  mFolder := ExtractFileDir(TAtlasGuard.RotatingLog.FileName);
  mLog := ReadLog(TPath.Combine(mFolder, 'atlas.1.log')) + ReadLog(TAtlasGuard.RotatingLog.FileName);
  mLines := TAtlasSafeMode.LogLinesBetween(mLog, TTimeZone.Local.ToLocalTime(ACrashed.StartedAt), AStartedLocal,
    TAtlasIdeSafeMode.MaxLogLines);
  Result := Result + ['', TAtlasStrings.Text(TAtlasTextId.SafeLogTitle)];
  // Anonym (#647): Pfade und Namen fallen weg.
  for mLine in mLines do
  begin
    Result := Result + [TAtlasGuard.SafeMessage(mLine)];
  end;
end;

procedure TAtlasIdeSafeMode.ShowNotice;
var
  mKind: TAtlasSafeNoticeKind;
  mArea: TRect;
begin
  if FLevel = TAtlasSafeLevel.Normal then
  begin
    Exit;
  end;
  if FNotice <> nil then
  begin
    FNotice.BringToFront;
    Exit;
  end;
  if FAnswered then
  begin
    mKind := TAtlasSafeNoticeKind.Safe;
  end
  else
  begin
    mKind := TAtlasSafeNoticeKind.Ask;
  end;
  FNotice := TAtlasSafeModeNotice.CreateNotice(Self, mKind, NoticeText(mKind, FDecision.Reason),
    Suggestion(FDecision, FChangedKeys, FCrashed), RestoreCaption,
    DetailLines(FHasCrashed, FDecision, FCrashed, FStartedLocal));
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
  begin
    mArea := Application.MainForm.BoundsRect;
  end
  else
  begin
    mArea := Screen.WorkAreaRect;
  end;
  FNotice.ShowIn(mArea);
end;

end.
