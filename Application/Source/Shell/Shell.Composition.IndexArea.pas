unit Shell.Composition.IndexArea;

// Teilwurzel Index der Komposition: gemeinsamer Symbolindex aller Ordner, Uses-Graph (#64), Declared(X) in {$IF}
// (#847), die Ordner des Arbeitsbereichs vom Client und die Ereignisse des Indexaufbaus (Projekt geladen,
// Stufe fertig). Dazu die Ersatz-Units der IDE (atlas/ideMembers) und der Index für Hover, Vervollständigung und
// Parameterhilfe, der sie zum gemeinsamen Index hinzunimmt. Wer außerhalb auf Namespaces oder Bibliotheksordner hört, bekommt sie über die Dienste.

interface

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Diagnostics.Anonymizer,
  Atlas.Common.Lsp.WorkspaceFolders,
  Atlas.Common.Lsp.IdeUnits,
  Shell.Composition.Core,
  Shell.Composition.DiagnosticsArea;

type
  /// <summary>Der Kern; besteht, sobald der Index Ereignisse meldet.</summary>
  TShellIndexCoreFunc = reference to function: TShellCore;
  /// <summary>Teilwurzel Diagnosen.</summary>
  TShellIndexDiagnosticsFunc = reference to function: TShellDiagnosticsArea;
  /// <summary>Anonymisierer des Server-Logs (#647); nil ohne.</summary>
  TShellIndexAnonymizerFunc = reference to function: ILogAnonymizer;
  /// <summary>Namespaces bzw. Bibliotheksordner aller Projekte ohne Doppelte.</summary>
  TShellIndexNamesProc = reference to procedure(const ANames: TArray<string>);
  /// <summary>Reiht AWork in die Nachrichtenschleife ein; False ohne Verbindung.</summary>
  TShellIndexQueueFunc = reference to function(const AWork: TProc): Boolean;

  /// <summary>Was die Teilwurzel Index von der Komposition braucht.</summary>
  TShellIndexAreaServices = record
    Dispatcher: TJsonRpcDispatcher;
    Core: TShellIndexCoreFunc;
    Diagnostics: TShellIndexDiagnosticsFunc;
    Anonymizer: TShellIndexAnonymizerFunc;
    /// <summary>Neues Projekt oder neue Installation: Der Compiler bekommt eine neue Chance (#40).</summary>
    ProjectStarted: TProc;
    NamespacesChanged: TShellIndexNamesProc;
    LibraryRootsChanged: TShellIndexNamesProc;
    Queue: TShellIndexQueueFunc;
    /// <summary>Der Aufbau ist ganz fertig (alle Stufen, kein Projekt mehr offen).</summary>
    IndexFinished: TProc;
  end;

  /// <summary>Hält Index, Uses-Graph und Ordner des Arbeitsbereichs.</summary>
  TShellIndexArea = class
  private
    FServices: TShellIndexAreaServices;
    FIndex: ISymbolIndex;
    /// <summary>Uses-Graph über FIndex für uses-cycle und unused-unit (#64); lebt so lange wie der Index.</summary>
    FUsesGraph: TUsesGraphService;
    FFolders: TLspWorkspaceFolders;
    FIdeUnits: TIdeUnits;
    FEditorIndex: ISymbolIndex;
    procedure FoldersChanged(const AAdded, ARemoved: TArray<TWorkspaceFolder>);
    procedure CollectNamespaces(out ANamespaces, ALibraryRoots: TArray<string>);
    procedure ApplyNamespaces(const ANamespaces: TArray<string>);
    procedure HideIndexedUnits;
    procedure RevalidateLater;
  public
    /// <summary>Legt Index und Uses-Graph an, meldet Declared(X) an und hängt die Ordner an den Verteiler.</summary>
    constructor Create(const AServices: TShellIndexAreaServices);
    /// <summary>Gibt Ordner und Uses-Graph frei und lässt den Index los; Declared(X) meldet die Komposition ab.</summary>
    destructor Destroy; override;
    /// <summary>Ein Ordner hat sein Projekt geladen: Namespaces und Bibliotheksordner neu verteilen.</summary>
    procedure ProjectLoaded;
    /// <summary>Eine Stufe des Indexaufbaus ist fertig (AProjectStage: die Projektstufe).</summary>
    procedure IndexStageDone(AProjectStage: Boolean);
    property Index: ISymbolIndex read FIndex;
    property UsesGraph: TUsesGraphService read FUsesGraph;
    /// <summary>Ersatz-Units der IDE für Units ohne Quelltext.</summary>
    property IdeUnits: TIdeUnits read FIdeUnits;
    /// <summary>Index samt Ersatz-Units für Hover, Vervollständigung und Parameterhilfe.</summary>
    property EditorIndex: ISymbolIndex read FEditorIndex;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Lsp.IdeIndex,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Preprocessor,
  Shell.Workspace;

