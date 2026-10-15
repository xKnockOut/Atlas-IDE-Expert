unit Atlas.IDE.Editor.WorkspaceEdit;

// Textänderungen des Servers in die Puffer der IDE (#397), nicht auf die
// Platte: Sonst überschreibt die IDE sie beim nächsten Speichern.
//   - Offene Dateien: je Datei ein Schreiber der IDE (CreateUndoableWriter),
//     also ein Rückgängig-Schritt je Datei.
//   - Nicht geöffnete Dateien: nach der Einstellung „Für Änderungen öffnen“
//     im Editor öffnen (Vorgabe) oder direkt auf die Platte schreiben, in
//     ihrer bisherigen Kodierung (TAtlasTextFile, Vorgabe "encoding" aus
//     atlas.json über TAtlasEncodingDefault, #121).
//   - Formulare, die im Designer offen sind (#402): nie auf die Platte, sonst
//     überschreibt der Designer die Änderung beim Speichern. Geänderte
//     Ereignis-Zuordnungen setzt TAtlasIdeForms im Designer, und zwar nach den
//     Units, damit die umbenannten Handler dort schon stehen; andere
//     Änderungen an offenen Formularen lehnt Atlas ab. Nicht geöffnete
//     Formulare öffnet Atlas nicht, sondern schreibt die Datei; ein binär
//     gespeichertes Formular lehnt es ab (#121).
//   - Projektdateien (.dproj, .groupproj, etwa von /define): nie als Text
//     öffnen, sondern auf die Platte schreiben und das geladene Projekt neu
//     laden. Hat es ungespeicherte Änderungen, ändert Atlas nichts.
// Erst werden alle Dateien geprüft (Puffer vorhanden, Positionen gültig,
// keine Überlappung); schlägt eine Prüfung fehl, ändert Atlas nichts.
// Dateioperationen des Servers (#721: anlegen, umbenennen, löschen) plant
// Atlas mit: Änderungen an einer neuen Datei gehen in ihren Inhalt, eine neue
// Unit kommt ins aktive Projekt (wenn sie unter dessen Ordner liegt), eine
// umbenannte bleibt in ihrem Projekt. Ändert das Edit selbst eine .dproj
// (neue Testunit, #274), kommt die neue Unit in dieses Projekt: Ist es
// geladen, trägt die IDE sie ein und Atlas lässt die Änderungen an .dproj und
// .dpr weg; sonst schreibt Atlas beide auf die Platte. Eine .dpr oder .dpk
// öffnet Atlas nie im Editor, das würde das Projekt öffnen. Ausgeführt wird erst nach allen
// Prüfungen: neue Dateien anlegen, dann die Textänderungen, zuletzt alte
// Dateien schließen, austragen und in den Papierkorb verschieben.
// Jede Änderung mehrerer Dateien landet als ein Satz im Änderungsprotokoll
// (#721, TAtlasIdeUndo) mit dem Inhalt vorher und nachher und der Kodierung
// der Datei; „Letzte Atlas-Änderung zurücknehmen“ nimmt sie in allen Dateien
// auf einmal zurück. Die Aktion beschreibt AAction.
// Nur im Hauptthread aufrufen.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Files.TextFile,
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
    /// <summary>Aktueller Text: offener Puffer, sonst die Datei auf der Platte; '' wenn sie fehlt (#400).</summary>
    class function CurrentText(const AFileName: string): string; static;
    /// <summary>Projektdatei des Projekts der Projektgruppe, das AFileName enthält; '' wenn keins.</summary>
    class function ProjectOfFile(const AFileName: string): string; static;
    /// <summary>Aktives Projekt für eine neue Unit (.pas unter dessen Ordner); sonst ''.</summary>
    class function ProjectForNewFile(const AFileName: string): string; static;
    /// <summary>.dproj oder .groupproj?</summary>
    class function IsProjectFile(const AFileName: string): Boolean; static;
    /// <summary>.dpr oder .dpk?</summary>
    class function IsProjectSource(const AFileName: string): Boolean; static;
    /// <summary>Wendet AEdit an. AOpenUnopened: nicht geöffnete Dateien im Editor öffnen,
    /// sonst auf die Platte schreiben. AAction: Name der Aktion im Änderungsprotokoll (#721).</summary>
    class function Apply(const AEdit: TLspWorkspaceEdit; AOpenUnopened: Boolean;
      const AAction: string): TAtlasWorkspaceEditResult; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Core.Files.EncodingDefault,
  Atlas.Core.Forms.Changes,
  Atlas.Core.Undo.Contract,
  Atlas.IDE.Editor.Buffer,
  Atlas.IDE.Forms.Designer,
  Atlas.IDE.Undo.Changes,
  Atlas.IDE.Undo.Target;

