unit Atlas.Common.Logging.Providers.RecentSink;

// Senke, die die letzten Logzeilen im Speicher hält (#108): Auszug für den
// Fehlerbericht, auch ohne --log. Fester Ringpuffer, die ältesten Zeilen
// werden verdrängt. Threadsicher.

interface

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract;

type
  IRecentLogLines = interface
    ['{2F8D6A41-7C3E-4B19-8E50-1A9C4D7B3E62}']
    /// <summary>Gemerkte Zeilen, älteste zuerst, je Eintrag wie TLogEntry.ToText.</summary>
    function Lines: TArray<string>;
  end;

  TRecentLogSink = class(TInterfacedObject, ILogSink, IRecentLogLines)
  public const
    DefaultCapacity = 200;
  private
    FLock: TObject;
    FLines: TArray<string>;
    FNext: Integer;
    FCount: Integer;
  public
    constructor Create; overload;
    constructor Create(ACapacity: Integer); overload;
    destructor Destroy; override;
    { ILogSink }
    procedure Write(const AEntry: TLogEntry);
    { IRecentLogLines }
    function Lines: TArray<string>;
  end;

implementation

{ TRecentLogSink }

constructor TRecentLogSink.Create;
begin
  Create(DefaultCapacity);
end;

constructor TRecentLogSink.Create(ACapacity: Integer);
begin
  inherited Create;
  FLock := TObject.Create;
  if ACapacity < 1 then
    ACapacity := 1;
  SetLength(FLines, ACapacity);
end;

destructor TRecentLogSink.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TRecentLogSink.Write(const AEntry: TLogEntry);
begin
  TMonitor.Enter(FLock);
  try
    FLines[FNext] := AEntry.ToText;
    FNext := (FNext + 1) mod Length(FLines);
    if FCount < Length(FLines) then
      Inc(FCount);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TRecentLogSink.Lines: TArray<string>;
var
  Index, First: Integer;
begin
  TMonitor.Enter(FLock);
  try
    SetLength(Result, FCount);
    First := (FNext - FCount + Length(FLines)) mod Length(FLines);
    for Index := 0 to FCount - 1 do
      Result[Index] := FLines[(First + Index) mod Length(FLines)];
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.
