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
  cHauptFile = 'C:\P\Haupt.pas';
  cWerkzeugFile = 'C:\P\Werkzeug.pas';

  cUnitWerkzeug =
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

  cUnitHaupt =
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

  cDispatchFile = 'C:\P\Ablauf.pas';

  // Aufrufe über ein Interface (zwei Umsetzungen) und eine virtuelle Methode (Basis und eine Überschreibung;
  // TSpaet erbt nur), dazu ein gewöhnlicher Aufruf (#1122).
  cUnitDispatch =
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
  Result := SameText(AFileName, cDispatchFile);
  if Result then
  begin
    AText := cUnitDispatch;
  end;
end;

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  mIndex, mLine, mLineStart, mScan: Integer;
begin
  mIndex := Pos(AMarker, AText);
  if mIndex = 0 then
  begin
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  end;
  mLine := 0;
  mLineStart := 1;
  for mScan := 1 to mIndex - 1 do
  begin
    if AText[mScan] = #10 then
    begin
      Inc(mLine);
      mLineStart := mScan + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

function ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, cHauptFile) then
  begin
    AText := cUnitHaupt;
  end
  else if SameText(AFileName, cWerkzeugFile) then
  begin
    AText := cUnitWerkzeug;
  end
  else
  begin
    Result := False;
  end;
end;

{ TLspHierarchiesTests }

procedure TLspHierarchiesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitWerkzeug, cWerkzeugFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitHaupt, cHauptFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspHierarchiesTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspHierarchiesTests.ItemAt(const AMarker: string; ACall: Boolean): THierarchyItem;
var
  mTree: TSyntaxTree;
  mFound: Boolean;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    if ACall then
    begin
      mFound := TLspHierarchies.CallItemAt(FResolver, mTree, cHauptFile, PositionOf(cUnitHaupt, AMarker), Result);
    end
    else
    begin
      mFound := TLspHierarchies.TypeItemAt(FResolver, mTree, cHauptFile, PositionOf(cUnitHaupt, AMarker), Result);
    end;
  finally
    mTree.Free;
  end;
  if not mFound then
  begin
    raise Exception.CreateFmt('Kein Element bei "%s"', [AMarker]);
  end;
end;

function TLspHierarchiesTests.Names(const AItems: TArray<THierarchyItem>): string;
var
  mItem: THierarchyItem;
begin
  Result := '';
  for mItem in AItems do
  begin
    Result := Result + mItem.Name + ' ';
  end;
  Result := Trim(Result);
end;

function TLspHierarchiesTests.Names(const ACalls: TArray<THierarchyCall>): string;
var
  mCall: THierarchyCall;
begin
  Result := '';
  for mCall in ACalls do
  begin
    Result := Result + mCall.Item.Name + '(' + IntToStr(Length(mCall.Ranges)) + ') ';
  end;
  Result := Trim(Result);
end;

procedure TLspHierarchiesTests.PrepareTypeFromVariableAndTypeName;
var
  mItem: THierarchyItem;
begin
  mItem := ItemAt('Wert', False);
  Assert.AreEqual('TKind', mItem.Name);
  Assert.AreEqual(5, mItem.LspKind);
  mItem := ItemAt('TBasis, IZaehlbar', False);
  Assert.AreEqual('TBasis', mItem.Name);
  Assert.AreEqual(cWerkzeugFile, mItem.FileName);
end;

procedure TLspHierarchiesTests.SupertypesFollowAncestorChain;
var
  mSupers: TArray<THierarchyItem>;
begin
  mSupers := TLspHierarchies.Supertypes(FResolver, ItemAt('Wert', False), ReadFile);
  Assert.AreEqual('TFoo', Names(mSupers));
  mSupers := TLspHierarchies.Supertypes(FResolver, mSupers[0], ReadFile);
  Assert.AreEqual('TBasis IZaehlbar', Names(mSupers));
  Assert.AreEqual(11, mSupers[1].LspKind);
  // TObject steht nicht im Index: die Kette endet bei TBasis.
  Assert.AreEqual('', Names(TLspHierarchies.Supertypes(FResolver, mSupers[0], ReadFile)));
end;

procedure TLspHierarchiesTests.SubtypesAreDirectDescendants;
begin
  Assert.AreEqual('TFoo', Names(TLspHierarchies.Subtypes(FIndex, ItemAt('TBasis, IZaehlbar', False))));
  Assert.AreEqual('TKind', Names(TLspHierarchies.Subtypes(FIndex, ItemAt('TFoo)', False))));
end;

procedure TLspHierarchiesTests.IncomingCallsGroupedByCaller;
var
  mItem: THierarchyItem;
  mCalls: TArray<THierarchyCall>;
