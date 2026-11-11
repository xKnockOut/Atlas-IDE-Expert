unit Atlas.Core.Designer.NearAlign;

// Fast bündige Kanten im Designer (#746), ohne VCL und Windows:
// - Verglichen werden je Parent linke, rechte, obere und untere Kanten und
//   die Textgrundlinie der Steuerelemente (ohne Align und ohne Klassen der
//   Ausnahmeliste; das markiert der Aufrufer mit Skip).
// - Zwei Steuerelemente vergleichen eine Kante nur, wenn sie quer dazu nahe
//   sind: überlappend oder höchstens cProximity Pixel auseinander.
// - Fast bündig: Versatz größer 0 und höchstens Toleranz. Bezug ist die
//   Flucht, die mehr Nachbarn teilen; bei Gleichstand die des älteren
//   Steuerelements (kleinerer Index = früher in der DFM).
// - Ausnahmen als Schlüssel „Name.kante“ (edtFax.left); sie werden nicht
//   gemeldet. TAtlasNearExceptions hält sie je Formulardatei als JSON.
// - Beheben: linke und obere Kante sowie Grundlinie verschieben, rechte und
//   untere ändern die Größe. Mit Kante oben und Grundlinie zählt nur oben.

interface

uses
  System.Types,
  System.Generics.Collections;

type
{$SCOPEDENUMS ON}
  TAtlasEdge = (Left, Top, Right, Bottom, Baseline);
{$SCOPEDENUMS OFF}

  TAtlasAlignItem = record
    Name: string;
    Bounds: TRect;
    /// <summary>Grundlinie im Parent; -1 ohne Text.</summary>
    Baseline: Integer;
    /// <summary>Nicht vergleichen (Align, Klasse auf der Ausnahmeliste).</summary>
    Skip: Boolean;
    class function Create(const AName: string; const ABounds: TRect; ABaseline: Integer;
      ASkip: Boolean): TAtlasAlignItem; static;
  end;

  TAtlasNearFinding = record
    /// <summary>Index in der Liste der Steuerelemente.</summary>
    Item: Integer;
    Edge: TAtlasEdge;
    Value: Integer;
    /// <summary>Bezugsflucht.</summary>
    Target: Integer;
    function Offset: Integer;
  end;

  TAtlasNearAlign = class
  public const
    cProximity = 200;
  public
    class function EdgeName(AEdge: TAtlasEdge): string; static;
    /// <summary>Schlüssel der Ausnahme: „Name.kante“.</summary>
    class function KeyOf(const AName: string; AEdge: TAtlasEdge): string; static;
    /// <summary>Kante AEdge von AItem; -1 ohne (Grundlinie ohne Text).</summary>
    class function EdgeOf(const AItem: TAtlasAlignItem; AEdge: TAtlasEdge): Integer; static;
    /// <summary>Fast bündige Kanten; ABaseline: auch Grundlinien.</summary>
    class function Find(const AItems: TArray<TAtlasAlignItem>; ATolerance: Integer; ABaseline: Boolean;
      const AExceptions: TArray<string>): TArray<TAtlasNearFinding>; static;
    /// <summary>Neue Lage aller Steuerelemente nach AFindings.</summary>
    class function FixAll(const AItems: TArray<TAtlasAlignItem>;
      const AFindings: TArray<TAtlasNearFinding>): TArray<TRect>; static;
  end;

  /// <summary>Ausnahmen je Formulardatei, als JSON {"version":1,"forms":{"Form1.dfm":["edtFax.left"]}}.</summary>
  TAtlasNearExceptions = class
  private
    FForms: TDictionary<string, TArray<string>>;
    FChanged: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function Keys(const AForm: string): TArray<string>;
    /// <summary>Schlüssel hinzufügen; doppelte zählen einmal.</summary>
    procedure Add(const AForm: string; const AKeys: TArray<string>);
    /// <summary>Alle Schlüssel, die mit einem der Namen beginnen („Name.“), entfernen; Anzahl entfernter.</summary>
    function RemoveNames(const AForm: string; const ANames: TArray<string>): Integer;
    function ToJson: string;
    /// <summary>Ersetzt den Inhalt; False bei unbrauchbarem Text (Inhalt dann leer).</summary>
    function LoadJson(const AText: string): Boolean;
    property Changed: Boolean read FChanged write FChanged;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.JSON;

