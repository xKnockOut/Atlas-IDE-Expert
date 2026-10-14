unit Atlas.Core.Diagnostics.Guard;

// Absturzsicherheit (#493), Teil ohne Windows und Open Tools API:
// - TAtlasGuard.Run: jeder Einstiegspunkt aus der IDE (Timer, Notifier,
//   Zeichnen, Tasten) läuft hierüber. Exceptions verlassen Atlas nie in
//   Richtung IDE; sie werden protokolliert und dem Feature angerechnet.
// - Sicherung: 3 Fehler eines Features innerhalb von 5 Minuten schalten nur
//   dieses Feature ab (Run tut dann nichts mehr), mit einer Warnung über
//   OnWarning. Wieder einschalten über Reset (Menü Atlas).
// - Sicherung je Quelle (Provider): ReportProvider zählt Fehler einer
//   einzelnen Datenquelle, etwa der Vervollständigung vom Server; nach 3
//   Fehlern in 5 Minuten fällt nur diese Quelle aus, die übrigen laufen weiter.
// - TAtlasRotatingLog: Protokoll unter %LOCALAPPDATA%\Atlas\Logs, höchstens
//   5 Dateien à 1 MB. Jede Fehlerzeile nennt Atlas-Version, Feature bzw.
//   Quelle, Fehlerklasse, Meldung (eine Zeile, gekürzt) und den Stack-Trace,
//   wenn ein Stack-Trace-Anbieter installiert ist; nie Quelltext aus dem Editor.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections;

