unit Shell.Linter.Baseline.Tests;

// Bekannte Kopien aus atlas-duplicates.json im Linter-Modus (#1895): duplicate-routine-body meldet bei --check eines
// Projekts keine Kopie, die die Baseline der wortgleichen Rümpfe schon führt. Die übrige Baseline (#97) prüft
// Shell.Linter.Parts.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLinterKnownCopiesTests = class
  private
    FFolder: string;
    function Path(const AName: string): string;
    procedure WriteFile(const AName, AText: string);
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    /// <summary>duplicate-routine-body schweigt für eine Routine, die mit ihrem Fingerabdruck in
    /// atlas-duplicates.json über dem Ordner steht; eine andere Routine und andere Regeln bleiben, ohne Baseline
    /// bis zum Stamm des Repositorys alles.</summary>
    [Test]
    procedure KnownCopiesHideOnlyRecordedCopies;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Metrics.DuplicateBodies,
  Atlas.Common.Metrics.DuplicateBaseline,
  Atlas.Common.Rules.Builtin.DuplicateBodies,
  Shell.Linter.Duplicates,
  Shell.Linter.Baseline,
  Atlas.Tests.TempFolder;

{ TLinterKnownCopiesTests }

function TLinterKnownCopiesTests.Path(const AName: string): string;
begin
  // Namen mit \ für alle Plattformen.
  Result := TPath.Combine(FFolder, StringReplace(AName, '\', PathDelim, [rfReplaceAll]));
end;

procedure TLinterKnownCopiesTests.WriteFile(const AName, AText: string);
begin
  ForceDirectories(ExtractFileDir(Path(AName)));
  TFile.WriteAllText(Path(AName), AText, TEncoding.UTF8);
end;

procedure TLinterKnownCopiesTests.SetUp;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'atlas-linter-copies-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FFolder);
end;

procedure TLinterKnownCopiesTests.TearDown;
begin
  TTestTempFolder.Remove(FFolder);
  FFolder := '';
end;

/// <summary>Treffer ARuleId am Kopf von ABody.</summary>
function FindingAt(const ARuleId: string; const ABody: TRoutineBody): TRuleFinding;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := ARuleId;
  Result.Range := ABody.HeaderRange;
end;

procedure TLinterKnownCopiesTests.KnownCopiesHideOnlyRecordedCopies;
const
  cUnit = 'unit A;'#13#10'interface'#13#10'type'#13#10'  TA = class'#13#10'    procedure Lauf;'#13#10 +
    '    procedure Neu;'#13#10'  end;'#13#10'implementation'#13#10'procedure TA.Lauf;'#13#10'begin'#13#10 +
    '  Lauf;'#13#10'end;'#13#10'procedure TA.Neu;'#13#10'begin'#13#10'  Neu;'#13#10'end;'#13#10'end.'#13#10;
var
  mBodies: TArray<TRoutineBody>;
  mBaseline: TDuplicateBaseline;
  mFindings, mKept: TArray<TRuleFinding>;
  mCopies: TLinterKnownCopies;
begin
  mBodies := TDuplicateBodies.ForText(cUnit);
  Assert.AreEqual(2, Integer(Length(mBodies)));
  ForceDirectories(Path('Repo\.git'));
  WriteFile('Repo\Pkg\A.pas', cUnit);
  mBaseline := Default(TDuplicateBaseline);
  SetLength(mBaseline.Groups, 1);
  mBaseline.Groups[0].Hash := mBodies[0].Hash;
  mBaseline.Groups[0].BodyLines := mBodies[0].BodyLines;
  mBaseline.Groups[0].Members := TArray<string>.Create('Pkg/A.pas:TA.Lauf', 'Pkg/B.pas:TB.Lauf');
  WriteFile('Repo\' + TLinterDuplicates.cBaselineName, mBaseline.ToJson);
  SetLength(mFindings, 3);
  mFindings[0] := FindingAt(cDuplicateRoutineBodyRuleId, mBodies[0]);
  mFindings[1] := FindingAt(cDuplicateRoutineBodyRuleId, mBodies[1]);
  mFindings[2] := FindingAt('unused-declaration', mBodies[0]);
  mCopies := TLinterKnownCopies.Find(Path('Repo\Pkg'));
  try
    mKept := mCopies.Filter(Path('Repo\Pkg\A.pas'), cUnit, mFindings);
  finally
    mCopies.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mKept)), 'nur TA.Lauf steht in der Baseline');
  Assert.AreEqual(mBodies[1].Line, mKept[0].Range.StartPos.Line + 1, 'TA.Neu bleibt');
  Assert.AreEqual('unused-declaration', mKept[1].RuleId);
  // Über dem Stamm des Repositorys wird nicht gesucht.
  ForceDirectories(Path('Repo\Pkg\.git'));
  mCopies := TLinterKnownCopies.Find(Path('Repo\Pkg'));
  try
    Assert.AreEqual(3, Integer(Length(mCopies.Filter(Path('Repo\Pkg\A.pas'), cUnit, mFindings))));
  finally
    mCopies.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLinterKnownCopiesTests);

end.
