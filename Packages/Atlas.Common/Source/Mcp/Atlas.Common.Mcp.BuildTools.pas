unit Atlas.Common.Mcp.BuildTools;

// Letzter Build aus der IDE für KI-Assistenten (MCP) (#556). Der LSP-Server bekommt
// die Build-Ergebnisse vom IDE-Plugin (TLspIdeBuild, #527/#528) und legt sie
// als JSON-Datei im Atlas-Cache ab (TIndexCacheDirectory.BuildFileFor); der
// MCP-Prozess liest sie für das Werkzeug get_last_build. Nur lesend; Meldungen
// zu Dateien außerhalb des Arbeitsordners bleiben weg (#99), gezählt.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Lsp.IdeBuild;

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
  Atlas.Common.Compiler.Contract,
  System.Generics.Collections,
  System.DateUtils,
  System.StrUtils,
  System.IOUtils,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TBuildToolsText = (NoBuildFromTheIDE, TheLastBuildConcernedNot);

const
  cTexts: array[TBuildToolsText] of TAtlasText = (
    (De: 'Noch kein Build aus der IDE für %s bekannt. Das IDE-Plugin meldet Builds, sobald Atlas in der IDE läuft ' +
      'und dort compiliert wurde.';
     En: 'No build from the IDE known yet for %s. The IDE plugin reports builds as soon as Atlas runs in the IDE and ' +
      'compiled there.'),
    (De: 'Der letzte Build betraf %s, nicht %s.'; En: 'The last build concerned %s, not %s.'));

{$SCOPEDENUMS OFF}

function SeverityText(ASeverity: TCompilerSeverity): string;
const
  cTexts: array[TCompilerSeverity] of string = ('hint', 'warning', 'error', 'fatal');
begin
  Result := cTexts[ASeverity];
end;

function SeverityOf(const AText: string): TCompilerSeverity;
var
  mSeverity: TCompilerSeverity;
begin
  for mSeverity := Low(TCompilerSeverity) to High(TCompilerSeverity) do
  begin
    if SameText(SeverityText(mSeverity), AText) then
    begin
      Exit(mSeverity);
    end;
  end;
  Result := TCompilerSeverity.Hint;
end;

/// <summary>AFileName liegt im Ordner ARoot (nach Normalisierung, ".." zählt nicht als darin).</summary>
function InsideRoot(const ARoot, AFileName: string): Boolean;
var
  mRoot, mFileName: string;
begin
  if (ARoot = '') or (AFileName = '') then
  begin
    Exit(AFileName = '');
  end;
  try
    mRoot := IncludeTrailingPathDelimiter(TPath.GetFullPath(ARoot));
    mFileName := TPath.GetFullPath(AFileName);
  except
    Exit(False);
  end;
  Result := StartsText(mRoot, mFileName);
end;

function MessagesToJson(const AMessages: TArray<TCompilerMessage>; const ARoot: string;
  out AOmitted: Integer): TJSONArray;
var
  mMessage: TCompilerMessage;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  AOmitted := 0;
  for mMessage in AMessages do
  begin
    if (ARoot <> '') and not InsideRoot(ARoot, mMessage.FileName) then
    begin
      Inc(AOmitted);
      Continue;
    end;
    mItem := TJSONObject.Create;
    mItem.AddPair('file', mMessage.FileName);
    // Für Menschen und Werkzeuge 1-basiert wie in der IDE; 0 = ohne.
    mItem.AddPair('line', TJSONNumber.Create(mMessage.Line + 1));
    mItem.AddPair('column', TJSONNumber.Create(mMessage.Column + 1));
    mItem.AddPair('severity', SeverityText(mMessage.Severity));
    mItem.AddPair('code', mMessage.Code);
    mItem.AddPair('text', mMessage.Text);
    Result.AddElement(mItem);
  end;
end;

class function TMcpBuildTools.ToFileText(const ABuild: TIdeBuild): string;
var
  mRoot: TJSONObject;
  mOmitted: Integer;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('project', ABuild.Project);
    mRoot.AddPair('kind', ABuild.Kind);
    mRoot.AddPair('configuration', ABuild.Configuration);
    mRoot.AddPair('platform', ABuild.Platform);
    mRoot.AddPair('success', TJSONBool.Create(ABuild.Success));
    mRoot.AddPair('durationMs', TJSONNumber.Create(ABuild.DurationMs));
    mRoot.AddPair('finishedAt', DateToISO8601(ABuild.FinishedAt, False));
    mRoot.AddPair('messages', MessagesToJson(ABuild.Messages, '', mOmitted));
    if ABuild.RequestedBy <> '' then
    begin
      mRoot.AddPair('requestedBy', ABuild.RequestedBy);
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TMcpBuildTools.FromFileText(const AText: string; out ABuild: TIdeBuild): Boolean;
var
  mValue, mItem: TJSONValue;
  mRoot: TJSONObject;
  mMessage: TCompilerMessage;
  mItems: TJSONArray;
