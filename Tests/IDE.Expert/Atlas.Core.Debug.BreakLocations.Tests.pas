unit Atlas.Core.Debug.BreakLocations.Tests;

// Tests für die gemeinsamen Haltestellen vorübergehender Haltepunkte (#856, #870).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasBreakLocationsTests = class
  public
    [Test]
    procedure AddGroupsByFileAndLine;
    [Test]
    procedure IndexOfIgnoresCase;
  end;

implementation

uses
  Atlas.Core.Debug.BreakLocations;

{ TAtlasBreakLocationsTests }

procedure TAtlasBreakLocationsTests.AddGroupsByFileAndLine;
var
  mLocations: TArray<TAtlasBreakLocation>;
begin
  mLocations := nil;
  TAtlasBreakLocations.Add(mLocations, 'C:\P\Kunde.pas', 10, 0);
  TAtlasBreakLocations.Add(mLocations, 'C:\P\Kunde.pas', 12, 1);
  TAtlasBreakLocations.Add(mLocations, 'c:\p\kunde.pas', 10, 2);
  Assert.AreEqual(2, Integer(Length(mLocations)));
  Assert.AreEqual(10, mLocations[0].Line);
  Assert.AreEqual(2, Integer(Length(mLocations[0].Items)));
  Assert.AreEqual(0, mLocations[0].Items[0]);
  Assert.AreEqual(2, mLocations[0].Items[1]);
  Assert.AreEqual(1, mLocations[1].Items[0]);
end;

procedure TAtlasBreakLocationsTests.IndexOfIgnoresCase;
var
  mLocations: TArray<TAtlasBreakLocation>;
begin
  mLocations := nil;
  Assert.AreEqual(-1, TAtlasBreakLocations.IndexOf(mLocations, 'A.pas', 1));
  TAtlasBreakLocations.Add(mLocations, 'A.pas', 1, 7);
  Assert.AreEqual(0, TAtlasBreakLocations.IndexOf(mLocations, 'a.PAS', 1));
  Assert.AreEqual(-1, TAtlasBreakLocations.IndexOf(mLocations, 'A.pas', 2));
  Assert.AreEqual(-1, TAtlasBreakLocations.IndexOf(mLocations, 'B.pas', 1));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBreakLocationsTests);

end.
