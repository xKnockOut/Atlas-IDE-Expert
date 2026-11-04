unit Atlas.Core.Welcome.Layout;

// Atlas-Layout der Willkommensseite (#753, frei anordnen #767), ohne VCL und
// Open Tools API: welche Bereiche in welcher Spalte, in welcher Reihenfolge
// und wie breit stehen.
// TAtlasWelcomeLayout.Atlas ist die Anordnung aus dem Mockup (links
// Weiterarbeiten, Projekte, Projektverlauf, Testergebnisse; rechts
// Zustandskachel, Nicht gesichert, Neu in Atlas, Atlas entdecken, Projekt
// einrichten, Meine Issues, Hilfe). Arrange verteilt die eingeschalteten
// Bereiche auf eine gewünschte Spaltenzahl: Bereiche, die das Layout nicht
// kennt, kommen ans Ende ihrer Vorgabespalte; bei weniger Spalten rücken die
// rechten Spalten unter die linken (schmales Fenster „Atlas-Start“).
// Für eigene Layouts (#767) gibt es je Platz Breite (eine oder zwei Spalten)
// und Sichtbarkeit sowie Bearbeitungen als reine Funktionen: Verschieben an
// eine Stelle (Ziehen), um einen Schritt (Strg+Pfeiltasten), Breite,
// Spaltenzahl und neue Bereiche ans Ende der Spalte mit dem meisten Platz.
// TAtlasWelcomeFlow rechnet daraus die Lage der Bereiche auf der Fläche
// (zweispaltige Bereiche über zwei Spalten) und das Ziel beim Ziehen.

interface

uses
  System.SysUtils,
  Atlas.Core.Welcome.Sections;

