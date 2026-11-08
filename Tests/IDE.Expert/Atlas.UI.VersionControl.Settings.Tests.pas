unit Atlas.UI.VersionControl.Settings.Tests;

// Seite der Versionsverwaltung als Abschnitt des Moduls (#1905, vorher Teile der Optionsseite von Base).

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Seite der Versionsverwaltung.</summary>
  [TestFixture]
  [Category('Atlas.IDE.VersionControl')]
  TAtlasSettingsPageVcsTests = class
  public
    /// <summary>Erstes Erzeugen von Steuerelementen legt einmalige VCL-Daten an (Themes, Schriften).</summary>
    [SetupFixture]
    procedure WarmUp;
    /// <summary>#1285: Seite Versionsverwaltung als eigener Bereich: Art, Programmpfade mit Fundort ohne
    /// Prozess, „Prüfen“ im Hintergrund, Zeitlimit, aktuelles Projekt beim ersten Zeigen und Links.</summary>
    [Test]
    procedure VcsPageLocatesChecksAndShowsProject;
    /// <summary>#1285: Texte für Fundort, Prüfergebnis und aktuelles Projekt.</summary>
    [Test]
    procedure VcsTexts;
    /// <summary>#1286: Tabelle Projekte der Versionsverwaltung: Zeile aus der .atlas schreibgeschützt, überdeckte
    /// persönliche Zeile markiert, „Aktuelles Projekt“ mit erkannter Art, Ordner über OnTrackerBrowse, Hauptbranch
    /// ohne Leerraum, Entfernen, Speichern nach vcs.projects.</summary>
    [Test]
    procedure VcsProjectsTable;
    /// <summary>#1287: Tabelle „Server“: Zeile je Ordner aus aktuellem Projekt und Tabelle Projekte, Zustand aus
    /// der Sitzung, „Prüfen“ und „Alle prüfen“ über OnVcsServerCheck, „Anmelden …“ nur bei „Anmeldung nötig“.
    /// </summary>
    [Test]
    procedure VcsServersTable;
  end;

implementation

uses
  Atlas.UI.Settings.Page.Tree,
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Projects.VersionControl,
  Atlas.UI.Settings.Page,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Tools,
  Atlas.Core.VersionControl.ToolCheck,
  Atlas.Core.VersionControl.ServerCheck,
  Atlas.Core.VersionControl.ServerAccess,
  System.Generics.Collections,
  Vcl.Forms,
  Vcl.ComCtrls,
  Atlas.UI.Settings.Marks,
  Atlas.UI.Strings,
  Atlas.UI.VersionControl.Strings,
  Atlas.Core.Modules.Contract,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.VersionControl.SettingsKind,
  Atlas.UI.VersionControl.SettingsBranch,
  Atlas.UI.VersionControl.SettingsProject,
  Atlas.UI.VersionControl.SettingsProjects,
  Atlas.UI.VersionControl.SettingsTools,
  Atlas.UI.VersionControl.SettingsSection;

var
  /// <summary>Abschnitt der laufenden Seite; NewPage legt ihn an, FreePage gibt ihn frei.</summary>
  GSection: TAtlasVcsSettingsSection;
  GSectionRef: IAtlasSettingsSection;
  GRegistration: IAtlasRegistration;

/// <summary>Neuer Abschnitt, bei der Registry angemeldet, und eine Seite mit Fenster auf AHost.</summary>
function NewPage(AHost: TForm): TAtlasSettingsPage;
begin
  GSection := TAtlasVcsSettingsSection.Create;
  GSectionRef := GSection;
  GRegistration := ProvideSection(GSectionRef);
  Result := TAtlasSettingsPage.Create(AHost);
  Result.Parent := AHost;
end;

/// <summary>Abschnitt abmelden und freigeben (nach dem Freigeben der Seite).</summary>
procedure FreePage;
begin
  if GRegistration <> nil then
  begin
    GRegistration.Revoke;
  end;
  GRegistration := nil;
  GSection := nil;
  GSectionRef := nil;
end;

/// <summary>Knoten des Bereichs im Baum, dessen Reiter ASheet ist; nil ohne.</summary>
function AreaNodeOf(APage: TAtlasSettingsPage; ASheet: TTabSheet): TTreeNode;
var
  mNode: TTreeNode;
begin
  for mNode in TopLevelNodes(APage) do
  begin
    APage.Navigation.OnChange(APage.Navigation, mNode);
    if APage.Pages.ActivePage = ASheet then
    begin
      Exit(mNode);
    end;
  end;
  Result := nil;
end;

procedure TAtlasSettingsPageVcsTests.WarmUp;
begin
  WarmUpSettingsPage;
end;

type
  /// <summary>Hält fest, was die Seite „Versionsverwaltung“ über ihre Ereignisse angefragt hat.</summary>
  TVcsPageProbe = class
  public
    FLocated: string;
    FCheckedKind: TAtlasVcsKind;
    FCheckedPath: string;
    FProjectCalls: Integer;
  end;

