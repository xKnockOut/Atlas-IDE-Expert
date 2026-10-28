unit Atlas.UI.Tracker.BoardFrame.Tests;

// Tests des Fensters „Atlas-Board“ (#1272) ohne IDE: Anordnung der Spalten und
// Karten (breit und schmal, eingeklappte Gruppen, Treffer der Maus), Farben
// aus "#rrggbb", Filter „Nur meine“ im Frame, sofortiges Verschieben mit
// Rücksprung, Beschriftung der Spalten und der Dialog „Verschieben“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasBoardFrameTests = class
  private
    FSaved: Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure WideLayoutPutsColumnsSideBySide;
    [Test]
    procedure CardsWithoutColumnGetOwnColumn;
    [Test]
    procedure NarrowLayoutStacksAndCollapses;
    [Test]
    procedure HitTesting;
    [Test]
    procedure WebColors;
    [Test]
    procedure FrameFiltersOnlyMine;
    [Test]
    procedure MoveAndRevert;
    [Test]
    procedure ColumnCaptions;
    [Test]
    procedure NoticeHidesBoard;
    [Test]
    procedure MoveDialogTexts;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Tracker.Board,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.BoardFrame,
  Atlas.UI.Tracker.MoveDialog;

function NewCard(const AKey, AState, ALogin: string): TAtlasBoardCard;
begin
  Result := Default(TAtlasBoardCard);
  Result.Key := AKey;
  Result.Title := 'Titel ' + AKey;
  Result.State := AState;
  if ALogin <> '' then
    Result.Logins := TArray<string>.Create(ALogin);
end;

function Snapshot: TAtlasBoardSnapshot;
begin
  Result := TAtlasBoardSnapshot.Empty;
  Result.Kind := TAtlasBoardKind.Agile;
  Result.Field := 'State';
  Result.Me := 'marco';
  Result.Columns := [TAtlasBoardColumn.Create('Offen', TArray<string>.Create('Open', 'Submitted'), '', False),
    TAtlasBoardColumn.Create('In Arbeit', TArray<string>.Create('In Progress'), '', False),
    TAtlasBoardColumn.Create('Erledigt', TArray<string>.Create('Done'), '', True)];
  Result.Cards := [NewCard('ATL-1', 'Open', 'marco'), NewCard('ATL-2', 'Submitted', 'anna'),
    NewCard('ATL-3', 'In Progress', 'marco'), NewCard('ATL-4', 'Done', '')];
end;

function Metrics: TAtlasBoardMetrics;
begin
  Result := TAtlasBoardMetrics.Create(16);
end;

function AllCards(const ASnapshot: TAtlasBoardSnapshot): TArray<Integer>;
begin
  Result := TAtlasTrackerBoard.Visible(ASnapshot, False, '');
end;

function Center(const ARect: TRect): TPoint;
begin
  Result := Point((ARect.Left + ARect.Right) div 2, (ARect.Top + ARect.Bottom) div 2);
end;

{ TAtlasBoardFrameTests }

procedure TAtlasBoardFrameTests.Setup;
begin
  FSaved := Ord(TAtlasStrings.Language);
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasBoardFrameTests.TearDown;
begin
  TAtlasStrings.Language := TAtlasLanguage(FSaved);
end;

procedure TAtlasBoardFrameTests.WideLayoutPutsColumnsSideBySide;
var
  mSnapshot: TAtlasBoardSnapshot;
  mLayout: TAtlasBoardLayout;
begin
  mSnapshot := Snapshot;
  mLayout := TAtlasBoardLayout.Build(mSnapshot, AllCards(mSnapshot), 800, nil, Metrics);
  Assert.IsFalse(mLayout.Narrow);
  Assert.AreEqual(3, Integer(Length(mLayout.Columns)), 'keine Spalte „ohne Spalte“');
  Assert.AreEqual(2, mLayout.Counts[0]);
  Assert.AreEqual(1, mLayout.Counts[1]);
  Assert.AreEqual(1, mLayout.Counts[2]);
  Assert.AreEqual(4, Integer(Length(mLayout.Places)));
  // Nebeneinander, gleiche Höhe der Köpfe.
  Assert.IsTrue(mLayout.Headers[1].Left > mLayout.Headers[0].Right);
  Assert.AreEqual(mLayout.Headers[0].Top, mLayout.Headers[2].Top);
  Assert.IsTrue(mLayout.Width >= 800);
  // Mindestbreite: viele Spalten in wenig Platz werden breiter als das Fenster (Bildlauf).
  mLayout := TAtlasBoardLayout.Build(mSnapshot, AllCards(mSnapshot), 400, nil, Metrics);
  Assert.IsTrue(mLayout.Width > 400);
end;

procedure TAtlasBoardFrameTests.CardsWithoutColumnGetOwnColumn;
var
  mSnapshot: TAtlasBoardSnapshot;
  mLayout: TAtlasBoardLayout;
