unit Atlas.Core.Tracker.SettingsTables;

// Tabellen der Seite Issue-Tracker im Optionsdialog (#1455), ohne VCL: Zeilen,
// gewählte Zeile und alles, was beim Bearbeiten geprüft wird. Die Oberfläche
// (Atlas.UI.Tracker.Settings*) zeigt nur, was diese Klassen sagen.
// - TAtlasTrackerConnectionTable: Verbindungen (#1260), persönliche zuerst,
//   dahinter die aus der .atlas (schreibgeschützt); Anbieter, laufende
//   Prüfungen, Werte für Zustand und Zuständigkeit (#1266).
// - TAtlasTrackerProjectTable: Zuordnung Delphi-Projekt → Tracker-Projekt
//   (#1261) mit dem Kontext der IDE (aktives Projekt, .groupproj, .atlas).
// - TAtlasTrackerQueryTable: benannte Abfragen (#1262).
// - TAtlasTrackerSnippetTable: Textbausteine für Kommentare (#1278).
// Projekte und Abfragen verweisen per Name auf eine Verbindung; die Namen zur
// Auswahl gibt TAtlasTrackerConnectionTable.Names, beim Umbenennen zieht
// RenameConnection die Verweise nach. Gespeichert werden nur vollständige
// Zeilen (ToJson). TAtlasTrackerSettingsTables hält die vier Tabellen und liest
// bzw. schreibt sie unter ihren Schlüsseln (issues.connections …).

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Projects,
  Atlas.Core.Tracker.Queries,
  Atlas.Core.Tracker.CommentEditor;

