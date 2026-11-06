unit Atlas.UI.Tracker.MyIssues.Tests;

// Bereich „Meine Issues“ der Willkommensseite (#765, Mockup #ws12): Titel,
// Chip des Pull Requests mit CI-Ampel, Zeile zum Stand („Stand vom …“ ohne
// Netz), Fußzeile vor und nach „Beginnen“, Kurztext „ATL-123 · 3 offen“;
// Klicks auf Kennung, Pull Request und „Beginnen“ erreichen die Quelle über
// die Nachrichtenschleife; Kontextmenü mit „Nur merken“, „Zugang …“ nur mit
// Schalter TrackerLogin und „Beenden“ nur mit aktuellem Issue. Ohne Tracker
// (weder .atlas noch Zuordnung, #1261) ist die Fußzeile der Link „zuordnen …“.
// Abfragen (#1262): Klappliste mit Trefferzahl, Wahl und „Abfragen
// bearbeiten …“ über die Quelle, Zeile mit Verbindung, Projekt und Abfrage.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerIssuesViewTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen (Warteschlange des Hauptthreads, Menüs).</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure TextsFollowMockup;
    [Test]
    procedure StatusAndFooter;
    [Test]
    procedure EnglishTexts;
    [Test]
    procedure ClicksReachSource;
    /// <summary>issues.preview (#1264): Klick auf Zeile oder Kennung zeigt die Vorschau, Strg+Klick und „Im
    /// Browser öffnen“ den Browser.</summary>
    [Test]
    procedure ClicksOpenPreview;
    /// <summary>Abnahme #1261: ohne Zuordnung zeigt der Bereich „zuordnen …“; der Klick erreicht die Quelle.
    /// </summary>
    [Test]
    procedure AssignLinkWithoutTracker;
    /// <summary>Abnahme #1262: Klappliste zeigt die Abfragen mit Trefferzahl, die Wahl erreicht die Quelle; mit
    /// issues.queryPicker aus fehlt sie.</summary>
    [Test]
    procedure QueryPickerAndSourceLine;
    /// <summary>#1277: Filter der Sprint-Kachel als Zeile „Gefiltert: … · alle zeigen“; der Klick hebt ihn auf.
    /// </summary>
    [Test]
    procedure SprintFilterLine;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  Vcl.Forms,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Queries,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Tracker.MyIssues,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.MyIssues;

type
  /// <summary>Quelle des Bereichs für die Tests; merkt sich die Aufrufe.</summary>
  TFakeIssues = class(TInterfacedObject, IAtlasIssuesSource)
  public
    FView: TAtlasIssuesView;
    Calls: TArray<string>;
    Login: Boolean;
    function View: TAtlasIssuesView;
    procedure Shown;
    procedure Start(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
    procedure Browse(const AIssue: TAtlasTrackerIssue);
    procedure Preview(const AIssue: TAtlasTrackerIssue);
    procedure BrowsePullRequest(const AIssue: TAtlasTrackerIssue);
    procedure QueryNow;
    procedure Credentials;
    function CanEnterCredentials: Boolean;
    procedure EndActive;
    procedure AssignProject;
    procedure SelectQuery(const AName: string);
    procedure EditQueries;
    procedure ClearFilter;
  end;

function NowUtc0: TDateTime;
begin
  Result := EncodeDate(2026, 10, 16) + EncodeTime(9, 0, 0, 0);
end;

function Issue(const AKey: string; ANumber: Integer; const ATitle: string): TAtlasTrackerIssue;
begin
  Result := TAtlasTrackerIssue.Empty;
  Result.Key := AKey;
  Result.Number := ANumber;
  Result.Title := ATitle;
end;

/// <summary>Zwei GitHub-Issues wie im Mockup, eines mit Pull Request; Git.</summary>
function SampleView: TAtlasIssuesView;
var
  Target: TAtlasTrackerTarget;
  State: TAtlasIssuesState;
  First, Second: TAtlasTrackerIssue;
  Items: TArray<TAtlasTrackerIssue>;
begin
  Target := TAtlasMyIssues.TargetFor('github', 'https://github.com/beispiel/atlas', '', '', '');
  First := Issue('#753', 753, 'Atlas-Bereiche und Layout der Willkommensseite');
  First.Labels := ['plugin', 'welcome'];
  First.PullRequest.Number := 760;
  First.PullRequest.Checks := TAtlasTrackerChecks.Success;
  Second := Issue('#612', 612, 'Parser für Generics');
  Items := [First, Second];
  State := TAtlasIssuesState.Empty;
  TAtlasMyIssues.Recorded(State, Target, NowUtc0, True, Items, TAtlasCiFetchError.None);
  Result := TAtlasMyIssues.View(State, Target, 'main');
  Result.Project := 'C:\Projekte\Atlas\Atlas.groupproj';
  Result.ProjectName := 'Atlas-IDE-Expert';
  Result.Tracker := 'GitHub';
  Result.Options := TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '', '', '{kennung} ');
  Result.VcsKind := TAtlasVcsKind.Git;
