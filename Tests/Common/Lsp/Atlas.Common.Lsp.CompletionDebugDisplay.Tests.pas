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
  Source =
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
  Request: TCompletionRequest;
begin
  Request := TCompletionRequest.Create(Source, 'Kunden.pas', TTextPosition.Create(ALine, ACharacter));
  try
    Result := TCompletionDebugDisplay.Items(Request, AItems);
  finally
    Request.Free;
  end;
end;

function Names(const AItems: TCompletionItems): string;
var
  Item: TCompletionItem;
begin
  Result := '';
  for Item in AItems.Items do
    Result := Result + Item.Name + ' ';
end;

function ColumnAfter(const ALine, AText: string): Integer;
begin
  Result := Pos(AText, ALine) - 1 + Length(AText);
end;

procedure TCompletionDebugDisplayTests.PlaceholderAfterBrace;
var
  Items: TCompletionItems;
begin
  // Cursor direkt hinter „{“ vor „Name“: alle Mitglieder.
  Assert.IsTrue(ItemsAt(3, ColumnAfter('  // atlas-debug: ''{Name}, {O''', '''{'), Items));
  Assert.IsTrue(Names(Items).StartsWith('Name Ort Saldo '), Names(Items));
  Assert.IsTrue(Names(Items).Contains('ClassName '));
end;

procedure TCompletionDebugDisplayTests.PrefixFiltersMembers;
var
  Items: TCompletionItems;
begin
  Assert.IsTrue(ItemsAt(3, ColumnAfter('  // atlas-debug: ''{Name}, {O''', '{O'), Items));
  Assert.AreEqual('Ort ', Names(Items));
  Assert.AreEqual(3, Items.Items[0].TextEdit.Range.StartPos.Line);
  Assert.AreEqual(ColumnAfter('  // atlas-debug: ''{Name}, {O''', '{O') - 1,
    Items.Items[0].TextEdit.Range.StartPos.Character);
  Assert.AreEqual('Ort', Items.Items[0].TextEdit.NewText);
end;

procedure TCompletionDebugDisplayTests.ChildrenList;
var
  Items: TCompletionItems;
begin
  Assert.IsTrue(ItemsAt(4, Length('  // atlas-debug-children: Name, '), Items));
  Assert.IsTrue(Names(Items).StartsWith('Name Ort Saldo '), Names(Items));
end;

procedure TCompletionDebugDisplayTests.AttributeTemplate;
var
  Items: TCompletionItems;
begin
  Assert.IsTrue(ItemsAt(9, ColumnAfter('  [AtlasDebugDisplay(''({'')]', '({'), Items));
  Assert.IsTrue(Names(Items).StartsWith('X Y '), Names(Items));
end;

procedure TCompletionDebugDisplayTests.NothingOutsidePlaceholder;
var
  Items: TCompletionItems;
begin
  // Hinter „}“ und in gewöhnlichem Code: keine Antwort dieser Quelle.
  Assert.IsFalse(ItemsAt(3, ColumnAfter('  // atlas-debug: ''{Name}, {O''', '{Name}'), Items));
  Assert.IsFalse(ItemsAt(6, 8, Items));
end;

procedure TCompletionDebugDisplayTests.PrefixAt;
var
  Start: Integer;
  Prefix: string;
begin
  Assert.IsTrue(TCompletionDebugDisplay.PrefixAt('// atlas-debug: {Na', 19, 16, TDebugDisplayCompletionPlace.Template,
    Start, Prefix));
  Assert.AreEqual('Na', Prefix);
  Assert.AreEqual(17, Start);
  Assert.IsFalse(TCompletionDebugDisplay.PrefixAt('// atlas-debug: {{Na', 20, 16,
    TDebugDisplayCompletionPlace.Template, Start, Prefix), 'escaped');
  Assert.IsFalse(TCompletionDebugDisplay.PrefixAt('// atlas-debug: {A}Na', 21, 16,
    TDebugDisplayCompletionPlace.Template, Start, Prefix));
  Assert.IsTrue(TCompletionDebugDisplay.PrefixAt('// atlas-debug-children: A, B', 29, 0,
    TDebugDisplayCompletionPlace.Children, Start, Prefix));
  Assert.AreEqual('B', Prefix);
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionDebugDisplayTests);

end.
