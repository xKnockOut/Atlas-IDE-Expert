unit Atlas.UI.Settings.QueryDialog.Tests;

// Tests des Dialogs „Abfrage bearbeiten“ (#1263) ohne Netz: Felder, Vorlagen
// je Verbindung und Sprache, „Testen“ über einen Haken mit fester Antwort,
// Meldungen zu jeder Ursache mit gesendeter Abfrage und Tipp, gesperrtes OK
// bei doppeltem Namen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTrackerQueryDialogTests = class
  public
    [Test]
    procedure FieldsAndQuery;
    /// <summary>Abnahme: Vorlagen je Sprache; Wahl einer Vorlage setzt die Abfrage.</summary>
    [Test]
    procedure TemplatesFollowConnection;
    /// <summary>Abnahme: „Testen“ zeigt Ergebnis, Tipp und die gesendete Abfrage; ein später Rückruf nach dem
    /// Schließen verfällt.</summary>
    [Test]
    procedure TestShowsResult;
    [Test]
    procedure ResultTextPerOutcome;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Queries,
  Atlas.Core.Tracker.QueryTest,
  Atlas.Core.Tracker.Templates,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.QueryDialog;

function Connections: TArray<TAtlasTrackerConnection>;
var
  mGerman: TAtlasTrackerConnection;
begin
  mGerman := TAtlasTrackerConnection.Create('Firma', 'youtrack', 'https://yt.local');
  mGerman.Language := 'de';
  Result := TArray<TAtlasTrackerConnection>.Create(mGerman,
    TAtlasTrackerConnection.Create('GitHub', 'github', 'https://github.com'));
end;

{ TAtlasTrackerQueryDialogTests }

procedure TAtlasTrackerQueryDialogTests.FieldsAndQuery;
var
  mDialog: TAtlasTrackerQueryDialog;
  mQuery: TAtlasTrackerQuery;
begin
  mDialog := TAtlasTrackerQueryDialog.CreateDialog(nil, TAtlasTrackerQuery.Create('Sprint', 's', 'Firma', 'ATL'),
    Connections, TArray<string>.Create('Standard'), nil);
  try
    // Wie in der IDE mit Fenster: Die Klapplisten füllen sich erst dann.
    mDialog.HandleNeeded;
    Assert.AreEqual('Sprint', mDialog.NameEdit.Text);
    Assert.AreEqual(1, mDialog.ConnectionBox.Choice);
    Assert.AreEqual('ATL', mDialog.ProjectEdit.Text);
    Assert.IsTrue(mDialog.OkButton.Enabled);
    Assert.IsFalse(mDialog.TestButton.Enabled, 'ohne Haken kein Testen');
    mDialog.QueryEdit.Text := '  zwei' + #10 + 'Zeilen ';
    mQuery := mDialog.Query;
    Assert.AreEqual('zwei Zeilen', mQuery.Query, 'einzeilig');
    Assert.AreEqual('Firma', mQuery.Connection);
    // Doppelter Name: OK gesperrt, mit Hinweis.
    mDialog.NameEdit.Text := 'standard';
    Assert.IsFalse(mDialog.OkButton.Enabled);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesQueryNameTaken), mDialog.ResultMemo.Text);
    mDialog.NameEdit.Text := 'Neu';
    mDialog.QueryEdit.Text := '';
    Assert.IsFalse(mDialog.OkButton.Enabled, 'ohne Abfrage');
    // „(alle)“ = ohne Verbindung.
    mDialog.SelectConnection(0);
    Assert.AreEqual('', mDialog.Query.Connection);
  finally
    mDialog.Free;
  end;
  // Verbindung, die es nicht mehr gibt, bleibt erhalten.
  mDialog := TAtlasTrackerQueryDialog.CreateDialog(nil, TAtlasTrackerQuery.Create('A', 'a', 'Alt', ''), Connections,
    nil, nil);
  try
    Assert.AreEqual(3, mDialog.ConnectionBox.Choice);
    Assert.AreEqual('Alt', mDialog.Query.Connection);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTrackerQueryDialogTests.TemplatesFollowConnection;
