unit Atlas.Core.Designer.PropertyPainter;

// Eigenschaften im Designer übertragen, Format-Pinsel (#726), ohne VCL und
// Windows. Das Plugin liest die gesetzten Eigenschaften der Quelle als Pfade
// („Font.Style“) mit Typnamen; hier stehen die Regeln:
// - Gruppen: Schrift, Farben, Größe, Position, Layout, Text, Verhalten,
//   Ereignisse, Übrige. Vorausgewählt sind die Gruppen aus
//   designer.propertyPainter.defaultGroups, sonst die für die Quellklasse
//   gemerkten Pfade.
// - Zeilen für den Dialog: je Gruppe eine Überschrift, verschachtelte
//   Eigenschaften unter ihrem Knoten („Font“), der alle Kinder umfasst.
// - Übertragen wird, was das Ziel unter demselben Pfad mit demselben Typ
//   hat; der Rest wird als übersprungen gemeldet.
// - TAtlasPaintMemory hält die Häkchen je Quellklasse als JSON
//   {"version":1,"classes":{"TButton":["Font.Style","Width"]}}.

interface

uses
  System.Generics.Collections;

type
{$SCOPEDENUMS ON}
  TAtlasPaintGroup = (Font, Colors, Size, Position, Layout, Text, Behavior, Events, Other);
  TAtlasPaintRowKind = (Header, Node, Leaf);
{$SCOPEDENUMS OFF}
  TAtlasPaintGroups = set of TAtlasPaintGroup;

  TAtlasPaintProperty = record
    /// <summary>Pfad mit Punkten für verschachtelte Eigenschaften (Font.Style).</summary>
    Path: string;
    TypeName: string;
    IsEvent: Boolean;
    class function Create(const APath, ATypeName: string; AIsEvent: Boolean): TAtlasPaintProperty; static;
  end;

  TAtlasPaintRow = record
    Kind: TAtlasPaintRowKind;
    Group: TAtlasPaintGroup;
    /// <summary>Pfad der Eigenschaft bzw. des Knotens; leer bei Überschriften.</summary>
    Path: string;
    /// <summary>Index des Knotens, unter dem die Zeile steht; -1 ohne.</summary>
    Parent: Integer;
  end;

  TAtlasPropertyPainter = class
  public
    class function GroupOf(const AProperty: TAtlasPaintProperty): TAtlasPaintGroup; static;
    class function GroupName(AGroup: TAtlasPaintGroup): string; static;
    /// <summary>Gruppen aus „font, colors, …“; unbekannte Namen fallen weg.</summary>
    class function ParseGroups(const AText: string): TAtlasPaintGroups; static;
    /// <summary>Zeilen für den Dialog in Gruppenreihenfolge.</summary>
    class function Rows(const AProperties: TArray<TAtlasPaintProperty>): TArray<TAtlasPaintRow>; static;
    /// <summary>Häkchen je Zeile: gemerkte Pfade (AHasRemembered) oder die Gruppen AGroups.</summary>
    class function Preselect(const ARows: TArray<TAtlasPaintRow>; AGroups: TAtlasPaintGroups;
      const ARemembered: TArray<string>; AHasRemembered: Boolean): TArray<Boolean>; static;
    /// <summary>Gewählte Eigenschaften: Blätter mit Häkchen oder unter einem Knoten mit Häkchen.</summary>
    class function Chosen(const ARows: TArray<TAtlasPaintRow>; const AChecked: TArray<Boolean>): TArray<string>; static;
    /// <summary>Pfade aus AChosen, die AQuelle und das Ziel mit gleichem Typ haben; ASkipped: die übrigen.</summary>
    class function Match(const ASource: TArray<TAtlasPaintProperty>; const AChosen: TArray<string>;
      const ATarget: TArray<TAtlasPaintProperty>; out ASkipped: TArray<string>): TArray<string>; static;
  end;

  TAtlasPaintMemory = class
  private
    FClasses: TDictionary<string, TArray<string>>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Gemerkte Pfade für AClass; False ohne Eintrag.</summary>
    function TryGet(const AClass: string; out APaths: TArray<string>): Boolean;
    procedure Put(const AClass: string; const APaths: TArray<string>);
    function ToJson: string;
    /// <summary>Ersetzt den Inhalt; False bei unbrauchbarem Text (Inhalt dann leer).</summary>
    function LoadJson(const AText: string): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.JSON;