end;

{ TFakeIssues }

function TFakeIssues.View: TAtlasIssuesView;
begin
  Result := FView;
end;

procedure TFakeIssues.Shown;
begin
  Calls := Calls + ['shown'];
end;

procedure TFakeIssues.Start(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
begin
  Calls := Calls + ['start ' + AIssue.Key + ' ' + TAtlasMyIssues.StartName(AMode)];
end;

procedure TFakeIssues.Browse(const AIssue: TAtlasTrackerIssue);
begin
  Calls := Calls + ['browse ' + AIssue.Key];
end;

procedure TFakeIssues.Preview(const AIssue: TAtlasTrackerIssue);
begin
  Calls := Calls + ['preview ' + AIssue.Key];
end;

procedure TFakeIssues.BrowsePullRequest(const AIssue: TAtlasTrackerIssue);
begin
  Calls := Calls + ['pr ' + IntToStr(AIssue.PullRequest.Number)];
end;

procedure TFakeIssues.QueryNow;
begin
  Calls := Calls + ['query'];
end;

procedure TFakeIssues.Credentials;
begin
  Calls := Calls + ['login'];
end;

function TFakeIssues.CanEnterCredentials: Boolean;
begin
  Result := Login;
end;

procedure TFakeIssues.EndActive;
begin
  Calls := Calls + ['end'];
end;

procedure TFakeIssues.AssignProject;
begin
  Calls := Calls + ['assign'];
end;

procedure TFakeIssues.SelectQuery(const AName: string);
begin
  Calls := Calls + ['select ' + AName];
end;

procedure TFakeIssues.EditQueries;
begin
  Calls := Calls + ['edit queries'];
end;

procedure TFakeIssues.ClearFilter;
begin
  Calls := Calls + ['clearFilter'];
end;

{ TAtlasTrackerIssuesViewTests }

procedure TAtlasTrackerIssuesViewTests.WarmUpFirstUse;
begin
  try
    ClicksReachSource;
  except
    on Exception do
      ;
  end;
end;

procedure TAtlasTrackerIssuesViewTests.TextsFollowMockup;
var
  Saved: TAtlasLanguage;
  View: TAtlasIssuesView;
  Pull: TAtlasTrackerPullRequest;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    View := SampleView;
    Assert.AreEqual('Meine Issues · Atlas-IDE-Expert', TAtlasTrackerIssuesText.TitleText(View.ProjectName));
    Assert.AreEqual('Meine Issues', TAtlasTrackerIssuesText.TitleText(''));
    // #1271: Punkt im Titel, solange ein Issue neue Änderungen hat; die Zeile trägt ihn auch.
    Assert.AreEqual('● Meine Issues · Atlas-IDE-Expert', TAtlasTrackerIssuesText.TitleText(View.ProjectName, True));
    Assert.AreEqual('Meine Issues', TAtlasTrackerIssuesText.TitleText('', False));
    Assert.IsFalse(View.IsUnseen(View.Items[0].Key));
    View.Unseen := [UpperCase(View.Items[0].Key)];
    Assert.IsTrue(View.IsUnseen(View.Items[0].Key));
    Assert.IsFalse(View.IsUnseen(View.Items[1].Key));
    Assert.IsFalse(View.IsUnseen(''));
    View.Unseen := nil;
    // Mockup: Chip „PR #640 · CI grün“.
    Assert.AreEqual('PR #760 · CI grün', TAtlasTrackerIssuesText.PullRequestText(View.Items[0].PullRequest));
    Pull := View.Items[0].PullRequest;
    Pull.Checks := TAtlasTrackerChecks.Failure;
    Assert.AreEqual('PR #760 · CI rot', TAtlasTrackerIssuesText.PullRequestText(Pull));
    Pull.Checks := TAtlasTrackerChecks.Unknown;
    Pull.Draft := True;
    Assert.AreEqual('PR #760 (Entwurf)', TAtlasTrackerIssuesText.PullRequestText(Pull));
    Assert.AreEqual('', TAtlasTrackerIssuesText.PullRequestText(View.Items[1].PullRequest));
    Assert.IsTrue(TAtlasTrackerIssuesText.ChecksColor(TAtlasTrackerChecks.Success) <>
      TAtlasTrackerIssuesText.ChecksColor(TAtlasTrackerChecks.Failure), 'rot ist nicht grün');
    // Hinweis auf „Beginnen“ mit dem Branch nach Muster (Abnahme: feature/753-atlas-bereiche-und).
    Assert.AreEqual('Branch: feature/753-atlas-bereiche-und', TAtlasTrackerIssuesText.StartHint(View,
      View.Items[0]));
    View.Options.Start := TAtlasIssueStart.Remember;
    Assert.AreEqual('Merkt #753 als aktuelles Issue', TAtlasTrackerIssuesText.StartHint(View, View.Items[0]));
    // Kurztext wie die Kachel im Mockup: „ATL-123 · 3 offen“.
    Assert.AreEqual('GitHub · 2 offen', TAtlasTrackerIssuesText.TileText(View));
    View.Active.Key := 'ATL-123';
    View.Items := View.Items + [Issue('ATL-124', 124, 'x')];
    Assert.AreEqual('ATL-123 · 3 offen', TAtlasTrackerIssuesText.TileText(View));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasTrackerIssuesViewTests.StatusAndFooter;
var
  Saved: TAtlasLanguage;
  View: TAtlasIssuesView;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    View := SampleView;
    // Frischer Stand: keine Zeile über der Liste; Fußzeile wie im Mockup.
    Assert.AreEqual('', TAtlasTrackerIssuesText.StatusText(View));
    Assert.AreEqual('„Beginnen“ legt den Branch an und öffnet das Projekt.',
      TAtlasTrackerIssuesText.FooterText(View));
    // Nach dem Klick: der Hinweis der Quelle.
    View.Notice := 'Branch feature/753-atlas-bereiche-und von main angelegt, Projekt wird geöffnet.';
    Assert.AreEqual(View.Notice, TAtlasTrackerIssuesText.FooterText(View));
    View.Notice := '';
    // Ohne Netz: der letzte Stand mit „Stand vom …“, kein Dialog.
    View.Status := TAtlasIssuesStatus.Stale;
    View.Error := TAtlasCiFetchError.Network;
    View.At := NowUtc0;
    Assert.StartsWith('GitHub · nicht erreichbar · Stand vom ', TAtlasTrackerIssuesText.StatusText(View));
    View.Status := TAtlasIssuesStatus.Failed;
    View.Error := TAtlasCiFetchError.Unauthorized;
    Assert.AreEqual('GitHub · Anmeldung vom Tracker abgelehnt: Token ungültig, abgelaufen oder ohne Rechte ' +
      '(Zugang zum Issue-Tracker neu hinterlegen)', TAtlasTrackerIssuesText.StatusText(View));
    // Ohne Token gibt es keine Anfrage: eigener Hinweis statt „abgelehnt“.
    View.Error := TAtlasCiFetchError.NoCredentials;
    Assert.AreEqual('GitHub · Noch kein Token: Rechtsklick › Zugang zum Issue-Tracker hinterlegen …',
      TAtlasTrackerIssuesText.StatusText(View));
    View.Status := TAtlasIssuesStatus.Waiting;
    View.Querying := True;
    Assert.AreEqual('Issues werden abgefragt …', TAtlasTrackerIssuesText.StatusText(View));
    View.Status := TAtlasIssuesStatus.Ready;
    View.Querying := False;
    View.Items := nil;
    Assert.AreEqual('Keine offenen Issues für diese Abfrage.', TAtlasTrackerIssuesText.StatusText(View));
    // Aktuelles Issue, das die Liste nicht (mehr) zeigt.
    View.Active.Key := 'ATL-123';
    View.Active.Title := 'Tracker';
    Assert.AreEqual('Aktuelles Issue: ATL-123 Tracker', TAtlasTrackerIssuesText.FooterText(View));
    // Ohne Tracker in .atlas bzw. ohne Projekt.
    View.Status := TAtlasIssuesStatus.NotConfigured;
    Assert.AreEqual('', TAtlasTrackerIssuesText.StatusText(View));
    Assert.Contains(TAtlasTrackerIssuesText.FooterText(View), 'tracker');
    View.Project := '';
    Assert.Contains(TAtlasTrackerIssuesText.FooterText(View), 'Noch kein Projekt');
    // Ohne Git und SVN wird nur gemerkt.
    View := SampleView;
    View.VcsKind := TAtlasVcsKind.None;
    Assert.Contains(TAtlasTrackerIssuesText.FooterText(View), 'merkt');
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasTrackerIssuesViewTests.EnglishTexts;
var
  Saved: TAtlasLanguage;
  View: TAtlasIssuesView;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.English;
    View := SampleView;
    Assert.AreEqual('My issues · Atlas-IDE-Expert', TAtlasTrackerIssuesText.TitleText(View.ProjectName));
    Assert.AreEqual('PR #760 · CI green', TAtlasTrackerIssuesText.PullRequestText(View.Items[0].PullRequest));
    Assert.AreEqual('“Start” creates the branch and opens the project.', TAtlasTrackerIssuesText.FooterText(View));
    Assert.AreEqual('GitHub · 2 open', TAtlasTrackerIssuesText.TileText(View));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasTrackerIssuesViewTests.ClicksReachSource;
var
  Host: TForm;
  Fake: TFakeIssues;
  Source: IAtlasIssuesSource;
  Frame: TAtlasTrackerIssuesView;
begin
  Fake := TFakeIssues.Create;
  Source := Fake;
  Fake.FView := SampleView;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasTrackerIssuesView.Create(Host);
    Frame.Parent := Host;
    Frame.Width := 600;
    Frame.Source := Source;
    Assert.AreEqual(1, Integer(Length(Fake.Calls)), 'Shown beim Setzen der Quelle');
    Assert.AreEqual('shown', Fake.Calls[0]);
    Fake.Calls := nil;
    Assert.IsTrue(Frame.CanStart);
    Frame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Key, 0));
    Frame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.PullRequest, 0));
    Frame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Start, 0));
    // Zeile selbst und Zeilen außerhalb tun nichts.
    Frame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Row, 1));
    Frame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Start, 9));
    Frame.Menus.MenuRow := 1;
    Frame.Menus.StartRememberItem.Click;
    Frame.Menus.QueryItem.Click;
    Frame.Menus.CredentialsItem.Click;
    Frame.Menus.EndItem.Click;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(7, Integer(Length(Fake.Calls)));
    Assert.AreEqual('browse #753', Fake.Calls[0]);
    Assert.AreEqual('pr 760', Fake.Calls[1]);
    Assert.AreEqual('start #753 branch', Fake.Calls[2]);
    Assert.AreEqual('start #612 remember', Fake.Calls[3]);
    Assert.AreEqual('query', Fake.Calls[4]);
    Assert.AreEqual('login', Fake.Calls[5]);
    Assert.AreEqual('end', Fake.Calls[6]);
    // Während „Beginnen“ läuft, kein zweites.
    Fake.Calls := nil;
    Fake.FView.Starting := True;
    Frame.UpdateContent;
    Assert.IsFalse(Frame.CanStart);
    Frame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Start, 0));
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)));
    Assert.IsTrue(Frame.HitTest(20, -5).Kind = TAtlasIssuesHitKind.None, 'über der ersten Zeile');
  finally
    Host.Free;
    Fake.Calls := nil;
  end;
