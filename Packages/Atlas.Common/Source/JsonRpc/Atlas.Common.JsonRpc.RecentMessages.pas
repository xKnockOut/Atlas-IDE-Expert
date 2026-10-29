unit Atlas.Common.JsonRpc.RecentMessages;

// Die letzten Nachrichten des Clients für Absturzfälle (#1355). Der Dispatcher
// trägt jede eingehende Nachricht ein; ein Fall zeigt die letzten ReportCount
// davon, gekürzt: Zeichenketten über MaxString Zeichen (etwa der ganze Text in
// didOpen und didChange) werden abgeschnitten; ab MaxMessage Zeichen steht für
// die übrigen Werte ein Platzhalter „…“, sodass jede Nachricht gültiges JSON
// bleibt. Zusätzlich bleiben Methode und volle Parameter der letzten
// Capacity Anfragen (mit id) abrufbar, damit ein Abbruch durch den Watchdog
// die Parameter seiner Anfrage findet. Kürzen und Eintragen kosten je
// Nachricht einen Lauf über das JSON ohne Kopie der langen Texte.
// Threadsicher: Eintragen im Thread der Nachrichtenschleife, Lesen aus
// Worker-Threads und dem Watchdog.

interface

uses
  System.SysUtils,
  System.JSON;

type
  IJsonRpcRecentMessages = interface
    ['{4B1E6D38-7A92-4C05-B3F1-9E2D8C5A7016}']
    /// <summary>Trägt eine eingehende Nachricht ein; AMessage bleibt beim Aufrufer.</summary>
    procedure Add(const AMessage: TJSONObject);
    /// <summary>Die letzten ACount Nachrichten, gekürzt, älteste zuerst.</summary>
    function Last(ACount: Integer): TArray<string>;
    /// <summary>Methode und volle Parameter (JSON, '' ohne) der Anfrage mit der id AId (JSON-Text der id);
    /// False, wenn sie nicht mehr unter den letzten Anfragen ist.</summary>
    function FindRequest(const AId: string; out AMethod, AParams: string): Boolean;
  end;

  TJsonRpcRecentMessages = class(TInterfacedObject, IJsonRpcRecentMessages)
  public const
    /// <summary>So viele Nachrichten und Anfragen bleiben gespeichert.</summary>
    Capacity = 64;
    /// <summary>So viele Nachrichten nennt ein Absturzfall.</summary>
    ReportCount = 20;
    /// <summary>Längere Zeichenketten werden gekürzt.</summary>
    MaxString = 200;
    /// <summary>Ab so vielen Zeichen ersetzt ein Platzhalter die übrigen Werte.</summary>
    MaxMessage = 2000;
    /// <summary>Volle Parameter einer Anfrage höchstens so lang (sonst gekürzt wie im Bericht).</summary>
    MaxParams = 65536;
  private type
    TRequest = record
      Id: string;
      Method: string;
      Params: string;
    end;
  private
    FLock: TObject;
    FMessages: array[0..Capacity - 1] of string;
    FMessageCount: Integer;
    FMessageNext: Integer;
    FRequests: array[0..Capacity - 1] of TRequest;
    FRequestNext: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AMessage: TJSONObject);
    function Last(ACount: Integer): TArray<string>;
    function FindRequest(const AId: string; out AMethod, AParams: string): Boolean;
    /// <summary>AValue als kompaktes JSON, Zeichenketten über AMaxString Zeichen gekürzt
    /// („…“ und die volle Länge); ab AMaxLength Zeichen ersetzt „…“ die übrigen Werte jedes Objekts und
    /// Arrays. Bleibt gültiges JSON.</summary>
    class function Shortened(const AValue: TJSONValue; AMaxString, AMaxLength: Integer): string; static;
  end;

implementation

const
  /// <summary>Platzhalter für die übrigen Werte eines Arrays bzw. Objekts über der Grenze.</summary>
  cRest = '"…"';
  cRestPair = '"…":null';

function ShortenedText(const AText: string; AMaxString: Integer): string;
var
  mValue: TJSONString;
begin
  if Length(AText) > AMaxString then
    mValue := TJSONString.Create(Copy(AText, 1, AMaxString) + Format('… (%d Zeichen)', [Length(AText)]))
  else
    mValue := TJSONString.Create(AText);
  try
    Result := mValue.ToJSON;
  finally
    mValue.Free;
  end;
end;

procedure WriteShort(const AValue: TJSONValue; AMaxString: Integer; const AOut: TStringBuilder;
  AMaxLength: Integer);
var
  mIndex: Integer;
  mObject: TJSONObject;
  mArray: TJSONArray;
