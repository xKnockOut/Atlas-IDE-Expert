unit Atlas.Common.Index.UsageCounts;

// Wie oft kommt ein Name in den Units des Projekts vor (#2109)? Die Vervollständigung ordnet danach die
// Mitglieder eines Typs, solange die eigene Gewichtung (#418) leer ist. Die Zählung entsteht aus den Verwendungen
// des Index (#492) und wird je Unit fortgeschrieben: Der Index ruft Replace bei jeder neuen Fassung einer Datei
// und Remove beim Entfernen, nie beim Verkleinern. Darum bleibt der Beitrag einer Unit auch dann, wenn ihre
// Verwendungen später wegen des Budgets ausgelagert werden. Bibliotheken zählen nicht. Nicht threadsicher; der
// Index ruft unter seiner Sperre.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Index.Contract;

type
  TIndexUsageCounts = class
  private type
    /// <summary>Beitrag einer Unit: Platz des Namens in FTotals und Zahl der Stellen.</summary>
    TNameCount = record
      Slot: Integer;
      Count: Integer;
    end;
  private
    // Name (groß) → Platz; jeder Name liegt nur hier als String, die Beiträge der Units nennen den Platz.
    FSlots: TDictionary<string, Integer>;
    // Platz → Summe über alle Units.
    FTotals: TList<Integer>;
    // Dateischlüssel → Beitrag der Unit, damit eine neue Fassung den alten Beitrag abziehen kann.
    FFiles: TDictionary<string, TArray<TNameCount>>;
    procedure Apply(const ACounts: TArray<TNameCount>; ASign: Integer);
    function CountsOf(const AUnit: TUnitIndex): TArray<TNameCount>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Neue Fassung der Datei AFileKey. Ohne Verwendungen (Bibliothek, index.usages aus) fällt ihr
    /// Beitrag weg; sind sie nur ausgelagert, bleibt der bisherige.</summary>
    procedure Replace(const AFileKey: string; const AUnit: TUnitIndex);
    procedure Remove(const AFileKey: string);
    /// <summary>Stellen mit dem Namen AName in allen Projekt-Units; 0, wenn keine.</summary>
    function Count(const AName: string): Integer;
    /// <summary>Zahl der verschiedenen Namen, die je gezählt wurden.</summary>
    function NameCount: Integer;
    /// <summary>Geschätzter Speicherbedarf in Byte; geteilte Strings zählen je Verwendung.</summary>
    function Bytes: Int64;
  end;

implementation

uses
  System.SysUtils;

constructor TIndexUsageCounts.Create;
begin
  inherited Create;
  FSlots := TDictionary<string, Integer>.Create;
  FTotals := TList<Integer>.Create;
  FFiles := TDictionary<string, TArray<TNameCount>>.Create;
end;

destructor TIndexUsageCounts.Destroy;
begin
  FFiles.Free;
  FTotals.Free;
  FSlots.Free;
  inherited;
end;

function TIndexUsageCounts.CountsOf(const AUnit: TUnitIndex): TArray<TNameCount>;
var
  mIndex, mSlot: Integer;
  mName: string;
begin
  SetLength(Result, Length(AUnit.Usages));
  for mIndex := 0 to High(AUnit.Usages) do
  begin
    mName := UpperCase(AUnit.Usages[mIndex].Name);
    if not FSlots.TryGetValue(mName, mSlot) then
    begin
      mSlot := FTotals.Add(0);
      FSlots.Add(mName, mSlot);
    end;
    Result[mIndex].Slot := mSlot;
    Result[mIndex].Count := Length(AUnit.Usages[mIndex].Positions);
  end;
end;

procedure TIndexUsageCounts.Apply(const ACounts: TArray<TNameCount>; ASign: Integer);
var
  mEntry: TNameCount;
begin
  for mEntry in ACounts do
  begin
    FTotals[mEntry.Slot] := FTotals[mEntry.Slot] + ASign * mEntry.Count;
  end;
end;

procedure TIndexUsageCounts.Replace(const AFileKey: string; const AUnit: TUnitIndex);
var
  mCounts: TArray<TNameCount>;
begin
  if AUnit.UsagesOffloaded and (Length(AUnit.Usages) = 0) and FFiles.ContainsKey(AFileKey) then
  begin
    Exit;
  end;
  Remove(AFileKey);
  if AUnit.Library_ or not AUnit.UsagesIndexed or (Length(AUnit.Usages) = 0) then
  begin
    Exit;
  end;
  mCounts := CountsOf(AUnit);
  FFiles.Add(AFileKey, mCounts);
  Apply(mCounts, 1);
end;

procedure TIndexUsageCounts.Remove(const AFileKey: string);
var
  mCounts: TArray<TNameCount>;
begin
  if FFiles.TryGetValue(AFileKey, mCounts) then
  begin
    Apply(mCounts, -1);
    FFiles.Remove(AFileKey);
  end;
end;

function TIndexUsageCounts.Count(const AName: string): Integer;
var
  mSlot: Integer;
begin
  Result := 0;
  if FSlots.TryGetValue(UpperCase(AName), mSlot) then
  begin
    Result := FTotals[mSlot];
  end;
end;

function TIndexUsageCounts.NameCount: Integer;
begin
  Result := FSlots.Count;
end;

function TIndexUsageCounts.Bytes: Int64;
const
  // Eintrag im Wörterbuch (Hash, Schlüssel, Wert), Kopf eines Strings bzw. eines dynamischen Arrays.
  cEntryBytes = 24;
  cStringHead = 16;
var
  mName: string;
  mCounts: TArray<TNameCount>;
begin
  Result := 0;
  for mName in FSlots.Keys do
  begin
    Inc(Result, cEntryBytes + cStringHead + Length(mName) * SizeOf(Char) + SizeOf(Integer));
  end;
  for mCounts in FFiles.Values do
  begin
    Inc(Result, cEntryBytes + cStringHead + Length(mCounts) * SizeOf(TNameCount));
  end;
end;

end.