type
{$SCOPEDENUMS ON}
  /// <summary>Herkunft einer Zeile der Tabelle Projekte, wie die Spalte „Quelle“ sie zeigt.</summary>
  TAtlasTrackerProjectSource = (Personal, Covered, Team);
  /// <summary>Hinweis unter der Tabelle Projekte zur gewählten Zeile.</summary>
  TAtlasTrackerProjectNote = (None, ReadOnly, NoConnection, ConnectionMissing, Covered);
  /// <summary>Hinweis unter der Tabelle Abfragen zur gewählten Zeile.</summary>
  TAtlasTrackerQueryNote = (None, Empty, ConnectionMissing, NoRows);
{$SCOPEDENUMS OFF}

  /// <summary>Verbindungen der Seite: persönliche (gespeichert) und die aus der .atlas.</summary>
  TAtlasTrackerConnectionTable = class
  private
    FItems: TArray<TAtlasTrackerConnection>;
    FTeam: TArray<TAtlasTrackerConnection>;
    FSelected: Integer;
    FProviderNames: TArray<string>;
    FProviderCaptions: TArray<string>;
    /// <summary>Server (CredentialTarget), deren Prüfung läuft.</summary>
    FChecking: TArray<string>;
    procedure Clamp;
  public
    constructor Create;
    /// <summary>Zeilen aus issues.connections; die erste ist gewählt.</summary>
    procedure Load(const AJson: string);
    /// <summary>Gespeicherte Form: nur mit Name, Anbieter und gültiger Adresse, Namen eindeutig.</summary>
    function ToJson: string;
    /// <summary>Persönliche, dann die aus der .atlas.</summary>
    function Rows: TArray<TAtlasTrackerConnection>;
    procedure SetTeam(const ATeam: TArray<TAtlasTrackerConnection>);
    /// <summary>Anbieter der Auswahl; False (unverändert) bei leerer oder ungleich langer Liste.</summary>
    function SetProviders(const ANames, ACaptions: TArray<string>): Boolean;
    function ProviderCaption(const AName: string): string;
    /// <summary>Stelle von AName in den Anbietern; -1 ohne.</summary>
    function ProviderIndex(const AName: string): Integer;
    procedure Select(AIndex: Integer);
    function HasSelection: Boolean;
    /// <summary>Gewählt und persönlich (nicht aus der .atlas).</summary>
    function Editable: Boolean;
    function SelectedRow: TAtlasTrackerConnection;
    /// <summary>Namen der persönlichen Verbindungen, eindeutig: die Auswahl in Projekten und Abfragen.</summary>
    function Names: TArray<string>;
    function NameTaken(const AName: string): Boolean;
    /// <summary>Benennt die gewählte Zeile um; liefert den alten Namen.</summary>
    function Rename(const AName: string): string;
    /// <summary>Anbieter der gewählten Zeile; False bei ungültiger Wahl.</summary>
    function SetProvider(AChoice: Integer): Boolean;
    /// <summary>Prüft AUrl; nur eine gültige Adresse wird übernommen (Werte der Verbindung bleiben).</summary>
    function SetUrl(const AUrl: string): TAtlasTrackerUrlCheck;
    /// <summary>Zustand und Zuständigkeit der gewählten Zeile (#1266); AEndStates wie eingegeben.</summary>
    procedure SetWorkflow(const AStateField, AAssigneeField, AStartState, AEndStates: string);
    /// <summary>Neue Zeile ohne Adresse (gespeichert erst mit Adresse) mit freiem Namen nach ABaseName.</summary>
    procedure Add(const ABaseName: string);
    /// <summary>Entfernt die gewählte persönliche Zeile und liefert sie.</summary>
    function Remove: TAtlasTrackerConnection;
    function Checking(const AConnection: TAtlasTrackerConnection): Boolean;
    /// <summary>Prüfung der gewählten Zeile beginnt; False, wenn sie keinen Server hat oder schon läuft.</summary>
    function StartCheck(out AConnection: TAtlasTrackerConnection): Boolean;
    /// <summary>Prüfung fertig; ALanguage (erkannte Sprache, #1263) an die Zeilen zum selben Server.</summary>
    procedure CheckDone(const AConnection: TAtlasTrackerConnection; const ALanguage: string);
    /// <summary>Verbindung für „Werte vom Tracker laden“: die gewählte mit Server, sonst die erste mit Server.
    /// </summary>
    function ValuesConnection(out AConnection: TAtlasTrackerConnection): Boolean;
    property Items: TArray<TAtlasTrackerConnection> read FItems;
    property Selected: Integer read FSelected;
    property ProviderNames: TArray<string> read FProviderNames;
    property ProviderCaptions: TArray<string> read FProviderCaptions;
  end;

  /// <summary>Zuordnung Delphi-Projekt → Tracker-Projekt (#1261).</summary>
  TAtlasTrackerProjectTable = class
  private
    FItems: TArray<TAtlasTrackerProjectMapping>;
    FContext: TAtlasTrackerProjectContext;
    FChoices: TArray<string>;
    FSelected: Integer;
    procedure Clamp;
  public
    constructor Create;
    procedure Load(const AJson: string);
    /// <summary>Gespeicherte Form: nur mit Pfad und Verbindung, Pfade eindeutig.</summary>
    function ToJson: string;
    /// <summary>Persönliche, dann die aus der .atlas.</summary>
    function Rows: TArray<TAtlasTrackerProjectMapping>;
    procedure SetContext(const AContext: TAtlasTrackerProjectContext);
    /// <summary>Namen der Verbindungen zur Auswahl.</summary>
    procedure SetChoices(const ANames: TArray<string>);
    procedure Select(AIndex: Integer);
    function HasSelection: Boolean;
    function Editable: Boolean;
    function SelectedRow: TAtlasTrackerProjectMapping;
    function Covered(const AMapping: TAtlasTrackerProjectMapping): Boolean;
    function SourceOf(const AMapping: TAtlasTrackerProjectMapping): TAtlasTrackerProjectSource;
    function NoteOf(const AMapping: TAtlasTrackerProjectMapping): TAtlasTrackerProjectNote;
    /// <summary>Stelle von AConnection in der Auswahl; -1 ohne.</summary>
    function ChoiceOf(const AConnection: string): Integer;
    /// <summary>Ein Pfad hat höchstens eine persönliche Zeile: False, wenn eine andere AMatch schon hat.</summary>
    function SetMatch(const AMatch: string): Boolean;
    function SetConnection(AChoice: Integer): Boolean;
    procedure SetProject(const AProject: string);
    /// <summary>Zeile für AMatch wählen bzw. anlegen (mit der ersten Verbindung); False bei leerem Pfad.</summary>
    function Add(const AMatch: string): Boolean;
    procedure Remove;
    procedure RenameConnection(const AOld, ANew: string);
    /// <summary>Die geöffnete .groupproj, sonst die aktive .dproj; '' ohne Projekt.</summary>
    function CurrentMatch: string;
    property Items: TArray<TAtlasTrackerProjectMapping> read FItems;
    property Context: TAtlasTrackerProjectContext read FContext;
    property Choices: TArray<string> read FChoices;
    property Selected: Integer read FSelected;
  end;

  /// <summary>Benannte Abfragen (#1262). Auswahl der Verbindung: 0 = „(alle)“, dann die Namen.</summary>
  TAtlasTrackerQueryTable = class
  private
    FItems: TArray<TAtlasTrackerQuery>;
    FChoices: TArray<string>;
    FSelected: Integer;
    procedure Clamp;
  public
    constructor Create;
    procedure Load(const AJson: string);
    /// <summary>Gespeicherte Form: nur mit Name und Abfrage, Namen eindeutig.</summary>
    function ToJson: string;
    procedure SetChoices(const ANames: TArray<string>);
    procedure Select(AIndex: Integer);
    function Editable: Boolean;
    function SelectedRow: TAtlasTrackerQuery;
    /// <summary>0 für „(alle)“, sonst Stelle + 1; -1, wenn es die Verbindung nicht gibt.</summary>
    function ChoiceOf(const AConnection: string): Integer;
    function NoteOf(const AQuery: TAtlasTrackerQuery): TAtlasTrackerQueryNote;
    /// <summary>False bei leerem oder vergebenem Namen.</summary>
    function SetName(const AName: string): Boolean;
    procedure SetQuery(const AQuery: string);
    function SetConnection(AChoice: Integer): Boolean;
    procedure SetProject(const AProject: string);
    procedure Replace(const AQuery: TAtlasTrackerQuery);
    /// <summary>Neue Zeile ohne Abfrage mit freiem Namen ABaseName, ABaseName 2 …</summary>
    procedure Add(const ABaseName: string);
    procedure Remove;
    /// <summary>Namen der übrigen Zeilen (für den Dialog).</summary>
    function Taken: TArray<string>;
    procedure RenameConnection(const AOld, ANew: string);
    property Items: TArray<TAtlasTrackerQuery> read FItems;
    property Choices: TArray<string> read FChoices;
    property Selected: Integer read FSelected;
  end;

  /// <summary>Textbausteine für Kommentare (#1278). English: Sprache der Oberfläche für die Vorgaben (#1458).
  /// </summary>
  TAtlasTrackerSnippetTable = class
  private
    FItems: TArray<TAtlasCommentSnippet>;
    FSelected: Integer;
    FEnglish: Boolean;
    procedure Clamp;
  public
    constructor Create;
    procedure Load(const AJson: string);
    function ToJson: string;
    procedure Select(AIndex: Integer);
    function Editable: Boolean;
    function CanAdd: Boolean;
    procedure Add(const AName: string);
    procedure Remove;
    procedure Defaults;
    procedure SetName(const AName: string);
    /// <summary>Text wie im Kommentar: Zeilen mit #10.</summary>
    procedure SetText(const AText: string);
    /// <summary>Eine Zeile in der Tabelle; Umbrüche als „⏎“.</summary>
    class function Line(const AText: string): string; static;
    property Items: TArray<TAtlasCommentSnippet> read FItems;
    property Selected: Integer read FSelected;
    property English: Boolean read FEnglish write FEnglish;
  end;

  /// <summary>Die vier Tabellen der Seite; Load und Save über die Schlüssel der Einstellungen.</summary>
  TAtlasTrackerSettingsTables = class
  public const
    cConnectionsKey = 'issues.connections';
    cProjectsKey = 'issues.projects';
    cQueriesKey = 'issues.queries';
    cSnippetsKey = 'issues.commentSnippets';
  private
    FConnections: TAtlasTrackerConnectionTable;
    FProjects: TAtlasTrackerProjectTable;
    FQueries: TAtlasTrackerQueryTable;
    FSnippets: TAtlasTrackerSnippetTable;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Load(const AValues: IAtlasSettingsValues);
    procedure Save(const AValues: IAtlasSettingsValues);
    /// <summary>Verbindungsnamen an Projekte und Abfragen (Auswahl der Zeilen).</summary>
    procedure ShareNames;
    /// <summary>Verbindung umbenannt: Verweise in Projekten und Abfragen ziehen nach.</summary>
    procedure ConnectionRenamed(const AOld, ANew: string);
    property Connections: TAtlasTrackerConnectionTable read FConnections;
    property Projects: TAtlasTrackerProjectTable read FProjects;
    property Queries: TAtlasTrackerQueryTable read FQueries;
    property Snippets: TAtlasTrackerSnippetTable read FSnippets;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Atlas.Core.Tracker.Workflow;

