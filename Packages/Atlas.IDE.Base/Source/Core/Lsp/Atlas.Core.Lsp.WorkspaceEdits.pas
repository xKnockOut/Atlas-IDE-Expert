unit Atlas.Core.Lsp.WorkspaceEdits;

// Textänderungen des Servers für mehrere Dateien (#397): WorkspaceEdit aus
// Antworten wie textDocument/rename oder Code-Aktionen lesen und auf Texte
// anwenden. Gelesen werden "changes" (uri → TextEdit[]) und, falls vorhanden,
// "documentChanges" (TextDocumentEdit, auch mit AnnotatedTextEdit).
// Dateioperationen in documentChanges (create, rename, delete mit ihren
// Optionen) liest es in Operations (#721); die IDE-Schicht führt sie aus und
// protokolliert sie. Unbekannte oder unvollständige Operationen werden nur
// gezählt (Unsupported), damit die IDE-Schicht darauf hinweisen kann.
// Trägt ein Edit eine neue Unit selbst in ein Projekt ein (.dproj und .dpr,
// etwa die Testunit aus #274), nennt ProjectFile dieses Projekt; ist es in
// der IDE geladen, entfernt WithoutProject diese Änderungen, und die IDE
// trägt die Unit über ihr Projekt ein.
// Positionen sind 0-basiert in UTF-16-Einheiten wie im LSP. Mehrere
// Änderungen gelten alle für den Text vor der ersten; überlappende sind ein
// Fehler. Gleicher Anfang: in der Reihenfolge der Liste (LSP 3.17).
// Beim Umbenennen nennt der Atlas-Server erschlossene Stellen, die er nicht
// ändert, in atlasUnchanged (#1119); sie stehen in Unchanged.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.TextChanges;

type
  TLspTextEdit = record
    StartPos: TLspTextPosition;
    EndPos: TLspTextPosition;
    NewText: string;
    class function FromJson(const AEdit: TJSONValue; out AResult: TLspTextEdit): Boolean; static;
  end;

  /// <summary>Änderung als Zeichenbereich (0-basiert, Ende ausschließlich) in einem bestimmten Text.</summary>
  TLspTextRange = record
    StartOffset: Integer;
    EndOffset: Integer;
    NewText: string;
  end;

  TLspFileEdits = record
    FileName: string;
    Edits: TArray<TLspTextEdit>;
  end;

{$SCOPEDENUMS ON}
  TLspFileOperationKind = (Create, Rename, Delete);
{$SCOPEDENUMS OFF}

  /// <summary>Dateioperation aus documentChanges (CreateFile, RenameFile, DeleteFile).</summary>
  TLspFileOperation = record
    Kind: TLspFileOperationKind;
    /// <summary>Anlegen, Löschen: die Datei; Umbenennen: der alte Name.</summary>
    FileName: string;
    /// <summary>Nur Umbenennen: der neue Name.</summary>
    NewFileName: string;
    /// <summary>Anlegen, Umbenennen: vorhandene Zieldatei überschreiben.</summary>
    Overwrite: Boolean;
    /// <summary>Anlegen, Umbenennen: vorhandene Zieldatei lassen und nichts tun.</summary>
    IgnoreIfExists: Boolean;
    /// <summary>Löschen: fehlende Datei ist kein Fehler.</summary>
    IgnoreIfNotExists: Boolean;
    /// <summary>Löschen: Ordner samt Inhalt (führt Atlas nicht aus).</summary>
    Recursive: Boolean;
    class function FromJson(const AValue: TJSONObject; out AResult: TLspFileOperation): Boolean; static;
  end;

  /// <summary>Erschlossene Stelle, die das Umbenennen nicht ändert (#1119).</summary>
  TLspUnchangedPlace = record
    FileName: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
    Character: Integer;
    Confidence: TAtlasConfidence;
  end;

  TLspWorkspaceEdit = record
    Files: TArray<TLspFileEdits>;
    /// <summary>atlasUnchanged der Antwort auf textDocument/rename (#1119); sonst leer.</summary>
    Unchanged: TArray<TLspUnchangedPlace>;
    /// <summary>Dateioperationen in der Reihenfolge des Servers (#721).</summary>
    Operations: TArray<TLspFileOperation>;
    /// <summary>Dateioperationen, die Atlas nicht lesen kann (unbekannte Art, fehlende Adresse).</summary>
    Unsupported: Integer;
    function EditCount: Integer;
    function IsEmpty: Boolean;
    /// <summary>Erste geänderte .dproj; '' ohne.</summary>
    function ProjectFile: string;
    /// <summary>Ohne die Änderungen an AProject (.dproj) und seiner Hauptdatei (.dpr, .dpk).</summary>
    function WithoutProject(const AProject: string): TLspWorkspaceEdit;
    /// <summary>Aus einem WorkspaceEdit; nil oder null ergibt eine leere Änderung.</summary>
    class function FromJson(const AValue: TJSONValue): TLspWorkspaceEdit; static;
  end;

  ELspEditError = class(Exception);

  TLspEdits = class
  public
    /// <summary>Bereiche zu AEdits in AText, aufsteigend; ELspEditError bei Überlappung oder
    /// einer Position außerhalb des Textes.</summary>
    class function Ordered(const AText: string; const AEdits: TArray<TLspTextEdit>): TArray<TLspTextRange>; static;
    /// <summary>AText mit allen Änderungen.</summary>
    class function Apply(const AText: string; const AEdits: TArray<TLspTextEdit>): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Lsp.Uris,
  Atlas.Text.Lines;

