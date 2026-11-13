unit Shell.Composition.CommandArea;

// Teilwurzel Befehle der Komposition: workspace/executeCommand mit Status und Fehlerbericht, Befehlen am Server, am
// Editor und der Unit-Suche. Sie meldet auch die Befehle der übrigen Teilwurzeln an, in der Reihenfolge, in der der
// Client sie sieht. Die Komposition reicht nur, was erst nach ihr entsteht oder nur sie kennt (Compilerläufe,
// Projektwahl, Absturzfälle, Protokoll), in den Diensten der Teile herein.

interface

uses
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Lsp.Commands,
  Shell.Workspace,
  Shell.Composition.Contract,
  Shell.Composition.Core,
  Shell.Composition.Editing,
  Shell.Composition.CodeArea,
  Shell.Composition.AnalysisArea,
  Shell.Composition.Status.Contract,
  Shell.Composition.Status,
  Shell.Composition.ServerCommands,
  Shell.Composition.EditorCommands,
  Shell.Composition.UnitSearch;

type
  /// <summary>Was die Teilwurzel Befehle von der Komposition braucht. In Status, Server, Editor und UnitSearch
  /// füllt die Komposition nur, was nicht aus Kern und Teilwurzeln kommt; den Rest setzt die Teilwurzel.</summary>
  TShellCommandAreaServices = record
    Logger: ILogger;
    Dispatcher: TJsonRpcDispatcher;
    Status: TShellStatusServices;
    Server: TShellServerCommandServices;
    Editor: TShellEditorCommandServices;
    UnitSearch: TShellUnitSearchServices;
  end;

  /// <summary>Hält die Befehle und ihre Teile; meldet alle Befehle am Verteiler an.</summary>
  TShellCommandArea = class
  private
    FCore: TShellCore;
    FCode: TShellCodeArea;
    FAnalysis: TShellAnalysisArea;
    FEditing: TShellEditing;
    FServices: TShellCommandAreaServices;
    FCommands: TLspCommands;
    /// <summary>Status (#28, #1356), Prozesse (#62), Fehlerbericht (#108) und Diagnosepaket (#1356).</summary>
    FStatusReports: TShellStatusReports;
    /// <summary>Befehle am Server selbst: Status, Einstellungen, Bau, Index, Build und Projekt wählen.</summary>
    FServerCommands: TShellServerCommands;
    /// <summary>Befehle des Plugins am Editor (#698, #712, #689, #660, #768, #473).</summary>
    FEditorCommands: TShellEditorCommands;
    /// <summary>Daten des Fensters „Units suchen“ im Plugin (#777).</summary>
    FUnitSearch: TShellUnitSearch;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function ProjectFiles: TArray<string>;
    function Namespaces: TArray<string>;
    procedure VisitWorkspaces(const AVisit: TShellWorkspacesProc);
    /// <summary>Arbeitsbereich von AUri, mit '' alle.</summary>
    function CommandWorkspaces(const AUri: string): TArray<TShellWorkspace>;
    function StatusServices: TShellStatusServices;
    function ServerServices: TShellServerCommandServices;
    function EditorServices: TShellEditorCommandServices;
    function UnitSearchServices: TShellUnitSearchServices;
    /// <summary>Eigenschaftsregeln anwenden in Formularen.</summary>
    procedure RegisterDfmPropertyRules;
    /// <summary>Leckprüfung einrichten (#1880) und Kandidaten zu einem Leckbericht (#1875).</summary>
    procedure RegisterLeakSetup;
    /// <summary>Befehl atlas.server.testCases (#1879).</summary>
    procedure RegisterTestCases;
    /// <summary>Befehle der Schnellbefehle: Einordnen, Erzeugen-Menü, Testunit, Unit-Suche.</summary>
    procedure RegisterSlashCommands;
  public
    /// <summary>Legt die Teile an und meldet alle Befehle an AServices.Dispatcher an; Kern, Teilwurzeln und Editor
    /// müssen bestehen.</summary>
    constructor Create(ACore: TShellCore; ACode: TShellCodeArea; AAnalysis: TShellAnalysisArea;
      AEditing: TShellEditing; const AServices: TShellCommandAreaServices);
    /// <summary>Gibt Befehle am Editor, am Server, Status, Unit-Suche und zuletzt die Befehlsliste frei.</summary>
    destructor Destroy; override;
    property Commands: TLspCommands read FCommands;
    property StatusReports: TShellStatusReports read FStatusReports;
    property ServerCommands: TShellServerCommands read FServerCommands;
    property EditorCommands: TShellEditorCommands read FEditorCommands;
    property UnitSearch: TShellUnitSearch read FUnitSearch;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.SmartIndent,
  Atlas.Common.Editing.LearnedSuggestions,
  Atlas.Common.Editing.MethodOrder,
  Atlas.Common.Index.Scheduler,
  Atlas.Common.Lsp.ServerActivity,
  Atlas.Common.Lsp.TestCases,
  Shell.Composition.DfmPropertyRules,
  Shell.Composition.LeakSetup,
  Shell.Composition.LeakCandidates;

