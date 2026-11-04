unit Atlas.UI.Welcome.Projects.Tests;

// Tests des Projektbereichs der Willkommensseite.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeProjectsFrameTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure PillTextsFollowKind;
    [Test]
    procedure RowsSetHeightAndAskForRefresh;
    [Test]
    procedure DetailAndHintNameState;
    [Test]
    procedure ClicksReachSource;
    [Test]
    procedure HitTestFindsRows;
    /// <summary>Mit Projektverlauf (#758): Klick wählt, Doppelklick und „Öffnen“ öffnen, rote Marke springt.
    /// </summary>
    [Test]
    procedure ClickSelectsForHistory;
    /// <summary>Schnellaktionen (#764): Knöpfe je Zeile, Tasten ohne Maus, Enter öffnet, aus = keine Knöpfe.
    /// </summary>
    [Test]
    procedure QuickActionsInRows;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Strings,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Welcome.Projects,
  Atlas.UI.Welcome.Projects,
  Atlas.Core.Welcome.QuickActions,
  Atlas.UI.Welcome.QuickActions,
  Atlas.UI.Welcome.QuickActions.Tests,
  Atlas.UI.Welcome.TestSupport;


type
  /// <summary>Quelle des Bereichs „Projekte“ für die Tests; merkt sich die Aufrufe.</summary>
  TFakeProjects = class(TInterfacedObject, IAtlasProjectsSource)
  public
    FEntries: TAtlasProjectEntries;
    Calls: TArray<string>;
    function Entries: TAtlasProjectEntries;
    procedure Open(const AProject: string);
    procedure OpenAt(const AProject: string; const ATarget: TAtlasProjectLocation);
    procedure OpenFolder(const AProject: string);
    procedure CreateBranch(const AProject: string);
    procedure ShowWorkingCopies(const AProject: string);
    function WorkingCopies: Boolean;
    procedure Remove(const AProject: string);
    procedure Shown;
    function Selectable: Boolean;
    procedure Select(const AProject: string);
    function Selected: string;
  public
    /// <summary>Projektverlauf an (#758): Klick wählt.</summary>
    FSelectable: Boolean;
    /// <summary>vcs.externals.show (#1292).</summary>
    FWorkingCopies: Boolean;
    FSelected: string;
  end;

{ TFakeProjects }

function TFakeProjects.Entries: TAtlasProjectEntries;
begin
  Result := FEntries;
end;
procedure TFakeProjects.Open(const AProject: string);
begin
  Calls := Calls + ['open ' + AProject];
end;
procedure TFakeProjects.OpenAt(const AProject: string; const ATarget: TAtlasProjectLocation);
begin
  Calls := Calls + [Format('openAt %s %s %d', [AProject, ATarget.FileName, ATarget.Line])];
end;
procedure TFakeProjects.OpenFolder(const AProject: string);
begin
  Calls := Calls + ['folder ' + AProject];
end;
procedure TFakeProjects.CreateBranch(const AProject: string);
begin
  Calls := Calls + ['branch ' + AProject];
end;
procedure TFakeProjects.ShowWorkingCopies(const AProject: string);
begin
  Calls := Calls + ['copies ' + AProject];
end;
function TFakeProjects.WorkingCopies: Boolean;
begin
  Result := FWorkingCopies;
end;
procedure TFakeProjects.Remove(const AProject: string);
begin
  Calls := Calls + ['remove ' + AProject];
end;
procedure TFakeProjects.Shown;
begin
  Calls := Calls + ['shown'];
end;
function TFakeProjects.Selectable: Boolean;
begin
  Result := FSelectable;
end;
procedure TFakeProjects.Select(const AProject: string);
begin
  Calls := Calls + ['select ' + AProject];
  FSelected := AProject;
end;
function TFakeProjects.Selected: string;
begin
  Result := FSelected;
end;
/// <summary>Projekt auf main; mit AErrors &gt; 0 ein fehlgeschlagener Build mit Sprungziel.</summary>
function ProjectEntry(const AProject: string; AErrors: Integer): TAtlasProjectEntry;
begin
  Result := Default(TAtlasProjectEntry);
  Result.HasSummary := True;
  Result.Summary := TAtlasProjectSummary.Create(AProject);
  Result.Summary.Vcs.Known := True;
  Result.Summary.Vcs.Kind := 'git';
  Result.Summary.Vcs.Branch := 'main';
  Result.Summary.Vcs.Changed := 0;
  Result.Summary.Vcs.At := EncodeDate(2026, 10, 14) + EncodeTime(17, 45, 0, 0);
  Result.Summary.Build.Known := True;
  Result.Summary.Build.Kind := 'build';
  Result.Summary.Build.Succeeded := AErrors = 0;
  Result.Summary.Build.Errors := AErrors;
  if AErrors > 0 then
  begin
    Result.Summary.Build.First.FileName := 'C:\P\Main.pas';
    Result.Summary.Build.First.Line := 12;
    Result.Summary.Build.First.Code := 'E2003';
  end;
