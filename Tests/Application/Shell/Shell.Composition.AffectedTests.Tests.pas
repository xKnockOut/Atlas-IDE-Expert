unit Shell.Composition.AffectedTests.Tests;

// atlas/affectedTests der Komposition: fehlende URI, kein Arbeitsbereich, Testprogramm der Testunit zusätzlich.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings,
  Shell.Composition.AffectedTests;

type
  [TestFixture]
  TShellAffectedTestsRequestTests = class
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
    /// <summary>Ohne Arbeitsbereich zur URI: Fehler RequestFailed.</summary>
    [Test]
    procedure NoWorkspaceRequestFailed;
    /// <summary>Das Testprogramm der Testunit kommt hinzu, auch wenn es unter den Projektdateien fehlt.</summary>
    [Test]
    procedure TestProgramOfContextAdded;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Lsp.TestUnits,
  Atlas.Common.Lsp.AffectedTests,
  Atlas.Common.Logging.Providers.Logger;

const
  cUri = 'file:///C:/Projekt/ATest.pas';
  cProgram = 'C:\Projekt\Tests.dpr';

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

function WithProgram(const AUri: string; out AContext: TTestUnitContext): Boolean;
begin
  AContext := Default(TTestUnitContext);
  AContext.TestProgram := cProgram;
  Result := True;
end;

function DefaultImpact(const AUri: string): TImpactOptions;
begin
  Result := TImpactOptions.Default;
end;

procedure TShellAffectedTestsRequestTests.Setup;
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
  FServices.TestUnitContext := WithProgram;
  FServices.ImpactOptions := DefaultImpact;
end;

procedure TShellAffectedTestsRequestTests.TearDown;
begin
  FServices := Default(TShellAffectedTestsServices);
  FreeAndNil(FSettings);
  FreeAndNil(FRegistry);
end;

procedure TShellAffectedTestsRequestTests.MissingUriInvalidParams;
var
  mParams: TJSONObject;
  mCode: Integer;
begin
  mParams := TJSONObject.Create;
  try
    mCode := 0;
    try
      TShellAffectedTestsRequest.Handle(FServices, mParams, nil).Free;
    except
      on E: EJsonRpcError do
        mCode := E.Code;
    end;
    Assert.AreEqual(TJsonRpcErrorCode.InvalidParams, mCode);
  finally
    mParams.Free;
  end;
end;

procedure TShellAffectedTestsRequestTests.NoWorkspaceRequestFailed;
var
  mParams: TJSONObject;
  mCode: Integer;
begin
  mParams := TJSONObject.Create;
  try
    mCode := 0;
    try
      TShellAffectedTestsRequest.QueryFor(FServices, mParams, cUri);
    except
      on E: EJsonRpcError do
        mCode := E.Code;
    end;
    Assert.AreEqual(TJsonRpcErrorCode.RequestFailed, mCode);
  finally
    mParams.Free;
  end;
end;

procedure TShellAffectedTestsRequestTests.TestProgramOfContextAdded;
var
  mRequest: TAffectedRequest;
begin
  mRequest := TShellAffectedTestsRequest.RequestFor(FServices, cUri, TServerSettings.Default);
  Assert.AreEqual(1, Integer(Length(mRequest.TestPrograms)));
  Assert.AreEqual(cProgram, mRequest.TestPrograms[0]);
  Assert.AreEqual(0, Integer(Length(mRequest.Files)));
end;

initialization
  TDUnitX.RegisterTestFixture(TShellAffectedTestsRequestTests);

end.
