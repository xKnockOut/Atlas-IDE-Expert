unit Atlas.IDE.Tracker.Development;

// Reiter „Entwicklung“ im Fenster „Atlas-Issue“ (#1269): Steuerung zwischen
// TAtlasIssueDevelopmentView und Versionsverwaltung bzw. Tracker.
// - Gesucht wird erst, wenn der Reiter sichtbar ist (bzw. beim Wechsel des
//   Issues mit sichtbarem Reiter), im Hintergrund: Log, Branches und Abstand
//   aus der Arbeitskopie des aktuellen Projekts (TAtlasIdeVcs.ForFolder),
//   dazu Pull Requests bzw. VCS-Änderungen vom Tracker. Ergebnis je Tracker
//   und Kennung im Speicher; „Aktualisieren“ fragt neu.
// - Klick auf einen Commit: Diff der Dateien (vorher/nachher) im Diff-Fenster
//   von Atlas; Doppelklick: erste geänderte Unit an der ersten geänderten
//   Zeile öffnen. Klick auf eine Unit öffnet sie.
// - „Wechseln“: mit lokalen Änderungen erst fragen; danach neu suchen.
// - issues.preview.development aus: Reiter fehlt, nichts wird abgefragt.
// - Eine Suche zur Zeit: Ein neuer Wunsch zählt, ältere Ergebnisse verfallen
//   (Generation); die Abfrage beim Tracker bricht „Abbrechen“ ab.
// - Protokoll anonym: nur Ergebnis, nie Kennung, Branch oder Pfad.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Development,
  Atlas.Core.Tracker.Preview,
  Atlas.Core.Vcs.Contract,
  Atlas.UI.Tracker.DevelopmentView,
  Atlas.UI.Tracker.IssueFrame;

