unit Atlas.Common.Mutation.Report.Tests;

// Tests der Ausgabe der Mutanten (#1460): JSON mit Zeilen ab 1 und Zahl je
// Operator, Markdown-Tabelle, Patch mit einem Diff je Mutant und der Text
// ohne Mutanten.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Mutation.Contract;

type
  [TestFixture]
  TMutationReportTests = class
  private
    FText: string;
    FMutants: TArray<TMutant>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure JsonHasPositionsFromOne;
    [Test]
    procedure JsonCountsPerOperator;
    [Test]
    procedure MarkdownTable;
    [Test]
    procedure MarkdownWithoutMutants;
    [Test]
    procedure PatchPerMutant;
    [Test]
    procedure DescribeShortensLongText;
    [Test]
    procedure ParsesFormats;
    [Test]
    procedure RenderMatchesSingleOutputs;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Mutation.Generator,
  Atlas.Common.Mutation.Report;

const
  cLf = #10;

{ TMutationReportTests }

procedure TMutationReportTests.Setup;
var
  mOptions: TMutationOptions;
begin
  FText := 'unit Preise;' + cLf + 'implementation' + cLf + 'function Satz(AMenge: Integer): Integer;' + cLf +
    'begin' + cLf + '  if AMenge >= 100 then' + cLf + '    Result := 5' + cLf + '  else' + cLf +
    '    Result := 0;' + cLf + 'end;' + cLf + 'end.';
  mOptions := TMutationOptions.Default;
  mOptions.Operators := [TMutationOperator.Boundary, TMutationOperator.RemoveStatement];
  FMutants := TMutationGenerator.ForText(FText, mOptions);
end;

procedure TMutationReportTests.TearDown;
begin
  FText := '';
  FMutants := nil;
end;

procedure TMutationReportTests.JsonHasPositionsFromOne;
var
  mJson: string;
begin
  mJson := TMutationReport.Json('Src/Preise.pas', FMutants);
  Assert.StartsWith('{"format": 1, "file": "Src/Preise.pas", "count": 3', mJson);
  Assert.Contains(mJson, '"id": 1, "operator": "boundary", "routine": "Satz", "line": 5, "character": 13, ' +
    '"endLine": 5, "endCharacter": 15');
  Assert.Contains(mJson, '"original": ">=", "replacement": ">"');
end;

procedure TMutationReportTests.JsonCountsPerOperator;
begin
  Assert.Contains(TMutationReport.Json('P.pas', FMutants), '"operators": {"boundary": 1, "statement": 2}');
  Assert.Contains(TMutationReport.Json('P.pas', nil), '"count": 0, "operators": {}, "mutants": []');
end;

procedure TMutationReportTests.MarkdownTable;
var
  mText: string;
begin
  mText := TMutationReport.Markdown('Preise.pas', FMutants);
  Assert.Contains(mText, 'boundary 1, statement 2');
  Assert.Contains(mText, '| 1 | 5 | Satz | boundary |');
  Assert.Contains(mText, '| 3 | 8 | Satz | statement |');
end;

procedure TMutationReportTests.MarkdownWithoutMutants;
var
  mText: string;
begin
  mText := TMutationReport.Markdown('Leer.pas', nil);
  Assert.DoesNotContain(mText, '| ---');
  Assert.AreEqual(4, Integer(Length(mText.Split([#10]))));
end;

procedure TMutationReportTests.PatchPerMutant;
var
  mPatch: string;
begin
  mPatch := TMutationReport.Patch('Src\Preise.pas', FText, FMutants);
  Assert.Contains(mPatch, '# Mutant 1 (boundary, Satz)');
  Assert.Contains(mPatch, '--- a/Src/Preise.pas');
  Assert.Contains(mPatch, '+++ b/Src/Preise.pas');
  Assert.Contains(mPatch, '-  if AMenge >= 100 then');
  Assert.Contains(mPatch, '+  if AMenge > 100 then');
  Assert.Contains(mPatch, '# Mutant 3 (statement, Satz)');
  Assert.AreEqual(3, Integer(Length(mPatch.Split(['# Mutant '])) - 1));
end;

procedure TMutationReportTests.DescribeShortensLongText;
var
  mMutant: TMutant;
begin
  mMutant := Default(TMutant);
  mMutant.Original := 'Foo(' + StringOfChar('x', 100) + ')';
  Assert.IsTrue(Length(TMutationReport.Describe(mMutant)) < 90);
  mMutant.Original := 'A' + #13#10 + '    + B';
  mMutant.Replacement := 'A';
  Assert.Contains(TMutationReport.Describe(mMutant), '"A + B"');
end;

procedure TMutationReportTests.ParsesFormats;
var
  mFormat: TMutationOutputFormat;
begin
  Assert.IsTrue(TMutationReport.TryParseFormat('', mFormat));
  Assert.AreEqual<TMutationOutputFormat>(TMutationOutputFormat.Markdown, mFormat);
  Assert.IsTrue(TMutationReport.TryParseFormat('Text', mFormat));
  Assert.AreEqual<TMutationOutputFormat>(TMutationOutputFormat.Markdown, mFormat);
  Assert.IsTrue(TMutationReport.TryParseFormat('JSON', mFormat));
  Assert.AreEqual<TMutationOutputFormat>(TMutationOutputFormat.Json, mFormat);
  Assert.IsTrue(TMutationReport.TryParseFormat('diff', mFormat));
  Assert.AreEqual<TMutationOutputFormat>(TMutationOutputFormat.Patch, mFormat);
  Assert.IsTrue(TMutationReport.TryParseFormat('patch', mFormat));
  Assert.IsFalse(TMutationReport.TryParseFormat('sarif', mFormat));
end;

procedure TMutationReportTests.RenderMatchesSingleOutputs;
var
  mOptions: TMutationOptions;
begin
  mOptions := TMutationOptions.Default;
  mOptions.Operators := [TMutationOperator.Boundary, TMutationOperator.RemoveStatement];
  Assert.AreEqual(TMutationReport.Json('P.pas', FMutants), TMutationReport.Render('P.pas', FText, mOptions,
    TMutationOutputFormat.Json));
  Assert.AreEqual(TMutationReport.Markdown('P.pas', FMutants), TMutationReport.Render('P.pas', FText, mOptions,
    TMutationOutputFormat.Markdown));
  Assert.AreEqual(TMutationReport.Patch('P.pas', FText, FMutants), TMutationReport.Render('P.pas', FText, mOptions,
    TMutationOutputFormat.Patch));
end;

initialization
  TDUnitX.RegisterTestFixture(TMutationReportTests);

end.
