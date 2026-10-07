unit BDLsp.Common.Logging.Providers.Logger;

// Logger, der jeden Eintrag an alle registrierten Senken verteilt, deren
// Mindeststufe er erreicht. Fehler einer Senke werden verschluckt, damit
// Logging nie den Server zum Absturz bringt.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  BDLsp.Common.Logging.Contract;

type
  TLogger = class(TInterfacedObject, ILogger)
  private type
    TSinkEntry = record
      Sink: ILogSink;
      MinLevel: TLogLevel;
    end;
  private
    FSinks: TList<TSinkEntry>;
    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Registriert eine Senke für alle Einträge ab AMinLevel.</summary>
    procedure AddSink(const ASink: ILogSink; AMinLevel: TLogLevel);
    { ILogger }
    procedure Log(ALevel: TLogLevel; const AText: string);
    procedure Debug(const AText: string);
    procedure Info(const AText: string);
    procedure Warning(const AText: string);
    procedure Error(const AText: string);
  end;

implementation

{ TLogger }

constructor TLogger.Create;
begin
  inherited Create;
  FSinks := TList<TSinkEntry>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TLogger.Destroy;
begin
  FLock.Free;
  FSinks.Free;
  inherited;
end;

procedure TLogger.AddSink(const ASink: ILogSink; AMinLevel: TLogLevel);
var
  Entry: TSinkEntry;
begin
  Entry.Sink := ASink;
  Entry.MinLevel := AMinLevel;
  FLock.Enter;
  try
    FSinks.Add(Entry);
  finally
    FLock.Leave;
  end;
end;

procedure TLogger.Log(ALevel: TLogLevel; const AText: string);
var
  LogEntry: TLogEntry;
  SinkEntry: TSinkEntry;
begin
  LogEntry := TLogEntry.Create(Now, ALevel, AText);
  // Die Sperre hält auch die Ausgabe zusammen, damit Zeilen mehrerer Threads
  // sich in Datei und stderr nicht mischen.
  FLock.Enter;
  try
    for SinkEntry in FSinks do
      if ALevel >= SinkEntry.MinLevel then
        try
          SinkEntry.Sink.Write(LogEntry);
        except
          // Fehler einer Senke dürfen weder andere Senken noch den Aufrufer stören.
        end;
  finally
    FLock.Leave;
  end;
end;

procedure TLogger.Debug(const AText: string);
begin
  Log(TLogLevel.Debug, AText);
end;

procedure TLogger.Info(const AText: string);
begin
  Log(TLogLevel.Info, AText);
end;

procedure TLogger.Warning(const AText: string);
begin
  Log(TLogLevel.Warning, AText);
end;

procedure TLogger.Error(const AText: string);
begin
  Log(TLogLevel.Error, AText);
end;

end.
