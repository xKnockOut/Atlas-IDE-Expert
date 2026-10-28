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
// (IAtlasCiCancel).
// „An Issue anhängen“ (#1276) sendet darüber Anhänge und Kommentare
// (IAtlasCiSend, POST): gleiche Anmeldung nur über https an den eingetragenen
// Server, aber ohne Weiterleitungen, damit kein Inhalt an ein anderes Ziel
// geht.

interface

uses
  System.SysUtils,
  System.Net.URLClient,
  Atlas.Core.Ci.Contract;

type
  TAtlasCiHttpTransport = class(TInterfacedObject, IAtlasCiTransport, IAtlasCiDownload, IAtlasCiCancel, IAtlasCiSend)
  private
    FServer: string;
    FUser: string;
    FToken: string;
    FBearer: Boolean;
    FCancelled: Integer;
    function Request(const AUrl, AAccept: string; ATimeoutMs, AMaxBytes: Integer; out AStatus: Integer;
      out ABytes: TBytes; out AError: TAtlasCiFetchError): Boolean; overload;
    /// <summary>ABody = nil: GET mit Weiterleitungen; sonst POST von ABody als AContentType ohne Weiterleitungen.
    /// </summary>
    function Request(const AUrl, AAccept, AContentType: string; const ABody: TBytes; ATimeoutMs, AMaxBytes: Integer;
      out AStatus: Integer; out ABytes: TBytes; out AError: TAtlasCiFetchError): Boolean; overload;
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
    procedure Cancel;
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
  Result := Request(AUrl, 'application/json', ATimeoutMs, MaxBytes, AStatus, mBytes, AError);
  if Result then
    AText := TEncoding.UTF8.GetString(mBytes);
end;

function TAtlasCiHttpTransport.GetBytes(const AUrl: string; ATimeoutMs, AMaxBytes: Integer; out AStatus: Integer;
  out ABytes: TBytes; out AError: TAtlasCiFetchError): Boolean;
begin
  Result := Request(AUrl, '*/*', ATimeoutMs, AMaxBytes, AStatus, ABytes, AError);
end;

function TAtlasCiHttpTransport.Post(const AUrl, AContentType: string; const ABody: TBytes; ATimeoutMs: Integer;
  out AStatus: Integer; out AText: string; out AError: TAtlasCiFetchError): Boolean;
var
  mBytes: TBytes;
begin
  AText := '';
  // Leerer Inhalt wäre ein GET: ein Byte ist das Mindeste, was ein POST hier sendet.
  if Length(ABody) = 0 then
  begin
    AStatus := 0;
    AError := TAtlasCiFetchError.Invalid;
    Exit(False);
  end;
  Result := Request(AUrl, 'application/json', AContentType, ABody, ATimeoutMs, MaxBytes, AStatus, mBytes, AError);
  if Result then
    AText := TEncoding.UTF8.GetString(mBytes);
end;

procedure TAtlasCiHttpTransport.Cancel;
begin
  AtomicExchange(FCancelled, 1);
end;

function TAtlasCiHttpTransport.Cancelled: Boolean;
begin
  Result := AtomicCmpExchange(FCancelled, 0, 0) <> 0;
end;

function TAtlasCiHttpTransport.Request(const AUrl, AAccept: string; ATimeoutMs, AMaxBytes: Integer;
  out AStatus: Integer; out ABytes: TBytes; out AError: TAtlasCiFetchError): Boolean;
begin
  Result := Request(AUrl, AAccept, '', nil, ATimeoutMs, AMaxBytes, AStatus, ABytes, AError);
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

function TAtlasCiHttpTransport.Request(const AUrl, AAccept, AContentType: string; const ABody: TBytes; ATimeoutMs,
  AMaxBytes: Integer; out AStatus: Integer; out ABytes: TBytes; out AError: TAtlasCiFetchError): Boolean;
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
  mPost: Boolean;
begin
  Result := False;
  AStatus := 0;
  ABytes := nil;
  AError := TAtlasCiFetchError.Network;
  if Cancelled then
  begin
    AError := TAtlasCiFetchError.Cancelled;
    Exit;
  end;
  mPost := Length(ABody) > 0;
  Client := THTTPClient.Create;
  Content := TBytesStream.Create;
  Source := nil;
  try
    Client.ConnectionTimeout := ATimeoutMs;
    Client.ResponseTimeout := ATimeoutMs;
    Client.HandleRedirects := False;
    Client.AllowCookies := False;
    Client.UserAgent := 'Atlas';
    Client.Accept := AAccept;
    if mPost then
    begin
      Client.ContentType := AContentType;
      Source := TBytesStream.Create(ABody);
    end;
    Url := AUrl;
    Redirects := 0;
    Watch := TStopwatch.StartNew;
    try
      while True do
      begin
        Headers := AuthHeaders(Url);
        Content.Clear;
        if mPost then
        begin
          Source.Position := 0;
          Async := Client.BeginPost(Url, Source, Content, Headers);
        end
        else
          Async := Client.BeginGet(Url, Content, Headers);
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
        Inc(Redirects);
        Next := TAtlasCiAddresses.Resolve(Url, Response.HeaderValue['Location']);
        // Ein POST folgt keiner Weiterleitung: Inhalt und Token gehen nur an die eingetragene Adresse.
        if mPost or (Redirects > MaxRedirects) or not TAtlasCiAddresses.RedirectAllowed(Url, Next) then
        begin
          // Fremdes Ziel (z. B. Anmeldeseite eines anderen Rechners): wie eine abgelehnte Anmeldung.
          AStatus := Response.StatusCode;
          AError := TAtlasCiFetchError.Unauthorized;
          Exit;
        end;
        Url := Next;
      end;
      AStatus := Response.StatusCode;
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
