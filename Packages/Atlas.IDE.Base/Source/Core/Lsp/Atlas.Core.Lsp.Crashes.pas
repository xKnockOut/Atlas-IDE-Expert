unit Atlas.Core.Lsp.Crashes;

// Ende des Serverprozesses, ohne Windows und Open Tools API:
// - TAtlasServerExits.Describe macht aus dem Exit-Code einen Text wie
//   „Stapelüberlauf (0xC00000FD)“. Bisher ging verloren, ob der Server sauber
//   endete oder an einem Stapelüberlauf oder einer Zugriffsverletzung starb;
//   genau das hielt die Suche nach #1094 lange auf.
// - TAtlasServerExits.Line ist die Zeile für atlas.log: Ursache, Laufzeit,
//   letzte Anfrage, beim Ende noch offene Anfragen und Zeilen auf stderr.
// - stderr des Servers geht nach server-stderr.log im Protokollordner statt
//   nach NUL (StderrFileName); ab StderrMaxBytes beim Start nach
//   server-stderr.1.log verschoben.
// - TAtlasServerCrashes: Endet der Server zweimal mit demselben Code innerhalb
//   von WindowMinutes, startet Atlas ihn nicht mehr still neu, sondern hält an
//   und bietet Neustart und Fehlerbericht an. Ein Neustart von Hand (Reset)
//   hebt das auf. Threadsicher: Crashed läuft im Lese-Thread der Sitzung.

interface

uses
  System.SysUtils,
  System.SyncObjs;

type
  TAtlasServerExits = class
  public const
    StderrName = 'server-stderr.log';
    StderrOldName = 'server-stderr.1.log';
    /// <summary>Ab dieser Größe wird die Datei beim Start beiseitegelegt.</summary>
    StderrMaxBytes = 1024 * 1024;
    /// <summary>STILL_ACTIVE: Der Prozess lief beim Ende der Verbindung noch; der Code ist unbekannt.</summary>
    Unknown = 259;
  public
    /// <summary>Ursache zum Exit-Code, z. B. „Stapelüberlauf (0xC00000FD)“ oder „Code 3“.</summary>
    class function Describe(ACode: Cardinal): string; static;
    /// <summary>„12 s“, „3 min 5 s“, „2 h 14 min“.</summary>
    class function Runtime(AMs: Int64): string; static;
    /// <summary>Protokollzeile zum Ende des Servers; ohne Pfade und ohne Quelltext.</summary>
    class function Line(ACode: Cardinal; ARuntimeMs: Int64; const ALastMethod: string;
      const AOpenMethods: TArray<string>; AErrorLines: Integer): string; static;
    class function StderrFileName(const AFolder: string): string; static;
    class function StderrOldFileName(const AFolder: string): string; static;
  end;

  TAtlasServerCrashes = class
  public const
    WindowMinutes = 10;
  private
    FLock: TCriticalSection;
    FClock: TFunc<TDateTime>;
    FHas: Boolean;
    FLastCode: Cardinal;
    FLastAt: TDateTime;
    FHeld: Boolean;
  public
    /// <summary>AClock nil: Now.</summary>
    constructor Create(const AClock: TFunc<TDateTime>);
    destructor Destroy; override;
    /// <summary>Der Server endete von selbst mit ACode. True: wie bisher neu starten; False: zweimal derselbe
    /// Code innerhalb von WindowMinutes, Atlas hält an (Held).</summary>
    function Crashed(ACode: Cardinal): Boolean;
    /// <summary>Neustart von Hand: wieder automatisch starten, Zählung von vorn.</summary>
    procedure Reset;
    function Held: Boolean;
    /// <summary>Code des letzten Absturzes; False ohne.</summary>
    function LastCode(out ACode: Cardinal): Boolean;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils;

{ TAtlasServerExits }

class function TAtlasServerExits.Describe(ACode: Cardinal): string;
var
  Name: string;
