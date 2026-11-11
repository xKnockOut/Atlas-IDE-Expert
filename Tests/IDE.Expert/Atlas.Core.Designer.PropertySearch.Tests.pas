unit Atlas.Core.Designer.PropertySearch.Tests;

// Tests für die formularweite Eigenschaftssuche ohne IDE (#524): Bedingungen
// lesen, Treffer über drei Formulare, geerbte Werte aus dem Vorfahrformular
// und die Vorfahrklasse aus dem Quelltext.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasPropertySearchTests = class
  public
    [Test]
    procedure ParsesConditions;
    [Test]
    procedure RejectsBrokenInput;
    [Test]
    procedure FindsTahomaInThreeForms;
    [Test]
    procedure ClassContainsAndSet;
    [Test]
    procedure InheritedValueIsMarked;
    [Test]
    procedure AncestorFromSource;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Designer.FormModel,
  Atlas.Core.Designer.PropertySearch;

const
  cKunden =
    'object frmKunden: TfrmKunden'#13#10 +
    '  Caption = ''Kunden'''#13#10 +
    '  Font.Name = ''Tahoma'''#13#10 +
    '  object lblName: TLabel'#13#10 +
    '    Caption = ''Kundenname'''#13#10 +
    '    Font.Name = ''Tahoma'''#13#10 +
    '  end'#13#10 +
    '  object grdKunden: TDBGrid'#13#10 +
    '    Visible = False'#13#10 +
    '  end'#13#10 +
    'end';
  cAuftrag =
    'object frmAuftrag: TfrmAuftrag'#13#10 +
    '  object edtNr: TEdit'#13#10 +
    '    Font.Name = ''tahoma'''#13#10 +
    '    Hint = ''Auftrags'' + ''nummer'''#13#10 +
    '  end'#13#10 +
    'end';
  cLager =
    'object frmLager: TfrmLager'#13#10 +
    '  object btnOk: TButton'#13#10 +
    '    Font.Name = ''Segoe UI'''#13#10 +
    '  end'#13#10 +
    '  object pnlTahoma: TPanel'#13#10 +
    '    Font.Name = ''Tahoma'''#13#10 +
    '  end'#13#10 +
    'end';
  cBasis =
    'object frmBasis: TfrmBasis'#13#10 +
    '  Font.Name = ''Tahoma'''#13#10 +
    '  object btnHilfe: TButton'#13#10 +
    '    Font.Name = ''Tahoma'''#13#10 +
    '  end'#13#10 +
    '  object btnOk: TButton'#13#10 +
    '    Font.Name = ''Tahoma'''#13#10 +
    '  end'#13#10 +
    'end';
  cKind =
    'inherited frmKind: TfrmKind'#13#10 +
    '  inherited btnOk: TButton'#13#10 +
    '    Font.Name = ''Arial'''#13#10 +
    '  end'#13#10 +
    '  object edtNeu: TEdit'#13#10 +
    '    Font.Name = ''Tahoma'''#13#10 +
    '  end'#13#10 +
    'end';

function Chain(const ATexts: array of string): TArray<TArray<TAtlasFormObject>>;
var
  mText: string;
begin
  Result := nil;
  for mText in ATexts do
  begin
    Result := Result + [TAtlasFormModel.Parse(mText)];
  end;
end;

function Find(const AQuery: string; const ATexts: array of string): TArray<TAtlasPropertyHit>;
begin
  Result := TAtlasPropertySearch.Search(TAtlasPropertyQuery.Parse(AQuery), Chain(ATexts));
end;

procedure TAtlasPropertySearchTests.ParsesConditions;
var
  mQuery: TAtlasPropertyQuery;
begin
  mQuery := TAtlasPropertyQuery.Parse('Font.Name = ''Tahoma'' und Visible <> True and Caption enthält ''und''');
  Assert.IsTrue(mQuery.Valid);
  Assert.AreEqual(3, Integer(Length(mQuery.Conditions)), '„und“ im String teilt nicht');
  Assert.AreEqual('Font.Name', mQuery.Conditions[0].Path);
  Assert.AreEqual('Tahoma', mQuery.Conditions[0].Value, 'ohne Hochkommas');
  Assert.IsTrue(mQuery.Conditions[1].Op = TAtlasPropertyOp.NotEquals);
  Assert.IsTrue(mQuery.Conditions[2].Op = TAtlasPropertyOp.Contains);
  Assert.AreEqual('und', mQuery.Conditions[2].Value);
  mQuery := TAtlasPropertyQuery.Parse('Klasse = TDBGrid und Hint nicht gesetzt und Tag gesetzt');
  Assert.AreEqual('', mQuery.Conditions[0].Path, 'Klasse');
  Assert.IsTrue(mQuery.Conditions[1].Op = TAtlasPropertyOp.NotSet);
  Assert.IsTrue(mQuery.Conditions[2].Op = TAtlasPropertyOp.IsSet);
  mQuery := TAtlasPropertyQuery.Parse('Class = TEdit and Hint is set and Caption contains ''x''');
  Assert.IsTrue(mQuery.Valid, 'englisch');
  Assert.IsTrue(mQuery.Conditions[1].Op = TAtlasPropertyOp.IsSet);
