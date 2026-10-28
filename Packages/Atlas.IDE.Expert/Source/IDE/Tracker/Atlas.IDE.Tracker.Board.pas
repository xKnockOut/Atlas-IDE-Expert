unit Atlas.IDE.Tracker.Board;

// Steuerung des Fensters „Atlas-Board“ (#1272):
// - Show öffnet das Fenster und lädt das Board des aktiven Projekts (Tracker
//   wie „Meine Issues“: .atlas, sonst Zuordnung #1261) im Hintergrund mit
//   10 s Zeitgrenze. Sofort erscheint der letzte Stand aus dem
//   Zwischenspeicher (%LOCALAPPDATA%\Atlas\issues, eine Datei je Tracker);
//   ohne Antwort bleibt er mit „Stand vom … · Grund · Ziehen ist gesperrt“.
// - Kein eigenes Abfrage-Intervall: geladen wird beim Öffnen, mit
//   „Aktualisieren“, nach einem Wechsel von Board oder Sprint, nach dem
//   Verschieben und über Refresh (Aktualisierung aus #1271, falls an).
// - Ziehen: Rückfrage (issues.board.confirmMove; „Nicht mehr fragen“ schaltet
//   sie aus), die Karte steht sofort in der Zielspalte, geschrieben wird im
//   Hintergrund über IAtlasTrackerBoards.MoveCard (YouTrack-Befehl wie #1266,
//   GitHub Feld „Status“); bei einem Fehler springt sie zurück und die
//   Statuszeile nennt den Grund (TAtlasTrackerEndDialog.ErrorText).
// - Klick zeigt die Vorschau (#1264), Doppelklick beginnt (#765),
//   Kontextmenü: Beginnen, Vorschau, Im Browser öffnen, Kennung kopieren,
//   Mir zuweisen (Schreibweg #1266).
// - „Nur meine“ gilt beim Öffnen nach issues.board.onlyMine, der Umschalter
//   danach für die Sitzung.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Vcs.Worker,
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
    CanStart: TFunc<Boolean>;
    /// <summary>Kennung des aktuellen Issues; '' ohne.</summary>
    ActiveKey: TFunc<string>;
    Assign: TAtlasBoardAssignHook;
    /// <summary>Zeile in die Meldungsansicht.</summary>
    Message: TProc<string>;
  end;

  TAtlasIdeBoard = class(TInterfacedObject)
  private
    FHooks: TAtlasBoardHooks;
    FCacheFolder: string;
    FStarted: Boolean;
    FWorker: TAtlasVcsWorker;
    FCancel: IAtlasCiCancel;
    FGeneration: Integer;
    FLoading: Boolean;
    FOnline: Boolean;
    FCanWrite: Boolean;
    FMoving: Boolean;
    FTarget: TAtlasTrackerTarget;
    FBoardId: string;
    FSprintId: string;
    FOnlyMine: Boolean;
    FOnlyMineSet: Boolean;
    function Frame: TAtlasBoardFrame;
    procedure Wire(AFrame: TAtlasBoardFrame);
    function ProviderOf(const ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
    function BoardsOf(const ATarget: TAtlasTrackerTarget): IAtlasTrackerBoards;
    procedure Load(const ABoardId, ASprintId: string);
    procedure Loaded(AGeneration: Integer; const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean;
      const ASnapshot: TAtlasBoardSnapshot; AError: TAtlasCiFetchError; AWrite: Boolean);
    procedure Move(ACard, AColumn: Integer);
    procedure Moved(const AKey, AColumn, AOldState: string; const AResult: TAtlasTrackerWriteResult);
    procedure OpenCard(ACard: Integer);
    procedure StartCard(ACard: Integer);
    procedure BrowseCard(ACard: Integer);
    procedure AssignCard(ACard: Integer);
    procedure Report(const AText: string);
    function ErrorText(AError: TAtlasCiFetchError): string;
    procedure CancelLoad;
    class function NowUtc: TDateTime; static;
  public
    /// <summary>ACacheFolder: Ordner des Zwischenspeichers ('' = keiner).</summary>
    constructor Create(const AHooks: TAtlasBoardHooks; const ACacheFolder: string);
    destructor Destroy; override;
    /// <summary>Fenster bei der IDE anmelden (Desktop, #879).</summary>
    procedure Start;
    /// <summary>Abbrechen, kurz warten, Fenster abmelden; danach wirkungslos.</summary>
    procedure Stop;
    /// <summary>Fenster zeigen und das Board neu laden (Befehl Atlas.Board, Menü Ansicht › Atlas › Board).</summary>
    procedure Show;
    /// <summary>Neu laden, wenn das Fenster offen ist (Aktualisieren, #1271).</summary>
    procedure Refresh;
    /// <summary>Markierung des aktuellen Issues nachführen (nach Beginnen und Beenden).</summary>
    procedure UpdateActive;
    /// <summary>Nach geänderten Einstellungen: mit issues.board aus das Fenster schließen.</summary>
    procedure UpdateSettings;
    /// <summary>issues.board an?</summary>
    class function Active: Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.DateUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tracker.Preview,
  Atlas.Core.Tracker.Providers.GitHub,
  Atlas.Core.Tracker.Providers.GitHubBoard,
  Atlas.Core.Tracker.Providers.YouTrack,
  Atlas.Core.Tracker.Providers.YouTrackBoard,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.MoveDialog,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tracker.BoardWindow;

{ TAtlasIdeBoard }

constructor TAtlasIdeBoard.Create(const AHooks: TAtlasBoardHooks; const ACacheFolder: string);
begin
  inherited Create;
  FHooks := AHooks;
  FCacheFolder := ACacheFolder;
  FWorker := TAtlasVcsWorker.Create;
end;

destructor TAtlasIdeBoard.Destroy;
begin
  FWorker.Free;
  inherited;
end;

class function TAtlasIdeBoard.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesBoard;
end;

class function TAtlasIdeBoard.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

procedure TAtlasIdeBoard.Start;
var
  mKeep: IInterface;
  mOwner: TAtlasIdeBoard;
begin
  if FStarted then
    Exit;
  FStarted := True;
  mKeep := Self;
  mOwner := Self;
  TAtlasIdeBoardWindow.OnFrame :=
    procedure(AFrame: TAtlasBoardFrame)
    begin
      if (mKeep <> nil) and mOwner.FStarted then
        mOwner.Wire(AFrame);
    end;
  // Früh anmelden: Die IDE speichert das Fenster im Desktop und legt es beim Laden selbst an (#879).
  TAtlasIdeBoardWindow.Prepare;
end;

procedure TAtlasIdeBoard.Stop;
begin
  if not FStarted then
    Exit;
  FStarted := False;
  Inc(FGeneration);
  CancelLoad;
  FWorker.Stop(1000);
  TAtlasIdeBoardWindow.Release;
  FHooks := Default(TAtlasBoardHooks);
end;

function TAtlasIdeBoard.Frame: TAtlasBoardFrame;
begin
  Result := TAtlasIdeBoardWindow.ExistingFrame;
end;

procedure TAtlasIdeBoard.Report(const AText: string);
begin
  if Assigned(FHooks.Message) then
    FHooks.Message(AText);
end;

function TAtlasIdeBoard.ProviderOf(const ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
begin
  Result := nil;
  if Assigned(FHooks.Provider) then
    Result := FHooks.Provider(ATarget.Provider);
end;

function TAtlasIdeBoard.BoardsOf(const ATarget: TAtlasTrackerTarget): IAtlasTrackerBoards;
begin
  // Anbieter mit Board; ein weiterer Tracker meldet sich hier mit seiner Klasse.
  if SameText(ATarget.Provider, TAtlasYouTrackTracker.ProviderName) then
    Result := TAtlasYouTrackBoards.Create
  else if SameText(ATarget.Provider, TAtlasGitHubTracker.ProviderName) then
    Result := TAtlasGitHubBoards.Create
  else
    Result := nil;
end;

procedure TAtlasIdeBoard.Wire(AFrame: TAtlasBoardFrame);
var
  mKeep: IInterface;
  mOwner: TAtlasIdeBoard;
begin
  mKeep := Self;
  mOwner := Self;
  AFrame.ApplyColors(TAtlasIdeStyle.Colors);
  if not FOnlyMineSet then
  begin
    FOnlyMine := TAtlasIdeSettings.Current.IssuesBoardOnlyMine;
    FOnlyMineSet := True;
  end;
  AFrame.SetOnlyMine(FOnlyMine);
  AFrame.OnRefresh :=
    procedure
    begin
      if mKeep <> nil then
        mOwner.Load(mOwner.FBoardId, mOwner.FSprintId);
    end;
  AFrame.OnBoard :=
    procedure(AId: string)
    begin
      if mKeep <> nil then
        mOwner.Load(AId, '');
    end;
  AFrame.OnSprint :=
    procedure(AId: string)
    begin
      if mKeep <> nil then
        mOwner.Load(mOwner.FBoardId, AId);
    end;
  AFrame.OnOnlyMine :=
    procedure(AValue: Boolean)
    begin
      if mKeep <> nil then
        mOwner.FOnlyMine := AValue;
    end;
  AFrame.OnMove :=
    procedure(ACard, AColumn: Integer)
    begin
      if mKeep <> nil then
        mOwner.Move(ACard, AColumn);
    end;
  AFrame.OnOpen :=
    procedure(ACard: Integer)
    begin
      if mKeep <> nil then
        mOwner.OpenCard(ACard);
    end;
  AFrame.OnStart :=
    procedure(ACard: Integer)
    begin
      if mKeep <> nil then
        mOwner.StartCard(ACard);
    end;
  AFrame.OnBrowse :=
    procedure(ACard: Integer)
    begin
      if mKeep <> nil then
        mOwner.BrowseCard(ACard);
    end;
  AFrame.OnAssign :=
    procedure(ACard: Integer)
    begin
      if mKeep <> nil then
        mOwner.AssignCard(ACard);
    end;
  AFrame.OnHidden :=
    procedure
    begin
      // Fenster geschlossen: Laden abbrechen.
      if mKeep <> nil then
        mOwner.CancelLoad;
    end;
end;

procedure TAtlasIdeBoard.Show;
begin
  if not FStarted or not Active then
    Exit;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mFrame: TAtlasBoardFrame;
    begin
      mFrame := TAtlasIdeBoardWindow.Show;
      if mFrame <> nil then
        TAtlasIdeBoardWindow.ApplyTheme;
      Load(FBoardId, FSprintId);
    end);
end;

procedure TAtlasIdeBoard.Refresh;
begin
  if FStarted and Active and TAtlasIdeBoardWindow.Visible and not FLoading and not FMoving then
    Load(FBoardId, FSprintId);
end;

procedure TAtlasIdeBoard.UpdateActive;
var
  mFrame: TAtlasBoardFrame;
begin
  mFrame := Frame;
  if (mFrame <> nil) and Assigned(FHooks.ActiveKey) then
    mFrame.SetActiveKey(FHooks.ActiveKey());
end;

procedure TAtlasIdeBoard.UpdateSettings;
begin
  if FStarted and not Active then
  begin
    CancelLoad;
    TAtlasIdeBoardWindow.Hide;
  end;
end;

procedure TAtlasIdeBoard.CancelLoad;
begin
  if FCancel <> nil then
    FCancel.Cancel;
end;

function TAtlasIdeBoard.ErrorText(AError: TAtlasCiFetchError): string;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorToken);
    TAtlasCiFetchError.NotFound:
      Result := TAtlasStrings.Text(TAtlasTextId.BoardNoBoard);
    TAtlasCiFetchError.Timeout:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorTimeout);
    TAtlasCiFetchError.NotConfigured, TAtlasCiFetchError.UnknownProvider:
      Result := TAtlasStrings.Text(TAtlasTextId.BoardNoTracker);
    TAtlasCiFetchError.Invalid, TAtlasCiFetchError.Server:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorInvalid);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorNetwork);
  end;
