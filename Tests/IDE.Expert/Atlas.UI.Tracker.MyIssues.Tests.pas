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
// Tracker-Projekt (#1927): Klappliste „Projekt: … ▾“ mit „Automatisch“, den
// Tracker-Projekten, „Alle“ (#1928) und „bearbeiten …“; Köpfe der Gruppen.
// Wieder geöffnet (#2127): Marke, Grund und Knöpfe in einer höheren Zeile;
// „Weiterarbeiten“, „Gelesen“ und Grund erreichen die Quelle.

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
    /// <summary>#1927/#1928: Klappliste „Tracker-Projekt“, Wahl über die Quelle; Köpfe der Gruppen bei „Alle“.
    /// </summary>
    [Test]
    procedure ProjectPickerAndGroups;
    /// <summary>#2127: Zeile mit Marke „wieder offen“, Grund und Knöpfen; Klicks erreichen die Quelle.</summary>
    [Test]
    procedure ReopenedRow;
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
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.Tracker.MyIssues,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Projects,
  Atlas.Core.Tracker.Reopened,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.ProjectPicker,
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
    procedure SelectProject(const AKey: string);
    procedure EditProjects;
    procedure Reopened(const AIssue: TAtlasTrackerIssue; AAction: TAtlasIssueReopenedAction);
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
  mTarget: TAtlasTrackerTarget;
  mState: TAtlasIssuesState;
  mFirst, mSecond: TAtlasTrackerIssue;
  mItems: TArray<TAtlasTrackerIssue>;
begin
  mTarget := TAtlasMyIssues.TargetFor('github', 'https://github.com/beispiel/atlas', '', '', '');
  mFirst := Issue('#753', 753, 'Atlas-Bereiche und Layout der Willkommensseite');
  mFirst.Labels := ['plugin', 'welcome'];
  mFirst.PullRequest.Number := 760;
  mFirst.PullRequest.Checks := TAtlasTrackerChecks.Success;
  mSecond := Issue('#612', 612, 'Parser für Generics');
  mItems := [mFirst, mSecond];
  mState := TAtlasIssuesState.Empty;
  TAtlasMyIssues.Recorded(mState, mTarget, NowUtc0, True, mItems, TAtlasCiFetchError.None);
  Result := TAtlasMyIssues.View(mState, mTarget, 'main');
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

procedure TFakeIssues.SelectProject(const AKey: string);
begin
  Calls := Calls + ['project:' + AKey];
end;

procedure TFakeIssues.EditProjects;
begin
  Calls := Calls + ['editProjects'];
end;

procedure TFakeIssues.Reopened(const AIssue: TAtlasTrackerIssue; AAction: TAtlasIssueReopenedAction);
const
  cNames: array[TAtlasIssueReopenedAction] of string = ('continue ', 'read ', 'reason ');
