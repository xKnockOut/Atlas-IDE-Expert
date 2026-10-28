unit Atlas.UI.Vcs.BranchDialog.Tests;

// Dialog „Branch anlegen“ (#1288): Vorgaben unter Git, „Was passiert“ aus dem
// Plan, ungültiger Name sperrt „Anlegen“, andere Basis baut die Schritte neu,
// SVN wartet auf den Server, Externals-Hinweis, „Nicht mehr fragen“ nur bei
// „Beginnen“. Gruppe „Git“ (#1289): Vorbelegung aus den Optionen, Abruf nur mit
// Basis vom Server, offene Änderungen mit „nachfragen“, worktree-Ordner.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  TAtlasBranchDialogTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Git: drei Basen, Vorgabe lokaler Hauptbranch, ein Schritt ohne Server, ohne SVN-Felder.</summary>
    [Test]
    procedure GitDefaultsAndSteps;
    /// <summary>Leerer bzw. ungültiger Name: Hinweis unter dem Feld, keine Schritte, „Anlegen“ gesperrt.</summary>
    [Test]
    procedure InvalidNameBlocksCreate;
    [Test]
    procedure OtherBaseRebuildsSteps;
    /// <summary>SVN: „wird ermittelt …“ bis Loaded; dann HEAD-Revision in der Basis und im copy, Zusatz „auf dem
    /// Server“.</summary>
    [Test]
    procedure SvnWaitsForServer;
    /// <summary>#1289: Basis vom Server mit Abruf, sofort pushen, „nachfragen“ sperrt bis zur Wahl; Schritte in
    /// der Reihenfolge des Plans; andere Basis ohne Abruf.</summary>
    [Test]
    procedure GitOptionsPreset;
    /// <summary>#1289: worktree-Ordner folgt dem Namen bis zur Handänderung; vorhandener bzw. relativer Ordner
    /// sperrt „Anlegen“; offene Änderungen bleiben in der Arbeitskopie.</summary>
    [Test]
    procedure WorktreeFolder;
  end;

implementation

uses
  System.SysUtils,
  System.UITypes,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.BranchPlan,
  Atlas.UI.Vcs.BranchDialog;

function GitFacts: TAtlasVcsBranchFacts;
begin
  Result := TAtlasVcsBranchFacts.Empty;
  Result.Kind := TAtlasVcsKind.Git;
  Result.Outcome := TAtlasVcsOutcome.Ok;
  Result.Current := 'feature/12-x';
  Result.MainBranch := 'main';
  Result.LocalMain := True;
  Result.RemoteMain := True;
end;

function RepoRoot: string;
begin
  Result := ExpandFileName(PathDelim + 'Projekte' + PathDelim + 'Kasse');
end;

function GitOptions(ABase: TAtlasVcsGitBaseOption; APushNow: Boolean; AUncommitted: TAtlasVcsGitUncommitted;
  AWorktree: Boolean; const AFolder: string): TAtlasVcsGitBranchOptions;
begin
  Result := TAtlasVcsGitBranchOptions.Classic;
  Result.Base := ABase;
  Result.PushNow := APushNow;
  Result.Uncommitted := AUncommitted;
  Result.Worktree := AWorktree;
  if AFolder <> '' then
    Result.WorktreeFolder := AFolder;
end;

function SvnFacts: TAtlasVcsBranchFacts;
begin
  Result := TAtlasVcsBranchFacts.Empty;
  Result.Kind := TAtlasVcsKind.Svn;
  Result.Outcome := TAtlasVcsOutcome.Ok;
  Result.Current := 'Kasse/trunk';
  Result.Revision := '48100';
  Result.MainBranch := 'trunk';
  Result.Externals := True;
end;

{ TAtlasBranchDialogTests }

procedure TAtlasBranchDialogTests.WarmUpFirstUse;
begin
  Setup;
  try
    GitDefaultsAndSteps;
  finally
    TearDown;
  end;
end;

procedure TAtlasBranchDialogTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasBranchDialogTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasBranchDialogTests.GitDefaultsAndSteps;
var
  mDialog: TAtlasBranchDialog;
  mRequest: TAtlasVcsBranchRequest;
