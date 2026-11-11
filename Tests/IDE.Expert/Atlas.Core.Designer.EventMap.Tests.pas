unit Atlas.Core.Designer.EventMap.Tests;

// Tests für die Ereignis-Karte (#612) auf Fixture-DFM und -Unit: Zuweisungen
// mit Zeilen, gemeinsamer Handler, leerer Handler, Handler ohne Zuweisung,
// Zuweisung ohne Methode, Gruppierung, Filter und Entfernen eines Handlers.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Designer.EventMap;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasEventMapTests = class
  private
    FRows: TArray<TAtlasEventRow>;
    function Row(const AComponent, AEvent: string): TAtlasEventRow;
  public
    [Setup]
    procedure Setup;
    [Test]
    procedure Assignments;
    [Test]
    procedure Findings;
    [Test]
    procedure GroupByHandler;
    [Test]
    procedure FilterRows;
    [Test]
    procedure RemoveEmptyHandler;
    [Test]
    procedure SkeletonIgnoresComments;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Designer.FormModel;

const
  cDfm =
    'object frmKunden: TfrmKunden' + #13#10 +
    '  Caption = ''Kunden''' + #13#10 +
    '  OnDestroy = FormDestroy' + #13#10 +
    '  object btnOk: TButton' + #13#10 +
    '    Action = actOk' + #13#10 +
    '    OnClick = btnOkClick' + #13#10 +
    '  end' + #13#10 +
    '  object edtName: TEdit' + #13#10 +
    '    OnChange = edtNameChange' + #13#10 +
    '    OnExit = edtNameExit' + #13#10 +
    '  end' + #13#10 +
    '  object alHaupt: TActionList' + #13#10 +
    '    object actOk: TAction' + #13#10 +
    '      Caption = ''OK''' + #13#10 +
    '      OnExecute = btnOkClick' + #13#10 +
    '    end' + #13#10 +
    '  end' + #13#10 +
    'end' + #13#10;

  cUnit =
    'unit uKunden;' + #13#10 +
    '' + #13#10 +
    'interface' + #13#10 +
    '' + #13#10 +
    'type' + #13#10 +
    '  TfrmKunden = class(TForm)' + #13#10 +
    '    btnOk: TButton;' + #13#10 +
    '    edtName: TEdit;' + #13#10 +
    '    procedure FormDestroy(Sender: TObject);' + #13#10 +
    '    procedure btnOkClick(Sender: TObject);' + #13#10 +
    '    procedure edtNameChange(Sender: TObject);' + #13#10 +
    '    procedure edtPlzExit(Sender: TObject);' + #13#10 +
    '  private' + #13#10 +
    '    procedure Pruefen(Sender: TObject);' + #13#10 +
    '  end;' + #13#10 +
    '' + #13#10 +
    'implementation' + #13#10 +
    '' + #13#10 +
    '{$R *.dfm}' + #13#10 +
    '' + #13#10 +
    'procedure TfrmKunden.FormDestroy(Sender: TObject);' + #13#10 +
    'begin' + #13#10 +
    '  // später' + #13#10 +
    'end;' + #13#10 +
    '' + #13#10 +
    'procedure TfrmKunden.btnOkClick(Sender: TObject);' + #13#10 +
    'begin' + #13#10 +
    '  Pruefen(Sender);' + #13#10 +
    '  Close;' + #13#10 +
    'end;' + #13#10 +
    '' + #13#10 +
    'procedure TfrmKunden.edtNameChange(Sender: TObject);' + #13#10 +
    'begin' + #13#10 +
    '  btnOk.Enabled := edtName.Text <> '''';' + #13#10 +
    'end;' + #13#10 +
    '' + #13#10 +
    'procedure TfrmKunden.edtPlzExit(Sender: TObject);' + #13#10 +
    'begin' + #13#10 +
    '  Pruefen(Sender);' + #13#10 +
    'end;' + #13#10 +
    '' + #13#10 +
    'procedure TfrmKunden.Pruefen(Sender: TObject);' + #13#10 +
    'begin' + #13#10 +
    'end;' + #13#10 +
    '' + #13#10 +
    'end.' + #13#10;

{ TAtlasEventMapTests }

procedure TAtlasEventMapTests.Setup;
begin
  FRows := TAtlasEventMap.Rows(TAtlasFormModel.Parse(cDfm), TAtlasEventMap.Handlers(cUnit, 'TfrmKunden'));
end;

function TAtlasEventMapTests.Row(const AComponent, AEvent: string): TAtlasEventRow;
var
  mRow: TAtlasEventRow;
begin
  for mRow in FRows do
  begin
    if SameText(mRow.Component, AComponent) and SameText(mRow.Event, AEvent) then
    begin
      Exit(mRow);
    end;
  end;
  Assert.Fail(AComponent + '.' + AEvent + ' fehlt');
  Result := Default(TAtlasEventRow);
end;

procedure TAtlasEventMapTests.Assignments;
begin
  // Fünf Zuweisungen und ein Handler ohne Zuweisung; Pruefen ist privat und fehlt.
  Assert.AreEqual(6, Length(FRows));
  Assert.AreEqual('TButton', Row('btnOk', 'OnClick').ClassName);
  Assert.AreEqual('btnOkClick', Row('btnOk', 'OnClick').Handler);
  Assert.AreEqual(25, Row('btnOk', 'OnClick').Line);
  Assert.AreEqual(5, Row('btnOk', 'OnClick').Lines);
  Assert.AreEqual(4, Row('frmKunden', 'OnDestroy').Lines);
  Assert.AreEqual(2, Row('actOk', 'OnExecute').UseCount);
  Assert.AreEqual(1, Row('edtName', 'OnChange').UseCount);
end;

procedure TAtlasEventMapTests.Findings;
begin
  Assert.AreEqual(Ord(TAtlasEventFinding.Empty), Ord(Row('frmKunden', 'OnDestroy').Finding));
  Assert.AreEqual(Ord(TAtlasEventFinding.None), Ord(Row('btnOk', 'OnClick').Finding));
  Assert.AreEqual(Ord(TAtlasEventFinding.Missing), Ord(Row('edtName', 'OnExit').Finding));
  Assert.AreEqual(-1, Row('edtName', 'OnExit').Line);
  Assert.AreEqual('edtPlzExit', Row('', '').Handler);
  Assert.AreEqual(Ord(TAtlasEventFinding.Unassigned), Ord(Row('', '').Finding));
  Assert.AreEqual(0, Row('', '').UseCount);
end;

procedure TAtlasEventMapTests.GroupByHandler;
var
  mSorted: TArray<TAtlasEventRow>;
  mIndex: Integer;
begin
  mSorted := TAtlasEventMap.Sorted(FRows, TAtlasEventGroup.Handler);
  // btnOkClick vorn, beide Zuweisungen nebeneinander, in der Reihenfolge des Formulars.
  Assert.AreEqual('btnOk', mSorted[0].Component);
  Assert.AreEqual('actOk', mSorted[1].Component);
  for mIndex := 1 to High(mSorted) do
  begin
    Assert.IsTrue(CompareText(mSorted[mIndex - 1].Handler, mSorted[mIndex].Handler) <= 0);
  end;
  mSorted := TAtlasEventMap.Sorted(FRows, TAtlasEventGroup.Event);
  Assert.AreEqual('', mSorted[0].Event);
  Assert.AreEqual('OnChange', mSorted[1].Event);
  Assert.AreEqual('frmKunden', TAtlasEventMap.GroupKey(Row('frmKunden', 'OnDestroy'), TAtlasEventGroup.Component));
end;

procedure TAtlasEventMapTests.FilterRows;
var
  mEvents: TArray<string>;
begin
  Assert.AreEqual(1, Length(TAtlasEventMap.Filter(FRows, '', 'OnClick', False)));
  Assert.AreEqual(2, Length(TAtlasEventMap.Filter(FRows, 'edtName', '', False)));
  Assert.AreEqual(3, Length(TAtlasEventMap.Filter(FRows, '', '', True)));
  Assert.AreEqual(1, Length(TAtlasEventMap.Filter(FRows, 'edt', 'OnExit', True)));
  mEvents := TAtlasEventMap.Events(FRows);
  Assert.AreEqual(5, Length(mEvents));
  Assert.AreEqual('OnChange', mEvents[0]);
  Assert.AreEqual('OnExit', mEvents[4]);
end;

procedure TAtlasEventMapTests.RemoveEmptyHandler;
var
  mText: string;
begin
  mText := TAtlasEventMap.RemoveHandler(cUnit, 'TfrmKunden', 'FormDestroy');
  Assert.IsFalse(mText.Contains('FormDestroy'));
  Assert.IsTrue(mText.Contains('    edtName: TEdit;' + #13#10 + '    procedure btnOkClick(Sender: TObject);'));
  Assert.IsTrue(mText.Contains('{$R *.dfm}' + #13#10 + #13#10 + 'procedure TfrmKunden.btnOkClick'));
  Assert.AreEqual(cUnit, TAtlasEventMap.RemoveHandler(cUnit, 'TfrmKunden', 'GibtEsNicht'));
end;

procedure TAtlasEventMapTests.SkeletonIgnoresComments;
begin
  Assert.AreEqual('beginend;', TAtlasEventMap.Skeleton('begin' + #10 + '  { a }' + #10 + '  (* b *) // c' + #10 +
    'end;'));
  Assert.AreEqual('beginx:=1;end;', TAtlasEventMap.Skeleton('begin x := 1; end;'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEventMapTests);

end.
