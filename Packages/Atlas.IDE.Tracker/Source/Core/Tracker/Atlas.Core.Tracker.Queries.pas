unit Atlas.Core.Tracker.Queries;

// Benannte Abfragen für „Meine Issues“ (#1262), ohne VCL und Open Tools API.
// - TAtlasTrackerQuery: Name, Abfrage in der Syntax des Trackers (ohne
//   "project: …", das setzt der Anbieter davor), optional Verbindung (Name aus
//   issues.connections, #1260) und Tracker-Projekt. Persönlich in
//   %APPDATA%\Atlas\settings.json unter issues.queries
//   (TAtlasPluginSettings.IssuesQueries, JSON-Text).
// - Available: die Abfragen, die zum Tracker eines Projekts passen. Ohne
//   Verbindung gilt eine Abfrage überall; mit Verbindung nur, wo diese
//   Verbindung gilt (gleicher Name oder gleicher Anbieter und Server, damit
//   auch der Tracker aus der .atlas passt); mit Projekt nur für dieses
//   Tracker-Projekt. Passt keine, gilt die Vorgabe des Anbieters
//   („Mir zugewiesen“, Abfrage leer = IAtlasTrackerProvider.DefaultQuery).
// - Choose: die gewählte Abfrage je Projekt (gemerkt in der
//   Projekt-Zusammenfassung); ohne Klappliste (issues.queryPicker aus) oder
//   wenn es die gewählte nicht mehr gibt, die erste passende.
// Die Übernahme des früheren issues.query als „Standard“ liegt bei den
// Einstellungen (Atlas.Core.Settings.QueryMigration).
// Ohne Netz, ohne Dateizugriff.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections;

type
  TAtlasTrackerQuery = record
    Name: string;
    /// <summary>Syntax des Trackers; '' = Vorgabe des Anbieters.</summary>
    Query: string;
    /// <summary>Name der Verbindung; '' = überall.</summary>
    Connection: string;
    /// <summary>Tracker-Projekt; '' = jedes.</summary>
    Project: string;
    /// <summary>Vorgabe des Anbieters, wenn keine eigene Abfrage passt; nie gespeichert.</summary>
    Builtin: Boolean;
    class function Create(const AName, AQuery, AConnection, AProject: string): TAtlasTrackerQuery; static;
    /// <summary>Vorgabe des Anbieters mit Anzeigename AName (z. B. „Mir zugewiesen“).</summary>
    class function Fallback(const AName: string): TAtlasTrackerQuery; static;
  end;

  TAtlasTrackerQueries = class
  public
    /// <summary>Zeilen aus issues.queries; ohne Name oder Abfrage und doppelte Namen fallen weg.</summary>
    class function Read(const AJson: string): TArray<TAtlasTrackerQuery>; static;
    /// <summary>JSON-Text für issues.queries; Vorgaben (Builtin) fallen weg.</summary>
    class function ToJson(const AItems: TArray<TAtlasTrackerQuery>): string; static;
    class function IndexOfName(const AItems: TArray<TAtlasTrackerQuery>; const AName: string): Integer; static;
    /// <summary>Gilt AQuery für ATarget mit der Verbindung AConnectionName ('' bei .atlas ohne Namen)?</summary>
    class function Applies(const AQuery: TAtlasTrackerQuery; const ATarget: TAtlasTrackerTarget;
      const AConnectionName: string; const AConnections: TArray<TAtlasTrackerConnection>): Boolean; static;
    /// <summary>Passende Abfragen in ihrer Reihenfolge; ohne Treffer die Vorgabe ADefaultName; ohne Tracker leer.
    /// </summary>
    class function Available(const AItems: TArray<TAtlasTrackerQuery>; const ATarget: TAtlasTrackerTarget;
      const AConnectionName: string; const AConnections: TArray<TAtlasTrackerConnection>;
      const ADefaultName: string): TArray<TAtlasTrackerQuery>; static;
    /// <summary>Index der gewählten Abfrage ASelected in AAvailable; ohne Klappliste (APicker False) oder ohne
    /// Treffer 0; -1 bei leerer Liste.</summary>
    class function Choose(const AAvailable: TArray<TAtlasTrackerQuery>; const ASelected: string;
      APicker: Boolean): Integer; static;
    /// <summary>Verbindung AOld heißt jetzt ANew: Zeilen mit AOld nachziehen.</summary>
    class procedure RenameConnection(var AItems: TArray<TAtlasTrackerQuery>; const AOld, ANew: string); static;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Text.Json;

{ TAtlasTrackerQuery }

