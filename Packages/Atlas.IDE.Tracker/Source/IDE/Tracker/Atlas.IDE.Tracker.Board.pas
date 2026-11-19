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
//   Das Laden liegt in Atlas.IDE.Tracker.BoardLoad, das Ziehen in
//   Atlas.IDE.Tracker.BoardMove; diese Unit steuert Fenster und Karten.
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
//   Kontextmenü: Beginnen, Prüfen … (#2126), Vorschau, Im Browser öffnen, Kennung kopieren,
//   Mir zuweisen (Schreibweg #1266).
// - „Nur meine“ gilt beim Öffnen nach issues.board.onlyMine, der Umschalter
//   danach für die Sitzung.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Diagnostics.BackgroundJobs,
  Atlas.UI.Tracker.BoardFrame,
  Atlas.Core.Notifications.MessageSink,
  Atlas.IDE.Tracker.BoardLoad,
  Atlas.IDE.Tracker.BoardMove;

type
  TAtlasBoardHooks = Atlas.IDE.Tracker.BoardLoad.TAtlasBoardHooks;

  TAtlasIdeBoard = class(TInterfacedObject)
  private
    FHooks: TAtlasBoardHooks;
    FMessage: TAtlasMessageSink;
    FStarted: Boolean;
    FWorker: TAtlasBackgroundJobs;
    FLoad: TAtlasIdeBoardLoad;
    FLoadRef: IInterface;
    FMove: TAtlasIdeBoardMove;
    FMoveRef: IInterface;
    FOnlyMine: Boolean;
    FOnlyMineSet: Boolean;
    function Frame: TAtlasBoardFrame;
    procedure Wire(AFrame: TAtlasBoardFrame);
    procedure OpenCard(ACard: Integer);
    /// <summary>„Beginnen“ bzw. mit AReview „Prüfen …“ (#2126) an der Karte ACard.</summary>
    procedure StartCard(ACard: Integer; AReview: Boolean);
    procedure BrowseCard(ACard: Integer);
    procedure AssignCard(ACard: Integer);
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
  Atlas.Core.Tracker.BoardPlan,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.EndDialog,
  Atlas.UI.Tracker.Board.Strings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tracker.BoardWindow;

{ TAtlasIdeBoard }

constructor TAtlasIdeBoard.Create(const AHooks: TAtlasBoardHooks; const ACacheFolder: string);
begin
  inherited Create;
  FHooks := AHooks;
  FMessage := TAtlasMessageSink.Create(FHooks.Message);
  // Ein Worker für Laden und Verschieben: Stop wartet auf beide.
  FWorker := TAtlasBackgroundJobs.Create(HInstance);
  FLoad := TAtlasIdeBoardLoad.Create(AHooks, ACacheFolder, FWorker);
  FLoadRef := FLoad;
  FMove := TAtlasIdeBoardMove.Create(FLoad, AHooks, FWorker);
  FMoveRef := FMove;
end;

destructor TAtlasIdeBoard.Destroy;
begin
  FWorker.Free;
  inherited;
end;

function TAtlasIdeBoard.Frame: TAtlasBoardFrame;
begin
  Result := TAtlasIdeBoardWindow.ExistingFrame;
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
  // Aus einem anderen Repository (GitHub "owner/repo#12"): die Seite im Browser.
  case TAtlasBoardPlan.CardOpen(mCard.Key, Assigned(FHooks.Preview)) of
    TAtlasBoardCardOpen.Preview:
      FHooks.Preview(FLoad.Target, mCard.Key);
    TAtlasBoardCardOpen.Browse:
      BrowseCard(ACard);
  end;
end;

procedure TAtlasIdeBoard.StartCard(ACard: Integer; AReview: Boolean);
var
  mFrame: TAtlasBoardFrame;
  mCard: TAtlasBoardCard;
  mAction: TProc<TAtlasTrackerIssue>;
begin
  mFrame := Frame;
  mAction := FHooks.Start;
  if AReview then
  begin
    mAction := FHooks.Review;
  end;
  if (mFrame = nil) or (ACard < 0) or not Assigned(mAction) then
  begin
    Exit;
  end;
  mCard := mFrame.Card(ACard);
  if not TAtlasBoardPlan.Actionable(mCard.Key) then
  begin
    Exit;
  end;
  if Assigned(FHooks.CanStart) and not FHooks.CanStart() then
  begin
    Exit;
  end;
  mAction(mCard.Issue);
end;

procedure TAtlasIdeBoard.BrowseCard(ACard: Integer);
var
  mFrame: TAtlasBoardFrame;
  mCard: TAtlasBoardCard;
  mPage: string;
  mProvider: IAtlasTrackerProvider;
begin
  mFrame := Frame;
  if (mFrame = nil) or (ACard < 0) then
  begin
    Exit;
  end;
  mCard := mFrame.Card(ACard);
  // Seite aus der eingetragenen Adresse, sonst die aus der Antwort, aber nur als Web-Adresse ohne Benutzer.
  mPage := '';
  mProvider := FLoad.ProviderOf(FLoad.Target);
  if not TAtlasBoardPlan.Foreign(mCard.Key) and (mProvider <> nil) then
  begin
    mPage := mProvider.IssuePage(FLoad.Target, mCard.Key);
  end;
  TAtlasIssuePreview.Browse(TAtlasBoardPlan.BrowsePage(mCard.Key, mCard.Page, mPage));
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
  if not TAtlasBoardPlan.Actionable(mKey) then
  begin
    Exit;
  end;
  mKeep := Self;
  mOwner := Self;
  FHooks.Assign(FLoad.Target, mKey,
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
        mOwner.FMessage.Say(TAtlasBoardStrings.Fmt(TAtlasBoardTextId.BoardAssigned, [mKey]));
        mOwner.FLoad.Reload;
      end
      else if mCurrent <> nil then
      begin
        mCurrent.SetStatus(TAtlasBoardStrings.Fmt(TAtlasBoardTextId.BoardAssignFailed, [mKey,
          TAtlasTrackerEndDialog.ErrorText(mKey, AResult)]));
      end;
    end);
