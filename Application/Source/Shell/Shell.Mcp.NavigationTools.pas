unit Shell.Mcp.NavigationTools;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Werkzeuge zur Navigation im Symbolindex:
// Symbole, Deklarationen, Hierarchien, Verweise, Auswirkungen und qualifizierte Namen.

interface

uses
  Shell.Mcp.Context;

/// <summary>Meldet find_symbol bis get_impact und qualified_name an.</summary>
procedure RegisterNavigationTools(const AContext: TMcpToolContext);

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.CodeTools;

function ToolFindSymbol(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := AContext.Tools.FindSymbol(TMcpServer.RequiredString(AArguments, 'name'));
end;

procedure AddFindSymbol(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('find_symbol',
    'Sucht Delphi-Symbole (Typen, Methoden, Felder, Konstanten …) im Projekt und in RTL/VCL. ' +
    'Liefert Art, Typ, Unit und Datei:Zeile. Name einfach ("Execute") oder qualifiziert ("TMyForm.Execute"); ' +
    'ohne exakten Treffer wird nach Teilstrings gesucht.',
    TMcpServer.StringSchema(['name'], ['Symbolname, optional mit Typ davor (TFoo.Bar)']),
    ContextTool(AContext, ToolFindSymbol));
end;

function ToolGetDeclaration(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := AContext.Tools.Declaration(TMcpServer.RequiredString(AArguments, 'name'));
end;

procedure AddGetDeclaration(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_declaration',
    'Vollständiger Quelltext der Deklaration eines Symbols, auch aus RTL/VCL, ohne die ganze Datei zu lesen. ' +
    'Dazu die Begründungen (// WHY:, // HACK:, // NOTE: … über der Deklaration und im Rumpf).',
    TMcpServer.StringSchema(['name'], ['Symbolname, am besten qualifiziert (TFoo.Bar)']),
    ContextTool(AContext, ToolGetDeclaration));
end;

function ToolGetRationale(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := AContext.Tools.Rationale(TMcpServer.OptionalString(AArguments, 'unit'),
    TMcpServer.OptionalString(AArguments, 'name'));
end;

procedure AddGetRationale(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_rationale',
    'Begründungen (#1123): Kommentare wie // WHY:, // HACK:, // NOTE:, // IMPORTANT:, // RATIONALE: (Marken aus ' +
    'hints.rationaleMarkers) einer Unit samt aller Symbole oder eines Symbols, mit Datei und Zeile. Erklärt, ' +
    'warum Code so gebaut ist; Verweise wie ADR-0007 oder #312 stehen im Text.',
    TMcpServer.StringSchema(['unit', 'name'], ['Unit-Name oder Pfad der .pas-Datei',
      'Symbolname, am besten qualifiziert (TFoo.Bar); statt unit'], 0),
    ContextTool(AContext, ToolGetRationale));
end;

function ToolGetTypeHierarchy(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := AContext.Tools.TypeHierarchy(TMcpServer.RequiredString(AArguments, 'name'));
end;

procedure AddGetTypeHierarchy(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_type_hierarchy',
    'Vorfahren bis zur Wurzel und alle Nachfahren einer Klasse oder eines Interfaces mit Fundstellen.',
    TMcpServer.StringSchema(['name'], ['Typname, z. B. TCustomForm']),
    ContextTool(AContext, ToolGetTypeHierarchy));
end;

function ToolGetComponentInfo(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := AContext.Tools.ComponentInfo(TMcpServer.RequiredString(AArguments, 'name'));
end;

procedure AddGetComponentInfo(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_component_info',
    'published-Properties mit Typ und Default, Ereignisse mit Signatur, Vorfahren, Palettenseite und Package ' +
    'einer Komponentenklasse, auch aus der VCL.',
    TMcpServer.StringSchema(['name'], ['Klassenname, z. B. TButton']),
    ContextTool(AContext, ToolGetComponentInfo));
end;

function ToolGetUnitOutline(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := AContext.Tools.UnitOutline(TMcpServer.RequiredString(AArguments, 'unit'));
end;

procedure AddGetUnitOutline(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_unit_outline',
    'Gliederung einer Unit ohne Quelltext: uses-Listen, Typen, Methoden, Felder mit Zeilennummern.',
    TMcpServer.StringSchema(['unit'], ['Unit-Name (Vcl.Forms) oder Pfad der .pas-Datei']),
    ContextTool(AContext, ToolGetUnitOutline));
end;

function ToolFindReferences(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  AContext.Code.Namespaces := AContext.Group.Main.State.Namespaces;
  Result := AContext.Code.References(TMcpServer.RequiredString(AArguments, 'name'));
end;

procedure AddFindReferences(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('find_references',
    'Alle Verwendungen eines Symbols im Projekt mit Datei:Zeile und der Quelltextzeile.',
    TMcpServer.StringSchema(['name'], ['Symbolname, am besten qualifiziert (TFoo.Bar)']),
    ContextTool(AContext, ToolFindReferences));
end;

function ToolGetCallHierarchy(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  AContext.Code.Namespaces := AContext.Group.Main.State.Namespaces;
  Result := AContext.Code.CallHierarchy(TMcpServer.RequiredString(AArguments, 'name'),
    TMcpCodeTools.ParseDirection(TMcpServer.OptionalString(AArguments, 'direction')));
end;

procedure AddGetCallHierarchy(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_call_hierarchy',
    'Aufrufer (incoming) und aufgerufene Routinen (outgoing) einer Methode oder Routine.',
    TMcpServer.StringSchema(['name', 'direction'],
      ['Methode oder Routine, z. B. TFoo.Bar', 'incoming, outgoing oder both (Standard)'], 1),
    ContextTool(AContext, ToolGetCallHierarchy));
end;

function ToolGetImpact(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  Name, Format: string;
  Depth: Integer;
begin
  Name := TMcpServer.RequiredString(AArguments, 'name');
  Format := TMcpServer.OptionalString(AArguments, 'format');
  if (Format <> '') and not SameText(Format, 'text') and not SameText(Format, 'json') then
  begin
    raise EMcpToolError.Create('"format" ist text oder json');
  end;
  AContext.Code.Namespaces := AContext.Group.Main.State.Namespaces;
  if AArguments.TryGetValue<Integer>('depth', Depth) then
  begin
    Result := AContext.Code.Impact(Name, Depth, SameText(Format, 'json'));
  end
  else
  begin
    Result := AContext.Code.Impact(Name, SameText(Format, 'json'));
  end;
end;

procedure AddGetImpact(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_impact',
    'Auswirkungsanalyse (#1120): Was ist betroffen, wenn sich ein Symbol ändert? Aufrufer und Verweise, ' +
    'Overrides, überschriebene Basismethode, Interface-Methode und Umsetzungen sowie Formularbindungen, nach ' +
    'Ebenen bis zur Tiefe (Vorgabe navigation.impactDepth), dazu die betroffenen DUnitX-Tests mit den Namen ' +
    'für run_tests. Erschlossene Treffer mit Grund (#1119); erreichte Grenzen stehen am Ende.',
    '{"type":"object","properties":{' +
      '"name":{"type":"string","description":"Symbol, am besten qualifiziert (TFoo.Bar)"},' +
      '"depth":{"type":"integer","minimum":1,"maximum":5,"description":"Ebenen; leer = navigation.impactDepth"},' +
      '"format":{"type":"string","enum":["text","json"],"description":"text (Vorgabe) oder json wie atlas/impact"}' +
      '},"required":["name"]}',
    ContextTool(AContext, ToolGetImpact));
end;

function ToolQualifiedName(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  FileName: string;
  Line, Column: Integer;
  WithParameters: Boolean;
begin
  FileName := AContext.Guard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
  if not (AArguments.TryGetValue<Integer>('line', Line) and AArguments.TryGetValue<Integer>('column', Column)) then
  begin
    raise EMcpToolError.Create('Argumente "line" und "column" fehlen');
  end;
  if not AArguments.TryGetValue<Boolean>('withParameters', WithParameters) then
  begin
    WithParameters := False;
  end;
  AContext.Code.Namespaces := AContext.Group.Main.State.Namespaces;
  Result := AContext.Code.QualifiedName(FileName, Line, Column, WithParameters);
end;

procedure AddQualifiedName(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('qualified_name',
    'Voll qualifizierter Name des Symbols an einer Stelle (Unit.TKlasse.Methode), z. B. für Dokumentation.',
    '{"type":"object","properties":{' +
      '"file":{"type":"string","description":"Pfad der Unit (relativ zum Projekt oder absolut)"},' +
      '"line":{"type":"integer","minimum":1,"description":"Zeile ab 1"},' +
      '"column":{"type":"integer","minimum":1,"description":"Spalte ab 1"},' +
      '"withParameters":{"type":"boolean","description":"Bei Routinen die Parametertypen anhängen"}},' +
      '"required":["file","line","column"]}',
    ContextTool(AContext, ToolQualifiedName));
end;

procedure RegisterNavigationTools(const AContext: TMcpToolContext);
begin
  AddFindSymbol(AContext);
  AddGetDeclaration(AContext);
  AddGetRationale(AContext);
  AddGetTypeHierarchy(AContext);
  AddGetComponentInfo(AContext);
  AddGetUnitOutline(AContext);
  AddFindReferences(AContext);
  AddGetCallHierarchy(AContext);
  AddGetImpact(AContext);
  AddQualifiedName(AContext);
end;

end.