/// <summary>Werkzeugpfad lokalisieren: leer = bekannter Ordner, sonst fehlt die angegebene Datei.</summary>
function LocateVcsTool(const APath: string): TAtlasVcsToolLocation;
begin
  Result := TAtlasVcsToolLocation.Empty;
  Result.Configured := APath;
  if APath = '' then
  begin
    Result.Executable := 'C:\Program Files\Git\cmd\git.exe';
    Result.Source := TAtlasVcsToolSource.KnownDir;
  end
  else
  begin
    Result.Source := TAtlasVcsToolSource.ConfiguredMissing;
  end;
end;
/// <summary>Hängt die Ereignisse der Seite an AProbe.</summary>
procedure WireVcsPage(APage: TAtlasSettingsPage; AProbe: TVcsPageProbe);
begin
  AProbe.FCheckedKind := TAtlasVcsKind.None;
  GSection.Tools.OnVcsLocate :=
    function(AKind: TAtlasVcsKind; const APath: string): TAtlasVcsToolLocation
    begin
      AProbe.FLocated := APath;
      Result := LocateVcsTool(APath);
    end;
  GSection.Tools.OnVcsCheck :=
    procedure(AKind: TAtlasVcsKind; const APath: string)
    begin
      AProbe.FCheckedKind := AKind;
      AProbe.FCheckedPath := APath;
    end;
  GSection.Project.OnVcsProject :=
    procedure
    begin
      Inc(AProbe.FProjectCalls);
    end;
end;
/// <summary>Steuerelemente der Seite: Lage im Baum und geladene Werte (#1285, #1288, #1290–#1292).</summary>
procedure AssertVcsPageControls(APage: TAtlasSettingsPage; AVcs: TTabSheet);
begin
  Assert.IsTrue(SheetOf(GSection.Tools.VcsPath(TAtlasVcsKind.Git)) = AVcs);
  Assert.IsTrue(SheetOf(GSection.Tools.VcsPath(TAtlasVcsKind.Svn)) = AVcs);
  Assert.IsTrue(SheetOf(EditOf(APage, 'VcsTimeoutSeconds')) = AVcs);
  Assert.IsTrue(SheetOf(GSection.Project.VcsProjectInfo) = AVcs);
  Assert.AreEqual(2, GSection.Kind.VcsProviderChoice.Choice, 'svn');
  Assert.AreEqual('D:\Tools\svn.exe', GSection.Tools.VcsPath(TAtlasVcsKind.Svn).Text);
  Assert.AreEqual('45', EditOf(APage, 'VcsTimeoutSeconds').Text);
  // #1288: Dialog „Branch anlegen“ bei „Beginnen“, Unterknoten vcs.branches (Schema).
  Assert.IsTrue(SheetOf(CheckOf(APage, 'VcsBranchConfirm')) = APage.NodeSheet('vcs.branches'));
  Assert.IsTrue(CheckOf(APage, 'VcsBranchConfirm').Checked);
  // #1290: SVN-Gruppe auf derselben Seite, Vorgaben aus den Einstellungen.
  Assert.IsTrue(SheetOf(EditOf(APage, 'VcsBranchSvnLocation')) = APage.NodeSheet('vcs.branches'));
  Assert.IsTrue(SheetOf(EditOf(APage, 'VcsBranchSvnMessage')) = APage.NodeSheet('vcs.branches'));
  Assert.AreEqual('{projektwurzel}/branches/{name}', EditOf(APage, 'VcsBranchSvnLocation').Text);
  Assert.AreEqual(0, GSection.Branch.VcsBranchSvnSource.Choice, 'head');
  Assert.AreEqual(0, GSection.Branch.VcsBranchSvnAfter.Choice, 'switch');
  Assert.AreEqual('..\{projekt}-{kennung}', EditOf(APage, 'VcsBranchSvnCheckoutFolder').Text);
  // #1291: Gruppe „Externals“ auf derselben Seite, Regeln als Zeilen; ungültige Zeile mit Hinweis.
  Assert.IsTrue(SheetOf(GSection.Branch.VcsExternalsRules) = APage.NodeSheet('vcs.externals'));
  Assert.AreEqual(0, GSection.Branch.VcsExternalsOnBranch.Choice, 'pin');
  Assert.AreEqual(0, GSection.Branch.VcsExternalsSuggest.Choice, 'modified');
  Assert.AreEqual('', GSection.Branch.VcsExternalsRules.Text);
  GSection.Branch.VcsExternalsRules.Text := '^/Packages/Basis = fragen';
  GSection.Branch.VcsExternalsRules.OnChange(GSection.Branch.VcsExternalsRules);
  Assert.Contains(GSection.Branch.VcsExternalsRulesError.Caption, '^/Packages/Basis = fragen');
  GSection.Branch.VcsExternalsRules.Text := '^/Packages/Basis = keep';
  GSection.Branch.VcsExternalsRules.OnChange(GSection.Branch.VcsExternalsRules);
  Assert.AreEqual('', GSection.Branch.VcsExternalsRulesError.Caption);
  // #1292: Arbeitskopien und Aktualisieren auf derselben Seite.
  Assert.IsTrue(SheetOf(CheckOf(APage, 'VcsExternalsShow')) = APage.NodeSheet('vcs.externals'));
  Assert.IsTrue(CheckOf(APage, 'VcsExternalsShow').Checked);
  Assert.AreEqual(0, GSection.Branch.VcsExternalsUpdate.Choice, 'with');
