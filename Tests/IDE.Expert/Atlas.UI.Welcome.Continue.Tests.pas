unit Atlas.UI.Welcome.Continue.Tests;

// Tests des Bereichs „Weitermachen“ der Willkommensseite.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeContinueFrameTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure TextsFollowLanguageAndAge;
    [Test]
    procedure ResumeAndCommitReachSource;
    [Test]
    procedure IncomingSectionOnlyWithData;
    [Test]
    procedure SavedTabFiltersAndOpens;
    [Test]
    procedure WithoutSavedOnlyRecent;
    /// <summary>Schnellaktionen (#764) in „Zuletzt“: Knöpfe je Arbeitsstand, Enter setzt fort, Strg+B baut.
    /// </summary>
    [Test]
    procedure QuickActionsInRecent;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Strings,
  Atlas.Core.Welcome.Continue,
  Atlas.Core.Welcome.Saved,
  Atlas.UI.Welcome.Continue,
  Atlas.UI.Welcome.QuickActions,
  Atlas.UI.Welcome.QuickActions.Tests,
  Atlas.UI.Welcome.TestSupport;

type
  /// <summary>Quelle des Bereichs „Weiterarbeiten“ für die Tests; merkt sich die Aufrufe.</summary>
  TFakeContinue = class(TInterfacedObject, IAtlasContinueSource)
  public
    FEntries: TAtlasContinueEntries;
    FIncoming: TAtlasContinueIncoming;
    FQuerying: Boolean;
    FSavedEnabled: Boolean;
    FSaved: TAtlasSavedItems;
    FNotice: string;
    Calls: TArray<string>;
    function Entries: TAtlasContinueEntries;
    function Incoming: TAtlasContinueIncoming;
    function IncomingQuerying: Boolean;
    function SavedEnabled: Boolean;
    function Saved: TAtlasSavedItems;
    function Notice: string;
    procedure Resume(const AProject: string);
    procedure ShowCommit(const AProject: string; const ACommit: TAtlasContinueCommit);
    procedure OpenSaved(const AItem: TAtlasSavedItem);
    procedure ShowServerAccess(const AProject: string);
    procedure Shown;
  end;

{ TFakeContinue }

function TFakeContinue.Entries: TAtlasContinueEntries;
begin
  Result := FEntries;
end;
function TFakeContinue.Incoming: TAtlasContinueIncoming;
begin
  Result := FIncoming;
end;
function TFakeContinue.IncomingQuerying: Boolean;
begin
  Result := FQuerying;
end;
function TFakeContinue.SavedEnabled: Boolean;
begin
  Result := FSavedEnabled;
end;
function TFakeContinue.Saved: TAtlasSavedItems;
begin
  Calls := Calls + ['saved'];
  Result := FSaved;
end;
function TFakeContinue.Notice: string;
begin
  Result := FNotice;
end;
procedure TFakeContinue.Resume(const AProject: string);
begin
  Calls := Calls + ['resume ' + AProject];
end;
procedure TFakeContinue.ShowCommit(const AProject: string; const ACommit: TAtlasContinueCommit);
begin
  Calls := Calls + ['commit ' + AProject + ' ' + ACommit.Commit.ShortHash];
end;
procedure TFakeContinue.OpenSaved(const AItem: TAtlasSavedItem);
begin
  Calls := Calls + ['open ' + AItem.Id];
end;
procedure TFakeContinue.ShowServerAccess(const AProject: string);
begin
  Calls := Calls + ['login ' + AProject];
end;
procedure TFakeContinue.Shown;
begin
  Calls := Calls + ['shown'];
end;
function ContinueEntry(const AProject: string; ATabs: Integer; AAtUtc: TDateTime): TAtlasContinueEntry;
var
  Index: Integer;
begin
  Result := Default(TAtlasContinueEntry);
  Result.Project := AProject;
  Result.State := TAtlasWorkState.Empty;
  Result.State.Known := True;
  Result.State.At := AAtUtc;
  for Index := 1 to ATabs do
  begin
    Result.State.Tabs := Result.State.Tabs + [TAtlasWorkTab.Create('C:\Repo\Unit' + IntToStr(Index) + '.pas', 1, 1)];
  end;
end;
function ContinueCommit(const AHash, ASummary, AAuthor, AFile: string): TAtlasContinueCommit;
begin
  Result := Default(TAtlasContinueCommit);
  Result.Commit.Hash := AHash;
  Result.Commit.Summary := ASummary;
  Result.Commit.Author := AAuthor;
  Result.Commit.Files := [AFile, 'C:\Repo\Neu.pas'];
  Result.Files := [AFile];
