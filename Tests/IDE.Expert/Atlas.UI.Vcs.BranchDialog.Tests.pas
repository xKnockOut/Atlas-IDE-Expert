unit Atlas.UI.Vcs.BranchDialog.Tests;

// Dialog „Branch anlegen“ (#1288): Vorgaben unter Git, „Was passiert“ aus dem
// Plan, ungültiger Name sperrt „Anlegen“, andere Basis baut die Schritte neu,
// SVN wartet auf den Server, Externals-Hinweis, „Nicht mehr fragen“ nur bei
// „Beginnen“; SVN-Optionen (#1290): Ort, Danach, Ordner, gemischte Revision;
// Externals (#1291): Auswahl je Zeile, Vorauswahl, „Anlegen“ erst mit Wahl.
// Gruppe „Git“ (#1289): Vorbelegung aus den Optionen, Abruf nur mit Basis vom
// Server, offene Änderungen mit „nachfragen“, worktree-Ordner.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Vcs')]
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
    /// <summary>#1290: Ort unter der Projektwurzel folgt dem Namen, bis er von Hand geändert wird; ohne Layout
    /// Hinweis; Ordner nur bei „frisch auschecken“; Warnung bei gemischter Arbeitskopie als Quelle.</summary>
    [Test]
    procedure SvnOptionsFollowName;
    /// <summary>#1291: Gruppe „Externals (3)“; festschreiben vorausgewählt, bei lokalen Änderungen mitverzweigen,
    /// feste Revision ohne Auswahl, fremdes Repository ohne „mitverzweigen“; Wahl landet in Request und Schritten;
    /// mit onBranch = ask „Anlegen“ gesperrt, bis alles gewählt ist.</summary>
    [Test]
    procedure ExternalsChoicePerRow;
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

/// <summary>Vorgaben mit Name feature/13-y, Kennung ATL-13 und AOptions für Git.</summary>
function GitSetup(const AOptions: TAtlasVcsGitBranchOptions; AOfferNeverAsk: Boolean): TAtlasBranchDialogSetup;
begin
  Result := TAtlasBranchDialogSetup.Make('feature/13-y', '', 'ATL-13', AOfferNeverAsk);
  Result.Git := AOptions;
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
  begin
    Result.WorktreeFolder := AFolder;
  end;
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

function MakeExternal(const AFolder, ASource, ARevision, AWorking: string; AModified: Boolean): TAtlasVcsSvnExternal;
begin
  Result := Default(TAtlasVcsSvnExternal);
  Result.Folder := AFolder;
  Result.Url := '^/' + ASource;
  Result.Source := ASource;
  Result.FullUrl := 'https://svn.firma.local/repo/' + ASource;
  Result.Revision := ARevision;
  Result.WorkingRevision := AWorking;
  Result.Modified := AModified;
end;

