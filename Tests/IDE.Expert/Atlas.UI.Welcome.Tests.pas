unit Atlas.UI.Welcome.Tests;

// Oberfläche der Atlas-Willkommensseite (#753): Texte im Kopf (Grußzeile,
// Kurzstatus, Tausendertrennzeichen je Sprache), Fabriken der Bereiche und
// der Frame „Atlas“ mit Kopf und Bereichen in Spalten; Suchfeld im Kopf
// (#760): Ein-/Ausblenden, Abfrage, Auswahl mit Grenzen, Öffnen und Esc;
// Karte „Neu in Atlas“ (#756): Zeilen mit Schalter, Taste und
// „Ausprobieren“, Gruppen je Version, Auf- und Zuklappen, Kontextmenü.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasWelcomeHeaderTests = class
  public
    [Test]
    procedure GreetingFollowsHourAndName;
    [Test]
    procedure StatusShowsServerAndIndex;
    [Test]
    procedure ThousandsFollowLanguage;
    [Test]
    procedure InfoShowsVersion;
    [Test]
    procedure ShowInfoFillsLabels;
  end;

  [TestFixture]
  TAtlasWelcomeBoardTests = class
  public
    [Test]
    procedure ViewsCreateFramesWithId;
    [Test]
    procedure BoardPlacesSectionsInColumns;
    [Test]
    procedure BoardKeepsAndDropsFrames;
  end;

  [TestFixture]
  TAtlasWelcomeSearchBoxTests = class
  public
    [Test]
    procedure HeaderShowsAndHidesSearch;
    [Test]
    procedure QueryFillsHitsAndRows;
    [Test]
    procedure SelectStaysInRange;
    [Test]
    procedure OpenSelectedHandsHitAndClears;
    [Test]
    procedure GroupCaptionsFollowLanguage;
  end;

  [TestFixture]
  TAtlasWelcomeWhatsNewFrameTests = class
  public
    [Test]
    procedure UnreadShowsRowsWithSwitchKeyAndTry;
    [Test]
    procedure JumpGroupsByVersion;
    [Test]
    procedure AllVersionsCollapseExceptNewest;
    [Test]
    procedure ClicksReachSource;
    [Test]
    procedure TitleNamesSingleVersion;
    [Test]
    procedure BoardSizesCardToItsText;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.Core.Status.Lines,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Layout,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.Header,
  Atlas.UI.Welcome.Board,
  Atlas.Core.Welcome.Search,
  Atlas.UI.Welcome.Search,
  Atlas.Core.Welcome.WhatsNew,
  Atlas.UI.Welcome.WhatsNew;

type
  /// <summary>Quelle der Karte für die Tests; merkt sich die Aufrufe.</summary>
  TFakeWhatsNew = class(TInterfacedObject, IAtlasWhatsNewSource)
  public
    FView: TAtlasWhatsNewView;
    FVersions: TAtlasWhatsNewVersions;
    Calls: TArray<string>;
    function View: TAtlasWhatsNewView;
    function Versions: TAtlasWhatsNewVersions;
    function SwitchOf(const ASetting: string): TAtlasWhatsNewSwitch;
    function KeyText(const AKey: string): string;
    function CanTry(const AItem: TAtlasWhatsNewItem): Boolean;
    procedure SetSwitch(const ASetting: string; AOn: Boolean);
    procedure TryItem(const AItem: TAtlasWhatsNewItem);
    procedure Dismiss;
    procedure Show(AView: TAtlasWhatsNewView);
  end;

function TFakeWhatsNew.View: TAtlasWhatsNewView;
begin
  Result := FView;
end;

function TFakeWhatsNew.Versions: TAtlasWhatsNewVersions;
begin
  Result := FVersions;
end;

function TFakeWhatsNew.SwitchOf(const ASetting: string): TAtlasWhatsNewSwitch;
begin
  if ASetting = 'An' then
    Result := TAtlasWhatsNewSwitch.On
  else if ASetting = 'Aus' then
    Result := TAtlasWhatsNewSwitch.Off
  else
    Result := TAtlasWhatsNewSwitch.None;
end;

function TFakeWhatsNew.KeyText(const AKey: string): string;
begin
  Result := '';
  if AKey = 'Taste' then
    Result := 'Ctrl+E';
end;