const
  cNoRow = -1;
  cLineBreak = ' ⏎ ';
  /// <summary>Vorgabe der Anbieter, bis die IDE die angemeldeten nennt (SetProviders).</summary>
  cYouTrackCaption = 'YouTrack';
  cGitHubCaption = 'GitHub';

/// <summary>Erste Zeile gewählt, ohne Zeilen keine.</summary>
function FirstRow(ACount: Integer): Integer;
begin
  Result := cNoRow;
  if ACount > 0 then
  begin
    Result := 0;
  end;
end;

{ TAtlasTrackerConnectionTable }

constructor TAtlasTrackerConnectionTable.Create;
begin
  inherited Create;
  FSelected := cNoRow;
  FProviderNames := TArray<string>.Create(TAtlasTrackerTarget.YouTrack, TAtlasTrackerTarget.GitHub);
  FProviderCaptions := TArray<string>.Create(cYouTrackCaption, cGitHubCaption);
end;

procedure TAtlasTrackerConnectionTable.Clamp;
begin
  FSelected := Min(FSelected, High(Rows));
end;

procedure TAtlasTrackerConnectionTable.Load(const AJson: string);
begin
  FItems := TAtlasTrackerConnections.Read(AJson);
  FSelected := FirstRow(Length(FItems));
  Clamp;
