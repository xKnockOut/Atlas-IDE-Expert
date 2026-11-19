unit Atlas.Common.Rules.Builtin.Inheritance.Constructors.Tests;

// Tests für virtual-call-in-constructor.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TVirtualCallInConstructorRuleTests = class
  public
    [Test]
    procedure IssueExampleReports;
    [Test]
    procedure NotOverriddenIsSilent;
    [Test]
    procedure GuardedOrEarlyFieldIsSilent;
    [Test]
    procedure ChainOverHelper;
    [Test]
    procedure DescendantInOtherUnit;
    [Test]
    procedure WithoutIndexOnlyBeforeInherited;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Tests.RuleAssert;

const
  cLowConfidence = '{"minConfidence": "low"}';
  cBaseDecl = 'unit U;'#10'interface'#10'uses'#10'  System.Classes;'#10'type'#10 +
    '  TAtlasDialog = class(TComponent)'#10'  protected'#10'    procedure BuildControls; virtual;'#10 +
    '    procedure ApplyTheme; virtual;'#10'    procedure Prepare;'#10'  public'#10 +
    '    constructor Create(AOwner: TComponent); override;'#10'  end;'#10;
  cDerivedDecl = '  TAtlasRuleDialog = class(TAtlasDialog)'#10'  private'#10'    FRules: TStrings;'#10 +
    '  protected'#10'    procedure BuildControls; override;'#10'  public'#10 +
    '    constructor Create(AOwner: TComponent; ARules: TStrings); reintroduce;'#10'  end;'#10;
  cDerivedCtor = '  inherited Create(AOwner);'#10'  FRules := ARules;'#10;
  cReadRules = '  FRules.Add(''Regel'');'#10;

// Basisklasse mit Konstruktorrumpf ABaseBody und Nachfahr in derselben Unit.
function DialogUnit(const ABaseBody, AOverrideBody, ADerivedCtor: string): string;
begin
  Result := cBaseDecl + cDerivedDecl + 'implementation'#10 +
    'constructor TAtlasDialog.Create(AOwner: TComponent);'#10'begin'#10 + ABaseBody + 'end;'#10 +
    'procedure TAtlasDialog.Prepare;'#10'begin'#10'  BuildControls;'#10'end;'#10 +
    'procedure TAtlasRuleDialog.BuildControls;'#10'begin'#10 + AOverrideBody + 'end;'#10 +
    'constructor TAtlasRuleDialog.Create(AOwner: TComponent; ARules: TStrings);'#10'begin'#10 + ADerivedCtor +
    'end;'#10'end.';
end;