begin
  case ACode of
    0:
      Exit('ohne Fehler (Code 0)');
    1:
      Exit('Code 1 (unbehandelte Ausnahme oder von außen beendet)');
    217:
      Exit('Laufzeitfehler 217 (unbehandelte Ausnahme)');
    Unknown:
      Exit('Exit-Code unbekannt (Prozess lief beim Ende der Verbindung noch)');
    $0EEDFADE:
      Name := 'unbehandelte Delphi-Ausnahme';
    $40010004:
      Name := 'von außen beendet (Abmelden oder Debugger)';
    $C0000005:
      Name := 'Zugriffsverletzung';
    $C0000017:
      Name := 'zu wenig Speicher';
    $C000001D:
      Name := 'unzulässiger Befehl';
    $C0000094:
      Name := 'Ganzzahl-Division durch null';
    $C0000096:
      Name := 'privilegierter Befehl';
    $C00000FD:
      Name := 'Stapelüberlauf';
    $C000013A:
      Name := 'mit Strg+C abgebrochen';
    $C0000135:
      Name := 'DLL nicht gefunden';
    $C0000142:
      Name := 'DLL-Initialisierung fehlgeschlagen';
    $C0000374:
      Name := 'Heap beschädigt';
    $C0000409:
      Name := 'Sicherheitsabbruch (Stackpuffer-Überlauf oder Fast-Fail)';
    $C0000420:
      Name := 'Assertion fehlgeschlagen';
  else
    begin
      if ACode >= $80000000 then
        Exit(Format('Ausnahme 0x%.8X', [ACode]));
      Exit(Format('Code %d', [ACode]));
    end;
  end;
  Result := Format('%s (0x%.8X)', [Name, ACode]);
end;

class function TAtlasServerExits.Runtime(AMs: Int64): string;
var
  Seconds: Int64;
begin
  if AMs < 1000 then
    Exit('unter 1 s');
  Seconds := AMs div 1000;
  if Seconds < 60 then
    Exit(Format('%d s', [Seconds]));
  if Seconds < 3600 then
    Exit(Format('%d min %d s', [Seconds div 60, Seconds mod 60]));
  Result := Format('%d h %d min', [Seconds div 3600, (Seconds mod 3600) div 60]);
end;

class function TAtlasServerExits.Line(ACode: Cardinal; ARuntimeMs: Int64; const ALastMethod: string;
  const AOpenMethods: TArray<string>; AErrorLines: Integer): string;
begin
  Result := Format('Server beendet: %s nach %s', [Describe(ACode), Runtime(ARuntimeMs)]);
  if ALastMethod <> '' then
    Result := Result + '; letzte Anfrage ' + ALastMethod;
  if Length(AOpenMethods) > 0 then
    Result := Result + '; offen: ' + string.Join(', ', AOpenMethods);
  if AErrorLines > 0 then
    Result := Result + Format('; %d Zeilen auf stderr (%s)', [AErrorLines, StderrName])
  else
    Result := Result + '; nichts auf stderr';
end;

class function TAtlasServerExits.StderrFileName(const AFolder: string): string;
begin
  Result := TPath.Combine(AFolder, StderrName);
end;

class function TAtlasServerExits.StderrOldFileName(const AFolder: string): string;
begin
  Result := TPath.Combine(AFolder, StderrOldName);
end;

{ TAtlasServerCrashes }

constructor TAtlasServerCrashes.Create(const AClock: TFunc<TDateTime>);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FClock := AClock;
  if not Assigned(FClock) then
    FClock :=
      function: TDateTime
      begin
        Result := Now;
      end;
end;

destructor TAtlasServerCrashes.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TAtlasServerCrashes.Crashed(ACode: Cardinal): Boolean;
var
  Time: TDateTime;
begin
  FLock.Enter;
  try
    Time := FClock();
    Result := not (FHas and (FLastCode = ACode) and (MinutesBetween(Time, FLastAt) < WindowMinutes));
    FHas := True;
    FLastCode := ACode;
    FLastAt := Time;
    if not Result then
      FHeld := True;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasServerCrashes.Reset;
begin
  FLock.Enter;
  try
    FHas := False;
    FHeld := False;
  finally
    FLock.Leave;
  end;
end;

function TAtlasServerCrashes.Held: Boolean;
begin
  FLock.Enter;
  try
    Result := FHeld;
  finally
    FLock.Leave;
  end;
end;

function TAtlasServerCrashes.LastCode(out ACode: Cardinal): Boolean;
begin
  FLock.Enter;
  try
    Result := FHas;
    ACode := FLastCode;
  finally
    FLock.Leave;
  end;
end;

end.
