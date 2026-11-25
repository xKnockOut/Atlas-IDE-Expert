unit Atlas.Core.Debug.ParallelWatch;

// Ausdrücke in allen Threads auswerten (#866), ohne VCL und Open Tools API: die Tabelle des Fensters
// „Parallel auswerten“.
//   - Zeilen sind Threads (Kennung, Name, Ort des obersten eigenen Rahmens #578), Spalten die Ausdrücke. Spalte 0 ist
//     der Thread, Spalte 1 der Ort, ab Spalte 2 folgen die Ausdrücke (cFirstValue).
//   - Ein Wert, der sich im Thread nicht auswerten lässt (unbekannter Bezeichner), steht als „–“ da.
//   - Threads ohne eigenen Rahmen (Pool im Leerlauf, Systemthreads) sind ausgeblendet, außer AShowAll.
//   - Filter je Spalte: Zeilen, deren Text in der Spalte den Filtertext enthält (ohne Groß-/Kleinschreibung).
//   - Markierte Threads (#852) stehen oben; darunter nach der gewählten Spalte, Zahlen nach Wert, sonst nach Text;
//     bei Gleichstand bleibt die Reihenfolge der IDE.
//   - Ab cAutoLimit Threads wertet Atlas erst auf Knopfdruck aus.

interface

uses
  Atlas.Core.Debug.Threads,
  Atlas.Core.Debug.ThreadMarks;

type
  {$SCOPEDENUMS ON}
  TAtlasParallelCellState = (Pending, Value, Invalid);
  {$SCOPEDENUMS OFF}

  TAtlasParallelCell = record
    State: TAtlasParallelCellState;
    /// <summary>Wert; bei Invalid die Meldung des Debuggers (für den Hinweis), angezeigt wird „–“.</summary>
    Text: string;
    class function Create(AOk: Boolean; const AText: string): TAtlasParallelCell; static;
    /// <summary>Text in der Tabelle: Wert, „–“ oder '' solange offen.</summary>
    function Shown: string;
  end;

  TAtlasParallelRow = record
    /// <summary>Index in der Stapelliste der IDE.</summary>
    Thread: Integer;
    ThreadId: Cardinal;
    Name: string;
    /// <summary>Rahmen, in dem ausgewertet wird: oberster eigener, sonst oberster mit Quelltext ('' ohne).</summary>
    FileName: string;
    /// <summary>1-basiert; 0 ohne.</summary>
    Line: Integer;
    /// <summary>„Routine (Datei.pas:42)“; ohne Quelltext die Routine des obersten Rahmens.</summary>
    Place: string;
    HasOwn: Boolean;
    Flagged: Boolean;
    Cells: TArray<TAtlasParallelCell>;
    /// <summary>Text der Spalte AColumn (siehe Kopf).</summary>
    function ColumnText(AColumn: Integer): string;
  end;

  TAtlasParallelRows = TArray<TAtlasParallelRow>;

  TAtlasParallelFilter = record
    /// <summary>Spalte (siehe Kopf); -1 ohne Filter.</summary>
    Column: Integer;
    Text: string;
    class function None: TAtlasParallelFilter; static;
    function Active: Boolean;
    function Matches(const ARow: TAtlasParallelRow): Boolean;
  end;

  TAtlasParallelOrder = record
    /// <summary>Spalte (siehe Kopf); -1: Reihenfolge der IDE.</summary>
    Column: Integer;
    Descending: Boolean;
    class function None: TAtlasParallelOrder; static;
    /// <summary>Klick auf AColumn: dieselbe Spalte kehrt die Richtung um, eine andere sortiert aufsteigend.</summary>
    function Toggled(AColumn: Integer): TAtlasParallelOrder;
  end;

  TAtlasParallelWatch = record
  public const
    cThreadColumn = 0;
    cPlaceColumn = 1;
    cFirstValue = 2;
    /// <summary>Ab so vielen Threads erst auf Knopfdruck auswerten.</summary>
    cAutoLimit = 32;
    cInvalidText = '–';
  public
    /// <summary>Zeilen aus AStacks mit AColumns offenen Zellen; AFlagged: markierte Threads (#852).</summary>
    class function Rows(const AStacks: TAtlasDebugThreadStacks; AColumns: Integer;
      const AFlagged: TAtlasDebugThreadSet): TAtlasParallelRows; static;
    /// <summary>Indizes in ARows, die angezeigt werden, in der Reihenfolge der Anzeige (siehe Kopf).</summary>
    class function View(const ARows: TAtlasParallelRows; AShowAll: Boolean; const AFilter: TAtlasParallelFilter;
      const AOrder: TAtlasParallelOrder): TArray<Integer>; static;
    /// <summary>Wird bei AThreadCount Threads von selbst ausgewertet?</summary>
    class function Automatic(AThreadCount: Integer): Boolean; static;
    /// <summary>Vergleich zweier Texte einer Spalte: Zahlen nach Wert und vor Text, sonst ohne Groß-/Kleinschreibung.
    /// </summary>
    class function CompareText(const A, B: string): Integer; static;
    /// <summary>Spalte ohne die Zellen von AColumn (Ausdruck entfernt); Index ab 0 unter den Ausdrücken.</summary>
    class procedure DeleteColumn(var ARows: TAtlasParallelRows; AColumn: Integer); static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.CallStack;

