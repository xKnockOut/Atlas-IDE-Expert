unit Atlas.Core.Debug.WatchStore;

// Ablage der Überwachungsliste des Fensters „Variablen“ (#853) mit Bindung an Klasse oder Unit (#2550), ohne IDE:
// höchstens Limit Ausdrücke je Projekt, jeder einmal, als JSON { "projects": { Projekt: [ … ] } }, jüngster
// zuerst. Ein Eintrag ohne Bindung ist ein String wie bisher, mit Bindung
// {"expression": "FFilter", "scope": "class:TAuftragsLauf"}. Dateien ohne scope bleiben lesbar; alle Einträge
// gelten dann überall. Ältere Atlas-Fassungen lesen aus einer neuen Datei nur die ungebundenen Einträge.

interface

uses
  System.Generics.Collections,
  Atlas.Core.Debug.WatchScopes;

type
  TAtlasWatchStore = class
  private
    FProjects: TDictionary<string, TAtlasScopedWatches>;
    FLimit: Integer;
    function ListOf(const AProject: string): TAtlasScopedWatches;
    procedure Store(const AProject: string; const AList: TAtlasScopedWatches);
    class function KeyOf(const AProject: string): string; static;
    class function IndexIn(const AList: TAtlasScopedWatches; const AExpression: string): Integer; static;
  public
    constructor Create(ALimit: Integer);
    destructor Destroy; override;
    /// <summary>AExpression (getrimmt) mit AScope vorn; schon da: unverändert. True, wenn er neu ist.</summary>
    function Add(const AProject, AExpression: string; const AScope: TAtlasWatchScope): Boolean;
    /// <summary>True, wenn es AExpression gab.</summary>
    function Remove(const AProject, AExpression: string): Boolean;
    /// <summary>Bindung von AExpression ändern; True, wenn sie sich geändert hat.</summary>
    function SetScope(const AProject, AExpression: string; const AScope: TAtlasWatchScope): Boolean;
    /// <summary>Ausdrücke von AProject in der Reihenfolge des Hinzufügens (ältester zuerst).</summary>
    function Items(const AProject: string): TAtlasScopedWatches;
    procedure Clear;
    /// <summary>Liest AText; False bei ungültigem JSON oder falscher Form (dann leer).</summary>
    function LoadFromText(const AText: string): Boolean;
    function ToText: string;
    property Limit: Integer read FLimit;
  end;

implementation

uses
  System.SysUtils,
  System.JSON;

/// <summary>Eintrag der Datei: String oder Objekt mit expression und scope; False bei allem anderen.</summary>
function ReadEntry(AValue: TJSONValue; out AWatch: TAtlasScopedWatch): Boolean;
var
  mExpression, mScope: TJSONValue;
begin
  AWatch := Default(TAtlasScopedWatch);
  // TJSONNumber erbt unter Delphi 12 von TJSONString.
  if (AValue is TJSONString) and not (AValue is TJSONNumber) then
  begin
    AWatch := TAtlasScopedWatch.Create(AValue.Value, TAtlasWatchScope.Everywhere);
  end
  else if AValue is TJSONObject then
  begin
    mExpression := TJSONObject(AValue).GetValue('expression');
    mScope := TJSONObject(AValue).GetValue('scope');
    if (mExpression is TJSONString) and not (mExpression is TJSONNumber) then
    begin
      AWatch.Expression := Trim(mExpression.Value);
    end;
    if (mScope is TJSONString) and not (mScope is TJSONNumber) then
    begin
      AWatch.Scope := TAtlasWatchScope.Parse(mScope.Value);
    end;
  end;
  Result := AWatch.Expression <> '';
end;

function WriteEntry(const AWatch: TAtlasScopedWatch): TJSONValue;
var
  mEntry: TJSONObject;
begin
  if AWatch.Scope.Kind = TAtlasWatchScopeKind.Everywhere then
  begin
    Result := TJSONString.Create(AWatch.Expression);
    Exit;
  end;
  mEntry := TJSONObject.Create;
  mEntry.AddPair('expression', AWatch.Expression);
  mEntry.AddPair('scope', AWatch.Scope.ToText);
  Result := mEntry;
end;

{ TAtlasWatchStore }

constructor TAtlasWatchStore.Create(ALimit: Integer);
begin
  inherited Create;
  FLimit := ALimit;
  if FLimit < 1 then
  begin
    FLimit := 1;
  end;
  FProjects := TDictionary<string, TAtlasScopedWatches>.Create;
end;

destructor TAtlasWatchStore.Destroy;
begin
  FreeAndNil(FProjects);
  inherited Destroy;
end;

class function TAtlasWatchStore.KeyOf(const AProject: string): string;
begin
  // Ohne Projekt eine eigene Liste; Pfade unter Windows ohne Groß-/Kleinschreibung.
  Result := LowerCase(Trim(AProject));
end;

