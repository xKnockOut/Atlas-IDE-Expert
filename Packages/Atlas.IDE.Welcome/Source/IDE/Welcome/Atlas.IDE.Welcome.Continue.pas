unit Atlas.IDE.Welcome.Continue;

// Bereich „Weiterarbeiten“ in der IDE (#755): Quelle des Bereichs
// (IAtlasContinueSource), Anmeldung als Bereich atlas.continue der
// Willkommensseite (bzw. des Fensters „Atlas-Start“), Mitschreiben des
// Arbeitsstands und die Aktionen.
// - Mitschreiben (nur mit welcomePage.continue): EditorViewModified merkt je
//   Datei die letzte Änderungsstelle. Beim Schließen eines Projekts bzw. einer
//   Projektgruppe und beim Beenden der IDE gehen die offenen Reiter (Reihenfolge
//   aus den Beschriftungen des Editorfensters, sonst die der Puffer), der aktive
//   Reiter, die Änderungsstellen samt Methode (Gliederung), Zeitpunkt und der
//   zuletzt bekannte HEAD in den Abschnitt "continue" der
//   Projekt-Zusammenfassung (#592); Ziel ist die gespeicherte Projektgruppe,
//   sonst das Projekt. Die IDE schließt beim Schließen eines Projekts erst die
//   Dateien: Die Reiter werden deshalb beim ersten Schließen einer Datei
//   festgehalten und gelten für ein Projekt, das binnen BatchMs folgt. Ohne
//   offene Reiter bleibt der vorige Stand.
// - HEAD und verfolgter Branch (#571) kommen aus einer Abfrage im
//   Hintergrund beim Öffnen und höchstens einmal je Minute beim Arbeiten;
//   nach dem Schließen wird frisch abgefragt und nachgetragen.
// - Eingehende Commits (welcomePage.continue.incoming) für den obersten
//   Eintrag im Hintergrund beim Anzeigen, höchstens einmal je Minute; fetch nur
//   mit welcomePage.continue.fetch (5 s, ohne Rückfrage nach Zugangsdaten).
//   Klick auf einen Commit listet seine Dateien im Fenster „Atlas-Ergebnisse“
//   (#400); eine eigene Commit-Ansicht hat #571 nicht.
// - „Fortsetzen“ öffnet das Projekt, dann die Reiter in ihrer Reihenfolge mit
//   dem Cursor an der letzten Änderung und aktiviert zuletzt den zuvor aktiven
//   Reiter. Fehlende Dateien werden übersprungen und als Hinweis im Bereich und
//   in der Meldungsansicht genannt. Palettenbefehl Atlas.Continue setzt den
//   obersten Eintrag fort.
// - „Gemerkt“ (welcomePage.saved) liest nur Dateien: Notizen (#545),
//   Lesezeichen (#622) der zuletzt geöffneten Projekte (bei Projektgruppen
//   auch ihrer Projekte) und Favoriten (#458). Doppelklick öffnet das Projekt
//   und springt hin; ein Favorit springt zur Deklaration in der Unit, deren
//   Datei aus den Index-Caches auf der Platte kommt.
// - welcomePage.continue aus: kein Bereich, kein Mitschreiben, keine Abfrage.
// - Schnellaktionen (#764): Die Quelle der Knopfleiste (QuickActions, aus der
//   Composition) bekommt jeder Frame.
// - Editor und Projekte der IDE: Atlas.IDE.Welcome.Continue.Editor; „Gemerkt“:
//   Atlas.IDE.Welcome.Continue.Saved.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  ToolsAPI,
  DockForm,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Continue,
  Atlas.Core.Welcome.Saved,
  Atlas.UI.Welcome.QuickActions,
  Atlas.UI.Welcome.Continue,
  Atlas.IDE.Welcome.Continue.Editor;

