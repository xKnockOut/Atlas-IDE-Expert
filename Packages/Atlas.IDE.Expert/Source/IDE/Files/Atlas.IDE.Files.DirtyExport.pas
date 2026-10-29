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
      TFile.Delete(FFileName);
  except
    // Ein liegengebliebener Eintrag wird vom Server übergangen (Prozess beendet).
    on Exception do
      ;
  end;
  inherited Destroy;
end;

class function TAtlasDirtyExport.ModifiedFiles: TArray<string>;
var
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  Index, FileIndex: Integer;
  Editor: IOTAEditor;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  for Index := 0 to Modules.ModuleCount - 1 do
  begin
    Module := Modules.Modules[Index];
    for FileIndex := 0 to Module.ModuleFileCount - 1 do
    begin
      Editor := Module.ModuleFileEditors[FileIndex];
      if (Editor <> nil) and Editor.Modified and (Editor.FileName <> '') then
        Result := Result + [Editor.FileName];
    end;
  end;
end;

class function TAtlasDirtyExport.OpenFiles: TArray<string>;
var
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  Index, FileIndex: Integer;
  Editor: IOTAEditor;
  Buffer: IOTAEditBuffer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  for Index := 0 to Modules.ModuleCount - 1 do
  begin
    Module := Modules.Modules[Index];
    for FileIndex := 0 to Module.ModuleFileCount - 1 do
    begin
      Editor := Module.ModuleFileEditors[FileIndex];
      if (Editor <> nil) and (Editor.FileName <> '') and Supports(Editor, IOTAEditBuffer, Buffer) then
        Result := Result + [Editor.FileName];
    end;
  end;
end;

class function TAtlasDirtyExport.OpenProjects(out AActive: string): TArray<string>;
var
  Modules: IOTAModuleServices;
  Project: IOTAProject;
  Index: Integer;
begin
  Result := nil;
  AActive := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  for Index := 0 to Modules.ModuleCount - 1 do
    if Supports(Modules.Modules[Index], IOTAProject, Project) and
      SameText(ExtractFileExt(Project.FileName), '.dproj') then
      Result := Result + [Project.FileName];
  Project := Modules.GetActiveProject;
  if (Project <> nil) and SameText(ExtractFileExt(Project.FileName), '.dproj') then
    AActive := Project.FileName;
end;

procedure TAtlasDirtyExport.Tick(Sender: TObject);
var
  Json: TJSONObject;
  Files, Open, Projects: TJSONArray;
  Name, Text, Active: string;
begin
  try
    Files := TJSONArray.Create;
    for Name in ModifiedFiles do
      Files.Add(Name);
    Open := TJSONArray.Create;
    for Name in OpenFiles do
      Open.Add(Name);
    Projects := TJSONArray.Create;
    for Name in OpenProjects(Active) do
      Projects.Add(Name);
    Json := TJSONObject.Create;
    try
      Json.AddPair('pid', TJSONNumber.Create(GetCurrentProcessId));
      Json.AddPair('files', Files);
      Json.AddPair('open', Open);
      Json.AddPair('projects', Projects);
      Json.AddPair('activeProject', Active);
      Text := Json.ToJSON;
    finally
      Json.Free;
    end;
    if Text = FLast then
      Exit;
    // Atomar (Bericht N3): Der Server liest die Liste jederzeit und sah sonst womöglich eine halbe.
    TAtlasDataFile.Write(FFileName, Text);
    FLast := Text;
  except
    // Ohne Liste schützt der Server weiter über den Vergleich mit der Platte; der Grund steht einmal im Protokoll.
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Liste ungespeicherter Dateien', E);
  end;
end;

end.
