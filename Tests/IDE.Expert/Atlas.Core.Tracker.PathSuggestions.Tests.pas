unit Atlas.Core.Tracker.PathSuggestions.Tests;

// Tests für „Arbeitskopien vorschlagen“ (#1929) ohne Dateien und Prozesse:
// Projekte einer .groupproj, origin aus .git/config, owner/repo aus einer
// GitHub-Adresse, Worktree-Datei .git, Werte der Liste „Wieder öffnen“ und
// das Zusammenführen der Funde.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerPathSuggestionsTests = class
  public
    [Test]
    procedure GroupProjectsAreAbsolute;
    [Test]
    procedure OriginUrlOnlyFromOrigin;
    [Test]
    procedure OwnerRepoFromGitHubAddresses;
    [Test]
    procedure WorktreeGitDirAndCommonDir;
    [Test]
    procedure RecentProjectFromIdeValue;
    /// <summary>Jeder Ordner einmal, schon hinterlegte fallen weg; Haken nur bei sicheren Funden.</summary>
    [Test]
    procedure AddDropsKnownAndDuplicates;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tracker.PathSuggestions;

{ TAtlasTrackerPathSuggestionsTests }

procedure TAtlasTrackerPathSuggestionsTests.GroupProjectsAreAbsolute;
var
  mProjects: TArray<string>;
begin
  mProjects := TAtlasTrackerPathSuggestions.GroupProjects('C:\Projekte\Kasse\Kasse.groupproj',
    '<Project><ItemGroup><Projects Include="Bon\Bon.dproj"><Dependencies/></Projects>' +
    '<Projects Include="..\Fremd\Lib\Lib.dproj"/><Projects Include="D:\Basis\Basis.dproj"/></ItemGroup></Project>');
  Assert.AreEqual(3, Integer(Length(mProjects)));
  Assert.AreEqual('C:\Projekte\Kasse\Bon\Bon.dproj', mProjects[0]);
  Assert.AreEqual('C:\Projekte\Fremd\Lib\Lib.dproj', mProjects[1]);
  Assert.AreEqual('D:\Basis\Basis.dproj', mProjects[2]);
  Assert.AreEqual(0, Integer(Length(TAtlasTrackerPathSuggestions.GroupProjects('C:\A.groupproj', '<Project/>'))));
  mProjects := nil;
end;

procedure TAtlasTrackerPathSuggestionsTests.OriginUrlOnlyFromOrigin;
const
  cConfig = '[core]'#10#9'bare = false'#10'[remote "upstream"]'#10#9'url = https://github.com/other/repo.git'#10 +
    '[remote "origin"]'#10#9'url = git@github.com:xKnockOut/Atlas-IDE-Expert.git'#10#9'fetch = +refs/*'#10 +
    '[branch "main"]'#10#9'remote = origin'#10;
