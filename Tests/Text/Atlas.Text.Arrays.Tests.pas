unit Atlas.Text.Arrays.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextArraysTests = class
  public
    [Test]
    procedure SameTextsComparesCase;
    [Test]
    procedure SameNeedsEqualLength;
    [Test]
    procedure SameInterfacesComparesReferences;
    [Test]
    procedure AddTextSkipsEmptyAndDuplicates;
    [Test]
    procedure ContainsIntegerFindsValue;
    [Test]
    procedure SameTextsIgnoresCase;
    [Test]
    procedure IndexOfTextUsesTextOf;
    [Test]
    procedure TextsKeepsOrder;
    [Test]
    procedure CountOfTextFromParallelArrays;
    [Test]
    procedure AddUniqueTextUsesSeen;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Arrays,
  System.Generics.Collections;

{ TTextArraysTests }

procedure TTextArraysTests.SameTextsComparesCase;
begin
  Assert.IsTrue(TTextArrays.Same<string>(TArray<string>.Create('a', 'b'), TArray<string>.Create('a', 'b')));
  Assert.IsFalse(TTextArrays.Same<string>(TArray<string>.Create('a', 'b'), TArray<string>.Create('a', 'B')));
end;

procedure TTextArraysTests.SameNeedsEqualLength;
begin
  Assert.IsTrue(TTextArrays.Same<string>(nil, nil));
  Assert.IsFalse(TTextArrays.Same<string>(TArray<string>.Create('a'), TArray<string>.Create('a', 'a')));
end;

procedure TTextArraysTests.SameInterfacesComparesReferences;
var
  mFirst, mSecond: IInterface;
begin
  mFirst := TInterfacedObject.Create;
  mSecond := TInterfacedObject.Create;
  Assert.IsTrue(TTextArrays.Same<IInterface>(TArray<IInterface>.Create(mFirst, mSecond),
    TArray<IInterface>.Create(mFirst, mSecond)));
  Assert.IsFalse(TTextArrays.Same<IInterface>(TArray<IInterface>.Create(mFirst, mSecond),
    TArray<IInterface>.Create(mSecond, mFirst)));
end;

procedure TTextArraysTests.AddTextSkipsEmptyAndDuplicates;
var
  mList: TArray<string>;
begin
  mList := nil;
  TTextArrays.AddText(mList, 'Alpha');
  TTextArrays.AddText(mList, '');
  TTextArrays.AddText(mList, 'ALPHA');
  TTextArrays.AddText(mList, 'Beta');
  Assert.AreEqual(2, Integer(Length(mList)));
  Assert.AreEqual('Alpha', mList[0]);
  Assert.AreEqual('Beta', mList[1]);
end;

procedure TTextArraysTests.ContainsIntegerFindsValue;
begin
  Assert.IsTrue(TTextArrays.ContainsInteger(TArray<Integer>.Create(3, 1, 2), 2));
  Assert.IsFalse(TTextArrays.ContainsInteger(TArray<Integer>.Create(3, 1), 2));
  Assert.IsFalse(TTextArrays.ContainsInteger(nil, 0));
end;

procedure TTextArraysTests.SameTextsIgnoresCase;
begin
  Assert.IsTrue(TTextArrays.SameTexts(TArray<string>.Create('Integer', 'string'),
    TArray<string>.Create('integer', 'String')));
  Assert.IsFalse(TTextArrays.SameTexts(TArray<string>.Create('a', 'b'), TArray<string>.Create('b', 'a')));
  Assert.IsFalse(TTextArrays.SameTexts(TArray<string>.Create('a'), TArray<string>.Create('a', 'b')));
  Assert.IsTrue(TTextArrays.SameTexts(nil, nil));
end;

procedure TTextArraysTests.IndexOfTextUsesTextOf;
var
  mTextOf: TFunc<Integer, string>;
begin
  mTextOf :=
    function(AValue: Integer): string
    begin
      Result := 'Unit' + IntToStr(AValue);
    end;
  Assert.AreEqual(1, TTextArrays.IndexOfText<Integer>(TArray<Integer>.Create(4, 7, 7), 'UNIT7', mTextOf));
  Assert.AreEqual(-1, TTextArrays.IndexOfText<Integer>(TArray<Integer>.Create(4), 'Unit5', mTextOf));
  mTextOf := nil;
end;

procedure TTextArraysTests.TextsKeepsOrder;
var
  mTextOf: TFunc<Integer, string>;
  mTexts: TArray<string>;
begin
  mTextOf :=
    function(AValue: Integer): string
    begin
      Result := 'Unit' + IntToStr(AValue);
    end;
  mTexts := TTextArrays.Texts<Integer>(TArray<Integer>.Create(4, 7), mTextOf);
  Assert.AreEqual(2, Integer(Length(mTexts)));
  Assert.AreEqual('Unit4', mTexts[0]);
  Assert.AreEqual('Unit7', mTexts[1]);
  Assert.AreEqual(0, Integer(Length(TTextArrays.Texts<Integer>(nil, mTextOf))));
  mTextOf := nil;
  mTexts := nil;
end;

procedure TTextArraysTests.CountOfTextFromParallelArrays;
begin
  Assert.AreEqual(3, TTextArrays.CountOfText(TArray<string>.Create('TODO', 'FIXME'), TArray<Integer>.Create(5, 3),
    'fixme'));
  Assert.AreEqual(0, TTextArrays.CountOfText(TArray<string>.Create('TODO'), TArray<Integer>.Create(5), 'HACK'));
end;

procedure TTextArraysTests.AddUniqueTextUsesSeen;
var
  mList: TArray<string>;
  mSeen: TDictionary<string, Boolean>;
begin
  mList := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    TTextArrays.AddUniqueText(mList, mSeen, 'Unit1');
    TTextArrays.AddUniqueText(mList, mSeen, 'UNIT1');
    TTextArrays.AddUniqueText(mList, mSeen, '');
    TTextArrays.AddUniqueText(mList, mSeen, 'Unit2');
    Assert.AreEqual(2, Integer(Length(mList)));
    Assert.AreEqual('Unit1', mList[0]);
    Assert.IsTrue(mSeen.ContainsKey('unit2'));
  finally
    mSeen.Free;
  end;
  mList := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TTextArraysTests);

end.
