unit Atlas.Core.Updates.Adapters.HttpSource;

// Versionsdatei über HTTPS lesen (#495), aus einem Hintergrund-Thread. Jede
// Abfrage läuft asynchron und wird abgebrochen, sobald das Abbruchsignal des
// Plugins kommt (TAtlasShutdown, Entladen in unter 1 s) oder die Zeit
// abgelaufen ist. Weiterleitungen folgt Atlas selbst, höchstens fünf und nur
// auf https; gesendet wird außer der Adresse nichts (keine Cookies).

interface

uses
  System.SysUtils,
  Atlas.Core.Updates.Contract;

type
  TAtlasHttpVersionSource = class(TInterfacedObject, IAtlasVersionSource)
  public
    function Fetch(const AUrl: string; ATimeoutMs: Integer; out AText, AError: string): Boolean;
  end;

implementation

uses
  System.Classes,
  System.Types,
  System.Diagnostics,
  System.Net.HttpClient,
  System.Net.URLClient,
  Atlas.Core.Diagnostics.Shutdown;

const
  // Die Versionsdatei ist ein paar Byte groß; mehr wird nicht gelesen.
  cMaxBytes = 64 * 1024;
  cMaxRedirects = 5;
  cSliceMs = 50;

function IsRedirect(AStatus: Integer): Boolean;
begin
  Result := (AStatus = 301) or (AStatus = 302) or (AStatus = 303) or (AStatus = 307) or (AStatus = 308);
end;

/// <summary>Holt AUrl in AContent; False, wenn das Abbruchsignal kommt oder die Zeit (ab AWatch) abläuft.
/// </summary>
function AwaitGet(AClient: THTTPClient; const AUrl: string; AContent: TBytesStream; const AWatch: TStopwatch;
  ATimeoutMs: Integer; out AResponse: IHTTPResponse): Boolean;
var
  mAsync: IAsyncResult;
  mWait: TStopwatch;
begin
  AResponse := nil;
  AContent.Clear;
  mAsync := AClient.BeginGet(AUrl, AContent);
  Result := True;
  while Result and not mAsync.IsCompleted do
  begin
    Result := not TAtlasShutdown.Wait(cSliceMs) and (AWatch.ElapsedMilliseconds <= ATimeoutMs);
  end;
  if Result then
  begin
    AResponse := THTTPClient.EndAsyncHTTP(mAsync);
  end
  else
  begin
    mAsync.Cancel;
    // Kurz auf das Ende warten, damit der Client danach freigegeben werden darf.
    mWait := TStopwatch.StartNew;
    while not mAsync.IsCompleted and (mWait.ElapsedMilliseconds < TAtlasShutdown.StopMs div 2) do
    begin
      Sleep(10);
    end;
  end;
end;

/// <summary>Holt AUrl und folgt Weiterleitungen (höchstens MaxRedirects, nur auf https); AError sonst.</summary>
function FollowRedirects(AClient: THTTPClient; const AUrl: string; AContent: TBytesStream; ATimeoutMs: Integer;
  out AResponse: IHTTPResponse; out AError: string): Boolean;
var
  mWatch: TStopwatch;
  mUrl: string;
  mRedirects: Integer;
begin
  AError := '';
  mUrl := AUrl;
  mRedirects := 0;
  mWatch := TStopwatch.StartNew;
  repeat
    if not mUrl.StartsWith('https://', True) then
    begin
      AError := 'nur https';
    end
    else if not AwaitGet(AClient, mUrl, AContent, mWatch, ATimeoutMs, AResponse) then
    begin
      AError := 'abgebrochen';
    end
    else if IsRedirect(AResponse.StatusCode) then
    begin
      Inc(mRedirects);
      mUrl := AResponse.HeaderValue['Location'];
      if mRedirects > cMaxRedirects then
      begin
        AError := 'zu viele Weiterleitungen';
      end;
    end;
  until (AError <> '') or not IsRedirect(AResponse.StatusCode);
  Result := AError = '';
end;

function TAtlasHttpVersionSource.Fetch(const AUrl: string; ATimeoutMs: Integer; out AText,
  AError: string): Boolean;
var
  mClient: THTTPClient;
  mContent: TBytesStream;
  mResponse: IHTTPResponse;
begin
  Result := False;
  AText := '';
  AError := '';
  mClient := THTTPClient.Create;
  mContent := TBytesStream.Create;
  try
    mClient.ConnectionTimeout := ATimeoutMs;
    mClient.ResponseTimeout := ATimeoutMs;
    mClient.HandleRedirects := False;
    mClient.AllowCookies := False;
    mClient.UserAgent := 'Atlas';
    try
      if not FollowRedirects(mClient, AUrl, mContent, ATimeoutMs, mResponse, AError) then
      begin
        Exit;
      end;
      if mResponse.StatusCode <> 200 then
      begin
        AError := Format('HTTP %d', [mResponse.StatusCode]);
      end
      else if mContent.Size > cMaxBytes then
      begin
        AError := 'Antwort zu groß';
      end
      else
      begin
        AText := TEncoding.UTF8.GetString(mContent.Bytes, 0, mContent.Size);
        Result := True;
      end;
    except
      on E: Exception do
        AError := E.ClassName;
    end;
  finally
    // Erst die Schnittstelle lösen, sie verweist auf den Client.
    mResponse := nil;
    mContent.Free;
    mClient.Free;
  end;
end;

end.
