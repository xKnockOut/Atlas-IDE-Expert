unit Atlas.Core.Build.Inbox;

// Builds für Claude Code über die IDE (#261, MCP-Werkzeug build_project), ohne
// Open Tools API. Ohne Kommandozeilen-Compiler (Starter Edition) baut das
// Plugin selbst über IOTAProjectBuilder (Atlas.IDE.Build.Runner). Der
// MCP-Server legt den Auftrag in den Eingang des Plugins:
//   %LOCALAPPDATA%\Atlas\ide-builds\<pid>\<id>.json
//   {"project": Pfad der .dproj, "mode": "make"|"build"|"check",
//    "configuration": "", "platform": ""}          ('' = wie in der IDE)
// Das Plugin übernimmt ihn durch Umbenennen in <id>.taken (wer das Umbenennen
// gewinnt, hat ihn; sonst zieht der MCP-Server ihn nach seiner Frist zurück)
// und antwortet mit <id>.result.json:
//   {"ok": true, "build": {project, kind, configuration, platform, success,
//    durationMs, finishedAt, requestedBy: "mcp", messages[]}}
//   {"ok": false, "reason": "…"}
// "build" hat das Format der build-*.json des Servers (get_last_build);
// Zeilen und Spalten sind 1-basiert, Info-Meldungen bleiben weg.
// Gegenstück im MCP-Server: Atlas.Common.Mcp.IdeBuilds.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages;

type
  TAtlasBuildRequest = record
    Id: string;
    /// <summary>Absoluter Pfad der .dproj.</summary>
    Project: string;
    /// <summary>Make, Build oder Check.</summary>
    Kind: TAtlasCompileKind;
    /// <summary>'' = aktive Konfiguration bzw. Plattform der IDE.</summary>
    Configuration: string;
    Platform: string;
  end;

  /// <summary>Ergebnis eines Builds für die Antwort.</summary>
  TAtlasBuildReport = record
    /// <summary>Projekt, Art, Konfiguration und Plattform des Laufs.</summary>
    Project: TAtlasCompileProject;
    Succeeded: Boolean;
    DurationMs: Int64;
    /// <summary>Ortszeit des Endes.</summary>
    FinishedAt: TDateTime;
    Messages: TArray<TAtlasCompilerMessage>;
  end;

  TAtlasBuildInbox = class
  public const
    RequestExtension = '.json';
    TakenExtension = '.taken';
    ResultSuffix = '.result.json';
    /// <summary>Wert von "requestedBy" in den Compile-Ereignissen und im Ergebnis.</summary>
    RequestedBy = 'mcp';
  public
    /// <summary>Eingang des Prozesses APid unter ABase (%LOCALAPPDATA%\Atlas).</summary>
    class function Folder(const ABase: string; APid: Cardinal): string; static;
    /// <summary>Wartende Aufträge (ohne .tmp, .taken und Ergebnisse), älteste zuerst.</summary>
    class function Pending(const AFolder: string): TArray<string>; static;
    /// <summary>"make", "build", "check" → Art; False bei anderem Text. '' gilt als "make".</summary>
    class function KindOf(const AMode: string; out AKind: TAtlasCompileKind): Boolean; static;
    /// <summary>Liest einen Auftrag; False mit Grund in AReason.</summary>
    class function ParseRequest(const AText: string; out ARequest: TAtlasBuildRequest; out AReason: string): Boolean;
      static;
    /// <summary>Übernimmt den Auftrag AFileName und liest ihn. False, wenn ihn schon jemand hat (AReason = '') oder
    /// er unlesbar ist (dann ist er mit Grund beantwortet).</summary>
    class function Take(const AFileName: string; out ARequest: TAtlasBuildRequest; out AReason: string): Boolean;
      static;
    /// <summary>Objekt "build" der Antwort; der Aufrufer gibt es frei.</summary>
    class function BuildJson(const AReport: TAtlasBuildReport): TJSONObject; static;
    /// <summary>{"ok": true, "build": …}.</summary>
    class function SuccessText(const AReport: TAtlasBuildReport): string; static;
    /// <summary>{"ok": false, "reason": …}.</summary>
    class function RefusalText(const AReason: string): string; static;
    /// <summary>Antwort schreiben (erst daneben, dann umbenennen) und den übernommenen Auftrag löschen.</summary>
    class procedure Answer(const AFolder, AId, AText: string); static;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  System.DateUtils,
  System.Generics.Collections;

class function TAtlasBuildInbox.Folder(const ABase: string; APid: Cardinal): string;
begin
  Result := TPath.Combine(TPath.Combine(ABase, 'ide-builds'), IntToStr(APid));
end;

class function TAtlasBuildInbox.Pending(const AFolder: string): TArray<string>;
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