type
{$SCOPEDENUMS ON}
  TAtlasFeature = (Completion, Signature, Hover, Pairs, Problems, Reloader, Palette, CheckOnSave, Watchdog, Server,
    Settings, Menu, Files, InlayHints, Results, EditorCommands, Forms, Build, Status);
{$SCOPEDENUMS OFF}

  TAtlasFeatures = set of TAtlasFeature;

  TAtlasRotatingLog = class
  private
    FFolder: string;
    FMaxBytes: Int64;
    FMaxFiles: Integer;
    FLock: TCriticalSection;
    procedure Rotate;
  public
    constructor Create(const AFolder: string; AMaxBytes: Int64 = 1024 * 1024; AMaxFiles: Integer = 5);
    destructor Destroy; override;
    /// <summary>Zeile mit Zeitstempel anhängen; Fehler beim Schreiben werden verschluckt.</summary>
    procedure Add(const AText: string);
    /// <summary>Aktuelle Datei (atlas.log); ältere heißen atlas.1.log … atlas.4.log.</summary>
    function FileName: string;
    /// <summary>Ordner der Protokolldateien (Tests stellen ihn um).</summary>
    property Folder: string read FFolder write FFolder;
    /// <summary>%LOCALAPPDATA%\Atlas\Logs.</summary>
    class function DefaultFolder: string; static;
  end;

  TAtlasFuse = class
  public const
    Limit = 3;
    WindowMinutes = 5;
  private
    FFailures: array[TAtlasFeature] of TArray<TDateTime>;
    FTripped: TAtlasFeatures;
    FProviderFailures: TDictionary<string, TArray<TDateTime>>;
    // Kleingeschriebener Name → Name wie gemeldet.
    FProvidersTripped: TDictionary<string, string>;
    FClock: TFunc<TDateTime>;
    FLock: TCriticalSection;
    /// <summary>Zählt einen Fehler zu AStamps; True, wenn es Limit Fehler im Zeitfenster sind.</summary>
    function Count(var AStamps: TArray<TDateTime>): Boolean;
  public
    constructor Create(const AClock: TFunc<TDateTime> = nil);
    destructor Destroy; override;
    /// <summary>Fehler zählen; True, wenn die Sicherung dadurch gerade auslöst.</summary>
    function Failed(AFeature: TAtlasFeature): Boolean;
    function Tripped(AFeature: TAtlasFeature): Boolean;
    function TrippedSet: TAtlasFeatures;
    procedure Reset(AFeature: TAtlasFeature);
    /// <summary>Wie Failed, für eine einzelne Quelle (Name ohne Groß-/Kleinschreibung).</summary>
    function ProviderFailed(const AName: string): Boolean;
    function ProviderTripped(const AName: string): Boolean;
    function TrippedProviders: TArray<string>;
    procedure ResetProvider(const AName: string);
    /// <summary>Alle Features und Quellen.</summary>
    procedure ResetAll;
  end;

  TAtlasGuardMessage = reference to procedure(const AText: string);

  TAtlasGuard = class
  private class var
    FFuse: TAtlasFuse;
    FLog: TAtlasRotatingLog;
    FOnWarning: TAtlasGuardMessage;
    FOnFailure: TProc<TAtlasFeature>;
    class procedure Warn(const AText: string); static;
    class function ErrorLine(const AWhere: string; E: Exception): string; static;
  public
    /// <summary>Höchstlänge einer Fehlermeldung im Protokoll; mehr könnte Quelltext enthalten.</summary>
    const MaxMessageLength = 300;
    class constructor Create;
    class destructor Destroy;
    /// <summary>Führt AProc geschützt aus; False bei Fehler oder abgeschaltetem Feature.</summary>
    class function Run(AFeature: TAtlasFeature; const AProc: TProc): Boolean; static;
    /// <summary>Fehler aus einem eigenen except-Block melden (zählt wie in Run).</summary>
    class procedure Report(AFeature: TAtlasFeature; E: Exception); static;
    /// <summary>Feature durch die Sicherung abgeschaltet?</summary>
    class function Disabled(AFeature: TAtlasFeature): Boolean; static;
    class procedure Enable(AFeature: TAtlasFeature); static;
    class procedure EnableAll; static;
    class function DisabledSet: TAtlasFeatures; static;
    /// <summary>Protokolliert eine Zeile ins rotierende Protokoll.</summary>
    class procedure Log(const AText: string); static;
    class function FeatureName(AFeature: TAtlasFeature): string; static;
    /// <summary>Fehler der Quelle AName melden; nach 3 in 5 Minuten fällt nur sie aus.</summary>
    class procedure ReportProvider(const AName: string; E: Exception); overload; static;
    class procedure ReportProvider(const AName, AMessage: string); overload; static;
    /// <summary>Führt AProc für die Quelle AName geschützt aus; False bei Fehler oder abgeschalteter Quelle.</summary>
    class function RunProvider(const AName: string; const AProc: TProc): Boolean; static;
    class function ProviderDisabled(const AName: string): Boolean; static;
    class procedure EnableProvider(const AName: string); static;
    class function DisabledProviders: TArray<string>; static;
    /// <summary>Meldung einzeilig und gekürzt, damit kein Quelltext ins Protokoll gelangt.</summary>
    class function SafeMessage(const AText: string): string; static;
    /// <summary>Warnungen für die Meldungsansicht (nie als Dialog).</summary>
    class property OnWarning: TAtlasGuardMessage read FOnWarning write FOnWarning;
    /// <summary>Nach jedem gezählten Fehler eines Features, aus jedem Thread (Startmarke des abgesicherten
    /// Starts, #722).</summary>
    class property OnFailure: TProc<TAtlasFeature> read FOnFailure write FOnFailure;
    class property Fuse: TAtlasFuse read FFuse;
    class property RotatingLog: TAtlasRotatingLog read FLog;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.Product.Version;

{ TAtlasRotatingLog }

constructor TAtlasRotatingLog.Create(const AFolder: string; AMaxBytes: Int64; AMaxFiles: Integer);
begin
  inherited Create;
  FFolder := AFolder;
  FMaxBytes := AMaxBytes;
  FMaxFiles := AMaxFiles;
  FLock := TCriticalSection.Create;
end;

destructor TAtlasRotatingLog.Destroy;
begin
  FLock.Free;
  inherited;
end;

class function TAtlasRotatingLog.DefaultFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), 'Logs');
end;