begin
  Calls := Calls + [cNames[AAction] + AIssue.Key];
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
  mSaved: TAtlasLanguage;
  mView: TAtlasIssuesView;
  mPull: TAtlasTrackerPullRequest;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mView := SampleView;
    Assert.AreEqual('Meine Issues · Atlas-IDE-Expert', TAtlasTrackerIssuesText.TitleText(mView.ProjectName));
    Assert.AreEqual('Meine Issues', TAtlasTrackerIssuesText.TitleText(''));
    // #1271: Punkt im Titel, solange ein Issue neue Änderungen hat; die Zeile trägt ihn auch.
    Assert.AreEqual('● Meine Issues · Atlas-IDE-Expert', TAtlasTrackerIssuesText.TitleText(mView.ProjectName, True));
    Assert.AreEqual('Meine Issues', TAtlasTrackerIssuesText.TitleText('', False));
    Assert.IsFalse(mView.IsUnseen(mView.Items[0].Key));
    mView.Unseen := [UpperCase(mView.Items[0].Key)];
    Assert.IsTrue(mView.IsUnseen(mView.Items[0].Key));
    Assert.IsFalse(mView.IsUnseen(mView.Items[1].Key));
    Assert.IsFalse(mView.IsUnseen(''));
    mView.Unseen := nil;
    // Mockup: Chip „PR #640 · CI grün“.
    Assert.AreEqual('PR #760 · CI grün', TAtlasTrackerIssuesText.PullRequestText(mView.Items[0].PullRequest));
    mPull := mView.Items[0].PullRequest;
    mPull.Checks := TAtlasTrackerChecks.Failure;
    Assert.AreEqual('PR #760 · CI rot', TAtlasTrackerIssuesText.PullRequestText(mPull));
    mPull.Checks := TAtlasTrackerChecks.Unknown;
    mPull.Draft := True;
    Assert.AreEqual('PR #760 (Entwurf)', TAtlasTrackerIssuesText.PullRequestText(mPull));
    Assert.AreEqual('', TAtlasTrackerIssuesText.PullRequestText(mView.Items[1].PullRequest));
    Assert.IsTrue(TAtlasTrackerIssuesText.ChecksColor(TAtlasTrackerChecks.Success) <>
      TAtlasTrackerIssuesText.ChecksColor(TAtlasTrackerChecks.Failure), 'rot ist nicht grün');
    // Hinweis auf „Beginnen“ mit dem Branch nach Muster (Abnahme: feature/753-atlas-bereiche-und).
    Assert.AreEqual('Branch: feature/753-atlas-bereiche-und', TAtlasTrackerIssuesText.StartHint(mView,
      mView.Items[0]));
    mView.Options.Start := TAtlasIssueStart.Remember;
    Assert.AreEqual('Merkt #753 als aktuelles Issue', TAtlasTrackerIssuesText.StartHint(mView, mView.Items[0]));
    // Kurztext wie die Kachel im Mockup: „ATL-123 · 3 offen“.
    Assert.AreEqual('GitHub · 2 offen', TAtlasTrackerIssuesText.TileText(mView));
    mView.Active.Key := 'ATL-123';
    mView.Items := mView.Items + [Issue('ATL-124', 124, 'x')];
    Assert.AreEqual('ATL-123 · 3 offen', TAtlasTrackerIssuesText.TileText(mView));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasTrackerIssuesViewTests.StatusAndFooter;
var
  mSaved: TAtlasLanguage;
  mView: TAtlasIssuesView;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mView := SampleView;
    // Frischer Stand: keine Zeile über der Liste; Fußzeile wie im Mockup.
    Assert.AreEqual('', TAtlasTrackerIssuesText.StatusText(mView));
    Assert.AreEqual('„Beginnen“ legt den Branch an und öffnet das Projekt.',
      TAtlasTrackerIssuesText.FooterText(mView));
    // Nach dem Klick: der Hinweis der Quelle.
    mView.Notice := 'Branch feature/753-atlas-bereiche-und von main angelegt, Projekt wird geöffnet.';
    Assert.AreEqual(mView.Notice, TAtlasTrackerIssuesText.FooterText(mView));
    mView.Notice := '';
    // Ohne Netz: der letzte Stand mit „Stand vom …“, kein Dialog.
    mView.Status := TAtlasIssuesStatus.Stale;
    mView.Error := TAtlasCiFetchError.Network;
    mView.At := NowUtc0;
    Assert.StartsWith('GitHub · nicht erreichbar · Stand vom ', TAtlasTrackerIssuesText.StatusText(mView));
    mView.Status := TAtlasIssuesStatus.Failed;
    mView.Error := TAtlasCiFetchError.Unauthorized;
    Assert.AreEqual('GitHub · Anmeldung vom Tracker abgelehnt: Token ungültig, abgelaufen oder ohne Rechte ' +
      '(Zugang zum Issue-Tracker neu hinterlegen)', TAtlasTrackerIssuesText.StatusText(mView));
    // Ohne Token gibt es keine Anfrage: eigener Hinweis statt „abgelehnt“.
    mView.Error := TAtlasCiFetchError.NoCredentials;
    Assert.AreEqual('GitHub · Noch kein Token: Rechtsklick › Zugang zum Issue-Tracker hinterlegen …',
      TAtlasTrackerIssuesText.StatusText(mView));
    mView.Status := TAtlasIssuesStatus.Waiting;
    mView.Querying := True;
    Assert.AreEqual('Issues werden abgefragt …', TAtlasTrackerIssuesText.StatusText(mView));
    mView.Status := TAtlasIssuesStatus.Ready;
    mView.Querying := False;
    mView.Items := nil;
    Assert.AreEqual('Keine offenen Issues für diese Abfrage.', TAtlasTrackerIssuesText.StatusText(mView));
    // Aktuelles Issue, das die Liste nicht (mehr) zeigt.
    mView.Active.Key := 'ATL-123';
    mView.Active.Title := 'Tracker';
    Assert.AreEqual('Aktuelles Issue: ATL-123 Tracker', TAtlasTrackerIssuesText.FooterText(mView));
    // Ohne Tracker in .atlas bzw. ohne Projekt.
    mView.Status := TAtlasIssuesStatus.NotConfigured;
    Assert.AreEqual('', TAtlasTrackerIssuesText.StatusText(mView));
    Assert.Contains(TAtlasTrackerIssuesText.FooterText(mView), 'tracker');
    mView.Project := '';
    Assert.Contains(TAtlasTrackerIssuesText.FooterText(mView), 'Noch kein Projekt');
    // Ohne Git und SVN wird nur gemerkt.
    mView := SampleView;
    mView.VcsKind := TAtlasVcsKind.None;
    Assert.Contains(TAtlasTrackerIssuesText.FooterText(mView), 'merkt');
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasTrackerIssuesViewTests.EnglishTexts;
var
  mSaved: TAtlasLanguage;
  mView: TAtlasIssuesView;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.English;
    mView := SampleView;
    Assert.AreEqual('My issues · Atlas-IDE-Expert', TAtlasTrackerIssuesText.TitleText(mView.ProjectName));
    Assert.AreEqual('PR #760 · CI green', TAtlasTrackerIssuesText.PullRequestText(mView.Items[0].PullRequest));
    Assert.AreEqual('“Start” creates the branch and opens the project.', TAtlasTrackerIssuesText.FooterText(mView));
    Assert.AreEqual('GitHub · 2 open', TAtlasTrackerIssuesText.TileText(mView));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasTrackerIssuesViewTests.ClicksReachSource;