end;
function ProjectsFrame(AHost: TForm; const ASource: IAtlasProjectsSource): TAtlasWelcomeProjectsFrame;
begin
  Result := TAtlasWelcomeProjectsFrame.Create(AHost);
  Result.Parent := AHost;
  Result.Width := 600;
  Result.Source := ASource;
end;
{ TAtlasWelcomeProjectsFrameTests }

procedure TAtlasWelcomeProjectsFrameTests.WarmUpFirstUse;
begin
  RowsSetHeightAndAskForRefresh;
end;
procedure TAtlasWelcomeProjectsFrameTests.PillTextsFollowKind;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Build 0/0/0', TAtlasWelcomeProjectsFrame.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.Build, TAtlasProjectPillLevel.Good, 0, 0, 0)));
    Assert.AreEqual('Build 0/3/1', TAtlasWelcomeProjectsFrame.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.Build, TAtlasProjectPillLevel.Warning, 0, 3, 1)));
    Assert.AreEqual('2 Fehler', TAtlasWelcomeProjectsFrame.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.BuildErrors, TAtlasProjectPillLevel.Error, 2, 0, 0)));
    Assert.AreEqual('Prüfung: 1 Fehler', TAtlasWelcomeProjectsFrame.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.CheckErrors, TAtlasProjectPillLevel.Error, 1, 0, 0)));
    Assert.AreEqual('3 geändert', TAtlasWelcomeProjectsFrame.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.Changes, TAtlasProjectPillLevel.Warning, 3, 0, 0)));
    Assert.AreEqual(#$2191'1 '#$2193'2', TAtlasWelcomeProjectsFrame.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.Sync, TAtlasProjectPillLevel.Neutral, 1, 2, 0)));
    Assert.AreEqual('5 neue Treffer', TAtlasWelcomeProjectsFrame.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.Rules, TAtlasProjectPillLevel.Warning, 5, 0, 0)));
    Assert.AreNotEqual(Integer(TAtlasWelcomeProjectsFrame.PillColor(TAtlasProjectPillLevel.Good)),
      Integer(TAtlasWelcomeProjectsFrame.PillColor(TAtlasProjectPillLevel.Error)));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;
procedure TAtlasWelcomeProjectsFrameTests.RowsSetHeightAndAskForRefresh;
var
  Host: TForm;
  Fake: TFakeProjects;
  Source: IAtlasProjectsSource;
  Frame: TAtlasWelcomeProjectsFrame;
  Empty, Two: Integer;
begin
  Fake := TFakeProjects.Create;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := ProjectsFrame(Host, Source);
    Assert.AreEqual(1, Integer(Length(Fake.Calls)), 'beim Anzeigen frisch abfragen');
    Assert.AreEqual('shown', Fake.Calls[0]);
    Assert.AreEqual(0, Integer(Length(Frame.Entries)));
    Empty := Frame.PreferredHeight;
    Fake.FEntries := [ProjectEntry('C:\P\Eins.dproj', 0), ProjectEntry('C:\P\Zwei.dproj', 2)];
    Frame.UpdateContent;
    Assert.AreEqual(2, Integer(Length(Frame.Entries)));
    Two := Frame.PreferredHeight;
    Assert.IsTrue(Two > Empty, Format('leer %d, zwei Zeilen %d', [Empty, Two]));
    Assert.AreEqual(1, Integer(Length(Fake.Calls)), 'Neu lesen fragt nicht erneut ab');
  finally
    Host.Free;
  end;
end;
procedure TAtlasWelcomeProjectsFrameTests.DetailAndHintNameState;
var
  Saved: TAtlasLanguage;
  Item: TAtlasProjectEntry;
  Hint, Detail: string;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Item := ProjectEntry('C:\P\Zwei.dproj', 2);
    Detail := TAtlasWelcomeProjectsFrame.DetailText(Item);
    Assert.Contains(Detail, 'C:\P\Zwei.dproj');
    Assert.Contains(Detail, 'Stand vom', 'gespeicherter Stand');
    Item.VcsFresh := True;
    Assert.IsFalse(TAtlasWelcomeProjectsFrame.DetailText(Item).Contains('Stand vom'), 'frisch abgefragt');
    Hint := TAtlasWelcomeProjectsFrame.HintFor(Item);
    Assert.Contains(Hint, 'main');
    Assert.Contains(Hint, '2 Fehler');
    Assert.Contains(Hint, 'Main.pas (12)');
    Assert.Contains(Hint, 'E2003');
    Item.Summary.Build := TAtlasProjectBuild.Empty;
    Assert.Contains(TAtlasWelcomeProjectsFrame.HintFor(Item),
      TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeProjectsHintNoBuild));
    Assert.AreEqual('', TAtlasWelcomeProjectsFrame.LocalText(0));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;