type
{$SCOPEDENUMS ON}
  /// <summary>Verschieben um einen Schritt (Strg+Pfeiltasten im Bearbeitungsmodus, #767).</summary>
  TAtlasWelcomeMove = (Up, Down, Left, Right);
{$SCOPEDENUMS OFF}

  TAtlasWelcomeSlot = record
    Id: string;
    /// <summary>Spalte ab 0.</summary>
    Column: Integer;
    /// <summary>1 = eine Spalte, 2 = zwei Spalten breit (ab Column nach rechts, #767).</summary>
    Width: Integer;
    /// <summary>Sichtbar? Spiegel der Einstellung des Bereichs im aktiven Layout (#767).</summary>
    Visible: Boolean;
    class function Create(const AId: string; AColumn: Integer): TAtlasWelcomeSlot; overload; static;
    class function Create(const AId: string; AColumn, AWidth: Integer; AVisible: Boolean): TAtlasWelcomeSlot;
      overload; static;
  end;

  /// <summary>Ein Bereich in einer Spalte mit seiner Breite in Spalten.</summary>
  TAtlasWelcomeCell = record
    Id: string;
    Span: Integer;
    class function Create(const AId: string; ASpan: Integer): TAtlasWelcomeCell; static;
  end;

  /// <summary>Bereiche je Spalte in Lesereihenfolge.</summary>
  TAtlasWelcomeCells = TArray<TArray<TAtlasWelcomeCell>>;

  /// <summary>Gewicht eines Bereichs für „Spalte mit dem meisten Platz“ (z. B. seine Höhe).</summary>
  TAtlasWelcomeWeight = reference to function(const AId: string): Integer;

  TAtlasWelcomeLayout = record
  public const
    MinColumns = 1;
    MaxColumns = 3;
    MinWidth = 1;
    MaxWidth = 2;
    /// <summary>Name des Atlas-Layouts und des ersten Layouts (welcomePage.activeLayout, #767).</summary>
    DefaultName = 'Standard';
  public
    Name: string;
    Columns: Integer;
    /// <summary>Plätze in Lesereihenfolge; innerhalb einer Spalte gilt diese Reihenfolge.</summary>
    Slots: TArray<TAtlasWelcomeSlot>;
    /// <summary>Anordnung aus dem Mockup (#753, mit den späteren Bereichen #762–#766).</summary>
    class function Atlas: TAtlasWelcomeLayout; static;
    /// <summary>Platz von AId; False, wenn das Layout den Bereich nicht kennt.</summary>
    function SlotOf(const AId: string; out ASlot: TAtlasWelcomeSlot): Boolean;
    function IndexOf(const AId: string): Integer;
    /// <summary>Dasselbe Layout mit AId ganz oben in der ersten Spalte (Karte „Neu in Atlas“ nach einem
    /// Update, #756); die übrigen Plätze behalten Spalte und Reihenfolge.</summary>
    function MovedToTop(const AId: string): TAtlasWelcomeLayout;
    /// <summary>Kennungen je Spalte (AColumns Spalten, mindestens eine) für die sichtbaren ASections.</summary>
    function Arrange(const ASections: TArray<TAtlasWelcomeSection>; AColumns: Integer): TArray<TArray<string>>;
    /// <summary>Wie Arrange, mit der Breite je Bereich (höchstens bis zur letzten Spalte).</summary>
    function Cells(const ASections: TArray<TAtlasWelcomeSection>; AColumns: Integer): TAtlasWelcomeCells;
    /// <summary>AId in Spalte AColumn vor ABeforeId; ABeforeId = '' (oder unbekannt) ans Ende der Spalte.
    /// Ein unbekannter Bereich bekommt einen neuen Platz (sichtbar, eine Spalte breit).</summary>
    function MovedTo(const AId: string; AColumn: Integer; const ABeforeId: string): TAtlasWelcomeLayout;
    /// <summary>Strg+Pfeiltaste: AId in der Anordnung von ASections (sichtbare Bereiche) um einen Schritt
    /// verschieben. False am Rand oder für einen Bereich, der nicht zu sehen ist.</summary>
    function MovedBy(const AId: string; ADirection: TAtlasWelcomeMove; const ASections: TArray<TAtlasWelcomeSection>;
      out ALayout: TAtlasWelcomeLayout): Boolean;
    /// <summary>Breite von AId (1 oder 2, begrenzt); ein unbekannter Bereich bekommt einen Platz.</summary>
    function WithWidth(const AId: string; AWidth: Integer): TAtlasWelcomeLayout;
    /// <summary>Breite von AId; 1 für unbekannte Bereiche.</summary>
    function WidthOf(const AId: string): Integer;
    /// <summary>Sichtbarkeit von AId setzen.</summary>
    function WithVisible(const AId: string; AVisible: Boolean): TAtlasWelcomeLayout;
    /// <summary>Spaltenzahl (1–3). Plätze rechts davon behalten ihre Spalte und stehen in der Anzeige (Cells) am
    /// Ende der letzten; beim Zurückschalten wieder an ihrem Platz.</summary>
    function WithColumns(AColumns: Integer): TAtlasWelcomeLayout;
    /// <summary>Bereiche aus AIds, die das Layout noch nicht kennt, ans Ende der Spalte mit dem meisten Platz
    /// (kleinste Summe von AWeight über die sichtbaren Plätze; nil = jeder Platz zählt 1, Gleichstand: linke
    /// Spalte). AAdded nennt die neuen Kennungen.</summary>
    function Adopted(const AIds: TArray<string>; const AWeight: TAtlasWelcomeWeight;
      out AAdded: TArray<string>): TAtlasWelcomeLayout;
    /// <summary>Spalte mit dem meisten Platz (siehe Adopted).</summary>
    function RoomiestColumn(const AWeight: TAtlasWelcomeWeight): Integer;
    function ToJson: string;
    /// <summary>False bei ungültigem Text; ALayout ist dann Atlas.</summary>
    class function FromJson(const AText: string; out ALayout: TAtlasWelcomeLayout): Boolean; static;
    class function Same(const ALeft, ARight: TAtlasWelcomeLayout): Boolean; static;
  end;

  /// <summary>Lage eines Bereichs auf der Fläche (Pixel, Top ohne Rollen).</summary>
  TAtlasWelcomePlaced = record
    Id: string;
    Column: Integer;
    Span: Integer;
    Left: Integer;
    Top: Integer;
    Width: Integer;
    Height: Integer;
  end;

  /// <summary>Fläche für TAtlasWelcomeFlow: Breite innen, Abstand der Spalten, Mindestbreite einer Spalte.</summary>
  TAtlasWelcomeArea = record
    ClientWidth: Integer;
    Gap: Integer;
    MinWidth: Integer;
    class function Create(AClientWidth, AGap, AMinWidth: Integer): TAtlasWelcomeArea; static;
  end;

  /// <summary>Ziel beim Ziehen: Spalte und der Bereich, vor dem eingefügt wird ('' = ans Ende).</summary>
  TAtlasWelcomeDrop = record
    Column: Integer;
    Before: string;
  end;

  /// <summary>Einfügelinie: linke Kante, Mitte der Lücke und Breite.</summary>
  TAtlasWelcomeInsertLine = record
    Left: Integer;
    Top: Integer;
    Width: Integer;
  end;

  /// <summary>Höhe eines Bereichs bei der Breite AWidth.</summary>
  TAtlasWelcomeHeight = reference to function(const AId: string; AWidth: Integer): Integer;

  /// <summary>Lage auf der Fläche, ohne VCL: Spalten gleicher Breite mit Abstand; ein zweispaltiger Bereich
  /// beginnt unter dem tieferen Ende beider Spalten. Reihenfolge: immer die Spalte mit dem höchsten Ende zuerst;
  /// wartet dort ein zweispaltiger Bereich, füllt erst die rechte Nachbarspalte auf.</summary>
  TAtlasWelcomeFlow = class
  public
    /// <summary>Breite einer Spalte, mindestens AMinWidth.</summary>
    class function ColumnWidth(ACount, AClientWidth, AGap, AMinWidth: Integer): Integer; static;
    /// <summary>So viele der AWanted Spalten, wie mit AMinWidth nebeneinander passen (mindestens eine).</summary>
    class function FitColumns(AWanted, AClientWidth, AGap, AMinWidth: Integer): Integer; static;
    /// <summary>Linke Kante von Spalte AColumn.</summary>
    class function ColumnLeft(AColumn, ACount, AClientWidth, AGap, AMinWidth: Integer): Integer; static;
    /// <summary>Spalte unter AX (begrenzt auf 0..ACount-1).</summary>
    class function ColumnAt(AX, ACount, AClientWidth, AGap, AMinWidth: Integer): Integer; static;
    class function Place(const ACells: TAtlasWelcomeCells; AClientWidth, AGap, AMinWidth: Integer;
      const AHeight: TAtlasWelcomeHeight): TArray<TAtlasWelcomePlaced>; static;
    /// <summary>Ziel beim Ziehen an (AX, AY): Spalte unter AX, davor der erste Bereich dieser Spalte (außer
    /// ADragged), dessen Mitte unter AY liegt; ABefore = '' heißt ans Ende.</summary>
    class function DropTarget(const ACells: TAtlasWelcomeCells; const APlaced: TArray<TAtlasWelcomePlaced>;
      const AArea: TAtlasWelcomeArea; AX, AY: Integer; const ADragged: string): TAtlasWelcomeDrop; static;
    /// <summary>Einfügelinie für (AColumn, ABefore): oberhalb von ABefore bzw. unter dem letzten Bereich der
    /// Spalte; ATop ist die Mitte der Lücke.</summary>
    class function InsertLine(const ACells: TAtlasWelcomeCells; const APlaced: TArray<TAtlasWelcomePlaced>;
      const AArea: TAtlasWelcomeArea; AColumn: Integer; const ABefore: string): TAtlasWelcomeInsertLine; static;
    /// <summary>Spalte mit dem tiefsten freien Platz oben (kleinstes Ende); Gleichstand: linke.</summary>
    class function ShortestColumn(const ACells: TAtlasWelcomeCells; const APlaced: TArray<TAtlasWelcomePlaced>;
      AGap: Integer): Integer; static;
    /// <summary>Index von AId in APlaced; -1 ohne.</summary>
    class function IndexOf(const APlaced: TArray<TAtlasWelcomePlaced>; const AId: string): Integer; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  System.JSON;

