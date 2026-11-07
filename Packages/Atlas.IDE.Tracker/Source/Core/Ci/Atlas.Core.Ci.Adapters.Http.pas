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
  System.Classes,
  System.Types,
  System.Diagnostics,
  System.Net.URLClient,
  System.Net.HttpClient,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract;

type
  TAtlasCiHttpTransport = class(TInterfacedObject, IAtlasCiTransport, IAtlasCiDownload, IAtlasCiSend, IAtlasCiPost,
    IAtlasCiCancel, IAtlasCiConditional)
  private type
    /// <summary>Eine Anfrage: AMethod "GET", "POST" oder "PATCH"; Body nur beim Schreiben, mit ContentType;
    /// IfModifiedSince '' = ohne (#1271).</summary>
    TRequest = record
      Method: string;
      Url: string;
      Accept: string;
      ContentType: string;
      IfModifiedSince: string;
      Body: TBytes;
      TimeoutMs: Integer;
      MaxBytes: Integer;
      /// <summary>Ohne Inhalt und Bedingung; Inhaltstyp JSON.</summary>
      class function Create(const AMethod, AUrl, AAccept: string; ATimeoutMs, AMaxBytes: Integer): TRequest;
        static;
    end;

    /// <summary>Antwort: Status, Inhalt und die Köpfe Last-Modified und X-Poll-Interval.</summary>
    TReply = record
      Status: Integer;
      Bytes: TBytes;
      LastModified: string;
      PollInterval: string;
      Error: TAtlasCiFetchError;
    end;
  private
    FServer: string;
    FUser: string;
    FToken: string;
    FBearer: Boolean;
    FCancelled: Integer;
    function Request(const ARequest: TRequest; out AReply: TReply): Boolean;
    /// <summary>Anfrage an AUrl (nach Weiterleitungen) beginnen; ASource nur beim Schreiben.</summary>
    function StartRequest(AClient: THTTPClient; const ARequest: TRequest; const AUrl: string;
      ASource, AContent: TBytesStream): IAsyncResult;
    /// <summary>Auf das Ende von AAsync warten; False mit AError bei Zeitgrenze, Abbruch oder Entladen.</summary>
    function AwaitResponse(const AAsync: IAsyncResult; const AWatch: TStopwatch; ATimeoutMs: Integer;
      var AError: TAtlasCiFetchError): Boolean;
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
    function Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AResponse: TAtlasCiResponse):
      Boolean;
    procedure Cancel;
    function GetConditional(const AUrl, AIfModifiedSince: string; ATimeoutMs: Integer;
      out AResponse: TAtlasCiResponse): Boolean;
    function Post(const AUrl, AContentType: string; const ABody: TBytes; ATimeoutMs: Integer;
      out AResponse: TAtlasCiResponse): Boolean;
  end;

  /// <summary>IAtlasCiTransports über TAtlasCiHttpTransport (#1455); erzeugt nur die Komposition des Moduls
  /// Tracker.</summary>
  TAtlasCiHttpTransports = class(TInterfacedObject, IAtlasCiTransports)
  public
    function Basic(const AServer, AUser, AToken: string): IAtlasCiTransport;
    function Bearer(const AServer, AToken: string): IAtlasCiTransport;
  end;

implementation

uses
  System.NetEncoding,
  System.NetConsts,
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
  mReply: TReply;
begin
  AText := '';
  Result := Request(TRequest.Create('GET', AUrl, 'application/json', ATimeoutMs, MaxBytes), mReply);
  AStatus := mReply.Status;
  AError := mReply.Error;
  if Result then
  begin
    AText := TEncoding.UTF8.GetString(mReply.Bytes);
  end;
end;

function TAtlasCiHttpTransport.GetBytes(const AUrl: string; ATimeoutMs, AMaxBytes: Integer; out AStatus: Integer;
  out ABytes: TBytes; out AError: TAtlasCiFetchError): Boolean;
var
  mReply: TReply;
