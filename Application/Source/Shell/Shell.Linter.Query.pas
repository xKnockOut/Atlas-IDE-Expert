unit Shell.Linter.Query;

// Internals-Rolle Shell: --query (#1351). Code-Abfrage über das Ziel aus --check (sonst den aktuellen Ordner) mit
// Symbolindex wie --check; Ergebnis als Text, JSON oder CSV (--format) auf stdout bzw. in --output. "@name" führt
// eine gespeicherte Abfrage aus.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Query.Contract,
  Shell.CommandLine;

type
  /// <summary>Abfrage nach dem Auflösen gespeicherter Abfragen.</summary>
  TLinterQueryText = record
    Text: string;
    FailOnMatch: Boolean;
  end;

  TLinterQuery = class
  public
    /// <summary>Exit-Code 0; 1 mit --fail-on-match (oder failIfAny der gespeicherten Abfrage), wenn sie etwas
    /// findet; 3 bei einem Fehler in der Abfrage, bei Aufruffehlern und bei query.enabled aus.</summary>
    class function Run(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>"@name" aus ASettings.Queries, sonst AText; False, wenn es die gespeicherte Abfrage nicht gibt.
    /// </summary>
    class function Resolve(const AText: string; AFailOnMatch: Boolean; const ASettings: TServerSettings;
      out AQuery: TLinterQueryText): Boolean; static;
    /// <summary>Abfrage über die Dateien von ATarget ohne Projekt: Index aus denselben Dateien wie --check.
    /// </summary>
    class function InFolder(const ATarget: string; const ASettings: TServerSettings;
      const AQuery: string): TQueryResult; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Diagnostics.CheckProfile,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Query,
  Atlas.Common.Query.Output,
  Atlas.Common.Query.Service,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Output,
  Shell.WorkspaceGroup,
  Shell.Linter.Output,
  Shell.Linter.Settings,
  Shell.Linter.Files,
  Shell.Linter.Index,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TLinterQueryMessage = (NoSavedQuery, Off, Formats);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TLinterQueryMessage] of TAtlasText = (
    (De: 'Keine gespeicherte Abfrage "%s" in atlas.json (queries)';
    En: 'No saved query "%s" in atlas.json (queries)'),
    (De: 'Code-Abfragen sind ausgeschaltet (query.enabled in atlas.json bzw. settings.json)';
    En: 'Code queries are turned off (query.enabled in atlas.json or settings.json)'),
    (De: '--query gibt es mit --format text (Standard), json oder csv';
    En: '--query exists with --format text (default), json or csv'));

class function TLinterQuery.Resolve(const AText: string; AFailOnMatch: Boolean; const ASettings: TServerSettings;
  out AQuery: TLinterQueryText): Boolean;
var
  mSaved: TSavedQuery;
  mName: string;
begin
  AQuery.Text := Trim(AText);
  AQuery.FailOnMatch := AFailOnMatch;
  Result := not AQuery.Text.StartsWith('@');
  if Result then
  begin
    Exit;
  end;
  mName := Copy(AQuery.Text, 2, MaxInt);
  for mSaved in ASettings.Queries do
  begin
    if not Result and SameText(mSaved.Name, mName) then
    begin
      AQuery.Text := mSaved.Query;
      AQuery.FailOnMatch := AQuery.FailOnMatch or mSaved.FailIfAny;
      Result := True;
    end;
  end;
  if not Result then
  begin
    TLinterOutput.Error(cTexts[TLinterQueryMessage.NoSavedQuery].Fmt([mName]));
  end;
end;

function ReaderFunc(): TReferenceReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := TLinterFiles.ReadText(AFileName, AText);
    end;
end;

/// <summary>Eingaben der Abfrage-Datenquelle für --check: ohne Namensräume und Nachladen von Units.</summary>
function QueryInput(const AIndex: ISymbolIndex; const ARoot: string; const AFiles: TArray<string>): TLspQueryInput;
begin
  Result := Default(TLspQueryInput);
  Result.Index := AIndex;
  Result.Root := ARoot;
  Result.Files := AFiles;
  Result.ReadText := ReaderFunc();
end;

/// <summary>Abfragedienst über AIndex und AFiles; eigene Routine, damit der Dienst nicht den Rahmen festhält, in
/// dem er liegt (Leck).</summary>
function FolderQueries(const AIndex: ISymbolIndex; const ARoot: string; const AFiles: TArray<string>;
  const AReferences: TReferenceSettings): ICodeQueries;
