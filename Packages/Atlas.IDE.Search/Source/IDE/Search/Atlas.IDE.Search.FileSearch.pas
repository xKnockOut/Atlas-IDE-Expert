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
  mSummary: TAtlasFileSearchSummary;
  mRun: Integer;
begin
  mRun := FRun;
  try
    mSummary := TAtlasFileSearch.Run(FSources, FQuery, TAtlasFileSearch.DiskLoader(),
      function: Boolean
      begin
        Result := Terminated;
      end,
      procedure(AHits: TAtlasFileHits)
      begin
        TAtlasMainThread.Queue(TAtlasFeature.Search,
          procedure
          begin
            TAtlasIdeFileSearch.Found(mRun, AHits);
          end);
      end);
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Search, E);
      mSummary := Default(TAtlasFileSearchSummary);
      mSummary.Cancelled := True;
    end;
  end;
  TAtlasMainThread.Queue(TAtlasFeature.Search,
    procedure
    begin
      TAtlasIdeFileSearch.Done(mRun, mSummary);
    end);
end;

{ TAtlasIdeFileSearch }

procedure AddModuleFiles(const AModule: IOTAModule; var AFiles: TArray<string>);
var
  mIndex: Integer;
begin
  if AModule = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to AModule.ModuleFileCount - 1 do
  begin
    if AModule.ModuleFileEditors[mIndex] <> nil then
    begin
      AFiles := AFiles + [AModule.ModuleFileEditors[mIndex].FileName];
    end;
  end;
end;

procedure AddProject(const AProject: IOTAProject; var AFiles: TArray<string>);
var
  mIndex: Integer;
  mInfo: IOTAModuleInfo;
  mMain: string;
begin
  if AProject = nil then
  begin
    Exit;
  end;
  for mMain in TArray<string>.Create(ChangeFileExt(AProject.FileName, '.dpr'),
    ChangeFileExt(AProject.FileName, '.dpk')) do
  begin
    if TFile.Exists(mMain) then
    begin
      AFiles := AFiles + [mMain];
    end;
  end;
  for mIndex := 0 to AProject.GetModuleCount - 1 do
  begin
    mInfo := AProject.GetModule(mIndex);
    if (mInfo = nil) or (mInfo.FileName = '') then
    begin
      Continue;
    end;
    AFiles := AFiles + [mInfo.FileName];
    // Formular der Unit (Projektmodule nennen nur die .pas).
    if mInfo.FormName <> '' then
    begin
      if TFile.Exists(ChangeFileExt(mInfo.FileName, '.dfm')) then
      begin
        AFiles := AFiles + [ChangeFileExt(mInfo.FileName, '.dfm')];
      end
      else if TFile.Exists(ChangeFileExt(mInfo.FileName, '.fmx')) then
      begin
        AFiles := AFiles + [ChangeFileExt(mInfo.FileName, '.fmx')];
      end;
    end;
  end;
end;

class function TAtlasIdeFileSearch.FilesOf(AScope: TAtlasSearchScope): TArray<string>;
var
  mServices: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  case AScope of
    TAtlasSearchScope.OpenFiles:
      for mIndex := 0 to mServices.ModuleCount - 1 do
      begin
        AddModuleFiles(mServices.Modules[mIndex], Result);
      end;
    TAtlasSearchScope.Project:
      AddProject(mServices.GetActiveProject, Result);
    TAtlasSearchScope.ProjectGroup:
      begin
        mGroup := mServices.MainProjectGroup;
        if mGroup = nil then
        begin
          AddProject(mServices.GetActiveProject, Result);
        end
        else
        begin
          for mIndex := 0 to mGroup.ProjectCount - 1 do
          begin
            AddProject(mGroup.Projects[mIndex], Result);
          end;
        end;
      end;
    TAtlasSearchScope.UnitFile, TAtlasSearchScope.Method, TAtlasSearchScope.Selection: ;
  end;
end;

class function TAtlasIdeFileSearch.Buffers: TArray<TAtlasSearchSource>;
var
  mServices: IOTAModuleServices;
  mIndex, mFileIndex: Integer;
  mModule: IOTAModule;
  mBuffer: IOTAEditBuffer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ModuleCount - 1 do
  begin
    mModule := mServices.Modules[mIndex];
    if mModule = nil then
    begin
      Continue;
    end;
    for mFileIndex := 0 to mModule.ModuleFileCount - 1 do
    begin
      if Supports(mModule.ModuleFileEditors[mFileIndex], IOTAEditBuffer, mBuffer) and
        TAtlasFileSearch.IsSearchable(mBuffer.FileName) then
      begin
        Result := Result + [TAtlasSearchSource.FromBuffer(mBuffer.FileName, TAtlasEditorBuffer.Text(mBuffer))];
      end;
    end;
  end;
end;

class function TAtlasIdeFileSearch.Start(const AFiles: TArray<string>; const AFirst: string;
  const AQuery: TAtlasSearchQuery; const AOnFound: TProc<TAtlasFileHits>;
  const AOnDone: TProc<TAtlasFileSearchSummary>): Boolean;
var
  mSources: TArray<TAtlasSearchSource>;
begin
  Stop;
  mSources := TAtlasFileSearch.Sources(AFiles, Buffers, AFirst);
  Result := Length(mSources) > 0;
  if not Result then
  begin
    Exit;
  end;
  Inc(FRun);
  FOnFound := AOnFound;
  FOnDone := AOnDone;
  FWorker := TWorker.Create(mSources, AQuery, FRun);
end;

class procedure TAtlasIdeFileSearch.Found(ARun: Integer; const AHits: TAtlasFileHits);
begin
  if (ARun = FRun) and Assigned(FOnFound) then
  begin
    FOnFound(AHits);
  end;
end;

class procedure TAtlasIdeFileSearch.Done(ARun: Integer; const ASummary: TAtlasFileSearchSummary);
var
  mOnDone: TProc<TAtlasFileSearchSummary>;
begin
  if ARun <> FRun then
  begin
    Exit;
  end;
  mOnDone := FOnDone;
  Finish;
  if Assigned(mOnDone) then
  begin
    mOnDone(ASummary);
  end;
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
  begin
    FWorker.Terminate;
  end;
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
