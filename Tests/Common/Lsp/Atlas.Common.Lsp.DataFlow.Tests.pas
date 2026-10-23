unit Atlas.Common.Lsp.DataFlow.Tests;

// Datenfluss (#690): Woher bei Lokalen, Feldern, Parametern über mehrere Aufrufer, Funktionsergebnissen,
// var-/out-Parametern, Property-Settern; Zyklen, Zusammenfassen gleicher Stellen, unsichere Kanten,
// Filter für Tests und die Gegenrichtung (Wohin).

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.DataFlow;

type
  [TestFixture]
  TLspDataFlowTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function Flow(const AFileName, AMarker: string; ADirection: TDataFlowDirection): TDataFlowResult; overload;
    function Flow(const AFileName, AMarker: string; ADirection: TDataFlowDirection;
      const AOptions: TDataFlowOptions): TDataFlowResult; overload;
    function Describe(const AResult: TDataFlowResult): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure LocalAssignmentsAreGrouped;
    [Test]
    procedure FunctionResultFromResultAndExit;
    [Test]
    procedure ParameterFromAllCallers;
    [Test]
    procedure VarAndOutArguments;
    [Test]
    procedure OutParameterHasNoCallers;
    [Test]
    procedure ExternalInputAndMoveAndCycle;
    [Test]
    procedure PropertySetterReachesAssignments;
    [Test]
    procedure PropertyAssignmentAndReadField;
    [Test]
    procedure FieldWrittenBySetter;
    [Test]
    procedure AddressIsUnsafe;
    [Test]
    procedure TargetsOfVariable;
    [Test]
    procedure TargetsOfLocalInFunction;
    [Test]
    procedure TestsCanBeExcluded;
    [Test]
    procedure PathMarksCycle;
    [Test]
    procedure InitializationAndLoop;
    [Test]
    procedure JsonShape;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

const
  DatenFile = 'C:\P\Daten.pas';
  HauptFile = 'C:\P\Haupt.pas';
  PruefFile = 'C:\P\Pruefung.pas';

  UnitDaten =
    'unit Daten;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '    procedure SetName(const AValue: string);'#10 +
    '  public'#10 +
    '    property Name: string read FName write SetName;'#10 +
    '  end;'#10 +
    'function Summe(A: Integer; var B: Integer; out C: Integer): Integer;'#10 +
    'procedure Lies(out AWert: Integer);'#10 +
    'implementation'#10 +
    'const'#10 +
    '  cMax = 10;'#10 +
    'function Summe(A: Integer; var B: Integer; out C: Integer): Integer;'#10 +
    'var'#10 +
    '  X: Integer;'#10 +
    'begin'#10 +
    '  X := A + B * cMax;'#10 +
    '  C := X;'#10 +
    '  Inc(B);'#10 +
    '  Result := X;'#10 +
    '  if X > 100 then'#10 +
    '    Exit(cMax);'#10 +
    'end;'#10 +
    'procedure Lies(out AWert: Integer);'#10 +
    'begin'#10 +
    '  ReadLn(AWert);'#10 +
    'end;'#10 +
    'procedure TKunde.SetName(const AValue: string);'#10 +
    'begin'#10 +
    '  FName := AValue;'#10 +
    'end;'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Daten;'#10 +
    'procedure Rechne;'#10 +
    'var'#10 +
    '  Wert, Neben, Ergebnis, Ziel, Zaehler: Integer;'#10 +
    '  Kunde: TKunde;'#10 +
    '  P: ^Integer;'#10 +
    'begin'#10 +
    '  Wert := 1;'#10 +
    '  Ergebnis := Summe(Wert, Neben, Ziel);'#10 +
    '  Ergebnis := Summe(2, Neben, Ziel);'#10 +
    '  Ergebnis := Summe(Wert, Neben, Ziel);'#10 +
    '  Lies(Zaehler);'#10 +
    '  Kunde.Name := ''Meier'';'#10 +
    '  P := @Wert;'#10 +
    '  Move(Wert, Zaehler, 4);'#10 +
    '  Zaehler := Zaehler + 1;'#10 +
    '  for var I := Wert to Zaehler do'#10 +
    '    ;'#10 +
    '  var Kopie := Ergebnis * 2;'#10 +
    'end;'#10 +
    'end.';

  UnitPruefung =
    'unit Pruefung;'#10 +
    'interface'#10 +
    'uses DUnitX.TestFramework, Daten;'#10 +
    'implementation'#10 +
    'procedure Probe;'#10 +
    'var'#10 +
    '  N, Z: Integer;'#10 +
    'begin'#10 +
    '  Summe(7, N, Z);'#10 +
    'end;'#10 +
    'end.';

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
  if SameText(AFileName, DatenFile) then
    AText := UnitDaten
  else if SameText(AFileName, HauptFile) then
    AText := UnitHaupt
  else if SameText(AFileName, PruefFile) then
    AText := UnitPruefung
  else
    Result := False;