end;
function SavedItem(AKind: TAtlasSavedKind; const AId, AText, AFileName, AProject: string;
  ALine: Integer): TAtlasSavedItem;
begin
  Result := Default(TAtlasSavedItem);
  Result.Kind := AKind;
  Result.Id := AId;
  Result.Text := AText;
  Result.FileName := AFileName;
  Result.Project := AProject;
  Result.Line := ALine;
end;
{ TAtlasWelcomeContinueFrameTests }

procedure TAtlasWelcomeContinueFrameTests.WarmUpFirstUse;
begin
  ResumeAndCommitReachSource;
end;
procedure TAtlasWelcomeContinueFrameTests.TextsFollowLanguageAndAge;
var
  Saved: TAtlasLanguage;
  Entry: TAtlasContinueEntry;
  NowUtc: TDateTime;
  Favorite: TAtlasSavedItem;
  Cells: TArray<string>;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    NowUtc := TAtlasWelcomeContinueFrame.NowUtc;
    Entry := ContinueEntry('C:\Repo\Atlas.dproj', 7, NowUtc - 2 * OneHour - 5 * OneMinute);
    Entry.State.Tabs[3].Changed := True;
    Entry.State.Tabs[3].ChangedAt := NowUtc - OneHour;
    Entry.State.Tabs[3].Method := 'TKunde.Laden';
    Entry.State.Tabs[3].Line := 42;
    Assert.AreEqual('Atlas · 7 Reiter', TAtlasWelcomeContinueFrame.TitleText(Entry));
    Assert.AreEqual('Unit4.pas › TKunde.Laden', TAtlasWelcomeContinueFrame.DetailText(Entry),
      'zuletzt bearbeitete Datei und Methode');
    Assert.AreEqual('1 Reiter', TAtlasWelcomeContinueFrame.TabsText(1));
    Assert.Contains(TAtlasWelcomeContinueFrame.HintFor(Entry), 'Unit4.pas:42');
    Assert.AreEqual('gerade eben', TAtlasWelcomeContinueFrame.AgeText(NowUtc - 10 * OneSecond, NowUtc));
    Assert.AreEqual('vor 5 Min.', TAtlasWelcomeContinueFrame.AgeText(NowUtc - 5 * OneMinute - OneSecond, NowUtc));
    Assert.AreEqual('', TAtlasWelcomeContinueFrame.AgeText(0, NowUtc), 'unbekannt');
    Assert.AreEqual('abc1234  Kunde: Prüfung — Eva · Kunde.pas', TAtlasWelcomeContinueFrame.CommitText(
      ContinueCommit('abc1234ffff', 'Kunde: Prüfung', 'Eva', 'C:\Repo\Kunde.pas')));
    Assert.Contains(TAtlasWelcomeContinueFrame.CommitHint(ContinueCommit('abc1234ffff', 'Kunde: Prüfung', 'Eva',
      'C:\Repo\Kunde.pas')), 'Autor: Eva');
    Cells := TAtlasWelcomeContinueFrame.SavedCells(SavedItem(TAtlasSavedKind.Bookmark, 'b1', 'Speichern',
      'C:\Repo\Kunde.pas', 'C:\Repo\Atlas.dproj', 79));
    Assert.AreEqual(4, Integer(Length(Cells)));
    Assert.AreEqual('Lesezeichen', Cells[0]);
    Assert.AreEqual('Speichern', Cells[1]);
    Assert.AreEqual('Kunde.pas:80', Cells[2]);
    Assert.AreEqual('Atlas', Cells[3]);
    Favorite := SavedItem(TAtlasSavedKind.Favorite, 'tdataset|open', 'TDataSet.Open', '', '', -1);
    Favorite.UnitName := 'Data.DB';
    Cells := TAtlasWelcomeContinueFrame.SavedCells(Favorite);
    Assert.AreEqual('Favorit', Cells[0]);
    Assert.AreEqual('Data.DB', Cells[2]);
    Assert.AreEqual('alle Projekte', Cells[3]);
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Atlas · 7 tabs', TAtlasWelcomeContinueFrame.TitleText(Entry));
    Assert.AreEqual('5 min ago', TAtlasWelcomeContinueFrame.AgeText(NowUtc - 5 * OneMinute - OneSecond, NowUtc));
    Assert.AreEqual('Note', TAtlasWelcomeContinueFrame.KindText(TAtlasSavedKind.Note));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;
