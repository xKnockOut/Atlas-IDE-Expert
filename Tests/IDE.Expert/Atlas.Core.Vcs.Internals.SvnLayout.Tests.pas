unit Atlas.Core.Vcs.Internals.SvnLayout.Tests;

// Ort von SVN-Branches (#1290) ohne Prozesse: Projektwurzel aus relative-url
// (trunk, branches/x, tags/x, kein Layout), Auflösen der Muster mit
// {projektwurzel}, {name} und {kennung}, Hauptbranch unter der Projektwurzel,
// Nachricht der Kopie, Ordner für „frisch auschecken“ und die höchste
// Revision aus svnversion.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSvnLayoutTests = class
  public
    /// <summary>^/Kasse/trunk → Kasse, ^/trunk → Wurzel, branches/x und tags/x, tiefer Unterordner; ohne Layout
    /// False.</summary>
    [Test]
    procedure ProjectRootFromRelativeUrl;
    /// <summary>{projektwurzel} mit und ohne Layout, ^/ fest, {kennung} ohne Issue = {name}, unsichere Ergebnisse
    /// abgelehnt.</summary>
    [Test]
    procedure ResolveLocation;
    [Test]
    procedure MainBranchUnderProjectRoot;
    [Test]
    procedure MessageFromPattern;
    [Test]
    procedure CheckoutFolderRelativeToWorkingCopy;
    /// <summary>svnversion: eine Revision, gemischt, Marken M/S/P, unversioniert.</summary>
    [Test]
    procedure WorkingRevisionFromSvnVersion;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Internals.SvnLayout;

function Root: string;
begin
  if PathDelim = '\' then
    Result := 'C:\Projekte\Kasse'
  else
    Result := '/projekte/kasse';
end;

function Beside(const AName: string): string;
begin
  Result := ExtractFilePath(Root) + AName;
end;

procedure TAtlasSvnLayoutTests.ProjectRootFromRelativeUrl;
var
  mRoot: string;
begin
  Assert.IsTrue(TAtlasSvnLayout.ProjectRoot('^/Kasse/trunk', mRoot));
  Assert.AreEqual('Kasse', mRoot);
  Assert.IsTrue(TAtlasSvnLayout.ProjectRoot('^/trunk', mRoot));
  Assert.AreEqual('', mRoot, 'Standardlayout: Wurzel des Repositorys');
  Assert.IsTrue(TAtlasSvnLayout.ProjectRoot('Packages/Drucken/branches/KASSE-42', mRoot));
  Assert.AreEqual('Packages/Drucken', mRoot);
  Assert.IsTrue(TAtlasSvnLayout.ProjectRoot('^/Kasse/tags/1.0/Quellen', mRoot));
  Assert.AreEqual('Kasse', mRoot);
  Assert.IsTrue(TAtlasSvnLayout.ProjectRoot('^/Kasse/trunk/Quellen/Basis', mRoot));
  Assert.AreEqual('Kasse', mRoot, 'Arbeitskopie eines Unterordners');
  Assert.IsFalse(TAtlasSvnLayout.ProjectRoot('^/Kasse/Quellen', mRoot));
  Assert.AreEqual('', mRoot);
  Assert.IsFalse(TAtlasSvnLayout.ProjectRoot('^/Kasse/branches', mRoot), 'branches ohne Namen');
  Assert.IsFalse(TAtlasSvnLayout.ProjectRoot('', mRoot));
end;

procedure TAtlasSvnLayoutTests.ResolveLocation;
var
  mPath: string;
  mOptions: TAtlasVcsSvnBranchOptions;
