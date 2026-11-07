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
// übergeht der Server.

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
  System.IOUtils,
  System.JSON,
  ToolsAPI,
  Atlas.Core.Files.DataFile;

constructor TAtlasDirtyExport.Create;
begin
  inherited Create;
  FFileName := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    Format('editor-dirty-%d.json', [GetCurrentProcessId]));
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
    // Atomar (Bericht N3): Der Server liest die Liste jederzeit und sah sonst womöglich eine halbe.
    TAtlasDataFile.Write(FFileName, mText);
    FLast := mText;
  except
    // Ohne Liste schützt der Server weiter über den Vergleich mit der Platte; der Grund steht einmal im Protokoll.
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Liste ungespeicherter Dateien', E);
  end;
end;

end.