function TFakeWhatsNew.CanTry(const AItem: TAtlasWhatsNewItem): Boolean;
begin
  Result := (AItem.Command <> '') or (AItem.Sample <> '');
end;

procedure TFakeWhatsNew.SetSwitch(const ASetting: string; AOn: Boolean);
begin
  Calls := Calls + [Format('switch %s %s', [ASetting, BoolToStr(AOn, True)])];
end;

procedure TFakeWhatsNew.TryItem(const AItem: TAtlasWhatsNewItem);
begin
  Calls := Calls + ['try ' + AItem.Title];
end;

procedure TFakeWhatsNew.Dismiss;
begin
  Calls := Calls + ['dismiss'];
end;

procedure TFakeWhatsNew.Show(AView: TAtlasWhatsNewView);
begin
  Calls := Calls + [Format('show %d', [Ord(AView)])];
end;

function NewsItem(const ATitle, ASetting, AKey, ACommand: string): TAtlasWhatsNewItem;
begin
  Result := Default(TAtlasWhatsNewItem);
  Result.Title := ATitle;
  Result.Text := 'Ein Satz zu ' + ATitle + ', lang genug, damit er in einer schmalen Karte umbricht.';
  Result.Setting := ASetting;
  Result.Key := AKey;
  Result.Command := ACommand;
end;

function NewsVersion(const AVersion: string; const AItems: TArray<TAtlasWhatsNewItem>): TAtlasWhatsNewVersion;
begin
  Result.Version := AVersion;
  Result.Items := AItems;
end;

/// <summary>Karte in einem Formular (Labels brauchen ein Fenster zum Messen).</summary>
function NewsFrame(AHost: TForm; const ASource: IAtlasWhatsNewSource): TAtlasWelcomeWhatsNewFrame;
begin
  Result := TAtlasWelcomeWhatsNewFrame.Create(AHost);
  Result.Parent := AHost;
  Result.SetBounds(0, 0, 420, 300);
  Result.Source := ASource;
end;

{ TAtlasWelcomeHeaderTests }

procedure TAtlasWelcomeHeaderTests.GreetingFollowsHourAndName;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Guten Morgen, Marco', TAtlasWelcomeHeaderFrame.GreetingText(8, 'Marco'));
    Assert.AreEqual('Guten Tag, Marco', TAtlasWelcomeHeaderFrame.GreetingText(14, 'Marco'));
    Assert.AreEqual('Guten Abend, Marco', TAtlasWelcomeHeaderFrame.GreetingText(20, 'Marco'));
    Assert.AreEqual('Gute Nacht', TAtlasWelcomeHeaderFrame.GreetingText(2, ''), 'ohne Namen nur der Gruß');
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Good evening, Marco', TAtlasWelcomeHeaderFrame.GreetingText(20, 'Marco'));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeHeaderTests.StatusShowsServerAndIndex;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Server läuft · 1.284 Units im Index',
      TAtlasWelcomeHeaderFrame.StatusText(TAtlasServerPhase.Running, 1284, False, -1));
    Assert.AreEqual('Server läuft · Index wird aufgebaut (45 %)',
      TAtlasWelcomeHeaderFrame.StatusText(TAtlasServerPhase.Running, 1284, True, 45));
    Assert.AreEqual('Server läuft · Index wird aufgebaut',
      TAtlasWelcomeHeaderFrame.StatusText(TAtlasServerPhase.Running, -1, True, -1));
    Assert.AreEqual('Server läuft', TAtlasWelcomeHeaderFrame.StatusText(TAtlasServerPhase.Running, -1, False, -1),
      'Units unbekannt');
    Assert.AreEqual('Server startet mit dem ersten Projekt',
      TAtlasWelcomeHeaderFrame.StatusText(TAtlasServerPhase.NotStarted, 10, False, -1));
    Assert.AreEqual('Server fehlt', TAtlasWelcomeHeaderFrame.StatusText(TAtlasServerPhase.Failed, 10, True, 5),
      'Index nur bei laufendem Server');
    Assert.AreEqual('Server gestoppt', TAtlasWelcomeHeaderFrame.StatusText(TAtlasServerPhase.Stopped, 10, False, -1));
    Assert.AreEqual('Server startet', TAtlasWelcomeHeaderFrame.StatusText(TAtlasServerPhase.Starting, 10, False, -1));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeHeaderTests.ThousandsFollowLanguage;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('1.234.567', TAtlasWelcomeHeaderFrame.Thousands(1234567));
    Assert.AreEqual('0', TAtlasWelcomeHeaderFrame.Thousands(0));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('1,284', TAtlasWelcomeHeaderFrame.Thousands(1284));
    Assert.AreEqual('Server running · 1,284 units in the index',
      TAtlasWelcomeHeaderFrame.StatusText(TAtlasServerPhase.Running, 1284, False, -1));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeHeaderTests.InfoShowsVersion;