end;
/// <summary>Pfad ändern prüft nur die Datei; „Prüfen“ fragt im Hintergrund und sperrt den Knopf bis zum
/// Ergebnis.</summary>
procedure AssertVcsToolChecks(APage: TAtlasSettingsPage; AProbe: TVcsPageProbe);
var
  mCheck: TAtlasVcsToolCheck;
begin
  GSection.Tools.VcsPath(TAtlasVcsKind.Git).Text := 'X:\fehlt\git.exe';
  GSection.Tools.VcsPath(TAtlasVcsKind.Git).OnChange(GSection.Tools.VcsPath(TAtlasVcsKind.Git));
  Assert.AreEqual('X:\fehlt\git.exe', AProbe.FLocated);
  Assert.Contains(GSection.Tools.VcsState(TAtlasVcsKind.Git).Caption, 'X:\fehlt\git.exe');
  Assert.IsTrue(AProbe.FCheckedKind = TAtlasVcsKind.None, 'Prüfen erst auf Klick');
  GSection.Tools.VcsPath(TAtlasVcsKind.Git).Text := '';
  GSection.Tools.VcsPath(TAtlasVcsKind.Git).OnChange(GSection.Tools.VcsPath(TAtlasVcsKind.Git));
  Assert.Contains(GSection.Tools.VcsState(TAtlasVcsKind.Git).Caption, 'C:\Program Files\Git\cmd\git.exe');
  GSection.Tools.VcsCheckButton(TAtlasVcsKind.Svn).Click;
  Assert.IsTrue(AProbe.FCheckedKind = TAtlasVcsKind.Svn);
  Assert.AreEqual('D:\Tools\svn.exe', AProbe.FCheckedPath);
  Assert.IsFalse(GSection.Tools.VcsCheckButton(TAtlasVcsKind.Svn).Enabled);
  mCheck := TAtlasVcsToolChecks.Missing(TAtlasVcsKind.Svn, TAtlasVcsToolLocation.Empty);
  mCheck.State := TAtlasVcsToolState.Found;
  mCheck.Version := 'svn 1.14.3';
  mCheck.Location.Executable := 'D:\Tools\svn.exe';
  mCheck.Location.Source := TAtlasVcsToolSource.Configured;
  GSection.Tools.VcsCheckDone(mCheck);
  Assert.IsTrue(GSection.Tools.VcsCheckButton(TAtlasVcsKind.Svn).Enabled);
  Assert.Contains(GSection.Tools.VcsState(TAtlasVcsKind.Svn).Caption, 'svn 1.14.3');
end;
/// <summary>Aktuelles Projekt: einmal beim ersten Zeigen der Seite; Links auf die steuernden Seiten.</summary>
procedure AssertVcsProjectAndLinks(APage: TAtlasSettingsPage; AProbe: TVcsPageProbe; AVcsNode, AOther: TTreeNode);
var
  mVcs: TTabSheet;
  mState: TAtlasVcsProjectState;
begin
  mVcs := SheetOf(GSection.Kind.VcsProviderChoice);
  APage.Navigation.OnChange(APage.Navigation, AOther);
  GSection.Project.CheckShown;
  Assert.AreEqual(0, AProbe.FProjectCalls, 'anderer Reiter: keine Abfrage');
  APage.Navigation.OnChange(APage.Navigation, AVcsNode);
  Assert.IsTrue(APage.Pages.ActivePage = mVcs);
  GSection.Project.CheckShown;
  Assert.AreEqual(1, AProbe.FProjectCalls);
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsProjectQuerying), GSection.Project.VcsProjectInfo.Caption);
  APage.Navigation.OnChange(APage.Navigation, AOther);
  APage.Navigation.OnChange(APage.Navigation, AVcsNode);
  GSection.Project.CheckShown;
  Assert.AreEqual(1, AProbe.FProjectCalls, 'nur einmal je Öffnen');
  mState := TAtlasVcsProjectState.Empty;
  mState.ProjectFile := 'C:\Projekte\Kasse\Kasse.dproj';
  mState.Outcome := TAtlasVcsOutcome.NoWorkingCopy;
  GSection.Project.VcsProjectDone(mState);
  Assert.Contains(GSection.Project.VcsProjectInfo.Caption, 'Kasse.dproj');
  // Ohne die Module Willkommensseite und Tracker keine Links auf ihre Seiten (#1456).
  Assert.IsFalse(GSection.Kind.VcsLinkWelcome.Visible, 'Willkommensseite fehlt');
  Assert.IsFalse(GSection.Kind.VcsLinkIssues.Visible, 'Tracker fehlt');
  GSection.Kind.VcsLinkWelcome.Click;
  Assert.IsTrue(APage.Pages.ActivePage = mVcs, 'ohne Ziel bleibt die Seite');
  GSection.Kind.VcsLinkEditor.Click;
  Assert.IsFalse(APage.Pages.ActivePage = mVcs, 'Editor-Seite mit Git-Rand');
