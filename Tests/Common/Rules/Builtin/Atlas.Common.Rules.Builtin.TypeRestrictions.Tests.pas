unit Atlas.Common.Rules.Builtin.TypeRestrictions.Tests;

// Tests der Sprachregeln für Typdeklarationen: operator-declaration-invalid
// (#1030) mit dem Beispiel samt Korrektur in Deklaration und Rumpf, allen
// Codes (E2393, E2517, E2518, E2519, E2520, E2521, E2522, E2464), stillen
// Fällen (richtige Operatoren, Aliase, unbekannte Typen) und Abschalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TOperatorDeclarationInvalidTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure UnknownOperatorName;
    [Test]
    procedure ParameterCount;
    [Test]
    procedure OwnTypeMissing;
    [Test]
    procedure IncResultAndAncestor;
    [Test]
    procedure AssignNeedsVar;
    [Test]
    procedure CorrectOperatorsAreSilent;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.TypeRestrictions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

function OperatorFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TOperatorDeclarationInvalidRule.Create, ASource);
end;

function OperatorFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TOperatorDeclarationInvalidRule.Create, ASource, AConfig, APath);
end;

/// <summary>Unit mit TGeld (Record), den Mitgliedern AMembers und den Rümpfen ABodies.</summary>
function Geld(const AMembers, ABodies: string): string; overload;
begin
  Result := 'unit Geld;'#10'interface'#10'type'#10'  TGeld = record'#10'    Betrag: Currency;'#10 + AMembers +
    '  end;'#10'implementation'#10 + ABodies + 'end.';
end;

/// <summary>Wie Geld(AMembers, ABodies) ohne Rümpfe.</summary>
function Geld(const AMembers: string): string; overload;
begin
  Result := Geld(AMembers, '');
end;

