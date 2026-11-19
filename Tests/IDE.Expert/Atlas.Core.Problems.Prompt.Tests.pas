unit Atlas.Core.Problems.Prompt.Tests;

// Tests für „Als Auftrag für KI-Assistenten kopieren“ im Fenster „Atlas-Prüfung“ (#2570): Argumente des
// Serverbefehls aus markierten Befunden (Regel und Compilermeldung) und der Text der Antwort.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasFindingsPromptTests = class
  public
    [Test]
    procedure ArgumentsCarryEveryFinding;
    [Test]
    procedure TextOfAnswer;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Problems.Findings,
  Atlas.Core.Problems.Prompt;

function Finding(const AFileName, ACode: string; ALine: Integer; ASeverity: TAtlasProblemSeverity;
  ACategory: TAtlasFindingCategory): TAtlasFinding;
begin
  Result := Default(TAtlasFinding);
  Result.FileName := AFileName;
  Result.Problem := Default(TAtlasProblem);
  Result.Problem.Code := ACode;
  Result.Problem.StartLine := ALine;
  Result.Problem.StartCharacter := 4;
  Result.Problem.Severity := ASeverity;
  Result.Problem.Message := 'Meldung ' + ACode;
  Result.Category := ACategory;
end;

{ TAtlasFindingsPromptTests }

procedure TAtlasFindingsPromptTests.ArgumentsCarryEveryFinding;
var
  mJson: TJSONValue;
  mFindings: TJSONArray;
  mFirst, mSecond: TJSONObject;
begin
  mJson := TJSONObject.ParseJSONValue(TAtlasFindingsPrompt.Arguments(TArray<TAtlasFinding>.Create(
    Finding('C:\P\U.pas', 'empty-except', 11, TAtlasProblemSeverity.Warning, TAtlasFindingCategory.CodeSmell),
    Finding('C:\P\V.pas', 'E2003', 3, TAtlasProblemSeverity.Error, TAtlasFindingCategory.Compiler))));
  try
    Assert.IsTrue(mJson is TJSONArray);
    mFindings := (TJSONArray(mJson).Items[0] as TJSONObject).GetValue<TJSONArray>('findings');
    Assert.AreEqual(2, mFindings.Count);
    mFirst := mFindings.Items[0] as TJSONObject;
    Assert.AreEqual('C:\P\U.pas', mFirst.GetValue<string>('file'));
    Assert.AreEqual(11, mFirst.GetValue<Integer>('line'));
    Assert.AreEqual(4, mFirst.GetValue<Integer>('character'));
    Assert.AreEqual('empty-except', mFirst.GetValue<string>('rule'));
    Assert.AreEqual('warning', mFirst.GetValue<string>('severity'));
    Assert.IsFalse(mFirst.GetValue<Boolean>('compiler'));
    mSecond := mFindings.Items[1] as TJSONObject;
    Assert.AreEqual('E2003', mSecond.GetValue<string>('rule'));
    Assert.AreEqual('Meldung E2003', mSecond.GetValue<string>('message'));
    Assert.AreEqual('error', mSecond.GetValue<string>('severity'));
    Assert.IsTrue(mSecond.GetValue<Boolean>('compiler'));
  finally
    mJson.Free;
  end;
end;

procedure TAtlasFindingsPromptTests.TextOfAnswer;
var
  mAnswer: TJSONValue;
begin
  mAnswer := TJSONObject.ParseJSONValue('{"text": "## Befund", "count": 1}');
  try
    Assert.AreEqual('## Befund', TAtlasFindingsPrompt.TextOf(mAnswer));
  finally
    mAnswer.Free;
  end;
  Assert.AreEqual('', TAtlasFindingsPrompt.TextOf(nil));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasFindingsPromptTests);

end.
