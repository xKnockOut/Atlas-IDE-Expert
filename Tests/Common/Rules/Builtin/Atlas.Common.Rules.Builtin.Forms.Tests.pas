unit Atlas.Common.Rules.Builtin.Forms.Tests;

// Tests der Formularregeln aus Builtin.Forms: form-resource-missing (#1054), form-autocreate-and-manual (#1055),
// inherited-form-handler-without-inherited (#1056).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormRulesTests = class
  public
    [Test]
    procedure ResourceMissingIssueExample;
    [Test]
    procedure ResourceMissingFixInsertsDirective;
    [Test]
    procedure ResourceIncludedIsSilent;
    [Test]
    procedure ResourceWithoutFormFileIsReported;
    [Test]
    procedure ResourceOtherClassOrNoFormIsSilent;
    [Test]
    procedure ResourceFmxAndExplicitName;
    [Test]
    procedure ResourceOffAndExclude;
    [Test]
    procedure FormResourceParsesDirectives;
    [Test]
    procedure AutoCreateIssueExample;
    [Test]
    procedure AutoCreateFixRemovesCreateForm;
    [Test]
    procedure AutoCreateGuardsAreSilent;
    [Test]
    procedure AutoCreateOtherNamesAreSilent;
    [Test]
    procedure AutoCreateWithoutProjectFile;
    [Test]
    procedure AutoCreateOffAndExclude;
    [Test]
    procedure InheritedHandlerIssueExample;
    [Test]
    procedure InheritedHandlerFixInsertsInherited;
    [Test]
    procedure InheritedHandlerSilentCases;
    [Test]
    procedure InheritedHandlerFollowsChain;
    [Test]
    procedure InheritedHandlerAncestorFromIndex;
    [Test]
    procedure InheritedHandlerOffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Builtin.FormFields,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.Forms,
  Atlas.Tests.RuleAssert;

const
  KundeForm =
    'object frmKunde: TfrmKunde'#10 +
    '  Caption = ''Kunde'''#10 +
    '  OnShow = FormShow'#10 +
    'end'#10;

function KundeUnit(const AImplementation: string): string;
begin
  Result :=
    'unit Kunde;'#10 +
    'interface'#10 +
    'uses Vcl.Forms;'#10 +
    'type'#10 +
    '  TfrmKunde = class(TForm)'#10 +
    '    procedure FormShow(Sender: TObject);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    AImplementation +
    #10 +
    'procedure TfrmKunde.FormShow(Sender: TObject);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
end;

/// <summary>Kontext wie im Server: Unit Kunde.pas, Formulardatei AFormFile mit AFormText, Dateien AFiles
/// neben der Unit.</summary>
function FormContext(const ASource, AFormText, AFormFile: string; const AFiles: TArray<string>): TRuleContext;
begin
  Result := Default(TRuleContext);
  Result.RelativePath := 'Source/Kunde.pas';
  Result.UnitName := 'Kunde';
  Result.Text := ASource;
  Result.FormText := AFormText;
  Result.FormFile := AFormFile;
  Result.ReadFile :=
    function(const AName: string; out AData: TBytes): Boolean
    var
      Name: string;
    begin
      AData := nil;
      for Name in AFiles do
        if SameText(Name, AName) then
          Exit(True);
      Result := False;
    end;
end;

const
  ProjektDpr =
    'program Projekt;'#10 +
    'uses'#10 +
    '  Vcl.Forms,'#10 +
    '  Haupt in ''Haupt.pas'' {frmHaupt},'#10 +
    '  Bericht in ''Bericht.pas'' {frmBericht};'#10 +
    'begin'#10 +
    '  Application.Initialize;'#10 +
    '  Application.CreateForm(TfrmHaupt, frmHaupt);'#10 +
    '  Application.CreateForm(TfrmBericht, frmBericht);'#10 +
    '  Application.Run;'#10 +
    'end.';

