unit Shell.Composition.Instructions;

// Internals-Rolle Shell: Anweisungsdateien für KI-Assistenten (#2615). Befehl atlas.server.assistantInstructions
// für das Plugin (Stand prüfen bzw. schreiben, Arbeitsbereich zur URI, sonst der einzige) und das Lesen und
// atomare Schreiben auf der Platte, das auch die Kommandozeile nutzt. Logik in Atlas.Common.Lsp.Instructions.

interface

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.Instructions,
  Shell.Composition.Workspaces;

type
  TShellInstructions = class
  public
    /// <summary>Meldet den Befehl an; ins Log nur Zahlen, keine Pfade.</summary>
    class procedure Attach(ACommands: TLspCommands; AWorkspaces: TShellWorkspaceRegistry;
      const ALogger: ILogger); static;
    /// <summary>Stand bzw. Schreiben der Anweisungsdateien unter ARoot mit den eingebauten Regeln.</summary>
    class function Run(const ARoot: string; const ASettings: TServerSettings;
      AWrite: Boolean): TArray<TInstructionsFile>; static;
  end;

implementation

uses
  System.JSON,
  System.IOUtils,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Adapters.DiskFileSystem,
  Atlas.Common.Rules.Builtin,
  Shell.Workspace;

function ReadInstructions(const AFileName: string; out ABytes: TBytes): Boolean;
begin
  ABytes := nil;
  Result := FileExists(AFileName);
  if Result then
  begin
    ABytes := TFile.ReadAllBytes(AFileName);
  end;
end;

function WriteInstructions(const AFileName: string; const ABytes: TBytes; out AError: string): Boolean;
var
  mDisk: IIndexFileSystem;
begin
  // Atomar wie die Baseline: Ein Assistent, der die Datei gerade liest, sieht nie einen halben Stand.
  mDisk := TDiskIndexFileSystem.Create;
  Result := mDisk.WriteBytes(AFileName, ABytes, AError);
end;

/// <summary>Ordner der atlas.json und Einstellungen des Arbeitsbereichs zu AUri (sonst des einzigen); False ohne.
/// </summary>
function TryWorkspace(AWorkspaces: TShellWorkspaceRegistry; const AUri: string; out ARoot: string;
  out ASettings: TServerSettings): Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  ARoot := '';
  ASettings := Default(TServerSettings);
  System.TMonitor.Enter(AWorkspaces.Lock);
  try
    mWorkspace := AWorkspaces.Pick(TDocumentUris.ToPath(AUri));
    Result := mWorkspace <> nil;
    if Result then
    begin
      ARoot := mWorkspace.Configuration.ConfigRoot;
      ASettings := mWorkspace.Configuration.Settings;
    end;
  finally
    System.TMonitor.Exit(AWorkspaces.Lock);
  end;
end;

{ TShellInstructions }

class function TShellInstructions.Run(const ARoot: string; const ASettings: TServerSettings;
  AWrite: Boolean): TArray<TInstructionsFile>;
var
  mInstructions: TLspInstructions;
begin
  mInstructions := TLspInstructions.Create(ReadInstructions, WriteInstructions);
  try
    Result := mInstructions.Run(ARoot, ASettings, BuiltinRules, AWrite);
  finally
    mInstructions.Free;
  end;
end;

class procedure TShellInstructions.Attach(ACommands: TLspCommands; AWorkspaces: TShellWorkspaceRegistry;
  const ALogger: ILogger);
var
  mLogger: ILogger;
begin
  mLogger := ALogger;
  ACommands.Register(TLspInstructions.cCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      mRoot: string;
      mSettings: TServerSettings;
      mFiles: TArray<TInstructionsFile>;
    begin
      if not TryWorkspace(AWorkspaces, TLspInstructions.UriOf(AArguments), mRoot, mSettings) then
      begin
        Exit(TLspInstructions.ToJson(nil));
      end;
      mFiles := Run(mRoot, mSettings, TLspInstructions.WriteRequested(AArguments));
      mLogger.Info(Format('Instructions for AI assistants: %d files, %d stale',
        [Length(mFiles), TLspInstructions.StaleCount(mFiles)]));
      Result := TLspInstructions.ToJson(mFiles);
    end);
end;

end.
