unit Atlas.Common.Documents.FileEncoding.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework;

type
  [TestFixture]
  TFileEncodingTests = class
  public
    /// <summary>#1358: EncodeKeepingLineBreaks lässt gemischte Umbrüche, Encode vereinheitlicht sie.</summary>
    [Test]
    procedure EncodeKeepingLineBreaksKeepsMixed;
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
    /// <summary>Minimalfall F15 (#1327): ANSI mit einem zufällig gültigen UTF-8-Paar bleibt ANSI, auch in
    /// InvalidUtf8; als ganz gültiges UTF-8 ohne BOM ist dieselbe Datei UTF-8, mit BOM gilt die BOM.</summary>
    [Test]
    procedure AnsiWithStrayUtf8PairStaysAnsi;
    [Test]
    procedure MostlyUtf8WithStrayByteIsDamagedUtf8;
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
    procedure LoadTextAndLinesDetectEncoding;
    [Test]
    procedure TextFormRoundTripKeepsBytes;
    [Test]
    procedure DetectsBinaryForms;
    [Test]
    procedure DetectsUtf32Bom;
    [Test]
    procedure NeverOverwritesBinaryForm;
    [Test]
    procedure AnsiDefaultUnitKeepsBytesOutsideEdit;
    [Test]
    procedure TextFormKeepsCharacterCodesAfterEdit;
    [Test]
    procedure SurveySkipsBinaryFormsAndNamesCodePage;
    /// <summary>LoadFromFile liest über den Leser der Plattform.</summary>
    [Test]
    procedure LoadsThroughPlatformReader;
    /// <summary>Ohne Leser der Plattform: lesen, während ein anderer die Datei zum Schreiben offen hat.</summary>
    [Test]
    procedure ReadsWhileSomeoneWrites;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding;

function Bytes(const AValues: array of Byte): TBytes;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AValues));
  for mIndex := 0 to High(AValues) do
  begin
    Result[mIndex] := AValues[mIndex];
  end;
end;

function SameBytes(const A, B: TBytes): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
  begin
    for mIndex := 0 to High(A) do
    begin
      if A[mIndex] <> B[mIndex] then
      begin
        Exit(False);
      end;
    end;
  end;
end;

{ TFileEncodingTests }

procedure TFileEncodingTests.DetectsBoms;
begin
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Utf8Bom,
    TFileEncoding.DetectEncoding(Bytes([$EF, $BB, $BF, $41])));
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Utf16LE,
    TFileEncoding.DetectEncoding(Bytes([$FF, $FE, $41, $00])));
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Utf16BE,
    TFileEncoding.DetectEncoding(Bytes([$FE, $FF, $00, $41])));
end;

procedure TFileEncodingTests.DetectsUtf8WithoutBom;
begin
  // "ä" als UTF-8
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Utf8,
    TFileEncoding.DetectEncoding(Bytes([$61, $C3, $A4]), TFileEncodingKind.Ansi1252));
end;

procedure TFileEncodingTests.DetectsAnsiForInvalidUtf8;
begin
  // "ä" als Windows-1252, ungültig als UTF-8
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Ansi1252, TFileEncoding.DetectEncoding(Bytes([$61, $E4, $62])));
  // Abgeschnittene Folge am Ende
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Ansi1252, TFileEncoding.DetectEncoding(Bytes([$61, $C3])));
end;

procedure TFileEncodingTests.PureAsciiUsesDefault;
begin
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Ansi1252,
    TFileEncoding.DetectEncoding(Bytes([$61, $62]), TFileEncodingKind.Ansi1252));
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Utf8, TFileEncoding.DetectEncoding(Bytes([$61, $62])));
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Utf8,
    TFileEncoding.DetectEncoding(Bytes([$61, $62]), TFileEncodingKind.Utf8Bom));
end;

procedure TFileEncodingTests.RejectsOverlongUtf8;
begin
  // Überlange Form von "/" und kodiertes Surrogat
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Ansi1252, TFileEncoding.DetectEncoding(Bytes([$E0, $80, $AF])));
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Ansi1252, TFileEncoding.DetectEncoding(Bytes([$ED, $A0, $80])));
end;

procedure TFileEncodingTests.DecodesAnsiUmlautsAndEuro;
var
  mFormat: TFileFormat;
  mText: string;
