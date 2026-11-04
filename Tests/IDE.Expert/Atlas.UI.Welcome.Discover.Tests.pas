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
  Vcl.Imaging.pngimage,
  Atlas.UI.Welcome.TestSupport;


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
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
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
    TAtlasStrings.Language := Saved;
  end;
end;
procedure TAtlasWelcomeDiscoverFrameTests.CardShowsTipAndButtons;
var
  Host: TForm;
  Fake: TFakeDiscover;
  Source: IAtlasDiscoverSource;
  Frame: TAtlasWelcomeDiscoverFrame;
begin
  Fake := DiscoverFake;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeDiscoverFrame.Create(Host);
    Frame.Parent := Host;
    Frame.SetBounds(0, 0, 420, 200);
    Frame.Source := Source;
    Assert.IsTrue(Frame.HasCard);
    Assert.AreEqual('Code-Aktionen', Frame.TipTitle.Caption);
    Assert.AreEqual('Ctrl+.', Frame.KeyLabel.Caption, 'tatsächliche Belegung');
    Assert.IsTrue(Frame.KeyLabel.Left > Frame.TipTitle.Left, 'Kürzel neben dem Titel');
    Assert.AreEqual(TAtlasDiscoverTexts.AgeText(Fake.Card_.Age), Frame.AgeLabel.Caption);
    Assert.IsTrue(Frame.TextLabel.Top > Frame.TipTitle.Top, 'Text unter dem Titel');
    Assert.IsFalse(Frame.Image.Visible, 'ohne Bild kein Platz dafür');
    Assert.IsTrue(Frame.Button(TAtlasDiscoverButton.TryIt).Enabled);
    Assert.IsTrue(Frame.Button(TAtlasDiscoverButton.Next).Enabled);
    Assert.IsTrue(Frame.Button(TAtlasDiscoverButton.Block).Visible);
    Assert.IsTrue(Frame.Button(TAtlasDiscoverButton.TryIt).Top > Frame.AgeLabel.Top, 'Knöpfe unten');
    Assert.IsTrue(Frame.PreferredHeight > Frame.Button(TAtlasDiscoverButton.TryIt).Top, 'Höhe nach dem Inhalt');
    Assert.IsFalse(Frame.EmptyLabel.Visible);
    // Einziger Tipp, nichts zum Ausprobieren, Zählung aus.
    Fake.Card_.Count := 1;
    Fake.Card_.Position := 1;
    Fake.Card_.CanTry := False;
    Fake.Card_.Age := TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.None, 0);
    Fake.Card_.KeyText := '';
    Frame.UpdateContent;
    Assert.IsFalse(Frame.Button(TAtlasDiscoverButton.Next).Enabled, 'kein nächster Tipp');
    Assert.IsFalse(Frame.Button(TAtlasDiscoverButton.TryIt).Enabled);
    Assert.IsFalse(Frame.AgeLabel.Visible);
    Assert.IsFalse(Frame.PositionLabel.Visible);
    Assert.IsFalse(Frame.KeyLabel.Visible);
    // Kein Tipp (alle gesperrt): nur der Hinweis.
    Fake.HasCard := False;
    Frame.UpdateContent;
    Assert.IsFalse(Frame.HasCard);
    Assert.IsTrue(Frame.EmptyLabel.Visible);
    Assert.IsFalse(Frame.Button(TAtlasDiscoverButton.Block).Visible);
    Assert.IsFalse(Frame.TipTitle.Visible);
  finally
    Host.Free;
  end;
end;
procedure TAtlasWelcomeDiscoverFrameTests.ClicksReachSource;
var
  Host: TForm;
  Fake: TFakeDiscover;
  Source: IAtlasDiscoverSource;
  Frame: TAtlasWelcomeDiscoverFrame;
