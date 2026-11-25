unit Atlas.Common.Rules.Providers.TextChecks.Tests;

// Tests des Anbieters der Textprüfung für andere Features: meldet die Treffer der gebundenen Regeln, wendet die
// Einstellungen auf den relativen Pfad an und fragt Projekt und Symbole zur geprüften Datei ab.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleTextChecksProviderTests = class
  public
    [Test]
    procedure FindsRuleFindings;
    [Test]
    procedure ExcludesRelativePath;
    [Test]
    procedure AsksProjectAndSourceForFile;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Contract.Api,
  Atlas.Common.Rules.Providers.TextChecks;

const
  cAssignedFree = 'unit U;'#10#10'interface'#10#10'uses'#10'  System.Classes;'#10#10'implementation'#10#10 +
    'procedure Weg(AList: TStringList);'#10'begin'#10'  if Assigned(AList) then'#10'    AList.Free;'#10'end;'#10#10 +
    'end.'#10;

function HasRule(const AFindings: TArray<TRuleFinding>; const ARuleId: string): Boolean;
var
  mFinding: TRuleFinding;
begin
  Result := False;
  for mFinding in AFindings do
  begin
    if mFinding.RuleId = ARuleId then
    begin
      Exit(True);
    end;
  end;
end;

{ TRuleTextChecksProviderTests }

procedure TRuleTextChecksProviderTests.FindsRuleFindings;
var
  mChecks: IRuleTextChecks;
begin
  mChecks := TRuleTextChecksProvider.Create(BuiltinRules, nil, nil);
  Assert.IsTrue(HasRule(mChecks.Check('C:\P\Src\U.pas', 'Src\U.pas', cAssignedFree, TServerSettings.Default),
    'redundant-assigned-free'));
end;

procedure TRuleTextChecksProviderTests.ExcludesRelativePath;
var
  mChecks: IRuleTextChecks;
  mIssues: TArray<TConfigurationIssue>;
  mSettings: TServerSettings;
begin
  mChecks := TRuleTextChecksProvider.Create(BuiltinRules, nil, nil);
  mSettings := TConfigurationParser.Parse('{"rules": {"redundant-assigned-free": "off"}}', mIssues);
  Assert.IsFalse(HasRule(mChecks.Check('C:\P\Src\U.pas', 'Src\U.pas', cAssignedFree, mSettings),
    'redundant-assigned-free'));
end;

procedure TRuleTextChecksProviderTests.AsksProjectAndSourceForFile;
var
  mChecks: IRuleTextChecks;
  mProjectFile, mSourceFile: string;
  mProject: TCheckProjectFunc;
  mSource: TCheckSourceFunc;
begin
  mProjectFile := '';
  mSourceFile := '';
  mProject :=
    function(const AFileName: string): TCheckProject
    begin
      mProjectFile := AFileName;
      Result := Default(TCheckProject);
      Result.FileName := AFileName;
    end;
  mSource :=
    function(const AFileName: string): TCheckSource
    begin
      mSourceFile := AFileName;
      Result := TCheckSource.Default;
    end;
  mChecks := TRuleTextChecksProvider.Create(BuiltinRules, mProject, mSource);
  mChecks.Check('C:\P\Src\U.pas', 'Src\U.pas', cAssignedFree, TServerSettings.Default);
  Assert.AreEqual('C:\P\Src\U.pas', mProjectFile);
  Assert.AreEqual('C:\P\Src\U.pas', mSourceFile);
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleTextChecksProviderTests);

end.
