unit Atlas.Core.Diagnostics.Guard;

// Absturzsicherheit (#493), Teil ohne Windows und Open Tools API:
// - TAtlasGuard.Run: jeder Einstiegspunkt aus der IDE (Timer, Notifier,
//   Zeichnen, Tasten) läuft hierüber. Exceptions verlassen Atlas nie in
//   Richtung IDE; sie werden protokolliert und dem Feature angerechnet.
// - Sicherung: 3 Fehler eines Features innerhalb von 5 Minuten schalten nur
//   dieses Feature ab (Run tut dann nichts mehr), mit einer Warnung über
//   OnWarning. Wieder einschalten über Reset (Menü Atlas).
// - TAtlasRotatingLog: Protokoll unter %LOCALAPPDATA%\Atlas\Logs, höchstens
//   5 Dateien à 1 MB. Es enthält Feature, Fehlerklasse und Meldung, nie
//   Quelltext aus dem Editor.

interface

uses
  System.SysUtils,
  System.SyncObjs;

type
{$SCOPEDENUMS ON}
  TAtlasFeature = (Completion, Signature, Hover, Pairs, Problems, Reloader, Palette, CheckOnSave, Watchdog, Server,
    Settings, Menu, Files);
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
    FClock: TFunc<TDateTime>;
    FLock: TCriticalSection;
  public
    constructor Create(const AClock: TFunc<TDateTime> = nil);
    destructor Destroy; override;
    /// <summary>Fehler zählen; True, wenn die Sicherung dadurch gerade auslöst.</summary>
    function Failed(AFeature: TAtlasFeature): Boolean;
    function Tripped(AFeature: TAtlasFeature): Boolean;
    function TrippedSet: TAtlasFeatures;
    procedure Reset(AFeature: TAtlasFeature);
    procedure ResetAll;
  end;

  TAtlasGuardMessage = reference to procedure(const AText: string);

  TAtlasGuard = class
  private class var
    FFuse: TAtlasFuse;
    FLog: TAtlasRotatingLog;
    FOnWarning: TAtlasGuardMessage;
  public
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
    /// <summary>Warnungen für die Meldungsansicht (nie als Dialog).</summary>
    class property OnWarning: TAtlasGuardMessage read FOnWarning write FOnWarning;
    class property Fuse: TAtlasFuse read FFuse;
    class property RotatingLog: TAtlasRotatingLog read FLog;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils;

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
end;

destructor TAtlasFuse.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TAtlasFuse.Failed(AFeature: TAtlasFeature): Boolean;
var
  Time, Stamp: TDateTime;
  Recent: TArray<TDateTime>;
begin
  FLock.Enter;
  try
    Result := False;
    if AFeature in FTripped then
      Exit;
    Time := FClock;
    Recent := nil;
    for Stamp in FFailures[AFeature] do
      if MinutesBetween(Time, Stamp) < WindowMinutes then
        Recent := Recent + [Stamp];
    Recent := Recent + [Time];
    FFailures[AFeature] := Recent;
    if Length(Recent) >= Limit then
    begin
      Include(FTripped, AFeature);
      Result := True;
    end;
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
    'Dateien');
begin
  Result := Names[AFeature];
end;

class procedure TAtlasGuard.Log(const AText: string);
begin
  if FLog <> nil then
    FLog.Add(AText);
end;

class procedure TAtlasGuard.Report(AFeature: TAtlasFeature; E: Exception);
var
  Text: string;
begin
  Text := Format('Fehler in %s: %s: %s', [FeatureName(AFeature), E.ClassName, E.Message]);
  Log(Text);
  if (FFuse <> nil) and FFuse.Failed(AFeature) then
  begin
    Text := Format('Atlas: %s nach %d Fehlern in %d Minuten abgeschaltet (zuletzt: %s). ' +
      'Wieder einschalten über Atlas > Abgeschaltete Funktionen einschalten.',
      [FeatureName(AFeature), TAtlasFuse.Limit, TAtlasFuse.WindowMinutes, E.Message]);
    Log(Text);
    if Assigned(FOnWarning) then
      try
        FOnWarning(Text);
      except
        // Auch die Warnung darf nicht in die IDE durchschlagen.
      end;
  end;
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
begin
  for Feature in DisabledSet do
    Enable(Feature);
end;

end.
