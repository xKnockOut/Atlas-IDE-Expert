unit Editing.Formatting.Protocol.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormattingProtocolTests = class
  public
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
    /// <summary>format.sortUses: Die ganze Datei formatieren sortiert die uses mit, die übrigen Änderungen
    /// bleiben; ohne Schalter oder bei einer Auswahl nicht.</summary>
    [Test]
    procedure FormattingSortsUsesWhenSwitchedOn;
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
  Editing.MaintenanceCommands,
  Editing.Formatting.Protocol;

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

/// <summary>result der Antwort auf AJson (Anfrage mit id 1) als JSON-Text.</summary>
function ResultOf(ADispatcher: TJsonRpcDispatcher; const AJson: string): string;
var
  mRequest, mResponse: TJSONObject;
  mResult: TJSONValue;
begin
  mRequest := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  try
    mResponse := ADispatcher.DispatchMessage(mRequest);
    try
      Result := '';
      if mResponse.TryGetValue<TJSONValue>('result', mResult) then
      begin
        Result := mResult.ToJSON;
      end;
    finally
      mResponse.Free;
    end;
  finally
    mRequest.Free;
  end;
end;

{ TFormattingProtocolTests }

procedure TFormattingProtocolTests.OnTypeStopsBeforeSlashCommandsWhenCancelled;
var
  mStore: IDocumentStore;
  mFormatting: TFormattingProtocol;
  mDispatcher: TJsonRpcDispatcher;
  mSlashAsked: Boolean;
