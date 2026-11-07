unit Shell.Composition.IdeArea;

// Teilwurzel IDE der Komposition: Nachrichten aus der IDE (Shell.Composition.Ide), Dateiänderungen von außen
// und Tipp-Pause (Shell.Composition.FileChanges, #492) und die gemerkte Projektwahl über Neustarts (#46).

interface

uses
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.IdeUnits,
  Atlas.Common.Projects.Selection,
  Atlas.Common.Pascal.FormatRoutines,
  Shell.Composition.Compile,
  Shell.Composition.Core,
  Shell.Composition.DiagnosticsArea,
  Shell.Composition.FileChanges,
  Shell.Composition.Ide;

type
  /// <summary>Teilwurzel Diagnosen; nil, sobald sie beim Beenden freigegeben ist.</summary>
  TShellIdeDiagnosticsFunc = reference to function: TShellDiagnosticsArea;
  /// <summary>Compile-Host; nil, sobald er beim Beenden freigegeben ist.</summary>
  TShellIdeCompileFunc = reference to function: TShellCompileHost;

  /// <summary>Was die Teilwurzel IDE von der Komposition braucht.</summary>
  TShellIdeAreaServices = record
    Logger: ILogger;
    Transport: IJsonRpcTransport;
    Dispatcher: TJsonRpcDispatcher;
    Diagnostics: TShellIdeDiagnosticsFunc;
    Compile: TShellIdeCompileFunc;
    /// <summary>Ersatz-Units der IDE und gemeinsamer Index (Teilwurzel Index).</summary>
    IdeUnits: TIdeUnits;
    Index: ISymbolIndex;
  end;

  /// <summary>Hält Nachrichten aus der IDE, Dateiänderungen und die Projektwahl.</summary>
  TShellIdeArea = class
  private
    FCore: TShellCore;
    FServices: TShellIdeAreaServices;
    FFileChanges: TShellFileChanges;
    FIde: TShellIde;
    /// <summary>Gemerkte Projektwahl über Neustarts (#46): selectBuild je Projekt, selectProject je Ordner.</summary>
    FSelection: TProjectSelection;
    function FileChangesServices: TShellFileChangesServices;
    function IdeServices: TShellIdeServices;
    procedure RefreshLater;
    procedure Typed;
    procedure Affected(const AFiles: TArray<string>);
  public
    /// <summary>Legt Dateiänderungen, IDE und Projektwahl an und meldet beide am Verteiler an.</summary>
    constructor Create(ACore: TShellCore; const AServices: TShellIdeAreaServices);
    /// <summary>Gibt Dateiänderungen, IDE und Projektwahl in dieser Reihenfolge frei.</summary>
    destructor Destroy; override;
    /// <summary>Formatfunktionen für format-args: Vorgaben, "formatMethods" aus den Einstellungen und die
    /// des IDE-Projekts der Datei.</summary>
    function FormatRoutinesFor(const AUri: string): TArray<TFormatRoutine>;
    property FileChanges: TShellFileChanges read FFileChanges;
    property Ide: TShellIde read FIde;
    property Selection: TProjectSelection read FSelection;
  end;

const
  /// <summary>Längste Pause der Projektprüfung für einen Compile, falls sein Ende nie ankommt (#1247).</summary>
  cCompilePauseLimitMs = 10 * 60 * 1000;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Messages,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Lsp.WorkspaceCheck,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Lsp.IdeProject,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.FormatArgs,
  Shell.Workspace;

constructor TShellIdeArea.Create(ACore: TShellCore; const AServices: TShellIdeAreaServices);
begin
  inherited Create;
  FCore := ACore;
  FServices := AServices;
  FFileChanges := TShellFileChanges.Create(FileChangesServices);
  FFileChanges.Attach(FServices.Dispatcher);
  FIde := TShellIde.Create(IdeServices);
  FIde.Attach(FServices.Dispatcher);
  // Projektwahl je Benutzer über Neustarts (#46).
  FSelection := TProjectSelection.Create(TPath.Combine(TIndexCacheDirectory.DefaultRoot, 'projektauswahl.json'));
end;

destructor TShellIdeArea.Destroy;
begin
  FreeAndNil(FFileChanges);
  FreeAndNil(FIde);
  FreeAndNil(FSelection);
  FServices := Default(TShellIdeAreaServices);
  inherited;
