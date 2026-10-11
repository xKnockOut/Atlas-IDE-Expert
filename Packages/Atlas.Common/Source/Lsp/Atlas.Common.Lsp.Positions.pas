unit Atlas.Common.Lsp.Positions;

// Umwandlung zwischen den LSP-Typen Position und Range und den Typen der
// Dokumentverwaltung. Fehlende oder falsche Felder führen zu InvalidParams.

interface

uses
  System.JSON,
  Atlas.Common.Documents.Contract;

type
  TLspPositions = record
  public
    /// <summary>Liest {"line": n, "character": n}.</summary>
    class function ReadPosition(const AValue: TJSONValue): TTextPosition; static;
    /// <summary>Liest {"start": Position, "end": Position}.</summary>
    class function ReadRange(const AValue: TJSONValue): TTextRange; static;
    /// <summary>Der Aufrufer übernimmt das Objekt.</summary>
    class function PositionToJson(const APosition: TTextPosition): TJSONObject; static;
    /// <summary>Der Aufrufer übernimmt das Objekt.</summary>
    class function RangeToJson(const ARange: TTextRange): TJSONObject; static;
  end;

implementation

uses
  Atlas.Common.JsonRpc.Contract;

function ReadInteger(const AValue: TJSONValue; const AName, AContext: string): Integer;
begin
  if not (AValue is TJSONObject) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, AContext + ' ist kein Objekt');
  if not TJSONObject(AValue).TryGetValue<Integer>(AName, Result) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Feld "' + AName + '" fehlt oder ist keine Zahl in ' + AContext);
end;

function ReadMember(const AValue: TJSONValue; const AName, AContext: string): TJSONValue;
begin
  Result := nil;
  if AValue is TJSONObject then
    Result := TJSONObject(AValue).GetValue(AName);
  if Result = nil then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Feld "' + AName + '" fehlt in ' + AContext);
end;

{ TLspPositions }

class function TLspPositions.ReadPosition(const AValue: TJSONValue): TTextPosition;
begin
  Result := TTextPosition.Create(
    ReadInteger(AValue, 'line', 'Position'),
    ReadInteger(AValue, 'character', 'Position'));
end;

class function TLspPositions.ReadRange(const AValue: TJSONValue): TTextRange;
begin
  Result := TTextRange.Create(
    ReadPosition(ReadMember(AValue, 'start', 'Range')),
    ReadPosition(ReadMember(AValue, 'end', 'Range')));
end;

class function TLspPositions.PositionToJson(const APosition: TTextPosition): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('line', TJSONNumber.Create(APosition.Line));
  Result.AddPair('character', TJSONNumber.Create(APosition.Character));
end;

class function TLspPositions.RangeToJson(const ARange: TTextRange): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('start', PositionToJson(ARange.StartPos));
  Result.AddPair('end', PositionToJson(ARange.EndPos));
end;

end.
