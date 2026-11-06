unit Atlas.IDE.Problems.Files;

// Projekte und Dateien für die Bereiche des Fensters „Atlas-Prüfung“ (#909,
// #1843) aus der Open Tools API, dazu die Zeilen ungeöffneter Dateien von der
// Platte. Projekt = .dpr/.dpk und die .pas-Module des
// Projekts; Projektgruppe = alle Dateien aller Projekte der Gruppe ohne
// Doppelte (vorher galt jeder Befund im Speicher, auch von Units außerhalb
// der Gruppe). Die Dateien der Gruppe bleiben 2 s im Zwischenspeicher, weil
// der Takt des Fensters alle 250 ms fragt; ändert sich die Gruppe, gilt der
// Speicher sofort nicht mehr. Nur im Hauptthread verwenden.

interface

uses
  Atlas.Core.Problems.ScopeProjects;

type
  TAtlasIdeProblemFiles = class
  public
    /// <summary>Projekte der offenen Gruppe in ihrer Reihenfolge, das aktive markiert; ohne Gruppe nur das aktive
    /// Projekt, ohne Projekt leer.</summary>
    class function Projects: TArray<TAtlasScopeProject>; static;
    /// <summary>Dateien des aktiven Projekts.</summary>
    class function ActiveFiles: TArray<string>; static;
    /// <summary>Dateien des Projekts AName der Gruppe; '' oder unbekannt = aktives Projekt.</summary>
    class function FilesOf(const AName: string): TArray<string>; static;
    /// <summary>Dateien aller Projekte der Gruppe; AKey kennzeichnet den Stand (gleich = gleiche Dateien). Ohne
    /// Projekt nil (dann gelten alle Dateien im Speicher).</summary>
    class function GroupFiles(out AKey: string): TArray<string>; static;
    /// <summary>Zeilen einer ungeöffneten Datei von der Platte; nil, wenn sie fehlt oder sich nicht lesen lässt.
    /// </summary>
    class function DiskLines(const AFileName: string): TArray<string>; static;
    /// <summary>Zwischenspeicher freigeben (Entladen).</summary>
    class procedure Release; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  ToolsAPI,
  Atlas.Core.Files.TextFile;

const
  /// <summary>So lange gelten die Dateien der Gruppe ohne neue Abfrage.</summary>
  cGroupCacheMs = 2000;

var
  GroupCache: TArray<string>;
  GroupCacheKey: string;
  GroupCacheProjects: string;
  GroupCacheAt: UInt64;

function ModuleServices(out AModules: IOTAModuleServices): Boolean;
begin
  Result := Supports(BorlandIDEServices, IOTAModuleServices, AModules);
end;

/// <summary>.dpr/.dpk und .pas-Module von AProject.</summary>
function FilesOfProject(const AProject: IOTAProject): TArray<string>;
var
  mIndex: Integer;
  mInfo: IOTAModuleInfo;
  mMain: string;
begin
  Result := nil;
  if AProject = nil then
  begin
    Exit;
  end;
  for mMain in TArray<string>.Create(ChangeFileExt(AProject.FileName, '.dpr'),
    ChangeFileExt(AProject.FileName, '.dpk')) do
  begin
    if TFile.Exists(mMain) then
    begin
      Result := Result + [mMain];
    end;
  end;
  for mIndex := 0 to AProject.GetModuleCount - 1 do
  begin
    mInfo := AProject.GetModule(mIndex);
    if (mInfo <> nil) and SameText(ExtractFileExt(mInfo.FileName), '.pas') then
    begin
      Result := Result + [mInfo.FileName];
    end;
  end;
end;

/// <summary>Projekte der offenen Gruppe; ohne Gruppe das aktive allein.</summary>
function GroupProjects: TArray<IOTAProject>;
var
  mModules: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mActive: IOTAProject;
  mIndex: Integer;
begin
  Result := nil;
  if not ModuleServices(mModules) then
  begin
    Exit;
  end;
  mGroup := mModules.MainProjectGroup;
  if (mGroup <> nil) and (mGroup.ProjectCount > 0) then
  begin
    for mIndex := 0 to mGroup.ProjectCount - 1 do
    begin
      Result := Result + [mGroup.Projects[mIndex]];
    end;
    Exit;
  end;
  mActive := mModules.GetActiveProject;
  if mActive <> nil then
  begin
    Result := [mActive];
  end;
end;

function ActiveProject: IOTAProject;
var
  mModules: IOTAModuleServices;
begin
  Result := nil;
  if ModuleServices(mModules) then
  begin
    Result := mModules.GetActiveProject;
  end;
end;

{ TAtlasIdeProblemFiles }

class function TAtlasIdeProblemFiles.Projects: TArray<TAtlasScopeProject>;
var
  mProject: IOTAProject;
  mActive: string;
begin
  Result := nil;
  mActive := '';
  if ActiveProject <> nil then
  begin
    mActive := ActiveProject.FileName;
  end;
  for mProject in GroupProjects do
  begin
    if mProject <> nil then
    begin
      Result := Result + [TAtlasScopeProject.Create(mProject.FileName, SameText(mProject.FileName, mActive))];
    end;
  end;
end;

class function TAtlasIdeProblemFiles.ActiveFiles: TArray<string>;
begin
  Result := FilesOfProject(ActiveProject);
end;

class function TAtlasIdeProblemFiles.FilesOf(const AName: string): TArray<string>;
var
  mProject: IOTAProject;
begin
  if AName <> '' then
  begin
    for mProject in GroupProjects do
    begin
      if (mProject <> nil) and SameText(TAtlasScopeProject.Create(mProject.FileName, False).Name, AName) then
      begin
        Exit(FilesOfProject(mProject));
      end;
    end;
  end;
  Result := ActiveFiles;
end;

class function TAtlasIdeProblemFiles.GroupFiles(out AKey: string): TArray<string>;
var
  mProjects: TArray<IOTAProject>;
  mLists: TArray<TArray<string>>;
  mProject: IOTAProject;
  mProjectFiles: TArray<string>;
  mNames: string;
  mIndex: Integer;
begin
  mProjects := GroupProjects;
  mProjectFiles := nil;
  for mProject in mProjects do
  begin
    mProjectFiles := mProjectFiles + [mProject.FileName];
  end;
  mNames := string.Join('|', mProjectFiles);
  if (mNames <> GroupCacheProjects) or (TThread.GetTickCount64 - GroupCacheAt >= cGroupCacheMs) then
  begin
    SetLength(mLists, Length(mProjects));
    for mIndex := 0 to High(mProjects) do
    begin
      mLists[mIndex] := FilesOfProject(mProjects[mIndex]);
    end;
    GroupCache := TAtlasScopeFiles.Union(mLists);
    GroupCacheProjects := mNames;
    GroupCacheAt := TThread.GetTickCount64;
    GroupCacheKey := mNames + string.Join(';', GroupCache);
  end;
  Result := GroupCache;
  AKey := GroupCacheKey;
end;

class function TAtlasIdeProblemFiles.DiskLines(const AFileName: string): TArray<string>;
begin
  Result := nil;
  try
    if TFile.Exists(AFileName) then
    begin
      Result := TAtlasTextFile.Load(AFileName).Text.Split([#13#10, #10]);
    end;
  except
    // Gesperrt, gelöscht oder binär: Die Spalte „Zeile“ bleibt leer, das Fenster läuft weiter.
    on Exception do
      Result := nil;
  end;
end;

class procedure TAtlasIdeProblemFiles.Release;
begin
  GroupCache := nil;
  GroupCacheKey := '';
  GroupCacheProjects := '';
  GroupCacheAt := 0;
end;

end.