end;
/// <summary>Alle Werte der Seite ändern.</summary>
procedure EditVcsPage(APage: TAtlasSettingsPage);
begin
  GSection.Kind.VcsProviderChoice.Choice := 1;
  GSection.Tools.VcsPath(TAtlasVcsKind.Git).Text := '  D:\Git\git.exe ';
  EditOf(APage, 'VcsTimeoutSeconds').Text := '120';
  CheckOf(APage, 'VcsBranchConfirm').Checked := False;
  EditOf(APage, 'VcsBranchSvnLocation').Text := '^/branches/{kennung}';
  GSection.Branch.VcsBranchSvnSource.Choice := 1;
  GSection.Branch.VcsBranchSvnAfter.Choice := 1;
  EditOf(APage, 'VcsBranchSvnCheckoutFolder').Text := 'D:\Branches\{name}';
  EditOf(APage, 'VcsBranchSvnMessage').Text := 'Neu: {kennung}';
  GSection.Branch.VcsExternalsOnBranch.Choice := 2;
  GSection.Branch.VcsExternalsSuggest.Choice := 2;
  CheckOf(APage, 'VcsExternalsShow').Checked := False;
  GSection.Branch.VcsExternalsUpdate.Choice := 1;
end;
/// <summary>Speichern; eine ungültige Regelzeile lässt die bisherigen Regeln stehen.</summary>
procedure AssertVcsPageSaved(APage: TAtlasSettingsPage; var ASaved: TAtlasPluginSettings);
begin
  APage.SaveTo(ASaved);
  Assert.IsFalse(ASaved.VcsExternalsShow);
  Assert.AreEqual('without', ASaved.VcsExternalsUpdate);
  Assert.AreEqual('ask', ASaved.VcsExternalsOnBranch);
  Assert.AreEqual('always', ASaved.VcsExternalsSuggestBranch);
  Assert.AreEqual('[{"source": "^/Packages/Basis", "onBranch": "keep"}]', ASaved.VcsExternalsRules);
  GSection.Branch.VcsExternalsRules.Text := '^/Packages/Basis = keep'#13#10'kaputt';
  APage.SaveTo(ASaved);
  Assert.AreEqual('[{"source": "^/Packages/Basis", "onBranch": "keep"}]', ASaved.VcsExternalsRules);
  APage.LoadFrom(ASaved);
  Assert.AreEqual('^/Packages/Basis = keep', GSection.Branch.VcsExternalsRules.Text);
  Assert.AreEqual(2, GSection.Branch.VcsExternalsOnBranch.Choice);
  APage.SaveTo(ASaved);
  Assert.IsFalse(ASaved.VcsBranchConfirm);
  Assert.AreEqual('^/branches/{kennung}', ASaved.VcsBranchSvnLocation);
  Assert.AreEqual('workingCopy', ASaved.VcsBranchSvnSource);
  Assert.AreEqual('checkout', ASaved.VcsBranchSvnAfter);
  Assert.AreEqual('D:\Branches\{name}', ASaved.VcsBranchSvnCheckoutFolder);
  Assert.AreEqual('Neu: {kennung}', ASaved.VcsBranchSvnMessage);
  Assert.AreEqual('git', ASaved.VcsProvider);
  Assert.AreEqual('D:\Git\git.exe', ASaved.VcsGitPath);
  Assert.AreEqual('D:\Tools\svn.exe', ASaved.VcsSvnPath);
  Assert.AreEqual(120, ASaved.VcsTimeoutSeconds);
end;
procedure TAtlasSettingsPageVcsTests.VcsPageLocatesChecksAndShowsProject;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mVcsNode: TTreeNode;
  mVcs: TTabSheet;
  mSettings, mSaved: TAtlasPluginSettings;
  mProbe: TVcsPageProbe;
begin
  TAtlasSettingsPageTree.ForgetTreeState;
  mProbe := TVcsPageProbe.Create;
  mHost := TForm.CreateNew(nil);
  try
    mPage := NewPage(mHost);
    mPage.HandleNeeded;
    WireVcsPage(mPage, mProbe);
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.VcsProvider := 'svn';
    mSettings.VcsSvnPath := 'D:\Tools\svn.exe';
    mSettings.VcsTimeoutSeconds := 45;
    mPage.LoadFrom(mSettings);
    mVcs := SheetOf(GSection.Kind.VcsProviderChoice);
    Assert.IsNotNull(mVcs);
    mVcsNode := AreaNodeOf(mPage, mVcs);
    Assert.IsNotNull(mVcsNode, 'eigener Bereich');
    // Mit Punkt: svn, Pfad und Zeitlimit weichen von der Vorgabe ab.
    Assert.IsTrue(mVcsNode.Text.StartsWith(TAtlasSettingsMarks.cDot), mVcsNode.Text);
    AssertVcsPageControls(mPage, mVcs);
    Assert.AreEqual(0, mProbe.FProjectCalls, 'kein Prozess ohne CheckShown');
    AssertVcsToolChecks(mPage, mProbe);
    AssertVcsProjectAndLinks(mPage, mProbe, mVcsNode, TopLevelNodes(mPage)[0]);
    EditVcsPage(mPage);
    mSaved := mSettings;
    AssertVcsPageSaved(mPage, mSaved);
  finally
    mHost.Free;
    FreePage;
    mProbe.Free;
  end;
end;
/// <summary>Texte zu Fundort und Prüfung des Werkzeugs.</summary>
procedure AssertVcsToolTexts;
var
  mLocation: TAtlasVcsToolLocation;
  mCheck: TAtlasVcsToolCheck;
  mText: string;
