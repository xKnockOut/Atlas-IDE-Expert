unit Atlas.UI.Tracker.NewIssueDialog.Tests;

// Tests des Dialogs „Issue anlegen“ (#1268) ohne Netz: Vorbelegung, Häkchen
// „Codeausschnitt“ nach issues.create.includeCode, nichts gesendet ohne Klick
// auf „Anlegen“, Fehler lässt den Dialog offen, Listen vom Tracker und ein
// später Rückruf nach dem Schließen. GitHub (#2137): Vorlagen mit
// Formularfeldern, Pflichtfelder vor dem Senden, Meilenstein, Issue-Typ,
// Issue-Felder und „Im Browser fortsetzen“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasNewIssueDialogTests = class
  public
    /// <summary>Abnahme: Mit issues.create.includeCode aus ist der Codeausschnitt nicht vorausgewählt.</summary>
    [Test]
    procedure IncludeCodeFollowsSetting;
    /// <summary>Abnahme: Ohne Klick auf „Anlegen“ wird nichts gesendet; ein Fehler (403) lässt den Dialog offen.
    /// </summary>
    [Test]
    procedure SendOnlyOnClick;
    [Test]
    procedure TrackersAndFields;
    [Test]
    procedure ResultTextPerOutcome;
    [Test]
    procedure TemplateWithFormFields;
    [Test]
    procedure RequiredFieldsBlockSending;
    [Test]
    procedure MilestoneTypeAndIssueFields;
    [Test]
    procedure BrowserLinkWithTemplateValues;
    [Test]
    procedure WithoutGitHubDataRowsStayHidden;
  end;

implementation

uses
  System.SysUtils,
  System.UITypes,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.NewIssue,
  Atlas.Core.Tracker.IssueForms,
  Atlas.Core.Tracker.NewIssueGitHub,
  Atlas.UI.Tracker.NewIssue.Strings,
  Atlas.UI.Tracker.NewIssueDialog;

function Setup(AIncludeCode: Boolean): TAtlasNewIssueSetup;
begin
  Result := TAtlasNewIssueSetup.Empty;
  Result.Trackers := [TAtlasNewIssueTracker.Create('Firma (YouTrack · https://yt.local)',
    TAtlasTrackerTarget.Create('youtrack', 'https://yt.local', 'ATL', '')),
    TAtlasNewIssueTracker.Create('Privat (GitHub · https://github.com)',
    TAtlasTrackerTarget.Create('github', 'https://github.com', '', ''))];
  Result.TrackerIndex := 0;
  Result.Title := 'Speicherleck beim Schließen';
  Result.Description := 'Fundstelle: `Main.pas`, Zeile 3';
  Result.Code := '// TODO Speicherleck beim Schließen';
  Result.IncludeCode := AIncludeCode;
  Result.CanStart := False;
end;

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

/// <summary>GitHub-Tracker gewählt, Fakten und Zuordnung wie im Plugin; AOnSend zählt bzw. merkt.</summary>
function GitHubSetup: TAtlasNewIssueSetup;
begin
  Result := Setup(True);
  Result.Trackers := [TAtlasNewIssueTracker.Create('GitHub',
    TAtlasTrackerTarget.Create('github', 'https://github.com', 'acme/kasse', ''))];
  Result.TrackerIndex := 0;
  Result.Facts.Version := '2.2.0';
  Result.Facts.Ide := 'Delphi 13 (64-Bit-IDE)';
  Result.Mappings := TAtlasIssueForms.ParseMapping(TAtlasIssueForms.cDefaultMapping);
end;

/// <summary>Vorlagen „Fehler“ (Formular mit Pflichtfeldern) und „Wunsch“ (Markdown), ohne leeres Issue.
/// </summary>
function GitHubFields: TAtlasNewIssueFields;
var
  mBlank: Boolean;
begin
  Result := TAtlasNewIssueFields.Empty;
  Result.GitHub.Forms := TAtlasIssueForms.ReadAll([TAtlasIssueFormFile.Create('1-fehler.yml', Lines(['name: Fehler',
    'title: "Fehler: "', 'labels: ["bug"]', 'type: Bug', 'body:', '  - type: input', '    id: version',
    '    attributes:', '      label: Atlas-Version', '    validations:', '      required: true',
    '  - type: dropdown', '    id: ide', '    attributes:', '      label: IDE', '      options:',
    '        - Delphi 12 (64-Bit-IDE)', '        - Delphi 13 (64-Bit-IDE)', '  - type: textarea', '    id: steps',
    '    attributes:', '      label: Schritte', '    validations:', '      required: true', '  - type: textarea',
    '    id: log', '    attributes:', '      label: Log', '      render: text'])),
    TAtlasIssueFormFile.Create('2-wunsch.md', Lines(['---', 'name: Wunsch', 'title: "[Wunsch] "', '---',
    '## Was fehlt?'])), TAtlasIssueFormFile.Create('config.yml', 'blank_issues_enabled: false')], mBlank);
  Result.GitHub.BlankAllowed := mBlank;
