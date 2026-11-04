unit Shell.Composition.Core.Tests;

// Kern der Komposition ohne Ordner: Text und Dateien kommen aus den geöffneten Dokumenten, die Teile bestehen ab
// dem Anlegen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract,
  Shell.Composition.Core;

type
  [TestFixture]
  TShellCoreTests = class
  private
    FDocuments: IDocumentStore;
    FCore: TShellCore;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Alle Teile bestehen ab dem Anlegen.</summary>
    [Test]
    procedure PartsExist;
    /// <summary>Ein geöffnetes Dokument hat Vorrang vor der Platte.</summary>
    [Test]
    procedure OpenDocumentWins;
    /// <summary>Ohne Ordner: Projekt- und Prüfdateien sind die geöffneten Dokumente.</summary>
    [Test]
    procedure FilesFromOpenDocuments;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Logging.Providers.Logger;

const
  cFile = 'C:\Projekt\Offen.pas';
  cText = 'unit Offen; interface implementation end.';

function NoIndex: ISymbolIndex;
begin
  Result := nil;
end;

function NoSelection(const AOrigin: string): string;
begin
  Result := '';
end;

function NoActive: string;
begin
  Result := '';
end;

procedure TShellCoreTests.Setup;
var
  mServices: TShellCoreServices;
begin
  FDocuments := TDocumentStore.Create;
  mServices := Default(TShellCoreServices);
  mServices.Logger := TLogger.Create;
  mServices.Documents := FDocuments;
  mServices.Index := NoIndex;
  mServices.SelectedProject := NoSelection;
  mServices.ActiveProject := NoActive;
  FCore := TShellCore.Create(mServices);
end;

procedure TShellCoreTests.TearDown;
begin
  FCore.FreeWorkspaces;
  FreeAndNil(FCore);
  FDocuments := nil;
end;

procedure TShellCoreTests.PartsExist;
begin
  Assert.IsNotNull(FCore.Workspaces);
  Assert.IsNotNull(FCore.Settings);
  Assert.IsNotNull(FCore.Configuration);
  Assert.IsNotNull(FCore.Folders);
  Assert.IsNotNull(FCore.RuleContext);
  Assert.IsNotNull(FCore.Sources);
  Assert.IsNotNull(FCore.Directives);
  Assert.IsNotNull(FCore.FileOptions);
end;

procedure TShellCoreTests.OpenDocumentWins;
var
  mText: string;
begin
  FDocuments.Open(TDocumentUris.FromPath(cFile), 'delphi', 1, cText);
  Assert.IsTrue(FCore.ReadText(cFile, mText));
  Assert.AreEqual(cText, mText);
end;

procedure TShellCoreTests.FilesFromOpenDocuments;
var
  mExpected: string;
begin
  Assert.AreEqual(0, Integer(Length(FCore.ProjectFiles)));
  FDocuments.Open(TDocumentUris.FromPath(cFile), 'delphi', 1, cText);
  mExpected := TDocumentUris.ToPath(TDocumentUris.FromPath(cFile));
  Assert.AreEqual(1, Integer(Length(FCore.ProjectFiles)));
  Assert.AreEqual(mExpected, FCore.ProjectFiles[0]);
  Assert.AreEqual(1, Integer(Length(FCore.CheckFiles)));
  Assert.AreEqual(mExpected, FCore.CheckFiles[0]);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellCoreTests);

end.
