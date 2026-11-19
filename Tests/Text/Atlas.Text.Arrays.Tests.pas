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
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Arrays;

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

initialization
  TDUnitX.RegisterTestFixture(TTextArraysTests);

end.
