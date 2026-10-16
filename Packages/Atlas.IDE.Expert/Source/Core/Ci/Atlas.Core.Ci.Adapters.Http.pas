unit Atlas.Core.Ci.Adapters.Http;

// GET beim Build-Server (#763), aus einem Hintergrund-Thread. Wie die
// Versionsabfrage (#495): asynchron, abgebrochen beim Entladen des Plugins
// (TAtlasShutdown) oder nach der Zeitgrenze, keine Cookies, Weiterleitungen
// folgt Atlas selbst.
// Anmeldung: Benutzer und API-Token aus dem Anmeldespeicher von Windows
// (Atlas.Core.Ci.Adapters.Credentials) gehen als „Authorization: Basic“ nur
// über https und nur an den eingetragenen Server; über http fragt Atlas ohne
// Anmeldung. Weiterleitungen nur auf denselben Rechner (http → https erlaubt),
// damit das Token nie an einen anderen Server geht. Weder Adresse noch Token
// kommen ins Protokoll.
// Der Issue-Tracker (#765) nutzt denselben Transport mit
// „Authorization: Bearer <Token>“ (CreateBearer; GitHub und YouTrack), unter
// denselben Regeln für https, Server und Weiterleitungen.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract;

type
  TAtlasCiHttpTransport = class(TInterfacedObject, IAtlasCiTransport)
  private
    FServer: string;
    FUser: string;
    FToken: string;
    FBearer: Boolean;
  public
    /// <summary>AServer wie TAtlasCiJob.Server; AUser/AToken leer = ohne Anmeldung.</summary>
    constructor Create(const AServer, AUser, AToken: string);
    /// <summary>Anmeldung mit „Authorization: Bearer“ (#765); AToken leer = ohne Anmeldung.</summary>
    constructor CreateBearer(const AServer, AToken: string);
    destructor Destroy; override;
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

implementation

uses
  System.Classes,
  System.Types,
  System.Diagnostics,
  System.NetEncoding,
  System.Net.HttpClient,
  System.Net.URLClient,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Ci.Internals.Addresses;

const
  // Testberichte mit tree=… bleiben klein; mehr wird nicht gelesen.
  MaxBytes = 8 * 1024 * 1024;
  MaxRedirects = 3;
  SliceMs = 50;

function IsRedirect(AStatus: Integer): Boolean;
begin
  Result := (AStatus = 301) or (AStatus = 302) or (AStatus = 303) or (AStatus = 307) or (AStatus = 308);
end;

{ TAtlasCiHttpTransport }

constructor TAtlasCiHttpTransport.Create(const AServer, AUser, AToken: string);
begin
  inherited Create;
  FServer := LowerCase(AServer);
  FUser := AUser;
  FToken := AToken;
end;

constructor TAtlasCiHttpTransport.CreateBearer(const AServer, AToken: string);
begin
  Create(AServer, '', AToken);
  FBearer := True;
end;

destructor TAtlasCiHttpTransport.Destroy;
begin
  // Das Token nicht länger als nötig im Speicher lassen.
  if FToken <> '' then
  begin
    UniqueString(FToken);
    FillChar(PChar(FToken)^, Length(FToken) * SizeOf(Char), 0);
  end;
  inherited;
end;

function TAtlasCiHttpTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer;
  out AText: string; out AError: TAtlasCiFetchError): Boolean;
var
  Client: THTTPClient;
  Content: TBytesStream;
  Async: IAsyncResult;
  Response: IHTTPResponse;
  Watch, Wait: TStopwatch;
  Url, Next: string;
  Redirects: Integer;
  Headers: TNetHeaders;
  Encoding: TBase64Encoding;
begin
  Result := False;
  AStatus := 0;
  AText := '';
  AError := TAtlasCiFetchError.Network;
  Client := THTTPClient.Create;
  Content := TBytesStream.Create;
  try
    Client.ConnectionTimeout := ATimeoutMs;
    Client.ResponseTimeout := ATimeoutMs;
    Client.HandleRedirects := False;
    Client.AllowCookies := False;
    Client.UserAgent := 'Atlas';
    Client.Accept := 'application/json';
    Url := AUrl;
    Redirects := 0;
    Watch := TStopwatch.StartNew;
    try
      while True do
      begin
        Headers := nil;
        // Anmeldung nur über https beim eingetragenen Server.
        if FBearer and (FToken <> '') and TAtlasCiAddresses.MayAuthenticate(Url, FServer) then
          Headers := [TNetHeader.Create('Authorization', 'Bearer ' + FToken)]
        else if (FUser <> '') and (FToken <> '') and TAtlasCiAddresses.MayAuthenticate(Url, FServer) then
        begin
          Encoding := TBase64Encoding.Create(0);
          try
            Headers := [TNetHeader.Create('Authorization', 'Basic ' +
              Encoding.EncodeBytesToString(TEncoding.UTF8.GetBytes(FUser + ':' + FToken)))];
          finally
            Encoding.Free;
          end;
        end;
        Content.Clear;
        Async := Client.BeginGet(Url, Content, Headers);
        while not Async.IsCompleted do
          if TAtlasShutdown.Wait(SliceMs) or (Watch.ElapsedMilliseconds > ATimeoutMs) then
          begin
            if Watch.ElapsedMilliseconds > ATimeoutMs then
              AError := TAtlasCiFetchError.Timeout
            else
              AError := TAtlasCiFetchError.Cancelled;
            Async.Cancel;
            // Kurz auf das Ende warten, damit der Client danach freigegeben werden darf.
            Wait := TStopwatch.StartNew;
            while not Async.IsCompleted and (Wait.ElapsedMilliseconds < TAtlasShutdown.StopMs div 2) do
              Sleep(10);
            Exit;
          end;
        Response := THTTPClient.EndAsyncHTTP(Async);
        if not IsRedirect(Response.StatusCode) then
          Break;
        Inc(Redirects);
        Next := TAtlasCiAddresses.Resolve(Url, Response.HeaderValue['Location']);
        if (Redirects > MaxRedirects) or not TAtlasCiAddresses.RedirectAllowed(Url, Next) then
        begin
          // Fremdes Ziel (z. B. Anmeldeseite eines anderen Rechners): wie eine abgelehnte Anmeldung.
          AStatus := Response.StatusCode;
          AError := TAtlasCiFetchError.Unauthorized;
          Exit;
        end;
        Url := Next;
      end;
      AStatus := Response.StatusCode;
      if Content.Size > MaxBytes then
      begin
        AError := TAtlasCiFetchError.Invalid;
        Exit;
      end;
      AText := TEncoding.UTF8.GetString(Content.Bytes, 0, Content.Size);
      AError := TAtlasCiFetchError.None;
      Result := True;
    except
      // Kein Netz, Name unbekannt, Zertifikat abgelehnt …: still als Fehler der Abfrage.
      if Watch.ElapsedMilliseconds > ATimeoutMs then
        AError := TAtlasCiFetchError.Timeout
      else
        AError := TAtlasCiFetchError.Network;
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