function Clamp(AValue, AMin, AMax: Integer): Integer;
begin
  Result := AValue;
  if Result < AMin then
  begin
    Result := AMin;
  end;
  if Result > AMax then
  begin
    Result := AMax;
  end;
end;

{ TAtlasWelcomeSlot }

class function TAtlasWelcomeSlot.Create(const AId: string; AColumn: Integer): TAtlasWelcomeSlot;
begin
  Result := Create(AId, AColumn, 1, True);
end;

class function TAtlasWelcomeSlot.Create(const AId: string; AColumn, AWidth: Integer;
  AVisible: Boolean): TAtlasWelcomeSlot;
begin
  Result.Id := AId;
  Result.Column := AColumn;
  Result.Width := Clamp(AWidth, TAtlasWelcomeLayout.MinWidth, TAtlasWelcomeLayout.MaxWidth);
  Result.Visible := AVisible;
end;

{ TAtlasWelcomeCell }

class function TAtlasWelcomeCell.Create(const AId: string; ASpan: Integer): TAtlasWelcomeCell;
begin
  Result.Id := AId;
  Result.Span := ASpan;
end;

{ TAtlasWelcomeLayout }

class function TAtlasWelcomeLayout.Atlas: TAtlasWelcomeLayout;
begin
  Result.Name := DefaultName;
  Result.Columns := 2;
  // Testergebnisse (#763) nach dem Projektverlauf (Mockup WS17), Nicht gesichert (#762) unter der Kachel,
  // Meine Issues (#765), Sprint (#1277) und Hilfe (#766) am Ende der rechten Spalte.
  Result.Slots := [
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.Continue, 0),
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.Projects, 0),
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.History, 0),
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.Tests, 0),
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.State, 1),
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.Unsaved, 1),
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.News, 1),
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.Discover, 1),
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.Setup, 1),
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.Issues, 1),
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.Sprint, 1),
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.Help, 1)];
end;

function TAtlasWelcomeLayout.IndexOf(const AId: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Slots) do
  begin
    if SameText(Slots[Index].Id, AId) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

function TAtlasWelcomeLayout.SlotOf(const AId: string; out ASlot: TAtlasWelcomeSlot): Boolean;
var
  Index: Integer;
begin
  Index := IndexOf(AId);
  Result := Index >= 0;
  if Result then
  begin
    ASlot := Slots[Index];
  end
  else
  begin
    ASlot := TAtlasWelcomeSlot.Create(AId, 0);
  end;
end;

function TAtlasWelcomeLayout.MovedToTop(const AId: string): TAtlasWelcomeLayout;
var
  Slot, Moved: TAtlasWelcomeSlot;
