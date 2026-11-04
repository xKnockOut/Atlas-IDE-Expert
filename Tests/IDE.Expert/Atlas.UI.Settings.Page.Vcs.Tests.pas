unit Atlas.UI.Settings.Page.Vcs.Tests;

// Tests der Einstellungsseite: Seite der Versionsverwaltung.

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Seite der Versionsverwaltung.</summary>
  [TestFixture]
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
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Projects.Vcs,
  Atlas.UI.Settings.Page,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Tools,
  Atlas.Core.Vcs.ToolCheck,
  Atlas.Core.Vcs.ServerCheck,
  Atlas.Core.Vcs.ServerAccess,
  System.Generics.Collections,
  Vcl.Forms,
  Vcl.ComCtrls,
  Atlas.UI.Settings.Marks,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Page.TestSupport;

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
  APage.OnVcsLocate :=
    function(AKind: TAtlasVcsKind; const APath: string): TAtlasVcsToolLocation
    begin
      AProbe.FLocated := APath;
      Result := LocateVcsTool(APath);
    end;
  APage.OnVcsCheck :=
    procedure(AKind: TAtlasVcsKind; const APath: string)
    begin
      AProbe.FCheckedKind := AKind;
      AProbe.FCheckedPath := APath;
    end;
  APage.OnVcsProject :=
    procedure
    begin
      Inc(AProbe.FProjectCalls);
    end;
end;
/// <summary>Steuerelemente der Seite: Lage im Baum und geladene Werte (#1285, #1288, #1290–#1292).</summary>
procedure AssertVcsPageControls(APage: TAtlasSettingsPage; AVcs: TTabSheet);
begin
  Assert.IsTrue(SheetOf(APage.VcsPath(TAtlasVcsKind.Git)) = AVcs);
  Assert.IsTrue(SheetOf(APage.VcsPath(TAtlasVcsKind.Svn)) = AVcs);
  Assert.IsTrue(SheetOf(EditOf(APage, 'VcsTimeoutSeconds')) = AVcs);
  Assert.IsTrue(SheetOf(APage.VcsProjectInfo) = AVcs);
  Assert.AreEqual(2, APage.VcsProviderChoice.Choice, 'svn');
  Assert.AreEqual('D:\Tools\svn.exe', APage.VcsPath(TAtlasVcsKind.Svn).Text);
  Assert.AreEqual('45', EditOf(APage, 'VcsTimeoutSeconds').Text);
  // #1288: Dialog „Branch anlegen“ bei „Beginnen“, Unterknoten vcs.branches (Schema).
  Assert.IsTrue(SheetOf(CheckOf(APage, 'VcsBranchConfirm')) = APage.NodeSheet('vcs.branches'));
  Assert.IsTrue(CheckOf(APage, 'VcsBranchConfirm').Checked);
  // #1290: SVN-Gruppe auf derselben Seite, Vorgaben aus den Einstellungen.
  Assert.IsTrue(SheetOf(EditOf(APage, 'VcsBranchSvnLocation')) = APage.NodeSheet('vcs.branches'));
  Assert.IsTrue(SheetOf(EditOf(APage, 'VcsBranchSvnMessage')) = APage.NodeSheet('vcs.branches'));
  Assert.AreEqual('{projektwurzel}/branches/{name}', EditOf(APage, 'VcsBranchSvnLocation').Text);
  Assert.AreEqual(0, APage.VcsBranchSvnSource.Choice, 'head');
  Assert.AreEqual(0, APage.VcsBranchSvnAfter.Choice, 'switch');
  Assert.AreEqual('..\{projekt}-{kennung}', EditOf(APage, 'VcsBranchSvnCheckoutFolder').Text);
  // #1291: Gruppe „Externals“ auf derselben Seite, Regeln als Zeilen; ungültige Zeile mit Hinweis.
  Assert.IsTrue(SheetOf(APage.VcsExternalsRules) = APage.NodeSheet('vcs.externals'));
  Assert.AreEqual(0, APage.VcsExternalsOnBranch.Choice, 'pin');
  Assert.AreEqual(0, APage.VcsExternalsSuggest.Choice, 'modified');
  Assert.AreEqual('', APage.VcsExternalsRules.Text);
  APage.VcsExternalsRules.Text := '^/Packages/Basis = fragen';
  APage.VcsExternalsRules.OnChange(APage.VcsExternalsRules);
  Assert.Contains(APage.VcsExternalsRulesError.Caption, '^/Packages/Basis = fragen');
  APage.VcsExternalsRules.Text := '^/Packages/Basis = keep';
  APage.VcsExternalsRules.OnChange(APage.VcsExternalsRules);
  Assert.AreEqual('', APage.VcsExternalsRulesError.Caption);
  // #1292: Arbeitskopien und Aktualisieren auf derselben Seite.
  Assert.IsTrue(SheetOf(CheckOf(APage, 'VcsExternalsShow')) = APage.NodeSheet('vcs.externals'));
  Assert.IsTrue(CheckOf(APage, 'VcsExternalsShow').Checked);
  Assert.AreEqual(0, APage.VcsExternalsUpdate.Choice, 'with');
