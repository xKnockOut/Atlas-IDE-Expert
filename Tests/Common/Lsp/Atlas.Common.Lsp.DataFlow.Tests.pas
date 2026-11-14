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
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

const
  cDatenFile = 'C:\P\Daten.pas';
  cHauptFile = 'C:\P\Haupt.pas';
  cPruefFile = 'C:\P\Pruefung.pas';

  cUnitDaten =
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

  cUnitHaupt =
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

  cUnitPruefung =
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
  if SameText(AFileName, cDatenFile) then
  begin
    AText := cUnitDaten;
  end
  else if SameText(AFileName, cHauptFile) then
  begin
    AText := cUnitHaupt;
  end
  else if SameText(AFileName, cPruefFile) then
  begin
    AText := cUnitPruefung;
  end
  else
  begin
    Result := False;
  end;
end;

{ TLspDataFlowTests }

procedure TLspDataFlowTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitDaten, cDatenFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitHaupt, cHauptFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitPruefung, cPruefFile, nil));
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
  mText: string;
  mRequest: TDataFlowRequest;
begin
  ReadFile(AFileName, mText);
  mRequest := Default(TDataFlowRequest);
  mRequest.Resolver := FResolver;
  mRequest.Index := FIndex;
  mRequest.FileName := AFileName;
  mRequest.Position := PositionOf(mText, AMarker);
  mRequest.Direction := ADirection;
  mRequest.Options := AOptions;
  mRequest.Files := TArray<string>.Create(cDatenFile, cHauptFile, cPruefFile);
  mRequest.ReadText := ReadFile;
  mRequest.Tree := TSyntaxTreeCache.Parse(mText);
  try
    Result := TLspDataFlow.Analyze(mRequest);
  finally
    mRequest.Tree.Free;
  end;
end;

/// <summary>Quellen von ANode als "Quelle/leaf,…".</summary>
function SourcesText(const ANode: TDataFlowNode): string;
var
  mSource: TDataFlowSymbol;
begin
  Result := '';
  for mSource in ANode.Sources do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mSource.Name;
    if mSource.Leaf <> TDataFlowLeaf.None then
    begin
      Result := Result + '/' + TLspDataFlow.LeafName(mSource.Leaf);
    end;
  end;
end;

/// <summary>ANode als "kind[detail](via)xN!lit!grund&lt;-Quellen".</summary>
function NodeText(const ANode: TDataFlowNode): string;
begin
  Result := TLspDataFlow.KindName(ANode.Kind) + '[' + ANode.Detail + ']';
  if ANode.Via <> '' then
  begin
    Result := Result + '(' + ANode.Via + ')';
  end;
  if Length(ANode.Places) > 1 then
  begin
    Result := Result + 'x' + IntToStr(Length(ANode.Places));
  end;
  if ANode.Literal then
  begin
    Result := Result + '!lit';
  end;
  if ANode.Unsafe then
  begin
    Result := Result + '!' + ANode.UnsafeReason;
  end;
  if Length(ANode.Sources) > 0 then
  begin
    Result := Result + '<-' + SourcesText(ANode);
  end;
end;

function TLspDataFlowTests.Describe(const AResult: TDataFlowResult): string;
var
  mNode: TDataFlowNode;
begin
  // "kind[detail](via)xN<-Quelle/leaf,…" je Knoten, mit "; " verbunden.
  Result := '';
  for mNode in AResult.Nodes do
  begin
    if Result <> '' then
    begin
      Result := Result + '; ';
    end;
    Result := Result + NodeText(mNode);
  end;
end;

procedure TLspDataFlowTests.LocalAssignmentsAreGrouped;
var
  mFlowed: TDataFlowResult;
begin
  mFlowed := Flow(cHauptFile, 'Ergebnis :=', TDataFlowDirection.Sources);
  Assert.IsTrue(mFlowed.Found);
  Assert.AreEqual('Ergebnis', mFlowed.Symbol.Name);
  Assert.AreEqual('assignment[Summe(Wert, Neben, Ziel)]x2<-Summe; assignment[Summe(2, Neben, Ziel)]<-Summe',
    Describe(mFlowed));
  Assert.AreEqual(11, mFlowed.Nodes[0].Places[0].Position.Line);
  Assert.AreEqual(13, mFlowed.Nodes[0].Places[1].Position.Line);
  Assert.AreEqual('Ergebnis := Summe(Wert, Neben, Ziel);', mFlowed.Nodes[0].Places[0].LineText);
