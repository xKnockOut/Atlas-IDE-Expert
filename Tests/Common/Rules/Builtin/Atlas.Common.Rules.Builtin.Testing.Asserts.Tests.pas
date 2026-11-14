unit Atlas.Common.Rules.Builtin.Testing.Asserts.Tests;

// Tests der Regeln dunitx-istrue-equality und dunitx-swapped-expected (#1780): Korrektur zu AreEqual, AreNotEqual,
// AreSame, AreNotSame, IsNull und IsNotNull samt Meldungsargument, Hinweis ohne Korrektur bei Gleitkomma,
// Aufzählung und NativeInt, still bei Records und nil/Assigned auf Methodenzeigern und -referenzen (kein
// passendes Assert, #2197), vertauschte Argumente mit Literal, Konstante und Aufzählungswert, stille Fälle.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDUnitXAssertsTests = class
  public
    [Test]
    procedure IsTrueBecomesAreEqual;
    [Test]
    procedure NilAndAssigned;
    [Test]
    procedure HintWithoutFix;
    [Test]
    procedure EqualitySilent;
    [Test]
    procedure SilentWithoutFittingAssert;
    [Test]
    procedure SwappedArguments;
    [Test]
    procedure SwappedSilent;
    [Test]
    procedure RulesAreRegistered;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Rules.Builtin.Testing.Asserts,
  Atlas.Tests.RuleAssert;

const
  // Zeile der ersten Anweisung im Rumpf von Pruefe (ab 0).
  cBodyLine = 34;

/// <summary>Testunit mit ABody als Rumpf von TFallTests.Pruefe.</summary>
function TestUnit(const ABody: string): string;
begin
  Result := 'unit Fall.Tests;'#10'interface'#10'uses'#10'  DUnitX.TestFramework;'#10'type'#10 +
    '  TFake = class'#10'  public'#10'    Calls: Integer;'#10'    Name: string;'#10'    Wert: Double;'#10 +
    '  end;'#10'  IDing = interface'#10'  end;'#10'  TFarbe = (Rot, Gruen);'#10 +
    '  TAktion = procedure of object; TFrage = reference to function: Boolean;'#10 +
    '  TPunkt = record X: Integer; class operator Equal(const A, B: TPunkt): Boolean; end;'#10 +
    '  [TestFixture]'#10'  TFallTests = class'#10'  private'#10 +
    '    FFake, FAnderer: TFake;'#10'    FDing: IDing;'#10'    FListe: TArray<Integer>;'#10'    FFarbe: TFarbe;'#10 +
    '    FAktion: TAktion; FFrage: TFrage; FPunkt, FAnders: TPunkt;'#10'  public'#10'    [Test]'#10 +
    '    procedure Pruefe;'#10'  end;'#10 +
    'implementation'#10'const'#10'  cVier = 4;'#10'  cName = ''Atlas'';'#10 +
    'procedure TFallTests.Pruefe;'#10'begin'#10 + ABody + #10'end;'#10'initialization'#10 +
    '  TDUnitX.RegisterTestFixture(TFallTests);'#10'end.';
end;

