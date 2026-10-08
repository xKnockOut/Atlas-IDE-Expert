unit BDLsp.Common.Lsp.Definition.Tests;

interface

uses
  DUnitX.TestFramework,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Semantics.NameResolver,
  BDLsp.Common.Lsp.Definition;

type
  [TestFixture]
  TLspDefinitionTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function TargetsAt(const AMarker: string; AOccurrence: Integer; ADeclaration: Boolean): TArray<TDefinitionTarget>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DefinitionOfMethodCallIsImplementation;
    [Test]
    procedure DeclarationOfMethodCallIsClassMember;
    [Test]
    procedure DefinitionOnImplementationJumpsBack;
    [Test]
    procedure DefinitionCrossesUnits;
    [Test]
    procedure UnitNameJumpsToFileStart;
    [Test]
    procedure LocalVariableAndUnknownName;
    [Test]
    procedure TypeDefinitionFollowsDeclaredTypes;
    [Test]
    procedure WritesLocations;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Documents.Uris,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Index.SymbolIndex,
  BDLsp.Common.Index.Extractor;

const
  HauptFile = 'C:\P\Haupt.pas';

  UnitWerkzeug =
    'unit Werkzeug;'#10 +
    'interface'#10 +
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
    '  TFoo = class'#10 +
    '    procedure Bar;'#10 +
    '    procedure Baz;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Bar;'#10 +
    'var'#10 +
    '  Wert: Integer;'#10 +
    'begin'#10 +
    '  Wert := 1;'#10 +
    '  Baz;'#10 +
    '  Rechne;'#10 +
    '  Unbekannt;'#10 +
    'end;'#10 +
    'procedure TFoo.Baz;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

function PositionOf(const AText, AMarker: string; AOccurrence: Integer): TTextPosition;
var
  Index, Found, Line, LineStart: Integer;
begin
  Found := 0;
  Index := 0;
  repeat
    Index := Pos(AMarker, AText, Index + 1);
    if Index = 0 then
      raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
    Inc(Found);
  until Found = AOccurrence;
  Line := 0;
  LineStart := 1;
  for Found := 1 to Index - 1 do
    if AText[Found] = #10 then
    begin
      Inc(Line);
      LineStart := Found + 1;
    end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

{ TLspDefinitionTests }

procedure TLspDefinitionTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitWerkzeug, 'C:\P\Werkzeug.pas', nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspDefinitionTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspDefinitionTests.TargetsAt(const AMarker: string; AOccurrence: Integer;
  ADeclaration: Boolean): TArray<TDefinitionTarget>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Result := TLspDefinition.Targets(FResolver, FIndex, Tree, HauptFile,
      PositionOf(UnitHaupt, AMarker, AOccurrence), ADeclaration);
  finally
    Tree.Free;
  end;
end;

procedure TLspDefinitionTests.DefinitionOfMethodCallIsImplementation;
var
  Targets: TArray<TDefinitionTarget>;
begin
  Targets := TargetsAt('Baz;', 2, False);
  Assert.AreEqual(1, Integer(Length(Targets)));
  Assert.AreEqual(HauptFile, Targets[0].FileName);
  Assert.AreEqual(18, Targets[0].SelectionRange.StartPos.Line);
end;

procedure TLspDefinitionTests.DeclarationOfMethodCallIsClassMember;
var
  Targets: TArray<TDefinitionTarget>;
begin
  Targets := TargetsAt('Baz;', 2, True);
  Assert.AreEqual(1, Integer(Length(Targets)));
  Assert.AreEqual(6, Targets[0].SelectionRange.StartPos.Line);
end;

procedure TLspDefinitionTests.DefinitionOnImplementationJumpsBack;
var
  Targets: TArray<TDefinitionTarget>;
begin
  // Auf der Deklaration in der Klasse: zur Implementierung.
  Targets := TargetsAt('Bar;', 1, False);
  Assert.AreEqual(9, Targets[0].SelectionRange.StartPos.Line);
  // Auf dem Namen der Implementierung: zurück zur Deklaration.
  Targets := TargetsAt('Bar;', 2, False);
  Assert.AreEqual(5, Targets[0].SelectionRange.StartPos.Line);
end;

procedure TLspDefinitionTests.DefinitionCrossesUnits;
var
  Targets: TArray<TDefinitionTarget>;
