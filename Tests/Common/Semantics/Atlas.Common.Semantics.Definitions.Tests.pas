unit Atlas.Common.Semantics.Definitions.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.Definitions;

type
  [TestFixture]
  TDefinitionsTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function TargetsAt(const AMarker: string; AOccurrence: Integer; ADeclaration: Boolean): TArray<TDefinitionTarget>;
    function TargetsIn(const AText, AMarker: string; AOccurrence: Integer;
      ADeclaration: Boolean): TArray<TDefinitionTarget>;
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
    /// <summary>Überladungen: Deklaration und Implementierung derselben Variante (gleiche Parametertypen); vorher
    /// galt immer die erste Überladung (Hover auf der zweiten zeigte die erste).</summary>
    [Test]
    procedure OverloadsPairByParameters;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Tests.SourceText;

const
  cHauptFile = 'C:\P\Haupt.pas';

  cUnitWerkzeug =
    'unit Werkzeug;'#10 +
    'interface'#10 +
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

  cKonsoleFile = 'C:\P\Konsole.pas';

  cUnitKonsole =
    'unit Konsole;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKonsole = class'#10 +
    '    procedure Progress(const S: string); overload;'#10 +
    '    procedure Progress(const S: string; Force: Boolean); overload;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TKonsole.Progress(const S: string);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TKonsole.Progress(const S: string; Force: Boolean);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

{ TDefinitionsTests }

function TDefinitionsTests.TargetsAt(const AMarker: string; AOccurrence: Integer;
  ADeclaration: Boolean): TArray<TDefinitionTarget>;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    Result := TDefinitions.Targets(FResolver, FIndex, mTree, cHauptFile,
      TTestSource.PositionOf(cUnitHaupt, AMarker, AOccurrence), ADeclaration);
  finally
    mTree.Free;
  end;
end;

function TDefinitionsTests.TargetsIn(const AText, AMarker: string; AOccurrence: Integer;
  ADeclaration: Boolean): TArray<TDefinitionTarget>;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := TDefinitions.Targets(FResolver, FIndex, mTree, cKonsoleFile, TTestSource.PositionOf(AText, AMarker, AOccurrence),
      ADeclaration);
  finally
    mTree.Free;
  end;
end;

procedure TDefinitionsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitWerkzeug, 'C:\P\Werkzeug.pas', nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TDefinitionsTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

procedure TDefinitionsTests.DefinitionOfMethodCallIsImplementation;
var
  mTargets: TArray<TDefinitionTarget>;
begin
  mTargets := TargetsAt('Baz;', 2, False);
  Assert.AreEqual(1, Integer(Length(mTargets)));
  Assert.AreEqual(cHauptFile, mTargets[0].FileName);
  Assert.AreEqual(18, mTargets[0].SelectionRange.StartPos.Line);
end;

procedure TDefinitionsTests.DeclarationOfMethodCallIsClassMember;
var
  mTargets: TArray<TDefinitionTarget>;
begin
  mTargets := TargetsAt('Baz;', 2, True);
  Assert.AreEqual(1, Integer(Length(mTargets)));
  Assert.AreEqual(6, mTargets[0].SelectionRange.StartPos.Line);
end;

procedure TDefinitionsTests.DefinitionOnImplementationJumpsBack;
var
  mTargets: TArray<TDefinitionTarget>;
begin
  // Auf der Deklaration in der Klasse: zur Implementierung.
  mTargets := TargetsAt('Bar;', 1, False);
  Assert.AreEqual(9, mTargets[0].SelectionRange.StartPos.Line);
  // Auf dem Namen der Implementierung: zurück zur Deklaration.
  mTargets := TargetsAt('Bar;', 2, False);
  Assert.AreEqual(5, mTargets[0].SelectionRange.StartPos.Line);
end;

procedure TDefinitionsTests.DefinitionCrossesUnits;
var
  mTargets: TArray<TDefinitionTarget>;
begin
  mTargets := TargetsAt('Rechne;', 1, False);
  Assert.AreEqual(1, Integer(Length(mTargets)));
  Assert.AreEqual('C:\P\Werkzeug.pas', mTargets[0].FileName);
  Assert.AreEqual(4, mTargets[0].SelectionRange.StartPos.Line);
  mTargets := TargetsAt('Rechne;', 1, True);
  Assert.AreEqual(2, mTargets[0].SelectionRange.StartPos.Line);