function TAtlasRotatingLog.FileName: string;
begin
  Result := TPath.Combine(FFolder, 'atlas.log');
end;

procedure TAtlasRotatingLog.Rotate;
var
  Index: Integer;
  Older, Newer: string;
begin
  // atlas.log → atlas.1.log → … → atlas.(Max-1).log; die älteste fällt weg.
  for Index := FMaxFiles - 1 downto 1 do
  begin
    Older := TPath.Combine(FFolder, Format('atlas.%d.log', [Index]));
    if Index = 1 then
      Newer := FileName
    else
      Newer := TPath.Combine(FFolder, Format('atlas.%d.log', [Index - 1]));
    if TFile.Exists(Older) then
      TFile.Delete(Older);
    if TFile.Exists(Newer) then
      TFile.Move(Newer, Older);
  end;
end;

procedure TAtlasRotatingLog.Add(const AText: string);
begin
  FLock.Enter;
  try
    try
      ForceDirectories(FFolder);
      if TFile.Exists(FileName) and (TFile.GetSize(FileName) >= FMaxBytes) then
        Rotate;
      TFile.AppendAllText(FileName, FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' ' + AText + sLineBreak,
        TEncoding.UTF8);
    except
      // Das Protokoll darf die IDE nie stören.
    end;
  finally
    FLock.Leave;
  end;
end;

{ TAtlasFuse }

constructor TAtlasFuse.Create(const AClock: TFunc<TDateTime>);
begin
  inherited Create;
  FClock := AClock;
  if not Assigned(FClock) then
    FClock :=
      function: TDateTime
      begin
        Result := Now;
      end;
  FLock := TCriticalSection.Create;
  FProviderFailures := TDictionary<string, TArray<TDateTime>>.Create;
  FProvidersTripped := TDictionary<string, string>.Create;
end;

destructor TAtlasFuse.Destroy;
begin
  FProvidersTripped.Free;
  FProviderFailures.Free;
  FLock.Free;
  inherited;
end;

function TAtlasFuse.Count(var AStamps: TArray<TDateTime>): Boolean;
var
  Time, Stamp: TDateTime;
  Recent: TArray<TDateTime>;
begin
  Time := FClock;
  Recent := nil;
  for Stamp in AStamps do
    if MinutesBetween(Time, Stamp) < WindowMinutes then
      Recent := Recent + [Stamp];
  Recent := Recent + [Time];
  AStamps := Recent;
  Result := Length(Recent) >= Limit;
end;

function TAtlasFuse.Failed(AFeature: TAtlasFeature): Boolean;
begin
  FLock.Enter;
  try
    Result := False;
    if AFeature in FTripped then
      Exit;
    if Count(FFailures[AFeature]) then
    begin
      Include(FTripped, AFeature);
      Result := True;
    end;
  finally
    FLock.Leave;
  end;
end;

function TAtlasFuse.ProviderFailed(const AName: string): Boolean;
var
  Key: string;
  Stamps: TArray<TDateTime>;
begin
  Key := AnsiLowerCase(AName);
  FLock.Enter;
  try
    Result := False;
    if FProvidersTripped.ContainsKey(Key) then
      Exit;
    if not FProviderFailures.TryGetValue(Key, Stamps) then
      Stamps := nil;
    if Count(Stamps) then
    begin
      FProvidersTripped.Add(Key, AName);
      Result := True;
    end;
    FProviderFailures.AddOrSetValue(Key, Stamps);
  finally
    FLock.Leave;
  end;
end;

function TAtlasFuse.ProviderTripped(const AName: string): Boolean;
begin
  FLock.Enter;
  try
    Result := FProvidersTripped.ContainsKey(AnsiLowerCase(AName));
  finally
    FLock.Leave;
  end;
end;

function TAtlasFuse.TrippedProviders: TArray<string>;
begin
  FLock.Enter;
  try
    Result := FProvidersTripped.Values.ToArray;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasFuse.ResetProvider(const AName: string);
var
  Key: string;
