unit Atlas.Common.Rules.Builtin.Forms.Tests;

// Tests der Formularregeln aus Builtin.Forms: form-resource-missing (#1054), form-autocreate-and-manual (#1055),
// inherited-form-handler-without-inherited (#1056), self-free-in-event-handler (#1057).

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
    [Test]
    procedure SelfFreeIssueExample;
    [Test]
    procedure SelfFreeFixUsesRelease;
    [Test]
    procedure SelfFreeVariants;
    [Test]
    procedure SelfFreeOnCloseUsesCaFree;
    [Test]
    procedure SelfFreeSilentCases;
    [Test]
    procedure SelfFreeOffAndExclude;
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
  cKundeForm =
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
      begin
        if SameText(Name, AName) then
        begin
          Exit(True);
        end;
      end;
      Result := False;
    end;
end;

const
  cProjektDpr =
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
  Result.AutoCreateForms := TFormAccessBeforeCreateRule.AutoCreatedForms(cProjektDpr);
  if AMainSource = '' then
  begin
    Exit;
  end;
  Result.ProjectMainSource := 'C:\P\Projekt.dpr';
  Result.ReadFile :=
    function(const AName: string; out AData: TBytes): Boolean
    begin
      Result := SameText(AName, 'C:\P\Projekt.dpr');
      if Result then
      begin
        AData := TEncoding.UTF8.GetBytes(AMainSource);
      end;
    end;
end;

const
  cBasisDialogDfm =
    'object frmBasisDialog: TfrmBasisDialog'#10 +
    '  Caption = ''Dialog'''#10 +
    '  OnShow = FormShow'#10 +
    '  object btnSpeichern: TButton'#10 +
    '    Caption = ''Speichern'''#10 +
    '    OnClick = btnSpeichernClick'#10 +
    '  end'#10 +
    'end'#10;
  cKundeBearbeitenDfm =
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
      begin
        if SameText(ANames[Index], AName) then
        begin
          AData := TEncoding.UTF8.GetBytes(ATexts[Index]);
          Exit(True);
        end;
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

const
  cMeldungDfm =
    'object frmMeldung: TfrmMeldung'#10 +
    '  Caption = ''Meldung'''#10 +
    '  ClientHeight = 120'#10 +
    '  ClientWidth = 300'#10 +
    '  OnClose = FormClose'#10 +
    '  object btnOK: TButton'#10 +
    '    OnClick = btnOKClick'#10 +
    '  end'#10 +
    'end'#10;

function Meldung(const AHeader, ABody: string): string;
begin
  Result :=
    'unit Meldung;'#10 +
    'interface'#10 +
    'uses System.Classes, Vcl.Forms, Vcl.StdCtrls;'#10 +
    'type'#10 +
    '  TfrmMeldung = class(TForm)'#10 +
    '    btnOK: TButton;'#10 +
    '    procedure btnOKClick(Sender: TObject);'#10 +
    '    procedure FormClose(Sender: TObject; var Action: TCloseAction);'#10 +
    '    procedure Aufraeumen;'#10 +
    '    procedure Weiter(Sender: TObject);'#10 +
    '  end;'#10 +
    'var'#10 +
    '  frmMeldung: TfrmMeldung;'#10 +
    'implementation'#10 +
    '{$R *.dfm}'#10 +
    AHeader + #10 +
    'begin'#10 +
    ABody +
    'end;'#10 +
    'end.';
end;

