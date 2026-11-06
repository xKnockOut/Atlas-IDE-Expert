unit Atlas.Common.Diagnostics.Providers.Log;

// IDiagnosticLog (#647): formatiert je Anfrage eine Zeile, lässt sie durch
// TDiagnosticFilter prüfen und gibt sie an den IDiagnosticWriter.
//
// Bis Configure aufgerufen wird (die Einstellungen kommen erst mit dem
// Arbeitsbereich), sammelt das Log die Zeilen im Speicher, höchstens
// PendingLimit. Configure(True) schreibt sie, Configure(False) verwirft sie;
// mit diagnostics.log = false wird so nichts geschrieben.
//
// Beispiel einer Zeile:
//   12:01:03.120 textDocument/completion 84 ms queue 3 ms ok:37 doc#4 v17 len 12840 crc 9A3F01C2
//   line 212 of 1180 col 14 ctx=memberAccess syntaxErr=2 index units 1569 lib 1239 loading 63 %
//   resolve unitNotFound

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Diagnostics.Contract,
  Atlas.Common.Diagnostics.Anonymizer;

type
  TDiagnosticLog = class(TInterfacedObject, IDiagnosticLog)
  public const
    cPendingLimit = 200;
  private
    FWriter: IDiagnosticWriter;
    FFilter: TDiagnosticFilter;
    FLock: TObject;
    FConfigured: Boolean;
    FEnabled: Boolean;
    FPending: TList<string>;
    procedure Emit(const ALine: string);
  public
    /// <summary>Übernimmt AFilter.</summary>
    constructor Create(const AWriter: IDiagnosticWriter; AFilter: TDiagnosticFilter);
    destructor Destroy; override;
    procedure LogRequest(const ARequest: TDiagnosticRequest);
    procedure LogStart(const AVersion: string; const AProcess: TDiagnosticProcess);
    procedure LogEnd(AReason: TDiagnosticEndReason; AExitCode: Integer; const AProcess: TDiagnosticProcess;
      const AException, AStack: string); overload;
    procedure LogEnd(AReason: TDiagnosticEndReason; AExitCode: Integer; const AProcess: TDiagnosticProcess;
      const AException: string); overload;
    procedure LogEnd(AReason: TDiagnosticEndReason; AExitCode: Integer;
      const AProcess: TDiagnosticProcess); overload;
    procedure LogEvent(const AText: string);
    procedure Configure(AEnabled: Boolean);
    function Enabled: Boolean;
    function Dropped: Integer;
    /// <summary>Schreibt gesammelte Zeilen auch ohne Configure (Serverende ohne Arbeitsbereich).</summary>
    procedure Flush;
    /// <summary>Zeile zu ARequest, ohne Filter (für Tests und Messungen).</summary>
    class function FormatRequest(const ARequest: TDiagnosticRequest): string; static;
    property Filter: TDiagnosticFilter read FFilter;
  end;

implementation

function TimeText(ATime: TDateTime): string;
begin
  Result := FormatDateTime('hh":"nn":"ss"."zzz', ATime);
end;

function MegaBytes(ABytes: Int64): string;
begin
  Result := IntToStr(ABytes div (1024 * 1024)) + ' MB';
end;

{ TDiagnosticLog }

constructor TDiagnosticLog.Create(const AWriter: IDiagnosticWriter; AFilter: TDiagnosticFilter);
begin
  inherited Create;
  FWriter := AWriter;
  FFilter := AFilter;
  FLock := TObject.Create;
  FPending := TList<string>.Create;
  FEnabled := True;
end;

destructor TDiagnosticLog.Destroy;
begin
  FPending.Free;
  FLock.Free;
  FFilter.Free;
  inherited;
end;

/// <summary>Ergebnis der Anfrage: Anzahl bei ok, Grund bei leer und Fehler.</summary>
procedure AppendOutcome(ABuilder: TStringBuilder; const ARequest: TDiagnosticRequest);
begin
  ABuilder.Append(' ').Append(cDiagnosticOutcomeCodes[ARequest.Outcome]);
  case ARequest.Outcome of
    TDiagnosticOutcome.Ok:
      ABuilder.Append(':').Append(ARequest.Count);
    TDiagnosticOutcome.Empty, TDiagnosticOutcome.Error:
      if ARequest.Reason = '' then
      begin
        ABuilder.Append(':unspecified');
      end
      else
      begin
        ABuilder.Append(':').Append(ARequest.Reason);
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>Dokument und Stelle der Anfrage.</summary>
procedure AppendLocation(ABuilder: TStringBuilder; const ARequest: TDiagnosticRequest);
begin
  if ARequest.Document <> '' then
  begin
    ABuilder.Append(' ').Append(ARequest.Document).Append(' v').Append(ARequest.Version).Append(' len ')
      .Append(ARequest.Length_).Append(' crc ').Append(ARequest.Checksum);
  end;
  if ARequest.Line >= 0 then
  begin
    ABuilder.Append(' line ').Append(ARequest.Line);
    if ARequest.LineCount > 0 then
    begin
      ABuilder.Append(' of ').Append(ARequest.LineCount);
    end;
    ABuilder.Append(' col ').Append(ARequest.Column);
  end;
