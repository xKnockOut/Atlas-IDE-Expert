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
  Atlas.UI.Welcome.QuickActions.Tests;


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
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Build 0/0/0', TAtlasProjectsTexts.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.Build, TAtlasProjectPillLevel.Good, 0, 0, 0)));
    Assert.AreEqual('Build 0/3/1', TAtlasProjectsTexts.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.Build, TAtlasProjectPillLevel.Warning, 0, 3, 1)));
    Assert.AreEqual('2 Fehler', TAtlasProjectsTexts.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.BuildErrors, TAtlasProjectPillLevel.Error, 2, 0, 0)));
    Assert.AreEqual('Prüfung: 1 Fehler', TAtlasProjectsTexts.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.CheckErrors, TAtlasProjectPillLevel.Error, 1, 0, 0)));
    Assert.AreEqual('3 geändert', TAtlasProjectsTexts.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.Changes, TAtlasProjectPillLevel.Warning, 3, 0, 0)));
    Assert.AreEqual(#$2191'1 '#$2193'2', TAtlasProjectsTexts.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.Sync, TAtlasProjectPillLevel.Neutral, 1, 2, 0)));
    Assert.AreEqual('5 neue Treffer', TAtlasProjectsTexts.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.Rules, TAtlasProjectPillLevel.Warning, 5, 0, 0)));
    Assert.AreNotEqual(Integer(TAtlasProjectsTexts.PillColor(TAtlasProjectPillLevel.Good)),
      Integer(TAtlasProjectsTexts.PillColor(TAtlasProjectPillLevel.Error)));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;
procedure TAtlasWelcomeProjectsFrameTests.RowsSetHeightAndAskForRefresh;
var
  mHost: TForm;
  mFake: TFakeProjects;
  mSource: IAtlasProjectsSource;
  mFrame: TAtlasWelcomeProjectsFrame;
  mEmpty, mTwo: Integer;
begin
  mFake := TFakeProjects.Create;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := ProjectsFrame(mHost, mSource);
    Assert.AreEqual(1, Integer(Length(mFake.Calls)), 'beim Anzeigen frisch abfragen');
    Assert.AreEqual('shown', mFake.Calls[0]);
    Assert.AreEqual(0, Integer(Length(mFrame.Entries)));
    mEmpty := mFrame.PreferredHeight;
    mFake.FEntries := [ProjectEntry('C:\P\Eins.dproj', 0), ProjectEntry('C:\P\Zwei.dproj', 2)];
    mFrame.UpdateContent;
    Assert.AreEqual(2, Integer(Length(mFrame.Entries)));
    mTwo := mFrame.PreferredHeight;
    Assert.IsTrue(mTwo > mEmpty, Format('leer %d, zwei Zeilen %d', [mEmpty, mTwo]));
    Assert.AreEqual(1, Integer(Length(mFake.Calls)), 'Neu lesen fragt nicht erneut ab');
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeProjectsFrameTests.DetailAndHintNameState;
var
  mSaved: TAtlasLanguage;
  mItem: TAtlasProjectEntry;
  mHint, mDetail: string;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mItem := ProjectEntry('C:\P\Zwei.dproj', 2);
    mDetail := TAtlasProjectsTexts.DetailText(mItem);
    Assert.Contains(mDetail, 'C:\P\Zwei.dproj');
    Assert.Contains(mDetail, 'Stand vom', 'gespeicherter Stand');
    mItem.VcsFresh := True;
    Assert.IsFalse(TAtlasProjectsTexts.DetailText(mItem).Contains('Stand vom'), 'frisch abgefragt');
    mHint := TAtlasProjectsTexts.HintFor(mItem);
    Assert.Contains(mHint, 'main');
    Assert.Contains(mHint, '2 Fehler');
    Assert.Contains(mHint, 'Main.pas (12)');
    Assert.Contains(mHint, 'E2003');
    mItem.Summary.Build := TAtlasProjectBuild.Empty;
    Assert.Contains(TAtlasProjectsTexts.HintFor(mItem),
      TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeProjectsHintNoBuild));
    Assert.AreEqual('', TAtlasProjectsTexts.LocalText(0));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;
procedure TAtlasWelcomeProjectsFrameTests.ClicksReachSource;
var
  mHost: TForm;
  mFake: TFakeProjects;
  mSource: IAtlasProjectsSource;
  mFrame: TAtlasWelcomeProjectsFrame;
  mHit: TAtlasProjectsHit;
