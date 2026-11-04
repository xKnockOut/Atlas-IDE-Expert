unit Atlas.IDE.Welcome.Unsaved;

// Bereich „Nicht gesichert“ in der IDE (#762): Quelle des Bereichs
// (IAtlasUnsavedSource), Anmeldung als Bereich atlas.unsaved der
// Willkommensseite (bzw. des Fensters „Atlas-Start“), Abfrage im Hintergrund
// und die Aktionen.
// - Projekte: dieselbe Liste wie der Bereich „Projekte“ (#592): zuletzt
//   geöffnete Projekte der IDE, höchstens welcomePage.maxProjects, ohne „Aus
//   Liste entfernte“.
// - Abfrage über TAtlasIdeVcs (#571) im Hintergrund: beim Anzeigen und beim
//   Schließen eines Projekts, je Projekt höchstens einmal je Minute, mit 1 s
//   je Aufruf und 2 s je Projekt; kein fetch, kein Netzzugriff. Das Ergebnis
//   steht im Abschnitt "unsaved" der Projekt-Zusammenfassung, damit die Seite
//   beim nächsten Start sofort den letzten Stand zeigt.
// - „Ansehen“ öffnet das Projekt und listet die geänderten Dateien (bzw. die
//   Dateien der Stashes) im Fenster „Atlas-Ergebnisse“ (#400); Doppelklick
//   öffnet die Datei. Eine eigene Änderungsansicht hat #571 nicht.
// - „Push …“ ermittelt Ziel und Commits frisch, zeigt sie in
//   TAtlasPushDialog und pusht nur nach „Pushen“; nie automatisch. Ergebnis
//   in der Meldungsansicht.
// - Kontextmenü: „Ordner öffnen“, „Ignorieren bis morgen“ (bis Mitternacht
//   Ortszeit, gespeichert in der Zusammenfassung).
// - welcomePage.unsaved aus: kein Bereich, keine Abfrage.
//   welcomePage.unsaved.hideWhenClean: Bereich nur, wenn es etwas zu zeigen
//   gibt; ändert sich das, richtet die Willkommensseite sich neu ein.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  ToolsAPI,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Unsaved,
  Atlas.UI.Welcome.Unsaved;

type
  TAtlasIdeUnsaved = class(TInterfacedObject, IAtlasUnsavedSource)
  public const
    /// <summary>Reihenfolge außerhalb des Atlas-Layouts.</summary>
    Order = 25;
    /// <summary>Zeitlimit je Aufruf für „Ansehen“ und das Ermitteln von Ziel und Commits.</summary>
    ActionTimeoutMs = 5000;
    /// <summary>Höchstens so viele Stashes zeigt „Ansehen“.</summary>
    MaxStashes = 10;
  private type
    TIdeNotifier = class(TNotifierObject, IOTAIDENotifier)
    private
      FOwner: TAtlasIdeUnsaved;
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
    FPushing: Boolean;
    // Normierter Pfad → Zeitpunkt (GetTickCount64) bzw. Ergebnis der letzten Abfrage in dieser Sitzung.
    FFresh: TDictionary<string, UInt64>;
    FLive: TDictionary<string, TAtlasUnsavedState>;
    // Normierter Pfad → Start der laufenden Abfrage (GetTickCount64).
    FQuerying: TDictionary<string, UInt64>;
    // Zuletzt gemeldete Sichtbarkeit des Bereichs (hideWhenClean).
    FVisible: Boolean;
    procedure Changed;
    procedure Report(const AText: string);
    function Projects: TArray<TAtlasUnsavedProject>;
    function CurrentView: TAtlasUnsavedView;
    function IsVisible: Boolean;
    procedure Refresh(AForce: Boolean);
    procedure Query(const AProject: string);
    function Querying(const AKey: string): Boolean;
    procedure Closing(const AProject: string);
    procedure OpenProject(const AProject: string);
    procedure ShowFiles(const ARow: TAtlasUnsavedRow);
    procedure RunPush(const ARow: TAtlasUnsavedRow; const APlans: TArray<TAtlasUnsavedPush>);
    class function Options: TAtlasUnsavedOptions; static;
    class function NowUtc: TDateTime; static;
    class function FileTimeUtc(const AFileName: string; out AUtc: TDateTime): Boolean; static;
    class function KindText(AKind: Integer): string; static;
  public
    /// <summary>AMessage: Zeile in die Meldungsansicht.</summary>
    constructor Create(const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Bereich, Fabrik und Beobachter der IDE anmelden.</summary>
    procedure Start;
    /// <summary>Alles abmelden (beim Entladen); danach wirkungslos.</summary>
    procedure Stop;
    function Section: TAtlasWelcomeSection;
    { IAtlasUnsavedSource }
    function View: TAtlasUnsavedView;
    procedure Show(const ARow: TAtlasUnsavedRow);
    procedure Push(const ARow: TAtlasUnsavedRow);
    procedure OpenFolder(const ARow: TAtlasUnsavedRow);
    procedure Ignore(const ARow: TAtlasUnsavedRow);
    procedure Shown;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  System.Math,
  Winapi.Windows,
  Winapi.ShellAPI,
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Results.Model,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Welcome.Search,
  Atlas.Core.Welcome.Projects,
  Atlas.UI.Welcome.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.Push,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.IDE.Vcs.Service,
  Atlas.IDE.Welcome.Search,
  Atlas.IDE.Welcome.Projects,
  Atlas.IDE.Projects.Summaries;

{ TAtlasIdeUnsaved.TIdeNotifier }

procedure TAtlasIdeUnsaved.TIdeNotifier.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string;
  var Cancel: Boolean);