begin
  SlotOf(AId, Moved);
  Moved.Column := 0;
  Result.Name := Name;
  Result.Columns := Columns;
  Result.Slots := [Moved];
  for Slot in Slots do
  begin
    if not SameText(Slot.Id, AId) then
    begin
      Result.Slots := Result.Slots + [Slot];
    end;
  end;
end;

function SectionIndex(const ASections: TArray<TAtlasWelcomeSection>; const AId: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ASections) do
  begin
    if SameText(ASections[mIndex].Id, AId) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Spalten AWide auf ATarget Spalten falten: überzählige rücken unter die letzte.</summary>
function FoldedCells(const AWide: TAtlasWelcomeCells; ATarget: Integer): TAtlasWelcomeCells;
var
  mColumn: Integer;
  mCell: TAtlasWelcomeCell;
begin
  Result := nil;
  SetLength(Result, ATarget);
  for mColumn := 0 to High(AWide) do
  begin
    for mCell in AWide[mColumn] do
    begin
      if mColumn < ATarget then
      begin
        Result[mColumn] := Result[mColumn] + [TAtlasWelcomeCell.Create(mCell.Id, Clamp(mCell.Span, 1,
          ATarget - mColumn))];
      end
      else
      begin
        Result[ATarget - 1] := Result[ATarget - 1] + [TAtlasWelcomeCell.Create(mCell.Id, 1)];
      end;
    end;
  end;
end;

function TAtlasWelcomeLayout.Cells(const ASections: TArray<TAtlasWelcomeSection>;
  AColumns: Integer): TAtlasWelcomeCells;
var
  mWide: TAtlasWelcomeCells;
  mWidth, mColumn, mIndex: Integer;
  mSlot: TAtlasWelcomeSlot;
  mSection: TAtlasWelcomeSection;
begin
  // Zuerst in der Breite des Layouts verteilen (mindestens zwei Spalten für die Vorgabespalten) …
  mWidth := Clamp(Columns, 2, MaxColumns);
  SetLength(mWide, mWidth);
  for mSlot in Slots do
  begin
    mIndex := SectionIndex(ASections, mSlot.Id);
    if mIndex >= 0 then
    begin
      mColumn := Clamp(mSlot.Column, 0, mWidth - 1);
      mWide[mColumn] := mWide[mColumn] + [TAtlasWelcomeCell.Create(ASections[mIndex].Id, Clamp(mSlot.Width,
        MinWidth, MaxWidth))];
    end;
  end;
  for mSection in ASections do
  begin
    if IndexOf(mSection.Id) < 0 then
    begin
      mColumn := Clamp(Ord(mSection.Column), 0, mWidth - 1);
      mWide[mColumn] := mWide[mColumn] + [TAtlasWelcomeCell.Create(mSection.Id, 1)];
    end;
  end;
  // … dann auf die gewünschte Zahl falten.
  Result := FoldedCells(mWide, Clamp(AColumns, MinColumns, MaxColumns));
end;

function TAtlasWelcomeLayout.Arrange(const ASections: TArray<TAtlasWelcomeSection>;
  AColumns: Integer): TArray<TArray<string>>;
var
  Grid: TAtlasWelcomeCells;
  Column: Integer;
  Cell: TAtlasWelcomeCell;
begin
  Result := nil;
  Grid := Cells(ASections, AColumns);
  SetLength(Result, Length(Grid));
  for Column := 0 to High(Grid) do
  begin
    for Cell in Grid[Column] do
    begin
      Result[Column] := Result[Column] + [Cell.Id];
    end;
  end;
end;

function TAtlasWelcomeLayout.MovedTo(const AId: string; AColumn: Integer;
  const ABeforeId: string): TAtlasWelcomeLayout;
var
  Moved: TAtlasWelcomeSlot;
  Index, Before: Integer;
begin
  SlotOf(AId, Moved);
  Moved.Column := Clamp(AColumn, 0, MaxColumns - 1);
  Result.Name := Name;
  Result.Columns := Columns;
  Result.Slots := nil;
  for Index := 0 to High(Slots) do
  begin
    if not SameText(Slots[Index].Id, AId) then
    begin
      Result.Slots := Result.Slots + [Slots[Index]];
    end;
  end;
  Before := -1;
  if (ABeforeId <> '') and not SameText(ABeforeId, AId) then
  begin
    Before := Result.IndexOf(ABeforeId);
  end;
  if Before < 0 then
  begin
    // Innerhalb einer Spalte gilt die Reihenfolge der Liste: hinten angehängt = letzter der Spalte.
    Result.Slots := Result.Slots + [Moved];
  end
  else
  begin
    Insert(Moved, Result.Slots, Before);
  end;
end;

function FindCell(const AGrid: TAtlasWelcomeCells; const AId: string; out AColumn, ARow: Integer): Boolean;
var
  mColumn, mRow: Integer;
