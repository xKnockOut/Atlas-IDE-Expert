unit Atlas.Common.Lsp.Status;

// Inhalt des Status-Befehls "atlas.server.status" (#28): Index, Speicher,
// letzter Indexlauf je Ordner und Antwortzeiten je Methode. Als JSON für
// Werkzeuge und als Markdown zum Anzeigen. Seit #492 auch die Größe der
// Caches auf der Platte, die letzte Aktualisierung je Ordner und die Zahl der
// Units mit ausgelagerten Verwendungen (Einstellungsseite des Plugins); seit
// #261 der Weg zum Compiler und, wenn keiner nutzbar ist, Grund und Ausweg.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Statistics;

type
  TWorkspaceStatus = record
    Name: string;
    /// <summary>Dauer des letzten Indexlaufs; -1 = noch keiner fertig.</summary>
    LastIndexMs: Int64;
    Parsed: Integer;
    FromCache: Integer;
    Missing: Integer;
    /// <summary>Letzte Änderung am Index dieses Ordners (Aufbau, Speichern, Tipp-Pause); 0 = noch keine.</summary>
    LastUpdate: TDateTime;
    /// <summary>Cache-Dateien des Ordners (Projekt, gemeinsame Bibliothek); '' ohne.</summary>
    CacheFile: string;
    LibraryCacheFile: string;
    /// <summary>Größe der Cache-Dateien in Byte (#492).</summary>
    CacheBytes: Int64;
    LibraryCacheBytes: Int64;
    /// <summary>Projektwahl (#46): .dproj, geladene Konfiguration und Plattform ('' ohne Projekt), per
    /// selectBuild gewählt (auch gemerkt), aktives Projekt der IDE, per selectProject ausgewählt.</summary>
    Project: string;
    Config: string;
    Platform: string;
    BuildChosen: Boolean;
    Active: Boolean;
    Selected: Boolean;
    /// <summary>" · Debug/Win64 (gewählt) · aktiv in der IDE · ausgewählt"; '' ohne Projekt.</summary>
    function ProjectText: string;
  end;

  TServerStatus = record
    Units: Integer;
    Symbols: Integer;
    /// <summary>Belegter Speicher in Byte; -1 = unbekannt.</summary>
    MemoryBytes: Int64;
    /// <summary>Geschätzter Bedarf des Symbolindex in Byte (#185).</summary>
    IndexBytes: Int64;
    /// <summary>Kompakt gehaltene Units.</summary>
    CompactUnits: Integer;
    /// <summary>Units mit ausgelagerten Verwendungen (#492).</summary>
    OffloadedUnits: Integer;
    /// <summary>Alle Index-Caches auf der Platte in Byte, auch anderer Projekte (#492).</summary>
    DiskBytes: Int64;
    /// <summary>Budget des Index in Byte; 0 = unbegrenzt.</summary>
    BudgetBytes: Int64;
    /// <summary>Text der geöffneten Dokumente in Byte.</summary>
    DocumentBytes: Int64;
    Workspaces: TArray<TWorkspaceStatus>;
    Requests: TArray<TMethodStatistics>;
    /// <summary>Zeile zum Compiler (#261), z. B. „Compiler: nicht verfügbar (Starter Edition)“; '' = keine.</summary>
    Compiler: string;
    /// <summary>Gewählter Weg: "dcc", "ide", "off"; '' = noch nicht geprüft.</summary>
    CompilerBackend: string;
    /// <summary>Grund und Ausweg, wenn kein Compiler nutzbar ist; sonst ''.</summary>
    CompilerReason: string;
    /// <summary>Der Aufrufer übernimmt das Objekt; enthält zusätzlich "markdown".</summary>
    function ToJson: TJSONObject;
    function ToMarkdown: string;
  end;

const
  StatusCommand = 'atlas.server.status';
  /// <summary>Alle Index-Caches löschen und die Ordner neu indizieren (#492).</summary>
  ClearIndexCommand = 'atlas.server.clearIndex';

implementation

uses
  System.DateUtils;

/// <summary>ISO 8601 in UTC; '' für 0.</summary>
function DateText(AValue: TDateTime): string;
begin
  if AValue = 0 then
    Result := ''
  else
    Result := DateToISO8601(AValue, False);
end;

function MegaBytes(ABytes: Int64): string;
begin
  Result := FormatFloat('0.0', ABytes / (1024 * 1024), TFormatSettings.Invariant) + ' MB';
end;

{ TWorkspaceStatus }

function TWorkspaceStatus.ProjectText: string;
begin
  Result := '';
  if Project = '' then
    Exit;
  if (Config <> '') or (Platform <> '') then
    Result := ' · ' + Config + '/' + Platform;
  if BuildChosen then
    Result := Result + ' (gewählt)';
  if Active then
    Result := Result + ' · aktiv in der IDE';
  if Selected then
    Result := Result + ' · ausgewählt';
end;

