unit Atlas.IDE.Tracker.BoardMove;

// Verschieben im Fenster „Atlas-Board“ (#1272): Prüfen, ob die Karte in die
// Spalte darf (ohne Verbindung gesperrt, Workflow von YouTrack nennt die
// erlaubten Übergänge), Rückfrage (issues.board.confirmMove; „Nicht mehr
// fragen“ schaltet sie aus), die Karte sofort in der Zielspalte zeigen und im
// Hintergrund über IAtlasTrackerBoards.MoveCard schreiben. Bei einem Fehler
// springt sie zurück und die Statuszeile nennt den Grund; nach dem Erfolg lädt
// das Board neu (der Tracker kann mehr geändert haben).

interface

uses
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board,
  Atlas.Core.VersionControl.Worker,
  Atlas.Core.Notifications.MessageSink,
  Atlas.UI.Tracker.BoardFrame,
  Atlas.IDE.Tracker.BoardLoad;

type
  TAtlasIdeBoardMove = class(TInterfacedObject)
  private
    type
      /// <summary>Verschieben im Hintergrund: was der Worker braucht.</summary>
      TMoveJob = record
        Target: TAtlasTrackerTarget;
        Boards: IAtlasTrackerBoards;
        Transport: IAtlasCiTransport;
        /// <summary>Stand vor dem Verschieben.</summary>
        Snapshot: TAtlasBoardSnapshot;
        Card: TAtlasBoardCard;
        Column: Integer;
        ColumnName: string;
        Comment: string;
        /// <summary>Wert vor dem Verschieben (zum Zurückspringen).</summary>
        Old: string;
      end;
  private
    FLoad: TAtlasIdeBoardLoad;
    FLoadRef: IInterface;
    FTransport: TAtlasBoardTransportHook;
    FMessage: TAtlasMessageSink;
    FWorker: TAtlasVcsWorker;
    FStopped: Boolean;
    FMoving: Boolean;
    function Allowed(AFrame: TAtlasBoardFrame; ACard, AColumn: Integer; out AJob: TMoveJob): Boolean;
    function Prepare(AFrame: TAtlasBoardFrame; var AJob: TMoveJob): Boolean;
    procedure Run(const AJob: TMoveJob);
    procedure Moved(const ACard: TAtlasBoardCard; const AColumn, AOldState: string;
      const AResult: TAtlasTrackerWriteResult);
  public
    /// <summary>ALoad liefert Tracker und Verbindung und lädt nach dem Verschieben neu; AWorker gehört dem
    /// Board.</summary>
    constructor Create(ALoad: TAtlasIdeBoardLoad; const AHooks: TAtlasBoardHooks; AWorker: TAtlasVcsWorker);
    /// <summary>Karte ACard nach Spalte AColumn ziehen (Ereignis des Frames).</summary>
    procedure Move(ACard, AColumn: Integer);
    /// <summary>Danach wirkungslos (auf den Worker wartet das Board).</summary>
    procedure Stop;
    /// <summary>Ein Verschieben läuft noch.</summary>
    property Moving: Boolean read FMoving;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.BoardPlan,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Tracker.EndDialog,
  Atlas.UI.Tracker.Board.Strings,
  Atlas.UI.Tracker.Workflow.Strings,
  Atlas.UI.Tracker.MoveDialog,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tracker.BoardWindow;

{ TAtlasIdeBoardMove }

constructor TAtlasIdeBoardMove.Create(ALoad: TAtlasIdeBoardLoad; const AHooks: TAtlasBoardHooks;
  AWorker: TAtlasVcsWorker);
begin
  inherited Create;
  FLoad := ALoad;
  FLoadRef := ALoad;
  FTransport := AHooks.Transport;
  FMessage := TAtlasMessageSink.Create(AHooks.Message);
  FWorker := AWorker;
end;

procedure TAtlasIdeBoardMove.Stop;
begin
  if FStopped then
  begin
    Exit;
  end;
  FStopped := True;
  FTransport := nil;
  FMessage.Clear;
