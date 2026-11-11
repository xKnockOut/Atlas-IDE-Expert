unit Atlas.UI.Welcome.ContinueIssues.Tests;

// Tests des Reiters „Issues“ in „Weiterarbeiten“ (#2052): Texte einer Zeile
// (Kennung, Titel, Alter, Reiter, Stelle, Branch, „Zustand unbekannt“) auf
// Deutsch und Englisch, Reiter nur mit eingeschalteter Quelle, Reihenfolge
// Zuletzt | Issues | Gemerkt und „Fortsetzen“ über die Nachrichtenschleife.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeContinueIssuesViewTests = class
  public
    [Test]
    procedure TextsFollowLanguage;
    [Test]
    procedure IssuesTabOnlyWhenEnabled;
    [Test]
    procedure ResumeReachesSource;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Strings,
  Atlas.Core.Welcome.Continue,
  Atlas.Core.Welcome.ContinueIssues,
  Atlas.Core.Welcome.Saved,
  Atlas.UI.Welcome.Continue,
  Atlas.UI.Welcome.ContinueIssues;

type
  /// <summary>Quelle für „Zuletzt“ und „Gemerkt“: leer, „Gemerkt“ an.</summary>
  TFakeRecent = class(TInterfacedObject, IAtlasContinueSource)
  public
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

  /// <summary>Quelle des Reiters „Issues“; merkt sich „Fortsetzen“.</summary>
  TFakeIssues = class(TInterfacedObject, IAtlasContinueIssuesSource)
  public
    FEnabled: Boolean;
    FRows: TAtlasIssueWorkRows;
    FNotice: string;
    Calls: TArray<string>;
    function IssuesEnabled: Boolean;
    function IssueRows: TAtlasIssueWorkRows;
    function IssuesNotice: string;
    procedure ResumeIssue(const AProject, AKey: string);
  end;

{ TFakeRecent }

function TFakeRecent.Entries: TAtlasContinueEntries;
begin
  Result := nil;
end;

function TFakeRecent.Incoming: TAtlasContinueIncoming;
begin
  Result := Default(TAtlasContinueIncoming);
end;

function TFakeRecent.IncomingQuerying: Boolean;
begin
  Result := False;
end;

function TFakeRecent.SavedEnabled: Boolean;
begin
  Result := True;
end;

function TFakeRecent.Saved: TAtlasSavedItems;
begin
  Result := nil;
end;

function TFakeRecent.Notice: string;
begin
  Result := '';
end;

procedure TFakeRecent.Resume(const AProject: string);
begin
end;

procedure TFakeRecent.ShowCommit(const AProject: string; const ACommit: TAtlasContinueCommit);
begin
end;

procedure TFakeRecent.OpenSaved(const AItem: TAtlasSavedItem);
begin
end;

procedure TFakeRecent.ShowServerAccess(const AProject: string);
begin
end;

procedure TFakeRecent.Shown;
begin
end;

{ TFakeIssues }

function TFakeIssues.IssuesEnabled: Boolean;
begin
  Result := FEnabled;
end;

function TFakeIssues.IssueRows: TAtlasIssueWorkRows;
begin
  Result := FRows;
end;

function TFakeIssues.IssuesNotice: string;
begin
  Result := FNotice;
end;

procedure TFakeIssues.ResumeIssue(const AProject, AKey: string);
begin
  Calls := Calls + [AProject + '|' + AKey];
end;

function RowOf(const AKey, ATitle, ABranch: string; AStatus: TAtlasIssueStateKind; AAtUtc: TDateTime): TAtlasIssueWorkRow;
var
  mState: TAtlasWorkState;
begin
  mState := TAtlasWorkState.Empty;
  mState.Known := True;
  mState.At := AAtUtc;
  mState.Tabs := [TAtlasWorkTab.Create('C:\Repo\Kunde.pas', 1, 1), TAtlasWorkTab.Create('C:\Repo\Main.pas', 42, 3)];
  mState.Tabs[1].Changed := True;
  mState.Tabs[1].ChangedAt := AAtUtc;
  mState.Tabs[1].Method := 'TMain.Laden';
  Result := Default(TAtlasIssueWorkRow);
  Result.Project := 'C:\Repo\Atlas.dproj';
  Result.Entry := TAtlasIssueWorkEntry.Create(AKey, ATitle, ABranch, mState);
  Result.Status := AStatus;
end;

{ TAtlasWelcomeContinueIssuesViewTests }

