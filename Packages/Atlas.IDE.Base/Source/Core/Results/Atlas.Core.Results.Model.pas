unit Atlas.Core.Results.Model;

// Daten des Ergebnisfensters (#400), ohne VCL und Open Tools API:
// Fundstellen (Referenzen, Implementierungen, Umbenennen-Vorschau) mit
// Zeilentext, nach Datei gruppiert; Symbole der projektweiten Suche
// (workspace/symbol) und Einträge der Typ- und Aufrufhierarchie. Positionen
// sind 0-basiert in UTF-16-Einheiten wie im LSP. Fundstellen der Referenzsuche
// tragen ihre Treffersicherheit (#1119); die Umbenennen-Vorschau nennt nicht
// geänderte, erschlossene Stellen als erschlossene Einträge. Issues zu einer
// Methode (#1275) stehen mit ihren Commits als fertige Texte darin.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.WorkspaceEdits;

type
  TAtlasResultEntry = record
    FileName: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
    /// <summary>0-basiert.</summary>
    Character: Integer;
    /// <summary>Zeilentext ohne Einrückung.</summary>
    Text: string;
    /// <summary>Umbenennen-Vorschau: die Zeile nach der Änderung; sonst leer.</summary>
    Detail: string;
    /// <summary>Sicher oder erschlossen (#1119); Einträge ohne Referenzsuche sind sicher.</summary>
    Confidence: TAtlasConfidence;
    class function Create(const AFileName: string; ALine, ACharacter: Integer): TAtlasResultEntry; static;
  end;

  TAtlasResultGroup = record
    FileName: string;
    Entries: TArray<TAtlasResultEntry>;
    /// <summary>"Unit1.pas (3)".</summary>
    function Caption: string;
  end;

  /// <summary>Commit unter einem Issue (#1275).</summary>
  TAtlasResultCommit = record
    /// <summary>Kennung für OnIssueCommit (Index beim Aufrufer).</summary>
    Id: Integer;
    Text: string;
  end;

  /// <summary>Issue mit den Commits, die eine Methode bzw. Unit geändert haben (#1275).</summary>
  TAtlasResultIssue = record
    /// <summary>Kennung für OnIssueOpen und SetIssueText (Index beim Aufrufer).</summary>
    Id: Integer;
    Text: string;
    Commits: TArray<TAtlasResultCommit>;
  end;

  /// <summary>Liefert den Text einer Datei (offener Puffer oder Platte); '' wenn sie fehlt.</summary>
  TAtlasReadText = reference to function(const AFileName: string): string;

  /// <summary>Seit A-09 im Lsp-Feature (Atlas.Core.Lsp.Contract); Aliase für bestehende Nutzer.</summary>
  TAtlasSymbol = Atlas.Core.Lsp.Contract.TAtlasSymbol;
  TAtlasHierarchyDirection = Atlas.Core.Lsp.Contract.TAtlasHierarchyDirection;
  TAtlasHierarchyItem = Atlas.Core.Lsp.Contract.TAtlasHierarchyItem;
  TAtlasConfidence = Atlas.Core.Lsp.Contract.TAtlasConfidence;

  TAtlasResults = class
  public
    /// <summary>Nach Datei gruppiert (Groß-/Kleinschreibung egal), Dateien nach Name, darin nach Position.</summary>
    class function Group(const AEntries: TArray<TAtlasResultEntry>): TArray<TAtlasResultGroup>; static;
    /// <summary>Setzt Text jedes Eintrags aus seiner Zeile; liest jede Datei nur einmal.</summary>
    class procedure FillText(var AEntries: TArray<TAtlasResultEntry>; const AReadText: TAtlasReadText); static;
    /// <summary>Zeilen eines Textes (CRLF, LF oder CR).</summary>
    class function Lines(const AText: string): TArray<string>; static;
    /// <summary>
    /// Fundstellen einer Umbenennung mit Vorschau: je geänderte Zeile ein Eintrag, Text vorher,
    /// Detail nachher. Änderungen über mehrere Zeilen zeigen nur ihren neuen Text. Dateioperationen
    /// (#721) stehen vorn mit Zeile 0: Text = alter Dateiname (leer beim Anlegen), Detail = neuer
    /// (leer beim Löschen).
    /// </summary>
    class function RenamePreview(const AEdit: TLspWorkspaceEdit; const AReadText: TAtlasReadText):
      TArray<TAtlasResultEntry>; static;
    /// <summary>Nur die sicheren Fundstellen (#1119).</summary>
    class function SureOnly(const AEntries: TArray<TAtlasResultEntry>): TArray<TAtlasResultEntry>; static;
    /// <summary>Anzahl der erschlossenen Fundstellen (#1119).</summary>
    class function InferredCount(const AEntries: TArray<TAtlasResultEntry>): Integer; static;
    /// <summary>Kürzel wie im Vervollständigungs-Popup (fn, pr, fd, ty, …) zu einem LSP SymbolKind.</summary>
    class function SymbolBadge(AKind: Integer): string; static;
    /// <summary>Richtung für die Anfrage zum Vorbereiten: Aufrufe oder Typen.</summary>
    class function IsCallHierarchy(ADirection: TAtlasHierarchyDirection): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults;

