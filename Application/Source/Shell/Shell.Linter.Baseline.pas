unit Shell.Linter.Baseline;

// Internals-Rolle Shell: Baseline des Linter-Modus (#97). Bekannte Treffer aus --baseline, sonst
// atlas-baseline.json neben atlas.json, werden ausgeblendet; --update-baseline schreibt sie neu und nennt auf
// stderr die Zähler und, bevor sie herausfallen, die Einträge ohne Datei.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Filter,
  Atlas.Common.Rules.Baseline,
  Shell.CommandLine,
  Shell.VersionControlChanges;

type
  /// <summary>Was KeptMarks zum Filtern braucht.</summary>
  TLinterMarkFilter = record
    Filter: TFindingFilter;
    Settings: TServerSettings;
    Descriptors: TArray<TRuleDescriptor>;
    /// <summary>Mit Git und ChangedLines nur Treffer in geänderten Zeilen.</summary>
    Git: TVcsChanges;
    ChangedLines: Boolean;
  end;

  TLinterBaseline = class
  public
    /// <summary>Pfad der Baseline: --baseline, sonst neben atlas.json (--update-baseline immer unter dem neuen
    /// Namen).</summary>
    class function PathOf(const AOptions: TCommandLineOptions; const AConfigRoot: string): string; static;
    /// <summary>Liest die Baseline APath. Fehlt eine mit --baseline genannte, False mit Meldung. Bei
    /// --update-baseline hält eine unlesbare das Neuschreiben nicht auf.</summary>
    class function Load(const AOptions: TCommandLineOptions; const APath: string;
      out ABaseline: IRuleBaseline): Boolean; static;
    /// <summary>Nur die Treffer, die nicht in der Baseline stehen.</summary>
    class function NewFindings(const AMarks: TArray<TBaselineMark>): TArray<TRuleFinding>; static;
    /// <summary>Treffer mit Fingerabdrücken für SARIF (#97) nach Filter und --changed-lines. Nicht mehr gefundene
    /// Einträge haben keine Zeile: Sie entfallen mit --changed-lines und tragen für den Filter den
    /// Standard-Schweregrad ihrer Regel.</summary>
    class function KeptMarks(const AMarks: TArray<TBaselineMark>; const AFilter: TLinterMarkFilter;
      const AFileName: string): TArray<TBaselineMark>; static;
    /// <summary>Einträge ohne Datei auf stderr, bevor die neue Datei sie entfernt.</summary>
    class procedure ReportOrphans(const AUpdate: TBaselineUpdate); static;
    /// <summary>Zähler nach --update-baseline auf stderr.</summary>
    class procedure ReportUpdate(const AUpdate: TBaselineUpdate; const APath: string); static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Rules.ChangedFiles,
  Shell.Linter.Output,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TLinterBaselineText = (Unreadable, NotFound, Orphans, Written, Completed);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TLinterBaselineText] of TAtlasText = (
    (De: 'Bisherige Baseline nicht lesbar, wird ersetzt: %s'; En: 'Previous baseline not readable, replacing it: %s'),
    (De: 'Baseline "%s" nicht gefunden'; En: 'Baseline "%s" not found'),
    (De: '%d Einträge ohne Datei werden entfernt (Datei umbenannt, verschoben oder gelöscht):';
    En: '%d entries without a file are removed (file renamed, moved or deleted):'),
    (De: 'Baseline geschrieben: %s (%d Treffer, %d Dateien geprüft; %d neu, %d entfernt, %d unverändert)';
    En: 'Baseline written: %s (%d findings, %d files checked; %d new, %d removed, %d unchanged)'),
    (De: '%d Einträge der älteren Baseline um die Routine ergänzt';
    En: '%d entries of the older baseline completed with the routine'));

class function TLinterBaseline.PathOf(const AOptions: TCommandLineOptions; const AConfigRoot: string): string;
begin
  Result := AOptions.BaselineFile;
  if Result <> '' then
  begin
    Exit;
  end;
  if AOptions.UpdateBaseline then
  begin
    Result := TPath.Combine(AConfigRoot, cBaselineFileName);
  end
  else
  begin
    Result := ExistingOrLegacyFile(AConfigRoot, cBaselineFileName, cLegacyBaselineFileName);
  end;
end;

function ReadBaseline(const APath: string): IRuleBaseline;
var
  mFormat: TFileFormat;
begin
  Result := TRuleBaseline.FromJson(TFileEncoding.LoadFromFile(APath, mFormat));
end;