type
  TAtlasIssueDevelopmentProviderHook = reference to function(const ATarget: TAtlasTrackerTarget):
    IAtlasTrackerProvider;
  /// <summary>Transport mit dem Token aus dem Anmeldespeicher, ohne Dialog; nil ohne Token.</summary>
  TAtlasIssueDevelopmentTransportHook = reference to function(const AProvider: IAtlasTrackerProvider;
    const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;

  TAtlasIssueDevelopmentHooks = record
    Provider: TAtlasIssueDevelopmentProviderHook;
    Transport: TAtlasIssueDevelopmentTransportHook;
    /// <summary>Projektdatei des aktuellen Projekts ('' ohne).</summary>
    Project: TFunc<string>;
    /// <summary>Seite im Browser öffnen (prüft die Adresse).</summary>
    Browse: TProc<string>;
    /// <summary>Frame des Fensters „Atlas-Issue“, falls angelegt.</summary>
    Frame: TFunc<TAtlasIssueFrame>;
  end;

  TAtlasIdeIssueDevelopment = class(TInterfacedObject)
  public const
    /// <summary>Zeitgrenze je Aufruf von git bzw. svn.</summary>
    VcsTimeoutMs = 10000;
    /// <summary>Zeitgrenze für den Tracker.</summary>
    TrackerTimeoutMs = 10000;
    /// <summary>Höchstens so viele Dateien im Diff eines Commits.</summary>
    MaxDiffFiles = 30;
  private
    FHooks: TAtlasIssueDevelopmentHooks;
    FCache: TAtlasIssueDevelopmentCache;
    FStarted: Boolean;
    FTarget: TAtlasTrackerTarget;
    FKey: string;
    FHasCurrent: Boolean;
    FShown: Boolean;
    FForce: Boolean;
    FGeneration: Integer;
    FThread: TThread;
    FCancel: IAtlasCiCancel;
    FWorkers: TList<TThread>;
    function View: TAtlasIssueDevelopmentView;
    function ProjectFile: string;
    procedure Load(AForce: Boolean);
    procedure Loaded(AGeneration: Integer; ANoProject: Boolean; const ADevelopment: TAtlasIssueDevelopment);
    procedure Show(const ADevelopment: TAtlasIssueDevelopment);
    procedure Notice(const AText: string);
    procedure ReleaseThreads(AWait: Boolean);
    procedure ShowDiff(const AEntry: TAtlasVcsLogEntry);
    procedure DiffLoaded(const AEntry: TAtlasVcsLogEntry; AOutcome: TAtlasVcsOutcome;
      const AFiles: TArray<TAtlasIssueFileDiff>);
    procedure OpenCommit(const AEntry: TAtlasVcsLogEntry);
    procedure OpenUnit(const AUnit: TAtlasIssueUnit);
    procedure SwitchBranch(const ABranch: TAtlasIssueBranch);
    procedure SwitchChecked(const ABranch: TAtlasIssueBranch; AChanges: Integer);
    procedure Switched(const ABranch: TAtlasIssueBranch; AOutcome: TAtlasVcsOutcome);
    function TrackerNote(const ADevelopment: TAtlasIssueDevelopment): string;
    class function NowUtc: TDateTime; static;
  public
    constructor Create(const AHooks: TAtlasIssueDevelopmentHooks);
    destructor Destroy; override;
    procedure Start;
    /// <summary>Abbrechen und kurz warten; danach wirkungslos.</summary>
    procedure Stop;
    /// <summary>Frame des Fensters anbinden (Schalter, Ereignisse der Ansicht).</summary>
    procedure Wire(AFrame: TAtlasIssueFrame);
    /// <summary>Anderes Issue im Fenster: sofort suchen, wenn der Reiter sichtbar ist.</summary>
    procedure Select(const ATarget: TAtlasTrackerTarget; const AKey: string);
    /// <summary>Reiter gewählt: suchen, wenn das Issue noch nicht gezeigt ist.</summary>
    procedure Shown;
    /// <summary>„Aktualisieren“: neu suchen, wenn der Reiter sichtbar ist, sonst beim nächsten Zeigen.</summary>
    procedure Refresh;
    /// <summary>„Abbrechen“ bzw. Fenster geschlossen.</summary>
    procedure Cancel;
    /// <summary>issues.preview.development an?</summary>
    class function Active: Boolean; static;
    /// <summary>Projekte der Projektgruppe mit ihren Dateien (Hauptthread).</summary>
    class function GroupProjects: TArray<TAtlasIssueProject>; static;
    /// <summary>Basis-Branches zum Vergleich: issues.branchBase, sonst main, master.</summary>
    class function Bases(const ABranchBase: string): TArray<string>; static;
    /// <summary>Inhalt einer Datei im Commit bzw. davor als Text (Kodierung erkannt).</summary>
    class function ReadContent(const AHistory: IAtlasVcsHistory; const ARevision: string;
      const AFile: TAtlasVcsLogFile; ABefore: Boolean; out AText: string): TAtlasVcsOutcome; static;
    /// <summary>Diff aller Dateien eines Commits (höchstens MaxDiffFiles, Text in der Arbeitskopie bzw. im
    /// Repository); im Hintergrund.</summary>
    class function CommitDiff(const AHistory: IAtlasVcsHistory; const AEntry: TAtlasVcsLogEntry;
      out AFiles: TArray<TAtlasIssueFileDiff>): TAtlasVcsOutcome; static;
  end;

implementation

uses
  ToolsAPI,
  System.DateUtils,
  System.UITypes,
  Vcl.Dialogs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.UI.Undo.DiffView,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Vcs.Service;

{ TAtlasIdeIssueDevelopment }

constructor TAtlasIdeIssueDevelopment.Create(const AHooks: TAtlasIssueDevelopmentHooks);
begin
  inherited Create;
  FHooks := AHooks;
  FCache := TAtlasIssueDevelopmentCache.Create;
  FWorkers := TList<TThread>.Create;
end;

destructor TAtlasIdeIssueDevelopment.Destroy;
begin
  ReleaseThreads(True);
  FWorkers.Free;
  FCache.Free;
  inherited;
end;

class function TAtlasIdeIssueDevelopment.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasIdeIssueDevelopment.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesPreviewDevelopment;
end;

class function TAtlasIdeIssueDevelopment.GroupProjects: TArray<TAtlasIssueProject>;
var
  mServices: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mProject: IOTAProject;
  mIndex, mModule: Integer;
  mFiles: TArray<string>;
  mName: string;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
    Exit;
  mGroup := mServices.MainProjectGroup;
  if mGroup = nil then
    Exit;
  for mIndex := 0 to mGroup.ProjectCount - 1 do
  begin
    mProject := mGroup.Projects[mIndex];
    if mProject = nil then
      Continue;
    // Module samt Projektquelltext (.dpr bzw. .dpk); Formulare kommen über die .pas dazu.
    mFiles := nil;
    for mModule := 0 to mProject.GetModuleCount - 1 do
    begin
      mName := mProject.GetModule(mModule).FileName;
      if mName <> '' then
        mFiles := mFiles + [mName];
    end;
    Result := Result + [TAtlasIssueProject.Create(mProject.FileName, mFiles)];
  end;
end;

class function TAtlasIdeIssueDevelopment.Bases(const ABranchBase: string): TArray<string>;
begin
  // SVN vergleicht nicht (Distance = -1); trunk liegt nicht unter ^/branches.
  if Trim(ABranchBase) <> '' then
    Result := TArray<string>.Create(Trim(ABranchBase))
  else
    Result := TArray<string>.Create('main', 'master');
end;

procedure TAtlasIdeIssueDevelopment.Start;
begin
  FStarted := True;
end;

procedure TAtlasIdeIssueDevelopment.Stop;
begin
  if not FStarted then
    Exit;
  FStarted := False;
  Inc(FGeneration);
  Cancel;
  ReleaseThreads(True);
  FHooks := Default(TAtlasIssueDevelopmentHooks);
end;

procedure TAtlasIdeIssueDevelopment.ReleaseThreads(AWait: Boolean);
var
  mIndex: Integer;
  mThread: TThread;
  mWait: TArray<TThread>;
begin
  if (FThread <> nil) and FThread.Finished then
  begin
    FWorkers.Add(FThread);
    FThread := nil;
  end;
  if AWait and (FThread <> nil) then
  begin
    FWorkers.Add(FThread);
    FThread := nil;
  end;
  if AWait then
  begin
    mWait := nil;
    for mIndex := 0 to FWorkers.Count - 1 do
      mWait := mWait + [FWorkers[mIndex]];
    if Length(mWait) > 0 then
      TAtlasShutdown.WaitForThreads(mWait);
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

function TAtlasIdeIssueDevelopment.View: TAtlasIssueDevelopmentView;
var
  mFrame: TAtlasIssueFrame;
begin
  Result := nil;
  if not Assigned(FHooks.Frame) then
    Exit;
  mFrame := FHooks.Frame();
  if mFrame <> nil then
    Result := mFrame.Development;
end;

function TAtlasIdeIssueDevelopment.ProjectFile: string;
begin
  Result := '';
  if Assigned(FHooks.Project) then
    Result := FHooks.Project();
end;

procedure TAtlasIdeIssueDevelopment.Notice(const AText: string);
var
  mFrame: TAtlasIssueFrame;
begin
  if not Assigned(FHooks.Frame) then
    Exit;
  mFrame := FHooks.Frame();
  if mFrame <> nil then
    mFrame.ShowError(AText, TAtlasIssueFix.None);
end;

procedure TAtlasIdeIssueDevelopment.Wire(AFrame: TAtlasIssueFrame);
var
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueDevelopment;
begin
  mKeep := Self;
  mOwner := Self;
  AFrame.DevelopmentVisible := Active;
  AFrame.OnDevelopmentShown :=
    procedure
    begin
      if mKeep <> nil then
        mOwner.Shown;
    end;
  AFrame.Development.OnShowDiff :=
    procedure(AEntry: TAtlasVcsLogEntry)
    begin
      if mKeep <> nil then
        mOwner.ShowDiff(AEntry);
    end;
  AFrame.Development.OnOpenCommit :=
    procedure(AEntry: TAtlasVcsLogEntry)
    begin
      if mKeep <> nil then
        mOwner.OpenCommit(AEntry);
    end;
  AFrame.Development.OnOpenUnit :=
    procedure(AUnit: TAtlasIssueUnit)
    begin
      if mKeep <> nil then
        mOwner.OpenUnit(AUnit);
    end;
  AFrame.Development.OnSwitchBranch :=
    procedure(ABranch: TAtlasIssueBranch)
    begin
      if mKeep <> nil then
        mOwner.SwitchBranch(ABranch);
    end;
  AFrame.Development.OnOpenPull :=
    procedure(APull: TAtlasTrackerPull)
    begin
      if (mKeep <> nil) and Assigned(mOwner.FHooks.Browse) then
        mOwner.FHooks.Browse(APull.Page);
    end;
  FShown := False;
end;

procedure TAtlasIdeIssueDevelopment.Select(const ATarget: TAtlasTrackerTarget; const AKey: string);
var
  mFrame: TAtlasIssueFrame;
begin
  if FHasCurrent and SameText(FTarget.Key, ATarget.Key) and SameText(FKey, AKey) then
    Exit;
  FTarget := ATarget;
  FKey := AKey;
  FHasCurrent := True;
  FShown := False;
  Inc(FGeneration);
  FForce := False;
  if not Assigned(FHooks.Frame) then
    Exit;
  mFrame := FHooks.Frame();
  if mFrame = nil then
    Exit;
  // Schalter erst beim nächsten Issue: Der Reiter verschwindet nicht unter der Maus.
  mFrame.DevelopmentVisible := Active;
  if mFrame.DevelopmentActive then
    Load(False);
end;

procedure TAtlasIdeIssueDevelopment.Shown;
begin
  if FHasCurrent and not FShown then
    Load(FForce);
end;

procedure TAtlasIdeIssueDevelopment.Refresh;
var
  mFrame: TAtlasIssueFrame;
begin
  if not FHasCurrent then
    Exit;
  FShown := False;
  FForce := True;
  if not Assigned(FHooks.Frame) then
    Exit;
  mFrame := FHooks.Frame();
  if (mFrame <> nil) and mFrame.DevelopmentActive then
    Load(True);
end;

procedure TAtlasIdeIssueDevelopment.Cancel;
begin
  if FCancel <> nil then
    FCancel.Cancel;
end;

function TAtlasIdeIssueDevelopment.TrackerNote(const ADevelopment: TAtlasIssueDevelopment): string;
begin
  Result := '';
  if ADevelopment.TrackerLoaded or (ADevelopment.TrackerError in [TAtlasCiFetchError.None,
    TAtlasCiFetchError.Cancelled]) then
    Exit;
  case ADevelopment.TrackerError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorToken);
    TAtlasCiFetchError.Timeout:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorTimeout);
    TAtlasCiFetchError.NotConfigured, TAtlasCiFetchError.UnknownProvider:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorConfig);
    TAtlasCiFetchError.Invalid, TAtlasCiFetchError.Server, TAtlasCiFetchError.NotFound:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorInvalid);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorNetwork);
  end;
