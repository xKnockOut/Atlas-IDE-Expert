unit Atlas.IDE.Undo.Target;

// Ziel des Änderungsprotokolls in der IDE (#721): schreibt beim Zurücknehmen
// und Wiederherstellen dorthin, wo der aktuelle Stand liegt.
//   - Offene Dateien: über ihren Editorpuffer, ein Schreiber für den ganzen
//     geänderten Bereich, also ein Rückgängig-Schritt je Puffer; danach geht
//     Strg+Z dort wie gewohnt.
//   - Formulare im Designer (#402): über den Designer (Ereignis-Zuordnungen
//     wie beim Umbenennen); andere Änderungen lehnt der Designer ab.
//   - Projektdateien (.dproj, .groupproj): auf die Platte und das Projekt neu
//     laden; mit ungespeicherten Projektänderungen nicht.
//   - Sonst die Platte in der Kodierung der Datei (TAtlasUndoDiskTarget).
// Neue Dateien trägt es aus dem Projekt aus, schließt sie und verschiebt sie in
// den Papierkorb (SHFileOperation mit FOF_ALLOWUNDO) oder löscht sie;
// wiederhergestellte trägt es wieder ins Projekt ein. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Undo.Contract;

type
  TAtlasIdeUndoTarget = class(TInterfacedObject, IAtlasUndoTarget)
  private class var
    FDiskFactory: TAtlasUndoDiskFactory;
  private
    FDisk: IAtlasUndoTarget;
    class procedure WriteBuffer(const ABuffer: IOTAEditBuffer; const AOld, ANew: string); static;
    class function ProjectOf(const AProject: string): IOTAProject; static;
    class procedure CloseFile(const AFileName: string); static;
  public
    constructor Create;
    function Read(const AFileName: string; out AContent: TAtlasTextFileContent): Boolean;
    procedure Write(const AFileName: string; const AContent: TAtlasTextFileContent);
    procedure CreateFile(const AFileName, AProject: string; const AContent: TAtlasTextFileContent);
    procedure RemoveFile(const AFileName, AProject: string; AMode: TAtlasNewFilesMode);
    /// <summary>Datei in den Papierkorb; EInOutError, wenn das nicht geht.</summary>
    class procedure Recycle(const AFileName: string); static;
    /// <summary>Legt das Plattenziel an; setzt die Kompositionswurzel (TAtlasUndoDiskTarget).</summary>
    class property DiskFactory: TAtlasUndoDiskFactory read FDiskFactory write FDiskFactory;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Forms.Changes,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Forms.Designer,
  Atlas.IDE.Foundation.Files;

{ TAtlasIdeUndoTarget }

constructor TAtlasIdeUndoTarget.Create;
var
  Hooks: TAtlasUndoDiskHooks;
begin
  inherited Create;
  Hooks.OnAddToProject :=
    procedure(const AFileName, AProject: string)
    var
      Project: IOTAProject;
    begin
      Project := ProjectOf(AProject);
      if Project <> nil then
      begin
        Project.AddFile(AFileName, SameText(ExtractFileExt(AFileName), '.pas'));
      end;
    end;
  Hooks.OnRemoveFromProject :=
    procedure(const AFileName, AProject: string)
    var
      Project: IOTAProject;
    begin
      Project := ProjectOf(AProject);
      if Project <> nil then
      begin
        Project.RemoveFile(AFileName);
      end;
    end;
  Hooks.OnRecycle :=
    procedure(AFileName: string)
    begin
      Recycle(AFileName);
    end;
  if not Assigned(FDiskFactory) then
  begin
    raise EInvalidOpException.Create('Atlas: Plattenziel des Änderungsprotokolls nicht eingesetzt.');
  end;
  FDisk := FDiskFactory(Hooks);
end;

class function TAtlasIdeUndoTarget.ProjectOf(const AProject: string): IOTAProject;
begin
  Result := nil;
  if AProject <> '' then
  begin
    Supports(TAtlasIdeFiles.ProjectModule(AProject), IOTAProject, Result);
  end;
end;

function TAtlasIdeUndoTarget.Read(const AFileName: string; out AContent: TAtlasTextFileContent): Boolean;
var
  Buffer: IOTAEditBuffer;
  Text: string;
begin
  if not TAtlasIdeFiles.IsProjectFile(AFileName) then
  begin
    Buffer := TAtlasIdeFiles.BufferOf(AFileName);
    if Buffer <> nil then
    begin
      AContent := TAtlasIdeFiles.DiskEncoding(AFileName);
      AContent.Text := TAtlasEditorBuffer.Text(Buffer);
      Exit(True);
    end;
    // Formular im Designer: der Stand des Designers, nicht die Datei.
    if TAtlasIdeForms.CurrentText(AFileName, Text) then
    begin
      AContent := TAtlasIdeFiles.DiskEncoding(AFileName);
      AContent.Text := Text;
      Exit(True);
    end;
  end;
  Result := FDisk.Read(AFileName, AContent);
end;