/// <summary>Wie im Vorschlag: Basis, Drucken (geändert), Kunden (-r 4711) und ein fremdes Repository.</summary>
function ExternalFacts: TAtlasVcsBranchFacts;
begin
  Result := SvnFacts;
  Result.Root := 'C:\Projekte\Kasse';
  Result.MainBranch := 'Kasse/trunk';
  Result.ProjectRoot := 'Kasse';
  Result.LayoutKnown := True;
  Result.ServerChecked := True;
  Result.HeadRevision := '48230';
  Result.RepositoryRoot := 'https://svn.firma.local/repo';
  Result.SvnVersion := '1.14.3';
  Result.SvnDefinitions := [TAtlasVcsSvnExternalDefinition.Make('', '^/Packages/Basis/trunk Packages/Basis'#10 +
    '^/Packages/Drucken/trunk Packages/Drucken'#10'-r 4711 ^/Packages/Kunden/trunk Packages/Kunden'#10 +
    'https://svn.lieferant.de/k/trunk Lieferant'#10)];
  Result.SvnExternals := [MakeExternal('Packages/Basis', 'Packages/Basis/trunk', '', '48190', False),
    MakeExternal('Packages/Drucken', 'Packages/Drucken/trunk', '', '48211', True),
    MakeExternal('Packages/Kunden', 'Packages/Kunden/trunk', '4711', '4711', False),
    MakeExternal('Lieferant', '', '', '17', False)];
  Result.SvnExternals[1].Line := 1;
  Result.SvnExternals[2].Line := 2;
  Result.SvnExternals[3].Line := 3;
  Result.SvnExternals[3].Url := 'https://svn.lieferant.de/k/trunk';
  Result.SvnExternals[3].FullUrl := 'https://svn.lieferant.de/k/trunk';
  Result.SvnExternals[3].Foreign := True;
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
    Assert.AreEqual(3, Integer(mDialog.Names.BaseBox.Items.Count));
    Assert.AreEqual(1, Integer(mDialog.Names.BaseBox.ItemIndex), 'Vorgabe: lokaler Hauptbranch');
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchBaseLocal, ['main']), mDialog.Names.BaseBox.Items[1]);
    Assert.AreEqual(1, Integer(mDialog.Steps.Memo.Lines.Count));
    Assert.AreEqual('1. git checkout --quiet --no-track -b feature/13-y refs/heads/main --',
      mDialog.Steps.Memo.Lines[0]);
    Assert.IsFalse(mDialog.Steps.ServerHint.Visible, 'kein Schritt auf dem Server');
    Assert.IsFalse(mDialog.Svn.MessagePanel.Visible, 'Nachricht nur bei SVN');
    Assert.IsFalse(mDialog.Externals.Box.Visible);
    Assert.IsFalse(mDialog.NeverAsk.Visible, 'nur bei „Beginnen“');
    // Git-Gruppe mit den Werten vor #1289: kein Abruf, beim ersten Push, umschalten.
    Assert.IsTrue(mDialog.Git.Box.Visible);
    Assert.IsFalse(mDialog.Git.FetchCheck.Checked);
    Assert.IsFalse(mDialog.Git.FetchCheck.Enabled, 'Abruf nur mit Basis vom Server');
    Assert.AreEqual(0, Integer(mDialog.Git.PushBox.ItemIndex));
    Assert.AreEqual(0, Integer(mDialog.Git.PlaceBox.ItemIndex));
    Assert.IsFalse(mDialog.Git.UncommittedPanel.Visible, 'ohne geänderte Dateien');
    Assert.IsFalse(mDialog.Git.WorktreePanel.Visible);
    Assert.IsFalse(mDialog.Git.Error.Visible);
    Assert.IsFalse(mDialog.Names.NameError.Visible);
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
    Assert.IsTrue(mDialog.Names.NameError.Visible);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.VcsBranchNameMissing), mDialog.Names.NameError.Caption);
    Assert.IsFalse(mDialog.CreateButton.Enabled);
    Assert.AreEqual(0, Integer(mDialog.Steps.Memo.Lines.Count));
    // Leerzeichen am Rand, verbotene Zeichen, „..“.
    mDialog.Names.NameEdit.Text := ' feature/13-y';
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.VcsBranchNameInvalid), mDialog.Names.NameError.Caption);
    Assert.IsFalse(mDialog.CreateButton.Enabled);
    mDialog.Names.NameEdit.Text := 'feature/13~y';
    Assert.IsFalse(mDialog.CreateButton.Enabled);
    mDialog.Names.NameEdit.Text := 'feature/13..y';
    Assert.IsFalse(mDialog.CanCreate);
    mDialog.Names.NameEdit.Text := 'feature/13-y';
    Assert.IsFalse(mDialog.Names.NameError.Visible);
    Assert.IsTrue(mDialog.CreateButton.Enabled);
    // Klick bei gesperrtem Zustand schließt nicht.
    mDialog.Names.NameEdit.Text := '';
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
    mDialog.Names.BaseBox.ItemIndex := 0;
    mDialog.Names.BaseBox.OnChange(mDialog.Names.BaseBox);
    Assert.AreEqual('1. git checkout --quiet --no-track -b feature/13-y refs/remotes/origin/main --',
      mDialog.Steps.Memo.Lines[0]);
    Assert.IsTrue(mDialog.Request.Base.Kind = TAtlasVcsBranchBaseKind.RemoteMain);
    mDialog.Names.BaseBox.ItemIndex := 2;
    mDialog.Names.BaseBox.OnChange(mDialog.Names.BaseBox);
    Assert.AreEqual('1. git checkout --quiet --no-track -b feature/13-y refs/heads/feature/12-x --',
      mDialog.Steps.Memo.Lines[0]);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchBaseCurrent, ['feature/12-x']),
      mDialog.Names.BaseBox.Items[2]);
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
    Assert.IsTrue(mDialog.Svn.MessagePanel.Visible, 'svn copy hat eine Nachricht');
    Assert.IsFalse(mDialog.Git.Box.Visible, 'Git-Optionen nur unter Git');
    Assert.IsTrue(mDialog.Externals.Box.Visible, 'Hinweis auf svn:externals');
    Assert.IsTrue(mDialog.InfoLabel.Visible);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.VcsBranchLoading), mDialog.InfoLabel.Caption);
    Assert.IsFalse(mDialog.CreateButton.Enabled, 'gesperrt, bis der Server geantwortet hat');
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchBaseHead, ['trunk']), mDialog.Names.BaseBox.Items[0]);
    mFacts.ServerChecked := True;
    mFacts.HeadRevision := '48230';
    mDialog.ServerLoaded(mFacts);
    Assert.IsFalse(mDialog.InfoLabel.Visible);
    Assert.IsTrue(mDialog.CreateButton.Enabled);
    Assert.AreEqual(0, Integer(mDialog.Names.BaseBox.ItemIndex));
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchBaseHeadRevision, ['trunk', '48230']),
      mDialog.Names.BaseBox.Items[0]);
    Assert.AreEqual(2, Integer(mDialog.Steps.Memo.Lines.Count));
    Assert.AreEqual('1. svn copy ^/trunk@48230 ^/branches/ATL-123-kasse@ --parents -m "Branch ATL-123-kasse"   ' +
      TAtlasStrings.Text(TAtlasTextId.VcsBranchOnServer), mDialog.Steps.Memo.Lines[0]);
    Assert.AreEqual('2. svn switch ^/branches/ATL-123-kasse@ .', mDialog.Steps.Memo.Lines[1]);
    Assert.IsTrue(mDialog.Steps.ServerHint.Visible);
    // Eigene Nachricht landet im copy.
    mDialog.Svn.MessageEdit.Text := 'ATL-123';
    Assert.AreEqual('ATL-123', mDialog.Request.Message);
    Assert.AreEqual('1. svn copy ^/trunk@48230 ^/branches/ATL-123-kasse@ --parents -m ATL-123   ' +
      TAtlasStrings.Text(TAtlasTextId.VcsBranchOnServer), mDialog.Steps.Memo.Lines[0]);
    // Server nicht erreichbar: Hinweis, Kopie von HEAD zum Zeitpunkt des Kopierens bleibt möglich.
    mFacts.HeadRevision := '';
    mFacts.ServerOutcome := TAtlasVcsOutcome.LoginNeeded;
    mDialog.ServerLoaded(mFacts);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchHeadUnknown,
      [AtlasVcsOutcomeName(TAtlasVcsOutcome.LoginNeeded)]), mDialog.InfoLabel.Caption);
    Assert.IsTrue(mDialog.CreateButton.Enabled);
  finally
    mDialog.Free;
  end;
  mFacts := TAtlasVcsBranchFacts.Empty;