begin
  mLocation := TAtlasVcsToolLocation.Empty;
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsToolMissing),
    TAtlasSettingsVcsToolsPart.VcsLocationText(mLocation));
  mLocation.Source := TAtlasVcsToolSource.ConfiguredMissing;
  mLocation.Configured := 'X:\git.exe';
  Assert.Contains(TAtlasSettingsVcsToolsPart.VcsLocationText(mLocation), 'X:\git.exe');
  mLocation.Source := TAtlasVcsToolSource.Path;
  mLocation.Executable := 'C:\Git\cmd\git.exe';
  mText := TAtlasSettingsVcsToolsPart.VcsLocationText(mLocation);
  Assert.Contains(mText, 'C:\Git\cmd\git.exe');
  Assert.Contains(mText, TAtlasSettingsVcsToolsPart.VcsSourceText(TAtlasVcsToolSource.Path));
  mCheck := TAtlasVcsToolChecks.Missing(TAtlasVcsKind.Git, mLocation);
  mCheck.State := TAtlasVcsToolState.StartFailed;
  mCheck.ExitCode := 128;
  Assert.Contains(TAtlasSettingsVcsToolsPart.VcsCheckText(mCheck), '128');
  mCheck.State := TAtlasVcsToolState.NoAnswer;
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsToolNoAnswer), TAtlasSettingsVcsToolsPart.VcsCheckText(mCheck));
  mCheck.State := TAtlasVcsToolState.Found;
  mCheck.Version := 'git version 2.47.1';
  mText := TAtlasSettingsVcsToolsPart.VcsCheckText(mCheck);
  Assert.Contains(mText, 'git version 2.47.1');
  Assert.Contains(mText, 'C:\Git\cmd\git.exe');
end;
/// <summary>#1287: Zustände der Tabelle „Server“.</summary>
procedure AssertVcsServerTexts;
var
  mServer: TAtlasVcsServerCheck;
begin
  // #1287: Zustände der Tabelle „Server“.
  mServer := TAtlasVcsServerCheck.Empty;
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsServerUnknown),
    TAtlasSettingsVcsServersPart.VcsServerStateText(mServer, False));
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsServerChecking),
    TAtlasSettingsVcsServersPart.VcsServerStateText(mServer, True));
  mServer.State := TAtlasVcsServerState.Reachable;
  mServer.CheckedAt := EncodeTime(14, 5, 0, 0);
  Assert.AreEqual(TAtlasVcsStrings.Fmt(TAtlasVcsTextId.SettingsVcsServerReachable, ['14:05']),
    TAtlasSettingsVcsServersPart.VcsServerStateText(mServer, False));
  mServer.State := TAtlasVcsServerState.LoginNeeded;
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsServerLoginNeeded),
    TAtlasSettingsVcsServersPart.VcsServerStateText(mServer, False));
  mServer.State := TAtlasVcsServerState.Unreachable;
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsServerUnreachable),
    TAtlasSettingsVcsServersPart.VcsServerStateText(mServer, False));
  mServer.State := TAtlasVcsServerState.NoServer;
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsServerNoServer),
    TAtlasSettingsVcsServersPart.VcsServerStateText(mServer, False));
  mServer.State := TAtlasVcsServerState.ToolMissing;
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsServerToolMissing),
    TAtlasSettingsVcsServersPart.VcsServerStateText(mServer, False));
end;
procedure TAtlasSettingsPageVcsTests.VcsTexts;
var
  mState: TAtlasVcsProjectState;
  mText: string;
begin
  AssertVcsToolTexts;
  mState := TAtlasVcsProjectState.Empty;
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsProjectNone), TAtlasSettingsVcsProjectPart.VcsProjectText(mState));
  mState.ProjectFile := 'C:\Projekte\Kasse\Kasse.dproj';
  mState.Outcome := TAtlasVcsOutcome.Ok;
  mState.WorkingCopy.Kind := TAtlasVcsKind.Git;
  mState.WorkingCopy.Root := 'C:\Projekte\Kasse';
  mState.Head.Branch := 'feature/42-kasse';
  mState.Head.Revision := '1979e3d795214220705682d5b0b63c8f3b7e66d7';
  mState.Head.Upstream := 'origin/feature/42-kasse';
  mText := TAtlasSettingsVcsProjectPart.VcsProjectText(mState);
  Assert.Contains(mText, 'Kasse.dproj');
  Assert.Contains(mText, 'C:\Projekte\Kasse');
  Assert.Contains(mText, 'feature/42-kasse');
  Assert.Contains(mText, 'origin/feature/42-kasse');
  Assert.Contains(mText, TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsSourceSetting), 'Herkunft der Art');
  mState.Source := TAtlasVcsProviderSource.Project;
  mState.SourceMatch := 'C:\Projekte\Kasse\Kasse.groupproj';
  Assert.Contains(TAtlasSettingsVcsProjectPart.VcsProjectText(mState), 'Kasse.groupproj');
  // #1286: Hauptbranch aus Zeile oder .atlas.
  Assert.DoesNotContain(TAtlasSettingsVcsProjectPart.VcsProjectText(mState),
    TAtlasVcsStrings.Fmt(TAtlasVcsTextId.SettingsVcsProjectMainBranch, ['develop']));
  mState.MainBranch := 'develop';
  Assert.Contains(TAtlasSettingsVcsProjectPart.VcsProjectText(mState),
    TAtlasVcsStrings.Fmt(TAtlasVcsTextId.SettingsVcsProjectMainBranch, ['develop']));
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsProviderSvn), TAtlasSettingsVcsPart.VcsProviderCaption('SVN'));
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsProviderAuto), TAtlasSettingsVcsPart.VcsProviderCaption(''));
  AssertVcsServerTexts;
