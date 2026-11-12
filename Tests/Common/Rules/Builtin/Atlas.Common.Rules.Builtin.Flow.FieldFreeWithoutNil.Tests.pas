unit Atlas.Common.Rules.Builtin.Flow.FieldFreeWithoutNil.Tests;

// Tests der Teilunit field-free-without-nil: Free ohne nil, Neusetzen, Destruktor, TearDown.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFlowFieldFreeWithoutNilTests = class
  public
    [Test]
    procedure FreeWithoutNilIsReported;
    [Test]
    procedure AssignerMethodIsSilent;
    [Test]
    procedure DestructorIsSilent;
    [Test]
    procedure TearDownIsSilent;
    [Test]
    procedure DestroyHandlerAndDUnitTearDownAreSilent;
    [Test]
    procedure DefaultIgnoreMethodsNameDestroy;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Flow.FieldFreeWithoutNil,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit der Klasse TLader (Feld FDaten, Methoden Laden und Leeren) und dem Implementierungsteil
/// AImplementation.</summary>
function ClassUnit(const AImplementation: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TLader = class'#10'  private'#10'    FDaten: TObject;'#10 +
    '    procedure Laden;'#10'    procedure Leeren;'#10'  public'#10'    destructor Destroy; override;'#10 +
    '  end;'#10'implementation'#10 + AImplementation + 'end.';
end;

procedure TFlowFieldFreeWithoutNilTests.FreeWithoutNilIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TFieldFreeWithoutNilRule.Create, ClassUnit(
    'procedure TLader.Leeren;'#10'begin'#10'  FDaten.Free;'#10'end;'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cFieldFreeWithoutNilRuleId, mFindings[0].RuleId);
  Assert.AreEqual('FreeAndNil(FDaten)', mFindings[0].Fixes[0].Edits[0].NewText);
end;

procedure TFlowFieldFreeWithoutNilTests.AssignerMethodIsSilent;
begin
  TRuleAssert.Silent(TFieldFreeWithoutNilRule.Create, ClassUnit(
    'procedure TLader.Laden;'#10'begin'#10'  FDaten := TObject.Create;'#10'end;'#10 +
    'procedure TLader.Leeren;'#10'begin'#10'  FDaten.Free;'#10'  Self.Laden();'#10'end;'#10));
end;

procedure TFlowFieldFreeWithoutNilTests.DestructorIsSilent;
begin
  TRuleAssert.Silent(TFieldFreeWithoutNilRule.Create, ClassUnit(
    'destructor TLader.Destroy;'#10'begin'#10'  FDaten.Free;'#10'  inherited;'#10'end;'#10));
end;

procedure TFlowFieldFreeWithoutNilTests.TearDownIsSilent;
begin
  TRuleAssert.Silent(TFieldFreeWithoutNilRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TTests = class'#10'  private'#10'    FDaten: TObject;'#10 +
    '  public'#10'    [TearDown]'#10'    procedure Aufraeumen;'#10'  end;'#10'implementation'#10 +
    'procedure TTests.Aufraeumen;'#10'begin'#10'  FDaten.Free;'#10'end;'#10'end.');
end;

procedure TFlowFieldFreeWithoutNilTests.DestroyHandlerAndDUnitTearDownAreSilent;
var
  mFindings: TArray<TRuleFinding>;
begin
  // FP-Prüfung 28.10.2026: OnDestroy-Behandlung wie von der IDE angelegt und TearDown aus DUnit (override).
  TRuleAssert.Silent(TFieldFreeWithoutNilRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TForm1 = class(TForm)'#10'    procedure FormDestroy(Sender: TObject);'#10 +
    '  private'#10'    FDaten: TObject;'#10'  end;'#10'  TTests = class(TTestCase)'#10'  private'#10 +
    '    FDaten: TObject;'#10'  protected'#10'    procedure TearDown; override;'#10'  end;'#10'implementation'#10 +
    'procedure TForm1.FormDestroy(Sender: TObject);'#10'begin'#10'  FDaten.Free;'#10'end;'#10 +
    'procedure TTests.TearDown;'#10'begin'#10'  FDaten.Free;'#10'end;'#10'end.');
  // Ein Name auf Destroy ohne Sender-Parameter bleibt ein Treffer.
  mFindings := TRuleAssert.Findings(TFieldFreeWithoutNilRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TLader = class'#10'  private'#10'    FDaten: TObject;'#10 +
    '    procedure DatenDestroy;'#10'  end;'#10'implementation'#10 +
    'procedure TLader.DatenDestroy;'#10'begin'#10'  FDaten.Free;'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  mFindings := nil;
end;

procedure TFlowFieldFreeWithoutNilTests.DefaultIgnoreMethodsNameDestroy;
begin
  Assert.AreEqual('Destroy', TFieldFreeWithoutNilRule.DefaultIgnoreMethods[0]);
end;

initialization
  TDUnitX.RegisterTestFixture(TFlowFieldFreeWithoutNilTests);

end.
