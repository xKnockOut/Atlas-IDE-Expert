unit Atlas.Core.Text.Agreement.Tests;

// Server und Plugin entscheiden gleich (ADR 0012, D-01 bis D-05): Kodierung,
// unscharfe Treffer der Vervollständigung und Anonymisierung im Fehlerbericht.
// Beide Seiten nutzen Atlas.Text; diese Tests halten fest, dass die Hüllen
// darum herum nichts Eigenes mehr entscheiden.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEncodingAgreementTests = class
  public
    /// <summary>Gleiche Kodierung für BOM, gültiges, überlanges und ungültiges UTF-8 und ANSI.</summary>
    [Test]
    procedure SameEncodingForSamples;
    [Test]
    procedure SameCodePages;
    [Test]
    procedure SameBinaryForms;
  end;

  [TestFixture]
  TFuzzyCompletionAgreementTests = class
  public
    /// <summary>Was der Server liefert, filtert das Plugin beim Weitertippen nicht weg, und umgekehrt.</summary>
    [Test]
    procedure SameMatches;
  end;

  [TestFixture]
  TBugReportAgreementTests = class
  public
    [Test]
    procedure SameAnonymizedLines;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Lsp.FuzzyMatch,
  Atlas.Common.Diagnostics.BugReport,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Files.Format,
  Atlas.Core.Completion.Matching,
  Atlas.Core.Diagnostics.BugReport;

function ServerName(AKind: TFileEncodingKind): string;
begin
  case AKind of
    TFileEncodingKind.Utf8:
      Result := 'utf8';
    TFileEncodingKind.Utf8Bom:
      Result := 'utf8bom';
    TFileEncodingKind.Utf16LE:
      Result := 'utf16le';
    TFileEncodingKind.Utf16BE:
      Result := 'utf16be';
  else
    Result := 'ansi';
  end;
end;

function FormatName(AKind: TAtlasFileEncoding): string;
begin
  case AKind of
    TAtlasFileEncoding.Utf8:
      Result := 'utf8';
    TAtlasFileEncoding.Utf8Bom:
      Result := 'utf8bom';
    TAtlasFileEncoding.Utf16LE:
      Result := 'utf16le';
    TAtlasFileEncoding.Utf16BE:
      Result := 'utf16be';
  else
    Result := 'ansi';
  end;
end;

function PluginName(AKind: TAtlasTextEncoding): string;
begin
  case AKind of
    TAtlasTextEncoding.Utf8:
      Result := 'utf8';
    TAtlasTextEncoding.Utf8Bom:
      Result := 'utf8bom';
    TAtlasTextEncoding.Utf16LE:
      Result := 'utf16le';
    TAtlasTextEncoding.Utf16BE:
      Result := 'utf16be';
  else
    Result := 'ansi';
  end;
end;

{ TEncodingAgreementTests }

procedure TEncodingAgreementTests.SameEncodingForSamples;
var
  Samples: TArray<TBytes>;
  Sample: TBytes;
  Index: Integer;
begin
  Samples := [
    TBytes.Create(Ord('a'), Ord('b')),
    TBytes.Create($EF, $BB, $BF, Ord('a')),
    TBytes.Create($FF, $FE, Ord('a'), 0),
    TBytes.Create($FE, $FF, 0, Ord('a')),
    TBytes.Create(Ord('a'), $C3, $A4),
    // Überlang ("/" als zwei Bytes), Surrogat, über U+10FFFF, abgeschnitten, ANSI-Umlaut.
    TBytes.Create($C0, $AF),
    TBytes.Create($E0, $80, $AF),
    TBytes.Create($ED, $A0, $80),
    TBytes.Create($F4, $90, $80, $80),
    TBytes.Create(Ord('a'), $C3),
    TBytes.Create(Ord('a'), $E4, Ord('b'))];
  for Index := 0 to High(Samples) do
  begin
    Sample := Samples[Index];
    Assert.AreEqual(ServerName(TFileEncoding.DetectEncoding(Sample)),
      PluginName(TAtlasTextFile.Decode(Sample).Encoding), 'TextFile, Probe ' + IntToStr(Index));
    Assert.AreEqual(ServerName(TFileEncoding.DetectEncoding(Sample)),
      FormatName(TAtlasFileFormats.Detect(Sample).Encoding), 'Format, Probe ' + IntToStr(Index));
  end;
