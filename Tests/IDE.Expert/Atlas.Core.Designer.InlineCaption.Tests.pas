unit Atlas.Core.Designer.InlineCaption.Tests;

// Tests für die Beschriftung direkt im Designer (#748): Zuordnung Klasse →
// Eigenschaft, Tab-Reihenfolge mit FocusControl, Spalte unter dem Mauszeiger,
// mehrzeilige Captions und doppelte Tastenkürzel.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasInlineCaptionTests = class
  public
    [Test]
    procedure PropertyByClass;
    [Test]
    procedure OwnMapping;
    [Test]
    procedure TextHintToggle;
    [Test]
    procedure TabOrderWithFocusControl;
    [Test]
    procedure LabelsWithoutFocusControl;
    [Test]
    procedure NextWraps;
    [Test]
    procedure GridColumn;
    [Test]
    procedure MultiLine;
    [Test]
    procedure DuplicateAccelerators;
    [Test]
    procedure ColumnPathDetected;
    [Test]
    procedure ColumnLeftSumsWidths;
    [Test]
    procedure EditorBandByHolder;
    [Test]
    procedure FittedGrowsAwayFromAnchor;
    [Test]
    procedure WithinDragDistance;
    [Test]
    procedure HistoryPerFormFile;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Designer.InlineCaption;

function Joined(const ANames: TArray<string>): string;
var
  mName: string;
begin
  Result := '';
  for mName in ANames do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mName;
  end;
end;

{ TAtlasInlineCaptionTests }

procedure TAtlasInlineCaptionTests.PropertyByClass;
begin
  Assert.AreEqual('Caption', TAtlasInlineCaption.PropertyFor(['TLabel', 'TCustomLabel', 'TGraphicControl'], True, ''));
  Assert.AreEqual('Caption', TAtlasInlineCaption.PropertyFor(['TButton', 'TButtonControl'], True, ''));
  Assert.AreEqual('Text', TAtlasInlineCaption.PropertyFor(['TEdit', 'TCustomEdit', 'TWinControl'], False, ''));
  Assert.AreEqual('EditLabel.Caption', TAtlasInlineCaption.PropertyFor(['TLabeledEdit', 'TCustomLabeledEdit',
    'TCustomEdit'], False, ''), 'spezieller vor allgemeiner');
  Assert.AreEqual('', TAtlasInlineCaption.PropertyFor(['TMemo', 'TCustomMemo', 'TCustomEdit'], False, ''), 'Memo nicht');
  Assert.AreEqual('', TAtlasInlineCaption.PropertyFor(['TTimer', 'TComponent'], False, ''), 'ohne Text');
  Assert.AreEqual(TAtlasInlineCaption.cColumnTitle, TAtlasInlineCaption.PropertyFor(['TDBGrid', 'TCustomDBGrid'],
    False, ''));
  Assert.AreEqual('Columns[2].Title.Caption', TAtlasInlineCaption.ColumnPath(2));
end;

procedure TAtlasInlineCaptionTests.OwnMapping;
begin
  Assert.AreEqual('Title', TAtlasInlineCaption.PropertyFor(['TMyHeader', 'TCustomPanel'], True, 'TMyHeader=Title'));
  Assert.AreEqual('', TAtlasInlineCaption.PropertyFor(['TMyButton', 'TButton'], True, 'TButton = -; TFoo=Bar'),
    'abschaltbar');
  Assert.AreEqual('Lines', TAtlasInlineCaption.PropertyFor(['TMemo', 'TCustomMemo'], False, 'TMemo=Lines'),
    'eigene Zuordnung vor der eingebauten');
end;

procedure TAtlasInlineCaptionTests.TextHintToggle;
begin
  Assert.AreEqual('TextHint', TAtlasInlineCaption.Toggled('Text'));
  Assert.AreEqual('Text', TAtlasInlineCaption.Toggled('TextHint'));
  Assert.AreEqual('Caption', TAtlasInlineCaption.Toggled('Caption'));
end;

procedure TAtlasInlineCaptionTests.TabOrderWithFocusControl;
var
  mOrder: TArray<string>;
