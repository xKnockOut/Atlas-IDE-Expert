unit Atlas.Common.Documents.FileEncoding.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework;

type
  [TestFixture]
  TFileEncodingTests = class
  public
    [Test]
    procedure DetectsBoms;
    [Test]
    procedure DetectsUtf8WithoutBom;
    [Test]
    procedure DetectsAnsiForInvalidUtf8;
    [Test]
    procedure PureAsciiUsesDefault;
    [Test]
    procedure RejectsOverlongUtf8;
    [Test]
    procedure DecodesAnsiUmlautsAndEuro;
    [Test]
    procedure DetectsDominantLineBreak;
    [Test]
    procedure RoundTripKeepsAnsiBytes;
    [Test]
    procedure RoundTripKeepsUtf8BomAndCrlf;
    [Test]
    procedure RoundTripKeepsUtf16;
    [Test]
    procedure EncodeNormalizesInsertedLineBreaks;
    [Test]
    procedure UnmappableAnsiCharacterBecomesQuestionMark;
    [Test]
    procedure SurveyCountsEncodings;
    [Test]
    procedure SurveyDetectsMixedProjects;
    [Test]
    procedure InvalidUtf8GivesLineAndColumn;
    [Test]
    procedure InvalidUtf8InPlainAnsiIsEmpty;
  end;

  /// <summary>Vorgabe-Kodierung je Ordner und Schutz binärer Formulare (#121).</summary>
  [TestFixture]
  TFileEncodingDefaultTests = class
  private
    FFolder: string;
    procedure WriteBytes(const AFileName: string; const ABytes: TBytes);
    function ReadAll(const AFileName: string): TBytes;
  public
    /// <summary>Erste Benutzung (VCL, Codepages, RTTI) ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DecodesCodePage1250;
    [Test]
    procedure PureAsciiFollowsAnsiDefault;
    [Test]
    procedure Utf8StaysUtf8WithAnsiDefault;
    [Test]
    procedure Utf8DefaultBehavesLikeDecode;
    [Test]
    procedure ParsesCodePageNames;
    [Test]
    procedure DeepestFolderWins;
    [Test]
    procedure LoadAndSaveUseFolderDefault;
    [Test]
    procedure TextFormRoundTripKeepsBytes;
    [Test]
    procedure DetectsBinaryForms;
    [Test]
    procedure NeverOverwritesBinaryForm;
    [Test]
    procedure AnsiDefaultUnitKeepsBytesOutsideEdit;
    [Test]
    procedure TextFormKeepsCharacterCodesAfterEdit;
    [Test]
    procedure SurveySkipsBinaryFormsAndNamesCodePage;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding;

function Bytes(const AValues: array of Byte): TBytes;
var
  Index: Integer;
begin
  SetLength(Result, Length(AValues));
  for Index := 0 to High(AValues) do
    Result[Index] := AValues[Index];
end;

function SameBytes(const A, B: TBytes): Boolean;
var
  Index: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
    for Index := 0 to High(A) do
      if A[Index] <> B[Index] then
        Exit(False);
end;

{ TFileEncodingTests }

procedure TFileEncodingTests.DetectsBoms;
begin
  Assert.IsTrue(TFileEncoding.DetectEncoding(Bytes([$EF, $BB, $BF, $41])) = TFileEncodingKind.Utf8Bom);
  Assert.IsTrue(TFileEncoding.DetectEncoding(Bytes([$FF, $FE, $41, $00])) = TFileEncodingKind.Utf16LE);
  Assert.IsTrue(TFileEncoding.DetectEncoding(Bytes([$FE, $FF, $00, $41])) = TFileEncodingKind.Utf16BE);
end;

procedure TFileEncodingTests.DetectsUtf8WithoutBom;
begin
  // "ä" als UTF-8
  Assert.IsTrue(TFileEncoding.DetectEncoding(Bytes([$61, $C3, $A4]), TFileEncodingKind.Ansi1252) = TFileEncodingKind.Utf8);
end;

