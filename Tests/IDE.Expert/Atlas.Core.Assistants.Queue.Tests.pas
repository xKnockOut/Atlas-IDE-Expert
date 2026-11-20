unit Atlas.Core.Assistants.Queue.Tests;

// Tests für die Warteschlange von Aufträgen der KI-Assistenten: Suchen nach Kennung, Entfernen, Reihenfolge.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasAssistantsQueueTests = class
  public
    [Test]
    procedure TryGetFindsByKey;
    [Test]
    procedure TryGetWithoutKeyGivesDefault;
    [Test]
    procedure RemoveKeepsTheOrderOfTheOthers;
  end;

implementation

uses
  Atlas.Core.Assistants.Queue;

type
  TNamed = record
    Key: string;
    Value: Integer;
  end;

  TNamedQueue = class(TAtlasAssistantsQueue<TNamed, string>)
  protected
    function KeyOf(const AItem: TNamed): string; override;
  public
    procedure Put(const AKey: string; AValue: Integer);
    function KeyAt(AIndex: Integer): string;
  end;

function TNamedQueue.KeyOf(const AItem: TNamed): string;
begin
  Result := AItem.Key;
end;

procedure TNamedQueue.Put(const AKey: string; AValue: Integer);
var
  mItem: TNamed;
begin
  mItem.Key := AKey;
  mItem.Value := AValue;
  FItems.Add(mItem);
end;

function TNamedQueue.KeyAt(AIndex: Integer): string;
begin
  Result := FItems[AIndex].Key;
end;

{ TAtlasAssistantsQueueTests }

procedure TAtlasAssistantsQueueTests.TryGetFindsByKey;
var
  mQueue: TNamedQueue;
  mItem: TNamed;
begin
  mQueue := TNamedQueue.Create;
  try
    mQueue.Put('a', 1);
    mQueue.Put('b', 2);
    Assert.IsTrue(mQueue.TryGet('b', mItem));
    Assert.AreEqual(2, mItem.Value);
    Assert.AreEqual(2, mQueue.Count);
  finally
    mQueue.Free;
  end;
end;

procedure TAtlasAssistantsQueueTests.TryGetWithoutKeyGivesDefault;
var
  mQueue: TNamedQueue;
  mItem: TNamed;
begin
  mQueue := TNamedQueue.Create;
  try
    mQueue.Put('a', 1);
    Assert.IsFalse(mQueue.TryGet('x', mItem));
    Assert.AreEqual('', mItem.Key);
    Assert.AreEqual(0, mItem.Value);
    Assert.IsFalse(mQueue.Remove('x'));
  finally
    mQueue.Free;
  end;
end;

procedure TAtlasAssistantsQueueTests.RemoveKeepsTheOrderOfTheOthers;
var
  mQueue: TNamedQueue;
begin
  mQueue := TNamedQueue.Create;
  try
    mQueue.Put('a', 1);
    mQueue.Put('b', 2);
    mQueue.Put('c', 3);
    Assert.IsTrue(mQueue.Remove('b'));
    Assert.AreEqual(2, mQueue.Count);
    Assert.AreEqual('a', mQueue.KeyAt(0));
    Assert.AreEqual('c', mQueue.KeyAt(1));
  finally
    mQueue.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAssistantsQueueTests);

end.
