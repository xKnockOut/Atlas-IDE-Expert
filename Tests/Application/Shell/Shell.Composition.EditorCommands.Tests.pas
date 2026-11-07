unit Shell.Composition.EditorCommands.Tests;

// Befehle des Plugins am Editor: Anmeldung in beiden Gruppen und Einstellungen der Zeichenkettenliterale über den
// Dienst der Komposition.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Configuration.Contract,
  Shell.Composition.EditorCommands;

type
  [TestFixture]
  TShellEditorCommandsTests = class
  private
    FLiteralCalls: Integer;
    function NewServices: TShellEditorCommandServices;
    function LiteralFor(const AUri: string; out AMultiline: Boolean): TStringLiteralSettings;
  public
    [Setup]
    procedure Setup;
    /// <summary>Markierungs- und Textbefehle stehen in executeCommandProvider.</summary>
    [Test]
    procedure RegistersAllCommands;
    /// <summary>„Text in Literal“ fragt die Einstellungen der Datei über den Dienst ab, bevor es die Argumente
    /// prüft.</summary>
    [Test]
    procedure ToLiteralAsksForSettings;
    /// <summary>atlas.server.smartIndent (#1827): falsche Argumente ergeben InvalidParams.</summary>
    [Test]
    procedure SmartIndentRejectsMissingLine;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.ExitPoints,
  Atlas.Common.Lsp.Reassigned,
  Atlas.Common.Lsp.ExpressionType,
  Atlas.Common.Lsp.MethodOrder,
  Atlas.Common.Lsp.OverrideMarks,
  Atlas.Common.Lsp.QualifiedNames,
  Atlas.Common.Lsp.EnumValueCommands,
  Atlas.Common.Lsp.ResourceStringCommands,
  Atlas.Common.Lsp.StringLiteralCommands,
  Atlas.Common.Lsp.SmartIndent;

procedure TShellEditorCommandsTests.Setup;
begin
  FLiteralCalls := 0;
end;

function TShellEditorCommandsTests.LiteralFor(const AUri: string; out AMultiline: Boolean): TStringLiteralSettings;
begin
  Inc(FLiteralCalls);
  AMultiline := False;
  Result := TStringLiteralSettings.Default;
end;

function TShellEditorCommandsTests.NewServices: TShellEditorCommandServices;
begin
  Result := Default(TShellEditorCommandServices);
  Result.Documents := TDocumentStore.Create;
  Result.StringLiteralFor := LiteralFor;
end;

procedure TShellEditorCommandsTests.RegistersAllCommands;
var
  mEditorCommands: TShellEditorCommands;
  mCommands: TLspCommands;
  mCapability: TJSONObject;
  mText: string;
  mName: string;
begin
  mEditorCommands := TShellEditorCommands.Create(NewServices);
  mCommands := TLspCommands.Create;
  try
    mEditorCommands.RegisterMarkCommands(mCommands);
    mEditorCommands.RegisterTextCommands(mCommands);
    mCapability := mCommands.Capability;
    try
      mText := mCapability.ToJSON;
    finally
      mCapability.Free;
    end;
    for mName in TArray<string>.Create(TLspExitPoints.cCommand, TLspReassigned.cCommand, TLspExpressionType.cCommand,
      TLspMethodOrder.cCommand, TLspOverrideMarks.cCommand, TQualifiedNames.cCommand, TEnumValueCommands.cCommand,
      TResourceStringCommands.cAddCommand, TStringLiteralCommands.cPlainTextCommand,
      TStringLiteralCommands.cToLiteralCommand, TLspSmartIndent.cCommand) do
    begin
      Assert.IsTrue(Pos('"' + mName + '"', mText) > 0, mName);
    end;
  finally
    mCommands.Free;
    mEditorCommands.Free;
  end;
end;

procedure TShellEditorCommandsTests.ToLiteralAsksForSettings;
var
  mEditorCommands: TShellEditorCommands;
  mCommands: TLspCommands;
  mArguments: TJSONArray;
  mResult: TJSONValue;
begin
  mEditorCommands := TShellEditorCommands.Create(NewServices);
  mCommands := TLspCommands.Create;
  mArguments := TJSONArray.Create;
  try
    mEditorCommands.RegisterTextCommands(mCommands);
    mArguments.Add('file:///tmp/A.pas');
    // Ohne Position lehnt der Befehl ab, die Einstellungen der Datei hat er da schon geholt.
    Assert.WillRaise(
      procedure
      begin
        mResult := mCommands.Execute(TStringLiteralCommands.cToLiteralCommand, mArguments);
        mResult.Free;
      end, EJsonRpcError);
    Assert.AreEqual(1, FLiteralCalls);
  finally
    mArguments.Free;
    mCommands.Free;
    mEditorCommands.Free;
  end;
end;

procedure TShellEditorCommandsTests.SmartIndentRejectsMissingLine;
var
  mEditorCommands: TShellEditorCommands;
  mCommands: TLspCommands;
  mArguments: TJSONArray;
  mResult: TJSONValue;
begin
  mEditorCommands := TShellEditorCommands.Create(NewServices);
  mCommands := TLspCommands.Create;
  mArguments := TJSONArray.Create;
  try
    mEditorCommands.RegisterTextCommands(mCommands);
    mArguments.Add('file:///tmp/A.pas');
    Assert.WillRaise(
      procedure
      begin
        mResult := mCommands.Execute(TLspSmartIndent.cCommand, mArguments);
        mResult.Free;
      end, EJsonRpcError);
  finally
    mArguments.Free;
    mCommands.Free;
    mEditorCommands.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellEditorCommandsTests);

end.