begin
  mItem := ItemAt('Rechne;'#10'  Baz', True);
  Assert.AreEqual(cWerkzeugFile, mItem.FileName);
  mCalls := TLspHierarchies.IncomingCalls(FResolver, FIndex, mItem, [cHauptFile, cWerkzeugFile], ReadFile);
  Assert.AreEqual('Bar(2) Baz(1)', Names(mCalls));
  Assert.AreEqual('TFoo', mCalls[0].Item.Container);
  Assert.AreEqual(15, mCalls[0].Ranges[0].StartPos.Line);
  // Auswahl ist der Name im Kopf (procedure TFoo.Bar), nicht der Anfang der Routine (#1120).
  Assert.AreEqual(11, mCalls[0].Item.SelectionRange.StartPos.Line);
  Assert.AreEqual(15, mCalls[0].Item.SelectionRange.StartPos.Character);
  Assert.AreEqual(18, mCalls[0].Item.SelectionRange.EndPos.Character);
  // Der Kopf von TFoo.Baz ist kein Aufruf von Baz.
  Assert.AreEqual('Bar(1)', Names(TLspHierarchies.IncomingCalls(FResolver, FIndex, ItemAt('Baz;'#10'  end', True),
    [cHauptFile, cWerkzeugFile], ReadFile)));
end;

procedure TLspHierarchiesTests.OutgoingCallsFromBody;
begin
  Assert.AreEqual('Rechne(2) Baz(1)', Names(TLspHierarchies.OutgoingCalls(FResolver,
    ItemAt('Bar;'#10'    procedure', True), ReadFile)));
end;

procedure TLspHierarchiesTests.ItemRoundTripsThroughJson;
var
  mItem, mBack: THierarchyItem;
  mJson: TJSONObject;
begin
  mItem := ItemAt('Baz;'#10'  end', True);
  mJson := TLspHierarchies.ItemToJson(mItem);
  try
    Assert.IsTrue(TLspHierarchies.ItemFromJson(mJson, mBack));
  finally
    mJson.Free;
  end;
  Assert.AreEqual('Baz', mBack.Name);
  Assert.AreEqual('TFoo', mBack.Container);
  Assert.AreEqual(Ord(mItem.SymbolKind), Ord(mBack.SymbolKind));
  Assert.AreEqual(mItem.SelectionRange.StartPos.Line, mBack.SelectionRange.StartPos.Line);
  Assert.AreEqual(cHauptFile, mBack.FileName);
end;

procedure TLspHierarchiesTests.OutgoingCallsMarkInterfaceAndVirtual;
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mItem: THierarchyItem;
  mCalls: TArray<THierarchyCall>;
  mJson: TJSONArray;
  mDispatch: TJSONValue;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitDispatch, cDispatchFile, nil));
  mResolver := TNameResolver.Create(mIndex);
  try
    mTree := TPascalParser.Parse(cUnitDispatch);
    try
      Assert.IsTrue(TLspHierarchies.CallItemAt(mResolver, mTree, cDispatchFile,
        PositionOf(cUnitDispatch, 'Ablauf(const S: ISpeicher; L: TLader);'#10'begin'), mItem));
    finally
      mTree.Free;
    end;
    mCalls := TLspHierarchies.OutgoingCalls(mResolver, mIndex, mItem, ReadDispatch, nil);
    Assert.AreEqual('Speichern(1) Laden(1) Fertig(1)', Names(mCalls));
    Assert.AreEqual(Ord(TReferenceReason.Interface_), Ord(mCalls[0].Dispatch));
    Assert.AreEqual(2, mCalls[0].Implementations);
    Assert.AreEqual(Ord(TReferenceReason.Virtual), Ord(mCalls[1].Dispatch));
    Assert.AreEqual(2, mCalls[1].Implementations);
    Assert.AreEqual(Ord(TReferenceReason.None), Ord(mCalls[2].Dispatch));
    mJson := TLspHierarchies.CallsToJson(mCalls, 'to');
    try
      mDispatch := mJson.Items[0].FindValue('atlasDispatch');
      Assert.IsNotNull(mDispatch);
      Assert.AreEqual('interface', mDispatch.GetValue<string>('kind'));
      Assert.AreEqual(2, mDispatch.GetValue<Integer>('implementations'));
      Assert.AreEqual('virtual', mJson.Items[1].GetValue<string>('atlasDispatch.kind'));
      Assert.IsNull(mJson.Items[2].FindValue('atlasDispatch'));
    finally
      mJson.Free;
    end;
    // Ohne Index wie bisher: keine Kennzeichnung.
    mCalls := TLspHierarchies.OutgoingCalls(mResolver, mItem, ReadDispatch);
    Assert.AreEqual(Ord(TReferenceReason.None), Ord(mCalls[0].Dispatch));
  finally
    mResolver.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspHierarchiesTests);

end.
