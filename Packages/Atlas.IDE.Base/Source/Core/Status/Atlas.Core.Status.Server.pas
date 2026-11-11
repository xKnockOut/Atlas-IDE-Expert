unit Atlas.Core.Status.Server;

// Inhalt des Fensters „Atlas-Server“ (#1356), ohne VCL und Open Tools API.
// TAtlasServerSnapshot.Parse liest die Antwort von atlas.server.status: die
// alten Schlüssel (units, memoryBytes, budgetBytes, requests) und die neuen
// des Servers ab #1356 (process, memory, checkRun, queue, cacheHits). Ein
// älterer Server liefert kein process; Known ist dann False, und das Fenster
// zeigt nur, was da ist. Das Plugin liest das Paket nicht (Atlas.Common ist
// kein Teil des Plugins), deshalb steht das Format hier ein zweites Mal; die
// Tests prüfen es an einer Antwort, wie sie der Server schreibt.
// Die Neustarts der Sitzung zählt der Code Insight-Manager (Starts des
// Servers). Texte (Sprache) setzt die UI-Schicht; hier stehen nur Zahlen
// und sprachfreie Formen (Laufzeit „1 h 05 min“).

interface

uses
  System.SysUtils,
  System.JSON;

type
{$SCOPEDENUMS ON}
  /// <summary>Zustand des Servers aus process.state: lädt (Index wird aufgebaut), bereit, prüft.</summary>
  TAtlasServerState = (Unknown, Loading, Ready, Checking);
  /// <summary>Speicherbereiche in der Reihenfolge des Fensters.</summary>
  TAtlasServerMemoryPart = (Symbols, Usages, LibraryUnits, TreeCache, Documents, Packages, Rest);
{$SCOPEDENUMS OFF}

  TAtlasServerSlowUnit = record
    Name: string;
    /// <summary>Pfad der Unit; '' ohne (dann öffnet ein Doppelklick nichts).</summary>
    FileName: string;
    Ms: Double;
  end;

  TAtlasServerSlowRule = record
    Id: string;
    /// <summary>Summe über den Lauf.</summary>
    Ms: Double;
    Calls: Integer;
  end;

  TAtlasServerRequest = record
    Method: string;
    Count: Integer;
    AverageMs: Double;
    MaxMs: Double;
    Failed: Integer;
  end;

  TAtlasServerSnapshot = record
  public const
    /// <summary>So viele Anfragen zeigt das Fenster (die langsamsten nach Maximum).</summary>
    cRequestRows = 10;
  public
    /// <summary>Die Antwort war ein Status-Objekt.</summary>
    Valid: Boolean;
    /// <summary>Der Server liefert die Diagnose ab #1356 (Schlüssel process).</summary>
    Known: Boolean;
    ProcessId: Cardinal;
    Version: string;
    UptimeMs: Int64;
    State: TAtlasServerState;
    Units: Integer;
    Memory: array[TAtlasServerMemoryPart] of Int64;
    /// <summary>Gemessener Prozessspeicher (memory.total bzw. memoryBytes).</summary>
    MemoryTotal: Int64;
    /// <summary>Budget in Bytes; 0 = keins.</summary>
    MemoryBudget: Int64;
    /// <summary>Über dem Budget: Verwendungen werden ausgelagert.</summary>
    OverBudget: Boolean;
    /// <summary>Zähler der Prüfläufe; 0 = noch keiner.</summary>
    CheckSerial: Integer;
    CheckActive: Boolean;
    CheckStarted: TDateTime;
    CheckDurationMs: Int64;
    CheckUnits: Integer;
    SlowUnits: TArray<TAtlasServerSlowUnit>;
    SlowRules: TArray<TAtlasServerSlowRule>;
    /// <summary>Die langsamsten Anfragen (Maximum absteigend, bei Gleichstand nach Methode), höchstens
    /// cRequestRows.</summary>
    Requests: TArray<TAtlasServerRequest>;
    IndexWaiting: Integer;
    IndexRunning: Integer;
    CheckWaiting: Integer;
    CheckRunning: Integer;
    OldestWaitMs: Int64;
    /// <summary>Cache-Treffer in Prozent; -1 = unbekannt.</summary>
    IndexHitPercent: Integer;
    TreeHitPercent: Integer;
    /// <summary>Liest die Antwort von atlas.server.status; Valid False bei leerem oder ungültigem Text.</summary>
    class function Parse(const AJson: string): TAtlasServerSnapshot; static;
    /// <summary>Summe der Bereiche (ohne Rest, der ist schon der Unterschied zum Gesamtwert).</summary>
    function PartsSum: Int64;
    /// <summary>Maßstab der Balken: das Budget, ohne Budget bzw. darüber der Prozessspeicher.</summary>
    function Scale: Int64;
    /// <summary>Anteil eines Bereichs am Maßstab, 0 bis 1.</summary>
    function Fraction(APart: TAtlasServerMemoryPart): Double;
    /// <summary>Anteil des Prozessspeichers am Maßstab, 0 bis 1.</summary>
    function TotalFraction: Double;
  end;

  TAtlasServerTexts = record
  public
    /// <summary>„45 s“, „12 min“, „1 h 05 min“; ab 48 h nur Stunden.</summary>
    class function Duration(AMs: Int64): string; static;
    /// <summary>Megabyte mit einer Nachkommastelle in den Zahlformaten AFormat.</summary>
    class function Megabytes(ABytes: Int64; const AFormat: TFormatSettings): string; static;
    /// <summary>Millisekunden ohne Nachkommastellen ab 10 ms, sonst mit einer.</summary>
    class function Milliseconds(AMs: Double; const AFormat: TFormatSettings): string; static;
  end;

