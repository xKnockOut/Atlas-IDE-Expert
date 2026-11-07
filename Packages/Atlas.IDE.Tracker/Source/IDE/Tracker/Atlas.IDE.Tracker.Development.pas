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
  Atlas.Core.CiBuild.Contract,
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
    cVcsTimeoutMs = 10000;
    /// <summary>Zeitgrenze für den Tracker.</summary>
    cTrackerTimeoutMs = 10000;
    /// <summary>Höchstens so viele Dateien im Diff eines Commits.</summary>
    cMaxDiffFiles = 30;
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
  Atlas.UI.Strings,  Atlas.UI.Tracker.Strings,
  Atlas.UI.Undo.DiffView,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Contracts.VersionControl;

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

function NowUtc: TDateTime;
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
  begin
    Exit;
  end;
  mGroup := mServices.MainProjectGroup;
  if mGroup = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mGroup.ProjectCount - 1 do
  begin
    mProject := mGroup.Projects[mIndex];
    if mProject = nil then
    begin
      Continue;
    end;
    // Module samt Projektquelltext (.dpr bzw. .dpk); Formulare kommen über die .pas dazu.
    mFiles := nil;
    for mModule := 0 to mProject.GetModuleCount - 1 do
    begin
      mName := mProject.GetModule(mModule).FileName;
      if mName <> '' then
      begin
        mFiles := mFiles + [mName];
      end;
    end;
    Result := Result + [TAtlasIssueProject.Create(mProject.FileName, mFiles)];
  end;
end;

class function TAtlasIdeIssueDevelopment.Bases(const ABranchBase: string): TArray<string>;
begin
  // SVN vergleicht nicht (Distance = -1); trunk liegt nicht unter ^/branches.
  if Trim(ABranchBase) <> '' then
  begin
    Result := TArray<string>.Create(Trim(ABranchBase));
  end
  else
  begin
    Result := TArray<string>.Create('main', 'master');
  end;
end;

procedure TAtlasIdeIssueDevelopment.Start;
begin
  FStarted := True;
end;

procedure TAtlasIdeIssueDevelopment.Stop;
begin
  if not FStarted then
  begin
    Exit;
  end;
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

function TAtlasIdeIssueDevelopment.View: TAtlasIssueDevelopmentView;
var
  mFrame: TAtlasIssueFrame;
begin
  Result := nil;
  if not Assigned(FHooks.Frame) then
  begin
    Exit;
  end;
  mFrame := FHooks.Frame();
  if mFrame <> nil then
  begin
    Result := mFrame.Parts.Development;
  end;
end;

function TAtlasIdeIssueDevelopment.ProjectFile: string;
begin
  Result := '';
  if Assigned(FHooks.Project) then
  begin
    Result := FHooks.Project();
  end;
end;

procedure TAtlasIdeIssueDevelopment.Notice(const AText: string);
var
  mFrame: TAtlasIssueFrame;
begin
  if not Assigned(FHooks.Frame) then
  begin
    Exit;
  end;
  mFrame := FHooks.Frame();
  if mFrame <> nil then
  begin
    mFrame.ShowError(AText, TAtlasIssueFix.None);
  end;
end;

