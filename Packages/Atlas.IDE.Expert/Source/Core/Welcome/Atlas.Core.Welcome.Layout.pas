unit Atlas.Core.Welcome.Layout;

// Atlas-Layout der Willkommensseite (#753), ohne VCL und Open Tools API:
// welche Bereiche in welcher Spalte und in welcher Reihenfolge stehen.
// TAtlasWelcomeLayout.Atlas ist die Anordnung aus dem Mockup (links
// Weiterarbeiten, Projekte, Projektverlauf; rechts Zustandskachel, Neu in
// Atlas, Atlas entdecken, Projekt einrichten). Arrange verteilt die
// eingeschalteten Bereiche auf eine gewünschte Spaltenzahl: Bereiche, die das
// Layout nicht kennt, kommen ans Ende ihrer Vorgabespalte; bei weniger Spalten
// rücken die rechten Spalten unter die linken (Fenster „Atlas-Start“: eine
// Spalte). Als JSON gespeichert, damit spätere Erweiterungen (#767: eigene
// Layouts) dieselbe Beschreibung nutzen.

interface

uses
  System.SysUtils,
  Atlas.Core.Welcome.Sections;

type
  TAtlasWelcomeSlot = record
    Id: string;
    /// <summary>Spalte ab 0.</summary>
    Column: Integer;
    class function Create(const AId: string; AColumn: Integer): TAtlasWelcomeSlot; static;
  end;

  TAtlasWelcomeLayout = record
  public const
    MinColumns = 1;
    MaxColumns = 3;
    AtlasName = 'Atlas';
  public
    Name: string;
    Columns: Integer;
    /// <summary>Plätze in Lesereihenfolge; innerhalb einer Spalte gilt diese Reihenfolge.</summary>
    Slots: TArray<TAtlasWelcomeSlot>;
    /// <summary>Anordnung aus dem Mockup (#753).</summary>
    class function Atlas: TAtlasWelcomeLayout; static;
    /// <summary>Platz von AId; False, wenn das Layout den Bereich nicht kennt.</summary>
    function SlotOf(const AId: string; out ASlot: TAtlasWelcomeSlot): Boolean;
    /// <summary>Dasselbe Layout mit AId ganz oben in der ersten Spalte (Karte „Neu in Atlas“ nach einem
    /// Update, #756); die übrigen Plätze behalten Spalte und Reihenfolge.</summary>
    function MovedToTop(const AId: string): TAtlasWelcomeLayout;
    /// <summary>Kennungen je Spalte (AColumns Spalten, mindestens eine) für die sichtbaren ASections.</summary>
    function Arrange(const ASections: TArray<TAtlasWelcomeSection>; AColumns: Integer): TArray<TArray<string>>;
    function ToJson: string;
    /// <summary>False bei ungültigem Text; ALayout ist dann Atlas.</summary>
    class function FromJson(const AText: string; out ALayout: TAtlasWelcomeLayout): Boolean; static;
    class function Same(const ALeft, ARight: TAtlasWelcomeLayout): Boolean; static;
  end;

implementation

uses
  System.JSON;

{ TAtlasWelcomeSlot }

class function TAtlasWelcomeSlot.Create(const AId: string; AColumn: Integer): TAtlasWelcomeSlot;
begin
  Result.Id := AId;
  Result.Column := AColumn;
end;

{ TAtlasWelcomeLayout }

class function TAtlasWelcomeLayout.Atlas: TAtlasWelcomeLayout;
begin
  Result.Name := AtlasName;
  Result.Columns := 2;
  Result.Slots := [
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.Continue, 0),
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.Projects, 0),
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.History, 0),
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.State, 1),
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.News, 1),
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.Discover, 1),
    TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.Setup, 1)];
end;

function TAtlasWelcomeLayout.SlotOf(const AId: string; out ASlot: TAtlasWelcomeSlot): Boolean;
var
  Slot: TAtlasWelcomeSlot;
begin
  for Slot in Slots do
    if SameText(Slot.Id, AId) then
    begin
      ASlot := Slot;
      Exit(True);
    end;
  ASlot := TAtlasWelcomeSlot.Create(AId, 0);
  Result := False;
end;

function TAtlasWelcomeLayout.MovedToTop(const AId: string): TAtlasWelcomeLayout;
var
  Slot: TAtlasWelcomeSlot;
begin
  Result.Name := Name;
  Result.Columns := Columns;
  Result.Slots := [TAtlasWelcomeSlot.Create(AId, 0)];
  for Slot in Slots do
    if not SameText(Slot.Id, AId) then
      Result.Slots := Result.Slots + [Slot];
end;

function Clamp(AValue, AMin, AMax: Integer): Integer;
begin
  Result := AValue;
  if Result < AMin then
    Result := AMin;
  if Result > AMax then
    Result := AMax;
end;

function TAtlasWelcomeLayout.Arrange(const ASections: TArray<TAtlasWelcomeSection>;
  AColumns: Integer): TArray<TArray<string>>;
var
  Wide: TArray<TArray<string>>;
  Width, Target, Column: Integer;
  Slot: TAtlasWelcomeSlot;
  Section: TAtlasWelcomeSection;
  Id: string;
  Known: Boolean;
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
        Wide[Column] := Wide[Column] + [Section.Id];
      end;
  for Section in ASections do
  begin
    Known := SlotOf(Section.Id, Slot);
    if Known then
      Continue;
    Column := Clamp(Ord(Section.Column), 0, Width - 1);
    Wide[Column] := Wide[Column] + [Section.Id];
  end;
  // … dann auf die gewünschte Zahl falten: überzählige Spalten rücken unter die letzte.
  Target := Clamp(AColumns, MinColumns, MaxColumns);
  SetLength(Result, Target);
  for Column := 0 to Width - 1 do
    for Id in Wide[Column] do
      if Column < Target then
        Result[Column] := Result[Column] + [Id]
      else
        Result[Target - 1] := Result[Target - 1] + [Id];
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
  Index, Column: Integer;
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
      if not (Field is TJSONString) then
        Exit;
      Id := Field.Value;
      Column := 0;
      Field := Item.GetValue('column');
      if Field is TJSONNumber then
        Column := Clamp(TJSONNumber(Field).AsInt, 0, MaxColumns - 1);
      ALayout.Slots := ALayout.Slots + [TAtlasWelcomeSlot.Create(Id, Column)];
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
      (ALeft.Slots[Index].Column <> ARight.Slots[Index].Column) then
      Exit(False);
end;

end.