implementation

uses
  System.Math,
  System.DateUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Json;

function StateOf(const AText: string): TAtlasServerState;
begin
  if SameText(AText, 'loading') then
  begin
    Result := TAtlasServerState.Loading;
  end
  else if SameText(AText, 'ready') then
  begin
    Result := TAtlasServerState.Ready;
  end
  else if SameText(AText, 'checking') then
  begin
    Result := TAtlasServerState.Checking;
  end
  else
  begin
    Result := TAtlasServerState.Unknown;
  end;
end;

function PercentOf(AObject: TJSONObject; const AName: string): Integer;
begin
  Result := -1;
  if (AObject <> nil) and (AObject.GetValue(AName) is TJSONNumber) then
  begin
    Result := EnsureRange(Integer(TJsonRead.Int64Or(AObject, AName, -1)), 0, 100);
  end;
end;

procedure ReadCheckRun(var ASnapshot: TAtlasServerSnapshot; ARun: TJSONObject);
var
  mItems: TJSONArray;
  mItem: TJSONValue;
  mUnit: TAtlasServerSlowUnit;
  mRule: TAtlasServerSlowRule;
  mStarted: TDateTime;
begin
  if ARun = nil then
  begin
    Exit;
  end;
  ASnapshot.CheckSerial := Integer(TJsonRead.Int64Or(ARun, 'serial', 0));
  ASnapshot.CheckActive := TJsonRead.Flag(ARun, 'active');
  if TryISO8601ToDate(TJsonRead.StrictText(ARun, 'started'), mStarted, False) then
  begin
    ASnapshot.CheckStarted := mStarted;
  end;
  ASnapshot.CheckDurationMs := TJsonRead.Int64Or(ARun, 'durationMs', 0);
  ASnapshot.CheckUnits := Integer(TJsonRead.Int64Or(ARun, 'units', 0));
  mItems := TJsonRead.Items(ARun, 'slowUnits');
  if mItems <> nil then
  begin
    for mItem in mItems do
    begin
      if mItem is TJSONObject then
      begin
        mUnit := Default(TAtlasServerSlowUnit);
        mUnit.Name := TJsonRead.StrictText(TJSONObject(mItem), 'name');
        mUnit.FileName := TJsonRead.StrictText(TJSONObject(mItem), 'file');
        mUnit.Ms := TJsonRead.Float(TJSONObject(mItem), 'ms');
        ASnapshot.SlowUnits := ASnapshot.SlowUnits + [mUnit];
      end;
    end;
  end;
  mItems := TJsonRead.Items(ARun, 'slowRules');
  if mItems <> nil then
  begin
    for mItem in mItems do
    begin
      if mItem is TJSONObject then
      begin
        mRule := Default(TAtlasServerSlowRule);
        mRule.Id := TJsonRead.StrictText(TJSONObject(mItem), 'id');
        mRule.Ms := TJsonRead.Float(TJSONObject(mItem), 'ms');
        mRule.Calls := Integer(TJsonRead.Int64Or(TJSONObject(mItem), 'calls', 0));
        ASnapshot.SlowRules := ASnapshot.SlowRules + [mRule];
      end;
    end;
  end;
end;

function CompareRequests(const ALeft, ARight: TAtlasServerRequest): Integer;
begin
  Result := CompareValue(ARight.MaxMs, ALeft.MaxMs);
  if Result = 0 then
  begin
    Result := CompareText(ALeft.Method, ARight.Method);
  end;
  // Gleiche Methode zweimal kommt nicht vor; trotzdem eindeutig (TArray.Sort ist nicht stabil).
  if Result = 0 then
  begin
    Result := CompareValue(ARight.Count, ALeft.Count);
  end;
