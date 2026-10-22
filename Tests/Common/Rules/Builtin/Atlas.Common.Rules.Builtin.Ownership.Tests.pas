unit Atlas.Common.Rules.Builtin.Ownership.Tests;

// Tests der Regel owned-item-freed (#947): Freigabe von Elementen besitzender Listen
// und Dictionarys, Besitz aus Erzeugung und OwnsObjects, Elementvariablen, Korrekturen, Optionen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TOwnershipRulesTests = class
  public
    [Test]
    procedure IssueExampleReported;
    [Test]
    procedure FixRemovesFree;
    [Test]
    procedure FreeWithoutRemovalSuggestsDelete;
    [Test]
    procedure NotOwningListsAreSilent;
    [Test]
    procedure ElementVariablesAndLoops;
    [Test]
    procedure RemoveSuggestsExtract;
    [Test]
    procedure Dictionaries;
    [Test]
    procedure OffAndExclude;
    [Test]
    procedure CreatesOwning;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.Ownership,
  Atlas.Tests.RuleAssert;

function Routine(const ACreate, ABody: string): string;
begin
  Result :=
    'unit Auftraege;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses System.Generics.Collections;'#10 +
    'procedure Bereinigen(I: Integer);'#10 +
    'var'#10 +
    '  Auftraege: TObjectList<TAuftrag>;'#10 +
    '  Auftrag: TAuftrag;'#10 +
    'begin'#10 +
    '  Auftraege := ' + ACreate + ';'#10 +
    ABody +
    'end;'#10 +
    'end.';
end;

function Body(const ABody: string): string;
begin
  Result := Routine('TObjectList<TAuftrag>.Create', ABody);
end;

