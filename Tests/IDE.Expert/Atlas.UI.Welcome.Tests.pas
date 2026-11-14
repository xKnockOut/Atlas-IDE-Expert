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
    [Test]
    procedure SameInfoComparesAllFields;
    [Test]
    procedure SameInfoLeavesHeaderAlone;
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
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Guten Morgen, Marco', TAtlasWelcomeHeaderFrame.GreetingText(8, 'Marco'));
    Assert.AreEqual('Guten Tag, Marco', TAtlasWelcomeHeaderFrame.GreetingText(14, 'Marco'));
    Assert.AreEqual('Guten Abend, Marco', TAtlasWelcomeHeaderFrame.GreetingText(20, 'Marco'));
    Assert.AreEqual('Gute Nacht', TAtlasWelcomeHeaderFrame.GreetingText(2, ''), 'ohne Namen nur der Gruß');
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Good evening, Marco', TAtlasWelcomeHeaderFrame.GreetingText(20, 'Marco'));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;
procedure TAtlasWelcomeHeaderTests.StatusShowsServerAndIndex;
var
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
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
    TAtlasStrings.Language := mSaved;
  end;
end;
procedure TAtlasWelcomeHeaderTests.ThousandsFollowLanguage;
var
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('1.234.567', TAtlasWelcomeHeaderFrame.Thousands(1234567));
    Assert.AreEqual('0', TAtlasWelcomeHeaderFrame.Thousands(0));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('1,284', TAtlasWelcomeHeaderFrame.Thousands(1284));
    Assert.AreEqual('Server running · 1,284 units in the index',
      TAtlasWelcomeHeaderFrame.StatusText(TAtlasServerPhase.Running, 1284, False, -1));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;
procedure TAtlasWelcomeHeaderTests.InfoShowsVersion;
var
  mSaved: TAtlasLanguage;
  mInfo: TAtlasWelcomeHeaderInfo;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mInfo := Default(TAtlasWelcomeHeaderInfo);
    mInfo.Version := '1.0.0';
    mInfo.Phase := TAtlasServerPhase.Stopped;
    mInfo.Units := -1;
    mInfo.Percent := -1;
    Assert.AreEqual('Atlas 1.0.0 · Server gestoppt', TAtlasWelcomeHeaderFrame.InfoText(mInfo));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;
procedure TAtlasWelcomeHeaderTests.ShowInfoFillsLabels;
var
  mSaved: TAtlasLanguage;
  mHeader: TAtlasWelcomeHeaderFrame;
  mInfo: TAtlasWelcomeHeaderInfo;
begin
  mSaved := TAtlasStrings.Language;
  mHeader := TAtlasWelcomeHeaderFrame.Create(nil);
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mInfo := Default(TAtlasWelcomeHeaderInfo);
    mInfo.Greeting := True;
    mInfo.Hour := 9;
    mInfo.FirstName := 'Marco';
    mInfo.Version := '1.0.0';
    mInfo.Phase := TAtlasServerPhase.Running;
    mInfo.Units := 42;
    mInfo.Percent := -1;
    mHeader.ShowInfo(mInfo);
    Assert.AreEqual('Guten Morgen, Marco', mHeader.GreetingLabel.Caption);
    Assert.AreEqual('Atlas 1.0.0 · Server läuft · 42 Units im Index', mHeader.InfoLabel.Caption);
    Assert.AreEqual(0, mHeader.SearchHost.Width, 'Platz für das Suchfeld (#760) noch leer');
    // welcomePage.greeting aus: nur „Atlas“.
    mInfo.Greeting := False;
    mHeader.ShowInfo(mInfo);
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeHeaderTitle), mHeader.GreetingLabel.Caption);
  finally
    mHeader.Free;
    TAtlasStrings.Language := mSaved;
  end;
end;

function SampleInfo: TAtlasWelcomeHeaderInfo;
begin
  Result := Default(TAtlasWelcomeHeaderInfo);
  Result.Greeting := True;
  Result.Hour := 9;
  Result.FirstName := 'Marco';
  Result.Version := '1.0.0';
  Result.Phase := TAtlasServerPhase.Running;
  Result.Units := 42;
  Result.Percent := -1;
end;

procedure TAtlasWelcomeHeaderTests.SameInfoComparesAllFields;
var
  mOther: TAtlasWelcomeHeaderInfo;
