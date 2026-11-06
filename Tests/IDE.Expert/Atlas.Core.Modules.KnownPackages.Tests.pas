unit Atlas.Core.Modules.KnownPackages.Tests;

// Module unter „Known Packages“ (Meldung vom 05.11.2026): Erkennen der
// Modul-BPLs neben Base, fehlende, abgeschaltete und aus anderem Ordner
// eingetragene Module und Vergleich zweier Stände.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasKnownPackagesTests = class
  public
    [Test]
    procedure ModuleFilesNeedBaseFolderAndSuffix;
    [Test]
    procedure MissingWhenNeitherKnownNorDisabled;
    [Test]
    procedure DisabledAndElsewhereAreNotMissing;
    [Test]
    procedure KnownIgnoresCaseAndSlashes;
    [Test]
    procedure CompareSeesOnlyAtlasEntries;
    [Test]
    procedure ReportNamesModulesOnly;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.KnownPackages;

const
  cDir = 'C:\Atlas\Win32\';
  cBase = cDir + 'Atlas.IDE.Base370.bpl';
  cDebugger = cDir + 'Atlas.IDE.Debugger370.bpl';
  cSearch = cDir + 'Atlas.IDE.Search370.bpl';
  cTests = cDir + 'Atlas.IDE.Tests370.bpl';

function Input(const AKnown, ADisabled: TArray<string>): TAtlasKnownPackagesInput;
begin
  Result := Default(TAtlasKnownPackagesInput);
  Result.BaseFile := cBase;
  Result.Files := TArray<string>.Create(cBase, cDebugger, cSearch, cTests, cDir + 'Atlas.IDE.Contracts370.bpl',
    cDir + 'Atlas.IDE.Expert370.bpl', cDir + 'Atlas.IDE.Search290.bpl', cDir + 'Fremd370.bpl');
  Result.Known := AKnown;
  Result.Disabled := ADisabled;
end;

{ TAtlasKnownPackagesTests }

procedure TAtlasKnownPackagesTests.ModuleFilesNeedBaseFolderAndSuffix;
begin
  Assert.IsTrue(TAtlasKnownPackages.IsModuleFile(cDebugger, cBase));
  Assert.IsTrue(TAtlasKnownPackages.IsModuleFile('c:/atlas/win32/atlas.ide.debugger370.bpl', cBase));
  Assert.IsFalse(TAtlasKnownPackages.IsModuleFile(cBase, cBase), 'Base');
  Assert.IsFalse(TAtlasKnownPackages.IsModuleFile(cDir + 'Atlas.IDE.Contracts370.bpl', cBase), 'Verträge');
  Assert.IsFalse(TAtlasKnownPackages.IsModuleFile(cDir + 'Atlas.IDE.Expert370.bpl', cBase), 'Plugin 1.x');
  Assert.IsFalse(TAtlasKnownPackages.IsModuleFile(cDir + 'Atlas.IDE.Search290.bpl', cBase), 'andere Endung');
  Assert.IsFalse(TAtlasKnownPackages.IsModuleFile('C:\Anders\Atlas.IDE.Search370.bpl', cBase), 'anderer Ordner');
  Assert.IsFalse(TAtlasKnownPackages.IsModuleFile(cDir + 'Fremd370.bpl', cBase), 'fremd');
  Assert.AreEqual('Debugger', TAtlasKnownPackages.ModuleName(cDebugger));
  Assert.AreEqual('370', TAtlasKnownPackages.Suffix(cDebugger));
  Assert.AreEqual('Atlas Debugger', TAtlasKnownPackages.Description(cDebugger));
end;

procedure TAtlasKnownPackagesTests.MissingWhenNeitherKnownNorDisabled;
var
  mState: TAtlasKnownPackagesState;
begin
  // Der Stand vom 05.11.2026: nur Base eingetragen.
  mState := TAtlasKnownPackages.Check(Input(TArray<string>.Create(cBase, 'C:\Fremd\Xml370.bpl'), nil));
  Assert.AreEqual(3, Integer(Length(mState.Modules)));
  Assert.AreEqual(3, Integer(Length(mState.Missing)));
  Assert.IsFalse(mState.IsComplete);
  Assert.AreEqual('Debugger, Search, Tests', TAtlasKnownPackages.Names(mState.Missing));

  mState := TAtlasKnownPackages.Check(Input(TArray<string>.Create(cBase, cDebugger, cSearch, cTests), nil));
  Assert.IsTrue(mState.IsComplete);
  Assert.AreEqual(3, Integer(Length(mState.Modules)));
end;

procedure TAtlasKnownPackagesTests.DisabledAndElsewhereAreNotMissing;
var
  mState: TAtlasKnownPackagesState;
begin
  mState := TAtlasKnownPackages.Check(Input(TArray<string>.Create(cBase, 'D:\Dev\Bpl\Atlas.IDE.Search370.bpl'),
    TArray<string>.Create(cDebugger)));
  Assert.AreEqual('Tests', TAtlasKnownPackages.Names(mState.Missing));
  Assert.AreEqual('Debugger', TAtlasKnownPackages.Names(mState.Disabled));
  Assert.AreEqual('Search', TAtlasKnownPackages.Names(mState.Elsewhere));
end;

procedure TAtlasKnownPackagesTests.KnownIgnoresCaseAndSlashes;
var
  mState: TAtlasKnownPackagesState;
begin
  mState := TAtlasKnownPackages.Check(Input(TArray<string>.Create(cBase, 'c:/atlas/win32/ATLAS.IDE.DEBUGGER370.BPL',
    cSearch, cTests), nil));
  Assert.IsTrue(mState.IsComplete);
end;

procedure TAtlasKnownPackagesTests.CompareSeesOnlyAtlasEntries;
var
  mChange: TAtlasKnownPackagesChange;
begin
  mChange := TAtlasKnownPackages.Compare(TArray<string>.Create(cBase, cDebugger, cSearch, 'C:\Fremd\Xml370.bpl'),
    TArray<string>.Create(cBase, cTests, 'C:\Fremd\Anderes370.bpl'));
  Assert.AreEqual('Debugger, Search', TAtlasKnownPackages.Names(mChange.Removed));
  Assert.AreEqual('Tests', TAtlasKnownPackages.Names(mChange.Added));
  Assert.IsFalse(mChange.IsEmpty);

  mChange := TAtlasKnownPackages.Compare(TArray<string>.Create(cBase, 'C:\Fremd\Xml370.bpl'),
    TArray<string>.Create(cBase));
  Assert.IsTrue(mChange.IsEmpty, 'fremde Packages zählen nicht');
end;

procedure TAtlasKnownPackagesTests.ReportNamesModulesOnly;
var
  mText: string;
begin
  mText := TAtlasKnownPackages.Report(TAtlasKnownPackages.Check(Input(TArray<string>.Create(cBase),
    TArray<string>.Create(cTests))));
  Assert.AreEqual('Known Packages: 3 Module im Ordner von Base, fehlend: Debugger, Search; abgeschaltet: Tests; ' +
    'aus anderem Ordner: -', mText);
  Assert.IsFalse(mText.Contains('C:\'), 'keine Pfade im Protokoll');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasKnownPackagesTests);

end.
