unit Atlas.Common.Rules.Builtin.FreeFields.Tests;

// Tests für field-not-freed (bis #918 owned-field-not-freed) und
// owned-field-free-unclear (#666): Beispiel aus #918, Owner-Komponenten,
// Option ignoreTypes, frühere Kennung, Abschalten und Ausnahmen; dazu
// initialization-not-finalized (#971).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFreeFieldRulesTests = class
  public
    [Test]
    procedure NotFreedIsWarningWithFix;
    [Test]
    procedure FreeAndNilStyleInFix;
    [Test]
    procedure UnclearIsHintWithoutFix;
    [Test]
    procedure SwitchedOff;
    [Test]
    procedure IssueExampleReportsOnlyUnfreedField;
    [Test]
    procedure OwnedComponentAndFreedFieldSilent;
    [Test]
    procedure IgnoreTypesSilencesClass;
    [Test]
    procedure FormerIdStillApplies;
    [Test]
    procedure OffAndExcludeSilence;
    [Test]
    procedure InitializationExampleCreatesFinalization;
    [Test]
    procedure InitializationFreedIsSilent;
    [Test]
    procedure ExistingFinalizationGetsSafeFix;
    [Test]
    procedure HandedOverOrOwnedIsSilent;
    [Test]
    procedure ClassConstructorWithoutClassDestructor;
    [Test]
    procedure ClassConstructorWithClassDestructor;
    [Test]
    procedure VisibleVariableUsedElsewhereIsSilent;
    [Test]
    procedure InitializationRuleOffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.FreeFields,
  Atlas.Common.Rules.Builtin.FreeFields,
  Atlas.Tests.RuleAssert;

const
  Text = 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'  private'#10'    FList: TStringList;'#10 +
    '  public'#10'    constructor Create;'#10'  end;'#10'implementation'#10'constructor TFoo.Create;'#10'begin'#10 +
    '  FList := TStringList.Create;'#10'end;'#10'end.';
  Returned = 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'  private'#10'    FList: TStringList;'#10 +
    '  public'#10'    constructor Create;'#10'    function Take: TStringList;'#10'  end;'#10'implementation'#10 +
    'constructor TFoo.Create;'#10'begin'#10'  FList := TStringList.Create;'#10'end;'#10 +
    'function TFoo.Take: TStringList;'#10'begin'#10'  Result := FList;'#10'end;'#10'end.';

procedure TFreeFieldRulesTests.NotFreedIsWarningWithFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Text);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual('FList wird im Konstruktor erzeugt, aber im Destruktor nicht freigegeben (Speicherleck).',
    Findings[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Im Destruktor freigeben', Findings[0].Fixes[0].Title);
  Assert.IsFalse(Findings[0].Fixes[0].Safe);
  Assert.AreEqual(2, Integer(Length(Findings[0].Fixes[0].Edits)));
  Assert.AreEqual(#10'    destructor Destroy; override;', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.IsTrue(Findings[0].Fixes[0].Edits[1].NewText.Contains('  FList.Free;'#10'  inherited;'));
  TRuleAssert.Silent(TOwnedFieldFreeUnclearRule.Create, Text);
end;

procedure TFreeFieldRulesTests.FreeAndNilStyleInFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Text,
    '{"refactoring": {"freeFieldsStyle": "freeAndNil"}}');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.IsTrue(Findings[0].Fixes[0].Edits[1].NewText.Contains('  FreeAndNil(FList);'#10'  inherited;'));
end;

procedure TFreeFieldRulesTests.UnclearIsHintWithoutFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TOwnedFieldFreeUnclearRule.Create, Returned);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual('"FList" wird in TFoo.Create erzeugt und nicht freigegeben; ob TFoo es freigeben muss, ist unklar: ' +
    'Es wird von TFoo.Take zurückgegeben', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  TRuleAssert.Silent(TOwnedFieldNotFreedRule.Create, Returned);
end;

procedure TFreeFieldRulesTests.SwitchedOff;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Text,
    '{"refactoring": {"freeFields": false}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedFieldFreeUnclearRule.Create, Returned,
    '{"refactoring": {"freeFields": false}}'))));
end;

const
  Import = 'unit U;'#10'interface'#10'type'#10'  TImport = class'#10'  private'#10'    FZeilen: TStringList;'#10 +
    '    FFehler: TStringList;'#10'  public'#10'    constructor Create;'#10'    destructor Destroy; override;'#10 +
    '  end;'#10'implementation'#10'constructor TImport.Create;'#10'begin'#10'  FZeilen := TStringList.Create;'#10 +
    '  FFehler := TStringList.Create;'#10'end;'#10'destructor TImport.Destroy;'#10'begin'#10'  FZeilen.Free;'#10 +
    '  inherited;'#10'end;'#10'end.';

