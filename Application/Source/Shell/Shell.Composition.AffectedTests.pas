unit Shell.Composition.AffectedTests;

// Anfrage atlas/affectedTests der Komposition: Arbeitsordner und Vergleichsbasis aus der Anfrage, Projektdateien,
// Testprogramme und Optionen wie atlas/impact, Analyse über git bzw. svn.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Lsp.TestUnits,
  Atlas.Common.Lsp.AffectedTests,
  Shell.AffectedTests,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings;

type
  TShellAffectedNamesFunc = reference to function: TArray<string>;
  TShellAffectedTestUnitFunc = reference to function(const AUri: string; out AContext: TTestUnitContext): Boolean;
  TShellAffectedImpactFunc = reference to function(const AUri: string): TImpactOptions;

  /// <summary>Was atlas/affectedTests von der Komposition braucht.</summary>
  TShellAffectedTestsServices = record
    Workspaces: TShellWorkspaceRegistry;
    Settings: TShellSettings;
    Index: ISymbolIndex;
    EnsureUnit: TEnsureUnitFunc;
    /// <summary>Namensräume der Projekte für die Namensauflösung.</summary>
    Namespaces: TShellAffectedNamesFunc;
    /// <summary>Text mit ungespeicherten Puffern des Editors.</summary>
    ReadText: TReferenceReadText;
    ProjectFiles: TShellAffectedNamesFunc;
    TestUnitContext: TShellAffectedTestUnitFunc;
    /// <summary>Treffersicherheit und Zeitlimit wie atlas/impact.</summary>
    ImpactOptions: TShellAffectedImpactFunc;
  end;

  /// <summary>Beantwortet atlas/affectedTests.</summary>
  TShellAffectedTestsRequest = class
  public
    /// <summary>Meldet die Anfrage nebenläufig am Verteiler an.</summary>
    class procedure Attach(ADispatcher: TJsonRpcDispatcher; const AServices: TShellAffectedTestsServices); static;
    class function Handle(const AServices: TShellAffectedTestsServices; const AParams: TJSONValue;
      const ACancellation: IJsonRpcCancellationToken): TJSONValue; static;
    /// <summary>Arbeitsordner des Arbeitsbereichs zu AUri und Vergleichsbasis, Ungespeichertes und Tiefe aus der
    /// Anfrage; ohne Arbeitsbereich ein Fehler der Anfrage.</summary>
    class function QueryFor(const AServices: TShellAffectedTestsServices; AParams: TJSONObject;
      const AUri: string): TShellAffectedQuery; static;
    /// <summary>Projektdateien, Testprogramme (auch das der Testunit zu AUri) und Optionen samt Testunits.</summary>
    class function RequestFor(const AServices: TShellAffectedTestsServices; const AUri: string;
      const ASettings: TServerSettings): TAffectedRequest; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Semantics.NameResolver,
  Shell.Bootstrap,
  Shell.Platform,
  Shell.VersionControlChanges,
  Shell.Workspace,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TAffectedRequestText = (UriMissing, NoWorkspace);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAffectedRequestText] of TAtlasText = (
    (De: 'Feld "textDocument.uri" fehlt in %s'; En: 'Field "textDocument.uri" is missing in %s'),
    (De: 'Kein Arbeitsbereich zu %s'; En: 'No workspace for %s'));

/// <summary>Text auf der Platte, ohne ungespeicherte Puffer des Editors.</summary>
function DiskSourceText(const AFileName: string; out AText: string): Boolean;
begin
  Result := TShellBootstrap.ReadSourceText(AFileName, AText);
end;

class procedure TShellAffectedTestsRequest.Attach(ADispatcher: TJsonRpcDispatcher;
  const AServices: TShellAffectedTestsServices);
var
  mServices: TShellAffectedTestsServices;
begin
  mServices := AServices;
  ADispatcher.RegisterConcurrentRequest(TAffectedTests.cMethod,
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    begin
      Result := Handle(mServices, AParams, ACancellation);
    end);
end;

