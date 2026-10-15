unit Atlas.UI.Welcome.Tests;

// Oberfläche der Atlas-Willkommensseite (#753): Texte im Kopf (Grußzeile,
// Kurzstatus, Tausendertrennzeichen je Sprache), Fabriken der Bereiche und
// der Frame „Atlas“ mit Kopf und Bereichen in Spalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
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
  TAtlasWelcomeBoardTests = class
  public
    [Test]
    procedure ViewsCreateFramesWithId;
    [Test]
    procedure BoardPlacesSectionsInColumns;
    [Test]
    procedure BoardKeepsAndDropsFrames;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.Core.Status.Lines,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Layout,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.Header,
  Atlas.UI.Welcome.Board;

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
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.WelcomeHeaderTitle), Header.GreetingLabel.Caption);
  finally
    Header.Free;
    TAtlasStrings.Language := Saved;
  end;
end;

{ TAtlasWelcomeBoardTests }

type
  TTestSection = class(TAtlasWelcomeSectionFrame)
  public
    Updates: Integer;
    procedure UpdateContent; override;
  end;

procedure TTestSection.UpdateContent;
begin
  Inc(Updates);
  inherited;
end;

procedure RegisterViews(const AIds: array of string);
var
  Id: string;
begin
  for Id in AIds do
    TAtlasWelcomeViews.Register(Id,
      function(AOwner: TComponent): TAtlasWelcomeSectionFrame
      begin
        Result := TTestSection.Create(AOwner);
      end);
end;

function Section(const AId: string; AOrder: Integer; AColumn: TAtlasWelcomeColumn): TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(AId, 'Titel ' + AId, AOrder, AColumn, nil);
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
  Board: TAtlasWelcomeBoardFrame;
  Kept: TAtlasWelcomeSectionFrame;
  Before: Integer;
begin
  RegisterViews([TAtlasWelcomeIds.Continue, TAtlasWelcomeIds.State]);
  Board := TAtlasWelcomeBoardFrame.Create(nil);
  try
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
    TAtlasWelcomeViews.Release;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeHeaderTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeBoardTests);

end.