/// <summary>Ereignisse der Ansicht; jedes erreicht das Objekt nur, solange AKeep es hält.</summary>
function DevelopmentEvents(AOwner: TAtlasIdeIssueDevelopment; const AKeep: IInterface): TAtlasIssueDevelopmentEvents;
begin
  Result := Default(TAtlasIssueDevelopmentEvents);
  Result.ShowDiff :=
    procedure(AEntry: TAtlasVcsLogEntry)
    begin
      if AKeep <> nil then
      begin
        AOwner.ShowDiff(AEntry);
      end;
    end;
  Result.OpenCommit :=
    procedure(AEntry: TAtlasVcsLogEntry)
    begin
      if AKeep <> nil then
      begin
        AOwner.OpenCommit(AEntry);
      end;
    end;
  Result.OpenUnit :=
    procedure(AUnit: TAtlasIssueUnit)
    begin
      if AKeep <> nil then
      begin
        AOwner.OpenUnit(AUnit);
      end;
    end;
  Result.SwitchBranch :=
    procedure(ABranch: TAtlasIssueBranch)
    begin
      if AKeep <> nil then
      begin
        AOwner.SwitchBranch(ABranch);
      end;
    end;
  Result.OpenPull :=
    procedure(APull: TAtlasTrackerPull)
    begin
      if (AKeep <> nil) and Assigned(AOwner.FHooks.Browse) then
      begin
        AOwner.FHooks.Browse(APull.Page);
      end;
    end;
end;

procedure TAtlasIdeIssueDevelopment.Wire(AFrame: TAtlasIssueFrame);
var
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueDevelopment;
  mEvents: TAtlasIssueFrameEvents;
begin
  mKeep := Self;
  mOwner := Self;
  AFrame.SetFlag(TAtlasIssueFlag.Development, Active);
  mEvents := AFrame.Events;
  mEvents.DevelopmentShown :=
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.Shown;
      end;
    end;
  AFrame.Events := mEvents;
  AFrame.Parts.Development.Events := DevelopmentEvents(Self, mKeep);
  FShown := False;
end;

procedure TAtlasIdeIssueDevelopment.Select(const ATarget: TAtlasTrackerTarget; const AKey: string);
var
  mFrame: TAtlasIssueFrame;
begin
  if FHasCurrent and SameText(FTarget.Key, ATarget.Key) and SameText(FKey, AKey) then
  begin
    Exit;
  end;
  FTarget := ATarget;
  FKey := AKey;
  FHasCurrent := True;
  FShown := False;
  Inc(FGeneration);
  FForce := False;
  if not Assigned(FHooks.Frame) then
  begin
    Exit;
  end;
  mFrame := FHooks.Frame();
  if mFrame = nil then
  begin
    Exit;
  end;
  // Schalter erst beim nächsten Issue: Der Reiter verschwindet nicht unter der Maus.
  mFrame.SetFlag(TAtlasIssueFlag.Development, Active);
  if mFrame.DevelopmentActive then
  begin
    Load(False);
  end;
end;

procedure TAtlasIdeIssueDevelopment.Shown;
begin
  if FHasCurrent and not FShown then
  begin
    Load(FForce);
  end;
end;

procedure TAtlasIdeIssueDevelopment.Refresh;
var
  mFrame: TAtlasIssueFrame;
begin
  if not FHasCurrent then
  begin
    Exit;
  end;
  FShown := False;
  FForce := True;
  if not Assigned(FHooks.Frame) then
  begin
    Exit;
  end;
  mFrame := FHooks.Frame();
  if (mFrame <> nil) and mFrame.DevelopmentActive then
  begin
    Load(True);
  end;
end;

procedure TAtlasIdeIssueDevelopment.Cancel;
begin
  if FCancel <> nil then
  begin
    FCancel.Cancel;
  end;
end;

/// <summary>Zeile zum Tracker, wenn er nicht geantwortet hat; '' sonst.</summary>
function TrackerNote(const ADevelopment: TAtlasIssueDevelopment): string;
begin
  Result := '';
  if ADevelopment.TrackerLoaded or (ADevelopment.TrackerError in [TAtlasCiFetchError.None,
    TAtlasCiFetchError.Cancelled]) then
  begin
    Exit;
  end;
  case ADevelopment.TrackerError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorToken);
    TAtlasCiFetchError.Timeout:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorTimeout);
    TAtlasCiFetchError.NotConfigured, TAtlasCiFetchError.UnknownProvider:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewErrorConfig);
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
  begin
    Exit;
  end;
  FShown := True;
  mView.ShowDevelopment(ADevelopment, TrackerNote(ADevelopment));