end;

/// <summary>Ohne erkennbares Layout und frisch auschecken.</summary>
procedure AssertSvnLayoutAndCheckout(const AFacts: TAtlasVcsBranchFacts; const ASvn: TAtlasVcsSvnBranchOptions);
var
  mDialog: TAtlasBranchDialog;
  mFacts: TAtlasVcsBranchFacts;
  mSvn: TAtlasVcsSvnBranchOptions;
  mRequest: TAtlasVcsBranchRequest;
begin
  mFacts := AFacts;
  mSvn := ASvn;
  // Ohne erkennbares Layout: Ort leer, Hinweis, nichts anzulegen.
  mFacts.LayoutKnown := False;
  mFacts.ProjectRoot := '';
  mDialog := TAtlasBranchDialog.CreateDialog(nil, mFacts, 'ATL-123-kasse', 'ATL-123 Branch', mSvn, False);
  try
    Assert.AreEqual('', mDialog.Svn.LocationEdit.Text);
    Assert.IsTrue(mDialog.Svn.LocationError.Visible);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.VcsBranchLocationMissing), mDialog.Svn.LocationError.Caption);
    Assert.IsFalse(mDialog.CreateButton.Enabled);
    mDialog.Svn.LocationEdit.Text := '^/Kasse/branches/ATL-123-kasse';
    Assert.IsFalse(mDialog.Svn.LocationError.Visible);
    Assert.IsTrue(mDialog.CreateButton.Enabled);
  finally
    mDialog.Free;
  end;
  // Frisch auschecken: Ordner neben der Arbeitskopie, Schritt checkout statt switch.
  mFacts.LayoutKnown := True;
  mFacts.ProjectRoot := 'Kasse';
  mSvn.After := TAtlasVcsSvnAfter.Checkout;
  mDialog := TAtlasBranchDialog.CreateDialog(nil, mFacts, 'ATL-123-kasse', 'ATL-123 Branch', mSvn, False);
  try
    Assert.IsTrue(mDialog.Svn.FolderPanel.Visible);
    Assert.AreEqual('C:\Projekte\Kasse-ATL-123', mDialog.Svn.FolderEdit.Text);
    mRequest := mDialog.Request;
    Assert.IsTrue(mRequest.After = TAtlasVcsSvnAfter.Checkout);
    Assert.AreEqual('C:\Projekte\Kasse-ATL-123', mRequest.CheckoutFolder);
    Assert.Contains(mDialog.Steps.Memo.Lines[1], 'svn checkout ^/Kasse/branches/ATL-123-kasse@');
  finally
    mDialog.Free;
  end;
  mFacts := TAtlasVcsBranchFacts.Empty;
  mSvn := TAtlasVcsSvnBranchOptions.Default;
  mRequest := Default(TAtlasVcsBranchRequest);
