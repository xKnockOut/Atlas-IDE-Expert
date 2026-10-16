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
    class procedure DropTarget(const ACells: TAtlasWelcomeCells; const APlaced: TArray<TAtlasWelcomePlaced>;
      AClientWidth, AGap, AMinWidth, AX, AY: Integer; const ADragged: string; out AColumn: Integer;
      out ABefore: string); static;
    /// <summary>Einfügelinie für (AColumn, ABefore): oberhalb von ABefore bzw. unter dem letzten Bereich der
    /// Spalte; ATop ist die Mitte der Lücke.</summary>
    class procedure InsertLine(const ACells: TAtlasWelcomeCells; const APlaced: TArray<TAtlasWelcomePlaced>;
      AClientWidth, AGap, AMinWidth, AColumn: Integer; const ABefore: string; out ALeft, ATop, AWidth: Integer);
      static;
    /// <summary>Spalte mit dem tiefsten freien Platz oben (kleinstes Ende); Gleichstand: linke.</summary>
    class function ShortestColumn(const ACells: TAtlasWelcomeCells; const APlaced: TArray<TAtlasWelcomePlaced>;
      AGap: Integer): Integer; static;
    /// <summary>Index von AId in APlaced; -1 ohne.</summary>
    class function IndexOf(const APlaced: TArray<TAtlasWelcomePlaced>; const AId: string): Integer; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON;

function Clamp(AValue, AMin, AMax: Integer): Integer;
begin
  Result := AValue;
  if Result < AMin then
    Result := AMin;
  if Result > AMax then
    Result := AMax;
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
  // Meine Issues (#765) und Hilfe (#766) am Ende der rechten Spalte.
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
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.Help, 1)];
end;

function TAtlasWelcomeLayout.IndexOf(const AId: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Slots) do
    if SameText(Slots[Index].Id, AId) then
      Exit(Index);
  Result := -1;
end;

function TAtlasWelcomeLayout.SlotOf(const AId: string; out ASlot: TAtlasWelcomeSlot): Boolean;
var
  Index: Integer;
begin
  Index := IndexOf(AId);
  Result := Index >= 0;
  if Result then
    ASlot := Slots[Index]
  else
    ASlot := TAtlasWelcomeSlot.Create(AId, 0);
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
    if not SameText(Slot.Id, AId) then
      Result.Slots := Result.Slots + [Slot];
end;

function TAtlasWelcomeLayout.Cells(const ASections: TArray<TAtlasWelcomeSection>;
  AColumns: Integer): TAtlasWelcomeCells;
var
  Wide: TAtlasWelcomeCells;
  Width, Target, Column: Integer;
  Slot: TAtlasWelcomeSlot;
  Section: TAtlasWelcomeSection;
  Cell: TAtlasWelcomeCell;
begin
  // Ergebnis leeren: Ein dynamisches Array als Result kann beim Eintritt Inhalt des Ziels tragen.
  Result := nil;
  // Zuerst in der Breite des Layouts verteilen (mindestens zwei Spalten für die Vorgabespalten) …
  Width := Clamp(Columns, MinColumns, MaxColumns);
  if Width < 2 then
    Width := 2;
  SetLength(Wide, Width);
  for Slot in Slots do
    for Section in ASections do
      if SameText(Section.Id, Slot.Id) then
      begin
        Column := Clamp(Slot.Column, 0, Width - 1);
        Wide[Column] := Wide[Column] + [TAtlasWelcomeCell.Create(Section.Id, Clamp(Slot.Width, MinWidth, MaxWidth))];
        Break;
      end;
  for Section in ASections do
  begin
    if IndexOf(Section.Id) >= 0 then
      Continue;
    Column := Clamp(Ord(Section.Column), 0, Width - 1);
    Wide[Column] := Wide[Column] + [TAtlasWelcomeCell.Create(Section.Id, 1)];
  end;
  // … dann auf die gewünschte Zahl falten: überzählige Spalten rücken unter die letzte.
  Target := Clamp(AColumns, MinColumns, MaxColumns);
  SetLength(Result, Target);
  for Column := 0 to Width - 1 do
    for Cell in Wide[Column] do
      if Column < Target then
        Result[Column] := Result[Column] + [TAtlasWelcomeCell.Create(Cell.Id, Clamp(Cell.Span, 1, Target - Column))]
      else
        Result[Target - 1] := Result[Target - 1] + [TAtlasWelcomeCell.Create(Cell.Id, 1)];
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
    for Cell in Grid[Column] do
      Result[Column] := Result[Column] + [Cell.Id];
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
    if not SameText(Slots[Index].Id, AId) then
      Result.Slots := Result.Slots + [Slots[Index]];
  Before := -1;
  if (ABeforeId <> '') and not SameText(ABeforeId, AId) then
    Before := Result.IndexOf(ABeforeId);
  if Before < 0 then
    // Innerhalb einer Spalte gilt die Reihenfolge der Liste: hinten angehängt = letzter der Spalte.
    Result.Slots := Result.Slots + [Moved]
  else
    Insert(Moved, Result.Slots, Before);