function Findings(ARule: IRule; const ABody: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(ARule, TestUnit(ABody), '', 'Fall.Tests.pas');
end;

/// <summary>Erste Anweisung des Rumpfs nach der ersten Korrektur des ersten Befunds; '' ohne Korrektur.</summary>
function Fixed(ARule: IRule; const ABody: string): string;
var
  mFound: TArray<TRuleFinding>;
begin
  Result := '';
  mFound := Findings(ARule, ABody);
  if (Length(mFound) = 1) and (Length(mFound[0].Fixes) > 0) then
  begin
    Result := Trim(SplitString(TChangeSignature.ApplyEdits(TestUnit(ABody), mFound[0].Fixes[0].Edits),
      #10)[cBodyLine]);
  end;
end;

function Equality(const ABody: string): string;
begin
  Result := Fixed(TDUnitXIsTrueEqualityRule.Create, ABody);
end;

function Swapped(const ABody: string): string;
begin
  Result := Fixed(TDUnitXSwappedExpectedRule.Create, ABody);
end;

function Count(ARule: IRule; const ABody: string): Integer;
begin
  Result := Length(Findings(ARule, ABody));
end;

{ TDUnitXAssertsTests }

procedure TDUnitXAssertsTests.IsTrueBecomesAreEqual;
begin
  Assert.AreEqual('Assert.AreEqual(1, FFake.Calls);', Equality('  Assert.IsTrue(FFake.Calls = 1);'));
  // Die Meldung bleibt als drittes Argument.
  Assert.AreEqual('Assert.AreEqual(1, FFake.Calls, ''Aufrufe'');',
    Equality('  Assert.IsTrue(FFake.Calls = 1, ''Aufrufe'');'));
  Assert.AreEqual('Assert.AreEqual(''x'', FFake.Name);', Equality('  Assert.IsFalse(FFake.Name <> ''x'');'));
  // Konstante links bleibt vorn.
  Assert.AreEqual('Assert.AreNotEqual(cVier, FFake.Calls);', Equality('  Assert.IsTrue(cVier <> FFake.Calls);'));
  Assert.AreEqual('Assert.AreNotEqual(2, FFake.Calls);', Equality('  Assert.IsTrue(not (FFake.Calls = 2));'));
end;

procedure TDUnitXAssertsTests.NilAndAssigned;
begin
  Assert.AreEqual('Assert.IsNull(FFake);', Equality('  Assert.IsTrue(FFake = nil);'));
  Assert.AreEqual('Assert.IsNotNull(FDing, ''da'');', Equality('  Assert.IsTrue(Assigned(FDing), ''da'');'));
  Assert.AreEqual('Assert.IsNull(FFake);', Equality('  Assert.IsFalse(Assigned(FFake));'));
  Assert.AreEqual('Assert.IsNotNull(FFake);', Equality('  Assert.IsFalse(nil = FFake);'));
  // Zwei Objekte: Identität.
  Assert.AreEqual('Assert.AreSame(FAnderer, FFake);', Equality('  Assert.IsTrue(FFake = FAnderer);'));
  Assert.AreEqual('Assert.AreNotSame(FAnderer, FFake);', Equality('  Assert.IsFalse(FFake = FAnderer);'));
end;

procedure TDUnitXAssertsTests.HintWithoutFix;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(TDUnitXIsTrueEqualityRule.Create, '  Assert.IsTrue(FFake.Wert = 1.5);');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('Assert.IsTrue nennt beim Fehlschlag die verglichenen Werte nicht: Assert.AreEqual zeigt ' +
    'erwartet und erhalten.', mFound[0].Message);
  // Aufzählung, NativeInt (Length eines dynamischen Arrays) und Methodenzeiger: keine sichere Überladung.
  Assert.AreEqual(1, Count(TDUnitXIsTrueEqualityRule.Create, '  Assert.IsTrue(FFarbe = Rot);'));
  Assert.AreEqual('', Equality('  Assert.IsTrue(FFarbe = Rot);'));
  Assert.AreEqual('', Equality('  Assert.IsTrue(Length(FListe) = 2);'));
  Assert.AreEqual('', Equality('  Assert.IsTrue(Assigned(FAktion));'));
end;

procedure TDUnitXAssertsTests.EqualitySilent;
var
  mSource: string;
begin
  Assert.AreEqual(0, Count(TDUnitXIsTrueEqualityRule.Create, '  Assert.IsTrue(FFake.Calls > 1);'#10 +
    '  Assert.IsTrue(FFake.Calls in [1, 2]);'#10'  Assert.IsTrue(Assigned(FFake) and (FFake.Calls = 1));'#10 +
    '  Assert.AreEqual(1, FFake.Calls);'#10'  IsTrue(FFake.Calls = 1);'));
  // Keine Testunit.
  mSource := StringReplace(TestUnit('  Assert.IsTrue(FFake.Calls = 1);'), 'DUnitX.TestFramework', 'System.Classes',
    []);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDUnitXIsTrueEqualityRule.Create, mSource, '',
    'Fall.Tests.pas'))));
end;

procedure TDUnitXAssertsTests.SilentWithoutFittingAssert;
begin
  // Record mit eigenem =: AreEqual<T> vergliche binär. Methodenzeiger und -referenzen: IsNull passt nicht.
  Assert.AreEqual(0, Count(TDUnitXIsTrueEqualityRule.Create, '  Assert.IsTrue(FPunkt = FAnders);'#10 +
    '  Assert.IsFalse(FPunkt <> FAnders);'#10'  Assert.IsTrue(Assigned(FAktion));'#10 +
    '  Assert.IsFalse(FFrage = nil);'#10'  Assert.IsTrue(not Assigned(FFrage));'));
  // Ein Objekt daneben meldet weiter.
  Assert.AreEqual(1, Count(TDUnitXIsTrueEqualityRule.Create, '  Assert.IsTrue(FPunkt = FAnders);'#10 +
    '  Assert.IsTrue(Assigned(FFake));'));
end;

procedure TDUnitXAssertsTests.SwappedArguments;
var
  mFound: TArray<TRuleFinding>;
begin
  Assert.AreEqual('Assert.AreEqual(4, FFake.Calls);', Swapped('  Assert.AreEqual(FFake.Calls, 4);'));
  mFound := Findings(TDUnitXSwappedExpectedRule.Create, '  Assert.AreEqual(FFake.Calls, 4);');
  Assert.AreEqual('Assert.AreEqual erwartet den erwarteten Wert zuerst: 4 ist eine Konstante, FFake.Calls nicht. ' +
    'Beim Fehlschlag vertauscht die Meldung erwartet und erhalten.', mFound[0].Message);
  Assert.AreEqual('Assert.AreEqual(cName, FFake.Name, ''Name'');',
    Swapped('  Assert.AreEqual(FFake.Name, cName, ''Name'');'));
  Assert.AreEqual('Assert.AreNotEqual(-cVier, FFake.Calls);', Swapped('  Assert.AreNotEqual(FFake.Calls, -cVier);'));
  Assert.AreEqual('Assert.AreEqual(Rot, FFarbe);', Swapped('  Assert.AreEqual(FFarbe, Rot);'));
  Assert.AreEqual('Assert.AreSame(nil, FFake);', Swapped('  Assert.AreSame(FFake, nil);'));
end;

procedure TDUnitXAssertsTests.SwappedSilent;
var
  mSource: string;
begin
  Assert.AreEqual(0, Count(TDUnitXSwappedExpectedRule.Create, '  Assert.AreEqual(4, FFake.Calls);'#10 +
    '  Assert.AreEqual(FFake.Calls, FFake.Calls);'#10'  Assert.AreEqual(1, 2);'#10 +
    '  Assert.IsTrue(FFake.Calls = 1);'#10'  Assert.Contains(FFake.Name, ''x'');'));
  mSource := StringReplace(TestUnit('  Assert.AreEqual(FFake.Calls, 4);'), 'DUnitX.TestFramework', 'System.Classes',
    []);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDUnitXSwappedExpectedRule.Create, mSource, '',
    'Fall.Tests.pas'))));
end;

procedure TDUnitXAssertsTests.RulesAreRegistered;
var
  mRule: IRule;
  mFound: Integer;
begin
  mFound := 0;
  for mRule in BuiltinRules do
  begin
    if MatchText(mRule.Descriptor.Id, [cDUnitXIsTrueEqualityRuleId, cDUnitXSwappedExpectedRuleId]) then
    begin
      Inc(mFound);
    end;
  end;
  Assert.AreEqual(2, mFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TDUnitXAssertsTests);

end.