end;

procedure TAtlasTrackerIssuesViewTests.ClicksOpenPreview;
var
  mHost: TForm;
  mFake: TFakeIssues;
  mSource: IAtlasIssuesSource;
  mFrame: TAtlasTrackerIssuesView;
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
  mFake := TFakeIssues.Create;
  mSource := mFake;
  mFake.FView := SampleView;
  mFake.FView.Options.Preview := True;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasTrackerIssuesView.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Width := 600;
    mFrame.Source := mSource;
    CheckSynchronize;
    mFake.Calls := nil;
    Assert.AreEqual('Vorschau', mFrame.Menus.PreviewItem.Caption);
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Row, 1));
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Key, 0));
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Key, 0), True);
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Row, 1), True);
    // Pull Request und „Beginnen“ bleiben, wie sie sind.
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.PullRequest, 0));
    mFrame.Menus.MenuRow := 1;
    mFrame.Menus.PreviewItem.Click;
    mFrame.Menus.BrowseItem.Click;
    CheckSynchronize;
    Assert.AreEqual(7, Integer(Length(mFake.Calls)));
    Assert.AreEqual('preview #612', mFake.Calls[0]);
    Assert.AreEqual('preview #753', mFake.Calls[1]);
    Assert.AreEqual('browse #753', mFake.Calls[2], 'Strg+Klick');
    Assert.AreEqual('browse #612', mFake.Calls[3], 'Strg+Klick auf die Zeile');
    Assert.AreEqual('pr 760', mFake.Calls[4]);
    Assert.AreEqual('preview #612', mFake.Calls[5]);
    Assert.AreEqual('browse #612', mFake.Calls[6]);
    // Ohne Vorschau: Zeile tut nichts, Kennung öffnet den Browser.
    mFake.Calls := nil;
    mFake.FView.Options.Preview := False;
    mFrame.UpdateContent;
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Row, 0));
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Row, 0), True);
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Key, 0));
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(mFake.Calls)));
    Assert.AreEqual('browse #753', mFake.Calls[0]);
  finally
    mHost.Free;
    mFake.Calls := nil;
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasTrackerIssuesViewTests.AssignLinkWithoutTracker;
var
  mSaved: TAtlasLanguage;
  mHost: TForm;
  mFake: TFakeIssues;
  mSource: IAtlasIssuesSource;
  mFrame: TAtlasTrackerIssuesView;
  mView: TAtlasIssuesView;
