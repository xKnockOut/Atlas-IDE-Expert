unit Atlas.IDE.Files.DirtyExport;

// Ungespeicherte Dateien der IDE für schreibende MCP-Werkzeuge (#61, #99):
// Jede Sekunde sammelt das Plugin die geänderten, nicht gespeicherten Dateien
// aller offenen Module und schreibt sie bei Änderung nach
// %LOCALAPPDATA%\Atlas\editor-dirty-<pid>.json ({"pid": …, "files": [...]}).
// Der MCP-Server bricht Schreibaufrufe ab, die eine dieser Dateien betreffen.
// Unter "open" stehen alle im Editor offenen Dateien: Diese ändert der
// MCP-Server über den Eingang des Plugins statt auf der Platte (#397).
// Unter "projects" stehen die offenen Projekte (.dproj), unter
// "activeProject" das aktive: build_project wählt danach IDE und Projekt
// (#261).
// Beim Beenden löscht das Plugin seine Datei; Dateien beendeter Prozesse
// übergeht der Server. Beim Start räumt das Plugin die Dateien und
// Build-Eingänge (ide-builds\<pid>) abgestürzter oder hart beendeter Prozesse
// weg (Atlas.Core.Files.ProcessLeftovers).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls;

type
  TAtlasDirtyExport = class
  private
    FTimer: TTimer;
    FFileName: string;
    FLast: string;
    procedure Tick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Geänderte, nicht gespeicherte Dateien aller offenen Module.</summary>
    class function ModifiedFiles: TArray<string>; static;
    /// <summary>Alle Dateien offener Module mit Editorpuffer (#397).</summary>
    class function OpenFiles: TArray<string>; static;
    /// <summary>Offene Projekte (.dproj) und das aktive ('' ohne), für build_project (#261).</summary>
    class function OpenProjects(out AActive: string): TArray<string>; static;
  end;

implementation

uses
  System.Generics.Collections,
  Winapi.Windows,
  Winapi.TlHelp32,
  System.IOUtils,
  System.JSON,
  ToolsAPI,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Files.ProcessLeftovers;

const
  cPROCESS_QUERY_LIMITED_INFORMATION = $1000;

/// <summary>Läuft unter APid dasselbe Programm wie im eigenen Prozess (bds.exe)? Eine wiederverwendete Nummer
/// gehört oft einem ganz anderen Programm, auch einem, das sich nicht öffnen lässt. Die Prozessliste von Windows
/// nennt den Namen ohne Zugriffsrechte. Ohne Liste: ja (lieber liegen lassen als fremde Reste löschen).</summary>
function SameProgram(APid: Cardinal): Boolean;
var
  mSnapshot: THandle;
  mEntry: TProcessEntry32;
begin
  Result := True;
  mSnapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if mSnapshot = INVALID_HANDLE_VALUE then
  begin
    Exit;
  end;
  try
    mEntry := Default(TProcessEntry32);
    mEntry.dwSize := SizeOf(mEntry);
    if not Process32First(mSnapshot, mEntry) then
    begin
      Exit;
    end;
    repeat
      if mEntry.th32ProcessID = APid then
      begin
        Exit(SameText(ExtractFileName(string(mEntry.szExeFile)), ExtractFileName(ParamStr(0))));
      end;
    until not Process32Next(mSnapshot, mEntry);
    // Nicht in der Liste: beendet.
    Result := False;
  finally
    CloseHandle(mSnapshot);
  end;
end;

/// <summary>Läuft APid noch, ist es dasselbe Programm, und lief er schon zu AStamp (sonst gehört die Nummer einem
/// neuen Prozess)?</summary>
function ProcessAlive(APid: Cardinal; AStamp: TDateTime): Boolean;
var
  mProcess: THandle;
  mCode: DWORD;
  mCreation, mExitTime, mKernelTime, mUserTime: TFileTime;
  mLocal: TFileTime;
  mStarted: TSystemTime;
begin
  if not SameProgram(APid) then
  begin
    Exit(False);
  end;
  mProcess := OpenProcess(cPROCESS_QUERY_LIMITED_INFORMATION, False, APid);
  if mProcess = 0 then
  begin
    // Kein Zugriff heißt: Den Prozess gibt es (andere Anmeldung); sonst ist er beendet.
    Exit(GetLastError = ERROR_ACCESS_DENIED);
  end;
  try
    Result := GetExitCodeProcess(mProcess, mCode) and (mCode = STILL_ACTIVE);
    if Result and GetProcessTimes(mProcess, mCreation, mExitTime, mKernelTime, mUserTime) and
      FileTimeToLocalFileTime(mCreation, mLocal) and FileTimeToSystemTime(mLocal, mStarted) then
    begin
      Result := SystemTimeToDateTime(mStarted) <= AStamp;
    end;
  finally
    CloseHandle(mProcess);
  end;
end;

/// <summary>Exportierte Dateien in AFolder mit der Prozessnummer im Namen.</summary>
function DirtyFiles(const AFolder: string): TArray<TAtlasLeftover>;
var
  mPath: string;
  mPid: Cardinal;
begin
  Result := nil;
  if not TDirectory.Exists(AFolder) then
  begin
    Exit;
  end;
  for mPath in TDirectory.GetFiles(AFolder, TAtlasProcessLeftovers.cDirtyPrefix + '*') do
  begin
    if TAtlasProcessLeftovers.PidOf(ExtractFileName(mPath), TAtlasProcessLeftovers.cDirtyPrefix,
      TAtlasProcessLeftovers.cDirtySuffix, mPid) then
    begin
      Result := Result + [TAtlasLeftover.Create(mPath, mPid, TFile.GetLastWriteTime(mPath))];
    end;
  end;
end;

