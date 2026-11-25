unit Adapters.Mcp.Conventions.Tests;

// Tests für die Host-Adapter zwischen Mcp und Rules (delphi://conventions, explain_finding): Einstellungen, Befund
// und Text gehen unverändert durch, das Markdown zurück.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpConventionsAdapterTests = class
  public
    [Test]
    procedure PassesSettings;
    [Test]
    procedure PassesFinding;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Mcp.Contract.Conventions,
  Atlas.Common.Rules.Contract.Api,
  Adapters.Mcp.Conventions;

type
  /// <summary>Merkt das Profil der Einstellungen und antwortet fest.</summary>
  TFakeConventions = class(TInterfacedObject, IRuleConventions)
  public
    Profile: string;
    function Markdown(const ASettings: TServerSettings): string;
  end;

  /// <summary>Merkt Befund, Datei und Text und antwortet fest.</summary>
  TFakePrompts = class(TInterfacedObject, IRuleFindingPrompts)
  public
    RuleId: string;
    FileName: string;
    Text: string;
    function Markdown(const AFinding: TRuleFinding; const AFileName, AText: string): string;
  end;

function TFakeConventions.Markdown(const ASettings: TServerSettings): string;
begin
  Profile := ASettings.Profile;
  Result := '# Konventionen';
end;

function TFakePrompts.Markdown(const AFinding: TRuleFinding; const AFileName, AText: string): string;
begin
  RuleId := AFinding.RuleId;
  FileName := AFileName;
  Text := AText;
  Result := '## Befund';
end;

{ TMcpConventionsAdapterTests }

procedure TMcpConventionsAdapterTests.PassesSettings;
var
  mFake: TFakeConventions;
  mRules: IRuleConventions;
  mAdapter: IMcpConventions;
  mSettings: TServerSettings;
begin
  mFake := TFakeConventions.Create;
  mRules := mFake;
  mAdapter := TMcpConventionsAdapter.Create(mRules);
  mSettings := Default(TServerSettings);
  mSettings.Profile := 'strict';
  Assert.AreEqual('# Konventionen', mAdapter.Markdown(mSettings));
  Assert.AreEqual('strict', mFake.Profile);
end;

procedure TMcpConventionsAdapterTests.PassesFinding;
var
  mFake: TFakePrompts;
  mRules: IRuleFindingPrompts;
  mAdapter: IMcpFindingPrompts;
  mFinding: TRuleFinding;
begin
  mFake := TFakePrompts.Create;
  mRules := mFake;
  mAdapter := TMcpFindingPromptsAdapter.Create(mRules);
  mFinding := Default(TRuleFinding);
  mFinding.RuleId := 'empty-except';
  Assert.AreEqual('## Befund', mAdapter.Markdown(mFinding, 'U.pas', 'unit U;'));
  Assert.AreEqual('empty-except', mFake.RuleId);
  Assert.AreEqual('U.pas', mFake.FileName);
  Assert.AreEqual('unit U;', mFake.Text);
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpConventionsAdapterTests);

end.
