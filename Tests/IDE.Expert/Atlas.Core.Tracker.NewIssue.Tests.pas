unit Atlas.Core.Tracker.NewIssue.Tests;

// Tests zu „Issue anlegen …“ (#1268) ohne Netz: Titel und Beschreibung aus
// Auswahl, TODO und Befunden, Einfügen der Kennung in die drei
// TODO-Schreibweisen, Anfragen an YouTrack und GitHub gegen eine
// Fake-Transport-Schicht (GET und POST), Listen für Typ, Priorität und
// Zuständig, und dass ein Fehler keine Kennung liefert.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasNewIssueTests = class
  public
    /// <summary>Abnahme: Die Kennung kommt in alle drei TODO-Schreibweisen, auch mit Optionen der IDE.</summary>
    [Test]
    procedure KeyIntoTodoStyles;
    [Test]
    procedure TodoDetection;
    /// <summary>Abnahme: Titel aus der Auswahl, aus dem TODO oder leer.</summary>
    [Test]
    procedure TitleFromSelectionOrTodo;
    [Test]
    procedure DescriptionWithLocationAndCode;
    /// <summary>Abnahme: Aus Befunden Regelkennung, Meldung und Fundstelle; mehrere als Liste.</summary>
    [Test]
    procedure DescriptionFromFindings;
    /// <summary>Abnahme: Auf „// TODO Speicherleck beim Schließen“ entsteht ATL-130 mit Titel, Fundstelle und
    /// Codeausschnitt; das TODO lautet danach „// TODO ATL-130: Speicherleck beim Schließen“.</summary>
    [Test]
    procedure YouTrackCreateFromTodo;
    [Test]
    procedure GitHubCreateWithLabelsAndAssignee;
    /// <summary>Abnahme: 403 und andere Fehler liefern keine Kennung; ohne Token kein Netz.</summary>
    [Test]
    procedure FailuresGiveNoKey;
    [Test]
    procedure LoadFieldsFromTracker;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Internals.GitHubApi,
  Atlas.Core.Tracker.Providers.GitHub,
  Atlas.Core.Tracker.Providers.YouTrack,
  Atlas.Core.Tracker.NewIssue;

type
  /// <summary>Transport mit festen Antworten je Methode und Adressanfang (erster Treffer gilt); merkt Anfragen.
  /// </summary>
  TFakeTransport = class(TInterfacedObject, IAtlasCiTransport, IAtlasCiSend)
  private
    FMethods: TArray<string>;
    FPrefixes: TArray<string>;
    FStatus: TArray<Integer>;
    FTexts: TArray<string>;
    function Answer(const AMethod, AUrl: string; out AStatus: Integer; out AText: string): Boolean;
  public
    /// <summary>"GET https://…" bzw. "POST https://…".</summary>
    Calls: TArray<string>;
    Bodies: TArray<string>;
    destructor Destroy; override;
    procedure Reply(const AMethod, APrefix: string; AStatus: Integer; const AText: string);
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
    function Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

destructor TFakeTransport.Destroy;
begin
  FMethods := nil;
  FPrefixes := nil;
  FStatus := nil;
  FTexts := nil;
  Calls := nil;
  Bodies := nil;
  inherited Destroy;
end;

procedure TFakeTransport.Reply(const AMethod, APrefix: string; AStatus: Integer; const AText: string);
begin
  FMethods := FMethods + [AMethod];
  FPrefixes := FPrefixes + [APrefix];
  FStatus := FStatus + [AStatus];
  FTexts := FTexts + [AText];
end;

function TFakeTransport.Answer(const AMethod, AUrl: string; out AStatus: Integer; out AText: string): Boolean;
var
  mIndex: Integer;
begin
  Calls := Calls + [AMethod + ' ' + AUrl];
  AStatus := 404;
  AText := '';
  Result := True;
  for mIndex := 0 to High(FPrefixes) do
    if (FMethods[mIndex] = AMethod) and AUrl.StartsWith(FPrefixes[mIndex]) then
    begin
      AStatus := FStatus[mIndex];
      AText := FTexts[mIndex];
      Exit;
    end;
end;

function TFakeTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
begin
  AError := TAtlasCiFetchError.None;
  Result := Answer('GET', AUrl, AStatus, AText);
