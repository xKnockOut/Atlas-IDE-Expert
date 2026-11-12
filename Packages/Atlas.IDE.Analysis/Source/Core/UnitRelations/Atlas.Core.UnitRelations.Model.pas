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
// - SplitUsedBy trennt „Wird verwendet von“ nach dem Abschnitt des Eintrags
//   in der verwendenden Unit (#554): Verwender über interface-uses geben
//   eine Änderung weiter, solche über implementation-uses nicht.
// - Movable zählt die interface-Einträge, die nur im implementation-Teil
//   gebraucht werden (#554, „ins implementation-uses verschieben“).
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
    /// <summary>Steht im interface-uses, gebraucht wird die Unit nur im implementation-Teil (#554).</summary>
    OnlyImplementation: Boolean;
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
    /// <summary>Teilt AItems nach dem Abschnitt des Eintrags (interface/implementation), Reihenfolge bleibt.
    /// </summary>
    class procedure SplitUsedBy(const AItems: TAtlasUnitRelationList; out AInterface,
      AImplementation: TAtlasUnitRelationList); static;
    /// <summary>Einträge in AItems (ohne Kinder), die sich ins implementation-uses verschieben lassen.</summary>
    class function Movable(const AItems: TAtlasUnitRelationList): Integer; static;
  end;

  TAtlasUnitRelationsCommands = class
  public const
    cCommand = 'atlas.unitRelations';
    cMoveCommand = 'atlas.server.moveUses';
    cRemoveCommand = 'atlas.server.removeUses';
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
    cCapacity = 32;
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

uses
  Atlas.Text.Json;

function RelationsOf(AValue: TJSONValue): TAtlasUnitRelationList; forward;

function RelationOf(AObject: TJSONObject): TAtlasUnitRelation;
var
  mLocation: TJSONValue;
begin
  Result := Default(TAtlasUnitRelation);
  Result.Name := TJsonRead.Text(AObject, 'name');
  Result.FileName := TJsonRead.Text(AObject, 'file');
  Result.InInterface := SameText(TJsonRead.Text(AObject, 'section'), 'interface');
  Result.Library_ := TJsonRead.Flag(AObject, 'library');
  Result.Cycle := TJsonRead.Flag(AObject, 'cycle');
  Result.CyclePath := TJsonRead.Text(AObject, 'cyclePath');
  Result.Unused := TJsonRead.Flag(AObject, 'unused');
  Result.OnlyImplementation := TJsonRead.Flag(AObject, 'onlyImplementation');
  Result.Repeated := TJsonRead.Flag(AObject, 'repeated');
  Result.Line := -1;
  Result.Character := -1;
  mLocation := AObject.GetValue('location');
  if mLocation is TJSONObject then
  begin
    Result.LocationFile := TJsonRead.Text(TJSONObject(mLocation), 'file');
    Result.Line := TJsonRead.IntOr(TJSONObject(mLocation), 'line', -1);
    Result.Character := TJsonRead.IntOr(TJSONObject(mLocation), 'character', -1);
  end;
  Result.Children := RelationsOf(AObject.GetValue('children'));
end;

function RelationsOf(AValue: TJSONValue): TAtlasUnitRelationList;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    if mItem is TJSONObject then
    begin
      Result := Result + [RelationOf(TJSONObject(mItem))];
    end;
  end;
end;

{ TAtlasUnitRelationsModel }

class function TAtlasUnitRelationsModel.Parse(const AJson: string; out ARelations: TAtlasUnitRelations): Boolean;
var
  mValue, mGeneration: TJSONValue;
  mRoot: TJSONObject;
begin
  ARelations := Default(TAtlasUnitRelations);
  ARelations.Depth := 1;
  Result := False;
  if Trim(AJson) = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    if not (mRoot.GetValue('uses') is TJSONArray) then
    begin
      Exit;
    end;
    ARelations.Found := TJsonRead.Flag(mRoot, 'found');
    ARelations.UnitName := TJsonRead.Text(mRoot, 'unit');
    ARelations.FileName := TJsonRead.Text(mRoot, 'file');
    ARelations.RecompileCount := TJsonRead.IntOr(mRoot, 'recompileCount', 0);
    ARelations.DependencyCount := TJsonRead.IntOr(mRoot, 'dependencies', 0);
    ARelations.DependentCount := TJsonRead.IntOr(mRoot, 'dependents', 0);
    ARelations.InCycle := TJsonRead.Flag(mRoot, 'inCycle');
    ARelations.CyclePath := TJsonRead.Text(mRoot, 'cyclePath');
    ARelations.Uses_ := RelationsOf(mRoot.GetValue('uses'));
    ARelations.UsedBy := RelationsOf(mRoot.GetValue('usedBy'));
    ARelations.Depth := TJsonRead.IntOr(mRoot, 'depth', 1);
    mGeneration := mRoot.GetValue('generation');
    if mGeneration is TJSONNumber then
    begin
      ARelations.Generation := TJSONNumber(mGeneration).AsInt64;
    end;
    Result := True;
  finally
    mValue.Free;
  end;