var
  Saved: TAtlasLanguage;
  Info: TAtlasWelcomeHeaderInfo;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Info := Default(TAtlasWelcomeHeaderInfo);
    Info.Version := '1.0.0';
    Info.Phase := TAtlasServerPhase.Stopped;
    Info.Units := -1;
    Info.Percent := -1;
    Assert.AreEqual('Atlas 1.0.0 · Server gestoppt', TAtlasWelcomeHeaderFrame.InfoText(Info));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeHeaderTests.ShowInfoFillsLabels;
var
  Saved: TAtlasLanguage;
  Header: TAtlasWelcomeHeaderFrame;
  Info: TAtlasWelcomeHeaderInfo;
begin
  Saved := TAtlasStrings.Language;
  Header := TAtlasWelcomeHeaderFrame.Create(nil);
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Info := Default(TAtlasWelcomeHeaderInfo);
    Info.Greeting := True;
    Info.Hour := 9;
    Info.FirstName := 'Marco';
    Info.Version := '1.0.0';
    Info.Phase := TAtlasServerPhase.Running;
    Info.Units := 42;
    Info.Percent := -1;
    Header.ShowInfo(Info);
    Assert.AreEqual('Guten Morgen, Marco', Header.GreetingLabel.Caption);
    Assert.AreEqual('Atlas 1.0.0 · Server läuft · 42 Units im Index', Header.InfoLabel.Caption);
    Assert.AreEqual(0, Header.SearchHost.Width, 'Platz für das Suchfeld (#760) noch leer');
    // welcomePage.greeting aus: nur „Atlas“.
    Info.Greeting := False;
    Header.ShowInfo(Info);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.WelcomeHeaderTitle), Header.GreetingLabel.Caption);
  finally
    Header.Free;
    TAtlasStrings.Language := Saved;
  end;
end;

{ TAtlasWelcomeBoardTests }

type
  TTestSection = class(TAtlasWelcomeSectionFrame)
  public
    Updates: Integer;
    procedure UpdateContent; override;
  end;

procedure TTestSection.UpdateContent;
begin
  Inc(Updates);
  inherited;
end;

procedure RegisterViews(const AIds: array of string);
var
  Id: string;
begin
  for Id in AIds do
    TAtlasWelcomeViews.Register(Id,
      function(AOwner: TComponent): TAtlasWelcomeSectionFrame
      begin
        Result := TTestSection.Create(AOwner);
      end);
end;

function Section(const AId: string; AOrder: Integer; AColumn: TAtlasWelcomeColumn): TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(AId, 'Titel ' + AId, AOrder, AColumn, nil);
end;

procedure TAtlasWelcomeBoardTests.ViewsCreateFramesWithId;
var
  View: TAtlasWelcomeSectionFrame;
begin
  RegisterViews([TAtlasWelcomeIds.State]);
  try
    Assert.IsTrue(TAtlasWelcomeViews.Exists('ATLAS.STATE'));
    Assert.IsFalse(TAtlasWelcomeViews.Exists(TAtlasWelcomeIds.News));
    Assert.IsNull(TAtlasWelcomeViews.CreateView(TAtlasWelcomeIds.News, nil));
    View := TAtlasWelcomeViews.CreateView(TAtlasWelcomeIds.State, nil);
    try
      Assert.IsNotNull(View);
      Assert.AreEqual(TAtlasWelcomeIds.State, View.SectionId);
      Assert.IsTrue(View.ShowTitle);
      Assert.AreEqual(TAtlasWelcomeSectionFrame.TitleHeight + TAtlasWelcomeSectionFrame.DefaultBodyHeight,
        View.PreferredHeight);
      View.ShowTitle := False;
      Assert.AreEqual(TAtlasWelcomeSectionFrame.DefaultBodyHeight, View.PreferredHeight);
    finally
      View.Free;
    end;
    TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.State);
    Assert.IsFalse(TAtlasWelcomeViews.Exists(TAtlasWelcomeIds.State));
  finally
    TAtlasWelcomeViews.Release;
  end;
