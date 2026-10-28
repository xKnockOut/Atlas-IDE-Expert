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
// Die Issue-Vorschau (#1264) lädt darüber auch Bilder und Anhänge
// (IAtlasCiDownload) und bricht beim Schließen des Fensters ab
// (IAtlasCiCancel). Abgehakte Checklisten (#1273) schreibt sie mit POST bzw.
// PATCH zurück (IAtlasCiSend): nur mit Token, nur über https an den
// eingetragenen Server, ohne Weiterleitungen.
// Die Meldungen zu Issues (#1271) fragen GitHub bedingt
// (IAtlasCiConditional: If-Modified-Since, Last-Modified, X-Poll-Interval).
// „An Issue anhängen“ (#1276) sendet darüber Anhänge und Kommentare
// (IAtlasCiPost, POST beliebigen Inhalts) unter denselben Regeln wie
// IAtlasCiSend.

interface

uses
  System.SysUtils,
  System.Net.URLClient,
  Atlas.Core.Ci.Contract;

type
  TAtlasCiHttpTransport = class(TInterfacedObject, IAtlasCiTransport, IAtlasCiDownload, IAtlasCiSend, IAtlasCiPost,
    IAtlasCiCancel, IAtlasCiConditional)
  private
    FServer: string;
    FUser: string;
    FToken: string;
    FBearer: Boolean;
    FCancelled: Integer;
    /// <summary>AMethod "GET", "POST" oder "PATCH"; ABody nur beim Schreiben (JSON).</summary>
    function Request(const AMethod, AUrl, AAccept: string; const ABody: TBytes; ATimeoutMs, AMaxBytes: Integer;
      out AStatus: Integer; out ABytes: TBytes; out AError: TAtlasCiFetchError): Boolean; overload;
    /// <summary>Wie oben, mit dem Inhaltstyp von ABody (AContentType, #1276), zusätzlichem If-Modified-Since
    /// (AIfModifiedSince '' = ohne, #1271) und den Köpfen Last-Modified und X-Poll-Interval der Antwort.</summary>
    function Request(const AMethod, AUrl, AAccept, AContentType, AIfModifiedSince: string; const ABody: TBytes;
      ATimeoutMs, AMaxBytes: Integer; out AStatus: Integer; out ABytes: TBytes; out ALastModified,
      APollInterval: string; out AError: TAtlasCiFetchError): Boolean; overload;
    /// <summary>Schreiben nur angemeldet beim eingetragenen Server über https, nie ohne Token.</summary>
    function MayWrite(const AUrl: string): Boolean;
    function AuthHeaders(const AUrl: string): TNetHeaders;
    function Cancelled: Boolean;
  public
    /// <summary>AServer wie TAtlasCiJob.Server; AUser/AToken leer = ohne Anmeldung.</summary>
    constructor Create(const AServer, AUser, AToken: string);
    /// <summary>Anmeldung mit „Authorization: Bearer“ (#765); AToken leer = ohne Anmeldung.</summary>
    constructor CreateBearer(const AServer, AToken: string);
    destructor Destroy; override;
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
    function GetBytes(const AUrl: string; ATimeoutMs, AMaxBytes: Integer; out AStatus: Integer; out ABytes: TBytes;
      out AError: TAtlasCiFetchError): Boolean;
    function Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
    procedure Cancel;
    function GetConditional(const AUrl, AIfModifiedSince: string; ATimeoutMs: Integer; out AStatus: Integer;
      out AText, ALastModified: string; out APollSeconds: Integer; out AError: TAtlasCiFetchError): Boolean;
    function Post(const AUrl, AContentType: string; const ABody: TBytes; ATimeoutMs: Integer; out AStatus: Integer;
      out AText: string; out AError: TAtlasCiFetchError): Boolean;
  end;

implementation

uses
  System.Classes,
  System.Types,
  System.Diagnostics,
  System.NetEncoding,
  System.Net.HttpClient,
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
  mBytes: TBytes;