end;

function TAtlasWelcomeLayout.MovedBy(const AId: string; ADirection: TAtlasWelcomeMove;
  const ASections: TArray<TAtlasWelcomeSection>; out ALayout: TAtlasWelcomeLayout): Boolean;
var
  Grid: TAtlasWelcomeCells;
  Column, Row, Index, Target: Integer;
  Before: string;
begin
  ALayout := Self;
  Grid := Cells(ASections, Columns);
  Column := -1;
  Row := -1;
  for Index := 0 to High(Grid) do
    for Target := 0 to High(Grid[Index]) do
      if SameText(Grid[Index][Target].Id, AId) then
      begin
        Column := Index;
        Row := Target;
      end;
  Result := Column >= 0;
  if not Result then
    Exit;
  Before := '';
  case ADirection of
    TAtlasWelcomeMove.Up:
      begin
        if Row = 0 then
          Exit(False);
        Target := Column;
        Before := Grid[Column][Row - 1].Id;
      end;
    TAtlasWelcomeMove.Down:
      begin
        if Row = High(Grid[Column]) then
          Exit(False);
        Target := Column;
        if Row + 2 <= High(Grid[Column]) then
          Before := Grid[Column][Row + 2].Id;
      end;
    TAtlasWelcomeMove.Left:
      begin
        if Column = 0 then
          Exit(False);
        Target := Column - 1;
        if Row <= High(Grid[Target]) then
          Before := Grid[Target][Row].Id;
      end;
  else
    begin
      if Column >= High(Grid) then
        Exit(False);
      Target := Column + 1;
      if Row <= High(Grid[Target]) then
        Before := Grid[Target][Row].Id;
    end;
  end;
  ALayout := MovedTo(AId, Target, Before);
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
    Result := Clamp(Slot.Width, MinWidth, MaxWidth);
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
      Continue;
    Weight := 1;
    if Assigned(AWeight) then
      Weight := AWeight(Slot.Id);
    Column := Clamp(Slot.Column, 0, Count - 1);
    for Index := Column to Clamp(Column + Slot.Width - 1, 0, Count - 1) do
      Inc(Load[Index], Weight);
  end;
  Result := 0;
  for Column := 1 to Count - 1 do
    if Load[Column] < Load[Result] then
      Result := Column;
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
      Continue;
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

class function TAtlasWelcomeLayout.FromJson(const AText: string; out ALayout: TAtlasWelcomeLayout): Boolean;
var
  Value, Field: TJSONValue;
  Root, Item: TJSONObject;
  List: TJSONArray;
  Index, Column, Width: Integer;
  Visible: Boolean;
  Id: string;
