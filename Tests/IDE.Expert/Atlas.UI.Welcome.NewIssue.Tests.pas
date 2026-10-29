unit Atlas.UI.Welcome.NewIssue.Tests;

// Tests des Dialogs „Issue anlegen“ (#1268) ohne Netz: Vorbelegung, Häkchen
// „Codeausschnitt“ nach issues.create.includeCode, nichts gesendet ohne Klick
// auf „Anlegen“, Fehler lässt den Dialog offen, Listen vom Tracker und ein
// später Rückruf nach dem Schließen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
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
  end;

implementation

uses
  System.SysUtils,
  System.UITypes,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.NewIssue,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.NewIssue;

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

{ TAtlasNewIssueDialogTests }

procedure TAtlasNewIssueDialogTests.IncludeCodeFollowsSetting;
var
  mDialog: TAtlasNewIssueDialog;
begin
  mDialog := TAtlasNewIssueDialog.CreateDialog(nil, Setup(False), nil, nil);
  try
    Assert.IsFalse(mDialog.IncludeCodeBox.Checked, 'nicht vorausgewählt');
    Assert.IsFalse(mDialog.CodeMemo.Enabled);
    Assert.AreEqual('Fundstelle: `Main.pas`, Zeile 3', mDialog.Draft.Description, 'ohne Code');
    mDialog.IncludeCodeBox.Checked := True;
    Assert.IsTrue(mDialog.CodeMemo.Enabled);
    Assert.IsTrue(mDialog.Draft.Description.EndsWith('```pascal' + #10 + '// TODO Speicherleck beim Schließen' + #10 +
      '```'), mDialog.Draft.Description);
    Assert.IsFalse(mDialog.StartNowBox.Enabled, '„gleich beginnen“ nur mit „Meine Issues“');
  finally
    mDialog.Free;
  end;
  mDialog := TAtlasNewIssueDialog.CreateDialog(nil, Setup(True), nil, nil);
  try
    Assert.IsTrue(mDialog.IncludeCodeBox.Checked, 'Vorgabe an');
    Assert.IsTrue(mDialog.Draft.Description.Contains('```pascal'));
    Assert.IsFalse(mDialog.CreateButton.Enabled, 'ohne Haken OnSend kein Anlegen');
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
    mDialog.TypeBox.Text := 'Bug';
    mDialog.AssignToMeBox.Checked := True;
    Assert.IsFalse(mDialog.AssigneeBox.Enabled, '„mir zuweisen“ ersetzt Zuständig');
    Assert.AreEqual(0, mSent, 'nichts ohne Klick');
    Assert.IsTrue(mDialog.CreateButton.Enabled);
    mDialog.ProjectEdit.Text := 'KASSE';
    mDialog.CreateButton.Click;
    Assert.AreEqual(1, mSent);
    Assert.IsTrue(mDialog.Sending);
    Assert.IsFalse(mDialog.CreateButton.Enabled, 'kein zweites Senden');
    Assert.IsFalse(mDialog.CancelButton.Enabled, 'nicht schließen, solange gesendet wird');
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
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.NewIssueRejected, [403]), mDialog.StatusLabel.Caption);
    Assert.IsTrue(mDialog.CreateButton.Enabled, 'erneut versuchen');
    // Erfolg: schließt mit OK und merkt das Ergebnis.
    mDialog.CreateButton.Click;
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
    Assert.AreEqual('ATL', mDialog.ProjectEdit.Text, 'Projekt aus der Zuordnung');
    Assert.IsTrue(mDialog.Target(mTarget));
    Assert.AreEqual('youtrack', mTarget.Provider);
    // Wechsel des Trackers: Projekt des Eintrags, Listen neu.
    mDialog.TrackerBox.Choice := 1;
    mDialog.TrackerBox.OnChange(mDialog.TrackerBox);
    Assert.AreEqual('', mDialog.ProjectEdit.Text);
    Assert.AreEqual(0, mLoads, 'GitHub ohne owner/repo: nichts zu laden');
    mDialog.ProjectEdit.Text := 'acme/kasse';
    Assert.IsTrue(mDialog.Target(mTarget));
    Assert.AreEqual('acme/kasse', mTarget.Project);
    mDialog.LoadFields;
    Assert.AreEqual(1, mLoads);
    // Listen übernehmen; was eingetippt ist, bleibt.
    mDialog.TypeBox.Text := 'eigener Typ';
    mFields := TAtlasNewIssueFields.Empty;
    mFields.TypeField := 'Typ';
    mFields.Types := TArray<string>.Create('Fehler', 'Aufgabe');
    mDialog.ShowFields(mFields, True);
    Assert.AreEqual('Fehler,Aufgabe', string.Join(',', mDialog.TypeBox.Values));
    Assert.AreEqual('eigener Typ', mDialog.TypeBox.Text);
    Assert.AreEqual('Typ', mDialog.Draft.TypeField);
    mDialog.ShowFields(TAtlasNewIssueFields.Empty, False);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.NewIssueLoadFailed), mDialog.StatusLabel.Caption);
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
    Assert.IsFalse(mDialog.CreateButton.Enabled);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.NewIssueNoTracker), mDialog.StatusLabel.Caption);
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
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.NewIssueNoToken, ['https://yt.local']),
    TAtlasNewIssueDialog.ResultText(mResult, 'ATL', 'https://yt.local'));
  mResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.ProjectUnknown);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.NewIssueProjectUnknown, ['ATL']),
    TAtlasNewIssueDialog.ResultText(mResult, 'ATL', ''));
  mResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.Invalid);
  mResult.TrackerMessage := 'Validation Failed';
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.NewIssueInvalid, ['Validation Failed']),
    TAtlasNewIssueDialog.ResultText(mResult, '', ''));
  mResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.Unreachable);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.NewIssueUnreachable), TAtlasNewIssueDialog.ResultText(mResult, '',
    ''));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNewIssueDialogTests);

end.
