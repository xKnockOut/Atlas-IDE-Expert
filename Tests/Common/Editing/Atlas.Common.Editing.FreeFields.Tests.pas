unit Atlas.Common.Editing.FreeFields.Tests;

// Tests für die Code-Aktionen „Im Destruktor freigeben“ (#666).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFreeFieldsTests = class
  public
    [Test]
    procedure ActionsOnFieldAndClass;
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.Destructors,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Editing.FreeFields,
  Atlas.Tests.TextEdits,
  Atlas.Tests.SourceText;

const
  cLager =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TLager = class'#10 +
    '    FRegale: TList;'#10 +
    '    FKisten: TList;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TLager.Create;'#10 +
    'begin'#10 +
    '  FRegale := TList.Create;'#10 +
    '  FKisten := TList.Create;'#10 +
    'end;'#10 +
    'end.';

procedure TFreeFieldsTests.ActionsOnFieldAndClass;
var
  mTree: TSyntaxTree;
  mActions: TArray<TCodeAction>;
begin
  mTree := TPascalParser.Parse(cLager);
  try
    // Feldzeile: Feld und ganze Klasse.
    mActions := TFreeFields.Actions(mTree, cLager, nil, 4, TFreeFieldsStyle.Free, True);
    Assert.AreEqual(2, Integer(Length(mActions)));
    Assert.AreEqual(TFreeFields.FieldTitle, mActions[0].Title);
    Assert.AreEqual('Alle eigenen Objekte freigeben (2)', mActions[1].Title);
    Assert.IsTrue(TTestSource.Parses(TTestEdits.Apply(cLager, mActions[0].Edits)));
    // Ohne Feldaktion (die Regel liefert sie) bleibt die für die Klasse.
    mActions := TFreeFields.Actions(mTree, cLager, nil, 4, TFreeFieldsStyle.Free, False);
    Assert.AreEqual(1, Integer(Length(mActions)));
    // Kopfzeile der Klasse.
    mActions := TFreeFields.Actions(mTree, cLager, nil, 3, TFreeFieldsStyle.Free, True);
    Assert.AreEqual(1, Integer(Length(mActions)));
    Assert.AreEqual('Alle eigenen Objekte freigeben (2)', mActions[0].Title);
    // Andere Zeile.
    mActions := TFreeFields.Actions(mTree, cLager, nil, 10, TFreeFieldsStyle.Free, True);
    Assert.AreEqual(0, Integer(Length(mActions)));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TFreeFieldsTests);

end.