end;

procedure TAtlasIdeIssueDevelopment.Show(const ADevelopment: TAtlasIssueDevelopment);
var
  mView: TAtlasIssueDevelopmentView;
begin
  mView := View;
  if mView = nil then
    Exit;
  FShown := True;
  mView.ShowDevelopment(ADevelopment, TrackerNote(ADevelopment));
end;

procedure TAtlasIdeIssueDevelopment.Load(AForce: Boolean);
var
  mView: TAtlasIssueDevelopmentView;
  mCached: TAtlasIssueDevelopment;
  mRequest: TAtlasIssueDevelopmentRequest;
  mProject, mFolder: string;
  mProjects: TArray<TAtlasIssueProject>;
  mProvider: IAtlasTrackerProvider;
  mTransport: IAtlasCiTransport;
  mTarget: TAtlasTrackerTarget;
  mGeneration: Integer;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueDevelopment;
begin
  if not FStarted or not FHasCurrent or not Active then
    Exit;
  mView := View;
  if mView = nil then
    Exit;
  if not AForce and FCache.Get(FTarget, FKey, mCached) then
  begin
    Show(mCached);
    Exit;
  end;
  // Eine Suche zur Zeit: die laufende verfällt (Generation), der Tracker bricht ab.
  Cancel;
  ReleaseThreads(False);
  Inc(FGeneration);
  mGeneration := FGeneration;
  FShown := True;
  mProject := ProjectFile;
  mFolder := ExtractFileDir(mProject);
  mProjects := GroupProjects;
  mTarget := FTarget;
  mRequest := TAtlasIssueDevelopmentRequest.Create(FTarget.Provider, FTarget.Project, FKey,
    Bases(TAtlasIdeSettings.Current.IssuesBranchBase), mProjects);
  FForce := False;
  mView.ShowLoading;
  // Der Transport entsteht hier, damit „Abbrechen“ ihn erreicht; er liest das Token ohne Dialog.
  mProvider := nil;
  mTransport := nil;
  if Assigned(FHooks.Provider) then
    mProvider := FHooks.Provider(FTarget);
  if (mProvider <> nil) and Assigned(FHooks.Transport) then
    mTransport := FHooks.Transport(mProvider, FTarget);
  if not Supports(mTransport, IAtlasCiCancel, FCancel) then
    FCancel := nil;
  mKeep := Self;
  mOwner := Self;
  // Ohne Ergebnis aus dem Thread weiter: Der Vorgänger kann noch laufen und verfällt.
  if FThread <> nil then
  begin
    FWorkers.Add(FThread);
    FThread := nil;
  end;
  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      mResult: TAtlasIssueDevelopment;
      mDevelopment: TAtlasTrackerDevelopment;
      mError: TAtlasCiFetchError;
    begin
      mResult := TAtlasIssueDevelopment.Empty;
      mResult.Key := mRequest.Key;
      try
        if mProject <> '' then
          TAtlasIssueDevelopmentQuery.Collect(TAtlasIdeVcs.ForFolder(mFolder, VcsTimeoutMs), mRequest, mResult);
      except
        on E: Exception do
        begin
          mResult.VcsOutcome := TAtlasVcsOutcome.Failed;
          TAtlasGuard.Log('Issue-Entwicklung: Versionsverwaltung mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      if mProvider = nil then
        mResult.TrackerError := TAtlasCiFetchError.NotConfigured
      else if mTransport = nil then
        mResult.TrackerError := TAtlasCiFetchError.Unauthorized
      else
        try
          mResult.TrackerLoaded := mProvider.Development(mTarget, mTransport, mRequest.Key, TrackerTimeoutMs,
            mDevelopment, mError);
          if mResult.TrackerLoaded then
            mResult.Tracker := mDevelopment
          else
            mResult.TrackerError := mError;
        except
          on E: Exception do
          begin
            mResult.TrackerError := TAtlasCiFetchError.Network;
            TAtlasGuard.Log('Issue-Entwicklung: Tracker mit ' + E.ClassName + ' abgebrochen');
          end;
        end;
      mTransport := nil;
      mProvider := nil;
      if TAtlasShutdown.Signalled then
        Exit;
      TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
        procedure
        begin
          if mKeep <> nil then
            mOwner.Loaded(mGeneration, mProject = '', mResult);
        end);
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