end;

procedure TDefinitionsTests.UnitNameJumpsToFileStart;
var
  mTargets: TArray<TDefinitionTarget>;
begin
  mTargets := TargetsAt('Werkzeug;', 1, False);
  Assert.AreEqual(1, Integer(Length(mTargets)));
  Assert.AreEqual('C:\P\Werkzeug.pas', mTargets[0].FileName);
  Assert.AreEqual(0, mTargets[0].SelectionRange.StartPos.Line);
  Assert.AreEqual(0, mTargets[0].SelectionRange.StartPos.Character);
end;

procedure TDefinitionsTests.LocalVariableAndUnknownName;
var
  mTargets: TArray<TDefinitionTarget>;
begin
  mTargets := TargetsAt('Wert :=', 1, False);
  Assert.AreEqual(1, Integer(Length(mTargets)));
  Assert.AreEqual(cHauptFile, mTargets[0].FileName);
  Assert.AreEqual(11, mTargets[0].SelectionRange.StartPos.Line);
  mTargets := TargetsAt('Unbekannt', 1, False);
  Assert.AreEqual(0, Integer(Length(mTargets)));
end;

procedure TDefinitionsTests.TypeDefinitionFollowsDeclaredTypes;
const
  cSource =
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
  mTree: TSyntaxTree;
  mTargets: TArray<TDefinitionTarget>;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    // Variable mit Alias-Typ: zum Zieltyp des Alias.
    mTargets := TDefinitions.TypeTargets(FResolver, mTree, 'C:\P\Typen.pas', TTestSource.PositionOf(cSource, 'Global :=', 1));
    Assert.AreEqual(1, Integer(Length(mTargets)));
    Assert.AreEqual(3, mTargets[0].SelectionRange.StartPos.Line);
    // Funktion: zum Ergebnistyp.
    mTargets := TDefinitions.TypeTargets(FResolver, mTree, 'C:\P\Typen.pas', TTestSource.PositionOf(cSource, 'Liefere(Zahl)', 1));
    Assert.AreEqual(1, Integer(Length(mTargets)));
    Assert.AreEqual(3, mTargets[0].SelectionRange.StartPos.Line);
    // Integer steht nicht im Index: kein Ziel.
    mTargets := TDefinitions.TypeTargets(FResolver, mTree, 'C:\P\Typen.pas', TTestSource.PositionOf(cSource, 'Zahl);', 1));
    Assert.AreEqual(0, Integer(Length(mTargets)));
  finally
    mTree.Free;
  end;
end;

procedure TDefinitionsTests.OverloadsPairByParameters;
const
  cZweite = 'Progress(const S: string; Force';
  cErste = 'Progress(const S: string)';
var
  mTargets: TArray<TDefinitionTarget>;
begin
  // Hover und Strg+Umschalt+↑ auf der zweiten Überladung: ihre eigene Deklaration.
  mTargets := TargetsIn(cUnitKonsole, cZweite, 1, True);
  Assert.AreEqual(1, Integer(Length(mTargets)));
  Assert.AreEqual(5, mTargets[0].SelectionRange.StartPos.Line, 'Deklaration der zweiten');
  Assert.AreEqual(5, mTargets[0].Range.StartPos.Line, 'Bereich der zweiten');
  // F12 auf der Deklaration der zweiten: ihre Implementierung, und zurück.
  mTargets := TargetsIn(cUnitKonsole, cZweite, 1, False);
  Assert.AreEqual(11, mTargets[0].SelectionRange.StartPos.Line, 'Implementierung der zweiten');
  mTargets := TargetsIn(cUnitKonsole, cZweite, 2, False);
  Assert.AreEqual(5, mTargets[0].SelectionRange.StartPos.Line, 'zurück zur zweiten');
  // Die erste bleibt bei sich.
  mTargets := TargetsIn(cUnitKonsole, cErste, 1, False);
  Assert.AreEqual(8, mTargets[0].SelectionRange.StartPos.Line, 'Implementierung der ersten');
  mTargets := TargetsIn(cUnitKonsole, cErste, 2, False);
  Assert.AreEqual(4, mTargets[0].SelectionRange.StartPos.Line, 'zurück zur ersten');
end;

initialization
  TDUnitX.RegisterTestFixture(TDefinitionsTests);

end.