begin
  AText := '';
  Result := Request('GET', AUrl, 'application/json', nil, ATimeoutMs, MaxBytes, AStatus, mBytes, AError);
  if Result then
    AText := TEncoding.UTF8.GetString(mBytes);
end;

function TAtlasCiHttpTransport.GetBytes(const AUrl: string; ATimeoutMs, AMaxBytes: Integer; out AStatus: Integer;
  out ABytes: TBytes; out AError: TAtlasCiFetchError): Boolean;
begin
  Result := Request('GET', AUrl, '*/*', nil, ATimeoutMs, AMaxBytes, AStatus, ABytes, AError);
end;

function TAtlasCiHttpTransport.Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AStatus: Integer;
  out AText: string; out AError: TAtlasCiFetchError): Boolean;
var
  mBytes: TBytes;
begin
  AText := '';
  AStatus := 0;
  Result := False;
  if not (SameText(AMethod, 'POST') or SameText(AMethod, 'PATCH')) or not MayWrite(AUrl) then
  begin
    AError := TAtlasCiFetchError.Unauthorized;
    Exit;
  end;
  Result := Request(UpperCase(AMethod), AUrl, 'application/json', TEncoding.UTF8.GetBytes(ABody), ATimeoutMs,
    MaxBytes, AStatus, mBytes, AError);
  if Result then
    AText := TEncoding.UTF8.GetString(mBytes);
end;

function TAtlasCiHttpTransport.Post(const AUrl, AContentType: string; const ABody: TBytes; ATimeoutMs: Integer;
  out AStatus: Integer; out AText: string; out AError: TAtlasCiFetchError): Boolean;
var
  mBytes: TBytes;
  mLastModified, mPoll: string;
begin
  AText := '';
  AStatus := 0;
  Result := False;
  if not MayWrite(AUrl) then
  begin
    AError := TAtlasCiFetchError.Unauthorized;
    Exit;
  end;
  // Leerer Inhalt: nichts zu senden.
  if Length(ABody) = 0 then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  Result := Request('POST', AUrl, 'application/json', AContentType, '', ABody, ATimeoutMs, MaxBytes, AStatus, mBytes,
    mLastModified, mPoll, AError);
  if Result then
    AText := TEncoding.UTF8.GetString(mBytes);
end;

function TAtlasCiHttpTransport.MayWrite(const AUrl: string): Boolean;
begin
  Result := (FToken <> '') and TAtlasCiAddresses.MayAuthenticate(AUrl, FServer);
end;

procedure TAtlasCiHttpTransport.Cancel;
begin
  AtomicExchange(FCancelled, 1);
end;

function TAtlasCiHttpTransport.Cancelled: Boolean;
begin
  Result := AtomicCmpExchange(FCancelled, 0, 0) <> 0;
end;

function TAtlasCiHttpTransport.GetConditional(const AUrl, AIfModifiedSince: string; ATimeoutMs: Integer;
  out AStatus: Integer; out AText, ALastModified: string; out APollSeconds: Integer;
  out AError: TAtlasCiFetchError): Boolean;
var
  mBytes: TBytes;
  mPoll: string;
begin
  AText := '';
  APollSeconds := 0;
  Result := Request('GET', AUrl, 'application/json', AIfModifiedSince, nil, ATimeoutMs, MaxBytes, AStatus, mBytes,
    ALastModified, mPoll, AError);
  if not Result then
    Exit;
  AText := TEncoding.UTF8.GetString(mBytes);
  if not TryStrToInt(Trim(mPoll), APollSeconds) or (APollSeconds < 0) then
    APollSeconds := 0;
end;

function TAtlasCiHttpTransport.Request(const AMethod, AUrl, AAccept: string; const ABody: TBytes;
  ATimeoutMs, AMaxBytes: Integer; out AStatus: Integer; out ABytes: TBytes; out AError: TAtlasCiFetchError): Boolean;
var
  mLastModified, mPoll: string;
begin
  Result := Request(AMethod, AUrl, AAccept, 'application/json; charset=utf-8', '', ABody, ATimeoutMs, AMaxBytes,
    AStatus, ABytes, mLastModified, mPoll, AError);