procedure TFileEncodingTests.DetectsAnsiForInvalidUtf8;
begin
  // "ä" als Windows-1252, ungültig als UTF-8
  Assert.IsTrue(TFileEncoding.DetectEncoding(Bytes([$61, $E4, $62])) = TFileEncodingKind.Ansi1252);
  // Abgeschnittene Folge am Ende
  Assert.IsTrue(TFileEncoding.DetectEncoding(Bytes([$61, $C3])) = TFileEncodingKind.Ansi1252);
end;

procedure TFileEncodingTests.PureAsciiUsesDefault;
begin
  Assert.IsTrue(TFileEncoding.DetectEncoding(Bytes([$61, $62]), TFileEncodingKind.Ansi1252) = TFileEncodingKind.Ansi1252);
  Assert.IsTrue(TFileEncoding.DetectEncoding(Bytes([$61, $62])) = TFileEncodingKind.Utf8);
  Assert.IsTrue(TFileEncoding.DetectEncoding(Bytes([$61, $62]), TFileEncodingKind.Utf8Bom) = TFileEncodingKind.Utf8);
end;

procedure TFileEncodingTests.RejectsOverlongUtf8;
begin
  // Überlange Form von "/" und kodiertes Surrogat
  Assert.IsTrue(TFileEncoding.DetectEncoding(Bytes([$E0, $80, $AF])) = TFileEncodingKind.Ansi1252);
  Assert.IsTrue(TFileEncoding.DetectEncoding(Bytes([$ED, $A0, $80])) = TFileEncodingKind.Ansi1252);
end;

procedure TFileEncodingTests.DecodesAnsiUmlautsAndEuro;
var
  Format: TFileFormat;
  Text: string;