begin
  ABuild := Default(TIdeBuild);
  mValue := TJSONObject.ParseJSONValue(AText);
  try
    Result := mValue is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    ABuild.Known := True;
    ABuild.Project := mRoot.GetValue<string>('project', '');
    ABuild.Kind := mRoot.GetValue<string>('kind', '');
    ABuild.Configuration := mRoot.GetValue<string>('configuration', '');
    ABuild.Platform := mRoot.GetValue<string>('platform', '');
    ABuild.Success := mRoot.GetValue<Boolean>('success', False);
    ABuild.DurationMs := mRoot.GetValue<Int64>('durationMs', 0);
    ABuild.FinishedAt := ISO8601ToDate(mRoot.GetValue<string>('finishedAt', '2000-01-01T00:00:00'), False);
    ABuild.RequestedBy := mRoot.GetValue<string>('requestedBy', '');
    if mRoot.TryGetValue<TJSONArray>('messages', mItems) then
    begin
      for mItem in mItems do
      begin
        if mItem is TJSONObject then
        begin
          mMessage.FileName := TJSONObject(mItem).GetValue<string>('file', '');
          mMessage.Line := TJSONObject(mItem).GetValue<Integer>('line', 0) - 1;
          mMessage.Column := TJSONObject(mItem).GetValue<Integer>('column', 0) - 1;
          mMessage.Severity := SeverityOf(TJSONObject(mItem).GetValue<string>('severity', ''));
          mMessage.Code := TJSONObject(mItem).GetValue<string>('code', '');
          mMessage.Text := TJSONObject(mItem).GetValue<string>('text', '');
          ABuild.Messages := ABuild.Messages + [mMessage];
        end;
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TMcpBuildTools.NoBuild(const ARoot: string): string;
begin
  Result := cTexts[TBuildToolsText.NoBuildFromTheIDE].Fmt([ARoot]);
end;

class function TMcpBuildTools.Report(const ABuild: TIdeBuild; const ARoot, AProject: string): string;
var
  mRoot: TJSONObject;
  mCounts: array[TCompilerSeverity] of Integer;
  mMessage: TCompilerMessage;
  mOmitted: Integer;
begin
  if not ABuild.Known then
  begin
    Exit(NoBuild(ARoot));
  end;
  if (AProject <> '') and not SameText(AProject, ABuild.Project) and
    not SameText(AProject, ExtractFileName(ABuild.Project)) and
    not SameText(ChangeFileExt(AProject, ''), ChangeFileExt(ExtractFileName(ABuild.Project), '')) then
  begin
    Exit(cTexts[TBuildToolsText.TheLastBuildConcernedNot].Fmt([ExtractFileName(ABuild.Project), AProject]));
  end;
  FillChar(mCounts, SizeOf(mCounts), 0);
  for mMessage in ABuild.Messages do
  begin
    Inc(mCounts[mMessage.Severity]);
  end;
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('result', IfThen(ABuild.Success, 'success', 'failed'));
    mRoot.AddPair('kind', ABuild.Kind);
    mRoot.AddPair('finishedAt', DateToISO8601(ABuild.FinishedAt, False));
    mRoot.AddPair('durationMs', TJSONNumber.Create(ABuild.DurationMs));
    mRoot.AddPair('project', ABuild.Project);
    mRoot.AddPair('configuration', ABuild.Configuration);
    mRoot.AddPair('platform', ABuild.Platform);
    // Angestoßen von einem KI-Assistenten (build_project, #261) statt vom Benutzer.
    if ABuild.RequestedBy <> '' then
    begin
      mRoot.AddPair('requestedBy', ABuild.RequestedBy);
    end;
    mRoot.AddPair('errors', TJSONNumber.Create(mCounts[TCompilerSeverity.Error] + mCounts[TCompilerSeverity.Fatal]));
    mRoot.AddPair('warnings', TJSONNumber.Create(mCounts[TCompilerSeverity.Warning]));
    mRoot.AddPair('hints', TJSONNumber.Create(mCounts[TCompilerSeverity.Hint]));
    mRoot.AddPair('messages', MessagesToJson(ABuild.Messages, ARoot, mOmitted));
    if mOmitted > 0 then
    begin
      mRoot.AddPair('omittedOutsideWorkspace', TJSONNumber.Create(mOmitted));
    end;
    Result := mRoot.Format(2);
  finally
    mRoot.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.BuildTools', cTexts);

end.