end;

procedure TLspDataFlowTests.FunctionResultFromResultAndExit;
begin
  Assert.AreEqual('return[X]<-X; return[cMax](Exit)<-cMax/constant',
    Describe(Flow(cHauptFile, 'Summe(Wert', TDataFlowDirection.Sources)));
  // Result steht für die Funktion selbst.
  Assert.AreEqual('return[X]<-X; return[cMax](Exit)<-cMax/constant',
    Describe(Flow(cDatenFile, 'Result := X', TDataFlowDirection.Sources)));
end;

procedure TLspDataFlowTests.ParameterFromAllCallers;
begin
  Assert.AreEqual('callerArgument[Wert](Summe)x2<-Wert; callerArgument[2](Summe)!lit; callerArgument[7](Summe)!lit',
    Describe(Flow(cDatenFile, 'A + B', TDataFlowDirection.Sources)));
end;

procedure TLspDataFlowTests.VarAndOutArguments;
begin
  Assert.AreEqual('varArgument[Summe(Wert, Neben, Ziel)](Summe)x2<-B; varArgument[Summe(2, Neben, Ziel)](Summe)<-B',
    Describe(Flow(cHauptFile, 'Neben, Ergebnis', TDataFlowDirection.Sources)));
  Assert.AreEqual('outArgument[Summe(Wert, Neben, Ziel)](Summe)x2<-C; outArgument[Summe(2, Neben, Ziel)](Summe)<-C',
    Describe(Flow(cHauptFile, 'Ziel, Zaehler', TDataFlowDirection.Sources)));
  // var-Parameter: Inc im Rumpf und die Argumente der Aufrufer.
  Assert.AreEqual('modify[Inc(B)](Inc)<-B/cycle; callerArgument[Neben](Summe)x3<-Neben; callerArgument[N](Summe)<-N',
    Describe(Flow(cDatenFile, 'B * cMax', TDataFlowDirection.Sources)));
end;

procedure TLspDataFlowTests.OutParameterHasNoCallers;
begin
  Assert.AreEqual('assignment[X]<-X', Describe(Flow(cDatenFile, 'C := X', TDataFlowDirection.Sources)));
end;

procedure TLspDataFlowTests.ExternalInputAndMoveAndCycle;
begin
  Assert.AreEqual('input[ReadLn(AWert)](ReadLn)', Describe(Flow(cDatenFile, 'AWert);'#10'end',
    TDataFlowDirection.Sources)));
  Assert.AreEqual('outArgument[Lies(Zaehler)](Lies)<-AWert; assignment[Wert](Move)!move<-Wert; ' +
    'assignment[Zaehler + 1]!lit<-Zaehler/cycle', Describe(Flow(cHauptFile, 'Zaehler :=', TDataFlowDirection.Sources)));
end;

procedure TLspDataFlowTests.PropertySetterReachesAssignments;
begin
  // AValue kommt über die Property Name, deren Setter SetName ist.
  Assert.AreEqual('propertyWrite[''Meier''](Name)!lit',
    Describe(Flow(cDatenFile, 'AValue;', TDataFlowDirection.Sources)));
end;

procedure TLspDataFlowTests.PropertyAssignmentAndReadField;
begin
  Assert.AreEqual('assignment[''Meier''](SetName)!lit; propertyRead[read FName]<-FName',
    Describe(Flow(cHauptFile, 'Name :=', TDataFlowDirection.Sources)));
end;

procedure TLspDataFlowTests.FieldWrittenBySetter;
begin
  Assert.AreEqual('assignment[AValue]<-AValue', Describe(Flow(cDatenFile, 'FName := AValue',
    TDataFlowDirection.Sources)));
end;

procedure TLspDataFlowTests.AddressIsUnsafe;
var
  mFlowed: TDataFlowResult;
begin
  mFlowed := Flow(cHauptFile, 'Wert :=', TDataFlowDirection.Sources);
  Assert.AreEqual('assignment[1]!lit; address[@Wert]!address', Describe(mFlowed));
  Assert.IsTrue(mFlowed.Nodes[1].Unsafe);
end;

procedure TLspDataFlowTests.TargetsOfVariable;
begin
  Assert.AreEqual('argument[Summe(Wert, Neben, Ziel)](Summe)x2<-A; assignment[P := @Wert]!address<-P; ' +
    'assignment[Zaehler](Move)!move<-Zaehler; loop[Wert]<-I',
    Describe(Flow(cHauptFile, 'Wert :=', TDataFlowDirection.Targets)));
