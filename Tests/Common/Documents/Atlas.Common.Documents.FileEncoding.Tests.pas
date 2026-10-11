unit Atlas.Common.Documents.FileEncoding.Tests;

interface

uses
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
  end;

implementation

uses
  System.SysUtils,
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

initialization
  TDUnitX.RegisterTestFixture(TFileEncodingTests);

end.
