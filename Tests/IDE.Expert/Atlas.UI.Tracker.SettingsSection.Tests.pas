unit Atlas.UI.Tracker.SettingsSection.Tests;

// Abschnitt des Trackers im Optionsdialog (#1455): Die Optionsseite holt ihn
// vom Anbieter des Moduls und baut ihn in den Reiter Issue-Tracker. Geprüft
// werden Lage, Tabellen (Verbindungen, Projekte, Abfragen, Textbausteine),
// Arbeitsablauf und das Laden und Speichern aller Werte über die Seite.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Modules.Contract,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Tracker.SettingsSection;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TTrackerSettingsSectionTests = class
  private
    FSection: TAtlasTrackerSettingsSection;
    FSectionRef: IAtlasSettingsSection;
    FRegistration: IAtlasRegistration;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure IssuesTrackerOwnPage;
    [Test]
    procedure TrackerConnectionsTable;
    [Test]
    procedure TrackerProjectsTable;
    [Test]
    procedure TrackerQueryEditAndLanguage;
    [Test]
    procedure TrackerQueriesTable;
    [Test]
    procedure TrackerWorkflowSettings;
    [Test]
    procedure TrackerConnectionFieldsByProvider;
    [Test]
    procedure CommentEditorSettings;
    [Test]
    procedure SettingsRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  System.DateUtils,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ComCtrls,
  Vcl.StdCtrls,
  Vcl.Menus,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Projects,
  Atlas.Core.Tracker.Queries,
  Atlas.Core.Tracker.Workflow,
  Atlas.Core.Tracker.CommentEditor,
  Atlas.UI.Settings.Page,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.Strings;

type
  /// <summary>Anbieter der Tests: liefert den vorbereiteten Abschnitt.</summary>
  TFixedProvider = class(TInterfacedObject, IAtlasSettingsSectionProvider)
  private
    FSection: IAtlasSettingsSection;
  public
    constructor Create(const ASection: IAtlasSettingsSection);
    function CreateSection: IAtlasSettingsSection;
  end;

constructor TFixedProvider.Create(const ASection: IAtlasSettingsSection);
begin
  inherited Create;
  FSection := ASection;
end;

function TFixedProvider.CreateSection: IAtlasSettingsSection;
begin
  Result := FSection;
end;

/// <summary>Reiter, auf dem AControl liegt; nil ohne.</summary>
function SheetOf(AControl: TControl): TTabSheet;
begin
  while (AControl <> nil) and not (AControl is TTabSheet) do
    AControl := AControl.Parent;
  Result := TTabSheet(AControl);
end;

/// <summary>Knoten des Baums, der ASheet zeigt; nil ohne.</summary>
function TreeNodeOf(APage: TAtlasSettingsPage; ASheet: TTabSheet): TTreeNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to APage.Navigation.Items.Count - 1 do
  begin
    Result := APage.Navigation.Items[mIndex];
    APage.Navigation.OnChange(APage.Navigation, Result);
    if APage.Pages.ActivePage = ASheet then
      Exit;
  end;
  Result := nil;
end;

function TopLevelNodes(APage: TAtlasSettingsPage): TArray<TTreeNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to APage.Navigation.Items.Count - 1 do
    if APage.Navigation.Items[mIndex].Level = 0 then
      Result := Result + [APage.Navigation.Items[mIndex]];
end;

procedure TTrackerSettingsSectionTests.Setup;
begin
  FSection := TAtlasTrackerSettingsSection.Create;
  FSectionRef := FSection;
  FRegistration := AtlasModuleRegistry.Provide(IAtlasSettingsSectionProvider,
    TFixedProvider.Create(FSectionRef) as IAtlasSettingsSectionProvider);
end;

procedure TTrackerSettingsSectionTests.TearDown;
begin
  FRegistration.Revoke;
  FRegistration := nil;
  FSection := nil;
  FSectionRef := nil;
end;

procedure TTrackerSettingsSectionTests.IssuesTrackerOwnPage;
var
  Host: TForm;
  Page: TAtlasSettingsPage;
  Areas: TArray<TTreeNode>;
  Issues: TTreeNode;
  Tracker: TTabSheet;
begin
  TAtlasSettingsPage.ForgetTreeState;
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSettingsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    Areas := TopLevelNodes(Page);
    Issues := Areas[16];
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabIssues), Issues.Text);
    // Alle Tracker-Einstellungen auf dem Hauptknoten der Seite Issue-Tracker.
    Tracker := SheetOf(FSection.IssuesTracker);
    Assert.IsNotNull(Tracker);
    Assert.AreEqual('', Page.NodeOfSheet(Tracker));
    Assert.IsTrue(TreeNodeOf(Page, Tracker) = Issues, 'Hauptknoten Issue-Tracker');
    Assert.IsTrue(SheetOf(FSection.IssuesQueries) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesStart) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesBranchPattern) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesBranchBase) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesCommitPattern) = Tracker);
    Assert.IsTrue(SheetOf(FSection.TrackerLogin) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesPreview) = Tracker, 'Vorschau (#1264)');
    Assert.IsTrue(SheetOf(FSection.IssuesPreviewComments) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesCodeLinks) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesBlameLinks) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesBlameMaxRevisions) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesPreviewChecklists) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesChecklistStatus) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesPreviewLinks) = Tracker, 'Verknüpfungen (#1279)');
    Assert.IsTrue(SheetOf(FSection.IssuesWarnBlocked) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesBoard) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesBoardConfirmMove) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesBoardOnlyMine) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesSprintBurndown) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesSprintCompare) = Tracker);
    // Sprint-Kachel (#1277): der Bereich auf der Willkommensseite, eigener Knoten welcome.sprint (Schema).
    Assert.IsTrue(SheetOf(Page.WelcomeSprint) = Page.NodeSheet('welcome.sprint'));
    Assert.IsTrue(SheetOf(FSection.IssuesPaletteSearch) = Tracker, 'Palettensuche (#1270)');
    Assert.IsTrue(SheetOf(FSection.IssuesPreviewDevelopment) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesNotify) = Tracker, 'Meldungen (#1271)');
    Assert.IsTrue(SheetOf(FSection.IssuesNotifyInterval) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesNotifyScope) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesAttach) = Tracker, 'Anhängen (#1276)');
    Assert.IsTrue(SheetOf(FSection.IssuesAttachLogFiles) = Tracker);
    Assert.IsTrue(SheetOf(FSection.IssuesAttachMaxImageWidth) = Tracker);
    // Die Willkommensseite behält nur den Schalter, daneben der Weg zur Seite.
    Assert.IsFalse(SheetOf(Page.WelcomeIssues) = Tracker);
    Assert.IsTrue(SheetOf(Page.WelcomeIssuesLink) = SheetOf(Page.WelcomeIssues));
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeIssuesLink), Page.WelcomeIssuesLink.Caption);
    Page.Pages.ActivePage := SheetOf(Page.WelcomeIssues);
    Page.WelcomeIssuesLink.Click;
    Assert.IsTrue(Page.Pages.ActivePage = Tracker, 'Link zeigt die Seite Issue-Tracker');
  finally
    Host.Free;
  end;
