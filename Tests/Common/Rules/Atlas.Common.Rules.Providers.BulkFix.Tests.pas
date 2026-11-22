unit Atlas.Common.Rules.Providers.BulkFix.Tests;

// Tests des Anbieters der Sammelkorrektur (#1352) für andere Features: korrigiert Texte, ohne zu schreiben, liefert
// Diff mit / im Pfad und beide Zusammenfassungen; eine niedrigere Untergrenze als fix.minConfidence lehnt er ab.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleBulkFixProviderTests = class
  public
    [Test]
    procedure FixesTextsAndDiffs;
    [Test]
    procedure LeavesCleanFileUnchanged;
    [Test]
    procedure RefusesLowerConfidence;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Contract.Api,
  Atlas.Common.Rules.Providers.BulkFix;

const
  cAssignedFree = 'unit U;'#10#10'interface'#10#10'uses'#10'  System.Classes;'#10#10'implementation'#10#10 +
    'procedure Weg(AList: TStringList);'#10'begin'#10'  if Assigned(AList) then'#10'    AList.Free;'#10'end;'#10#10 +
    'end.'#10;
  cClean = 'unit V;'#10#10'interface'#10#10'implementation'#10#10'end.'#10;

function Input(const AFileName, ARelativePath, AText: string): TRuleBulkFixInput;
begin
  Result := Default(TRuleBulkFixInput);
  Result.FileName := AFileName;
  Result.RelativePath := ARelativePath;
  Result.Text := AText;
end;

function Provider: IRuleBulkFix;
begin
  Result := TRuleBulkFixProvider.Create(BuiltinRules, nil, nil);
end;

{ TRuleBulkFixProviderTests }

procedure TRuleBulkFixProviderTests.FixesTextsAndDiffs;
var
  mRun: TRuleBulkFixRun;
  mError: string;
begin
  Assert.IsTrue(Provider.Run([Input('C:\P\Src\U.pas', 'Src\U.pas', cAssignedFree)], ['redundant-assigned-free'],
    '', TServerSettings.Default, mRun, mError), mError);
  Assert.AreEqual(1, Integer(Length(mRun.Files)));
  Assert.AreEqual('C:\P\Src\U.pas', mRun.Files[0].FileName);
  Assert.AreEqual(cAssignedFree, mRun.Files[0].OldText);
  Assert.IsTrue(mRun.Files[0].Changed);
  Assert.IsFalse(Pos('Assigned', mRun.Files[0].NewText) > 0, mRun.Files[0].NewText);
  Assert.Contains(mRun.Files[0].Diff, '--- a/Src/U.pas');
  Assert.Contains(mRun.Files[0].Diff, '-  if Assigned(AList) then');
  Assert.Contains(mRun.PreviewSummary, 'Vorschau: 1 Korrekturen in 1 Dateien');
  Assert.Contains(mRun.WrittenSummary, '1 Korrekturen in 1 Dateien geschrieben');
end;

procedure TRuleBulkFixProviderTests.LeavesCleanFileUnchanged;
var
  mRun: TRuleBulkFixRun;
  mError: string;
begin
  Assert.IsTrue(Provider.Run([Input('C:\P\V.pas', 'V.pas', cClean)], ['all'], '', TServerSettings.Default, mRun,
    mError), mError);
  Assert.AreEqual(1, Integer(Length(mRun.Files)));
  Assert.IsFalse(mRun.Files[0].Changed);
  Assert.AreEqual(cClean, mRun.Files[0].NewText);
  Assert.AreEqual('', mRun.Files[0].Diff);
end;

procedure TRuleBulkFixProviderTests.RefusesLowerConfidence;
var
  mRun: TRuleBulkFixRun;
  mError: string;
begin
  Assert.IsFalse(Provider.Run([Input('C:\P\U.pas', 'U.pas', cAssignedFree)], ['redundant-assigned-free'], 'medium',
    TServerSettings.Default, mRun, mError));
  Assert.Contains(mError, 'fix.minConfidence');
  Assert.AreEqual(0, Integer(Length(mRun.Files)));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleBulkFixProviderTests);

end.
