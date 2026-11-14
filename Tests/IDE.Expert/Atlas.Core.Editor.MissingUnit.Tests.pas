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
  mRequest: TAtlasSearchPathRequest;
begin
  Assert.IsTrue(TAtlasSearchPathRequest.TryParse('["C:\\Projekt\\Kasse.dproj", "Source\\Common", "Debug"]',
    mRequest));
  Assert.AreEqual('C:\Projekt\Kasse.dproj', mRequest.ProjectFile);
  Assert.AreEqual('Source\Common', mRequest.Folder);
  Assert.AreEqual('Debug', mRequest.Config);
end;

procedure TAtlasMissingUnitTests.BaseMeansAllConfigurations;
var
  mRequest: TAtlasSearchPathRequest;
begin
  Assert.IsTrue(TAtlasSearchPathRequest.TryParse('["K.dproj", "Lib", ""]', mRequest));
  Assert.AreEqual('', mRequest.Config);
  Assert.IsTrue(TAtlasSearchPathRequest.TryParse('["K.dproj", "Lib", "Base"]', mRequest));
  Assert.AreEqual('', mRequest.Config);
  Assert.IsTrue(TAtlasSearchPathRequest.TryParse('["K.dproj", "Lib"]', mRequest));
  Assert.AreEqual('', mRequest.Config);
end;

procedure TAtlasMissingUnitTests.RefusesIncompleteArguments;
var
  mRequest: TAtlasSearchPathRequest;
begin
  Assert.IsFalse(TAtlasSearchPathRequest.TryParse('["K.dproj"]', mRequest));
  Assert.IsFalse(TAtlasSearchPathRequest.TryParse('["", "Lib"]', mRequest));
  Assert.IsFalse(TAtlasSearchPathRequest.TryParse('["K.dproj", "A;B"]', mRequest), 'nur ein Ordner');
  Assert.IsFalse(TAtlasSearchPathRequest.TryParse('{kaputt', mRequest));
end;

procedure TAtlasMissingUnitTests.ParsesAddUnit;
var
  mRequest: TAtlasAddUnitRequest;
begin
  Assert.IsTrue(TAtlasAddUnitRequest.TryParse('["K.dproj", "C:\\Projekt\\Source\\Werkzeug.pas"]', mRequest));
  Assert.AreEqual('C:\Projekt\Source\Werkzeug.pas', mRequest.FileName);
  Assert.IsFalse(TAtlasAddUnitRequest.TryParse('["K.dproj", "C:\\Lib\\Fertig.dcu"]', mRequest),
    'eine .dcu kommt nicht ins Projekt');
end;

procedure TAtlasMissingUnitTests.ParsesInfo;
var
  mText: string;
begin
  Assert.IsTrue(TAtlasSearchPaths.TryParseInfo('["Fehlt nicht gefunden"]', mText));
  Assert.AreEqual('Fehlt nicht gefunden', mText);
  Assert.IsFalse(TAtlasSearchPaths.TryParseInfo('[]', mText));
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
