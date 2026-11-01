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
  begin
    AControl := AControl.Parent;
  end;
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
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

function TopLevelNodes(APage: TAtlasSettingsPage): TArray<TTreeNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to APage.Navigation.Items.Count - 1 do
  begin
    if APage.Navigation.Items[mIndex].Level = 0 then
    begin
      Result := Result + [APage.Navigation.Items[mIndex]];
    end;
  end;
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
    Tracker := SheetOf(FSection.General.View.Tracker);
    Assert.IsNotNull(Tracker);
    Assert.AreEqual('', Page.NodeOfSheet(Tracker));
    Assert.IsTrue(TreeNodeOf(Page, Tracker) = Issues, 'Hauptknoten Issue-Tracker');
    Assert.IsTrue(SheetOf(FSection.Queries.View.List) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.Start) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.BranchPattern) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.BranchBase) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.CommitPattern) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.Login) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.Preview) = Tracker, 'Vorschau (#1264)');
    Assert.IsTrue(SheetOf(FSection.General.View.PreviewComments) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.CodeLinks) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.BlameLinks) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.BlameMaxRevisions) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.PreviewChecklists) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.ChecklistStatus) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.PreviewLinks) = Tracker, 'Verknüpfungen (#1279)');
    Assert.IsTrue(SheetOf(FSection.General.View.WarnBlocked) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.Board) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.BoardConfirmMove) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.BoardOnlyMine) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.SprintBurndown) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.SprintCompare) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.PaletteSearch) = Tracker, 'Palettensuche (#1270)');
    Assert.IsTrue(SheetOf(FSection.General.View.PreviewDevelopment) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.Notify) = Tracker, 'Meldungen (#1271)');
    Assert.IsTrue(SheetOf(FSection.General.View.NotifyInterval) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.NotifyScope) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.Attach) = Tracker, 'Anhängen (#1276)');
    Assert.IsTrue(SheetOf(FSection.General.View.AttachLogFiles) = Tracker);
    Assert.IsTrue(SheetOf(FSection.General.View.AttachMaxImageWidth) = Tracker);
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
    FSection.Hooks.OnState :=
      function(const AConnection: TAtlasTrackerConnection): TAtlasTrackerTokenStatus
      begin
        if AConnection.Provider = 'youtrack' then
        begin
          Result := TAtlasTrackerTokenStatus.Create(TAtlasTrackerTokenState.Verified,
            EncodeDate(2026, 10, 28) + EncodeTime(10, 18, 0, 0), 200);
        end
        else
        begin
          Result := TAtlasTrackerTokenStatus.Stored(False);
        end;
      end;
    FSection.Hooks.OnTeam :=
      function: TArray<TAtlasTrackerConnection>
      begin
        Result := [TAtlasTrackerConnection.FromTeamFile('Atlas', TAtlasTrackerTarget.Create('github',
          'https://github.com', 'xKnockOut/Atlas-IDE-Expert', ''))];
      end;
    FSection.Hooks.OnToken :=
      procedure(const AConnection: TAtlasTrackerConnection)
      begin
        mToken := AConnection.Name;
      end;
    FSection.Hooks.OnCheck :=
      procedure(const AConnection: TAtlasTrackerConnection)
      begin
        mChecked := AConnection.Name;
      end;
    FSection.Hooks.OnRemove :=
      procedure(const AConnection: TAtlasTrackerConnection)
      begin
        mRemoved := AConnection.Name;
      end;
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.IssuesConnections := '[{"name": "Firma", "provider": "youtrack", "url": "https://youtrack.firma.local"},' +
      ' {"name": "GitHub", "provider": "github", "url": "https://github.com"}]';
    mPage.LoadFrom(mSettings);
    mList := FSection.Connections.View.List;
    // Abnahme: zwei Verbindungen mit Zustand, dahinter die aus der .atlas.
    Assert.AreEqual(3, mList.Items.Count);
    Assert.AreEqual('Firma', mList.Items[0].Caption);
    Assert.AreEqual('YouTrack', mList.Items[0].SubItems[0]);
    Assert.AreEqual('https://youtrack.firma.local', mList.Items[0].SubItems[1]);
    Assert.AreEqual(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerTokenVerified, ['10:18']), mList.Items[0].SubItems[2]);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTokenMissing), mList.Items[1].SubItems[2]);
    Assert.AreEqual(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SettingsIssuesConnectionTeam, ['Atlas']), mList.Items[2].Caption);
    // Erste Zeile gewählt und bearbeitbar.
    Assert.AreEqual('Firma', FSection.Connections.View.Name.Text);
    Assert.IsTrue(FSection.Connections.View.Name.Enabled);
    // Zeile aus der .atlas: nur ansehen, Token und Prüfung gehen.
    mList.Items[2].Selected := True;
    Assert.IsFalse(FSection.Connections.View.Name.Enabled);
    Assert.IsFalse(FSection.Connections.View.Url.Enabled);
    Assert.IsFalse(FSection.Connections.View.Remove.Enabled);
    Assert.IsTrue(FSection.Connections.View.Token.Enabled);
    FSection.Connections.View.Token.Click;
    Assert.AreEqual('Atlas', mToken);
    // Prüfen: „wird geprüft …“ bis zur Antwort.
    mList.Items[0].Selected := True;
    FSection.Connections.View.Check.Click;
    Assert.AreEqual('Firma', mChecked);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTokenChecking), mList.Items[0].SubItems[2]);
    FSection.TrackerCheckDone(FSection.Tables.Connections.Items[0]);
    Assert.AreEqual(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerTokenVerified, ['10:18']), mList.Items[0].SubItems[2]);
    // Neue Verbindung: erst mit gültiger Adresse gespeichert; http wird abgewiesen.
    FSection.Connections.View.Add.Click;
    Assert.AreEqual(4, mList.Items.Count);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionNew), FSection.Connections.View.Name.Text);
    mSaved := mSettings;
    mPage.SaveTo(mSaved);
    Assert.AreEqual(2, Integer(Length(TAtlasTrackerConnections.Read(mSaved.IssuesConnections))), 'ohne Adresse');
    // Absicht: Die Seite soll eine Adresse ohne https ablehnen.
    // lsp-ignore: security-insecure-http
    FSection.Connections.View.Url.Text := 'http://yt2.firma.local';
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionUrlHttps),
      FSection.Connections.View.Note.Caption);
    Assert.AreEqual('', FSection.Tables.Connections.Items[2].Url);
    FSection.Connections.View.Url.Text := 'https://marco@yt2.firma.local';
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionUrlUser),
      FSection.Connections.View.Note.Caption);
    FSection.Connections.View.Url.Text := 'https://yt2.firma.local/';
    Assert.AreEqual('', FSection.Connections.View.Note.Caption);
    Assert.AreEqual('https://yt2.firma.local', FSection.Tables.Connections.Items[2].Url);
    // Vergebener Name wird nicht übernommen.
    FSection.Connections.View.Name.Text := 'firma';
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionNameTaken),
      FSection.Connections.View.Note.Caption);
    FSection.Connections.View.Name.Text := 'Lager';
    Assert.AreEqual('Lager', FSection.Tables.Connections.Items[2].Name);
    mPage.SaveTo(mSaved);
    Assert.AreEqual(3, Integer(Length(TAtlasTrackerConnections.Read(mSaved.IssuesConnections))));
    Assert.IsTrue(mSaved.IssuesConnections.Contains('"Lager"'), mSaved.IssuesConnections);
    Assert.IsFalse(mSaved.IssuesConnections.Contains('Atlas'), 'Verbindung aus der .atlas bleibt dort');
    // Entfernen fragt über den Haken (Token) und nimmt die Zeile heraus.
    mList.Items[1].Selected := True;
    FSection.Connections.View.Remove.Click;
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
    FSection.Hooks.OnContext :=
      function: TAtlasTrackerProjectContext
      begin
        Result := TAtlasTrackerProjectContext.Empty;
        Result.ProjectFile := 'C:\Projekte\Kasse\Kasse.dproj';
        Result.GroupFile := 'C:\Projekte\Kasse\Kasse.groupproj';
        Result.Team := [TAtlasTrackerProjectMapping.FromTeamFile('C:\Projekte\Kasse\Kasse.dproj', 'Kasse',
          'xKnockOut/Kasse')];
      end;
    FSection.Hooks.OnBrowse :=
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
    mList := FSection.Projects.View.List;
    // Abnahme: persönliche Zeile vor der aus der .atlas; die .atlas gewinnt für Kasse.
    Assert.AreEqual(2, mList.Items.Count);
    Assert.AreEqual('C:\Projekte', mList.Items[0].Caption);
    Assert.AreEqual('Firma', mList.Items[0].SubItems[0]);
    Assert.AreEqual('KASSE', mList.Items[0].SubItems[1]);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectCovered), mList.Items[0].SubItems[2]);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectTeam), mList.Items[1].SubItems[2]);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesProjectCoveredHint),
      FSection.Projects.View.Note.Caption);
    Assert.IsTrue(FSection.Projects.View.Match.Enabled);
    Assert.IsTrue(FSection.Projects.View.AddCurrent.Enabled);
    // Zeile aus der .atlas: nur ansehen.
    mList.Items[1].Selected := True;
    Assert.IsFalse(FSection.Projects.View.Match.Enabled);
    Assert.IsFalse(FSection.Projects.View.Remove.Enabled);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectReadOnly),
      FSection.Projects.View.Note.Caption);
    // „Aktuelles Projekt“: die geöffnete Gruppe, vorbelegt mit der ersten Verbindung.
    FSection.Projects.View.AddCurrent.Click;
    Assert.AreEqual(2, Integer(Length(FSection.Tables.Projects.Items)));
    Assert.AreEqual('C:\Projekte\Kasse\Kasse.groupproj', FSection.Tables.Projects.Items[1].Match);
    Assert.AreEqual('Firma', FSection.Tables.Projects.Items[1].Connection);
    Assert.AreEqual('C:\Projekte\Kasse\Kasse.groupproj', FSection.Projects.View.Match.Text);
    FSection.Projects.View.Project.Text := 'LAGER';
    Assert.AreEqual('LAGER', FSection.Tables.Projects.Items[1].Project);
    // Derselbe Pfad zweimal wird nicht übernommen.
    FSection.Projects.View.Match.Text := 'c:\projekte';
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectMatchTaken),
      FSection.Projects.View.Note.Caption);
    Assert.AreEqual('C:\Projekte\Kasse\Kasse.groupproj', FSection.Tables.Projects.Items[1].Match);
    // Hinzufügen über die Dateiauswahl.
    FSection.Projects.View.AddMenu.Items[0].Click;
    Assert.AreEqual('False', mBrowsed);
    Assert.AreEqual(3, Integer(Length(FSection.Tables.Projects.Items)));
    Assert.AreEqual('C:\Projekte\Lager\Lager.dproj', FSection.Tables.Projects.Items[2].Match);
    // Aus „Meine Issues“: vorhandene Zeile wird gewählt, keine zweite angelegt.
    FSection.AssignTrackerProject('C:\Projekte');
    Assert.AreEqual(3, Integer(Length(FSection.Tables.Projects.Items)));
    Assert.AreEqual('C:\Projekte', FSection.Projects.View.Match.Text);
    // Verbindung umbenennen: die Zuordnungen ziehen mit.
    FSection.Connections.View.List.Items[0].Selected := True;
    FSection.Connections.View.Name.Text := 'Werk';
    Assert.AreEqual('Werk', FSection.Tables.Projects.Items[0].Connection);
    Assert.AreEqual('Werk', mList.Items[0].SubItems[0]);
    // Entfernen, dann speichern: nur die persönlichen Zeilen landen in issues.projects.
    mList.Items[2].Selected := True;
    FSection.Projects.View.Remove.Click;
    Assert.AreEqual(2, Integer(Length(FSection.Tables.Projects.Items)));
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
    Assert.IsTrue(FSection.Queries.View.Edit.Enabled, 'erste Zeile gewählt');
    mSeenTaken := '';
    mSeenConnections := 0;
    FSection.Hooks.OnQueryEdit :=
      function(var AQuery: TAtlasTrackerQuery; const AConnections: TArray<TAtlasTrackerConnection>;
        const ATaken: TArray<string>): Boolean
      begin
        mSeenTaken := string.Join(';', ATaken);
        mSeenConnections := Length(AConnections);
        AQuery := TAtlasTrackerQuery.Create(AQuery.Name, 'assignee: meine #Ungelöst', 'Firma', 'ATL');
        Result := True;
      end;
    FSection.Queries.View.Edit.Click;
    Assert.AreEqual('Sprint', mSeenTaken, 'Namen der übrigen Zeilen');
    Assert.AreEqual(1, mSeenConnections);
    Assert.AreEqual('assignee: meine #Ungelöst', FSection.Queries.View.List.Items[0].SubItems[0]);
    Assert.AreEqual('Firma', FSection.Queries.View.List.Items[0].SubItems[1]);
    Assert.AreEqual('assignee: meine #Ungelöst', FSection.Queries.View.Text.Text);
    // Abbrechen ändert nichts.
    FSection.Hooks.OnQueryEdit :=
      function(var AQuery: TAtlasTrackerQuery; const AConnections: TArray<TAtlasTrackerConnection>;
        const ATaken: TArray<string>): Boolean
      begin
        AQuery.Query := 'verworfen';
        Result := False;
      end;
    FSection.Queries.View.Edit.Click;
    Assert.AreEqual('assignee: meine #Ungelöst', FSection.Tables.Queries.Items[0].Query);
    // „Prüfen“ hat die Sprache erkannt: Sie kommt mit OK in settings.json.
    FSection.Hooks.OnState :=
      function(const AConnection: TAtlasTrackerConnection): TAtlasTrackerTokenStatus
      begin
        Result := TAtlasTrackerTokenStatus.Create(TAtlasTrackerTokenState.Verified, Now, 200);
        Result.Language := 'de';
      end;
    FSection.TrackerCheckDone(FSection.Tables.Connections.Items[0]);
    Assert.AreEqual('de', FSection.Tables.Connections.Items[0].Language);
    mSaved := mSettings;
    mPage.SaveTo(mSaved);
    Assert.IsTrue(mSaved.IssuesConnections.Contains('"language": "de"'), mSaved.IssuesConnections);
    FSection.Hooks.OnQueryEdit := nil;
    FSection.Hooks.OnState := nil;
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
    Assert.AreEqual(0, FSection.Queries.View.List.Items.Count);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueriesNone), FSection.Queries.View.Note.Caption);
    Assert.IsFalse(FSection.Queries.View.Name.Enabled);
    mSettings.IssuesQueries := '[{"name": "Standard", "query": "assignee: meine #Ungelöst"},' +
      ' {"name": "Sprint", "query": "#{Aktueller Sprint}", "connection": "Firma", "project": "KASSE"}]';
    mPage.LoadFrom(mSettings);
    mList := FSection.Queries.View.List;
    Assert.AreEqual(2, mList.Items.Count);
    Assert.AreEqual('Standard', mList.Items[0].Caption);
    Assert.AreEqual('assignee: meine #Ungelöst', mList.Items[0].SubItems[0]);
    Assert.AreEqual('', mList.Items[0].SubItems[1], 'ohne Verbindung: überall');
    Assert.AreEqual('Firma', mList.Items[1].SubItems[1]);
    Assert.AreEqual('KASSE', mList.Items[1].SubItems[2]);
    // Erste Zeile gewählt; „(alle)“ als Verbindung.
    Assert.AreEqual('Standard', FSection.Queries.View.Name.Text);
    Assert.AreEqual(0, FSection.Queries.View.Connection.Choice);
    mList.Items[1].Selected := True;
    Assert.AreEqual('#{Aktueller Sprint}', FSection.Queries.View.Text.Text);
    Assert.AreEqual(1, FSection.Queries.View.Connection.Choice);
    // Doppelter Name wird nicht übernommen.
    FSection.Queries.View.Name.Text := 'standard';
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueryNameTaken), FSection.Queries.View.Note.Caption);
    Assert.AreEqual('Sprint', FSection.Tables.Queries.Items[1].Name);
    FSection.Queries.View.Name.Text := 'Aktueller Sprint';
    Assert.AreEqual('Aktueller Sprint', mList.Items[1].Caption);
    // Neue Zeile: ohne Abfrage nicht gespeichert; Leerraum außen fällt weg.
    FSection.Queries.View.Add.Click;
    Assert.AreEqual(3, mList.Items.Count);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueryNew), FSection.Queries.View.Name.Text);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesQueryEmpty), FSection.Queries.View.Note.Caption);
    mSaved := mSettings;
    mPage.SaveTo(mSaved);
    Assert.AreEqual(2, Integer(Length(TAtlasTrackerQueries.Read(mSaved.IssuesQueries))), 'ohne Abfrage');
    FSection.Queries.View.Text.Text := '  created by: me #Unresolved ';
    Assert.AreEqual('created by: me #Unresolved', FSection.Tables.Queries.Items[2].Query);
    Assert.AreEqual('', FSection.Queries.View.Note.Caption);
    // Verbindung umbenennen: die Abfrage zieht mit.
    FSection.Connections.View.List.Items[0].Selected := True;
    FSection.Connections.View.Name.Text := 'Werk';
    Assert.AreEqual('Werk', FSection.Tables.Queries.Items[1].Connection);
    // Entfernen, Klappliste aus, speichern.
    mList.Items[0].Selected := True;
    FSection.Queries.View.Remove.Click;
    FSection.Queries.View.Picker.Checked := False;
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
    Assert.IsTrue(SheetOf(FSection.Workflow.View.SyncState) = SheetOf(FSection.General.View.Tracker));
    Assert.IsTrue(SheetOf(FSection.Workflow.View.EndComment) = SheetOf(FSection.General.View.Tracker));
    Assert.IsTrue(SheetOf(FSection.Connections.View.StateField) = SheetOf(FSection.General.View.Tracker));
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.IssuesStartState := 'In Arbeit';
    mSettings.IssuesAssignOnStart := True;
    mSettings.IssuesEndStates := 'Zur Prüfung, Erledigt';
    mSettings.IssuesConnections := '[{"name": "Firma", "provider": "youtrack", "url": "https://youtrack.firma.local",' +
      ' "stateField": "Status", "endStates": ["Geprüft"]}]';
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(FSection.Workflow.View.SyncState.Checked);
    Assert.AreEqual('State', FSection.Workflow.View.StateField.Value);
    Assert.AreEqual('In Arbeit', FSection.Workflow.View.StartState.Value);
    Assert.IsTrue(FSection.Workflow.View.AssignOnStart.Checked);
    Assert.AreEqual('Zur Prüfung, Erledigt', FSection.Workflow.View.EndStates.Text);
    Assert.AreEqual('Erledigt in {branch}.\n{commits}', FSection.Workflow.View.EndComment.Text);
    // Gewählte Verbindung: ihre Werte, leer = global.
    Assert.AreEqual('Status', FSection.Connections.View.StateField.Value);
    Assert.AreEqual('', FSection.Connections.View.StartState.Value);
    Assert.AreEqual('Geprüft', FSection.Connections.View.EndStates.Text);
    Assert.IsTrue(FSection.Connections.View.StateField.Enabled);
    FSection.Connections.View.EndStates.Text := 'Geprüft; Abgelehnt';
    Assert.AreEqual(2, Integer(Length(FSection.Tables.Connections.Items[0].EndStates)));
    // Andere Adresse: Zustandsfeld und Zielzustände der Verbindung bleiben (WithUrl).
    FSection.Connections.View.Url.Text := 'https://yt.firma.local';
    Assert.AreEqual('Status', FSection.Tables.Connections.Items[0].StateField);
    Assert.AreEqual('Abgelehnt', FSection.Tables.Connections.Items[0].EndStates[1]);
    // Speichern.
    FSection.Workflow.View.SyncState.Checked := False;
    FSection.Workflow.View.StateField.Value := ' Status ';
    FSection.Workflow.View.EndStates.Text := 'Zur Prüfung;; Erledigt';
    FSection.Workflow.View.EndComment.Text := 'Fertig: {pr}';
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
    FSection.Workflow.View.LoadValues.Click;
    Assert.AreEqual('', mAsked, 'ohne Haken nichts');
    FSection.Hooks.OnValues :=
      procedure(const AConnection: TAtlasTrackerConnection; const AStateField: string)
      begin
        mAsked := AConnection.Name;
        mField := AStateField;
      end;
    FSection.Workflow.View.LoadValues.Click;
    Assert.AreEqual('Firma', mAsked);
    Assert.AreEqual('Status', mField);
    Assert.IsFalse(FSection.Workflow.View.LoadValues.Enabled, 'bis zur Antwort');
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesValuesLoading), FSection.Workflow.View.ValuesNote.Caption);
    mValues := Default(TAtlasTrackerValueSet);
    mValues.States := TArray<string>.Create('Offen', 'In Arbeit');
    mValues.StateFields := TArray<string>.Create('Status');
    mValues.UserFields := TArray<string>.Create('Zuständig');
    FSection.TrackerValuesDone(mValues, '');
    Assert.IsTrue(FSection.Workflow.View.LoadValues.Enabled);
    Assert.AreEqual(2, Integer(Length(FSection.Workflow.View.StartState.Values)));
    Assert.AreEqual('Zuständig', FSection.Workflow.View.AssigneeField.Values[0]);
    Assert.AreEqual('Status', FSection.Connections.View.StateField.Values[0]);
    Assert.AreEqual('Status', FSection.Workflow.View.StateField.Value, 'eingegebener Text bleibt');
    Assert.AreEqual(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SettingsIssuesValuesLoaded, [2, 2]), FSection.Workflow.View.ValuesNote.Caption);
    FSection.TrackerValuesDone(Default(TAtlasTrackerValueSet), 'Keine Rechte');
    Assert.AreEqual(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SettingsIssuesValuesFailed, ['Keine Rechte']),
      FSection.Workflow.View.ValuesNote.Caption);
    Assert.AreEqual(2, Integer(Length(FSection.Workflow.View.StartState.Values)), 'Fehler lässt die Vorschläge');
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
    Assert.AreEqual(FSection.Connections.View.Name.Parent.Height, FSection.Connections.View.StateRow.Height);
    Assert.AreEqual(FSection.Connections.View.Name.Parent.Height, FSection.Connections.View.AssigneeRow.Height);
    Assert.AreEqual(FSection.Connections.View.Name.Parent.Height, FSection.Connections.View.StartState.Parent.Height);
    Assert.AreEqual(FSection.Connections.View.Name.Parent.Height, FSection.Connections.View.EndStates.Parent.Height);
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.IssuesConnections := '[{"name": "Firma", "provider": "youtrack", "url": "https://youtrack.firma.local"},' +
      ' {"name": "GitHub", "provider": "github", "url": "https://github.com"}]';
    mPage.LoadFrom(mSettings);
    mList := FSection.Connections.View.List;
    // YouTrack: Felder sichtbar.
    Assert.AreEqual('Firma', FSection.Connections.View.Name.Text);
    Assert.IsTrue(FSection.Connections.View.StateRow.Visible, 'YouTrack Zustandsfeld');
    Assert.IsTrue(FSection.Connections.View.AssigneeRow.Visible, 'YouTrack Benutzerfeld');
    // GitHub kennt keine Felder; Zustand beim Beginnen und Zielzustände (Labels) bleiben.
    mList.Items[1].Selected := True;
    Assert.AreEqual('GitHub', FSection.Connections.View.Name.Text);
    Assert.IsFalse(FSection.Connections.View.StateRow.Visible, 'GitHub Zustandsfeld');
    Assert.IsFalse(FSection.Connections.View.AssigneeRow.Visible, 'GitHub Benutzerfeld');
    Assert.IsTrue(FSection.Connections.View.StartState.Parent.Visible);
    Assert.IsTrue(FSection.Connections.View.EndStates.Parent.Visible);
    // Anbieter wechseln (wie eine Auswahl in der Klappliste): GitHub nach YouTrack und zurück.
    FSection.Connections.View.Provider.Choice := 0;
    FSection.Connections.View.Provider.OnChange(FSection.Connections.View.Provider);
    Assert.AreEqual('youtrack', FSection.Tables.Connections.Items[1].Provider);
    Assert.IsTrue(FSection.Connections.View.StateRow.Visible, 'nach Wechsel zu YouTrack');
    FSection.Connections.View.Provider.Choice := 1;
    FSection.Connections.View.Provider.OnChange(FSection.Connections.View.Provider);
    Assert.AreEqual('github', FSection.Tables.Connections.Items[1].Provider);
    Assert.IsFalse(FSection.Connections.View.AssigneeRow.Visible, 'nach Wechsel zu GitHub');
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
    Assert.IsTrue(SheetOf(FSection.General.View.CommentEditor) = SheetOf(FSection.General.View.Tracker));
    Assert.IsTrue(SheetOf(FSection.Snippets.View.List) = SheetOf(FSection.General.View.Tracker));
    mSettings := TAtlasPluginSettings.Defaults;
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(FSection.General.View.CommentEditor.Checked);
    Assert.AreEqual(2, FSection.Snippets.View.List.Items.Count, 'zwei Vorgaben');
    Assert.AreEqual('Bitte mit aktuellem Build prüfen', FSection.Snippets.View.List.Items[0].Caption);
    Assert.AreEqual('Bitte mit aktuellem Build prüfen', FSection.Snippets.View.Name.Text, 'erste Zeile gewählt');
    // Hinzufügen, Name und mehrzeiligen Text eingeben.
    FSection.Snippets.View.Add.Click;
    Assert.AreEqual(3, FSection.Snippets.View.List.Items.Count);
    Assert.AreEqual('Neuer Textbaustein', FSection.Snippets.View.Name.Text);
    FSection.Snippets.View.Name.Text := 'Version';
    FSection.Snippets.View.Text.Text := 'In {version}'#13#10'bitte prüfen';
    Assert.AreEqual('Version', FSection.Snippets.View.List.Items[2].Caption);
    Assert.AreEqual('In {version} ⏎ bitte prüfen', FSection.Snippets.View.List.Items[2].SubItems[0]);
    // Den ersten entfernen.
    FSection.Snippets.View.List.Items[0].Selected := True;
    FSection.Snippets.View.Remove.Click;
    Assert.AreEqual(2, FSection.Snippets.View.List.Items.Count);
    FSection.General.View.CommentEditor.Checked := False;
    mSaved := mSettings;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.IssuesCommentEditor);
    Assert.IsTrue(TAtlasCommentSnippets.Parse(mSaved.IssuesCommentSnippets, mRead));
    Assert.AreEqual(2, Integer(Length(mRead)));
    Assert.AreEqual('Behoben in {commit}', mRead[0].Name);
    Assert.AreEqual('In {version}'#10'bitte prüfen', mRead[1].Text, 'Zeilen mit #10');
    // Vorgaben stellen die Liste wieder her; geladen wird, was gespeichert war.
    FSection.Snippets.View.Defaults.Click;
    Assert.AreEqual(2, FSection.Snippets.View.List.Items.Count);
    Assert.AreEqual('Bitte mit aktuellem Build prüfen', FSection.Snippets.View.List.Items[0].Caption);
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(FSection.General.View.CommentEditor.Checked);
    Assert.AreEqual('Version', FSection.Snippets.View.List.Items[1].Caption);
    // Leere Liste bleibt leer: Felder gesperrt.
    mSaved.IssuesCommentSnippets := '[]';
    mPage.LoadFrom(mSaved);
    Assert.AreEqual(0, FSection.Snippets.View.List.Items.Count);
    Assert.IsFalse(FSection.Snippets.View.Name.Enabled);
    Assert.IsFalse(FSection.Snippets.View.Remove.Enabled);
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
    Assert.AreEqual(0, FSection.General.View.Tracker.Choice);
    Assert.IsTrue(FSection.Queries.View.Picker.Checked, 'Klappliste an (#1262)');
    Assert.IsTrue(FSection.Queries.View.CreateIssue.Checked, '„Issue anlegen …“ an (#1268)');
    Assert.IsTrue(FSection.Queries.View.CreateIncludeCode.Checked, 'Codeausschnitt vorgeschlagen (#1268)');
    Assert.AreEqual(0, FSection.General.View.Start.Choice);
    Assert.AreEqual('', FSection.General.View.BranchPattern.Text);
    Assert.AreEqual('', FSection.General.View.BranchBase.Text);
    Assert.AreEqual('{kennung} ', FSection.General.View.CommitPattern.Text);
    Assert.IsTrue(FSection.General.View.Login.Checked);
    Assert.IsTrue(FSection.General.View.Preview.Checked);
    Assert.IsTrue(FSection.General.View.PreviewComments.Checked);
    Assert.IsTrue(FSection.General.View.CodeLinks.Checked);
    Assert.IsTrue(FSection.General.View.BlameLinks.Checked);
    Assert.AreEqual('200', FSection.General.View.BlameMaxRevisions.Text);
    Assert.IsTrue(FSection.General.View.PreviewChecklists.Checked);
    Assert.IsTrue(FSection.General.View.ChecklistStatus.Checked);
    Assert.IsTrue(FSection.General.View.PreviewLinks.Checked);
    Assert.IsTrue(FSection.General.View.WarnBlocked.Checked);
    Assert.IsTrue(FSection.General.View.Board.Checked);
    Assert.IsTrue(FSection.General.View.BoardConfirmMove.Checked);
    Assert.IsTrue(FSection.General.View.BoardOnlyMine.Checked);
    Assert.IsTrue(FSection.General.View.SprintBurndown.Checked);
    Assert.IsTrue(FSection.General.View.SprintCompare.Checked);
    Assert.IsTrue(FSection.General.View.PaletteSearch.Checked);
    Assert.IsTrue(FSection.General.View.PreviewDevelopment.Checked);
    Assert.IsFalse(FSection.General.View.Notify.Checked);
    Assert.AreEqual('10', FSection.General.View.NotifyInterval.Text);
    Assert.AreEqual(1, FSection.General.View.NotifyScope.Choice);
    Assert.IsTrue(FSection.General.View.Attach.Checked);
    Assert.AreEqual('', FSection.General.View.AttachLogFiles.Text);
    Assert.AreEqual('1920', FSection.General.View.AttachMaxImageWidth.Text);
    FSection.General.View.Tracker.Choice := 2;
    FSection.Queries.View.Picker.Checked := False;
    FSection.Queries.View.CreateIssue.Checked := False;
    FSection.Queries.View.CreateIncludeCode.Checked := False;
    FSection.General.View.Start.Choice := 1;
    FSection.General.View.BranchPattern.Text := ' {kennung}/{kurztitel} ';
    FSection.General.View.BranchBase.Text := ' develop ';
    FSection.General.View.CommitPattern.Text := '[{kennung}] ';
    FSection.General.View.Login.Checked := False;
    FSection.General.View.PreviewComments.Checked := False;
    FSection.General.View.CodeLinks.Checked := False;
    FSection.General.View.BlameLinks.Checked := False;
    FSection.General.View.BlameMaxRevisions.Text := '50';
    FSection.General.View.PreviewChecklists.Checked := False;
    FSection.General.View.ChecklistStatus.Checked := False;
    FSection.General.View.PreviewLinks.Checked := False;
    FSection.General.View.WarnBlocked.Checked := False;
    FSection.General.View.Board.Checked := False;
    FSection.General.View.BoardConfirmMove.Checked := False;
    FSection.General.View.BoardOnlyMine.Checked := False;
    FSection.General.View.SprintBurndown.Checked := False;
    FSection.General.View.SprintCompare.Checked := False;
    FSection.General.View.PaletteSearch.Checked := False;
    FSection.General.View.PreviewDevelopment.Checked := False;
    FSection.General.View.Notify.Checked := True;
    FSection.General.View.NotifyInterval.Text := ' 15 ';
    FSection.General.View.NotifyScope.Choice := 2;
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
    Assert.AreEqual(2, FSection.General.View.Tracker.Choice);
    Assert.AreEqual(1, FSection.General.View.Start.Choice);
    Assert.AreEqual('develop', FSection.General.View.BranchBase.Text);
    Assert.AreEqual('[{kennung}] ', FSection.General.View.CommitPattern.Text);
    Assert.IsFalse(FSection.General.View.Login.Checked);
    Assert.IsFalse(FSection.General.View.PreviewComments.Checked);
    Assert.IsFalse(FSection.General.View.CodeLinks.Checked);
    Assert.IsFalse(FSection.General.View.BlameLinks.Checked);
    Assert.AreEqual('50', FSection.General.View.BlameMaxRevisions.Text);
    Assert.IsFalse(FSection.General.View.PreviewChecklists.Checked);
    Assert.IsFalse(FSection.General.View.ChecklistStatus.Checked);
    Assert.IsFalse(FSection.General.View.PreviewLinks.Checked);
    Assert.IsFalse(FSection.General.View.WarnBlocked.Checked);
    Assert.IsFalse(FSection.General.View.Board.Checked);
    Assert.IsFalse(FSection.General.View.BoardConfirmMove.Checked);
    Assert.IsFalse(FSection.General.View.BoardOnlyMine.Checked);
    Assert.IsFalse(FSection.General.View.SprintBurndown.Checked);
    Assert.IsFalse(FSection.General.View.SprintCompare.Checked);
    Assert.IsFalse(FSection.General.View.PaletteSearch.Checked);
    Assert.IsFalse(FSection.General.View.PreviewDevelopment.Checked);
    Assert.IsTrue(FSection.General.View.Notify.Checked);
    Assert.AreEqual(2, FSection.General.View.NotifyScope.Choice);
    Page.SaveTo(Saved);
  finally
    Page.Free;
  end;
end;



initialization
  TDUnitX.RegisterTestFixture(TTrackerSettingsSectionTests);

end.
