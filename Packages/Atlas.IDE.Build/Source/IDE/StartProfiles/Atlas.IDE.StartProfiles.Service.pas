unit Atlas.IDE.StartProfiles.Service;

// Startprofile in der IDE (#575): Auswahl, Setzen der Startoptionen des
// Projekts, Statusfeld und Start für die Willkommensseite (#764). Lesen,
// Zusammenführen und die lokale Datei in Atlas.Core.StartProfiles.Store, der
// Ablauf (Profil setzen, zurücksetzen, speichern, Statusfeld) in
// Atlas.Core.StartProfiles.Flow; diese Unit gibt ihm Zugriff auf die
// Startoptionen der IDE und macht aus seinen Ergebnissen Meldungen.
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
  Atlas.Plugin.Settings.TeamFile,
  Atlas.Core.StartProfiles.Store,
  Atlas.Core.StartProfiles.Flow,
  Atlas.Plugin.Localization.Strings,
  Atlas.UI.Build.Strings;

type
  /// <summary>Text und Tooltip des Statusfelds; AText '' = kein Feld.</summary>
  TAtlasStartProfileStatus = reference to procedure(const AText, AHint: string);

  TAtlasIdeStartProfiles = class
  private class var
    FInstance: TAtlasIdeStartProfiles;
    FOnStatus: TAtlasStartProfileStatus;
    FFlow: TAtlasStartProfileFlow;
  private
    FTimer: TTimer;
    FStamp: string;
    /// <summary>Anmeldung bei TAtlasIdeOpenWatch: ohne Projekt ruht der Takt.</summary>
    FOpenHandle: Integer;
    procedure OpenChanged;
    procedure Tick(Sender: TObject);
    procedure Check(AForce: Boolean);
    procedure Publish(const AProject: string);
    class function Team(const AProject: string): TAtlasTeamSettings; static;
    /// <summary>Ablauf mit Zugriff auf die Startoptionen der IDE; lebt bis zum Entladen der Unit.</summary>
    class function Flow: TAtlasStartProfileFlow; static;
    /// <summary>Meldung zu einem gescheiterten Schritt für AProject.</summary>
    class function Failure(const AResult: TAtlasStartProfileResult; const AProject: string): string; static;
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
  Vcl.Forms,
  Vcl.Dialogs,
  Atlas.Core.StartProfiles.Picker,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.ToolsApi.Files.OpenWatch,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.StartOptions,
  Atlas.ToolsApi.Theme.Style,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.UI.Commands.Palette;

const
  cCheckMs = 1000;

{ TAtlasIdeStartProfiles }

constructor TAtlasIdeStartProfiles.Create;
begin
  inherited Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cCheckMs;
  FTimer.OnTimer := Tick;
  // Ohne Projekt gibt es kein Profil und keine Datei zu beobachten; der Takt lief sonst jede Sekunde auch auf der
  // Willkommensseite.
  FOpenHandle := TAtlasIdeOpenWatch.Register(OpenChanged);
  FTimer.Enabled := TAtlasIdeOpenWatch.ProjectOpen;
end;

destructor TAtlasIdeStartProfiles.Destroy;
begin
  TAtlasIdeOpenWatch.Unregister(FOpenHandle);
  FTimer.Free;
  if Assigned(FOnStatus) then
  begin
    FOnStatus('', '');
  end;
  inherited Destroy;
end;

procedure TAtlasIdeStartProfiles.OpenChanged;
begin
  FTimer.Enabled := TAtlasIdeOpenWatch.ProjectOpen;
  // Gleich prüfen: beim Öffnen das Profil setzen, beim Schließen das Statusfeld leeren (letzter Takt).
  Tick(nil);
end;

procedure TAtlasIdeStartProfiles.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Build,
    procedure
    begin
      Check(False);
    end);
end;

/// <summary>Änderungszeit von AFileName für den Stempel.</summary>
function AgeOf(const AFileName: string): TAtlasStartProfileFileAge;
var
  mAge: TDateTime;
begin
  mAge := 0;
  Result := TAtlasStartProfileFileAge.Make((AFileName <> '') and FileAge(AFileName, mAge), mAge);
end;

/// <summary>Stempel des geöffneten AProject samt .atlas und lokaler Datei.</summary>
function StampOf(const AProject: IOTAProject): string;
var
  mTeamFile: string;
begin
  mTeamFile := TAtlasIdeStartProfiles.Team(AProject.FileName).FileName;
  Result := TAtlasStartProfilePicker.Stamp(AProject.FileName, AProject.CurrentConfiguration, AProject.CurrentPlatform,
    mTeamFile, AgeOf(mTeamFile), AgeOf(TAtlasStartProfiles.FileFor(TAtlasIdeStartOptions.Folder, AProject.FileName)));
end;

procedure TAtlasIdeStartProfiles.Check(AForce: Boolean);
var
  mProject: IOTAProject;
  mFileName, mStamp: string;
  mResult: TAtlasStartProfileResult;
