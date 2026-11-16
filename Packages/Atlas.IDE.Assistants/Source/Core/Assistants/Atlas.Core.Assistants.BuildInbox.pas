unit Atlas.Core.Assistants.BuildInbox;

// Builds für KI-Assistenten über die IDE (#261, MCP-Werkzeug build_project), ohne
// Open Tools API. Ohne Kommandozeilen-Compiler (Starter Edition) baut das
// Plugin selbst über IOTAProjectBuilder (Atlas.IDE.BuildPipeline.Runner). Der
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
// Gegenstück im MCP-Server: Atlas.Common.Mcp.IdeBuilds. Die Gründe einer
// Ablehnung kommen in der Sprache der Oberfläche als TAtlasBuildInboxTexts
// herein (#1458; Core kennt die Texttabellen nicht).
// Finden, Übernehmen und Antworten teilt er mit dem anderen Eingang
// (TAtlasFileInbox in Atlas.Core.Assistants.Inbox).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Requests;

type
  /// <summary>Gründe, aus denen ein Auftrag nicht lesbar ist, in der Sprache der Oberfläche.</summary>
  TAtlasBuildInboxTexts = record
    Unreadable: string;
    NoProject: string;
    /// <summary>Format mit %s für den Wert von "mode".</summary>
    UnknownMode: string;
  end;

  TAtlasBuildInbox = class
  public const
    /// <summary>Wert von "requestedBy" in den Compile-Ereignissen und im Ergebnis.</summary>
    cRequestedBy = 'mcp';
  public
    /// <summary>Eingang des Prozesses APid unter ABase (%LOCALAPPDATA%\Atlas).</summary>
    class function Folder(const ABase: string; APid: Cardinal): string; static;
    /// <summary>"make", "build", "check" → Art; False bei anderem Text. '' gilt als "make".</summary>
    class function KindOf(const AMode: string; out AKind: TAtlasCompileKind): Boolean; static;
    /// <summary>Liest einen Auftrag; False mit Grund in AReason.</summary>
    class function ParseRequest(const AText: string; const ATexts: TAtlasBuildInboxTexts;
      out ARequest: TAtlasBuildRequest; out AReason: string): Boolean; static;
    /// <summary>Übernimmt den Auftrag AFileName und liest ihn. False, wenn ihn schon jemand hat (AReason = '') oder
    /// er unlesbar ist (dann ist er mit Grund beantwortet).</summary>
    class function Take(const AFileName: string; const ATexts: TAtlasBuildInboxTexts;
      out ARequest: TAtlasBuildRequest; out AReason: string): Boolean; static;
    /// <summary>Objekt "build" der Antwort; der Aufrufer gibt es frei.</summary>
    class function BuildJson(const AReport: TAtlasBuildReport): TJSONObject; static;
    /// <summary>{"ok": true, "build": …}.</summary>
    class function SuccessText(const AReport: TAtlasBuildReport): string; static;
    /// <summary>{"ok": false, "reason": …}.</summary>
    class function RefusalText(const AReason: string): string; static;
  end;

implementation

uses
  Atlas.Core.Build.Messages,
  System.IOUtils,
  System.DateUtils,
  System.Generics.Collections,
  Atlas.Core.Assistants.Inbox;

{ TAtlasBuildInbox }

class function TAtlasBuildInbox.Folder(const ABase: string; APid: Cardinal): string;
begin
  Result := TPath.Combine(TPath.Combine(ABase, 'ide-builds'), IntToStr(APid));
end;

class function TAtlasBuildInbox.KindOf(const AMode: string; out AKind: TAtlasCompileKind): Boolean;
begin
  Result := True;
  AKind := TAtlasCompileKind.Make;
  if (AMode = '') or SameText(AMode, 'make') then
  begin
    AKind := TAtlasCompileKind.Make;
  end
  else if SameText(AMode, 'build') then
  begin
    AKind := TAtlasCompileKind.Build;
  end
  else if SameText(AMode, 'check') then
  begin
    AKind := TAtlasCompileKind.Check;
  end
  else
  begin
    Result := False;
  end;