var
  mDialog: TAtlasTrackerQueryDialog;
  mTemplate: TAtlasTrackerTemplate;
begin
  mDialog := TAtlasTrackerQueryDialog.CreateDialog(nil, TAtlasTrackerQuery.Create('A', 'a', 'Firma', ''),
    Connections, nil, nil);
  try
    mDialog.HandleNeeded;
    // YouTrack mit erkannter deutscher Oberfläche: nur die deutschen Vorlagen.
    Assert.AreEqual(4, Integer(Length(mDialog.Templates)));
    for mTemplate in mDialog.Templates do
      Assert.AreEqual('de', mTemplate.Language);
    Assert.AreEqual('YouTrack · ' + TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQueryDefault) + ' (' +
      TAtlasStrings.Text(TAtlasTextId.TrackerLanguageGerman) + ')',
      TAtlasTrackerQueryDialog.TemplateCaption(mDialog.Templates[0]));
    mDialog.ApplyTemplate(0);
    Assert.AreEqual('assignee: meine #Ungelöst', mDialog.QueryEdit.Text);
    Assert.AreEqual(0, mDialog.TemplateBox.Choice, 'wieder „(Vorlage einsetzen …)“');
    // GitHub: englische Begriffe, ohne Sprint und ohne Sprachangabe.
    mDialog.SelectConnection(2);
    Assert.AreEqual(3, Integer(Length(mDialog.Templates)));
    Assert.AreEqual('GitHub · ' + TAtlasStrings.Text(TAtlasTextId.TrackerTemplateCreatedByMe),
      TAtlasTrackerQueryDialog.TemplateCaption(mDialog.Templates[1]));
    mDialog.ApplyTemplate(1);
    Assert.AreEqual('author:@me state:open', mDialog.QueryEdit.Text);
    // „(alle)“: Vorlagen beider Anbieter.
    mDialog.SelectConnection(0);
    Assert.AreEqual(7, Integer(Length(mDialog.Templates)));
  finally
    mDialog.Free;
  end;
  // Ohne Verbindungen: alle Vorlagen, YouTrack in beiden Sprachen.
  Assert.AreEqual(11, Integer(Length(TAtlasTrackerQueryDialog.TemplatesFor(nil, 0))));
end;

procedure TAtlasTrackerQueryDialogTests.TestShowsResult;
var
  mDialog: TAtlasTrackerQueryDialog;
  mSeen: TAtlasTrackerTarget;
  mSeenConnection: string;
  mLate: TAtlasQueryTestDone;
  mResult: TAtlasTrackerQueryTestResult;
begin
  mLate := nil;
  mDialog := TAtlasTrackerQueryDialog.CreateDialog(nil, TAtlasTrackerQuery.Create('A', 'assignee: me #Unresolved',
    'Firma', 'ATL'), Connections, nil,
    procedure(const AConnection: TAtlasTrackerConnection; const ATarget: TAtlasTrackerTarget;
      const ADone: TAtlasQueryTestDone)
    var
      mAnswer: TAtlasTrackerQueryTestResult;
    begin
      mSeen := ATarget;
      mSeenConnection := AConnection.Name;
      mLate := ADone;
      mAnswer := TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.Empty,
        'project: ATL assignee: me #Unresolved');
      mAnswer.ElapsedMs := 120;
      mAnswer.SuggestedQuery := 'assignee: meine #Ungelöst';
      ADone(mAnswer);
    end);
  try
    mDialog.HandleNeeded;
    Assert.IsTrue(mDialog.TestButton.Enabled);
    mDialog.TestButton.Click;
    Assert.AreEqual('Firma', mSeenConnection);
    Assert.AreEqual('ATL', mSeen.Project);
    Assert.AreEqual('assignee: me #Unresolved', mSeen.Query);
    Assert.AreEqual('de', mSeen.Language, 'Sprache der Verbindung');
    Assert.IsTrue(string(mDialog.ResultMemo.Text).Contains(TAtlasStrings.Fmt(TAtlasTextId.QueryTestEmpty, [120])),
      mDialog.ResultMemo.Text);
    Assert.IsTrue(string(mDialog.ResultMemo.Text).Contains('assignee: meine #Ungelöst'), 'Tipp');
    Assert.IsTrue(string(mDialog.ResultMemo.Text).Contains(TAtlasStrings.Fmt(TAtlasTextId.QueryTestSent,
      ['Firma', 'project: ATL assignee: me #Unresolved'])), 'gesendete Abfrage');
    Assert.IsTrue(mDialog.TestButton.Enabled, 'nach dem Ergebnis wieder frei');
  finally
    mDialog.Free;
  end;
  // Rückruf nach dem Schließen: kein Zugriff auf den freigegebenen Dialog.
  mResult := TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.Unreachable, '');
  mLate(mResult);
  mLate := nil;
  mSeenConnection := '';
  mSeen := Default(TAtlasTrackerTarget);