end;
/// <summary>Pfad ändern prüft nur die Datei; „Prüfen“ fragt im Hintergrund und sperrt den Knopf bis zum
/// Ergebnis.</summary>
procedure AssertVcsToolChecks(APage: TAtlasSettingsPage; AProbe: TVcsPageProbe);
var
  mCheck: TAtlasVcsToolCheck;
begin
  APage.VcsPath(TAtlasVcsKind.Git).Text := 'X:\fehlt\git.exe';
  APage.VcsPath(TAtlasVcsKind.Git).OnChange(APage.VcsPath(TAtlasVcsKind.Git));
  Assert.AreEqual('X:\fehlt\git.exe', AProbe.FLocated);
  Assert.Contains(APage.VcsState(TAtlasVcsKind.Git).Caption, 'X:\fehlt\git.exe');
  Assert.IsTrue(AProbe.FCheckedKind = TAtlasVcsKind.None, 'Prüfen erst auf Klick');
  APage.VcsPath(TAtlasVcsKind.Git).Text := '';
  APage.VcsPath(TAtlasVcsKind.Git).OnChange(APage.VcsPath(TAtlasVcsKind.Git));
  Assert.Contains(APage.VcsState(TAtlasVcsKind.Git).Caption, 'C:\Program Files\Git\cmd\git.exe');
  APage.VcsCheckButton(TAtlasVcsKind.Svn).Click;
  Assert.IsTrue(AProbe.FCheckedKind = TAtlasVcsKind.Svn);
  Assert.AreEqual('D:\Tools\svn.exe', AProbe.FCheckedPath);
  Assert.IsFalse(APage.VcsCheckButton(TAtlasVcsKind.Svn).Enabled);
  mCheck := TAtlasVcsToolChecks.Missing(TAtlasVcsKind.Svn, TAtlasVcsToolLocation.Empty);
  mCheck.State := TAtlasVcsToolState.Found;
  mCheck.Version := 'svn 1.14.3';
  mCheck.Location.Executable := 'D:\Tools\svn.exe';
  mCheck.Location.Source := TAtlasVcsToolSource.Configured;
  APage.VcsCheckDone(mCheck);
  Assert.IsTrue(APage.VcsCheckButton(TAtlasVcsKind.Svn).Enabled);
  Assert.Contains(APage.VcsState(TAtlasVcsKind.Svn).Caption, 'svn 1.14.3');
end;
/// <summary>Aktuelles Projekt: einmal beim ersten Zeigen der Seite; Links auf die steuernden Seiten.</summary>
procedure AssertVcsProjectAndLinks(APage: TAtlasSettingsPage; AProbe: TVcsPageProbe; const AAreas: TArray<TTreeNode>);
var
  mVcs: TTabSheet;
  mState: TAtlasVcsProjectState;
