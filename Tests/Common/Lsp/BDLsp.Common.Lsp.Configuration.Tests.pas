unit BDLsp.Common.Lsp.Configuration.Tests;

interface

uses
  DUnitX.TestFramework,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Lsp.SyntaxDiagnostics.Tests,
  BDLsp.Common.Lsp.Configuration;

type
  [TestFixture]
  TLspUrisTests = class
  public
    [Test]
    procedure ConvertsWindowsPaths;
    [Test]
    procedure ConvertsUncAndUnixPaths;
    [Test]
    procedure DecodesUtf8;
    [Test]
    procedure IgnoresOtherSchemes;
  end;

  [TestFixture]
  TLspConfigurationTests = class
  private
    FStore: IDocumentStore;
    FCapture: TCapturingTransport;
    FTransport: IJsonRpcTransport;
    FConfiguration: TLspConfiguration;
    FDiskText: string;
    FChanges: Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure UsesDefaultsWithoutFile;
    [Test]
    procedure LoadsFileFromWorkspaceRoot;
    [Test]
    procedure PublishesIssuesOfOpenedFile;
    [Test]
    procedure AppliesEditsAndRevertsOnClose;
    [Test]
    procedure ReadsRootFromInitializeParams;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.Documents.Providers.DocumentStore,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Lsp.Uris;

const
  Root = 'c:\Projekt';
  ConfigUri = 'file:///c%3A/Projekt/delphi-lsp.json';

{ TLspUrisTests }

procedure TLspUrisTests.ConvertsWindowsPaths;
begin
  Assert.AreEqual('c:\Projekt\A B.pas', TLspUris.ToPath('file:///c%3A/Projekt/A%20B.pas'));
  Assert.AreEqual('C:\Projekt\A.pas', TLspUris.ToPath('file:///C:/Projekt/A.pas'));
  Assert.AreEqual('file:///c%3A/Projekt/A%20B.pas', TLspUris.FromPath('C:\Projekt\A B.pas'));
  Assert.IsTrue(TLspUris.SameFile('file:///c%3A/Projekt/A.pas', 'file:///C:/projekt/a.pas'));
end;

procedure TLspUrisTests.ConvertsUncAndUnixPaths;
begin
  Assert.AreEqual('\\server\share\A.pas', TLspUris.ToPath('file://server/share/A.pas'));
  Assert.AreEqual('file://server/share/A.pas', TLspUris.FromPath('\\server\share\A.pas'));
  Assert.AreEqual('/home/a/A.pas', TLspUris.ToPath('file:///home/a/A.pas'));
end;

procedure TLspUrisTests.DecodesUtf8;
begin
  Assert.AreEqual('c:\Gr' + #$00FC + 'n.pas', TLspUris.ToPath('file:///c%3A/Gr%C3%BCn.pas'));
  Assert.AreEqual('file:///c%3A/Gr%C3%BCn.pas', TLspUris.FromPath('c:\Gr' + #$00FC + 'n.pas'));
end;

procedure TLspUrisTests.IgnoresOtherSchemes;
begin
  Assert.AreEqual('', TLspUris.ToPath('untitled:Untitled-1'));
end;

{ TLspConfigurationTests }

procedure TLspConfigurationTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FCapture := TCapturingTransport.Create;
  FTransport := FCapture;
  FDiskText := '';
  FChanges := 0;
  FConfiguration := TLspConfiguration.Create(FStore, FTransport,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := SameText(AFileName, Root + '\' + ConfigurationFileName) and (FDiskText <> '');
      AText := FDiskText;
    end);
  FConfiguration.OnChanged :=
    procedure(const ASettings: TServerSettings)
    begin
      Inc(FChanges);
    end;
  FConfiguration.Attach;
end;

procedure TLspConfigurationTests.TearDown;
begin
  FConfiguration.Free;
  FStore := nil;
  FTransport := nil;
end;

procedure TLspConfigurationTests.UsesDefaultsWithoutFile;
begin
  FConfiguration.LoadWorkspace(Root);
  Assert.AreEqual('de', FConfiguration.Settings.Language);
  Assert.AreEqual(1, FChanges);
  Assert.AreEqual(0, FCapture.Count);
end;

procedure TLspConfigurationTests.LoadsFileFromWorkspaceRoot;
var
  Message: TJSONObject;
begin
  FDiskText := '{"platform": "Win64", "unbekannt": 1}';
  FConfiguration.LoadWorkspace(Root);
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform);
  Assert.AreEqual(1, FCapture.Count);
  Message := FCapture.MessageAt(0);
  try
    Assert.AreEqual(ConfigUri, Message.GetValue<string>('params.uri'));
    Assert.AreEqual(1, Message.GetValue<TJSONArray>('params.diagnostics').Count);
    Assert.AreEqual(2, Message.GetValue<Integer>('params.diagnostics[0].severity'));
  finally
    Message.Free;
  end;
end;

procedure TLspConfigurationTests.PublishesIssuesOfOpenedFile;
var
  Message: TJSONObject;
begin
  FStore.Open('file:///c%3A/Anderer/delphi-lsp.json', 'json', 3, '{"language": 1}');
  Assert.AreEqual(1, FCapture.Count);
  Message := FCapture.MessageAt(0);
  try
    Assert.AreEqual(3, Message.GetValue<Integer>('params.version'));
    Assert.AreEqual(1, Message.GetValue<Integer>('params.diagnostics[0].severity'));
  finally
    Message.Free;
  end;
  // Eine andere Datei als die des Arbeitsbereichs ändert die Einstellungen nicht.
  Assert.AreEqual(0, FChanges);
end;

procedure TLspConfigurationTests.AppliesEditsAndRevertsOnClose;
begin
  FDiskText := '{"platform": "Win32"}';
  FConfiguration.LoadWorkspace(Root);
  FStore.Open(ConfigUri, 'json', 1, '{"platform": "Win64"}');
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform);
  FStore.Change(ConfigUri, 2, [TTextChange.Full('{"platform": "Linux64"}')]);
  Assert.AreEqual('Linux64', FConfiguration.Settings.Platform);
  FStore.Close(ConfigUri);
  Assert.AreEqual('Win32', FConfiguration.Settings.Platform);
end;

procedure TLspConfigurationTests.ReadsRootFromInitializeParams;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.ParseJSONValue('{"rootUri": "file:///c%3A/Projekt"}') as TJSONObject;
  try
    Assert.AreEqual('c:\Projekt', TLspConfiguration.RootPathFromInitialize(Params));
  finally
    Params.Free;
  end;
  Params := TJSONObject.ParseJSONValue('{"rootUri": null, "workspaceFolders": [{"uri": "file:///d%3A/W", "name": "W"}]}') as TJSONObject;
  try
    Assert.AreEqual('d:\W', TLspConfiguration.RootPathFromInitialize(Params));
  finally
    Params.Free;
  end;
  Assert.AreEqual('', TLspConfiguration.RootPathFromInitialize(nil));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspUrisTests);
  TDUnitX.RegisterTestFixture(TLspConfigurationTests);

end.
