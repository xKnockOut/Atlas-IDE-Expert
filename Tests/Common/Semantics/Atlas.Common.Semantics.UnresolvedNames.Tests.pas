unit Atlas.Common.Semantics.UnresolvedNames.Tests;

// Tests für nicht auflösbare Bezeichner (#178, MCP check_code).

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  [TestFixture]
  TUnresolvedNamesTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function Names(const AText: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReportsUnknownName;
    [Test]
    procedure KnowsLocalsUsesAndIntrinsics;
    [Test]
    procedure SkipsWithAndExceptionVariables;
    [Test]
    procedure NeedsSystemUnit;
    [Test]
    procedure RuleReportsInEditorOnlyWithIndex;
    [Test]
    procedure KnowsCastsUnitPrefixesAndNestedTypes;
    [Test]
    procedure SkipsNamesWithUnknownAncestor;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.UnresolvedNames,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Builtin.Unresolved;

const
  UnitSystem =
    'unit System;'#10 +
    'interface'#10 +
    'type'#10 +
    '  Integer = -2147483648..2147483647;'#10 +
    '  TObject = class'#10 +
    '  end;'#10 +
    '  Exception = class(TObject)'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';
  UnitBasis =
    'unit Basis;'#10 +
    'interface'#10 +
    'procedure Melde(A: Integer);'#10 +
    'implementation'#10 +
    'procedure Melde(A: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

procedure TUnresolvedNamesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitSystem, 'C:\Lib\System.pas', nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, 'C:\P\Basis.pas', nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TUnresolvedNamesTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TUnresolvedNamesTests.Names(const AText: string): string;
var
  Tree: TSyntaxTree;
  Name: TUnresolvedName;
begin
  Result := '';
  Tree := TPascalParser.Parse(AText);
  try
    for Name in TUnresolvedNames.Find(FResolver, Tree, 'C:\P\Haupt.pas') do
      Result := Result + Name.Name + Format('@%d:%d;', [Name.Range.StartPos.Line, Name.Range.StartPos.Character]);
  finally
    Tree.Free;
  end;
end;

procedure TUnresolvedNamesTests.RuleReportsInEditorOnlyWithIndex;
const
  Text =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure P;'#10 +
    'begin'#10 +
    '  fdsfds.Create;'#10 +
    'end;'#10 +
    'end.';
var
  Registry: TRuleRegistry;
  Context: TRuleContext;
  Tree: TSyntaxTree;
  Findings: TArray<TRuleFinding>;
begin
  Registry := TRuleRegistry.Create;
  Tree := TPascalParser.Parse(Text);
  try
    RegisterUnresolvedRules(Registry);
    Context := Default(TRuleContext);
    Context.RelativePath := 'Haupt.pas';
    Context.Text := Text;
    Context.Tree := Tree;
    // Ohne Index (Linter): keine Aussage.
    Findings := TRuleEngine.Run(Registry.Rules, TServerSettings.Default, Context);
    Assert.AreEqual(0, Integer(Length(Findings)));
    Context.Index := FIndex;
    Findings := TRuleEngine.Run(Registry.Rules, TServerSettings.Default, Context);
    Assert.AreEqual(1, Integer(Length(Findings)));
    Assert.AreEqual('unresolved-identifier', Findings[0].RuleId);
    Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
    Assert.Contains(Findings[0].Message, 'fdsfds');
  finally
    Tree.Free;
    Registry.Free;
  end;
end;

procedure TUnresolvedNamesTests.ReportsUnknownName;
begin
  Assert.AreEqual('Unbekannt@5:2;', Names(
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure P;'#10 +
    'begin'#10 +
    '  Unbekannt(1);'#10 +
    'end;'#10 +
    'end.'));
end;

procedure TUnresolvedNamesTests.KnowsLocalsUsesAndIntrinsics;
begin
  Assert.AreEqual('', Names(
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Basis;'#10 +
    'function P(A: Integer): Integer;'#10 +
    'var'#10 +
    '  B: Integer;'#10 +
    'begin'#10 +
    '  B := A;'#10 +
    '  Inc(B);'#10 +
    '  Melde(Length(''x'') + B);'#10 +
    '  Result := B;'#10 +
    'end;'#10 +
    'end.'));
end;

procedure TUnresolvedNamesTests.SkipsWithAndExceptionVariables;
begin
  Assert.AreEqual('', Names(
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure P(O: TObject);'#10 +
    'begin'#10 +
    '  with O do'#10 +
    '    Feld := 1;'#10 +
    '  try'#10 +
    '  except'#10 +
    '    on E: Exception do'#10 +
    '      raise E;'#10 +
    '  end;'#10 +
    'end;'#10 +
    'end.'));
end;

procedure TUnresolvedNamesTests.KnowsCastsUnitPrefixesAndNestedTypes;
begin
  // Fehlalarme aus der Problemliste zu Atlas selbst (#647).
  FIndex.AddUnit(TIndexExtractor.ExtractText(
    'unit Werk.Hilfe;'#10 +
    'interface'#10 +
    'procedure Hilf;'#10 +
    'implementation'#10 +
    'procedure Hilf;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.', 'C:\P\Werk.Hilfe.pas', nil));
  Assert.AreEqual('', Names(
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TAussen = class'#10 +
    '  type'#10 +
    '    TInnen = class'#10 +
    '    private'#10 +
    '      FWert: Integer;'#10 +
    '      procedure Lauf;'#10 +
    '    end;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'uses Werk.Hilfe;'#10 +
    'procedure TAussen.TInnen.Lauf;'#10 +
    'var'#10 +
    '  P: PChar;'#10 +
    'begin'#10 +
    '  FWert := Integer(MaxInt);'#10 +
    '  P := PChar(''x'');'#10 +
    '  AtomicIncrement(FWert);'#10 +
    '  Werk.Hilfe.Hilf;'#10 +
    'end;'#10 +
    'end.'));
end;

procedure TUnresolvedNamesTests.SkipsNamesWithUnknownAncestor;
const
  Text =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFenster = class(TFremd)'#10 +
    '    procedure Male;'#10 +
    '  end;'#10 +
    '  TEigen = class'#10 +
    '    procedure Male;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'uses Basis;'#10 +
    'procedure TFenster.Male;'#10 +
    'begin'#10 +
    '  Melde(ClientWidth);'#10 +
    'end;'#10 +
    'procedure TEigen.Male;'#10 +
    'begin'#10 +
    '  Melde(ClientWidth);'#10 +
    'end;'#10 +
    'end.';
begin
  // TFremd steht nicht im Index: ClientWidth kann geerbt sein (#647). In TEigen ist es sicher unbekannt.
  Assert.AreEqual('ClientWidth@17:8;', Names(Text));
end;

procedure TUnresolvedNamesTests.NeedsSystemUnit;
var
  Empty: ISymbolIndex;
begin
  Assert.IsTrue(TUnresolvedNames.Available(FIndex));
  Empty := TSymbolIndex.Create;
  Assert.IsFalse(TUnresolvedNames.Available(Empty));
  Assert.IsTrue(TUnresolvedNames.IsIntrinsic('writeln'));
end;

initialization
  TDUnitX.RegisterTestFixture(TUnresolvedNamesTests);

end.
