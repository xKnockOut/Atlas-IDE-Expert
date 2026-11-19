unit Atlas.IDE.Tracker.BoardLoad;

// Laden des Fensters „Atlas-Board“ (#1272): Tracker des aktiven Projekts
// übernehmen, sofort den letzten Stand aus dem Zwischenspeicher zeigen, das
// Board im Hintergrund mit 10 s Zeitgrenze holen und ohne Antwort den letzten
// Stand mit Grund zeigen (Ziehen gesperrt). Merkt sich Tracker, Board und
// Sprint; das Verschieben (Atlas.IDE.Tracker.BoardMove) fragt hier, ob
// geschrieben werden darf.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Diagnostics.BackgroundJobs,
  Atlas.UI.Tracker.EndDialog,
  Atlas.UI.Tracker.BoardFrame;

type
  TAtlasBoardProviderHook = reference to function(const AName: string): IAtlasTrackerProvider;
  /// <summary>Transport mit dem Token aus dem Anmeldespeicher; nil ohne Token.</summary>
  TAtlasBoardTransportHook = reference to function(const AProvider: IAtlasTrackerProvider;
    const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
  /// <summary>AKey mir zuweisen (#1266); ADone im Hauptthread, genau einmal.</summary>
  TAtlasBoardAssignHook = reference to procedure(const ATarget: TAtlasTrackerTarget; const AKey: string;
    const ADone: TAtlasTrackerSendDone);

  TAtlasBoardHooks = record
    Provider: TAtlasBoardProviderHook;
    Transport: TAtlasBoardTransportHook;
    /// <summary>Tracker des aktiven Projekts; Server '' ohne.</summary>
    Target: TFunc<TAtlasTrackerTarget>;
    /// <summary>Issue in „Atlas-Issue“ zeigen (#1264).</summary>
    Preview: TProc<TAtlasTrackerTarget, string>;
    /// <summary>„Beginnen“ wie in „Meine Issues“ (#765).</summary>
    Start: TProc<TAtlasTrackerIssue>;
    /// <summary>„Prüfen …“ wie in „Meine Issues“ (#2126).</summary>
    Review: TProc<TAtlasTrackerIssue>;
    CanStart: TFunc<Boolean>;
    /// <summary>Kennung des aktuellen Issues; '' ohne.</summary>
    ActiveKey: TFunc<string>;
    Assign: TAtlasBoardAssignHook;
    /// <summary>Zeile in die Meldungsansicht.</summary>
    Message: TProc<string>;
  end;

  TAtlasIdeBoardLoad = class(TInterfacedObject)
  private
    type
      /// <summary>Laden im Hintergrund: was der Worker braucht.</summary>
      TLoadJob = record
        Generation: Integer;
        Target: TAtlasTrackerTarget;
        Boards: IAtlasTrackerBoards;
        Transport: IAtlasCiTransport;
        BoardId: string;
        SprintId: string;
        /// <summary>Schreibweg da: Ziehen erlaubt.</summary>
        Write: Boolean;
      end;
  private
    FHooks: TAtlasBoardHooks;
    FCacheFolder: string;
    FWorker: TAtlasBackgroundJobs;
    FStopped: Boolean;
    FCancel: IAtlasCiCancel;
    FGeneration: Integer;
    FLoading: Boolean;
    FOnline: Boolean;
    FCanWrite: Boolean;
    FTarget: TAtlasTrackerTarget;
    FBoardId: string;
    FSprintId: string;
    procedure Loaded(AGeneration: Integer; const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean;
      const ASnapshot: TAtlasBoardSnapshot; AError: TAtlasCiFetchError; AWrite: Boolean);
    procedure ShowFailed(AFrame: TAtlasBoardFrame; const ATarget: TAtlasTrackerTarget; AError: TAtlasCiFetchError);
    procedure SelectTarget(AFrame: TAtlasBoardFrame; const ABoardId, ASprintId: string);
    function PrepareLoad(AFrame: TAtlasBoardFrame; out AJob: TLoadJob): Boolean;
    procedure RunLoad(const AJob: TLoadJob);
    function ErrorText(AError: TAtlasCiFetchError): string;
    class function NowUtc: TDateTime; static;
  public
    /// <summary>ACacheFolder: Ordner des Zwischenspeichers ('' = keiner); AWorker gehört dem Board.</summary>
    constructor Create(const AHooks: TAtlasBoardHooks; const ACacheFolder: string; AWorker: TAtlasBackgroundJobs);
    /// <summary>Board ABoardId mit Sprint ASprintId laden ('' = Vorgabe des Trackers), wenn das Fenster da
    /// ist.</summary>
    procedure Load(const ABoardId, ASprintId: string);
    /// <summary>Gezeigtes Board und gezeigten Sprint neu laden.</summary>
    procedure Reload;
    procedure CancelLoad;
    /// <summary>Markierung des aktuellen Issues nachführen.</summary>
    procedure UpdateActive;
    /// <summary>Abbrechen; danach wirkungslos (auf den Worker wartet das Board).</summary>
    procedure Stop;
    /// <summary>Anbieter des Trackers ATarget; nil ohne.</summary>
    function ProviderOf(const ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
    /// <summary>Board-Zugriff des Anbieters (optionale Fähigkeit IAtlasTrackerBoards); nil ohne Anbieter oder
    /// ohne Board.</summary>
    class function BoardsOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerBoards; static;
    /// <summary>Tracker des gezeigten Boards.</summary>
    property Target: TAtlasTrackerTarget read FTarget;
    property BoardId: string read FBoardId;
    property Loading: Boolean read FLoading;
    /// <summary>Letztes Laden mit Antwort: Ziehen nur dann.</summary>
    property Online: Boolean read FOnline;
    /// <summary>Schreibweg beim letzten Laden da.</summary>
    property CanWrite: Boolean read FCanWrite;
  end;

implementation

uses
  System.DateUtils,
  Atlas.Core.Tracker.BoardPlan,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Tracker.Issue.Strings,
  Atlas.UI.Tracker.Board.Strings,
  Atlas.IDE.Tracker.BoardWindow;

{ TAtlasIdeBoardLoad }

constructor TAtlasIdeBoardLoad.Create(const AHooks: TAtlasBoardHooks; const ACacheFolder: string;
  AWorker: TAtlasBackgroundJobs);
begin
  inherited Create;
  FHooks := AHooks;
  FCacheFolder := ACacheFolder;
  FWorker := AWorker;
end;

function TAtlasIdeBoardLoad.ProviderOf(const ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
begin
  Result := nil;
  if Assigned(FHooks.Provider) then
  begin
    Result := FHooks.Provider(ATarget.Provider);
  end;
end;

class function TAtlasIdeBoardLoad.BoardsOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerBoards;
begin
  // Der Anbieter kommt über die Hooks aus der Komposition; ein Board bietet er als weitere Fähigkeit an.
  if not Supports(AProvider, IAtlasTrackerBoards, Result) then
  begin
    Result := nil;
  end;
end;

class function TAtlasIdeBoardLoad.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

function TAtlasIdeBoardLoad.ErrorText(AError: TAtlasCiFetchError): string;
begin
  case TAtlasBoardPlan.ReasonOf(AError) of
    TAtlasBoardReason.Token:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorToken);
    TAtlasBoardReason.NoBoard:
      Result := TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardNoBoard);
    TAtlasBoardReason.Timeout:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorTimeout);
    TAtlasBoardReason.NoTracker:
      Result := TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardNoTracker);
    TAtlasBoardReason.Invalid:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorInvalid);
  else
    Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorNetwork);
  end;
