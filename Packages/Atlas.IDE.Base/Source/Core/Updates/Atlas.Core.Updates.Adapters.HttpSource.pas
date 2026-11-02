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
  MaxBytes = 64 * 1024;
  MaxRedirects = 5;
  SliceMs = 50;

function IsRedirect(AStatus: Integer): Boolean;
begin
  Result := (AStatus = 301) or (AStatus = 302) or (AStatus = 303) or (AStatus = 307) or (AStatus = 308);
end;

function TAtlasHttpVersionSource.Fetch(const AUrl: string; ATimeoutMs: Integer; out AText,
  AError: string): Boolean;
var
  Client: THTTPClient;
  Content: TBytesStream;
  Async: IAsyncResult;
  Response: IHTTPResponse;
  Watch: TStopwatch;
  Url: string;
  Redirects: Integer;
begin
  Result := False;
  AText := '';
  AError := '';
  Client := THTTPClient.Create;
  Content := TBytesStream.Create;
  try
    Client.ConnectionTimeout := ATimeoutMs;
    Client.ResponseTimeout := ATimeoutMs;
    Client.HandleRedirects := False;
    Client.AllowCookies := False;
    Client.UserAgent := 'Atlas';
    Url := AUrl;
    Redirects := 0;
    Watch := TStopwatch.StartNew;
    try
      while True do
      begin
        if not Url.StartsWith('https://', True) then
        begin
          AError := 'nur https';
          Exit;
        end;
        Content.Clear;
        Async := Client.BeginGet(Url, Content);
        while not Async.IsCompleted do
          if TAtlasShutdown.Wait(SliceMs) or (Watch.ElapsedMilliseconds > ATimeoutMs) then
          begin
            Async.Cancel;
            // Kurz auf das Ende warten, damit der Client danach freigegeben werden darf.
            Watch := TStopwatch.StartNew;
            while not Async.IsCompleted and (Watch.ElapsedMilliseconds < TAtlasShutdown.StopMs div 2) do
              Sleep(10);
            AError := 'abgebrochen';
            Exit;
          end;
        Response := THTTPClient.EndAsyncHTTP(Async);
        if not IsRedirect(Response.StatusCode) then
          Break;
        Inc(Redirects);
        if Redirects > MaxRedirects then
        begin
          AError := 'zu viele Weiterleitungen';
          Exit;
        end;
        Url := Response.HeaderValue['Location'];
      end;
      if Response.StatusCode <> 200 then
      begin
        AError := Format('HTTP %d', [Response.StatusCode]);
        Exit;
      end;
      if Content.Size > MaxBytes then
      begin
        AError := 'Antwort zu groß';
        Exit;
      end;
      AText := TEncoding.UTF8.GetString(Content.Bytes, 0, Content.Size);
      Result := True;
    except
      on E: Exception do
        AError := E.ClassName;
    end;
  finally
    // Erst die Schnittstellen lösen, sie verweisen auf den Client.
    Response := nil;
    Async := nil;
    Content.Free;
    Client.Free;
  end;
end;

end.
