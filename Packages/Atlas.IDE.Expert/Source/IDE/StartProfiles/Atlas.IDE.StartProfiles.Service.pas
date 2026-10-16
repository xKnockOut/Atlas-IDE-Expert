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
// - Vorübergehende Startparameter (Test debuggen, #585): RunTemporary merkt
//   die Startoptionen in der lokalen Datei ("temporary"), schreibt die neuen
//   Parameter, macht das Projekt aktiv und löst „Start“ aus; EndTemporary
//   stellt sie zurück. Solange sie gelten, setzt der Zeitgeber das aktive
//   Profil nicht wieder. Bleibt ein Eintrag nach einem Absturz stehen, stellt
//   der Zeitgeber ihn beim nächsten Mal zurück (auch bei ausgeschalteten
//   Startprofilen geht RunTemporary/EndTemporary).
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
  Atlas.UI.Strings;

type
  /// <summary>Text und Tooltip des Statusfelds; AText '' = kein Feld.</summary>
  TAtlasStartProfileStatus = reference to procedure(const AText, AHint: string);

  TAtlasIdeStartProfiles = class
  private class var
    FInstance: TAtlasIdeStartProfiles;
    FOnStatus: TAtlasStartProfileStatus;
    /// <summary>Projekt mit vorübergehenden Startparametern (#585); '' ohne.</summary>
    FTemporary: string;
  private
    FTimer: TTimer;
    FStamp: string;
    procedure Tick(Sender: TObject);
    procedure Check(AForce: Boolean);
    procedure Publish(const AProject: string);
    class function Folder: string; static;
    class function FindProject(const AFileName: string): IOTAProject; static;
    class function ActiveProject: IOTAProject; static;
    class function BuildConfiguration(const AProject: IOTAProject): IOTABuildConfiguration; static;
    class function ReadOptions(const AProject: IOTAProject; out AOptions: TAtlasStartOptions): Boolean; static;
    class function WriteOptions(const AProject: IOTAProject; const AOptions: TAtlasStartOptions;
      out AReason: string): Boolean; static;
    class function Team(const AProject: string): TAtlasTeamSettings; static;
    class procedure Say(const AText: string); static;
    class function Debugging: Boolean; static;
    class function Summary(const AOptions: TAtlasStartOptions): string; static;
    class function Describe(const AEntry: TAtlasStartProfileEntry): string; static;
    class procedure SaveCurrent(const AProject: IOTAProject); static;
    class procedure EditPersonal(const AProject: string); static;
    class function ActionCommand(const AId: string; ATextId: TAtlasTextId): TAtlasCommand; static;
    /// <summary>„Start“ (ADebugger) bzw. „Ohne Debugger starten“ der IDE auslösen; False mit Grund.</summary>
    class function ExecuteRun(ADebugger: Boolean; out AReason: string): Boolean; static;
    /// <summary>Offenen Eintrag "temporary" von AProject zurückstellen (nach einem Absturz); True, wenn einer offen
    /// war.</summary>
    class function RecoverTemporary(const AProject: IOTAProject): Boolean; static;
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
    /// <summary>Für „Test debuggen“ (#585): Parameter vorübergehend auf AParameters(bisherige Parameter) setzen
    /// (Arbeitsordner, Host und Umgebung bleiben), AProject aktiv machen und „Start“ bzw. „Ohne Debugger starten“
    /// auslösen. Das Projekt muss geöffnet sein; der Debugger darf nicht laufen. Scheitert der Start, stellt es die
    /// Parameter gleich zurück. False mit Grund.</summary>
    class function RunTemporary(const AProject: string; const AParameters: TFunc<string, string>;
      ADebugger: Boolean; out AReason: string): Boolean; static;
    /// <summary>Vorübergehende Parameter von AProject zurückstellen. AChanged: Jemand hat sie während des Laufs
    /// geändert, sie bleiben. False, wenn das Projekt nicht offen ist oder Schreiben scheitert.</summary>
    class function EndTemporary(const AProject: string; out AChanged: Boolean): Boolean; static;
    /// <summary>Auswahl für das aktive Projekt öffnen (Befehl und Statusfeld).</summary>
    class procedure ShowPicker; static;
    /// <summary>Empfänger für Text und Tooltip des Statusfelds nach jeder Änderung; nil = keiner. Meldet sofort,
    /// wenn das Feature läuft.</summary>
    class procedure SetStatusHandler(const AValue: TAtlasStartProfileStatus); static;
  end;