var
  Owner: TAtlasIdeUnsaved;
  Name: string;
begin
  Owner := FOwner;
  if (Owner = nil) or (NotifyCode <> ofnFileClosing) or not TAtlasWelcomeSearch.IsProjectFile(FileName) then
  begin
    Exit;
  end;
  Name := FileName;
  // Keine Exception an die IDE (#493).
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      Owner.Closing(Name);
    end);
end;

procedure TAtlasIdeUnsaved.TIdeNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TAtlasIdeUnsaved.TIdeNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

{ TAtlasIdeUnsaved }

constructor TAtlasIdeUnsaved.Create(const AMessage: TProc<string>);
begin
  inherited Create;
  FMessage := AMessage;
  FNotifierIndex := -1;
  FVisible := True;
  FFresh := TDictionary<string, UInt64>.Create;
  FLive := TDictionary<string, TAtlasUnsavedState>.Create;
  FQuerying := TDictionary<string, UInt64>.Create;
end;

destructor TAtlasIdeUnsaved.Destroy;
begin
  Stop;
  FQuerying.Free;
  FLive.Free;
  FFresh.Free;
  inherited;
end;

class function TAtlasIdeUnsaved.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasIdeUnsaved.Options: TAtlasUnsavedOptions;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := TAtlasUnsavedOptions.Create(Settings.WelcomePageUnsavedMinAgeHours, Settings.WelcomePageUnsavedWarnHours,
    Settings.WelcomePageUnsavedAlertHours);
end;

class function TAtlasIdeUnsaved.FileTimeUtc(const AFileName: string; out AUtc: TDateTime): Boolean;
begin
  // Läuft im Hintergrund: nur Dateisystem, keine IDE.
  Result := False;
  AUtc := 0;
  try
    if FileExists(AFileName) then
    begin
      AUtc := TFile.GetLastWriteTimeUtc(AFileName);
      Result := True;
    end
    else if DirectoryExists(AFileName) then
    begin
      // SVN meldet unversionierte Ordner als einen Eintrag.
      AUtc := TDirectory.GetLastWriteTimeUtc(AFileName);
      Result := True;
    end;
  except
    // Gerade gelöscht oder gesperrt: Alter dann über den Zeitpunkt der ersten Sicht.
    on Exception do
      Result := False;
  end;
end;

