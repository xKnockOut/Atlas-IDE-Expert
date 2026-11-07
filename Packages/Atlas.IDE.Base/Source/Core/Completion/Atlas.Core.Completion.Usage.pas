unit Atlas.Core.Completion.Usage;

// Lernende Gewichtung (#418): Wie oft und wann zuletzt ein Eintrag übernommen
// wurde, je Paar (Typ, Member). Daraus ein Zuschlag unter 100 Punkten für die
// Rangfolge (TAtlasRanking) und die Marken „zuletzt“ (letzte Übernahme bei
// diesem Typ) und „häufig“ (ab 5 Übernahmen). Gespeichert als JSON
// (%APPDATA%\Atlas\usage.json, Pfad von der IDE-Schicht), höchstens 5.000
// Paare; die am längsten nicht genutzten werden verdrängt. Lesen und
// Schreiben über TAtlasDataFile (Bericht N3): atomar ersetzt, eine
// unbrauchbare Datei liegt danach als usage.json.defekt daneben, eine
// gesperrte bleibt unverändert und wird nicht überschrieben.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Files.DataFile;

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
    /// <summary>Vorhandene Datei, die LoadFromFile nicht lesen konnte: SaveToFile überschreibt sie nicht.</summary>
    FKept: string;
    procedure Evict;
    /// <summary>Übernimmt AText; False, wenn es kein Objekt ist oder "entries"/"recent" die falsche Form haben.
    /// </summary>
    function Parse(const AText: string): Boolean;
    procedure ReadEntries(AItems: TJSONArray);
    procedure ReadRecent(ARecent: TJSONObject);
  public
    /// <summary>Schlüssel "typ|member" in Kleinbuchstaben; auch für die Favoriten (#458).</summary>
    class function KeyOf(const AItem: TAtlasCompletionItem): string; static;
    /// <summary>Typ in Kleinbuchstaben: deklarierende Klasse, auf Unit-Ebene die Unit, sonst leer.</summary>
    class function TypeOf(const AItem: TAtlasCompletionItem): string; static;
    constructor Create;
    destructor Destroy; override;
    /// <summary>Übernahme von AItem merken.</summary>
    procedure Record_(const AItem: TAtlasCompletionItem);
    /// <summary>Zuschlag 0..90 für die Rangfolge.</summary>
    function Boost(const AItem: TAtlasCompletionItem): Integer;
    function Mark(const AItem: TAtlasCompletionItem): TAtlasUsageMark;
    function Count: Integer;
    procedure Clear;
    /// <summary>Liest über TAtlasDataFile.Load; fehlt die Datei oder ist sie unbrauchbar, beginnt der Verlauf
    /// leer. Ergebnis Kept: Die Datei bleibt unverändert, SaveToFile schreibt sie nicht.</summary>
    function LoadFromFile(const AFileName: string): TAtlasDataLoad;
    /// <summary>Schreibt atomar; False, wenn LoadFromFile die vorhandene Datei nicht lesen konnte.</summary>
    function SaveToFile(const AFileName: string): Boolean;
    /// <summary>Seit dem Laden bzw. Speichern geändert.</summary>
    property Changed: Boolean read FChanged;
  end;

implementation

uses
  System.Math,
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
  begin
    Result := LowerCase(AItem.DeclaringUnit);
  end;
end;

class function TAtlasUsage.KeyOf(const AItem: TAtlasCompletionItem): string;
begin
  Result := TypeOf(AItem) + '|' + LowerCase(AItem.Name);
end;

procedure TAtlasUsage.Record_(const AItem: TAtlasCompletionItem);
var
  mEntry: TEntry;
  mKey: string;
begin
  mKey := KeyOf(AItem);
  if not FEntries.TryGetValue(mKey, mEntry) then
  begin
    mEntry := Default(TEntry);
  end;
  Inc(mEntry.Count);
  Inc(FClock);
  mEntry.Last := FClock;
  FEntries.AddOrSetValue(mKey, mEntry);
  FRecent.AddOrSetValue(TypeOf(AItem), LowerCase(AItem.Name));
  FChanged := True;
  if FEntries.Count > MaxEntries then
  begin
    Evict;
  end;
end;

procedure TAtlasUsage.Evict;
var
  mPairs: TArray<TPair<string, TEntry>>;
  mIndex: Integer;
begin
  // Älteste zuerst entfernen, bis wieder Platz ist (ein Zehntel Luft, damit nicht bei jeder Übernahme sortiert wird).
  mPairs := FEntries.ToArray;
  TArray.Sort<TPair<string, TEntry>>(mPairs, TComparer<TPair<string, TEntry>>.Construct(
    function(const A, B: TPair<string, TEntry>): Integer
    begin
      Result := CompareValue(A.Value.Last, B.Value.Last);
    end));
  for mIndex := 0 to Length(mPairs) - MaxEntries + MaxEntries div 10 - 1 do
  begin
    FEntries.Remove(mPairs[mIndex].Key);
  end;
