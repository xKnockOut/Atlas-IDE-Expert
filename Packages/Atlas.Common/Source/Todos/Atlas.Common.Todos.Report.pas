unit Atlas.Common.Todos.Report;

// TODO-Übersicht (#68) als JSON und Markdown für das MCP-Werkzeug get_todos,
// den Befehl atlas.server.todos, die Kommandozeile (--todos) und die
// Projekt-Zusammenfassung der Willkommensseite (#592, Projektverlauf #758).
//
// JSON (Format 1, Zeilen und Spalten ab 1):
//   {"format": 1,
//    "summary": {"files": 2, "open": 5, "done": 1,
//                "keywords": {"FIXME": 1, "TODO": 4}},
//    "files": [{"file": "Source/Main.pas", "unit": "Main", "todos": [
//      {"keyword": "TODO", "done": false, "priority": 1, "owner": "Marco",
//       "category": "GUI", "text": "Fokus setzen", "line": 12, "character": 3,
//       "endLine": 12}]}]}
// "files" zählt Dateien mit offenen Einträgen, "open" die offenen, "done" die
// erledigten Einträge, "keywords" die offenen je Marke (nach Name sortiert).
// Die Zusammenfassung zählt, was der Aufrufer übergibt; ein Filter wirkt also
// vorher (TTodoScanner.Filter).
// Der Text entsteht ohne System.JSON, damit die Unit überall gleich arbeitet.

interface

uses
  Atlas.Common.Todos.Contract;

type
  /// <summary>Zahlen über alle Einträge eines Berichts.</summary>
  TTodoSummary = record
    /// <summary>Dateien mit mindestens einem offenen Eintrag.</summary>
    Files: Integer;
    Open: Integer;
    Done: Integer;
    /// <summary>Marken der offenen Einträge, nach Name sortiert; Anzahl in KeywordCounts.</summary>
    Keywords: TArray<string>;
    KeywordCounts: TArray<Integer>;
    /// <summary>Offene Einträge mit der Marke AKeyword; 0, wenn es keine gibt.</summary>
    function CountOf(const AKeyword: string): Integer;
  end;

  TTodoReport = class
  public const
    Format = 1;
  public
    class function Summarize(const AFiles: TArray<TFileTodos>): TTodoSummary; static;
    class function SummaryJson(const ASummary: TTodoSummary): string; static;
    class function EntryJson(const AEntry: TTodoEntry): string; static;
    /// <summary>{"file": …, "unit": …, "todos": […]} einer Datei.</summary>
    class function FileJson(const AFile: TFileTodos): string; static;
    /// <summary>Vollständige Daten (siehe Kopf der Unit); ARoot (absolut) erscheint als "root", wenn nicht leer.</summary>
    class function Json(const AFiles: TArray<TFileTodos>; const ARoot: string): string; overload; static;
    class function Json(const AFiles: TArray<TFileTodos>): string; overload; static;
    /// <summary>Übersicht als Markdown: Zahlen, Kategorien, Personen und je Unit eine Tabelle. ATitle z. B. der
    /// Projektname.</summary>
    class function Markdown(const AFiles: TArray<TFileTodos>; const ATitle: string): string; static;
    /// <summary>Kurzbeschreibung eines Eintrags: "TODO 1 [GUI, Marco]: Text".</summary>
    class function Caption(const AEntry: TTodoEntry): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Metrics.Report;

const
  LineBreak = #13#10;

function JsonText(const AText: string): string;
begin
  Result := TMetricsReport.JsonString(AText);
end;

function Cell(const AText: string): string;
begin
  Result := StringReplace(AText, '|', '\|', [rfReplaceAll]);
end;

{ TTodoSummary }

function TTodoSummary.CountOf(const AKeyword: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Keywords) do
    if SameText(Keywords[Index], AKeyword) then
      Exit(KeywordCounts[Index]);
  Result := 0;
end;

{ TTodoReport }

class function TTodoReport.Summarize(const AFiles: TArray<TFileTodos>): TTodoSummary;
var
  Counts: TDictionary<string, Integer>;
  FileItem: TFileTodos;
  Entry: TTodoEntry;
  HasOpen: Boolean;
  Count, Index: Integer;
  Names: TArray<string>;
