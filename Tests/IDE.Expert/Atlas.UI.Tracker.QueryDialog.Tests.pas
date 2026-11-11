unit Atlas.UI.Tracker.QueryDialog.Tests;

// Tests des Dialogs „Abfrage bearbeiten“ (#1263) ohne Netz: Felder, Vorlagen
// je Verbindung und Sprache, „Testen“ über einen Haken mit fester Antwort,
// Meldungen zu jeder Ursache mit gesendeter Abfrage und Tipp, gesperrtes OK
// bei doppeltem Namen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
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
  Atlas.UI.Tracker.Strings,
  Atlas.UI.Settings.Page,
  Atlas.UI.Tracker.QueryDialog;

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
    Assert.AreEqual('Sprint', mDialog.View.Name.Text);
    Assert.AreEqual(1, mDialog.View.Connection.Choice);
    Assert.AreEqual('ATL', mDialog.View.Project.Text);
    Assert.IsTrue(mDialog.View.Ok.Enabled);
    Assert.IsFalse(mDialog.View.Test.Enabled, 'ohne Haken kein Testen');
    mDialog.View.Query.Text := '  zwei' + #10 + 'Zeilen ';
    mQuery := mDialog.Query;
    Assert.AreEqual('zwei Zeilen', mQuery.Query, 'einzeilig');
    Assert.AreEqual('Firma', mQuery.Connection);
    // Doppelter Name: OK gesperrt, mit Hinweis.
    mDialog.View.Name.Text := 'standard';
    Assert.IsFalse(mDialog.View.Ok.Enabled);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueryNameTaken),
      mDialog.View.Result.Text);
    mDialog.View.Name.Text := 'Neu';
    mDialog.View.Query.Text := '';
    Assert.IsFalse(mDialog.View.Ok.Enabled, 'ohne Abfrage');
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
    Assert.AreEqual(3, mDialog.View.Connection.Choice);
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
    begin
      Assert.AreEqual('de', mTemplate.Language);
    end;
    Assert.AreEqual('YouTrack · ' + TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeIssuesQueryDefault) + ' (' +
      TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerLanguageGerman) + ')',
      TAtlasTrackerQueryDialog.TemplateCaption(mDialog.Templates[0]));
    mDialog.ApplyTemplate(0);
    Assert.AreEqual('assignee: meine #Ungelöst', mDialog.View.Query.Text);
    Assert.AreEqual(0, mDialog.View.Template.Choice, 'wieder „(Vorlage einsetzen …)“');
    // GitHub: englische Begriffe, ohne Sprint und ohne Sprachangabe.
    mDialog.SelectConnection(2);
    Assert.AreEqual(3, Integer(Length(mDialog.Templates)));
    Assert.AreEqual('GitHub · ' + TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTemplateCreatedByMe),
      TAtlasTrackerQueryDialog.TemplateCaption(mDialog.Templates[1]));
    mDialog.ApplyTemplate(1);
    Assert.AreEqual('author:@me state:open', mDialog.View.Query.Text);
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
    Assert.IsTrue(mDialog.View.Test.Enabled);
    mDialog.View.Test.Click;
    Assert.AreEqual('Firma', mSeenConnection);
    Assert.AreEqual('ATL', mSeen.Project);
    Assert.AreEqual('assignee: me #Unresolved', mSeen.Query);
    Assert.AreEqual('de', mSeen.Language, 'Sprache der Verbindung');
    Assert.IsTrue(string(mDialog.View.Result.Text)
      .Contains(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.QueryTestEmpty, [120])),
      mDialog.View.Result.Text);
    Assert.IsTrue(string(mDialog.View.Result.Text).Contains('assignee: meine #Ungelöst'), 'Tipp');
    Assert.IsTrue(string(mDialog.View.Result.Text).Contains(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.QueryTestSent,
      ['Firma', 'project: ATL assignee: me #Unresolved'])), 'gesendete Abfrage');
    Assert.IsTrue(mDialog.View.Test.Enabled, 'nach dem Ergebnis wieder frei');
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
  Assert.IsTrue(mText.StartsWith(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.QueryTestFound, [3, 80, 'ATL-1, ATL-2, ATL-3'])),
    mText);
  Assert.IsTrue(mText.EndsWith(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.QueryTestSent, ['Firma', 'q'])), mText);
  mResult.More := True;
  Assert.IsTrue(TAtlasTrackerQueryDialog.ResultText(mResult, 'Firma').StartsWith(TAtlasTrackerStrings.Fmt(
    TAtlasTrackerTextId.QueryTestFoundMore, [3, 80, 'ATL-1, ATL-2, ATL-3'])));
  mResult := TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.QueryRejected, 'q');
  mResult.HttpStatus := 400;
  mResult.TrackerMessage := 'Unbekannter Wert';
  Assert.IsTrue(TAtlasTrackerQueryDialog.ResultText(mResult, 'Firma').StartsWith(TAtlasTrackerStrings.Fmt(
    TAtlasTrackerTextId.QueryTestQueryRejected, [400, 'Unbekannter Wert'])));
  mResult := TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.ProjectUnknown, 'q');
  Assert.IsTrue(TAtlasTrackerQueryDialog.ResultText(mResult, 'Firma').StartsWith(TAtlasTrackerStrings.Text(
    TAtlasTrackerTextId.QueryTestProjectUnknown)));
  mResult := TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.NoToken, 'q');
  Assert.IsTrue(TAtlasTrackerQueryDialog.ResultText(mResult, 'Firma').StartsWith(TAtlasTrackerStrings.Text(
    TAtlasTrackerTextId.QueryTestNoToken)));
  mResult := TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.Unreadable, 'q');
  mResult.HttpStatus := 200;
  Assert.IsTrue(TAtlasTrackerQueryDialog.ResultText(mResult, 'Firma').StartsWith(TAtlasTrackerStrings.Fmt(
    TAtlasTrackerTextId.QueryTestUnreadable, [200])));
  // Ohne gesendete Abfrage keine Zeile „Gesendet an“.
  mResult := TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.Unreachable, '');
  Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.QueryTestUnreachable),
    TAtlasTrackerQueryDialog.ResultText(mResult, 'Firma'));
  mResult := Default(TAtlasTrackerQueryTestResult);
  mText := '';
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerQueryDialogTests);

end.
