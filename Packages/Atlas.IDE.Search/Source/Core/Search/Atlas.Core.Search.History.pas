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
    AValue := 0;
  FCapacity := AValue;
  if Length(FItems) > FCapacity then
    SetLength(FItems, FCapacity);
  Reset;
end;

procedure TAtlasSearchHistory.Remember(const AText: string);
var
  Index: Integer;
  Next: TArray<string>;
begin
  Reset;
  if (AText = '') or (FCapacity = 0) then
    Exit;
  Next := [AText];
  for Index := 0 to High(FItems) do
    if (FItems[Index] <> AText) and (Length(Next) < FCapacity) then
      Next := Next + [FItems[Index]];
  FItems := Next;
end;

function TAtlasSearchHistory.Step(const ACurrent: string; AOlder: Boolean): string;
begin
  Result := ACurrent;
  if Length(FItems) = 0 then
    Exit;
  if AOlder then
  begin
    if FPosition < 0 then
    begin
      FTyped := ACurrent;
      // Steht der neueste Eintrag schon im Feld, ist der nächste ältere gemeint.
      if ACurrent = FItems[0] then
        FPosition := 0;
    end;
    if FPosition < High(FItems) then
      Inc(FPosition);
    Result := FItems[FPosition];
  end
  else
  begin
    if FPosition < 0 then
      Exit;
    Dec(FPosition);
    if FPosition < 0 then
      Result := FTyped
    else
      Result := FItems[FPosition];
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
  Item: string;
begin
  Result := TJSONArray.Create;
  for Item in FItems do
    Result.Add(Item);
end;

procedure TAtlasSearchHistory.LoadFromJson(const AValue: TJSONValue);
var
  Element: TJSONValue;
  Loaded: TArray<string>;
  Index: Integer;
begin
  Clear;
  if not (AValue is TJSONArray) then
    Exit;
  Loaded := nil;
  for Element in TJSONArray(AValue) do
    // TJSONNumber erbt von TJSONString; Zahlen sind keine Einträge.
    if (Element is TJSONString) and not (Element is TJSONNumber) and (Element.Value <> '') then
      Loaded := Loaded + [Element.Value];
  // Von hinten merken: so steht der erste Eintrag der Datei wieder vorn, Doppelte fallen weg.
  for Index := High(Loaded) downto 0 do
    Remember(Loaded[Index]);
end;

{ TAtlasSearchHistories }

class function TAtlasSearchHistories.ToText(ASearch, AReplace: TAtlasSearchHistory): string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('search', ASearch.ToJson);
    Root.AddPair('replace', AReplace.ToJson);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

class function TAtlasSearchHistories.FromText(const AText: string; ASearch, AReplace: TAtlasSearchHistory): Boolean;
var
  Root: TJSONValue;
begin
  ASearch.Clear;
  AReplace.Clear;
  Root := TJSONObject.ParseJSONValue(AText);
  try
    Result := Root is TJSONObject;
    if not Result then
      Exit;
    ASearch.LoadFromJson(TJSONObject(Root).GetValue('search'));
    AReplace.LoadFromJson(TJSONObject(Root).GetValue('replace'));
  finally
    Root.Free;
  end;
end;

end.