end;

/// <summary>Laden, Auswahl und Schließen in AEvents an AOwner; AKeep hält AOwner, solange der Frame lebt.
/// </summary>
procedure AddLoadEvents(var AEvents: TAtlasBoardFrameEvents; AOwner: TAtlasIdeBoard; const AKeep: IInterface);
var
  mKeep: IInterface;
  mOwner: TAtlasIdeBoard;
begin
  mKeep := AKeep;
  mOwner := AOwner;
  AEvents.Refresh :=
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.FLoad.Reload;
      end;
    end;
  AEvents.Board :=
    procedure(AId: string)
    begin
      if mKeep <> nil then
      begin
        mOwner.FLoad.Load(AId, '');
      end;
    end;
  AEvents.Sprint :=
    procedure(AId: string)
    begin
      if mKeep <> nil then
      begin
        mOwner.FLoad.Load(mOwner.FLoad.BoardId, AId);
      end;
    end;
  AEvents.OnlyMine :=
    procedure(AValue: Boolean)
    begin
      if mKeep <> nil then
      begin
        mOwner.FOnlyMine := AValue;
      end;
    end;
  AEvents.Hidden :=
    procedure
    begin
      // Fenster geschlossen: Laden abbrechen.
      if mKeep <> nil then
      begin
        mOwner.FLoad.CancelLoad;
      end;
    end;
end;

/// <summary>Karten in AEvents an AOwner; AKeep hält AOwner, solange der Frame lebt.</summary>
procedure AddCardEvents(var AEvents: TAtlasBoardFrameEvents; AOwner: TAtlasIdeBoard; const AKeep: IInterface);
var
  mKeep: IInterface;
  mOwner: TAtlasIdeBoard;
begin
  mKeep := AKeep;
  mOwner := AOwner;
  AEvents.Move :=
    procedure(ACard, AColumn: Integer)
    begin
      if mKeep <> nil then
      begin
        mOwner.FMove.Move(ACard, AColumn);
      end;
    end;
  AEvents.Open :=
    procedure(ACard: Integer)
    begin
      if mKeep <> nil then
      begin
        mOwner.OpenCard(ACard);
      end;
    end;
  AEvents.Start :=
    procedure(ACard: Integer)
    begin
      if mKeep <> nil then
      begin
        mOwner.StartCard(ACard, False);
      end;
    end;
  AEvents.Review :=
    procedure(ACard: Integer)
    begin
      if mKeep <> nil then
      begin
        mOwner.StartCard(ACard, True);
      end;
    end;
  AEvents.Browse :=
    procedure(ACard: Integer)
    begin
      if mKeep <> nil then
      begin
        mOwner.BrowseCard(ACard);
      end;
    end;
  AEvents.Assign :=
    procedure(ACard: Integer)
    begin
      if mKeep <> nil then
      begin
        mOwner.AssignCard(ACard);
      end;
    end;
end;

/// <summary>Ereignisse des Frames an AOwner; AKeep hält AOwner, solange der Frame lebt.</summary>
function BoardEvents(AOwner: TAtlasIdeBoard; const AKeep: IInterface): TAtlasBoardFrameEvents;
begin
  Result := Default(TAtlasBoardFrameEvents);
  AddLoadEvents(Result, AOwner, AKeep);
  AddCardEvents(Result, AOwner, AKeep);
end;

procedure TAtlasIdeBoard.Wire(AFrame: TAtlasBoardFrame);
begin
  AFrame.ApplyColors(TAtlasIdeStyle.WindowColorsIf(TAtlasIdeSettings.Current.IssuesIdeColors));
  if not FOnlyMineSet then
  begin
    FOnlyMine := TAtlasIdeSettings.Current.IssuesBoardOnlyMine;
    FOnlyMineSet := True;
  end;
  AFrame.SetOnlyMine(FOnlyMine);
  AFrame.Events := BoardEvents(Self, Self);
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
  FLoad.Stop;
  FMove.Stop;
  FWorker.Stop(1000);
  TAtlasIdeBoardWindow.Release;
  FHooks := Default(TAtlasBoardHooks);
  FMessage.Clear;
end;

procedure TAtlasIdeBoard.Show;
begin
  if not FStarted or not Active then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.Tracker,
    procedure
    var
      mFrame: TAtlasBoardFrame;
    begin
      mFrame := TAtlasIdeBoardWindow.Show;
      if mFrame <> nil then
      begin
        TAtlasIdeBoardWindow.ApplyTheme;
      end;
      FLoad.Reload;
    end);
end;

procedure TAtlasIdeBoard.Refresh;
begin
  if TAtlasBoardPlan.Refreshes(FStarted, Active, TAtlasIdeBoardWindow.Visible, FLoad.Loading, FMove.Moving) then
  begin
    FLoad.Reload;
  end;
end;

procedure TAtlasIdeBoard.UpdateActive;
begin
  FLoad.UpdateActive;
end;

procedure TAtlasIdeBoard.UpdateSettings;
begin
  if FStarted and not Active then
  begin
    FLoad.CancelLoad;
    TAtlasIdeBoardWindow.Hide;
  end;
end;

class function TAtlasIdeBoard.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesBoard;
end;

class function TAtlasIdeBoard.BoardsOf(const AProvider: IAtlasTrackerProvider): IAtlasTrackerBoards;
begin
  Result := TAtlasIdeBoardLoad.BoardsOf(AProvider);
end;

end.
