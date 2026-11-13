unit Shell.Mcp.ReportTools;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Werkzeuge für Laufzeitberichte (#74): resolve_address löst Adressen
// über die Map-Datei auf, analyze_report wertet einen Leck- oder Absturzbericht aus. Hier nur Dateien (Map, EXE,
// Bericht) und Projekt; Auswertung und Ausgabe in Atlas.Common.Mcp.ReportTools.

interface

uses
  Shell.Mcp.Context;

/// <summary>Meldet resolve_address und analyze_report an.</summary>
procedure RegisterReportTools(const AContext: TMcpToolContext);

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.Paths,
  Atlas.Common.Mcp.ReportTools,
  Atlas.Common.Mcp.TestTools,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Localization.Texts,
  Atlas.Text.MapFile,
  Atlas.Text.PeImage,
  Atlas.Text.CrashReport,
  Shell.WorkspaceGroup;

type
{$SCOPEDENUMS ON}
  TMcpReportText = (ResolveTool, ResolveAddresses, MapArgument, ExeArgument, ProjectArgument, BaseArgument,
    AnalyzeTool, AnalyzeText, AnalyzeFile, MapMissing, ProjectUnreadable, BadBase, TextOrFile);
{$SCOPEDENUMS OFF}

const
  // Der PE-Kopf samt Abschnittstabelle steht in den ersten Kilobytes der Datei.
  cImageHeadBytes = 64 * 1024;

  cTexts: array[TMcpReportText] of TAtlasText = (
    (De: 'Löst Adressen aus Absturzberichten über die Map-Datei des Linkers (DCC_MapFile=3) in Unit, Routine, ' +
      'Zeile und Datei im Projekt auf. Absolute Adressen gehen über die Basisadresse des Moduls (aus der EXE, sonst ' +
      'aus der Map, oder base), „Modul+$Offset“ über den Offset. Mit exe oder project prüft es, ob Map und EXE zum ' +
      'selben Build gehören.';
     En: 'Resolves addresses from crash reports through the linker map file (DCC_MapFile=3) into unit, routine, ' +
      'line and file in the project. Absolute addresses use the module base address (from the EXE, otherwise from ' +
      'the map, or base), "module+$offset" uses the offset. With exe or project it checks that map and EXE belong to ' +
      'the same build.'),
    (De: 'Adressen, getrennt durch Leerzeichen oder Komma: 0045A1B2, $0045A1B2, 0x0045A1B2 oder Kunden.exe+$5A1B2';
     En: 'Addresses separated by spaces or commas: 0045A1B2, $0045A1B2, 0x0045A1B2 or Customers.exe+$5A1B2'),
    (De: 'Map-Datei (.map); leer = neben exe bzw. der EXE des Projekts';
     En: 'Map file (.map); empty = next to exe or the project EXE'),
    (De: 'EXE, DLL oder BPL des Builds; für Vorzugsbasis und Prüfung gegen die Map';
     En: 'EXE, DLL or BPL of the build; for the preferred base and the check against the map'),
    (De: 'Projekt (.dproj); EXE und Map aus seinem Ausgabeordner';
     En: 'Project (.dproj); EXE and map from its output folder'),
    (De: 'Basisadresse, mit der das Modul geladen war (hex); leer = Vorzugsbasis';
     En: 'Base address the module was loaded at (hex); empty = preferred base'),
    (De: 'Wertet einen Leckbericht (FastMM4/5-Log, Meldung von ReportMemoryLeaksOnShutdown) oder einen ' +
      'Absturzbericht (madExcept, EurekaLog, JclDebug, Meldung einer Exception) aus: Lecks je Erzeugungsstelle bzw. ' +
      'Exception, Absturzadresse, betroffene Stelle im Projekt und Aufrufstapel. Stapelzeilen ohne ' +
      'Debug-Informationen löst es mit map, exe oder project über die Map-Datei auf.';
     En: 'Analyzes a leak report (FastMM4/5 log, ReportMemoryLeaksOnShutdown message) or a crash report ' +
      '(madExcept, EurekaLog, JclDebug, exception message): leaks per creation site or the exception, crash ' +
      'address, affected location in the project and call stack. With map, exe or project it resolves stack lines ' +
      'without debug information through the map file.'),
    (De: 'Text des Berichts'; En: 'Text of the report'),
    (De: 'Berichtsdatei im Arbeitsordner statt text'; En: 'Report file in the working folder instead of text'),
    (De: 'Map-Datei %s fehlt (Linker-Option „Map-Datei: Detailliert“)';
     En: 'Map file %s is missing (linker option "Map file: Detailed")'),
    (De: 'Projekt %s ist nicht lesbar'; En: 'Project %s cannot be read'),
    (De: '"base" ist keine Hexzahl: %s'; En: '"base" is not a hex number: %s'),
    (De: 'text oder file angeben'; En: 'Pass text or file'));

/// <summary>Erste Bytes einer Datei; nil, wenn sie fehlt oder nicht lesbar ist.</summary>
function ReadHead(const AFileName: string): TBytes;
var
  mStream: TFileStream;
begin
  Result := nil;
  if not FileExists(AFileName) then
  begin
    Exit;
  end;
  try
    mStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Result, mStream.Size);
      if mStream.Size > cImageHeadBytes then
      begin
        SetLength(Result, cImageHeadBytes);
      end;
      if Length(Result) > 0 then
      begin
        mStream.ReadBuffer(Result[0], Length(Result));
      end;
    finally
      mStream.Free;
    end;
  except
    on EStreamError do
    begin
      Result := nil;
    end;
  end;
