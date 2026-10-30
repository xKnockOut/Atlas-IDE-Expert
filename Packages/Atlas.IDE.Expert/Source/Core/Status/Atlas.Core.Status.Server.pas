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
  TAtlasServerMemoryPart = (Symbols, Usages, LibraryUnits, TreeCache, Documents, Rest);
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
  System.Generics.Defaults;

function IntOf(AObject: TJSONObject; const AName: string; ADefault: Int64): Int64;
var
  mValue: TJSONValue;
begin
  Result := ADefault;
  if AObject = nil then
    Exit;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONNumber then
    Result := TJSONNumber(mValue).AsInt64;
end;

function FloatOf(AObject: TJSONObject; const AName: string): Double;
var
  mValue: TJSONValue;
begin
  Result := 0;
  if AObject = nil then
    Exit;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONNumber then
    Result := TJSONNumber(mValue).AsDouble;
end;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  if AObject = nil then
    Exit;
  mValue := AObject.GetValue(AName);
  // TJSONNumber leitet von TJSONString ab; Zahlen sind hier kein Text.
  if (mValue is TJSONString) and not (mValue is TJSONNumber) then
    Result := mValue.Value;
end;

function BoolOf(AObject: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  Result := False;
  if AObject = nil then
    Exit;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONBool then
    Result := TJSONBool(mValue).AsBoolean;
end;

function ObjectOf(AObject: TJSONObject; const AName: string): TJSONObject;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONObject then
    Result := TJSONObject(mValue);
end;

function ArrayOf(AObject: TJSONObject; const AName: string): TJSONArray;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONArray then
    Result := TJSONArray(mValue);
end;

function StateOf(const AText: string): TAtlasServerState;
begin
  if SameText(AText, 'loading') then
    Result := TAtlasServerState.Loading
  else if SameText(AText, 'ready') then
    Result := TAtlasServerState.Ready
  else if SameText(AText, 'checking') then
    Result := TAtlasServerState.Checking
  else
    Result := TAtlasServerState.Unknown;
end;

function PercentOf(AObject: TJSONObject; const AName: string): Integer;
begin
  Result := -1;
  if (AObject <> nil) and (AObject.GetValue(AName) is TJSONNumber) then
    Result := EnsureRange(Integer(IntOf(AObject, AName, -1)), 0, 100);
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
    Exit;
  ASnapshot.CheckSerial := Integer(IntOf(ARun, 'serial', 0));
  ASnapshot.CheckActive := BoolOf(ARun, 'active');
  if TryISO8601ToDate(TextOf(ARun, 'started'), mStarted, False) then
    ASnapshot.CheckStarted := mStarted;
  ASnapshot.CheckDurationMs := IntOf(ARun, 'durationMs', 0);
  ASnapshot.CheckUnits := Integer(IntOf(ARun, 'units', 0));
  mItems := ArrayOf(ARun, 'slowUnits');
  if mItems <> nil then
    for mItem in mItems do
      if mItem is TJSONObject then
      begin
        mUnit := Default(TAtlasServerSlowUnit);
        mUnit.Name := TextOf(TJSONObject(mItem), 'name');
        mUnit.FileName := TextOf(TJSONObject(mItem), 'file');
        mUnit.Ms := FloatOf(TJSONObject(mItem), 'ms');
        ASnapshot.SlowUnits := ASnapshot.SlowUnits + [mUnit];
      end;
  mItems := ArrayOf(ARun, 'slowRules');
  if mItems <> nil then
    for mItem in mItems do
      if mItem is TJSONObject then
      begin
        mRule := Default(TAtlasServerSlowRule);
        mRule.Id := TextOf(TJSONObject(mItem), 'id');
        mRule.Ms := FloatOf(TJSONObject(mItem), 'ms');
        mRule.Calls := Integer(IntOf(TJSONObject(mItem), 'calls', 0));
        ASnapshot.SlowRules := ASnapshot.SlowRules + [mRule];
      end;
end;

function CompareRequests(const ALeft, ARight: TAtlasServerRequest): Integer;
begin
  Result := CompareValue(ARight.MaxMs, ALeft.MaxMs);
  if Result = 0 then
    Result := CompareText(ALeft.Method, ARight.Method);
  // Gleiche Methode zweimal kommt nicht vor; trotzdem eindeutig (TArray.Sort ist nicht stabil).
  if Result = 0 then
    Result := CompareValue(ARight.Count, ALeft.Count);
end;

procedure ReadRequests(var ASnapshot: TAtlasServerSnapshot; AItems: TJSONArray);
var
  mItem: TJSONValue;
  mRequest: TAtlasServerRequest;
  mAll: TArray<TAtlasServerRequest>;
begin
  if AItems = nil then
    Exit;
  mAll := nil;
  for mItem in AItems do
    if mItem is TJSONObject then
    begin
      mRequest := Default(TAtlasServerRequest);
      mRequest.Method := TextOf(TJSONObject(mItem), 'method');
      mRequest.Count := Integer(IntOf(TJSONObject(mItem), 'count', 0));
      mRequest.AverageMs := FloatOf(TJSONObject(mItem), 'averageMs');
      mRequest.MaxMs := FloatOf(TJSONObject(mItem), 'maxMs');
      mRequest.Failed := Integer(IntOf(TJSONObject(mItem), 'failed', 0));
      mAll := mAll + [mRequest];
    end;
  TArray.Sort<TAtlasServerRequest>(mAll, TComparer<TAtlasServerRequest>.Construct(CompareRequests));
  if Length(mAll) > TAtlasServerSnapshot.cRequestRows then
    SetLength(mAll, TAtlasServerSnapshot.cRequestRows);
  ASnapshot.Requests := mAll;
end;

{ TAtlasServerSnapshot }

class function TAtlasServerSnapshot.Parse(const AJson: string): TAtlasServerSnapshot;
var
  mValue: TJSONValue;
  mRoot, mProcess, mMemory, mQueue, mHits: TJSONObject;
begin
  Result := Default(TAtlasServerSnapshot);
  Result.Units := -1;
  Result.IndexHitPercent := -1;
  Result.TreeHitPercent := -1;
  if Trim(AJson) = '' then
    Exit;
  // Ungültiger Text liefert nil (keine Ausnahme).
  mValue := TJSONObject.ParseJSONValue(AJson);
  if mValue = nil then
    Exit;
  try
    if not (mValue is TJSONObject) then
      Exit;
    mRoot := TJSONObject(mValue);
    Result.Valid := True;
    Result.Units := Integer(IntOf(mRoot, 'units', -1));
    Result.MemoryTotal := IntOf(mRoot, 'memoryBytes', 0);
    Result.MemoryBudget := IntOf(mRoot, 'budgetBytes', 0);
    ReadRequests(Result, ArrayOf(mRoot, 'requests'));
    mProcess := ObjectOf(mRoot, 'process');
    Result.Known := mProcess <> nil;
    if mProcess <> nil then
    begin
      Result.ProcessId := Cardinal(IntOf(mProcess, 'pid', 0));
      Result.Version := TextOf(mProcess, 'version');
      Result.UptimeMs := IntOf(mProcess, 'uptimeMs', 0);
      Result.State := StateOf(TextOf(mProcess, 'state'));
    end;
    mMemory := ObjectOf(mRoot, 'memory');
    if mMemory <> nil then
    begin
      Result.Memory[TAtlasServerMemoryPart.Symbols] := IntOf(mMemory, 'symbols', 0);
      Result.Memory[TAtlasServerMemoryPart.Usages] := IntOf(mMemory, 'usages', 0);
      Result.Memory[TAtlasServerMemoryPart.LibraryUnits] := IntOf(mMemory, 'libraryUnits', 0);
      Result.Memory[TAtlasServerMemoryPart.TreeCache] := IntOf(mMemory, 'treeCache', 0);
      Result.Memory[TAtlasServerMemoryPart.Documents] := IntOf(mMemory, 'documents', 0);
      Result.Memory[TAtlasServerMemoryPart.Rest] := IntOf(mMemory, 'rest', 0);
      Result.MemoryTotal := IntOf(mMemory, 'total', Result.MemoryTotal);
      Result.MemoryBudget := IntOf(mMemory, 'budget', Result.MemoryBudget);
      Result.OverBudget := BoolOf(mMemory, 'overBudget');
    end;
    ReadCheckRun(Result, ObjectOf(mRoot, 'checkRun'));
    mQueue := ObjectOf(mRoot, 'queue');
    if mQueue <> nil then
    begin
      Result.IndexWaiting := Integer(IntOf(mQueue, 'indexWaiting', 0));
      Result.IndexRunning := Integer(IntOf(mQueue, 'indexRunning', 0));
      Result.CheckWaiting := Integer(IntOf(mQueue, 'checkWaiting', 0));
      Result.CheckRunning := Integer(IntOf(mQueue, 'checkRunning', 0));
      Result.OldestWaitMs := IntOf(mQueue, 'oldestWaitMs', 0);
    end;
    mHits := ObjectOf(mRoot, 'cacheHits');
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
    if mPart <> TAtlasServerMemoryPart.Rest then
      Inc(Result, Memory[mPart]);
end;

function TAtlasServerSnapshot.Scale: Int64;
begin
  Result := Max(MemoryBudget, MemoryTotal);
  Result := Max(Result, PartsSum + Memory[TAtlasServerMemoryPart.Rest]);
end;

function TAtlasServerSnapshot.Fraction(APart: TAtlasServerMemoryPart): Double;
begin
  if Scale <= 0 then
    Exit(0);
  Result := EnsureRange(Memory[APart] / Scale, 0, 1);
end;

function TAtlasServerSnapshot.TotalFraction: Double;
begin
  if Scale <= 0 then
    Exit(0);
  Result := EnsureRange(MemoryTotal / Scale, 0, 1);
end;

{ TAtlasServerTexts }

class function TAtlasServerTexts.Duration(AMs: Int64): string;
var
  mSeconds, mMinutes, mHours: Int64;
begin
  mSeconds := Max(AMs, 0) div 1000;
  if mSeconds < 60 then
    Exit(Format('%d s', [mSeconds]));
  mMinutes := mSeconds div 60;
  if mMinutes < 60 then
    Exit(Format('%d min', [mMinutes]));
  mHours := mMinutes div 60;
  if mHours >= 48 then
    Exit(Format('%d h', [mHours]));
  Result := Format('%d h %.2d min', [mHours, mMinutes mod 60]);
end;

class function TAtlasServerTexts.Megabytes(ABytes: Int64; const AFormat: TFormatSettings): string;
begin
  Result := FormatFloat('0.0', Max(ABytes, 0) / (1024 * 1024), AFormat) + ' MB';
end;

class function TAtlasServerTexts.Milliseconds(AMs: Double; const AFormat: TFormatSettings): string;
begin
  if AMs >= 10 then
    Result := FormatFloat('0', AMs, AFormat)
  else
    Result := FormatFloat('0.0', AMs, AFormat);
end;

end.
