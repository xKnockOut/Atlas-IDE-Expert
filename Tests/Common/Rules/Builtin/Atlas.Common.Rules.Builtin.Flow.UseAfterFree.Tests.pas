unit Atlas.Common.Rules.Builtin.Flow.UseAfterFree.Tests;

// Tests der Teilunit use-after-free: Lesen nach Free, Neuzuweisung, Abfrage mit Assigned, Übergabe als Argument.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFlowUseAfterFreeTests = class
  public
    [Test]
    procedure ReadAfterFreeIsReported;
    [Test]
    procedure ReassignedIsSilent;
    [Test]
    procedure AssignedAfterFreeAndNilIsSilent;
    [Test]
    procedure PassedAsArgumentIsSilent;
    [Test]
    procedure AssignedAfterFreeIsReported;
    [Test]
    procedure OwnMethodMayReassignField;
    /// <summary>Im Rumpf eines with kann der Name ein Mitglied des with-Objekts sein (ACBr: NFSe.Free; … with
    /// Liste.New do NFSe.Numero := …): still; der with-Ausdruck selbst bleibt ein Zugriff.</summary>
    [Test]
    procedure WithMemberOfSameNameIsSilent;
    [Test]
    procedure NestedRoutineOrAbsoluteMayReassign;
  end;


implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Flow.UseAfterFree,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit "procedure P(L: TStringList)" und dem Rumpf ABody.</summary>
function Routine(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure Merke(A: TObject);'#10'begin'#10'end;'#10 +
    'procedure P(L: TStringList);'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

{ TFlowUseAfterFreeTests }

procedure TFlowUseAfterFreeTests.ReadAfterFreeIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TUseAfterFreeRule.Create, Routine('  L.Free;'#10'  L.Clear;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cUseAfterFreeRuleId, mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
end;

procedure TFlowUseAfterFreeTests.ReassignedIsSilent;
begin
  TRuleAssert.Silent(TUseAfterFreeRule.Create, Routine('  L.Free;'#10'  L := TStringList.Create;'#10'  L.Clear;'));
end;

procedure TFlowUseAfterFreeTests.AssignedAfterFreeAndNilIsSilent;
begin
  TRuleAssert.Silent(TUseAfterFreeRule.Create, Routine('  FreeAndNil(L);'#10'  if Assigned(L) then'#10 +
    '    L.Clear;'));
end;

procedure TFlowUseAfterFreeTests.PassedAsArgumentIsSilent;
begin
  TRuleAssert.Silent(TUseAfterFreeRule.Create, Routine('  L.Free;'#10'  Merke(L);'#10'  L.Clear;'));
end;

procedure TFlowUseAfterFreeTests.AssignedAfterFreeIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TUseAfterFreeRule.Create, Routine('  L.Free;'#10'  if Assigned(L) then'#10 +
    '    Merke(nil);'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
end;

procedure TFlowUseAfterFreeTests.OwnMethodMayReassignField;
const
  cHead = 'unit U;'#10'interface'#10'type'#10'  TLader = class'#10'  private'#10'    FListe: TList;'#10 +
    '    procedure Neu;'#10'    procedure Laden;'#10'  end;'#10'implementation'#10 +
    'procedure TLader.Neu;'#10'begin'#10'  FListe := TList.Create;'#10'end;'#10 +
    'procedure TLader.Laden;'#10'begin'#10;
var
  mFindings: TArray<TRuleFinding>;
begin
  // FP-Prüfung 28.10.2026: Eine eigene Methode zwischen Free und Zugriff kann das Feld neu belegen.
  TRuleAssert.Silent(TUseAfterFreeRule.Create, cHead + '  FListe.Free;'#10'  Neu;'#10'  FListe.Add(nil);'#10 +
    '  FListe.Free;'#10'  Self.Neu;'#10'  FListe.Add(nil);'#10'end;'#10'end.');
  // inherited ruft eine Methode für Self auf (ACBr TACBrECFVirtualClass: FreeAndNil(fpAliquotas);
  // inherited CarregaAliquotas; fpAliquotas.Add(…)).
  TRuleAssert.Silent(TUseAfterFreeRule.Create, cHead + '  FreeAndNil(FListe);'#10'  inherited Laden;'#10 +
    '  FListe.Add(nil);'#10'end;'#10'end.');
  // Eine fremde Routine belegt das Feld nicht neu.
  mFindings := TRuleAssert.Findings(TUseAfterFreeRule.Create, cHead + '  FListe.Free;'#10'  Melden;'#10 +
    '  FListe.Add(nil);'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  // inherited belegt nur Felder neu, keine lokale Variable.
  mFindings := TRuleAssert.Findings(TUseAfterFreeRule.Create, Copy(cHead, 1, Length(cHead) - Length('begin'#10)) +
    'var'#10'  L: TList;'#10'begin'#10'  L := TList.Create;'#10'  L.Free;'#10'  inherited Laden;'#10'  L.Add(nil);'#10 +
    'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)), 'lokal nach inherited');
  mFindings := nil;
end;

procedure TFlowUseAfterFreeTests.WithMemberOfSameNameIsSilent;
var
  mFindings: TArray<TRuleFinding>;
begin
  TRuleAssert.Silent(TUseAfterFreeRule.Create, Routine('  L.Free;'#10'  with Merke2 do'#10'  begin'#10 +
    '    L.Add(''x'');'#10'  end;'));
  mFindings := TRuleAssert.Findings(TUseAfterFreeRule.Create, Routine('  L.Free;'#10'  with L do'#10'    Clear;'));
  Assert.AreEqual(1, Integer(Length(mFindings)), 'with L');
  mFindings := nil;
end;

procedure TFlowUseAfterFreeTests.NestedRoutineOrAbsoluteMayReassign;
var
  mFindings: TArray<TRuleFinding>;
begin
  // FP mORMot: Eine lokale Routine setzt die Variable der umgebenden Routine neu (CreateMaster).
  TRuleAssert.Silent(TUseAfterFreeRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure P;'#10'var'#10'  L: TStringList;'#10'  procedure Neu;'#10'  begin'#10 +
    '    L := TStringList.Create;'#10'  end;'#10'begin'#10'  Neu;'#10'  L.Free;'#10'  Neu;'#10'  L.Clear;'#10 +
    'end;'#10'end.');
  // FP mORMot (SynBigTable): Neu gesetzt über eine Variable, die mit absolute auf L liegt.
  TRuleAssert.Silent(TUseAfterFreeRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure P(L: TStrings);'#10'var'#10'  S: TStringList absolute L;'#10'begin'#10'  L.Free;'#10 +
    '  S := TStringList.Create;'#10'  L.Clear;'#10'end;'#10'end.');
  // Ein anderer Name ohne absolute beendet den Weg nicht.
  mFindings := TRuleAssert.Findings(TUseAfterFreeRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure P(L: TStrings);'#10'var'#10'  S: TStringList;'#10'begin'#10'  L.Free;'#10 +
    '  S := TStringList.Create;'#10'  L.Clear;'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  mFindings := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TFlowUseAfterFreeTests);

end.
