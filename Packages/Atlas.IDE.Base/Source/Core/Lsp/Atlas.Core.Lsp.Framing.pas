unit Atlas.Core.Lsp.Framing;

// Content-Length-Rahmung der LSP-Nachrichten des Plugins: Frame rahmt eine
// ausgehende Nachricht, der Leser sammelt empfangene Bytes (auch in
// beliebigen Stücken) und gibt vollständige Nachrichten der Reihe nach
// heraus. Abgetrennt vom Client (TLspClient), der Anfragen und Antworten
// zuordnet; der Client sperrt den Leser selbst (nicht threadsicher).
// Obergrenzen wie im Server: Ein Kopf ohne Ende in den ersten 8 KB oder ein
// Inhalt über 256 MB gibt ELspClientError, damit eine kaputte Verbindung nicht
// den Speicher füllt. Ein Kopf ohne gültiges Content-Length wird verworfen.

interface

uses
  System.SysUtils;

type
  ELspClientError = class(Exception);

  TLspFrameReader = class
  public const
    /// <summary>Obergrenzen der Rahmung wie im Server (Atlas.Common.JsonRpc.StreamTransport): Kopf 8 KB,
    /// Inhalt 256 MB. Darüber gilt die Verbindung als kaputt.</summary>
    cMaxHeaderLength = 8 * 1024;
    cMaxContentLength = 256 * 1024 * 1024;
  private
    FBuffer: TBytes;
  public
    /// <summary>Rahmt AText mit Content-Length.</summary>
    class function Frame(const AText: string): TBytes; static;
    /// <summary>Die ersten ACount Bytes von ABytes an den Puffer hängen.</summary>
    procedure Append(const ABytes: TBytes; ACount: Integer);
    /// <summary>Nimmt die nächste Nachricht aus dem Puffer. True, solange es weitergeht: mit AText, oder mit
    /// leerem AText, wenn ein kaputter Kopf verworfen wurde. False, wenn die Nachricht noch unvollständig ist.
    /// ELspClientError bei Kopf ohne Ende oder zu großem Inhalt (der Puffer ist dann leer).</summary>
    function TakeMessage(out AText: string): Boolean;
  end;

implementation

uses
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TFramingText = (ServerMessageWithoutEndOf, ServerMessageWithBytesExceeds);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TFramingText] of string = (
    ('Servernachricht ohne Kopfende',
     'Servernachricht mit %d Bytes über der Grenze von %d Bytes'),
    ('Server message without end of header',
     'Server message with %d bytes exceeds the limit of %d bytes'));

  cHeaderEnd: array[0..3] of Byte = (13, 10, 13, 10);
  // Kopfzeile mit der Länge des Inhalts (Protokoll, nicht übersetzen).
  cContentLength = 'Content-Length:';
  cFrameHeader = cContentLength + ' %d'#13#10#13#10;

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TFramingText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

/// <summary>Index des Kopfendes (CR LF CR LF) in den ersten MaxHeaderLength Bytes, -1 ohne.</summary>
function HeaderEndIndex(const ABuffer: TBytes): Integer;
var
  mIndex, mLast: Integer;
begin
  Result := -1;
  // Nur im möglichen Kopf suchen, nicht im ganzen Puffer.
  mLast := Length(ABuffer) - Length(cHeaderEnd);
  if mLast > TLspFrameReader.cMaxHeaderLength then
  begin
    mLast := TLspFrameReader.cMaxHeaderLength;
  end;
  mIndex := 0;
  while (Result < 0) and (mIndex <= mLast) do
  begin
    if CompareMem(@ABuffer[mIndex], @cHeaderEnd[0], Length(cHeaderEnd)) then
    begin
      Result := mIndex;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Kein Kopfende in den ersten MaxHeaderLength Bytes: kein LSP, Verbindung aufgeben statt den
/// Speicher zu füllen.</summary>
procedure RejectEndlessHeader(var ABuffer: TBytes);
begin
  if Length(ABuffer) >= TLspFrameReader.cMaxHeaderLength + Length(cHeaderEnd) then
  begin
    ABuffer := nil;
    raise ELspClientError.Create(UiText(TFramingText.ServerMessageWithoutEndOf));
  end;
end;

/// <summary>Nachricht über MaxContentLength: Verbindung aufgeben statt den Speicher zu füllen.</summary>
procedure RejectOversizedBody(var ABuffer: TBytes; ABodyLength: Integer);
begin
  if ABodyLength > TLspFrameReader.cMaxContentLength then
  begin
    ABuffer := nil;
    raise ELspClientError.CreateFmt(UiText(TFramingText.ServerMessageWithBytesExceeds),
      [ABodyLength, TLspFrameReader.cMaxContentLength]);
  end;
end;

/// <summary>Wert von Content-Length im Kopf, -1 ohne oder bei ungültiger Zahl.</summary>
function ContentLengthOf(const AHeader: string): Integer;
var
  mLine: string;
begin
  Result := -1;
  for mLine in AHeader.Split([#13#10]) do
  begin
    if mLine.StartsWith(cContentLength, True) then
    begin
      Result := StrToIntDef(mLine.Substring(Length(cContentLength)).Trim, -1);
    end;
  end;
end;

{ TLspFrameReader }

class function TLspFrameReader.Frame(const AText: string): TBytes;
var
  mBody: TBytes;
  mHeader: TBytes;
begin
  mBody := TEncoding.UTF8.GetBytes(AText);
  mHeader := TEncoding.UTF8.GetBytes(Format(cFrameHeader, [Length(mBody)]));
  Result := mHeader + mBody;
end;

procedure TLspFrameReader.Append(const ABytes: TBytes; ACount: Integer);
var
  mStart: Integer;
begin
  mStart := Length(FBuffer);
  SetLength(FBuffer, mStart + ACount);
  if ACount > 0 then
  begin
    Move(ABytes[0], FBuffer[mStart], ACount);
  end;
end;

function TLspFrameReader.TakeMessage(out AText: string): Boolean;
var
  mHeaderLength, mLen, mBodyLength: Integer;
begin
  Result := False;
  mHeaderLength := HeaderEndIndex(FBuffer);
  if mHeaderLength < 0 then
  begin
    RejectEndlessHeader(FBuffer);
    Exit;
  end;
  mBodyLength := ContentLengthOf(TEncoding.UTF8.GetString(FBuffer, 0, mHeaderLength));
  mLen := mHeaderLength + Length(cHeaderEnd);
  if mBodyLength < 0 then
  begin
    // Kaputter Kopf: verwerfen und weitermachen.
    Delete(FBuffer, 0, mLen);
    Exit(True);
  end;
  RejectOversizedBody(FBuffer, mBodyLength);
  if Length(FBuffer) >= mLen + mBodyLength then
  begin
    AText := TEncoding.UTF8.GetString(FBuffer, mLen, mBodyLength);
    Delete(FBuffer, 0, mLen + mBodyLength);
    Result := True;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Lsp.Framing', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