class function TShellAffectedTestsRequest.Handle(const AServices: TShellAffectedTestsServices;
  const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mUri: string;
  mSettings: TServerSettings;
  mQuery: TShellAffectedQuery;
  mRequest: TAffectedRequest;
  mResolver: TNameResolver;
  mProcess: ICompilerProcess;
  mFound: TAffectedResult;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TAffectedRequestText.UriMissing].Fmt([TAffectedTests.cMethod]));
  end;
  mSettings := AServices.Settings.SettingsFor(mUri);
  mQuery := QueryFor(AServices, TJSONObject(AParams), mUri);
  mRequest := RequestFor(AServices, mUri, mSettings);
  mResolver := TNameResolver.Create(AServices.Index, AServices.EnsureUnit);
  try
    mResolver.Namespaces := AServices.Namespaces();
    try
      // Eigener Prozessstarter: git/svn laufen neben einem Compilerlauf. Über eine Variable: nie ein frisches
      // Objekt an einen const-Interface-Parameter.
      mProcess := TProcessRunner.Create;
      // git bzw. svn vergleichen die gespeicherten Dateien: Die geänderten Zeilen passen nur zum Text auf der
      // Platte, nicht zu einem ungespeicherten Puffer im Editor.
      mFound := TShellAffectedTests.Run(mProcess, mSettings, mQuery,
        TShellAffectedSources.New(mResolver, AServices.Index, DiskSourceText), mRequest, ACancellation);
    except
      on E: EAffectedTestsOff do
        raise EJsonRpcError.Create(TJsonRpcErrorCode.cRequestFailed, E.Message);
      on E: EVcsChanges do
        raise EJsonRpcError.Create(TJsonRpcErrorCode.cRequestFailed, E.Message);
    end;
  finally
    mResolver.Free;
  end;
  Result := TAffectedTests.ToJson(mFound);
end;

class function TShellAffectedTestsRequest.QueryFor(const AServices: TShellAffectedTestsServices;
  AParams: TJSONObject; const AUri: string): TShellAffectedQuery;
var
  mWorkspace: TShellWorkspace;
begin
  Result := Default(TShellAffectedQuery);
  System.TMonitor.Enter(AServices.Workspaces.Lock);
  try
    mWorkspace := AServices.Workspaces.Pick(TDocumentUris.ToPath(AUri));
    if mWorkspace = nil then
    begin
      raise EJsonRpcError.Create(TJsonRpcErrorCode.cRequestFailed,
        cTexts[TAffectedRequestText.NoWorkspace].Fmt([AUri]));
    end;
    Result.WorkingDir := mWorkspace.Root;
  finally
    System.TMonitor.Exit(AServices.Workspaces.Lock);
  end;
  if not AParams.TryGetValue<string>('base', Result.Base) then
  begin
    Result.Base := '';
  end;
  if not AParams.TryGetValue<Boolean>('includeUncommitted', Result.IncludeUncommitted) then
  begin
    Result.IncludeUncommitted := True;
  end;
  if not AParams.TryGetValue<Integer>('depth', Result.Depth) then
  begin
    Result.Depth := 0;
  end;
end;

class function TShellAffectedTestsRequest.RequestFor(const AServices: TShellAffectedTestsServices;
  const AUri: string; const ASettings: TServerSettings): TAffectedRequest;
var
  mContext: TTestUnitContext;
begin
  Result := Default(TAffectedRequest);
  Result.Files := AServices.ProjectFiles();
  Result.TestPrograms := TShellAffectedTests.TestPrograms(Result.Files, AServices.ReadText);
  if AServices.TestUnitContext(AUri, mContext) and (mContext.TestProgram <> '') and
    (IndexText(mContext.TestProgram, Result.TestPrograms) < 0) then
  begin
    Result.TestPrograms := Result.TestPrograms + [mContext.TestProgram];
  end;
  // Treffersicherheit und Zeitlimit wie atlas/impact; Testunits aus allen Testprogrammen.
  Result.Options := AServices.ImpactOptions(AUri);
  Result.Options.Tests := TShellAffectedTests.TestScope(ASettings.TestUnits.Pattern, Result.TestPrograms,
    AServices.ReadText);
end;

initialization
  TAtlasTextTables.Add('Shell.Composition.AffectedTests', cTexts);

end.