end;

{ TLspDataFlowTests }

procedure TLspDataFlowTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitDaten, DatenFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitHaupt, HauptFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitPruefung, PruefFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspDataFlowTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspDataFlowTests.Flow(const AFileName, AMarker: string; ADirection: TDataFlowDirection): TDataFlowResult;
begin
  Result := Flow(AFileName, AMarker, ADirection, Default(TDataFlowOptions));
end;

function TLspDataFlowTests.Flow(const AFileName, AMarker: string; ADirection: TDataFlowDirection;
  const AOptions: TDataFlowOptions): TDataFlowResult;
var
  Text: string;
  Tree: TSyntaxTree;
begin
  ReadFile(AFileName, Text);
  Tree := TSyntaxTreeCache.Parse(Text);
  try
    Result := TLspDataFlow.Analyze(FResolver, FIndex, Tree, AFileName, PositionOf(Text, AMarker), ADirection, AOptions,
      TArray<string>.Create(DatenFile, HauptFile, PruefFile), ReadFile, nil);
  finally
    Tree.Free;
  end;
end;

function TLspDataFlowTests.Describe(const AResult: TDataFlowResult): string;
var
  Node: TDataFlowNode;
  Source: TDataFlowSymbol;
  Line: string;
begin
  // "kind[detail](via)xN<-Quelle/leaf,…" je Knoten, mit "; " verbunden.
  Result := '';
  for Node in AResult.Nodes do
  begin
    Line := TLspDataFlow.KindName(Node.Kind) + '[' + Node.Detail + ']';
    if Node.Via <> '' then
      Line := Line + '(' + Node.Via + ')';
    if Length(Node.Places) > 1 then
      Line := Line + 'x' + IntToStr(Length(Node.Places));
    if Node.Literal then
      Line := Line + '!lit';
    if Node.Unsafe then
      Line := Line + '!' + Node.UnsafeReason;
    if Length(Node.Sources) > 0 then
    begin
      Line := Line + '<-';
      for Source in Node.Sources do
      begin
        Line := Line + Source.Name;
        if Source.Leaf <> TDataFlowLeaf.None then
          Line := Line + '/' + TLspDataFlow.LeafName(Source.Leaf);
        Line := Line + ',';
      end;
      SetLength(Line, Length(Line) - 1);
    end;
    if Result <> '' then
      Result := Result + '; ';
    Result := Result + Line;
  end;
end;

procedure TLspDataFlowTests.LocalAssignmentsAreGrouped;
var
  Flowed: TDataFlowResult;
begin
  Flowed := Flow(HauptFile, 'Ergebnis :=', TDataFlowDirection.Sources);
  Assert.IsTrue(Flowed.Found);
  Assert.AreEqual('Ergebnis', Flowed.Symbol.Name);
  Assert.AreEqual('assignment[Summe(Wert, Neben, Ziel)]x2<-Summe; assignment[Summe(2, Neben, Ziel)]<-Summe',
    Describe(Flowed));
  Assert.AreEqual(11, Flowed.Nodes[0].Places[0].Position.Line);
  Assert.AreEqual(13, Flowed.Nodes[0].Places[1].Position.Line);
  Assert.AreEqual('Ergebnis := Summe(Wert, Neben, Ziel);', Flowed.Nodes[0].Places[0].LineText);
end;

