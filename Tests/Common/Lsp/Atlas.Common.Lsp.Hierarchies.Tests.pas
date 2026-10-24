unit Atlas.Common.Lsp.Hierarchies.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Hierarchies;

type
  [TestFixture]
  TLspHierarchiesTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function ItemAt(const AMarker: string; ACall: Boolean): THierarchyItem;
    function Names(const AItems: TArray<THierarchyItem>): string; overload;
    function Names(const ACalls: TArray<THierarchyCall>): string; overload;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure PrepareTypeFromVariableAndTypeName;
    [Test]
    procedure SupertypesFollowAncestorChain;
    [Test]
    procedure SubtypesAreDirectDescendants;
    [Test]
    procedure IncomingCallsGroupedByCaller;
    [Test]
    procedure OutgoingCallsFromBody;
    [Test]
    procedure ItemRoundTripsThroughJson;
    [Test]
    procedure OutgoingCallsMarkInterfaceAndVirtual;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.ReferenceConfidence;

const
  HauptFile = 'C:\P\Haupt.pas';
  WerkzeugFile = 'C:\P\Werkzeug.pas';

  UnitWerkzeug =
    'unit Werkzeug;'#10 +
    'interface'#10 +
    'type'#10 +
    '  IZaehlbar = interface'#10 +
    '  end;'#10 +
    '  TBasis = class'#10 +
    '  end;'#10 +
    'procedure Rechne;'#10 +
    'implementation'#10 +
    'procedure Rechne;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Werkzeug;'#10 +
    'type'#10 +
    '  TFoo = class(TBasis, IZaehlbar)'#10 +
    '    procedure Bar;'#10 +
    '    procedure Baz;'#10 +
    '  end;'#10 +
    '  TKind = class(TFoo)'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Bar;'#10 +
    'var'#10 +
    '  Wert: TKind;'#10 +
    'begin'#10 +
    '  Rechne;'#10 +
    '  Baz;'#10 +
    '  Rechne;'#10 +
    'end;'#10 +
    'procedure TFoo.Baz;'#10 +
    'begin'#10 +
    '  Rechne;'#10 +
    'end;'#10 +
    'end.';

  DispatchFile = 'C:\P\Ablauf.pas';

  // Aufrufe über ein Interface (zwei Umsetzungen) und eine virtuelle Methode (Basis und eine Überschreibung;
  // TSpaet erbt nur), dazu ein gewöhnlicher Aufruf (#1122).
  UnitDispatch =
    'unit Ablauf;'#10 +
    'interface'#10 +
    'type'#10 +
    '  ISpeicher = interface'#10 +
    '    procedure Speichern;'#10 +
    '  end;'#10 +
    '  TDatei = class(TInterfacedObject, ISpeicher)'#10 +
    '    procedure Speichern;'#10 +
    '  end;'#10 +
    '  TNetz = class(TInterfacedObject, ISpeicher)'#10 +
    '    procedure Speichern;'#10 +
    '  end;'#10 +
    '  TLader = class'#10 +
    '    procedure Laden; virtual;'#10 +
    '  end;'#10 +
    '  TSchnell = class(TLader)'#10 +
    '    procedure Laden; override;'#10 +
    '  end;'#10 +
    '  TSpaet = class(TSchnell)'#10 +
    '  end;'#10 +
    'procedure Ablauf(const S: ISpeicher; L: TLader);'#10 +
    'procedure Fertig;'#10 +
    'implementation'#10 +
    'procedure TDatei.Speichern; begin end;'#10 +
    'procedure TNetz.Speichern; begin end;'#10 +
    'procedure TLader.Laden; begin end;'#10 +
    'procedure TSchnell.Laden; begin end;'#10 +
    'procedure Fertig; begin end;'#10 +
    'procedure Ablauf(const S: ISpeicher; L: TLader);'#10 +
    'begin'#10 +
    '  S.Speichern;'#10 +
    '  L.Laden;'#10 +
    '  Fertig;'#10 +
    'end;'#10 +
    'end.';

function ReadDispatch(const AFileName: string; out AText: string): Boolean;
begin
  Result := SameText(AFileName, DispatchFile);
  if Result then
    AText := UnitDispatch;
