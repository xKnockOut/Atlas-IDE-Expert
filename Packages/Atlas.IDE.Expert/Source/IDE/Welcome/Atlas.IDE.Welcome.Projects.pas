unit Atlas.IDE.Welcome.Projects;

// Bereich „Projekte“ in der IDE (#592): Quelle des Bereichs
// (IAtlasProjectsSource), Anmeldung als Bereich atlas.projects der
// Willkommensseite (bzw. des Fensters „Atlas-Start“) und Pflege der
// Projekt-Zusammenfassungen in %LOCALAPPDATA%\Atlas\projects.
// - Liste: zuletzt geöffnete Projekte und Projektgruppen der IDE (Registry
//   <Basis>\Closed Projects), höchstens welcomePage.maxProjects; Schalter
//   welcomePage.projectStatus.
// - Geschrieben wird nach jedem Build und jeder Hintergrundprüfung (Meldungen
//   aus dem Reiter „Build“, #528; bei einer Projektgruppe auch in deren
//   Zusammenfassung), beim Öffnen (lastOpened, hebt „Aus Liste entfernen“
//   auf) und beim Schließen eines Projekts (lastClosed, frischer Stand der
//   Versionsverwaltung). Das geschieht auch, wenn der Bereich ausgeblendet
//   ist: Spätere Bereiche (#755, #758 …) lesen dieselben Dateien.
// - Versionsverwaltung (#571): beim Anzeigen im Hintergrund frisch abgefragt
//   (welcomePage.refreshVcs), je Projekt höchstens einmal je Minute, mit 2 s
//   Zeitlimit; bis dahin gilt der gespeicherte Stand („Stand vom …“).
// - Die Willkommensseite startet keinen Server und liest nur lokale Dateien.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  ToolsAPI,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Projects,
  Atlas.UI.Welcome.Projects;

type
  TAtlasIdeProjects = class(TInterfacedObject, IAtlasProjectsSource)
  public const
    /// <summary>Reihenfolge außerhalb des Atlas-Layouts.</summary>
    Order = 20;
  private type
    TIdeNotifier = class(TNotifierObject, IOTAIDENotifier)
    private
      FOwner: TAtlasIdeProjects;
    public
      procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
      procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;
      procedure AfterCompile(Succeeded: Boolean); overload;
    end;
  private
    FMessage: TProc<string>;
    FNotifier: TIdeNotifier;
    FNotifierIndex: Integer;
    FStopped: Boolean;
    // Normierter Pfad → Zeitpunkt (GetTickCount64) bzw. Ergebnis der letzten Abfrage in dieser Sitzung.
    FFresh: TDictionary<string, UInt64>;
    FLive: TDictionary<string, TAtlasProjectVcs>;
    FQuerying: TDictionary<string, Boolean>;
    procedure Changed;
    procedure Report(const AText: string);
    procedure Opened(const AProject: string);
    procedure Closing(const AProject: string);
    procedure Query(const AProject: string);
    procedure RecordInto(const AProject: string; const AMessages: TArray<TAtlasCompilerMessage>;
      const AInfo: TAtlasCompileProject; ASucceeded: Boolean; ANowUtc: TDateTime);
    class function NowUtc: TDateTime; static;
    class function ProjectOpen(const AFileName: string): Boolean; static;
    class function GroupOf(const AProject: string): string; static;
  public
    /// <summary>AMessage: Zeile in die Meldungsansicht.</summary>
    constructor Create(const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Bereich, Fabrik und Beobachter der IDE anmelden.</summary>
    procedure Start;
    /// <summary>Alles abmelden (beim Entladen); danach wirkungslos.</summary>
    procedure Stop;
    function Section: TAtlasWelcomeSection;
    /// <summary>Ergebnis eines Compiles aus dem Reiter „Build“ (#528); AReadable = False: Meldungen nicht
    /// lesbar, dann bleibt die Zusammenfassung unverändert.</summary>
    procedure Recorded(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      ASucceeded, AReadable: Boolean);
    /// <summary>%LOCALAPPDATA%\Atlas\projects.</summary>
    class function Folder: string; static;
    /// <summary>.dpr bzw. .dpk mit .dproj daneben → .dproj (so führt die IDE ihre Liste).</summary>
    class function ProjectFileOf(const AFileName: string): string; static;
    { IAtlasProjectsSource }
    function Entries: TAtlasProjectEntries;
    procedure Open(const AProject: string);
    procedure OpenAt(const AProject: string; const ATarget: TAtlasProjectLocation);
    procedure OpenFolder(const AProject: string);
    procedure Remove(const AProject: string);
    procedure Shown;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Welcome.Search,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.IDE.Settings.Store,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Vcs.Service,
  Atlas.IDE.Welcome.Search;

{ TAtlasIdeProjects.TIdeNotifier }

procedure TAtlasIdeProjects.TIdeNotifier.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string;
  var Cancel: Boolean);