function ReadPosition(const ARange: TJSONObject; const AName: string; out APosition: TLspTextPosition): Boolean;
var
  Position: TJSONObject;
begin
  Result := ARange.TryGetValue<TJSONObject>(AName, Position) and
    Position.TryGetValue<Integer>('line', APosition.Line) and
    Position.TryGetValue<Integer>('character', APosition.Character);
end;

{ TLspTextEdit }

class function TLspTextEdit.FromJson(const AEdit: TJSONValue; out AResult: TLspTextEdit): Boolean;
var
  Range: TJSONObject;
begin
  AResult := Default(TLspTextEdit);
  Result := (AEdit is TJSONObject) and TJSONObject(AEdit).TryGetValue<TJSONObject>('range', Range) and
    ReadPosition(Range, 'start', AResult.StartPos) and ReadPosition(Range, 'end', AResult.EndPos) and
    TJSONObject(AEdit).TryGetValue<string>('newText', AResult.NewText);
end;

{ TLspWorkspaceEdit }

function TLspWorkspaceEdit.EditCount: Integer;
var
  FileEdits: TLspFileEdits;
begin
  Result := 0;
  for FileEdits in Files do
  begin
    Inc(Result, Length(FileEdits.Edits));
  end;
end;

function TLspWorkspaceEdit.IsEmpty: Boolean;
begin
  Result := (EditCount = 0) and (Length(Operations) = 0);
end;

function TLspWorkspaceEdit.ProjectFile: string;
var
  FileEdits: TLspFileEdits;
begin
  Result := '';
  for FileEdits in Files do
  begin
    if SameText(ExtractFileExt(FileEdits.FileName), '.dproj') then
    begin
      Exit(FileEdits.FileName);
    end;
  end;
end;

function TLspWorkspaceEdit.WithoutProject(const AProject: string): TLspWorkspaceEdit;
var
  FileEdits: TLspFileEdits;
begin
  Result := Self;
  Result.Files := nil;
  for FileEdits in Files do
  begin
    if not SameText(FileEdits.FileName, AProject) and
      not SameText(FileEdits.FileName, ChangeFileExt(AProject, '.dpr')) and
      not SameText(FileEdits.FileName, ChangeFileExt(AProject, '.dpk')) then
    begin
      Result.Files := Result.Files + [FileEdits];
    end;
  end;
end;

{ TLspFileOperation }

/// <summary>Art einer Dateioperation aus kind; False für Unbekanntes.</summary>
function FileOperationKindOf(const AKind: string; out AResult: TLspFileOperationKind): Boolean;
begin
  Result := True;
  AResult := TLspFileOperationKind.Create;
  if AKind = 'rename' then
  begin
    AResult := TLspFileOperationKind.Rename;
  end
  else if AKind = 'delete' then
  begin
    AResult := TLspFileOperationKind.Delete;
  end
  else
  begin
    Result := AKind = 'create';
  end;
end;

/// <summary>Liest die Datei (uri bzw. oldUri) und beim Umbenennen das Ziel (newUri); False, wenn eine fehlt oder
/// kein Pfad ist.</summary>
function ReadFileOperationFiles(const AValue: TJSONObject; var AResult: TLspFileOperation): Boolean;
var
  Uri, NewUri: string;