end;

type
  /// <summary>Eine Suche, wie sie in den Hintergrund geht.</summary>
  TLoadJob = record
    Generation: Integer;
    Project: string;
    Request: TAtlasIssueDevelopmentRequest;
    Target: TAtlasTrackerTarget;
    Provider: IAtlasTrackerProvider;
    Transport: IAtlasCiTransport;
  end;

/// <summary>Branches und Commits aus der Versionsverwaltung des Projektordners (ohne Projekt keine).</summary>
procedure CollectVcs(const AJob: TLoadJob; var AResult: TAtlasIssueDevelopment);
begin
  try
    if AJob.Project <> '' then
    begin
      TAtlasIssueDevelopmentQuery.Collect(TAtlasIdeVcs.ForFolder(ExtractFileDir(AJob.Project),
        TAtlasIdeIssueDevelopment.cVcsTimeoutMs), AJob.Request, AResult);
    end;
  except
    on E: Exception do
    begin
      AResult.VcsOutcome := TAtlasVcsOutcome.Failed;
      TAtlasGuard.Log('Issue-Entwicklung: Versionsverwaltung mit ' + E.ClassName + ' abgebrochen');
    end;
  end;
end;

/// <summary>Entwicklung beim Tracker (Pull Requests, VCS-Änderungen).</summary>
procedure CollectTracker(const AJob: TLoadJob; var AResult: TAtlasIssueDevelopment);
var
  mDevelopment: TAtlasTrackerDevelopment;
  mError: TAtlasCiFetchError;
begin
  if AJob.Provider = nil then
  begin
    AResult.TrackerError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  if AJob.Transport = nil then
  begin
    AResult.TrackerError := TAtlasCiFetchError.Unauthorized;
    Exit;
  end;
  try
    AResult.TrackerLoaded := AJob.Provider.Development(AJob.Target, AJob.Transport, AJob.Request.Key,
      TAtlasIdeIssueDevelopment.cTrackerTimeoutMs, mDevelopment, mError);
    if AResult.TrackerLoaded then
    begin
      AResult.Tracker := mDevelopment;
    end
    else
    begin
      AResult.TrackerError := mError;
    end;
  except
    on E: Exception do
    begin
      AResult.TrackerError := TAtlasCiFetchError.Network;
      TAtlasGuard.Log('Issue-Entwicklung: Tracker mit ' + E.ClassName + ' abgebrochen');
    end;
  end;
end;

/// <summary>Arbeit des Hintergrundthreads; das Ergebnis geht über den Hauptthread an AOwner, solange AKeep ihn
/// hält. Eigene Routine: Die anonyme Methode hält nur ihre Parameter.</summary>
function LoadWorker(AOwner: TAtlasIdeIssueDevelopment; const AKeep: IInterface; const AJob: TLoadJob): TProc;
var
  mJob: TLoadJob;
  mKeep: IInterface;
begin
  mJob := AJob;
  mKeep := AKeep;
  Result :=
    procedure
    var
      mResult: TAtlasIssueDevelopment;
    begin
      mResult := TAtlasIssueDevelopment.Empty;
      mResult.Key := mJob.Request.Key;
      CollectVcs(mJob, mResult);
      CollectTracker(mJob, mResult);
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
            AOwner.Loaded(mJob.Generation, mJob.Project = '', mResult);
          end;
        end);
    end;
end;

procedure TAtlasIdeIssueDevelopment.Load(AForce: Boolean);
var
  mView: TAtlasIssueDevelopmentView;
  mCached: TAtlasIssueDevelopment;
  mJob: TLoadJob;
