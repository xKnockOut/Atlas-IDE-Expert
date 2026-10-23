unit Atlas.Core.Editor.MissingUnit.Tests;

// Tests für die Argumente der Client-Befehle zu „Unit nicht gefunden“ und die
// neue Suchpfadliste (#550).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasMissingUnitTests = class
  public
    [Test]
    procedure ParsesSearchPath;
    [Test]
    procedure BaseMeansAllConfigurations;
    [Test]
    procedure RefusesIncompleteArguments;
    [Test]
    procedure ParsesAddUnit;
    [Test]
    procedure ParsesInfo;
    [Test]
    procedure ContainsIgnoresCaseAndSeparator;
    /// <summary>Abnahme: Ein Suchpfad, der nur in Debug steht, kommt nach Release, ohne das Geerbte zu
    /// verlieren.</summary>
    [Test]
    procedure WithFolderKeepsInherited;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Editor.MissingUnit;

procedure TAtlasMissingUnitTests.ParsesSearchPath;
var
  Request: TAtlasSearchPathRequest;
begin
  Assert.IsTrue(TAtlasSearchPathRequest.TryParse('["C:\\Projekt\\Kasse.dproj", "Source\\Common", "Debug"]',
    Request));
  Assert.AreEqual('C:\Projekt\Kasse.dproj', Request.ProjectFile);
  Assert.AreEqual('Source\Common', Request.Folder);
  Assert.AreEqual('Debug', Request.Config);
end;

procedure TAtlasMissingUnitTests.BaseMeansAllConfigurations;
var
  Request: TAtlasSearchPathRequest;
begin
  Assert.IsTrue(TAtlasSearchPathRequest.TryParse('["K.dproj", "Lib", ""]', Request));
  Assert.AreEqual('', Request.Config);
  Assert.IsTrue(TAtlasSearchPathRequest.TryParse('["K.dproj", "Lib", "Base"]', Request));
  Assert.AreEqual('', Request.Config);
  Assert.IsTrue(TAtlasSearchPathRequest.TryParse('["K.dproj", "Lib"]', Request));
  Assert.AreEqual('', Request.Config);
end;

procedure TAtlasMissingUnitTests.RefusesIncompleteArguments;
var
  Request: TAtlasSearchPathRequest;
begin
  Assert.IsFalse(TAtlasSearchPathRequest.TryParse('["K.dproj"]', Request));
  Assert.IsFalse(TAtlasSearchPathRequest.TryParse('["", "Lib"]', Request));
  Assert.IsFalse(TAtlasSearchPathRequest.TryParse('["K.dproj", "A;B"]', Request), 'nur ein Ordner');
  Assert.IsFalse(TAtlasSearchPathRequest.TryParse('{kaputt', Request));
end;

procedure TAtlasMissingUnitTests.ParsesAddUnit;
var
  Request: TAtlasAddUnitRequest;
begin
  Assert.IsTrue(TAtlasAddUnitRequest.TryParse('["K.dproj", "C:\\Projekt\\Source\\Werkzeug.pas"]', Request));
  Assert.AreEqual('C:\Projekt\Source\Werkzeug.pas', Request.FileName);
  Assert.IsFalse(TAtlasAddUnitRequest.TryParse('["K.dproj", "C:\\Lib\\Fertig.dcu"]', Request),
    'eine .dcu kommt nicht ins Projekt');
end;

procedure TAtlasMissingUnitTests.ParsesInfo;
var
  Text: string;
begin
  Assert.IsTrue(TAtlasSearchPaths.TryParseInfo('["Fehlt nicht gefunden"]', Text));
  Assert.AreEqual('Fehlt nicht gefunden', Text);
  Assert.IsFalse(TAtlasSearchPaths.TryParseInfo('[]', Text));
end;

procedure TAtlasMissingUnitTests.ContainsIgnoresCaseAndSeparator;
begin
  Assert.IsTrue(TAtlasSearchPaths.Contains('..\Lib;source\common\;$(DCC_UnitSearchPath)', 'Source\Common'));
  Assert.IsFalse(TAtlasSearchPaths.Contains('..\Lib;Source', 'Source\Common'));
  Assert.IsFalse(TAtlasSearchPaths.Contains('', 'Source'));
end;

procedure TAtlasMissingUnitTests.WithFolderKeepsInherited;
begin
  Assert.AreEqual('..\Gemeinsam\Debug;$(DCC_UnitSearchPath)',
    TAtlasSearchPaths.WithFolder('', '..\Gemeinsam\Debug', False), 'Release ohne eigenen Wert erbt weiter');
  Assert.AreEqual('Lib;Source;$(DCC_UnitSearchPath)', TAtlasSearchPaths.WithFolder('Source;$(DCC_UnitSearchPath)',
    'Lib', False));
  Assert.AreEqual('Lib', TAtlasSearchPaths.WithFolder('', 'Lib', True), 'die Basis erbt nichts');
  Assert.AreEqual('Lib;Alt', TAtlasSearchPaths.WithFolder('Alt', 'Lib', True));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMissingUnitTests);

end.