begin
  if AResult.Kind = TLspFileOperationKind.Rename then
  begin
    Result := AValue.TryGetValue<string>('oldUri', Uri) and AValue.TryGetValue<string>('newUri', NewUri);
    if Result then
    begin
      AResult.NewFileName := TLspUris.ToPath(NewUri);
      Result := AResult.NewFileName <> '';
    end;
  end
  else
  begin
    Result := AValue.TryGetValue<string>('uri', Uri);
  end;
  if Result then
  begin
    AResult.FileName := TLspUris.ToPath(Uri);
    Result := AResult.FileName <> '';
  end;
end;

/// <summary>Liest options; overwrite gewinnt über ignoreIfExists (LSP 3.17).</summary>
procedure ReadFileOperationOptions(const AValue: TJSONObject; var AResult: TLspFileOperation);
var
  Options: TJSONObject;
begin
  if AValue.TryGetValue<TJSONObject>('options', Options) then
  begin
    Options.TryGetValue<Boolean>('overwrite', AResult.Overwrite);
    Options.TryGetValue<Boolean>('ignoreIfExists', AResult.IgnoreIfExists);
    Options.TryGetValue<Boolean>('ignoreIfNotExists', AResult.IgnoreIfNotExists);
    Options.TryGetValue<Boolean>('recursive', AResult.Recursive);
  end;
  if AResult.Overwrite then
  begin
    AResult.IgnoreIfExists := False;
  end;
end;

class function TLspFileOperation.FromJson(const AValue: TJSONObject; out AResult: TLspFileOperation): Boolean;
var
  Kind: string;
begin
  AResult := Default(TLspFileOperation);
  Result := AValue.TryGetValue<string>('kind', Kind) and FileOperationKindOf(Kind, AResult.Kind) and
    ReadFileOperationFiles(AValue, AResult);
  if Result then
  begin
    ReadFileOperationOptions(AValue, AResult);
  end;
end;

function ReadEdits(const AUri: string; const AEdits: TJSONArray; out AFile: TLspFileEdits): Boolean;
var
  Item: TJSONValue;
  Edit: TLspTextEdit;
begin
  AFile.FileName := TLspUris.ToPath(AUri);
  AFile.Edits := nil;
  if (AFile.FileName = '') or (AEdits = nil) then
  begin
    Exit(False);
  end;
  for Item in AEdits do
  begin
    if TLspTextEdit.FromJson(Item, Edit) then
    begin
      AFile.Edits := AFile.Edits + [Edit];
    end;
  end;
  Result := Length(AFile.Edits) > 0;
end;

/// <summary>Stellen aus atlasUnchanged, die die Änderung nicht anpasst (mit Sicherheit).</summary>
function UnchangedPlacesOf(const AEdit: TJSONObject): TArray<TLspUnchangedPlace>;
var
  Unchanged: TJSONArray;
  Item: TJSONValue;
  Uri: string;
  Place: TLspUnchangedPlace;
begin
  Result := nil;
  if not AEdit.TryGetValue<TJSONArray>('atlasUnchanged', Unchanged) then
  begin
    Exit;
  end;
  for Item in Unchanged do
  begin
    if (Item is TJSONObject) and TJSONObject(Item).TryGetValue<string>('uri', Uri) then
    begin
      Place.FileName := TLspUris.ToPath(Uri);
      Place.Line := TJSONObject(Item).GetValue<Integer>('range.start.line', 0);
      Place.Character := TJSONObject(Item).GetValue<Integer>('range.start.character', 0);
      Place.Confidence := TAtlasConfidence.FromJson(Item);
      Result := Result + [Place];
    end;
  end;
end;

/// <summary>Ein Eintrag aus documentChanges: Dateioperation (mit kind) oder Textänderungen einer Datei.</summary>
procedure ReadDocumentChange(const AItem: TJSONObject; var AResult: TLspWorkspaceEdit);
var
  Document: TJSONObject;
  Edits: TJSONArray;
  Uri: string;
  FileEdits: TLspFileEdits;
  Operation: TLspFileOperation;
begin
  if AItem.GetValue('kind') <> nil then
  begin
    if TLspFileOperation.FromJson(AItem, Operation) then
    begin
      AResult.Operations := AResult.Operations + [Operation];
    end
    else
    begin
      Inc(AResult.Unsupported);
    end;
  end
  else if AItem.TryGetValue<TJSONObject>('textDocument', Document) and Document.TryGetValue<string>('uri', Uri) and
    AItem.TryGetValue<TJSONArray>('edits', Edits) and ReadEdits(Uri, Edits, FileEdits) then
  begin
    AResult.Files := AResult.Files + [FileEdits];
  end;