const
  cGroupNames: array [TAtlasPaintGroup] of string = ('font', 'colors', 'size', 'position', 'layout', 'text',
    'behavior', 'events', 'other');

{ TAtlasPaintProperty }

class function TAtlasPaintProperty.Create(const APath, ATypeName: string; AIsEvent: Boolean): TAtlasPaintProperty;
begin
  Result.Path := APath;
  Result.TypeName := ATypeName;
  Result.IsEvent := AIsEvent;
end;

{ TAtlasPropertyPainter }

function OneOf(const AName: string; const ANames: array of string): Boolean;
var
  mName: string;
begin
  for mName in ANames do
  begin
    if SameText(AName, mName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Erster Teil des Pfads (Font bei Font.Style).</summary>
function HeadOf(const APath: string): string;
var
  mDot: Integer;
begin
  mDot := Pos('.', APath);
  Result := APath;
  if mDot > 0 then
  begin
    Result := Copy(APath, 1, mDot - 1);
  end;
end;

class function TAtlasPropertyPainter.GroupOf(const AProperty: TAtlasPaintProperty): TAtlasPaintGroup;
var
  mHead: string;
begin
  mHead := HeadOf(AProperty.Path);
  if AProperty.IsEvent then
  begin
    Result := TAtlasPaintGroup.Events;
  end
  else if OneOf(mHead, ['Font', 'ParentFont']) then
  begin
    Result := TAtlasPaintGroup.Font;
  end
  else if OneOf(mHead, ['Color', 'ParentColor', 'StyleElements']) then
  begin
    Result := TAtlasPaintGroup.Colors;
  end
  else if OneOf(mHead, ['Width', 'Height']) then
  begin
    Result := TAtlasPaintGroup.Size;
  end
  else if OneOf(mHead, ['Left', 'Top']) then
  begin
    Result := TAtlasPaintGroup.Position;
  end
  else if OneOf(mHead, ['Anchors', 'Align', 'AlignWithMargins', 'Margins', 'Padding', 'Constraints']) then
  begin
    Result := TAtlasPaintGroup.Layout;
  end
  else if OneOf(mHead, ['Caption', 'Text', 'Hint', 'ShowHint']) then
  begin
    Result := TAtlasPaintGroup.Text;
  end
  else if OneOf(mHead, ['Enabled', 'TabStop', 'Cursor', 'PopupMenu', 'Action']) then
  begin
    Result := TAtlasPaintGroup.Behavior;
  end
  else
  begin
    Result := TAtlasPaintGroup.Other;
  end;
end;

class function TAtlasPropertyPainter.GroupName(AGroup: TAtlasPaintGroup): string;
begin
  Result := cGroupNames[AGroup];
end;

class function TAtlasPropertyPainter.ParseGroups(const AText: string): TAtlasPaintGroups;
var
  mPart: string;
  mGroup: TAtlasPaintGroup;
begin
  Result := [];
  for mPart in AText.Split([',', ';']) do
  begin
    for mGroup := Low(TAtlasPaintGroup) to High(TAtlasPaintGroup) do
    begin
      if SameText(Trim(mPart), cGroupNames[mGroup]) then
      begin
        Include(Result, mGroup);
      end;
    end;
  end;
end;

function Row(AKind: TAtlasPaintRowKind; AGroup: TAtlasPaintGroup; const APath: string;
  AParent: Integer): TAtlasPaintRow;
begin
  Result.Kind := AKind;
  Result.Group := AGroup;
  Result.Path := APath;
  Result.Parent := AParent;
end;

/// <summary>Index des Knotens AHead in ARows ab AFrom; -1 ohne.</summary>
function NodeIndex(const ARows: TArray<TAtlasPaintRow>; AFrom: Integer; const AHead: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := AFrom to High(ARows) do
  begin
    if (ARows[mIndex].Kind = TAtlasPaintRowKind.Node) and SameText(ARows[mIndex].Path, AHead) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Zeilen einer Gruppe an ARows anhängen: Blätter, verschachtelte unter ihrem Knoten.</summary>
procedure AddGroup(var ARows: TArray<TAtlasPaintRow>; const AProperties: TArray<TAtlasPaintProperty>;
  AGroup: TAtlasPaintGroup);
var
  mProperty: TAtlasPaintProperty;
  mStart, mNode, mAt: Integer;
  mHead: string;
begin
  mStart := Length(ARows);
  for mProperty in AProperties do
  begin
    if TAtlasPropertyPainter.GroupOf(mProperty) <> AGroup then
    begin
      Continue;
    end;
    if Length(ARows) = mStart then
    begin
      ARows := ARows + [Row(TAtlasPaintRowKind.Header, AGroup, '', -1)];
    end;
    mHead := HeadOf(mProperty.Path);
    if mHead = mProperty.Path then
    begin
      ARows := ARows + [Row(TAtlasPaintRowKind.Leaf, AGroup, mProperty.Path, -1)];
      Continue;
    end;
    mNode := NodeIndex(ARows, mStart, mHead);
    if mNode < 0 then
    begin
      ARows := ARows + [Row(TAtlasPaintRowKind.Node, AGroup, mHead, -1)];
      mNode := High(ARows);
    end;
    // Hinter die letzten Kinder des Knotens.
    mAt := mNode + 1;
    while (mAt <= High(ARows)) and (ARows[mAt].Kind = TAtlasPaintRowKind.Leaf) and (ARows[mAt].Parent >= 0) and
      SameText(HeadOf(ARows[mAt].Path), mHead) do
    begin
      Inc(mAt);
    end;
    Insert(Row(TAtlasPaintRowKind.Leaf, AGroup, mProperty.Path, mNode), ARows, mAt);
  end;
end;

/// <summary>Parent-Indizes nach dem Einfügen neu setzen (Kinder stehen direkt hinter ihrem Knoten).</summary>
procedure FixParents(var ARows: TArray<TAtlasPaintRow>);
var
  mIndex, mNode: Integer;
begin
  mNode := -1;
  for mIndex := 0 to High(ARows) do
  begin
    case ARows[mIndex].Kind of
      TAtlasPaintRowKind.Node:
        mNode := mIndex;
      TAtlasPaintRowKind.Header:
        mNode := -1;
    else
      if ARows[mIndex].Parent >= 0 then
      begin
        ARows[mIndex].Parent := mNode;
      end;
    end;
  end;
end;

class function TAtlasPropertyPainter.Rows(const AProperties: TArray<TAtlasPaintProperty>): TArray<TAtlasPaintRow>;
var
  mGroup: TAtlasPaintGroup;
begin
  Result := nil;
  for mGroup := Low(TAtlasPaintGroup) to High(TAtlasPaintGroup) do
  begin
    AddGroup(Result, AProperties, mGroup);
  end;
  FixParents(Result);
end;

function Listed(const AList: TArray<string>; const AValue: string): Boolean;
var
  mItem: string;
begin
  for mItem in AList do
  begin
    if SameText(mItem, AValue) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasPropertyPainter.Preselect(const ARows: TArray<TAtlasPaintRow>; AGroups: TAtlasPaintGroups;
  const ARemembered: TArray<string>; AHasRemembered: Boolean): TArray<Boolean>;
var
  mIndex, mChild: Integer;
  mAll: Boolean;
begin
  SetLength(Result, Length(ARows));
  for mIndex := 0 to High(ARows) do
  begin
    if ARows[mIndex].Kind = TAtlasPaintRowKind.Leaf then
    begin
      Result[mIndex] := (AHasRemembered and Listed(ARemembered, ARows[mIndex].Path)) or
        (not AHasRemembered and (ARows[mIndex].Group in AGroups));
    end;
  end;
  // Ein Knoten hat ein Häkchen, wenn alle seine Kinder eins haben.
  for mIndex := 0 to High(ARows) do
  begin
    if ARows[mIndex].Kind <> TAtlasPaintRowKind.Node then
    begin
      Continue;
    end;
    mAll := True;
    for mChild := 0 to High(ARows) do
    begin
      mAll := mAll and ((ARows[mChild].Parent <> mIndex) or Result[mChild]);
    end;
    Result[mIndex] := mAll;
  end;
end;

class function TAtlasPropertyPainter.Chosen(const ARows: TArray<TAtlasPaintRow>;
  const AChecked: TArray<Boolean>): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(ARows) do
  begin
    if (ARows[mIndex].Kind = TAtlasPaintRowKind.Leaf) and (AChecked[mIndex] or ((ARows[mIndex].Parent >= 0) and
      AChecked[ARows[mIndex].Parent])) then
    begin
      Result := Result + [ARows[mIndex].Path];
    end;
  end;
end;

function TypeNameOf(const AProperties: TArray<TAtlasPaintProperty>; const APath: string; out ATypeName: string): Boolean;
var
  mProperty: TAtlasPaintProperty;
begin
  for mProperty in AProperties do
  begin
    if SameText(mProperty.Path, APath) then
    begin
      ATypeName := mProperty.TypeName;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasPropertyPainter.Match(const ASource: TArray<TAtlasPaintProperty>;
  const AChosen: TArray<string>; const ATarget: TArray<TAtlasPaintProperty>; out ASkipped: TArray<string>): TArray<string>;
var
  mPath, mSourceType, mTargetType: string;
begin
  Result := nil;
  ASkipped := nil;
  for mPath in AChosen do
  begin
    if TypeNameOf(ASource, mPath, mSourceType) and TypeNameOf(ATarget, mPath, mTargetType) and
      SameText(mSourceType, mTargetType) then
    begin
      Result := Result + [mPath];
    end
    else
    begin
      ASkipped := ASkipped + [mPath];
    end;
  end;
end;

{ TAtlasPaintMemory }

constructor TAtlasPaintMemory.Create;
begin
  inherited Create;
  FClasses := TDictionary<string, TArray<string>>.Create;
end;

destructor TAtlasPaintMemory.Destroy;
begin
  FClasses.Free;
  inherited Destroy;
end;

function TAtlasPaintMemory.TryGet(const AClass: string; out APaths: TArray<string>): Boolean;
begin
  Result := FClasses.TryGetValue(LowerCase(AClass), APaths);
end;

procedure TAtlasPaintMemory.Put(const AClass: string; const APaths: TArray<string>);
begin
  FClasses.AddOrSetValue(LowerCase(AClass), APaths);
end;

function TAtlasPaintMemory.ToJson: string;
var
  mRoot, mClasses: TJSONObject;
  mList: TJSONArray;
  mPair: TPair<string, TArray<string>>;
  mPath: string;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('version', TJSONNumber.Create(1));
    mClasses := TJSONObject.Create;
    mRoot.AddPair('classes', mClasses);
    for mPair in FClasses do
    begin
      mList := TJSONArray.Create;
      mClasses.AddPair(mPair.Key, mList);
      for mPath in mPair.Value do
      begin
        mList.Add(mPath);
      end;
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

function TAtlasPaintMemory.LoadJson(const AText: string): Boolean;
var
  mRoot: TJSONValue;
  mClasses: TJSONObject;
  mPair: TJSONPair;
  mItem: TJSONValue;
  mPaths: TArray<string>;
begin
  FClasses.Clear;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    Result := (mRoot is TJSONObject) and TJSONObject(mRoot).TryGetValue<TJSONObject>('classes', mClasses);
    if not Result then
    begin
      Exit;
    end;
    for mPair in mClasses do
    begin
      if not (mPair.JsonValue is TJSONArray) then
      begin
        Continue;
      end;
      mPaths := nil;
      for mItem in TJSONArray(mPair.JsonValue) do
      begin
        if mItem is TJSONString then
        begin
          mPaths := mPaths + [TJSONString(mItem).Value];
        end;
      end;
      FClasses.AddOrSetValue(LowerCase(mPair.JsonString.Value), mPaths);
    end;
  finally
    mRoot.Free;
  end;
end;

end.
