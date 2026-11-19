unit Atlas.Common.JsonRpc.CustomCancellation;

// Abbruchsignal mit eigenem Grund: Wer eine Frist oder ein eigenes Abbruchkriterium
// an eine Anfrage hängen will, beschreibt nur den Grund; das Token dazu baut dieses
// Feature. So implementiert kein anderes Feature IJsonRpcCancellationToken selbst.

interface

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract;

type
  /// <summary>Grund des Abbruchs: '' heißt weiter; sonst der Text der Ausnahme, die
  /// ThrowIfCancellationRequested mit AClass auslöst.</summary>
  TJsonRpcCancelReason = reference to function(out AClass: ExceptClass): string;

  TJsonRpcCancellations = record
  public
    /// <summary>Token, das abbricht, wenn AInner (darf nil sein) abbricht oder AReason einen Grund
    /// nennt. AInner geht vor.</summary>
    class function WithReason(const AInner: IJsonRpcCancellationToken;
      const AReason: TJsonRpcCancelReason): IJsonRpcCancellationToken; static;
  end;

implementation

type
  TReasonCancellation = class(TInterfacedObject, IJsonRpcCancellationToken)
  private
    FInner: IJsonRpcCancellationToken;
    FReason: TJsonRpcCancelReason;
  public
    constructor Create(const AInner: IJsonRpcCancellationToken; const AReason: TJsonRpcCancelReason);
    function IsCancellationRequested: Boolean;
    procedure ThrowIfCancellationRequested;
  end;

{ TReasonCancellation }

constructor TReasonCancellation.Create(const AInner: IJsonRpcCancellationToken;
  const AReason: TJsonRpcCancelReason);
begin
  inherited Create;
  FInner := AInner;
  FReason := AReason;
end;

function TReasonCancellation.IsCancellationRequested: Boolean;
var
  mClass: ExceptClass;
begin
  Result := (FInner <> nil) and FInner.IsCancellationRequested;
  if not Result then
  begin
    Result := FReason(mClass) <> '';
  end;
end;

procedure TReasonCancellation.ThrowIfCancellationRequested;
var
  mClass: ExceptClass;
  mText: string;
begin
  if FInner <> nil then
  begin
    FInner.ThrowIfCancellationRequested;
  end;
  mText := FReason(mClass);
  if mText <> '' then
  begin
    raise mClass.Create(mText);
  end;
end;

{ TJsonRpcCancellations }

class function TJsonRpcCancellations.WithReason(const AInner: IJsonRpcCancellationToken;
  const AReason: TJsonRpcCancelReason): IJsonRpcCancellationToken;
begin
  Result := TReasonCancellation.Create(AInner, AReason);
end;

end.
