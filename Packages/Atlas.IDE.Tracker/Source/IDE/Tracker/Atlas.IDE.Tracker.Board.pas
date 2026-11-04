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
// - Workflow von YouTrack: Legt die Zustandsmaschine des Spaltenfeldes die
//   erreichbaren Spalten fest (TAtlasBoardTransitions.Known), bleibt eine
//   Karte über einer anderen Spalte stehen und die Statuszeile nennt die
//   erlaubten Übergänge, ohne Anfrage an den Server. Lehnt YouTrack einen
//   Wechsel ab, nennt die Meldung sie ebenfalls.
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
  Atlas.Core.CiBuild.Contract,
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
    procedure Load(const ABoardId, ASprintId: string);
    procedure Loaded(AGeneration: Integer; const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean;
      const ASnapshot: TAtlasBoardSnapshot; AError: TAtlasCiFetchError; AWrite: Boolean);
    procedure Move(ACard, AColumn: Integer);
    procedure Moved(const ACard: TAtlasBoardCard; const AColumn, AOldState: string;
      const AResult: TAtlasTrackerWriteResult);
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
    /// <summary>Board-Zugriff des Anbieters (optionale Fähigkeit IAtlasTrackerBoards); nil ohne Anbieter oder
    /// ohne Board (auch für die Sprint-Kachel, #1277).</summary>
    class function BoardsOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerBoards; static;
  end;

implementation

uses
  Winapi.Windows,
  System.DateUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Strings,  Atlas.UI.Tracker.Strings,
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
  begin
    Exit;
  end;
  FStarted := True;
  mKeep := Self;
  mOwner := Self;
  TAtlasIdeBoardWindow.OnFrame :=
    procedure(AFrame: TAtlasBoardFrame)
    begin
      if (mKeep <> nil) and mOwner.FStarted then
      begin
        mOwner.Wire(AFrame);
      end;
    end;
  // Früh anmelden: Die IDE speichert das Fenster im Desktop und legt es beim Laden selbst an (#879).
  TAtlasIdeBoardWindow.Prepare;
end;

procedure TAtlasIdeBoard.Stop;
begin
  if not FStarted then
  begin
    Exit;
  end;
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
  begin
    FHooks.Message(AText);
  end;
end;

function TAtlasIdeBoard.ProviderOf(const ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
begin
  Result := nil;
  if Assigned(FHooks.Provider) then
  begin
    Result := FHooks.Provider(ATarget.Provider);
  end;
end;

class function TAtlasIdeBoard.BoardsOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerBoards;
begin
  // Der Anbieter kommt über die Hooks aus der Komposition; ein Board bietet er als weitere Fähigkeit an.
  if not Supports(AProvider, IAtlasTrackerBoards, Result) then
  begin
    Result := nil;
  end;
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
      begin
        mOwner.Load(mOwner.FBoardId, mOwner.FSprintId);
      end;
    end;
  AFrame.OnBoard :=
    procedure(AId: string)
    begin
      if mKeep <> nil then
      begin
        mOwner.Load(AId, '');
      end;
    end;
  AFrame.OnSprint :=
    procedure(AId: string)
    begin
      if mKeep <> nil then
      begin
        mOwner.Load(mOwner.FBoardId, AId);
      end;
    end;
  AFrame.OnOnlyMine :=
    procedure(AValue: Boolean)
    begin
      if mKeep <> nil then
      begin
        mOwner.FOnlyMine := AValue;
      end;
    end;
  AFrame.OnMove :=
    procedure(ACard, AColumn: Integer)
    begin
      if mKeep <> nil then
      begin
        mOwner.Move(ACard, AColumn);
      end;
    end;
  AFrame.OnOpen :=
    procedure(ACard: Integer)
    begin
      if mKeep <> nil then
      begin
        mOwner.OpenCard(ACard);
      end;
    end;
  AFrame.OnStart :=
    procedure(ACard: Integer)
    begin
      if mKeep <> nil then
      begin
        mOwner.StartCard(ACard);
      end;
    end;
  AFrame.OnBrowse :=
    procedure(ACard: Integer)
    begin
      if mKeep <> nil then
      begin
        mOwner.BrowseCard(ACard);
      end;
    end;
  AFrame.OnAssign :=
    procedure(ACard: Integer)
    begin
      if mKeep <> nil then
      begin
        mOwner.AssignCard(ACard);
      end;
    end;
  AFrame.OnHidden :=
    procedure
    begin
      // Fenster geschlossen: Laden abbrechen.
      if mKeep <> nil then
      begin
        mOwner.CancelLoad;
      end;
    end;
end;

procedure TAtlasIdeBoard.Show;
begin
  if not FStarted or not Active then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mFrame: TAtlasBoardFrame;
    begin
      mFrame := TAtlasIdeBoardWindow.Show;
      if mFrame <> nil then
      begin
        TAtlasIdeBoardWindow.ApplyTheme;
      end;
      Load(FBoardId, FSprintId);
    end);
