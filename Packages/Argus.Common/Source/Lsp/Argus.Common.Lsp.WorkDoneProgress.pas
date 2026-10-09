unit Argus.Common.Lsp.WorkDoneProgress;

// Fortschrittsanzeige über window/workDoneProgress/create und $/progress.
// Die Antwort des Clients auf create wird nicht ausgewertet; Clients ohne
// Unterstützung ignorieren die Nachrichten. Zwischenstände werden auf
// höchstens fünf je Sekunde gedrosselt. Threadsicher, solange der
// Transport es ist.

interface

uses
  System.SysUtils,
  System.Diagnostics,
  Argus.Common.JsonRpc.Contract,
  Argus.Common.Index.Contract;

type
  TLspWorkDoneProgress = class
  private
    FTransport: IJsonRpcTransport;
    FToken: string;
    FLock: TObject;
    FLastReport: TStopwatch;
    FActive: Boolean;
    procedure SendProgress(const AKind, ATitleOrMessage: string; APercent: Integer);
  public
    const MinReportIntervalMs = 200;
    constructor Create(const ATransport: IJsonRpcTransport; const AToken: string);
    destructor Destroy; override;
    procedure Start(const ATitle: string);
    /// <summary>APercent < 0: ohne Prozentangabe.</summary>
    procedure Report(const AMessage: string; APercent: Integer);
    procedure Finish(const AMessage: string);
    /// <summary>Adapter für den Symbolindex.</summary>
    function AsIndexProgress: TIndexProgressEvent;
    property Active: Boolean read FActive;
  end;

implementation

uses
  System.JSON,
  Argus.Common.JsonRpc.Messages;

{ TLspWorkDoneProgress }

constructor TLspWorkDoneProgress.Create(const ATransport: IJsonRpcTransport; const AToken: string);
begin
  inherited Create;
  FTransport := ATransport;
  FToken := AToken;
  FLock := TObject.Create;
end;

destructor TLspWorkDoneProgress.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TLspWorkDoneProgress.SendProgress(const AKind, ATitleOrMessage: string; APercent: Integer);
var
  Value, Params: TJSONObject;
  Notification: TJSONObject;
begin
  Value := TJSONObject.Create;
  Value.AddPair('kind', AKind);
  if AKind = 'begin' then
  begin
    Value.AddPair('title', ATitleOrMessage);
    Value.AddPair('cancellable', TJSONBool.Create(False));
  end
  else if ATitleOrMessage <> '' then
    Value.AddPair('message', ATitleOrMessage);
  if (AKind <> 'end') and (APercent >= 0) then
    Value.AddPair('percentage', TJSONNumber.Create(APercent));
  Params := TJSONObject.Create;
  Params.AddPair('token', FToken);
  Params.AddPair('value', Value);
  Notification := TJsonRpcMessages.Notification('$/progress', Params);
  try
    FTransport.WriteMessage(Notification);
  finally
    Notification.Free;
  end;
end;

procedure TLspWorkDoneProgress.Start(const ATitle: string);
var
  Request, Params: TJSONObject;
begin
  TMonitor.Enter(FLock);
  try
    Params := TJSONObject.Create;
    Params.AddPair('token', FToken);
    Request := TJSONObject.Create;
    try
      Request.AddPair('jsonrpc', '2.0');
      Request.AddPair('id', 'argus/' + FToken);
      Request.AddPair('method', 'window/workDoneProgress/create');
      Request.AddPair('params', Params);
      FTransport.WriteMessage(Request);
    finally
      Request.Free;
    end;
    SendProgress('begin', ATitle, 0);
    FActive := True;
    FLastReport := TStopwatch.StartNew;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspWorkDoneProgress.Report(const AMessage: string; APercent: Integer);
begin
  TMonitor.Enter(FLock);
  try
    if not FActive or (FLastReport.ElapsedMilliseconds < MinReportIntervalMs) then
      Exit;
    SendProgress('report', AMessage, APercent);
    FLastReport := TStopwatch.StartNew;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspWorkDoneProgress.Finish(const AMessage: string);
begin
  TMonitor.Enter(FLock);
  try
    if not FActive then
      Exit;
    SendProgress('end', AMessage, -1);
    FActive := False;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLspWorkDoneProgress.AsIndexProgress: TIndexProgressEvent;
begin
  Result :=
    procedure(AKind: TIndexProgressKind; const AMessage: string; APercent: Integer)
    var
      Name: string;
    begin
      case AKind of
        TIndexProgressKind.Started:
          Start(AMessage);
        TIndexProgressKind.Report:
          begin
            // Nur den Dateinamen zeigen.
            Name := AMessage;
            if LastDelimiter('\/', Name) > 0 then
              Name := Copy(Name, LastDelimiter('\/', Name) + 1, MaxInt);
            Report(Name, APercent);
          end;
        TIndexProgressKind.Finished:
          Finish(AMessage);
      end;
    end;
end;

end.
