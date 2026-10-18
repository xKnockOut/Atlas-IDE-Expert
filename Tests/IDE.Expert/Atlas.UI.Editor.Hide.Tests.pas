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
  Atlas.UI.Editor.Hide,
  Atlas.UI.Settings.Page;

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
  Menu: TAtlasHideMenu;
begin
  Menu := TAtlasHideMenu.Create(nil);
  try
    Menu.Build([Target(TAtlasDrawnElement.BlockEndLabels)]);
    Assert.AreEqual(5, Integer(Menu.Menu.Items.Count));
    Assert.AreEqual('Nur hier ausblenden', Menu.Menu.Items[0].Caption);
    Assert.AreEqual('In dieser Datei ausblenden', Menu.Menu.Items[1].Caption);
    Assert.AreEqual('Blockende-Beschriftungen überall ausblenden', Menu.Menu.Items[2].Caption);
    Assert.IsTrue(Menu.Menu.Items[3].IsLine, 'Trennlinie');
    Assert.AreEqual('Einstellungen dazu …', Menu.Menu.Items[4].Caption);
    Assert.AreEqual(4, Integer(Length(Menu.Choices)));
    Assert.IsTrue(Menu.Choices[3].Settings);
  finally
    Menu.Free;
  end;
end;

procedure TAtlasHideUiTests.MenuOnlyOffersScopesOfElement;
var
  Menu: TAtlasHideMenu;
begin
  Menu := TAtlasHideMenu.Create(nil);
  try
    // Klammerfarben gelten je Datei: kein „Nur hier“.
    Menu.Build([Target(TAtlasDrawnElement.PairColors)]);
    Assert.AreEqual(4, Integer(Menu.Menu.Items.Count));
    Assert.AreEqual('In dieser Datei ausblenden', Menu.Menu.Items[0].Caption);
    Assert.AreEqual('Klammerfarben überall ausblenden', Menu.Menu.Items[1].Caption);
    // Die Vorschau der Vervollständigung nur überall.
    Menu.Build([Target(TAtlasDrawnElement.CompletionPreview)]);
    Assert.AreEqual(3, Integer(Menu.Menu.Items.Count));
    Assert.AreEqual(2, Integer(Length(Menu.Choices)));
    Assert.IsTrue(Menu.Choices[0].Scope = TAtlasHideScope.Everywhere);
  finally
    Menu.Free;
  end;
end;

procedure TAtlasHideUiTests.SeveralElementsGetSubmenus;
var
  Menu: TAtlasHideMenu;
begin
  Menu := TAtlasHideMenu.Create(nil);
  try
    Menu.Build([TAtlasHideTarget.Finding('C:\Projekt\Kunde.pas', 3, 'unused-variable', '  X := 1;'),
      Target(TAtlasDrawnElement.InlayHints), Target(TAtlasDrawnElement.InlayHints)]);
    Assert.AreEqual(2, Integer(Menu.Menu.Items.Count), 'gleiches Element nur einmal');
    Assert.AreEqual('Befund-Unterstreichung', Menu.Menu.Items[0].Caption);
    Assert.AreEqual('Inlay-Hint', Menu.Menu.Items[1].Caption);
    Assert.AreEqual(5, Integer(Menu.Menu.Items[0].Count));
    Assert.AreEqual('Befund-Unterstreichungen überall ausblenden', Menu.Menu.Items[0].Items[2].Caption);
    Assert.AreEqual(8, Integer(Length(Menu.Choices)));
    Assert.AreEqual('unused-variable', Menu.Choices[0].Target.RuleId);
  finally
    Menu.Free;
  end;
end;

procedure TAtlasHideUiTests.ChoiceReachesOnChoose;
var
  Menu: TAtlasHideMenu;
  Chosen: TAtlasHideChoice;
  Calls: Integer;
begin
  Calls := 0;
  Chosen := Default(TAtlasHideChoice);
  Menu := TAtlasHideMenu.Create(nil);
  try
    Menu.OnChoose :=
      procedure(AChoice: TAtlasHideChoice)
      begin
        Inc(Calls);
        Chosen := AChoice;
      end;
    Menu.Build([Target(TAtlasDrawnElement.BlockEndLabels)]);
    // Wie ein Klick auf „Blockende-Beschriftungen überall ausblenden“.
    Menu.Menu.Items[2].Click;
    Assert.AreEqual(1, Calls);
    Assert.IsTrue(Chosen.Scope = TAtlasHideScope.Everywhere);
    Assert.IsFalse(Chosen.Settings);
    Assert.AreEqual('BlockEndLabels', Chosen.Target.SettingKey);
    Menu.Menu.Items[4].Click;
    Assert.AreEqual(2, Calls);
    Assert.IsTrue(Chosen.Settings, '„Einstellungen dazu …“');
    Menu.Choose(99);
    Assert.AreEqual(2, Calls, 'unbekannter Eintrag: nichts');
  finally
    Menu.Free;
    Chosen := Default(TAtlasHideChoice);
  end;
end;

procedure TAtlasHideUiTests.EveryElementHasNames;
var
  Element: TAtlasDrawnElement;
  Scope: TAtlasHideScope;