end;

function TAtlasTrackerConnectionTable.ToJson: string;
var
  mKept: TArray<TAtlasTrackerConnection>;
  mConnection: TAtlasTrackerConnection;
  mComplete: Boolean;
begin
  mKept := nil;
  for mConnection in FItems do
  begin
    mComplete := (mConnection.Name <> '') and (mConnection.Provider <> '') and
      (TAtlasTrackerConnections.CheckUrl(mConnection.Url) = TAtlasTrackerUrlCheck.Valid);
    if mComplete and (TAtlasTrackerConnections.IndexOfName(mKept, mConnection.Name) < 0) then
    begin
      mKept := mKept + [mConnection];
    end;
  end;
  Result := TAtlasTrackerConnections.ToJson(mKept);
end;

function TAtlasTrackerConnectionTable.Rows: TArray<TAtlasTrackerConnection>;
begin
  Result := FItems + FTeam;
end;

procedure TAtlasTrackerConnectionTable.SetTeam(const ATeam: TArray<TAtlasTrackerConnection>);
begin
  FTeam := ATeam;
  Clamp;
end;

function TAtlasTrackerConnectionTable.SetProviders(const ANames, ACaptions: TArray<string>): Boolean;
begin
  Result := (Length(ANames) > 0) and (Length(ANames) = Length(ACaptions));
  if Result then
  begin
    FProviderNames := ANames;
    FProviderCaptions := ACaptions;
  end;
end;

function TAtlasTrackerConnectionTable.ProviderIndex(const AName: string): Integer;
var
  mIndex: Integer;
begin
  Result := cNoRow;
  for mIndex := 0 to High(FProviderNames) do
  begin
    if SameText(FProviderNames[mIndex], AName) then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TAtlasTrackerConnectionTable.ProviderCaption(const AName: string): string;
var
  mIndex: Integer;
begin
  Result := AName;
  mIndex := ProviderIndex(AName);
  if (mIndex >= 0) and (mIndex <= High(FProviderCaptions)) then
  begin
    Result := FProviderCaptions[mIndex];
  end;
end;

procedure TAtlasTrackerConnectionTable.Select(AIndex: Integer);
begin
  FSelected := AIndex;
  Clamp;
end;

function TAtlasTrackerConnectionTable.HasSelection: Boolean;
begin
  Result := (FSelected >= 0) and (FSelected <= High(Rows));
end;

function TAtlasTrackerConnectionTable.Editable: Boolean;
begin
  Result := (FSelected >= 0) and (FSelected < Length(FItems));
end;

function TAtlasTrackerConnectionTable.SelectedRow: TAtlasTrackerConnection;
begin
  Result := TAtlasTrackerConnection.Create('', '', '');
  if HasSelection then
  begin
    Result := Rows[FSelected];
  end;
end;

function TAtlasTrackerConnectionTable.Names: TArray<string>;
var
  mConnection: TAtlasTrackerConnection;
begin
  Result := nil;
  for mConnection in FItems do
  begin
    if (mConnection.Name <> '') and not MatchText(mConnection.Name, Result) then
    begin
      Result := Result + [mConnection.Name];
    end;
  end;
end;

function TAtlasTrackerConnectionTable.NameTaken(const AName: string): Boolean;
begin
  Result := TAtlasTrackerConnections.NameTaken(FItems, AName, FSelected);
end;

function TAtlasTrackerConnectionTable.Rename(const AName: string): string;
begin
  Result := '';
  if Editable then
  begin
    Result := FItems[FSelected].Name;
    FItems[FSelected].Name := AName;
  end;
end;

function TAtlasTrackerConnectionTable.SetProvider(AChoice: Integer): Boolean;
begin
  Result := Editable and (AChoice >= 0) and (AChoice <= High(FProviderNames));
  if Result then
  begin
    FItems[FSelected].Provider := FProviderNames[AChoice];
  end;
end;

function TAtlasTrackerConnectionTable.SetUrl(const AUrl: string): TAtlasTrackerUrlCheck;
begin
  Result := TAtlasTrackerConnections.CheckUrl(AUrl);
  if Editable and (Result = TAtlasTrackerUrlCheck.Valid) then
  begin
    FItems[FSelected] := FItems[FSelected].WithUrl(AUrl);
  end;
end;

procedure TAtlasTrackerConnectionTable.SetWorkflow(const AStateField, AAssigneeField, AStartState,
  AEndStates: string);
