unit Atlas.Core.Diagnostics.StartTimes;

// Startanteile (Bericht N4, zum Einfrier-Wächter #501), ohne Windows und Open
// Tools API: Wie lange hat Atlas selbst den Start der IDE aufgehalten, und
// womit? Ein langsamer Start ist kein Absturz; früher schaltete er beim
// nächsten Start alle Funktionen ab (#722), ohne dass man erfuhr, woran es
// lag. Jetzt misst Atlas seine Anteile und nennt sie, damit sich die Ursache
// beheben lässt.
// - Teile: jedes Feature beim Anmelden (TAtlasFeatureTable), die übrige
//   Anmeldung und Atlas-Aktionen (TAtlasActivity) bis zur freien
//   Nachrichtenschleife. Gleiche Namen werden addiert.
// - Die Zeit bis zur freien Nachrichtenschleife enthält auch die übrigen
//   Packages, den Desktop und das Projekt; was nicht Atlas ist, ist der Rest.
// - Nur Namen und Millisekunden, keine Pfade (Protokolle anonym, #647).

interface

uses
  System.SysUtils,
  System.SyncObjs;

type
  TAtlasStartPart = record
    Name: string;
    Ms: Int64;
  end;

  TAtlasStartTimes = class
  public const
    /// <summary>Kürzere Teile fallen aus der Aufzählung (Rauschen).</summary>
    MinPartMs = 20;
    /// <summary>Höchstens so viele Teile in der Aufzählung.</summary>
    MaxParts = 5;
  private
    FLock: TCriticalSection;
    FParts: TArray<TAtlasStartPart>;
    FClock: TFunc<Int64>;
  public
    /// <summary>Uhr in ms (monoton, TStopwatch).</summary>
    constructor Create; overload;
    /// <summary>AClock liefert ms; für Tests.</summary>
    constructor Create(const AClock: TFunc<Int64>); overload;
    destructor Destroy; override;
    /// <summary>Jetzt in ms nach der Uhr.</summary>
    function Clock: Int64;
    /// <summary>AMs zu AName addieren; aus jedem Thread. Negative Werte zählen als 0.</summary>
    procedure Add(const AName: string; AMs: Int64);
    /// <summary>AProc ausführen und seine Dauer zu AName addieren, auch wenn AProc eine Ausnahme wirft.</summary>
    procedure Measure(const AName: string; const AProc: TProc);
    /// <summary>Summe aller Teile: so lange hat Atlas den Start aufgehalten.</summary>
    function Total: Int64;
    /// <summary>Die AMax längsten Teile ab MinPartMs, absteigend; bei gleicher Dauer in der Reihenfolge des
    /// ersten Eintrags.</summary>
    function Slowest(AMax: Integer): TArray<TAtlasStartPart>;
    /// <summary>"Manager 1200 ms, Forms 300 ms" (die MaxParts längsten); '' ohne.</summary>
    function SlowestText: string;
    /// <summary>Länger als ALimitMs (safeMode.startupTimeoutMs, von den Einstellungen begrenzt)? Ohne Limit
    /// (0 oder kleiner) nie.</summary>
    class function IsSlow(ALoadMs: Int64; ALimitMs: Integer): Boolean; static;
    /// <summary>Protokollzeile: Startzeit bis zur freien Nachrichtenschleife, Atlas-Anteil und die längsten Teile;
    /// mit Zeitlimit, wenn der Start zu langsam war.</summary>
    function LogLine(ALoadMs: Int64; ALimitMs: Integer): string;
  end;

implementation

uses
  System.Math,
  System.Diagnostics;

{ TAtlasStartTimes }

constructor TAtlasStartTimes.Create;
var
  Ticks: TFunc<Int64>;
begin
  // Typisierte Variable: Delphi wählt zwischen Überladungen mit anonymer Methode als Argument nicht (E2250).
  Ticks :=
    function: Int64
    begin
      Result := TStopwatch.GetTimeStamp div (TStopwatch.Frequency div 1000);
    end;
  Create(Ticks);
end;

constructor TAtlasStartTimes.Create(const AClock: TFunc<Int64>);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FClock := AClock;
end;

destructor TAtlasStartTimes.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TAtlasStartTimes.Clock: Int64;
begin
  Result := FClock();
end;

procedure TAtlasStartTimes.Add(const AName: string; AMs: Int64);
var
  Index: Integer;
  Part: TAtlasStartPart;
begin
  FLock.Enter;
  try
    for Index := 0 to High(FParts) do
      if SameText(FParts[Index].Name, AName) then
      begin
        FParts[Index].Ms := FParts[Index].Ms + Max(AMs, Int64(0));
        Exit;
      end;
    Part.Name := AName;
    Part.Ms := Max(AMs, Int64(0));
    FParts := FParts + [Part];
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasStartTimes.Measure(const AName: string; const AProc: TProc);
var
  Started: Int64;
begin
  Started := Clock;
  try
    AProc();
  finally
    Add(AName, Clock - Started);
  end;
end;

function TAtlasStartTimes.Total: Int64;
var
  Part: TAtlasStartPart;
begin
  Result := 0;
  FLock.Enter;
  try
    for Part in FParts do
      Inc(Result, Part.Ms);
  finally
    FLock.Leave;
  end;
end;

function TAtlasStartTimes.Slowest(AMax: Integer): TArray<TAtlasStartPart>;
var
  Parts: TArray<TAtlasStartPart>;
  Part: TAtlasStartPart;
  Target: Integer;
begin
  FLock.Enter;
  try
    Parts := Copy(FParts);
  finally
    FLock.Leave;
  end;
  // Einfügen nach Dauer: stabil, wenige Teile.
  Result := nil;
  for Part in Parts do
  begin
    if Part.Ms < MinPartMs then
      Continue;
    Target := Length(Result);
    while (Target > 0) and (Result[Target - 1].Ms < Part.Ms) do
      Dec(Target);
    Insert(Part, Result, Target);
  end;
  if Length(Result) > Max(AMax, 0) then
    SetLength(Result, Max(AMax, 0));
end;

function TAtlasStartTimes.SlowestText: string;
var
  Part: TAtlasStartPart;
begin
  Result := '';
  for Part in Slowest(MaxParts) do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Format('%s %d ms', [Part.Name, Part.Ms]);
  end;
end;

class function TAtlasStartTimes.IsSlow(ALoadMs: Int64; ALimitMs: Integer): Boolean;
begin
  Result := (ALimitMs > 0) and (ALoadMs > ALimitMs);
end;

function TAtlasStartTimes.LogLine(ALoadMs: Int64; ALimitMs: Integer): string;
var
  Parts: string;
begin
  Result := Format('Start: %d ms bis zur freien Nachrichtenschleife', [ALoadMs]);
  if IsSlow(ALoadMs, ALimitMs) then
    Result := Result + Format(' (länger als %d ms)', [ALimitMs]);
  Result := Result + Format(', davon Atlas %d ms', [Total]);
  Parts := SlowestText;
  if Parts <> '' then
    Result := Result + ': ' + Parts;
end;

end.
