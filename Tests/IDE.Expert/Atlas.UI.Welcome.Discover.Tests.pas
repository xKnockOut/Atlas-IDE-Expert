unit Atlas.UI.Welcome.Discover.Tests;

// Tests des Bereichs „Entdecken“ der Willkommensseite.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeDiscoverFrameTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure AgeTextsFollowKind;
    [Test]
    procedure CardShowsTipAndButtons;
    [Test]
    procedure ClicksReachSource;
    [Test]
    procedure ImageFitsColumn;
  end;

implementation

uses
  System.Classes,
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms,
  Atlas.UI.Strings,
  System.DateUtils,
  Atlas.Core.Welcome.Discover,
  Atlas.UI.Welcome.Discover,
  System.IOUtils,
  Vcl.Imaging.pngimage;


type
  /// <summary>Quelle der Karte „Atlas entdecken“ für die Tests; merkt sich die Aufrufe.</summary>
  TFakeDiscover = class(TInterfacedObject, IAtlasDiscoverSource)
  public
    HasCard: Boolean;
    Card_: TAtlasDiscoverCard;
    Calls: TArray<string>;
    function Card(out ACard: TAtlasDiscoverCard): Boolean;
    procedure TryTip(const AId: string);
    procedure NextTip(const AId: string);
    procedure BlockTip(const AId: string);
  end;

{ TFakeDiscover }

function TFakeDiscover.Card(out ACard: TAtlasDiscoverCard): Boolean;
begin
  ACard := Card_;
  Result := HasCard;
end;
procedure TFakeDiscover.TryTip(const AId: string);
begin
  Calls := Calls + ['try ' + AId];
end;
procedure TFakeDiscover.NextTip(const AId: string);
begin
  Calls := Calls + ['next ' + AId];
end;
procedure TFakeDiscover.BlockTip(const AId: string);
begin
  Calls := Calls + ['block ' + AId];
end;
function DiscoverFake: TFakeDiscover;
begin
  Result := TFakeDiscover.Create;
  Result.HasCard := True;
  Result.Card_.Id := 'codeActions';
  Result.Card_.Title := 'Code-Aktionen';
  Result.Card_.Text := 'Zeigt, was Atlas an dieser Stelle kann, und führt es aus.';
  Result.Card_.KeyText := 'Ctrl+.';
  Result.Card_.Age := TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Never, 0);
  Result.Card_.CanTry := True;
  Result.Card_.Position := 2;
  Result.Card_.Count := 5;
end;
{ TAtlasWelcomeDiscoverFrameTests }

procedure TAtlasWelcomeDiscoverFrameTests.WarmUpFirstUse;
begin
  CardShowsTipAndButtons;
end;
procedure TAtlasWelcomeDiscoverFrameTests.AgeTextsFollowKind;
var
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Noch nie benutzt',
      TAtlasDiscoverTexts.AgeText(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Never, 0)));
    Assert.AreEqual('Zuletzt vor 3 Wochen',
      TAtlasDiscoverTexts.AgeText(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Weeks, 3)));
    Assert.AreEqual('Zuletzt vor 1 Jahr',
      TAtlasDiscoverTexts.AgeText(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Years, 1)));
    Assert.AreEqual('Zuletzt gestern benutzt',
      TAtlasDiscoverTexts.AgeText(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Yesterday, 1)));
    Assert.AreEqual('', TAtlasDiscoverTexts.AgeText(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.None, 0)),
      'ohne Zählung kein Hinweis');
    Assert.AreEqual('Tipp 2 von 5', TAtlasDiscoverTexts.PositionText(2, 5));
    Assert.AreEqual('', TAtlasDiscoverTexts.PositionText(1, 1), 'ein Tipp: keine Stelle');
    Assert.AreEqual('Atlas entdecken', TAtlasDiscoverTexts.TitleText);
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Last used 3 weeks ago',
      TAtlasDiscoverTexts.AgeText(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Weeks, 3)));
    Assert.AreEqual('Don''t show again', TAtlasDiscoverTexts.ButtonCaption(TAtlasDiscoverButton.Block));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;