begin
  mDialog := TAtlasBranchDialog.CreateDialog(nil, GitFacts, 'feature/13-y', '', False);
  try
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.VcsBranchTitle), mDialog.Caption);
    Assert.AreEqual(3, Integer(mDialog.BaseBox.Items.Count));
    Assert.AreEqual(1, Integer(mDialog.BaseBox.ItemIndex), 'Vorgabe: lokaler Hauptbranch');
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchBaseLocal, ['main']), mDialog.BaseBox.Items[1]);
    Assert.AreEqual(1, Integer(mDialog.StepsMemo.Lines.Count));
    Assert.AreEqual('1. git checkout --quiet --no-track -b feature/13-y refs/heads/main --',
      mDialog.StepsMemo.Lines[0]);
    Assert.IsFalse(mDialog.ServerHint.Visible, 'kein Schritt auf dem Server');
    Assert.IsFalse(mDialog.MessagePanel.Visible, 'Nachricht nur bei SVN');
    Assert.IsFalse(mDialog.ExternalsBox.Visible);
    Assert.IsFalse(mDialog.NeverAsk.Visible, 'nur bei „Beginnen“');
    // Git-Gruppe mit den Werten vor #1289: kein Abruf, beim ersten Push, umschalten.
    Assert.IsTrue(mDialog.GitBox.Visible);
    Assert.IsFalse(mDialog.FetchCheck.Checked);
    Assert.IsFalse(mDialog.FetchCheck.Enabled, 'Abruf nur mit Basis vom Server');
    Assert.AreEqual(0, Integer(mDialog.PushBox.ItemIndex));
    Assert.AreEqual(0, Integer(mDialog.PlaceBox.ItemIndex));
    Assert.IsFalse(mDialog.UncommittedPanel.Visible, 'ohne geänderte Dateien');
    Assert.IsFalse(mDialog.FolderPanel.Visible);
    Assert.IsFalse(mDialog.GitError.Visible);
    Assert.IsFalse(mDialog.NameError.Visible);
    Assert.IsFalse(mDialog.InfoLabel.Visible);
    Assert.IsTrue(mDialog.CanCreate);
    Assert.IsTrue(mDialog.CreateButton.Enabled);
    Assert.IsTrue(mDialog.CreateButton.Default, 'Enter legt an');
    mRequest := mDialog.Request;
    Assert.AreEqual('feature/13-y', mRequest.Name);
    Assert.IsTrue(mRequest.Base.Kind = TAtlasVcsBranchBaseKind.LocalMain);
    mDialog.CreateButton.Click;
    Assert.AreEqual(Integer(mrOk), Integer(mDialog.ModalResult));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasBranchDialogTests.InvalidNameBlocksCreate;
var
  mDialog: TAtlasBranchDialog;
begin
  mDialog := TAtlasBranchDialog.CreateDialog(nil, GitFacts, '', '', True);
  try
    Assert.IsTrue(mDialog.NeverAsk.Visible, 'angeboten');
    Assert.IsTrue(mDialog.NameError.Visible);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.VcsBranchNameMissing), mDialog.NameError.Caption);
    Assert.IsFalse(mDialog.CreateButton.Enabled);
    Assert.AreEqual(0, Integer(mDialog.StepsMemo.Lines.Count));
    // Leerzeichen am Rand, verbotene Zeichen, „..“.
    mDialog.NameEdit.Text := ' feature/13-y';
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.VcsBranchNameInvalid), mDialog.NameError.Caption);
    Assert.IsFalse(mDialog.CreateButton.Enabled);
    mDialog.NameEdit.Text := 'feature/13~y';
    Assert.IsFalse(mDialog.CreateButton.Enabled);
    mDialog.NameEdit.Text := 'feature/13..y';
    Assert.IsFalse(mDialog.CanCreate);
    mDialog.NameEdit.Text := 'feature/13-y';
    Assert.IsFalse(mDialog.NameError.Visible);
    Assert.IsTrue(mDialog.CreateButton.Enabled);
    // Klick bei gesperrtem Zustand schließt nicht.
    mDialog.NameEdit.Text := '';
    mDialog.CreateButton.OnClick(mDialog.CreateButton);
    Assert.AreEqual(Integer(mrNone), Integer(mDialog.ModalResult));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasBranchDialogTests.OtherBaseRebuildsSteps;
