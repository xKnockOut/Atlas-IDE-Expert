unit Atlas.Common.Pascal.ParamOwnership.Tests;

// Tests der Besitz-Zusammenfassung je Parameter (Atlas.Common.Pascal.ParamOwnership): freigeben, übernehmen,
// leihen, weiterreichen, unklare Fälle, Kodierung und Lesen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TParamOwnershipTests = class
  public
    [Test]
    procedure EffectPerParameter;
    [Test]
    procedure ForwardsByName;
    [Test]
    procedure UnclearCases;
    [Test]
    procedure NothingToSay;
    [Test]
    procedure DecodeReadsEachParameter;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.ParamOwnership;

/// <summary>Zusammenfassung der ersten Routine im implementation-Teil; AHeader und ABody ohne begin/end.</summary>
function Summary(const AHeader, ABody: string): string;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse('unit U;'#10'interface'#10'implementation'#10 + AHeader + #10'begin'#10 + ABody +
    #10'end;'#10'end.');
  try
    Result := TParamOwnership.Summarize(mTree.Root.FindChild(TSyntaxKind.ImplementationSection).FindChild(
      TSyntaxKind.RoutineDecl));
  finally
    mTree.Free;
  end;
end;

procedure TParamOwnershipTests.EffectPerParameter;
begin
  Assert.AreEqual('b;-;f;k', Summary('procedure P(A: TStrings; const S: string; B: TObject; C: TList);',
    '  A.Add(S);'#10'  B.Free;'#10'  GListe := C;'));
  Assert.AreEqual('f', Summary('procedure P(var A: TObject);', '  FreeAndNil(A);'));
  Assert.AreEqual('k', Summary('function P(A: TObject): TObject;', '  Result := A;'));
  Assert.AreEqual('k', Summary('procedure P(A: TObject);', '  Exit(A);'));
  // Übernehmen und im Fehlerfall freigeben: übernommen.
  Assert.AreEqual('k', Summary('procedure P(A: TObject);', '  try'#10'    FFeld := A;'#10'  except'#10 +
    '    A.Free;'#10'    raise;'#10'  end;'));
  Assert.AreEqual('b;b', Summary('procedure P(A, B: TStrings);', '  A.Assign(B);'));
end;

procedure TParamOwnershipTests.ForwardsByName;
begin
  Assert.AreEqual('b>Fuellen#1', Summary('procedure P(A: TStrings);', '  Fuellen(1, A);'));
  Assert.AreEqual('b>Fuellen#0,Zeigen#0', Summary('procedure P(A: TStrings);', '  Fuellen(A);'#10 +
    '  Self.Zeigen(A);'));
  // Freigabe neben einer Weitergabe: freigegeben.
  Assert.AreEqual('f', Summary('procedure P(A: TStrings);', '  Fuellen(A);'#10'  A.Free;'));
end;

procedure TParamOwnershipTests.UnclearCases;
begin
  // Aufruf über ein anderes Objekt: nicht über den Namen auffindbar.
  Assert.AreEqual('?;f', Summary('procedure P(A: TStrings; B: TObject);', '  FListe.Add(A);'#10'  B.Free;'));
  Assert.AreEqual('?;f', Summary('procedure P(out A: TStrings; B: TObject);', '  A := nil;'#10'  B.Free;'));
  Assert.AreEqual('?;f', Summary('procedure P(A: TStrings; B: TObject);', '  A := nil;'#10'  B.Free;'));
  Assert.AreEqual('?;f', Summary('procedure P(A: TStrings; B: TObject);', '  TThread.Queue(nil,'#10 +
    '    procedure'#10'    begin'#10'      A.Free;'#10'    end);'#10'  B.Free;'));
  // with: Namen im Rumpf nicht sicher zuzuordnen, also nichts zu sagen.
  Assert.AreEqual('', Summary('procedure P(A: TStrings; B: TObject);', '  with A do'#10'    Clear;'#10 +
    '  B.Free;'));
end;

procedure TParamOwnershipTests.NothingToSay;
begin
  Assert.AreEqual('', Summary('procedure P(const S: string; N: Integer; const I: IInterface);', '  N := 1;'));
  Assert.AreEqual('', Summary('procedure P;', '  Exit;'));
  Assert.AreEqual('', Summary('procedure P(A: TStrings);', '  FListe.Add(A);'));
end;

procedure TParamOwnershipTests.DecodeReadsEachParameter;
var
  mSummary: TParamSummary;
begin
  Assert.IsTrue(TParamOwnership.Decode('b>Fuellen#1,Zeigen#0;-;f;k;?', 0, mSummary));
  Assert.AreEqual(Ord(TParamEffect.Borrows), Ord(mSummary.Effect));
  Assert.AreEqual(2, Integer(Length(mSummary.Forwards)));
  Assert.AreEqual('Fuellen', mSummary.Forwards[0].Callee);
  Assert.AreEqual(1, mSummary.Forwards[0].Argument);
  Assert.AreEqual('Zeigen', mSummary.Forwards[1].Callee);
  Assert.IsTrue(TParamOwnership.Decode('b>Fuellen#1,Zeigen#0;-;f;k;?', 1, mSummary));
  Assert.AreEqual(Ord(TParamEffect.NoObject), Ord(mSummary.Effect));
  Assert.IsTrue(TParamOwnership.Decode('b>Fuellen#1,Zeigen#0;-;f;k;?', 2, mSummary));
  Assert.AreEqual(Ord(TParamEffect.Frees), Ord(mSummary.Effect));
  Assert.IsTrue(TParamOwnership.Decode('b>Fuellen#1,Zeigen#0;-;f;k;?', 3, mSummary));
  Assert.AreEqual(Ord(TParamEffect.Keeps), Ord(mSummary.Effect));
  Assert.IsTrue(TParamOwnership.Decode('b>Fuellen#1,Zeigen#0;-;f;k;?', 4, mSummary));
  Assert.AreEqual(Ord(TParamEffect.Unknown), Ord(mSummary.Effect));
  Assert.IsFalse(TParamOwnership.Decode('b;f', 2, mSummary));
  Assert.IsFalse(TParamOwnership.Decode('', 0, mSummary));
  // Kaputte Weitergabe: unklar statt geliehen.
  Assert.IsTrue(TParamOwnership.Decode('b>Fuellen', 0, mSummary));
  Assert.AreEqual(Ord(TParamEffect.Unknown), Ord(mSummary.Effect));
  mSummary := Default(TParamSummary);
end;

end.
