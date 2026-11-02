unit Atlas.Core.Editor.LinkedEditing;

// Bezeichner live mitziehen (#658), ohne Open Tools API. Der Server liefert
// für lokale Bezeichner die Vorkommen in der Routine samt der dort sichtbaren
// Namen (textDocument/linkedEditingRange mit "atlasLocals"); hier steht, was
// eine Taste im bearbeiteten Vorkommen aus dem Namen macht, wie der neue Name
// in alle Vorkommen kommt und ob er mit etwas zusammenstößt.
// - Bereiche liegen in einer Zeile (Zeile, Zeichen, Länge; 0-basiert).
// - Key rechnet Tippen, Rücktaste und Entf im Namen; False, wenn die Taste den
//   Namen verließe (Rücktaste am Anfang, Entf am Ende) oder kein Bezeichner
//   mehr entstünde. Leer ist erlaubt (Löschen bis zur Länge 0).
// - Follow erkennt eine Änderung, die die IDE selbst am Namen gemacht hat
//   (Einfügen aus der Zwischenablage, Vorschlag übernommen): Text vor und
//   hinter dem Bereich unverändert.
// - Rename ersetzt alle Bereiche im ganzen Text; die IDE schreibt den
//   Unterschied in einem Schritt.
// Für out-Parameter nie dieselbe Variable wie für die Eingabe übergeben.

interface

uses
  System.SysUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  TAtlasLinkedKey = (Insert, Backspace, Delete);
  TAtlasLinkedProblem = (None, Reserved, Visible);
  {$SCOPEDENUMS OFF}

  /// <summary>Ein Vorkommen: Zeile, erstes Zeichen und Länge (0-basiert, UTF-16 wie im LSP).</summary>
  TAtlasLinkedRange = record
    Line: Integer;
    Character: Integer;
    Length: Integer;
    class function Create(ALine, ACharacter, ALength: Integer): TAtlasLinkedRange; static;
    function EndCharacter: Integer;
    /// <summary>(ALine, ACharacter) im Bereich, beide Ränder eingeschlossen.</summary>
    function Contains(ALine, ACharacter: Integer): Boolean;
  end;
  TAtlasLinkedRanges = TArray<TAtlasLinkedRange>;

  /// <summary>Sichtbarer Name, mit dem ein neuer Name zusammenstieße, und seine Beschreibung vom Server.</summary>
  TAtlasLinkedConflict = record
    Name: string;
    Detail: string;
  end;
  TAtlasLinkedConflicts = TArray<TAtlasLinkedConflict>;

  TAtlasLinkedEditing = class
  public
    /// <summary>Antwort des Servers lesen; False ohne Bereiche oder bei Bereichen über mehrere Zeilen.</summary>
    class function FromJson(const AValue: TJSONValue; out ARanges: TAtlasLinkedRanges;
      out AConflicts: TAtlasLinkedConflicts): Boolean; static;
    /// <summary>Bereich, der (ALine, ACharacter) enthält; -1 ohne.</summary>
    class function IndexAt(const ARanges: TAtlasLinkedRanges; ALine, ACharacter: Integer): Integer; static;
    /// <summary>Text des Bereichs in ALines; '' außerhalb.</summary>
    class function NameOf(const ALines: TArray<string>; const ARange: TAtlasLinkedRange): string; static;
    /// <summary>Alle Bereiche passen in ihre Zeilen und tragen denselben Namen (ohne Rücksicht auf
    /// Groß-/Kleinschreibung) wie der erste: Die Antwort gilt noch für diesen Text.</summary>
    class function Matches(const ALines: TArray<string>; const ARanges: TAtlasLinkedRanges): Boolean; static;
    /// <summary>'' oder ein Bezeichner (erstes Zeichen keine Ziffer).</summary>
    class function IsName(const AName: string): Boolean; static;
    /// <summary>Reserviertes Wort von Delphi (ohne Rücksicht auf Groß-/Kleinschreibung).</summary>
    class function IsReserved(const AName: string): Boolean; static;
    /// <summary>Taste AKind an AOffset (0 = vor dem ersten Zeichen) im Namen AName; AInsert ist der getippte
    /// Text. False, wenn die Taste den Namen verließe oder kein Bezeichner entstünde.</summary>
    class function Key(const AName: string; AOffset: Integer; AKind: TAtlasLinkedKey; const AInsert: string;
      out ANewName: string; out ANewOffset: Integer): Boolean; static;
    /// <summary>Hat sich von AOldLine zu ANewLine nur der Bereich ARange geändert, steht in AName der neue
    /// Text des Bereichs.</summary>
    class function Follow(const AOldLine, ANewLine: string; const ARange: TAtlasLinkedRange;
      out AName: string): Boolean; static;
    /// <summary>Bereiche, nachdem ARanges[APrimary] die Länge ANewLength bekommen hat (Follow): Bereiche
    /// dahinter in derselben Zeile rücken um den Unterschied.</summary>
    class function Resized(const ARanges: TAtlasLinkedRanges; APrimary, ANewLength: Integer): TAtlasLinkedRanges;
      static;
    /// <summary>AName in alle Bereiche von AText schreiben; ANewRanges sind die Bereiche danach in derselben
    /// Reihenfolge. False, wenn ein Bereich nicht in seine Zeile passt.</summary>
    class function Rename(const AText: string; const ARanges: TAtlasLinkedRanges; const AName: string;
      out ANewText: string; out ANewRanges: TAtlasLinkedRanges): Boolean; static;
    /// <summary>Stößt AName mit einem reservierten Wort oder einem sichtbaren Namen zusammen? AOriginal (der
    /// Name zu Beginn) ist nie ein Konflikt. ADetail ist die Beschreibung bei Visible.</summary>
    class function Problem(const AName, AOriginal: string; const AConflicts: TAtlasLinkedConflicts;
      out ADetail: string): TAtlasLinkedProblem; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Chars,
  Atlas.Text.Lines;

