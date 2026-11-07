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
    cOrder = 25;
    /// <summary>Zeitlimit je Aufruf für „Ansehen“ und das Ermitteln von Ziel und Commits.</summary>
    cActionTimeoutMs = 5000;
    /// <summary>Höchstens so viele Stashes zeigt „Ansehen“.</summary>
    cMaxStashes = 10;
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
  mOwner: TAtlasIdeUnsaved;
  mName: string;
begin
  mOwner := FOwner;
  if (mOwner = nil) or (NotifyCode <> ofnFileClosing) or not TAtlasWelcomeSearch.IsProjectFile(FileName) then
  begin
    Exit;
  end;
  mName := FileName;
  // Keine Exception an die IDE (#493).
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      mOwner.Closing(mName);
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
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasUnsavedOptions.Create(mSettings.WelcomePageUnsavedMinAgeHours, mSettings.WelcomePageUnsavedWarnHours,
    mSettings.WelcomePageUnsavedAlertHours);
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
  mServices: IOTAServices;
  mKeep: IAtlasUnsavedSource;
begin
  FStopped := False;
  mKeep := Self;
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.cUnsaved,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeUnsavedFrame;
    begin
      Frame := TAtlasWelcomeUnsavedFrame.Create(AOwner);
      Frame.Source := mKeep;
      Result := Frame;
    end);
  TAtlasWelcomeSections.Default.Add(Section);
  if (FNotifier = nil) and Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    FNotifier := TIdeNotifier.Create;
    FNotifier.FOwner := Self;
    FNotifierIndex := mServices.AddNotifier(FNotifier);
  end;
end;

procedure TAtlasIdeUnsaved.Stop;
var
  mServices: IOTAServices;
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
    if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, mServices) then
    begin
      mServices.RemoveNotifier(FNotifierIndex);
    end;
    FNotifier := nil;
    FNotifierIndex := -1;
  end;
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.cUnsaved);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.cUnsaved);
end;

function TAtlasIdeUnsaved.Section: TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.cUnsaved,
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedTitle), cOrder, TAtlasWelcomeColumn.Right,
    function: Boolean
    begin
      Result := IsVisible;
    end);
end;

function TAtlasIdeUnsaved.IsVisible: Boolean;
var
  mSettings: TAtlasPluginSettings;
  mKeep: IAtlasUnsavedSource;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.WelcomePageUnsaved and not FStopped;
  if Result and mSettings.WelcomePageUnsavedHideWhenClean then
  begin
    Result := not CurrentView.Clean;
    // Ausgeblendet gibt es kein „Shown“: neue Arbeit trotzdem bemerken (je Projekt höchstens einmal je Minute).
    if not Result then
    begin
      // Keep hält die Quelle bis zum Aufruf am Leben.
      mKeep := Self;
      TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
        procedure
        begin
          if mKeep <> nil then
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
  mSettings: TAtlasPluginSettings;
begin
  if FStopped then
  begin
    Exit;
  end;
  mSettings := TAtlasIdeSettings.Current;
  // Mit hideWhenClean kann der Bereich erscheinen oder verschwinden: dann neu einrichten.
  if mSettings.WelcomePageUnsaved and mSettings.WelcomePageUnsavedHideWhenClean and
    (FVisible = CurrentView.Clean) then
  begin
    TAtlasWelcomeSections.Default.Changed;
  end
  else
  begin
    TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.cUnsaved);
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
  mRecent: TArray<string>;
  mEntries: TAtlasProjectEntries;
  mEntry: TAtlasProjectEntry;
  mItem: TAtlasUnsavedProject;
  mKey, mRoot: string;
  mState: TAtlasUnsavedState;
