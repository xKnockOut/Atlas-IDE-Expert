unit Atlas.Core.AiProviders.Adapters.Http;

// HTTPS für die KI-Anbieter (#1922) über THTTPClient, aus einem
// Hintergrund-Thread. Wie die Abfragen des Build-Servers: asynchron, beendet
// beim Abbruchsignal des Plugins (TAtlasShutdown), bei Cancel oder nach der
// Zeitgrenze; Client und Streams werden erst nach dem Ende einer abgebrochenen
// Anfrage freigegeben (TAtlasAsyncWait.AwaitSettled). Die Antwort liest ein
// Stream mit Größengrenze.
// Keine Cookies und keine Weiterleitungen: Der Schlüssel geht nur an die
// eingetragene Adresse. Weder Adresse noch Köpfe kommen ins Protokoll.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Net.URLClient,
  System.Net.HttpClient,
  Atlas.Core.Diagnostics.BoundedStream,
  Atlas.Core.AiProviders.Contract;

type
  TAtlasAiHttpClient = class(TInterfacedObject, IAtlasAiHttp)
  public const
    /// <summary>Größte Antwort; Vorschläge und Zusammenfassungen sind klein.</summary>
    cMaxBytes = 2 * 1024 * 1024;
  private type
    /// <summary>Client und Streams einer Anfrage; gehören Send.</summary>
    TExchange = record
      Client: THTTPClient;
      Source: TStream;
      Content: TAtlasBoundedStream;
    end;
  private
    FCancelled: Integer;
    function Cancelled: Boolean;
    function Run(const AExchange: TExchange; const AMethod, AUrl: string; const AHeaders: TNetHeaders;
      ATimeoutMs: Integer): TAtlasAiHttpReply;
  public
    function Send(const AMethod, AUrl: string; const AHeaders: TArray<TAtlasAiHeader>; const ABody: string;
      ATimeoutMs: Integer): TAtlasAiHttpReply;
    procedure Cancel;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Diagnostics.Deadline,
  Atlas.Core.Diagnostics.AsyncWait;

{ TAtlasAiHttpClient }

function TAtlasAiHttpClient.Cancelled: Boolean;
begin
  Result := AtomicCmpExchange(FCancelled, 0, 0) <> 0;
end;

procedure TAtlasAiHttpClient.Cancel;
begin
  AtomicExchange(FCancelled, 1);
end;

/// <summary>Köpfe für THTTPClient.</summary>
function NetHeadersOf(const AHeaders: TArray<TAtlasAiHeader>): TNetHeaders;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AHeaders));
  for mIndex := 0 to High(AHeaders) do
  begin
    Result[mIndex] := TNetHeader.Create(AHeaders[mIndex].Name, AHeaders[mIndex].Value);
  end;
end;

/// <summary>Fehler nach dem Ende des Wartens.</summary>
function FailureOf(AEnd: TAtlasAsyncEnd): TAtlasAiError;
begin
  if AEnd = TAtlasAsyncEnd.Timeout then
  begin
    Result := TAtlasAiError.Timeout;
  end
  else
  begin
    Result := TAtlasAiError.Cancelled;
  end;
end;

function TAtlasAiHttpClient.Run(const AExchange: TExchange; const AMethod, AUrl: string;
  const AHeaders: TNetHeaders; ATimeoutMs: Integer): TAtlasAiHttpReply;
var
  mAsync: IAsyncResult;
  mResponse: IHTTPResponse;
  mDeadline: TAtlasDeadline;
  mEnd: TAtlasAsyncEnd;
begin
  Result := Default(TAtlasAiHttpReply);
  mDeadline := TAtlasDeadline.After(Cardinal(Max(ATimeoutMs, 0)));
  try
    if SameText(AMethod, 'POST') then
    begin
      mAsync := AExchange.Client.BeginPost(AUrl, AExchange.Source, AExchange.Content, AHeaders);
    end
    else
    begin
      mAsync := AExchange.Client.BeginGet(AUrl, AExchange.Content, AHeaders);
    end;
    // Bei einem Abbruch erst nach dem Ende der Anfrage zurück: Bis dahin benutzt der Task der RTL Client und Streams.
    mEnd := TAtlasAsyncWait.AwaitSettled(
      function: Boolean
      begin
        Result := mAsync.IsCompleted;
      end,
      procedure
      begin
        mAsync.Cancel;
      end, mDeadline,
      function: Boolean
      begin
        Result := Cancelled;
      end);
    if mEnd <> TAtlasAsyncEnd.Done then
    begin
      Result.Failure := FailureOf(mEnd);
      Exit;
    end;
    mResponse := THTTPClient.EndAsyncHTTP(mAsync);
    Result.Status := mResponse.StatusCode;
    Result.Body := TEncoding.UTF8.GetString(AExchange.Content.Bytes, 0, AExchange.Content.Size);
  except
    // Kein Netz, Name unbekannt, Zertifikat abgelehnt, Antwort zu groß …: still als Fehler der Anfrage.
    Result.Status := 0;
    Result.Failure := TAtlasAiError.Unreachable;
    if AExchange.Content.Exceeded then
    begin
      Result.Failure := TAtlasAiError.BadAnswer;
    end
    else if mDeadline.Reached then
    begin
      Result.Failure := TAtlasAiError.Timeout;
    end;
  end;
  // Erst die Schnittstellen lösen, sie verweisen auf den Client.
  mResponse := nil;
  mAsync := nil;
end;

function TAtlasAiHttpClient.Send(const AMethod, AUrl: string; const AHeaders: TArray<TAtlasAiHeader>;
  const ABody: string; ATimeoutMs: Integer): TAtlasAiHttpReply;
var
  mExchange: TExchange;
begin
  Result := Default(TAtlasAiHttpReply);
  if Cancelled then
  begin
    Result.Failure := TAtlasAiError.Cancelled;
    Exit;
  end;
  mExchange.Client := THTTPClient.Create;
  mExchange.Content := TAtlasBoundedStream.Create(cMaxBytes);
  mExchange.Source := TBytesStream.Create(TEncoding.UTF8.GetBytes(ABody));
  try
    // Kurz: Ein Abbruch während des Verbindungsaufbaus wirkt erst, wenn dieser endet.
    mExchange.Client.ConnectionTimeout := TAtlasAsyncWait.ConnectTimeout(ATimeoutMs);
    mExchange.Client.ResponseTimeout := ATimeoutMs;
    mExchange.Client.HandleRedirects := False;
    mExchange.Client.AllowCookies := False;
    mExchange.Client.UserAgent := 'Atlas';
    mExchange.Client.Accept := 'application/json';
    Result := Run(mExchange, AMethod, AUrl, NetHeadersOf(AHeaders), ATimeoutMs);
  finally
    mExchange.Source.Free;
    mExchange.Content.Free;
    mExchange.Client.Free;
  end;
end;

end.
