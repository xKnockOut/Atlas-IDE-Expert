unit BDLsp.Common.Dfm.BinaryForm.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDfmBinaryTests = class
  public
    [Test]
    procedure ConvertsSimpleForm;
    [Test]
    procedure WritesSpecialCharactersAsCodes;
    [Test]
    procedure SplitsLongStrings;
    [Test]
    procedure ConvertsCollectionsListsAndBinaryData;
    [Test]
    procedure ConvertsInheritedWithPosition;
    [Test]
    procedure SkipsResourceHeader;
    [Test]
    procedure RejectsDamagedData;
    [Test]
    procedure ParserReadsDecodedBinaryText;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Dfm.Contract,
  BDLsp.Common.Dfm.Parser,
  BDLsp.Common.Dfm.BinaryForm;

function B(const AValues: array of Byte): TBytes;
var
  Index: Integer;
begin
  SetLength(Result, Length(AValues));
  for Index := 0 to High(AValues) do
    Result[Index] := AValues[Index];
end;

/// <summary>Kurzer String mit Längenbyte.</summary>
function S(const AText: string): TBytes;
begin
  Result := B([Length(AText)]) + TEncoding.ASCII.GetBytes(AText);
end;

function Ident(const AText: string): TBytes;
begin
  Result := B([7]) + S(AText);
end;

function Str(const AText: string): TBytes;
begin
  Result := B([6]) + S(AText);
end;

function Header: TBytes;
begin
  Result := TEncoding.ASCII.GetBytes('TPF0');
end;

function Convert(const ABytes: TBytes): string;
begin
  Assert.IsTrue(TDfmBinary.ToText(ABytes, Result), 'Umwandlung');
end;

procedure TDfmBinaryTests.ConvertsSimpleForm;
var
  Bytes: TBytes;