end;

procedure TAtlasBranchDialogTests.SvnOptionsFollowName;
var
  mDialog: TAtlasBranchDialog;
  mFacts: TAtlasVcsBranchFacts;
  mSvn: TAtlasVcsSvnBranchOptions;
  mRequest: TAtlasVcsBranchRequest;
begin
  mFacts := SvnFacts;
  mFacts.Root := 'C:\Projekte\Kasse';
  mFacts.MainBranch := 'Kasse/trunk';
  mFacts.ProjectRoot := 'Kasse';
  mFacts.LayoutKnown := True;
  mFacts.MixedRevision := True;
  mFacts.ServerChecked := True;
  mFacts.HeadRevision := '48230';
  mSvn := TAtlasVcsSvnBranchOptions.Default;
  mSvn.Key := 'ATL-123';
  mSvn.Project := 'Kasse';
  mSvn.Source := TAtlasVcsSvnSource.WorkingCopy;
  mDialog := TAtlasBranchDialog.CreateDialog(nil, mFacts, 'ATL-123-kasse', 'ATL-123 Branch', mSvn, False);
  try
    Assert.IsTrue(mDialog.Svn.LocationPanel.Visible);
    Assert.IsTrue(mDialog.Svn.AfterPanel.Visible);
    Assert.IsFalse(mDialog.Svn.FolderPanel.Visible, 'nur bei „frisch auschecken“');
    Assert.AreEqual('^/Kasse/branches/ATL-123-kasse', mDialog.Svn.LocationEdit.Text);
    Assert.IsFalse(mDialog.Svn.LocationError.Visible);
    // Quelle Arbeitskopie: vorausgewählt, gemischte Revision gewarnt.
    Assert.AreEqual(1, Integer(mDialog.Names.BaseBox.ItemIndex));
    Assert.IsTrue(mDialog.Svn.MixedLabel.Visible);
    mRequest := mDialog.Request;
    Assert.AreEqual('Kasse/branches/ATL-123-kasse', mRequest.Location);
    Assert.IsTrue(mRequest.After = TAtlasVcsSvnAfter.Switch);
    Assert.AreEqual('', mRequest.CheckoutFolder);
    Assert.Contains(mDialog.Steps.Memo.Lines[0], '^/Kasse/branches/ATL-123-kasse@');
    // Name ändern: Ort folgt.
    mDialog.Names.NameEdit.Text := 'ATL-123-bon';
    Assert.AreEqual('^/Kasse/branches/ATL-123-bon', mDialog.Svn.LocationEdit.Text);
    // Basis HEAD: keine Warnung.
    mDialog.Names.BaseBox.ItemIndex := 0;
    mDialog.Names.BaseBox.OnChange(mDialog.Names.BaseBox);
    Assert.IsFalse(mDialog.Svn.MixedLabel.Visible);
    // Von Hand geändert: bleibt, auch wenn sich der Name ändert; ungültig gesperrt.
    mDialog.Svn.LocationEdit.Text := '^/Kasse/branches/eigener';
    mDialog.Names.NameEdit.Text := 'ATL-123-kasse';
    Assert.AreEqual('^/Kasse/branches/eigener', mDialog.Svn.LocationEdit.Text);
    Assert.AreEqual('Kasse/branches/eigener', mDialog.Request.Location);
    mDialog.Svn.LocationEdit.Text := 'Kasse/branches/eigener';
    Assert.IsTrue(mDialog.Svn.LocationError.Visible, 'ohne ^/');
    Assert.IsFalse(mDialog.CreateButton.Enabled);
  finally
    mDialog.Free;
  end;
  AssertSvnLayoutAndCheckout(mFacts, mSvn);
  mFacts := TAtlasVcsBranchFacts.Empty;
  mSvn := TAtlasVcsSvnBranchOptions.Default;
  mRequest := Default(TAtlasVcsBranchRequest);