implementation

uses
  System.IOUtils,
  System.Types,
  System.Actions,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.ActnList,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.UI.Commands.Palette;

const
  CheckMs = 1000;
  MessageGroup = 'Atlas';
  RunAction = 'RunRunCommand';
  RunNoDebugAction = 'RunRunNoDebugCommand';
  // Einträge der Auswahl, die kein Profil sind.
  NoneId = 'atlas:none';
  SaveId = 'atlas:save';
  EditPersonalId = 'atlas:personal';
  EditTeamId = 'atlas:team';
  ProfilePrefix = 'profile:';

{ TAtlasIdeStartProfiles }

constructor TAtlasIdeStartProfiles.Create;
begin
  inherited Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := CheckMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeStartProfiles.Destroy;
begin
  FTimer.Free;
  if Assigned(FOnStatus) then
    FOnStatus('', '');
  inherited Destroy;
end;

class function TAtlasIdeStartProfiles.Folder: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    TAtlasStartProfiles.FolderName);
end;

class procedure TAtlasIdeStartProfiles.Say(const AText: string);
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Group := Messages.GetGroup(MessageGroup);
  if Group = nil then
    Group := Messages.AddMessageGroup(MessageGroup);
  Messages.AddTitleMessage(AText, Group);
end;

class function TAtlasIdeStartProfiles.Debugging: Boolean;
var
  Debugger: IOTADebuggerServices;
begin
  Result := Supports(BorlandIDEServices, IOTADebuggerServices, Debugger) and (Debugger.ProcessCount > 0);
end;

class function TAtlasIdeStartProfiles.FindProject(const AFileName: string): IOTAProject;
var
  Services: IOTAModuleServices;
begin
  Result := nil;
  if (AFileName <> '') and Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Supports(Services.FindModule(AFileName), IOTAProject, Result);
end;

class function TAtlasIdeStartProfiles.ActiveProject: IOTAProject;
var
  Services: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Result := Services.GetActiveProject;
  // Nur gespeicherte .dproj: Die lokale Datei hängt am Pfad.
  if (Result <> nil) and not SameText(ExtractFileExt(Result.FileName), '.dproj') then
    Result := nil;
end;

class function TAtlasIdeStartProfiles.BuildConfiguration(const AProject: IOTAProject): IOTABuildConfiguration;
var
  Configurations: IOTAProjectOptionsConfigurations;
  Platformed: IOTABuildConfiguration;
begin
  Result := nil;
  if (AProject = nil) or not Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations,
    Configurations) then
    Exit;
  Result := Configurations.ActiveConfiguration;
  if (Result = nil) or (AProject.CurrentPlatform = '') then
    Exit;
  // Die IDE legt die Startoptionen je Konfiguration und Plattform ab (Cfg_1_Win32).
  Platformed := Result.PlatformConfiguration[AProject.CurrentPlatform];
  if Platformed <> nil then
    Result := Platformed;
end;

class function TAtlasIdeStartProfiles.ReadOptions(const AProject: IOTAProject;
  out AOptions: TAtlasStartOptions): Boolean;
var
  Build: IOTABuildConfiguration;
begin
  AOptions := Default(TAtlasStartOptions);
  Result := False;
  try
    Build := BuildConfiguration(AProject);
    if Build = nil then
      Exit;
    // Roh, ohne geerbte Werte: genau das, was „Kein Startprofil“ zurückschreibt.
    AOptions.Parameters := Build.GetValue(TAtlasStartProfiles.ParametersOption, False);
    AOptions.WorkingDir := Build.GetValue(TAtlasStartProfiles.WorkingDirOption, False);
    AOptions.Host := Build.GetValue(TAtlasStartProfiles.HostOption, False);
    AOptions.Environment := Build.GetValue(TAtlasStartProfiles.EnvironmentOption, False);
    Result := True;
  except
    on Exception do
      Result := False;
  end;
end;