end;


procedure TTrackerSettingsSectionTests.TrackerConnectionsTable;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
  mChecked, mRemoved, mToken: string;
  mList: TListView;
begin
  mChecked := '';
  mRemoved := '';
  mToken := '';
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    FSection.OnTrackerState :=
      function(const AConnection: TAtlasTrackerConnection): TAtlasTrackerTokenStatus
      begin
        if AConnection.Provider = 'youtrack' then
          Result := TAtlasTrackerTokenStatus.Create(TAtlasTrackerTokenState.Verified,
            EncodeDate(2026, 10, 28) + EncodeTime(10, 18, 0, 0), 200)
        else
          Result := TAtlasTrackerTokenStatus.Stored(False);
      end;
    FSection.OnTrackerTeam :=
      function: TArray<TAtlasTrackerConnection>
      begin
        Result := [TAtlasTrackerConnection.FromTeamFile('Atlas', TAtlasTrackerTarget.Create('github',
          'https://github.com', 'xKnockOut/Atlas-IDE-Expert', ''))];
      end;
    FSection.OnTrackerToken :=
      procedure(const AConnection: TAtlasTrackerConnection)
      begin
        mToken := AConnection.Name;
      end;
    FSection.OnTrackerCheck :=
      procedure(const AConnection: TAtlasTrackerConnection)
      begin
        mChecked := AConnection.Name;
      end;
    FSection.OnTrackerRemove :=
      procedure(const AConnection: TAtlasTrackerConnection)
      begin
        mRemoved := AConnection.Name;
      end;
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.IssuesConnections := '[{"name": "Firma", "provider": "youtrack", "url": "https://youtrack.firma.local"},' +
      ' {"name": "GitHub", "provider": "github", "url": "https://github.com"}]';
    mPage.LoadFrom(mSettings);
    mList := FSection.IssuesConnections;
    // Abnahme: zwei Verbindungen mit Zustand, dahinter die aus der .atlas.
    Assert.AreEqual(3, mList.Items.Count);
    Assert.AreEqual('Firma', mList.Items[0].Caption);
    Assert.AreEqual('YouTrack', mList.Items[0].SubItems[0]);
    Assert.AreEqual('https://youtrack.firma.local', mList.Items[0].SubItems[1]);
    Assert.AreEqual(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerTokenVerified, ['10:18']), mList.Items[0].SubItems[2]);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTokenMissing), mList.Items[1].SubItems[2]);
    Assert.AreEqual(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SettingsIssuesConnectionTeam, ['Atlas']), mList.Items[2].Caption);
    // Erste Zeile gewählt und bearbeitbar.
    Assert.AreEqual('Firma', FSection.IssuesConnectionName.Text);
    Assert.IsTrue(FSection.IssuesConnectionName.Enabled);
    // Zeile aus der .atlas: nur ansehen, Token und Prüfung gehen.
    mList.Items[2].Selected := True;
    Assert.IsFalse(FSection.IssuesConnectionName.Enabled);
    Assert.IsFalse(FSection.IssuesConnectionUrl.Enabled);
    Assert.IsFalse(FSection.IssuesConnectionRemove.Enabled);
    Assert.IsTrue(FSection.IssuesConnectionToken.Enabled);
    FSection.IssuesConnectionToken.Click;
    Assert.AreEqual('Atlas', mToken);
    // Prüfen: „wird geprüft …“ bis zur Antwort.
    mList.Items[0].Selected := True;
    FSection.IssuesConnectionCheck.Click;
    Assert.AreEqual('Firma', mChecked);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTokenChecking), mList.Items[0].SubItems[2]);
    FSection.TrackerCheckDone(FSection.TrackerConnections[0]);
    Assert.AreEqual(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerTokenVerified, ['10:18']), mList.Items[0].SubItems[2]);
    // Neue Verbindung: erst mit gültiger Adresse gespeichert; http wird abgewiesen.
    FSection.IssuesConnectionAdd.Click;
    Assert.AreEqual(4, mList.Items.Count);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionNew), FSection.IssuesConnectionName.Text);
    mSaved := mSettings;
    mPage.SaveTo(mSaved);
    Assert.AreEqual(2, Integer(Length(TAtlasTrackerConnections.Read(mSaved.IssuesConnections))), 'ohne Adresse');
    FSection.IssuesConnectionUrl.Text := 'http://yt2.firma.local';
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionUrlHttps),
      FSection.IssuesConnectionNote.Caption);
    Assert.AreEqual('', FSection.TrackerConnections[2].Url);
    FSection.IssuesConnectionUrl.Text := 'https://marco@yt2.firma.local';
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionUrlUser),
      FSection.IssuesConnectionNote.Caption);
    FSection.IssuesConnectionUrl.Text := 'https://yt2.firma.local/';
    Assert.AreEqual('', FSection.IssuesConnectionNote.Caption);
    Assert.AreEqual('https://yt2.firma.local', FSection.TrackerConnections[2].Url);
    // Vergebener Name wird nicht übernommen.
    FSection.IssuesConnectionName.Text := 'firma';
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionNameTaken),
      FSection.IssuesConnectionNote.Caption);
    FSection.IssuesConnectionName.Text := 'Lager';
    Assert.AreEqual('Lager', FSection.TrackerConnections[2].Name);
    mPage.SaveTo(mSaved);
    Assert.AreEqual(3, Integer(Length(TAtlasTrackerConnections.Read(mSaved.IssuesConnections))));
    Assert.IsTrue(mSaved.IssuesConnections.Contains('"Lager"'), mSaved.IssuesConnections);
    Assert.IsFalse(mSaved.IssuesConnections.Contains('Atlas'), 'Verbindung aus der .atlas bleibt dort');
    // Entfernen fragt über den Haken (Token) und nimmt die Zeile heraus.
    mList.Items[1].Selected := True;
    FSection.IssuesConnectionRemove.Click;
    Assert.AreEqual('GitHub', mRemoved);
    mPage.SaveTo(mSaved);
    Assert.AreEqual(2, Integer(Length(TAtlasTrackerConnections.Read(mSaved.IssuesConnections))));
    Assert.IsFalse(mSaved.IssuesConnections.Contains('"GitHub"'), mSaved.IssuesConnections);
  finally
    mHost.Free;
  end;
  mChecked := '';
  mRemoved := '';
  mToken := '';
