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
  UnitText =
    'unit Schalter;'#10 +   // 0
    '{$R-}'#10 +            // 1
    'interface'#10 +        // 2
    'implementation'#10 +   // 3
    'end.';

  FileName = 'C:\P\Schalter.pas';

function ProjectContext(const AUri: string): TCompilerSwitchContext;
begin
  Result := Default(TCompilerSwitchContext);
  Result.FileName := FileName;
  Result.HasProject := True;
  Result.Configuration := 'Debug';
  Result.Platform := 'Win64';
  Result.Input.Defines := TArray<string>.Create('DEBUG', '$R+', '$Q+');
end;

{ TLspCompilerSwitchesTests }

function TLspCompilerSwitchesTests.Answer(const AParams: string; AKnownDocument: Boolean): string;
var
  Store: IDocumentStore;
  Switches: TLspCompilerSwitches;
  Dispatcher: TJsonRpcDispatcher;
  Request, Response: TJSONObject;
  Value: TJSONValue;
begin
  Store := TDocumentStore.Create;
  if AKnownDocument then
    Store.Open(TDocumentUris.FromPath(FileName), 'delphi', 1, UnitText);
  Switches := TLspCompilerSwitches.Create(Store, ProjectContext);
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Switches.Attach(Dispatcher);
    Request := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"' + TLspCompilerSwitches.Method +
      '","params":' + AParams + '}') as TJSONObject;
    try
      Response := Dispatcher.DispatchMessage(Request);
    finally
      Request.Free;
    end;
    try
      Value := Response.GetValue('result');
      if Value = nil then
        Value := Response.GetValue('error');
      Result := Value.ToJSON;
    finally
      Response.Free;
    end;
  finally
    Dispatcher.Free;
    Switches.Free;
  end;
end;

function DocumentParams(ALine: Integer): string;
begin
  Result := '{"textDocument":{"uri":"' + TDocumentUris.FromPath(FileName).Replace('\', '\\') +
    '"},"position":{"line":' + IntToStr(ALine) + ',"character":0}}';
end;

procedure TLspCompilerSwitchesTests.StateAtUsesProjectDefines;
var
  State: TCompilerSwitchState;
begin
  State := TLspCompilerSwitches.StateAt(UnitText, TTextPosition.Create(0, 0), ProjectContext(''));
  Assert.AreEqual('R', State.Switches[0].Name);
  Assert.AreEqual('+', State.Switches[0].Value);
  Assert.AreEqual('', State.Summary);
  State := TLspCompilerSwitches.StateAt(UnitText, TTextPosition.Create(3, 0), ProjectContext(''));
  Assert.AreEqual('-', State.Switches[0].Value);
  Assert.AreEqual('R'#$2212, State.Summary);
end;

procedure TLspCompilerSwitchesTests.HandlerWritesSwitchesWithOrigin;
var
  Text: string;
begin
  Text := Answer(DocumentParams(3), True);
  Assert.IsTrue(Text.StartsWith('{"configuration":"Debug","platform":"Win64","hasProject":true,'), Text);
  Assert.IsTrue(Text.Contains('{"name":"R","longName":"RANGECHECKS","value":"-","projectValue":"+",' +
    '"deviates":true,"origin":{"kind":"directive","text":"{$R-}","file":"' + FileName.Replace('\', '\\') +
    '","line":1}}'), Text);
  Assert.IsTrue(Text.Contains('{"name":"DEBUG","origin":{"kind":"project"'), Text);
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