end;

procedure TAtlasIdeBoard.Refresh;
begin
  if FStarted and Active and TAtlasIdeBoardWindow.Visible and not FLoading and not FMoving then
  begin
    Load(FBoardId, FSprintId);
  end;
end;

procedure TAtlasIdeBoard.UpdateActive;
var
  mFrame: TAtlasBoardFrame;
begin
  mFrame := Frame;
  if (mFrame <> nil) and Assigned(FHooks.ActiveKey) then
  begin
    mFrame.SetActiveKey(FHooks.ActiveKey());
  end;
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
  begin
    FCancel.Cancel;
  end;
end;

function TAtlasIdeBoard.ErrorText(AError: TAtlasCiFetchError): string;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorToken);
    TAtlasCiFetchError.NotFound:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.BoardNoBoard);
    TAtlasCiFetchError.Timeout:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorTimeout);
    TAtlasCiFetchError.NotConfigured, TAtlasCiFetchError.UnknownProvider:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.BoardNoTracker);
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
  begin
    Exit;
  end;
  CancelLoad;
  Inc(FGeneration);
  mGeneration := FGeneration;
  mTarget := Default(TAtlasTrackerTarget);
  if Assigned(FHooks.Target) then
  begin
    mTarget := FHooks.Target();
  end;
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
  mBoards := BoardsOf(mProvider);
  if (mTarget.Server = '') or (mProvider = nil) or (mBoards = nil) then
  begin
    mFrame.ShowNotice(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.BoardNoTracker));
    mFrame.SetStatus('');
    Exit;
  end;
  // Sofort der letzte Stand; frisch geladen ersetzt ihn.
  if not mFrame.HasSnapshot and TAtlasTrackerBoard.Load(FCacheFolder, mTarget, mCached) then
  begin
    mFrame.SetSnapshot(mCached, '');
  end;
  mFrame.SetLoading(True);
  FLoading := True;
  mTransport := nil;
  if Assigned(FHooks.Transport) then
  begin
    mTransport := FHooks.Transport(mProvider, mTarget);
  end;
  if mTransport = nil then
  begin
    Loaded(mGeneration, mTarget, False, TAtlasBoardSnapshot.Empty, TAtlasCiFetchError.Unauthorized, False);
    Exit;
  end;
  if not Supports(mTransport, IAtlasCiCancel, FCancel) then
  begin
    FCancel := nil;
  end;
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
      begin
        mOwner.Loaded(mGeneration, mTarget, mOk, mSnapshot, mError, mWrite);
      end;
    end) then
  begin
    Loaded(mGeneration, mTarget, False, TAtlasBoardSnapshot.Empty, TAtlasCiFetchError.Cancelled, False);
  end;
end;

procedure TAtlasIdeBoard.Loaded(AGeneration: Integer; const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean;
  const ASnapshot: TAtlasBoardSnapshot; AError: TAtlasCiFetchError; AWrite: Boolean);
var
  mFrame: TAtlasBoardFrame;
  mSnapshot, mCached: TAtlasBoardSnapshot;
  mWhen: string;
