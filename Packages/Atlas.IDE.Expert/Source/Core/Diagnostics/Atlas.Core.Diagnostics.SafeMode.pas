unit Atlas.Core.Diagnostics.SafeMode;

// Abgesicherter Start nach einem Absturz (#722), Teil ohne Windows und ohne
// Open Tools API:
// - Startmarke: Beim Laden schreibt Atlas je IDE-Prozess eine Marke „Sitzung
//   läuft“ (Prozess, Atlas-Version, Startzeit, aktive Funktionen, Fehler je
//   Feature aus #493) und löscht sie beim sauberen Beenden. Eine Marke, deren
//   Prozess nicht mehr läuft, heißt: Die Sitzung ist abgestürzt.
// - Zustand zwischen den Sitzungen: Anzahl der Abstürze hintereinander, Zeit
//   des letzten, Marke der abgestürzten Sitzung (für „Details“) und ob der
//   letzte Start länger als das Zeitlimit brauchte (zählt wie ein Absturz).
// - Entscheidung beim Start: Umschalt/Strg beim Laden, Kommandozeile
//   -AtlasSafeMode oder ATLAS_SAFE_MODE=1 → nur Einstellungsseite und
//   Statusfeld (Minimal); zwei Abstürze innerhalb von RepeatWindowMinutes →
//   abgesichert ohne Rückfrage; ein Absturz → abgesichert, bis die Rückfrage
//   beantwortet ist; sonst normal.
// - Abgesichert heißt: alle Schnellschalter (#604) für diese Sitzung aus;
//   Suggest nennt, womit man beim Wiedereinschalten anfängt (zuletzt
//   geänderte Einstellungen, dann Funktionen mit Fehlern).

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Settings.QuickToggles;

