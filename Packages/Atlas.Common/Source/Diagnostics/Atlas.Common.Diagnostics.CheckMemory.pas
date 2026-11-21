unit Atlas.Common.Diagnostics.CheckMemory;

// Speicher eines Laufs von --check --timings (#1480). Ein einzelner Wert
// taugt nicht zum Vergleich zweier Fassungen: Wann er genommen wird, hängt
// davon ab, wie weit die übrigen Projekte der Gruppe mit ihrem Index sind.
// Darum vier Werte mit festem Zeitpunkt:
//
// - bereit: wenn der Index des Zielprojekts fertig ist (MarkReady, beim
//   ersten Mal),
// - Gruppe: wenn der Index aller Projekte der Gruppe fertig ist (MarkGroup),
// - Gipfel: der höchste Wert über den ganzen Lauf; ein Hintergrundthread
//   misst alle cSampleMs, dazu jeder Zeitpunkt oben,
// - Ende: nach der Prüfung (Finish).
//
// Gemessen wird über eine Funktion (im Server TShutdownLeaks.AllocatedBytes),
// damit Tests feste Werte vorgeben können. -1 heißt: nicht gemessen.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs;

type
  /// <summary>Belegter Speicher in Byte.</summary>
  TCheckMemoryMeasure = reference to function: Int64;

  TCheckMemoryTrack = class
  public const
    /// <summary>Abstand der Messungen im Hintergrund für den Gipfel.</summary>
    cSampleMs = 50;
  private type
    TSampler = class(TThread)
    private
      FOwner: TCheckMemoryTrack;
    protected
      procedure Execute; override;
    public
      constructor Create(AOwner: TCheckMemoryTrack);
    end;
  private
    FLock: TCriticalSection;
    FMeasure: TCheckMemoryMeasure;
    FWake: TEvent;
    FSampler: TSampler;
    FStopping: Boolean;
    FReadyBytes: Int64;
    FGroupBytes: Int64;
    FPeakBytes: Int64;
    FEndBytes: Int64;
    function Read(var AValue: Int64): Int64;
    procedure StopSampling;
  public
    constructor Create(const AMeasure: TCheckMemoryMeasure);
    destructor Destroy; override;
    /// <summary>Misst jetzt, merkt den Gipfel und liefert den Wert.</summary>
    function Sample: Int64;
    /// <summary>Misst im Hintergrund alle cSampleMs bis Finish bzw. zur Freigabe.</summary>
    procedure StartSampling;
    /// <summary>Index des Zielprojekts fertig; zählt nur beim ersten Mal.</summary>
    procedure MarkReady;
    /// <summary>Index eines Projekts fertig: beim Zielprojekt (AMain) MarkReady, sonst nur für den Gipfel messen.
    /// </summary>
    procedure IndexFinished(AMain: Boolean);
    /// <summary>Index aller Projekte der Gruppe fertig; ein späterer Aufruf ersetzt den Wert.</summary>
    procedure MarkGroup;
    /// <summary>Lauf zu Ende: hält das Messen im Hintergrund an und misst den Endwert (nur beim ersten Mal).
    /// </summary>
    procedure Finish;
    /// <summary>Bei bereitem Zielprojekt; -1 ohne.</summary>
    function ReadyBytes: Int64;
    /// <summary>Wenn alle Projekte der Gruppe fertig waren; -1 ohne.</summary>
    function GroupBytes: Int64;
    /// <summary>Höchster gemessener Wert; -1 ohne Messung.</summary>
    function PeakBytes: Int64;
    /// <summary>Nach Finish; -1 vorher.</summary>
    function EndBytes: Int64;
  end;

implementation

{ TCheckMemoryTrack.TSampler }

constructor TCheckMemoryTrack.TSampler.Create(AOwner: TCheckMemoryTrack);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FOwner := AOwner;
end;

procedure TCheckMemoryTrack.TSampler.Execute;
begin
  try
    while not FOwner.FStopping do
    begin
      FOwner.Sample;
      FOwner.FWake.WaitFor(TCheckMemoryTrack.cSampleMs);
    end;
  except
    // Scheitert eine Messung, endet nur das Messen im Hintergrund; der Gipfel bleibt
    // der bisher gemessene, die festen Zeitpunkte messen weiter selbst.
    on Exception do
      Exit;
  end;
end;

{ TCheckMemoryTrack }

constructor TCheckMemoryTrack.Create(const AMeasure: TCheckMemoryMeasure);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FWake := TEvent.Create(nil, False, False, '');
  FMeasure := AMeasure;
  FReadyBytes := -1;
  FGroupBytes := -1;
  FPeakBytes := -1;
  FEndBytes := -1;
end;

destructor TCheckMemoryTrack.Destroy;
begin
  StopSampling;
  FWake.Free;
  FLock.Free;
  FMeasure := nil;
  inherited Destroy;
end;

function TCheckMemoryTrack.Sample: Int64;
begin
  Result := FMeasure();
  FLock.Enter;
  try
    if Result > FPeakBytes then
    begin
      FPeakBytes := Result;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TCheckMemoryTrack.StartSampling;
begin
  if (FSampler <> nil) or FStopping then
  begin
    Exit;
  end;
  FSampler := TSampler.Create(Self);
  FSampler.Start;
end;

procedure TCheckMemoryTrack.MarkReady;
var
  mBytes: Int64;
begin
  mBytes := Sample;
  FLock.Enter;
  try
    if FReadyBytes < 0 then
    begin
      FReadyBytes := mBytes;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TCheckMemoryTrack.IndexFinished(AMain: Boolean);
begin
  if AMain then
  begin
    MarkReady;
  end
  else
  begin
    Sample;
  end;
end;

procedure TCheckMemoryTrack.MarkGroup;
var
  mBytes: Int64;
begin
  mBytes := Sample;
  FLock.Enter;
  try
    FGroupBytes := mBytes;
  finally
    FLock.Leave;
  end;
end;

procedure TCheckMemoryTrack.StopSampling;
begin
  FStopping := True;
  if FSampler <> nil then
  begin
    FWake.SetEvent;
    FSampler.WaitFor;
    FreeAndNil(FSampler);
  end;
end;

procedure TCheckMemoryTrack.Finish;
var
  mBytes: Int64;
begin
  StopSampling;
  if FEndBytes >= 0 then
  begin
    Exit;
  end;
  mBytes := Sample;
  FLock.Enter;
  try
    FEndBytes := mBytes;
  finally
    FLock.Leave;
  end;
end;

function TCheckMemoryTrack.Read(var AValue: Int64): Int64;
begin
  FLock.Enter;
  try
    Result := AValue;
  finally
    FLock.Leave;
  end;
end;

function TCheckMemoryTrack.ReadyBytes: Int64;
begin
  Result := Read(FReadyBytes);
end;

function TCheckMemoryTrack.GroupBytes: Int64;
begin
  Result := Read(FGroupBytes);
end;

function TCheckMemoryTrack.PeakBytes: Int64;
begin
  Result := Read(FPeakBytes);
end;

function TCheckMemoryTrack.EndBytes: Int64;
begin
  Result := Read(FEndBytes);
end;

end.