begin
  Key := AnsiLowerCase(AName);
  FLock.Enter;
  try
    FProvidersTripped.Remove(Key);
    FProviderFailures.Remove(Key);
  finally
    FLock.Leave;
  end;
end;

function TAtlasFuse.Tripped(AFeature: TAtlasFeature): Boolean;
begin
  FLock.Enter;
  try
    Result := AFeature in FTripped;
  finally
    FLock.Leave;
  end;
end;

function TAtlasFuse.TrippedSet: TAtlasFeatures;
begin
  FLock.Enter;
  try
    Result := FTripped;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasFuse.Reset(AFeature: TAtlasFeature);
begin
  FLock.Enter;
  try
    Exclude(FTripped, AFeature);
    FFailures[AFeature] := nil;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasFuse.ResetAll;
var
  Feature: TAtlasFeature;
begin
  for Feature := Low(TAtlasFeature) to High(TAtlasFeature) do
    Reset(Feature);
  FLock.Enter;
  try
    FProvidersTripped.Clear;
    FProviderFailures.Clear;
  finally
    FLock.Leave;
  end;
end;

{ TAtlasGuard }

class constructor TAtlasGuard.Create;
begin
  FFuse := TAtlasFuse.Create;
  FLog := TAtlasRotatingLog.Create(TAtlasRotatingLog.DefaultFolder);
end;

class destructor TAtlasGuard.Destroy;
begin
  FOnWarning := nil;
  FreeAndNil(FLog);
  FreeAndNil(FFuse);
end;

class function TAtlasGuard.FeatureName(AFeature: TAtlasFeature): string;
const
  Names: array[TAtlasFeature] of string = ('Vervollständigung', 'Parameter-Hint', 'Tooltip', 'Klammerpaare',
    'Probleme', 'Neuladen', 'Befehlspalette', 'Prüfung beim Speichern', 'Wächter', 'Server', 'Einstellungen', 'Menü',
    'Dateien', 'Inlay-Hints', 'Ergebnisfenster', 'Editorbefehle', 'Formulare', 'Compile-Ereignisse', 'Statusfeld');
begin
  Result := Names[AFeature];
end;

class procedure TAtlasGuard.Log(const AText: string);
begin
  if FLog <> nil then
    FLog.Add(AText);
end;

class function TAtlasGuard.SafeMessage(const AText: string): string;
var
  Builder: TStringBuilder;
  Ch: Char;
  Space: Boolean;