end;

class function TAtlasUnitRelationsModel.Filter(const AItems: TAtlasUnitRelationList;
  const AText: string): TAtlasUnitRelationList;
var
  mIndex: Integer;
  mItem: TAtlasUnitRelation;
  mNeedle: string;
begin
  mNeedle := LowerCase(Trim(AText));
  if mNeedle = '' then
  begin
    Exit(AItems);
  end;
  Result := nil;
  for mIndex := 0 to High(AItems) do
  begin
    mItem := AItems[mIndex];
    mItem.Children := Filter(mItem.Children, mNeedle);
    if (Pos(mNeedle, LowerCase(mItem.Name)) > 0) or (mItem.Children <> nil) then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

class procedure TAtlasUnitRelationsModel.SplitLibrary(const AItems: TAtlasUnitRelationList; out AProject,
  ALibrary: TAtlasUnitRelationList);
var
  mItem: TAtlasUnitRelation;
begin
  AProject := nil;
  ALibrary := nil;
  for mItem in AItems do
  begin
    if mItem.Library_ then
    begin
      ALibrary := ALibrary + [mItem];
    end
    else
    begin
      AProject := AProject + [mItem];
    end;
  end;
end;

class procedure TAtlasUnitRelationsModel.SplitUsedBy(const AItems: TAtlasUnitRelationList; out AInterface,
  AImplementation: TAtlasUnitRelationList);
var
  mItem: TAtlasUnitRelation;
begin
  AInterface := nil;
  AImplementation := nil;
  for mItem in AItems do
  begin
    if mItem.InInterface then
    begin
      AInterface := AInterface + [mItem];
    end
    else
    begin
      AImplementation := AImplementation + [mItem];
    end;
  end;
end;

class function TAtlasUnitRelationsModel.Movable(const AItems: TAtlasUnitRelationList): Integer;
var
  mItem: TAtlasUnitRelation;
begin
  Result := 0;
  for mItem in AItems do
  begin
    if mItem.OnlyImplementation and mItem.InInterface then
    begin
      Inc(Result);
    end;
  end;
end;

{ TAtlasUnitRelationsCommands }

class function TAtlasUnitRelationsCommands.Arguments(const AUri: string; AAllLevels: Boolean): string;
var
  mItems: TJSONArray;
  mOption: TJSONObject;
begin
  mItems := TJSONArray.Create;
  try
    mItems.Add(AUri);
    mOption := TJSONObject.Create;
    if AAllLevels then
    begin
      mOption.AddPair('depth', TJSONNumber.Create(0));
    end
    else
    begin
      mOption.AddPair('depth', TJSONNumber.Create(1));
    end;
    mItems.AddElement(mOption);
    Result := mItems.ToJSON;
  finally
    mItems.Free;
  end;
end;

class function TAtlasUnitRelationsCommands.MoveArguments(const AUri, AUnit: string; AToInterface: Boolean): string;
var
  mItems: TJSONArray;
begin
  mItems := TJSONArray.Create;
  try
    mItems.Add(AUri);
    mItems.Add(AUnit);
    if AToInterface then
    begin
      mItems.Add('interface');
    end
    else
    begin
      mItems.Add('implementation');
    end;
    Result := mItems.ToJSON;
  finally
    mItems.Free;
  end;
end;

class function TAtlasUnitRelationsCommands.RemoveArguments(const AUri, AUnit: string): string;
var
  mItems: TJSONArray;
begin
  mItems := TJSONArray.Create;
  try
    mItems.Add(AUri);
    mItems.Add(AUnit);
    Result := mItems.ToJSON;
  finally
    mItems.Free;
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
  mKey: string;
begin
  if (AFileName = '') or (AJson = '') then
  begin
    Exit;
  end;
  mKey := KeyOf(AFileName, AAllLevels);
  FKeys.Remove(mKey);
  FKeys.Add(mKey);
  FAnswers.AddOrSetValue(mKey, AJson);
  while FKeys.Count > cCapacity do
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