type
{$SCOPEDENUMS ON}
  /// <summary>Normal: alles; Safe: Grundfunktionen (Server, Statusfeld, Einstellungen, Palette, Menü);
  /// Minimal: nur Einstellungsseite und Statusfeld.</summary>
  TAtlasSafeLevel = (Normal, Safe, Minimal);
  /// <summary>Warum nicht normal: nach einem Absturz (Rückfrage offen), nach wiederholtem Absturz, Taste beim
  /// Start, Kommandozeile bzw. Umgebungsvariable.</summary>
  TAtlasSafeReason = (None, Crash, RepeatedCrash, StartupKey, Forced);
  TAtlasStartupKey = (None, Shift, Ctrl);
{$SCOPEDENUMS OFF}

  TAtlasSessionMarker = record
    ProcessId: Cardinal;
    Version: string;
    /// <summary>UTC.</summary>
    StartedAt: TDateTime;
    /// <summary>Laden fertig (Nachrichtenschleife frei) und wie lange es gedauert hat.</summary>
    Loaded: Boolean;
    LoadMs: Int64;
    Level: TAtlasSafeLevel;
    /// <summary>Aktive Funktionen (Namen der eingeschalteten Schnellschalter).</summary>
    Features: TArray<string>;
    /// <summary>Fehler je Feature (#493) in dieser Sitzung.</summary>
    Failures: TArray<TPair<string, Integer>>;
    class function Create(AProcessId: Cardinal; const AVersion: string; AStartedAt: TDateTime): TAtlasSessionMarker;
      static;
    procedure AddFailure(const AFeature: string);
    function FailureCount(const AFeature: string): Integer;
    function ToJson: string;
    /// <summary>False bei ungültigem Text.</summary>
    class function FromJson(const AText: string; out AMarker: TAtlasSessionMarker): Boolean; static;
  end;

  TAtlasSafeOptions = record
    AskAfterCrash: Boolean;
    AutoAfterRepeatedCrash: Boolean;
    StartupKey: TAtlasStartupKey;
    StartupTimeoutMs: Integer;
    class function Create(AAsk, AAuto: Boolean; AKey: TAtlasStartupKey; ATimeoutMs: Integer): TAtlasSafeOptions; static;
  end;

  /// <summary>Was zwischen den Sitzungen bleibt.</summary>
  TAtlasSafeState = record
    /// <summary>Abstürze hintereinander; ein sauberes Ende setzt auf 0.</summary>
    CrashCount: Integer;
    /// <summary>UTC; 0 ohne.</summary>
    LastCrashAt: TDateTime;
    /// <summary>Letzter Start brauchte länger als das Zeitlimit.</summary>
    SlowStart: Boolean;
    /// <summary>Marke der zuletzt abgestürzten Sitzung als JSON; '' ohne.</summary>
    CrashedMarker: string;
    function ToJson: string;
    class function FromJson(const AText: string): TAtlasSafeState; static;
  end;

  TAtlasSafeDecision = record
    Level: TAtlasSafeLevel;
    Reason: TAtlasSafeReason;
    /// <summary>Letzte Sitzung abgestürzt oder hängend gestartet.</summary>
    Crashed: Boolean;
    /// <summary>Rückfrage zeigen („Abgesichert starten“, „Normal starten“, „Details“).</summary>
    Ask: Boolean;
  end;

  TAtlasSafeMode = class
  public const
    /// <summary>Zwei Abstürze in dieser Zeit gelten als wiederholt.</summary>
    RepeatWindowMinutes = 10;
    MinTimeoutMs = 1000;
    MaxTimeoutMs = 120000;
    EnvironmentName = 'ATLAS_SAFE_MODE';
    SwitchName = 'AtlasSafeMode';
  public
    /// <summary>Entscheidung beim Start und neuer Zustand. ACrashed: Marken früherer Sitzungen, deren Prozess
    /// nicht mehr läuft; AKeyDown: welche Taste beim Laden gedrückt ist; AForced: Kommandozeile bzw.
    /// Umgebungsvariable.</summary>
    class function Decide(var AState: TAtlasSafeState; const ACrashed: TArray<TAtlasSessionMarker>;
      ANow: TDateTime; const AOptions: TAtlasSafeOptions; AKeyDown: TAtlasStartupKey;
      AForced: Boolean): TAtlasSafeDecision; static;
    /// <summary>Sauberes Ende: keine Abstürze mehr in Folge.</summary>
    class procedure CleanExit(var AState: TAtlasSafeState); static;
    /// <summary>Laden fertig nach ALoadMs; länger als AOptions.StartupTimeoutMs zählt beim nächsten Start wie ein
    /// Absturz. True, wenn zu langsam.</summary>
    class function LoadFinished(var AState: TAtlasSafeState; ALoadMs: Int64;
      const AOptions: TAtlasSafeOptions): Boolean; static;
    /// <summary>Umgebungsvariable ("1", "true", "yes") oder Kommandozeile -AtlasSafeMode bzw. /AtlasSafeMode.</summary>
    class function IsForced(const AEnvironment: string; const AArgs: TArray<string>): Boolean; static;
    /// <summary>Taste aus safeMode.startupKey ("shift", "ctrl", "none").</summary>
    class function KeyOf(const AText: string): TAtlasStartupKey; static;
    class function KeyText(AKey: TAtlasStartupKey): string; static;
    /// <summary>Sitzungswerte für den abgesicherten Start: alle Schnellschalter aus.</summary>
    class function SafeSession(const AToggles: TArray<TAtlasQuickToggle>): TAtlasToggleSession; static;
    /// <summary>Womit man beim Wiedereinschalten anfängt: zuletzt geänderte Einstellungen, dann Funktionen mit
    /// den meisten Fehlern der abgestürzten Sitzung (x-feature), jeweils nur Schnellschalter.</summary>
    class function Suggest(const AToggles: TArray<TAtlasQuickToggle>; const AChangedKeys: TArray<string>;
      const ACrashed: TAtlasSessionMarker): TArray<string>; static;
    /// <summary>Text der Details: Version, Start, Ladezeit, aktive Funktionen, Fehler je Feature.</summary>
    class function Details(const AMarker: TAtlasSessionMarker): TArray<string>; static;
    /// <summary>Zeilen des Plugin-Protokolls (Zeitstempel "yyyy-mm-dd hh:nn:ss.zzz" in Ortszeit) ab AFrom und vor
    /// ATo (0 = ohne Ende), höchstens die letzten AMax; Zeilen ohne Zeitstempel gehören zur vorigen.</summary>
    class function LogLinesBetween(const ALines: TArray<string>; AFrom, ATo: TDateTime;
      AMax: Integer): TArray<string>; static;
  end;

  /// <summary>Läuft der Prozess AProcessId noch und ist er nicht nach AStartedAt (UTC) gestartet (sonst hat ein
  /// neuer Prozess die Nummer übernommen)?</summary>
  TAtlasProcessAlive = reference to function(AProcessId: Cardinal; AStartedAt: TDateTime): Boolean;

  /// <summary>Dateien des abgesicherten Starts in AFolder (in der IDE %LOCALAPPDATA%\Atlas\Session): je Prozess
  /// session-&lt;pid&gt;.json und der Zustand safemode.json. Geschrieben wird über eine temporäre Datei, damit
  /// ein Absturz mitten im Schreiben keine halbe Marke hinterlässt.</summary>
  TAtlasSessionFiles = class
  public
    class function MarkerFile(const AFolder: string; AProcessId: Cardinal): string; static;
    class function StateFile(const AFolder: string): string; static;
    class procedure WriteMarker(const AFolder: string; const AMarker: TAtlasSessionMarker); static;
    class procedure DeleteMarker(const AFolder: string; AProcessId: Cardinal); static;
    /// <summary>Marken früherer Sitzungen, deren Prozess nicht mehr läuft; ihre Dateien werden gelöscht.
    /// Die eigene Marke (AOwnProcessId) und Marken laufender IDEs bleiben; unlesbare Marken fallen weg.</summary>
    class function TakeCrashed(const AFolder: string; AOwnProcessId: Cardinal;
      const AAlive: TAtlasProcessAlive): TArray<TAtlasSessionMarker>; static;
    class function ReadState(const AFolder: string): TAtlasSafeState; static;
    class procedure WriteState(const AFolder: string; const AState: TAtlasSafeState); static;
  end;

