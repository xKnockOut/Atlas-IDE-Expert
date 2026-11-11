unit Atlas.Core.Tests.UnitMatch.Tests;

// Tests der Testunits zu einer Unit (#1817): Namensmuster, die Unit selbst
// zuerst, keine Doppelten, volle Namen der Fixtures.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestUnitMatchTests = class
  public
    [Test]
    procedure FindsUsualNames;
    [Test]
    procedure UnitItselfComesFirst;
    [Test]
    procedure NamesOfFixtures;
  end;

implementation

uses
  Atlas.Text.DUnitX,
  Atlas.Core.Tests.UnitMatch;

procedure TAtlasTestUnitMatchTests.FindsUsualNames;
var
  Found: TArray<string>;
begin
  Found := TAtlasTestUnitMatch.Candidates('C:\P\Core\Rechner.pas', ['C:\P\Tests\Rechner.Tests.pas',
    'C:\P\Tests\RechnerTests.pas', 'C:\P\Tests\TestRechner.pas', 'C:\P\Tests\Rechner.Test.dfm',
    'C:\P\Tests\RechnerTool.Tests.pas', 'C:\P\Tests\Rechner2Tests.pas']);
  Assert.AreEqual(4, Integer(Length(Found)));
  Assert.AreEqual('C:\P\Tests\Rechner.Tests.pas', Found[1]);
  Assert.AreEqual('C:\P\Tests\TestRechner.pas', Found[3]);
end;

procedure TAtlasTestUnitMatchTests.UnitItselfComesFirst;
var
  Found: TArray<string>;
begin
  Found := TAtlasTestUnitMatch.Candidates('C:\P\Tests\Rechner.Tests.pas', ['c:\p\tests\rechner.tests.pas',
    'C:\P\Tests\Rechner.Tests.Tests.pas']);
  Assert.AreEqual(2, Integer(Length(Found)), 'die Unit nicht doppelt');
  Assert.AreEqual('C:\P\Tests\Rechner.Tests.pas', Found[0]);
end;

procedure TAtlasTestUnitMatchTests.NamesOfFixtures;
var
  TestUnit: TDUnitXUnit;
  Names: TArray<string>;
begin
  TestUnit := TDUnitXSource.Scan(['unit Rechner.Tests;', 'interface', 'type', '  [TestFixture]',
    '  TAddTests = class', '  public', '    [Test]', '    procedure Adds;', '  end;', '  [TestFixture]',
    '  TSubTests = class', '  public', '    [Test]', '    procedure Subtracts;', '  end;', 'implementation',
    'end.']);
  Names := TAtlasTestUnitMatch.Names(TestUnit);
  Assert.AreEqual(2, Integer(Length(Names)));
  Assert.AreEqual('Rechner.Tests.TAddTests', Names[0]);
  Assert.AreEqual('Rechner.Tests.TSubTests', Names[1]);
  Assert.AreEqual(0, Integer(Length(TAtlasTestUnitMatch.Names(TDUnitXSource.Scan(['unit Leer;', 'end.'])))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestUnitMatchTests);

end.