const
  Reserved: array[0..64] of string = ('and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const', 'constructor',
    'destructor', 'dispinterface', 'div', 'do', 'downto', 'else', 'end', 'except', 'exports', 'file', 'finalization',
    'finally', 'for', 'function', 'goto', 'if', 'implementation', 'in', 'inherited', 'initialization', 'inline',
    'interface', 'is', 'label', 'library', 'mod', 'nil', 'not', 'object', 'of', 'or', 'packed', 'procedure', 'program',
    'property', 'raise', 'record', 'repeat', 'resourcestring', 'set', 'shl', 'shr', 'string', 'then', 'threadvar',
    'to', 'try', 'type', 'unit', 'until', 'uses', 'var', 'while', 'with', 'xor', 'out');

{ TAtlasLinkedRange }

class function TAtlasLinkedRange.Create(ALine, ACharacter, ALength: Integer): TAtlasLinkedRange;
begin
  Result.Line := ALine;
  Result.Character := ACharacter;
  Result.Length := ALength;
end;

function TAtlasLinkedRange.EndCharacter: Integer;
begin
  Result := Character + Length;
end;

function TAtlasLinkedRange.Contains(ALine, ACharacter: Integer): Boolean;
begin
  Result := (ALine = Line) and (ACharacter >= Character) and (ACharacter <= EndCharacter);
end;

{ TAtlasLinkedEditing }

class function TAtlasLinkedEditing.FromJson(const AValue: TJSONValue; out ARanges: TAtlasLinkedRanges;
  out AConflicts: TAtlasLinkedConflicts): Boolean;
var
  Items: TJSONArray;
  Item: TJSONValue;
  StartLine, StartCharacter, EndLine, EndCharacter: Integer;
  Conflict: TAtlasLinkedConflict;
begin
  ARanges := nil;
  AConflicts := nil;
  Result := False;
  if not (AValue is TJSONObject) or not TJSONObject(AValue).TryGetValue<TJSONArray>('ranges', Items) then
    Exit;
  for Item in Items do
  begin
    if not (Item is TJSONObject) or
      not TJSONObject(Item).TryGetValue<Integer>('start.line', StartLine) or
      not TJSONObject(Item).TryGetValue<Integer>('start.character', StartCharacter) or
      not TJSONObject(Item).TryGetValue<Integer>('end.line', EndLine) or
      not TJSONObject(Item).TryGetValue<Integer>('end.character', EndCharacter) or
      (StartLine <> EndLine) or (EndCharacter < StartCharacter) or (StartLine < 0) or (StartCharacter < 0) then
    begin
      ARanges := nil;
      Exit;
    end;
    ARanges := ARanges + [TAtlasLinkedRange.Create(StartLine, StartCharacter, EndCharacter - StartCharacter)];
  end;
  if TJSONObject(AValue).TryGetValue<TJSONArray>('atlasConflicts', Items) then
    for Item in Items do
      if (Item is TJSONObject) and TJSONObject(Item).TryGetValue<string>('name', Conflict.Name) then
      begin
        if not TJSONObject(Item).TryGetValue<string>('detail', Conflict.Detail) then
          Conflict.Detail := Conflict.Name;
        AConflicts := AConflicts + [Conflict];
      end;
  Result := Length(ARanges) > 0;
