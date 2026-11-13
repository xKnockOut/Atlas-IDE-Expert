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
    /// <summary>Einmal-Belegungen vorwegnehmen; sie gehören nicht in die Leckmessung.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
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
  Atlas.UI.Settings.Page.Tree,
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
  Atlas.UI.Tracker.Settings.Strings;

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

procedure TTrackerSettingsSectionTests.WarmUpFirstUse;
begin
  Setup;
  try
    IssuesTrackerOwnPage;
  finally
    TearDown;
  end;
  Setup;
  try
    SettingsRoundTrip;
  finally
    TearDown;
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
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mAreas: TArray<TTreeNode>;
  mIssues: TTreeNode;
  mTracker: TTabSheet;
begin
  TAtlasSettingsPageTree.ForgetTreeState;
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    mAreas := TopLevelNodes(mPage);
    mIssues := mAreas[14];
    // Reiter des Moduls hinter denen von Base (#1456), beschriftet wie der Bereich im Katalog.
    Assert.AreEqual(mPage.Catalog.AreaCaption('issues', TAtlasStrings.Language = TAtlasLanguage.English), mIssues.Text);
    // Alle Tracker-Einstellungen auf dem Hauptknoten der Seite Issue-Tracker.
    mTracker := SheetOf(FSection.General.View.Tracker);
    Assert.IsNotNull(mTracker);
    Assert.AreEqual('', mPage.NodeOfSheet(mTracker));
    Assert.IsTrue(TreeNodeOf(mPage, mTracker) = mIssues, 'Hauptknoten Issue-Tracker');
    Assert.IsTrue(SheetOf(FSection.Queries.View.List) = mTracker);
    Assert.IsTrue(SheetOf(FSection.General.View.Login) = mTracker);
    Assert.IsTrue(SheetOf(FSection.General.View.Preview) = mTracker, 'Vorschau (#1264)');
    Assert.IsTrue(SheetOf(FSection.General.View.PreviewComments) = mTracker);
    Assert.IsTrue(SheetOf(FSection.General.View.CodeLinks) = mTracker);
    Assert.IsTrue(SheetOf(FSection.General.View.BlameLinks) = mTracker);
    Assert.IsTrue(SheetOf(FSection.General.View.BlameMaxRevisions) = mTracker);
    Assert.IsTrue(SheetOf(FSection.General.View.PreviewChecklists) = mTracker);
    Assert.IsTrue(SheetOf(FSection.General.View.ChecklistStatus) = mTracker);
    Assert.IsTrue(SheetOf(FSection.General.View.PreviewLinks) = mTracker, 'Verknüpfungen (#1279)');
    Assert.IsTrue(SheetOf(FSection.General.View.WarnBlocked) = mTracker);
    Assert.IsTrue(SheetOf(FSection.General.View.Board) = mTracker);
    Assert.IsTrue(SheetOf(FSection.General.View.BoardConfirmMove) = mTracker);
    Assert.IsTrue(SheetOf(FSection.General.View.BoardOnlyMine) = mTracker);
    Assert.IsTrue(SheetOf(FSection.General.View.SprintBurndown) = mTracker);
    Assert.IsTrue(SheetOf(FSection.General.View.SprintCompare) = mTracker);
    Assert.IsTrue(SheetOf(FSection.General.View.PaletteSearch) = mTracker, 'Palettensuche (#1270)');
    Assert.IsTrue(SheetOf(FSection.General.View.PreviewDevelopment) = mTracker);
    Assert.IsTrue(SheetOf(FSection.General.View.Notify) = mTracker, 'Meldungen (#1271)');
    Assert.IsTrue(SheetOf(FSection.General.View.NotifyInterval) = mTracker);
    Assert.IsTrue(SheetOf(FSection.General.View.NotifyScope) = mTracker);
    Assert.IsTrue(SheetOf(FSection.General.View.Attach) = mTracker, 'Anhängen (#1276)');
    Assert.IsTrue(SheetOf(FSection.General.View.AttachLogFiles) = mTracker);
    Assert.IsTrue(SheetOf(FSection.General.View.AttachMaxImageWidth) = mTracker);
  finally
    mHost.Free;
  end;
end;


