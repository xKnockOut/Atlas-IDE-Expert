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
// Geplant wird ohne IDE in Atlas.Core.Editor.WorkspacePlan (S-03b); hier bleiben Puffer,
// Designer, Projekte und das Schreiben. Dateihelfer stehen in Atlas.IDE.Foundation.Files.
// Nur im Hauptthread aufrufen.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.WorkspacePlan;

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
    /// <summary>Aktueller Text: offener Puffer, offenes Formular (Stand des Designers), sonst die Datei auf der
    /// Platte; '' wenn sie fehlt (#400).</summary>
    class function CurrentText(const AFileName: string): string; static;
    /// <summary>Wendet AEdit an. APolicy: nicht geöffnete Dateien im Editor öffnen oder auf die Platte
    /// schreiben. AAction: Name der Aktion im Änderungsprotokoll (#721).</summary>
    class function Apply(const AEdit: TLspWorkspaceEdit; APolicy: TAtlasUnopenedPolicy;
      const AAction: string): TAtlasWorkspaceEditResult; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Files.EncodingDefault,
  Atlas.Core.Forms.Changes,
  Atlas.Core.Undo.Contract,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Forms.Designer,
  Atlas.IDE.Undo.Changes,
  Atlas.IDE.Undo.Target;

type
  /// <summary>Vorhandene Datei, fertig zum Schreiben: Puffer, Formular im Designer, Projektdatei oder Platte.</summary>
  TPreparedFile = record
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

function Failure(const AFileName, AReason: string): string;
begin
  Result := Format('%s: %s', [ExtractFileName(AFileName), AReason]);
end;

function Content(const AFileName, AText: string): TAtlasTextFileContent;
begin
  Result := TAtlasIdeFiles.DiskEncoding(AFileName);
  Result.Text := AText;
end;

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

/// <summary>Formular im Designer (#402): nur Ereignis-Zuordnungen; '' oder der Grund der Ablehnung.</summary>
function PrepareForm(const AEntry: TAtlasPlannedEdit; var AFile: TPreparedFile): string;
var
  Sent: string;
begin
  AFile.IsForm := True;
  if AEntry.HasBase then
    Exit('im Designer offen; dort ändert Atlas nur Ereignis-Zuordnungen');
  Result := TAtlasIdeForms.Check(AEntry.FileName, AEntry.Edits, AFile.FormChanges);
  if Result <> '' then
    Exit;
  // Check hat den Text schon geprüft; vorher ist der Stand, den der Server kennt.
  if TAtlasIdeForms.SentText(AEntry.FileName, Sent) then
    AFile.Change := TAtlasFileChange.Modified(AEntry.FileName, Content(AEntry.FileName, Sent),
      Content(AEntry.FileName, TLspEdits.Apply(Sent, AEntry.Edits)));
end;

/// <summary>Puffer, Projektdatei oder Platte; ELspEditError und Fehler beim Lesen brechen ab.</summary>
procedure PrepareText(const AEntry: TAtlasPlannedEdit; APolicy: TAtlasUnopenedPolicy; var AFile: TPreparedFile);
var
  Actions: IOTAActionServices;
  Base, FinalText: string;
