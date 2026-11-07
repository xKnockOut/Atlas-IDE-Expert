unit Atlas.Core.BuildPipeline.Inbox;

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

  /// <summary>Ergebnis eines Builds auf Auftrag.</summary>
  TAtlasBuildReport = record
    /// <summary>Projekt, Art, Konfiguration und Plattform des Laufs.</summary>
    Project: TAtlasCompileProject;
    Succeeded: Boolean;
    DurationMs: Int64;
    /// <summary>Ortszeit des Endes.</summary>
    FinishedAt: TDateTime;
    Messages: TArray<TAtlasCompilerMessage>;
  end;

  /// <summary>Gründe, aus denen ein Auftrag nicht lesbar ist, in der Sprache der Oberfläche.</summary>
  TAtlasBuildInboxTexts = record
    Unreadable: string;
    NoProject: string;
    /// <summary>Format mit %s für den Wert von "mode".</summary>
    UnknownMode: string;
  end;

  /// <summary>Ende eines Auftrags; AError &lt;&gt; '' = nicht gebaut (Grund), sonst Ergebnis in AReport.</summary>
  TAtlasBuildDoneProc = reference to procedure(const AReport: TAtlasBuildReport; const AError: string);

  TAtlasBuildInbox = class
  public const
    cRequestExtension = '.json';
    cTakenExtension = '.taken';
    cResultSuffix = '.result.json';
    /// <summary>Wert von "requestedBy" in den Compile-Ereignissen und im Ergebnis.</summary>
    cRequestedBy = 'mcp';
  public
    /// <summary>Eingang des Prozesses APid unter ABase (%LOCALAPPDATA%\Atlas).</summary>
    class function Folder(const ABase: string; APid: Cardinal): string; static;
    /// <summary>Wartende Aufträge (ohne .tmp, .taken und Ergebnisse), älteste zuerst.</summary>
    class function Pending(const AFolder: string): TArray<string>; static;
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
  mTaken, mText, mId: string;
begin
  ARequest := Default(TAtlasBuildRequest);
  AReason := '';
  mId := ChangeFileExt(ExtractFileName(AFileName), '');
  mTaken := ChangeFileExt(AFileName, cTakenExtension);
  // Umbenennen ist der Zuschlag: Hat der MCP-Server inzwischen zurückgezogen, schlägt es fehl.
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
  Result := ParseRequest(mText, ATexts, ARequest, AReason);
  ARequest.Id := mId;
  if not Result then
  begin
    Answer(ExtractFilePath(AFileName), mId, RefusalText(AReason));
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

class procedure TAtlasBuildInbox.Answer(const AFolder, AId, AText: string);
var
  mTarget, mTemporary: string;
begin
  mTarget := TPath.Combine(AFolder, AId + cResultSuffix);
  mTemporary := mTarget + '.tmp';
  TFile.WriteAllText(mTemporary, AText, TEncoding.UTF8);
  if FileExists(mTarget) then
  begin
    TFile.Delete(mTarget);
  end;
  TFile.Move(mTemporary, mTarget);
  if FileExists(TPath.Combine(AFolder, AId + cTakenExtension)) then
  begin
    TFile.Delete(TPath.Combine(AFolder, AId + cTakenExtension));
  end;
end;

end.
