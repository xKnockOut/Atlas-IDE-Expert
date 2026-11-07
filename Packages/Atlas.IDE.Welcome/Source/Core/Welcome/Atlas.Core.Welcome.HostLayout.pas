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
// WithoutAtlas nimmt alle Atlas-Kennungen aus Raster und Liste der
// ausgeblendeten und lässt leere Zeilen zusammenrücken. TAtlasWelcomeRetire
// räumt damit auf, solange Atlas nicht auf der Willkommensseite der IDE
// stehen soll (welcomePage.ideWelcomePage aus, #761; bis dahin #1114): Gibt es
// die Sicherung von „Atlas-Layout anwenden“, gilt sie, sonst das Raster ohne
// Atlas.

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
    cLayoutKey = 'Layout';
    cAvailableKey = 'AvailablePlugins';
    cItemPrefix = 'Item ';
    /// <summary>Höhe des Bereichs „Atlas“ in Rasterzeilen.</summary>
    cBoardRows = 2;
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
    /// <summary>Atlas-Layout: ABoardId oben über alle Spalten, übrige Bereiche darunter, Plugins mit
    /// APrefix (einzelne Atlas-Bereiche) entfernt.</summary>
    function WithAtlasOnTop(const ABoardId, APrefix: string): TAtlasHostLayout;
    /// <summary>Steht ABoardId oben über alle Spalten und fehlen einzelne Atlas-Bereiche (APrefix)?</summary>
    function HasAtlasOnTop(const ABoardId, APrefix: string): Boolean;
    /// <summary>Vorgabe der IDE (RAD Studio 12/13), wenn die Registry noch kein Raster enthält:
    /// „Neu in GetIt“, „Zuletzt geöffnet“, „Lernen“ nebeneinander, je zwei Zeilen hoch.</summary>
    class function IdeDefault: TAtlasHostLayout; static;
  end;

  TAtlasRetireResult = (Nothing, Restored, Removed);

  /// <summary>Atlas-Bereiche von der Willkommensseite der IDE nehmen (#1114, #761).</summary>
  TAtlasWelcomeRetire = record
  public
    /// <summary>ABackup (Sicherung von „Atlas-Layout anwenden“, leer = keine) zurückschreiben; sonst die
    /// Kennungen APrefix… aus dem Schlüssel AWelcomePath nehmen. ASnapshot ist danach der gewünschte Stand
    /// (für die Marke, falls die IDE ihr Layout beim Beenden zurückschreibt); leer bei Nothing.</summary>
    class function Run(const AAccess: IAtlasRegistryAccess; const AWelcomePath, ABackup, APrefix: string;
      out ASnapshot: string): TAtlasRetireResult; static;
  end;

  /// <summary>Was beim Umschalten in den Optionen auf der Willkommensseite der IDE geschieht (#761).</summary>
  TAtlasIdePageStep = (None, Retire, PlaceBoard, Unplace, ClearPending);

  TAtlasIdePageSteps = record
  public
    /// <summary>Schritte nach einem Sync. AStarted: nicht der erste Sync (beim Start gilt, was die IDE aus der
    /// Registry liest); AWasShown/AShown: Atlas-Bereiche auf der Willkommensseite der IDE vorher/jetzt
    /// gewollt; ALastLayout/ALayout: welcomePage.layout vorher/jetzt.</summary>
    class function After(AStarted, AWasShown, AShown: Boolean; const ALastLayout, ALayout: string)
      : TArray<TAtlasIdePageStep>; static;
  end;

implementation

uses
  System.Math;

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
  mValue: TAtlasRegValue;
begin
  Result := ADefault;
  if AKey.FindValue(AName, mValue) and (mValue.Kind in [TAtlasRegKind.Number, TAtlasRegKind.Number64]) then
  begin
    Result := StrToIntDef(mValue.Data, ADefault);
  end;
end;

