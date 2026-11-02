unit Shell.Mcp.Context;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), gemeinsamer Kontext der Werkzeuge (TMcpToolContext) und
// Hilfen zum Lesen von Quelltext und Projekten.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.IndexTools,
  Atlas.Common.Mcp.CodeTools,
  Atlas.Common.Mcp.Paths,
  Atlas.Common.Mcp.EditTools,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Architecture.Report,
  Atlas.Common.Architecture.SymbolPath,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Hotspots.Service,
  Atlas.Common.Lsp.Impact,
  Shell.WorkspaceGroup;

type
  /// <summary>Text der Architekturübersicht (#1118) zu Abschnitt bzw. Unit ('' = Abschnitt); mit ACompareWith
  /// (absoluter Pfad eines gespeicherten Stands, #1121) der Text des Vergleichs. AResolution: Feinheit γ für
  /// diesen Aufruf (#1366), 0 = architecture.grouping.resolution.</summary>
  TMcpArchitectureFunc = reference to function(ASection: TArchitectureSection;
    const AUnit, ACompareWith: string; AResolution: Double): string;
  /// <summary>Antwort von find_path (#1117) als Text.</summary>
  TMcpFindPathFunc = reference to function(const ARequest: TSymbolPathRequest): string;

  /// <summary>Was die Werkzeuge des MCP-Modus brauchen; ToolNames füllt nur Server (die Werkzeuge greifen erst
  /// beim Aufruf auf die Dienste zu).</summary>
  TMcpToolContext = record
    Server: TMcpServer;
    Tools: TMcpIndexTools;
    Code: TMcpCodeTools;
    Group: TShellWorkspaceGroup;
    Root: string;
    Guard: TMcpPathGuard;
    Edit: TMcpEditTools;
    Architecture: TMcpArchitectureFunc;
    FindPath: TMcpFindPathFunc;
    CheckSource: TCheckSourceFunc;
    CheckProject: TCheckProjectFunc;
    Index: ISymbolIndex;
    Hotspots: THotspotService;
    ImpactOptionsFor: TImpactOptionsProvider;
    /// <summary>Start des MCP-Prozesses für get_server_status.</summary>
    Started: TDateTime;
  end;

  /// <summary>Werkzeug mit seinem Kontext; ContextTool macht daraus den Handler für TMcpServer.AddTool.</summary>
  TMcpContextTool = function(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;

/// <summary>Handler, der ATool mit einer Kopie von AContext aufruft.</summary>
function ContextTool(const AContext: TMcpToolContext; ATool: TMcpContextTool): TMcpToolHandler;
/// <summary>dryRun-Argument; Vorgabe true (#61).</summary>
function DryRunOf(const AArguments: TJSONObject): Boolean;
// Als gewöhnliche Funktion, weil sie als TReadText-Rückruf an mehrere Werkzeuge geht.
function ReadSourceText(const AFileName: string; out AText: string): Boolean;
/// <summary>Projektdatei ohne Ausnahme auswerten; False, wenn sie nicht lesbar ist.</summary>
function LoadProject(const AFileName, AConfiguration, APlatform: string; out AInfo: TProjectInfo): Boolean;
/// <summary>DUnitX-Testprojekt: Die Hauptdatei verwendet DUnitX.TestFramework (#69).</summary>
function IsTestProject(const AFileName: string): Boolean;
/// <summary>Projektdateien unter ARoot ohne Sicherungsordner der IDE.</summary>
function ProjectFilesUnder(const ARoot: string): TArray<string>;
/// <summary>AGroup.Main.State.CheckSource als Methodenreferenz. Als anonyme Methode, weil Free Pascal (Linux-Bau) an der
/// Umwandlung einer Methode eines anderen Objekts intern abbricht; in eigener Routine, weil eine anonyme Methode in
/// einer Variablen, die die anderen anonymen Methoden derselben Routine einfangen, ihren eigenen Rahmen festhält
/// (Leck unter Delphi). Main erst beim Aufruf: Tests registrieren die Werkzeuge ohne Gruppe.</summary>
function CheckSourceOf(AGroup: TShellWorkspaceGroup): TCheckSourceFunc;
/// <summary>AGroup.RuleProject als Methodenreferenz (#1112), aus denselben Gründen wie CheckSourceOf in eigener
/// Routine.</summary>
function CheckProjectOf(AGroup: TShellWorkspaceGroup): TCheckProjectFunc;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  Atlas.Common.Projects.DprojReader,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX,
  Shell.Bootstrap;

/// <summary>dryRun-Argument; Vorgabe true (#61).</summary>
function DryRunOf(const AArguments: TJSONObject): Boolean;
begin
  if (AArguments = nil) or not AArguments.TryGetValue<Boolean>('dryRun', Result) then
  begin
    Result := True;
  end;
end;

// Als gewöhnliche Funktion, weil sie als TReadText-Rückruf an mehrere Werkzeuge geht.
function ReadSourceText(const AFileName: string; out AText: string): Boolean;
begin
  Result := TShellBootstrap.ReadSourceText(AFileName, AText);
end;

/// <summary>Projektdatei ohne Ausnahme auswerten; False, wenn sie nicht lesbar ist.</summary>
function LoadProject(const AFileName, AConfiguration, APlatform: string; out AInfo: TProjectInfo): Boolean;
var
  Options: TDprojOptions;
begin
  Options := Default(TDprojOptions);
  Options.Config := AConfiguration;
  Options.Platform := APlatform;
  Options.FileExists :=
    function(APath: string): Boolean
    begin
      Result := FileExists(APath);
    end;
  try
    AInfo := TDprojReader.Load(AFileName, Options);
    Result := True;
  except
    on Exception do
    begin
      AInfo := Default(TProjectInfo);
      Result := False;
    end;
  end;
end;

/// <summary>DUnitX-Testprojekt: Die Hauptdatei verwendet DUnitX.TestFramework (#69).</summary>
function IsTestProject(const AFileName: string): Boolean;
var
  Info: TProjectInfo;
  Text: string;
begin
  Result := LoadProject(AFileName, '', '', Info) and (Info.MainSource <> '') and
    ReadSourceText(Info.MainSource, Text) and TDUnitXSource.UsesDUnitX(TTextLines.SplitLines(Text));
end;

/// <summary>Projektdateien unter ARoot ohne Sicherungsordner der IDE.</summary>
function ProjectFilesUnder(const ARoot: string): TArray<string>;
var
  FileName: string;
begin
  Result := nil;
  if (ARoot = '') or not TDirectory.Exists(ARoot) then
  begin
    Exit;
  end;
  for FileName in TDirectory.GetFiles(ARoot, '*.dproj', TSearchOption.soAllDirectories) do
  begin
    if not ContainsText(FileName, '\__history\') and not ContainsText(FileName, '\__recovery\') then
    begin
      Result := Result + [FileName];
    end;
  end;
end;

/// <summary>AGroup.Main.State.CheckSource als Methodenreferenz. Als anonyme Methode, weil Free Pascal (Linux-Bau) an der
/// Umwandlung einer Methode eines anderen Objekts intern abbricht; in eigener Routine, weil eine anonyme Methode in
/// einer Variablen, die die anderen anonymen Methoden derselben Routine einfangen, ihren eigenen Rahmen festhält
/// (Leck unter Delphi). Main erst beim Aufruf: Tests registrieren die Werkzeuge ohne Gruppe.</summary>
function CheckSourceOf(AGroup: TShellWorkspaceGroup): TCheckSourceFunc;
begin
  Result :=
    function(const AFileName: string): TCheckSource
    begin
      Result := AGroup.Main.State.CheckSource(AFileName);
    end;
end;

/// <summary>AGroup.RuleProject als Methodenreferenz (#1112), aus denselben Gründen wie CheckSourceOf in eigener
/// Routine.</summary>
function CheckProjectOf(AGroup: TShellWorkspaceGroup): TCheckProjectFunc;
begin
  Result :=
    function(const AFileName: string): TCheckProject
    begin
      Result := AGroup.RuleProject(AFileName);
    end;
end;

function ContextTool(const AContext: TMcpToolContext; ATool: TMcpContextTool): TMcpToolHandler;
var
  mContext: TMcpToolContext;
begin
  mContext := AContext;
  Result :=
    function(const AArguments: TJSONObject): string
    begin
      Result := ATool(mContext, AArguments);
    end;
end;

end.