end;

function TShellIdeArea.FormatRoutinesFor(const AUri: string): TArray<TFormatRoutine>;
var
  mWorkspace: TShellWorkspace;
  mProject: TProjectInfo;
  mContext: TIdeProjectContext;
  mName: string;
begin
  Result := TFormatRoutines.Defaults;
  for mName in TRuleOptions.Strings(TRuleEngine.RuleOptions(cFormatArgsRuleId, FCore.Settings.SettingsFor(AUri)),
    'formatMethods', nil) do
  begin
    if Trim(mName) <> '' then
    begin
      Result := Result + [TFormatRoutines.Custom(mName, -1)];
    end;
  end;
  mWorkspace := FCore.Workspaces.WorkspaceOf(TDocumentUris.ToPath(AUri));
  if (mWorkspace <> nil) and mWorkspace.State.Project(mProject) and FIde.Project.Find(mProject.FileName, mContext) then
  begin
    Result := Result + mContext.FormatFunctions;
  end;
end;

procedure TShellIdeArea.RefreshLater;
var
  mDiagnostics: TShellDiagnosticsArea;
begin
  mDiagnostics := FServices.Diagnostics();
  if (mDiagnostics <> nil) and (mDiagnostics.Syntax <> nil) then
  begin
    mDiagnostics.Syntax.RefreshLater;
  end;
end;

procedure TShellIdeArea.Typed;
var
  mDiagnostics: TShellDiagnosticsArea;
begin
  mDiagnostics := FServices.Diagnostics();
  if (mDiagnostics <> nil) and (mDiagnostics.Pull <> nil) then
  begin
    mDiagnostics.Pull.Typed;
  end;
end;

procedure TShellIdeArea.Affected(const AFiles: TArray<string>);
var
  mDiagnostics: TShellDiagnosticsArea;
begin
  mDiagnostics := FServices.Diagnostics();
  if (mDiagnostics <> nil) and (mDiagnostics.Pull <> nil) then
  begin
    mDiagnostics.Pull.Check.Affected(AFiles, True);
  end;
end;

function TShellIdeArea.FileChangesServices: TShellFileChangesServices;
begin
  Result := Default(TShellFileChangesServices);
  Result.Logger := FServices.Logger;
  Result.Workspaces := FCore.Workspaces;
  Result.Transport := FServices.Transport;
  Result.Configuration := FCore.Configuration;
  Result.RefreshLater := RefreshLater;
  // Beim Tippen macht die Projektprüfung Platz (#1247).
  Result.Typed := Typed;
  Result.Affected := Affected;
end;

/// <summary>Schickt Benachrichtigungen über ATransport an die IDE.</summary>
function NotifierOf(const ATransport: IJsonRpcTransport): TShellIdeNotifyProc;
begin
  Result :=
    procedure(const AMethod: string; AParams: TJSONObject)
    var
      mMessage: TJSONObject;
    begin
      mMessage := TJsonRpcMessages.Notification(AMethod, AParams);
      try
        ATransport.WriteMessage(mMessage);
      finally
        mMessage.Free;
      end;
    end;
end;

function TShellIdeArea.IdeServices: TShellIdeServices;
var
  mServices: TShellIdeAreaServices;
begin
  mServices := FServices;
  Result := Default(TShellIdeServices);
  Result.Logger := FServices.Logger;
  Result.Workspaces := FCore.Workspaces;
  Result.MessagesReceived :=
    procedure(const AMessages: TArray<TCompilerMessage>)
    begin
      mServices.Diagnostics().Syntax.RefreshFiles(mServices.Compile().Results.Replace(AMessages));
    end;
  Result.Compiling :=
    procedure(ARunning: Boolean)
    begin
      // Die Frist ist ein Sicherheitsnetz für ein verlorenes Ende, keine Steuerung.
      mServices.Diagnostics().Pull.Check.Pause(TLspWorkspaceCheck.cPauseCompile, ARunning, cCompilePauseLimitMs);
    end;
  Result.NamingChanged := RefreshLater;
  Result.TypesChanged := RefreshLater;
  Result.IdeUnits := FServices.IdeUnits;
  Result.Index := FServices.Index;
  Result.Notify := NotifierOf(FServices.Transport);
end;

end.