begin
  Assert.IsTrue(TAtlasSvnLayout.Resolve('{projektwurzel}/branches/{name}', True, 'Kasse', 'KASSE-42-bon', '', mPath));
  Assert.AreEqual('Kasse/branches/KASSE-42-bon', mPath);
  Assert.IsTrue(TAtlasSvnLayout.Resolve('{projektwurzel}/branches/{name}', True, '', 'KASSE-42-bon', '', mPath));
  Assert.AreEqual('branches/KASSE-42-bon', mPath, 'Standardlayout wie vor #1290');
  Assert.IsFalse(TAtlasSvnLayout.Resolve('{projektwurzel}/branches/{name}', False, '', 'KASSE-42-bon', '', mPath),
    'ohne Layout fragt der Dialog');
  Assert.AreEqual('', mPath);
  Assert.IsTrue(TAtlasSvnLayout.Resolve('^/branches/{name}', False, '', 'KASSE-42-bon', '', mPath));
  Assert.AreEqual('branches/KASSE-42-bon', mPath, 'fester Ort braucht keine Projektwurzel');
  Assert.IsTrue(TAtlasSvnLayout.Resolve('{PROJEKTWURZEL}/branches/{kennung}/', True, 'Kasse', 'KASSE-42-bon',
    'KASSE-42', mPath));
  Assert.AreEqual('Kasse/branches/KASSE-42', mPath, 'Platzhalter ohne Groß-/Kleinschreibung, "/" am Ende weg');
  Assert.IsTrue(TAtlasSvnLayout.Resolve('^/Kasse/branches/{kennung}', False, '', 'x', '', mPath));
  Assert.AreEqual('Kasse/branches/x', mPath, 'ohne Issue gilt der Name');
  Assert.IsFalse(TAtlasSvnLayout.Resolve('branches/{name}', True, 'Kasse', 'x', '', mPath), 'weder ^/ noch Wurzel');
  Assert.IsFalse(TAtlasSvnLayout.Resolve('^/{name}/../trunk', True, '', 'x', '', mPath), '„..“');
  Assert.IsFalse(TAtlasSvnLayout.Resolve('^/branches/{titel}', True, '', 'x', '', mPath), 'unbekannter Platzhalter');
  Assert.IsFalse(TAtlasSvnLayout.Resolve('^/', True, '', 'x', '', mPath), 'leer');
  Assert.IsFalse(TAtlasSvnLayout.Resolve('{projektwurzel}/branches/{name}', True, 'Kasse', '', '', mPath),
    'ohne Namen');
  // Mit den Optionen und der Projektwurzel aus relative-url.
  mOptions := TAtlasVcsSvnBranchOptions.Default;
  Assert.IsTrue(TAtlasSvnLayout.Resolve(mOptions, '^/Packages/Drucken/trunk', 'KASSE-42-bon', mPath));
  Assert.AreEqual('Packages/Drucken/branches/KASSE-42-bon', mPath);
  Assert.IsFalse(TAtlasSvnLayout.Resolve(mOptions, '^/Sonstiges', 'KASSE-42-bon', mPath));
  mOptions := TAtlasVcsSvnBranchOptions.Legacy;
  Assert.IsTrue(TAtlasSvnLayout.Resolve(mOptions, '^/Sonstiges', 'KASSE-42-bon', mPath));
  Assert.AreEqual('branches/KASSE-42-bon', mPath);
  Assert.IsTrue(TAtlasSvnLayout.NeedsRoot(' {projektwurzel}/x'));
  Assert.IsFalse(TAtlasSvnLayout.NeedsRoot('^/x'));
  Assert.IsTrue(TAtlasSvnLayout.ValidPattern('^/x'));
  Assert.IsFalse(TAtlasSvnLayout.ValidPattern('x'));
end;

procedure TAtlasSvnLayoutTests.MainBranchUnderProjectRoot;
begin
  Assert.AreEqual('Kasse/trunk', TAtlasSvnLayout.MainPath('trunk', True, 'Kasse'));
  Assert.AreEqual('Kasse/branches/release', TAtlasSvnLayout.MainPath('branches/release', True, 'Kasse'));
  Assert.AreEqual('Kasse/trunk', TAtlasSvnLayout.MainPath('Kasse/trunk', True, 'Kasse'), 'schon mit Wurzel');
  Assert.AreEqual('Basis/trunk', TAtlasSvnLayout.MainPath('^/Basis/trunk', True, 'Kasse'), 'mit ^/ wie angegeben');
  Assert.AreEqual('Andere/trunk', TAtlasSvnLayout.MainPath('Andere/trunk', True, 'Kasse'));
  Assert.AreEqual('trunk', TAtlasSvnLayout.MainPath('trunk', True, ''), 'Standardlayout');
  Assert.AreEqual('trunk', TAtlasSvnLayout.MainPath('trunk', False, 'Kasse'), 'ohne Layout');