class function TAtlasIdeStartProfiles.WriteOptions(const AProject: IOTAProject; const AOptions: TAtlasStartOptions;
  out AReason: string): Boolean;
var
  Build: IOTABuildConfiguration;
  Current: TAtlasStartOptions;
begin
  AReason := '';
  Result := False;
  try
    Build := BuildConfiguration(AProject);
    if Build = nil then
    begin
      AReason := ExtractFileName(AProject.FileName);
      Exit;
    end;
    // Nur bei Abweichung schreiben: Sonst gälte das Projekt bei jedem Wechsel als geändert.
    if ReadOptions(AProject, Current) and Current.SameAs(AOptions) then
      Exit(True);
    Build.SetValue(TAtlasStartProfiles.ParametersOption, AOptions.Parameters);
    Build.SetValue(TAtlasStartProfiles.WorkingDirOption, AOptions.WorkingDir);
    Build.SetValue(TAtlasStartProfiles.HostOption, AOptions.Host);
    Build.SetValue(TAtlasStartProfiles.EnvironmentOption, AOptions.Environment);
    Result := True;
  except
    on E: Exception do
      AReason := E.Message;
  end;
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
    Exit;
  Result := TAtlasStartProfiles.ForProject(Folder, AProject, Team(AProject));
end;

class function TAtlasIdeStartProfiles.ActiveName(const AProject: string): string;
begin
  Result := '';
  if AProject <> '' then
    Result := TAtlasStartProfiles.Load(Folder, AProject).Active;
end;

class function TAtlasIdeStartProfiles.Summary(const AOptions: TAtlasStartOptions): string;
var
  Parts: TArray<string>;
  Variable: TAtlasTeamVariable;
  Names: string;
begin
  Parts := nil;
  if AOptions.Parameters <> '' then
    Parts := Parts + [TAtlasStrings.Fmt(TAtlasTextId.StartProfilesParameters, [AOptions.Parameters])]
  else
    Parts := Parts + [TAtlasStrings.Text(TAtlasTextId.StartProfilesNoOptions)];
  if AOptions.WorkingDir <> '' then
    Parts := Parts + [TAtlasStrings.Fmt(TAtlasTextId.StartProfilesWorkingDir, [AOptions.WorkingDir])];
  if AOptions.Host <> '' then
    Parts := Parts + [TAtlasStrings.Fmt(TAtlasTextId.StartProfilesHost, [AOptions.Host])];
  Names := '';
  for Variable in TAtlasStartProfiles.DecodeEnvironment(AOptions.Environment) do
  begin
    if Names <> '' then
      Names := Names + ', ';
    Names := Names + Variable.Name + '=' + Variable.Value;
  end;
  if Names <> '' then
    Parts := Parts + [TAtlasStrings.Fmt(TAtlasTextId.StartProfilesEnvironment, [Names])];
  Result := string.Join(' · ', Parts);
end;

class function TAtlasIdeStartProfiles.Describe(const AEntry: TAtlasStartProfileEntry): string;
begin
  Result := Summary(TAtlasStartProfiles.OptionsOf(AEntry));
end;

class function TAtlasIdeStartProfiles.Activate(const AProject, AName: string; out AReason: string): Boolean;
var
  Project: IOTAProject;
  State: TAtlasStartProfileState;
  Entry: TAtlasStartProfileEntry;
  Current, Options: TAtlasStartOptions;
