unit Atlas.UI.Editor.Hide.Tests;

// Ausblenden am Element (#628), Fensterteil: Menü mit den Bereichen, die das
// Element anbietet (Mockup Runde 25 Z6 plus „In dieser Datei“), Untermenüs
// bei mehreren Elementen, Wahl an OnChoose; Hinweis „Ausgeblendet ·
// Rückgängig“ mit Lage unter dem Element und Klick auf „Rückgängig“; die
// Optionsseite kennt zu jedem Element und jedem Bereich der Willkommensseite
// die Zeile (Reveal, „Einstellungen dazu …“).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasHideUiTests = class
  public
    /// <summary>Erste Benutzung von Menü, Hinweisfenster und Einstellungsseite ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MenuOfBlockEndLabelLikeMockup;
    [Test]
    procedure MenuOnlyOffersScopesOfElement;
    [Test]
    procedure SeveralElementsGetSubmenus;
    [Test]
    procedure ChoiceReachesOnChoose;
    [Test]
    procedure EveryElementHasNames;
    [Test]
    procedure NoticeSitsBelowElementInsideWorkArea;
    [Test]
    procedure NoticeUndoRaisesEventAndHides;
    [Test]
    procedure PageRevealsEverySettingOfElementsAndWelcome;
  end;

implementation

uses
  Atlas.Core.Modules.Contract,
  Atlas.UI.Welcome.TestSupport,
  System.SysUtils,
  System.Types,
  System.UITypes,
  System.Classes,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.ComCtrls,
  Vcl.StdCtrls,
  Vcl.Graphics,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Editor.Hide,
  Atlas.UI.Strings,
  Atlas.UI.Editor.Strings,
  Atlas.UI.Editor.Hide,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Analysis.SettingsSection,
  Atlas.UI.Tests.SettingsSection,
  Atlas.UI.Bookmarks.SettingsSection;

type
  /// <summary>Zählt „Rückgängig“ (TNotifyEvent braucht eine Methode).</summary>
  TUndoCounter = class
  public
    Count: Integer;
    procedure UndoClick(Sender: TObject);
  end;

var
  Language: TAtlasLanguage;

procedure TUndoCounter.UndoClick(Sender: TObject);
begin
  Inc(Count);
end;

function Target(AElement: TAtlasDrawnElement): TAtlasHideTarget;
begin
  Result := TAtlasHideTarget.Create(AElement, 'C:\Projekt\Kunde.pas', 41, 'TKunde.Speichern');
end;

procedure TAtlasHideUiTests.Setup;
begin
  Language := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasHideUiTests.TearDown;
begin
  TAtlasStrings.Language := Language;
end;

procedure TAtlasHideUiTests.WarmUpFirstUse;
begin
  Setup;
  try
    try
      MenuOfBlockEndLabelLikeMockup;
      NoticeUndoRaisesEventAndHides;
      PageRevealsEverySettingOfElementsAndWelcome;
    except
      on Exception do
        ;
    end;
  finally
    TearDown;
  end;
end;

procedure TAtlasHideUiTests.MenuOfBlockEndLabelLikeMockup;
var
  mMenu: TAtlasHideMenu;
begin
  mMenu := TAtlasHideMenu.Create(nil);
  try
    mMenu.Build([Target(TAtlasDrawnElement.BlockEndLabels)]);
    Assert.AreEqual(5, Integer(mMenu.Menu.Items.Count));
    Assert.AreEqual('Nur hier ausblenden', mMenu.Menu.Items[0].Caption);
    Assert.AreEqual('In dieser Datei ausblenden', mMenu.Menu.Items[1].Caption);
    Assert.AreEqual('Blockende-Beschriftungen überall ausblenden', mMenu.Menu.Items[2].Caption);
    Assert.IsTrue(mMenu.Menu.Items[3].IsLine, 'Trennlinie');
    Assert.AreEqual('Einstellungen dazu …', mMenu.Menu.Items[4].Caption);
    Assert.AreEqual(4, Integer(Length(mMenu.Choices)));
    Assert.IsTrue(mMenu.Choices[3].Settings);
  finally
    mMenu.Free;
  end;
end;

procedure TAtlasHideUiTests.MenuOnlyOffersScopesOfElement;
var
  mMenu: TAtlasHideMenu;
