unit Atlas.Core.Assistants.Instructions.Tests;

// Tests für die Anweisungsdateien für KI-Assistenten im Plugin (#2615): Argumente des Serverbefehls, Antwort lesen,
// Vergleich alt/neu für die Meldungsansicht, atlas.json erkennen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasInstructionsTests = class
  public
    [Test]
    procedure ArgumentsCarryUriAndWrite;
    [Test]
    procedure ParsesAnswer;
    [Test]
    procedure DiffNamesOnlyChangedLines;
    [Test]
    procedure DiffOfNewSectionAddsEveryLine;
    [Test]
    procedure RecognizesConfigFile;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Assistants.Instructions;

{ TAtlasInstructionsTests }

procedure TAtlasInstructionsTests.ArgumentsCarryUriAndWrite;
var
  mJson: TJSONValue;
  mArguments: TJSONObject;
begin
  mJson := TJSONObject.ParseJSONValue(TAtlasInstructions.Arguments('file:///c%3A/P/atlas.json', True));
  try
    Assert.IsTrue(mJson is TJSONArray);
    mArguments := TJSONArray(mJson).Items[0] as TJSONObject;
    Assert.AreEqual('file:///c%3A/P/atlas.json', mArguments.GetValue<string>('uri'));
    Assert.IsTrue(mArguments.GetValue<Boolean>('write'));
  finally
    mJson.Free;
  end;
end;

procedure TAtlasInstructionsTests.ParsesAnswer;
var
  mAnswer: TJSONValue;
  mFiles: TArray<TAtlasInstructionsFile>;
begin
  mAnswer := TJSONObject.ParseJSONValue('{"files": [{"file": "AGENTS.md", "state": "stale", "old": "a", ' +
    '"new": "b", "written": false, "error": ""}, {"file": "docs/X.md", "state": "missing", "written": true}], ' +
    '"stale": 1}');
  try
    mFiles := TAtlasInstructions.Parse(mAnswer);
  finally
    mAnswer.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mFiles)));
  Assert.AreEqual('AGENTS.md', mFiles[0].FileName);
  Assert.AreEqual('b', mFiles[0].NewSection);
  Assert.IsTrue(mFiles[0].Outdated, 'veraltet und nicht geschrieben');
  Assert.IsFalse(mFiles[1].Outdated, 'geschrieben');
  Assert.AreEqual(0, Integer(Length(TAtlasInstructions.Parse(nil))));
  mFiles := nil;
end;

procedure TAtlasInstructionsTests.DiffNamesOnlyChangedLines;
var
  mLines: TArray<string>;
begin
  mLines := TAtlasInstructions.Diff('Kopf'#10'- Methode: höchstens 60'#10'Ende',
    'Kopf'#10'- Methode: höchstens 61'#10'Ende'#10'Neu');
  Assert.AreEqual(3, Integer(Length(mLines)));
  Assert.AreEqual('- - Methode: höchstens 60', mLines[0]);
  Assert.AreEqual('+ - Methode: höchstens 61', mLines[1]);
  Assert.AreEqual('+ Neu', mLines[2]);
  Assert.AreEqual(0, Integer(Length(TAtlasInstructions.Diff('a'#13#10'b', 'a'#10'b'))), 'Zeilenenden zählen nicht');
  mLines := nil;
end;

procedure TAtlasInstructionsTests.DiffOfNewSectionAddsEveryLine;
var
  mLines: TArray<string>;
begin
  mLines := TAtlasInstructions.Diff('', 'a'#10'b');
  Assert.AreEqual(2, Integer(Length(mLines)));
  Assert.AreEqual('+ a', mLines[0]);
  Assert.AreEqual('+ b', mLines[1]);
  mLines := nil;
end;

procedure TAtlasInstructionsTests.RecognizesConfigFile;
begin
  Assert.IsTrue(TAtlasInstructions.IsConfigFile('C:\Projekt\Atlas.json'));
  Assert.IsTrue(TAtlasInstructions.IsConfigFile('/home/p/atlas.json'));
  Assert.IsFalse(TAtlasInstructions.IsConfigFile('C:\Projekt\atlas-plugin.json'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasInstructionsTests);

end.
