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
    cRequestExtension = '.json';
    cTakenExtension = '.taken';
    cResultSuffix = '.result.json';
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
  Winapi.Windows,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections;

class function TAtlasEditInbox.Folder(const ABase: string; APid: Cardinal): string;
begin
  Result := TPath.Combine(TPath.Combine(ABase, 'ide-edits'), IntToStr(APid));
end;

class function TAtlasEditInbox.Pending(const AFolder: string): TArray<string>;
var
  mName: string;
  mFound: TList<string>;
begin
  Result := nil;
  if not TDirectory.Exists(AFolder) then
  begin
    Exit;
  end;
  mFound := TList<string>.Create;
  try
    for mName in TDirectory.GetFiles(AFolder, '*' + cRequestExtension) do
    begin
      if mName.EndsWith(cRequestExtension, True) and not mName.EndsWith(cResultSuffix, True) then
      begin
        mFound.Add(mName);
      end;
    end;
    mFound.Sort;
    Result := mFound.ToArray;
  finally
    mFound.Free;
  end;
end;

class function TAtlasEditInbox.Take(const AFileName: string; out ARequest: TAtlasEditRequest): Boolean;
var
  mTaken, mText: string;
  mJson: TJSONValue;
begin
  ARequest := Default(TAtlasEditRequest);
  ARequest.Id := ChangeFileExt(ExtractFileName(AFileName), '');
  mTaken := ChangeFileExt(AFileName, cTakenExtension);
  // Umbenennen ist der Zuschlag: Hat der MCP-Server inzwischen gelöscht, schlägt es fehl.
  if not RenameFile(AFileName, mTaken) then
  begin
    Exit(False);
  end;
  try
    mText := TFile.ReadAllText(mTaken, TEncoding.UTF8);
  except
    on Exception do
      mText := '';
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
  mTarget, mTemporary, mText: string;
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
  mTarget := TPath.Combine(AFolder, ARequest.Id + cResultSuffix);
  mTemporary := mTarget + '.tmp';
  TFile.WriteAllText(mTemporary, mText, TEncoding.UTF8);
  if FileExists(mTarget) then
  begin
    TFile.Delete(mTarget);
  end;
  TFile.Move(mTemporary, mTarget);
  if FileExists(TPath.Combine(AFolder, ARequest.Id + cTakenExtension)) then
  begin
    TFile.Delete(TPath.Combine(AFolder, ARequest.Id + cTakenExtension));
  end;
end;

end.