end;

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  Index, Line, LineStart, Scan: Integer;
begin
  Index := Pos(AMarker, AText);
  if Index = 0 then
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
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

function ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, HauptFile) then
    AText := UnitHaupt
  else if SameText(AFileName, WerkzeugFile) then
    AText := UnitWerkzeug
  else
    Result := False;
end;

{ TLspHierarchiesTests }

procedure TLspHierarchiesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitWerkzeug, WerkzeugFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitHaupt, HauptFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspHierarchiesTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspHierarchiesTests.ItemAt(const AMarker: string; ACall: Boolean): THierarchyItem;
var
  Tree: TSyntaxTree;
  Found: Boolean;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    if ACall then
      Found := TLspHierarchies.CallItemAt(FResolver, Tree, HauptFile, PositionOf(UnitHaupt, AMarker), Result)
    else
      Found := TLspHierarchies.TypeItemAt(FResolver, Tree, HauptFile, PositionOf(UnitHaupt, AMarker), Result);
  finally
    Tree.Free;
  end;
  if not Found then
    raise Exception.CreateFmt('Kein Element bei "%s"', [AMarker]);
end;

function TLspHierarchiesTests.Names(const AItems: TArray<THierarchyItem>): string;
var
  Item: THierarchyItem;
begin
  Result := '';
  for Item in AItems do
    Result := Result + Item.Name + ' ';
  Result := Trim(Result);
end;

function TLspHierarchiesTests.Names(const ACalls: TArray<THierarchyCall>): string;
var
  Call: THierarchyCall;
begin
  Result := '';
  for Call in ACalls do
    Result := Result + Call.Item.Name + '(' + IntToStr(Length(Call.Ranges)) + ') ';
  Result := Trim(Result);
end;

procedure TLspHierarchiesTests.PrepareTypeFromVariableAndTypeName;
var
  Item: THierarchyItem;
begin
  Item := ItemAt('Wert', False);
  Assert.AreEqual('TKind', Item.Name);
  Assert.AreEqual(5, Item.LspKind);
  Item := ItemAt('TBasis, IZaehlbar', False);
  Assert.AreEqual('TBasis', Item.Name);
  Assert.AreEqual(WerkzeugFile, Item.FileName);
end;

procedure TLspHierarchiesTests.SupertypesFollowAncestorChain;
var
  Supers: TArray<THierarchyItem>;
begin
  Supers := TLspHierarchies.Supertypes(FResolver, ItemAt('Wert', False), ReadFile);
  Assert.AreEqual('TFoo', Names(Supers));
  Supers := TLspHierarchies.Supertypes(FResolver, Supers[0], ReadFile);
  Assert.AreEqual('TBasis IZaehlbar', Names(Supers));
  Assert.AreEqual(11, Supers[1].LspKind);
  // TObject steht nicht im Index: die Kette endet bei TBasis.
  Assert.AreEqual('', Names(TLspHierarchies.Supertypes(FResolver, Supers[0], ReadFile)));
end;

procedure TLspHierarchiesTests.SubtypesAreDirectDescendants;
begin
  Assert.AreEqual('TFoo', Names(TLspHierarchies.Subtypes(FIndex, ItemAt('TBasis, IZaehlbar', False))));
  Assert.AreEqual('TKind', Names(TLspHierarchies.Subtypes(FIndex, ItemAt('TFoo)', False))));
end;

procedure TLspHierarchiesTests.IncomingCallsGroupedByCaller;
var
  Item: THierarchyItem;
  Calls: TArray<THierarchyCall>;
