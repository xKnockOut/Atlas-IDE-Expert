unit Lsp.Completion.Server.TestSupport;

// Gemeinsame Hilfen der Vervollständigungstests über das Protokoll: Vervollständigung hinter einem Dispatcher mit
// Index und Dokumenten, wie der Server sie anbietet.

interface

uses
  System.JSON,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Lsp.Completion,
  Lsp.Completion.Hooks;

type
  /// <summary>Vervollständigung über textDocument/completion mit eigenem Index und eigenen Dokumenten.</summary>
  TCompletionServer = class
  private
    FIndex: ISymbolIndex;
    FStore: IDocumentStore;
    FCompletion: TLspCompletion;
    FDispatcher: TJsonRpcDispatcher;
    FId: Integer;
  public
    /// <summary>ASettings liefert die Einstellungen je Anfrage.</summary>
    constructor Create(const ASettings: TCompletionSettingsFunc);
    destructor Destroy; override;
    /// <summary>Fragt an der Stelle von "|" in AText (Datei Haupt.pas). Der Aufrufer gibt frei.</summary>
    function Complete(const AText: string): TJSONObject;
    property Index: ISymbolIndex read FIndex;
    property Store: IDocumentStore read FStore;
  end;

/// <summary>Unit Haupt (uses Zaehler) mit Pruefe(AZaehler: TZaehler), ABody zwischen begin und end.</summary>
function HauptWith(const ABody: string): string;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.SysUtils,
  DUnitX.TestFramework,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Tests.SourceText;

const
  cHauptFile = 'C:\P\Haupt.pas';

function HauptWith(const ABody: string): string;
begin
  Result :=
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses Zaehler;'#13#10 +
    'implementation'#13#10 +
    'procedure Pruefe(AZaehler: TZaehler);'#13#10 +
    'begin'#13#10 +
    ABody + #13#10 +
    'end;'#13#10 +
    'end.';
end;

{ TCompletionServer }

constructor TCompletionServer.Create(const ASettings: TCompletionSettingsFunc);
begin
  inherited Create;
  FIndex := TSymbolIndex.Create;
  FStore := TDocumentStore.Create;
  FCompletion := TLspCompletion.Create(FStore, FIndex);
  FCompletion.Hooks.SettingsFor := ASettings;
  FDispatcher := TJsonRpcDispatcher.Create;
  FCompletion.Attach(FDispatcher);
end;

destructor TCompletionServer.Destroy;
begin
  FDispatcher.Free;
  FCompletion.Free;
  FStore := nil;
  FIndex := nil;
  inherited;
end;

function TCompletionServer.Complete(const AText: string): TJSONObject;
var
  mPosition: TTextPosition;
  mText, mUri: string;
  mRequest, mResponse: TJSONObject;
begin
  mText := TTestSource.Unmark(AText, mPosition);
  mUri := TDocumentUris.FromPath(cHauptFile);
  FStore.Close(mUri);
  FStore.Open(mUri, 'delphi', 1, mText);
  Inc(FId);
  mRequest := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":' + IntToStr(FId) +
    ',"method":"textDocument/completion","params":{"textDocument":{"uri":"' + mUri.Replace('\', '\\') +
    '"},"position":{"line":' + IntToStr(mPosition.Line) + ',"character":' + IntToStr(mPosition.Character) +
    '}}}') as TJSONObject;
  try
    mResponse := FDispatcher.DispatchMessage(mRequest);
  finally
    mRequest.Free;
  end;
  try
    Assert.IsTrue(mResponse.GetValue('result') is TJSONObject, mResponse.ToJSON);
    Result := mResponse.GetValue('result').Clone as TJSONObject;
  finally
    mResponse.Free;
  end;
end;

end.
