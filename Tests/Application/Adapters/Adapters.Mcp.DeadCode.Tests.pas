unit Adapters.Mcp.DeadCode.Tests;

// Tests für den Host-Adapter zwischen Mcp und Rules (find_unused_code): Kennungen, Verfügbarkeit, Vollständigkeit,
// Lesen und Prüfen gehen unverändert durch.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpDeadCodeAdapterTests = class
  public
    [Test]
    procedure PassesCalls;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Mcp.Contract.DeadCode,
  Rules.Contract.Api,
  Adapters.Mcp.DeadCode;

type
  /// <summary>Antwortet fest und merkt die Eingaben von Check.</summary>
  TFakeDeadCode = class(TInterfacedObject, IRuleDeadCode)
  public
    CheckedFile: string;
    CheckedPath: string;
    function RuleIds: TArray<string>;
    function Available: Boolean;
    function Complete(out AReason: string): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function Check(const AFileName, ARelativePath, AText: string; const ASettings: TServerSettings):
      TArray<TRuleFinding>;
  end;

function TFakeDeadCode.RuleIds: TArray<string>;
begin
  Result := TArray<string>.Create('unused-unit');
end;

function TFakeDeadCode.Available: Boolean;
begin
  Result := True;
end;

function TFakeDeadCode.Complete(out AReason: string): Boolean;
begin
  AReason := 'Index läuft';
  Result := False;
end;

function TFakeDeadCode.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := 'Text von ' + AFileName;
  Result := True;
end;

function TFakeDeadCode.Check(const AFileName, ARelativePath, AText: string;
  const ASettings: TServerSettings): TArray<TRuleFinding>;
begin
  CheckedFile := AFileName;
  CheckedPath := ARelativePath;
  SetLength(Result, 1);
  Result[0] := Default(TRuleFinding);
  Result[0].RuleId := 'unused-unit';
end;

{ TMcpDeadCodeAdapterTests }

procedure TMcpDeadCodeAdapterTests.PassesCalls;
var
  mFake: TFakeDeadCode;
  mRules: IRuleDeadCode;
  mAdapter: IMcpDeadCode;
  mReason, mText: string;
  mFindings: TArray<TRuleFinding>;
begin
  mFake := TFakeDeadCode.Create;
  mRules := mFake;
  mAdapter := TMcpDeadCodeAdapter.Create(mRules);
  Assert.AreEqual('unused-unit', mAdapter.RuleIds[0]);
  Assert.IsTrue(mAdapter.Available);
  Assert.IsFalse(mAdapter.Complete(mReason));
  Assert.AreEqual('Index läuft', mReason);
  Assert.IsTrue(mAdapter.ReadText('C:\P\U.pas', mText));
  Assert.AreEqual('Text von C:\P\U.pas', mText);
  mFindings := mAdapter.Check('C:\P\U.pas', 'U.pas', 'unit U;', TServerSettings.Default);
  Assert.AreEqual('C:\P\U.pas', mFake.CheckedFile);
  Assert.AreEqual('U.pas', mFake.CheckedPath);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('unused-unit', mFindings[0].RuleId);
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpDeadCodeAdapterTests);

end.
