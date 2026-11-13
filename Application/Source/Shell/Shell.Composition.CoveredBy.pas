unit Shell.Composition.CoveredBy;

// Anfrage atlas/coveredBy der Komposition (#1778): Tests je Methode einer Unit. Projektdateien, Testprogramme,
// Testunits und Optionen wie atlas/affectedTests; Tiefe und private Methoden aus der Anfrage, der Text der Unit aus
// der Anfrage (Puffer des Editors) oder wie jede andere Datei gelesen.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Lsp.CoveredBy,
  Shell.Composition.AffectedTests;

type
  /// <summary>Beantwortet atlas/coveredBy.</summary>
  TShellCoveredByRequest = class
  public
    /// <summary>Meldet die Anfrage nebenläufig am Verteiler an.</summary>
    class procedure Attach(ADispatcher: TJsonRpcDispatcher; const AServices: TShellAffectedTestsServices); static;
    class function Handle(const AServices: TShellAffectedTestsServices; const AParams: TJSONValue;
      const ACancellation: IJsonRpcCancellationToken): TJSONValue; static;
    /// <summary>Projektdateien, Testunits und Optionen zu AUri; Tiefe und private Methoden aus AParams.</summary>
    class function RequestFor(const AServices: TShellAffectedTestsServices; const AUri: string;
      AParams: TJSONObject): TCoveredRequest; static;
  end;

implementation

uses
  Atlas.Common.Documents.Uris,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.AffectedTests,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TCoveredByRequestText = (UriMissing, NotReadable);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TCoveredByRequestText] of TAtlasText = (
    (De: 'Feld "textDocument.uri" fehlt in %s'; En: 'Field "textDocument.uri" is missing in %s'),
    (De: '%s nicht lesbar'; En: '%s not readable'));

class procedure TShellCoveredByRequest.Attach(ADispatcher: TJsonRpcDispatcher;
  const AServices: TShellAffectedTestsServices);
var
  mServices: TShellAffectedTestsServices;
begin
  mServices := AServices;
  ADispatcher.RegisterConcurrentRequest(TCoveredBy.cMethod,
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    begin
      Result := Handle(mServices, AParams, ACancellation);
    end);
end;

class function TShellCoveredByRequest.RequestFor(const AServices: TShellAffectedTestsServices; const AUri: string;
  AParams: TJSONObject): TCoveredRequest;
var
  mAffected: TAffectedRequest;
  mDepth: Integer;
  mPrivate: Boolean;
begin
  // Dieselben Projektdateien, Testprogramme und Testunits wie die betroffenen Tests (#1353).
  mAffected := TShellAffectedTestsRequest.RequestFor(AServices, AUri, AServices.Settings.SettingsFor(AUri));
  Result := Default(TCoveredRequest);
  Result.Files := mAffected.Files;
  Result.Options := mAffected.Options;
  if not AParams.TryGetValue<Integer>('depth', mDepth) then
  begin
    mDepth := TCoveredBy.cDefaultDepth;
  end;
  Result.Options.Depth := mDepth;
  if not AParams.TryGetValue<Boolean>('includePrivate', mPrivate) then
  begin
    mPrivate := False;
  end;
  Result.IncludePrivate := mPrivate;
end;

class function TShellCoveredByRequest.Handle(const AServices: TShellAffectedTestsServices;
  const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mUri, mFileName, mText: string;
  mRequest: TCoveredRequest;
  mResolver: TNameResolver;
  mFound: TCoveredResult;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TCoveredByRequestText.UriMissing].Fmt([TCoveredBy.cMethod]));
  end;
  mFileName := TDocumentUris.ToPath(mUri);
  // Der Puffer des Editors kann ungespeichert sein: Die Zeilen der Marken passen nur zu seinem Text.
  if not TJSONObject(AParams).TryGetValue<string>('text', mText) and not AServices.ReadText(mFileName, mText) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cRequestFailed,
      cTexts[TCoveredByRequestText.NotReadable].Fmt([ExtractFileName(mFileName)]));
  end;
  mRequest := RequestFor(AServices, mUri, TJSONObject(AParams));
  mResolver := TNameResolver.Create(AServices.Index, AServices.EnsureUnit);
  try
    mResolver.Namespaces := AServices.Namespaces();
    mFound := TCoveredBy.Determine(mResolver, AServices.Index, mFileName, mText, mRequest, AServices.ReadText,
      ACancellation);
  finally
    mResolver.Free;
  end;
  Result := TCoveredBy.ToJson(mFound);
end;

initialization
  TAtlasTextTables.Add('Shell.Composition.CoveredBy', cTexts);

end.