end;

/// <summary>EXE aus exe bzw. project; '' ohne beide.</summary>
function ExecutableOf(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mProject: string;
  mInfo: TProjectInfo;
begin
  Result := TMcpArgs.OptionalString(AArguments, 'exe');
  if Result <> '' then
  begin
    Exit(AContext.Guard.Resolve(Result));
  end;
  mProject := TMcpArgs.OptionalString(AArguments, 'project');
  if mProject = '' then
  begin
    Exit;
  end;
  mProject := AContext.Guard.Resolve(mProject);
  if not LoadProject(mProject, '', '', mInfo) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpReportText.ProjectUnreadable].Fmt([mProject]));
  end;
  Result := TMcpTestTools.ExecutableOf(mInfo);
end;

function BaseOf(const AArguments: TJSONObject): UInt64;
var
  mText: string;
begin
  Result := 0;
  mText := Trim(TMcpArgs.OptionalString(AArguments, 'base'));
  if (mText <> '') and not TCrashReports.TryParseHex(mText, Result) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpReportText.BadBase].Fmt([mText]));
  end;
end;

/// <summary>Map und EXE aus den Argumenten; ASymbols.Map = nil, wenn keine Map da ist. Der Aufrufer gibt
/// ASymbols.Map frei.</summary>
procedure LoadSymbols(const AContext: TMcpToolContext; const AArguments: TJSONObject; out ASymbols: TMcpSymbols);
var
  mMapName, mExe: string;
  mImage: TPeImage;
begin
  ASymbols := Default(TMcpSymbols);
  ASymbols.Base := BaseOf(AArguments);
  mExe := ExecutableOf(AContext, AArguments);
  mMapName := TMcpArgs.OptionalString(AArguments, 'map');
  if mMapName <> '' then
  begin
    mMapName := AContext.Guard.Resolve(mMapName);
  end
  else if mExe <> '' then
  begin
    mMapName := ChangeFileExt(mExe, '.map');
  end;
  if mMapName = '' then
  begin
    Exit;
  end;
  if not FileExists(mMapName) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpReportText.MapMissing].Fmt([mMapName]));
  end;
  ASymbols.Map := TMapFile.Create(TFile.ReadAllText(mMapName, TEncoding.UTF8));
  ASymbols.MapName := mMapName;
  mImage := TPeImage.Read(ReadHead(mExe));
  ASymbols.Match := TMapImageCheck.Compare(ASymbols.Map, mImage);
  if mImage.Valid then
  begin
    ASymbols.Module := ExtractFileName(mExe);
  end;
  if (ASymbols.Base = 0) and mImage.Valid then
  begin
    ASymbols.Base := mImage.ImageBase;
  end;
end;