/// <summary>Abnahme: zwei Verbindungen mit Zustand, dahinter die aus der .atlas.</summary>
procedure AssertConnectionRows(AList: TListView);
begin
  // Abnahme: zwei Verbindungen mit Zustand, dahinter die aus der .atlas.
  Assert.AreEqual(3, AList.Items.Count);
  Assert.AreEqual('Firma', AList.Items[0].Caption);
  Assert.AreEqual('YouTrack', AList.Items[0].SubItems[0]);
  Assert.AreEqual('https://youtrack.firma.local', AList.Items[0].SubItems[1]);
  Assert.AreEqual(TAtlasOptionsStrings.Fmt(TAtlasOptionsTextId.TrackerTokenVerified, ['10:18']),
    AList.Items[0].SubItems[2]);
  Assert.AreEqual(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.TrackerTokenMissing), AList.Items[1].SubItems[2]);
  Assert.AreEqual(TAtlasOptionsStrings.Fmt(TAtlasOptionsTextId.SettingsIssuesConnectionTeam, ['Atlas']),
    AList.Items[2].Caption);
end;

/// <summary>Neue Verbindung: erst mit gültiger Adresse gespeichert; http und vergebene Namen werden
/// abgewiesen.</summary>
procedure AddConnectionLager(APage: TAtlasSettingsPage; ASection: TAtlasTrackerSettingsSection; AList: TListView;
  var ASaved: TAtlasPluginSettings);
begin
  // Neue Verbindung: erst mit gültiger Adresse gespeichert; http wird abgewiesen.
  ASection.Connections.View.Add.Click;
  Assert.AreEqual(4, AList.Items.Count);
  Assert.AreEqual(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesConnectionNew),
    ASection.Connections.View.Name.Text);
  APage.SaveTo(ASaved);
  Assert.AreEqual(2, Integer(Length(TAtlasTrackerConnections.Read(ASaved.IssuesConnections))), 'ohne Adresse');
  // Absicht: Die Seite soll eine Adresse ohne https ablehnen.
  // lsp-ignore: security-insecure-http
  ASection.Connections.View.Url.Text := 'http://yt2.firma.local';
  Assert.AreEqual(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesConnectionUrlHttps),
    ASection.Connections.View.Note.Caption);
  Assert.AreEqual('', ASection.Tables.Connections.Items[2].Url);
  ASection.Connections.View.Url.Text := 'https://marco@yt2.firma.local';
  Assert.AreEqual(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesConnectionUrlUser),
    ASection.Connections.View.Note.Caption);
  ASection.Connections.View.Url.Text := 'https://yt2.firma.local/';
  Assert.AreEqual('', ASection.Connections.View.Note.Caption);
  Assert.AreEqual('https://yt2.firma.local', ASection.Tables.Connections.Items[2].Url);
  // Vergebener Name wird nicht übernommen.
  ASection.Connections.View.Name.Text := 'firma';
  Assert.AreEqual(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesConnectionNameTaken),
    ASection.Connections.View.Note.Caption);
  ASection.Connections.View.Name.Text := 'Lager';
  Assert.AreEqual('Lager', ASection.Tables.Connections.Items[2].Name);
  APage.SaveTo(ASaved);
  Assert.AreEqual(3, Integer(Length(TAtlasTrackerConnections.Read(ASaved.IssuesConnections))));
  Assert.IsTrue(ASaved.IssuesConnections.Contains('"Lager"'), ASaved.IssuesConnections);
  Assert.IsFalse(ASaved.IssuesConnections.Contains('Atlas'), 'Verbindung aus der .atlas bleibt dort');
end;

type
  /// <summary>Hält fest, für welche Verbindung die Tabelle Token, Prüfung und Entfernen angefragt hat.</summary>
  TConnectionProbe = class
  public
    FChecked: string;
    FRemoved: string;
    FToken: string;
  end;

/// <summary>Zustände je Anbieter, eine Verbindung aus der .atlas und die Aktionen über AProbe.</summary>
procedure WireConnections(ASection: TAtlasTrackerSettingsSection; AProbe: TConnectionProbe);
begin
  ASection.Hooks.OnState :=
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
  ASection.Hooks.OnTeam :=
    function: TArray<TAtlasTrackerConnection>
    begin
      Result := [TAtlasTrackerConnection.FromTeamFile('Atlas', TAtlasTrackerTarget.Create('github',
        'https://github.com', 'xKnockOut/Atlas-IDE-Expert', ''))];
    end;
  ASection.Hooks.OnToken :=
    procedure(const AConnection: TAtlasTrackerConnection)
    begin
      AProbe.FToken := AConnection.Name;
    end;
  ASection.Hooks.OnCheck :=
    procedure(const AConnection: TAtlasTrackerConnection)
    begin
      AProbe.FChecked := AConnection.Name;
    end;
  ASection.Hooks.OnRemove :=
    procedure(const AConnection: TAtlasTrackerConnection)
    begin
      AProbe.FRemoved := AConnection.Name;
    end;
