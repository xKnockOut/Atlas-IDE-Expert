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
  System.DateUtils,
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
  mIndex: Integer;
begin
  Result := Default(TAtlasContinueEntry);
  Result.Project := AProject;
  Result.State := TAtlasWorkState.Empty;
  Result.State.Known := True;
  Result.State.At := AAtUtc;
  for mIndex := 1 to ATabs do
  begin
    Result.State.Tabs := Result.State.Tabs + [TAtlasWorkTab.Create('C:\Repo\Unit' + IntToStr(mIndex) + '.pas', 1, 1)];
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
  mSaved: TAtlasLanguage;
  mEntry: TAtlasContinueEntry;
  mNowUtc: TDateTime;
  mFavorite: TAtlasSavedItem;
  mCells: TArray<string>;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mNowUtc := TAtlasContinueTexts.NowUtc;
    mEntry := ContinueEntry('C:\Repo\Atlas.dproj', 7, mNowUtc - 2 * OneHour - 5 * OneMinute);
    mEntry.State.Tabs[3].Changed := True;
    mEntry.State.Tabs[3].ChangedAt := mNowUtc - OneHour;
    mEntry.State.Tabs[3].Method := 'TKunde.Laden';
    mEntry.State.Tabs[3].Line := 42;
    Assert.AreEqual('Atlas · 7 Reiter', TAtlasContinueTexts.TitleText(mEntry));
    Assert.AreEqual('Unit4.pas › TKunde.Laden', TAtlasContinueTexts.DetailText(mEntry),
      'zuletzt bearbeitete Datei und Methode');
    Assert.AreEqual('1 Reiter', TAtlasContinueTexts.TabsText(1));
    Assert.Contains(TAtlasContinueTexts.HintFor(mEntry), 'Unit4.pas:42');
    Assert.AreEqual('gerade eben', TAtlasContinueTexts.AgeText(mNowUtc - 10 * OneSecond, mNowUtc));
    Assert.AreEqual('vor 5 Min.', TAtlasContinueTexts.AgeText(mNowUtc - 5 * OneMinute - OneSecond, mNowUtc));
    Assert.AreEqual('', TAtlasContinueTexts.AgeText(0, mNowUtc), 'unbekannt');
    Assert.AreEqual('abc1234  Kunde: Prüfung — Eva · Kunde.pas', TAtlasContinueTexts.CommitText(
      ContinueCommit('abc1234ffff', 'Kunde: Prüfung', 'Eva', 'C:\Repo\Kunde.pas')));
    Assert.Contains(TAtlasContinueTexts.CommitHint(ContinueCommit('abc1234ffff', 'Kunde: Prüfung', 'Eva',
      'C:\Repo\Kunde.pas')), 'Autor: Eva');
    mCells := TAtlasContinueTexts.SavedCells(SavedItem(TAtlasSavedKind.Bookmark, 'b1', 'Speichern',
      'C:\Repo\Kunde.pas', 'C:\Repo\Atlas.dproj', 79));
    Assert.AreEqual(4, Integer(Length(mCells)));
    Assert.AreEqual('Lesezeichen', mCells[0]);
    Assert.AreEqual('Speichern', mCells[1]);
    Assert.AreEqual('Kunde.pas:80', mCells[2]);
    Assert.AreEqual('Atlas', mCells[3]);
    mFavorite := SavedItem(TAtlasSavedKind.Favorite, 'tdataset|open', 'TDataSet.Open', '', '', -1);
    mFavorite.UnitName := 'Data.DB';
    mCells := TAtlasContinueTexts.SavedCells(mFavorite);
    Assert.AreEqual('Favorit', mCells[0]);
    Assert.AreEqual('Data.DB', mCells[2]);
    Assert.AreEqual('alle Projekte', mCells[3]);
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Atlas · 7 tabs', TAtlasContinueTexts.TitleText(mEntry));
    Assert.AreEqual('5 min ago', TAtlasContinueTexts.AgeText(mNowUtc - 5 * OneMinute - OneSecond, mNowUtc));
    Assert.AreEqual('Note', TAtlasContinueTexts.KindText(TAtlasSavedKind.Note));
  finally
    TAtlasStrings.Language := mSaved;
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
  AFrame.Recent.ClickAt(mHit);
  mHit.Row := 1;
  mHit.Button := True;
  AFrame.Recent.ClickAt(mHit);
  mHit.Row := -1;
  mHit.Button := False;
  mHit.Commit := 0;
  AFrame.Recent.ClickAt(mHit);
  mHit.Commit := 3;
  AFrame.Recent.ClickAt(mHit);