class function TAtlasIdeUnsaved.KindText(AKind: Integer): string;
begin
  case TAtlasVcsChangeKind(AKind) of
    TAtlasVcsChangeKind.Added:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedKindAdded);
    TAtlasVcsChangeKind.Untracked:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedKindUntracked);
    TAtlasVcsChangeKind.Deleted, TAtlasVcsChangeKind.Missing:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedKindDeleted);
    TAtlasVcsChangeKind.Renamed, TAtlasVcsChangeKind.Copied:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedKindRenamed);
    TAtlasVcsChangeKind.Conflicted:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedKindConflicted);
  else
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedKindModified);
  end;
end;

procedure TAtlasIdeUnsaved.Start;
var
  Services: IOTAServices;
  Keep: IAtlasUnsavedSource;
begin
  FStopped := False;
  Keep := Self;
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.Unsaved,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeUnsavedFrame;
    begin
      Frame := TAtlasWelcomeUnsavedFrame.Create(AOwner);
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

procedure TAtlasIdeUnsaved.Stop;
var
  Services: IOTAServices;
begin
  if FStopped then
  begin
    Exit;
  end;
  FStopped := True;
  if FNotifier <> nil then
  begin
    FNotifier.FOwner := nil;
    // RemoveNotifier gibt die Referenz der IDE frei und damit den Beobachter (#493).
    if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, Services) then
    begin
      Services.RemoveNotifier(FNotifierIndex);
    end;
    FNotifier := nil;
    FNotifierIndex := -1;
  end;
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.Unsaved);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.Unsaved);
end;

function TAtlasIdeUnsaved.Section: TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.Unsaved,
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedTitle), Order, TAtlasWelcomeColumn.Right,
    function: Boolean
    begin
      Result := IsVisible;
    end);
end;

function TAtlasIdeUnsaved.IsVisible: Boolean;
var
  Settings: TAtlasPluginSettings;
  Keep: IAtlasUnsavedSource;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.WelcomePageUnsaved and not FStopped;
  if Result and Settings.WelcomePageUnsavedHideWhenClean then
  begin
    Result := not CurrentView.Clean;
    // Ausgeblendet gibt es kein „Shown“: neue Arbeit trotzdem bemerken (je Projekt höchstens einmal je Minute).
    if not Result then
    begin
      // Keep hält die Quelle bis zum Aufruf am Leben.
      Keep := Self;
      TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
        procedure
        begin
          if Keep <> nil then
          begin
            Refresh(False);
          end;
        end);
    end;
  end;
  FVisible := Result;
end;

procedure TAtlasIdeUnsaved.Changed;
var
  Settings: TAtlasPluginSettings;
begin
  if FStopped then
  begin
    Exit;
  end;
  Settings := TAtlasIdeSettings.Current;
  // Mit hideWhenClean kann der Bereich erscheinen oder verschwinden: dann neu einrichten.
  if Settings.WelcomePageUnsaved and Settings.WelcomePageUnsavedHideWhenClean and
    (FVisible = CurrentView.Clean) then
  begin
    TAtlasWelcomeSections.Default.Changed;
  end
  else
  begin
    TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.Unsaved);
  end;
end;

procedure TAtlasIdeUnsaved.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

function TAtlasIdeUnsaved.Projects: TArray<TAtlasUnsavedProject>;
var
  Recent: TArray<string>;
  Entries: TAtlasProjectEntries;
  Entry: TAtlasProjectEntry;
  Item: TAtlasUnsavedProject;
  Key, Root: string;
  State: TAtlasUnsavedState;