end;

function TAtlasUsage.Boost(const AItem: TAtlasCompletionItem): Integer;
var
  mEntry: TEntry;
begin
  Result := 0;
  if not FEntries.TryGetValue(KeyOf(AItem), mEntry) then
  begin
    Exit;
  end;
  Result := Min(60, mEntry.Count * 15);
  if Mark(AItem) = TAtlasUsageMark.Recent then
  begin
    Inc(Result, 30);
  end;
end;

function TAtlasUsage.Mark(const AItem: TAtlasCompletionItem): TAtlasUsageMark;
var
  mEntry: TEntry;
  mName: string;
begin
  Result := TAtlasUsageMark.None;
  if FRecent.TryGetValue(TypeOf(AItem), mName) and (mName = LowerCase(AItem.Name)) then
  begin
    Exit(TAtlasUsageMark.Recent);
  end;
  if FEntries.TryGetValue(KeyOf(AItem), mEntry) and (mEntry.Count >= FrequentCount) then
  begin
    Result := TAtlasUsageMark.Frequent;
  end;
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

procedure TAtlasUsage.ReadEntries(AItems: TJSONArray);
var
  mValue: TJSONValue;
  mItem: TJSONObject;
  mEntry: TEntry;
begin
  for mValue in AItems do
  begin
    if not (mValue is TJSONObject) then
    begin
      Continue;
    end;
    mItem := TJSONObject(mValue);
    mEntry.Count := mItem.GetValue<Integer>('count', 0);
    mEntry.Last := mItem.GetValue<Int64>('last', 0);
    if mItem.GetValue<string>('key', '') <> '' then
    begin
      FEntries.AddOrSetValue(mItem.GetValue<string>('key', ''), mEntry);
    end;
    FClock := Max(FClock, mEntry.Last);
  end;
end;

procedure TAtlasUsage.ReadRecent(ARecent: TJSONObject);
var
  mPair: TJSONPair;
begin
  for mPair in ARecent do
  begin
    FRecent.AddOrSetValue(mPair.JsonString.Value, mPair.JsonValue.Value);
  end;
end;

function TAtlasUsage.Parse(const AText: string): Boolean;
var
  mRoot, mItems, mRecent: TJSONValue;
begin
  Result := False;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    mItems := TJSONObject(mRoot).GetValue('entries');
    mRecent := TJSONObject(mRoot).GetValue('recent');
    if ((mItems <> nil) and not (mItems is TJSONArray)) or ((mRecent <> nil) and not (mRecent is TJSONObject)) then
    begin
      Exit;
    end;
    Result := True;
    if mItems <> nil then
    begin
      ReadEntries(TJSONArray(mItems));
    end;
    if mRecent <> nil then
    begin
      ReadRecent(TJSONObject(mRecent));
    end;
  finally
    mRoot.Free;
  end;
end;

function TAtlasUsage.LoadFromFile(const AFileName: string): TAtlasDataLoad;
begin
  Clear;
  FKept := '';
  Result := TAtlasDataFile.Load(AFileName, 'Lernende Gewichtung',
    function(const AText: string): Boolean
    begin
      Result := Parse(AText);
    end);
  if not TAtlasDataFile.Writable(Result) then
  begin
    FKept := AFileName;
  end;
  // Unbrauchbarer Inhalt bleibt nicht halb geladen stehen.
  if Result <> TAtlasDataLoad.Loaded then
  begin
    Clear;
  end;
  FChanged := False;
end;

function TAtlasUsage.SaveToFile(const AFileName: string): Boolean;
var
  mRoot, mItem, mRecent: TJSONObject;
  mItems: TJSONArray;
  mPair: TPair<string, TEntry>;
  mRecentPair: TPair<string, string>;
begin
  Result := not SameFileName(AFileName, FKept);
  if not Result then
  begin
    Exit;
  end;
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('version', TJSONNumber.Create(1));
    mItems := TJSONArray.Create;
    mRoot.AddPair('entries', mItems);
    for mPair in FEntries do
    begin
      mItem := TJSONObject.Create;
      mItem.AddPair('key', mPair.Key);
      mItem.AddPair('count', TJSONNumber.Create(mPair.Value.Count));
      mItem.AddPair('last', TJSONNumber.Create(mPair.Value.Last));
      mItems.AddElement(mItem);
    end;
    mRecent := TJSONObject.Create;
    mRoot.AddPair('recent', mRecent);
    for mRecentPair in FRecent do
    begin
      mRecent.AddPair(mRecentPair.Key, mRecentPair.Value);
    end;
    TAtlasDataFile.Write(AFileName, mRoot.ToJSON);
    FChanged := False;
  finally
    mRoot.Free;
  end;
end;

end.
