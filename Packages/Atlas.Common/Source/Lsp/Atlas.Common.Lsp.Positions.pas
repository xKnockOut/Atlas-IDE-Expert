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
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TPositionsText = (IsNotAnObject, FieldMissingOrNotA, FieldMissingIn);

const
  cTexts: array[TPositionsText] of TAtlasText = (
    (De: ' ist kein Objekt'; En: ' is not an object'),
    (De: 'Feld "%s" fehlt oder ist keine Zahl in '; En: 'Field "%s" missing or not a number in '),
    (De: 'Feld "%s" fehlt in '; En: 'Field "%s" missing in '));

{$SCOPEDENUMS OFF}

function ReadInteger(const AValue: TJSONValue; const AName, AContext: string): Integer;
begin
  if not (AValue is TJSONObject) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, AContext + cTexts[TPositionsText.IsNotAnObject].Text);
  end;
  if not TJSONObject(AValue).TryGetValue<Integer>(AName, Result) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TPositionsText.FieldMissingOrNotA].Fmt([AName]) + AContext);
  end;
end;

function ReadMember(const AValue: TJSONValue; const AName, AContext: string): TJSONValue;
begin
  Result := nil;
  if AValue is TJSONObject then
  begin
    Result := TJSONObject(AValue).GetValue(AName);
  end;
  if Result = nil then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TPositionsText.FieldMissingIn].Fmt([AName]) + AContext);
  end;
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Positions', cTexts);

end.