type
  /// <summary>Was die Komposition dem Bereich mitgibt.</summary>
  TAtlasIdeContinueHooks = record
    /// <summary>Quelle der Schnellaktionen (#764) für neue Frames; nil = keine Knöpfe. Vor Start setzen.</summary>
    QuickActions: IAtlasQuickActionsSource;
    /// <summary>„Anmeldung am Server nötig – prüfen …“ (#1287): Seite Versionsverwaltung für den Ordner öffnen;
    /// nil = Link ohne Wirkung.</summary>
    OnServerAccess: TProc<string>;
  end;

  TAtlasIdeContinue = class(TInterfacedObject, IAtlasContinueSource)
  public const
    /// <summary>Reihenfolge außerhalb des Atlas-Layouts.</summary>
    cOrder = 15;
    /// <summary>So lange nach dem ersten Schließen einer Datei gelten die festgehaltenen Reiter.</summary>
    cBatchMs = 5000;
  private type
    TIdeNotifier = class(TNotifierObject, IOTAIDENotifier)
    private
      FOwner: TAtlasIdeContinue;
    public
      procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
      procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;
      procedure AfterCompile(Succeeded: Boolean); overload;
    end;

    TEditNotifier = class(TNotifierObject, INTAEditServicesNotifier)
    private
      FOwner: TAtlasIdeContinue;
    public
      procedure WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
      procedure WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
      procedure WindowActivated(const EditWindow: INTAEditWindow);
      procedure WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer; var Handled: Boolean);
      procedure EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
      procedure EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
      procedure DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
      procedure DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
      procedure DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
    end;

    /// <summary>Angemeldete Beobachter der IDE mit ihrem Index (-1 = keiner).</summary>
    TNotifiers = record
      Ide: TIdeNotifier;
      IdeIndex: Integer;
      Edit: TEditNotifier;
      EditIndex: Integer;
    end;

    /// <summary>Festgehaltene Reiter beim ersten Schließen einer Datei.</summary>
    TBatch = record
      Snapshot: TAtlasContinueSnapshot;
      /// <summary>GetTickCount64 des letzten Schließens einer Datei; 0 = nichts festgehalten.</summary>
      At: UInt64;
      /// <summary>GetTickCount64 des letzten geschriebenen Stands.</summary>
      LastWrite: UInt64;
    end;

    /// <summary>Normiertes Ziel → HEAD-Stand (VcsKind, Head, Upstream, UpstreamRevision) bzw. Zeitpunkt der
    /// letzten und der laufenden Abfrage.</summary>
    THeads = record
      States: TDictionary<string, TAtlasWorkState>;
      Fresh: TDictionary<string, UInt64>;
      Querying: TDictionary<string, UInt64>;
    end;

    /// <summary>Eingehende Commits zum obersten Eintrag.</summary>
    TIncomingState = record
      Data: TAtlasContinueIncoming;
      Key: string;
      Fresh: UInt64;
      Started: UInt64;
    end;
  private
    FMessage: TProc<string>;
    FNotifiers: TNotifiers;
    FStopped: Boolean;
    // Großgeschriebener Pfad → letzte Änderungsstelle dieser Sitzung.
    FChanges: TDictionary<string, TAtlasWorkTab>;
    FBatch: TBatch;
    FHeads: THeads;
    FIncoming: TIncomingState;
    FNotice: string;
    procedure Changed;
    function Enabled: Boolean;
    function Recording: Boolean;
    procedure Modified(const AView: IOTAEditView);
    procedure Activated;
    procedure SourceClosing;
    procedure ProjectOpened(const AFileName: string);
    procedure ProjectClosing(const AFileName: string);
    procedure WriteState(const ATarget: string; const ASnapshot: TAtlasContinueSnapshot; AProbe: Boolean);
    procedure QueryHead(const ATarget: string; AStamp: TDateTime);
    procedure RefreshIncoming(AForce: Boolean);
    procedure OpenFavorite(const AItem: TAtlasSavedItem);
  public
    /// <summary>Quelle der Schnellaktionen und Seite Versionsverwaltung; setzt die Komposition.</summary>
    Hooks: TAtlasIdeContinueHooks;
    /// <summary>AMessage: Zeile in die Meldungsansicht.</summary>
    constructor Create(const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Bereich, Fabrik und Beobachter der IDE anmelden.</summary>
    procedure Start;
    /// <summary>Stand des offenen Projekts schreiben (Beenden der IDE), alles abmelden; danach wirkungslos.</summary>
    procedure Stop;
    function Section: TAtlasWelcomeSection;
    /// <summary>Palettenbefehl Atlas.Continue: obersten Arbeitsstand fortsetzen.</summary>
    procedure ResumeLatest;
    { IAtlasContinueSource }
    function Entries: TAtlasContinueEntries;
    function Incoming: TAtlasContinueIncoming;
    function IncomingQuerying: Boolean;
    function SavedEnabled: Boolean;
    function Saved: TAtlasSavedItems;
    function Notice: string;
    procedure Resume(const AProject: string);
    procedure ShowCommit(const AProject: string; const ACommit: TAtlasContinueCommit);
    procedure OpenSaved(const AItem: TAtlasSavedItem);
    procedure ShowServerAccess(const AProject: string);
    procedure Shown;
  end;

implementation

uses
  Winapi.Windows,
  System.DateUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Results.Model,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Welcome.Search,
  Atlas.UI.Welcome.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.IDE.Contracts.VersionControl,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Welcome.Neighbors,
  Atlas.IDE.Welcome.Search,
  Atlas.IDE.Projects.Summaries,
  Atlas.IDE.Welcome.Continue.Saved;

type
  /// <summary>Eine HEAD-Abfrage im Hintergrund: Ziel, normierter Schlüssel, Ordner der Zusammenfassungen,
  /// Beginn (GetTickCount64) und Zeitstempel des eben geschriebenen Stands (0 = nichts nachtragen).</summary>
  THeadQuery = record
    Key: string;
    Target: string;
    Root: string;
    Started: UInt64;
    Stamp: TDateTime;
  end;

  /// <summary>Eine Abfrage eingehender Commits zum obersten Eintrag.</summary>
  TIncomingQuery = record
    Key: string;
    Project: string;
    Dir: string;
    MainBranch: string;
    State: TAtlasWorkState;
    Fetch: Boolean;
    Stamp: TDateTime;
    Started: UInt64;
  end;

{ TAtlasIdeContinue.TIdeNotifier }

procedure TAtlasIdeContinue.TIdeNotifier.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string;
  var Cancel: Boolean);
var
  mOwner: TAtlasIdeContinue;
  mName: string;
  mCode: TOTAFileNotification;
begin
  mOwner := FOwner;
  if (mOwner = nil) or not ((NotifyCode = ofnFileOpened) or (NotifyCode = ofnFileClosing)) then
  begin
    Exit;
  end;
  mName := FileName;
  mCode := NotifyCode;
  // Keine Exception an die IDE (#493).
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if not TAtlasWelcomeSearch.IsProjectFile(mName) then
      begin
        if mCode = ofnFileClosing then
        begin
          mOwner.SourceClosing;
        end;
      end
      else if mCode = ofnFileOpened then
      begin
        mOwner.ProjectOpened(mName);
      end
      else
      begin
        mOwner.ProjectClosing(mName);
      end;
    end);
