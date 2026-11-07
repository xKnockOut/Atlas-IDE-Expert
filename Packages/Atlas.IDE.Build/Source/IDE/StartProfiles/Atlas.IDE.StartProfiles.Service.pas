unit Atlas.IDE.StartProfiles.Service;

// Startprofile in der IDE (#575): Auswahl, Setzen der Startoptionen des
// Projekts, Statusfeld und Start für die Willkommensseite (#764). Lesen,
// Zusammenführen und die lokale Datei in Atlas.Core.StartProfiles.Store.
// - Auswahl (Befehl „Startprofil: …“, Atlas.StartProfile, und Klick auf das
//   Statusfeld): Palettenfenster mit den Profilen des aktiven Projekts (erst
//   aus .atlas, dann persönliche), „Kein Startprofil“, „Aktuelle
//   Startoptionen als persönliches Profil speichern …“ und den Dateien zum
//   Bearbeiten.
// - Setzen: Atlas schreibt Parameter, Arbeitsordner, Host-Anwendung und
//   Umgebungsvariablen in die aktive Konfiguration für die aktive Plattform
//   (wie Start › Parameter, #396); „Start“ und „Ohne Debugger starten“ der
//   IDE nutzen sie dann. Das Projekt gilt danach als geändert; die IDE
//   speichert die Werte mit der .dproj. Die Startoptionen von vor dem ersten
//   Profil merkt sich die lokale Datei; „Kein Startprofil“ setzt sie zurück.
// - Ein Zeitgeber prüft jede Sekunde im Hauptthread, ob sich aktives Projekt,
//   Konfiguration, Plattform, .atlas oder die lokale Datei geändert haben.
//   Dann setzt er das gemerkte aktive Profil erneut (nur wenn die
//   Startoptionen abweichen) und meldet Text und Tooltip des Statusfelds über
//   OnStatus (Text '' = kein Feld: keine Profile, kein aktives).
// - Meldungen in der Meldungsansicht (Gruppe Atlas), nie als Dialog; das
//   Protokoll bekommt keine Parameter oder Pfade.
// - Lesen und Schreiben der Startoptionen, „Start“ und die vorübergehenden
//   Startparameter (Test debuggen, #585) liegen in Base
//   (Atlas.IDE.Foundation.StartOptions, #1455), weil auch das Modul Tests sie
//   braucht. Solange vorübergehende Parameter gelten, setzt der Zeitgeber das
//   aktive Profil nicht wieder; einen liegengebliebenen Eintrag stellt er
//   beim nächsten Mal zurück.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.StartProfiles.Store,
  Atlas.UI.Strings,
  Atlas.UI.Build.Strings;

type
  /// <summary>Text und Tooltip des Statusfelds; AText '' = kein Feld.</summary>
  TAtlasStartProfileStatus = reference to procedure(const AText, AHint: string);

  TAtlasIdeStartProfiles = class
  private class var
    FInstance: TAtlasIdeStartProfiles;
    FOnStatus: TAtlasStartProfileStatus;
  private
    FTimer: TTimer;
    FStamp: string;
    procedure Tick(Sender: TObject);
    procedure Check(AForce: Boolean);
    procedure Publish(const AProject: string);
    class function Team(const AProject: string): TAtlasTeamSettings; static;
    class function Summary(const AOptions: TAtlasStartOptions): string; static;
    class function Describe(const AEntry: TAtlasStartProfileEntry): string; static;
    class procedure SaveCurrent(const AProject: IOTAProject); static;
    class procedure EditPersonal(const AProject: string); static;
    class function ActionCommand(const AId: string; ATextId: TAtlasBuildTextId): TAtlasCommand; static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Zeitgeber anlegen und gleich prüfen (Feature StartProfiles).</summary>
    class procedure Start; static;
    class procedure Stop; static;
    class function Started: Boolean; static;
    /// <summary>Statusfeld neu melden (nach Einstellungsänderungen).</summary>
    class procedure Refresh; static;
    /// <summary>Profile für AProject (.dproj) ohne offenes Projekt: aus .atlas (wenn die Projektdatei an ist),
    /// dann die persönlichen (Willkommensseite #764).</summary>
    class function Profiles(const AProject: string): TArray<TAtlasStartProfileEntry>; static;
    /// <summary>Aktives Profil von AProject; '' ohne.</summary>
    class function ActiveName(const AProject: string): string; static;
    /// <summary>Profil AName für das geöffnete AProject setzen und merken; AName '' = kein Profil (Startoptionen
    /// von vorher). False mit Grund, wenn das Projekt nicht offen ist, das Profil fehlt oder Schreiben scheitert.
    /// </summary>
    class function Activate(const AProject, AName: string; out AReason: string): Boolean; static;
    /// <summary>Für #764: Profil setzen, AProject zum aktiven Projekt machen und „Start“ (ADebugger) bzw. „Ohne
    /// Debugger starten“ der IDE auslösen. Das Projekt muss geöffnet sein.</summary>
    class function Run(const AProject, AName: string; ADebugger: Boolean; out AReason: string): Boolean; static;
    /// <summary>Auswahl für das aktive Projekt öffnen (Befehl und Statusfeld).</summary>
    class procedure ShowPicker; static;
    /// <summary>Empfänger für Text und Tooltip des Statusfelds nach jeder Änderung; nil = keiner. Meldet sofort,
    /// wenn das Feature läuft.</summary>
    class procedure SetStatusHandler(const AValue: TAtlasStartProfileStatus); static;
  end;