function SelfFreeFindings(const AHeader, ABody: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.FormFindings(TSelfFreeInEventHandlerRule.Create, Meldung(AHeader, ABody), cMeldungDfm);
end;

const
  cClickHeader = 'procedure TfrmMeldung.btnOKClick(Sender: TObject);';

function ApplyFix(const AText: string; const AFix: TRuleFix): string;
var
  mIndex: Integer;
  mEdit: TRuleEdit;

  function OffsetOf(const APosition: TTextPosition): Integer;
  var
    mLine, mPosition: Integer;
  begin
    mPosition := 0;
    for mLine := 1 to APosition.Line do
    begin
      mPosition := Pos(#10, AText, mPosition + 1);
    end;
    Result := mPosition + APosition.Character;
  end;

begin
  Result := AText;
  for mIndex := High(AFix.Edits) downto 0 do
  begin
    mEdit := AFix.Edits[mIndex];
    Result := Copy(Result, 1, OffsetOf(mEdit.Range.StartPos)) + mEdit.NewText +
      Copy(Result, OffsetOf(mEdit.Range.EndPos) + 1, MaxInt);
  end;
end;

{ TFormRulesTests }

procedure TFormRulesTests.ResourceMissingIssueExample;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(''), cKundeForm, 'C:\P\Kunde.dfm', ['Kunde.dfm']), '');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('form-resource-missing', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Kunde.dfm wird nicht eingebunden; TfrmKunde.Create löst EResNotFound aus.', mFindings[0].Message);
  Assert.AreEqual(7, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(0, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(14, mFindings[0].Range.EndPos.Character);
end;

procedure TFormRulesTests.ResourceMissingFixInsertsDirective;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
  mTree: TSyntaxTree;
begin
  mSource := KundeUnit('');
  mFindings := TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(mSource, cKundeForm, 'C:\P\Kunde.dfm', ['Kunde.dfm']), '');
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('{$R *.dfm} nach implementation einfügen', mFindings[0].Fixes[0].Title);
  Assert.IsTrue(mFindings[0].Fixes[0].Safe);
  mFixed := ApplyFix(mSource, mFindings[0].Fixes[0]);
  Assert.AreEqual(KundeUnit(#10'{$R *.dfm}'#10), mFixed);
  mTree := TPascalParser.Parse(mFixed);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)));
  finally
    mTree.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(mFixed, cKundeForm, 'C:\P\Kunde.dfm', ['Kunde.dfm']), ''))));
end;

procedure TFormRulesTests.ResourceIncludedIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$R *.DFM}'#10), cKundeForm, 'C:\P\Kunde.dfm', ['Kunde.dfm']), ''))));
  // Eingebunden nur in einem Zweig der bedingten Übersetzung zählt ebenfalls.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$IFDEF MSWINDOWS}'#10'{$R *.dfm}'#10'{$ENDIF}'#10), cKundeForm, 'C:\P\Kunde.dfm',
    ['Kunde.dfm']), ''))));
  // Eingebunden vor der uses-Klausel des Implementation-Teils.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$R *.dfm}'#10#10'uses System.SysUtils;'#10), cKundeForm, 'C:\P\Kunde.dfm',
    ['Kunde.dfm']), ''))));
end;

procedure TFormRulesTests.ResourceWithoutFormFileIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$R *.dfm}'#10), '', '', []), '');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Kunde.dfm fehlt; der Compiler bricht mit F1026 ab.', mFindings[0].Message);
  Assert.AreEqual(9, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  // Ohne Dateizugriff (Linter ohne Pfad) keine Aussage.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TFormResourceMissingRule.Create,
    KundeUnit(#10'{$R *.dfm}'#10), ''))));
end;

procedure TFormRulesTests.ResourceOtherClassOrNoFormIsSilent;
begin
  // Wurzelklasse der Formulardatei steht nicht in der Unit.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(''), StringReplace(cKundeForm, 'TfrmKunde', 'TfrmAnders', []), 'C:\P\Kunde.dfm',
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
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(''), cKundeForm, 'C:\P\Kunde.fmx', ['Kunde.fmx']), '');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Kunde.fmx wird nicht eingebunden; TfrmKunde.Create löst EResNotFound aus.', mFindings[0].Message);
  Assert.AreEqual('{$R *.fmx} nach implementation einfügen', mFindings[0].Fixes[0].Title);
  // Falscher Name: die eingebundene Datei fehlt.
  mFindings := TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$R Kunden.dfm}'#10), '', '', ['Kunde.dfm']), '');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Kunden.dfm fehlt; der Compiler bricht mit F1026 ab.', mFindings[0].Message);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$R ''Kunden.dfm''}'#10), '', '', ['Kunden.dfm']), ''))));
end;

procedure TFormRulesTests.ResourceOffAndExclude;
var
  mContext: TRuleContext;
begin
  mContext := FormContext(KundeUnit(''), cKundeForm, 'C:\P\Kunde.dfm', ['Kunde.dfm']);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create, mContext,
    '{"rules": {"form-resource-missing": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create, mContext,
    '{"rules": {"form-resource-missing": {"exclude": ["Source/*.pas"]}}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create, mContext,
    '{"rules": {"group:forms": "off"}}'))));
end;

procedure TFormRulesTests.FormResourceParsesDirectives;
var
  mFileName: string;