procedure TAtlasWelcomeProjectsFrameTests.ClicksReachSource;
var
  Host: TForm;
  Fake: TFakeProjects;
  Source: IAtlasProjectsSource;
  Frame: TAtlasWelcomeProjectsFrame;
  Hit: TAtlasProjectsHit;
begin
  Fake := TFakeProjects.Create;
  Source := Fake;
  Fake.FEntries := [ProjectEntry('C:\P\Eins.dproj', 0), ProjectEntry('C:\P\Zwei.dproj', 2)];
  Host := TForm.CreateNew(nil);
  try
    Frame := ProjectsFrame(Host, Source);
    Fake.Calls := nil;
    Hit.Row := 0;
    Hit.Pill := -1;
    Frame.ClickAt(Hit);
    // Rote Marke: Projekt öffnen und zur ersten Meldung springen.
    Hit.Row := 1;
    Hit.Pill := 0;
    Frame.ClickAt(Hit);
    // Grüne Marke ist kein Sprungziel: öffnet nur das Projekt.
    Hit.Row := 0;
    Hit.Pill := 0;
    Frame.ClickAt(Hit);
    Frame.MenuRow := 1;
    Frame.OpenFolderItem.Click;
    Frame.CreateBranchItem.Click;
    Frame.RemoveItem.Click;
    Frame.WorkingCopiesItem.Click;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(7, Integer(Length(Fake.Calls)));
    Assert.AreEqual('open C:\P\Eins.dproj', Fake.Calls[0]);
    Assert.AreEqual('openAt C:\P\Zwei.dproj C:\P\Main.pas 12', Fake.Calls[1]);
    Assert.AreEqual('open C:\P\Eins.dproj', Fake.Calls[2]);
    Assert.AreEqual('folder C:\P\Zwei.dproj', Fake.Calls[3]);
    // „Branch anlegen …“ (#1288) geht an die Quelle; dort öffnet der Dialog.
    Assert.AreEqual('branch C:\P\Zwei.dproj', Fake.Calls[4]);
    Assert.AreEqual('remove C:\P\Zwei.dproj', Fake.Calls[5]);
    // „Arbeitskopien …“ (#1292) ebenso; sichtbar nur mit vcs.externals.show.
    Assert.AreEqual('copies C:\P\Zwei.dproj', Fake.Calls[6]);
    Frame.Menu.OnPopup(Frame.Menu);
    Assert.IsFalse(Frame.WorkingCopiesItem.Visible);
    Fake.FWorkingCopies := True;
    Frame.Menu.OnPopup(Frame.Menu);
    Assert.IsTrue(Frame.WorkingCopiesItem.Visible);
  finally
    Host.Free;
  end;
end;
procedure TAtlasWelcomeProjectsFrameTests.HitTestFindsRows;
var
  Host: TForm;
  Fake: TFakeProjects;
  Source: IAtlasProjectsSource;
  Frame: TAtlasWelcomeProjectsFrame;
  Row: Integer;
begin
  Fake := TFakeProjects.Create;
  Source := Fake;
  Fake.FEntries := [ProjectEntry('C:\P\Eins.dproj', 0), ProjectEntry('C:\P\Zwei.dproj', 0)];
  Host := TForm.CreateNew(nil);
  try
    Frame := ProjectsFrame(Host, Source);
    Row := Frame.ScaleValue(TAtlasWelcomeProjectsFrame.RowHeight);
    Assert.AreEqual(0, Frame.HitTest(20, Row div 2).Row);
    Assert.AreEqual(1, Frame.HitTest(20, Row + Row div 2).Row);
    Assert.AreEqual(-1, Frame.HitTest(20, 5 * Row).Row, 'unter der letzten Zeile');
  finally
    Host.Free;
  end;
end;
procedure TAtlasWelcomeProjectsFrameTests.QuickActionsInRows;
var
  Host: TForm;
  Fake: TFakeProjects;
  Source: IAtlasProjectsSource;
  Quick: TAtlasFakeQuickActions;
  QuickSource: IAtlasQuickActionsSource;
  Frame: TAtlasWelcomeProjectsFrame;