begin
  AReason := '';
  Result := False;
  Project := FindProject(AProject);
  if Project = nil then
  begin
    AReason := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesNotOpen, [ExtractFileName(AProject)]);
    Exit;
  end;
  State := TAtlasStartProfiles.Load(Folder, Project.FileName);
  ReadOptions(Project, Current);
  if Trim(AName) = '' then
  begin
    // Kein Profil: die gemerkten Startoptionen zurück; ohne gemerkte bleiben die jetzigen.
    if TAtlasStartProfiles.Deactivate(State, Options) and not WriteOptions(Project, Options, AReason) then
    begin
      AReason := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesWriteFailed, [AReason]);
      Exit;
    end;
    if not TAtlasStartProfiles.Save(Folder, State) then
    begin
      AReason := TAtlasStrings.Text(TAtlasTextId.StartProfilesSaveFailed);
      Exit;
    end;
    Say(TAtlasStrings.Text(TAtlasTextId.StartProfilesRestored));
  end
  else
  begin
    if not TAtlasStartProfiles.Find(TAtlasStartProfiles.Merge(Team(Project.FileName), State), AName, Entry) then
    begin
      AReason := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesUnknown, [AName, ExtractFileName(Project.FileName)]);
      Exit;
    end;
    Options := TAtlasStartProfiles.OptionsOf(Entry);
    // Erst merken, was vorher galt, dann schreiben: Scheitert das Schreiben, bleibt der alte Stand.
    TAtlasStartProfiles.Activate(State, Entry.Profile.Name, Current);
    if not WriteOptions(Project, Options, AReason) then
    begin
      AReason := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesWriteFailed, [AReason]);
      Exit;
    end;
    if not TAtlasStartProfiles.Save(Folder, State) then
    begin
      AReason := TAtlasStrings.Text(TAtlasTextId.StartProfilesSaveFailed);
      Exit;
    end;
    Say(TAtlasStrings.Fmt(TAtlasTextId.StartProfilesApplied, [Entry.Profile.Name, Summary(Options)]));
  end;
  Result := True;
  if FInstance <> nil then
    FInstance.Check(True);
end;

class function TAtlasIdeStartProfiles.Run(const AProject, AName: string; ADebugger: Boolean;
  out AReason: string): Boolean;
var
  Services: IOTAModuleServices;
  Project: IOTAProject;
begin
  Result := False;
  AReason := '';
  if Debugging then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.StartProfilesDebuggerRunning);
    Exit;
  end;
  Project := FindProject(AProject);
  if Project = nil then
  begin
    AReason := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesNotOpen, [ExtractFileName(AProject)]);
    Exit;
  end;
  // „Start“ der IDE startet das aktive Projekt.
  if Supports(BorlandIDEServices, IOTAModuleServices, Services) and (Services.MainProjectGroup <> nil) and
    (Services.MainProjectGroup.ActiveProject <> Project) then
    Services.MainProjectGroup.ActiveProject := Project;
  if not Activate(Project.FileName, AName, AReason) then
    Exit;
  Result := ExecuteRun(ADebugger, AReason);
end;

class function TAtlasIdeStartProfiles.ExecuteRun(ADebugger: Boolean; out AReason: string): Boolean;
var
  Actions: INTAServices;
  Index: Integer;
  Name: string;
  Action: TContainedAction;
begin
  AReason := '';
  if ADebugger then
    Name := RunAction
  else
    Name := RunNoDebugAction;
  if Supports(BorlandIDEServices, INTAServices, Actions) and (Actions.ActionList <> nil) then
    for Index := 0 to Actions.ActionList.ActionCount - 1 do
    begin
      Action := Actions.ActionList.Actions[Index];
      if not SameText(Action.Name, Name) then
        Continue;
      Action.Update;
      if (Action is TCustomAction) and not TCustomAction(Action).Enabled then
        Break;
      Action.Execute;
      Exit(True);
    end;
  AReason := TAtlasStrings.Text(TAtlasTextId.StartProfilesNoRunAction);
  Result := False;
end;

class function TAtlasIdeStartProfiles.RunTemporary(const AProject: string; const AParameters: TFunc<string, string>;
  ADebugger: Boolean; out AReason: string): Boolean;
var
  Services: IOTAModuleServices;
  Project: IOTAProject;
  State: TAtlasStartProfileState;
  Current, Options: TAtlasStartOptions;
  Changed: Boolean;