procedure TAtlasIdeIssueDevelopment.Loaded(AGeneration: Integer; ANoProject: Boolean;
  const ADevelopment: TAtlasIssueDevelopment);
var
  mDevelopment: TAtlasIssueDevelopment;
  mView: TAtlasIssueDevelopmentView;
begin
  ReleaseThreads(False);
  if not FStarted or (AGeneration <> FGeneration) then
    Exit;
  FCancel := nil;
  TAtlasGuard.Log(Format('Issue-Entwicklung: Versionsverwaltung %s, Tracker %s',
    [AtlasVcsOutcomeName(ADevelopment.VcsOutcome), TAtlasCiBuild.ErrorKey(ADevelopment.TrackerError)]));
  mDevelopment := ADevelopment;
  mDevelopment.Fetched := NowUtc;
  // Ohne Projekt: nur der Tracker; die Zeile sagt, warum Branches und Commits fehlen.
  if ANoProject then
  begin
    mView := View;
    if mView <> nil then
    begin
      FShown := True;
      mView.ShowDevelopment(mDevelopment, TrackerNote(mDevelopment),
        TAtlasStrings.Text(TAtlasTextId.IssueDevNoProject));
    end;
    Exit;
  end;
  FCache.Put(FTarget, mDevelopment);
  Show(mDevelopment);
