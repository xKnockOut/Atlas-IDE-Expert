unit Atlas.Common.Rules.Builtin.Inheritance.Tests;

// Tests für die Vererbungsregeln (#125), shadowed-name (#934) und
// inherited-abstract-call (#1026), override-only-inherited (#1143) und
// inherited-without-ancestor (#1144).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInheritanceRulesTests = class
  public
    [Test]
    procedure DestroyWithoutOverrideReportsPreferredFix;
    [Test]
    procedure DestroyWithOverrideIsSilent;
    [Test]
    procedure ComponentCreateResolvedFromIndexReports;
    [Test]
    procedure CreateOutsideComponentIsSilent;
    [Test]
    procedure UnresolvableAncestorIsSilent;
    [Test]
    procedure HidesVirtualOffersTwoAlternatives;
    [Test]
    procedure HidesVirtualWithOtherSignatureIsMedium;
    [Test]
    procedure ReintroduceSilencesAllRules;
    [Test]
    procedure OverloadWithOtherSignatureIsSilent;
    [Test]
    procedure VirtualInsteadOfOverrideReplacesDirective;
    [Test]
    procedure NewVirtualMethodIsSilent;
    /// <summary>#1094: Tiefe Ausdrücke in Routinen sprengen den Stapel nicht mehr; die Regeln melden weiter.
    /// Ohne Fix stieg ClassMethods rekursiv durch jeden Ausdruck ab und lief in 256 KB Stapel über.</summary>
    [Test]
    procedure DeepExpressionDoesNotOverflowStack;
    [Test]
    procedure ShadowedNameIssueExample;
    [Test]
    procedure ShadowedNameFieldsLocalsAndGlobals;
    [Test]
    procedure ShadowedNameFromIndexAndVisibility;
    [Test]
    procedure ShadowedNameSilentCases;
    [Test]
    procedure ShadowedNameOptions;
    [Test]
    procedure OverrideTargetIssueExample;
    [Test]
    procedure OverrideTargetStaticFinalSealed;
    [Test]
    procedure OverrideTargetTypoAndMissing;
    [Test]
    procedure OverrideTargetSilentCases;
    [Test]
    procedure OverrideTargetFromIndex;
    /// <summary>Gleichnamige Typen mit und ohne Typparameter (#1326): THorseChannel&lt;T&gt; = class(THorseChannel)
    /// in einer Unit, TProxy und TProxy&lt;T&gt; in zwei Units des Index.</summary>
    [Test]
    procedure OverrideTargetGenericAndPlainNamesakes;
    [Test]
    procedure OverrideTargetOptions;
    [Test]
    procedure AbstractInstantiatedIssueExample;
    [Test]
    procedure AbstractInstantiatedInheritedWithFix;
    [Test]
    procedure AbstractInstantiatedAbstractClassAndIndex;
    [Test]
    procedure AbstractInstantiatedSilentCases;
    [Test]
    procedure AbstractInstantiatedOptions;
    [Test]
    procedure InheritedAbstractIssueExample;
    [Test]
    procedure InheritedAbstractExpressionAndIndex;
    [Test]
    procedure InheritedAbstractSilentCases;
    [Test]
    procedure InheritedAbstractOptions;
    [Test]
    procedure ClassRefConstructorIssueExample;
    [Test]
    procedure ClassRefConstructorFromIndex;
    [Test]
    procedure ClassRefConstructorSilentCases;
    [Test]
    procedure ClassRefConstructorOptions;
    [Test]
    procedure OverrideOnlyInheritedIssueExample;
    [Test]
    procedure OverrideOnlyInheritedForms;
    [Test]
    procedure OverrideOnlyInheritedSilentCases;
    [Test]
    procedure OverrideOnlyInheritedObjectMethods;
    [Test]
    procedure OverrideOnlyInheritedOptions;
    [Test]
    procedure InheritedWithoutAncestorIssueExample;
    [Test]
    procedure InheritedWithoutAncestorSilentCases;
    [Test]
    procedure InheritedWithoutAncestorFromIndex;
    [Test]
    procedure InheritedWithoutAncestorOptions;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Rules.Derived,
  Atlas.Tests.RuleAssert,
  Atlas.Tests.SmallStack,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Configuration.Parser;

const
  // Ausschnitte aus RTL und VCL, wie sie der Index aus den Quellen liest.
  ClassesSource =
    'unit System.Classes;'#10'interface'#10'type'#10 +
    '  TPersistent = class(TObject)'#10'  end;'#10 +
    '  TComponent = class(TPersistent)'#10'  public'#10 +
    '    constructor Create(AOwner: TComponent); virtual;'#10'  end;'#10 +
    'implementation'#10'end.';
  ControlsSource =
    'unit Vcl.Controls;'#10'interface'#10'type'#10 +
    '  TControl = class(TComponent)'#10'  end;'#10 +
    '  TCustomControl = class(TControl)'#10'  end;'#10 +
    'implementation'#10'end.';

function ClassUnit(const AMembers: string; const AHead: string = 'TFoo = class(TBasis)'): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10 +
    '  TBasis = class'#10'  public'#10'    procedure Lauf(A: Integer); virtual;'#10'  end;'#10 +
    '  ' + AHead + #10'  public'#10 + AMembers + #10'  end;'#10'implementation'#10'end.';
end;

function IndexWith(const ASources: array of string): ISymbolIndex;
var
  Index: Integer;
  Tree: TSyntaxTree;
begin
  Result := TSymbolIndex.Create;
  for Index := 0 to High(ASources) do
  begin
    Tree := TPascalParser.Parse(ASources[Index]);
    try
      Result.AddUnit(TIndexExtractor.Extract(Tree, Format('C:\Quellen\Unit%d.pas', [Index])));
    finally
      Tree.Free;
    end;
  end;
end;

function Run(const ARule: IRule; const ASource: string; const AIndex: ISymbolIndex): TArray<TRuleFinding>;
var
  Context: TRuleContext;
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(ASource);
  try
    Context := Default(TRuleContext);
    Context.Text := ASource;
    Context.Tree := Tree;
    Context.Index := AIndex;
    Result := TRuleEngine.Run([ARule], TServerSettings.Default, Context);
  finally
    Tree.Free;
  end;
end;