end;

class function TAtlasLinkedEditing.IndexAt(const ARanges: TAtlasLinkedRanges; ALine, ACharacter: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ARanges) do
    if ARanges[Index].Contains(ALine, ACharacter) then
      Exit(Index);
  Result := -1;
end;

class function TAtlasLinkedEditing.NameOf(const ALines: TArray<string>; const ARange: TAtlasLinkedRange): string;
begin
  Result := '';
  if (ARange.Line < 0) or (ARange.Line > High(ALines)) or (ARange.EndCharacter > Length(ALines[ARange.Line])) then
    Exit;
  Result := Copy(ALines[ARange.Line], ARange.Character + 1, ARange.Length);
end;

class function TAtlasLinkedEditing.Matches(const ALines: TArray<string>; const ARanges: TAtlasLinkedRanges): Boolean;
var
  Range: TAtlasLinkedRange;
  First: string;
begin
  Result := False;
  if Length(ARanges) = 0 then
    Exit;
  First := NameOf(ALines, ARanges[0]);
  if (First = '') or not IsName(First) then
    Exit;
  for Range in ARanges do
    if (Range.Line > High(ALines)) or (Range.EndCharacter > Length(ALines[Range.Line])) or
      not SameText(NameOf(ALines, Range), First) then
      Exit;
  Result := True;
end;

class function TAtlasLinkedEditing.IsName(const AName: string): Boolean;
var
  Index: Integer;
begin
  Result := True;
  for Index := 1 to Length(AName) do
    if not TTextChars.IsIdentChar(AName[Index]) or ((Index = 1) and not TTextChars.IsIdentStart(AName[1])) then
      Exit(False);
end;

class function TAtlasLinkedEditing.IsReserved(const AName: string): Boolean;
begin
  Result := IndexText(AName, Reserved) >= 0;
end;

class function TAtlasLinkedEditing.Key(const AName: string; AOffset: Integer; AKind: TAtlasLinkedKey;
  const AInsert: string; out ANewName: string; out ANewOffset: Integer): Boolean;
begin
  Result := False;
  ANewName := AName;
  ANewOffset := AOffset;
  if (AOffset < 0) or (AOffset > Length(AName)) then
    Exit;
  case AKind of
    TAtlasLinkedKey.Insert:
      begin
        if AInsert = '' then
          Exit;
        ANewName := Copy(AName, 1, AOffset) + AInsert + Copy(AName, AOffset + 1, MaxInt);
        ANewOffset := AOffset + Length(AInsert);
      end;
    TAtlasLinkedKey.Backspace:
      begin
        if AOffset = 0 then
          Exit;
        ANewName := Copy(AName, 1, AOffset - 1) + Copy(AName, AOffset + 1, MaxInt);
        ANewOffset := AOffset - 1;
      end;
    TAtlasLinkedKey.Delete:
      begin
        if AOffset = Length(AName) then
          Exit;
        ANewName := Copy(AName, 1, AOffset) + Copy(AName, AOffset + 2, MaxInt);
      end;
  end;
  Result := IsName(ANewName);
  if not Result then
  begin
    ANewName := AName;
    ANewOffset := AOffset;
  end;
end;

class function TAtlasLinkedEditing.Follow(const AOldLine, ANewLine: string; const ARange: TAtlasLinkedRange;
  out AName: string): Boolean;
var
  Tail: Integer;
