unit Atlas.Common.Documents.Contract.Tests;

// Tests der Bereichsabfragen von TTextRange (Atlas.Common.Documents.Contract): Encloses schließt das Ende ein,
// Contains nicht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextRangeTests = class
  public
    [Test]
    procedure EnclosesIncludesEnd;
    [Test]
    procedure AnyEnclosesChecksAllRanges;
    [Test]
    procedure OneLineInJoinsLines;
    [Test]
    procedure TextOrEmptyWithoutFile;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  System.SysUtils;

/// <summary>Leser, der nur AFileName kennt (ohne Groß-/Kleinschreibung) und AText liefert.</summary>
function ReaderFor(const AFileName, AText: string): TDocumentReadText;
begin
  Result :=
    function(const AName: string; out AResult: string): Boolean
    begin
      Result := SameText(AName, AFileName);
      AResult := '';
      if Result then
      begin
        AResult := AText;
      end;
    end;
end;

{ TTextRangeTests }

procedure TTextRangeTests.EnclosesIncludesEnd;
var
  mRange: TTextRange;
begin
  mRange := TTextRange.Create(TTextPosition.Create(1, 4), TTextPosition.Create(2, 3));
  Assert.IsTrue(mRange.Encloses(TTextPosition.Create(1, 4)));
  Assert.IsTrue(mRange.Encloses(TTextPosition.Create(1, 99)));
  Assert.IsTrue(mRange.Encloses(TTextPosition.Create(2, 3)), 'Ende zählt mit');
  Assert.IsFalse(mRange.Contains(TTextPosition.Create(2, 3)), 'Contains schließt das Ende aus');
  Assert.IsFalse(mRange.Encloses(TTextPosition.Create(1, 3)));
  Assert.IsFalse(mRange.Encloses(TTextPosition.Create(2, 4)));
end;

procedure TTextRangeTests.AnyEnclosesChecksAllRanges;
var
  mRanges: TArray<TTextRange>;
begin
  Assert.IsFalse(TTextRange.AnyEncloses(nil, TTextPosition.Create(0, 0)));
  mRanges := [TTextRange.Create(TTextPosition.Create(0, 0), TTextPosition.Create(0, 2)),
    TTextRange.Create(TTextPosition.Create(5, 0), TTextPosition.Create(6, 0))];
  Assert.IsTrue(TTextRange.AnyEncloses(mRanges, TTextPosition.Create(6, 0)));
  Assert.IsFalse(TTextRange.AnyEncloses(mRanges, TTextPosition.Create(3, 0)));
  mRanges := nil;
end;

procedure TTextRangeTests.OneLineInJoinsLines;
var
  mLines: TArray<string>;
begin
  mLines := TArray<string>.Create('  X := Foo(', '    1,', '    2);', 'Rest');
  Assert.AreEqual('Foo( 1, 2);', TTextRange.Create(0, 7, 2, 6).OneLineIn(mLines));
  Assert.AreEqual('Rest', TTextRange.Create(3, 0, 9, 0).OneLineIn(mLines), 'hinter dem Ende abgeschnitten');
  Assert.AreEqual('', TTextRange.Create(7, 0, 8, 0).OneLineIn(mLines));
  mLines := nil;
end;

procedure TTextRangeTests.TextOrEmptyWithoutFile;
begin
  Assert.AreEqual('Inhalt', TDocumentReads.TextOrEmpty(ReaderFor('A.pas', 'Inhalt'), 'a.pas'));
  Assert.AreEqual('', TDocumentReads.TextOrEmpty(ReaderFor('A.pas', 'Inhalt'), 'B.pas'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTextRangeTests);

end.