end;


procedure TTrackerSettingsSectionTests.TrackerProjectsTable;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
  mList: TListView;
  mBrowsed: string;
  mMappings: TArray<TAtlasTrackerProjectMapping>;
begin
  mBrowsed := '';
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    FSection.OnTrackerContext :=
      function: TAtlasTrackerProjectContext
      begin
        Result := TAtlasTrackerProjectContext.Empty;
        Result.ProjectFile := 'C:\Projekte\Kasse\Kasse.dproj';
        Result.GroupFile := 'C:\Projekte\Kasse\Kasse.groupproj';
        Result.Team := [TAtlasTrackerProjectMapping.FromTeamFile('C:\Projekte\Kasse\Kasse.dproj', 'Kasse',
          'xKnockOut/Kasse')];
      end;
    FSection.OnTrackerBrowse :=
      function(AFolder: Boolean; out APath: string): Boolean
      begin
        mBrowsed := BoolToStr(AFolder, True);
        APath := 'C:\Projekte\Lager\Lager.dproj';
        Result := True;
      end;
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.IssuesConnections := '[{"name": "Firma", "provider": "youtrack", "url": "https://youtrack.firma.local"},' +
      ' {"name": "GitHub", "provider": "github", "url": "https://github.com"}]';
    mSettings.IssuesProjects := '[{"match": "C:\\Projekte", "connection": "Firma", "project": "KASSE"}]';
    mPage.LoadFrom(mSettings);
    mList := FSection.IssuesProjects;
    // Abnahme: persönliche Zeile vor der aus der .atlas; die .atlas gewinnt für Kasse.
    Assert.AreEqual(2, mList.Items.Count);
    Assert.AreEqual('C:\Projekte', mList.Items[0].Caption);
    Assert.AreEqual('Firma', mList.Items[0].SubItems[0]);
    Assert.AreEqual('KASSE', mList.Items[0].SubItems[1]);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectCovered), mList.Items[0].SubItems[2]);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectTeam), mList.Items[1].SubItems[2]);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesProjectCoveredHint),
      FSection.IssuesProjectNote.Caption);
    Assert.IsTrue(FSection.IssuesProjectMatch.Enabled);
    Assert.IsTrue(FSection.IssuesProjectAddCurrent.Enabled);
    // Zeile aus der .atlas: nur ansehen.
    mList.Items[1].Selected := True;
    Assert.IsFalse(FSection.IssuesProjectMatch.Enabled);
    Assert.IsFalse(FSection.IssuesProjectRemove.Enabled);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectReadOnly),
      FSection.IssuesProjectNote.Caption);
    // „Aktuelles Projekt“: die geöffnete Gruppe, vorbelegt mit der ersten Verbindung.
    FSection.IssuesProjectAddCurrent.Click;
    Assert.AreEqual(2, Integer(Length(FSection.TrackerProjects)));
    Assert.AreEqual('C:\Projekte\Kasse\Kasse.groupproj', FSection.TrackerProjects[1].Match);
    Assert.AreEqual('Firma', FSection.TrackerProjects[1].Connection);
    Assert.AreEqual('C:\Projekte\Kasse\Kasse.groupproj', FSection.IssuesProjectMatch.Text);
    FSection.IssuesProjectProject.Text := 'LAGER';
    Assert.AreEqual('LAGER', FSection.TrackerProjects[1].Project);
    // Derselbe Pfad zweimal wird nicht übernommen.
    FSection.IssuesProjectMatch.Text := 'c:\projekte';
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectMatchTaken),
      FSection.IssuesProjectNote.Caption);
    Assert.AreEqual('C:\Projekte\Kasse\Kasse.groupproj', FSection.TrackerProjects[1].Match);
    // Hinzufügen über die Dateiauswahl.
    FSection.IssuesProjectAddMenu.Items[0].Click;
    Assert.AreEqual('False', mBrowsed);
    Assert.AreEqual(3, Integer(Length(FSection.TrackerProjects)));
    Assert.AreEqual('C:\Projekte\Lager\Lager.dproj', FSection.TrackerProjects[2].Match);
    // Aus „Meine Issues“: vorhandene Zeile wird gewählt, keine zweite angelegt.
    FSection.AssignTrackerProject('C:\Projekte');
    Assert.AreEqual(3, Integer(Length(FSection.TrackerProjects)));
    Assert.AreEqual('C:\Projekte', FSection.IssuesProjectMatch.Text);
    // Verbindung umbenennen: die Zuordnungen ziehen mit.
    FSection.IssuesConnections.Items[0].Selected := True;
    FSection.IssuesConnectionName.Text := 'Werk';
    Assert.AreEqual('Werk', FSection.TrackerProjects[0].Connection);
    Assert.AreEqual('Werk', mList.Items[0].SubItems[0]);
    // Entfernen, dann speichern: nur die persönlichen Zeilen landen in issues.projects.
    mList.Items[2].Selected := True;
    FSection.IssuesProjectRemove.Click;
    Assert.AreEqual(2, Integer(Length(FSection.TrackerProjects)));
    mSaved := mSettings;
    mPage.SaveTo(mSaved);
    mMappings := TAtlasTrackerProjects.Read(mSaved.IssuesProjects);
    Assert.AreEqual(2, Integer(Length(mMappings)), mSaved.IssuesProjects);
    Assert.AreEqual('C:\Projekte', mMappings[0].Match);
    Assert.AreEqual('Werk', mMappings[0].Connection);
    Assert.AreEqual('C:\Projekte\Kasse\Kasse.groupproj', mMappings[1].Match);
    Assert.AreEqual('LAGER', mMappings[1].Project);
    Assert.IsFalse(mSaved.IssuesProjects.Contains('xKnockOut/Kasse'), 'Zeile aus der .atlas bleibt dort');
  finally
    mHost.Free;
  end;
  mBrowsed := '';
  mMappings := nil;