procedure TLspDataFlowTests.FunctionResultFromResultAndExit;
begin
  Assert.AreEqual('return[X]<-X; return[cMax](Exit)<-cMax/constant',
    Describe(Flow(HauptFile, 'Summe(Wert', TDataFlowDirection.Sources)));
  // Result steht für die Funktion selbst.
  Assert.AreEqual('return[X]<-X; return[cMax](Exit)<-cMax/constant',
    Describe(Flow(DatenFile, 'Result := X', TDataFlowDirection.Sources)));
end;

procedure TLspDataFlowTests.ParameterFromAllCallers;
begin
  Assert.AreEqual('callerArgument[Wert](Summe)x2<-Wert; callerArgument[2](Summe)!lit; callerArgument[7](Summe)!lit',
    Describe(Flow(DatenFile, 'A + B', TDataFlowDirection.Sources)));
end;

procedure TLspDataFlowTests.VarAndOutArguments;
begin
  Assert.AreEqual('varArgument[Summe(Wert, Neben, Ziel)](Summe)x2<-B; varArgument[Summe(2, Neben, Ziel)](Summe)<-B',
    Describe(Flow(HauptFile, 'Neben, Ergebnis', TDataFlowDirection.Sources)));
  Assert.AreEqual('outArgument[Summe(Wert, Neben, Ziel)](Summe)x2<-C; outArgument[Summe(2, Neben, Ziel)](Summe)<-C',
    Describe(Flow(HauptFile, 'Ziel, Zaehler', TDataFlowDirection.Sources)));
  // var-Parameter: Inc im Rumpf und die Argumente der Aufrufer.
  Assert.AreEqual('modify[Inc(B)](Inc)<-B/cycle; callerArgument[Neben](Summe)x3<-Neben; callerArgument[N](Summe)<-N',
    Describe(Flow(DatenFile, 'B * cMax', TDataFlowDirection.Sources)));
end;

procedure TLspDataFlowTests.OutParameterHasNoCallers;
begin
  Assert.AreEqual('assignment[X]<-X', Describe(Flow(DatenFile, 'C := X', TDataFlowDirection.Sources)));
end;

procedure TLspDataFlowTests.ExternalInputAndMoveAndCycle;
begin
  Assert.AreEqual('input[ReadLn(AWert)](ReadLn)', Describe(Flow(DatenFile, 'AWert);'#10'end',
    TDataFlowDirection.Sources)));
  Assert.AreEqual('outArgument[Lies(Zaehler)](Lies)<-AWert; assignment[Wert](Move)!move<-Wert; ' +
    'assignment[Zaehler + 1]!lit<-Zaehler/cycle', Describe(Flow(HauptFile, 'Zaehler :=', TDataFlowDirection.Sources)));
end;

procedure TLspDataFlowTests.PropertySetterReachesAssignments;
begin
  // AValue kommt über die Property Name, deren Setter SetName ist.
  Assert.AreEqual('propertyWrite[''Meier''](Name)!lit',
    Describe(Flow(DatenFile, 'AValue;', TDataFlowDirection.Sources)));
end;

procedure TLspDataFlowTests.PropertyAssignmentAndReadField;
begin
  Assert.AreEqual('assignment[''Meier''](SetName)!lit; propertyRead[read FName]<-FName',
    Describe(Flow(HauptFile, 'Name :=', TDataFlowDirection.Sources)));
end;

procedure TLspDataFlowTests.FieldWrittenBySetter;
begin
  Assert.AreEqual('assignment[AValue]<-AValue', Describe(Flow(DatenFile, 'FName := AValue',
    TDataFlowDirection.Sources)));
end;

procedure TLspDataFlowTests.AddressIsUnsafe;
var
  Flowed: TDataFlowResult;
begin
  Flowed := Flow(HauptFile, 'Wert :=', TDataFlowDirection.Sources);
  Assert.AreEqual('assignment[1]!lit; address[@Wert]!address', Describe(Flowed));
  Assert.IsTrue(Flowed.Nodes[1].Unsafe);
end;

procedure TLspDataFlowTests.TargetsOfVariable;
begin
  Assert.AreEqual('argument[Summe(Wert, Neben, Ziel)](Summe)x2<-A; assignment[P := @Wert]!address<-P; ' +
    'assignment[Zaehler](Move)!move<-Zaehler; loop[Wert]<-I',
    Describe(Flow(HauptFile, 'Wert :=', TDataFlowDirection.Targets)));
