unit BDLsp.Common.Lsp.Status;

// Inhalt des Status-Befehls "betterdelphilsp.status" (#28): Index, Speicher,
// letzter Indexlauf je Ordner und Antwortzeiten je Methode. Als JSON für
// Werkzeuge und als Markdown zum Anzeigen.

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.JsonRpc.Statistics;

type
  TWorkspaceStatus = record
    Name: string;
    /// <summary>Dauer des letzten Indexlaufs; -1 = noch keiner fertig.</summary>
    LastIndexMs: Int64;
    Parsed: Integer;
    FromCache: Integer;
    Missing: Integer;
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
    /// <summary>Budget des Index in Byte; 0 = unbegrenzt.</summary>
    BudgetBytes: Int64;
    /// <summary>Text der geöffneten Dokumente in Byte.</summary>
    DocumentBytes: Int64;
    Workspaces: TArray<TWorkspaceStatus>;
    Requests: TArray<TMethodStatistics>;
    /// <summary>Der Aufrufer übernimmt das Objekt; enthält zusätzlich "markdown".</summary>
    function ToJson: TJSONObject;
    function ToMarkdown: string;
  end;

const
  StatusCommand = 'betterdelphilsp.status';

implementation

function MegaBytes(ABytes: Int64): string;
begin
  Result := FormatFloat('0.0', ABytes / (1024 * 1024), TFormatSettings.Invariant) + ' MB';
end;

function TServerStatus.ToMarkdown: string;
var
  Builder: TStringBuilder;
  Workspace: TWorkspaceStatus;
  Request: TMethodStatistics;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('**BetterDelphiLSP**').Append(#10#10);
    Builder.Append(Format('- Index: %d Units, %d Symbole', [Units, Symbols])).Append(#10);
    if MemoryBytes >= 0 then
      Builder.Append('- Speicher: ').Append(MegaBytes(MemoryBytes)).Append(#10);
    Builder.Append('- davon Symbolindex: ').Append(MegaBytes(IndexBytes));
    if BudgetBytes > 0 then
      Builder.Append(' von ').Append(MegaBytes(BudgetBytes));
    if CompactUnits > 0 then
      Builder.Append(Format(', %d Units kompakt', [CompactUnits]));
    Builder.Append(#10);
    Builder.Append('- davon geöffnete Dokumente: ').Append(MegaBytes(DocumentBytes)).Append(#10);
    for Workspace in Workspaces do
      if Workspace.LastIndexMs < 0 then
        Builder.Append(Format('- %s: Index wird aufgebaut', [Workspace.Name])).Append(#10)
      else
        Builder.Append(Format('- %s: letzter Indexlauf %d ms (%d neu eingelesen, %d aus dem Cache, %d fehlen)',
          [Workspace.Name, Workspace.LastIndexMs, Workspace.Parsed, Workspace.FromCache, Workspace.Missing])).Append(#10);
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
  Result.AddPair('markdown', ToMarkdown);
end;

end.
