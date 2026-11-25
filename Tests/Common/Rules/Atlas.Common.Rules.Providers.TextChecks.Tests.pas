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
    [Test]
    procedure OffersFixInRange;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Contract.Api,
  Atlas.Common.Rules.Providers.TextChecks,
  Atlas.Common.Checks.Contract;

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

procedure TRuleTextChecksProviderTests.OffersFixInRange;
var
  mChecks: IRuleTextChecks;
  mActions: TArray<TCodeAction>;
  mAction: TCodeAction;
  mFixes: Integer;
begin
  mChecks := TRuleTextChecksProvider.Create(BuiltinRules, nil, nil);
  // Zeile 11 (ab 0): "  if Assigned(AList) then".
  mActions := mChecks.Actions('C:\P\U.pas', 'U.pas', cAssignedFree, TServerSettings.Default,
    TTextRange.Create(11, 0, 11, 100));
  mFixes := 0;
  for mAction in mActions do
  begin
    if Length(mAction.Edits) > 0 then
    begin
      Inc(mFixes);
    end;
  end;
  Assert.IsTrue(mFixes > 0);
  Assert.AreEqual(0, Integer(Length(mChecks.Actions('C:\P\U.pas', 'U.pas', cAssignedFree, TServerSettings.Default,
    TTextRange.Create(0, 0, 0, 5)))));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleTextChecksProviderTests);

end.
