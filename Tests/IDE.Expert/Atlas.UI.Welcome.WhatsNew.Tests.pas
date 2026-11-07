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
  mHost: TForm;
  mFake: TFakeWhatsNew;
  mSource: IAtlasWhatsNewSource;
  mFrame: TAtlasWelcomeWhatsNewFrame;
begin
  mFake := TFakeWhatsNew.Create;
  mSource := mFake;
  mFake.FView := TAtlasWhatsNewView.Unread;
  mFake.FVersions := [NewsVersion('1.1.0', [NewsItem('Suchfeld', 'An', 'Taste', 'Atlas.WelcomeStart'),
    NewsItem('Ohne alles', '', '', ''), NewsItem('Aus', 'Aus', '', '')])];
  mHost := TForm.CreateNew(nil);
  try
    mFrame := NewsFrame(mHost, mSource);
    Assert.AreEqual(3, Integer(Length(mFrame.Rows)));
    Assert.AreEqual(0, Integer(Length(mFrame.Headings)), 'eine Version: keine Überschrift');
    Assert.AreEqual('Suchfeld', mFrame.Rows[0].Title.Caption);
    Assert.AreEqual('Ctrl+E', mFrame.Rows[0].Key.Caption, 'tatsächliche Belegung');
    Assert.IsTrue(mFrame.Rows[0].Switch.Checked);
    Assert.IsNotNull(mFrame.Rows[0].TryButton);
    Assert.IsNull(mFrame.Rows[1].Key);
    Assert.IsNull(mFrame.Rows[1].Switch, 'ohne Einstellung kein Schalter');
    Assert.IsNull(mFrame.Rows[1].TryButton, 'ohne Befehl und Beispiel kein „Ausprobieren“');
    Assert.IsFalse(mFrame.Rows[2].Switch.Checked);
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeNewsRead), mFrame.DismissButton.Caption);
    Assert.IsTrue(mFrame.Rows[1].Title.Top > mFrame.Rows[0].Text.Top, 'Zeilen untereinander');
    Assert.IsTrue(mFrame.Rows[0].Switch.Left > mFrame.Rows[0].Title.Left + mFrame.Rows[0].Title.Width,
      'Schalter rechts vom Titel');
    Assert.IsTrue(mFrame.PreferredHeight > mFrame.DismissButton.Top, 'Höhe nach dem Inhalt');
    Assert.AreSame(mSource, mFrame.Menu.Source);
    // Danach ohne Ungelesenes: „Schließen“ statt „Gelesen“.
    mFake.FView := TAtlasWhatsNewView.Current;
    mFrame.UpdateContent;
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeNewsClose), mFrame.DismissButton.Caption);
    mFake.FView := TAtlasWhatsNewView.Hidden;
    mFake.FVersions := nil;
    mFrame.UpdateContent;
    Assert.IsNull(mFrame.DismissButton);
    Assert.AreEqual(0, Integer(Length(mFrame.Rows)));
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeWhatsNewFrameTests.JumpGroupsByVersion;
var
  mHost: TForm;
  mFake: TFakeWhatsNew;
  mSource: IAtlasWhatsNewSource;
  mFrame: TAtlasWelcomeWhatsNewFrame;
begin
  mFake := TFakeWhatsNew.Create;
  mSource := mFake;
  mFake.FView := TAtlasWhatsNewView.Unread;
  mFake.FVersions := [NewsVersion('1.2.0', [NewsItem('Neu 2', '', '', '')]),
    NewsVersion('1.1.0', [NewsItem('Neu 1a', '', '', ''), NewsItem('Neu 1b', '', '', '')])];
  mHost := TForm.CreateNew(nil);
  try
    mFrame := NewsFrame(mHost, mSource);
    Assert.AreEqual(2, Integer(Length(mFrame.Headings)));
    Assert.AreEqual(3, Integer(Length(mFrame.Rows)), 'Neuerungen aller übersprungenen Versionen');
    Assert.AreEqual(TAtlasWelcomeWhatsNewFrame.HeadingText('1.2.0', False, True), mFrame.Headings[0].Caption);
    Assert.AreEqual('1.1.0', mFrame.Rows[1].Version);
    Assert.IsTrue(mFrame.Headings[1].Top > mFrame.Rows[0].Title.Top, 'Gruppe 1.1.0 unter 1.2.0');
    Assert.IsTrue(mFrame.Rows[1].Title.Top > mFrame.Headings[1].Top);
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeWhatsNewFrameTests.AllVersionsCollapseExceptNewest;
var
  mHost: TForm;
  mFake: TFakeWhatsNew;
  mSource: IAtlasWhatsNewSource;
  mFrame: TAtlasWelcomeWhatsNewFrame;
