unit Atlas.UI.Welcome.Issues.Tests;

// Bereich „Meine Issues“ der Willkommensseite (#765, Mockup #ws12): Titel,
// Chip des Pull Requests mit CI-Ampel, Zeile zum Stand („Stand vom …“ ohne
// Netz), Fußzeile vor und nach „Beginnen“, Kurztext „ATL-123 · 3 offen“;
// Klicks auf Kennung, Pull Request und „Beginnen“ erreichen die Quelle über
// die Nachrichtenschleife; Kontextmenü mit „Nur merken“, „Zugang …“ nur mit
// Schalter TrackerLogin und „Beenden“ nur mit aktuellem Issue.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasWelcomeIssuesFrameTests = class
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
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  Vcl.Forms,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Welcome.Issues,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Issues;

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
    procedure BrowsePullRequest(const AIssue: TAtlasTrackerIssue);
    procedure QueryNow;
    procedure Credentials;
    function CanEnterCredentials: Boolean;
    procedure EndActive;
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
  Target := TAtlasWelcomeIssues.TargetFor('github', 'https://github.com/beispiel/atlas', '', '', '');
  First := Issue('#753', 753, 'Atlas-Bereiche und Layout der Willkommensseite');
  First.Labels := ['plugin', 'welcome'];
  First.PullRequest.Number := 760;
  First.PullRequest.Checks := TAtlasTrackerChecks.Success;
  Second := Issue('#612', 612, 'Parser für Generics');
  Items := [First, Second];
  State := TAtlasIssuesState.Empty;
  TAtlasWelcomeIssues.Recorded(State, Target, NowUtc0, True, Items, TAtlasCiFetchError.None);
  Result := TAtlasWelcomeIssues.View(State, Target, 'main');
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
  Calls := Calls + ['start ' + AIssue.Key + ' ' + TAtlasWelcomeIssues.StartName(AMode)];
end;

procedure TFakeIssues.Browse(const AIssue: TAtlasTrackerIssue);
begin
  Calls := Calls + ['browse ' + AIssue.Key];
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

{ TAtlasWelcomeIssuesFrameTests }

procedure TAtlasWelcomeIssuesFrameTests.WarmUpFirstUse;
begin
  try
    ClicksReachSource;
  except
    on Exception do
      ;
  end;
end;

procedure TAtlasWelcomeIssuesFrameTests.TextsFollowMockup;
var
  Saved: TAtlasLanguage;
  View: TAtlasIssuesView;
  Pull: TAtlasTrackerPullRequest;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    View := SampleView;
    Assert.AreEqual('Meine Issues · Atlas-IDE-Expert', TAtlasWelcomeIssuesFrame.TitleText(View.ProjectName));
    Assert.AreEqual('Meine Issues', TAtlasWelcomeIssuesFrame.TitleText(''));
    // Mockup: Chip „PR #640 · CI grün“.
    Assert.AreEqual('PR #760 · CI grün', TAtlasWelcomeIssuesFrame.PullRequestText(View.Items[0].PullRequest));
    Pull := View.Items[0].PullRequest;
    Pull.Checks := TAtlasTrackerChecks.Failure;
    Assert.AreEqual('PR #760 · CI rot', TAtlasWelcomeIssuesFrame.PullRequestText(Pull));
    Pull.Checks := TAtlasTrackerChecks.Unknown;
    Pull.Draft := True;
    Assert.AreEqual('PR #760 (Entwurf)', TAtlasWelcomeIssuesFrame.PullRequestText(Pull));
    Assert.AreEqual('', TAtlasWelcomeIssuesFrame.PullRequestText(View.Items[1].PullRequest));
    Assert.IsTrue(TAtlasWelcomeIssuesFrame.ChecksColor(TAtlasTrackerChecks.Success) <>
      TAtlasWelcomeIssuesFrame.ChecksColor(TAtlasTrackerChecks.Failure), 'rot ist nicht grün');
    // Hinweis auf „Beginnen“ mit dem Branch nach Muster (Abnahme: feature/753-atlas-bereiche-und).
    Assert.AreEqual('Branch: feature/753-atlas-bereiche-und', TAtlasWelcomeIssuesFrame.StartHint(View,
      View.Items[0]));
    View.Options.Start := TAtlasIssueStart.Remember;
    Assert.AreEqual('Merkt #753 als aktuelles Issue', TAtlasWelcomeIssuesFrame.StartHint(View, View.Items[0]));
    // Kurztext wie die Kachel im Mockup: „ATL-123 · 3 offen“.
    Assert.AreEqual('GitHub · 2 offen', TAtlasWelcomeIssuesFrame.TileText(View));
    View.Active.Key := 'ATL-123';
    View.Items := View.Items + [Issue('ATL-124', 124, 'x')];
    Assert.AreEqual('ATL-123 · 3 offen', TAtlasWelcomeIssuesFrame.TileText(View));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeIssuesFrameTests.StatusAndFooter;
