unit Shell.Composition.Editing.Tests;

// Bearbeiten des Servers: Befehle des Erzeugen-Menüs werden angemeldet, der Host der Schnellbefehle kommt erst mit
// UseSlashHost.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Editing;

type
  [TestFixture]
  TShellEditingTests = class
  public
    /// <summary>Menü, Auswahl und Ausführen des Erzeugen-Menüs stehen in executeCommandProvider.</summary>
    [Test]
    procedure RegistersSlashMenuCommands;
    /// <summary>Vor UseSlashHost gibt es keinen Host der Schnellbefehle.</summary>
    [Test]
    procedure NoSlashHostBeforeUse;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.SlashMenu;

function NewServices: TShellEditingServices;
begin
  Result := Default(TShellEditingServices);
  Result.Documents := TDocumentStore.Create;
end;

procedure TShellEditingTests.RegistersSlashMenuCommands;
var
  mEditing: TShellEditing;
  mCommands: TLspCommands;
  mCapability: TJSONObject;
  mText: string;
begin
  mEditing := TShellEditing.Create(NewServices);
  mCommands := TLspCommands.Create;
  try
    mEditing.RegisterCommands(mCommands);
    mCapability := mCommands.Capability;
    try
      mText := mCapability.ToJSON;
    finally
      mCapability.Free;
    end;
    Assert.IsTrue(Pos('"' + TLspSlashMenu.MenuCommand + '"', mText) > 0, TLspSlashMenu.MenuCommand);
    Assert.IsTrue(Pos('"' + TLspSlashMenu.ChoicesCommand + '"', mText) > 0, TLspSlashMenu.ChoicesCommand);
    Assert.IsTrue(Pos('"' + TLspSlashMenu.RunCommand + '"', mText) > 0, TLspSlashMenu.RunCommand);
  finally
    mCommands.Free;
    mEditing.Free;
  end;
end;

procedure TShellEditingTests.NoSlashHostBeforeUse;
var
  mEditing: TShellEditing;
begin
  mEditing := TShellEditing.Create(NewServices);
  try
    Assert.IsTrue(mEditing.SlashHost = nil);
  finally
    mEditing.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellEditingTests);

end.