begin
  Result := False;
  AReason := '';
  if Debugging then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.StartProfilesDebuggerRunning);
    Exit;
  end;
  Project := FindProject(AProject);
  if Project = nil then
  begin
    AReason := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesNotOpen, [ExtractFileName(AProject)]);
    Exit;
  end;
  // „Start“ der IDE startet das aktive Projekt; die Startoptionen gelten für dessen Konfiguration und Plattform.
  if Supports(BorlandIDEServices, IOTAModuleServices, Services) and (Services.MainProjectGroup <> nil) and
    (Services.MainProjectGroup.ActiveProject <> Project) then
    Services.MainProjectGroup.ActiveProject := Project;
  // Ein Eintrag von einem abgebrochenen Lauf zuerst zurückstellen, sonst gälten danach dessen Parameter.
  RecoverTemporary(Project);
  if not ReadOptions(Project, Current) then
  begin
    AReason := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesWriteFailed, [ExtractFileName(Project.FileName)]);
    Exit;
  end;
  Options := TAtlasStartProfiles.TemporaryOptions(Current, AParameters(Current.Parameters));
  // Erst merken (übersteht einen Absturz), dann schreiben.
  State := TAtlasStartProfiles.Load(Folder, Project.FileName);
  TAtlasStartProfiles.BeginTemporary(State, Current, Options.Parameters);
  if not TAtlasStartProfiles.Save(Folder, State) then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.StartProfilesSaveFailed);
    Exit;
  end;
  FTemporary := Project.FileName;
  if not WriteOptions(Project, Options, AReason) then
  begin
    AReason := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesWriteFailed, [AReason]);
    EndTemporary(Project.FileName, Changed);
    Exit;
  end;
  if not ExecuteRun(ADebugger, AReason) then
  begin
    EndTemporary(Project.FileName, Changed);
    Exit;
  end;
  Result := True;
end;

class function TAtlasIdeStartProfiles.EndTemporary(const AProject: string; out AChanged: Boolean): Boolean;
var
  Project: IOTAProject;
  State: TAtlasStartProfileState;
  Current, Before: TAtlasStartOptions;
  Reason: string;
begin
  AChanged := False;
  Result := False;
  if SameText(FTemporary, AProject) then
    FTemporary := '';
  Project := FindProject(AProject);
  if Project = nil then
    Exit;
  State := TAtlasStartProfiles.Load(Folder, Project.FileName);
  if not State.HasTemporary then
    Exit(True);
  ReadOptions(Project, Current);
  if TAtlasStartProfiles.EndTemporary(State, Current, Before) then
  begin
    if not WriteOptions(Project, Before, Reason) then
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.StartProfilesWriteFailed, [Reason]));
      Exit;
    end;
  end
  else
    AChanged := True;
  Result := TAtlasStartProfiles.Save(Folder, State);
  if FInstance <> nil then
    FInstance.Check(True);
end;

class function TAtlasIdeStartProfiles.RecoverTemporary(const AProject: IOTAProject): Boolean;
var
  State: TAtlasStartProfileState;
  Changed: Boolean;
begin
  Result := False;
  if (AProject = nil) or SameText(FTemporary, AProject.FileName) or Debugging then
    Exit;
  State := TAtlasStartProfiles.Load(Folder, AProject.FileName);
  if not State.HasTemporary then
    Exit;
  Result := True;
  if EndTemporary(AProject.FileName, Changed) and not Changed then
    Say(TAtlasStrings.Fmt(TAtlasTextId.StartProfilesTemporaryRestored, [ExtractFileName(AProject.FileName)]));
end;

class procedure TAtlasIdeStartProfiles.SaveCurrent(const AProject: IOTAProject);
var
  Name: string;
  Options: TAtlasStartOptions;
  State: TAtlasStartProfileState;
  Reason: string;
begin
  Name := '';
  if not InputQuery(TAtlasStrings.Text(TAtlasTextId.StartProfilesNameTitle),
    TAtlasStrings.Text(TAtlasTextId.StartProfilesNamePrompt), Name) then
    Exit;
  if Trim(Name) = '' then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.StartProfilesInvalidName));
    Exit;
  end;
  ReadOptions(AProject, Options);
  State := TAtlasStartProfiles.Load(Folder, AProject.FileName);
  TAtlasStartProfiles.PutPersonal(State, TAtlasStartProfiles.ProfileFromOptions(Name, Options));
  if not TAtlasStartProfiles.Save(Folder, State) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.StartProfilesSaveFailed));
    Exit;
  end;
  Say(TAtlasStrings.Fmt(TAtlasTextId.StartProfilesSaved, [Trim(Name)]));
  // Gleich aktiv: Die Startoptionen bleiben dieselben, gemerkt wird das Profil.
  if not Activate(AProject.FileName, Trim(Name), Reason) then
    Say(Reason);