procedure TFreeFieldRulesTests.IssueExampleReportsOnlyUnfreedField;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Import);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('FFehler wird im Konstruktor erzeugt, aber im Destruktor nicht freigegeben (Speicherleck).',
    Findings[0].Message);
  Assert.AreEqual(6, Findings[0].Range.StartPos.Line);
  // Korrigierte Form: beide Felder frei.
  TRuleAssert.Silent(TOwnedFieldNotFreedRule.Create, StringReplace(Import, '  FZeilen.Free;'#10,
    '  FZeilen.Free;'#10'  FFehler.Free;'#10, []));
end;

procedure TFreeFieldRulesTests.OwnedComponentAndFreedFieldSilent;
const
  Owned = 'unit U;'#10'interface'#10'type'#10'  TFenster = class(TForm)'#10'  private'#10 +
    '    FKnopf: TButton;'#10'  public'#10'    constructor Create(AOwner: TComponent); override;'#10'  end;'#10 +
    'implementation'#10'constructor TFenster.Create(AOwner: TComponent);'#10'begin'#10 +
    '  inherited Create(AOwner);'#10'  FKnopf := TButton.Create(Self);'#10'end;'#10'end.';
begin
  // Komponente mit Owner: der Owner gibt sie frei.
  TRuleAssert.Silent(TOwnedFieldNotFreedRule.Create, Owned);
end;

procedure TFreeFieldRulesTests.IgnoreTypesSilencesClass;
var
  Findings: TArray<TRuleFinding>;
  Issues: TArray<TConfigurationIssue>;
  Field: TOwnedField;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Import,
    '{"rules": {"field-not-freed": {"ignoreTypes": ["TStringList"]}}}', 'U.pas'))));
  Findings := TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Import,
    '{"rules": {"field-not-freed": {"ignoreTypes": ["TObjectList"]}}}', 'U.pas');
  Assert.AreEqual(1, Integer(Length(Findings)), 'andere Klasse bleibt gemeldet');
  // Generische Deklaration trifft auch ohne Typparameter.
  Field := Default(TOwnedField);
  Field.TypeName := 'TObjectList<TOrder>';
  Field.CreatedType := 'TObjectList<TOrder>';
  Assert.IsTrue(TOwnedFieldNotFreedRule.Ignored(Field, ['tobjectlist']));
  Assert.IsFalse(TOwnedFieldNotFreedRule.Ignored(Field, ['TStringList']));
  TConfigurationParser.Parse('{"rules": {"field-not-freed": {"ignoreTypes": "TStringList"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"ignoreTypes" muss eine Liste von Texten sein', Issues[0].Message);
end;

procedure TFreeFieldRulesTests.FormerIdStillApplies;
begin
  Assert.AreEqual('field-not-freed', TRuleIdAliases.Current('owned-field-not-freed'));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Import,
    '{"rules": {"owned-field-not-freed": "off"}}', 'U.pas'))));
  TRuleAssert.Silent(TOwnedFieldNotFreedRule.Create, StringReplace(Import, '    FFehler: TStringList;',
    '    FFehler: TStringList; // lsp-ignore: owned-field-not-freed', []));
end;

procedure TFreeFieldRulesTests.OffAndExcludeSilence;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Import,
    '{"rules": {"field-not-freed": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Import,
    '{"rules": {"field-not-freed": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Import,
    '{"rules": {"field-not-freed": {"exclude": ["Alt/*.pas"]}}}', 'Neu/U.pas'))));
end;

const
  // Beispiel aus #971
  Protokoll = 'unit U;'#10'interface'#10'implementation'#10'var'#10'  GProtokoll: TProtokoll;'#10 +
    'initialization'#10'  GProtokoll := TProtokoll.Create;'#10'end.';

function InitFindings(const ASource: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TInitializationNotFinalizedRule.Create, ASource);
end;

