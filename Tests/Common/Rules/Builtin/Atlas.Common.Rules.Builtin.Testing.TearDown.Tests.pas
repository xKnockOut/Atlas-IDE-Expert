unit Atlas.Common.Rules.Builtin.Testing.TearDown.Tests;

// Tests der Regel dunitx-setup-not-torn-down (#1781): Objekt im Setup erzeugt und im TearDown nicht freigegeben,
// fehlende TearDown-Methode samt Korrektur, Freigabe über eine Hilfsmethode, Interface- und Besitzer-Felder,
// string- und Array-Felder mit der Option managedFields, Korrektur ohne SysUtils, SetupFixture.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDUnitXSetupNotTornDownTests = class
  public
    [Test]
    procedure ObjectNotFreed;
    [Test]
    procedure WithoutTearDown;
    [Test]
    procedure ReleasedOrNotOwned;
    [Test]
    procedure ManagedFields;
    [Test]
    procedure FixWithoutSysUtils;
    [Test]
    procedure SetupFixture;
    [Test]
    procedure SilentOutsideTests;
    [Test]
    procedure RuleIsRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Rules.Builtin.Testing.TearDown,
  Atlas.Tests.RuleAssert;

const
  cNoTearDown = '-';

/// <summary>Testunit mit den Feldern AFields, dem Rumpf ASetup von Setup und ATearDown von TearDown (cNoTearDown:
/// keine TearDown-Methode). Jede Zeile endet mit #10.</summary>
function TestUnit(const AFields, ASetup, ATearDown: string): string;
var
  mDecl, mImpl: string;
begin
  mDecl := '';
  mImpl := '';
  if ATearDown <> cNoTearDown then
  begin
    mDecl := '    [TearDown]'#10'    procedure TearDown;'#10;
    mImpl := #10'procedure TFallTests.TearDown;'#10'begin'#10 + ATearDown + 'end;'#10;
  end;
  Result := 'unit Fall.Tests;'#10'interface'#10'uses'#10'  System.SysUtils, DUnitX.TestFramework;'#10'type'#10 +
    '  TFake = class'#10'  end;'#10'  IDing = interface'#10'  end;'#10 +
    '  TDing = class(TInterfacedObject, IDing)'#10'  end;'#10'  [TestFixture]'#10'  TFallTests = class'#10 +
    '  private'#10 + AFields + '    procedure Weg;'#10'  public'#10'    [Setup]'#10'    procedure Setup;'#10 + mDecl +
    '    [Test]'#10'    procedure Pruefe;'#10'  end;'#10'implementation'#10'procedure TFallTests.Setup;'#10 +
    'begin'#10 + ASetup + 'end;'#10 + mImpl + 'procedure TFallTests.Weg;'#10'begin'#10'  FFake.Free;'#10'end;'#10 +
    'procedure TFallTests.Pruefe;'#10'begin'#10'  Assert.Pass;'#10'end;'#10'initialization'#10 +
    '  TDUnitX.RegisterTestFixture(TFallTests);'#10'end.';
end;

function Findings(const ASource: string; const AConfig: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TDUnitXSetupNotTornDownRule.Create, ASource, AConfig, 'Fall.Tests.pas');
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := Findings(ASource, '');
end;

function Messages(const ASource: string; const AConfig: string): string; overload;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in Findings(ASource, AConfig) do
  begin
    if Result <> '' then
    begin
      Result := Result + ' | ';
    end;
    Result := Result + IntToStr(mFinding.Range.StartPos.Line) + ': ' + mFinding.Message;
  end;
end;

function Messages(const ASource: string): string; overload;
begin
  Result := Messages(ASource, '');
end;

/// <summary>ASource nach der ersten Korrektur des ersten Befunds.</summary>
function Fixed(const ASource: string): string;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(ASource);
  Result := '';
  if (Length(mFound) > 0) and (Length(mFound[0].Fixes) > 0) then
  begin
    Result := TChangeSignature.ApplyEdits(ASource, mFound[0].Fixes[0].Edits);
  end;
end;

{ TDUnitXSetupNotTornDownTests }

procedure TDUnitXSetupNotTornDownTests.ObjectNotFreed;
const
  cFields = '    FFake: TFake;'#10'    FAndere: TFake;'#10;
  cSetup = '  FFake := TFake.Create;'#10'  Self.FAndere := TFake.Create;'#10;