end;

class procedure TAtlasIdeStartProfiles.EditPersonal(const AProject: string);
var
  FileName: string;
  State: TAtlasStartProfileState;
  Actions: IOTAActionServices;
begin
  FileName := TAtlasStartProfiles.FileFor(Folder, AProject);
  if not FileExists(FileName) then
  begin
    State := TAtlasStartProfiles.Empty(AProject);
    if not TAtlasStartProfiles.Save(Folder, State) then
    begin
      Say(TAtlasStrings.Text(TAtlasTextId.StartProfilesSaveFailed));
      Exit;
    end;
  end;
  if Supports(BorlandIDEServices, IOTAActionServices, Actions) then
    Actions.OpenFile(FileName);
end;

class function TAtlasIdeStartProfiles.ActionCommand(const AId: string; ATextId: TAtlasTextId): TAtlasCommand;
begin
  Result := Default(TAtlasCommand);
  Result.Id := AId;
  Result.Caption := TAtlasStrings.Text(ATextId);
  Result.Path := TAtlasStrings.Text(TAtlasTextId.StartProfilesActions);
end;

class procedure TAtlasIdeStartProfiles.ShowPicker;
var
  Project: IOTAProject;
  FileName, Active: string;
  Entries: TArray<TAtlasStartProfileEntry>;
  Entry: TAtlasStartProfileEntry;
  Commands: TArray<TAtlasCommand>;
  Command: TAtlasCommand;
  Window: TAtlasPaletteWindow;
  Area: TRect;
begin
  Project := ActiveProject;
  if Project = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.StartProfilesNoProject));
    Exit;
  end;
  FileName := Project.FileName;
  Entries := Profiles(FileName);
  Active := ActiveName(FileName);
  Commands := nil;
  for Entry in Entries do
  begin
    Command := Default(TAtlasCommand);
    Command.Id := ProfilePrefix + Entry.Profile.Name;
    Command.Caption := Entry.Profile.Name;
    if Entry.Source = TAtlasStartProfileSource.Team then
      Command.Path := TAtlasStrings.Text(TAtlasTextId.StartProfilesTeam)
    else
      Command.Path := TAtlasStrings.Text(TAtlasTextId.StartProfilesPersonal);
    if SameText(Entry.Profile.Name, Active) then
      Command.ShortCut := TAtlasStrings.Text(TAtlasTextId.StartProfilesActiveMark);
    Command.Description := Describe(Entry);
    Commands := Commands + [Command];
  end;
  if Active <> '' then
    Commands := Commands + [ActionCommand(NoneId, TAtlasTextId.StartProfilesNone)];
  Commands := Commands + [ActionCommand(SaveId, TAtlasTextId.StartProfilesSaveCurrent),
    ActionCommand(EditPersonalId, TAtlasTextId.StartProfilesEditPersonal),
    ActionCommand(EditTeamId, TAtlasTextId.StartProfilesEditTeam)];
  Window := TAtlasPaletteWindow.CreatePalette(Application, Commands, nil, TAtlasIdeStyle.Colors);
  Window.KeepOrder := True;
  Window.OnExecute :=
    procedure(ACommand: TAtlasCommand)
    var
      Id: string;
    begin
      Id := ACommand.Id;
      TAtlasGuard.Run(TAtlasFeature.Build,
        procedure
        var
          Reason: string;
          Current: IOTAProject;
        begin
          // Das Projekt kann inzwischen geschlossen sein.
          Current := FindProject(FileName);
          if Current = nil then
          begin
            Say(TAtlasStrings.Fmt(TAtlasTextId.StartProfilesNotOpen, [ExtractFileName(FileName)]));
            Exit;
          end;
          if Id = NoneId then
          begin
            if not Activate(FileName, '', Reason) then
              Say(Reason);
          end
          else if Id = SaveId then
            SaveCurrent(Current)
          else if Id = EditPersonalId then
            EditPersonal(FileName)
          else if Id = EditTeamId then
          begin
            if TAtlasIdeSettings.Current.TeamFile then
              TAtlasIdeTeamFile.OpenInEditor
            else
              Say(TAtlasStrings.Text(TAtlasTextId.StartProfilesTeamOff));
          end
          else if Copy(Id, 1, Length(ProfilePrefix)) = ProfilePrefix then
          begin
            if not Activate(FileName, Copy(Id, Length(ProfilePrefix) + 1, MaxInt), Reason) then
              Say(Reason);
          end;
        end);
    end;
  if Screen.ActiveForm <> nil then
    Area := Screen.ActiveForm.BoundsRect
  else if Application.MainForm <> nil then
    Area := Application.MainForm.BoundsRect
  else
    Area := Screen.WorkAreaRect;
  Window.ShowOver(Area);