end;

/// <summary>Stand des Index und Auflösung.</summary>
procedure AppendIndex(ABuilder: TStringBuilder; const ARequest: TDiagnosticRequest);
begin
  if ARequest.IndexUnits > 0 then
  begin
    ABuilder.Append(' index units ').Append(ARequest.IndexUnits).Append(' lib ').Append(ARequest.IndexLibrary);
    if ARequest.IndexLoading >= 0 then
    begin
      ABuilder.Append(' loading ').Append(ARequest.IndexLoading).Append(' %');
    end;
  end;
  if ARequest.Resolve <> '' then
  begin
    ABuilder.Append(' resolve ').Append(ARequest.Resolve);
  end;
end;

class function TDiagnosticLog.FormatRequest(const ARequest: TDiagnosticRequest): string;
var
  mBuilder: TStringBuilder;
  mNote: string;
begin
  mBuilder := TStringBuilder.Create(256);
  try
    mBuilder.Append(TimeText(ARequest.Time)).Append(' ').Append(ARequest.Method);
    mBuilder.Append(' ').Append(ARequest.ElapsedMs).Append(' ms');
    if ARequest.QueueMs > 0 then
    begin
      mBuilder.Append(' queue ').Append(ARequest.QueueMs).Append(' ms');
    end;
    AppendOutcome(mBuilder, ARequest);
    AppendLocation(mBuilder, ARequest);
    for mNote in ARequest.Notes do
    begin
      mBuilder.Append(' ').Append(mNote);
    end;
    AppendIndex(mBuilder, ARequest);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

procedure TDiagnosticLog.Emit(const ALine: string);
begin
  if not FFilter.Accept(ALine) then
  begin
    Exit;
  end;
  TMonitor.Enter(FLock);
  try
    if not FConfigured then
    begin
      if FPending.Count < cPendingLimit then
      begin
        FPending.Add(ALine);
      end;
      Exit;
    end;
    if FEnabled then
    begin
      FWriter.WriteLine(ALine);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TDiagnosticLog.LogRequest(const ARequest: TDiagnosticRequest);
begin
  if FConfigured and not FEnabled then
  begin
    Exit;
  end;
  Emit(FormatRequest(ARequest));
end;

procedure TDiagnosticLog.LogStart(const AVersion: string; const AProcess: TDiagnosticProcess);
begin
  Emit(Format('%s run start version %s mem %s threads %d', [TimeText(Now), AVersion,
    MegaBytes(AProcess.MemoryBytes), AProcess.Threads]));
end;

procedure TDiagnosticLog.LogEnd(AReason: TDiagnosticEndReason; AExitCode: Integer; const AProcess: TDiagnosticProcess;
  const AException: string);
begin
  LogEnd(AReason, AExitCode, AProcess, AException, '');
end;

procedure TDiagnosticLog.LogEnd(AReason: TDiagnosticEndReason; AExitCode: Integer;
  const AProcess: TDiagnosticProcess);
begin
  LogEnd(AReason, AExitCode, AProcess, '', '');
end;

procedure TDiagnosticLog.LogEnd(AReason: TDiagnosticEndReason; AExitCode: Integer; const AProcess: TDiagnosticProcess;
  const AException, AStack: string);
var
  mLine: string;
  mFrame: string;
begin
  mLine := Format('%s run end reason %s exit %d mem %s threads %d dropped %d', [TimeText(Now),
    cDiagnosticEndReasonCodes[AReason], AExitCode, MegaBytes(AProcess.MemoryBytes), AProcess.Threads, Dropped]);
  if AException <> '' then
  begin
    mLine := mLine + ' exception ' + AException;
  end;
  Emit(mLine);
  // Jeder Rahmen eine eigene Zeile: Verwirft der Filter einen, bleiben die übrigen.
  for mFrame in AStack.Split([#13#10, #10], TStringSplitOptions.ExcludeEmpty) do
  begin
    Emit('  at ' + TDiagnosticFilter.StackFrame(mFrame));
  end;
end;

procedure TDiagnosticLog.LogEvent(const AText: string);
begin
  Emit(TimeText(Now) + ' ' + AText);
end;

procedure TDiagnosticLog.Configure(AEnabled: Boolean);
var
  mLine: string;
begin
  TMonitor.Enter(FLock);
  try
    FEnabled := AEnabled;
    if not FConfigured then
    begin
      FConfigured := True;
      if FEnabled then
      begin
        for mLine in FPending do
        begin
          FWriter.WriteLine(mLine);
        end;
      end;
      FPending.Clear;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TDiagnosticLog.Flush;
begin
  TMonitor.Enter(FLock);
  try
    if not FConfigured then
    begin
      Configure(FEnabled);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TDiagnosticLog.Enabled: Boolean;
begin
  Result := FEnabled;
end;

function TDiagnosticLog.Dropped: Integer;
begin
  Result := FFilter.Dropped;
end;

end.
