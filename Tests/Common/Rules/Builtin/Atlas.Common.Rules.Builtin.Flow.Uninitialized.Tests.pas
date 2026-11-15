unit Atlas.Common.Rules.Builtin.Flow.Uninitialized.Tests;

// Tests der Teilunit possibly-uninitialized: Lesen vor der ersten Zuweisung, Merker, verwaltete Typen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFlowUninitializedTests = class
  public
    [Test]
    procedure ReadBeforeAssignIsReported;
    [Test]
    procedure AssignedOnAllPathsIsSilent;
    [Test]
    procedure GuardedByFlagIsSilent;
    [Test]
    procedure ManagedTypeIsSilent;
    [Test]
    procedure RecordMethodFromOtherUnitIsSilent;
    [Test]
    procedure MethodOfRecordFieldIsSilent;
    [Test]
    procedure NameInsideWithIsSilent;
    [Test]
    procedure MethodOfOldStyleObjectIsSilent;
    [Test]
    procedure LoopOverConstantArrayIsSilent;
    [Test]
    procedure AbsoluteOverlayIsSilent;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Flow.Uninitialized,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit "procedure P(B: Boolean)", den Variablen AVars und dem Rumpf ABody.</summary>
function Routine(const AVars, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure Zeige(A: Integer);'#10'begin'#10'end;'#10 +
    'procedure P(B: Boolean);'#10'var'#10 + AVars + #10'begin'#10 + ABody + #10'end;'#10'end.';
end;

{ TFlowUninitializedTests }

procedure TFlowUninitializedTests.ReadBeforeAssignIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TPossiblyUninitializedRule.Create, Routine('  N: Integer;',
    '  if B then'#10'    N := 1;'#10'  Zeige(N + 1);'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('possibly-uninitialized', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
end;

procedure TFlowUninitializedTests.AssignedOnAllPathsIsSilent;
begin
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create, Routine('  N: Integer;',
    '  if B then'#10'    N := 1'#10'  else'#10'    N := 2;'#10'  Zeige(N + 1);'));
end;

procedure TFlowUninitializedTests.GuardedByFlagIsSilent;
begin
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create, Routine('  N: Integer;'#10'  Gefunden: Boolean;',
    '  Gefunden := False;'#10'  if B then'#10'  begin'#10'    N := 1;'#10'    Gefunden := True;'#10'  end;'#10 +
    '  if Gefunden then'#10'    Zeige(N + 1);'));
end;

procedure TFlowUninitializedTests.ManagedTypeIsSilent;
begin
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create, Routine('  S, T: string;', '  T := S;'));
end;

procedure TFlowUninitializedTests.RecordMethodFromOtherUnitIsSilent;
const
  cSource = 'unit U;'#10'interface'#10'uses Fremd;'#10'implementation'#10'procedure P(B: Boolean);'#10'var'#10 +
    '  G: TAufraeumer;'#10'  O: TObject;'#10'begin'#10'  if B then'#10'    O := G.Merke(TObject.Create);'#10 +
    'end;'#10'end.';
var
  mIndex: ISymbolIndex;
  mFindings: TArray<TRuleFinding>;
begin
  // Die Methode bekommt den Record als var-Self, auch wenn er in einer anderen Unit steht (PascalCoin:
  // GC.AddObject mit TDisposables aus UMemory).
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Fremd;'#10'interface'#10'type'#10'  TAufraeumer = record'#10 +
    '  private'#10'    FZeiger: array of Pointer;'#10'  public'#10 +
    '    function Merke(const AObjekt: TObject): TObject;'#10'  end;'#10'implementation'#10 +
    'function TAufraeumer.Merke(const AObjekt: TObject): TObject;'#10'begin'#10'  Result := AObjekt;'#10'end;'#10 +
    'end.', 'C:\P\Fremd.pas', nil));
  mFindings := TRuleAssert.IndexFindings(TPossiblyUninitializedRule.Create, cSource, mIndex, '', 'U.pas');
  Assert.AreEqual(0, Integer(Length(mFindings)));
  // Ohne Index bleibt der Befund (Record unbekannt).
  TRuleAssert.Reports(TPossiblyUninitializedRule.Create, cSource);
end;

procedure TFlowUninitializedTests.MethodOfRecordFieldIsSilent;
const
  cSource = 'unit U;'#10'interface'#10'uses Fremd;'#10'type'#10'  THuelle = record'#10'    Bag: TAufraeumer;'#10 +
    '  end;'#10'implementation'#10'procedure P;'#10'var'#10'  H: THuelle;'#10'begin'#10 +
    '  H.Bag.Merke(TObject.Create);'#10'end;'#10'end.';
var
  mIndex: ISymbolIndex;
  mFindings: TArray<TRuleFinding>;
begin
  // Die Methode bekommt das Record-Feld als var-Self (PascalCoin: Container.Bag.AddObject mit TDisposables).
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Fremd;'#10'interface'#10'type'#10'  TAufraeumer = record'#10 +
    '  private'#10'    FZeiger: array of Pointer;'#10'  public'#10 +
    '    function Merke(const AObjekt: TObject): TObject;'#10'  end;'#10'implementation'#10 +
    'function TAufraeumer.Merke(const AObjekt: TObject): TObject;'#10'begin'#10'  Result := AObjekt;'#10'end;'#10 +
    'end.', 'C:\P\Fremd.pas', nil));
  mFindings := TRuleAssert.IndexFindings(TPossiblyUninitializedRule.Create, cSource, mIndex, '', 'U.pas');
  Assert.AreEqual(0, Integer(Length(mFindings)));
  // Ohne Index bleibt der Befund (Feldtyp unbekannt).
  TRuleAssert.Reports(TPossiblyUninitializedRule.Create, cSource);
