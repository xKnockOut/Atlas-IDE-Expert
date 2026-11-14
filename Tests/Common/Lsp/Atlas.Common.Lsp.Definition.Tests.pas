unit Atlas.Common.Lsp.Definition.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Definition;

type
  [TestFixture]
  TLspDefinitionTests = class
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
    [Test]
    procedure WritesLocations;
    /// <summary>Ersatz-Units der IDE (atlas-ide:…) gibt es nicht als Datei: kein Sprungziel.</summary>
    [Test]
    procedure SkipsIdeUnits;
    /// <summary>Überladungen: Deklaration und Implementierung derselben Variante (gleiche Parametertypen); vorher
    /// galt immer die erste Überladung (Hover auf der zweiten zeigte die erste).</summary>
    [Test]
    procedure OverloadsPairByParameters;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

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

function PositionOf(const AText, AMarker: string; AOccurrence: Integer): TTextPosition;
var
  mIndex, mFound, mLine, mLineStart: Integer;
begin
  mFound := 0;
  mIndex := 0;
  repeat
    mIndex := Pos(AMarker, AText, mIndex + 1);
    if mIndex = 0 then
    begin
      raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
    end;
    Inc(mFound);
  until mFound = AOccurrence;
  mLine := 0;
  mLineStart := 1;
  for mFound := 1 to mIndex - 1 do
  begin
    if AText[mFound] = #10 then
    begin
      Inc(mLine);
      mLineStart := mFound + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

{ TLspDefinitionTests }

procedure TLspDefinitionTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitWerkzeug, 'C:\P\Werkzeug.pas', nil));
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
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    Result := TLspDefinition.Targets(FResolver, FIndex, mTree, cHauptFile,
      PositionOf(cUnitHaupt, AMarker, AOccurrence), ADeclaration);
  finally
    mTree.Free;
  end;
end;

function TLspDefinitionTests.TargetsIn(const AText, AMarker: string; AOccurrence: Integer;
  ADeclaration: Boolean): TArray<TDefinitionTarget>;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := TLspDefinition.Targets(FResolver, FIndex, mTree, cKonsoleFile, PositionOf(AText, AMarker, AOccurrence),
      ADeclaration);
  finally
    mTree.Free;
  end;
end;

procedure TLspDefinitionTests.OverloadsPairByParameters;
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

procedure TLspDefinitionTests.DefinitionOfMethodCallIsImplementation;
var
  mTargets: TArray<TDefinitionTarget>;
begin
  mTargets := TargetsAt('Baz;', 2, False);
  Assert.AreEqual(1, Integer(Length(mTargets)));
  Assert.AreEqual(cHauptFile, mTargets[0].FileName);
  Assert.AreEqual(18, mTargets[0].SelectionRange.StartPos.Line);
end;

procedure TLspDefinitionTests.DeclarationOfMethodCallIsClassMember;
var
  mTargets: TArray<TDefinitionTarget>;
begin
  mTargets := TargetsAt('Baz;', 2, True);
  Assert.AreEqual(1, Integer(Length(mTargets)));
  Assert.AreEqual(6, mTargets[0].SelectionRange.StartPos.Line);
end;

procedure TLspDefinitionTests.DefinitionOnImplementationJumpsBack;
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

procedure TLspDefinitionTests.DefinitionCrossesUnits;
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

procedure TLspDefinitionTests.UnitNameJumpsToFileStart;
var
  mTargets: TArray<TDefinitionTarget>;
begin
  mTargets := TargetsAt('Werkzeug;', 1, False);
  Assert.AreEqual(1, Integer(Length(mTargets)));
  Assert.AreEqual('C:\P\Werkzeug.pas', mTargets[0].FileName);
  Assert.AreEqual(0, mTargets[0].SelectionRange.StartPos.Line);
  Assert.AreEqual(0, mTargets[0].SelectionRange.StartPos.Character);
end;

procedure TLspDefinitionTests.LocalVariableAndUnknownName;
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

procedure TLspDefinitionTests.TypeDefinitionFollowsDeclaredTypes;
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
    mTargets := TLspDefinition.TypeTargets(FResolver, mTree, 'C:\P\Typen.pas', PositionOf(cSource, 'Global :=', 1));
    Assert.AreEqual(1, Integer(Length(mTargets)));
    Assert.AreEqual(3, mTargets[0].SelectionRange.StartPos.Line);
    // Funktion: zum Ergebnistyp.
    mTargets := TLspDefinition.TypeTargets(FResolver, mTree, 'C:\P\Typen.pas', PositionOf(cSource, 'Liefere(Zahl)', 1));
    Assert.AreEqual(1, Integer(Length(mTargets)));
    Assert.AreEqual(3, mTargets[0].SelectionRange.StartPos.Line);
    // Integer steht nicht im Index: kein Ziel.
    mTargets := TLspDefinition.TypeTargets(FResolver, mTree, 'C:\P\Typen.pas', PositionOf(cSource, 'Zahl);', 1));
    Assert.AreEqual(0, Integer(Length(mTargets)));
  finally
    mTree.Free;
  end;
end;

procedure TLspDefinitionTests.WritesLocations;
var
  mTarget: TDefinitionTarget;
  mJson: TJSONArray;
  mLocation: TJSONValue;
  mUri: string;
  mLine, mCharacter: Integer;
begin
  mTarget.FileName := 'C:\P\Werkzeug.pas';
  mTarget.Range := TTextRange.Create(TTextPosition.Create(4, 0), TTextPosition.Create(6, 4));
  mTarget.SelectionRange := TTextRange.Create(TTextPosition.Create(4, 10), TTextPosition.Create(4, 16));
  mJson := TLspDefinition.ToJson([mTarget]);
  try
    Assert.AreEqual(1, Integer(mJson.Count));
    // Werte erst in typisierte Variablen lesen: GetValue<T> direkt als
    // Argument von Assert.AreEqual übersetzt dcc64 (Delphi 13) nicht.
    mLocation := mJson.Items[0];
    mUri := mLocation.GetValue<string>('uri');
    mLine := mLocation.GetValue<Integer>('range.start.line');
    mCharacter := mLocation.GetValue<Integer>('range.start.character');
    Assert.AreEqual(TDocumentUris.FromPath('C:\P\Werkzeug.pas'), mUri);
    Assert.AreEqual(4, mLine);
    Assert.AreEqual(10, mCharacter);
  finally
    mJson.Free;
  end;
end;

procedure TLspDefinitionTests.SkipsIdeUnits;
var
  mReal, mIde: TDefinitionTarget;
  mJson: TJSONArray;
  mUri: string;
begin
  mReal.FileName := 'C:\P\Werkzeug.pas';
  mReal.Range := TTextRange.Create(TTextPosition.Create(4, 0), TTextPosition.Create(6, 4));
  mReal.SelectionRange := mReal.Range;
  mIde := mReal;
  mIde.FileName := 'atlas-ide:Vcl.Forms.pas';
  mJson := TLspDefinition.ToJson([mIde]);
  try
    // Ersatz-Unit der IDE allein: kein Sprungziel.
    Assert.AreEqual(0, Integer(mJson.Count));
  finally
    mJson.Free;
  end;
  mJson := TLspDefinition.ToJson([mIde, mReal]);
  try
    Assert.AreEqual(1, Integer(mJson.Count));
    mUri := mJson.Items[0].GetValue<string>('uri');
    Assert.AreEqual(TDocumentUris.FromPath('C:\P\Werkzeug.pas'), mUri);
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDefinitionTests);

end.