end;

procedure TAtlasIdeBoard.Load(const ABoardId, ASprintId: string);
var
  mFrame: TAtlasBoardFrame;
  mTarget: TAtlasTrackerTarget;
  mProvider: IAtlasTrackerProvider;
  mBoards: IAtlasTrackerBoards;
  mTransport: IAtlasCiTransport;
  mCached: TAtlasBoardSnapshot;
  mGeneration: Integer;
  mKeep: IInterface;
  mOwner: TAtlasIdeBoard;
  mBoardId, mSprintId: string;
  mWrite, mOk: Boolean;
  mSnapshot: TAtlasBoardSnapshot;
  mError: TAtlasCiFetchError;
begin
  mFrame := Frame;
  if not FStarted or (mFrame = nil) then
    Exit;
  CancelLoad;
  Inc(FGeneration);
  mGeneration := FGeneration;
  mTarget := Default(TAtlasTrackerTarget);
  if Assigned(FHooks.Target) then
    mTarget := FHooks.Target();
  // Anderer Tracker (Projektwechsel): Auswahl von Board und Sprint und der gezeigte Stand gelten nicht mehr.
  if not SameText(mTarget.Key, FTarget.Key) then
  begin
    mBoardId := '';
    mSprintId := '';
    mFrame.ShowNotice('');
  end
  else
  begin
    mBoardId := ABoardId;
    mSprintId := ASprintId;
  end;
  FTarget := mTarget;
  FBoardId := mBoardId;
  FSprintId := mSprintId;
  FOnline := False;
  mFrame.SetCanDrag(False);
  UpdateActive;
  mProvider := ProviderOf(mTarget);
  mBoards := BoardsOf(mTarget);
  if (mTarget.Server = '') or (mProvider = nil) or (mBoards = nil) then
  begin
    mFrame.ShowNotice(TAtlasStrings.Text(TAtlasTextId.BoardNoTracker));
    mFrame.SetStatus('');
    Exit;
  end;
  // Sofort der letzte Stand; frisch geladen ersetzt ihn.
  if not mFrame.HasSnapshot and TAtlasTrackerBoard.Load(FCacheFolder, mTarget, mCached) then
    mFrame.SetSnapshot(mCached, '');
  mFrame.SetLoading(True);
  FLoading := True;
  mTransport := nil;
  if Assigned(FHooks.Transport) then
    mTransport := FHooks.Transport(mProvider, mTarget);
  if mTransport = nil then
  begin
    Loaded(mGeneration, mTarget, False, TAtlasBoardSnapshot.Empty, TAtlasCiFetchError.Unauthorized, False);
    Exit;
  end;
  if not Supports(mTransport, IAtlasCiCancel, FCancel) then
    FCancel := nil;
  // Ziehen nur mit Schreibweg.
  mWrite := Supports(mTransport, IAtlasCiSend);
  mKeep := Self;
  mOwner := Self;
  mSnapshot := TAtlasBoardSnapshot.Empty;
  mOk := False;
  mError := TAtlasCiFetchError.Network;
  if not FWorker.Run(
    procedure
    begin
      try
        mOk := mBoards.LoadBoard(mTarget, mTransport, mBoardId, mSprintId, TAtlasTrackerBoard.TimeoutMs, mSnapshot,
          mError);
      except
        // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
        on E: Exception do
        begin
          mOk := False;
          mError := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Atlas-Board: Abfrage mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mTransport := nil;
    end,
    procedure
    begin
      if mKeep <> nil then
        mOwner.Loaded(mGeneration, mTarget, mOk, mSnapshot, mError, mWrite);
    end) then
    Loaded(mGeneration, mTarget, False, TAtlasBoardSnapshot.Empty, TAtlasCiFetchError.Cancelled, False);
