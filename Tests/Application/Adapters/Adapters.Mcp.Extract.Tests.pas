unit Adapters.Mcp.Extract.Tests;

// Tests für den Host-Adapter zwischen Mcp und Editing (extract_method): Wünsche und Ergebnis gehen unverändert
// durch.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpExtractAdapterTests = class
  public
    [Test]
    procedure PassesWishAndResult;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Mcp.Contract.Extract,
  Editing.Contract.Extract,
  Adapters.Mcp.Extract;

type
  /// <summary>Merkt den Wunsch und antwortet fest.</summary>
  TFakeExtract = class(TInterfacedObject, IEditingExtract)
  public
    Wish: TEditingExtractWish;
    Range: TTextRange;
    Text: string;
    function ExtractMethod(const AText: string; const ARange: TTextRange;
      const AWish: TEditingExtractWish): TEditingExtractResult;
  end;

function TFakeExtract.ExtractMethod(const AText: string; const ARange: TTextRange;
  const AWish: TEditingExtractWish): TEditingExtractResult;
begin
  Text := AText;
  Range := ARange;
  Wish := AWish;
  Result := Default(TEditingExtractResult);
  Result.Extracted := True;
  Result.Action.Title := 'Methode extrahieren';
  Result.Reason := 'Grund';
  Result.DuplicatesReason := 'keine';
end;

{ TMcpExtractAdapterTests }

procedure TMcpExtractAdapterTests.PassesWishAndResult;
var
  mFake: TFakeExtract;
  mEditing: IEditingExtract;
  mAdapter: IMcpExtract;
  mWish: TMcpExtractWish;
  mPlan: TMcpExtractPlan;
begin
  mFake := TFakeExtract.Create;
  mEditing := mFake;
  mAdapter := TMcpExtractAdapter.Create(mEditing);
  mWish := Default(TMcpExtractWish);
  mWish.MethodName := 'Neu';
  mWish.Duplicates := True;
  mWish.InlineVar := True;
  mWish.Style := TFormatStyle.Default;
  mPlan := mAdapter.ExtractMethod('unit U;', TTextRange.Create(1, 2, 3, 4), mWish);
  Assert.AreEqual('unit U;', mFake.Text);
  Assert.AreEqual(3, mFake.Range.EndPos.Line);
  Assert.AreEqual('Neu', mFake.Wish.MethodName);
  Assert.IsTrue(mFake.Wish.Duplicates);
  Assert.IsTrue(mFake.Wish.InlineVar);
  Assert.IsTrue(mPlan.Extracted);
  Assert.AreEqual('Methode extrahieren', mPlan.Action.Title);
  Assert.AreEqual('Grund', mPlan.Reason);
  Assert.AreEqual('keine', mPlan.DuplicatesReason);
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpExtractAdapterTests);

end.