var
  mHost: TForm;
  mFake: TFakeIssues;
  mSource: IAtlasIssuesSource;
  mFrame: TAtlasTrackerIssuesView;
begin
  mFake := TFakeIssues.Create;
  mSource := mFake;
  mFake.FView := SampleView;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasTrackerIssuesView.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Width := 600;
    mFrame.Source := mSource;
    Assert.AreEqual(1, Integer(Length(mFake.Calls)), 'Shown beim Setzen der Quelle');
    Assert.AreEqual('shown', mFake.Calls[0]);
    mFake.Calls := nil;
    Assert.IsTrue(mFrame.CanStart);
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Key, 0));
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.PullRequest, 0));
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Start, 0));
    // Zeile selbst und Zeilen außerhalb tun nichts.
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Row, 1));
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Start, 9));
    mFrame.Menus.MenuRow := 1;
    mFrame.Menus.StartRememberItem.Click;
    mFrame.Menus.QueryItem.Click;
    mFrame.Menus.CredentialsItem.Click;
    mFrame.Menus.EndItem.Click;
    Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(7, Integer(Length(mFake.Calls)));
    Assert.AreEqual('browse #753', mFake.Calls[0]);
    Assert.AreEqual('pr 760', mFake.Calls[1]);
    Assert.AreEqual('start #753 branch', mFake.Calls[2]);
    Assert.AreEqual('start #612 remember', mFake.Calls[3]);
    Assert.AreEqual('query', mFake.Calls[4]);
    Assert.AreEqual('login', mFake.Calls[5]);
    Assert.AreEqual('end', mFake.Calls[6]);
    // Während „Beginnen“ läuft, kein zweites.
    mFake.Calls := nil;
    mFake.FView.Starting := True;
    mFrame.UpdateContent;
    Assert.IsFalse(mFrame.CanStart);
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Start, 0));
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(mFake.Calls)));
    Assert.IsTrue(mFrame.HitTest(20, -5).Kind = TAtlasIssuesHitKind.None, 'über der ersten Zeile');
  finally
    mHost.Free;
    mFake.Calls := nil;
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

/// <summary>Zwei Tracker-Projekte für die Klappliste.</summary>
function ChoicesView: TAtlasIssuesView;
begin
  Result := SampleView;
  Result.ProjectPicker := True;
  Result.AllProjects := True;
  Result.AutomaticName := 'Kasse';
  Result.ProjectChoices := TAtlasTrackerProjects.Choices(TAtlasTrackerProjects.Read(
    '[{"match": "C:\\Kasse", "connection": "Firma", "project": "KASSE"}, ' +
    '{"match": "C:\\Atlas", "connection": "GitHub", "project": "owner/repo"}]'),
    TAtlasTrackerConnections.Read('[{"name": "Firma", "provider": "youtrack", "url": "https://yt.local"}, ' +
    '{"name": "GitHub", "provider": "github", "url": "https://github.com"}]'));
