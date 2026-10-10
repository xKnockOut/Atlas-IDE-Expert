unit Argus.Core.Diagnostics.Hangs;

// Einfrier-Wächter (#501), Teil ohne Windows und Open Tools API:
// - TArgusActivity: Argus-Arbeit im Hauptthread meldet sich mit Scope an; der
//   Wächter liest den Namen aus seinem Thread (threadsicher, ohne zu warten).
// - TArgusHangMonitor: Schwelle, Statistik je Sitzung und Bericht.
// - TArgusStackScan: ordnet Adressen eines rohen Stapelabzugs Modulen zu
//   (Modul+Offset), ohne Symbole; der Bericht zeigt so, ob Argus beteiligt ist.

interface

uses
  System.SysUtils,
  System.SyncObjs;

type
  TArgusActivity = class
  private class var
    FLock: TCriticalSection;
    FNames: TArray<string>;
  private
    class procedure Leave; static;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>Meldet AName an, bis das Ergebnis freigegeben wird (Ende der Routine).</summary>
    class function Scope(const AName: string): IInterface; static;
    /// <summary>Innerste laufende Aktion; '' ohne oder wenn gerade gesperrt.</summary>
    class function Current: string; static;
  end;

  TArgusModuleRange = record
    Name: string;
    Base: UInt64;
    Size: UInt64;
  end;

  TArgusStackScan = class
  public
    /// <summary>Adressen, die in einem Modul liegen, als "Modul+Offset" (hex); höchstens AMax,
    /// gleiche Einträge direkt hintereinander nur einmal.</summary>
    class function Frames(const AAddresses: TArray<UInt64>; const AModules: TArray<TArgusModuleRange>;
      AMax: Integer = 24): TArray<string>; static;
  end;

  TArgusHang = record
    DurationMs: Int64;
    At: TDateTime;
    Activity: string;
    Window: string;
    Frames: TArray<string>;
    /// <summary>Code-Insight-Kompilierungen bisher (#527).</summary>
    CodeInsightCount: Integer;
    CodeInsightMs: Int64;
  end;

  TArgusHangMonitor = class
  private
    FThresholdMs: Integer;
    FCount: Integer;
    FWithArgus: Integer;
    FLongestMs: Int64;
  public
    constructor Create(AThresholdMs: Integer = 500);
    /// <summary>Wertet einen beendeten Hänger aus: '' unter der Schwelle, sonst der Bericht; zählt mit.</summary>
    function Finish(const AHang: TArgusHang): string;
    /// <summary>Statistik der Sitzung in einer Zeile.</summary>
    function Summary: string;
    /// <summary>Argus beteiligt: laufende Aktion oder ein Rahmen aus einem Argus-Modul.</summary>
    class function InvolvesArgus(const AHang: TArgusHang): Boolean; static;
    property ThresholdMs: Integer read FThresholdMs write FThresholdMs;
    property Count: Integer read FCount;
    property WithArgus: Integer read FWithArgus;
    property LongestMs: Int64 read FLongestMs;
  end;

implementation

type
  TActivityScope = class(TInterfacedObject)
  public
    destructor Destroy; override;
  end;

destructor TActivityScope.Destroy;
begin
  TArgusActivity.Leave;
  inherited;
end;

{ TArgusActivity }

class constructor TArgusActivity.Create;
begin
  FLock := TCriticalSection.Create;
end;

class destructor TArgusActivity.Destroy;
begin
  FLock.Free;
end;

class function TArgusActivity.Scope(const AName: string): IInterface;
begin
  FLock.Enter;
  try
    FNames := FNames + [AName];
  finally
    FLock.Leave;
  end;
  Result := TActivityScope.Create;
end;

class procedure TArgusActivity.Leave;
begin
  FLock.Enter;
  try
    if Length(FNames) > 0 then
      SetLength(FNames, Length(FNames) - 1);
  finally
    FLock.Leave;
  end;
end;

class function TArgusActivity.Current: string;
begin
  Result := '';
  if not FLock.TryEnter then
    Exit;
  try
    if Length(FNames) > 0 then
      Result := FNames[High(FNames)];
  finally
    FLock.Leave;
  end;
end;

{ TArgusStackScan }

class function TArgusStackScan.Frames(const AAddresses: TArray<UInt64>; const AModules: TArray<TArgusModuleRange>;
  AMax: Integer): TArray<string>;
var
  Address: UInt64;
  Module: TArgusModuleRange;
  Frame: string;
begin
  Result := nil;
  for Address in AAddresses do
  begin
    if Length(Result) >= AMax then
      Break;
    for Module in AModules do
      if (Address >= Module.Base) and (Address < Module.Base + Module.Size) then
      begin
        Frame := Format('%s+%x', [Module.Name, Address - Module.Base]);
        if (Length(Result) = 0) or (Result[High(Result)] <> Frame) then
          Result := Result + [Frame];
        Break;
      end;
  end;
end;

{ TArgusHangMonitor }

constructor TArgusHangMonitor.Create(AThresholdMs: Integer);
begin
  inherited Create;
  FThresholdMs := AThresholdMs;
end;

class function TArgusHangMonitor.InvolvesArgus(const AHang: TArgusHang): Boolean;
var
  Frame: string;
begin
  Result := AHang.Activity <> '';
  for Frame in AHang.Frames do
    if Frame.StartsWith('Argus', True) then
      Result := True;
end;

function TArgusHangMonitor.Finish(const AHang: TArgusHang): string;
var
  Lines: TStringBuilder;
  Frame: string;
begin
  Result := '';
  if AHang.DurationMs < FThresholdMs then
    Exit;
  Inc(FCount);
  if AHang.DurationMs > FLongestMs then
    FLongestMs := AHang.DurationMs;
  if InvolvesArgus(AHang) then
    Inc(FWithArgus);
  Lines := TStringBuilder.Create;
  try
    Lines.AppendFormat('Hänger %d ms um %s', [AHang.DurationMs, FormatDateTime('hh:nn:ss', AHang.At)]);
    if AHang.Activity <> '' then
      Lines.AppendFormat('; Argus: %s, %d ms', [AHang.Activity, AHang.DurationMs])
    else if InvolvesArgus(AHang) then
      Lines.Append('; Argus im Aufrufstapel');
    if AHang.Window <> '' then
      Lines.AppendFormat('; Fenster: %s', [AHang.Window]);
    if AHang.CodeInsightCount > 0 then
      Lines.AppendFormat('; Code Insight bisher %d-mal, %d ms', [AHang.CodeInsightCount, AHang.CodeInsightMs]);
    for Frame in AHang.Frames do
      Lines.Append(sLineBreak).Append('    ').Append(Frame);
    Lines.Append(sLineBreak).Append('    ').Append(Summary);
    Result := Lines.ToString;
  finally
    Lines.Free;
  end;
end;

function TArgusHangMonitor.Summary: string;
begin
  Result := Format('Sitzung: %d Hänger, längster %d ms, %d mit Argus', [FCount, FLongestMs, FWithArgus]);
end;

end.