begin
  Text := TFileEncoding.Decode(Bytes([$E4, $F6, $FC, $DF, $80]), Format);
  Assert.IsTrue(Format.Encoding = TFileEncodingKind.Ansi1252);
  Assert.AreEqual(#$E4#$F6#$FC#$DF#$20AC, Text);
end;

procedure TFileEncodingTests.DetectsDominantLineBreak;
var
  Mixed: Boolean;
begin
  Assert.IsTrue(TFileEncoding.DetectLineBreak('a'#13#10'b'#13#10'c'#10, Mixed) = TLineBreakStyle.CRLF);
  Assert.IsTrue(Mixed);
  Assert.IsTrue(TFileEncoding.DetectLineBreak('a'#10'b'#10, Mixed) = TLineBreakStyle.LF);
  Assert.IsFalse(Mixed);
  Assert.IsTrue(TFileEncoding.DetectLineBreak('abc', Mixed, TLineBreakStyle.LF) = TLineBreakStyle.LF);
  Assert.IsFalse(Mixed);
end;

procedure TFileEncodingTests.RoundTripKeepsAnsiBytes;
var
  Original: TBytes;
  Format: TFileFormat;
  Text: string;
begin
  Original := Bytes([$75, $6E, $69, $74, $20, $C4, $3B, $0D, $0A, $80, $0D, $0A]);
  Text := TFileEncoding.Decode(Original, Format);
  Assert.IsTrue(Format.LineBreak = TLineBreakStyle.CRLF);
  Assert.IsTrue(SameBytes(Original, TFileEncoding.Encode(Text, Format)));
end;

procedure TFileEncodingTests.RoundTripKeepsUtf8BomAndCrlf;
var
  Original: TBytes;
  Format: TFileFormat;
  Text: string;
begin
  Original := Bytes([$EF, $BB, $BF, $61, $C3, $A4, $0D, $0A, $62]);
  Text := TFileEncoding.Decode(Original, Format);
  Assert.AreEqual('a'#$E4#13#10'b', Text);
  Assert.IsTrue(SameBytes(Original, TFileEncoding.Encode(Text, Format)));
end;

procedure TFileEncodingTests.RoundTripKeepsUtf16;
var
  Original: TBytes;
  Format: TFileFormat;
  Text: string;
begin
  Original := Bytes([$FF, $FE, $E4, $00, $0A, $00]);
  Text := TFileEncoding.Decode(Original, Format);
  Assert.AreEqual(#$E4#10, Text);
  Assert.IsTrue(Format.LineBreak = TLineBreakStyle.LF);
  Assert.IsTrue(SameBytes(Original, TFileEncoding.Encode(Text, Format)));
end;

procedure TFileEncodingTests.EncodeNormalizesInsertedLineBreaks;
var
  Format: TFileFormat;
begin
  Format := TFileFormat.Create(TFileEncodingKind.Utf8, TLineBreakStyle.CRLF);
  Assert.IsTrue(SameBytes(Bytes([$61, $0D, $0A, $62, $0D, $0A, $63]),
    TFileEncoding.Encode('a'#10'b'#13#10'c', Format)));
end;

procedure TFileEncodingTests.UnmappableAnsiCharacterBecomesQuestionMark;
var
  Format: TFileFormat;
begin
  Format := TFileFormat.Create(TFileEncodingKind.Ansi1252, TLineBreakStyle.CRLF);
  Assert.IsTrue(SameBytes(Bytes([$3F, $80]), TFileEncoding.Encode(#$0416#$20AC, Format)));
end;

procedure TFileEncodingTests.SurveyCountsEncodings;
var
  Survey: TEncodingSurvey;
begin
  Survey := Default(TEncodingSurvey);
  Survey.Add(Bytes([$41, $42]));
  Survey.Add(Bytes([$61, $C3, $A4]));
  Survey.Add(Bytes([$EF, $BB, $BF, $41]));
  Survey.Add(Bytes([$61, $E4]));
  Survey.Add(Bytes([$FF, $FE, $41, $00]));
  Assert.AreEqual(1, Survey.Ascii);
  Assert.AreEqual(2, Survey.Utf8);
  Assert.AreEqual(1, Survey.Ansi);
  Assert.AreEqual(1, Survey.Utf16);
  Assert.AreEqual('1 Datei in Windows-1252, 2 in UTF-8, 1 in UTF-16, 1 in reinem ASCII', Survey.Describe);
end;

procedure TFileEncodingTests.SurveyDetectsMixedProjects;
var
  Survey: TEncodingSurvey;
begin
  Survey := Default(TEncodingSurvey);
  // ASCII passt zu allem und mischt nichts.
  Survey.Add(Bytes([$41]));
  Survey.Add(Bytes([$61, $E4]));
  Assert.IsFalse(Survey.IsMixed);
  Survey.Add(Bytes([$61, $C3, $A4]));
  Assert.IsTrue(Survey.IsMixed);
end;

{ TFileEncodingDefaultTests }

procedure TFileEncodingDefaultTests.WarmUpFirstUse;
begin
  Setup;
  try
    DecodesCodePage1250;
  finally
    TearDown;
  end;
end;

procedure TFileEncodingDefaultTests.Setup;
begin
  FFolder := IncludeTrailingPathDelimiter(TPath.Combine(TPath.GetTempPath, 'AtlasEncoding' + IntToStr(Random(1000000))));
  ForceDirectories(FFolder + 'Sub');
  TFileEncodingDefaults.Clear;
end;

procedure TFileEncodingDefaultTests.TearDown;
begin
  TFileEncodingDefaults.Clear;
  if DirectoryExists(FFolder) then
    TDirectory.Delete(FFolder, True);
  FFolder := '';
end;

procedure TFileEncodingDefaultTests.WriteBytes(const AFileName: string; const ABytes: TBytes);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(AFileName, fmCreate);
  try
    if Length(ABytes) > 0 then
      Stream.WriteBuffer(ABytes[0], Length(ABytes));
  finally
    Stream.Free;
  end;
end;

function TFileEncodingDefaultTests.ReadAll(const AFileName: string): TBytes;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(AFileName, fmOpenRead);
  try
    SetLength(Result, Stream.Size);
    if Length(Result) > 0 then
      Stream.ReadBuffer(Result[0], Length(Result));
  finally
    Stream.Free;
  end;
end;

procedure TFileEncodingDefaultTests.DecodesCodePage1250;
var
  Format: TFileFormat;
  Source: TBytes;
  Text: string;
begin
  // "Šč" in Windows-1250; ungültiges UTF-8, also ANSI mit der Vorgabe.
  Source := Bytes([$8A, $E8, $0D, $0A]);
  Text := TFileEncoding.DecodeWithCodePage(Source, Format, 1250);
  Assert.AreEqual(#$0160#$010D#13#10, Text);
  Assert.IsTrue(Format.Encoding = TFileEncodingKind.Ansi1252);
  Assert.AreEqual(1250, Format.CodePage);
  Assert.IsTrue(SameBytes(Source, TFileEncoding.Encode(Text, Format)));
end;

procedure TFileEncodingDefaultTests.PureAsciiFollowsAnsiDefault;
var
  Format: TFileFormat;
  Text: string;
begin
  Text := TFileEncoding.DecodeWithCodePage(Bytes([$61, $62]), Format, 1250);
  Assert.IsTrue(Format.Encoding = TFileEncodingKind.Ansi1252);
  // Ein eingefügtes "č" landet als ein Byte der Codepage in der Datei.
  Assert.IsTrue(SameBytes(Bytes([$61, $62, $E8]), TFileEncoding.Encode(Text + #$010D, Format)));
end;

procedure TFileEncodingDefaultTests.Utf8StaysUtf8WithAnsiDefault;
var
  Format: TFileFormat;
begin
  Assert.AreEqual('a'#$E4, TFileEncoding.DecodeWithCodePage(Bytes([$61, $C3, $A4]), Format, 1250));
  Assert.IsTrue(Format.Encoding = TFileEncodingKind.Utf8);
end;

procedure TFileEncodingDefaultTests.Utf8DefaultBehavesLikeDecode;
var
  Format: TFileFormat;
begin
  TFileEncoding.DecodeWithCodePage(Bytes([$61, $62]), Format, TFileEncoding.Utf8CodePage);
  Assert.IsTrue(Format.Encoding = TFileEncodingKind.Utf8);
  Assert.AreEqual(#$00E4, TFileEncoding.DecodeWithCodePage(Bytes([$E4]), Format, TFileEncoding.Utf8CodePage));
  Assert.AreEqual(1252, Format.CodePage);
end;

procedure TFileEncodingDefaultTests.ParsesCodePageNames;
var
  CodePage: Integer;
begin
  Assert.IsTrue(TFileEncoding.ParseCodePage('utf-8', CodePage));
  Assert.AreEqual(65001, CodePage);
  Assert.IsTrue(TFileEncoding.ParseCodePage('UTF8', CodePage));
  Assert.AreEqual(65001, CodePage);
  Assert.IsTrue(TFileEncoding.ParseCodePage('65001', CodePage));
  Assert.IsTrue(TFileEncoding.ParseCodePage('windows-1250', CodePage));
  Assert.AreEqual(1250, CodePage);
  Assert.IsTrue(TFileEncoding.ParseCodePage(' CP1251 ', CodePage));
  Assert.AreEqual(1251, CodePage);
  Assert.IsTrue(TFileEncoding.ParseCodePage('1252', CodePage));
  Assert.AreEqual(1252, CodePage);
  Assert.IsFalse(TFileEncoding.ParseCodePage('latin9', CodePage));
  Assert.IsFalse(TFileEncoding.ParseCodePage('932', CodePage));
  Assert.IsFalse(TFileEncoding.ParseCodePage('', CodePage));
end;

procedure TFileEncodingDefaultTests.DeepestFolderWins;
begin
  Assert.AreEqual(65001, TFileEncodingDefaults.CodePageFor(FFolder + 'a.pas'));
  TFileEncodingDefaults.SetFolder(FFolder, 1250);
  TFileEncodingDefaults.SetFolder(FFolder + 'Sub', 1252);
  Assert.AreEqual(1250, TFileEncodingDefaults.CodePageFor(FFolder + 'a.pas'));
  Assert.AreEqual(1252, TFileEncodingDefaults.CodePageFor(FFolder + 'Sub' + PathDelim + 'b.pas'));
  // "Sub2" liegt nicht in "Sub".
  Assert.AreEqual(1250, TFileEncodingDefaults.CodePageFor(FFolder + 'Sub2' + PathDelim + 'c.pas'));
  TFileEncodingDefaults.RemoveFolder(FFolder);
  Assert.AreEqual(65001, TFileEncodingDefaults.CodePageFor(FFolder + 'a.pas'));
end;

procedure TFileEncodingDefaultTests.LoadAndSaveUseFolderDefault;
var
  FileName: string;
  Format: TFileFormat;
  Text: string;
begin
  FileName := FFolder + 'Unit1.pas';
  WriteBytes(FileName, Bytes([$61, $0D, $0A]));
  TFileEncodingDefaults.SetFolder(FFolder, 1250);
  Text := TFileEncoding.LoadFromFile(FileName, Format);
  Assert.AreEqual(1250, Format.CodePage);
  TFileEncoding.SaveToFile(FileName, Text + #$0160, Format);
  Assert.IsTrue(SameBytes(Bytes([$61, $0D, $0A, $8A]), ReadAll(FileName)));
end;

procedure TFileEncodingDefaultTests.TextFormRoundTripKeepsBytes;
const
  Form = 'object Form1: TForm1'#13#10'  Caption = ''Gr''#246#223''e'''#13#10'end'#13#10;
var
  FileName: string;
  Format: TFileFormat;
  Source: TBytes;
begin
  // Text-DFM mit #-Zeichen: reines ASCII, bleibt beim Zurückschreiben Byte für Byte gleich.
  FileName := FFolder + 'Unit1.dfm';
  Source := TEncoding.ASCII.GetBytes(Form);
  WriteBytes(FileName, Source);
  TFileEncodingDefaults.SetFolder(FFolder, 1250);
  TFileEncoding.SaveToFile(FileName, TFileEncoding.LoadFromFile(FileName, Format), Format);
  Assert.IsTrue(SameBytes(Source, ReadAll(FileName)));
end;

procedure TFileEncodingDefaultTests.DetectsBinaryForms;
begin
  Assert.IsTrue(TFileEncoding.IsBinaryForm(Bytes([Ord('T'), Ord('P'), Ord('F'), Ord('0'), 6])));
  Assert.IsTrue(TFileEncoding.IsBinaryForm(Bytes([$FF, $0A, $00, $54])));
  Assert.IsFalse(TFileEncoding.IsBinaryForm(Bytes([Ord('o'), Ord('b'), Ord('j')])));
  Assert.IsFalse(TFileEncoding.IsBinaryForm(nil));
  Assert.IsFalse(TFileEncoding.IsBinaryFormFile(FFolder + 'fehlt.dfm'));
end;

procedure TFileEncodingDefaultTests.NeverOverwritesBinaryForm;
var
  FileName: string;
  Source: TBytes;
  Raised: Boolean;
begin
  FileName := FFolder + 'Unit2.dfm';
  Source := Bytes([Ord('T'), Ord('P'), Ord('F'), Ord('0'), 6, Ord('T')]);
  WriteBytes(FileName, Source);
  Assert.IsTrue(TFileEncoding.IsBinaryFormFile(FileName));
  Raised := False;
  try
    TFileEncoding.SaveToFile(FileName, 'object Form1: TForm1'#13#10'end', TFileFormat.Create(TFileEncodingKind.Utf8,
      TLineBreakStyle.CRLF));
  except
    on EFileEncodingError do
      Raised := True;
  end;
  Assert.IsTrue(Raised);
  Assert.IsTrue(SameBytes(Source, ReadAll(FileName)));
end;

procedure TFileEncodingDefaultTests.AnsiDefaultUnitKeepsBytesOutsideEdit;
var
  FileName: string;
  Format: TFileFormat;
  Text: string;
begin
  // Abnahme #121: Unit in Codepage 1250 ohne BOM ("Š" = $8A, "č" = $E8), Vorgabe 1250, Code-Aktion
  // ersetzt "x" durch "y"; alles andere bleibt Byte für Byte gleich.
  FileName := FFolder + 'Unit3.pas';
  WriteBytes(FileName, Bytes([$8A, $0D, $0A, Ord('x'), $0D, $0A, $E8]));
  TFileEncodingDefaults.SetFolder(FFolder, 1250);
  Text := TFileEncoding.LoadFromFile(FileName, Format);
  Assert.AreEqual(#$0160#13#10'x'#13#10#$010D, Text);
  TFileEncoding.SaveToFile(FileName, StringReplace(Text, 'x', 'y', []), Format);
  Assert.IsTrue(SameBytes(Bytes([$8A, $0D, $0A, Ord('y'), $0D, $0A, $E8]), ReadAll(FileName)));
end;

procedure TFileEncodingDefaultTests.TextFormKeepsCharacterCodesAfterEdit;
const
  Form = 'object Form1: TForm1'#13#10'  object Button1: TButton'#13#10'    Caption = ''M''#228''rz'''#13#10 +
    '  end'#13#10'end'#13#10;
var
  FileName: string;
  Format: TFileFormat;
begin
  // Umbenennen in einer Text-DFM: "#228" bleibt in dieser Schreibweise stehen.
  FileName := FFolder + 'Unit4.dfm';
  WriteBytes(FileName, TEncoding.ASCII.GetBytes(Form));
  TFileEncoding.SaveToFile(FileName, StringReplace(TFileEncoding.LoadFromFile(FileName, Format), 'Button1',
    'btnOk', []), Format);
  Assert.IsTrue(SameBytes(TEncoding.ASCII.GetBytes(StringReplace(Form, 'Button1', 'btnOk', [])), ReadAll(FileName)));
end;

procedure TFileEncodingDefaultTests.SurveySkipsBinaryFormsAndNamesCodePage;
var
  Survey: TEncodingSurvey;
begin
  Survey := Default(TEncodingSurvey);
  Survey.AnsiCodePage := 1250;
  Survey.Add(Bytes([Ord('T'), Ord('P'), Ord('F'), Ord('0'), $E4]));
  Assert.AreEqual(0, Survey.Ansi + Survey.Utf8 + Survey.Ascii);
  Survey.Add(Bytes([$61, $E4]));
  Assert.AreEqual('1 Datei in Windows-1250', Survey.Describe);
  Survey.AnsiCodePage := TFileEncoding.Utf8CodePage;
  Assert.AreEqual('1 Datei in Windows-1252', Survey.Describe);
end;

procedure TFileEncodingTests.InvalidUtf8GivesLineAndColumn;
var
  Data: TBytes;
  Format: TFileFormat;
  Invalid: TArray<TInvalidUtf8>;
begin
  // BOM, "a" LF, Emoji (vier Bytes, zwei UTF-16-Einheiten), zu kurzes E2 82, "b", einzelnes $FF.
  Data := Bytes([$EF, $BB, $BF, Ord('a'), 10, $F0, $9F, $98, $80, $E2, $82, Ord('b'), $FF]);
  Format := TFileFormat.Create(TFileEncodingKind.Utf8Bom, TLineBreakStyle.LF);
  Invalid := TFileEncoding.InvalidUtf8(Data, Format);
  Assert.AreEqual(2, Integer(Length(Invalid)));
  Assert.AreEqual(1, Invalid[0].Position.Line);
  Assert.AreEqual(2, Invalid[0].Position.Character);
  Assert.AreEqual(9, Invalid[0].ByteOffset);
  Assert.AreEqual($E2, Integer(Invalid[0].Value));
  Assert.AreEqual(4, Invalid[1].Position.Character);
  // Gelesen als ANSI: ein Zeichen je Byte.
  Format := TFileFormat.Create(TFileEncodingKind.Ansi1252, TLineBreakStyle.LF);
  Invalid := TFileEncoding.InvalidUtf8(Copy(Data, 3, MaxInt), Format);
  Assert.AreEqual(4, Invalid[0].Position.Character);
end;

procedure TFileEncodingTests.InvalidUtf8InPlainAnsiIsEmpty;
var
  Format: TFileFormat;
begin
  Format := TFileFormat.Create(TFileEncodingKind.Ansi1252, TLineBreakStyle.CRLF);
  Assert.AreEqual(0, Integer(Length(TFileEncoding.InvalidUtf8(Bytes([Ord('a'), $E4, Ord('b')]), Format))));
end;

initialization
  TDUnitX.RegisterTestFixture(TFileEncodingTests);
  TDUnitX.RegisterTestFixture(TFileEncodingDefaultTests);

end.