begin
  Base := AEntry.Base;
  if TAtlasIdeFiles.IsProjectFile(AEntry.FileName) then
  begin
    // Projektdatei: nie als Text öffnen; ungespeicherte Projektänderungen nicht verwerfen.
    AFile.Project := TAtlasIdeFiles.ProjectModule(AEntry.FileName);
    if (AFile.Project <> nil) and TAtlasIdeFiles.ProjectModified(AFile.Project) then
      raise ELspEditError.Create('Projekt hat ungespeicherte Änderungen; bitte erst speichern');
  end
  // Ein Formular würde Atlas mit dem Designer öffnen; dessen Text passt nicht zu den Positionen.
  else if (AFile.Buffer = nil) and (APolicy = TAtlasUnopenedPolicy.OpenInEditor) and
    not TAtlasIdeFiles.IsFormFile(AEntry.FileName) and not TAtlasIdeFiles.IsProjectSource(AEntry.FileName) and
    FileExists(AEntry.FileName) and Supports(BorlandIDEServices, IOTAActionServices, Actions) and
    Actions.OpenFile(AEntry.FileName) then
    AFile.Buffer := TAtlasIdeFiles.BufferOf(AEntry.FileName);
  if AFile.Buffer <> nil then
  begin
    if AFile.Buffer.IsReadOnly then
      raise ELspEditError.Create('schreibgeschützt');
    AFile.Text := TAtlasEditorBuffer.Text(AFile.Buffer);
    if AEntry.HasBase then
    begin
      // Ersetzt: ein Bereich über den ganzen Puffer.
      FinalText := TLspEdits.Apply(Base, AEntry.Edits);
      AFile.Ranges := nil;
      SetLength(AFile.Ranges, 1);
      AFile.Ranges[0].StartOffset := 0;
      AFile.Ranges[0].EndOffset := Length(AFile.Text);
      AFile.Ranges[0].NewText := FinalText;
    end
    else
    begin
      AFile.Ranges := TLspEdits.Ordered(AFile.Text, AEntry.Edits);
      FinalText := TLspEdits.Apply(AFile.Text, AEntry.Edits);
    end;
    AFile.Change := TAtlasFileChange.Modified(AEntry.FileName, Content(AEntry.FileName, AFile.Text),
      Content(AEntry.FileName, FinalText));
    Exit;
  end;
  if not FileExists(AEntry.FileName) then
    raise ELspEditError.Create('Datei nicht gefunden');
  // Vorgabe-Kodierung aus atlas.json wie beim Server (#121); binäre Formulare brechen hier ab.
  AFile.Disk := TAtlasTextFile.Load(AEntry.FileName, TAtlasEncodingDefault.CodePageFor(AEntry.FileName));
  AFile.Change := TAtlasFileChange.Modified(AEntry.FileName, AFile.Disk, AFile.Disk);
  if not AEntry.HasBase then
    Base := AFile.Disk.Text;
  AFile.Disk.Text := TLspEdits.Apply(Base, AEntry.Edits);
  AFile.Change.After := AFile.Disk;
end;

/// <summary>Jede vorhandene Datei prüfen und vorbereiten (Puffer öffnen, Bereiche rechnen); noch nichts
/// ändern. False mit AResult.Error beim ersten Fehler.</summary>
function PrepareFiles(const APlan: TAtlasEditPlan; APolicy: TAtlasUnopenedPolicy; out AFiles: TArray<TPreparedFile>;
  var AResult: TAtlasWorkspaceEditResult): Boolean;
var
  Prepared: TList<TPreparedFile>;
  Entry: TAtlasPlannedEdit;
  Item: TPreparedFile;
  Error: string;
begin
  Result := False;
  AFiles := nil;
  Prepared := TList<TPreparedFile>.Create;
  try
    for Entry in APlan.Files do
    begin
      Item := Default(TPreparedFile);
      Item.FileName := Entry.FileName;
      if not TAtlasIdeFiles.IsProjectFile(Entry.FileName) then
        Item.Buffer := TAtlasIdeFiles.BufferOf(Entry.FileName);
      if (Item.Buffer = nil) and TAtlasIdeFiles.IsFormFile(Entry.FileName) and
        TAtlasIdeForms.IsOpen(Entry.FileName) then
      begin
        Error := PrepareForm(Entry, Item);
        if Error <> '' then
        begin
          AResult.Error := Failure(Entry.FileName, Error);
          Exit;
        end;
      end
      else
        try
          PrepareText(Entry, APolicy, Item);
        except
          on E: Exception do
          begin
            AResult.Error := Failure(Entry.FileName, E.Message);
            Exit;
          end;
        end;
      Prepared.Add(Item);
      Inc(AResult.Edits, Length(Entry.Edits));
    end;
    AFiles := Prepared.ToArray;
    Result := True;
  finally
    Prepared.Free;
  end;
end;

/// <summary>Anwenden: neue Dateien, dann Units und Dateien, dann die Formulare im Designer, zuletzt entfernen.
/// Was geschrieben ist, kommt als ein Satz ins Änderungsprotokoll, auch nach einem Fehler.</summary>
procedure Execute(const APlan: TAtlasEditPlan; const AFiles: TArray<TPreparedFile>; const AAction: string;
  const ATarget: IAtlasUndoTarget; var AResult: TAtlasWorkspaceEditResult);
var
  Recorded: TList<TAtlasFileChange>;
  Planned: TAtlasPlannedOperation;
  Prepared: TPreparedFile;
  Actions: IOTAActionServices;
  Error: string;
