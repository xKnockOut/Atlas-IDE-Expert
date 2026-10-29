unit Atlas.Common.Rationale.References.Tests;

// Tests für die Verweise in Begründungen (#1123): ADR, Issue, URL und die
// Suche der ADR-Datei.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRationaleReferencesTests = class
  public
    [Test]
    procedure Links;
    [Test]
    procedure AdrFiles;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rationale.Contract,
  Atlas.Common.Rationale.References;

procedure TRationaleReferencesTests.Links;
var
  mLinks: TArray<TRationaleLink>;
begin
  mLinks := TRationaleReferences.Find('siehe ADR-0007, ADR 12 und #312; nicht #13#10, a#5 oder ADRx. https://x.de/a.');
  Assert.AreEqual(4, Integer(Length(mLinks)));
  Assert.AreEqual(Ord(TRationaleLinkKind.Adr), Ord(mLinks[0].Kind));
  Assert.AreEqual('7', mLinks[0].Key);
  Assert.AreEqual(6, mLinks[0].Start);
  Assert.AreEqual(8, mLinks[0].Length);
  Assert.AreEqual('12', mLinks[1].Key);
  Assert.AreEqual(Ord(TRationaleLinkKind.Issue), Ord(mLinks[2].Kind));
  Assert.AreEqual('312', mLinks[2].Key);
  Assert.AreEqual(Ord(TRationaleLinkKind.Url), Ord(mLinks[3].Kind));
  Assert.AreEqual('https://x.de/a', mLinks[3].Key);
  // Auch nicht hinter Buchstaben außerhalb von ASCII.
  Assert.AreEqual(0, Integer(Length(TRationaleReferences.Find('Gr'#$00F6'#5 und &#312;'))));
end;

procedure TRationaleReferencesTests.AdrFiles;
var
  mFiles: TArray<string>;
begin
  mFiles := TArray<string>.Create('C:\P\docs\adr\0012-cache.md', 'C:\P\docs\adr\0007-threads.md',
    'C:\P\docs\adr\README.md', 'C:\P\docs\adr\ADR-0003-namen.md', 'C:\P\docs\adr\00070-anderes.md');
  Assert.AreEqual('C:\P\docs\adr\0007-threads.md', TRationaleReferences.AdrFile('7', mFiles));
  Assert.AreEqual('C:\P\docs\adr\0003-namen.md'.Replace('0003', 'ADR-0003'), TRationaleReferences.AdrFile('3', mFiles));
  Assert.AreEqual('C:\P\docs\adr\00070-anderes.md', TRationaleReferences.AdrFile('70', mFiles));
  Assert.AreEqual('', TRationaleReferences.AdrFile('8', mFiles));
end;

initialization
  TDUnitX.RegisterTestFixture(TRationaleReferencesTests);

end.
