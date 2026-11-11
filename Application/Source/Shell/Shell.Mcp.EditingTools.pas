unit Shell.Mcp.EditingTools;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), schreibende Werkzeuge (rename_symbol, apply_code_action,
// fix_findings, format_code); mit dryRun nur der Diff.

interface

uses
  Shell.Mcp.Context;

/// <summary>Meldet rename_symbol, apply_code_action, fix_findings und format_code an.</summary>
procedure RegisterEditingTools(const AContext: TMcpToolContext);

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.Contract,
  Atlas.Common.Editing.FormatCheck,
  Atlas.Common.Lsp.Formatting,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Localization.Texts,
  Shell.Texts;

type
{$SCOPEDENUMS ON}
  TMcpEditingText = (RenameSymbolTool, RenameSymbolFile, RenameSymbolLine, RenameSymbolColumn, RenameSymbolNewName,
    RenameSymbolDryRun, ApplyCodeActionTool, ApplyCodeActionFile, ApplyCodeActionLine, ApplyCodeActionTitle,
    ApplyCodeActionDryRun, FixFindingsTool, FixFindingsRules, FixFindingsFile, FixFindingsMinConfidence,
    FixFindingsDryRun, FormatCodeTool, FormatCodeFile, FormatCodeText, FormatCodeStartLine, FormatCodeEndLine,
    FormatCodeDryRun, LineRange);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpEditingText] of TAtlasText = (
    (De: 'Benennt ein Symbol projektweit um, samt .dfm/.fmx und automatisch benannter Ereignis-Handler (#61). ' +
    'dryRun (Vorgabe true) zeigt nur den Diff; dryRun=false schreibt alle Dateien atomar.';
    En: 'Renames a symbol across the project, including .dfm/.fmx and automatically named event handlers (#61). ' +
    'dryRun (default true) only shows the diff; dryRun=false writes all files atomically.'),
    (De: 'Datei mit dem Symbol (relativ zum Projekt oder absolut)';
    En: 'File with the symbol (relative to the project or absolute)'),
    (De: 'Zeile (ab 1)'; En: 'Line (from 1)'),
    (De: 'Spalte (ab 1) im Bezeichner'; En: 'Column (from 1) within the identifier'),
    (De: 'Neuer Name'; En: 'New name'),
    (De: 'Nur Vorschau, nichts schreiben'; En: 'Preview only, write nothing'),
    (De: 'Wendet die Korrektur eines Regeltreffers in einer Zeile an (#61). Ohne title listet es die Korrekturen ' +
    'der Zeile. dryRun (Vorgabe true) zeigt nur den Diff; dryRun=false schreibt.';
    En: 'Applies the fix of a rule finding in one line (#61). Without title it lists the fixes of the line. ' +
    'dryRun (default true) only shows the diff; dryRun=false writes.'),
    (De: 'Pfad der Unit (relativ zum Projekt oder absolut)';
    En: 'Path of the unit (relative to the project or absolute)'),
    (De: 'Zeile des Befunds (ab 1)'; En: 'Line of the finding (from 1)'),
    (De: 'Titel der Korrektur oder Regelkennung; leer = Korrekturen auflisten';
    En: 'Title of the fix or rule id; empty = list the fixes'),
    (De: 'Nur Vorschau, nichts schreiben'; En: 'Preview only, write nothing'),
    (De: 'Sammelkorrektur (#1352): wendet die sicheren Korrekturen der genannten Regeln (oder "all") in einer ' +
    'Datei oder im ganzen Projekt an, nur Treffer ab fix.minConfidence (Vorgabe hoch) und nur Regeln mit ' +
    'safeFix im Katalog; bis zu drei Durchgänge, keine neuen Syntaxfehler. dryRun (Vorgabe true) zeigt nur ' +
    'Zusammenfassung und Diff; dryRun=false schreibt alle Dateien oder keine. In der IDE offene Dateien ' +
    'ändert das Plugin als einen Rückgängig-Schritt je Datei, ungespeicherte bleiben unberührt.';
    En: 'Bulk fix (#1352): applies the safe fixes of the given rules (or "all") in one file or in the whole ' +
    'project, only findings from fix.minConfidence on (default high) and only rules with safeFix in the ' +
    'catalog; up to three passes, no new syntax errors. dryRun (default true) only shows the summary and ' +
    'diff; dryRun=false writes all files or none. Files open in the IDE are changed by the plugin as one ' +
    'undo step per file; unsaved ones stay untouched.'),
    (De: 'Regelkennungen, z. B. ["redundant-cast"]; ["all"] = alle';
    En: 'Rule ids, e.g. ["redundant-cast"]; ["all"] = all'),
    (De: 'Pfad einer Unit; leer = alle Projektdateien'; En: 'Path of a unit; empty = all project files'),
    (De: 'Untergrenze der Konfidenz; nicht unter fix.minConfidence';
    En: 'Lower bound of the confidence; not below fix.minConfidence'),
    (De: 'Nur Vorschau, nichts schreiben'; En: 'Preview only, write nothing'),
    (De: 'Formatiert eine Unit nach den Formatregeln des Projekts (#1358; format.* in atlas.json, .editorconfig) ' +
    'wie "Dokument formatieren" in der IDE, ganz oder nur startLine..endLine. Mit text wird geplanter Code ' +
    'statt der Datei formatiert und als Text zurückgegeben, ohne zu schreiben. Ohne text zeigt dryRun ' +
    '(Vorgabe true) den Diff; dryRun=false schreibt wie apply_code_action (offene Dateien als ein ' +
    'Rückgängig-Schritt in der IDE). Dateien mit Syntaxfehlern werden nicht formatiert; // atlas-format: off ' +
    '... on bleibt unverändert.';
    En: 'Formats a unit according to the format rules of the project (#1358; format.* in atlas.json, ' +
    '.editorconfig) like "Format document" in the IDE, completely or only startLine..endLine. With text, ' +
    'planned code is formatted instead of the file and returned as text without writing. Without text, ' +
    'dryRun (default true) shows the diff; dryRun=false writes like apply_code_action (open files as one ' +
    'undo step in the IDE). Files with syntax errors are not formatted; // atlas-format: off ... on stays ' +
    'unchanged.'),
    (De: 'Pfad der Unit (relativ zum Projekt oder absolut)';
    En: 'Path of the unit (relative to the project or absolute)'),
    (De: 'Optional: geplanter Inhalt der ganzen Unit statt der Datei';
    En: 'Optional: planned content of the whole unit instead of the file'),
    (De: 'Erste zu formatierende Zeile (ab 1); ohne Angabe die ganze Unit';
    En: 'First line to format (from 1); without it the whole unit'),
    (De: 'Letzte zu formatierende Zeile; Vorgabe startLine'; En: 'Last line to format; default startLine'),
    (De: 'Nur Vorschau, nichts schreiben'; En: 'Preview only, write nothing'),
    (De: '"startLine" ab 1 und "endLine" nicht davor'; En: '"startLine" from 1 and "endLine" not before it'));