class function TAtlasWatchStore.IndexIn(const AList: TAtlasScopedWatches; const AExpression: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AList) do
  begin
    if AList[mIndex].Expression = AExpression then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasWatchStore.ListOf(const AProject: string): TAtlasScopedWatches;
var
  mList: TAtlasScopedWatches;
begin
  // Eigene Variable: TryGetValue setzt den out-Wert auch ohne Schlüssel.
  Result := nil;
  if FProjects.TryGetValue(KeyOf(AProject), mList) then
  begin
    Result := Copy(mList);
  end;
end;

procedure TAtlasWatchStore.Store(const AProject: string; const AList: TAtlasScopedWatches);
begin
  if Length(AList) = 0 then
  begin
    FProjects.Remove(KeyOf(AProject));
  end
  else
  begin
    FProjects.AddOrSetValue(KeyOf(AProject), AList);
  end;
end;

function TAtlasWatchStore.Add(const AProject, AExpression: string; const AScope: TAtlasWatchScope): Boolean;
var
  mOld, mNew: TAtlasScopedWatches;
  mWatch: TAtlasScopedWatch;
begin
  mWatch := TAtlasScopedWatch.Create(AExpression, AScope);
  mOld := ListOf(AProject);
  Result := (mWatch.Expression <> '') and (IndexIn(mOld, mWatch.Expression) < 0);
  if not Result then
  begin
    Exit;
  end;
  // Jüngster vorn; über der Grenze fällt der älteste weg.
  mNew := TAtlasScopedWatches.Create(mWatch) + mOld;
  if Length(mNew) > FLimit then
  begin
    SetLength(mNew, FLimit);
  end;
  Store(AProject, mNew);
end;

function TAtlasWatchStore.Remove(const AProject, AExpression: string): Boolean;
var
  mList: TAtlasScopedWatches;
  mIndex: Integer;
begin
  mList := ListOf(AProject);
  mIndex := IndexIn(mList, Trim(AExpression));
  Result := mIndex >= 0;
  if Result then
  begin
    Delete(mList, mIndex, 1);
    Store(AProject, mList);
  end;
end;

function TAtlasWatchStore.SetScope(const AProject, AExpression: string; const AScope: TAtlasWatchScope): Boolean;
var
  mList: TAtlasScopedWatches;
  mIndex: Integer;
begin
  mList := ListOf(AProject);
  mIndex := IndexIn(mList, Trim(AExpression));
  Result := (mIndex >= 0) and not mList[mIndex].Scope.Same(AScope);
  if Result then
  begin
    mList[mIndex].Scope := AScope;
    Store(AProject, mList);
  end;
end;

function TAtlasWatchStore.Items(const AProject: string): TAtlasScopedWatches;
var
  mNewest: TAtlasScopedWatches;
  mIndex: Integer;
begin
  mNewest := ListOf(AProject);
  Result := nil;
  SetLength(Result, Length(mNewest));
  for mIndex := 0 to High(mNewest) do
  begin
    Result[High(mNewest) - mIndex] := mNewest[mIndex];
  end;
end;

procedure TAtlasWatchStore.Clear;
begin
  FProjects.Clear;
end;

function TAtlasWatchStore.LoadFromText(const AText: string): Boolean;
var
  mRoot, mProjects, mValue: TJSONValue;
  mPair: TJSONPair;
  mList: TAtlasScopedWatches;
  mWatch: TAtlasScopedWatch;
begin
  Clear;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    mProjects := nil;
    if mRoot is TJSONObject then
    begin
      mProjects := TJSONObject(mRoot).GetValue('projects');
    end;
    Result := mProjects is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    for mPair in TJSONObject(mProjects) do
    begin
      if not (mPair.JsonValue is TJSONArray) then
      begin
        Continue;
      end;
      mList := nil;
      for mValue in TJSONArray(mPair.JsonValue) do
      begin
        if ReadEntry(mValue, mWatch) and (IndexIn(mList, mWatch.Expression) < 0) and (Length(mList) < FLimit) then
        begin
          mList := mList + [mWatch];
        end;
      end;
      Store(mPair.JsonString.Value, mList);
    end;
  finally
    mRoot.Free;
  end;
end;

function TAtlasWatchStore.ToText: string;
var
  mRoot, mProjects: TJSONObject;
  mList: TJSONArray;
  mKeys: TArray<string>;
  mKey: string;
  mWatch: TAtlasScopedWatch;
begin
  mRoot := TJSONObject.Create;
  try
    mProjects := TJSONObject.Create;
    mRoot.AddPair('projects', mProjects);
    // Feste Reihenfolge: Die Datei ändert sich nur, wenn sich die Liste ändert.
    mKeys := FProjects.Keys.ToArray;
    TArray.Sort<string>(mKeys);
    for mKey in mKeys do
    begin
      mList := TJSONArray.Create;
      for mWatch in FProjects[mKey] do
      begin
        mList.AddElement(WriteEntry(mWatch));
      end;
      mProjects.AddPair(mKey, mList);
    end;
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

end.