begin
  mSnapshot := Snapshot;
  mSnapshot.Cards := mSnapshot.Cards + [NewCard('ATL-5', 'Wartet', '')];
  mLayout := TAtlasBoardLayout.Build(mSnapshot, AllCards(mSnapshot), 1000, nil, Metrics);
  Assert.AreEqual(4, Integer(Length(mLayout.Columns)));
  Assert.AreEqual(-1, mLayout.Columns[3]);
  Assert.AreEqual(1, mLayout.Counts[3]);
  // Ausgefiltert: keine Spalte „ohne Spalte“.
  mLayout := TAtlasBoardLayout.Build(mSnapshot, TAtlasTrackerBoard.Visible(mSnapshot, False, 'ATL-1'), 1000, nil,
    Metrics);
  Assert.AreEqual(3, Integer(Length(mLayout.Columns)));
end;

procedure TAtlasBoardFrameTests.NarrowLayoutStacksAndCollapses;
var
  mSnapshot: TAtlasBoardSnapshot;
  mLayout: TAtlasBoardLayout;
  mPlace: TAtlasBoardPlace;
begin
  mSnapshot := Snapshot;
  mLayout := TAtlasBoardLayout.Build(mSnapshot, AllCards(mSnapshot), 300, nil, Metrics);
  Assert.IsTrue(mLayout.Narrow);
  Assert.AreEqual(300, mLayout.Width);
  Assert.AreEqual(mLayout.Headers[0].Left, mLayout.Headers[1].Left, 'untereinander');
  Assert.IsTrue(mLayout.Headers[1].Top >= mLayout.Areas[0].Bottom);
  Assert.AreEqual(4, Integer(Length(mLayout.Places)));
  // Gruppe „Offen“ eingeklappt: Kopf bleibt mit Anzahl, Karten verschwinden.
  mLayout := TAtlasBoardLayout.Build(mSnapshot, AllCards(mSnapshot), 300, TArray<Integer>.Create(0), Metrics);
  Assert.AreEqual(2, mLayout.Counts[0]);
  Assert.AreEqual(2, Integer(Length(mLayout.Places)));
  Assert.IsFalse(mLayout.PlaceOf(0, mPlace));
  Assert.IsTrue(mLayout.PlaceOf(2, mPlace));
  Assert.AreEqual(1, mPlace.Column);
  // Breit wirkt Einklappen nicht.
  mLayout := TAtlasBoardLayout.Build(mSnapshot, AllCards(mSnapshot), 800, TArray<Integer>.Create(0), Metrics);
  Assert.AreEqual(4, Integer(Length(mLayout.Places)));
end;

procedure TAtlasBoardFrameTests.HitTesting;
var
  mSnapshot: TAtlasBoardSnapshot;
  mLayout: TAtlasBoardLayout;
  mPlace: TAtlasBoardPlace;
begin
  mSnapshot := Snapshot;
  mLayout := TAtlasBoardLayout.Build(mSnapshot, AllCards(mSnapshot), 800, nil, Metrics);
  Assert.IsTrue(mLayout.PlaceOf(2, mPlace));
  Assert.AreEqual(2, mLayout.CardAt(Center(mPlace.Bounds)));
  Assert.AreEqual(1, mLayout.ColumnAt(Center(mPlace.Bounds)));
  Assert.AreEqual(2, mLayout.HeaderAt(Center(mLayout.Headers[2])));
  Assert.AreEqual(2, mLayout.ColumnAt(Center(mLayout.Headers[2])), 'Kopf gehört zur Spalte');
  Assert.AreEqual(-1, mLayout.CardAt(Center(mLayout.Headers[2])));
  Assert.AreEqual(-1, mLayout.CardAt(Point(1, 1)));
  Assert.AreEqual(-2, mLayout.ColumnAt(Point(1, 1)), 'Rand gehört zu keiner Spalte');
  Assert.AreEqual(-2, mLayout.HeaderAt(Point(1, 1)));
end;

procedure TAtlasBoardFrameTests.WebColors;
var
  mColor: TColor;
begin
  Assert.IsTrue(TryWebColor('#ff0000', mColor));
  Assert.AreEqual(Integer(clRed), Integer(mColor));
  Assert.IsTrue(TryWebColor(' #0000FF ', mColor));
  Assert.AreEqual(Integer(clBlue), Integer(mColor));
  Assert.IsFalse(TryWebColor('red', mColor));
  Assert.IsFalse(TryWebColor('#12345', mColor));
  Assert.IsFalse(TryWebColor('#gg0000', mColor));
  Assert.AreEqual(Integer(clNone), Integer(mColor));
end;

procedure TAtlasBoardFrameTests.FrameFiltersOnlyMine;
var
  mFrame: TAtlasBoardFrame;