begin
  Result := Request(TRequest.Create('GET', AUrl, '*/*', ATimeoutMs, AMaxBytes), mReply);
  AStatus := mReply.Status;
  ABytes := mReply.Bytes;
  AError := mReply.Error;
end;

/// <summary>Antwort für die Aufrufer; Inhalt und X-Poll-Interval nur, wenn AOk.</summary>
function ResponseOf(const AReply: TAtlasCiHttpTransport.TReply; AOk: Boolean): TAtlasCiResponse;
begin
  Result := TAtlasCiResponse.Failed(AReply.Error);
  Result.Status := AReply.Status;
  Result.LastModified := AReply.LastModified;
  if AOk then
  begin
    Result.Text := TEncoding.UTF8.GetString(AReply.Bytes);
    if not TryStrToInt(Trim(AReply.PollInterval), Result.PollSeconds) or (Result.PollSeconds < 0) then
    begin
      Result.PollSeconds := 0;
    end;
  end;
end;

function TAtlasCiHttpTransport.Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer;
  out AResponse: TAtlasCiResponse): Boolean;
var
  mRequest: TRequest;
  mReply: TReply;
begin
  Result := False;
  AResponse := TAtlasCiResponse.Failed(TAtlasCiFetchError.Unauthorized);
  if not (SameText(AMethod, 'POST') or SameText(AMethod, 'PATCH')) or not MayWrite(AUrl) then
  begin
    Exit;
  end;
  mRequest := TRequest.Create(UpperCase(AMethod), AUrl, 'application/json', ATimeoutMs, MaxBytes);
  mRequest.Body := TEncoding.UTF8.GetBytes(ABody);
  Result := Request(mRequest, mReply);
  AResponse := ResponseOf(mReply, Result);
end;

function TAtlasCiHttpTransport.Post(const AUrl, AContentType: string; const ABody: TBytes; ATimeoutMs: Integer;
  out AResponse: TAtlasCiResponse): Boolean;
var
  mRequest: TRequest;
  mReply: TReply;
begin
  Result := False;
  AResponse := TAtlasCiResponse.Failed(TAtlasCiFetchError.Unauthorized);
  if not MayWrite(AUrl) then
  begin
    Exit;
  end;
  // Leerer Inhalt: nichts zu senden.
  if Length(ABody) = 0 then
  begin
    AResponse.Error := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  mRequest := TRequest.Create('POST', AUrl, 'application/json', ATimeoutMs, MaxBytes);
  mRequest.ContentType := AContentType;
  mRequest.Body := ABody;
  Result := Request(mRequest, mReply);
  AResponse := ResponseOf(mReply, Result);
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
  out AResponse: TAtlasCiResponse): Boolean;
var
  mRequest: TRequest;
  mReply: TReply;
begin
  mRequest := TRequest.Create('GET', AUrl, 'application/json', ATimeoutMs, MaxBytes);
  mRequest.ContentType := '';
  mRequest.IfModifiedSince := AIfModifiedSince;
  Result := Request(mRequest, mReply);
  AResponse := ResponseOf(mReply, Result);
end;

{ TAtlasCiHttpTransport.TRequest }

class function TAtlasCiHttpTransport.TRequest.Create(const AMethod, AUrl, AAccept: string;
  ATimeoutMs, AMaxBytes: Integer): TRequest;
begin
  Result := Default(TRequest);
  Result.Method := AMethod;
  Result.Url := AUrl;
  Result.Accept := AAccept;
  Result.ContentType := 'application/json; charset=utf-8';
  Result.IfModifiedSince := '';
  Result.Body := nil;
  Result.TimeoutMs := ATimeoutMs;
  Result.MaxBytes := AMaxBytes;
end;

function TAtlasCiHttpTransport.AuthHeaders(const AUrl: string): TNetHeaders;
var
  Encoding: TBase64Encoding;
begin
  Result := nil;
  // Anmeldung nur über https beim eingetragenen Server.
  if FBearer and (FToken <> '') and TAtlasCiAddresses.MayAuthenticate(AUrl, FServer) then
  begin
    Result := [TNetHeader.Create('Authorization', 'Bearer ' + FToken)];
  end
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

