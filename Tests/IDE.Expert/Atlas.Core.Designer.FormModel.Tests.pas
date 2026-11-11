unit Atlas.Core.Designer.FormModel.Tests;

// Tests des Formulartexts als Komponentenliste (#738): Objekte samt Tiefe und
// Besitzer, einzeilige und fortgesetzte Werte, Ereignisse, übersprungene
// Listen, Kollektionen und Binärdaten, String-Werte.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasFormModelTests = class
  public
    [Test]
    procedure ObjectsWithOwnerAndDepth;
    [Test]
    procedure ValuesAndEvents;
    [Test]
    procedure SkipsListsCollectionsAndBinary;
    [Test]
    procedure ContinuedStringIsOneValue;
    [Test]
    procedure StringValues;
  end;

implementation

uses
  Atlas.Core.Designer.FormModel;

const
  cForm =
    'object Form1: TForm1' + #13#10 +
    '  Caption = ''Kunden''' + #13#10 +
    '  Font.Name = ''Tahoma''' + #13#10 +
    '  OnCreate = FormCreate' + #13#10 +
    '  object Panel1: TPanel' + #13#10 +
    '    Left = 8' + #13#10 +
    '    object edtName: TEdit' + #13#10 +
    '      Text = ''''' + #13#10 +
    '      OnChange = EingabeChange' + #13#10 +
    '    end' + #13#10 +
    '  end' + #13#10 +
    '  object lstOrte: TListBox' + #13#10 +
    '    Items.Strings = (' + #13#10 +
    '      ''Berlin''' + #13#10 +
    '      ''Hamburg'')' + #13#10 +
    '    Columns = <' + #13#10 +
    '      item' + #13#10 +
    '        Width = 20' + #13#10 +
    '      end>' + #13#10 +
    '    Picture.Data = {' + #13#10 +
    '      0102}' + #13#10 +
    '    TabOrder = 1' + #13#10 +
    '  end' + #13#10 +
    '  inherited dsKunden: TDataSource [2]' + #13#10 +
    '    Hint = ' + #13#10 +
    '      ''erste Zeile'' +' + #13#10 +
    '      ''zweite''' + #13#10 +
    '  end' + #13#10 +
    'end' + #13#10;

procedure TAtlasFormModelTests.ObjectsWithOwnerAndDepth;
var
  mObjects: TArray<TAtlasFormObject>;
begin
  mObjects := TAtlasFormModel.Parse(cForm);
  Assert.AreEqual(5, Integer(Length(mObjects)));
  Assert.AreEqual('Form1', mObjects[0].Name);
  Assert.AreEqual('TForm1', mObjects[0].TypeName);
  Assert.AreEqual(0, mObjects[0].Depth);
  Assert.AreEqual('', mObjects[0].OwnerName);
  Assert.AreEqual('edtName', mObjects[2].Name);
  Assert.AreEqual('Panel1', mObjects[2].OwnerName);
  Assert.AreEqual(2, mObjects[2].Depth);
  Assert.AreEqual('dsKunden', mObjects[4].Name, 'inherited mit [n]');
  Assert.AreEqual('TDataSource', mObjects[4].TypeName);
  Assert.AreEqual(3, TAtlasFormModel.IndexOf(mObjects, 'LSTORTE'));
  Assert.AreEqual(-1, TAtlasFormModel.IndexOf(mObjects, 'Fehlt'));
end;

procedure TAtlasFormModelTests.ValuesAndEvents;
var
  mObjects: TArray<TAtlasFormObject>;
  mValue: string;
begin
  mObjects := TAtlasFormModel.Parse(cForm);
  Assert.AreEqual(2, Integer(Length(mObjects[0].Values)));
  Assert.AreEqual('Font.Name = ''Tahoma''', mObjects[0].Values[1].Text);
  Assert.AreEqual(1, Integer(Length(mObjects[0].Events)));
  Assert.AreEqual('OnCreate', mObjects[0].Events[0].Path);
  Assert.AreEqual('FormCreate', mObjects[0].Events[0].Value);
  Assert.IsTrue(mObjects[1].ValueOf('left', mValue));
  Assert.AreEqual('8', mValue);
  Assert.IsFalse(mObjects[1].ValueOf('Top', mValue));
  Assert.AreEqual('EingabeChange', mObjects[2].Events[0].Value);
  Assert.AreEqual('''''', mObjects[2].Values[0].Value, 'leerer String bleibt ein Wert');
end;

procedure TAtlasFormModelTests.SkipsListsCollectionsAndBinary;
var
  mObjects: TArray<TAtlasFormObject>;
begin
  mObjects := TAtlasFormModel.Parse(cForm);
  Assert.AreEqual(1, Integer(Length(mObjects[3].Values)), 'nur TabOrder');
  Assert.AreEqual('TabOrder', mObjects[3].Values[0].Path);
end;

procedure TAtlasFormModelTests.ContinuedStringIsOneValue;
var
  mObjects: TArray<TAtlasFormObject>;
  mText: string;
begin
  mObjects := TAtlasFormModel.Parse(cForm);
  Assert.AreEqual(1, Integer(Length(mObjects[4].Values)));
  Assert.AreEqual('Hint', mObjects[4].Values[0].Path);
  Assert.IsTrue(TAtlasFormModel.StringValue(mObjects[4].Values[0].Value, mText));
  Assert.AreEqual('erste Zeilezweite', mText);
end;

procedure TAtlasFormModelTests.StringValues;
var
  mText: string;
begin
  Assert.IsTrue(TAtlasFormModel.StringValue('''It''''s''', mText));
  Assert.AreEqual('It''s', mText);
  Assert.IsTrue(TAtlasFormModel.StringValue('''a''#13''b''', mText));
  Assert.AreEqual('a' + #13 + 'b', mText);
  Assert.IsTrue(TAtlasFormModel.StringValue('''''', mText));
  Assert.AreEqual('', mText);
  Assert.IsFalse(TAtlasFormModel.StringValue('clRed', mText));
  Assert.IsFalse(TAtlasFormModel.StringValue('''offen', mText));
end;

end.
