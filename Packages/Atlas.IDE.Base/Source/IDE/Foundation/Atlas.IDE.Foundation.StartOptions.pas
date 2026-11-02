unit Atlas.IDE.Foundation.StartOptions;

// Startoptionen eines Projekts in der IDE (#575, #585, #1455): Base kapselt
// das Lesen und Schreiben von Parametern, Arbeitsordner, Host-Anwendung und
// Umgebung der aktiven Konfiguration für die aktive Plattform (wie Start ›
// Parameter, #396) und das Auslösen von „Start“ bzw. „Ohne Debugger
// starten“. Zwei Module nutzen das: die Startprofile (Modul Build, #575) und
// „Test debuggen“ (Modul Tests, #585). Deshalb liegt es in Base und nicht in
// einem der beiden; ein Modul kennt das andere nicht (ADR 0017 Regel 9).
// - Vorübergehende Startparameter (Test debuggen, #585): RunTemporary merkt
//   die Startoptionen in der lokalen Datei der Startprofile ("temporary"),
//   schreibt die neuen Parameter, macht das Projekt aktiv und löst „Start“
//   aus; EndTemporary stellt sie zurück. Solange sie gelten
//   (TemporaryProject), setzen die Startprofile das aktive Profil nicht
//   wieder. Bleibt ein Eintrag nach einem Absturz stehen, stellt
//   RecoverTemporary ihn zurück. Das geht auch ohne Startprofile.
// - Meldungen in der Meldungsansicht (Gruppe Atlas), nie als Dialog; das
//   Protokoll bekommt keine Parameter oder Pfade.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.StartProfiles.Store;

type
  TAtlasIdeStartOptions = class
  private class var
    /// <summary>Projekt mit vorübergehenden Startparametern (#585); '' ohne.</summary>
    FTemporary: string;
  private
    class function BuildConfiguration(const AProject: IOTAProject): IOTABuildConfiguration; static;
  public
    /// <summary>Ordner der lokalen Datei der Startprofile (je Projekt eine).</summary>
    class function Folder: string; static;
    /// <summary>Meldung in der Meldungsansicht, Gruppe Atlas.</summary>
    class procedure Say(const AText: string); static;
    /// <summary>Läuft ein Prozess im Debugger?</summary>
    class function Debugging: Boolean; static;
    /// <summary>Geöffnetes Projekt AFileName; nil, wenn es nicht offen ist.</summary>
    class function FindProject(const AFileName: string): IOTAProject; static;
    /// <summary>Aktives Projekt, nur gespeicherte .dproj (die lokale Datei hängt am Pfad); sonst nil.</summary>
    class function ActiveProject: IOTAProject; static;
    /// <summary>AProject zum aktiven Projekt der Gruppe machen („Start“ startet das aktive Projekt).</summary>
    class procedure MakeActive(const AProject: IOTAProject); static;
    /// <summary>Startoptionen roh, ohne geerbte Werte; False, wenn die Konfiguration fehlt.</summary>
    class function ReadOptions(const AProject: IOTAProject; out AOptions: TAtlasStartOptions): Boolean; static;
    /// <summary>Startoptionen schreiben, nur bei Abweichung (sonst gälte das Projekt bei jedem Wechsel als
    /// geändert). False mit Grund.</summary>
    class function WriteOptions(const AProject: IOTAProject; const AOptions: TAtlasStartOptions;
      out AReason: string): Boolean; static;
    /// <summary>„Start“ (ADebugger) bzw. „Ohne Debugger starten“ der IDE auslösen; False mit Grund.</summary>
    class function Execute(ADebugger: Boolean; out AReason: string): Boolean; static;
    /// <summary>Für „Test debuggen“ (#585): Parameter vorübergehend auf AParameters(bisherige Parameter) setzen
    /// (Arbeitsordner, Host und Umgebung bleiben), AProject aktiv machen und „Start“ bzw. „Ohne Debugger
    /// starten“ auslösen. Das Projekt muss geöffnet sein; der Debugger darf nicht laufen. Scheitert der Start,
    /// stellt es die Parameter gleich zurück. False mit Grund.</summary>
    class function RunTemporary(const AProject: string; const AParameters: TFunc<string, string>;
      ADebugger: Boolean; out AReason: string): Boolean; static;
    /// <summary>Vorübergehende Parameter von AProject zurückstellen. AChanged: Jemand hat sie während des Laufs
    /// geändert, sie bleiben. False, wenn das Projekt nicht offen ist oder Schreiben scheitert.</summary>
    class function EndTemporary(const AProject: string; out AChanged: Boolean): Boolean; static;
    /// <summary>Offenen Eintrag "temporary" von AProject zurückstellen (nach einem Absturz); True, wenn einer offen
    /// war. Nichts, solange der Lauf noch gilt oder der Debugger läuft.</summary>
    class function RecoverTemporary(const AProject: IOTAProject): Boolean; static;
    /// <summary>Projekt, dessen vorübergehende Parameter gerade gelten; '' ohne.</summary>
    class function TemporaryProject: string; static;
  end;