end;

procedure TAtlasIdeBoardLoad.CancelLoad;
begin
  TAtlasCiCancels.Cancel(FCancel);
end;

procedure TAtlasIdeBoardLoad.UpdateActive;
var
  mFrame: TAtlasBoardFrame;
begin
  mFrame := TAtlasIdeBoardWindow.ExistingFrame;
  if (mFrame <> nil) and Assigned(FHooks.ActiveKey) then
  begin
    mFrame.SetActiveKey(FHooks.ActiveKey());
  end;
end;

procedure TAtlasIdeBoardLoad.Stop;
begin
  if FStopped then
  begin
    Exit;
  end;
  FStopped := True;
  Inc(FGeneration);
  CancelLoad;
  FHooks := Default(TAtlasBoardHooks);
end;

/// <summary>Anzeige nach dem Laden ohne Antwort: letzter Stand, Hinweis oder nichts; Ziehen gesperrt.</summary>
procedure TAtlasIdeBoardLoad.ShowFailed(AFrame: TAtlasBoardFrame; const ATarget: TAtlasTrackerTarget;
  AError: TAtlasCiFetchError);
var
  mCached: TAtlasBoardSnapshot;
  mHasCache: Boolean;
  mWhen: string;
begin
  // Ohne Antwort: der letzte Stand mit Grund, Ziehen gesperrt.
  FOnline := False;
  AFrame.SetCanDrag(False);
  mHasCache := TAtlasTrackerBoard.Load(FCacheFolder, ATarget, mCached);
  case TAtlasBoardPlan.LoadView(False, False, mHasCache, AError) of
    TAtlasBoardLoadView.Cached:
      begin
        mWhen := FormatDateTime('dd.mm.yyyy hh:nn', TTimeZone.Local.ToLocalTime(mCached.Fetched), FormatSettings);
        AFrame.SetSnapshot(mCached, TAtlasBoardStrings.Fmt(TAtlasBoardTextId.BoardOffline,
          [mWhen, ErrorText(AError)]));
        UpdateActive;
      end;
    TAtlasBoardLoadView.Notice:
      begin
        AFrame.ShowNotice(ErrorText(AError));
        AFrame.SetStatus('');
      end;
  end;