end;

function TFakeTransport.Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AStatus: Integer;
  out AText: string; out AError: TAtlasCiFetchError): Boolean;
begin
  AError := TAtlasCiFetchError.None;
  Bodies := Bodies + [ABody];
  Result := Answer(AMethod, AUrl, AStatus, AText);
end;

function YouTrackTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('youtrack', 'https://yt.local', 'ATL', '');
end;

function GitHubTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('github', 'https://github.com', 'acme/kasse', '');
end;

/// <summary>Wert APath (durch "." getrennt, Zahlen = Index) aus dem JSON AText als Text; '' ohne.</summary>
function JsonAt(const AText, APath: string): string;
var
  mRoot, mValue: TJSONValue;
  mPart: string;
  mIndex: Integer;
begin
  Result := '';
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    mValue := mRoot;
    for mPart in APath.Split(['.']) do
    begin
      if (mValue is TJSONArray) and TryStrToInt(mPart, mIndex) and (mIndex < TJSONArray(mValue).Count) then
        mValue := TJSONArray(mValue).Items[mIndex]
      else if mValue is TJSONObject then
        mValue := TJSONObject(mValue).Values[mPart]
      else
        mValue := nil;
      if mValue = nil then
        Exit;
    end;
    if mValue is TJSONString then
      Result := TJSONString(mValue).Value
    else
      Result := mValue.ToJSON;
  finally
    mRoot.Free;
  end;
end;

{ TAtlasNewIssueTests }

procedure TAtlasNewIssueTests.KeyIntoTodoStyles;
begin
  Assert.AreEqual('  // TODO ATL-130: Speicherleck beim Schließen',
    TAtlasNewIssues.WithKey('  // TODO Speicherleck beim Schließen', 'ATL-130'));
  Assert.AreEqual('// TODO ATL-130: Speicherleck', TAtlasNewIssues.WithKey('// TODO: Speicherleck', 'ATL-130'),
    'Doppelpunkt nach der Marke');
  Assert.AreEqual('x := 1; { TODO ATL-130: Fokus setzen }',
    TAtlasNewIssues.WithKey('x := 1; { TODO Fokus setzen }', 'ATL-130'));
  Assert.AreEqual('(* TODO ATL-130: Fokus setzen *)', TAtlasNewIssues.WithKey('(* TODO Fokus setzen *)', 'ATL-130'));
  Assert.AreEqual('{ TODO -oMarco -cGUI : ATL-130: Fokus setzen }',
    TAtlasNewIssues.WithKey('{ TODO -oMarco -cGUI : Fokus setzen }', 'ATL-130'), 'Optionen der IDE');
  Assert.AreEqual('// FIXME #42: Absturz', TAtlasNewIssues.WithKey('// FIXME Absturz', '#42'), 'GitHub');
  Assert.AreEqual('// TODO ATL-130', TAtlasNewIssues.WithKey('// TODO', 'ATL-130'), 'ohne Text');
  Assert.AreEqual('{ TODO ATL-130 }', TAtlasNewIssues.WithKey('{ TODO }', 'ATL-130'), 'ohne Text, geschweift');
  // Schon eingetragen bzw. kein TODO: unverändert.
  Assert.AreEqual('// TODO ATL-7: alt', TAtlasNewIssues.WithKey('// TODO ATL-7: alt', 'ATL-130'));
  Assert.AreEqual('x := 1; // Kommentar', TAtlasNewIssues.WithKey('x := 1; // Kommentar', 'ATL-130'));
  Assert.AreEqual('// ATL-130', TAtlasNewIssues.KeyComment(' ATL-130 '));
  Assert.AreEqual('x := 1; // ATL-130', TAtlasNewIssues.WithKeyComment('x := 1;  ', 'ATL-130'));
  Assert.AreEqual('  // ATL-130', TAtlasNewIssues.WithKeyComment('  ', 'ATL-130'), 'leere Zeile');
end;

procedure TAtlasNewIssueTests.TodoDetection;
var
  mTodo: TAtlasTodoComment;