end;

procedure TTrackerSettingsSectionTests.TrackerConnectionsTable;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
  mList: TListView;
  mProbe: TConnectionProbe;
begin
  mProbe := TConnectionProbe.Create;
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    WireConnections(FSection, mProbe);
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.IssuesConnections := '[{"name": "Firma", "provider": "youtrack", "url": "https://youtrack.firma.local"},' +
      ' {"name": "GitHub", "provider": "github", "url": "https://github.com"}]';
    mPage.LoadFrom(mSettings);
    mList := FSection.Connections.View.List;
    AssertConnectionRows(mList);
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
    Assert.AreEqual('Atlas', mProbe.FToken);
    // Prüfen: „wird geprüft …“ bis zur Antwort.
    mList.Items[0].Selected := True;
    FSection.Connections.View.Check.Click;
    Assert.AreEqual('Firma', mProbe.FChecked);
    Assert.AreEqual(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.TrackerTokenChecking), mList.Items[0].SubItems[2]);
    FSection.TrackerCheckDone(FSection.Tables.Connections.Items[0]);
    Assert.AreEqual(TAtlasOptionsStrings.Fmt(TAtlasOptionsTextId.TrackerTokenVerified, ['10:18']),
      mList.Items[0].SubItems[2]);
    mSaved := mSettings;
    AddConnectionLager(mPage, FSection, mList, mSaved);
    // Entfernen fragt über den Haken (Token) und nimmt die Zeile heraus.
    mList.Items[1].Selected := True;
    FSection.Connections.View.Remove.Click;
    Assert.AreEqual('GitHub', mProbe.FRemoved);
    mPage.SaveTo(mSaved);
    Assert.AreEqual(2, Integer(Length(TAtlasTrackerConnections.Read(mSaved.IssuesConnections))));
    Assert.IsFalse(mSaved.IssuesConnections.Contains('"GitHub"'), mSaved.IssuesConnections);
  finally
    mHost.Free;
    mProbe.Free;
  end;
end;


/// <summary>Kontext: Projekt und Gruppe Kasse, Zuordnung aus der .atlas.</summary>
procedure WireKasseProjectContext(ASection: TAtlasTrackerSettingsSection);
begin
  ASection.Hooks.OnContext :=
    function: TAtlasTrackerProjectContext
    begin
      Result := TAtlasTrackerProjectContext.Empty;
      Result.ProjectFile := 'C:\Projekte\Kasse\Kasse.dproj';
      Result.GroupFile := 'C:\Projekte\Kasse\Kasse.groupproj';
      Result.Team := [TAtlasTrackerProjectMapping.FromTeamFile('C:\Projekte\Kasse\Kasse.dproj', 'Kasse',
        'xKnockOut/Kasse')];
    end;
end;

/// <summary>Abnahme: persönliche Zeile vor der aus der .atlas; diese nur ansehen.</summary>
procedure AssertProjectRows(ASection: TAtlasTrackerSettingsSection; AList: TListView);
begin
  // Abnahme: persönliche Zeile vor der aus der .atlas; die .atlas gewinnt für Kasse.
  Assert.AreEqual(2, AList.Items.Count);
  Assert.AreEqual('C:\Projekte', AList.Items[0].Caption);
  Assert.AreEqual('Firma', AList.Items[0].SubItems[0]);
  Assert.AreEqual('KASSE', AList.Items[0].SubItems[1]);
  // Spalte 2 sind die Arbeitskopien (#1926), die Herkunft steht in Spalte 3.
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectCovered), AList.Items[0].SubItems[3]);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectTeam), AList.Items[1].SubItems[3]);
  Assert.AreEqual(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesProjectCoveredHint),
    ASection.Projects.View.Note.Caption);
  Assert.IsTrue(ASection.Projects.View.Match.Enabled);
  Assert.IsTrue(ASection.Projects.View.AddCurrent.Enabled);
  // Zeile aus der .atlas: nur ansehen.
  AList.Items[1].Selected := True;
  Assert.IsFalse(ASection.Projects.View.Match.Enabled);
  Assert.IsFalse(ASection.Projects.View.Remove.Enabled);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectReadOnly),
    ASection.Projects.View.Note.Caption);