const
  cEdgeNames: array [TAtlasEdge] of string = ('left', 'top', 'right', 'bottom', 'baseline');

{ TAtlasAlignItem }

class function TAtlasAlignItem.Create(const AName: string; const ABounds: TRect; ABaseline: Integer;
  ASkip: Boolean): TAtlasAlignItem;
begin
  Result.Name := AName;
  Result.Bounds := ABounds;
  Result.Baseline := ABaseline;
  Result.Skip := ASkip;
end;

{ TAtlasNearFinding }

function TAtlasNearFinding.Offset: Integer;
begin
  Result := Target - Value;
end;

{ TAtlasNearAlign }

class function TAtlasNearAlign.EdgeName(AEdge: TAtlasEdge): string;
begin
  Result := cEdgeNames[AEdge];
end;

class function TAtlasNearAlign.KeyOf(const AName: string; AEdge: TAtlasEdge): string;
begin
  Result := AName + '.' + cEdgeNames[AEdge];
end;

class function TAtlasNearAlign.EdgeOf(const AItem: TAtlasAlignItem; AEdge: TAtlasEdge): Integer;
begin
  case AEdge of
    TAtlasEdge.Left:
      Result := AItem.Bounds.Left;
    TAtlasEdge.Top:
      Result := AItem.Bounds.Top;
    TAtlasEdge.Right:
      Result := AItem.Bounds.Right;
    TAtlasEdge.Bottom:
      Result := AItem.Bounds.Bottom;
  else
    Result := AItem.Baseline;
  end;
end;

/// <summary>Abstand von A und B quer zur Kante (senkrecht bei linker/rechter Kante); 0 bei Überlappung.</summary>
function Distance(const A, B: TRect; AEdge: TAtlasEdge): Integer;
begin
  if AEdge in [TAtlasEdge.Left, TAtlasEdge.Right] then
  begin
    Result := Max(0, Max(A.Top - B.Bottom, B.Top - A.Bottom));
  end
  else
  begin
    Result := Max(0, Max(A.Left - B.Right, B.Left - A.Right));
  end;
end;

type
  /// <summary>Eine Flucht unter den Nachbarn: Wert, Anzahl und ältestes Steuerelement.</summary>
  TLine = record
    Value: Integer;
    Count: Integer;
    First: Integer;
    /// <summary>Schlägt diese Flucht AOther (mehr Steuerelemente, bei Gleichstand das ältere)?</summary>
    function Beats(const AOther: TLine): Boolean;
  end;

function TLine.Beats(const AOther: TLine): Boolean;
begin
  Result := (Count > AOther.Count) or ((Count = AOther.Count) and (First < AOther.First));
end;

/// <summary>Flucht AValue unter AItem und seinen Nachbarn.</summary>
function LineOf(const AItems: TArray<TAtlasAlignItem>; AItem: Integer; AEdge: TAtlasEdge; AValue: Integer): TLine;
var
  mIndex: Integer;
begin
  Result.Value := AValue;
  Result.Count := 0;
  Result.First := MaxInt;
  for mIndex := 0 to High(AItems) do
  begin
    if AItems[mIndex].Skip or (TAtlasNearAlign.EdgeOf(AItems[mIndex], AEdge) <> AValue) or
      ((mIndex <> AItem) and (Distance(AItems[mIndex].Bounds, AItems[AItem].Bounds, AEdge) >
      TAtlasNearAlign.cProximity)) then
    begin
      Continue;
    end;
    Inc(Result.Count);
    Result.First := Min(Result.First, mIndex);
  end;
end;

/// <summary>Zählt AOther als Nachbar von AItem an AEdge (nicht übergangen, quer dazu nahe)?</summary>
function Neighbour(const AItems: TArray<TAtlasAlignItem>; AItem, AOther: Integer; AEdge: TAtlasEdge): Boolean;
begin
  Result := not AItems[AOther].Skip and (Distance(AItems[AOther].Bounds, AItems[AItem].Bounds, AEdge) <=
    TAtlasNearAlign.cProximity);