function TextOf(AKey: TAtlasRegKey; const AName: string): string;
var
  mValue: TAtlasRegValue;
begin
  Result := '';
  if AKey.FindValue(AName, mValue) and (mValue.Kind in [TAtlasRegKind.Text, TAtlasRegKind.ExpandText]) then
  begin
    Result := mValue.Data;
  end;
end;

function Number(const AName: string; AValue: Integer): TAtlasRegValue;
begin
  Result := TAtlasRegValue.Create(AName, TAtlasRegKind.Number, IntToStr(AValue));
end;

class function TAtlasHostLayout.Read(AWelcomeKey: TAtlasRegKey; out ALayout: TAtlasHostLayout): Boolean;
var
  mLayout, mAvailable, mItem: TAtlasRegKey;
  mValue: TAtlasRegValue;
  mIndex: Integer;
  mId: string;
begin
  ALayout.Rows := 0;
  ALayout.Columns := 0;
  ALayout.Items := nil;
  ALayout.Available := nil;
  Result := False;
  if AWelcomeKey = nil then
  begin
    Exit;
  end;
  mLayout := AWelcomeKey.FindKey(cLayoutKey);
  if mLayout = nil then
  begin
    Exit;
  end;
  ALayout.Rows := NumberOf(mLayout, 'RowsCount', 0);
  ALayout.Columns := NumberOf(mLayout, 'ColumnsCount', 0);
  // Nach der Nummer im Namen, damit die Reihenfolge der IDE erhalten bleibt.
  mIndex := 0;
  while True do
  begin
    mItem := mLayout.FindKey(cItemPrefix + IntToStr(mIndex));
    if mItem = nil then
    begin
      Break;
    end;
    mId := TextOf(mItem, 'PluginID');
    if mId <> '' then
    begin
      ALayout.Items := ALayout.Items + [TAtlasHostItem.Create(mId, NumberOf(mItem, 'Row', 0),
        NumberOf(mItem, 'Column', 0), NumberOf(mItem, 'RowSpan', 1), NumberOf(mItem, 'ColumnSpan', 1))];
    end;
    Inc(mIndex);
  end;
  mAvailable := AWelcomeKey.FindKey(cAvailableKey);
  if mAvailable <> nil then
  begin
    mIndex := 0;
    while mAvailable.FindValue(IntToStr(mIndex), mValue) do
    begin
      if mValue.Data <> '' then
      begin
        ALayout.Available := ALayout.Available + [mValue.Data];
      end;
      Inc(mIndex);
    end;
  end;
  Result := (ALayout.Rows > 0) and (ALayout.Columns > 0);
end;

procedure TAtlasHostLayout.WriteTo(AWelcomeKey: TAtlasRegKey);
var
  mLayout, mAvailable, mKey: TAtlasRegKey;
  mIndex: Integer;
begin
  mIndex := AWelcomeKey.Keys.IndexOf(AWelcomeKey.FindKey(cLayoutKey));
  if mIndex >= 0 then
  begin
    AWelcomeKey.Keys.Delete(mIndex);
  end;
  mIndex := AWelcomeKey.Keys.IndexOf(AWelcomeKey.FindKey(cAvailableKey));
  if mIndex >= 0 then
  begin
    AWelcomeKey.Keys.Delete(mIndex);
  end;
  mAvailable := AWelcomeKey.AddKey(cAvailableKey);
  for mIndex := 0 to High(Self.Available) do
  begin
    mAvailable.SetValue(TAtlasRegValue.Create(IntToStr(mIndex), TAtlasRegKind.Text, Self.Available[mIndex]));
  end;
  if Items = nil then
  begin
    Exit;
  end;
  mLayout := AWelcomeKey.AddKey(cLayoutKey);
  mLayout.SetValue(Number('RowsCount', Rows));
  mLayout.SetValue(Number('ColumnsCount', Columns));
  for mIndex := 0 to High(Items) do
  begin
    mKey := mLayout.AddKey(cItemPrefix + IntToStr(mIndex));
    mKey.SetValue(TAtlasRegValue.Create('PluginID', TAtlasRegKind.Text, Items[mIndex].PluginId));
    mKey.SetValue(Number('Row', Items[mIndex].Row));
    mKey.SetValue(Number('Column', Items[mIndex].Column));
    mKey.SetValue(Number('RowSpan', Items[mIndex].RowSpan));
    mKey.SetValue(Number('ColumnSpan', Items[mIndex].ColumnSpan));
  end;