end;

/// <summary>„Aktuelles Projekt“ übernehmen; derselbe Pfad zweimal wird nicht übernommen.</summary>
procedure AddCurrentProject(ASection: TAtlasTrackerSettingsSection);
begin
  // „Aktuelles Projekt“: die geöffnete Gruppe, vorbelegt mit der ersten Verbindung.
  ASection.Projects.View.AddCurrent.Click;
  Assert.AreEqual(2, Integer(Length(ASection.Tables.Projects.Items)));
  Assert.AreEqual('C:\Projekte\Kasse\Kasse.groupproj', ASection.Tables.Projects.Items[1].Match);
  Assert.AreEqual('Firma', ASection.Tables.Projects.Items[1].Connection);
  Assert.AreEqual('C:\Projekte\Kasse\Kasse.groupproj', ASection.Projects.View.Match.Text);
  ASection.Projects.View.Project.Text := 'LAGER';
  Assert.AreEqual('LAGER', ASection.Tables.Projects.Items[1].Project);
  // Derselbe Pfad zweimal wird nicht übernommen.
  ASection.Projects.View.Match.Text := 'c:\projekte';
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectMatchTaken),
    ASection.Projects.View.Note.Caption);
  Assert.AreEqual('C:\Projekte\Kasse\Kasse.groupproj', ASection.Tables.Projects.Items[1].Match);
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
    WireKasseProjectContext(FSection);
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
    AssertProjectRows(FSection, mList);
    AddCurrentProject(FSection);
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


/// <summary>Abbrechen im Abfrage-Dialog ändert nichts.</summary>
procedure AssertQueryEditCancelled(ASection: TAtlasTrackerSettingsSection);
begin
  // Abbrechen ändert nichts.
  ASection.Hooks.OnQueryEdit :=
    function(var AQuery: TAtlasTrackerQuery; const AConnections: TArray<TAtlasTrackerConnection>;
      const ATaken: TArray<string>): Boolean
    begin
      AQuery.Query := 'verworfen';
      Result := False;
    end;
  ASection.Queries.View.Edit.Click;
  Assert.AreEqual('assignee: meine #Ungelöst', ASection.Tables.Queries.Items[0].Query);
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
    AssertQueryEditCancelled(FSection);
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


/// <summary>Zwei Abfragen, erste gewählt; „(alle)“ als Verbindung.</summary>
procedure AssertQueryRows(ASection: TAtlasTrackerSettingsSection; AList: TListView);
begin
  Assert.AreEqual(2, AList.Items.Count);
  Assert.AreEqual('Standard', AList.Items[0].Caption);
  Assert.AreEqual('assignee: meine #Ungelöst', AList.Items[0].SubItems[0]);
  Assert.AreEqual('', AList.Items[0].SubItems[1], 'ohne Verbindung: überall');
  Assert.AreEqual('Firma', AList.Items[1].SubItems[1]);
  Assert.AreEqual('KASSE', AList.Items[1].SubItems[2]);
  // Erste Zeile gewählt; „(alle)“ als Verbindung.
  Assert.AreEqual('Standard', ASection.Queries.View.Name.Text);
  Assert.AreEqual(0, ASection.Queries.View.Connection.Choice);
  AList.Items[1].Selected := True;
  Assert.AreEqual('#{Aktueller Sprint}', ASection.Queries.View.Text.Text);
  Assert.AreEqual(1, ASection.Queries.View.Connection.Choice);
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
    Assert.AreEqual(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesQueriesNone),
      FSection.Queries.View.Note.Caption);
    Assert.IsFalse(FSection.Queries.View.Name.Enabled);
    mSettings.IssuesQueries := '[{"name": "Standard", "query": "assignee: meine #Ungelöst"},' +
      ' {"name": "Sprint", "query": "#{Aktueller Sprint}", "connection": "Firma", "project": "KASSE"}]';
    mPage.LoadFrom(mSettings);
    mList := FSection.Queries.View.List;
    AssertQueryRows(FSection, mList);
    // Doppelter Name wird nicht übernommen.
    FSection.Queries.View.Name.Text := 'standard';
    Assert.AreEqual(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesQueryNameTaken),
      FSection.Queries.View.Note.Caption);
    Assert.AreEqual('Sprint', FSection.Tables.Queries.Items[1].Name);
    FSection.Queries.View.Name.Text := 'Aktueller Sprint';
    Assert.AreEqual('Aktueller Sprint', mList.Items[1].Caption);
    // Neue Zeile: ohne Abfrage nicht gespeichert; Leerraum außen fällt weg.
    FSection.Queries.View.Add.Click;
    Assert.AreEqual(3, mList.Items.Count);
    Assert.AreEqual(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesQueryNew),
      FSection.Queries.View.Name.Text);
    Assert.AreEqual(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesQueryEmpty),
      FSection.Queries.View.Note.Caption);
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
    Assert.AreEqual(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesQueryNew), mQueries[1].Name);
    Assert.IsFalse(mSaved.IssuesQueryPicker);
  finally
    mHost.Free;
  end;
  mQueries := nil;
