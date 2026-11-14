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
    [Test]
    procedure IndexedOwnerAndDynamicArrayAreSilent;
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
  cText = 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'  private'#10'    FList: TStringList;'#10 +
    '  public'#10'    constructor Create;'#10'  end;'#10'implementation'#10'constructor TFoo.Create;'#10'begin'#10 +
    '  FList := TStringList.Create;'#10'end;'#10'end.';
  cReturned = 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'  private'#10'    FList: TStringList;'#10 +
    '  public'#10'    constructor Create;'#10'    function Take: TStringList;'#10'  end;'#10'implementation'#10 +
    'constructor TFoo.Create;'#10'begin'#10'  FList := TStringList.Create;'#10'end;'#10 +
    'function TFoo.Take: TStringList;'#10'begin'#10'  Result := FList;'#10'end;'#10'end.';

procedure TFreeFieldRulesTests.NotFreedIsWarningWithFix;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, cText);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual('FList wird im Konstruktor erzeugt, aber im Destruktor nicht freigegeben (Speicherleck).',
    mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  Assert.AreEqual(5, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Im Destruktor freigeben', mFindings[0].Fixes[0].Title);
  Assert.IsFalse(mFindings[0].Fixes[0].Safe);
  Assert.AreEqual(2, Integer(Length(mFindings[0].Fixes[0].Edits)));
  Assert.AreEqual(#10'    destructor Destroy; override;', mFindings[0].Fixes[0].Edits[0].NewText);
  Assert.IsTrue(mFindings[0].Fixes[0].Edits[1].NewText.Contains('  FList.Free;'#10'  inherited;'));
  TRuleAssert.Silent(TOwnedFieldFreeUnclearRule.Create, cText);
end;

procedure TFreeFieldRulesTests.FreeAndNilStyleInFix;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, cText,
    '{"refactoring": {"freeFieldsStyle": "freeAndNil"}}');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.IsTrue(mFindings[0].Fixes[0].Edits[1].NewText.Contains('  FreeAndNil(FList);'#10'  inherited;'));
end;

procedure TFreeFieldRulesTests.UnclearIsHintWithoutFix;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOwnedFieldFreeUnclearRule.Create, cReturned);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual('"FList" wird in TFoo.Create erzeugt und nicht freigegeben; ob TFoo es freigeben muss, ist unklar: ' +
    'Es wird von TFoo.Take zurückgegeben', mFindings[0].Message);
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  TRuleAssert.Silent(TOwnedFieldNotFreedRule.Create, cReturned);
end;

procedure TFreeFieldRulesTests.SwitchedOff;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, cText,
    '{"refactoring": {"freeFields": false}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedFieldFreeUnclearRule.Create, cReturned,
    '{"refactoring": {"freeFields": false}}'))));
end;

const
  cImport = 'unit U;'#10'interface'#10'type'#10'  TImport = class'#10'  private'#10'    FZeilen: TStringList;'#10 +
    '    FFehler: TStringList;'#10'  public'#10'    constructor Create;'#10'    destructor Destroy; override;'#10 +
    '  end;'#10'implementation'#10'constructor TImport.Create;'#10'begin'#10'  FZeilen := TStringList.Create;'#10 +
    '  FFehler := TStringList.Create;'#10'end;'#10'destructor TImport.Destroy;'#10'begin'#10'  FZeilen.Free;'#10 +
    '  inherited;'#10'end;'#10'end.';

procedure TFreeFieldRulesTests.IssueExampleReportsOnlyUnfreedField;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, cImport);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('FFehler wird im Konstruktor erzeugt, aber im Destruktor nicht freigegeben (Speicherleck).',
    mFindings[0].Message);
  Assert.AreEqual(6, mFindings[0].Range.StartPos.Line);
  // Korrigierte Form: beide Felder frei.
  TRuleAssert.Silent(TOwnedFieldNotFreedRule.Create, StringReplace(cImport, '  FZeilen.Free;'#10,
    '  FZeilen.Free;'#10'  FFehler.Free;'#10, []));
  // Freigabe über eine lokale Kopie (Writer := FWriter; FWriter := nil; Writer.Free).
  TRuleAssert.Silent(TOwnedFieldNotFreedRule.Create, StringReplace(StringReplace(cImport,
    'destructor TImport.Destroy;'#10'begin'#10, 'destructor TImport.Destroy;'#10'var'#10'  Alt: TStringList;'#10 +
    'begin'#10, []), '  FZeilen.Free;'#10, '  FZeilen.Free;'#10'  Alt := FFehler;'#10'  FFehler := nil;'#10 +
    '  Alt.Free;'#10, []));
end;

procedure TFreeFieldRulesTests.OwnedComponentAndFreedFieldSilent;
const
  cOwned = 'unit U;'#10'interface'#10'type'#10'  TFenster = class(TForm)'#10'  private'#10 +
    '    FKnopf: TButton;'#10'  public'#10'    constructor Create(AOwner: TComponent); override;'#10'  end;'#10 +
    'implementation'#10'constructor TFenster.Create(AOwner: TComponent);'#10'begin'#10 +
    '  inherited Create(AOwner);'#10'  FKnopf := TButton.Create(Self);'#10'end;'#10'end.';
begin
  // Komponente mit Owner: der Owner gibt sie frei.
  TRuleAssert.Silent(TOwnedFieldNotFreedRule.Create, cOwned);
end;

procedure TFreeFieldRulesTests.IgnoreTypesSilencesClass;
var
  mFindings: TArray<TRuleFinding>;
  mIssues: TArray<TConfigurationIssue>;
  mField: TOwnedField;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, cImport,
    '{"rules": {"field-not-freed": {"ignoreTypes": ["TStringList"]}}}', 'U.pas'))));
  mFindings := TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, cImport,
    '{"rules": {"field-not-freed": {"ignoreTypes": ["TObjectList"]}}}', 'U.pas');
  Assert.AreEqual(1, Integer(Length(mFindings)), 'andere Klasse bleibt gemeldet');
  // Generische Deklaration trifft auch ohne Typparameter.
  mField := Default(TOwnedField);
  mField.TypeName := 'TObjectList<TOrder>';
  mField.CreatedType := 'TObjectList<TOrder>';
  Assert.IsTrue(TOwnedFieldNotFreedRule.Ignored(mField, ['tobjectlist']));
  Assert.IsFalse(TOwnedFieldNotFreedRule.Ignored(mField, ['TStringList']));
  TConfigurationParser.Parse('{"rules": {"field-not-freed": {"ignoreTypes": "TStringList"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual('"ignoreTypes" muss eine Liste von Texten sein', mIssues[0].Message);
end;

procedure TFreeFieldRulesTests.FormerIdStillApplies;
begin
  Assert.AreEqual('field-not-freed', TRuleIdAliases.Current('owned-field-not-freed'));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, cImport,
    '{"rules": {"owned-field-not-freed": "off"}}', 'U.pas'))));
  TRuleAssert.Silent(TOwnedFieldNotFreedRule.Create, StringReplace(cImport, '    FFehler: TStringList;',
    '    FFehler: TStringList; // lsp-ignore: owned-field-not-freed', []));
