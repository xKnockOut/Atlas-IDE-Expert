unit Atlas.Common.Rules.Builtin.Testing.AreEqual.Tests;

// Tests der Regel dunitx-areequal-length (#1937): die Fälle aus dem Issue (Length eines dynamischen Arrays,
// mit Meldungstext und verschachtelten Klammern), High und AreNotEqual, NativeInt-Variable, Korrektur
// Integer(...), stille Fälle (Integer(...) schon da, String, statisches Array, beide NativeInt, Typargument,
// Delphi vor 12) und die Anmeldung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDUnitXAreEqualLengthTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure HighNativeIntAndMessageArgument;
    [Test]
    procedure SilentCases;
    [Test]
    procedure DelphiBefore12IsSilent;
    [Test]
    procedure RuleIsRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Testing.AreEqual,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

/// <summary>Testunit mit den Variablen AVars und den Anweisungen AStatements in einer Testmethode.</summary>
function TestUnit(const AVars, AStatements: string): string;
begin
  Result := 'unit Fall.Tests;'#10'interface'#10'implementation'#10'uses'#10'  DUnitX.TestFramework;'#10 +
    'function Namen: TArray<string>;'#10'begin'#10'  Result := nil;'#10'end;'#10 +
    'procedure Pruefe;'#10'var'#10 + AVars + 'begin'#10 + AStatements + 'end;'#10'end.';
end;

function Findings(const ASource: string; const AConfig: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TDUnitXAreEqualLengthRule.Create, ASource, AConfig, 'Fall.Tests.pas');
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := Findings(ASource, '');
end;

function Messages(const AFound: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFound do
  begin
    if Result <> '' then
    begin
      Result := Result + ' | ';
    end;
    Result := Result + IntToStr(mFinding.Range.StartPos.Line) + ': ' + mFinding.Message;
  end;
end;

{ TDUnitXAreEqualLengthTests }

procedure TDUnitXAreEqualLengthTests.IssueExampleWithFix;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := TestUnit('  mObjects: TArray<TObject>;'#10, '  Assert.AreEqual(5, Length(mObjects));'#10);
  mFound := Findings(mSource);
  Assert.AreEqual('13: Assert.AreEqual vergleicht eine Ganzzahl mit Length(mObjects) (NativeInt): Keine Überladung ' +
    'passt eindeutig, AreEqual<T> kann T nicht ableiten (wie E2532 unter Delphi). Integer(...) darum setzen.',
    Messages(mFound));
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.IsTrue(mFound[0].Fixes[0].Safe);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFound[0].Fixes[0].Edits);
  Assert.AreEqual(StringReplace(mSource, 'Length(mObjects)', 'Integer(Length(mObjects))', []), mFixed);
  Assert.AreEqual('', Messages(Findings(mFixed)));
end;

procedure TDUnitXAreEqualLengthTests.HighNativeIntAndMessageArgument;
begin
  // Meldungstext als drittes Argument, Funktionsergebnis mit Klammern.
  Assert.AreEqual(1, Integer(Length(Findings(TestUnit('', '  Assert.AreEqual(1, Length(Namen()), ''Knöpfe ' +
    'unverändert'');'#10)))));
  // High, AreNotEqual, NativeInt auf der linken Seite.
  Assert.AreEqual(2, Integer(Length(Findings(TestUnit('  mWerte: TArray<Integer>;'#10'  mAnzahl: NativeInt;'#10,
    '  Assert.AreNotEqual(High(mWerte), 3);'#10'  Assert.AreEqual(mAnzahl, 2);'#10)))));
end;

procedure TDUnitXAreEqualLengthTests.SilentCases;
begin
  Assert.AreEqual('', Messages(Findings(TestUnit('  mObjects: TArray<TObject>;'#10'  mText: string;'#10 +
    '  mFest: array[0..4] of Integer;'#10'  mAnzahl: NativeInt;'#10'  mUnbekannt: TFremd;'#10,
    // Schon umgewandelt, String, statisches Array, beide NativeInt, Typargument, unbekannter Typ.
    '  Assert.AreEqual(5, Integer(Length(mObjects)));'#10'  Assert.AreEqual(5, Length(mText));'#10 +
    '  Assert.AreEqual(4, High(mFest));'#10'  Assert.AreEqual(mAnzahl, Length(mObjects));'#10 +
    '  Assert.AreEqual<NativeInt>(5, Length(mObjects));'#10'  Assert.AreEqual(5, Length(mUnbekannt));'#10 +
    '  Assert.IsTrue(5 = Length(mObjects));'#10))));
end;

procedure TDUnitXAreEqualLengthTests.DelphiBefore12IsSilent;
var
  mSource: string;
begin
  mSource := TestUnit('  mObjects: TArray<TObject>;'#10, '  Assert.AreEqual(5, Length(mObjects));'#10);
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"delphiVersion": "22.0"}'))));
  Assert.AreEqual(1, Integer(Length(Findings(mSource, '{"delphiVersion": "37.0"}'))));
end;

procedure TDUnitXAreEqualLengthTests.RuleIsRegistered;
var
  mRule: IRule;
  mFound: Boolean;
begin
  mFound := False;
  for mRule in BuiltinRules do
  begin
    mFound := mFound or (mRule.Descriptor.Id = cDUnitXAreEqualLengthRuleId);
  end;
  Assert.IsTrue(mFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TDUnitXAreEqualLengthTests);

end.