begin
  mText := TFileEncoding.Decode(Bytes([$E4, $F6, $FC, $DF, $80]), mFormat);
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Ansi1252, mFormat.Encoding);
  Assert.AreEqual(#$E4#$F6#$FC#$DF#$20AC, mText);
end;

procedure TFileEncodingTests.DetectsDominantLineBreak;
var
  mMixed: Boolean;
begin
  Assert.AreEqual<TLineBreakStyle>(TLineBreakStyle.CRLF,
    TFileEncoding.DetectLineBreak('a'#13#10'b'#13#10'c'#10, mMixed));
  Assert.IsTrue(mMixed);
  Assert.AreEqual<TLineBreakStyle>(TLineBreakStyle.LF, TFileEncoding.DetectLineBreak('a'#10'b'#10, mMixed));
  Assert.IsFalse(mMixed);
  Assert.AreEqual<TLineBreakStyle>(TLineBreakStyle.LF, TFileEncoding.DetectLineBreak('abc', mMixed, TLineBreakStyle.LF));
  Assert.IsFalse(mMixed);
end;

procedure TFileEncodingTests.RoundTripKeepsAnsiBytes;
var
  mOriginal: TBytes;
  mFormat: TFileFormat;
  mText: string;
begin
  mOriginal := Bytes([$75, $6E, $69, $74, $20, $C4, $3B, $0D, $0A, $80, $0D, $0A]);
  mText := TFileEncoding.Decode(mOriginal, mFormat);
  Assert.AreEqual<TLineBreakStyle>(TLineBreakStyle.CRLF, mFormat.LineBreak);
  Assert.IsTrue(SameBytes(mOriginal, TFileEncoding.Encode(mText, mFormat)));
end;

procedure TFileEncodingTests.RoundTripKeepsUtf8BomAndCrlf;
var
  mOriginal: TBytes;
  mFormat: TFileFormat;
  mText: string;
begin
  mOriginal := Bytes([$EF, $BB, $BF, $61, $C3, $A4, $0D, $0A, $62]);
  mText := TFileEncoding.Decode(mOriginal, mFormat);
  Assert.AreEqual('a'#$E4#13#10'b', mText);
  Assert.IsTrue(SameBytes(mOriginal, TFileEncoding.Encode(mText, mFormat)));
end;

procedure TFileEncodingTests.RoundTripKeepsUtf16;
var
  mOriginal: TBytes;
  mFormat: TFileFormat;
  mText: string;
begin
  mOriginal := Bytes([$FF, $FE, $E4, $00, $0A, $00]);
  mText := TFileEncoding.Decode(mOriginal, mFormat);
  Assert.AreEqual(#$E4#10, mText);
  Assert.AreEqual<TLineBreakStyle>(TLineBreakStyle.LF, mFormat.LineBreak);
  Assert.IsTrue(SameBytes(mOriginal, TFileEncoding.Encode(mText, mFormat)));
end;

procedure TFileEncodingTests.EncodeNormalizesInsertedLineBreaks;
var
  mFormat: TFileFormat;
begin
  mFormat := TFileFormat.Create(TFileEncodingKind.Utf8, TLineBreakStyle.CRLF);
  Assert.IsTrue(SameBytes(Bytes([$61, $0D, $0A, $62, $0D, $0A, $63]),
    TFileEncoding.Encode('a'#10'b'#13#10'c', mFormat)));
end;

procedure TFileEncodingTests.UnmappableAnsiCharacterBecomesQuestionMark;
var
  mFormat: TFileFormat;
begin
  mFormat := TFileFormat.Create(TFileEncodingKind.Ansi1252, TLineBreakStyle.CRLF);
  Assert.IsTrue(SameBytes(Bytes([$3F, $80]), TFileEncoding.Encode(#$0416#$20AC, mFormat)));
end;

procedure TFileEncodingTests.SurveyCountsEncodings;
var
  mSurvey: TEncodingSurvey;
begin
  mSurvey := Default(TEncodingSurvey);
  mSurvey.Add(Bytes([$41, $42]));
  mSurvey.Add(Bytes([$61, $C3, $A4]));
  mSurvey.Add(Bytes([$EF, $BB, $BF, $41]));
  mSurvey.Add(Bytes([$61, $E4]));
  mSurvey.Add(Bytes([$FF, $FE, $41, $00]));
  Assert.AreEqual(1, mSurvey.Ascii);
  Assert.AreEqual(2, mSurvey.Utf8);
  Assert.AreEqual(1, mSurvey.Ansi);
  Assert.AreEqual(1, mSurvey.Utf16);
  Assert.AreEqual('1 Datei in Windows-1252, 2 in UTF-8, 1 in UTF-16, 1 in reinem ASCII', mSurvey.Describe);
end;

procedure TFileEncodingTests.SurveyDetectsMixedProjects;
var
  mSurvey: TEncodingSurvey;
begin
  mSurvey := Default(TEncodingSurvey);
  // ASCII passt zu allem und mischt nichts.
  mSurvey.Add(Bytes([$41]));
  mSurvey.Add(Bytes([$61, $E4]));
  Assert.IsFalse(mSurvey.IsMixed);
  mSurvey.Add(Bytes([$61, $C3, $A4]));
  Assert.IsTrue(mSurvey.IsMixed);
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
  TFileEncoding.Reader := nil;
  TFileEncodingDefaults.Clear;
  if DirectoryExists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
end;

procedure TFileEncodingDefaultTests.WriteBytes(const AFileName: string; const ABytes: TBytes);
var
  mStream: TFileStream;
begin
  mStream := TFileStream.Create(AFileName, fmCreate);
  try
    if Length(ABytes) > 0 then
    begin
      mStream.WriteBuffer(ABytes[0], Length(ABytes));
    end;
  finally
    mStream.Free;
  end;
end;

function TFileEncodingDefaultTests.ReadAll(const AFileName: string): TBytes;
var
  mStream: TFileStream;
begin
  mStream := TFileStream.Create(AFileName, fmOpenRead);
  try
    SetLength(Result, mStream.Size);
    if Length(Result) > 0 then
    begin
      mStream.ReadBuffer(Result[0], Length(Result));
    end;
  finally
    mStream.Free;
  end;
end;

procedure TFileEncodingDefaultTests.DecodesCodePage1250;
var
  mFormat: TFileFormat;
  mSource: TBytes;
  mText: string;
begin
  // "Šč" in Windows-1250; ungültiges UTF-8, also ANSI mit der Vorgabe.
  mSource := Bytes([$8A, $E8, $0D, $0A]);
  mText := TFileEncoding.DecodeWithCodePage(mSource, mFormat, 1250);
  Assert.AreEqual(#$0160#$010D#13#10, mText);
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Ansi1252, mFormat.Encoding);
  Assert.AreEqual(1250, mFormat.CodePage);
  Assert.IsTrue(SameBytes(mSource, TFileEncoding.Encode(mText, mFormat)));
end;

procedure TFileEncodingDefaultTests.PureAsciiFollowsAnsiDefault;
var
  mFormat: TFileFormat;
  mText: string;
begin
  mText := TFileEncoding.DecodeWithCodePage(Bytes([$61, $62]), mFormat, 1250);
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Ansi1252, mFormat.Encoding);
  // Ein eingefügtes "č" landet als ein Byte der Codepage in der Datei.
  Assert.IsTrue(SameBytes(Bytes([$61, $62, $E8]), TFileEncoding.Encode(mText + #$010D, mFormat)));
end;

procedure TFileEncodingDefaultTests.Utf8StaysUtf8WithAnsiDefault;
var
  mFormat: TFileFormat;
begin
  Assert.AreEqual('a'#$E4, TFileEncoding.DecodeWithCodePage(Bytes([$61, $C3, $A4]), mFormat, 1250));
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Utf8, mFormat.Encoding);
end;

procedure TFileEncodingDefaultTests.Utf8DefaultBehavesLikeDecode;
var
  mFormat: TFileFormat;
begin
  TFileEncoding.DecodeWithCodePage(Bytes([$61, $62]), mFormat, TFileEncoding.cUtf8CodePage);
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Utf8, mFormat.Encoding);
  Assert.AreEqual(#$00E4, TFileEncoding.DecodeWithCodePage(Bytes([$E4]), mFormat, TFileEncoding.cUtf8CodePage));
  Assert.AreEqual(1252, mFormat.CodePage);
end;

procedure TFileEncodingDefaultTests.ParsesCodePageNames;
var
  mCodePage: Integer;
begin
  Assert.IsTrue(TFileEncoding.ParseCodePage('utf-8', mCodePage));
  Assert.AreEqual(65001, mCodePage);
  Assert.IsTrue(TFileEncoding.ParseCodePage('UTF8', mCodePage));
  Assert.AreEqual(65001, mCodePage);
  Assert.IsTrue(TFileEncoding.ParseCodePage('65001', mCodePage));
  Assert.IsTrue(TFileEncoding.ParseCodePage('windows-1250', mCodePage));
  Assert.AreEqual(1250, mCodePage);
  Assert.IsTrue(TFileEncoding.ParseCodePage(' CP1251 ', mCodePage));
  Assert.AreEqual(1251, mCodePage);
  Assert.IsTrue(TFileEncoding.ParseCodePage('1252', mCodePage));
  Assert.AreEqual(1252, mCodePage);
  Assert.IsFalse(TFileEncoding.ParseCodePage('latin9', mCodePage));
  Assert.IsFalse(TFileEncoding.ParseCodePage('932', mCodePage));
  Assert.IsFalse(TFileEncoding.ParseCodePage('', mCodePage));
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
  mFileName: string;
  mFormat: TFileFormat;
  mText: string;
begin
  mFileName := FFolder + 'Unit1.pas';
  WriteBytes(mFileName, Bytes([$61, $0D, $0A]));
  TFileEncodingDefaults.SetFolder(FFolder, 1250);
  mText := TFileEncoding.LoadFromFile(mFileName, mFormat);
  Assert.AreEqual(1250, mFormat.CodePage);
  TFileEncoding.SaveToFile(mFileName, mText + #$0160, mFormat);
  Assert.IsTrue(SameBytes(Bytes([$61, $0D, $0A, $8A]), ReadAll(mFileName)));
end;

procedure TFileEncodingDefaultTests.LoadTextAndLinesDetectEncoding;
var
  mFileName: string;
  mLines: TArray<string>;
begin
  mFileName := FFolder + 'Projekt.dproj';
  // UTF-8 ohne BOM: TFile.ReadAllText läse "Ã¤".
  WriteBytes(mFileName, Bytes([$C3, $A4, $0D, $0A, $62, $0D, $0A]));
  Assert.AreEqual(#$E4#13#10'b'#13#10, TFileEncoding.LoadText(mFileName));
  mLines := TFileEncoding.LoadLines(mFileName);
  Assert.AreEqual(2, Integer(Length(mLines)));
  Assert.AreEqual(#$E4, mLines[0]);
  Assert.AreEqual('b', mLines[1]);
  // ANSI (ungültiges UTF-8) bleibt ANSI.
  WriteBytes(mFileName, Bytes([$E4, $0A, $62]));
  mLines := TFileEncoding.LoadLines(mFileName);
  Assert.AreEqual(2, Integer(Length(mLines)));
  Assert.AreEqual(#$E4, mLines[0]);
  WriteBytes(mFileName, nil);
  Assert.AreEqual(0, Integer(Length(TFileEncoding.LoadLines(mFileName))));
end;

procedure TFileEncodingDefaultTests.TextFormRoundTripKeepsBytes;
const
  cForm = 'object Form1: TForm1'#13#10'  Caption = ''Gr''#246#223''e'''#13#10'end'#13#10;
var
  mFileName: string;
  mFormat: TFileFormat;
  mSource: TBytes;
begin
  // Text-DFM mit #-Zeichen: reines ASCII, bleibt beim Zurückschreiben Byte für Byte gleich.
  mFileName := FFolder + 'Unit1.dfm';
  mSource := TEncoding.ASCII.GetBytes(cForm);
  WriteBytes(mFileName, mSource);
  TFileEncodingDefaults.SetFolder(FFolder, 1250);
  TFileEncoding.SaveToFile(mFileName, TFileEncoding.LoadFromFile(mFileName, mFormat), mFormat);
  Assert.IsTrue(SameBytes(mSource, ReadAll(mFileName)));
end;

procedure TFileEncodingDefaultTests.DetectsBinaryForms;
begin
  Assert.IsTrue(TFileEncoding.IsBinaryForm(Bytes([Ord('T'), Ord('P'), Ord('F'), Ord('0'), 6])));
  Assert.IsTrue(TFileEncoding.IsBinaryForm(Bytes([$FF, $0A, $00, $54])));
  Assert.IsFalse(TFileEncoding.IsBinaryForm(Bytes([Ord('o'), Ord('b'), Ord('j')])));
  Assert.IsFalse(TFileEncoding.IsBinaryForm(nil));
  Assert.IsFalse(TFileEncoding.IsBinaryFormFile(FFolder + 'fehlt.dfm'));
end;

procedure TFileEncodingDefaultTests.DetectsUtf32Bom;
begin
  Assert.IsTrue(TFileEncoding.HasUtf32Bom(Bytes([$FF, $FE, 0, 0, Ord('u'), 0, 0, 0])));
  Assert.IsTrue(TFileEncoding.HasUtf32Bom(Bytes([0, 0, $FE, $FF, 0, 0, 0, Ord('u')])));
  // UTF-16 LE mit BOM und einem Zeichen, dessen hohes Byte nicht 0 ist.
  Assert.IsFalse(TFileEncoding.HasUtf32Bom(Bytes([$FF, $FE, Ord('u'), 0])));
  Assert.IsFalse(TFileEncoding.HasUtf32Bom(Bytes([$FF, $FE, 0])));
  Assert.IsFalse(TFileEncoding.HasUtf32Bom(nil));
end;

procedure TFileEncodingDefaultTests.NeverOverwritesBinaryForm;
var
  mFileName: string;
  mSource: TBytes;
  mRaised: Boolean;
begin
  mFileName := FFolder + 'Unit2.dfm';
  mSource := Bytes([Ord('T'), Ord('P'), Ord('F'), Ord('0'), 6, Ord('T')]);
  WriteBytes(mFileName, mSource);
  Assert.IsTrue(TFileEncoding.IsBinaryFormFile(mFileName));
  mRaised := False;
  try
    TFileEncoding.SaveToFile(mFileName, 'object Form1: TForm1'#13#10'end', TFileFormat.Create(TFileEncodingKind.Utf8,
      TLineBreakStyle.CRLF));
  except
    on EFileEncodingError do
      mRaised := True;
  end;
  Assert.IsTrue(mRaised);
  Assert.IsTrue(SameBytes(mSource, ReadAll(mFileName)));
end;

procedure TFileEncodingDefaultTests.AnsiDefaultUnitKeepsBytesOutsideEdit;
var
  mFileName: string;
  mFormat: TFileFormat;
  mText: string;
begin
  // Abnahme #121: Unit in Codepage 1250 ohne BOM ("Š" = $8A, "č" = $E8), Vorgabe 1250, Code-Aktion
  // ersetzt "x" durch "y"; alles andere bleibt Byte für Byte gleich.
  mFileName := FFolder + 'Unit3.pas';
  WriteBytes(mFileName, Bytes([$8A, $0D, $0A, Ord('x'), $0D, $0A, $E8]));
  TFileEncodingDefaults.SetFolder(FFolder, 1250);
  mText := TFileEncoding.LoadFromFile(mFileName, mFormat);
  Assert.AreEqual(#$0160#13#10'x'#13#10#$010D, mText);
  TFileEncoding.SaveToFile(mFileName, StringReplace(mText, 'x', 'y', []), mFormat);
  Assert.IsTrue(SameBytes(Bytes([$8A, $0D, $0A, Ord('y'), $0D, $0A, $E8]), ReadAll(mFileName)));
end;

procedure TFileEncodingDefaultTests.TextFormKeepsCharacterCodesAfterEdit;
const
  cForm = 'object Form1: TForm1'#13#10'  object Button1: TButton'#13#10'    Caption = ''M''#228''rz'''#13#10 +
    '  end'#13#10'end'#13#10;
var
  mFileName: string;
  mFormat: TFileFormat;
begin
  // Umbenennen in einer Text-DFM: "#228" bleibt in dieser Schreibweise stehen.
  mFileName := FFolder + 'Unit4.dfm';
  WriteBytes(mFileName, TEncoding.ASCII.GetBytes(cForm));
  TFileEncoding.SaveToFile(mFileName, StringReplace(TFileEncoding.LoadFromFile(mFileName, mFormat), 'Button1',
    'btnOk', []), mFormat);
  Assert.IsTrue(SameBytes(TEncoding.ASCII.GetBytes(StringReplace(cForm, 'Button1', 'btnOk', [])), ReadAll(mFileName)));
end;

procedure TFileEncodingDefaultTests.SurveySkipsBinaryFormsAndNamesCodePage;
var
  mSurvey: TEncodingSurvey;
begin
  mSurvey := Default(TEncodingSurvey);
  mSurvey.AnsiCodePage := 1250;
  mSurvey.Add(Bytes([Ord('T'), Ord('P'), Ord('F'), Ord('0'), $E4]));
  Assert.AreEqual(0, mSurvey.Ansi + mSurvey.Utf8 + mSurvey.Ascii);
  mSurvey.Add(Bytes([$61, $E4]));
  Assert.AreEqual('1 Datei in Windows-1250', mSurvey.Describe);
  mSurvey.AnsiCodePage := TFileEncoding.cUtf8CodePage;
  Assert.AreEqual('1 Datei in Windows-1252', mSurvey.Describe);
end;

procedure TFileEncodingTests.InvalidUtf8GivesLineAndColumn;
var
  mData: TBytes;
  mFormat: TFileFormat;
  mInvalid: TArray<TInvalidUtf8>;
begin
  // BOM, "a" LF, Emoji (vier Bytes, zwei UTF-16-Einheiten), zu kurzes E2 82, "b", einzelnes $FF.
  mData := Bytes([$EF, $BB, $BF, Ord('a'), 10, $F0, $9F, $98, $80, $E2, $82, Ord('b'), $FF]);
  mFormat := TFileFormat.Create(TFileEncodingKind.Utf8Bom, TLineBreakStyle.LF);
  mInvalid := TFileEncoding.InvalidUtf8(mData, mFormat);
  Assert.AreEqual(2, Integer(Length(mInvalid)));
  Assert.AreEqual(1, mInvalid[0].Position.Line);
  Assert.AreEqual(2, mInvalid[0].Position.Character);
  Assert.AreEqual(9, mInvalid[0].ByteOffset);
  Assert.AreEqual($E2, Integer(mInvalid[0].Value));
  Assert.AreEqual(4, mInvalid[1].Position.Character);
  // Gelesen als ANSI: ein Zeichen je Byte. "ä" und "ö" dazu, damit die gültigen Folgen überwiegen (#1327).
  mData := Bytes([Ord('a'), 10, $F0, $9F, $98, $80, $C3, $A4, $C3, $B6, $E2, $82, Ord('b'), $FF]);
  mFormat := TFileFormat.Create(TFileEncodingKind.Ansi1252, TLineBreakStyle.LF);
  mInvalid := TFileEncoding.InvalidUtf8(mData, mFormat);
  Assert.AreEqual(2, Integer(Length(mInvalid)));
  Assert.AreEqual(8, mInvalid[0].Position.Character);
  Assert.AreEqual(11, mInvalid[1].Position.Character);
end;

procedure TFileEncodingTests.InvalidUtf8InPlainAnsiIsEmpty;
var
  mFormat: TFileFormat;
begin
  mFormat := TFileFormat.Create(TFileEncodingKind.Ansi1252, TLineBreakStyle.CRLF);
  Assert.AreEqual(0, Integer(Length(TFileEncoding.InvalidUtf8(Bytes([Ord('a'), $E4, Ord('b')]), mFormat))));
end;

procedure TFileEncodingDefaultTests.LoadsThroughPlatformReader;
var
  mAsked: string;
  mFormat: TFileFormat;
begin
  TFileEncoding.Reader :=
    function(const AFileName: string): TBytes
    begin
      mAsked := AFileName;
      Result := Bytes([$61, $C3, $A4]);
    end;
  // Die Datei gibt es nicht: Der Text kommt allein vom Leser.
  Assert.AreEqual('aä', TFileEncoding.LoadFromFile(FFolder + 'Fehlt.pas', mFormat));
  Assert.AreEqual(FFolder + 'Fehlt.pas', mAsked);
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Utf8, mFormat.Encoding);
  TFileEncoding.Reader := nil;
  Assert.WillRaise(
    procedure
    begin
      TFileEncoding.ReadAllBytes(FFolder + 'Fehlt.pas');
    end, EFOpenError);
end;

procedure TFileEncodingDefaultTests.ReadsWhileSomeoneWrites;
var
  mFileName: string;
  mWriter: TFileStream;
begin
  mFileName := FFolder + 'Offen.pas';
  WriteBytes(mFileName, Bytes([$61]));
  // Offen zum Schreiben, Lesen und Schreiben geteilt. Vorher teilte LoadFromFile nur Lesen und scheiterte
  // daran; umgekehrt scheiterte ein Schreiber, solange der Server las.
  mWriter := TFileStream.Create(mFileName, fmOpenReadWrite or fmShareDenyNone);
  try
    Assert.IsTrue(SameBytes(Bytes([$61]), TFileEncoding.ReadAllBytes(mFileName)));
  finally
    mWriter.Free;
  end;
end;

procedure TFileEncodingTests.AnsiWithStrayUtf8PairStaysAnsi;
var
  mAnsi, mUtf8, mWithBom: TBytes;
  mFormat: TFileFormat;
  mText: string;
begin
  // "// Grüße aus Köln, Zeichen °" mit Umlauten in Windows-1252 und "°" als UTF-8 (C2 B0), wie F15.
  mAnsi := TEncoding.ASCII.GetBytes('// Gr') + Bytes([$FC, $DF]) + TEncoding.ASCII.GetBytes('e aus K') + Bytes([$F6]) +
    TEncoding.ASCII.GetBytes('ln, Zeichen ') + Bytes([$C2, $B0, 13, 10, Ord('S'), Ord('='), $E4, $F6, $FC]);
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Ansi1252, TFileEncoding.DetectEncoding(mAnsi), 'ANSI');
  mText := TFileEncoding.Decode(mAnsi, mFormat);
  Assert.AreEqual('// Grüße aus Köln, Zeichen Â°'#13#10'S=äöü', mText);
  Assert.AreEqual(0, Integer(Length(TFileEncoding.InvalidUtf8(mAnsi, mFormat))), 'Fehlstellen');
  // Derselbe Text ganz in UTF-8 ohne BOM: UTF-8.
  mUtf8 := TEncoding.UTF8.GetBytes('// Grüße aus Köln, Zeichen °'#13#10'S=äöü');
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Utf8,
    TFileEncoding.DetectEncoding(mUtf8, TFileEncodingKind.Ansi1252), 'UTF-8');
  // Mit BOM entscheidet die BOM, auch wenn danach ANSI-Bytes stehen.
  mWithBom := Bytes([$EF, $BB, $BF]) + mAnsi;
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Utf8Bom, TFileEncoding.DetectEncoding(mWithBom), 'BOM');
  TFileEncoding.Decode(mWithBom, mFormat);
  Assert.AreEqual(6, Integer(Length(TFileEncoding.InvalidUtf8(mWithBom, mFormat))), 'Fehlstellen nach BOM');
end;

procedure TFileEncodingTests.MostlyUtf8WithStrayByteIsDamagedUtf8;
var
  mData: TBytes;
  mFormat: TFileFormat;
  mInvalid: TArray<TInvalidUtf8>;
begin
  // "äöü" als UTF-8 und ein eingestreutes "ß" in Windows-1252 ($DF): Die Datei ist UTF-8 mit einer Fehlstelle.
  mData := Bytes([$C3, $A4, $C3, $B6, $C3, $BC, Ord(' '), $DF, Ord('!')]);
  TFileEncoding.Decode(mData, mFormat);
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Ansi1252, mFormat.Encoding, 'dcc liest sie als ANSI');
  mInvalid := TFileEncoding.InvalidUtf8(mData, mFormat);
  Assert.AreEqual(1, Integer(Length(mInvalid)));
  Assert.AreEqual(7, mInvalid[0].ByteOffset);
  Assert.AreEqual($DF, Integer(mInvalid[0].Value));
end;

procedure TFileEncodingTests.EncodeKeepingLineBreaksKeepsMixed;
var
  mFormat: TFileFormat;
  mBytes: TBytes;
begin
  mFormat := TFileFormat.Create(TFileEncodingKind.Utf8Bom, TLineBreakStyle.CRLF);
  mBytes := TFileEncoding.EncodeKeepingLineBreaks('a'#10'b'#13#10'ä', mFormat);
  Assert.AreEqual(10, Integer(Length(mBytes)));
  Assert.AreEqual(Integer($EF), Integer(mBytes[0]));
  Assert.AreEqual(Integer(10), Integer(mBytes[4]));
  Assert.AreEqual(Integer(13), Integer(mBytes[6]));
  Assert.AreEqual(11, Integer(Length(TFileEncoding.Encode('a'#10'b'#13#10'ä', mFormat))));
end;

initialization
  TDUnitX.RegisterTestFixture(TFileEncodingTests);
  TDUnitX.RegisterTestFixture(TFileEncodingDefaultTests);

end.
