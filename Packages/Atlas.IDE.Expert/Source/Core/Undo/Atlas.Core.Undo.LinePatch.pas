unit Atlas.Core.Undo.LinePatch;

// Stellen eines Änderungsschritts auf einen später geänderten Text übertragen
// (#721): Zurücknehmen heißt, den Schritt „nachher → vorher“ auf den
// aktuellen Text anzuwenden, Wiederherstellen den Schritt „vorher → nachher“.
// Ist der aktuelle Text noch genau der Ausgangstext, ist das Ergebnis der
// Zieltext. Sonst werden die geänderten Zeilenblöcke beider Seiten verglichen
// (Dreiwegevergleich über den Ausgangstext): Berühren sich ein Block des
// Schritts und ein Block, den jemand danach geändert hat (auch direkt
// angrenzend), ist das ein Konflikt und nichts wird übertragen. Nie wird so
// Benutzerarbeit überschrieben.
// Zeilen behalten ihr Zeilenende (CRLF, LF, CR), damit gemischte Zeilenenden
// und eine fehlende letzte Zeilenschaltung erhalten bleiben. Verglichen wird
// nach gleichem Anfang und Ende mit der längsten gemeinsamen Teilfolge; ist der
// Rest zu groß dafür, gilt er als ein Block.

interface

uses
  System.SysUtils;

type
  /// <summary>Geänderter Zeilenblock: im alten Text ab OldStart OldCount Zeilen, im neuen ab NewStart
  /// NewCount Zeilen (0-basiert).</summary>
  TAtlasLineHunk = record
    OldStart: Integer;
    OldCount: Integer;
    NewStart: Integer;
    NewCount: Integer;
  end;

  TAtlasLinePatch = class
  public const
    /// <summary>Größte Fläche (Zeilen alt × neu) für den genauen Vergleich der Mitte.</summary>
    MaxCells = 4000000;
  public
    /// <summary>Zeilen samt Zeilenende; die letzte ohne, wenn der Text nicht mit einem endet.</summary>
    class function SplitLines(const AText: string): TArray<string>; static;
    /// <summary>Geänderte Blöcke von AOld nach ANew, aufsteigend.</summary>
    class function Hunks(const AOld, ANew: TArray<string>): TArray<TAtlasLineHunk>; static;
    /// <summary>Überträgt den Schritt ASource → ATarget auf ACurrent (ein späterer Stand von ASource).
    /// False bei einem Konflikt; AResult ist dann leer.</summary>
    class function Rebase(const ASource, ATarget, ACurrent: string; out AResult: string): Boolean; static;
  end;

implementation

uses
  System.Math;

class function TAtlasLinePatch.SplitLines(const AText: string): TArray<string>;
var
  Index, Start, Count: Integer;