procedure TAtlasWelcomeDiscoverFrameTests.CardShowsTipAndButtons;
var
  mHost: TForm;
  mFake: TFakeDiscover;
  mSource: IAtlasDiscoverSource;
  mFrame: TAtlasWelcomeDiscoverFrame;
begin
  mFake := DiscoverFake;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasWelcomeDiscoverFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.SetBounds(0, 0, 420, 200);
    mFrame.Source := mSource;
    Assert.IsTrue(mFrame.HasCard);
    Assert.AreEqual('Code-Aktionen', mFrame.TipTitle.Caption);
    Assert.AreEqual('Ctrl+.', mFrame.KeyLabel.Caption, 'tatsächliche Belegung');
    Assert.IsTrue(mFrame.KeyLabel.Left > mFrame.TipTitle.Left, 'Kürzel neben dem Titel');
    Assert.AreEqual(TAtlasDiscoverTexts.AgeText(mFake.Card_.Age), mFrame.AgeLabel.Caption);
    Assert.IsTrue(mFrame.TextLabel.Top > mFrame.TipTitle.Top, 'Text unter dem Titel');
    Assert.IsFalse(mFrame.Image.Visible, 'ohne Bild kein Platz dafür');
    Assert.IsTrue(mFrame.Button(TAtlasDiscoverButton.TryIt).Enabled);
    Assert.IsTrue(mFrame.Button(TAtlasDiscoverButton.Next).Enabled);
    Assert.IsTrue(mFrame.Button(TAtlasDiscoverButton.Block).Visible);
    Assert.IsTrue(mFrame.Button(TAtlasDiscoverButton.TryIt).Top > mFrame.AgeLabel.Top, 'Knöpfe unten');
    Assert.IsTrue(mFrame.PreferredHeight > mFrame.Button(TAtlasDiscoverButton.TryIt).Top, 'Höhe nach dem Inhalt');
    Assert.IsFalse(mFrame.EmptyLabel.Visible);
    // Einziger Tipp, nichts zum Ausprobieren, Zählung aus.
    mFake.Card_.Count := 1;
    mFake.Card_.Position := 1;
    mFake.Card_.CanTry := False;
    mFake.Card_.Age := TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.None, 0);
    mFake.Card_.KeyText := '';
    mFrame.UpdateContent;
    Assert.IsFalse(mFrame.Button(TAtlasDiscoverButton.Next).Enabled, 'kein nächster Tipp');
    Assert.IsFalse(mFrame.Button(TAtlasDiscoverButton.TryIt).Enabled);
    Assert.IsFalse(mFrame.AgeLabel.Visible);
    Assert.IsFalse(mFrame.PositionLabel.Visible);
    Assert.IsFalse(mFrame.KeyLabel.Visible);
    // Kein Tipp (alle gesperrt): nur der Hinweis.
    mFake.HasCard := False;
    mFrame.UpdateContent;
    Assert.IsFalse(mFrame.HasCard);
    Assert.IsTrue(mFrame.EmptyLabel.Visible);
    Assert.IsFalse(mFrame.Button(TAtlasDiscoverButton.Block).Visible);
    Assert.IsFalse(mFrame.TipTitle.Visible);
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeDiscoverFrameTests.ClicksReachSource;
var
  mHost: TForm;
  mFake: TFakeDiscover;
  mSource: IAtlasDiscoverSource;
  mFrame: TAtlasWelcomeDiscoverFrame;