begin
  Assert.IsTrue(TAtlasWelcomeHeaderFrame.SameInfo(SampleInfo, SampleInfo));
  mOther := SampleInfo;
  mOther.Greeting := False;
  Assert.IsFalse(TAtlasWelcomeHeaderFrame.SameInfo(SampleInfo, mOther), 'Grußzeile');
  mOther := SampleInfo;
  mOther.Hour := 10;
  Assert.IsFalse(TAtlasWelcomeHeaderFrame.SameInfo(SampleInfo, mOther), 'Stunde');
  mOther := SampleInfo;
  mOther.FirstName := 'Mia';
  Assert.IsFalse(TAtlasWelcomeHeaderFrame.SameInfo(SampleInfo, mOther), 'Name');
  mOther := SampleInfo;
  mOther.Version := '1.0.1';
  Assert.IsFalse(TAtlasWelcomeHeaderFrame.SameInfo(SampleInfo, mOther), 'Version');
  mOther := SampleInfo;
  mOther.Phase := TAtlasServerPhase.Stopped;
  Assert.IsFalse(TAtlasWelcomeHeaderFrame.SameInfo(SampleInfo, mOther), 'Phase');
  mOther := SampleInfo;
  mOther.Units := 43;
  Assert.IsFalse(TAtlasWelcomeHeaderFrame.SameInfo(SampleInfo, mOther), 'Units');
  mOther := SampleInfo;
  mOther.Indexing := True;
  Assert.IsFalse(TAtlasWelcomeHeaderFrame.SameInfo(SampleInfo, mOther), 'Indizierung');
  mOther := SampleInfo;
  mOther.Percent := 50;
  Assert.IsFalse(TAtlasWelcomeHeaderFrame.SameInfo(SampleInfo, mOther), 'Prozent');
end;

procedure TAtlasWelcomeHeaderTests.SameInfoLeavesHeaderAlone;
var
  mSaved: TAtlasLanguage;
  mHeader: TAtlasWelcomeHeaderFrame;
  mInfo: TAtlasWelcomeHeaderInfo;
begin
  mSaved := TAtlasStrings.Language;
  mHeader := TAtlasWelcomeHeaderFrame.Create(nil);
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mInfo := SampleInfo;
    mHeader.ShowInfo(mInfo);
    // Markierung: Ein zweites ShowInfo mit denselben Angaben darf den Kopf nicht anfassen.
    mHeader.InfoLabel.Caption := 'unberührt';
    mHeader.ShowInfo(mInfo);
    Assert.AreEqual('unberührt', mHeader.InfoLabel.Caption, 'gleiche Angaben: nichts neu gesetzt');
    mInfo.Units := 43;
    mHeader.ShowInfo(mInfo);
    Assert.AreEqual('Atlas 1.0.0 · Server läuft · 43 Units im Index', mHeader.InfoLabel.Caption, 'geändert: neu');
    // Nach Renew (Thema, Sprache, Einstellungen) setzt auch dasselbe ShowInfo alles neu.
    mHeader.InfoLabel.Caption := 'unberührt';
    mHeader.Renew;
    mHeader.ShowInfo(mInfo);
    Assert.AreEqual('Atlas 1.0.0 · Server läuft · 43 Units im Index', mHeader.InfoLabel.Caption, 'nach Renew');
  finally
    mHeader.Free;
    TAtlasStrings.Language := mSaved;
  end;
end;
procedure TAtlasWelcomeBoardTests.WarmUpFirstUse;
begin
  BoardPlacesSectionsInColumns;
end;
procedure TAtlasWelcomeBoardTests.ViewsCreateFramesWithId;
var
  mView: TAtlasWelcomeSectionFrame;
begin
  RegisterViews([TAtlasWelcomeIds.cState]);
  try
    Assert.IsTrue(TAtlasWelcomeViews.Exists('ATLAS.STATE'));
    Assert.IsFalse(TAtlasWelcomeViews.Exists(TAtlasWelcomeIds.cNews));
    Assert.IsNull(TAtlasWelcomeViews.CreateView(TAtlasWelcomeIds.cNews, nil));
    mView := TAtlasWelcomeViews.CreateView(TAtlasWelcomeIds.cState, nil);
    try
      Assert.IsNotNull(mView);
      Assert.AreEqual(TAtlasWelcomeIds.cState, mView.SectionId);
      Assert.IsTrue(mView.ShowTitle);
      Assert.AreEqual(TAtlasWelcomeSectionFrame.cTitleHeight + TAtlasWelcomeSectionFrame.cDefaultBodyHeight,
        mView.PreferredHeight);
      mView.ShowTitle := False;
      Assert.AreEqual(TAtlasWelcomeSectionFrame.cDefaultBodyHeight, mView.PreferredHeight);
    finally
      mView.Free;
    end;
    TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.cState);
    Assert.IsFalse(TAtlasWelcomeViews.Exists(TAtlasWelcomeIds.cState));
  finally
    TAtlasWelcomeViews.Release;
  end;