end;

{ TAtlasNewIssueDialogTests }

procedure TAtlasNewIssueDialogTests.IncludeCodeFollowsSetting;
var
  mDialog: TAtlasNewIssueDialog;
begin
  mDialog := TAtlasNewIssueDialog.CreateDialog(nil, Setup(False), nil, nil);
  try
    Assert.IsFalse(mDialog.Parts.IncludeCodeBox.Checked, 'nicht vorausgewählt');
    Assert.IsFalse(mDialog.Parts.CodeMemo.Enabled);
    Assert.AreEqual('Fundstelle: `Main.pas`, Zeile 3', mDialog.Draft.Description, 'ohne Code');
    mDialog.Parts.IncludeCodeBox.Checked := True;
    Assert.IsTrue(mDialog.Parts.CodeMemo.Enabled);
    Assert.IsTrue(mDialog.Draft.Description.EndsWith('```pascal' + #10 + '// TODO Speicherleck beim Schließen' + #10 +
      '```'), mDialog.Draft.Description);
    Assert.IsFalse(mDialog.Parts.StartNowBox.Enabled, '„gleich beginnen“ nur mit „Meine Issues“');
  finally
    mDialog.Free;
  end;
  mDialog := TAtlasNewIssueDialog.CreateDialog(nil, Setup(True), nil, nil);
  try
    Assert.IsTrue(mDialog.Parts.IncludeCodeBox.Checked, 'Vorgabe an');
    Assert.IsTrue(mDialog.Draft.Description.Contains('```pascal'));
    Assert.IsFalse(mDialog.Parts.CreateButton.Enabled, 'ohne Haken OnSend kein Anlegen');
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasNewIssueDialogTests.SendOnlyOnClick;
var
  mDialog: TAtlasNewIssueDialog;
  mSent: Integer;
  mTarget: TAtlasTrackerTarget;
  mDraft: TAtlasNewIssueDraft;
  mDone: TAtlasNewIssueSendDone;
  mResult: TAtlasNewIssueResult;
begin
  mSent := 0;
  mDone := nil;
  mDialog := TAtlasNewIssueDialog.CreateDialog(nil, Setup(True), nil,
    procedure(const ATarget: TAtlasTrackerTarget; const ADraft: TAtlasNewIssueDraft;
      const ADone: TAtlasNewIssueSendDone)
    begin
      Inc(mSent);
      mTarget := ATarget;
      mDraft := ADraft;
      mDone := ADone;
    end);
  try
    mDialog.Parts.TypeBox.Text := 'Bug';
    mDialog.Parts.AssignToMeBox.Checked := True;
    Assert.IsFalse(mDialog.Parts.AssigneeBox.Enabled, '„mir zuweisen“ ersetzt Zuständig');
    Assert.AreEqual(0, mSent, 'nichts ohne Klick');
    Assert.IsTrue(mDialog.Parts.CreateButton.Enabled);
    mDialog.Parts.ProjectEdit.Text := 'KASSE';
    mDialog.Parts.CreateButton.Click;
    Assert.AreEqual(1, mSent);
    Assert.IsTrue(mDialog.Sending);
    Assert.IsFalse(mDialog.Parts.CreateButton.Enabled, 'kein zweites Senden');
    Assert.IsFalse(mDialog.Parts.CancelButton.Enabled, 'nicht schließen, solange gesendet wird');
    Assert.AreEqual('KASSE', mTarget.Project, 'Projekt aus dem Feld');
    Assert.AreEqual('Speicherleck beim Schließen', mDraft.Title);
    Assert.AreEqual('Bug', mDraft.IssueType);
    Assert.IsTrue(mDraft.AssignToMe);
    // 403: Dialog bleibt offen und nennt die Ursache.
    mResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.Rejected);
    mResult.HttpStatus := 403;
    mDone(mResult);
    Assert.IsFalse(mDialog.Sending);
    Assert.AreEqual(Integer(mrNone), Integer(mDialog.ModalResult), 'offen');
    Assert.AreEqual(TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueRejected, [403]),
      mDialog.Parts.StatusLabel.Caption);
    Assert.IsTrue(mDialog.Parts.CreateButton.Enabled, 'erneut versuchen');
    // Erfolg: schließt mit OK und merkt das Ergebnis.
    mDialog.Parts.CreateButton.Click;
    mResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.Created);
    mResult.Key := 'ATL-130';
    mDone(mResult);
    Assert.AreEqual(Integer(mrOk), Integer(mDialog.ModalResult));
    Assert.AreEqual('ATL-130', mDialog.IssueResult.Key);
  finally
    mDialog.Free;
  end;
  // Ein später Rückruf nach dem Schließen verfällt.
  mDone(mResult);
  mDone := nil;