end;

procedure TEncodingAgreementTests.SameCodePages;
var
  Text: string;
  ServerCodePage, PluginCodePage: Integer;
  ServerOk, PluginOk: Boolean;
begin
  for Text in TArray<string>.Create('utf-8', 'UTF8', '65001', '1250', 'cp1252', 'windows-1251', ' 28591 ', '932',
    'shift_jis', '', 'cp', '1200') do
  begin
    ServerOk := TFileEncoding.ParseCodePage(Text, ServerCodePage);
    PluginOk := TAtlasTextFile.ParseCodePage(Text, PluginCodePage);
    Assert.AreEqual(ServerOk, PluginOk, Text);
    Assert.AreEqual(ServerCodePage, PluginCodePage, Text);
  end;
end;

procedure TEncodingAgreementTests.SameBinaryForms;
var
  Sample: TBytes;
begin
  for Sample in TArray<TBytes>.Create(TBytes.Create(Ord('T'), Ord('P'), Ord('F'), Ord('0')),
    TBytes.Create($FF, $0A, $00, 1), TBytes.Create(Ord('o'), Ord('b'), Ord('j')), nil) do
    Assert.AreEqual(TFileEncoding.IsBinaryForm(Sample), TAtlasTextFile.IsBinaryForm(Sample));
end;

{ TFuzzyCompletionAgreementTests }

procedure TFuzzyCompletionAgreementTests.SameMatches;
const
  Pairs: array[0..15, 0..1] of string = (
    ('stl', 'TStringList'), ('TBB', 'TBButton'), ('gth', 'GetTypeHierarchy'), ('mln', 'my_long_name'),
    ('liste', 'TListe'), ('liste', 'ListeLeeren'), ('zlr', 'Zaehler'), ('myLis', 'ERROR_TOO_MANY_LINKS'),
    ('stlcr', 'TStringList.Create'), ('b2s', 'Base2String'), ('xyz', 'TStringList'), ('gr', 'TStringList'),
    ('ehl', 'Zaehler'), ('ic', 'IntToStr'), ('its', 'IntToStr'), ('i2s', 'Int2Str'));
var
  Index: Integer;
  ServerMatches, PluginMatches: Boolean;
begin
  for Index := Low(Pairs) to High(Pairs) do
  begin
    ServerMatches := TFuzzyMatch.CompletionScore(Pairs[Index, 1], Pairs[Index, 0]) <> TFuzzyMatch.NoMatch;
    PluginMatches := TAtlasCompletionMatcher.Score(Pairs[Index, 0], Pairs[Index, 1]) <>
      TAtlasCompletionMatcher.NoMatch;
    Assert.AreEqual(ServerMatches, PluginMatches, Pairs[Index, 0] + ' / ' + Pairs[Index, 1]);
  end;
end;

{ TBugReportAgreementTests }

procedure TBugReportAgreementTests.SameAnonymizedLines;
var
  Line: string;
  Roots, Identity: TArray<string>;
begin
  Roots := ['C:\Projekte\Atlas'];
  Identity := ['marco', 'WERKBANK'];
  for Line in TArray<string>.Create('Öffne C:\Projekte\Atlas\Src\A.pas',
    'URI file:///c%3A/Projekte/Atlas/B.pas geladen', 'Fehler in D:\Fremd\X.pas: "Wert" fehlt',
    'Benutzer marco auf WERKBANK', 'don''t touch \\server\share\c.pas', 'ohne alles') do
    Assert.AreEqual(TBugReport.AnonymizeLogLine(Line, Roots, Identity),
      TAtlasBugReport.AnonymizeLogLine(Line, Roots, Identity), Line);
end;

initialization
  TDUnitX.RegisterTestFixture(TEncodingAgreementTests);
  TDUnitX.RegisterTestFixture(TFuzzyCompletionAgreementTests);
  TDUnitX.RegisterTestFixture(TBugReportAgreementTests);

end.