/// <summary>Build-Ordner unter AFolder, je Prozessnummer einer.</summary>
function BuildFolders(const AFolder: string): TArray<TAtlasLeftover>;
var
  mPath, mBuilds: string;
  mPid: Cardinal;
begin
  Result := nil;
  mBuilds := TPath.Combine(AFolder, TAtlasProcessLeftovers.cBuildsFolder);
  if not TDirectory.Exists(mBuilds) then
  begin
    Exit;
  end;
  for mPath in TDirectory.GetDirectories(mBuilds) do
  begin
    if TAtlasProcessLeftovers.PidOf(ExtractFileName(mPath), '', '', mPid) then
    begin
      Result := Result + [TAtlasLeftover.Create(mPath, mPid, TDirectory.GetLastWriteTime(mPath))];
    end;
  end;
end;

/// <summary>Dateien und Build-Eingänge beendeter Prozesse unter AFolder entfernen.</summary>
procedure RemoveLeftovers(const AFolder: string);
var
  mPath: string;
begin
  for mPath in TAtlasProcessLeftovers.Stale(DirtyFiles(AFolder) + BuildFolders(AFolder), GetCurrentProcessId,
    ProcessAlive) do
  begin
    try
      if TDirectory.Exists(mPath) then
      begin
        TDirectory.Delete(mPath, True);
      end
      else
      begin
        TFile.Delete(mPath);
      end;
    except
      // Gesperrt oder schon weg: beim nächsten Start wieder versuchen.
      on Exception do
        ;
    end;
  end;
end;

constructor TAtlasDirtyExport.Create;
begin
  inherited Create;
  FFileName := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    Format('editor-dirty-%d.json', [GetCurrentProcessId]));
  try
    RemoveLeftovers(ExtractFileDir(FFileName));
  except
    // Aufräumen ist Nebensache; die Liste dieses Prozesses entsteht trotzdem.
    on Exception do
      ;
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 1000;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasDirtyExport.Destroy;
begin
  FTimer.Free;
  try
    if FileExists(FFileName) then
    begin
      TFile.Delete(FFileName);
    end;
  except
    // Ein liegengebliebener Eintrag wird vom Server übergangen (Prozess beendet).
    on Exception do
      ;
  end;
  inherited Destroy;
end;

class function TAtlasDirtyExport.ModifiedFiles: TArray<string>;
var
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
  mIndex, mFileIndex: Integer;
  mEditor: IOTAEditor;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  for mIndex := 0 to mModules.ModuleCount - 1 do
  begin
    mModule := mModules.Modules[mIndex];
    for mFileIndex := 0 to mModule.ModuleFileCount - 1 do
    begin
      mEditor := mModule.ModuleFileEditors[mFileIndex];
      if (mEditor <> nil) and mEditor.Modified and (mEditor.FileName <> '') then
      begin
        Result := Result + [mEditor.FileName];
      end;
    end;
  end;
end;

class function TAtlasDirtyExport.OpenFiles: TArray<string>;
var
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
  mIndex, mFileIndex: Integer;
  mEditor: IOTAEditor;
  mBuffer: IOTAEditBuffer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  for mIndex := 0 to mModules.ModuleCount - 1 do
  begin
    mModule := mModules.Modules[mIndex];
    for mFileIndex := 0 to mModule.ModuleFileCount - 1 do
    begin
      mEditor := mModule.ModuleFileEditors[mFileIndex];
      if (mEditor <> nil) and (mEditor.FileName <> '') and Supports(mEditor, IOTAEditBuffer, mBuffer) then
      begin
        Result := Result + [mEditor.FileName];
      end;
    end;
  end;
end;

class function TAtlasDirtyExport.OpenProjects(out AActive: string): TArray<string>;
var
  mModules: IOTAModuleServices;
  mProject: IOTAProject;
  mIndex: Integer;
begin
  Result := nil;
  AActive := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  for mIndex := 0 to mModules.ModuleCount - 1 do
  begin
    if Supports(mModules.Modules[mIndex], IOTAProject, mProject) and
      SameText(ExtractFileExt(mProject.FileName), '.dproj') then
    begin
      Result := Result + [mProject.FileName];
    end;
  end;
  mProject := mModules.GetActiveProject;
  if (mProject <> nil) and SameText(ExtractFileExt(mProject.FileName), '.dproj') then
  begin
    AActive := mProject.FileName;
  end;
end;

procedure TAtlasDirtyExport.Tick(Sender: TObject);
var
  mJson: TJSONObject;
  mFiles, mOpen, mProjects: TJSONArray;
  mName, mText, mActive: string;
begin
  try
    mFiles := TJSONArray.Create;
    for mName in ModifiedFiles do
    begin
      mFiles.Add(mName);
    end;
    mOpen := TJSONArray.Create;
    for mName in OpenFiles do
    begin
      mOpen.Add(mName);
    end;
    mProjects := TJSONArray.Create;
    for mName in OpenProjects(mActive) do
    begin
      mProjects.Add(mName);
    end;
    mJson := TJSONObject.Create;
    try
      mJson.AddPair('pid', TJSONNumber.Create(GetCurrentProcessId));
      mJson.AddPair('files', mFiles);
      mJson.AddPair('open', mOpen);
      mJson.AddPair('projects', mProjects);
      mJson.AddPair('activeProject', mActive);
      mText := mJson.ToJSON;
    finally
      mJson.Free;
    end;
    if mText = FLast then
    begin
      Exit;
    end;
    // Atomar: Der Server liest die Liste jederzeit und sah sonst womöglich eine halbe.
    TAtlasDataFile.Write(FFileName, mText);
    FLast := mText;
  except
    // Ohne Liste schützt der Server weiter über den Vergleich mit der Platte; der Grund steht einmal im Protokoll.
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Liste ungespeicherter Dateien', E);
  end;
end;

end.
