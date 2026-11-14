unit Atlas.Common.Lsp.CompilerSwitches.Tests;

// Anfrage atlas/compilerSwitches (#558): Stand an der Position mit den
// Symbolen des Projekts, JSON-Antwort mit Herkunft je Schalter, unbekannte
// Datei liefert null, fehlende Parameter einen Fehler.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspCompilerSwitchesTests = class
  private
    /// <summary>Antwort (result bzw. error) auf AParams als JSON-Text.</summary>
    function Answer(const AParams: string; AKnownDocument: Boolean): string;
  public
    [Test]
    procedure StateAtUsesProjectDefines;
    [Test]
    procedure HandlerWritesSwitchesWithOrigin;
    [Test]
    procedure UnknownDocumentGivesNull;
    [Test]
    procedure MissingPositionIsInvalidParams;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Pascal.CompilerSwitches,
  Atlas.Common.Lsp.CompilerSwitches;

const
  cUnitText =
    'unit Schalter;'#10 +   // 0
    '{$R-}'#10 +            // 1
    'interface'#10 +        // 2
    'implementation'#10 +   // 3
    'end.';

  cFileName = 'C:\P\Schalter.pas';

function ProjectContext(const AUri: string): TCompilerSwitchContext;
begin
  Result := Default(TCompilerSwitchContext);
  Result.FileName := cFileName;
  Result.HasProject := True;
  Result.Configuration := 'Debug';
  Result.Platform := 'Win64';
  Result.Input.Defines := TArray<string>.Create('DEBUG', '$R+', '$Q+');
end;

{ TLspCompilerSwitchesTests }

function TLspCompilerSwitchesTests.Answer(const AParams: string; AKnownDocument: Boolean): string;
var
  mStore: IDocumentStore;
  mSwitches: TLspCompilerSwitches;
  mDispatcher: TJsonRpcDispatcher;
  mRequest, mResponse: TJSONObject;
  mValue: TJSONValue;
begin
  mStore := TDocumentStore.Create;
  if AKnownDocument then
  begin
    mStore.Open(TDocumentUris.FromPath(cFileName), 'delphi', 1, cUnitText);
  end;
  mSwitches := TLspCompilerSwitches.Create(mStore, ProjectContext);
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mSwitches.Attach(mDispatcher);
    mRequest := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"' + TLspCompilerSwitches.cMethod +
      '","params":' + AParams + '}') as TJSONObject;
    try
      mResponse := mDispatcher.DispatchMessage(mRequest);
    finally
      mRequest.Free;
    end;
    try
      mValue := mResponse.GetValue('result');
      if mValue = nil then
      begin
        mValue := mResponse.GetValue('error');
      end;
      Result := mValue.ToJSON;
    finally
      mResponse.Free;
    end;
  finally
    mDispatcher.Free;
    mSwitches.Free;
  end;
end;

function DocumentParams(ALine: Integer): string;
begin
  Result := '{"textDocument":{"uri":"' + TDocumentUris.FromPath(cFileName).Replace('\', '\\') +
    '"},"position":{"line":' + IntToStr(ALine) + ',"character":0}}';
end;

procedure TLspCompilerSwitchesTests.StateAtUsesProjectDefines;
var
  mState: TCompilerSwitchState;
begin
  mState := TLspCompilerSwitches.StateAt(cUnitText, TTextPosition.Create(0, 0), ProjectContext(''));
  Assert.AreEqual('R', mState.Switches[0].Name);
  Assert.AreEqual('+', mState.Switches[0].Value);
  Assert.AreEqual('', mState.Summary);
  mState := TLspCompilerSwitches.StateAt(cUnitText, TTextPosition.Create(3, 0), ProjectContext(''));
  Assert.AreEqual('-', mState.Switches[0].Value);
  Assert.AreEqual('R'#$2212, mState.Summary);
end;

procedure TLspCompilerSwitchesTests.HandlerWritesSwitchesWithOrigin;
var
  mText: string;
begin
  mText := Answer(DocumentParams(3), True);
  Assert.IsTrue(mText.StartsWith('{"configuration":"Debug","platform":"Win64","hasProject":true,'), mText);
  Assert.IsTrue(mText.Contains('{"name":"R","longName":"RANGECHECKS","value":"-","projectValue":"+",' +
    '"deviates":true,"origin":{"kind":"directive","text":"{$R-}","file":"' + cFileName.Replace('\', '\\') +
    '","line":1}}'), mText);
  Assert.IsTrue(mText.Contains('{"name":"DEBUG","origin":{"kind":"project"'), mText);
end;

procedure TLspCompilerSwitchesTests.UnknownDocumentGivesNull;
begin
  Assert.AreEqual('null', Answer(DocumentParams(3), False));
end;

procedure TLspCompilerSwitchesTests.MissingPositionIsInvalidParams;
begin
  Assert.IsTrue(Answer('{"textDocument":{"uri":"file:///x.pas"}}', True).Contains('-32602'));
end;

end.