begin
  if not FStarted or not FHasCurrent or not Active then
  begin
    Exit;
  end;
  mView := View;
  if mView = nil then
  begin
    Exit;
  end;
  if not AForce and FCache.Get(FTarget, FKey, mCached) then
  begin
    Show(mCached);
    Exit;
  end;
  // Eine Suche zur Zeit: die laufende verfällt (Generation), der Tracker bricht ab.
  Cancel;
  ReleaseThreads(False);
  Inc(FGeneration);
  FShown := True;
  mJob := Default(TLoadJob);
  mJob.Generation := FGeneration;
  mJob.Project := ProjectFile;
  mJob.Target := FTarget;
  mJob.Request := TAtlasIssueDevelopmentRequest.Create(FTarget.Provider, FTarget.Project, FKey,
    Bases(TAtlasIdeSettings.Current.IssuesBranchBase), GroupProjects);
  FForce := False;
  mView.ShowLoading;
  // Der Transport entsteht hier, damit „Abbrechen“ ihn erreicht; er liest das Token ohne Dialog.
  if Assigned(FHooks.Provider) then
  begin
    mJob.Provider := FHooks.Provider(FTarget);
  end;
  if (mJob.Provider <> nil) and Assigned(FHooks.Transport) then
  begin
    mJob.Transport := FHooks.Transport(mJob.Provider, FTarget);
  end;
  if not Supports(mJob.Transport, IAtlasCiCancel, FCancel) then
  begin
    FCancel := nil;
  end;
  // Ohne Ergebnis aus dem Thread weiter: Der Vorgänger kann noch laufen und verfällt.
  if FThread <> nil then
  begin
    FWorkers.Add(FThread);
    FThread := nil;
  end;
  FThread := TThread.CreateAnonymousThread(LoadWorker(Self, Self, mJob));
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
  begin
    Exit;
  end;
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
        TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevNoProject));
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
  begin
    AText := TAtlasTextFile.Decode(mBytes).Text;
  end;
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
    if Length(AFiles) >= cMaxDiffFiles then
    begin
      Break;
    end;
    mDiff := Default(TAtlasIssueFileDiff);
    mDiff.Caption := mFile.RepositoryPath;
    if mDiff.Caption = '' then
    begin
      mDiff.Caption := mFile.Path;
    end;
    Result := ReadContent(AHistory, AEntry.Revision, mFile, True, mDiff.Before);
    if Result = TAtlasVcsOutcome.Ok then
    begin
      Result := ReadContent(AHistory, AEntry.Revision, mFile, False, mDiff.After);
    end;
    if Result <> TAtlasVcsOutcome.Ok then
    begin
      Exit;
    end;
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
  begin
    Exit;
  end;
  mEntry := AEntry;
  mOutcome := TAtlasVcsOutcome.Failed;
  mKeep := Self;
  mOwner := Self;
  TAtlasIdeVcs.Run(
    procedure
    var
      mHistory: IAtlasVcsHistory;
    begin
      if Supports(TAtlasIdeVcs.ForFolder(mFolder, cVcsTimeoutMs), IAtlasVcsHistory, mHistory) then
      begin
        mOutcome := CommitDiff(mHistory, mEntry, mFiles);
      end
      else
      begin
        mOutcome := TAtlasVcsOutcome.NoWorkingCopy;
      end;
    end,
    procedure
    begin
      if (mKeep <> nil) and mOwner.FStarted then
      begin
        mOwner.DiffLoaded(mEntry, mOutcome, mFiles);
      end;
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
  begin
    mShort := Copy(mShort, 1, 7);
  end;
  if AOutcome <> TAtlasVcsOutcome.Ok then
  begin
    Notice(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevDiffFailed, [mShort, AtlasVcsOutcomeName(AOutcome)]));
    Exit;
  end;
  mLines := TAtlasIssueDevelopmentQuery.DiffLines(AFiles);
  if Length(mLines) = 0 then
  begin
    Notice(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevDiffEmpty));
    Exit;
  end;
  TAtlasUndoDiffView.Execute(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevDiffTitle,
    [mShort, AEntry.Summary]), mLines);
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
  begin
    Exit;
  end;
  if not TAtlasIssueDevelopmentQuery.OpenTarget(AEntry, mFile) then
  begin
    Notice(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevDiffEmpty));
    Exit;
  end;
  if not FileExists(mFile.Path) then
  begin
    Notice(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevUnitMissing, [ExtractFileName(mFile.Path)]));
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
      if Supports(TAtlasIdeVcs.ForFolder(mFolder, cVcsTimeoutMs), IAtlasVcsHistory, mHistory) and
        (ReadContent(mHistory, mEntry.Revision, mFile, True, mBefore) = TAtlasVcsOutcome.Ok) and
        (ReadContent(mHistory, mEntry.Revision, mFile, False, mAfter) = TAtlasVcsOutcome.Ok) then
      begin
        mLine := TAtlasIssueDevelopmentQuery.FirstChangedLine(mBefore, mAfter);
      end;
    end,
    procedure
    begin
      if (mKeep <> nil) and mOwner.FStarted then
      begin
        TAtlasIdeNavigation.GoToLocation(mFile.Path, mLine - 1, 0);
      end;
    end) then
  begin
    TAtlasIdeNavigation.GoToLocation(mFile.Path, 0, 0);
  end;
