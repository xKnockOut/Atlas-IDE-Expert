unit Atlas.Core.Designer.FormStore.Tests;

// Tests für die Ablage von Formulardaten der Designer-Werkzeuge: Schlüssel
// und Datei, geteilt neben dem Formular oder lokal.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasDesignerFormStoreTests = class
  public
    [Test]
    procedure KeySharedIsFileName;
    [Test]
    procedure SharedFileBesideForm;
    [Test]
    procedure LocalFileUnderLocalData;
    [Test]
    procedure LocalFileFallsBackToTemp;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Designer.FormStore;

const
  cForm = 'Projekt' + PathDelim + 'Main.dfm';
  cShared = '.atlas-test.json';
  cLocal = 'designer-test.json';

{ TAtlasDesignerFormStoreTests }

procedure TAtlasDesignerFormStoreTests.KeySharedIsFileName;
begin
  Assert.AreEqual('Main.dfm', TAtlasDesignerFormStore.FormKey(cForm, True));
  Assert.AreEqual(cForm, TAtlasDesignerFormStore.FormKey(cForm, False));
end;

procedure TAtlasDesignerFormStoreTests.SharedFileBesideForm;
begin
  Assert.AreEqual(TPath.Combine('Projekt', cShared),
    TAtlasDesignerFormStore.StorePath(cForm, True, 'lokal', 'temp', cShared, cLocal));
end;

procedure TAtlasDesignerFormStoreTests.LocalFileUnderLocalData;
begin
  Assert.AreEqual(TPath.Combine(TPath.Combine('lokal', 'Atlas'), cLocal),
    TAtlasDesignerFormStore.StorePath(cForm, False, 'lokal', 'temp', cShared, cLocal));
end;

procedure TAtlasDesignerFormStoreTests.LocalFileFallsBackToTemp;
begin
  Assert.AreEqual(TPath.Combine(TPath.Combine('temp', 'Atlas'), cLocal),
    TAtlasDesignerFormStore.StorePath(cForm, False, '', 'temp', cShared, cLocal));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDesignerFormStoreTests);

end.
