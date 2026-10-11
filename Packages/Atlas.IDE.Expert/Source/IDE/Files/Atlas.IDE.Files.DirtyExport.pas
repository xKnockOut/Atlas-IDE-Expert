unit Atlas.IDE.Files.DirtyExport;

// Ungespeicherte Dateien der IDE für schreibende MCP-Werkzeuge (#61, #99):
// Jede Sekunde sammelt das Plugin die geänderten, nicht gespeicherten Dateien
// aller offenen Module und schreibt sie bei Änderung nach
// %LOCALAPPDATA%\Atlas\editor-dirty-<pid>.json ({"pid": …, "files": [...]}).
// Der MCP-Server bricht Schreibaufrufe ab, die eine dieser Dateien betreffen.
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
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  System.JSON,
  ToolsAPI;

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

procedure TAtlasDirtyExport.Tick(Sender: TObject);
var
  Json: TJSONObject;
  Files: TJSONArray;
  Name, Text: string;
begin
  try
    Files := TJSONArray.Create;
    for Name in ModifiedFiles do
      Files.Add(Name);
    Json := TJSONObject.Create;
    try
      Json.AddPair('pid', TJSONNumber.Create(GetCurrentProcessId));
      Json.AddPair('files', Files);
      Text := Json.ToJSON;
    finally
      Json.Free;
    end;
    if Text = FLast then
      Exit;
    ForceDirectories(ExtractFilePath(FFileName));
    TFile.WriteAllText(FFileName, Text, TEncoding.UTF8);
    FLast := Text;
  except
    // Ohne Liste schützt der Server weiter über den Vergleich mit der Platte.
    on Exception do
      ;
  end;
end;

end.