end;

procedure TAtlasIdeContinue.TIdeNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TAtlasIdeContinue.TIdeNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

{ TAtlasIdeContinue.TEditNotifier }

procedure TAtlasIdeContinue.TEditNotifier.WindowShow(const EditWindow: INTAEditWindow; Show,
  LoadedFromDesktop: Boolean);
begin
end;

procedure TAtlasIdeContinue.TEditNotifier.WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
begin
end;

procedure TAtlasIdeContinue.TEditNotifier.WindowActivated(const EditWindow: INTAEditWindow);
begin
end;

procedure TAtlasIdeContinue.TEditNotifier.WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer;
  var Handled: Boolean);
begin
end;

procedure TAtlasIdeContinue.TEditNotifier.EditorViewActivated(const EditWindow: INTAEditWindow;
  const EditView: IOTAEditView);
var
  mOwner: TAtlasIdeContinue;
begin
  mOwner := FOwner;
  if mOwner = nil then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      mOwner.Activated;
    end);
end;

procedure TAtlasIdeContinue.TEditNotifier.EditorViewModified(const EditWindow: INTAEditWindow;
  const EditView: IOTAEditView);
var
  mOwner: TAtlasIdeContinue;
  mView: IOTAEditView;
begin
  mOwner := FOwner;
  if (mOwner = nil) or (EditView = nil) then
  begin
    Exit;
  end;
  mView := EditView;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      mOwner.Modified(mView);
    end);
end;

procedure TAtlasIdeContinue.TEditNotifier.DockFormVisibleChanged(const EditWindow: INTAEditWindow;
  DockForm: TDockableForm);
begin
end;

procedure TAtlasIdeContinue.TEditNotifier.DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TAtlasIdeContinue.TEditNotifier.DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

{ Hilfen }

function NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

function Key(const APath: string): string;
begin
  Result := TAtlasProjectSummaries.NormalizedPath(APath);
end;

procedure Report(ASelf: TAtlasIdeContinue; const AText: string);
begin
  if Assigned(ASelf.FMessage) then
  begin
    ASelf.FMessage(AText);
  end;
end;

function IncomingRunning(ASelf: TAtlasIdeContinue): Boolean;
begin
  Result := (ASelf.FIncoming.Started > 0) and
    (GetTickCount64 - ASelf.FIncoming.Started < TAtlasWelcomeContinue.cQueryLimitMs);
  if not Result then
  begin
    ASelf.FIncoming.Started := 0;
  end;
end;

/// <summary>Oberster Eintrag; leer ohne.</summary>
function Top(ASelf: TAtlasIdeContinue): TAtlasContinueEntry;
var
  mList: TAtlasContinueEntries;
begin
  Result := Default(TAtlasContinueEntry);
  mList := ASelf.Entries;
  if Length(mList) > 0 then
  begin
    Result := mList[0];
  end;
end;

/// <summary>HEAD aus AHead in AState übernehmen.</summary>
procedure TakeHead(var AState: TAtlasWorkState; const AHead: TAtlasWorkState);
begin
  AState.VcsKind := AHead.VcsKind;
  AState.Head := AHead.Head;
  AState.Upstream := AHead.Upstream;
  AState.UpstreamRevision := AHead.UpstreamRevision;
end;

/// <summary>Nach dem Schließen: HEAD in den eben geschriebenen Stand nachtragen (nur, wenn es noch derselbe ist).
/// </summary>
procedure StoreHead(const AQuery: THeadQuery; const AHead: TAtlasWorkState);
var
  mStamp: TDateTime;
  mHead: TAtlasWorkState;
begin
  mStamp := AQuery.Stamp;
  mHead := AHead;
  TAtlasProjectSummaries.Update(AQuery.Root, AQuery.Target,
    procedure(var ASummary: TAtlasProjectSummary)
    var
      mStored: TAtlasWorkState;
    begin
      if not TAtlasWelcomeContinue.Read(ASummary, mStored) or (Abs(mStored.At - mStamp) > OneSecond) then
      begin
        Exit;
      end;
      TakeHead(mStored, mHead);
      TAtlasWelcomeContinue.Write(ASummary, mStored);
    end);
end;

/// <summary>Ergebnis einer HEAD-Abfrage im Hauptthread.</summary>
procedure HeadArrived(ASelf: TAtlasIdeContinue; const AQuery: THeadQuery; AOk: Boolean;
  const AHead: TAtlasWorkState);
var
  mCurrent: UInt64;
begin
  if ASelf.FHeads.Querying.TryGetValue(AQuery.Key, mCurrent) and (mCurrent = AQuery.Started) then
  begin
    ASelf.FHeads.Querying.Remove(AQuery.Key);
  end;
  ASelf.FHeads.Fresh.AddOrSetValue(AQuery.Key, GetTickCount64);
  if not AOk then
  begin
    Exit;
  end;
  ASelf.FHeads.States.AddOrSetValue(AQuery.Key, AHead);
  if AQuery.Stamp > 0 then
  begin
    StoreHead(AQuery, AHead);
    ASelf.Changed;
  end;
end;

/// <summary>Hauptbranch des Projekts (#1286) für Branches ohne verfolgten Branch; .atlas und Gruppe im
/// Hauptthread.</summary>
function MainBranchFor(const AProject: string): string;
begin
  if SameText(ExtractFileExt(AProject), '.groupproj') then
  begin
    Result := TAtlasIdeVcs.MainBranchOf(AProject, AProject);
  end
  else
  begin
    Result := TAtlasIdeVcs.MainBranchOf(AProject, TAtlasIdeFiles.GroupOfProject(AProject));
  end;
