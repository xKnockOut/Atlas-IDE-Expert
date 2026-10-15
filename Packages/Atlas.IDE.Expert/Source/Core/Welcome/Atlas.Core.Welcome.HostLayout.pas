unit Atlas.Core.Welcome.HostLayout;

// Raster der Willkommensseite der IDE (#753), ohne Windows: So speichert
// RAD Studio (12 und 13) das Layout unter …\BDS\<Version>\WelcomePage:
//   Layout             RowsCount, ColumnsCount (DWORD)
//   Layout\Item <n>    PluginID (Text), Row, Column, RowSpan, ColumnSpan (DWORD)
//   AvailablePlugins   "0", "1", … = Kennungen der ausgeblendeten Bereiche
// TAtlasHostLayout liest und schreibt das auf einem TAtlasRegKey (Kopie des
// Schlüssels WelcomePage). WithAtlasOnTop baut das Atlas-Layout: Der Bereich
// „Atlas“ (alle Atlas-Bereiche in einem Frame) steht oben über die ganze
// Breite, alle übrigen Bereiche rücken um seine Höhe nach unten, einzelne
// Atlas-Bereiche verschwinden aus Raster und Liste der ausgeblendeten.

interface

uses
  System.SysUtils,
  Atlas.Core.Welcome.Backup;

type
  TAtlasHostItem = record
    PluginId: string;
    Row, Column, RowSpan, ColumnSpan: Integer;
    class function Create(const APluginId: string; ARow, AColumn, ARowSpan, AColumnSpan: Integer): TAtlasHostItem;
      static;
  end;

  TAtlasHostLayout = record
  public const
    LayoutKey = 'Layout';
    AvailableKey = 'AvailablePlugins';
    ItemPrefix = 'Item ';
    /// <summary>Höhe des Bereichs „Atlas“ in Rasterzeilen.</summary>
    BoardRows = 2;
  public
    Rows: Integer;
    Columns: Integer;
    Items: TArray<TAtlasHostItem>;
    /// <summary>Ausgeblendete Bereiche (Kennungen).</summary>
    Available: TArray<string>;
    /// <summary>False, wenn AWelcomeKey kein Raster enthält (die IDE nutzt dann ihre Vorgabe).</summary>
    class function Read(AWelcomeKey: TAtlasRegKey; out ALayout: TAtlasHostLayout): Boolean; static;
    /// <summary>Ersetzt Layout und AvailablePlugins in AWelcomeKey; andere Werte bleiben.</summary>
    procedure WriteTo(AWelcomeKey: TAtlasRegKey);
    function IndexOf(const APluginId: string): Integer;
    function Contains(const APluginId: string): Boolean;
    /// <summary>Atlas-Layout: ABoardId oben über alle Spalten, übrige Bereiche darunter, Plugins mit
    /// APrefix (einzelne Atlas-Bereiche) entfernt.</summary>
    function WithAtlasOnTop(const ABoardId, APrefix: string): TAtlasHostLayout;
    /// <summary>Steht ABoardId oben über alle Spalten und fehlen einzelne Atlas-Bereiche (APrefix)?</summary>
    function HasAtlasOnTop(const ABoardId, APrefix: string): Boolean;
    /// <summary>Vorgabe der IDE (RAD Studio 12/13), wenn die Registry noch kein Raster enthält:
    /// „Neu in GetIt“, „Zuletzt geöffnet“, „Lernen“ nebeneinander, je zwei Zeilen hoch.</summary>
    class function IdeDefault: TAtlasHostLayout; static;
  end;

implementation

{ TAtlasHostItem }

class function TAtlasHostItem.Create(const APluginId: string; ARow, AColumn, ARowSpan,
  AColumnSpan: Integer): TAtlasHostItem;
begin
  Result.PluginId := APluginId;
  Result.Row := ARow;
  Result.Column := AColumn;
  Result.RowSpan := ARowSpan;
  Result.ColumnSpan := AColumnSpan;
end;

{ TAtlasHostLayout }

function NumberOf(AKey: TAtlasRegKey; const AName: string; ADefault: Integer): Integer;
var
  Value: TAtlasRegValue;
begin
  Result := ADefault;
  if AKey.FindValue(AName, Value) and (Value.Kind in [TAtlasRegKind.Number, TAtlasRegKind.Number64]) then
    Result := StrToIntDef(Value.Data, ADefault);
end;

function TextOf(AKey: TAtlasRegKey; const AName: string): string;
var
  Value: TAtlasRegValue;
begin
  Result := '';
  if AKey.FindValue(AName, Value) and (Value.Kind in [TAtlasRegKind.Text, TAtlasRegKind.ExpandText]) then
    Result := Value.Data;
end;

function Number(const AName: string; AValue: Integer): TAtlasRegValue;
begin
  Result := TAtlasRegValue.Create(AName, TAtlasRegKind.Number, IntToStr(AValue));
end;

class function TAtlasHostLayout.Read(AWelcomeKey: TAtlasRegKey; out ALayout: TAtlasHostLayout): Boolean;
var
  Layout, Available, Item: TAtlasRegKey;
  Value: TAtlasRegValue;
  Index: Integer;
  Id: string;
