unit Atlas.Common.Rules.LibrarySources.Tests;

// Tests für fremde Quellen im Editor (diagnostics.librarySources).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLibrarySourcesTests = class
  public
    [Test]
    procedure InstallationSourceIsLibrary;
    [Test]
    procedure LibraryPathIsLibrary;
    [Test]
    procedure ProjectFolderWins;
    [Test]
    procedure OtherFileIsNotLibrary;
    [Test]
    procedure FolderContainingProjectIgnored;
    [Test]
    procedure RelativeAndMacroRootsIgnored;
    [Test]
    procedure SeparatorsAndCase;
  end;

implementation

uses
  Atlas.Common.Rules.LibrarySources;

const
  cBds = 'C:\Program Files (x86)\Embarcadero\Studio\37.0';

procedure TLibrarySourcesTests.InstallationSourceIsLibrary;
var
  mSources: TLibrarySources;
begin
  mSources := TLibrarySources.Create([cBds], ['C:\Projekte\Atlas']);
  Assert.IsTrue(mSources.IsLibraryFile(cBds + '\source\rtl\net\System.Net.HttpClient.pas'));
  Assert.IsTrue(mSources.IsLibraryFile(cBds + '\source\rtl\common\System.Generics.Defaults.pas'));
end;

procedure TLibrarySourcesTests.LibraryPathIsLibrary;
var
  mSources: TLibrarySources;
begin
  mSources := TLibrarySources.Create([cBds, 'C:\Komponenten\JVCL\run'], ['C:\Projekte\Atlas']);
  Assert.IsTrue(mSources.IsLibraryFile('C:\Komponenten\JVCL\run\JvButton.pas'));
  Assert.IsFalse(mSources.IsLibraryFile('C:\Komponenten\JVCL\design\JvDsgn.pas'));
end;

procedure TLibrarySourcesTests.ProjectFolderWins;
var
  mSources: TLibrarySources;
begin
  // Ein Bibliothekspfad, der in den Projektordner zeigt (eigene Komponenten im Repository).
  mSources := TLibrarySources.Create([cBds, 'C:\Projekte\Atlas\Komponenten'], ['C:\Projekte\Atlas']);
  Assert.IsFalse(mSources.IsLibraryFile('C:\Projekte\Atlas\Komponenten\MeinButton.pas'));
  Assert.IsFalse(mSources.IsLibraryFile('C:\Projekte\Atlas\Source\Main.pas'));
end;

procedure TLibrarySourcesTests.OtherFileIsNotLibrary;
var
  mSources: TLibrarySources;
begin
  mSources := TLibrarySources.Create([cBds], ['C:\Projekte\Atlas']);
  Assert.IsFalse(mSources.IsLibraryFile('C:\Temp\Versuch.pas'));
  // Nur ganze Ordnernamen: "37.0x" liegt nicht unter "37.0".
  Assert.IsFalse(mSources.IsLibraryFile(cBds + 'x\source\Foo.pas'));
  Assert.IsFalse(mSources.IsLibraryFile(''));
end;

procedure TLibrarySourcesTests.FolderContainingProjectIgnored;
var
  mSources: TLibrarySources;
begin
  // Suchpfad "C:\Projekte" enthält das Projekt: Nachbarprojekte sind deshalb nicht fremd.
  mSources := TLibrarySources.Create(['C:\Projekte'], ['C:\Projekte\Atlas']);
  Assert.IsFalse(mSources.IsLibraryFile('C:\Projekte\Anderes\Unit1.pas'));
end;

procedure TLibrarySourcesTests.RelativeAndMacroRootsIgnored;
var
  mSources: TLibrarySources;
begin
  mSources := TLibrarySources.Create(['.', '..\Lib', '$(BDSCOMMONDIR)\Dcp', ''], ['C:\Projekte\Atlas']);
  Assert.IsFalse(mSources.IsLibraryFile('C:\Projekte\Lib\Foo.pas'));
  Assert.IsFalse(mSources.IsLibraryFile('Foo.pas'));
end;

procedure TLibrarySourcesTests.SeparatorsAndCase;
var
  mSources: TLibrarySources;
begin
  mSources := TLibrarySources.Create([cBds + '\'], []);
  Assert.IsTrue(mSources.IsLibraryFile('c:/program files (x86)/embarcadero/studio/37.0/source/vcl/Vcl.Forms.pas'));
  Assert.IsTrue(TLibrarySources.IsUnder('/opt/delphi/source/System.pas', '/opt/delphi'));
end;

initialization
  TDUnitX.RegisterTestFixture(TLibrarySourcesTests);

end.