end;

procedure TAtlasSvnLayoutTests.MessageFromPattern;
begin
  Assert.AreEqual('KASSE-42 Branch für Bon drucken langsam', TAtlasSvnLayout.MessageText('{kennung} Branch für {titel}',
    'KASSE-42', 'Bon drucken langsam', 'KASSE-42-bon'));
  Assert.AreEqual('Branch KASSE-42-bon', TAtlasSvnLayout.MessageText('{kennung} Branch für {titel}', '', '',
    'KASSE-42-bon'), 'ohne Issue');
  Assert.AreEqual('KASSE-42-bon: KASSE-42', TAtlasSvnLayout.MessageText('{name}: {KENNUNG}', 'KASSE-42', 'x',
    'KASSE-42-bon'));
  Assert.AreEqual('Branch x', TAtlasSvnLayout.MessageText('  ', 'KASSE-42', 'Titel', 'x'), 'leeres Muster');
end;

procedure TAtlasSvnLayoutTests.CheckoutFolderRelativeToWorkingCopy;
begin
  Assert.AreEqual(Beside(ExtractFileName(Root) + '-KASSE-42'), TAtlasSvnLayout.CheckoutFolder('..\{projekt}-{kennung}', Root, '',
    'KASSE-42-bon', 'KASSE-42'), 'Projekt = Ordner der Arbeitskopie');
  Assert.AreEqual(Beside('Kassengruppe-KASSE-42'), TAtlasSvnLayout.CheckoutFolder('../{projekt}-{kennung}', Root,
    'Kassengruppe', 'KASSE-42-bon', 'KASSE-42'));
  Assert.AreEqual(Beside(ExtractFileName(Root) + '-feature-x'), TAtlasSvnLayout.CheckoutFolder('..\{projekt}-{kennung}', Root, '',
    'feature/x', ''), 'ohne Issue der Name, "/" wird "-"');
  Assert.AreEqual(Root + PathDelim + 'branches' + PathDelim + 'x', TAtlasSvnLayout.CheckoutFolder('branches\{name}',
    Root, '', 'x', ''), 'unter der Arbeitskopie');
  if PathDelim = '\' then
    Assert.AreEqual('D:\Branches\x', TAtlasSvnLayout.CheckoutFolder('D:\Branches\{name}', Root, '', 'x', ''))
  else
    Assert.AreEqual('/branches/x', TAtlasSvnLayout.CheckoutFolder('/branches/{name}', Root, '', 'x', ''));
  Assert.AreEqual('', TAtlasSvnLayout.CheckoutFolder('', Root, '', 'x', ''));
  Assert.AreEqual('', TAtlasSvnLayout.CheckoutFolder('..\{name}', '', '', 'x', ''));
end;

procedure TAtlasSvnLayoutTests.WorkingRevisionFromSvnVersion;
var
  mRevision: string;
  mMixed: Boolean;
begin
  Assert.IsTrue(TAtlasSvnLayout.WorkingRevision('48213' + #13#10, mRevision, mMixed));
  Assert.AreEqual('48213', mRevision);
  Assert.IsFalse(mMixed);
  Assert.IsTrue(TAtlasSvnLayout.WorkingRevision('48190:48213', mRevision, mMixed));
  Assert.AreEqual('48213', mRevision);
  Assert.IsTrue(mMixed);
  Assert.IsTrue(TAtlasSvnLayout.WorkingRevision('48190:48213MSP', mRevision, mMixed));
  Assert.AreEqual('48213', mRevision);
  Assert.IsTrue(mMixed);
  Assert.IsTrue(TAtlasSvnLayout.WorkingRevision('48213M', mRevision, mMixed));
  Assert.AreEqual('48213', mRevision);
  Assert.IsFalse(mMixed);
  Assert.IsFalse(TAtlasSvnLayout.WorkingRevision('Unversioned directory', mRevision, mMixed));
  Assert.AreEqual('', mRevision);
  Assert.IsFalse(mMixed);
  Assert.IsFalse(TAtlasSvnLayout.WorkingRevision('exported', mRevision, mMixed));
  Assert.IsFalse(TAtlasSvnLayout.WorkingRevision('', mRevision, mMixed));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSvnLayoutTests);

end.