begin
  mProject := TAtlasIdeStartOptions.ActiveProject;
  mFileName := '';
  mStamp := '';
  if mProject <> nil then
  begin
    mFileName := mProject.FileName;
    mStamp := StampOf(mProject);
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
    mResult := Flow.Reapply(mFileName);
    if not mResult.Succeeded then
    begin
      TAtlasIdeStartOptions.Say(Failure(mResult, mFileName));
    end;
  end;
  Publish(mFileName);
end;

procedure TAtlasIdeStartProfiles.Publish(const AProject: string);
var
  // Voll qualifiziert: Der Rückruftyp TAtlasStartProfileStatus dieser Unit verdeckt den Record (E2010).
  mStatus: Atlas.Core.StartProfiles.Flow.TAtlasStartProfileStatus;
  mText, mHint: string;
begin
  if not Assigned(FOnStatus) then
  begin
    Exit;
  end;
  mText := '';
  mHint := '';
  mStatus := Flow.Status(AProject);
  case mStatus.Kind of
    TAtlasStartProfileStatusKind.Hidden: ;
    TAtlasStartProfileStatusKind.NoneActive:
      begin
        mText := TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesStatusNone);
        mHint := TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesHintNone);
      end;
    TAtlasStartProfileStatusKind.Active:
      begin
        mText := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.StartProfilesStatus, [mStatus.Entry.Profile.Name]);
        mHint := Describe(mStatus.Entry);
      end;
    TAtlasStartProfileStatusKind.Missing:
      begin
        mText := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.StartProfilesStatusMissing, [mStatus.Active]);
        mHint := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.StartProfilesHintMissing, [mStatus.Active]);
      end;
  end;
  if mText <> '' then
  begin
    mHint := mHint + sLineBreak + TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesHintClick);
  end;
  FOnStatus(mText, mHint);
end;

class function TAtlasIdeStartProfiles.Team(const AProject: string): TAtlasTeamSettings;
begin
  // ForProject ist leer, wenn die Projektdatei (#486) ausgeschaltet ist.
  Result := TAtlasIdeTeamFile.ForProject(AProject);
end;

/// <summary>Startoptionen des geöffneten AProject für den Ablauf; False, wenn es nicht offen ist.</summary>
function ReadOpen(const AProject: string; out AOptions: TAtlasStartOptions): Boolean;
var
  mProject: IOTAProject;
begin
  AOptions := Default(TAtlasStartOptions);
  mProject := TAtlasIdeStartOptions.FindProject(AProject);
  Result := mProject <> nil;
  if Result then
  begin
    TAtlasIdeStartOptions.ReadOptions(mProject, AOptions);
  end;
end;

/// <summary>Startoptionen von AProject für den Ablauf schreiben; False mit Grund.</summary>
function WriteOpen(const AProject: string; const AOptions: TAtlasStartOptions; out AReason: string): Boolean;
var
  mProject: IOTAProject;
begin
  AReason := '';
  mProject := TAtlasIdeStartOptions.FindProject(AProject);
  if mProject = nil then
  begin
    AReason := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesNotOpen, [ExtractFileName(AProject)]);
    Exit(False);
  end;
  Result := TAtlasIdeStartOptions.WriteOptions(mProject, AOptions, AReason);
end;

class function TAtlasIdeStartProfiles.Flow: TAtlasStartProfileFlow;
var
  mAccess: TAtlasStartProfileAccess;
begin
  if FFlow = nil then
  begin
    mAccess := Default(TAtlasStartProfileAccess);
    mAccess.Folder := TAtlasIdeStartOptions.Folder;
    mAccess.TeamOf := Team;
    mAccess.ReadOptions := ReadOpen;
    mAccess.WriteOptions := WriteOpen;
    FFlow := TAtlasStartProfileFlow.Create(mAccess);
  end;
  Result := FFlow;
end;

class function TAtlasIdeStartProfiles.Failure(const AResult: TAtlasStartProfileResult; const AProject: string): string;
begin
  case AResult.Outcome of
    TAtlasStartProfileOutcome.NotOpen:
      Result := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesNotOpen, [ExtractFileName(AProject)]);
    TAtlasStartProfileOutcome.Unknown:
      Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.StartProfilesUnknown,
        [AResult.Name, ExtractFileName(AProject)]);
    TAtlasStartProfileOutcome.InvalidName:
      Result := TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesInvalidName);
    TAtlasStartProfileOutcome.WriteFailed:
      Result := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesWriteFailed, [AResult.Reason]);
    TAtlasStartProfileOutcome.SaveFailed:
      Result := TAtlasStrings.Text(TAtlasTextId.StartProfilesSaveFailed);
  else
    Result := '';
  end;
end;

class function TAtlasIdeStartProfiles.Summary(const AOptions: TAtlasStartOptions): string;
var
  mParts: TArray<string>;
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
  mNames := TAtlasStartProfilePicker.EnvironmentText(TAtlasStartProfiles.DecodeEnvironment(AOptions.Environment));
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

class procedure TAtlasIdeStartProfiles.SaveCurrent(const AProject: IOTAProject);
var
  mName: string;
  mResult: TAtlasStartProfileResult;
  mReason: string;