end;

/// <summary>Textänderungen aus changes (URI auf Liste von Änderungen).</summary>
procedure ReadChanges(const AChanges: TJSONObject; var AResult: TLspWorkspaceEdit);
var
  Pair: TJSONPair;
  FileEdits: TLspFileEdits;
begin
  for Pair in AChanges do
  begin
    if (Pair.JsonValue is TJSONArray) and ReadEdits(Pair.JsonString.Value, TJSONArray(Pair.JsonValue), FileEdits) then
    begin
      AResult.Files := AResult.Files + [FileEdits];
    end;
  end;
end;

class function TLspWorkspaceEdit.FromJson(const AValue: TJSONValue): TLspWorkspaceEdit;
var
  Edit, Changes: TJSONObject;
  DocumentChanges: TJSONArray;
  Item: TJSONValue;
begin
  Result := Default(TLspWorkspaceEdit);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  Edit := TJSONObject(AValue);
  Result.Unchanged := UnchangedPlacesOf(Edit);
  // documentChanges hat Vorrang, wenn der Server beides schickt.
  if Edit.TryGetValue<TJSONArray>('documentChanges', DocumentChanges) then
  begin
    for Item in DocumentChanges do
    begin
      if Item is TJSONObject then
      begin
        ReadDocumentChange(TJSONObject(Item), Result);
      end;
    end;
  end
  else if Edit.TryGetValue<TJSONObject>('changes', Changes) then
  begin
    ReadChanges(Changes, Result);
  end;
end;

{ TLspEdits }

type
  TIndexedRange = record
    Range: TLspTextRange;
    Index: Integer;
  end;

class function TLspEdits.Ordered(const AText: string; const AEdits: TArray<TLspTextEdit>): TArray<TLspTextRange>;
var
  Items: TArray<TIndexedRange>;
  Index: Integer;
  LastLine: Integer;
  Lines: TLineTable;
begin
  // Letzte gültige Zeile: Positionen dahinter sind ein Fehler, nicht still das Textende.
  Lines := TLineTable.Build(AText);
  LastLine := Lines.LineCount - 1;
  SetLength(Items, Length(AEdits));
  for Index := 0 to High(AEdits) do
  begin
    if (AEdits[Index].StartPos.Line > LastLine) or (AEdits[Index].EndPos.Line > LastLine) then
    begin
      raise ELspEditError.CreateFmt('Änderung in Zeile %d, der Text hat nur %d Zeilen',
        [AEdits[Index].EndPos.Line + 1, LastLine + 1]);
    end;
    Items[Index].Range.StartOffset := TLspTextChanges.OffsetOf(Lines, AEdits[Index].StartPos);
    Items[Index].Range.EndOffset := TLspTextChanges.OffsetOf(Lines, AEdits[Index].EndPos);
    Items[Index].Range.NewText := AEdits[Index].NewText;
    Items[Index].Index := Index;
    if Items[Index].Range.EndOffset < Items[Index].Range.StartOffset then
    begin
      raise ELspEditError.CreateFmt('Änderung %d endet vor ihrem Anfang', [Index + 1]);
    end;
  end;
  TArray.Sort<TIndexedRange>(Items, TComparer<TIndexedRange>.Construct(
    function(const A, B: TIndexedRange): Integer
    begin
      Result := A.Range.StartOffset - B.Range.StartOffset;
      if Result = 0 then
      begin
        Result := A.Index - B.Index;
      end;
    end));
  SetLength(Result, Length(Items));
  for Index := 0 to High(Items) do
  begin
    if (Index > 0) and (Items[Index].Range.StartOffset < Items[Index - 1].Range.EndOffset) then
    begin
      raise ELspEditError.Create('Änderungen überlappen sich');
    end;
    Result[Index] := Items[Index].Range;
  end;
end;

class function TLspEdits.Apply(const AText: string; const AEdits: TArray<TLspTextEdit>): string;
var
  Ranges: TArray<TLspTextRange>;
  Range: TLspTextRange;
  Builder: TStringBuilder;
  Position: Integer;
begin
  Ranges := Ordered(AText, AEdits);
  Builder := TStringBuilder.Create(Length(AText));
  try
    Position := 0;
    for Range in Ranges do
    begin
      Builder.Append(AText, Position, Range.StartOffset - Position);
      Builder.Append(Range.NewText);
      Position := Range.EndOffset;
    end;
    Builder.Append(AText, Position, Length(AText) - Position);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

end.