implementation

uses
  System.Types,
  Vcl.Forms,
  Vcl.Dialogs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.StartOptions,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.UI.Commands.Palette;

const
  cCheckMs = 1000;
  // Einträge der Auswahl, die kein Profil sind.
  cNoneId = 'atlas:none';
  cSaveId = 'atlas:save';
  cEditPersonalId = 'atlas:personal';
  cEditTeamId = 'atlas:team';
  cProfilePrefix = 'profile:';

{ TAtlasIdeStartProfiles }

constructor TAtlasIdeStartProfiles.Create;
begin
  inherited Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cCheckMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeStartProfiles.Destroy;
begin
  FTimer.Free;
  if Assigned(FOnStatus) then
  begin
    FOnStatus('', '');
  end;
  inherited Destroy;
end;

class function TAtlasIdeStartProfiles.Team(const AProject: string): TAtlasTeamSettings;
begin
  // ForProject ist leer, wenn die Projektdatei (#486) ausgeschaltet ist.
  Result := TAtlasIdeTeamFile.ForProject(AProject);
end;

class function TAtlasIdeStartProfiles.Profiles(const AProject: string): TArray<TAtlasStartProfileEntry>;
begin
  Result := nil;
  if AProject = '' then
  begin
    Exit;
  end;
  Result := TAtlasStartProfiles.ForProject(TAtlasIdeStartOptions.Folder, AProject, Team(AProject));
end;

class function TAtlasIdeStartProfiles.ActiveName(const AProject: string): string;
begin
  Result := '';
  if AProject <> '' then
  begin
    Result := TAtlasStartProfiles.Load(TAtlasIdeStartOptions.Folder, AProject).Active;
  end;
end;

class function TAtlasIdeStartProfiles.Summary(const AOptions: TAtlasStartOptions): string;
var
  mParts: TArray<string>;
  mVariable: TAtlasTeamVariable;
  mNames: string;
begin
  mParts := nil;
  if AOptions.Parameters <> '' then
  begin
    mParts := mParts + [TAtlasBuildStrings.Fmt(TAtlasBuildTextId.StartProfilesParameters, [AOptions.Parameters])];
  end
  else
  begin
    mParts := mParts + [TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesNoOptions)];
  end;
  if AOptions.WorkingDir <> '' then
  begin
    mParts := mParts + [TAtlasBuildStrings.Fmt(TAtlasBuildTextId.StartProfilesWorkingDir, [AOptions.WorkingDir])];
  end;
  if AOptions.Host <> '' then
  begin
    mParts := mParts + [TAtlasBuildStrings.Fmt(TAtlasBuildTextId.StartProfilesHost, [AOptions.Host])];
  end;
  mNames := '';
  for mVariable in TAtlasStartProfiles.DecodeEnvironment(AOptions.Environment) do
  begin
    if mNames <> '' then
    begin
      mNames := mNames + ', ';
    end;
    mNames := mNames + mVariable.Name + '=' + mVariable.Value;
  end;
  if mNames <> '' then
  begin
    mParts := mParts + [TAtlasBuildStrings.Fmt(TAtlasBuildTextId.StartProfilesEnvironment, [mNames])];
  end;
  Result := string.Join(' · ', mParts);
