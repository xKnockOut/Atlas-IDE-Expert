unit Atlas.Core.UnitSearch.State;

// Gemerkter Zustand des Fensters „Units suchen“ (#777), Teil ohne VCL:
//   - je Projektgruppe: eingeklappte Gruppen (je Gruppierung), gewählte
//     Herkunft und Art der Filterchips;
//   - fürs Fenster: Lage und Größe, Breite und Sichtbarkeit der Vorschau.
// Gespeichert als JSON (Datei unter %LOCALAPPDATA%\Atlas, setzt die IDE-Schicht).

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.UnitSearch.Model,
  Atlas.Core.UnitSearch.Sections;

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
    function GroupState(const AGroupFile: string): TGroupState;
  public
    /// <summary>Lage des Fensters; Width = 0 = noch keine.</summary>
    Left, Top, Width, Height: Integer;
    /// <summary>Breite der Vorschau in Pixeln bei 96 dpi; 0 = Vorgabe.</summary>
    PreviewWidth: Integer;
    PreviewVisible: Boolean;
    /// <summary>Wahl je Abschnitt des Detail-Panels (#876); nur für die Sitzung, nicht im JSON.</summary>
    Sections: TAtlasUnitSectionChoices;
    constructor Create;
    destructor Destroy; override;
    /// <summary>Eingeklappte Gruppen (Schlüssel in Kleinschrift) der Projektgruppe für AGrouping.</summary>
    function Collapsed(const AGroupFile: string; AGrouping: TAtlasUnitGrouping): TArray<string>;
    procedure SetCollapsed(const AGroupFile: string; AGrouping: TAtlasUnitGrouping; const AKeys: TArray<string>);
    /// <summary>Gemerkte Chips der Projektgruppe; False, wenn keine gemerkt sind.</summary>
    function Filters(const AGroupFile: string; out AOrigins: TAtlasUnitOrigins; out AKinds: TAtlasUnitKinds): Boolean;
    procedure SetFilters(const AGroupFile: string; AOrigins: TAtlasUnitOrigins; AKinds: TAtlasUnitKinds);
    function ToJson: string;
    procedure LoadJson(const AText: string);
    procedure LoadFromFile(const AFileName: string);
    procedure SaveToFile(const AFileName: string);
  end;

implementation

uses
  System.IOUtils;

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
    Result := Default(TGroupState);
end;

function TAtlasUnitSearchState.Collapsed(const AGroupFile: string; AGrouping: TAtlasUnitGrouping): TArray<string>;
var
  Item, Prefix: string;
begin
  Result := nil;
  Prefix := GroupingPrefix(AGrouping);
  for Item in GroupState(AGroupFile).Collapsed do
    if Item.StartsWith(Prefix) then
      Result := Result + [Copy(Item, Length(Prefix) + 1, MaxInt)];
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
    if not Item.StartsWith(Prefix) then
      Kept := Kept + [Item];
  for Item in AKeys do
    Kept := Kept + [Prefix + LowerCase(Item)];
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

function TAtlasUnitSearchState.ToJson: string;
var
  Root, Groups, Item, Window: TJSONObject;
  List: TJSONArray;
  Pair: TPair<string, TGroupState>;
  Value: string;
  Origin: TAtlasUnitOrigin;
  Kind: TAtlasUnitKind;
begin
  Root := TJSONObject.Create;
  try
    Window := TJSONObject.Create;
    Window.AddPair('left', TJSONNumber.Create(Left));
    Window.AddPair('top', TJSONNumber.Create(Top));
    Window.AddPair('width', TJSONNumber.Create(Width));
    Window.AddPair('height', TJSONNumber.Create(Height));
    Window.AddPair('previewWidth', TJSONNumber.Create(PreviewWidth));
    Window.AddPair('previewVisible', TJSONBool.Create(PreviewVisible));
    Root.AddPair('window', Window);
    Groups := TJSONObject.Create;
    for Pair in FGroups do
    begin
      Item := TJSONObject.Create;
      List := TJSONArray.Create;
      for Value in Pair.Value.Collapsed do
        List.Add(Value);
      Item.AddPair('collapsed', List);
      if Pair.Value.HasFilters then
      begin
        List := TJSONArray.Create;
        for Origin := Low(TAtlasUnitOrigin) to High(TAtlasUnitOrigin) do
          if Origin in Pair.Value.Origins then
            List.Add(OriginTexts[Origin]);
        Item.AddPair('origins', List);
        List := TJSONArray.Create;
        for Kind := Low(TAtlasUnitKind) to High(TAtlasUnitKind) do
          if Kind in Pair.Value.Kinds then
            List.Add(TAtlasUnitSearch.KindText(Kind));
        Item.AddPair('kinds', List);
      end;
      Groups.AddPair(Pair.Key, Item);
    end;
    Root.AddPair('groups', Groups);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

procedure TAtlasUnitSearchState.LoadJson(const AText: string);
var
  Root: TJSONValue;
  Window, Groups, Item: TJSONObject;
  List: TJSONArray;
  Pair: TJSONPair;
  Value: TJSONValue;
  State: TGroupState;
  Origin: TAtlasUnitOrigin;
  Kind: TAtlasUnitKind;
begin
  FGroups.Clear;
  Left := 0;
  Top := 0;
  Width := 0;
  Height := 0;
  PreviewWidth := 0;
  PreviewVisible := True;
  Root := TJSONObject.ParseJSONValue(AText);
  try
    if not (Root is TJSONObject) then
      Exit;
    if TJSONObject(Root).TryGetValue<TJSONObject>('window', Window) then
    begin
      Window.TryGetValue<Integer>('left', Left);
      Window.TryGetValue<Integer>('top', Top);
      Window.TryGetValue<Integer>('width', Width);
      Window.TryGetValue<Integer>('height', Height);
      Window.TryGetValue<Integer>('previewWidth', PreviewWidth);
      Window.TryGetValue<Boolean>('previewVisible', PreviewVisible);
    end;
    if not TJSONObject(Root).TryGetValue<TJSONObject>('groups', Groups) then
      Exit;
    for Pair in Groups do
    begin
      if not (Pair.JsonValue is TJSONObject) then
        Continue;
      Item := TJSONObject(Pair.JsonValue);
      State := Default(TGroupState);
      if Item.TryGetValue<TJSONArray>('collapsed', List) then
        for Value in List do
          State.Collapsed := State.Collapsed + [LowerCase(Value.Value)];
      if Item.TryGetValue<TJSONArray>('origins', List) then
      begin
        State.HasFilters := True;
        for Value in List do
          for Origin := Low(TAtlasUnitOrigin) to High(TAtlasUnitOrigin) do
            if SameText(Value.Value, OriginTexts[Origin]) then
              Include(State.Origins, Origin);
      end;
      if Item.TryGetValue<TJSONArray>('kinds', List) then
        for Value in List do
          if TAtlasUnitSearch.KindFromText(Value.Value, Kind) then
            Include(State.Kinds, Kind);
      FGroups.AddOrSetValue(LowerCase(Pair.JsonString.Value), State);
    end;
  finally
    Root.Free;
  end;
end;

procedure TAtlasUnitSearchState.LoadFromFile(const AFileName: string);
begin
  if TFile.Exists(AFileName) then
    LoadJson(TFile.ReadAllText(AFileName, TEncoding.UTF8))
  else
    LoadJson('');
end;

procedure TAtlasUnitSearchState.SaveToFile(const AFileName: string);
begin
  ForceDirectories(ExtractFileDir(AFileName));
  TFile.WriteAllText(AFileName, ToJson, TEncoding.UTF8);
end;

end.