end;

procedure TAtlasWelcomeBoardTests.BoardPlacesSectionsInColumns;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Left, Right, Below: TAtlasWelcomeSectionFrame;
begin
  RegisterViews([TAtlasWelcomeIds.Continue, TAtlasWelcomeIds.Projects, TAtlasWelcomeIds.State]);
  Host := TForm.CreateNew(nil);
  try
    Host.ClientWidth := 800;
    Host.ClientHeight := 600;
    Board := TAtlasWelcomeBoardFrame.Create(Host);
    Board.Parent := Host;
    Board.Align := alClient;
    Board.Rebuild([Section(TAtlasWelcomeIds.State, 10, TAtlasWelcomeColumn.Right),
      Section(TAtlasWelcomeIds.Continue, 20, TAtlasWelcomeColumn.Left),
      Section(TAtlasWelcomeIds.Projects, 30, TAtlasWelcomeColumn.Left),
      Section(TAtlasWelcomeIds.News, 40, TAtlasWelcomeColumn.Right)], TAtlasWelcomeLayout.Atlas, 2);
    Assert.AreEqual(2, Integer(Length(Board.Columns)));
    Left := Board.View(TAtlasWelcomeIds.Continue);
    Below := Board.View(TAtlasWelcomeIds.Projects);
    Right := Board.View(TAtlasWelcomeIds.State);
    Assert.IsNotNull(Left);
    Assert.IsNull(Board.View(TAtlasWelcomeIds.News), 'ohne Fabrik kein Frame');
    Assert.AreEqual('Titel ' + TAtlasWelcomeIds.Continue, Left.Title);
    Assert.IsTrue(Left.ShowTitle);
    Assert.AreEqual(Left.Left, Below.Left, 'gleiche Spalte');
    Assert.IsTrue(Below.Top > Left.Top + Left.Height - 1, 'untereinander');
    Assert.IsTrue(Right.Left > Left.Left + Left.Width - 1, 'rechte Spalte');
    Assert.AreEqual(Left.Top, Right.Top);
    Assert.IsTrue(TTestSection(Left).Updates > 0, 'neuer Frame liest seinen Inhalt');
    // Eine Spalte (Fenster „Atlas-Start“): alles untereinander.
    Board.Rebuild([Section(TAtlasWelcomeIds.State, 10, TAtlasWelcomeColumn.Right),
      Section(TAtlasWelcomeIds.Continue, 20, TAtlasWelcomeColumn.Left)], TAtlasWelcomeLayout.Atlas, 1);
    Assert.AreEqual(Board.View(TAtlasWelcomeIds.Continue).Left, Board.View(TAtlasWelcomeIds.State).Left);
    Assert.IsTrue(Board.View(TAtlasWelcomeIds.State).Top > Board.View(TAtlasWelcomeIds.Continue).Top);
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;

procedure TAtlasWelcomeBoardTests.BoardKeepsAndDropsFrames;
var
  Board: TAtlasWelcomeBoardFrame;
  Kept: TAtlasWelcomeSectionFrame;
  Before: Integer;
begin
  RegisterViews([TAtlasWelcomeIds.Continue, TAtlasWelcomeIds.State]);
  Board := TAtlasWelcomeBoardFrame.Create(nil);
  try
    Board.Rebuild([Section(TAtlasWelcomeIds.Continue, 20, TAtlasWelcomeColumn.Left),
      Section(TAtlasWelcomeIds.State, 10, TAtlasWelcomeColumn.Right)], TAtlasWelcomeLayout.Atlas, 2);
    Kept := Board.View(TAtlasWelcomeIds.Continue);
    Board.Rebuild([Section(TAtlasWelcomeIds.Continue, 20, TAtlasWelcomeColumn.Left)], TAtlasWelcomeLayout.Atlas, 2);
    Assert.IsTrue(Kept = Board.View(TAtlasWelcomeIds.Continue), 'sichtbarer Bereich behält seinen Frame');
    Assert.IsNull(Board.View(TAtlasWelcomeIds.State), 'ausgeschalteter Bereich verschwindet');
    Before := TTestSection(Kept).Updates;
    Board.UpdateSection(TAtlasWelcomeIds.Continue);
    Assert.AreEqual(Before + 1, TTestSection(Kept).Updates);
    Board.UpdateContent;
    Assert.AreEqual(Before + 2, TTestSection(Kept).Updates);
  finally
    Board.Free;
    TAtlasWelcomeViews.Release;
  end;