end;

class function TAtlasIdeStartProfiles.Describe(const AEntry: TAtlasStartProfileEntry): string;
begin
  Result := Summary(TAtlasStartProfiles.OptionsOf(AEntry));
end;

/// <summary>Lokale Datei speichern; False mit Grund.</summary>
function SaveState(const AState: TAtlasStartProfileState; var AReason: string): Boolean;
begin
  Result := TAtlasStartProfiles.Save(TAtlasIdeStartOptions.Folder, AState);
  if not Result then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.StartProfilesSaveFailed);
  end;
end;

/// <summary>Startoptionen schreiben; False mit Grund.</summary>
function WriteWithReason(const AProject: IOTAProject; const AOptions: TAtlasStartOptions; var AReason: string): Boolean;
begin
  Result := TAtlasIdeStartOptions.WriteOptions(AProject, AOptions, AReason);
  if not Result then
  begin
    AReason := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesWriteFailed, [AReason]);
  end;
end;

/// <summary>Kein Profil: die gemerkten Startoptionen zurück; ohne gemerkte bleiben die jetzigen.</summary>
function RestoreBefore(const AProject: IOTAProject; var AState: TAtlasStartProfileState; var AReason: string): Boolean;
var
  mOptions: TAtlasStartOptions;
begin
  Result := (not TAtlasStartProfiles.Deactivate(AState, mOptions) or WriteWithReason(AProject, mOptions, AReason)) and
    SaveState(AState, AReason);
  if Result then
  begin
    TAtlasIdeStartOptions.Say(TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesRestored));
  end;
end;

/// <summary>Profil AName setzen; ACurrent sind die Startoptionen davor.</summary>
function ApplyProfile(const AProject: IOTAProject; var AState: TAtlasStartProfileState; const AName: string;
  const ACurrent: TAtlasStartOptions; var AReason: string): Boolean;
var
  mEntry: TAtlasStartProfileEntry;
  mOptions: TAtlasStartOptions;
begin
  if not TAtlasStartProfiles.Find(TAtlasStartProfiles.Merge(TAtlasIdeStartProfiles.Team(AProject.FileName), AState),
    AName, mEntry) then
  begin
    AReason := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.StartProfilesUnknown,
      [AName, ExtractFileName(AProject.FileName)]);
    Exit(False);
  end;
  mOptions := TAtlasStartProfiles.OptionsOf(mEntry);
  // Erst merken, was vorher galt, dann schreiben: Scheitert das Schreiben, bleibt der alte Stand.
  TAtlasStartProfiles.Activate(AState, mEntry.Profile.Name, ACurrent);
  Result := WriteWithReason(AProject, mOptions, AReason) and SaveState(AState, AReason);
  if Result then
  begin
    TAtlasIdeStartOptions.Say(TAtlasBuildStrings.Fmt(TAtlasBuildTextId.StartProfilesApplied,
      [mEntry.Profile.Name, TAtlasIdeStartProfiles.Summary(mOptions)]));
  end;
end;

class function TAtlasIdeStartProfiles.Activate(const AProject, AName: string; out AReason: string): Boolean;
var
  mProject: IOTAProject;
  mState: TAtlasStartProfileState;
  mCurrent: TAtlasStartOptions;
begin
  AReason := '';
  mProject := TAtlasIdeStartOptions.FindProject(AProject);
  if mProject = nil then
  begin
    AReason := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesNotOpen, [ExtractFileName(AProject)]);
    Exit(False);
  end;
  mState := TAtlasStartProfiles.Load(TAtlasIdeStartOptions.Folder, mProject.FileName);
  TAtlasIdeStartOptions.ReadOptions(mProject, mCurrent);
  if Trim(AName) = '' then
  begin
    Result := RestoreBefore(mProject, mState, AReason);
  end
  else
  begin
    Result := ApplyProfile(mProject, mState, AName, mCurrent, AReason);
  end;
  if Result and (FInstance <> nil) then
  begin
    FInstance.Check(True);
  end;
end;

class function TAtlasIdeStartProfiles.Run(const AProject, AName: string; ADebugger: Boolean;
  out AReason: string): Boolean;
var
  mProject: IOTAProject;
