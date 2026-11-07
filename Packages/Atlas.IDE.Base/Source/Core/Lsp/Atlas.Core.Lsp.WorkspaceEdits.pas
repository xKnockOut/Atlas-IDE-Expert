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
  Atlas.Text.Lines,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TWorkspaceEditsText = (ChangeInLineTheText, ChangeEndsBeforeItsStart, ChangesOverlap);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TWorkspaceEditsText] of string = (
    ('Änderung in Zeile %d, der Text hat nur %d Zeilen',
     'Änderung %d endet vor ihrem Anfang',
     'Änderungen überlappen sich'),
    ('Change in line %d, the text has only %d lines',
     'Change %d ends before its start',
     'Changes overlap'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TWorkspaceEditsText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

function ReadPosition(const ARange: TJSONObject; const AName: string; out APosition: TLspTextPosition): Boolean;
var
  mPosition: TJSONObject;
begin
  Result := ARange.TryGetValue<TJSONObject>(AName, mPosition) and
    mPosition.TryGetValue<Integer>('line', APosition.Line) and
    mPosition.TryGetValue<Integer>('character', APosition.Character);
end;

{ TLspTextEdit }

class function TLspTextEdit.FromJson(const AEdit: TJSONValue; out AResult: TLspTextEdit): Boolean;
var
  mRange: TJSONObject;
begin
  AResult := Default(TLspTextEdit);
  Result := (AEdit is TJSONObject) and TJSONObject(AEdit).TryGetValue<TJSONObject>('range', mRange) and
    ReadPosition(mRange, 'start', AResult.StartPos) and ReadPosition(mRange, 'end', AResult.EndPos) and
    TJSONObject(AEdit).TryGetValue<string>('newText', AResult.NewText);
end;

{ TLspWorkspaceEdit }

function TLspWorkspaceEdit.EditCount: Integer;
var
  mFileEdits: TLspFileEdits;
begin
  Result := 0;
  for mFileEdits in Files do
  begin
    Inc(Result, Length(mFileEdits.Edits));
  end;
end;

function TLspWorkspaceEdit.IsEmpty: Boolean;
begin
  Result := (EditCount = 0) and (Length(Operations) = 0);
end;

function TLspWorkspaceEdit.ProjectFile: string;
var
  mFileEdits: TLspFileEdits;
begin
  Result := '';
  for mFileEdits in Files do
  begin
    if SameText(ExtractFileExt(mFileEdits.FileName), '.dproj') then
    begin
      Exit(mFileEdits.FileName);
    end;
  end;
end;

function TLspWorkspaceEdit.WithoutProject(const AProject: string): TLspWorkspaceEdit;
var
  mFileEdits: TLspFileEdits;
begin
  Result := Self;
  Result.Files := nil;
  for mFileEdits in Files do
  begin
    if not SameText(mFileEdits.FileName, AProject) and
      not SameText(mFileEdits.FileName, ChangeFileExt(AProject, '.dpr')) and
      not SameText(mFileEdits.FileName, ChangeFileExt(AProject, '.dpk')) then
    begin
      Result.Files := Result.Files + [mFileEdits];
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
  mUri, mNewUri: string;
begin
  if AResult.Kind = TLspFileOperationKind.Rename then
  begin
    Result := AValue.TryGetValue<string>('oldUri', mUri) and AValue.TryGetValue<string>('newUri', mNewUri);
    if Result then
    begin
      AResult.NewFileName := TLspUris.ToPath(mNewUri);
      Result := AResult.NewFileName <> '';
    end;
  end
  else
  begin
    Result := AValue.TryGetValue<string>('uri', mUri);
  end;
  if Result then
  begin
    AResult.FileName := TLspUris.ToPath(mUri);
    Result := AResult.FileName <> '';
  end;
end;

/// <summary>Liest options; overwrite gewinnt über ignoreIfExists (LSP 3.17).</summary>
procedure ReadFileOperationOptions(const AValue: TJSONObject; var AResult: TLspFileOperation);
var
  mOptions: TJSONObject;
begin
  if AValue.TryGetValue<TJSONObject>('options', mOptions) then
  begin
    mOptions.TryGetValue<Boolean>('overwrite', AResult.Overwrite);
    mOptions.TryGetValue<Boolean>('ignoreIfExists', AResult.IgnoreIfExists);
    mOptions.TryGetValue<Boolean>('ignoreIfNotExists', AResult.IgnoreIfNotExists);
    mOptions.TryGetValue<Boolean>('recursive', AResult.Recursive);
  end;
  if AResult.Overwrite then
  begin
    AResult.IgnoreIfExists := False;
  end;
end;

class function TLspFileOperation.FromJson(const AValue: TJSONObject; out AResult: TLspFileOperation): Boolean;
var
  mKind: string;
begin
  AResult := Default(TLspFileOperation);
  Result := AValue.TryGetValue<string>('kind', mKind) and FileOperationKindOf(mKind, AResult.Kind) and
    ReadFileOperationFiles(AValue, AResult);
  if Result then
  begin
    ReadFileOperationOptions(AValue, AResult);
  end;
end;

function ReadEdits(const AUri: string; const AEdits: TJSONArray; out AFile: TLspFileEdits): Boolean;
var
  mItem: TJSONValue;
  mEdit: TLspTextEdit;
begin
  AFile.FileName := TLspUris.ToPath(AUri);
  AFile.Edits := nil;
  if (AFile.FileName = '') or (AEdits = nil) then
  begin
    Exit(False);
  end;
  for mItem in AEdits do
  begin
    if TLspTextEdit.FromJson(mItem, mEdit) then
    begin
      AFile.Edits := AFile.Edits + [mEdit];
    end;
  end;
  Result := Length(AFile.Edits) > 0;
end;

/// <summary>Stellen aus atlasUnchanged, die die Änderung nicht anpasst (mit Sicherheit).</summary>
function UnchangedPlacesOf(const AEdit: TJSONObject): TArray<TLspUnchangedPlace>;
var
  mUnchanged: TJSONArray;
  mItem: TJSONValue;
  mUri: string;
  mPlace: TLspUnchangedPlace;
begin
  Result := nil;
  if not AEdit.TryGetValue<TJSONArray>('atlasUnchanged', mUnchanged) then
  begin
    Exit;
  end;
  for mItem in mUnchanged do
  begin
    if (mItem is TJSONObject) and TJSONObject(mItem).TryGetValue<string>('uri', mUri) then
    begin
      mPlace.FileName := TLspUris.ToPath(mUri);
      mPlace.Line := TJSONObject(mItem).GetValue<Integer>('range.start.line', 0);
      mPlace.Character := TJSONObject(mItem).GetValue<Integer>('range.start.character', 0);
      mPlace.Confidence := TAtlasConfidence.FromJson(mItem);
      Result := Result + [mPlace];
    end;
  end;
end;

/// <summary>Ein Eintrag aus documentChanges: Dateioperation (mit kind) oder Textänderungen einer Datei.</summary>
procedure ReadDocumentChange(const AItem: TJSONObject; var AResult: TLspWorkspaceEdit);
var
  mDocument: TJSONObject;
  mEdits: TJSONArray;
  mUri: string;
  mFileEdits: TLspFileEdits;
  mOperation: TLspFileOperation;
begin
  if AItem.GetValue('kind') <> nil then
  begin
    if TLspFileOperation.FromJson(AItem, mOperation) then
    begin
      AResult.Operations := AResult.Operations + [mOperation];
    end
    else
    begin
      Inc(AResult.Unsupported);
    end;
  end
  else if AItem.TryGetValue<TJSONObject>('textDocument', mDocument) and mDocument.TryGetValue<string>('uri', mUri) and
    AItem.TryGetValue<TJSONArray>('edits', mEdits) and ReadEdits(mUri, mEdits, mFileEdits) then
  begin
    AResult.Files := AResult.Files + [mFileEdits];
  end;
end;

/// <summary>Textänderungen aus changes (URI auf Liste von Änderungen).</summary>
procedure ReadChanges(const AChanges: TJSONObject; var AResult: TLspWorkspaceEdit);
var
  mPair: TJSONPair;
  mFileEdits: TLspFileEdits;
begin
  for mPair in AChanges do
  begin
    if (mPair.JsonValue is TJSONArray) and ReadEdits(mPair.JsonString.Value, TJSONArray(mPair.JsonValue), mFileEdits) then
    begin
      AResult.Files := AResult.Files + [mFileEdits];
    end;
  end;
end;

class function TLspWorkspaceEdit.FromJson(const AValue: TJSONValue): TLspWorkspaceEdit;
var
  mEdit, mChanges: TJSONObject;
  mDocumentChanges: TJSONArray;
  mItem: TJSONValue;
begin
  Result := Default(TLspWorkspaceEdit);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mEdit := TJSONObject(AValue);
  Result.Unchanged := UnchangedPlacesOf(mEdit);
  // documentChanges hat Vorrang, wenn der Server beides schickt.
  if mEdit.TryGetValue<TJSONArray>('documentChanges', mDocumentChanges) then
  begin
    for mItem in mDocumentChanges do
    begin
      if mItem is TJSONObject then
      begin
        ReadDocumentChange(TJSONObject(mItem), Result);
      end;
    end;
  end
  else if mEdit.TryGetValue<TJSONObject>('changes', mChanges) then
  begin
    ReadChanges(mChanges, Result);
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
  mItems: TArray<TIndexedRange>;
  mIndex: Integer;
  mLastLine: Integer;
  mLines: TLineTable;
begin
  // Letzte gültige Zeile: Positionen dahinter sind ein Fehler, nicht still das Textende.
  mLines := TLineTable.Build(AText);
  mLastLine := mLines.LineCount - 1;
  SetLength(mItems, Length(AEdits));
  for mIndex := 0 to High(AEdits) do
  begin
    if (AEdits[mIndex].StartPos.Line > mLastLine) or (AEdits[mIndex].EndPos.Line > mLastLine) then
    begin
      raise ELspEditError.CreateFmt(UiText(TWorkspaceEditsText.ChangeInLineTheText),
        [AEdits[mIndex].EndPos.Line + 1, mLastLine + 1]);
    end;
    mItems[mIndex].Range.StartOffset := TLspTextChanges.OffsetOf(mLines, AEdits[mIndex].StartPos);
    mItems[mIndex].Range.EndOffset := TLspTextChanges.OffsetOf(mLines, AEdits[mIndex].EndPos);
    mItems[mIndex].Range.NewText := AEdits[mIndex].NewText;
    mItems[mIndex].Index := mIndex;
    if mItems[mIndex].Range.EndOffset < mItems[mIndex].Range.StartOffset then
    begin
      raise ELspEditError.CreateFmt(UiText(TWorkspaceEditsText.ChangeEndsBeforeItsStart), [mIndex + 1]);
    end;
  end;
  TArray.Sort<TIndexedRange>(mItems, TComparer<TIndexedRange>.Construct(
    function(const A, B: TIndexedRange): Integer
    begin
      Result := A.Range.StartOffset - B.Range.StartOffset;
      if Result = 0 then
      begin
        Result := A.Index - B.Index;
      end;
    end));
  SetLength(Result, Length(mItems));
  for mIndex := 0 to High(mItems) do
  begin
    if (mIndex > 0) and (mItems[mIndex].Range.StartOffset < mItems[mIndex - 1].Range.EndOffset) then
    begin
      raise ELspEditError.Create(UiText(TWorkspaceEditsText.ChangesOverlap));
    end;
    Result[mIndex] := mItems[mIndex].Range;
  end;
end;

class function TLspEdits.Apply(const AText: string; const AEdits: TArray<TLspTextEdit>): string;
var
  mRanges: TArray<TLspTextRange>;
  mRange: TLspTextRange;
  mBuilder: TStringBuilder;
  mPosition: Integer;
begin
  mRanges := Ordered(AText, AEdits);
  mBuilder := TStringBuilder.Create(Length(AText));
  try
    mPosition := 0;
    for mRange in mRanges do
    begin
      mBuilder.Append(AText, mPosition, mRange.StartOffset - mPosition);
      mBuilder.Append(mRange.NewText);
      mPosition := mRange.EndOffset;
    end;
    mBuilder.Append(AText, mPosition, Length(AText) - mPosition);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Lsp.WorkspaceEdits', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