end;

/// <summary>Darf ACard nach AColumn? Ohne Verbindung kein Schreiben (#1272: Ziehen ohne Netz gesperrt); verbietet es
/// der Workflow des Trackers, nennt die Statuszeile die erlaubten Übergänge.</summary>
function TAtlasIdeBoardMove.Allowed(AFrame: TAtlasBoardFrame; ACard, AColumn: Integer; out AJob: TMoveJob): Boolean;
var
  mCard: TAtlasBoardCard;
  mCheck: TAtlasBoardMoveCheck;
begin
  AJob := Default(TMoveJob);
  AJob.Snapshot := AFrame.Snapshot;
  mCheck := TAtlasBoardPlan.MoveCheck(FLoad.Online, FLoad.CanWrite, AJob.Snapshot, ACard, AColumn);
  Result := mCheck = TAtlasBoardMoveCheck.Allowed;
  case mCheck of
    TAtlasBoardMoveCheck.Allowed:
      begin
        AJob.Card := AJob.Snapshot.Cards[ACard];
        AJob.Column := AColumn;
        AJob.ColumnName := AFrame.ColumnCaption(AColumn);
      end;
    TAtlasBoardMoveCheck.Locked:
      AFrame.SetStatus(TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardMoveLocked));
    TAtlasBoardMoveCheck.Refused:
      // Gleiche Spalte oder Spalte ohne Wert: ohne Meldung.
      ;
    TAtlasBoardMoveCheck.NoTransition:
      begin
        // Die Zustandsmaschine von YouTrack lässt diese Spalte nicht zu: gleich sagen, welche gehen.
        mCard := AJob.Snapshot.Cards[ACard];
        AFrame.SetStatus(TAtlasBoardStrings.Fmt(TAtlasBoardTextId.BoardMoveNoTransition, [mCard.Key, mCard.State]));
      end;
    TAtlasBoardMoveCheck.NotAllowed:
      begin
        mCard := AJob.Snapshot.Cards[ACard];
        AFrame.SetStatus(TAtlasBoardStrings.Fmt(TAtlasBoardTextId.BoardMoveNotAllowed, [mCard.Key,
          AFrame.ColumnCaption(AColumn), mCard.State, TAtlasBoardTransitions.Names(mCard)]));
      end;
  end;
end;

/// <summary>Rückfrage (issues.board.confirmMove) mit Kommentar; False = abgebrochen.</summary>
function ConfirmMove(const AKey, AColumn: string; out AComment: string): Boolean;
var
  mDontAsk: Boolean;
  mNext: TAtlasPluginSettings;
begin
  AComment := '';
  Result := True;
  if TAtlasIdeSettings.Current.IssuesBoardConfirmMove then
  begin
    Result := TAtlasBoardMoveDialog.Execute(AKey, AColumn, AComment, mDontAsk);
    if Result and mDontAsk then
    begin
      mNext := TAtlasIdeSettings.Stored;
      mNext.IssuesBoardConfirmMove := False;
      TAtlasIdeSettings.Update(mNext);
    end;
  end;
end;

/// <summary>Board-Zugriff und Transport für das Verschieben; ohne Schreibweg False und Grund in der
/// Statuszeile.</summary>
function TAtlasIdeBoardMove.Prepare(AFrame: TAtlasBoardFrame; var AJob: TMoveJob): Boolean;
var
  mProvider: IAtlasTrackerProvider;
begin
  AJob.Target := FLoad.Target;
  mProvider := FLoad.ProviderOf(AJob.Target);
  AJob.Boards := TAtlasIdeBoardLoad.BoardsOf(mProvider);
  AJob.Transport := nil;
  if (mProvider <> nil) and Assigned(FTransport) then
  begin
    AJob.Transport := FTransport(mProvider, AJob.Target);
  end;
  Result := (AJob.Boards <> nil) and (AJob.Transport <> nil);
  if not Result then
  begin
    AFrame.SetStatus(TAtlasBoardStrings.Fmt(TAtlasBoardTextId.BoardMoveFailed, [AJob.Card.Key,
      TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.TrackerWriteNotConfigured)]));
  end;
