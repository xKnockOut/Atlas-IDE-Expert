unit Atlas.Common.Projects.UnitAliases.Tests;

// Tests für Unit-Aliase wie beim Compiler (DCC_UnitAlias): Vorgaben von Delphi
// (WinTypes, WinProcs → Winapi.Windows), Aliase der .dproj, und dass Unit-Suche
// (uses-unit-not-found), Nachladen über die Suchpfade und Index einen Alias auf
// seine Unit führen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUnitAliasesTests = class
  public
    [Test]
    procedure DefaultsMapOldWindowsUnits;
    [Test]
    procedure ParseSkipsBrokenEntriesAndMacros;
    [Test]
    procedure ProjectAliasesGoBeforeDefaults;
    /// <summary>uses WinTypes, WinProcs: dcc meldet nichts, Atlas meldete F2613.</summary>
    [Test]
    procedure LookupFindsAliasedUnits;
    [Test]
    procedure LookupStillMissesAliasWithoutTarget;
    [Test]
    procedure ResolverLoadsTargetOfAlias;
    [Test]
    procedure IndexFindsTargetOfAlias;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Projects.UnitAliases,
  Atlas.Common.Projects.UnitLookup,
  Atlas.Common.Projects.UnitResolver,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex;

/// <summary>Projekt C:\P\App.dproj mit Namespaces System und Winapi und DCC_UnitAlias = AAliases ('' = ohne).
/// </summary>
function Project(const AAliases: string): TProjectInfo;
begin
  Result := Default(TProjectInfo);
  Result.FileName := 'C:\P\App.dproj';
  Result.Namespaces := TArray<string>.Create('System', 'Winapi');
  if AAliases <> '' then
  begin
    Result.Properties := TArray<TPair<string, string>>.Create(
      TPair<string, string>.Create(TUnitAliases.cProperty, AAliases));
  end;
end;

/// <summary>Unit-Suche über die Dateien AFiles im Bibliothekspfad C:\BDS\lib.</summary>
function Lookup(const AProject: TProjectInfo; const AFiles: TArray<string>): IRuleUnitLookup;
var
  mSetup: TUnitLookupSetup;
begin
  mSetup := Default(TUnitLookupSetup);
  mSetup.Project := AProject;
  mSetup.LibraryPaths := TArray<string>.Create('C:\BDS\lib');
  mSetup.LibraryKnown := True;
  mSetup.ListFiles :=
    function(AFolder: string): TArray<string>
    var
      mFileName: string;
    begin
      Result := nil;
      for mFileName in AFiles do
      begin
        if SameText(TProjectPaths.DirectoryOf(mFileName), AFolder) then
        begin
          Result := Result + [mFileName];
        end;
      end;
    end;
  mSetup.FileExists :=
    function(AFileName: string): Boolean
    begin
      Result := IndexText(AFileName, AFiles) >= 0;
    end;
  Result := TUnitLookup.Create(mSetup);
end;

// Ohne const: Aufrufer übergeben Lookup(...) direkt; so zählt Delphi die Referenz und gibt das Objekt frei.
function Answer(ALookup: IRuleUnitLookup; const AName: string): TRuleUnitAnswer;
begin
  Result := ALookup.Find(AName, '', 'C:\P\Main.pas', [TRuleUnitSource.Project]);
end;

procedure TUnitAliasesTests.DefaultsMapOldWindowsUnits;
var
  mUnit: string;
begin
  Assert.IsTrue(TUnitAliases.Target(TUnitAliases.Defaults, 'WinTypes', mUnit));
  Assert.AreEqual('Winapi.Windows', mUnit);
  Assert.IsTrue(TUnitAliases.Target(TUnitAliases.Defaults, 'winprocs', mUnit), 'ohne Groß-/Kleinschreibung');
  Assert.AreEqual('Winapi.Windows', mUnit);
  Assert.IsTrue(TUnitAliases.Target(TUnitAliases.Defaults, 'DbiErrs', mUnit));
  Assert.AreEqual('BDE', mUnit);
  Assert.IsFalse(TUnitAliases.Target(TUnitAliases.Defaults, 'Windows', mUnit));
  Assert.AreEqual('', mUnit);
end;

procedure TUnitAliasesTests.ParseSkipsBrokenEntriesAndMacros;
var
  mAliases: TArray<TUnitAlias>;
begin
  mAliases := TUnitAliases.Parse(' Alt = Neu.Unit ;ohne;=Leer;Leer=;$(DCC_UnitAlias);X=$(Ziel);;B=C');
  Assert.AreEqual(2, Integer(Length(mAliases)));
  Assert.AreEqual('Alt', mAliases[0].Key);
  Assert.AreEqual('Neu.Unit', mAliases[0].Value);
  Assert.AreEqual('B', mAliases[1].Key);
  Assert.AreEqual('C', mAliases[1].Value);
