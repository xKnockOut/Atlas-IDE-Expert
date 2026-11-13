unit Shell.Composition.CoveredBy.Tests;

// atlas/coveredBy der Komposition (#1778): fehlende URI, Tiefe und private Methoden aus der Anfrage;
// atlas/untestedMethods (#1783): fehlende URI, Projekt ohne Dateien.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings,
  Shell.Composition.AffectedTests;

type
  [TestFixture]
  TShellCoveredByRequestTests = class
  private
    FRegistry: TShellWorkspaceRegistry;
    FSettings: TShellSettings;
    FServices: TShellAffectedTestsServices;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Ohne textDocument.uri: Fehler InvalidParams.</summary>
    [Test]
    procedure MissingUriInvalidParams;
    /// <summary>Ohne Text in der Anfrage und ohne lesbare Datei: Fehler RequestFailed.</summary>
    [Test]
    procedure UnreadableFileRequestFailed;
    /// <summary>Ohne Angaben Tiefe 1 und nur öffentliche Methoden.</summary>
    [Test]
    procedure DefaultsDepthOneAndPublic;
    /// <summary>Tiefe und private Methoden aus der Anfrage.</summary>
    [Test]
    procedure DepthAndPrivateFromParams;
    /// <summary>atlas/untestedMethods ohne textDocument.uri: Fehler InvalidParams.</summary>
    [Test]
    procedure ProjectMissingUriInvalidParams;
    /// <summary>atlas/untestedMethods ohne Projektdateien: keine Units, nichts ausgelassen.</summary>
    [Test]
    procedure ProjectWithoutFilesIsEmpty;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Lsp.TestUnits,
  Atlas.Common.Lsp.CoveredBy,
  Atlas.Common.Logging.Providers.Logger,
  Shell.Composition.CoveredBy;

const
  cUri = 'file:///C:/Projekt/ATest.pas';

function NoText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function NoSelection(const AOrigin: string): string;
begin
  Result := '';
end;

function NoActive: string;
begin
  Result := '';
end;

function NoLanguageLevel(const AUri: string): string;
begin
  Result := '';
end;

function NoFiles: TArray<string>;
begin
  Result := nil;
end;

function NoContext(const AUri: string; out AContext: TTestUnitContext): Boolean;
begin
  AContext := Default(TTestUnitContext);
  Result := False;
end;

function NoNames: TArray<string>;
begin
  Result := nil;
end;

function DefaultImpact(const AUri: string): TImpactOptions;
begin
  Result := TImpactOptions.Default;
end;

/// <summary>Code des EJsonRpcError der Anfrage mit AParams; 0 ohne Fehler.</summary>
function ErrorCode(const AServices: TShellAffectedTestsServices; AParams: TJSONObject): Integer;
begin
  Result := 0;
  try
    TShellCoveredByRequest.Handle(AServices, AParams, nil).Free;
  except
    on E: EJsonRpcError do
      Result := E.Code;
  end;
end;

procedure TShellCoveredByRequestTests.Setup;
var
  mRegistry: TShellWorkspaceRegistryServices;
begin
  mRegistry := Default(TShellWorkspaceRegistryServices);
  mRegistry.Logger := TLogger.Create;
  mRegistry.SelectedProject := NoSelection;
  mRegistry.ActiveProject := NoActive;
  mRegistry.ReadText := NoText;
  FRegistry := TShellWorkspaceRegistry.Create(mRegistry);
  FSettings := TShellSettings.Create(FRegistry, NoLanguageLevel);
  FServices := Default(TShellAffectedTestsServices);
  FServices.Workspaces := FRegistry;
  FServices.Settings := FSettings;
  FServices.ReadText := NoText;
  FServices.ProjectFiles := NoFiles;
  FServices.TestUnitContext := NoContext;
  FServices.ImpactOptions := DefaultImpact;
end;

procedure TShellCoveredByRequestTests.TearDown;
begin
  FServices := Default(TShellAffectedTestsServices);
  FreeAndNil(FSettings);
  FreeAndNil(FRegistry);
end;

procedure TShellCoveredByRequestTests.MissingUriInvalidParams;
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.Create;
  try
    Assert.AreEqual(TJsonRpcErrorCode.cInvalidParams, ErrorCode(FServices, mParams));
  finally
    mParams.Free;
  end;
end;

procedure TShellCoveredByRequestTests.UnreadableFileRequestFailed;
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.Create;
  try
    mParams.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', cUri)));
    Assert.AreEqual(TJsonRpcErrorCode.cRequestFailed, ErrorCode(FServices, mParams));
  finally
    mParams.Free;
  end;
end;

procedure TShellCoveredByRequestTests.DefaultsDepthOneAndPublic;
var
  mParams: TJSONObject;
  mRequest: TCoveredRequest;
begin
  mParams := TJSONObject.Create;
  try
    mRequest := TShellCoveredByRequest.RequestFor(FServices, cUri, mParams);
    Assert.AreEqual(TCoveredBy.cDefaultDepth, mRequest.Options.Depth);
    Assert.IsFalse(mRequest.IncludePrivate);
    Assert.AreEqual(0, Integer(Length(mRequest.Files)));
  finally
    mParams.Free;
  end;
end;

procedure TShellCoveredByRequestTests.DepthAndPrivateFromParams;
var
  mParams: TJSONObject;
  mRequest: TCoveredRequest;
begin
  mParams := TJSONObject.Create;
  try
    mParams.AddPair('depth', TJSONNumber.Create(3));
    mParams.AddPair('includePrivate', TJSONBool.Create(True));
    mRequest := TShellCoveredByRequest.RequestFor(FServices, cUri, mParams);
    Assert.AreEqual(3, mRequest.Options.Depth);
    Assert.IsTrue(mRequest.IncludePrivate);
  finally
    mParams.Free;
  end;
end;

procedure TShellCoveredByRequestTests.ProjectMissingUriInvalidParams;
var
  mParams: TJSONObject;
  mCode: Integer;
begin
  mParams := TJSONObject.Create;
  try
    mCode := 0;
    try
      TShellCoveredByRequest.HandleProject(FServices, mParams, nil).Free;
    except
      on E: EJsonRpcError do
        mCode := E.Code;
    end;
    Assert.AreEqual(TJsonRpcErrorCode.cInvalidParams, mCode);
  finally
    mParams.Free;
  end;
end;

procedure TShellCoveredByRequestTests.ProjectWithoutFilesIsEmpty;
var
  mParams: TJSONObject;
  mResult: TJSONValue;
begin
  FServices.Namespaces := NoNames;
  mParams := TJSONObject.Create;
  try
    mParams.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', cUri)));
    mResult := TShellCoveredByRequest.HandleProject(FServices, mParams, nil);
    try
      Assert.AreEqual(0, mResult.GetValue<TJSONArray>('units').Count);
      Assert.AreEqual(0, mResult.GetValue<Integer>('skipped'));
    finally
      mResult.Free;
    end;
  finally
    mParams.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellCoveredByRequestTests);

end.