end;

{ TAtlasWelcomeSearchBoxTests }

function SampleQuery: TAtlasWelcomeSearchQuery;
begin
  Result :=
    function(const APattern: string): TArray<TAtlasWelcomeSearchResult>
    var
      Hits: TArray<TAtlasWelcomeHit>;
    begin
      Hits := [TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Files, 'Atlas.IDE.Expert.WelcomePage.pas', 'Atlas',
        'C:\P\Atlas.IDE.Expert.WelcomePage.pas'),
        TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Files, 'Welcome.pas', 'Atlas', 'C:\P\Welcome.pas'),
        TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Commands, 'Atlas-Layout anwenden', '', 'Atlas.WelcomeApply')];
      Hits[2].Alias := 'WelcomeApply';
      Result := TAtlasWelcomeSearch.Search(APattern, Hits, 'Hinweis');
    end;
end;

procedure TAtlasWelcomeSearchBoxTests.HeaderShowsAndHidesSearch;
var
  Header: TAtlasWelcomeHeaderFrame;
begin
  Header := TAtlasWelcomeHeaderFrame.Create(nil);
  try
    Assert.IsNull(Header.Search);
    Assert.AreEqual(0, Header.SearchHost.Width);
    Header.ShowSearch(True);
    Assert.IsNotNull(Header.Search);
    Assert.IsTrue(Header.Search.Visible);
    Assert.IsTrue(Header.SearchHost.Width > 0);
    Header.Search.Edit.Text := 'wel';
    Header.ShowSearch(False);
    Assert.IsFalse(Header.Search.Visible);
    Assert.AreEqual('', Header.Search.Edit.Text);
    Assert.AreEqual(0, Header.SearchHost.Width);
  finally
    Header.Free;
  end;
end;

procedure TAtlasWelcomeSearchBoxTests.QueryFillsHitsAndRows;
var
  Box: TAtlasWelcomeSearchBox;
begin
  Box := TAtlasWelcomeSearchBox.Create(nil);
  try
    Box.OnQuery := SampleQuery;
    Box.Edit.Text := 'wel';
    Box.Query;
    // Dateien (2), Symbole mit Hinweis, Befehle (1).
    Assert.AreEqual(3, Integer(Length(Box.Hits)));
    Assert.AreEqual(3, Integer(Length(Box.Results)));
    Assert.AreEqual(7, Integer(Length(Box.Rows)));
    Assert.AreEqual(0, Box.Selected);
    Box.Edit.Text := '';
    Assert.AreEqual(0, Integer(Length(Box.Hits)));
    Assert.AreEqual(-1, Box.Selected);
  finally
    Box.Free;
  end;
end;

procedure TAtlasWelcomeSearchBoxTests.SelectStaysInRange;
var
  Box: TAtlasWelcomeSearchBox;
begin
  Box := TAtlasWelcomeSearchBox.Create(nil);
  try
    Box.OnQuery := SampleQuery;
    Box.Edit.Text := 'wel';
    Box.Query;
    Box.Select(-5);
    Assert.AreEqual(0, Box.Selected);
    Box.Select(2);
    Assert.AreEqual(2, Box.Selected);
    Box.Select(9);
    Assert.AreEqual(2, Box.Selected);
  finally
    Box.Free;
  end;
end;

procedure TAtlasWelcomeSearchBoxTests.OpenSelectedHandsHitAndClears;
var
  Box: TAtlasWelcomeSearchBox;
  Opened: string;