begin
  ALayout := Atlas;
  Result := False;
  Value := TJSONObject.ParseJSONValue(AText);
  try
    if not (Value is TJSONObject) then
      Exit;
    Root := TJSONObject(Value);
    Field := Root.GetValue('slots');
    if not (Field is TJSONArray) then
      Exit;
    List := TJSONArray(Field);
    ALayout.Slots := nil;
    for Index := 0 to List.Count - 1 do
    begin
      if not (List.Items[Index] is TJSONObject) then
        Exit;
      Item := TJSONObject(List.Items[Index]);
      Field := Item.GetValue('id');
      if not (Field is TJSONString) or (Trim(Field.Value) = '') then
        Exit;
      Id := Trim(Field.Value);
      // Doppelte Kennung: der erste Platz gilt.
      if ALayout.IndexOf(Id) >= 0 then
        Continue;
      Column := 0;
      Field := Item.GetValue('column');
      if Field is TJSONNumber then
        Column := Clamp(TJSONNumber(Field).AsInt, 0, MaxColumns - 1);
      Width := 1;
      Field := Item.GetValue('width');
      if Field is TJSONNumber then
        Width := Clamp(TJSONNumber(Field).AsInt, MinWidth, MaxWidth);
      Visible := True;
      Field := Item.GetValue('visible');
      if Field is TJSONBool then
        Visible := TJSONBool(Field).AsBoolean;
      ALayout.Slots := ALayout.Slots + [TAtlasWelcomeSlot.Create(Id, Column, Width, Visible)];
    end;
    Field := Root.GetValue('name');
    if Field is TJSONString then
      ALayout.Name := Field.Value;
    Field := Root.GetValue('columns');
    if Field is TJSONNumber then
      ALayout.Columns := Clamp(TJSONNumber(Field).AsInt, MinColumns, MaxColumns);
    Result := True;
  finally
    Value.Free;
    if not Result then
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
    Exit;
  for Index := 0 to High(ALeft.Slots) do
    if not SameText(ALeft.Slots[Index].Id, ARight.Slots[Index].Id) or
      (ALeft.Slots[Index].Column <> ARight.Slots[Index].Column) or
      (ALeft.Slots[Index].Width <> ARight.Slots[Index].Width) or
      (ALeft.Slots[Index].Visible <> ARight.Slots[Index].Visible) then
      Exit(False);
end;

{ TAtlasWelcomeFlow }

class function TAtlasWelcomeFlow.ColumnWidth(ACount, AClientWidth, AGap, AMinWidth: Integer): Integer;
begin
  if ACount < 1 then
    ACount := 1;
  Result := (AClientWidth - (ACount + 1) * AGap) div ACount;
  if Result < AMinWidth then
    Result := AMinWidth;
end;

class function TAtlasWelcomeFlow.FitColumns(AWanted, AClientWidth, AGap, AMinWidth: Integer): Integer;
begin
  Result := Clamp(AWanted, TAtlasWelcomeLayout.MinColumns, TAtlasWelcomeLayout.MaxColumns);
  while (Result > 1) and ((AClientWidth - (Result + 1) * AGap) div Result < AMinWidth) do
    Dec(Result);
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
    Exit(0);
  Width := ColumnWidth(ACount, AClientWidth, AGap, AMinWidth);
  // Die Lücke links einer Spalte gehört zu ihr.
  Result := Clamp((AX - AGap div 2) div (Width + AGap), 0, ACount - 1);
end;

