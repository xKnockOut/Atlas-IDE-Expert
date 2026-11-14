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
  mBase, mChanged: TAtlasProjectContext;
begin
  mBase := Sample;
  mChanged := Sample;
  Assert.AreEqual(mBase.Key, mChanged.Key);
  mChanged.Project := 'c:\p\a.dproj';
  Assert.AreEqual(mBase.Key, mChanged.Key, 'Pfad ohne Groß-/Kleinschreibung');
  mChanged := Sample;
  mChanged.Configuration := 'Release';
  Assert.AreNotEqual(mBase.Key, mChanged.Key);
  mChanged := Sample;
  mChanged.Platform := 'Win64';
  Assert.AreNotEqual(mBase.Key, mChanged.Key);
  mChanged := Sample;
  mChanged.Defines := ['DEBUG', 'TRACE'];
  Assert.AreNotEqual(mBase.Key, mChanged.Key);
  mChanged := Sample;
  mChanged.SearchPaths := nil;
  Assert.AreNotEqual(mBase.Key, mChanged.Key);
  mChanged := Sample;
  mChanged.LibraryPaths := ['$(BDSLIB)\$(Platform)\release'];
  Assert.AreNotEqual(mBase.Key, mChanged.Key);
  // Präfix-Vorgabe der Projektdatei (#452), auch eine leere.
  mChanged := Sample;
  mChanged.HasNaming[TAtlasProjectNamingKind.Field] := True;
  Assert.AreNotEqual(mBase.Key, mChanged.Key);
  mBase := mChanged;
  mChanged.Naming[TAtlasProjectNamingKind.Field] := 'F';
  Assert.AreNotEqual(mBase.Key, mChanged.Key);
  // Wechsel des aktiven Projekts (#46).
  mChanged := Sample;
  mChanged.Active := True;
  Assert.AreNotEqual(Sample.Key, mChanged.Key);
  // Eigene Formatroutine der Projektdatei (#451).
  mChanged := Sample;
  SetLength(mChanged.FormatFunctions, 1);
  mChanged.FormatFunctions[0].Name := 'Log';
  mChanged.FormatFunctions[0].FormatIndex := 0;
  Assert.AreNotEqual(Sample.Key, mChanged.Key);
end;

procedure TAtlasProjectContextTests.WritesJson;
var
  mJson: TJSONObject;
  mContext: TAtlasProjectContext;
begin
  mJson := Sample.ToJson;
  try
    Assert.AreEqual('C:\P\A.dproj', mJson.GetValue<string>('project'));
    Assert.AreEqual('Win32', mJson.GetValue<string>('platform'));
    Assert.AreEqual('23.0', mJson.GetValue<string>('bdsVersion'));
    Assert.AreEqual('["DEBUG"]', mJson.GetValue<TJSONArray>('defines').ToJSON);
    Assert.AreEqual('["System","Vcl"]', mJson.GetValue<TJSONArray>('namespaces').ToJSON);
    // Ohne Bibliothekspfade nimmt der Server die der Installation.
    Assert.IsNull(mJson.FindValue('libraryPaths'));
    Assert.IsNull(mJson.FindValue('naming'));
    Assert.AreEqual('false', mJson.GetValue('active').ToJSON);
  finally
    mJson.Free;
  end;
  // Präfix-Vorgaben der Projektdatei (#452): nur die gesetzten, auch leer.
  mContext := Sample;
  mContext.HasNaming[TAtlasProjectNamingKind.Field] := True;
  mContext.Naming[TAtlasProjectNamingKind.Field] := 'F';
  mContext.HasNaming[TAtlasProjectNamingKind.Local] := True;
  // Konstanten für naming-prefix (#1111).
  mContext.HasNaming[TAtlasProjectNamingKind.Constant] := True;
  mContext.Naming[TAtlasProjectNamingKind.Constant] := 'c';
  mJson := mContext.ToJson;
  try
    Assert.AreEqual('{"field":"F","local":"","constant":"c"}', mJson.GetValue<TJSONObject>('naming').ToJSON);
  finally
    mJson.Free;
  end;
  mContext := Sample;
  mContext.Active := True;
  mJson := mContext.ToJson;
  try
    Assert.AreEqual('true', mJson.GetValue('active').ToJSON);
    Assert.IsNull(mJson.FindValue('formatFunctions'));
  finally
    mJson.Free;
  end;
  // Formatroutinen der Projektdatei (#451).
  mContext := Sample;
  SetLength(mContext.FormatFunctions, 1);
  mContext.FormatFunctions[0].Name := 'Log';
  mContext.FormatFunctions[0].FormatIndex := 1;
  mJson := mContext.ToJson;
  try
    Assert.AreEqual('[{"name":"Log","formatIndex":1}]', mJson.GetValue<TJSONArray>('formatFunctions').ToJSON);
  finally
    mJson.Free;
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
  mContext: TAtlasProjectContext;
begin
  mContext := Sample;
  mContext.Source := TAtlasProjectContext.cSourceConfiguration;
  Assert.AreEqual('A.dproj Debug/Win32 (Konfiguration, BDS 23.0): Defines DEBUG; 1 Suchpfade, 2 Namespaces, ' +
    '0 Bibliothekspfade', mContext.Describe);
  // Die Herkunft gehört nur ins Protokoll: Der Server bekommt deshalb nichts Neues.
  Assert.AreEqual(Sample.Key, mContext.Key);
  mContext.Active := True;
  Assert.IsTrue(mContext.Describe.EndsWith(', aktiv'), mContext.Describe);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProjectContextTests);

end.
