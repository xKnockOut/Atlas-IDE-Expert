unit Shell.Mcp.NavigationTools;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Werkzeuge zur Navigation im Symbolindex:
// Symbole, Deklarationen, Hierarchien, Verweise, Umsetzungen (#2635), Auswirkungen und qualifizierte Namen.

interface

uses
  Shell.Mcp.Context;

/// <summary>Meldet find_symbol bis get_impact, find_implementations und qualified_name an.</summary>
procedure RegisterNavigationTools(const AContext: TMcpToolContext);

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.CodeTools,
  Atlas.Common.Mcp.ImplementationTools,
  Atlas.Common.Localization.Texts,
  Shell.Texts;

type
{$SCOPEDENUMS ON}
  TMcpNavigationText = (FindSymbolTool, FindSymbolName, GetDeclarationTool, GetDeclarationName, GetRationaleTool,
    GetRationaleUnit, GetRationaleName, GetTypeHierarchyTool, GetTypeHierarchyName, GetComponentInfoTool,
    GetComponentInfoName, GetUnitOutlineTool, GetUnitOutlineUnit, FindReferencesTool, FindReferencesName,
    GetCallHierarchyTool, GetCallHierarchyName, GetCallHierarchyDirection, GetImpactTool, GetImpactName,
    GetImpactDepth, GetImpactFormat, QualifiedNameTool, QualifiedNameFile, QualifiedNameLine, QualifiedNameColumn,
    QualifiedNameWithParameters, FindImplementationsTool, FindImplementationsName, FindImplementationsFile,
    FindImplementationsLine, FindImplementationsColumn, FindImplementationsIncludeBody, FindImplementationsFormat);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpNavigationText] of TAtlasText = (
    (De: 'Sucht Delphi-Symbole (Typen, Methoden, Felder, Konstanten …) im Projekt und in RTL/VCL. Liefert Art, ' +
    'Typ, Unit und Datei:Zeile. Name einfach ("Execute") oder qualifiziert ("TMyForm.Execute"); ohne exakten ' +
    'Treffer wird nach Teilstrings gesucht.';
    En: 'Searches Delphi symbols (types, methods, fields, constants …) in the project and in RTL/VCL. Returns ' +
    'kind, type, unit and file:line. Name simple ("Execute") or qualified ("TMyForm.Execute"); without an ' +
    'exact match it searches for substrings.'),
    (De: 'Symbolname, optional mit Typ davor (TFoo.Bar)';
    En: 'Symbol name, optionally with the type in front (TFoo.Bar)'),
    (De: 'Vollständiger Quelltext der Deklaration eines Symbols, auch aus RTL/VCL, ohne die ganze Datei zu lesen. ' +
    'Dazu die Begründungen (// WHY:, // HACK:, // NOTE: … über der Deklaration und im Rumpf).';
    En: 'Complete source of the declaration of a symbol, also from RTL/VCL, without reading the whole file. Plus ' +
    'the rationales (// WHY:, // HACK:, // NOTE: … above the declaration and in the body).'),
    (De: 'Symbolname, am besten qualifiziert (TFoo.Bar)'; En: 'Symbol name, preferably qualified (TFoo.Bar)'),
    (De: 'Begründungen (#1123): Kommentare wie // WHY:, // HACK:, // NOTE:, // IMPORTANT:, // RATIONALE: (Marken ' +
    'aus hints.rationaleMarkers) einer Unit samt aller Symbole oder eines Symbols, mit Datei und Zeile. ' +
    'Erklärt, warum Code so gebaut ist; Verweise wie ADR-0007 oder #312 stehen im Text.';
    En: 'Rationales (#1123): comments like // WHY:, // HACK:, // NOTE:, // IMPORTANT:, // RATIONALE: (markers ' +
    'from hints.rationaleMarkers) of a unit with all its symbols or of one symbol, with file and line. ' +
    'Explains why code is built the way it is; references like ADR-0007 or #312 are in the text.'),
    (De: 'Unit-Name oder Pfad der .pas-Datei'; En: 'Unit name or path of the .pas file'),
    (De: 'Symbolname, am besten qualifiziert (TFoo.Bar); statt unit';
    En: 'Symbol name, preferably qualified (TFoo.Bar); instead of unit'),
    (De: 'Vorfahren bis zur Wurzel und alle Nachfahren einer Klasse oder eines Interfaces mit Fundstellen.';
    En: 'Ancestors up to the root and all descendants of a class or interface with locations.'),
    (De: 'Typname, z. B. TCustomForm'; En: 'Type name, e.g. TCustomForm'),
    (De: 'published-Properties mit Typ und Default, Ereignisse mit Signatur, Vorfahren, Palettenseite und Package ' +
    'einer Komponentenklasse, auch aus der VCL.';
    En: 'Published properties with type and default, events with signature, ancestors, palette page and package ' +
    'of a component class, also from the VCL.'),
    (De: 'Klassenname, z. B. TButton'; En: 'Class name, e.g. TButton'),
    (De: 'Gliederung einer Unit ohne Quelltext: uses-Listen, Typen, Methoden, Felder mit Zeilennummern.';
    En: 'Outline of a unit without source: uses lists, types, methods, fields with line numbers.'),
    (De: 'Unit-Name (Vcl.Forms) oder Pfad der .pas-Datei'; En: 'Unit name (Vcl.Forms) or path of the .pas file'),
    (De: 'Alle Verwendungen eines Symbols im Projekt mit Datei:Zeile und der Quelltextzeile.';
    En: 'All usages of a symbol in the project with file:line and the source line.'),
    (De: 'Symbolname, am besten qualifiziert (TFoo.Bar)'; En: 'Symbol name, preferably qualified (TFoo.Bar)'),
    (De: 'Aufrufer (incoming) und aufgerufene Routinen (outgoing) einer Methode oder Routine.';
    En: 'Callers (incoming) and called routines (outgoing) of a method or routine.'),
    (De: 'Methode oder Routine, z. B. TFoo.Bar'; En: 'Method or routine, e.g. TFoo.Bar'),
    (De: 'incoming, outgoing oder both (Standard)'; En: 'incoming, outgoing or both (default)'),
    (De: 'Auswirkungsanalyse (#1120): Was ist betroffen, wenn sich ein Symbol ändert? Aufrufer und Verweise, ' +
    'Overrides, überschriebene Basismethode, Interface-Methode und Umsetzungen sowie Formularbindungen, nach ' +
    'Ebenen bis zur Tiefe (Vorgabe navigation.impactDepth), dazu die betroffenen DUnitX-Tests mit den Namen ' +
    'für run_tests. Erschlossene Treffer mit Grund (#1119); erreichte Grenzen stehen am Ende.';
    En: 'Impact analysis (#1120): what is affected when a symbol changes? Callers and references, overrides, ' +
    'overridden base method, interface method and implementations as well as form bindings, by level up to ' +
    'the depth (default navigation.impactDepth), plus the affected DUnitX tests with the names for ' +
    'run_tests. Inferred matches with a reason (#1119); limits reached are listed at the end.'),
    (De: 'Symbol, am besten qualifiziert (TFoo.Bar)'; En: 'Symbol, preferably qualified (TFoo.Bar)'),
    (De: 'Ebenen; leer = navigation.impactDepth'; En: 'Levels; empty = navigation.impactDepth'),
    (De: 'text (Vorgabe) oder json wie atlas/impact'; En: 'text (default) or json like atlas/impact'),
    (De: 'Voll qualifizierter Name des Symbols an einer Stelle (Unit.TKlasse.Methode), z. B. für Dokumentation.';
    En: 'Fully qualified name of the symbol at a position (Unit.TClass.Method), e.g. for documentation.'),
    (De: 'Pfad der Unit (relativ zum Projekt oder absolut)';
    En: 'Path of the unit (relative to the project or absolute)'),
    (De: 'Zeile ab 1'; En: 'Line from 1'),
    (De: 'Spalte ab 1'; En: 'Column from 1'),
    (De: 'Bei Routinen die Parametertypen anhängen'; En: 'For routines, append the parameter types'),
    (De: 'Umsetzungen einer Interface- oder virtuellen Methode (#2635): welche Klassen sie umsetzen, wo die ' +
    'Rümpfe stehen und wie (umgesetzt, überschrieben, abstrakt, reintroduce, Methodenzuordnung, Delegation ' +
    'über implements), Testunits gekennzeichnet. Dieselben Ziele wie „Gehe zu Implementierung“ und dieselbe ' +
    'Zahl wie get_call_hierarchy. Bei Klassen und Interfaces die Nachfahren bzw. umsetzenden Klassen.';
    En: 'Implementations of an interface or virtual method (#2635): which classes implement it, where the ' +
    'bodies are and how (implemented, overridden, abstract, reintroduce, method resolution, delegation via ' +
    'implements), test units marked. The same targets as "Go to implementation" and the same count as ' +
    'get_call_hierarchy. For classes and interfaces the descendants or implementing classes.'),
    (De: 'Methode oder Typ, z. B. IFoo.Bar, TFoo.Bar oder Unit.TFoo.Bar; statt file, line und column';
    En: 'Method or type, e.g. IFoo.Bar, TFoo.Bar or Unit.TFoo.Bar; instead of file, line and column'),
    (De: 'Pfad der Unit mit dem Symbol (statt name)'; En: 'Path of the unit with the symbol (instead of name)'),
    (De: 'Zeile ab 1 (mit file)'; En: 'Line from 1 (with file)'),
    (De: 'Spalte ab 1 (mit file)'; En: 'Column from 1 (with file)'),
    (De: 'Rumpf je Umsetzung mitliefern, höchstens 20 Zeilen (Vorgabe false)';
    En: 'Include the body of each implementation, at most 20 lines (default false)'),
    (De: 'markdown (Vorgabe) oder json'; En: 'markdown (default) or json'));