/// <summary>Client ohne Cookies und ohne eigene Weiterleitungen, mit der Zeitgrenze von ARequest.</summary>
function ClientFor(const ARequest: TAtlasCiHttpTransport.TRequest): THTTPClient;
begin
  Result := THTTPClient.Create;
  Result.ConnectionTimeout := ARequest.TimeoutMs;
  Result.ResponseTimeout := ARequest.TimeoutMs;
  Result.HandleRedirects := False;
  Result.AllowCookies := False;
  Result.UserAgent := 'Atlas';
  Result.Accept := ARequest.Accept;
end;

function TAtlasCiHttpTransport.StartRequest(AClient: THTTPClient; const ARequest: TRequest; const AUrl: string;
  ASource, AContent: TBytesStream): IAsyncResult;
var
  mHeaders: TNetHeaders;
begin
  mHeaders := AuthHeaders(AUrl);
  if ARequest.IfModifiedSince <> '' then
  begin
    mHeaders := mHeaders + [TNetHeader.Create('If-Modified-Since', ARequest.IfModifiedSince)];
  end;
  AContent.Clear;
  if ARequest.Method = 'GET' then
  begin
    Result := AClient.BeginGet(AUrl, AContent, mHeaders);
    Exit;
  end;
  mHeaders := mHeaders + [TNetHeader.Create('Content-Type', ARequest.ContentType)];
  ASource.Position := 0;
  if ARequest.Method = 'PATCH' then
  begin
    Result := AClient.BeginPatch(AUrl, ASource, AContent, mHeaders);
  end
  else
  begin
    Result := AClient.BeginPost(AUrl, ASource, AContent, mHeaders);
  end;
end;

function TAtlasCiHttpTransport.AwaitResponse(const AAsync: IAsyncResult; const AWatch: TStopwatch;
  ATimeoutMs: Integer; var AError: TAtlasCiFetchError): Boolean;
var
  mWait: TStopwatch;
begin
  Result := True;
  while Result and not AAsync.IsCompleted do
  begin
    Result := not (TAtlasShutdown.Wait(SliceMs) or Cancelled or (AWatch.ElapsedMilliseconds > ATimeoutMs));
  end;
  if Result then
  begin
    Exit;
  end;
  if AWatch.ElapsedMilliseconds > ATimeoutMs then
  begin
    AError := TAtlasCiFetchError.Timeout;
  end
  else
  begin
    AError := TAtlasCiFetchError.Cancelled;
  end;
  AAsync.Cancel;
  // Kurz auf das Ende warten, damit der Client danach freigegeben werden darf.
  mWait := TStopwatch.StartNew;
  while not AAsync.IsCompleted and (mWait.ElapsedMilliseconds < TAtlasShutdown.cStopMs div 2) do
  begin
    Sleep(10);
  end;
end;

/// <summary>Ziel einer Weiterleitung in AUrl; False mit Status und Fehler in AReply, wenn ihr nicht gefolgt wird.
/// </summary>
function FollowRedirect(const AResponse: IHTTPResponse; const AMethod: string; var AUrl: string;
  var ARedirects: Integer; var AReply: TAtlasCiHttpTransport.TReply): Boolean;
var
  mNext: string;
begin
  Result := False;
  AReply.Status := AResponse.StatusCode;
  // Geschrieben wird nur an die eingetragene Adresse: Eine Weiterleitung ist ein Fehler, der Inhalt ginge sonst
  // an ein anderes Ziel.
  if AMethod <> 'GET' then
  begin
    AReply.Error := TAtlasCiFetchError.Server;
    Exit;
  end;
  Inc(ARedirects);
  mNext := TAtlasCiAddresses.Resolve(AUrl, AResponse.HeaderValue['Location']);
  if (ARedirects > MaxRedirects) or not TAtlasCiAddresses.RedirectAllowed(AUrl, mNext) then
  begin
    // Fremdes Ziel (z. B. Anmeldeseite eines anderen Rechners): wie eine abgelehnte Anmeldung.
    AReply.Error := TAtlasCiFetchError.Unauthorized;
    Exit;
  end;
  AReply.Status := 0;
  AUrl := mNext;
  Result := True;
