unit Atlas.Core.Tracker.IssueForms.Tests;

// Issue-Formulare von GitHub (#2137): Lesen der Vorlagen (YAML-Formulare,
// Markdown mit Kopf, config.yml), Reihenfolge, Pflichtfelder, Beschreibung wie
// das Formular von GitHub (### Beschriftung, _No response_), Präfix des
// Titels, Zuordnung und Platzhalter, Auswahl passender Optionen, Vorbelegung
// von Code und Befund und die Adresse für „Im Browser fortsetzen“.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Tracker.IssueForms;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasIssueFormsTests = class
  private
    FForm: TAtlasIssueForm;
    FFacts: TAtlasIssueFormFacts;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ParsesFormWithHeadAndFields;
    [Test]
    procedure ParsesMarkdownTemplateWithHead;
    [Test]
    procedure UnreadableYamlIsUnsupported;
    [Test]
    procedure UnknownFieldTypeIsUnsupported;
    [Test]
    procedure ReadAllSortsAndReadsConfig;
    [Test]
    procedure BlankAllowedWithoutConfig;
    [Test]
    procedure IsFormFileByExtension;
    [Test]
    procedure TitleGetsPrefixOnce;
    [Test]
    procedure MissingNamesRequiredFields;
    [Test]
    procedure BodyLooksLikeGitHubForm;
    [Test]
    procedure BodyOfMarkdownTemplateIsItsText;
    [Test]
    procedure ParseMappingAndMerge;
    [Test]
    procedure ExpandFillsPlaceholders;
    [Test]
    procedure MatchOptionFindsSimilarOption;
    [Test]
    procedure FactsNameDelphiAndIde;
    [Test]
    procedure PrefillUsesMappingAndFacts;
    [Test]
    procedure PrefillPutsCodeIntoRenderedTextarea;
    [Test]
    procedure PrefillKeepsTemplateDefaults;
    [Test]
    procedure LinkFieldsSkipCheckboxes;
    [Test]
    procedure BrowserUrlCarriesValues;
    [Test]
    procedure BrowserUrlNeedsHttps;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Product.Version;