end;

procedure TAtlasNewIssueDialogTests.TrackersAndFields;
var
  mDialog: TAtlasNewIssueDialog;
  mTarget: TAtlasTrackerTarget;
  mFields: TAtlasNewIssueFields;
  mLoads: Integer;
  mSetup: TAtlasNewIssueSetup;
begin
  mLoads := 0;
  mDialog := TAtlasNewIssueDialog.CreateDialog(nil, Setup(True),
    procedure(const ATarget: TAtlasTrackerTarget; const ADone: TAtlasNewIssueFieldsDone)
    begin
      Inc(mLoads);
    end, nil);
  try
    Assert.AreEqual('ATL', mDialog.Parts.ProjectEdit.Text, 'Projekt aus der Zuordnung');
    Assert.IsTrue(mDialog.Target(mTarget));
    Assert.AreEqual('youtrack', mTarget.Provider);
    // Wechsel des Trackers: Projekt des Eintrags, Listen neu.
    mDialog.Parts.TrackerBox.Choice := 1;
    mDialog.Parts.TrackerBox.OnChange(mDialog.Parts.TrackerBox);
    Assert.AreEqual('', mDialog.Parts.ProjectEdit.Text);
    Assert.AreEqual(0, mLoads, 'GitHub ohne owner/repo: nichts zu laden');
    mDialog.Parts.ProjectEdit.Text := 'acme/kasse';
    Assert.IsTrue(mDialog.Target(mTarget));
    Assert.AreEqual('acme/kasse', mTarget.Project);
    mDialog.LoadFields;
    Assert.AreEqual(1, mLoads);
    // Listen übernehmen; was eingetippt ist, bleibt.
    mDialog.Parts.TypeBox.Text := 'eigener Typ';
    mFields := TAtlasNewIssueFields.Empty;
    mFields.TypeField := 'Typ';
    mFields.Types := TArray<string>.Create('Fehler', 'Aufgabe');
    mDialog.ShowFields(mFields, True);
    Assert.AreEqual('Fehler,Aufgabe', string.Join(',', mDialog.Parts.TypeBox.Values));
    Assert.AreEqual('eigener Typ', mDialog.Parts.TypeBox.Text);
    Assert.AreEqual('Typ', mDialog.Draft.TypeField);
    mDialog.ShowFields(TAtlasNewIssueFields.Empty, False);
    Assert.AreEqual(TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueLoadFailed),
      mDialog.Parts.StatusLabel.Caption);
  finally
    mDialog.Free;
  end;
  // Ohne Tracker: Hinweis, kein Anlegen.
  mSetup := TAtlasNewIssueSetup.Empty;
  mSetup.Title := 'x';
  mDialog := TAtlasNewIssueDialog.CreateDialog(nil, mSetup, nil,
    procedure(const ATarget: TAtlasTrackerTarget; const ADraft: TAtlasNewIssueDraft;
      const ADone: TAtlasNewIssueSendDone)
    begin
    end);
  try
    Assert.IsFalse(mDialog.Parts.CreateButton.Enabled);
    Assert.AreEqual(TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueNoTracker),
      mDialog.Parts.StatusLabel.Caption);
  finally
    mDialog.Free;
  end;
  mFields := TAtlasNewIssueFields.Empty;
end;

procedure TAtlasNewIssueDialogTests.ResultTextPerOutcome;
var
  mResult: TAtlasNewIssueResult;
begin
  mResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.NoToken);
  Assert.AreEqual(TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueNoToken, ['https://yt.local']),
    TAtlasNewIssueDialog.ResultText(mResult, 'ATL', 'https://yt.local'));
  mResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.ProjectUnknown);
  Assert.AreEqual(TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueProjectUnknown, ['ATL']),
    TAtlasNewIssueDialog.ResultText(mResult, 'ATL', ''));
  mResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.Invalid);
  mResult.TrackerMessage := 'Validation Failed';
  Assert.AreEqual(TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueInvalid, ['Validation Failed']),
    TAtlasNewIssueDialog.ResultText(mResult, '', ''));
  mResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.Unreachable);
  Assert.AreEqual(TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueUnreachable),
    TAtlasNewIssueDialog.ResultText(mResult, '', ''));