begin
  Fake := DiscoverFake;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeDiscoverFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Source := Source;
    Frame.Button(TAtlasDiscoverButton.TryIt).Click;
    Frame.Button(TAtlasDiscoverButton.Next).Click;
    Frame.Button(TAtlasDiscoverButton.Block).Click;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(3, Integer(Length(Fake.Calls)));
    Assert.AreEqual('try codeActions', Fake.Calls[0]);
    Assert.AreEqual('next codeActions', Fake.Calls[1]);
    Assert.AreEqual('block codeActions', Fake.Calls[2]);
    // Ausgegraute Knöpfe tun nichts.
    Fake.Card_.Count := 1;
    Fake.Card_.CanTry := False;
    Frame.UpdateContent;
    Frame.ClickButton(TAtlasDiscoverButton.Next);
    Frame.ClickButton(TAtlasDiscoverButton.TryIt);
    CheckSynchronize;
    Assert.AreEqual(3, Integer(Length(Fake.Calls)));
  finally
    Host.Free;
  end;
end;
procedure TAtlasWelcomeDiscoverFrameTests.ImageFitsColumn;
var
  Host: TForm;
  Fake: TFakeDiscover;
  Source: IAtlasDiscoverSource;
  Frame: TAtlasWelcomeDiscoverFrame;
  Folder, FileName: string;
  Png: TPngImage;
begin
  Folder := TPath.Combine(TPath.GetTempPath, 'AtlasDiscoverImage' + IntToStr(Random(1000000)));
  ForceDirectories(Folder);
  FileName := TPath.Combine(Folder, 'tipp.png');
  Png := TPngImage.CreateBlank(COLOR_RGB, 8, TAtlasWelcomeDiscoverFrame.ImageWidth,
    TAtlasWelcomeDiscoverFrame.ImageHeight);
  try
    Png.SaveToFile(FileName);
  finally
    Png.Free;
  end;
  Fake := DiscoverFake;
  Fake.Card_.ImageFile := FileName;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeDiscoverFrame.Create(Host);
    Frame.Parent := Host;
    // Schmale Spalte: Bild oben, höchstens so breit wie die Spalte, Seitenverhältnis 16:9; Text darunter.
    Frame.SetBounds(0, 0, 420, 200);
    Frame.Source := Source;
    Assert.IsTrue(Frame.Image.Visible, 'Bild geladen');
    Assert.IsTrue(Frame.Image.Width <= Frame.ClientWidth);
    Assert.IsTrue(Frame.Image.Width >= TAtlasWelcomeDiscoverFrame.ImageWidth, 'bei 100 % volle Größe, sonst mehr');
    Assert.IsTrue(Abs(Frame.Image.Height - Frame.Image.Width * TAtlasWelcomeDiscoverFrame.ImageHeight div
      TAtlasWelcomeDiscoverFrame.ImageWidth) <= 1, 'Seitenverhältnis bleibt');
    Assert.IsTrue(Frame.TipTitle.Top >= Frame.Image.Top + Frame.Image.Height, 'Titel unter dem Bild');
    Assert.AreEqual(Frame.Image.Left, Frame.TipTitle.Left, 'Text bündig mit dem Bild');
    Assert.IsTrue(Frame.PreferredHeight > Frame.Image.Height, 'Höhe mit Bild');
    // Breite Spalte: Text neben dem Bild.
    Frame.SetBounds(0, 0, 2000, 200);
    Frame.UpdateContent;
    Assert.IsTrue(Frame.TipTitle.Left >= Frame.Image.Left + Frame.Image.Width, 'Titel neben dem Bild');
    Assert.IsTrue(Frame.TipTitle.Top < Frame.Image.Top + Frame.Image.Height);
    // Ohne Bild: kein Platz dafür.
    Fake.Card_.ImageFile := '';
    Frame.UpdateContent;
    Assert.IsFalse(Frame.Image.Visible);
    Assert.AreEqual(Frame.ScaleValue(TAtlasWelcomeDiscoverFrame.Indent), Frame.TipTitle.Left);
  finally
    Host.Free;
    TDirectory.Delete(Folder, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeDiscoverFrameTests);

end.
