unit Argus.Core.Build.CheckOnSave;

// Compilerprüfung im Hintergrund nach dem Speichern (#548), ohne Open Tools
// API: wann eine Prüfung fällig ist und wann die Automatik für ein Projekt
// abschaltet.
// - Speichern einer Unit des aktiven Projekts merkt eine Prüfung vor; sie ist
//   DelayMs nach dem letzten Speichern fällig (weiteres Speichern verschiebt).
// - Während eines Builds des Benutzers und im Debugger keine Prüfung; was
//   vorgemerkt war, bleibt vorgemerkt.
// - Dauert eine Prüfung länger als MaxMs, ist die Automatik für das Projekt
//   aus (einmal gemeldet); von Hand geht es weiter.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TArgusCheckOnSave = class
  private
    FDelayMs: Integer;
    FMaxMs: Integer;
    FPending: Boolean;
    FDueAt: Int64;
    FProject: string;
    FBuildRunning: Boolean;
    FDisabled: TDictionary<string, Boolean>;
  public
    constructor Create(ADelayMs: Integer = 2000; AMaxMs: Integer = 1500);
    destructor Destroy; override;
    /// <summary>AFileName gehört zu AProject (aktives Projekt) und wurde gespeichert.</summary>
    procedure Saved(const AProject: string; ANowMs: Int64);
    /// <summary>Eine Prüfung ist fällig; ADebugging: der Debugger läuft.</summary>
    function Due(ANowMs: Int64; ADebugging: Boolean): Boolean;
    /// <summary>Projekt der fälligen Prüfung; setzt die Vormerkung zurück.</summary>
    function Take: string;
    procedure BuildStarted;
    procedure BuildFinished;
    /// <summary>Ende einer automatischen Prüfung; True, wenn die Automatik für AProject jetzt abschaltet.</summary>
    function CheckFinished(const AProject: string; ADurationMs: Int64): Boolean;
    function IsDisabled(const AProject: string): Boolean;
    property DelayMs: Integer read FDelayMs write FDelayMs;
    property MaxMs: Integer read FMaxMs write FMaxMs;
    property BuildRunning: Boolean read FBuildRunning;
  end;

implementation

{ TArgusCheckOnSave }

constructor TArgusCheckOnSave.Create(ADelayMs, AMaxMs: Integer);
begin
  inherited Create;
  FDelayMs := ADelayMs;
  FMaxMs := AMaxMs;
  FDisabled := TDictionary<string, Boolean>.Create;
end;

destructor TArgusCheckOnSave.Destroy;
begin
  FDisabled.Free;
  inherited;
end;

procedure TArgusCheckOnSave.Saved(const AProject: string; ANowMs: Int64);
begin
  if (AProject = '') or IsDisabled(AProject) then
    Exit;
  FPending := True;
  FProject := AProject;
  FDueAt := ANowMs + FDelayMs;
end;

function TArgusCheckOnSave.Due(ANowMs: Int64; ADebugging: Boolean): Boolean;
begin
  Result := FPending and (ANowMs >= FDueAt) and not FBuildRunning and not ADebugging and not IsDisabled(FProject);
end;

function TArgusCheckOnSave.Take: string;
begin
  Result := FProject;
  FPending := False;
end;

procedure TArgusCheckOnSave.BuildStarted;
begin
  FBuildRunning := True;
end;

procedure TArgusCheckOnSave.BuildFinished;
begin
  FBuildRunning := False;
end;

function TArgusCheckOnSave.CheckFinished(const AProject: string; ADurationMs: Int64): Boolean;
begin
  Result := (ADurationMs > FMaxMs) and not IsDisabled(AProject);
  if Result then
    FDisabled.AddOrSetValue(UpperCase(AProject), True);
end;

function TArgusCheckOnSave.IsDisabled(const AProject: string): Boolean;
begin
  Result := FDisabled.ContainsKey(UpperCase(AProject));
end;

end.