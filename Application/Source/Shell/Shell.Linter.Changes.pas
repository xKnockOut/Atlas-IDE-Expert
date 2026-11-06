unit Shell.Linter.Changes;

// Internals-Rolle Shell: Änderungen laut Versionsverwaltung für den Linter-Modus. Mit --changed bzw. --diff nur die
// geänderten Dateien laut Git (#157) bzw. SVN (#276), mit --changed-lines nur Treffer in geänderten Zeilen.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.FormatCheck,
  Shell.CommandLine,
  Shell.VcsChanges;

type
  TLinterChanges = class
  public
    /// <summary>Versionsverwaltung über AConfigRoot nach vcs.provider (#571) mit eigenen Programmpfaden und
    /// Zeitlimit wie im Plugin (#1285).</summary>
    class function Detect(const AConfigRoot: string; const ASettings: TServerSettings): TVcsChanges; static;
    /// <summary>Teilmenge von AFiles nach den Änderungen; AGit bleibt für --changed-lines geladen.</summary>
    class function Select(const AOptions: TCommandLineOptions; const AFiles: TArray<string>;
      AGit: TVcsChanges): TArray<string>; static;
    /// <summary>Nur Treffer in geänderten Zeilen von AFileName.</summary>
    class function InChangedLines(const AFindings: TArray<TRuleFinding>; AGit: TVcsChanges;
      const AFileName: string): TArray<TRuleFinding>; static;
    /// <summary>Geänderte Zeilen von AFileName als Bereiche des Formatierers; False ohne geänderte Zeile.</summary>
    class function Spans(AGit: TVcsChanges; const AFileName: string; out ASpans: TArray<TFormatLineSpan>): Boolean;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Rules.ChangedFiles,
  Shell.Platform,
  Shell.Linter.Output,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TLinterChangesText = (Changed);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TLinterChangesText] of TAtlasText = (
    (De: '%s: %d von %d Dateien geändert gegenüber %s'; En: '%s: %d of %d files changed compared with %s'));

class function TLinterChanges.Detect(const AConfigRoot: string; const ASettings: TServerSettings): TVcsChanges;
var
  mProcess: ICompilerProcess;
begin
  // Über eine Variable halten: Detect gibt einen Probelauf frei, bevor es den nächsten startet.
  mProcess := TProcessRunner.Create;
  Result := TVcsChanges.Detect(mProcess, AConfigRoot, ASettings.VcsProvider, ASettings.VcsGitPath,
    ASettings.VcsSvnPath, ASettings.VcsTimeoutSeconds);
end;

/// <summary>Units, die AFileName über $I einbindet, damit eine geänderte Include-Datei ihre Unit auswählt.</summary>
function IncludeNamesOf(const AFileName: string): TArray<string>;
var
  mFormat: TFileFormat;
begin
  try
    Result := TChangedFiles.IncludeNames(TFileEncoding.LoadFromFile(AFileName, mFormat));
  except
    on EFileStreamError do
      Result := nil;
  end;
end;

class function TLinterChanges.Select(const AOptions: TCommandLineOptions; const AFiles: TArray<string>;
  AGit: TVcsChanges): TArray<string>;
begin
  AGit.Load(AOptions.ChangedRef, AOptions.ChangedMergeBase,
    AOptions.ChangedMergeBase and (AOptions.ChangedRef = TCommandLineOptions.DefaultChangedBase),
    AOptions.IncludeUncommitted, AOptions.ChangedLines);
  Result := TChangedFiles.Select(AGit.Files, AFiles,
    function(const AFileName: string): TArray<string>
    begin
      Result := IncludeNamesOf(AFileName);
    end);
  TLinterOutput.Error(cTexts[TLinterChangesText.Changed].Fmt([AGit.Name, Length(Result), Length(AFiles),
    AOptions.ChangedRef]));
end;

class function TLinterChanges.InChangedLines(const AFindings: TArray<TRuleFinding>; AGit: TVcsChanges;
  const AFileName: string): TArray<TRuleFinding>;
var
  mLines: TChangedLines;
  mFinding: TRuleFinding;
begin
  Result := nil;
  if not TChangedFiles.LinesOf(AGit.Lines, AGit.RepoRoot, AFileName, mLines) then
  begin
    Exit;
  end;
  for mFinding in AFindings do
  begin
    if mLines.Contains(mFinding.Range.StartPos.Line) then
    begin
      Result := Result + [mFinding];
    end;
  end;
end;

class function TLinterChanges.Spans(AGit: TVcsChanges; const AFileName: string;
  out ASpans: TArray<TFormatLineSpan>): Boolean;
var
  mLines: TChangedLines;
  mSpan: TLineSpan;
begin
  ASpans := nil;
  Result := TChangedFiles.LinesOf(AGit.Lines, AGit.RepoRoot, AFileName, mLines);
  if not Result then
  begin
    Exit;
  end;
  for mSpan in mLines.Spans do
  begin
    ASpans := ASpans + [TFormatLineSpan.Create(mSpan.First, mSpan.Last)];
  end;
  Result := Length(ASpans) > 0;
end;

initialization
  TAtlasTextTables.Add('Shell.Linter.Changes', cTexts);

end.