end;

/// <summary>Abfrage eingehender Commits für den obersten Eintrag fällig (AEntry); nicht bei laufender Abfrage
/// oder (ohne AForce) frischem Ergebnis.</summary>
function IncomingDue(ASelf: TAtlasIdeContinue; AForce: Boolean; out AEntry: TAtlasContinueEntry): Boolean;
begin
  AEntry := Default(TAtlasContinueEntry);
  Result := ASelf.Enabled and TAtlasIdeSettings.Current.WelcomePageContinueIncoming and not IncomingRunning(ASelf);
  if Result then
  begin
    AEntry := Top(ASelf);
    Result := AEntry.Project <> '';
  end;
  if Result and not AForce and (Key(AEntry.Project) = ASelf.FIncoming.Key) and (ASelf.FIncoming.Fresh > 0) then
  begin
    Result := GetTickCount64 - ASelf.FIncoming.Fresh >= TAtlasWelcomeContinue.cRefreshMs;
  end;
end;

/// <summary>Im Hintergrund: eingehende Commits abfragen; fetch mit eigenem Zeitlimit, Zugangsdaten fragt der
/// Anbieter nie ab.</summary>
function ProbeIncoming(const AQuery: TIncomingQuery; out AFound: TAtlasContinueIncoming): Boolean;
var
  mFetchVcs: IAtlasVersionControl;
begin
  mFetchVcs := nil;
  if AQuery.Fetch then
  begin
    mFetchVcs := TAtlasIdeVcs.ForFolder(AQuery.Dir, TAtlasWelcomeContinue.cFetchTimeoutMs);
  end;
  Result := TAtlasWelcomeContinue.ProbeIncoming(TAtlasIdeVcs.ForFolder(AQuery.Dir,
    TAtlasWelcomeContinue.cCallTimeoutMs), mFetchVcs, TAtlasContinueProbe.Create(AQuery.Project, AQuery.MainBranch,
    AQuery.State, AQuery.Stamp), AFound);
end;

/// <summary>Ergebnis der Abfrage eingehender Commits im Hauptthread.</summary>
procedure IncomingArrived(ASelf: TAtlasIdeContinue; const AQuery: TIncomingQuery; AOk: Boolean;
  const AFound: TAtlasContinueIncoming);
begin
  if ASelf.FIncoming.Started = AQuery.Started then
  begin
    ASelf.FIncoming.Started := 0;
  end;
  if ASelf.FIncoming.Key <> AQuery.Key then
  begin
    Exit;
  end;
  ASelf.FIncoming.Fresh := GetTickCount64;
  ASelf.FIncoming.Data := AFound;
  if not AOk then
  begin
    // Fehler oder Zeitüberschreitung: kein Abschnitt.
    ASelf.FIncoming.Data := Default(TAtlasContinueIncoming);
    ASelf.FIncoming.Data.Project := AQuery.Project;
  end;
  ASelf.Changed;
end;

/// <summary>Gespeicherter Stand des Projekts AProject mit Reitern; sonst False mit Meldung.</summary>
function ResumeState(ASelf: TAtlasIdeContinue; const AProject: string; out AState: TAtlasWorkState): Boolean;
var
  mSummary: TAtlasProjectSummary;
begin
  Result := False;
  AState := TAtlasWorkState.Empty;
  if not ASelf.Enabled then
  begin
    Report(ASelf, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueDisabled));
  end
  else if not TAtlasProjectSummaries.Load(TAtlasIdeProjectSummaries.Folder, AProject, mSummary) or
    not TAtlasWelcomeContinue.Read(mSummary, AState) or (AState.TabCount = 0) then
  begin
    Report(ASelf, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueNothing));
  end
  else if not FileExists(AProject) then
  begin
    Report(ASelf, TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsMissing, [AProject]));
  end
  else
  begin
    Result := True;
  end;
end;

/// <summary>Hinweis auf fehlende Dateien beim Fortsetzen; '' ohne.</summary>
function MissingNotice(const AMissing: TArray<string>): string;
var
  mNames: TArray<string>;
  mName: string;
begin
  Result := '';
  if Length(AMissing) = 0 then
  begin
    Exit;
  end;
  mNames := nil;
  for mName in AMissing do
  begin
    mNames := mNames + [ExtractFileName(mName)];
  end;
  Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueMissing, [string.Join(', ', mNames)]);
end;

/// <summary>Einträge für „Atlas-Ergebnisse“: die Dateien des Commits, die eigenen zuerst.</summary>
function CommitEntries(const ACommit: TAtlasContinueCommit; const AFiles: TArray<string>): TArray<TAtlasResultEntry>;
var
  mFileName, mOwn: string;
  mMine: Boolean;
  mEntry: TAtlasResultEntry;
  mFirst, mRest: TArray<TAtlasResultEntry>;
begin
  mFirst := nil;
  mRest := nil;
  for mFileName in AFiles do
  begin
    mEntry := TAtlasResultEntry.Create(mFileName, 0, 0);
    mEntry.Text := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueCommitFile,
      [ACommit.Commit.ShortHash]);
    mMine := False;
    for mOwn in ACommit.Files do
    begin
      mMine := mMine or TAtlasWelcomeContinue.SameFile(mOwn, mFileName);
    end;
    if mMine then
    begin
      mFirst := mFirst + [mEntry];
    end
    else
    begin
      mRest := mRest + [mEntry];
    end;
  end;
  Result := mFirst + mRest;
