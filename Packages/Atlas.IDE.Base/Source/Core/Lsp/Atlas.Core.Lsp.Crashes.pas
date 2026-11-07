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
    cStderrName = 'server-stderr.log';
    cStderrOldName = 'server-stderr.1.log';
    /// <summary>Ab dieser Größe wird die Datei beim Start beiseitegelegt.</summary>
    cStderrMaxBytes = 1024 * 1024;
    /// <summary>STILL_ACTIVE: Der Prozess lief beim Ende der Verbindung noch; der Code ist unbekannt.</summary>
    cUnknown = 259;
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
    cWindowMinutes = 10;
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
  System.DateUtils,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TCrashesText = (Exception0x8X, WithoutErrorCode0, Code1UnhandledExceptionOr, RuntimeError217UnhandledException,
    ExitCodeUnknownProcessWas);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TCrashesText] of string = (
    ('Ausnahme 0x%.8X',
     'ohne Fehler (Code 0)',
     'Code 1 (unbehandelte Ausnahme oder von außen beendet)',
     'Laufzeitfehler 217 (unbehandelte Ausnahme)',
     'Exit-Code unbekannt (Prozess lief beim Ende der Verbindung noch)'),
    ('Exception 0x%.8X',
     'without error (code 0)',
     'code 1 (unhandled exception or terminated from outside)',
     'runtime error 217 (unhandled exception)',
     'exit code unknown (process was still running when the connection ended)'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TCrashesText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

{ TAtlasServerExits }

const
  // Bekannte Codes mit Namen; Describe nennt sie mit dem Code in Hex.
  cNamedExitCodes: array[0..13] of Cardinal = ($0EEDFADE, $40010004, $C0000005, $C0000017, $C000001D, $C0000094,
    $C0000096, $C00000FD, $C000013A, $C0000135, $C0000142, $C0000374, $C0000409, $C0000420);
  cNamedExitTexts: array[TAtlasLanguage, 0..13] of string = (
    ('unbehandelte Delphi-Ausnahme',
     'von außen beendet (Abmelden oder Debugger)', 'Zugriffsverletzung', 'zu wenig Speicher',
     'unzulässiger Befehl', 'Ganzzahl-Division durch null', 'privilegierter Befehl', 'Stapelüberlauf',
     'mit Strg+C abgebrochen', 'DLL nicht gefunden', 'DLL-Initialisierung fehlgeschlagen', 'Heap beschädigt',
     'Sicherheitsabbruch (Stackpuffer-Überlauf oder Fast-Fail)', 'Assertion fehlgeschlagen'),
    ('unhandled Delphi exception', 'terminated from outside (logoff or debugger)', 'access violation',
     'out of memory', 'illegal instruction', 'integer division by zero', 'privileged instruction', 'stack overflow',
     'cancelled with Ctrl+C', 'DLL not found', 'DLL initialization failed', 'heap corrupted',
     'security abort (stack buffer overrun or fast fail)', 'assertion failed'));

/// <summary>Name eines bekannten Codes aus NamedExitCodes; False für andere.</summary>
function NamedExitText(ACode: Cardinal; out AText: string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := Low(cNamedExitCodes) to High(cNamedExitCodes) do
  begin
    if cNamedExitCodes[mIndex] = ACode then
    begin
      AText := cNamedExitTexts[TAtlasTextLanguage.Current, mIndex];
      Exit(True);
    end;
  end;
  AText := '';
  Result := False;
end;

/// <summary>Beschreibung eines Codes ohne eigenen Text: Name mit Hex-Code, sonst Ausnahme oder Zahl.</summary>
function DescribeNamedExit(ACode: Cardinal): string;
var
  mName: string;
begin
  if NamedExitText(ACode, mName) then
  begin
    Result := Format('%s (0x%.8X)', [mName, ACode]);
  end
  else if ACode >= $80000000 then
  begin
    Result := Format(UiText(TCrashesText.Exception0x8X), [ACode]);
  end
  else
  begin
    Result := Format('Code %d', [ACode]);
  end;
end;

class function TAtlasServerExits.Describe(ACode: Cardinal): string;
begin
  case ACode of
    0:
      Result := UiText(TCrashesText.WithoutErrorCode0);
    1:
      Result := UiText(TCrashesText.Code1UnhandledExceptionOr);
    217:
      Result := UiText(TCrashesText.RuntimeError217UnhandledException);
    cUnknown:
      Result := UiText(TCrashesText.ExitCodeUnknownProcessWas);
  else
    Result := DescribeNamedExit(ACode);
  end;
end;

class function TAtlasServerExits.Runtime(AMs: Int64): string;
var
  mSeconds: Int64;
begin
  if AMs < 1000 then
  begin
    Exit('unter 1 s');
  end;
  mSeconds := AMs div 1000;
  if mSeconds < 60 then
  begin
    Exit(Format('%d s', [mSeconds]));
  end;
  if mSeconds < 3600 then
  begin
    Exit(Format('%d min %d s', [mSeconds div 60, mSeconds mod 60]));
  end;
  Result := Format('%d h %d min', [mSeconds div 3600, (mSeconds mod 3600) div 60]);
end;

class function TAtlasServerExits.Line(ACode: Cardinal; ARuntimeMs: Int64; const ALastMethod: string;
  const AOpenMethods: TArray<string>; AErrorLines: Integer): string;
begin
  Result := Format('Server beendet: %s nach %s', [Describe(ACode), Runtime(ARuntimeMs)]);
  if ALastMethod <> '' then
  begin
    Result := Result + '; letzte Anfrage ' + ALastMethod;
  end;
  if Length(AOpenMethods) > 0 then
  begin
    Result := Result + '; offen: ' + string.Join(', ', AOpenMethods);
  end;
  if AErrorLines > 0 then
  begin
    Result := Result + Format('; %d Zeilen auf stderr (%s)', [AErrorLines, cStderrName]);
  end
  else
  begin
    Result := Result + '; nichts auf stderr';
  end;
end;

class function TAtlasServerExits.StderrFileName(const AFolder: string): string;
begin
  Result := TPath.Combine(AFolder, cStderrName);
end;

class function TAtlasServerExits.StderrOldFileName(const AFolder: string): string;
begin
  Result := TPath.Combine(AFolder, cStderrOldName);
end;

{ TAtlasServerCrashes }

constructor TAtlasServerCrashes.Create(const AClock: TFunc<TDateTime>);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FClock := AClock;
  if not Assigned(FClock) then
  begin
    FClock :=
      function: TDateTime
      begin
        Result := Now;
      end;
  end;
end;

destructor TAtlasServerCrashes.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TAtlasServerCrashes.Crashed(ACode: Cardinal): Boolean;
var
  mTime: TDateTime;
begin
  FLock.Enter;
  try
    mTime := FClock();
    Result := not (FHas and (FLastCode = ACode) and (MinutesBetween(mTime, FLastAt) < cWindowMinutes));
    FHas := True;
    FLastCode := ACode;
    FLastAt := mTime;
    if not Result then
    begin
      FHeld := True;
    end;
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

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Lsp.Crashes', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
