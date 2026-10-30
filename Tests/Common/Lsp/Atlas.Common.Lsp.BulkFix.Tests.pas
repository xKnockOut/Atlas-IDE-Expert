unit Atlas.Common.Lsp.BulkFix.Tests;

// Tests für den Befehl atlas.server.fixFindings (#1352): Antwort mit
// Zusammenfassung, Diff und WorkspaceEdit je Datei, nur geänderte Dateien,
// Baseline-Treffer bleiben, Fehler bei fehlenden Regeln und zu niedriger
// Untergrenze.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspBulkFixTests = class
  public
    [Test]
    procedure AnswersWithDiffAndEdit;
    [Test]
    procedure UnchangedAndUnreadableFilesAreLeftOut;
    [Test]
    procedure BaselineFindingsStay;
    [Test]
    procedure RefusesMissingRulesAndLowerConfidence;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Baseline,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Lsp.BulkFix;

const
  cAssignedFree = 'unit U;'#13#10#13#10'interface'#13#10#13#10'uses'#13#10'  System.Classes;'#13#10#13#10 +
    'implementation'#13#10#13#10'procedure Weg(AList: TStringList);'#13#10'begin'#13#10 +
    '  if Assigned(AList) then'#13#10'    AList.Free;'#13#10'end;'#13#10#13#10'end.'#13#10;
  cClean = 'unit V;'#13#10#13#10'interface'#13#10#13#10'implementation'#13#10#13#10'end.'#13#10;

var
  Baseline: IRuleBaseline;

function Input(const AFileName: string; out AInput: TLspBulkFixInput): Boolean;
begin
  AInput := Default(TLspBulkFixInput);
  Result := SameText(ExtractFileName(AFileName), 'U.pas') or SameText(ExtractFileName(AFileName), 'V.pas');
  if not Result then
    Exit;
  AInput.Rules := BuiltinRules;
  AInput.Settings := TServerSettings.Default;
  AInput.RelativePath := ExtractFileName(AFileName);
  if SameText(ExtractFileName(AFileName), 'U.pas') then
    AInput.Text := cAssignedFree
  else
    AInput.Text := cClean;
  AInput.Project.FileName := AFileName;
  AInput.Source := TCheckSource.Default;
  AInput.Baseline := Baseline;
end;

function Execute(const AArguments: string): TJSONObject;
var
  mFix: TLspBulkFix;
  mArguments: TJSONArray;
begin
  mFix := TLspBulkFix.Create(Input);
  mArguments := TJSONObject.ParseJSONValue(AArguments) as TJSONArray;
  try
    Result := mFix.Execute(mArguments) as TJSONObject;
  finally
    mArguments.Free;
    mFix.Free;
  end;
end;

procedure TLspBulkFixTests.AnswersWithDiffAndEdit;
var
  mAnswer, mFile: TJSONObject;
  mChanges, mRule: TJSONObject;
begin
  Baseline := nil;
  mAnswer := Execute('[{"rules": ["redundant-assigned-free"], "files": ["C:\\P\\U.pas"]}]');
  try
    Assert.StartsWith('Vorschau: 1 Korrekturen in 1 Dateien', mAnswer.GetValue<string>('summary'));
    Assert.AreEqual(1, mAnswer.GetValue<TJSONArray>('files').Count);
    mFile := mAnswer.GetValue<TJSONArray>('files').Items[0] as TJSONObject;
    Assert.AreEqual('C:\P\U.pas', mFile.GetValue<string>('file'));
    Assert.AreEqual(1, mFile.GetValue<Integer>('fixes'));
    Assert.IsFalse(mFile.GetValue<Boolean>('rejected'));
    mRule := mFile.GetValue<TJSONArray>('rules').Items[0] as TJSONObject;
    Assert.AreEqual('redundant-assigned-free', mRule.GetValue<string>('rule'));
    Assert.StartsWith('--- a/U.pas', mFile.GetValue<string>('diff'));
    Assert.IsTrue(Pos('-  if Assigned(AList) then', mFile.GetValue<string>('diff')) > 0);
    mChanges := mFile.GetValue<TJSONObject>('edit').GetValue<TJSONObject>('changes');
    Assert.AreEqual(1, mChanges.Count);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspBulkFixTests.UnchangedAndUnreadableFilesAreLeftOut;
var
  mAnswer: TJSONObject;
begin
  Baseline := nil;
  mAnswer := Execute('[{"rules": ["all"], "files": ["V.pas", "Fehlt.pas"]}]');
  try
    Assert.AreEqual(0, mAnswer.GetValue<TJSONArray>('files').Count);
    Assert.StartsWith('Vorschau: 0 Korrekturen in 0 Dateien', mAnswer.GetValue<string>('summary'));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspBulkFixTests.BaselineFindingsStay;
var
  mSource: TBaselineSource;
  mAnswer: TJSONObject;
begin
  // Was in der Baseline steht, korrigiert die Sammelkorrektur nicht (wie im Editor ausgeblendet).
  mSource.Path := 'U.pas';
  mSource.Text := cAssignedFree;
  mSource.Findings := TFileChecker.CheckText(BuiltinRules, TServerSettings.Default, 'U.pas', cAssignedFree);
  Baseline := TRuleBaseline.FromJson(TRuleBaseline.Build(TArray<TBaselineSource>.Create(mSource)));
  try
    mAnswer := Execute('[{"rules": ["redundant-assigned-free"], "files": ["U.pas"]}]');
    try
      Assert.AreEqual(0, mAnswer.GetValue<TJSONArray>('files').Count);
    finally
      mAnswer.Free;
    end;
  finally
    Baseline := nil;
  end;
end;

procedure TLspBulkFixTests.RefusesMissingRulesAndLowerConfidence;
begin
  Baseline := nil;
  Assert.WillRaise(
    procedure
    begin
      Execute('[{"files": ["U.pas"]}]').Free;
    end, EJsonRpcError);
  Assert.WillRaise(
    procedure
    begin
      Execute('[{"rules": ["redundant-assigned-free"], "files": ["U.pas"], "minConfidence": "medium"}]').Free;
    end, EJsonRpcError);
  Assert.WillRaise(
    procedure
    begin
      Execute('[]').Free;
    end, EJsonRpcError);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspBulkFixTests);

end.