begin
  mVcs := SheetOf(APage.VcsProviderChoice);
  APage.Navigation.OnChange(APage.Navigation, AAreas[17]);
  Assert.IsTrue(APage.Pages.ActivePage = mVcs);
  Assert.AreEqual(1, AProbe.FProjectCalls);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectQuerying), APage.VcsProjectInfo.Caption);
  APage.Navigation.OnChange(APage.Navigation, AAreas[0]);
  APage.Navigation.OnChange(APage.Navigation, AAreas[17]);
  Assert.AreEqual(1, AProbe.FProjectCalls, 'nur einmal je Öffnen');
  mState := TAtlasVcsProjectState.Empty;
  mState.ProjectFile := 'C:\Projekte\Kasse\Kasse.dproj';
  mState.Outcome := TAtlasVcsOutcome.NoWorkingCopy;
  APage.VcsProjectDone(mState);
  Assert.Contains(APage.VcsProjectInfo.Caption, 'Kasse.dproj');
  APage.VcsLinkWelcome.Click;
  // Ohne das Modul Willkommensseite die Seite seines Schalters (#1456).
  Assert.IsTrue(APage.Pages.ActivePage = SheetOf(APage.ControlOfSetting('WelcomePage')));
  APage.VcsLinkIssues.Click;
  Assert.IsTrue(APage.Pages.ActivePage = SheetOf(APage.ControlOfSetting('IssuesEnabled')));
  APage.VcsLinkEditor.Click;
  Assert.IsFalse(APage.Pages.ActivePage = mVcs, 'Editor-Seite mit Git-Rand');
end;
/// <summary>Alle Werte der Seite ändern.</summary>
procedure EditVcsPage(APage: TAtlasSettingsPage);
begin
  APage.VcsProviderChoice.Choice := 1;
  APage.VcsPath(TAtlasVcsKind.Git).Text := '  D:\Git\git.exe ';
  EditOf(APage, 'VcsTimeoutSeconds').Text := '120';
  CheckOf(APage, 'VcsBranchConfirm').Checked := False;
  EditOf(APage, 'VcsBranchSvnLocation').Text := '^/branches/{kennung}';
  APage.VcsBranchSvnSource.Choice := 1;
  APage.VcsBranchSvnAfter.Choice := 1;
  EditOf(APage, 'VcsBranchSvnCheckoutFolder').Text := 'D:\Branches\{name}';
  EditOf(APage, 'VcsBranchSvnMessage').Text := 'Neu: {kennung}';
  APage.VcsExternalsOnBranch.Choice := 2;
  APage.VcsExternalsSuggest.Choice := 2;
  CheckOf(APage, 'VcsExternalsShow').Checked := False;
  APage.VcsExternalsUpdate.Choice := 1;
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
  APage.VcsExternalsRules.Text := '^/Packages/Basis = keep'#13#10'kaputt';
  APage.SaveTo(ASaved);
  Assert.AreEqual('[{"source": "^/Packages/Basis", "onBranch": "keep"}]', ASaved.VcsExternalsRules);
  APage.LoadFrom(ASaved);
  Assert.AreEqual('^/Packages/Basis = keep', APage.VcsExternalsRules.Text);
  Assert.AreEqual(2, APage.VcsExternalsOnBranch.Choice);
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
  mAreas: TArray<TTreeNode>;
  mVcs: TTabSheet;
  mSettings, mSaved: TAtlasPluginSettings;
  mProbe: TVcsPageProbe;