/// <summary>Die bisherige Baseline nur für die Zähler; eine unlesbare hält das Neuschreiben nicht auf.</summary>
function PreviousBaseline(const APath: string): IRuleBaseline;
begin
  Result := nil;
  if not TFile.Exists(APath) then
  begin
    Exit;
  end;
  try
    Result := ReadBaseline(APath);
  except
    on E: Exception do
    begin
      TLinterOutput.Error(cTexts[TLinterBaselineText.Unreadable].Fmt([E.Message]));
      Result := nil;
    end;
  end;
end;

class function TLinterBaseline.Load(const AOptions: TCommandLineOptions; const APath: string;
  out ABaseline: IRuleBaseline): Boolean;
begin
  ABaseline := nil;
  Result := True;
  if AOptions.UpdateBaseline then
  begin
    ABaseline := PreviousBaseline(APath);
  end
  else if TFile.Exists(APath) then
  begin
    ABaseline := ReadBaseline(APath);
  end
  else if AOptions.BaselineFile <> '' then
  begin
    TLinterOutput.Error(cTexts[TLinterBaselineText.NotFound].Fmt([APath]));
    Result := False;
  end;
end;

class function TLinterBaseline.NewFindings(const AMarks: TArray<TBaselineMark>): TArray<TRuleFinding>;
var
  mMark: TBaselineMark;
begin
  Result := nil;
  for mMark in AMarks do
  begin
    if mMark.State = TBaselineState.New then
    begin
      Result := Result + [mMark.Finding];
    end;
  end;
end;

/// <summary>Standard-Schweregrad der Regel ARuleId, angepasst durch die Einstellungen.</summary>
function DefaultSeverityOf(const AFilter: TLinterMarkFilter; const ARuleId: string): TRuleSeverity;
var
  mDescriptor: TRuleDescriptor;
begin
  Result := TRuleSeverity.Hint;
  for mDescriptor in AFilter.Descriptors do
  begin
    if SameText(mDescriptor.Id, ARuleId) then
    begin
      Result := mDescriptor.DefaultSeverity;
    end;
  end;
  Result := AFilter.Settings.RuleSeverity(ARuleId, Result);
end;

/// <summary>Bleibt AMark mit den geänderten Zeilen ALines (nur mit AHasLines)? Nicht mehr gefundene Einträge
/// bekommen den Standard-Schweregrad.</summary>
function KeepMark(var AMark: TBaselineMark; const AFilter: TLinterMarkFilter; AHasLines: Boolean;
  const ALines: TChangedLines): Boolean;
begin
  if AMark.State = TBaselineState.Absent then
  begin
    Result := not AHasLines;
    if Result then
    begin
      AMark.Finding.Severity := DefaultSeverityOf(AFilter, AMark.Finding.RuleId);
    end;
  end
  else
  begin
    Result := not AHasLines or ALines.Contains(AMark.Finding.Range.StartPos.Line);
  end;
  Result := Result and AFilter.Filter.AcceptsFinding(AMark.Finding);
end;

class function TLinterBaseline.KeptMarks(const AMarks: TArray<TBaselineMark>; const AFilter: TLinterMarkFilter;
  const AFileName: string): TArray<TBaselineMark>;
var
  mLines: TChangedLines;
  mHasLines: Boolean;
  mMark, mItem: TBaselineMark;
begin
  Result := nil;
  mLines := Default(TChangedLines);
  mHasLines := (AFilter.Git <> nil) and AFilter.ChangedLines;
  if mHasLines and not TChangedFiles.LinesOf(AFilter.Git.Lines, AFilter.Git.RepoRoot, AFileName, mLines) then
  begin
    Exit;
  end;
  for mMark in AMarks do
  begin
    // Kopie: KeepMark passt den Schweregrad an.
    mItem := mMark;
    if KeepMark(mItem, AFilter, mHasLines, mLines) then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

class procedure TLinterBaseline.ReportOrphans(const AUpdate: TBaselineUpdate);
var
  mOrphan: TBaselineOrphan;
begin
  if Length(AUpdate.Orphans) = 0 then
  begin
    Exit;
  end;
  TLinterOutput.Error(cTexts[TLinterBaselineText.Orphans].Fmt([AUpdate.OrphanCount]));
  for mOrphan in AUpdate.Orphans do
  begin
    TLinterOutput.Error(Format('  %s (%d)', [mOrphan.Path, mOrphan.Count]));
  end;
end;

class procedure TLinterBaseline.ReportUpdate(const AUpdate: TBaselineUpdate; const APath: string);
begin
  TLinterOutput.Error(cTexts[TLinterBaselineText.Written].Fmt([APath, AUpdate.Total, AUpdate.Files, AUpdate.Added,
    AUpdate.Removed, AUpdate.Unchanged]));
  if AUpdate.Completed > 0 then
  begin
    TLinterOutput.Error(cTexts[TLinterBaselineText.Completed].Fmt([AUpdate.Completed]));
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Linter.Baseline', cTexts);

end.