end;

procedure TAtlasNewIssueDialogTests.TemplateWithFormFields;
var
  mDialog: TAtlasNewIssueDialog;
  mDraft: TAtlasNewIssueDraft;
begin
  mDialog := TAtlasNewIssueDialog.CreateDialog(nil, GitHubSetup, nil, nil);
  try
    mDialog.ShowFields(GitHubFields, True);
    Assert.IsTrue(mDialog.Parts.TemplateBox.Visible, 'Zeile „Vorlage“ mit Vorlagen');
    Assert.AreEqual('Fehler,Wunsch', string.Join(',', mDialog.Parts.TemplateBox.Values), 'ohne „Leeres Issue“');
    Assert.AreEqual(0, mDialog.Parts.TemplateBox.Choice);
    Assert.AreEqual('Fehler: Speicherleck beim Schließen', mDialog.Parts.TitleEdit.Text);
    Assert.IsTrue(mDialog.Parts.FormPanel.Visible);
    Assert.AreEqual('2.2.0', mDialog.Parts.FormPanel.Inputs[0].Edit.Text, 'version={version}');
    Assert.AreEqual(1, mDialog.Parts.FormPanel.Inputs[1].Box.Choice - mDialog.Parts.FormPanel.Inputs[1].BoxOffset,
      'Delphi 13 (64-Bit-IDE)');
    Assert.IsTrue(mDialog.Parts.FormPanel.Inputs[3].Memo.Text.Contains('// TODO Speicherleck'),
      'Code ins textarea mit render');
    mDialog.Parts.FormPanel.Inputs[2].Memo.Text := 'Öffnen und schließen';
    mDraft := mDialog.Draft;
    Assert.IsTrue(mDraft.Description.StartsWith('### Atlas-Version' + #10#10 + '2.2.0'), mDraft.Description);
    Assert.IsTrue(mDraft.Description.Contains('### Schritte' + #10#10 + 'Öffnen und schließen'));
    Assert.AreEqual('bug', string.Join(',', mDraft.GitHub.Labels));
    Assert.AreEqual('', mDraft.GitHub.IssueType, 'ohne Issue-Typen des Repositorys kein type');
    // Wechsel auf die Markdown-Vorlage: Präfix getauscht, ihr Text in der Beschreibung.
    mDialog.Parts.TemplateBox.Choice := 1;
    mDialog.Parts.TemplateBox.OnChange(mDialog.Parts.TemplateBox);
    Assert.AreEqual('[Wunsch] Speicherleck beim Schließen', mDialog.Parts.TitleEdit.Text);
    Assert.IsFalse(mDialog.Parts.FormPanel.Visible);
    Assert.IsTrue(mDialog.Parts.DescriptionMemo.Text.StartsWith('## Was fehlt?'));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasNewIssueDialogTests.RequiredFieldsBlockSending;
var
  mDialog: TAtlasNewIssueDialog;
  mSent: Integer;
begin
  mSent := 0;
  mDialog := TAtlasNewIssueDialog.CreateDialog(nil, GitHubSetup, nil,
    procedure(const ATarget: TAtlasTrackerTarget; const ADraft: TAtlasNewIssueDraft;
      const ADone: TAtlasNewIssueSendDone)
    begin
      Inc(mSent);
    end);
  try
    mDialog.ShowFields(GitHubFields, True);
    mDialog.Parts.FormPanel.Inputs[0].Edit.Text := '';
    mDialog.Parts.CreateButton.Click;
    Assert.AreEqual(0, mSent, 'Pflichtfelder fehlen');
    Assert.AreEqual(TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueRequiredMany, ['Atlas-Version, Schritte']),
      mDialog.Parts.StatusLabel.Caption);
    mDialog.Parts.FormPanel.Inputs[0].Edit.Text := '2.2.0';
    mDialog.Parts.CreateButton.Click;
    Assert.AreEqual(TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueRequired, ['Schritte']),
      mDialog.Parts.StatusLabel.Caption);
    mDialog.Parts.FormPanel.Inputs[2].Memo.Text := 'Öffnen';
    mDialog.Parts.CreateButton.Click;
    Assert.AreEqual(1, mSent);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasNewIssueDialogTests.MilestoneTypeAndIssueFields;
var
  mDialog: TAtlasNewIssueDialog;
  mFields: TAtlasNewIssueFields;
  mField: TAtlasGitHubIssueField;
  mDraft: TAtlasNewIssueDraft;
begin
  mFields := GitHubFields;
  mFields.Types := TArray<string>.Create('bug', 'docs');
  mFields.GitHub.IssueTypes := TArray<string>.Create('Bug', 'Task');
  mFields.GitHub.Milestones := [TAtlasGitHubMilestone.Create(3, 'v2.2.0'), TAtlasGitHubMilestone.Create(5, 'v2.3.0')];
  mField := Default(TAtlasGitHubIssueField);
  mField.Id := 12;
  mField.Name := 'Aufwand';
  mField.Kind := TAtlasIssueFieldKind.Number;
  mFields.GitHub.Fields := [mField];
  mDialog := TAtlasNewIssueDialog.CreateDialog(nil, GitHubSetup, nil, nil);
  try
    mDialog.ShowFields(mFields, True);
    Assert.AreEqual('Bug,Task', string.Join(',', mDialog.Parts.TypeBox.Values), 'Issue-Typen statt Labels');
    Assert.AreEqual('Bug', mDialog.Parts.TypeBox.Text, 'Typ der Vorlage');
    Assert.IsTrue(mDialog.Parts.MilestoneBox.Visible);
    Assert.AreEqual(TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueNone) + ',v2.2.0,v2.3.0',
      string.Join(',', mDialog.Parts.MilestoneBox.Values));
    mDialog.Parts.MilestoneBox.Choice := 2;
    Assert.AreEqual(1, Integer(Length(mDialog.Parts.FieldRows.Edits)));
    mDialog.Parts.FieldRows.Edits[0].Text := 'viel';
    Assert.AreEqual('Aufwand', mDialog.Parts.FieldRows.InvalidField);
    mDialog.Parts.FieldRows.Edits[0].Text := '3';
    mDraft := mDialog.Draft;
    Assert.AreEqual('Bug', mDraft.GitHub.IssueType);
    Assert.AreEqual('', mDraft.IssueType, 'kein Label für den Typ');
    Assert.AreEqual(5, mDraft.GitHub.Milestone);
    Assert.AreEqual(1, Integer(Length(mDraft.GitHub.FieldValues)));
    Assert.AreEqual('3', mDraft.GitHub.FieldValues[0].Value);
  finally
    mDialog.Free;
  end;
  mFields := TAtlasNewIssueFields.Empty;
end;

procedure TAtlasNewIssueDialogTests.BrowserLinkWithTemplateValues;
var
  mDialog: TAtlasNewIssueDialog;
  mSetup: TAtlasNewIssueSetup;
  mOpened: string;
begin
  mOpened := '';
  mSetup := GitHubSetup;
  mSetup.OnBrowse :=
    procedure(AUrl: string)
    begin
      mOpened := AUrl;
    end;
  mDialog := TAtlasNewIssueDialog.CreateDialog(nil, mSetup, nil, nil);
  try
    mDialog.ShowFields(GitHubFields, True);
    Assert.IsTrue(mDialog.Parts.BrowseButton.Enabled);
    mDialog.Parts.BrowseButton.Click;
    Assert.IsTrue(mOpened.StartsWith('https://github.com/acme/kasse/issues/new?template=1-fehler.yml&title=Fehler'),
      mOpened);
    Assert.IsTrue(mOpened.Contains('&version=2.2.0'), mOpened);
    Assert.IsFalse(mOpened.Contains('&labels='), 'Labels setzt das Formular von GitHub selbst');
  finally
    mDialog.Free;
  end;
  mSetup := TAtlasNewIssueSetup.Empty;
end;

procedure TAtlasNewIssueDialogTests.WithoutGitHubDataRowsStayHidden;
var
  mDialog: TAtlasNewIssueDialog;
begin
  mDialog := TAtlasNewIssueDialog.CreateDialog(nil, Setup(True), nil, nil);
  try
    mDialog.ShowFields(TAtlasNewIssueFields.Empty, True);
    Assert.IsFalse(mDialog.Parts.TemplateBox.Visible, 'YouTrack: keine Vorlagen');
    Assert.IsFalse(mDialog.Parts.MilestoneBox.Visible);
    Assert.AreEqual(0, mDialog.Parts.FieldRows.Height);
    Assert.IsFalse(mDialog.Parts.FormPanel.Visible);
    Assert.IsFalse(mDialog.Parts.BrowseButton.Visible, 'ohne OnBrowse kein Knopf');
    Assert.AreEqual('Fundstelle: `Main.pas`, Zeile 3', mDialog.Draft.Description.Split([#10])[0]);
  finally
    mDialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNewIssueDialogTests);

end.