end;

function TAtlasHostLayout.IndexOf(const APluginId: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Items) do
  begin
    if SameText(Items[mIndex].PluginId, APluginId) then
    begin
      Exit(mIndex);
    end;
  end;
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
  mItem: TAtlasHostItem;
  mId: string;
begin
  Result := True;
  for mItem in Items do
  begin
    if StartsWith(mItem.PluginId, APrefix) then
    begin
      Exit;
    end;
  end;
  for mId in Available do
  begin
    if StartsWith(mId, APrefix) then
    begin
      Exit;
    end;
  end;
  Result := False;
end;

/// <summary>Belegte Zeilen von AItems; Bereiche, die über ARows hinausragen, vergrößern das Raster.</summary>
function CoveredRows(const AItems: TArray<TAtlasHostItem>; ARows: Integer): TArray<Boolean>;
var
  mItem: TAtlasHostItem;
  mRow, mLast: Integer;
begin
  mLast := ARows;
  for mItem in AItems do
  begin
    mLast := Max(mLast, mItem.Row + mItem.RowSpan);
  end;
  SetLength(Result, mLast);
  for mRow := 0 to mLast - 1 do
  begin
    Result[mRow] := False;
  end;
  for mItem in AItems do
  begin
    for mRow := Max(0, mItem.Row) to mItem.Row + mItem.RowSpan - 1 do
    begin
      Result[mRow] := True;
    end;
  end;
end;

/// <summary>Leere Zeilen von ALayout fallen weg, die folgenden rücken nach.</summary>
procedure CompactRows(var ALayout: TAtlasHostLayout);
var
  mCovered: TArray<Boolean>;
  mNewRow: TArray<Integer>;
  mRow, mCount, mIndex: Integer;
begin
  mCovered := CoveredRows(ALayout.Items, ALayout.Rows);
  SetLength(mNewRow, Length(mCovered));
  mCount := 0;
  for mRow := 0 to High(mCovered) do
  begin
    mNewRow[mRow] := mCount;
    if mCovered[mRow] then
    begin
      Inc(mCount);
    end;
  end;
  for mIndex := 0 to High(ALayout.Items) do
  begin
    if ALayout.Items[mIndex].Row >= 0 then
    begin
      ALayout.Items[mIndex].Row := mNewRow[ALayout.Items[mIndex].Row];
    end;
  end;
  ALayout.Rows := mCount;
end;

function TAtlasHostLayout.WithoutAtlas(const APrefix: string): TAtlasHostLayout;
var
  mItem: TAtlasHostItem;
  mId: string;
begin
  Result.Columns := Columns;
  Result.Rows := Rows;
  Result.Items := nil;
  for mItem in Items do
  begin
    if not StartsWith(mItem.PluginId, APrefix) then
    begin
      Result.Items := Result.Items + [mItem];
    end;
  end;
  Result.Available := nil;
  for mId in Available do
  begin
    if not StartsWith(mId, APrefix) then
    begin
      Result.Available := Result.Available + [mId];
    end;
  end;
  CompactRows(Result);
end;

function TAtlasHostLayout.WithAtlasOnTop(const ABoardId, APrefix: string): TAtlasHostLayout;
var
  mItem: TAtlasHostItem;
  mId: string;
