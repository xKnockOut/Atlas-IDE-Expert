unit Atlas.Common.Lsp.DebugScope.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Pascal.SyntaxTree;

type
  [TestFixture]
  TLspDebugScopeTests = class
  private
    FTree: TSyntaxTree;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MethodNamesUnitAndClass;
    [Test]
    procedure NestedRoutineCountsToItsMethod;
    [Test]
    procedure FreeRoutineHasNoClass;
    [Test]
    procedure OutsideRoutineHasUnitOnly;
    [Test]
    procedure TypeOfRoutineDropsTypeParams;
    [Test]
    procedure AncestorsFromIndex;
    [Test]
    procedure AncestorCycleEnds;
    [Test]
    procedure JsonLeavesOutEmptyFields;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.DebugScope;

const
  cSource =
    'unit Auftrag.Lauf;'#10 +                                    // 0
    'interface'#10 +                                             // 1
    'type'#10 +                                                  // 2
    '  TBasisLauf = class'#10 +                                  // 3
    '  end;'#10 +                                                // 4
    '  TAuftragsLauf = class(TBasisLauf)'#10 +                   // 5
    '    procedure LeseBericht;'#10 +                            // 6
    '  end;'#10 +                                                // 7
    'implementation'#10 +                                        // 8
    'procedure Frei;'#10 +                                       // 9
    'begin'#10 +                                                 // 10
    '  Sleep(1);'#10 +                                           // 11
    'end;'#10 +                                                  // 12
    'procedure TAuftragsLauf.LeseBericht;'#10 +                  // 13
    '  procedure Innen;'#10 +                                    // 14
    '  begin'#10 +                                               // 15
    '    Sleep(2);'#10 +                                         // 16
    '  end;'#10 +                                                // 17
    'begin'#10 +                                                 // 18
    '  Innen;'#10 +                                              // 19
    'end;'#10 +                                                  // 20
    'initialization'#10 +                                        // 21
    '  Frei;'#10 +                                               // 22
    'end.';

function NewIndex(const ASource: string): ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText(ASource, 'C:\P\Auftrag.Lauf.pas', nil));
end;

{ TLspDebugScopeTests }

procedure TLspDebugScopeTests.Setup;
begin
  FTree := TSyntaxTreeCache.Parse(cSource);
end;

procedure TLspDebugScopeTests.TearDown;
begin
  FreeAndNil(FTree);
end;

procedure TLspDebugScopeTests.MethodNamesUnitAndClass;
var
  mScope: TLspDebugScope;
begin
  mScope := TLspDebugScope.At(FTree, 19, nil);
  Assert.AreEqual('Auftrag.Lauf', mScope.UnitName);
  Assert.AreEqual('TAuftragsLauf', mScope.TypeName);
  Assert.AreEqual(0, Integer(Length(mScope.Ancestors)), 'ohne Index keine Vorfahren');
end;

procedure TLspDebugScopeTests.NestedRoutineCountsToItsMethod;
begin
  Assert.AreEqual('TAuftragsLauf', TLspDebugScope.At(FTree, 16, nil).TypeName);
end;

procedure TLspDebugScopeTests.FreeRoutineHasNoClass;
var
  mScope: TLspDebugScope;
begin
  mScope := TLspDebugScope.At(FTree, 11, nil);
  Assert.AreEqual('Auftrag.Lauf', mScope.UnitName);
  Assert.AreEqual('', mScope.TypeName);
end;

procedure TLspDebugScopeTests.OutsideRoutineHasUnitOnly;
var
  mScope: TLspDebugScope;
begin
  mScope := TLspDebugScope.At(FTree, 22, nil);
  Assert.AreEqual('Auftrag.Lauf', mScope.UnitName);
  Assert.AreEqual('', mScope.TypeName);
end;

procedure TLspDebugScopeTests.TypeOfRoutineDropsTypeParams;
begin
  Assert.AreEqual('TListe', TLspDebugScope.TypeOfRoutine('TListe<T>.Add'));
  Assert.AreEqual('TAussen.TInnen', TLspDebugScope.TypeOfRoutine('TAussen.TInnen.Lauf'));
  Assert.AreEqual('TPaar', TLspDebugScope.TypeOfRoutine('TPaar<TKey, TValue>.Tausche<X>'));
  Assert.AreEqual('', TLspDebugScope.TypeOfRoutine('Frei'));
end;

procedure TLspDebugScopeTests.AncestorsFromIndex;
var
  mScope: TLspDebugScope;
begin
  mScope := TLspDebugScope.At(FTree, 19, NewIndex(cSource));
  Assert.AreEqual('TBasisLauf', string.Join(',', mScope.Ancestors));
end;

procedure TLspDebugScopeTests.AncestorCycleEnds;
const
  cCycle = 'unit Kreis;'#10'interface'#10'type'#10'  TA = class(TB)'#10'  end;'#10'  TB = class(TA)'#10 +
    '  end;'#10'implementation'#10'end.';
begin
  Assert.AreEqual('TB', string.Join(',', TLspDebugScope.AncestorChain(NewIndex(cCycle), 'TA')));
end;

procedure TLspDebugScopeTests.JsonLeavesOutEmptyFields;
var
  mJson: TJSONObject;
  mScope: TLspDebugScope;
begin
  mJson := TJSONObject.Create;
  try
    mScope := TLspDebugScope.At(FTree, 11, nil);
    mScope.AddTo(mJson);
    Assert.AreEqual('{"unit":"Auftrag.Lauf"}', mJson.ToJSON);
  finally
    mJson.Free;
  end;
  mJson := TJSONObject.Create;
  try
    mScope := TLspDebugScope.At(FTree, 19, NewIndex(cSource));
    mScope.AddTo(mJson);
    Assert.AreEqual('{"unit":"Auftrag.Lauf","class":"TAuftragsLauf","ancestors":["TBasisLauf"]}', mJson.ToJSON);
  finally
    mJson.Free;
  end;
end;

end.