begin
  Result := False;
  AReason := '';
  if TAtlasIdeStartOptions.Debugging then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.StartProfilesDebuggerRunning);
    Exit;
  end;
  mProject := TAtlasIdeStartOptions.FindProject(AProject);
  if mProject = nil then
  begin
    AReason := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesNotOpen, [ExtractFileName(AProject)]);
    Exit;
  end;
  // „Start“ der IDE startet das aktive Projekt.
  TAtlasIdeStartOptions.MakeActive(mProject);
  if not Activate(mProject.FileName, AName, AReason) then
  begin
    Exit;
  end;
  Result := TAtlasIdeStartOptions.Execute(ADebugger, AReason);
end;

class procedure TAtlasIdeStartProfiles.SaveCurrent(const AProject: IOTAProject);
var
  mName: string;
  mOptions: TAtlasStartOptions;
  mState: TAtlasStartProfileState;
  mReason: string;
begin
  mName := '';
  if not InputQuery(TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesNameTitle),
    TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesNamePrompt), mName) then
  begin
    Exit;
  end;
  if Trim(mName) = '' then
  begin
    TAtlasIdeStartOptions.Say(TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesInvalidName));
    Exit;
  end;
  TAtlasIdeStartOptions.ReadOptions(AProject, mOptions);
  mState := TAtlasStartProfiles.Load(TAtlasIdeStartOptions.Folder, AProject.FileName);
  TAtlasStartProfiles.PutPersonal(mState, TAtlasStartProfiles.ProfileFromOptions(mName, mOptions));
  if not TAtlasStartProfiles.Save(TAtlasIdeStartOptions.Folder, mState) then
  begin
    TAtlasIdeStartOptions.Say(TAtlasStrings.Text(TAtlasTextId.StartProfilesSaveFailed));
    Exit;
  end;
  TAtlasIdeStartOptions.Say(TAtlasBuildStrings.Fmt(TAtlasBuildTextId.StartProfilesSaved, [Trim(mName)]));
  // Gleich aktiv: Die Startoptionen bleiben dieselben, gemerkt wird das Profil.
  if not Activate(AProject.FileName, Trim(mName), mReason) then
  begin
    TAtlasIdeStartOptions.Say(mReason);
  end;
end;

class procedure TAtlasIdeStartProfiles.EditPersonal(const AProject: string);
var
  mFileName: string;
  mState: TAtlasStartProfileState;
  mActions: IOTAActionServices;
begin
  mFileName := TAtlasStartProfiles.FileFor(TAtlasIdeStartOptions.Folder, AProject);
  if not FileExists(mFileName) then
  begin
    mState := TAtlasStartProfiles.Empty(AProject);
    if not TAtlasStartProfiles.Save(TAtlasIdeStartOptions.Folder, mState) then
    begin
      TAtlasIdeStartOptions.Say(TAtlasStrings.Text(TAtlasTextId.StartProfilesSaveFailed));
      Exit;
    end;
  end;
  if Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    mActions.OpenFile(mFileName);
  end;
end;

class function TAtlasIdeStartProfiles.ActionCommand(const AId: string; ATextId: TAtlasBuildTextId): TAtlasCommand;
begin
  Result := Default(TAtlasCommand);
  Result.Id := AId;
  Result.Caption := TAtlasBuildStrings.Text(ATextId);
  Result.Path := TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesActions);
end;

function ProfileCommand(const AEntry: TAtlasStartProfileEntry; const AActive: string): TAtlasCommand;
begin
  Result := Default(TAtlasCommand);
  Result.Id := cProfilePrefix + AEntry.Profile.Name;
  Result.Caption := AEntry.Profile.Name;
  if AEntry.Source = TAtlasStartProfileSource.Team then
  begin
    Result.Path := TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesTeam);
  end
  else
  begin
    Result.Path := TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesPersonal);
  end;
  if SameText(AEntry.Profile.Name, AActive) then
  begin
    Result.ShortCut := TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesActiveMark);
  end;
  Result.Description := TAtlasIdeStartProfiles.Describe(AEntry);
end;

/// <summary>Profile, „Kein Startprofil“ (nur mit aktivem) und die Aktionen.</summary>
function PickerCommands(const AFileName: string): TArray<TAtlasCommand>;
var
  mActive: string;
  mEntry: TAtlasStartProfileEntry;
