unit Atlas.Core.Projects.Contract.Tests;

// Tests für den Projektkontext des Plugins (#396).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProjectContextTests = class
  public
    [Test]
    procedure SplitsOptionLists;
    [Test]
    procedure ReadsVersionFromRegistryKey;
    [Test]
    procedure KeyChangesWithEveryField;
    [Test]
    procedure WritesJson;
    [Test]
    procedure InheritsReferencedParentValues;
    [Test]
    procedure DescribesForTheLog;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Core.Projects.Contract;

function Sample: TAtlasProjectContext;
begin
  Result := Default(TAtlasProjectContext);
  Result.Project := 'C:\P\A.dproj';
  Result.Configuration := 'Debug';
  Result.Platform := 'Win32';
  Result.BdsVersion := '23.0';
  Result.Defines := ['DEBUG'];
  Result.SearchPaths := ['..\Lib'];
  Result.Namespaces := ['System', 'Vcl'];
end;

procedure TAtlasProjectContextTests.SplitsOptionLists;
begin
  Assert.AreEqual('DEBUG|$(DCC_Define)', string.Join('|', TAtlasProjectContext.List(' DEBUG ;;$(DCC_Define);')));
  Assert.AreEqual(0, Integer(Length(TAtlasProjectContext.List(''))));
end;

procedure TAtlasProjectContextTests.ReadsVersionFromRegistryKey;
begin
  Assert.AreEqual('23.0', TAtlasProjectContext.VersionOfRegistryKey('Software\Embarcadero\BDS\23.0'));
  Assert.AreEqual('37.0', TAtlasProjectContext.VersionOfRegistryKey('Software\Embarcadero\BDS\37.0\'));
  // Schlüssel ohne Versionsnummer am Ende: Der Server wählt die Version selbst.
  Assert.AreEqual('', TAtlasProjectContext.VersionOfRegistryKey('Software\Embarcadero\Profil'));
  Assert.AreEqual('', TAtlasProjectContext.VersionOfRegistryKey(''));
end;

procedure TAtlasProjectContextTests.KeyChangesWithEveryField;
var
  Base, Changed: TAtlasProjectContext;
begin
  Base := Sample;
  Changed := Sample;
  Assert.AreEqual(Base.Key, Changed.Key);
  Changed.Project := 'c:\p\a.dproj';
  Assert.AreEqual(Base.Key, Changed.Key, 'Pfad ohne Groß-/Kleinschreibung');
  Changed := Sample;
  Changed.Configuration := 'Release';
  Assert.AreNotEqual(Base.Key, Changed.Key);
  Changed := Sample;
  Changed.Platform := 'Win64';
  Assert.AreNotEqual(Base.Key, Changed.Key);
  Changed := Sample;
  Changed.Defines := ['DEBUG', 'TRACE'];
  Assert.AreNotEqual(Base.Key, Changed.Key);
  Changed := Sample;
  Changed.SearchPaths := nil;
  Assert.AreNotEqual(Base.Key, Changed.Key);
  Changed := Sample;
  Changed.LibraryPaths := ['$(BDSLIB)\$(Platform)\release'];
  Assert.AreNotEqual(Base.Key, Changed.Key);
  // Präfix-Vorgabe der Projektdatei (#452), auch eine leere.
  Changed := Sample;
  Changed.HasNaming[TAtlasProjectNamingKind.Field] := True;
  Assert.AreNotEqual(Base.Key, Changed.Key);
  Base := Changed;
  Changed.Naming[TAtlasProjectNamingKind.Field] := 'F';
  Assert.AreNotEqual(Base.Key, Changed.Key);
  // Wechsel des aktiven Projekts (#46).
  Changed := Sample;
  Changed.Active := True;
  Assert.AreNotEqual(Sample.Key, Changed.Key);
end;

procedure TAtlasProjectContextTests.WritesJson;
var
  Json: TJSONObject;
  Context: TAtlasProjectContext;
begin
  Json := Sample.ToJson;
  try
    Assert.AreEqual('C:\P\A.dproj', Json.GetValue<string>('project'));
    Assert.AreEqual('Win32', Json.GetValue<string>('platform'));
    Assert.AreEqual('23.0', Json.GetValue<string>('bdsVersion'));
    Assert.AreEqual('["DEBUG"]', Json.GetValue<TJSONArray>('defines').ToJSON);
    Assert.AreEqual('["System","Vcl"]', Json.GetValue<TJSONArray>('namespaces').ToJSON);
    // Ohne Bibliothekspfade nimmt der Server die der Installation.
    Assert.IsNull(Json.FindValue('libraryPaths'));
    Assert.IsNull(Json.FindValue('naming'));
    Assert.AreEqual('false', Json.GetValue('active').ToJSON);
  finally
    Json.Free;
  end;
  // Präfix-Vorgaben der Projektdatei (#452): nur die gesetzten, auch leer.
  Context := Sample;
  Context.HasNaming[TAtlasProjectNamingKind.Field] := True;
  Context.Naming[TAtlasProjectNamingKind.Field] := 'F';
  Context.HasNaming[TAtlasProjectNamingKind.Local] := True;
  Json := Context.ToJson;
  try
    Assert.AreEqual('{"field":"F","local":""}', Json.GetValue<TJSONObject>('naming').ToJSON);
  finally
    Json.Free;
  end;
  Context := Sample;
  Context.Active := True;
  Json := Context.ToJson;
  try
    Assert.AreEqual('true', Json.GetValue('active').ToJSON);
  finally
    Json.Free;
  end;
end;

procedure TAtlasProjectContextTests.InheritsReferencedParentValues;
begin
  Assert.AreEqual('DEBUG;FRAMEWORK_VCL;MSWINDOWS',
    TAtlasProjectContext.Inherit('DEBUG;$(DCC_Define)', 'DCC_Define', 'FRAMEWORK_VCL;MSWINDOWS'));
  // Groß-/Kleinschreibung wie bei MSBuild egal; leere Elternliste hinterlässt keinen leeren Eintrag.
  Assert.AreEqual('DEBUG', TAtlasProjectContext.Inherit('DEBUG;$(dcc_define)', 'DCC_Define', ''));
  // Ohne Verweis ersetzt der eigene Wert den geerbten.
  Assert.AreEqual('RELEASE', TAtlasProjectContext.Inherit('RELEASE', 'DCC_Define', 'DEBUG'));
  Assert.IsTrue(TAtlasProjectContext.RefersToItself('..\Lib;$(DCC_UnitSearchPath)', 'DCC_UnitSearchPath'));
  Assert.IsFalse(TAtlasProjectContext.RefersToItself('$(BDS)\Lib', 'DCC_UnitSearchPath'));
end;

procedure TAtlasProjectContextTests.DescribesForTheLog;
var
  Context: TAtlasProjectContext;
begin
  Context := Sample;
  Context.Source := TAtlasProjectContext.SourceConfiguration;
  Assert.AreEqual('A.dproj Debug/Win32 (Konfiguration, BDS 23.0): Defines DEBUG; 1 Suchpfade, 2 Namespaces, ' +
    '0 Bibliothekspfade', Context.Describe);
  // Die Herkunft gehört nur ins Protokoll: Der Server bekommt deshalb nichts Neues.
  Assert.AreEqual(Sample.Key, Context.Key);
  Context.Active := True;
  Assert.IsTrue(Context.Describe.EndsWith(', aktiv'), Context.Describe);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProjectContextTests);

end.
