unit Atlas.Common.Rules.Builtin.Inheritance.Tests;

// Tests für die Vererbungsregeln (#125) und shadowed-name (#934).

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
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Configuration.Parser,
  Atlas.Tests.RuleAssert;

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

initialization
  TDUnitX.RegisterTestFixture(TInheritanceRulesTests);

end.