end;
procedure TAtlasWelcomeContinueFrameTests.ResumeAndCommitReachSource;
var
  mHost: TForm;
  mFake: TFakeContinue;
  mSource: IAtlasContinueSource;
  mFrame: TAtlasWelcomeContinueFrame;
  mHit: TAtlasContinueHit;
  mHeight: Integer;
begin
  mFake := TFakeContinue.Create;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasWelcomeContinueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Width := 600;
    mFrame.Source := mSource;
    Assert.AreEqual('shown', mFake.Calls[0], 'Shown beim Setzen der Quelle');
    mHeight := mFrame.PreferredHeight;
    mFake.FEntries := [ContinueEntry('C:\Repo\Atlas.dproj', 7, Now), ContinueEntry('C:\Alt\Alt.groupproj', 2, Now)];
    mFake.FIncoming.Available := True;
    mFake.FIncoming.Project := 'C:\Repo\Atlas.dproj';
    mFake.FIncoming.Upstream := 'origin/main';
    mFake.FIncoming.Commits := [ContinueCommit('abc1234ffff', 'Kunde: Prüfung', 'Eva', 'C:\Repo\Kunde.pas')];
    mFrame.UpdateContent;
    Assert.IsTrue(mFrame.PreferredHeight > mHeight, 'zwei Arbeitsstände und ein Commit brauchen mehr Platz');
    Assert.AreEqual(2, Integer(Length(mFrame.Recent.Entries)));
    mFake.Calls := nil;
    ClickContinueRowsAndCommits(mFrame);
    Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(2, Integer(Length(mFake.Calls)));
    Assert.AreEqual('resume C:\Alt\Alt.groupproj', mFake.Calls[0]);
    Assert.AreEqual('commit C:\Repo\Atlas.dproj abc1234', mFake.Calls[1]);
    Assert.AreEqual(-1, mFrame.Recent.HitTest(20, -5).Row, 'über der ersten Zeile');
    Assert.AreEqual(1, mFrame.Recent.HitTest(20, mFrame.Recent.RowTop(1) + 4).Row);
    // Anmeldung am Server nötig (#1287): Hinweis als Link unter dem Commit, Klick öffnet die Seite.
    Assert.IsFalse(mFrame.Recent.HitTest(20, mFrame.Recent.IncomingTop + 2 *
      mFrame.ScaleValue(TAtlasWelcomeContinueFrame.cLineHeight) +
      4).Login, 'ohne fehlende Anmeldung kein Link');
    mFake.FIncoming.FetchFailed := True;
    mFake.FIncoming.LoginNeeded := True;
    mFrame.UpdateContent;
    mHit := mFrame.Recent.HitTest(20, mFrame.Recent.IncomingTop + 2 *
      mFrame.ScaleValue(TAtlasWelcomeContinueFrame.cLineHeight) + 4);
    Assert.IsTrue(mHit.Login, 'Zeile unter dem einen Commit');
    Assert.AreEqual(-1, mHit.Commit);
    mFake.Calls := nil;
    mFrame.Recent.ClickAt(mHit);
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(mFake.Calls)));
    Assert.AreEqual('login C:\Repo\Atlas.dproj', mFake.Calls[0]);
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeContinueFrameTests.QuickActionsInRecent;
var
  mHost: TForm;
  mFake: TFakeContinue;
  mSource: IAtlasContinueSource;
  mQuick: TAtlasFakeQuickActions;
  mQuickSource: IAtlasQuickActionsSource;
  mFrame: TAtlasWelcomeContinueFrame;