begin
  for Element := Low(TAtlasDrawnElement) to High(TAtlasDrawnElement) do
  begin
    Assert.IsTrue(TAtlasHideMenu.ElementName(Element, False) <> '', 'Einzahl ' + IntToStr(Ord(Element)));
    Assert.IsTrue(TAtlasHideMenu.ElementName(Element, True) <> '', 'Mehrzahl ' + IntToStr(Ord(Element)));
    for Scope := Low(TAtlasHideScope) to High(TAtlasHideScope) do
      Assert.IsTrue(TAtlasHideMenu.ScopeCaption(Element, Scope) <> '');
  end;
  TAtlasStrings.Language := TAtlasLanguage.English;
  Assert.AreEqual('Hide block end labels everywhere',
    TAtlasHideMenu.ScopeCaption(TAtlasDrawnElement.BlockEndLabels, TAtlasHideScope.Everywhere));
end;

procedure TAtlasHideUiTests.NoticeSitsBelowElementInsideWorkArea;
var
  Bounds: TRect;
begin
  Bounds := TAtlasHideNoticeWindow.PlaceBelow(Point(100, 200), 180, 40, 4, Rect(0, 0, 1000, 800));
  Assert.AreEqual(100, Bounds.Left);
  Assert.AreEqual(204, Bounds.Top);
  Assert.AreEqual(180, Bounds.Width);
  // Unten kein Platz: darüber; rechts kein Platz: nach links.
  Bounds := TAtlasHideNoticeWindow.PlaceBelow(Point(950, 790), 180, 40, 4, Rect(0, 0, 1000, 800));
  Assert.AreEqual(746, Bounds.Top);
  Assert.AreEqual(820, Bounds.Left);
end;

procedure TAtlasHideUiTests.NoticeUndoRaisesEventAndHides;
var
  Window: TAtlasHideNoticeWindow;
  Counter: TUndoCounter;
begin
  Counter := TUndoCounter.Create;
  Window := TAtlasHideNoticeWindow.Create(nil);
  try
    Window.Colors := TAtlasColors.Light;
    Window.SetScaling(96, 1, 'Segoe UI', 9);
    Window.OnUndo := Counter.UndoClick;
    Window.ShowNotice(TAtlasStrings.Text(TAtlasTextId.HideNotice),
      'Einstellung „Blockende-Beschriftungen“ ausgeschaltet.', True, Point(200, 200));
    try
      Assert.IsTrue(Window.IsShown);
      Assert.IsTrue(Window.Timer.Enabled, 'verschwindet von selbst');
      Assert.AreEqual(TAtlasHideNoticeWindow.VisibleMs, Integer(Window.Timer.Interval));
      Assert.IsFalse(Window.UndoRect.IsEmpty, '„Rückgängig“ ist da');
      Assert.AreEqual('Ausgeblendet', Window.Title);
      Window.ClickUndo;
      Assert.AreEqual(1, Integer(Counter.Count));
      Assert.IsFalse(Window.IsShown, 'Klick blendet aus');
      // Ohne Rückgängig (etwa ein abgelehnter Bereich): kein Link, Klick ohne Wirkung.
      Window.ShowNotice('', TAtlasStrings.Text(TAtlasTextId.HideRefusedAlready), False, Point(200, 200));
      Assert.IsTrue(Window.UndoRect.IsEmpty);
      Window.ClickUndo;
      Assert.AreEqual(1, Integer(Counter.Count));
    finally
      Window.Dismiss;
    end;
  finally
    Window.Free;
    Counter.Free;
  end;
end;

procedure TAtlasHideUiTests.PageRevealsEverySettingOfElementsAndWelcome;
var
  Host: TForm;
  Page: TAtlasSettingsPage;
  Element: TAtlasDrawnElement;
  Section: string;
  Key: string;
  Control: TControl;
  Parent: TWinControl;
begin
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSettingsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    for Element := Low(TAtlasDrawnElement) to High(TAtlasDrawnElement) do
    begin
      Key := TAtlasDrawnElements.SettingKey(Element);
      Assert.IsNotNull(Page.ControlOf(Key), 'Zeile für ' + Key);
    end;
    // Bereiche der Willkommensseite (#767) über ihren Schlüssel.
    for Section in TAtlasDrawnElements.KnownSections do
      Assert.IsNotNull(Page.ControlOf(TAtlasDrawnElements.SectionSetting(Section)), 'Zeile für ' + Section);
    Assert.IsNull(Page.ControlOf('GibtEsNicht'));
    Assert.IsFalse(Page.Reveal('GibtEsNicht'));
    // Reveal wählt den Reiter der Zeile und hebt sie hervor.
    Assert.IsTrue(Page.Reveal('BlockEndLabels'));
    Control := Page.ControlOf('BlockEndLabels');
    Parent := Control.Parent;
    while (Parent <> nil) and not (Parent is TTabSheet) do
      Parent := Parent.Parent;
    Assert.IsNotNull(Parent);
    Assert.IsTrue(Page.Pages.ActivePage = Parent, 'Reiter der Zeile gewählt');
    Assert.IsTrue(fsBold in TCheckBox(Control).Font.Style, 'Zeile hervorgehoben');
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasHideUiTests);

end.