class procedure TAtlasIdeUndoTarget.WriteBuffer(const ABuffer: IOTAEditBuffer; const AOld, ANew: string);
var
  Change: TLspTextChange;
  Writer: IOTAEditWriter;
  StartOffset, EndOffset: Integer;
begin
  // Nur der geänderte Bereich, ein Schreiber = ein Rückgängig-Schritt im Puffer.
  Change := TLspTextChanges.Between(AOld, ANew);
  StartOffset := TLspTextChanges.OffsetOf(AOld, Change.StartPos);
  EndOffset := TLspTextChanges.OffsetOf(AOld, Change.EndPos);
  Writer := ABuffer.CreateUndoableWriter;
  Writer.CopyTo(TEncoding.UTF8.GetByteCount(Copy(AOld, 1, StartOffset)));
  Writer.DeleteTo(TEncoding.UTF8.GetByteCount(Copy(AOld, 1, EndOffset)));
  if Change.Text <> '' then
  begin
    Writer.Insert(PAnsiChar(UTF8Encode(Change.Text)));
  end;
  Writer := nil;
  // Eigener Schreibvorgang: gemeinsamen Pufferstand verwerfen (P-04).
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

procedure TAtlasIdeUndoTarget.Write(const AFileName: string; const AContent: TAtlasTextFileContent);
var
  Buffer: IOTAEditBuffer;
  Module: IOTAModule;
  Actions: IOTAActionServices;
  Old, Reason: string;
  FormChanges: TArray<TAtlasFormEventChange>;
  FormProperties: TArray<TAtlasFormPropertyChange>;
begin
  if TAtlasIdeFiles.IsProjectFile(AFileName) then
  begin
    // Projektdatei: nie als Text; ungespeicherte Projektänderungen nicht verwerfen.
    Module := TAtlasIdeFiles.ProjectModule(AFileName);
    if (Module <> nil) and TAtlasIdeFiles.ProjectModified(Module) then
    begin
      raise EInOutError.Create('Projekt hat ungespeicherte Änderungen; bitte erst speichern');
    end;
    FDisk.Write(AFileName, AContent);
    if (Module <> nil) and Supports(BorlandIDEServices, IOTAActionServices, Actions) then
    begin
      Actions.ReloadFile(AFileName);
    end;
    Exit;
  end;
  Buffer := TAtlasIdeFiles.BufferOf(AFileName);
  if Buffer <> nil then
  begin
    if Buffer.IsReadOnly then
    begin
      raise EInOutError.Create('schreibgeschützt');
    end;
    WriteBuffer(Buffer, TAtlasEditorBuffer.Text(Buffer), AContent.Text);
    Exit;
  end;
  if TAtlasIdeForms.CurrentText(AFileName, Old) then
  begin
    // Wie beim Umbenennen (#402): Im Designer setzt Atlas Ereignis-Zuordnungen und Eigenschaften (#309).
    if not TAtlasFormChanges.Diff(Old, AContent.Text, FormChanges, FormProperties, Reason) then
    begin
      raise EInOutError.CreateFmt('im Designer offen; dort ändert Atlas nur Ereignis-Zuordnungen und ' +
        'Eigenschaften (%s)', [Reason]);
    end;
    Reason := TAtlasIdeForms.Apply(AFileName, FormChanges, FormProperties);
    if Reason <> '' then
    begin
      raise EInOutError.Create(Reason);
    end;
    Exit;
  end;
  FDisk.Write(AFileName, AContent);
end;

procedure TAtlasIdeUndoTarget.CreateFile(const AFileName, AProject: string; const AContent: TAtlasTextFileContent);
begin
  FDisk.CreateFile(AFileName, AProject, AContent);
end;

class procedure TAtlasIdeUndoTarget.CloseFile(const AFileName: string);
var
  Services: IOTAModuleServices;
  Module: IOTAModule;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
  begin
    Exit;
  end;
  Module := Services.FindModule(AFileName);
  // Inhalt ist geprüft (genau der Stand nach der Aktion); ohne Rückfrage schließen.
  if Module <> nil then
  begin
    Module.CloseModule(True);
  end;
end;

procedure TAtlasIdeUndoTarget.RemoveFile(const AFileName, AProject: string; AMode: TAtlasNewFilesMode);
begin
  CloseFile(AFileName);
  FDisk.RemoveFile(AFileName, AProject, AMode);
end;

class procedure TAtlasIdeUndoTarget.Recycle(const AFileName: string);
var
  Operation: TSHFileOpStruct;
  From: string;
begin
  // Doppelt nullterminiert, wie SHFileOperation es verlangt.
  From := AFileName + #0#0;
  FillChar(Operation, SizeOf(Operation), 0);
  Operation.wFunc := FO_DELETE;
  Operation.pFrom := PChar(From);
  Operation.fFlags := FOF_ALLOWUNDO or FOF_NOCONFIRMATION or FOF_SILENT or FOF_NOERRORUI;
  if (SHFileOperation(Operation) <> 0) or Operation.fAnyOperationsAborted then
  begin
    raise EInOutError.Create('Papierkorb nicht erreichbar');
  end;
end;

end.