implementation

uses
  System.Math,
  System.Classes,
  System.IOUtils,
  System.DateUtils;

const
  LevelNames: array[TAtlasSafeLevel] of string = ('normal', 'safe', 'minimal');

function LevelOf(const AText: string): TAtlasSafeLevel;
var
  Level: TAtlasSafeLevel;
begin
  for Level := Low(TAtlasSafeLevel) to High(TAtlasSafeLevel) do
    if SameText(LevelNames[Level], AText) then
      Exit(Level);
  Result := TAtlasSafeLevel.Normal;
end;

function ContainsText_(const AList: TArray<string>; const AText: string): Boolean;
var
  Item: string;
begin
  for Item in AList do
    if SameText(Item, AText) then
      Exit(True);
  Result := False;
end;

{ TAtlasSessionMarker }

class function TAtlasSessionMarker.Create(AProcessId: Cardinal; const AVersion: string;
  AStartedAt: TDateTime): TAtlasSessionMarker;
begin
  Result := Default(TAtlasSessionMarker);
  Result.ProcessId := AProcessId;
  Result.Version := AVersion;
  Result.StartedAt := AStartedAt;
  Result.LoadMs := -1;
end;

procedure TAtlasSessionMarker.AddFailure(const AFeature: string);
var
  Index: Integer;
begin
  for Index := 0 to High(Failures) do
    if SameText(Failures[Index].Key, AFeature) then
    begin
      Failures[Index] := TPair<string, Integer>.Create(Failures[Index].Key, Failures[Index].Value + 1);
      Exit;
    end;
  Failures := Failures + [TPair<string, Integer>.Create(AFeature, 1)];
end;

function TAtlasSessionMarker.FailureCount(const AFeature: string): Integer;
var
  Pair: TPair<string, Integer>;
begin
  for Pair in Failures do
    if SameText(Pair.Key, AFeature) then
      Exit(Pair.Value);
  Result := 0;
end;

function TAtlasSessionMarker.ToJson: string;
var
  Root, Counts: TJSONObject;
  List: TJSONArray;
  Name: string;
  Pair: TPair<string, Integer>;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('processId', TJSONNumber.Create(Int64(ProcessId)));
    Root.AddPair('version', TJSONString.Create(Version));
    Root.AddPair('startedAt', TJSONString.Create(DateToISO8601(StartedAt, True)));
    Root.AddPair('loaded', TJSONBool.Create(Loaded));
    Root.AddPair('loadMs', TJSONNumber.Create(LoadMs));
    Root.AddPair('level', TJSONString.Create(LevelNames[Level]));
    List := TJSONArray.Create;
    for Name in Features do
      List.Add(Name);
    Root.AddPair('features', List);
    Counts := TJSONObject.Create;
    for Pair in Failures do
      Counts.AddPair(Pair.Key, TJSONNumber.Create(Pair.Value));
    Root.AddPair('failures', Counts);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