begin
  Result := nil;
  if FStopped then
  begin
    Exit;
  end;
  Recent := nil;
  try
    Recent := TAtlasIdeWelcomeSearch.ClosedProjects;
  except
    // Registry nicht lesbar: leere Liste statt eines Fehlers in der Willkommensseite.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
  Root := TAtlasIdeProjectSummaries.Folder;
  // Dieselbe Liste wie der Bereich „Projekte“ (#592).
  Entries := TAtlasWelcomeProjects.Entries(Recent,
    function(const AProject: string; out ASummary: TAtlasProjectSummary): Boolean
    begin
      Result := TAtlasProjectSummaries.Load(Root, AProject, ASummary);
    end,
    TAtlasIdeSettings.Current.WelcomePageMaxProjects);
  for Entry in Entries do
  begin
    Item := Default(TAtlasUnsavedProject);
    Item.Project := Entry.Project;
    Key := TAtlasProjectSummaries.NormalizedPath(Entry.Project);
    if FLive.TryGetValue(Key, State) then
    begin
      Item.State := State;
      Item.Fresh := True;
    end
    else if Entry.HasSummary then
    begin
      TAtlasWelcomeUnsaved.Read(Entry.Summary, Item.State);
    end;
    Item.Querying := Querying(Key);
    Result := Result + [Item];
  end;
end;

function TAtlasIdeUnsaved.CurrentView: TAtlasUnsavedView;
begin
  Result := TAtlasWelcomeUnsaved.View(Projects, NowUtc, Options);
end;

function TAtlasIdeUnsaved.View: TAtlasUnsavedView;
begin
  Result := Default(TAtlasUnsavedView);
  if FStopped or not TAtlasIdeSettings.Current.WelcomePageUnsaved then
  begin
    Exit;
  end;
  Result := CurrentView;
end;

procedure TAtlasIdeUnsaved.Shown;
begin
  Refresh(False);
end;

procedure TAtlasIdeUnsaved.Refresh(AForce: Boolean);
var
  Item: TAtlasUnsavedProject;
  Last, Now_: UInt64;
begin
  if FStopped or not TAtlasIdeSettings.Current.WelcomePageUnsaved then
  begin
    Exit;
  end;
  Now_ := GetTickCount64;
  for Item in Projects do
  begin
    if AForce or not FFresh.TryGetValue(TAtlasProjectSummaries.NormalizedPath(Item.Project), Last) or
      (Now_ - Last >= TAtlasWelcomeUnsaved.RefreshMs) then
    begin
      Query(Item.Project);
    end;
  end;
end;

function TAtlasIdeUnsaved.Querying(const AKey: string): Boolean;
var
  Started: UInt64;
begin
  // Eine Abfrage, die nicht binnen QueryLimitMs zurückkam, gilt als beendet.
  Result := FQuerying.TryGetValue(AKey, Started) and (GetTickCount64 >= Started) and
    (GetTickCount64 - Started < TAtlasWelcomeUnsaved.QueryLimitMs);
  if not Result then
  begin
    FQuerying.Remove(AKey);
  end;
end;

/// <summary>Anfrage für die Abfrage im Hintergrund: Zeitlimit von 2 s je Projekt ab AStarted; danach kein weiterer
/// Aufruf, der Rest kommt aus dem gespeicherten Stand.</summary>
function QueryFor(const ADir: string; AStamp: TDateTime; AStarted: UInt64; AWorkingCopies: Boolean;
  const AFileTime: TAtlasUnsavedFileTime): TAtlasUnsavedQuery;
begin
  Result := TAtlasUnsavedQuery.Create(ADir, AStamp, AFileTime,
    function: Boolean
    begin
      Result := GetTickCount64 - AStarted >= TAtlasWelcomeUnsaved.TimeLimitMs;
    end);
  Result.WorkingCopies := AWorkingCopies;
end;

/// <summary>AState mit dem gespeicherten Stand zusammenführen (Ignorieren, Alter unbekannter Arten, nicht
/// Abgefragtes) und in die Zusammenfassung schreiben; ALive (Stand dieser Sitzung) hat Vorrang vor der Datei.</summary>
function MergeAndStore(const ARoot, AProject, AKey: string; const AState: TAtlasUnsavedState; AStamp: TDateTime;
  ALive: TDictionary<string, TAtlasUnsavedState>): TAtlasUnsavedState;
var
  mMerged: TAtlasUnsavedState;
