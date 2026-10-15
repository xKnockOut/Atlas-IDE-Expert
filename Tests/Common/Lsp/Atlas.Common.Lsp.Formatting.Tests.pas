unit Atlas.Common.Lsp.Formatting.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspFormattingTests = class
  public
    [Test]
    procedure EditorOptionsAreTheBase;
    [Test]
    procedure EditorConfigOverridesEditor;
    [Test]
    procedure ConfiguredKeysOverrideEditorConfig;
    /// <summary>Code-Review A-06: Abgebrochen, bevor Schnellbefehle Projekt und Platte ändern.</summary>
    [Test]
    procedure OnTypeStopsBeforeSlashCommandsWhenCancelled;
    [Test]
    procedure FormattingStopsWhenCancelled;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Editing.EditorConfig,
  Atlas.Common.Lsp.Formatting;

const
  CancelUri = 'file:///C:/P/Unit1.pas';

/// <summary>Schickt AJson (Anfrage mit id 1) durch einen eigenen Dispatcher; liefert error.code oder 0.</summary>
function ErrorCodeOf(ADispatcher: TJsonRpcDispatcher; const AJson: string): Integer;
var
  Request, Response: TJSONObject;
begin
  Request := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  try
    Response := ADispatcher.DispatchMessage(Request);
    try
      if not Response.TryGetValue<Integer>('error.code', Result) then
        Result := 0;
    finally
      Response.Free;
    end;
  finally
    Request.Free;
  end;
end;

function Options: TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue('{"tabSize": 4, "insertSpaces": false, "insertFinalNewline": true}') as TJSONObject;
end;

function ReadTabsConfig: TEditorConfigReadFile;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := SameText(AFileName, 'C:\P\.editorconfig');
      AText := 'root = true'#10'[*.pas]'#10'indent_style = space'#10'indent_size = 3';
    end;
end;

{ TLspFormattingTests }

procedure TLspFormattingTests.EditorOptionsAreTheBase;
var
  Json: TJSONObject;
  Style: TFormatStyle;
begin
  Json := Options;
  try
    Style := TLspFormatting.Resolve(Json, 'C:\P\Unit1.pas', TFormatStyle.Default, nil);
    Assert.AreEqual(4, Style.IndentSize);
    Assert.IsTrue(Style.UseTabs);
    Assert.IsTrue(Style.InsertFinalNewline);
  finally
    Json.Free;
  end;
end;

procedure TLspFormattingTests.EditorConfigOverridesEditor;
var
  Json: TJSONObject;
  Style: TFormatStyle;
begin
  Json := Options;
  try
    Style := TLspFormatting.Resolve(Json, 'C:\P\Unit1.pas', TFormatStyle.Default, ReadTabsConfig());
    Assert.AreEqual(3, Style.IndentSize);
    Assert.IsFalse(Style.UseTabs);
  finally
    Json.Free;
  end;
end;

procedure TLspFormattingTests.ConfiguredKeysOverrideEditorConfig;
var
  Json: TJSONObject;
  Configured, Style: TFormatStyle;
begin
  Configured := TFormatStyle.Default;
  Configured.IndentSize := 8;
  Configured.KeywordCase := TKeywordCase.Upper;
  Configured.Given := [TFormatKey.IndentSize];
  Json := Options;
  try
    Style := TLspFormatting.Resolve(Json, 'C:\P\Unit1.pas', Configured, ReadTabsConfig());
    Assert.AreEqual(8, Style.IndentSize);
    // Nicht ausdrücklich gesetzt: bleibt beim Wert aus .editorconfig bzw. der Vorgabe.
    Assert.IsFalse(Style.UseTabs);
    Assert.IsTrue(Style.KeywordCase = TKeywordCase.Preserve);
  finally
    Json.Free;
  end;
end;

procedure TLspFormattingTests.OnTypeStopsBeforeSlashCommandsWhenCancelled;
var
  Store: IDocumentStore;
  Formatting: TLspFormatting;
  Dispatcher: TJsonRpcDispatcher;
  SlashAsked: Boolean;
begin
  SlashAsked := False;
  Store := TDocumentStore.Create;
  Store.Open(CancelUri, 'objectpascal', 1, 'unit Unit1;'#10'/define TEST'#10'interface'#10'implementation'#10'end.');
  Dispatcher := TJsonRpcDispatcher.Create;
  Formatting := TLspFormatting.Create(Store, nil, nil);
  try
    // Ohne Scheduler läuft die Anfrage in DispatchMessage; abgebrochen wird mitten im Handler.
    Formatting.DelphiVersionFor :=
      function(const AUri: string): string
      var
        Id: TJSONValue;
      begin
        Id := TJSONNumber.Create(1);
        try
          Dispatcher.PendingRequests.Cancel(Id);
        finally
          Id.Free;
        end;
        Result := '';
      end;
    Formatting.SlashCommandsFor :=
      function(const AUri: string; out ADisabled: TArray<string>): Boolean
      begin
        SlashAsked := True;
        ADisabled := nil;
        Result := True;
      end;
    Formatting.Attach(Dispatcher);
    Assert.AreEqual(TJsonRpcErrorCode.RequestCancelled, ErrorCodeOf(Dispatcher,
      '{"jsonrpc":"2.0","id":1,"method":"textDocument/onTypeFormatting","params":{"textDocument":{"uri":"' +
      CancelUri + '"},"position":{"line":2,"character":0},"ch":"\n"}}'));
    Assert.IsFalse(SlashAsked, 'Schnellbefehle trotz Abbruch');
  finally
    Formatting.Free;
    Dispatcher.Free;
  end;
end;

procedure TLspFormattingTests.FormattingStopsWhenCancelled;
var
  Store: IDocumentStore;
  Formatting: TLspFormatting;
  Dispatcher: TJsonRpcDispatcher;
begin
  Store := TDocumentStore.Create;
  Store.Open(CancelUri, 'objectpascal', 1, 'unit Unit1;'#10'interface'#10'implementation'#10'end.');
  Dispatcher := TJsonRpcDispatcher.Create;
  Formatting := TLspFormatting.Create(Store,
    function(const AUri: string): TFormatStyle
    var
      Id: TJSONValue;
    begin
      Id := TJSONNumber.Create(1);
      try
        Dispatcher.PendingRequests.Cancel(Id);
      finally
        Id.Free;
      end;
      Result := TFormatStyle.Default;
    end, nil);
  try
    Formatting.Attach(Dispatcher);
    Assert.AreEqual(TJsonRpcErrorCode.RequestCancelled, ErrorCodeOf(Dispatcher,
      '{"jsonrpc":"2.0","id":1,"method":"textDocument/formatting","params":{"textDocument":{"uri":"' +
      CancelUri + '"},"options":{"tabSize":2,"insertSpaces":true}}}'));
  finally
    Formatting.Free;
    Dispatcher.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspFormattingTests);

end.
