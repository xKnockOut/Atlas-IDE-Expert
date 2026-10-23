unit Atlas.Core.Welcome.HostLayout;

// Raster der Willkommensseite der IDE (#753), ohne Windows: So speichert
// RAD Studio (12 und 13) das Layout unter …\BDS\<Version>\WelcomePage:
//   Layout             RowsCount, ColumnsCount (DWORD)
//   Layout\Item <n>    PluginID (Text), Row, Column, RowSpan, ColumnSpan (DWORD)
//   AvailablePlugins   "0", "1", … = Kennungen der ausgeblendeten Bereiche
// TAtlasHostLayout liest und schreibt das auf einem TAtlasRegKey (Kopie des
// Schlüssels WelcomePage). Seit #1114 meldet Atlas keine Bereiche mehr auf der
// Willkommensseite der IDE an; WithoutAtlas nimmt die Kennungen früherer
// Fassungen aus Raster und Liste der ausgeblendeten und lässt leere Zeilen
// zusammenrücken. TAtlasWelcomeRetire räumt damit beim Start einmal auf:
// Gibt es noch die Sicherung von „Atlas-Layout anwenden“, gilt sie, sonst das
// Raster ohne Atlas.

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
  public
    Rows: Integer;
    Columns: Integer;
    Items: TArray<TAtlasHostItem>;
    /// <summary>Ausgeblendete Bereiche (Kennungen).</summary>
    Available: TArray<string>;
    /// <summary>False, wenn AWelcomeKey kein Raster enthält (die IDE nutzt dann ihre Vorgabe).</summary>
    class function Read(AWelcomeKey: TAtlasRegKey; out ALayout: TAtlasHostLayout): Boolean; static;
    /// <summary>Ersetzt Layout und AvailablePlugins in AWelcomeKey; andere Werte bleiben. Ohne Bereiche
    /// entfällt das Raster, die IDE zeigt dann ihre Vorgabe.</summary>
    procedure WriteTo(AWelcomeKey: TAtlasRegKey);
    function IndexOf(const APluginId: string): Integer;
    function Contains(const APluginId: string): Boolean;
    /// <summary>Steht ein Bereich mit der Kennung APrefix… im Raster oder unter den ausgeblendeten?</summary>
    function ContainsAtlas(const APrefix: string): Boolean;
    /// <summary>Raster ohne Bereiche mit der Kennung APrefix…; Zeilen, die danach leer sind, entfallen und
    /// die Bereiche darunter rücken nach oben.</summary>
    function WithoutAtlas(const APrefix: string): TAtlasHostLayout;
  end;

  TAtlasRetireResult = (Nothing, Restored, Removed);

  /// <summary>Atlas-Bereiche früherer Fassungen von der Willkommensseite der IDE nehmen (#1114).</summary>
  TAtlasWelcomeRetire = record
  public
    /// <summary>ABackup (Sicherung von „Atlas-Layout anwenden“, leer = keine) zurückschreiben; sonst die
    /// Kennungen APrefix… aus dem Schlüssel AWelcomePath nehmen. ASnapshot ist danach der gewünschte Stand
    /// (für die Marke, falls die IDE ihr Layout beim Beenden zurückschreibt); leer bei Nothing.</summary>
    class function Run(const AAccess: IAtlasRegistryAccess; const AWelcomePath, ABackup, APrefix: string;
      out ASnapshot: string): TAtlasRetireResult; static;
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
  if Items = nil then
    Exit;
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

function TAtlasHostLayout.ContainsAtlas(const APrefix: string): Boolean;
var
  Item: TAtlasHostItem;
  Id: string;
begin
  Result := True;
  for Item in Items do
    if StartsWith(Item.PluginId, APrefix) then
      Exit;
  for Id in Available do
    if StartsWith(Id, APrefix) then
      Exit;
  Result := False;
end;

function TAtlasHostLayout.WithoutAtlas(const APrefix: string): TAtlasHostLayout;
var
  Item: TAtlasHostItem;
  Id: string;
  Covered: TArray<Boolean>;
  NewRow: TArray<Integer>;
  Row, Count, Last, Index: Integer;
begin
  Result.Columns := Columns;
  Result.Items := nil;
  for Item in Items do
    if not StartsWith(Item.PluginId, APrefix) then
      Result.Items := Result.Items + [Item];
  Result.Available := nil;
  for Id in Available do
    if not StartsWith(Id, APrefix) then
      Result.Available := Result.Available + [Id];
  // Belegte Zeilen bestimmen; Bereiche, die über das Raster hinausragen, vergrößern es.
  Last := Rows;
  for Item in Result.Items do
    if Item.Row + Item.RowSpan > Last then
      Last := Item.Row + Item.RowSpan;
  SetLength(Covered, Last);
  for Row := 0 to Last - 1 do
    Covered[Row] := False;
  for Item in Result.Items do
    for Row := Item.Row to Item.Row + Item.RowSpan - 1 do
      if Row >= 0 then
        Covered[Row] := True;
  // Neue Zeile je alter: Leere Zeilen fallen weg, die folgenden rücken nach.
  SetLength(NewRow, Last);
  Count := 0;
  for Row := 0 to Last - 1 do
  begin
    NewRow[Row] := Count;
    if Covered[Row] then
      Inc(Count);
  end;
  for Index := 0 to High(Result.Items) do
    if Result.Items[Index].Row >= 0 then
      Result.Items[Index].Row := NewRow[Result.Items[Index].Row];
  Result.Rows := Count;
end;

{ TAtlasWelcomeRetire }

class function TAtlasWelcomeRetire.Run(const AAccess: IAtlasRegistryAccess; const AWelcomePath, ABackup,
  APrefix: string; out ASnapshot: string): TAtlasRetireResult;
var
  Key: TAtlasRegKey;
  Layout, Cleaned: TAtlasHostLayout;
begin
  ASnapshot := '';
  Result := TAtlasRetireResult.Nothing;
  // Die Sicherung hält das Layout von vor Atlas; ist sie lesbar, gilt sie.
  if (ABackup <> '') and TAtlasWelcomeBackup.Restore(AAccess, ABackup) then
  begin
    ASnapshot := ABackup;
    Result := TAtlasRetireResult.Restored;
    Exit;
  end;
  Key := AAccess.Read(AWelcomePath);
  try
    if (Key = nil) or not TAtlasHostLayout.Read(Key, Layout) or not Layout.ContainsAtlas(APrefix) then
      Exit;
    Cleaned := Layout.WithoutAtlas(APrefix);
    Cleaned.WriteTo(Key);
    AAccess.Replace(AWelcomePath, Key);
  finally
    Key.Free;
  end;
  ASnapshot := TAtlasWelcomeBackup.Snapshot(AAccess, AWelcomePath);
  Result := TAtlasRetireResult.Removed;
end;

end.