/// <summary>Klicks neben „Fortsetzen“, auf „Fortsetzen“ der zweiten Zeile und auf zwei Commits.</summary>
procedure ClickContinueRowsAndCommits(const AFrame: TAtlasWelcomeContinueFrame);
var
  mHit: TAtlasContinueHit;
begin
  // Klick auf die Zeile außerhalb von „Fortsetzen“: nichts.
  mHit := Default(TAtlasContinueHit);
  mHit.Row := 0;
  mHit.Button := False;
  mHit.Commit := -1;
  AFrame.ClickAt(mHit);
  mHit.Row := 1;
  mHit.Button := True;
  AFrame.ClickAt(mHit);
  mHit.Row := -1;
  mHit.Button := False;
  mHit.Commit := 0;
  AFrame.ClickAt(mHit);
  mHit.Commit := 3;
  AFrame.ClickAt(mHit);
end;
procedure TAtlasWelcomeContinueFrameTests.ResumeAndCommitReachSource;
var
  Host: TForm;
  Fake: TFakeContinue;
  Source: IAtlasContinueSource;
  Frame: TAtlasWelcomeContinueFrame;
  Hit: TAtlasContinueHit;
  Height: Integer;
begin
  Fake := TFakeContinue.Create;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeContinueFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Width := 600;
    Frame.Source := Source;
    Assert.AreEqual('shown', Fake.Calls[0], 'Shown beim Setzen der Quelle');
    Height := Frame.PreferredHeight;
    Fake.FEntries := [ContinueEntry('C:\Repo\Atlas.dproj', 7, Now), ContinueEntry('C:\Alt\Alt.groupproj', 2, Now)];
    Fake.FIncoming.Available := True;
    Fake.FIncoming.Project := 'C:\Repo\Atlas.dproj';
    Fake.FIncoming.Upstream := 'origin/main';
    Fake.FIncoming.Commits := [ContinueCommit('abc1234ffff', 'Kunde: Prüfung', 'Eva', 'C:\Repo\Kunde.pas')];
    Frame.UpdateContent;
    Assert.IsTrue(Frame.PreferredHeight > Height, 'zwei Arbeitsstände und ein Commit brauchen mehr Platz');
    Assert.AreEqual(2, Integer(Length(Frame.Entries)));
    Fake.Calls := nil;
    ClickContinueRowsAndCommits(Frame);
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(2, Integer(Length(Fake.Calls)));
    Assert.AreEqual('resume C:\Alt\Alt.groupproj', Fake.Calls[0]);
    Assert.AreEqual('commit C:\Repo\Atlas.dproj abc1234', Fake.Calls[1]);
    Assert.AreEqual(-1, Frame.HitTest(20, -5).Row, 'über der ersten Zeile');
    Assert.AreEqual(1, Frame.HitTest(20, Frame.RowTop(1) + 4).Row);
    // Anmeldung am Server nötig (#1287): Hinweis als Link unter dem Commit, Klick öffnet die Seite.
    Assert.IsFalse(Frame.HitTest(20, Frame.IncomingTop + 2 * Frame.ScaleValue(TAtlasWelcomeContinueFrame.LineHeight) +
      4).Login, 'ohne fehlende Anmeldung kein Link');
    Fake.FIncoming.FetchFailed := True;
    Fake.FIncoming.LoginNeeded := True;
    Frame.UpdateContent;
    Hit := Frame.HitTest(20, Frame.IncomingTop + 2 * Frame.ScaleValue(TAtlasWelcomeContinueFrame.LineHeight) + 4);
    Assert.IsTrue(Hit.Login, 'Zeile unter dem einen Commit');
    Assert.AreEqual(-1, Hit.Commit);
    Fake.Calls := nil;
    Frame.ClickAt(Hit);
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(Fake.Calls)));
    Assert.AreEqual('login C:\Repo\Atlas.dproj', Fake.Calls[0]);
  finally
    Host.Free;
  end;
end;
procedure TAtlasWelcomeContinueFrameTests.QuickActionsInRecent;
var
  Host: TForm;
  Fake: TFakeContinue;
  Source: IAtlasContinueSource;
  Quick: TAtlasFakeQuickActions;
  QuickSource: IAtlasQuickActionsSource;
  Frame: TAtlasWelcomeContinueFrame;
