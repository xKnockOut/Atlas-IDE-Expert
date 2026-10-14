unit Atlas.Core.Lsp.WorkspaceEdits;

// Textänderungen des Servers für mehrere Dateien (#397): WorkspaceEdit aus
// Antworten wie textDocument/rename oder Code-Aktionen lesen und auf Texte
// anwenden. Gelesen werden "changes" (uri → TextEdit[]) und, falls vorhanden,
// "documentChanges" (TextDocumentEdit, auch mit AnnotatedTextEdit).
// Dateioperationen (create, rename, delete) führt Atlas nicht aus; sie werden
// nur gezählt, damit die IDE-Schicht darauf hinweisen kann.
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

  TLspWorkspaceEdit = record
    Files: TArray<TLspFileEdits>;
    /// <summary>Dateioperationen (anlegen, umbenennen, löschen), die Atlas nicht ausführt.</summary>
    Unsupported: Integer;
    function EditCount: Integer;
    function IsEmpty: Boolean;
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
  Result := EditCount = 0;
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
