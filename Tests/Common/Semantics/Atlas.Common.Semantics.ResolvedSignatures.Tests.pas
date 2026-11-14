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
  Atlas.Common.Semantics.ControlFlow.Signatures,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ResolvedSignatures;

const
  cLB = #13#10;
  cMainFile = 'C:\P\Haupt.pas';
  cOtherFile = 'C:\P\Lader.pas';
  cModeNames: array[TFlowArgumentMode] of string = ('value', 'ref', 'out', '?');

  cUnitOther =
    'unit Lader;' + cLB +
    'interface' + cLB +
    'type' + cLB +
    '  TListe = class' + cLB +
    '    procedure Take(var AValue: Integer; ACount: Integer);' + cLB +
    '    procedure Twice(A: Integer); overload;' + cLB +
    '    procedure Twice(var A: string); overload;' + cLB +
    '  end;' + cLB +
    'procedure Fill(out AText: string; const AValue: Integer);' + cLB +
    'implementation' + cLB +
    'procedure TListe.Take(var AValue: Integer; ACount: Integer);' + cLB +
    'begin' + cLB +
    'end;' + cLB +
    'procedure TListe.Twice(A: Integer);' + cLB +
    'begin' + cLB +
    'end;' + cLB +
    'procedure TListe.Twice(var A: string);' + cLB +
    'begin' + cLB +
    'end;' + cLB +
    'procedure Fill(out AText: string; const AValue: Integer);' + cLB +
    'begin' + cLB +
    'end;' + cLB +
    'end.';

  cUnitMain =
    'unit Haupt;' + cLB +
    'interface' + cLB +
    'implementation' + cLB +
    'uses Lader;' + cLB +
    'procedure Local(var A: Integer);' + cLB +
    'begin' + cLB +
    'end;' + cLB +
    'procedure Run;' + cLB +
    'var' + cLB +
    '  L: TListe;' + cLB +
    '  N: Integer;' + cLB +
    '  S: string;' + cLB +
    'begin' + cLB +
    '  Local(N);' + cLB +
    '  Fill(S, N);' + cLB +
    '  L.Take(N, 1);' + cLB +
    '  L.Twice(N);' + cLB +
    '  L.Twice(Unbekannt);' + cLB +
    '  Writeln(PChar(S));' + cLB +
    'end;' + cLB +
    'end.';

procedure TResolvedSignaturesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitOther, cOtherFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitMain, cMainFile, nil));
end;

procedure TResolvedSignaturesTests.TearDown;
begin
  FIndex := nil;
end;

function TResolvedSignaturesTests.Modes(AWithResolver: Boolean): string;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mLookup: TFlowSignatureLookup;
  mCalls: TList<TSyntaxNode>;
  mCall: TSyntaxNode;
  mItem: string;
  mArgument: Integer;
begin
  Result := '';
  mResolver := nil;
  mCalls := TList<TSyntaxNode>.Create;
  mTree := TPascalParser.Parse(cUnitMain);
  try
    if AWithResolver then
    begin
      mResolver := TNameResolver.Create(FIndex, nil);
    end;
    mLookup := TResolvedSignatures.Lookup(mResolver, mTree, cMainFile);
    mTree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if ANode.Kind = TSyntaxKind.Call then
        begin
          mCalls.Add(ANode);
        end;
        Result := True;
      end);
    for mCall in mCalls do
    begin
      mItem := mCall.Name + ':';
      for mArgument := 0 to mCall.ChildCount - 2 do
      begin
        if mArgument > 0 then
        begin
          mItem := mItem + ',';
        end;
        mItem := mItem + cModeNames[mLookup(mCall, mArgument)];
      end;
      if Result <> '' then
      begin
        Result := Result + ' ';
      end;
      Result := Result + mItem;
    end;
  finally
    mLookup := nil;
    mResolver.Free;
    mTree.Free;
    mCalls.Free;
  end;
end;

procedure TResolvedSignaturesTests.ModesFromSignature;
var
  mFound: TArray<string>;
begin
  Assert.IsTrue(TResolvedSignatures.SignatureModes('procedure Foo(var A: Integer; const B, C: string; D: Byte)',
    mFound));
  Assert.AreEqual('var|const|const|', string.Join('|', mFound));
  Assert.IsTrue(TResolvedSignatures.SignatureModes('function Bar(out X: TArray<Integer>): Boolean', mFound));
  Assert.AreEqual('out', string.Join('|', mFound));
  Assert.IsFalse(TResolvedSignatures.SignatureModes('procedure Ohne', mFound));
  Assert.AreEqual(0, Integer(Length(mFound)));
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