{ TAtlasParallelCell }

class function TAtlasParallelCell.Create(AOk: Boolean; const AText: string): TAtlasParallelCell;
begin
  Result := Default(TAtlasParallelCell);
  Result.Text := AText;
  Result.State := TAtlasParallelCellState.Invalid;
  if AOk then
  begin
    Result.State := TAtlasParallelCellState.Value;
  end;
end;

function TAtlasParallelCell.Shown: string;
begin
  case State of
    TAtlasParallelCellState.Value:
      Result := Text;
    TAtlasParallelCellState.Invalid:
      Result := TAtlasParallelWatch.cInvalidText;
  else
    Result := '';
  end;
end;

{ TAtlasParallelRow }

function TAtlasParallelRow.ColumnText(AColumn: Integer): string;
begin
  Result := '';
  if AColumn = TAtlasParallelWatch.cThreadColumn then
  begin
    Result := Name;
    if Result = '' then
    begin
      Result := IntToStr(ThreadId);
    end;
  end
  else if AColumn = TAtlasParallelWatch.cPlaceColumn then
  begin
    Result := Place;
  end
  else if (AColumn >= TAtlasParallelWatch.cFirstValue) and
    (AColumn - TAtlasParallelWatch.cFirstValue <= High(Cells)) then
  begin
    Result := Cells[AColumn - TAtlasParallelWatch.cFirstValue].Shown;
  end;
end;

{ TAtlasParallelFilter }

class function TAtlasParallelFilter.None: TAtlasParallelFilter;
begin
  Result := Default(TAtlasParallelFilter);
  Result.Column := -1;
end;

function TAtlasParallelFilter.Active: Boolean;
begin
  Result := (Column >= 0) and (Trim(Text) <> '');
end;

function TAtlasParallelFilter.Matches(const ARow: TAtlasParallelRow): Boolean;
begin
  Result := not Active or (Pos(LowerCase(Trim(Text)), LowerCase(ARow.ColumnText(Column))) > 0);
end;

{ TAtlasParallelOrder }

class function TAtlasParallelOrder.None: TAtlasParallelOrder;
begin
  Result := Default(TAtlasParallelOrder);
  Result.Column := -1;
end;

function TAtlasParallelOrder.Toggled(AColumn: Integer): TAtlasParallelOrder;
begin
  Result := Default(TAtlasParallelOrder);
  Result.Column := AColumn;
  Result.Descending := (AColumn = Column) and not Descending;
end;

{ TAtlasParallelWatch }

/// <summary>„Routine (Datei.pas:42)“ des Rahmens AFrame.</summary>
function PlaceOf(const AFrame: TAtlasDebugFrame): string;
begin
  Result := AFrame.Routine;
  if AFrame.HasSource then
  begin
    // Pfade der IDE mit \ oder /, auch unter Linux in den Tests.
    Result := Result + ' (' + Copy(AFrame.FileName, LastDelimiter('\/', AFrame.FileName) + 1, MaxInt) + ':' +
      IntToStr(AFrame.Line) + ')';
  end;
end;

class function TAtlasParallelWatch.Rows(const AStacks: TAtlasDebugThreadStacks; AColumns: Integer;
  const AFlagged: TAtlasDebugThreadSet): TAtlasParallelRows;
var
  mIndex, mFrame: Integer;
  mRow: TAtlasParallelRow;