begin
  if Editable then
  begin
    FItems[FSelected].StateField := AStateField;
    FItems[FSelected].AssigneeField := AAssigneeField;
    FItems[FSelected].StartState := AStartState;
    FItems[FSelected].EndStates := TAtlasTrackerWorkflow.ParseList(AEndStates);
  end;
end;

procedure TAtlasTrackerConnectionTable.Add(const ABaseName: string);
begin
  FItems := FItems + [TAtlasTrackerConnection.Create(TAtlasTrackerConnections.FreeName(Rows, ABaseName),
    FProviderNames[0], '')];
  FSelected := High(FItems);
end;

function TAtlasTrackerConnectionTable.Remove: TAtlasTrackerConnection;
begin
  Result := TAtlasTrackerConnection.Create('', '', '');
  if Editable then
  begin
    Result := FItems[FSelected];
    Delete(FItems, FSelected, 1);
    Clamp;
  end;
end;

function TAtlasTrackerConnectionTable.Checking(const AConnection: TAtlasTrackerConnection): Boolean;
begin
  Result := MatchText(AConnection.Target.CredentialTarget, FChecking);
end;

function TAtlasTrackerConnectionTable.StartCheck(out AConnection: TAtlasTrackerConnection): Boolean;
var
  mServer: string;
begin
  AConnection := SelectedRow;
  mServer := AConnection.Target.CredentialTarget;
  Result := HasSelection and (mServer <> '') and not MatchText(mServer, FChecking);
  if Result then
  begin
    FChecking := FChecking + [mServer];
  end;
end;

procedure TAtlasTrackerConnectionTable.CheckDone(const AConnection: TAtlasTrackerConnection;
  const ALanguage: string);
var
  mIndex: Integer;
  mServer: string;
begin
  mServer := AConnection.Target.CredentialTarget;
  for mIndex := High(FChecking) downto 0 do
  begin
    if SameText(FChecking[mIndex], mServer) then
    begin
      Delete(FChecking, mIndex, 1);
    end;
  end;
  if ALanguage = '' then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FItems) do
  begin
    if SameText(FItems[mIndex].Target.CredentialTarget, mServer) then
    begin
      FItems[mIndex].Language := ALanguage;
    end;
  end;
end;

function TAtlasTrackerConnectionTable.ValuesConnection(out AConnection: TAtlasTrackerConnection): Boolean;
var
  mRow: TAtlasTrackerConnection;
begin
  AConnection := SelectedRow;
  Result := HasSelection and (AConnection.Target.Server <> '');
  if Result then
  begin
    Exit;
  end;
  for mRow in Rows do
  begin
    if mRow.Target.Server <> '' then
    begin
      AConnection := mRow;
      Exit(True);
    end;
  end;
  AConnection := TAtlasTrackerConnection.Create('', '', '');
end;

{ TAtlasTrackerProjectTable }

constructor TAtlasTrackerProjectTable.Create;
begin
  inherited Create;
  FSelected := cNoRow;
  FContext := TAtlasTrackerProjectContext.Empty;
end;

procedure TAtlasTrackerProjectTable.Clamp;
begin
  FSelected := Min(FSelected, High(Rows));
end;

procedure TAtlasTrackerProjectTable.Load(const AJson: string);
begin
  FItems := TAtlasTrackerProjects.Read(AJson);
  FSelected := FirstRow(Length(FItems));
  Clamp;
end;

function TAtlasTrackerProjectTable.ToJson: string;
var
  mKept: TArray<TAtlasTrackerProjectMapping>;
  mMapping: TAtlasTrackerProjectMapping;
begin
  mKept := nil;
  for mMapping in FItems do
  begin
    if (mMapping.Match <> '') and (mMapping.Connection <> '') and
      (TAtlasTrackerProjects.IndexOfMatch(mKept, mMapping.Match) < 0) then
    begin
      mKept := mKept + [mMapping];
    end;
  end;
  Result := TAtlasTrackerProjects.ToJson(mKept);
end;

function TAtlasTrackerProjectTable.Rows: TArray<TAtlasTrackerProjectMapping>;
begin
  Result := FItems + FContext.Team;
end;

procedure TAtlasTrackerProjectTable.SetContext(const AContext: TAtlasTrackerProjectContext);
begin
  FContext := AContext;
  Clamp;
end;

procedure TAtlasTrackerProjectTable.SetChoices(const ANames: TArray<string>);
begin
  FChoices := ANames;
end;

procedure TAtlasTrackerProjectTable.Select(AIndex: Integer);
begin
  FSelected := AIndex;
  Clamp;
end;

function TAtlasTrackerProjectTable.HasSelection: Boolean;
begin
  Result := (FSelected >= 0) and (FSelected <= High(Rows));
end;

function TAtlasTrackerProjectTable.Editable: Boolean;
begin
  Result := (FSelected >= 0) and (FSelected < Length(FItems));