type
  TPlannedFile = record
    FileName: string;
    Buffer: IOTAEditBuffer;
    Text: string;
    Disk: TAtlasTextFileContent;
    Ranges: TArray<TLspTextRange>;
    /// <summary>Formular im Designer (#402): Ereignis-Zuordnungen statt Text.</summary>
    IsForm: Boolean;
    FormChanges: TArray<TAtlasFormEventChange>;
    /// <summary>Geladenes Projekt zur Projektdatei; nach dem Schreiben neu laden.</summary>
    Project: IOTAModule;
    /// <summary>Für das Änderungsprotokoll (#721): Inhalt vorher und nachher.</summary>
    Change: TAtlasFileChange;
  end;

  /// <summary>Datei, die angelegt (Created) oder entfernt (Deleted) wird (#721).</summary>
  TPlannedOperation = record
    Kind: TAtlasFileChangeKind;
    FileName: string;
    Project: string;
    /// <summary>Created: Inhalt nach allen Änderungen; Deleted: Inhalt vorher.</summary>
    Content: TAtlasTextFileContent;
  end;

  /// <summary>Vorhandene Datei, die eine Operation ersetzt: Änderungen gelten für Base.</summary>
  TReplacedFile = record
    FileName: string;
    Base: string;
  end;

function KeyOf(const AFileName: string): string;
begin
  Result := AnsiLowerCase(AFileName);
end;

