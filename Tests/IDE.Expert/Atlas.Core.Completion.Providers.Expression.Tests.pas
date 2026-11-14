unit Atlas.Core.Completion.Providers.Expression.Tests;

// Datenquelle der Debug-Dialoge (#538): Einträge aus dem Verlauf. Die
// Übersetzung der Serverantwort prüfen die Tests der Quelle Server.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Completion.Providers.Expression;

type
  [TestFixture]
  TAtlasExpressionProviderTests = class
  public
    [Test]
    procedure HistoryItemsReplaceField;
  end;

implementation

uses
  Atlas.Core.Completion.Contract;

{ TAtlasExpressionProviderTests }

procedure TAtlasExpressionProviderTests.HistoryItemsReplaceField;
var
  mItems: TAtlasCompletionItems;
begin
  mItems := TAtlasExpressionCompletionProvider.HistoryItems(TArray<string>.Create('Kunde.Name', 'Summe'), 'Verlauf');
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual('Kunde.Name', mItems[0].Name);
  Assert.AreEqual('Verlauf', mItems[1].Signature);
  Assert.AreEqual(1, mItems[1].Rank, 'neuester zuerst');
  Assert.AreEqual(0, Integer(Length(TAtlasExpressionCompletionProvider.HistoryItems(nil, 'Verlauf'))));
end;

end.
