unit Adapters.Mcp.CompilerFixes.Tests;

// Tests für den Host-Adapter zwischen Mcp und Editing (explain_compiler_message): Meldung und Korrekturen gehen
// unverändert durch.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpCompilerFixesAdapterTests = class
  public
    [Test]
    procedure PassesMessageAndFixes;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Mcp.Contract.CompilerFixes,
  Atlas.Common.Editing.Contract.CompilerFixes,
  Adapters.Mcp.CompilerFixes;

type
  /// <summary>Merkt Text und Meldung und antwortet fest.</summary>
  TFakeCompilerFixes = class(TInterfacedObject, IEditingCompilerFixes)
  public
    Text: string;
    Message: TFixMessage;
    function Fixes(const AText: string; const AMessage: TFixMessage): TArray<TCompilerFix>;
  end;

function TFakeCompilerFixes.Fixes(const AText: string; const AMessage: TFixMessage): TArray<TCompilerFix>;
begin
  Text := AText;
  Message := AMessage;
  SetLength(Result, 2);
  Result[0] := Default(TCompilerFix);
  Result[0].Title := 'Erste';
  Result[1] := Default(TCompilerFix);
  Result[1].Title := 'Zweite';
  Result[1].Preferred := True;
  Result[1].Edits := [TTextEdit.Create(TTextRange.Create(1, 0, 1, 0), 'Neu')];
end;

{ TMcpCompilerFixesAdapterTests }

procedure TMcpCompilerFixesAdapterTests.PassesMessageAndFixes;
var
  mFake: TFakeCompilerFixes;
  mEditing: IEditingCompilerFixes;
  mAdapter: IMcpCompilerFixes;
  mMessage: TMcpFixMessage;
  mResult: TArray<TMcpCompilerFix>;
begin
  mFake := TFakeCompilerFixes.Create;
  mEditing := mFake;
  mAdapter := TMcpCompilerFixesAdapter.Create(mEditing);
  mMessage := Default(TMcpFixMessage);
  mMessage.Code := 'w1035';
  mMessage.Line := 3;
  mMessage.Column := 4;
  mMessage.Text := 'Meldung';
  mResult := mAdapter.Fixes('unit U;', mMessage);
  Assert.AreEqual('unit U;', mFake.Text);
  Assert.AreEqual('W1035', mFake.Message.Code);
  Assert.AreEqual(3, mFake.Message.Line);
  Assert.AreEqual(4, mFake.Message.Column);
  Assert.AreEqual('Meldung', mFake.Message.Text);
  Assert.AreEqual(2, Integer(Length(mResult)));
  Assert.AreEqual('Erste', mResult[0].Title);
  Assert.IsFalse(mResult[0].Preferred);
  Assert.AreEqual('Zweite', mResult[1].Title);
  Assert.IsTrue(mResult[1].Preferred);
  Assert.AreEqual('Neu', mResult[1].Edits[0].NewText);
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpCompilerFixesAdapterTests);

end.
