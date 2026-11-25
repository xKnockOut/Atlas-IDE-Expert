unit Atlas.Common.Logging.Providers.Logger;

// Logger, der jeden Eintrag an alle registrierten Senken verteilt, deren
// Mindeststufe er erreicht. Fehler einer Senke enden in TReporting.Quietly
// (gezählt, sonst ohne Empfänger), damit Logging nie den Server zum Absturz
// bringt und die übrigen Senken weiter schreiben.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract;

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

uses
  Atlas.Text.Reporting;

/// <summary>AEntry an ASink; ein Fehler der Senke stört weder andere Senken noch den Aufrufer.</summary>
procedure WriteQuietly(const ASink: ILogSink; const AEntry: TLogEntry);
begin
  TReporting.Quietly(
    procedure
    begin
      ASink.Write(AEntry);
    end);
end;

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
  mEntry: TSinkEntry;
begin
  mEntry.Sink := ASink;
  mEntry.MinLevel := AMinLevel;
  FLock.Enter;
  try
    FSinks.Add(mEntry);
  finally
    FLock.Leave;
  end;
end;

procedure TLogger.Log(ALevel: TLogLevel; const AText: string);
var
  mLogEntry: TLogEntry;
  mSinkEntry: TSinkEntry;
begin
  mLogEntry := TLogEntry.Create(Now, ALevel, AText);
  // Die Sperre hält auch die Ausgabe zusammen, damit Zeilen mehrerer Threads
  // sich in Datei und stderr nicht mischen.
  FLock.Enter;
  try
    for mSinkEntry in FSinks do
    begin
      if ALevel >= mSinkEntry.MinLevel then
      begin
        WriteQuietly(mSinkEntry.Sink, mLogEntry);
      end;
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