var
  Owner: TAtlasIdeProjects;
  Name: string;
begin
  Owner := FOwner;
  if (Owner = nil) or not ((NotifyCode = ofnFileOpened) or (NotifyCode = ofnFileClosing)) or
    not TAtlasWelcomeSearch.IsProjectFile(FileName) then
    Exit;
  Name := FileName;
  // Keine Exception an die IDE (#493).
  if NotifyCode = ofnFileOpened then
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        Owner.Opened(Name);
      end)
  else
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        Owner.Closing(Name);
      end);
end;

procedure TAtlasIdeProjects.TIdeNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TAtlasIdeProjects.TIdeNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

{ TAtlasIdeProjects }

constructor TAtlasIdeProjects.Create(const AMessage: TProc<string>);
begin
  inherited Create;
  FMessage := AMessage;
  FNotifierIndex := -1;
  FFresh := TDictionary<string, UInt64>.Create;
  FLive := TDictionary<string, TAtlasProjectVcs>.Create;
  FQuerying := TDictionary<string, Boolean>.Create;
end;

destructor TAtlasIdeProjects.Destroy;
begin
  Stop;
  FQuerying.Free;
  FLive.Free;
  FFresh.Free;
  inherited;
end;

class function TAtlasIdeProjects.Folder: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    TAtlasProjectSummaries.FolderName);
end;

class function TAtlasIdeProjects.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasIdeProjects.ProjectFileOf(const AFileName: string): string;
begin
  Result := AFileName;
  if (SameText(ExtractFileExt(Result), '.dpr') or SameText(ExtractFileExt(Result), '.dpk')) and
    FileExists(ChangeFileExt(Result, '.dproj')) then
    Result := ChangeFileExt(Result, '.dproj');
end;

class function TAtlasIdeProjects.ProjectOpen(const AFileName: string): Boolean;
var
  Modules: IOTAModuleServices;
begin
  Result := Supports(BorlandIDEServices, IOTAModuleServices, Modules) and (Modules.FindModule(AFileName) <> nil);
end;

class function TAtlasIdeProjects.GroupOf(const AProject: string): string;
var
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Index: Integer;
begin
  // Liegt das Projekt in der offenen Projektgruppe, zählt sein Build auch für die Gruppe (die Liste der IDE
  // führt oft nur die Gruppe).
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Group := Modules.MainProjectGroup;
  if (Group = nil) or (Group.FileName = '') or SameText(Group.FileName, AProject) then
    Exit;
  for Index := 0 to Group.ProjectCount - 1 do
    if (Group.Projects[Index] <> nil) and SameText(Group.Projects[Index].FileName, AProject) then
      Exit(Group.FileName);
end;

procedure TAtlasIdeProjects.Start;
var
  Services: IOTAServices;
  Keep: IAtlasProjectsSource;
begin
  FStopped := False;
  Keep := Self;
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.Projects,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeProjectsFrame;
    begin
      Frame := TAtlasWelcomeProjectsFrame.Create(AOwner);
      Frame.Source := Keep;
      Result := Frame;
    end);
  TAtlasWelcomeSections.Default.Add(Section);
  if (FNotifier = nil) and Supports(BorlandIDEServices, IOTAServices, Services) then
  begin
    FNotifier := TIdeNotifier.Create;
    FNotifier.FOwner := Self;
    FNotifierIndex := Services.AddNotifier(FNotifier);
  end;
end;

procedure TAtlasIdeProjects.Stop;
var
  Services: IOTAServices;
begin
  if FStopped then
    Exit;
  FStopped := True;
  if FNotifier <> nil then
  begin
    FNotifier.FOwner := nil;
    // RemoveNotifier gibt die Referenz der IDE frei und damit den Beobachter (#493).
    if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, Services) then
      Services.RemoveNotifier(FNotifierIndex);
    FNotifier := nil;
    FNotifierIndex := -1;
  end;
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.Projects);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.Projects);
end;

