unit Atlas.Common.Semantics.SymbolPath.Request;

// Anfrage der Pfadsuche (#1117) aus JSON: from, to, via, maxSteps und all, wie
// sie atlas/symbolPath (Atlas.Common.Lsp.SymbolPath) und das MCP-Werkzeug
// find_path übergeben. Ungültige Werte lehnt EJsonRpcError mit
// cInvalidParams ab.

interface

uses
  System.JSON,
  Atlas.Common.Semantics.SymbolPath.Search;

type
  TSymbolPathRequests = class
  public
    /// <summary>from, to, via, maxSteps und all aus AParams; EJsonRpcError bei ungültigen Werten.</summary>
    class function Read(const AParams: TJSONObject): TSymbolPathRequest; static;
  end;

implementation

uses
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Localization.Texts,
  Atlas.Text.Json;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TSymbolPathRequestText = (ViaKnowsUsesInheritsImplements, MaxStepsLiesBetween1And, FromAndToAreRequired);

const
  cTexts: array[TSymbolPathRequestText] of TAtlasText = (
    (De: '"via" kennt uses, inherits, implements, hasField, parameter, result, calls, contains und library';
     En: '"via" knows uses, inherits, implements, hasField, parameter, result, calls, contains and library'),
    (De: '"maxSteps" liegt zwischen 1 und %d'; En: '"maxSteps" lies between 1 and %d'),
    (De: '"from" und "to" sind nötig'; En: '"from" and "to" are required'));

{$SCOPEDENUMS OFF}

procedure ReadVia(AValue: TJSONArray; var ARequest: TSymbolPathRequest);
var
  mItem: TJSONValue;
  mKind: TSymbolPathEdgeKind;
  mLibrary: Boolean;
begin
  ARequest.Via := [];
  for mItem in AValue do
  begin
    if not (mItem is TJSONString) or not TSymbolPathSearch.TryParseEdge(mItem.Value, mKind, mLibrary) then
    begin
      raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
        cTexts[TSymbolPathRequestText.ViaKnowsUsesInheritsImplements].Text);
    end;
    if mLibrary then
    begin
      ARequest.ThroughLibrary := True;
    end
    else
    begin
      Include(ARequest.Via, mKind);
    end;
  end;
  // Nur "library": alle Kantenarten, Bibliothek als Durchgang.
  if ARequest.Via = [] then
  begin
    ARequest.Via := cAllSymbolPathEdges;
  end;
end;

/// <summary>"maxSteps" zwischen 1 und TSymbolPathRequest.cMaxStepsLimit.</summary>
function ReadMaxSteps(AValue: TJSONNumber): Integer;
begin
  Result := AValue.AsInt;
  if (Result < 1) or (Result > TSymbolPathRequest.cMaxStepsLimit) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TSymbolPathRequestText.MaxStepsLiesBetween1And].Fmt([TSymbolPathRequest.cMaxStepsLimit]));
  end;
end;

{ TSymbolPathRequests }

class function TSymbolPathRequests.Read(const AParams: TJSONObject): TSymbolPathRequest;
var
  mValue: TJSONValue;
begin
  Result := TSymbolPathRequest.Default;
  Result.From := TJsonRead.TrimmedText(AParams, 'from');
  Result.To_ := TJsonRead.TrimmedText(AParams, 'to');
  if (Result.From = '') or (Result.To_ = '') then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TSymbolPathRequestText.FromAndToAreRequired].Text);
  end;
  mValue := TJsonRead.Value(AParams, 'via');
  if mValue is TJSONArray then
  begin
    ReadVia(TJSONArray(mValue), Result);
  end;
  mValue := TJsonRead.Value(AParams, 'maxSteps');
  if mValue is TJSONNumber then
  begin
    Result.MaxSteps := ReadMaxSteps(TJSONNumber(mValue));
  end;
  mValue := TJsonRead.Value(AParams, 'all');
  if mValue is TJSONBool then
  begin
    Result.All := TJSONBool(mValue).AsBoolean;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Semantics.SymbolPath.Request', cTexts);

end.
