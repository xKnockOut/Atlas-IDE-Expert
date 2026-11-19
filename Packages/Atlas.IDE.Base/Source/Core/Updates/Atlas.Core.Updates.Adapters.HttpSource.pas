unit Atlas.Core.Updates.Adapters.HttpSource;

// Versionsdatei über HTTPS lesen (#495), aus einem Hintergrund-Thread. Jede
// Abfrage läuft asynchron und wird abgebrochen, sobald das Abbruchsignal des
// Plugins kommt (TAtlasShutdown, Entladen in unter 1 s) oder die Zeit
// abgelaufen ist; Client und Antwort-Stream werden erst nach dem Ende der
// abgebrochenen Anfrage freigegeben (TAtlasAsyncWait.AwaitSettled). Die
// Antwort liest ein Stream mit Größengrenze (cMaxBytes). Weiterleitungen folgt
// Atlas selbst, höchstens fünf und nur auf https; gesendet wird außer der
// Adresse nichts (keine Cookies).

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
  System.Math,
  System.Net.HttpClient,
  System.Net.URLClient,
  Atlas.Core.Diagnostics.Deadline,
  Atlas.Core.Diagnostics.AsyncWait,
  Atlas.Core.Diagnostics.BoundedStream;

const
  // Die Versionsdatei ist ein paar Byte groß; mehr nimmt der Antwort-Stream nicht an.
  cMaxBytes = 64 * 1024;
  cMaxRedirects = 5;
  cHttpOk = 200;
  /// <summary>Statuscodes der Weiterleitungen: 301, 302, 303, 307, 308.</summary>
  cRedirectCodes: array[0..4] of Integer = (301, 302, 303, 307, 308);
  // Gründe fürs Protokoll (nie übersetzt).
  cHttpsOnly = 'nur https';
  cTooManyRedirects = 'zu viele Weiterleitungen';
  cHttpStatus = 'HTTP %d';
  cTooLarge = 'Antwort zu groß';

function IsRedirect(AStatus: Integer): Boolean;
var
  mCode: Integer;
begin
  for mCode in cRedirectCodes do
  begin
    if AStatus = mCode then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Holt AUrl in AContent; False, wenn das Abbruchsignal kommt oder ADeadline erreicht ist.</summary>
function AwaitGet(AClient: THTTPClient; const AUrl: string; AContent: TAtlasBoundedStream;
  const ADeadline: TAtlasDeadline; out AResponse: IHTTPResponse): Boolean;
var
  mAsync: IAsyncResult;
begin
  AResponse := nil;
  AContent.Clear;
  mAsync := AClient.BeginGet(AUrl, AContent);
  // Bei einem Abbruch erst nach dem Ende der Anfrage zurück: Bis dahin schreibt der Task der RTL in AContent.
  Result := TAtlasAsyncWait.AwaitSettled(
    function: Boolean
    begin
      Result := mAsync.IsCompleted;
    end,
    procedure
    begin
      mAsync.Cancel;
    end, ADeadline, nil) = TAtlasAsyncEnd.Done;
  if Result then
  begin
    AResponse := THTTPClient.EndAsyncHTTP(mAsync);
  end;
end;

/// <summary>Holt AUrl und folgt Weiterleitungen (höchstens MaxRedirects, nur auf https); AError sonst.</summary>
function FollowRedirects(AClient: THTTPClient; const AUrl: string; AContent: TAtlasBoundedStream;
  ATimeoutMs: Integer; out AResponse: IHTTPResponse; out AError: string): Boolean;
var
  mDeadline: TAtlasDeadline;
  mUrl: string;
  mRedirects: Integer;
begin
  AError := '';
  mUrl := AUrl;
  mRedirects := 0;
  mDeadline := TAtlasDeadline.After(Cardinal(Max(ATimeoutMs, 0)));
  repeat
    if not mUrl.StartsWith('https://', True) then
    begin
      AError := cHttpsOnly;
    end
    else if not AwaitGet(AClient, mUrl, AContent, mDeadline, AResponse) then
    begin
      AError := 'abgebrochen';
    end
    else if IsRedirect(AResponse.StatusCode) then
    begin
      Inc(mRedirects);
      mUrl := AResponse.HeaderValue['Location'];
      if mRedirects > cMaxRedirects then
      begin
        AError := cTooManyRedirects;
      end;
    end;
  until (AError <> '') or not IsRedirect(AResponse.StatusCode);
  Result := AError = '';
end;

{ TAtlasHttpVersionSource }

function TAtlasHttpVersionSource.Fetch(const AUrl: string; ATimeoutMs: Integer; out AText,
  AError: string): Boolean;
var
  mClient: THTTPClient;
  mContent: TAtlasBoundedStream;
  mResponse: IHTTPResponse;
begin
  Result := False;
  AText := '';
  AError := '';
  mClient := THTTPClient.Create;
  mContent := TAtlasBoundedStream.Create(cMaxBytes);
  try
    // Kurz: Ein Abbruch während des Verbindungsaufbaus wirkt erst, wenn dieser endet.
    mClient.ConnectionTimeout := TAtlasAsyncWait.ConnectTimeout(ATimeoutMs);
    mClient.ResponseTimeout := ATimeoutMs;
    mClient.HandleRedirects := False;
    mClient.AllowCookies := False;
    mClient.UserAgent := 'Atlas';
    try
      if not FollowRedirects(mClient, AUrl, mContent, ATimeoutMs, mResponse, AError) then
      begin
        Exit;
      end;
      if mResponse.StatusCode <> cHttpOk then
      begin
        AError := Format(cHttpStatus, [mResponse.StatusCode]);
      end
      else
      begin
        AText := TEncoding.UTF8.GetString(mContent.Bytes, 0, mContent.Size);
        Result := True;
      end;
    except
      on E: Exception do
      begin
        AError := E.ClassName;
        if mContent.Exceeded then
        begin
          AError := cTooLarge;
        end;
      end;
    end;
  finally
    // Erst die Schnittstelle lösen, sie verweist auf den Client.
    mResponse := nil;
    mContent.Free;
    mClient.Free;
  end;
end;

end.
