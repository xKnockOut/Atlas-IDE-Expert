unit Atlas.Core.Editor.LineItems.Tests;

// Tests der Suche nach dem Eintrag einer Editorzeile (Linsen über Methodenköpfen).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasLineItemsTests = class
  public
    /// <summary>Der erste Eintrag mit der Zeile gewinnt; ohne Treffer und ohne Einträge -1.</summary>
    [Test]
    procedure FindsFirstEntryOfLine;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Editor.LineItems;

function LineOf(AValue: Integer): Integer;
begin
  Result := AValue div 10;
end;

procedure TAtlasLineItemsTests.FindsFirstEntryOfLine;
var
  mItems: TArray<Integer>;
begin
  mItems := TArray<Integer>.Create(10, 31, 32, 50);
  Assert.AreEqual(0, TAtlasLineItems.IndexAt<Integer>(mItems, 1, LineOf));
  Assert.AreEqual(1, TAtlasLineItems.IndexAt<Integer>(mItems, 3, LineOf), 'erster Eintrag der Zeile');
  Assert.AreEqual(-1, TAtlasLineItems.IndexAt<Integer>(mItems, 4, LineOf), 'ohne Eintrag');
  Assert.AreEqual(-1, TAtlasLineItems.IndexAt<Integer>(nil, 1, LineOf), 'ohne Einträge');
  mItems := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLineItemsTests);

end.
