unit Atlas.Common.Editing.BoundaryCases.Protocol;

// Grenzfälle als Testfälle (#2173) für das Plugin. Logik und Bericht in Atlas.Common.Editing.BoundaryCases(.Report);
// den Text (offenes Dokument vor der Platte) liefert die Shell.
//
// Befehl atlas.server.boundaryCases [uri, zeile, max?]: zeile 0-basiert irgendwo in der Routine (bei
// verschachtelten gewinnt die innerste), max 1 bis 200 (Vorgabe 20).
// Antwort: null ohne Routine mit Rumpf an der Zeile, sonst
//   { uri, routine, resultType, line, truncated,
//     parameters: [{name, type, kind, neutral}],     kind: unknown, text, ordinal, float, logical, enum, reference
//     cases: [{parameter, value, reason, line, testCase, values: [..]}] }
// line der Fälle 0-basiert, -1 ohne eigene Bedingung; testCase False, wenn der Wert nicht in ein [TestCase]
// passt (nil eines Objekts oder Interfaces); values sind die Werte aller Parameter für den Fall.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract;

type
  TBoundaryCasesProtocol = class
  public const
    cCommand = 'atlas.server.boundaryCases';
  public
    /// <summary>Befehl mit dem Text des Dokuments AArguments[0].</summary>
    class function Execute(const AArguments: TJSONArray; const AReadText: TDocumentReadText): TJSONValue; static;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.Math,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Editing.BoundaryCases.Report,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  TBoundaryCasesProtocolText = (NeedsUriAndLine, NotReadable);

const
  cTexts: array[TBoundaryCasesProtocolText] of TAtlasText = (
    (De: '%s braucht URI und Zeile'; En: '%s needs a URI and a line'),
    (De: '%s ist nicht lesbar'; En: '%s cannot be read'));

{$SCOPEDENUMS OFF}

{ TBoundaryCasesProtocol }

/// <summary>Höchstzahl aus AArguments[2]; Vorgabe ohne Angabe.</summary>
function MaxOf(const AArguments: TJSONArray): Integer;
begin
  Result := TBoundaryCaseReports.cDefaultMax;
  if (AArguments.Count > 2) and (AArguments.Items[2] is TJSONNumber) then
  begin
    Result := EnsureRange(TJSONNumber(AArguments.Items[2]).AsInt, TBoundaryCaseReports.cMinMax,
      TBoundaryCaseReports.cMaxMax);
  end;
end;

class function TBoundaryCasesProtocol.Execute(const AArguments: TJSONArray;
  const AReadText: TDocumentReadText): TJSONValue;
var
  mUri, mText: string;
begin
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[0] is TJSONString) or
    not (AArguments.Items[1] is TJSONNumber) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TBoundaryCasesProtocolText.NeedsUriAndLine].Fmt([cCommand]));
  end;
  mUri := AArguments.Items[0].Value;
  if not AReadText(mUri, mText) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TBoundaryCasesProtocolText.NotReadable].Fmt([mUri]));
  end;
  Result := TBoundaryCaseReports.JsonAt(mText, mUri, Max(0, TJSONNumber(AArguments.Items[1]).AsInt),
    MaxOf(AArguments));
  if Result = nil then
  begin
    Result := TJSONNull.Create;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.BoundaryCases.Protocol', cTexts);

end.