begin
  Opened := '';
  Box := TAtlasWelcomeSearchBox.Create(nil);
  try
    Box.OnQuery := SampleQuery;
    Box.OnOpen :=
      procedure(const AHit: TAtlasWelcomeHit)
      begin
        Opened := AHit.Target;
      end;
    Box.Edit.Text := 'wel';
    Box.Query;
    Box.Select(2);
    Box.OpenSelected;
    // Geöffnet wird nach dem Schließen der Liste über die Warteschlange.
    Assert.AreEqual('', Box.Edit.Text);
    Assert.AreEqual(0, Integer(Length(Box.Hits)));
    CheckSynchronize;
    Assert.AreEqual('Atlas.WelcomeApply', Opened);
    // Esc bzw. Clear ohne Treffer öffnet nichts.
    Opened := '';
    Box.OpenSelected;
    CheckSynchronize;
    Assert.AreEqual('', Opened);
  finally
    Box.Free;
  end;
end;

procedure TAtlasWelcomeSearchBoxTests.GroupCaptionsFollowLanguage;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Projekte', TAtlasWelcomeSearchBox.GroupCaption(TAtlasWelcomeSearchGroup.Projects));
    Assert.AreEqual('Befehle', TAtlasWelcomeSearchBox.GroupCaption(TAtlasWelcomeSearchGroup.Commands));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Files', TAtlasWelcomeSearchBox.GroupCaption(TAtlasWelcomeSearchGroup.Files));
    Assert.AreEqual('Symbols', TAtlasWelcomeSearchBox.GroupCaption(TAtlasWelcomeSearchGroup.Symbols));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

{ TAtlasWelcomeWhatsNewFrameTests }

procedure TAtlasWelcomeWhatsNewFrameTests.UnreadShowsRowsWithSwitchKeyAndTry;
var
  Host: TForm;
  Fake: TFakeWhatsNew;
  Source: IAtlasWhatsNewSource;
  Frame: TAtlasWelcomeWhatsNewFrame;
begin
  Fake := TFakeWhatsNew.Create;
  Source := Fake;
  Fake.FView := TAtlasWhatsNewView.Unread;
  Fake.FVersions := [NewsVersion('1.1.0', [NewsItem('Suchfeld', 'An', 'Taste', 'Atlas.WelcomeStart'),
    NewsItem('Ohne alles', '', '', ''), NewsItem('Aus', 'Aus', '', '')])];
  Host := TForm.CreateNew(nil);
  try
    Frame := NewsFrame(Host, Source);
    Assert.AreEqual(3, Integer(Length(Frame.Rows)));
    Assert.AreEqual(0, Integer(Length(Frame.Headings)), 'eine Version: keine Überschrift');
    Assert.AreEqual('Suchfeld', Frame.Rows[0].Title.Caption);
    Assert.AreEqual('Ctrl+E', Frame.Rows[0].Key.Caption, 'tatsächliche Belegung');
    Assert.IsTrue(Frame.Rows[0].Switch.Checked);
    Assert.IsNotNull(Frame.Rows[0].TryButton);
    Assert.IsNull(Frame.Rows[1].Key);
    Assert.IsNull(Frame.Rows[1].Switch, 'ohne Einstellung kein Schalter');
    Assert.IsNull(Frame.Rows[1].TryButton, 'ohne Befehl und Beispiel kein „Ausprobieren“');
    Assert.IsFalse(Frame.Rows[2].Switch.Checked);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.WelcomeNewsRead), Frame.DismissButton.Caption);
    Assert.IsTrue(Frame.Rows[1].Title.Top > Frame.Rows[0].Text.Top, 'Zeilen untereinander');
    Assert.IsTrue(Frame.Rows[0].Switch.Left > Frame.Rows[0].Title.Left + Frame.Rows[0].Title.Width,
      'Schalter rechts vom Titel');
    Assert.IsTrue(Frame.PreferredHeight > Frame.DismissButton.Top, 'Höhe nach dem Inhalt');
    Assert.AreSame(Source, Frame.Menu.Source);
    // Danach ohne Ungelesenes: „Schließen“ statt „Gelesen“.
    Fake.FView := TAtlasWhatsNewView.Current;
    Frame.UpdateContent;
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.WelcomeNewsClose), Frame.DismissButton.Caption);
    Fake.FView := TAtlasWhatsNewView.Hidden;
    Fake.FVersions := nil;
    Frame.UpdateContent;
    Assert.IsNull(Frame.DismissButton);
    Assert.AreEqual(0, Integer(Length(Frame.Rows)));
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeWhatsNewFrameTests.JumpGroupsByVersion;
var
  Host: TForm;
  Fake: TFakeWhatsNew;
  Source: IAtlasWhatsNewSource;
  Frame: TAtlasWelcomeWhatsNewFrame;
