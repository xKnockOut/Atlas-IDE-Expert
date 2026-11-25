unit Atlas.IDE.Editor.Adapters.EditEnvironment;

// IAtlasEditEnvironment über die Open Tools API (#397, #721): Dateien, offene Puffer und Projekte für den Planer
// der Textänderungen des Servers (Atlas.Core.Editor.WorkspacePlan); gelesen wird über das Ziel des
// Änderungsprotokolls. Erzeugt nur die Kompositionswurzel (TAtlasIdeWorkspaceEdit.EnvironmentFactory). Nur im
// Hauptthread.

interface

uses
  Atlas.Plugin.Files.TextFile,
  Atlas.Core.Undo.Contract,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Plugin.Editor.Contract;

type
  /// <summary>Dateien und Projekte für den Planer aus Sicht der IDE.</summary>
  TAtlasIdeEditEnvironment = class(TInterfacedObject, IAtlasEditEnvironment)
  private
    FTarget: IAtlasUndoTarget;
  public
    constructor Create(const ATarget: IAtlasUndoTarget);
    function Exists(const AFileName: string): Boolean;
    function IsDirectory(const AFileName: string): Boolean;
    function Read(const AFileName: string; out AContent: TAtlasTextFileContent): Boolean;
    function DiskEncoding(const AFileName: string): TAtlasTextFileContent;
    function ProjectOfFile(const AFileName: string): string;
    function ProjectForNewFile(const AFileName: string): string;
    function ProjectLoaded(const AProjectFile: string): Boolean;
  end;

implementation

uses
  System.SysUtils,
  Atlas.ToolsApi.Files.Service;

{ TAtlasIdeEditEnvironment }

constructor TAtlasIdeEditEnvironment.Create(const ATarget: IAtlasUndoTarget);
begin
  inherited Create;
  FTarget := ATarget;
end;

function TAtlasIdeEditEnvironment.Exists(const AFileName: string): Boolean;
begin
  Result := FileExists(AFileName) or (TAtlasIdeFiles.BufferOf(AFileName) <> nil);
end;

function TAtlasIdeEditEnvironment.IsDirectory(const AFileName: string): Boolean;
begin
  Result := DirectoryExists(AFileName);
end;

function TAtlasIdeEditEnvironment.Read(const AFileName: string; out AContent: TAtlasTextFileContent): Boolean;
begin
  Result := FTarget.Read(AFileName, AContent);
end;

function TAtlasIdeEditEnvironment.DiskEncoding(const AFileName: string): TAtlasTextFileContent;
begin
  Result := TAtlasIdeFiles.DiskEncoding(AFileName);
end;

function TAtlasIdeEditEnvironment.ProjectOfFile(const AFileName: string): string;
begin
  Result := TAtlasIdeFiles.ProjectOfFile(AFileName);
end;

function TAtlasIdeEditEnvironment.ProjectForNewFile(const AFileName: string): string;
begin
  Result := TAtlasIdeFiles.ProjectForNewFile(AFileName);
end;

function TAtlasIdeEditEnvironment.ProjectLoaded(const AProjectFile: string): Boolean;
begin
  Result := TAtlasIdeFiles.ProjectModule(AProjectFile) <> nil;
end;

end.