end;

procedure TLspDataFlowTests.TargetsOfLocalInFunction;
begin
  Assert.AreEqual('assignment[C := X]<-C; return[Result := X]<-Summe; use[]',
    Describe(Flow(cDatenFile, 'X := A', TDataFlowDirection.Targets)));
  // Wohin geht das Ergebnis von Summe: in Ergebnis, bzw. verworfen im Test.
  Assert.AreEqual('assignment[Ergebnis := Summe(Wert, Neben, Ziel)]x2<-Ergebnis; ' +
    'assignment[Ergebnis := Summe(2, Neben, Ziel)]<-Ergebnis; use[]',
    Describe(Flow(cDatenFile, 'Result := X', TDataFlowDirection.Targets)));
end;

procedure TLspDataFlowTests.TestsCanBeExcluded;
var
  mOptions: TDataFlowOptions;
begin
  mOptions := Default(TDataFlowOptions);
  mOptions.ExcludeTests := True;
  Assert.AreEqual('callerArgument[Wert](Summe)x2<-Wert; callerArgument[2](Summe)!lit',
    Describe(Flow(cDatenFile, 'A + B', TDataFlowDirection.Sources, mOptions)));
  mOptions.ExcludeTests := False;
  mOptions.OnlyProject := True;
  Assert.AreEqual(3, Integer(Length(Flow(cDatenFile, 'A + B', TDataFlowDirection.Sources, mOptions).Nodes)));
end;

procedure TLspDataFlowTests.PathMarksCycle;
var
  mOptions: TDataFlowOptions;
  mFlowed: TDataFlowResult;
begin
  mFlowed := Flow(cHauptFile, 'Summe(Wert', TDataFlowDirection.Sources);
  mOptions := Default(TDataFlowOptions);
  mOptions.Path := TArray<string>.Create(mFlowed.Symbol.Key);
  // Von X aus führt der Weg zurück zu A, B und cMax; Summe steht schon im Pfad.
  mFlowed := Flow(cDatenFile, 'X := A', TDataFlowDirection.Targets, mOptions);
  Assert.AreEqual('assignment[C := X]<-C; return[Result := X]<-Summe/cycle; use[]', Describe(mFlowed));
end;

procedure TLspDataFlowTests.InitializationAndLoop;
begin
  Assert.AreEqual('initialization[Ergebnis * 2]!lit<-Ergebnis', Describe(Flow(cHauptFile, 'Kopie',
    TDataFlowDirection.Sources)));
  Assert.AreEqual('loop[Wert .. Zaehler]<-Wert,Zaehler', Describe(Flow(cHauptFile, 'I :=',
    TDataFlowDirection.Sources)));
end;

procedure TLspDataFlowTests.JsonShape;
var
  mJson: TJSONObject;
  mNode, mEntry: TJSONObject;
begin
  mJson := TLspDataFlow.ToJson(Flow(cHauptFile, 'Zaehler :=', TDataFlowDirection.Sources));
  try
    Assert.IsTrue(mJson.GetValue<Boolean>('found'));
    Assert.AreEqual('Zaehler', mJson.GetValue<string>('symbol.name'));
    mNode := mJson.GetValue<TJSONArray>('nodes').Items[2] as TJSONObject;
    Assert.AreEqual('assignment', mNode.GetValue<string>('kind'));
    Assert.AreEqual('Zaehler + 1', mNode.GetValue<string>('detail'));
    mEntry := mNode.GetValue<TJSONArray>('sources').Items[0] as TJSONObject;
    Assert.AreEqual('cycle', mEntry.GetValue<string>('leaf'));
    mEntry := mNode.GetValue<TJSONArray>('places').Items[0] as TJSONObject;
    Assert.AreEqual(18, mEntry.GetValue<Integer>('line'));
    Assert.AreEqual('Zaehler := Zaehler + 1;', mEntry.GetValue<string>('lineText'));
    mNode := mJson.GetValue<TJSONArray>('nodes').Items[1] as TJSONObject;
    Assert.IsTrue(mNode.GetValue<Boolean>('unsafe'));
    Assert.AreEqual('move', mNode.GetValue<string>('unsafeReason'));
  finally
    mJson.Free;
  end;
end;

end.