{ TAtlasResultEntry }

class function TAtlasResultEntry.Create(const AFileName: string; ALine, ACharacter: Integer): TAtlasResultEntry;
begin
  Result := Default(TAtlasResultEntry);
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Character := ACharacter;
end;

{ TAtlasResultGroup }

function TAtlasResultGroup.Caption: string;
begin
  Result := Format('%s (%d)', [ExtractFileName(FileName), Length(Entries)]);
end;

{ TAtlasResults }

class function TAtlasResults.Lines(const AText: string): TArray<string>;
begin
  Result := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
end;

class function TAtlasResults.Group(const AEntries: TArray<TAtlasResultEntry>): TArray<TAtlasResultGroup>;
var
  mGroups: TList<TAtlasResultGroup>;
  mIndex: TDictionary<string, Integer>;
  mEntry: TAtlasResultEntry;
  mPosition: Integer;
  mBucket: TAtlasResultGroup;
  mItem: Integer;
  mEntries: TArray<TAtlasResultEntry>;
begin
  mGroups := TList<TAtlasResultGroup>.Create;
  mIndex := TDictionary<string, Integer>.Create;
  try
    for mEntry in AEntries do
    begin
      if not mIndex.TryGetValue(AnsiUpperCase(mEntry.FileName), mPosition) then
      begin
        mBucket := Default(TAtlasResultGroup);
        mBucket.FileName := mEntry.FileName;
        mPosition := mGroups.Add(mBucket);
        mIndex.Add(AnsiUpperCase(mEntry.FileName), mPosition);
      end;
      mBucket := mGroups[mPosition];
      mBucket.Entries := mBucket.Entries + [mEntry];
      mGroups[mPosition] := mBucket;
    end;
    for mItem := 0 to mGroups.Count - 1 do
    begin
      mBucket := mGroups[mItem];
      mEntries := mBucket.Entries;
      TArray.Sort<TAtlasResultEntry>(mEntries, TComparer<TAtlasResultEntry>.Construct(
        function(const A, B: TAtlasResultEntry): Integer
        begin
          Result := A.Line - B.Line;
          if Result = 0 then
          begin
            Result := A.Character - B.Character;
          end;
        end));
      mBucket.Entries := mEntries;
      mGroups[mItem] := mBucket;
    end;
    mGroups.Sort(TComparer<TAtlasResultGroup>.Construct(
      function(const A, B: TAtlasResultGroup): Integer
      begin
        Result := CompareText(ExtractFileName(A.FileName), ExtractFileName(B.FileName));
        if Result = 0 then
        begin
          Result := CompareText(A.FileName, B.FileName);
        end;
      end));
    Result := mGroups.ToArray;
  finally
    mIndex.Free;
    mGroups.Free;
  end;
end;