begin
  Recorded := TList<TAtlasFileChange>.Create;
  try
    try
      for Planned in APlan.Creates do
      begin
        try
          ATarget.CreateFile(Planned.FileName, Planned.Project, Planned.Content);
        except
          on E: Exception do
          begin
            AResult.Error := Failure(Planned.FileName, E.Message);
            Exit;
          end;
        end;
        Recorded.Add(TAtlasFileChange.Created(Planned.FileName, Planned.Project, Planned.Content));
        Inc(AResult.Files);
        Inc(AResult.Written);
      end;
      for Prepared in AFiles do
      begin
        if Prepared.IsForm then
          Continue;
        try
          if Prepared.Buffer <> nil then
            TAtlasIdeWorkspaceEdit.WriteBuffer(Prepared.Buffer, Prepared.Text, Prepared.Ranges)
          else
          begin
            TAtlasTextFile.Save(Prepared.FileName, Prepared.Disk);
            Inc(AResult.Written);
            // Geladenes Projekt neu einlesen, sonst schreibt die IDE beim Speichern ihren alten Stand zurück.
            if (Prepared.Project <> nil) and Supports(BorlandIDEServices, IOTAActionServices, Actions) then
              Actions.ReloadFile(Prepared.FileName);
          end;
        except
          on E: Exception do
          begin
            // Was schon geschrieben ist, bleibt (je Datei rückgängig zu machen); der Rest fehlt.
            AResult.Error := Failure(Prepared.FileName, E.Message);
            Exit;
          end;
        end;
        Recorded.Add(Prepared.Change);
        Inc(AResult.Files);
      end;
      for Prepared in AFiles do
      begin
        if not Prepared.IsForm then
          Continue;
        Error := TAtlasIdeForms.Apply(Prepared.FileName, Prepared.FormChanges);
        if Error <> '' then
        begin
          // Die Units sind schon geändert (je Datei rückgängig zu machen); das Formular blieb, wie es war.
          AResult.Error := Failure(Prepared.FileName, Error);
          Exit;
        end;
        if Prepared.Change.FileName <> '' then
          Recorded.Add(Prepared.Change);
        Inc(AResult.Files);
      end;
      for Planned in APlan.Removes do
      begin
        try
          // Schließen, austragen, Papierkorb; der Inhalt steht im Änderungsprotokoll.
          ATarget.RemoveFile(Planned.FileName, Planned.Project, TAtlasNewFilesMode.RecycleBin);
        except
          on E: Exception do
          begin
            AResult.Error := Failure(Planned.FileName, E.Message);
            Exit;
          end;
        end;
        Recorded.Add(TAtlasFileChange.Deleted(Planned.FileName, Planned.Project, Planned.Content));
        Inc(AResult.Files);
      end;
    finally
      // Auch nach einem Fehler: Was schon geschrieben ist, lässt sich so gemeinsam zurücknehmen.
      TAtlasIdeUndo.Add(AAction, Recorded.ToArray);
    end;
  finally
    Recorded.Free;
  end;
end;

class function TAtlasIdeWorkspaceEdit.CurrentText(const AFileName: string): string;
var
  Buffer: IOTAEditBuffer;
begin
  Result := '';
  Buffer := TAtlasIdeFiles.BufferOf(AFileName);
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
  // Eigener Schreibvorgang: Probleme und Inlay-Hints lesen den Puffer neu (P-04).
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

class function TAtlasIdeWorkspaceEdit.Apply(const AEdit: TLspWorkspaceEdit; APolicy: TAtlasUnopenedPolicy;
  const AAction: string): TAtlasWorkspaceEditResult;
var
  Target: IAtlasUndoTarget;
  Environment: IAtlasEditEnvironment;
  Plan: TAtlasEditPlan;
  Files: TArray<TPreparedFile>;
begin
  Result := Default(TAtlasWorkspaceEditResult);
  Target := TAtlasIdeUndoTarget.Create;
  Environment := TAtlasIdeEditEnvironment.Create(Target);
  // 1. Prüfen: Dateioperationen und alle Texte planen, noch nichts ändern.
  Plan := TAtlasEditPlanner.Plan(AEdit, Environment);
  if Plan.Error <> '' then
  begin
    Result.Error := Plan.Error;
    Exit;
  end;
  Result.Edits := Plan.CreatedEdits;
  if not PrepareFiles(Plan, APolicy, Files, Result) then
    Exit;
  // 2. Anwenden.
  Execute(Plan, Files, AAction, Target, Result);
end;

end.
