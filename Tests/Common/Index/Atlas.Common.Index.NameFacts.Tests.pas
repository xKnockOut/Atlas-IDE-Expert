unit Atlas.Common.Index.NameFacts.Tests;

// Über Units hinweg gemerkte Antworten zum Index (TIndexNameFacts): einmal
// gerechnet je Fassung des Index, neu nach jeder Änderung und für einen
// anderen Index, ohne Vorrat oder ohne Index jedes Mal.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIndexNameFactsTests = class
  public
    [Test]
    procedure ComputesOncePerGeneration;
    [Test]
    procedure IndexChangeForgets;
    [Test]
    procedure OtherIndexForgets;
    [Test]
    procedure WithoutFactsOrIndexAlwaysComputes;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.NameFacts;

function Counter(var ACalls: Integer; AValue: Integer): TFunc<Integer>;
var
  mCalls: PInteger;
begin
  mCalls := @ACalls;
  Result :=
    function: Integer
    begin
      Inc(mCalls^);
      Result := AValue;
    end;
end;

procedure TIndexNameFactsTests.ComputesOncePerGeneration;
var
  mFacts: IIndexNameFacts;
  mIndex: ISymbolIndex;
  mCalls: Integer;
begin
  mFacts := TIndexNameFacts.Create;
  mIndex := TSymbolIndex.Create;
  mCalls := 0;
  Assert.AreEqual(7, mFacts.Lookup(mIndex, 'a:COUNT', Counter(mCalls, 7)));
  Assert.AreEqual(7, mFacts.Lookup(mIndex, 'a:COUNT', Counter(mCalls, 99)));
  Assert.AreEqual(1, mCalls);
  // Anderer Schlüssel: eigene Antwort.
  Assert.AreEqual(3, mFacts.Lookup(mIndex, 'a:NAME', Counter(mCalls, 3)));
  Assert.AreEqual(2, mCalls);
end;

procedure TIndexNameFactsTests.IndexChangeForgets;
var
  mFacts: IIndexNameFacts;
  mIndex: ISymbolIndex;
  mCalls: Integer;
begin
  mFacts := TIndexNameFacts.Create;
  mIndex := TSymbolIndex.Create;
  mCalls := 0;
  mFacts.Lookup(mIndex, 'a:COUNT', Counter(mCalls, 1));
  // Eine neue Unit kann die Antwort ändern.
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit U;'#10'interface'#10'implementation'#10'end.', 'C:\P\U.pas',
    nil));
  Assert.AreEqual(2, mFacts.Lookup(mIndex, 'a:COUNT', Counter(mCalls, 2)));
  Assert.AreEqual(2, mCalls);
end;

procedure TIndexNameFactsTests.OtherIndexForgets;
var
  mFacts: IIndexNameFacts;
  mFirst, mSecond: ISymbolIndex;
  mCalls: Integer;
begin
  mFacts := TIndexNameFacts.Create;
  mFirst := TSymbolIndex.Create;
  mSecond := TSymbolIndex.Create;
  mCalls := 0;
  mFacts.Lookup(mFirst, 'a:COUNT', Counter(mCalls, 1));
  Assert.AreEqual(5, mFacts.Lookup(mSecond, 'a:COUNT', Counter(mCalls, 5)));
  Assert.AreEqual(2, mCalls);
end;

procedure TIndexNameFactsTests.WithoutFactsOrIndexAlwaysComputes;
var
  mFacts: IIndexNameFacts;
  mIndex: ISymbolIndex;
  mCalls: Integer;
begin
  mFacts := TIndexNameFacts.Create;
  mIndex := TSymbolIndex.Create;
  mCalls := 0;
  mFacts.Lookup(nil, 'a:COUNT', Counter(mCalls, 1));
  mFacts.Lookup(nil, 'a:COUNT', Counter(mCalls, 1));
  TIndexNameFacts.Get(nil, mIndex, 'a:COUNT', Counter(mCalls, 1));
  TIndexNameFacts.Get(nil, mIndex, 'a:COUNT', Counter(mCalls, 1));
  Assert.AreEqual(4, mCalls);
end;

end.
