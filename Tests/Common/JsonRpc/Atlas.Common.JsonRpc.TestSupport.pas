unit Atlas.Common.JsonRpc.TestSupport;

// Hilfsfunktionen für Tests der Protokollschicht: Nachrichten rahmen,
// Eingabestreams bauen und geschriebene Ausgabe wieder einlesen.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON;

type
  TJsonRpcTestSupport = record
  public
    /// <summary>Rahmt einen JSON-Text mit Content-Length-Header (Länge in UTF-8-Bytes).</summary>
    class function Frame(const AJson: string): TBytes; static;
    /// <summary>Eingabestream aus mehreren gerahmten Nachrichten.</summary>
    class function InputOf(const AJsonMessages: array of string): TBytesStream; static;
    /// <summary>Eingabestream aus rohem Text (ASCII/UTF-8), z. B. für fehlerhafte Header.</summary>
    class function RawInput(const AText: string): TBytesStream; static;
    /// <summary>Liest alle in AOutput geschriebenen Nachrichten. Der Aufrufer gibt die Liste frei.</summary>
    class function ReadMessages(AOutput: TBytesStream): TObjectList<TJSONObject>; static;
    /// <summary>Parst ein JSON-Objekt. Der Aufrufer gibt es frei.</summary>
    class function Parse(const AJson: string): TJSONObject; static;
  end;

implementation

uses
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.StreamTransport;

{ TJsonRpcTestSupport }

class function TJsonRpcTestSupport.Frame(const AJson: string): TBytes;
var
  mBody: TBytes;
begin
  mBody := TEncoding.UTF8.GetBytes(AJson);
  Result := TEncoding.ASCII.GetBytes(Format('Content-Length: %d'#13#10#13#10, [Length(mBody)])) + mBody;
end;

class function TJsonRpcTestSupport.InputOf(const AJsonMessages: array of string): TBytesStream;
var
  mData: TBytes;
  mJson: string;
begin
  mData := nil;
  for mJson in AJsonMessages do
  begin
    mData := mData + Frame(mJson);
  end;
  Result := TBytesStream.Create(mData);
end;

class function TJsonRpcTestSupport.RawInput(const AText: string): TBytesStream;
begin
  Result := TBytesStream.Create(TEncoding.UTF8.GetBytes(AText));
end;

class function TJsonRpcTestSupport.ReadMessages(AOutput: TBytesStream): TObjectList<TJSONObject>;
var
  mInput: TBytesStream;
  mTransport: IJsonRpcTransport;
begin
  Result := TObjectList<TJSONObject>.Create(True);
  mInput := TBytesStream.Create(Copy(AOutput.Bytes, 0, Integer(AOutput.Size)));
  try
    mTransport := TJsonRpcStreamTransport.Create(mInput, nil, False);
    try
      while True do
      begin
        Result.Add(mTransport.ReadMessage);
      end;
    except
      on EJsonRpcTransportClosed do
        ; // alle Nachrichten gelesen
    end;
    mTransport := nil;
  finally
    mInput.Free;
  end;
end;

class function TJsonRpcTestSupport.Parse(const AJson: string): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
end;

end.