begin
  mFake := DiscoverFake;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasWelcomeDiscoverFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Source := mSource;
    mFrame.Button(TAtlasDiscoverButton.TryIt).Click;
    mFrame.Button(TAtlasDiscoverButton.Next).Click;
    mFrame.Button(TAtlasDiscoverButton.Block).Click;
    Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(3, Integer(Length(mFake.Calls)));
    Assert.AreEqual('try codeActions', mFake.Calls[0]);
    Assert.AreEqual('next codeActions', mFake.Calls[1]);
    Assert.AreEqual('block codeActions', mFake.Calls[2]);
    // Ausgegraute Knöpfe tun nichts.
    mFake.Card_.Count := 1;
    mFake.Card_.CanTry := False;
    mFrame.UpdateContent;
    mFrame.ClickButton(TAtlasDiscoverButton.Next);
    mFrame.ClickButton(TAtlasDiscoverButton.TryIt);
    CheckSynchronize;
    Assert.AreEqual(3, Integer(Length(mFake.Calls)));
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeDiscoverFrameTests.ImageFitsColumn;
var
  mHost: TForm;
  mFake: TFakeDiscover;
  mSource: IAtlasDiscoverSource;
  mFrame: TAtlasWelcomeDiscoverFrame;
  mFolder, mFileName: string;
  mPng: TPngImage;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasDiscoverImage' + IntToStr(Random(1000000)));
  ForceDirectories(mFolder);
  mFileName := TPath.Combine(mFolder, 'tipp.png');
  mPng := TPngImage.CreateBlank(COLOR_RGB, 8, TAtlasWelcomeDiscoverFrame.cImageWidth,
    TAtlasWelcomeDiscoverFrame.cImageHeight);
  try
    mPng.SaveToFile(mFileName);
  finally
    mPng.Free;
  end;
  mFake := DiscoverFake;
  mFake.Card_.ImageFile := mFileName;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasWelcomeDiscoverFrame.Create(mHost);
    mFrame.Parent := mHost;
    // Schmale Spalte: Bild oben, höchstens so breit wie die Spalte, Seitenverhältnis 16:9; Text darunter.
    mFrame.SetBounds(0, 0, 420, 200);
    mFrame.Source := mSource;
    Assert.IsTrue(mFrame.Image.Visible, 'Bild geladen');
    Assert.IsTrue(mFrame.Image.Width <= mFrame.ClientWidth);
    Assert.IsTrue(mFrame.Image.Width >= TAtlasWelcomeDiscoverFrame.cImageWidth, 'bei 100 % volle Größe, sonst mehr');
    Assert.IsTrue(Abs(mFrame.Image.Height - mFrame.Image.Width * TAtlasWelcomeDiscoverFrame.cImageHeight div
      TAtlasWelcomeDiscoverFrame.cImageWidth) <= 1, 'Seitenverhältnis bleibt');
    Assert.IsTrue(mFrame.TipTitle.Top >= mFrame.Image.Top + mFrame.Image.Height, 'Titel unter dem Bild');
    Assert.AreEqual(mFrame.Image.Left, mFrame.TipTitle.Left, 'Text bündig mit dem Bild');
    Assert.IsTrue(mFrame.PreferredHeight > mFrame.Image.Height, 'Höhe mit Bild');
    // Breite Spalte: Text neben dem Bild.
    mFrame.SetBounds(0, 0, 2000, 200);
    mFrame.UpdateContent;
    Assert.IsTrue(mFrame.TipTitle.Left >= mFrame.Image.Left + mFrame.Image.Width, 'Titel neben dem Bild');
    Assert.IsTrue(mFrame.TipTitle.Top < mFrame.Image.Top + mFrame.Image.Height);
    // Ohne Bild: kein Platz dafür.
    mFake.Card_.ImageFile := '';
    mFrame.UpdateContent;
    Assert.IsFalse(mFrame.Image.Visible);
    Assert.AreEqual(mFrame.ScaleValue(TAtlasWelcomeDiscoverFrame.cIndent), mFrame.TipTitle.Left);
  finally
    mHost.Free;
    TDirectory.Delete(mFolder, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeDiscoverFrameTests);

end.
