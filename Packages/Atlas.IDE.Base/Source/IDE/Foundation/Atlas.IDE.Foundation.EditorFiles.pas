unit Atlas.IDE.Foundation.EditorFiles;

// IAtlasEditorFiles über die Open Tools API: Puffer über die Editoren der offenen Module
// (TAtlasIdeFiles.BufferOf, auch die .dpr des Projektmoduls), Speichern über FindModule.
// Dünner Adapter ohne eigene Entscheidung; was mit dem Puffer geschieht, entscheidet Core.

interface

uses
  Atlas.Core.Files.Contract;

type
  TAtlasIdeEditorFiles = class(TInterfacedObject, IAtlasEditorFiles)
  public
    function Buffer(const AFileName: string): TAtlasEditorFile;
    function Save(const AFileName: string): Boolean;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files;

function TAtlasIdeEditorFiles.Buffer(const AFileName: string): TAtlasEditorFile;
var
  mBuffer: IOTAEditBuffer;
begin
  mBuffer := TAtlasIdeFiles.BufferOf(AFileName);
  if mBuffer = nil then
  begin
    Result := TAtlasEditorFile.Closed;
  end
  else
  begin
    Result := TAtlasEditorFile.Opened(TAtlasEditorBuffer.Text(mBuffer), mBuffer.IsModified);
  end;
end;

function TAtlasIdeEditorFiles.Save(const AFileName: string): Boolean;
var
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  mModule := mModules.FindModule(AFileName);
  if mModule <> nil then
  begin
    Result := mModule.Save(False, True);
  end;
end;

end.
