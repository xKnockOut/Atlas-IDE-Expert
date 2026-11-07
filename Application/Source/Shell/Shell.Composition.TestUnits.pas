unit Shell.Composition.TestUnits;

// Internals-Rolle Shell: Testunit anlegen und wechseln (#274, #189). Umfeld einer Datei für die Testunits
// (Einstellungen und Wurzel des Ordners, Testprogramm), gemerktes Testprogramm je Wurzel, Code-Aktionen und
// Befehl. Die Komposition reicht Dokumente, Index, Quelltext und die Arbeitsbereiche (unter ihrer Sperre) als
// Dienste herein.

interface

uses
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.TestUnits,
  Shell.Workspace,
  Shell.Composition.Contract;

type
  TShellTestUnitReadText = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>Arbeitsbereich zur Datei; nur unter der Sperre der Arbeitsbereiche aufzurufen.</summary>
  TShellTestUnitPickFunc = reference to function(const AFileName: string): TShellWorkspace;

  /// <summary>Was die Testunits von der Komposition brauchen.</summary>
  TShellTestUnitServices = record
    Logger: ILogger;
    Documents: IDocumentStore;
    Index: ISymbolIndex;
    /// <summary>Geöffnete Dokumente vor der Platte.</summary>
    ReadText: TShellTestUnitReadText;
    VisitWorkspaces: TShellVisitWorkspacesProc;
    PickWorkspace: TShellTestUnitPickFunc;
  end;

  /// <summary>Testunits des Servers: Umfeld je Datei, Code-Aktionen und Befehl.</summary>
  TShellTestUnits = class
  private
    FServices: TShellTestUnitServices;
    FTestUnits: TLspTestUnits;
    /// <summary>Gefundenes Testprogramm je Wurzel mit Zeitpunkt (#274); Sperre ist das Objekt selbst.</summary>
    FTestPrograms: TDictionary<string, TPair<string, UInt64>>;
    function Workspace(const AFileName: string; var AContext: TTestUnitContext;
      out ACandidates: TArray<string>): Boolean;
    function SourceTextOrEmpty(const AFileName: string): string;
    function DocumentOrFileExists(const AFileName: string): Boolean;
    function ProjectUnitFile(const AUnitName: string): string;
    function CachedTestProgram(const ARoot: string; out AProgram: string): Boolean;
    procedure StoreTestProgram(const ARoot, AProgram: string);
    function DprFilesNear(const ARoot: string): TArray<string>;
  public
    constructor Create(const AServices: TShellTestUnitServices);
    destructor Destroy; override;
    /// <summary>Umfeld der Testunits für AUri; False ohne Arbeitsbereich.</summary>
    function ContextFor(const AUri: string; out AContext: TTestUnitContext): Boolean;
    /// <summary>Code-Aktionen der Testunits in Zeile ALine.</summary>
    function Actions(const AUri: string; ALine: Integer): TArray<TJSONObject>;
    /// <summary>Befehl atlas.server.testUnit.</summary>
    procedure RegisterCommand(ACommands: TLspCommands);
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Editing.TestUnits,
  Atlas.Text.LogMarks;

const
  /// <summary>Testprogramm höchstens so lange merken; ein neu angelegtes wird danach gefunden.</summary>
  cCacheMs = 10000;

constructor TShellTestUnits.Create(const AServices: TShellTestUnitServices);
begin
  inherited Create;
  FServices := AServices;
  FTestPrograms := TDictionary<string, TPair<string, UInt64>>.Create;
  FTestUnits := TLspTestUnits.Create(FServices.Documents, ContextFor);
end;

destructor TShellTestUnits.Destroy;
begin
  FreeAndNil(FTestUnits);
  FreeAndNil(FTestPrograms);
  inherited Destroy;
end;

function TShellTestUnits.Actions(const AUri: string; ALine: Integer): TArray<TJSONObject>;
begin
  Result := FTestUnits.Actions(AUri, ALine);
end;

procedure TShellTestUnits.RegisterCommand(ACommands: TLspCommands);
begin
  // Closure: Free Pascal bricht ab, wenn eine Methode einer Klasse aus einer anderen Unit als Referenz geht.
  // Nebenläufig: derselbe Weg wie die Code-Aktionen (Diagnose 06.11.2026: bis 9 s in der Schlange).
  ACommands.RegisterConcurrent(TLspTestUnits.cCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FTestUnits.Execute(AArguments);
    end);
end;

function TShellTestUnits.ContextFor(const AUri: string; out AContext: TTestUnitContext): Boolean;
var
  mCandidates: TArray<string>;
  mFound: string;
