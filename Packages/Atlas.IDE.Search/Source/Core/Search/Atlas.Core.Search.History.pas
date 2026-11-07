unit Atlas.Core.Search.History;

// Such- und Ersetzen-Verlauf der Atlas-Suchleiste (#893, search.history),
// ohne VCL und Open Tools API:
// - Remember: neuester Eintrag vorn; ein Text, den es schon gibt, rückt nach
//   vorn statt doppelt zu stehen (Groß-/Kleinschreibung zählt, „Foo“ und
//   „foo“ sind verschiedene Suchen). Höchstens Capacity Einträge; 0 = kein
//   Verlauf (Remember merkt nichts, Step blättert nicht).
// - Step: Pfeil hoch (AOlder) bzw. runter im Feld. Der erste Schritt nach
//   oben merkt sich den getippten Text; unter den neuesten Eintrag hinab
//   kommt er zurück. Remember und Reset beginnen von vorn.
// - ToJson/FromJson: {"search": [...], "replace": [...]} für die Datei
//   %APPDATA%\Atlas\search-history.json (gespeichert über Neustarts).

interface

uses
  System.SysUtils,
  System.JSON;

type
  TAtlasSearchHistory = class
  private
    FItems: TArray<string>;
    FCapacity: Integer;
    // -1 = nicht beim Blättern; sonst Index des gezeigten Eintrags.
    FPosition: Integer;
    FTyped: string;
    procedure SetCapacity(AValue: Integer);
  public
    constructor Create(ACapacity: Integer);
    procedure Remember(const AText: string);
    /// <summary>Text nach einem Schritt; ACurrent ist der Text im Feld. Ohne weiteren Eintrag bleibt ACurrent.
    /// </summary>
    function Step(const ACurrent: string; AOlder: Boolean): string;
    /// <summary>Blättern beenden (Feld von Hand geändert).</summary>
    procedure Reset;
    procedure Clear;
    function ToJson: TJSONArray;
    procedure LoadFromJson(const AValue: TJSONValue);
    /// <summary>Neueste zuerst.</summary>
    property Items: TArray<string> read FItems;
    /// <summary>search.history; kürzt sofort.</summary>
    property Capacity: Integer read FCapacity write SetCapacity;
  end;

  TAtlasSearchHistories = class
  public
    /// <summary>Text der Datei aus beiden Verläufen.</summary>
    class function ToText(ASearch, AReplace: TAtlasSearchHistory): string; static;
    /// <summary>Beide Verläufe aus dem Text; False, wenn er kein Objekt ist (Datei unbrauchbar).</summary>
    class function FromText(const AText: string; ASearch, AReplace: TAtlasSearchHistory): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections;

{ TAtlasSearchHistory }

constructor TAtlasSearchHistory.Create(ACapacity: Integer);
begin
  inherited Create;
  FPosition := -1;
  SetCapacity(ACapacity);
end;

procedure TAtlasSearchHistory.SetCapacity(AValue: Integer);
begin
  if AValue < 0 then
  begin
    AValue := 0;
  end;
  FCapacity := AValue;
  if Length(FItems) > FCapacity then
  begin
    SetLength(FItems, FCapacity);
  end;
  Reset;
end;

procedure TAtlasSearchHistory.Remember(const AText: string);
var
  mIndex: Integer;
  mNext: TArray<string>;
begin
  Reset;
  if (AText = '') or (FCapacity = 0) then
  begin
    Exit;
  end;
  mNext := [AText];
  for mIndex := 0 to High(FItems) do
  begin
    if (FItems[mIndex] <> AText) and (Length(mNext) < FCapacity) then
    begin
      mNext := mNext + [FItems[mIndex]];
    end;
  end;
  FItems := mNext;
end;

function TAtlasSearchHistory.Step(const ACurrent: string; AOlder: Boolean): string;
begin
  Result := ACurrent;
  if Length(FItems) = 0 then
  begin
    Exit;
  end;
  if AOlder then
  begin
    if FPosition < 0 then
    begin
      FTyped := ACurrent;
      // Steht der neueste Eintrag schon im Feld, ist der nächste ältere gemeint.
      if ACurrent = FItems[0] then
      begin
        FPosition := 0;
      end;
    end;
    if FPosition < High(FItems) then
    begin
      Inc(FPosition);
    end;
    Result := FItems[FPosition];
  end
  else
  begin
    if FPosition < 0 then
    begin
      Exit;
    end;
    Dec(FPosition);
    if FPosition < 0 then
    begin
      Result := FTyped;
    end
    else
    begin
      Result := FItems[FPosition];
    end;
  end;
end;

procedure TAtlasSearchHistory.Reset;
begin
  FPosition := -1;
  FTyped := '';
end;

procedure TAtlasSearchHistory.Clear;
begin
  FItems := nil;
  Reset;
end;

function TAtlasSearchHistory.ToJson: TJSONArray;
var
  mItem: string;
begin
  Result := TJSONArray.Create;
  for mItem in FItems do
  begin
    Result.Add(mItem);
  end;
end;

procedure TAtlasSearchHistory.LoadFromJson(const AValue: TJSONValue);
var
  mElement: TJSONValue;
  mLoaded: TArray<string>;
  mIndex: Integer;
begin
  Clear;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  mLoaded := nil;
  for mElement in TJSONArray(AValue) do
  begin
    // TJSONNumber erbt von TJSONString; Zahlen sind keine Einträge.
    if (mElement is TJSONString) and not (mElement is TJSONNumber) and (mElement.Value <> '') then
    begin
      mLoaded := mLoaded + [mElement.Value];
    end;
  end;
  // Von hinten merken: so steht der erste Eintrag der Datei wieder vorn, Doppelte fallen weg.
  for mIndex := High(mLoaded) downto 0 do
  begin
    Remember(mLoaded[mIndex]);
  end;
end;

{ TAtlasSearchHistories }

class function TAtlasSearchHistories.ToText(ASearch, AReplace: TAtlasSearchHistory): string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('search', ASearch.ToJson);
    mRoot.AddPair('replace', AReplace.ToJson);
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasSearchHistories.FromText(const AText: string; ASearch, AReplace: TAtlasSearchHistory): Boolean;
var
  mRoot: TJSONValue;
begin
  ASearch.Clear;
  AReplace.Clear;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    Result := mRoot is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    ASearch.LoadFromJson(TJSONObject(mRoot).GetValue('search'));
    AReplace.LoadFromJson(TJSONObject(mRoot).GetValue('replace'));
  finally
    mRoot.Free;
  end;
end;

end.