end;

class function TAtlasBuildInbox.ParseRequest(const AText: string; const ATexts: TAtlasBuildInboxTexts;
  out ARequest: TAtlasBuildRequest; out AReason: string): Boolean;
var
  mValue: TJSONValue;
  mRoot: TJSONObject;
  mMode: string;
begin
  ARequest := Default(TAtlasBuildRequest);
  AReason := '';
  mValue := TJSONObject.ParseJSONValue(AText);
  try
    if not (mValue is TJSONObject) then
    begin
      AReason := ATexts.Unreadable;
      Exit(False);
    end;
    mRoot := TJSONObject(mValue);
    ARequest.Project := mRoot.GetValue<string>('project', '');
    mMode := mRoot.GetValue<string>('mode', '');
    ARequest.Configuration := mRoot.GetValue<string>('configuration', '');
    ARequest.Platform := mRoot.GetValue<string>('platform', '');
    ARequest.Group := mRoot.GetValue<string>('group', '');
  finally
    mValue.Free;
  end;
  if ARequest.Project = '' then
  begin
    AReason := ATexts.NoProject;
    Exit(False);
  end;
  if not KindOf(mMode, ARequest.Kind) then
  begin
    AReason := Format(ATexts.UnknownMode, [mMode]);
    Exit(False);
  end;
  Result := True;
end;

class function TAtlasBuildInbox.Take(const AFileName: string; const ATexts: TAtlasBuildInboxTexts;
  out ARequest: TAtlasBuildRequest; out AReason: string): Boolean;
var
  mText, mId: string;
begin
  ARequest := Default(TAtlasBuildRequest);
  AReason := '';
  if not TAtlasFileInbox.Claim(AFileName, mId, mText) then
  begin
    Exit(False);
  end;
  Result := ParseRequest(mText, ATexts, ARequest, AReason);
  ARequest.Id := mId;
  if not Result then
  begin
    TAtlasFileInbox.Answer(ExtractFilePath(AFileName), mId, RefusalText(AReason));
  end;
end;

class function TAtlasBuildInbox.BuildJson(const AReport: TAtlasBuildReport): TJSONObject;
var
  mItems: TJSONArray;
  mMessage: TAtlasCompilerMessage;
  mItem: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('project', AReport.Project.FileName);
  Result.AddPair('kind', TAtlasCompileEvents.KindText(AReport.Project.Kind));
  Result.AddPair('configuration', AReport.Project.Configuration);
  Result.AddPair('platform', AReport.Project.Platform);
  Result.AddPair('success', TJSONBool.Create(AReport.Succeeded));
  Result.AddPair('durationMs', TJSONNumber.Create(AReport.DurationMs));
  Result.AddPair('finishedAt', DateToISO8601(AReport.FinishedAt, False));
  Result.AddPair('requestedBy', cRequestedBy);
  mItems := TJSONArray.Create;
  Result.AddPair('messages', mItems);
  for mMessage in AReport.Messages do
  begin
    if mMessage.Severity = TAtlasCompilerSeverity.Info then
    begin
      Continue;
    end;
    mItem := TJSONObject.Create;
    mItem.AddPair('file', mMessage.FileName);
    mItem.AddPair('line', TJSONNumber.Create(mMessage.Line));
    mItem.AddPair('column', TJSONNumber.Create(mMessage.Column));
    mItem.AddPair('severity', TAtlasCompilerMessages.SeverityText(mMessage.Severity));
    mItem.AddPair('code', mMessage.Code);
    mItem.AddPair('text', mMessage.Text);
    mItems.AddElement(mItem);
  end;
end;

class function TAtlasBuildInbox.SuccessText(const AReport: TAtlasBuildReport): string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('ok', TJSONBool.Create(True));
    mRoot.AddPair('build', BuildJson(AReport));
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasBuildInbox.RefusalText(const AReason: string): string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('ok', TJSONBool.Create(False));
    mRoot.AddPair('reason', AReason);
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

end.