end;

procedure ShowCommitEntries(const ACommit: TAtlasContinueCommit; const AEntries: TArray<TAtlasResultEntry>);
var
  mCommit: TAtlasContinueCommit;
  mEntries: TArray<TAtlasResultEntry>;
begin
  mCommit := ACommit;
  mEntries := AEntries;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      TAtlasIdeResultsWindow.ShowEntries(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueCommitTitle,
        [mCommit.Commit.ShortHash, mCommit.Commit.Summary, mCommit.Commit.Author, Length(mEntries)]), mEntries);
    end);
end;

/// <summary>Im Hintergrund: Dateien des Commits AHash beim Anbieter im Ordner ADir.</summary>
function CommitFiles(const ADir, AHash: string; out AFiles: TArray<string>): TAtlasVcsOutcome;
var
  mLocal: IAtlasVcsLocalWork;
  mChanges: TArray<TAtlasVcsChange>;
  mChange: TAtlasVcsChange;
begin
  AFiles := nil;
  Result := TAtlasVcsOutcome.Failed;
  if not Supports(TAtlasIdeVcs.ForFolder(ADir, TAtlasWelcomeContinue.cFetchTimeoutMs), IAtlasVcsLocalWork,
    mLocal) then
  begin
    Exit;
  end;
  Result := mLocal.ChangesIn(AHash, mChanges);
  for mChange in mChanges do
  begin
    AFiles := AFiles + [mChange.Path];
  end;
end;

{ TAtlasIdeContinue }

constructor TAtlasIdeContinue.Create(const AMessage: TProc<string>);
begin
  inherited Create;
  FMessage := AMessage;
  FNotifiers.IdeIndex := -1;
  FNotifiers.EditIndex := -1;
  FChanges := TDictionary<string, TAtlasWorkTab>.Create;
  FHeads.States := TDictionary<string, TAtlasWorkState>.Create;
  FHeads.Fresh := TDictionary<string, UInt64>.Create;
  FHeads.Querying := TDictionary<string, UInt64>.Create;
end;

destructor TAtlasIdeContinue.Destroy;
begin
  Stop;
  FHeads.Querying.Free;
  FHeads.Fresh.Free;
  FHeads.States.Free;
  FChanges.Free;
  inherited;
end;

procedure TAtlasIdeContinue.Start;
var
  mServices: IOTAServices;
  mEditors: IOTAEditorServices;
  mKeep: IAtlasContinueSource;
begin
  FStopped := False;
  mKeep := Self;
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.cContinue,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeContinueFrame;
    begin
      Frame := TAtlasWelcomeContinueFrame.Create(AOwner);
      Frame.Source := mKeep;
      // Schnellaktionen (#764): dieselbe Quelle für jeden Frame.
      Frame.QuickActions := Hooks.QuickActions;
      Result := Frame;
    end);
  TAtlasWelcomeSections.Default.Add(Section);
  if (FNotifiers.Ide = nil) and Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    FNotifiers.Ide := TIdeNotifier.Create;
    FNotifiers.Ide.FOwner := Self;
    FNotifiers.IdeIndex := mServices.AddNotifier(FNotifiers.Ide);
  end;
  if (FNotifiers.Edit = nil) and Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    FNotifiers.Edit := TEditNotifier.Create;
    FNotifiers.Edit.FOwner := Self;
    FNotifiers.EditIndex := mEditors.AddNotifier(FNotifiers.Edit);
  end;
  // Plugin nach dem Öffnen eines Projekts geladen: HEAD trotzdem kennen.
  if Recording then
  begin
    QueryHead(TAtlasIdeContinueEditor.CurrentTarget, 0);
  end;
end;

procedure TAtlasIdeContinue.Stop;
var
  mServices: IOTAServices;
  mEditors: IOTAEditorServices;
  mTarget: string;
begin
  if FStopped then
  begin
    Exit;
  end;
  // Beenden der IDE: Ist das Projekt noch offen (kein Schließen gemeldet), jetzt schreiben, ohne Abfrage.
  try
    if Recording and (GetTickCount64 - FBatch.LastWrite >= cBatchMs) then
    begin
      mTarget := TAtlasIdeContinueEditor.CurrentTarget;
      if mTarget <> '' then
      begin
        WriteState(mTarget, TAtlasIdeContinueEditor.TakeSnapshot(FChanges), False);
      end;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
  FStopped := True;
  Hooks.OnServerAccess := nil;
  if FNotifiers.Ide <> nil then
  begin
    FNotifiers.Ide.FOwner := nil;
    // RemoveNotifier gibt die Referenz der IDE frei und damit den Beobachter (#493).
    if (FNotifiers.IdeIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, mServices) then
    begin
      mServices.RemoveNotifier(FNotifiers.IdeIndex);
    end;
    FNotifiers.Ide := nil;
    FNotifiers.IdeIndex := -1;
  end;
  if FNotifiers.Edit <> nil then
  begin
    FNotifiers.Edit.FOwner := nil;
    if (FNotifiers.EditIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
    begin
      mEditors.RemoveNotifier(FNotifiers.EditIndex);
    end;
    FNotifiers.Edit := nil;
    FNotifiers.EditIndex := -1;
  end;
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.cContinue);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.cContinue);
  Hooks.QuickActions := nil;
end;

function TAtlasIdeContinue.Section: TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.cContinue,
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueTitle), cOrder, TAtlasWelcomeColumn.Left,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.WelcomePageContinue;
    end);
