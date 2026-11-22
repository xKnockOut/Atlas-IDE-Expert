unit Atlas.Core.UnitSearch.State;

// Gemerkter Zustand des Fensters „Units suchen“ (#777), Teil ohne VCL:
//   - je Projektgruppe: eingeklappte Gruppen (je Gruppierung), gewählte
//     Herkunft und Art der Filterchips;
//   - fürs Fenster: Lage und Größe, Breite und Sichtbarkeit der Vorschau;
//   - nur für die Sitzung, nicht gespeichert: von Hand auf- oder zugeklappte
//     Abschnitte der Vorschau (#876).
// Gespeichert als JSON (Datei unter %LOCALAPPDATA%\Atlas, setzt die IDE-Schicht),
// gelesen und atomar geschrieben über TAtlasDataFile: Eine
// unbrauchbare Datei liegt danach als .defekt daneben, eine gesperrte bleibt
// unverändert und wird nicht überschrieben.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.UnitSearch.Model,
  Atlas.Core.UnitSearch.Sections,
  Atlas.Plugin.Files.DataFile;

const
  /// <summary>Name der Ablage im Protokoll (TAtlasDataFile).</summary>
  cUnitSearchStateKind = 'Zustand von Units suchen';

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
    FLeft: Integer;
    FTop: Integer;
    FWidth: Integer;
    FHeight: Integer;
    FPreviewWidth: Integer;
    FPreviewVisible: Boolean;
    FSections: TAtlasSectionChoices;
    function GroupState(const AGroupFile: string): TGroupState;
    function GetSection(ASection: TAtlasPreviewSection): TAtlasSectionChoice;
    procedure SetSection(ASection: TAtlasPreviewSection; AChoice: TAtlasSectionChoice);
    function WindowJson: TJSONObject;
    procedure LoadWindow(AWindow: TJSONObject);
    procedure LoadGroups(AGroups: TJSONObject);
  public
    /// <summary>Lage des Fensters; Width = 0 = noch keine.</summary>
    property Left: Integer read FLeft write FLeft;
    property Top: Integer read FTop write FTop;
    property Width: Integer read FWidth write FWidth;
    property Height: Integer read FHeight write FHeight;
    /// <summary>Breite der Vorschau in Pixeln bei 96 dpi; 0 = Vorgabe.</summary>
    property PreviewWidth: Integer read FPreviewWidth write FPreviewWidth;
    property PreviewVisible: Boolean read FPreviewVisible write FPreviewVisible;
    /// <summary>Wahl von Hand je Abschnitt der Vorschau; nur in der Sitzung (#876).</summary>
    property Sections: TAtlasSectionChoices read FSections;
    property Section[ASection: TAtlasPreviewSection]: TAtlasSectionChoice read GetSection write SetSection;
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

uses
  Atlas.Text.Json;

const
  cOriginTexts: array[TAtlasUnitOrigin] of string = ('active', 'group', 'searchPath', 'library');

function GroupingPrefix(AGrouping: TAtlasUnitGrouping): string;
begin
  Result := TAtlasUnitSearch.GroupingText(AGrouping) + ':';
end;

{ TAtlasUnitSearchState }

constructor TAtlasUnitSearchState.Create;
begin
  inherited Create;
  FGroups := TDictionary<string, TGroupState>.Create;
  FPreviewVisible := True;
end;

destructor TAtlasUnitSearchState.Destroy;
begin
  FGroups.Free;
  inherited Destroy;
end;

function TAtlasUnitSearchState.GetSection(ASection: TAtlasPreviewSection): TAtlasSectionChoice;
begin
  Result := FSections[ASection];
end;

procedure TAtlasUnitSearchState.SetSection(ASection: TAtlasPreviewSection; AChoice: TAtlasSectionChoice);
begin
  FSections[ASection] := AChoice;
end;

function TAtlasUnitSearchState.GroupState(const AGroupFile: string): TGroupState;
begin
  if not FGroups.TryGetValue(LowerCase(AGroupFile), Result) then
  begin
    Result := Default(TGroupState);
  end;
end;

