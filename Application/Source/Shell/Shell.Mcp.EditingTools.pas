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
  Atlas.Common.Rules.Builtin;

function ToolRenameSymbol(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  FileName: string;
  Line, Column: Integer;
begin
  FileName := AContext.Guard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
  if not AArguments.TryGetValue<Integer>('line', Line) or not AArguments.TryGetValue<Integer>('column', Column) then
  begin
    raise EMcpToolError.Create('Argumente "line" und "column" fehlen');
  end;
  AContext.Edit.Namespaces := AContext.Group.Main.State.Namespaces;
  Result := AContext.Edit.RenameSymbol(FileName, Line, Column, TMcpServer.RequiredString(AArguments, 'newName'),
    DryRunOf(AArguments));
end;

procedure AddRenameSymbol(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('rename_symbol',
    'Benennt ein Symbol projektweit um, samt .dfm/.fmx und automatisch benannter Ereignis-Handler (#61). ' +
    'dryRun (Vorgabe true) zeigt nur den Diff; dryRun=false schreibt alle Dateien atomar.',
    '{"type":"object","properties":{' +
      '"file":{"type":"string","description":"Datei mit dem Symbol (relativ zum Projekt oder absolut)"},' +
      '"line":{"type":"integer","minimum":1,"description":"Zeile (ab 1)"},' +
      '"column":{"type":"integer","minimum":1,"description":"Spalte (ab 1) im Bezeichner"},' +
      '"newName":{"type":"string","description":"Neuer Name"},' +
      '"dryRun":{"type":"boolean","default":true,"description":"Nur Vorschau, nichts schreiben"}},' +
      '"required":["file","line","column","newName"]}',
    ContextTool(AContext, ToolRenameSymbol), TMcpToolKind.Write);
end;

function ToolApplyCodeAction(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  FileName: string;
  Line: Integer;
begin
  FileName := AContext.Guard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
  if not AArguments.TryGetValue<Integer>('line', Line) then
  begin
    raise EMcpToolError.Create('Argument "line" fehlt');
  end;
  Result := AContext.Edit.ApplyCodeAction(TMcpRuleScope.Create(BuiltinRules,
    AContext.Group.Main.Configuration.Settings, AContext.Root), FileName, Line,
    TMcpServer.OptionalString(AArguments, 'title'), DryRunOf(AArguments));
end;

procedure AddApplyCodeAction(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('apply_code_action',
    'Wendet die Korrektur eines Regeltreffers in einer Zeile an (#61). Ohne title listet es die Korrekturen der Zeile. ' +
    'dryRun (Vorgabe true) zeigt nur den Diff; dryRun=false schreibt.',
    '{"type":"object","properties":{' +
      '"file":{"type":"string","description":"Pfad der Unit (relativ zum Projekt oder absolut)"},' +
      '"line":{"type":"integer","minimum":1,"description":"Zeile des Befunds (ab 1)"},' +
      '"title":{"type":"string","description":"Titel der Korrektur oder Regelkennung; leer = Korrekturen auflisten"},' +
      '"dryRun":{"type":"boolean","default":true,"description":"Nur Vorschau, nichts schreiben"}},' +
      '"required":["file","line"]}',
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
  mFile := TMcpServer.OptionalString(AArguments, 'file');
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
    raise EMcpToolError.Create('Kein Projekt geladen; Datei angeben');
  end;
  Result := AContext.Edit.FixFindings(TMcpRuleScope.Create(BuiltinRules,
    AContext.Group.Main.Configuration.Settings, AContext.Root), mFiles, mRules,
    TMcpServer.OptionalString(AArguments, 'minConfidence'), DryRunOf(AArguments));
end;

procedure AddFixFindings(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('fix_findings',
    'Sammelkorrektur (#1352): wendet die sicheren Korrekturen der genannten Regeln (oder "all") in einer Datei ' +
    'oder im ganzen Projekt an, nur Treffer ab fix.minConfidence (Vorgabe hoch) und nur Regeln mit safeFix im ' +
    'Katalog; bis zu drei Durchgänge, keine neuen Syntaxfehler. dryRun (Vorgabe true) zeigt nur Zusammenfassung ' +
    'und Diff; dryRun=false schreibt alle Dateien oder keine. In der IDE offene Dateien ändert das Plugin als ' +
    'einen Rückgängig-Schritt je Datei, ungespeicherte bleiben unberührt.',
    '{"type":"object","properties":{' +
      '"rules":{"type":"array","items":{"type":"string"},"description":"Regelkennungen, z. B. [\"redundant-cast\"]; [\"all\"] = alle"},' +
      '"file":{"type":"string","description":"Pfad einer Unit; leer = alle Projektdateien"},' +
      '"minConfidence":{"type":"string","enum":["medium","high"],"description":"Untergrenze der Konfidenz; nicht unter fix.minConfidence"},' +
      '"dryRun":{"type":"boolean","default":true,"description":"Nur Vorschau, nichts schreiben"}},' +
      '"required":["rules"]}',
    ContextTool(AContext, ToolFixFindings), TMcpToolKind.Write);
end;

function ToolFormatCode(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFileName, mText: string;
  mStartLine, mEndLine: Integer;
  mScope: TFormatScope;
  mStyle: TFormatStyle;
begin
  mFileName := AContext.Guard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
  mScope := TFormatScope.All;
  if AArguments.TryGetValue<Integer>('startLine', mStartLine) then
  begin
    if not AArguments.TryGetValue<Integer>('endLine', mEndLine) then
    begin
      mEndLine := mStartLine;
    end;
    if (mStartLine < 1) or (mEndLine < mStartLine) then
    begin
      raise EMcpToolError.Create('"startLine" ab 1 und "endLine" nicht davor');
    end;
    mScope := TFormatScope.Lines([TFormatLineSpan.Create(mStartLine - 1, mEndLine - 1)]);
  end;
  // Formatregeln wie im Editor: format.* über .editorconfig über den Vorgaben (TLspFormatting.Resolve).
  mStyle := TLspFormatting.Resolve(nil, mFileName, AContext.Group.WorkspaceOf(mFileName).Configuration.Settings.Formatting,
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
  AContext.Server.AddTool('format_code',
    'Formatiert eine Unit nach den Formatregeln des Projekts (#1358; format.* in atlas.json, .editorconfig) wie ' +
    '"Dokument formatieren" in der IDE, ganz oder nur startLine..endLine. Mit text wird geplanter Code statt der ' +
    'Datei formatiert und als Text zurückgegeben, ohne zu schreiben. Ohne text zeigt dryRun (Vorgabe true) den ' +
    'Diff; dryRun=false schreibt wie apply_code_action (offene Dateien als ein Rückgängig-Schritt in der IDE). ' +
    'Dateien mit Syntaxfehlern werden nicht formatiert; // atlas-format: off ... on bleibt unverändert.',
    '{"type":"object","properties":{' +
      '"file":{"type":"string","description":"Pfad der Unit (relativ zum Projekt oder absolut)"},' +
      '"text":{"type":"string","description":"Optional: geplanter Inhalt der ganzen Unit statt der Datei"},' +
      '"startLine":{"type":"integer","minimum":1,"description":"Erste zu formatierende Zeile (ab 1); ohne Angabe die ganze Unit"},' +
      '"endLine":{"type":"integer","minimum":1,"description":"Letzte zu formatierende Zeile; Vorgabe startLine"},' +
      '"dryRun":{"type":"boolean","default":true,"description":"Nur Vorschau, nichts schreiben"}},' +
      '"required":["file"]}',
    ContextTool(AContext, ToolFormatCode), TMcpToolKind.Write);
end;

procedure RegisterEditingTools(const AContext: TMcpToolContext);
begin
  AddRenameSymbol(AContext);
  AddApplyCodeAction(AContext);
  AddFixFindings(AContext);
  AddFormatCode(AContext);
end;

end.