end;

procedure TUnitAliasesTests.ProjectAliasesGoBeforeDefaults;
var
  mAliases: TArray<TUnitAlias>;
  mUnit: string;
begin
  mAliases := TUnitAliases.OfProject(Project('WinTypes=Eigene.Typen;Generics.Collections=' +
    'System.Generics.Collections;$(DCC_UnitAlias)'));
  Assert.IsTrue(TUnitAliases.Target(mAliases, 'WinTypes', mUnit));
  Assert.AreEqual('Eigene.Typen', mUnit, 'Projekt vor Vorgabe');
  Assert.IsTrue(TUnitAliases.Target(mAliases, 'Generics.Collections', mUnit));
  Assert.AreEqual('System.Generics.Collections', mUnit);
  Assert.IsTrue(TUnitAliases.Target(mAliases, 'WinProcs', mUnit), 'Vorgabe bleibt');
  Assert.AreEqual('Winapi.Windows', mUnit);
  Assert.AreEqual(Integer(Length(TUnitAliases.Defaults)), Integer(Length(TUnitAliases.OfProject(Project('')))),
    'ohne DCC_UnitAlias nur die Vorgaben');
end;

procedure TUnitAliasesTests.LookupFindsAliasedUnits;
var
  mLookup: IRuleUnitLookup;
begin
  mLookup := Lookup(Project(''), TArray<string>.Create('C:\BDS\lib\System.dcu', 'C:\BDS\lib\Winapi.Windows.dcu'));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(mLookup, 'WinTypes')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(mLookup, 'WinProcs')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(mLookup, 'Windows')), 'Namespace Winapi');
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(mLookup, 'WinTypen')));
  mLookup := Lookup(Project('Alt=Neu'), TArray<string>.Create('C:\BDS\lib\Neu.dcu'));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(mLookup, 'Alt')), 'Alias der .dproj');
end;

procedure TUnitAliasesTests.LookupStillMissesAliasWithoutTarget;
begin
  // Fehlt die Ziel-Unit, meldet auch dcc F2613.
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing),
    Ord(Answer(Lookup(Project(''), TArray<string>.Create('C:\BDS\lib\System.dcu')), 'WinTypes')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing),
    Ord(Answer(Lookup(Project(''), TArray<string>.Create('C:\BDS\lib\System.dcu')), 'DbiTypes')), 'BDE fehlt');
end;

procedure TUnitAliasesTests.ResolverLoadsTargetOfAlias;
var
  mResolver: TUnitResolver;
begin
  mResolver := TUnitResolver.Create(Project(''), TArray<string>.Create('C:\BDS\source\rtl\win'),
    function(AFileName: string): Boolean
    begin
      Result := SameText(AFileName, 'C:\BDS\source\rtl\win\Winapi.Windows.pas');
    end);
  try
    Assert.AreEqual('C:\BDS\source\rtl\win\Winapi.Windows.pas', mResolver.Resolve('WinTypes'));
    Assert.AreEqual('C:\BDS\source\rtl\win\Winapi.Windows.pas', mResolver.Resolve('WinProcs'));
    Assert.AreEqual('', mResolver.Resolve('WinTypen'));
  finally
    mResolver.Free;
  end;
end;

procedure TUnitAliasesTests.IndexFindsTargetOfAlias;
var
  mIndex: ISymbolIndex;
  mUnit: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  mUnit := Default(TUnitIndex);
  mUnit.UnitName := 'Winapi.Windows';
  mUnit.FileName := 'C:\BDS\source\rtl\win\Winapi.Windows.pas';
  mIndex.AddUnit(mUnit);
  mUnit := Default(TUnitIndex);
  Assert.IsTrue(mIndex.FindUnit('WinTypes', mUnit), 'Vorgabe von Delphi');
  Assert.AreEqual('Winapi.Windows', mUnit.UnitName);
  Assert.IsFalse(mIndex.FindUnit('Alt', mUnit));
  mIndex.AddUnitAliases(TUnitAliases.Parse('Alt=Winapi.Windows'));
  Assert.IsTrue(mIndex.FindUnit('Alt', mUnit), 'Alias eines Projekts');
  // Eine Unit, die selbst so heißt wie ein Alias, geht vor.
  mUnit := Default(TUnitIndex);
  mUnit.UnitName := 'WinTypes';
  mUnit.FileName := 'C:\P\WinTypes.pas';
  mIndex.AddUnit(mUnit);
  mUnit := Default(TUnitIndex);
  Assert.IsTrue(mIndex.FindUnit('WinTypes', mUnit));
  Assert.AreEqual('WinTypes', mUnit.UnitName);
  mUnit := Default(TUnitIndex);
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitAliasesTests);

end.