class procedure TAtlasResults.FillText(var AEntries: TArray<TAtlasResultEntry>; const AReadText: TAtlasReadText);
var
  mCache: TDictionary<string, TArray<string>>;
  mIndex: Integer;
  mFileLines: TArray<string>;
begin
  mCache := TDictionary<string, TArray<string>>.Create;
  try
    for mIndex := 0 to High(AEntries) do
    begin
      if not mCache.TryGetValue(AnsiUpperCase(AEntries[mIndex].FileName), mFileLines) then
      begin
        mFileLines := Lines(AReadText(AEntries[mIndex].FileName));
        mCache.Add(AnsiUpperCase(AEntries[mIndex].FileName), mFileLines);
      end;
      if (AEntries[mIndex].Line >= 0) and (AEntries[mIndex].Line < Length(mFileLines)) then
      begin
        AEntries[mIndex].Text := Trim(mFileLines[AEntries[mIndex].Line]);
      end;
    end;
  finally
    mCache.Free;
  end;
end;

/// <summary>Einträge für angelegte, umbenannte und gelöschte Dateien.</summary>
function OperationEntries(const AEdit: TLspWorkspaceEdit): TArray<TAtlasResultEntry>;
var
  mOperation: TLspFileOperation;
  mEntry: TAtlasResultEntry;
begin
  Result := nil;
  for mOperation in AEdit.Operations do
  begin
    mEntry := TAtlasResultEntry.Create(mOperation.FileName, 0, 0);
    case mOperation.Kind of
      TLspFileOperationKind.Create:
        mEntry.Detail := ExtractFileName(mOperation.FileName);
      TLspFileOperationKind.Rename:
        begin
          mEntry.Text := ExtractFileName(mOperation.FileName);
          mEntry.Detail := ExtractFileName(mOperation.NewFileName);
        end;
    else
      mEntry.Text := ExtractFileName(mOperation.FileName);
    end;
    Result := Result + [mEntry];
  end;
end;

/// <summary>Zeilen mit Änderungen, aufsteigend, jede einmal.</summary>
function ChangedLines(const AFileEdits: TLspFileEdits): TArray<Integer>;
var
  mChanged: TList<Integer>;
  mEdit: TLspTextEdit;
begin
  mChanged := TList<Integer>.Create;
  try
    for mEdit in AFileEdits.Edits do
    begin
      if not mChanged.Contains(mEdit.StartPos.Line) then
      begin
        mChanged.Add(mEdit.StartPos.Line);
      end;
    end;
    mChanged.Sort;
    Result := mChanged.ToArray;
  finally
    mChanged.Free;
  end;
end;

/// <summary>Zeile nach den Änderungen AOnLine, die in ALine beginnen. Nur Änderungen innerhalb der Zeile lassen
/// sich als Zeile zeigen; sonst der neue Text der übergreifenden Änderung.</summary>
function AfterText(const ABefore: string; const AOnLine: TArray<TLspTextEdit>; ALine: Integer): string;
var
  mEdit, mShifted: TLspTextEdit;
  mSameLine: TArray<TLspTextEdit>;
begin
  Result := '';
  mSameLine := nil;
  for mEdit in AOnLine do
  begin
    if mEdit.EndPos.Line <> ALine then
    begin
      Result := mEdit.NewText;
    end
    else
    begin
      // Auf die eine Zeile bezogen: Zeile 0 in ABefore.
      mShifted := mEdit;
      mShifted.StartPos.Line := 0;
      mShifted.EndPos.Line := 0;
      mSameLine := mSameLine + [mShifted];
    end;
  end;
  if Result = '' then
    try
      Result := TLspEdits.Apply(ABefore, mSameLine);
    except
      on ELspEditError do
        Result := ABefore;
    end;
end;

/// <summary>Eintrag für eine geänderte Zeile: Text vorher, Detail nachher.</summary>
function LineEntry(const AFileEdits: TLspFileEdits; const AFileLines: TArray<string>;
  ALine: Integer): TAtlasResultEntry;