end;
procedure TAtlasWelcomeBoardTests.BoardPlacesSectionsInColumns;
var
  mHost: TForm;
  mBoard: TAtlasWelcomeBoardFrame;
  mLeft, mRight, mBelow: TAtlasWelcomeSectionFrame;
begin
  RegisterViews([TAtlasWelcomeIds.cContinue, TAtlasWelcomeIds.cProjects, TAtlasWelcomeIds.cState]);
  mHost := TForm.CreateNew(nil);
  try
    mHost.ClientWidth := 800;
    mHost.ClientHeight := 600;
    mBoard := TAtlasWelcomeBoardFrame.Create(mHost);
    mBoard.Parent := mHost;
    mBoard.Align := alClient;
    mBoard.Rebuild([Section(TAtlasWelcomeIds.cState, 10, TAtlasWelcomeColumn.Right),
      Section(TAtlasWelcomeIds.cContinue, 20, TAtlasWelcomeColumn.Left),
      Section(TAtlasWelcomeIds.cProjects, 30, TAtlasWelcomeColumn.Left),
      Section(TAtlasWelcomeIds.cNews, 40, TAtlasWelcomeColumn.Right)], TAtlasWelcomeLayout.Atlas, 2);
    Assert.AreEqual(2, Integer(Length(mBoard.Columns)));
    mLeft := mBoard.View(TAtlasWelcomeIds.cContinue);
    mBelow := mBoard.View(TAtlasWelcomeIds.cProjects);
    mRight := mBoard.View(TAtlasWelcomeIds.cState);
    Assert.IsNotNull(mLeft);
    Assert.IsNull(mBoard.View(TAtlasWelcomeIds.cNews), 'ohne Fabrik kein Frame');
    Assert.AreEqual('Titel ' + TAtlasWelcomeIds.cContinue, mLeft.Title);
    Assert.IsTrue(mLeft.ShowTitle);
    Assert.AreEqual(mLeft.Left, mBelow.Left, 'gleiche Spalte');
    Assert.IsTrue(mBelow.Top > mLeft.Top + mLeft.Height - 1, 'untereinander');
    Assert.IsTrue(mRight.Left > mLeft.Left + mLeft.Width - 1, 'rechte Spalte');
    Assert.AreEqual(mLeft.Top, mRight.Top);
    Assert.IsTrue(TTestSection(mLeft).Updates > 0, 'neuer Frame liest seinen Inhalt');
    // Eine Spalte (Fenster „Atlas-Start“): alles untereinander.
    mBoard.Rebuild([Section(TAtlasWelcomeIds.cState, 10, TAtlasWelcomeColumn.Right),
      Section(TAtlasWelcomeIds.cContinue, 20, TAtlasWelcomeColumn.Left)], TAtlasWelcomeLayout.Atlas, 1);
    Assert.AreEqual(mBoard.View(TAtlasWelcomeIds.cContinue).Left, mBoard.View(TAtlasWelcomeIds.cState).Left);
    Assert.IsTrue(mBoard.View(TAtlasWelcomeIds.cState).Top > mBoard.View(TAtlasWelcomeIds.cContinue).Top);
  finally
    mHost.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
procedure TAtlasWelcomeBoardTests.BoardKeepsAndDropsFrames;
var
  mHost: TForm;
  mBoard: TAtlasWelcomeBoardFrame;
  mKept: TAtlasWelcomeSectionFrame;
  mBefore: Integer;