end;
/// <summary>Kontext: Projekt und Gruppe Kasse, eine Zeile aus der .atlas.</summary>
procedure WireKasseTeamContext(APage: TAtlasSettingsPage);
begin
  GSection.Projects.OnVcsContext :=
    function: TAtlasVcsProjectContext
    begin
      Result := TAtlasVcsProjectContext.Empty;
      Result.ProjectFile := 'C:\Projekte\Kasse\Kasse.dproj';
      Result.GroupFile := 'C:\Projekte\Kasse\Kasse.groupproj';
      Result.Team := [TAtlasVcsProjectMapping.FromTeamFile('C:\Projekte\Kasse\Kasse.dproj', '', 'develop')];
    end;
end;
/// <summary>Persönliche Zeile vor der aus der .atlas; diese nur ansehen.</summary>
procedure AssertVcsProjectRows(APage: TAtlasSettingsPage; AList: TListView);
begin
  // Persönliche Zeile vor der aus der .atlas; die .atlas gewinnt für Kasse.
  Assert.AreEqual(2, AList.Items.Count);
  Assert.AreEqual('C:\Projekte', AList.Items[0].Caption);
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsProviderSvn), AList.Items[0].SubItems[0]);
  Assert.AreEqual('trunk', AList.Items[0].SubItems[1]);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectCovered), AList.Items[0].SubItems[2]);
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsProviderAuto), AList.Items[1].SubItems[0]);
  Assert.AreEqual('develop', AList.Items[1].SubItems[1]);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectTeam), AList.Items[1].SubItems[2]);
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsProjectsCoveredHint), GSection.Projects.VcsProjectNote.Caption);
  Assert.IsTrue(GSection.Projects.VcsProjectMatch.Enabled);
  // Zeile aus der .atlas: nur ansehen.
  AList.Items[1].Selected := True;
  Assert.IsFalse(GSection.Projects.VcsProjectMatch.Enabled);
  Assert.IsFalse(GSection.Projects.VcsProjectProvider.Enabled);
  Assert.IsFalse(GSection.Projects.VcsProjectRemove.Enabled);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectReadOnly), GSection.Projects.VcsProjectNote.Caption);
end;
/// <summary>Aktuelles Projekt übernehmen, Hauptbranch prüfen, doppelten Pfad abweisen.</summary>
procedure EditVcsProjectRows(APage: TAtlasSettingsPage; AList: TListView);
var
  mState: TAtlasVcsProjectState;
begin
  // „Aktuelles Projekt“: die geöffnete Gruppe, Art aus der letzten Abfrage.
  mState := TAtlasVcsProjectState.Empty;
  mState.ProjectFile := 'C:\Projekte\Kasse\Kasse.dproj';
  mState.Outcome := TAtlasVcsOutcome.Ok;
  mState.WorkingCopy.Kind := TAtlasVcsKind.Svn;
  GSection.Project.VcsProjectDone(mState);
  GSection.ProjectAdd.AddCurrentButton.Click;
  Assert.AreEqual(2, Integer(Length(GSection.Projects.VcsProjects)));
  Assert.AreEqual('C:\Projekte\Kasse\Kasse.groupproj', GSection.Projects.VcsProjects[1].Match);
  Assert.AreEqual('svn', GSection.Projects.VcsProjects[1].Provider);
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsProjectsGuess), AList.Items[1].SubItems[1]);
  // Hauptbranch: Leerraum wird abgewiesen.
  GSection.Projects.VcsProjectMainBranch.Text := 'release 1';
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsProjectsBranchInvalid), GSection.Projects.VcsProjectNote.Caption);
  Assert.AreEqual('', GSection.Projects.VcsProjects[1].MainBranch);
  GSection.Projects.VcsProjectMainBranch.Text := 'branches/develop';
  Assert.AreEqual('branches/develop', GSection.Projects.VcsProjects[1].MainBranch);
  Assert.AreEqual('branches/develop', AList.Items[1].SubItems[1]);
  // Derselbe Pfad zweimal wird nicht übernommen.
  GSection.Projects.VcsProjectMatch.Text := 'c:\projekte';
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectMatchTaken), GSection.Projects.VcsProjectNote.Caption);
  Assert.AreEqual('C:\Projekte\Kasse\Kasse.groupproj', GSection.Projects.VcsProjects[1].Match);
end;
/// <summary>Nur persönliche Zeilen landen in vcs.projects.</summary>
procedure AssertVcsProjectsSaved(APage: TAtlasSettingsPage; const ASettings: TAtlasPluginSettings);
var
  mSaved: TAtlasPluginSettings;
  mMappings: TArray<TAtlasVcsProjectMapping>;
