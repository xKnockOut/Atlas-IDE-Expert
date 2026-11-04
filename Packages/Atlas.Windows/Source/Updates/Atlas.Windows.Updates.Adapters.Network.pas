unit Atlas.Windows.Updates.Adapters.Network;

// Platform-Feature "Updates" (#1519), Adapter: Laden über THTTPClient mit
// dem Proxy des Systems. Nur https; Weiterleitungen (GitHub leitet Downloads
// auf seinen Dateispeicher um) folgt der Client. Fehlertexte nennen den
// HTTP-Status oder die Art des Fehlers, nie die Adresse.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Updates.Contract;

type
  TUpdateWindowsNetwork = class(TInterfacedObject, IUpdateNetwork)
  public
    function Fetch(const AUrl: string; out AText, AError: string): Boolean;
    function Download(const AUrl, AFileName: string; const AProgress: TUpdateProgress; out AError: string): Boolean;
  end;

implementation

uses
  System.Net.HttpClient,
  System.Net.URLClient;

type
  /// <summary>Leitet den Fortschritt des Clients (Methodenzeiger) an die Methodenreferenz weiter.</summary>
  TUpdateDownloadProgress = class
  private
    FProgress: TUpdateProgress;
    FLast: Integer;
  public
    constructor Create(const AProgress: TUpdateProgress);
    procedure Received(const ASender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean);
  end;

const
  cAgent = 'AtlasUpdate';
  cTimeoutMs = 30000;

constructor TUpdateDownloadProgress.Create(const AProgress: TUpdateProgress);
begin
  inherited Create;
  FProgress := AProgress;
  FLast := -1;
end;

procedure TUpdateDownloadProgress.Received(const ASender: TObject; AContentLength, AReadCount: Int64;
  var AAbort: Boolean);
var
  mPercent: Integer;
begin
  if AContentLength <= 0 then
  begin
    Exit;
  end;
  mPercent := Integer(AReadCount * 100 div AContentLength);
  if mPercent <> FLast then
  begin
    FLast := mPercent;
    FProgress(mPercent);
  end;
end;

function NewClient: THTTPClient;
begin
  Result := THTTPClient.Create;
  Result.UserAgent := cAgent;
  Result.ConnectionTimeout := cTimeoutMs;
  Result.ResponseTimeout := cTimeoutMs;
end;

function IsHttps(const AUrl: string; out AError: string): Boolean;
begin
  Result := AUrl.StartsWith('https://', True);
  AError := '';
  if not Result then
  begin
    AError := 'nur https';
  end;
end;

{ TUpdateWindowsNetwork }

function TUpdateWindowsNetwork.Fetch(const AUrl: string; out AText, AError: string): Boolean;
var
  mClient: THTTPClient;
  mResponse: IHTTPResponse;
begin
  AText := '';
  if not IsHttps(AUrl, AError) then
  begin
    Exit(False);
  end;
  mClient := NewClient;
  try
    try
      mResponse := mClient.Get(AUrl);
      Result := mResponse.StatusCode = 200;
      if Result then
      begin
        AText := mResponse.ContentAsString(TEncoding.UTF8);
      end
      else
      begin
        AError := 'HTTP ' + IntToStr(mResponse.StatusCode);
      end;
    except
      on mError: ENetException do
      begin
        AError := mError.ClassName;
        Result := False;
      end;
    end;
  finally
    mClient.Free;
  end;
end;

function TUpdateWindowsNetwork.Download(const AUrl, AFileName: string; const AProgress: TUpdateProgress;
  out AError: string): Boolean;
var
  mClient: THTTPClient;
  mStream: TFileStream;
  mProgress: TUpdateDownloadProgress;
  mStatus: Integer;
begin
  if not IsHttps(AUrl, AError) then
  begin
    Exit(False);
  end;
  ForceDirectories(ExtractFileDir(AFileName));
  mProgress := TUpdateDownloadProgress.Create(AProgress);
  mClient := NewClient;
  mStream := TFileStream.Create(AFileName, fmCreate);
  try
    mClient.OnReceiveData := mProgress.Received;
    try
      mStatus := mClient.Get(AUrl, mStream).StatusCode;
      Result := mStatus = 200;
      if not Result then
      begin
        AError := 'HTTP ' + IntToStr(mStatus);
      end;
    except
      on mError: ENetException do
      begin
        AError := mError.ClassName;
        Result := False;
      end;
    end;
  finally
    mStream.Free;
    mClient.Free;
    mProgress.Free;
  end;
end;

end.