function Lines(const ALines: array of string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(ALines) do
  begin
    Result := Result + ALines[mIndex] + #10;
  end;
end;

/// <summary>Wie .github/ISSUE_TEMPLATE/1-fehler.yml von Atlas, gekürzt, mit Kontrollkästchen.</summary>
function BugForm: string;
begin
  Result := Lines(['name: Fehler', 'description: Atlas verhält sich falsch.', 'title: "Fehler: "',
    'labels: ["bug"]', 'assignees: anna, ben', 'projects: ["beispiel/4"]', 'type: Bug', 'body:',
    '  - type: markdown', '    attributes:', '      value: Bitte den Fehlerbericht anhängen.',
    '  - type: input', '    id: version', '    attributes:', '      label: Atlas-Version',
    '      placeholder: "0.1.0"', '    validations:', '      required: true',
    '  - type: dropdown', '    id: ide', '    attributes:', '      label: Delphi-Version und IDE', '      options:',
    '        - Delphi 13 (32-Bit-IDE)', '        - Delphi 13 (64-Bit-IDE)', '        - Delphi 12 (64-Bit-IDE)',
    '    validations:', '      required: true',
    '  - type: textarea', '    id: steps', '    attributes:', '      label: Schritte', '      value: "1. "',
    '  - type: textarea', '    id: log', '    attributes:', '      label: Log-Auszug', '      render: text',
    '  - type: checkboxes', '    id: terms', '    attributes:', '      label: Bestätigung', '      options:',
    '        - label: Ich habe gesucht', '          required: true', '        - label: Newsletter']);
end;

procedure TAtlasIssueFormsTests.Setup;
begin
  Assert.IsTrue(TAtlasIssueForms.Parse(TAtlasIssueFormFile.Create('1-fehler.yml', BugForm), FForm));
  FFacts := Default(TAtlasIssueFormFacts);
  FFacts.Version := '2.2.0';
  FFacts.Ide := 'Delphi 13 (64-Bit-IDE)';
end;

procedure TAtlasIssueFormsTests.TearDown;
begin
  FForm := TAtlasIssueForm.Empty;
  FFacts := Default(TAtlasIssueFormFacts);
end;

procedure TAtlasIssueFormsTests.ParsesFormWithHeadAndFields;
begin
  Assert.AreEqual('1-fehler.yml', FForm.FileName);
  Assert.AreEqual('Fehler', FForm.Name);
  Assert.AreEqual('Atlas verhält sich falsch.', FForm.About);
  Assert.AreEqual('Fehler: ', FForm.TitlePrefix);
  Assert.AreEqual('bug', string.Join(',', FForm.Labels));
  Assert.AreEqual('anna,ben', string.Join(',', FForm.Assignees), 'labels/assignees auch als Text mit Komma');
  Assert.AreEqual('beispiel/4', string.Join(',', FForm.Projects));
  Assert.AreEqual('Bug', FForm.IssueType);
  Assert.IsFalse(FForm.IsMarkdown);
  Assert.IsFalse(FForm.Unsupported);
  Assert.AreEqual(6, Integer(Length(FForm.Fields)));
  Assert.AreEqual<TAtlasIssueFormKind>(TAtlasIssueFormKind.Markdown, FForm.Fields[0].Kind);
  Assert.IsFalse(FForm.Fields[0].Editable);
  Assert.AreEqual('Bitte den Fehlerbericht anhängen.', FForm.Fields[0].Value);
  Assert.AreEqual('version', FForm.Fields[1].Id);
  Assert.IsTrue(FForm.Fields[1].Required);
  Assert.AreEqual('0.1.0', FForm.Fields[1].Placeholder);
  Assert.AreEqual(3, Integer(Length(FForm.Fields[2].Options)));
  Assert.AreEqual(-1, FForm.Fields[2].DefaultIndex);
  Assert.AreEqual('text', FForm.Fields[4].Render);
  Assert.IsTrue(FForm.Fields[5].OptionRequired[0]);
  Assert.IsFalse(FForm.Fields[5].OptionRequired[1]);
end;

procedure TAtlasIssueFormsTests.ParsesMarkdownTemplateWithHead;
var
  mForm: TAtlasIssueForm;
begin
  Assert.IsTrue(TAtlasIssueForms.Parse(TAtlasIssueFormFile.Create('wunsch.md', Lines(['---', 'name: Wunsch',
    'about: Neue Funktion', 'title: "[Wunsch] "', 'labels: enhancement', '---', '', '## Was fehlt?', '',
    'Text'])), mForm));
  Assert.IsTrue(mForm.IsMarkdown);
  Assert.AreEqual('Wunsch', mForm.Name);
  Assert.AreEqual('Neue Funktion', mForm.About);
  Assert.AreEqual('[Wunsch] ', mForm.TitlePrefix);
  Assert.AreEqual('enhancement', string.Join(',', mForm.Labels));
  Assert.AreEqual('## Was fehlt?' + #10#10 + 'Text', mForm.Body);
  Assert.AreEqual(0, Integer(Length(mForm.Fields)));
end;

procedure TAtlasIssueFormsTests.UnreadableYamlIsUnsupported;
var
  mForm: TAtlasIssueForm;
begin
  Assert.IsTrue(TAtlasIssueForms.Parse(TAtlasIssueFormFile.Create('a.yml', 'name: &a x' + #10 + 'body: *a'),
    mForm));
  Assert.IsTrue(mForm.Unsupported);
  Assert.AreEqual('a', mForm.Name, 'ohne Namen der Dateiname');
  Assert.IsFalse(TAtlasIssueForms.Parse(TAtlasIssueFormFile.Create('b.yml', 'name: ohne body'), mForm),
    'Formular ohne body ist keine Vorlage');
end;

procedure TAtlasIssueFormsTests.UnknownFieldTypeIsUnsupported;
var
  mForm: TAtlasIssueForm;
begin
  Assert.IsTrue(TAtlasIssueForms.Parse(TAtlasIssueFormFile.Create('c.yml', Lines(['name: C', 'body:',
    '  - type: upload', '    id: datei', '  - type: input', '    id: x', '    attributes:', '      label: X'])),
    mForm));
  Assert.IsTrue(mForm.Unsupported);
  Assert.AreEqual(1, Integer(Length(mForm.Fields)), 'bekannte Felder bleiben');
end;

procedure TAtlasIssueFormsTests.ReadAllSortsAndReadsConfig;
var
  mForms: TArray<TAtlasIssueForm>;
  mBlank: Boolean;
begin
  mForms := TAtlasIssueForms.ReadAll([TAtlasIssueFormFile.Create('3-wunsch.md', 'Text'),
    TAtlasIssueFormFile.Create('config.yml', 'blank_issues_enabled: false'),
    TAtlasIssueFormFile.Create('1-fehler.yml', BugForm), TAtlasIssueFormFile.Create('liesmich.txt', 'x')], mBlank);
  Assert.IsFalse(mBlank);
  Assert.AreEqual(2, Integer(Length(mForms)));
  Assert.AreEqual('1-fehler.yml', mForms[0].FileName);
  Assert.AreEqual('3-wunsch.md', mForms[1].FileName);
end;

procedure TAtlasIssueFormsTests.BlankAllowedWithoutConfig;
var
  mBlank: Boolean;
begin
  TAtlasIssueForms.ReadAll([TAtlasIssueFormFile.Create('1-fehler.yml', BugForm)], mBlank);
  Assert.IsTrue(mBlank);
  Assert.IsTrue(TAtlasIssueForms.BlankAllowed('contact_links: []'));
  Assert.IsFalse(TAtlasIssueForms.BlankAllowed('blank_issues_enabled: false'));
end;

procedure TAtlasIssueFormsTests.IsFormFileByExtension;
begin
  Assert.IsTrue(TAtlasIssueForms.IsFormFile('a.YML'));
  Assert.IsTrue(TAtlasIssueForms.IsFormFile('a.yaml'));
  Assert.IsTrue(TAtlasIssueForms.IsFormFile('a.md'));
  Assert.IsFalse(TAtlasIssueForms.IsFormFile('config.yml'));
  Assert.IsFalse(TAtlasIssueForms.IsFormFile('a.txt'));
  Assert.IsTrue(TAtlasIssueForms.IsConfigFile('Config.yml'));
end;

procedure TAtlasIssueFormsTests.TitleGetsPrefixOnce;
begin
  Assert.AreEqual('Fehler: Absturz', TAtlasIssueForms.TitleOf(FForm, 'Absturz'));
  Assert.AreEqual('Fehler: Absturz', TAtlasIssueForms.TitleOf(FForm, 'Fehler: Absturz'));
  Assert.AreEqual('Absturz', TAtlasIssueForms.TitleOf(TAtlasIssueForm.Empty, 'Absturz'));
end;

procedure TAtlasIssueFormsTests.MissingNamesRequiredFields;
var
  mAnswers: TAtlasIssueFormAnswers;
begin
  SetLength(mAnswers, Length(FForm.Fields));
  Assert.AreEqual('Atlas-Version, Delphi-Version und IDE, Ich habe gesucht',
    string.Join(', ', TAtlasIssueForms.Missing(FForm, mAnswers)));
  mAnswers[1].Text := '2.2.0';
  mAnswers[2].Chosen := [1];
  mAnswers[5].Chosen := [0];
  Assert.AreEqual(0, Integer(Length(TAtlasIssueForms.Missing(FForm, mAnswers))));
end;

procedure TAtlasIssueFormsTests.BodyLooksLikeGitHubForm;
var
  mAnswers: TAtlasIssueFormAnswers;
begin
  SetLength(mAnswers, Length(FForm.Fields));
  mAnswers[1].Text := '2.2.0';
  mAnswers[2].Chosen := [1];
  mAnswers[4].Text := 'Zeile 1' + #13#10 + 'Zeile 2';
  mAnswers[5].Chosen := [0];
  Assert.AreEqual('### Atlas-Version' + #10#10 + '2.2.0' + #10#10 +
    '### Delphi-Version und IDE' + #10#10 + 'Delphi 13 (64-Bit-IDE)' + #10#10 +
    '### Schritte' + #10#10 + '_No response_' + #10#10 +
    '### Log-Auszug' + #10#10 + '```text' + #10 + 'Zeile 1' + #10 + 'Zeile 2' + #10 + '```' + #10#10 +
    '### Bestätigung' + #10#10 + '- [X] Ich habe gesucht' + #10 + '- [ ] Newsletter',
    TAtlasIssueForms.Body(FForm, mAnswers));
end;

procedure TAtlasIssueFormsTests.BodyOfMarkdownTemplateIsItsText;
var
  mForm: TAtlasIssueForm;
begin
  TAtlasIssueForms.Parse(TAtlasIssueFormFile.Create('w.md', '## Was fehlt?'), mForm);
  Assert.AreEqual('## Was fehlt?', TAtlasIssueForms.Body(mForm, nil));
end;

procedure TAtlasIssueFormsTests.ParseMappingAndMerge;
var
  mItems: TAtlasIssueFormMappings;
begin
  mItems := TAtlasIssueForms.ParseMapping('version={version}; ide = {ide}' + #10 + 'log={finding}\n{code};' +
    ' =leer; ohneGleich');
  Assert.AreEqual(3, Integer(Length(mItems)));
  Assert.AreEqual('ide', mItems[1].Id);
  Assert.AreEqual('{ide}', mItems[1].Value);
  Assert.AreEqual('{finding}' + #10 + '{code}', mItems[2].Value);
  mItems := TAtlasIssueForms.Merge(mItems, [TAtlasIssueFormMapping.Create('IDE', 'fest'),
    TAtlasIssueFormMapping.Create('steps', '{code}')]);
  Assert.AreEqual(4, Integer(Length(mItems)));
  Assert.AreEqual('fest', mItems[1].Value, 'Überschreiben ohne Groß-/Kleinschreibung');
  Assert.AreEqual('steps', mItems[3].Id);
end;

procedure TAtlasIssueFormsTests.ExpandFillsPlaceholders;
begin
  FFacts.Code := 'X := 1;';
  FFacts.Finding := 'Unit1.pas, Zeile 3';
  Assert.AreEqual('Atlas 2.2.0 in Delphi 13 (64-Bit-IDE)',
    TAtlasIssueForms.Expand('Atlas {VERSION} in {ide}', FFacts, False));
  Assert.AreEqual('```pascal' + #10 + 'X := 1;' + #10 + '```', TAtlasIssueForms.Expand('{code}', FFacts, False));
  Assert.AreEqual('X := 1;', TAtlasIssueForms.Expand('{code}', FFacts, True), 'im Codeblock roh');
  Assert.AreEqual('Unit1.pas, Zeile 3' + #10#10 + 'X := 1;', TAtlasIssueForms.Expand('{log}', FFacts, True));
end;

procedure TAtlasIssueFormsTests.MatchOptionFindsSimilarOption;
var
  mOptions: TArray<string>;
begin
  mOptions := TArray<string>.Create('Delphi 13 (32-Bit-IDE)', 'Delphi 13 (64-Bit-IDE)', 'Delphi 12 (64-Bit-IDE)');
  Assert.AreEqual(1, TAtlasIssueForms.MatchOption(mOptions, 'delphi 13 (64-bit-ide)'));
  Assert.AreEqual(2, TAtlasIssueForms.MatchOption(mOptions, 'Delphi 12 64'));
  Assert.AreEqual(1, TAtlasIssueForms.MatchOption(mOptions, 'RAD Studio 13, 64 Bit'));
  Assert.AreEqual(-1, TAtlasIssueForms.MatchOption(mOptions, 'Delphi 11'));
end;

procedure TAtlasIssueFormsTests.FactsNameDelphiAndIde;
var
  mFacts: TAtlasIssueFormFacts;
begin
  mFacts := TAtlasIssueFormFacts.Create(37.0, 64);
  Assert.AreEqual(string(TAtlasPluginVersion.cVersion), mFacts.Version);
  Assert.AreEqual('Delphi 13 (64-Bit-IDE)', mFacts.Ide);
  Assert.AreEqual('', mFacts.Code);
  Assert.AreEqual('Delphi 12 (32-Bit-IDE)', TAtlasIssueFormFacts.Create(36.0, 32).Ide);
end;

procedure TAtlasIssueFormsTests.PrefillUsesMappingAndFacts;
var
  mAnswers: TAtlasIssueFormAnswers;
begin
  FFacts.Code := 'X := 1;';
  mAnswers := TAtlasIssueForms.Prefill(FForm, TAtlasIssueForms.ParseMapping(TAtlasIssueForms.cDefaultMapping),
    FFacts);
  Assert.AreEqual(6, Integer(Length(mAnswers)));
  Assert.AreEqual('2.2.0', mAnswers[1].Text);
  Assert.AreEqual(1, Integer(Length(mAnswers[2].Chosen)));
  Assert.AreEqual(1, mAnswers[2].Chosen[0]);
  Assert.AreEqual('X := 1;', mAnswers[4].Text, 'log mit render: Code roh');
  Assert.AreEqual('1. ', mAnswers[3].Text, 'Vorgabe der Vorlage bleibt');
end;

procedure TAtlasIssueFormsTests.PrefillPutsCodeIntoRenderedTextarea;
var
  mAnswers: TAtlasIssueFormAnswers;
begin
  FFacts.Code := 'X := 1;';
  FFacts.Finding := 'Unit1.pas, Zeile 3';
  mAnswers := TAtlasIssueForms.Prefill(FForm, nil, FFacts);
  Assert.AreEqual('Unit1.pas, Zeile 3' + #10#10 + 'X := 1;', mAnswers[4].Text,
    'ohne Zuordnung ins erste textarea mit render');
  Assert.AreEqual('', mAnswers[1].Text);
end;

procedure TAtlasIssueFormsTests.PrefillKeepsTemplateDefaults;
var
  mForm: TAtlasIssueForm;
  mAnswers: TAtlasIssueFormAnswers;
begin
  TAtlasIssueForms.Parse(TAtlasIssueFormFile.Create('d.yml', Lines(['name: D', 'body:', '  - type: dropdown',
    '    id: art', '    attributes:', '      label: Art', '      options: [a, b, c]', '      default: 2'])), mForm);
  mAnswers := TAtlasIssueForms.Prefill(mForm, nil, FFacts);
  Assert.AreEqual(2, mAnswers[0].Chosen[0]);
end;

procedure TAtlasIssueFormsTests.LinkFieldsSkipCheckboxes;
var
  mAnswers: TAtlasIssueFormAnswers;
  mFields: TAtlasIssueFormMappings;
begin
  SetLength(mAnswers, Length(FForm.Fields));
  mAnswers[1].Text := '2.2.0';
  mAnswers[2].Chosen := [0];
  mAnswers[5].Chosen := [0];
  mFields := TAtlasIssueForms.LinkFields(FForm, mAnswers);
  Assert.AreEqual(2, Integer(Length(mFields)));
  Assert.AreEqual('version', mFields[0].Id);
  Assert.AreEqual('Delphi 13 (32-Bit-IDE)', mFields[1].Value);
end;

procedure TAtlasIssueFormsTests.BrowserUrlCarriesValues;
var
  mLink: TAtlasIssueFormLink;
begin
  mLink := TAtlasIssueFormLink.Empty;
  mLink.Repository := 'https://github.com/beispiel/atlas/';
  mLink.Template := '1-fehler.yml';
  mLink.Title := 'Fehler: A & B';
  mLink.Labels := TArray<string>.Create('bug', 'ui');
  mLink.Milestone := 'v2.2.0';
  mLink.IssueType := 'Bug';
  mLink.Fields := [TAtlasIssueFormMapping.Create('version', '2.2.0')];
  Assert.AreEqual('https://github.com/beispiel/atlas/issues/new?template=1-fehler.yml' +
    '&title=Fehler%3A%20A%20%26%20B&labels=bug%2Cui&milestone=v2.2.0&type=Bug&version=2.2.0',
    TAtlasIssueForms.BrowserUrl(mLink));
end;

procedure TAtlasIssueFormsTests.BrowserUrlNeedsHttps;
var
  mLink: TAtlasIssueFormLink;
begin
  mLink := TAtlasIssueFormLink.Empty;
  mLink.Repository := 'http://github.com/beispiel/atlas';
  Assert.AreEqual('', TAtlasIssueForms.BrowserUrl(mLink));
  mLink.Repository := 'https://github.com/beispiel/atlas';
  Assert.AreEqual('https://github.com/beispiel/atlas/issues/new', TAtlasIssueForms.BrowserUrl(mLink));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIssueFormsTests);

end.