end;

/// <summary>Status, Köpfe und Inhalt (höchstens AMaxBytes) der letzten Antwort in AReply.</summary>
function ReadReply(const AResponse: IHTTPResponse; AContent: TBytesStream; AMaxBytes: Integer;
  var AReply: TAtlasCiHttpTransport.TReply): Boolean;
begin
  AReply.Status := AResponse.StatusCode;
  AReply.LastModified := AResponse.HeaderValue['Last-Modified'];
  AReply.PollInterval := AResponse.HeaderValue['X-Poll-Interval'];
  Result := AContent.Size <= AMaxBytes;
  if Result then
  begin
    AReply.Bytes := Copy(AContent.Bytes, 0, AContent.Size);
    AReply.Error := TAtlasCiFetchError.None;
  end
  else
  begin
    AReply.Error := TAtlasCiFetchError.Invalid;
  end;
end;

/// <summary>Fehler einer Anfrage, die mit einer Ausnahme endete: Timeout nach der Zeitgrenze, sonst Network.
/// </summary>
function FailureAfter(const AWatch: TStopwatch; ATimeoutMs: Integer): TAtlasCiFetchError;
begin
  Result := TAtlasCiFetchError.Network;
  if AWatch.ElapsedMilliseconds > ATimeoutMs then
  begin
    Result := TAtlasCiFetchError.Timeout;
  end;
end;

function TAtlasCiHttpTransport.Request(const ARequest: TRequest; out AReply: TReply): Boolean;
var
  mClient: THTTPClient;
  mContent, mSource: TBytesStream;
  mAsync: IAsyncResult;
  mResponse: IHTTPResponse;
  mWatch: TStopwatch;
  mUrl: string;
  mRedirects: Integer;
begin
  Result := False;
  AReply := Default(TReply);
  AReply.Error := TAtlasCiFetchError.Network;
  if Cancelled then
  begin
    AReply.Error := TAtlasCiFetchError.Cancelled;
    Exit;
  end;
  mClient := ClientFor(ARequest);
  mContent := TBytesStream.Create;
  mSource := nil;
  if ARequest.Method <> 'GET' then
  begin
    mSource := TBytesStream.Create(ARequest.Body);
  end;
  try
    mUrl := ARequest.Url;
    mRedirects := 0;
    mWatch := TStopwatch.StartNew;
    try
      repeat
        mAsync := StartRequest(mClient, ARequest, mUrl, mSource, mContent);
        if not AwaitResponse(mAsync, mWatch, ARequest.TimeoutMs, AReply.Error) then
        begin
          Exit;
        end;
        mResponse := THTTPClient.EndAsyncHTTP(mAsync);
        if IsRedirect(mResponse.StatusCode) and not FollowRedirect(mResponse, ARequest.Method, mUrl, mRedirects,
          AReply) then
        begin
          Exit;
        end;
      until not IsRedirect(mResponse.StatusCode);
      Result := ReadReply(mResponse, mContent, ARequest.MaxBytes, AReply);
    except
      // Kein Netz, Name unbekannt, Zertifikat abgelehnt …: still als Fehler der Abfrage.
      AReply.Error := FailureAfter(mWatch, ARequest.TimeoutMs);
    end;
  finally
    // Erst die Schnittstellen lösen, sie verweisen auf den Client.
    mResponse := nil;
    mAsync := nil;
    mSource.Free;
    mContent.Free;
    mClient.Free;
  end;
end;

{ TAtlasCiHttpTransports }
{ TAtlasCiHttpTransports }

function TAtlasCiHttpTransports.Basic(const AServer, AUser, AToken: string): IAtlasCiTransport;
begin
  Result := TAtlasCiHttpTransport.Create(AServer, AUser, AToken);
end;

function TAtlasCiHttpTransports.Bearer(const AServer, AToken: string): IAtlasCiTransport;
begin
  Result := TAtlasCiHttpTransport.CreateBearer(AServer, AToken);
end;

end.