class function TAtlasSessionMarker.FromJson(const AText: string; out AMarker: TAtlasSessionMarker): Boolean;
var
  Root, Value: TJSONValue;
  Element: TJSONValue;
  Pair: TJSONPair;
  Stamp: string;
begin
  AMarker := Default(TAtlasSessionMarker);
  Result := False;
  Root := TJSONObject.ParseJSONValue(AText);
  try
    if not (Root is TJSONObject) then
      Exit;
    Value := TJSONObject(Root).GetValue('processId');
    if not (Value is TJSONNumber) then
      Exit;
    AMarker.ProcessId := Cardinal(TJSONNumber(Value).AsInt64);
    AMarker.Version := TJSONObject(Root).GetValue<string>('version', '');
    Stamp := TJSONObject(Root).GetValue<string>('startedAt', '');
    if Stamp <> '' then
      try
        AMarker.StartedAt := ISO8601ToDate(Stamp, True);
      except
        on EConvertError do
          AMarker.StartedAt := 0;
      end;
    Value := TJSONObject(Root).GetValue('loaded');
    AMarker.Loaded := (Value is TJSONBool) and TJSONBool(Value).AsBoolean;
    Value := TJSONObject(Root).GetValue('loadMs');
    AMarker.LoadMs := -1;
    if Value is TJSONNumber then
      AMarker.LoadMs := TJSONNumber(Value).AsInt64;
    AMarker.Level := LevelOf(TJSONObject(Root).GetValue<string>('level', ''));
    Value := TJSONObject(Root).GetValue('features');
    if Value is TJSONArray then
      for Element in TJSONArray(Value) do
        if Element is TJSONString then
          AMarker.Features := AMarker.Features + [TJSONString(Element).Value];
    Value := TJSONObject(Root).GetValue('failures');
    if Value is TJSONObject then
      for Pair in TJSONObject(Value) do
        if Pair.JsonValue is TJSONNumber then
          AMarker.Failures := AMarker.Failures + [TPair<string, Integer>.Create(Pair.JsonString.Value,
            TJSONNumber(Pair.JsonValue).AsInt)];
    Result := True;
  finally
    Root.Free;
  end;
end;

{ TAtlasSafeOptions }

class function TAtlasSafeOptions.Create(AAsk, AAuto: Boolean; AKey: TAtlasStartupKey;
  ATimeoutMs: Integer): TAtlasSafeOptions;
begin
  Result.AskAfterCrash := AAsk;
  Result.AutoAfterRepeatedCrash := AAuto;
  Result.StartupKey := AKey;
  Result.StartupTimeoutMs := ATimeoutMs;
end;

{ TAtlasSafeState }

function TAtlasSafeState.ToJson: string;
var
  Root: TJSONObject;
  Crashed: TJSONValue;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('crashCount', TJSONNumber.Create(CrashCount));
    if LastCrashAt > 0 then
      Root.AddPair('lastCrashAt', TJSONString.Create(DateToISO8601(LastCrashAt, True)));
    Root.AddPair('slowStart', TJSONBool.Create(SlowStart));
    Crashed := nil;
    if CrashedMarker <> '' then
      Crashed := TJSONObject.ParseJSONValue(CrashedMarker);
    if Crashed is TJSONObject then
      Root.AddPair('crashed', Crashed)
    else
      Crashed.Free;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

class function TAtlasSafeState.FromJson(const AText: string): TAtlasSafeState;
var
  Root, Value: TJSONValue;
  Stamp: string;