begin
  Result := nil;
  if FStopped then
  begin
    Exit;
  end;
  mRecent := nil;
  try
    mRecent := TAtlasIdeWelcomeSearch.ClosedProjects;
  except
    // Registry nicht lesbar: leere Liste statt eines Fehlers in der Willkommensseite.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
  mRoot := TAtlasIdeProjectSummaries.Folder;
  // Dieselbe Liste wie der Bereich „Projekte“ (#592).
  mEntries := TAtlasWelcomeProjects.Entries(mRecent,
    function(const AProject: string; out ASummary: TAtlasProjectSummary): Boolean
    begin
      Result := TAtlasProjectSummaries.Load(mRoot, AProject, ASummary);
    end,
    TAtlasIdeSettings.Current.WelcomePageMaxProjects);
  for mEntry in mEntries do
  begin
    mItem := Default(TAtlasUnsavedProject);
    mItem.Project := mEntry.Project;
    mKey := TAtlasProjectSummaries.NormalizedPath(mEntry.Project);
    if FLive.TryGetValue(mKey, mState) then
    begin
      mItem.State := mState;
      mItem.Fresh := True;
    end
    else if mEntry.HasSummary then
    begin
      TAtlasWelcomeUnsaved.Read(mEntry.Summary, mItem.State);
    end;
    mItem.Querying := Querying(mKey);
    Result := Result + [mItem];
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
  mItem: TAtlasUnsavedProject;
  mLast, mNow_: UInt64;
begin
  if FStopped or not TAtlasIdeSettings.Current.WelcomePageUnsaved then
  begin
    Exit;
  end;
  mNow_ := GetTickCount64;
  for mItem in Projects do
  begin
    if AForce or not FFresh.TryGetValue(TAtlasProjectSummaries.NormalizedPath(mItem.Project), mLast) or
      (mNow_ - mLast >= TAtlasWelcomeUnsaved.cRefreshMs) then
    begin
      Query(mItem.Project);
    end;
  end;
end;

function TAtlasIdeUnsaved.Querying(const AKey: string): Boolean;
var
  mStarted: UInt64;
begin
  // Eine Abfrage, die nicht binnen QueryLimitMs zurückkam, gilt als beendet.
  Result := FQuerying.TryGetValue(AKey, mStarted) and (GetTickCount64 >= mStarted) and
    (GetTickCount64 - mStarted < TAtlasWelcomeUnsaved.cQueryLimitMs);
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
      Result := GetTickCount64 - AStarted >= TAtlasWelcomeUnsaved.cTimeLimitMs;
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
  mKeep: IAtlasUnsavedSource;
  mKey, mProject, mDir, mRoot: string;
  mStamp: TDateTime;
  mOk: Boolean;
  mState: TAtlasUnsavedState;
  mStarted: UInt64;
  mQuery: TAtlasUnsavedQuery;
begin
  mKey := TAtlasProjectSummaries.NormalizedPath(AProject);
  if FStopped or Querying(mKey) then
  begin
    Exit;
  end;
  mStarted := GetTickCount64;
  FQuerying.AddOrSetValue(mKey, mStarted);
  mKeep := Self;
  mProject := AProject;
  mDir := ExtractFileDir(AProject);
  mRoot := TAtlasIdeProjectSummaries.Folder;
  mStamp := NowUtc;
  mOk := False;
  mState := TAtlasUnsavedState.Empty;
  // Anteile je External bzw. Submodul (#1292); im Hauptthread gelesen.
  mQuery := QueryFor(mDir, mStamp, mStarted, TAtlasIdeSettings.Current.VcsExternalsShow, FileTimeUtc);
  // Arbeit und Ergebnis teilen sich Ok und State; das Ergebnis kommt erst nach der Arbeit.
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      mOk := TAtlasWelcomeUnsaved.Probe(TAtlasIdeVcs.ForFolder(mDir, TAtlasWelcomeUnsaved.cCallTimeoutMs), mQuery,
        mState);
    end,
    procedure
    var
      Current: UInt64;
    begin
      // Keep hält die Quelle bis hierher am Leben.
      if (mKeep = nil) or FStopped then
      begin
        Exit;
      end;
      // Nur die eigene Abfrage beenden, nicht eine neuere nach Ablauf des Zeitlimits.
      if FQuerying.TryGetValue(mKey, Current) and (Current = mStarted) then
      begin
        FQuerying.Remove(mKey);
      end;
      FFresh.AddOrSetValue(mKey, GetTickCount64);
      if mOk then
      begin
        FLive.AddOrSetValue(mKey, MergeAndStore(mRoot, mProject, mKey, mState, mStamp, FLive));
      end;
      Changed;
    end) then
  begin
    // Nicht gestartet (Versionsverwaltung noch nicht bereit oder beendet): nicht bei jedem Zeichnen neu versuchen.
    FQuerying.Remove(mKey);
    FFresh.AddOrSetValue(mKey, GetTickCount64);
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
  mModules: IOTAModuleServices;
  mActions: IOTAActionServices;
