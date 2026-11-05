unit Atlas.Core.Diagnostics.SafeMode;

// Abgesicherter Start nach einem Absturz (#722), Teil ohne Windows und ohne
// Open Tools API:
// - Startmarke: Beim Laden schreibt Atlas je IDE-Prozess eine Marke „Sitzung
//   läuft“ (Prozess, Atlas-Version, Startzeit, aktive Funktionen, Fehler je
//   Feature aus #493) und löscht sie beim sauberen Beenden. Eine Marke, deren
//   Prozess nicht mehr läuft, heißt: Die Sitzung ist abgestürzt.
// - Zustand zwischen den Sitzungen: Anzahl der Abstürze hintereinander, Zeit
//   des letzten und Marke der abgestürzten Sitzung (für „Details“).
// - Ein langsamer Start ist kein Absturz (Bericht N4): Er schaltet beim
//   nächsten Start nichts ab. Atlas misst stattdessen seine Startanteile
//   (TAtlasStartTimes) und nennt sie, damit sich die Ursache beheben lässt.
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
  Atlas.Core.Settings.QuickToggles,
  // TAtlasSafeLevel (Stufe des abgesicherten Starts) steht im Modulvertrag (#1455).
  Atlas.Core.Modules.Contract;

type
{$SCOPEDENUMS ON}
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
    class function Create(AAsk, AAuto: Boolean; AKey: TAtlasStartupKey): TAtlasSafeOptions; static;
  end;

  /// <summary>Was zwischen den Sitzungen bleibt.</summary>
  TAtlasSafeState = record
    /// <summary>Abstürze hintereinander; ein sauberes Ende setzt auf 0.</summary>
    CrashCount: Integer;
    /// <summary>UTC; 0 ohne.</summary>
    LastCrashAt: TDateTime;
    /// <summary>Marke der zuletzt abgestürzten Sitzung als JSON; '' ohne.</summary>
    CrashedMarker: string;
    function ToJson: string;
    class function FromJson(const AText: string): TAtlasSafeState; static;
  end;

  TAtlasSafeDecision = record
    Level: TAtlasSafeLevel;
    Reason: TAtlasSafeReason;
    /// <summary>Letzte Sitzung abgestürzt (ein langsamer Start zählt nicht, Bericht N4).</summary>
    Crashed: Boolean;
    /// <summary>Rückfrage zeigen („Abgesichert starten“, „Normal starten“, „Details“).</summary>
    Ask: Boolean;
  end;

  TAtlasSafeMode = class
  public const
    /// <summary>Zwei Abstürze in dieser Zeit gelten als wiederholt.</summary>
    RepeatWindowMinutes = 10;
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
  System.DateUtils,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TSafeModeText = (LoadingMs, LoadingNotFinished, Mode, ActiveFeatures, ErrorsNone, Errors);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TSafeModeText] of string = (
    ('Laden: %d ms',
     'Laden: nicht abgeschlossen',
     'Modus: ',
     'Aktive Funktionen: ',
     'Fehler: keine',
     'Fehler %s: %d'),
    ('Loading: %d ms',
     'Loading: not finished',
     'Mode: ',
     'Active features: ',
     'Errors: none',
     'Errors %s: %d'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TSafeModeText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

const
  LevelNames: array[TAtlasSafeLevel] of string = ('normal', 'safe', 'minimal');

function LevelOf(const AText: string): TAtlasSafeLevel;
var
  Level: TAtlasSafeLevel;
begin
  for Level := Low(TAtlasSafeLevel) to High(TAtlasSafeLevel) do
  begin
    if SameText(LevelNames[Level], AText) then
    begin
      Exit(Level);
    end;
  end;
  Result := TAtlasSafeLevel.Normal;
end;

function ContainsText_(const AList: TArray<string>; const AText: string): Boolean;
var
  Item: string;
begin
  for Item in AList do
  begin
    if SameText(Item, AText) then
    begin
      Exit(True);
    end;
  end;
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
  begin
    if SameText(Failures[Index].Key, AFeature) then
    begin
      Failures[Index] := TPair<string, Integer>.Create(Failures[Index].Key, Failures[Index].Value + 1);
      Exit;
    end;
  end;
  Failures := Failures + [TPair<string, Integer>.Create(AFeature, 1)];
end;

function TAtlasSessionMarker.FailureCount(const AFeature: string): Integer;
var
  Pair: TPair<string, Integer>;
begin
  for Pair in Failures do
  begin
    if SameText(Pair.Key, AFeature) then
    begin
      Exit(Pair.Value);
    end;
  end;
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
    begin
      List.Add(Name);
    end;
    Root.AddPair('features', List);
    Counts := TJSONObject.Create;
    for Pair in Failures do
    begin
      Counts.AddPair(Pair.Key, TJSONNumber.Create(Pair.Value));
    end;
    Root.AddPair('failures', Counts);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

/// <summary>ISO-8601-Zeitpunkt (UTC); 0 bei leerem oder ungültigem Text.</summary>
function MarkerDateOf(const AStamp: string): TDateTime;
begin
  Result := 0;
  if AStamp = '' then
  begin
    Exit;
  end;
  try
    Result := ISO8601ToDate(AStamp, True);
  except
    on EConvertError do
    begin
      Result := 0;
    end;
  end;
end;

function MarkerFeaturesOf(const AValue: TJSONValue): TArray<string>;
var
  mElement: TJSONValue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mElement in TJSONArray(AValue) do
  begin
    if mElement is TJSONString then
    begin
      Result := Result + [TJSONString(mElement).Value];
    end;
  end;
end;

function MarkerFailuresOf(const AValue: TJSONValue): TArray<TPair<string, Integer>>;
var
  mPair: TJSONPair;
begin
  Result := nil;
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  for mPair in TJSONObject(AValue) do
  begin
    if mPair.JsonValue is TJSONNumber then
    begin
      Result := Result + [TPair<string, Integer>.Create(mPair.JsonString.Value, TJSONNumber(mPair.JsonValue).AsInt)];
    end;
  end;
end;

class function TAtlasSessionMarker.FromJson(const AText: string; out AMarker: TAtlasSessionMarker): Boolean;
var
  mRoot, mValue: TJSONValue;
begin
  AMarker := Default(TAtlasSessionMarker);
  Result := False;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    mValue := TJSONObject(mRoot).GetValue('processId');
    if not (mValue is TJSONNumber) then
    begin
      Exit;
    end;
    AMarker.ProcessId := Cardinal(TJSONNumber(mValue).AsInt64);
    AMarker.Version := TJSONObject(mRoot).GetValue<string>('version', '');
    AMarker.StartedAt := MarkerDateOf(TJSONObject(mRoot).GetValue<string>('startedAt', ''));
    mValue := TJSONObject(mRoot).GetValue('loaded');
    AMarker.Loaded := (mValue is TJSONBool) and TJSONBool(mValue).AsBoolean;
    mValue := TJSONObject(mRoot).GetValue('loadMs');
    AMarker.LoadMs := -1;
    if mValue is TJSONNumber then
    begin
      AMarker.LoadMs := TJSONNumber(mValue).AsInt64;
    end;
    AMarker.Level := LevelOf(TJSONObject(mRoot).GetValue<string>('level', ''));
    AMarker.Features := MarkerFeaturesOf(TJSONObject(mRoot).GetValue('features'));
    AMarker.Failures := MarkerFailuresOf(TJSONObject(mRoot).GetValue('failures'));
    Result := True;
  finally
    mRoot.Free;
  end;
end;

{ TAtlasSafeOptions }

class function TAtlasSafeOptions.Create(AAsk, AAuto: Boolean; AKey: TAtlasStartupKey): TAtlasSafeOptions;
begin
  Result.AskAfterCrash := AAsk;
  Result.AutoAfterRepeatedCrash := AAuto;
  Result.StartupKey := AKey;
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
    begin
      Root.AddPair('lastCrashAt', TJSONString.Create(DateToISO8601(LastCrashAt, True)));
    end;
    Crashed := nil;
    if CrashedMarker <> '' then
    begin
      Crashed := TJSONObject.ParseJSONValue(CrashedMarker);
    end;
    if Crashed is TJSONObject then
    begin
      Root.AddPair('crashed', Crashed);
    end
    else
    begin
      Crashed.Free;
    end;
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
    begin
      Exit;
    end;
    Value := TJSONObject(Root).GetValue('crashCount');
    if Value is TJSONNumber then
    begin
      Result.CrashCount := Max(0, TJSONNumber(Value).AsInt);
    end;
    Stamp := TJSONObject(Root).GetValue<string>('lastCrashAt', '');
    if Stamp <> '' then
      try
        Result.LastCrashAt := ISO8601ToDate(Stamp, True);
      except
        on EConvertError do
          Result.LastCrashAt := 0;
      end;
    // "slowStart" älterer Fassungen bleibt unbeachtet: Ein langsamer Start ist kein Absturz (Bericht N4).
    Value := TJSONObject(Root).GetValue('crashed');
    if Value is TJSONObject then
    begin
      Result.CrashedMarker := Value.ToJSON;
    end;
  finally
    Root.Free;
  end;
end;

{ TAtlasSafeMode }

/// <summary>Zählt einen Absturz in AState und merkt die zuletzt gestartete abgestürzte Sitzung; True, wenn er
/// binnen ARepeatMinutes nach dem letzten kam.</summary>
function RecordCrash(var AState: TAtlasSafeState; const ACrashed: TArray<TAtlasSessionMarker>; ANow: TDateTime;
  ARepeatMinutes: Integer): Boolean;
var
  mLatest, mMarker: TAtlasSessionMarker;
begin
  Result := (AState.CrashCount > 0) and (AState.LastCrashAt > 0) and
    (MinutesBetween(ANow, AState.LastCrashAt) < ARepeatMinutes) and (ANow >= AState.LastCrashAt);
  if Result then
  begin
    Inc(AState.CrashCount);
  end
  else
  begin
    AState.CrashCount := 1;
  end;
  AState.LastCrashAt := ANow;
  // Für „Details“ die zuletzt gestartete abgestürzte Sitzung.
  mLatest := ACrashed[0];
  for mMarker in ACrashed do
  begin
    if mMarker.StartedAt > mLatest.StartedAt then
    begin
      mLatest := mMarker;
    end;
  end;
  AState.CrashedMarker := mLatest.ToJson;
end;

class function TAtlasSafeMode.Decide(var AState: TAtlasSafeState; const ACrashed: TArray<TAtlasSessionMarker>;
  ANow: TDateTime; const AOptions: TAtlasSafeOptions; AKeyDown: TAtlasStartupKey;
  AForced: Boolean): TAtlasSafeDecision;
var
  mRepeated: Boolean;
begin
  Result := Default(TAtlasSafeDecision);
  Result.Crashed := Length(ACrashed) > 0;
  mRepeated := Result.Crashed and RecordCrash(AState, ACrashed, ANow, RepeatWindowMinutes);
  if AForced then
  begin
    Result.Level := TAtlasSafeLevel.Minimal;
    Result.Reason := TAtlasSafeReason.Forced;
  end
  else if (AOptions.StartupKey <> TAtlasStartupKey.None) and (AKeyDown = AOptions.StartupKey) then
  begin
    Result.Level := TAtlasSafeLevel.Minimal;
    Result.Reason := TAtlasSafeReason.StartupKey;
  end
  else if mRepeated and AOptions.AutoAfterRepeatedCrash then
  begin
    Result.Level := TAtlasSafeLevel.Safe;
    Result.Reason := TAtlasSafeReason.RepeatedCrash;
  end
  else if Result.Crashed and AOptions.AskAfterCrash then
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

class function TAtlasSafeMode.IsForced(const AEnvironment: string; const AArgs: TArray<string>): Boolean;
var
  Arg, Value: string;
begin
  Value := Trim(AEnvironment);
  if SameText(Value, '1') or SameText(Value, 'true') or SameText(Value, 'yes') then
  begin
    Exit(True);
  end;
  for Arg in AArgs do
  begin
    if SameText(Arg, '-' + SwitchName) or SameText(Arg, '/' + SwitchName) or SameText(Arg, '--' + SwitchName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasSafeMode.KeyOf(const AText: string): TAtlasStartupKey;
begin
  if SameText(AText, 'ctrl') then
  begin
    Result := TAtlasStartupKey.Ctrl;
  end
  else if SameText(AText, 'none') then
  begin
    Result := TAtlasStartupKey.None;
  end
  else
  begin
    Result := TAtlasStartupKey.Shift;
  end;
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
  begin
    Result.Put(Toggle.Key, False);
  end;
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
  begin
    if TAtlasQuickToggles.Find(AToggles, Key, Toggle) and not ContainsText_(Result, Toggle.Key) then
    begin
      Result := Result + [Toggle.Key];
    end;
  end;
  // Dann Funktionen mit Fehlern in der abgestürzten Sitzung, die meisten zuerst; bei Gleichstand Katalog.
  Candidates := nil;
  for Toggle in AToggles do
  begin
    if (Toggle.Feature <> '') and (ACrashed.FailureCount(Toggle.Feature) > 0) and
      not ContainsText_(Result, Toggle.Key) then
    begin
      Candidates := Candidates + [TPair<string, Integer>.Create(Toggle.Key, ACrashed.FailureCount(Toggle.Feature))];
    end;
  end;
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
  begin
    Result := Result + [Candidates[Index].Key];
  end;
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
  begin
    Result := TryEncodeDateTime(Year, Month, Day, Hour, Minute, Second, Milli, AStamp);
  end;
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
    begin
      Inside := (Stamp >= AFrom) and ((ATo = 0) or (Stamp < ATo));
    end;
    if Inside then
    begin
      Result := Result + [Line];
    end;
  end;
  if (AMax >= 0) and (Length(Result) > AMax) then
  begin
    Result := Copy(Result, Length(Result) - AMax, AMax);
  end;
end;

class function TAtlasSafeMode.Details(const AMarker: TAtlasSessionMarker): TArray<string>;
var
  Pair: TPair<string, Integer>;
  Names: string;
begin
  Result := ['Atlas ' + AMarker.Version, 'Start: ' + DateToISO8601(AMarker.StartedAt, True)];
  if AMarker.Loaded then
  begin
    Result := Result + [Format(UiText(TSafeModeText.LoadingMs), [AMarker.LoadMs])];
  end
  else
  begin
    Result := Result + [UiText(TSafeModeText.LoadingNotFinished)];
  end;
  Result := Result + [UiText(TSafeModeText.Mode) + LevelNames[AMarker.Level]];
  Names := string.Join(', ', AMarker.Features);
  if Names = '' then
  begin
    Names := '–';
  end;
  Result := Result + [UiText(TSafeModeText.ActiveFeatures) + Names];
  if Length(AMarker.Failures) = 0 then
  begin
    Result := Result + [UiText(TSafeModeText.ErrorsNone)];
  end
  else
  begin
    for Pair in AMarker.Failures do
    begin
      Result := Result + [Format(UiText(TSafeModeText.Errors), [Pair.Key, Pair.Value])];
    end;
  end;
end;

{ TAtlasSessionFiles }

const
  MarkerPrefix = 'session-';

/// <summary>
/// Ersetzt AFileName in einem Schritt (Bericht N3): erst vollständig daneben schreiben, dann TFile.Replace
/// (unter Windows ReplaceFile). Früher erst löschen, dann umbenennen: Ein Absturz dazwischen ließ keine Marke
/// bzw. keinen Zustand zurück. Ohne TAtlasDataFile, weil das über TAtlasGuard protokolliert und Core.Diagnostics
/// Core.Files nicht verwenden darf (Feature-Zyklus). EInOutError, wenn die Datei nicht ersetzt wurde; sie bleibt
/// dann, wie sie war.
/// </summary>
procedure WriteFileSafely(const AFileName, AText: string);
var
  Temp, Backup: string;
begin
  ForceDirectories(ExtractFileDir(AFileName));
  Temp := AFileName + '.tmp';
  // TFile.Replace braucht eine Sicherungsdatei, sobald das Ziel existiert.
  Backup := AFileName + '.bak';
  TFile.WriteAllText(Temp, AText, TEncoding.UTF8);
  try
    if TFile.Exists(AFileName) then
    begin
      TFile.Replace(Temp, AFileName, Backup);
    end
    else
    begin
      TFile.Move(Temp, AFileName);
    end;
    // TFile.Replace meldet ein Scheitern von ReplaceFile nicht. Hat es das Ziel schon zur Sicherung umbenannt,
    // ohne die neue Datei nachzuschieben, gehört die vollständige neue an seine Stelle.
    if TFile.Exists(Temp) and not TFile.Exists(AFileName) then
    begin
      TFile.Move(Temp, AFileName);
    end;
    if TFile.Exists(Temp) then
    begin
      raise EInOutError.Create('Datei des abgesicherten Starts nicht ersetzt');
    end;
  finally
    if TFile.Exists(Temp) then
    begin
      TFile.Delete(Temp);
    end;
    if TFile.Exists(Backup) then
    begin
      TFile.Delete(Backup);
    end;
  end;
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
  begin
    TFile.Delete(MarkerFile(AFolder, AProcessId));
  end;
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
  begin
    Exit;
  end;
  for FileName in TDirectory.GetFiles(AFolder, MarkerPrefix + '*.json') do
  begin
    try
      Valid := TAtlasSessionMarker.FromJson(TFile.ReadAllText(FileName, TEncoding.UTF8), Marker);
    except
      Valid := False;
    end;
    if Valid and (Marker.ProcessId = AOwnProcessId) then
    begin
      Continue;
    end;
    if Valid and Assigned(AAlive) and AAlive(Marker.ProcessId, Marker.StartedAt) then
    begin
      Continue;
    end;
    if Valid then
    begin
      Result := Result + [Marker];
    end;
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
    begin
      Result := TAtlasSafeState.FromJson(TFile.ReadAllText(StateFile(AFolder), TEncoding.UTF8));
    end;
  except
    on Exception do
      Result := Default(TAtlasSafeState);
  end;
end;

class procedure TAtlasSessionFiles.WriteState(const AFolder: string; const AState: TAtlasSafeState);
begin
  WriteFileSafely(StateFile(AFolder), AState.ToJson);
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Diagnostics.SafeMode', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