end;

/// <summary>onBranch = ask sperrt bis alles gewählt ist; nicht lesbare Externals zeigen nur den Hinweis.</summary>
procedure AssertExternalsAskAndUnreadable(const AFacts: TAtlasVcsBranchFacts; const ASvn: TAtlasVcsSvnBranchOptions);
var
  mDialog: TAtlasBranchDialog;
  mFacts: TAtlasVcsBranchFacts;
  mSvn: TAtlasVcsSvnBranchOptions;
begin
  mFacts := AFacts;
  mSvn := ASvn;
  // onBranch = ask: keine Vorauswahl, „Anlegen“ gesperrt mit Hinweis, bis alles gewählt ist.
  mSvn.ExternalsOnBranch := TAtlasVcsExternalAction.Ask;
  mSvn.ExternalsSuggest := TAtlasVcsExternalSuggest.Never;
  mDialog := TAtlasBranchDialog.CreateDialog(nil, mFacts, 'KASSE-42-bon', 'KASSE-42 Branch', mSvn, False);
  try
    mDialog.HandleNeeded;
    Assert.AreEqual(-1, Integer(mDialog.Externals.Boxes[0].ItemIndex));
    Assert.IsTrue(mDialog.Externals.Hint.Visible);
    Assert.IsFalse(mDialog.CreateButton.Enabled);
    mDialog.Externals.Boxes[0].ItemIndex := 0;
    mDialog.Externals.Boxes[0].OnChange(mDialog.Externals.Boxes[0]);
    mDialog.Externals.Boxes[1].ItemIndex := 1;
    mDialog.Externals.Boxes[1].OnChange(mDialog.Externals.Boxes[1]);
    Assert.IsFalse(mDialog.CreateButton.Enabled, 'Lieferant fehlt noch');
    mDialog.Externals.Boxes[3].ItemIndex := 1;
    mDialog.Externals.Boxes[3].OnChange(mDialog.Externals.Boxes[3]);
    Assert.IsFalse(mDialog.Externals.Hint.Visible);
    Assert.IsTrue(mDialog.CreateButton.Enabled);
  finally
    mDialog.Free;
  end;
  // Externals nicht lesbar: nur der Hinweis wie vor #1291.
  mFacts.SvnExternals := nil;
  mDialog := TAtlasBranchDialog.CreateDialog(nil, mFacts, 'KASSE-42-bon', 'KASSE-42 Branch', mSvn, False);
  try
    Assert.IsTrue(mDialog.Externals.Box.Visible);
    Assert.AreEqual(0, Integer(Length(mDialog.Externals.Boxes)));
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.VcsBranchExternalsKept), mDialog.Externals.Hint.Caption);
    Assert.IsTrue(mDialog.CreateButton.Enabled);
  finally
    mDialog.Free;
  end;
  mFacts := TAtlasVcsBranchFacts.Empty;
  mSvn := TAtlasVcsSvnBranchOptions.Default;
