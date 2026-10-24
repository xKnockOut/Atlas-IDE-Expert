unit Atlas.Common.Rules.Builtin.DebugDisplay.Tests;

// Tests der Regel debug-display-placeholder (#854): unbekannte Platzhalter und
// Unterelemente, ungültige Vorlage, geerbte Mitglieder über Unit und Index,
// unbekannter Vorfahr still.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDebugDisplayRuleTests = class
  public
    [Test]
    procedure KnownMembersSilent;
    [Test]
    procedure UnknownPlaceholderReported;
    [Test]
    procedure UnknownChildReported;
    [Test]
    procedure InvalidTemplateReported;
    [Test]
    procedure InheritedMembersFromIndex;
    [Test]
    procedure UnknownAncestorSilent;
    [Test]
    procedure AttributeRuleChecked;
    [Test]
    procedure RuleIsRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.DebugDisplay,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Tests.RuleAssert;

const
  Kunden =
    'unit Kunden;'#10 +
    'interface'#10 +
    'type'#10 +
    '  // atlas-debug: ''{Name}, {Ort} ({ClassName})'''#10 +
    '  // atlas-debug-children: Name, Nr'#10 +
    '  TKunde = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '  public'#10 +
    '    Ort: string;'#10 +
    '    function Nr: Integer;'#10 +
    '    property Name: string read FName;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TKunde.Nr: Integer;'#10 +
    'begin'#10 +
    '  Result := 1;'#10 +
    'end;'#10 +
    'end.';

function Findings(const ASource: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TDebugDisplayPlaceholderRule.Create, ASource);
end;

function BasisIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText('unit Basis;'#10'interface'#10'type'#10'  TPerson = class'#10 +
    '    Name: string;'#10'  end;'#10'implementation'#10'end.', 'Basis.pas', nil));
end;

procedure TDebugDisplayRuleTests.KnownMembersSilent;
begin
  Assert.AreEqual(0, Integer(Length(Findings(Kunden))));
end;

procedure TDebugDisplayRuleTests.UnknownPlaceholderReported;
var
  Found: TArray<TRuleFinding>;
  Source: string;
begin
  Source := StringReplace(Kunden, '{Ort}', '{Stadt.Name}', []);
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(DebugDisplayPlaceholderRuleId, Found[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Found[0].Severity));
  Assert.AreEqual(3, Found[0].Range.StartPos.Line);
  Assert.AreEqual(Pos('Stadt', '  // atlas-debug: ''{Name}, {Stadt.Name}') - 1, Found[0].Range.StartPos.Character);
  Assert.AreEqual(Found[0].Range.StartPos.Character + 5, Found[0].Range.EndPos.Character);
  Assert.AreEqual('TKunde hat kein Mitglied „Stadt“; der Platzhalter {Stadt.Name} bleibt beim Debuggen leer.',
    Found[0].Message);
end;

procedure TDebugDisplayRuleTests.UnknownChildReported;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(StringReplace(Kunden, 'children: Name, Nr', 'children: Name, Saldo', []));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(4, Found[0].Range.StartPos.Line);
  Assert.AreEqual(Pos('Saldo', '  // atlas-debug-children: Name, Saldo') - 1, Found[0].Range.StartPos.Character);
  Assert.AreEqual('TKunde hat kein Mitglied „Saldo“ für die Unterelemente.', Found[0].Message);
end;

procedure TDebugDisplayRuleTests.InvalidTemplateReported;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(StringReplace(Kunden, '{Ort}', '{}', []));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(3, Found[0].Range.StartPos.Line);
  Assert.IsTrue(Found[0].Message.StartsWith('Ungültige Wertdarstellung: '), Found[0].Message);
end;

procedure TDebugDisplayRuleTests.InheritedMembersFromIndex;
const
  Source =
    'unit Kunden;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  // atlas-debug: {Name} {Nr} {Fehlt}'#10 +
    '  TKunde = class(TPerson)'#10 +
    '    Nr: Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';
var
  Found: TArray<TRuleFinding>;
begin
  Found := TRuleAssert.IndexFindings(TDebugDisplayPlaceholderRule.Create, Source, BasisIndex, '', 'Kunden.pas');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.Contains(Found[0].Message, '„Fehlt“');
end;

procedure TDebugDisplayRuleTests.UnknownAncestorSilent;
const
  Source =
    'unit Kunden;'#10 +
    'interface'#10 +
    'type'#10 +
    '  // atlas-debug: {Name} {Fehlt}'#10 +
    '  TKunde = class(TUnbekannt)'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';
begin
  Assert.AreEqual(0, Integer(Length(Findings(Source))));
  // Eine ungültige Vorlage meldet die Regel trotzdem.
  Assert.AreEqual(1, Integer(Length(Findings(StringReplace(Source, '{Fehlt}', '{Fehlt', [])))));
end;

procedure TDebugDisplayRuleTests.AttributeRuleChecked;
const
  Source =
    'unit Punkte;'#10 +
    'interface'#10 +
    'type'#10 +
    '  [AtlasDebugDisplay(''({X}, {Z})'')]'#10 +
    '  [AtlasDebugChildren(''X, Y, W'')]'#10 +
    '  TPunkt = record'#10 +
    '    X, Y: Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Source);
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual(3, Found[0].Range.StartPos.Line);
  Assert.AreEqual(Pos('Z}', '  [AtlasDebugDisplay(''({X}, {Z})'')]') - 1, Found[0].Range.StartPos.Character);
  Assert.AreEqual(4, Found[1].Range.StartPos.Line);
  Assert.AreEqual(Pos('W''', '  [AtlasDebugChildren(''X, Y, W'')]') - 1, Found[1].Range.StartPos.Character);
end;

procedure TDebugDisplayRuleTests.RuleIsRegistered;
var
  Rule: IRule;
  Found: Boolean;
begin
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = DebugDisplayPlaceholderRuleId then
      Found := True;
  Assert.IsTrue(Found);
end;

initialization
  TDUnitX.RegisterTestFixture(TDebugDisplayRuleTests);

end.