begin
  Assert.IsTrue(TFormResourceMissingRule.FormResource('{$R *.dfm}', 'Kunde', mFileName));
  Assert.AreEqual('Kunde.dfm', mFileName);
  Assert.IsTrue(TFormResourceMissingRule.FormResource('{$R *.Windows.fmx MSWINDOWS}', 'Kunde', mFileName));
  Assert.AreEqual('Kunde.Windows.fmx', mFileName);
  Assert.IsTrue(TFormResourceMissingRule.FormResource('{$RESOURCE ''Form\Kunde.dfm''}', 'Kunde', mFileName));
  Assert.AreEqual('Form\Kunde.dfm', mFileName);
  Assert.IsFalse(TFormResourceMissingRule.FormResource('{$R *.res}', 'Kunde', mFileName));
  Assert.IsFalse(TFormResourceMissingRule.FormResource('{$R+}', 'Kunde', mFileName));
  Assert.IsFalse(TFormResourceMissingRule.FormResource('{$R *.dfm}', '', mFileName));
end;

procedure TFormRulesTests.AutoCreateIssueExample;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.ContextFindings(TFormAutoCreateAndManualRule.Create, ProjectContext(HauptUnit('',
    '  frmBericht := TfrmBericht.Create(Application);'#10'  frmBericht.ShowModal;'#10), cProjektDpr), '');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('form-autocreate-and-manual', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('frmBericht wird schon in Projekt.dpr erzeugt; hier entsteht eine zweite Instanz.',
    mFindings[0].Message);
  Assert.AreEqual(12, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(34, mFindings[0].Range.EndPos.Character);
end;

procedure TFormRulesTests.AutoCreateFixRemovesCreateForm;
var
  mFindings: TArray<TRuleFinding>;
  mFixed: string;
  mTree: TSyntaxTree;
begin
  mFindings := TRuleAssert.ContextFindings(TFormAutoCreateAndManualRule.Create, ProjectContext(HauptUnit('',
    '  frmBericht := TfrmBericht.Create(Application);'#10'  frmBericht.ShowModal;'#10), cProjektDpr), '');
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Application.CreateForm(TfrmBericht, frmBericht) aus Projekt.dpr entfernen',
    mFindings[0].Fixes[0].Title);
  Assert.AreEqual('C:\P\Projekt.dpr', mFindings[0].Fixes[0].FileName);
  Assert.IsFalse(mFindings[0].Fixes[0].Safe);
  mFixed := ApplyFix(cProjektDpr, mFindings[0].Fixes[0]);
  Assert.AreEqual(StringReplace(cProjektDpr, '  Application.CreateForm(TfrmBericht, frmBericht);'#10, '', []), mFixed);
  mTree := TPascalParser.Parse(mFixed);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)));
  finally
    mTree.Free;
  end;
  // Danach erzeugt nur noch der Code das Formular.
  Assert.AreEqual('frmHaupt', string.Join(',', TFormAccessBeforeCreateRule.AutoCreatedForms(mFixed)));
end;

procedure TFormRulesTests.AutoCreateGuardsAreSilent;

  procedure Silent(const AVar, ABody: string);
  begin
    Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormAutoCreateAndManualRule.Create,
      ProjectContext(HauptUnit(AVar, ABody), cProjektDpr), ''))), ABody);
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
  mSource: string;