end;

class function TAtlasIdeIssueDevelopment.ReadContent(const AHistory: IAtlasVcsHistory; const ARevision: string;
  const AFile: TAtlasVcsLogFile; ABefore: Boolean; out AText: string): TAtlasVcsOutcome;
var
  mBytes: TBytes;
begin
  AText := '';
  Result := AHistory.ContentOf(ARevision, AFile, ABefore, mBytes);
  if (Result = TAtlasVcsOutcome.Ok) and (Length(mBytes) > 0) then
    AText := TAtlasTextFile.Decode(mBytes).Text;
end;

class function TAtlasIdeIssueDevelopment.CommitDiff(const AHistory: IAtlasVcsHistory;
  const AEntry: TAtlasVcsLogEntry; out AFiles: TArray<TAtlasIssueFileDiff>): TAtlasVcsOutcome;
var
  mFile: TAtlasVcsLogFile;
  mDiff: TAtlasIssueFileDiff;
begin
  AFiles := nil;
  Result := TAtlasVcsOutcome.Ok;
  for mFile in AEntry.Files do
  begin
    if Length(AFiles) >= MaxDiffFiles then
      Break;
    mDiff := Default(TAtlasIssueFileDiff);
    mDiff.Caption := mFile.RepositoryPath;
    if mDiff.Caption = '' then
      mDiff.Caption := mFile.Path;
    Result := ReadContent(AHistory, AEntry.Revision, mFile, True, mDiff.Before);
    if Result = TAtlasVcsOutcome.Ok then
      Result := ReadContent(AHistory, AEntry.Revision, mFile, False, mDiff.After);
    if Result <> TAtlasVcsOutcome.Ok then
      Exit;
    AFiles := AFiles + [mDiff];
  end;