begin
  mFake := TFakeProjects.Create;
  mSource := mFake;
  mFake.FEntries := [ProjectEntry('C:\P\Eins.dproj', 0), ProjectEntry('C:\P\Zwei.dproj', 2)];
  mHost := TForm.CreateNew(nil);
  try
    mFrame := ProjectsFrame(mHost, mSource);
    mFake.Calls := nil;
    mHit.Row := 0;
    mHit.Pill := -1;
    mFrame.ClickAt(mHit);
    // Rote Marke: Projekt öffnen und zur ersten Meldung springen.
    mHit.Row := 1;
    mHit.Pill := 0;
    mFrame.ClickAt(mHit);
    // Grüne Marke ist kein Sprungziel: öffnet nur das Projekt.
    mHit.Row := 0;
    mHit.Pill := 0;
    mFrame.ClickAt(mHit);
    mFrame.Menu.Row := 1;
    mFrame.Menu.OpenFolderItem.Click;
    mFrame.Menu.CreateBranchItem.Click;
    mFrame.Menu.RemoveItem.Click;
    mFrame.Menu.WorkingCopiesItem.Click;
    Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(7, Integer(Length(mFake.Calls)));
    Assert.AreEqual('open C:\P\Eins.dproj', mFake.Calls[0]);
    Assert.AreEqual('openAt C:\P\Zwei.dproj C:\P\Main.pas 12', mFake.Calls[1]);
    Assert.AreEqual('open C:\P\Eins.dproj', mFake.Calls[2]);
    Assert.AreEqual('folder C:\P\Zwei.dproj', mFake.Calls[3]);
    // „Branch anlegen …“ (#1288) geht an die Quelle; dort öffnet der Dialog.
    Assert.AreEqual('branch C:\P\Zwei.dproj', mFake.Calls[4]);
    Assert.AreEqual('remove C:\P\Zwei.dproj', mFake.Calls[5]);
    // „Arbeitskopien …“ (#1292) ebenso; sichtbar nur mit vcs.externals.show.
    Assert.AreEqual('copies C:\P\Zwei.dproj', mFake.Calls[6]);
    mFrame.Menu.OnPopup(mFrame.Menu);
    Assert.IsFalse(mFrame.Menu.WorkingCopiesItem.Visible);
    mFake.FWorkingCopies := True;
    mFrame.Menu.OnPopup(mFrame.Menu);
    Assert.IsTrue(mFrame.Menu.WorkingCopiesItem.Visible);
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeProjectsFrameTests.HitTestFindsRows;
var
  mHost: TForm;
  mFake: TFakeProjects;
  mSource: IAtlasProjectsSource;
  mFrame: TAtlasWelcomeProjectsFrame;
  mRow: Integer;
begin
  mFake := TFakeProjects.Create;
  mSource := mFake;
  mFake.FEntries := [ProjectEntry('C:\P\Eins.dproj', 0), ProjectEntry('C:\P\Zwei.dproj', 0)];
  mHost := TForm.CreateNew(nil);
  try
    mFrame := ProjectsFrame(mHost, mSource);
    mRow := mFrame.ScaleValue(TAtlasWelcomeProjectsFrame.cRowHeight);
    Assert.AreEqual(0, mFrame.HitTest(20, mRow div 2).Row);
    Assert.AreEqual(1, mFrame.HitTest(20, mRow + mRow div 2).Row);
    Assert.AreEqual(-1, mFrame.HitTest(20, 5 * mRow).Row, 'unter der letzten Zeile');
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeProjectsFrameTests.QuickActionsInRows;
var
  mHost: TForm;
  mFake: TFakeProjects;
  mSource: IAtlasProjectsSource;
  mQuick: TAtlasFakeQuickActions;
  mQuickSource: IAtlasQuickActionsSource;
  mFrame: TAtlasWelcomeProjectsFrame;