begin
  Result := Default(TAtlasSafeState);
  Root := TJSONObject.ParseJSONValue(AText);
  try
    if not (Root is TJSONObject) then
      Exit;
    Value := TJSONObject(Root).GetValue('crashCount');
    if Value is TJSONNumber then
      Result.CrashCount := Max(0, TJSONNumber(Value).AsInt);
    Stamp := TJSONObject(Root).GetValue<string>('lastCrashAt', '');
    if Stamp <> '' then
      try
        Result.LastCrashAt := ISO8601ToDate(Stamp, True);
      except
        on EConvertError do
          Result.LastCrashAt := 0;
      end;
    Value := TJSONObject(Root).GetValue('slowStart');
    Result.SlowStart := (Value is TJSONBool) and TJSONBool(Value).AsBoolean;
    Value := TJSONObject(Root).GetValue('crashed');
    if Value is TJSONObject then
      Result.CrashedMarker := Value.ToJSON;
  finally
    Root.Free;
  end;
end;

{ TAtlasSafeMode }

class function TAtlasSafeMode.Decide(var AState: TAtlasSafeState; const ACrashed: TArray<TAtlasSessionMarker>;
  ANow: TDateTime; const AOptions: TAtlasSafeOptions; AKeyDown: TAtlasStartupKey;
  AForced: Boolean): TAtlasSafeDecision;
var
  Latest: TAtlasSessionMarker;
  Marker: TAtlasSessionMarker;
  Repeated: Boolean;
begin
  Result := Default(TAtlasSafeDecision);
  Result.Crashed := (Length(ACrashed) > 0) or AState.SlowStart;
  Repeated := False;
  if Result.Crashed then
  begin
    Repeated := (AState.CrashCount > 0) and (AState.LastCrashAt > 0) and
      (MinutesBetween(ANow, AState.LastCrashAt) < RepeatWindowMinutes) and (ANow >= AState.LastCrashAt);
    if Repeated then
      Inc(AState.CrashCount)
    else
      AState.CrashCount := 1;
    AState.LastCrashAt := ANow;
    // Für „Details“ die zuletzt gestartete abgestürzte Sitzung.
    if Length(ACrashed) > 0 then
    begin
      Latest := ACrashed[0];
      for Marker in ACrashed do
        if Marker.StartedAt > Latest.StartedAt then
          Latest := Marker;
      AState.CrashedMarker := Latest.ToJson;
    end;
  end;
  AState.SlowStart := False;
  if AForced then
  begin
    Result.Level := TAtlasSafeLevel.Minimal;
    Result.Reason := TAtlasSafeReason.Forced;
    Exit;
  end;
  if (AOptions.StartupKey <> TAtlasStartupKey.None) and (AKeyDown = AOptions.StartupKey) then
  begin
    Result.Level := TAtlasSafeLevel.Minimal;
    Result.Reason := TAtlasSafeReason.StartupKey;
    Exit;
  end;
  if not Result.Crashed then
    Exit;
  if Repeated and AOptions.AutoAfterRepeatedCrash then
  begin
    Result.Level := TAtlasSafeLevel.Safe;
    Result.Reason := TAtlasSafeReason.RepeatedCrash;
    Exit;
  end;
  if AOptions.AskAfterCrash then
  begin
    // Bis zur Antwort abgesichert: Die Rückfrage blockiert den Start nicht.
    Result.Level := TAtlasSafeLevel.Safe;
    Result.Reason := TAtlasSafeReason.Crash;
    Result.Ask := True;
  end;
end;

class procedure TAtlasSafeMode.CleanExit(var AState: TAtlasSafeState);
begin
  AState.CrashCount := 0;
end;

class function TAtlasSafeMode.LoadFinished(var AState: TAtlasSafeState; ALoadMs: Int64;
  const AOptions: TAtlasSafeOptions): Boolean;
begin
  Result := (AOptions.StartupTimeoutMs > 0) and (ALoadMs > EnsureRange(AOptions.StartupTimeoutMs, MinTimeoutMs,
    MaxTimeoutMs));
  AState.SlowStart := Result;
end;

class function TAtlasSafeMode.IsForced(const AEnvironment: string; const AArgs: TArray<string>): Boolean;
var
  Arg, Value: string;
begin
  Value := Trim(AEnvironment);
  if SameText(Value, '1') or SameText(Value, 'true') or SameText(Value, 'yes') then
    Exit(True);
  for Arg in AArgs do
    if SameText(Arg, '-' + SwitchName) or SameText(Arg, '/' + SwitchName) or SameText(Arg, '--' + SwitchName) then
      Exit(True);
  Result := False;
end;