end;

procedure TAtlasPropertySearchTests.RejectsBrokenInput;
begin
  Assert.IsFalse(TAtlasPropertyQuery.Parse('').Valid);
  Assert.AreEqual('Font Name = ''x''', TAtlasPropertyQuery.Parse('Font Name = ''x''').Invalid, 'kein Pfad');
  Assert.AreEqual('Caption =', TAtlasPropertyQuery.Parse('Visible = False und Caption =').Invalid, 'ohne Wert');
  Assert.IsFalse(TAtlasPropertyQuery.Parse('Visible False').Valid);
end;

procedure TAtlasPropertySearchTests.FindsTahomaInThreeForms;
var
  mHits: TArray<TAtlasPropertyHit>;
  mCount: Integer;
  mText: string;
begin
  mCount := 0;
  for mText in TArray<string>.Create(cKunden, cAuftrag, cLager) do
  begin
    mHits := Find('Font.Name = ''Tahoma''', [mText]);
    Inc(mCount, Length(mHits));
  end;
  Assert.AreEqual(4, mCount, 'Formular und Label, Edit (klein geschrieben), Panel; nicht der Button');
  mHits := Find('Font.Name = ''Tahoma''', [cKunden]);
  Assert.AreEqual('frmKunden', mHits[0].Component);
  Assert.AreEqual('TfrmKunden', mHits[0].TypeName);
  Assert.AreEqual('Font.Name = ''Tahoma''', mHits[0].Found);
  Assert.IsFalse(mHits[0].FromAncestor);
end;

procedure TAtlasPropertySearchTests.ClassContainsAndSet;
var
  mHits: TArray<TAtlasPropertyHit>;
begin
  mHits := Find('Klasse = TDBGrid und Visible = False', [cKunden]);
  Assert.AreEqual(1, Integer(Length(mHits)));
  Assert.AreEqual('grdKunden', mHits[0].Component);
  Assert.AreEqual('Visible = False', mHits[0].Found, 'Klasse zählt nicht als Wert');
  mHits := Find('Caption enthält ''kunde''', [cKunden]);
  Assert.AreEqual(2, Integer(Length(mHits)), 'Formular und Label');
  mHits := Find('Hint enthält ''nummer''', [cAuftrag]);
  Assert.AreEqual('edtNr', mHits[0].Component, 'verketteter String');
  mHits := Find('Klasse = TButton und Font.Name nicht gesetzt', [cLager]);
  Assert.AreEqual(0, Integer(Length(mHits)));
  mHits := Find('Font.Name <> ''Tahoma''', [cLager]);
  Assert.AreEqual('btnOk', mHits[0].Component, 'gesetzt und anders');
end;

procedure TAtlasPropertySearchTests.InheritedValueIsMarked;
var
  mHits: TArray<TAtlasPropertyHit>;
  mHit: TAtlasPropertyHit;
  mNames: string;
begin
  mHits := Find('Font.Name = ''Tahoma''', [cKind, cBasis]);
  mNames := '';
  for mHit in mHits do
  begin
    mNames := mNames + mHit.Component + ':' + BoolToStr(mHit.FromAncestor, True) + ' ';
  end;
  Assert.AreEqual('frmKind:True btnHilfe:True edtNeu:False ', mNames,
    'btnOk ist im Kind überschrieben; Formular und btnHilfe erben');
  mHits := Find('Font.Name = ''Arial''', [cKind, cBasis]);
  Assert.AreEqual('btnOk', mHits[0].Component);
  Assert.IsFalse(mHits[0].FromAncestor, 'im Kind gesetzt');
end;

procedure TAtlasPropertySearchTests.AncestorFromSource;
const
  cUnit =
    'type'#13#10 +
    '  TfrmKindHilfe = class(TForm)'#13#10 +
    '  end;'#13#10 +
    '  TfrmKind = class (Basis.TfrmBasis)'#13#10 +
    '    btnOk: TButton;'#13#10 +
    '  end;';
begin
  Assert.AreEqual('Basis.TfrmBasis', TAtlasPropertySearch.AncestorOf(cUnit, 'TfrmKind'));
  Assert.AreEqual('TForm', TAtlasPropertySearch.AncestorOf(cUnit, 'tfrmkindhilfe'));
  Assert.AreEqual('', TAtlasPropertySearch.AncestorOf(cUnit, 'TfrmFehlt'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPropertySearchTests);

end.
