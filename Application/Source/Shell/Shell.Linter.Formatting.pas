unit Shell.Linter.Formatting;

// Internals-Rolle Shell: Formatieren ohne IDE (#1358). --format-check bzw. --format-write statt der Regeln.
// Dieselben Dateien wie --check (Ziel, --units, --changed/--diff, Ausschlüsse aus atlas.json), mit
// --changed-lines nur die geänderten Zeilen. Formatregeln wie „Dokument formatieren“: format.* aus atlas.json über
// .editorconfig über den Vorgaben (ohne die Einrückung der IDE-Optionen). Geschrieben wird atomar über eine
// Nachbardatei; Kodierung und Zeilenenden bleiben, außer format.endOfLine verlangt andere. Exit-Codes in
// Atlas.Common.Rules.FormatOutput.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Filter,
  Atlas.Common.Rules.FormatOutput,
  Shell.CommandLine,
  Shell.VcsChanges;

type
  /// <summary>Was das Formatieren je Datei braucht.</summary>
  TLinterFormatRun = record
    Options: TCommandLineOptions;
    Settings: TServerSettings;
    Root: string;
    Sources: TCheckSourceFunc;
    Filter: TFindingFilter;
    /// <summary>Mit --changed bzw. --diff geladen, sonst nil.</summary>
    Git: TVcsChanges;
  end;

  TLinterFormatting = class
  public
    /// <summary>--format-check bzw. --format-write; Exit-Code nach TFormatOutput.ExitCode, 3 bei Fehlern.</summary>
    class function Run(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>Ausgabeart aus --format; False mit Meldung bei einer unpassenden Kombination.</summary>
    class function KindOf(const AOptions: TCommandLineOptions; out AKind: TFormatOutputKind): Boolean; static;
    /// <summary>Schreibt AText atomar: erst eine Nachbardatei, dann in einem Schritt ersetzen. Kodierung aus
    /// AFormat, Zeilenumbrüche wie in AText.</summary>
    class procedure WriteFormatted(const AFileName, AText: string; const AFormat: TFileFormat); static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Rules.Output,
  Atlas.Common.Editing.FormatCheck,
  Atlas.Common.Editing.EditorConfig,
  Atlas.Common.Lsp.Formatting,
  Shell.Platform,
  Shell.Linter.Output,
  Shell.Linter.Settings,
  Shell.Linter.Files,
  Shell.Linter.Changes;

class function TLinterFormatting.KindOf(const AOptions: TCommandLineOptions; out AKind: TFormatOutputKind): Boolean;
begin
  AKind := TFormatOutputKind.Text;
  Result := False;
  if AOptions.FormatCheck and AOptions.FormatWrite then
  begin
    TLinterOutput.Error('--format-check und --format-write schließen sich aus');
  end
  else if AOptions.Metrics or AOptions.Todos or AOptions.SuppressionStats or AOptions.UpdateBaseline then
  begin
    TLinterOutput.Error('--format-check und --format-write gehen nicht mit --metrics, --todos, ' +
      '--suppression-stats oder --update-baseline');
  end
  else if not AOptions.FormatDiff and (AOptions.CheckFormat = TFindingsFormat.Sarif) then
  begin
    TLinterOutput.Error('--format-check und --format-write gibt es mit --format text, json oder diff');
  end
  else
  begin
    Result := True;
    if AOptions.FormatDiff then
    begin
      AKind := TFormatOutputKind.Diff;
    end
    else if AOptions.CheckFormat = TFindingsFormat.Json then
    begin
      AKind := TFormatOutputKind.Json;
    end;
  end;
end;

class procedure TLinterFormatting.WriteFormatted(const AFileName, AText: string; const AFormat: TFileFormat);
var
  mTemp: string;
begin
  if TFileEncoding.IsBinaryFormFile(AFileName) then
  begin
    raise EFileEncodingError.Create('Binär gespeichertes Formular wird nicht geändert');
  end;
  mTemp := AFileName + '.atlas-format.tmp';
  TFile.WriteAllBytes(mTemp, TFileEncoding.EncodeKeepingLineBreaks(AText, AFormat));
  if not TShellPlatform.MoveReplacing(mTemp, AFileName) then
  begin
    if TFile.Exists(mTemp) then
    begin
      TFile.Delete(mTemp);
    end;
    raise EInOutError.Create('Datei nicht ersetzbar (gesperrt oder schreibgeschützt)');
  end;
end;

function ReadEditorConfigFunc(): TEditorConfigReadFile;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := FileExists(AFileName);
      if Result then
      begin
        AText := TFileEncoding.LoadText(AFileName);
      end;
    end;
end;

/// <summary>Bereich der Formatierung von AFileName: alles, mit --changed-lines nur die geänderten Zeilen. False,
/// wenn die Datei nur über DFM oder Include-Datei ausgewählt ist: keine eigene geänderte Zeile.</summary>
function ScopeOf(const ARun: TLinterFormatRun; const AFileName: string; out AScope: TFormatScope): Boolean;
var
  mSpans: TArray<TFormatLineSpan>;
begin
  AScope := TFormatScope.All;
  Result := (ARun.Git = nil) or not ARun.Options.ChangedLines;
  if not Result and TLinterChanges.Spans(ARun.Git, AFileName, mSpans) then
  begin
    AScope := TFormatScope.Lines(mSpans);
    Result := True;
  end;
end;

/// <summary>Formatiert AFileName (mit --format-write auch schreiben); False, wenn die Datei entfällt.</summary>
function FormatFile(const ARun: TLinterFormatRun; const AFileName, ARelativePath: string;
  out AItem: TFormattedFile): Boolean;
var
  mScope: TFormatScope;
  mText: string;
  mFormat: TFileFormat;
  mStyle: TFormatStyle;
begin
  Result := ScopeOf(ARun, AFileName, mScope);
  if not Result then
  begin
    Exit;
  end;
  try
    mText := TFileEncoding.LoadFromFile(AFileName, mFormat);
  except
    on E: Exception do
    begin
      TLinterOutput.Error(Format('%s: %s', [AFileName, E.Message]));
      Exit(False);
    end;
  end;
  mStyle := TLspFormatting.Resolve(nil, AFileName, ARun.Settings.Formatting, ReadEditorConfigFunc());
  AItem := TFormattedFile.Create(ARelativePath, TFormatCheck.Run(mText, mStyle, mScope,
    ARun.Sources(AFileName).Options));
  if ARun.Options.FormatWrite and AItem.Outcome.Changed then
    try
      TLinterFormatting.WriteFormatted(AFileName, AItem.Outcome.Formatted, mFormat);
      AItem.Written := True;
    except
      on E: Exception do
        AItem.Error := E.Message;
    end;
end;

/// <summary>Alle Dateien aus ACandidates nach Filter und Ausschlüssen.</summary>
function FormatAll(const ARun: TLinterFormatRun; const ACandidates: TArray<string>): TArray<TFormattedFile>;
var
  mFileName, mRelativePath: string;
  mItem: TFormattedFile;
begin
  Result := nil;
  for mFileName in ACandidates do
  begin
    mRelativePath := ExtractRelativePath(IncludeTrailingPathDelimiter(ARun.Root), mFileName);
    if ARun.Filter.AcceptsFile(mRelativePath) and not ARun.Settings.IsExcluded(mRelativePath) and
      FormatFile(ARun, mFileName, mRelativePath, mItem) then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

/// <summary>Dateien des Ziels sammeln, mit --changed/--diff auf die geänderten beschränken und formatieren.</summary>
function FormatTarget(const AOptions: TCommandLineOptions; const AConfigRoot: string;
  const ASettings: TServerSettings): TArray<TFormattedFile>;
var
  mRun: TLinterFormatRun;
  mCandidates: TArray<string>;
begin
  mRun := Default(TLinterFormatRun);
  mRun.Options := AOptions;
  mRun.Settings := ASettings;
  mRun.Filter := Default(TFindingFilter);
  mRun.Filter.Units := AOptions.UnitFilter;
  mCandidates := TLinterFiles.Collect(AOptions.CheckTarget, ASettings, mRun.Root, mRun.Sources);
  try
    if AOptions.ChangedRef <> '' then
    begin
      mRun.Git := TLinterChanges.Detect(AConfigRoot, ASettings);
      mCandidates := TLinterChanges.Select(AOptions, mCandidates, mRun.Git);
    end;
    Result := FormatAll(mRun, mCandidates);
  finally
    mRun.Git.Free;
  end;
end;

/// <summary>Ausgabe, beim Diff die Probleme auf stderr (Syntaxfehler und instabile Dateien gehören nicht in den
/// Diff), die Zusammenfassung und der Exit-Code.</summary>
function Finish(const AOptions: TCommandLineOptions; const AFiles: TArray<TFormattedFile>;
  AKind: TFormatOutputKind): Integer;
var
  mProblem: string;
begin
  TLinterOutput.Write(AOptions, TFormatOutput.Render(AFiles, AKind, AOptions.FormatWrite));
  if AKind = TFormatOutputKind.Diff then
  begin
    for mProblem in TFormatOutput.Problems(AFiles) do
    begin
      TLinterOutput.Error(mProblem);
    end;
  end;
  TLinterOutput.Error(TFormatOutput.Summary(AFiles, AOptions.FormatWrite));
  Result := TFormatOutput.ExitCode(AFiles, AOptions.FormatWrite);
end;

class function TLinterFormatting.Run(const AOptions: TCommandLineOptions): Integer;
var
  mKind: TFormatOutputKind;
  mTarget: TLinterTarget;
  mSettings: TServerSettings;
begin
  TLinterOutput.Warnings(AOptions);
  if not KindOf(AOptions, mKind) or not TLinterTarget.Resolve(AOptions.CheckTarget, mTarget) then
  begin
    Exit(TFindingsOutput.ExitFailure);
  end;
  try
    mSettings := TLinterSettings.Load(mTarget.ConfigRoot);
    TFileEncodingDefaults.SetFolder(mTarget.ConfigRoot, mSettings.DefaultEncoding);
    Result := Finish(AOptions, FormatTarget(AOptions, mTarget.ConfigRoot, mSettings), mKind);
  except
    on E: Exception do
    begin
      TLinterOutput.Error(Format('%s: %s', [E.ClassName, E.Message]));
      Result := TFindingsOutput.ExitFailure;
    end;
  end;
end;

end.