begin
  mFake := TFakeContinue.Create;
  mSource := mFake;
  mQuick := TAtlasFakeQuickActions.Create;
  mQuickSource := mQuick;
  mFake.FEntries := [ContinueEntry('C:\Repo\Atlas.dproj', 7, Now), ContinueEntry('C:\Alt\Alt.groupproj', 2, Now)];
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasWelcomeContinueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Width := 600;
    mFrame.Source := mSource;
    Assert.AreEqual(0, Integer(Length(mFrame.Recent.Quick.ButtonsOf(0))), 'ohne Quelle keine Knöpfe');
    mFrame.QuickActions := mQuickSource;
    Assert.AreEqual(7, Integer(Length(mFrame.Recent.Quick.ButtonsOf(1))), 'Vorgabe mit Aufgaben (#900)');
    Assert.IsTrue(mFrame.Recent.Quick.Sink.Visible, 'Tastatur auf „Zuletzt“');
    mFake.Calls := nil;
    // Ohne Maus: Pfeil ab, Strg+B baut die Gruppe, Pos1 und Enter setzen fort.
    Assert.IsTrue(mFrame.Recent.Quick.HandleKey(VK_DOWN, []));
    Assert.IsTrue(mFrame.Recent.Quick.HandleKey(Ord('B'), [ssCtrl]));
    Assert.IsTrue(mFrame.Recent.Quick.HandleKey(VK_HOME, []));
    Assert.IsTrue(mFrame.Recent.Quick.HandleKey(VK_RETURN, []));
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(mQuick.Calls)));
    Assert.AreEqual('build C:\Alt\Alt.groupproj', mQuick.Calls[0]);
    Assert.AreEqual(1, Integer(Length(mFake.Calls)));
    Assert.AreEqual('resume C:\Alt\Alt.groupproj', mFake.Calls[0]);
    // Ausgeschaltet: keine Knöpfe mehr.
    mQuick.IsOn := False;
    mFrame.UpdateContent;
    Assert.AreEqual(0, Integer(Length(mFrame.Recent.Quick.ButtonsOf(1))));
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeContinueFrameTests.IncomingSectionOnlyWithData;
var
  mHost: TForm;
  mFake: TFakeContinue;
  mSource: IAtlasContinueSource;
  mFrame: TAtlasWelcomeContinueFrame;
  mWithout, mQuerying, mWithCommit: Integer;
begin
  mFake := TFakeContinue.Create;
  mSource := mFake;
  mFake.FEntries := [ContinueEntry('C:\Repo\Atlas.dproj', 3, Now)];
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasWelcomeContinueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Width := 600;
    mFrame.Source := mSource;
    // Ohne Versionsverwaltung bzw. ohne Ergebnis: kein Abschnitt.
    mWithout := mFrame.PreferredHeight;
    Assert.AreEqual(-1, mFrame.Recent.HitTest(20, mFrame.Recent.IncomingTop + 2 * mFrame.ScaleValue(
      TAtlasWelcomeContinueFrame.cLineHeight)).Commit);
    mFake.FQuerying := True;
    mFrame.UpdateContent;
    mQuerying := mFrame.PreferredHeight;
    Assert.IsTrue(mQuerying > mWithout, '„wird abgefragt …“');
    mFake.FQuerying := False;
    mFake.FIncoming.Available := True;
    mFake.FIncoming.Project := 'C:\Repo\Atlas.dproj';
    mFake.FIncoming.Upstream := 'origin/main';
    mFake.FIncoming.Commits := [ContinueCommit('abc1234ffff', 'Eins', 'Eva', 'C:\Repo\Unit1.pas'),
      ContinueCommit('def5678ffff', 'Zwei', 'Max', 'C:\Repo\Unit2.pas')];
    mFake.FIncoming.More := True;
    mFrame.UpdateContent;
    mWithCommit := mFrame.PreferredHeight;
    Assert.IsTrue(mWithCommit > mQuerying, 'zwei Commits und „… und weitere“');
    Assert.AreEqual(1, mFrame.Recent.HitTest(20, mFrame.Recent.IncomingTop + 2 * mFrame.ScaleValue(
      TAtlasWelcomeContinueFrame.cLineHeight) + 2).Commit, 'Überschrift, dann die Commits');
    // Ohne Arbeitsstand auch kein Abschnitt.
    mFake.FEntries := nil;
    mFrame.UpdateContent;
    Assert.IsTrue(mFrame.PreferredHeight < mWithCommit);
    // Hinweis der Quelle (übersprungene Dateien) braucht eine Zeile.
    mFake.FEntries := [ContinueEntry('C:\Repo\Atlas.dproj', 3, Now)];
    mFake.FIncoming := Default(TAtlasContinueIncoming);
    mFrame.UpdateContent;
    mWithout := mFrame.PreferredHeight;
    mFake.FNotice := 'nicht mehr vorhanden, übersprungen: Weg.pas';
    mFrame.UpdateContent;
    Assert.IsTrue(mFrame.PreferredHeight > mWithout);
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeContinueFrameTests.SavedTabFiltersAndOpens;
var
  mHost: TForm;
  mFake: TFakeContinue;
  mSource: IAtlasContinueSource;
  mFrame: TAtlasWelcomeContinueFrame;
  mKey: Word;