end;


/// <summary>Geladene Ablaufwerte, global und je Verbindung; andere Adresse behält die Werte der Verbindung.</summary>
procedure AssertWorkflowLoaded(ASection: TAtlasTrackerSettingsSection);
begin
  Assert.IsTrue(ASection.Workflow.View.SyncState.Checked);
  Assert.AreEqual('State', ASection.Workflow.View.StateField.Value);
  Assert.AreEqual('In Arbeit', ASection.Workflow.View.StartState.Value);
  Assert.IsTrue(ASection.Workflow.View.AssignOnStart.Checked);
  Assert.AreEqual('Zur Prüfung, Erledigt', ASection.Workflow.View.EndStates.Text);
  Assert.AreEqual('Erledigt in {branch}.\n{commits}', ASection.Workflow.View.EndComment.Text);
  // Gewählte Verbindung: ihre Werte, leer = global.
  Assert.AreEqual('Status', ASection.Connections.View.StateField.Value);
  Assert.AreEqual('', ASection.Connections.View.StartState.Value);
  Assert.AreEqual('Geprüft', ASection.Connections.View.EndStates.Text);
  Assert.AreEqual('Im Review', ASection.Connections.View.ReviewStates.Text);
  Assert.AreEqual('Zur Prüfung', ASection.Workflow.View.ReviewStates.Text);
  Assert.IsTrue(ASection.Workflow.View.Reopened.Checked, 'Vorgabe an');
  Assert.IsTrue(ASection.Workflow.View.ReviewBuild.Checked, '#2126: Vorgabe an');
  Assert.AreEqual('Geprüft: {build}, {tests}.', ASection.Workflow.View.ReviewComment.Text);
  Assert.IsTrue(ASection.Connections.View.StateField.Enabled);
  ASection.Connections.View.EndStates.Text := 'Geprüft; Abgelehnt';
  Assert.AreEqual(2, Integer(Length(ASection.Tables.Connections.Items[0].EndStates)));
  // Andere Adresse: Zustandsfeld und Zielzustände der Verbindung bleiben (WithUrl).
  ASection.Connections.View.Url.Text := 'https://yt.firma.local';
  Assert.AreEqual('Status', ASection.Tables.Connections.Items[0].StateField);
  Assert.AreEqual('Abgelehnt', ASection.Tables.Connections.Items[0].EndStates[1]);
end;

/// <summary>Gespeicherte Ablaufwerte, global und je Verbindung.</summary>
procedure AssertWorkflowSaved(const ASaved: TAtlasPluginSettings);
var
  mRead: TArray<TAtlasTrackerConnection>;
begin
  Assert.IsFalse(ASaved.IssuesSyncState);
  Assert.AreEqual('Status', ASaved.IssuesStateField);
  Assert.AreEqual('Zur Prüfung, Erledigt', ASaved.IssuesEndStates);
  Assert.AreEqual('Fertig: {pr}', ASaved.IssuesEndComment);
  Assert.AreEqual('Zur Prüfung, QA', ASaved.IssuesReviewStates);
  Assert.IsFalse(ASaved.IssuesReopened);
  Assert.IsFalse(ASaved.IssuesReviewBuild);
  Assert.AreEqual('Ok: {tests}', ASaved.IssuesReviewComment);
  mRead := TAtlasTrackerConnections.Read(ASaved.IssuesConnections);
  Assert.AreEqual('https://yt.firma.local', mRead[0].Url);
  Assert.AreEqual('Status', mRead[0].StateField);
  Assert.AreEqual(2, Integer(Length(mRead[0].EndStates)));
  Assert.AreEqual('Im Review', mRead[0].ReviewStates[0]);