end;

procedure TAtlasIdeIssueDevelopment.OpenUnit(const AUnit: TAtlasIssueUnit);
begin
  if AUnit.Deleted or (AUnit.Path = '') then
  begin
    Exit;
  end;
  if not FileExists(AUnit.Path) then
  begin
    Notice(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevUnitMissing, [ExtractFileName(AUnit.Path)]));
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
  begin
    Exit;
  end;
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
      mVcs := TAtlasIdeVcs.ForFolder(mFolder, cVcsTimeoutMs);
      if (mVcs <> nil) and (mVcs.Changes(mList) = TAtlasVcsOutcome.Ok) then
      begin
        mChanges := Length(mList);
      end;
    end,
    procedure
    begin
      if (mKeep <> nil) and mOwner.FStarted then
      begin
        mOwner.SwitchChecked(mBranch, mChanges);
      end;
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
  if (AChanges > 0) and (MessageDlg(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevSwitchAsk,
    [AChanges, ABranch.Name]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
  begin
    Exit;
  end;
  mFolder := ExtractFileDir(ProjectFile);
  if mFolder = '' then
  begin
    Exit;
  end;
  mBranch := ABranch;
  mOutcome := TAtlasVcsOutcome.Failed;
  mKeep := Self;
  mOwner := Self;
  TAtlasIdeVcs.Run(
    procedure
    var
      mBranching: IAtlasVcsBranching;
    begin
      if Supports(TAtlasIdeVcs.ForFolder(mFolder, cVcsTimeoutMs), IAtlasVcsBranching, mBranching) then
      begin
        mOutcome := mBranching.SwitchBranch(mBranch.Name);
      end
      else
      begin
        mOutcome := TAtlasVcsOutcome.NoWorkingCopy;
      end;
    end,
    procedure
    begin
      if (mKeep <> nil) and mOwner.FStarted then
      begin
        mOwner.Switched(mBranch, mOutcome);
      end;
    end);
end;

procedure TAtlasIdeIssueDevelopment.Switched(const ABranch: TAtlasIssueBranch; AOutcome: TAtlasVcsOutcome);
begin
  TAtlasGuard.Log('Issue-Entwicklung: Wechseln ' + AtlasVcsOutcomeName(AOutcome));
  if AOutcome <> TAtlasVcsOutcome.Ok then
  begin
    Notice(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevSwitchFailed,
      [ABranch.Name, AtlasVcsOutcomeName(AOutcome)]));
    Exit;
  end;
  Notice(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevSwitched, [ABranch.Name]));
  // Aktueller Branch und Abstand haben sich geändert.
  FShown := False;
  Load(True);
end;

end.