class function TAtlasSafeMode.KeyOf(const AText: string): TAtlasStartupKey;
begin
  if SameText(AText, 'ctrl') then
    Result := TAtlasStartupKey.Ctrl
  else if SameText(AText, 'none') then
    Result := TAtlasStartupKey.None
  else
    Result := TAtlasStartupKey.Shift;
end;

class function TAtlasSafeMode.KeyText(AKey: TAtlasStartupKey): string;
begin
  case AKey of
    TAtlasStartupKey.Ctrl:
      Result := 'ctrl';
    TAtlasStartupKey.None:
      Result := 'none';
  else
    Result := 'shift';
  end;
end;

class function TAtlasSafeMode.SafeSession(const AToggles: TArray<TAtlasQuickToggle>): TAtlasToggleSession;
var
  Toggle: TAtlasQuickToggle;
begin
  Result := Default(TAtlasToggleSession);
  for Toggle in AToggles do
    Result.Put(Toggle.Key, False);
end;

class function TAtlasSafeMode.Suggest(const AToggles: TArray<TAtlasQuickToggle>; const AChangedKeys: TArray<string>;
  const ACrashed: TAtlasSessionMarker): TArray<string>;
var
  Toggle: TAtlasQuickToggle;
  Key: string;
  Candidates: TArray<TPair<string, Integer>>;
  Index, Other: Integer;
  Swap: TPair<string, Integer>;
begin
  Result := nil;
  // Zuerst, was zuletzt geändert wurde: das ist am ehesten die Ursache.
  for Key in AChangedKeys do
    if TAtlasQuickToggles.Find(AToggles, Key, Toggle) and not ContainsText_(Result, Toggle.Key) then
      Result := Result + [Toggle.Key];
  // Dann Funktionen mit Fehlern in der abgestürzten Sitzung, die meisten zuerst; bei Gleichstand Katalog.
  Candidates := nil;
  for Toggle in AToggles do
    if (Toggle.Feature <> '') and (ACrashed.FailureCount(Toggle.Feature) > 0) and
      not ContainsText_(Result, Toggle.Key) then
      Candidates := Candidates + [TPair<string, Integer>.Create(Toggle.Key, ACrashed.FailureCount(Toggle.Feature))];
  for Index := 1 to High(Candidates) do
  begin
    Other := Index;
    while (Other > 0) and (Candidates[Other - 1].Value < Candidates[Other].Value) do
    begin
      Swap := Candidates[Other - 1];
      Candidates[Other - 1] := Candidates[Other];
      Candidates[Other] := Swap;
      Dec(Other);
    end;
  end;
  for Index := 0 to High(Candidates) do
    Result := Result + [Candidates[Index].Key];
end;

function LineStamp(const ALine: string; out AStamp: TDateTime): Boolean;
var
  Year, Month, Day, Hour, Minute, Second, Milli: Integer;
begin
  AStamp := 0;
  Result := (Length(ALine) >= 23) and (ALine[5] = '-') and (ALine[8] = '-') and (ALine[11] = ' ') and
    (ALine[14] = ':') and (ALine[17] = ':') and (ALine[20] = '.') and
    TryStrToInt(Copy(ALine, 1, 4), Year) and TryStrToInt(Copy(ALine, 6, 2), Month) and
    TryStrToInt(Copy(ALine, 9, 2), Day) and TryStrToInt(Copy(ALine, 12, 2), Hour) and
    TryStrToInt(Copy(ALine, 15, 2), Minute) and TryStrToInt(Copy(ALine, 18, 2), Second) and
    TryStrToInt(Copy(ALine, 21, 3), Milli);
  if Result then
    Result := TryEncodeDateTime(Year, Month, Day, Hour, Minute, Second, Milli, AStamp);
end;

class function TAtlasSafeMode.LogLinesBetween(const ALines: TArray<string>; AFrom, ATo: TDateTime;
  AMax: Integer): TArray<string>;
var
  Line: string;
  Stamp: TDateTime;
  Inside: Boolean;
begin
  Result := nil;
  Inside := False;
  for Line in ALines do
  begin
    if LineStamp(Line, Stamp) then
      Inside := (Stamp >= AFrom) and ((ATo = 0) or (Stamp < ATo));
    if Inside then
      Result := Result + [Line];
  end;
  if (AMax >= 0) and (Length(Result) > AMax) then
    Result := Copy(Result, Length(Result) - AMax, AMax);