end;

/// <summary>Werte vom Tracker als Vorschläge; ein Fehler lässt die Vorschläge stehen.</summary>
procedure AssertTrackerValuesDone(ASection: TAtlasTrackerSettingsSection);
var
  mValues: TAtlasTrackerValueSet;
begin
  mValues := Default(TAtlasTrackerValueSet);
  mValues.States := TArray<string>.Create('Offen', 'In Arbeit');
  mValues.StateFields := TArray<string>.Create('Status');
  mValues.UserFields := TArray<string>.Create('Zuständig');
  ASection.TrackerValuesDone(mValues, '');
  Assert.IsTrue(ASection.Workflow.View.LoadValues.Enabled);
  Assert.AreEqual(2, Integer(Length(ASection.Workflow.View.StartState.Values)));
  Assert.AreEqual('Zuständig', ASection.Workflow.View.AssigneeField.Values[0]);
  Assert.AreEqual('Status', ASection.Connections.View.StateField.Values[0]);
  Assert.AreEqual('Status', ASection.Workflow.View.StateField.Value, 'eingegebener Text bleibt');
  Assert.AreEqual(TAtlasOptionsStrings.Fmt(TAtlasOptionsTextId.SettingsIssuesValuesLoaded, [2, 2]),
    ASection.Workflow.View.ValuesNote.Caption);
  ASection.TrackerValuesDone(Default(TAtlasTrackerValueSet), 'Keine Rechte');
  Assert.AreEqual(TAtlasOptionsStrings.Fmt(TAtlasOptionsTextId.SettingsIssuesValuesFailed, ['Keine Rechte']),
    ASection.Workflow.View.ValuesNote.Caption);
  Assert.AreEqual(2, Integer(Length(ASection.Workflow.View.StartState.Values)), 'Fehler lässt die Vorschläge');
end;

procedure TTrackerSettingsSectionTests.TrackerWorkflowSettings;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
  mAsked, mField: string;
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
    mSettings.IssuesReviewStates := 'Zur Prüfung';
    mSettings.IssuesConnections := '[{"name": "Firma", "provider": "youtrack", "url": "https://youtrack.firma.local",' +
      ' "stateField": "Status", "endStates": ["Geprüft"], "reviewStates": ["Im Review"]}]';
    mPage.LoadFrom(mSettings);
    AssertWorkflowLoaded(FSection);
    // Speichern.
    FSection.Workflow.View.SyncState.Checked := False;
    FSection.Workflow.View.StateField.Value := ' Status ';
    FSection.Workflow.View.EndStates.Text := 'Zur Prüfung;; Erledigt';
    FSection.Workflow.View.EndComment.Text := 'Fertig: {pr}';
    // #2126/#2127: Prüfzustände geordnet, Schalter für wieder geöffnete Issues.
    FSection.Workflow.View.ReviewStates.Text := 'Zur Prüfung;; QA';
    FSection.Workflow.View.Reopened.Checked := False;
    FSection.Workflow.View.ReviewBuild.Checked := False;
    FSection.Workflow.View.ReviewComment.Text := 'Ok: {tests}';
    mSaved := mSettings;
    mPage.SaveTo(mSaved);
    AssertWorkflowSaved(mSaved);
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
    Assert.AreEqual(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesValuesLoading),
      FSection.Workflow.View.ValuesNote.Caption);
    AssertTrackerValuesDone(FSection);
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