end;

function TAtlasIdeContinue.Enabled: Boolean;
begin
  Result := not FStopped and TAtlasIdeSettings.Current.WelcomePageContinue;
end;

function TAtlasIdeContinue.Recording: Boolean;
begin
  // Ohne Willkommensseite gibt es den Bereich nicht: dann auch nichts mitschreiben.
  Result := Enabled and TAtlasIdeSettings.Current.WelcomePage;
end;

procedure TAtlasIdeContinue.Changed;
begin
  if not FStopped then
  begin
    TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.cContinue);
  end;
end;

procedure TAtlasIdeContinue.Modified(const AView: IOTAEditView);
var
  mTab: TAtlasWorkTab;
begin
  if not Recording or (AView.Buffer = nil) or (AView.Buffer.FileName = '') then
  begin
    Exit;
  end;
  // Nur die Stelle merken (bei jedem Tastendruck): Methode erst beim Festhalten der Reiter.
  mTab := TAtlasWorkTab.Create(AView.Buffer.FileName, AView.CursorPos.Line, AView.CursorPos.Col);
  mTab.Changed := True;
  mTab.ChangedAt := NowUtc;
  FChanges.AddOrSetValue(AnsiUpperCase(mTab.FileName), mTab);
end;

procedure TAtlasIdeContinue.Activated;
var
  mTarget: string;
  mLast: UInt64;
begin
  // HEAD beim Arbeiten aktuell halten (höchstens einmal je Minute), damit er beim Beenden bekannt ist.
  if not Recording or not TAtlasIdeSettings.Current.WelcomePageContinueIncoming then
  begin
    Exit;
  end;
  mTarget := TAtlasIdeContinueEditor.CurrentTarget;
  if (mTarget = '') or (FHeads.Fresh.TryGetValue(Key(mTarget), mLast) and
    (GetTickCount64 - mLast < TAtlasWelcomeContinue.cRefreshMs)) then
  begin
    Exit;
  end;
  QueryHead(mTarget, 0);
end;

procedure TAtlasIdeContinue.SourceClosing;
begin
  if not Recording then
  begin
    Exit;
  end;
  // Erste Datei einer Folge: Reiter festhalten, solange sie noch alle offen sind.
  if (FBatch.At = 0) or (GetTickCount64 - FBatch.At >= cBatchMs) then
  begin
    FBatch.Snapshot := TAtlasIdeContinueEditor.TakeSnapshot(FChanges);
  end;
  FBatch.At := GetTickCount64;
end;

procedure TAtlasIdeContinue.ProjectOpened(const AFileName: string);
var
  mTarget: string;
begin
  if not Recording then
  begin
    Exit;
  end;
  mTarget := TAtlasIdeContinueEditor.TargetOf(AFileName);
  if mTarget <> '' then
  begin
    QueryHead(mTarget, 0);
  end;
end;

procedure TAtlasIdeContinue.ProjectClosing(const AFileName: string);
var
  mTarget: string;
  mSnapshot: TAtlasContinueSnapshot;
begin
  if not Recording then
  begin
    Exit;
  end;
  // Gruppe und ihre Projekte melden sich einzeln: einmal je Schließen schreiben.
  if (FBatch.LastWrite > 0) and (GetTickCount64 - FBatch.LastWrite < cBatchMs) then
  begin
    Exit;
  end;
  mTarget := TAtlasIdeContinueEditor.TargetOf(AFileName);
  if mTarget = '' then
  begin
    Exit;
  end;
  if (FBatch.At > 0) and (GetTickCount64 - FBatch.At < cBatchMs) then
  begin
    mSnapshot := FBatch.Snapshot;
  end
  else
  begin
    mSnapshot := TAtlasIdeContinueEditor.TakeSnapshot(FChanges);
  end;
  WriteState(mTarget, mSnapshot, True);
end;

procedure TAtlasIdeContinue.WriteState(const ATarget: string; const ASnapshot: TAtlasContinueSnapshot;
  AProbe: Boolean);
var
  mOld, mState, mHead: TAtlasWorkState;
  mSummary: TAtlasProjectSummary;
  mStamp: TDateTime;
  mRoot, mTargetKey: string;
begin
  // Ohne offene Reiter bleibt der vorige Stand (z. B. alles schon geschlossen).
  if Length(ASnapshot.Tabs) = 0 then
  begin
    Exit;
  end;
  mRoot := TAtlasIdeProjectSummaries.Folder;
  mTargetKey := Key(ATarget);
  mStamp := NowUtc;
  mOld := TAtlasWorkState.Empty;
  if TAtlasProjectSummaries.Load(mRoot, ATarget, mSummary) then
  begin
    TAtlasWelcomeContinue.Read(mSummary, mOld);
  end;
  mState := TAtlasWelcomeContinue.Build(ASnapshot.Tabs, ASnapshot.Active, FChanges.Values.ToArray, mOld, mStamp);
  if FHeads.States.TryGetValue(mTargetKey, mHead) then
  begin
    TakeHead(mState, mHead);
  end;
  TAtlasProjectSummaries.Update(mRoot, ATarget,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      TAtlasWelcomeContinue.Write(ASummary, mState);
    end);
  FBatch.LastWrite := GetTickCount64;
  FBatch.At := 0;
  FBatch.Snapshot := Default(TAtlasContinueSnapshot);
  // Neue Sitzung: Änderungen gehören zum geschriebenen Stand.
  FChanges.Clear;
  if FIncoming.Key = mTargetKey then
  begin
    FIncoming.Fresh := 0;
  end;
  // HEAD frisch abfragen und nachtragen; beim Beenden der IDE weder Abfrage noch neues Zeichnen.
  if not AProbe then
  begin
    Exit;
  end;
  QueryHead(ATarget, mStamp);
  Changed;
