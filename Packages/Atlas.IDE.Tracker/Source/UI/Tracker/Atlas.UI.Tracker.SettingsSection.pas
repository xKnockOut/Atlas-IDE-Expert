unit Atlas.UI.Tracker.SettingsSection;

// Abschnitt „Issue-Tracker“ des Moduls Tracker im Optionsdialog (#1455; vorher Teil von Atlas.UI.Settings.Page).
// Die Seite von Base baut ihn über IAtlasSettingsSectionHost in den Bereich „issues“. Der
// Abschnitt fügt nur die Teile zusammen:
// - TAtlasTrackerSettingsTables (Core): Zeilen der Tabellen und ihre Regeln.
// - Teile der Oberfläche: Verbindungen (#1260), Projekte (#1261), Abfragen
//   (#1262), Allgemein, Zustand im Tracker (#1266), Textbausteine (#1278).
// - TAtlasTrackerSettingsHooks: Netz, Anmeldespeicher und Projekt der IDE;
//   sie setzt Atlas.IDE.Tracker.Settings. Ohne Haken: keine Prüfung, kein
//   Token.
// Close gibt Teile, Steuerelemente und Haken frei; danach erreicht den
// Abschnitt nichts mehr (Regel 3).

interface

uses
  Vcl.StdCtrls,
  Atlas.Core.Settings.Contract,
  Atlas.UI.Settings.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Workflow,
  Atlas.Core.Tracker.SettingsTables,
  Atlas.UI.Tracker.SettingsRows,
  Atlas.UI.Tracker.SettingsConnections,
  Atlas.UI.Tracker.SettingsProjects,
  Atlas.UI.Tracker.SettingsQueries,
  Atlas.UI.Tracker.SettingsSnippets,
  Atlas.UI.Tracker.SettingsWorkflow,
  Atlas.UI.Tracker.SettingsGeneral;

type
  TAtlasTrackerSettingsSection = class(TInterfacedObject, IAtlasSettingsSection)
  public const
    cOwnerId = 'atlas.tracker';
    cAreaId = 'issues';
    cEnabledKey = 'issues.enabled';
  private
    FEnabled: TCheckBox;
    FRows: TAtlasTrackerSettingsRows;
    FHooks: TAtlasTrackerSettingsHooks;
    FTables: TAtlasTrackerSettingsTables;
    FConnections: TAtlasTrackerConnectionsPart;
    FProjects: TAtlasTrackerProjectsPart;
    FQueries: TAtlasTrackerQueriesPart;
    FSnippets: TAtlasTrackerSnippetsPart;
    FWorkflow: TAtlasTrackerWorkflowPart;
    FGeneral: TAtlasTrackerGeneralPart;
    FClosed: Boolean;
    function Active: Boolean;
    procedure ConnectionsChanged;
    procedure ProjectsChanged;
  public
    constructor Create;
    destructor Destroy; override;
    { IAtlasSettingsSection }
    function OwnerId: string;
    function AreaId: string;
    procedure Build(const AHost: IAtlasSettingsSectionHost);
    procedure Load(const AValues: IAtlasSettingsValues);
    procedure Save(const AValues: IAtlasSettingsValues);
    procedure WindowReady;
    function Show(const AKey, AArgument: string): Boolean;
    procedure Close;
    /// <summary>Anbieter der Auswahl (Namen und Beschriftungen); auch vor Build.</summary>
    procedure SetTrackerProviders(const ANames, ACaptions: TArray<string>);
    /// <summary>Prüfung einer Verbindung ist fertig (Zustand über Hooks.OnState).</summary>
    procedure TrackerCheckDone(const AConnection: TAtlasTrackerConnection);
    /// <summary>Werte vom Tracker sind da (#1266): AError '' = geladen, sonst der Grund.</summary>
    procedure TrackerValuesDone(const AValues: TAtlasTrackerValueSet; const AError: string);
    /// <summary>„zuordnen …“ aus „Meine Issues“ (#1261): Zeile für AMatch anlegen bzw. wählen und zeigen.</summary>
    procedure AssignTrackerProject(const AMatch: string);
    property Closed: Boolean read FClosed;
    /// <summary>Schalter des Moduls (issues.enabled); früher in Base (#1456).</summary>
    property Enabled: TCheckBox read FEnabled;
    property Hooks: TAtlasTrackerSettingsHooks read FHooks;
    property Tables: TAtlasTrackerSettingsTables read FTables;
    property Connections: TAtlasTrackerConnectionsPart read FConnections;
    property Projects: TAtlasTrackerProjectsPart read FProjects;
    property Queries: TAtlasTrackerQueriesPart read FQueries;
    property Snippets: TAtlasTrackerSnippetsPart read FSnippets;
    property Workflow: TAtlasTrackerWorkflowPart read FWorkflow;
    property General: TAtlasTrackerGeneralPart read FGeneral;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Tracker.Strings;

{ TAtlasTrackerSettingsSection }

constructor TAtlasTrackerSettingsSection.Create;
begin
  inherited Create;
  FHooks := TAtlasTrackerSettingsHooks.Create;
  FTables := TAtlasTrackerSettingsTables.Create;
  FTables.Snippets.English := TAtlasTrackerStrings.English;
end;

destructor TAtlasTrackerSettingsSection.Destroy;
begin
  Close;
  FreeAndNil(FTables);
  inherited Destroy;
end;

function TAtlasTrackerSettingsSection.OwnerId: string;
begin
  Result := cOwnerId;
end;

