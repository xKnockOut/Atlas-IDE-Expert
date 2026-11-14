unit Atlas.Common.Lsp.CompletionWith.Tests;

// with-Bloecke durchschaubar (#481): Mitglieder der with-Objekte in der Liste mit Herkunft, innerstes Objekt
// zuerst, Warnung bei verdeckten lokalen Namen und Mitgliedern von Self, Schalter completion.withOrigin.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver,
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
  Atlas.Common.Lsp.Completion.Lists,
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex;

const
  cHauptFile = 'C:\P\Haupt.pas';

  cUnitHaupt =
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
  mIndex, mLine, mCharacter: Integer;
begin
  mLine := 0;
  mCharacter := 0;
  for mIndex := 1 to Pos('|', AMarked) - 1 do
  begin
    if AMarked[mIndex] = #10 then
    begin
      Inc(mLine);
      mCharacter := 0;
    end
    else
    begin
      Inc(mCharacter);
    end;
  end;
  APosition := TTextPosition.Create(mLine, mCharacter);
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
  mText: string;
  mPosition: TTextPosition;
  mTree: TSyntaxTree;
  mRequest: TCompletionRequest;
begin
  mText := Split(StringReplace(cUnitHaupt, '{ Code }', AMarked, []), mPosition);
  mTree := TPascalParser.Parse(mText);
  mRequest := TCompletionRequest.Create(mText, cHauptFile, mPosition);
  try
    mRequest.Tree := mTree;
    mRequest.Resolver := FResolver;
    mRequest.Index := FIndex;
    mRequest.Matching := TCompletionMatching.Prefix;
    mRequest.Settings := ASettings;
    Result := TCompletionLists.Collect(mRequest, Default(TPostfixOptions), nil);
  finally
    mRequest.Free;
    mTree.Free;
  end;
end;

function TCompletionWithTests.ItemsAt(const AMarked: string): TCompletionItems;
begin
  Result := ItemsAt(AMarked, TCompletionSettings.Default);
end;

function TCompletionWithTests.Find(const AItems: TCompletionItems; const AName: string;
  out AItem: TCompletionItem): Boolean;
var
  mItem: TCompletionItem;
begin
  for mItem in AItems.Items do
  begin
    if mItem.Name = AName then
    begin
      AItem := mItem;
      Exit(True);
    end;
  end;
  AItem := Default(TCompletionItem);
  Result := False;
end;

function TCompletionWithTests.Count(const AItems: TCompletionItems; const AName: string): Integer;
var
  mItem: TCompletionItem;
begin
  Result := 0;
  for mItem in AItems.Items do
  begin
    if SameText(mItem.Name, AName) then
    begin
      Inc(Result);
    end;
  end;
end;

procedure TCompletionWithTests.MembersCarryOrigin;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt('with qryOrders do'#10'    Op|');
  Assert.IsTrue(Find(mItems, 'Open', mItem), 'Mitglied des with-Objekts fehlt');
  Assert.AreEqual(6, mItem.Scope);
  Assert.AreEqual('qryOrders', mItem.WithOrigin);
  Assert.AreEqual(0, Integer(Length(mItem.WithShadows)), 'verdeckt nichts');
end;

procedure TCompletionWithTests.WarnsAboutSelfAndLocals;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  // Akzeptanz: Name aus qryOrders verdeckt Self.Name.
  mItems := ItemsAt('with qryOrders do'#10'    Na|');
  Assert.AreEqual(1, Count(mItems, 'Name'), 'nur die Bedeutung, die gilt');
  Assert.IsTrue(Find(mItems, 'Name', mItem));
  Assert.AreEqual('qryOrders', mItem.WithOrigin);
  Assert.AreEqual('Self.Name', string.Join('|', mItem.WithShadows));
  Assert.AreEqual('Feld TForm1.Name', string.Join('|', mItem.Hides));
  // Lokale Variable.
  mItems := ItemsAt('with qryOrders do'#10'    Act|');
  Assert.IsTrue(Find(mItems, 'Active', mItem));
  Assert.AreEqual('lokale Variable Active', string.Join('|', mItem.WithShadows));
  // Self-Mitglied ohne Gegenstueck im with-Objekt bleibt Mitglied von Self.
  mItems := ItemsAt('with qryOrders do'#10'    Cap|');
  Assert.IsTrue(Find(mItems, 'Caption', mItem));
  Assert.AreEqual(3, mItem.Scope);
  Assert.AreEqual('', mItem.WithOrigin);
end;

procedure TCompletionWithTests.InnermostWithWins;
var
  mItem: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('with qryOrders do'#10'    with qryOther do'#10'      Na|'), 'Name', mItem));
  Assert.AreEqual('qryOther', mItem.WithOrigin);
  // with A, B: B zuerst.
  Assert.IsTrue(Find(ItemsAt('with qryOrders, qryOther do'#10'    Na|'), 'Name', mItem));
  Assert.AreEqual('qryOther', mItem.WithOrigin);
  Assert.AreEqual('Self.Name', string.Join('|', mItem.WithShadows));
end;

procedure TCompletionWithTests.HiddenMembersDoNotHideLocals;
var
  mItem: TCompletionItem;
begin
  // FSecret von TQuery ist strict private: die lokale Variable gilt.
  Assert.IsTrue(Find(ItemsAt('with qryOrders do'#10'    FSec|'), 'FSecret', mItem));
  Assert.AreEqual(1, mItem.Scope);
  Assert.AreEqual('', mItem.WithOrigin);
end;

procedure TCompletionWithTests.OutsideWithAsBefore;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt('with qryOrders do'#10'    Open;'#10'  Na|');
  Assert.IsTrue(Find(mItems, 'Name', mItem));
  Assert.AreEqual(3, mItem.Scope);
  Assert.AreEqual('', mItem.WithOrigin);
  Assert.IsFalse(Find(mItems, 'Open', mItem));
end;

procedure TCompletionWithTests.OriginIsSourceText;
var
  mItem: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('with Self.FQuery { Abfrage } do'#10'    Op|'), 'Open', mItem));
  Assert.AreEqual('Self.FQuery', mItem.WithOrigin);
end;

procedure TCompletionWithTests.WritesJson;
var
  mJson: TJSONObject;
  mText: string;
begin
  mJson := TLspCompletion.ToJson(ItemsAt('with qryOrders do'#10'    Na|'));
  try
    mText := mJson.ToJSON;
  finally
    mJson.Free;
  end;
  Assert.IsTrue(mText.Contains('"withOrigin":"qryOrders"'), mText);
  Assert.IsTrue(mText.Contains('"withShadows":["Self.Name"]'), mText);
  Assert.IsTrue(mText.Contains('"scope":6'), mText);
end;

procedure TCompletionWithTests.SwitchOff;
var
  mSettings: TCompletionSettings;
  mItem: TCompletionItem;
begin
  mSettings := TCompletionSettings.Default;
  mSettings.WithOrigin := False;
  // Das Mitglied gilt weiter (Compiler-Regel), nur ohne Herkunft.
  Assert.IsTrue(Find(ItemsAt('with qryOrders do'#10'    Na|', mSettings), 'Name', mItem));
  Assert.AreEqual(0, mItem.Scope);
  Assert.AreEqual('', mItem.WithOrigin);
  Assert.AreEqual(0, Integer(Length(mItem.WithShadows)));
end;

end.