begin
  mSlashAsked := False;
  mStore := TDocumentStore.Create;
  mStore.Open(cCancelUri, 'objectpascal', 1, 'unit Unit1;'#10'/define TEST'#10'interface'#10'implementation'#10'end.');
  mDispatcher := nil;
  mFormatting := nil;
  try
    mDispatcher := TJsonRpcDispatcher.Create;
    mFormatting := TFormattingProtocol.Create(mStore, nil, nil);
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

procedure TFormattingProtocolTests.FormattingStopsWhenCancelled;
var
  mStore: IDocumentStore;
  mFormatting: TFormattingProtocol;
  mDispatcher: TJsonRpcDispatcher;
begin
  mStore := TDocumentStore.Create;
  mStore.Open(cCancelUri, 'objectpascal', 1, 'unit Unit1;'#10'interface'#10'implementation'#10'end.');
  mDispatcher := nil;
  mFormatting := nil;
  try
    mDispatcher := TJsonRpcDispatcher.Create;
    mFormatting := TFormattingProtocol.Create(mStore,
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
    mFormatting.Attach(mDispatcher);
    Assert.AreEqual(TJsonRpcErrorCode.cRequestCancelled, ErrorCodeOf(mDispatcher,
      '{"jsonrpc":"2.0","id":1,"method":"textDocument/formatting","params":{"textDocument":{"uri":"' +
      cCancelUri + '"},"options":{"tabSize":2,"insertSpaces":true}}}'));
  finally
    mFormatting.Free;
    mDispatcher.Free;
  end;
end;

procedure TFormattingProtocolTests.DocCommentAfterSlashIsSwitchable;
const
  cRequest = '{"jsonrpc":"2.0","id":1,"method":"textDocument/onTypeFormatting","params":{"textDocument":{"uri":"' +
    cCancelUri + '"},"position":{"line":3,"character":5},"ch":"/"}}';
var
  mStore: IDocumentStore;
  mFormatting: TFormattingProtocol;
  mDispatcher: TJsonRpcDispatcher;
  mEnabled: Boolean;
begin
  mStore := TDocumentStore.Create;
  mStore.Open(cCancelUri, 'objectpascal', 1, 'unit Unit1;'#10'interface'#10#10'  ///'#10 +
    'procedure Foo(A: Integer);'#10'implementation'#10'procedure Foo(A: Integer);'#10'begin'#10'end;'#10'end.');
  mDispatcher := nil;
  mFormatting := nil;
  try
    mDispatcher := TJsonRpcDispatcher.Create;
    mFormatting := TFormattingProtocol.Create(mStore, nil, nil);
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

procedure TFormattingProtocolTests.SlashCommandFollowsEditorOptions;
const
  cRequest = '{"jsonrpc":"2.0","id":1,"method":"textDocument/onTypeFormatting","params":{"textDocument":{"uri":"' +
    cCancelUri + '"},"position":{"line":9,"character":1},"ch":"\n",' +
    '"options":{"tabSize":4,"insertSpaces":false}}}';
var
  mStore: IDocumentStore;
  mFormatting: TFormattingProtocol;
  mDispatcher: TJsonRpcDispatcher;
  mMessage_, mResponse: TJSONObject;
begin
  mStore := TDocumentStore.Create;
  mStore.Open(cCancelUri, 'objectpascal', 1, 'unit Unit1;'#10'interface'#10'implementation'#10'procedure P;'#10 +
    'var'#10#9'Liste: TStringList;'#10'begin'#10#9'Liste := TStringList.Create;'#10#9'/try'#10#9#10 +
    #9'Liste.Sort;'#10'end;'#10'end.');
  mDispatcher := nil;
  mFormatting := nil;
  try
    mDispatcher := TJsonRpcDispatcher.Create;
    mFormatting := TFormattingProtocol.Create(mStore, nil, nil);
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

procedure TFormattingProtocolTests.FormattingSortsUsesWhenSwitchedOn;
const
  cWhole = '{"jsonrpc":"2.0","id":1,"method":"textDocument/formatting","params":{"textDocument":{"uri":"' +
    cCancelUri + '"},"options":{"tabSize":2,"insertSpaces":true}}}';
  cRange = '{"jsonrpc":"2.0","id":1,"method":"textDocument/rangeFormatting","params":{"textDocument":{"uri":"' +
    cCancelUri + '"},"range":{"start":{"line":0,"character":0},"end":{"line":9,"character":0}},' +
    '"options":{"tabSize":2,"insertSpaces":true}}}';
var
  mStore: IDocumentStore;
  mFormatting: TFormattingProtocol;
  mDispatcher: TJsonRpcDispatcher;
  mSortUses: Boolean;
  mResult: string;
begin
  mStore := TDocumentStore.Create;
  // Zeta doppelt, Leerzeichen am Ende von "interface" für den Formatter.
  mStore.Open(cCancelUri, 'objectpascal', 1, 'unit Unit1;'#10'interface   '#10'uses'#10'  Zeta, Alpha, Zeta;'#10 +
    'implementation'#10'end.');
  mDispatcher := nil;
  mFormatting := nil;
  try
    mDispatcher := TJsonRpcDispatcher.Create;
    mSortUses := True;
    mFormatting := TFormattingProtocol.Create(mStore,
      function(const AUri: string): TFormatStyle
      begin
        Result := TFormatStyle.Default;
        Result.SortUses := mSortUses;
      end, nil);
    mFormatting.SortUses := SortUsesEdits;
    mFormatting.Attach(mDispatcher);
    mResult := ResultOf(mDispatcher, cWhole);
    Assert.IsTrue(Pos('\n  Alpha, Zeta"', mResult) > 0, mResult);
    Assert.IsTrue(Pos('"newText":"interface"', mResult) > 0, 'Leerzeichen am Zeilenende: ' + mResult);
    // Auswahl: nur formatieren.
    mResult := ResultOf(mDispatcher, cRange);
    Assert.AreEqual(0, Pos('Alpha', mResult), mResult);
    mSortUses := False;
    mResult := ResultOf(mDispatcher, cWhole);
    Assert.AreEqual(0, Pos('Alpha', mResult), mResult);
  finally
    mFormatting.Free;
    mDispatcher.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TFormattingProtocolTests);

end.
