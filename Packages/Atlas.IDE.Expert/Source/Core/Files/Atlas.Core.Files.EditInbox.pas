unit Atlas.Core.Files.EditInbox;

// Schreibende MCP-Werkzeuge bei laufender IDE (#397), ohne Open Tools API:
// Der MCP-Server schreibt eine Datei, die in der IDE offen ist, nicht selbst,
// sondern legt einen Auftrag in den Eingang des Plugins:
//   %LOCALAPPDATA%\Atlas\ide-edits\<pid>\<id>.json
//   {"file": Pfad, "expected": bisheriger Text, "text": neuer Text}
// Das Plugin übernimmt ihn durch Umbenennen in <id>.taken (wer das Umbenennen
// gewinnt, hat ihn; der MCP-Server löscht nach seinem Zeitlimit sonst die
// .json und schreibt selbst), ändert den Puffer und antwortet mit
//   <id>.result.json  {"applied": true|false, "reason": "...", "notOpen": true}
// Gegenstück im MCP-Server: Atlas.Common.Mcp.IdeEdits. Welche Dateien offen
// sind, steht unter "open" in editor-dirty-<pid>.json (TAtlasDirtyExport).

interface

uses
  System.SysUtils;

type
  TAtlasEditRequest = record
    Id: string;
    FileName: string;
    Expected: string;
    Text: string;
  end;

  TAtlasEditInbox = class
  public const
    RequestExtension = '.json';
    TakenExtension = '.taken';
    ResultSuffix = '.result.json';
  public
    /// <summary>Eingang des Prozesses APid unter ABase (%LOCALAPPDATA%\Atlas).</summary>
    class function Folder(const ABase: string; APid: Cardinal): string; static;
    /// <summary>Wartende Aufträge (ohne .tmp, .taken und Ergebnisse), älteste zuerst.</summary>
    class function Pending(const AFolder: string): TArray<string>; static;
    /// <summary>Übernimmt den Auftrag AFileName und liest ihn; False, wenn ihn schon jemand hat
    /// oder er unlesbar ist (dann ist er gelöscht).</summary>
    class function Take(const AFileName: string; out ARequest: TAtlasEditRequest): Boolean; static;
    /// <summary>Antwort schreiben (erst daneben, dann umbenennen) und den übernommenen Auftrag löschen.</summary>
    class procedure Answer(const AFolder: string; const ARequest: TAtlasEditRequest; AApplied, ANotOpen: Boolean;
      const AReason: string); static;
  end;

implementation

uses
  System.IOUtils,
  System.JSON,
  System.Generics.Collections;

class function TAtlasEditInbox.Folder(const ABase: string; APid: Cardinal): string;
begin
  Result := TPath.Combine(TPath.Combine(ABase, 'ide-edits'), IntToStr(APid));
end;

class function TAtlasEditInbox.Pending(const AFolder: string): TArray<string>;
var
  Name: string;
  Found: TList<string>;
begin
  Result := nil;
  if not TDirectory.Exists(AFolder) then
    Exit;
  Found := TList<string>.Create;
  try
    for Name in TDirectory.GetFiles(AFolder, '*' + RequestExtension) do
      if Name.EndsWith(RequestExtension, True) and not Name.EndsWith(ResultSuffix, True) then
        Found.Add(Name);
    Found.Sort;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

class function TAtlasEditInbox.Take(const AFileName: string; out ARequest: TAtlasEditRequest): Boolean;
var
  Taken, Text: string;
  Json: TJSONValue;
begin
  ARequest := Default(TAtlasEditRequest);
  ARequest.Id := ChangeFileExt(ExtractFileName(AFileName), '');
  Taken := ChangeFileExt(AFileName, TakenExtension);
  // Umbenennen ist der Zuschlag: Hat der MCP-Server inzwischen gelöscht, schlägt es fehl.
  if not RenameFile(AFileName, Taken) then
    Exit(False);
  try
    Text := TFile.ReadAllText(Taken, TEncoding.UTF8);
  except
    on Exception do
      Text := '';
  end;
  Json := TJSONObject.ParseJSONValue(Text);
  try
    Result := (Json is TJSONObject) and TJSONObject(Json).TryGetValue<string>('file', ARequest.FileName) and
      TJSONObject(Json).TryGetValue<string>('expected', ARequest.Expected) and
      TJSONObject(Json).TryGetValue<string>('text', ARequest.Text);
  finally
    Json.Free;
  end;
  if not Result then
    Answer(ExtractFilePath(AFileName), ARequest, False, False, 'Auftrag nicht lesbar');
end;

class procedure TAtlasEditInbox.Answer(const AFolder: string; const ARequest: TAtlasEditRequest; AApplied,
  ANotOpen: Boolean; const AReason: string);
var
  Json: TJSONObject;
  Target, Temporary, Text: string;
begin
  Json := TJSONObject.Create;
  try
    Json.AddPair('applied', TJSONBool.Create(AApplied));
    if ANotOpen then
      Json.AddPair('notOpen', TJSONBool.Create(True));
    if AReason <> '' then
      Json.AddPair('reason', AReason);
    Text := Json.ToJSON;
  finally
    Json.Free;
  end;
  Target := TPath.Combine(AFolder, ARequest.Id + ResultSuffix);
  Temporary := Target + '.tmp';
  TFile.WriteAllText(Temporary, Text, TEncoding.UTF8);
  if FileExists(Target) then
    TFile.Delete(Target);
  TFile.Move(Temporary, Target);
  if FileExists(TPath.Combine(AFolder, ARequest.Id + TakenExtension)) then
    TFile.Delete(TPath.Combine(AFolder, ARequest.Id + TakenExtension));
end;

end.