function TAtlasUnitSearchState.WindowJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('left', TJSONNumber.Create(FLeft));
  Result.AddPair('top', TJSONNumber.Create(FTop));
  Result.AddPair('width', TJSONNumber.Create(FWidth));
  Result.AddPair('height', TJSONNumber.Create(FHeight));
  Result.AddPair('previewWidth', TJSONNumber.Create(FPreviewWidth));
  Result.AddPair('previewVisible', TJSONBool.Create(FPreviewVisible));
end;

procedure TAtlasUnitSearchState.LoadWindow(AWindow: TJSONObject);
begin
  AWindow.TryGetValue<Integer>('left', FLeft);
  AWindow.TryGetValue<Integer>('top', FTop);
  AWindow.TryGetValue<Integer>('width', FWidth);
  AWindow.TryGetValue<Integer>('height', FHeight);
  AWindow.TryGetValue<Integer>('previewWidth', FPreviewWidth);
  AWindow.TryGetValue<Boolean>('previewVisible', FPreviewVisible);
end;

function TAtlasUnitSearchState.Collapsed(const AGroupFile: string; AGrouping: TAtlasUnitGrouping): TArray<string>;
var
  mItem, mPrefix: string;
begin
  Result := nil;
  mPrefix := GroupingPrefix(AGrouping);
  for mItem in GroupState(AGroupFile).Collapsed do
  begin
    if mItem.StartsWith(mPrefix) then
    begin
      Result := Result + [Copy(mItem, Length(mPrefix) + 1, MaxInt)];
    end;
  end;
end;

procedure TAtlasUnitSearchState.SetCollapsed(const AGroupFile: string; AGrouping: TAtlasUnitGrouping;
  const AKeys: TArray<string>);
var
  mState: TGroupState;
  mKept: TArray<string>;
  mItem, mPrefix: string;
begin
  mState := GroupState(AGroupFile);
  mPrefix := GroupingPrefix(AGrouping);
  mKept := nil;
  for mItem in mState.Collapsed do
  begin
    if not mItem.StartsWith(mPrefix) then
    begin
      mKept := mKept + [mItem];
    end;
  end;
  for mItem in AKeys do
  begin
    mKept := mKept + [mPrefix + LowerCase(mItem)];
  end;
  mState.Collapsed := mKept;
  FGroups.AddOrSetValue(LowerCase(AGroupFile), mState);
end;

function OriginsToJson(AOrigins: TAtlasUnitOrigins): TJSONArray;
var
  mOrigin: TAtlasUnitOrigin;
begin
  Result := TJSONArray.Create;
  for mOrigin in AOrigins do
  begin
    Result.Add(cOriginTexts[mOrigin]);
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
  Result.AddPair('collapsed', TJsonBuild.Strings(AState.Collapsed));
  if AState.HasFilters then
  begin
    Result.AddPair('origins', OriginsToJson(AState.Origins));
    Result.AddPair('kinds', KindsToJson(AState.Kinds));
  end;
end;

function TAtlasUnitSearchState.Filters(const AGroupFile: string; out AOrigins: TAtlasUnitOrigins;
  out AKinds: TAtlasUnitKinds): Boolean;
var
  mState: TGroupState;
begin
  mState := GroupState(AGroupFile);
  AOrigins := mState.Origins;
  AKinds := mState.Kinds;
  Result := mState.HasFilters;
end;

procedure TAtlasUnitSearchState.SetFilters(const AGroupFile: string; AOrigins: TAtlasUnitOrigins;
  AKinds: TAtlasUnitKinds);
var
  mState: TGroupState;
begin
  mState := GroupState(AGroupFile);
  mState.HasFilters := True;
  mState.Origins := AOrigins;
  mState.Kinds := AKinds;
  FGroups.AddOrSetValue(LowerCase(AGroupFile), mState);
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
      if SameText(mValue.Value, cOriginTexts[mOrigin]) then
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

function TAtlasUnitSearchState.LoadJson(const AText: string): Boolean;
var
  mRoot: TJSONValue;
  mSection: TJSONObject;
begin
  FGroups.Clear;
  FLeft := 0;
  FTop := 0;
  FWidth := 0;
  FHeight := 0;
  FPreviewWidth := 0;
  FPreviewVisible := True;
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
  Result := TAtlasDataFile.Load(AFileName, cUnitSearchStateKind,
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
  Result := TAtlasDataFile.WriteUnlessKept(AFileName, FKept, ToJson);
end;

end.
