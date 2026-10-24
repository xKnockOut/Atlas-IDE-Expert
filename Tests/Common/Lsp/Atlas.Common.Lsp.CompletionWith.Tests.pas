unit Atlas.Common.Lsp.CompletionWith.Tests;

// with-Bloecke durchschaubar (#481): Mitglieder der with-Objekte in der Liste mit Herkunft, innerstes Objekt
// zuerst, Warnung bei verdeckten lokalen Namen und Mitgliedern von Self, Schalter completion.withOrigin.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.Completion;

type
  [TestFixture]
  TCompletionWithTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function ItemsAt(const AMarked: string; const ASettings: TCompletionSettings): TCompletionItems; overload;
    function ItemsAt(const AMarked: string): TCompletionItems; overload;
    function Find(const AItems: TCompletionItems; const AName: string; out AItem: TCompletionItem): Boolean;
    function Count(const AItems: TCompletionItems; const AName: string): Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MembersCarryOrigin;
    [Test]
    procedure WarnsAboutSelfAndLocals;
    [Test]
    procedure InnermostWithWins;
    [Test]
    procedure HiddenMembersDoNotHideLocals;
    [Test]
    procedure OutsideWithAsBefore;
    [Test]
    procedure OriginIsSourceText;
    [Test]
    procedure WritesJson;
    [Test]
    procedure SwitchOff;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex;

const
  HauptFile = 'C:\P\Haupt.pas';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TQuery = class'#10 +
    '  strict private'#10 +
    '    FSecret: Integer;'#10 +
    '  public'#10 +
    '    Name: string;'#10 +
    '    Active: Boolean;'#10 +
    '    procedure Open;'#10 +
    '  end;'#10 +
    '  TForm1 = class'#10 +
    '  public'#10 +
    '    Name: string;'#10 +
    '    Caption: string;'#10 +
    '    FQuery: TQuery;'#10 +
    '    procedure Run;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TQuery.Open;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TForm1.Run;'#10 +
    'var'#10 +
    '  qryOrders, qryOther: TQuery;'#10 +
    '  Active: Boolean;'#10 +
    '  FSecret: Integer;'#10 +
    'begin'#10 +
    '  { Code }'#10 +
    'end;'#10 +
    'end.';

/// <summary>Text ohne "|" und die Position des "|".</summary>
function Split(const AMarked: string; out APosition: TTextPosition): string;
var
  Index, Line, Character: Integer;
begin
  Line := 0;
  Character := 0;
  for Index := 1 to Pos('|', AMarked) - 1 do
    if AMarked[Index] = #10 then
    begin
      Inc(Line);
      Character := 0;
    end
    else
      Inc(Character);
  APosition := TTextPosition.Create(Line, Character);
  Result := StringReplace(AMarked, '|', '', []);
end;

{ TCompletionWithTests }

procedure TCompletionWithTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TCompletionWithTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TCompletionWithTests.ItemsAt(const AMarked: string; const ASettings: TCompletionSettings): TCompletionItems;
var
  Text: string;
  Position: TTextPosition;
  Tree: TSyntaxTree;
  Request: TCompletionRequest;
begin
  Text := Split(StringReplace(UnitHaupt, '{ Code }', AMarked, []), Position);
  Tree := TPascalParser.Parse(Text);
  Request := TCompletionRequest.Create(Text, HauptFile, Position);
  try
    Request.Tree := Tree;
    Request.Resolver := FResolver;
    Request.Index := FIndex;
    Request.Matching := TCompletionMatching.Prefix;
    Request.Settings := ASettings;
    Result := TLspCompletion.Collect(Request, Default(TPostfixOptions), nil);
  finally
    Request.Free;
    Tree.Free;
  end;
end;

function TCompletionWithTests.ItemsAt(const AMarked: string): TCompletionItems;
begin
  Result := ItemsAt(AMarked, TCompletionSettings.Default);
end;

function TCompletionWithTests.Find(const AItems: TCompletionItems; const AName: string;
  out AItem: TCompletionItem): Boolean;
var
  Item: TCompletionItem;
begin
  for Item in AItems.Items do
    if Item.Name = AName then
    begin
      AItem := Item;
      Exit(True);
    end;
  AItem := Default(TCompletionItem);
  Result := False;
end;

function TCompletionWithTests.Count(const AItems: TCompletionItems; const AName: string): Integer;
var
  Item: TCompletionItem;
begin
  Result := 0;
  for Item in AItems.Items do
    if SameText(Item.Name, AName) then
      Inc(Result);
end;