begin
  if AGeneration <> FGeneration then
  begin
    Exit;
  end;
  FCancel := nil;
  FLoading := False;
  mFrame := Frame;
  if not FStarted or (mFrame = nil) then
  begin
    Exit;
  end;
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
    begin
      mFrame.SetSnapshot(mSnapshot, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.BoardErrorScopes));
    end
    else
    begin
      mFrame.SetSnapshot(mSnapshot, '');
    end;
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
    mFrame.SetSnapshot(mCached, TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.BoardOffline, [mWhen, ErrorText(AError)]));
    UpdateActive;
  end
  else if AError <> TAtlasCiFetchError.Cancelled then
  begin
    mFrame.ShowNotice(ErrorText(AError));
    mFrame.SetStatus('');
  end;
end;

/// <summary>Darf ACard nach AColumn; verbietet es der Workflow des Trackers, nennt die Statuszeile von AFrame die
/// erlaubten Übergänge.</summary>
function Movable(AFrame: TAtlasBoardFrame; const ASnapshot: TAtlasBoardSnapshot; ACard, AColumn: Integer): Boolean;
var
  mCard: TAtlasBoardCard;
  mNames: string;
begin
  Result := TAtlasBoardTransitions.Allowed(ASnapshot, ACard, AColumn);
  if Result or not TAtlasTrackerBoard.CanMove(ASnapshot, ACard, AColumn) then
  begin
    Exit;
  end;
  // Die Zustandsmaschine von YouTrack lässt diese Spalte nicht zu: gleich sagen, welche gehen.
  mCard := ASnapshot.Cards[ACard];
  mNames := TAtlasBoardTransitions.Names(mCard);
  if mNames = '' then
  begin
    AFrame.SetStatus(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.BoardMoveNoTransition, [mCard.Key, mCard.State]));
  end
  else
  begin
    AFrame.SetStatus(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.BoardMoveNotAllowed, [mCard.Key,
      AFrame.ColumnCaption(AColumn), mCard.State, mNames]));
  end;
end;

/// <summary>Text der Statuszeile, wenn das Verschieben scheiterte.</summary>
function MoveFailedText(const ACard: TAtlasBoardCard; const AResult: TAtlasTrackerWriteResult): string;
begin
  Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.BoardMoveFailed, [ACard.Key,
    TAtlasTrackerEndDialog.ErrorText(ACard.Key, AResult)]);
  // Abgelehnt (400) unter einer Zustandsmaschine: die erlaubten Übergänge dazu.
  if (AResult.Error = TAtlasCiFetchError.Invalid) and ACard.Workflow.StateMachine and
    (TAtlasBoardTransitions.Names(ACard) <> '') then
  begin
    Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.BoardMoveTransitions, [Result, ACard.State,
      TAtlasBoardTransitions.Names(ACard)]);
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
  begin
    Exit;
  end;
  // Ohne Verbindung kein Schreiben (#1272: Ziehen ohne Netz gesperrt).
  if not FOnline or not FCanWrite then
  begin
    mFrame.SetStatus(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.BoardMoveLocked));
    Exit;
  end;
  mSnapshot := mFrame.Snapshot;
  if not Movable(mFrame, mSnapshot, ACard, AColumn) then
  begin
    Exit;
  end;
  mCard := mSnapshot.Cards[ACard];
  mColumnName := mFrame.ColumnCaption(AColumn);
  mComment := '';
  if TAtlasIdeSettings.Current.IssuesBoardConfirmMove then
  begin
    if not TAtlasBoardMoveDialog.Execute(mCard.Key, mColumnName, mComment, mDontAsk) then
    begin
      Exit;
    end;
    if mDontAsk then
    begin
      mNext := TAtlasIdeSettings.Stored;
      mNext.IssuesBoardConfirmMove := False;
      TAtlasIdeSettings.Update(mNext);
    end;
  end;
  mTarget := FTarget;
  mProvider := ProviderOf(mTarget);
  mBoards := BoardsOf(mProvider);
  mTransport := nil;
  if (mProvider <> nil) and Assigned(FHooks.Transport) then
  begin
    mTransport := FHooks.Transport(mProvider, mTarget);
  end;
  if (mBoards = nil) or (mTransport = nil) then
  begin
    mFrame.SetStatus(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.BoardMoveFailed, [mCard.Key,
      TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerWriteNotConfigured)]));
    Exit;
  end;
  // Sofort in der Zielspalte; bei einem Fehler springt die Karte zurück.
  mOld := mFrame.MoveCard(ACard, AColumn);
  mFrame.SetStatus(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.BoardMoving, [mCard.Key]));
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
      begin
        mOwner.Moved(mCard, mColumnName, mOld, mResult);
      end;
    end) then
  begin
    Moved(mCard, mColumnName, mOld, TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Cancelled, 0, ''));
  end;
