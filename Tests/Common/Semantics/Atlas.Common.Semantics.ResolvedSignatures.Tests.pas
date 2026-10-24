unit Atlas.Common.Semantics.ResolvedSignatures.Tests;

// Übergabeart über die Namensauflösung (#712): Modifizierer aus einer
// Signatur, Typumwandlungen, Routinen anderer Units, Methoden über Objekte,
// Überladungen bleiben unbekannt, ohne Auflöser nur der Baum.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TResolvedSignaturesTests = class
  private
    FIndex: ISymbolIndex;
    /// <summary>Übergabearten aller Argumente aller Aufrufe in Haupt als "Name:Art,Art", mit Leerzeichen.</summary>
    function Modes(AWithResolver: Boolean): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ModesFromSignature;
    [Test]
    procedure TreeOnlyWithoutResolver;
    [Test]
    procedure ResolverKnowsOtherUnitsAndMethods;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ResolvedSignatures;

const
  LB = #13#10;
  MainFile = 'C:\P\Haupt.pas';
  OtherFile = 'C:\P\Lader.pas';
  ModeNames: array[TFlowArgumentMode] of string = ('value', 'ref', 'out', '?');

  UnitOther =
    'unit Lader;' + LB +
    'interface' + LB +
    'type' + LB +
    '  TListe = class' + LB +
    '    procedure Take(var AValue: Integer; ACount: Integer);' + LB +
    '    procedure Twice(A: Integer); overload;' + LB +
    '    procedure Twice(var A: string); overload;' + LB +
    '  end;' + LB +
    'procedure Fill(out AText: string; const AValue: Integer);' + LB +
    'implementation' + LB +
    'procedure TListe.Take(var AValue: Integer; ACount: Integer);' + LB +
    'begin' + LB +
    'end;' + LB +
    'procedure TListe.Twice(A: Integer);' + LB +
    'begin' + LB +
    'end;' + LB +
    'procedure TListe.Twice(var A: string);' + LB +
    'begin' + LB +
    'end;' + LB +
    'procedure Fill(out AText: string; const AValue: Integer);' + LB +
    'begin' + LB +
    'end;' + LB +
    'end.';

  UnitMain =
    'unit Haupt;' + LB +
    'interface' + LB +
    'implementation' + LB +
    'uses Lader;' + LB +
    'procedure Local(var A: Integer);' + LB +
    'begin' + LB +
    'end;' + LB +
    'procedure Run;' + LB +
    'var' + LB +
    '  L: TListe;' + LB +
    '  N: Integer;' + LB +
    '  S: string;' + LB +
    'begin' + LB +
    '  Local(N);' + LB +
    '  Fill(S, N);' + LB +
    '  L.Take(N, 1);' + LB +
    '  L.Twice(N);' + LB +
    '  L.Twice(Unbekannt);' + LB +
    '  Writeln(PChar(S));' + LB +
    'end;' + LB +
    'end.';

procedure TResolvedSignaturesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitOther, OtherFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitMain, MainFile, nil));
end;

procedure TResolvedSignaturesTests.TearDown;
begin
  FIndex := nil;
end;

function TResolvedSignaturesTests.Modes(AWithResolver: Boolean): string;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Lookup: TFlowSignatureLookup;
  Calls: TList<TSyntaxNode>;
  Call: TSyntaxNode;
  Item: string;
  Argument: Integer;
begin
  Result := '';
  Resolver := nil;
  Calls := TList<TSyntaxNode>.Create;
  Tree := TPascalParser.Parse(UnitMain);
  try
    if AWithResolver then
      Resolver := TNameResolver.Create(FIndex, nil);
    Lookup := TResolvedSignatures.Lookup(Resolver, Tree, MainFile);
    Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if ANode.Kind = TSyntaxKind.Call then
          Calls.Add(ANode);
        Result := True;
      end);
    for Call in Calls do
    begin
      Item := Call.Name + ':';
      for Argument := 0 to Call.ChildCount - 2 do
      begin
        if Argument > 0 then
          Item := Item + ',';
        Item := Item + ModeNames[Lookup(Call, Argument)];
      end;
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + Item;
    end;
  finally
    Lookup := nil;
    Resolver.Free;
    Tree.Free;
    Calls.Free;
  end;
end;

procedure TResolvedSignaturesTests.ModesFromSignature;
var
  Found: TArray<string>;
begin
  Assert.IsTrue(TResolvedSignatures.SignatureModes('procedure Foo(var A: Integer; const B, C: string; D: Byte)',
    Found));
  Assert.AreEqual('var|const|const|', string.Join('|', Found));
  Assert.IsTrue(TResolvedSignatures.SignatureModes('function Bar(out X: TArray<Integer>): Boolean', Found));
  Assert.AreEqual('out', string.Join('|', Found));
  Assert.IsFalse(TResolvedSignatures.SignatureModes('procedure Ohne', Found));
  Assert.AreEqual(0, Integer(Length(Found)));
end;

procedure TResolvedSignaturesTests.TreeOnlyWithoutResolver;
begin
  // Routinen der Datei und Standardroutinen; Fill und Methoden sind unbekannt, PChar liest nur.
  Assert.AreEqual('Local:ref Fill:?,? Take:?,? Twice:? Twice:? Writeln:value PChar:value', Modes(False));
end;

procedure TResolvedSignaturesTests.ResolverKnowsOtherUnitsAndMethods;
begin
  // Die Überladung wählt die Namensauflösung nach dem Argumenttyp; ohne bekannten Typ bleibt sie unbekannt.
  Assert.AreEqual('Local:ref Fill:out,value Take:ref,value Twice:value Twice:? Writeln:value PChar:value',
    Modes(True));
end;

initialization
  TDUnitX.RegisterTestFixture(TResolvedSignaturesTests);

end.
