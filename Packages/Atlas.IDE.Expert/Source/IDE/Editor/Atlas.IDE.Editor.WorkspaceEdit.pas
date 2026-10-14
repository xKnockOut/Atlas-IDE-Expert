unit Atlas.IDE.Editor.WorkspaceEdit;

// Textänderungen des Servers in die Puffer der IDE (#397), nicht auf die
// Platte: Sonst überschreibt die IDE sie beim nächsten Speichern.
//   - Offene Dateien: je Datei ein Schreiber der IDE (CreateUndoableWriter),
//     also ein Rückgängig-Schritt je Datei.
//   - Nicht geöffnete Dateien: nach der Einstellung „Für Änderungen öffnen“
//     im Editor öffnen (Vorgabe) oder direkt auf die Platte schreiben, in
//     ihrer bisherigen Kodierung (TAtlasTextFile).
//   - Projektdateien (.dproj, .groupproj, etwa von /define): nie als Text
//     öffnen, sondern auf die Platte schreiben und das geladene Projekt neu
//     laden. Hat es ungespeicherte Änderungen, ändert Atlas nichts.
// Erst werden alle Dateien geprüft (Puffer vorhanden, Positionen gültig,
// keine Überlappung); schlägt eine Prüfung fehl, ändert Atlas nichts.
// Nur im Hauptthread aufrufen.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Lsp.WorkspaceEdits;

type
  TAtlasWorkspaceEditResult = record
    Files: Integer;
    Edits: Integer;
    /// <summary>Davon direkt auf die Platte geschrieben.</summary>
    Written: Integer;
    /// <summary>Leer bei Erfolg, sonst warum nichts geändert wurde.</summary>
    Error: string;
  end;

  TAtlasIdeWorkspaceEdit = class
  private
    class procedure WriteBuffer(const ABuffer: IOTAEditBuffer; const AText: string;
      const ARanges: TArray<TLspTextRange>); static;
    class function ProjectModule(const AFileName: string): IOTAModule; static;
    class function ProjectModified(const AModule: IOTAModule): Boolean; static;
  public
    /// <summary>Puffer der IDE zu einer Datei, auch wenn sie nicht vorn liegt; nil, wenn sie nicht offen ist.</summary>
    class function BufferOf(const AFileName: string): IOTAEditBuffer; static;
    /// <summary>.dproj oder .groupproj?</summary>
    class function IsProjectFile(const AFileName: string): Boolean; static;
    /// <summary>Wendet AEdit an. AOpenUnopened: nicht geöffnete Dateien im Editor öffnen,
    /// sonst auf die Platte schreiben.</summary>
    class function Apply(const AEdit: TLspWorkspaceEdit; AOpenUnopened: Boolean): TAtlasWorkspaceEditResult; static;
  end;

implementation

uses
  Atlas.Core.Files.TextFile,
  Atlas.IDE.Editor.Buffer;

type
  TPlannedFile = record
    FileName: string;
    Buffer: IOTAEditBuffer;
    Text: string;
    Disk: TAtlasTextFileContent;
    Ranges: TArray<TLspTextRange>;
    /// <summary>Geladenes Projekt zur Projektdatei; nach dem Schreiben neu laden.</summary>
    Project: IOTAModule;
  end;