/// <summary>Wendet alle Änderungen der Korrektur an, von hinten nach vorn (Zeilen mit #10).</summary>
function ApplyFix(const AText: string; const AFix: TRuleFix): string;
var
  Index: Integer;
  Edit: TRuleEdit;

  function OffsetOf(const APosition: TTextPosition): Integer;
  var
    Line, Position: Integer;
  begin
    Position := 0;
    for Line := 1 to APosition.Line do
      Position := Pos(#10, AText, Position + 1);
    Result := Position + APosition.Character;
  end;

begin
  Result := AText;
  for Index := High(AFix.Edits) downto 0 do
  begin
    Edit := AFix.Edits[Index];
    Result := Copy(Result, 1, OffsetOf(Edit.Range.StartPos)) + Edit.NewText +
      Copy(Result, OffsetOf(Edit.Range.EndPos) + 1, MaxInt);
  end;
end;

procedure AssertParses(const ASource: string);
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(ASource);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
  finally
    Tree.Free;
  end;
end;

{ TOwnershipRulesTests }

procedure TOwnershipRulesTests.IssueExampleReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TOwnedItemFreedRule.Create, Body('  Auftraege[I].Free;'#10 +
    '  Auftraege.Delete(I);'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('owned-item-freed', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Auftraege besitzt seine Elemente (OwnsObjects); Delete gibt das Element ein zweites Mal frei.',
    Findings[0].Message);
  Assert.AreEqual(10, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(19, Findings[0].Range.EndPos.Character);
  // Reihenfolge egal: Delete vor Free ebenso.
  TRuleAssert.Reports(TOwnedItemFreedRule.Create, Body('  Auftrag := Auftraege[I];'#10 +
    '  Auftraege.Delete(I);'#10'  Auftrag.Free;'#10));
  // Zuweisung an das Element gibt das alte frei.
  Findings := TRuleAssert.Findings(TOwnedItemFreedRule.Create, Body('  Auftraege[I].Free;'#10 +
    '  Auftraege[I] := nil;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Auftraege besitzt seine Elemente (OwnsObjects); die Zuweisung an Auftraege[…] gibt das ' +
    'Element ein zweites Mal frei.', Findings[0].Message);
end;

procedure TOwnershipRulesTests.FixRemovesFree;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Body('  Auftraege[I].Free;'#10'  Auftraege.Delete(I);'#10);
  Findings := TRuleAssert.Findings(TOwnedItemFreedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Free entfernen', Findings[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(Body('  Auftraege.Delete(I);'#10), Fixed);
  AssertParses(Fixed);
  TRuleAssert.Silent(TOwnedItemFreedRule.Create, Fixed);
  // FreeAndNil ebenso.
  Source := Body('  FreeAndNil(Auftraege[I]);'#10'  Auftraege.Delete(I);'#10);
  Findings := TRuleAssert.Findings(TOwnedItemFreedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Body('  Auftraege.Delete(I);'#10), ApplyFix(Source, Findings[0].Fixes[0]));
end;

procedure TOwnershipRulesTests.FreeWithoutRemovalSuggestsDelete;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Body('  Auftraege.Items[I].Free;'#10);
  Findings := TRuleAssert.Findings(TOwnedItemFreedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Auftraege besitzt seine Elemente (OwnsObjects); die Liste gibt das Element beim Freigeben ' +
    'ein zweites Mal frei.', Findings[0].Message);
  Assert.AreEqual('Delete statt Free', Findings[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(Body('  Auftraege.Delete(I);'#10), Fixed);
  AssertParses(Fixed);
end;

procedure TOwnershipRulesTests.NotOwningListsAreSilent;
begin
  TRuleAssert.Silent(TOwnedItemFreedRule.Create, Routine('TObjectList<TAuftrag>.Create(False)',
    '  Auftraege[I].Free;'#10'  Auftraege.Delete(I);'#10));
  TRuleAssert.Silent(TOwnedItemFreedRule.Create, Body('  Auftraege.OwnsObjects := False;'#10 +
    '  Auftraege[I].Free;'#10'  Auftraege.Delete(I);'#10));
  // Extract gibt nicht frei.
  TRuleAssert.Silent(TOwnedItemFreedRule.Create, Body('  Auftrag := Auftraege[I];'#10 +
    '  Auftraege.Extract(Auftrag);'#10'  Auftrag.Free;'#10));
  // Liste selbst freigeben und Delete allein sind richtig.
  TRuleAssert.Silent(TOwnedItemFreedRule.Create, Body('  Auftraege.Delete(I);'#10'  Auftraege.Free;'#10));
  // TList<T> besitzt nichts.
  TRuleAssert.Silent(TOwnedItemFreedRule.Create, StringReplace(Routine('TList<TAuftrag>.Create',
    '  Auftraege[I].Free;'#10'  Auftraege.Delete(I);'#10), 'TObjectList<TAuftrag>;', 'TList<TAuftrag>;', []));
  // Element eines anderen Objekts.
  TRuleAssert.Silent(TOwnedItemFreedRule.Create, Body('  Kunde.Auftraege[I].Free;'#10));
end;

procedure TOwnershipRulesTests.ElementVariablesAndLoops;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  TRuleAssert.Reports(TOwnedItemFreedRule.Create, Body('  Auftrag := Auftraege.Last;'#10'  Auftrag.Free;'#10));
  Source := Body('  for Auftrag in Auftraege do'#10'    Auftrag.Free;'#10'  Auftraege.Clear;'#10);
  Findings := TRuleAssert.Findings(TOwnedItemFreedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Auftraege besitzt seine Elemente (OwnsObjects); Clear gibt das Element ein zweites Mal frei.',
    Findings[0].Message);
  // Die Korrektur nimmt die ganze Schleife weg.
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(Body('  Auftraege.Clear;'#10), Fixed);
  AssertParses(Fixed);
  // Freigabe nach der Schleife betrifft das Element nicht mehr sicher; ein Feld der Schleife schon.
  TRuleAssert.Silent(TOwnedItemFreedRule.Create, Body('  for Auftrag in Auftraege do'#10'    Pruefen(Auftrag);'#10 +
    '  Auftrag := TAuftrag.Create;'#10'  Auftrag.Free;'#10));
  TRuleAssert.Silent(TOwnedItemFreedRule.Create, Body('  Auftrag := TAuftrag.Create;'#10'  Auftrag.Free;'#10));
  // V := Liste[I].Kunde ist kein Element.
  TRuleAssert.Silent(TOwnedItemFreedRule.Create, Body('  Auftrag := Auftraege[I].Vorgaenger;'#10'  Auftrag.Free;'#10));
end;

procedure TOwnershipRulesTests.RemoveSuggestsExtract;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Body('  Auftrag := Auftraege[I];'#10'  Auftraege.Remove(Auftrag);'#10'  Auftrag.Free;'#10);
  Findings := TRuleAssert.Findings(TOwnedItemFreedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(2, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Free entfernen', Findings[0].Fixes[0].Title);
  Assert.AreEqual('Extract statt Remove', Findings[0].Fixes[1].Title);
  Assert.IsTrue(Findings[0].Fixes[1].Alternative);
  Fixed := ApplyFix(Source, Findings[0].Fixes[1]);
  Assert.AreEqual(Body('  Auftrag := Auftraege[I];'#10'  Auftraege.Extract(Auftrag);'#10'  Auftrag.Free;'#10), Fixed);
  TRuleAssert.Silent(TOwnedItemFreedRule.Create, Fixed);
end;

procedure TOwnershipRulesTests.Dictionaries;
const
  Source =
    'unit Kunden;'#10 +
    'interface'#10 +
    'uses System.Generics.Collections;'#10 +
    'type'#10 +
    '  TKunden = class'#10 +
    '  private'#10 +
    '    FKunden: TObjectDictionary<string, TKunde>;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    procedure Entfernen(const AName: string);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TKunden.Create;'#10 +
    'begin'#10 +
    '  FKunden := TObjectDictionary<string, TKunde>.Create([doOwnsValues]);'#10 +
    'end;'#10 +
    'procedure TKunden.Entfernen(const AName: string);'#10 +
    'begin'#10 +
    '  Self.FKunden[AName].Free;'#10 +
    'end;'#10 +
    'end.';
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TOwnedItemFreedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('FKunden besitzt seine Werte (doOwnsValues); die Liste gibt das Element beim Freigeben ' +
    'ein zweites Mal frei.', Findings[0].Message);
  Assert.AreEqual('Remove statt Free', Findings[0].Fixes[0].Title);
  Assert.AreEqual(StringReplace(Source, 'Self.FKunden[AName].Free', 'Self.FKunden.Remove(AName)', []),
    ApplyFix(Source, Findings[0].Fixes[0]));
  // Ohne doOwnsValues besitzt das Dictionary nichts.
  TRuleAssert.Silent(TOwnedItemFreedRule.Create, StringReplace(Source, '[doOwnsValues]', '[]', []));
  // for in Values.
  TRuleAssert.Reports(TOwnedItemFreedRule.Create, StringReplace(Source, '  Self.FKunden[AName].Free;'#10,
    '  for var Kunde in FKunden.Values do'#10'    Kunde.Free;'#10, []));
end;

procedure TOwnershipRulesTests.OffAndExclude;
var
  Source: string;
begin
  Source := Body('  Auftraege[I].Free;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedItemFreedRule.Create, Source,
    '{"rules": {"owned-item-freed": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedItemFreedRule.Create, Source,
    '{"rules": {"owned-item-freed": {"exclude": ["Source/*.pas"]}}}', 'Source/Auftraege.pas'))));
end;

procedure TOwnershipRulesTests.CreatesOwning;
var
  IsDictionary: Boolean;
begin
  Assert.IsTrue(TOwnedItemFreedRule.CreatesOwning('TObjectList', '', IsDictionary));
  Assert.IsFalse(IsDictionary);
  Assert.IsTrue(TOwnedItemFreedRule.CreatesOwning('TObjectList', 'True', IsDictionary));
  Assert.IsFalse(TOwnedItemFreedRule.CreatesOwning('TObjectList', 'False', IsDictionary));
  Assert.IsFalse(TOwnedItemFreedRule.CreatesOwning('TObjectList', 'TComparer<T>.Default, False', IsDictionary));
  Assert.IsTrue(TOwnedItemFreedRule.CreatesOwning('TObjectDictionary', '[doOwnsKeys, doOwnsValues]', IsDictionary));
  Assert.IsTrue(IsDictionary);
  Assert.IsFalse(TOwnedItemFreedRule.CreatesOwning('TObjectDictionary', '[doOwnsKeys]', IsDictionary));
  Assert.IsFalse(TOwnedItemFreedRule.CreatesOwning('TObjectDictionary', '', IsDictionary));
end;

initialization
  TDUnitX.RegisterTestFixture(TOwnershipRulesTests);

end.