end;


procedure TTrackerSettingsSectionTests.TrackerQueryEditAndLanguage;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
  mSeenTaken: string;
  mSeenConnections: Integer;
begin
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.IssuesConnections := '[{"name": "Firma", "provider": "youtrack", "url": "https://yt.local"}]';
    mSettings.IssuesQueries := '[{"name": "Standard", "query": "assignee: me #Unresolved"},' +
      ' {"name": "Sprint", "query": "s"}]';
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(FSection.IssuesQueryEdit.Enabled, 'erste Zeile gewählt');
    mSeenTaken := '';
    mSeenConnections := 0;
    FSection.OnTrackerQueryEdit :=
      function(var AQuery: TAtlasTrackerQuery; const AConnections: TArray<TAtlasTrackerConnection>;
        const ATaken: TArray<string>): Boolean
      begin
        mSeenTaken := string.Join(';', ATaken);
        mSeenConnections := Length(AConnections);
        AQuery := TAtlasTrackerQuery.Create(AQuery.Name, 'assignee: meine #Ungelöst', 'Firma', 'ATL');
        Result := True;
      end;
    FSection.IssuesQueryEdit.Click;
    Assert.AreEqual('Sprint', mSeenTaken, 'Namen der übrigen Zeilen');
    Assert.AreEqual(1, mSeenConnections);
    Assert.AreEqual('assignee: meine #Ungelöst', FSection.IssuesQueries.Items[0].SubItems[0]);
    Assert.AreEqual('Firma', FSection.IssuesQueries.Items[0].SubItems[1]);
    Assert.AreEqual('assignee: meine #Ungelöst', FSection.IssuesQueryText.Text);
    // Abbrechen ändert nichts.
    FSection.OnTrackerQueryEdit :=
      function(var AQuery: TAtlasTrackerQuery; const AConnections: TArray<TAtlasTrackerConnection>;
        const ATaken: TArray<string>): Boolean
      begin
        AQuery.Query := 'verworfen';
        Result := False;
      end;
    FSection.IssuesQueryEdit.Click;
    Assert.AreEqual('assignee: meine #Ungelöst', FSection.TrackerQueries[0].Query);
    // „Prüfen“ hat die Sprache erkannt: Sie kommt mit OK in settings.json.
    FSection.OnTrackerState :=
      function(const AConnection: TAtlasTrackerConnection): TAtlasTrackerTokenStatus
      begin
        Result := TAtlasTrackerTokenStatus.Create(TAtlasTrackerTokenState.Verified, Now, 200);
        Result.Language := 'de';
      end;
    FSection.TrackerCheckDone(FSection.TrackerConnections[0]);
    Assert.AreEqual('de', FSection.TrackerConnections[0].Language);
    mSaved := mSettings;
    mPage.SaveTo(mSaved);
    Assert.IsTrue(mSaved.IssuesConnections.Contains('"language": "de"'), mSaved.IssuesConnections);
    FSection.OnTrackerQueryEdit := nil;
    FSection.OnTrackerState := nil;
  finally
    mHost.Free;
  end;
  mSeenTaken := '';
end;


procedure TTrackerSettingsSectionTests.TrackerQueriesTable;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
  mList: TListView;
  mQueries: TArray<TAtlasTrackerQuery>;
