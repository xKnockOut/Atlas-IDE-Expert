unit Atlas.Common.Lsp.WorkDoneProgress;

// Fortschrittsanzeige über window/workDoneProgress/create und $/progress.
// Die Antwort des Clients auf create wird nicht ausgewertet; Clients ohne
// Unterstützung ignorieren die Nachrichten. Zwischenstände werden auf
// höchstens fünf je Sekunde gedrosselt. Threadsicher, solange der
// Transport es ist.

interface

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Index.Contract;

type
  TLspWorkDoneProgress = class
  private
    FTransport: IJsonRpcTransport;
    FToken: string;
    FLock: TObject;
    FLastReport: TStopwatch;
    FActive: Boolean;
    FPercent: Integer;
    procedure SendProgress(const AKind, ATitleOrMessage: string; APercent: Integer);
  public
    const cMinReportIntervalMs = 200;
    constructor Create(const ATransport: IJsonRpcTransport; const AToken: string);
    destructor Destroy; override;
    procedure Start(const ATitle: string);
    /// <summary>APercent &lt; 0: ohne Prozentangabe.</summary>
    procedure Report(const AMessage: string; APercent: Integer);
    procedure Finish(const AMessage: string);
    /// <summary>Adapter für den Symbolindex.</summary>
    function AsIndexProgress: TIndexProgressEvent;
    property Active: Boolean read FActive;
    /// <summary>Zuletzt gemeldeter Fortschritt, auch wenn die Meldung gedrosselt wurde (#647); -1 ohne.</summary>
    property Percent: Integer read FPercent;
  end;

implementation

uses
  System.JSON,
  Atlas.Common.JsonRpc.Messages;

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
  mValue, mParams: TJSONObject;
  mNotification: TJSONObject;
begin
  mValue := TJSONObject.Create;
  mValue.AddPair('kind', AKind);
  if AKind = 'begin' then
  begin
    mValue.AddPair('title', ATitleOrMessage);
    mValue.AddPair('cancellable', TJSONBool.Create(False));
  end
  else if ATitleOrMessage <> '' then
  begin
    mValue.AddPair('message', ATitleOrMessage);
  end;
  if (AKind <> 'end') and (APercent >= 0) then
  begin
    mValue.AddPair('percentage', TJSONNumber.Create(APercent));
  end;
  mParams := TJSONObject.Create;
  mParams.AddPair('token', FToken);
  mParams.AddPair('value', mValue);
  mNotification := TJsonRpcMessages.Notification('$/progress', mParams);
  try
    FTransport.WriteMessage(mNotification);
  finally
    mNotification.Free;
  end;
end;

procedure TLspWorkDoneProgress.Start(const ATitle: string);
var
  mRequest, mParams: TJSONObject;
begin
  TMonitor.Enter(FLock);
  try
    mParams := TJSONObject.Create;
    mParams.AddPair('token', FToken);
    mRequest := TJSONObject.Create;
    try
      mRequest.AddPair('jsonrpc', '2.0');
      mRequest.AddPair('id', 'atlas/' + FToken);
      mRequest.AddPair('method', 'window/workDoneProgress/create');
      mRequest.AddPair('params', mParams);
      FTransport.WriteMessage(mRequest);
    finally
      mRequest.Free;
    end;
    SendProgress('begin', ATitle, 0);
    FActive := True;
    FPercent := 0;
    FLastReport := TStopwatch.StartNew;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspWorkDoneProgress.Report(const AMessage: string; APercent: Integer);
begin
  TMonitor.Enter(FLock);
  try
    if FActive and (APercent >= 0) then
    begin
      FPercent := APercent;
    end;
    if not FActive or (FLastReport.ElapsedMilliseconds < cMinReportIntervalMs) then
    begin
      Exit;
    end;
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
    begin
      Exit;
    end;
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
            begin
              Name := Copy(Name, LastDelimiter('\/', Name) + 1, MaxInt);
            end;
            Report(Name, APercent);
          end;
        TIndexProgressKind.Finished:
          Finish(AMessage);
      end;
    end;
end;

end.
