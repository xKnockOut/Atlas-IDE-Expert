unit Adapters.Lsp.BulkFix.Tests;

// Tests für den Host-Adapter, der atlas.server.fixFindings die Sammelkorrektur der Prüfregeln gibt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspBulkFixAdapterTests = class
  public
    [Test]
    procedure DelegatesToRules;
    [Test]
    procedure PassesRefusal;
    [Test]
    procedure WrapOfNilIsNil;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.CheckContext,
  Atlas.Common.Rules.Contract.Api,
  Atlas.Common.Rules.Providers.BulkFix,
  Adapters.Lsp.BulkFix;

const
  cAssignedFree = 'unit U;'#10#10'interface'#10#10'uses'#10'  System.Classes;'#10#10'implementation'#10#10 +
    'procedure Weg(AList: TStringList);'#10'begin'#10'  if Assigned(AList) then'#10'    AList.Free;'#10'end;'#10#10 +
    'end.'#10;

function ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := cAssignedFree;
  Result := True;
end;

function Contexts: TRuleContextProvider;
begin
  Result :=
    function(const AUri: string; out AContext: TRuleCheckContext): Boolean
    begin
      AContext := Default(TRuleCheckContext);
      AContext.Rules := BuiltinRules;
      AContext.Settings := TServerSettings.Default;
      AContext.RelativePath := 'U.pas';
      Result := True;
    end;
end;

function Adapter: ILspBulkFix;
var
  mRules: IRuleWorkspaceBulkFix;
begin
  mRules := TRuleBulkFixProvider.CreateForWorkspace(Contexts(), ReadText, nil);
  Result := TLspBulkFixAdapter.Wrap(mRules);
end;

{ TLspBulkFixAdapterTests }

procedure TLspBulkFixAdapterTests.DelegatesToRules;
var
  mRun: TLspBulkFixRun;
  mError: string;
begin
  Assert.IsTrue(Adapter.Run(['C:\P\U.pas'], ['redundant-assigned-free'], '', mRun, mError), mError);
  Assert.AreEqual(1, Integer(Length(mRun.Files)));
  Assert.AreEqual('C:\P\U.pas', mRun.Files[0].FileName);
  Assert.IsTrue(mRun.Files[0].Changed);
  Assert.AreEqual(1, mRun.Files[0].FixCount);
  Assert.AreEqual('redundant-assigned-free', mRun.Files[0].Applied[0].RuleId);
  Assert.AreEqual(1, mRun.Files[0].Applied[0].Count);
  Assert.AreEqual(cAssignedFree, mRun.Files[0].OldText);
  Assert.AreNotEqual(cAssignedFree, mRun.Files[0].NewText);
  Assert.Contains(mRun.Files[0].Diff, '--- a/U.pas');
  Assert.Contains(mRun.Summary, 'Vorschau: 1 Korrekturen in 1 Dateien');
end;

procedure TLspBulkFixAdapterTests.PassesRefusal;
var
  mRun: TLspBulkFixRun;
  mError: string;
begin
  Assert.IsFalse(Adapter.Run(['C:\P\U.pas'], ['redundant-assigned-free'], 'medium', mRun, mError));
  Assert.Contains(mError, 'fix.minConfidence');
  Assert.AreEqual(0, Integer(Length(mRun.Files)));
end;

procedure TLspBulkFixAdapterTests.WrapOfNilIsNil;
var
  mBulkFix: IInterface;
begin
  mBulkFix := TLspBulkFixAdapter.Wrap(nil);
  Assert.IsNull(mBulkFix);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspBulkFixAdapterTests);

end.
