unit Atlas.Common.Mcp.CheckTools;

// MCP-Werkzeuge, die Dateien mit den Prüfregeln und Kennzahlen durchgehen
// (#48, #66, #68): get_diagnostics, hook_check, get_metrics und get_todos.
// Befunde lesen die Dateien mit den Symbolen des Projekts und dessen
// Include-Dateien (CheckSource, #860), wie der Editor, und geben den Regeln den
// Symbolindex und die Projektdienste mit (CheckProject, #1112). Regeln und
// overrides aus atlas.json gelten für den Pfad relativ zum Arbeitsordner.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Lsp.References,
  Atlas.Common.Todos.Contract,
  Atlas.Common.Mcp.Contract;

type
  TMcpCheckTools = class
  public const
    MaxFindings = 200;
  public
    /// <summary>Befunde der Prüfregeln aus AScope und Syntaxfehler je Datei; AScope.Root für relative Pfade.
    /// </summary>
    class function Diagnostics(const AScope: TMcpRuleScope; const AFiles: TArray<string>;
      const AReadText: TReferenceReadText): string; overload; static;
    /// <summary>Wie oben mit Symbolen und Include-Dateien je Datei aus ASource (#860).</summary>
    class function Diagnostics(const AScope: TMcpRuleScope; const AFiles: TArray<string>;
      const AReadText: TReferenceReadText; const ASource: TCheckSourceFunc): string; overload; static;
    /// <summary>Wie oben mit Projekt, Symbolindex und Projektdiensten je Datei aus AProject (#1112), wie im
    /// Server.</summary>
    class function Diagnostics(const AScope: TMcpRuleScope; const AFiles: TArray<string>;
      const AReadText: TReferenceReadText; const ASource: TCheckSourceFunc;
      const AProject: TCheckProjectFunc): string; overload; static;
    /// <summary>hook_check: Befunde ab ASeverity (Warning: Warnungen und Fehler) einer gerade bearbeiteten
    /// Datei als Ausgabe eines PostToolUse-Hooks von Claude Code: JSON mit
    /// hookSpecificOutput.additionalContext, damit Claude die Befunde sofort sieht. Leer, wenn die Datei
    /// kein Pascal-Quelltext ist (.pas, .dpr, .dpk, .inc), sich nicht lesen lässt oder keine Befunde hat;
    /// leere Hook-Ausgabe ändert nichts. Projekt und Symbolindex aus AProject wie bei get_diagnostics (#1112).
    /// </summary>
    class function HookDiagnostics(const AScope: TMcpRuleScope; const AFileName: string;
      const AReadText: TReferenceReadText; const ASource: TCheckSourceFunc; const AProject: TCheckProjectFunc;
      ASeverity: TRuleSeverity): string; static;
    /// <summary>Schwelle für hook_check aus "error", "warning" (Vorgabe bei leerem Text), "information" oder
    /// "hint"; EMcpToolError bei anderem Text.</summary>
    class function ParseHookSeverity(const AText: string): TRuleSeverity; static;
    /// <summary>get_metrics (#66): Kennzahlen je Methode mit den Grenzwerten aus ASettings; Markdown-Bericht
    /// oder mit AJson die Metrikdaten. Pfade relativ zu ARoot.</summary>
    class function Metrics(const ASettings: TServerSettings; const ARoot: string; const AFiles: TArray<string>;
      const AReadText: TReferenceReadText; AJson: Boolean): string; static;
    /// <summary>get_todos (#68): TODO-Einträge der Dateien AFiles mit den Marken aus ASettings (Option keywords
    /// der Regel todo-comment), gefiltert nach AFilter; Markdown-Übersicht oder mit AJson die Daten. Pfade relativ
    /// zu ARoot.</summary>
    class function Todos(const ASettings: TServerSettings; const ARoot: string; const AFiles: TArray<string>;
      const AReadText: TReferenceReadText; const AFilter: TTodoFilter; AJson: Boolean): string; static;
    /// <summary>AFileName relativ zu ARoot, wenn sie darunter liegt; sonst unverändert.</summary>
    class function RelativeTo(const ARoot, AFileName: string): string; static;
    /// <summary>Befund als "Zeile:Spalte: Schwere [Regel] [Konfidenz …] Meldung" (Zeilen und Spalten ab 1).
    /// </summary>
    class function FindingLine(const AFinding: TRuleFinding): string; static;
  end;

