unit Atlas.Core.Completion.Usage;

// Lernende Gewichtung (#418): Wie oft und wann zuletzt ein Eintrag übernommen
// wurde, je Paar (Typ, Member). Daraus ein Zuschlag unter 100 Punkten für die
// Rangfolge (TAtlasRanking) und die Marken „zuletzt“ (letzte Übernahme bei
// diesem Typ) und „häufig“ (ab 5 Übernahmen). Gespeichert als JSON
// (%APPDATA%\Atlas\usage.json, Pfad von der IDE-Schicht), höchstens 5.000
// Paare; die am längsten nicht genutzten werden verdrängt.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Completion.Contract;

type
  TAtlasUsage = class
  public const
    MaxEntries = 5000;
    FrequentCount = 5;
  private type
    TEntry = record
      Count: Integer;
      /// <summary>Laufende Nummer der letzten Übernahme (größer = jünger).</summary>
      Last: Int64;
    end;
  private
    FEntries: TDictionary<string, TEntry>;
    /// <summary>Je Typ der zuletzt übernommene Member.</summary>
    FRecent: TDictionary<string, string>;
    FClock: Int64;
    FChanged: Boolean;
    class function KeyOf(const AItem: TAtlasCompletionItem): string; static;
    class function TypeOf(const AItem: TAtlasCompletionItem): string; static;
    procedure Evict;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Übernahme von AItem merken.</summary>
    procedure Record_(const AItem: TAtlasCompletionItem);
    /// <summary>Zuschlag 0..90 für die Rangfolge.</summary>
    function Boost(const AItem: TAtlasCompletionItem): Integer;
    function Mark(const AItem: TAtlasCompletionItem): TAtlasUsageMark;
    function Count: Integer;
    procedure Clear;
    procedure LoadFromFile(const AFileName: string);
    procedure SaveToFile(const AFileName: string);
    /// <summary>Seit dem Laden bzw. Speichern geändert.</summary>
    property Changed: Boolean read FChanged;
  end;

implementation

uses
  System.Math,
  System.IOUtils,
  System.JSON,
  System.Generics.Defaults;

{ TAtlasUsage }

constructor TAtlasUsage.Create;
begin
  inherited Create;
  FEntries := TDictionary<string, TEntry>.Create;
  FRecent := TDictionary<string, string>.Create;
end;

destructor TAtlasUsage.Destroy;
begin
  FRecent.Free;
  FEntries.Free;
  inherited Destroy;
end;

class function TAtlasUsage.TypeOf(const AItem: TAtlasCompletionItem): string;
begin
  // Typ des Members; auf Unit-Ebene die Unit, sonst leer.
  Result := LowerCase(AItem.DeclaringClass);
  if Result = '' then
    Result := LowerCase(AItem.DeclaringUnit);
end;

class function TAtlasUsage.KeyOf(const AItem: TAtlasCompletionItem): string;
begin
  Result := TypeOf(AItem) + '|' + LowerCase(AItem.Name);
end;

procedure TAtlasUsage.Record_(const AItem: TAtlasCompletionItem);
var
  Entry: TEntry;
  Key: string;
begin
  Key := KeyOf(AItem);
  if not FEntries.TryGetValue(Key, Entry) then
    Entry := Default(TEntry);
  Inc(Entry.Count);
  Inc(FClock);
  Entry.Last := FClock;
  FEntries.AddOrSetValue(Key, Entry);
  FRecent.AddOrSetValue(TypeOf(AItem), LowerCase(AItem.Name));
  FChanged := True;
  if FEntries.Count > MaxEntries then
    Evict;
end;

procedure TAtlasUsage.Evict;
var
  Pairs: TArray<TPair<string, TEntry>>;
  Index: Integer;
begin
  // Älteste zuerst entfernen, bis wieder Platz ist (ein Zehntel Luft, damit nicht bei jeder Übernahme sortiert wird).
  Pairs := FEntries.ToArray;
  TArray.Sort<TPair<string, TEntry>>(Pairs, TComparer<TPair<string, TEntry>>.Construct(
    function(const A, B: TPair<string, TEntry>): Integer
    begin
      Result := CompareValue(A.Value.Last, B.Value.Last);
    end));
  for Index := 0 to Length(Pairs) - MaxEntries + MaxEntries div 10 - 1 do
    FEntries.Remove(Pairs[Index].Key);