begin
  mMenu := TAtlasHideMenu.Create(nil);
  try
    // Klammerfarben gelten je Datei: kein „Nur hier“.
    mMenu.Build([Target(TAtlasDrawnElement.PairColors)]);
    Assert.AreEqual(4, Integer(mMenu.Menu.Items.Count));
    Assert.AreEqual('In dieser Datei ausblenden', mMenu.Menu.Items[0].Caption);
    Assert.AreEqual('Klammerfarben überall ausblenden', mMenu.Menu.Items[1].Caption);
    // Die Vorschau der Vervollständigung nur überall.
    mMenu.Build([Target(TAtlasDrawnElement.CompletionPreview)]);
    Assert.AreEqual(3, Integer(mMenu.Menu.Items.Count));
    Assert.AreEqual(2, Integer(Length(mMenu.Choices)));
    Assert.AreEqual<TAtlasHideScope>(TAtlasHideScope.Everywhere, mMenu.Choices[0].Scope);
  finally
    mMenu.Free;
  end;
end;

procedure TAtlasHideUiTests.SeveralElementsGetSubmenus;
var
  mMenu: TAtlasHideMenu;
begin
  mMenu := TAtlasHideMenu.Create(nil);
  try
    mMenu.Build([TAtlasHideTarget.Finding('C:\Projekt\Kunde.pas', 3, 'unused-variable', '  X := 1;'),
      Target(TAtlasDrawnElement.InlayHints), Target(TAtlasDrawnElement.InlayHints)]);
    Assert.AreEqual(2, Integer(mMenu.Menu.Items.Count), 'gleiches Element nur einmal');
    Assert.AreEqual('Befund-Unterstreichung', mMenu.Menu.Items[0].Caption);
    Assert.AreEqual('Inlay-Hint', mMenu.Menu.Items[1].Caption);
    Assert.AreEqual(5, Integer(mMenu.Menu.Items[0].Count));
    Assert.AreEqual('Befund-Unterstreichungen überall ausblenden', mMenu.Menu.Items[0].Items[2].Caption);
    Assert.AreEqual(8, Integer(Length(mMenu.Choices)));
    Assert.AreEqual('unused-variable', mMenu.Choices[0].Target.RuleId);
  finally
    mMenu.Free;
  end;
end;

procedure TAtlasHideUiTests.ChoiceReachesOnChoose;
var
  mMenu: TAtlasHideMenu;
  mChosen: TAtlasHideChoice;
  mCalls: Integer;
begin
  mCalls := 0;
  mChosen := Default(TAtlasHideChoice);
  mMenu := TAtlasHideMenu.Create(nil);
  try
    mMenu.OnChoose :=
      procedure(AChoice: TAtlasHideChoice)
      begin
        Inc(mCalls);
        mChosen := AChoice;
      end;
    mMenu.Build([Target(TAtlasDrawnElement.BlockEndLabels)]);
    // Wie ein Klick auf „Blockende-Beschriftungen überall ausblenden“.
    mMenu.Menu.Items[2].Click;
    Assert.AreEqual(1, mCalls);
    Assert.AreEqual<TAtlasHideScope>(TAtlasHideScope.Everywhere, mChosen.Scope);
    Assert.IsFalse(mChosen.Settings);
    Assert.AreEqual('BlockEndLabels', mChosen.Target.SettingKey);
    mMenu.Menu.Items[4].Click;
    Assert.AreEqual(2, mCalls);
    Assert.IsTrue(mChosen.Settings, '„Einstellungen dazu …“');
    mMenu.Choose(99);
    Assert.AreEqual(2, mCalls, 'unbekannter Eintrag: nichts');
  finally
    mMenu.Free;
    mChosen := Default(TAtlasHideChoice);
  end;
end;

procedure TAtlasHideUiTests.EveryElementHasNames;
var
  mElement: TAtlasDrawnElement;
  mScope: TAtlasHideScope;
begin
  for mElement := Low(TAtlasDrawnElement) to High(TAtlasDrawnElement) do
  begin
    Assert.AreNotEqual('', TAtlasHideMenu.ElementName(mElement, False), 'Einzahl ' + IntToStr(Ord(mElement)));
    Assert.AreNotEqual('', TAtlasHideMenu.ElementName(mElement, True), 'Mehrzahl ' + IntToStr(Ord(mElement)));
    for mScope := Low(TAtlasHideScope) to High(TAtlasHideScope) do
    begin
      Assert.AreNotEqual('', TAtlasHideMenu.ScopeCaption(mElement, mScope));
    end;
  end;
  TAtlasStrings.Language := TAtlasLanguage.English;
  Assert.AreEqual('Hide block end labels everywhere',
    TAtlasHideMenu.ScopeCaption(TAtlasDrawnElement.BlockEndLabels, TAtlasHideScope.Everywhere));
end;

procedure TAtlasHideUiTests.NoticeSitsBelowElementInsideWorkArea;
var
  mBounds: TRect;
