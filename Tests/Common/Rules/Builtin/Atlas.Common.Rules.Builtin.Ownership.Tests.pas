unit Atlas.Common.Rules.Builtin.Ownership.Tests;

// Tests der Regel owned-item-freed (#947): Freigabe von Elementen besitzender Listen
// und Dictionarys, Besitz aus Erzeugung und OwnsObjects, Elementvariablen, Korrekturen, Optionen.
// Tests der Regel create-without-assignment (#948): erzeugte und sofort verlorene Objekte,
// Owner, Threads, selfRegistering, Korrektur mit try/finally.
// Tests der Regel self-as-interface-in-constructor (#950): eigene Referenzzählung im Konstruktor,
// TInterfacedObject nach inherited AfterConstruction, Formen der Weitergabe, Korrektur.
// Tests der Regel raw-memory-leak (#1047): Beispiel mit Korrektur, Belegungen und Freigaben,
// Weitergabe, stille Fälle, Abschalten.
// Tests der Regel stringlist-objects-leak (#1048): Beispiel mit Korrektur, lokale Variable, Steuerelemente,
// besitzende Listen, Freigabe und Weitergabe, Abschalten.
// Tests der Regel component-interface-dangling (#1090): Komponenten als Interface gespeichert und freigegeben,
// Formen der Speicherung, Abmeldungen, Korrektur, TInterfacedObject mit Free, Option componentClasses.

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
    [Test]
    procedure CreateIssueExampleReported;
    [Test]
    procedure CreateFixAssignsWithTryFinally;
    [Test]
    procedure CreateOwnersAndThreadsAreSilent;
    [Test]
    procedure CreateSelfRegisteringOption;
    [Test]
    procedure CreateOffAndExclude;
    [Test]
    procedure CreateNames;
    [Test]
    procedure SelfAsInterfaceOwnCounting;
    [Test]
    procedure SelfAsInterfaceOwnCountingSilentCases;
    [Test]
    procedure SelfAsInterfaceAfterConstruction;
    [Test]
    procedure SelfAsInterfaceOffAndExclude;
    [Test]
    procedure DanglingIssueExample;
    [Test]
    procedure DanglingVariants;
    [Test]
    procedure DanglingSilentCases;
    [Test]
    procedure DanglingOptions;
  end;

  [TestFixture]
  TRawMemoryLeakTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure AllocatorsAndReleases;
    [Test]
    procedure EscapesAreSilent;
    [Test]
    procedure OffAndExclude;
  end;

  [TestFixture]
  TStringListObjectsLeakTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure OtherConstructorsAndLocals;
    [Test]
    procedure ControlItems;
    [Test]
    procedure OwningOrReleasedIsSilent;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.Ownership,
  Atlas.Common.Editing.ChangeSignature,
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

function Import(const ABody: string): string;
begin
  Result :=
    'unit Import;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TImportProtokoll = class'#10 +
    '  end;'#10 +
    '  TImport = class'#10 +
    '    procedure Starten;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TImport.Starten;'#10 +
    'begin'#10 +
    ABody +
    'end;'#10 +
    'end.';
end;