begin
  AColumn := -1;
  ARow := -1;
  for mColumn := 0 to High(AGrid) do
  begin
    for mRow := 0 to High(AGrid[mColumn]) do
    begin
      if SameText(AGrid[mColumn][mRow].Id, AId) then
      begin
        AColumn := mColumn;
        ARow := mRow;
      end;
    end;
  end;
  Result := AColumn >= 0;
end;

/// <summary>Kennung in Spalte AColumn, Zeile ARow; '' außerhalb.</summary>
function CellIdAt(const AGrid: TAtlasWelcomeCells; AColumn, ARow: Integer): string;
begin
  Result := '';
  if (AColumn >= 0) and (AColumn <= High(AGrid)) and (ARow >= 0) and (ARow <= High(AGrid[AColumn])) then
  begin
    Result := AGrid[AColumn][ARow].Id;
  end;
end;

/// <summary>Ziel eines Schritts von (AColumn, ARow); False am Rand.</summary>
function StepTarget(const AGrid: TAtlasWelcomeCells; AColumn, ARow: Integer; ADirection: TAtlasWelcomeMove;
  out ATarget: Integer; out ABefore: string): Boolean;
begin
  case ADirection of
    TAtlasWelcomeMove.Up:
      begin
        Result := ARow > 0;
        ATarget := AColumn;
        ABefore := CellIdAt(AGrid, AColumn, ARow - 1);
      end;
    TAtlasWelcomeMove.Down:
      begin
        Result := ARow < High(AGrid[AColumn]);
        ATarget := AColumn;
        ABefore := CellIdAt(AGrid, AColumn, ARow + 2);
      end;
    TAtlasWelcomeMove.Left:
      begin
        Result := AColumn > 0;
        ATarget := AColumn - 1;
        ABefore := CellIdAt(AGrid, ATarget, ARow);
      end;
  else
    begin
      Result := AColumn < High(AGrid);
      ATarget := AColumn + 1;
      ABefore := CellIdAt(AGrid, ATarget, ARow);
    end;
  end;
end;

function TAtlasWelcomeLayout.MovedBy(const AId: string; ADirection: TAtlasWelcomeMove;
  const ASections: TArray<TAtlasWelcomeSection>; out ALayout: TAtlasWelcomeLayout): Boolean;
var
  mGrid: TAtlasWelcomeCells;
  mColumn, mRow, mTarget: Integer;
  mBefore: string;
begin
  ALayout := Self;
  mGrid := Cells(ASections, Columns);
  Result := FindCell(mGrid, AId, mColumn, mRow) and StepTarget(mGrid, mColumn, mRow, ADirection, mTarget, mBefore);
  if Result then
  begin
    ALayout := MovedTo(AId, mTarget, mBefore);
  end;
end;

function TAtlasWelcomeLayout.WithWidth(const AId: string; AWidth: Integer): TAtlasWelcomeLayout;
var
  Index: Integer;
begin
  Result := Self;
  Result.Slots := Copy(Slots);
  Index := Result.IndexOf(AId);
  if Index < 0 then
  begin
    Result.Slots := Result.Slots + [TAtlasWelcomeSlot.Create(AId, 0)];
    Index := High(Result.Slots);
  end;
  Result.Slots[Index].Width := Clamp(AWidth, MinWidth, MaxWidth);
end;

function TAtlasWelcomeLayout.WidthOf(const AId: string): Integer;
var
  Slot: TAtlasWelcomeSlot;
begin
  Result := 1;
  if SlotOf(AId, Slot) then
  begin
    Result := Clamp(Slot.Width, MinWidth, MaxWidth);
  end;
end;

function TAtlasWelcomeLayout.WithVisible(const AId: string; AVisible: Boolean): TAtlasWelcomeLayout;
var
  Index: Integer;
begin
  Result := Self;
  Result.Slots := Copy(Slots);
  Index := Result.IndexOf(AId);
  if Index < 0 then
  begin
    Result.Slots := Result.Slots + [TAtlasWelcomeSlot.Create(AId, 0)];
    Index := High(Result.Slots);
  end;
  Result.Slots[Index].Visible := AVisible;
end;

function TAtlasWelcomeLayout.WithColumns(AColumns: Integer): TAtlasWelcomeLayout;
begin
  // Die Plätze behalten ihre Spalte: Cells faltet die rechten unter die letzte, und beim Zurückschalten
  // stehen sie wieder an ihrem Platz.
  Result := Self;
  Result.Slots := Copy(Slots);
  Result.Columns := Clamp(AColumns, MinColumns, MaxColumns);
end;

function TAtlasWelcomeLayout.RoomiestColumn(const AWeight: TAtlasWelcomeWeight): Integer;
var
  Load: TArray<Int64>;
  Count, Column, Index, Weight: Integer;
  Slot: TAtlasWelcomeSlot;