begin
  // lblName „Name:“ gehört zu edtName (TabOrder 1), lblOrt zu edtOrt (0); grp ist ein Container mit TabOrder 2.
  mOrder := TAtlasInlineCaption.Order([
    TAtlasCaptionStop.Create('lblName', 'Form', nil, 'edtName', 10, 10),
    TAtlasCaptionStop.Create('edtName', 'Form', [1], '', 10, 80),
    TAtlasCaptionStop.Create('lblOrt', 'Form', nil, 'edtOrt', 40, 10),
    TAtlasCaptionStop.Create('edtOrt', 'Form', [0], '', 40, 80),
    TAtlasCaptionStop.Create('chkInGrp', 'grp', [2, 0], '', 5, 5),
    TAtlasCaptionStop.Create('grp', 'Form', [2], '', 80, 10)]);
  Assert.AreEqual('lblOrt,edtOrt,lblName,edtName,grp,chkInGrp', Joined(mOrder));
end;

procedure TAtlasInlineCaptionTests.LabelsWithoutFocusControl;
var
  mOrder: TArray<string>;
begin
  mOrder := TAtlasInlineCaption.Order([
    TAtlasCaptionStop.Create('btnOk', 'Form', [0], '', 100, 10),
    TAtlasCaptionStop.Create('lblHinweis', 'Form', nil, '', 50, 10),
    TAtlasCaptionStop.Create('lblFuss', 'Form', nil, '', 200, 10),
    TAtlasCaptionStop.Create('lblInPanel', 'pnl', nil, '', 5, 5),
    TAtlasCaptionStop.Create('pnl', 'Form', [1], '', 150, 10)]);
  Assert.AreEqual('lblHinweis,btnOk,pnl,lblInPanel,lblFuss', Joined(mOrder));
end;

procedure TAtlasInlineCaptionTests.NextWraps;
begin
  Assert.AreEqual('b', TAtlasInlineCaption.Next(['a', 'b', 'c'], 'a', False));
  Assert.AreEqual('a', TAtlasInlineCaption.Next(['a', 'b', 'c'], 'c', False), 'am Ende wieder vorn');
  Assert.AreEqual('c', TAtlasInlineCaption.Next(['a', 'b', 'c'], 'a', True), 'Umschalt+Tab');
  Assert.AreEqual('', TAtlasInlineCaption.Next(['a'], 'a', False));
  Assert.AreEqual('', TAtlasInlineCaption.Next(['a', 'b'], 'x', False));
end;

procedure TAtlasInlineCaptionTests.GridColumn;
begin
  Assert.AreEqual(-1, TAtlasInlineCaption.ColumnAt(5, [64, 100], 11, 1), 'Indikator');
  Assert.AreEqual(0, TAtlasInlineCaption.ColumnAt(11, [64, 100], 11, 1));
  Assert.AreEqual(1, TAtlasInlineCaption.ColumnAt(76, [64, 100], 11, 1));
  Assert.AreEqual(-1, TAtlasInlineCaption.ColumnAt(300, [64, 100], 11, 1));
end;