begin
  Result.Columns := Columns;
  if Result.Columns < 1 then
  begin
    Result.Columns := 1;
  end;
  Result.Rows := Rows + cBoardRows;
  Result.Items := [TAtlasHostItem.Create(ABoardId, 0, 0, cBoardRows, Result.Columns)];
  for mItem in Items do
  begin
    if not SameText(mItem.PluginId, ABoardId) and not StartsWith(mItem.PluginId, APrefix) then
    begin
      Result.Items := Result.Items + [TAtlasHostItem.Create(mItem.PluginId, mItem.Row + cBoardRows, mItem.Column,
        mItem.RowSpan, mItem.ColumnSpan)];
    end;
  end;
  Result.Available := nil;
  for mId in Available do
  begin
    if not SameText(mId, ABoardId) and not StartsWith(mId, APrefix) then
    begin
      Result.Available := Result.Available + [mId];
    end;
  end;
end;

function TAtlasHostLayout.HasAtlasOnTop(const ABoardId, APrefix: string): Boolean;
var
  mIndex: Integer;
  mItem: TAtlasHostItem;
  mId: string;
begin
  mIndex := IndexOf(ABoardId);
  if mIndex < 0 then
  begin
    Exit(False);
  end;
  mItem := Items[mIndex];
  if (mItem.Row <> 0) or (mItem.Column <> 0) or (mItem.ColumnSpan < Columns) then
  begin
    Exit(False);
  end;
  for mItem in Items do
  begin
    if not SameText(mItem.PluginId, ABoardId) and StartsWith(mItem.PluginId, APrefix) then
    begin
      Exit(False);
    end;
  end;
  for mId in Available do
  begin
    if SameText(mId, ABoardId) then
    begin
      Exit(False);
    end;
  end;
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

{ TAtlasIdePageSteps }

class function TAtlasIdePageSteps.After(AStarted, AWasShown, AShown: Boolean; const ALastLayout, ALayout: string)
  : TArray<TAtlasIdePageStep>;
var
  mAtlas: Boolean;
begin
  Result := nil;
  if not AStarted then
  begin
    Exit;
  end;
  mAtlas := SameText(ALayout, 'atlas');
  if AWasShown and not AShown then
  begin
    // Abgeschaltet: Sicherung zurück bzw. Atlas aus dem Raster der IDE nehmen.
    Result := [TAtlasIdePageStep.Retire];
  end
  else if AShown and not AWasShown then
  begin
    // Wieder eingeschaltet: Der beim Abschalten gemerkte Stand ohne Atlas gilt nicht mehr.
    Result := [TAtlasIdePageStep.ClearPending];
    if mAtlas then
    begin
      Result := Result + [TAtlasIdePageStep.PlaceBoard];
    end;
  end
  else if AShown and not SameText(ALastLayout, ALayout) then
  begin
    if mAtlas then
    begin
      Result := [TAtlasIdePageStep.PlaceBoard];
    end
    else
    begin
      Result := [TAtlasIdePageStep.Unplace];
    end;
  end;
end;

{ TAtlasWelcomeRetire }

class function TAtlasWelcomeRetire.Run(const AAccess: IAtlasRegistryAccess; const AWelcomePath, ABackup,
  APrefix: string; out ASnapshot: string): TAtlasRetireResult;
var
  mKey: TAtlasRegKey;
  mLayout, mCleaned: TAtlasHostLayout;
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
  mKey := AAccess.Read(AWelcomePath);
  try
    if (mKey = nil) or not TAtlasHostLayout.Read(mKey, mLayout) or not mLayout.ContainsAtlas(APrefix) then
    begin
      Exit;
    end;
    mCleaned := mLayout.WithoutAtlas(APrefix);
    mCleaned.WriteTo(mKey);
    AAccess.Replace(AWelcomePath, mKey);
  finally
    mKey.Free;
  end;
  ASnapshot := TAtlasWelcomeBackup.Snapshot(AAccess, AWelcomePath);
  Result := TAtlasRetireResult.Removed;
end;

end.