function ToolFindSymbol(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := AContext.Tools.FindSymbol(TMcpArgs.RequiredString(AArguments, 'name'));
end;

procedure AddFindSymbol(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('find_symbol', cTexts[TMcpNavigationText.FindSymbolTool].Text,
    TMcpArgs.StringSchema(['name'],
      [cTexts[TMcpNavigationText.FindSymbolName].Text]),
    ContextTool(AContext, ToolFindSymbol));
end;

function ToolGetDeclaration(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := AContext.Tools.Declaration(TMcpArgs.RequiredString(AArguments, 'name'));
end;

procedure AddGetDeclaration(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_declaration', cTexts[TMcpNavigationText.GetDeclarationTool].Text,
    TMcpArgs.StringSchema(['name'],
      [cTexts[TMcpNavigationText.GetDeclarationName].Text]),
    ContextTool(AContext, ToolGetDeclaration));
end;

function ToolGetRationale(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := AContext.Tools.Rationale(TMcpArgs.OptionalString(AArguments, 'unit'),
    TMcpArgs.OptionalString(AArguments, 'name'));
end;

procedure AddGetRationale(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_rationale', cTexts[TMcpNavigationText.GetRationaleTool].Text,
    TMcpArgs.StringSchema(['unit', 'name'],
      [cTexts[TMcpNavigationText.GetRationaleUnit].Text,
      cTexts[TMcpNavigationText.GetRationaleName].Text], 0),
    ContextTool(AContext, ToolGetRationale));
end;

function ToolGetTypeHierarchy(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := AContext.Tools.TypeHierarchy(TMcpArgs.RequiredString(AArguments, 'name'));
end;

procedure AddGetTypeHierarchy(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_type_hierarchy', cTexts[TMcpNavigationText.GetTypeHierarchyTool].Text,
    TMcpArgs.StringSchema(['name'],
      [cTexts[TMcpNavigationText.GetTypeHierarchyName].Text]),
    ContextTool(AContext, ToolGetTypeHierarchy));
end;

function ToolGetComponentInfo(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := AContext.Tools.ComponentInfo(TMcpArgs.RequiredString(AArguments, 'name'));
end;

procedure AddGetComponentInfo(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_component_info', cTexts[TMcpNavigationText.GetComponentInfoTool].Text,
    TMcpArgs.StringSchema(['name'],
      [cTexts[TMcpNavigationText.GetComponentInfoName].Text]),
    ContextTool(AContext, ToolGetComponentInfo));
end;

function ToolGetUnitOutline(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := AContext.Tools.UnitOutline(TMcpArgs.RequiredString(AArguments, 'unit'));
end;

procedure AddGetUnitOutline(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_unit_outline', cTexts[TMcpNavigationText.GetUnitOutlineTool].Text,
    TMcpArgs.StringSchema(['unit'],
      [cTexts[TMcpNavigationText.GetUnitOutlineUnit].Text]),
    ContextTool(AContext, ToolGetUnitOutline));
end;

function ToolFindReferences(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  AContext.Code.Namespaces := AContext.Group.Main.State.Namespaces;
  Result := AContext.Code.References(TMcpArgs.RequiredString(AArguments, 'name'));
end;

procedure AddFindReferences(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('find_references', cTexts[TMcpNavigationText.FindReferencesTool].Text,
    TMcpArgs.StringSchema(['name'],
      [cTexts[TMcpNavigationText.FindReferencesName].Text]),
    ContextTool(AContext, ToolFindReferences));
end;

function ToolGetCallHierarchy(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  AContext.Code.Namespaces := AContext.Group.Main.State.Namespaces;
  Result := AContext.Code.CallHierarchy(TMcpArgs.RequiredString(AArguments, 'name'),
    TMcpCodeTools.ParseDirection(TMcpArgs.OptionalString(AArguments, 'direction')));
end;

procedure AddGetCallHierarchy(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_call_hierarchy', cTexts[TMcpNavigationText.GetCallHierarchyTool].Text,
    TMcpArgs.StringSchema(['name', 'direction'],
      [cTexts[TMcpNavigationText.GetCallHierarchyName].Text,
      cTexts[TMcpNavigationText.GetCallHierarchyDirection].Text], 1),
    ContextTool(AContext, ToolGetCallHierarchy));
end;

function ToolGetImpact(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mName, mFormat: string;
  mDepth: Integer;
begin
  mName := TMcpArgs.RequiredString(AArguments, 'name');
  mFormat := TMcpArgs.OptionalString(AArguments, 'format');
  if (mFormat <> '') and not SameText(mFormat, 'text') and not SameText(mFormat, 'json') then
  begin
    raise EMcpToolError.Create(TShellTexts.Choice('format', ['text', 'json']));
  end;
  AContext.Code.Namespaces := AContext.Group.Main.State.Namespaces;
  if AArguments.TryGetValue<Integer>('depth', mDepth) then
  begin
    Result := AContext.Code.Impact(mName, mDepth, SameText(mFormat, 'json'));
  end
  else
  begin
    Result := AContext.Code.Impact(mName, SameText(mFormat, 'json'));
  end;
end;

procedure AddGetImpact(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_impact', cTexts[TMcpNavigationText.GetImpactTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"name":{"type":"string","description":%s},' +
      '"depth":{"type":"integer","minimum":1,"maximum":5,"description":%s},' +
      '"format":{"type":"string","enum":["text","json"],"description":%s}},' +
      '"required":["name"]}',
      [cTexts[TMcpNavigationText.GetImpactName].Text,
      cTexts[TMcpNavigationText.GetImpactDepth].Text,
      cTexts[TMcpNavigationText.GetImpactFormat].Text]),
    ContextTool(AContext, ToolGetImpact));
end;

function ToolQualifiedName(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFileName: string;
  mLine, mColumn: Integer;
  mWithParameters: Boolean;
begin
  mFileName := AContext.Guard.Resolve(TMcpArgs.RequiredString(AArguments, 'file'));
  if not (AArguments.TryGetValue<Integer>('line', mLine) and AArguments.TryGetValue<Integer>('column', mColumn)) then
  begin
    raise EMcpToolError.Create(TShellTexts.Missing(['line', 'column']));
  end;
  if not AArguments.TryGetValue<Boolean>('withParameters', mWithParameters) then
  begin
    mWithParameters := False;
  end;
  AContext.Code.Namespaces := AContext.Group.Main.State.Namespaces;
  Result := AContext.Code.QualifiedName(mFileName, mLine, mColumn, mWithParameters);
end;

procedure AddQualifiedName(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('qualified_name', cTexts[TMcpNavigationText.QualifiedNameTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"file":{"type":"string","description":%s},' +
      '"line":{"type":"integer","minimum":1,"description":%s},' +
      '"column":{"type":"integer","minimum":1,"description":%s},' +
      '"withParameters":{"type":"boolean","description":%s}},' +
      '"required":["file","line","column"]}',
      [cTexts[TMcpNavigationText.QualifiedNameFile].Text,
      cTexts[TMcpNavigationText.QualifiedNameLine].Text,
      cTexts[TMcpNavigationText.QualifiedNameColumn].Text,
      cTexts[TMcpNavigationText.QualifiedNameWithParameters].Text]),
    ContextTool(AContext, ToolQualifiedName));
end;

/// <summary>Name des Symbols aus name bzw. aus file, line und column (über qualified_name).</summary>
function ImplementationsName(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFileName: string;
  mLine, mColumn: Integer;
begin
  Result := TMcpArgs.OptionalString(AArguments, 'name');
  if Result <> '' then
  begin
    Exit;
  end;
  mFileName := TMcpArgs.OptionalString(AArguments, 'file');
  if (mFileName = '') or not (AArguments.TryGetValue<Integer>('line', mLine) and
    AArguments.TryGetValue<Integer>('column', mColumn)) then
  begin
    raise EMcpToolError.Create(TShellTexts.Missing(['name', 'file', 'line', 'column']));
  end;
  AContext.Code.Namespaces := AContext.Group.Main.State.Namespaces;
  Result := AContext.Code.QualifiedName(AContext.Guard.Resolve(mFileName), mLine, mColumn, False);
end;

function ToolFindImplementations(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFormat: string;
  mIncludeBody: Boolean;
  mTools: TMcpImplementationTools;
begin
  mFormat := TMcpArgs.OptionalString(AArguments, 'format');
  if (mFormat <> '') and not SameText(mFormat, 'markdown') and not SameText(mFormat, 'json') then
  begin
    raise EMcpToolError.Create(TShellTexts.Choice('format', ['markdown', 'json']));
  end;
  if not AArguments.TryGetValue<Boolean>('includeBody', mIncludeBody) then
  begin
    mIncludeBody := False;
  end;
  mTools := TMcpImplementationTools.Create(AContext.Index, ReadSourceText);
  try
    mTools.ImpactOptionsFor := AContext.ImpactOptionsFor;
    Result := mTools.Find(ImplementationsName(AContext, AArguments), mIncludeBody, SameText(mFormat, 'json'));
  finally
    mTools.Free;
  end;
end;

procedure AddFindImplementations(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('find_implementations', cTexts[TMcpNavigationText.FindImplementationsTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"name":{"type":"string","description":%s},' +
      '"file":{"type":"string","description":%s},' +
      '"line":{"type":"integer","minimum":1,"description":%s},' +
      '"column":{"type":"integer","minimum":1,"description":%s},' +
      '"includeBody":{"type":"boolean","description":%s},' +
      '"format":{"type":"string","enum":["markdown","json"],"description":%s}}}',
      [cTexts[TMcpNavigationText.FindImplementationsName].Text,
      cTexts[TMcpNavigationText.FindImplementationsFile].Text,
      cTexts[TMcpNavigationText.FindImplementationsLine].Text,
      cTexts[TMcpNavigationText.FindImplementationsColumn].Text,
      cTexts[TMcpNavigationText.FindImplementationsIncludeBody].Text,
      cTexts[TMcpNavigationText.FindImplementationsFormat].Text]),
    ContextTool(AContext, ToolFindImplementations));
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
  AddFindImplementations(AContext);
  AddQualifiedName(AContext);
end;

initialization
  TAtlasTextTables.Add('Shell.Mcp.NavigationTools', cTexts);

end.
