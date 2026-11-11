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
  end;

implementation

uses
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

initialization
  TDUnitX.RegisterTestFixture(TAtlasInlineCaptionTests);

end.
