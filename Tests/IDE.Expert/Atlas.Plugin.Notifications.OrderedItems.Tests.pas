unit Atlas.Plugin.Notifications.OrderedItems.Tests;

// Liste angemeldeter Einträge mit Kennung und Reihenfolge (TAtlasOrderedItems<T>): Reihenfolge, Ersetzen,
// Entfernen (auch mit dem entfernten bzw. ersetzten Eintrag), Suchen und unveränderliche Schnappschüsse.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasOrderedItemsTests = class
  public
    /// <summary>Nach Order, bei Gleichstand nach Kennung ohne Groß-/Kleinschreibung.</summary>
    [Test]
    procedure SortsByOrderThenId;
    /// <summary>Gleiche Kennung in anderer Schreibweise ersetzt den Eintrag an seiner neuen Stelle.</summary>
    [Test]
    procedure PutReplacesSameId;
    [Test]
    procedure RemoveTellsWhetherFound;
    /// <summary>Put und Take nennen den Eintrag, den die Liste abgibt (der Besitzer löst ihn dann).</summary>
    [Test]
    procedure PutAndTakeHandBackTheReleasedItem;
    [Test]
    procedure FindWithoutItemGivesDefault;
    /// <summary>Ein herausgegebenes Array bleibt, wie es war, auch wenn danach Einträge kommen und gehen.</summary>
    [Test]
    procedure SnapshotStaysUnchanged;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Plugin.Notifications.OrderedItems;

const
  cFirst = 5;
  cSecond = 10;
  cThird = 20;

type
  TEntry = record
    Id: string;
    Order: Integer;
  end;

  TEntries = class(TAtlasOrderedItems<TEntry>)
  protected
    function IdOf(const AItem: TEntry): string; override;
    function OrderOf(const AItem: TEntry): Integer; override;
  end;

function Entry(const AId: string; AOrder: Integer): TEntry;
begin
  Result.Id := AId;
  Result.Order := AOrder;
end;

function IdsOf(const AItems: TArray<TEntry>): string;
var
  mItem: TEntry;
begin
  Result := '';
  for mItem in AItems do
  begin
    Result := Result + mItem.Id + ';';
  end;
end;

{ TEntries }

function TEntries.IdOf(const AItem: TEntry): string;
begin
  Result := AItem.Id;
end;

function TEntries.OrderOf(const AItem: TEntry): Integer;
begin
  Result := AItem.Order;
end;

{ TAtlasOrderedItemsTests }

procedure TAtlasOrderedItemsTests.SortsByOrderThenId;
var
  mItems: TEntries;
begin
  mItems := TEntries.Create;
  try
    mItems.Put(Entry('c', cThird));
    mItems.Put(Entry('B', cSecond));
    mItems.Put(Entry('a', cSecond));
    mItems.Put(Entry('d', cFirst));
    Assert.AreEqual('d;a;B;c;', IdsOf(mItems.ToArray));
  finally
    mItems.Free;
  end;
end;

procedure TAtlasOrderedItemsTests.PutReplacesSameId;
var
  mItems: TEntries;
  mAll: TArray<TEntry>;
begin
  mItems := TEntries.Create;
  try
    mItems.Put(Entry('a', cFirst));
    mItems.Put(Entry('b', cSecond));
    mItems.Put(Entry('A', cThird));
    mAll := mItems.ToArray;
    Assert.AreEqual('b;A;', IdsOf(mAll));
    Assert.AreEqual(cThird, mAll[1].Order);
  finally
    mItems.Free;
  end;
  mAll := nil;
end;

procedure TAtlasOrderedItemsTests.RemoveTellsWhetherFound;
var
  mItems: TEntries;
begin
  mItems := TEntries.Create;
  try
    mItems.Put(Entry('a', 1));
    Assert.IsFalse(mItems.Remove('b'));
    Assert.IsTrue(mItems.Remove('A'));
    Assert.AreEqual(0, Integer(Length(mItems.ToArray)));
  finally
    mItems.Free;
  end;
end;

procedure TAtlasOrderedItemsTests.PutAndTakeHandBackTheReleasedItem;
var
  mItems: TEntries;
  mOut: TEntry;
begin
  mItems := TEntries.Create;
  try
    Assert.IsFalse(mItems.Put(Entry('a', cFirst), mOut), 'neu: nichts ersetzt');
    Assert.AreEqual('', mOut.Id);
    Assert.IsTrue(mItems.Put(Entry('A', cSecond), mOut));
    Assert.AreEqual('a', mOut.Id);
    Assert.AreEqual(cFirst, mOut.Order);
    Assert.IsFalse(mItems.Take('b', mOut));
    Assert.AreEqual('', mOut.Id);
    Assert.IsTrue(mItems.Take('a', mOut));
    Assert.AreEqual('A', mOut.Id);
    Assert.AreEqual(cSecond, mOut.Order);
    Assert.AreEqual(0, Integer(Length(mItems.ToArray)));
  finally
    mItems.Free;
  end;
  mOut.Id := '';
end;

procedure TAtlasOrderedItemsTests.FindWithoutItemGivesDefault;
var
  mItems: TEntries;
  mFound: TEntry;
begin
  mItems := TEntries.Create;
  try
    mItems.Put(Entry('a', cSecond));
    Assert.IsTrue(mItems.Find('A', mFound));
    Assert.AreEqual(cSecond, mFound.Order);
    Assert.IsFalse(mItems.Find('b', mFound));
    Assert.AreEqual('', mFound.Id);
    Assert.AreEqual(0, mFound.Order);
  finally
    mItems.Free;
  end;
  mFound.Id := '';
end;

procedure TAtlasOrderedItemsTests.SnapshotStaysUnchanged;
var
  mItems: TEntries;
  mBefore: TArray<TEntry>;
begin
  mItems := TEntries.Create;
  try
    mItems.Put(Entry('a', 1));
    mItems.Put(Entry('b', 2));
    mBefore := mItems.ToArray;
    mItems.Put(Entry('c', 0));
    Assert.IsTrue(mItems.Remove('a'));
    Assert.AreEqual('a;b;', IdsOf(mBefore));
    Assert.AreEqual('c;b;', IdsOf(mItems.ToArray));
  finally
    mItems.Free;
  end;
  mBefore := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOrderedItemsTests);

end.
