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
  cKunden =
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
  Assert.AreEqual(0, Integer(Length(Findings(cKunden))));
end;

procedure TDebugDisplayRuleTests.UnknownPlaceholderReported;
var
  mFound: TArray<TRuleFinding>;
  mSource: string;
begin
  mSource := StringReplace(cKunden, '{Ort}', '{Stadt.Name}', []);
  mFound := Findings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(cDebugDisplayPlaceholderRuleId, mFound[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFound[0].Severity));
  Assert.AreEqual(3, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(Pos('Stadt', '  // atlas-debug: ''{Name}, {Stadt.Name}') - 1, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(mFound[0].Range.StartPos.Character + 5, mFound[0].Range.EndPos.Character);
  Assert.AreEqual('TKunde hat kein Mitglied „Stadt“; der Platzhalter {Stadt.Name} bleibt beim Debuggen leer.',
    mFound[0].Message);
end;

procedure TDebugDisplayRuleTests.UnknownChildReported;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(StringReplace(cKunden, 'children: Name, Nr', 'children: Name, Saldo', []));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(4, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(Pos('Saldo', '  // atlas-debug-children: Name, Saldo') - 1, mFound[0].Range.StartPos.Character);
  Assert.AreEqual('TKunde hat kein Mitglied „Saldo“ für die Unterelemente.', mFound[0].Message);
end;

procedure TDebugDisplayRuleTests.InvalidTemplateReported;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(StringReplace(cKunden, '{Ort}', '{}', []));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(3, mFound[0].Range.StartPos.Line);
  Assert.IsTrue(mFound[0].Message.StartsWith('Ungültige Wertdarstellung: '), mFound[0].Message);
end;

procedure TDebugDisplayRuleTests.InheritedMembersFromIndex;
const
  cSource =
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
  mFound: TArray<TRuleFinding>;
begin
  mFound := TRuleAssert.IndexFindings(TDebugDisplayPlaceholderRule.Create, cSource, BasisIndex, '', 'Kunden.pas');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.Contains(mFound[0].Message, '„Fehlt“');
end;

procedure TDebugDisplayRuleTests.UnknownAncestorSilent;
const
  cSource =
    'unit Kunden;'#10 +
    'interface'#10 +
    'type'#10 +
    '  // atlas-debug: {Name} {Fehlt}'#10 +
    '  TKunde = class(TUnbekannt)'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';
begin
  Assert.AreEqual(0, Integer(Length(Findings(cSource))));
  // Eine ungültige Vorlage meldet die Regel trotzdem.
  Assert.AreEqual(1, Integer(Length(Findings(StringReplace(cSource, '{Fehlt}', '{Fehlt', [])))));
end;

procedure TDebugDisplayRuleTests.AttributeRuleChecked;
const
  cSource =
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
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(cSource);
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual(3, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(Pos('Z}', '  [AtlasDebugDisplay(''({X}, {Z})'')]') - 1, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(4, mFound[1].Range.StartPos.Line);
  Assert.AreEqual(Pos('W''', '  [AtlasDebugChildren(''X, Y, W'')]') - 1, mFound[1].Range.StartPos.Character);
end;

procedure TDebugDisplayRuleTests.RuleIsRegistered;
var
  mRule: IRule;
  mFound: Boolean;
begin
  mFound := False;
  for mRule in BuiltinRules do
  begin
    if mRule.Descriptor.Id = cDebugDisplayPlaceholderRuleId then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TDebugDisplayRuleTests);

end.
