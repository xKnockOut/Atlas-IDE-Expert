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
    cMaxTermLength = 200;
    /// <summary>Ab so vielen Zeilen nur im sichtbaren Bereich suchen.</summary>
    cLargeFileLines = 20000;
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
  mMatch: TAtlasSelectionMatch;
begin
  Result := nil;
  // Matches ist nach Zeile und Zeichen sortiert.
  for mMatch in Matches do
  begin
    if mMatch.Line = ALine then
    begin
      Result := Result + [mMatch];
    end
    else if mMatch.Line > ALine then
    begin
      Break;
    end;
  end;
end;

{ TAtlasSelectionMatches }

/// <summary>Treffer an Position AIndex (ab 1) in ALine darf zählen (ganze Wörter: kein Wortzeichen davor und
/// danach).</summary>
function Bounded(const ALine: string; AIndex, ALength: Integer; AWholeWord: Boolean): Boolean;
begin
  Result := True;
  if not AWholeWord then
  begin
    Exit;
  end;
  if (AIndex > 1) and TTextChars.IsIdentChar(ALine[AIndex - 1]) then
  begin
    Exit(False);
  end;
  if (AIndex + ALength <= Length(ALine)) and TTextChars.IsIdentChar(ALine[AIndex + ALength]) then
  begin
    Exit(False);
  end;
end;

/// <summary>Anfänge (ab 1) aller nicht überlappenden Treffer von ANeedle (schon passend groß geschrieben) in
/// ALine.</summary>
function Positions(const ALine, ANeedle: string; const AOptions: TAtlasSelectionMatchOptions): TArray<Integer>;
var
  mHaystack: string;
  mIndex: Integer;
begin
  Result := nil;
  if (ANeedle = '') or (Length(ALine) < Length(ANeedle)) then
  begin
    Exit;
  end;
  mHaystack := ALine;
  if not AOptions.CaseSensitive then
  begin
    mHaystack := AnsiUpperCase(ALine);
  end;
  mIndex := Pos(ANeedle, mHaystack);
  while mIndex > 0 do
  begin
    if Bounded(ALine, mIndex, Length(ANeedle), AOptions.WholeWord) then
    begin
      Result := Result + [mIndex];
      mIndex := Pos(ANeedle, mHaystack, mIndex + Length(ANeedle));
    end
    else
    begin
      mIndex := Pos(ANeedle, mHaystack, mIndex + 1);
    end;
  end;
end;

function NeedleOf(const ATerm: string; const AOptions: TAtlasSelectionMatchOptions): string;
begin
  Result := ATerm;
  if not AOptions.CaseSensitive then
  begin
    Result := AnsiUpperCase(ATerm);
  end;
end;

class function TAtlasSelectionMatches.Term(const ASelection: string; const AOptions: TAtlasSelectionMatchOptions;
  out ATerm: string): Boolean;