end;

class function TAtlasSafeMode.Details(const AMarker: TAtlasSessionMarker): TArray<string>;
var
  Pair: TPair<string, Integer>;
  Names: string;
begin
  Result := ['Atlas ' + AMarker.Version, 'Start: ' + DateToISO8601(AMarker.StartedAt, True)];
  if AMarker.Loaded then
    Result := Result + [Format('Laden: %d ms', [AMarker.LoadMs])]
  else
    Result := Result + ['Laden: nicht abgeschlossen'];
  Result := Result + ['Modus: ' + LevelNames[AMarker.Level]];
  Names := string.Join(', ', AMarker.Features);
  if Names = '' then
    Names := '–';
  Result := Result + ['Aktive Funktionen: ' + Names];
  if Length(AMarker.Failures) = 0 then
    Result := Result + ['Fehler: keine']
  else
    for Pair in AMarker.Failures do
      Result := Result + [Format('Fehler %s: %d', [Pair.Key, Pair.Value])];
end;

{ TAtlasSessionFiles }

const
  MarkerPrefix = 'session-';

procedure WriteFileSafely(const AFileName, AText: string);
var
  Temp: string;
begin
  ForceDirectories(ExtractFileDir(AFileName));
  Temp := AFileName + '.tmp';
  TFile.WriteAllText(Temp, AText, TEncoding.UTF8);
  if TFile.Exists(AFileName) then
    TFile.Delete(AFileName);
  TFile.Move(Temp, AFileName);
end;

class function TAtlasSessionFiles.MarkerFile(const AFolder: string; AProcessId: Cardinal): string;
begin
  Result := TPath.Combine(AFolder, MarkerPrefix + UIntToStr(AProcessId) + '.json');
end;

class function TAtlasSessionFiles.StateFile(const AFolder: string): string;
begin
  Result := TPath.Combine(AFolder, 'safemode.json');
end;

class procedure TAtlasSessionFiles.WriteMarker(const AFolder: string; const AMarker: TAtlasSessionMarker);
begin
  WriteFileSafely(MarkerFile(AFolder, AMarker.ProcessId), AMarker.ToJson);
end;

class procedure TAtlasSessionFiles.DeleteMarker(const AFolder: string; AProcessId: Cardinal);
begin
  if TFile.Exists(MarkerFile(AFolder, AProcessId)) then
    TFile.Delete(MarkerFile(AFolder, AProcessId));
end;

class function TAtlasSessionFiles.TakeCrashed(const AFolder: string; AOwnProcessId: Cardinal;
  const AAlive: TAtlasProcessAlive): TArray<TAtlasSessionMarker>;
var
  FileName: string;
  Marker: TAtlasSessionMarker;
  Valid: Boolean;
begin
  Result := nil;
  if not TDirectory.Exists(AFolder) then
    Exit;
  for FileName in TDirectory.GetFiles(AFolder, MarkerPrefix + '*.json') do
  begin
    try
      Valid := TAtlasSessionMarker.FromJson(TFile.ReadAllText(FileName, TEncoding.UTF8), Marker);
    except
      Valid := False;
    end;
    if Valid and (Marker.ProcessId = AOwnProcessId) then
      Continue;
    if Valid and Assigned(AAlive) and AAlive(Marker.ProcessId, Marker.StartedAt) then
      Continue;
    if Valid then
      Result := Result + [Marker];
    try
      TFile.Delete(FileName);
    except
      // Gesperrt: beim nächsten Start noch einmal.
      on Exception do
        ;
    end;
  end;
end;

class function TAtlasSessionFiles.ReadState(const AFolder: string): TAtlasSafeState;
begin
  Result := Default(TAtlasSafeState);
  try
    if TFile.Exists(StateFile(AFolder)) then
      Result := TAtlasSafeState.FromJson(TFile.ReadAllText(StateFile(AFolder), TEncoding.UTF8));
  except
    on Exception do
      Result := Default(TAtlasSafeState);
  end;
end;

class procedure TAtlasSessionFiles.WriteState(const AFolder: string; const AState: TAtlasSafeState);
begin
  WriteFileSafely(StateFile(AFolder), AState.ToJson);
end;

end.
