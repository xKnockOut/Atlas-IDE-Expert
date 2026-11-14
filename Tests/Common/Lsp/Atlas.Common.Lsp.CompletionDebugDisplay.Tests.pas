unit Atlas.Common.Lsp.CompletionDebugDisplay.Tests;

// Tests der Vervollständigung in Wertdarstellungen (#854): Platzhalter nach {,
// Namen in atlas-debug-children und im Attribut, nichts außerhalb.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompletionDebugDisplayTests = class
  public
    [Test]
    procedure PlaceholderAfterBrace;
    [Test]
    procedure PrefixFiltersMembers;
    [Test]
    procedure ChildrenList;
    [Test]
    procedure AttributeTemplate;
    [Test]
    procedure NothingOutsidePlaceholder;
    [Test]
    procedure PrefixAt;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.CompletionDebugDisplay;

const
  cSource =
    'unit Kunden;'#10 +
    'interface'#10 +
    'type'#10 +
    '  // atlas-debug: ''{Name}, {O'''#10 +
    '  // atlas-debug-children: Name, '#10 +
    '  TKunde = class'#10 +
    '    Name, Ort: string;'#10 +
    '    function Saldo: Double;'#10 +
    '  end;'#10 +
    '  [AtlasDebugDisplay(''({'')]'#10 +
    '  TPunkt = record'#10 +
    '    X, Y: Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TKunde.Saldo: Double;'#10 +
    'begin'#10 +
    '  Result := 0;'#10 +
    'end;'#10 +
    'end.';

function ItemsAt(ALine, ACharacter: Integer; out AItems: TCompletionItems): Boolean;
var
  mRequest: TCompletionRequest;
begin
  mRequest := TCompletionRequest.Create(cSource, 'Kunden.pas', TTextPosition.Create(ALine, ACharacter));
  try
    Result := TCompletionDebugDisplay.Items(mRequest, AItems);
  finally
    mRequest.Free;
  end;
end;

function Names(const AItems: TCompletionItems): string;
var
  mItem: TCompletionItem;
begin
  Result := '';
  for mItem in AItems.Items do
  begin
    Result := Result + mItem.Name + ' ';
  end;
end;

function ColumnAfter(const ALine, AText: string): Integer;
begin
  Result := Pos(AText, ALine) - 1 + Length(AText);
end;

procedure TCompletionDebugDisplayTests.PlaceholderAfterBrace;
var
  mItems: TCompletionItems;
begin
  // Cursor direkt hinter „{“ vor „Name“: alle Mitglieder.
  Assert.IsTrue(ItemsAt(3, ColumnAfter('  // atlas-debug: ''{Name}, {O''', '''{'), mItems));
  Assert.IsTrue(Names(mItems).StartsWith('Name Ort Saldo '), Names(mItems));
  Assert.IsTrue(Names(mItems).Contains('ClassName '));
end;

procedure TCompletionDebugDisplayTests.PrefixFiltersMembers;
var
  mItems: TCompletionItems;
begin
  Assert.IsTrue(ItemsAt(3, ColumnAfter('  // atlas-debug: ''{Name}, {O''', '{O'), mItems));
  Assert.AreEqual('Ort ', Names(mItems));
  Assert.AreEqual(3, mItems.Items[0].TextEdit.Range.StartPos.Line);
  Assert.AreEqual(ColumnAfter('  // atlas-debug: ''{Name}, {O''', '{O') - 1,
    mItems.Items[0].TextEdit.Range.StartPos.Character);
  Assert.AreEqual('Ort', mItems.Items[0].TextEdit.NewText);
end;

procedure TCompletionDebugDisplayTests.ChildrenList;
var
  mItems: TCompletionItems;
begin
  Assert.IsTrue(ItemsAt(4, Length('  // atlas-debug-children: Name, '), mItems));
  Assert.IsTrue(Names(mItems).StartsWith('Name Ort Saldo '), Names(mItems));
end;

procedure TCompletionDebugDisplayTests.AttributeTemplate;
var
  mItems: TCompletionItems;
begin
  Assert.IsTrue(ItemsAt(9, ColumnAfter('  [AtlasDebugDisplay(''({'')]', '({'), mItems));
  Assert.IsTrue(Names(mItems).StartsWith('X Y '), Names(mItems));
end;

procedure TCompletionDebugDisplayTests.NothingOutsidePlaceholder;
var
  mItems: TCompletionItems;
begin
  // Hinter „}“ und in gewöhnlichem Code: keine Antwort dieser Quelle.
  Assert.IsFalse(ItemsAt(3, ColumnAfter('  // atlas-debug: ''{Name}, {O''', '{Name}'), mItems));
  Assert.IsFalse(ItemsAt(6, 8, mItems));
end;

procedure TCompletionDebugDisplayTests.PrefixAt;
var
  mStart: Integer;
  mPrefix: string;
begin
  Assert.IsTrue(TCompletionDebugDisplay.PrefixAt('// atlas-debug: {Na', 19, 16, TDebugDisplayCompletionPlace.Template,
    mStart, mPrefix));
  Assert.AreEqual('Na', mPrefix);
  Assert.AreEqual(17, mStart);
  Assert.IsFalse(TCompletionDebugDisplay.PrefixAt('// atlas-debug: {{Na', 20, 16,
    TDebugDisplayCompletionPlace.Template, mStart, mPrefix), 'escaped');
  Assert.IsFalse(TCompletionDebugDisplay.PrefixAt('// atlas-debug: {A}Na', 21, 16,
    TDebugDisplayCompletionPlace.Template, mStart, mPrefix));
  Assert.IsTrue(TCompletionDebugDisplay.PrefixAt('// atlas-debug-children: A, B', 29, 0,
    TDebugDisplayCompletionPlace.Children, mStart, mPrefix));
  Assert.AreEqual('B', mPrefix);
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionDebugDisplayTests);

end.