/// <summary>Ausführlicher Status von AReports als Funktion für die Aktivität des Servers.</summary>
function DetailsOf(AReports: TShellStatusReports): TServerDetailsFunc;
begin
  Result :=
    function: TServerDetails
    begin
      Result := AReports.FileDetails;
    end;
end;

constructor TShellCommandArea.Create(ACore: TShellCore; ACode: TShellCodeArea; AAnalysis: TShellAnalysisArea;
  AEditing: TShellEditing; const AServices: TShellCommandAreaServices);
begin
  inherited Create;
  FCore := ACore;
  FCode := ACode;
  FAnalysis := AAnalysis;
  FEditing := AEditing;
  FServices := AServices;
  FCommands := TLspCommands.Create;
  FStatusReports := TShellStatusReports.Create(StatusServices);
  // Ausführlicher Status in der Statusdatei (#1901); TShellParts meldet ihn beim Beenden zuerst ab.
  TServerActivity.Shared.SetDetails(DetailsOf(FStatusReports));
  FServerCommands := TShellServerCommands.Create(ServerServices);
  FServerCommands.RegisterConvertCommand(FCommands);
  RegisterDfmPropertyRules;
  RegisterLeakSetup;
  RegisterTestCases;
  FCode.Refactorings.Register(FCommands);
  FAnalysis.Analysis.RegisterReportCommands(FCommands);
  FAnalysis.Overviews.RegisterReportCommands(FCommands);
  FAnalysis.Overviews.RegisterUnitCommands(FCommands);
  FEditorCommands := TShellEditorCommands.Create(EditorServices);
  FEditorCommands.RegisterMarkCommands(FCommands);
  FAnalysis.Baselines.RegisterCommands(FCommands);
  RegisterSlashCommands;
  FEditorCommands.RegisterTextCommands(FCommands);
  // Reine Lesebefehle laufen nebenläufig (#874), auch der Fehlerbericht und das Diagnosepaket.
  FServerCommands.RegisterReadCommands(FCommands);
  FStatusReports.RegisterCommands(FCommands);
  FServerCommands.RegisterActionCommands(FCommands);
  FCommands.Attach(FServices.Dispatcher);
end;

destructor TShellCommandArea.Destroy;
begin
  TServerActivity.Shared.SetDetails(nil);
  FreeAndNil(FEditorCommands);
  FreeAndNil(FServerCommands);
  FreeAndNil(FStatusReports);
  FreeAndNil(FUnitSearch);
  FreeAndNil(FCommands);
  inherited;
end;

function TShellCommandArea.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := FCore.ReadText(AFileName, AText);
end;

function TShellCommandArea.ProjectFiles: TArray<string>;
begin
  Result := FCore.ProjectFiles;
end;

function TShellCommandArea.Namespaces: TArray<string>;
begin
  Result := FCode.Navigation.Namespaces;
end;

procedure TShellCommandArea.VisitWorkspaces(const AVisit: TShellWorkspacesProc);
begin
  FCore.Workspaces.Visit(AVisit);
end;

function TShellCommandArea.CommandWorkspaces(const AUri: string): TArray<TShellWorkspace>;
var
  mWorkspace: TShellWorkspace;
begin
  Result := nil;
  System.TMonitor.Enter(FCore.Workspaces.Lock);
  try
    if AUri = '' then
    begin
      Result := FCore.Workspaces.Items.ToArray;
    end
    else
    begin
      mWorkspace := FCore.Workspaces.WorkspaceOf(TDocumentUris.ToPath(AUri));
      if mWorkspace <> nil then
      begin
        Result := [mWorkspace];
      end;
    end;
  finally
    System.TMonitor.Exit(FCore.Workspaces.Lock);
  end;
end;

function TShellCommandArea.StatusServices: TShellStatusServices;
var
  mCore: TShellCore;
begin
  mCore := FCore;
  Result := FServices.Status;
  Result.Logger := FServices.Logger;
  Result.VisitWorkspaces := VisitWorkspaces;
  Result.EditorSettings :=
    function: string
    begin
      Result := mCore.Settings.EditorSettings;
    end;
  Result.IsSelectedProject :=
    function(AWorkspace: TShellWorkspace): Boolean
    begin
      Result := mCore.Workspaces.IsSelected(AWorkspace);
    end;
  Result.IndexQueue :=
    function: TIndexSchedulerQueue
    begin
      Result := mCore.Folders.Scheduler.Queue;
    end;