begin
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.IssuesConnections := '[{"name": "Firma", "provider": "youtrack", "url": "https://youtrack.firma.local"}]';
    mPage.LoadFrom(mSettings);
    // Ohne eigene Abfragen: Hinweis auf die Vorgabe je Anbieter.
    Assert.AreEqual(0, FSection.IssuesQueries.Items.Count);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueriesNone), FSection.IssuesQueryNote.Caption);
    Assert.IsFalse(FSection.IssuesQueryName.Enabled);
    mSettings.IssuesQueries := '[{"name": "Standard", "query": "assignee: meine #Ungelöst"},' +
      ' {"name": "Sprint", "query": "#{Aktueller Sprint}", "connection": "Firma", "project": "KASSE"}]';
    mPage.LoadFrom(mSettings);
    mList := FSection.IssuesQueries;
    Assert.AreEqual(2, mList.Items.Count);
    Assert.AreEqual('Standard', mList.Items[0].Caption);
    Assert.AreEqual('assignee: meine #Ungelöst', mList.Items[0].SubItems[0]);
    Assert.AreEqual('', mList.Items[0].SubItems[1], 'ohne Verbindung: überall');
    Assert.AreEqual('Firma', mList.Items[1].SubItems[1]);
    Assert.AreEqual('KASSE', mList.Items[1].SubItems[2]);
    // Erste Zeile gewählt; „(alle)“ als Verbindung.
    Assert.AreEqual('Standard', FSection.IssuesQueryName.Text);
    Assert.AreEqual(0, FSection.IssuesQueryConnection.Choice);
    mList.Items[1].Selected := True;
    Assert.AreEqual('#{Aktueller Sprint}', FSection.IssuesQueryText.Text);
    Assert.AreEqual(1, FSection.IssuesQueryConnection.Choice);
    // Doppelter Name wird nicht übernommen.
    FSection.IssuesQueryName.Text := 'standard';
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueryNameTaken), FSection.IssuesQueryNote.Caption);
    Assert.AreEqual('Sprint', FSection.TrackerQueries[1].Name);
    FSection.IssuesQueryName.Text := 'Aktueller Sprint';
    Assert.AreEqual('Aktueller Sprint', mList.Items[1].Caption);
    // Neue Zeile: ohne Abfrage nicht gespeichert; Leerraum außen fällt weg.
    FSection.IssuesQueryAdd.Click;
    Assert.AreEqual(3, mList.Items.Count);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueryNew), FSection.IssuesQueryName.Text);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueryEmpty), FSection.IssuesQueryNote.Caption);
    mSaved := mSettings;
    mPage.SaveTo(mSaved);
    Assert.AreEqual(2, Integer(Length(TAtlasTrackerQueries.Read(mSaved.IssuesQueries))), 'ohne Abfrage');
    FSection.IssuesQueryText.Text := '  created by: me #Unresolved ';
    Assert.AreEqual('created by: me #Unresolved', FSection.TrackerQueries[2].Query);
    Assert.AreEqual('', FSection.IssuesQueryNote.Caption);
    // Verbindung umbenennen: die Abfrage zieht mit.
    FSection.IssuesConnections.Items[0].Selected := True;
    FSection.IssuesConnectionName.Text := 'Werk';
    Assert.AreEqual('Werk', FSection.TrackerQueries[1].Connection);
    // Entfernen, Klappliste aus, speichern.
    mList.Items[0].Selected := True;
    FSection.IssuesQueryRemove.Click;
    FSection.IssuesQueryPicker.Checked := False;
    mPage.SaveTo(mSaved);
    mQueries := TAtlasTrackerQueries.Read(mSaved.IssuesQueries);
    Assert.AreEqual(2, Integer(Length(mQueries)), mSaved.IssuesQueries);
    Assert.AreEqual('Aktueller Sprint', mQueries[0].Name);
    Assert.AreEqual('Werk', mQueries[0].Connection);
    Assert.AreEqual('KASSE', mQueries[0].Project);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueryNew), mQueries[1].Name);
    Assert.IsFalse(mSaved.IssuesQueryPicker);
  finally
    mHost.Free;
  end;
  mQueries := nil;
end;


procedure TTrackerSettingsSectionTests.TrackerWorkflowSettings;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
  mAsked, mField: string;
  mValues: TAtlasTrackerValueSet;
  mRead: TArray<TAtlasTrackerConnection>;
