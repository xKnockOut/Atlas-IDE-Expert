unit Argus.Common.Lsp.Implementations.Tests;

interface

uses
  DUnitX.TestFramework,
  Argus.Common.Index.Contract,
  Argus.Common.Semantics.NameResolver,
  Argus.Common.Lsp.Definition,
  Argus.Common.Lsp.Implementations;

type
  [TestFixture]
  TLspImplementationsTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function TargetsAt(const AMarker: string; AOffset: Integer = 0): TArray<TDefinitionTarget>;
    function Lines(const ATargets: TArray<TDefinitionTarget>): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure VirtualMethodListsOwnAndOverridingBodies;
    [Test]
    procedure InterfaceMethodListsImplementingClasses;
    [Test]
    procedure TypeListsAllDescendants;
    [Test]
    procedure InheritedWithNameJumpsToAncestorBody;
    [Test]
    procedure BareInheritedUsesEnclosingMethod;
  end;

implementation

uses
  System.SysUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser,
  Argus.Common.Index.SymbolIndex,
  Argus.Common.Index.Extractor;

const
  HauptFile = 'C:\P\Haupt.pas';

  UnitHaupt =
    'unit Haupt;'#10 +                                     // 0
    'interface'#10 +                                       // 1
    'type'#10 +                                            // 2
    '  IZeichner = interface'#10 +                         // 3
    '    procedure Zeichne;'#10 +                          // 4
    '  end;'#10 +                                          // 5
    '  TBasis = class(TInterfacedObject, IZeichner)'#10 + // 6
    '    procedure Zeichne; virtual;'#10 +                 // 7
    '    procedure Leer; virtual; abstract;'#10 +          // 8
    '  end;'#10 +                                          // 9
    '  TMitte = class(TBasis)'#10 +                        // 10
    '    procedure Zeichne; override;'#10 +                // 11
    '  end;'#10 +                                          // 12
    '  TBlatt = class(TMitte)'#10 +                        // 13
    '    procedure Zeichne; override;'#10 +                // 14
    '    procedure Leer; override;'#10 +                   // 15
    '  end;'#10 +                                          // 16
    'implementation'#10 +                                  // 17
    'procedure TBasis.Zeichne;'#10 +                       // 18
    'begin'#10 +                                           // 19
    'end;'#10 +                                            // 20
    'procedure TMitte.Zeichne;'#10 +                       // 21
    'begin'#10 +                                           // 22
    '  inherited Zeichne;'#10 +                            // 23
    'end;'#10 +                                            // 24
    'procedure TBlatt.Zeichne;'#10 +                       // 25
    'begin'#10 +                                           // 26
    '  inherited;'#10 +                                    // 27
    'end;'#10 +                                            // 28
    'procedure TBlatt.Leer;'#10 +                          // 29
    'begin'#10 +                                           // 30
    'end;'#10 +                                            // 31
    'end.';

function PositionOf(const AText, AMarker: string; AOffset: Integer): TTextPosition;
var
  Index, Line, LineStart, Scan: Integer;
begin
  Index := Pos(AMarker, AText);
  if Index = 0 then
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  Inc(Index, AOffset);
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

{ TLspImplementationsTests }

procedure TLspImplementationsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitHaupt, HauptFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspImplementationsTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspImplementationsTests.TargetsAt(const AMarker: string; AOffset: Integer): TArray<TDefinitionTarget>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Result := TLspImplementations.Targets(FResolver, FIndex, Tree, HauptFile, PositionOf(UnitHaupt, AMarker, AOffset));
  finally
    Tree.Free;
  end;
end;

function TLspImplementationsTests.Lines(const ATargets: TArray<TDefinitionTarget>): string;
var
  Item: TDefinitionTarget;
begin
  Result := '';
  for Item in ATargets do
    Result := Result + IntToStr(Item.SelectionRange.StartPos.Line) + ' ';
  Result := Trim(Result);
end;

procedure TLspImplementationsTests.VirtualMethodListsOwnAndOverridingBodies;
begin
  // Auf der Deklaration in TBasis: eigener Rumpf, dann TMitte und TBlatt.
  Assert.AreEqual('18 21 25', Lines(TargetsAt('Zeichne; virtual', 0)));
  // Abstrakt: nur der Rumpf in TBlatt.
  Assert.AreEqual('29', Lines(TargetsAt('Leer; virtual', 0)));
end;

procedure TLspImplementationsTests.InterfaceMethodListsImplementingClasses;
begin
  Assert.AreEqual('18 21 25', Lines(TargetsAt('Zeichne;'#10'  end;'#10'  TBasis', 0)));
end;

procedure TLspImplementationsTests.TypeListsAllDescendants;
begin
  Assert.AreEqual('10 13', Lines(TargetsAt('TBasis = class', 0)));
  Assert.AreEqual('6 10 13', Lines(TargetsAt('IZeichner = interface', 0)));
end;

procedure TLspImplementationsTests.InheritedWithNameJumpsToAncestorBody;
begin
  Assert.AreEqual('18', Lines(TargetsAt('inherited Zeichne', 2)));
end;

procedure TLspImplementationsTests.BareInheritedUsesEnclosingMethod;
begin
  Assert.AreEqual('21', Lines(TargetsAt('inherited;', 2)));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspImplementationsTests);

end.