class function TAtlasWelcomeFlow.IndexOf(const APlaced: TArray<TAtlasWelcomePlaced>; const AId: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(APlaced) do
    if SameText(APlaced[Index].Id, AId) then
      Exit(Index);
  Result := -1;
end;

class function TAtlasWelcomeFlow.Place(const ACells: TAtlasWelcomeCells; AClientWidth, AGap, AMinWidth: Integer;
  const AHeight: TAtlasWelcomeHeight): TArray<TAtlasWelcomePlaced>;
var
  Count, Width, Column, Index, Span, Top, Remaining: Integer;
  Next, Tops: TArray<Integer>;
  Cell: TAtlasWelcomeCell;
  Placed: TAtlasWelcomePlaced;
begin
  Result := nil;
  Count := Length(ACells);
  if Count = 0 then
    Exit;
  Width := ColumnWidth(Count, AClientWidth, AGap, AMinWidth);
  SetLength(Next, Count);
  SetLength(Tops, Count);
  Remaining := 0;
  for Column := 0 to Count - 1 do
  begin
    Tops[Column] := AGap;
    Inc(Remaining, Length(ACells[Column]));
  end;
  while Remaining > 0 do
  begin
    // Spalte mit dem höchsten Ende, die noch Bereiche hat.
    Column := -1;
    for Index := 0 to Count - 1 do
      if (Next[Index] <= High(ACells[Index])) and ((Column < 0) or (Tops[Index] < Tops[Column])) then
        Column := Index;
    // Wartet ein zweispaltiger Bereich, füllt erst die Nachbarspalte bis auf seine Höhe auf.
    while (Column < Count - 1) and (ACells[Column][Next[Column]].Span > 1) and
      (Next[Column + 1] <= High(ACells[Column + 1])) and (Tops[Column + 1] < Tops[Column]) do
      Inc(Column);
    Cell := ACells[Column][Next[Column]];
    Inc(Next[Column]);
    Dec(Remaining);
    Span := Clamp(Cell.Span, 1, Count - Column);
    Top := Tops[Column];
    for Index := Column + 1 to Column + Span - 1 do
      if Tops[Index] > Top then
        Top := Tops[Index];
    Placed.Id := Cell.Id;
    Placed.Column := Column;
    Placed.Span := Span;
    Placed.Left := AGap + Column * (Width + AGap);
    Placed.Top := Top;
    Placed.Width := Span * Width + (Span - 1) * AGap;
    Placed.Height := 0;
    if Assigned(AHeight) then
      Placed.Height := AHeight(Cell.Id, Placed.Width);
    if Placed.Height < 0 then
      Placed.Height := 0;
    for Index := Column to Column + Span - 1 do
      Tops[Index] := Top + Placed.Height + AGap;
    Result := Result + [Placed];
  end;
end;

class procedure TAtlasWelcomeFlow.DropTarget(const ACells: TAtlasWelcomeCells;
  const APlaced: TArray<TAtlasWelcomePlaced>; AClientWidth, AGap, AMinWidth, AX, AY: Integer;
  const ADragged: string; out AColumn: Integer; out ABefore: string);
var
  Cell: TAtlasWelcomeCell;
  Index: Integer;
begin
  ABefore := '';
  AColumn := ColumnAt(AX, Length(ACells), AClientWidth, AGap, AMinWidth);
  if AColumn > High(ACells) then
    Exit;
  for Cell in ACells[AColumn] do
  begin
    if SameText(Cell.Id, ADragged) then
      Continue;
    Index := IndexOf(APlaced, Cell.Id);
    if (Index >= 0) and (AY < APlaced[Index].Top + APlaced[Index].Height div 2) then
    begin
      ABefore := Cell.Id;
      Exit;
    end;
  end;
end;

class procedure TAtlasWelcomeFlow.InsertLine(const ACells: TAtlasWelcomeCells;
  const APlaced: TArray<TAtlasWelcomePlaced>; AClientWidth, AGap, AMinWidth, AColumn: Integer;
  const ABefore: string; out ALeft, ATop, AWidth: Integer);
var
  Count, Index: Integer;
  Cell: TAtlasWelcomeCell;
begin
  Count := Length(ACells);
  if Count < 1 then
    Count := 1;
  AColumn := Clamp(AColumn, 0, Count - 1);
  ALeft := ColumnLeft(AColumn, Count, AClientWidth, AGap, AMinWidth);
  AWidth := ColumnWidth(Count, AClientWidth, AGap, AMinWidth);
  ATop := AGap div 2;
  Index := IndexOf(APlaced, ABefore);
  if (ABefore <> '') and (Index >= 0) then
  begin
    ATop := APlaced[Index].Top - AGap div 2;
    Exit;
  end;
  // Ans Ende: unter den letzten Bereich der Spalte.
  if AColumn <= High(ACells) then
    for Cell in ACells[AColumn] do
    begin
      Index := IndexOf(APlaced, Cell.Id);
      if Index >= 0 then
        ATop := APlaced[Index].Top + APlaced[Index].Height + AGap div 2;
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
    Exit;
  SetLength(Bottoms, Length(ACells));
  for Placed in APlaced do
    for Column := Placed.Column to Placed.Column + Placed.Span - 1 do
      if (Column <= High(Bottoms)) and (Placed.Top + Placed.Height + AGap > Bottoms[Column]) then
        Bottoms[Column] := Placed.Top + Placed.Height + AGap;
  for Column := 1 to High(Bottoms) do
    if Bottoms[Column] < Bottoms[Result] then
      Result := Column;
end;

end.