begin
  mAsked := '';
  mField := '';
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    // Alle Steuerelemente auf der Seite Issue-Tracker.
    Assert.IsTrue(SheetOf(FSection.IssuesSyncState) = SheetOf(FSection.IssuesTracker));
    Assert.IsTrue(SheetOf(FSection.IssuesEndComment) = SheetOf(FSection.IssuesTracker));
    Assert.IsTrue(SheetOf(FSection.IssuesConnectionStateField) = SheetOf(FSection.IssuesTracker));
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.IssuesStartState := 'In Arbeit';
    mSettings.IssuesAssignOnStart := True;
    mSettings.IssuesEndStates := 'Zur Prüfung, Erledigt';
    mSettings.IssuesConnections := '[{"name": "Firma", "provider": "youtrack", "url": "https://youtrack.firma.local",' +
      ' "stateField": "Status", "endStates": ["Geprüft"]}]';
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(FSection.IssuesSyncState.Checked);
    Assert.AreEqual('State', FSection.IssuesStateField.Value);
    Assert.AreEqual('In Arbeit', FSection.IssuesStartState.Value);
    Assert.IsTrue(FSection.IssuesAssignOnStart.Checked);
    Assert.AreEqual('Zur Prüfung, Erledigt', FSection.IssuesEndStates.Text);
    Assert.AreEqual('Erledigt in {branch}.\n{commits}', FSection.IssuesEndComment.Text);
    // Gewählte Verbindung: ihre Werte, leer = global.
    Assert.AreEqual('Status', FSection.IssuesConnectionStateField.Value);
    Assert.AreEqual('', FSection.IssuesConnectionStartState.Value);
    Assert.AreEqual('Geprüft', FSection.IssuesConnectionEndStates.Text);
    Assert.IsTrue(FSection.IssuesConnectionStateField.Enabled);
    FSection.IssuesConnectionEndStates.Text := 'Geprüft; Abgelehnt';
    Assert.AreEqual(2, Integer(Length(FSection.TrackerConnections[0].EndStates)));
    // Andere Adresse: Zustandsfeld und Zielzustände der Verbindung bleiben (WithUrl).
    FSection.IssuesConnectionUrl.Text := 'https://yt.firma.local';
    Assert.AreEqual('Status', FSection.TrackerConnections[0].StateField);
    Assert.AreEqual('Abgelehnt', FSection.TrackerConnections[0].EndStates[1]);
    // Speichern.
    FSection.IssuesSyncState.Checked := False;
    FSection.IssuesStateField.Value := ' Status ';
    FSection.IssuesEndStates.Text := 'Zur Prüfung;; Erledigt';
    FSection.IssuesEndComment.Text := 'Fertig: {pr}';
    mSaved := mSettings;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.IssuesSyncState);
    Assert.AreEqual('Status', mSaved.IssuesStateField);
    Assert.AreEqual('Zur Prüfung, Erledigt', mSaved.IssuesEndStates);
    Assert.AreEqual('Fertig: {pr}', mSaved.IssuesEndComment);
    mRead := TAtlasTrackerConnections.Read(mSaved.IssuesConnections);
    Assert.AreEqual('https://yt.firma.local', mRead[0].Url);
    Assert.AreEqual('Status', mRead[0].StateField);
    Assert.AreEqual(2, Integer(Length(mRead[0].EndStates)));
    // „Werte vom Tracker laden“: gewählte Verbindung, Zustandsfeld der Verbindung; Ergebnis als Vorschläge.
    FSection.IssuesLoadValues.Click;
    Assert.AreEqual('', mAsked, 'ohne Haken nichts');
    FSection.OnTrackerValues :=
      procedure(const AConnection: TAtlasTrackerConnection; const AStateField: string)
      begin
        mAsked := AConnection.Name;
        mField := AStateField;
      end;
    FSection.IssuesLoadValues.Click;
    Assert.AreEqual('Firma', mAsked);
    Assert.AreEqual('Status', mField);
    Assert.IsFalse(FSection.IssuesLoadValues.Enabled, 'bis zur Antwort');
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesValuesLoading), FSection.IssuesValuesNote.Caption);
    mValues := Default(TAtlasTrackerValueSet);
    mValues.States := TArray<string>.Create('Offen', 'In Arbeit');
    mValues.StateFields := TArray<string>.Create('Status');
    mValues.UserFields := TArray<string>.Create('Zuständig');
    FSection.TrackerValuesDone(mValues, '');
    Assert.IsTrue(FSection.IssuesLoadValues.Enabled);
    Assert.AreEqual(2, Integer(Length(FSection.IssuesStartState.Values)));
    Assert.AreEqual('Zuständig', FSection.IssuesAssigneeField.Values[0]);
    Assert.AreEqual('Status', FSection.IssuesConnectionStateField.Values[0]);
    Assert.AreEqual('Status', FSection.IssuesStateField.Value, 'eingegebener Text bleibt');
    Assert.AreEqual(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SettingsIssuesValuesLoaded, [2, 2]), FSection.IssuesValuesNote.Caption);
    FSection.TrackerValuesDone(Default(TAtlasTrackerValueSet), 'Keine Rechte');
    Assert.AreEqual(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SettingsIssuesValuesFailed, ['Keine Rechte']),
      FSection.IssuesValuesNote.Caption);
    Assert.AreEqual(2, Integer(Length(FSection.IssuesStartState.Values)), 'Fehler lässt die Vorschläge');
  finally
    mHost.Free;
  end;
  mAsked := '';
  mField := '';
end;


procedure TTrackerSettingsSectionTests.TrackerConnectionFieldsByProvider;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
  mList: TListView;
begin
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    // Zeilen so hoch wie Name und Adresse: vorher 180 bzw. 376 Pixel hoch.
    Assert.AreEqual(FSection.IssuesConnectionName.Parent.Height, FSection.IssuesConnectionStateRow.Height);
    Assert.AreEqual(FSection.IssuesConnectionName.Parent.Height, FSection.IssuesConnectionAssigneeRow.Height);
    Assert.AreEqual(FSection.IssuesConnectionName.Parent.Height, FSection.IssuesConnectionStartState.Parent.Height);
    Assert.AreEqual(FSection.IssuesConnectionName.Parent.Height, FSection.IssuesConnectionEndStates.Parent.Height);
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.IssuesConnections := '[{"name": "Firma", "provider": "youtrack", "url": "https://youtrack.firma.local"},' +
      ' {"name": "GitHub", "provider": "github", "url": "https://github.com"}]';
    mPage.LoadFrom(mSettings);
    mList := FSection.IssuesConnections;
    // YouTrack: Felder sichtbar.
    Assert.AreEqual('Firma', FSection.IssuesConnectionName.Text);
    Assert.IsTrue(FSection.IssuesConnectionStateRow.Visible, 'YouTrack Zustandsfeld');
    Assert.IsTrue(FSection.IssuesConnectionAssigneeRow.Visible, 'YouTrack Benutzerfeld');
    // GitHub kennt keine Felder; Zustand beim Beginnen und Zielzustände (Labels) bleiben.
    mList.Items[1].Selected := True;
    Assert.AreEqual('GitHub', FSection.IssuesConnectionName.Text);
    Assert.IsFalse(FSection.IssuesConnectionStateRow.Visible, 'GitHub Zustandsfeld');
    Assert.IsFalse(FSection.IssuesConnectionAssigneeRow.Visible, 'GitHub Benutzerfeld');
    Assert.IsTrue(FSection.IssuesConnectionStartState.Parent.Visible);
    Assert.IsTrue(FSection.IssuesConnectionEndStates.Parent.Visible);
    // Anbieter wechseln (wie eine Auswahl in der Klappliste): GitHub nach YouTrack und zurück.
    FSection.IssuesConnectionProvider.Choice := 0;
    FSection.IssuesConnectionProvider.OnChange(FSection.IssuesConnectionProvider);
    Assert.AreEqual('youtrack', FSection.TrackerConnections[1].Provider);
    Assert.IsTrue(FSection.IssuesConnectionStateRow.Visible, 'nach Wechsel zu YouTrack');
    FSection.IssuesConnectionProvider.Choice := 1;
    FSection.IssuesConnectionProvider.OnChange(FSection.IssuesConnectionProvider);
    Assert.AreEqual('github', FSection.TrackerConnections[1].Provider);
    Assert.IsFalse(FSection.IssuesConnectionAssigneeRow.Visible, 'nach Wechsel zu GitHub');
  finally
    mHost.Free;
  end;