begin
  AName := '';
  Result := False;
  if (ARange.Character < 0) or (ARange.EndCharacter > Length(AOldLine)) then
    Exit;
  Tail := Length(AOldLine) - ARange.EndCharacter;
  if (Length(ANewLine) < ARange.Character + Tail) or
    (Copy(ANewLine, 1, ARange.Character) <> Copy(AOldLine, 1, ARange.Character)) or
    (Copy(ANewLine, Length(ANewLine) - Tail + 1, Tail) <> Copy(AOldLine, ARange.EndCharacter + 1, Tail)) then
    Exit;
  AName := Copy(ANewLine, ARange.Character + 1, Length(ANewLine) - ARange.Character - Tail);
  Result := True;
end;

class function TAtlasLinkedEditing.Resized(const ARanges: TAtlasLinkedRanges; APrimary,
  ANewLength: Integer): TAtlasLinkedRanges;
var
  Index, Delta: Integer;
  Primary: TAtlasLinkedRange;
begin
  Result := Copy(ARanges);
  if (APrimary < 0) or (APrimary > High(ARanges)) then
    Exit;
  Primary := ARanges[APrimary];
  Delta := ANewLength - Primary.Length;
  Result[APrimary].Length := ANewLength;
  for Index := 0 to High(Result) do
    if (Index <> APrimary) and (Result[Index].Line = Primary.Line) and (Result[Index].Character > Primary.Character)
    then
      Inc(Result[Index].Character, Delta);
end;

class function TAtlasLinkedEditing.Rename(const AText: string; const ARanges: TAtlasLinkedRanges; const AName: string;
  out ANewText: string; out ANewRanges: TAtlasLinkedRanges): Boolean;
var
  Table: TLineTable;
  Sorted: TAtlasLinkedRanges;
  Order: TArray<Integer>;
  Index, Other, Offset, Delta: Integer;
  Range: TAtlasLinkedRange;
begin
  ANewText := AText;
  ANewRanges := Copy(ARanges);
  Result := False;
  Table := TLineTable.Build(AText);
  for Range in ARanges do
    if (Range.Line < 0) or (Range.Line >= Table.LineCount) or (Range.Character < 0) or
      (Table.LineStart(Range.Line) + Range.EndCharacter > Table.LineContentEnd(Range.Line)) then
      Exit;
  // Von hinten nach vorn ersetzen, damit die Offsets davor gültig bleiben.
  Sorted := ARanges;
  SetLength(Order, Length(ARanges));
  for Index := 0 to High(Order) do
    Order[Index] := Index;
  TArray.Sort<Integer>(Order, TComparer<Integer>.Construct(
    function(const A, B: Integer): Integer
    begin
      Result := Sorted[B].Line - Sorted[A].Line;
      if Result = 0 then
        Result := Sorted[B].Character - Sorted[A].Character;
    end));
  for Index in Order do
  begin
    Range := ARanges[Index];
    Offset := Table.LineStart(Range.Line) + Range.Character;
    ANewText := Copy(ANewText, 1, Offset) + AName + Copy(ANewText, Offset + Range.Length + 1, MaxInt);
  end;
  // Neue Bereiche: Länge des Namens, verschoben um die Änderungen davor in derselben Zeile.
  for Index := 0 to High(ARanges) do
  begin
    Delta := 0;
    for Other := 0 to High(ARanges) do
      if (ARanges[Other].Line = ARanges[Index].Line) and (ARanges[Other].Character < ARanges[Index].Character) then
        Inc(Delta, Length(AName) - ARanges[Other].Length);
    ANewRanges[Index] := TAtlasLinkedRange.Create(ARanges[Index].Line, ARanges[Index].Character + Delta,
      Length(AName));
  end;
  Result := True;
end;

class function TAtlasLinkedEditing.Problem(const AName, AOriginal: string; const AConflicts: TAtlasLinkedConflicts;
  out ADetail: string): TAtlasLinkedProblem;
var
  Conflict: TAtlasLinkedConflict;
begin
  ADetail := '';
  Result := TAtlasLinkedProblem.None;
  if (AName = '') or SameText(AName, AOriginal) then
    Exit;
  if IsReserved(AName) then
    Exit(TAtlasLinkedProblem.Reserved);
  for Conflict in AConflicts do
    if SameText(Conflict.Name, AName) then
    begin
      ADetail := Conflict.Detail;
      Exit(TAtlasLinkedProblem.Visible);
    end;
end;

end.
