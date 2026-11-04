unit Atlas.Core.UnitSearch.State;

// Gemerkter Zustand des Fensters „Units suchen“ (#777), Teil ohne VCL:
//   - je Projektgruppe: eingeklappte Gruppen (je Gruppierung), gewählte
//     Herkunft und Art der Filterchips;
//   - fürs Fenster: Lage und Größe, Breite und Sichtbarkeit der Vorschau;
//   - nur für die Sitzung, nicht gespeichert: von Hand auf- oder zugeklappte
//     Abschnitte der Vorschau (#876).
// Gespeichert als JSON (Datei unter %LOCALAPPDATA%\Atlas, setzt die IDE-Schicht),
// gelesen und atomar geschrieben über TAtlasDataFile (Bericht N3): Eine
// unbrauchbare Datei liegt danach als .defekt daneben, eine gesperrte bleibt
// unverändert und wird nicht überschrieben.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.UnitSearch.Model,
  Atlas.Core.UnitSearch.Sections,
  Atlas.Core.Files.DataFile;

type
  TAtlasUnitSearchState = class
  private type
    TGroupState = record
      /// <summary>Eingeklappte Gruppen als "project:schlüssel" bzw. "folder:schlüssel" in Kleinschrift.</summary>
      Collapsed: TArray<string>;
      HasFilters: Boolean;
      Origins: TAtlasUnitOrigins;
      Kinds: TAtlasUnitKinds;
    end;
  private
    FGroups: TDictionary<string, TGroupState>;
    /// <summary>Vorhandene Datei, die LoadFromFile nicht lesen konnte: SaveToFile überschreibt sie nicht.</summary>
    FKept: string;
    function GroupState(const AGroupFile: string): TGroupState;
    function WindowJson: TJSONObject;
    procedure LoadWindow(AWindow: TJSONObject);
    procedure LoadGroups(AGroups: TJSONObject);
  public
    /// <summary>Lage des Fensters; Width = 0 = noch keine.</summary>
    Left, Top, Width, Height: Integer;
    /// <summary>Breite der Vorschau in Pixeln bei 96 dpi; 0 = Vorgabe.</summary>
    PreviewWidth: Integer;
    PreviewVisible: Boolean;
    /// <summary>Wahl von Hand je Abschnitt der Vorschau; nur in der Sitzung (#876).</summary>
    Sections: TAtlasSectionChoices;
    constructor Create;
    destructor Destroy; override;
    /// <summary>Eingeklappte Gruppen (Schlüssel in Kleinschrift) der Projektgruppe für AGrouping.</summary>
    function Collapsed(const AGroupFile: string; AGrouping: TAtlasUnitGrouping): TArray<string>;
    procedure SetCollapsed(const AGroupFile: string; AGrouping: TAtlasUnitGrouping; const AKeys: TArray<string>);
    /// <summary>Gemerkte Chips der Projektgruppe; False, wenn keine gemerkt sind.</summary>
    function Filters(const AGroupFile: string; out AOrigins: TAtlasUnitOrigins; out AKinds: TAtlasUnitKinds): Boolean;
    procedure SetFilters(const AGroupFile: string; AOrigins: TAtlasUnitOrigins; AKinds: TAtlasUnitKinds);
    function ToJson: string;
    /// <summary>Ersetzt den Zustand durch AText; False (und Vorgaben), wenn AText kein Objekt ist.</summary>
    function LoadJson(const AText: string): Boolean;
    /// <summary>Liest über TAtlasDataFile.Load; fehlt die Datei oder ist sie unbrauchbar, gelten die Vorgaben.
    /// Ergebnis Kept: Die Datei bleibt unverändert, SaveToFile schreibt sie nicht.</summary>
    function LoadFromFile(const AFileName: string): TAtlasDataLoad;
    /// <summary>Schreibt atomar; False, wenn LoadFromFile die vorhandene Datei nicht lesen konnte.</summary>
    function SaveToFile(const AFileName: string): Boolean;
  end;

implementation

const
  OriginTexts: array[TAtlasUnitOrigin] of string = ('active', 'group', 'searchPath', 'library');

function GroupingPrefix(AGrouping: TAtlasUnitGrouping): string;
begin
  Result := TAtlasUnitSearch.GroupingText(AGrouping) + ':';
end;

{ TAtlasUnitSearchState }

constructor TAtlasUnitSearchState.Create;
begin
  inherited Create;
  FGroups := TDictionary<string, TGroupState>.Create;
  PreviewVisible := True;
