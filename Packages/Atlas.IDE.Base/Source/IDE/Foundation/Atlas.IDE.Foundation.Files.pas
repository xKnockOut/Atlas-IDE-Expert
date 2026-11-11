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
    /// <summary>Datei des aktiven Projekts der IDE; '' ohne Projekt.</summary>
    class function ActiveProjectFile: string; static;
    /// <summary>Zeilen von AFileName: aus dem Editorpuffer, wenn die Datei offen ist, sonst von der Platte;
    /// False, wenn sie fehlt oder nicht lesbar ist.</summary>
    class function ReadLines(const AFileName: string; out ALines: TArray<string>): Boolean; static;
    /// <summary>Projektdatei des Projekts der Projektgruppe, das AFileName enthält; '' wenn keins.</summary>
    class function ProjectOfFile(const AFileName: string): string; static;
    /// <summary>Projekt der Projektgruppe mit der Projektdatei AProjectFile (.dproj); nil, wenn keins.</summary>
    class function GroupProject(const AProjectFile: string): IOTAProject; static;
    /// <summary>Gespeicherte .groupproj der geöffneten Projektgruppe, wenn sie AProjectFile (.dproj) enthält; sonst
    /// '' (auch für die ungespeicherte Vorgabegruppe der IDE).</summary>
    class function GroupOfProject(const AProjectFile: string): string; static;
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
  Atlas.Core.Files.EncodingDefault,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.Text.Lines;

class function TAtlasIdeFiles.ProjectModule(const AFileName: string): IOTAModule;
var
  mServices: IOTAModuleServices;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ModuleCount - 1 do
  begin
    if SameText(mServices.Modules[mIndex].FileName, AFileName) then
    begin
      Exit(mServices.Modules[mIndex]);
    end;
  end;
end;

class function TAtlasIdeFiles.ProjectModified(const AModule: IOTAModule): Boolean;
var
  mProject: IOTAProject;
  mIndex: Integer;
begin
  Result := Supports(AModule, IOTAProject, mProject) and (mProject.ProjectOptions <> nil) and
    mProject.ProjectOptions.ModifiedState;
  for mIndex := 0 to AModule.ModuleFileCount - 1 do
  begin
    if AModule.ModuleFileEditors[mIndex].Modified then
    begin
      Result := True;
    end;
  end;
end;

class function TAtlasIdeFiles.DiskEncoding(const AFileName: string): TAtlasTextFileContent;
begin
  Result := Default(TAtlasTextFileContent);
  Result.Encoding := TAtlasTextEncoding.Utf8Bom;
  try
    if FileExists(AFileName) then
    begin
      Result := TAtlasTextFile.Load(AFileName, TAtlasEncodingDefault.CodePageFor(AFileName));
    end;
  except
    on Exception do
      Result.Encoding := TAtlasTextEncoding.Utf8Bom;
  end;
  Result.Text := '';
end;

class function TAtlasIdeFiles.BufferOf(const AFileName: string): IOTAEditBuffer;
var
  mServices: IOTAModuleServices;
  mIndex, mFileIndex: Integer;
  mModule: IOTAModule;
  mEditor: IOTAEditor;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  // Über die Editoren jedes Moduls: Die .dpr gehört zum Projektmodul (.dproj).
  for mIndex := 0 to mServices.ModuleCount - 1 do
  begin
    mModule := mServices.Modules[mIndex];
    for mFileIndex := 0 to mModule.ModuleFileCount - 1 do
    begin
      mEditor := mModule.ModuleFileEditors[mFileIndex];
      if SameText(mEditor.FileName, AFileName) and Supports(mEditor, IOTAEditBuffer, Result) then
      begin
        Exit;
      end;
    end;
  end;
  Result := nil;
end;

class function TAtlasIdeFiles.ActiveProjectFile: string;
var
  mServices: IOTAModuleServices;
  mProject: IOTAProject;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mProject := mServices.GetActiveProject;
  if mProject <> nil then
  begin
    Result := mProject.FileName;
  end;
end;

class function TAtlasIdeFiles.ReadLines(const AFileName: string; out ALines: TArray<string>): Boolean;
var
  mBuffer: IOTAEditBuffer;
  mText: string;
begin
  ALines := nil;
  mBuffer := TAtlasIdeFiles.BufferOf(AFileName);
  if mBuffer <> nil then
  begin
    mText := TAtlasEditorBuffer.Text(mBuffer);
  end
  else
  begin
    if not FileExists(AFileName) then
    begin
      Exit(False);
    end;
    try
      mText := TAtlasTextFile.Load(AFileName).Text;
    except
      on Exception do
        Exit(False);
    end;
  end;
  ALines := TTextLines.SplitLines(mText);
  Result := True;
end;

class function TAtlasIdeFiles.ProjectOfFile(const AFileName: string): string;
var
  mServices: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mIndex: Integer;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mGroup := mServices.MainProjectGroup;
  if mGroup = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mGroup.ProjectCount - 1 do
  begin
    if mGroup.Projects[mIndex].FindModuleInfo(AFileName) <> nil then
    begin
      Exit(mGroup.Projects[mIndex].FileName);
    end;
  end;
end;

class function TAtlasIdeFiles.GroupProject(const AProjectFile: string): IOTAProject;
var
  mServices: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mIndex: Integer;
begin
  Result := nil;
  if (AProjectFile = '') or not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mGroup := mServices.MainProjectGroup;
  if mGroup = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mGroup.ProjectCount - 1 do
  begin
    if SameFileName(mGroup.Projects[mIndex].FileName, AProjectFile) then
    begin
      Exit(mGroup.Projects[mIndex]);
    end;
  end;
end;

class function TAtlasIdeFiles.GroupOfProject(const AProjectFile: string): string;
var
  mServices: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
begin
  Result := '';
  if (GroupProject(AProjectFile) = nil) or not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mGroup := mServices.MainProjectGroup;
  // Die Vorgabegruppe „ProjectGroup1“ hat keinen Pfad und keine Datei: Eine Zeile kann nicht für sie gelten.
  if (mGroup <> nil) and SameText(ExtractFileExt(mGroup.FileName), '.groupproj') and FileExists(mGroup.FileName) then
  begin
    Result := mGroup.FileName;
  end;
end;

class function TAtlasIdeFiles.ProjectForNewFile(const AFileName: string): string;
var
  mServices: IOTAModuleServices;
  mProject: IOTAProject;
begin
  Result := '';
  if not SameText(ExtractFileExt(AFileName), '.pas') or
    not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mProject := mServices.GetActiveProject;
  if (mProject <> nil) and
    AFileName.StartsWith(IncludeTrailingPathDelimiter(ExtractFilePath(mProject.FileName)), True) then
  begin
    Result := mProject.FileName;
  end;
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