end;

procedure ReadRequests(var ASnapshot: TAtlasServerSnapshot; AItems: TJSONArray);
var
  mItem: TJSONValue;
  mRequest: TAtlasServerRequest;
  mAll: TArray<TAtlasServerRequest>;
begin
  if AItems = nil then
  begin
    Exit;
  end;
  mAll := nil;
  for mItem in AItems do
  begin
    if mItem is TJSONObject then
    begin
      mRequest := Default(TAtlasServerRequest);
      mRequest.Method := TJsonRead.StrictText(TJSONObject(mItem), 'method');
      mRequest.Count := Integer(TJsonRead.Int64Or(TJSONObject(mItem), 'count', 0));
      mRequest.AverageMs := TJsonRead.Float(TJSONObject(mItem), 'averageMs');
      mRequest.MaxMs := TJsonRead.Float(TJSONObject(mItem), 'maxMs');
      mRequest.Failed := Integer(TJsonRead.Int64Or(TJSONObject(mItem), 'failed', 0));
      mAll := mAll + [mRequest];
    end;
  end;
  TArray.Sort<TAtlasServerRequest>(mAll, TComparer<TAtlasServerRequest>.Construct(CompareRequests));
  if Length(mAll) > TAtlasServerSnapshot.cRequestRows then
  begin
    SetLength(mAll, TAtlasServerSnapshot.cRequestRows);
  end;
  ASnapshot.Requests := mAll;
end;

/// <summary>Schlüssel process (Server ab #1356); ohne ihn bleibt Known False.</summary>
procedure ReadProcess(var ASnapshot: TAtlasServerSnapshot; AProcess: TJSONObject);
begin
  ASnapshot.Known := AProcess <> nil;
  if AProcess = nil then
  begin
    Exit;
  end;
  ASnapshot.ProcessId := Cardinal(TJsonRead.Int64Or(AProcess, 'pid', 0));
  ASnapshot.Version := TJsonRead.StrictText(AProcess, 'version');
  ASnapshot.UptimeMs := TJsonRead.Int64Or(AProcess, 'uptimeMs', 0);
  ASnapshot.State := StateOf(TJsonRead.StrictText(AProcess, 'state'));
end;

/// <summary>Schlüssel memory; Gesamtwert und Budget überschreiben die alten Schlüssel nur, wenn vorhanden.</summary>
procedure ReadMemory(var ASnapshot: TAtlasServerSnapshot; AMemory: TJSONObject);
begin
  if AMemory = nil then
  begin
    Exit;
  end;
  ASnapshot.Memory[TAtlasServerMemoryPart.Symbols] := TJsonRead.Int64Or(AMemory, 'symbols', 0);
  ASnapshot.Memory[TAtlasServerMemoryPart.Usages] := TJsonRead.Int64Or(AMemory, 'usages', 0);
  ASnapshot.Memory[TAtlasServerMemoryPart.LibraryUnits] := TJsonRead.Int64Or(AMemory, 'libraryUnits', 0);
  ASnapshot.Memory[TAtlasServerMemoryPart.TreeCache] := TJsonRead.Int64Or(AMemory, 'treeCache', 0);
  ASnapshot.Memory[TAtlasServerMemoryPart.Packages] := TJsonRead.Int64Or(AMemory, 'packages', 0);
  ASnapshot.Memory[TAtlasServerMemoryPart.Documents] := TJsonRead.Int64Or(AMemory, 'documents', 0);
  ASnapshot.Memory[TAtlasServerMemoryPart.Rest] := TJsonRead.Int64Or(AMemory, 'rest', 0);
  ASnapshot.MemoryTotal := TJsonRead.Int64Or(AMemory, 'total', ASnapshot.MemoryTotal);
  ASnapshot.MemoryBudget := TJsonRead.Int64Or(AMemory, 'budget', ASnapshot.MemoryBudget);
  ASnapshot.OverBudget := TJsonRead.Flag(AMemory, 'overBudget');
end;