end;

procedure TAtlasIdeStartProfiles.Publish(const AProject: string);
var
  Entries: TArray<TAtlasStartProfileEntry>;
  Entry: TAtlasStartProfileEntry;
  Active, Text, Hint: string;
begin
  if not Assigned(FOnStatus) then
    Exit;
  Text := '';
  Hint := '';
  if AProject <> '' then
  begin
    Entries := Profiles(AProject);
    Active := ActiveName(AProject);
    if Active = '' then
    begin
      // Ohne Profile kein Feld; mit Profilen zeigt es „–“.
      if Length(Entries) > 0 then
      begin
        Text := TAtlasStrings.Text(TAtlasTextId.StartProfilesStatusNone);
        Hint := TAtlasStrings.Text(TAtlasTextId.StartProfilesHintNone);
      end;
    end
    else if TAtlasStartProfiles.Find(Entries, Active, Entry) then
    begin
      Text := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesStatus, [Entry.Profile.Name]);
      Hint := Describe(Entry);
    end
    else
    begin
      Text := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesStatusMissing, [Active]);
      Hint := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesHintMissing, [Active]);
    end;
    if Text <> '' then
      Hint := Hint + sLineBreak + TAtlasStrings.Text(TAtlasTextId.StartProfilesHintClick);
  end;
  FOnStatus(Text, Hint);
end;

procedure TAtlasIdeStartProfiles.Check(AForce: Boolean);
var
  Project: IOTAProject;
  FileName, Personal, Stamp, Active, Reason: string;
  TeamSettings: TAtlasTeamSettings;
  Age: TDateTime;
  Entry: TAtlasStartProfileEntry;
begin
  Project := ActiveProject;
  FileName := '';
  Stamp := '';
  if Project <> nil then
  begin
    FileName := Project.FileName;
    TeamSettings := Team(FileName);
    Personal := TAtlasStartProfiles.FileFor(Folder, FileName);
    Stamp := FileName + '|' + Project.CurrentConfiguration + '|' + Project.CurrentPlatform + '|' + TeamSettings.FileName;
    if (TeamSettings.FileName <> '') and FileAge(TeamSettings.FileName, Age) then
      Stamp := Stamp + '|' + FloatToStr(Age);
    if FileAge(Personal, Age) then
      Stamp := Stamp + '|' + FloatToStr(Age);
  end;
  if not AForce and (Stamp = FStamp) then
    Exit;
  FStamp := Stamp;
  // Gemerktes Profil für Projekt, Konfiguration und Plattform (wieder) setzen, wenn die Startoptionen abweichen;
  // nicht, solange vorübergehende Parameter gelten (#585). Ein liegengebliebener Eintrag wird zurückgestellt.
  if (Project <> nil) and not SameText(FTemporary, FileName) then
  begin
    RecoverTemporary(Project);
    Active := ActiveName(FileName);
    if (Active <> '') and TAtlasStartProfiles.Find(Profiles(FileName), Active, Entry) and
      not WriteOptions(Project, TAtlasStartProfiles.OptionsOf(Entry), Reason) then
      Say(TAtlasStrings.Fmt(TAtlasTextId.StartProfilesWriteFailed, [Reason]));
  end;
  Publish(FileName);
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
    Exit;
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
    FInstance.Check(True);
end;

class procedure TAtlasIdeStartProfiles.SetStatusHandler(const AValue: TAtlasStartProfileStatus);
begin
  FOnStatus := AValue;
  if FInstance <> nil then
    FInstance.Check(True);
end;

end.