begin
  Count := Clamp(Columns, MinColumns, MaxColumns);
  SetLength(Load, Count);
  for Slot in Slots do
  begin
    if not Slot.Visible then
    begin
      Continue;
    end;
    Weight := 1;
    if Assigned(AWeight) then
    begin
      Weight := AWeight(Slot.Id);
    end;
    Column := Clamp(Slot.Column, 0, Count - 1);
    for Index := Column to Clamp(Column + Slot.Width - 1, 0, Count - 1) do
    begin
      Inc(Load[Index], Weight);
    end;
  end;
  Result := 0;
  for Column := 1 to Count - 1 do
  begin
    if Load[Column] < Load[Result] then
    begin
      Result := Column;
    end;
  end;
end;

function TAtlasWelcomeLayout.Adopted(const AIds: TArray<string>; const AWeight: TAtlasWelcomeWeight;
  out AAdded: TArray<string>): TAtlasWelcomeLayout;
var
  Id: string;
begin
  AAdded := nil;
  Result := Self;
  Result.Slots := Copy(Slots);
  for Id in AIds do
  begin
    if (Id = '') or (Result.IndexOf(Id) >= 0) then
    begin
      Continue;
    end;
    // Jeder neue Bereich zählt für den nächsten mit: mehrere neue verteilen sich.
    Result.Slots := Result.Slots + [TAtlasWelcomeSlot.Create(Id, Result.RoomiestColumn(AWeight))];
    AAdded := AAdded + [Id];
  end;
end;

function TAtlasWelcomeLayout.ToJson: string;
var
  Root, Item: TJSONObject;
  List: TJSONArray;
  Slot: TAtlasWelcomeSlot;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('name', Name);
    Root.AddPair('columns', TJSONNumber.Create(Columns));
    List := TJSONArray.Create;
    Root.AddPair('slots', List);
    for Slot in Slots do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('id', Slot.Id);
      Item.AddPair('column', TJSONNumber.Create(Slot.Column));
      Item.AddPair('width', TJSONNumber.Create(Clamp(Slot.Width, MinWidth, MaxWidth)));
      Item.AddPair('visible', TJSONBool.Create(Slot.Visible));
      List.AddElement(Item);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function IntegerField(AItem: TJSONObject; const AName: string; ADefault, AMin, AMax: Integer): Integer;
var
  mField: TJSONValue;
begin
  Result := ADefault;
  mField := AItem.GetValue(AName);
  if mField is TJSONNumber then
  begin
    Result := Clamp(TJSONNumber(mField).AsInt, AMin, AMax);
  end;
end;

function BooleanField(AItem: TJSONObject; const AName: string; ADefault: Boolean): Boolean;
var
  mField: TJSONValue;
begin
  Result := ADefault;
  mField := AItem.GetValue(AName);
  if mField is TJSONBool then
  begin
    Result := TJSONBool(mField).AsBoolean;
  end;
end;

/// <summary>Plätze aus „slots“ in ALayout; doppelte Kennung: der erste Platz gilt. False bei ungültigem Eintrag.</summary>
function SlotsFromJson(AList: TJSONArray; var ALayout: TAtlasWelcomeLayout): Boolean;
var
  mIndex: Integer;
  mItem: TJSONObject;
  mField: TJSONValue;
  mId: string;
begin
  ALayout.Slots := nil;
  for mIndex := 0 to AList.Count - 1 do
  begin
    if not (AList.Items[mIndex] is TJSONObject) then
    begin
      Exit(False);
    end;
    mItem := TJSONObject(AList.Items[mIndex]);
    mField := mItem.GetValue('id');
    if not (mField is TJSONString) or (Trim(mField.Value) = '') then
    begin
      Exit(False);
    end;
    mId := Trim(mField.Value);
    if ALayout.IndexOf(mId) < 0 then
    begin
      ALayout.Slots := ALayout.Slots + [TAtlasWelcomeSlot.Create(mId,
        IntegerField(mItem, 'column', 0, 0, TAtlasWelcomeLayout.MaxColumns - 1),
        IntegerField(mItem, 'width', 1, TAtlasWelcomeLayout.MinWidth, TAtlasWelcomeLayout.MaxWidth),
        BooleanField(mItem, 'visible', True))];
    end;
  end;
  Result := True;
end;

class function TAtlasWelcomeLayout.FromJson(const AText: string; out ALayout: TAtlasWelcomeLayout): Boolean;
var
  mValue, mField: TJSONValue;
  mRoot: TJSONObject;
begin
  ALayout := Atlas;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AText);
  try
    if mValue is TJSONObject then
    begin
      mRoot := TJSONObject(mValue);
      mField := mRoot.GetValue('slots');
      Result := (mField is TJSONArray) and SlotsFromJson(TJSONArray(mField), ALayout);
      mField := mRoot.GetValue('name');
      if Result and (mField is TJSONString) then
      begin
        ALayout.Name := mField.Value;
      end;
      ALayout.Columns := IntegerField(mRoot, 'columns', ALayout.Columns, MinColumns, MaxColumns);
    end;
  finally
    mValue.Free;
  end;
  if not Result then
  begin
    ALayout := Atlas;
  end;
end;