end;

procedure TAtlasIdeIssueDevelopment.ShowDiff(const AEntry: TAtlasVcsLogEntry);
var
  mFolder: string;
  mEntry: TAtlasVcsLogEntry;
  mFiles: TArray<TAtlasIssueFileDiff>;
  mOutcome: TAtlasVcsOutcome;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueDevelopment;
begin
  mFolder := ExtractFileDir(ProjectFile);
  if not FStarted or (mFolder = '') then
    Exit;
  mEntry := AEntry;
  mOutcome := TAtlasVcsOutcome.Failed;
  mKeep := Self;
  mOwner := Self;
  TAtlasIdeVcs.Run(
    procedure
    var
      mHistory: IAtlasVcsHistory;
    begin
      if Supports(TAtlasIdeVcs.ForFolder(mFolder, VcsTimeoutMs), IAtlasVcsHistory, mHistory) then
        mOutcome := CommitDiff(mHistory, mEntry, mFiles)
      else
        mOutcome := TAtlasVcsOutcome.NoWorkingCopy;
    end,
    procedure
    begin
      if (mKeep <> nil) and mOwner.FStarted then
        mOwner.DiffLoaded(mEntry, mOutcome, mFiles);
    end);
end;

procedure TAtlasIdeIssueDevelopment.DiffLoaded(const AEntry: TAtlasVcsLogEntry; AOutcome: TAtlasVcsOutcome;
  const AFiles: TArray<TAtlasIssueFileDiff>);
var
  mLines: TArray<string>;
  mShort: string;
begin
  mShort := AEntry.Revision;
  if Length(mShort) > 10 then
    mShort := Copy(mShort, 1, 7);
  if AOutcome <> TAtlasVcsOutcome.Ok then
  begin
    Notice(TAtlasStrings.Fmt(TAtlasTextId.IssueDevDiffFailed, [mShort, AtlasVcsOutcomeName(AOutcome)]));
    Exit;
  end;
  mLines := TAtlasIssueDevelopmentQuery.DiffLines(AFiles);
  if Length(mLines) = 0 then
  begin
    Notice(TAtlasStrings.Text(TAtlasTextId.IssueDevDiffEmpty));
    Exit;
  end;
  TAtlasUndoDiffView.Execute(TAtlasStrings.Fmt(TAtlasTextId.IssueDevDiffTitle, [mShort, AEntry.Summary]), mLines);
end;

procedure TAtlasIdeIssueDevelopment.OpenCommit(const AEntry: TAtlasVcsLogEntry);
var
  mFolder: string;
  mEntry: TAtlasVcsLogEntry;
  mFile: TAtlasVcsLogFile;
  mLine: Integer;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueDevelopment;
begin
  mFolder := ExtractFileDir(ProjectFile);
  if not FStarted or (mFolder = '') then
    Exit;
  if not TAtlasIssueDevelopmentQuery.OpenTarget(AEntry, mFile) then
  begin
    Notice(TAtlasStrings.Text(TAtlasTextId.IssueDevDiffEmpty));
    Exit;
  end;
  if not FileExists(mFile.Path) then
  begin
    Notice(TAtlasStrings.Fmt(TAtlasTextId.IssueDevUnitMissing, [ExtractFileName(mFile.Path)]));
    Exit;
  end;
  mEntry := AEntry;
  mLine := 1;
  mKeep := Self;
  mOwner := Self;
  // Die Zeile kommt aus dem Commit; heute kann sie verschoben sein, die Stelle stimmt dann ungefähr.
  if not TAtlasIdeVcs.Run(
    procedure
    var
      mHistory: IAtlasVcsHistory;
      mBefore, mAfter: string;
    begin
      if Supports(TAtlasIdeVcs.ForFolder(mFolder, VcsTimeoutMs), IAtlasVcsHistory, mHistory) and
        (ReadContent(mHistory, mEntry.Revision, mFile, True, mBefore) = TAtlasVcsOutcome.Ok) and
        (ReadContent(mHistory, mEntry.Revision, mFile, False, mAfter) = TAtlasVcsOutcome.Ok) then
        mLine := TAtlasIssueDevelopmentQuery.FirstChangedLine(mBefore, mAfter);
    end,
    procedure
    begin
      if (mKeep <> nil) and mOwner.FStarted then
        TAtlasIdeNavigation.GoToLocation(mFile.Path, mLine - 1, 0);
    end) then
    TAtlasIdeNavigation.GoToLocation(mFile.Path, 0, 0);