begin
  AContext := Default(TTestUnitContext);
  if not Workspace(TDocumentUris.ToPath(AUri), AContext, mCandidates) then
  begin
    Result := False;
    Exit;
  end;
  AContext.ReadText := SourceTextOrEmpty;
  AContext.Exists := DocumentOrFileExists;
  // Nur der Index: Diese Abfrage läuft bei jeder Code-Aktion und soll nichts nachladen.
  AContext.FindUnit := ProjectUnitFile;
  Result := True;
  if AContext.Settings.Project <> '' then
  begin
    mFound := AContext.Settings.Project;
    if not TPath.IsPathRooted(mFound) then
    begin
      mFound := TPath.Combine(AContext.Root, mFound);
    end;
    AContext.TestProgram := ChangeFileExt(ExpandFileName(mFound), '.dpr');
  end
  else if not CachedTestProgram(AContext.Root, AContext.TestProgram) then
  begin
    AContext.TestProgram := TTestUnits.FindTestProgram(mCandidates + DprFilesNear(AContext.Root), AContext.ReadText);
    StoreTestProgram(AContext.Root, AContext.TestProgram);
  end;
end;

function TShellTestUnits.Workspace(const AFileName: string; var AContext: TTestUnitContext;
  out ACandidates: TArray<string>): Boolean;
var
  mFound: Boolean;
  mContext: TTestUnitContext;
  mCandidates: TArray<string>;
begin
  mFound := False;
  mContext := AContext;
  mCandidates := nil;
  FServices.VisitWorkspaces(
    procedure(const AWorkspaces: TArray<TShellWorkspace>)
    var
      mWorkspace, mOther: TShellWorkspace;
      mInfo: TProjectInfo;
    begin
      mWorkspace := FServices.PickWorkspace(AFileName);
      mFound := mWorkspace <> nil;
      if not mFound then
      begin
        Exit;
      end;
      mContext.Settings := mWorkspace.Configuration.Settings.TestUnits;
      mContext.Root := mWorkspace.Root;
      // Projekte der Gruppe zuerst, dann .dpr in der Wurzel und eine Ebene darunter.
      for mOther in AWorkspaces do
      begin
        if mOther.State.Project(mInfo) and (mInfo.MainSource <> '') then
        begin
          mCandidates := mCandidates + [mInfo.MainSource];
        end;
      end;
    end);
  AContext := mContext;
  ACandidates := mCandidates;
  Result := mFound;
end;

function TShellTestUnits.SourceTextOrEmpty(const AFileName: string): string;
begin
  if not FServices.ReadText(AFileName, Result) then
  begin
    Result := '';
  end;
end;

function TShellTestUnits.DocumentOrFileExists(const AFileName: string): Boolean;
var
  mDocument: ITextDocument;
begin
  Result := FileExists(AFileName) or FServices.Documents.TryGet(TDocumentUris.FromPath(AFileName), mDocument);
end;

function TShellTestUnits.ProjectUnitFile(const AUnitName: string): string;
var
  mUnit: TUnitIndex;
begin
  if FServices.Index.FindUnit(AUnitName, mUnit) and not mUnit.Library_ then
  begin
    Result := mUnit.FileName;
  end
  else
  begin
    Result := '';
  end;
end;

function TShellTestUnits.CachedTestProgram(const ARoot: string; out AProgram: string): Boolean;
var
  mCached: TPair<string, UInt64>;
begin
  System.TMonitor.Enter(FTestPrograms);
  try
    Result := FTestPrograms.TryGetValue(LowerCase(ARoot), mCached) and
      (TThread.GetTickCount64 - mCached.Value < cCacheMs);
  finally
    System.TMonitor.Exit(FTestPrograms);
  end;
  AProgram := '';
  if Result then
  begin
    AProgram := mCached.Key;
  end;
end;

procedure TShellTestUnits.StoreTestProgram(const ARoot, AProgram: string);
begin
  System.TMonitor.Enter(FTestPrograms);
  try
    FTestPrograms.AddOrSetValue(LowerCase(ARoot), TPair<string, UInt64>.Create(AProgram, TThread.GetTickCount64));
  finally
    System.TMonitor.Exit(FTestPrograms);
  end;
end;

function TShellTestUnits.DprFilesNear(const ARoot: string): TArray<string>;
var
  mFolder: string;
begin
  Result := nil;
  try
    Result := TDirectory.GetFiles(ARoot, '*.dpr', TSearchOption.soTopDirectoryOnly);
    for mFolder in TDirectory.GetDirectories(ARoot) do
    begin
      if not ExtractFileName(mFolder).StartsWith('.') then
      begin
        Result := Result + TDirectory.GetFiles(mFolder, '*.dpr', TSearchOption.soTopDirectoryOnly);
      end;
    end;
  except
    on E: EInOutError do
      FServices.Logger.Debug('Testprojekt: Ordner nicht lesbar: ' + TLogMarks.Text(E.Message));
  end;
end;

end.