end;


procedure TTrackerSettingsSectionTests.CommentEditorSettings;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
  mRead: TArray<TAtlasCommentSnippet>;
begin
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    Assert.IsTrue(SheetOf(FSection.IssuesCommentEditor) = SheetOf(FSection.IssuesTracker));
    Assert.IsTrue(SheetOf(FSection.IssuesSnippets) = SheetOf(FSection.IssuesTracker));
    mSettings := TAtlasPluginSettings.Defaults;
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(FSection.IssuesCommentEditor.Checked);
    Assert.AreEqual(2, FSection.IssuesSnippets.Items.Count, 'zwei Vorgaben');
    Assert.AreEqual('Bitte mit aktuellem Build prüfen', FSection.IssuesSnippets.Items[0].Caption);
    Assert.AreEqual('Bitte mit aktuellem Build prüfen', FSection.IssuesSnippetName.Text, 'erste Zeile gewählt');
    // Hinzufügen, Name und mehrzeiligen Text eingeben.
    FSection.IssuesSnippetAdd.Click;
    Assert.AreEqual(3, FSection.IssuesSnippets.Items.Count);
    Assert.AreEqual('Neuer Textbaustein', FSection.IssuesSnippetName.Text);
    FSection.IssuesSnippetName.Text := 'Version';
    FSection.IssuesSnippetText.Text := 'In {version}'#13#10'bitte prüfen';
    Assert.AreEqual('Version', FSection.IssuesSnippets.Items[2].Caption);
    Assert.AreEqual('In {version} ⏎ bitte prüfen', FSection.IssuesSnippets.Items[2].SubItems[0]);
    // Den ersten entfernen.
    FSection.IssuesSnippets.Items[0].Selected := True;
    FSection.IssuesSnippetRemove.Click;
    Assert.AreEqual(2, FSection.IssuesSnippets.Items.Count);
    FSection.IssuesCommentEditor.Checked := False;
    mSaved := mSettings;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.IssuesCommentEditor);
    Assert.IsTrue(TAtlasCommentSnippets.Parse(mSaved.IssuesCommentSnippets, mRead));
    Assert.AreEqual(2, Integer(Length(mRead)));
    Assert.AreEqual('Behoben in {commit}', mRead[0].Name);
    Assert.AreEqual('In {version}'#10'bitte prüfen', mRead[1].Text, 'Zeilen mit #10');
    // Vorgaben stellen die Liste wieder her; geladen wird, was gespeichert war.
    FSection.IssuesSnippetDefaults.Click;
    Assert.AreEqual(2, FSection.IssuesSnippets.Items.Count);
    Assert.AreEqual('Bitte mit aktuellem Build prüfen', FSection.IssuesSnippets.Items[0].Caption);
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(FSection.IssuesCommentEditor.Checked);
    Assert.AreEqual('Version', FSection.IssuesSnippets.Items[1].Caption);
    // Leere Liste bleibt leer: Felder gesperrt.
    mSaved.IssuesCommentSnippets := '[]';
    mPage.LoadFrom(mSaved);
    Assert.AreEqual(0, FSection.IssuesSnippets.Items.Count);
    Assert.IsFalse(FSection.IssuesSnippetName.Enabled);
    Assert.IsFalse(FSection.IssuesSnippetRemove.Enabled);
  finally
    mHost.Free;
  end;
  mRead := nil;
end;


procedure TTrackerSettingsSectionTests.SettingsRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.AreEqual(0, FSection.IssuesTracker.Choice);
    Assert.IsTrue(FSection.IssuesQueryPicker.Checked, 'Klappliste an (#1262)');
    Assert.IsTrue(FSection.IssuesCreate.Checked, '„Issue anlegen …“ an (#1268)');
    Assert.IsTrue(FSection.IssuesCreateIncludeCode.Checked, 'Codeausschnitt vorgeschlagen (#1268)');
    Assert.AreEqual(0, FSection.IssuesStart.Choice);
    Assert.AreEqual('', FSection.IssuesBranchPattern.Text);
    Assert.AreEqual('', FSection.IssuesBranchBase.Text);
    Assert.AreEqual('{kennung} ', FSection.IssuesCommitPattern.Text);
    Assert.IsTrue(FSection.TrackerLogin.Checked);
    Assert.IsTrue(FSection.IssuesPreview.Checked);
    Assert.IsTrue(FSection.IssuesPreviewComments.Checked);
    Assert.IsTrue(FSection.IssuesCodeLinks.Checked);
    Assert.IsTrue(FSection.IssuesBlameLinks.Checked);
    Assert.AreEqual('200', FSection.IssuesBlameMaxRevisions.Text);
    Assert.IsTrue(FSection.IssuesPreviewChecklists.Checked);
    Assert.IsTrue(FSection.IssuesChecklistStatus.Checked);
    Assert.IsTrue(FSection.IssuesPreviewLinks.Checked);
    Assert.IsTrue(FSection.IssuesWarnBlocked.Checked);
    Assert.IsTrue(FSection.IssuesBoard.Checked);
    Assert.IsTrue(FSection.IssuesBoardConfirmMove.Checked);
    Assert.IsTrue(FSection.IssuesBoardOnlyMine.Checked);
    Assert.IsTrue(FSection.IssuesSprintBurndown.Checked);
    Assert.IsTrue(FSection.IssuesSprintCompare.Checked);
    Assert.IsTrue(FSection.IssuesPaletteSearch.Checked);
    Assert.IsTrue(FSection.IssuesPreviewDevelopment.Checked);
    Assert.IsFalse(FSection.IssuesNotify.Checked);
    Assert.AreEqual('10', FSection.IssuesNotifyInterval.Text);
    Assert.AreEqual(1, FSection.IssuesNotifyScope.Choice);
    Assert.IsTrue(FSection.IssuesAttach.Checked);
    Assert.AreEqual('', FSection.IssuesAttachLogFiles.Text);
    Assert.AreEqual('1920', FSection.IssuesAttachMaxImageWidth.Text);
    FSection.IssuesTracker.Choice := 2;
    FSection.IssuesQueryPicker.Checked := False;
    FSection.IssuesCreate.Checked := False;
    FSection.IssuesCreateIncludeCode.Checked := False;
    FSection.IssuesStart.Choice := 1;
    FSection.IssuesBranchPattern.Text := ' {kennung}/{kurztitel} ';
    FSection.IssuesBranchBase.Text := ' develop ';
    FSection.IssuesCommitPattern.Text := '[{kennung}] ';
    FSection.TrackerLogin.Checked := False;
    FSection.IssuesPreviewComments.Checked := False;
    FSection.IssuesCodeLinks.Checked := False;
    FSection.IssuesBlameLinks.Checked := False;
    FSection.IssuesBlameMaxRevisions.Text := '50';
    FSection.IssuesPreviewChecklists.Checked := False;
    FSection.IssuesChecklistStatus.Checked := False;
    FSection.IssuesPreviewLinks.Checked := False;
    FSection.IssuesWarnBlocked.Checked := False;
    FSection.IssuesBoard.Checked := False;
    FSection.IssuesBoardConfirmMove.Checked := False;
    FSection.IssuesBoardOnlyMine.Checked := False;
    FSection.IssuesSprintBurndown.Checked := False;
    FSection.IssuesSprintCompare.Checked := False;
    FSection.IssuesPaletteSearch.Checked := False;
    FSection.IssuesPreviewDevelopment.Checked := False;
    FSection.IssuesNotify.Checked := True;
    FSection.IssuesNotifyInterval.Text := ' 15 ';
    FSection.IssuesNotifyScope.Choice := 2;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.AreEqual('youtrack', Saved.IssuesTracker);
    Assert.IsFalse(Saved.IssuesQueryPicker);
    Assert.IsFalse(Saved.IssuesCreate, 'Befehl abschaltbar (#1268)');
    Assert.IsFalse(Saved.IssuesCreateIncludeCode);
    Assert.AreEqual('remember', Saved.IssuesStart);
    Assert.AreEqual('{kennung}/{kurztitel}', Saved.IssuesBranchPattern);
    Assert.AreEqual('develop', Saved.IssuesBranchBase);
    Assert.AreEqual('[{kennung}] ', Saved.IssuesCommitPattern, 'Leerzeichen am Ende bleibt');
    Assert.IsFalse(Saved.TrackerLogin);
    Assert.IsTrue(Saved.IssuesPreview);
    Assert.IsFalse(Saved.IssuesPreviewComments);
    Assert.IsFalse(Saved.IssuesCodeLinks);
    Assert.IsFalse(Saved.IssuesBlameLinks);
    Assert.AreEqual(50, Saved.IssuesBlameMaxRevisions);
    Assert.IsFalse(Saved.IssuesPreviewChecklists);
    Assert.IsFalse(Saved.IssuesChecklistStatus);
    Assert.IsFalse(Saved.IssuesPreviewLinks);
    Assert.IsFalse(Saved.IssuesWarnBlocked);
    Assert.IsFalse(Saved.IssuesBoard);
    Assert.IsFalse(Saved.IssuesBoardConfirmMove);
    Assert.IsFalse(Saved.IssuesBoardOnlyMine);
    Assert.IsFalse(Saved.IssuesSprintBurndown);
    Assert.IsFalse(Saved.IssuesSprintCompare);
    Assert.IsFalse(Saved.IssuesPaletteSearch);
    Assert.IsFalse(Saved.IssuesPreviewDevelopment);
    Assert.IsTrue(Saved.IssuesNotify);
    Assert.AreEqual(15, Saved.IssuesNotifyIntervalMinutes);
    Assert.AreEqual('watched', Saved.IssuesNotifyScope);
    Page.LoadFrom(Saved);
    Assert.AreEqual(2, FSection.IssuesTracker.Choice);
    Assert.AreEqual(1, FSection.IssuesStart.Choice);
    Assert.AreEqual('develop', FSection.IssuesBranchBase.Text);
    Assert.AreEqual('[{kennung}] ', FSection.IssuesCommitPattern.Text);
    Assert.IsFalse(FSection.TrackerLogin.Checked);
    Assert.IsFalse(FSection.IssuesPreviewComments.Checked);
    Assert.IsFalse(FSection.IssuesCodeLinks.Checked);
    Assert.IsFalse(FSection.IssuesBlameLinks.Checked);
    Assert.AreEqual('50', FSection.IssuesBlameMaxRevisions.Text);
    Assert.IsFalse(FSection.IssuesPreviewChecklists.Checked);
    Assert.IsFalse(FSection.IssuesChecklistStatus.Checked);
    Assert.IsFalse(FSection.IssuesPreviewLinks.Checked);
    Assert.IsFalse(FSection.IssuesWarnBlocked.Checked);
    Assert.IsFalse(FSection.IssuesBoard.Checked);
    Assert.IsFalse(FSection.IssuesBoardConfirmMove.Checked);
    Assert.IsFalse(FSection.IssuesBoardOnlyMine.Checked);
    Assert.IsFalse(FSection.IssuesSprintBurndown.Checked);
    Assert.IsFalse(FSection.IssuesSprintCompare.Checked);
    Assert.IsFalse(FSection.IssuesPaletteSearch.Checked);
    Assert.IsFalse(FSection.IssuesPreviewDevelopment.Checked);
    Assert.IsTrue(FSection.IssuesNotify.Checked);
    Assert.AreEqual(2, FSection.IssuesNotifyScope.Choice);
    Page.SaveTo(Saved);
  finally
    Page.Free;
  end;
end;



initialization
  TDUnitX.RegisterTestFixture(TTrackerSettingsSectionTests);

end.