procedure TFreeFieldRulesTests.InitializationExampleCreatesFinalization;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := InitFindings(Protokoll);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('GProtokoll wird in initialization erzeugt, aber in finalization nicht freigegeben.',
    Findings[0].Message);
  Assert.AreEqual(6, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(12, Findings[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('In finalization freigeben', Findings[0].Fixes[0].Title);
  // Neue finalization und uses-Eintrag: nur einzeln anwenden.
  Assert.IsFalse(Findings[0].Fixes[0].Safe);
  Assert.AreEqual('unit U;'#10'interface'#10'implementation'#10#10'uses'#10'  System.SysUtils;'#10'var'#10 +
    '  GProtokoll: TProtokoll;'#10'initialization'#10'  GProtokoll := TProtokoll.Create;'#10#10'finalization'#10 +
    '  FreeAndNil(GProtokoll);'#10'end.', TChangeSignature.ApplyEdits(Protokoll, Findings[0].Fixes[0].Edits));
  // Die korrigierte Form schweigt.
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create,
    TChangeSignature.ApplyEdits(Protokoll, Findings[0].Fixes[0].Edits));
end;

procedure TFreeFieldRulesTests.InitializationFreedIsSilent;
const
  Freed = 'unit U;'#10'interface'#10'implementation'#10'var'#10'  GListe: TStringList;'#10 +
    'initialization'#10'  GListe := TStringList.Create;'#10'finalization'#10'  if Assigned(GListe) then'#10 +
    '    GListe.Free;'#10'end.';
  InRoutine = 'unit U;'#10'interface'#10'procedure Aufraeumen;'#10'implementation'#10'var'#10 +
    '  GListe: TStringList;'#10'procedure Aufraeumen;'#10'begin'#10'  FreeAndNil(GListe);'#10'end;'#10 +
    'initialization'#10'  GListe := TStringList.Create;'#10'  GListe.Add(''a'');'#10'end.';
begin
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create, Freed);
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create, InRoutine);
  // Ohne Freigabe meldet dieselbe Unit.
  Assert.AreEqual(1, Integer(Length(InitFindings(StringReplace(InRoutine, '  FreeAndNil(GListe);'#10, '', [])))));
end;

procedure TFreeFieldRulesTests.ExistingFinalizationGetsSafeFix;
const
  Existing = 'unit U;'#10'interface'#10'implementation'#10'uses'#10'  System.SysUtils;'#10'var'#10 +
    '  GA: TStringList;'#10'  GB: TStringList;'#10'initialization'#10'  GA := TStringList.Create;'#10 +
    '  GB := TStringList.Create;'#10'finalization'#10'  GB.Free'#10'end.';
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := InitFindings(Existing);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('GA wird in initialization erzeugt, aber in finalization nicht freigegeben.', Findings[0].Message);
  Assert.IsTrue(Findings[0].Fixes[0].Safe);
  // Fehlendes Semikolon hinter der letzten Anweisung wird ergänzt.
  Assert.AreEqual(StringReplace(Existing, '  GB.Free'#10, '  GB.Free;'#10'  FreeAndNil(GA);'#10, []),
    TChangeSignature.ApplyEdits(Existing, Findings[0].Fixes[0].Edits));
end;

procedure TFreeFieldRulesTests.HandedOverOrOwnedIsSilent;

  function Unit_(const AVar, AInit: string): string;
  begin
    Result := 'unit U;'#10'interface'#10'implementation'#10'var'#10'  ' + AVar + #10 +
      'procedure Nimm(AObjekt: TObject);'#10'begin'#10'end;'#10'initialization'#10 + AInit + #10'end.';
  end;

begin
  // Gegenprobe: so wird gemeldet.
  Assert.AreEqual(1, Integer(Length(InitFindings(Unit_('G: TListe;', '  G := TListe.Create;'#10'  G.Add(1);')))));
  // Interface, Record mit Create, Komponente mit Owner
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create, Unit_('G: IListe;', '  G := TListe.Create;'));
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create, Unit_('G: TStopwatch;', '  G := TStopwatch.Create;'));
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create,
    Unit_('G: TDatenmodul;', '  G := TDatenmodul.Create(Application);'));
  // Weitergegeben: als Argument, zugewiesen, mit with, als Thread mit FreeOnTerminate
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create, Unit_('G: TListe;', '  G := TListe.Create;'#10'  Nimm(G);'));
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create,
    Unit_('G: TListe;', '  G := TListe.Create;'#10'  Application.Liste := G;'));
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create,
    Unit_('G: TListe;', '  G := TListe.Create;'#10'  with G do'#10'    Free;'));
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create,
    Unit_('G: TArbeit;', '  G := TArbeit.Create(True);'#10'  G.FreeOnTerminate := True;'#10'  G.Start;'));
  // Nur deklariert, nicht in initialization erzeugt
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create, Unit_('G: TListe;', '  G := nil;'));
end;

const
  Singleton = 'unit U;'#10'interface'#10'type'#10'  TDienst = class'#10'  private'#10'    class var FInstanz: TDienst;'#10 +
    '    class constructor Create;'#10'  end;'#10'implementation'#10'uses'#10'  System.SysUtils;'#10 +
    'class constructor TDienst.Create;'#10'begin'#10'  FInstanz := TDienst.Create;'#10'end;'#10'end.';

procedure TFreeFieldRulesTests.ClassConstructorWithoutClassDestructor;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := InitFindings(Singleton);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('FInstanz wird im class constructor erzeugt, aber im class destructor nicht freigegeben.',
    Findings[0].Message);
  Assert.AreEqual(13, Findings[0].Range.StartPos.Line);
  Assert.AreEqual('Im class destructor freigeben', Findings[0].Fixes[0].Title);
  Assert.IsFalse(Findings[0].Fixes[0].Safe);
  Assert.AreEqual('unit U;'#10'interface'#10'type'#10'  TDienst = class'#10'  private'#10 +
    '    class var FInstanz: TDienst;'#10'    class constructor Create;'#10'    class destructor Destroy;'#10 +
    '  end;'#10'implementation'#10'uses'#10'  System.SysUtils;'#10'class constructor TDienst.Create;'#10'begin'#10 +
    '  FInstanz := TDienst.Create;'#10'end;'#10#10'class destructor TDienst.Destroy;'#10'begin'#10 +
    '  FreeAndNil(FInstanz);'#10'end;'#10'end.', TChangeSignature.ApplyEdits(Singleton, Findings[0].Fixes[0].Edits));
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create,
    TChangeSignature.ApplyEdits(Singleton, Findings[0].Fixes[0].Edits));
end;

procedure TFreeFieldRulesTests.ClassConstructorWithClassDestructor;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := StringReplace(StringReplace(Singleton, '    class constructor Create;'#10,
    '    class constructor Create;'#10'    class destructor Destroy;'#10, []), 'end;'#10'end.',
    'end;'#10'class destructor TDienst.Destroy;'#10'begin'#10'end;'#10'end.', []);
  Findings := InitFindings(Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.IsTrue(Findings[0].Fixes[0].Safe);
  Assert.AreEqual(StringReplace(Source, 'Destroy;'#10'begin'#10'end;', 'Destroy;'#10'begin'#10 +
    '  FreeAndNil(FInstanz);'#10'end;', []), TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits));
  // Freigabe über den Klassennamen
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create, StringReplace(Source, 'Destroy;'#10'begin'#10'end;',
    'Destroy;'#10'begin'#10'  TDienst.FInstanz.Free;'#10'end;', []));
  // Öffentliche Property: andere könnten das Objekt übernehmen.
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create, StringReplace(Source, '    class constructor Create;',
    '    class constructor Create;'#10'  public'#10'    class property Instanz: TDienst read FInstanz;', []));
end;

procedure TFreeFieldRulesTests.VisibleVariableUsedElsewhereIsSilent;
const
  Visible = 'unit U;'#10'interface'#10'var'#10'  GProtokoll: TProtokoll;'#10'implementation'#10 +
    'initialization'#10'  GProtokoll := TProtokoll.Create;'#10'end.';
var
  Index: ISymbolIndex;
  Other: TUnitIndex;
  Usage: TIndexUsage;
begin
  Index := TSymbolIndex.Create;
  Assert.AreEqual(1, Integer(Length(TRuleAssert.IndexFindings(TInitializationNotFinalizedRule.Create, Visible,
    Index, '', 'U.pas'))), 'ohne Verwendung in anderen Units');
  Other := Default(TUnitIndex);
  Other.UnitName := 'Haupt';
  Other.FileName := 'Haupt.pas';
  Usage := Default(TIndexUsage);
  Usage.Name := 'GProtokoll';
  Usage.Positions := [TTextPosition.Create(10, 2)];
  Other.Usages := [Usage];
  Other.UsagesIndexed := True;
  Index.AddUnit(Other);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TInitializationNotFinalizedRule.Create, Visible,
    Index, '', 'U.pas'))), 'Haupt könnte GProtokoll freigeben');
  // Eine Variable im implementation-Abschnitt sieht keine andere Unit.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.IndexFindings(TInitializationNotFinalizedRule.Create, Protokoll,
    Index, '', 'U.pas'))));
end;

procedure TFreeFieldRulesTests.InitializationRuleOffAndExclude;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInitializationNotFinalizedRule.Create, Protokoll,
    '{"rules": {"initialization-not-finalized": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInitializationNotFinalizedRule.Create, Protokoll,
    '{"rules": {"group:robustness": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInitializationNotFinalizedRule.Create, Protokoll,
    '{"rules": {"initialization-not-finalized": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TInitializationNotFinalizedRule.Create, Protokoll,
    '{"rules": {"initialization-not-finalized": {"exclude": ["Alt/*.pas"]}}}', 'Neu/U.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TFreeFieldRulesTests);

end.