procedure TCompletionWithTests.MembersCarryOrigin;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Items := ItemsAt('with qryOrders do'#10'    Op|');
  Assert.IsTrue(Find(Items, 'Open', Item), 'Mitglied des with-Objekts fehlt');
  Assert.AreEqual(6, Item.Scope);
  Assert.AreEqual('qryOrders', Item.WithOrigin);
  Assert.AreEqual(0, Integer(Length(Item.WithShadows)), 'verdeckt nichts');
end;

procedure TCompletionWithTests.WarnsAboutSelfAndLocals;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  // Akzeptanz: Name aus qryOrders verdeckt Self.Name.
  Items := ItemsAt('with qryOrders do'#10'    Na|');
  Assert.AreEqual(1, Count(Items, 'Name'), 'nur die Bedeutung, die gilt');
  Assert.IsTrue(Find(Items, 'Name', Item));
  Assert.AreEqual('qryOrders', Item.WithOrigin);
  Assert.AreEqual('Self.Name', string.Join('|', Item.WithShadows));
  Assert.AreEqual('Feld TForm1.Name', string.Join('|', Item.Hides));
  // Lokale Variable.
  Items := ItemsAt('with qryOrders do'#10'    Act|');
  Assert.IsTrue(Find(Items, 'Active', Item));
  Assert.AreEqual('lokale Variable Active', string.Join('|', Item.WithShadows));
  // Self-Mitglied ohne Gegenstueck im with-Objekt bleibt Mitglied von Self.
  Items := ItemsAt('with qryOrders do'#10'    Cap|');
  Assert.IsTrue(Find(Items, 'Caption', Item));
  Assert.AreEqual(3, Item.Scope);
  Assert.AreEqual('', Item.WithOrigin);
end;

procedure TCompletionWithTests.InnermostWithWins;
var
  Item: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('with qryOrders do'#10'    with qryOther do'#10'      Na|'), 'Name', Item));
  Assert.AreEqual('qryOther', Item.WithOrigin);
  // with A, B: B zuerst.
  Assert.IsTrue(Find(ItemsAt('with qryOrders, qryOther do'#10'    Na|'), 'Name', Item));
  Assert.AreEqual('qryOther', Item.WithOrigin);
  Assert.AreEqual('Self.Name', string.Join('|', Item.WithShadows));
end;

procedure TCompletionWithTests.HiddenMembersDoNotHideLocals;
var
  Item: TCompletionItem;
begin
  // FSecret von TQuery ist strict private: die lokale Variable gilt.
  Assert.IsTrue(Find(ItemsAt('with qryOrders do'#10'    FSec|'), 'FSecret', Item));
  Assert.AreEqual(1, Item.Scope);
  Assert.AreEqual('', Item.WithOrigin);
end;

procedure TCompletionWithTests.OutsideWithAsBefore;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Items := ItemsAt('with qryOrders do'#10'    Open;'#10'  Na|');
  Assert.IsTrue(Find(Items, 'Name', Item));
  Assert.AreEqual(3, Item.Scope);
  Assert.AreEqual('', Item.WithOrigin);
  Assert.IsFalse(Find(Items, 'Open', Item));
end;

procedure TCompletionWithTests.OriginIsSourceText;
var
  Item: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('with Self.FQuery { Abfrage } do'#10'    Op|'), 'Open', Item));
  Assert.AreEqual('Self.FQuery', Item.WithOrigin);
end;

procedure TCompletionWithTests.WritesJson;
var
  Json: TJSONObject;
  Text: string;
begin
  Json := TLspCompletion.ToJson(ItemsAt('with qryOrders do'#10'    Na|'));
  try
    Text := Json.ToJSON;
  finally
    Json.Free;
  end;
  Assert.IsTrue(Text.Contains('"withOrigin":"qryOrders"'), Text);
  Assert.IsTrue(Text.Contains('"withShadows":["Self.Name"]'), Text);
  Assert.IsTrue(Text.Contains('"scope":6'), Text);
end;

procedure TCompletionWithTests.SwitchOff;
var
  Settings: TCompletionSettings;
  Item: TCompletionItem;
begin
  Settings := TCompletionSettings.Default;
  Settings.WithOrigin := False;
  // Das Mitglied gilt weiter (Compiler-Regel), nur ohne Herkunft.
  Assert.IsTrue(Find(ItemsAt('with qryOrders do'#10'    Na|', Settings), 'Name', Item));
  Assert.AreEqual(0, Item.Scope);
  Assert.AreEqual('', Item.WithOrigin);
  Assert.AreEqual(0, Integer(Length(Item.WithShadows)));
end;

end.