var
  mDialog: TAtlasBranchDialog;
begin
  mDialog := TAtlasBranchDialog.CreateDialog(nil, GitFacts, 'feature/13-y', '', False);
  try
    mDialog.BaseBox.ItemIndex := 0;
    mDialog.BaseBox.OnChange(mDialog.BaseBox);
    Assert.AreEqual('1. git checkout --quiet --no-track -b feature/13-y refs/remotes/origin/main --',
      mDialog.StepsMemo.Lines[0]);
    Assert.IsTrue(mDialog.Request.Base.Kind = TAtlasVcsBranchBaseKind.RemoteMain);
    mDialog.BaseBox.ItemIndex := 2;
    mDialog.BaseBox.OnChange(mDialog.BaseBox);
    Assert.AreEqual('1. git checkout --quiet --no-track -b feature/13-y refs/heads/feature/12-x --',
      mDialog.StepsMemo.Lines[0]);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchBaseCurrent, ['feature/12-x']),
      mDialog.BaseBox.Items[2]);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasBranchDialogTests.SvnWaitsForServer;
var
  mDialog: TAtlasBranchDialog;
  mFacts: TAtlasVcsBranchFacts;
begin
  mFacts := SvnFacts;
  mDialog := TAtlasBranchDialog.CreateDialog(nil, mFacts, 'ATL-123-kasse', '', True);
  try
    Assert.IsTrue(mDialog.MessagePanel.Visible, 'svn copy hat eine Nachricht');
    Assert.IsFalse(mDialog.GitBox.Visible, 'Git-Optionen nur unter Git');
    Assert.IsTrue(mDialog.ExternalsBox.Visible, 'Hinweis auf svn:externals');
    Assert.IsTrue(mDialog.InfoLabel.Visible);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.VcsBranchLoading), mDialog.InfoLabel.Caption);
    Assert.IsFalse(mDialog.CreateButton.Enabled, 'gesperrt, bis der Server geantwortet hat');
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchBaseHead, ['trunk']), mDialog.BaseBox.Items[0]);
    mFacts.ServerChecked := True;
    mFacts.HeadRevision := '48230';
    mDialog.Loaded(mFacts);
    Assert.IsFalse(mDialog.InfoLabel.Visible);
    Assert.IsTrue(mDialog.CreateButton.Enabled);
    Assert.AreEqual(0, Integer(mDialog.BaseBox.ItemIndex));
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchBaseHeadRevision, ['trunk', '48230']),
      mDialog.BaseBox.Items[0]);
    Assert.AreEqual(2, Integer(mDialog.StepsMemo.Lines.Count));
    Assert.AreEqual('1. svn copy ^/trunk@48230 ^/branches/ATL-123-kasse@ --parents -m "Branch ATL-123-kasse"   ' +
      TAtlasStrings.Text(TAtlasTextId.VcsBranchOnServer), mDialog.StepsMemo.Lines[0]);
    Assert.AreEqual('2. svn switch ^/branches/ATL-123-kasse@ .', mDialog.StepsMemo.Lines[1]);
    Assert.IsTrue(mDialog.ServerHint.Visible);
    // Eigene Nachricht landet im copy.
    mDialog.MessageEdit.Text := 'ATL-123';
    Assert.AreEqual('ATL-123', mDialog.Request.Message);
    Assert.AreEqual('1. svn copy ^/trunk@48230 ^/branches/ATL-123-kasse@ --parents -m ATL-123   ' +
      TAtlasStrings.Text(TAtlasTextId.VcsBranchOnServer), mDialog.StepsMemo.Lines[0]);
    // Server nicht erreichbar: Hinweis, Kopie von HEAD zum Zeitpunkt des Kopierens bleibt möglich.
    mFacts.HeadRevision := '';
    mFacts.ServerOutcome := TAtlasVcsOutcome.LoginNeeded;
    mDialog.Loaded(mFacts);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchHeadUnknown,
      [AtlasVcsOutcomeName(TAtlasVcsOutcome.LoginNeeded)]), mDialog.InfoLabel.Caption);
    Assert.IsTrue(mDialog.CreateButton.Enabled);
  finally
    mDialog.Free;
  end;
  mFacts := TAtlasVcsBranchFacts.Empty;