procedure TVirtualCallInConstructorRuleTests.IssueExampleReports;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TVirtualCallInConstructorRule.Create, DialogUnit('  inherited Create(AOwner);'#10 +
    '  BuildControls;'#10, cReadRules, cDerivedCtor));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('virtual-call-in-constructor', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  Assert.AreEqual('BuildControls ist virtuell; TAtlasRuleDialog.BuildControls liest FRules, das erst nach inherited ' +
    'Create gesetzt wird.', mFindings[0].Message);
  Assert.AreEqual(25, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(15, mFindings[0].Range.EndPos.Character);
  // Die Code-Aktion springt zur Überschreibung.
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.IsTrue(mFindings[0].Fixes[0].HasJump);
  Assert.AreEqual('Zur Überschreibung TAtlasRuleDialog.BuildControls springen', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(31, mFindings[0].Fixes[0].JumpTo.Line);
  // Self.BuildControls und ein Aufruf in einem Ausdruck zählen ebenso.
  TRuleAssert.Reports(TVirtualCallInConstructorRule.Create, DialogUnit('  inherited Create(AOwner);'#10 +
    '  Self.BuildControls;'#10, cReadRules, cDerivedCtor), 1);
end;

procedure TVirtualCallInConstructorRuleTests.NotOverriddenIsSilent;
begin
  // ApplyTheme ist virtuell, aber kein Nachfahr überschreibt sie.
  TRuleAssert.Silent(TVirtualCallInConstructorRule.Create, DialogUnit('  inherited Create(AOwner);'#10 +
    '  ApplyTheme;'#10, cReadRules, cDerivedCtor));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TVirtualCallInConstructorRule.Create,
    DialogUnit('  inherited Create(AOwner);'#10'  ApplyTheme;'#10, cReadRules, cDerivedCtor), cLowConfidence))));
  // Die Überschreibung liest kein eigenes Feld.
  TRuleAssert.Silent(TVirtualCallInConstructorRule.Create, DialogUnit('  inherited Create(AOwner);'#10 +
    '  BuildControls;'#10, '  Caption := ''Regeln'';'#10, cDerivedCtor));
  // Aufruf an einem anderen Objekt.
  TRuleAssert.Silent(TVirtualCallInConstructorRule.Create, DialogUnit('  inherited Create(AOwner);'#10 +
    '  FOther.BuildControls;'#10, cReadRules, cDerivedCtor));
end;

procedure TVirtualCallInConstructorRuleTests.GuardedOrEarlyFieldIsSilent;
begin
  // Die Überschreibung prüft das Feld auf nil.
  TRuleAssert.Silent(TVirtualCallInConstructorRule.Create, DialogUnit('  inherited Create(AOwner);'#10 +
    '  BuildControls;'#10, '  if Assigned(FRules) then'#10'    FRules.Add(''Regel'');'#10, cDerivedCtor));
  TRuleAssert.Silent(TVirtualCallInConstructorRule.Create, DialogUnit('  inherited Create(AOwner);'#10 +
    '  BuildControls;'#10, '  if FRules <> nil then'#10'    FRules.Add(''Regel'');'#10, cDerivedCtor));
  // Der Nachfahr setzt das Feld vor inherited.
  TRuleAssert.Silent(TVirtualCallInConstructorRule.Create, DialogUnit('  inherited Create(AOwner);'#10 +
    '  BuildControls;'#10, cReadRules, '  FRules := ARules;'#10'  inherited Create(AOwner);'#10));
  // Die Überschreibung schreibt das Feld nur oder gibt es frei.
  TRuleAssert.Silent(TVirtualCallInConstructorRule.Create, DialogUnit('  inherited Create(AOwner);'#10 +
    '  BuildControls;'#10, '  FRules := nil;'#10'  FreeAndNil(FRules);'#10'  FRules.Free;'#10, cDerivedCtor));
end;

procedure TVirtualCallInConstructorRuleTests.ChainOverHelper;
var
  mFindings: TArray<TRuleFinding>;
begin
  // Über die nicht virtuelle Methode Prepare.
  mFindings := TRuleAssert.Findings(TVirtualCallInConstructorRule.Create, DialogUnit('  inherited Create(AOwner);'#10 +
    '  Prepare;'#10, cReadRules, cDerivedCtor));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Prepare ruft die virtuelle Methode BuildControls auf; TAtlasRuleDialog.BuildControls liest ' +
    'FRules, das erst nach inherited Create gesetzt wird.', mFindings[0].Message);
  Assert.AreEqual(25, mFindings[0].Range.StartPos.Line);
  // Über eine eingebettete Routine.
  mFindings := TRuleAssert.Findings(TVirtualCallInConstructorRule.Create, StringReplace(DialogUnit(
    '  inherited Create(AOwner);'#10'  Aufbauen;'#10, cReadRules, cDerivedCtor),
    'constructor TAtlasDialog.Create(AOwner: TComponent);'#10, 'constructor TAtlasDialog.Create(AOwner: TComponent);'#10 +
    '  procedure Aufbauen;'#10'  begin'#10'    BuildControls;'#10'  end;'#10, []));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.StartsWith('Aufbauen ruft die virtuelle Methode BuildControls auf;', mFindings[0].Message);
end;

// Liest die Datei des Nachfahren aus dem Text ADerived, alle anderen nicht.
function DerivedReader(const ADerived: string): TRuleFileReader;
begin
  Result :=
    function(const AName: string; out AData: TBytes): Boolean
    begin
      Result := SameText(AName, 'C:\Quellen\Ableitung.pas');
      if Result then
      begin
        AData := TEncoding.UTF8.GetBytes(ADerived);
      end;
    end;
end;

procedure TVirtualCallInConstructorRuleTests.DescendantInOtherUnit;
const
  cBase = 'unit Basis;'#10'interface'#10'uses'#10'  System.Classes;'#10'type'#10 +
    '  TAtlasDialog = class(TComponent)'#10'  protected'#10'    procedure BuildControls; virtual;'#10'  public'#10 +
    '    constructor Create(AOwner: TComponent); override;'#10'  end;'#10'implementation'#10 +
    'constructor TAtlasDialog.Create(AOwner: TComponent);'#10'begin'#10'  inherited Create(AOwner);'#10 +
    '  BuildControls;'#10'end;'#10'procedure TAtlasDialog.BuildControls;'#10'begin'#10'end;'#10'end.';
  cDerived = 'unit Ableitung;'#10'interface'#10'uses'#10'  System.Classes, Basis;'#10'type'#10 + cDerivedDecl +
    'implementation'#10'procedure TAtlasRuleDialog.BuildControls;'#10'begin'#10 + cReadRules + 'end;'#10 +
    'constructor TAtlasRuleDialog.Create(AOwner: TComponent; ARules: TStrings);'#10'begin'#10 + cDerivedCtor +
    'end;'#10'end.';
var
  mIndex: ISymbolIndex;
  mTree: TSyntaxTree;
  mContext: TRuleContext;
  mFindings: TArray<TRuleFinding>;
begin
  mIndex := TSymbolIndex.Create;
  mTree := TPascalParser.Parse(cBase);
  try
    mIndex.AddUnit(TIndexExtractor.Extract(mTree, 'C:\Quellen\Basis.pas'));
  finally
    mTree.Free;
  end;
  mTree := TPascalParser.Parse(cDerived);
  try
    mIndex.AddUnit(TIndexExtractor.Extract(mTree, 'C:\Quellen\Ableitung.pas'));
  finally
    mTree.Free;
  end;
  mContext := Default(TRuleContext);
  mContext.Text := cBase;
  mContext.FileName := 'C:\Quellen\Basis.pas';
  mContext.Index := mIndex;
  mContext.ReadFile := DerivedReader(cDerived);
  mFindings := TRuleAssert.ContextFindings(TVirtualCallInConstructorRule.Create, mContext, '');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('BuildControls ist virtuell; TAtlasRuleDialog.BuildControls liest FRules, das erst nach inherited ' +
    'Create gesetzt wird.', mFindings[0].Message);
  Assert.AreEqual(15, mFindings[0].Range.StartPos.Line);
  // Ohne Sprung: die Überschreibung steht in einer anderen Datei.
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  // Lässt sich die Unit des Nachfahren nicht lesen, schweigt die Regel (mit Index kein Raten).
  mContext.ReadFile := nil;
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TVirtualCallInConstructorRule.Create, mContext,
    cLowConfidence))));
end;

procedure TVirtualCallInConstructorRuleTests.WithoutIndexOnlyBeforeInherited;
var
  mFindings: TArray<TRuleFinding>;
begin
  // Ohne Index und ohne Nachfahren in der Unit: Hinweis nur vor inherited.
  mFindings := TRuleAssert.Findings(TVirtualCallInConstructorRule.Create, cBaseDecl + 'implementation'#10 +
    'constructor TAtlasDialog.Create(AOwner: TComponent);'#10'begin'#10'  ApplyTheme;'#10 +
    '  inherited Create(AOwner);'#10'  BuildControls;'#10'end;'#10'end.', cLowConfidence);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(mFindings[0].Confidence));
  Assert.AreEqual('ApplyTheme ist virtuell und läuft vor inherited; eine Überschreibung sieht die Felder ihrer ' +
    'Klasse noch nicht gesetzt.', mFindings[0].Message);
  Assert.AreEqual(16, mFindings[0].Range.StartPos.Line);
  // Mit der Vorgabe (Konfidenz ab mittel) bleibt der Hinweis verborgen.
  TRuleAssert.Silent(TVirtualCallInConstructorRule.Create, cBaseDecl + 'implementation'#10 +
    'constructor TAtlasDialog.Create(AOwner: TComponent);'#10'begin'#10'  ApplyTheme;'#10 +
    '  inherited Create(AOwner);'#10'end;'#10'end.');
end;

initialization
  TDUnitX.RegisterTestFixture(TVirtualCallInConstructorRuleTests);

end.