function TAtlasIdeProjects.Section: TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.Projects,
    TAtlasStrings.Text(TAtlasTextId.WelcomeProjectsTitle), Order, TAtlasWelcomeColumn.Left,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.WelcomePageProjectStatus;
    end);
end;

procedure TAtlasIdeProjects.Changed;
begin
  if not FStopped then
    TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.Projects);
end;

procedure TAtlasIdeProjects.Report(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

function TAtlasIdeProjects.Entries: TAtlasProjectEntries;
var
  Recent: TArray<string>;
  Index: Integer;
  Key: string;
  Vcs: TAtlasProjectVcs;
  Root: string;
begin
  Result := nil;
  if FStopped then
    Exit;
  Recent := nil;
  try
    Recent := TAtlasIdeWelcomeSearch.ClosedProjects;
  except
    // Registry nicht lesbar: leere Liste statt eines Fehlers in der Willkommensseite.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
  Root := Folder;
  Result := TAtlasWelcomeProjects.Entries(Recent,
    function(const AProject: string; out ASummary: TAtlasProjectSummary): Boolean
    begin
      Result := TAtlasProjectSummaries.Load(Root, AProject, ASummary);
    end,
    TAtlasIdeSettings.Current.WelcomePageMaxProjects);
  for Index := 0 to High(Result) do
  begin
    Key := TAtlasProjectSummaries.NormalizedPath(Result[Index].Project);
    if FLive.TryGetValue(Key, Vcs) then
    begin
      Result[Index].Summary.Vcs := Vcs;
      Result[Index].VcsFresh := True;
    end;
    Result[Index].VcsQuerying := FQuerying.ContainsKey(Key);
  end;
end;

procedure TAtlasIdeProjects.Shown;
var
  Entry: TAtlasProjectEntry;
  Last: UInt64;
  Now_: UInt64;
begin
  if FStopped or not TAtlasIdeSettings.Current.WelcomePageRefreshVcs then
    Exit;
  Now_ := GetTickCount64;
  for Entry in Entries do
    if not FFresh.TryGetValue(TAtlasProjectSummaries.NormalizedPath(Entry.Project), Last) or
      (Now_ - Last >= TAtlasWelcomeProjects.VcsRefreshMs) then
      Query(Entry.Project);
end;

procedure TAtlasIdeProjects.Query(const AProject: string);
var
  Keep: IAtlasProjectsSource;
  Key, Project, Dir, Root: string;
  Stamp: TDateTime;
  Ok: Boolean;
  State: TAtlasProjectVcs;
begin
  Key := TAtlasProjectSummaries.NormalizedPath(AProject);
  if FStopped or FQuerying.ContainsKey(Key) then
    Exit;
  FQuerying.Add(Key, True);
  Keep := Self;
  Project := AProject;
  Dir := ExtractFileDir(AProject);
  Root := Folder;
  Stamp := NowUtc;
  Ok := False;
  State := TAtlasProjectVcs.Empty;
  // Arbeit und Ergebnis teilen sich Ok und State; das Ergebnis kommt erst nach der Arbeit.
  TAtlasIdeVcs.Run(
    procedure
    begin
      Ok := TAtlasWelcomeProjects.Probe(TAtlasIdeVcs.ForFolder(Dir, TAtlasWelcomeProjects.VcsCallTimeoutMs), Stamp,
        State);
    end,
    procedure
    begin
      // Keep hält die Quelle bis hierher am Leben.
      if (Keep = nil) or FStopped then
        Exit;
      FQuerying.Remove(Key);
      FFresh.AddOrSetValue(Key, GetTickCount64);
      if Ok then
      begin
        FLive.AddOrSetValue(Key, State);
        TAtlasProjectSummaries.Update(Root, Project,
          procedure(var ASummary: TAtlasProjectSummary)
          begin
            ASummary.Vcs := State;
          end);
      end;
      Changed;
    end);
end;

procedure TAtlasIdeProjects.Opened(const AProject: string);
var
  Stamp: TDateTime;
begin
  if FStopped then
    Exit;
  Stamp := NowUtc;
  TAtlasProjectSummaries.Update(Folder, ProjectFileOf(AProject),
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      ASummary.LastOpened := Stamp;
      // Wieder geöffnet: erscheint wieder in der Liste.
      ASummary.Hidden := False;
    end);
  Changed;
end;

procedure TAtlasIdeProjects.Closing(const AProject: string);
var
  Stamp: TDateTime;
  Project: string;
begin
  if FStopped then
    Exit;
  Stamp := NowUtc;
  Project := ProjectFileOf(AProject);
  TAtlasProjectSummaries.Update(Folder, Project,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      ASummary.LastClosed := Stamp;
    end);
  // Branch und Änderungen beim Schließen festhalten (im Hintergrund, auch wenn die Willkommensseite noch zu ist).
  if TAtlasIdeSettings.Current.WelcomePageRefreshVcs then
    Query(Project);
  Changed;
end;

procedure TAtlasIdeProjects.RecordInto(const AProject: string; const AMessages: TArray<TAtlasCompilerMessage>;
  const AInfo: TAtlasCompileProject; ASucceeded: Boolean; ANowUtc: TDateTime);
var
  Messages: TArray<TAtlasCompilerMessage>;
  Info: TAtlasCompileProject;
  Succeeded: Boolean;
  Stamp: TDateTime;
begin
  Messages := AMessages;
  Info := AInfo;
  Succeeded := ASucceeded;
  Stamp := ANowUtc;
  TAtlasProjectSummaries.Update(Folder, AProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      TAtlasWelcomeProjects.RecordCompile(ASummary, Messages, Info.Background, Succeeded,
        TAtlasCompileEvents.KindText(Info.Kind), Info.Configuration, Info.Platform, Stamp);
    end);
end;

procedure TAtlasIdeProjects.Recorded(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; ASucceeded, AReadable: Boolean);
var
  Stamp: TDateTime;
  Group: string;
begin
  if FStopped or not AReadable or (AProject.FileName = '') then
    Exit;
  Stamp := NowUtc;
  RecordInto(AProject.FileName, AMessages, AProject, ASucceeded, Stamp);
  Group := GroupOf(AProject.FileName);
  if Group <> '' then
    RecordInto(Group, AMessages, AProject, ASucceeded, Stamp);
  Changed;
end;

procedure TAtlasIdeProjects.Open(const AProject: string);
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Actions: IOTAActionServices;
    begin
      if not FileExists(AProject) then
      begin
        Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsMissing, [AProject]));
        Exit;
      end;
      if Supports(BorlandIDEServices, IOTAActionServices, Actions) then
        Actions.OpenProject(AProject, True);
    end);