end;

procedure TAtlasIdeContinue.QueryHead(const ATarget: string; AStamp: TDateTime);
var
  mKeep: IAtlasContinueSource;
  mQuery: THeadQuery;
  mStarted: UInt64;
  mDir: string;
  mOk: Boolean;
  mHead: TAtlasWorkState;
begin
  if FStopped or (ATarget = '') then
  begin
    Exit;
  end;
  mQuery := Default(THeadQuery);
  mQuery.Key := Key(ATarget);
  if FHeads.Querying.TryGetValue(mQuery.Key, mStarted) and
    (GetTickCount64 - mStarted < TAtlasWelcomeContinue.cQueryLimitMs) then
  begin
    Exit;
  end;
  mQuery.Target := ATarget;
  mQuery.Root := TAtlasIdeProjectSummaries.Folder;
  mQuery.Started := GetTickCount64;
  mQuery.Stamp := AStamp;
  FHeads.Querying.AddOrSetValue(mQuery.Key, mQuery.Started);
  mKeep := Self;
  mDir := ExtractFileDir(ATarget);
  mOk := False;
  mHead := TAtlasWorkState.Empty;
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      mOk := TAtlasWelcomeContinue.ProbeHead(TAtlasIdeVcs.ForFolder(mDir, TAtlasWelcomeContinue.cCallTimeoutMs),
        mHead);
    end,
    procedure
    begin
      if (mKeep <> nil) and not FStopped then
      begin
        HeadArrived(Self, mQuery, mOk, mHead);
      end;
    end) then
  begin
    FHeads.Querying.Remove(mQuery.Key);
    FHeads.Fresh.AddOrSetValue(mQuery.Key, GetTickCount64);
  end;
end;

function TAtlasIdeContinue.Entries: TAtlasContinueEntries;
var
  mRecent: TArray<string>;
  mRoot: string;
begin
  Result := nil;
  if not Enabled then
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
  Result := TAtlasWelcomeContinue.Entries(mRecent,
    function(const AProject: string; out ASummary: TAtlasProjectSummary): Boolean
    begin
      Result := TAtlasProjectSummaries.Load(mRoot, AProject, ASummary);
    end,
    TAtlasIdeSettings.Current.WelcomePageContinueCount);
end;

function TAtlasIdeContinue.Incoming: TAtlasContinueIncoming;
var
  mEntry: TAtlasContinueEntry;
begin
  Result := Default(TAtlasContinueIncoming);
  if not Enabled or not TAtlasIdeSettings.Current.WelcomePageContinueIncoming then
  begin
    Exit;
  end;
  mEntry := Top(Self);
  if (mEntry.Project <> '') and (Key(mEntry.Project) = FIncoming.Key) and
    (Key(FIncoming.Data.Project) = FIncoming.Key) then
  begin
    Result := FIncoming.Data;
  end;
end;

function TAtlasIdeContinue.IncomingQuerying: Boolean;
var
  mEntry: TAtlasContinueEntry;
begin
  Result := False;
  if not Enabled or not TAtlasIdeSettings.Current.WelcomePageContinueIncoming or not IncomingRunning(Self) then
  begin
    Exit;
  end;
  mEntry := Top(Self);
  Result := (mEntry.Project <> '') and (Key(mEntry.Project) = FIncoming.Key);
end;

procedure TAtlasIdeContinue.Shown;
begin
  RefreshIncoming(False);
end;

procedure TAtlasIdeContinue.RefreshIncoming(AForce: Boolean);
var
  mKeep: IAtlasContinueSource;
  mEntry: TAtlasContinueEntry;
  mQuery: TIncomingQuery;
  mOk: Boolean;
  mFound: TAtlasContinueIncoming;
begin
  if not IncomingDue(Self, AForce, mEntry) then
  begin
    Exit;
  end;
  mKeep := Self;
  mQuery := Default(TIncomingQuery);
  mQuery.Key := Key(mEntry.Project);
  mQuery.Project := mEntry.Project;
  mQuery.State := mEntry.State;
  mQuery.Dir := ExtractFileDir(mEntry.Project);
  mQuery.MainBranch := MainBranchFor(mEntry.Project);
  mQuery.Fetch := TAtlasIdeSettings.Current.WelcomePageContinueFetch;
  mQuery.Stamp := NowUtc;
  mQuery.Started := GetTickCount64;
  mOk := False;
  mFound := Default(TAtlasContinueIncoming);
  FIncoming.Started := mQuery.Started;
  // Ein anderer oberster Eintrag: alte Commits nicht mehr zeigen.
  if mQuery.Key <> FIncoming.Key then
  begin
    FIncoming.Data := Default(TAtlasContinueIncoming);
  end;
  FIncoming.Key := mQuery.Key;
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      mOk := ProbeIncoming(mQuery, mFound);
    end,
    procedure
    begin
      if (mKeep <> nil) and not FStopped then
      begin
        IncomingArrived(Self, mQuery, mOk, mFound);
      end;
    end) then
  begin
    FIncoming.Started := 0;
    FIncoming.Fresh := GetTickCount64;
  end;
end;

function TAtlasIdeContinue.Notice: string;
begin
  Result := '';
  if Enabled then
  begin
    Result := FNotice;
  end;
end;