begin
  Bytes := Header + S('TForm1') + S('Form1') +
    S('Left') + B([2, 8]) +
    S('Width') + B([3, $2C, $01]) +
    S('Caption') + Str('Hallo') +
    S('Color') + Ident('clBtnFace') +
    S('Visible') + B([8]) +
    S('Anchors') + B([11]) + S('akLeft') + S('akTop') + B([0]) +
    B([0]) +
    S('TButton') + S('Button1') +
    S('OnClick') + Ident('Button1Click') +
    B([0, 0]) +
    B([0]);
  Assert.AreEqual(
    'object Form1: TForm1'#13#10 +
    '  Left = 8'#13#10 +
    '  Width = 300'#13#10 +
    '  Caption = ''Hallo'''#13#10 +
    '  Color = clBtnFace'#13#10 +
    '  Visible = False'#13#10 +
    '  Anchors = [akLeft, akTop]'#13#10 +
    '  object Button1: TButton'#13#10 +
    '    OnClick = Button1Click'#13#10 +
    '  end'#13#10 +
    'end'#13#10, Convert(Bytes));
end;

procedure TDfmBinaryTests.WritesSpecialCharactersAsCodes;
var
  Bytes: TBytes;
begin
  // vaWString: Anzahl UTF-16-Zeichen, dann die Zeichen.
  Bytes := Header + S('TForm1') + S('Form1') +
    S('Caption') + B([18, 7, 0, 0, 0]) + TEncoding.Unicode.GetBytes('Kai''s ä') +
    B([0, 0]);
  Assert.AreEqual('object Form1: TForm1'#13#10'  Caption = ''Kai''#39''s ''#228'#13#10'end'#13#10, Convert(Bytes));
end;

procedure TDfmBinaryTests.SplitsLongStrings;
var
  Bytes: TBytes;
  Text: string;
begin
  Text := StringOfChar('a', 70);
  Bytes := Header + S('TForm1') + S('Form1') + S('Hint') + Str(Text) + B([0, 0]);
  Assert.AreEqual('object Form1: TForm1'#13#10 +
    '  Hint = '#13#10 +
    '    ''' + StringOfChar('a', 64) + ''' +'#13#10 +
    '    ''' + StringOfChar('a', 6) + ''''#13#10 +
    'end'#13#10, Convert(Bytes));
end;

procedure TDfmBinaryTests.ConvertsCollectionsListsAndBinaryData;
var
  Bytes: TBytes;
begin
  Bytes := Header + S('TForm1') + S('Form1') +
    S('Columns') + B([14]) +
      B([1]) + S('Caption') + Str('A') + B([0]) +
      B([2, 5, 1]) + S('Width') + B([2, 40]) + B([0]) +
    B([0]) +
    S('Items.Strings') + B([1]) + Str('x') + Str('y') + B([0]) +
    S('Data') + B([10, 3, 0, 0, 0, $01, $AB, $FF]) +
    B([0, 0]);
  Assert.AreEqual('object Form1: TForm1'#13#10 +
    '  Columns = <'#13#10 +
    '    item'#13#10 +
    '      Caption = ''A'''#13#10 +
    '    end'#13#10 +
    '    item [5]'#13#10 +
    '      Width = 40'#13#10 +
    '    end>'#13#10 +
    '  Items.Strings = ('#13#10 +
    '    ''x'''#13#10 +
    '    ''y'')'#13#10 +
    '  Data = {'#13#10 +
    '    01ABFF}'#13#10 +
    'end'#13#10, Convert(Bytes));
end;

procedure TDfmBinaryTests.ConvertsInheritedWithPosition;
var
  Bytes: TBytes;
begin
  Bytes := Header + B([$F1]) + S('TForm2') + S('Form2') + B([0]) +
    B([$F3, 2, 1]) + S('TButton') + S('Ok') + B([0, 0]) +
    B([$F4]) + S('TRahmen') + S('Rahmen1') + B([0, 0]) +
    B([0]);
  Assert.AreEqual('inherited Form2: TForm2'#13#10 +
    '  inherited Ok: TButton [1]'#13#10 +
    '  end'#13#10 +
    '  inline Rahmen1: TRahmen'#13#10 +
    '  end'#13#10 +
    'end'#13#10, Convert(Bytes));
end;

procedure TDfmBinaryTests.SkipsResourceHeader;
var
  Bytes: TBytes;
begin
  Bytes := B([$FF, $0A, $00]) + TEncoding.ASCII.GetBytes('TFORM1') + B([0, $30, $10, 20, 0, 0, 0]) +
    Header + S('TForm1') + S('Form1') + B([0, 0]);
  Assert.IsTrue(TDfmBinary.IsBinary(Bytes));
  Assert.AreEqual('object Form1: TForm1'#13#10'end'#13#10, Convert(Bytes));
end;

procedure TDfmBinaryTests.RejectsDamagedData;
var
  Text: string;
begin
  Assert.IsFalse(TDfmBinary.ToText(Header + S('TForm1') + S('Form1') + S('Left'), Text));
  Assert.IsFalse(TDfmBinary.ToText(TEncoding.ASCII.GetBytes('object Form1: TForm1'), Text));
end;

procedure TDfmBinaryTests.ParserReadsDecodedBinaryText;
var
  Bytes: TBytes;
  Decoded: string;
  Index: Integer;
  Document: TDfmDocument;
begin
  // So kommt der Inhalt aus TFileEncoding (Windows-1252, ein Zeichen je Byte).
  Bytes := Header + S('TForm1') + S('Form1') + S('Width') + B([3, $2C, $01]) + B([0]) +
    S('TButton') + S('Button1') + S('OnClick') + Ident('Button1Click') + B([0, 0]) + B([0]);
  Decoded := '';
  for Index := 0 to High(Bytes) do
    Decoded := Decoded + Char(Bytes[Index]);
  Document := TDfmParser.Parse(Decoded);
  try
    Assert.AreEqual(0, Integer(Length(Document.Errors)));
    Assert.AreEqual('TForm1', Document.Root.TypeName);
    Assert.AreEqual('Button1', Document.Root.Children[0].Name);
    Assert.AreEqual('Button1Click', Document.Root.Children[0].Properties[0].Value);
  finally
    Document.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDfmBinaryTests);

end.