end;

procedure TAtlasIdeBoard.Loaded(AGeneration: Integer; const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean;
  const ASnapshot: TAtlasBoardSnapshot; AError: TAtlasCiFetchError; AWrite: Boolean);
var
  mFrame: TAtlasBoardFrame;
  mSnapshot, mCached: TAtlasBoardSnapshot;
  mWhen: string;
begin
  if AGeneration <> FGeneration then
    Exit;
  FCancel := nil;
  FLoading := False;
  mFrame := Frame;
  if not FStarted or (mFrame = nil) then
    Exit;
  mFrame.SetLoading(False);
  TAtlasGuard.Log('Atlas-Board: ' + ATarget.Provider + ', ' + TAtlasCiBuild.ErrorKey(AError));
  if ASucceeded then
  begin
    mSnapshot := ASnapshot;
    mSnapshot.Fetched := NowUtc;
    TAtlasTrackerBoard.Save(FCacheFolder, ATarget, mSnapshot);
    FBoardId := mSnapshot.Board.Id;
    FSprintId := mSnapshot.Sprint.Id;
    FOnline := True;
    FCanWrite := AWrite;
    // GitHub: Ohne Recht auf Projekte zeigt das Board Offen/Geschlossen und sagt warum.
    if mSnapshot.ProjectsDenied then
      mFrame.SetSnapshot(mSnapshot, TAtlasStrings.Text(TAtlasTextId.BoardErrorScopes))
    else
      mFrame.SetSnapshot(mSnapshot, '');
    mFrame.SetCanDrag(AWrite);
    UpdateActive;
    Exit;
  end;
  // Ohne Antwort: der letzte Stand mit Grund, Ziehen gesperrt.
  FOnline := False;
  mFrame.SetCanDrag(False);
  if TAtlasTrackerBoard.Load(FCacheFolder, ATarget, mCached) and (AError <> TAtlasCiFetchError.NotFound) then
  begin
    mWhen := FormatDateTime('dd.mm.yyyy hh:nn', TTimeZone.Local.ToLocalTime(mCached.Fetched));
    mFrame.SetSnapshot(mCached, TAtlasStrings.Fmt(TAtlasTextId.BoardOffline, [mWhen, ErrorText(AError)]));
    UpdateActive;
  end
  else if AError <> TAtlasCiFetchError.Cancelled then
  begin
    mFrame.ShowNotice(ErrorText(AError));
    mFrame.SetStatus('');
  end;