begin
  Assert.AreEqual('git@github.com:xKnockOut/Atlas-IDE-Expert.git', TAtlasTrackerPathSuggestions.OriginUrl(cConfig));
  Assert.AreEqual('', TAtlasTrackerPathSuggestions.OriginUrl('[core]'#10'url = x'#10));
end;

procedure TAtlasTrackerPathSuggestionsTests.OwnerRepoFromGitHubAddresses;
begin
  Assert.AreEqual('xKnockOut/Atlas-IDE-Expert',
    TAtlasTrackerPathSuggestions.OwnerRepo('https://github.com/xKnockOut/Atlas-IDE-Expert.git'));
  Assert.AreEqual('owner/repo', TAtlasTrackerPathSuggestions.OwnerRepo('git@github.com:owner/repo'));
  Assert.AreEqual('owner/repo', TAtlasTrackerPathSuggestions.OwnerRepo('ssh://git@github.com/owner/repo/'));
  Assert.AreEqual('', TAtlasTrackerPathSuggestions.OwnerRepo('https://gitlab.com/owner/repo.git'));
  Assert.AreEqual('', TAtlasTrackerPathSuggestions.OwnerRepo('https://github.com/owner'));
  Assert.IsTrue(TAtlasTrackerPathSuggestions.IsOwnerRepo(' owner/repo '));
  Assert.IsFalse(TAtlasTrackerPathSuggestions.IsOwnerRepo('KASSE'));
end;

procedure TAtlasTrackerPathSuggestionsTests.WorktreeGitDirAndCommonDir;
var
  mGitDir: string;
begin
  mGitDir := TAtlasTrackerPathSuggestions.WorktreeGitDir('C:\Projekte\Atlas-wt-1903',
    'gitdir: C:/Projekte/Atlas-IDE-Expert/.git/worktrees/Atlas-wt-1903'#10);
  Assert.AreEqual('C:\Projekte\Atlas-IDE-Expert\.git\worktrees\Atlas-wt-1903', mGitDir);
  Assert.AreEqual('C:\Projekte\Atlas-IDE-Expert\.git', TAtlasTrackerPathSuggestions.CommonGitDir(mGitDir));
  Assert.AreEqual('C:\X\.git', TAtlasTrackerPathSuggestions.CommonGitDir('C:\X\.git'));
  Assert.AreEqual('', TAtlasTrackerPathSuggestions.WorktreeGitDir('C:\X', 'irgendwas'));
end;

procedure TAtlasTrackerPathSuggestionsTests.RecentProjectFromIdeValue;
begin
  Assert.AreEqual('C:\Projekte\Kasse\Kasse.groupproj',
    TAtlasTrackerPathSuggestions.RecentProjectOf('''C:\Projekte\Kasse\Kasse.groupproj'',1,2'));
  Assert.AreEqual('D:\A\A.dproj', TAtlasTrackerPathSuggestions.RecentProjectOf('0,D:\A\A.dproj'));
  Assert.AreEqual('', TAtlasTrackerPathSuggestions.RecentProjectOf('A.dproj,C:\B.pas'));
end;

procedure TAtlasTrackerPathSuggestionsTests.AddDropsKnownAndDuplicates;
var
  mList: TArray<TAtlasTrackerPathSuggestion>;
begin
  mList := nil;
  TAtlasTrackerPathSuggestions.Add(mList, TAtlasTrackerPathSuggestion.Create('D:\SVN\Kasse\trunk\', 'svn',
    TAtlasTrackerPathReason.Project, 'Kasse.groupproj'), nil);
  TAtlasTrackerPathSuggestions.Add(mList, TAtlasTrackerPathSuggestion.Create('d:/svn/kasse/trunk', 'svn',
    TAtlasTrackerPathReason.Group, 'Kasse.groupproj'), nil);
  TAtlasTrackerPathSuggestions.Add(mList, TAtlasTrackerPathSuggestion.Create('D:\Lib', 'git',
    TAtlasTrackerPathReason.Group, 'Kasse.groupproj'), nil);
  TAtlasTrackerPathSuggestions.Add(mList, TAtlasTrackerPathSuggestion.Create('D:\Basis', 'svn',
    TAtlasTrackerPathReason.External, 'D:\SVN\Kasse\trunk'), ['D:\Basis\']);
  TAtlasTrackerPathSuggestions.Add(mList, TAtlasTrackerPathSuggestion.Create('', 'svn',
    TAtlasTrackerPathReason.External, ''), nil);
  Assert.AreEqual(2, Integer(Length(mList)));
  Assert.AreEqual('D:\SVN\Kasse\trunk', mList[0].Folder);
  Assert.IsTrue(mList[0].Checked);
  Assert.AreEqual('D:\Lib', mList[1].Folder);
  Assert.IsFalse(mList[1].Checked);
  Assert.IsFalse(TAtlasTrackerPathSuggestion.Create('C:\W', 'git', TAtlasTrackerPathReason.Worktree, '').Checked);
  mList := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerPathSuggestionsTests);

end.