begin
  mActive := TAtlasIdeStartProfiles.ActiveName(AFileName);
  Result := nil;
  for mEntry in TAtlasIdeStartProfiles.Profiles(AFileName) do
  begin
    Result := Result + [ProfileCommand(mEntry, mActive)];
  end;
  if mActive <> '' then
  begin
    Result := Result + [TAtlasIdeStartProfiles.ActionCommand(cNoneId, TAtlasBuildTextId.StartProfilesNone)];
  end;
  Result := Result + [TAtlasIdeStartProfiles.ActionCommand(cSaveId, TAtlasBuildTextId.StartProfilesSaveCurrent),
    TAtlasIdeStartProfiles.ActionCommand(cEditPersonalId, TAtlasBuildTextId.StartProfilesEditPersonal),
    TAtlasIdeStartProfiles.ActionCommand(cEditTeamId, TAtlasBuildTextId.StartProfilesEditTeam)];
end;

procedure ActivateOrSay(const AFileName, AName: string);
var
  mReason: string;
begin
  if not TAtlasIdeStartProfiles.Activate(AFileName, AName, mReason) then
  begin
    TAtlasIdeStartOptions.Say(mReason);
  end;
end;

procedure OpenTeamFile;
begin
  if TAtlasIdeSettings.Current.TeamFile then
  begin
    TAtlasIdeTeamFile.OpenInEditor;
  end
  else
  begin
    TAtlasIdeStartOptions.Say(TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesTeamOff));
  end;
end;

/// <summary>Eintrag AId der Auswahl für AFileName ausführen.</summary>
procedure ExecutePicked(const AFileName, AId: string);
var
  mCurrent: IOTAProject;
begin
  // Das Projekt kann inzwischen geschlossen sein.
  mCurrent := TAtlasIdeStartOptions.FindProject(AFileName);
  if mCurrent = nil then
  begin
    TAtlasIdeStartOptions.Say(TAtlasStrings.Fmt(TAtlasTextId.StartProfilesNotOpen, [ExtractFileName(AFileName)]));
  end
  else if AId = cNoneId then
  begin
    ActivateOrSay(AFileName, '');
  end
  else if AId = cSaveId then
  begin
    TAtlasIdeStartProfiles.SaveCurrent(mCurrent);
  end
  else if AId = cEditPersonalId then
  begin
    TAtlasIdeStartProfiles.EditPersonal(AFileName);
  end
  else if AId = cEditTeamId then
  begin
    OpenTeamFile;
  end
  else if Copy(AId, 1, Length(cProfilePrefix)) = cProfilePrefix then
  begin
    ActivateOrSay(AFileName, Copy(AId, Length(cProfilePrefix) + 1, MaxInt));
  end;
end;

function PickedHandler(const AFileName: string): TProc<TAtlasCommand>;
begin
  Result :=
    procedure(ACommand: TAtlasCommand)
    var
      mId: string;
    begin
      mId := ACommand.Id;
      TAtlasGuard.Run(TAtlasFeature.Build,
        procedure
        begin
          ExecutePicked(AFileName, mId);
        end);
    end;
end;

function PickerArea: TRect;
begin
  if Screen.ActiveForm <> nil then
  begin
    Result := Screen.ActiveForm.BoundsRect;
  end
  else if Application.MainForm <> nil then
  begin
    Result := Application.MainForm.BoundsRect;
  end
  else
  begin
    Result := Screen.WorkAreaRect;
  end;
end;

class procedure TAtlasIdeStartProfiles.ShowPicker;
var
  mProject: IOTAProject;
  mWindow: TAtlasPaletteWindow;
begin
  mProject := TAtlasIdeStartOptions.ActiveProject;
  if mProject = nil then
  begin
    TAtlasIdeStartOptions.Say(TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesNoProject));
    Exit;
  end;
  mWindow := TAtlasPaletteWindow.CreatePalette(Application, PickerCommands(mProject.FileName), nil,
    TAtlasIdeStyle.Colors);
  mWindow.KeepOrder := True;
  mWindow.OnExecute := PickedHandler(mProject.FileName);
  mWindow.ShowOver(PickerArea);
end;

procedure TAtlasIdeStartProfiles.Publish(const AProject: string);
var
  mEntries: TArray<TAtlasStartProfileEntry>;
  mEntry: TAtlasStartProfileEntry;
  mActive, mText, mHint: string;