begin
  mSaved := ASettings;
  APage.SaveTo(mSaved);
  mMappings := TAtlasVcsProjects.Read(mSaved.VcsProjects);
  Assert.AreEqual(2, Integer(Length(mMappings)), mSaved.VcsProjects);
  Assert.AreEqual('C:\Projekte\Kasse\Kasse.groupproj', mMappings[0].Match);
  Assert.AreEqual('branches/develop', mMappings[0].MainBranch);
  Assert.AreEqual('git', mMappings[1].Provider);
  Assert.IsFalse(mSaved.VcsProjects.Contains('Kasse.dproj'), 'Zeile aus der .atlas bleibt dort');
end;
procedure TAtlasSettingsPageVcsTests.VcsProjectsTable;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
  mList: TListView;
  mBrowsed: string;
begin
  mBrowsed := '';
  mHost := TForm.CreateNew(nil);
  try
    mPage := NewPage(mHost);
    mPage.HandleNeeded;
    WireKasseTeamContext(mPage);
    GSection.ProjectAdd.OnBrowseProject :=
      function(AFolder: Boolean; out APath: string): Boolean
      begin
        mBrowsed := BoolToStr(AFolder, True);
        APath := 'C:\Projekte\Kasse\Pakete\Basis';
        Result := True;
      end;
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.VcsProjects := '[{"match": "C:\\Projekte", "provider": "svn", "mainBranch": "trunk"}]';
    mPage.LoadFrom(mSettings);
    mList := GSection.Projects.VcsProjectList;
    AssertVcsProjectRows(mPage, mList);
    EditVcsProjectRows(mPage, mList);
    // Paketordner aus SVN-Externals über die Ordnerauswahl, dann Art Git.
    GSection.ProjectAdd.AddMenu.Items[1].Click;
    Assert.AreEqual('True', mBrowsed);
    Assert.AreEqual(3, Integer(Length(GSection.Projects.VcsProjects)));
    Assert.AreEqual('C:\Projekte\Kasse\Pakete\Basis', GSection.Projects.VcsProjects[2].Match);
    Assert.AreEqual('auto', GSection.Projects.VcsProjects[2].Provider);
    // Zuweisen löst kein OnChange aus (wie bei der Auswahl mit der Maus erst über das Ereignis).
    GSection.Projects.VcsProjectProvider.Choice := 1;
    GSection.Projects.VcsProjectProvider.OnChange(GSection.Projects.VcsProjectProvider);
    Assert.AreEqual('git', GSection.Projects.VcsProjects[2].Provider);
    Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsProviderGit), mList.Items[2].SubItems[0]);
    // Entfernen, dann speichern: nur persönliche Zeilen landen in vcs.projects.
    mList.Items[0].Selected := True;
    GSection.Projects.VcsProjectRemove.Click;
    Assert.AreEqual(2, Integer(Length(GSection.Projects.VcsProjects)));
    AssertVcsProjectsSaved(mPage, mSettings);
  finally
    mHost.Free;
    FreePage;
  end;
  mBrowsed := '';
end;
/// <summary>Projekt und Gruppe teilen den Ordner: eine Zeile; dazu der Paketordner (SVN-Externals).</summary>
procedure AssertVcsServerRows(AList: TListView);
begin
  // Aktuelles Projekt und Gruppe teilen den Ordner: eine Zeile; dazu der Paketordner (SVN-Externals).
  Assert.AreEqual(2, AList.Items.Count);
  Assert.AreEqual('Kasse.groupproj', AList.Items[0].Caption);
  Assert.AreEqual('–', AList.Items[0].SubItems[0]);
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsServerUnknown), AList.Items[0].SubItems[1]);
  Assert.AreEqual('Basis', AList.Items[1].Caption);
  Assert.AreEqual('https://svn.firma.local/basis', AList.Items[1].SubItems[0]);
  Assert.AreEqual(TAtlasVcsStrings.Fmt(TAtlasVcsTextId.SettingsVcsServerReachable, ['09:30']), AList.Items[1].SubItems[1]);
end;
/// <summary>Prüfergebnis: Git-Server von Kasse verlangt eine Anmeldung.</summary>
function KasseLoginNeeded: TAtlasVcsServerCheck;
begin
  Result := TAtlasVcsServerCheck.Empty;
  Result.Kind := TAtlasVcsKind.Git;
  Result.Root := 'C:\Projekte\Kasse';
  Result.Remote := 'origin';
  Result.Url := 'https://git.firma.local/kasse.git';
  Result.State := TAtlasVcsServerState.LoginNeeded;
end;
/// <summary>Nach der Anmeldung wartet die Zeile auf die neue Prüfung und wird erreichbar.</summary>
procedure AssertVcsLoginRechecked(APage: TAtlasSettingsPage; AList: TListView; const ACheck: TAtlasVcsServerCheck);
var
  mCheck: TAtlasVcsServerCheck;
begin
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsServerLoginOpen), GSection.Servers.VcsServerNote.Caption);
  Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsServerChecking), AList.Items[0].SubItems[1]);
  mCheck := ACheck;
  mCheck.State := TAtlasVcsServerState.Reachable;
  mCheck.CheckedAt := EncodeTime(10, 0, 0, 0);
  GSection.Servers.VcsServerDone('C:\Projekte\Kasse', mCheck);
  Assert.AreEqual(TAtlasVcsStrings.Fmt(TAtlasVcsTextId.SettingsVcsServerReachable, ['10:00']), AList.Items[0].SubItems[1]);
  Assert.IsFalse(GSection.Servers.VcsServerLogin.Enabled);
