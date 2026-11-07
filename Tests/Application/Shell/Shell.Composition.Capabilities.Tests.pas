unit Shell.Composition.Capabilities.Tests;

// Capabilities für initialize: Anbieter der Features und die Befehle für workspace/executeCommand.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellCapabilitiesTests = class
  public
    /// <summary>Die wichtigsten Anbieter sind gemeldet.</summary>
    [Test]
    procedure ReportsProviders;
    /// <summary>Die Befehle enthalten Status und Neuversuch eines Absturzfalls.</summary>
    [Test]
    procedure ReportsCommands;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Lsp.Status,
  Shell.CrashCases,
  Shell.Composition.Capabilities;

procedure TShellCapabilitiesTests.ReportsProviders;
var
  mCapabilities: TJSONObject;
begin
  mCapabilities := TShellCapabilities.Build;
  try
    Assert.IsNotNull(mCapabilities.GetValue('textDocumentSync'));
    Assert.IsNotNull(mCapabilities.GetValue('definitionProvider'));
    Assert.IsNotNull(mCapabilities.GetValue('completionProvider'));
    Assert.IsNotNull(mCapabilities.GetValue('workspace'));
  finally
    mCapabilities.Free;
  end;
end;

procedure TShellCapabilitiesTests.ReportsCommands;
var
  mCapabilities: TJSONObject;
  mCommands: TJSONArray;
  mItem: TJSONValue;
  mNames: TArray<string>;
begin
  mCapabilities := TShellCapabilities.Build;
  try
    mCommands := mCapabilities.GetValue<TJSONArray>('executeCommandProvider.commands');
    mNames := nil;
    for mItem in mCommands do
    begin
      mNames := mNames + [mItem.Value];
    end;
  finally
    mCapabilities.Free;
  end;
  Assert.IsTrue(string.Join(';', mNames).Contains(cStatusCommand), 'Status');
  Assert.IsTrue(string.Join(';', mNames).Contains(TShellCrashCases.cRetryCommand), 'Neuversuch');
end;

initialization
  TDUnitX.RegisterTestFixture(TShellCapabilitiesTests);

end.