function HauptUnit(const AVar, ABody: string): string;
begin
  Result :=
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Vcl.Forms, Bericht;'#10 +
    'type'#10 +
    '  TfrmHaupt = class(TForm)'#10 +
    '    procedure BerichtClick(Sender: TObject);'#10 +
    '  end;'#10 +
    'var'#10 +
    '  frmHaupt: TfrmHaupt;'#10 +
    'implementation'#10 +
    'procedure TfrmHaupt.BerichtClick(Sender: TObject);'#10 +
    AVar +
    'begin'#10 +
    ABody +
    'end;'#10 +
    'end.';
end;

/// <summary>Kontext einer Unit des Projekts Projekt.dpr (CreateForm-Reihenfolge, .dpr über ReadFile).</summary>
function ProjectContext(const ASource, AMainSource: string): TRuleContext;
begin
  Result := Default(TRuleContext);
  Result.RelativePath := 'Source/Haupt.pas';
  Result.UnitName := 'Haupt';
  Result.Text := ASource;
  Result.ProjectName := 'Projekt';
  Result.AutoCreateForms := TFormAccessBeforeCreateRule.AutoCreatedForms(ProjektDpr);
  if AMainSource = '' then
    Exit;
  Result.ProjectMainSource := 'C:\P\Projekt.dpr';
  Result.ReadFile :=
    function(const AName: string; out AData: TBytes): Boolean
    begin
      Result := SameText(AName, 'C:\P\Projekt.dpr');
      if Result then
        AData := TEncoding.UTF8.GetBytes(AMainSource);
    end;
end;

const
  BasisDialogDfm =
    'object frmBasisDialog: TfrmBasisDialog'#10 +
    '  Caption = ''Dialog'''#10 +
    '  OnShow = FormShow'#10 +
    '  object btnSpeichern: TButton'#10 +
    '    Caption = ''Speichern'''#10 +
    '    OnClick = btnSpeichernClick'#10 +
    '  end'#10 +
    'end'#10;
  KundeBearbeitenDfm =
    'inherited frmKundeBearbeiten: TfrmKundeBearbeiten'#10 +
    '  Caption = ''Kunde bearbeiten'''#10 +
    '  inherited btnSpeichern: TButton'#10 +
    '    OnClick = btnSpeichernClick'#10 +
    '  end'#10 +
    'end'#10;

function KundeBearbeiten(const ABody: string): string;
begin
  Result :=
    'unit KundeBearbeiten;'#10 +
    'interface'#10 +
    'uses Vcl.Forms, BasisDialog, Kunden;'#10 +
    'type'#10 +
    '  TfrmKundeBearbeiten = class(TfrmBasisDialog)'#10 +
    '    procedure btnSpeichernClick(Sender: TObject);'#10 +
    '  private'#10 +
    '    FKunde: TKunde;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    '{$R *.dfm}'#10 +
    'procedure TfrmKundeBearbeiten.btnSpeichernClick(Sender: TObject);'#10 +
    'begin'#10 +
    ABody +
    'end;'#10 +
    'end.';
end;

/// <summary>Kontext mit Formulardatei AFormText und Dateien ANames (Inhalt ATexts) neben der Unit.</summary>
function FilesContext(const ASource, AFormText: string; const ANames, ATexts: TArray<string>): TRuleContext;
begin
  Result := Default(TRuleContext);
  Result.RelativePath := 'Source/KundeBearbeiten.pas';
  Result.UnitName := 'KundeBearbeiten';
  Result.Text := ASource;
  Result.FormText := AFormText;
  Result.ReadFile :=
    function(const AName: string; out AData: TBytes): Boolean
    var
      Index: Integer;
    begin
      for Index := 0 to High(ANames) do
        if SameText(ANames[Index], AName) then
        begin
          AData := TEncoding.UTF8.GetBytes(ATexts[Index]);
          Exit(True);
        end;
      Result := False;
    end;
end;

function InheritedFindings(const ASource, AFormText: string; const ANames, ATexts: TArray<string>):
  TArray<TRuleFinding>;
begin
  Result := TRuleAssert.ContextFindings(TInheritedFormHandlerRule.Create, FilesContext(ASource, AFormText, ANames,
    ATexts), '');
end;

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

{ TFormRulesTests }