begin
  mMerged := AState;
  TAtlasProjectSummaries.Update(ARoot, AProject,
    procedure(var ASummary: TAtlasProjectSummary)
    var
      mOld: TAtlasUnsavedState;
    begin
      if not ALive.TryGetValue(AKey, mOld) then
      begin
        TAtlasWelcomeUnsaved.Read(ASummary, mOld);
      end;
      mMerged := TAtlasWelcomeUnsaved.Merge(mOld, AState, AStamp);
      TAtlasWelcomeUnsaved.Write(ASummary, mMerged);
    end);
  Result := mMerged;
end;

procedure TAtlasIdeUnsaved.Query(const AProject: string);
var
  Keep: IAtlasUnsavedSource;
  Key, Project, Dir, Root: string;
  Stamp: TDateTime;
  Ok: Boolean;
  State: TAtlasUnsavedState;
  Started: UInt64;
  mQuery: TAtlasUnsavedQuery;
begin
  Key := TAtlasProjectSummaries.NormalizedPath(AProject);
  if FStopped or Querying(Key) then
  begin
    Exit;
  end;
  Started := GetTickCount64;
  FQuerying.AddOrSetValue(Key, Started);
  Keep := Self;
  Project := AProject;
  Dir := ExtractFileDir(AProject);
  Root := TAtlasIdeProjectSummaries.Folder;
  Stamp := NowUtc;
  Ok := False;
  State := TAtlasUnsavedState.Empty;
  // Anteile je External bzw. Submodul (#1292); im Hauptthread gelesen.
  mQuery := QueryFor(Dir, Stamp, Started, TAtlasIdeSettings.Current.VcsExternalsShow, FileTimeUtc);
  // Arbeit und Ergebnis teilen sich Ok und State; das Ergebnis kommt erst nach der Arbeit.
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      Ok := TAtlasWelcomeUnsaved.Probe(TAtlasIdeVcs.ForFolder(Dir, TAtlasWelcomeUnsaved.CallTimeoutMs), mQuery, State);
    end,
    procedure
    var
      Current: UInt64;
    begin
      // Keep hält die Quelle bis hierher am Leben.
      if (Keep = nil) or FStopped then
      begin
        Exit;
      end;
      // Nur die eigene Abfrage beenden, nicht eine neuere nach Ablauf des Zeitlimits.
      if FQuerying.TryGetValue(Key, Current) and (Current = Started) then
      begin
        FQuerying.Remove(Key);
      end;
      FFresh.AddOrSetValue(Key, GetTickCount64);
      if Ok then
      begin
        FLive.AddOrSetValue(Key, MergeAndStore(Root, Project, Key, State, Stamp, FLive));
      end;
      Changed;
    end) then
  begin
    // Nicht gestartet (Versionsverwaltung noch nicht bereit oder beendet): nicht bei jedem Zeichnen neu versuchen.
    FQuerying.Remove(Key);
    FFresh.AddOrSetValue(Key, GetTickCount64);
  end;
end;

procedure TAtlasIdeUnsaved.Closing(const AProject: string);
begin
  // Beim Schließen bleibt oft etwas liegen: frisch abfragen, auch wenn die Willkommensseite zu ist.
  if FStopped or not TAtlasIdeSettings.Current.WelcomePageUnsaved then
  begin
    Exit;
  end;
  Query(TAtlasIdeProjectSummaries.ProjectFileOf(AProject));
end;

procedure TAtlasIdeUnsaved.OpenProject(const AProject: string);
var
  Modules: IOTAModuleServices;
  Actions: IOTAActionServices;
begin
  if not FileExists(AProject) then
  begin
    Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsMissing, [AProject]));
    Exit;
  end;
  // Schon offen: nicht neu laden.
  if Supports(BorlandIDEServices, IOTAModuleServices, Modules) and (Modules.FindModule(AProject) <> nil) then
  begin
    Exit;
  end;
  if Supports(BorlandIDEServices, IOTAActionServices, Actions) then
  begin
    Actions.OpenProject(AProject, True);
  end;
end;