implementation

uses
  System.IOUtils,
  System.Classes,
  System.Actions,
  Vcl.ActnList,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Host;

const
  RunAction = 'RunRunCommand';
  RunNoDebugAction = 'RunRunNoDebugCommand';

{ TAtlasIdeStartOptions }

class function TAtlasIdeStartOptions.Folder: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    TAtlasStartProfiles.FolderName);
end;

class procedure TAtlasIdeStartOptions.Say(const AText: string);
begin
  TAtlasIdeHost.Message(AText);
end;

class function TAtlasIdeStartOptions.Debugging: Boolean;
var
  mDebugger: IOTADebuggerServices;
begin
  Result := Supports(BorlandIDEServices, IOTADebuggerServices, mDebugger) and (mDebugger.ProcessCount > 0);
end;

class function TAtlasIdeStartOptions.FindProject(const AFileName: string): IOTAProject;
var
  mServices: IOTAModuleServices;
begin
  Result := nil;
  if (AFileName <> '') and Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
    Supports(mServices.FindModule(AFileName), IOTAProject, Result);
end;

class function TAtlasIdeStartOptions.ActiveProject: IOTAProject;
var
  mServices: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
    Result := mServices.GetActiveProject;
  if (Result <> nil) and not SameText(ExtractFileExt(Result.FileName), '.dproj') then
    Result := nil;
end;

class procedure TAtlasIdeStartOptions.MakeActive(const AProject: IOTAProject);
var
  mServices: IOTAModuleServices;
begin
  if (AProject <> nil) and Supports(BorlandIDEServices, IOTAModuleServices, mServices) and
    (mServices.MainProjectGroup <> nil) and (mServices.MainProjectGroup.ActiveProject <> AProject) then
    mServices.MainProjectGroup.ActiveProject := AProject;
end;

class function TAtlasIdeStartOptions.BuildConfiguration(const AProject: IOTAProject): IOTABuildConfiguration;
var
  mConfigurations: IOTAProjectOptionsConfigurations;
  mPlatformed: IOTABuildConfiguration;
begin
  Result := nil;
  if (AProject = nil) or not Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations,
    mConfigurations) then
    Exit;
  Result := mConfigurations.ActiveConfiguration;
  if (Result = nil) or (AProject.CurrentPlatform = '') then
    Exit;
  // Die IDE legt die Startoptionen je Konfiguration und Plattform ab (Cfg_1_Win32).
  mPlatformed := Result.PlatformConfiguration[AProject.CurrentPlatform];
  if mPlatformed <> nil then
    Result := mPlatformed;
end;

class function TAtlasIdeStartOptions.ReadOptions(const AProject: IOTAProject;
  out AOptions: TAtlasStartOptions): Boolean;
var
  mBuild: IOTABuildConfiguration;
begin
  AOptions := Default(TAtlasStartOptions);
  Result := False;
  try
    mBuild := BuildConfiguration(AProject);
    if mBuild = nil then
      Exit;
    // Roh, ohne geerbte Werte: genau das, was „Kein Startprofil“ zurückschreibt.
    AOptions.Parameters := mBuild.GetValue(TAtlasStartProfiles.ParametersOption, False);
    AOptions.WorkingDir := mBuild.GetValue(TAtlasStartProfiles.WorkingDirOption, False);
    AOptions.Host := mBuild.GetValue(TAtlasStartProfiles.HostOption, False);
    AOptions.Environment := mBuild.GetValue(TAtlasStartProfiles.EnvironmentOption, False);
    Result := True;
  except
    on Exception do
      Result := False;
  end;
end;

class function TAtlasIdeStartOptions.WriteOptions(const AProject: IOTAProject; const AOptions: TAtlasStartOptions;
  out AReason: string): Boolean;
var
  mBuild: IOTABuildConfiguration;
  mCurrent: TAtlasStartOptions;
begin
  AReason := '';
  Result := False;
  try
    mBuild := BuildConfiguration(AProject);
    if mBuild = nil then
    begin
      AReason := ExtractFileName(AProject.FileName);
      Exit;
    end;
    if ReadOptions(AProject, mCurrent) and mCurrent.SameAs(AOptions) then
      Exit(True);
    mBuild.SetValue(TAtlasStartProfiles.ParametersOption, AOptions.Parameters);
    mBuild.SetValue(TAtlasStartProfiles.WorkingDirOption, AOptions.WorkingDir);
    mBuild.SetValue(TAtlasStartProfiles.HostOption, AOptions.Host);
    mBuild.SetValue(TAtlasStartProfiles.EnvironmentOption, AOptions.Environment);
    Result := True;
  except
    on E: Exception do
      AReason := E.Message;
  end;
end;

