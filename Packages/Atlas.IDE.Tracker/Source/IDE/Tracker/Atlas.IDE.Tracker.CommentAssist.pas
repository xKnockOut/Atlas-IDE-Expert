unit Atlas.IDE.Tracker.CommentAssist;

// Kommentar-Editor in der IDE (#1278): was TAtlasCommentEditor von der IDE
// bekommt (IAtlasCommentAssist), je Tracker, Issue und Feld.
// - Benutzer für "@": über IAtlasTrackerPeople des Anbieters (YouTrack
//   /api/users, GitHub zuweisbare Benutzer), höchstens MaxSuggestions, im
//   Hintergrund mit TimeoutMs; dieselbe Anfrage binnen CacheMs ohne Netz.
// - Issues für "#…" bzw. "ATL-…": wie die Befehlspalette (#1270, Search bzw.
//   Lookup); "ATL-" ohne Text zeigt die zuletzt geöffneten ohne Netz.
// - Platzhalter: {issue} = Kennung, {branch}/{commit} aus der
//   Versionsverwaltung des Projektordners (TAtlasIdeVcs.Run im Hintergrund),
//   {version} aus den Versionsinformationen des aktiven Projekts
//   (TAtlasIdeProjectContext.Version von Base, aktive Konfiguration und Plattform).
// - Entwürfe in <Zwischenspeicher>\drafts.json (TAtlasCommentDrafts); die
//   Datei liest der Dienst einmal und schreibt sie bei jeder Änderung atomar.
// - Eine neue Anfrage derselben Art ersetzt die alte, Cancel verwirft alle;
//   Antworten kommen im Hauptthread über TAtlasMainThread, nach Cancel oder
//   Stop nie.
// - issues.commentEditor aus: Assist liefert nil, das Feld bleibt einfach.
// - Protokoll anonym: Anbieter, Anzahl und Fehlerart, nie Suchtext, Kennung,
//   Kommentar oder Adresse.
// Anbieter, Transport, zuletzt geöffnete Issues und Projektordner kommen über
// Hooks („Meine Issues“).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.CommentEditor,
  Atlas.Core.Tracker.PaletteSearch;