begin
  ALayout.Rows := 0;
  ALayout.Columns := 0;
  ALayout.Items := nil;
  ALayout.Available := nil;
  Result := False;
  if AWelcomeKey = nil then
    Exit;
  Layout := AWelcomeKey.FindKey(LayoutKey);
  if Layout = nil then
    Exit;
  ALayout.Rows := NumberOf(Layout, 'RowsCount', 0);
  ALayout.Columns := NumberOf(Layout, 'ColumnsCount', 0);
  // Nach der Nummer im Namen, damit die Reihenfolge der IDE erhalten bleibt.
  Index := 0;
  while True do
  begin
    Item := Layout.FindKey(ItemPrefix + IntToStr(Index));
    if Item = nil then
      Break;
    Id := TextOf(Item, 'PluginID');
    if Id <> '' then
      ALayout.Items := ALayout.Items + [TAtlasHostItem.Create(Id, NumberOf(Item, 'Row', 0),
        NumberOf(Item, 'Column', 0), NumberOf(Item, 'RowSpan', 1), NumberOf(Item, 'ColumnSpan', 1))];
    Inc(Index);
  end;
  Available := AWelcomeKey.FindKey(AvailableKey);
  if Available <> nil then
  begin
    Index := 0;
    while Available.FindValue(IntToStr(Index), Value) do
    begin
      if Value.Data <> '' then
        ALayout.Available := ALayout.Available + [Value.Data];
      Inc(Index);
    end;
  end;
  Result := (ALayout.Rows > 0) and (ALayout.Columns > 0);
end;

procedure TAtlasHostLayout.WriteTo(AWelcomeKey: TAtlasRegKey);
var
  Layout, Available, Key: TAtlasRegKey;
  Index: Integer;
begin
  Index := AWelcomeKey.Keys.IndexOf(AWelcomeKey.FindKey(LayoutKey));
  if Index >= 0 then
    AWelcomeKey.Keys.Delete(Index);
  Index := AWelcomeKey.Keys.IndexOf(AWelcomeKey.FindKey(AvailableKey));
  if Index >= 0 then
    AWelcomeKey.Keys.Delete(Index);
  Available := AWelcomeKey.AddKey(AvailableKey);
  for Index := 0 to High(Self.Available) do
    Available.SetValue(TAtlasRegValue.Create(IntToStr(Index), TAtlasRegKind.Text, Self.Available[Index]));
  Layout := AWelcomeKey.AddKey(LayoutKey);
  Layout.SetValue(Number('RowsCount', Rows));
  Layout.SetValue(Number('ColumnsCount', Columns));
  for Index := 0 to High(Items) do
  begin
    Key := Layout.AddKey(ItemPrefix + IntToStr(Index));
    Key.SetValue(TAtlasRegValue.Create('PluginID', TAtlasRegKind.Text, Items[Index].PluginId));
    Key.SetValue(Number('Row', Items[Index].Row));
    Key.SetValue(Number('Column', Items[Index].Column));
    Key.SetValue(Number('RowSpan', Items[Index].RowSpan));
    Key.SetValue(Number('ColumnSpan', Items[Index].ColumnSpan));
  end;
end;

function TAtlasHostLayout.IndexOf(const APluginId: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Items) do
    if SameText(Items[Index].PluginId, APluginId) then
      Exit(Index);
  Result := -1;
end;

function TAtlasHostLayout.Contains(const APluginId: string): Boolean;
begin
  Result := IndexOf(APluginId) >= 0;
end;

function StartsWith(const AText, APrefix: string): Boolean;
begin
  Result := (APrefix <> '') and SameText(Copy(AText, 1, Length(APrefix)), APrefix);
end;

function TAtlasHostLayout.WithAtlasOnTop(const ABoardId, APrefix: string): TAtlasHostLayout;
var
  Item: TAtlasHostItem;
  Id: string;
begin
  Result.Columns := Columns;
  if Result.Columns < 1 then
    Result.Columns := 1;
  Result.Rows := Rows + BoardRows;
  Result.Items := [TAtlasHostItem.Create(ABoardId, 0, 0, BoardRows, Result.Columns)];
  for Item in Items do
    if not SameText(Item.PluginId, ABoardId) and not StartsWith(Item.PluginId, APrefix) then
      Result.Items := Result.Items + [TAtlasHostItem.Create(Item.PluginId, Item.Row + BoardRows, Item.Column,
        Item.RowSpan, Item.ColumnSpan)];
  Result.Available := nil;
  for Id in Available do
    if not SameText(Id, ABoardId) and not StartsWith(Id, APrefix) then
      Result.Available := Result.Available + [Id];
end;

function TAtlasHostLayout.HasAtlasOnTop(const ABoardId, APrefix: string): Boolean;
var
  Index: Integer;
  Item: TAtlasHostItem;
  Id: string;
begin
  Index := IndexOf(ABoardId);
  if Index < 0 then
    Exit(False);
  Item := Items[Index];
  if (Item.Row <> 0) or (Item.Column <> 0) or (Item.ColumnSpan < Columns) then
    Exit(False);
  for Item in Items do
    if not SameText(Item.PluginId, ABoardId) and StartsWith(Item.PluginId, APrefix) then
      Exit(False);
  for Id in Available do
    if SameText(Id, ABoardId) then
      Exit(False);
  Result := True;
end;

class function TAtlasHostLayout.IdeDefault: TAtlasHostLayout;
begin
  Result.Rows := 2;
  Result.Columns := 3;
  Result.Items := [TAtlasHostItem.Create('Embarcadero.WelcomePagePlugin.GetItNewIn', 0, 0, 2, 1),
    TAtlasHostItem.Create('Embarcadero.WelcomePagePlugin.OpenRecent', 0, 1, 2, 1),
    TAtlasHostItem.Create('Embarcadero.WelcomePagePlugin.Learn', 0, 2, 2, 1)];
  Result.Available := ['Embarcadero.WelcomePagePlugin.GetItPromoted', 'Embarcadero.WelcomePagePlugin.CreateNew'];
end;

end.