class function TAtlasIdeStartOptions.Execute(ADebugger: Boolean; out AReason: string): Boolean;
var
  mActions: INTAServices;
  mIndex: Integer;
  mName: string;
  mAction: TContainedAction;
begin
  AReason := '';
  if ADebugger then
    mName := RunAction
  else
    mName := RunNoDebugAction;
  if Supports(BorlandIDEServices, INTAServices, mActions) and (mActions.ActionList <> nil) then
    for mIndex := 0 to mActions.ActionList.ActionCount - 1 do
    begin
      mAction := mActions.ActionList.Actions[mIndex];
      if not SameText(mAction.Name, mName) then
        Continue;
      mAction.Update;
      if (mAction is TCustomAction) and not TCustomAction(mAction).Enabled then
        Break;
      mAction.Execute;
      Exit(True);
    end;
  AReason := TAtlasStrings.Text(TAtlasTextId.StartProfilesNoRunAction);
  Result := False;
end;

class function TAtlasIdeStartOptions.RunTemporary(const AProject: string; const AParameters: TFunc<string, string>;
  ADebugger: Boolean; out AReason: string): Boolean;
var
  mProject: IOTAProject;
  mState: TAtlasStartProfileState;
  mCurrent, mOptions: TAtlasStartOptions;
  mChanged: Boolean;
begin
  Result := False;
  AReason := '';
  if Debugging then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.StartProfilesDebuggerRunning);
    Exit;
  end;
  mProject := FindProject(AProject);
  if mProject = nil then
  begin
    AReason := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesNotOpen, [ExtractFileName(AProject)]);
    Exit;
  end;
  // „Start“ der IDE startet das aktive Projekt; die Startoptionen gelten für dessen Konfiguration und Plattform.
  MakeActive(mProject);
  // Ein Eintrag von einem abgebrochenen Lauf zuerst zurückstellen, sonst gälten danach dessen Parameter.
  RecoverTemporary(mProject);
  if not ReadOptions(mProject, mCurrent) then
  begin
    AReason := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesWriteFailed, [ExtractFileName(mProject.FileName)]);
    Exit;
  end;
  mOptions := TAtlasStartProfiles.TemporaryOptions(mCurrent, AParameters(mCurrent.Parameters));
  // Erst merken (übersteht einen Absturz), dann schreiben.
  mState := TAtlasStartProfiles.Load(Folder, mProject.FileName);
  TAtlasStartProfiles.BeginTemporary(mState, mCurrent, mOptions.Parameters);
  if not TAtlasStartProfiles.Save(Folder, mState) then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.StartProfilesSaveFailed);
    Exit;
  end;
  FTemporary := mProject.FileName;
  if not WriteOptions(mProject, mOptions, AReason) then
  begin
    AReason := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesWriteFailed, [AReason]);
    EndTemporary(mProject.FileName, mChanged);
    Exit;
  end;
  if not Execute(ADebugger, AReason) then
  begin
    EndTemporary(mProject.FileName, mChanged);
    Exit;
  end;
  Result := True;
end;

class function TAtlasIdeStartOptions.EndTemporary(const AProject: string; out AChanged: Boolean): Boolean;
var
  mProject: IOTAProject;
  mState: TAtlasStartProfileState;
  mCurrent, mBefore: TAtlasStartOptions;
  mReason: string;
begin
  AChanged := False;
  Result := False;
  if SameText(FTemporary, AProject) then
    FTemporary := '';
  mProject := FindProject(AProject);
  if mProject = nil then
    Exit;
  mState := TAtlasStartProfiles.Load(Folder, mProject.FileName);
  if not mState.HasTemporary then
    Exit(True);
  ReadOptions(mProject, mCurrent);
  if TAtlasStartProfiles.EndTemporary(mState, mCurrent, mBefore) then
  begin
    if not WriteOptions(mProject, mBefore, mReason) then
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.StartProfilesWriteFailed, [mReason]));
      Exit;
    end;
  end
  else
    AChanged := True;
  // Die Startprofile sehen die geänderte lokale Datei bei ihrer nächsten Prüfung und setzen das Profil wieder.
  Result := TAtlasStartProfiles.Save(Folder, mState);
end;

class function TAtlasIdeStartOptions.RecoverTemporary(const AProject: IOTAProject): Boolean;
var
  mState: TAtlasStartProfileState;
  mChanged: Boolean;
begin
  Result := False;
  if (AProject = nil) or SameText(FTemporary, AProject.FileName) or Debugging then
    Exit;
  mState := TAtlasStartProfiles.Load(Folder, AProject.FileName);
  if not mState.HasTemporary then
    Exit;
  Result := True;
  if EndTemporary(AProject.FileName, mChanged) and not mChanged then
    Say(TAtlasStrings.Fmt(TAtlasTextId.StartProfilesTemporaryRestored, [ExtractFileName(AProject.FileName)]));
end;

class function TAtlasIdeStartOptions.TemporaryProject: string;
begin
  Result := FTemporary;
end;

end.