end;

function TAtlasTrackerProjectTable.SelectedRow: TAtlasTrackerProjectMapping;
begin
  Result := TAtlasTrackerProjectMapping.Create('', '', '');
  if HasSelection then
  begin
    Result := Rows[FSelected];
  end;
end;

function TAtlasTrackerProjectTable.Covered(const AMapping: TAtlasTrackerProjectMapping): Boolean;
begin
  Result := TAtlasTrackerProjects.Covered(AMapping, FContext.HasTeam, FContext.ProjectFile, FContext.GroupFile);
end;

function TAtlasTrackerProjectTable.SourceOf(const AMapping: TAtlasTrackerProjectMapping): TAtlasTrackerProjectSource;
begin
  Result := TAtlasTrackerProjectSource.Personal;
  if AMapping.ReadOnly then
  begin
    Result := TAtlasTrackerProjectSource.Team;
  end
  else if Covered(AMapping) then
  begin
    Result := TAtlasTrackerProjectSource.Covered;
  end;
end;

function TAtlasTrackerProjectTable.NoteOf(const AMapping: TAtlasTrackerProjectMapping): TAtlasTrackerProjectNote;
begin
  Result := TAtlasTrackerProjectNote.None;
  if AMapping.ReadOnly then
  begin
    Result := TAtlasTrackerProjectNote.ReadOnly;
  end
  else if Length(FChoices) = 0 then
  begin
    Result := TAtlasTrackerProjectNote.NoConnection;
  end
  else if not MatchText(AMapping.Connection, FChoices) then
  begin
    Result := TAtlasTrackerProjectNote.ConnectionMissing;
  end
  else if Covered(AMapping) then
  begin
    Result := TAtlasTrackerProjectNote.Covered;
  end;
end;

function TAtlasTrackerProjectTable.ChoiceOf(const AConnection: string): Integer;
var
  mIndex: Integer;
begin
  Result := cNoRow;
  for mIndex := 0 to High(FChoices) do
  begin
    if SameText(FChoices[mIndex], AConnection) then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TAtlasTrackerProjectTable.SetMatch(const AMatch: string): Boolean;
var
  mOther: Integer;
begin
  mOther := TAtlasTrackerProjects.IndexOfMatch(FItems, AMatch);
  Result := Editable and ((AMatch = '') or (mOther < 0) or (mOther = FSelected));
  if Result then
  begin
    FItems[FSelected].Match := AMatch;
  end;
end;

function TAtlasTrackerProjectTable.SetConnection(AChoice: Integer): Boolean;
begin
  Result := Editable and (AChoice >= 0) and (AChoice <= High(FChoices));
  if Result then
  begin
    FItems[FSelected].Connection := FChoices[AChoice];
  end;
end;

procedure TAtlasTrackerProjectTable.SetProject(const AProject: string);
begin
  if Editable then
  begin
    FItems[FSelected].Project := AProject;
  end;
end;

function TAtlasTrackerProjectTable.Add(const AMatch: string): Boolean;
var
  mIndex: Integer;
  mConnection: string;
begin
  Result := Trim(AMatch) <> '';
  if not Result then
  begin
    Exit;
  end;
  mIndex := TAtlasTrackerProjects.IndexOfMatch(FItems, AMatch);
  if mIndex < 0 then
  begin
    // Vorbelegt mit der ersten Verbindung; das Tracker-Projekt trägt man selbst ein.
    mConnection := '';
    if Length(FChoices) > 0 then
    begin
      mConnection := FChoices[0];
    end;
    FItems := FItems + [TAtlasTrackerProjectMapping.Create(AMatch, mConnection, '')];
    mIndex := High(FItems);
  end;
  FSelected := mIndex;
end;

procedure TAtlasTrackerProjectTable.Remove;
begin
  if Editable then
  begin
    Delete(FItems, FSelected, 1);
    Clamp;
  end;
end;

procedure TAtlasTrackerProjectTable.RenameConnection(const AOld, ANew: string);
var
  mIndex: Integer;
begin
  if AOld = '' then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FItems) do
  begin
    if SameText(FItems[mIndex].Connection, AOld) then
    begin
      FItems[mIndex].Connection := ANew;
    end;
  end;
end;

function TAtlasTrackerProjectTable.CurrentMatch: string;
begin
  Result := '';
  if FContext.ProjectFile <> '' then
  begin
    Result := TAtlasTrackerProjects.CurrentMatch(FContext.ProjectFile, FContext.GroupFile);
  end;
end;

{ TAtlasTrackerQueryTable }

constructor TAtlasTrackerQueryTable.Create;
begin
  inherited Create;
  FSelected := cNoRow;
end;

procedure TAtlasTrackerQueryTable.Clamp;
begin
  FSelected := Min(FSelected, High(FItems));
