unit Argus.Common.Lsp.Completion.Tests;

interface

uses
  DUnitX.TestFramework,
  Argus.Common.Index.Contract,
  Argus.Common.Semantics.NameResolver,
  Argus.Common.Lsp.Completion;

type
  [TestFixture]
  TLspCompletionTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function ItemsAt(const AText, AMarker: string): TCompletionItems;
    function Names(const AItems: TCompletionItems): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ScopeListsLocalsMembersAndUsedUnits;
    [Test]
    procedure ScopeFiltersByPrefix;
    [Test]
    procedure MembersAfterDotIncludeInherited;
    [Test]
    procedure MembersOfUnitAreInterfaceSymbols;
    [Test]
    procedure UsesClauseListsUnits;
    [Test]
    procedure NothingInCommentsAndStrings;
    [Test]
    procedure WritesCompletionList;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser,
  Argus.Common.Index.SymbolIndex,
  Argus.Common.Index.Extractor;

const
  HauptFile = 'C:\P\Haupt.pas';

  UnitWerkzeug =
    'unit Werkzeug;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TBasis = class'#10 +
    '    Zaehler: Integer;'#10 +
    '    procedure Melde;'#10 +
    '  end;'#10 +
    'procedure Rechne;'#10 +
    'implementation'#10 +
    'procedure Versteckt;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Rechne;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TBasis.Melde;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Werkzeug;'#10 +
    'type'#10 +
    '  TFoo = class(TBasis)'#10 +
    '    Name: string;'#10 +
    '    procedure Bar(Anzahl: Integer);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Bar(Anzahl: Integer);'#10 +
    'var'#10 +
    '  Wert: TFoo;'#10 +
    'begin'#10 +
    '  { Kommentar Wert } |'#10 +
    'end;'#10 +
    'end.';

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  Index, Line, LineStart, Scan: Integer;
begin
  // Cursor hinter AMarker.
  Index := Pos(AMarker, AText);
  if Index = 0 then
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  Inc(Index, Length(AMarker));
  Line := 0;
  LineStart := 1;
  for Scan := 1 to Index - 1 do
    if AText[Scan] = #10 then
    begin
      Inc(Line);
      LineStart := Scan + 1;
    end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

function WithCode(const ACode: string): string;
begin
  Result := StringReplace(UnitHaupt, '  { Kommentar Wert } |', ACode, []);
end;

{ TLspCompletionTests }

procedure TLspCompletionTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitWerkzeug, 'C:\P\Werkzeug.pas', nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspCompletionTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspCompletionTests.ItemsAt(const AText, AMarker: string): TCompletionItems;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TLspCompletion.Collect(FResolver, FIndex, Tree, HauptFile, PositionOf(AText, AMarker));
  finally
    Tree.Free;
  end;
end;

function TLspCompletionTests.Names(const AItems: TCompletionItems): string;
var
  Item: TCompletionItem;
begin
  Result := '';
  for Item in AItems.Items do
    Result := Result + Item.Name + ' ';
  Result := Result.Trim;
end;

procedure TLspCompletionTests.ScopeListsLocalsMembersAndUsedUnits;
begin
  // Nächster Gültigkeitsbereich zuerst; Versteckt steht nur in implementation von Werkzeug.
  Assert.AreEqual('Anzahl Wert Self Name Bar Zaehler Melde TFoo TBasis Rechne',
    Names(ItemsAt(WithCode('  '), #10'begin'#10'  ')));
end;

procedure TLspCompletionTests.ScopeFiltersByPrefix;
begin
  Assert.AreEqual('Wert', Names(ItemsAt(WithCode('  We'), '  We')));
  Assert.AreEqual('TFoo', Names(ItemsAt(WithCode('  tf'), '  tf')));
end;

procedure TLspCompletionTests.MembersAfterDotIncludeInherited;
var
  Text: string;
begin
  Text := WithCode('  Wert.');
  Assert.AreEqual('Name Bar Zaehler Melde', Names(ItemsAt(Text, 'Wert.')));
  Text := WithCode('  Self.Za');
  Assert.AreEqual('Zaehler', Names(ItemsAt(Text, 'Self.Za')));
end;

procedure TLspCompletionTests.MembersOfUnitAreInterfaceSymbols;
var
  Text: string;
begin
  Text := WithCode('  Werkzeug.');
  Assert.AreEqual('TBasis Rechne', Names(ItemsAt(Text, 'Werkzeug.')));
end;

procedure TLspCompletionTests.UsesClauseListsUnits;
var
  Text: string;
  Items: TCompletionItems;
begin
  Text := StringReplace(UnitHaupt, 'uses Werkzeug;', 'uses Werk', []);
  Items := ItemsAt(Text, 'uses Werk');
  Assert.AreEqual('Werkzeug', Names(Items));
  Assert.AreEqual(9, Items.Items[0].Kind);
end;

procedure TLspCompletionTests.NothingInCommentsAndStrings;
begin
  Assert.AreEqual('', Names(ItemsAt(UnitHaupt, '{ Kommentar W')));
  Assert.AreEqual('', Names(ItemsAt(WithCode('  Name := ''We'';'), '''We')));
  Assert.AreEqual('', Names(ItemsAt(WithCode('  // We'), '// We')));
end;

procedure TLspCompletionTests.WritesCompletionList;
var
  Items: TCompletionItems;
  Json: TJSONObject;
begin
  SetLength(Items.Items, 1);
  Items.Items[0].Name := 'Wert';
  Items.Items[0].Detail := 'TFoo';
  Items.Items[0].Kind := 6;
  Items.Incomplete := False;
  Json := TLspCompletion.ToJson(Items);
  try
    Assert.AreEqual('{"isIncomplete":false,"items":[{"label":"Wert","kind":6,"detail":"TFoo","sortText":"00000"}]}',
      Json.ToJSON);
  finally
    Json.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCompletionTests);

end.
