unit Lsp.ConfigurationProtocol.Tests;

// Tests für die LSP-Seite der Konfiguration: publishDiagnostics zu atlas.json, Editor-Einstellungen aus
// didChangeConfiguration, Wurzelordner und Sprache aus initialize.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspConfigurationProtocolTests = class
  public
    /// <summary>Fehler als Severity 1, Warnungen als 2, Version nur aus dem Editor.</summary>
    [Test]
    procedure PublisherSendsDiagnostics;
    [Test]
    procedure EditorSettingsFromParams;
    [Test]
    procedure ReadsRootFromInitializeParams;
    /// <summary>initializationOptions.locale vor locale (#1458).</summary>
    [Test]
    procedure ClientLocaleFromInitialize;
  end;

implementation

uses
  System.Generics.Collections, // Inline TJSONArray.GetValue (H2443)
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Workspace,
  Lsp.SyntaxDiagnostics.Tests,
  Lsp.ConfigurationProtocol;

function IssueOf(AIsError: Boolean; const AMessage: string): TConfigurationIssue;
begin
  Result := Default(TConfigurationIssue);
  Result.IsError := AIsError;
  Result.Message := AMessage;
  Result.Range.StartPos.Line := 2;
  Result.Range.StartPos.Character := 4;
end;

{ TLspConfigurationProtocolTests }

procedure TLspConfigurationProtocolTests.PublisherSendsDiagnostics;
var
  mCapture: TCapturingTransport;
  mTransport: IJsonRpcTransport;
  mPublish: TConfigurationIssuesPublisher;
  mMessage, mFirst: TJSONObject;
  mDiagnostics: TJSONArray;
begin
  mCapture := TCapturingTransport.Create;
  mTransport := mCapture;
  mPublish := TLspConfigurationProtocol.Publisher(mTransport);
  mPublish('file:///c%3A/P/atlas.json', 3, [IssueOf(True, 'kaputt'), IssueOf(False, 'falscher Ort')]);
  mPublish('file:///c%3A/P/atlas.json', -1, nil);
  Assert.AreEqual(2, mCapture.Count);
  mMessage := mCapture.MessageAt(0);
  try
    Assert.AreEqual('textDocument/publishDiagnostics', mMessage.GetValue<string>('method'));
    Assert.AreEqual('file:///c%3A/P/atlas.json', mMessage.GetValue<string>('params.uri'));
    Assert.AreEqual(3, mMessage.GetValue<Integer>('params.version'));
    mDiagnostics := mMessage.GetValue<TJSONArray>('params.diagnostics');
    Assert.AreEqual(2, mDiagnostics.Count);
    mFirst := mDiagnostics.Items[0] as TJSONObject;
    Assert.AreEqual(1, mFirst.GetValue<Integer>('severity'));
    Assert.AreEqual(2, (mDiagnostics.Items[1] as TJSONObject).GetValue<Integer>('severity'));
    Assert.AreEqual('Atlas', mFirst.GetValue<string>('source'));
    Assert.AreEqual('kaputt', mFirst.GetValue<string>('message'));
    Assert.AreEqual(2, mFirst.GetValue<Integer>('range.start.line'));
    Assert.AreEqual(4, mFirst.GetValue<Integer>('range.start.character'));
  finally
    mMessage.Free;
  end;
  mMessage := mCapture.MessageAt(1);
  try
    Assert.IsNull(mMessage.FindValue('params.version'));
    Assert.AreEqual(0, mMessage.GetValue<TJSONArray>('params.diagnostics').Count);
  finally
    mMessage.Free;
  end;
  mPublish := nil;
end;

procedure TLspConfigurationProtocolTests.EditorSettingsFromParams;
var
  mParams: TJSONValue;
begin
  mParams := TJSONObject.ParseJSONValue('{"settings": {"atlas": {"language": "en"}, "andere": {"x": 1}}}');
  try
    Assert.AreEqual('{"language":"en"}', TLspConfigurationProtocol.EditorSettingsFromParams(mParams));
  finally
    mParams.Free;
  end;
  mParams := TJSONObject.ParseJSONValue('{"settings": {"andere": {"x": 1}}}');
  try
    Assert.AreEqual('', TLspConfigurationProtocol.EditorSettingsFromParams(mParams));
  finally
    mParams.Free;
  end;
  Assert.AreEqual('', TLspConfigurationProtocol.EditorSettingsFromParams(nil));
end;

procedure TLspConfigurationProtocolTests.ReadsRootFromInitializeParams;
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.ParseJSONValue('{"rootUri": "file:///c%3A/Projekt"}') as TJSONObject;
  try
    Assert.AreEqual('c:\Projekt', TLspConfigurationProtocol.RootPathFromInitialize(mParams));
  finally
    mParams.Free;
  end;
  mParams := TJSONObject.ParseJSONValue('{"rootUri": null, "workspaceFolders": [{"uri": "file:///d%3A/W", ' +
    '"name": "W"}]}') as TJSONObject;
  try
    Assert.AreEqual('d:\W', TLspConfigurationProtocol.RootPathFromInitialize(mParams));
  finally
    mParams.Free;
  end;
  Assert.AreEqual('', TLspConfigurationProtocol.RootPathFromInitialize(nil));
end;

function LocaleOf(const AJson: string): string;
var
  mParams: TJSONValue;
begin
  mParams := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TLspClientLocale.FromInitialize(mParams);
  finally
    mParams.Free;
  end;
end;

procedure TLspConfigurationProtocolTests.ClientLocaleFromInitialize;
begin
  Assert.AreEqual('de', LocaleOf('{"locale": "en-US", "initializationOptions": {"locale": "de"}}'));
  Assert.AreEqual('en-US', LocaleOf('{"locale": "en-US", "initializationOptions": {"locale": " "}}'));
  Assert.AreEqual('en-US', LocaleOf('{"locale": "en-US"}'));
  Assert.AreEqual('', LocaleOf('{"processId": 1}'));
  Assert.AreEqual('', TLspClientLocale.FromInitialize(nil));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspConfigurationProtocolTests);

end.