procedure TFormRulesTests.ResourceMissingIssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(''), KundeForm, 'C:\P\Kunde.dfm', ['Kunde.dfm']), '');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('form-resource-missing', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Kunde.dfm wird nicht eingebunden; TfrmKunde.Create löst EResNotFound aus.', Findings[0].Message);
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(0, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(14, Findings[0].Range.EndPos.Character);
end;

procedure TFormRulesTests.ResourceMissingFixInsertsDirective;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
  Tree: TSyntaxTree;
begin
  Source := KundeUnit('');
  Findings := TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(Source, KundeForm, 'C:\P\Kunde.dfm', ['Kunde.dfm']), '');
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('{$R *.dfm} nach implementation einfügen', Findings[0].Fixes[0].Title);
  Assert.IsTrue(Findings[0].Fixes[0].Safe);
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(KundeUnit(#10'{$R *.dfm}'#10), Fixed);
  Tree := TPascalParser.Parse(Fixed);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
  finally
    Tree.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(Fixed, KundeForm, 'C:\P\Kunde.dfm', ['Kunde.dfm']), ''))));
end;

procedure TFormRulesTests.ResourceIncludedIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$R *.DFM}'#10), KundeForm, 'C:\P\Kunde.dfm', ['Kunde.dfm']), ''))));
  // Eingebunden nur in einem Zweig der bedingten Übersetzung zählt ebenfalls.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$IFDEF MSWINDOWS}'#10'{$R *.dfm}'#10'{$ENDIF}'#10), KundeForm, 'C:\P\Kunde.dfm',
    ['Kunde.dfm']), ''))));
  // Eingebunden vor der uses-Klausel des Implementation-Teils.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$R *.dfm}'#10#10'uses System.SysUtils;'#10), KundeForm, 'C:\P\Kunde.dfm',
    ['Kunde.dfm']), ''))));
end;

procedure TFormRulesTests.ResourceWithoutFormFileIsReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$R *.dfm}'#10), '', '', []), '');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Kunde.dfm fehlt; der Compiler bricht mit F1026 ab.', Findings[0].Message);
  Assert.AreEqual(9, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Ohne Dateizugriff (Linter ohne Pfad) keine Aussage.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TFormResourceMissingRule.Create,
    KundeUnit(#10'{$R *.dfm}'#10), ''))));
end;

procedure TFormRulesTests.ResourceOtherClassOrNoFormIsSilent;
begin
  // Wurzelklasse der Formulardatei steht nicht in der Unit.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(''), StringReplace(KundeForm, 'TfrmKunde', 'TfrmAnders', []), 'C:\P\Kunde.dfm',
    ['Kunde.dfm']), ''))));
  // Unit ohne Formulardatei und ohne {$R}.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(''), '', '', []), ''))));
  // Andere Ressourcen ({$R *.res}) zählen nicht.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$R *.res}'#10), '', '', []), ''))));
end;

procedure TFormRulesTests.ResourceFmxAndExplicitName;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(''), KundeForm, 'C:\P\Kunde.fmx', ['Kunde.fmx']), '');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Kunde.fmx wird nicht eingebunden; TfrmKunde.Create löst EResNotFound aus.', Findings[0].Message);
  Assert.AreEqual('{$R *.fmx} nach implementation einfügen', Findings[0].Fixes[0].Title);
  // Falscher Name: die eingebundene Datei fehlt.
  Findings := TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$R Kunden.dfm}'#10), '', '', ['Kunde.dfm']), '');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Kunden.dfm fehlt; der Compiler bricht mit F1026 ab.', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$R ''Kunden.dfm''}'#10), '', '', ['Kunden.dfm']), ''))));
end;

procedure TFormRulesTests.ResourceOffAndExclude;
var
  Context: TRuleContext;
begin
  Context := FormContext(KundeUnit(''), KundeForm, 'C:\P\Kunde.dfm', ['Kunde.dfm']);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create, Context,
    '{"rules": {"form-resource-missing": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create, Context,
    '{"rules": {"form-resource-missing": {"exclude": ["Source/*.pas"]}}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create, Context,
    '{"rules": {"group:forms": "off"}}'))));
end;

procedure TFormRulesTests.FormResourceParsesDirectives;
var
  FileName: string;