function TServerStatus.ToMarkdown: string;
var
  Builder: TStringBuilder;
  Workspace: TWorkspaceStatus;
  Request: TMethodStatistics;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('**Atlas**').Append(#10#10);
    Builder.Append(Format('- Index: %d Units, %d Symbole', [Units, Symbols])).Append(#10);
    if MemoryBytes >= 0 then
      Builder.Append('- Speicher: ').Append(MegaBytes(MemoryBytes)).Append(#10);
    Builder.Append('- davon Symbolindex: ').Append(MegaBytes(IndexBytes));
    if BudgetBytes > 0 then
      Builder.Append(' von ').Append(MegaBytes(BudgetBytes));
    if CompactUnits > 0 then
      Builder.Append(Format(', %d Units kompakt', [CompactUnits]));
    if OffloadedUnits > 0 then
      Builder.Append(Format(', Verwendungen von %d Units ausgelagert', [OffloadedUnits]));
    Builder.Append(#10);
    Builder.Append('- Caches auf der Platte: ').Append(MegaBytes(DiskBytes)).Append(#10);
    Builder.Append('- davon geöffnete Dokumente: ').Append(MegaBytes(DocumentBytes)).Append(#10);
    if Compiler <> '' then
    begin
      Builder.Append('- ').Append(Compiler).Append(#10);
      if CompilerReason <> '' then
        Builder.Append('  ').Append(CompilerReason).Append(#10);
    end;
    for Workspace in Workspaces do
      if Workspace.LastIndexMs < 0 then
        Builder.Append(Format('- %s%s: Index wird aufgebaut', [Workspace.Name, Workspace.ProjectText])).Append(#10)
      else
      begin
        Builder.Append(Format('- %s%s: letzter Indexlauf %d ms (%d neu eingelesen, %d aus dem Cache, %d fehlen)',
          [Workspace.Name, Workspace.ProjectText, Workspace.LastIndexMs, Workspace.Parsed, Workspace.FromCache,
          Workspace.Missing]));
        if Workspace.LastUpdate <> 0 then
          Builder.Append(', aktualisiert ').Append(FormatDateTime('dd.mm.yyyy hh:nn:ss', Workspace.LastUpdate));
        Builder.Append(', Cache ').Append(MegaBytes(Workspace.CacheBytes + Workspace.LibraryCacheBytes));
        Builder.Append(#10);
      end;
    if Length(Requests) > 0 then
    begin
      Builder.Append(#10).Append('| Methode | Anzahl | Mittel ms | Max ms | Fehler |').Append(#10);
      Builder.Append('|---|---:|---:|---:|---:|').Append(#10);
      for Request in Requests do
        Builder.Append(Format('| %s | %d | %s | %d | %d |', [Request.Method, Request.Count,
          FormatFloat('0.0', Request.AverageMs, TFormatSettings.Invariant), Request.MaxMs, Request.Failed])).Append(#10);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function TServerStatus.ToJson: TJSONObject;
var
  Items: TJSONArray;
  Item: TJSONObject;
  Workspace: TWorkspaceStatus;
  Request: TMethodStatistics;
begin
  Result := TJSONObject.Create;
  Result.AddPair('units', TJSONNumber.Create(Units));
  Result.AddPair('symbols', TJSONNumber.Create(Symbols));
  Result.AddPair('memoryBytes', TJSONNumber.Create(MemoryBytes));
  Result.AddPair('indexBytes', TJSONNumber.Create(IndexBytes));
  Result.AddPair('compactUnits', TJSONNumber.Create(CompactUnits));
  Result.AddPair('offloadedUnits', TJSONNumber.Create(OffloadedUnits));
  Result.AddPair('diskBytes', TJSONNumber.Create(DiskBytes));
  Result.AddPair('budgetBytes', TJSONNumber.Create(BudgetBytes));
  Result.AddPair('documentBytes', TJSONNumber.Create(DocumentBytes));
  Items := TJSONArray.Create;
  for Workspace in Workspaces do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('name', Workspace.Name);
    Item.AddPair('lastIndexMs', TJSONNumber.Create(Workspace.LastIndexMs));
    Item.AddPair('parsed', TJSONNumber.Create(Workspace.Parsed));
    Item.AddPair('fromCache', TJSONNumber.Create(Workspace.FromCache));
    Item.AddPair('missing', TJSONNumber.Create(Workspace.Missing));
    Item.AddPair('lastUpdate', DateText(Workspace.LastUpdate));
    Item.AddPair('cacheBytes', TJSONNumber.Create(Workspace.CacheBytes));
    Item.AddPair('libraryCacheBytes', TJSONNumber.Create(Workspace.LibraryCacheBytes));
    if Workspace.Project <> '' then
    begin
      Item.AddPair('project', Workspace.Project);
      Item.AddPair('config', Workspace.Config);
      Item.AddPair('platform', Workspace.Platform);
      Item.AddPair('buildChosen', TJSONBool.Create(Workspace.BuildChosen));
      Item.AddPair('active', TJSONBool.Create(Workspace.Active));
      Item.AddPair('selected', TJSONBool.Create(Workspace.Selected));
    end;
    Items.AddElement(Item);
  end;
  Result.AddPair('workspaces', Items);
  Items := TJSONArray.Create;
  for Request in Requests do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('method', Request.Method);
    Item.AddPair('count', TJSONNumber.Create(Request.Count));
    Item.AddPair('averageMs', TJSONNumber.Create(Request.AverageMs));
    Item.AddPair('maxMs', TJSONNumber.Create(Request.MaxMs));
    Item.AddPair('failed', TJSONNumber.Create(Request.Failed));
    Items.AddElement(Item);
  end;
  Result.AddPair('requests', Items);
  if Compiler <> '' then
  begin
    Item := TJSONObject.Create;
    Item.AddPair('status', Compiler);
    Item.AddPair('backend', CompilerBackend);
    Item.AddPair('reason', CompilerReason);
    Result.AddPair('compiler', Item);
  end;
  Result.AddPair('markdown', ToMarkdown);
end;

end.
