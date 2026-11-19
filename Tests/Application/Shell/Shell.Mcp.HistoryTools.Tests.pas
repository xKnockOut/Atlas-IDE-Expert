unit Shell.Mcp.HistoryTools.Tests;

// Anmeldung von get_symbol_history (#2641): Name und Schema des Werkzeugs, ungültige Argumente als Werkzeugfehler,
// bevor Einstellungen oder Versionsverwaltung gelesen werden.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellMcpHistoryToolsTests = class
  public
    [Test]
    procedure RegistersToolWithSchema;
    [Test]
    procedure MissingNameIsToolError;
    [Test]
    procedure LimitOutOfRangeIsToolError;
    [Test]
    procedure UnknownFormatIsToolError;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.SysUtils,
  System.JSON,
  Atlas.Common.Mcp.Server,
  Shell.Mcp.Context,
  Shell.Mcp.HistoryTools;

/// <summary>Server nur mit get_symbol_history; der Kontext hat keine Gruppe, gültige Aufrufe gingen fehl.</summary>
function NewServer: TMcpServer;
var
  mContext: TMcpToolContext;
begin
  Result := TMcpServer.Create('Atlas', '0');
  mContext := Default(TMcpToolContext);
  mContext.Server := Result;
  RegisterSymbolHistoryTool(mContext);
end;

/// <summary>Text der Antwort auf get_symbol_history mit AArguments; AIsError aus isError.</summary>
function CallText(const AArguments: string; out AIsError: Boolean): string;
var
  mServer: TMcpServer;
  mParams: TJSONValue;
  mAnswer: TJSONObject;
begin
  mServer := NewServer;
  try
    mParams := TJSONObject.ParseJSONValue('{"name":"get_symbol_history","arguments":' + AArguments + '}');
    try
      mAnswer := mServer.CallTool(mParams);
      try
        AIsError := mAnswer.GetValue<Boolean>('isError', False);
        Result := mAnswer.GetValue<TJSONArray>('content').Items[0].GetValue<string>('text');
      finally
        mAnswer.Free;
      end;
    finally
      mParams.Free;
    end;
  finally
    mServer.Free;
  end;
end;

procedure TShellMcpHistoryToolsTests.RegistersToolWithSchema;
var
  mServer: TMcpServer;
  mListed: TJSONObject;
  mTools: TJSONArray;
  mSchema: TJSONObject;
begin
  mServer := NewServer;
  try
    mListed := mServer.ListTools;
    try
      mTools := mListed.GetValue<TJSONArray>('tools');
      Assert.AreEqual(1, mTools.Count);
      Assert.AreEqual('get_symbol_history', mTools.Items[0].GetValue<string>('name'));
      mSchema := mTools.Items[0].GetValue<TJSONObject>('inputSchema');
      Assert.AreEqual('["name"]', mSchema.GetValue<TJSONArray>('required').ToJSON);
      Assert.IsNotNull(mSchema.GetValue<TJSONObject>('properties').GetValue('followMoves'));
      Assert.AreEqual(200, mSchema.GetValue<TJSONObject>('properties').GetValue<TJSONObject>('limit').GetValue<Integer>(
        'maximum'));
    finally
      mListed.Free;
    end;
  finally
    mServer.Free;
  end;
end;

procedure TShellMcpHistoryToolsTests.MissingNameIsToolError;
var
  mIsError: Boolean;
begin
  Assert.StartsWith('"name"', CallText('{"name":"  "}', mIsError));
  Assert.IsTrue(mIsError);
end;

procedure TShellMcpHistoryToolsTests.LimitOutOfRangeIsToolError;
var
  mIsError: Boolean;
begin
  Assert.StartsWith('"limit"', CallText('{"name":"TFoo.Bar","limit":0}', mIsError));
  Assert.IsTrue(mIsError);
  Assert.StartsWith('"limit"', CallText('{"name":"TFoo.Bar","limit":201}', mIsError));
  Assert.IsTrue(mIsError);
end;

procedure TShellMcpHistoryToolsTests.UnknownFormatIsToolError;
var
  mIsError: Boolean;
begin
  Assert.Contains(CallText('{"name":"TFoo.Bar","format":"xml"}', mIsError), 'markdown');
  Assert.IsTrue(mIsError);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellMcpHistoryToolsTests);

end.
