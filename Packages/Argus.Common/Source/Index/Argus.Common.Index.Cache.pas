unit Argus.Common.Index.Cache;

// Festplatten-Cache des Symbolindex als JSON. Je Unit stehen Zeitstempel
// und Hash darin; beim Start werden nur geänderte Dateien neu eingelesen.
// Ein Cache mit anderer Formatversion wird verworfen.
//
// Kurze Schlüssel halten die Datei klein:
//   {"version":1,"units":[{"u":"Name","f":"Datei","t":Stamp,"h":"Hash",
//     "iu":[...],"mu":[...],"s":[[Name,Container,Art,
//     L1,C1,L2,C2, SL1,SC1,SL2,SC2, InInterface, [Vorfahren], Typ], ...]}]}

interface

uses
  System.SysUtils,
  Argus.Common.Index.Contract;

type
  TIndexCache = class
  public
    const FormatVersion = 2;
    class function Serialize(const AUnits: TArray<TUnitIndex>): string; static;
    /// <summary>Liest den Cache; bei falscher Version oder kaputtem JSON leer.</summary>
    class function Deserialize(const AText: string): TArray<TUnitIndex>; static;
    /// <summary>Hash eines Dateiinhalts.</summary>
    class function HashOf(const AText: string): string; static;
  end;

implementation

uses
  System.JSON,
  System.Hash,
  System.Generics.Collections,
  Argus.Common.Documents.Contract;

function StringsToJson(const AValues: TArray<string>): TJSONArray;
var
  Value: string;
begin
  Result := TJSONArray.Create;
  for Value in AValues do
    Result.Add(Value);
end;

function JsonToStrings(AValue: TJSONValue): TArray<string>;
var
  Items: TJSONArray;
  Index: Integer;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
    Exit;
  Items := TJSONArray(AValue);
  SetLength(Result, Items.Count);
  for Index := 0 to Items.Count - 1 do
    Result[Index] := Items.Items[Index].Value;
end;

function IntAt(AItems: TJSONArray; AIndex: Integer): Integer;
begin
  Result := StrToIntDef(AItems.Items[AIndex].Value, 0);
end;

function SymbolToJson(const ASymbol: TIndexSymbol): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add(ASymbol.Name);
  Result.Add(ASymbol.Container);
  Result.Add(Ord(ASymbol.Kind));
  Result.Add(ASymbol.Range.StartPos.Line);
  Result.Add(ASymbol.Range.StartPos.Character);
  Result.Add(ASymbol.Range.EndPos.Line);
  Result.Add(ASymbol.Range.EndPos.Character);
  Result.Add(ASymbol.SelectionRange.StartPos.Line);
  Result.Add(ASymbol.SelectionRange.StartPos.Character);
  Result.Add(ASymbol.SelectionRange.EndPos.Line);
  Result.Add(ASymbol.SelectionRange.EndPos.Character);
  Result.Add(ASymbol.InInterface);
  Result.AddElement(StringsToJson(ASymbol.Ancestors));
  Result.Add(ASymbol.TypeName);
end;

function JsonToSymbol(AItems: TJSONArray; out ASymbol: TIndexSymbol): Boolean;
var
  Kind: Integer;
begin
  Result := AItems.Count >= 14;
  if not Result then
    Exit;
  Kind := IntAt(AItems, 2);
  if (Kind < Ord(Low(TIndexSymbolKind))) or (Kind > Ord(High(TIndexSymbolKind))) then
    Exit(False);
  ASymbol.Name := AItems.Items[0].Value;
  ASymbol.Container := AItems.Items[1].Value;
  ASymbol.Kind := TIndexSymbolKind(Kind);
  ASymbol.Range := TTextRange.Create(TTextPosition.Create(IntAt(AItems, 3), IntAt(AItems, 4)),
    TTextPosition.Create(IntAt(AItems, 5), IntAt(AItems, 6)));
  ASymbol.SelectionRange := TTextRange.Create(TTextPosition.Create(IntAt(AItems, 7), IntAt(AItems, 8)),
    TTextPosition.Create(IntAt(AItems, 9), IntAt(AItems, 10)));
  ASymbol.InInterface := (AItems.Items[11] is TJSONBool) and TJSONBool(AItems.Items[11]).AsBoolean;
  ASymbol.Ancestors := JsonToStrings(AItems.Items[12]);
  ASymbol.TypeName := AItems.Items[13].Value;