begin
  if not FileExists(AProject) then
  begin
    Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsMissing, [AProject]));
    Exit;
  end;
  // Schon offen: nicht neu laden.
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) and (mModules.FindModule(AProject) <> nil) then
  begin
    Exit;
  end;
  if Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    mActions.OpenProject(AProject, True);
  end;
end;

procedure TAtlasIdeUnsaved.Show(const ARow: TAtlasUnsavedRow);
var
  mRow: TAtlasUnsavedRow;
begin
  mRow := ARow;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      OpenProject(mRow.Project);
      ShowFiles(mRow);
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
  for mIndex := 0 to Min(High(mStashes), TAtlasIdeUnsaved.cMaxStashes - 1) do
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
  mVcs := TAtlasIdeVcs.ForFolder(ADir, TAtlasIdeUnsaved.cActionTimeoutMs);
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
  mKeep: IAtlasUnsavedSource;
  mRow: TAtlasUnsavedRow;
  mDir: string;
  mEntries: TArray<TAtlasResultEntry>;
  mOutcome: TAtlasVcsOutcome;
begin
  mKeep := Self;
  mRow := ARow;
  mDir := ExtractFileDir(ARow.Project);
  mEntries := nil;
  mOutcome := TAtlasVcsOutcome.Failed;
  TAtlasIdeVcs.Run(
    procedure
    begin
      mOutcome := FilesOf(mDir, mRow.Item.Kind, mEntries);
    end,
    procedure
    var
      mTitle: TAtlasWelcomeTextId;
    begin
      if (mKeep = nil) or FStopped then
      begin
        Exit;
      end;
      if mOutcome <> TAtlasVcsOutcome.Ok then
      begin
        Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedQueryFailed,
          [mRow.Name, AtlasVcsOutcomeName(mOutcome)]));
        Exit;
      end;
      mTitle := TAtlasWelcomeTextId.WelcomeUnsavedChangesTitle;
      if mRow.Item.Kind = TAtlasUnsavedKind.Stashes then
      begin
        mTitle := TAtlasWelcomeTextId.WelcomeUnsavedStashTitle;
      end;
      TAtlasIdeResultsWindow.ShowEntries(TAtlasWelcomeStrings.Fmt(mTitle, [mRow.Name, Length(mEntries)]), mEntries);
    end);
end;

procedure TAtlasIdeUnsaved.Push(const ARow: TAtlasUnsavedRow);
var
  mKeep: IAtlasUnsavedSource;
  mRow: TAtlasUnsavedRow;
  mDir: string;
  mPlans: TArray<TAtlasUnsavedPush>;
  mOutcome: TAtlasVcsOutcome;