begin
  mSaved := TAtlasStrings.Language;
  mFake := TFakeIssues.Create;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mView := Default(TAtlasIssuesView);
    mView.Status := TAtlasIssuesStatus.NotConfigured;
    mView.Project := 'C:\Projekte\Kasse\Kasse.dproj';
    // Ohne Haken (Zuordnen nicht möglich) bleibt der bisherige Hinweis.
    Assert.IsFalse(TAtlasTrackerIssuesText.FooterIsAssign(mView));
    Assert.Contains(TAtlasTrackerIssuesText.FooterText(mView), 'tracker');
    mView.CanAssign := True;
    Assert.IsTrue(TAtlasTrackerIssuesText.FooterIsAssign(mView));
    Assert.AreEqual('Kein Tracker für dieses Projekt – zuordnen …', TAtlasTrackerIssuesText.FooterText(mView));
    // Ein Hinweis der Quelle geht vor; ohne Projekt gibt es nichts zuzuordnen.
    mView.Notice := 'x';
    Assert.IsFalse(TAtlasTrackerIssuesText.FooterIsAssign(mView));
    mView.Notice := '';
    mView.Project := '';
    Assert.IsFalse(TAtlasTrackerIssuesText.FooterIsAssign(mView));
    mView.Project := 'C:\Projekte\Kasse\Kasse.dproj';
    // Klick auf den Link über die Nachrichtenschleife.
    mFake.FView := mView;
    mFrame := TAtlasTrackerIssuesView.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Width := 600;
    mFrame.Source := mSource;
    mFake.Calls := nil;
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Assign, -1));
    Assert.AreEqual(0, Integer(Length(mFake.Calls)));
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(mFake.Calls)));
    Assert.AreEqual('assign', mFake.Calls[0]);
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('No tracker for this project – assign …', TAtlasTrackerIssuesText.FooterText(mView));
  finally
    TAtlasStrings.Language := mSaved;
    mHost.Free;
    mFake.Calls := nil;
  end;
