unit Atlas.Core.Editor.SelectionMatches;

// Gleichen Text wie die Markierung hervorheben (#709), ohne VCL und Open
// Tools API. Rein textuell: auch in Strings, Kommentaren und Teilwörtern.
// - Term: Die Markierung zählt nur einzeilig, mit mindestens MinLength
//   Zeichen, nicht nur aus Leerraum und höchstens MaxTermLength lang.
// - Find: alle Treffer der Datei (Zeile, Zeichen ab 0, Länge in UTF-16 wie
//   im LSP), auf Wunsch nur in einem Zeilenbereich (sehr große Dateien:
//   sichtbarer Bereich); höchstens MaxMatches, dann Truncated.
//   Groß-/Kleinschreibung beachten oder nicht, ganze Wörter oder auch
//   Teilwörter. Treffer überlappen nicht.
// - Next: nächster bzw. vorheriger Treffer ab einer Stelle, über das
//   Dateiende hinweg (F3/Umschalt+F3, solange die Markierung steht).
// - Lines: Zeilen mit Treffern für die Übersichtsleiste (#519).

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.TextChanges;

type
  TAtlasSelectionMatchOptions = record
    MinLength: Integer;
    CaseSensitive: Boolean;
    WholeWord: Boolean;
    MaxMatches: Integer;
    /// <summary>Vorgaben wie in den Einstellungen: 3 Zeichen, ohne Groß-/Kleinschreibung, Teilwörter, 1000.
    /// </summary>
    class function Defaults: TAtlasSelectionMatchOptions; static;
  end;

  TAtlasSelectionMatch = record
    /// <summary>0-basiert.</summary>
    Line: Integer;
    /// <summary>0-basiert, UTF-16-Einheiten.</summary>
    Character: Integer;
    Length: Integer;
  end;

  TAtlasSelectionMatchList = record
    Matches: TArray<TAtlasSelectionMatch>;
    /// <summary>Obergrenze erreicht: Es gibt mehr Treffer als Matches.</summary>
    Truncated: Boolean;
    function Count: Integer;
    /// <summary>Treffer in ALine (0-basiert), von links nach rechts.</summary>
    function OnLine(ALine: Integer): TArray<TAtlasSelectionMatch>;
  end;

  TAtlasSelectionMatches = class
  public const
    MaxTermLength = 200;
    /// <summary>Ab so vielen Zeilen nur im sichtbaren Bereich suchen.</summary>
    LargeFileLines = 20000;
    /// <summary>Grenzen der Einstellungen.</summary>
    MinMinLength = 1;
    MaxMinLength = 100;
    MinMaxMatches = 1;
    MaxMaxMatches = 100000;
  public
    /// <summary>Suchtext aus der Markierung ASelection; False, wenn sie nicht zählt (mehrzeilig, zu kurz, nur
    /// Leerraum, zu lang).</summary>
    class function Term(const ASelection: string; const AOptions: TAtlasSelectionMatchOptions;
      out ATerm: string): Boolean; static;
    /// <summary>Alle Treffer von ATerm in ALines.</summary>
    class function Find(const ALines: TArray<string>; const ATerm: string;
      const AOptions: TAtlasSelectionMatchOptions): TAtlasSelectionMatchList; overload; static;
    /// <summary>Treffer nur in den Zeilen AFirstLine bis ALastLine (0-basiert, eingeschlossen).</summary>
    class function Find(const ALines: TArray<string>; const ATerm: string; const AOptions: TAtlasSelectionMatchOptions;
      AFirstLine, ALastLine: Integer): TAtlasSelectionMatchList; overload; static;
    /// <summary>Nächster (ABackward: vorheriger) Treffer ab AFrom über das Dateiende hinweg; vorwärts beginnt er
    /// bei oder nach AFrom, rückwärts endet er vor AFrom. False ohne Treffer.</summary>
    class function Next(const ALines: TArray<string>; const ATerm: string; const AOptions: TAtlasSelectionMatchOptions;
      const AFrom: TLspTextPosition; ABackward: Boolean; out AFound: TLspRange): Boolean; static;
    /// <summary>Zeilen mit mindestens einem Treffer, aufsteigend, je einmal.</summary>
    class function Lines(const AList: TAtlasSelectionMatchList): TArray<Integer>; static;
    /// <summary>Gehört die Stelle zur Markierung selbst (ALine, AStart bis AStop ausschließlich)?</summary>
    class function IsSelection(const AMatch: TAtlasSelectionMatch; ALine, AStart, AStop: Integer): Boolean; static;
  end;

implementation

uses
  System.Math,
  Atlas.Text.Chars;

{ TAtlasSelectionMatchOptions }

class function TAtlasSelectionMatchOptions.Defaults: TAtlasSelectionMatchOptions;
begin
  Result.MinLength := 3;
  Result.CaseSensitive := False;
  Result.WholeWord := False;
  Result.MaxMatches := 1000;
end;

{ TAtlasSelectionMatchList }

function TAtlasSelectionMatchList.Count: Integer;
begin
  Result := System.Length(Matches);
end;

function TAtlasSelectionMatchList.OnLine(ALine: Integer): TArray<TAtlasSelectionMatch>;
var
  Match: TAtlasSelectionMatch;
begin
  Result := nil;
  // Matches ist nach Zeile und Zeichen sortiert.
  for Match in Matches do
    if Match.Line = ALine then
      Result := Result + [Match]
    else if Match.Line > ALine then
      Break;
end;

{ TAtlasSelectionMatches }