begin
  Fake := TFakeContinue.Create;
  Source := Fake;
  Quick := TAtlasFakeQuickActions.Create;
  QuickSource := Quick;
  Fake.FEntries := [ContinueEntry('C:\Repo\Atlas.dproj', 7, Now), ContinueEntry('C:\Alt\Alt.groupproj', 2, Now)];
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeContinueFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Width := 600;
    Frame.Source := Source;
    Assert.AreEqual(0, Integer(Length(Frame.Quick.ButtonsOf(0))), 'ohne Quelle keine Knöpfe');
    Frame.QuickActions := QuickSource;
    Assert.AreEqual(7, Integer(Length(Frame.Quick.ButtonsOf(1))), 'Vorgabe mit Aufgaben (#900)');
    Assert.IsTrue(Frame.Quick.Sink.Visible, 'Tastatur auf „Zuletzt“');
    Fake.Calls := nil;
    // Ohne Maus: Pfeil ab, Strg+B baut die Gruppe, Pos1 und Enter setzen fort.
    Assert.IsTrue(Frame.Quick.HandleKey(VK_DOWN, []));
    Assert.IsTrue(Frame.Quick.HandleKey(Ord('B'), [ssCtrl]));
    Assert.IsTrue(Frame.Quick.HandleKey(VK_HOME, []));
    Assert.IsTrue(Frame.Quick.HandleKey(VK_RETURN, []));
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(Quick.Calls)));
    Assert.AreEqual('build C:\Alt\Alt.groupproj', Quick.Calls[0]);
    Assert.AreEqual(1, Integer(Length(Fake.Calls)));
    Assert.AreEqual('resume C:\Alt\Alt.groupproj', Fake.Calls[0]);
    // Ausgeschaltet: keine Knöpfe mehr.
    Quick.IsOn := False;
    Frame.UpdateContent;
    Assert.AreEqual(0, Integer(Length(Frame.Quick.ButtonsOf(1))));
  finally
    Host.Free;
  end;
end;
procedure TAtlasWelcomeContinueFrameTests.IncomingSectionOnlyWithData;
var
  Host: TForm;
  Fake: TFakeContinue;
  Source: IAtlasContinueSource;
  Frame: TAtlasWelcomeContinueFrame;
  Without, Querying, WithCommit: Integer;
begin
  Fake := TFakeContinue.Create;
  Source := Fake;
  Fake.FEntries := [ContinueEntry('C:\Repo\Atlas.dproj', 3, Now)];
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeContinueFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Width := 600;
    Frame.Source := Source;
    // Ohne Versionsverwaltung bzw. ohne Ergebnis: kein Abschnitt.
    Without := Frame.PreferredHeight;
    Assert.AreEqual(-1, Frame.HitTest(20, Frame.IncomingTop + 2 * Frame.ScaleValue(
      TAtlasWelcomeContinueFrame.LineHeight)).Commit);
    Fake.FQuerying := True;
    Frame.UpdateContent;
    Querying := Frame.PreferredHeight;
    Assert.IsTrue(Querying > Without, '„wird abgefragt …“');
    Fake.FQuerying := False;
    Fake.FIncoming.Available := True;
    Fake.FIncoming.Project := 'C:\Repo\Atlas.dproj';
    Fake.FIncoming.Upstream := 'origin/main';
    Fake.FIncoming.Commits := [ContinueCommit('abc1234ffff', 'Eins', 'Eva', 'C:\Repo\Unit1.pas'),
      ContinueCommit('def5678ffff', 'Zwei', 'Max', 'C:\Repo\Unit2.pas')];
    Fake.FIncoming.More := True;
    Frame.UpdateContent;
    WithCommit := Frame.PreferredHeight;
    Assert.IsTrue(WithCommit > Querying, 'zwei Commits und „… und weitere“');
    Assert.AreEqual(1, Frame.HitTest(20, Frame.IncomingTop + 2 * Frame.ScaleValue(
      TAtlasWelcomeContinueFrame.LineHeight) + 2).Commit, 'Überschrift, dann die Commits');
    // Ohne Arbeitsstand auch kein Abschnitt.
    Fake.FEntries := nil;
    Frame.UpdateContent;
    Assert.IsTrue(Frame.PreferredHeight < WithCommit);
    // Hinweis der Quelle (übersprungene Dateien) braucht eine Zeile.
    Fake.FEntries := [ContinueEntry('C:\Repo\Atlas.dproj', 3, Now)];
    Fake.FIncoming := Default(TAtlasContinueIncoming);
    Frame.UpdateContent;
    Without := Frame.PreferredHeight;
    Fake.FNotice := 'nicht mehr vorhanden, übersprungen: Weg.pas';
    Frame.UpdateContent;
    Assert.IsTrue(Frame.PreferredHeight > Without);
  finally
    Host.Free;
  end;