end;

/// <summary>GitHub-Ansicht mit drei Abfragen, die erste gewählt, Klappliste an.</summary>
function QueryPickerView: TAtlasIssuesView;
begin
  Result := SampleView;
  Result.Connection := 'GitHub';
  Result.TrackerProject := 'beispiel/atlas';
  Result.Queries := TAtlasTrackerQueries.Read('[{"name": "Standard", "query": "assignee:@me state:open"}, ' +
    '{"name": "Bugs", "query": "label:bug"}, {"name": "Alle", "query": "is:open"}]');
  Result.QueryCounts := TArray<Integer>.Create(2, -1, 10);
  Result.QueryIndex := 0;
  Result.QueryText := 'assignee:@me state:open';
  Result.Picker := True;
end;

/// <summary>Klappliste: drei Abfragen, die gewählte mit Haken, dann „Abfragen bearbeiten …“.</summary>
procedure AssertQueryMenu(const AFrame: TAtlasTrackerIssuesView);
begin
  AFrame.Queries.Fill;
  Assert.AreEqual(5, AFrame.Queries.QueryMenu.Items.Count);
  Assert.AreEqual('Standard (2)', AFrame.Queries.QueryMenu.Items[0].Caption);
  Assert.IsTrue(AFrame.Queries.QueryMenu.Items[0].Checked);
  Assert.IsFalse(AFrame.Queries.QueryMenu.Items[1].Checked);
  Assert.AreEqual('Alle (10+)', AFrame.Queries.QueryMenu.Items[2].Caption);
  Assert.AreEqual('Abfragen bearbeiten …', AFrame.Queries.QueryMenu.Items[4].Caption);
