unit Atlas.Core.Marks.Ids.Tests;

// Tests der gemeinsamen Kennungen und des Dateivergleichs für Lesezeichen und
// Notizen: GUID-Form, Eindeutigkeit, Fallback ohne GUID mit laufender Nummer.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Bookmarks')]
  TAtlasMarkIdsTests = class
  public
    [Test]
    procedure SameFileIgnoresCaseAndSlashes;
    [Test]
    procedure NewIdIsGuidWithoutBraces;
    [Test]
    procedure NewIdsDiffer;
    /// <summary>Gleicher Zeitpunkt, andere Nummer: andere Kennung (früher Zufall nach Randomize).</summary>
    [Test]
    procedure FallbackDiffersBySerial;
    [Test]
    procedure FallbackHasTwentyHexDigits;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Marks.Ids;

procedure TAtlasMarkIdsTests.SameFileIgnoresCaseAndSlashes;
begin
  Assert.IsTrue(TAtlasMarkIds.SameFile('C:\Projekte\Kunde.pas', ' c:/projekte/KUNDE.pas '));
  Assert.IsFalse(TAtlasMarkIds.SameFile('C:\Projekte\Kunde.pas', 'C:\Projekte\Kunde.dfm'));
end;

procedure TAtlasMarkIdsTests.NewIdIsGuidWithoutBraces;
var
  mId: string;
begin
  mId := TAtlasMarkIds.NewId;
  Assert.AreEqual(36, Length(mId));
  Assert.AreEqual(LowerCase(mId), mId);
  Assert.IsFalse(mId.Contains('{'));
  Assert.IsFalse(mId.Contains('}'));
end;

procedure TAtlasMarkIdsTests.NewIdsDiffer;
begin
  Assert.AreNotEqual(TAtlasMarkIds.NewId, TAtlasMarkIds.NewId);
end;

procedure TAtlasMarkIdsTests.FallbackDiffersBySerial;
begin
  Assert.AreNotEqual(TAtlasMarkIds.Fallback(1234567, 1), TAtlasMarkIds.Fallback(1234567, 2));
end;

procedure TAtlasMarkIdsTests.FallbackHasTwentyHexDigits;
begin
  Assert.AreEqual('00000012d687' + '0000002a', TAtlasMarkIds.Fallback(1234567, 42));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMarkIdsTests);

end.