procedure TAtlasIdeUnsaved.Show(const ARow: TAtlasUnsavedRow);
var
  Row: TAtlasUnsavedRow;
begin
  Row := ARow;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      OpenProject(Row.Project);
      ShowFiles(Row);
    end);
end;

/// <summary>Dateien der Stashes (höchstens MaxStashes) für „Ansehen“.</summary>
function StashEntries(const ALocal: IAtlasVcsLocalWork; out AEntries: TArray<TAtlasResultEntry>): TAtlasVcsOutcome;
var
  mStashes: TArray<TAtlasVcsStash>;
  mChanges: TArray<TAtlasVcsChange>;
  mChange: TAtlasVcsChange;
  mIndex: Integer;
  mEntry: TAtlasResultEntry;
begin
  AEntries := nil;
  Result := ALocal.Stashes(mStashes);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  for mIndex := 0 to Min(High(mStashes), TAtlasIdeUnsaved.MaxStashes - 1) do
  begin
    if ALocal.ChangesIn(mStashes[mIndex].Hash, mChanges) <> TAtlasVcsOutcome.Ok then
    begin
      Continue;
    end;
    for mChange in mChanges do
    begin
      mEntry := TAtlasResultEntry.Create(mChange.Path, 0, 0);
      mEntry.Text := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedInStash, [mStashes[mIndex].Message,
        TAtlasIdeUnsaved.KindText(Ord(mChange.Kind))]);
      AEntries := AEntries + [mEntry];
    end;
  end;
end;

/// <summary>Wie in der Zeile: nur im Projektordner ADir; Konflikte (AConflicts) bzw. die übrigen Änderungen.</summary>
function ChangeEntries(const AVcs: IAtlasVersionControl; const ADir: string; AConflicts: Boolean;
  out AEntries: TArray<TAtlasResultEntry>): TAtlasVcsOutcome;
var
  mChanges: TArray<TAtlasVcsChange>;
  mChange: TAtlasVcsChange;
  mEntry: TAtlasResultEntry;
begin
  AEntries := nil;
  Result := AVcs.Changes(mChanges);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  for mChange in TAtlasWelcomeUnsaved.ChangesBelow(mChanges, ADir) do
  begin
    if (mChange.Kind = TAtlasVcsChangeKind.Conflicted) = AConflicts then
    begin
      mEntry := TAtlasResultEntry.Create(mChange.Path, 0, 0);
      mEntry.Text := TAtlasIdeUnsaved.KindText(Ord(mChange.Kind));
      AEntries := AEntries + [mEntry];
    end;
  end;
end;

/// <summary>Einträge für „Ansehen“ der Art AKind in ADir (startet Prozesse: nur im Hintergrund).</summary>
function FilesOf(const ADir: string; AKind: TAtlasUnsavedKind;
  out AEntries: TArray<TAtlasResultEntry>): TAtlasVcsOutcome;
var
  mVcs: IAtlasVersionControl;
  mLocal: IAtlasVcsLocalWork;
begin
  AEntries := nil;
  Result := TAtlasVcsOutcome.Failed;
  mVcs := TAtlasIdeVcs.ForFolder(ADir, TAtlasIdeUnsaved.ActionTimeoutMs);
  if AKind <> TAtlasUnsavedKind.Stashes then
  begin
    Result := ChangeEntries(mVcs, ADir, AKind = TAtlasUnsavedKind.Conflicts, AEntries);
  end
  else if Supports(mVcs, IAtlasVcsLocalWork, mLocal) then
  begin
    Result := StashEntries(mLocal, AEntries);
  end;
end;

procedure TAtlasIdeUnsaved.ShowFiles(const ARow: TAtlasUnsavedRow);
var
  Keep: IAtlasUnsavedSource;
  Row: TAtlasUnsavedRow;
  Dir: string;
  Entries: TArray<TAtlasResultEntry>;
  Outcome: TAtlasVcsOutcome;