end;

procedure TAtlasTrackerIssuesViewTests.QueryPickerAndSourceLine;
var
  mSaved: TAtlasLanguage;
  mHost: TForm;
  mFake: TFakeIssues;
  mSource: IAtlasIssuesSource;
  mFrame: TAtlasTrackerIssuesView;
  mView: TAtlasIssuesView;
begin
  mSaved := TAtlasStrings.Language;
  mFake := TFakeIssues.Create;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mView := QueryPickerView;
    Assert.AreEqual('GitHub · beispiel/atlas · Abfrage: assignee:@me state:open',
      TAtlasTrackerIssuesText.SourceText(mView));
    Assert.AreEqual('Standard (2)', TAtlasTrackerIssuesText.QueryCaption('Standard', 2));
    Assert.AreEqual('Bugs', TAtlasTrackerIssuesText.QueryCaption('Bugs', -1), 'noch nicht abgefragt');
    Assert.AreEqual('Alle (10+)', TAtlasTrackerIssuesText.QueryCaption('Alle', 10), 'höchstens MaxItems geholt');
    Assert.IsTrue(TAtlasTrackerIssuesText.ShowsQueryPicker(mView));
    mFake.FView := mView;
    mFrame := TAtlasTrackerIssuesView.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Width := 600;
    mFrame.Source := mSource;
    Assert.IsTrue(mFrame.Queries.QueryLabel.Visible);
    Assert.AreEqual('Standard (2) ' + #$25BE, mFrame.Queries.QueryLabel.Caption);
    // Klappliste: drei Abfragen, die gewählte mit Haken, dann „Abfragen bearbeiten …“.
    AssertQueryMenu(mFrame);
    // Wahl und Bearbeiten über die Nachrichtenschleife.
    mFake.Calls := nil;
    mFrame.Queries.QueryMenu.Items[1].Click;
    mFrame.Queries.QueryMenu.Items[4].Click;
    Assert.AreEqual(0, Integer(Length(mFake.Calls)));
    CheckSynchronize;
    Assert.AreEqual(2, Integer(Length(mFake.Calls)));
    Assert.AreEqual('select Bugs', mFake.Calls[0]);
    Assert.AreEqual('edit queries', mFake.Calls[1]);
    // issues.queryPicker aus: keine Klappliste; ohne Tracker auch nicht und keine Quellzeile.
    mView.Picker := False;
    mFake.FView := mView;
    mFrame.UpdateContent;
    Assert.IsFalse(mFrame.Queries.QueryLabel.Visible);
    mView.Picker := True;
    mView.Status := TAtlasIssuesStatus.NotConfigured;
    Assert.IsFalse(TAtlasTrackerIssuesText.ShowsQueryPicker(mView));
    Assert.AreEqual('', TAtlasTrackerIssuesText.SourceText(mView));
    TAtlasStrings.Language := TAtlasLanguage.English;
    mFrame.Queries.Fill;
    Assert.AreEqual('Edit queries …', mFrame.Queries.QueryMenu.Items[4].Caption);
  finally
    TAtlasStrings.Language := mSaved;
    mHost.Free;
    mFake.Calls := nil;
    mFake.FView := Default(TAtlasIssuesView);
  end;
end;

procedure TAtlasTrackerIssuesViewTests.SprintFilterLine;
var
  mSaved: TAtlasLanguage;
  mHost: TForm;
  mFake: TFakeIssues;
  mSource: IAtlasIssuesSource;
  mFrame: TAtlasTrackerIssuesView;
  mView: TAtlasIssuesView;
  mTop: Integer;
begin
  mSaved := TAtlasStrings.Language;
  mFake := TFakeIssues.Create;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mView := SampleView;
    Assert.AreEqual('', TAtlasTrackerIssuesText.FilterText(mView), 'ohne Filter keine Zeile');
    mFake.FView := mView;
    mFrame := TAtlasTrackerIssuesView.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Width := 600;
    mFrame.Source := mSource;
    mTop := mFrame.Painter.ListTop;
    // Mit Filter: Zeile über der Liste, die Liste rückt nach unten.
    mView.Filter := '„Sprint 12“, meine offen';
    Assert.AreEqual('Gefiltert: „Sprint 12“, meine offen · alle zeigen', TAtlasTrackerIssuesText.FilterText(mView));
    mFake.FView := mView;
    mFrame.UpdateContent;
    Assert.IsTrue(mFrame.Painter.ListTop > mTop, 'Liste unter der Filterzeile');
    mFake.Calls := nil;
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Filter, -1));
    Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'nicht im Mausereignis');
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(mFake.Calls)));
    Assert.AreEqual('clearFilter', mFake.Calls[0]);
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Filtered: „Sprint 12“, meine offen · show all', TAtlasTrackerIssuesText.FilterText(mView));
  finally
    TAtlasStrings.Language := mSaved;
    mHost.Free;
    mFake.Calls := nil;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerIssuesViewTests);

end.