end;

type
  /// <summary>Hält fest, welche Ordner die Tabelle „Server“ prüfen und anmelden ließ.</summary>
  TVcsServerProbe = class
  public
    FChecked: TArray<string>;
    FLogins: TArray<string>;
  end;

/// <summary>Kontext Kasse, bekannter Zustand des Paketordners, Prüfen und Anmelden über AProbe.</summary>
procedure WireVcsServers(APage: TAtlasSettingsPage; AProbe: TVcsServerProbe);
begin
  GSection.Projects.OnVcsContext :=
    function: TAtlasVcsProjectContext
    begin
      Result := TAtlasVcsProjectContext.Empty;
      Result.ProjectFile := 'C:\Projekte\Kasse\Kasse.dproj';
      Result.GroupFile := 'C:\Projekte\Kasse\Kasse.groupproj';
    end;
  GSection.Servers.OnVcsServerState :=
    function(AFolder: string): TAtlasVcsServerCheck
    begin
      Result := TAtlasVcsServerCheck.Empty;
      // Aus der Sitzung: das Paket war schon erreichbar.
      if SameText(AFolder, 'C:\Projekte\Pakete\Basis') then
      begin
        Result.Kind := TAtlasVcsKind.Svn;
        Result.Url := 'https://svn.firma.local/basis';
        Result.State := TAtlasVcsServerState.Reachable;
        Result.CheckedAt := EncodeTime(9, 30, 0, 0);
      end;
    end;
  GSection.Servers.OnVcsServerCheck :=
    procedure(const AFolder: string)
    begin
      AProbe.FChecked := AProbe.FChecked + [AFolder];
    end;
  GSection.Servers.OnVcsServerLogin :=
    function(const AFolder: string; const ACheck: TAtlasVcsServerCheck): Boolean
    begin
      AProbe.FLogins := AProbe.FLogins + [AFolder + '|' + ACheck.Remote];
      Result := True;
    end;
end;
procedure TAtlasSettingsPageVcsTests.VcsServersTable;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
  mList: TListView;
  mCheck: TAtlasVcsServerCheck;
  mProbe: TVcsServerProbe;
begin
  mProbe := TVcsServerProbe.Create;
  mHost := TForm.CreateNew(nil);
  try
    mPage := NewPage(mHost);
    mPage.HandleNeeded;
    WireVcsServers(mPage, mProbe);
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.VcsProjects := '[{"match": "C:\\Projekte\\Kasse\\Kasse.groupproj", "provider": "svn"},' +
      ' {"match": "C:\\Projekte\\Pakete\\Basis", "provider": "svn"}]';
    mPage.LoadFrom(mSettings);
    mList := GSection.Servers.VcsServerList;
    AssertVcsServerRows(mList);
    Assert.AreEqual(0, Integer(Length(mProbe.FChecked)), 'ohne Klick kein Netzzugriff');
    Assert.IsFalse(GSection.Servers.VcsServerLogin.Enabled);
    // Prüfen der gewählten Zeile.
    GSection.Servers.VcsServerCheck.Click;
    Assert.AreEqual(1, Integer(Length(mProbe.FChecked)));
    Assert.AreEqual('C:\Projekte\Kasse', mProbe.FChecked[0]);
    Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsServerChecking), mList.Items[0].SubItems[1]);
    Assert.IsFalse(GSection.Servers.VcsServerCheck.Enabled, 'läuft schon');
    mCheck := KasseLoginNeeded;
    GSection.Servers.VcsServerDone('c:\projekte\kasse', mCheck);
    Assert.AreEqual('origin · git.firma.local', mList.Items[0].SubItems[0]);
    Assert.AreEqual(TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsServerLoginNeeded), mList.Items[0].SubItems[1]);
    Assert.IsTrue(GSection.Servers.VcsServerLogin.Enabled, 'Anmelden bei „Anmeldung nötig“');
    // „Anmelden …“: Konsole offen, die Zeile wartet auf die neue Prüfung.
    GSection.Servers.VcsServerLogin.Click;
    Assert.AreEqual(1, Integer(Length(mProbe.FLogins)));
    Assert.AreEqual('C:\Projekte\Kasse|origin', mProbe.FLogins[0]);
    AssertVcsLoginRechecked(mPage, mList, mCheck);
    // „Alle prüfen“.
    mProbe.FChecked := nil;
    GSection.Servers.VcsServerCheckAll.Click;
    Assert.AreEqual(2, Integer(Length(mProbe.FChecked)));
    Assert.AreEqual('C:\Projekte\Pakete\Basis', mProbe.FChecked[1]);
    // „prüfen …“ der Willkommensseite für einen Ordner ohne Zeile: Zeile kommt dazu und wird geprüft.
    mProbe.FChecked := nil;
    GSection.Servers.RevealVcsServer('C:\Projekte\Lager\');
    Assert.AreEqual(3, mList.Items.Count);
    Assert.AreEqual('Lager', mList.Items[2].Caption);
    Assert.AreEqual(1, Integer(Length(mProbe.FChecked)));
    Assert.AreEqual('C:\Projekte\Lager', mProbe.FChecked[0]);
  finally
    mHost.Free;
    FreePage;
    mProbe.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPageVcsTests);

end.