end;

/// <summary>Beste Flucht für AItem an AEdge, die seine eigene schlägt; False ohne.</summary>
function BestLine(const AItems: TArray<TAtlasAlignItem>; AItem: Integer; AEdge: TAtlasEdge; ATolerance: Integer;
  out ALine: TLine): Boolean;
var
  mIndex, mValue, mOther: Integer;
  mOwn, mLine: TLine;
begin
  mValue := TAtlasNearAlign.EdgeOf(AItems[AItem], AEdge);
  mOwn := LineOf(AItems, AItem, AEdge, mValue);
  ALine := mOwn;
  for mIndex := 0 to High(AItems) do
  begin
    mOther := TAtlasNearAlign.EdgeOf(AItems[mIndex], AEdge);
    if (mIndex = AItem) or (mOther < 0) or (mOther = mValue) or (Abs(mOther - mValue) > ATolerance) or
      not Neighbour(AItems, AItem, mIndex, AEdge) then
    begin
      Continue;
    end;
    mLine := LineOf(AItems, AItem, AEdge, mOther);
    if mLine.Beats(ALine) then
    begin
      ALine := mLine;
    end;
  end;
  Result := ALine.Value <> mValue;
end;

function Excepted(const AExceptions: TArray<string>; const AKey: string): Boolean;
var
  mKey: string;
begin
  for mKey in AExceptions do
  begin
    if SameText(mKey, AKey) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasNearAlign.Find(const AItems: TArray<TAtlasAlignItem>; ATolerance: Integer; ABaseline: Boolean;
  const AExceptions: TArray<string>): TArray<TAtlasNearFinding>;
var
  mIndex: Integer;
  mEdge: TAtlasEdge;
  mLine: TLine;
  mFinding: TAtlasNearFinding;
begin
  Result := nil;
  for mIndex := 0 to High(AItems) do
  begin
    for mEdge := Low(TAtlasEdge) to High(TAtlasEdge) do
    begin
      if AItems[mIndex].Skip or ((mEdge = TAtlasEdge.Baseline) and (not ABaseline or (AItems[mIndex].Baseline < 0))) or
        Excepted(AExceptions, KeyOf(AItems[mIndex].Name, mEdge)) then
      begin
        Continue;
      end;
      if BestLine(AItems, mIndex, mEdge, ATolerance, mLine) then
      begin
        mFinding.Item := mIndex;
        mFinding.Edge := mEdge;
        mFinding.Value := EdgeOf(AItems[mIndex], mEdge);
        mFinding.Target := mLine.Value;
        Result := Result + [mFinding];
      end;
    end;
  end;
end;

function HasTopFinding(const AFindings: TArray<TAtlasNearFinding>; AItem: Integer): Boolean;
var
  mFinding: TAtlasNearFinding;
begin
  for mFinding in AFindings do
  begin
    if (mFinding.Item = AItem) and (mFinding.Edge = TAtlasEdge.Top) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>ARect nach einem Fund: verschieben (links, oben, Grundlinie) oder Größe (rechts, unten).</summary>
function Fixed(const ARect: TRect; const AFinding: TAtlasNearFinding): TRect;
begin
  Result := ARect;
  case AFinding.Edge of
    TAtlasEdge.Left:
      Result.Offset(AFinding.Offset, 0);
    TAtlasEdge.Top, TAtlasEdge.Baseline:
      Result.Offset(0, AFinding.Offset);
    TAtlasEdge.Right:
      Result.Right := AFinding.Target;
    TAtlasEdge.Bottom:
      Result.Bottom := AFinding.Target;
  end;
end;

class function TAtlasNearAlign.FixAll(const AItems: TArray<TAtlasAlignItem>;
  const AFindings: TArray<TAtlasNearFinding>): TArray<TRect>;
var
  mIndex: Integer;
  mPass: Boolean;
  mFinding: TAtlasNearFinding;