end;

function TShellCommandArea.ServerServices: TShellServerCommandServices;
var
  mCore: TShellCore;
  mStatus: TShellStatusReports;
begin
  mCore := FCore;
  mStatus := FStatusReports;
  Result := FServices.Server;
  Result.Logger := FServices.Logger;
  Result.Status :=
    function(AAnonymize: Boolean): TJSONObject
    begin
      Result := mStatus.StatusJson(AAnonymize);
    end;
  Result.GlobalSettingsFile :=
    function: string
    begin
      Result := mCore.Configuration.GlobalSettingsFile;
    end;
  Result.ProjectSourceFiles := ProjectFiles;
  Result.Workspaces := CommandWorkspaces;
  Result.IsSelectedProject :=
    function(AWorkspace: TShellWorkspace): Boolean
    begin
      Result := mCore.Workspaces.IsSelected(AWorkspace);
    end;
end;

function TShellCommandArea.EditorServices: TShellEditorCommandServices;
var
  mCore: TShellCore;
begin
  mCore := FCore;
  Result := FServices.Editor;
  Result.EnsureUnit := mCore.Folders.EnsureUnitFunc();
  Result.ReadText := ReadText;
  Result.Namespaces := Namespaces;
  Result.HighlightSettingsFor :=
    function(const AUri: string): THighlightSettings
    begin
      Result := mCore.Settings.Highlight(AUri);
    end;
  Result.StringLiteralFor :=
    function(const AUri: string; out AMultiline: Boolean): TStringLiteralSettings
    begin
      Result := mCore.Settings.StringLiteral(AUri, AMultiline);
    end;
  Result.SmartIndentFor :=
    function(const AUri: string; const AEditorOptions: TJSONValue; out AOptions: TSmartIndentOptions): Boolean
    begin
      Result := mCore.FileOptions.SmartIndentFor(AUri, AEditorOptions, AOptions);
    end;
  Result.MethodOrderFor :=
    function(const AUri: string): TMethodOrderOptions
    begin
      Result := mCore.FileOptions.MethodOrderFor(AUri);
    end;
  Result.LearnedOptionsFor :=
    function(const AUri: string; const AEditorOptions: TJSONValue): TLearnedOptions
    begin
      Result := mCore.FileOptions.LearnedOptionsFor(AUri, AEditorOptions);
    end;
end;

function TShellCommandArea.UnitSearchServices: TShellUnitSearchServices;
begin
  Result := FServices.UnitSearch;
  Result.Logger := FServices.Logger;
  Result.VisitWorkspaces := VisitWorkspaces;
  Result.ReadText := ReadText;
end;

procedure TShellCommandArea.RegisterDfmPropertyRules;
var
  mServices: TShellDfmPropertyRulesServices;
begin
  mServices := Default(TShellDfmPropertyRulesServices);
  mServices.Logger := FServices.Logger;
  mServices.Workspaces := FCore.Workspaces;
  mServices.RuleContext := FCore.RuleContext;
  mServices.ReadText := ReadText;
  TShellDfmPropertyRules.Attach(FCommands, mServices);
end;

procedure TShellCommandArea.RegisterLeakSetup;
var
  mServices: TShellLeakSetupServices;
begin
  mServices := Default(TShellLeakSetupServices);
  mServices.Logger := FServices.Logger;
  mServices.Workspaces := FCore.Workspaces;
  mServices.ReadText := ReadText;
  TShellLeakSetup.Attach(FCommands, mServices);
  TShellLeakCandidates.Attach(FCommands, mServices);
end;

procedure TShellCommandArea.RegisterTestCases;
begin
  // Closure: Free Pascal bricht ab, wenn eine Methode einer Klasse aus einer anderen Unit als Referenz geht.
  TLspTestCases.Attach(FCommands,
    function(const AUri: string; out AText: string): Boolean
    begin
      Result := ReadText(TDocumentUris.ToPath(AUri), AText);
    end);
end;

procedure TShellCommandArea.RegisterSlashCommands;
begin
  FAnalysis.Baselines.RegisterClassifyCommand(FCommands);
  FEditing.RegisterCommands(FCommands);
  FCode.TestUnits.RegisterCommand(FCommands);
  FUnitSearch := TShellUnitSearch.Create(UnitSearchServices);
  FUnitSearch.RegisterCommands(FCommands);
end;

end.