begin
  // Zeilenumbrüche und Steuerzeichen werden zu einem Leerzeichen; Folgen davon zu einem.
  Builder := TStringBuilder.Create;
  try
    Space := False;
    for Ch in AText do
      if CharInSet(Ch, [#0..#32]) then
        Space := True
      else
      begin
        if Space and (Builder.Length > 0) then
          Builder.Append(' ');
        Space := False;
        Builder.Append(Ch);
      end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
  if Length(Result) > MaxMessageLength then
    Result := Copy(Result, 1, MaxMessageLength) + '…';
end;

class function TAtlasGuard.ErrorLine(const AWhere: string; E: Exception): string;
var
  Trace: string;
begin
  Result := Format('Atlas %s · Fehler in %s: %s: %s', [TAtlasPluginVersion.Version, AWhere, E.ClassName,
    SafeMessage(E.Message)]);
  // Nur mit installiertem Stack-Trace-Anbieter (z. B. JCL, madExcept) gefüllt.
  Trace := Trim(E.StackTrace);
  if Trace <> '' then
    Result := Result + sLineBreak + '  Stack: ' + StringReplace(Trace, sLineBreak, sLineBreak + '  ', [rfReplaceAll]);
end;

class procedure TAtlasGuard.Warn(const AText: string);
begin
  Log(AText);
  if Assigned(FOnWarning) then
    try
      FOnWarning(AText);
    except
      // Auch die Warnung darf nicht in die IDE durchschlagen.
    end;
end;

class procedure TAtlasGuard.Report(AFeature: TAtlasFeature; E: Exception);
var
  Failure: TProc<TAtlasFeature>;
begin
  Log(ErrorLine(FeatureName(AFeature), E));
  Failure := FOnFailure;
  if Assigned(Failure) then
    try
      Failure(AFeature);
    except
      // Die Meldung eines Fehlers darf selbst keinen auslösen.
    end;
  if (FFuse <> nil) and FFuse.Failed(AFeature) then
    Warn(Format('Atlas: %s nach %d Fehlern in %d Minuten abgeschaltet (zuletzt: %s). ' +
      'Wieder einschalten unter Tools > Optionen > Drittanbieter > Atlas oder über Atlas > Abgeschaltete ' +
      'Funktionen einschalten.', [FeatureName(AFeature), TAtlasFuse.Limit, TAtlasFuse.WindowMinutes,
      SafeMessage(E.Message)]));
end;

class procedure TAtlasGuard.ReportProvider(const AName: string; E: Exception);
begin
  Log(ErrorLine('Quelle ' + AName, E));
  if (FFuse <> nil) and FFuse.ProviderFailed(AName) then
    Warn(Format('Atlas: Quelle „%s“ nach %d Fehlern in %d Minuten abgeschaltet (zuletzt: %s); die übrigen ' +
      'Quellen laufen weiter. Wieder einschalten unter Tools > Optionen > Drittanbieter > Atlas oder über ' +
      'Atlas > Abgeschaltete Funktionen einschalten.', [AName, TAtlasFuse.Limit, TAtlasFuse.WindowMinutes,
      SafeMessage(E.Message)]));
end;

class procedure TAtlasGuard.ReportProvider(const AName, AMessage: string);
var
  Error: Exception;
begin
  Error := Exception.Create(AMessage);
  try
    ReportProvider(AName, Error);
  finally
    Error.Free;
  end;
end;

class function TAtlasGuard.RunProvider(const AName: string; const AProc: TProc): Boolean;
begin
  if ProviderDisabled(AName) then
    Exit(False);
  try
    AProc();
    Result := True;
  except
    on E: EAbort do
      Result := False;
    on E: Exception do
    begin
      ReportProvider(AName, E);
      Result := False;
    end;
  end;
end;

class function TAtlasGuard.ProviderDisabled(const AName: string): Boolean;
begin
  Result := (FFuse <> nil) and FFuse.ProviderTripped(AName);
end;

class procedure TAtlasGuard.EnableProvider(const AName: string);
begin
  if FFuse <> nil then
    FFuse.ResetProvider(AName);
  Log(Format('Quelle %s wieder eingeschaltet', [AName]));
end;

class function TAtlasGuard.DisabledProviders: TArray<string>;
begin
  if FFuse = nil then
    Result := nil
  else
    Result := FFuse.TrippedProviders;
end;

class function TAtlasGuard.Run(AFeature: TAtlasFeature; const AProc: TProc): Boolean;
begin
  if Disabled(AFeature) then
    Exit(False);
  try
    AProc();
    Result := True;
  except
    on E: EAbort do
      Result := False;
    on E: Exception do
    begin
      Report(AFeature, E);
      Result := False;
    end;
  end;
end;

class function TAtlasGuard.Disabled(AFeature: TAtlasFeature): Boolean;
begin
  Result := (FFuse <> nil) and FFuse.Tripped(AFeature);
end;

class function TAtlasGuard.DisabledSet: TAtlasFeatures;
begin
  if FFuse = nil then
    Result := []
  else
    Result := FFuse.TrippedSet;
end;

class procedure TAtlasGuard.Enable(AFeature: TAtlasFeature);
begin
  if FFuse <> nil then
    FFuse.Reset(AFeature);
  Log(Format('%s wieder eingeschaltet', [FeatureName(AFeature)]));
end;

class procedure TAtlasGuard.EnableAll;
var
  Feature: TAtlasFeature;
  Name: string;
begin
  for Feature in DisabledSet do
    Enable(Feature);
  for Name in DisabledProviders do
    EnableProvider(Name);
end;

end.