begin
  mFake := TFakeProjects.Create;
  mSource := mFake;
  mQuick := TAtlasFakeQuickActions.Create;
  mQuickSource := mQuick;
  mFake.FEntries := [ProjectEntry('C:\P\Eins.dproj', 0), ProjectEntry('C:\P\Zwei.dproj', 0)];
  mHost := TForm.CreateNew(nil);
  try
    mFrame := ProjectsFrame(mHost, mSource);
    mFrame.QuickActions := mQuickSource;
    Assert.AreEqual(7, Integer(Length(mFrame.Quick.ButtonsOf(0))), 'Vorgabe mit Aufgaben (#900)');
    // items ohne console: nur dieser Knopf fehlt.
    mQuick.Items := TAtlasWelcomeQuickActions.ParseItems('build,tests,run,pull,folder');
    mFrame.UpdateContent;
    Assert.AreEqual(5, Integer(Length(mFrame.Quick.ButtonsOf(0))));
    Assert.AreEqual(-1, TAtlasWelcomeQuickActions.IndexOf(mFrame.Quick.ButtonsOf(0), TAtlasQuickAction.Console));
    mFake.Calls := nil;
    // Ohne Maus: Pfeil ab, Strg+B, Strg+T, Pos1 und Enter öffnet.
    mQuick.FTests := ['C:\P\Tests\Zwei.Tests.dproj'];
    Assert.IsTrue(mFrame.Quick.HandleKey(VK_DOWN, []));
    Assert.IsTrue(mFrame.Quick.HandleKey(Ord('B'), [ssCtrl]));
    Assert.IsTrue(mFrame.Quick.HandleKey(Ord('T'), [ssCtrl]));
    Assert.IsTrue(mFrame.Quick.HandleKey(VK_HOME, []));
    Assert.IsTrue(mFrame.Quick.HandleKey(VK_RETURN, []));
    Assert.AreEqual(0, Integer(Length(mQuick.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(2, Integer(Length(mQuick.Calls)));
    Assert.AreEqual('build C:\P\Zwei.dproj', mQuick.Calls[0]);
    Assert.AreEqual('tests C:\P\Zwei.dproj', mQuick.Calls[1]);
    Assert.AreEqual(1, Integer(Length(mFake.Calls)));
    Assert.AreEqual('open C:\P\Zwei.dproj', mFake.Calls[0]);
    // Ausgeschaltet bzw. ohne Quelle: keine Knöpfe, Tasten bleiben bei der IDE.
    mQuick.IsOn := False;
    mFrame.UpdateContent;
    Assert.AreEqual(0, Integer(Length(mFrame.Quick.ButtonsOf(0))));
    Assert.IsFalse(mFrame.Quick.HandleKey(Ord('B'), [ssCtrl]));
    mFrame.QuickActions := nil;
    Assert.IsFalse(mFrame.Quick.Active);
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeProjectsFrameTests.ClickSelectsForHistory;
var
  mHost: TForm;
  mFake: TFakeProjects;
  mSource: IAtlasProjectsSource;
  mFrame: TAtlasWelcomeProjectsFrame;
  mHit: TAtlasProjectsHit;
begin
  mFake := TFakeProjects.Create;
  mSource := mFake;
  mFake.FEntries := [ProjectEntry('C:\P\Eins.dproj', 0), ProjectEntry('C:\P\Zwei.dproj', 2)];
  mHost := TForm.CreateNew(nil);
  try
    mFrame := ProjectsFrame(mHost, mSource);
    Assert.AreEqual(-1, mFrame.SelectedRow, 'ohne Projektverlauf keine Auswahl');
    mHit.Row := 0;
    mHit.Pill := -1;
    mFake.Calls := nil;
    mFrame.DoubleClickAt(mHit);
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'ohne Auswahl öffnet schon der Klick');
    mFake.FSelectable := True;
    Assert.AreEqual(0, mFrame.SelectedRow, 'ohne Auswahl das oberste');
    mHit.Row := 1;
    mFrame.ClickAt(mHit);
    // Rote Marke springt weiter.
    mHit.Pill := 0;
    mFrame.ClickAt(mHit);
    mHit.Row := 0;
    mHit.Pill := -1;
    mFrame.DoubleClickAt(mHit);
    mFrame.Menu.Row := 1;
    mFrame.Menu.OpenItem.Click;
    Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(4, Integer(Length(mFake.Calls)));
    Assert.AreEqual('select C:\P\Zwei.dproj', mFake.Calls[0]);
    Assert.AreEqual('openAt C:\P\Zwei.dproj C:\P\Main.pas 12', mFake.Calls[1]);
    Assert.AreEqual('open C:\P\Eins.dproj', mFake.Calls[2]);
    Assert.AreEqual('open C:\P\Zwei.dproj', mFake.Calls[3]);
    Assert.AreEqual(1, mFrame.SelectedRow);
    mFake.FSelected := 'c:/p/eins.DPROJ';
    Assert.AreEqual(0, mFrame.SelectedRow, 'Schreibweise egal');
    Assert.Contains(TAtlasProjectsTexts.HintFor(mFake.FEntries[0], True),
      TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeProjectsHintSelect));
    Assert.Contains(TAtlasProjectsTexts.HintFor(mFake.FEntries[0], False),
      TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeProjectsHintClick));
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeProjectsFrameTests);

end.