type
  TAtlasCommentProviderHook = reference to function(const AName: string): IAtlasTrackerProvider;
  /// <summary>Transport mit dem Token aus dem Anmeldespeicher; nil ohne Token. Ohne Dialog.</summary>
  TAtlasCommentTransportHook = reference to function(const AProvider: IAtlasTrackerProvider;
    const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
  TAtlasCommentRecentHook = reference to function(const ATarget: TAtlasTrackerTarget): TArray<TAtlasTrackerIssue>;

  TAtlasCommentAssistHooks = record
    Provider: TAtlasCommentProviderHook;
    Transport: TAtlasCommentTransportHook;
    /// <summary>Zuletzt in der Vorschau geöffnete Issues.</summary>
    Recent: TAtlasCommentRecentHook;
    /// <summary>Ordner des Projekts für {branch} und {commit}; '' ohne Projekt.</summary>
    Folder: TFunc<string>;
  end;

  /// <summary>Dienst hinter allen Kommentarfeldern: Entwurfsdatei, Zwischenspeicher der Benutzer, Threads.
  /// </summary>
  TAtlasIdeCommentService = class(TInterfacedObject)
  public const
    cTimeoutMs = 5000;
    /// <summary>So lange gilt eine Benutzerliste für denselben Text.</summary>
    cCacheMs = 5 * 60 * 1000;
    cVcsTimeoutMs = 5000;
  private type
    TCachedUsers = record
      Users: TArray<TAtlasTrackerUser>;
      Tick: UInt64;
    end;
  private
    FHooks: TAtlasCommentAssistHooks;
    FStarted: Boolean;
    FFolder: string;
    FDrafts: TAtlasCommentDrafts;
    FDraftsLoaded: Boolean;
    FUsers: TDictionary<string, TCachedUsers>;
    FWorkers: TList<TThread>;
    function DraftFile: string;
    procedure LoadDrafts;
    procedure SaveDrafts;
    procedure ReleaseThreads(AWait: Boolean);
    procedure AddWorker(AThread: TThread);
    function CachedUsers(const AKey: string; out AUsers: TArray<TAtlasTrackerUser>): Boolean;
    procedure CacheUsers(const AKey: string; const AUsers: TArray<TAtlasTrackerUser>);
    function ProviderOf(const ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
    function TransportOf(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget):
      IAtlasCiTransport;
    function RecentOf(const ATarget: TAtlasTrackerTarget): TArray<TAtlasTrackerIssue>;
    function ProjectFolder: string;
    class function NowMs: UInt64; static;
  public
    /// <summary>ACacheFolder: Ordner der Entwurfsdatei ('' = nur im Speicher).</summary>
    constructor Create(const AHooks: TAtlasCommentAssistHooks; const ACacheFolder: string);
    destructor Destroy; override;
    /// <summary>Abbrechen, kurz auf die Threads warten, Hooks lösen; danach liefert Assist nil.</summary>
    procedure Stop;
    /// <summary>Für Tracker ATarget, Issue AKey und Feld AField (TAtlasCommentDrafts.Field…); nil mit
    /// issues.commentEditor aus oder nach Stop.</summary>
    function Assist(const ATarget: TAtlasTrackerTarget; const AKey, AField: string): IAtlasCommentAssist;
    /// <summary>Entwurf löschen, ohne dass ein Feld gebunden ist (Kommentar gesendet, Feld inzwischen bei
    /// einem anderen Issue).</summary>
    procedure DeleteDraft(const ATarget: TAtlasTrackerTarget; const AKey, AField: string);
    /// <summary>issues.commentEditor an?</summary>
    class function Active: Boolean; static;
  end;

  TAtlasIdeCommentAssist = class(TInterfacedObject, IAtlasCommentAssist)
  private
    FService: TAtlasIdeCommentService;
    FServiceRef: IInterface;
    FTarget: TAtlasTrackerTarget;
    FKey: string;
    FField: string;
    FUserGeneration: Integer;
    FIssueGeneration: Integer;
    FValueGeneration: Integer;
    FUserCancel: IAtlasCiCancel;
    FIssueCancel: IAtlasCiCancel;
    procedure CancelUsers;
    procedure CancelIssues;
    procedure UsersAnswered(AGeneration: Integer; const AKey: string; ASucceeded: Boolean;
      const AUsers: TArray<TAtlasTrackerUser>; AError: TAtlasCiFetchError; const ADone: TAtlasCommentUsersDone);
    procedure IssuesAnswered(AGeneration: Integer; ASucceeded: Boolean; const AIssues: TArray<TAtlasTrackerIssue>;
      AError: TAtlasCiFetchError; const ADone: TAtlasCommentIssuesDone);
    procedure ValuesAnswered(AGeneration: Integer; const AValues: TAtlasCommentValues;
      const ADone: TAtlasCommentValuesDone);
    function Alive: Boolean;
    function VersionValue: string;
  public
    constructor Create(AService: TAtlasIdeCommentService; const ATarget: TAtlasTrackerTarget;
      const AKey, AField: string);
    destructor Destroy; override;
    { IAtlasCommentAssist }
    function Target: TAtlasTrackerTarget;
    function Snippets: TArray<TAtlasCommentSnippet>;
    procedure FindUsers(const AText: string; const ADone: TAtlasCommentUsersDone);
    procedure FindIssues(const AQuery: TAtlasIssueSearchQuery; const ADone: TAtlasCommentIssuesDone);
    procedure Values(const ADone: TAtlasCommentValuesDone);
    procedure Cancel;
    function LoadDraft(out AText: string; out ASaved: TDateTime): Boolean;
    procedure SaveDraft(const AText: string);
    procedure DeleteDraft;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  System.DateUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Files.DataFile,
  Atlas.Core.VersionControl.Contract,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Projects.Context,
  Atlas.IDE.Contracts.VersionControl,
  Atlas.UI.Tracker.Strings;

{ TAtlasIdeCommentService }

constructor TAtlasIdeCommentService.Create(const AHooks: TAtlasCommentAssistHooks; const ACacheFolder: string);
begin
  inherited Create;
  FHooks := AHooks;
  FFolder := ACacheFolder;
  FStarted := True;
  FDrafts := TAtlasCommentDrafts.Create;
  FUsers := TDictionary<string, TCachedUsers>.Create;
  FWorkers := TList<TThread>.Create;
end;

destructor TAtlasIdeCommentService.Destroy;
begin
  Stop;
  ReleaseThreads(True);
  FWorkers.Free;
  FUsers.Free;
  FDrafts.Free;
  inherited;
end;

class function TAtlasIdeCommentService.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesCommentEditor;
end;

class function TAtlasIdeCommentService.NowMs: UInt64;
begin
  Result := GetTickCount64;
end;

procedure TAtlasIdeCommentService.Stop;
begin
  if not FStarted then
  begin
    Exit;
  end;
  FStarted := False;
  ReleaseThreads(True);
  FUsers.Clear;
  FHooks := Default(TAtlasCommentAssistHooks);
end;

procedure TAtlasIdeCommentService.ReleaseThreads(AWait: Boolean);
var
  mIndex: Integer;
  mThread: TThread;
  mWait: TArray<TThread>;
begin
  if AWait then
  begin
    mWait := nil;
    for mIndex := 0 to FWorkers.Count - 1 do
    begin
      mWait := mWait + [FWorkers[mIndex]];
    end;
    if Length(mWait) > 0 then
    begin
      TAtlasShutdown.WaitForThreads(mWait);
    end;
  end;
  for mIndex := FWorkers.Count - 1 downto 0 do
  begin
    mThread := FWorkers[mIndex];
    if mThread.Finished then
    begin
      mThread.Free;
      FWorkers.Delete(mIndex);
    end
    else if AWait then
    begin
      // Läuft noch (Zeitgrenze): räumt sich selbst auf.
      mThread.FreeOnTerminate := True;
      FWorkers.Delete(mIndex);
    end;
  end;
end;

procedure TAtlasIdeCommentService.AddWorker(AThread: TThread);
begin
  ReleaseThreads(False);
  AThread.FreeOnTerminate := False;
  FWorkers.Add(AThread);
  AThread.Start;
end;

function TAtlasIdeCommentService.DraftFile: string;
begin
  Result := '';
  if FFolder <> '' then
  begin
    Result := TPath.Combine(FFolder, TAtlasCommentDrafts.cFileName);
  end;
end;

procedure TAtlasIdeCommentService.LoadDrafts;
begin
  if FDraftsLoaded then
  begin
    Exit;
  end;
  FDraftsLoaded := True;
  if DraftFile <> '' then
  begin
    FDrafts.LoadFromFile(DraftFile);
  end;
end;

procedure TAtlasIdeCommentService.SaveDrafts;
begin
  if DraftFile = '' then
  begin
    Exit;
  end;
  try
    FDrafts.SaveToFile(DraftFile);
  except
    // Die Entwürfe bleiben im Speicher; der Grund steht einmal im Protokoll.
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(FDrafts.Kind, E);
  end;
end;

procedure TAtlasIdeCommentService.DeleteDraft(const ATarget: TAtlasTrackerTarget; const AKey, AField: string);
begin
  LoadDrafts;
  if FDrafts.Delete(TAtlasCommentDrafts.TrackerKey(ATarget), AKey, AField) then
  begin
    SaveDrafts;
  end;
end;

function TAtlasIdeCommentService.CachedUsers(const AKey: string; out AUsers: TArray<TAtlasTrackerUser>): Boolean;
var
  mEntry: TCachedUsers;
begin
  AUsers := nil;
  Result := FUsers.TryGetValue(AKey, mEntry) and (NowMs - mEntry.Tick < cCacheMs);
  if Result then
  begin
    AUsers := mEntry.Users;
  end;
end;

procedure TAtlasIdeCommentService.CacheUsers(const AKey: string; const AUsers: TArray<TAtlasTrackerUser>);
var
  mEntry: TCachedUsers;
begin
  if not FStarted then
  begin
    Exit;
  end;
  mEntry.Users := AUsers;
  mEntry.Tick := NowMs;
  FUsers.AddOrSetValue(AKey, mEntry);
end;

function TAtlasIdeCommentService.ProviderOf(const ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
begin
  Result := nil;
  if FStarted and Assigned(FHooks.Provider) then
  begin
    Result := FHooks.Provider(ATarget.Provider);
  end;
end;

function TAtlasIdeCommentService.TransportOf(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
begin
  Result := nil;
  if FStarted and (AProvider <> nil) and Assigned(FHooks.Transport) then
  begin
    Result := FHooks.Transport(AProvider, ATarget);
  end;
end;

function TAtlasIdeCommentService.RecentOf(const ATarget: TAtlasTrackerTarget): TArray<TAtlasTrackerIssue>;
begin
  Result := nil;
  if FStarted and Assigned(FHooks.Recent) then
  begin
    Result := FHooks.Recent(ATarget);
  end;
end;

function TAtlasIdeCommentService.ProjectFolder: string;
begin
  Result := '';
  if FStarted and Assigned(FHooks.Folder) then
  begin
    Result := FHooks.Folder();
  end;
end;

function TAtlasIdeCommentService.Assist(const ATarget: TAtlasTrackerTarget; const AKey, AField: string):
  IAtlasCommentAssist;
begin
  Result := nil;
  if FStarted and Active and (AKey <> '') then
  begin
    Result := TAtlasIdeCommentAssist.Create(Self, ATarget, AKey, AField);
  end;
end;

{ TAtlasIdeCommentAssist }

constructor TAtlasIdeCommentAssist.Create(AService: TAtlasIdeCommentService; const ATarget: TAtlasTrackerTarget;
  const AKey, AField: string);
begin
  inherited Create;
  FService := AService;
  // Der Dienst lebt, solange ein Feld ihn hält; nach Stop antwortet er nicht mehr.
  FServiceRef := AService;
  FTarget := ATarget;
  FKey := AKey;
  FField := AField;
end;

destructor TAtlasIdeCommentAssist.Destroy;
begin
  Cancel;
  FServiceRef := nil;
  inherited;
end;

function TAtlasIdeCommentAssist.Alive: Boolean;
begin
  Result := (FService <> nil) and FService.FStarted;
end;

function TAtlasIdeCommentAssist.Target: TAtlasTrackerTarget;
begin
  Result := FTarget;
end;

function TAtlasIdeCommentAssist.Snippets: TArray<TAtlasCommentSnippet>;
begin
  Result := TAtlasCommentSnippets.Read(TAtlasIdeSettings.Current.IssuesCommentSnippets, TAtlasTrackerStrings.English);
end;

procedure TAtlasIdeCommentAssist.CancelUsers;
begin
  Inc(FUserGeneration);
  if FUserCancel <> nil then
  begin
    FUserCancel.Cancel;
  end;
  FUserCancel := nil;
end;

procedure TAtlasIdeCommentAssist.CancelIssues;
begin
  Inc(FIssueGeneration);
  if FIssueCancel <> nil then
  begin
    FIssueCancel.Cancel;
  end;
  FIssueCancel := nil;
end;

procedure TAtlasIdeCommentAssist.Cancel;
begin
  CancelUsers;
  CancelIssues;
  Inc(FValueGeneration);
end;

type
  /// <summary>Eine Benutzerabfrage, wie sie in den Hintergrund geht.</summary>
  TUserJob = record
    Generation: Integer;
    CacheKey: string;
    Text: string;
    Target: TAtlasTrackerTarget;
    Transport: IAtlasCiTransport;
    People: IAtlasTrackerPeople;
  end;

/// <summary>Arbeit des Hintergrundthreads der Benutzerabfrage; die Antwort geht über den Hauptthread an AOwner,
/// solange AKeep ihn hält. Eigene Routine: Die anonyme Methode hält nur ihre Parameter.</summary>
function UsersWorker(AOwner: TAtlasIdeCommentAssist; const AKeep: IAtlasCommentAssist; const AJob: TUserJob;
  const ADone: TAtlasCommentUsersDone): TProc;
var
  mJob: TUserJob;
  mKeep: IAtlasCommentAssist;
begin
  mJob := AJob;
  mKeep := AKeep;
  Result :=
    procedure
    var
      mFound: TArray<TAtlasTrackerUser>;
      mError: TAtlasCiFetchError;
      mOk: Boolean;
    begin
      mFound := nil;
      mOk := False;
      mError := TAtlasCiFetchError.Network;
      try
        mOk := mJob.People.Users(TAtlasTrackerCall.Create(mJob.Target, mJob.Transport,
          TAtlasIdeCommentService.cTimeoutMs), mJob.Text, TAtlasCommentEditing.cMaxSuggestions, mFound, mError);
      except
        // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
        on E: Exception do
        begin
          mOk := False;
          mError := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Kommentar-Editor: Benutzerabfrage mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mJob.Transport := nil;
      mJob.People := nil;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.Tracker,
        procedure
        begin
          if mKeep <> nil then
          begin
            AOwner.UsersAnswered(mJob.Generation, mJob.CacheKey, mOk, mFound, mError, ADone);
          end;
        end);
    end;
end;

procedure TAtlasIdeCommentAssist.FindUsers(const AText: string; const ADone: TAtlasCommentUsersDone);
var
  mJob: TUserJob;
  mUsers: TArray<TAtlasTrackerUser>;
begin
  CancelUsers;
  mJob := Default(TUserJob);
  mJob.Generation := FUserGeneration;
  if not Alive then
  begin
    Exit;
  end;
  mJob.Text := AText;
  mJob.CacheKey := TAtlasCommentDrafts.TrackerKey(FTarget) + '|' + AnsiLowerCase(AText);
  // Rücktaste und neu getippt: dieselbe Liste ohne Netz.
  if FService.CachedUsers(mJob.CacheKey, mUsers) then
  begin
    ADone(mUsers);
    Exit;
  end;
  // Der Transport entsteht hier, damit die nächste Eingabe ihn abbrechen kann; er liest das Token ohne Dialog.
  if Supports(FService.ProviderOf(FTarget), IAtlasTrackerPeople, mJob.People) then
  begin
    mJob.Transport := FService.TransportOf(FService.ProviderOf(FTarget), FTarget);
  end;
  if mJob.Transport = nil then
  begin
    ADone(nil);
    Exit;
  end;
  if not Supports(mJob.Transport, IAtlasCiCancel, FUserCancel) then
  begin
    FUserCancel := nil;
  end;
  mJob.Target := FTarget;
  FService.AddWorker(TThread.CreateAnonymousThread(UsersWorker(Self, Self, mJob, ADone)));
end;

procedure TAtlasIdeCommentAssist.UsersAnswered(AGeneration: Integer; const AKey: string; ASucceeded: Boolean;
  const AUsers: TArray<TAtlasTrackerUser>; AError: TAtlasCiFetchError; const ADone: TAtlasCommentUsersDone);
begin
  if Alive then
  begin
    FService.ReleaseThreads(False);
  end;
  // Weitergetippt, abgebrochen oder Dienst beendet: diese Antwort zählt nicht.
  if not Alive or (AGeneration <> FUserGeneration) then
  begin
    Exit;
  end;
  FUserCancel := nil;
  if not ASucceeded then
  begin
    if AError <> TAtlasCiFetchError.Cancelled then
    begin
      TAtlasGuard.Log('Kommentar-Editor: Benutzer ' + FTarget.Provider + ' ohne Antwort (' +
        TAtlasCiBuild.ErrorKey(AError) + ')');
    end;
    ADone(nil);
    Exit;
  end;
  FService.CacheUsers(AKey, AUsers);
  ADone(AUsers);
end;

type
  /// <summary>Eine Issue-Suche, wie sie in den Hintergrund geht.</summary>
  TIssueJob = record
    Generation: Integer;
    Query: TAtlasIssueSearchQuery;
    Provider: IAtlasTrackerProvider;
    Target: TAtlasTrackerTarget;
    Transport: IAtlasCiTransport;
  end;

/// <summary>Issue zur Kennung bzw. Suche nach Text; False mit AError.</summary>
function FetchIssues(const AJob: TIssueJob; out AIssues: TArray<TAtlasTrackerIssue>;
  out AError: TAtlasCiFetchError): Boolean;
var
  mIssue: TAtlasTrackerIssue;
begin
  AIssues := nil;
  if AJob.Query.Kind <> TAtlasIssueSearchKind.Key then
  begin
    Exit(AJob.Provider.Search(TAtlasTrackerCall.Create(AJob.Target, AJob.Transport, TAtlasIdeCommentService.cTimeoutMs),
      AJob.Query.Text, TAtlasCommentEditing.cMaxSuggestions, AIssues, AError));
  end;
  Result := AJob.Provider.Lookup(AJob.Target, AJob.Transport, AJob.Query.Key, TAtlasIdeCommentService.cTimeoutMs,
    mIssue, AError);
  if Result then
  begin
    AIssues := [mIssue];
  end;
end;

/// <summary>Arbeit des Hintergrundthreads der Issue-Suche (siehe UsersWorker).</summary>
function IssuesWorker(AOwner: TAtlasIdeCommentAssist; const AKeep: IAtlasCommentAssist; const AJob: TIssueJob;
  const ADone: TAtlasCommentIssuesDone): TProc;
var
  mJob: TIssueJob;
  mKeep: IAtlasCommentAssist;
begin
  mJob := AJob;
  mKeep := AKeep;
  Result :=
    procedure
    var
      mIssues: TArray<TAtlasTrackerIssue>;
      mError: TAtlasCiFetchError;
      mOk: Boolean;
    begin
      mOk := False;
      mError := TAtlasCiFetchError.Network;
      try
        mOk := FetchIssues(mJob, mIssues, mError);
      except
        on E: Exception do
        begin
          mOk := False;
          mIssues := nil;
          mError := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Kommentar-Editor: Issue-Suche mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mJob.Transport := nil;
      mJob.Provider := nil;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.Tracker,
        procedure
        begin
          if mKeep <> nil then
          begin
            AOwner.IssuesAnswered(mJob.Generation, mOk, mIssues, mError, ADone);
          end;
        end);
    end;
end;

procedure TAtlasIdeCommentAssist.FindIssues(const AQuery: TAtlasIssueSearchQuery;
  const ADone: TAtlasCommentIssuesDone);
var
  mJob: TIssueJob;
begin
  CancelIssues;
  mJob := Default(TIssueJob);
  mJob.Generation := FIssueGeneration;
  if not Alive then
  begin
    Exit;
  end;
  case AQuery.Kind of
    TAtlasIssueSearchKind.None:
      begin
        ADone(nil);
        Exit;
      end;
    TAtlasIssueSearchKind.Recent:
      begin
        // Ohne Netz: die zuletzt in der Vorschau geöffneten.
        ADone(Copy(FService.RecentOf(FTarget), 0, TAtlasCommentEditing.cMaxSuggestions));
        Exit;
      end;
    TAtlasIssueSearchKind.Key, TAtlasIssueSearchKind.Text: ;
  end;
  mJob.Provider := FService.ProviderOf(FTarget);
  mJob.Transport := FService.TransportOf(mJob.Provider, FTarget);
  if mJob.Transport = nil then
  begin
    ADone(nil);
    Exit;
  end;
  if not Supports(mJob.Transport, IAtlasCiCancel, FIssueCancel) then
  begin
    FIssueCancel := nil;
  end;
  mJob.Target := FTarget;
  mJob.Query := AQuery;
  FService.AddWorker(TThread.CreateAnonymousThread(IssuesWorker(Self, Self, mJob, ADone)));
end;

procedure TAtlasIdeCommentAssist.IssuesAnswered(AGeneration: Integer; ASucceeded: Boolean;
  const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError; const ADone: TAtlasCommentIssuesDone);
begin
  if Alive then
  begin
    FService.ReleaseThreads(False);
  end;
  if not Alive or (AGeneration <> FIssueGeneration) then
  begin
    Exit;
  end;
  FIssueCancel := nil;
  if not ASucceeded then
  begin
    if (AError <> TAtlasCiFetchError.Cancelled) and (AError <> TAtlasCiFetchError.NotFound) then
    begin
      TAtlasGuard.Log('Kommentar-Editor: Issue-Suche ' + FTarget.Provider + ' ohne Antwort (' +
        TAtlasCiBuild.ErrorKey(AError) + ')');
    end;
    ADone(nil);
    Exit;
  end;
  ADone(AIssues);
end;

function TAtlasIdeCommentAssist.VersionValue: string;
var
  mModules: IOTAModuleServices;
  mProject: IOTAProject;
begin
  // Version des aktiven Projekts in der aktiven Konfiguration und Plattform; '' ohne Versionsinformationen.
  Result := '';
  mProject := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    mProject := mModules.GetActiveProject;
  end;
  if mProject = nil then
  begin
    Exit;
  end;
  Result := TAtlasIdeProjectContext.Version(mProject, mProject.CurrentConfiguration, mProject.CurrentPlatform);
end;

procedure TAtlasIdeCommentAssist.Values(const ADone: TAtlasCommentValuesDone);
var
  mValues: TAtlasCommentValues;
  mFolder: string;
  mGeneration: Integer;
  mKeep: IAtlasCommentAssist;
  mOwner: TAtlasIdeCommentAssist;
begin
  Inc(FValueGeneration);
  mGeneration := FValueGeneration;
  if not Alive then
  begin
    Exit;
  end;
  // Kennung und Version sofort (Hauptthread, Open Tools API); Branch und Commit im Hintergrund.
  mValues := TAtlasCommentValues.Create(FKey, '', '', VersionValue);
  mFolder := FService.ProjectFolder;
  mKeep := Self;
  mOwner := Self;
  if (mFolder = '') or not TAtlasIdeVcs.Run(
    procedure
    var
      mVcs: IAtlasVersionControl;
      mHead: TAtlasVcsHead;
    begin
      mVcs := TAtlasIdeVcs.ForFolder(mFolder, TAtlasIdeCommentService.cVcsTimeoutMs);
      if (mVcs <> nil) and (mVcs.Head(mHead) = TAtlasVcsOutcome.Ok) then
      begin
        mValues := TAtlasCommentValues.Create(mValues.Issue, mHead.Branch, mHead.ShortRevision(mVcs.Kind),
          mValues.Version);
      end;
    end,
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.ValuesAnswered(mGeneration, mValues, ADone);
      end;
    end) then
  begin
    ValuesAnswered(mGeneration, mValues, ADone);
  end;
end;

procedure TAtlasIdeCommentAssist.ValuesAnswered(AGeneration: Integer; const AValues: TAtlasCommentValues;
  const ADone: TAtlasCommentValuesDone);
begin
  if not Alive or (AGeneration <> FValueGeneration) then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.Tracker,
    procedure
    begin
      ADone(AValues);
    end);
end;

function TAtlasIdeCommentAssist.LoadDraft(out AText: string; out ASaved: TDateTime): Boolean;
begin
  AText := '';
  ASaved := 0;
  Result := False;
  if not Alive then
  begin
    Exit;
  end;
  FService.LoadDrafts;
  Result := FService.FDrafts.Get(TAtlasCommentDrafts.TrackerKey(FTarget), FKey, FField, AText, ASaved);
end;

procedure TAtlasIdeCommentAssist.SaveDraft(const AText: string);
begin
  if not Alive then
  begin
    Exit;
  end;
  FService.LoadDrafts;
  FService.FDrafts.Put(TAtlasCommentDrafts.TrackerKey(FTarget), FKey, FField, AText,
    TTimeZone.Local.ToUniversalTime(Now));
  FService.SaveDrafts;
end;

procedure TAtlasIdeCommentAssist.DeleteDraft;
begin
  if Alive then
  begin
    FService.DeleteDraft(FTarget, FKey, FField);
  end;
end;

end.