end;

procedure TAtlasIdeBoard.Move(ACard, AColumn: Integer);
var
  mFrame: TAtlasBoardFrame;
  mSnapshot: TAtlasBoardSnapshot;
  mCard: TAtlasBoardCard;
  mColumnName, mComment, mOld: string;
  mDontAsk: Boolean;
  mNext: TAtlasPluginSettings;
  mBoards: IAtlasTrackerBoards;
  mProvider: IAtlasTrackerProvider;
  mTransport: IAtlasCiTransport;
  mTarget: TAtlasTrackerTarget;
  mKeep: IInterface;
  mOwner: TAtlasIdeBoard;
  mResult: TAtlasTrackerWriteResult;
begin
  mFrame := Frame;
  if not FStarted or (mFrame = nil) or FMoving then
    Exit;
  // Ohne Verbindung kein Schreiben (#1272: Ziehen ohne Netz gesperrt).
  if not FOnline or not FCanWrite then
  begin
    mFrame.SetStatus(TAtlasStrings.Text(TAtlasTextId.BoardMoveLocked));
    Exit;
  end;
  mSnapshot := mFrame.Snapshot;
  if not TAtlasTrackerBoard.CanMove(mSnapshot, ACard, AColumn) then
    Exit;
  mCard := mSnapshot.Cards[ACard];
  mColumnName := mFrame.ColumnCaption(AColumn);
  mComment := '';
  if TAtlasIdeSettings.Current.IssuesBoardConfirmMove then
  begin
    if not TAtlasBoardMoveDialog.Execute(mCard.Key, mColumnName, mComment, mDontAsk) then
      Exit;
    if mDontAsk then
    begin
      mNext := TAtlasIdeSettings.Stored;
      mNext.IssuesBoardConfirmMove := False;
      TAtlasIdeSettings.Update(mNext);
    end;
  end;
  mTarget := FTarget;
  mProvider := ProviderOf(mTarget);
  mBoards := BoardsOf(mTarget);
  mTransport := nil;
  if (mProvider <> nil) and Assigned(FHooks.Transport) then
    mTransport := FHooks.Transport(mProvider, mTarget);
  if (mBoards = nil) or (mTransport = nil) then
  begin
    mFrame.SetStatus(TAtlasStrings.Fmt(TAtlasTextId.BoardMoveFailed, [mCard.Key,
      TAtlasStrings.Text(TAtlasTextId.TrackerWriteNotConfigured)]));
    Exit;
  end;
  // Sofort in der Zielspalte; bei einem Fehler springt die Karte zurück.
  mOld := mFrame.MoveCard(ACard, AColumn);
  mFrame.SetStatus(TAtlasStrings.Fmt(TAtlasTextId.BoardMoving, [mCard.Key]));
  FMoving := True;
  mKeep := Self;
  mOwner := Self;
  mResult := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Network, 0, '');
  if not FWorker.Run(
    procedure
    begin
      try
        mResult := mBoards.MoveCard(mTarget, mTransport, mSnapshot, mCard, AColumn, mComment,
          TAtlasTrackerBoard.MoveTimeoutMs);
      except
        on E: Exception do
        begin
          mResult := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Network, 0, '');
          TAtlasGuard.Log('Atlas-Board: Verschieben mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mTransport := nil;
    end,
    procedure
    begin
      if mKeep <> nil then
        mOwner.Moved(mCard.Key, mColumnName, mOld, mResult);
    end) then
    Moved(mCard.Key, mColumnName, mOld, TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Cancelled, 0, ''));
