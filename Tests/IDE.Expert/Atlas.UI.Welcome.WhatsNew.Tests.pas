unit Atlas.UI.Welcome.WhatsNew.Tests;

// Tests des Bereichs „Neu in Atlas“ der Willkommensseite.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeWhatsNewFrameTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
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
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Layout,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.Board,
  Atlas.Core.Welcome.WhatsNew,
  Atlas.UI.Welcome.WhatsNew,
  Atlas.UI.Welcome.TestSupport;


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
  begin
    Result := TAtlasWhatsNewSwitch.On;
  end
  else if ASetting = 'Aus' then
  begin
    Result := TAtlasWhatsNewSwitch.Off;
  end
  else
  begin
    Result := TAtlasWhatsNewSwitch.None;
  end;
end;
function TFakeWhatsNew.KeyText(const AKey: string): string;
begin
  Result := '';
  if AKey = 'Taste' then
  begin
    Result := 'Ctrl+E';
  end;
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
{ TAtlasWelcomeWhatsNewFrameTests }

procedure TAtlasWelcomeWhatsNewFrameTests.WarmUpFirstUse;
begin
  UnreadShowsRowsWithSwitchKeyAndTry;
  BoardSizesCardToItsText;
end;
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
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeNewsRead), Frame.DismissButton.Caption);
    Assert.IsTrue(Frame.Rows[1].Title.Top > Frame.Rows[0].Text.Top, 'Zeilen untereinander');
    Assert.IsTrue(Frame.Rows[0].Switch.Left > Frame.Rows[0].Title.Left + Frame.Rows[0].Title.Width,
      'Schalter rechts vom Titel');
    Assert.IsTrue(Frame.PreferredHeight > Frame.DismissButton.Top, 'Höhe nach dem Inhalt');
    Assert.AreSame(Source, Frame.Menu.Source);
    // Danach ohne Ungelesenes: „Schließen“ statt „Gelesen“.
    Fake.FView := TAtlasWhatsNewView.Current;
    Frame.UpdateContent;
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeNewsClose), Frame.DismissButton.Caption);
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
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeNewsClose), Frame.DismissButton.Caption);
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
  TDUnitX.RegisterTestFixture(TAtlasWelcomeWhatsNewFrameTests);

end.
