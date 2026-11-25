unit Atlas.UI.Tracker.BoardFrame.Tests;

// Tests des Fensters „Atlas-Board“ (#1272) ohne IDE: Farben aus "#rrggbb",
// Filter „Nur meine“ im Frame, sofortiges Verschieben mit Rücksprung,
// Beschriftung der Spalten und der Dialog „Verschieben“. Die Anordnung prüft
// Atlas.Core.Tracker.BoardLayout.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasBoardFrameTests = class
  private
    FSaved: Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
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
  Vcl.Graphics,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.BoardLayout.TestSupport,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.Board.Strings,
  Atlas.UI.Tracker.BoardFrame,
  Atlas.UI.Tracker.BoardPainter,
  Atlas.UI.Tracker.MoveDialog;

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
    mFrame.SetSnapshot(SampleBoard, 'Stand vom 28.10.');
    Assert.IsTrue(mFrame.HasSnapshot);
    Assert.AreEqual('Stand vom 28.10.', mFrame.StatusText);
    Assert.AreEqual(2, Integer(Length(mFrame.VisibleCards)), 'ATL-1 und ATL-3');
    mFrame.SetOnlyMine(False);
    Assert.AreEqual(4, Integer(Length(mFrame.VisibleCards)));
    Assert.IsTrue(mFrame.Parts.All.Down);
    mFrame.Parts.Search.Text := 'atl-4';
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
    mFrame.SetSnapshot(SampleBoard, '');
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
    mFrame.SetSnapshot(SampleBoard, '');
    Assert.AreEqual('In Arbeit', mFrame.ColumnCaption(1));
    Assert.AreEqual(TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardNoColumn), mFrame.ColumnCaption(-1));
    mSnapshot := TAtlasBoardSnapshot.Empty;
    mSnapshot.Kind := TAtlasBoardKind.Repository;
    mSnapshot.Columns := [TAtlasBoardColumn.Create('open', TArray<string>.Create('open'), '', False),
      TAtlasBoardColumn.Create('closed', TArray<string>.Create('closed'), '', True)];
    mFrame.SetSnapshot(mSnapshot, '');
    Assert.AreEqual(TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardColumnOpen), mFrame.ColumnCaption(0));
    Assert.AreEqual(TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardColumnClosed), mFrame.ColumnCaption(1));
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
    mFrame.SetSnapshot(SampleBoard, '');
    mFrame.ShowNotice('Kein Tracker');
    Assert.IsFalse(mFrame.HasSnapshot);
    Assert.IsFalse(mFrame.View.Visible);
    Assert.AreEqual('Kein Tracker', mFrame.Parts.Empty.Caption);
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
    Assert.AreEqual(TAtlasBoardStrings.Fmt(TAtlasBoardTextId.BoardMoveQuestion, ['ATL-123', 'Zur Prüfung']),
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