begin
  mName := '';
  if not InputQuery(TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesNameTitle),
    TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesNamePrompt), mName) then
  begin
    Exit;
  end;
  mResult := Flow.SaveCurrent(AProject.FileName, mName);
  if not mResult.Succeeded then
  begin
    TAtlasIdeStartOptions.Say(Failure(mResult, AProject.FileName));
    Exit;
  end;
  TAtlasIdeStartOptions.Say(TAtlasBuildStrings.Fmt(TAtlasBuildTextId.StartProfilesSaved, [mResult.Name]));
  // Gleich aktiv: Die Startoptionen bleiben dieselben, gemerkt wird das Profil.
  if not Activate(AProject.FileName, mResult.Name, mReason) then
  begin
    TAtlasIdeStartOptions.Say(mReason);
  end;
end;

class procedure TAtlasIdeStartProfiles.EditPersonal(const AProject: string);
var
  mFileName: string;
  mActions: IOTAActionServices;
begin
  if not Flow.PersonalFile(AProject, mFileName) then
  begin
    TAtlasIdeStartOptions.Say(TAtlasStrings.Text(TAtlasTextId.StartProfilesSaveFailed));
    Exit;
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

function ProfileCommand(const AEntry: TAtlasStartProfileEntry; const AActive: string): TAtlasCommand;
begin
  Result := Default(TAtlasCommand);
  Result.Id := TAtlasStartProfilePicker.ProfileId(AEntry.Profile.Name);
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
  if TAtlasStartProfilePicker.OffersNone(mActive) then
  begin
    Result := Result + [TAtlasIdeStartProfiles.ActionCommand(TAtlasStartProfilePicker.cNoneId,
      TAtlasBuildTextId.StartProfilesNone)];
  end;
  Result := Result + [TAtlasIdeStartProfiles.ActionCommand(TAtlasStartProfilePicker.cSaveId,
    TAtlasBuildTextId.StartProfilesSaveCurrent),
    TAtlasIdeStartProfiles.ActionCommand(TAtlasStartProfilePicker.cEditPersonalId,
    TAtlasBuildTextId.StartProfilesEditPersonal),
    TAtlasIdeStartProfiles.ActionCommand(TAtlasStartProfilePicker.cEditTeamId,
    TAtlasBuildTextId.StartProfilesEditTeam)];
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
  mName: string;
begin
  // Das Projekt kann inzwischen geschlossen sein.
  mCurrent := TAtlasIdeStartOptions.FindProject(AFileName);
  if mCurrent = nil then
  begin
    TAtlasIdeStartOptions.Say(TAtlasStrings.Fmt(TAtlasTextId.StartProfilesNotOpen, [ExtractFileName(AFileName)]));
    Exit;
  end;
  case TAtlasStartProfilePicker.Parse(AId, mName) of
    TAtlasStartProfilePick.NoProfile:
      ActivateOrSay(AFileName, '');
    TAtlasStartProfilePick.SaveCurrent:
      TAtlasIdeStartProfiles.SaveCurrent(mCurrent);
    TAtlasStartProfilePick.EditPersonal:
      TAtlasIdeStartProfiles.EditPersonal(AFileName);
    TAtlasStartProfilePick.EditTeam:
      OpenTeamFile;
    TAtlasStartProfilePick.Profile:
      ActivateOrSay(AFileName, mName);
    TAtlasStartProfilePick.Unknown: ;
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

class function TAtlasIdeStartProfiles.Profiles(const AProject: string): TArray<TAtlasStartProfileEntry>;
begin
  Result := Flow.Profiles(AProject);
end;

class function TAtlasIdeStartProfiles.ActiveName(const AProject: string): string;
begin
  Result := Flow.ActiveName(AProject);
end;

class function TAtlasIdeStartProfiles.Activate(const AProject, AName: string; out AReason: string): Boolean;
var
  mProject: IOTAProject;
  mResult: TAtlasStartProfileResult;
begin
  AReason := '';
  mProject := TAtlasIdeStartOptions.FindProject(AProject);
  if mProject = nil then
  begin
    AReason := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesNotOpen, [ExtractFileName(AProject)]);
    Exit(False);
  end;
  mResult := Flow.Activate(mProject.FileName, AName);
  Result := mResult.Succeeded;
  case mResult.Outcome of
    TAtlasStartProfileOutcome.Applied:
      TAtlasIdeStartOptions.Say(TAtlasBuildStrings.Fmt(TAtlasBuildTextId.StartProfilesApplied,
        [mResult.Name, Summary(mResult.Options)]));
    TAtlasStartProfileOutcome.Restored:
      TAtlasIdeStartOptions.Say(TAtlasBuildStrings.Text(TAtlasBuildTextId.StartProfilesRestored));
  else
    if not Result then
    begin
      AReason := Failure(mResult, mProject.FileName);
    end;
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
  mWindow.ShowOver(TAtlasIdeHost.PopupArea);
end;

class procedure TAtlasIdeStartProfiles.SetStatusHandler(const AValue: TAtlasStartProfileStatus);
begin
  FOnStatus := AValue;
  if FInstance <> nil then
  begin
    FInstance.Check(True);
  end;
end;

initialization

finalization
  FreeAndNil(TAtlasIdeStartProfiles.FFlow);

end.