begin
  RegisterViews([TAtlasWelcomeIds.cContinue, TAtlasWelcomeIds.cState]);
  // Wie in der IDE: Die Tafel hängt an einem Fenster.
  mHost := TForm.CreateNew(nil);
  mBoard := TAtlasWelcomeBoardFrame.Create(nil);
  try
    mBoard.Parent := mHost;
    mBoard.Rebuild([Section(TAtlasWelcomeIds.cContinue, 20, TAtlasWelcomeColumn.Left),
      Section(TAtlasWelcomeIds.cState, 10, TAtlasWelcomeColumn.Right)], TAtlasWelcomeLayout.Atlas, 2);
    mKept := mBoard.View(TAtlasWelcomeIds.cContinue);
    mBoard.Rebuild([Section(TAtlasWelcomeIds.cContinue, 20, TAtlasWelcomeColumn.Left)], TAtlasWelcomeLayout.Atlas, 2);
    Assert.AreSame(mBoard.View(TAtlasWelcomeIds.cContinue), mKept, 'sichtbarer Bereich behält seinen Frame');
    Assert.IsNull(mBoard.View(TAtlasWelcomeIds.cState), 'ausgeschalteter Bereich verschwindet');
    mBefore := TTestSection(mKept).Updates;
    mBoard.UpdateSection(TAtlasWelcomeIds.cContinue);
    Assert.AreEqual(mBefore + 1, TTestSection(mKept).Updates);
    mBoard.UpdateContent;
    Assert.AreEqual(mBefore + 2, TTestSection(mKept).Updates);
  finally
    mBoard.Free;
    mHost.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
/// <summary>Tafel mit drei Bereichen untereinander in einem niedrigen Fenster: Der Inhalt ist höher als der
/// Platz.</summary>
function TallBoard(AHost: TForm): TAtlasWelcomeBoardFrame;
begin
  RegisterViews([TAtlasWelcomeIds.cContinue, TAtlasWelcomeIds.cProjects, TAtlasWelcomeIds.cState]);
  AHost.ClientWidth := 400;
  AHost.ClientHeight := 160;
  Result := TAtlasWelcomeBoardFrame.Create(AHost);
  Result.Parent := AHost;
  Result.Align := alClient;
  Result.Rebuild([Section(TAtlasWelcomeIds.cContinue, 10, TAtlasWelcomeColumn.Left),
    Section(TAtlasWelcomeIds.cProjects, 20, TAtlasWelcomeColumn.Left),
    Section(TAtlasWelcomeIds.cState, 30, TAtlasWelcomeColumn.Left)], TAtlasWelcomeLayout.Atlas, 1);
  // Ohne gezeigtes Fenster: Bereich der Leiste mit Fenster rechnen lassen.
  Result.ScrollBox.HandleNeeded;
  Result.ScrollBox.Realign;
end;
procedure TAtlasWelcomeBoardTests.WheelScrollsPageFromSectionAndHeader;
var
  mHost: TForm;
  mBoard: TAtlasWelcomeBoardFrame;
  mOther: TPanel;
begin
  mHost := TForm.CreateNew(nil);
  try
    mBoard := TallBoard(mHost);
    Assert.IsTrue(mBoard.ScrollBox.VertScrollBar.IsScrollBarVisible, 'Überlänge zeigt die Leiste');
    Assert.AreEqual(0, mBoard.ScrollBox.VertScrollBar.Position);
    Assert.IsFalse(mBoard.Scroller.ScrollWheel(mBoard.View(TAtlasWelcomeIds.cContinue), 120), 'oben geht es nicht weiter');
    Assert.IsTrue(mBoard.Scroller.ScrollWheel(mBoard.View(TAtlasWelcomeIds.cContinue).TitleLabel, -120),
      'über einem Bereich scrollt die Seite');
    Assert.IsTrue(mBoard.ScrollBox.VertScrollBar.Position > 0);
    Assert.IsTrue(mBoard.Scroller.ScrollWheel(mBoard.Header, 3 * 120), 'über dem Kopf auch');
    Assert.AreEqual(0, mBoard.ScrollBox.VertScrollBar.Position);
    mOther := TPanel.Create(mHost);
    mOther.Parent := mHost;
    Assert.IsFalse(mBoard.Contains(mOther));
    Assert.IsFalse(mBoard.Scroller.ScrollWheel(mOther, -120), 'außerhalb der Tafel nicht');
    Assert.IsFalse(mBoard.Scroller.ScrollWheel(nil, -120));
  finally
    mHost.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
procedure TAtlasWelcomeBoardTests.WheelScrollsInnerListFirst;
var
  mHost: TForm;
  mBoard: TAtlasWelcomeBoardFrame;
  mInner: TScrollBox;
  mContent: TPanel;
  mBar: TControlScrollBar;