end;

/// <summary>Karte im Hintergrund verschieben; das Ergebnis geht im Hauptthread an Moved.</summary>
procedure TAtlasIdeBoardMove.Run(const AJob: TMoveJob);
var
  mJob: TMoveJob;
  mKeep: IInterface;
  mOwner: TAtlasIdeBoardMove;
  mResult: TAtlasTrackerWriteResult;
begin
  mJob := AJob;
  mKeep := Self;
  mOwner := Self;
  mResult := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Network, 0, '');
  if not FWorker.Run(
    procedure
    begin
      try
        mResult := mJob.Boards.MoveCard(TAtlasBoardMove.Create(mJob.Target, mJob.Transport, mJob.Card, mJob.Column,
          mJob.Comment, TAtlasTrackerBoard.cMoveTimeoutMs), mJob.Snapshot);
      except
        on E: Exception do
        begin
          mResult := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Network, 0, '');
          TAtlasGuard.Log('Atlas-Board: Verschieben mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mJob.Transport := nil;
    end,
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.Moved(mJob.Card, mJob.ColumnName, mJob.Old, mResult);
      end;
    end) then
  begin
    Moved(mJob.Card, mJob.ColumnName, mJob.Old, TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Cancelled, 0, ''));
  end;
end;

procedure TAtlasIdeBoardMove.Move(ACard, AColumn: Integer);
var
  mFrame: TAtlasBoardFrame;
  mJob: TMoveJob;
  mGo: Boolean;
begin
  mFrame := TAtlasIdeBoardWindow.ExistingFrame;
  mGo := not FStopped and (mFrame <> nil) and not FMoving;
  mGo := mGo and Allowed(mFrame, ACard, AColumn, mJob) and ConfirmMove(mJob.Card.Key, mJob.ColumnName, mJob.Comment)
    and Prepare(mFrame, mJob);
  if mGo then
  begin
    // Sofort in der Zielspalte; bei einem Fehler springt die Karte zurück.
    mJob.Old := mFrame.MoveCard(ACard, AColumn);
    mFrame.SetStatus(TAtlasBoardStrings.Fmt(TAtlasBoardTextId.BoardMoving, [mJob.Card.Key]));
    FMoving := True;
    Run(mJob);
  end;
end;

/// <summary>Text der Statuszeile, wenn das Verschieben scheiterte.</summary>
function MoveFailedText(const ACard: TAtlasBoardCard; const AResult: TAtlasTrackerWriteResult): string;
begin
  Result := TAtlasBoardStrings.Fmt(TAtlasBoardTextId.BoardMoveFailed, [ACard.Key,
    TAtlasTrackerEndDialog.ErrorText(ACard.Key, AResult)]);
  // Abgelehnt (400) unter einer Zustandsmaschine: die erlaubten Übergänge dazu.
  if TAtlasBoardPlan.ShowsTransitions(ACard, AResult) then
  begin
    Result := TAtlasBoardStrings.Fmt(TAtlasBoardTextId.BoardMoveTransitions, [Result, ACard.State,
      TAtlasBoardTransitions.Names(ACard)]);
  end;
end;

procedure TAtlasIdeBoardMove.Moved(const ACard: TAtlasBoardCard; const AColumn, AOldState: string;
  const AResult: TAtlasTrackerWriteResult);
var
  mFrame: TAtlasBoardFrame;
begin
  FMoving := False;
  mFrame := TAtlasIdeBoardWindow.ExistingFrame;
  if FStopped or (mFrame = nil) then
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
  FMessage.Say(TAtlasBoardStrings.Fmt(TAtlasBoardTextId.BoardMoved, [ACard.Key, AColumn]));
  // Der Tracker kann mehr geändert haben (Workflow-Regeln): neu laden.
  FLoad.Reload;
end;

end.