var
  mBefore: string;
  mOnLine: TArray<TLspTextEdit>;
  mEdit: TLspTextEdit;
begin
  mBefore := '';
  if (ALine >= 0) and (ALine < Length(AFileLines)) then
  begin
    mBefore := AFileLines[ALine];
  end;
  mOnLine := nil;
  for mEdit in AFileEdits.Edits do
  begin
    if mEdit.StartPos.Line = ALine then
    begin
      mOnLine := mOnLine + [mEdit];
    end;
  end;
  Result := TAtlasResultEntry.Create(AFileEdits.FileName, ALine, mOnLine[0].StartPos.Character);
  for mEdit in mOnLine do
  begin
    if mEdit.StartPos.Character < Result.Character then
    begin
      Result.Character := mEdit.StartPos.Character;
    end;
  end;
  Result.Text := Trim(mBefore);
  Result.Detail := Trim(AfterText(mBefore, mOnLine, ALine));
end;

/// <summary>Nicht geänderte, erschlossene Stellen (#1119): zum Prüfen, ohne Vorschau.</summary>
function UnchangedEntries(const AEdit: TLspWorkspaceEdit): TArray<TAtlasResultEntry>;
var
  mPlace: TLspUnchangedPlace;
  mEntry: TAtlasResultEntry;
begin
  Result := nil;
  for mPlace in AEdit.Unchanged do
  begin
    mEntry := TAtlasResultEntry.Create(mPlace.FileName, mPlace.Line, mPlace.Character);
    mEntry.Confidence := mPlace.Confidence;
    Result := Result + [mEntry];
  end;
end;
class function TAtlasResults.RenamePreview(const AEdit: TLspWorkspaceEdit; const AReadText: TAtlasReadText):
  TArray<TAtlasResultEntry>;
var
  mFileEdits: TLspFileEdits;
  mFileLines: TArray<string>;
  mLine: Integer;
  mUnchanged: TArray<TAtlasResultEntry>;
begin
  Result := OperationEntries(AEdit);
  for mFileEdits in AEdit.Files do
  begin
    mFileLines := TAtlasResults.Lines(AReadText(mFileEdits.FileName));
    for mLine in ChangedLines(mFileEdits) do
    begin
      Result := Result + [LineEntry(mFileEdits, mFileLines, mLine)];
    end;
  end;
  mUnchanged := UnchangedEntries(AEdit);
  FillText(mUnchanged, AReadText);
  Result := Result + mUnchanged;
end;

class function TAtlasResults.SureOnly(const AEntries: TArray<TAtlasResultEntry>): TArray<TAtlasResultEntry>;
var
  mEntry: TAtlasResultEntry;
begin
  Result := nil;
  for mEntry in AEntries do
  begin
    if not mEntry.Confidence.Inferred then
    begin
      Result := Result + [mEntry];
    end;
  end;
end;

class function TAtlasResults.InferredCount(const AEntries: TArray<TAtlasResultEntry>): Integer;
var
  mEntry: TAtlasResultEntry;
begin
  Result := 0;
  for mEntry in AEntries do
  begin
    if mEntry.Confidence.Inferred then
    begin
      Inc(Result);
    end;
  end;
end;

class function TAtlasResults.SymbolBadge(AKind: Integer): string;
begin
  // SymbolKind nach LSP 3.17.
  case AKind of
    1, 2, 3, 4:
      Result := 'un';
    5, 10, 11, 23:
      Result := 'ty';
    6, 9, 12:
      Result := 'fn';
    7:
      Result := 'pr';
    8:
      Result := 'fd';
    13:
      Result := 'va';
    14, 22:
      Result := 'co';
    24:
      Result := 'ev';
    26:
      Result := 'ty';
  else
    Result := 'kw';
  end;
end;

class function TAtlasResults.IsCallHierarchy(ADirection: TAtlasHierarchyDirection): Boolean;
begin
  Result := ADirection in [TAtlasHierarchyDirection.Incoming, TAtlasHierarchyDirection.Outgoing];
end;

end.