var
  Saved: TAtlasLanguage;
  View: TAtlasIssuesView;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    View := SampleView;
    // Frischer Stand: keine Zeile über der Liste; Fußzeile wie im Mockup.
    Assert.AreEqual('', TAtlasWelcomeIssuesFrame.StatusText(View, NowUtc0));
    Assert.AreEqual('„Beginnen“ legt den Branch an und öffnet das Projekt.',
      TAtlasWelcomeIssuesFrame.FooterText(View));
    // Nach dem Klick: der Hinweis der Quelle.
    View.Notice := 'Branch feature/753-atlas-bereiche-und von main angelegt, Projekt wird geöffnet.';
    Assert.AreEqual(View.Notice, TAtlasWelcomeIssuesFrame.FooterText(View));
    View.Notice := '';
    // Ohne Netz: der letzte Stand mit „Stand vom …“, kein Dialog.
    View.Status := TAtlasIssuesStatus.Stale;
    View.Error := TAtlasCiFetchError.Network;
    View.At := NowUtc0;
    Assert.StartsWith('GitHub · nicht erreichbar · Stand vom ', TAtlasWelcomeIssuesFrame.StatusText(View, NowUtc0));
    View.Status := TAtlasIssuesStatus.Failed;
    View.Error := TAtlasCiFetchError.Unauthorized;
    Assert.AreEqual('GitHub · Anmeldung abgelehnt oder kein Token (Zugang zum Issue-Tracker hinterlegen)',
      TAtlasWelcomeIssuesFrame.StatusText(View, NowUtc0));
    View.Status := TAtlasIssuesStatus.Waiting;
    View.Querying := True;
    Assert.AreEqual('Issues werden abgefragt …', TAtlasWelcomeIssuesFrame.StatusText(View, NowUtc0));
    View.Status := TAtlasIssuesStatus.Ready;
    View.Querying := False;
    View.Items := nil;
    Assert.AreEqual('Keine offenen Issues für diese Abfrage.', TAtlasWelcomeIssuesFrame.StatusText(View, NowUtc0));
    // Aktuelles Issue, das die Liste nicht (mehr) zeigt.
    View.Active.Key := 'ATL-123';
    View.Active.Title := 'Tracker';
    Assert.AreEqual('Aktuelles Issue: ATL-123 Tracker', TAtlasWelcomeIssuesFrame.FooterText(View));
    // Ohne Tracker in .atlas bzw. ohne Projekt.
    View.Status := TAtlasIssuesStatus.NotConfigured;
    Assert.AreEqual('', TAtlasWelcomeIssuesFrame.StatusText(View, NowUtc0));
    Assert.Contains(TAtlasWelcomeIssuesFrame.FooterText(View), 'tracker');
    View.Project := '';
    Assert.Contains(TAtlasWelcomeIssuesFrame.FooterText(View), 'Noch kein Projekt');
    // Ohne Git und SVN wird nur gemerkt.
    View := SampleView;
    View.VcsKind := TAtlasVcsKind.None;
    Assert.Contains(TAtlasWelcomeIssuesFrame.FooterText(View), 'merkt');
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeIssuesFrameTests.EnglishTexts;
var
  Saved: TAtlasLanguage;
  View: TAtlasIssuesView;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.English;
    View := SampleView;
    Assert.AreEqual('My issues · Atlas-IDE-Expert', TAtlasWelcomeIssuesFrame.TitleText(View.ProjectName));
    Assert.AreEqual('PR #760 · CI green', TAtlasWelcomeIssuesFrame.PullRequestText(View.Items[0].PullRequest));
    Assert.AreEqual('“Start” creates the branch and opens the project.', TAtlasWelcomeIssuesFrame.FooterText(View));
    Assert.AreEqual('GitHub · 2 open', TAtlasWelcomeIssuesFrame.TileText(View));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeIssuesFrameTests.ClicksReachSource;
var
  Host: TForm;
  Fake: TFakeIssues;
  Source: IAtlasIssuesSource;
  Frame: TAtlasWelcomeIssuesFrame;
begin
  Fake := TFakeIssues.Create;
  Source := Fake;
  Fake.FView := SampleView;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeIssuesFrame.Create(Host);
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
    Frame.MenuRow := 1;
    Frame.StartRememberItem.Click;
    Frame.QueryItem.Click;
    Frame.CredentialsItem.Click;
    Frame.EndItem.Click;
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

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeIssuesFrameTests);

end.
