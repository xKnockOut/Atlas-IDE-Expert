unit Atlas.IDE.Foundation.Files;

// Dateien aus Sicht der IDE (#397, #121, #721): offener Puffer, geladenes Projekt, Kodierung auf der Platte.
// Foundation des Plugins (A-09): importiert kein Atlas.IDE-Feature, nur Open Tools API und Atlas.Core.
// Bis S-03b Teil von TAtlasIdeWorkspaceEdit. Nur im Hauptthread.

interface

uses
  ToolsAPI,
  Atlas.Core.Files.TextFile;

type
  TAtlasIdeFiles = class
  public
    /// <summary>Geladenes Modul zu einer Projektdatei (.dproj, .groupproj); nil, wenn keins.</summary>
    class function ProjectModule(const AFileName: string): IOTAModule; static;
    /// <summary>Hat das Projekt ungespeicherte Änderungen (Optionen oder Projektdateien)?</summary>
    class function ProjectModified(const AModule: IOTAModule): Boolean; static;
    /// <summary>Kodierung der Datei auf der Platte (Text leer); UTF-8 mit BOM, wenn sie fehlt oder nicht
    /// lesbar ist (#121).</summary>
    class function DiskEncoding(const AFileName: string): TAtlasTextFileContent; static;
    /// <summary>Puffer der IDE zu einer Datei, auch wenn sie nicht vorn liegt; nil, wenn sie nicht offen ist.</summary>
    class function BufferOf(const AFileName: string): IOTAEditBuffer; static;
    /// <summary>Projektdatei des Projekts der Projektgruppe, das AFileName enthält; '' wenn keins.</summary>
    class function ProjectOfFile(const AFileName: string): string; static;
    /// <summary>Projekt der Projektgruppe mit der Projektdatei AProjectFile (.dproj); nil, wenn keins.</summary>
    class function GroupProject(const AProjectFile: string): IOTAProject; static;
    /// <summary>Aktives Projekt für eine neue Unit (.pas unter dessen Ordner); sonst ''.</summary>
    class function ProjectForNewFile(const AFileName: string): string; static;
    /// <summary>.dproj oder .groupproj?</summary>
    class function IsProjectFile(const AFileName: string): Boolean; static;
    /// <summary>.dpr oder .dpk?</summary>
    class function IsProjectSource(const AFileName: string): Boolean; static;
    /// <summary>.dfm oder .fmx?</summary>
    class function IsFormFile(const AFileName: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Files.EncodingDefault;

class function TAtlasIdeFiles.ProjectModule(const AFileName: string): IOTAModule;
var
  Services: IOTAModuleServices;
  Index: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  for Index := 0 to Services.ModuleCount - 1 do
    if SameText(Services.Modules[Index].FileName, AFileName) then
      Exit(Services.Modules[Index]);
end;

class function TAtlasIdeFiles.ProjectModified(const AModule: IOTAModule): Boolean;
var
  Project: IOTAProject;
  Index: Integer;
begin
  Result := Supports(AModule, IOTAProject, Project) and (Project.ProjectOptions <> nil) and
    Project.ProjectOptions.ModifiedState;
  for Index := 0 to AModule.ModuleFileCount - 1 do
    if AModule.ModuleFileEditors[Index].Modified then
      Result := True;
end;

class function TAtlasIdeFiles.DiskEncoding(const AFileName: string): TAtlasTextFileContent;
begin
  Result := Default(TAtlasTextFileContent);
  Result.Encoding := TAtlasTextEncoding.Utf8Bom;
  try
    if FileExists(AFileName) then
      Result := TAtlasTextFile.Load(AFileName, TAtlasEncodingDefault.CodePageFor(AFileName));
  except
    on Exception do
      Result.Encoding := TAtlasTextEncoding.Utf8Bom;
  end;
  Result.Text := '';
end;

class function TAtlasIdeFiles.BufferOf(const AFileName: string): IOTAEditBuffer;
var
  Services: IOTAModuleServices;
  Index, FileIndex: Integer;
  Module: IOTAModule;
  Editor: IOTAEditor;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  // Über die Editoren jedes Moduls: Die .dpr gehört zum Projektmodul (.dproj).
  for Index := 0 to Services.ModuleCount - 1 do
  begin
    Module := Services.Modules[Index];
    for FileIndex := 0 to Module.ModuleFileCount - 1 do
    begin
      Editor := Module.ModuleFileEditors[FileIndex];
      if SameText(Editor.FileName, AFileName) and Supports(Editor, IOTAEditBuffer, Result) then
        Exit;
    end;
  end;
  Result := nil;
end;

class function TAtlasIdeFiles.ProjectOfFile(const AFileName: string): string;
var
  Services: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Index: Integer;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  Group := Services.MainProjectGroup;
  if Group = nil then
    Exit;
  for Index := 0 to Group.ProjectCount - 1 do
    if Group.Projects[Index].FindModuleInfo(AFileName) <> nil then
      Exit(Group.Projects[Index].FileName);
end;

class function TAtlasIdeFiles.GroupProject(const AProjectFile: string): IOTAProject;
var
  Services: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Index: Integer;
begin
  Result := nil;
  if (AProjectFile = '') or not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  Group := Services.MainProjectGroup;
  if Group = nil then
    Exit;
  for Index := 0 to Group.ProjectCount - 1 do
    if SameFileName(Group.Projects[Index].FileName, AProjectFile) then
      Exit(Group.Projects[Index]);
end;

class function TAtlasIdeFiles.ProjectForNewFile(const AFileName: string): string;
var
  Services: IOTAModuleServices;
  Project: IOTAProject;
begin
  Result := '';
  if not SameText(ExtractFileExt(AFileName), '.pas') or
    not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  Project := Services.GetActiveProject;
  if (Project <> nil) and
    AFileName.StartsWith(IncludeTrailingPathDelimiter(ExtractFilePath(Project.FileName)), True) then
    Result := Project.FileName;
end;

class function TAtlasIdeFiles.IsProjectFile(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dproj') or SameText(ExtractFileExt(AFileName), '.groupproj');
end;

class function TAtlasIdeFiles.IsProjectSource(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dpr') or SameText(ExtractFileExt(AFileName), '.dpk');
end;

class function TAtlasIdeFiles.IsFormFile(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dfm') or SameText(ExtractFileExt(AFileName), '.fmx');
end;

end.
