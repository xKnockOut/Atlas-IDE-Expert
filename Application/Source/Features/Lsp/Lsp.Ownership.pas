unit Lsp.Ownership;

// Befehl atlas.server.ownership [uri] (#1877): „Wer gibt das frei?“ für jede Erzeugung T.Create(…) der Unit, für
// die Marke am Zeilenende im Plugin. Die Antwort rechnet der Host über ILspOwnershipReport (Prüfregeln, Anbieter
// Rules.Providers.OwnershipReport); ohne Anbieter ist sites leer.

interface

uses
  System.SysUtils,
  System.JSON,
  Lsp.Contract,
  Lsp.Commands;

type
  TLspOwnership = class
  public const
    cCommand = 'atlas.server.ownership';
  public
    /// <summary>Meldet den Befehl an (nebenläufig: liest nur).</summary>
    class procedure Attach(ACommands: TLspCommands; const AReport: ILspOwnershipReport); static;
    /// <summary>atlas.server.ownership [uri]; EJsonRpcError ohne URI.</summary>
    class function Execute(const AArguments: TJSONArray; const AReport: ILspOwnershipReport): TJSONValue; static;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspOwnershipText = (NeedsUri);

const
  cTexts: array[TLspOwnershipText] of TAtlasText = (
    (De: '%s braucht die URI der Unit'; En: '%s needs the URI of the unit'));

{$SCOPEDENUMS OFF}

{ TLspOwnership }

class procedure TLspOwnership.Attach(ACommands: TLspCommands; const AReport: ILspOwnershipReport);
var
  mReport: ILspOwnershipReport;
begin
  mReport := AReport;
  ACommands.RegisterConcurrent(cCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := TLspOwnership.Execute(AArguments, mReport);
    end);
end;

class function TLspOwnership.Execute(const AArguments: TJSONArray; const AReport: ILspOwnershipReport): TJSONValue;
var
  mUri: string;
  mAnswer: TJSONObject;
begin
  if (AArguments = nil) or (AArguments.Count = 0) or not (AArguments.Items[0] is TJSONString) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TLspOwnershipText.NeedsUri].Fmt([TLspOwnership.cCommand]));
  end;
  mUri := AArguments.Items[0].Value;
  if AReport <> nil then
  begin
    Exit(AReport.Report(mUri));
  end;
  mAnswer := TJSONObject.Create;
  mAnswer.AddPair('uri', mUri);
  mAnswer.AddPair('sites', TJSONArray.Create);
  Result := mAnswer;
end;

end.