class function TAtlasWelcomeLayout.Same(const ALeft, ARight: TAtlasWelcomeLayout): Boolean;
var
  Index: Integer;
begin
  Result := (ALeft.Name = ARight.Name) and (ALeft.Columns = ARight.Columns) and
    (Length(ALeft.Slots) = Length(ARight.Slots));
  if not Result then
  begin
    Exit;
  end;
  for Index := 0 to High(ALeft.Slots) do
  begin
    if not SameText(ALeft.Slots[Index].Id, ARight.Slots[Index].Id) or
      (ALeft.Slots[Index].Column <> ARight.Slots[Index].Column) or
      (ALeft.Slots[Index].Width <> ARight.Slots[Index].Width) or
      (ALeft.Slots[Index].Visible <> ARight.Slots[Index].Visible) then
    begin
      Exit(False);
    end;
  end;
end;

{ TAtlasWelcomeArea }

class function TAtlasWelcomeArea.Create(AClientWidth, AGap, AMinWidth: Integer): TAtlasWelcomeArea;
begin
  Result.ClientWidth := AClientWidth;
  Result.Gap := AGap;
  Result.MinWidth := AMinWidth;
end;

{ TAtlasWelcomeFlow }

class function TAtlasWelcomeFlow.ColumnWidth(ACount, AClientWidth, AGap, AMinWidth: Integer): Integer;
begin
  if ACount < 1 then
  begin
    ACount := 1;
  end;
  Result := (AClientWidth - (ACount + 1) * AGap) div ACount;
  if Result < AMinWidth then
  begin
    Result := AMinWidth;
  end;
end;

class function TAtlasWelcomeFlow.FitColumns(AWanted, AClientWidth, AGap, AMinWidth: Integer): Integer;
begin
  Result := Clamp(AWanted, TAtlasWelcomeLayout.MinColumns, TAtlasWelcomeLayout.MaxColumns);
  while (Result > 1) and ((AClientWidth - (Result + 1) * AGap) div Result < AMinWidth) do
  begin
    Dec(Result);
  end;
end;

class function TAtlasWelcomeFlow.ColumnLeft(AColumn, ACount, AClientWidth, AGap, AMinWidth: Integer): Integer;
begin
  Result := AGap + AColumn * (ColumnWidth(ACount, AClientWidth, AGap, AMinWidth) + AGap);
end;

class function TAtlasWelcomeFlow.ColumnAt(AX, ACount, AClientWidth, AGap, AMinWidth: Integer): Integer;
var
  Width: Integer;
begin
  if ACount < 1 then
  begin
    Exit(0);
  end;
  Width := ColumnWidth(ACount, AClientWidth, AGap, AMinWidth);
  // Die Lücke links einer Spalte gehört zu ihr.
  Result := Clamp((AX - AGap div 2) div (Width + AGap), 0, ACount - 1);
end;