end;

procedure TAtlasTrackerQueryTable.Load(const AJson: string);
begin
  FItems := TAtlasTrackerQueries.Read(AJson);
  FSelected := FirstRow(Length(FItems));
end;

function TAtlasTrackerQueryTable.ToJson: string;
var
  mKept: TArray<TAtlasTrackerQuery>;
  mQuery: TAtlasTrackerQuery;
begin
  mKept := nil;
  for mQuery in FItems do
  begin
    if (mQuery.Name <> '') and (mQuery.Query <> '') and (TAtlasTrackerQueries.IndexOfName(mKept, mQuery.Name) < 0) then
    begin
      mKept := mKept + [mQuery];
    end;
  end;
  Result := TAtlasTrackerQueries.ToJson(mKept);
end;

procedure TAtlasTrackerQueryTable.SetChoices(const ANames: TArray<string>);
begin
  FChoices := ANames;
end;

procedure TAtlasTrackerQueryTable.Select(AIndex: Integer);
begin
  FSelected := AIndex;
  Clamp;
end;

function TAtlasTrackerQueryTable.Editable: Boolean;
begin
  Result := (FSelected >= 0) and (FSelected <= High(FItems));
end;

function TAtlasTrackerQueryTable.SelectedRow: TAtlasTrackerQuery;
begin
  Result := TAtlasTrackerQuery.Create('', '', '', '');
  if Editable then
  begin
    Result := FItems[FSelected];
  end;
end;

function TAtlasTrackerQueryTable.ChoiceOf(const AConnection: string): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  if AConnection = '' then
  begin
    Exit;
  end;
  Result := cNoRow;
  for mIndex := 0 to High(FChoices) do
  begin
    if SameText(FChoices[mIndex], AConnection) then
    begin
      Exit(mIndex + 1);
    end;
  end;
end;

function TAtlasTrackerQueryTable.NoteOf(const AQuery: TAtlasTrackerQuery): TAtlasTrackerQueryNote;
begin
  Result := TAtlasTrackerQueryNote.None;
  if AQuery.Query = '' then
  begin
    Result := TAtlasTrackerQueryNote.Empty;
  end
  else if (AQuery.Connection <> '') and (ChoiceOf(AQuery.Connection) < 0) then
  begin
    Result := TAtlasTrackerQueryNote.ConnectionMissing;
  end;
end;

function TAtlasTrackerQueryTable.SetName(const AName: string): Boolean;
var
  mOther: Integer;
begin
  mOther := TAtlasTrackerQueries.IndexOfName(FItems, AName);
  Result := Editable and (AName <> '') and ((mOther < 0) or (mOther = FSelected));
  if Result then
  begin
    FItems[FSelected].Name := AName;
  end;
end;

procedure TAtlasTrackerQueryTable.SetQuery(const AQuery: string);
var
  mRow: TAtlasTrackerQuery;
begin
  if Editable then
  begin
    // Einzeilig wie beim Lesen (TAtlasTrackerQuery.Create).
    mRow := FItems[FSelected];
    FItems[FSelected] := TAtlasTrackerQuery.Create(mRow.Name, AQuery, mRow.Connection, mRow.Project);
  end;
end;

function TAtlasTrackerQueryTable.SetConnection(AChoice: Integer): Boolean;
begin
  Result := Editable and (AChoice >= 0) and (AChoice <= Length(FChoices));
  if not Result then
  begin
    Exit;
  end;
  FItems[FSelected].Connection := '';
  if AChoice > 0 then
  begin
    FItems[FSelected].Connection := FChoices[AChoice - 1];
  end;
end;

procedure TAtlasTrackerQueryTable.SetProject(const AProject: string);
begin
  if Editable then
  begin
    FItems[FSelected].Project := AProject;
  end;
end;

procedure TAtlasTrackerQueryTable.Replace(const AQuery: TAtlasTrackerQuery);
begin
  if Editable then
  begin
    FItems[FSelected] := AQuery;
  end;
end;

procedure TAtlasTrackerQueryTable.Add(const ABaseName: string);
var
  mName: string;
  mNumber: Integer;
begin
  mName := ABaseName;
  mNumber := 1;
  while TAtlasTrackerQueries.IndexOfName(FItems, mName) >= 0 do
  begin
    Inc(mNumber);
    mName := ABaseName + ' ' + IntToStr(mNumber);
  end;
  FItems := FItems + [TAtlasTrackerQuery.Create(mName, '', '', '')];
  FSelected := High(FItems);
end;

procedure TAtlasTrackerQueryTable.Remove;
begin
  if Editable then
  begin
    Delete(FItems, FSelected, 1);
    Clamp;
  end;
end;

