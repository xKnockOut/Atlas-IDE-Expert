unit Argus.Common.Mcp.BuildTools;

// Letzter Build aus der IDE für Claude Code (#556). Der LSP-Server bekommt
// die Build-Ergebnisse vom IDE-Plugin (TLspIdeBuild, #527/#528) und legt sie
// als JSON-Datei im Argus-Cache ab (TIndexCacheDirectory.BuildFileFor); der
// MCP-Prozess liest sie für das Werkzeug get_last_build. Nur lesend; Meldungen
// zu Dateien außerhalb des Arbeitsordners bleiben weg (#99), gezählt.

interface

uses
  System.SysUtils,
  System.JSON,
  Argus.Common.Compiler.Contract,
  Argus.Common.Lsp.IdeBuild;

type
  TMcpBuildTools = class
  public
    /// <summary>Dateiinhalt für den Austausch zwischen LSP- und MCP-Prozess.</summary>
    class function ToFileText(const ABuild: TIdeBuild): string; static;
    /// <summary>Liest ToFileText; False bei kaputtem Inhalt.</summary>
    class function FromFileText(const AText: string; out ABuild: TIdeBuild): Boolean; static;
    /// <summary>Ergebnis von get_last_build als JSON-Text; AProject filtert (Dateiname oder Pfad, '' = alle),
    /// ARoot begrenzt die Meldungen auf den Arbeitsordner.</summary>
    class function Report(const ABuild: TIdeBuild; const ARoot, AProject: string): string; static;
    /// <summary>Antwort, wenn noch kein Build aus der IDE bekannt ist.</summary>
    class function NoBuild(const ARoot: string): string; static;
  end;

implementation

uses
  System.DateUtils,
  System.StrUtils,
  System.IOUtils;

function SeverityText(ASeverity: TCompilerSeverity): string;
const
  Texts: array[TCompilerSeverity] of string = ('hint', 'warning', 'error', 'fatal');
begin
  Result := Texts[ASeverity];
end;

function SeverityOf(const AText: string): TCompilerSeverity;
var
  Severity: TCompilerSeverity;
begin
  for Severity := Low(TCompilerSeverity) to High(TCompilerSeverity) do
    if SameText(SeverityText(Severity), AText) then
      Exit(Severity);
  Result := TCompilerSeverity.Hint;
end;

/// <summary>AFileName liegt im Ordner ARoot (nach Normalisierung, ".." zählt nicht als darin).</summary>
function InsideRoot(const ARoot, AFileName: string): Boolean;
var
  Root, FileName: string;
begin
  if (ARoot = '') or (AFileName = '') then
    Exit(AFileName = '');
  try
    Root := IncludeTrailingPathDelimiter(TPath.GetFullPath(ARoot));
    FileName := TPath.GetFullPath(AFileName);
  except
    Exit(False);
  end;
  Result := StartsText(Root, FileName);
end;

function MessagesToJson(const AMessages: TArray<TCompilerMessage>; const ARoot: string;
  out AOmitted: Integer): TJSONArray;
var
  Message: TCompilerMessage;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  AOmitted := 0;
  for Message in AMessages do
  begin
    if (ARoot <> '') and not InsideRoot(ARoot, Message.FileName) then
    begin
      Inc(AOmitted);
      Continue;
    end;
    Item := TJSONObject.Create;
    Item.AddPair('file', Message.FileName);
    // Für Menschen und Werkzeuge 1-basiert wie in der IDE; 0 = ohne.
    Item.AddPair('line', TJSONNumber.Create(Message.Line + 1));
    Item.AddPair('column', TJSONNumber.Create(Message.Column + 1));
    Item.AddPair('severity', SeverityText(Message.Severity));
    Item.AddPair('code', Message.Code);
    Item.AddPair('text', Message.Text);
    Result.AddElement(Item);
  end;
end;

class function TMcpBuildTools.ToFileText(const ABuild: TIdeBuild): string;
var
  Root: TJSONObject;
  Omitted: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('project', ABuild.Project);
    Root.AddPair('kind', ABuild.Kind);
    Root.AddPair('configuration', ABuild.Configuration);
    Root.AddPair('platform', ABuild.Platform);
    Root.AddPair('success', TJSONBool.Create(ABuild.Success));
    Root.AddPair('durationMs', TJSONNumber.Create(ABuild.DurationMs));
    Root.AddPair('finishedAt', DateToISO8601(ABuild.FinishedAt, False));
    Root.AddPair('messages', MessagesToJson(ABuild.Messages, '', Omitted));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

