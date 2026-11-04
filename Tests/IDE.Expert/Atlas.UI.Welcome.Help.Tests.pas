unit Atlas.UI.Welcome.Help.Tests;

// Tests des Hilfebereichs der Willkommensseite.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeHelpFrameTests = class
  public
    [Test]
    procedure TextsFollowLanguage;
    [Test]
    procedure ButtonsFollowSourceAndWidth;
    [Test]
    procedure ClicksReachSource;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Strings,
  Atlas.Core.Welcome.Help,
  Atlas.UI.Welcome.Help,
  Atlas.UI.Welcome.TestSupport;

type
  /// <summary>Quelle des Bereichs „Hilfe und Rückmeldung“ für die Tests; merkt sich die Aufrufe.</summary>
  TFakeHelp = class(TInterfacedObject, IAtlasHelpSource)
  public
    Keys: Boolean;
    Calls: TArray<string>;
    function KeysAvailable: Boolean;
    procedure OpenDocs;
    procedure ShowKeys;
    procedure ReportProblem;
    procedure Donate;
  end;

{ TFakeHelp }

function TFakeHelp.KeysAvailable: Boolean;
begin
  Result := Keys;
end;
procedure TFakeHelp.OpenDocs;
begin
  Calls := Calls + ['docs'];
end;
procedure TFakeHelp.ShowKeys;
begin
  Calls := Calls + ['keys'];
end;
procedure TFakeHelp.ReportProblem;
begin
  Calls := Calls + ['report'];
end;
procedure TFakeHelp.Donate;
begin
  Calls := Calls + ['donate'];
end;
{ TAtlasWelcomeHelpFrameTests }

procedure TAtlasWelcomeHelpFrameTests.TextsFollowLanguage;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Hilfe und Rückmeldung', TAtlasWelcomeHelpFrame.TitleText);
    Assert.AreEqual('Atlas-Doku', TAtlasWelcomeHelpFrame.ButtonCaption(TAtlasHelpButton.Docs));
    Assert.AreEqual('Tastenkürzel', TAtlasWelcomeHelpFrame.ButtonCaption(TAtlasHelpButton.Keys));
    Assert.AreEqual('Problem melden …', TAtlasWelcomeHelpFrame.ButtonCaption(TAtlasHelpButton.Report));
    Assert.AreEqual('Atlas unterstützen ♥', TAtlasWelcomeHelpFrame.ButtonCaption(TAtlasHelpButton.Donate));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Help and feedback', TAtlasWelcomeHelpFrame.TitleText);
    Assert.AreEqual('Report a problem …', TAtlasWelcomeHelpFrame.ButtonCaption(TAtlasHelpButton.Report));
    Assert.AreEqual('Support Atlas ♥', TAtlasWelcomeHelpFrame.ButtonCaption(TAtlasHelpButton.Donate));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;
procedure TAtlasWelcomeHelpFrameTests.ButtonsFollowSourceAndWidth;
var
  Host: TForm;
  Fake: TFakeHelp;
  Source: IAtlasHelpSource;
  Frame: TAtlasWelcomeHelpFrame;
  Kind: TAtlasHelpButton;
  Wide: Integer;
begin
  Fake := TFakeHelp.Create;
  Fake.Keys := True;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeHelpFrame.Create(Host);
    Frame.Parent := Host;
    Frame.SetBounds(0, 0, 600, 120);
    // Ohne Quelle geht nichts.
    for Kind := Low(TAtlasHelpButton) to High(TAtlasHelpButton) do
    begin
      Assert.IsFalse(Frame.Button(Kind).Enabled, 'ohne Quelle ausgegraut');
    end;
    Frame.Source := Source;
    for Kind := Low(TAtlasHelpButton) to High(TAtlasHelpButton) do
    begin
      Assert.IsTrue(Frame.Button(Kind).Enabled);
    end;
    Assert.AreEqual(Frame.Button(TAtlasHelpButton.Docs).Top, Frame.Button(TAtlasHelpButton.Report).Top,
      'genug Breite: eine Reihe');
    Assert.IsTrue(Frame.Button(TAtlasHelpButton.Keys).Left > Frame.Button(TAtlasHelpButton.Docs).Left);
    Assert.IsTrue(Frame.NoteLabel.Top > Frame.Button(TAtlasHelpButton.Docs).Top, 'Hinweis unter den Knöpfen');
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeHelpNote), Frame.NoteLabel.Caption);
    Assert.IsTrue(Frame.PreferredHeight > Frame.NoteLabel.Top, 'Höhe nach dem Inhalt');
    Wide := Frame.PreferredHeight;
    // Schmal: weitere Reihen, der Bereich wird höher.
    Frame.Width := 120;
    Frame.UpdateContent;
    Assert.IsTrue(Frame.Button(TAtlasHelpButton.Report).Top > Frame.Button(TAtlasHelpButton.Docs).Top,
      'schmal: Umbruch');
    Assert.IsTrue(Frame.PreferredHeight > Wide);
    // Übersicht aus (keys.overview): „Tastenkürzel“ ausgegraut, die anderen gehen.
    Fake.Keys := False;
    Frame.UpdateContent;
    Assert.IsFalse(Frame.Button(TAtlasHelpButton.Keys).Enabled);
    Assert.IsTrue(Frame.Button(TAtlasHelpButton.Docs).Enabled);
    Assert.IsTrue(Frame.Button(TAtlasHelpButton.Report).Enabled);
  finally
    Host.Free;
  end;
end;
procedure TAtlasWelcomeHelpFrameTests.ClicksReachSource;
var
  Host: TForm;
  Fake: TFakeHelp;
  Source: IAtlasHelpSource;
  Frame: TAtlasWelcomeHelpFrame;
begin
  Fake := TFakeHelp.Create;
  Fake.Keys := True;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeHelpFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Source := Source;
    Frame.Button(TAtlasHelpButton.Docs).Click;
    Frame.Button(TAtlasHelpButton.Keys).Click;
    Frame.Button(TAtlasHelpButton.Report).Click;
    Frame.Button(TAtlasHelpButton.Donate).Click;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(4, Integer(Length(Fake.Calls)));
    Assert.AreEqual('docs', Fake.Calls[0]);
    Assert.AreEqual('keys', Fake.Calls[1]);
    Assert.AreEqual('report', Fake.Calls[2]);
    Assert.AreEqual('donate', Fake.Calls[3]);
    // Ausgegrauter Knopf tut nichts.
    Fake.Keys := False;
    Frame.UpdateContent;
    Frame.ClickButton(TAtlasHelpButton.Keys);
    CheckSynchronize;
    Assert.AreEqual(4, Integer(Length(Fake.Calls)));
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeHelpFrameTests);

end.