implementation

uses
  System.Classes,
  System.StrUtils,
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Rules.Output,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Metrics.Collector,
  Atlas.Common.Metrics.Report,
  Atlas.Common.Rules.Builtin.Metrics,
  Atlas.Common.Todos.Scanner,
  Atlas.Common.Todos.Report,
  Atlas.Common.Rules.Builtin.Todos;

{ TMcpCheckTools }

class function TMcpCheckTools.RelativeTo(const ARoot, AFileName: string): string;
begin
  Result := AFileName;
  if (ARoot <> '') and StartsText(IncludeTrailingPathDelimiter(ARoot), AFileName) then
  begin
    Result := Copy(AFileName, Length(IncludeTrailingPathDelimiter(ARoot)) + 1, MaxInt);
  end;
end;

class function TMcpCheckTools.FindingLine(const AFinding: TRuleFinding): string;
begin
  Result := Format('%d:%d: %s [%s] [Konfidenz %s] %s', [AFinding.Range.StartPos.Line + 1,
    AFinding.Range.StartPos.Character + 1, TFindingsOutput.SeverityName(AFinding.Severity), AFinding.RuleId,
    ConfidenceText(AFinding.Confidence), AFinding.Message]);
end;

class function TMcpCheckTools.Metrics(const ASettings: TServerSettings; const ARoot: string;
  const AFiles: TArray<string>; const AReadText: TReferenceReadText; AJson: Boolean): string;
var
  mCollector: TMetricsCollector;
  mFiles: TArray<TFileMetrics>;
  mLimits: TMetricLimits;
begin
  mLimits := TMetricRules.Limits(ASettings);
  mCollector := TMetricsCollector.Create;
  try
    mFiles := mCollector.Collect(AFiles, ARoot,
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := Assigned(AReadText) and AReadText(AFileName, AText);
      end);
  finally
    mCollector.Free;
  end;
  if AJson then
  begin
    Result := TMetricsReport.Json(mFiles, mLimits);
  end
  else
  begin
    Result := TMetricsReport.Markdown(mFiles, mLimits, ExtractFileName(ExcludeTrailingPathDelimiter(ARoot)));
  end;
end;

class function TMcpCheckTools.Todos(const ASettings: TServerSettings; const ARoot: string;
  const AFiles: TArray<string>; const AReadText: TReferenceReadText; const AFilter: TTodoFilter;
  AJson: Boolean): string;
var
  mFiles: TArray<TFileTodos>;
begin
  mFiles := TTodoScanner.Filter(TTodoScanner.Collect(AFiles, ARoot,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := Assigned(AReadText) and AReadText(AFileName, AText);
    end, TTodoRules.Keywords(ASettings)), AFilter);
  if AJson then
  begin
    Result := TTodoReport.Json(mFiles);
  end
  else
  begin
    Result := TTodoReport.Markdown(mFiles, ExtractFileName(ExcludeTrailingPathDelimiter(ARoot)));
  end;
end;

class function TMcpCheckTools.Diagnostics(const AScope: TMcpRuleScope; const AFiles: TArray<string>;
  const AReadText: TReferenceReadText): string;
begin
  Result := Diagnostics(AScope, AFiles, AReadText, nil);
end;

class function TMcpCheckTools.Diagnostics(const AScope: TMcpRuleScope; const AFiles: TArray<string>;
  const AReadText: TReferenceReadText; const ASource: TCheckSourceFunc): string;
begin
  Result := Diagnostics(AScope, AFiles, AReadText, ASource, nil);
end;

/// <summary>Befunde der Regeln aus AScope in AText (Inhalt von AFileName).</summary>
function FileFindings(const AScope: TMcpRuleScope; const AFileName, AText: string; const ASource: TCheckSourceFunc;
  const AProject: TCheckProjectFunc): TArray<TRuleFinding>;
var
  mScopes: TFindingScopes;
begin
  Result := TFileChecker.CheckText(AScope.Rules, AScope.Settings, TMcpCheckTools.RelativeTo(AScope.Root, AFileName),
    AText, TCheckOrigin.ForFile(AProject, ASource, AFileName), mScopes);
end;

class function TMcpCheckTools.Diagnostics(const AScope: TMcpRuleScope; const AFiles: TArray<string>;
  const AReadText: TReferenceReadText; const ASource: TCheckSourceFunc; const AProject: TCheckProjectFunc): string;