begin
  Item := ItemAt('Rechne;'#10'  Baz', True);
  Assert.AreEqual(WerkzeugFile, Item.FileName);
  Calls := TLspHierarchies.IncomingCalls(FResolver, FIndex, Item, [HauptFile, WerkzeugFile], ReadFile);
  Assert.AreEqual('Bar(2) Baz(1)', Names(Calls));
  Assert.AreEqual('TFoo', Calls[0].Item.Container);
  Assert.AreEqual(15, Calls[0].Ranges[0].StartPos.Line);
  // Auswahl ist der Name im Kopf (procedure TFoo.Bar), nicht der Anfang der Routine (#1120).
  Assert.AreEqual(11, Calls[0].Item.SelectionRange.StartPos.Line);
  Assert.AreEqual(15, Calls[0].Item.SelectionRange.StartPos.Character);
  Assert.AreEqual(18, Calls[0].Item.SelectionRange.EndPos.Character);
  // Der Kopf von TFoo.Baz ist kein Aufruf von Baz.
  Assert.AreEqual('Bar(1)', Names(TLspHierarchies.IncomingCalls(FResolver, FIndex, ItemAt('Baz;'#10'  end', True),
    [HauptFile, WerkzeugFile], ReadFile)));
end;

procedure TLspHierarchiesTests.OutgoingCallsFromBody;
begin
  Assert.AreEqual('Rechne(2) Baz(1)', Names(TLspHierarchies.OutgoingCalls(FResolver,
    ItemAt('Bar;'#10'    procedure', True), ReadFile)));
end;

procedure TLspHierarchiesTests.ItemRoundTripsThroughJson;
var
  Item, Back: THierarchyItem;
  Json: TJSONObject;
begin
  Item := ItemAt('Baz;'#10'  end', True);
  Json := TLspHierarchies.ItemToJson(Item);
  try
    Assert.IsTrue(TLspHierarchies.ItemFromJson(Json, Back));
  finally
    Json.Free;
  end;
  Assert.AreEqual('Baz', Back.Name);
  Assert.AreEqual('TFoo', Back.Container);
  Assert.AreEqual(Ord(Item.SymbolKind), Ord(Back.SymbolKind));
  Assert.AreEqual(Item.SelectionRange.StartPos.Line, Back.SelectionRange.StartPos.Line);
  Assert.AreEqual(HauptFile, Back.FileName);
end;

procedure TLspHierarchiesTests.OutgoingCallsMarkInterfaceAndVirtual;
var
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  Tree: TSyntaxTree;
  Item: THierarchyItem;
  Calls: TArray<THierarchyCall>;
  Json: TJSONArray;
  Dispatch: TJSONValue;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(UnitDispatch, DispatchFile, nil));
  Resolver := TNameResolver.Create(Index);
  try
    Tree := TPascalParser.Parse(UnitDispatch);
    try
      Assert.IsTrue(TLspHierarchies.CallItemAt(Resolver, Tree, DispatchFile,
        PositionOf(UnitDispatch, 'Ablauf(const S: ISpeicher; L: TLader);'#10'begin'), Item));
    finally
      Tree.Free;
    end;
    Calls := TLspHierarchies.OutgoingCalls(Resolver, Index, Item, ReadDispatch, nil);
    Assert.AreEqual('Speichern(1) Laden(1) Fertig(1)', Names(Calls));
    Assert.AreEqual(Ord(TReferenceReason.Interface_), Ord(Calls[0].Dispatch));
    Assert.AreEqual(2, Calls[0].Implementations);
    Assert.AreEqual(Ord(TReferenceReason.Virtual), Ord(Calls[1].Dispatch));
    Assert.AreEqual(2, Calls[1].Implementations);
    Assert.AreEqual(Ord(TReferenceReason.None), Ord(Calls[2].Dispatch));
    Json := TLspHierarchies.CallsToJson(Calls, 'to');
    try
      Dispatch := Json.Items[0].FindValue('atlasDispatch');
      Assert.IsNotNull(Dispatch);
      Assert.AreEqual('interface', Dispatch.GetValue<string>('kind'));
      Assert.AreEqual(2, Dispatch.GetValue<Integer>('implementations'));
      Assert.AreEqual('virtual', Json.Items[1].GetValue<string>('atlasDispatch.kind'));
      Assert.IsNull(Json.Items[2].FindValue('atlasDispatch'));
    finally
      Json.Free;
    end;
    // Ohne Index wie bisher: keine Kennzeichnung.
    Calls := TLspHierarchies.OutgoingCalls(Resolver, Item, ReadDispatch);
    Assert.AreEqual(Ord(TReferenceReason.None), Ord(Calls[0].Dispatch));
  finally
    Resolver.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspHierarchiesTests);

end.
