unit Atlas.Core.Diagnostics.Hangs;

// Einfrier-Wächter (#501), Teil ohne Windows und Open Tools API:
// - TAtlasActivity: Atlas-Arbeit im Hauptthread meldet sich mit Scope an; der
//   Wächter liest den Namen aus seinem Thread (threadsicher, ohne zu warten).
//   Während des Starts zählt TimeInto die Dauer jeder äußersten Aktion zu den
//   Startanteilen (Bericht N4).
// - TAtlasHangMonitor: Schwelle, Statistik je Sitzung und Bericht.
// - TAtlasStackScan: ordnet Adressen eines rohen Stapelabzugs Modulen zu
//   (Modul+Offset), ohne Symbole; der Bericht zeigt so, ob Atlas beteiligt ist.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  Atlas.Core.Diagnostics.StartTimes;

type
  TAtlasActivity = class
  private class var
    FLock: TCriticalSection;
    FNames: TArray<string>;
    FTimes: TAtlasStartTimes;
  private
    /// <summary>ATimed: äußerste Aktion, begonnen bei AStarted (Uhr der Startanteile).</summary>
    class procedure Leave(const AName: string; ATimed: Boolean; AStarted: Int64); static;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>Meldet AName an, bis das Ergebnis freigegeben wird (Ende der Routine).</summary>
    class function Scope(const AName: string): IInterface; static;
    /// <summary>Ab jetzt die Dauer jeder äußersten Aktion als „Aktion Name“ zu ATimes addieren (Startanteile,
    /// Bericht N4); nil beendet das. ATimes gehört dem Aufrufer und darf nach TimeInto(nil) freigegeben werden.
    /// </summary>
    class procedure TimeInto(ATimes: TAtlasStartTimes); static;
    /// <summary>Innerste laufende Aktion; '' ohne oder wenn gerade gesperrt.</summary>
    class function Current: string; static;
  end;

  TAtlasModuleRange = record
    Name: string;
    Base: UInt64;
    Size: UInt64;
  end;

  TAtlasStackScan = class
  public
    /// <summary>Adressen, die in einem Modul liegen, als "Modul+Offset" (hex); höchstens AMax,
    /// gleiche Einträge direkt hintereinander nur einmal.</summary>
    class function Frames(const AAddresses: TArray<UInt64>; const AModules: TArray<TAtlasModuleRange>;
      AMax: Integer = 24): TArray<string>; static;
  end;

  TAtlasHang = record
    DurationMs: Int64;
    At: TDateTime;
    Activity: string;
    Window: string;
    Frames: TArray<string>;
    /// <summary>Code-Insight-Kompilierungen bisher (#527).</summary>
    CodeInsightCount: Integer;
    CodeInsightMs: Int64;
  end;

  TAtlasHangMonitor = class
  private
    FThresholdMs: Integer;
    FCount: Integer;
    FWithAtlas: Integer;
    FLongestMs: Int64;
  public
    constructor Create(AThresholdMs: Integer = 500);
    /// <summary>Wertet einen beendeten Hänger aus: '' unter der Schwelle, sonst der Bericht; zählt mit.</summary>
    function Finish(const AHang: TAtlasHang): string;
    /// <summary>Statistik der Sitzung in einer Zeile.</summary>
    function Summary: string;
    /// <summary>Atlas beteiligt: laufende Aktion oder ein Rahmen aus einem Atlas-Modul.</summary>
    class function InvolvesAtlas(const AHang: TAtlasHang): Boolean; static;
    property ThresholdMs: Integer read FThresholdMs write FThresholdMs;
    property Count: Integer read FCount;
    property WithAtlas: Integer read FWithAtlas;
    property LongestMs: Int64 read FLongestMs;
  end;

implementation

type
  TActivityScope = class(TInterfacedObject)
  private
    FName: string;
    FTimed: Boolean;
    FStarted: Int64;
  public
    constructor Create(const AName: string; ATimed: Boolean; AStarted: Int64);
    destructor Destroy; override;
  end;

constructor TActivityScope.Create(const AName: string; ATimed: Boolean; AStarted: Int64);
begin
  inherited Create;
  FName := AName;
  FTimed := ATimed;
  FStarted := AStarted;
end;

destructor TActivityScope.Destroy;
begin
  TAtlasActivity.Leave(FName, FTimed, FStarted);
  inherited;
end;

{ TAtlasActivity }

class constructor TAtlasActivity.Create;
begin
  FLock := TCriticalSection.Create;
end;

class destructor TAtlasActivity.Destroy;
begin
  FLock.Free;
end;

class function TAtlasActivity.Scope(const AName: string): IInterface;
var
  Timed: Boolean;
  Started: Int64;
begin
  Started := 0;
  FLock.Enter;
  try
    // Nur die äußerste Aktion zählt: Verschachtelte stecken in ihrer Dauer.
    Timed := (Length(FNames) = 0) and (FTimes <> nil);
    if Timed then
      Started := FTimes.Clock;
    FNames := FNames + [AName];
  finally
    FLock.Leave;
  end;
  Result := TActivityScope.Create(AName, Timed, Started);
end;

class procedure TAtlasActivity.Leave(const AName: string; ATimed: Boolean; AStarted: Int64);
begin
  FLock.Enter;
  try
    if Length(FNames) > 0 then
      SetLength(FNames, Length(FNames) - 1);
    // Unter der Sperre: Nach TimeInto(nil) schreibt keine Aktion mehr in die freigegebenen Startanteile.
    if ATimed and (FTimes <> nil) then
      FTimes.Add('Aktion ' + AName, FTimes.Clock - AStarted);
  finally
    FLock.Leave;
  end;
end;

class procedure TAtlasActivity.TimeInto(ATimes: TAtlasStartTimes);
begin
  FLock.Enter;
  try
    FTimes := ATimes;
  finally
    FLock.Leave;
  end;
end;

class function TAtlasActivity.Current: string;
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

{ TAtlasStackScan }

class function TAtlasStackScan.Frames(const AAddresses: TArray<UInt64>; const AModules: TArray<TAtlasModuleRange>;
  AMax: Integer): TArray<string>;
var
  Address: UInt64;
  Module: TAtlasModuleRange;
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

{ TAtlasHangMonitor }

constructor TAtlasHangMonitor.Create(AThresholdMs: Integer);
begin
  inherited Create;
  FThresholdMs := AThresholdMs;
end;

class function TAtlasHangMonitor.InvolvesAtlas(const AHang: TAtlasHang): Boolean;
var
  Frame: string;
begin
  Result := AHang.Activity <> '';
  for Frame in AHang.Frames do
    if Frame.StartsWith('Atlas', True) then
      Result := True;
end;

function TAtlasHangMonitor.Finish(const AHang: TAtlasHang): string;
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
  if InvolvesAtlas(AHang) then
    Inc(FWithAtlas);
  Lines := TStringBuilder.Create;
  try
    Lines.AppendFormat('Hänger %d ms um %s', [AHang.DurationMs, FormatDateTime('hh":"nn":"ss', AHang.At)]);
    if AHang.Activity <> '' then
      Lines.AppendFormat('; Atlas: %s, %d ms', [AHang.Activity, AHang.DurationMs])
    else if InvolvesAtlas(AHang) then
      Lines.Append('; Atlas im Aufrufstapel');
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

function TAtlasHangMonitor.Summary: string;
begin
  Result := Format('Sitzung: %d Hänger, längster %d ms, %d mit Atlas', [FCount, FLongestMs, FWithAtlas]);
end;

end.