function ToolRenameSymbol(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFileName: string;
  mLine, mColumn: Integer;
begin
  mFileName := AContext.Guard.Resolve(TMcpArgs.RequiredString(AArguments, 'file'));
  if not AArguments.TryGetValue<Integer>('line', mLine) or not AArguments.TryGetValue<Integer>('column', mColumn) then
  begin
    raise EMcpToolError.Create(TShellTexts.Missing(['line', 'column']));
  end;
  AContext.Edit.Namespaces := AContext.Group.Main.State.Namespaces;
  Result := AContext.Edit.RenameSymbol(mFileName, mLine, mColumn, TMcpArgs.RequiredString(AArguments, 'newName'),
    DryRunOf(AArguments));
end;

procedure AddRenameSymbol(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('rename_symbol', cTexts[TMcpEditingText.RenameSymbolTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"file":{"type":"string","description":%s},' +
      '"line":{"type":"integer","minimum":1,"description":%s},' +
      '"column":{"type":"integer","minimum":1,"description":%s},' +
      '"newName":{"type":"string","description":%s},' +
      '"dryRun":{"type":"boolean","default":true,"description":%s}},' +
      '"required":["file","line","column","newName"]}',
      [cTexts[TMcpEditingText.RenameSymbolFile].Text,
      cTexts[TMcpEditingText.RenameSymbolLine].Text,
      cTexts[TMcpEditingText.RenameSymbolColumn].Text,
      cTexts[TMcpEditingText.RenameSymbolNewName].Text,
      cTexts[TMcpEditingText.RenameSymbolDryRun].Text]),
    ContextTool(AContext, ToolRenameSymbol), TMcpToolKind.Write);
end;

function ToolApplyCodeAction(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFileName: string;
  mLine: Integer;
begin
  mFileName := AContext.Guard.Resolve(TMcpArgs.RequiredString(AArguments, 'file'));
  if not AArguments.TryGetValue<Integer>('line', mLine) then
  begin
    raise EMcpToolError.Create(TShellTexts.Missing(['line']));
  end;
  Result := AContext.Edit.ApplyCodeAction(TMcpRuleScope.Create(BuiltinRules,
    AContext.Group.Main.Configuration.Settings, AContext.Root), mFileName, mLine,
    TMcpArgs.OptionalString(AArguments, 'title'), DryRunOf(AArguments));
end;

procedure AddApplyCodeAction(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('apply_code_action', cTexts[TMcpEditingText.ApplyCodeActionTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"file":{"type":"string","description":%s},' +
      '"line":{"type":"integer","minimum":1,"description":%s},' +
      '"title":{"type":"string","description":%s},' +
      '"dryRun":{"type":"boolean","default":true,"description":%s}},' +
      '"required":["file","line"]}',
      [cTexts[TMcpEditingText.ApplyCodeActionFile].Text,
      cTexts[TMcpEditingText.ApplyCodeActionLine].Text,
      cTexts[TMcpEditingText.ApplyCodeActionTitle].Text,
      cTexts[TMcpEditingText.ApplyCodeActionDryRun].Text]),
    ContextTool(AContext, ToolApplyCodeAction), TMcpToolKind.Write);
end;

function ToolFixFindings(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFiles, mRules: TArray<string>;
  mItems: TJSONArray;
  mItem: TJSONValue;
  mFile: string;
begin
  mRules := nil;
  if (AArguments <> nil) and (AArguments.GetValue('rules') is TJSONArray) then
  begin
    mItems := TJSONArray(AArguments.GetValue('rules'));
    for mItem in mItems do
    begin
      if (mItem is TJSONString) and (Trim(mItem.Value) <> '') then
      begin
        mRules := mRules + [Trim(mItem.Value)];
      end;
    end;
  end;
  mFile := TMcpArgs.OptionalString(AArguments, 'file');
  if mFile <> '' then
  begin
    mFiles := TArray<string>.Create(AContext.Guard.Resolve(mFile));
  end
  else
  begin
    mFiles := AContext.Group.Main.State.ProjectFiles;
  end;
  if Length(mFiles) = 0 then
  begin
    raise EMcpToolError.Create(TShellTexts.NoProjectGiveFile);
  end;
  Result := AContext.Edit.FixFindings(TMcpRuleScope.Create(BuiltinRules,
    AContext.Group.Main.Configuration.Settings, AContext.Root), mFiles, mRules,
    TMcpArgs.OptionalString(AArguments, 'minConfidence'), DryRunOf(AArguments));
end;

procedure AddFixFindings(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('fix_findings', cTexts[TMcpEditingText.FixFindingsTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"rules":{"type":"array","items":{"type":"string"},' +
      '"description":%s},' +
      '"file":{"type":"string","description":%s},' +
      '"minConfidence":{"type":"string","enum":["medium","high"],"description":%s},' +
      '"dryRun":{"type":"boolean","default":true,"description":%s}},' +
      '"required":["rules"]}',
      [cTexts[TMcpEditingText.FixFindingsRules].Text,
      cTexts[TMcpEditingText.FixFindingsFile].Text,
      cTexts[TMcpEditingText.FixFindingsMinConfidence].Text,
      cTexts[TMcpEditingText.FixFindingsDryRun].Text]),
    ContextTool(AContext, ToolFixFindings), TMcpToolKind.Write);
end;

function ToolFormatCode(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFileName, mText: string;
  mStartLine, mEndLine: Integer;
  mScope: TFormatScope;
  mStyle: TFormatStyle;
begin
  mFileName := AContext.Guard.Resolve(TMcpArgs.RequiredString(AArguments, 'file'));
  mScope := TFormatScope.All;
  if AArguments.TryGetValue<Integer>('startLine', mStartLine) then
  begin
    if not AArguments.TryGetValue<Integer>('endLine', mEndLine) then
    begin
      mEndLine := mStartLine;
    end;
    if (mStartLine < 1) or (mEndLine < mStartLine) then
    begin
      raise EMcpToolError.Create(cTexts[TMcpEditingText.LineRange].Text);
    end;
    mScope := TFormatScope.Lines([TFormatLineSpan.Create(mStartLine - 1, mEndLine - 1)]);
  end;
  // Formatregeln wie im Editor: format.* über .editorconfig über den Vorgaben (TLspFormatting.Resolve).
  mStyle := TLspFormatting.Resolve(nil, mFileName,
    AContext.Group.WorkspaceOf(mFileName).Configuration.Settings.Formatting,
    function(const AConfigFile: string; out AConfigText: string): Boolean
    begin
      Result := FileExists(AConfigFile) and ReadSourceText(AConfigFile, AConfigText);
    end);
  if AArguments.TryGetValue<string>('text', mText) then
  begin
    Result := AContext.Edit.FormatCode(mStyle, mFileName, mText, mScope);
  end
  else
  begin
    Result := AContext.Edit.FormatCode(mStyle, mFileName, mScope, DryRunOf(AArguments));
  end;
end;

procedure AddFormatCode(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('format_code', cTexts[TMcpEditingText.FormatCodeTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"file":{"type":"string","description":%s},' +
      '"text":{"type":"string","description":%s},' +
      '"startLine":{"type":"integer","minimum":1,"description":%s},' +
      '"endLine":{"type":"integer","minimum":1,"description":%s},' +
      '"dryRun":{"type":"boolean","default":true,"description":%s}},' +
      '"required":["file"]}',
      [cTexts[TMcpEditingText.FormatCodeFile].Text,
      cTexts[TMcpEditingText.FormatCodeText].Text,
      cTexts[TMcpEditingText.FormatCodeStartLine].Text,
      cTexts[TMcpEditingText.FormatCodeEndLine].Text,
      cTexts[TMcpEditingText.FormatCodeDryRun].Text]),
    ContextTool(AContext, ToolFormatCode), TMcpToolKind.Write);
end;

procedure RegisterEditingTools(const AContext: TMcpToolContext);
begin
  AddRenameSymbol(AContext);
  AddApplyCodeAction(AContext);
  AddFixFindings(AContext);
  AddFormatCode(AContext);
end;

initialization
  TAtlasTextTables.Add('Shell.Mcp.EditingTools', cTexts);

end.