function TAtlasTrackerSettingsSection.AreaId: string;
begin
  Result := cAreaId;
end;

function TAtlasTrackerSettingsSection.Active: Boolean;
begin
  Result := not FClosed and (FRows <> nil) and FRows.Active;
end;

procedure TAtlasTrackerSettingsSection.Build(const AHost: IAtlasSettingsSectionHost);
begin
  if FClosed or (FRows <> nil) then
  begin
    Exit;
  end;
  FRows := TAtlasTrackerSettingsRows.Create(AHost);
  FEnabled := AHost.AddModuleSwitch(cEnabledKey) as TCheckBox;
  FConnections := TAtlasTrackerConnectionsPart.Create(FRows, FHooks, FTables, ConnectionsChanged);
  FProjects := TAtlasTrackerProjectsPart.Create(FRows, FHooks, FTables, ProjectsChanged);
  FQueries := TAtlasTrackerQueriesPart.Create(FRows, FHooks, FTables);
  FGeneral := TAtlasTrackerGeneralPart.Create(FRows);
  FWorkflow := TAtlasTrackerWorkflowPart.Create(FRows, FHooks, FTables);
  FSnippets := TAtlasTrackerSnippetsPart.Create(FRows, FTables);
  // Reihenfolge der Seite: Tabellen (Mockups IT1 bis IT3), Allgemein, Zustand, Zeit, Textbausteine, Rest.
  FConnections.Build;
  FProjects.Build;
  FQueries.Build;
  FGeneral.BuildStart;
  FWorkflow.Build;
  FGeneral.BuildTime;
  FSnippets.Build;
  FGeneral.BuildMore;
end;

procedure TAtlasTrackerSettingsSection.Load(const AValues: IAtlasSettingsValues);
begin
  if not Active then
  begin
    Exit;
  end;
  // Gebundene Felder hat die Seite schon geladen; hier die eigenen Zeilen.
  FTables.Load(AValues);
  FWorkflow.Load(AValues);
  FSnippets.Refresh;
  // Baut über ConnectionsChanged auch Projekte und Abfragen.
  FConnections.Refresh;
end;

procedure TAtlasTrackerSettingsSection.Save(const AValues: IAtlasSettingsValues);
begin
  if not Active then
  begin
    Exit;
  end;
  FTables.Save(AValues);
  FWorkflow.Save(AValues);
end;

procedure TAtlasTrackerSettingsSection.WindowReady;
begin
  if Active then
  begin
    FConnections.Refresh;
    FSnippets.Refresh;
  end;
end;

function TAtlasTrackerSettingsSection.Show(const AKey, AArgument: string): Boolean;
begin
  Result := Active and SameText(AKey, TAtlasTrackerSettingsTables.cProjectsKey);
  if Result and (AArgument <> '') then
  begin
    AssignTrackerProject(AArgument);
  end;
end;

procedure TAtlasTrackerSettingsSection.Close;
begin
  if FClosed then
  begin
    Exit;
  end;
  FClosed := True;
  // Rückwärts zum Aufbau: Teile, dann die Steuerelemente, zuletzt die Haken zur IDE.
  FreeAndNil(FSnippets);
  FreeAndNil(FWorkflow);
  FreeAndNil(FGeneral);
  FreeAndNil(FQueries);
  FreeAndNil(FProjects);
  FreeAndNil(FConnections);
  FreeAndNil(FRows);
  // Der Schalter gehört der Seite.
  FEnabled := nil;
  FreeAndNil(FHooks);
end;

procedure TAtlasTrackerSettingsSection.ConnectionsChanged;
begin
  FProjects.Refresh;
end;

procedure TAtlasTrackerSettingsSection.ProjectsChanged;
begin
  FQueries.Refresh;
end;

procedure TAtlasTrackerSettingsSection.SetTrackerProviders(const ANames, ACaptions: TArray<string>);
begin
  if FClosed or not FTables.Connections.SetProviders(ANames, ACaptions) then
  begin
    Exit;
  end;
  // Vor Build (aus CreateSection) übernimmt der Aufbau die Auswahl.
  if Active then
  begin
    FConnections.ProvidersChanged;
  end;
end;

procedure TAtlasTrackerSettingsSection.TrackerCheckDone(const AConnection: TAtlasTrackerConnection);
var
  mLanguage: string;
begin
  // Späte Antwort nach dem Schließen: verfällt (Regel 3).
  if not Active then
  begin
    Exit;
  end;
  // Erkannte Sprache der Oberfläche (#1263) an den persönlichen Verbindungen merken; gespeichert mit OK.
  mLanguage := '';
  if Assigned(FHooks.OnState) then
  begin
    mLanguage := FHooks.OnState(AConnection).Language;
  end;
  FTables.Connections.CheckDone(AConnection, mLanguage);
  FConnections.Refresh;
end;

procedure TAtlasTrackerSettingsSection.TrackerValuesDone(const AValues: TAtlasTrackerValueSet; const AError: string);
begin
  // Späte Antwort nach dem Schließen: verfällt (Regel 3).
  if not Active then
  begin
    Exit;
  end;
  FWorkflow.ValuesDone(AValues, AError);
  if AError = '' then
  begin
    FConnections.ValuesLoaded(AValues);
  end;
end;

procedure TAtlasTrackerSettingsSection.AssignTrackerProject(const AMatch: string);
begin
  if Active then
  begin
    FProjects.AddMatch(AMatch);
    FRows.Reveal(TAtlasTrackerSettingsTables.cProjectsKey);
  end;
end;

end.