begin
  Targets := TargetsAt('Rechne;', 1, False);
  Assert.AreEqual(1, Integer(Length(Targets)));
  Assert.AreEqual('C:\P\Werkzeug.pas', Targets[0].FileName);
  Assert.AreEqual(4, Targets[0].SelectionRange.StartPos.Line);
  Targets := TargetsAt('Rechne;', 1, True);
  Assert.AreEqual(2, Targets[0].SelectionRange.StartPos.Line);
end;

procedure TLspDefinitionTests.UnitNameJumpsToFileStart;
var
  Targets: TArray<TDefinitionTarget>;
begin
  Targets := TargetsAt('Werkzeug;', 1, False);
  Assert.AreEqual(1, Integer(Length(Targets)));
  Assert.AreEqual('C:\P\Werkzeug.pas', Targets[0].FileName);
  Assert.AreEqual(0, Targets[0].SelectionRange.StartPos.Line);
  Assert.AreEqual(0, Targets[0].SelectionRange.StartPos.Character);
end;

procedure TLspDefinitionTests.LocalVariableAndUnknownName;
var
  Targets: TArray<TDefinitionTarget>;
begin
  Targets := TargetsAt('Wert :=', 1, False);
  Assert.AreEqual(1, Integer(Length(Targets)));
  Assert.AreEqual(HauptFile, Targets[0].FileName);
  Assert.AreEqual(11, Targets[0].SelectionRange.StartPos.Line);
  Targets := TargetsAt('Unbekannt', 1, False);
  Assert.AreEqual(0, Integer(Length(Targets)));
end;

procedure TLspDefinitionTests.TypeDefinitionFollowsDeclaredTypes;
const
  Source =
    'unit Typen;'#10 +                       // 0
    'interface'#10 +                         // 1
    'type'#10 +                              // 2
    '  TBasis = class end;'#10 +             // 3
    '  TAlias = TBasis;'#10 +                // 4
    'var Global: TAlias;'#10 +               // 5
    'implementation'#10 +                    // 6
    'function Liefere(Zahl: Integer): TBasis;'#10 + // 7
    'begin'#10 +                             // 8
    '  Global := Liefere(Zahl);'#10 +        // 9
    'end;'#10 +                              // 10
    'end.';
var
  Tree: TSyntaxTree;
  Targets: TArray<TDefinitionTarget>;
begin
  Tree := TPascalParser.Parse(Source);
  try
    // Variable mit Alias-Typ: zum Zieltyp des Alias.
    Targets := TLspDefinition.TypeTargets(FResolver, Tree, 'C:\P\Typen.pas', PositionOf(Source, 'Global :=', 1));
    Assert.AreEqual(1, Integer(Length(Targets)));
    Assert.AreEqual(3, Targets[0].SelectionRange.StartPos.Line);
    // Funktion: zum Ergebnistyp.
    Targets := TLspDefinition.TypeTargets(FResolver, Tree, 'C:\P\Typen.pas', PositionOf(Source, 'Liefere(Zahl)', 1));
    Assert.AreEqual(1, Integer(Length(Targets)));
    Assert.AreEqual(3, Targets[0].SelectionRange.StartPos.Line);
    // Integer steht nicht im Index: kein Ziel.
    Targets := TLspDefinition.TypeTargets(FResolver, Tree, 'C:\P\Typen.pas', PositionOf(Source, 'Zahl);', 1));
    Assert.AreEqual(0, Integer(Length(Targets)));
  finally
    Tree.Free;
  end;
end;

procedure TLspDefinitionTests.WritesLocations;
var
  Target: TDefinitionTarget;
  Json: TJSONArray;
begin
  Target.FileName := 'C:\P\Werkzeug.pas';
  Target.Range := TTextRange.Create(TTextPosition.Create(4, 0), TTextPosition.Create(6, 4));
  Target.SelectionRange := TTextRange.Create(TTextPosition.Create(4, 10), TTextPosition.Create(4, 16));
  Json := TLspDefinition.ToJson([Target]);
  try
    Assert.AreEqual(1, Integer(Json.Count));
    Assert.AreEqual(TDocumentUris.FromPath('C:\P\Werkzeug.pas'), Json.Items[0].GetValue<string>('uri'));
    Assert.AreEqual(4, Json.Items[0].GetValue<Integer>('range.start.line'));
    Assert.AreEqual(10, Json.Items[0].GetValue<Integer>('range.start.character'));
  finally
    Json.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDefinitionTests);

end.