begin
  Result := Default(TTodoSummary);
  Result.Keywords := nil;
  Result.KeywordCounts := nil;
  Counts := TDictionary<string, Integer>.Create;
  try
    for FileItem in AFiles do
    begin
      HasOpen := False;
      for Entry in FileItem.Entries do
        if Entry.Done then
          Inc(Result.Done)
        else
        begin
          Inc(Result.Open);
          HasOpen := True;
          if not Counts.TryGetValue(Entry.Keyword, Count) then
            Count := 0;
          Counts.AddOrSetValue(Entry.Keyword, Count + 1);
        end;
      if HasOpen then
        Inc(Result.Files);
    end;
    Names := Counts.Keys.ToArray;
    TArray.Sort<string>(Names);
    SetLength(Result.KeywordCounts, Length(Names));
    for Index := 0 to High(Names) do
      Result.KeywordCounts[Index] := Counts[Names[Index]];
    Result.Keywords := Names;
  finally
    Counts.Free;
  end;
end;

class function TTodoReport.SummaryJson(const ASummary: TTodoSummary): string;
var
  Index: Integer;
  Keywords: string;
begin
  Keywords := '';
  for Index := 0 to High(ASummary.Keywords) do
  begin
    if Index > 0 then
      Keywords := Keywords + ', ';
    Keywords := Keywords + JsonText(ASummary.Keywords[Index]) + ': ' + IntToStr(ASummary.KeywordCounts[Index]);
  end;
  Result := '{"files": ' + IntToStr(ASummary.Files) + ', "open": ' + IntToStr(ASummary.Open) + ', "done": ' +
    IntToStr(ASummary.Done) + ', "keywords": {' + Keywords + '}}';
end;

class function TTodoReport.EntryJson(const AEntry: TTodoEntry): string;
begin
  Result := '{"keyword": ' + JsonText(AEntry.Keyword) + ', "done": ' + LowerCase(BoolToStr(AEntry.Done, True)) +
    ', "priority": ' + IntToStr(AEntry.Priority) + ', "owner": ' + JsonText(AEntry.Owner) + ', "category": ' +
    JsonText(AEntry.Category) + ', "text": ' + JsonText(AEntry.Text) + ', "line": ' +
    IntToStr(AEntry.Range.StartPos.Line + 1) + ', "character": ' + IntToStr(AEntry.Range.StartPos.Character + 1) +
    ', "endLine": ' + IntToStr(AEntry.Range.EndPos.Line + 1) + '}';
end;

class function TTodoReport.FileJson(const AFile: TFileTodos): string;
var
  Index: Integer;
begin
  Result := '{"file": ' + JsonText(AFile.Path) + ', "unit": ' + JsonText(AFile.UnitName) + ', "todos": [';
  for Index := 0 to High(AFile.Entries) do
  begin
    if Index > 0 then
      Result := Result + ', ';
    Result := Result + EntryJson(AFile.Entries[Index]);
  end;
  Result := Result + ']}';
end;

class function TTodoReport.Json(const AFiles: TArray<TFileTodos>; const ARoot: string): string;
var
  Builder: TStringBuilder;
  Index: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('{"format": ').Append(IntToStr(Format));
    if ARoot <> '' then
      Builder.Append(', "root": ').Append(JsonText(ARoot));
    Builder.Append(', "summary": ').Append(SummaryJson(Summarize(AFiles))).Append(', "files": [');
    for Index := 0 to High(AFiles) do
    begin
      if Index > 0 then
        Builder.Append(',');
      Builder.Append(LineBreak).Append('  ').Append(FileJson(AFiles[Index]));
    end;
    Builder.Append(']}').Append(LineBreak);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TTodoReport.Json(const AFiles: TArray<TFileTodos>): string;
begin
  Result := Json(AFiles, '');
end;

class function TTodoReport.Caption(const AEntry: TTodoEntry): string;
var
  Details: string;
begin
  Result := AEntry.Keyword;
  if AEntry.Priority > 0 then
    Result := Result + ' ' + IntToStr(AEntry.Priority);
  Details := AEntry.Category;
  if AEntry.Owner <> '' then
  begin
    if Details <> '' then
      Details := Details + ', ';
    Details := Details + AEntry.Owner;
  end;
  if Details <> '' then
    Result := Result + ' [' + Details + ']';
  if AEntry.Text <> '' then
    Result := Result + ': ' + AEntry.Text;
end;

/// <summary>Anzahl der Einträge je Wert (Kategorie oder Person), meiste zuerst; leere Werte als „(ohne)“.</summary>
procedure AppendCounts(ABuilder: TStringBuilder; const AFiles: TArray<TFileTodos>; AOwner: Boolean;
  const AHeading, AColumn: string);
var
  Counts: TDictionary<string, Integer>;
  FileItem: TFileTodos;
  Entry: TTodoEntry;
  Value: string;
  Count: Integer;
  Names: TArray<string>;