begin
  // Nicht automatisch erzeugt, nicht der globalen Variablen zugewiesen, andere Klasse als in CreateForm.
  mSource := HauptUnit('var'#10'  Dialog: TfrmBericht;'#10, '  Dialog := TfrmBericht.Create(nil);'#10 +
    '  with TfrmBericht.Create(nil) do'#10'    ShowModal;'#10 + '  frmBericht := TfrmBerichtNeu.Create(nil);'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormAutoCreateAndManualRule.Create,
    ProjectContext(mSource, cProjektDpr), ''))));
  // Feld gleichen Namens in der eigenen Klasse.
  mSource := StringReplace(HauptUnit('', '  frmBericht := TfrmBericht.Create(Self);'#10),
    '    procedure BerichtClick', '    frmBericht: TfrmBericht;'#10'    procedure BerichtClick', []);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormAutoCreateAndManualRule.Create,
    ProjectContext(mSource, cProjektDpr), ''))));
  // Unit außerhalb eines Projekts.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TFormAutoCreateAndManualRule.Create,
    HauptUnit('', '  frmBericht := TfrmBericht.Create(Application);'#10)))));
end;

procedure TFormRulesTests.AutoCreateWithoutProjectFile;
var
  mFindings: TArray<TRuleFinding>;
begin
  // Nur die Reihenfolge bekannt (Linter, Golden-Korpus): Meldung ohne Korrektur.
  mFindings := TRuleAssert.ContextFindings(TFormAutoCreateAndManualRule.Create, ProjectContext(HauptUnit('',
    '  frmBericht := TfrmBericht.Create(Application);'#10), ''), '');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('frmBericht wird schon in Projekt.dpr erzeugt; hier entsteht eine zweite Instanz.',
    mFindings[0].Message);
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
end;

procedure TFormRulesTests.AutoCreateOffAndExclude;
var
  mContext: TRuleContext;
begin
  mContext := ProjectContext(HauptUnit('', '  frmBericht := TfrmBericht.Create(Application);'#10), cProjektDpr);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormAutoCreateAndManualRule.Create, mContext,
    '{"rules": {"form-autocreate-and-manual": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormAutoCreateAndManualRule.Create, mContext,
    '{"rules": {"form-autocreate-and-manual": {"exclude": ["Source/*.pas"]}}}'))));
end;

procedure TFormRulesTests.InheritedHandlerIssueExample;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := InheritedFindings(KundeBearbeiten('  FKunde.Speichern;'#10), cKundeBearbeitenDfm, ['BasisDialog.dfm'],
    [cBasisDialogDfm]);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('inherited-form-handler-without-inherited', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('TfrmBasisDialog.btnSpeichernClick wird nicht mehr ausgeführt (kein inherited).',
    mFindings[0].Message);
  Assert.AreEqual(11, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(30, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(47, mFindings[0].Range.EndPos.Character);
end;

procedure TFormRulesTests.InheritedHandlerFixInsertsInherited;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
  mTree: TSyntaxTree;
begin
  mSource := KundeBearbeiten('  FKunde.Speichern;'#10);
  mFindings := InheritedFindings(mSource, cKundeBearbeitenDfm, ['BasisDialog.dfm'], [cBasisDialogDfm]);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('inherited; am Anfang einfügen', mFindings[0].Fixes[0].Title);
  mFixed := ApplyFix(mSource, mFindings[0].Fixes[0]);
  Assert.AreEqual(KundeBearbeiten('  inherited;'#10'  FKunde.Speichern;'#10), mFixed);
  mTree := TPascalParser.Parse(mFixed);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)));
  finally
    mTree.Free;
  end;
  Assert.AreEqual(0, Integer(Length(InheritedFindings(mFixed, cKundeBearbeitenDfm, ['BasisDialog.dfm'],
    [cBasisDialogDfm]))));
end;

procedure TFormRulesTests.InheritedHandlerSilentCases;
begin
  // inherited mit Namen bzw. irgendwo im Rumpf.
  Assert.AreEqual(0, Integer(Length(InheritedFindings(KundeBearbeiten('  FKunde.Speichern;'#10 +
    '  inherited btnSpeichernClick(Sender);'#10), cKundeBearbeitenDfm, ['BasisDialog.dfm'], [cBasisDialogDfm]))));
  // Anderer Handlername: bewusster Ersatz.
  Assert.AreEqual(0, Integer(Length(InheritedFindings(StringReplace(KundeBearbeiten('  FKunde.Speichern;'#10),
    'btnSpeichernClick', 'SpeichernNeuClick', [rfReplaceAll]), StringReplace(cKundeBearbeitenDfm,
    'btnSpeichernClick', 'SpeichernNeuClick', []), ['BasisDialog.dfm'], [cBasisDialogDfm]))));
  // Vorfahr belegt das Ereignis nicht.
  Assert.AreEqual(0, Integer(Length(InheritedFindings(KundeBearbeiten('  FKunde.Speichern;'#10),
    cKundeBearbeitenDfm, ['BasisDialog.dfm'], [StringReplace(cBasisDialogDfm, '    OnClick = btnSpeichernClick'#10,
    '', [])]))));
  // Formulardatei des Vorfahren unbekannt.
  Assert.AreEqual(0, Integer(Length(InheritedFindings(KundeBearbeiten('  FKunde.Speichern;'#10),
    cKundeBearbeitenDfm, [], []))));
  // Keine Vererbung in der Formulardatei.
  Assert.AreEqual(0, Integer(Length(InheritedFindings(KundeBearbeiten('  FKunde.Speichern;'#10),
    StringReplace(cKundeBearbeitenDfm, 'inherited frmKundeBearbeiten', 'object frmKundeBearbeiten', []),
    ['BasisDialog.dfm'], [cBasisDialogDfm]))));
end;

procedure TFormRulesTests.InheritedHandlerFollowsChain;
const
  cMitteDfm =
    'inherited frmMitte: TfrmMitte'#10 +
    '  Caption = ''Mitte'''#10 +
    'end'#10;
  cMittePas =
    'unit Mitte;'#10'interface'#10'uses BasisDialog;'#10'type'#10'  TfrmMitte = class(TfrmBasisDialog)'#10 +
    '  end;'#10'implementation'#10'{$R *.dfm}'#10'end.';
var
  mFindings: TArray<TRuleFinding>;
  mSource: string;
begin
  // TfrmKundeBearbeiten → TfrmMitte (ohne eigenes OnClick) → TfrmBasisDialog (setzt es).
  mSource := StringReplace(StringReplace(KundeBearbeiten('  FKunde.Speichern;'#10), 'class(TfrmBasisDialog)',
    'class(TfrmMitte)', []), 'BasisDialog, Kunden', 'Mitte, Kunden', []);
  mFindings := InheritedFindings(mSource, cKundeBearbeitenDfm, ['Mitte.dfm', 'Mitte.pas', 'BasisDialog.dfm'],
    [cMitteDfm, cMittePas, cBasisDialogDfm]);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('TfrmBasisDialog.btnSpeichernClick wird nicht mehr ausgeführt (kein inherited).',
    mFindings[0].Message);
end;

procedure TFormRulesTests.InheritedHandlerAncestorFromIndex;
var
  mIndex: ISymbolIndex;
  mContext: TRuleContext;
  mFindings: TArray<TRuleFinding>;
begin
  // Vorfahr in einem anderen Ordner: Datei kommt aus dem Index.
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit BasisDialog;'#10'interface'#10'uses Vcl.Forms;'#10'type'#10 +
    '  TfrmBasisDialog = class(TForm)'#10'  end;'#10'implementation'#10'end.', 'C:\Basis\BasisDialog.pas', nil));
  mContext := FilesContext(KundeBearbeiten('  FKunde.Speichern;'#10), cKundeBearbeitenDfm,
    ['C:\Basis\BasisDialog.dfm'], [cBasisDialogDfm]);
  mContext.Index := mIndex;
  mFindings := TRuleAssert.ContextFindings(TInheritedFormHandlerRule.Create, mContext, '');
  Assert.AreEqual(1, Integer(Length(mFindings)));
end;

procedure TFormRulesTests.InheritedHandlerOffAndExclude;
var
  mContext: TRuleContext;
begin
  mContext := FilesContext(KundeBearbeiten('  FKunde.Speichern;'#10), cKundeBearbeitenDfm, ['BasisDialog.dfm'],
    [cBasisDialogDfm]);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TInheritedFormHandlerRule.Create, mContext,
    '{"rules": {"inherited-form-handler-without-inherited": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TInheritedFormHandlerRule.Create, mContext,
    '{"rules": {"inherited-form-handler-without-inherited": {"exclude": ["Source/*.pas"]}}}'))));
end;

procedure TFormRulesTests.SelfFreeIssueExample;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := SelfFreeFindings(cClickHeader, '  Free;'#10);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('self-free-in-event-handler', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Das Formular gibt sich im eigenen Click-Handler frei; die VCL greift danach noch darauf zu.',
    mFindings[0].Message);
  Assert.AreEqual(17, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(6, mFindings[0].Range.EndPos.Character);
end;

procedure TFormRulesTests.SelfFreeFixUsesRelease;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
  mTree: TSyntaxTree;
begin
  mSource := Meldung(cClickHeader, '  Free;'#10);
  mFindings := TRuleAssert.FormFindings(TSelfFreeInEventHandlerRule.Create, mSource, cMeldungDfm);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Free durch Release ersetzen', mFindings[0].Fixes[0].Title);
  Assert.IsTrue(mFindings[0].Fixes[0].Safe);
  mFixed := ApplyFix(mSource, mFindings[0].Fixes[0]);
  Assert.AreEqual(Meldung(cClickHeader, '  Release;'#10), mFixed);
  mTree := TPascalParser.Parse(mFixed);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)));
  finally
    mTree.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TSelfFreeInEventHandlerRule.Create, mFixed,
    cMeldungDfm))));
end;

procedure TFormRulesTests.SelfFreeVariants;
var
  mFindings: TArray<TRuleFinding>;
begin
  Assert.AreEqual(1, Integer(Length(SelfFreeFindings(cClickHeader, '  Self.Free;'#10))));
  Assert.AreEqual(1, Integer(Length(SelfFreeFindings(cClickHeader, '  FreeAndNil(Self);'#10))));
  Assert.AreEqual(1, Integer(Length(SelfFreeFindings(cClickHeader, '  frmMeldung.Free;'#10))));
  Assert.AreEqual(1, Integer(Length(SelfFreeFindings(cClickHeader, '  FreeAndNil(frmMeldung);'#10))));
  Assert.AreEqual(1, Integer(Length(SelfFreeFindings(cClickHeader, '  Destroy;'#10))));
  Assert.AreEqual(1, Integer(Length(SelfFreeFindings(cClickHeader, '  if btnOK.Tag = 1 then'#10'    Free;'#10))));
  // Handler, der im Code zugewiesen wird (Sender: TObject), ohne Eintrag in der Formulardatei.
  mFindings := SelfFreeFindings('procedure TfrmMeldung.Weiter(Sender: TObject);', '  Free;'#10);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Das Formular gibt sich im eigenen Ereignis-Handler frei; die VCL greift danach noch darauf zu.',
    mFindings[0].Message);
end;

procedure TFormRulesTests.SelfFreeOnCloseUsesCaFree;
var
  mSource, mHeader: string;
  mFindings: TArray<TRuleFinding>;
begin
  mHeader := 'procedure TfrmMeldung.FormClose(Sender: TObject; var Action: TCloseAction);';
  mSource := Meldung(mHeader, '  Free;'#10);
  mFindings := TRuleAssert.FormFindings(TSelfFreeInEventHandlerRule.Create, mSource, cMeldungDfm);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Das Formular gibt sich im eigenen Close-Handler frei; die VCL greift danach noch darauf zu.',
    mFindings[0].Message);
  Assert.AreEqual('Durch Action := caFree ersetzen', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(Meldung(mHeader, '  Action := caFree;'#10), ApplyFix(mSource, mFindings[0].Fixes[0]));
end;

procedure TFormRulesTests.SelfFreeSilentCases;
const
  cRahmenDfm =
    'object Rahmen: TRahmen'#10 +
    '  Width = 200'#10 +
    '  Height = 100'#10 +
    '  object btnOK: TButton'#10 +
    '    OnClick = btnOKClick'#10 +
    '  end'#10 +
    'end'#10;
begin
  // Keine Ereignismethode, Release, andere Objekte.
  Assert.AreEqual(0, Integer(Length(SelfFreeFindings('procedure TfrmMeldung.Aufraeumen;', '  Free;'#10))));
  Assert.AreEqual(0, Integer(Length(SelfFreeFindings(cClickHeader, '  Release;'#10))));
  Assert.AreEqual(0, Integer(Length(SelfFreeFindings(cClickHeader, '  btnOK.Free;'#10))));
  // Später im Hauptthread bzw. auf das Objekt des with-Blocks.
  Assert.AreEqual(0, Integer(Length(SelfFreeFindings(cClickHeader, '  TThread.ForceQueue(nil,'#10 +
    '    procedure'#10'    begin'#10'      Free;'#10'    end);'#10))));
  Assert.AreEqual(0, Integer(Length(SelfFreeFindings(cClickHeader, '  with TStringList.Create do'#10'    Free;'#10))));
  // Rahmen haben kein Release.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TSelfFreeInEventHandlerRule.Create,
    StringReplace(StringReplace(Meldung(cClickHeader, '  Free;'#10), 'TfrmMeldung', 'TRahmen', [rfReplaceAll]),
    'class(TForm)', 'class(TFrame)', []), cRahmenDfm))));
  // Ohne Formulardatei keine Aussage.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSelfFreeInEventHandlerRule.Create,
    Meldung(cClickHeader, '  Free;'#10)))));
end;

procedure TFormRulesTests.SelfFreeOffAndExclude;
var
  mContext: TRuleContext;
begin
  mContext := Default(TRuleContext);
  mContext.RelativePath := 'Source/Meldung.pas';
  mContext.Text := Meldung(cClickHeader, '  Free;'#10);
  mContext.FormText := cMeldungDfm;
  Assert.AreEqual(1, Integer(Length(TRuleAssert.ContextFindings(TSelfFreeInEventHandlerRule.Create, mContext, ''))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TSelfFreeInEventHandlerRule.Create, mContext,
    '{"rules": {"self-free-in-event-handler": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TSelfFreeInEventHandlerRule.Create, mContext,
    '{"rules": {"self-free-in-event-handler": {"exclude": ["Source/*.pas"]}}}'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TFormRulesTests);

end.