begin
  Fake := TFakeWhatsNew.Create;
  Source := Fake;
  Fake.FView := TAtlasWhatsNewView.Unread;
  Fake.FVersions := [NewsVersion('1.2.0', [NewsItem('Neu 2', '', '', '')]),
    NewsVersion('1.1.0', [NewsItem('Neu 1a', '', '', ''), NewsItem('Neu 1b', '', '', '')])];
  Host := TForm.CreateNew(nil);
  try
    Frame := NewsFrame(Host, Source);
    Assert.AreEqual(2, Integer(Length(Frame.Headings)));
    Assert.AreEqual(3, Integer(Length(Frame.Rows)), 'Neuerungen aller übersprungenen Versionen');
    Assert.AreEqual(TAtlasWelcomeWhatsNewFrame.HeadingText('1.2.0', False, True), Frame.Headings[0].Caption);
    Assert.AreEqual('1.1.0', Frame.Rows[1].Version);
    Assert.IsTrue(Frame.Headings[1].Top > Frame.Rows[0].Title.Top, 'Gruppe 1.1.0 unter 1.2.0');
    Assert.IsTrue(Frame.Rows[1].Title.Top > Frame.Headings[1].Top);
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeWhatsNewFrameTests.AllVersionsCollapseExceptNewest;
var
  Host: TForm;
  Fake: TFakeWhatsNew;
  Source: IAtlasWhatsNewSource;
  Frame: TAtlasWelcomeWhatsNewFrame;
begin
  Fake := TFakeWhatsNew.Create;
  Source := Fake;
  Fake.FView := TAtlasWhatsNewView.All;
  Fake.FVersions := [NewsVersion('1.2.0', [NewsItem('Neu 2', '', '', '')]),
    NewsVersion('1.1.0', [NewsItem('Neu 1', '', '', '')]), NewsVersion('1.0.0', [NewsItem('Erste', '', '', '')])];
  Host := TForm.CreateNew(nil);
  try
    Frame := NewsFrame(Host, Source);
    Assert.AreEqual(3, Integer(Length(Frame.Headings)));
    Assert.AreEqual(1, Integer(Length(Frame.Rows)), 'nur die neueste aufgeklappt');
    Assert.IsTrue(Frame.IsExpanded('1.2.0'));
    Assert.IsFalse(Frame.IsExpanded('1.0.0'));
    Assert.AreEqual(TAtlasWelcomeWhatsNewFrame.HeadingText('1.0.0', True, False), Frame.Headings[2].Caption);
    Assert.AreNotEqual(TAtlasWelcomeWhatsNewFrame.HeadingText('1.0.0', True, False),
      TAtlasWelcomeWhatsNewFrame.HeadingText('1.0.0', True, True), 'Pfeil zeigt den Zustand');
    Frame.Toggle('1.0.0');
    Assert.AreEqual(2, Integer(Length(Frame.Rows)));
    Assert.AreEqual('Erste', Frame.Rows[1].Title.Caption);
    Frame.Toggle('1.2.0');
    Assert.AreEqual(1, Integer(Length(Frame.Rows)));
    // Neu lesen behält den Zustand, solange „Alle Versionen“ bleibt.
    Frame.UpdateContent;
    Assert.AreEqual('Erste', Frame.Rows[0].Title.Caption);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.WelcomeNewsClose), Frame.DismissButton.Caption);
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeWhatsNewFrameTests.ClicksReachSource;
var
  Host: TForm;
  Fake: TFakeWhatsNew;
  Source: IAtlasWhatsNewSource;
  Frame: TAtlasWelcomeWhatsNewFrame;