end;

procedure TAtlasIdeProjects.OpenAt(const AProject: string; const ATarget: TAtlasProjectLocation);
var
  Target: TAtlasProjectLocation;
begin
  Target := ATarget;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Actions: IOTAActionServices;
      Line, Column: Integer;
    begin
      if not FileExists(AProject) then
      begin
        Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsMissing, [AProject]));
        Exit;
      end;
      // Erst das Projekt (wie die Liste der IDE), dann die erste Meldung.
      if not ProjectOpen(AProject) and Supports(BorlandIDEServices, IOTAActionServices, Actions) then
        Actions.OpenProject(AProject, True);
      if Target.IsEmpty or not FileExists(Target.FileName) then
        Exit;
      // Die Zusammenfassung zählt ab 1, der Editor ab 0.
      Line := Target.Line - 1;
      if Line < 0 then
        Line := 0;
      Column := Target.Column - 1;
      if Column < 0 then
        Column := 0;
      TAtlasIdeResults.Open(Target.FileName, Line, Column);
    end);
end;

procedure TAtlasIdeProjects.OpenFolder(const AProject: string);
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if FileExists(AProject) then
        // Explorer mit markierter Projektdatei.
        ShellExecute(0, 'open', 'explorer.exe', PChar('/select,"' + AProject + '"'), nil, SW_SHOWNORMAL)
      else if DirectoryExists(ExtractFileDir(AProject)) then
        ShellExecute(0, 'open', PChar(ExtractFileDir(AProject)), nil, nil, SW_SHOWNORMAL)
      else
        Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsMissing, [AProject]));
    end);
end;

procedure TAtlasIdeProjects.Remove(const AProject: string);
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      // Nur dieser Bereich: Die Liste „Zuletzt geöffnet“ der IDE bleibt unverändert.
      TAtlasProjectSummaries.Update(Folder, AProject,
        procedure(var ASummary: TAtlasProjectSummary)
        begin
          ASummary.Hidden := True;
        end);
      Changed;
    end);
end;

end.