end;

procedure TAtlasBranchDialogTests.GitOptionsPreset;
var
  mDialog: TAtlasBranchDialog;
  mFacts: TAtlasVcsBranchFacts;
  mRequest: TAtlasVcsBranchRequest;
begin
  mFacts := GitFacts;
  mFacts.Remote := 'origin';
  mFacts.LocalChanges := 3;
  mFacts.Root := RepoRoot;
  mDialog := TAtlasBranchDialog.CreateDialog(nil, mFacts, 'feature/13-y', '', 'ATL-13',
    GitOptions(TAtlasVcsGitBaseOption.Remote, True, TAtlasVcsGitUncommitted.Ask, False, ''), True);
  try
    Assert.AreEqual(0, Integer(mDialog.BaseBox.ItemIndex), 'Vorgabe: Stand auf dem Server');
    Assert.IsTrue(mDialog.FetchCheck.Checked);
    Assert.IsTrue(mDialog.FetchCheck.Enabled);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchFetch, ['origin', 'main']), mDialog.FetchCheck.Caption);
    Assert.AreEqual(1, Integer(mDialog.PushBox.ItemIndex));
    // „nachfragen“: Anzahl sichtbar, keine Wahl, „Anlegen“ gesperrt.
    Assert.IsTrue(mDialog.UncommittedPanel.Visible);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchUncommittedCount, [3]), mDialog.UncommittedCount.Caption);
    Assert.AreEqual(-1, Integer(mDialog.UncommittedBox.ItemIndex));
    Assert.IsTrue(mDialog.GitError.Visible);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.VcsBranchUncommittedChoose), mDialog.GitError.Caption);
    Assert.IsFalse(mDialog.CreateButton.Enabled);
    // Beiseitelegen gewählt: fetch, stash, checkout, push (auf dem Server).
    mDialog.UncommittedBox.ItemIndex := 1;
    mDialog.UncommittedBox.OnChange(mDialog.UncommittedBox);
    Assert.IsFalse(mDialog.GitError.Visible);
    Assert.IsTrue(mDialog.CreateButton.Enabled);
    Assert.AreEqual(4, Integer(mDialog.StepsMemo.Lines.Count));
    Assert.AreEqual('1. git fetch --quiet --no-tags origin main', mDialog.StepsMemo.Lines[0]);
    Assert.AreEqual('2. git stash push --include-untracked --quiet -m "Atlas: vor feature/13-y"',
      mDialog.StepsMemo.Lines[1]);
    Assert.AreEqual('3. git checkout --quiet --no-track -b feature/13-y refs/remotes/origin/main --',
      mDialog.StepsMemo.Lines[2]);
    Assert.AreEqual('4. git push --set-upstream origin refs/heads/feature/13-y:refs/heads/feature/13-y   ' +
      TAtlasStrings.Text(TAtlasTextId.VcsBranchOnServer), mDialog.StepsMemo.Lines[3]);
    Assert.IsTrue(mDialog.ServerHint.Visible);
    mRequest := mDialog.Request;
    Assert.IsTrue(mRequest.Fetch);
    Assert.IsTrue(mRequest.PushNow);
    Assert.IsTrue(mRequest.Stash);
    Assert.AreEqual('', mRequest.WorktreeFolder);
    // Mitnehmen, später pushen, lokale Basis: kein Abruf, nur checkout.
    mDialog.UncommittedBox.ItemIndex := 0;
    mDialog.UncommittedBox.OnChange(mDialog.UncommittedBox);
    mDialog.PushBox.ItemIndex := 0;
    mDialog.PushBox.OnChange(mDialog.PushBox);
    mDialog.BaseBox.ItemIndex := 1;
    mDialog.BaseBox.OnChange(mDialog.BaseBox);
    Assert.IsFalse(mDialog.FetchCheck.Enabled);
    Assert.AreEqual(1, Integer(mDialog.StepsMemo.Lines.Count));
    mRequest := mDialog.Request;
    Assert.IsFalse(mRequest.Fetch, 'Abruf nur mit Basis vom Server');
    Assert.IsFalse(mRequest.Stash);
    Assert.IsFalse(mRequest.PushNow);
    // Zurück zur Basis vom Server, Abruf abgewählt: ohne fetch.
    mDialog.BaseBox.ItemIndex := 0;
    mDialog.BaseBox.OnChange(mDialog.BaseBox);
    mDialog.FetchCheck.Checked := False;
    Assert.AreEqual('1. git checkout --quiet --no-track -b feature/13-y refs/remotes/origin/main --',
      mDialog.StepsMemo.Lines[0]);
  finally
    mDialog.Free;
  end;
  mFacts := TAtlasVcsBranchFacts.Empty;
  mRequest := Default(TAtlasVcsBranchRequest);