end;

procedure TAtlasBranchDialogTests.ExternalsChoicePerRow;
var
  mDialog: TAtlasBranchDialog;
  mFacts: TAtlasVcsBranchFacts;
  mSvn: TAtlasVcsSvnBranchOptions;
  mRequest: TAtlasVcsBranchRequest;
  mText: string;
begin
  mFacts := ExternalFacts;
  mSvn := TAtlasVcsSvnBranchOptions.Default;
  mSvn.Key := 'KASSE-42';
  mDialog := TAtlasBranchDialog.CreateDialog(nil, mFacts, 'KASSE-42-bon', 'KASSE-42 Branch', mSvn, False);
  try
    mDialog.HandleNeeded;
    Assert.IsTrue(mDialog.Externals.Box.Visible);
    Assert.AreEqual('Externals (4)', mDialog.Externals.Box.Caption);
    Assert.AreEqual(4, Integer(Length(mDialog.Externals.Boxes)));
    // Basis: festschreiben auf die Revision der Arbeitskopie, drei Einträge.
    Assert.AreEqual(3, Integer(mDialog.Externals.Boxes[0].Items.Count));
    Assert.AreEqual('festschreiben (r48190)', mDialog.Externals.Boxes[0].Text);
    // Drucken: lokale Änderungen, „mitverzweigen“ vorgeschlagen.
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.VcsBranchExternalBranch), mDialog.Externals.Boxes[1].Text);
    // Kunden: feste Revision, keine Auswahl.
    Assert.IsTrue(mDialog.Externals.Boxes[2] = nil);
    // Fremdes Repository: festschreiben oder unverändert.
    Assert.AreEqual(2, Integer(mDialog.Externals.Boxes[3].Items.Count));
    Assert.IsFalse(mDialog.Externals.Hint.Visible);
    Assert.IsTrue(mDialog.CreateButton.Enabled);
    mRequest := mDialog.Request;
    Assert.IsTrue(mRequest.ExternalActions[0] = TAtlasVcsExternalAction.Pin);
    Assert.IsTrue(mRequest.ExternalActions[1] = TAtlasVcsExternalAction.Branch);
    Assert.IsTrue(mRequest.ExternalActions[2] = TAtlasVcsExternalAction.Keep);
    Assert.AreEqual('Packages/Drucken/branches/KASSE-42-bon', mRequest.ExternalLocations[1]);
    // Reihenfolge: Package kopieren, Projekt kopieren, umschreiben, umschalten.
    mText := mDialog.Steps.Memo.Lines.Text;
    Assert.Contains(mDialog.Steps.Memo.Lines[0], '^/Packages/Drucken/trunk@48211 ^/Packages/Drucken/branches/KASSE-42-bon');
    Assert.Contains(mDialog.Steps.Memo.Lines[1], '^/Kasse/branches/KASSE-42-bon');
    Assert.Contains(mText, 'svn propset svn:externals');
    // Drucken unverändert: kein Package-Schritt mehr; Basis und Lieferant schreibt Atlas selbst fest.
    mDialog.Externals.Boxes[1].ItemIndex := 1;
    mDialog.Externals.Boxes[1].OnChange(mDialog.Externals.Boxes[1]);
    Assert.IsTrue(mDialog.Request.ExternalActions[1] = TAtlasVcsExternalAction.Keep);
    Assert.IsFalse(mDialog.Steps.Memo.Lines.Text.Contains('Packages/Drucken/branches'));
  finally
    mDialog.Free;
  end;
  AssertExternalsAskAndUnreadable(mFacts, mSvn);
  mFacts := TAtlasVcsBranchFacts.Empty;
  mSvn := TAtlasVcsSvnBranchOptions.Default;
  mRequest := Default(TAtlasVcsBranchRequest);
  mText := '';