class function TAtlasBuildInbox.KindOf(const AMode: string; out AKind: TAtlasCompileKind): Boolean;
begin
  Result := True;
  AKind := TAtlasCompileKind.Make;
  if (AMode = '') or SameText(AMode, 'make') then
    AKind := TAtlasCompileKind.Make
  else if SameText(AMode, 'build') then
    AKind := TAtlasCompileKind.Build
  else if SameText(AMode, 'check') then
    AKind := TAtlasCompileKind.Check
  else
    Result := False;
end;

class function TAtlasBuildInbox.ParseRequest(const AText: string; out ARequest: TAtlasBuildRequest;
  out AReason: string): Boolean;
var
  Value: TJSONValue;
  Root: TJSONObject;
  Mode: string;
begin
  ARequest := Default(TAtlasBuildRequest);
  AReason := '';
  Value := TJSONObject.ParseJSONValue(AText);
  try
    if not (Value is TJSONObject) then
    begin
      AReason := 'Auftrag nicht lesbar';
      Exit(False);
    end;
    Root := TJSONObject(Value);
    ARequest.Project := Root.GetValue<string>('project', '');
    Mode := Root.GetValue<string>('mode', '');
    ARequest.Configuration := Root.GetValue<string>('configuration', '');
    ARequest.Platform := Root.GetValue<string>('platform', '');
  finally
    Value.Free;
  end;
  if ARequest.Project = '' then
  begin
    AReason := 'Auftrag ohne Projekt';
    Exit(False);
  end;
  if not KindOf(Mode, ARequest.Kind) then
  begin
    AReason := Format('Unbekannte Art "%s"; erlaubt sind make, build und check', [Mode]);
    Exit(False);
  end;
  Result := True;
end;

class function TAtlasBuildInbox.Take(const AFileName: string; out ARequest: TAtlasBuildRequest;
  out AReason: string): Boolean;
var
  Taken, Text, Id: string;
begin
  ARequest := Default(TAtlasBuildRequest);
  AReason := '';
  Id := ChangeFileExt(ExtractFileName(AFileName), '');
  Taken := ChangeFileExt(AFileName, TakenExtension);
  // Umbenennen ist der Zuschlag: Hat der MCP-Server inzwischen zurückgezogen, schlägt es fehl.
  if not RenameFile(AFileName, Taken) then
    Exit(False);
  try
    Text := TFile.ReadAllText(Taken, TEncoding.UTF8);
  except
    on Exception do
      Text := '';
  end;
  Result := ParseRequest(Text, ARequest, AReason);
  ARequest.Id := Id;
  if not Result then
    Answer(ExtractFilePath(AFileName), Id, RefusalText(AReason));
end;

class function TAtlasBuildInbox.BuildJson(const AReport: TAtlasBuildReport): TJSONObject;
var
  Items: TJSONArray;
  Message: TAtlasCompilerMessage;
  Item: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('project', AReport.Project.FileName);
  Result.AddPair('kind', TAtlasCompileEvents.KindText(AReport.Project.Kind));
  Result.AddPair('configuration', AReport.Project.Configuration);
  Result.AddPair('platform', AReport.Project.Platform);
  Result.AddPair('success', TJSONBool.Create(AReport.Succeeded));
  Result.AddPair('durationMs', TJSONNumber.Create(AReport.DurationMs));
  Result.AddPair('finishedAt', DateToISO8601(AReport.FinishedAt, False));
  Result.AddPair('requestedBy', RequestedBy);
  Items := TJSONArray.Create;
  Result.AddPair('messages', Items);
  for Message in AReport.Messages do
  begin
    if Message.Severity = TAtlasCompilerSeverity.Info then
      Continue;
    Item := TJSONObject.Create;
    Item.AddPair('file', Message.FileName);
    Item.AddPair('line', TJSONNumber.Create(Message.Line));
    Item.AddPair('column', TJSONNumber.Create(Message.Column));
    Item.AddPair('severity', TAtlasCompilerMessages.SeverityText(Message.Severity));
    Item.AddPair('code', Message.Code);
    Item.AddPair('text', Message.Text);
    Items.AddElement(Item);
  end;
end;

class function TAtlasBuildInbox.SuccessText(const AReport: TAtlasBuildReport): string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('ok', TJSONBool.Create(True));
    Root.AddPair('build', BuildJson(AReport));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

class function TAtlasBuildInbox.RefusalText(const AReason: string): string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('ok', TJSONBool.Create(False));
    Root.AddPair('reason', AReason);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

class procedure TAtlasBuildInbox.Answer(const AFolder, AId, AText: string);
var
  Target, Temporary: string;
begin
  Target := TPath.Combine(AFolder, AId + ResultSuffix);
  Temporary := Target + '.tmp';
  TFile.WriteAllText(Temporary, AText, TEncoding.UTF8);
  if FileExists(Target) then
    TFile.Delete(Target);
  TFile.Move(Temporary, Target);
  if FileExists(TPath.Combine(AFolder, AId + TakenExtension)) then
    TFile.Delete(TPath.Combine(AFolder, AId + TakenExtension));
end;

end.
