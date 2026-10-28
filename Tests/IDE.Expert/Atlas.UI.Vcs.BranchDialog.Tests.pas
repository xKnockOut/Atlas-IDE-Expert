unit Atlas.UI.Vcs.BranchDialog.Tests;

// Dialog „Branch anlegen“ (#1288): Vorgaben unter Git, „Was passiert“ aus dem
// Plan, ungültiger Name sperrt „Anlegen“, andere Basis baut die Schritte neu,
// SVN wartet auf den Server, Externals-Hinweis, „Nicht mehr fragen“ nur bei
// „Beginnen“; SVN-Optionen (#1290): Ort, Danach, Ordner, gemischte Revision.

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
    /// <summary>#1290: Ort unter der Projektwurzel folgt dem Namen, bis er von Hand geändert wird; ohne Layout
    /// Hinweis; Ordner nur bei „frisch auschecken“; Warnung bei gemischter Arbeitskopie als Quelle.</summary>
    [Test]
    procedure SvnOptionsFollowName;
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
    Assert.IsTrue(mDialog.LocationPanel.Visible);
    Assert.IsTrue(mDialog.AfterPanel.Visible);
    Assert.IsFalse(mDialog.FolderPanel.Visible, 'nur bei „frisch auschecken“');
    Assert.AreEqual('^/Kasse/branches/ATL-123-kasse', mDialog.LocationEdit.Text);
    Assert.IsFalse(mDialog.LocationError.Visible);
    // Quelle Arbeitskopie: vorausgewählt, gemischte Revision gewarnt.
    Assert.AreEqual(1, Integer(mDialog.BaseBox.ItemIndex));
    Assert.IsTrue(mDialog.MixedLabel.Visible);
    mRequest := mDialog.Request;
    Assert.AreEqual('Kasse/branches/ATL-123-kasse', mRequest.Location);
    Assert.IsTrue(mRequest.After = TAtlasVcsSvnAfter.Switch);
    Assert.AreEqual('', mRequest.CheckoutFolder);
    Assert.Contains(mDialog.StepsMemo.Lines[0], '^/Kasse/branches/ATL-123-kasse@');
    // Name ändern: Ort folgt.
    mDialog.NameEdit.Text := 'ATL-123-bon';
    Assert.AreEqual('^/Kasse/branches/ATL-123-bon', mDialog.LocationEdit.Text);
    // Basis HEAD: keine Warnung.
    mDialog.BaseBox.ItemIndex := 0;
    mDialog.BaseBox.OnChange(mDialog.BaseBox);
    Assert.IsFalse(mDialog.MixedLabel.Visible);
    // Von Hand geändert: bleibt, auch wenn sich der Name ändert; ungültig gesperrt.
    mDialog.LocationEdit.Text := '^/Kasse/branches/eigener';
    mDialog.NameEdit.Text := 'ATL-123-kasse';
    Assert.AreEqual('^/Kasse/branches/eigener', mDialog.LocationEdit.Text);
    Assert.AreEqual('Kasse/branches/eigener', mDialog.Request.Location);
    mDialog.LocationEdit.Text := 'Kasse/branches/eigener';
    Assert.IsTrue(mDialog.LocationError.Visible, 'ohne ^/');
    Assert.IsFalse(mDialog.CreateButton.Enabled);
  finally
    mDialog.Free;
  end;
  // Ohne erkennbares Layout: Ort leer, Hinweis, nichts anzulegen.
  mFacts.LayoutKnown := False;
  mFacts.ProjectRoot := '';
  mDialog := TAtlasBranchDialog.CreateDialog(nil, mFacts, 'ATL-123-kasse', 'ATL-123 Branch', mSvn, False);
  try
    Assert.AreEqual('', mDialog.LocationEdit.Text);
    Assert.IsTrue(mDialog.LocationError.Visible);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.VcsBranchLocationMissing), mDialog.LocationError.Caption);
    Assert.IsFalse(mDialog.CreateButton.Enabled);
    mDialog.LocationEdit.Text := '^/Kasse/branches/ATL-123-kasse';
    Assert.IsFalse(mDialog.LocationError.Visible);
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
    Assert.IsTrue(mDialog.FolderPanel.Visible);
    Assert.AreEqual('C:\Projekte\Kasse-ATL-123', mDialog.FolderEdit.Text);
    mRequest := mDialog.Request;
    Assert.IsTrue(mRequest.After = TAtlasVcsSvnAfter.Checkout);
    Assert.AreEqual('C:\Projekte\Kasse-ATL-123', mRequest.CheckoutFolder);
    Assert.Contains(mDialog.StepsMemo.Lines[1], 'svn checkout ^/Kasse/branches/ATL-123-kasse@');
  finally
    mDialog.Free;
  end;
  mFacts := TAtlasVcsBranchFacts.Empty;
  mSvn := TAtlasVcsSvnBranchOptions.Default;
  mRequest := Default(TAtlasVcsBranchRequest);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBranchDialogTests);

end.
