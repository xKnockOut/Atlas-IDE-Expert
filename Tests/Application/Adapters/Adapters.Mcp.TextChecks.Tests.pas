unit Adapters.Mcp.TextChecks.Tests;

// Tests für den Host-Adapter zwischen Mcp und Rules (Prüfung eines Textes): Datei, relativer Pfad, Text und
// Einstellungen gehen unverändert durch, die Treffer zurück.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpTextChecksAdapterTests = class
  public
    [Test]
    procedure PassesArgumentsAndFindings;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Mcp.Contract.TextChecks,
  Atlas.Common.Rules.Contract.Api,
  Adapters.Mcp.TextChecks;

type
  /// <summary>Merkt die Eingaben und meldet einen festen Treffer.</summary>
  TFakeTextChecks = class(TInterfacedObject, IRuleTextChecks)
  public
    FileName: string;
    RelativePath: string;
    Text: string;
    Project: string;
    function Check(const AFileName, ARelativePath, AText: string; const ASettings: TServerSettings):
      TArray<TRuleFinding>;
  end;

function TFakeTextChecks.Check(const AFileName, ARelativePath, AText: string;
  const ASettings: TServerSettings): TArray<TRuleFinding>;
begin
  FileName := AFileName;
  RelativePath := ARelativePath;
  Text := AText;
  Project := ASettings.Project;
  SetLength(Result, 1);
  Result[0] := Default(TRuleFinding);
  Result[0].RuleId := 'fake-rule';
  Result[0].Message := 'Treffer';
end;

{ TMcpTextChecksAdapterTests }

procedure TMcpTextChecksAdapterTests.PassesArgumentsAndFindings;
var
  mFake: TFakeTextChecks;
  mRules: IRuleTextChecks;
  mAdapter: IMcpTextChecks;
  mSettings: TServerSettings;
  mFindings: TArray<TRuleFinding>;
begin
  mFake := TFakeTextChecks.Create;
  mRules := mFake;
  mAdapter := TMcpTextChecksAdapter.Create(mRules);
  mSettings := TServerSettings.Default;
  mSettings.Project := 'P.dproj';
  mFindings := mAdapter.Check('C:\P\U.pas', 'U.pas', 'unit U;', mSettings);
  Assert.AreEqual('C:\P\U.pas', mFake.FileName);
  Assert.AreEqual('U.pas', mFake.RelativePath);
  Assert.AreEqual('unit U;', mFake.Text);
  Assert.AreEqual('P.dproj', mFake.Project);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('fake-rule', mFindings[0].RuleId);
  Assert.AreEqual('Treffer', mFindings[0].Message);
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpTextChecksAdapterTests);

end.