begin
  Counts := TDictionary<string, Integer>.Create;
  try
    for FileItem in AFiles do
      for Entry in FileItem.Entries do
      begin
        if AOwner then
          Value := Entry.Owner
        else
          Value := Entry.Category;
        if Value = '' then
          Value := '(ohne)';
        if not Counts.TryGetValue(Value, Count) then
          Count := 0;
        Counts.AddOrSetValue(Value, Count + 1);
      end;
    // Nur ein Wert „(ohne)“: die Tabelle sagt nichts.
    if (Counts.Count = 0) or ((Counts.Count = 1) and Counts.ContainsKey('(ohne)')) then
      Exit;
    Names := Counts.Keys.ToArray;
    TArray.Sort<string>(Names, TComparer<string>.Construct(
      function(const A, B: string): Integer
      begin
        Result := Counts[B] - Counts[A];
        if Result = 0 then
          Result := CompareText(A, B);
      end));
    ABuilder.Append(LineBreak).Append('## ').Append(AHeading).Append(LineBreak).Append(LineBreak);
    ABuilder.Append('| ').Append(AColumn).Append(' | Einträge |').Append(LineBreak);
    ABuilder.Append('|---|---:|').Append(LineBreak);
    for Value in Names do
      ABuilder.Append('| ').Append(Cell(Value)).Append(' | ').Append(IntToStr(Counts[Value])).Append(' |')
        .Append(LineBreak);
  finally
    Counts.Free;
  end;
end;

class function TTodoReport.Markdown(const AFiles: TArray<TFileTodos>; const ATitle: string): string;
var
  Builder: TStringBuilder;
  Summary: TTodoSummary;
  FileItem: TFileTodos;
  Entry: TTodoEntry;
  Index: Integer;
  Kind, Priority: string;
begin
  Summary := Summarize(AFiles);
  Builder := TStringBuilder.Create;
  try
    if ATitle <> '' then
      Builder.Append('# TODOs: ').Append(ATitle).Append(LineBreak)
    else
      Builder.Append('# TODOs').Append(LineBreak);
    Builder.Append(LineBreak);
    Builder.Append(IntToStr(Summary.Open)).Append(' offene Einträge in ').Append(IntToStr(Summary.Files))
      .Append(' Dateien');
    if Summary.Done > 0 then
      Builder.Append(', ').Append(IntToStr(Summary.Done)).Append(' erledigt');
    if Length(Summary.Keywords) > 0 then
    begin
      Builder.Append(' (');
      for Index := 0 to High(Summary.Keywords) do
      begin
        if Index > 0 then
          Builder.Append(', ');
        Builder.Append(Summary.Keywords[Index]).Append(' ').Append(IntToStr(Summary.KeywordCounts[Index]));
      end;
      Builder.Append(')');
    end;
    Builder.Append('.').Append(LineBreak);
    if Length(AFiles) = 0 then
    begin
      Builder.Append(LineBreak).Append('Keine Einträge.').Append(LineBreak);
      Exit(Builder.ToString);
    end;

    AppendCounts(Builder, AFiles, False, 'Nach Kategorie', 'Kategorie');
    AppendCounts(Builder, AFiles, True, 'Nach Person', 'Person');

    for FileItem in AFiles do
    begin
      Builder.Append(LineBreak).Append('## ').Append(FileItem.UnitName).Append(' (')
        .Append(IntToStr(Length(FileItem.Entries))).Append(')').Append(LineBreak).Append(LineBreak);
      Builder.Append('`').Append(FileItem.Path).Append('`').Append(LineBreak).Append(LineBreak);
      Builder.Append('| Zeile | Marke | Priorität | Kategorie | Person | Text |').Append(LineBreak);
      Builder.Append('|---:|---|---:|---|---|---|').Append(LineBreak);
      for Entry in FileItem.Entries do
      begin
        Kind := Entry.Keyword;
        if Entry.Done then
          Kind := Kind + ' (erledigt)';
        Priority := '';
        if Entry.Priority > 0 then
          Priority := IntToStr(Entry.Priority);
        Builder.Append('| ').Append(IntToStr(Entry.Range.StartPos.Line + 1)).Append(' | ').Append(Kind)
          .Append(' | ').Append(Priority).Append(' | ').Append(Cell(Entry.Category)).Append(' | ')
          .Append(Cell(Entry.Owner)).Append(' | ').Append(Cell(Entry.Text)).Append(' |').Append(LineBreak);
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

end.
