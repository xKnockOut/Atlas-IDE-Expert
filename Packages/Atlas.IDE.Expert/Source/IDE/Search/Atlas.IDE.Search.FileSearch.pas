unit Atlas.IDE.Search.FileSearch;

// Suche der Atlas-Suchleiste über mehrere Dateien (#893, search.multiFile):
// - FilesOf: Dateien der Bereiche „Offene Dateien“ (alle Module der IDE mit
//   ihren Dateien, also auch .dfm und .dpr), „Projekt“ (aktives Projekt:
//   .dpr/.dpk und seine Units mit Formularen) und „Projektgruppe“ (alle
//   Projekte der Gruppe).
// - Start: liest im Hauptthread die Puffer aller offenen Dateien (Vorrang vor
//   der Platte, auch ungespeichert) und sucht in einem eigenen Thread
//   (TAtlasFileSearch.Run). Jede Datei mit Treffern und das Ende kommen über
//   TAtlasMainThread in den Hauptthread; die IDE bleibt bedienbar
//   (Einfrier-Wächter #501). Ein neuer Start, Cancel oder Stop beendet die
//   laufende Suche; Meldungen einer beendeten Suche fallen weg (Nummer des
//   Laufs). Stop wartet auf den Thread (beim Entladen).
// Nur im Hauptthread aufrufen.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Search.Matching,
  Atlas.Core.Search.Files;

type
  TAtlasIdeFileSearch = class
  private type
    TWorker = class(TThread)
    private
      FSources: TArray<TAtlasSearchSource>;
      FQuery: TAtlasSearchQuery;
      FRun: Integer;
    protected
      procedure Execute; override;
    public
      constructor Create(const ASources: TArray<TAtlasSearchSource>; const AQuery: TAtlasSearchQuery; ARun: Integer);
    end;
  private class var
    FWorker: TWorker;
    FRun: Integer;
    FOnFound: TProc<TAtlasFileHits>;
    FOnDone: TProc<TAtlasFileSearchSummary>;
    class procedure Found(ARun: Integer; const AHits: TAtlasFileHits); static;
    class procedure Done(ARun: Integer; const ASummary: TAtlasFileSearchSummary); static;
    class procedure Finish; static;
  public
    /// <summary>Dateien des Bereichs; leer, wenn es keine gibt (kein Projekt).</summary>
    class function FilesOf(AScope: TAtlasSearchScope): TArray<string>; static;
    /// <summary>Text aller offenen Puffer.</summary>
    class function Buffers: TArray<TAtlasSearchSource>; static;
    /// <summary>Suche in AFiles beginnen (AFirst zuerst); False ohne durchsuchbare Datei.</summary>
    class function Start(const AFiles: TArray<string>; const AFirst: string; const AQuery: TAtlasSearchQuery;
      const AOnFound: TProc<TAtlasFileHits>; const AOnDone: TProc<TAtlasFileSearchSummary>): Boolean; static;
    /// <summary>Laufende Suche abbrechen; das Ende meldet sie mit Cancelled.</summary>
    class procedure Cancel; static;
    /// <summary>Abbrechen, auf den Thread warten, keine Meldungen mehr (Entladen, Einstellung aus).</summary>
    class procedure Stop; static;
    class function Running: Boolean; static;
  end;

implementation

uses
  System.IOUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.IDE.Foundation.EditorBuffer;

{ TAtlasIdeFileSearch.TWorker }

constructor TAtlasIdeFileSearch.TWorker.Create(const ASources: TArray<TAtlasSearchSource>;
  const AQuery: TAtlasSearchQuery; ARun: Integer);
begin
  FSources := ASources;
  FQuery := AQuery;
  FRun := ARun;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TAtlasIdeFileSearch.TWorker.Execute;
var
  Summary: TAtlasFileSearchSummary;
  Run: Integer;
begin
  Run := FRun;
  try
    Summary := TAtlasFileSearch.Run(FSources, FQuery, TAtlasFileSearch.DiskLoader,
      function: Boolean
      begin
        Result := Terminated;
      end,
      procedure(AHits: TAtlasFileHits)
      begin
        TAtlasMainThread.Queue(TAtlasFeature.Search,
          procedure
          begin
            TAtlasIdeFileSearch.Found(Run, AHits);
          end);
      end);
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Search, E);
      Summary := Default(TAtlasFileSearchSummary);
      Summary.Cancelled := True;
    end;
  end;
  TAtlasMainThread.Queue(TAtlasFeature.Search,
    procedure
    begin
      TAtlasIdeFileSearch.Done(Run, Summary);
    end);
end;

{ TAtlasIdeFileSearch }

procedure AddModuleFiles(const AModule: IOTAModule; var AFiles: TArray<string>);
var
  Index: Integer;
begin
  if AModule = nil then
    Exit;
  for Index := 0 to AModule.ModuleFileCount - 1 do
    if AModule.ModuleFileEditors[Index] <> nil then
      AFiles := AFiles + [AModule.ModuleFileEditors[Index].FileName];