end;

procedure TFreeFieldRulesTests.OffAndExcludeSilence;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, cImport,
    '{"rules": {"field-not-freed": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, cImport,
    '{"rules": {"field-not-freed": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, cImport,
    '{"rules": {"field-not-freed": {"exclude": ["Alt/*.pas"]}}}', 'Neu/U.pas'))));
end;

const
  // Beispiel aus #971
  cProtokoll = 'unit U;'#10'interface'#10'implementation'#10'var'#10'  GProtokoll: TProtokoll;'#10 +
    'initialization'#10'  GProtokoll := TProtokoll.Create;'#10'end.';

function InitFindings(const ASource: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TInitializationNotFinalizedRule.Create, ASource);
end;

procedure TFreeFieldRulesTests.InitializationExampleCreatesFinalization;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := InitFindings(cProtokoll);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('GProtokoll wird in initialization erzeugt, aber in finalization nicht freigegeben.',
    mFindings[0].Message);
  Assert.AreEqual(6, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(12, mFindings[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('In finalization freigeben', mFindings[0].Fixes[0].Title);
  // Neue finalization und uses-Eintrag: nur einzeln anwenden.
  Assert.IsFalse(mFindings[0].Fixes[0].Safe);
  Assert.AreEqual('unit U;'#10'interface'#10'implementation'#10#10'uses'#10'  System.SysUtils;'#10'var'#10 +
    '  GProtokoll: TProtokoll;'#10'initialization'#10'  GProtokoll := TProtokoll.Create;'#10#10'finalization'#10 +
    '  FreeAndNil(GProtokoll);'#10'end.', TChangeSignature.ApplyEdits(cProtokoll, mFindings[0].Fixes[0].Edits));
  // Die korrigierte Form schweigt.
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create,
    TChangeSignature.ApplyEdits(cProtokoll, mFindings[0].Fixes[0].Edits));
end;

procedure TFreeFieldRulesTests.InitializationFreedIsSilent;
const
  cFreed = 'unit U;'#10'interface'#10'implementation'#10'var'#10'  GListe: TStringList;'#10 +
    'initialization'#10'  GListe := TStringList.Create;'#10'finalization'#10'  if Assigned(GListe) then'#10 +
    '    GListe.Free;'#10'end.';
  cInRoutine = 'unit U;'#10'interface'#10'procedure Aufraeumen;'#10'implementation'#10'var'#10 +
    '  GListe: TStringList;'#10'procedure Aufraeumen;'#10'begin'#10'  FreeAndNil(GListe);'#10'end;'#10 +
    'initialization'#10'  GListe := TStringList.Create;'#10'  GListe.Add(''a'');'#10'end.';
begin
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create, cFreed);
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create, cInRoutine);
  // Ohne Freigabe meldet dieselbe Unit.
  Assert.AreEqual(1, Integer(Length(InitFindings(StringReplace(cInRoutine, '  FreeAndNil(GListe);'#10, '', [])))));
end;

procedure TFreeFieldRulesTests.ExistingFinalizationGetsSafeFix;
const
  cExisting = 'unit U;'#10'interface'#10'implementation'#10'uses'#10'  System.SysUtils;'#10'var'#10 +
    '  GA: TStringList;'#10'  GB: TStringList;'#10'initialization'#10'  GA := TStringList.Create;'#10 +
    '  GB := TStringList.Create;'#10'finalization'#10'  GB.Free'#10'end.';
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := InitFindings(cExisting);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('GA wird in initialization erzeugt, aber in finalization nicht freigegeben.', mFindings[0].Message);
  Assert.IsTrue(mFindings[0].Fixes[0].Safe);
  // Fehlendes Semikolon hinter der letzten Anweisung wird ergänzt.
  Assert.AreEqual(StringReplace(cExisting, '  GB.Free'#10, '  GB.Free;'#10'  FreeAndNil(GA);'#10, []),
    TChangeSignature.ApplyEdits(cExisting, mFindings[0].Fixes[0].Edits));
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
  cSingleton = 'unit U;'#10'interface'#10'type'#10'  TDienst = class'#10'  private'#10'    class var FInstanz: TDienst;'#10 +
    '    class constructor Create;'#10'  end;'#10'implementation'#10'uses'#10'  System.SysUtils;'#10 +
    'class constructor TDienst.Create;'#10'begin'#10'  FInstanz := TDienst.Create;'#10'end;'#10'end.';

procedure TFreeFieldRulesTests.ClassConstructorWithoutClassDestructor;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := InitFindings(cSingleton);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('FInstanz wird im class constructor erzeugt, aber im class destructor nicht freigegeben.',
    mFindings[0].Message);
  Assert.AreEqual(13, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual('Im class destructor freigeben', mFindings[0].Fixes[0].Title);
  Assert.IsFalse(mFindings[0].Fixes[0].Safe);
  Assert.AreEqual('unit U;'#10'interface'#10'type'#10'  TDienst = class'#10'  private'#10 +
    '    class var FInstanz: TDienst;'#10'    class constructor Create;'#10'    class destructor Destroy;'#10 +
    '  end;'#10'implementation'#10'uses'#10'  System.SysUtils;'#10'class constructor TDienst.Create;'#10'begin'#10 +
    '  FInstanz := TDienst.Create;'#10'end;'#10#10'class destructor TDienst.Destroy;'#10'begin'#10 +
    '  FreeAndNil(FInstanz);'#10'end;'#10'end.', TChangeSignature.ApplyEdits(cSingleton, mFindings[0].Fixes[0].Edits));
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create,
    TChangeSignature.ApplyEdits(cSingleton, mFindings[0].Fixes[0].Edits));
end;

procedure TFreeFieldRulesTests.ClassConstructorWithClassDestructor;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := StringReplace(StringReplace(cSingleton, '    class constructor Create;'#10,
    '    class constructor Create;'#10'    class destructor Destroy;'#10, []), 'end;'#10'end.',
    'end;'#10'class destructor TDienst.Destroy;'#10'begin'#10'end;'#10'end.', []);
  mFindings := InitFindings(mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.IsTrue(mFindings[0].Fixes[0].Safe);
  Assert.AreEqual(StringReplace(mSource, 'Destroy;'#10'begin'#10'end;', 'Destroy;'#10'begin'#10 +
    '  FreeAndNil(FInstanz);'#10'end;', []), TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits));
  // Freigabe über den Klassennamen
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create, StringReplace(mSource, 'Destroy;'#10'begin'#10'end;',
    'Destroy;'#10'begin'#10'  TDienst.FInstanz.Free;'#10'end;', []));
  // Öffentliche Property: andere könnten das Objekt übernehmen.
  TRuleAssert.Silent(TInitializationNotFinalizedRule.Create, StringReplace(mSource, '    class constructor Create;',
    '    class constructor Create;'#10'  public'#10'    class property Instanz: TDienst read FInstanz;', []));
end;

procedure TFreeFieldRulesTests.VisibleVariableUsedElsewhereIsSilent;
const
  cVisible = 'unit U;'#10'interface'#10'var'#10'  GProtokoll: TProtokoll;'#10'implementation'#10 +
    'initialization'#10'  GProtokoll := TProtokoll.Create;'#10'end.';
var
  mIndex: ISymbolIndex;
  mOther: TUnitIndex;
  mUsage: TIndexUsage;
begin
  mIndex := TSymbolIndex.Create;
  Assert.AreEqual(1, Integer(Length(TRuleAssert.IndexFindings(TInitializationNotFinalizedRule.Create, cVisible,
    mIndex, '', 'U.pas'))), 'ohne Verwendung in anderen Units');
  mOther := Default(TUnitIndex);
  mOther.UnitName := 'Haupt';
  mOther.FileName := 'Haupt.pas';
  mUsage := Default(TIndexUsage);
  mUsage.Name := 'GProtokoll';
  mUsage.Positions := [TTextPosition.Create(10, 2)];
  mOther.Usages := [mUsage];
  mOther.UsagesIndexed := True;
  mIndex.AddUnit(mOther);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TInitializationNotFinalizedRule.Create, cVisible,
    mIndex, '', 'U.pas'))), 'Haupt könnte GProtokoll freigeben');
  // Eine Variable im implementation-Abschnitt sieht keine andere Unit.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.IndexFindings(TInitializationNotFinalizedRule.Create, cProtokoll,
    mIndex, '', 'U.pas'))));
end;

procedure TFreeFieldRulesTests.IndexedOwnerAndDynamicArrayAreSilent;
const
  // Wie Atlas.IDE.Build.CheckOnSave: Der Dienst aus einer anderen Unit hält seine Teilnehmer in einer
  // TObjectList; dazu ein TArray<string>, das der Index neben der Klasse TArray kennt.
  cSource = 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'  private type'#10 +
    '    TWatcher = class(TParticipant)'#10'    end;'#10'  private'#10'    FEvents: TEvents;'#10 +
    '    FWatcher: TWatcher;'#10'    FNames: TArray<string>;'#10'  public'#10 +
    '    constructor Create(AEvents: TEvents);'#10'    function Names: TArray<string>;'#10'  end;'#10 +
    'implementation'#10'constructor TFoo.Create(AEvents: TEvents);'#10'begin'#10'  FEvents := AEvents;'#10 +
    '  FWatcher := TWatcher.Create;'#10'  FEvents.Add(FWatcher);'#10 +
    '  FNames := TArray<string>.Create(''a'');'#10'end;'#10'function TFoo.Names: TArray<string>;'#10 +
    'begin'#10'  Result := FNames;'#10'end;'#10'end.';

  function Symbol(const AName, AContainer: string; AKind: TIndexSymbolKind; const ATypeName,
    ATypeArgs: string): TIndexSymbol;
  begin
    Result := Default(TIndexSymbol);
    Result.Name := AName;
    Result.Container := AContainer;
    Result.Kind := AKind;
    Result.TypeName := ATypeName;
    Result.TypeArgs := ATypeArgs;
  end;

  function Unclear(const AIndex: ISymbolIndex): Integer;
  begin
    Result := Length(TRuleAssert.IndexFindings(TOwnedFieldFreeUnclearRule.Create, cSource, AIndex, '', 'U.pas')) +
      Length(TRuleAssert.IndexFindings(TOwnedFieldNotFreedRule.Create, cSource, AIndex, '', 'U.pas'));
  end;

var
  mIndex: ISymbolIndex;
  mEvents, mCollections: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  mCollections := Default(TUnitIndex);
  mCollections.UnitName := 'System.Generics.Collections';
  mCollections.FileName := 'System.Generics.Collections.pas';
  mCollections.Symbols := [Symbol('TArray', '', TIndexSymbolKind.ClassType, '', '')];
  mIndex.AddUnit(mCollections);
  mEvents := Default(TUnitIndex);
  mEvents.UnitName := 'Events';
  mEvents.FileName := 'Events.pas';
  mEvents.Symbols := [Symbol('TEvents', '', TIndexSymbolKind.ClassType, '', ''),
    Symbol('FItems', 'TEvents', TIndexSymbolKind.Field, 'TObjectList', 'TParticipant')];
  mIndex.AddUnit(mEvents);
  Assert.AreEqual(0, Unclear(mIndex));
  // Ohne besitzende Liste bleibt die Übergabe unklar.
  mEvents.Symbols := [Symbol('TEvents', '', TIndexSymbolKind.ClassType, '', ''),
    Symbol('FItems', 'TEvents', TIndexSymbolKind.Field, 'TList', 'TParticipant')];
  mIndex.AddUnit(mEvents);
  Assert.AreEqual(1, Unclear(mIndex));
end;

procedure TFreeFieldRulesTests.InitializationRuleOffAndExclude;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInitializationNotFinalizedRule.Create, cProtokoll,
    '{"rules": {"initialization-not-finalized": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInitializationNotFinalizedRule.Create, cProtokoll,
    '{"rules": {"group:robustness": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInitializationNotFinalizedRule.Create, cProtokoll,
    '{"rules": {"initialization-not-finalized": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TInitializationNotFinalizedRule.Create, cProtokoll,
    '{"rules": {"initialization-not-finalized": {"exclude": ["Alt/*.pas"]}}}', 'Neu/U.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TFreeFieldRulesTests);

end.