begin
  Assert.AreEqual('28: FFake wird in Setup erzeugt, aber in TearDown nicht freigegeben: Jeder Test leckt ein TFake.',
    Messages(TestUnit(cFields, cSetup, '  FreeAndNil(FAndere);'#10)));
  Assert.AreEqual(TestUnit(cFields, cSetup, '  FreeAndNil(FAndere);'#10'  FreeAndNil(FFake);'#10),
    Fixed(TestUnit(cFields, cSetup, '  FreeAndNil(FAndere);'#10)));
end;

procedure TDUnitXSetupNotTornDownTests.WithoutTearDown;
const
  cFields = '    FFake: TFake;'#10'    FName: string;'#10;
  cSetup = '  FFake := TFake.Create;'#10'  FName := ''x'';'#10;
begin
  Assert.AreEqual('19: Setup belegt FFake, FName, die Klasse hat aber keine [TearDown]-Methode: Jeder Test leckt.',
    Messages(TestUnit(cFields, cSetup, cNoTearDown)));
  Assert.AreEqual(TestUnit(cFields, cSetup, '  FreeAndNil(FFake);'#10'  FName := '''';'#10),
    Fixed(TestUnit(cFields, cSetup, cNoTearDown)));
end;

procedure TDUnitXSetupNotTornDownTests.ReleasedOrNotOwned;
const
  cFields = '    FFake, FZwei, FDrei, FVier: TFake;'#10'    FDing: IDing;'#10'    FKind: TFake;'#10;
begin
  // FreeAndNil, Free über Self, := nil und Free in einer Hilfsmethode; Interface; Objekt mit Besitzer.
  Assert.AreEqual('', Messages(TestUnit(cFields, '  FFake := TFake.Create;'#10'  FZwei := TFake.Create;'#10 +
    '  FDrei := TFake.Create;'#10'  FVier := TFake.Create;'#10'  FDing := TDing.Create;'#10 +
    '  FKind := TFake.Create(FZwei);'#10, '  Weg;'#10'  FreeAndNil(FZwei);'#10'  Self.FDrei.Free;'#10 +
    '  FVier.Free;'#10'  FVier := nil;'#10)));
  // An ein Interface-Feld übergeben: Die Referenzzählung gibt frei.
  Assert.AreEqual('', Messages(TestUnit('    FFake: TFake;'#10'    FDing: IDing;'#10, '  FFake := TFake.Create;'#10 +
    '  FDing := FFake;'#10, '')));
end;

procedure TDUnitXSetupNotTornDownTests.ManagedFields;
const
  cFields = '    FName: string;'#10'    FListe: TArray<Integer>;'#10'    FLeer: string;'#10;
  cSetup = '  FName := ''x'';'#10'  FListe := [1, 2];'#10'  FLeer := '''';'#10;
begin
  Assert.AreEqual('29: FName wird in Setup belegt, aber in TearDown nicht geleert: Der Leckmonitor zählt den ' +
    'Speicher jedem Test zu. | 30: FListe wird in Setup belegt, aber in TearDown nicht geleert: Der Leckmonitor ' +
    'zählt den Speicher jedem Test zu.', Messages(TestUnit(cFields, cSetup, '')));
  Assert.AreEqual(TestUnit(cFields, cSetup, '  FName := '''';'#10), Fixed(TestUnit(cFields, cSetup, '')));
  Assert.AreEqual('', Messages(TestUnit(cFields, cSetup, '  FName := '''';'#10'  SetLength(FListe, 0);'#10)));
  // Übergabe an eine Routine (var-Parameter) zählt als Leeren.
  Assert.AreEqual('', Messages(TestUnit(cFields, cSetup, '  Leeren(FName);'#10'  RevokeAll(FListe);'#10)));
  Assert.AreEqual('', Messages(TestUnit(cFields, cSetup, ''),
    '{"rules": {"dunitx-setup-not-torn-down": {"managedFields": false}}}'));
end;

procedure TDUnitXSetupNotTornDownTests.FixWithoutSysUtils;
var
  mSource: string;
begin
  mSource := StringReplace(TestUnit('    FFake: TFake;'#10, '  FFake := TFake.Create;'#10, ''), 'System.SysUtils, ',
    '', []);
  Assert.AreEqual(StringReplace(TestUnit('    FFake: TFake;'#10, '  FFake := TFake.Create;'#10,
    '  FFake.Free;'#10'  FFake := nil;'#10), 'System.SysUtils, ', '', []), Fixed(mSource));
end;

procedure TDUnitXSetupNotTornDownTests.SetupFixture;
var
  mSource: string;
begin
  mSource := StringReplace(StringReplace(TestUnit('    FFake: TFake;'#10, '  FFake := TFake.Create;'#10, ''),
    '[Setup]', '[SetupFixture]', []), '[TearDown]', '[TearDownFixture]', []);
  Assert.AreEqual('27: FFake wird in Setup erzeugt, aber in TearDown nicht freigegeben: Jeder Test leckt ein TFake.',
    Messages(mSource));
  // [Setup] ohne passendes [TearDown]: TearDownFixture zählt nicht.
  mSource := StringReplace(TestUnit('    FFake: TFake;'#10, '  FFake := TFake.Create;'#10, '  FFake.Free;'#10),
    '[TearDown]', '[TearDownFixture]', []);
  Assert.AreEqual(1, Integer(Length(Findings(mSource))));
end;

procedure TDUnitXSetupNotTornDownTests.SilentOutsideTests;
begin
  Assert.AreEqual('', Messages(StringReplace(TestUnit('    FFake: TFake;'#10, '  FFake := TFake.Create;'#10, ''),
    'DUnitX.TestFramework', 'System.Classes', [])));
end;

procedure TDUnitXSetupNotTornDownTests.RuleIsRegistered;
var
  mRule: IRule;
  mFound: Boolean;
begin
  mFound := False;
  for mRule in BuiltinRules do
  begin
    mFound := mFound or (mRule.Descriptor.Id = cDUnitXSetupNotTornDownRuleId);
  end;
  Assert.IsTrue(mFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TDUnitXSetupNotTornDownTests);

end.
