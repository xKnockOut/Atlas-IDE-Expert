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
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.Push,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.IDE.Vcs.Service,
  Atlas.IDE.Welcome.Search,
  Atlas.IDE.Welcome.Projects;

{ TAtlasIdeUnsaved.TIdeNotifier }

procedure TAtlasIdeUnsaved.TIdeNotifier.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string;
  var Cancel: Boolean);
var
  Owner: TAtlasIdeUnsaved;
  Name: string;
begin
  Owner := FOwner;
  if (Owner = nil) or (NotifyCode <> ofnFileClosing) or not TAtlasWelcomeSearch.IsProjectFile(FileName) then
    Exit;
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
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedKindAdded);
    TAtlasVcsChangeKind.Untracked:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedKindUntracked);
    TAtlasVcsChangeKind.Deleted, TAtlasVcsChangeKind.Missing:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedKindDeleted);
    TAtlasVcsChangeKind.Renamed, TAtlasVcsChangeKind.Copied:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedKindRenamed);
    TAtlasVcsChangeKind.Conflicted:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedKindConflicted);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedKindModified);
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
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.Unsaved);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.Unsaved);
end;

function TAtlasIdeUnsaved.Section: TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.Unsaved,
    TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedTitle), Order, TAtlasWelcomeColumn.Right,
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
            Refresh(False);
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
    Exit;
  Settings := TAtlasIdeSettings.Current;
  // Mit hideWhenClean kann der Bereich erscheinen oder verschwinden: dann neu einrichten.
  if Settings.WelcomePageUnsaved and Settings.WelcomePageUnsavedHideWhenClean and
    (FVisible = CurrentView.Clean) then
    TAtlasWelcomeSections.Default.Changed
  else
    TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.Unsaved);
end;