class function TMcpBuildTools.FromFileText(const AText: string; out ABuild: TIdeBuild): Boolean;
var
  Value, Item: TJSONValue;
  Root: TJSONObject;
  Message: TCompilerMessage;
  Items: TJSONArray;
begin
  ABuild := Default(TIdeBuild);
  Value := TJSONObject.ParseJSONValue(AText);
  try
    Result := Value is TJSONObject;
    if not Result then
      Exit;
    Root := TJSONObject(Value);
    ABuild.Known := True;
    ABuild.Project := Root.GetValue<string>('project', '');
    ABuild.Kind := Root.GetValue<string>('kind', '');
    ABuild.Configuration := Root.GetValue<string>('configuration', '');
    ABuild.Platform := Root.GetValue<string>('platform', '');
    ABuild.Success := Root.GetValue<Boolean>('success', False);
    ABuild.DurationMs := Root.GetValue<Int64>('durationMs', 0);
    ABuild.FinishedAt := ISO8601ToDate(Root.GetValue<string>('finishedAt', '2000-01-01T00:00:00'), False);
    if Root.TryGetValue<TJSONArray>('messages', Items) then
      for Item in Items do
        if Item is TJSONObject then
        begin
          Message.FileName := TJSONObject(Item).GetValue<string>('file', '');
          Message.Line := TJSONObject(Item).GetValue<Integer>('line', 0) - 1;
          Message.Column := TJSONObject(Item).GetValue<Integer>('column', 0) - 1;
          Message.Severity := SeverityOf(TJSONObject(Item).GetValue<string>('severity', ''));
          Message.Code := TJSONObject(Item).GetValue<string>('code', '');
          Message.Text := TJSONObject(Item).GetValue<string>('text', '');
          ABuild.Messages := ABuild.Messages + [Message];
        end;
  finally
    Value.Free;
  end;
end;

class function TMcpBuildTools.NoBuild(const ARoot: string): string;
begin
  Result := Format('Noch kein Build aus der IDE für %s bekannt. Das IDE-Plugin meldet Builds, sobald Argus ' +
    'in der IDE läuft und dort compiliert wurde.', [ARoot]);
end;

class function TMcpBuildTools.Report(const ABuild: TIdeBuild; const ARoot, AProject: string): string;
var
  Root: TJSONObject;
  Counts: array[TCompilerSeverity] of Integer;
  Message: TCompilerMessage;
  Omitted: Integer;
begin
  if not ABuild.Known then
    Exit(NoBuild(ARoot));
  if (AProject <> '') and not SameText(AProject, ABuild.Project) and
    not SameText(AProject, ExtractFileName(ABuild.Project)) and
    not SameText(ChangeFileExt(AProject, ''), ChangeFileExt(ExtractFileName(ABuild.Project), '')) then
    Exit(Format('Der letzte Build betraf %s, nicht %s.', [ExtractFileName(ABuild.Project), AProject]));
  FillChar(Counts, SizeOf(Counts), 0);
  for Message in ABuild.Messages do
    Inc(Counts[Message.Severity]);
  Root := TJSONObject.Create;
  try
    Root.AddPair('result', IfThen(ABuild.Success, 'success', 'failed'));
    Root.AddPair('kind', ABuild.Kind);
    Root.AddPair('finishedAt', DateToISO8601(ABuild.FinishedAt, False));
    Root.AddPair('durationMs', TJSONNumber.Create(ABuild.DurationMs));
    Root.AddPair('project', ABuild.Project);
    Root.AddPair('configuration', ABuild.Configuration);
    Root.AddPair('platform', ABuild.Platform);
    Root.AddPair('errors', TJSONNumber.Create(Counts[TCompilerSeverity.Error] + Counts[TCompilerSeverity.Fatal]));
    Root.AddPair('warnings', TJSONNumber.Create(Counts[TCompilerSeverity.Warning]));
    Root.AddPair('hints', TJSONNumber.Create(Counts[TCompilerSeverity.Hint]));
    Root.AddPair('messages', MessagesToJson(ABuild.Messages, ARoot, Omitted));
    if Omitted > 0 then
      Root.AddPair('omittedOutsideWorkspace', TJSONNumber.Create(Omitted));
    Result := Root.Format(2);
  finally
    Root.Free;
  end;
end;

end.