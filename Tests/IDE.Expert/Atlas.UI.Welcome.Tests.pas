unit Atlas.UI.Welcome.Tests;

// Oberfläche der Atlas-Willkommensseite (#753): Texte im Kopf (Grußzeile,
// Kurzstatus, Tausendertrennzeichen je Sprache), Fabriken der Bereiche und
// der Frame „Atlas“ mit Kopf und Bereichen in Spalten; Suchfeld im Kopf
// (#760): Ein-/Ausblenden, Abfrage, Auswahl mit Grenzen, Öffnen und Esc;
// Karte „Neu in Atlas“ (#756): Zeilen mit Schalter, Taste und
// „Ausprobieren“, Gruppen je Version, Auf- und Zuklappen, Kontextmenü;
// Bereich „Projekte“ (#592): Texte der Marken, Zeilen und Höhe, Tooltip,
// Klicks auf Zeile, Fehler-Marke und Kontextmenü; Bereich „Nicht gesichert“
// (#762): Texte je Art und Alter, leerer Bereich, nur die Schaltfläche löst
// eine Aktion aus, Kontextmenü, Rückfrage vor dem Push mit „Abbrechen“ als
// Vorgabe; Zustandskachel „Atlas“ (#754): Ersatztexte, „Jetzt aktualisieren“
// nur mit Update, Klicks auf Zeilen mit Aktion und auf die Knöpfe; Karte
// „Atlas entdecken“ (#757): Hinweise zur Nutzung, Tipp mit Kürzel und Stelle,
// Knöpfe nach Lage, leere Karte, Klicks über die Nachrichtenschleife;
// Bereich „Hilfe und Rückmeldung“ (#766): Texte, drei Knöpfe mit Umbruch,
// „Tastenkürzel“ nur mit Übersicht, Klicks über die Nachrichtenschleife;
// Bereich „Weiterarbeiten“ (#755): Texte (Reiter, Zeit, Commit, Zeile der
// Liste „Gemerkt“), „Fortsetzen“ und Commits über die Nachrichtenschleife,
// Abschnitt der eingehenden Commits nur mit Daten, Reiter „Gemerkt“ nur mit
// welcomePage.saved, Filter und Öffnen per Enter bzw. Doppelklick;
// Bereich „Projektverlauf“ (#758): Wert, Vorwert und Einheit je Kachel,
// Klick auf einen Punkt zeigt Build, Datum, Branch und Commit, leere
// Zustände, Umbruch der Kacheln; Auswahl in „Projekte“ (Klick wählt,
// Doppelklick und „Öffnen“ öffnen); frei anordnen (#767): Leiste,
// Bearbeitungsmodus mit Griff, Strg+Pfeiltasten, Breite und Auge, Menüs
// „Layout“ und „Bereich hinzufügen“, Leiste „Ausgeblendet“ und Rechtsklick
// „Ausblenden“; ohne welcomePage.customLayout kein Bearbeitungsmodus;
// Scrollen der Tafel (#1440): Mausrad über Bereich und Kopf, innere Liste
// zuerst, Tasten und welche Steuerelemente ihre Tasten behalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
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
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeBoardTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure ViewsCreateFramesWithId;
    [Test]
    procedure BoardPlacesSectionsInColumns;
    [Test]
    procedure BoardKeepsAndDropsFrames;
    [Test]
    procedure WheelScrollsPageFromSectionAndHeader;
    [Test]
    procedure WheelScrollsInnerListFirst;
    [Test]
    procedure KeysScrollPage;
    [Test]
    procedure ScrollKeysAndOwnersFollowControl;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Welcome.Scroll,
  Atlas.Core.Status.Lines,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Layout,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.Header,
  Atlas.UI.Welcome.Board,
  Atlas.UI.Welcome.TestSupport;

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
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeHeaderTitle), Header.GreetingLabel.Caption);
  finally
    Header.Free;
    TAtlasStrings.Language := Saved;
  end;
end;
procedure TAtlasWelcomeBoardTests.WarmUpFirstUse;
begin
  BoardPlacesSectionsInColumns;
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
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Kept: TAtlasWelcomeSectionFrame;
  Before: Integer;