function DeclaredIn(const AIndex: ISymbolIndex): TDeclaredFunc;
begin
  Result :=
    function(const AName: string): Boolean
    var
      mLocation: TSymbolLocation;
    begin
      for mLocation in AIndex.FindSymbols(AName) do
      begin
        if mLocation.Symbol.Container = '' then
        begin
          Exit(True);
        end;
      end;
      Result := False;
    end;
end;

constructor TShellIndexArea.Create(const AServices: TShellIndexAreaServices);
begin
  inherited Create;
  FServices := AServices;
  FIndex := TSymbolIndex.Create;
  FUsesGraph := TUsesGraphService.Create(FIndex, TUsesGraphOptions.Default);
  // Declared(X) in {$IF} fragt den Index (#847). Die Referenz hält den Index, bis die Komposition den Anbieter
  // abmeldet.
  TPascalPreprocessor.SetDeclaredProvider(DeclaredIn(FIndex));
  FFolders := TLspWorkspaceFolders.Create;
  FFolders.OnChanged := FoldersChanged;
  FFolders.Attach(FServices.Dispatcher);
  FIdeUnits := TIdeUnits.Create;
  FEditorIndex := TIdeIndex.Create(FIndex, FIdeUnits.Index);
end;

destructor TShellIndexArea.Destroy;
begin
  FreeAndNil(FFolders);
  FreeAndNil(FUsesGraph);
  FEditorIndex := nil;
  FreeAndNil(FIdeUnits);
  FIndex := nil;
  FServices := Default(TShellIndexAreaServices);
  inherited;
end;

procedure TShellIndexArea.FoldersChanged(const AAdded, ARemoved: TArray<TWorkspaceFolder>);
var
  mCore: TShellCore;
  mFolder: TWorkspaceFolder;
begin
  mCore := FServices.Core();
  for mFolder in ARemoved do
  begin
    mCore.Folders.Remove(mFolder);
  end;
  for mFolder in AAdded do
  begin
    mCore.Folders.Add(mFolder);
  end;
end;

procedure TShellIndexArea.ProjectLoaded;
var
  mNamespaces: TArray<string>;
  mLibraryRoots: TArray<string>;
  mAnonymizer: ILogAnonymizer;
  mDiagnostics: TShellDiagnosticsArea;
begin
  // Absicherung: Beim Beenden sind die Diagnosen vor dem Index fort.
  mDiagnostics := FServices.Diagnostics();
  // Neuer Indexaufbau: Seine Projektstufe oder, falls die ausbleibt, sein Ende startet die Projektprüfung.
  if mDiagnostics <> nil then
  begin
    mDiagnostics.IndexRecheck.IndexStarted;
  end;
  FServices.ProjectStarted();
  CollectNamespaces(mNamespaces, mLibraryRoots);
  ApplyNamespaces(mNamespaces);
  FServices.LibraryRootsChanged(mLibraryRoots);
  mAnonymizer := FServices.Anonymizer();
  if mAnonymizer <> nil then
  begin
    mAnonymizer.SetLibraryRoots(mLibraryRoots);
  end;
  if mDiagnostics <> nil then
  begin
    mDiagnostics.Syntax.Refresh;
  end;
end;

procedure TShellIndexArea.CollectNamespaces(out ANamespaces, ALibraryRoots: TArray<string>);
var
  mCore: TShellCore;
  mWorkspace: TShellWorkspace;
  mNamespace: string;
