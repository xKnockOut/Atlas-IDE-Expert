unit Atlas.Text.Lists.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextListsTests = class
  public
    [Test]
    procedure ContainsIntegerFindsValue;
    [Test]
    procedure SameTextsIgnoresCase;
    [Test]
    procedure AddTextSkipsEmptyAndKnown;
    [Test]
    procedure AddUniqueTextUsesSeen;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Text.Lists;

{ TTextListsTests }

procedure TTextListsTests.ContainsIntegerFindsValue;
begin
  Assert.IsTrue(TTextLists.ContainsInteger(TArray<Integer>.Create(3, 1, 2), 2));
  Assert.IsFalse(TTextLists.ContainsInteger(TArray<Integer>.Create(3, 1), 2));
  Assert.IsFalse(TTextLists.ContainsInteger(nil, 0));
end;

procedure TTextListsTests.SameTextsIgnoresCase;
begin
  Assert.IsTrue(TTextLists.SameTexts(TArray<string>.Create('Integer', 'string'),
    TArray<string>.Create('integer', 'String')));
  Assert.IsFalse(TTextLists.SameTexts(TArray<string>.Create('a', 'b'), TArray<string>.Create('b', 'a')));
  Assert.IsFalse(TTextLists.SameTexts(TArray<string>.Create('a'), TArray<string>.Create('a', 'b')));
  Assert.IsTrue(TTextLists.SameTexts(nil, nil));
end;

procedure TTextListsTests.AddTextSkipsEmptyAndKnown;
var
  mList: TArray<string>;
begin
  mList := nil;
  TTextLists.AddText(mList, 'Foo');
  TTextLists.AddText(mList, '');
  TTextLists.AddText(mList, 'FOO');
  TTextLists.AddText(mList, 'Bar');
  Assert.AreEqual(2, Integer(Length(mList)));
  Assert.AreEqual('Foo', mList[0]);
  Assert.AreEqual('Bar', mList[1]);
  mList := nil;
end;

procedure TTextListsTests.AddUniqueTextUsesSeen;
var
  mList: TArray<string>;
  mSeen: TDictionary<string, Boolean>;
begin
  mList := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    TTextLists.AddUniqueText(mList, mSeen, 'Unit1');
    TTextLists.AddUniqueText(mList, mSeen, 'UNIT1');
    TTextLists.AddUniqueText(mList, mSeen, '');
    TTextLists.AddUniqueText(mList, mSeen, 'Unit2');
    Assert.AreEqual(2, Integer(Length(mList)));
    Assert.AreEqual('Unit1', mList[0]);
    Assert.IsTrue(mSeen.ContainsKey('unit2'));
  finally
    mSeen.Free;
  end;
  mList := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TTextListsTests);

end.