function TAtlasTrackerQueryTable.Taken: TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(FItems) do
  begin
    if mIndex <> FSelected then
    begin
      Result := Result + [FItems[mIndex].Name];
    end;
  end;
end;

procedure TAtlasTrackerQueryTable.RenameConnection(const AOld, ANew: string);
begin
  TAtlasTrackerQueries.RenameConnection(FItems, AOld, ANew);
end;

{ TAtlasTrackerSnippetTable }

constructor TAtlasTrackerSnippetTable.Create;
begin
  inherited Create;
  FSelected := cNoRow;
end;

procedure TAtlasTrackerSnippetTable.Clamp;
begin
  FSelected := Min(FSelected, High(FItems));
end;

procedure TAtlasTrackerSnippetTable.Load(const AJson: string);
begin
  FItems := TAtlasCommentSnippets.Read(AJson, FEnglish);
  FSelected := FirstRow(Length(FItems));
end;

function TAtlasTrackerSnippetTable.ToJson: string;
begin
  Result := TAtlasCommentSnippets.ToJson(FItems);
end;

procedure TAtlasTrackerSnippetTable.Select(AIndex: Integer);
begin
  FSelected := AIndex;
  Clamp;
end;

function TAtlasTrackerSnippetTable.Editable: Boolean;
begin
  Result := (FSelected >= 0) and (FSelected <= High(FItems));
end;

function TAtlasTrackerSnippetTable.CanAdd: Boolean;
begin
  Result := Length(FItems) < TAtlasCommentSnippets.MaxSnippets;
end;

procedure TAtlasTrackerSnippetTable.Add(const AName: string);
begin
  if CanAdd then
  begin
    // Ohne Text wird der Baustein nicht gespeichert (TAtlasCommentSnippets.Parse lässt ihn fallen).
    FItems := FItems + [TAtlasCommentSnippet.Create(AName, '')];
    FSelected := High(FItems);
  end;
end;

procedure TAtlasTrackerSnippetTable.Remove;
begin
  if Editable then
  begin
    Delete(FItems, FSelected, 1);
    Clamp;
  end;
end;

procedure TAtlasTrackerSnippetTable.Defaults;
begin
  FItems := TAtlasCommentSnippets.Defaults(FEnglish);
  FSelected := FirstRow(Length(FItems));
end;

procedure TAtlasTrackerSnippetTable.SetName(const AName: string);
begin
  if Editable then
  begin
    FItems[FSelected].Name := AName;
  end;
end;

procedure TAtlasTrackerSnippetTable.SetText(const AText: string);
begin
  if Editable then
  begin
    FItems[FSelected].Text := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
  end;
end;

{ TAtlasTrackerSettingsTables }

constructor TAtlasTrackerSettingsTables.Create;
begin
  inherited Create;
  FConnections := TAtlasTrackerConnectionTable.Create;
  FProjects := TAtlasTrackerProjectTable.Create;
  FQueries := TAtlasTrackerQueryTable.Create;
  FSnippets := TAtlasTrackerSnippetTable.Create;
end;

destructor TAtlasTrackerSettingsTables.Destroy;
begin
  FSnippets.Free;
  FQueries.Free;
  FProjects.Free;
  FConnections.Free;
  inherited Destroy;
end;

procedure TAtlasTrackerSettingsTables.Load(const AValues: IAtlasSettingsValues);
begin
  FConnections.Load(AValues.ReadString(cConnectionsKey));
  FProjects.Load(AValues.ReadString(cProjectsKey));
  FQueries.Load(AValues.ReadString(cQueriesKey));
  FSnippets.Load(AValues.ReadString(cSnippetsKey));
  ShareNames;
end;

procedure TAtlasTrackerSettingsTables.Save(const AValues: IAtlasSettingsValues);
begin
  AValues.WriteString(cConnectionsKey, FConnections.ToJson);
  AValues.WriteString(cProjectsKey, FProjects.ToJson);
  AValues.WriteString(cQueriesKey, FQueries.ToJson);
  AValues.WriteString(cSnippetsKey, FSnippets.ToJson);
end;

procedure TAtlasTrackerSettingsTables.ShareNames;
var
  mNames: TArray<string>;
begin
  mNames := FConnections.Names;
  FProjects.SetChoices(mNames);
  FQueries.SetChoices(mNames);
end;

procedure TAtlasTrackerSettingsTables.ConnectionRenamed(const AOld, ANew: string);
begin
  FProjects.RenameConnection(AOld, ANew);
  FQueries.RenameConnection(AOld, ANew);
  ShareNames;
end;

class function TAtlasTrackerSnippetTable.Line(const AText: string): string;
begin
  Result := StringReplace(StringReplace(AText, #13#10, #10, [rfReplaceAll]), #10, cLineBreak, [rfReplaceAll]);
end;

end.