end;

procedure TAtlasTrackerIssuesViewTests.ProjectPickerAndGroups;
var
  mSaved: TAtlasLanguage;
  mHost: TForm;
  mFake: TFakeIssues;
  mSource: IAtlasIssuesSource;
  mFrame: TAtlasTrackerIssuesView;
  mView, mGroup: TAtlasIssuesView;
  mTop: Integer;
begin
  mSaved := TAtlasStrings.Language;
  mFake := TFakeIssues.Create;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mView := ChoicesView;
    Assert.AreEqual(2, Integer(Length(mView.ProjectChoices)));
    Assert.IsTrue(TAtlasTrackerProjectPicker.Shows(mView));
    Assert.AreEqual('Projekt: Automatisch', TAtlasTrackerProjectPicker.CaptionOf(mView));
    mFake.FView := mView;
    mFrame := TAtlasTrackerIssuesView.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Width := 600;
    mFrame.Source := mSource;
    Assert.IsTrue(mFrame.Queries.Projects.Visible);
    Assert.IsTrue(mFrame.Queries.Bar.Visible);
    // Automatisch (mit Projekt), zwei Tracker-Projekte, Alle, Linie, bearbeiten.
    mFrame.Queries.Projects.Fill;
    Assert.AreEqual(6, mFrame.Queries.Projects.Menu.Items.Count);
    Assert.AreEqual('Automatisch – nach dem Delphi-Projekt (Kasse)', mFrame.Queries.Projects.Menu.Items[0].Caption);
    Assert.IsTrue(mFrame.Queries.Projects.Menu.Items[0].Checked);
    Assert.AreEqual('Firma · KASSE', mFrame.Queries.Projects.Menu.Items[1].Caption);
    Assert.AreEqual('Alle Tracker-Projekte', mFrame.Queries.Projects.Menu.Items[3].Caption);
    mFake.Calls := nil;
    mFrame.Queries.Projects.Menu.Items[1].Click;
    mFrame.Queries.Projects.Menu.Items[3].Click;
    mFrame.Queries.Projects.Menu.Items[5].Click;
    Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'nicht im Menüereignis');
    CheckSynchronize;
    Assert.AreEqual(3, Integer(Length(mFake.Calls)));
    Assert.AreEqual('project:KASSE@Firma', mFake.Calls[0]);
    Assert.AreEqual('project:*', mFake.Calls[1]);
    Assert.AreEqual('editProjects', mFake.Calls[2]);
    // Gewählt: Beschriftung mit dem Tracker-Projekt; ohne issues.allProjects kein „Alle“.
    mView.ProjectKey := 'owner/repo@GitHub';
    mView.AllProjects := False;
    Assert.AreEqual('Projekt: GitHub · owner/repo', TAtlasTrackerProjectPicker.CaptionOf(mView));
    mFake.FView := mView;
    mFrame.UpdateContent;
    mFrame.Queries.Projects.Fill;
    Assert.AreEqual(5, mFrame.Queries.Projects.Menu.Items.Count);
    Assert.IsTrue(mFrame.Queries.Projects.Menu.Items[2].Checked);
    // issues.projectPicker aus: keine Klappliste.
    mView.ProjectPicker := False;
    mFake.FView := mView;
    mFrame.UpdateContent;
    Assert.IsFalse(mFrame.Queries.Projects.Visible);
    // „Alle“ (#1928): Kopf je Gruppe, die Zeilen rücken darunter.
    mView := ChoicesView;
    mView.Items := nil;
    mGroup := SampleView;
    TAtlasMyIssues.AddGroup(mView, 'Firma · KASSE', 'C:\Kasse', mGroup, 1);
    mGroup.Status := TAtlasIssuesStatus.Failed;
    mGroup.Error := TAtlasCiFetchError.NoCredentials;
    mGroup.Items := nil;
    TAtlasMyIssues.AddGroup(mView, 'GitHub · owner/repo', 'C:\Atlas', mGroup, 1);
    Assert.AreEqual(Format('Firma · KASSE (%d)', [Length(SampleView.Items)]),
      TAtlasTrackerIssuesText.GroupCaption(mView.Groups[0]));
    Assert.AreEqual(Format('+ %d weitere', [Length(SampleView.Items) - 1]),
      TAtlasTrackerIssuesText.GroupNote(mView.Groups[0]));
    Assert.AreEqual('Kein Zugang hinterlegt', TAtlasTrackerIssuesText.GroupNote(mView.Groups[1]));
    mFake.FView := mView;
    mFrame.UpdateContent;
    mTop := mFrame.Painter.ListTop;
    Assert.AreEqual(mTop + mFrame.ScaleValue(TAtlasTrackerIssuesView.cStatusHeight), mFrame.Painter.RowTop(0));
    Assert.AreEqual(mTop + 2 * mFrame.ScaleValue(TAtlasTrackerIssuesView.cStatusHeight) +
      mFrame.Painter.RowHeight(0), mFrame.Painter.FooterTop, 'Kopf der leeren Gruppe vor der Fußzeile');
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Project: Automatic', TAtlasTrackerProjectPicker.CaptionOf(ChoicesView));
  finally
    TAtlasStrings.Language := mSaved;
    mHost.Free;
    mFake.Calls := nil;
    mFake.FView := Default(TAtlasIssuesView);
  end;