class function TAtlasTrackerQuery.Create(const AName, AQuery, AConnection, AProject: string): TAtlasTrackerQuery;
begin
  Result.Name := Trim(AName);
  // Einzeilig: der Anbieter hängt die Abfrage an die Adresse.
  Result.Query := Trim(AQuery.Replace(#13#10, ' ').Replace(#10, ' ').Replace(#13, ' '));
  Result.Connection := Trim(AConnection);
  Result.Project := Trim(AProject);
  Result.Builtin := False;
end;

class function TAtlasTrackerQuery.Fallback(const AName: string): TAtlasTrackerQuery;
begin
  Result := Create(AName, '', '', '');
  Result.Builtin := True;
end;

{ TAtlasTrackerQueries }

function Quoted(const AText: string): string;
var
  mValue: TJSONString;
begin
  mValue := TJSONString.Create(AText);
  try
    // Ohne Option: Umlaute bleiben lesbar (ToJSON ohne Argument schreibt sie als \u-Folge).
    Result := mValue.ToJSON([]);
  finally
    mValue.Free;
  end;
end;

class function TAtlasTrackerQueries.Read(const AJson: string): TArray<TAtlasTrackerQuery>;
var
  mRoot: TJSONValue;
  mItem: TJSONValue;
  mQuery: TAtlasTrackerQuery;
begin
  Result := nil;
  if Trim(AJson) = '' then
  begin
    Exit;
  end;
  mRoot := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mRoot is TJSONArray) then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mRoot) do
    begin
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      mQuery := TAtlasTrackerQuery.Create(TJsonRead.Text(TJSONObject(mItem), 'name'), TJsonRead.Text(TJSONObject(mItem), 'query'),
        TJsonRead.Text(TJSONObject(mItem), 'connection'), TJsonRead.Text(TJSONObject(mItem), 'project'));
      if (mQuery.Name = '') or (mQuery.Query = '') or (IndexOfName(Result, mQuery.Name) >= 0) then
      begin
        Continue;
      end;
      Result := Result + [mQuery];
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasTrackerQueries.ToJson(const AItems: TArray<TAtlasTrackerQuery>): string;
var
  mItem: TAtlasTrackerQuery;
  mParts: TArray<string>;
  mPart: string;
begin
  mParts := nil;
  for mItem in AItems do
  begin
    if mItem.Builtin then
    begin
      Continue;
    end;
    mPart := '{"name": ' + Quoted(mItem.Name) + ', "query": ' + Quoted(mItem.Query);
    if mItem.Connection <> '' then
    begin
      mPart := mPart + ', "connection": ' + Quoted(mItem.Connection);
    end;
    if mItem.Project <> '' then
    begin
      mPart := mPart + ', "project": ' + Quoted(mItem.Project);
    end;
    mParts := mParts + [mPart + '}'];
  end;
  Result := '[' + string.Join(', ', mParts) + ']';
end;

class function TAtlasTrackerQueries.IndexOfName(const AItems: TArray<TAtlasTrackerQuery>;
  const AName: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(AItems) do
  begin
    if SameText(AItems[mIndex].Name, Trim(AName)) then
    begin
      Exit(mIndex);
    end;
  end;
end;

class function TAtlasTrackerQueries.Applies(const AQuery: TAtlasTrackerQuery; const ATarget: TAtlasTrackerTarget;
  const AConnectionName: string; const AConnections: TArray<TAtlasTrackerConnection>): Boolean;
var
  mIndex: Integer;
  mConnection: TAtlasTrackerConnection;
begin
  if not ATarget.Configured then
  begin
    Exit(False);
  end;
  if (AQuery.Project <> '') and not SameText(AQuery.Project, ATarget.Project) then
  begin
    Exit(False);
  end;
  if (AQuery.Connection = '') or SameText(AQuery.Connection, AConnectionName) then
  begin
    Exit(True);
  end;
  // Andere oder keine benannte Verbindung (.atlas): passt, wenn die Verbindung der Abfrage auf denselben Server
  // desselben Anbieters zeigt.
  mIndex := TAtlasTrackerConnections.IndexOfName(AConnections, AQuery.Connection);
  if mIndex < 0 then
  begin
    Exit(False);
  end;
  mConnection := AConnections[mIndex];
  Result := SameText(mConnection.Provider, ATarget.Provider) and (mConnection.Target.Server <> '') and
    SameText(mConnection.Target.Server, ATarget.Server);
end;

class function TAtlasTrackerQueries.Available(const AItems: TArray<TAtlasTrackerQuery>;
  const ATarget: TAtlasTrackerTarget; const AConnectionName: string;
  const AConnections: TArray<TAtlasTrackerConnection>; const ADefaultName: string): TArray<TAtlasTrackerQuery>;
var
  mItem: TAtlasTrackerQuery;
begin
  Result := nil;
  if not ATarget.Configured then
  begin
    Exit;
  end;
  for mItem in AItems do
  begin
    if not mItem.Builtin and Applies(mItem, ATarget, AConnectionName, AConnections) then
    begin
      Result := Result + [mItem];
    end;
  end;
  if Length(Result) = 0 then
  begin
    Result := [TAtlasTrackerQuery.Fallback(ADefaultName)];
  end;
end;

class function TAtlasTrackerQueries.Choose(const AAvailable: TArray<TAtlasTrackerQuery>; const ASelected: string;
  APicker: Boolean): Integer;
begin
  if Length(AAvailable) = 0 then
  begin
    Exit(-1);
  end;
  Result := -1;
  if APicker and (Trim(ASelected) <> '') then
  begin
    Result := IndexOfName(AAvailable, ASelected);
  end;
  if Result < 0 then
  begin
    Result := 0;
  end;
end;

class procedure TAtlasTrackerQueries.RenameConnection(var AItems: TArray<TAtlasTrackerQuery>; const AOld,
  ANew: string);
var
  mIndex: Integer;
begin
  if AOld = '' then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AItems) do
  begin
    if SameText(AItems[mIndex].Connection, AOld) then
    begin
      AItems[mIndex].Connection := ANew;
    end;
  end;
end;

end.