/// <summary>Treffer an Position AIndex (ab 1) in ALine darf zählen (ganze Wörter: kein Wortzeichen davor und
/// danach).</summary>
function Bounded(const ALine: string; AIndex, ALength: Integer; AWholeWord: Boolean): Boolean;
begin
  Result := True;
  if not AWholeWord then
    Exit;
  if (AIndex > 1) and TTextChars.IsIdentChar(ALine[AIndex - 1]) then
    Exit(False);
  if (AIndex + ALength <= Length(ALine)) and TTextChars.IsIdentChar(ALine[AIndex + ALength]) then
    Exit(False);
end;

/// <summary>Anfänge (ab 1) aller nicht überlappenden Treffer von ANeedle (schon passend groß geschrieben) in
/// ALine.</summary>
function Positions(const ALine, ANeedle: string; const AOptions: TAtlasSelectionMatchOptions): TArray<Integer>;
var
  Haystack: string;
  Index: Integer;
begin
  Result := nil;
  if (ANeedle = '') or (Length(ALine) < Length(ANeedle)) then
    Exit;
  Haystack := ALine;
  if not AOptions.CaseSensitive then
    Haystack := AnsiUpperCase(ALine);
  Index := Pos(ANeedle, Haystack);
  while Index > 0 do
  begin
    if Bounded(ALine, Index, Length(ANeedle), AOptions.WholeWord) then
    begin
      Result := Result + [Index];
      Index := Pos(ANeedle, Haystack, Index + Length(ANeedle));
    end
    else
      Index := Pos(ANeedle, Haystack, Index + 1);
  end;
end;

function NeedleOf(const ATerm: string; const AOptions: TAtlasSelectionMatchOptions): string;
begin
  Result := ATerm;
  if not AOptions.CaseSensitive then
    Result := AnsiUpperCase(ATerm);
end;

class function TAtlasSelectionMatches.Term(const ASelection: string; const AOptions: TAtlasSelectionMatchOptions;
  out ATerm: string): Boolean;
begin
  ATerm := '';
  Result := (ASelection <> '') and (Trim(ASelection) <> '') and (Pos(#10, ASelection) = 0) and
    (Pos(#13, ASelection) = 0) and (Length(ASelection) >= Max(1, AOptions.MinLength)) and
    (Length(ASelection) <= MaxTermLength);
  if Result then
    ATerm := ASelection;
end;

class function TAtlasSelectionMatches.Find(const ALines: TArray<string>; const ATerm: string;
  const AOptions: TAtlasSelectionMatchOptions): TAtlasSelectionMatchList;
begin
  Result := Find(ALines, ATerm, AOptions, 0, High(ALines));
end;

class function TAtlasSelectionMatches.Find(const ALines: TArray<string>; const ATerm: string;
  const AOptions: TAtlasSelectionMatchOptions; AFirstLine, ALastLine: Integer): TAtlasSelectionMatchList;
var
  Needle: string;
  Line, Index: Integer;
  Match: TAtlasSelectionMatch;
begin
  Result := Default(TAtlasSelectionMatchList);
  if ATerm = '' then
    Exit;
  Needle := NeedleOf(ATerm, AOptions);
  for Line := Max(0, AFirstLine) to Min(High(ALines), ALastLine) do
    for Index in Positions(ALines[Line], Needle, AOptions) do
    begin
      if Result.Count >= Max(1, AOptions.MaxMatches) then
      begin
        Result.Truncated := True;
        Exit;
      end;
      Match.Line := Line;
      Match.Character := Index - 1;
      Match.Length := Length(ATerm);
      Result.Matches := Result.Matches + [Match];
    end;
end;

class function TAtlasSelectionMatches.Next(const ALines: TArray<string>; const ATerm: string;
  const AOptions: TAtlasSelectionMatchOptions; const AFrom: TLspTextPosition; ABackward: Boolean;
  out AFound: TLspRange): Boolean;
var
  Needle: string;
  Count, Step, Row, Index, Chosen: Integer;
  Found: TArray<Integer>;
begin
  Result := False;
  AFound := TLspRange.Create(AFrom.Line, AFrom.Character, AFrom.Line, AFrom.Character);
  Count := Length(ALines);
  if (ATerm = '') or (Count = 0) then
    Exit;
  Needle := NeedleOf(ATerm, AOptions);
  // Einmal um die Datei; die Ausgangszeile kommt am Ende noch einmal ganz dran (Step > 0: alle Treffer zählen).
  for Step := 0 to Count do
  begin
    if ABackward then
      Row := ((AFrom.Line - Step) mod Count + Count) mod Count
    else
      Row := ((AFrom.Line + Step) mod Count + Count) mod Count;
    Found := Positions(ALines[Row], Needle, AOptions);
    Chosen := -1;
    if not ABackward then
    begin
      for Index in Found do
        if (Step > 0) or (Index - 1 >= AFrom.Character) then
        begin
          Chosen := Index;
          Break;
        end;
    end
    else
      for Index in Found do
        if (Step > 0) or (Index - 1 + Length(ATerm) <= AFrom.Character) then
          Chosen := Index;
    if Chosen > 0 then
    begin
      AFound := TLspRange.Create(Row, Chosen - 1, Row, Chosen - 1 + Length(ATerm));
      Exit(True);
    end;
  end;
end;

class function TAtlasSelectionMatches.Lines(const AList: TAtlasSelectionMatchList): TArray<Integer>;
var
  Match: TAtlasSelectionMatch;
begin
  Result := nil;
  for Match in AList.Matches do
    if (Length(Result) = 0) or (Result[High(Result)] <> Match.Line) then
      Result := Result + [Match.Line];
end;

class function TAtlasSelectionMatches.IsSelection(const AMatch: TAtlasSelectionMatch; ALine, AStart,
  AStop: Integer): Boolean;
begin
  Result := (AMatch.Line = ALine) and (AMatch.Character = AStart) and (AMatch.Character + AMatch.Length = AStop);
end;

end.