end;

procedure TAtlasTrackerQueryDialogTests.ResultTextPerOutcome;
var
  mResult: TAtlasTrackerQueryTestResult;
  mText: string;
begin
  mResult := TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.Found, 'q');
  mResult.Count := 3;
  mResult.ElapsedMs := 80;
  mResult.Keys := TArray<string>.Create('ATL-1', 'ATL-2', 'ATL-3');
  mText := TAtlasTrackerQueryDialog.ResultText(mResult, 'Firma');
  Assert.IsTrue(mText.StartsWith(TAtlasStrings.Fmt(TAtlasTextId.QueryTestFound, [3, 80, 'ATL-1, ATL-2, ATL-3'])),
    mText);
  Assert.IsTrue(mText.EndsWith(TAtlasStrings.Fmt(TAtlasTextId.QueryTestSent, ['Firma', 'q'])), mText);
  mResult.More := True;
  Assert.IsTrue(TAtlasTrackerQueryDialog.ResultText(mResult, 'Firma').StartsWith(TAtlasStrings.Fmt(
    TAtlasTextId.QueryTestFoundMore, [3, 80, 'ATL-1, ATL-2, ATL-3'])));
  mResult := TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.QueryRejected, 'q');
  mResult.HttpStatus := 400;
  mResult.TrackerMessage := 'Unbekannter Wert';
  Assert.IsTrue(TAtlasTrackerQueryDialog.ResultText(mResult, 'Firma').StartsWith(TAtlasStrings.Fmt(
    TAtlasTextId.QueryTestQueryRejected, [400, 'Unbekannter Wert'])));
  mResult := TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.ProjectUnknown, 'q');
  Assert.IsTrue(TAtlasTrackerQueryDialog.ResultText(mResult, 'Firma').StartsWith(TAtlasStrings.Text(
    TAtlasTextId.QueryTestProjectUnknown)));
  mResult := TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.NoToken, 'q');
  Assert.IsTrue(TAtlasTrackerQueryDialog.ResultText(mResult, 'Firma').StartsWith(TAtlasStrings.Text(
    TAtlasTextId.QueryTestNoToken)));
  mResult := TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.Unreadable, 'q');
  mResult.HttpStatus := 200;
  Assert.IsTrue(TAtlasTrackerQueryDialog.ResultText(mResult, 'Firma').StartsWith(TAtlasStrings.Fmt(
    TAtlasTextId.QueryTestUnreadable, [200])));
  // Ohne gesendete Abfrage keine Zeile „Gesendet an“.
  mResult := TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.Unreachable, '');
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.QueryTestUnreachable),
    TAtlasTrackerQueryDialog.ResultText(mResult, 'Firma'));
  mResult := Default(TAtlasTrackerQueryTestResult);
  mText := '';
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerQueryDialogTests);

end.