var
  mLines: TStringList;
  mFileName, mText: string;
  mFinding: TRuleFinding;
  mCount, mChecked: Integer;
begin
  mLines := TStringList.Create;
  try
    mCount := 0;
    mChecked := 0;
    for mFileName in AFiles do
    begin
      if not AReadText(mFileName, mText) then
      begin
        mLines.Add(Format('%s: nicht lesbar', [mFileName]));
        Continue;
      end;
      Inc(mChecked);
      for mFinding in FileFindings(AScope, mFileName, mText, ASource, AProject) do
      begin
        Inc(mCount);
        if mCount <= MaxFindings then
        begin
          mLines.Add(mFileName + ':' + FindingLine(mFinding));
        end;
      end;
    end;
    if mCount > MaxFindings then
    begin
      mLines.Add(Format('… %d weitere Befunde', [mCount - MaxFindings]));
    end;
    mLines.Insert(0, Format('%d Befunde in %d Dateien.', [mCount, mChecked]));
    Result := TrimRight(mLines.Text);
  finally
    mLines.Free;
  end;
end;

/// <summary>Befunde ab ASeverity als Zeilen "Zeile:Spalte: Schwere [Regel] Meldung", höchstens MaxFindings, und
/// ihre Zahl.</summary>
function HookFindings(const AFindings: TArray<TRuleFinding>; ASeverity: TRuleSeverity;
  out ACount: Integer): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  ACount := 0;
  for mFinding in AFindings do
  begin
    if mFinding.Severity < ASeverity then
    begin
      Continue;
    end;
    Inc(ACount);
    if ACount <= TMcpCheckTools.MaxFindings then
    begin
      Result := Result + Format('%d:%d: %s [%s] %s', [mFinding.Range.StartPos.Line + 1,
        mFinding.Range.StartPos.Character + 1, TFindingsOutput.SeverityName(mFinding.Severity), mFinding.RuleId,
        mFinding.Message]) + #10;
    end;
  end;
  if ACount > TMcpCheckTools.MaxFindings then
  begin
    Result := Result + Format('… %d weitere Befunde', [ACount - TMcpCheckTools.MaxFindings]) + #10;
  end;
  Result := TrimRight(Result);
end;

class function TMcpCheckTools.HookDiagnostics(const AScope: TMcpRuleScope; const AFileName: string;
  const AReadText: TReferenceReadText; const ASource: TCheckSourceFunc; const AProject: TCheckProjectFunc;
  ASeverity: TRuleSeverity): string;
const
  cPascalExtensions: array[0..3] of string = ('.pas', '.dpr', '.dpk', '.inc');
var
  mText, mFindings, mContext: string;
  mCount: Integer;
begin
  Result := '';
  if not MatchText(ExtractFileExt(AFileName), cPascalExtensions) or
    not (Assigned(AReadText) and AReadText(AFileName, mText)) then
  begin
    Exit;
  end;
  // Wie get_diagnostics: Regeln und overrides aus atlas.json gelten für den Pfad relativ zum Projekt.
  mFindings := HookFindings(FileFindings(AScope, AFileName, mText, ASource, AProject), ASeverity, mCount);
  if mCount = 0 then
  begin
    Exit;
  end;
  mContext := Format('Atlas hat in %s nach der Änderung %d Befunde gefunden (Zeile:Spalte):', [AFileName, mCount]) +
    #10 + mFindings + #10 + 'Ursache im Code beheben; Erklärung mit explain_finding, Korrektur mit apply_code_action.';
  Result := '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":' +
    TFindingsOutput.JsonString(mContext) + '}}';
end;

class function TMcpCheckTools.ParseHookSeverity(const AText: string): TRuleSeverity;
begin
  if (AText = '') or SameText(AText, 'warning') then
  begin
    Result := TRuleSeverity.Warning;
  end
  else if SameText(AText, 'error') then
  begin
    Result := TRuleSeverity.Error;
  end
  else if SameText(AText, 'information') then
  begin
    Result := TRuleSeverity.Information;
  end
  else if SameText(AText, 'hint') then
  begin
    Result := TRuleSeverity.Hint;
  end
  else
  begin
    raise EMcpToolError.Create('"severity" ist error, warning, information oder hint');
  end;
end;

end.