end;

function TAtlasUsage.Boost(const AItem: TAtlasCompletionItem): Integer;
var
  Entry: TEntry;
begin
  Result := 0;
  if not FEntries.TryGetValue(KeyOf(AItem), Entry) then
    Exit;
  Result := Min(60, Entry.Count * 15);
  if Mark(AItem) = TAtlasUsageMark.Recent then
    Inc(Result, 30);
end;

function TAtlasUsage.Mark(const AItem: TAtlasCompletionItem): TAtlasUsageMark;
var
  Entry: TEntry;
  Name: string;
begin
  Result := TAtlasUsageMark.None;
  if FRecent.TryGetValue(TypeOf(AItem), Name) and (Name = LowerCase(AItem.Name)) then
    Exit(TAtlasUsageMark.Recent);
  if FEntries.TryGetValue(KeyOf(AItem), Entry) and (Entry.Count >= FrequentCount) then
    Result := TAtlasUsageMark.Frequent;
end;

function TAtlasUsage.Count: Integer;
begin
  Result := FEntries.Count;
end;

procedure TAtlasUsage.Clear;
begin
  FEntries.Clear;
  FRecent.Clear;
  FClock := 0;
  FChanged := True;
end;

procedure TAtlasUsage.LoadFromFile(const AFileName: string);
var
  Root: TJSONValue;
  Items: TJSONArray;
  Value: TJSONValue;
  Item: TJSONObject;
  Entry: TEntry;
  Recent: TJSONObject;
  Pair: TJSONPair;
begin
  Clear;
  FChanged := False;
  if not FileExists(AFileName) then
    Exit;
  try
    Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(AFileName, TEncoding.UTF8));
  except
    // Unlesbare Datei: ohne Verlauf weiter, beim nächsten Speichern neu.
    on EInOutError do
      Exit;
  end;
  if Root = nil then
    Exit;
  try
    if not (Root is TJSONObject) then
      Exit;
    Items := TJSONObject(Root).GetValue('entries') as TJSONArray;
    if Items <> nil then
      for Value in Items do
        if Value is TJSONObject then
        begin
          Item := TJSONObject(Value);
          Entry.Count := Item.GetValue<Integer>('count', 0);
          Entry.Last := Item.GetValue<Int64>('last', 0);
          if Item.GetValue<string>('key', '') <> '' then
            FEntries.AddOrSetValue(Item.GetValue<string>('key', ''), Entry);
          FClock := Max(FClock, Entry.Last);
        end;
    Recent := TJSONObject(Root).GetValue('recent') as TJSONObject;
    if Recent <> nil then
      for Pair in Recent do
        FRecent.AddOrSetValue(Pair.JsonString.Value, Pair.JsonValue.Value);
  finally
    Root.Free;
  end;
  FChanged := False;
end;

procedure TAtlasUsage.SaveToFile(const AFileName: string);
var
  Root, Item, Recent: TJSONObject;
  Items: TJSONArray;
  Pair: TPair<string, TEntry>;
  RecentPair: TPair<string, string>;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('version', TJSONNumber.Create(1));
    Items := TJSONArray.Create;
    Root.AddPair('entries', Items);
    for Pair in FEntries do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('key', Pair.Key);
      Item.AddPair('count', TJSONNumber.Create(Pair.Value.Count));
      Item.AddPair('last', TJSONNumber.Create(Pair.Value.Last));
      Items.AddElement(Item);
    end;
    Recent := TJSONObject.Create;
    Root.AddPair('recent', Recent);
    for RecentPair in FRecent do
      Recent.AddPair(RecentPair.Key, RecentPair.Value);
    ForceDirectories(ExtractFileDir(AFileName));
    TFile.WriteAllText(AFileName, Root.ToJSON, TEncoding.UTF8);
    FChanged := False;
  finally
    Root.Free;
  end;
end;

end.
