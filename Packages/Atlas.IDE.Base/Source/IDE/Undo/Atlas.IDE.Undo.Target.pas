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
  Atlas.IDE.Foundation.Files,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TUndoTargetText = (ProjectHasUnsavedChangesPlease, OpenInTheDesignerThere, ReadOnly, RecycleBinNotReachable);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TUndoTargetText] of string = (
    ('Projekt hat ungespeicherte Änderungen; bitte erst speichern',
     'im Designer offen; dort ändert Atlas nur Ereignis-Zuordnungen und Eigenschaften (%s)',
     'schreibgeschützt',
     'Papierkorb nicht erreichbar'),
    ('project has unsaved changes; please save first',
     'open in the designer; there Atlas only changes event assignments and properties (%s)',
     'read-only',
     'recycle bin not reachable'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TUndoTargetText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

{ TAtlasIdeUndoTarget }

constructor TAtlasIdeUndoTarget.Create;
var
  mHooks: TAtlasUndoDiskHooks;
begin
  inherited Create;
  mHooks.OnAddToProject :=
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
  mHooks.OnRemoveFromProject :=
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
  mHooks.OnRecycle :=
    procedure(AFileName: string)
    begin
      Recycle(AFileName);
    end;
  if not Assigned(FDiskFactory) then
  begin
    raise EInvalidOpException.Create('Atlas: Plattenziel des Änderungsprotokolls nicht eingesetzt.');
  end;
  FDisk := FDiskFactory(mHooks);
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
  mBuffer: IOTAEditBuffer;
  mText: string;
begin
  if not TAtlasIdeFiles.IsProjectFile(AFileName) then
  begin
    mBuffer := TAtlasIdeFiles.BufferOf(AFileName);
    if mBuffer <> nil then
    begin
      AContent := TAtlasIdeFiles.DiskEncoding(AFileName);
      AContent.Text := TAtlasEditorBuffer.Text(mBuffer);
      Exit(True);
    end;
    // Formular im Designer: der Stand des Designers, nicht die Datei.
    if TAtlasIdeForms.CurrentText(AFileName, mText) then
    begin
      AContent := TAtlasIdeFiles.DiskEncoding(AFileName);
      AContent.Text := mText;
      Exit(True);
    end;
  end;
  Result := FDisk.Read(AFileName, AContent);
end;

class procedure TAtlasIdeUndoTarget.WriteBuffer(const ABuffer: IOTAEditBuffer; const AOld, ANew: string);
var
  mChange: TLspTextChange;
  mWriter: IOTAEditWriter;
  mStartOffset, mEndOffset: Integer;
begin
  // Nur der geänderte Bereich, ein Schreiber = ein Rückgängig-Schritt im Puffer.
  mChange := TLspTextChanges.Between(AOld, ANew);
  mStartOffset := TLspTextChanges.OffsetOf(AOld, mChange.StartPos);
  mEndOffset := TLspTextChanges.OffsetOf(AOld, mChange.EndPos);
  mWriter := ABuffer.CreateUndoableWriter;
  mWriter.CopyTo(TEncoding.UTF8.GetByteCount(Copy(AOld, 1, mStartOffset)));
  mWriter.DeleteTo(TEncoding.UTF8.GetByteCount(Copy(AOld, 1, mEndOffset)));
  if mChange.Text <> '' then
  begin
    mWriter.Insert(PAnsiChar(UTF8Encode(mChange.Text)));
  end;
  mWriter := nil;
  // Eigener Schreibvorgang: gemeinsamen Pufferstand verwerfen.
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

/// <summary>Projektdatei: nie als Text; ungespeicherte Projektänderungen nicht verwerfen.</summary>
procedure WriteProjectFile(const ADisk: IAtlasUndoTarget; const AFileName: string;
  const AContent: TAtlasTextFileContent);
var
  mModule: IOTAModule;
  mActions: IOTAActionServices;
begin
  mModule := TAtlasIdeFiles.ProjectModule(AFileName);
  if (mModule <> nil) and TAtlasIdeFiles.ProjectModified(mModule) then
  begin
    raise EInOutError.Create(UiText(TUndoTargetText.ProjectHasUnsavedChangesPlease));
  end;
  ADisk.Write(AFileName, AContent);
  if (mModule <> nil) and Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    mActions.ReloadFile(AFileName);
  end;
end;

/// <summary>Wie beim Umbenennen (#402): Im Designer setzt Atlas Ereignis-Zuordnungen und Eigenschaften (#309).
/// False, wenn das Formular nicht offen ist; sonst geschrieben oder eine Ausnahme mit dem Grund.</summary>
function WriteDesignerForm(const AFileName: string; const AContent: TAtlasTextFileContent): Boolean;
var
  mOld, mReason: string;
  mChanges: TArray<TAtlasFormEventChange>;
  mProperties: TArray<TAtlasFormPropertyChange>;
begin
  Result := TAtlasIdeForms.CurrentText(AFileName, mOld);
  if not Result then
  begin
    Exit;
  end;
  if not TAtlasFormChanges.Diff(mOld, AContent.Text, mChanges, mProperties, mReason) then
  begin
    raise EInOutError.CreateFmt(UiText(TUndoTargetText.OpenInTheDesignerThere), [mReason]);
  end;
  mReason := TAtlasIdeForms.Apply(AFileName, mChanges, mProperties);
  if mReason <> '' then
  begin
    raise EInOutError.Create(mReason);
  end;
end;

procedure TAtlasIdeUndoTarget.Write(const AFileName: string; const AContent: TAtlasTextFileContent);
var
  mBuffer: IOTAEditBuffer;
begin
  if TAtlasIdeFiles.IsProjectFile(AFileName) then
  begin
    WriteProjectFile(FDisk, AFileName, AContent);
    Exit;
  end;
  mBuffer := TAtlasIdeFiles.BufferOf(AFileName);
  if (mBuffer <> nil) and mBuffer.IsReadOnly then
  begin
    raise EInOutError.Create(UiText(TUndoTargetText.ReadOnly));
  end;
  if mBuffer <> nil then
  begin
    WriteBuffer(mBuffer, TAtlasEditorBuffer.Text(mBuffer), AContent.Text);
  end
  else if not WriteDesignerForm(AFileName, AContent) then
  begin
    FDisk.Write(AFileName, AContent);
  end;
end;

procedure TAtlasIdeUndoTarget.CreateFile(const AFileName, AProject: string; const AContent: TAtlasTextFileContent);
begin
  FDisk.CreateFile(AFileName, AProject, AContent);
end;

class procedure TAtlasIdeUndoTarget.CloseFile(const AFileName: string);
var
  mServices: IOTAModuleServices;
  mModule: IOTAModule;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mModule := mServices.FindModule(AFileName);
  // Inhalt ist geprüft (genau der Stand nach der Aktion); ohne Rückfrage schließen.
  if mModule <> nil then
  begin
    mModule.CloseModule(True);
  end;
end;

procedure TAtlasIdeUndoTarget.RemoveFile(const AFileName, AProject: string; AMode: TAtlasNewFilesMode);
begin
  CloseFile(AFileName);
  FDisk.RemoveFile(AFileName, AProject, AMode);
end;

class procedure TAtlasIdeUndoTarget.Recycle(const AFileName: string);
var
  mOperation: TSHFileOpStruct;
  mFrom: string;
begin
  // Doppelt nullterminiert, wie SHFileOperation es verlangt.
  mFrom := AFileName + #0#0;
  FillChar(mOperation, SizeOf(mOperation), 0);
  mOperation.wFunc := FO_DELETE;
  mOperation.pFrom := PChar(mFrom);
  mOperation.fFlags := FOF_ALLOWUNDO or FOF_NOCONFIRMATION or FOF_SILENT or FOF_NOERRORUI;
  if (SHFileOperation(mOperation) <> 0) or mOperation.fAnyOperationsAborted then
  begin
    raise EInOutError.Create(UiText(TUndoTargetText.RecycleBinNotReachable));
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.IDE.Undo.Target', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