end;

procedure TLspDataFlowTests.TargetsOfLocalInFunction;
begin
  Assert.AreEqual('assignment[C := X]<-C; return[Result := X]<-Summe; use[]',
    Describe(Flow(DatenFile, 'X := A', TDataFlowDirection.Targets)));
  // Wohin geht das Ergebnis von Summe: in Ergebnis, bzw. verworfen im Test.
  Assert.AreEqual('assignment[Ergebnis := Summe(Wert, Neben, Ziel)]x2<-Ergebnis; ' +
    'assignment[Ergebnis := Summe(2, Neben, Ziel)]<-Ergebnis; use[]',
    Describe(Flow(DatenFile, 'Result := X', TDataFlowDirection.Targets)));
end;

procedure TLspDataFlowTests.TestsCanBeExcluded;
var
  Options: TDataFlowOptions;
begin
  Options := Default(TDataFlowOptions);
  Options.ExcludeTests := True;
  Assert.AreEqual('callerArgument[Wert](Summe)x2<-Wert; callerArgument[2](Summe)!lit',
    Describe(Flow(DatenFile, 'A + B', TDataFlowDirection.Sources, Options)));
  Options.ExcludeTests := False;
  Options.OnlyProject := True;
  Assert.AreEqual(3, Integer(Length(Flow(DatenFile, 'A + B', TDataFlowDirection.Sources, Options).Nodes)));
end;

procedure TLspDataFlowTests.PathMarksCycle;
var
  Options: TDataFlowOptions;
  Flowed: TDataFlowResult;
begin
  Flowed := Flow(HauptFile, 'Summe(Wert', TDataFlowDirection.Sources);
  Options := Default(TDataFlowOptions);
  Options.Path := TArray<string>.Create(Flowed.Symbol.Key);
  // Von X aus führt der Weg zurück zu A, B und cMax; Summe steht schon im Pfad.
  Flowed := Flow(DatenFile, 'X := A', TDataFlowDirection.Targets, Options);
  Assert.AreEqual('assignment[C := X]<-C; return[Result := X]<-Summe/cycle; use[]', Describe(Flowed));
end;

procedure TLspDataFlowTests.InitializationAndLoop;
begin
  Assert.AreEqual('initialization[Ergebnis * 2]!lit<-Ergebnis', Describe(Flow(HauptFile, 'Kopie',
    TDataFlowDirection.Sources)));
  Assert.AreEqual('loop[Wert .. Zaehler]<-Wert,Zaehler', Describe(Flow(HauptFile, 'I :=',
    TDataFlowDirection.Sources)));
end;

procedure TLspDataFlowTests.JsonShape;
var
  Json: TJSONObject;
  Node, Entry: TJSONObject;
begin
  Json := TLspDataFlow.ToJson(Flow(HauptFile, 'Zaehler :=', TDataFlowDirection.Sources));
  try
    Assert.IsTrue(Json.GetValue<Boolean>('found'));
    Assert.AreEqual('Zaehler', Json.GetValue<string>('symbol.name'));
    Node := Json.GetValue<TJSONArray>('nodes').Items[2] as TJSONObject;
    Assert.AreEqual('assignment', Node.GetValue<string>('kind'));
    Assert.AreEqual('Zaehler + 1', Node.GetValue<string>('detail'));
    Entry := Node.GetValue<TJSONArray>('sources').Items[0] as TJSONObject;
    Assert.AreEqual('cycle', Entry.GetValue<string>('leaf'));
    Entry := Node.GetValue<TJSONArray>('places').Items[0] as TJSONObject;
    Assert.AreEqual(18, Entry.GetValue<Integer>('line'));
    Assert.AreEqual('Zaehler := Zaehler + 1;', Entry.GetValue<string>('lineText'));
    Node := Json.GetValue<TJSONArray>('nodes').Items[1] as TJSONObject;
    Assert.IsTrue(Node.GetValue<Boolean>('unsafe'));
    Assert.AreEqual('move', Node.GetValue<string>('unsafeReason'));
  finally
    Json.Free;
  end;
end;

end.
