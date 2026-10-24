unit Atlas.Core.UnitRelations.Model;

// Fenster „Unit-Beziehungen“ (#593), Kern ohne VCL und OTA:
// - Parse liest die Antwort von atlas.unitRelations (Server:
//   TUnitRelationsBuilder.ToJson samt "generation" und "depth") in
//   Datensätze. Zeilen und Spalten bleiben 0-basiert wie im LSP, -1 = keine
//   Fundstelle.
// - Filter behält Einträge, deren Name den Text enthält, und die Vorfahren
//   solcher Einträge (im Baum über alle Ebenen); Groß-/Kleinschreibung zählt
//   nicht.
// - SplitLibrary trennt „Verwendet“ in Projekt- und Bibliotheks-Units (RTL,
//   VCL, Fremdkomponenten): Das Fenster zeigt die Bibliothek abgeblendet in
//   einer eingeklappten Gruppe.
// - TAtlasUnitRelationsCommands baut die Argumente von atlas.unitRelations,
//   atlas.server.moveUses und atlas.server.removeUses.
// - TAtlasUnitRelationsCache merkt sich die letzten Antworten je Datei und
//   Tiefe, damit ein Wechsel zurück sofort etwas zeigt; die Antwort des
//   Servers folgt im Hintergrund.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

type
  TAtlasUnitRelation = record
    Name: string;
    /// <summary>Datei der Unit; '' bei Units, die der Index nicht kennt.</summary>
    FileName: string;
    /// <summary>Eintrag im interface-uses (bei „Wird verwendet von“: in der verwendenden Unit).</summary>
    InInterface: Boolean;
    Library_: Boolean;
    /// <summary>Teil eines Zyklus über interface-uses (Compilerfehler F2047).</summary>
    Cycle: Boolean;
    CyclePath: string;
    Unused: Boolean;
    /// <summary>Steht im Baum schon weiter oben und wird hier nicht aufgeklappt.</summary>
    Repeated: Boolean;
    /// <summary>Fundstelle des uses-Eintrags; Line = -1 ohne.</summary>
    LocationFile: string;
    Line: Integer;
    Character: Integer;
    Children: TArray<TAtlasUnitRelation>;
  end;

  TAtlasUnitRelationList = TArray<TAtlasUnitRelation>;

  TAtlasUnitRelations = record
    /// <summary>Die Unit steht im Index (sonst nur „Verwendet“ aus dem Text).</summary>
    Found: Boolean;
    UnitName: string;
    FileName: string;
    RecompileCount: Integer;
    DependencyCount: Integer;
    DependentCount: Integer;
    InCycle: Boolean;
    CyclePath: string;
    Uses_: TAtlasUnitRelationList;
    UsedBy: TAtlasUnitRelationList;
    Generation: Int64;
    /// <summary>1 = direkt, 0 = alle Ebenen.</summary>
    Depth: Integer;
  end;

  TAtlasUnitRelationsModel = class
  public
    /// <summary>Antwort von atlas.unitRelations; False bei leerer oder unlesbarer Antwort.</summary>
    class function Parse(const AJson: string; out ARelations: TAtlasUnitRelations): Boolean; static;
    /// <summary>Einträge, deren Name AText enthält, samt ihren Vorfahren; AText = '' gibt alles zurück.</summary>
    class function Filter(const AItems: TAtlasUnitRelationList; const AText: string): TAtlasUnitRelationList;
      static;
    /// <summary>Teilt AItems in Projekt- und Bibliotheks-Units, Reihenfolge bleibt.</summary>
    class procedure SplitLibrary(const AItems: TAtlasUnitRelationList; out AProject,
      ALibrary: TAtlasUnitRelationList); static;
  end;

  TAtlasUnitRelationsCommands = class
  public const
    Command = 'atlas.unitRelations';
    MoveCommand = 'atlas.server.moveUses';
    RemoveCommand = 'atlas.server.removeUses';
  public
    /// <summary>[uri, {"depth": 1 | 0}] für atlas.unitRelations.</summary>
    class function Arguments(const AUri: string; AAllLevels: Boolean): string; static;
    /// <summary>[uri, Unit, "interface" | "implementation"] für atlas.server.moveUses.</summary>
    class function MoveArguments(const AUri, AUnit: string; AToInterface: Boolean): string; static;
    /// <summary>[uri, Unit] für atlas.server.removeUses.</summary>
    class function RemoveArguments(const AUri, AUnit: string): string; static;
  end;

  /// <summary>Letzte Antworten je Datei und Tiefe, die jüngste zuletzt; höchstens Capacity Einträge.</summary>
  TAtlasUnitRelationsCache = class
  public const
    Capacity = 32;
  private
    FKeys: TList<string>;
    FAnswers: TDictionary<string, string>;
    class function KeyOf(const AFileName: string; AAllLevels: Boolean): string; static;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Put(const AFileName: string; AAllLevels: Boolean; const AJson: string);
    function TryGet(const AFileName: string; AAllLevels: Boolean; out AJson: string): Boolean;
    procedure Clear;
    function Count: Integer;
  end;