/// <summary>Schlüssel queue: wartende und laufende Aufträge.</summary>
procedure ReadQueue(var ASnapshot: TAtlasServerSnapshot; AQueue: TJSONObject);
begin
  if AQueue = nil then
  begin
    Exit;
  end;
  ASnapshot.IndexWaiting := Integer(TJsonRead.Int64Or(AQueue, 'indexWaiting', 0));
  ASnapshot.IndexRunning := Integer(TJsonRead.Int64Or(AQueue, 'indexRunning', 0));
  ASnapshot.CheckWaiting := Integer(TJsonRead.Int64Or(AQueue, 'checkWaiting', 0));
  ASnapshot.CheckRunning := Integer(TJsonRead.Int64Or(AQueue, 'checkRunning', 0));
  ASnapshot.OldestWaitMs := TJsonRead.Int64Or(AQueue, 'oldestWaitMs', 0);
end;

{ TAtlasServerSnapshot }

class function TAtlasServerSnapshot.Parse(const AJson: string): TAtlasServerSnapshot;
var
  mValue: TJSONValue;
  mRoot, mHits: TJSONObject;
begin
  Result := Default(TAtlasServerSnapshot);
  Result.Units := -1;
  Result.IndexHitPercent := -1;
  Result.TreeHitPercent := -1;
  if Trim(AJson) = '' then
  begin
    Exit;
  end;
  // Ungültiger Text liefert nil (keine Ausnahme).
  mValue := TJSONObject.ParseJSONValue(AJson);
  if mValue = nil then
  begin
    Exit;
  end;
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    Result.Valid := True;
    Result.Units := Integer(TJsonRead.Int64Or(mRoot, 'units', -1));
    Result.MemoryTotal := TJsonRead.Int64Or(mRoot, 'memoryBytes', 0);
    Result.MemoryBudget := TJsonRead.Int64Or(mRoot, 'budgetBytes', 0);
    ReadRequests(Result, TJsonRead.Items(mRoot, 'requests'));
    ReadProcess(Result, TJsonRead.Obj(mRoot, 'process'));
    ReadMemory(Result, TJsonRead.Obj(mRoot, 'memory'));
    ReadCheckRun(Result, TJsonRead.Obj(mRoot, 'checkRun'));
    ReadQueue(Result, TJsonRead.Obj(mRoot, 'queue'));
    mHits := TJsonRead.Obj(mRoot, 'cacheHits');
    Result.IndexHitPercent := PercentOf(mHits, 'index');
    Result.TreeHitPercent := PercentOf(mHits, 'trees');
  finally
    mValue.Free;
  end;
end;

function TAtlasServerSnapshot.PartsSum: Int64;
var
  mPart: TAtlasServerMemoryPart;
begin
  Result := 0;
  for mPart := Low(TAtlasServerMemoryPart) to High(TAtlasServerMemoryPart) do
  begin
    if mPart <> TAtlasServerMemoryPart.Rest then
    begin
      Inc(Result, Memory[mPart]);
    end;
  end;
end;

function TAtlasServerSnapshot.Scale: Int64;
begin
  Result := Max(MemoryBudget, MemoryTotal);
  Result := Max(Result, PartsSum + Memory[TAtlasServerMemoryPart.Rest]);
end;

function TAtlasServerSnapshot.Fraction(APart: TAtlasServerMemoryPart): Double;
begin
  if Scale <= 0 then
  begin
    Exit(0);
  end;
  Result := EnsureRange(Memory[APart] / Scale, 0, 1);
end;

function TAtlasServerSnapshot.TotalFraction: Double;
begin
  if Scale <= 0 then
  begin
    Exit(0);
  end;
  Result := EnsureRange(MemoryTotal / Scale, 0, 1);
end;

{ TAtlasServerTexts }

class function TAtlasServerTexts.Duration(AMs: Int64): string;
var
  mSeconds, mMinutes, mHours: Int64;
begin
  mSeconds := Max(AMs, 0) div 1000;
  if mSeconds < 60 then
  begin
    Exit(Format('%d s', [mSeconds]));
  end;
  mMinutes := mSeconds div 60;
  if mMinutes < 60 then
  begin
    Exit(Format('%d min', [mMinutes]));
  end;
  mHours := mMinutes div 60;
  if mHours >= 48 then
  begin
    Exit(Format('%d h', [mHours]));
  end;
  Result := Format('%d h %.2d min', [mHours, mMinutes mod 60]);
end;

class function TAtlasServerTexts.Megabytes(ABytes: Int64; const AFormat: TFormatSettings): string;
begin
  Result := FormatFloat('0.0', Max(ABytes, 0) / (1024 * 1024), AFormat) + ' MB';
end;

class function TAtlasServerTexts.Milliseconds(AMs: Double; const AFormat: TFormatSettings): string;
begin
  if AMs >= 10 then
  begin
    Result := FormatFloat('0', AMs, AFormat);
  end
  else
  begin
    Result := FormatFloat('0.0', AMs, AFormat);
  end;
end;

end.
