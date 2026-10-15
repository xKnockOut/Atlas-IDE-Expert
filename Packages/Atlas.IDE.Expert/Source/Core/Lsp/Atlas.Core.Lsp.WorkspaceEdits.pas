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

interface

uses
  System.SysUtils,
  System.JSON,
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

  TLspWorkspaceEdit = record
    Files: TArray<TLspFileEdits>;
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
  Atlas.Core.Lsp.Session;

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
    Inc(Result, Length(FileEdits.Edits));
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
    if SameText(ExtractFileExt(FileEdits.FileName), '.dproj') then
      Exit(FileEdits.FileName);
end;

function TLspWorkspaceEdit.WithoutProject(const AProject: string): TLspWorkspaceEdit;
var
  FileEdits: TLspFileEdits;
begin
  Result := Self;
  Result.Files := nil;
  for FileEdits in Files do
    if not SameText(FileEdits.FileName, AProject) and
      not SameText(FileEdits.FileName, ChangeFileExt(AProject, '.dpr')) and
      not SameText(FileEdits.FileName, ChangeFileExt(AProject, '.dpk')) then
      Result.Files := Result.Files + [FileEdits];
end;

{ TLspFileOperation }

class function TLspFileOperation.FromJson(const AValue: TJSONObject; out AResult: TLspFileOperation): Boolean;
var
  Kind, Uri, NewUri: string;
  Options: TJSONObject;
begin
  AResult := Default(TLspFileOperation);
  if not AValue.TryGetValue<string>('kind', Kind) then
    Exit(False);
  if Kind = 'create' then
    AResult.Kind := TLspFileOperationKind.Create
  else if Kind = 'rename' then
    AResult.Kind := TLspFileOperationKind.Rename
  else if Kind = 'delete' then
    AResult.Kind := TLspFileOperationKind.Delete
  else
    Exit(False);
  if AResult.Kind = TLspFileOperationKind.Rename then
  begin
    if not AValue.TryGetValue<string>('oldUri', Uri) or not AValue.TryGetValue<string>('newUri', NewUri) then
      Exit(False);
    AResult.NewFileName := TLspSession.UriToPath(NewUri);
    if AResult.NewFileName = '' then
      Exit(False);
  end
  else if not AValue.TryGetValue<string>('uri', Uri) then
    Exit(False);
  AResult.FileName := TLspSession.UriToPath(Uri);
  if AResult.FileName = '' then
    Exit(False);
  if AValue.TryGetValue<TJSONObject>('options', Options) then
  begin
    Options.TryGetValue<Boolean>('overwrite', AResult.Overwrite);
    Options.TryGetValue<Boolean>('ignoreIfExists', AResult.IgnoreIfExists);
    Options.TryGetValue<Boolean>('ignoreIfNotExists', AResult.IgnoreIfNotExists);
    Options.TryGetValue<Boolean>('recursive', AResult.Recursive);
  end;
  // overwrite gewinnt über ignoreIfExists (LSP 3.17).
  if AResult.Overwrite then
    AResult.IgnoreIfExists := False;
  Result := True;
end;

function ReadEdits(const AUri: string; const AEdits: TJSONArray; out AFile: TLspFileEdits): Boolean;
var
  Item: TJSONValue;
  Edit: TLspTextEdit;
begin
  AFile.FileName := TLspSession.UriToPath(AUri);
  AFile.Edits := nil;
  if (AFile.FileName = '') or (AEdits = nil) then
    Exit(False);
  for Item in AEdits do
    if TLspTextEdit.FromJson(Item, Edit) then
      AFile.Edits := AFile.Edits + [Edit];
  Result := Length(AFile.Edits) > 0;
end;

class function TLspWorkspaceEdit.FromJson(const AValue: TJSONValue): TLspWorkspaceEdit;
var
  Edit: TJSONObject;
  Changes: TJSONObject;
  DocumentChanges, Edits: TJSONArray;
  Pair: TJSONPair;
  Item: TJSONValue;
  Document: TJSONObject;
  Uri: string;
  FileEdits: TLspFileEdits;
  Operation: TLspFileOperation;
begin
  Result := Default(TLspWorkspaceEdit);
  if not (AValue is TJSONObject) then
    Exit;
  Edit := TJSONObject(AValue);
  // documentChanges hat Vorrang, wenn der Server beides schickt.
  if Edit.TryGetValue<TJSONArray>('documentChanges', DocumentChanges) then
  begin
    for Item in DocumentChanges do
    begin
      if not (Item is TJSONObject) then
        Continue;
      if TJSONObject(Item).GetValue('kind') <> nil then
      begin
        if TLspFileOperation.FromJson(TJSONObject(Item), Operation) then
          Result.Operations := Result.Operations + [Operation]
        else
          Inc(Result.Unsupported);
        Continue;
      end;
      if TJSONObject(Item).TryGetValue<TJSONObject>('textDocument', Document) and
        Document.TryGetValue<string>('uri', Uri) and TJSONObject(Item).TryGetValue<TJSONArray>('edits', Edits) and
        ReadEdits(Uri, Edits, FileEdits) then
        Result.Files := Result.Files + [FileEdits];
    end;
    Exit;
  end;
  if Edit.TryGetValue<TJSONObject>('changes', Changes) then
    for Pair in Changes do
      if (Pair.JsonValue is TJSONArray) and ReadEdits(Pair.JsonString.Value, TJSONArray(Pair.JsonValue), FileEdits) then
        Result.Files := Result.Files + [FileEdits];
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
begin
  // Letzte gültige Zeile: Positionen dahinter sind ein Fehler, nicht still das Textende.
  LastLine := TLspTextChanges.PositionOf(AText, Length(AText)).Line;
  SetLength(Items, Length(AEdits));
  for Index := 0 to High(AEdits) do
  begin
    if (AEdits[Index].StartPos.Line > LastLine) or (AEdits[Index].EndPos.Line > LastLine) then
      raise ELspEditError.CreateFmt('Änderung in Zeile %d, der Text hat nur %d Zeilen',
        [AEdits[Index].EndPos.Line + 1, LastLine + 1]);
    Items[Index].Range.StartOffset := TLspTextChanges.OffsetOf(AText, AEdits[Index].StartPos);
    Items[Index].Range.EndOffset := TLspTextChanges.OffsetOf(AText, AEdits[Index].EndPos);
    Items[Index].Range.NewText := AEdits[Index].NewText;
    Items[Index].Index := Index;
    if Items[Index].Range.EndOffset < Items[Index].Range.StartOffset then
      raise ELspEditError.CreateFmt('Änderung %d endet vor ihrem Anfang', [Index + 1]);
  end;
  TArray.Sort<TIndexedRange>(Items, TComparer<TIndexedRange>.Construct(
    function(const A, B: TIndexedRange): Integer
    begin
      Result := A.Range.StartOffset - B.Range.StartOffset;
      if Result = 0 then
        Result := A.Index - B.Index;
    end));
  SetLength(Result, Length(Items));
  for Index := 0 to High(Items) do
  begin
    if (Index > 0) and (Items[Index].Range.StartOffset < Items[Index - 1].Range.EndOffset) then
      raise ELspEditError.Create('Änderungen überlappen sich');
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