function IsFormFile(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dfm') or SameText(ExtractFileExt(AFileName), '.fmx');
end;

class function TAtlasIdeWorkspaceEdit.CurrentText(const AFileName: string): string;
var
  Buffer: IOTAEditBuffer;
begin
  Result := '';
  Buffer := BufferOf(AFileName);
  if Buffer <> nil then
    Exit(TAtlasEditorBuffer.Text(Buffer));
  // Offenes Formular: der Stand des Designers, wie ihn der Server kennt (#402).
  if TAtlasIdeForms.SentText(AFileName, Result) then
    Exit;
  try
    if FileExists(AFileName) then
      Result := TAtlasTextFile.Load(AFileName, TAtlasEncodingDefault.CodePageFor(AFileName)).Text;
  except
    on Exception do
      Result := '';
  end;
end;

class function TAtlasIdeWorkspaceEdit.DiskEncoding(const AFileName: string): TAtlasTextFileContent;
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

class function TAtlasIdeWorkspaceEdit.IsProjectFile(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dproj') or SameText(ExtractFileExt(AFileName), '.groupproj');
end;

class function TAtlasIdeWorkspaceEdit.IsProjectSource(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dpr') or SameText(ExtractFileExt(AFileName), '.dpk');
end;

class function TAtlasIdeWorkspaceEdit.ProjectOfFile(const AFileName: string): string;
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

class function TAtlasIdeWorkspaceEdit.ProjectForNewFile(const AFileName: string): string;
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

class function TAtlasIdeWorkspaceEdit.Apply(const AEdit: TLspWorkspaceEdit; AOpenUnopened: Boolean;
  const AAction: string): TAtlasWorkspaceEditResult;
var
  Actions: IOTAActionServices;
  Target: IAtlasUndoTarget;
  Plans: TArray<TPlannedFile>;
  Plan: TPlannedFile;
  Targets: TArray<TLspFileEdits>;
  FileEdits: TLspFileEdits;
  Operation: TLspFileOperation;
  Creates, Removes: TList<TPlannedOperation>;
  Pending: TDictionary<string, Integer>;
  Gone: TDictionary<string, Integer>;
  Replaced: TDictionary<string, TReplacedFile>;
  Planned: TPlannedOperation;
  Replacement: TReplacedFile;
  Existing: TReplacedFile;
  Recorded: TArray<TAtlasFileChange>;
  Sent, Base, FinalText: string;
  HasBase: Boolean;
  Index: Integer;
  Edit: TLspWorkspaceEdit;
  Owner: string;
  OwnerLoaded: Boolean;

  function Content(const AFileName, AText: string): TAtlasTextFileContent;
  begin
    Result := DiskEncoding(AFileName);
    Result.Text := AText;
  end;

  procedure Remember;
  begin
    // Auch nach einem Fehler: Was schon geschrieben ist, lässt sich so gemeinsam zurücknehmen.
    TAtlasIdeUndo.Add(AAction, Recorded);
  end;

  function Exists(const AFileName: string): Boolean;
  begin
    Result := Pending.ContainsKey(KeyOf(AFileName)) or
      ((FileExists(AFileName) or (BufferOf(AFileName) <> nil)) and not Gone.ContainsKey(KeyOf(AFileName)));
  end;

  function ReadCurrent(const AFileName: string): TAtlasTextFileContent;
  var
    Item: TReplacedFile;
  begin
    if Pending.ContainsKey(KeyOf(AFileName)) then
      Exit(Creates[Pending[KeyOf(AFileName)]].Content);
    if not Target.Read(AFileName, Result) then
      raise ELspEditError.Create('Datei nicht gefunden');
    if Replaced.TryGetValue(KeyOf(AFileName), Item) then
      Result.Text := Item.Base;
  end;

  procedure Replace(const AFileName, ABase: string);
  var
    Item: TReplacedFile;
  begin
    Item.FileName := AFileName;
    Item.Base := ABase;
    Replaced.AddOrSetValue(KeyOf(AFileName), Item);
  end;

  procedure AddCreate(const AFileName, AProject: string; const AContent: TAtlasTextFileContent);
  var
    Created: TPlannedOperation;
  begin
    Created := Default(TPlannedOperation);
    Created.Kind := TAtlasFileChangeKind.Created;
    Created.FileName := AFileName;
    Created.Project := AProject;
    Created.Content := AContent;
    Pending.AddOrSetValue(KeyOf(AFileName), Creates.Add(Created));
  end;

  procedure AddRemove(const AFileName: string);
  var
    Removed: TPlannedOperation;
  begin
    Removed := Default(TPlannedOperation);
    Removed.Kind := TAtlasFileChangeKind.Deleted;
    Removed.FileName := AFileName;
    Removed.Project := ProjectOfFile(AFileName);
    Removed.Content := ReadCurrent(AFileName);
    Gone.AddOrSetValue(KeyOf(AFileName), Removes.Add(Removed));
    Replaced.Remove(KeyOf(AFileName));
  end;

  procedure DropCreate(const AFileName: string);
  var
    Dropped: TPlannedOperation;
  begin
    // Angelegt und im selben Edit wieder gelöscht bzw. umbenannt: die Anlage entfällt.
    Dropped := Creates[Pending[KeyOf(AFileName)]];
    Dropped.FileName := '';
    Creates[Pending[KeyOf(AFileName)]] := Dropped;
    Pending.Remove(KeyOf(AFileName));
  end;

  procedure PlanCreate(const AFileName, AProject: string; const AContent: TAtlasTextFileContent);
  var
    Revived: TPlannedOperation;
  begin
    if Gone.ContainsKey(KeyOf(AFileName)) then
    begin
      // Vorher im selben Edit entfernt: Die Datei bleibt und bekommt den neuen Inhalt.
      Revived := Removes[Gone[KeyOf(AFileName)]];
      Revived.FileName := '';
      Removes[Gone[KeyOf(AFileName)]] := Revived;
      Gone.Remove(KeyOf(AFileName));
      Replace(AFileName, AContent.Text);
    end
    else
      AddCreate(AFileName, AProject, AContent);
  end;

  /// <summary>Ziel existiert schon: True = ersetzen, False = Operation auslassen.</summary>
  function MayReplace(const AFileName: string; const AOperation: TLspFileOperation): Boolean;
  begin
    if AOperation.Overwrite then
      Exit(True);
    if AOperation.IgnoreIfExists then
      Exit(False);
    raise ELspEditError.CreateFmt('%s existiert bereits', [ExtractFileName(AFileName)]);
  end;

  procedure SetTarget(const AFileName, AProject: string; const AContent: TAtlasTextFileContent);
  var
    Changed: TPlannedOperation;
  begin
    // Neuer Inhalt für ein Ziel, das existiert (Überschreiben) oder neu ist.
    if Pending.ContainsKey(KeyOf(AFileName)) then
    begin
      Changed := Creates[Pending[KeyOf(AFileName)]];
      Changed.Content.Text := AContent.Text;
      Creates[Pending[KeyOf(AFileName)]] := Changed;
    end
    else if Exists(AFileName) then
      Replace(AFileName, AContent.Text)
    else
      PlanCreate(AFileName, AProject, AContent);
  end;

  /// <summary>Projekt für eine neue Datei: das des Edits (#274) oder das aktive.</summary>
  function NewFileProject(const AFileName: string): string;
  begin
    if Owner = '' then
      Result := ProjectForNewFile(AFileName)
    else if OwnerLoaded and SameText(ExtractFileExt(AFileName), '.pas') then
      Result := Owner
    else
      Result := '';
  end;

  procedure PlanOperation(const AOperation: TLspFileOperation);
  var
    Source: TAtlasTextFileContent;
    Project: string;
  begin
    case AOperation.Kind of
      TLspFileOperationKind.Create:
        begin
          if Exists(AOperation.FileName) and not MayReplace(AOperation.FileName, AOperation) then
            Exit;
          SetTarget(AOperation.FileName, NewFileProject(AOperation.FileName), Content(AOperation.FileName, ''));
        end;
      TLspFileOperationKind.Rename:
        begin
          if not Exists(AOperation.FileName) then
            raise ELspEditError.Create('Datei nicht gefunden');
          if SameText(AOperation.FileName, AOperation.NewFileName) then
            Exit;
          if Exists(AOperation.NewFileName) and not MayReplace(AOperation.NewFileName, AOperation) then
            Exit;
          Source := ReadCurrent(AOperation.FileName);
          if Pending.ContainsKey(KeyOf(AOperation.FileName)) then
          begin
            Project := Creates[Pending[KeyOf(AOperation.FileName)]].Project;
            DropCreate(AOperation.FileName);
          end
          else
          begin
            Project := ProjectOfFile(AOperation.FileName);
            AddRemove(AOperation.FileName);
          end;
          // Kodierung und Zeilenenden wandern mit (#121); das Projekt bleibt.
          SetTarget(AOperation.NewFileName, Project, Source);
        end;
      TLspFileOperationKind.Delete:
        begin
          if Pending.ContainsKey(KeyOf(AOperation.FileName)) then
          begin
            DropCreate(AOperation.FileName);
            Exit;
          end;
          if DirectoryExists(AOperation.FileName) then
            raise ELspEditError.Create('Ordner löscht Atlas nicht');
          if not Exists(AOperation.FileName) then
          begin
            if AOperation.IgnoreIfNotExists then
              Exit;
            raise ELspEditError.Create('Datei nicht gefunden');
          end;
          AddRemove(AOperation.FileName);
        end;
    end;
  end;

begin
  Recorded := nil;
  Result := Default(TAtlasWorkspaceEditResult);
  Plans := nil;
  Target := TAtlasIdeUndoTarget.Create;
  Creates := TList<TPlannedOperation>.Create;
  Removes := TList<TPlannedOperation>.Create;
  Pending := TDictionary<string, Integer>.Create;
  Gone := TDictionary<string, Integer>.Create;
  Replaced := TDictionary<string, TReplacedFile>.Create;
  try
    Edit := AEdit;
    Owner := Edit.ProjectFile;
    OwnerLoaded := (Owner <> '') and (Length(Edit.Operations) > 0) and (ProjectModule(Owner) <> nil);
    if OwnerLoaded then
      Edit := Edit.WithoutProject(Owner);
    // 1. Prüfen: Dateioperationen und alle Texte planen, noch nichts ändern.
    for Operation in Edit.Operations do
      try
        PlanOperation(Operation);
      except
        on E: Exception do
        begin
          Result.Error := Format('%s: %s', [ExtractFileName(Operation.FileName), E.Message]);
          Exit;
        end;
      end;
    Targets := nil;
    for FileEdits in Edit.Files do
    begin
      if Gone.ContainsKey(KeyOf(FileEdits.FileName)) then
      begin
        Result.Error := Format('%s: %s', [ExtractFileName(FileEdits.FileName), 'wird gelöscht']);
        Exit;
      end;
      if Pending.ContainsKey(KeyOf(FileEdits.FileName)) then
      begin
        // Neue Datei: Die Änderungen gehen in ihren Inhalt.
        Index := Pending[KeyOf(FileEdits.FileName)];
        Planned := Creates[Index];
        try
          Planned.Content.Text := TLspEdits.Apply(Planned.Content.Text, FileEdits.Edits);
        except
          on E: Exception do
          begin
            Result.Error := Format('%s: %s', [ExtractFileName(FileEdits.FileName), E.Message]);
            Exit;
          end;
        end;
        Creates[Index] := Planned;
        Inc(Result.Edits, Length(FileEdits.Edits));
        Continue;
      end;
      Targets := Targets + [FileEdits];
    end;
    // Ersetzte Dateien ohne eigene Textänderungen bekommen den neuen Inhalt ebenso.
    for Existing in Replaced.Values do
    begin
      HasBase := False;
      for FileEdits in Targets do
        if SameText(FileEdits.FileName, Existing.FileName) then
          HasBase := True;
      if not HasBase then
      begin
        FileEdits := Default(TLspFileEdits);
        FileEdits.FileName := Existing.FileName;
        Targets := Targets + [FileEdits];
      end;
    end;
    for FileEdits in Targets do
    begin
      Plan := Default(TPlannedFile);
      Plan.FileName := FileEdits.FileName;
      HasBase := Replaced.TryGetValue(KeyOf(FileEdits.FileName), Replacement);
      Base := Replacement.Base;
      if not IsProjectFile(FileEdits.FileName) then
        Plan.Buffer := BufferOf(FileEdits.FileName);
      if (Plan.Buffer = nil) and IsFormFile(FileEdits.FileName) and TAtlasIdeForms.IsOpen(FileEdits.FileName) then
      begin
        Plan.IsForm := True;
        if HasBase then
          Result.Error := 'im Designer offen; dort ändert Atlas nur Ereignis-Zuordnungen'
        else
          Result.Error := TAtlasIdeForms.Check(FileEdits.FileName, FileEdits.Edits, Plan.FormChanges);
        if Result.Error <> '' then
        begin
          Result.Error := Format('%s: %s', [ExtractFileName(FileEdits.FileName), Result.Error]);
          Exit;
        end;
        // Check hat den Text schon geprüft; vorher ist der Stand, den der Server kennt.
        if TAtlasIdeForms.SentText(FileEdits.FileName, Sent) then
          Plan.Change := TAtlasFileChange.Modified(FileEdits.FileName, Content(FileEdits.FileName, Sent),
            Content(FileEdits.FileName, TLspEdits.Apply(Sent, FileEdits.Edits)));
        Plans := Plans + [Plan];
        Inc(Result.Edits, Length(FileEdits.Edits));
        Continue;
      end;
      try
        if IsProjectFile(FileEdits.FileName) then
        begin
          // Projektdatei: nie als Text öffnen; ungespeicherte Projektänderungen nicht verwerfen.
          Plan.Project := ProjectModule(FileEdits.FileName);
          if (Plan.Project <> nil) and ProjectModified(Plan.Project) then
            raise ELspEditError.Create('Projekt hat ungespeicherte Änderungen; bitte erst speichern');
        end
        // Ein Formular würde Atlas mit dem Designer öffnen; dessen Text passt nicht zu den Positionen.
        else if (Plan.Buffer = nil) and AOpenUnopened and not IsFormFile(FileEdits.FileName) and
          not IsProjectSource(FileEdits.FileName) and FileExists(FileEdits.FileName) and Supports(BorlandIDEServices, IOTAActionServices, Actions) and
          Actions.OpenFile(FileEdits.FileName) then
          Plan.Buffer := BufferOf(FileEdits.FileName);
        if Plan.Buffer <> nil then
        begin
          if Plan.Buffer.IsReadOnly then
            raise ELspEditError.Create('schreibgeschützt');
          Plan.Text := TAtlasEditorBuffer.Text(Plan.Buffer);
          if HasBase then
          begin
            // Ersetzt: ein Bereich über den ganzen Puffer.
            FinalText := TLspEdits.Apply(Base, FileEdits.Edits);
            SetLength(Plan.Ranges, 1);
            Plan.Ranges[0].StartOffset := 0;
            Plan.Ranges[0].EndOffset := Length(Plan.Text);
            Plan.Ranges[0].NewText := FinalText;
          end
          else
          begin
            Plan.Ranges := TLspEdits.Ordered(Plan.Text, FileEdits.Edits);
            FinalText := TLspEdits.Apply(Plan.Text, FileEdits.Edits);
          end;
          Plan.Change := TAtlasFileChange.Modified(FileEdits.FileName, Content(FileEdits.FileName, Plan.Text),
            Content(FileEdits.FileName, FinalText));
        end
        else
        begin
          if not FileExists(FileEdits.FileName) then
            raise ELspEditError.Create('Datei nicht gefunden');
          // Vorgabe-Kodierung aus atlas.json wie beim Server (#121); binäre Formulare brechen hier ab.
          Plan.Disk := TAtlasTextFile.Load(FileEdits.FileName, TAtlasEncodingDefault.CodePageFor(FileEdits.FileName));
          Plan.Change := TAtlasFileChange.Modified(FileEdits.FileName, Plan.Disk, Plan.Disk);
          if not HasBase then
            Base := Plan.Disk.Text;
          Plan.Disk.Text := TLspEdits.Apply(Base, FileEdits.Edits);
          Plan.Change.After := Plan.Disk;
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
    // 2. Anwenden: neue Dateien, dann Units und Dateien, dann die Formulare im Designer, zuletzt entfernen.
    for Planned in Creates do
    begin
      if Planned.FileName = '' then
        Continue;
      try
        Target.CreateFile(Planned.FileName, Planned.Project, Planned.Content);
      except
        on E: Exception do
        begin
          Result.Error := Format('%s: %s', [ExtractFileName(Planned.FileName), E.Message]);
          Remember;
          Exit;
        end;
      end;
      Recorded := Recorded + [TAtlasFileChange.Created(Planned.FileName, Planned.Project, Planned.Content)];
      Inc(Result.Files);
      Inc(Result.Written);
    end;
    for Plan in Plans do
    begin
      if Plan.IsForm then
        Continue;
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
          Remember;
          Exit;
        end;
      end;
      Recorded := Recorded + [Plan.Change];
      Inc(Result.Files);
    end;
    for Plan in Plans do
    begin
      if not Plan.IsForm then
        Continue;
      Result.Error := TAtlasIdeForms.Apply(Plan.FileName, Plan.FormChanges);
      if Result.Error <> '' then
      begin
        // Die Units sind schon geändert (je Datei rückgängig zu machen); das Formular blieb, wie es war.
        Result.Error := Format('%s: %s', [ExtractFileName(Plan.FileName), Result.Error]);
        Remember;
        Exit;
      end;
      if Plan.Change.FileName <> '' then
        Recorded := Recorded + [Plan.Change];
      Inc(Result.Files);
    end;
    for Planned in Removes do
    begin
      if Planned.FileName = '' then
        Continue;
      try
        // Schließen, austragen, Papierkorb; der Inhalt steht im Änderungsprotokoll.
        Target.RemoveFile(Planned.FileName, Planned.Project, TAtlasNewFilesMode.RecycleBin);
      except
        on E: Exception do
        begin
          Result.Error := Format('%s: %s', [ExtractFileName(Planned.FileName), E.Message]);
          Remember;
          Exit;
        end;
      end;
      Recorded := Recorded + [TAtlasFileChange.Deleted(Planned.FileName, Planned.Project, Planned.Content)];
      Inc(Result.Files);
    end;
    Remember;
  finally
    Replaced.Free;
    Gone.Free;
    Pending.Free;
    Removes.Free;
    Creates.Free;
  end;
end;

end.