begin
  TAtlasSettingsPage.ForgetTreeState;
  mProbe := TVcsPageProbe.Create;
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    WireVcsPage(mPage, mProbe);
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.VcsProvider := 'svn';
    mSettings.VcsSvnPath := 'D:\Tools\svn.exe';
    mSettings.VcsTimeoutSeconds := 45;
    mPage.LoadFrom(mSettings);
    mVcs := SheetOf(mPage.VcsProviderChoice);
    Assert.IsNotNull(mVcs);
    mAreas := TopLevelNodes(mPage);
    // Mit Punkt: svn, Pfad und Zeitlimit weichen von der Vorgabe ab.
    Assert.AreEqual(TAtlasSettingsMarks.Dot + TAtlasStrings.Text(TAtlasTextId.SettingsTabVcs), mAreas[17].Text,
      'eigener Bereich');
    AssertVcsPageControls(mPage, mVcs);
    Assert.AreEqual(0, mProbe.FProjectCalls, 'kein Prozess, solange die Seite nicht gezeigt wurde');
    AssertVcsToolChecks(mPage, mProbe);
    AssertVcsProjectAndLinks(mPage, mProbe, mAreas);
    EditVcsPage(mPage);
    mSaved := mSettings;
    AssertVcsPageSaved(mPage, mSaved);
  finally
    mHost.Free;
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
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsToolMissing),
    TAtlasSettingsPage.VcsLocationText(mLocation));
  mLocation.Source := TAtlasVcsToolSource.ConfiguredMissing;
  mLocation.Configured := 'X:\git.exe';
  Assert.Contains(TAtlasSettingsPage.VcsLocationText(mLocation), 'X:\git.exe');
  mLocation.Source := TAtlasVcsToolSource.Path;
  mLocation.Executable := 'C:\Git\cmd\git.exe';
  mText := TAtlasSettingsPage.VcsLocationText(mLocation);
  Assert.Contains(mText, 'C:\Git\cmd\git.exe');
  Assert.Contains(mText, TAtlasSettingsPage.VcsSourceText(TAtlasVcsToolSource.Path));
  mCheck := TAtlasVcsToolChecks.Missing(TAtlasVcsKind.Git, mLocation);
  mCheck.State := TAtlasVcsToolState.StartFailed;
  mCheck.ExitCode := 128;
  Assert.Contains(TAtlasSettingsPage.VcsCheckText(mCheck), '128');
  mCheck.State := TAtlasVcsToolState.NoAnswer;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsToolNoAnswer), TAtlasSettingsPage.VcsCheckText(mCheck));
  mCheck.State := TAtlasVcsToolState.Found;
  mCheck.Version := 'git version 2.47.1';
  mText := TAtlasSettingsPage.VcsCheckText(mCheck);
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
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerUnknown),
    TAtlasSettingsPage.VcsServerStateText(mServer, False));
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerChecking),
    TAtlasSettingsPage.VcsServerStateText(mServer, True));
  mServer.State := TAtlasVcsServerState.Reachable;
  mServer.CheckedAt := EncodeTime(14, 5, 0, 0);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsServerReachable, ['14:05']),
    TAtlasSettingsPage.VcsServerStateText(mServer, False));
  mServer.State := TAtlasVcsServerState.LoginNeeded;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerLoginNeeded),
    TAtlasSettingsPage.VcsServerStateText(mServer, False));
  mServer.State := TAtlasVcsServerState.Unreachable;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerUnreachable),
    TAtlasSettingsPage.VcsServerStateText(mServer, False));
  mServer.State := TAtlasVcsServerState.NoServer;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerNoServer),
    TAtlasSettingsPage.VcsServerStateText(mServer, False));
  mServer.State := TAtlasVcsServerState.ToolMissing;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerToolMissing),
    TAtlasSettingsPage.VcsServerStateText(mServer, False));
end;
procedure TAtlasSettingsPageVcsTests.VcsTexts;
var
  mState: TAtlasVcsProjectState;
  mText: string;
begin
  AssertVcsToolTexts;
  mState := TAtlasVcsProjectState.Empty;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectNone), TAtlasSettingsPage.VcsProjectText(mState));
  mState.ProjectFile := 'C:\Projekte\Kasse\Kasse.dproj';
  mState.Outcome := TAtlasVcsOutcome.Ok;
  mState.WorkingCopy.Kind := TAtlasVcsKind.Git;
  mState.WorkingCopy.Root := 'C:\Projekte\Kasse';
  mState.Head.Branch := 'feature/42-kasse';
  mState.Head.Revision := '1979e3d795214220705682d5b0b63c8f3b7e66d7';
  mState.Head.Upstream := 'origin/feature/42-kasse';
  mText := TAtlasSettingsPage.VcsProjectText(mState);
  Assert.Contains(mText, 'Kasse.dproj');
  Assert.Contains(mText, 'C:\Projekte\Kasse');
  Assert.Contains(mText, 'feature/42-kasse');
  Assert.Contains(mText, 'origin/feature/42-kasse');
  Assert.Contains(mText, TAtlasStrings.Text(TAtlasTextId.SettingsVcsSourceSetting), 'Herkunft der Art');
  mState.Source := TAtlasVcsProviderSource.Project;
  mState.SourceMatch := 'C:\Projekte\Kasse\Kasse.groupproj';
  Assert.Contains(TAtlasSettingsPage.VcsProjectText(mState), 'Kasse.groupproj');
  // #1286: Hauptbranch aus Zeile oder .atlas.
  Assert.DoesNotContain(TAtlasSettingsPage.VcsProjectText(mState),
    TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectMainBranch, ['develop']));
  mState.MainBranch := 'develop';
  Assert.Contains(TAtlasSettingsPage.VcsProjectText(mState),
    TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectMainBranch, ['develop']));
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderSvn), TAtlasSettingsPage.VcsProviderCaption('SVN'));
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderAuto), TAtlasSettingsPage.VcsProviderCaption(''));
  AssertVcsServerTexts;