begin
  mFake := TFakeWhatsNew.Create;
  mSource := mFake;
  mFake.FView := TAtlasWhatsNewView.All;
  mFake.FVersions := [NewsVersion('1.2.0', [NewsItem('Neu 2', '', '', '')]),
    NewsVersion('1.1.0', [NewsItem('Neu 1', '', '', '')]), NewsVersion('1.0.0', [NewsItem('Erste', '', '', '')])];
  mHost := TForm.CreateNew(nil);
  try
    mFrame := NewsFrame(mHost, mSource);
    Assert.AreEqual(3, Integer(Length(mFrame.Headings)));
    Assert.AreEqual(1, Integer(Length(mFrame.Rows)), 'nur die neueste aufgeklappt');
    Assert.IsTrue(mFrame.IsExpanded('1.2.0'));
    Assert.IsFalse(mFrame.IsExpanded('1.0.0'));
    Assert.AreEqual(TAtlasWelcomeWhatsNewFrame.HeadingText('1.0.0', True, False), mFrame.Headings[2].Caption);
    Assert.AreNotEqual(TAtlasWelcomeWhatsNewFrame.HeadingText('1.0.0', True, False),
      TAtlasWelcomeWhatsNewFrame.HeadingText('1.0.0', True, True), 'Pfeil zeigt den Zustand');
    mFrame.Toggle('1.0.0');
    Assert.AreEqual(2, Integer(Length(mFrame.Rows)));
    Assert.AreEqual('Erste', mFrame.Rows[1].Title.Caption);
    mFrame.Toggle('1.2.0');
    Assert.AreEqual(1, Integer(Length(mFrame.Rows)));
    // Neu lesen behält den Zustand, solange „Alle Versionen“ bleibt.
    mFrame.UpdateContent;
    Assert.AreEqual('Erste', mFrame.Rows[0].Title.Caption);
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeNewsClose), mFrame.DismissButton.Caption);
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeWhatsNewFrameTests.ClicksReachSource;
var
  mHost: TForm;
  mFake: TFakeWhatsNew;
  mSource: IAtlasWhatsNewSource;
  mFrame: TAtlasWelcomeWhatsNewFrame;
begin
  mFake := TFakeWhatsNew.Create;
  mSource := mFake;
  mFake.FView := TAtlasWhatsNewView.Unread;
  mFake.FVersions := [NewsVersion('1.1.0', [NewsItem('Suchfeld', 'An', 'Taste', 'Atlas.WelcomeStart')])];
  mHost := TForm.CreateNew(nil);
  try
    mFrame := NewsFrame(mHost, mSource);
    mFrame.Rows[0].Switch.Checked := False;
    mFrame.Rows[0].TryButton.Click;
    mFrame.DismissButton.Click;
    mFrame.Menu.AllItem.Click;
    mFrame.Menu.CurrentItem.Click;
    // Alles läuft über die Nachrichtenschleife.
    Assert.AreEqual(0, Integer(Length(mFake.Calls)));
    CheckSynchronize;
    Assert.AreEqual(5, Integer(Length(mFake.Calls)));
    Assert.AreEqual('switch An False', mFake.Calls[0]);
    Assert.AreEqual('try Suchfeld', mFake.Calls[1]);
    Assert.AreEqual('dismiss', mFake.Calls[2]);
    Assert.AreEqual(Format('show %d', [Ord(TAtlasWhatsNewView.All)]), mFake.Calls[3]);
    Assert.AreEqual(Format('show %d', [Ord(TAtlasWhatsNewView.Current)]), mFake.Calls[4]);
    // Neu lesen setzt den Schalter, ohne die Quelle zu rufen.
    mFrame.UpdateContent;
    CheckSynchronize;
    Assert.AreEqual(5, Integer(Length(mFake.Calls)));
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeWhatsNewFrameTests.TitleNamesSingleVersion;
var
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
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
    TAtlasStrings.Language := mSaved;
  end;
end;
procedure TAtlasWelcomeWhatsNewFrameTests.BoardSizesCardToItsText;
var
  mHost: TForm;
  mBoard: TAtlasWelcomeBoardFrame;
  mFake: TFakeWhatsNew;
  mSource: IAtlasWhatsNewSource;
  mCard: TAtlasWelcomeSectionFrame;
  mNarrow, mWide: Integer;
begin
  mFake := TFakeWhatsNew.Create;
  mSource := mFake;
  mFake.FView := TAtlasWhatsNewView.Unread;
  mFake.FVersions := [NewsVersion('1.1.0', [NewsItem('Suchfeld', 'An', 'Taste', 'Atlas.WelcomeStart'),
    NewsItem('Zweite', 'Aus', '', '')])];
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.cNews,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeWhatsNewFrame;
    begin
      Frame := TAtlasWelcomeWhatsNewFrame.Create(AOwner);
      Frame.Source := mSource;
      Result := Frame;
    end);
  mHost := TForm.CreateNew(nil);
  try
    mHost.ClientWidth := 1200;
    mHost.ClientHeight := 600;
    mBoard := TAtlasWelcomeBoardFrame.Create(mHost);
    mBoard.Parent := mHost;
    mBoard.Align := alClient;
    // Nach einem Update oben links (#756).
    mBoard.Rebuild([Section(TAtlasWelcomeIds.cNews, 50, TAtlasWelcomeColumn.Right)],
      TAtlasWelcomeLayout.Atlas.MovedToTop(TAtlasWelcomeIds.cNews), 2);
    mCard := mBoard.View(TAtlasWelcomeIds.cNews);
    Assert.IsNotNull(mCard);
    Assert.AreEqual(TAtlasWelcomeIds.cNews, mBoard.Columns[0][0]);
    Assert.AreEqual(mCard.PreferredHeight, mCard.Height, 'Höhe nach der gesetzten Breite');
    Assert.IsTrue(Assigned(mCard.OnHeightChanged), 'Aufklappen ordnet die Spalten neu');
    // Schmal: Der Text bricht um, die Karte wird höher.
    mCard.Width := 900;
    mWide := mCard.PreferredHeight;
    mCard.Width := 260;
    mNarrow := mCard.PreferredHeight;
    Assert.IsTrue(mNarrow > mWide, Format('schmal %d, breit %d', [mNarrow, mWide]));
  finally
    mHost.Free;
    TAtlasWelcomeViews.Release;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeWhatsNewFrameTests);

end.