end;

procedure TAtlasIdeIssueDevelopment.OpenUnit(const AUnit: TAtlasIssueUnit);
begin
  if AUnit.Deleted or (AUnit.Path = '') then
    Exit;
  if not FileExists(AUnit.Path) then
  begin
    Notice(TAtlasStrings.Fmt(TAtlasTextId.IssueDevUnitMissing, [ExtractFileName(AUnit.Path)]));
    Exit;
  end;
  TAtlasIdeNavigation.GoToLocation(AUnit.Path, 0, 0);
end;

procedure TAtlasIdeIssueDevelopment.SwitchBranch(const ABranch: TAtlasIssueBranch);
var
  mFolder: string;
  mBranch: TAtlasIssueBranch;
  mChanges: Integer;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueDevelopment;
begin
  mFolder := ExtractFileDir(ProjectFile);
  if not FStarted or (mFolder = '') or ABranch.Current then
    Exit;
  mBranch := ABranch;
  mChanges := 0;
  mKeep := Self;
  mOwner := Self;
  // Erst zählen, was lokal geändert ist; gefragt wird im Hauptthread.
  TAtlasIdeVcs.Run(
    procedure
    var
      mVcs: IAtlasVersionControl;
      mList: TArray<TAtlasVcsChange>;
    begin
      mVcs := TAtlasIdeVcs.ForFolder(mFolder, VcsTimeoutMs);
      if (mVcs <> nil) and (mVcs.Changes(mList) = TAtlasVcsOutcome.Ok) then
        mChanges := Length(mList);
    end,
    procedure
    begin
      if (mKeep <> nil) and mOwner.FStarted then
        mOwner.SwitchChecked(mBranch, mChanges);
    end);
end;

procedure TAtlasIdeIssueDevelopment.SwitchChecked(const ABranch: TAtlasIssueBranch; AChanges: Integer);
var
  mFolder: string;
  mBranch: TAtlasIssueBranch;
  mOutcome: TAtlasVcsOutcome;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueDevelopment;
begin
  if (AChanges > 0) and (MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.IssueDevSwitchAsk, [AChanges, ABranch.Name]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
    Exit;
  mFolder := ExtractFileDir(ProjectFile);
  if mFolder = '' then
    Exit;
  mBranch := ABranch;
  mOutcome := TAtlasVcsOutcome.Failed;
  mKeep := Self;
  mOwner := Self;
  TAtlasIdeVcs.Run(
    procedure
    var
      mBranching: IAtlasVcsBranching;
    begin
      if Supports(TAtlasIdeVcs.ForFolder(mFolder, VcsTimeoutMs), IAtlasVcsBranching, mBranching) then
        mOutcome := mBranching.SwitchBranch(mBranch.Name)
      else
        mOutcome := TAtlasVcsOutcome.NoWorkingCopy;
    end,
    procedure
    begin
      if (mKeep <> nil) and mOwner.FStarted then
        mOwner.Switched(mBranch, mOutcome);
    end);
end;

procedure TAtlasIdeIssueDevelopment.Switched(const ABranch: TAtlasIssueBranch; AOutcome: TAtlasVcsOutcome);
begin
  TAtlasGuard.Log('Issue-Entwicklung: Wechseln ' + AtlasVcsOutcomeName(AOutcome));
  if AOutcome <> TAtlasVcsOutcome.Ok then
  begin
    Notice(TAtlasStrings.Fmt(TAtlasTextId.IssueDevSwitchFailed, [ABranch.Name, AtlasVcsOutcomeName(AOutcome)]));
    Exit;
  end;
  Notice(TAtlasStrings.Fmt(TAtlasTextId.IssueDevSwitched, [ABranch.Name]));
  // Aktueller Branch und Abstand haben sich geändert.
  FShown := False;
  Load(True);
end;

end.