end;

/// <summary>Mitnehmen, später pushen, lokale Basis; zurück zur Basis vom Server ohne Abruf.</summary>
procedure AssertGitLocalBaseSteps(const ADialog: TAtlasBranchDialog);
var
  mDialog: TAtlasBranchDialog;
  mRequest: TAtlasVcsBranchRequest;
begin
  mDialog := ADialog;
    // Mitnehmen, später pushen, lokale Basis: kein Abruf, nur checkout.
    mDialog.Git.UncommittedBox.ItemIndex := 0;
    mDialog.Git.UncommittedBox.OnChange(mDialog.Git.UncommittedBox);
    mDialog.Git.PushBox.ItemIndex := 0;
    mDialog.Git.PushBox.OnChange(mDialog.Git.PushBox);
    mDialog.Names.BaseBox.ItemIndex := 1;
    mDialog.Names.BaseBox.OnChange(mDialog.Names.BaseBox);
    Assert.IsFalse(mDialog.Git.FetchCheck.Enabled);
    Assert.AreEqual(1, Integer(mDialog.Steps.Memo.Lines.Count));
    mRequest := mDialog.Request;
    Assert.IsFalse(mRequest.Fetch, 'Abruf nur mit Basis vom Server');
    Assert.IsFalse(mRequest.Stash);
    Assert.IsFalse(mRequest.PushNow);
    // Zurück zur Basis vom Server, Abruf abgewählt: ohne fetch.
    mDialog.Names.BaseBox.ItemIndex := 0;
    mDialog.Names.BaseBox.OnChange(mDialog.Names.BaseBox);
    mDialog.Git.FetchCheck.Checked := False;
    Assert.AreEqual('1. git checkout --quiet --no-track -b feature/13-y refs/remotes/origin/main --',
      mDialog.Steps.Memo.Lines[0]);
  mRequest := Default(TAtlasVcsBranchRequest);
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
  mDialog := TAtlasBranchDialog.CreateDialog(nil, mFacts, GitSetup(GitOptions(TAtlasVcsGitBaseOption.Remote, True,
    TAtlasVcsGitUncommitted.Ask, False, ''), True));
  try
    Assert.AreEqual(0, Integer(mDialog.Names.BaseBox.ItemIndex), 'Vorgabe: Stand auf dem Server');
    Assert.IsTrue(mDialog.Git.FetchCheck.Checked);
    Assert.IsTrue(mDialog.Git.FetchCheck.Enabled);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchFetch, ['origin', 'main']), mDialog.Git.FetchCheck.Caption);
    Assert.AreEqual(1, Integer(mDialog.Git.PushBox.ItemIndex));
    // „nachfragen“: Anzahl sichtbar, keine Wahl, „Anlegen“ gesperrt.
    Assert.IsTrue(mDialog.Git.UncommittedPanel.Visible);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchUncommittedCount, [3]), mDialog.Git.UncommittedCount.Caption);
    Assert.AreEqual(-1, Integer(mDialog.Git.UncommittedBox.ItemIndex));
    Assert.IsTrue(mDialog.Git.Error.Visible);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.VcsBranchUncommittedChoose), mDialog.Git.Error.Caption);
    Assert.IsFalse(mDialog.CreateButton.Enabled);
    // Beiseitelegen gewählt: fetch, stash, checkout, push (auf dem Server).
    mDialog.Git.UncommittedBox.ItemIndex := 1;
    mDialog.Git.UncommittedBox.OnChange(mDialog.Git.UncommittedBox);
    Assert.IsFalse(mDialog.Git.Error.Visible);
    Assert.IsTrue(mDialog.CreateButton.Enabled);
    Assert.AreEqual(4, Integer(mDialog.Steps.Memo.Lines.Count));
    Assert.AreEqual('1. git fetch --quiet --no-tags origin main', mDialog.Steps.Memo.Lines[0]);
    Assert.AreEqual('2. git stash push --include-untracked --quiet -m "Atlas: vor feature/13-y"',
      mDialog.Steps.Memo.Lines[1]);
    Assert.AreEqual('3. git checkout --quiet --no-track -b feature/13-y refs/remotes/origin/main --',
      mDialog.Steps.Memo.Lines[2]);
    Assert.AreEqual('4. git push --set-upstream origin refs/heads/feature/13-y:refs/heads/feature/13-y   ' +
      TAtlasStrings.Text(TAtlasTextId.VcsBranchOnServer), mDialog.Steps.Memo.Lines[3]);
    Assert.IsTrue(mDialog.Steps.ServerHint.Visible);
    mRequest := mDialog.Request;
    Assert.IsTrue(mRequest.Fetch);
    Assert.IsTrue(mRequest.PushNow);
    Assert.IsTrue(mRequest.Stash);
    Assert.AreEqual('', mRequest.WorktreeFolder);
    AssertGitLocalBaseSteps(mDialog);
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
  mDialog := TAtlasBranchDialog.CreateDialog(nil, mFacts, GitSetup(GitOptions(TAtlasVcsGitBaseOption.Local, False,
    TAtlasVcsGitUncommitted.Ask, True, '..\{repo}-{name}'), False));
  try
    Assert.AreEqual(1, Integer(mDialog.Git.PlaceBox.ItemIndex));
    Assert.IsTrue(mDialog.Git.WorktreePanel.Visible);
    Assert.IsFalse(mDialog.Git.UncommittedPanel.Visible, 'die Arbeitskopie bleibt unberührt');
    Assert.AreEqual(mParent + PathDelim + 'Kasse-feature-13-y', mDialog.Git.WorktreeEdit.Text);
    Assert.AreEqual('1. git worktree add --quiet --no-track -b feature/13-y ' + mParent + PathDelim +
      'Kasse-feature-13-y refs/heads/main', mDialog.Steps.Memo.Lines[0]);
    Assert.IsTrue(mDialog.CreateButton.Enabled);
    // Der Ordner folgt dem Namen.
    mDialog.Names.NameEdit.Text := 'feature/14-z';
    Assert.AreEqual(mParent + PathDelim + 'Kasse-feature-14-z', mDialog.Git.WorktreeEdit.Text);
    Assert.AreEqual(mParent + PathDelim + 'Kasse-feature-14-z', mDialog.Request.WorktreeFolder);
    // Von Hand geändert: folgt nicht mehr; relativ bzw. vorhanden sperrt „Anlegen“.
    mDialog.Git.WorktreeEdit.Text := 'relativ';
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.VcsBranchFolderInvalid), mDialog.Git.Error.Caption);
    Assert.IsFalse(mDialog.CreateButton.Enabled);
    mDialog.Git.WorktreeEdit.Text := ExcludeTrailingPathDelimiter(GetCurrentDir);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchFolderExists, [ExcludeTrailingPathDelimiter(GetCurrentDir)]),
      mDialog.Git.Error.Caption);
    Assert.IsFalse(mDialog.CreateButton.Enabled);
    mDialog.Names.NameEdit.Text := 'feature/15-a';
    Assert.AreEqual(ExcludeTrailingPathDelimiter(GetCurrentDir), mDialog.Git.WorktreeEdit.Text, 'Handänderung bleibt');
    // Zurück zu „umschalten“: offene Änderungen wieder gefragt, Ordner ohne Wirkung.
    mDialog.Git.PlaceBox.ItemIndex := 0;
    mDialog.Git.PlaceBox.OnChange(mDialog.Git.PlaceBox);
    Assert.IsFalse(mDialog.Git.WorktreePanel.Visible);
    Assert.IsTrue(mDialog.Git.UncommittedPanel.Visible);
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