end;

destructor TAtlasUnitSearchState.Destroy;
begin
  FGroups.Free;
  inherited Destroy;
end;

function TAtlasUnitSearchState.GroupState(const AGroupFile: string): TGroupState;
begin
  if not FGroups.TryGetValue(LowerCase(AGroupFile), Result) then
  begin
    Result := Default(TGroupState);
  end;
end;

function TAtlasUnitSearchState.Collapsed(const AGroupFile: string; AGrouping: TAtlasUnitGrouping): TArray<string>;
var
  Item, Prefix: string;
begin
  Result := nil;
  Prefix := GroupingPrefix(AGrouping);
  for Item in GroupState(AGroupFile).Collapsed do
  begin
    if Item.StartsWith(Prefix) then
    begin
      Result := Result + [Copy(Item, Length(Prefix) + 1, MaxInt)];
    end;
  end;
end;

procedure TAtlasUnitSearchState.SetCollapsed(const AGroupFile: string; AGrouping: TAtlasUnitGrouping;
  const AKeys: TArray<string>);
var
  State: TGroupState;
  Kept: TArray<string>;
  Item, Prefix: string;
begin
  State := GroupState(AGroupFile);
  Prefix := GroupingPrefix(AGrouping);
  Kept := nil;
  for Item in State.Collapsed do
  begin
    if not Item.StartsWith(Prefix) then
    begin
      Kept := Kept + [Item];
    end;
  end;
  for Item in AKeys do
  begin
    Kept := Kept + [Prefix + LowerCase(Item)];
  end;
  State.Collapsed := Kept;
  FGroups.AddOrSetValue(LowerCase(AGroupFile), State);
end;

function TAtlasUnitSearchState.Filters(const AGroupFile: string; out AOrigins: TAtlasUnitOrigins;
  out AKinds: TAtlasUnitKinds): Boolean;
var
  State: TGroupState;
begin
  State := GroupState(AGroupFile);
  AOrigins := State.Origins;
  AKinds := State.Kinds;
  Result := State.HasFilters;
end;

procedure TAtlasUnitSearchState.SetFilters(const AGroupFile: string; AOrigins: TAtlasUnitOrigins;
  AKinds: TAtlasUnitKinds);
var
  State: TGroupState;
begin
  State := GroupState(AGroupFile);
  State.HasFilters := True;
  State.Origins := AOrigins;
  State.Kinds := AKinds;
  FGroups.AddOrSetValue(LowerCase(AGroupFile), State);
end;

function TextsToJson(const ATexts: TArray<string>): TJSONArray;
var
  mText: string;
begin
  Result := TJSONArray.Create;
  for mText in ATexts do
  begin
    Result.Add(mText);
  end;
end;

function OriginsToJson(AOrigins: TAtlasUnitOrigins): TJSONArray;
var
  mOrigin: TAtlasUnitOrigin;
begin
  Result := TJSONArray.Create;
  for mOrigin in AOrigins do
  begin
    Result.Add(OriginTexts[mOrigin]);
  end;
end;

function KindsToJson(AKinds: TAtlasUnitKinds): TJSONArray;
var
  mKind: TAtlasUnitKind;
begin
  Result := TJSONArray.Create;
  for mKind in AKinds do
  begin
    Result.Add(TAtlasUnitSearch.KindText(mKind));
  end;
end;

function GroupToJson(const AState: TAtlasUnitSearchState.TGroupState): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('collapsed', TextsToJson(AState.Collapsed));
  if AState.HasFilters then
  begin
    Result.AddPair('origins', OriginsToJson(AState.Origins));
    Result.AddPair('kinds', KindsToJson(AState.Kinds));
  end;
end;

function TAtlasUnitSearchState.WindowJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('left', TJSONNumber.Create(Left));
  Result.AddPair('top', TJSONNumber.Create(Top));
  Result.AddPair('width', TJSONNumber.Create(Width));
  Result.AddPair('height', TJSONNumber.Create(Height));
  Result.AddPair('previewWidth', TJSONNumber.Create(PreviewWidth));
  Result.AddPair('previewVisible', TJSONBool.Create(PreviewVisible));
end;

function TAtlasUnitSearchState.ToJson: string;
var
  mRoot, mGroups: TJSONObject;
  mPair: TPair<string, TGroupState>;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('window', WindowJson);
    mGroups := TJSONObject.Create;
    for mPair in FGroups do
    begin
      mGroups.AddPair(mPair.Key, GroupToJson(mPair.Value));
    end;
    mRoot.AddPair('groups', mGroups);
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