/// <summary>Datei einer Unit im Arbeitsordner über den Symbolindex (lädt sie über die Suchpfade nach); '' für
/// Bibliotheken und Unbekanntes.</summary>
function UnitFileOf(const AContext: TMcpToolContext): TMcpUnitFileFunc;
var
  mIndex: ISymbolIndex;
  mGroup: TShellWorkspaceGroup;
  mRoot: string;
begin
  mIndex := AContext.Index;
  mGroup := AContext.Group;
  mRoot := AContext.Root;
  Result :=
    function(const AUnitName, AFileName: string): string
    var
      mUnit: TUnitIndex;
    begin
      Result := '';
      mUnit := Default(TUnitIndex);
      if (AUnitName = '') or (mIndex = nil) then
      begin
        Exit;
      end;
      if not mIndex.FindUnit(AUnitName, mUnit) and (mGroup <> nil) and mGroup.EnsureUnit(AUnitName) then
      begin
        mIndex.FindUnit(AUnitName, mUnit);
      end;
      if TMcpPathGuard.IsInside(mRoot, mUnit.FileName) then
      begin
        Result := mUnit.FileName;
      end;
    end;
end;

function ToolResolveAddress(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mAddresses: TArray<TMcpAddress>;
  mSymbols: TMcpSymbols;
begin
  mAddresses := TMcpReportTools.ParseAddresses(TMcpArgs.RequiredString(AArguments, 'addresses'));
  LoadSymbols(AContext, AArguments, mSymbols);
  try
    Result := TMcpReportTools.ResolveAddresses(mAddresses, mSymbols, UnitFileOf(AContext));
  finally
    mSymbols.Map.Free;
  end;
end;

function ReportTextOf(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFile: string;
begin
  Result := TMcpArgs.OptionalString(AArguments, 'text');
  mFile := TMcpArgs.OptionalString(AArguments, 'file');
  // Berichte sind je nach Werkzeug UTF-8 oder ANSI: lesen wie Quelltext (BOM, sonst UTF-8 oder Codepage).
  if (Result = '') and (mFile <> '') and not ReadSourceText(AContext.Guard.Resolve(mFile), Result) then
  begin
    Result := '';
  end;
  if Trim(Result) = '' then
  begin
    raise EMcpToolError.Create(cTexts[TMcpReportText.TextOrFile].Text);
  end;
end;

function ToolAnalyzeReport(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mText: string;
  mSymbols: TMcpSymbols;
begin
  mText := ReportTextOf(AContext, AArguments);
  LoadSymbols(AContext, AArguments, mSymbols);
  try
    Result := TMcpReportTools.AnalyzeReport(mText, mSymbols, UnitFileOf(AContext));
  finally
    mSymbols.Map.Free;
  end;
end;

/// <summary>Gemeinsame Argumente für Map, EXE, Projekt und Basis.</summary>
function SymbolProperties: string;
begin
  Result := SchemaWith(
    '"map":{"type":"string","description":%s},' +
    '"exe":{"type":"string","description":%s},' +
    '"project":{"type":"string","description":%s},' +
    '"base":{"type":"string","description":%s}',
    [cTexts[TMcpReportText.MapArgument].Text,
    cTexts[TMcpReportText.ExeArgument].Text,
    cTexts[TMcpReportText.ProjectArgument].Text,
    cTexts[TMcpReportText.BaseArgument].Text]);
end;

procedure RegisterReportTools(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('resolve_address', cTexts[TMcpReportText.ResolveTool].Text,
    SchemaWith('{"type":"object","properties":{"addresses":{"type":"string","description":%s},',
      [cTexts[TMcpReportText.ResolveAddresses].Text]) + SymbolProperties + '},"required":["addresses"]}',
    ContextTool(AContext, ToolResolveAddress));
  AContext.Server.AddTool('analyze_report', cTexts[TMcpReportText.AnalyzeTool].Text,
    SchemaWith('{"type":"object","properties":{"text":{"type":"string","description":%s},' +
      '"file":{"type":"string","description":%s},',
      [cTexts[TMcpReportText.AnalyzeText].Text, cTexts[TMcpReportText.AnalyzeFile].Text]) + SymbolProperties +
      '}}',
    ContextTool(AContext, ToolAnalyzeReport));
end;

initialization
  TAtlasTextTables.Add('Shell.Mcp.ReportTools', cTexts);

end.