begin
  Fake := TFakeWhatsNew.Create;
  Source := Fake;
  Fake.FView := TAtlasWhatsNewView.Unread;
  Fake.FVersions := [NewsVersion('1.1.0', [NewsItem('Suchfeld', 'An', 'Taste', 'Atlas.WelcomeStart')])];
  Host := TForm.CreateNew(nil);
  try
    Frame := NewsFrame(Host, Source);
    Frame.Rows[0].Switch.Checked := False;
    Frame.Rows[0].TryButton.Click;
    Frame.DismissButton.Click;
    Frame.Menu.AllItem.Click;
    Frame.Menu.CurrentItem.Click;
    // Alles läuft über die Nachrichtenschleife.
    Assert.AreEqual(0, Integer(Length(Fake.Calls)));
    CheckSynchronize;
    Assert.AreEqual(5, Integer(Length(Fake.Calls)));
    Assert.AreEqual('switch An False', Fake.Calls[0]);
    Assert.AreEqual('try Suchfeld', Fake.Calls[1]);
    Assert.AreEqual('dismiss', Fake.Calls[2]);
    Assert.AreEqual(Format('show %d', [Ord(TAtlasWhatsNewView.All)]), Fake.Calls[3]);
    Assert.AreEqual(Format('show %d', [Ord(TAtlasWhatsNewView.Current)]), Fake.Calls[4]);
    // Neu lesen setzt den Schalter, ohne die Quelle zu rufen.
    Frame.UpdateContent;
    CheckSynchronize;
    Assert.AreEqual(5, Integer(Length(Fake.Calls)));
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeWhatsNewFrameTests.TitleNamesSingleVersion;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Neu in Atlas 1.1.0', TAtlasWelcomeWhatsNewFrame.TitleFor(TAtlasWhatsNewView.Unread,
      [NewsVersion('1.1.0', [NewsItem('A', '', '', '')])]));
    Assert.AreEqual('Neu in Atlas', TAtlasWelcomeWhatsNewFrame.TitleFor(TAtlasWhatsNewView.Unread,
      [NewsVersion('1.2.0', [NewsItem('A', '', '', '')]), NewsVersion('1.1.0', [NewsItem('B', '', '', '')])]));
    Assert.AreEqual('Neu in Atlas', TAtlasWelcomeWhatsNewFrame.TitleFor(TAtlasWhatsNewView.All,
      [NewsVersion('1.1.0', [NewsItem('A', '', '', '')])]));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('New in Atlas 1.1.0', TAtlasWelcomeWhatsNewFrame.TitleFor(TAtlasWhatsNewView.Current,
      [NewsVersion('1.1.0', [NewsItem('A', '', '', '')])]));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeWhatsNewFrameTests.BoardSizesCardToItsText;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Fake: TFakeWhatsNew;
  Source: IAtlasWhatsNewSource;
  Card: TAtlasWelcomeSectionFrame;
  Narrow, Wide: Integer;
begin
  Fake := TFakeWhatsNew.Create;
  Source := Fake;
  Fake.FView := TAtlasWhatsNewView.Unread;
  Fake.FVersions := [NewsVersion('1.1.0', [NewsItem('Suchfeld', 'An', 'Taste', 'Atlas.WelcomeStart'),
    NewsItem('Zweite', 'Aus', '', '')])];
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.News,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeWhatsNewFrame;
    begin
      Frame := TAtlasWelcomeWhatsNewFrame.Create(AOwner);
      Frame.Source := Source;
      Result := Frame;
    end);
  Host := TForm.CreateNew(nil);
  try
    Host.ClientWidth := 1200;
    Host.ClientHeight := 600;
    Board := TAtlasWelcomeBoardFrame.Create(Host);
    Board.Parent := Host;
    Board.Align := alClient;
    // Nach einem Update oben links (#756).
    Board.Rebuild([Section(TAtlasWelcomeIds.News, 50, TAtlasWelcomeColumn.Right)],
      TAtlasWelcomeLayout.Atlas.MovedToTop(TAtlasWelcomeIds.News), 2);
    Card := Board.View(TAtlasWelcomeIds.News);
    Assert.IsNotNull(Card);
    Assert.AreEqual(TAtlasWelcomeIds.News, Board.Columns[0][0]);
    Assert.AreEqual(Card.PreferredHeight, Card.Height, 'Höhe nach der gesetzten Breite');
    Assert.IsTrue(Assigned(Card.OnHeightChanged), 'Aufklappen ordnet die Spalten neu');
    // Schmal: Der Text bricht um, die Karte wird höher.
    Card.Width := 900;
    Wide := Card.PreferredHeight;
    Card.Width := 260;
    Narrow := Card.PreferredHeight;
    Assert.IsTrue(Narrow > Wide, Format('schmal %d, breit %d', [Narrow, Wide]));
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeHeaderTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeSearchBoxTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeBoardTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeWhatsNewFrameTests);

end.