begin
  Assert.IsTrue(TAtlasNewIssues.TodoAt('  // todo: klein geschrieben', mTodo));
  Assert.AreEqual('klein geschrieben', mTodo.Text);
  Assert.IsTrue(mTodo.Style = TAtlasTodoStyle.Slashes);
  Assert.IsTrue(TAtlasNewIssues.TodoAt('Foo; (* FIXME Bar *) // Rest', mTodo));
  Assert.IsTrue(mTodo.Style = TAtlasTodoStyle.Parens);
  Assert.AreEqual('Bar', mTodo.Text);
  Assert.IsTrue(TAtlasNewIssues.TodoAt('{ TODO 2 -oMarco : Mit Priorität }', mTodo));
  Assert.IsTrue(mTodo.HasOptions);
  Assert.AreEqual('Mit Priorität', mTodo.Text);
  Assert.IsTrue(TAtlasNewIssues.TodoAt('// TODO #12: schon da', mTodo));
  Assert.AreEqual('#12', mTodo.Key);
  Assert.AreEqual('schon da', mTodo.Text);
  // Kein TODO: Wörter, die nur so anfangen, Strings und Direktiven.
  Assert.IsFalse(TAtlasNewIssues.TodoAt('// TODOs aufräumen', mTodo));
  Assert.IsFalse(TAtlasNewIssues.TodoAt('// TODO-Liste', mTodo));
  Assert.IsFalse(TAtlasNewIssues.TodoAt('S := ''// TODO kein Kommentar'';', mTodo));
  Assert.IsFalse(TAtlasNewIssues.TodoAt('{$IFDEF TODO}', mTodo));
  Assert.IsFalse(TAtlasNewIssues.TodoAt('x := 1;', mTodo));
end;

procedure TAtlasNewIssueTests.TitleFromSelectionOrTodo;
var
  mContext: TAtlasNewIssueContext;
begin
  mContext := TAtlasNewIssueContext.Empty;
  mContext.Lines := TArray<string>.Create('begin', '  // TODO Speicherleck beim Schließen', 'end;');
  mContext.Line := 2;
  Assert.AreEqual('Speicherleck beim Schließen', TAtlasNewIssues.TitleOf(mContext), 'TODO unter dem Cursor');
  mContext.Line := 1;
  Assert.AreEqual('', TAtlasNewIssues.TitleOf(mContext), 'ohne Auswahl und TODO leer');
  mContext.Selection := #13#10 + '  FList.Free;' + #13#10 + '  FList := nil;';
  Assert.AreEqual('FList.Free;', TAtlasNewIssues.TitleOf(mContext), 'erste nicht leere Zeile der Auswahl');
  mContext.Selection := StringOfChar('x', 300);
  Assert.AreEqual(Integer(TAtlasNewIssues.MaxTitle), Integer(Length(TAtlasNewIssues.TitleOf(mContext))), 'gekürzt');
  mContext.Lines := nil;
end;

procedure TAtlasNewIssueTests.DescriptionWithLocationAndCode;
var
  mContext: TAtlasNewIssueContext;
  mIndex: Integer;
  mText, mCode: string;