end;

function TAtlasCiHttpTransport.AuthHeaders(const AUrl: string): TNetHeaders;
var
  Encoding: TBase64Encoding;
begin
  Result := nil;
  // Anmeldung nur über https beim eingetragenen Server.
  if FBearer and (FToken <> '') and TAtlasCiAddresses.MayAuthenticate(AUrl, FServer) then
    Result := [TNetHeader.Create('Authorization', 'Bearer ' + FToken)]
  else if (FUser <> '') and (FToken <> '') and TAtlasCiAddresses.MayAuthenticate(AUrl, FServer) then
  begin
    Encoding := TBase64Encoding.Create(0);
    try
      Result := [TNetHeader.Create('Authorization', 'Basic ' +
        Encoding.EncodeBytesToString(TEncoding.UTF8.GetBytes(FUser + ':' + FToken)))];
    finally
      Encoding.Free;
    end;
  end;
end;

function TAtlasCiHttpTransport.Request(const AMethod, AUrl, AAccept, AContentType, AIfModifiedSince: string;
  const ABody: TBytes; ATimeoutMs, AMaxBytes: Integer; out AStatus: Integer; out ABytes: TBytes; out ALastModified,
  APollInterval: string; out AError: TAtlasCiFetchError): Boolean;
var
  Client: THTTPClient;
  Content: TBytesStream;
  Source: TBytesStream;
  Async: IAsyncResult;
  Response: IHTTPResponse;
  Watch, Wait: TStopwatch;
  Url, Next: string;
  Redirects: Integer;
  Headers: TNetHeaders;
begin
  Result := False;
  AStatus := 0;
  ABytes := nil;
  ALastModified := '';
  APollInterval := '';
  AError := TAtlasCiFetchError.Network;
  if Cancelled then
  begin
    AError := TAtlasCiFetchError.Cancelled;
    Exit;
  end;
  Client := THTTPClient.Create;
  Content := TBytesStream.Create;
  Source := nil;
  if AMethod <> 'GET' then
    Source := TBytesStream.Create(ABody);
  try
    Client.ConnectionTimeout := ATimeoutMs;
    Client.ResponseTimeout := ATimeoutMs;
    Client.HandleRedirects := False;
    Client.AllowCookies := False;
    Client.UserAgent := 'Atlas';
    Client.Accept := AAccept;
    Url := AUrl;
    Redirects := 0;
    Watch := TStopwatch.StartNew;
    try
      while True do
      begin
        Headers := AuthHeaders(Url);
        if AIfModifiedSince <> '' then
          Headers := Headers + [TNetHeader.Create('If-Modified-Since', AIfModifiedSince)];
        Content.Clear;
        if AMethod = 'GET' then
          Async := Client.BeginGet(Url, Content, Headers)
        else
        begin
          Headers := Headers + [TNetHeader.Create('Content-Type', AContentType)];
          Source.Position := 0;
          if AMethod = 'PATCH' then
            Async := Client.BeginPatch(Url, Source, Content, Headers)
          else
            Async := Client.BeginPost(Url, Source, Content, Headers);
        end;
        while not Async.IsCompleted do
          if TAtlasShutdown.Wait(SliceMs) or Cancelled or (Watch.ElapsedMilliseconds > ATimeoutMs) then
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
        // Geschrieben wird nur an die eingetragene Adresse: Eine Weiterleitung ist ein Fehler, der Inhalt ginge sonst
        // an ein anderes Ziel.
        if AMethod <> 'GET' then
        begin
          AStatus := Response.StatusCode;
          AError := TAtlasCiFetchError.Server;
          Exit;
        end;
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
      ALastModified := Response.HeaderValue['Last-Modified'];
      APollInterval := Response.HeaderValue['X-Poll-Interval'];
      if Content.Size > AMaxBytes then
      begin
        AError := TAtlasCiFetchError.Invalid;
        Exit;
      end;
      ABytes := Copy(Content.Bytes, 0, Content.Size);
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
    Source.Free;
    Content.Free;
    Client.Free;
  end;
end;

end.