begin
  Keep := Self;
  Row := ARow;
  Dir := ExtractFileDir(ARow.Project);
  Entries := nil;
  Outcome := TAtlasVcsOutcome.Failed;
  TAtlasIdeVcs.Run(
    procedure
    begin
      Outcome := FilesOf(Dir, Row.Item.Kind, Entries);
    end,
    procedure
    var
      mTitle: TAtlasWelcomeTextId;
    begin
      if (Keep = nil) or FStopped then
      begin
        Exit;
      end;
      if Outcome <> TAtlasVcsOutcome.Ok then
      begin
        Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedQueryFailed,
          [Row.Name, AtlasVcsOutcomeName(Outcome)]));
        Exit;
      end;
      mTitle := TAtlasWelcomeTextId.WelcomeUnsavedChangesTitle;
      if Row.Item.Kind = TAtlasUnsavedKind.Stashes then
      begin
        mTitle := TAtlasWelcomeTextId.WelcomeUnsavedStashTitle;
      end;
      TAtlasIdeResultsWindow.ShowEntries(TAtlasWelcomeStrings.Fmt(mTitle, [Row.Name, Length(Entries)]), Entries);
    end);
end;

procedure TAtlasIdeUnsaved.Push(const ARow: TAtlasUnsavedRow);
var
  Keep: IAtlasUnsavedSource;
  Row: TAtlasUnsavedRow;
  Dir: string;
  Plans: TArray<TAtlasUnsavedPush>;
  Outcome: TAtlasVcsOutcome;
begin
  if FStopped or FPushing or not ARow.Item.CanPush then
  begin
    Exit;
  end;
  Keep := Self;
  Row := ARow;
  Dir := ExtractFileDir(ARow.Project);
  Plans := nil;
  Outcome := TAtlasVcsOutcome.Failed;
  FPushing := True;
  // Ziel und Commits frisch ermitteln (nur lokal); gepusht wird erst nach der Bestätigung.
  if not TAtlasIdeVcs.Run(
    procedure
    var
      Local: IAtlasVcsLocalWork;
    begin
      if Supports(TAtlasIdeVcs.ForFolder(Dir, ActionTimeoutMs), IAtlasVcsLocalWork, Local) then
      begin
        Outcome := TAtlasWelcomeUnsaved.PushPlans(Local, Row.Item, Plans);
      end;
    end,
    procedure
    begin
      FPushing := False;
      if (Keep = nil) or FStopped then
      begin
        Exit;
      end;
      TAtlasGuard.Run(TAtlasFeature.WelcomePage,
        procedure
        begin
          if Outcome <> TAtlasVcsOutcome.Ok then
          begin
            Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedQueryFailed, [Row.Name,
              AtlasVcsOutcomeName(Outcome)]));
          end
          else if Length(Plans) = 0 then
          begin
            Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedPushNothing, [Row.Name]));
          end
          else if TAtlasPushDialog.Confirm(Row.Name, Plans, nil) then
          begin
            RunPush(Row, Plans);
          end;
        end);
    end) then
  begin
    FPushing := False;
  end;
end;

/// <summary>Alle APlans pushen (spricht mit dem Server: eigenes, langes Zeitlimit); leer ohne Umsetzung.</summary>
function PushAll(const ADir: string; const APlans: TArray<TAtlasUnsavedPush>): TArray<TAtlasVcsOutcome>;
var
  mLocal: IAtlasVcsLocalWork;
  mPlan: TAtlasUnsavedPush;
begin
  Result := nil;
  if Supports(TAtlasIdeVcs.ForFolder(ADir, TAtlasWelcomeUnsaved.PushTimeoutMs), IAtlasVcsLocalWork, mLocal) then
  begin
    for mPlan in APlans do
    begin
      Result := Result + [mLocal.Push(mPlan.Branch, mPlan.Remote, mPlan.RemoteRef, mPlan.SetUpstream)];
    end;
  end;
end;

/// <summary>Meldung zu Push AIndex von APlans; fehlt sein Ergebnis, gilt er als misslungen.</summary>
function PushReport(const AName: string; const APlans: TArray<TAtlasUnsavedPush>;
  const AOutcomes: TArray<TAtlasVcsOutcome>; AIndex: Integer): string;