end;

procedure TAtlasBranchDialogTests.WorktreeFolder;
var
  mDialog: TAtlasBranchDialog;
  mFacts: TAtlasVcsBranchFacts;
  mParent: string;
begin
  mFacts := GitFacts;
  mFacts.LocalChanges := 2;
  mFacts.Root := RepoRoot;
  mParent := ExtractFileDir(RepoRoot);
  mDialog := TAtlasBranchDialog.CreateDialog(nil, mFacts, 'feature/13-y', '', 'ATL-13',
    GitOptions(TAtlasVcsGitBaseOption.Local, False, TAtlasVcsGitUncommitted.Ask, True, '..\{repo}-{name}'), False);
  try
    Assert.AreEqual(1, Integer(mDialog.PlaceBox.ItemIndex));
    Assert.IsTrue(mDialog.FolderPanel.Visible);
    Assert.IsFalse(mDialog.UncommittedPanel.Visible, 'die Arbeitskopie bleibt unberührt');
    Assert.AreEqual(mParent + PathDelim + 'Kasse-feature-13-y', mDialog.FolderEdit.Text);
    Assert.AreEqual('1. git worktree add --quiet --no-track -b feature/13-y ' + mParent + PathDelim +
      'Kasse-feature-13-y refs/heads/main', mDialog.StepsMemo.Lines[0]);
    Assert.IsTrue(mDialog.CreateButton.Enabled);
    // Der Ordner folgt dem Namen.
    mDialog.NameEdit.Text := 'feature/14-z';
    Assert.AreEqual(mParent + PathDelim + 'Kasse-feature-14-z', mDialog.FolderEdit.Text);
    Assert.AreEqual(mParent + PathDelim + 'Kasse-feature-14-z', mDialog.Request.WorktreeFolder);
    // Von Hand geändert: folgt nicht mehr; relativ bzw. vorhanden sperrt „Anlegen“.
    mDialog.FolderEdit.Text := 'relativ';
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.VcsBranchFolderInvalid), mDialog.GitError.Caption);
    Assert.IsFalse(mDialog.CreateButton.Enabled);
    mDialog.FolderEdit.Text := ExcludeTrailingPathDelimiter(GetCurrentDir);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchFolderExists, [ExcludeTrailingPathDelimiter(GetCurrentDir)]),
      mDialog.GitError.Caption);
    Assert.IsFalse(mDialog.CreateButton.Enabled);
    mDialog.NameEdit.Text := 'feature/15-a';
    Assert.AreEqual(ExcludeTrailingPathDelimiter(GetCurrentDir), mDialog.FolderEdit.Text, 'Handänderung bleibt');
    // Zurück zu „umschalten“: offene Änderungen wieder gefragt, Ordner ohne Wirkung.
    mDialog.PlaceBox.ItemIndex := 0;
    mDialog.PlaceBox.OnChange(mDialog.PlaceBox);
    Assert.IsFalse(mDialog.FolderPanel.Visible);
    Assert.IsTrue(mDialog.UncommittedPanel.Visible);
    Assert.AreEqual('', mDialog.Request.WorktreeFolder);
    Assert.IsFalse(mDialog.CreateButton.Enabled, 'nachfragen: erst wählen');
  finally
    mDialog.Free;
  end;
  mFacts := TAtlasVcsBranchFacts.Empty;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBranchDialogTests);

end.