end;

procedure TAtlasTrackerIssuesViewTests.ReopenedRow;
var
  mHost: TForm;
  mFake: TFakeIssues;
  mSource: IAtlasIssuesSource;
  mFrame: TAtlasTrackerIssuesView;
  mSaved: TAtlasLanguage;
  mReopen: TAtlasTrackerReopen;
  mPlain: Integer;
begin
  mSaved := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
  mFake := TFakeIssues.Create;
  mSource := mFake;
  mFake.FView := SampleView;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasTrackerIssuesView.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Width := 600;
    mFrame.Source := mSource;
    mPlain := mFrame.Painter.RowHeight(1);
    mReopen := Default(TAtlasTrackerReopen);
    mReopen.Key := '#612';
    mReopen.Branch := 'issue/612';
    mReopen.State := 'open';
    mReopen.Previous := 'closed';
    mReopen.CommentBy := 'jana';
    mReopen.CommentAt := NowUtc0 - 20 / MinsPerDay;
    mReopen.Comment := 'Lesezeichen fehlen.';
    mFake.FView.Reopened := [mReopen];
    mFrame.UpdateContent;
    // Zeile ohne Chips: Chip-Zeile, Grund und Knöpfe kommen dazu.
    Assert.AreEqual(mPlain + mFrame.ScaleValue(TAtlasTrackerIssuesView.cChipLineHeight) +
      mFrame.ScaleValue(TAtlasTrackerIssuesView.cLineHeight) +
      mFrame.ScaleValue(TAtlasTrackerIssuesView.cActionLineHeight), mFrame.Painter.RowHeight(1));
    Assert.AreEqual('jana, vor 20 Min.: „Lesezeichen fehlen.“',
      TAtlasTrackerIssuesText.ReasonText(mReopen, NowUtc0));
    Assert.AreEqual('Weiterarbeiten auf issue/612', TAtlasTrackerIssuesText.ContinueText(mReopen));
    mReopen.Comment := '';
    Assert.AreEqual('closed → open, kein neuer Kommentar', TAtlasTrackerIssuesText.ReasonText(mReopen, NowUtc0));
    mReopen.Branch := '';
    Assert.AreEqual('Weiterarbeiten', TAtlasTrackerIssuesText.ContinueText(mReopen));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Continue', TAtlasTrackerIssuesText.ContinueText(mReopen));
    TAtlasStrings.Language := TAtlasLanguage.German;
    mFake.Calls := nil;
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Continue, 1));
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Reason, 1));
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Dismiss, 1));
    CheckSynchronize;
    Assert.AreEqual(3, Integer(Length(mFake.Calls)));
    Assert.AreEqual('continue #612', mFake.Calls[0]);
    Assert.AreEqual('reason #612', mFake.Calls[1]);
    Assert.AreEqual('read #612', mFake.Calls[2]);
    // Während „Beginnen“ läuft, kein „Weiterarbeiten“; „Gelesen“ geht weiter.
    mFake.Calls := nil;
    mFake.FView.Starting := True;
    mFrame.UpdateContent;
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Continue, 1));
    mFrame.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Dismiss, 1));
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(mFake.Calls)));
    Assert.AreEqual('read #612', mFake.Calls[0]);
  finally
    TAtlasStrings.Language := mSaved;
    mHost.Free;
    mFake.Calls := nil;
    mFake.FView := Default(TAtlasIssuesView);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerIssuesViewTests);

end.