/// <summary>Abschnitt mit den Vorgaben geladen.</summary>
procedure AssertSectionDefaults(ASection: TAtlasTrackerSettingsSection);
begin
  Assert.AreEqual(0, ASection.General.View.Tracker.Choice);
  Assert.IsTrue(ASection.Queries.View.Picker.Checked, 'Klappliste an (#1262)');
  Assert.IsTrue(ASection.Queries.View.CreateIssue.Checked, '„Issue anlegen …“ an (#1268)');
  Assert.IsTrue(ASection.Queries.View.CreateIncludeCode.Checked, 'Codeausschnitt vorgeschlagen (#1268)');
  Assert.IsTrue(ASection.General.View.Login.Checked);
  Assert.IsTrue(ASection.General.View.Preview.Checked);
  Assert.IsTrue(ASection.General.View.PreviewComments.Checked);
  Assert.IsTrue(ASection.General.View.CodeLinks.Checked);
  Assert.IsTrue(ASection.General.View.BlameLinks.Checked);
  Assert.AreEqual('200', ASection.General.View.BlameMaxRevisions.Text);
  Assert.IsTrue(ASection.General.View.PreviewChecklists.Checked);
  Assert.IsTrue(ASection.General.View.ChecklistStatus.Checked);
  Assert.IsTrue(ASection.General.View.StatusState.Checked);
  Assert.AreEqual(0, ASection.General.View.SprintOnStart.Choice, 'Sprint beim Beginnen: fragen');
  Assert.IsTrue(ASection.General.View.PreviewLinks.Checked);
  Assert.IsTrue(ASection.General.View.WarnBlocked.Checked);
  Assert.IsTrue(ASection.General.View.Board.Checked);
  Assert.IsTrue(ASection.General.View.BoardConfirmMove.Checked);
  Assert.IsTrue(ASection.General.View.BoardOnlyMine.Checked);
  Assert.IsTrue(ASection.General.View.IdeColors.Checked);
  Assert.IsTrue(ASection.General.View.SprintBurndown.Checked);
  Assert.IsTrue(ASection.General.View.SprintCompare.Checked);
  Assert.IsTrue(ASection.General.View.PaletteSearch.Checked);
  Assert.IsTrue(ASection.General.View.PreviewDevelopment.Checked);
  Assert.IsFalse(ASection.General.View.Notify.Checked);
  Assert.AreEqual('10', ASection.General.View.NotifyInterval.Text);
  Assert.AreEqual(1, ASection.General.View.NotifyScope.Choice);
  Assert.IsTrue(ASection.General.View.Attach.Checked);
  Assert.AreEqual('', ASection.General.View.AttachLogFiles.Text);
  Assert.AreEqual('1920', ASection.General.View.AttachMaxImageWidth.Text);
end;

/// <summary>Alle Werte des Abschnitts umstellen.</summary>
procedure EditSection(ASection: TAtlasTrackerSettingsSection);
begin
  ASection.General.View.Tracker.Choice := 2;
  ASection.Queries.View.Picker.Checked := False;
  ASection.Queries.View.CreateIssue.Checked := False;
  ASection.Queries.View.CreateIncludeCode.Checked := False;
  ASection.General.View.Login.Checked := False;
  ASection.General.View.PreviewComments.Checked := False;
  ASection.General.View.CodeLinks.Checked := False;
  ASection.General.View.BlameLinks.Checked := False;
  ASection.General.View.BlameMaxRevisions.Text := '50';
  ASection.General.View.PreviewChecklists.Checked := False;
  ASection.General.View.ChecklistStatus.Checked := False;
  ASection.General.View.StatusState.Checked := False;
  ASection.General.View.SprintOnStart.Choice := 2;
  ASection.General.View.PreviewLinks.Checked := False;
  ASection.General.View.WarnBlocked.Checked := False;
  ASection.General.View.Board.Checked := False;
  ASection.General.View.BoardConfirmMove.Checked := False;
  ASection.General.View.BoardOnlyMine.Checked := False;
  ASection.General.View.IdeColors.Checked := False;
  ASection.General.View.SprintBurndown.Checked := False;
  ASection.General.View.SprintCompare.Checked := False;
  ASection.General.View.PaletteSearch.Checked := False;
  ASection.General.View.PreviewDevelopment.Checked := False;
  ASection.General.View.Notify.Checked := True;
  ASection.General.View.NotifyInterval.Text := ' 15 ';
  ASection.General.View.NotifyScope.Choice := 2;
end;

