unit Shell.Composition.UnitSearch;

// Internals-Rolle Shell: Daten des Fensters „Units suchen“ im Plugin (#777). Units des Index, Projekte der
// Arbeitsbereiche, Vorfahren, Text, Änderungszeit, Git-Zustand und uses-Umfeld einer Datei. Die Komposition
// reicht Index, Arbeitsbereiche (unter ihrer Sperre), Quelltext, uses-Umfeld und Prozessstarter als Dienste
// herein.

interface

uses
  Atlas.Common.Logging.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Lsp.UnitSearch,
  Shell.Composition.Contract;

type
  TShellUnitSearchReadText = reference to function(const AFileName: string; out AText: string): Boolean;
  TShellUnitSearchProcessFunc = reference to function: ICompilerProcess;

  /// <summary>Was die Unit-Suche von der Komposition braucht.</summary>
  TShellUnitSearchServices = record
    Logger: ILogger;
    Index: ISymbolIndex;
    VisitWorkspaces: TShellVisitWorkspacesProc;
    /// <summary>Geöffnete Dokumente vor der Platte.</summary>
    ReadText: TShellUnitSearchReadText;
    UsesContextFor: TUsesContextProvider;
    /// <summary>Startet git für den Zustand einer Datei.</summary>
    Process: TShellUnitSearchProcessFunc;
  end;

  /// <summary>Unit-Suche des Plugins mit ihren Befehlen.</summary>
  TShellUnitSearch = class
  private
    FServices: TShellUnitSearchServices;
    FUnitSearch: TUnitSearch;
    function Context(out AContext: TUnitSearchContext): Boolean;
    function Projects: TArray<TUnitSearchProject>;
    function AncestorsOf(AType: string): TArray<string>;
    function SourceText(AFileName: string): string;
    function GitState(AFileName: string): string;
    function UsesFor(AUri: string): TUsesContext;
  public
    constructor Create(const AServices: TShellUnitSearchServices);
    destructor Destroy; override;
    /// <summary>Units suchen, Vorschau und uses ergänzen.</summary>
    procedure RegisterCommands(ACommands: TLspCommands);
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Editing.TestUnits,
  Shell.Workspace,
  Shell.VcsChanges;

/// <summary>Gibt es die Datei auf der Platte?</summary>
function FileOnDisk(AFileName: string): Boolean;
begin
  Result := FileExists(AFileName);
end;

/// <summary>Letzte Änderung der Datei; 0, wenn sie fehlt.</summary>
function FileModified(AFileName: string): TDateTime;
begin
  Result := 0;
  if FileExists(AFileName) then
  begin
    Result := TFile.GetLastWriteTime(AFileName);
  end;
end;

constructor TShellUnitSearch.Create(const AServices: TShellUnitSearchServices);
begin
  inherited Create;
  FServices := AServices;
  FUnitSearch := TUnitSearch.Create(Context);
end;

destructor TShellUnitSearch.Destroy;
begin
  FreeAndNil(FUnitSearch);
  inherited Destroy;
end;

procedure TShellUnitSearch.RegisterCommands(ACommands: TLspCommands);
begin
  // Closures: Free Pascal bricht ab, wenn eine Methode einer Klasse aus einer anderen Unit als Referenz geht.
  ACommands.Register(TUnitSearch.UnitsCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FUnitSearch.ExecuteUnits(AArguments);
    end);
  ACommands.Register(TUnitSearch.PreviewCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FUnitSearch.ExecutePreview(AArguments);
    end);
  ACommands.Register(TUnitSearch.AddUsesCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FUnitSearch.ExecuteAddUses(AArguments);
    end);
end;

function TShellUnitSearch.Context(out AContext: TUnitSearchContext): Boolean;
begin
  AContext := Default(TUnitSearchContext);
  AContext.Units := FServices.Index.Units;
  AContext.Projects := Projects;
  AContext.AncestorsOf := AncestorsOf;
  AContext.Exists := FileOnDisk;
  AContext.ReadText := SourceText;
  AContext.Modified := FileModified;
  AContext.GitState := GitState;
  AContext.UsesFor := UsesFor;
  Result := True;
end;

function TShellUnitSearch.Projects: TArray<TUnitSearchProject>;
var
  mResult: TArray<TUnitSearchProject>;
begin
  mResult := nil;
  FServices.VisitWorkspaces(
    procedure(const AWorkspaces: TArray<TShellWorkspace>)
    var
      mWorkspace: TShellWorkspace;
      mInfo: TProjectInfo;
      mProject: TUnitSearchProject;
      mText: string;
    begin
      for mWorkspace in AWorkspaces do
      begin
        mProject := Default(TUnitSearchProject);
        mProject.Files := mWorkspace.State.ProjectFiles;
        if mWorkspace.State.Project(mInfo) then
        begin
          mProject.FileName := mInfo.FileName;
          mProject.Name := ChangeFileExt(ExtractFileName(mInfo.FileName), '');
          mProject.IsTest := (mInfo.MainSource <> '') and FServices.ReadText(mInfo.MainSource, mText) and
            TTestUnits.IsTestProgram(mText);
        end
        else
        begin
          mProject.Name := mWorkspace.Name;
        end;
        mResult := mResult + [mProject];
      end;
    end);
  Result := mResult;
end;

function TShellUnitSearch.AncestorsOf(AType: string): TArray<string>;
var
  mLocation: TSymbolLocation;
begin
  Result := nil;
  for mLocation in FServices.Index.FindSymbols(AType) do
  begin
    if (mLocation.Symbol.Kind = TIndexSymbolKind.ClassType) and (mLocation.Symbol.Container = '') then
    begin
      Result := mLocation.Symbol.Ancestors;
      Exit;
    end;
  end;
end;

function TShellUnitSearch.SourceText(AFileName: string): string;
begin
  if not FServices.ReadText(AFileName, Result) then
  begin
    Result := '';
  end;
end;

function TShellUnitSearch.UsesFor(AUri: string): TUsesContext;
begin
  if not FServices.UsesContextFor(AUri, Result) then
  begin
    Result := Default(TUsesContext);
  end;
end;

function TShellUnitSearch.GitState(AFileName: string): string;
var
  mRequest: TCompilerRequest;
  mOutput: TArray<string>;
  mCode: Integer;
begin
  Result := '';
  if not FileExists(AFileName) then
  begin
    Exit;
  end;
  mRequest := Default(TCompilerRequest);
  mRequest.Executable := TVcsChanges.FindProgram('git.exe');
  mRequest.Arguments := ['status', '--porcelain', '--', ExtractFileName(AFileName)];
  mRequest.WorkingDir := ExtractFileDir(AFileName);
  mOutput := nil;
  try
    mCode := FServices.Process().Run(mRequest,
      procedure(const ALine: string)
      begin
        mOutput := mOutput + [ALine];
      end);
  except
    // Ohne Git: kein Zustand.
    on E: Exception do
    begin
      FServices.Logger.Debug('Git-Zustand nicht ermittelt: ' + E.ClassName);
      Exit;
    end;
  end;
  // Exit-Code 128: kein Repository.
  Result := TUnitSearch.GitState(mOutput, mCode = 0);
end;

end.