end;
/// <summary>Kontext: Projekt und Gruppe Kasse, eine Zeile aus der .atlas.</summary>
procedure WireKasseTeamContext(APage: TAtlasSettingsPage);
begin
  APage.OnVcsContext :=
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
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderSvn), AList.Items[0].SubItems[0]);
  Assert.AreEqual('trunk', AList.Items[0].SubItems[1]);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectCovered), AList.Items[0].SubItems[2]);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderAuto), AList.Items[1].SubItems[0]);
  Assert.AreEqual('develop', AList.Items[1].SubItems[1]);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectTeam), AList.Items[1].SubItems[2]);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectsCoveredHint), APage.VcsProjectNote.Caption);
  Assert.IsTrue(APage.VcsProjectMatch.Enabled);
  // Zeile aus der .atlas: nur ansehen.
  AList.Items[1].Selected := True;
  Assert.IsFalse(APage.VcsProjectMatch.Enabled);
  Assert.IsFalse(APage.VcsProjectProvider.Enabled);
  Assert.IsFalse(APage.VcsProjectRemove.Enabled);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectReadOnly), APage.VcsProjectNote.Caption);
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
  APage.VcsProjectDone(mState);
  APage.VcsProjectAddCurrent.Click;
  Assert.AreEqual(2, Integer(Length(APage.VcsProjects)));
  Assert.AreEqual('C:\Projekte\Kasse\Kasse.groupproj', APage.VcsProjects[1].Match);
  Assert.AreEqual('svn', APage.VcsProjects[1].Provider);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectsGuess), AList.Items[1].SubItems[1]);
  // Hauptbranch: Leerraum wird abgewiesen.
  APage.VcsProjectMainBranch.Text := 'release 1';
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectsBranchInvalid), APage.VcsProjectNote.Caption);
  Assert.AreEqual('', APage.VcsProjects[1].MainBranch);
  APage.VcsProjectMainBranch.Text := 'branches/develop';
  Assert.AreEqual('branches/develop', APage.VcsProjects[1].MainBranch);
  Assert.AreEqual('branches/develop', AList.Items[1].SubItems[1]);
  // Derselbe Pfad zweimal wird nicht übernommen.
  APage.VcsProjectMatch.Text := 'c:\projekte';
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectMatchTaken), APage.VcsProjectNote.Caption);
  Assert.AreEqual('C:\Projekte\Kasse\Kasse.groupproj', APage.VcsProjects[1].Match);
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
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    WireKasseTeamContext(mPage);
    mPage.OnBrowseProject :=
      function(AFolder: Boolean; out APath: string): Boolean
      begin
        mBrowsed := BoolToStr(AFolder, True);
        APath := 'C:\Projekte\Kasse\Pakete\Basis';
        Result := True;
      end;
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.VcsProjects := '[{"match": "C:\\Projekte", "provider": "svn", "mainBranch": "trunk"}]';
    mPage.LoadFrom(mSettings);
    mList := mPage.VcsProjectList;
    AssertVcsProjectRows(mPage, mList);
    EditVcsProjectRows(mPage, mList);
    // Paketordner aus SVN-Externals über die Ordnerauswahl, dann Art Git.
    mPage.VcsProjectAddMenu.Items[1].Click;
    Assert.AreEqual('True', mBrowsed);
    Assert.AreEqual(3, Integer(Length(mPage.VcsProjects)));
    Assert.AreEqual('C:\Projekte\Kasse\Pakete\Basis', mPage.VcsProjects[2].Match);
    Assert.AreEqual('auto', mPage.VcsProjects[2].Provider);
    // Zuweisen löst kein OnChange aus (wie bei der Auswahl mit der Maus erst über das Ereignis).
    mPage.VcsProjectProvider.Choice := 1;
    mPage.VcsProjectProvider.OnChange(mPage.VcsProjectProvider);
    Assert.AreEqual('git', mPage.VcsProjects[2].Provider);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderGit), mList.Items[2].SubItems[0]);
    // Entfernen, dann speichern: nur persönliche Zeilen landen in vcs.projects.
    mList.Items[0].Selected := True;
    mPage.VcsProjectRemove.Click;
    Assert.AreEqual(2, Integer(Length(mPage.VcsProjects)));
    AssertVcsProjectsSaved(mPage, mSettings);
  finally
    mHost.Free;
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
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerUnknown), AList.Items[0].SubItems[1]);
  Assert.AreEqual('Basis', AList.Items[1].Caption);
  Assert.AreEqual('https://svn.firma.local/basis', AList.Items[1].SubItems[0]);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsServerReachable, ['09:30']), AList.Items[1].SubItems[1]);
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
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerLoginOpen), APage.VcsServerNote.Caption);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerChecking), AList.Items[0].SubItems[1]);
  mCheck := ACheck;
  mCheck.State := TAtlasVcsServerState.Reachable;
  mCheck.CheckedAt := EncodeTime(10, 0, 0, 0);
  APage.VcsServerDone('C:\Projekte\Kasse', mCheck);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsServerReachable, ['10:00']), AList.Items[0].SubItems[1]);
  Assert.IsFalse(APage.VcsServerLogin.Enabled);
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
  APage.OnVcsContext :=
    function: TAtlasVcsProjectContext
    begin
      Result := TAtlasVcsProjectContext.Empty;
      Result.ProjectFile := 'C:\Projekte\Kasse\Kasse.dproj';
      Result.GroupFile := 'C:\Projekte\Kasse\Kasse.groupproj';
    end;
  APage.OnVcsServerState :=
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
  APage.OnVcsServerCheck :=
    procedure(const AFolder: string)
    begin
      AProbe.FChecked := AProbe.FChecked + [AFolder];
    end;
  APage.OnVcsServerLogin :=
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
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    WireVcsServers(mPage, mProbe);
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.VcsProjects := '[{"match": "C:\\Projekte\\Kasse\\Kasse.groupproj", "provider": "svn"},' +
      ' {"match": "C:\\Projekte\\Pakete\\Basis", "provider": "svn"}]';
    mPage.LoadFrom(mSettings);
    mList := mPage.VcsServerList;
    AssertVcsServerRows(mList);
    Assert.AreEqual(0, Integer(Length(mProbe.FChecked)), 'ohne Klick kein Netzzugriff');
    Assert.IsFalse(mPage.VcsServerLogin.Enabled);
    // Prüfen der gewählten Zeile.
    mPage.VcsServerCheck.Click;
    Assert.AreEqual(1, Integer(Length(mProbe.FChecked)));
    Assert.AreEqual('C:\Projekte\Kasse', mProbe.FChecked[0]);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerChecking), mList.Items[0].SubItems[1]);
    Assert.IsFalse(mPage.VcsServerCheck.Enabled, 'läuft schon');
    mCheck := KasseLoginNeeded;
    mPage.VcsServerDone('c:\projekte\kasse', mCheck);
    Assert.AreEqual('origin · git.firma.local', mList.Items[0].SubItems[0]);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerLoginNeeded), mList.Items[0].SubItems[1]);
    Assert.IsTrue(mPage.VcsServerLogin.Enabled, 'Anmelden bei „Anmeldung nötig“');
    // „Anmelden …“: Konsole offen, die Zeile wartet auf die neue Prüfung.
    mPage.VcsServerLogin.Click;
    Assert.AreEqual(1, Integer(Length(mProbe.FLogins)));
    Assert.AreEqual('C:\Projekte\Kasse|origin', mProbe.FLogins[0]);
    AssertVcsLoginRechecked(mPage, mList, mCheck);
    // „Alle prüfen“.
    mProbe.FChecked := nil;
    mPage.VcsServerCheckAll.Click;
    Assert.AreEqual(2, Integer(Length(mProbe.FChecked)));
    Assert.AreEqual('C:\Projekte\Pakete\Basis', mProbe.FChecked[1]);
    // „prüfen …“ der Willkommensseite für einen Ordner ohne Zeile: Zeile kommt dazu und wird geprüft.
    mProbe.FChecked := nil;
    mPage.RevealVcsServer('C:\Projekte\Lager\');
    Assert.AreEqual(3, mList.Items.Count);
    Assert.AreEqual('Lager', mList.Items[2].Caption);
    Assert.AreEqual(1, Integer(Length(mProbe.FChecked)));
    Assert.AreEqual('C:\Projekte\Lager', mProbe.FChecked[0]);
  finally
    mHost.Free;
    mProbe.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPageVcsTests);

end.