begin
  Fake := TFakeProjects.Create;
  Source := Fake;
  Quick := TAtlasFakeQuickActions.Create;
  QuickSource := Quick;
  Fake.FEntries := [ProjectEntry('C:\P\Eins.dproj', 0), ProjectEntry('C:\P\Zwei.dproj', 0)];
  Host := TForm.CreateNew(nil);
  try
    Frame := ProjectsFrame(Host, Source);
    Frame.QuickActions := QuickSource;
    Assert.AreEqual(7, Integer(Length(Frame.Quick.ButtonsOf(0))), 'Vorgabe mit Aufgaben (#900)');
    // items ohne console: nur dieser Knopf fehlt.
    Quick.Items := TAtlasWelcomeQuickActions.ParseItems('build,tests,run,pull,folder');
    Frame.UpdateContent;
    Assert.AreEqual(5, Integer(Length(Frame.Quick.ButtonsOf(0))));
    Assert.AreEqual(-1, TAtlasWelcomeQuickActions.IndexOf(Frame.Quick.ButtonsOf(0), TAtlasQuickAction.Console));
    Fake.Calls := nil;
    // Ohne Maus: Pfeil ab, Strg+B, Strg+T, Pos1 und Enter öffnet.
    Quick.FTests := ['C:\P\Tests\Zwei.Tests.dproj'];
    Assert.IsTrue(Frame.Quick.HandleKey(VK_DOWN, []));
    Assert.IsTrue(Frame.Quick.HandleKey(Ord('B'), [ssCtrl]));
    Assert.IsTrue(Frame.Quick.HandleKey(Ord('T'), [ssCtrl]));
    Assert.IsTrue(Frame.Quick.HandleKey(VK_HOME, []));
    Assert.IsTrue(Frame.Quick.HandleKey(VK_RETURN, []));
    Assert.AreEqual(0, Integer(Length(Quick.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(2, Integer(Length(Quick.Calls)));
    Assert.AreEqual('build C:\P\Zwei.dproj', Quick.Calls[0]);
    Assert.AreEqual('tests C:\P\Zwei.dproj', Quick.Calls[1]);
    Assert.AreEqual(1, Integer(Length(Fake.Calls)));
    Assert.AreEqual('open C:\P\Zwei.dproj', Fake.Calls[0]);
    // Ausgeschaltet bzw. ohne Quelle: keine Knöpfe, Tasten bleiben bei der IDE.
    Quick.IsOn := False;
    Frame.UpdateContent;
    Assert.AreEqual(0, Integer(Length(Frame.Quick.ButtonsOf(0))));
    Assert.IsFalse(Frame.Quick.HandleKey(Ord('B'), [ssCtrl]));
    Frame.QuickActions := nil;
    Assert.IsFalse(Frame.Quick.Active);
  finally
    Host.Free;
  end;
end;
procedure TAtlasWelcomeProjectsFrameTests.ClickSelectsForHistory;
var
  Host: TForm;
  Fake: TFakeProjects;
  Source: IAtlasProjectsSource;
  Frame: TAtlasWelcomeProjectsFrame;
  Hit: TAtlasProjectsHit;
begin
  Fake := TFakeProjects.Create;
  Source := Fake;
  Fake.FEntries := [ProjectEntry('C:\P\Eins.dproj', 0), ProjectEntry('C:\P\Zwei.dproj', 2)];
  Host := TForm.CreateNew(nil);
  try
    Frame := ProjectsFrame(Host, Source);
    Assert.AreEqual(-1, Frame.SelectedRow, 'ohne Projektverlauf keine Auswahl');
    Hit.Row := 0;
    Hit.Pill := -1;
    Fake.Calls := nil;
    Frame.DoubleClickAt(Hit);
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'ohne Auswahl öffnet schon der Klick');
    Fake.FSelectable := True;
    Assert.AreEqual(0, Frame.SelectedRow, 'ohne Auswahl das oberste');
    Hit.Row := 1;
    Frame.ClickAt(Hit);
    // Rote Marke springt weiter.
    Hit.Pill := 0;
    Frame.ClickAt(Hit);
    Hit.Row := 0;
    Hit.Pill := -1;
    Frame.DoubleClickAt(Hit);
    Frame.MenuRow := 1;
    Frame.OpenItem.Click;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(4, Integer(Length(Fake.Calls)));
    Assert.AreEqual('select C:\P\Zwei.dproj', Fake.Calls[0]);
    Assert.AreEqual('openAt C:\P\Zwei.dproj C:\P\Main.pas 12', Fake.Calls[1]);
    Assert.AreEqual('open C:\P\Eins.dproj', Fake.Calls[2]);
    Assert.AreEqual('open C:\P\Zwei.dproj', Fake.Calls[3]);
    Assert.AreEqual(1, Frame.SelectedRow);
    Fake.FSelected := 'c:/p/eins.DPROJ';
    Assert.AreEqual(0, Frame.SelectedRow, 'Schreibweise egal');
    Assert.Contains(TAtlasWelcomeProjectsFrame.HintFor(Fake.FEntries[0], True),
      TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeProjectsHintSelect));
    Assert.Contains(TAtlasWelcomeProjectsFrame.HintFor(Fake.FEntries[0], False),
      TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeProjectsHintClick));
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeProjectsFrameTests);

end.
