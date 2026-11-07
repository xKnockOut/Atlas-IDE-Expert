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
  System.Classes,
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
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
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
    TAtlasStrings.Language := mSaved;
  end;
end;
procedure TAtlasWelcomeHelpFrameTests.ButtonsFollowSourceAndWidth;
var
  mHost: TForm;
  mFake: TFakeHelp;
  mSource: IAtlasHelpSource;
  mFrame: TAtlasWelcomeHelpFrame;
  mKind: TAtlasHelpButton;
  mWide: Integer;
begin
  mFake := TFakeHelp.Create;
  mFake.Keys := True;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasWelcomeHelpFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.SetBounds(0, 0, 600, 120);
    // Ohne Quelle geht nichts.
    for mKind := Low(TAtlasHelpButton) to High(TAtlasHelpButton) do
    begin
      Assert.IsFalse(mFrame.Button(mKind).Enabled, 'ohne Quelle ausgegraut');
    end;
    mFrame.Source := mSource;
    for mKind := Low(TAtlasHelpButton) to High(TAtlasHelpButton) do
    begin
      Assert.IsTrue(mFrame.Button(mKind).Enabled);
    end;
    Assert.AreEqual(mFrame.Button(TAtlasHelpButton.Docs).Top, mFrame.Button(TAtlasHelpButton.Report).Top,
      'genug Breite: eine Reihe');
    Assert.IsTrue(mFrame.Button(TAtlasHelpButton.Keys).Left > mFrame.Button(TAtlasHelpButton.Docs).Left);
    Assert.IsTrue(mFrame.NoteLabel.Top > mFrame.Button(TAtlasHelpButton.Docs).Top, 'Hinweis unter den Knöpfen');
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeHelpNote), mFrame.NoteLabel.Caption);
    Assert.IsTrue(mFrame.PreferredHeight > mFrame.NoteLabel.Top, 'Höhe nach dem Inhalt');
    mWide := mFrame.PreferredHeight;
    // Schmal: weitere Reihen, der Bereich wird höher.
    mFrame.Width := 120;
    mFrame.UpdateContent;
    Assert.IsTrue(mFrame.Button(TAtlasHelpButton.Report).Top > mFrame.Button(TAtlasHelpButton.Docs).Top,
      'schmal: Umbruch');
    Assert.IsTrue(mFrame.PreferredHeight > mWide);
    // Übersicht aus (keys.overview): „Tastenkürzel“ ausgegraut, die anderen gehen.
    mFake.Keys := False;
    mFrame.UpdateContent;
    Assert.IsFalse(mFrame.Button(TAtlasHelpButton.Keys).Enabled);
    Assert.IsTrue(mFrame.Button(TAtlasHelpButton.Docs).Enabled);
    Assert.IsTrue(mFrame.Button(TAtlasHelpButton.Report).Enabled);
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeHelpFrameTests.ClicksReachSource;
var
  mHost: TForm;
  mFake: TFakeHelp;
  mSource: IAtlasHelpSource;
  mFrame: TAtlasWelcomeHelpFrame;
begin
  mFake := TFakeHelp.Create;
  mFake.Keys := True;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasWelcomeHelpFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Source := mSource;
    mFrame.Button(TAtlasHelpButton.Docs).Click;
    mFrame.Button(TAtlasHelpButton.Keys).Click;
    mFrame.Button(TAtlasHelpButton.Report).Click;
    mFrame.Button(TAtlasHelpButton.Donate).Click;
    Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(4, Integer(Length(mFake.Calls)));
    Assert.AreEqual('docs', mFake.Calls[0]);
    Assert.AreEqual('keys', mFake.Calls[1]);
    Assert.AreEqual('report', mFake.Calls[2]);
    Assert.AreEqual('donate', mFake.Calls[3]);
    // Ausgegrauter Knopf tut nichts.
    mFake.Keys := False;
    mFrame.UpdateContent;
    mFrame.ClickButton(TAtlasHelpButton.Keys);
    CheckSynchronize;
    Assert.AreEqual(4, Integer(Length(mFake.Calls)));
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeHelpFrameTests);

end.