begin
  SetLength(Result, Length(AItems));
  for mIndex := 0 to High(AItems) do
  begin
    Result[mIndex] := AItems[mIndex].Bounds;
  end;
  // Erst verschieben, dann die Größe: rechte und untere Kante liegen danach genau auf der Flucht.
  for mPass := False to True do
  begin
    for mFinding in AFindings do
    begin
      if (mFinding.Edge in [TAtlasEdge.Right, TAtlasEdge.Bottom]) <> mPass then
      begin
        Continue;
      end;
      if (mFinding.Edge = TAtlasEdge.Baseline) and HasTopFinding(AFindings, mFinding.Item) then
      begin
        Continue;
      end;
      Result[mFinding.Item] := Fixed(Result[mFinding.Item], mFinding);
    end;
  end;
end;

{ TAtlasNearExceptions }

constructor TAtlasNearExceptions.Create;
begin
  inherited Create;
  FForms := TDictionary<string, TArray<string>>.Create;
end;

destructor TAtlasNearExceptions.Destroy;
begin
  FForms.Free;
  inherited Destroy;
end;

function TAtlasNearExceptions.Keys(const AForm: string): TArray<string>;
begin
  if not FForms.TryGetValue(LowerCase(AForm), Result) then
  begin
    Result := nil;
  end;
end;

procedure TAtlasNearExceptions.Add(const AForm: string; const AKeys: TArray<string>);
var
  mKeys: TArray<string>;
  mKey: string;
begin
  mKeys := Keys(AForm);
  for mKey in AKeys do
  begin
    if not Excepted(mKeys, mKey) then
    begin
      mKeys := mKeys + [mKey];
      FChanged := True;
    end;
  end;
  FForms.AddOrSetValue(LowerCase(AForm), mKeys);
end;

function TAtlasNearExceptions.RemoveNames(const AForm: string; const ANames: TArray<string>): Integer;
var
  mKeys, mKept: TArray<string>;
  mKey, mName: string;
  mDrop: Boolean;
begin
  mKeys := Keys(AForm);
  mKept := nil;
  for mKey in mKeys do
  begin
    mDrop := False;
    for mName in ANames do
    begin
      mDrop := mDrop or mKey.StartsWith(mName + '.', True);
    end;
    if not mDrop then
    begin
      mKept := mKept + [mKey];
    end;
  end;
  Result := Length(mKeys) - Length(mKept);
  if Result > 0 then
  begin
    FForms.AddOrSetValue(LowerCase(AForm), mKept);
    FChanged := True;
  end;
end;

function TAtlasNearExceptions.ToJson: string;
var
  mRoot, mForms: TJSONObject;
  mList: TJSONArray;
  mPair: TPair<string, TArray<string>>;
  mKey: string;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('version', TJSONNumber.Create(1));
    mForms := TJSONObject.Create;
    mRoot.AddPair('forms', mForms);
    for mPair in FForms do
    begin
      if Length(mPair.Value) = 0 then
      begin
        Continue;
      end;
      mList := TJSONArray.Create;
      mForms.AddPair(mPair.Key, mList);
      for mKey in mPair.Value do
      begin
        mList.Add(mKey);
      end;
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

function TAtlasNearExceptions.LoadJson(const AText: string): Boolean;
var
  mRoot: TJSONValue;
  mForms: TJSONObject;
  mPair: TJSONPair;
  mItem: TJSONValue;
  mKeys: TArray<string>;
begin
  FForms.Clear;
  FChanged := False;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    Result := (mRoot is TJSONObject) and TJSONObject(mRoot).TryGetValue<TJSONObject>('forms', mForms);
    if not Result then
    begin
      Exit;
    end;
    for mPair in mForms do
    begin
      if not (mPair.JsonValue is TJSONArray) then
      begin
        Continue;
      end;
      mKeys := nil;
      for mItem in TJSONArray(mPair.JsonValue) do
      begin
        if mItem is TJSONString then
        begin
          mKeys := mKeys + [TJSONString(mItem).Value];
        end;
      end;
      FForms.AddOrSetValue(LowerCase(mPair.JsonString.Value), mKeys);
    end;
  finally
    mRoot.Free;
  end;
end;

end.