end;

procedure TAtlasIdeBoardLoad.Loaded(AGeneration: Integer; const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean;
  const ASnapshot: TAtlasBoardSnapshot; AError: TAtlasCiFetchError; AWrite: Boolean);
var
  mFrame: TAtlasBoardFrame;
  mSnapshot: TAtlasBoardSnapshot;
  mNotice: string;
begin
  if AGeneration <> FGeneration then
  begin
    Exit;
  end;
  FCancel := nil;
  FLoading := False;
  mFrame := TAtlasIdeBoardWindow.ExistingFrame;
  if FStopped or (mFrame = nil) then
  begin
    Exit;
  end;
  mFrame.SetLoading(False);
  TAtlasGuard.Log('Atlas-Board: ' + ATarget.Provider + ', ' + TAtlasCiBuild.ErrorKey(AError));
  if not ASucceeded then
  begin
    ShowFailed(mFrame, ATarget, AError);
    Exit;
  end;
  mSnapshot := ASnapshot;
  mSnapshot.Fetched := NowUtc;
  TAtlasTrackerBoard.Save(FCacheFolder, ATarget, mSnapshot);
  FBoardId := mSnapshot.Board.Id;
  FSprintId := mSnapshot.Sprint.Id;
  FOnline := True;
  FCanWrite := AWrite;
  // GitHub: Ohne Recht auf Projekte zeigt das Board Offen/Geschlossen und sagt warum.
  mNotice := '';
  if TAtlasBoardPlan.LoadView(True, mSnapshot.ProjectsDenied, False, AError) = TAtlasBoardLoadView.FreshDenied then
  begin
    mNotice := TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardErrorScopes);
  end;
  mFrame.SetSnapshot(mSnapshot, mNotice);
  mFrame.SetCanDrag(AWrite);
  UpdateActive;
end;

/// <summary>Tracker des aktiven Projekts übernehmen; bei anderem Tracker (Projektwechsel) gelten Auswahl von
/// Board und Sprint und der gezeigte Stand nicht mehr.</summary>
procedure TAtlasIdeBoardLoad.SelectTarget(AFrame: TAtlasBoardFrame; const ABoardId, ASprintId: string);
var
  mTarget: TAtlasTrackerTarget;
begin
  mTarget := Default(TAtlasTrackerTarget);
  if Assigned(FHooks.Target) then
  begin
    mTarget := FHooks.Target();
  end;
  FBoardId := ABoardId;
  FSprintId := ASprintId;
  if TAtlasBoardPlan.TargetChanged(FTarget, mTarget) then
  begin
    FBoardId := '';
    FSprintId := '';
    AFrame.ShowNotice('');
  end;
  FTarget := mTarget;
  FOnline := False;
  AFrame.SetCanDrag(False);
  UpdateActive;
end;