/// <summary>Umgestellte Werte gespeichert und normalisiert.</summary>
procedure AssertSectionSaved(const ASaved: TAtlasPluginSettings);
begin
  Assert.AreEqual('youtrack', ASaved.IssuesTracker);
  Assert.IsFalse(ASaved.IssuesQueryPicker);
  Assert.IsFalse(ASaved.IssuesCreate, 'Befehl abschaltbar (#1268)');
  Assert.IsFalse(ASaved.IssuesCreateIncludeCode);
  Assert.IsFalse(ASaved.TrackerLogin);
  Assert.IsTrue(ASaved.IssuesPreview);
  Assert.IsFalse(ASaved.IssuesPreviewComments);
  Assert.IsFalse(ASaved.IssuesCodeLinks);
  Assert.IsFalse(ASaved.IssuesBlameLinks);
  Assert.AreEqual(50, ASaved.IssuesBlameMaxRevisions);
  Assert.IsFalse(ASaved.IssuesPreviewChecklists);
  Assert.IsFalse(ASaved.IssuesChecklistStatus);
  Assert.IsFalse(ASaved.IssuesStatusState);
  Assert.AreEqual('never', ASaved.IssuesSprintOnStart);
  Assert.IsFalse(ASaved.IssuesPreviewLinks);
  Assert.IsFalse(ASaved.IssuesWarnBlocked);
  Assert.IsFalse(ASaved.IssuesBoard);
  Assert.IsFalse(ASaved.IssuesBoardConfirmMove);
  Assert.IsFalse(ASaved.IssuesBoardOnlyMine);
  Assert.IsFalse(ASaved.IssuesIdeColors);
  Assert.IsFalse(ASaved.IssuesSprintBurndown);
  Assert.IsFalse(ASaved.IssuesSprintCompare);
  Assert.IsFalse(ASaved.IssuesPaletteSearch);
  Assert.IsFalse(ASaved.IssuesPreviewDevelopment);
  Assert.IsTrue(ASaved.IssuesNotify);
  Assert.AreEqual(15, ASaved.IssuesNotifyIntervalMinutes);
  Assert.AreEqual('watched', ASaved.IssuesNotifyScope);
end;

/// <summary>Abschnitt nach erneutem Laden.</summary>
procedure AssertSectionReloaded(ASection: TAtlasTrackerSettingsSection);
begin
  Assert.AreEqual(2, ASection.General.View.Tracker.Choice);
  Assert.IsFalse(ASection.General.View.Login.Checked);
  Assert.IsFalse(ASection.General.View.PreviewComments.Checked);
  Assert.IsFalse(ASection.General.View.CodeLinks.Checked);
  Assert.IsFalse(ASection.General.View.BlameLinks.Checked);
  Assert.AreEqual('50', ASection.General.View.BlameMaxRevisions.Text);
  Assert.IsFalse(ASection.General.View.PreviewChecklists.Checked);
  Assert.IsFalse(ASection.General.View.ChecklistStatus.Checked);
  Assert.IsFalse(ASection.General.View.StatusState.Checked);
  Assert.AreEqual(2, ASection.General.View.SprintOnStart.Choice);
  Assert.IsFalse(ASection.General.View.PreviewLinks.Checked);
  Assert.IsFalse(ASection.General.View.WarnBlocked.Checked);
  Assert.IsFalse(ASection.General.View.Board.Checked);
  Assert.IsFalse(ASection.General.View.BoardConfirmMove.Checked);
  Assert.IsFalse(ASection.General.View.BoardOnlyMine.Checked);
  Assert.IsFalse(ASection.General.View.IdeColors.Checked);
  Assert.IsFalse(ASection.General.View.SprintBurndown.Checked);
  Assert.IsFalse(ASection.General.View.SprintCompare.Checked);
  Assert.IsFalse(ASection.General.View.PaletteSearch.Checked);
  Assert.IsFalse(ASection.General.View.PreviewDevelopment.Checked);
  Assert.IsTrue(ASection.General.View.Notify.Checked);
  Assert.AreEqual(2, ASection.General.View.NotifyScope.Choice);
end;

procedure TTrackerSettingsSectionTests.SettingsRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    AssertSectionDefaults(FSection);
    EditSection(FSection);
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    AssertSectionSaved(mSaved);
    mPage.LoadFrom(mSaved);
    AssertSectionReloaded(FSection);
    mPage.SaveTo(mSaved);
  finally
    mPage.Free;
  end;
end;



initialization
  TDUnitX.RegisterTestFixture(TTrackerSettingsSectionTests);

end.
