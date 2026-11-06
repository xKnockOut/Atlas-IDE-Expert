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
  /// <summary>Versuche je Abruf: GitHub beendet Verbindungen zeitweise (WinHTTP 12030), frisch hochgeladene Dateien
  /// liefern kurz 404.</summary>
  cAttempts = 3;
  cRetryWaitMs = 2000;

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

/// <summary>Lohnt ein weiterer Versuch nach Status AStatus (0 = Verbindungsfehler)?</summary>
function Retryable(AStatus: Integer): Boolean;
begin
  Result := (AStatus = 0) or (AStatus = 404) or (AStatus >= 500);
end;

/// <summary>ATry bis zu cAttempts mal; liefert Erfolg und Status des letzten Versuchs.</summary>
function WithRetries(const ATry: TFunc<Integer>): Boolean;
var
  mAttempt, mStatus: Integer;
begin
  for mAttempt := 1 to cAttempts do
  begin
    mStatus := ATry();
    Result := mStatus = 200;
    if Result or not Retryable(mStatus) then
    begin
      Exit;
    end;
    if mAttempt < cAttempts then
    begin
      TThread.Sleep(cRetryWaitMs);
    end;
  end;
end;

{ TUpdateWindowsNetwork }

function TUpdateWindowsNetwork.Fetch(const AUrl: string; out AText, AError: string): Boolean;
var
  mClient: THTTPClient;
  mText, mError: string;
begin
  AText := '';
  if not IsHttps(AUrl, AError) then
  begin
    Exit(False);
  end;
  mClient := NewClient;
  try
    Result := WithRetries(
      function: Integer
      var
        mResponse: IHTTPResponse;
      begin
        Result := 0;
        try
          mResponse := mClient.Get(AUrl);
          Result := mResponse.StatusCode;
          mError := 'HTTP ' + IntToStr(Result);
          if Result = 200 then
          begin
            mText := mResponse.ContentAsString(TEncoding.UTF8);
          end;
        except
          on mFailure: ENetException do
          begin
            mError := mFailure.ClassName + ': ' + mFailure.Message;
          end;
        end;
      end);
    AText := mText;
    if not Result then
    begin
      AError := mError;
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
  mError: string;
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
    Result := WithRetries(
      function: Integer
      begin
        Result := 0;
        // Ein abgebrochener Versuch hinterlässt Teile der Datei.
        mStream.Size := 0;
        try
          Result := mClient.Get(AUrl, mStream).StatusCode;
          mError := 'HTTP ' + IntToStr(Result);
        except
          on mFailure: ENetException do
          begin
            mError := mFailure.ClassName + ': ' + mFailure.Message;
          end;
        end;
      end);
    if not Result then
    begin
      AError := mError;
    end;
  finally
    mStream.Free;
    mClient.Free;
    mProgress.Free;
  end;
end;

end.