begin
  mFrame := TAtlasBoardFrame.Create(nil);
  try
    Assert.IsTrue(mFrame.OnlyMine, 'Vorgabe „Nur meine“');
    mFrame.SetSnapshot(Snapshot, 'Stand vom 28.10.');
    Assert.IsTrue(mFrame.HasSnapshot);
    Assert.AreEqual('Stand vom 28.10.', mFrame.StatusText);
    Assert.AreEqual(2, Integer(Length(mFrame.VisibleCards)), 'ATL-1 und ATL-3');
    mFrame.SetOnlyMine(False);
    Assert.AreEqual(4, Integer(Length(mFrame.VisibleCards)));
    Assert.IsTrue(mFrame.AllButton.Down);
    mFrame.SearchEdit.Text := 'atl-4';
    Assert.AreEqual(1, Integer(Length(mFrame.VisibleCards)));
    Assert.AreEqual(3, mFrame.VisibleCards[0]);
    mFrame.SetStatus('');
    Assert.AreEqual('', mFrame.StatusText);
  finally
    mFrame.Free;
  end;
end;

procedure TAtlasBoardFrameTests.MoveAndRevert;
var
  mFrame: TAtlasBoardFrame;
  mOld: string;
begin
  mFrame := TAtlasBoardFrame.Create(nil);
  try
    mFrame.SetSnapshot(Snapshot, '');
    mOld := mFrame.MoveCard(0, 1);
    Assert.AreEqual('Open', mOld);
    Assert.AreEqual('In Progress', mFrame.Card(0).State, 'erster Wert der Spalte');
    Assert.AreEqual(1, mFrame.Snapshot.CardColumn(0));
    mFrame.RevertMove('ATL-1', mOld);
    Assert.AreEqual(0, mFrame.Snapshot.CardColumn(0), 'zurückgesprungen');
    Assert.AreEqual('', mFrame.MoveCard(9, 1), 'unbekannte Karte');
    Assert.AreEqual('', mFrame.MoveCard(0, 7), 'unbekannte Spalte');
    mFrame.RevertMove('ATL-99', 'Done');
    Assert.AreEqual('', mFrame.Card(99).Key);
  finally
    mFrame.Free;
  end;
end;

procedure TAtlasBoardFrameTests.ColumnCaptions;
var
  mFrame: TAtlasBoardFrame;
  mSnapshot: TAtlasBoardSnapshot;
begin
  mFrame := TAtlasBoardFrame.Create(nil);
  try
    mFrame.SetSnapshot(Snapshot, '');
    Assert.AreEqual('In Arbeit', mFrame.ColumnCaption(1));
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.BoardNoColumn), mFrame.ColumnCaption(-1));
    mSnapshot := TAtlasBoardSnapshot.Empty;
    mSnapshot.Kind := TAtlasBoardKind.Repository;
    mSnapshot.Columns := [TAtlasBoardColumn.Create('open', TArray<string>.Create('open'), '', False),
      TAtlasBoardColumn.Create('closed', TArray<string>.Create('closed'), '', True)];
    mFrame.SetSnapshot(mSnapshot, '');
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.BoardColumnOpen), mFrame.ColumnCaption(0));
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.BoardColumnClosed), mFrame.ColumnCaption(1));
  finally
    mFrame.Free;
  end;
end;

procedure TAtlasBoardFrameTests.NoticeHidesBoard;
var
  mFrame: TAtlasBoardFrame;
begin
  mFrame := TAtlasBoardFrame.Create(nil);
  try
    mFrame.SetSnapshot(Snapshot, '');
    mFrame.ShowNotice('Kein Tracker');
    Assert.IsFalse(mFrame.HasSnapshot);
    Assert.IsFalse(mFrame.View.Visible);
    Assert.AreEqual('Kein Tracker', mFrame.EmptyLabel.Caption);
    Assert.AreEqual(0, Integer(Length(mFrame.VisibleCards)));
  finally
    mFrame.Free;
  end;
end;

procedure TAtlasBoardFrameTests.MoveDialogTexts;
var
  mDialog: TAtlasBoardMoveDialog;
begin
  mDialog := TAtlasBoardMoveDialog.CreateDialog(nil, 'ATL-123', 'Zur Prüfung');
  try
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.BoardMoveQuestion, ['ATL-123', 'Zur Prüfung']),
      mDialog.QuestionLabel.Caption);
    Assert.IsFalse(mDialog.DontAskCheck.Checked);
    Assert.IsTrue(mDialog.MoveButton.Default);
    Assert.AreEqual('', mDialog.Comment);
    mDialog.CommentMemo.Text := 'Bitte prüfen.' + sLineBreak + sLineBreak;
    Assert.AreEqual('Bitte prüfen.', mDialog.Comment, 'ohne Leerzeilen am Ende');
  finally
    mDialog.Free;
  end;
end;

end.