end;

procedure AddProject(const AProject: IOTAProject; var AFiles: TArray<string>);
var
  Index: Integer;
  Info: IOTAModuleInfo;
  Main: string;
begin
  if AProject = nil then
    Exit;
  for Main in TArray<string>.Create(ChangeFileExt(AProject.FileName, '.dpr'),
    ChangeFileExt(AProject.FileName, '.dpk')) do
    if TFile.Exists(Main) then
      AFiles := AFiles + [Main];
  for Index := 0 to AProject.GetModuleCount - 1 do
  begin
    Info := AProject.GetModule(Index);
    if (Info = nil) or (Info.FileName = '') then
      Continue;
    AFiles := AFiles + [Info.FileName];
    // Formular der Unit (Projektmodule nennen nur die .pas).
    if Info.FormName <> '' then
    begin
      if TFile.Exists(ChangeFileExt(Info.FileName, '.dfm')) then
        AFiles := AFiles + [ChangeFileExt(Info.FileName, '.dfm')]
      else if TFile.Exists(ChangeFileExt(Info.FileName, '.fmx')) then
        AFiles := AFiles + [ChangeFileExt(Info.FileName, '.fmx')];
    end;
  end;
end;

class function TAtlasIdeFileSearch.FilesOf(AScope: TAtlasSearchScope): TArray<string>;
var
  Services: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Index: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  case AScope of
    TAtlasSearchScope.OpenFiles:
      for Index := 0 to Services.ModuleCount - 1 do
        AddModuleFiles(Services.Modules[Index], Result);
    TAtlasSearchScope.Project:
      AddProject(Services.GetActiveProject, Result);
    TAtlasSearchScope.ProjectGroup:
      begin
        Group := Services.MainProjectGroup;
        if Group = nil then
          AddProject(Services.GetActiveProject, Result)
        else
          for Index := 0 to Group.ProjectCount - 1 do
            AddProject(Group.Projects[Index], Result);
      end;
  end;
end;

class function TAtlasIdeFileSearch.Buffers: TArray<TAtlasSearchSource>;
var
  Services: IOTAModuleServices;
  Index, FileIndex: Integer;
  Module: IOTAModule;
  Buffer: IOTAEditBuffer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  for Index := 0 to Services.ModuleCount - 1 do
  begin
    Module := Services.Modules[Index];
    if Module = nil then
      Continue;
    for FileIndex := 0 to Module.ModuleFileCount - 1 do
      if Supports(Module.ModuleFileEditors[FileIndex], IOTAEditBuffer, Buffer) and
        TAtlasFileSearch.IsSearchable(Buffer.FileName) then
        Result := Result + [TAtlasSearchSource.FromBuffer(Buffer.FileName, TAtlasEditorBuffer.Text(Buffer))];
  end;
end;

class function TAtlasIdeFileSearch.Start(const AFiles: TArray<string>; const AFirst: string;
  const AQuery: TAtlasSearchQuery; const AOnFound: TProc<TAtlasFileHits>;
  const AOnDone: TProc<TAtlasFileSearchSummary>): Boolean;
var
  Sources: TArray<TAtlasSearchSource>;
begin
  Stop;
  Sources := TAtlasFileSearch.Sources(AFiles, Buffers, AFirst);
  Result := Length(Sources) > 0;
  if not Result then
    Exit;
  Inc(FRun);
  FOnFound := AOnFound;
  FOnDone := AOnDone;
  FWorker := TWorker.Create(Sources, AQuery, FRun);
end;

class procedure TAtlasIdeFileSearch.Found(ARun: Integer; const AHits: TAtlasFileHits);
begin
  if (ARun = FRun) and Assigned(FOnFound) then
    FOnFound(AHits);
end;

class procedure TAtlasIdeFileSearch.Done(ARun: Integer; const ASummary: TAtlasFileSearchSummary);
var
  OnDone: TProc<TAtlasFileSearchSummary>;
begin
  if ARun <> FRun then
    Exit;
  OnDone := FOnDone;
  Finish;
  if Assigned(OnDone) then
    OnDone(ASummary);
end;

/// <summary>Fertigen Thread freigeben, Rückrufe vergessen.</summary>
class procedure TAtlasIdeFileSearch.Finish;
begin
  if FWorker <> nil then
  begin
    FWorker.Terminate;
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
  FOnFound := nil;
  FOnDone := nil;
end;

class procedure TAtlasIdeFileSearch.Cancel;
begin
  if FWorker <> nil then
    FWorker.Terminate;
end;

class procedure TAtlasIdeFileSearch.Stop;
begin
  // Neue Nummer: Was der Thread noch einreiht, fällt weg.
  Inc(FRun);
  Finish;
end;

class function TAtlasIdeFileSearch.Running: Boolean;
begin
  Result := (FWorker <> nil) and not FWorker.Finished;
end;

end.