procedure TOperatorDeclarationInvalidTests.IssueExampleWithFix;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Geld('    class operator Equal(const A, B: TGeld): Integer;'#10,
    'class operator TGeld.Equal(const A, B: TGeld): Integer;'#10'begin'#10'  Result := 0;'#10'end;'#10);
  Found := OperatorFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Equal muss Boolean liefern (wie E2520).', Found[0].Message);
  Assert.AreEqual(5, Found[0].Range.StartPos.Line);
  Assert.AreEqual(19, Found[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Boolean als Ergebnis', Found[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  Assert.AreEqual(Geld('    class operator Equal(const A, B: TGeld): Boolean;'#10,
    'class operator TGeld.Equal(const A, B: TGeld): Boolean;'#10'begin'#10'  Result := 0;'#10'end;'#10), Fixed);
  Assert.AreEqual(0, Integer(Length(OperatorFindings(Fixed))), Fixed);
end;

procedure TOperatorDeclarationInvalidTests.UnknownOperatorName;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Geld('    class operator Addition(const A, B: TGeld): TGeld;'#10,
    'class operator TGeld.Addition(const A, B: TGeld): TGeld;'#10'begin'#10'end;'#10);
  Found := OperatorFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Unbekannter Operator Addition (wie E2393).', Found[0].Message);
  Source := Geld('    class operator Substract(const A, B: TGeld): TGeld;'#10,
    'class operator TGeld.Substract(const A, B: TGeld): TGeld;'#10'begin'#10'end;'#10);
  Found := OperatorFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Unbekannter Operator Substract; gemeint ist wohl Subtract (wie E2393).', Found[0].Message);
  Assert.AreEqual('In Subtract umbenennen', Found[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  Assert.AreEqual(Geld('    class operator Subtract(const A, B: TGeld): TGeld;'#10,
    'class operator TGeld.Subtract(const A, B: TGeld): TGeld;'#10'begin'#10'end;'#10), Fixed);
end;

procedure TOperatorDeclarationInvalidTests.ParameterCount;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Geld('    class operator Negative(const A, B: TGeld): TGeld;'#10);
  Found := OperatorFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Der Operator Negative muss 1 Parameter haben (wie E2517).', Found[0].Message);
  Assert.AreEqual('Parameter nach Vorlage: (const A: TGeld)', Found[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  Assert.AreEqual(Geld('    class operator Negative(const A: TGeld): TGeld;'#10), Fixed);
  Found := OperatorFindings(Geld('    class operator Add(const A: TGeld): TGeld;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Der Operator Add muss 2 Parameter haben (wie E2517).', Found[0].Message);
  // Umwandlungen ohne Vorlage.
  Found := OperatorFindings(Geld('    class operator Implicit(A: Integer; B: TGeld): TGeld;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
end;

procedure TOperatorDeclarationInvalidTests.OwnTypeMissing;
var
  Found: TArray<TRuleFinding>;
begin
  Found := OperatorFindings(Geld('    class operator Add(A, B: Integer): TGeld;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Der Operator Add muss TGeld in mindestens einem Parameter haben (wie E2518).', Found[0].Message);
  Found := OperatorFindings(Geld('    class operator Implicit(A: Integer): string;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Implicit muss TGeld als Parameter oder Ergebnis haben (wie E2521).', Found[0].Message);
  // Unbekannter Typ aus einer anderen Unit: keine Aussage.
  Assert.AreEqual(0, Integer(Length(OperatorFindings(Geld('    class operator Add(A, B: TFremd): TGeld;'#10)))));
  // Alias des eigenen Typs.
  Assert.AreEqual(0, Integer(Length(OperatorFindings(Geld('    class operator Add(A, B: TMoney): TGeld;'#10).Replace(
    'implementation', 'type'#10'  TMoney = TGeld;'#10'implementation')))));
end;

procedure TOperatorDeclarationInvalidTests.IncResultAndAncestor;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Geld('    class operator Inc(const A: TGeld): Integer;'#10);
  Found := OperatorFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Inc muss denselben Typ liefern wie den ersten Parameter, hier TGeld (wie E2519).',
    Found[0].Message);
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  Assert.AreEqual(Geld('    class operator Inc(const A: TGeld): TGeld;'#10), Fixed);
  // Klasse mit Umwandlung in den Vorfahren.
  Found := OperatorFindings('unit Tiere;'#10'interface'#10'type'#10'  TTier = class'#10'  end;'#10 +
    '  THund = class(TTier)'#10'    class operator Implicit(A: THund): TTier;'#10'  end;'#10'implementation'#10'end.');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Implicit darf nicht in den Vorfahren TTier oder aus ihm umwandeln (wie E2522).', Found[0].Message);
end;

procedure TOperatorDeclarationInvalidTests.AssignNeedsVar;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Geld('    class operator Assign(const Dest: TGeld; const [ref] Src: TGeld);'#10);
  Found := OperatorFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Der erste Parameter von Assign muss ein var-Parameter sein (wie E2464).', Found[0].Message);
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  Assert.AreEqual(Geld('    class operator Assign(var Dest: TGeld; const [ref] Src: TGeld);'#10), Fixed);
  Source := Geld('    class operator Assign(Dest: TGeld; const [ref] Src: TGeld);'#10);
  Fixed := TChangeSignature.ApplyEdits(Source, OperatorFindings(Source)[0].Fixes[0].Edits);
  Assert.AreEqual(Geld('    class operator Assign(var Dest: TGeld; const [ref] Src: TGeld);'#10), Fixed);
end;

procedure TOperatorDeclarationInvalidTests.CorrectOperatorsAreSilent;
begin
  Assert.AreEqual(0, Integer(Length(OperatorFindings(Geld(
    '    class operator Equal(const A, B: TGeld): Boolean;'#10 +
    '    class operator NotEqual(const A, B: TGeld): Boolean; inline;'#10 +
    '    class operator Add(const A: TGeld; B: Currency): TGeld;'#10 +
    '    class operator In(A: Integer; const B: TGeld): Boolean;'#10 +
    '    class operator Implicit(A: Currency): TGeld;'#10 +
    '    class operator Explicit(const A: TGeld): Currency;'#10 +
    '    class operator Negative(const A: TGeld): TGeld;'#10 +
    '    class operator Inc(const A: TGeld): TGeld;'#10 +
    '    class operator Initialize(out Dest: TGeld);'#10 +
    '    class operator Finalize(var Dest: TGeld);'#10 +
    '    class operator Assign(var Dest: TGeld; const [ref] Src: TGeld);'#10 +
    '    class operator True(const A: TGeld): Boolean;'#10 +
    '    class operator GreaterThan(const A, B: TGeld): TBoolAlias;'#10 +
    '    class function Add(A, B: Integer): Integer; static;'#10)))));
  // Generischer Record.
  Assert.AreEqual(0, Integer(Length(OperatorFindings('unit G;'#10'interface'#10'type'#10'  TBox<T> = record'#10 +
    '    class operator Implicit(const A: T): TBox<T>;'#10'    class operator Equal(const A, B: TBox<T>): Boolean;'#10 +
    '  end;'#10'implementation'#10'end.'))));
end;

procedure TOperatorDeclarationInvalidTests.OffAndExclude;
var
  Source: string;
begin
  Source := Geld('    class operator Equal(const A, B: TGeld): Integer;'#10);
  Assert.AreEqual(1, Integer(Length(OperatorFindings(Source, '', 'Source/Geld.pas'))));
  Assert.AreEqual(0, Integer(Length(OperatorFindings(Source, '{"rules": {"operator-declaration-invalid": "off"}}',
    'Source/Geld.pas'))));
  Assert.AreEqual(0, Integer(Length(OperatorFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Geld.pas'))));
  Assert.AreEqual(0, Integer(Length(OperatorFindings(Source,
    '{"rules": {"operator-declaration-invalid": {"exclude": ["Source/*.pas"]}}}', 'Source/Geld.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TOperatorDeclarationInvalidTests);

end.