begin
  mHost := TForm.CreateNew(nil);
  try
    mBoard := TallBoard(mHost);
    // Wie „Neu in Atlas“: eine eigene Scrollbox im Bereich.
    mInner := TScrollBox.Create(mHost);
    mInner.Parent := mBoard.View(TAtlasWelcomeIds.cContinue);
    mInner.BorderStyle := bsNone;
    mInner.SetBounds(0, 0, 200, 40);
    mContent := TPanel.Create(mHost);
    mContent.Parent := mInner;
    mContent.SetBounds(0, 0, 180, 400);
    mInner.HandleNeeded;
    mInner.Realign;
    mBar := mInner.VertScrollBar;
    Assert.IsTrue(mBar.IsScrollBarVisible, 'innere Liste mit Überlänge');
    Assert.IsTrue(mBoard.Scroller.ScrollWheel(mContent, -120));
    Assert.IsTrue(mBar.Position > 0, 'die innere Liste scrollt zuerst');
    Assert.AreEqual(0, mBoard.ScrollBox.VertScrollBar.Position, 'die Seite bleibt stehen');
    // Am Ende der Liste geht das Rad an die Seite.
    mBar.Position := mBar.Range;
    Assert.IsTrue(mBoard.Scroller.ScrollWheel(mContent, -120));
    Assert.IsTrue(mBoard.ScrollBox.VertScrollBar.Position > 0, 'danach die Seite');
  finally
    mHost.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
procedure TAtlasWelcomeBoardTests.KeysScrollPage;
var
  mHost: TForm;
  mBoard: TAtlasWelcomeBoardFrame;
  mBar: TControlScrollBar;
  mPage: Integer;
begin
  mHost := TForm.CreateNew(nil);
  try
    mBoard := TallBoard(mHost);
    mBar := mBoard.ScrollBox.VertScrollBar;
    Assert.IsFalse(mBoard.Scroller.ScrollKey(TAtlasWelcomeScrollKey.PageUp), 'oben bleibt Bild auf ohne Wirkung');
    Assert.IsTrue(mBoard.Scroller.ScrollKey(TAtlasWelcomeScrollKey.PageDown));
    mPage := mBar.Position;
    Assert.IsTrue(mPage > 0);
    Assert.IsTrue(mBoard.Scroller.ScrollKey(TAtlasWelcomeScrollKey.Bottom));
    Assert.IsTrue(mBar.Position >= mPage);
    Assert.IsFalse(mBoard.Scroller.ScrollKey(TAtlasWelcomeScrollKey.Bottom), 'am Ende bleibt es stehen');
    Assert.IsFalse(mBoard.Scroller.ScrollKey(TAtlasWelcomeScrollKey.PageDown));
    Assert.IsTrue(mBoard.Scroller.ScrollKey(TAtlasWelcomeScrollKey.Top));
    Assert.AreEqual(0, mBar.Position);
  finally
    mHost.Free;
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
  Assert.AreEqual(Ord(TAtlasWelcomeScrollKey.PageUp), Ord(TAtlasWelcomeBoardScroller.ScrollKeyOf(VK_PRIOR, [])));
  Assert.AreEqual(Ord(TAtlasWelcomeScrollKey.PageDown), Ord(TAtlasWelcomeBoardScroller.ScrollKeyOf(VK_NEXT, [])));
  Assert.AreEqual(Ord(TAtlasWelcomeScrollKey.Top), Ord(TAtlasWelcomeBoardScroller.ScrollKeyOf(VK_HOME, [ssCtrl])));
  Assert.AreEqual(Ord(TAtlasWelcomeScrollKey.Bottom), Ord(TAtlasWelcomeBoardScroller.ScrollKeyOf(VK_END, [])));
  Assert.AreEqual(Ord(TAtlasWelcomeScrollKey.None), Ord(TAtlasWelcomeBoardScroller.ScrollKeyOf(VK_NEXT, [ssAlt])),
    'Alt bleibt bei der IDE');
  Assert.AreEqual(Ord(TAtlasWelcomeScrollKey.None), Ord(TAtlasWelcomeBoardScroller.ScrollKeyOf(Ord('A'), [])));
  mEdit := TEdit.Create(nil);
  mList := TListBox.Create(nil);
  mCombo := TComboBox.Create(nil);
  mPanel := TPanel.Create(nil);
  try
    Assert.IsTrue(TAtlasWelcomeBoardScroller.OwnsScrollKeys(mEdit), 'Eingabefeld');
    Assert.IsTrue(TAtlasWelcomeBoardScroller.OwnsScrollKeys(mList), 'Liste');
    Assert.IsTrue(TAtlasWelcomeBoardScroller.OwnsScrollKeys(mCombo), 'Auswahlfeld');
    Assert.IsFalse(TAtlasWelcomeBoardScroller.OwnsScrollKeys(mPanel));
    Assert.IsFalse(TAtlasWelcomeBoardScroller.OwnsScrollKeys(nil));
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
