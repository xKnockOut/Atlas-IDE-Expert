unit Atlas.Core.Build.CheckOnSave;

// Compilerprüfung im Hintergrund nach dem Speichern (#548), ohne Open Tools
// API: wann eine Prüfung fällig ist und wann die Automatik für ein Projekt
// abschaltet.
// - Speichern einer Unit des aktiven Projekts merkt eine Prüfung vor; sie ist
//   DelayMs nach dem letzten Speichern fällig (weiteres Speichern verschiebt).
// - Während eines Builds des Benutzers und im Debugger keine Prüfung; was
//   vorgemerkt war, bleibt vorgemerkt. Ein Build läuft, solange eine Gruppe
//   oder ein Projekt übersetzt wird, und bis QuietMs nach dem letzten
//   Compile-Ereignis (TAtlasBuildIdleGate). Ein Ja/Nein reichte nicht: Beim
//   Bauen einer Gruppe meldete schon das Ende des ersten Projekts „kein
//   Build“, und die Prüfung startete den Compiler mitten im laufenden
//   Gruppen-Build ein zweites Mal (interne Fehler F2084 des Compilers).
// - Dauert eine Prüfung länger als MaxMs, ist die Automatik für das Projekt
//   aus (einmal gemeldet); von Hand geht es weiter.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Build.IdleGate;

type
  TAtlasCheckOnSave = class
  public const
    /// <summary>Wartezeit nach dem Speichern bis zur Prüfung.</summary>
    cDefaultDelayMs = 2000;
    /// <summary>Dauert eine automatische Prüfung länger, schaltet die Automatik für das Projekt ab.</summary>
    cDefaultMaxMs = 1500;
  private
    FDelayMs: Integer;
    FMaxMs: Integer;
    FPending: Boolean;
    FDueAt: Int64;
    FProject: string;
    FBuild: TAtlasBuildIdleGate;
    FDisabled: TDictionary<string, Boolean>;
  public
    constructor Create(ADelayMs, AMaxMs: Integer); overload;
    /// <summary>Wie oben mit AMaxMs = cDefaultMaxMs.</summary>
    constructor Create(ADelayMs: Integer); overload;
    /// <summary>Wie oben mit ADelayMs = cDefaultDelayMs und AMaxMs = cDefaultMaxMs.</summary>
    constructor Create; overload;
    destructor Destroy; override;
    /// <summary>AFileName gehört zu AProject (aktives Projekt) und wurde gespeichert.</summary>
    procedure Saved(const AProject: string; ANowMs: Int64);
    /// <summary>Eine Prüfung ist fällig; ADebugging: der Debugger läuft.</summary>
    function Due(ANowMs: Int64; ADebugging: Boolean): Boolean;
    /// <summary>Projekt der fälligen Prüfung; setzt die Vormerkung zurück.</summary>
    function Take: string;
    /// <summary>Compile-Ereignisse des Benutzers (nicht die eigene Prüfung); ANowMs wie bei Saved.</summary>
    procedure GroupStarted(ANowMs: Int64);
    procedure GroupFinished(ANowMs: Int64);
    procedure ProjectStarted(ANowMs: Int64);
    procedure ProjectFinished(ANowMs: Int64);
    /// <summary>Kein Build des Benutzers aktiv und die Ruhezeit danach vorbei.</summary>
    function BuildIdle(ANowMs: Int64): Boolean;
    /// <summary>Ende einer automatischen Prüfung; True, wenn die Automatik für AProject jetzt abschaltet.</summary>
    function CheckFinished(const AProject: string; ADurationMs: Int64): Boolean;
    function IsDisabled(const AProject: string): Boolean;
    /// <summary>Gehört die gespeicherte Datei AFileName zum Projekt AProjectFile mit den Moduldateien AModules?
    /// Auch .dpr bzw. .dpk neben der Projektdatei.</summary>
    class function Belongs(const AProjectFile: string; const AModules: TArray<string>;
      const AFileName: string): Boolean; static;
    property DelayMs: Integer read FDelayMs write FDelayMs;
    property MaxMs: Integer read FMaxMs write FMaxMs;
  end;

implementation

{ TAtlasCheckOnSave }

constructor TAtlasCheckOnSave.Create(ADelayMs, AMaxMs: Integer);
begin
  inherited Create;
  FDelayMs := ADelayMs;
  FMaxMs := AMaxMs;
  FDisabled := TDictionary<string, Boolean>.Create;
  FBuild := TAtlasBuildIdleGate.Create(0);
end;

constructor TAtlasCheckOnSave.Create(ADelayMs: Integer);
begin
  Create(ADelayMs, cDefaultMaxMs);
end;

constructor TAtlasCheckOnSave.Create;
begin
  Create(cDefaultDelayMs, cDefaultMaxMs);
end;

destructor TAtlasCheckOnSave.Destroy;
begin
  FBuild.Free;
  FDisabled.Free;
  inherited;
end;

procedure TAtlasCheckOnSave.Saved(const AProject: string; ANowMs: Int64);
begin
  if (AProject = '') or IsDisabled(AProject) then
  begin
    Exit;
  end;
  FPending := True;
  FProject := AProject;
  FDueAt := ANowMs + FDelayMs;
end;

function TAtlasCheckOnSave.Due(ANowMs: Int64; ADebugging: Boolean): Boolean;
begin
  Result := FPending and (ANowMs >= FDueAt) and BuildIdle(ANowMs) and not ADebugging and not IsDisabled(FProject);
end;

function TAtlasCheckOnSave.Take: string;
begin
  Result := FProject;
  FPending := False;
end;

procedure TAtlasCheckOnSave.GroupStarted(ANowMs: Int64);
begin
  FBuild.GroupStarted(UInt64(ANowMs));
end;

procedure TAtlasCheckOnSave.GroupFinished(ANowMs: Int64);
begin
  FBuild.GroupFinished(UInt64(ANowMs));
end;

procedure TAtlasCheckOnSave.ProjectStarted(ANowMs: Int64);
begin
  FBuild.ProjectStarted(UInt64(ANowMs));
end;

procedure TAtlasCheckOnSave.ProjectFinished(ANowMs: Int64);
begin
  FBuild.ProjectFinished(UInt64(ANowMs));
end;

function TAtlasCheckOnSave.BuildIdle(ANowMs: Int64): Boolean;
begin
  Result := FBuild.Idle(UInt64(ANowMs));
end;

function TAtlasCheckOnSave.CheckFinished(const AProject: string; ADurationMs: Int64): Boolean;
begin
  Result := (ADurationMs > FMaxMs) and not IsDisabled(AProject);
  if Result then
  begin
    FDisabled.AddOrSetValue(UpperCase(AProject), True);
  end;
end;

function TAtlasCheckOnSave.IsDisabled(const AProject: string): Boolean;
begin
  Result := FDisabled.ContainsKey(UpperCase(AProject));
end;

class function TAtlasCheckOnSave.Belongs(const AProjectFile: string; const AModules: TArray<string>;
  const AFileName: string): Boolean;
const
  cSources: array[0..1] of string = ('.dpr', '.dpk');
var
  mModule, mExtension: string;
begin
  for mModule in AModules do
  begin
    if SameText(mModule, AFileName) then
    begin
      Exit(True);
    end;
  end;
  for mExtension in cSources do
  begin
    if SameText(ChangeFileExt(AProjectFile, mExtension), AFileName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

end.