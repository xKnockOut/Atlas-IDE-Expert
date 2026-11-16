unit Atlas.Core.Assistants.EditInbox;

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
// Finden, Übernehmen und Antworten teilt er mit dem anderen Eingang
// (TAtlasFileInbox in Atlas.Core.Assistants.Inbox).

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
  public
    /// <summary>Eingang des Prozesses APid unter ABase (%LOCALAPPDATA%\Atlas).</summary>
    class function Folder(const ABase: string; APid: Cardinal): string; static;
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
  System.Generics.Collections,
  Atlas.Core.Assistants.Inbox;

{ TAtlasEditInbox }

class function TAtlasEditInbox.Folder(const ABase: string; APid: Cardinal): string;
begin
  Result := TPath.Combine(TPath.Combine(ABase, 'ide-edits'), IntToStr(APid));
end;

class function TAtlasEditInbox.Take(const AFileName: string; out ARequest: TAtlasEditRequest): Boolean;
var
  mText: string;
  mJson: TJSONValue;
begin
  ARequest := Default(TAtlasEditRequest);
  if not TAtlasFileInbox.Claim(AFileName, ARequest.Id, mText) then
  begin
    Exit(False);
  end;
  mJson := TJSONObject.ParseJSONValue(mText);
  try
    Result := (mJson is TJSONObject) and TJSONObject(mJson).TryGetValue<string>('file', ARequest.FileName) and
      TJSONObject(mJson).TryGetValue<string>('expected', ARequest.Expected) and
      TJSONObject(mJson).TryGetValue<string>('text', ARequest.Text);
  finally
    mJson.Free;
  end;
  if not Result then
  begin
    Answer(ExtractFilePath(AFileName), ARequest, False, False, 'Auftrag nicht lesbar');
  end;
end;

class procedure TAtlasEditInbox.Answer(const AFolder: string; const ARequest: TAtlasEditRequest; AApplied,
  ANotOpen: Boolean; const AReason: string);
var
  mJson: TJSONObject;
  mText: string;
begin
  mJson := TJSONObject.Create;
  try
    mJson.AddPair('applied', TJSONBool.Create(AApplied));
    if ANotOpen then
    begin
      mJson.AddPair('notOpen', TJSONBool.Create(True));
    end;
    if AReason <> '' then
    begin
      mJson.AddPair('reason', AReason);
    end;
    mText := mJson.ToJSON;
  finally
    mJson.Free;
  end;
  TAtlasFileInbox.Answer(AFolder, ARequest.Id, mText);
end;

end.
