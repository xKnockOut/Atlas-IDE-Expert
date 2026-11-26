unit Lsp.Implementations.Tests;

// Anfrage textDocument/implementation über den Dispatcher; die Ziele selbst prüft
// Atlas.Common.Semantics.Implementations.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspImplementationsTests = class
  public
    /// <summary>Die Antwort nennt je Ziel Datei und Namen als Location.</summary>
    [Test]
    procedure AnswersWithLocations;
    /// <summary>Ein unbekanntes Dokument ergibt null.</summary>
    [Test]
    procedure UnknownDocumentIsNull;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Lsp.Implementations;

const
  cHauptFile = 'C:\P\Haupt.pas';

  cUnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TBasis = class'#10 +
    '    procedure Zeichne; virtual;'#10 +
    '  end;'#10 +
    '  TBlatt = class(TBasis)'#10 +
    '    procedure Zeichne; override;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TBasis.Zeichne;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TBlatt.Zeichne;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

/// <summary>Antwort des Dispatchers auf textDocument/implementation an Zeile ALine, Spalte ACharacter von AUri.
/// </summary>
function Answer(const AStore: IDocumentStore; const AUri: string; ALine, ACharacter: Integer): TJSONObject;
var
  mIndex: ISymbolIndex;
  mFeature: TLspImplementations;
  mDispatcher: TJsonRpcDispatcher;
  mMessage: TJSONObject;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitHaupt, cHauptFile, nil));
  mFeature := nil;
  mDispatcher := nil;
  mMessage := nil;
  try
    mFeature := TLspImplementations.Create(AStore, mIndex);
    mDispatcher := TJsonRpcDispatcher.Create;
    mFeature.Attach(mDispatcher);
    mMessage := TJSONObject.ParseJSONValue(Format('{"jsonrpc":"2.0","id":1,"method":"%s","params":' +
      '{"textDocument":{"uri":"%s"},"position":{"line":%d,"character":%d}}}',
      [TLspImplementations.cMethod, AUri.Replace('\', '\\'), ALine, ACharacter])) as TJSONObject;
    Result := mDispatcher.DispatchMessage(mMessage);
  finally
    mMessage.Free;
    mDispatcher.Free;
    mFeature.Free;
  end;
end;

{ TLspImplementationsTests }

procedure TLspImplementationsTests.AnswersWithLocations;
var
  mStore: IDocumentStore;
  mUri: string;
  mResponse: TJSONObject;
  mLines: string;
  mItem: TJSONValue;
begin
  mStore := TDocumentStore.Create;
  mUri := TDocumentUris.FromPath(cHauptFile);
  mStore.Open(mUri, 'delphi', 1, cUnitHaupt);
  // Auf "Zeichne" in TBasis: der eigene Rumpf und der überschreibende.
  mResponse := Answer(mStore, mUri, 4, 15);
  try
    Assert.IsTrue(mResponse.GetValue('result') is TJSONArray, mResponse.ToJSON);
    mLines := '';
    for mItem in TJSONArray(mResponse.GetValue('result')) do
    begin
      Assert.AreEqual(mUri, mItem.GetValue<string>('uri'));
      mLines := mLines + IntToStr(mItem.GetValue<Integer>('range.start.line')) + ' ';
    end;
    Assert.AreEqual('10 13', Trim(mLines));
  finally
    mResponse.Free;
    mStore := nil;
  end;
end;

procedure TLspImplementationsTests.UnknownDocumentIsNull;
var
  mStore: IDocumentStore;
  mResponse: TJSONObject;
begin
  mStore := TDocumentStore.Create;
  mResponse := Answer(mStore, TDocumentUris.FromPath(cHauptFile), 4, 15);
  try
    Assert.IsTrue(mResponse.GetValue('result') is TJSONNull, mResponse.ToJSON);
  finally
    mResponse.Free;
    mStore := nil;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspImplementationsTests);

end.