procedure TInheritanceRulesTests.DestroyWithoutOverrideReportsPreferredFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TDestroyWithoutOverrideRule.Create, ClassUnit('    destructor Destroy;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.IsFalse(Findings[0].Fixes[0].Alternative);
  Assert.AreEqual(' override;', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(9, Findings[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(23, Findings[0].Fixes[0].Edits[0].Range.StartPos.Character);
end;

procedure TInheritanceRulesTests.DestroyWithOverrideIsSilent;
begin
  TRuleAssert.Silent(TDestroyWithoutOverrideRule.Create, ClassUnit('    destructor Destroy; override;'));
end;

procedure TInheritanceRulesTests.ComponentCreateResolvedFromIndexReports;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := Run(TComponentCreateWithoutOverrideRule.Create,
    ClassUnit('    constructor Create(AOwner: TComponent);', 'TFoo = class(TCustomControl)'),
    IndexWith([ClassesSource, ControlsSource]));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(' override;', Findings[0].Fixes[0].Edits[0].NewText);
  // Ohne override verdeckt der Konstruktor TComponent.Create, das meldet aber nur diese Regel.
  Assert.AreEqual(0, Integer(Length(Run(THidesVirtualRule.Create,
    ClassUnit('    constructor Create(AOwner: TComponent);', 'TFoo = class(TCustomControl)'),
    IndexWith([ClassesSource, ControlsSource])))));
end;

procedure TInheritanceRulesTests.CreateOutsideComponentIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(Run(TComponentCreateWithoutOverrideRule.Create,
    ClassUnit('    constructor Create(AOwner: TComponent);'), IndexWith([ClassesSource])))));
end;

procedure TInheritanceRulesTests.UnresolvableAncestorIsSilent;
begin
  // TCustomControl fehlt im Index: keine Aussage.
  Assert.AreEqual(0, Integer(Length(Run(TComponentCreateWithoutOverrideRule.Create,
    ClassUnit('    constructor Create(AOwner: TComponent);', 'TFoo = class(TCustomControl)'),
    IndexWith([ClassesSource])))));
  Assert.AreEqual(0, Integer(Length(Run(THidesVirtualRule.Create,
    ClassUnit('    procedure Lauf(A: Integer);', 'TFoo = class(TUnbekannt)'), nil))));
end;

procedure TInheritanceRulesTests.HidesVirtualOffersTwoAlternatives;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(THidesVirtualRule.Create, ClassUnit('    procedure Lauf(A: Integer);'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(2, Integer(Length(Findings[0].Fixes)));
  Assert.IsTrue(Findings[0].Fixes[0].Alternative);
  Assert.IsTrue(Findings[0].Fixes[1].Alternative);
  Assert.AreEqual(' override;', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(' reintroduce;', Findings[0].Fixes[1].Edits[0].NewText);
end;

procedure TInheritanceRulesTests.HidesVirtualWithOtherSignatureIsMedium;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(THidesVirtualRule.Create, ClassUnit('    procedure Lauf(const S: string);'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  // override passt nicht zur Signatur; nur reintroduce.
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
end;

procedure TInheritanceRulesTests.ReintroduceSilencesAllRules;
var
  Source: string;
begin
  Source := ClassUnit('    procedure Lauf(A: Integer); reintroduce;'#10'    destructor Destroy; reintroduce;');
  TRuleAssert.Silent(THidesVirtualRule.Create, Source);
  TRuleAssert.Silent(TDestroyWithoutOverrideRule.Create, Source);
  TRuleAssert.Silent(TVirtualInsteadOfOverrideRule.Create, Source);
  TRuleAssert.Silent(TComponentCreateWithoutOverrideRule.Create, Source);
end;

procedure TInheritanceRulesTests.OverloadWithOtherSignatureIsSilent;
begin
  TRuleAssert.Silent(THidesVirtualRule.Create, ClassUnit('    procedure Lauf(const S: string); overload;'));
end;

procedure TInheritanceRulesTests.VirtualInsteadOfOverrideReplacesDirective;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TVirtualInsteadOfOverrideRule.Create,
    ClassUnit('    procedure Lauf(A: Integer); virtual;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('override', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(9, Findings[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(32, Findings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  TRuleAssert.Silent(THidesVirtualRule.Create, ClassUnit('    procedure Lauf(A: Integer); virtual;'));
end;

procedure TInheritanceRulesTests.NewVirtualMethodIsSilent;
begin
  TRuleAssert.Silent(TVirtualInsteadOfOverrideRule.Create, ClassUnit('    procedure Neu; virtual;'));
  TRuleAssert.Silent(THidesVirtualRule.Create, ClassUnit('    procedure Neu; virtual;'));
end;

type
  /// <summary>Zählt Treffer einer direkt aufgerufenen Regel (ohne Engine und deren Tiefenlimit).</summary>
  TCountingReport = class(TInterfacedObject, IRuleReport)
  public
    Count: Integer;
    procedure Add(const ARange: TTextRange; const AMessage: string); overload;
    procedure Add(const ARange: TTextRange; const AMessage: string; const AFixes: TArray<TRuleFix>); overload;
    procedure Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence); overload;
    procedure Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence;
      const AFixes: TArray<TRuleFix>); overload;
    procedure AddWithSeverity(const ARange: TTextRange; const AMessage: string; ASeverity: TRuleSeverity;
      const AFixes: TArray<TRuleFix>);
    procedure AddWithDetails(const ARange: TTextRange; const AMessage, ADetails: string;
      AConfidence: TRuleConfidence; const AFixes: TArray<TRuleFix>);
  end;

procedure TCountingReport.Add(const ARange: TTextRange; const AMessage: string);
begin
  Inc(Count);
end;

procedure TCountingReport.Add(const ARange: TTextRange; const AMessage: string; const AFixes: TArray<TRuleFix>);
begin
  Inc(Count);
end;

procedure TCountingReport.Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence);
begin
  Inc(Count);
end;

procedure TCountingReport.Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence;
  const AFixes: TArray<TRuleFix>);
begin
  Inc(Count);
end;

procedure TCountingReport.AddWithSeverity(const ARange: TTextRange; const AMessage: string;
  ASeverity: TRuleSeverity; const AFixes: TArray<TRuleFix>);
begin
  Inc(Count);
end;

procedure TCountingReport.AddWithDetails(const ARange: TTextRange; const AMessage, ADetails: string;
  AConfidence: TRuleConfidence; const AFixes: TArray<TRuleFix>);
begin
  Inc(Count);
end;

procedure TInheritanceRulesTests.DeepExpressionDoesNotOverflowStack;
var
  Builder: TStringBuilder;
  Index: Integer;
  Text, Failure: string;
  Tree: TSyntaxTree;
  Context: TRuleContext;
  Rules: TArray<IRule>;
  Counter: TCountingReport;
  Report: IRuleReport;
begin
  // Subtraktion bleibt im Parser linkslastig: 3000 Glieder ergeben gut 3000 Ebenen.
  Builder := TStringBuilder.Create;
  try
    Builder.Append('unit U;'#10'interface'#10'type'#10 +
      '  TBasis = class'#10'  public'#10'    procedure Lauf(A: Integer); virtual;'#10'  end;'#10 +
      '  TFoo = class(TBasis)'#10'  public'#10'    destructor Destroy;'#10 +
      '    procedure Lauf(A: Integer); virtual;'#10'  end;'#10 +
      'implementation'#10'procedure Rechne;'#10'begin'#10'  X := 1');
    for Index := 1 to 3000 do
      Builder.Append(' - 1');
    Builder.Append(';'#10'end;'#10'end.');
    Text := Builder.ToString;
  finally
    Builder.Free;
  end;
  Rules := [TDestroyWithoutOverrideRule.Create, TComponentCreateWithoutOverrideRule.Create,
    THidesVirtualRule.Create, TVirtualInsteadOfOverrideRule.Create];
  Counter := TCountingReport.Create;
  Report := Counter;
  Tree := TPascalParser.Parse(Text);
  try
    Context := Default(TRuleContext);
    Context.Text := Text;
    Context.Tree := Tree;
    Context.Derived := TRuleDerivedCache.Create;
    Failure := TSmallStack.Run(256,
      procedure
      var
        Rule: IRule;
      begin
        for Rule in Rules do
          Rule.Check(Context, Report);
      end);
    // Der Ableitungscache hält Verweise in den Baum: vor ihm leeren.
    Context.Derived := nil;
  finally
    Tree.Free;
  end;
  Assert.AreEqual('', Failure, 'kein Stapelüberlauf');
  // destroy-without-override und virtual-instead-of-override.
  Assert.AreEqual(2, Counter.Count);
  Rules := nil;
end;

function Kunde(const AParam, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TfrmKunde = class(TForm)'#10'  public'#10 +
    '    procedure Laden(const ' + AParam + ': string);'#10'  end;'#10'implementation'#10 +
    'procedure TfrmKunde.Laden(const ' + AParam + ': string);'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

procedure TInheritanceRulesTests.ShadowedNameIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Kunde('Caption', '  Caption := Caption + '' (geladen)'';');
  Findings := TRuleAssert.Findings(TShadowedNameRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Parameter Caption verdeckt die Property TfrmKunde.Caption; die Zuweisung ändert nur den ' +
    'Parameter.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(8, Findings[0].Range.StartPos.Line);
  Assert.AreEqual('In ACaption umbenennen', Findings[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Kunde('ACaption', '  ACaption := ACaption + '' (geladen)'';'), Fixed);
  TRuleAssert.Silent(TShadowedNameRule.Create, Fixed);
end;

procedure TInheritanceRulesTests.ShadowedNameFieldsLocalsAndGlobals;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TShadowedNameRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TBasis = class'#10'  private'#10'    FWert: Integer;'#10'  protected'#10'    property Wert: Integer read FWert;'#10 +
    '  end;'#10'  TKonto = class(TBasis)'#10'  private'#10'    FStand: Integer;'#10'  public'#10 +
    '    procedure Buchen(Betrag: Integer);'#10'  end;'#10'var'#10'  Protokoll: TStringList;'#10 +
    'implementation'#10'procedure TKonto.Buchen(Betrag: Integer);'#10'var'#10'  FStand, Wert: Integer;'#10 +
    'begin'#10'  var Protokoll := 1;'#10'  FStand := Betrag;'#10'end;'#10'end.');
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual('Lokale Variable FStand verdeckt das Feld TKonto.FStand; die Zuweisung ändert nur die lokale ' +
    'Variable.', Findings[0].Message);
  Assert.AreEqual('In LFStand umbenennen', Findings[0].Fixes[0].Title);
  Assert.AreEqual('Lokale Variable Wert verdeckt die Property TKonto.Wert.', Findings[1].Message);
  Assert.AreEqual('Lokale Variable Protokoll verdeckt die globale Variable Protokoll.', Findings[2].Message);
end;

procedure TInheritanceRulesTests.ShadowedNameFromIndexAndVisibility;
const
  BaseSource = 'unit Basis;'#10'interface'#10'type'#10'  TFremd = class'#10'  private'#10 +
    '    FGeheim: Integer;'#10'  protected'#10'    FSichtbar: Integer;'#10'  public'#10 +
    '    property Name: string read FName;'#10'  end;'#10'implementation'#10'end.';
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := Run(TShadowedNameRule.Create, 'unit U;'#10'interface'#10'type'#10'  TMeins = class(TFremd)'#10 +
    '    procedure Tun(Name: string; FGeheim, FSichtbar: Integer);'#10'  end;'#10'implementation'#10 +
    'procedure TMeins.Tun(Name: string; FGeheim, FSichtbar: Integer);'#10'begin'#10'end;'#10'end.',
    IndexWith([BaseSource]));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('Parameter Name verdeckt die Property TMeins.Name.', Findings[0].Message);
  Assert.AreEqual('Parameter FSichtbar verdeckt das Feld TMeins.FSichtbar.', Findings[1].Message);
end;

procedure TInheritanceRulesTests.ShadowedNameSilentCases;
begin
  // Korrigierte Form, Ereignis-Handler mit Sender, Self.Caption, Routine ohne Klasse, unbekannter Vorfahr.
  TRuleAssert.Silent(TShadowedNameRule.Create, Kunde('ACaption', '  Self.Caption := ACaption;'));
  TRuleAssert.Silent(TShadowedNameRule.Create, 'unit U;'#10'interface'#10'type'#10'  TForm1 = class(TForm)'#10 +
    '    procedure FormClose(Sender: TObject; var Action: TCloseAction);'#10'  end;'#10'implementation'#10 +
    'procedure TForm1.FormClose(Sender: TObject; var Action: TCloseAction);'#10'begin'#10'end;'#10 +
    'procedure Frei(Caption: string);'#10'var'#10'  Name: string;'#10'begin'#10'end;'#10 +
    'procedure TUnbekannt.Tun(Caption: string);'#10'begin'#10'end;'#10'end.');
end;

procedure TInheritanceRulesTests.ShadowedNameOptions;
var
  Source: string;
  Issues: TArray<TConfigurationIssue>;
begin
  Source := Kunde('Caption', '  Caption := Caption + '' (geladen)'';');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TShadowedNameRule.Create, Source,
    '{"rules": {"shadowed-name": {"ignore": ["Cap*"]}}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TShadowedNameRule.Create, Source,
    '{"rules": {"shadowed-name": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TShadowedNameRule.Create, Source,
    '{"rules": {"shadowed-name": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  // Ohne Vorgabe "Value" wird der Setter-Parameter gemeldet.
  Source := 'unit U;'#10'interface'#10'type'#10'  TA = class'#10'    FValue: Integer;'#10 +
    '    procedure SetX(Value: Integer);'#10'  end;'#10'implementation'#10 +
    'procedure TA.SetX(Value: Integer);'#10'begin'#10'end;'#10'end.';
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TShadowedNameRule.Create, Source))));
  Source := StringReplace(Source, 'FValue', 'Value', []);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TShadowedNameRule.Create, Source))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TShadowedNameRule.Create, Source,
    '{"rules": {"shadowed-name": {"ignore": []}}}', 'U.pas'))));
  TConfigurationParser.Parse('{"rules": {"shadowed-name": {"ignore": "Value"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;

function Dienste(const ABase, AMembers, AImplementation: string): string;
begin
  Result := 'unit Dienste;'#10'interface'#10'type'#10'  TModus = (mdSchnell, mdGruendlich);'#10 +
    '  TDienst = class' + ABase + #10'  protected'#10 +
    '    procedure Ausfuehren(const Modus: TModus); virtual;'#10'  end;'#10 +
    '  TImportDienst = class(TDienst)'#10'  protected'#10 + AMembers + #10'  end;'#10 +
    'implementation'#10'procedure TDienst.Ausfuehren(const Modus: TModus);'#10'begin'#10'end;'#10 +
    AImplementation + 'end.';
end;

/// <summary>Wendet alle Edits einer Korrektur an (jedes Edit in einer Zeile, von hinten nach vorn).</summary>
function ApplyEdits(const AText: string; const AFix: TRuleFix): string;
var
  Lines: TArray<string>;
  Edit: TRuleEdit;
  Line: string;
  Index: Integer;
begin
  Lines := AText.Split([#10]);
  for Index := High(AFix.Edits) downto 0 do
  begin
    Edit := AFix.Edits[Index];
    Line := Lines[Edit.Range.StartPos.Line];
    Lines[Edit.Range.StartPos.Line] := Copy(Line, 1, Edit.Range.StartPos.Character) + Edit.NewText +
      Copy(Line, Edit.Range.EndPos.Character + 1, MaxInt);
  end;
  Result := string.Join(#10, Lines);
end;

procedure TInheritanceRulesTests.OverrideTargetIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Dienste('', '    procedure Ausfuehren(Modus: Integer); override;',
    'procedure TImportDienst.Ausfuehren(Modus: Integer);'#10'begin'#10'end;'#10);
  Findings := TRuleAssert.Findings(TOverrideTargetMissingRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TDienst hat kein virtuelles Ausfuehren(Integer); dort heißt es Ausfuehren(const Modus: TModus) ' +
    '(wie E2137).', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Signatur von TDienst.Ausfuehren übernehmen', Findings[0].Fixes[0].Title);
  Fixed := ApplyEdits(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(Dienste('', '    procedure Ausfuehren(const Modus: TModus); override;',
    'procedure TImportDienst.Ausfuehren(const Modus: TModus);'#10'begin'#10'end;'#10), Fixed);
  TRuleAssert.Silent(TOverrideTargetMissingRule.Create, Fixed);
  // Anderer Aufbau (Zahl der Parameter, Funktion statt Prozedur): ebenfalls E2137.
  Findings := TRuleAssert.Findings(TOverrideTargetMissingRule.Create, Dienste('',
    '    procedure Ausfuehren(const Modus: TModus; Stufe: Integer); override;', ''));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TDienst hat kein virtuelles Ausfuehren(TModus, Integer); dort heißt es ' +
    'Ausfuehren(const Modus: TModus) (wie E2137).', Findings[0].Message);
  // Ein unbekannter Typ könnte ein Alias sein: mittlere Konfidenz.
  Findings := TRuleAssert.Findings(TOverrideTargetMissingRule.Create, Dienste('',
    '    procedure Ausfuehren(const Modus: TUnbekannt); override;', ''));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
end;

procedure TInheritanceRulesTests.OverrideTargetStaticFinalSealed;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := 'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10'  public'#10 +
    '    procedure Statisch;'#10'    procedure Fest; virtual;'#10'  end;'#10 +
    '  TMitte = class(TBasis)'#10'  public'#10'    procedure Fest; override; final;'#10'  end;'#10 +
    '  TEnde = class(TMitte)'#10'  public'#10'    procedure Statisch; override;'#10 +
    '    procedure Fest; override;'#10'  end;'#10'implementation'#10'end.';
  Findings := TRuleAssert.Findings(TOverrideTargetMissingRule.Create, Source);
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('TBasis.Statisch ist nicht virtuell; override braucht virtual oder dynamic im Vorfahren ' +
    '(wie E2170).', Findings[0].Message);
  Assert.AreEqual('TMitte.Fest ist final und lässt sich nicht überschreiben (wie E2352).', Findings[1].Message);
  Source := 'unit U;'#10'interface'#10'type'#10'  TBasis = class sealed'#10'  end;'#10 +
    '  TAbgeleitet = class(TBasis)'#10'  end;'#10'  TFrei = class abstract'#10'  end;'#10 +
    '  TAuchFrei = class(TFrei)'#10'  end;'#10'implementation'#10'end.';
  Findings := TRuleAssert.Findings(TOverrideTargetMissingRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TBasis ist sealed; davon lässt sich nicht ableiten (wie E2353).', Findings[0].Message);
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
end;

procedure TInheritanceRulesTests.OverrideTargetTypoAndMissing;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  // Ohne System im Index: Destroy von TObject als Vorschlag.
  Source := 'unit U;'#10'interface'#10'type'#10'  TListe = class'#10'  public'#10 +
    '    destructor Destory; override;'#10'  end;'#10'implementation'#10 +
    'destructor TListe.Destory;'#10'begin'#10'  inherited;'#10'end;'#10'end.';
  Findings := TRuleAssert.Findings(TOverrideTargetMissingRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Kein Vorfahr von TListe hat ein virtuelles Destory; gemeint ist wohl Destroy (wie E2137).',
    Findings[0].Message);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Fixed := ApplyEdits(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(StringReplace(Source, 'Destory', 'Destroy', [rfReplaceAll]), Fixed);
  TRuleAssert.Silent(TOverrideTargetMissingRule.Create, Fixed);
  // Tippfehler in einer Methode des Vorfahren der Datei.
  Findings := TRuleAssert.Findings(TOverrideTargetMissingRule.Create, Dienste('',
    '    procedure Ausfueren(const Modus: TModus); override;', ''));
  Assert.AreEqual('Kein Vorfahr von TImportDienst hat ein virtuelles Ausfueren; gemeint ist wohl Ausfuehren ' +
    '(wie E2137).', Findings[0].Message);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  // Nichts Ähnliches: ohne Korrektur.
  Findings := TRuleAssert.Findings(TOverrideTargetMissingRule.Create, Dienste('',
    '    procedure Speichern; override;', ''));
  Assert.AreEqual('Kein Vorfahr von TImportDienst hat ein virtuelles Speichern (wie E2137).', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TInheritanceRulesTests.OverrideTargetSilentCases;
begin
  TRuleAssert.Silent(TOverrideTargetMissingRule.Create, Dienste('',
    '    procedure Ausfuehren(const Modus: TModus); override;', ''));
  // TObject ohne Index: dessen virtuelle Methoden gelten als vorhanden.
  TRuleAssert.Silent(TOverrideTargetMissingRule.Create, 'unit U;'#10'interface'#10'type'#10'  TA = class'#10 +
    '  public'#10'    destructor Destroy; override;'#10'    procedure AfterConstruction; override;'#10 +
    '    function ToString: string; override;'#10'  end;'#10'implementation'#10'end.');
  // Unbekannter Vorfahr: keine Aussage.
  TRuleAssert.Silent(TOverrideTargetMissingRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TMain = class(TForm)'#10'  protected'#10'    procedure Speichern; override;'#10'  end;'#10 +
    'implementation'#10'end.');
  // Alias der Datei und Synonyme wie Longint.
  TRuleAssert.Silent(TOverrideTargetMissingRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TZahl = Integer;'#10'  TA = class'#10'  public'#10'    procedure Lauf(A: Integer; B: Longint); virtual;'#10 +
    '  end;'#10'  TB = class(TA)'#10'  public'#10'    procedure Lauf(A: TZahl; B: Integer); override;'#10'  end;'#10 +
    'implementation'#10'end.');
  // Generischer Vorfahr: T steht für das Typargument.
  TRuleAssert.Silent(TOverrideTargetMissingRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TKunde = class'#10'  end;'#10'  TListe<T> = class'#10'  protected'#10 +
    '    procedure Melden(const Item: T); virtual;'#10'  end;'#10'  TKunden = class(TListe<TKunde>)'#10 +
    '  protected'#10'    procedure Melden(const Item: TKunde); override;'#10'  end;'#10'implementation'#10'end.');
  // Überladungen: das passende override zählt; class-Methoden prüft die Regel nicht.
  TRuleAssert.Silent(TOverrideTargetMissingRule.Create, 'unit U;'#10'interface'#10'type'#10'  TA = class'#10 +
    '  public'#10'    procedure Lesen(A: Integer); overload; virtual;'#10 +
    '    procedure Lesen(const S: string); overload; virtual;'#10'  end;'#10'  TB = class(TA)'#10'  public'#10 +
    '    procedure Lesen(const S: string); overload; override;'#10 +
    '    class function NewInstance: TObject; override;'#10'  end;'#10'implementation'#10'end.');
end;

procedure TInheritanceRulesTests.OverrideTargetFromIndex;
const
  BasisSource = 'unit Basis;'#10'interface'#10'type'#10'  TBasis = class'#10'  private'#10 +
    '    procedure Geheim; virtual;'#10'  protected'#10'    procedure Laden(const Datei: string); virtual;'#10 +
    '  end;'#10'  TFest = class sealed(TBasis)'#10'  end;'#10'implementation'#10'end.';
var
  Index: ISymbolIndex;
  Findings: TArray<TRuleFinding>;
begin
  Index := IndexWith([BasisSource]);
  Findings := Run(TOverrideTargetMissingRule.Create, 'unit U;'#10'interface'#10'uses Basis;'#10'type'#10 +
    '  TA = class(TBasis)'#10'  protected'#10'    procedure Laden(const Datei: string); override;'#10 +
    '    procedure Geheim; override;'#10'  end;'#10'  TB = class(TFest)'#10'  end;'#10'implementation'#10'end.',
    Index);
  Assert.AreEqual(2, Integer(Length(Findings)));
  // private aus einer anderen Unit sieht der Nachfahre nicht.
  Assert.AreEqual('Kein Vorfahr von TA hat ein virtuelles Geheim (wie E2137).', Findings[0].Message);
  Assert.AreEqual('TFest ist sealed; davon lässt sich nicht ableiten (wie E2353).', Findings[1].Message);
  // Ein gleichnamiger Typ aus dem implementation-Teil einer anderen Unit ist nicht der Vorfahr: Der echte TFrame
  // (Vcl.Forms) fehlt im Index, also keine Aussage.
  Index := IndexWith(['unit Fremd;'#10'interface'#10'implementation'#10'type'#10'  TFrame = class'#10'  end;'#10 +
    'end.']);
  Findings := Run(TOverrideTargetMissingRule.Create, 'unit U;'#10'interface'#10'uses Vcl.Forms;'#10'type'#10 +
    '  TMeinFrame = class(TFrame)'#10'  protected'#10'    procedure CreateWnd; override;'#10'  end;'#10 +
    'implementation'#10'end.', Index);
  Assert.AreEqual(0, Integer(Length(Findings)));
end;

procedure TInheritanceRulesTests.OverrideTargetGenericAndPlainNamesakes;
var
  mIndex: ISymbolIndex;
  mFindings: TArray<TRuleFinding>;
begin
  // Horse: Der generische Kanal überschreibt die Methoden des nicht generischen gleichen Namens.
  TRuleAssert.Silent(TOverrideTargetMissingRule.Create, 'unit Kanal;'#10'interface'#10'type'#10 +
    '  TKanal = class'#10'  public'#10'    procedure Schliessen; virtual; abstract;'#10'  end;'#10 +
    '  TKanal<T: class> = class(TKanal)'#10'  public'#10'    procedure Schliessen; override;'#10'  end;'#10 +
    'implementation'#10'procedure TKanal<T>.Schliessen;'#10'begin'#10'end;'#10'end.');
  // Gegenprobe: Was der nicht generische Vorfahr nicht hat, fehlt weiterhin.
  mFindings := TRuleAssert.Findings(TOverrideTargetMissingRule.Create, 'unit Kanal;'#10'interface'#10'type'#10 +
    '  TKanal = class'#10'  public'#10'    procedure Schliessen; virtual; abstract;'#10'  end;'#10 +
    '  TKanal<T: class> = class(TKanal)'#10'  public'#10'    procedure Oeffnen; override;'#10'  end;'#10 +
    'implementation'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Kein Vorfahr von TKanal hat ein virtuelles Oeffnen (wie E2137).', mFindings[0].Message);
  // Delphi-Mocks: TObjectProxy<T> = class(TProxy<T>), daneben ein nicht generisches TProxy in einer anderen Unit.
  mIndex := IndexWith(['unit Proxy.Plain;'#10'interface'#10'type'#10'  TProxy = class'#10'  public'#10 +
    '    procedure Pruefen; virtual;'#10'  end;'#10'implementation'#10'end.', 'unit Proxy;'#10'interface'#10 +
    'type'#10'  TProxy<T> = class'#10'  protected'#10'    function Proxy: T; virtual;'#10'  end;'#10 +
    'implementation'#10'end.']);
  mFindings := Run(TOverrideTargetMissingRule.Create, 'unit ObjectProxy;'#10'interface'#10'uses Proxy.Plain, Proxy;'#10 +
    'type'#10'  TObjectProxy<T> = class(TProxy<T>)'#10'  protected'#10'    function Proxy: T; override;'#10 +
    '    procedure Pruefen; override;'#10'  end;'#10'implementation'#10'end.', mIndex);
  // Pruefen gehört dem nicht generischen TProxy, nicht dem Vorfahren.
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Kein Vorfahr von TObjectProxy hat ein virtuelles Pruefen (wie E2137).', mFindings[0].Message);
end;

procedure TInheritanceRulesTests.OverrideTargetOptions;
var
  Source: string;
begin
  Source := Dienste('', '    procedure Speichern; override;', '');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TOverrideTargetMissingRule.Create, Source, '', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOverrideTargetMissingRule.Create, Source,
    '{"rules": {"override-target-missing": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOverrideTargetMissingRule.Create, Source,
    '{"rules": {"group:compiler": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOverrideTargetMissingRule.Create, Source,
    '{"rules": {"override-target-missing": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

function Formen(const AKreis, ABody: string): string;
begin
  Result := 'unit Formen;'#10'interface'#10'type'#10'  TForm = class'#10'  public'#10 +
    '    function Flaeche: Double; virtual; abstract;'#10'    function Name: string; virtual;'#10'  end;'#10 +
    '  TKreis = class(TForm)'#10'  public'#10 + AKreis + '  end;'#10'implementation'#10 +
    'function TForm.Name: string;'#10'begin'#10'  Result := '''';'#10'end;'#10 +
    'procedure Rechnen;'#10'var'#10'  Form: TForm;'#10'  Gesamt: Double;'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

procedure TInheritanceRulesTests.AbstractInstantiatedIssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TAbstractClassInstantiatedRule.Create, Formen('',
    '  Form := TForm.Create;'#10'  Gesamt := Gesamt + Form.Flaeche;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TForm hat die abstrakte Methode Flaeche; der Aufruf löst EAbstractError aus (wie W1020).',
    Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(21, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(10, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(22, Findings[0].Range.EndPos.Character);
  // Die korrigierte Form: eine konkrete Unterklasse.
  TRuleAssert.Silent(TAbstractClassInstantiatedRule.Create, Formen(
    '    function Flaeche: Double; override;'#10, '  Form := TKreis.Create;'#10));
end;

procedure TInheritanceRulesTests.AbstractInstantiatedInheritedWithFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TAbstractClassInstantiatedRule.Create, Formen(
    '    function Name: string; override;'#10, '  Form := TKreis.Create;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TKreis hat die abstrakte Methode TForm.Flaeche; der Aufruf löst EAbstractError aus (wie W1020).',
    Findings[0].Message);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Flaeche in TKreis überschreiben', Findings[0].Fixes[0].Title);
  Assert.IsTrue(Pos('function Flaeche: Double; override;', Findings[0].Fixes[0].Edits[0].NewText) > 0,
    Findings[0].Fixes[0].Edits[0].NewText);
  // Mehrere offene Methoden in einer Meldung.
  Findings := TRuleAssert.Findings(TAbstractClassInstantiatedRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TA = class'#10'  public'#10'    procedure Eins; virtual; abstract;'#10 +
    '    procedure Zwei(X: Integer); virtual; abstract;'#10'  end;'#10'implementation'#10 +
    'procedure P;'#10'begin'#10'  TA.Create.Free;'#10'end;'#10'end.');
  Assert.AreEqual('TA hat die abstrakten Methoden Eins, Zwei; ihr Aufruf löst EAbstractError aus (wie W1020).',
    Findings[0].Message);
end;

procedure TInheritanceRulesTests.AbstractInstantiatedAbstractClassAndIndex;
const
  ListenSource = 'unit Listen;'#10'interface'#10'type'#10'  TListe = class'#10'  protected'#10 +
    '    function Get(Index: Integer): string; virtual; abstract;'#10'  end;'#10 +
    '  TFeste = class(TListe)'#10'  protected'#10'    function Get(Index: Integer): string; override;'#10 +
    '  end;'#10'implementation'#10'function TFeste.Get(Index: Integer): string;'#10'begin'#10'end;'#10'end.';
var
  Findings: TArray<TRuleFinding>;
begin
  // "class abstract" ohne abstrakte Methoden übersetzt dcc still (#1383, Cm.E2402); mit offener Methode W1020.
  TRuleAssert.Silent(TAbstractClassInstantiatedRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TBasis = class abstract'#10'  end;'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  TBasis.Create.Free;'#10'end;'#10'end.');
  Findings := TRuleAssert.Findings(TAbstractClassInstantiatedRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TBasis = class abstract'#10'  public'#10'    procedure Eins; virtual; abstract;'#10'  end;'#10 +
    'implementation'#10'procedure P;'#10'begin'#10'  TBasis.Create.Free;'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TBasis hat die abstrakte Methode Eins; der Aufruf löst EAbstractError aus (wie W1020).',
    Findings[0].Message);
  // Klassen aus dem Index; geerbte Methoden fremder Units ohne Korrektur.
  Findings := Run(TAbstractClassInstantiatedRule.Create, 'unit U;'#10'interface'#10'uses Listen;'#10 +
    'implementation'#10'procedure P;'#10'begin'#10'  TListe.Create.Free;'#10'  TFeste.Create.Free;'#10'end;'#10 +
    'end.', IndexWith([ListenSource]));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TListe hat die abstrakte Methode Get; der Aufruf löst EAbstractError aus (wie W1020).',
    Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TInheritanceRulesTests.AbstractInstantiatedSilentCases;
begin
  // Konstruktor-Rumpf, inherited, unbekannte Klasse, Klassenreferenz.
  TRuleAssert.Silent(TAbstractClassInstantiatedRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TA = class'#10'  public'#10'    constructor Create;'#10'    procedure Eins; virtual; abstract;'#10 +
    '  end;'#10'  TAKlasse = class of TA;'#10'implementation'#10'constructor TA.Create;'#10'begin'#10 +
    '  inherited Create;'#10'end;'#10'procedure P(K: TAKlasse);'#10'begin'#10'  K.Create.Free;'#10 +
    '  TUnbekannt.Create.Free;'#10'end;'#10'end.');
  // Überschrieben in einer Zwischenklasse; Überladung mit gleicher Parameterzahl.
  TRuleAssert.Silent(TAbstractClassInstantiatedRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TA = class'#10'  public'#10'    procedure Eins(X: Integer); virtual; abstract;'#10'  end;'#10 +
    '  TB = class(TA)'#10'  public'#10'    procedure Eins(X: Integer); override;'#10'  end;'#10 +
    '  TC = class(TB)'#10'  end;'#10'implementation'#10'procedure TB.Eins(X: Integer);'#10'begin'#10'end;'#10 +
    'procedure P;'#10'begin'#10'  TC.Create.Free;'#10'end;'#10'end.');
end;

procedure TInheritanceRulesTests.AbstractInstantiatedOptions;
var
  Source: string;
begin
  Source := Formen('', '  Form := TForm.Create;'#10);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TAbstractClassInstantiatedRule.Create, Source, '',
    'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TAbstractClassInstantiatedRule.Create, Source,
    '{"rules": {"abstract-class-instantiated": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TAbstractClassInstantiatedRule.Create, Source,
    '{"rules": {"group:compiler": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TAbstractClassInstantiatedRule.Create, Source,
    '{"rules": {"abstract-class-instantiated": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

/// <summary>TForm mit abstraktem Zeichnen, TKreis überschreibt es; ABody ist der Rumpf von TKreis.Zeichnen.
/// </summary>
function Kreise(const ABody: string): string;
begin
  Result := 'unit Formen;'#10'interface'#10'type'#10'  TForm = class'#10'  public'#10 +
    '    procedure Zeichnen(C: Integer); virtual; abstract;'#10'    function Flaeche: Double; virtual;'#10 +
    '  end;'#10'  TKreis = class(TForm)'#10'  public'#10'    procedure Zeichnen(C: Integer); override;'#10 +
    '    function Flaeche: Double; override;'#10'  end;'#10'implementation'#10 +
    'function TForm.Flaeche: Double;'#10'begin'#10'  Result := 0;'#10'end;'#10 +
    'procedure TKreis.Zeichnen(C: Integer);'#10'begin'#10 + ABody + 'end;'#10 +
    'function TKreis.Flaeche: Double;'#10'begin'#10'  Result := inherited Flaeche;'#10'end;'#10'end.';
end;

/// <summary>Offset (ab 1) der Position APosition in AText mit #10 als Zeilenende.</summary>
function OffsetOf(const AText: string; const APosition: TTextPosition): Integer;
var
  Line: Integer;
begin
  Result := 1;
  for Line := 1 to APosition.Line do
    Result := Pos(#10, AText, Result) + 1;
  Inc(Result, APosition.Character);
end;

procedure TInheritanceRulesTests.InheritedAbstractIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
  Edit: TRuleEdit;
begin
  Source := Kreise('  inherited Zeichnen(C);'#10'  Inc(C);'#10);
  Findings := TRuleAssert.Findings(TInheritedAbstractCallRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TForm.Zeichnen ist abstrakt; der Aufruf über inherited löst zur Laufzeit EAbstractError aus.',
    Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(20, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Aufruf entfernen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)));
  Edit := Findings[0].Fixes[0].Edits[0];
  Fixed := Copy(Source, 1, OffsetOf(Source, Edit.Range.StartPos) - 1) + Edit.NewText +
    Copy(Source, OffsetOf(Source, Edit.Range.EndPos), MaxInt);
  Assert.AreEqual(Kreise('  Inc(C);'#10), Fixed);
  TRuleAssert.Silent(TInheritedAbstractCallRule.Create, Fixed);
  // Ohne Klammern ebenso.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TInheritedAbstractCallRule.Create,
    Kreise('  inherited Zeichnen;'#10)))));
end;

procedure TInheritanceRulesTests.InheritedAbstractExpressionAndIndex;
const
  BasisSource = 'unit Basis;'#10'interface'#10'type'#10'  TRechner = class'#10'  protected'#10 +
    '    function Berechnen(X: Integer): Integer; virtual; abstract;'#10'  end;'#10'implementation'#10'end.';
var
  Findings: TArray<TRuleFinding>;
begin
  // Als Ausdruck und aus dem Index: gemeldet, aber ohne Korrektur.
  Findings := TRuleAssert.IndexFindings(TInheritedAbstractCallRule.Create, 'unit U;'#10'interface'#10 +
    'uses Basis;'#10'type'#10'  TSumme = class(TRechner)'#10'  protected'#10 +
    '    function Berechnen(X: Integer): Integer; override;'#10'  end;'#10'implementation'#10 +
    'function TSumme.Berechnen(X: Integer): Integer;'#10'begin'#10'  Result := inherited Berechnen(X) + 1;'#10 +
    'end;'#10'end.', IndexWith([BasisSource]), '', 'U.pas');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TRechner.Berechnen ist abstrakt; der Aufruf über inherited löst zur Laufzeit EAbstractError aus.',
    Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Im Zweig einer if-Anweisung: Entfernen ließe ein leeres then zurück, also keine Korrektur.
  Findings := TRuleAssert.Findings(TInheritedAbstractCallRule.Create,
    Kreise('  if C > 0 then'#10'    inherited Zeichnen(C);'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TInheritanceRulesTests.InheritedAbstractSilentCases;
begin
  // Bloßes inherited, konkrete Methode des Vorfahren (Flaeche), unbekannter Vorfahr.
  TRuleAssert.Silent(TInheritedAbstractCallRule.Create, Kreise('  inherited;'#10));
  TRuleAssert.Silent(TInheritedAbstractCallRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TFoo = class(TUnbekannt)'#10'  public'#10'    procedure Lauf; override;'#10'  end;'#10'implementation'#10 +
    'procedure TFoo.Lauf;'#10'begin'#10'  inherited Lauf;'#10'end;'#10'end.');
  // Eine Zwischenklasse überschreibt die abstrakte Methode.
  TRuleAssert.Silent(TInheritedAbstractCallRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TA = class'#10'  public'#10'    procedure Eins; virtual; abstract;'#10'  end;'#10 +
    '  TB = class(TA)'#10'  public'#10'    procedure Eins; override;'#10'  end;'#10 +
    '  TC = class(TB)'#10'  public'#10'    procedure Eins; override;'#10'  end;'#10'implementation'#10 +
    'procedure TB.Eins;'#10'begin'#10'end;'#10'procedure TC.Eins;'#10'begin'#10'  inherited Eins;'#10'end;'#10 +
    'end.');
  // Überladung: die passende ist konkret.
  TRuleAssert.Silent(TInheritedAbstractCallRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TA = class'#10'  public'#10'    procedure Eins; overload; virtual; abstract;'#10 +
    '    procedure Eins(X: Integer); overload; virtual;'#10'  end;'#10 +
    '  TB = class(TA)'#10'  public'#10'    procedure Eins(X: Integer); override;'#10'  end;'#10'implementation'#10 +
    'procedure TA.Eins(X: Integer);'#10'begin'#10'end;'#10'procedure TB.Eins(X: Integer);'#10'begin'#10 +
    '  inherited Eins(X);'#10'end;'#10'end.');
end;

procedure TInheritanceRulesTests.InheritedAbstractOptions;
var
  Source: string;
begin
  Source := Kreise('  inherited Zeichnen(C);'#10);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TInheritedAbstractCallRule.Create, Source, '',
    'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInheritedAbstractCallRule.Create, Source,
    '{"rules": {"inherited-abstract-call": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInheritedAbstractCallRule.Create, Source,
    '{"rules": {"group:compiler": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInheritedAbstractCallRule.Create, Source,
    '{"rules": {"inherited-abstract-call": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

/// <summary>Das Beispiel aus #1032: TPlugin mit statischem Create, TSpezial deklariert ein eigenes; ADirektiven
/// steht hinter beiden Konstruktoren, ACall im Rumpf von Neu.</summary>
function Plugins(const ABasis, ASpezial, ACall: string): string;
begin
  Result := 'unit Plugins;'#10'interface'#10'type'#10'  TPluginKlasse = class of TPlugin;'#10 +
    '  TPlugin = class'#10'  public'#10'    constructor Create;' + ABasis + #10'  end;'#10 +
    '  TSpezial = class(TPlugin)'#10'  public'#10'    constructor Create;' + ASpezial + #10'  end;'#10 +
    'function Neu(Klasse: TPluginKlasse): TPlugin;'#10'implementation'#10 +
    'constructor TPlugin.Create;'#10'begin'#10'end;'#10'constructor TSpezial.Create;'#10'begin'#10'end;'#10 +
    'function Neu(Klasse: TPluginKlasse): TPlugin;'#10'begin'#10 + ACall + 'end;'#10'end.';
end;

/// <summary>AText mit allen Änderungen von AFix, hinterste zuerst.</summary>
function Applied(const AText: string; const AFix: TRuleFix): string;
var
  Index, Later: Integer;
  Edits: TArray<TRuleEdit>;
  Edit: TRuleEdit;
begin
  Edits := Copy(AFix.Edits);
  for Index := 0 to High(Edits) - 1 do
    for Later := Index + 1 to High(Edits) do
      if OffsetOf(AText, Edits[Later].Range.StartPos) > OffsetOf(AText, Edits[Index].Range.StartPos) then
      begin
        Edit := Edits[Index];
        Edits[Index] := Edits[Later];
        Edits[Later] := Edit;
      end;
  Result := AText;
  for Edit in Edits do
    Result := Copy(Result, 1, OffsetOf(Result, Edit.Range.StartPos) - 1) + Edit.NewText +
      Copy(Result, OffsetOf(Result, Edit.Range.EndPos), MaxInt);
end;

procedure TInheritanceRulesTests.ClassRefConstructorIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Plugins('', '', '  Result := Klasse.Create;'#10);
  Findings := TRuleAssert.Findings(TClassReferenceNonvirtualConstructorRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TPlugin.Create ist nicht virtuell; über die Klassenreferenz läuft immer TPlugin.Create ' +
    '(wie E2391).', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(22, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(12, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(22, Findings[0].Range.EndPos.Line);
  Assert.AreEqual(25, Findings[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('virtual an TPlugin.Create, override in den Nachfahren', Findings[0].Fixes[0].Title);
  Fixed := Applied(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(Plugins(' virtual;', ' override;', '  Result := Klasse.Create;'#10), Fixed);
  TRuleAssert.Silent(TClassReferenceNonvirtualConstructorRule.Create, Fixed);
  // Mit Argumenten, über ein Feld und als Anweisung ebenso.
  Findings := TRuleAssert.Findings(TClassReferenceNonvirtualConstructorRule.Create, 'unit U;'#10'interface'#10 +
    'type'#10'  TTeil = class'#10'  public'#10'    constructor Create(ANummer: Integer);'#10'  end;'#10 +
    '  TTeilKlasse = class of TTeil;'#10'  TFabrik = class'#10'  private'#10'    FKlasse: TTeilKlasse;'#10 +
    '  public'#10'    procedure Baue;'#10'  end;'#10'implementation'#10 +
    'constructor TTeil.Create(ANummer: Integer);'#10'begin'#10'end;'#10'procedure TFabrik.Baue;'#10'begin'#10 +
    '  FKlasse.Create(1).Free;'#10'  Self.FKlasse.Create(2);'#10'end;'#10'end.');
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('virtual an TTeil.Create', Findings[0].Fixes[0].Title);
end;

procedure TInheritanceRulesTests.ClassRefConstructorFromIndex;
const
  BasisSource = 'unit Basis;'#10'interface'#10'type'#10'  TDienst = class'#10'  public'#10 +
    '    constructor Create;'#10'  end;'#10'  TDienstKlasse = class of TDienst;'#10 +
    '  TBauteil = class'#10'  public'#10'    constructor Create(AOwner: TObject); virtual;'#10'  end;'#10 +
    '  TBauteilKlasse = class of TBauteil;'#10'function Klasse: TDienstKlasse;'#10'implementation'#10 +
    'constructor TDienst.Create;'#10'begin'#10'end;'#10'constructor TBauteil.Create(AOwner: TObject);'#10 +
    'begin'#10'end;'#10'function Klasse: TDienstKlasse;'#10'begin'#10'  Result := TDienst;'#10'end;'#10'end.';
var
  Findings: TArray<TRuleFinding>;
begin
  // Klassenreferenz und Konstruktor aus einer anderen Unit: gemeldet, ohne Korrektur; auch über eine Funktion.
  Findings := TRuleAssert.IndexFindings(TClassReferenceNonvirtualConstructorRule.Create, 'unit U;'#10 +
    'interface'#10'uses Basis;'#10'procedure Lauf(K: TDienstKlasse; B: TBauteilKlasse);'#10'implementation'#10 +
    'procedure Lauf(K: TDienstKlasse; B: TBauteilKlasse);'#10'begin'#10'  K.Create.Free;'#10 +
    '  B.Create(nil).Free;'#10'  Klasse.Create.Free;'#10'end;'#10'end.', IndexWith([BasisSource]), '', 'U.pas');
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('TDienst.Create ist nicht virtuell; über die Klassenreferenz läuft immer TDienst.Create ' +
    '(wie E2391).', Findings[0].Message);
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual(9, Findings[1].Range.StartPos.Line);
end;

procedure TInheritanceRulesTests.ClassRefConstructorSilentCases;
begin
  // Virtueller Konstruktor mit override in den Nachfahren, Create direkt an der Klasse.
  TRuleAssert.Silent(TClassReferenceNonvirtualConstructorRule.Create, Plugins(' virtual;', ' override;',
    '  Result := Klasse.Create;'#10'  TPlugin.Create.Free;'#10'  TSpezial.Create.Free;'#10));
  // Create auf einer Instanz (constructor-on-instance) und eine passende virtuelle Überladung.
  TRuleAssert.Silent(TClassReferenceNonvirtualConstructorRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TA = class'#10'  public'#10'    constructor Create; overload; virtual;'#10 +
    '    constructor Create(X: Integer); overload;'#10'  end;'#10'  TAKlasse = class of TA;'#10 +
    'implementation'#10'constructor TA.Create;'#10'begin'#10'end;'#10'constructor TA.Create(X: Integer);'#10 +
    'begin'#10'end;'#10'procedure Lauf(K: TAKlasse; A: TA);'#10'begin'#10'  K.Create.Free;'#10 +
    '  A.Create;'#10'end;'#10'end.');
  // Unbekannter Vorfahr ohne eigenes Create, unbekannte Klassenreferenz.
  TRuleAssert.Silent(TClassReferenceNonvirtualConstructorRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TB = class(TUnbekannt)'#10'  end;'#10'  TBKlasse = class of TB;'#10'implementation'#10 +
    'procedure Lauf(K: TBKlasse; F: TFremdKlasse);'#10'begin'#10'  K.Create.Free;'#10'  F.Create.Free;'#10 +
    'end;'#10'end.');
  // Die Variable ist nur in einem Zweig der bedingten Übersetzung eine Klassenreferenz.
  TRuleAssert.Silent(TClassReferenceNonvirtualConstructorRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TC = class'#10'  public'#10'    constructor Create;'#10'  end;'#10'  TCKlasse = class of TC;'#10 +
    'implementation'#10'constructor TC.Create;'#10'begin'#10'end;'#10'var'#10'{$IFDEF NEU}'#10 +
    '  K: TCKlasse;'#10'{$ELSE}'#10'  K: TC;'#10'{$ENDIF}'#10'procedure Lauf;'#10'begin'#10 +
    '  K.Create;'#10'end;'#10'end.');
end;

procedure TInheritanceRulesTests.ClassRefConstructorOptions;
var
  Source: string;
begin
  Source := Plugins('', '', '  Result := Klasse.Create;'#10);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TClassReferenceNonvirtualConstructorRule.Create, Source,
    '', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TClassReferenceNonvirtualConstructorRule.Create, Source,
    '{"rules": {"class-reference-nonvirtual-constructor": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TClassReferenceNonvirtualConstructorRule.Create, Source,
    '{"rules": {"group:compiler": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TClassReferenceNonvirtualConstructorRule.Create, Source,
    '{"rules": {"class-reference-nonvirtual-constructor": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

/// <summary>TFoo erbt Lauf und Wert von TBasis; AMembers steht im protected-Abschnitt von TFoo, AImplementation
/// hinter den Rümpfen von TBasis. Beide enden mit einem Zeilenumbruch.</summary>
function Erben(const AMembers, AImplementation: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10'  protected'#10 +
    '    procedure Lauf(A, B: Integer); virtual;'#10'    function Wert(X: Integer): Integer; virtual;'#10 +
    '  end;'#10'  TFoo = class(TBasis)'#10'  protected'#10 + AMembers + '  end;'#10'implementation'#10 +
    'procedure TBasis.Lauf(A, B: Integer);'#10'begin'#10'end;'#10#10 +
    'function TBasis.Wert(X: Integer): Integer;'#10'begin'#10'  Result := X;'#10'end;'#10#10 + AImplementation +
    'end.';
end;

const
  LaufDecl = '    procedure Lauf(A, B: Integer); override;'#10;
  WertDecl = '    function Wert(X: Integer): Integer; override;'#10;

procedure TInheritanceRulesTests.OverrideOnlyInheritedIssueExample;
const
  FormsSource = 'unit Vcl.Forms;'#10'interface'#10'type'#10'  TForm = class'#10'  protected'#10 +
    '    procedure Loaded; virtual;'#10'  end;'#10'implementation'#10'end.';

  function Kunden(const AMembers, AImplementation: string): string;
  begin
    Result := 'unit Kunden;'#10'interface'#10'uses Vcl.Forms;'#10'type'#10'  TKundenForm = class(TForm)'#10 +
      '  protected'#10 + AMembers + '    procedure Zeigen;'#10'  end;'#10'implementation'#10 + AImplementation +
      'procedure TKundenForm.Zeigen;'#10'begin'#10'end;'#10'end.';
  end;

var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
  mIndex: ISymbolIndex;
begin
  mIndex := IndexWith([FormsSource]);
  mSource := Kunden('    /// <summary>Liest nach.</summary>'#10'    procedure Loaded; override;'#10,
    '/// <summary>Liest nach.</summary>'#10'procedure TKundenForm.Loaded;'#10'begin'#10'  inherited Loaded;'#10'end;'#10#10);
  mFindings := TRuleAssert.IndexFindings(TOverrideOnlyInheritedRule.Create, mSource, mIndex, '', 'Kunden.pas');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('TKundenForm.Loaded ruft nur inherited auf und kann entfallen.', mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  // Gemeldet am Namen in der Implementierung.
  Assert.AreEqual(12, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(22, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(28, mFindings[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Methode entfernen', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(2, Integer(Length(mFindings[0].Fixes[0].Edits)));
  // Deklaration und Rumpf samt XMLDoc und Leerzeile verschwinden.
  mFixed := Applied(mSource, mFindings[0].Fixes[0]);
  Assert.AreEqual(Kunden('', ''), mFixed);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TOverrideOnlyInheritedRule.Create, mFixed, mIndex, '',
    'Kunden.pas'))));
end;

procedure TInheritanceRulesTests.OverrideOnlyInheritedForms;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  // inherited Name(A, B) mit unveränderten Parametern und bloßes inherited.
  mSource := Erben(LaufDecl, 'procedure TFoo.Lauf(A, B: Integer);'#10'begin'#10'  inherited Lauf(A, B);'#10'end;'#10);
  mFindings := TRuleAssert.Findings(TOverrideOnlyInheritedRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('TFoo.Lauf ruft nur inherited auf und kann entfallen.', mFindings[0].Message);
  Assert.AreEqual(Erben('', ''), Applied(mSource, mFindings[0].Fixes[0]));
  TRuleAssert.Reports(TOverrideOnlyInheritedRule.Create,
    Erben(LaufDecl, 'procedure TFoo.Lauf(A, B: Integer);'#10'begin'#10'  inherited;'#10'end;'#10));
  TRuleAssert.Reports(TOverrideOnlyInheritedRule.Create,
    Erben(LaufDecl, 'procedure TFoo.Lauf(A, B: Integer);'#10'begin'#10'  inherited Lauf(A, B)'#10'end;'#10));
  // Funktion: nur Result := inherited Name(…).
  TRuleAssert.Reports(TOverrideOnlyInheritedRule.Create,
    Erben(WertDecl, 'function TFoo.Wert(X: Integer): Integer;'#10'begin'#10'  Result := inherited Wert(X);'#10 +
    'end;'#10));
  // Beide in einer Unit, andere Schreibweise des Namens.
  TRuleAssert.Reports(TOverrideOnlyInheritedRule.Create, Erben(LaufDecl + WertDecl,
    'procedure TFoo.Lauf(A, B: Integer);'#10'begin'#10'  inherited lauf(a, b);'#10'end;'#10#10 +
    'function TFoo.Wert(X: Integer): Integer;'#10'begin'#10'  Result := inherited Wert(X);'#10'end;'#10), 2);
end;

procedure TInheritanceRulesTests.OverrideOnlyInheritedSilentCases;

  procedure Lauf(const AMembers, ABody: string);
  begin
    TRuleAssert.Silent(TOverrideOnlyInheritedRule.Create,
      Erben(AMembers, 'procedure TFoo.Lauf(A, B: Integer);'#10 + ABody + 'end;'#10));
  end;

begin
  // Geänderte oder vertauschte Parameter, weitere Anweisungen, lokale Variable, Kommentar im Rumpf.
  Lauf(LaufDecl, 'begin'#10'  inherited Lauf(B, A);'#10);
  Lauf(LaufDecl, 'begin'#10'  inherited Lauf(A, 1);'#10);
  Lauf(LaufDecl, 'begin'#10'  inherited;'#10'  Inc(A);'#10);
  Lauf(LaufDecl, 'var'#10'  C: Integer;'#10'begin'#10'  inherited;'#10);
  Lauf(LaufDecl, 'begin'#10'  // Absicht: Haken für später'#10'  inherited;'#10);
  Lauf(LaufDecl, 'begin'#10'  inherited; {$IFDEF X} Inc(A); {$ENDIF}'#10);
  Lauf(LaufDecl, 'begin'#10'end;'#10'procedure TFoo.Weiter;'#10'begin'#10);
  // Sichtbarkeit geändert (protected -> public), Attribut, final, deprecated.
  Lauf('  public'#10 + LaufDecl, 'begin'#10'  inherited;'#10);
  Lauf('    [Weak]'#10 + LaufDecl, 'begin'#10'  inherited;'#10);
  Lauf('    procedure Lauf(A, B: Integer); override; final;'#10, 'begin'#10'  inherited;'#10);
  Lauf('    procedure Lauf(A, B: Integer); override; deprecated;'#10, 'begin'#10'  inherited;'#10);
  // Ohne override (verdeckt) und neue virtuelle Methode.
  Lauf('    procedure Lauf(A, B: Integer); reintroduce;'#10, 'begin'#10'  inherited;'#10);
  // Funktion mit bloßem inherited oder ohne Ergebnis: Das Ergebnis bleibt undefiniert, das ist kein Fall hier.
  TRuleAssert.Silent(TOverrideOnlyInheritedRule.Create, Erben(WertDecl,
    'function TFoo.Wert(X: Integer): Integer;'#10'begin'#10'  inherited;'#10'end;'#10));
  TRuleAssert.Silent(TOverrideOnlyInheritedRule.Create, Erben(WertDecl,
    'function TFoo.Wert(X: Integer): Integer;'#10'begin'#10'  Result := inherited Wert(X) + 1;'#10'end;'#10));
  // Unbekannter Vorfahr: Sichtbarkeit nicht prüfbar.
  TRuleAssert.Silent(TOverrideOnlyInheritedRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TFoo = class(TUnbekannt)'#10'  protected'#10'    procedure Loaded; override;'#10'  end;'#10 +
    'implementation'#10'procedure TFoo.Loaded;'#10'begin'#10'  inherited;'#10'end;'#10'end.');
  // Standardwerte (andere Werte als der Vorfahr wären der Zweck).
  TRuleAssert.Silent(TOverrideOnlyInheritedRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TA = class'#10'  public'#10'    procedure P(X: Integer = 1); virtual;'#10'  end;'#10 +
    '  TB = class(TA)'#10'  public'#10'    procedure P(X: Integer = 2); override;'#10'  end;'#10 +
    'implementation'#10'procedure TA.P(X: Integer);'#10'begin'#10'end;'#10 +
    'procedure TB.P(X: Integer);'#10'begin'#10'  inherited P(X);'#10'end;'#10'end.');
end;

procedure TInheritanceRulesTests.OverrideOnlyInheritedObjectMethods;
const
  Source = 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'  public'#10 +
    '    destructor Destroy; override;'#10'    procedure AfterConstruction; override;'#10 +
    '  protected'#10'    function ToString: string; override;'#10'  end;'#10'implementation'#10 +
    'destructor TFoo.Destroy;'#10'begin'#10'  inherited;'#10'end;'#10 +
    'procedure TFoo.AfterConstruction;'#10'begin'#10'  inherited AfterConstruction;'#10'end;'#10 +
    'function TFoo.ToString: string;'#10'begin'#10'  Result := inherited ToString;'#10'end;'#10'end.';
var
  mFindings: TArray<TRuleFinding>;
begin
  // TObject steht nicht im Index: Seine virtuellen Methoden sind öffentlich. ToString wird protected, bleibt stumm.
  mFindings := TRuleAssert.Findings(TOverrideOnlyInheritedRule.Create, Source);
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual('TFoo.Destroy ruft nur inherited auf und kann entfallen.', mFindings[0].Message);
  Assert.AreEqual('TFoo.AfterConstruction ruft nur inherited auf und kann entfallen.', mFindings[1].Message);
end;

procedure TInheritanceRulesTests.OverrideOnlyInheritedOptions;
var
  mSource: string;
begin
  mSource := Erben(LaufDecl, 'procedure TFoo.Lauf(A, B: Integer);'#10'begin'#10'  inherited;'#10'end;'#10);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TOverrideOnlyInheritedRule.Create, mSource, '',
    'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOverrideOnlyInheritedRule.Create, mSource,
    '{"rules": {"override-only-inherited": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOverrideOnlyInheritedRule.Create, mSource,
    '{"rules": {"override-only-inherited": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

/// <summary>Das Beispiel aus #1144: TImport erbt von TBasis, AMembers steht im public-Abschnitt von TImport,
/// ABody ist der Rumpf von TImport.Vorbereiten.</summary>
function Importe(const ABasis, AMembers, ABody: string): string;
begin
  Result := 'unit Importe;'#10'interface'#10'type'#10'  TBasis = class' + ABasis + #10'  public'#10 +
    '    procedure Lauf; virtual;'#10'  end;'#10'  TImport = class(TBasis)'#10'  private'#10 +
    '    FZeilen: TStringList;'#10'  public'#10'    procedure Vorbereiten;'#10 + AMembers + '  end;'#10 +
    'implementation'#10'procedure TBasis.Lauf;'#10'begin'#10'end;'#10'procedure TImport.Vorbereiten;'#10 +
    'begin'#10 + ABody + 'end;'#10'end.';
end;

procedure TInheritanceRulesTests.InheritedWithoutAncestorIssueExample;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := Importe('', '', '  inherited;'#10'  FZeilen.Clear;'#10);
  mFindings := TRuleAssert.Findings(TInheritedWithoutAncestorRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Kein Vorfahr von TImport hat Vorbereiten: inherited tut nichts. Fehlt override?',
    mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual(19, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('inherited entfernen', mFindings[0].Fixes[0].Title);
  mFixed := Applied(mSource, mFindings[0].Fixes[0]);
  Assert.AreEqual(Importe('', '', '  FZeilen.Clear;'#10), mFixed);
  TRuleAssert.Silent(TInheritedWithoutAncestorRule.Create, mFixed);
  // In einem Zweig: gemeldet, ohne Korrektur (sonst bliebe ein leeres then).
  mFindings := TRuleAssert.Findings(TInheritedWithoutAncestorRule.Create,
    Importe('', '', '  if FZeilen <> nil then'#10'    inherited;'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  // Ohne Vorfahr (TObject) ebenso, zweimal im Rumpf zweimal.
  TRuleAssert.Reports(TInheritedWithoutAncestorRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TFoo = class'#10'  public'#10'    procedure Lauf;'#10'  end;'#10'implementation'#10 +
    'procedure TFoo.Lauf;'#10'begin'#10'  inherited;'#10'  inherited;'#10'end;'#10'end.', 2);
end;

procedure TInheritanceRulesTests.InheritedWithoutAncestorSilentCases;
begin
  // override, Message-Handler, Konstruktor, Destruktor, Klassenmethode.
  TRuleAssert.Silent(TInheritedWithoutAncestorRule.Create, Importe('',
    '    procedure Lauf; override;'#10'    procedure WMPaint(var Msg: TMessage); message WM_PAINT;'#10 +
    '    constructor Create;'#10'    destructor Destroy; override;'#10'    class procedure Melden;'#10,
    '  FZeilen.Clear;'#10'end;'#10'procedure TImport.Lauf;'#10'begin'#10'  inherited;'#10'end;'#10 +
    'procedure TImport.WMPaint(var Msg: TMessage);'#10'begin'#10'  inherited;'#10'end;'#10 +
    'constructor TImport.Create;'#10'begin'#10'  inherited;'#10'end;'#10 +
    'destructor TImport.Destroy;'#10'begin'#10'  inherited;'#10'end;'#10 +
    'class procedure TImport.Melden;'#10'begin'#10'  inherited;'#10));
  // Der Vorfahr hat eine gleichnamige Methode (auch statisch), benanntes inherited, anonyme Methode.
  TRuleAssert.Silent(TInheritedWithoutAncestorRule.Create, Importe(#10'  public'#10'    procedure Vorbereiten;', '',
    '  inherited;'#10'end;'#10'procedure TBasis.Vorbereiten;'#10'begin'#10));
  TRuleAssert.Silent(TInheritedWithoutAncestorRule.Create, Importe('', '', '  inherited Vorbereiten;'#10));
  // Unbekannter Vorfahr.
  TRuleAssert.Silent(TInheritedWithoutAncestorRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TFoo = class(TUnbekannt)'#10'  public'#10'    procedure Lauf;'#10'  end;'#10'implementation'#10 +
    'procedure TFoo.Lauf;'#10'begin'#10'  inherited;'#10'end;'#10'end.');
  // Methoden von TObject, wenn System nicht im Index steht.
  TRuleAssert.Silent(TInheritedWithoutAncestorRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TFoo = class'#10'  public'#10'    procedure AfterConstruction;'#10'    procedure Free;'#10'  end;'#10 +
    'implementation'#10'procedure TFoo.AfterConstruction;'#10'begin'#10'  inherited;'#10'end;'#10 +
    'procedure TFoo.Free;'#10'begin'#10'  inherited;'#10'end;'#10'end.');
end;

procedure TInheritanceRulesTests.InheritedWithoutAncestorFromIndex;
const
  MitSource = 'unit Basis;'#10'interface'#10'type'#10'  TBasis = class'#10'  public'#10 +
    '    procedure Vorbereiten;'#10'  end;'#10'implementation'#10'end.';
  OhneSource = 'unit Basis;'#10'interface'#10'type'#10'  TBasis = class'#10'  public'#10 +
    '    procedure Lauf;'#10'  end;'#10'implementation'#10'end.';
  Source = 'unit U;'#10'interface'#10'uses Basis;'#10'type'#10'  TImport = class(TBasis)'#10'  public'#10 +
    '    procedure Vorbereiten;'#10'  end;'#10'implementation'#10'procedure TImport.Vorbereiten;'#10'begin'#10 +
    '  inherited;'#10'end;'#10'end.';
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TInheritedWithoutAncestorRule.Create, Source,
    IndexWith([MitSource]), '', 'U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.IndexFindings(TInheritedWithoutAncestorRule.Create, Source,
    IndexWith([OhneSource]), '', 'U.pas'))));
end;

procedure TInheritanceRulesTests.InheritedWithoutAncestorOptions;
var
  mSource: string;
begin
  mSource := Importe('', '', '  inherited;'#10);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TInheritedWithoutAncestorRule.Create, mSource, '',
    'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInheritedWithoutAncestorRule.Create, mSource,
    '{"rules": {"inherited-without-ancestor": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInheritedWithoutAncestorRule.Create, mSource,
    '{"rules": {"inherited-without-ancestor": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TInheritanceRulesTests);

end.
