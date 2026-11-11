unit Atlas.Core.Designer.FormUnit.Tests;

// Tests für die Zeilensicht auf eine Formular-Unit: Klasse, Methodenrumpf,
// Name eines Felds oder einer Methode, Kopf einer Methode und Einrückung.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Designer.FormUnit;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasFormUnitTests = class
  public
    [Test]
    procedure LinesAndText;
    [Test]
    procedure FindsClass;
    [Test]
    procedure FindsBodyWithoutTrailingBlanks;
    [Test]
    procedure MissingBody;
    [Test]
    procedure MemberNames;
    [Test]
    procedure MethodHeaders;
  end;

implementation

const
  cUnit =
    'unit uKunden;' + #13#10 +
    '' + #13#10 +
    'interface' + #13#10 +
    '' + #13#10 +
    'type' + #13#10 +
    '  TfrmKunden = class(TForm)' + #13#10 +
    '    edtName: TEdit;' + #13#10 +
    '    procedure edtNameChange(Sender: TObject);' + #13#10 +
    '    procedure FormShow(Sender: TObject);' + #13#10 +
    '  end;' + #13#10 +
    '' + #13#10 +
    'implementation' + #13#10 +
    '' + #13#10 +
    'procedure TfrmKunden.edtNameChange(Sender: TObject);' + #13#10 +
    'begin' + #13#10 +
    '  Caption := edtName.Text;' + #13#10 +
    'end;' + #13#10 +
    '' + #13#10 +
    '' + #13#10 +
    'procedure TfrmKunden.FormShow(Sender: TObject);' + #13#10 +
    'begin' + #13#10 +
    'end;' + #13#10 +
    '' + #13#10 +
    'end.';

{ TAtlasFormUnitTests }

procedure TAtlasFormUnitTests.LinesAndText;
var
  mUnit: TAtlasFormUnit;
begin
  mUnit := TAtlasFormUnit.Create('a' + #10 + 'b' + #13#10 + 'c');
  Assert.AreEqual(3, Integer(Length(mUnit.Lines)));
  Assert.AreEqual('a' + #13#10 + 'b' + #13#10 + 'c', mUnit.Text);
  Assert.AreEqual(3, mUnit.ImplementationLine, 'ohne implementation: Zeilenzahl');
  Assert.AreEqual(11, TAtlasFormUnit.Create(cUnit).ImplementationLine);
end;

procedure TAtlasFormUnitTests.FindsClass;
var
  mFirst, mLast: Integer;
begin
  Assert.IsTrue(TAtlasFormUnit.Create(cUnit).FindClass('TfrmKunden', mFirst, mLast));
  Assert.AreEqual(5, mFirst);
  Assert.AreEqual(9, mLast);
  Assert.IsFalse(TAtlasFormUnit.Create(cUnit).FindClass('TfrmAuftraege', mFirst, mLast));
end;

procedure TAtlasFormUnitTests.FindsBodyWithoutTrailingBlanks;
var
  mFirst, mLast: Integer;
begin
  Assert.IsTrue(TAtlasFormUnit.Create(cUnit).FindBody('TfrmKunden', 'edtNameChange', mFirst, mLast));
  Assert.AreEqual(13, mFirst);
  Assert.AreEqual(16, mLast, 'Leerzeilen danach gehören nicht dazu');
  Assert.IsTrue(TAtlasFormUnit.Create(cUnit).FindBody('TfrmKunden', 'FormShow', mFirst, mLast));
  Assert.AreEqual(19, mFirst);
  Assert.AreEqual(21, mLast, 'endet vor „end.“');
end;

procedure TAtlasFormUnitTests.MissingBody;
var
  mFirst, mLast: Integer;
begin
  Assert.IsFalse(TAtlasFormUnit.Create(cUnit).FindBody('TfrmKunden', 'FormClose', mFirst, mLast));
  Assert.IsFalse(TAtlasFormUnit.Create(cUnit).FindBody('TfrmKunden', 'edtName', mFirst, mLast),
    'Präfix eines anderen Namens zählt nicht');
end;

procedure TAtlasFormUnitTests.MemberNames;
var
  mIsMethod: Boolean;
begin
  Assert.AreEqual('edtName', TAtlasFormUnit.MemberName('    edtName: TEdit;', mIsMethod));
  Assert.IsFalse(mIsMethod);
  Assert.AreEqual('edtNameChange', TAtlasFormUnit.MemberName('    procedure edtNameChange(Sender: TObject);', mIsMethod));
  Assert.IsTrue(mIsMethod);
  Assert.AreEqual('Refresh', TAtlasFormUnit.MemberName('    procedure Refresh;', mIsMethod));
  Assert.AreEqual('', TAtlasFormUnit.MemberName('  private', mIsMethod));
end;

procedure TAtlasFormUnitTests.MethodHeaders;
begin
  Assert.IsTrue(TAtlasFormUnit.IsMethodHeader('procedure TfrmKunden.FormShow(Sender: TObject);'));
  Assert.IsTrue(TAtlasFormUnit.IsMethodHeader('{ TfrmKunden }'));
  Assert.IsTrue(TAtlasFormUnit.IsMethodHeader('end.'));
  Assert.IsFalse(TAtlasFormUnit.IsMethodHeader('    procedure FormShow(Sender: TObject);'), 'eingerückt');
  Assert.IsFalse(TAtlasFormUnit.IsMethodHeader('begin'));
  Assert.AreEqual(4, TAtlasFormUnit.SpacesOf('    edtName: TEdit;'));
  Assert.AreEqual(0, TAtlasFormUnit.SpacesOf(''));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasFormUnitTests);

end.
