unit Atlas.Core.Results.Model;

// Daten des Ergebnisfensters (#400), ohne VCL und Open Tools API:
// Fundstellen (Referenzen, Implementierungen, Umbenennen-Vorschau) mit
// Zeilentext, nach Datei gruppiert; Symbole der projektweiten Suche
// (workspace/symbol) und Einträge der Typ- und Aufrufhierarchie. Positionen
// sind 0-basiert in UTF-16-Einheiten wie im LSP.

interface

uses
  System.SysUtils,
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
    class function Create(const AFileName: string; ALine, ACharacter: Integer): TAtlasResultEntry; static;
  end;

  TAtlasResultGroup = record
    FileName: string;
    Entries: TArray<TAtlasResultEntry>;
    /// <summary>"Unit1.pas (3)".</summary>
    function Caption: string;
  end;

  /// <summary>Liefert den Text einer Datei (offener Puffer oder Platte); '' wenn sie fehlt.</summary>
  TAtlasReadText = reference to function(const AFileName: string): string;

  TAtlasSymbol = record
    Name: string;
    /// <summary>Enthaltende Klasse oder Unit (containerName).</summary>
    Container: string;
    /// <summary>LSP SymbolKind.</summary>
    Kind: Integer;
    FileName: string;
    Line: Integer;
    Character: Integer;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Richtung einer Hierarchie: Aufrufer, Aufgerufene, Vorfahren, Nachfahren.</summary>
  TAtlasHierarchyDirection = (Incoming, Outgoing, Supertypes, Subtypes);
{$SCOPEDENUMS OFF}

  TAtlasHierarchyItem = record
    Name: string;
    Detail: string;
    /// <summary>LSP SymbolKind.</summary>
    Kind: Integer;
    FileName: string;
    /// <summary>Anfang des Namens (selectionRange), 0-basiert.</summary>
    Line: Integer;
    Character: Integer;
    /// <summary>Der Eintrag als JSON, so wie ihn der Server für Folgeanfragen zurückhaben will.</summary>
    Raw: string;
  end;

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
    /// Detail nachher. Änderungen über mehrere Zeilen zeigen nur ihren neuen Text.
    /// </summary>
    class function RenamePreview(const AEdit: TLspWorkspaceEdit; const AReadText: TAtlasReadText):
      TArray<TAtlasResultEntry>; static;
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
  Groups: TList<TAtlasResultGroup>;
  Index: TDictionary<string, Integer>;
  Entry: TAtlasResultEntry;
  Position: Integer;
  Bucket: TAtlasResultGroup;
  Item: Integer;
  Entries: TArray<TAtlasResultEntry>;
begin
  Groups := TList<TAtlasResultGroup>.Create;
  Index := TDictionary<string, Integer>.Create;
  try
    for Entry in AEntries do
    begin
      if not Index.TryGetValue(AnsiUpperCase(Entry.FileName), Position) then
      begin
        Bucket := Default(TAtlasResultGroup);
        Bucket.FileName := Entry.FileName;
        Position := Groups.Add(Bucket);
        Index.Add(AnsiUpperCase(Entry.FileName), Position);
      end;
      Bucket := Groups[Position];
      Bucket.Entries := Bucket.Entries + [Entry];
      Groups[Position] := Bucket;
    end;
    for Item := 0 to Groups.Count - 1 do
    begin
      Bucket := Groups[Item];
      Entries := Bucket.Entries;
      TArray.Sort<TAtlasResultEntry>(Entries, TComparer<TAtlasResultEntry>.Construct(
        function(const A, B: TAtlasResultEntry): Integer
        begin
          Result := A.Line - B.Line;
          if Result = 0 then
            Result := A.Character - B.Character;
        end));
      Bucket.Entries := Entries;
      Groups[Item] := Bucket;
    end;
    Groups.Sort(TComparer<TAtlasResultGroup>.Construct(
      function(const A, B: TAtlasResultGroup): Integer
      begin
        Result := CompareText(ExtractFileName(A.FileName), ExtractFileName(B.FileName));
        if Result = 0 then
          Result := CompareText(A.FileName, B.FileName);
      end));
    Result := Groups.ToArray;
  finally
    Index.Free;
    Groups.Free;
  end;
end;

class procedure TAtlasResults.FillText(var AEntries: TArray<TAtlasResultEntry>; const AReadText: TAtlasReadText);
var
  Cache: TDictionary<string, TArray<string>>;
  Index: Integer;
  FileLines: TArray<string>;
begin
  Cache := TDictionary<string, TArray<string>>.Create;
  try
    for Index := 0 to High(AEntries) do
    begin
      if not Cache.TryGetValue(AnsiUpperCase(AEntries[Index].FileName), FileLines) then
      begin
        FileLines := Lines(AReadText(AEntries[Index].FileName));
        Cache.Add(AnsiUpperCase(AEntries[Index].FileName), FileLines);
      end;
      if (AEntries[Index].Line >= 0) and (AEntries[Index].Line < Length(FileLines)) then
        AEntries[Index].Text := Trim(FileLines[AEntries[Index].Line]);
    end;
  finally
    Cache.Free;
  end;
end;

class function TAtlasResults.RenamePreview(const AEdit: TLspWorkspaceEdit; const AReadText: TAtlasReadText):
  TArray<TAtlasResultEntry>;
var
  FileEdits: TLspFileEdits;
  FileLines: TArray<string>;
  OnLine, InLine: TArray<TLspTextEdit>;
  Edit, Shifted: TLspTextEdit;
  Changed: TList<Integer>;
  Line: Integer;
  Before, After: string;
  Entry: TAtlasResultEntry;
begin
  Result := nil;
  Changed := TList<Integer>.Create;
  try
    for FileEdits in AEdit.Files do
    begin
      FileLines := TAtlasResults.Lines(AReadText(FileEdits.FileName));
      Changed.Clear;
      for Edit in FileEdits.Edits do
        if not Changed.Contains(Edit.StartPos.Line) then
          Changed.Add(Edit.StartPos.Line);
      Changed.Sort;
      for Line in Changed do
      begin
        Before := '';
        if (Line >= 0) and (Line < Length(FileLines)) then
          Before := FileLines[Line];
        OnLine := nil;
        for Edit in FileEdits.Edits do
          if Edit.StartPos.Line = Line then
            OnLine := OnLine + [Edit];
        Entry := TAtlasResultEntry.Create(FileEdits.FileName, Line, OnLine[0].StartPos.Character);
        for Edit in OnLine do
          if Edit.StartPos.Character < Entry.Character then
            Entry.Character := Edit.StartPos.Character;
        Entry.Text := Trim(Before);
        // Nur Änderungen innerhalb der Zeile lassen sich als Zeile zeigen.
        After := '';
        InLine := nil;
        for Edit in OnLine do
          if Edit.EndPos.Line <> Line then
            After := Edit.NewText
          else
          begin
            // Auf die eine Zeile bezogen: Zeile 0 in Before.
            Shifted := Edit;
            Shifted.StartPos.Line := 0;
            Shifted.EndPos.Line := 0;
            InLine := InLine + [Shifted];
          end;
        if After = '' then
          try
            After := TLspEdits.Apply(Before, InLine);
          except
            on ELspEditError do
              After := Before;
          end;
        Entry.Detail := Trim(After);
        Result := Result + [Entry];
      end;
    end;
  finally
    Changed.Free;
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
