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
    PendingLimit = 200;
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
      const AException: string = ''; const AStack: string = '');
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

class function TDiagnosticLog.FormatRequest(const ARequest: TDiagnosticRequest): string;
var
  Builder: TStringBuilder;
  Note: string;
begin
  Builder := TStringBuilder.Create(256);
  try
    Builder.Append(TimeText(ARequest.Time)).Append(' ').Append(ARequest.Method);
    Builder.Append(' ').Append(ARequest.ElapsedMs).Append(' ms');
    if ARequest.QueueMs > 0 then
      Builder.Append(' queue ').Append(ARequest.QueueMs).Append(' ms');
    Builder.Append(' ').Append(DiagnosticOutcomeCodes[ARequest.Outcome]);
    case ARequest.Outcome of
      TDiagnosticOutcome.Ok:
        Builder.Append(':').Append(ARequest.Count);
      TDiagnosticOutcome.Empty, TDiagnosticOutcome.Error:
        if ARequest.Reason = '' then
          Builder.Append(':unspecified')
        else
          Builder.Append(':').Append(ARequest.Reason);
    end;
    if ARequest.Document <> '' then
      Builder.Append(' ').Append(ARequest.Document).Append(' v').Append(ARequest.Version).Append(' len ')
        .Append(ARequest.Length_).Append(' crc ').Append(ARequest.Checksum);
    if ARequest.Line >= 0 then
    begin
      Builder.Append(' line ').Append(ARequest.Line);
      if ARequest.LineCount > 0 then
        Builder.Append(' of ').Append(ARequest.LineCount);
      Builder.Append(' col ').Append(ARequest.Column);
    end;
    for Note in ARequest.Notes do
      Builder.Append(' ').Append(Note);
    if ARequest.IndexUnits > 0 then
    begin
      Builder.Append(' index units ').Append(ARequest.IndexUnits).Append(' lib ').Append(ARequest.IndexLibrary);
      if ARequest.IndexLoading >= 0 then
        Builder.Append(' loading ').Append(ARequest.IndexLoading).Append(' %');
    end;
    if ARequest.Resolve <> '' then
      Builder.Append(' resolve ').Append(ARequest.Resolve);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

procedure TDiagnosticLog.Emit(const ALine: string);
begin
  if not FFilter.Accept(ALine) then
    Exit;
  TMonitor.Enter(FLock);
  try
    if not FConfigured then
    begin
      if FPending.Count < PendingLimit then
        FPending.Add(ALine);
      Exit;
    end;
    if FEnabled then
      FWriter.WriteLine(ALine);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TDiagnosticLog.LogRequest(const ARequest: TDiagnosticRequest);
begin
  if FConfigured and not FEnabled then
    Exit;
  Emit(FormatRequest(ARequest));
end;

procedure TDiagnosticLog.LogStart(const AVersion: string; const AProcess: TDiagnosticProcess);
begin
  Emit(Format('%s run start version %s mem %s threads %d', [TimeText(Now), AVersion,
    MegaBytes(AProcess.MemoryBytes), AProcess.Threads]));
end;

procedure TDiagnosticLog.LogEnd(AReason: TDiagnosticEndReason; AExitCode: Integer; const AProcess: TDiagnosticProcess;
  const AException, AStack: string);
var
  Line: string;
  Frame: string;
begin
  Line := Format('%s run end reason %s exit %d mem %s threads %d dropped %d', [TimeText(Now),
    DiagnosticEndReasonCodes[AReason], AExitCode, MegaBytes(AProcess.MemoryBytes), AProcess.Threads, Dropped]);
  if AException <> '' then
    Line := Line + ' exception ' + AException;
  Emit(Line);
  // Jeder Rahmen eine eigene Zeile: Verwirft der Filter einen, bleiben die übrigen.
  for Frame in AStack.Split([#13#10, #10], TStringSplitOptions.ExcludeEmpty) do
    Emit('  at ' + TDiagnosticFilter.StackFrame(Frame));
end;

procedure TDiagnosticLog.LogEvent(const AText: string);
begin
  Emit(TimeText(Now) + ' ' + AText);
end;

procedure TDiagnosticLog.Configure(AEnabled: Boolean);
var
  Line: string;
begin
  TMonitor.Enter(FLock);
  try
    FEnabled := AEnabled;
    if not FConfigured then
    begin
      FConfigured := True;
      if FEnabled then
        for Line in FPending do
          FWriter.WriteLine(Line);
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
      Configure(FEnabled);
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