begin
  if not Assigned(FOnStatus) then
  begin
    Exit;
  end;
  mText := '';
  mHint := '';
  if AProject <> '' then
  begin
    mEntries := Profiles(AProject);
    mActive := ActiveName(AProject);
    if mActive = '' then
    begin
      // Ohne Profile kein Feld; mit Profilen zeigt es „–“.
      if Length(mEntries) > 0 then
      begin
        mText := TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesStatusNone);
        mHint := TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesHintNone);
      end;
    end
    else if TAtlasStartProfiles.Find(mEntries, mActive, mEntry) then
    begin
      mText := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.StartProfilesStatus, [mEntry.Profile.Name]);
      mHint := Describe(mEntry);
    end
    else
    begin
      mText := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.StartProfilesStatusMissing, [mActive]);
      mHint := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.StartProfilesHintMissing, [mActive]);
    end;
    if mText <> '' then
    begin
      mHint := mHint + sLineBreak + TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesHintClick);
    end;
  end;
  FOnStatus(mText, mHint);
end;

procedure TAtlasIdeStartProfiles.Check(AForce: Boolean);
var
  mProject: IOTAProject;
  mFileName, mPersonal, mStamp, mActive, mReason: string;
  mTeamSettings: TAtlasTeamSettings;
  mAge: TDateTime;
  mEntry: TAtlasStartProfileEntry;
begin
  mProject := TAtlasIdeStartOptions.ActiveProject;
  mFileName := '';
  mStamp := '';
  if mProject <> nil then
  begin
    mFileName := mProject.FileName;
    mTeamSettings := Team(mFileName);
    mPersonal := TAtlasStartProfiles.FileFor(TAtlasIdeStartOptions.Folder, mFileName);
    mStamp := mFileName + '|' + mProject.CurrentConfiguration + '|' + mProject.CurrentPlatform + '|' +
      mTeamSettings.FileName;
    if (mTeamSettings.FileName <> '') and FileAge(mTeamSettings.FileName, mAge) then
    begin
      mStamp := mStamp + '|' + FloatToStr(mAge, TFormatSettings.Invariant);
    end;
    if FileAge(mPersonal, mAge) then
    begin
      mStamp := mStamp + '|' + FloatToStr(mAge, TFormatSettings.Invariant);
    end;
  end;
  if not AForce and (mStamp = FStamp) then
  begin
    Exit;
  end;
  FStamp := mStamp;
  // Gemerktes Profil für Projekt, Konfiguration und Plattform (wieder) setzen, wenn die Startoptionen abweichen;
  // nicht, solange vorübergehende Parameter gelten (#585). Ein liegengebliebener Eintrag wird zurückgestellt.
  if (mProject <> nil) and not SameText(TAtlasIdeStartOptions.TemporaryProject, mFileName) then
  begin
    TAtlasIdeStartOptions.RecoverTemporary(mProject);
    mActive := ActiveName(mFileName);
    if (mActive <> '') and TAtlasStartProfiles.Find(Profiles(mFileName), mActive, mEntry) and
      not TAtlasIdeStartOptions.WriteOptions(mProject, TAtlasStartProfiles.OptionsOf(mEntry), mReason) then
    begin
      TAtlasIdeStartOptions.Say(TAtlasStrings.Fmt(TAtlasTextId.StartProfilesWriteFailed, [mReason]));
    end;
  end;
  Publish(mFileName);
end;

procedure TAtlasIdeStartProfiles.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Build,
    procedure
    begin
      Check(False);
    end);
end;

class procedure TAtlasIdeStartProfiles.Start;
begin
  if FInstance <> nil then
  begin
    Exit;
  end;
  FInstance := TAtlasIdeStartProfiles.Create;
  TAtlasGuard.Run(TAtlasFeature.Build,
    procedure
    begin
      FInstance.Check(True);
    end);
end;

class procedure TAtlasIdeStartProfiles.Stop;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeStartProfiles.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class procedure TAtlasIdeStartProfiles.Refresh;
begin
  if FInstance <> nil then
  begin
    FInstance.Check(True);
  end;
end;

class procedure TAtlasIdeStartProfiles.SetStatusHandler(const AValue: TAtlasStartProfileStatus);
begin
  FOnStatus := AValue;
  if FInstance <> nil then
  begin
    FInstance.Check(True);
  end;
end;

end.