begin
  Result := nil;
  SetLength(Result, Length(AStacks));
  for mIndex := 0 to High(AStacks) do
  begin
    mRow := Default(TAtlasParallelRow);
    mRow.Thread := mIndex;
    mRow.ThreadId := AStacks[mIndex].ThreadId;
    mRow.Name := AStacks[mIndex].Name;
    mRow.HasOwn := AStacks[mIndex].FirstOwn >= 0;
    mRow.Flagged := AFlagged.Contains(mRow.ThreadId);
    mFrame := AStacks[mIndex].JumpFrame;
    if mFrame >= 0 then
    begin
      mRow.FileName := AStacks[mIndex].Frames[mFrame].FileName;
      mRow.Line := AStacks[mIndex].Frames[mFrame].Line;
      mRow.Place := PlaceOf(AStacks[mIndex].Frames[mFrame]);
    end
    else if AStacks[mIndex].Frames <> nil then
    begin
      mRow.Place := PlaceOf(AStacks[mIndex].Frames[0]);
    end;
    SetLength(mRow.Cells, AColumns);
    Result[mIndex] := mRow;
  end;
end;

/// <summary>Steht ARows[A] in der Anzeige vor ARows[B]? Markierte zuerst, dann AOrder, dann Reihenfolge der IDE.
/// </summary>
function Before(const ARows: TAtlasParallelRows; A, B: Integer; const AOrder: TAtlasParallelOrder): Boolean;
var
  mCompare: Integer;
begin
  if ARows[A].Flagged <> ARows[B].Flagged then
  begin
    Exit(ARows[A].Flagged);
  end;
  mCompare := 0;
  if AOrder.Column >= 0 then
  begin
    mCompare := TAtlasParallelWatch.CompareText(ARows[A].ColumnText(AOrder.Column),
      ARows[B].ColumnText(AOrder.Column));
    if AOrder.Descending then
    begin
      mCompare := -mCompare;
    end;
  end;
  if mCompare = 0 then
  begin
    mCompare := ARows[A].Thread - ARows[B].Thread;
  end;
  Result := mCompare < 0;
end;

class function TAtlasParallelWatch.View(const ARows: TAtlasParallelRows; AShowAll: Boolean;
  const AFilter: TAtlasParallelFilter; const AOrder: TAtlasParallelOrder): TArray<Integer>;
var
  mIndex, mAt, mCount: Integer;
begin
  Result := nil;
  SetLength(Result, Length(ARows));
  mCount := 0;
  for mIndex := 0 to High(ARows) do
  begin
    if (AShowAll or ARows[mIndex].HasOwn) and AFilter.Matches(ARows[mIndex]) then
    begin
      // Einfügen an der richtigen Stelle; die Liste ist klein.
      mAt := mCount;
      while (mAt > 0) and Before(ARows, mIndex, Result[mAt - 1], AOrder) do
      begin
        Result[mAt] := Result[mAt - 1];
        Dec(mAt);
      end;
      Result[mAt] := mIndex;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

class function TAtlasParallelWatch.Automatic(AThreadCount: Integer): Boolean;
begin
  Result := AThreadCount < cAutoLimit;
end;

class function TAtlasParallelWatch.CompareText(const A, B: string): Integer;
var
  mA, mB: Double;
  mNumberA, mNumberB: Boolean;
begin
  mNumberA := TryStrToFloat(Trim(A), mA, TFormatSettings.Invariant);
  mNumberB := TryStrToFloat(Trim(B), mB, TFormatSettings.Invariant);
  if mNumberA and mNumberB then
  begin
    Result := 0;
    if mA < mB then
    begin
      Result := -1;
    end
    else if mA > mB then
    begin
      Result := 1;
    end;
  end
  else if mNumberA <> mNumberB then
  begin
    Result := Ord(mNumberB) - Ord(mNumberA);
  end
  else
  begin
    Result := System.SysUtils.CompareText(A, B);
  end;
end;

class procedure TAtlasParallelWatch.DeleteColumn(var ARows: TAtlasParallelRows; AColumn: Integer);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ARows) do
  begin
    if (AColumn >= 0) and (AColumn <= High(ARows[mIndex].Cells)) then
    begin
      Delete(ARows[mIndex].Cells, AColumn, 1);
    end;
  end;
end;

end.
