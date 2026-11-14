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
    /// <summary>Abgebrochen, bevor Schnellbefehle Projekt und Platte ändern.</summary>
    [Test]
    procedure OnTypeStopsBeforeSlashCommandsWhenCancelled;
    [Test]
    procedure FormattingStopsWhenCancelled;
    [Test]
    procedure DocCommentAfterSlashIsSwitchable;
    /// <summary>#293/#43: Schnellbefehle nach Enter rücken nach den Editor-Optionen ein (hier Tabulatoren).</summary>
    [Test]
    procedure SlashCommandFollowsEditorOptions;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Editing.EditorConfig,
  Atlas.Common.Lsp.Formatting;

const
  cCancelUri = 'file:///C:/P/Unit1.pas';

/// <summary>Schickt AJson (Anfrage mit id 1) durch einen eigenen Dispatcher; liefert error.code oder 0.</summary>
function ErrorCodeOf(ADispatcher: TJsonRpcDispatcher; const AJson: string): Integer;
var
  mRequest, mResponse: TJSONObject;
begin
  mRequest := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  try
    mResponse := ADispatcher.DispatchMessage(mRequest);
    try
      if not mResponse.TryGetValue<Integer>('error.code', Result) then
      begin
        Result := 0;
      end;
    finally
      mResponse.Free;
    end;
  finally
    mRequest.Free;
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

/// <summary>Anzahl der Bearbeitungen in der Antwort auf AJson (Anfrage mit id 1); -1 ohne result.</summary>
function EditCountOf(ADispatcher: TJsonRpcDispatcher; const AJson: string): Integer;
var
  mRequest, mResponse: TJSONObject;
  mEdits: TJSONArray;
begin
  mRequest := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  try
    mResponse := ADispatcher.DispatchMessage(mRequest);
    try
      if mResponse.TryGetValue<TJSONArray>('result', mEdits) then
      begin
        Result := mEdits.Count;
      end
      else
      begin
        Result := -1;
      end;
    finally
      mResponse.Free;
    end;
  finally
    mRequest.Free;
  end;
end;

{ TLspFormattingTests }

procedure TLspFormattingTests.DocCommentAfterSlashIsSwitchable;
const
  cRequest = '{"jsonrpc":"2.0","id":1,"method":"textDocument/onTypeFormatting","params":{"textDocument":{"uri":"' +
    cCancelUri + '"},"position":{"line":3,"character":5},"ch":"/"}}';
var
  mStore: IDocumentStore;
  mFormatting: TLspFormatting;
  mDispatcher: TJsonRpcDispatcher;
  mEnabled: Boolean;