procedure TAtlasInlineCaptionTests.MultiLine;
begin
  Assert.IsTrue(TAtlasInlineCaption.CanBreak(True, 'Text'));
  Assert.IsTrue(TAtlasInlineCaption.CanBreak(False, 'Zeile 1' + #13#10 + 'Zeile 2'));
  Assert.IsFalse(TAtlasInlineCaption.CanBreak(False, 'Eine Zeile'));
  Assert.AreEqual(120, TAtlasInlineCaption.EditorWidth(120, 50, 16), 'mindestens so breit wie die Komponente');
  Assert.AreEqual(216, TAtlasInlineCaption.EditorWidth(120, 200, 16), 'wächst mit dem Text');
end;

procedure TAtlasInlineCaptionTests.DuplicateAccelerators;
var
  mDuplicates: TArray<Integer>;
begin
  mDuplicates := TAtlasInlineCaption.Duplicates(['&Name:', '&Nummer', 'O&rt', 'Speichern && &nächster'], 0);
  Assert.AreEqual(2, Integer(Length(mDuplicates)));
  Assert.AreEqual(1, mDuplicates[0]);
  Assert.AreEqual(3, mDuplicates[1], '&& ist kein Kürzel');
  Assert.AreEqual(0, Integer(Length(TAtlasInlineCaption.Duplicates(['O&rt', '&Name'], 0))));
  Assert.AreEqual(0, Integer(Length(TAtlasInlineCaption.Duplicates(['Ohne'], 0))));
end;

procedure TAtlasInlineCaptionTests.ColumnPathDetected;
begin
  Assert.IsTrue(TAtlasCaptionLayout.IsColumn(TAtlasInlineCaption.ColumnPath(2)));
  Assert.IsFalse(TAtlasCaptionLayout.IsColumn('Caption'));
  Assert.IsFalse(TAtlasCaptionLayout.IsColumn('EditLabel.Caption'));
end;

procedure TAtlasInlineCaptionTests.ColumnLeftSumsWidths;
begin
  Assert.AreEqual(11, TAtlasCaptionLayout.ColumnLeft(TArray<Integer>.Create(50, 60, 70), 11, 1, 0));
  Assert.AreEqual(11 + 51 + 61, TAtlasCaptionLayout.ColumnLeft(TArray<Integer>.Create(50, 60, 70), 11, 1, 2));
end;

procedure TAtlasInlineCaptionTests.EditorBandByHolder;
var
  mRect: TRect;
begin
  mRect := TAtlasCaptionLayout.EditorBand(Rect(100, 100, 300, 200), TAtlasCaptionHolder.GroupBox, 20, 8);
  Assert.AreEqual(108, mRect.Left);
  Assert.AreEqual(292, mRect.Right);
  Assert.AreEqual(120, mRect.Bottom);
  mRect := TAtlasCaptionLayout.EditorBand(Rect(100, 100, 300, 200), TAtlasCaptionHolder.TabSheet, 20, 8);
  Assert.AreEqual(80, mRect.Top);
  Assert.AreEqual(100, mRect.Bottom);
  mRect := TAtlasCaptionLayout.EditorBand(Rect(100, 100, 300, 200), TAtlasCaptionHolder.Other, 20, 8);
  Assert.AreEqual(140, mRect.Top);
  Assert.AreEqual(160, mRect.Bottom);
  mRect := TAtlasCaptionLayout.EditorBand(Rect(100, 100, 300, 200), TAtlasCaptionHolder.TextControl, 20, 8);
  Assert.AreEqual(100, mRect.Top);
  Assert.AreEqual(200, mRect.Bottom);
  // Niedriger als eine Zeile: bleibt.
  mRect := TAtlasCaptionLayout.EditorBand(Rect(100, 100, 300, 110), TAtlasCaptionHolder.Other, 20, 8);
  Assert.AreEqual(110, mRect.Bottom);
end;

procedure TAtlasInlineCaptionTests.FittedGrowsAwayFromAnchor;
var
  mRect: TRect;
begin
  mRect := TAtlasCaptionLayout.Fitted(Rect(100, 10, 175, 35), 120, False);
  Assert.AreEqual(100, mRect.Left);
  Assert.AreEqual(220, mRect.Right);
  mRect := TAtlasCaptionLayout.Fitted(Rect(100, 10, 175, 35), 120, True);
  Assert.AreEqual(55, mRect.Left);
  Assert.AreEqual(175, mRect.Right);
  Assert.AreEqual(35, mRect.Bottom);
end;

procedure TAtlasInlineCaptionTests.WithinDragDistance;
begin
  Assert.IsTrue(TAtlasCaptionLayout.WithinDrag(Point(10, 10), Point(14, 6), 4, 4));
  Assert.IsFalse(TAtlasCaptionLayout.WithinDrag(Point(10, 10), Point(15, 10), 4, 4));
  Assert.IsFalse(TAtlasCaptionLayout.WithinDrag(Point(10, 10), Point(10, 15), 4, 4));
end;

procedure TAtlasInlineCaptionTests.HistoryPerFormFile;
var
  mHistory: TAtlasCaptionHistory;
  mChange: TAtlasCaptionChange;
begin
  mHistory := Default(TAtlasCaptionHistory);
  mChange := Default(TAtlasCaptionChange);
  mChange.FormFile := 'Unit1.dfm';
  mChange.Component := 'Button1';
  mChange.OldText := 'OK';
  mHistory.Push(mChange);
  mChange.FormFile := 'Unit2.dfm';
  mChange.Component := 'Label1';
  mHistory.Push(mChange);
  Assert.IsFalse(mHistory.CanUndo('Unit1.dfm'));
  Assert.IsTrue(mHistory.CanUndo('UNIT2.DFM'));
  Assert.IsTrue(mHistory.Pop(mChange));
  Assert.AreEqual('Label1', mChange.Component);
  Assert.IsTrue(mHistory.CanUndo('Unit1.dfm'));
  Assert.IsTrue(mHistory.Pop(mChange));
  Assert.IsFalse(mHistory.Pop(mChange));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasInlineCaptionTests);

end.