end;

{ TIndexCache }

class function TIndexCache.HashOf(const AText: string): string;
begin
  Result := THashFNV1a32.GetHashString(AText) + IntToHex(Length(AText), 1);
end;

class function TIndexCache.Serialize(const AUnits: TArray<TUnitIndex>): string;
var
  Root, Item: TJSONObject;
  Units, Symbols: TJSONArray;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('version', TJSONNumber.Create(FormatVersion));
    Units := TJSONArray.Create;
    Root.AddPair('units', Units);
    for UnitIndex in AUnits do
    begin
      Item := TJSONObject.Create;
      Units.AddElement(Item);
      Item.AddPair('u', UnitIndex.UnitName);
      Item.AddPair('f', UnitIndex.FileName);
      Item.AddPair('t', TJSONNumber.Create(UnitIndex.Stamp));
      Item.AddPair('h', UnitIndex.Hash);
      Item.AddPair('iu', StringsToJson(UnitIndex.InterfaceUses));
      Item.AddPair('mu', StringsToJson(UnitIndex.ImplementationUses));
      Symbols := TJSONArray.Create;
      Item.AddPair('s', Symbols);
      for Symbol in UnitIndex.Symbols do
        Symbols.AddElement(SymbolToJson(Symbol));
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

class function TIndexCache.Deserialize(const AText: string): TArray<TUnitIndex>;
var
  Root: TJSONValue;
  Units, Symbols: TJSONArray;
  Item: TJSONObject;
  Value: TJSONValue;
  Index, SymbolIndex: Integer;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  Found: TList<TUnitIndex>;
  SymbolList: TList<TIndexSymbol>;
begin
  Result := nil;
  if AText = '' then
    Exit;
  Root := TJSONObject.ParseJSONValue(AText);
  if Root = nil then
    Exit;
  Found := TList<TUnitIndex>.Create;
  SymbolList := TList<TIndexSymbol>.Create;
  try
    if not (Root is TJSONObject) then
      Exit;
    Value := TJSONObject(Root).GetValue('version');
    if not (Value is TJSONNumber) or (TJSONNumber(Value).AsInt <> FormatVersion) then
      Exit;
    Value := TJSONObject(Root).GetValue('units');
    if not (Value is TJSONArray) then
      Exit;
    Units := TJSONArray(Value);
    for Index := 0 to Units.Count - 1 do
    begin
      if not (Units.Items[Index] is TJSONObject) then
        Continue;
      Item := TJSONObject(Units.Items[Index]);
      UnitIndex := Default(TUnitIndex);
      UnitIndex.UnitName := Item.GetValue<string>('u', '');
      UnitIndex.FileName := Item.GetValue<string>('f', '');
      UnitIndex.Stamp := Item.GetValue<Int64>('t', 0);
      UnitIndex.Hash := Item.GetValue<string>('h', '');
      UnitIndex.InterfaceUses := JsonToStrings(Item.GetValue('iu'));
      UnitIndex.ImplementationUses := JsonToStrings(Item.GetValue('mu'));
      SymbolList.Clear;
      Value := Item.GetValue('s');
      if Value is TJSONArray then
      begin
        Symbols := TJSONArray(Value);
        for SymbolIndex := 0 to Symbols.Count - 1 do
          if (Symbols.Items[SymbolIndex] is TJSONArray) and
            JsonToSymbol(TJSONArray(Symbols.Items[SymbolIndex]), Symbol) then
            SymbolList.Add(Symbol);
      end;
      UnitIndex.Symbols := SymbolList.ToArray;
      if UnitIndex.FileName <> '' then
        Found.Add(UnitIndex);
    end;
    Result := Found.ToArray;
  finally
    SymbolList.Free;
    Found.Free;
    Root.Free;
  end;
end;

end.
