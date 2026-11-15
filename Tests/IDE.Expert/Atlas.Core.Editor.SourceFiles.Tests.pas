unit Atlas.Core.Editor.SourceFiles.Tests;

// Welche Dateien die Editorfunktionen bearbeiten: Endungen ohne Rücksicht auf Groß-/Kleinschreibung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSourceFilesTests = class
  public
    [Test]
    procedure PascalIncludesIncludeFiles;
    [Test]
    procedure CompiledLeavesOutIncludeFiles;
    [Test]
    procedure UsesOnlyInUnitsAndPrograms;
    [Test]
    procedure ProjectFiles;
  end;

implementation

uses
  Atlas.Core.Editor.SourceFiles;

{ TAtlasSourceFilesTests }

procedure TAtlasSourceFilesTests.PascalIncludesIncludeFiles;
begin
  Assert.IsTrue(TAtlasSourceFiles.IsPascal('C:\Src\Main.pas'));
  Assert.IsTrue(TAtlasSourceFiles.IsPascal('Projekt.DPR'));
  Assert.IsTrue(TAtlasSourceFiles.IsPascal('Paket.dpk'));
  Assert.IsTrue(TAtlasSourceFiles.IsPascal('defines.Inc'));
  Assert.IsFalse(TAtlasSourceFiles.IsPascal('Main.dfm'));
  Assert.IsFalse(TAtlasSourceFiles.IsPascal('Projekt.dproj'));
  Assert.IsFalse(TAtlasSourceFiles.IsPascal(''));
end;

procedure TAtlasSourceFilesTests.CompiledLeavesOutIncludeFiles;
begin
  Assert.IsTrue(TAtlasSourceFiles.IsCompiled('Main.PAS'));
  Assert.IsTrue(TAtlasSourceFiles.IsCompiled('Paket.dpk'));
  Assert.IsFalse(TAtlasSourceFiles.IsCompiled('defines.inc'));
end;

procedure TAtlasSourceFilesTests.UsesOnlyInUnitsAndPrograms;
begin
  Assert.IsTrue(TAtlasSourceFiles.HasUses('Main.pas'));
  Assert.IsTrue(TAtlasSourceFiles.HasUses('Projekt.dpr'));
  Assert.IsFalse(TAtlasSourceFiles.HasUses('Paket.dpk'));
  Assert.IsFalse(TAtlasSourceFiles.HasUses('defines.inc'));
end;

procedure TAtlasSourceFilesTests.ProjectFiles;
begin
  Assert.IsTrue(TAtlasSourceFiles.IsProjectFile('Projekt.dproj'));
  Assert.IsTrue(TAtlasSourceFiles.IsProjectFile('Gruppe.GROUPPROJ'));
  Assert.IsTrue(TAtlasSourceFiles.IsProjectFile('Projekt.dpr'));
  Assert.IsTrue(TAtlasSourceFiles.IsProjectFile('Paket.dpk'));
  Assert.IsFalse(TAtlasSourceFiles.IsProjectFile('Main.pas'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSourceFilesTests);

end.