end;

procedure TFlowUninitializedTests.NameInsideWithIsSilent;
begin
  // Im with-Rumpf kann Breite ein Mitglied von TRect(…) sein und die lokale Variable verdecken.
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create, Routine('  Breite, N: Integer;',
    '  N := 0;'#10'  if B then'#10'    Breite := 1'#10'  else'#10'    with TRect(Self) do'#10'      N := Breite;'#10 +
    '  Zeige(N);'));
  // Der Ausdruck hinter with gehört nicht zum Rumpf und wird weiter geprüft.
  TRuleAssert.Reports(TPossiblyUninitializedRule.Create, Routine('  Breite, N: Integer;',
    '  N := 0;'#10'  with Liste[Breite] do'#10'    Zeige(N);'));
end;

procedure TFlowUninitializedTests.MethodOfOldStyleObjectIsSilent;
const
  cTypes = 'type'#10'  TBasis = object'#10'    P: PChar;'#10'    procedure Init(const S: string);'#10'  end;'#10 +
    '  TEsc = object(TBasis)'#10'    procedure Weiter;'#10'  end;'#10;
begin
  // Ein old-style object bekommt Self wie ein Record als var-Parameter: E.Init legt E an, auch geerbt.
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create, 'unit U;'#10'interface'#10 + cTypes + 'implementation'#10 +
    'procedure Run;'#10'var'#10'  E: TEsc;'#10'begin'#10'  E.Init(''abc'');'#10'end;'#10'end.');
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create, 'unit U;'#10'interface'#10 + cTypes + 'implementation'#10 +
    'procedure Run;'#10'var'#10'  E: TBasis;'#10'begin'#10'  E.Init(''abc'');'#10'end;'#10'end.');
  // Nur ein Feld gelesen: Das bleibt ein Befund.
  TRuleAssert.Reports(TPossiblyUninitializedRule.Create, 'unit U;'#10'interface'#10 + cTypes + 'implementation'#10 +
    'procedure Run(var Q: PChar);'#10'var'#10'  E: TEsc;'#10'begin'#10'  Q := E.P;'#10'end;'#10'end.');
end;

procedure TFlowUninitializedTests.LoopOverConstantArrayIsSilent;
const
  cHead = 'unit U;'#10'interface'#10'implementation'#10'const'#10'  A: array[0..2] of Integer = (1, 2, 3);'#10 +
    'function F(X: Integer): Boolean;'#10'var'#10'  B: Boolean;'#10'  I: Integer;'#10'  D: array of Integer;'#10 +
    'begin'#10;
begin
  // Die Grenzen sind beim Übersetzen bekannt und der Bereich nicht leer: Der Rumpf läuft sicher einmal.
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create, cHead + '  for I := Low(A) to High(A) do'#10'  begin'#10 +
    '    B := A[I] = X;'#10'    if B then'#10'      Break;'#10'  end;'#10'  Result := B;'#10'end;'#10'end.');
  // Dynamisches Array: Die Schleife kann leer sein.
  TRuleAssert.Reports(TPossiblyUninitializedRule.Create, cHead + '  for I := Low(D) to High(D) do'#10'  begin'#10 +
    '    B := D[I] = X;'#10'    if B then'#10'      Break;'#10'  end;'#10'  Result := B;'#10'end;'#10'end.');
end;

procedure TFlowUninitializedTests.AbsoluteOverlayIsSilent;
const
  cHead = 'unit U;'#10'interface'#10'implementation'#10'function HexToDouble(A, B: Integer): Double;'#10'var'#10 +
    '  D: Double;'#10;
begin
  // Overlay liegt über D: Die Zuweisungen an Overlay setzen D.
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create, cHead + '  Overlay: array[1..2] of Longint absolute D;'#10 +
    'begin'#10'  Overlay[1] := A;'#10'  Overlay[2] := B;'#10'  Result := D;'#10'end;'#10'end.');
  // Ohne absolute bleibt D ungesetzt.
  TRuleAssert.Reports(TPossiblyUninitializedRule.Create, cHead + '  Overlay: array[1..2] of Longint;'#10 +
    'begin'#10'  Overlay[1] := A;'#10'  Overlay[2] := B;'#10'  Result := D;'#10'end;'#10'end.');
end;

initialization
  TDUnitX.RegisterTestFixture(TFlowUninitializedTests);

end.
