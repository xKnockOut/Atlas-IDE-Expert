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
  cReserved: array[0..64] of string = ('and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const', 'constructor',
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

/// <summary>Ein Bereich {start, end} in einer Zeile; False, wenn er fehlt oder ungültig ist.</summary>
function ReadLinkedRange(const AItem: TJSONValue; out ARange: TAtlasLinkedRange): Boolean;
var
  mStartLine, mStartCharacter, mEndLine, mEndCharacter: Integer;
begin
  ARange := Default(TAtlasLinkedRange);
  mStartLine := -1;
  mStartCharacter := -1;
  mEndLine := -1;
  mEndCharacter := -1;
  Result := (AItem is TJSONObject) and TJSONObject(AItem).TryGetValue<Integer>('start.line', mStartLine) and
    TJSONObject(AItem).TryGetValue<Integer>('start.character', mStartCharacter) and
    TJSONObject(AItem).TryGetValue<Integer>('end.line', mEndLine) and
    TJSONObject(AItem).TryGetValue<Integer>('end.character', mEndCharacter);
  Result := Result and (mStartLine = mEndLine) and (mEndCharacter >= mStartCharacter) and (mStartLine >= 0) and
    (mStartCharacter >= 0);
  if Result then
  begin
    ARange := TAtlasLinkedRange.Create(mStartLine, mStartCharacter, mEndCharacter - mStartCharacter);
  end;
end;

/// <summary>Namenskonflikte {name, detail}; ohne detail gilt der Name.</summary>
function ReadConflicts(const AValue: TJSONObject): TAtlasLinkedConflicts;
var
  mItems: TJSONArray;
  mItem: TJSONValue;
  mConflict: TAtlasLinkedConflict;
begin
  Result := nil;
  if AValue.TryGetValue<TJSONArray>('atlasConflicts', mItems) then
  begin
    for mItem in mItems do
    begin
      if (mItem is TJSONObject) and TJSONObject(mItem).TryGetValue<string>('name', mConflict.Name) then
      begin
        if not TJSONObject(mItem).TryGetValue<string>('detail', mConflict.Detail) then
        begin
          mConflict.Detail := mConflict.Name;
        end;
        Result := Result + [mConflict];
      end;
    end;
  end;
end;

class function TAtlasLinkedEditing.FromJson(const AValue: TJSONValue; out ARanges: TAtlasLinkedRanges;
  out AConflicts: TAtlasLinkedConflicts): Boolean;
var
  mItems: TJSONArray;
  mItem: TJSONValue;
  mRange: TAtlasLinkedRange;
begin
  ARanges := nil;
  AConflicts := nil;
  mItems := nil;
  Result := (AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<TJSONArray>('ranges', mItems);
  if Result then
  begin
    for mItem in mItems do
    begin
      Result := Result and ReadLinkedRange(mItem, mRange);
      if Result then
      begin
        ARanges := ARanges + [mRange];
      end;
    end;
  end;
  if Result then
  begin
    AConflicts := ReadConflicts(TJSONObject(AValue));
    Result := Length(ARanges) > 0;
  end
  else
  begin
    ARanges := nil;
  end;
end;

class function TAtlasLinkedEditing.IndexAt(const ARanges: TAtlasLinkedRanges; ALine, ACharacter: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ARanges) do
  begin
    if ARanges[mIndex].Contains(ALine, ACharacter) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasLinkedEditing.NameOf(const ALines: TArray<string>; const ARange: TAtlasLinkedRange): string;
begin
  Result := '';
  if (ARange.Line < 0) or (ARange.Line > High(ALines)) or (ARange.EndCharacter > Length(ALines[ARange.Line])) then
  begin
    Exit;
  end;
  Result := Copy(ALines[ARange.Line], ARange.Character + 1, ARange.Length);
end;

class function TAtlasLinkedEditing.Matches(const ALines: TArray<string>; const ARanges: TAtlasLinkedRanges): Boolean;
var
  mRange: TAtlasLinkedRange;
  mFirst: string;
begin
  Result := False;
  if Length(ARanges) = 0 then
  begin
    Exit;
  end;
  mFirst := NameOf(ALines, ARanges[0]);
  if (mFirst = '') or not IsName(mFirst) then
  begin
    Exit;
  end;
  for mRange in ARanges do
  begin
    if (mRange.Line > High(ALines)) or (mRange.EndCharacter > Length(ALines[mRange.Line])) or
      not SameText(NameOf(ALines, mRange), mFirst) then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

class function TAtlasLinkedEditing.IsName(const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := True;
  for mIndex := 1 to Length(AName) do
  begin
    if not TTextChars.IsIdentChar(AName[mIndex]) or ((mIndex = 1) and not TTextChars.IsIdentStart(AName[1])) then
    begin
      Exit(False);
    end;
  end;
end;

class function TAtlasLinkedEditing.IsReserved(const AName: string): Boolean;
begin
  Result := IndexText(AName, cReserved) >= 0;
end;

class function TAtlasLinkedEditing.Key(const AName: string; AOffset: Integer; AKind: TAtlasLinkedKey;
  const AInsert: string; out ANewName: string; out ANewOffset: Integer): Boolean;
begin
  Result := False;
  ANewName := AName;
  ANewOffset := AOffset;
  if (AOffset < 0) or (AOffset > Length(AName)) then
  begin
    Exit;
  end;
  case AKind of
    TAtlasLinkedKey.Insert:
      begin
        if AInsert = '' then
        begin
          Exit;
        end;
        ANewName := Copy(AName, 1, AOffset) + AInsert + Copy(AName, AOffset + 1, MaxInt);
        ANewOffset := AOffset + Length(AInsert);
      end;
    TAtlasLinkedKey.Backspace:
      begin
        if AOffset = 0 then
        begin
          Exit;
        end;
        ANewName := Copy(AName, 1, AOffset - 1) + Copy(AName, AOffset + 1, MaxInt);
        ANewOffset := AOffset - 1;
      end;
    TAtlasLinkedKey.Delete:
      begin
        if AOffset = Length(AName) then
        begin
          Exit;
        end;
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
  mTail: Integer;
begin
  AName := '';
  Result := False;
  if (ARange.Character < 0) or (ARange.EndCharacter > Length(AOldLine)) then
  begin
    Exit;
  end;
  mTail := Length(AOldLine) - ARange.EndCharacter;
  if (Length(ANewLine) < ARange.Character + mTail) or
    (Copy(ANewLine, 1, ARange.Character) <> Copy(AOldLine, 1, ARange.Character)) or
    (Copy(ANewLine, Length(ANewLine) - mTail + 1, mTail) <> Copy(AOldLine, ARange.EndCharacter + 1, mTail)) then
  begin
    Exit;
  end;
  AName := Copy(ANewLine, ARange.Character + 1, Length(ANewLine) - ARange.Character - mTail);
  Result := True;
end;

class function TAtlasLinkedEditing.Resized(const ARanges: TAtlasLinkedRanges; APrimary,
  ANewLength: Integer): TAtlasLinkedRanges;
var
  mIndex, mDelta: Integer;
  mPrimary: TAtlasLinkedRange;
begin
  Result := Copy(ARanges);
  if (APrimary < 0) or (APrimary > High(ARanges)) then
  begin
    Exit;
  end;
  mPrimary := ARanges[APrimary];
  mDelta := ANewLength - mPrimary.Length;
  Result[APrimary].Length := ANewLength;
  for mIndex := 0 to High(Result) do
  begin
    if (mIndex <> APrimary) and (Result[mIndex].Line = mPrimary.Line) and
      (Result[mIndex].Character > mPrimary.Character)
    then
    begin
      Inc(Result[mIndex].Character, mDelta);
    end;
  end;
end;

class function TAtlasLinkedEditing.Rename(const AText: string; const ARanges: TAtlasLinkedRanges; const AName: string;
  out ANewText: string; out ANewRanges: TAtlasLinkedRanges): Boolean;
var
  mTable: TLineTable;
  mSorted: TAtlasLinkedRanges;
  mOrder: TArray<Integer>;
  mIndex, mOther, mOffset, mDelta: Integer;
  mRange: TAtlasLinkedRange;
begin
  ANewText := AText;
  ANewRanges := Copy(ARanges);
  Result := False;
  mTable := TLineTable.Build(AText);
  for mRange in ARanges do
  begin
    if (mRange.Line < 0) or (mRange.Line >= mTable.LineCount) or (mRange.Character < 0) or
      (mTable.LineStart(mRange.Line) + mRange.EndCharacter > mTable.LineContentEnd(mRange.Line)) then
    begin
      Exit;
    end;
  end;
  // Von hinten nach vorn ersetzen, damit die Offsets davor gültig bleiben.
  mSorted := ARanges;
  SetLength(mOrder, Length(ARanges));
  for mIndex := 0 to High(mOrder) do
  begin
    mOrder[mIndex] := mIndex;
  end;
  TArray.Sort<Integer>(mOrder, TComparer<Integer>.Construct(
    function(const A, B: Integer): Integer
    begin
      Result := mSorted[B].Line - mSorted[A].Line;
      if Result = 0 then
      begin
        Result := mSorted[B].Character - mSorted[A].Character;
      end;
    end));
  for mIndex in mOrder do
  begin
    mRange := ARanges[mIndex];
    mOffset := mTable.LineStart(mRange.Line) + mRange.Character;
    ANewText := Copy(ANewText, 1, mOffset) + AName + Copy(ANewText, mOffset + mRange.Length + 1, MaxInt);
  end;
  // Neue Bereiche: Länge des Namens, verschoben um die Änderungen davor in derselben Zeile.
  for mIndex := 0 to High(ARanges) do
  begin
    mDelta := 0;
    for mOther := 0 to High(ARanges) do
    begin
      if (ARanges[mOther].Line = ARanges[mIndex].Line) and (ARanges[mOther].Character < ARanges[mIndex].Character) then
      begin
        Inc(mDelta, Length(AName) - ARanges[mOther].Length);
      end;
    end;
    ANewRanges[mIndex] := TAtlasLinkedRange.Create(ARanges[mIndex].Line, ARanges[mIndex].Character + mDelta,
      Length(AName));
  end;
  Result := True;
end;

class function TAtlasLinkedEditing.Problem(const AName, AOriginal: string; const AConflicts: TAtlasLinkedConflicts;
  out ADetail: string): TAtlasLinkedProblem;
var
  mConflict: TAtlasLinkedConflict;
begin
  ADetail := '';
  Result := TAtlasLinkedProblem.None;
  if (AName = '') or SameText(AName, AOriginal) then
  begin
    Exit;
  end;
  if IsReserved(AName) then
  begin
    Exit(TAtlasLinkedProblem.Reserved);
  end;
  for mConflict in AConflicts do
  begin
    if SameText(mConflict.Name, AName) then
    begin
      ADetail := mConflict.Detail;
      Exit(TAtlasLinkedProblem.Visible);
    end;
  end;
end;

end.