end;
procedure TAtlasWelcomeContinueFrameTests.SavedTabFiltersAndOpens;
var
  Host: TForm;
  Fake: TFakeContinue;
  Source: IAtlasContinueSource;
  Frame: TAtlasWelcomeContinueFrame;
  Key: Word;
begin
  Fake := TFakeContinue.Create;
  Source := Fake;
  Fake.FSavedEnabled := True;
  Fake.FSaved := [SavedItem(TAtlasSavedKind.Note, 'n1', 'Prüfen', 'C:\Repo\Kunde.pas', 'C:\Repo\Atlas.dproj', 4),
    SavedItem(TAtlasSavedKind.Bookmark, 'b1', 'Speichern', 'C:\Zeta\Haupt.pas', 'C:\Zeta\Zeta.dproj', 9)];
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeContinueFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Width := 600;
    Frame.Source := Source;
    Assert.IsTrue(Frame.Tabs.Visible, 'Reiter „Zuletzt“ und „Gemerkt“');
    Assert.AreEqual(2, Integer(Frame.Tabs.Tabs.Count));
    Assert.AreEqual(TAtlasWelcomeContinueFrame.PageRecent, Frame.Page);
    Assert.AreEqual(0, Integer(Length(Fake.Calls)) - 1, '„Gemerkt“ erst beim Wechsel lesen');
    Frame.Page := TAtlasWelcomeContinueFrame.PageSaved;
    Assert.AreEqual(TAtlasWelcomeContinueFrame.PageSaved, Frame.Page);
    Assert.AreEqual(2, Integer(Frame.List.Items.Count));
    Assert.AreEqual('Notiz', Frame.List.Items[0].Caption);
    Assert.AreEqual('Kunde.pas:5', Frame.List.Items[0].SubItems[1]);
    Assert.AreEqual('Zeta', Frame.List.Items[1].SubItems[2]);
    Frame.Filter.Text := 'zeta';
    Assert.AreEqual(1, Integer(Frame.List.Items.Count), 'Filter');
    Assert.AreEqual('b1', Frame.ShownSaved[0].Id);
    Frame.Filter.Text := 'gibtsnicht';
    Assert.IsTrue(Frame.SavedEmptyLabel.Visible);
    Assert.IsFalse(Frame.List.Visible);
    Frame.Filter.Text := '';
    Frame.List.Items[1].Selected := True;
    Fake.Calls := nil;
    Frame.OpenSelected;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(Fake.Calls)));
    Assert.AreEqual('open b1', Fake.Calls[0]);
    // Enter im Filterfeld öffnet den gewählten Eintrag.
    Fake.Calls := nil;
    Key := VK_RETURN;
    Frame.Filter.OnKeyDown(Frame.Filter, Key, []);
    Assert.AreEqual(0, Integer(Key));
    CheckSynchronize;
    Assert.AreEqual('open b1', Fake.Calls[0], 'Enter öffnet den gewählten Eintrag');
  finally
    Host.Free;
  end;
end;
procedure TAtlasWelcomeContinueFrameTests.WithoutSavedOnlyRecent;
var
  Host: TForm;
  Fake: TFakeContinue;
  Source: IAtlasContinueSource;
  Frame: TAtlasWelcomeContinueFrame;
begin
  Fake := TFakeContinue.Create;
  Source := Fake;
  Fake.FSavedEnabled := False;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeContinueFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Width := 600;
    Frame.Source := Source;
    Assert.IsFalse(Frame.Tabs.Visible, 'welcomePage.saved aus: keine Reiter');
    Frame.Page := TAtlasWelcomeContinueFrame.PageSaved;
    Assert.AreEqual(TAtlasWelcomeContinueFrame.PageRecent, Frame.Page);
    Assert.IsTrue(Frame.PaintBox.Visible);
    Assert.AreEqual(1, Integer(Length(Fake.Calls)), 'nichts gelesen außer Shown');
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeContinueFrameTests);

end.