begin
  Result := TCodeQueryService.Create(
    function(out AQuerySource: TQuerySource): Boolean
    begin
      AQuerySource := TLspQuery.Source(QueryInput(AIndex, ARoot, AFiles), AReferences);
      Result := True;
    end);
end;

class function TLinterQuery.InFolder(const ATarget: string; const ASettings: TServerSettings;
  const AQuery: string): TQueryResult;
var
  mFiles: TArray<string>;
  mRoot: string;
  mSources: TCheckSourceFunc;
begin
  mFiles := TLinterFiles.Collect(ATarget, ASettings, mRoot, mSources);
  Result := FolderQueries(TLinterFiles.IndexOf(mFiles, mSources), mRoot, mFiles, ASettings.References).Execute(
    TQueryRequest.Create(AQuery, 0));
end;

/// <summary>Führt AQuery aus: mit Projekt über den Index der Gruppe, ohne über die Dateien des Ziels.</summary>
function Execute(const AOptions: TCommandLineOptions; const AConfigRoot, ATarget: string;
  const ASettings: TServerSettings; const AQuery: string): TQueryResult;
var
  mGroup: TShellWorkspaceGroup;
  mTimings: TCheckTimings;
begin
  // Die Abfrage misst nicht (--timings gilt nur für die Prüfung).
  mTimings := Default(TCheckTimings);
  mGroup := TLinterIndex.Load(AOptions, AConfigRoot, mTimings);
  try
    if Length(mGroup.AllFiles) > 0 then
    begin
      Result := mGroup.Queries.Execute(TQueryRequest.Create(AQuery, 0));
    end
    else
    begin
      // Ohne Projekt die Dateien des Ziels wie --check und --architecture, in einem eigenen Index.
      Result := TLinterQuery.InFolder(ATarget, ASettings, AQuery);
    end;
  finally
    TLinterIndex.Release(mGroup);
  end;
end;

/// <summary>Einstellungen laden, Abfrage auflösen, ausführen und ausgeben; Exit-Code.</summary>
function Answer(const AOptions: TCommandLineOptions; const ATarget: TLinterTarget;
  AFormat: TQueryOutputFormat): Integer;
var
  mSettings: TServerSettings;
  mQuery: TLinterQueryText;
  mResult: TQueryResult;
begin
  mSettings := TLinterSettings.Load(ATarget.ConfigRoot);
  if not mSettings.QueryEnabled then
  begin
    TLinterOutput.Error(cTexts[TLinterQueryMessage.Off].Text);
    Exit(TFindingsOutput.cExitFailure);
  end;
  TFileEncodingDefaults.SetFolder(ATarget.ConfigRoot, mSettings.DefaultEncoding);
  if not TLinterQuery.Resolve(AOptions.QueryText, AOptions.FailOnMatch, mSettings, mQuery) then
  begin
    Exit(TFindingsOutput.cExitFailure);
  end;
  mResult := Execute(AOptions, ATarget.ConfigRoot, ATarget.Target, mSettings, mQuery.Text);
  if mResult.Failed then
  begin
    TLinterOutput.Error(TQueryOutput.ErrorText(mResult));
    Exit(TFindingsOutput.cExitFailure);
  end;
  TLinterOutput.Write(AOptions, TQueryOutput.Render(mResult, AFormat));
  Result := TFindingsOutput.cExitClean;
  if mQuery.FailOnMatch and (mResult.Total > 0) then
  begin
    Result := TFindingsOutput.cExitFindings;
  end;
end;

class function TLinterQuery.Run(const AOptions: TCommandLineOptions): Integer;
var
  mFormat: TQueryOutputFormat;
  mTarget: TLinterTarget;
begin
  TLinterOutput.Warnings(AOptions);
  if not TQueryOutput.TryParseFormat(AOptions.FormatText, TQueryOutputFormat.Text, mFormat) or
    (mFormat = TQueryOutputFormat.Markdown) then
  begin
    TLinterOutput.Error(cTexts[TLinterQueryMessage.Formats].Text);
    Exit(TFindingsOutput.cExitFailure);
  end;
  if not TLinterTarget.ResolveOrCurrent(AOptions.CheckTarget, mTarget) then
  begin
    Exit(TFindingsOutput.cExitFailure);
  end;
  try
    Result := Answer(AOptions, mTarget, mFormat);
  except
    on E: Exception do
    begin
      TLinterOutput.Error(E.Message);
      Result := TFindingsOutput.cExitFailure;
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Linter.Query', cTexts);

end.