class function TAtlasWelcomeFlow.IndexOf(const APlaced: TArray<TAtlasWelcomePlaced>; const AId: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(APlaced) do
  begin
    if SameText(APlaced[Index].Id, AId) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

/// <summary>Nächste Spalte zum Platzieren: die mit dem höchsten Ende, die noch Bereiche hat; wartet dort ein
/// zweispaltiger Bereich, erst die Nachbarspalte bis auf seine Höhe.</summary>
function NextColumn(const ACells: TAtlasWelcomeCells; const ANext, ATops: TArray<Integer>): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ACells) do
  begin
    if (ANext[mIndex] <= High(ACells[mIndex])) and ((Result < 0) or (ATops[mIndex] < ATops[Result])) then
    begin
      Result := mIndex;
    end;
  end;
  while (Result < High(ACells)) and (ACells[Result][ANext[Result]].Span > 1) and
    (ANext[Result + 1] <= High(ACells[Result + 1])) and (ATops[Result + 1] < ATops[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Höchstes Ende der Spalten AColumn bis AColumn + ASpan - 1.</summary>
function TopOf(const ATops: TArray<Integer>; AColumn, ASpan: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := ATops[AColumn];
  for mIndex := AColumn + 1 to AColumn + ASpan - 1 do
  begin
    if ATops[mIndex] > Result then
    begin
      Result := ATops[mIndex];
    end;
  end;
end;

function HeightOf(const AHeight: TAtlasWelcomeHeight; const AId: string; AWidth: Integer): Integer;
begin
  Result := 0;
  if Assigned(AHeight) then
  begin
    Result := Max(AHeight(AId, AWidth), 0);
  end;
end;

class function TAtlasWelcomeFlow.Place(const ACells: TAtlasWelcomeCells; AClientWidth, AGap, AMinWidth: Integer;
  const AHeight: TAtlasWelcomeHeight): TArray<TAtlasWelcomePlaced>;
var
  mCount, mWidth, mColumn, mIndex, mRemaining: Integer;
  mNext, mTops: TArray<Integer>;
  mCell: TAtlasWelcomeCell;
  mPlaced: TAtlasWelcomePlaced;
begin
  Result := nil;
  mCount := Length(ACells);
  mWidth := ColumnWidth(mCount, AClientWidth, AGap, AMinWidth);
  SetLength(mNext, mCount);
  SetLength(mTops, mCount);
  mRemaining := 0;
  for mColumn := 0 to mCount - 1 do
  begin
    mTops[mColumn] := AGap;
    Inc(mRemaining, Length(ACells[mColumn]));
  end;
  while mRemaining > 0 do
  begin
    mColumn := NextColumn(ACells, mNext, mTops);
    mCell := ACells[mColumn][mNext[mColumn]];
    Inc(mNext[mColumn]);
    Dec(mRemaining);
    mPlaced.Id := mCell.Id;
    mPlaced.Column := mColumn;
    mPlaced.Span := Clamp(mCell.Span, 1, mCount - mColumn);
    mPlaced.Left := AGap + mColumn * (mWidth + AGap);
    mPlaced.Top := TopOf(mTops, mColumn, mPlaced.Span);
    mPlaced.Width := mPlaced.Span * mWidth + (mPlaced.Span - 1) * AGap;
    mPlaced.Height := HeightOf(AHeight, mCell.Id, mPlaced.Width);
    for mIndex := mColumn to mColumn + mPlaced.Span - 1 do
    begin
      mTops[mIndex] := mPlaced.Top + mPlaced.Height + AGap;
    end;
    Result := Result + [mPlaced];
  end;
end;

class function TAtlasWelcomeFlow.DropTarget(const ACells: TAtlasWelcomeCells;
  const APlaced: TArray<TAtlasWelcomePlaced>; const AArea: TAtlasWelcomeArea; AX, AY: Integer;
  const ADragged: string): TAtlasWelcomeDrop;
var
  mCell: TAtlasWelcomeCell;
  mIndex: Integer;
begin
  Result.Before := '';
  Result.Column := ColumnAt(AX, Length(ACells), AArea.ClientWidth, AArea.Gap, AArea.MinWidth);
  if Result.Column > High(ACells) then
  begin
    Exit;
  end;
  for mCell in ACells[Result.Column] do
  begin
    mIndex := IndexOf(APlaced, mCell.Id);
    if not SameText(mCell.Id, ADragged) and (mIndex >= 0) and
      (AY < APlaced[mIndex].Top + APlaced[mIndex].Height div 2) then
    begin
      Result.Before := mCell.Id;
      Exit;
    end;
  end;
end;

class function TAtlasWelcomeFlow.InsertLine(const ACells: TAtlasWelcomeCells;
  const APlaced: TArray<TAtlasWelcomePlaced>; const AArea: TAtlasWelcomeArea; AColumn: Integer;
  const ABefore: string): TAtlasWelcomeInsertLine;
var
  mCount, mColumn, mIndex: Integer;
  mCell: TAtlasWelcomeCell;
begin
  mCount := Max(Length(ACells), 1);
  mColumn := Clamp(AColumn, 0, mCount - 1);
  Result.Left := ColumnLeft(mColumn, mCount, AArea.ClientWidth, AArea.Gap, AArea.MinWidth);
  Result.Width := ColumnWidth(mCount, AArea.ClientWidth, AArea.Gap, AArea.MinWidth);
  Result.Top := AArea.Gap div 2;
  mIndex := IndexOf(APlaced, ABefore);
  if (ABefore <> '') and (mIndex >= 0) then
  begin
    Result.Top := APlaced[mIndex].Top - AArea.Gap div 2;
    Exit;
  end;
  // Ans Ende: unter den letzten Bereich der Spalte.
  if mColumn > High(ACells) then
  begin
    Exit;
  end;
  for mCell in ACells[mColumn] do
  begin
    mIndex := IndexOf(APlaced, mCell.Id);
    if mIndex >= 0 then
    begin
      Result.Top := APlaced[mIndex].Top + APlaced[mIndex].Height + AArea.Gap div 2;
    end;
  end;
end;

class function TAtlasWelcomeFlow.ShortestColumn(const ACells: TAtlasWelcomeCells;
  const APlaced: TArray<TAtlasWelcomePlaced>; AGap: Integer): Integer;
var
  Bottoms: TArray<Integer>;
  Placed: TAtlasWelcomePlaced;
  Column: Integer;
begin
  Result := 0;
  if Length(ACells) = 0 then
  begin
    Exit;
  end;
  SetLength(Bottoms, Length(ACells));
  for Placed in APlaced do
  begin
    for Column := Placed.Column to Placed.Column + Placed.Span - 1 do
    begin
      if (Column <= High(Bottoms)) and (Placed.Top + Placed.Height + AGap > Bottoms[Column]) then
      begin
        Bottoms[Column] := Placed.Top + Placed.Height + AGap;
      end;
    end;
  end;
  for Column := 1 to High(Bottoms) do
  begin
    if Bottoms[Column] < Bottoms[Result] then
    begin
      Result := Column;
    end;
  end;
end;

end.