function OriginsFromJson(AList: TJSONArray): TAtlasUnitOrigins;
var
  mValue: TJSONValue;
  mOrigin: TAtlasUnitOrigin;
begin
  Result := [];
  for mValue in AList do
  begin
    for mOrigin := Low(TAtlasUnitOrigin) to High(TAtlasUnitOrigin) do
    begin
      if SameText(mValue.Value, OriginTexts[mOrigin]) then
      begin
        Include(Result, mOrigin);
      end;
    end;
  end;
end;

function KindsFromJson(AList: TJSONArray): TAtlasUnitKinds;
var
  mValue: TJSONValue;
  mKind: TAtlasUnitKind;
begin
  Result := [];
  for mValue in AList do
  begin
    if TAtlasUnitSearch.KindFromText(mValue.Value, mKind) then
    begin
      Include(Result, mKind);
    end;
  end;
end;

function GroupFromJson(AItem: TJSONObject): TAtlasUnitSearchState.TGroupState;
var
  mList: TJSONArray;
  mValue: TJSONValue;
begin
  Result := Default(TAtlasUnitSearchState.TGroupState);
  if AItem.TryGetValue<TJSONArray>('collapsed', mList) then
  begin
    for mValue in mList do
    begin
      Result.Collapsed := Result.Collapsed + [LowerCase(mValue.Value)];
    end;
  end;
  if AItem.TryGetValue<TJSONArray>('origins', mList) then
  begin
    Result.HasFilters := True;
    Result.Origins := OriginsFromJson(mList);
  end;
  if AItem.TryGetValue<TJSONArray>('kinds', mList) then
  begin
    Result.Kinds := KindsFromJson(mList);
  end;
end;

procedure TAtlasUnitSearchState.LoadWindow(AWindow: TJSONObject);
begin
  AWindow.TryGetValue<Integer>('left', Left);
  AWindow.TryGetValue<Integer>('top', Top);
  AWindow.TryGetValue<Integer>('width', Width);
  AWindow.TryGetValue<Integer>('height', Height);
  AWindow.TryGetValue<Integer>('previewWidth', PreviewWidth);
  AWindow.TryGetValue<Boolean>('previewVisible', PreviewVisible);
end;

procedure TAtlasUnitSearchState.LoadGroups(AGroups: TJSONObject);
var
  mPair: TJSONPair;
begin
  for mPair in AGroups do
  begin
    if mPair.JsonValue is TJSONObject then
    begin
      FGroups.AddOrSetValue(LowerCase(mPair.JsonString.Value), GroupFromJson(TJSONObject(mPair.JsonValue)));
    end;
  end;
end;

function TAtlasUnitSearchState.LoadJson(const AText: string): Boolean;
var
  mRoot: TJSONValue;
  mSection: TJSONObject;
begin
  FGroups.Clear;
  Left := 0;
  Top := 0;
  Width := 0;
  Height := 0;
  PreviewWidth := 0;
  PreviewVisible := True;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    Result := mRoot is TJSONObject;
    if Result and TJSONObject(mRoot).TryGetValue<TJSONObject>('window', mSection) then
    begin
      LoadWindow(mSection);
    end;
    if Result and TJSONObject(mRoot).TryGetValue<TJSONObject>('groups', mSection) then
    begin
      LoadGroups(mSection);
    end;
  finally
    mRoot.Free;
  end;
end;

function TAtlasUnitSearchState.LoadFromFile(const AFileName: string): TAtlasDataLoad;
begin
  FKept := '';
  Result := TAtlasDataFile.Load(AFileName, 'Zustand von Units suchen',
    function(const AText: string): Boolean
    begin
      Result := LoadJson(AText);
    end);
  if not TAtlasDataFile.Writable(Result) then
  begin
    FKept := AFileName;
  end;
  // Ohne gelesene Datei gelten die Vorgaben.
  if Result <> TAtlasDataLoad.Loaded then
  begin
    LoadJson('');
  end;
end;

function TAtlasUnitSearchState.SaveToFile(const AFileName: string): Boolean;
begin
  Result := not SameFileName(AFileName, FKept);
  if Result then
  begin
    TAtlasDataFile.Write(AFileName, ToJson);
  end;
end;

end.