end;

procedure TAtlasIdeBoard.Moved(const AKey, AColumn, AOldState: string; const AResult: TAtlasTrackerWriteResult);
var
  mFrame: TAtlasBoardFrame;
begin
  FMoving := False;
  mFrame := Frame;
  if not FStarted or (mFrame = nil) then
    Exit;
  TAtlasGuard.Log('Atlas-Board: verschoben, ' + TAtlasCiBuild.ErrorKey(AResult.Error));
  if not AResult.Succeeded then
  begin
    mFrame.RevertMove(AKey, AOldState);
    mFrame.SetStatus(TAtlasStrings.Fmt(TAtlasTextId.BoardMoveFailed, [AKey,
      TAtlasTrackerEndDialog.ErrorText(AKey, AResult)]));
    Exit;
  end;
  Report(TAtlasStrings.Fmt(TAtlasTextId.BoardMoved, [AKey, AColumn]));
  // Der Tracker kann mehr geändert haben (Workflow-Regeln): neu laden.
  Load(FBoardId, FSprintId);
end;

procedure TAtlasIdeBoard.OpenCard(ACard: Integer);
var
  mFrame: TAtlasBoardFrame;
  mCard: TAtlasBoardCard;
begin
  mFrame := Frame;
  if (mFrame = nil) or (ACard < 0) then
    Exit;
  mCard := mFrame.Card(ACard);
  if mCard.Key = '' then
    Exit;
  // Aus einem anderen Repository (GitHub "owner/repo#12"): die Seite im Browser.
  if (Pos('/', mCard.Key) > 0) or not Assigned(FHooks.Preview) then
    BrowseCard(ACard)
  else
    FHooks.Preview(FTarget, mCard.Key);