begin
  Assert.IsTrue(TFormResourceMissingRule.FormResource('{$R *.dfm}', 'Kunde', FileName));
  Assert.AreEqual('Kunde.dfm', FileName);
  Assert.IsTrue(TFormResourceMissingRule.FormResource('{$R *.Windows.fmx MSWINDOWS}', 'Kunde', FileName));
  Assert.AreEqual('Kunde.Windows.fmx', FileName);
  Assert.IsTrue(TFormResourceMissingRule.FormResource('{$RESOURCE ''Form\Kunde.dfm''}', 'Kunde', FileName));
  Assert.AreEqual('Form\Kunde.dfm', FileName);
  Assert.IsFalse(TFormResourceMissingRule.FormResource('{$R *.res}', 'Kunde', FileName));
  Assert.IsFalse(TFormResourceMissingRule.FormResource('{$R+}', 'Kunde', FileName));
  Assert.IsFalse(TFormResourceMissingRule.FormResource('{$R *.dfm}', '', FileName));
end;

procedure TFormRulesTests.AutoCreateIssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.ContextFindings(TFormAutoCreateAndManualRule.Create, ProjectContext(HauptUnit('',
    '  frmBericht := TfrmBericht.Create(Application);'#10'  frmBericht.ShowModal;'#10), ProjektDpr), '');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('form-autocreate-and-manual', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('frmBericht wird schon in Projekt.dpr erzeugt; hier entsteht eine zweite Instanz.',
    Findings[0].Message);
  Assert.AreEqual(12, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(34, Findings[0].Range.EndPos.Character);
end;

procedure TFormRulesTests.AutoCreateFixRemovesCreateForm;
var
  Findings: TArray<TRuleFinding>;
  Fixed: string;
  Tree: TSyntaxTree;
begin
  Findings := TRuleAssert.ContextFindings(TFormAutoCreateAndManualRule.Create, ProjectContext(HauptUnit('',
    '  frmBericht := TfrmBericht.Create(Application);'#10'  frmBericht.ShowModal;'#10), ProjektDpr), '');
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Application.CreateForm(TfrmBericht, frmBericht) aus Projekt.dpr entfernen',
    Findings[0].Fixes[0].Title);
  Assert.AreEqual('C:\P\Projekt.dpr', Findings[0].Fixes[0].FileName);
  Assert.IsFalse(Findings[0].Fixes[0].Safe);
  Fixed := ApplyFix(ProjektDpr, Findings[0].Fixes[0]);
  Assert.AreEqual(StringReplace(ProjektDpr, '  Application.CreateForm(TfrmBericht, frmBericht);'#10, '', []), Fixed);
  Tree := TPascalParser.Parse(Fixed);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
  finally
    Tree.Free;
  end;
  // Danach erzeugt nur noch der Code das Formular.
  Assert.AreEqual('frmHaupt', string.Join(',', TFormAccessBeforeCreateRule.AutoCreatedForms(Fixed)));
end;

procedure TFormRulesTests.AutoCreateGuardsAreSilent;

  procedure Silent(const AVar, ABody: string);
  begin
    Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormAutoCreateAndManualRule.Create,
      ProjectContext(HauptUnit(AVar, ABody), ProjektDpr), ''))), ABody);
  end;

begin
  Silent('', '  if not Assigned(frmBericht) then'#10'    frmBericht := TfrmBericht.Create(Application);'#10);
  Silent('', '  if frmBericht = nil then'#10'    frmBericht := TfrmBericht.Create(Application);'#10);
  Silent('', '  frmBericht.Free;'#10'  frmBericht := TfrmBericht.Create(Application);'#10);
  Silent('', '  FreeAndNil(frmBericht);'#10'  frmBericht := TfrmBericht.Create(Application);'#10);
  Silent('', '  frmBericht.Release;'#10'  frmBericht := TfrmBericht.Create(Application);'#10);
  // Lokale Variable gleichen Namens.
  Silent('var'#10'  frmBericht: TfrmBericht;'#10, '  frmBericht := TfrmBericht.Create(nil);'#10);
end;

procedure TFormRulesTests.AutoCreateOtherNamesAreSilent;
var
  Source: string;
begin
  // Nicht automatisch erzeugt, nicht der globalen Variablen zugewiesen, andere Klasse als in CreateForm.
  Source := HauptUnit('var'#10'  Dialog: TfrmBericht;'#10, '  Dialog := TfrmBericht.Create(nil);'#10 +
    '  with TfrmBericht.Create(nil) do'#10'    ShowModal;'#10 + '  frmBericht := TfrmBerichtNeu.Create(nil);'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormAutoCreateAndManualRule.Create,
    ProjectContext(Source, ProjektDpr), ''))));
  // Feld gleichen Namens in der eigenen Klasse.
  Source := StringReplace(HauptUnit('', '  frmBericht := TfrmBericht.Create(Self);'#10),
    '    procedure BerichtClick', '    frmBericht: TfrmBericht;'#10'    procedure BerichtClick', []);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormAutoCreateAndManualRule.Create,
    ProjectContext(Source, ProjektDpr), ''))));
  // Unit außerhalb eines Projekts.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TFormAutoCreateAndManualRule.Create,
    HauptUnit('', '  frmBericht := TfrmBericht.Create(Application);'#10)))));
end;

procedure TFormRulesTests.AutoCreateWithoutProjectFile;
var
  Findings: TArray<TRuleFinding>;
begin
  // Nur die Reihenfolge bekannt (Linter, Golden-Korpus): Meldung ohne Korrektur.
  Findings := TRuleAssert.ContextFindings(TFormAutoCreateAndManualRule.Create, ProjectContext(HauptUnit('',
    '  frmBericht := TfrmBericht.Create(Application);'#10), ''), '');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('frmBericht wird schon in Projekt.dpr erzeugt; hier entsteht eine zweite Instanz.',
    Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TFormRulesTests.AutoCreateOffAndExclude;
var
  Context: TRuleContext;
begin
  Context := ProjectContext(HauptUnit('', '  frmBericht := TfrmBericht.Create(Application);'#10), ProjektDpr);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormAutoCreateAndManualRule.Create, Context,
    '{"rules": {"form-autocreate-and-manual": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormAutoCreateAndManualRule.Create, Context,
    '{"rules": {"form-autocreate-and-manual": {"exclude": ["Source/*.pas"]}}}'))));
end;

procedure TFormRulesTests.InheritedHandlerIssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := InheritedFindings(KundeBearbeiten('  FKunde.Speichern;'#10), KundeBearbeitenDfm, ['BasisDialog.dfm'],
    [BasisDialogDfm]);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('inherited-form-handler-without-inherited', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('TfrmBasisDialog.btnSpeichernClick wird nicht mehr ausgeführt (kein inherited).',
    Findings[0].Message);
  Assert.AreEqual(11, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(30, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(47, Findings[0].Range.EndPos.Character);
end;

procedure TFormRulesTests.InheritedHandlerFixInsertsInherited;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
  Tree: TSyntaxTree;
begin
  Source := KundeBearbeiten('  FKunde.Speichern;'#10);
  Findings := InheritedFindings(Source, KundeBearbeitenDfm, ['BasisDialog.dfm'], [BasisDialogDfm]);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('inherited; am Anfang einfügen', Findings[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(KundeBearbeiten('  inherited;'#10'  FKunde.Speichern;'#10), Fixed);
  Tree := TPascalParser.Parse(Fixed);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
  finally
    Tree.Free;
  end;
  Assert.AreEqual(0, Integer(Length(InheritedFindings(Fixed, KundeBearbeitenDfm, ['BasisDialog.dfm'],
    [BasisDialogDfm]))));
end;

procedure TFormRulesTests.InheritedHandlerSilentCases;
begin
  // inherited mit Namen bzw. irgendwo im Rumpf.
  Assert.AreEqual(0, Integer(Length(InheritedFindings(KundeBearbeiten('  FKunde.Speichern;'#10 +
    '  inherited btnSpeichernClick(Sender);'#10), KundeBearbeitenDfm, ['BasisDialog.dfm'], [BasisDialogDfm]))));
  // Anderer Handlername: bewusster Ersatz.
  Assert.AreEqual(0, Integer(Length(InheritedFindings(StringReplace(KundeBearbeiten('  FKunde.Speichern;'#10),
    'btnSpeichernClick', 'SpeichernNeuClick', [rfReplaceAll]), StringReplace(KundeBearbeitenDfm,
    'btnSpeichernClick', 'SpeichernNeuClick', []), ['BasisDialog.dfm'], [BasisDialogDfm]))));
  // Vorfahr belegt das Ereignis nicht.
  Assert.AreEqual(0, Integer(Length(InheritedFindings(KundeBearbeiten('  FKunde.Speichern;'#10),
    KundeBearbeitenDfm, ['BasisDialog.dfm'], [StringReplace(BasisDialogDfm, '    OnClick = btnSpeichernClick'#10,
    '', [])]))));
  // Formulardatei des Vorfahren unbekannt.
  Assert.AreEqual(0, Integer(Length(InheritedFindings(KundeBearbeiten('  FKunde.Speichern;'#10),
    KundeBearbeitenDfm, [], []))));
  // Keine Vererbung in der Formulardatei.
  Assert.AreEqual(0, Integer(Length(InheritedFindings(KundeBearbeiten('  FKunde.Speichern;'#10),
    StringReplace(KundeBearbeitenDfm, 'inherited frmKundeBearbeiten', 'object frmKundeBearbeiten', []),
    ['BasisDialog.dfm'], [BasisDialogDfm]))));
end;

procedure TFormRulesTests.InheritedHandlerFollowsChain;
const
  MitteDfm =
    'inherited frmMitte: TfrmMitte'#10 +
    '  Caption = ''Mitte'''#10 +
    'end'#10;
  MittePas =
    'unit Mitte;'#10'interface'#10'uses BasisDialog;'#10'type'#10'  TfrmMitte = class(TfrmBasisDialog)'#10 +
    '  end;'#10'implementation'#10'{$R *.dfm}'#10'end.';
var
  Findings: TArray<TRuleFinding>;
  Source: string;
begin
  // TfrmKundeBearbeiten → TfrmMitte (ohne eigenes OnClick) → TfrmBasisDialog (setzt es).
  Source := StringReplace(StringReplace(KundeBearbeiten('  FKunde.Speichern;'#10), 'class(TfrmBasisDialog)',
    'class(TfrmMitte)', []), 'BasisDialog, Kunden', 'Mitte, Kunden', []);
  Findings := InheritedFindings(Source, KundeBearbeitenDfm, ['Mitte.dfm', 'Mitte.pas', 'BasisDialog.dfm'],
    [MitteDfm, MittePas, BasisDialogDfm]);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TfrmBasisDialog.btnSpeichernClick wird nicht mehr ausgeführt (kein inherited).',
    Findings[0].Message);
end;

procedure TFormRulesTests.InheritedHandlerAncestorFromIndex;
var
  Index: ISymbolIndex;
  Context: TRuleContext;
  Findings: TArray<TRuleFinding>;
begin
  // Vorfahr in einem anderen Ordner: Datei kommt aus dem Index.
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit BasisDialog;'#10'interface'#10'uses Vcl.Forms;'#10'type'#10 +
    '  TfrmBasisDialog = class(TForm)'#10'  end;'#10'implementation'#10'end.', 'C:\Basis\BasisDialog.pas', nil));
  Context := FilesContext(KundeBearbeiten('  FKunde.Speichern;'#10), KundeBearbeitenDfm,
    ['C:\Basis\BasisDialog.dfm'], [BasisDialogDfm]);
  Context.Index := Index;
  Findings := TRuleAssert.ContextFindings(TInheritedFormHandlerRule.Create, Context, '');
  Assert.AreEqual(1, Integer(Length(Findings)));
end;

procedure TFormRulesTests.InheritedHandlerOffAndExclude;
var
  Context: TRuleContext;
begin
  Context := FilesContext(KundeBearbeiten('  FKunde.Speichern;'#10), KundeBearbeitenDfm, ['BasisDialog.dfm'],
    [BasisDialogDfm]);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TInheritedFormHandlerRule.Create, Context,
    '{"rules": {"inherited-form-handler-without-inherited": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TInheritedFormHandlerRule.Create, Context,
    '{"rules": {"inherited-form-handler-without-inherited": {"exclude": ["Source/*.pas"]}}}'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TFormRulesTests);

end.