begin
  mStore := TDocumentStore.Create;
  mStore.Open(cCancelUri, 'objectpascal', 1, 'unit Unit1;'#10'interface'#10#10'  ///'#10 +
    'procedure Foo(A: Integer);'#10'implementation'#10'procedure Foo(A: Integer);'#10'begin'#10'end;'#10'end.');
  mDispatcher := TJsonRpcDispatcher.Create;
  mFormatting := TLspFormatting.Create(mStore, nil, nil);
  try
    mEnabled := True;
    mFormatting.DocCommentsFor :=
      function(const AUri: string): Boolean
      begin
        Result := mEnabled;
      end;
    mFormatting.Attach(mDispatcher);
    Assert.AreEqual(1, EditCountOf(mDispatcher, cRequest), 'Gerüst eingeschaltet');
    // completeBlocks.docComment = false: "///" bleibt, wie getippt.
    mEnabled := False;
    Assert.AreEqual(0, EditCountOf(mDispatcher, cRequest), 'Gerüst abgeschaltet');
  finally
    mFormatting.Free;
    mDispatcher.Free;
  end;
end;

procedure TLspFormattingTests.SlashCommandFollowsEditorOptions;
const
  cRequest = '{"jsonrpc":"2.0","id":1,"method":"textDocument/onTypeFormatting","params":{"textDocument":{"uri":"' +
    cCancelUri + '"},"position":{"line":9,"character":1},"ch":"\n",' +
    '"options":{"tabSize":4,"insertSpaces":false}}}';
var
  mStore: IDocumentStore;
  mFormatting: TLspFormatting;
  mDispatcher: TJsonRpcDispatcher;
  mMessage_, mResponse: TJSONObject;
begin
  mStore := TDocumentStore.Create;
  mStore.Open(cCancelUri, 'objectpascal', 1, 'unit Unit1;'#10'interface'#10'implementation'#10'procedure P;'#10 +
    'var'#10#9'Liste: TStringList;'#10'begin'#10#9'Liste := TStringList.Create;'#10#9'/try'#10#9#10 +
    #9'Liste.Sort;'#10'end;'#10'end.');
  mDispatcher := TJsonRpcDispatcher.Create;
  mFormatting := TLspFormatting.Create(mStore, nil, nil);
  try
    mFormatting.Attach(mDispatcher);
    mMessage_ := TJSONObject.ParseJSONValue(cRequest) as TJSONObject;
    try
      mResponse := mDispatcher.DispatchMessage(mMessage_);
      try
        Assert.IsTrue(Pos('\t\tListe.Sort', mResponse.ToJSON) > 0, mResponse.ToJSON);
        Assert.AreEqual(0, Pos('  \tListe.Sort', mResponse.ToJSON), mResponse.ToJSON);
      finally
        mResponse.Free;
      end;
    finally
      mMessage_.Free;
    end;
  finally
    mFormatting.Free;
    mDispatcher.Free;
  end;
end;

procedure TLspFormattingTests.EditorOptionsAreTheBase;
var
  mJson: TJSONObject;
  mStyle: TFormatStyle;
begin
  mJson := Options;
  try
    mStyle := TLspFormatting.Resolve(mJson, 'C:\P\Unit1.pas', TFormatStyle.Default, nil);
    Assert.AreEqual(4, mStyle.IndentSize);
    Assert.IsTrue(mStyle.UseTabs);
    Assert.IsTrue(mStyle.InsertFinalNewline);
  finally
    mJson.Free;
  end;
end;

procedure TLspFormattingTests.EditorConfigOverridesEditor;
var
  mJson: TJSONObject;
  mStyle: TFormatStyle;
begin
  mJson := Options;
  try
    mStyle := TLspFormatting.Resolve(mJson, 'C:\P\Unit1.pas', TFormatStyle.Default, ReadTabsConfig());
    Assert.AreEqual(3, mStyle.IndentSize);
    Assert.IsFalse(mStyle.UseTabs);
  finally
    mJson.Free;
  end;
end;

procedure TLspFormattingTests.ConfiguredKeysOverrideEditorConfig;
var
  mJson: TJSONObject;
  mConfigured, mStyle: TFormatStyle;
begin
  mConfigured := TFormatStyle.Default;
  mConfigured.IndentSize := 8;
  mConfigured.KeywordCase := TKeywordCase.Upper;
  mConfigured.Given := [TFormatKey.IndentSize];
  mJson := Options;
  try
    mStyle := TLspFormatting.Resolve(mJson, 'C:\P\Unit1.pas', mConfigured, ReadTabsConfig());
    Assert.AreEqual(8, mStyle.IndentSize);
    // Nicht ausdrücklich gesetzt: bleibt beim Wert aus .editorconfig bzw. der Vorgabe.
    Assert.IsFalse(mStyle.UseTabs);
    Assert.AreEqual<TKeywordCase>(TKeywordCase.Preserve, mStyle.KeywordCase);
  finally
    mJson.Free;
  end;
  // Schalter ohne Gegenstück im Editor gelten immer; maxLineLength nur gesetzt vor .editorconfig (#43).
  mConfigured := TFormatStyle.Default;
  mConfigured.Reindent := False;
  mConfigured.BeginPlacement := TBlockPlacement.NewLine;
  mConfigured.AlignComments := True;
  mConfigured.MaxLineLength := 90;
  mStyle := TLspFormatting.Resolve(nil, 'C:\P\Unit1.pas', mConfigured, nil);
  Assert.IsFalse(mStyle.Reindent);
  Assert.AreEqual<TBlockPlacement>(TBlockPlacement.NewLine, mStyle.BeginPlacement);
  Assert.IsTrue(mStyle.AlignComments);
  Assert.AreEqual(0, mStyle.MaxLineLength);
  mConfigured.Given := [TFormatKey.MaxLineLength];
  mStyle := TLspFormatting.Resolve(nil, 'C:\P\Unit1.pas', mConfigured, nil);
  Assert.AreEqual(90, mStyle.MaxLineLength);
end;

procedure TLspFormattingTests.OnTypeStopsBeforeSlashCommandsWhenCancelled;
var
  mStore: IDocumentStore;
  mFormatting: TLspFormatting;
  mDispatcher: TJsonRpcDispatcher;
  mSlashAsked: Boolean;
begin
  mSlashAsked := False;
  mStore := TDocumentStore.Create;
  mStore.Open(cCancelUri, 'objectpascal', 1, 'unit Unit1;'#10'/define TEST'#10'interface'#10'implementation'#10'end.');
  mDispatcher := TJsonRpcDispatcher.Create;
  mFormatting := TLspFormatting.Create(mStore, nil, nil);
  try
    // Ohne Scheduler läuft die Anfrage in DispatchMessage; abgebrochen wird mitten im Handler.
    mFormatting.DelphiVersionFor :=
      function(const AUri: string): string
      var
        Id: TJSONValue;
      begin
        Id := TJSONNumber.Create(1);
        try
          mDispatcher.PendingRequests.Cancel(Id);
        finally
          Id.Free;
        end;
        Result := '';
      end;
    mFormatting.SlashCommandsFor :=
      function(const AUri: string; out ADisabled: TArray<string>): Boolean
      begin
        mSlashAsked := True;
        ADisabled := nil;
        Result := True;
      end;
    mFormatting.Attach(mDispatcher);
    Assert.AreEqual(TJsonRpcErrorCode.cRequestCancelled, ErrorCodeOf(mDispatcher,
      '{"jsonrpc":"2.0","id":1,"method":"textDocument/onTypeFormatting","params":{"textDocument":{"uri":"' +
      cCancelUri + '"},"position":{"line":2,"character":0},"ch":"\n"}}'));
    Assert.IsFalse(mSlashAsked, 'Schnellbefehle trotz Abbruch');
  finally
    mFormatting.Free;
    mDispatcher.Free;
  end;
end;

procedure TLspFormattingTests.FormattingStopsWhenCancelled;
var
  mStore: IDocumentStore;
  mFormatting: TLspFormatting;
  mDispatcher: TJsonRpcDispatcher;
begin
  mStore := TDocumentStore.Create;
  mStore.Open(cCancelUri, 'objectpascal', 1, 'unit Unit1;'#10'interface'#10'implementation'#10'end.');
  mDispatcher := TJsonRpcDispatcher.Create;
  mFormatting := TLspFormatting.Create(mStore,
    function(const AUri: string): TFormatStyle
    var
      Id: TJSONValue;
    begin
      Id := TJSONNumber.Create(1);
      try
        mDispatcher.PendingRequests.Cancel(Id);
      finally
        Id.Free;
      end;
      Result := TFormatStyle.Default;
    end, nil);
  try
    mFormatting.Attach(mDispatcher);
    Assert.AreEqual(TJsonRpcErrorCode.cRequestCancelled, ErrorCodeOf(mDispatcher,
      '{"jsonrpc":"2.0","id":1,"method":"textDocument/formatting","params":{"textDocument":{"uri":"' +
      cCancelUri + '"},"options":{"tabSize":2,"insertSpaces":true}}}'));
  finally
    mFormatting.Free;
    mDispatcher.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspFormattingTests);

end.