begin
  mFake := TFakeContinue.Create;
  mSource := mFake;
  mFake.FSavedEnabled := True;
  mFake.FSaved := [SavedItem(TAtlasSavedKind.Note, 'n1', 'Prüfen', 'C:\Repo\Kunde.pas', 'C:\Repo\Atlas.dproj', 4),
    SavedItem(TAtlasSavedKind.Bookmark, 'b1', 'Speichern', 'C:\Zeta\Haupt.pas', 'C:\Zeta\Zeta.dproj', 9)];
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasWelcomeContinueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Width := 600;
    mFrame.Source := mSource;
    Assert.IsTrue(mFrame.Tabs.Visible, 'Reiter „Zuletzt“ und „Gemerkt“');
    Assert.AreEqual(2, Integer(mFrame.Tabs.Tabs.Count));
    Assert.AreEqual(TAtlasWelcomeContinueFrame.cPageRecent, mFrame.Page);
    Assert.AreEqual(0, Integer(Length(mFake.Calls)) - 1, '„Gemerkt“ erst beim Wechsel lesen');
    mFrame.Page := TAtlasWelcomeContinueFrame.cPageSaved;
    Assert.AreEqual(TAtlasWelcomeContinueFrame.cPageSaved, mFrame.Page);
    Assert.AreEqual(2, Integer(mFrame.SavedPage.List.Items.Count));
    Assert.AreEqual('Notiz', mFrame.SavedPage.List.Items[0].Caption);
    Assert.AreEqual('Kunde.pas:5', mFrame.SavedPage.List.Items[0].SubItems[1]);
    Assert.AreEqual('Zeta', mFrame.SavedPage.List.Items[1].SubItems[2]);
    mFrame.SavedPage.Filter.Text := 'zeta';
    Assert.AreEqual(1, Integer(mFrame.SavedPage.List.Items.Count), 'Filter');
    Assert.AreEqual('b1', mFrame.SavedPage.ShownSaved[0].Id);
    mFrame.SavedPage.Filter.Text := 'gibtsnicht';
    Assert.IsTrue(mFrame.SavedPage.EmptyLabel.Visible);
    Assert.IsFalse(mFrame.SavedPage.List.Visible);
    mFrame.SavedPage.Filter.Text := '';
    mFrame.SavedPage.List.Items[1].Selected := True;
    mFake.Calls := nil;
    mFrame.SavedPage.OpenSelected;
    Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(mFake.Calls)));
    Assert.AreEqual('open b1', mFake.Calls[0]);
    // Enter im Filterfeld öffnet den gewählten Eintrag.
    mFake.Calls := nil;
    mKey := VK_RETURN;
    mFrame.SavedPage.Filter.OnKeyDown(mFrame.SavedPage.Filter, mKey, []);
    Assert.AreEqual(0, Integer(mKey));
    CheckSynchronize;
    Assert.AreEqual('open b1', mFake.Calls[0], 'Enter öffnet den gewählten Eintrag');
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeContinueFrameTests.WithoutSavedOnlyRecent;
var
  mHost: TForm;
  mFake: TFakeContinue;
  mSource: IAtlasContinueSource;
  mFrame: TAtlasWelcomeContinueFrame;
begin
  mFake := TFakeContinue.Create;
  mSource := mFake;
  mFake.FSavedEnabled := False;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasWelcomeContinueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Width := 600;
    mFrame.Source := mSource;
    Assert.IsFalse(mFrame.Tabs.Visible, 'welcomePage.saved aus: keine Reiter');
    mFrame.Page := TAtlasWelcomeContinueFrame.cPageSaved;
    Assert.AreEqual(TAtlasWelcomeContinueFrame.cPageRecent, mFrame.Page);
    Assert.IsTrue(mFrame.Recent.Visible);
    Assert.AreEqual(1, Integer(Length(mFake.Calls)), 'nichts gelesen außer Shown');
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeContinueFrameTests);

end.