procedure TAtlasWelcomeContinueIssuesViewTests.TextsFollowLanguage;
var
  mSaved: TAtlasLanguage;
  mNowUtc: TDateTime;
  mRow: TAtlasIssueWorkRow;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mNowUtc := TAtlasContinueTexts.NowUtc;
    mRow := RowOf('#1926', 'Arbeitskopien', 'feature/1926', TAtlasIssueStateKind.Open, mNowUtc - 5 * OneMinute -
      OneSecond);
    Assert.AreEqual('#1926  Arbeitskopien', TAtlasContinueIssueTexts.TitleText(mRow));
    Assert.AreEqual('vor 5 Min. · 2 Reiter · zuletzt TMain.Laden (Main.pas:42)',
      TAtlasContinueIssueTexts.DetailText(mRow, mNowUtc));
    Assert.AreEqual('Branch feature/1926', TAtlasContinueIssueTexts.BranchText(mRow));
    Assert.Contains(TAtlasContinueIssueTexts.HintFor(mRow), 'C:\Repo\Atlas.dproj');
    mRow.Status := TAtlasIssueStateKind.Unknown;
    Assert.AreEqual('Branch feature/1926 · Zustand unbekannt', TAtlasContinueIssueTexts.BranchText(mRow));
    mRow.Entry.Branch := '';
    Assert.AreEqual('Zustand unbekannt', TAtlasContinueIssueTexts.BranchText(mRow));
    mRow.Entry.Title := '';
    Assert.AreEqual('#1926', TAtlasContinueIssueTexts.TitleText(mRow), 'ohne Titel nur die Kennung');
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('State unknown', TAtlasContinueIssueTexts.BranchText(mRow));
    Assert.AreEqual('5 min ago · 2 tabs · last TMain.Laden (Main.pas:42)',
      TAtlasContinueIssueTexts.DetailText(mRow, mNowUtc));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasWelcomeContinueIssuesViewTests.IssuesTabOnlyWhenEnabled;
var
  mHost: TForm;
  mRecent: IAtlasContinueSource;
  mFake: TFakeIssues;
  mIssues: IAtlasContinueIssuesSource;
  mFrame: TAtlasWelcomeContinueFrame;
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  mRecent := TFakeRecent.Create;
  mFake := TFakeIssues.Create;
  mIssues := mFake;
  mHost := TForm.CreateNew(nil);
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mFrame := TAtlasWelcomeContinueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Width := 600;
    mFrame.Source := mRecent;
    mFrame.IssuesSource := mIssues;
    Assert.AreEqual(2, Integer(mFrame.Tabs.Tabs.Count), 'ohne welcomePage.continue.issues bzw. Tracker kein Reiter');
    mFrame.Page := TAtlasWelcomeContinueFrame.cPageIssues;
    Assert.AreEqual(TAtlasWelcomeContinueFrame.cPageRecent, mFrame.Page, 'zurück zu „Zuletzt“');
    mFake.FEnabled := True;
    mFake.FRows := [RowOf('#1', 'Eins', '', TAtlasIssueStateKind.Open, TAtlasContinueTexts.NowUtc)];
    mFrame.UpdateContent;
    Assert.AreEqual(3, Integer(mFrame.Tabs.Tabs.Count));
    Assert.AreEqual('Zuletzt', mFrame.Tabs.Tabs[0]);
    Assert.AreEqual('Issues', mFrame.Tabs.Tabs[1]);
    Assert.AreEqual('Gemerkt', mFrame.Tabs.Tabs[2]);
    mFrame.Page := TAtlasWelcomeContinueFrame.cPageIssues;
    Assert.AreEqual(TAtlasWelcomeContinueFrame.cPageIssues, mFrame.Page);
    Assert.IsTrue(mFrame.Issues.Visible);
    Assert.IsFalse(mFrame.Recent.Visible);
    Assert.AreEqual(1, Integer(Length(mFrame.Issues.Rows)));
    Assert.AreEqual(1, mFrame.Tabs.TabIndex);
  finally
    mHost.Free;
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasWelcomeContinueIssuesViewTests.ResumeReachesSource;
var
  mHost: TForm;
  mFake: TFakeIssues;
  mIssues: IAtlasContinueIssuesSource;
  mFrame: TAtlasWelcomeContinueFrame;
  mView: TAtlasContinueIssuesView;
  mButton: Boolean;
  mRight, mTop: Integer;
begin
  mFake := TFakeIssues.Create;
  mIssues := mFake;
  mFake.FEnabled := True;
  mFake.FRows := [RowOf('#2', 'Zwei', 'feature/2', TAtlasIssueStateKind.Open, TAtlasContinueTexts.NowUtc),
    RowOf('#1', 'Eins', '', TAtlasIssueStateKind.Unknown, TAtlasContinueTexts.NowUtc - OneHour)];
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasWelcomeContinueFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Width := 600;
    mFrame.IssuesSource := mIssues;
    mFrame.Page := TAtlasWelcomeContinueFrame.cPageIssues;
    mView := mFrame.Issues;
    mView.Fill;
    mView.LayoutButtons;
    Assert.AreEqual(2, Integer(Length(mView.Rows)));
    mTop := mView.RowTop(1) + mFrame.ScaleValue(TAtlasContinueIssuesView.cButtonHeight) div 2;
    Assert.AreEqual(1, mView.HitTest(mFrame.ScaleValue(TAtlasContinueIssuesView.cIndent) + 1, mTop, mButton));
    Assert.IsFalse(mButton, 'neben „Fortsetzen“');
    mRight := mView.Width - mFrame.ScaleValue(TAtlasContinueIssuesView.cIndent) - 2;
    Assert.AreEqual(1, mView.HitTest(mRight, mTop, mButton));
    Assert.IsTrue(mButton, 'auf „Fortsetzen“');
    Assert.AreEqual(-1, mView.HitTest(mRight, mView.RowTop(2) + 1, mButton), 'unter der letzten Zeile');
    mView.ResumeRow(1);
    Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(mFake.Calls)));
    Assert.AreEqual('C:\Repo\Atlas.dproj|#1', mFake.Calls[0]);
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeContinueIssuesViewTests);

end.