end;

procedure TAtlasIdeBoard.StartCard(ACard: Integer);
var
  mFrame: TAtlasBoardFrame;
  mCard: TAtlasBoardCard;
begin
  mFrame := Frame;
  if (mFrame = nil) or (ACard < 0) or not Assigned(FHooks.Start) then
    Exit;
  mCard := mFrame.Card(ACard);
  if (mCard.Key = '') or (Pos('/', mCard.Key) > 0) then
    Exit;
  if Assigned(FHooks.CanStart) and not FHooks.CanStart() then
    Exit;
  FHooks.Start(mCard.Issue);
end;

procedure TAtlasIdeBoard.BrowseCard(ACard: Integer);
var
  mFrame: TAtlasBoardFrame;
  mPage: string;
  mProvider: IAtlasTrackerProvider;
begin
  mFrame := Frame;
  if (mFrame = nil) or (ACard < 0) then
    Exit;
  mPage := mFrame.Card(ACard).Page;
  // Seite aus der eingetragenen Adresse, sonst die aus der Antwort, aber nur als Web-Adresse ohne Benutzer.
  mProvider := ProviderOf(FTarget);
  if (Pos('/', mFrame.Card(ACard).Key) = 0) and (mProvider <> nil) and
    (mProvider.IssuePage(FTarget, mFrame.Card(ACard).Key) <> '') then
    mPage := mProvider.IssuePage(FTarget, mFrame.Card(ACard).Key);
  if TAtlasIssuePreview.MayBrowse(mPage) then
    ShellExecute(0, 'open', PChar(mPage), nil, nil, SW_SHOWNORMAL);
end;

procedure TAtlasIdeBoard.AssignCard(ACard: Integer);
var
  mFrame: TAtlasBoardFrame;
  mKey: string;
  mKeep: IInterface;
  mOwner: TAtlasIdeBoard;
begin
  mFrame := Frame;
  if (mFrame = nil) or (ACard < 0) or not Assigned(FHooks.Assign) then
    Exit;
  mKey := mFrame.Card(ACard).Key;
  if (mKey = '') or (Pos('/', mKey) > 0) then
    Exit;
  mKeep := Self;
  mOwner := Self;
  FHooks.Assign(FTarget, mKey,
    procedure(const AResult: TAtlasTrackerWriteResult)
    var
      mCurrent: TAtlasBoardFrame;
    begin
      if (mKeep = nil) or not mOwner.FStarted then
        Exit;
      mCurrent := mOwner.Frame;
      if AResult.Succeeded then
      begin
        mOwner.Report(TAtlasStrings.Fmt(TAtlasTextId.BoardAssigned, [mKey]));
        mOwner.Load(mOwner.FBoardId, mOwner.FSprintId);
      end
      else if mCurrent <> nil then
        mCurrent.SetStatus(TAtlasStrings.Fmt(TAtlasTextId.BoardAssignFailed, [mKey,
          TAtlasTrackerEndDialog.ErrorText(mKey, AResult)]));
    end);
end;

end.