begin
  if FStopped or FPushing or not ARow.Item.CanPush then
  begin
    Exit;
  end;
  mKeep := Self;
  mRow := ARow;
  mDir := ExtractFileDir(ARow.Project);
  mPlans := nil;
  mOutcome := TAtlasVcsOutcome.Failed;
  FPushing := True;
  // Ziel und Commits frisch ermitteln (nur lokal); gepusht wird erst nach der Bestätigung.
  if not TAtlasIdeVcs.Run(
    procedure
    var
      Local: IAtlasVcsLocalWork;
    begin
      if Supports(TAtlasIdeVcs.ForFolder(mDir, cActionTimeoutMs), IAtlasVcsLocalWork, Local) then
      begin
        mOutcome := TAtlasWelcomeUnsaved.PushPlans(Local, mRow.Item, mPlans);
      end;
    end,
    procedure
    begin
      FPushing := False;
      if (mKeep = nil) or FStopped then
      begin
        Exit;
      end;
      TAtlasGuard.Run(TAtlasFeature.WelcomePage,
        procedure
        begin
          if mOutcome <> TAtlasVcsOutcome.Ok then
          begin
            Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedQueryFailed, [mRow.Name,
              AtlasVcsOutcomeName(mOutcome)]));
          end
          else if Length(mPlans) = 0 then
          begin
            Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedPushNothing, [mRow.Name]));
          end
          else if TAtlasPushDialog.Confirm(mRow.Name, mPlans, nil) then
          begin
            RunPush(mRow, mPlans);
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
  if Supports(TAtlasIdeVcs.ForFolder(ADir, TAtlasWelcomeUnsaved.cPushTimeoutMs), IAtlasVcsLocalWork, mLocal) then
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
  mKeep: IAtlasUnsavedSource;
  mRow: TAtlasUnsavedRow;
  mPlans: TArray<TAtlasUnsavedPush>;
  mDir: string;
  mOutcomes: TArray<TAtlasVcsOutcome>;
begin
  mKeep := Self;
  mRow := ARow;
  mPlans := APlans;
  mDir := ExtractFileDir(ARow.Project);
  mOutcomes := nil;
  FPushing := True;
  TAtlasGuard.Log(Format('Willkommensseite: Push von %d Branch(es) bestätigt', [Length(mPlans)]));
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      mOutcomes := PushAll(mDir, mPlans);
    end,
    procedure
    var
      mIndex: Integer;
    begin
      FPushing := False;
      if (mKeep = nil) or FStopped then
      begin
        Exit;
      end;
      for mIndex := 0 to High(mPlans) do
      begin
        Report(PushReport(mRow.Name, mPlans, mOutcomes, mIndex));
      end;
      // Neuer Stand für die Zeile.
      FFresh.Remove(TAtlasProjectSummaries.NormalizedPath(mRow.Project));
      Query(mRow.Project);
    end) then
  begin
    FPushing := False;
  end;
end;

procedure TAtlasIdeUnsaved.OpenFolder(const ARow: TAtlasUnsavedRow);
var
  mProject: string;
begin
  mProject := ARow.Project;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if FileExists(mProject) then
      begin
        // Explorer mit markierter Projektdatei.
        ShellExecute(0, 'open', 'explorer.exe', PChar('/select,"' + mProject + '"'), nil, SW_SHOWNORMAL);
      end
      else if DirectoryExists(ExtractFileDir(mProject)) then
      begin
        ShellExecute(0, 'open', PChar(ExtractFileDir(mProject)), nil, nil, SW_SHOWNORMAL);
      end
      else
      begin
        Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsMissing, [mProject]));
      end;
    end);
end;

procedure TAtlasIdeUnsaved.Ignore(const ARow: TAtlasUnsavedRow);
var
  mRow: TAtlasUnsavedRow;
begin
  mRow := ARow;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Key: string;
      UntilUtc: TDateTime;
      State: TAtlasUnsavedState;
    begin
      Key := TAtlasProjectSummaries.NormalizedPath(mRow.Project);
      // Bis Mitternacht Ortszeit.
      UntilUtc := TTimeZone.Local.ToUniversalTime(TAtlasWelcomeUnsaved.Tomorrow(Now));
      TAtlasProjectSummaries.Update(TAtlasIdeProjectSummaries.Folder, mRow.Project,
        procedure(var ASummary: TAtlasProjectSummary)
        var
          Stored: TAtlasUnsavedState;
        begin
          TAtlasWelcomeUnsaved.Read(ASummary, Stored);
          TAtlasWelcomeUnsaved.Ignore(Stored, mRow.Item.Kind, UntilUtc);
          TAtlasWelcomeUnsaved.Write(ASummary, Stored);
        end);
      if FLive.TryGetValue(Key, State) then
      begin
        TAtlasWelcomeUnsaved.Ignore(State, mRow.Item.Kind, UntilUtc);
        FLive.AddOrSetValue(Key, State);
      end;
      Changed;
    end);
end;

end.