begin
  ATerm := '';
  Result := (ASelection <> '') and (Trim(ASelection) <> '') and (Pos(#10, ASelection) = 0) and
    (Pos(#13, ASelection) = 0) and (Length(ASelection) >= Max(1, AOptions.MinLength)) and
    (Length(ASelection) <= cMaxTermLength);
  if Result then
  begin
    ATerm := ASelection;
  end;
end;

class function TAtlasSelectionMatches.Find(const ALines: TArray<string>; const ATerm: string;
  const AOptions: TAtlasSelectionMatchOptions): TAtlasSelectionMatchList;
begin
  Result := Find(ALines, ATerm, AOptions, 0, High(ALines));
end;

class function TAtlasSelectionMatches.Find(const ALines: TArray<string>; const ATerm: string;
  const AOptions: TAtlasSelectionMatchOptions; AFirstLine, ALastLine: Integer): TAtlasSelectionMatchList;
var
  mNeedle: string;
  mLine, mIndex: Integer;
  mMatch: TAtlasSelectionMatch;
begin
  Result := Default(TAtlasSelectionMatchList);
  if ATerm = '' then
  begin
    Exit;
  end;
  mNeedle := NeedleOf(ATerm, AOptions);
  for mLine := Max(0, AFirstLine) to Min(High(ALines), ALastLine) do
  begin
    for mIndex in Positions(ALines[mLine], mNeedle, AOptions) do
    begin
      if Result.Count >= Max(1, AOptions.MaxMatches) then
      begin
        Result.Truncated := True;
        Exit;
      end;
      mMatch.Line := mLine;
      mMatch.Character := mIndex - 1;
      mMatch.Length := Length(ATerm);
      Result.Matches := Result.Matches + [mMatch];
    end;
  end;
end;

/// <summary>Erster Treffer (1-basiert) aus AFound, der bei oder nach ACharacter beginnt; AAll: jeder zählt.
/// 0 ohne.</summary>
function FirstFrom(const AFound: TArray<Integer>; ACharacter: Integer; AAll: Boolean): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  mIndex := 0;
  while (Result = 0) and (mIndex <= High(AFound)) do
  begin
    if AAll or (AFound[mIndex] - 1 >= ACharacter) then
    begin
      Result := AFound[mIndex];
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Letzter Treffer (1-basiert) aus AFound, der bis ACharacter endet; AAll: jeder zählt. 0 ohne.</summary>
function LastBefore(const AFound: TArray<Integer>; ACharacter, ALength: Integer; AAll: Boolean): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex in AFound do
  begin
    if AAll or (mIndex - 1 + ALength <= ACharacter) then
    begin
      Result := mIndex;
    end;
  end;
end;

class function TAtlasSelectionMatches.Next(const ALines: TArray<string>; const ATerm: string;
  const AOptions: TAtlasSelectionMatchOptions; const AFrom: TLspTextPosition; ABackward: Boolean;
  out AFound: TLspRange): Boolean;
var
  mNeedle: string;
  mCount, mStep, mRow, mChosen: Integer;
  mFound: TArray<Integer>;
begin
  Result := False;
  AFound := TLspRange.Create(AFrom.Line, AFrom.Character, AFrom.Line, AFrom.Character);
  mCount := Length(ALines);
  mNeedle := NeedleOf(ATerm, AOptions);
  mStep := 0;
  // Einmal um die Datei; die Ausgangszeile kommt am Ende noch einmal ganz dran (Step > 0: alle Treffer zählen).
  while (ATerm <> '') and not Result and (mStep <= mCount) and (mCount > 0) do
  begin
    if ABackward then
    begin
      mRow := ((AFrom.Line - mStep) mod mCount + mCount) mod mCount;
      mFound := Positions(ALines[mRow], mNeedle, AOptions);
      mChosen := LastBefore(mFound, AFrom.Character, Length(ATerm), mStep > 0);
    end
    else
    begin
      mRow := ((AFrom.Line + mStep) mod mCount + mCount) mod mCount;
      mFound := Positions(ALines[mRow], mNeedle, AOptions);
      mChosen := FirstFrom(mFound, AFrom.Character, mStep > 0);
    end;
    if mChosen > 0 then
    begin
      AFound := TLspRange.Create(mRow, mChosen - 1, mRow, mChosen - 1 + Length(ATerm));
      Result := True;
    end;
    Inc(mStep);
  end;
end;

class function TAtlasSelectionMatches.Lines(const AList: TAtlasSelectionMatchList): TArray<Integer>;
var
  mMatch: TAtlasSelectionMatch;
begin
  Result := nil;
  for mMatch in AList.Matches do
  begin
    if (Length(Result) = 0) or (Result[High(Result)] <> mMatch.Line) then
    begin
      Result := Result + [mMatch.Line];
    end;
  end;
end;

class function TAtlasSelectionMatches.IsSelection(const AMatch: TAtlasSelectionMatch; ALine, AStart,
  AStop: Integer): Boolean;
begin
  Result := (AMatch.Line = ALine) and (AMatch.Character = AStart) and (AMatch.Character + AMatch.Length = AStop);
end;

end.