var
  mOutcome: TAtlasVcsOutcome;
begin
  mOutcome := TAtlasVcsOutcome.Failed;
  if AIndex <= High(AOutcomes) then
  begin
    mOutcome := AOutcomes[AIndex];
  end;
  if mOutcome = TAtlasVcsOutcome.Ok then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedPushDone, [AName, APlans[AIndex].Branch,
      APlans[AIndex].Target]);
  end
  else
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedPushFailed, [AName, APlans[AIndex].Branch,
      APlans[AIndex].Target, AtlasVcsOutcomeName(mOutcome)]);
  end;
end;

procedure TAtlasIdeUnsaved.RunPush(const ARow: TAtlasUnsavedRow; const APlans: TArray<TAtlasUnsavedPush>);
var
  Keep: IAtlasUnsavedSource;
  Row: TAtlasUnsavedRow;
  Plans: TArray<TAtlasUnsavedPush>;
  Dir: string;
  Outcomes: TArray<TAtlasVcsOutcome>;
begin
  Keep := Self;
  Row := ARow;
  Plans := APlans;
  Dir := ExtractFileDir(ARow.Project);
  Outcomes := nil;
  FPushing := True;
  TAtlasGuard.Log(Format('Willkommensseite: Push von %d Branch(es) bestätigt', [Length(Plans)]));
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      Outcomes := PushAll(Dir, Plans);
    end,
    procedure
    var
      mIndex: Integer;
    begin
      FPushing := False;
      if (Keep = nil) or FStopped then
      begin
        Exit;
      end;
      for mIndex := 0 to High(Plans) do
      begin
        Report(PushReport(Row.Name, Plans, Outcomes, mIndex));
      end;
      // Neuer Stand für die Zeile.
      FFresh.Remove(TAtlasProjectSummaries.NormalizedPath(Row.Project));
      Query(Row.Project);
    end) then
  begin
    FPushing := False;
  end;
end;

procedure TAtlasIdeUnsaved.OpenFolder(const ARow: TAtlasUnsavedRow);
var
  Project: string;
begin
  Project := ARow.Project;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if FileExists(Project) then
      begin
        // Explorer mit markierter Projektdatei.
        ShellExecute(0, 'open', 'explorer.exe', PChar('/select,"' + Project + '"'), nil, SW_SHOWNORMAL);
      end
      else if DirectoryExists(ExtractFileDir(Project)) then
      begin
        ShellExecute(0, 'open', PChar(ExtractFileDir(Project)), nil, nil, SW_SHOWNORMAL);
      end
      else
      begin
        Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsMissing, [Project]));
      end;
    end);
end;

procedure TAtlasIdeUnsaved.Ignore(const ARow: TAtlasUnsavedRow);
var
  Row: TAtlasUnsavedRow;
begin
  Row := ARow;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Key: string;
      UntilUtc: TDateTime;
      State: TAtlasUnsavedState;
    begin
      Key := TAtlasProjectSummaries.NormalizedPath(Row.Project);
      // Bis Mitternacht Ortszeit.
      UntilUtc := TTimeZone.Local.ToUniversalTime(TAtlasWelcomeUnsaved.Tomorrow(Now));
      TAtlasProjectSummaries.Update(TAtlasIdeProjectSummaries.Folder, Row.Project,
        procedure(var ASummary: TAtlasProjectSummary)
        var
          Stored: TAtlasUnsavedState;
        begin
          TAtlasWelcomeUnsaved.Read(ASummary, Stored);
          TAtlasWelcomeUnsaved.Ignore(Stored, Row.Item.Kind, UntilUtc);
          TAtlasWelcomeUnsaved.Write(ASummary, Stored);
        end);
      if FLive.TryGetValue(Key, State) then
      begin
        TAtlasWelcomeUnsaved.Ignore(State, Row.Item.Kind, UntilUtc);
        FLive.AddOrSetValue(Key, State);
      end;
      Changed;
    end);
end;

end.