begin
  mContext := TAtlasNewIssueContext.Empty;
  SetLength(mContext.Lines, 20);
  for mIndex := 0 to High(mContext.Lines) do
    mContext.Lines[mIndex] := '    Zeile' + IntToStr(mIndex + 1) + ';';
  mContext.FileName := 'C:\Projekte\Kasse\Source\Main.pas';
  mContext.Line := 10;
  mContext.Method := 'TMainForm.FormClose';
  mContext.Branch := 'feature/ATL-12-schliessen';
  mContext.Commit := '0123456789abcdef0123456789abcdef01234567';
  mText := TAtlasNewIssues.DescriptionOf(mContext, TAtlasNewIssueLabels.German);
  Assert.AreEqual('Fundstelle: `Main.pas`, Zeile 10' + #10 + 'Methode: `TMainForm.FormClose`' + #10 +
    'Branch: `feature/ATL-12-schliessen` (Commit `0123456`)', mText, 'ohne Pfad, Commit gekürzt');
  // ±5 Zeilen ohne gemeinsame Einrückung.
  mCode := TAtlasNewIssues.CodeOf(mContext);
  Assert.AreEqual(11, Integer(Length(mCode.Split([#10]))));
  Assert.IsTrue(mCode.StartsWith('Zeile5;'), mCode);
  Assert.IsTrue(mCode.EndsWith('Zeile15;'), mCode);
  Assert.AreEqual(mText + #10#10 + '```pascal' + #10 + mCode + #10 + '```',
    TAtlasNewIssues.Compose(mText, mCode, True));
  Assert.AreEqual(mText, TAtlasNewIssues.Compose(mText, mCode, False), 'Häkchen aus: ohne Code');
  // Auswahl statt Umgebung; die Zeile der Fundstelle ist die der Auswahl.
  mContext.Selection := '  if A then' + #13#10 + '    B;';
  mContext.SelectionLine := 7;
  Assert.AreEqual('if A then' + #10 + '  B;', TAtlasNewIssues.CodeOf(mContext));
  Assert.IsTrue(TAtlasNewIssues.DescriptionOf(mContext, TAtlasNewIssueLabels.German).StartsWith(
    'Fundstelle: `Main.pas`, Zeile 7'));
  Assert.IsTrue(TAtlasNewIssues.CodeBlock('a ```b```').StartsWith('~~~pascal'), 'Zaun im Code');
  mContext.Lines := nil;
end;

procedure TAtlasNewIssueTests.DescriptionFromFindings;
var
  mFindings: TArray<TAtlasNewIssueFinding>;
  mContext: TAtlasNewIssueContext;
  mText: string;
begin
  mFindings := [TAtlasNewIssueFinding.Create('missing-free', 'FList wird nicht freigegeben', 'Main.pas:12:5',
    '  FList := TList.Create;')];
  mContext := TAtlasNewIssueContext.Empty;
  Assert.AreEqual('missing-free: FList wird nicht freigegeben',
    TAtlasNewIssues.TitleOfFindings(mFindings, TAtlasNewIssueLabels.German));
  mText := TAtlasNewIssues.DescriptionOfFindings(mFindings, mContext, TAtlasNewIssueLabels.German);
  Assert.AreEqual('Befunde:' + #10 + '- `missing-free` FList wird nicht freigegeben – `Main.pas:12:5`', mText);
  Assert.AreEqual('// Main.pas:12:5' + #10 + 'FList := TList.Create;', TAtlasNewIssues.CodeOfFindings(mFindings));
  mFindings := mFindings + [TAtlasNewIssueFinding.Create('E2003', 'Undeklarierter Bezeichner', 'Main.pas:20:3', '')];
  Assert.AreEqual('2 Befunde in Main.pas', TAtlasNewIssues.TitleOfFindings(mFindings, TAtlasNewIssueLabels.German));
  mContext.Branch := 'main';
  mText := TAtlasNewIssues.DescriptionOfFindings(mFindings, mContext, TAtlasNewIssueLabels.German);
  Assert.IsTrue(mText.StartsWith('Branch: `main`' + #10#10 + 'Befunde:'), mText);
  Assert.IsTrue(mText.EndsWith('- `E2003` Undeklarierter Bezeichner – `Main.pas:20:3`'), mText);
  Assert.AreEqual('// Main.pas:12:5' + #10 + 'FList := TList.Create;', TAtlasNewIssues.CodeOfFindings(mFindings),
    'ohne Zeile kein Code');
  mFindings := nil;
end;

procedure TAtlasNewIssueTests.YouTrackCreateFromTodo;
var
  mTransport: TFakeTransport;
  mRef: IAtlasCiTransport;
  mProvider: IAtlasTrackerProvider;
  mContext: TAtlasNewIssueContext;
  mDraft: TAtlasNewIssueDraft;
  mResult: TAtlasNewIssueResult;
  mBody: string;
begin
  mContext := TAtlasNewIssueContext.Empty;
  mContext.FileName := 'Main.pas';
  mContext.Lines := TArray<string>.Create('procedure TMainForm.FormClose;', 'begin',
    '  // TODO Speicherleck beim Schließen', 'end;');
  mContext.Line := 3;
  mDraft := TAtlasNewIssueDraft.Empty;
  mDraft.Title := TAtlasNewIssues.TitleOf(mContext);
  mDraft.Description := TAtlasNewIssues.Compose(TAtlasNewIssues.DescriptionOf(mContext, TAtlasNewIssueLabels.German),
    TAtlasNewIssues.CodeOf(mContext), True);
  mDraft.IssueType := 'Bug';
  mDraft.AssignToMe := True;
  mDraft.AssigneeField := 'Zuständig';
  mTransport := TFakeTransport.Create;
  mRef := mTransport;
  mTransport.Reply('GET', 'https://yt.local/api/admin/projects?', 200,
    '[{"id":"0-1","shortName":"KASSE"},{"id":"0-7","shortName":"ATL"}]');
  mTransport.Reply('GET', 'https://yt.local/api/users/me', 200, '{"login":"marco"}');
  mTransport.Reply('POST', 'https://yt.local/api/issues', 200,
    '{"idReadable":"ATL-130","numberInProject":130,"$type":"Issue"}');
  mProvider := TAtlasYouTrackTracker.Create;
  mResult := TAtlasNewIssues.CreateIssue(mProvider, YouTrackTarget, mRef, mDraft);
  Assert.IsTrue(mResult.Outcome = TAtlasNewIssueOutcome.Created);
  Assert.AreEqual('ATL-130', mResult.Key);
  Assert.AreEqual(130, mResult.Number);
  Assert.AreEqual('https://yt.local/issue/ATL-130', mResult.Page);
  Assert.AreEqual(3, Integer(Length(mTransport.Calls)), string.Join(' | ', mTransport.Calls));
  Assert.AreEqual('POST https://yt.local/api/issues?fields=idReadable,numberInProject', mTransport.Calls[2]);
  mBody := mTransport.Bodies[0];
  Assert.AreEqual('0-7', JsonAt(mBody, 'project.id'), 'ID zum Kürzel ATL');
  Assert.AreEqual('Speicherleck beim Schließen', JsonAt(mBody, 'summary'));
  Assert.IsTrue(JsonAt(mBody, 'description').StartsWith('Fundstelle: `Main.pas`, Zeile 3'), mBody);
  Assert.IsTrue(JsonAt(mBody, 'description').Contains('```pascal' + #10 + 'procedure TMainForm.FormClose;'),
    'Codeausschnitt');
  Assert.AreEqual('Type', JsonAt(mBody, 'customFields.0.name'));
  Assert.AreEqual('Bug', JsonAt(mBody, 'customFields.0.value.name'));
  Assert.AreEqual('Zuständig', JsonAt(mBody, 'customFields.1.name'), 'Name des Felds aus dem Projekt');
  Assert.AreEqual('marco', JsonAt(mBody, 'customFields.1.value.login'), 'mir zuweisen');
  // Danach das TODO mit Kennung.
  Assert.AreEqual('  // TODO ATL-130: Speicherleck beim Schließen',
    TAtlasNewIssues.WithKey(mContext.Lines[mContext.Line - 1], mResult.Key));
  mContext.Lines := nil;
end;

procedure TAtlasNewIssueTests.GitHubCreateWithLabelsAndAssignee;
var
  mTransport: TFakeTransport;
  mRef: IAtlasCiTransport;
  mDraft: TAtlasNewIssueDraft;
  mResult: TAtlasNewIssueResult;
  mBody: string;
  mGitHub: IAtlasTrackerProvider;
begin
  mGitHub := TAtlasGitHubTracker.Create;
  mDraft := TAtlasNewIssueDraft.Empty;
  mDraft.Title := '  Absturz beim Speichern ';
  mDraft.Description := 'Text';
  mDraft.IssueType := 'bug';
  mDraft.Priority := 'prio:high';
  mDraft.Assignee := 'octocat';
  mTransport := TFakeTransport.Create;
  mRef := mTransport;
  mTransport.Reply('POST', 'https://api.github.com/repos/acme/kasse/issues', 201,
    '{"number":42,"html_url":"https://github.com/acme/kasse/issues/42"}');
  mResult := TAtlasNewIssues.CreateIssue(mGitHub, GitHubTarget, mRef, mDraft);
  Assert.IsTrue(mResult.Outcome = TAtlasNewIssueOutcome.Created);
  Assert.AreEqual('#42', mResult.Key);
  Assert.AreEqual(1, Integer(Length(mTransport.Calls)), 'ohne „mir zuweisen“ keine Abfrage des Benutzers');
  mBody := mTransport.Bodies[0];
  Assert.AreEqual('Absturz beim Speichern', JsonAt(mBody, 'title'));
  Assert.AreEqual('Text', JsonAt(mBody, 'body'));
  Assert.AreEqual('["bug","prio:high"]', JsonAt(mBody, 'labels'));
  Assert.AreEqual('["octocat"]', JsonAt(mBody, 'assignees'));
  Assert.AreEqual('https://api.github.com/repos/acme/kasse/labels?per_page=100',
    TAtlasNewIssues.GitHubLabelsUrl(GitHubTarget));
  Assert.AreEqual('https://ghe.firma.de/api/v3/repos/acme/kasse/issues',
    TAtlasNewIssues.GitHubCreateUrl(TAtlasTrackerTarget.Create('github', 'https://ghe.firma.de', 'acme/kasse', '')),
    'Enterprise');
  // Anbieter und „Issue anlegen“ teilen sich die API-Adresse.
  Assert.AreEqual('https://api.github.com', TAtlasGitHubApi.Base(GitHubTarget));
  Assert.AreEqual('', TAtlasGitHubApi.Base(TAtlasTrackerTarget.Create('github', 'ftp://x', 'acme/kasse', '')),
    'nur http(s)');
end;

procedure TAtlasNewIssueTests.FailuresGiveNoKey;
var
  mTransport: TFakeTransport;
  mRef: IAtlasCiTransport;
  mDraft: TAtlasNewIssueDraft;
  mResult: TAtlasNewIssueResult;
  mGitHub, mYouTrack: IAtlasTrackerProvider;
begin
  mGitHub := TAtlasGitHubTracker.Create;
  mYouTrack := TAtlasYouTrackTracker.Create;
  mDraft := TAtlasNewIssueDraft.Empty;
  mDraft.Title := 'Titel';
  // 403: abgelehnt, keine Kennung (der Code bleibt unverändert).
  mTransport := TFakeTransport.Create;
  mRef := mTransport;
  mTransport.Reply('POST', 'https://api.github.com/', 403, '{"message":"Resource not accessible"}');
  mResult := TAtlasNewIssues.CreateIssue(mGitHub, GitHubTarget, mRef, mDraft);
  Assert.IsTrue(mResult.Outcome = TAtlasNewIssueOutcome.Rejected);
  Assert.AreEqual(403, mResult.HttpStatus);
  Assert.AreEqual('', mResult.Key);
  // 422 mit Meldung des Trackers.
  mTransport := TFakeTransport.Create;
  mRef := mTransport;
  mTransport.Reply('POST', 'https://api.github.com/', 422, '{"message":"Validation Failed"}');
  mResult := TAtlasNewIssues.CreateIssue(mGitHub, GitHubTarget, mRef, mDraft);
  Assert.IsTrue(mResult.Outcome = TAtlasNewIssueOutcome.Invalid);
  Assert.AreEqual('Validation Failed', mResult.TrackerMessage);
  // YouTrack: Projektkürzel unbekannt, nichts gesendet.
  mTransport := TFakeTransport.Create;
  mRef := mTransport;
  mTransport.Reply('GET', 'https://yt.local/api/admin/projects?', 200, '[{"id":"0-1","shortName":"KASSE"}]');
  mResult := TAtlasNewIssues.CreateIssue(mYouTrack, YouTrackTarget, mRef, mDraft);
  Assert.IsTrue(mResult.Outcome = TAtlasNewIssueOutcome.ProjectUnknown);
  Assert.AreEqual(0, Integer(Length(mTransport.Bodies)), 'kein POST');
  // Angelegt, aber Antwort ohne Kennung: nichts in den Code.
  mTransport := TFakeTransport.Create;
  mRef := mTransport;
  mTransport.Reply('POST', 'https://api.github.com/', 201, '<html>');
  mResult := TAtlasNewIssues.CreateIssue(mGitHub, GitHubTarget, mRef, mDraft);
  Assert.IsTrue(mResult.Outcome = TAtlasNewIssueOutcome.Unreadable);
  Assert.AreEqual('', mResult.Key);
  // Ohne Token (kein Transport) und ohne Titel kein Netz.
  mResult := TAtlasNewIssues.CreateIssue(mGitHub, GitHubTarget, nil, mDraft);
  Assert.IsTrue(mResult.Outcome = TAtlasNewIssueOutcome.NoToken);
  mTransport := TFakeTransport.Create;
  mRef := mTransport;
  mDraft.Title := '  ';
  mResult := TAtlasNewIssues.CreateIssue(mGitHub, GitHubTarget, mRef, mDraft);
  Assert.IsTrue(mResult.Outcome = TAtlasNewIssueOutcome.NotConfigured);
  Assert.AreEqual(0, Integer(Length(mTransport.Calls)));
end;

procedure TAtlasNewIssueTests.LoadFieldsFromTracker;
var
  mTransport: TFakeTransport;
  mRef: IAtlasCiTransport;
  mFields: TAtlasNewIssueFields;
  mGitHub, mYouTrack: IAtlasTrackerProvider;
begin
  mGitHub := TAtlasGitHubTracker.Create;
  mYouTrack := TAtlasYouTrackTracker.Create;
  mTransport := TFakeTransport.Create;
  mRef := mTransport;
  mTransport.Reply('GET', 'https://yt.local/api/users/me', 200, '{"login":"marco"}');
  mTransport.Reply('GET', 'https://yt.local/api/admin/projects?', 200, '[{"id":"0-7","shortName":"atl"}]');
  mTransport.Reply('GET', 'https://yt.local/api/admin/projects/0-7/customFields', 200,
    '[{"field":{"name":"Priorität"},"bundle":{"values":[{"name":"Kritisch"},{"name":"Normal"}]}},' +
    '{"field":{"name":"Typ"},"bundle":{"values":[{"name":"Fehler"},{"name":"Aufgabe"}]}},' +
    '{"field":{"name":"Zuständig"},"bundle":{"values":[{"login":"marco","name":"Marco"}],' +
    '"aggregatedUsers":[{"login":"anna"},{"login":"marco"}]}},' +
    '{"field":{"name":"State"},"bundle":{"values":[{"name":"Offen"}]}}]');
  Assert.IsTrue(TAtlasNewIssues.LoadFields(mYouTrack, YouTrackTarget, mRef, mFields));
  Assert.AreEqual('marco', mFields.Me);
  Assert.AreEqual('Typ', mFields.TypeField);
  Assert.AreEqual('Fehler,Aufgabe', string.Join(',', mFields.Types));
  Assert.AreEqual('Priorität', mFields.PriorityField);
  Assert.AreEqual('Kritisch,Normal', string.Join(',', mFields.Priorities));
  Assert.AreEqual('Zuständig', mFields.AssigneeField);
  Assert.AreEqual('marco,anna', string.Join(',', mFields.Assignees), 'ohne Dubletten');
  // GitHub: Labels für Typ und Priorität, Zuständige aus /assignees.
  mTransport := TFakeTransport.Create;
  mRef := mTransport;
  mTransport.Reply('GET', 'https://api.github.com/user', 200, '{"login":"octocat"}');
  mTransport.Reply('GET', 'https://api.github.com/repos/acme/kasse/labels', 200, '[{"name":"bug"},{"name":"docs"}]');
  mTransport.Reply('GET', 'https://api.github.com/repos/acme/kasse/assignees', 200, '[{"login":"octocat"}]');
  Assert.IsTrue(TAtlasNewIssues.LoadFields(mGitHub, GitHubTarget, mRef, mFields));
  Assert.AreEqual('octocat', mFields.Me);
  Assert.AreEqual('bug,docs', string.Join(',', mFields.Types));
  Assert.AreEqual('octocat', string.Join(',', mFields.Assignees));
  Assert.AreEqual('', mFields.TypeField, 'GitHub ohne Feldnamen');
  // Ohne Antwort: False, Felder leer (frei eintippbar).
  mTransport := TFakeTransport.Create;
  mRef := mTransport;
  Assert.IsFalse(TAtlasNewIssues.LoadFields(mGitHub, GitHubTarget, mRef, mFields));
  Assert.AreEqual(0, Integer(Length(mFields.Types)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNewIssueTests);

end.
