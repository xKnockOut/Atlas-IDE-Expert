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
    cFormat = 1;
  public
    class function Summarize(const AFiles: TArray<TFileTodos>): TTodoSummary; static;
    class function SummaryJson(const ASummary: TTodoSummary): string; static;
    class function EntryJson(const AEntry: TTodoEntry): string; static;
    /// <summary>{"file": …, "unit": …, "todos": […]} einer Datei.</summary>
    class function FileJson(const AFile: TFileTodos): string; static;
    /// <summary>Vollständige Daten (siehe Kopf der Unit); ARoot (absolut) erscheint als "root", wenn nicht
    /// leer.</summary>
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
  Atlas.Common.Metrics.Report,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TTodosReportText = (Entries, OpenEntriesIn, LineMarkerPriorityCategoryPerson, NoEntries, ByCategory, ByPerson, Done,
    Done2, Category);

const
  cTexts: array[TTodosReportText] of TAtlasText = (
    (De: ' | Einträge |'; En: ' | Entries |'),
    (De: ' offene Einträge in '; En: ' open entries in '),
    (De: '| Zeile | Marke | Priorität | Kategorie | Person | Text |';
     En: '| Line | Marker | Priority | Category | Person | Text |'),
    (De: 'Keine Einträge.'; En: 'No entries.'),
    (De: 'Nach Kategorie'; En: 'By category'),
    (De: 'Nach Person'; En: 'By person'),
    (De: ' erledigt'; En: ' done'),
    (De: ' (erledigt)'; En: ' (done)'),
    (De: 'Kategorie'; En: 'Category'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Wert und Anzahl seiner Einträge.</summary>
  TCountPair = TPair<string, Integer>;

const
  cLineBreak = #13#10;

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
  mIndex: Integer;
begin
  for mIndex := 0 to High(Keywords) do
  begin
    if SameText(Keywords[mIndex], AKeyword) then
    begin
      Exit(KeywordCounts[mIndex]);
    end;
  end;
  Result := 0;
end;

/// <summary>Zählt AKey in ACounts um eins hoch.</summary>
procedure CountKey(ACounts: TDictionary<string, Integer>; const AKey: string);
var
  mCount: Integer;
begin
  if not ACounts.TryGetValue(AKey, mCount) then
  begin
    mCount := 0;
  end;
  ACounts.AddOrSetValue(AKey, mCount + 1);
end;

/// <summary>Zählt die Einträge von AFile in ASummary und offene je Marke in ACounts.</summary>
procedure SummarizeFile(const AFile: TFileTodos; var ASummary: TTodoSummary; ACounts: TDictionary<string, Integer>);
var
  mEntry: TTodoEntry;
  mHasOpen: Boolean;
begin
  mHasOpen := False;
  for mEntry in AFile.Entries do
  begin
    if mEntry.Done then
    begin
      Inc(ASummary.Done);
    end
    else
    begin
      Inc(ASummary.Open);
      mHasOpen := True;
      CountKey(ACounts, mEntry.Keyword);
    end;
  end;
  if mHasOpen then
  begin
    Inc(ASummary.Files);
  end;
end;

{ TTodoReport }

class function TTodoReport.Summarize(const AFiles: TArray<TFileTodos>): TTodoSummary;
var
  mCounts: TDictionary<string, Integer>;
  mFileItem: TFileTodos;
  mIndex: Integer;
  mNames: TArray<string>;
begin
  Result := Default(TTodoSummary);
  Result.Keywords := nil;
  Result.KeywordCounts := nil;
  mCounts := TDictionary<string, Integer>.Create;
  try
    for mFileItem in AFiles do
    begin
      SummarizeFile(mFileItem, Result, mCounts);
    end;
    mNames := mCounts.Keys.ToArray;
    TArray.Sort<string>(mNames);
    SetLength(Result.KeywordCounts, Length(mNames));
    for mIndex := 0 to High(mNames) do
    begin
      Result.KeywordCounts[mIndex] := mCounts[mNames[mIndex]];
    end;
    Result.Keywords := mNames;
  finally
    mCounts.Free;
  end;
end;

class function TTodoReport.SummaryJson(const ASummary: TTodoSummary): string;
var
  mIndex: Integer;
  mKeywords: string;
begin
  mKeywords := '';
  for mIndex := 0 to High(ASummary.Keywords) do
  begin
    if mIndex > 0 then
    begin
      mKeywords := mKeywords + ', ';
    end;
    mKeywords := mKeywords + JsonText(ASummary.Keywords[mIndex]) + ': ' + IntToStr(ASummary.KeywordCounts[mIndex]);
  end;
  Result := '{"files": ' + IntToStr(ASummary.Files) + ', "open": ' + IntToStr(ASummary.Open) + ', "done": ' +
    IntToStr(ASummary.Done) + ', "keywords": {' + mKeywords + '}}';
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
  mIndex: Integer;
begin
  Result := '{"file": ' + JsonText(AFile.Path) + ', "unit": ' + JsonText(AFile.UnitName) + ', "todos": [';
  for mIndex := 0 to High(AFile.Entries) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ', ';
    end;
    Result := Result + EntryJson(AFile.Entries[mIndex]);
  end;
  Result := Result + ']}';
end;

class function TTodoReport.Json(const AFiles: TArray<TFileTodos>; const ARoot: string): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('{"format": ').Append(IntToStr(cFormat));
    if ARoot <> '' then
    begin
      mBuilder.Append(', "root": ').Append(JsonText(ARoot));
    end;
    mBuilder.Append(', "summary": ').Append(SummaryJson(Summarize(AFiles))).Append(', "files": [');
    for mIndex := 0 to High(AFiles) do
    begin
      if mIndex > 0 then
      begin
        mBuilder.Append(',');
      end;
      mBuilder.Append(cLineBreak).Append('  ').Append(FileJson(AFiles[mIndex]));
    end;
    mBuilder.Append(']}').Append(cLineBreak);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TTodoReport.Json(const AFiles: TArray<TFileTodos>): string;
begin
  Result := Json(AFiles, '');
end;

class function TTodoReport.Caption(const AEntry: TTodoEntry): string;
var
  mDetails: string;
begin
  Result := AEntry.Keyword;
  if AEntry.Priority > 0 then
  begin
    Result := Result + ' ' + IntToStr(AEntry.Priority);
  end;
  mDetails := AEntry.Category;
  if AEntry.Owner <> '' then
  begin
    if mDetails <> '' then
    begin
      mDetails := mDetails + ', ';
    end;
    mDetails := mDetails + AEntry.Owner;
  end;
  if mDetails <> '' then
  begin
    Result := Result + ' [' + mDetails + ']';
  end;
  if AEntry.Text <> '' then
  begin
    Result := Result + ': ' + AEntry.Text;
  end;
end;

/// <summary>Anzahl der Einträge je Kategorie bzw. (AOwner) Person; leere Werte als „(ohne)“.</summary>
procedure CountValues(ACounts: TDictionary<string, Integer>; const AFiles: TArray<TFileTodos>; AOwner: Boolean);
var
  mFileItem: TFileTodos;
  mEntry: TTodoEntry;
  mValue: string;
begin
  for mFileItem in AFiles do
  begin
    for mEntry in mFileItem.Entries do
    begin
      mValue := mEntry.Category;
      if AOwner then
      begin
        mValue := mEntry.Owner;
      end;
      if mValue = '' then
      begin
        mValue := '(ohne)';
      end;
      CountKey(ACounts, mValue);
    end;
  end;
end;

/// <summary>Werte und Anzahlen aus ACounts, meiste zuerst, bei Gleichstand nach Name.</summary>
function ByCount(ACounts: TDictionary<string, Integer>): TArray<TCountPair>;
begin
  Result := ACounts.ToArray;
  TArray.Sort<TCountPair>(Result, TComparer<TCountPair>.Construct(
    function(const A, B: TCountPair): Integer
    begin
      Result := B.Value - A.Value;
      if Result = 0 then
      begin
        Result := CompareText(A.Key, B.Key);
      end;
    end));
end;

/// <summary>Anzahl der Einträge je Wert (Kategorie oder Person), meiste zuerst; leere Werte als „(ohne)“.</summary>
procedure AppendCounts(ABuilder: TStringBuilder; const AFiles: TArray<TFileTodos>; AOwner: Boolean;
  const AHeading, AColumn: string);
var
  mCounts: TDictionary<string, Integer>;
  mPair: TCountPair;
begin
  mCounts := TDictionary<string, Integer>.Create;
  try
    CountValues(mCounts, AFiles, AOwner);
    // Nur ein Wert „(ohne)“: die Tabelle sagt nichts.
    if (mCounts.Count = 0) or ((mCounts.Count = 1) and mCounts.ContainsKey('(ohne)')) then
    begin
      Exit;
    end;
    ABuilder.Append(cLineBreak).Append('## ').Append(AHeading).Append(cLineBreak).Append(cLineBreak);
    ABuilder.Append('| ').Append(AColumn).Append(cTexts[TTodosReportText.Entries].Text).Append(cLineBreak);
    ABuilder.Append('|---|---:|').Append(cLineBreak);
    for mPair in ByCount(mCounts) do
    begin
      ABuilder.Append('| ').Append(Cell(mPair.Key)).Append(' | ').Append(IntToStr(mPair.Value)).Append(' |')
        .Append(cLineBreak);
    end;
  finally
    mCounts.Free;
  end;
end;

/// <summary>Kopfzeile mit Titel und Zusammenfassung des Markdown-Berichts.</summary>
procedure AppendHeader(ABuilder: TStringBuilder; const ASummary: TTodoSummary; const ATitle: string);
var
  mIndex: Integer;
begin
  ABuilder.Append('# TODOs');
  if ATitle <> '' then
  begin
    ABuilder.Append(': ').Append(ATitle);
  end;
  ABuilder.Append(cLineBreak).Append(cLineBreak);
  ABuilder.Append(IntToStr(ASummary.Open)).Append(cTexts[TTodosReportText.OpenEntriesIn].Text)
    .Append(IntToStr(ASummary.Files))
    .Append(' Dateien');
  if ASummary.Done > 0 then
  begin
    ABuilder.Append(', ').Append(IntToStr(ASummary.Done)).Append(cTexts[TTodosReportText.Done].Text);
  end;
  if Length(ASummary.Keywords) > 0 then
  begin
    ABuilder.Append(' (');
    for mIndex := 0 to High(ASummary.Keywords) do
    begin
      if mIndex > 0 then
      begin
        ABuilder.Append(', ');
      end;
      ABuilder.Append(ASummary.Keywords[mIndex]).Append(' ').Append(IntToStr(ASummary.KeywordCounts[mIndex]));
    end;
    ABuilder.Append(')');
  end;
  ABuilder.Append('.').Append(cLineBreak);
end;

/// <summary>Tabelle der Einträge einer Datei.</summary>
procedure AppendFile(ABuilder: TStringBuilder; const AFile: TFileTodos);
var
  mEntry: TTodoEntry;
  mKind, mPriority: string;
begin
  ABuilder.Append(cLineBreak).Append('## ').Append(AFile.UnitName).Append(' (')
    .Append(IntToStr(Length(AFile.Entries))).Append(')').Append(cLineBreak).Append(cLineBreak);
  ABuilder.Append('`').Append(AFile.Path).Append('`').Append(cLineBreak).Append(cLineBreak);
  ABuilder.Append(cTexts[TTodosReportText.LineMarkerPriorityCategoryPerson].Text).Append(cLineBreak);
  ABuilder.Append('|---:|---|---:|---|---|---|').Append(cLineBreak);
  for mEntry in AFile.Entries do
  begin
    mKind := mEntry.Keyword;
    if mEntry.Done then
    begin
      mKind := mKind + cTexts[TTodosReportText.Done2].Text;
    end;
    mPriority := '';
    if mEntry.Priority > 0 then
    begin
      mPriority := IntToStr(mEntry.Priority);
    end;
    ABuilder.Append('| ').Append(IntToStr(mEntry.Range.StartPos.Line + 1)).Append(' | ').Append(mKind)
      .Append(' | ').Append(mPriority).Append(' | ').Append(Cell(mEntry.Category)).Append(' | ')
      .Append(Cell(mEntry.Owner)).Append(' | ').Append(Cell(mEntry.Text)).Append(' |').Append(cLineBreak);
  end;
end;

class function TTodoReport.Markdown(const AFiles: TArray<TFileTodos>; const ATitle: string): string;
var
  mBuilder: TStringBuilder;
  mFileItem: TFileTodos;
begin
  mBuilder := TStringBuilder.Create;
  try
    AppendHeader(mBuilder, Summarize(AFiles), ATitle);
    if Length(AFiles) = 0 then
    begin
      mBuilder.Append(cLineBreak).Append(cTexts[TTodosReportText.NoEntries].Text).Append(cLineBreak);
    end
    else
    begin
      AppendCounts(mBuilder, AFiles, False, cTexts[TTodosReportText.ByCategory].Text,
        cTexts[TTodosReportText.Category].Text);
      AppendCounts(mBuilder, AFiles, True, cTexts[TTodosReportText.ByPerson].Text, 'Person');
      for mFileItem in AFiles do
      begin
        AppendFile(mBuilder, mFileItem);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Todos.Report', cTexts);

end.
