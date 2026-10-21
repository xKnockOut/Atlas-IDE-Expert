unit Atlas.Core.Search.Results;

// Ergebnisse der Atlas-Suche für die Suchleiste und das Meldungsfenster
// (#878), ohne VCL und Open Tools API:
// - IndexAt: welcher Treffer gerade markiert ist bzw. den Cursor enthält (für
//   den Zähler „n von m“ der Leiste).
// - Entries: je Treffer eine Zeile für den Reiter „Atlas-Suche“ im Fenster
//   Meldungen: 1-basierte Zeile, 1-basierte Editorspalte (Tabs aufgelöst) und
//   Zeilentext ohne Einzug; höchstens MaxEntries.
// - RoutineName: kurzer Name einer Routine aus ihrer Kopfzeile für die
//   Kopfzeile der Liste („Methode TFoo.Bar“).

interface

uses
  System.SysUtils,
  Atlas.Core.Search.Matching;

type
  TAtlasSearchEntry = record
    /// <summary>Zeile, 1-basiert.</summary>
    Line: Integer;
    /// <summary>Editorspalte, 1-basiert, Tabs aufgelöst.</summary>
    Column: Integer;
    Text: string;
  end;

  TAtlasSearchResults = class
  public const
    MaxEntries = 1000;
  public
    /// <summary>Index des Treffers, der an APos beginnt; sonst des ersten, der APos enthält (Start &lt; APos
    /// &lt;= Ende); -1 ohne.</summary>
    class function IndexAt(const AHits: TArray<TAtlasSearchHit>; const APos: TAtlasSearchPos): Integer; static;
    /// <summary>Zeilen für das Meldungsfenster, höchstens MaxEntries.</summary>
    class function Entries(const ALines: TArray<string>; const AHits: TArray<TAtlasSearchHit>;
      ATabWidth: Integer): TArray<TAtlasSearchEntry>; static;
    /// <summary>„TFoo.Bar“ aus „class function TFoo.Bar(const A: Integer): Boolean;“; ohne Namen die Zeile.
    /// </summary>
    class function RoutineName(const ACaption: string): string; static;
  end;

implementation

uses
  Atlas.Text.Chars,
  Atlas.Core.Editor.Pairs;

class function TAtlasSearchResults.IndexAt(const AHits: TArray<TAtlasSearchHit>;
  const APos: TAtlasSearchPos): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(AHits) do
    if TAtlasSearchPos.Compare(AHits[Index].StartPos, APos) = 0 then
      Exit(Index);
  for Index := 0 to High(AHits) do
    if (TAtlasSearchPos.Compare(AHits[Index].StartPos, APos) < 0) and
      (TAtlasSearchPos.Compare(APos, AHits[Index].StopPos) <= 0) then
      Exit(Index);
  Result := -1;
end;

class function TAtlasSearchResults.Entries(const ALines: TArray<string>; const AHits: TArray<TAtlasSearchHit>;
  ATabWidth: Integer): TArray<TAtlasSearchEntry>;
var
  Count, Index: Integer;
  LineText: string;
begin
  Result := nil;
  Count := Length(AHits);
  if Count > MaxEntries then
    Count := MaxEntries;
  SetLength(Result, Count);
  for Index := 0 to Count - 1 do
  begin
    LineText := '';
    if (AHits[Index].Line >= 0) and (AHits[Index].Line <= High(ALines)) then
      LineText := ALines[AHits[Index].Line];
    Result[Index].Line := AHits[Index].Line + 1;
    Result[Index].Column := TAtlasPairs.ColumnOf(LineText, AHits[Index].Character, ATabWidth);
    Result[Index].Text := TAtlasTextSearch.HitText(ALines, AHits[Index]);
  end;
end;

class function TAtlasSearchResults.RoutineName(const ACaption: string): string;
var
  Text: string;
  Start, Stop: Integer;
begin
  Text := Trim(ACaption);
  // Schlüsselwörter vorn überspringen: class, procedure, function, constructor, destructor, operator.
  Start := 1;
  repeat
    while (Start <= Length(Text)) and (Text[Start] = ' ') do
      Inc(Start);
    Stop := Start;
    while (Stop <= Length(Text)) and TTextChars.IsIdentChar(Text[Stop]) do
      Inc(Stop);
    if not TAtlasTextSearch.IsReserved(Copy(Text, Start, Stop - Start)) then
      Break;
    Start := Stop;
  until Start > Length(Text);
  // Name mit Punkten und Typparametern bis zur Parameterliste bzw. zum Ergebnistyp.
  Stop := Start;
  while (Stop <= Length(Text)) and not CharInSet(Text[Stop], ['(', ':', ';', ' ']) do
    Inc(Stop);
  Result := Copy(Text, Start, Stop - Start);
  if Result = '' then
    Result := Text;
end;

end.
