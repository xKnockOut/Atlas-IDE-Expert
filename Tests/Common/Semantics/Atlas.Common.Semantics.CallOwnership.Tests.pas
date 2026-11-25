unit Atlas.Common.Semantics.CallOwnership.Tests;

// Tests der Abfrage beim Aufruf (Atlas.Common.Semantics.CallOwnership): Routine einer anderen Unit, die leiht,
// freigibt oder übernimmt, Weitergaben über mehrere Routinen, Kreise, virtuelle Methoden, unbekannte Routinen und
// die Tabelle bekannter RTL-Routinen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCallOwnershipTests = class
  public
    [Test]
    procedure RoutineOfOtherUnit;
    [Test]
    procedure ForwardsAcrossRoutines;
    [Test]
    procedure CycleCountsAsBorrowed;
    [Test]
    procedure VirtualAndUnknownStayUnknown;
    [Test]
    procedure KnownRtlRoutines;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.ParamOwnership,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.CallOwnership,
  Atlas.Tests.SymbolIndex;

const
  cHelfer = 'unit Helfer;'#10'interface'#10'uses System.Classes;'#10'type'#10'  THalter = class'#10 +
    '  private'#10'    FListe: TStrings;'#10'  public'#10'    constructor Create(AListe: TStrings);'#10 +
    '    procedure Anzeigen(AListe: TStrings); virtual;'#10'  end;'#10 +
    'procedure StrBreakApart(const S, Trenner: string; Teile: TStrings);'#10'procedure Weg(A: TObject);'#10 +
    'procedure Weiter(A: TObject);'#10'procedure Kreis(A: TObject; N: Integer);'#10'implementation'#10 +
    'constructor THalter.Create(AListe: TStrings);'#10'begin'#10'  FListe := AListe;'#10'end;'#10 +
    'procedure THalter.Anzeigen(AListe: TStrings);'#10'begin'#10'  AListe.Clear;'#10'end;'#10 +
    'procedure StrBreakApart(const S, Trenner: string; Teile: TStrings);'#10'begin'#10'  Teile.Add(S);'#10 +
    'end;'#10'procedure Weg(A: TObject);'#10'begin'#10'  A.Free;'#10'end;'#10 +
    'procedure Weiter(A: TObject);'#10'begin'#10'  Weg(A);'#10'end;'#10 +
    'procedure Kreis(A: TObject; N: Integer);'#10'begin'#10'  if N > 0 then'#10'    Kreis(A, N - 1);'#10'end;'#10 +
    'end.';

/// <summary>Antwort für das Argument AArgument des ersten Aufrufs von ACallee in der Anweisung AStatement einer
/// Unit, die Helfer einbindet.</summary>
function EffectIn(const AStatement, ACallee: string; AArgument: Integer; AWithIndex: Boolean): TCallEffect;
var
  mIndex: ISymbolIndex;
  mText: string;
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mCalls: TCallOwnership;
  mCall: TSyntaxNode;
begin
  mIndex := nil;
  if AWithIndex then
  begin
    mIndex := TTestIndex.Build([cHelfer, 'Helfer.pas']);
  end;
  mText := 'unit Nutzer;'#10'interface'#10'implementation'#10'uses System.Classes, Helfer;'#10'procedure Lauf;'#10 +
    'var'#10'  X: TStringList;'#10'  H: THalter;'#10'begin'#10'  ' + AStatement + #10'end;'#10'end.';
  mTree := TSyntaxTreeCache.Parse(mText);
  mResolver := TNameResolver.Create(mIndex);
  mCalls := nil;
  try
    mResolver.PinTree(mTree, 'Nutzer.pas');
    try
      mCalls := TCallOwnership.Create(mResolver, mTree, 'Nutzer.pas', mIndex, nil, nil);
      mCall := mTree.Root.Search(
        function(ANode: TSyntaxNode): TSyntaxSearchStep
        begin
          Result := TSyntaxSearchStep.Descend;
          if (ANode.Kind = TSyntaxKind.Call) and SameText(ANode.Name, ACallee) then
          begin
            Result := TSyntaxSearchStep.Found;
          end;
        end);
      Assert.IsNotNull(mCall, ACallee);
      Result := mCalls.EffectOf(mCall, AArgument);
    finally
      mResolver.UnpinTree;
    end;
  finally
    mCalls.Free;
    mResolver.Free;
    mTree.Free;
  end;
end;

function EffectName(const AEffect: TCallEffect): string;
begin
  Result := TParamOwnership.cEffectMarks[AEffect.Effect];
end;

procedure TCallOwnershipTests.RoutineOfOtherUnit;
var
  mEffect: TCallEffect;
begin
  mEffect := EffectIn('StrBreakApart(''a,b'', '','', X);', 'StrBreakApart', 2, True);
  Assert.AreEqual('b', EffectName(mEffect));
  Assert.AreEqual('StrBreakApart', mEffect.Callee);
  Assert.AreEqual('Helfer', mEffect.UnitName);
  Assert.AreEqual('f', EffectName(EffectIn('Weg(X);', 'Weg', 0, True)));
  Assert.AreEqual('k', EffectName(EffectIn('H := THalter.Create(X);', 'Create', 0, True)));
end;

procedure TCallOwnershipTests.ForwardsAcrossRoutines;
var
  mEffect: TCallEffect;
begin
  mEffect := EffectIn('Weiter(X);', 'Weiter', 0, True);
  Assert.AreEqual('f', EffectName(mEffect));
  Assert.AreEqual('Weiter', mEffect.Callee);
  Assert.AreEqual('Weg', mEffect.Via);
end;

procedure TCallOwnershipTests.CycleCountsAsBorrowed;
begin
  Assert.AreEqual('b', EffectName(EffectIn('Kreis(X, 3);', 'Kreis', 0, True)));
end;

procedure TCallOwnershipTests.VirtualAndUnknownStayUnknown;
begin
  Assert.AreEqual('?', EffectName(EffectIn('H.Anzeigen(X);', 'Anzeigen', 0, True)));
  Assert.AreEqual('?', EffectName(EffectIn('Unbekannt(X);', 'Unbekannt', 0, True)));
  // Ohne Index keine Aussage über Helfer.
  Assert.AreEqual('?', EffectName(EffectIn('Weg(X);', 'Weg', 0, False)));
end;

procedure TCallOwnershipTests.KnownRtlRoutines;
var
  mEffect: TParamEffect;
begin
  Assert.AreEqual('b', EffectName(EffectIn('ExtractStrings(['',''], [], ''a,b'', X);', 'ExtractStrings', 3,
    False)));
  Assert.IsTrue(TCallOwnership.KnownRoutine('ExtractStrings', 3, mEffect));
  Assert.AreEqual(Ord(TParamEffect.Borrows), Ord(mEffect));
  Assert.IsFalse(TCallOwnership.KnownRoutine('ExtractStrings', 0, mEffect));
end;

end.