begin
  // Die Features kennen eine Liste: die Namespaces aller Projekte ohne Doppelte.
  ANamespaces := nil;
  ALibraryRoots := nil;
  mCore := FServices.Core();
  System.TMonitor.Enter(mCore.Workspaces.Lock);
  try
    // Projekte für projektweite Prüfregeln neu bestimmen (#1102).
    mCore.Workspaces.Touch;
    for mWorkspace in mCore.Workspaces.Items do
    begin
      for mNamespace in mWorkspace.State.Namespaces do
      begin
        if IndexText(mNamespace, ANamespaces) < 0 then
        begin
          ANamespaces := ANamespaces + [mNamespace];
        end;
      end;
      // Units der Delphi-Installation erscheinen im Diagnoselog mit Namen (#647).
      if (mWorkspace.State.BdsRoot <> '') and (IndexText(mWorkspace.State.BdsRoot, ALibraryRoots) < 0) then
      begin
        ALibraryRoots := ALibraryRoots + [mWorkspace.State.BdsRoot];
      end;
    end;
  finally
    System.TMonitor.Exit(mCore.Workspaces.Lock);
  end;
end;

procedure TShellIndexArea.ApplyNamespaces(const ANamespaces: TArray<string>);
var
  mGraphOptions: TUsesGraphOptions;
begin
  // Uses-Graph (#64) löst Namen ohne Namensraum über dieselbe Liste auf; neu aufgebaut nur bei Änderung.
  mGraphOptions := FUsesGraph.Options;
  if string.Join(';', mGraphOptions.Namespaces) <> string.Join(';', ANamespaces) then
  begin
    mGraphOptions.Namespaces := ANamespaces;
    FUsesGraph.SetOptions(mGraphOptions);
  end;
  FServices.NamespacesChanged(ANamespaces);
end;

procedure TShellIndexArea.HideIndexedUnits;
var
  mAnonymizer: ILogAnonymizer;
  mUnit: TUnitIndex;
begin
  // Units aus Suchpfaden stehen in keiner .dproj; im Server-Log ebenfalls verbergen (#647).
  mAnonymizer := FServices.Anonymizer();
  if mAnonymizer = nil then
  begin
    Exit;
  end;
  for mUnit in FIndex.Units do
  begin
    mAnonymizer.AddUnit(mUnit.UnitName, mUnit.FileName);
  end;
end;

procedure TShellIndexArea.RevalidateLater;
var
  mCore: TShellCore;
begin
  // Meldungen in atlas.json, die den Index brauchen (#309); Publish nur in der Nachrichtenschleife.
  mCore := FServices.Core();
  FServices.Queue(
    procedure
    var
      mWorkspace: TShellWorkspace;
      mWorkspaces: TArray<TShellWorkspace>;
    begin
      System.TMonitor.Enter(mCore.Workspaces.Lock);
      try
        mWorkspaces := mCore.Workspaces.Items.ToArray;
      finally
        System.TMonitor.Exit(mCore.Workspaces.Lock);
      end;
      for mWorkspace in mWorkspaces do
      begin
        mWorkspace.Configuration.Revalidate;
      end;
    end);
end;

procedure TShellIndexArea.IndexStageDone(AProjectStage: Boolean);
var
  mDiagnostics: TShellDiagnosticsArea;
begin
  HideIndexedUnits;
  // Befunde aus der Zeit des Aufbaus enthalten Units, die damals noch fehlten. Im Pull-Modus steigt
  // damit die Generation: Der Client holt geöffnete Dateien neu, workspace/diagnostic prüft alle.
  // Gebündelt: Die große Datei zu prüfen dauerte im Log über 20 s, und jedes Projekt meldet sich.
  // In einer Projektgruppe erst, wenn kein Projekt mehr indiziert wird: Sonst prüfte jedes fertige
  // Projekt alle Dateien neu (CPU-Last beim Start).
  if FServices.Core().Workspaces.ProjectIndexPending then
  begin
    Exit;
  end;
  // Erst am Ende des ganzen Aufbaus steht fest, welche Units der IDE keinen Quelltext haben.
  if not AProjectStage and Assigned(FServices.IndexFinished) then
  begin
    FServices.IndexFinished();
  end;
  // Nach der Projektstufe kennt der Index alles, was das Projekt über uses erreicht. Das Ende des Aufbaus
  // (Suchpfade, Bibliothek) startet die Prüfung nicht noch einmal von vorn (Diagnose-Log 29.10.2026).
  mDiagnostics := FServices.Diagnostics();
  // Absicherung: Beim Beenden sind die Diagnosen vor dem Index fort.
  if (mDiagnostics <> nil) and mDiagnostics.IndexRecheck.Recheck(AProjectStage) then
  begin
    mDiagnostics.Syntax.RefreshLater;
  end;
  RevalidateLater;
end;

end.