procedure TAtlasIdeContinue.Resume(const AProject: string);
var
  mProject: string;
begin
  mProject := AProject;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      State: TAtlasWorkState;
      Plan: TAtlasContinuePlan;
      Tab: TAtlasWorkTab;
    begin
      if not ResumeState(Self, mProject, State) then
      begin
        Exit;
      end;
      Plan := TAtlasWelcomeContinue.Plan(mProject, State,
        function(const AFileName: string): Boolean
        begin
          Result := FileExists(AFileName);
        end);
      FNotice := MissingNotice(Plan.Missing);
      if FNotice <> '' then
      begin
        Report(Self, FNotice);
      end;
      TAtlasIdeContinueEditor.EnsureProject(mProject);
      // Reiter in ihrer Reihenfolge; danach den zuvor aktiven noch einmal, damit er vorn liegt.
      for Tab in Plan.Open do
      begin
        TAtlasIdeContinueEditor.OpenTab(Tab);
      end;
      if (Plan.Active >= 0) and (Plan.Active <= High(Plan.Open)) then
      begin
        TAtlasIdeContinueEditor.OpenTab(Plan.Open[Plan.Active]);
      end;
      Changed;
    end);
end;

procedure TAtlasIdeContinue.ResumeLatest;
var
  mEntry: TAtlasContinueEntry;
begin
  if not Enabled then
  begin
    Report(Self, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueDisabled));
    Exit;
  end;
  mEntry := Top(Self);
  if mEntry.Project = '' then
  begin
    Report(Self, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueNothing));
    Exit;
  end;
  Resume(mEntry.Project);
end;

procedure TAtlasIdeContinue.ShowCommit(const AProject: string; const ACommit: TAtlasContinueCommit);
var
  mKeep: IAtlasContinueSource;
  mCommit: TAtlasContinueCommit;
  mDir: string;
  mFiles: TArray<string>;
  mOutcome: TAtlasVcsOutcome;
begin
  mCommit := ACommit;
  if Length(mCommit.Commit.Files) > 0 then
  begin
    ShowCommitEntries(mCommit, CommitEntries(mCommit, mCommit.Commit.Files));
    Exit;
  end;
  // Ohne Dateiliste (z. B. Merge): beim Anbieter nachfragen.
  mKeep := Self;
  mDir := ExtractFileDir(AProject);
  mFiles := nil;
  mOutcome := TAtlasVcsOutcome.Failed;
  TAtlasIdeVcs.Run(
    procedure
    begin
      mOutcome := CommitFiles(mDir, mCommit.Commit.Hash, mFiles);
    end,
    procedure
    begin
      if (mKeep = nil) or FStopped then
      begin
        Exit;
      end;
      if mOutcome <> TAtlasVcsOutcome.Ok then
      begin
        Report(Self, TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueCommitFailed,
          [mCommit.Commit.ShortHash, AtlasVcsOutcomeName(mOutcome)]));
        Exit;
      end;
      ShowCommitEntries(mCommit, CommitEntries(mCommit, mFiles));
    end);
end;

function TAtlasIdeContinue.SavedEnabled: Boolean;
begin
  Result := Enabled and TAtlasIdeSettings.Current.WelcomePageSaved;
end;

function TAtlasIdeContinue.Saved: TAtlasSavedItems;
begin
  Result := nil;
  if SavedEnabled then
  begin
    Result := TAtlasIdeContinueSaved.Items;
  end;
end;

procedure TAtlasIdeContinue.OpenFavorite(const AItem: TAtlasSavedItem);
var
  mFileName: string;
  mLine: Integer;
begin
  if not TAtlasIdeContinueSaved.FindFavorite(AItem, mFileName, mLine) then
  begin
    Report(Self, TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSavedUnitMissing, [AItem.Text, AItem.UnitName]));
    Exit;
  end;
  TAtlasIdeResults.Open(mFileName, mLine, 0);
end;

procedure TAtlasIdeContinue.ShowServerAccess(const AProject: string);
var
  mFolder: string;
begin
  mFolder := ExtractFileDir(AProject);
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if FStopped or not Assigned(Hooks.OnServerAccess) or (mFolder = '') then
      begin
        Exit;
      end;
      Hooks.OnServerAccess(mFolder);
      // Nach dem Dialog (vielleicht angemeldet): eingehende Commits neu abfragen.
      RefreshIncoming(True);
    end);
end;

procedure TAtlasIdeContinue.OpenSaved(const AItem: TAtlasSavedItem);
var
  mItem: TAtlasSavedItem;
begin
  mItem := AItem;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Line: Integer;
    begin
      if not SavedEnabled then
      begin
        Exit;
      end;
      if mItem.Kind = TAtlasSavedKind.Favorite then
      begin
        OpenFavorite(mItem);
        Exit;
      end;
      TAtlasIdeContinueEditor.EnsureProject(mItem.Project);
      if not FileExists(mItem.FileName) then
      begin
        Report(Self, TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSavedFileMissing, [mItem.FileName]));
        Exit;
      end;
      // Lesezeichen mit eingeschalteter Funktion: über #622 (findet die Stelle vor dem Sprung wieder).
      if (mItem.Kind = TAtlasSavedKind.Bookmark) and TAtlasWelcomeNeighbors.OpenBookmark(mItem.Project, mItem.Id) then
      begin
        Exit;
      end;
      Line := mItem.Line;
      if Line < 0 then
      begin
        Line := 0;
      end;
      TAtlasIdeResults.Open(mItem.FileName, Line, 0);
    end);
end;

end.