begin
  Result := nil;
  Count := 0;
  Start := 1;
  Index := 1;
  while Index <= Length(AText) do
  begin
    if (AText[Index] = #13) and (Index < Length(AText)) and (AText[Index + 1] = #10) then
      Inc(Index);
    if (AText[Index] = #10) or (AText[Index] = #13) then
    begin
      if Count = Length(Result) then
        SetLength(Result, Max(16, Count * 2));
      Result[Count] := Copy(AText, Start, Index - Start + 1);
      Inc(Count);
      Start := Index + 1;
    end;
    Inc(Index);
  end;
  if Start <= Length(AText) then
  begin
    SetLength(Result, Count + 1);
    Result[Count] := Copy(AText, Start, MaxInt);
    Inc(Count);
  end;
  SetLength(Result, Count);
end;

class function TAtlasLinePatch.Hunks(const AOld, ANew: TArray<string>): TArray<TAtlasLineHunk>;
var
  Prefix, Suffix, OldCount, NewCount, Row, Column, Width: Integer;
  Table: TArray<Integer>;
  Hunk: TAtlasLineHunk;
  Open: Boolean;

  procedure Flush;
  begin
    if Open then
      Result := Result + [Hunk];
    Open := False;
  end;

  procedure Touch(AOldLine, ANewLine: Integer);
  begin
    if Open then
      Exit;
    Open := True;
    Hunk.OldStart := AOldLine;
    Hunk.NewStart := ANewLine;
    Hunk.OldCount := 0;
    Hunk.NewCount := 0;
  end;

begin
  Result := nil;
  Prefix := 0;
  while (Prefix < Length(AOld)) and (Prefix < Length(ANew)) and (AOld[Prefix] = ANew[Prefix]) do
    Inc(Prefix);
  Suffix := 0;
  while (Suffix < Length(AOld) - Prefix) and (Suffix < Length(ANew) - Prefix) and
    (AOld[High(AOld) - Suffix] = ANew[High(ANew) - Suffix]) do
    Inc(Suffix);
  OldCount := Length(AOld) - Prefix - Suffix;
  NewCount := Length(ANew) - Prefix - Suffix;
  if (OldCount = 0) and (NewCount = 0) then
    Exit;
  Hunk := Default(TAtlasLineHunk);
  if (OldCount = 0) or (NewCount = 0) or (Int64(OldCount + 1) * (NewCount + 1) > MaxCells) then
  begin
    // Nur auf einer Seite etwas oder zu groß: ein Block.
    Hunk.OldStart := Prefix;
    Hunk.OldCount := OldCount;
    Hunk.NewStart := Prefix;
    Hunk.NewCount := NewCount;
    begin Result := [Hunk]; Exit; end;
  end;
  // Längste gemeinsame Teilfolge der Mitte, von hinten: Table[Row, Column] für AOld[Row..] und ANew[Column..].
  Width := NewCount + 1;
  SetLength(Table, (OldCount + 1) * Width);
  for Row := OldCount - 1 downto 0 do
    for Column := NewCount - 1 downto 0 do
      if AOld[Prefix + Row] = ANew[Prefix + Column] then
        Table[Row * Width + Column] := Table[(Row + 1) * Width + Column + 1] + 1
      else
        Table[Row * Width + Column] := Max(Table[(Row + 1) * Width + Column], Table[Row * Width + Column + 1]);
  Open := False;
  Row := 0;
  Column := 0;
  while (Row < OldCount) or (Column < NewCount) do
  begin
    if (Row < OldCount) and (Column < NewCount) and (AOld[Prefix + Row] = ANew[Prefix + Column]) then
    begin
      Flush;
      Inc(Row);
      Inc(Column);
    end
    else if (Column = NewCount) or ((Row < OldCount) and
      (Table[(Row + 1) * Width + Column] >= Table[Row * Width + Column + 1])) then
    begin
      Touch(Prefix + Row, Prefix + Column);
      Inc(Hunk.OldCount);
      Inc(Row);
    end
    else
    begin
      Touch(Prefix + Row, Prefix + Column);
      Inc(Hunk.NewCount);
      Inc(Column);
    end;
  end;
  Flush;
end;

class function TAtlasLinePatch.Rebase(const ASource, ATarget, ACurrent: string; out AResult: string): Boolean;
var
  SourceLines, TargetLines, CurrentLines: TArray<string>;
  Step, Later: TArray<TAtlasLineHunk>;
  A, B: TAtlasLineHunk;
  StepIndex, LaterIndex, Line, Index: Integer;
  Builder: TStringBuilder;

  function Touches(const AFirst, ASecond: TAtlasLineHunk): Boolean;
  begin
    // Überlappend oder direkt angrenzend; leere Blöcke (Einfügungen) an derselben Stelle auch.
    Result := Max(AFirst.OldStart, ASecond.OldStart) <=
      Min(AFirst.OldStart + AFirst.OldCount, ASecond.OldStart + ASecond.OldCount);
  end;

begin
  AResult := '';
  if ACurrent = ASource then
  begin
    AResult := ATarget;
    Exit(True);
  end;
  if ACurrent = ATarget then
  begin
    // Schon im Zielstand (z. B. von Hand genauso zurückgenommen).
    AResult := ATarget;
    Exit(True);
  end;
  SourceLines := SplitLines(ASource);
  TargetLines := SplitLines(ATarget);
  CurrentLines := SplitLines(ACurrent);
  Step := Hunks(SourceLines, TargetLines);
  Later := Hunks(SourceLines, CurrentLines);
  for A in Step do
    for B in Later do
      if Touches(A, B) then
        Exit(False);
  // Beide Blocklisten sind disjunkt: den Ausgangstext durchlaufen und je Block die passende Seite einsetzen.
  Builder := TStringBuilder.Create(Length(ACurrent));
  try
    StepIndex := 0;
    LaterIndex := 0;
    Line := 0;
    while (Line < Length(SourceLines)) or (StepIndex < Length(Step)) or (LaterIndex < Length(Later)) do
    begin
      if (StepIndex < Length(Step)) and (Step[StepIndex].OldStart = Line) then
      begin
        A := Step[StepIndex];
        for Index := A.NewStart to A.NewStart + A.NewCount - 1 do
          Builder.Append(TargetLines[Index]);
        Inc(Line, A.OldCount);
        Inc(StepIndex);
        Continue;
      end;
      if (LaterIndex < Length(Later)) and (Later[LaterIndex].OldStart = Line) then
      begin
        B := Later[LaterIndex];
        for Index := B.NewStart to B.NewStart + B.NewCount - 1 do
          Builder.Append(CurrentLines[Index]);
        Inc(Line, B.OldCount);
        Inc(LaterIndex);
        Continue;
      end;
      if Line >= Length(SourceLines) then
        Break;
      Builder.Append(SourceLines[Line]);
      Inc(Line);
    end;
    AResult := Builder.ToString;
  finally
    Builder.Free;
  end;
  Result := True;
end;

end.