end;

procedure TAtlasIdeBoard.Moved(const ACard: TAtlasBoardCard; const AColumn, AOldState: string;
  const AResult: TAtlasTrackerWriteResult);
var
  mFrame: TAtlasBoardFrame;
begin
  FMoving := False;
  mFrame := Frame;
  if not FStarted or (mFrame = nil) then
  begin
    Exit;
  end;
  TAtlasGuard.Log('Atlas-Board: verschoben, ' + TAtlasCiBuild.ErrorKey(AResult.Error));
  if not AResult.Succeeded then
  begin
    mFrame.RevertMove(ACard.Key, AOldState);
    mFrame.SetStatus(MoveFailedText(ACard, AResult));
    Exit;
  end;
  Report(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.BoardMoved, [ACard.Key, AColumn]));
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
  begin
    Exit;
  end;
  mCard := mFrame.Card(ACard);
  if mCard.Key = '' then
  begin
    Exit;
  end;
  // Aus einem anderen Repository (GitHub "owner/repo#12"): die Seite im Browser.
  if (Pos('/', mCard.Key) > 0) or not Assigned(FHooks.Preview) then
  begin
    BrowseCard(ACard);
  end
  else
  begin
    FHooks.Preview(FTarget, mCard.Key);
  end;
end;

procedure TAtlasIdeBoard.StartCard(ACard: Integer);
var
  mFrame: TAtlasBoardFrame;
  mCard: TAtlasBoardCard;
begin
  mFrame := Frame;
  if (mFrame = nil) or (ACard < 0) or not Assigned(FHooks.Start) then
  begin
    Exit;
  end;
  mCard := mFrame.Card(ACard);
  if (mCard.Key = '') or (Pos('/', mCard.Key) > 0) then
  begin
    Exit;
  end;
  if Assigned(FHooks.CanStart) and not FHooks.CanStart() then
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  mPage := mFrame.Card(ACard).Page;
  // Seite aus der eingetragenen Adresse, sonst die aus der Antwort, aber nur als Web-Adresse ohne Benutzer.
  mProvider := ProviderOf(FTarget);
  if (Pos('/', mFrame.Card(ACard).Key) = 0) and (mProvider <> nil) and
    (mProvider.IssuePage(FTarget, mFrame.Card(ACard).Key) <> '') then
  begin
    mPage := mProvider.IssuePage(FTarget, mFrame.Card(ACard).Key);
  end;
  TAtlasIssuePreview.Browse(mPage);
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
  begin
    Exit;
  end;
  mKey := mFrame.Card(ACard).Key;
  if (mKey = '') or (Pos('/', mKey) > 0) then
  begin
    Exit;
  end;
  mKeep := Self;
  mOwner := Self;
  FHooks.Assign(FTarget, mKey,
    procedure(const AResult: TAtlasTrackerWriteResult)
    var
      mCurrent: TAtlasBoardFrame;
    begin
      if (mKeep = nil) or not mOwner.FStarted then
      begin
        Exit;
      end;
      mCurrent := mOwner.Frame;
      if AResult.Succeeded then
      begin
        mOwner.Report(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.BoardAssigned, [mKey]));
        mOwner.Load(mOwner.FBoardId, mOwner.FSprintId);
      end
      else if mCurrent <> nil then
      begin
        mCurrent.SetStatus(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.BoardAssignFailed, [mKey,
          TAtlasTrackerEndDialog.ErrorText(mKey, AResult)]));
      end;
    end);
end;

end.