begin
  mBounds := TAtlasHideNoticeWindow.PlaceBelow(Point(100, 200), 180, 40, 4, Rect(0, 0, 1000, 800));
  Assert.AreEqual(100, mBounds.Left);
  Assert.AreEqual(204, mBounds.Top);
  Assert.AreEqual(180, mBounds.Width);
  // Unten kein Platz: darüber; rechts kein Platz: nach links.
  mBounds := TAtlasHideNoticeWindow.PlaceBelow(Point(950, 790), 180, 40, 4, Rect(0, 0, 1000, 800));
  Assert.AreEqual(746, mBounds.Top);
  Assert.AreEqual(820, mBounds.Left);
end;

procedure TAtlasHideUiTests.NoticeUndoRaisesEventAndHides;
var
  mWindow: TAtlasHideNoticeWindow;
  mCounter: TUndoCounter;
begin
  mCounter := TUndoCounter.Create;
  mWindow := TAtlasHideNoticeWindow.Create(nil);
  try
    mWindow.Colors := TAtlasColors.Light;
    mWindow.SetScaling(96, 1, 'Segoe UI', 9);
    mWindow.OnUndo := mCounter.UndoClick;
    mWindow.ShowNotice(TAtlasEditorStrings.Text(TAtlasEditorTextId.HideNotice),
      'Einstellung „Blockende-Beschriftungen“ ausgeschaltet.', True, Point(200, 200));
    try
      Assert.IsTrue(mWindow.IsShown);
      Assert.IsTrue(mWindow.Timer.Enabled, 'verschwindet von selbst');
      Assert.AreEqual(TAtlasHideNoticeWindow.cVisibleMs, Integer(mWindow.Timer.Interval));
      Assert.IsFalse(mWindow.UndoRect.IsEmpty, '„Rückgängig“ ist da');
      Assert.AreEqual('Ausgeblendet', mWindow.Title);
      mWindow.ClickUndo;
      Assert.AreEqual(1, Integer(mCounter.Count));
      Assert.IsFalse(mWindow.IsShown, 'Klick blendet aus');
      // Ohne Rückgängig (etwa ein abgelehnter Bereich): kein Link, Klick ohne Wirkung.
      mWindow.ShowNotice('', TAtlasEditorStrings.Text(TAtlasEditorTextId.HideRefusedAlready), False, Point(200, 200));
      Assert.IsTrue(mWindow.UndoRect.IsEmpty);
      mWindow.ClickUndo;
      Assert.AreEqual(1, Integer(mCounter.Count));
    finally
      mWindow.Dismiss;
    end;
  finally
    mWindow.Free;
    mCounter.Free;
  end;
end;

procedure TAtlasHideUiTests.PageRevealsEverySettingOfElementsAndWelcome;
var
  mWelcome: IAtlasRegistration;
  mModules: TArray<IAtlasRegistration>;
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mElement: TAtlasDrawnElement;
  mSection: string;
  mKey: string;
  mControl: TControl;
  mParent: TWinControl;
begin
  mWelcome := ProvideWelcomeSettings;
  // Zeilen der Module (#1456): Code Lens an Testmethoden, Notizen und Lesezeichen.
  mModules := ProvideSections([TAtlasTestsEditorSection, TAtlasBookmarksEditorSection, TAtlasAnalysisEditorSection]);
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    for mElement := Low(TAtlasDrawnElement) to High(TAtlasDrawnElement) do
    begin
      mKey := TAtlasDrawnElements.SettingKey(mElement);
      Assert.IsNotNull(mPage.ControlOf(mKey), 'Zeile für ' + mKey);
    end;
    // Bereiche der Willkommensseite (#767) über ihren Schlüssel.
    for mSection in TAtlasDrawnElements.KnownSections do
    begin
      Assert.IsNotNull(mPage.ControlOf(TAtlasDrawnElements.SectionSetting(mSection)), 'Zeile für ' + mSection);
    end;
    Assert.IsNull(mPage.ControlOf('GibtEsNicht'));
    Assert.IsFalse(mPage.Reveal('GibtEsNicht'));
    // Reveal wählt den Reiter der Zeile und hebt sie hervor.
    Assert.IsTrue(mPage.Reveal('BlockEndLabels'));
    mControl := mPage.ControlOf('BlockEndLabels');
    mParent := mControl.Parent;
    while (mParent <> nil) and not (mParent is TTabSheet) do
    begin
      mParent := mParent.Parent;
    end;
    Assert.IsNotNull(mParent);
    Assert.AreSame(mParent, mPage.Pages.ActivePage, 'Reiter der Zeile gewählt');
    Assert.IsTrue(fsBold in TCheckBox(mControl).Font.Style, 'Zeile hervorgehoben');
  finally
    mHost.Free;
    mWelcome.Revoke;
    RevokeAll(mModules);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasHideUiTests);

end.