class function TAtlasIdeWorkspaceEdit.IsProjectFile(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dproj') or SameText(ExtractFileExt(AFileName), '.groupproj');
end;

class function TAtlasIdeWorkspaceEdit.ProjectModule(const AFileName: string): IOTAModule;
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

class function TAtlasIdeWorkspaceEdit.ProjectModified(const AModule: IOTAModule): Boolean;
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

class function TAtlasIdeWorkspaceEdit.BufferOf(const AFileName: string): IOTAEditBuffer;
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

class procedure TAtlasIdeWorkspaceEdit.WriteBuffer(const ABuffer: IOTAEditBuffer; const AText: string;
  const ARanges: TArray<TLspTextRange>);
var
  Writer: IOTAEditWriter;
  Range: TLspTextRange;
  StartByte, EndByte: Integer;
begin
  // Ein Schreiber = ein Rückgängig-Schritt. Er schreibt nur vorwärts; die Bereiche sind aufsteigend.
  Writer := ABuffer.CreateUndoableWriter;
  for Range in ARanges do
  begin
    StartByte := TEncoding.UTF8.GetByteCount(Copy(AText, 1, Range.StartOffset));
    EndByte := TEncoding.UTF8.GetByteCount(Copy(AText, 1, Range.EndOffset));
    Writer.CopyTo(StartByte);
    Writer.DeleteTo(EndByte);
    if Range.NewText <> '' then
      Writer.Insert(PAnsiChar(UTF8Encode(Range.NewText)));
  end;
  Writer := nil;
end;

class function TAtlasIdeWorkspaceEdit.Apply(const AEdit: TLspWorkspaceEdit; AOpenUnopened: Boolean): TAtlasWorkspaceEditResult;
var
  Actions: IOTAActionServices;
  Plans: TArray<TPlannedFile>;
  Plan: TPlannedFile;
  FileEdits: TLspFileEdits;
begin
  Result := Default(TAtlasWorkspaceEditResult);
  Plans := nil;
  // 1. Prüfen: alles lesen und ordnen, noch nichts ändern.
  for FileEdits in AEdit.Files do
  begin
    Plan := Default(TPlannedFile);
    Plan.FileName := FileEdits.FileName;
    try
      if IsProjectFile(FileEdits.FileName) then
      begin
        // Projektdatei: nie als Text öffnen; ungespeicherte Projektänderungen nicht verwerfen.
        Plan.Project := ProjectModule(FileEdits.FileName);
        if (Plan.Project <> nil) and ProjectModified(Plan.Project) then
          raise ELspEditError.Create('Projekt hat ungespeicherte Änderungen; bitte erst speichern');
      end
      else
      begin
        Plan.Buffer := BufferOf(FileEdits.FileName);
        if (Plan.Buffer = nil) and AOpenUnopened and FileExists(FileEdits.FileName) and
          Supports(BorlandIDEServices, IOTAActionServices, Actions) and Actions.OpenFile(FileEdits.FileName) then
          Plan.Buffer := BufferOf(FileEdits.FileName);
      end;
      if Plan.Buffer <> nil then
      begin
        if Plan.Buffer.IsReadOnly then
          raise ELspEditError.Create('schreibgeschützt');
        Plan.Text := TAtlasEditorBuffer.Text(Plan.Buffer);
        Plan.Ranges := TLspEdits.Ordered(Plan.Text, FileEdits.Edits);
      end
      else
      begin
        if not FileExists(FileEdits.FileName) then
          raise ELspEditError.Create('Datei nicht gefunden');
        Plan.Disk := TAtlasTextFile.Load(FileEdits.FileName);
        Plan.Disk.Text := TLspEdits.Apply(Plan.Disk.Text, FileEdits.Edits);
      end;
    except
      on E: Exception do
      begin
        Result.Error := Format('%s: %s', [ExtractFileName(FileEdits.FileName), E.Message]);
        Exit;
      end;
    end;
    Plans := Plans + [Plan];
    Inc(Result.Edits, Length(FileEdits.Edits));
  end;
  // 2. Anwenden.
  for Plan in Plans do
  begin
    try
      if Plan.Buffer <> nil then
        WriteBuffer(Plan.Buffer, Plan.Text, Plan.Ranges)
      else
      begin
        TAtlasTextFile.Save(Plan.FileName, Plan.Disk);
        Inc(Result.Written);
        // Geladenes Projekt neu einlesen, sonst schreibt die IDE beim Speichern ihren alten Stand zurück.
        if (Plan.Project <> nil) and Supports(BorlandIDEServices, IOTAActionServices, Actions) then
          Actions.ReloadFile(Plan.FileName);
      end;
    except
      on E: Exception do
      begin
        // Was schon geschrieben ist, bleibt (je Datei rückgängig zu machen); der Rest fehlt.
        Result.Error := Format('%s: %s', [ExtractFileName(Plan.FileName), E.Message]);
        Exit;
      end;
    end;
    Inc(Result.Files);
  end;
end;

end.