begin
  RegisterViews([TAtlasWelcomeIds.Continue, TAtlasWelcomeIds.State]);
  // Wie in der IDE: Die Tafel hängt an einem Fenster.
  Host := TForm.CreateNew(nil);
  Board := TAtlasWelcomeBoardFrame.Create(nil);
  try
    Board.Parent := Host;
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
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
/// <summary>Tafel mit drei Bereichen untereinander in einem niedrigen Fenster: Der Inhalt ist höher als der Platz.</summary>
function TallBoard(AHost: TForm): TAtlasWelcomeBoardFrame;
begin
  RegisterViews([TAtlasWelcomeIds.Continue, TAtlasWelcomeIds.Projects, TAtlasWelcomeIds.State]);
  AHost.ClientWidth := 400;
  AHost.ClientHeight := 160;
  Result := TAtlasWelcomeBoardFrame.Create(AHost);
  Result.Parent := AHost;
  Result.Align := alClient;
  Result.Rebuild([Section(TAtlasWelcomeIds.Continue, 10, TAtlasWelcomeColumn.Left),
    Section(TAtlasWelcomeIds.Projects, 20, TAtlasWelcomeColumn.Left),
    Section(TAtlasWelcomeIds.State, 30, TAtlasWelcomeColumn.Left)], TAtlasWelcomeLayout.Atlas, 1);
  // Ohne gezeigtes Fenster: Bereich der Leiste mit Fenster rechnen lassen.
  Result.ScrollBox.HandleNeeded;
  Result.ScrollBox.Realign;
end;
procedure TAtlasWelcomeBoardTests.WheelScrollsPageFromSectionAndHeader;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  mOther: TPanel;
begin
  Host := TForm.CreateNew(nil);
  try
    Board := TallBoard(Host);
    Assert.IsTrue(Board.ScrollBox.VertScrollBar.IsScrollBarVisible, 'Überlänge zeigt die Leiste');
    Assert.AreEqual(0, Board.ScrollBox.VertScrollBar.Position);
    Assert.IsFalse(Board.ScrollWheel(Board.View(TAtlasWelcomeIds.Continue), 120), 'oben geht es nicht weiter');
    Assert.IsTrue(Board.ScrollWheel(Board.View(TAtlasWelcomeIds.Continue).TitleLabel, -120),
      'über einem Bereich scrollt die Seite');
    Assert.IsTrue(Board.ScrollBox.VertScrollBar.Position > 0);
    Assert.IsTrue(Board.ScrollWheel(Board.Header, 3 * 120), 'über dem Kopf auch');
    Assert.AreEqual(0, Board.ScrollBox.VertScrollBar.Position);
    mOther := TPanel.Create(Host);
    mOther.Parent := Host;
    Assert.IsFalse(Board.Contains(mOther));
    Assert.IsFalse(Board.ScrollWheel(mOther, -120), 'außerhalb der Tafel nicht');
    Assert.IsFalse(Board.ScrollWheel(nil, -120));
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
procedure TAtlasWelcomeBoardTests.WheelScrollsInnerListFirst;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  mInner: TScrollBox;
  mContent: TPanel;
  mBar: TControlScrollBar;
begin
  Host := TForm.CreateNew(nil);
  try
    Board := TallBoard(Host);
    // Wie „Neu in Atlas“: eine eigene Scrollbox im Bereich.
    mInner := TScrollBox.Create(Host);
    mInner.Parent := Board.View(TAtlasWelcomeIds.Continue);
    mInner.BorderStyle := bsNone;
    mInner.SetBounds(0, 0, 200, 40);
    mContent := TPanel.Create(Host);
    mContent.Parent := mInner;
    mContent.SetBounds(0, 0, 180, 400);
    mInner.HandleNeeded;
    mInner.Realign;
    mBar := mInner.VertScrollBar;
    Assert.IsTrue(mBar.IsScrollBarVisible, 'innere Liste mit Überlänge');
    Assert.IsTrue(Board.ScrollWheel(mContent, -120));
    Assert.IsTrue(mBar.Position > 0, 'die innere Liste scrollt zuerst');
    Assert.AreEqual(0, Board.ScrollBox.VertScrollBar.Position, 'die Seite bleibt stehen');
    // Am Ende der Liste geht das Rad an die Seite.
    mBar.Position := mBar.Range;
    Assert.IsTrue(Board.ScrollWheel(mContent, -120));
    Assert.IsTrue(Board.ScrollBox.VertScrollBar.Position > 0, 'danach die Seite');
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
procedure TAtlasWelcomeBoardTests.KeysScrollPage;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  mBar: TControlScrollBar;
  mPage: Integer;