begin
  if AValue = nil then
    AOut.Append('null')
  // TJSONNumber erbt von TJSONString: Zahlen zuerst, sonst würden sie zu Zeichenketten.
  else if AValue is TJSONNumber then
    AOut.Append(AValue.ToJSON)
  else if AValue is TJSONString then
    AOut.Append(ShortenedText(TJSONString(AValue).Value, AMaxString))
  else if AValue is TJSONObject then
  begin
    mObject := TJSONObject(AValue);
    AOut.Append('{');
    for mIndex := 0 to mObject.Count - 1 do
    begin
      if mIndex > 0 then
        AOut.Append(',');
      // Über der Grenze: ein Platzhalter für den Rest, damit das Ergebnis gültiges JSON bleibt.
      if AOut.Length > AMaxLength then
      begin
        AOut.Append(cRestPair);
        Break;
      end;
      AOut.Append(ShortenedText(mObject.Pairs[mIndex].JsonString.Value, AMaxString));
      AOut.Append(':');
      WriteShort(mObject.Pairs[mIndex].JsonValue, AMaxString, AOut, AMaxLength);
    end;
    AOut.Append('}');
  end
  else if AValue is TJSONArray then
  begin
    mArray := TJSONArray(AValue);
    AOut.Append('[');
    for mIndex := 0 to mArray.Count - 1 do
    begin
      if mIndex > 0 then
        AOut.Append(',');
      if AOut.Length > AMaxLength then
      begin
        AOut.Append(cRest);
        Break;
      end;
      WriteShort(mArray.Items[mIndex], AMaxString, AOut, AMaxLength);
    end;
    AOut.Append(']');
  end
  else
    AOut.Append(AValue.ToJSON);
end;

{ TJsonRpcRecentMessages }

constructor TJsonRpcRecentMessages.Create;
begin
  inherited Create;
  FLock := TObject.Create;
end;

destructor TJsonRpcRecentMessages.Destroy;
begin
  FLock.Free;
  inherited;
end;

class function TJsonRpcRecentMessages.Shortened(const AValue: TJSONValue; AMaxString, AMaxLength: Integer): string;
var
  mOut: TStringBuilder;
begin
  mOut := TStringBuilder.Create;
  try
    WriteShort(AValue, AMaxString, mOut, AMaxLength);
    Result := mOut.ToString;
  finally
    mOut.Free;
  end;
end;

procedure TJsonRpcRecentMessages.Add(const AMessage: TJSONObject);
var
  mText, mId, mMethod, mParams: string;
  mIdValue, mMethodValue, mParamsValue: TJSONValue;
  mIsRequest: Boolean;
begin
  if AMessage = nil then
    Exit;
  mText := Shortened(AMessage, MaxString, MaxMessage);
  mIdValue := AMessage.GetValue('id');
  mMethodValue := AMessage.GetValue('method');
  mIsRequest := (mIdValue <> nil) and (mMethodValue is TJSONString);
  mId := '';
  mMethod := '';
  mParams := '';
  if mIsRequest then
  begin
    mId := mIdValue.ToJSON;
    mMethod := mMethodValue.Value;
    mParamsValue := AMessage.GetValue('params');
    if mParamsValue <> nil then
    begin
      mParams := mParamsValue.ToJSON;
      if Length(mParams) > MaxParams then
        mParams := Shortened(mParamsValue, MaxString, MaxParams);
    end;
  end;
  System.TMonitor.Enter(FLock);
  try
    FMessages[FMessageNext] := mText;
    FMessageNext := (FMessageNext + 1) mod Capacity;
    if FMessageCount < Capacity then
      Inc(FMessageCount);
    if mIsRequest then
    begin
      FRequests[FRequestNext].Id := mId;
      FRequests[FRequestNext].Method := mMethod;
      FRequests[FRequestNext].Params := mParams;
      FRequestNext := (FRequestNext + 1) mod Capacity;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TJsonRpcRecentMessages.Last(ACount: Integer): TArray<string>;
var
  mCount, mIndex, mStart: Integer;
begin
  Result := nil;
  System.TMonitor.Enter(FLock);
  try
    mCount := ACount;
    if mCount > FMessageCount then
      mCount := FMessageCount;
    if mCount <= 0 then
      Exit;
    SetLength(Result, mCount);
    mStart := (FMessageNext - mCount + Capacity) mod Capacity;
    for mIndex := 0 to mCount - 1 do
      Result[mIndex] := FMessages[(mStart + mIndex) mod Capacity];
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TJsonRpcRecentMessages.FindRequest(const AId: string; out AMethod, AParams: string): Boolean;
var
  mStep, mIndex: Integer;
begin
  AMethod := '';
  AParams := '';
  Result := False;
  if AId = '' then
    Exit;
  System.TMonitor.Enter(FLock);
  try
    // Die jüngste Anfrage mit dieser id zuerst: Clients vergeben ids nach einem Neustart neu.
    for mStep := 1 to Capacity do
    begin
      mIndex := (FRequestNext - mStep + Capacity) mod Capacity;
      if FRequests[mIndex].Id = AId then
      begin
        AMethod := FRequests[mIndex].Method;
        AParams := FRequests[mIndex].Params;
        Exit(True);
      end;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

end.