procedure TAtlasIdeUnsaved.Report(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
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
    Exit;
  Recent := nil;
  try
    Recent := TAtlasIdeWelcomeSearch.ClosedProjects;
  except
    // Registry nicht lesbar: leere Liste statt eines Fehlers in der Willkommensseite.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
  Root := TAtlasIdeProjects.Folder;
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
      TAtlasWelcomeUnsaved.Read(Entry.Summary, Item.State);
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
    Exit;
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
    Exit;
  Now_ := GetTickCount64;
  for Item in Projects do
    if AForce or not FFresh.TryGetValue(TAtlasProjectSummaries.NormalizedPath(Item.Project), Last) or
      (Now_ - Last >= TAtlasWelcomeUnsaved.RefreshMs) then
      Query(Item.Project);
end;

function TAtlasIdeUnsaved.Querying(const AKey: string): Boolean;
var
  Started: UInt64;
begin
  // Eine Abfrage, die nicht binnen QueryLimitMs zurückkam, gilt als beendet.
  Result := FQuerying.TryGetValue(AKey, Started) and (GetTickCount64 >= Started) and
    (GetTickCount64 - Started < TAtlasWelcomeUnsaved.QueryLimitMs);
  if not Result then
    FQuerying.Remove(AKey);
end;

procedure TAtlasIdeUnsaved.Query(const AProject: string);
var
  Keep: IAtlasUnsavedSource;
  Key, Project, Dir, Root: string;
  Stamp: TDateTime;
  Ok: Boolean;
  State: TAtlasUnsavedState;
  Started: UInt64;
begin
  Key := TAtlasProjectSummaries.NormalizedPath(AProject);
  if FStopped or Querying(Key) then
    Exit;
  Started := GetTickCount64;
  FQuerying.AddOrSetValue(Key, Started);
  Keep := Self;
  Project := AProject;
  Dir := ExtractFileDir(AProject);
  Root := TAtlasIdeProjects.Folder;
  Stamp := NowUtc;
  Ok := False;
  State := TAtlasUnsavedState.Empty;
  // Arbeit und Ergebnis teilen sich Ok und State; das Ergebnis kommt erst nach der Arbeit.
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      Ok := TAtlasWelcomeUnsaved.Probe(TAtlasIdeVcs.ForFolder(Dir, TAtlasWelcomeUnsaved.CallTimeoutMs), Dir, Stamp,
        FileTimeUtc,
        function: Boolean
        begin
          // 2 s je Projekt: danach kein weiterer Aufruf; der Rest kommt aus dem gespeicherten Stand.
          Result := GetTickCount64 - Started >= TAtlasWelcomeUnsaved.TimeLimitMs;
        end, State);
    end,
    procedure
    var
      Current: UInt64;
      Merged: TAtlasUnsavedState;
    begin
      // Keep hält die Quelle bis hierher am Leben.
      if (Keep = nil) or FStopped then
        Exit;
      // Nur die eigene Abfrage beenden, nicht eine neuere nach Ablauf des Zeitlimits.
      if FQuerying.TryGetValue(Key, Current) and (Current = Started) then
        FQuerying.Remove(Key);
      FFresh.AddOrSetValue(Key, GetTickCount64);
      if Ok then
      begin
        // Mit dem gespeicherten Stand zusammenführen (Ignorieren, Alter unbekannter Arten, nicht Abgefragtes).
        Merged := State;
        TAtlasProjectSummaries.Update(Root, Project,
          procedure(var ASummary: TAtlasProjectSummary)
          var
            Old: TAtlasUnsavedState;
          begin
            if not FLive.TryGetValue(Key, Old) then
              TAtlasWelcomeUnsaved.Read(ASummary, Old);
            Merged := TAtlasWelcomeUnsaved.Merge(Old, State, Stamp);
            TAtlasWelcomeUnsaved.Write(ASummary, Merged);
          end);
        FLive.AddOrSetValue(Key, Merged);
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
    Exit;
  Query(TAtlasIdeProjects.ProjectFileOf(AProject));
end;

procedure TAtlasIdeUnsaved.OpenProject(const AProject: string);
var
  Modules: IOTAModuleServices;
  Actions: IOTAActionServices;
begin
  if not FileExists(AProject) then
  begin
    Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsMissing, [AProject]));
    Exit;
  end;
  // Schon offen: nicht neu laden.
  if Supports(BorlandIDEServices, IOTAModuleServices, Modules) and (Modules.FindModule(AProject) <> nil) then
    Exit;
  if Supports(BorlandIDEServices, IOTAActionServices, Actions) then
    Actions.OpenProject(AProject, True);
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
    var
      Vcs: IAtlasVersionControl;
      Local: IAtlasVcsLocalWork;
      Changes: TArray<TAtlasVcsChange>;
      Change: TAtlasVcsChange;
      Stashes: TArray<TAtlasVcsStash>;
      Index: Integer;
      Entry: TAtlasResultEntry;
    begin
      Vcs := TAtlasIdeVcs.ForFolder(Dir, ActionTimeoutMs);
      if Row.Item.Kind = TAtlasUnsavedKind.Stashes then
      begin
        if not Supports(Vcs, IAtlasVcsLocalWork, Local) then
          Exit;
        Outcome := Local.Stashes(Stashes);
        if Outcome <> TAtlasVcsOutcome.Ok then
          Exit;
        for Index := 0 to High(Stashes) do
        begin
          if Index >= MaxStashes then
            Break;
          if Local.ChangesIn(Stashes[Index].Hash, Changes) <> TAtlasVcsOutcome.Ok then
            Continue;
          for Change in Changes do
          begin
            Entry := TAtlasResultEntry.Create(Change.Path, 0, 0);
            Entry.Text := TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedInStash, [Stashes[Index].Message,
              KindText(Ord(Change.Kind))]);
            Entries := Entries + [Entry];
          end;
        end;
        Exit;
      end;
      Outcome := Vcs.Changes(Changes);
      if Outcome <> TAtlasVcsOutcome.Ok then
        Exit;
      // Wie in der Zeile: nur im Projektordner; Konflikte bzw. die übrigen Änderungen.
      for Change in TAtlasWelcomeUnsaved.ChangesBelow(Changes, Dir) do
        if (Change.Kind = TAtlasVcsChangeKind.Conflicted) = (Row.Item.Kind = TAtlasUnsavedKind.Conflicts) then
        begin
          Entry := TAtlasResultEntry.Create(Change.Path, 0, 0);
          Entry.Text := KindText(Ord(Change.Kind));
          Entries := Entries + [Entry];
        end;
    end,
    procedure
    begin
      if (Keep = nil) or FStopped then
        Exit;
      if Outcome <> TAtlasVcsOutcome.Ok then
      begin
        Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedQueryFailed, [Row.Name, AtlasVcsOutcomeName(Outcome)]));
        Exit;
      end;
      if Row.Item.Kind = TAtlasUnsavedKind.Stashes then
        TAtlasIdeResultsWindow.ShowEntries(TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedStashTitle,
          [Row.Name, Length(Entries)]), Entries)
      else
        TAtlasIdeResultsWindow.ShowEntries(TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedChangesTitle,
          [Row.Name, Length(Entries)]), Entries);
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
    Exit;
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
        Outcome := TAtlasWelcomeUnsaved.PushPlans(Local, Row.Item, Plans);
    end,
    procedure
    begin
      FPushing := False;
      if (Keep = nil) or FStopped then
        Exit;
      TAtlasGuard.Run(TAtlasFeature.WelcomePage,
        procedure
        begin
          if Outcome <> TAtlasVcsOutcome.Ok then
            Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedQueryFailed, [Row.Name,
              AtlasVcsOutcomeName(Outcome)]))
          else if Length(Plans) = 0 then
            Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedPushNothing, [Row.Name]))
          else if TAtlasPushDialog.Confirm(Row.Name, Plans, nil) then
            RunPush(Row, Plans);
        end);
    end) then
    FPushing := False;
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
    var
      Local: IAtlasVcsLocalWork;
      Plan: TAtlasUnsavedPush;
    begin
      // Push spricht mit dem Server: eigenes, langes Zeitlimit.
      if not Supports(TAtlasIdeVcs.ForFolder(Dir, TAtlasWelcomeUnsaved.PushTimeoutMs), IAtlasVcsLocalWork,
        Local) then
        Exit;
      for Plan in Plans do
        Outcomes := Outcomes + [Local.Push(Plan.Branch, Plan.Remote, Plan.RemoteRef, Plan.SetUpstream)];
    end,
    procedure
    var
      Index: Integer;
    begin
      FPushing := False;
      if (Keep = nil) or FStopped then
        Exit;
      for Index := 0 to High(Plans) do
        if (Index <= High(Outcomes)) and (Outcomes[Index] = TAtlasVcsOutcome.Ok) then
          Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedPushDone, [Row.Name, Plans[Index].Branch,
            Plans[Index].Target]))
        else if Index <= High(Outcomes) then
          Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedPushFailed, [Row.Name, Plans[Index].Branch,
            Plans[Index].Target, AtlasVcsOutcomeName(Outcomes[Index])]))
        else
          Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedPushFailed, [Row.Name, Plans[Index].Branch,
            Plans[Index].Target, AtlasVcsOutcomeName(TAtlasVcsOutcome.Failed)]));
      // Neuer Stand für die Zeile.
      FFresh.Remove(TAtlasProjectSummaries.NormalizedPath(Row.Project));
      Query(Row.Project);
    end) then
    FPushing := False;
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
        // Explorer mit markierter Projektdatei.
        ShellExecute(0, 'open', 'explorer.exe', PChar('/select,"' + Project + '"'), nil, SW_SHOWNORMAL)
      else if DirectoryExists(ExtractFileDir(Project)) then
        ShellExecute(0, 'open', PChar(ExtractFileDir(Project)), nil, nil, SW_SHOWNORMAL)
      else
        Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsMissing, [Project]));
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
      TAtlasProjectSummaries.Update(TAtlasIdeProjects.Folder, Row.Project,
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