/// <summary>Anbieter, Board-Zugriff und Transport für das Laden; False, wenn nicht geladen wird (dann ist
/// das Fenster schon beschriftet bzw. Loaded gemeldet).</summary>
function TAtlasIdeBoardLoad.PrepareLoad(AFrame: TAtlasBoardFrame; out AJob: TLoadJob): Boolean;
var
  mProvider: IAtlasTrackerProvider;
  mCached: TAtlasBoardSnapshot;
begin
  AJob := Default(TLoadJob);
  AJob.Generation := FGeneration;
  AJob.Target := FTarget;
  AJob.BoardId := FBoardId;
  AJob.SprintId := FSprintId;
  mProvider := ProviderOf(AJob.Target);
  AJob.Boards := BoardsOf(mProvider);
  Result := (AJob.Target.Server <> '') and (mProvider <> nil) and (AJob.Boards <> nil);
  if not Result then
  begin
    AFrame.ShowNotice(TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardNoTracker));
    AFrame.SetStatus('');
  end
  else
  begin
    // Sofort der letzte Stand; frisch geladen ersetzt ihn.
    if not AFrame.HasSnapshot and TAtlasTrackerBoard.Load(FCacheFolder, AJob.Target, mCached) then
    begin
      AFrame.SetSnapshot(mCached, '');
    end;
    AFrame.SetLoading(True);
    FLoading := True;
    if Assigned(FHooks.Transport) then
    begin
      AJob.Transport := FHooks.Transport(mProvider, AJob.Target);
    end;
    Result := AJob.Transport <> nil;
    if not Result then
    begin
      // Ohne Token kein Transport.
      Loaded(AJob.Generation, AJob.Target, False, TAtlasBoardSnapshot.Empty, TAtlasCiFetchError.Unauthorized, False);
    end;
  end;
end;

/// <summary>Board im Hintergrund laden; das Ergebnis geht im Hauptthread an Loaded.</summary>
procedure TAtlasIdeBoardLoad.RunLoad(const AJob: TLoadJob);
var
  mJob: TLoadJob;
  mKeep: IInterface;
  mOwner: TAtlasIdeBoardLoad;
  mOk: Boolean;
  mSnapshot: TAtlasBoardSnapshot;
  mError: TAtlasCiFetchError;
begin
  mJob := AJob;
  if not Supports(mJob.Transport, IAtlasCiCancel, FCancel) then
  begin
    FCancel := nil;
  end;
  // Ziehen nur mit Schreibweg.
  mJob.Write := Supports(mJob.Transport, IAtlasCiSend);
  mKeep := Self;
  mOwner := Self;
  mSnapshot := TAtlasBoardSnapshot.Empty;
  mOk := False;
  mError := TAtlasCiFetchError.Network;
  if not FWorker.Run(
    procedure
    begin
      try
        mOk := mJob.Boards.LoadBoard(TAtlasBoardRequest.Create(mJob.Target, mJob.Transport, mJob.BoardId,
          mJob.SprintId, TAtlasTrackerBoard.cTimeoutMs), mSnapshot, mError);
      except
        // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
        on E: Exception do
        begin
          mOk := False;
          mError := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Atlas-Board: Abfrage mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mJob.Transport := nil;
    end,
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.Loaded(mJob.Generation, mJob.Target, mOk, mSnapshot, mError, mJob.Write);
      end;
    end) then
  begin
    Loaded(mJob.Generation, mJob.Target, False, TAtlasBoardSnapshot.Empty, TAtlasCiFetchError.Cancelled, False);
  end;
end;

procedure TAtlasIdeBoardLoad.Load(const ABoardId, ASprintId: string);
var
  mFrame: TAtlasBoardFrame;
  mJob: TLoadJob;
begin
  mFrame := TAtlasIdeBoardWindow.ExistingFrame;
  if not FStopped and (mFrame <> nil) then
  begin
    CancelLoad;
    Inc(FGeneration);
    SelectTarget(mFrame, ABoardId, ASprintId);
    if PrepareLoad(mFrame, mJob) then
    begin
      RunLoad(mJob);
    end;
  end;
end;

procedure TAtlasIdeBoardLoad.Reload;
begin
  Load(FBoardId, FSprintId);
end;

end.
