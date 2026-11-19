unit Atlas.Common.Dfm.BinaryForm.Tests;

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
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Dfm.BinaryForm;

/// <summary>Kurzer String mit Längenbyte.</summary>
function S(const AText: string): TBytes;
begin
  Result := TBytes.Create(Length(AText)) + TEncoding.ASCII.GetBytes(AText);
end;

function Ident(const AText: string): TBytes;
begin
  Result := TBytes.Create(7) + S(AText);
end;

function Str(const AText: string): TBytes;
begin
  Result := TBytes.Create(6) + S(AText);
end;

function Header: TBytes;
begin
  Result := TEncoding.ASCII.GetBytes('TPF0');
end;

function Convert(const ABytes: TBytes): string;
begin
  Assert.IsTrue(TDfmBinary.ToText(ABytes, Result), 'Umwandlung');
end;

/// <summary>Formular mit den gängigen Werttypen und einer Unterkomponente.</summary>
function SimpleForm: TBytes;
begin
  Result := Header + S('TForm1') + S('Form1') +
    S('Left') + TBytes.Create(2, 8) +
    S('Width') + TBytes.Create(3, $2C, $01) +
    S('Caption') + Str('Hallo') +
    S('Color') + Ident('clBtnFace') +
    S('Visible') + TBytes.Create(8) +
    S('Anchors') + TBytes.Create(11) + S('akLeft') + S('akTop') + TBytes.Create(0) +
    TBytes.Create(0) +
    S('TButton') + S('Button1') +
    S('OnClick') + Ident('Button1Click') +
    TBytes.Create(0, 0) +
    TBytes.Create(0);
end;

{ TDfmBinaryTests }

procedure TDfmBinaryTests.ConvertsSimpleForm;
begin
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
    'end'#13#10, Convert(SimpleForm));
end;

procedure TDfmBinaryTests.WritesSpecialCharactersAsCodes;
var
  mBytes: TBytes;
begin
  // vaWString: Anzahl UTF-16-Zeichen, dann die Zeichen.
  mBytes := Header + S('TForm1') + S('Form1') +
    S('Caption') + TBytes.Create(18, 7, 0, 0, 0) + TEncoding.Unicode.GetBytes('Kai''s ä') +
    TBytes.Create(0, 0);
  Assert.AreEqual('object Form1: TForm1'#13#10'  Caption = ''Kai''#39''s ''#228'#13#10'end'#13#10, Convert(mBytes));
end;

procedure TDfmBinaryTests.SplitsLongStrings;
var
  mBytes: TBytes;
  mText: string;
begin
  mText := StringOfChar('a', 70);
  mBytes := Header + S('TForm1') + S('Form1') + S('Hint') + Str(mText) + TBytes.Create(0, 0);
  Assert.AreEqual('object Form1: TForm1'#13#10 +
    '  Hint = '#13#10 +
    '    ''' + StringOfChar('a', 64) + ''' +'#13#10 +
    '    ''' + StringOfChar('a', 6) + ''''#13#10 +
    'end'#13#10, Convert(mBytes));
end;

procedure TDfmBinaryTests.ConvertsCollectionsListsAndBinaryData;
var
  mBytes: TBytes;
begin
  mBytes := Header + S('TForm1') + S('Form1') +
    S('Columns') + TBytes.Create(14) +
      TBytes.Create(1) + S('Caption') + Str('A') + TBytes.Create(0) +
      TBytes.Create(2, 5, 1) + S('Width') + TBytes.Create(2, 40) + TBytes.Create(0) +
    TBytes.Create(0) +
    S('Items.Strings') + TBytes.Create(1) + Str('x') + Str('y') + TBytes.Create(0) +
    S('Data') + TBytes.Create(10, 3, 0, 0, 0, $01, $AB, $FF) +
    TBytes.Create(0, 0);
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
    'end'#13#10, Convert(mBytes));
end;

procedure TDfmBinaryTests.ConvertsInheritedWithPosition;
var
  mBytes: TBytes;
begin
  mBytes := Header + TBytes.Create($F1) + S('TForm2') + S('Form2') + TBytes.Create(0) +
    TBytes.Create($F3, 2, 1) + S('TButton') + S('Ok') + TBytes.Create(0, 0) +
    TBytes.Create($F4) + S('TRahmen') + S('Rahmen1') + TBytes.Create(0, 0) +
    TBytes.Create(0);
  Assert.AreEqual('inherited Form2: TForm2'#13#10 +
    '  inherited Ok: TButton [1]'#13#10 +
    '  end'#13#10 +
    '  inline Rahmen1: TRahmen'#13#10 +
    '  end'#13#10 +
    'end'#13#10, Convert(mBytes));
end;

procedure TDfmBinaryTests.SkipsResourceHeader;
var
  mBytes: TBytes;
begin
  mBytes := TBytes.Create($FF, $0A, $00) + TEncoding.ASCII.GetBytes('TFORM1') + TBytes.Create(0, $30, $10, 20, 0, 0, 0) +
    Header + S('TForm1') + S('Form1') + TBytes.Create(0, 0);
  Assert.IsTrue(TDfmBinary.IsBinary(mBytes));
  Assert.AreEqual('object Form1: TForm1'#13#10'end'#13#10, Convert(mBytes));
end;

procedure TDfmBinaryTests.RejectsDamagedData;
var
  mText: string;
begin
  Assert.IsFalse(TDfmBinary.ToText(Header + S('TForm1') + S('Form1') + S('Left'), mText));
  Assert.IsFalse(TDfmBinary.ToText(TEncoding.ASCII.GetBytes('object Form1: TForm1'), mText));
end;

procedure TDfmBinaryTests.ParserReadsDecodedBinaryText;
var
  mBytes: TBytes;
  mDecoded: string;
  mIndex: Integer;
  mDocument: TDfmDocument;
begin
  // So kommt der Inhalt aus TFileEncoding (Windows-1252, ein Zeichen je Byte).
  mBytes := Header + S('TForm1') + S('Form1') + S('Width') + TBytes.Create(3, $2C, $01) + TBytes.Create(0) +
    S('TButton') + S('Button1') + S('OnClick') + Ident('Button1Click') + TBytes.Create(0, 0) + TBytes.Create(0);
  mDecoded := '';
  for mIndex := 0 to High(mBytes) do
  begin
    mDecoded := mDecoded + Char(mBytes[mIndex]);
  end;
  mDocument := TDfmParser.Parse(mDecoded);
  try
    Assert.AreEqual(0, Integer(Length(mDocument.Errors)));
    Assert.AreEqual('TForm1', mDocument.Root.TypeName);
    Assert.AreEqual('Button1', mDocument.Root.Children[0].Name);
    Assert.AreEqual('Button1Click', mDocument.Root.Children[0].Properties[0].Value);
  finally
    mDocument.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDfmBinaryTests);

end.
