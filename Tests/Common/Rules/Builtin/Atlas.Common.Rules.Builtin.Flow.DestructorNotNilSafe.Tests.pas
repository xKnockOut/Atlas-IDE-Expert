unit Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe.Tests;

// Tests der Teilunit destructor-not-nil-safe: Zugriff nach werfendem Konstruktor, Abfrage, Kurzschluss, Korrektur.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFlowDestructorNotNilSafeTests = class
  public
    [Test]
    procedure AccessAfterRaisingCreateIsReported;
    [Test]
    procedure AssignedGuardIsSilent;
    [Test]
    procedure ShortCircuitIsSilent;
    [Test]
    procedure FreeIsSilent;
    [Test]
    procedure FixWrapsStatement;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit TImport (Felder FStrom und FZeilen), dem Konstruktor-Rumpf AConstructor und dem
/// Destruktor-Rumpf ADestructor.</summary>
function ImportUnit(const AConstructor, ADestructor: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TImport = class'#10'  private'#10'    FStrom: TFileStream;'#10 +
    '    FZeilen: TStringList;'#10'  public'#10'    constructor Create(const Datei: string);'#10 +
    '    destructor Destroy; override;'#10'  end;'#10'implementation'#10 +
    'constructor TImport.Create(const Datei: string);'#10'begin'#10 + AConstructor + #10'end;'#10 +
    'destructor TImport.Destroy;'#10'begin'#10 + ADestructor + #10'end;'#10'end.';
end;

const
  cCreate = '  inherited Create;'#10'  FStrom := TFileStream.Create(Datei, fmOpenRead);'#10 +
    '  FZeilen := TStringList.Create;';

procedure TFlowDestructorNotNilSafeTests.AccessAfterRaisingCreateIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TDestructorNotNilSafeRule.Create, ImportUnit(cCreate, '  FZeilen.Clear;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(DestructorNotNilSafeRuleId, mFindings[0].RuleId);
end;

procedure TFlowDestructorNotNilSafeTests.AssignedGuardIsSilent;
begin
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(cCreate, '  if Assigned(FZeilen) then'#10 +
    '    FZeilen.Clear;'));
end;

procedure TFlowDestructorNotNilSafeTests.ShortCircuitIsSilent;
begin
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(cCreate, '  if (FZeilen <> nil) and ' +
    '(FZeilen.Count > 0) then'#10'    Exit;'));
end;

procedure TFlowDestructorNotNilSafeTests.FreeIsSilent;
begin
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(cCreate, '  FZeilen.Free;'#10'  FStrom.Free;'));
end;

procedure TFlowDestructorNotNilSafeTests.FixWrapsStatement;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TDestructorNotNilSafeRule.Create, ImportUnit(cCreate, '  FZeilen.Clear;'));
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('if Assigned(FZeilen) then'#10'    FZeilen.Clear', mFindings[0].Fixes[0].Edits[0].NewText);
end;

initialization
  TDUnitX.RegisterTestFixture(TFlowDestructorNotNilSafeTests);

end.