begin
  Host := TForm.CreateNew(nil);
  try
    Board := TallBoard(Host);
    mBar := Board.ScrollBox.VertScrollBar;
    Assert.IsFalse(Board.ScrollKey(TAtlasWelcomeScrollKey.PageUp), 'oben bleibt Bild auf ohne Wirkung');
    Assert.IsTrue(Board.ScrollKey(TAtlasWelcomeScrollKey.PageDown));
    mPage := mBar.Position;
    Assert.IsTrue(mPage > 0);
    Assert.IsTrue(Board.ScrollKey(TAtlasWelcomeScrollKey.Bottom));
    Assert.IsTrue(mBar.Position >= mPage);
    Assert.IsFalse(Board.ScrollKey(TAtlasWelcomeScrollKey.Bottom), 'am Ende bleibt es stehen');
    Assert.IsFalse(Board.ScrollKey(TAtlasWelcomeScrollKey.PageDown));
    Assert.IsTrue(Board.ScrollKey(TAtlasWelcomeScrollKey.Top));
    Assert.AreEqual(0, mBar.Position);
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
procedure TAtlasWelcomeBoardTests.ScrollKeysAndOwnersFollowControl;
var
  mEdit: TEdit;
  mList: TListBox;
  mCombo: TComboBox;
  mPanel: TPanel;
begin
  Assert.AreEqual(Ord(TAtlasWelcomeScrollKey.PageUp), Ord(TAtlasWelcomeBoardFrame.ScrollKeyOf(VK_PRIOR, [])));
  Assert.AreEqual(Ord(TAtlasWelcomeScrollKey.PageDown), Ord(TAtlasWelcomeBoardFrame.ScrollKeyOf(VK_NEXT, [])));
  Assert.AreEqual(Ord(TAtlasWelcomeScrollKey.Top), Ord(TAtlasWelcomeBoardFrame.ScrollKeyOf(VK_HOME, [ssCtrl])));
  Assert.AreEqual(Ord(TAtlasWelcomeScrollKey.Bottom), Ord(TAtlasWelcomeBoardFrame.ScrollKeyOf(VK_END, [])));
  Assert.AreEqual(Ord(TAtlasWelcomeScrollKey.None), Ord(TAtlasWelcomeBoardFrame.ScrollKeyOf(VK_NEXT, [ssAlt])),
    'Alt bleibt bei der IDE');
  Assert.AreEqual(Ord(TAtlasWelcomeScrollKey.None), Ord(TAtlasWelcomeBoardFrame.ScrollKeyOf(Ord('A'), [])));
  mEdit := TEdit.Create(nil);
  mList := TListBox.Create(nil);
  mCombo := TComboBox.Create(nil);
  mPanel := TPanel.Create(nil);
  try
    Assert.IsTrue(TAtlasWelcomeBoardFrame.OwnsScrollKeys(mEdit), 'Eingabefeld');
    Assert.IsTrue(TAtlasWelcomeBoardFrame.OwnsScrollKeys(mList), 'Liste');
    Assert.IsTrue(TAtlasWelcomeBoardFrame.OwnsScrollKeys(mCombo), 'Auswahlfeld');
    Assert.IsFalse(TAtlasWelcomeBoardFrame.OwnsScrollKeys(mPanel));
    Assert.IsFalse(TAtlasWelcomeBoardFrame.OwnsScrollKeys(nil));
  finally
    mPanel.Free;
    mCombo.Free;
    mList.Free;
    mEdit.Free;
  end;
end;
initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeHeaderTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeBoardTests);

end.