procedure TOwnershipRulesTests.CreateIssueExampleReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TCreateWithoutAssignmentRule.Create,
    Import('  TImportProtokoll.Create;'#10'  Laden;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('create-without-assignment', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Das erzeugte TImportProtokoll wird nirgends gespeichert und nie freigegeben (Speicherleck).',
    Findings[0].Message);
  Assert.AreEqual(11, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(25, Findings[0].Range.EndPos.Character);
  // Gespeichert, weitergegeben oder sofort benutzt: still.
  TRuleAssert.Silent(TCreateWithoutAssignmentRule.Create, Import('  FProtokoll := TImportProtokoll.Create;'#10));
  TRuleAssert.Silent(TCreateWithoutAssignmentRule.Create, Import('  FListe.Add(TImportProtokoll.Create);'#10));
  TRuleAssert.Silent(TCreateWithoutAssignmentRule.Create, Import('  TImportProtokoll.Create.Free;'#10));
  TRuleAssert.Silent(TCreateWithoutAssignmentRule.Create, Import('  inherited Create;'#10));
  TRuleAssert.Silent(TCreateWithoutAssignmentRule.Create, Import('  FFabrik.Create;'#10));
  // Records belegen keinen Heap.
  TRuleAssert.Silent(TCreateWithoutAssignmentRule.Create, StringReplace(Import('  TImportProtokoll.Create(1);'#10),
    '  TImportProtokoll = class', '  TImportProtokoll = record', []));
  // Unbekannte Klasse ohne Argumente: gemeldet, mit Unit-Präfix und generisch ebenso.
  TRuleAssert.Reports(TCreateWithoutAssignmentRule.Create, Import('  System.Classes.TStringList.Create;'#10));
  Findings := TRuleAssert.Findings(TCreateWithoutAssignmentRule.Create, Import('  TList<Integer>.Create();'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Das erzeugte TList<Integer> wird nirgends gespeichert und nie freigegeben (Speicherleck).',
    Findings[0].Message);
end;

procedure TOwnershipRulesTests.CreateFixAssignsWithTryFinally;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Import('  TImportProtokoll.Create;'#10'  Laden;'#10'  Melden;'#10);
  Findings := TRuleAssert.Findings(TCreateWithoutAssignmentRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('An ImportProtokoll zuweisen und in try/finally freigeben', Findings[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(StringReplace(Import('  ImportProtokoll := TImportProtokoll.Create;'#10'  try'#10 +
    '    Laden;'#10'    Melden;'#10'  finally'#10'    ImportProtokoll.Free;'#10'  end;'#10),
    'procedure TImport.Starten;'#10'begin', 'procedure TImport.Starten;'#10'var'#10 +
    '  ImportProtokoll: TImportProtokoll;'#10'begin', []), Fixed);
  AssertParses(Fixed);
  TRuleAssert.Silent(TCreateWithoutAssignmentRule.Create, Fixed);
  // Letzte Anweisung: leerer try-Block; vergebener Name bekommt eine Nummer.
  Source := Import('  ImportProtokoll := 1;'#10'  TImportProtokoll.Create;'#10);
  Findings := TRuleAssert.Findings(TCreateWithoutAssignmentRule.Create, Source);
  Assert.AreEqual('An ImportProtokoll2 zuweisen und in try/finally freigeben', Findings[0].Fixes[0].Title);
  AssertParses(ApplyFix(Source, Findings[0].Fixes[0]));
  // In einer Zeile mit anderer Anweisung keine Korrektur.
  Findings := TRuleAssert.Findings(TCreateWithoutAssignmentRule.Create,
    Import('  if X then TImportProtokoll.Create;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TOwnershipRulesTests.CreateOwnersAndThreadsAreSilent;
const
  Source =
    'unit Formular;'#10 +
    'interface'#10 +
    'uses Vcl.StdCtrls, System.Classes;'#10 +
    'type'#10 +
    '  TKnopf = class(TButton)'#10 +
    '  end;'#10 +
    '  TArbeiter = class(TThread)'#10 +
    '  end;'#10 +
    '  TMerker = class'#10 +
    '    constructor Create(A: Integer);'#10 +
    '  end;'#10 +
    '  TFormular = class(TForm)'#10 +
    '    procedure Anlegen;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TMerker.Create(A: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TFormular.Anlegen;'#10 +
    'begin'#10 +
    '  TButton.Create(Self);'#10 +
    '  TKnopf.Create(Panel1);'#10 +
    '  TArbeiter.Create(False);'#10 +
    '  TRegistrierung.Create(Menue);'#10 +
    '  TMerker.Create(1);'#10 +
    '  TKnopf.Create(nil);'#10 +
    'end;'#10 +
    'end.';
var
  Findings: TArray<TRuleFinding>;
begin
  // Gemeldet: TMerker (bekannte Klasse ohne Owner) und TKnopf.Create(nil).
  Findings := TRuleAssert.Findings(TCreateWithoutAssignmentRule.Create, Source);
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual(24, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(25, Findings[1].Range.StartPos.Line);
end;

procedure TOwnershipRulesTests.CreateSelfRegisteringOption;
var
  Source: string;
  Issues: TArray<TConfigurationIssue>;
begin
  Source := Import('  TImportProtokoll.Create;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCreateWithoutAssignmentRule.Create, Source,
    '{"rules": {"create-without-assignment": {"selfRegistering": ["TImport*"]}}}'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TCreateWithoutAssignmentRule.Create, Source,
    '{"rules": {"create-without-assignment": {"selfRegistering": ["TExpert"]}}}'))));
  TConfigurationParser.Parse('{"rules": {"create-without-assignment": {"selfRegistering": "TExpert"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;

procedure TOwnershipRulesTests.CreateOffAndExclude;
var
  Source: string;
begin
  Source := Import('  TImportProtokoll.Create;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCreateWithoutAssignmentRule.Create, Source,
    '{"rules": {"create-without-assignment": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCreateWithoutAssignmentRule.Create, Source,
    '{"rules": {"create-without-assignment": {"exclude": ["Source/*.pas"]}}}', 'Source/Import.pas'))));
end;

procedure TOwnershipRulesTests.CreateNames;
begin
  Assert.IsTrue(TCreateWithoutAssignmentRule.LooksLikeType('TStringList'));
  Assert.IsTrue(TCreateWithoutAssignmentRule.LooksLikeType('EImport'));
  Assert.IsFalse(TCreateWithoutAssignmentRule.LooksLikeType('FFabrik'));
  Assert.IsFalse(TCreateWithoutAssignmentRule.LooksLikeType('Termin'));
  Assert.AreEqual('StringList', TCreateWithoutAssignmentRule.VariableName('System.Classes.TStringList'));
  Assert.AreEqual('List', TCreateWithoutAssignmentRule.VariableName('TList<Integer>'));
  Assert.AreEqual('Termin', TCreateWithoutAssignmentRule.VariableName('Termin'));
end;

function Beobachter(const AAncestor, AMembers, AImplementation: string): string;
begin
  Result :=
    'unit Beobachtung;'#10 +
    'interface'#10 +
    'type'#10 +
    '  IBeobachter = interface'#10 +
    '  end;'#10 +
    '  IQuelle = interface'#10 +
    '    procedure Anmelden(const ABeobachter: IBeobachter);'#10 +
    '    procedure Merken(AObjekt: TObject);'#10 +
    '  end;'#10 +
    '  TBeobachter = class(' + AAncestor + ', IBeobachter)'#10 +
    '  private'#10 +
    '    FQuelle: IQuelle;'#10 +
    AMembers +
    '  public'#10 +
    '    constructor Create(const AQuelle: IQuelle);'#10 +
    '    procedure AfterConstruction; override;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    AImplementation +
    'end.';
end;

function Gezaehlt(const AConstructorBody: string): string;
begin
  Result := Beobachter('TObject',
    '    FZaehler: Integer;'#10 +
    '    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;'#10 +
    '    function _AddRef: Integer; stdcall;'#10 +
    '    function _Release: Integer; stdcall;'#10,
    'function TBeobachter._Release: Integer;'#10 +
    'begin'#10 +
    '  Dec(FZaehler);'#10 +
    '  Result := FZaehler;'#10 +
    '  if Result = 0 then'#10 +
    '    Destroy;'#10 +
    'end;'#10 +
    'constructor TBeobachter.Create(const AQuelle: IQuelle);'#10 +
    'begin'#10 +
    '  inherited Create;'#10 +
    '  FQuelle := AQuelle;'#10 +
    AConstructorBody +
    'end;'#10 +
    'procedure TBeobachter.AfterConstruction;'#10 +
    'begin'#10 +
    '  inherited;'#10 +
    'end;'#10);
end;

function NachInherited(const ABody: string): string;
begin
  Result := Beobachter('TInterfacedObject', '',
    'constructor TBeobachter.Create(const AQuelle: IQuelle);'#10 +
    'begin'#10 +
    '  inherited Create;'#10 +
    '  FQuelle := AQuelle;'#10 +
    '  FQuelle.Anmelden(Self);'#10 +
    'end;'#10 +
    'procedure TBeobachter.AfterConstruction;'#10 +
    'begin'#10 +
    ABody +
    'end;'#10);
end;

procedure TOwnershipRulesTests.SelfAsInterfaceOwnCounting;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TSelfAsInterfaceInConstructorRule.Create,
    Gezaehlt('  FQuelle.Anmelden(Self);'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('self-as-interface-in-constructor', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Self wird im Konstruktor als Interface übergeben; die eigene Referenzzählung von TBeobachter ' +
    'gibt das Objekt frei, sobald der Zähler danach auf 0 fällt.', Findings[0].Message);
  Assert.AreEqual(32, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(19, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Weitere Formen der Weitergabe.
  TRuleAssert.Reports(TSelfAsInterfaceInConstructorRule.Create, Gezaehlt('  (Self as IBeobachter)._AddRef;'#10));
  TRuleAssert.Reports(TSelfAsInterfaceInConstructorRule.Create,
    Gezaehlt('  FQuelle.Anmelden(IBeobachter(Self));'#10));
  TRuleAssert.Reports(TSelfAsInterfaceInConstructorRule.Create,
    StringReplace(Gezaehlt('  FSelbst := Self;'#10), '    FQuelle: IQuelle;'#10,
    '    FQuelle: IQuelle;'#10'    FSelbst: IBeobachter;'#10, []));
end;

procedure TOwnershipRulesTests.SelfAsInterfaceOwnCountingSilentCases;
begin
  // Als Objekt weitergegeben, Methode von Self, Feld von Self.
  TRuleAssert.Silent(TSelfAsInterfaceInConstructorRule.Create, Gezaehlt('  FQuelle.Merken(Self);'#10 +
    '  Self.Free;'#10'  FQuelle.Anmelden(nil);'#10));
  // Schutz in NewInstance.
  TRuleAssert.Silent(TSelfAsInterfaceInConstructorRule.Create, StringReplace(Gezaehlt('  FQuelle.Anmelden(Self);'#10),
    '    function _Release: Integer; stdcall;'#10, '    function _Release: Integer; stdcall;'#10 +
    '    class function NewInstance: TObject; override;'#10, []));
  // _Release ohne Freigabe (Singleton-Muster).
  TRuleAssert.Silent(TSelfAsInterfaceInConstructorRule.Create, StringReplace(Gezaehlt('  FQuelle.Anmelden(Self);'#10),
    '    Destroy;'#10, '    Result := -1;'#10, []));
  // Unbekannter Vorfahr: die Kette ist nicht zu prüfen.
  TRuleAssert.Silent(TSelfAsInterfaceInConstructorRule.Create, StringReplace(Gezaehlt('  FQuelle.Anmelden(Self);'#10),
    'class(TObject,', 'class(TUnbekannt,', []));
  // TInterfacedObject im Konstruktor: Self ist durch NewInstance geschützt.
  TRuleAssert.Silent(TSelfAsInterfaceInConstructorRule.Create, NachInherited('  inherited;'#10));
end;

procedure TOwnershipRulesTests.SelfAsInterfaceAfterConstruction;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := NachInherited('  inherited;'#10'  FQuelle.Anmelden(Self);'#10);
  Findings := TRuleAssert.Findings(TSelfAsInterfaceInConstructorRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Self wird nach inherited AfterConstruction als Interface übergeben; fällt der Zähler danach ' +
    'auf 0, ist das Objekt schon freigegeben.', Findings[0].Message);
  Assert.AreEqual(26, Findings[0].Range.StartPos.Line);
  Assert.AreEqual('Vor inherited verschieben', Findings[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(NachInherited('  FQuelle.Anmelden(Self);'#10'  inherited;'#10), Fixed);
  AssertParses(Fixed);
  TRuleAssert.Silent(TSelfAsInterfaceInConstructorRule.Create, Fixed);
  // Ohne eigene Zeile keine Korrektur.
  Findings := TRuleAssert.Findings(TSelfAsInterfaceInConstructorRule.Create,
    NachInherited('  inherited; FQuelle.Anmelden(Self);'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Eigene Referenzzählung: auch in AfterConstruction gemeldet.
  Findings := TRuleAssert.Findings(TSelfAsInterfaceInConstructorRule.Create,
    StringReplace(Gezaehlt(''), '  inherited;'#10'end;'#10'end.', '  FQuelle.Anmelden(Self);'#10'end;'#10'end.', []));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Self wird in AfterConstruction als Interface übergeben; die eigene Referenzzählung von ' +
    'TBeobachter gibt das Objekt frei, sobald der Zähler danach auf 0 fällt.', Findings[0].Message);
end;

procedure TOwnershipRulesTests.SelfAsInterfaceOffAndExclude;
var
  Source: string;
begin
  Source := Gezaehlt('  FQuelle.Anmelden(Self);'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSelfAsInterfaceInConstructorRule.Create, Source,
    '{"rules": {"self-as-interface-in-constructor": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSelfAsInterfaceInConstructorRule.Create, Source,
    '{"rules": {"self-as-interface-in-constructor": {"exclude": ["Source/*.pas"]}}}', 'Source/Beobachtung.pas'))));
  Assert.IsTrue(TSelfAsInterfaceInConstructorRule.IsInterfaceType('IBeobachter'));
  Assert.IsTrue(TSelfAsInterfaceInConstructorRule.IsInterfaceType('System.IInterface'));
  Assert.IsTrue(TSelfAsInterfaceInConstructorRule.IsInterfaceType('IList<Integer>'));
  Assert.IsFalse(TSelfAsInterfaceInConstructorRule.IsInterfaceType('TObject'));
  Assert.IsFalse(TSelfAsInterfaceInConstructorRule.IsInterfaceType('Integer'));
end;

{ TRawMemoryLeakTests }

function Puffer(const AVars, ABody: string): string;
begin
  Result :=
    'unit Pruefung;'#10 +
    'interface'#10 +
    'uses System.Classes;'#10 +
    'implementation'#10 +
    'function Pruefsumme(P: Pointer; N: Integer): Integer;'#10 +
    'begin'#10 +
    '  Result := N;'#10 +
    'end;'#10 +
    'function Lesen(Strom: TStream; Groesse: Integer): Integer;'#10 +
    'var'#10 +
    AVars +
    'begin'#10 +
    ABody +
    'end;'#10 +
    'end.';
end;

procedure TRawMemoryLeakTests.IssueExampleWithFix;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Puffer('  Puffer: PByte;'#10, '  GetMem(Puffer, Groesse);'#10'  Strom.ReadBuffer(Puffer^, Groesse);'#10 +
    '  Result := Pruefsumme(Puffer, Groesse);'#10);
  Findings := TRuleAssert.Findings(TRawMemoryLeakRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('raw-memory-leak', Findings[0].RuleId);
  Assert.AreEqual('Puffer wird mit GetMem angelegt, aber nie freigegeben.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual(12, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('try … finally FreeMem(Puffer) end einfügen', Findings[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(Puffer('  Puffer: PByte;'#10, '  GetMem(Puffer, Groesse);'#10'  try'#10 +
    '    Strom.ReadBuffer(Puffer^, Groesse);'#10'    Result := Pruefsumme(Puffer, Groesse);'#10'  finally'#10 +
    '    FreeMem(Puffer);'#10'  end;'#10), Fixed);
  AssertParses(Fixed);
  TRuleAssert.Silent(TRawMemoryLeakRule.Create, Fixed);
end;

procedure TRawMemoryLeakTests.AllocatorsAndReleases;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TRawMemoryLeakRule.Create, Puffer('  Satz: PSatz;'#10,
    '  New(Satz);'#10'  Satz^.Wert := 1;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Satz wird mit New angelegt, aber nie freigegeben.', Findings[0].Message);
  Assert.AreEqual('try … finally Dispose(Satz) end einfügen', Findings[0].Fixes[0].Title);
  Findings := TRuleAssert.Findings(TRawMemoryLeakRule.Create, Puffer('  Text: PChar;'#10,
    '  Text := StrAlloc(Groesse);'#10'  Result := Pruefsumme(PByte(Text) + 1, Groesse);'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Text wird mit StrAlloc angelegt, aber nie freigegeben.', Findings[0].Message);
  Assert.AreEqual('try … finally StrDispose(Text) end einfügen', Findings[0].Fixes[0].Title);
  Source := Puffer('  Text: PChar;'#10, '  Text := StrAlloc(Groesse);'#10);
  Findings := TRuleAssert.Findings(TRawMemoryLeakRule.Create, Source);
  // Letzte Anweisung: leerer try-Block.
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.IsTrue(Pos('  try'#10'  finally'#10'    StrDispose(Text);'#10, Fixed) > 0, Fixed);
  AssertParses(Fixed);
  TRuleAssert.Reports(TRawMemoryLeakRule.Create, Puffer('  P: Pointer;'#10, '  P := AllocMem(Groesse);'#10));
  // Freigegeben, auch ohne try/finally (das meldet pair-without-finally) oder über ReallocMem(P, 0).
  TRuleAssert.Silent(TRawMemoryLeakRule.Create, Puffer('  P: Pointer;'#10,
    '  GetMem(P, Groesse);'#10'  Strom.ReadBuffer(P^, Groesse);'#10'  FreeMem(P);'#10));
  TRuleAssert.Silent(TRawMemoryLeakRule.Create, Puffer('  P: Pointer;'#10,
    '  GetMem(P, Groesse);'#10'  if Groesse > 0 then'#10'    ReallocMem(P, 0);'#10));
  TRuleAssert.Silent(TRawMemoryLeakRule.Create, Puffer('  Satz: PSatz;'#10,
    '  New(Satz);'#10'  try'#10'  finally'#10'    Dispose(Satz);'#10'  end;'#10));
  // Eigene Freigaberoutine.
  TRuleAssert.Silent(TRawMemoryLeakRule.Create, Puffer('  P: Pointer;'#10,
    '  GetMem(P, Groesse);'#10'  PufferFreigeben(P);'#10));
end;

procedure TRawMemoryLeakTests.EscapesAreSilent;
begin
  // Zurückgegeben, in einem Feld oder einer Liste gespeichert, Adresse weitergegeben, eingefangen.
  TRuleAssert.Silent(TRawMemoryLeakRule.Create, Puffer('  P: Pointer;'#10,
    '  GetMem(P, Groesse);'#10'  Exit(Integer(P));'#10));
  TRuleAssert.Silent(TRawMemoryLeakRule.Create, Puffer('  P: Pointer;'#10,
    '  GetMem(P, Groesse);'#10'  FDaten := P;'#10));
  TRuleAssert.Silent(TRawMemoryLeakRule.Create, Puffer('  P: Pointer;'#10,
    '  GetMem(P, Groesse);'#10'  FListe.Add(P);'#10));
  TRuleAssert.Silent(TRawMemoryLeakRule.Create, Puffer('  P: Pointer;'#10,
    '  GetMem(P, Groesse);'#10'  Merken(@P);'#10));
  TRuleAssert.Silent(TRawMemoryLeakRule.Create, Puffer('  P: Pointer;'#10,
    '  GetMem(P, Groesse);'#10'  TThread.Queue(nil, procedure begin Pruefsumme(P, 1); end);'#10));
  // Neu zugewiesen, absolute oder in einer lokalen Routine benutzt.
  TRuleAssert.Silent(TRawMemoryLeakRule.Create, Puffer('  P, Q: Pointer;'#10,
    '  GetMem(P, Groesse);'#10'  Q := P;'#10));
  TRuleAssert.Silent(TRawMemoryLeakRule.Create, Puffer('  P: Pointer;'#10'  A: NativeInt absolute P;'#10,
    '  GetMem(P, Groesse);'#10));
  TRuleAssert.Silent(TRawMemoryLeakRule.Create, Puffer('  P: Pointer;'#10 +
    '  procedure Aufraeumen;'#10'  begin'#10'    FreeMem(P);'#10'  end;'#10,
    '  GetMem(P, Groesse);'#10'  Aufraeumen;'#10));
  // Felder und Parameter sind nicht Sache der Regel.
  TRuleAssert.Silent(TRawMemoryLeakRule.Create, Puffer('  I: Integer;'#10, '  GetMem(FPuffer, Groesse);'#10));
end;

procedure TRawMemoryLeakTests.OffAndExclude;
var
  Source: string;
begin
  Source := Puffer('  P: Pointer;'#10, '  GetMem(P, Groesse);'#10);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TRawMemoryLeakRule.Create, Source, '',
    'Source/Pruefung.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRawMemoryLeakRule.Create, Source,
    '{"rules": {"raw-memory-leak": "off"}}', 'Source/Pruefung.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRawMemoryLeakRule.Create, Source,
    '{"rules": {"raw-memory-leak": {"exclude": ["Source/*.pas"]}}}', 'Source/Pruefung.pas'))));
  Assert.AreEqual('FreeMem', TRawMemoryLeakRule.ReleaseFor('AllocMem'));
  Assert.AreEqual('FreeMemory', TRawMemoryLeakRule.ReleaseFor('GetMemory'));
  Assert.AreEqual('', TRawMemoryLeakRule.ReleaseFor('Unbekannt'));
end;

{ TStringListObjectsLeakTests }

/// <summary>Klasse TKundenListe mit FKunden: TStringList; ACreate erzeugt die Liste, ABody füllt sie.</summary>
function Kundenliste(const ACreate, ABody, AExtra: string): string;
begin
  Result :=
    'unit Kundenliste;'#10 +
    'interface'#10 +
    'uses System.Classes, Vcl.StdCtrls;'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '    Name: string;'#10 +
    '    constructor Create(AQuelle: TKunde);'#10 +
    '  end;'#10 +
    '  TKundenListe = class'#10 +
    '    FKunden: TStringList;'#10 +
    '    LbKunden: TListBox;'#10 +
    '    constructor Create;'#10 +
    '    destructor Destroy; override;'#10 +
    '    procedure Laden(K: TKunde);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TKunde.Create(AQuelle: TKunde);'#10 +
    'begin'#10 +
    'end;'#10 +
    'constructor TKundenListe.Create;'#10 +
    'begin'#10 +
    '  ' + ACreate + #10 +
    'end;'#10 +
    'destructor TKundenListe.Destroy;'#10 +
    'begin'#10 +
    AExtra +
    '  FKunden.Free;'#10 +
    '  inherited;'#10 +
    'end;'#10 +
    'procedure TKundenListe.Laden(K: TKunde);'#10 +
    ABody +
    'end;'#10 +
    'end.';
end;

procedure TStringListObjectsLeakTests.IssueExampleWithFix;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Kundenliste('FKunden := TStringList.Create;', 'begin'#10'  FKunden.AddObject(K.Name, TKunde.Create(K));'#10,
    '');
  Findings := TRuleAssert.Findings(TStringListObjectsLeakRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('stringlist-objects-leak', Findings[0].RuleId);
  Assert.AreEqual('FKunden besitzt die Objekte nicht; die TKunde-Objekte werden nie freigegeben.',
    Findings[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual(30, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('TStringList.Create(True) setzen', Findings[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(Kundenliste('FKunden := TStringList.Create(True);',
    'begin'#10'  FKunden.AddObject(K.Name, TKunde.Create(K));'#10, ''), Fixed);
  AssertParses(Fixed);
  TRuleAssert.Silent(TStringListObjectsLeakRule.Create, Fixed);
  // Mit leeren Klammern und mit False ebenso.
  Findings := TRuleAssert.Findings(TStringListObjectsLeakRule.Create, Kundenliste('FKunden := TStringList.Create(False);',
    'begin'#10'  FKunden.InsertObject(0, K.Name, TKunde.Create(nil));'#10, ''));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Kundenliste('FKunden := TStringList.Create(True);',
    'begin'#10'  FKunden.InsertObject(0, K.Name, TKunde.Create(nil));'#10, ''),
    ApplyFix(Kundenliste('FKunden := TStringList.Create(False);',
    'begin'#10'  FKunden.InsertObject(0, K.Name, TKunde.Create(nil));'#10, ''), Findings[0].Fixes[0]));
end;

procedure TStringListObjectsLeakTests.OtherConstructorsAndLocals;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  // Konstruktor mit anderen Argumenten: OwnsObjects nach der Erzeugung.
  Source := Kundenliste('FKunden := TStringList.Create(dupIgnore, True, False);',
    'var'#10'  Neu: TKunde;'#10'begin'#10'  Neu := TKunde.Create(K);'#10'  FKunden.AddObject(Neu.Name, Neu);'#10, '');
  Findings := TRuleAssert.Findings(TStringListObjectsLeakRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('FKunden besitzt die Objekte nicht; die TKunde-Objekte werden nie freigegeben.',
    Findings[0].Message);
  Assert.AreEqual('OwnsObjects := True setzen', Findings[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.IsTrue(Pos('  FKunden := TStringList.Create(dupIgnore, True, False);'#10'  FKunden.OwnsObjects := True;'#10,
    Fixed) > 0, Fixed);
  AssertParses(Fixed);
  TRuleAssert.Silent(TStringListObjectsLeakRule.Create, Fixed);
  // Die lokale Variable wird anderswo gespeichert oder freigegeben: still.
  TRuleAssert.Silent(TStringListObjectsLeakRule.Create, Kundenliste('FKunden := TStringList.Create;',
    'var'#10'  Neu: TKunde;'#10'begin'#10'  Neu := TKunde.Create(K);'#10'  FKunden.AddObject(Neu.Name, Neu);'#10 +
    '  FAlle.Add(Neu);'#10, ''));
  // Vorhandene Objekte (Parameter) gehören jemand anderem.
  TRuleAssert.Silent(TStringListObjectsLeakRule.Create, Kundenliste('FKunden := TStringList.Create;',
    'begin'#10'  FKunden.AddObject(K.Name, K);'#10, ''));
end;

procedure TStringListObjectsLeakTests.ControlItems;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TStringListObjectsLeakRule.Create, Kundenliste('FKunden := nil;',
    'begin'#10'  LbKunden.Items.AddObject(K.Name, TKunde.Create(K));'#10, ''));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('LbKunden.Items besitzt die Objekte nicht; die TKunde-Objekte werden nie freigegeben.',
    Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Im Destruktor über Items.Objects freigegeben: still.
  TRuleAssert.Silent(TStringListObjectsLeakRule.Create, Kundenliste('FKunden := nil;',
    'begin'#10'  LbKunden.Items.AddObject(K.Name, TKunde.Create(K));'#10,
    '  for var I := 0 to LbKunden.Items.Count - 1 do'#10'    LbKunden.Items.Objects[I].Free;'#10));
end;

procedure TStringListObjectsLeakTests.OwningOrReleasedIsSilent;
const
  Add = 'begin'#10'  FKunden.AddObject(K.Name, TKunde.Create(K));'#10;
begin
  TRuleAssert.Silent(TStringListObjectsLeakRule.Create, Kundenliste('FKunden := TStringList.Create(True);', Add, ''));
  TRuleAssert.Silent(TStringListObjectsLeakRule.Create, Kundenliste('FKunden := TStringList.Create; ' +
    'FKunden.OwnsObjects := True;', Add, ''));
  TRuleAssert.Silent(TStringListObjectsLeakRule.Create, Kundenliste('FKunden := TStringList.Create;', Add,
    '  for var I := 0 to FKunden.Count - 1 do'#10'    TKunde(FKunden.Objects[I]).Free;'#10));
  // Eigene Freigaberoutine bzw. weitergegebene Liste.
  TRuleAssert.Silent(TStringListObjectsLeakRule.Create, Kundenliste('FKunden := TStringList.Create;', Add,
    '  ObjekteFreigeben(FKunden);'#10));
  // Komponenten mit Owner.
  TRuleAssert.Silent(TStringListObjectsLeakRule.Create, Kundenliste('FKunden := TStringList.Create;',
    'begin'#10'  FKunden.AddObject(K.Name, TButton.Create(Self));'#10, ''));
  // Unbekannte Liste (nicht in der Unit erzeugt).
  TRuleAssert.Silent(TStringListObjectsLeakRule.Create, Kundenliste('FKunden := Fabrik.Liste;', Add, ''));
end;

procedure TStringListObjectsLeakTests.OffAndExclude;
var
  Source: string;
begin
  Source := Kundenliste('FKunden := TStringList.Create;', 'begin'#10'  FKunden.AddObject(K.Name, TKunde.Create(K));'#10,
    '');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TStringListObjectsLeakRule.Create, Source,
    '{"rules": {"stringlist-objects-leak": "off"}}', 'Source/Kundenliste.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TStringListObjectsLeakRule.Create, Source,
    '{"rules": {"stringlist-objects-leak": {"exclude": ["Source/*.pas"]}}}', 'Source/Kundenliste.pas'))));
  Assert.AreEqual('fkunden.items', TStringListObjectsLeakRule.KeyOf('Self.FKunden. Items'));
end;

/// <summary>Formular, das ein zweites Formular als IBeobachter beim Bus anmeldet; AFelder ergänzt TfrmHaupt,
/// AOeffnen und ASchliessen stehen in den beiden Methoden, AKunden ist der Vorfahr von TfrmKunden.</summary>
function Haupt(const AKunden, AFelder, AOeffnen, ASchliessen: string): string;
begin
  Result := 'unit Haupt;'#10'interface'#10'uses'#10'  System.Classes, System.Generics.Collections, Vcl.Forms;'#10 +
    'type'#10'  IBeobachter = interface'#10'    procedure Melden;'#10'  end;'#10'  TBus = class'#10'  public'#10 +
    '    procedure Anmelden(const ABeobachter: IBeobachter);'#10 +
    '    procedure Abmelden(const ABeobachter: IBeobachter);'#10'  end;'#10 +
    '  TfrmKunden = class(' + AKunden + ', IBeobachter)'#10'    procedure Melden;'#10'  end;'#10 +
    '  TfrmHaupt = class(TForm)'#10'  private'#10'    FAnsicht: TfrmKunden;'#10 + AFelder +
    '    procedure AnsichtOeffnen;'#10'    procedure AnsichtSchliessen;'#10'  end;'#10'var'#10'  Bus: TBus;'#10 +
    'implementation'#10'procedure TBus.Anmelden(const ABeobachter: IBeobachter);'#10'begin'#10'end;'#10 +
    'procedure TBus.Abmelden(const ABeobachter: IBeobachter);'#10'begin'#10'end;'#10 +
    'procedure TfrmKunden.Melden;'#10'begin'#10'end;'#10'procedure TfrmHaupt.AnsichtOeffnen;'#10'begin'#10 +
    '  FAnsicht := TfrmKunden.Create(Self);'#10 + AOeffnen + 'end;'#10'procedure TfrmHaupt.AnsichtSchliessen;'#10 +
    'begin'#10 + ASchliessen + 'end;'#10'end.';
end;

procedure TOwnershipRulesTests.DanglingIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
  Tree: TSyntaxTree;
begin
  Source := Haupt('TForm', '', '  Bus.Anmelden(FAnsicht as IBeobachter);'#10, '  FAnsicht.Free;'#10);
  Findings := TRuleAssert.Findings(TComponentInterfaceDanglingRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('component-interface-dangling', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual('TfrmKunden ist ein TComponent ohne Referenzzählung; nach FAnsicht.Free hält Bus ein ungültiges ' +
    'IBeobachter.', Findings[0].Message);
  Assert.AreEqual(37, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Abmeldung vor der Freigabe einfügen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  Fixed := TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Haupt('TForm', '', '  Bus.Anmelden(FAnsicht as IBeobachter);'#10,
    '  Bus.Abmelden(FAnsicht as IBeobachter);'#10'  FAnsicht.Free;'#10), Fixed);
  Tree := TPascalParser.Parse(Fixed);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
  finally
    Tree.Free;
  end;
  TRuleAssert.Silent(TComponentInterfaceDanglingRule.Create, Fixed);
end;

procedure TOwnershipRulesTests.DanglingVariants;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  // Interface-Feld: Korrektur setzt es vor der Freigabe auf nil.
  Source := Haupt('TForm', '    FBeobachter: IBeobachter;'#10, '  FBeobachter := FAnsicht;'#10,
    '  FreeAndNil(FAnsicht);'#10);
  Findings := TRuleAssert.Findings(TComponentInterfaceDanglingRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TfrmKunden ist ein TComponent ohne Referenzzählung; nach FreeAndNil(FAnsicht) hält FBeobachter ' +
    'ein ungültiges IBeobachter.', Findings[0].Message);
  Assert.AreEqual(Haupt('TForm', '    FBeobachter: IBeobachter;'#10, '  FBeobachter := FAnsicht;'#10,
    '  FBeobachter := nil;'#10'  FreeAndNil(FAnsicht);'#10),
    TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits));
  // Liste von Interfaces ohne "as"; Release; Self.FAnsicht; Gegenstück am unbekannten TList: keine Korrektur.
  Findings := TRuleAssert.Findings(TComponentInterfaceDanglingRule.Create, Haupt('TForm',
    '    FListe: TList<IBeobachter>;'#10, '  FListe.Add(Self.FAnsicht);'#10, '  FAnsicht.Release;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TfrmKunden ist ein TComponent ohne Referenzzählung; nach FAnsicht.Release hält FListe ein ' +
    'ungültiges IBeobachter.', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Frame und Datenmodul; Anmeldung in Klammern.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TComponentInterfaceDanglingRule.Create, Haupt('TFrame', '',
    '  Bus.Anmelden((FAnsicht as IBeobachter));'#10, '  FAnsicht.Free;'#10)))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TComponentInterfaceDanglingRule.Create, Haupt('TDataModule',
    '', '  Bus.Anmelden(FAnsicht as IBeobachter);'#10, '  FAnsicht.Free;'#10)))));
  // Referenzgezählt und zusätzlich mit Free freigegeben: gemeldet, auch mit Abmeldung, ohne Korrektur.
  Findings := TRuleAssert.Findings(TComponentInterfaceDanglingRule.Create, Haupt('TInterfacedObject', '',
    '  Bus.Anmelden(FAnsicht as IBeobachter);'#10, '  Bus.Abmelden(FAnsicht as IBeobachter);'#10 +
    '  FAnsicht.Free;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TfrmKunden ist referenzgezählt (TInterfacedObject); FAnsicht.Free gibt es frei, obwohl Bus ' +
    'noch ein IBeobachter darauf hält.', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Abmelden', TComponentInterfaceDanglingRule.Counterpart('Anmelden'));
  Assert.AreEqual('Remove', TComponentInterfaceDanglingRule.Counterpart('add'));
  Assert.AreEqual('', TComponentInterfaceDanglingRule.Counterpart('Push'));
end;

procedure TOwnershipRulesTests.DanglingSilentCases;
begin
  // Abmeldung irgendwo in der Datei: Abmelden, FreeNotification, weitere Zuweisung, Clear.
  TRuleAssert.Silent(TComponentInterfaceDanglingRule.Create, Haupt('TForm', '',
    '  Bus.Anmelden(FAnsicht as IBeobachter);'#10'  FAnsicht.FreeNotification(Self);'#10, '  FAnsicht.Free;'#10));
  TRuleAssert.Silent(TComponentInterfaceDanglingRule.Create, Haupt('TForm', '    FBeobachter: IBeobachter;'#10,
    '  FBeobachter := FAnsicht as IBeobachter;'#10, '  FBeobachter := nil;'#10'  FAnsicht.Free;'#10));
  TRuleAssert.Silent(TComponentInterfaceDanglingRule.Create, Haupt('TForm', '    FListe: TList<IBeobachter>;'#10,
    '  FListe.Add(FAnsicht);'#10, '  FListe.Clear;'#10'  FAnsicht.Free;'#10));
  // Ohne Freigabe in der Datei (der Owner gibt frei), lokales Ziel, Self, lokale Liste.
  TRuleAssert.Silent(TComponentInterfaceDanglingRule.Create, Haupt('TForm', '',
    '  Bus.Anmelden(FAnsicht as IBeobachter);'#10, ''));
  TRuleAssert.Silent(TComponentInterfaceDanglingRule.Create, StringReplace(Haupt('TForm', '',
    '  B := FAnsicht as IBeobachter;'#10'  B.Melden;'#10, '  FAnsicht.Free;'#10),
    'procedure TfrmHaupt.AnsichtOeffnen;'#10, 'procedure TfrmHaupt.AnsichtOeffnen;'#10'var'#10'  B: IBeobachter;'#10,
    []));
  TRuleAssert.Silent(TComponentInterfaceDanglingRule.Create, Haupt('TForm', '',
    '  Bus.Anmelden(Self as IBeobachter);'#10, '  Free;'#10));
  // Eigenes _Release, unbekannter Vorfahr.
  TRuleAssert.Silent(TComponentInterfaceDanglingRule.Create, StringReplace(Haupt('TForm', '',
    '  Bus.Anmelden(FAnsicht as IBeobachter);'#10, '  FAnsicht.Free;'#10), '    procedure Melden;'#10'  end;'#10 +
    '  TfrmHaupt', '    procedure Melden;'#10'    function _Release: Integer; stdcall;'#10'  end;'#10'  TfrmHaupt', []));
  TRuleAssert.Silent(TComponentInterfaceDanglingRule.Create, Haupt('TFremdeBasis', '',
    '  Bus.Anmelden(FAnsicht as IBeobachter);'#10, '  FAnsicht.Free;'#10));
end;

procedure TOwnershipRulesTests.DanglingOptions;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
  Issues: TArray<TConfigurationIssue>;
begin
  Source := Haupt('TFremdeBasis', '', '  Bus.Anmelden(FAnsicht as IBeobachter);'#10, '  FAnsicht.Free;'#10);
  Findings := TRuleAssert.Findings(TComponentInterfaceDanglingRule.Create, Source,
    '{"rules": {"component-interface-dangling": {"componentClasses": ["TFremdeBasis"]}}}');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TfrmKunden ist ein TFremdeBasis ohne Referenzzählung; nach FAnsicht.Free hält Bus ein ' +
    'ungültiges IBeobachter.', Findings[0].Message);
  // Ohne TComponent in der Liste gelten die VCL-Klassen nicht mehr als Basis.
  Source := Haupt('TForm', '', '  Bus.Anmelden(FAnsicht as IBeobachter);'#10, '  FAnsicht.Free;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TComponentInterfaceDanglingRule.Create, Source,
    '{"rules": {"component-interface-dangling": {"componentClasses": ["TFremdeBasis"]}}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TComponentInterfaceDanglingRule.Create, Source,
    '{"rules": {"component-interface-dangling": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TComponentInterfaceDanglingRule.Create, Source,
    '{"rules": {"component-interface-dangling": {"exclude": ["Source/*.pas"]}}}', 'Source/Haupt.pas'))));
  TConfigurationParser.Parse('{"rules": {"component-interface-dangling": {"componentClasses": "TComponent"}}}',
    Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;

initialization
  TDUnitX.RegisterTestFixture(TOwnershipRulesTests);
  TDUnitX.RegisterTestFixture(TRawMemoryLeakTests);
  TDUnitX.RegisterTestFixture(TStringListObjectsLeakTests);

end.