implementation

function BoolOf(AObject: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Value := AObject.GetValue(AName);
  Result := (Value is TJSONBool) and TJSONBool(Value).AsBoolean;
end;

function IntOf(AObject: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  Value: TJSONValue;
begin
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
    Result := TJSONNumber(Value).AsInt
  else
    Result := ADefault;
end;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := Value.Value
  else
    Result := '';
end;

function RelationsOf(AValue: TJSONValue): TAtlasUnitRelationList; forward;

function RelationOf(AObject: TJSONObject): TAtlasUnitRelation;
var
  Location: TJSONValue;
begin
  Result := Default(TAtlasUnitRelation);
  Result.Name := TextOf(AObject, 'name');
  Result.FileName := TextOf(AObject, 'file');
  Result.InInterface := SameText(TextOf(AObject, 'section'), 'interface');
  Result.Library_ := BoolOf(AObject, 'library');
  Result.Cycle := BoolOf(AObject, 'cycle');
  Result.CyclePath := TextOf(AObject, 'cyclePath');
  Result.Unused := BoolOf(AObject, 'unused');
  Result.Repeated := BoolOf(AObject, 'repeated');
  Result.Line := -1;
  Result.Character := -1;
  Location := AObject.GetValue('location');
  if Location is TJSONObject then
  begin
    Result.LocationFile := TextOf(TJSONObject(Location), 'file');
    Result.Line := IntOf(TJSONObject(Location), 'line', -1);
    Result.Character := IntOf(TJSONObject(Location), 'character', -1);
  end;
  Result.Children := RelationsOf(AObject.GetValue('children'));
end;

function RelationsOf(AValue: TJSONValue): TAtlasUnitRelationList;
var
  Item: TJSONValue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
    Exit;
  for Item in TJSONArray(AValue) do
    if Item is TJSONObject then
      Result := Result + [RelationOf(TJSONObject(Item))];
end;

{ TAtlasUnitRelationsModel }

class function TAtlasUnitRelationsModel.Parse(const AJson: string; out ARelations: TAtlasUnitRelations): Boolean;
var
  Value, Generation: TJSONValue;
  Root: TJSONObject;
begin
  ARelations := Default(TAtlasUnitRelations);
  ARelations.Depth := 1;
  Result := False;
  if Trim(AJson) = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONObject) then
      Exit;
    Root := TJSONObject(Value);
    if not (Root.GetValue('uses') is TJSONArray) then
      Exit;
    ARelations.Found := BoolOf(Root, 'found');
    ARelations.UnitName := TextOf(Root, 'unit');
    ARelations.FileName := TextOf(Root, 'file');
    ARelations.RecompileCount := IntOf(Root, 'recompileCount', 0);
    ARelations.DependencyCount := IntOf(Root, 'dependencies', 0);
    ARelations.DependentCount := IntOf(Root, 'dependents', 0);
    ARelations.InCycle := BoolOf(Root, 'inCycle');
    ARelations.CyclePath := TextOf(Root, 'cyclePath');
    ARelations.Uses_ := RelationsOf(Root.GetValue('uses'));
    ARelations.UsedBy := RelationsOf(Root.GetValue('usedBy'));
    ARelations.Depth := IntOf(Root, 'depth', 1);
    Generation := Root.GetValue('generation');
    if Generation is TJSONNumber then
      ARelations.Generation := TJSONNumber(Generation).AsInt64;
    Result := True;
  finally
    Value.Free;
  end;
end;

class function TAtlasUnitRelationsModel.Filter(const AItems: TAtlasUnitRelationList;
  const AText: string): TAtlasUnitRelationList;
var
  Index: Integer;
  Item: TAtlasUnitRelation;
  Needle: string;
begin
  Needle := LowerCase(Trim(AText));
  if Needle = '' then
    Exit(AItems);
  Result := nil;
  for Index := 0 to High(AItems) do
  begin
    Item := AItems[Index];
    Item.Children := Filter(Item.Children, Needle);
    if (Pos(Needle, LowerCase(Item.Name)) > 0) or (Item.Children <> nil) then
      Result := Result + [Item];
  end;
end;

class procedure TAtlasUnitRelationsModel.SplitLibrary(const AItems: TAtlasUnitRelationList; out AProject,
  ALibrary: TAtlasUnitRelationList);
var
  Item: TAtlasUnitRelation;
begin
  AProject := nil;
  ALibrary := nil;
  for Item in AItems do
    if Item.Library_ then
      ALibrary := ALibrary + [Item]
    else
      AProject := AProject + [Item];
end;

{ TAtlasUnitRelationsCommands }

class function TAtlasUnitRelationsCommands.Arguments(const AUri: string; AAllLevels: Boolean): string;
var
  Items: TJSONArray;
  Option: TJSONObject;
begin
  Items := TJSONArray.Create;
  try
    Items.Add(AUri);
    Option := TJSONObject.Create;
    if AAllLevels then
      Option.AddPair('depth', TJSONNumber.Create(0))
    else
      Option.AddPair('depth', TJSONNumber.Create(1));
    Items.AddElement(Option);
    Result := Items.ToJSON;
  finally
    Items.Free;
  end;
end;

class function TAtlasUnitRelationsCommands.MoveArguments(const AUri, AUnit: string; AToInterface: Boolean): string;
var
  Items: TJSONArray;
begin
  Items := TJSONArray.Create;
  try
    Items.Add(AUri);
    Items.Add(AUnit);
    if AToInterface then
      Items.Add('interface')
    else
      Items.Add('implementation');
    Result := Items.ToJSON;
  finally
    Items.Free;
  end;
end;

class function TAtlasUnitRelationsCommands.RemoveArguments(const AUri, AUnit: string): string;
var
  Items: TJSONArray;
begin
  Items := TJSONArray.Create;
  try
    Items.Add(AUri);
    Items.Add(AUnit);
    Result := Items.ToJSON;
  finally
    Items.Free;
  end;
end;

{ TAtlasUnitRelationsCache }

constructor TAtlasUnitRelationsCache.Create;
begin
  inherited Create;
  FKeys := TList<string>.Create;
  FAnswers := TDictionary<string, string>.Create;
end;

destructor TAtlasUnitRelationsCache.Destroy;
begin
  FAnswers.Free;
  FKeys.Free;
  inherited Destroy;
end;

class function TAtlasUnitRelationsCache.KeyOf(const AFileName: string; AAllLevels: Boolean): string;
begin
  Result := LowerCase(AFileName) + '|' + BoolToStr(AAllLevels, True);
end;

procedure TAtlasUnitRelationsCache.Put(const AFileName: string; AAllLevels: Boolean; const AJson: string);
var
  Key: string;
begin
  if (AFileName = '') or (AJson = '') then
    Exit;
  Key := KeyOf(AFileName, AAllLevels);
  FKeys.Remove(Key);
  FKeys.Add(Key);
  FAnswers.AddOrSetValue(Key, AJson);
  while FKeys.Count > Capacity do
  begin
    FAnswers.Remove(FKeys[0]);
    FKeys.Delete(0);
  end;
end;

function TAtlasUnitRelationsCache.TryGet(const AFileName: string; AAllLevels: Boolean; out AJson: string): Boolean;
begin
  Result := FAnswers.TryGetValue(KeyOf(AFileName, AAllLevels), AJson);
end;

procedure TAtlasUnitRelationsCache.Clear;
begin
  FKeys.Clear;
  FAnswers.Clear;
end;

function TAtlasUnitRelationsCache.Count: Integer;
begin
  Result := FKeys.Count;
end;

end.
