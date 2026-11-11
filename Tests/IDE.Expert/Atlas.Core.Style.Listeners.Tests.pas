unit Atlas.Core.Style.Listeners.Tests;

// Abonnenten des Themenwechsels (#2061): Reihenfolge, Ersetzen, Abmelden auch
// während des Rufens, neu Angemeldete erst beim nächsten Wechsel, Fehler eines
// Rückrufs halten die übrigen nicht auf.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Style.Listeners;

type
  [TestFixture]
  TAtlasThemeListenersTests = class
  private
    FListeners: TAtlasThemeListeners;
    FCalls: string;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CallsInOrderOfSubscription;
    [Test]
    procedure SecondAddReplacesHandler;
    [Test]
    procedure RemovedOwnerIsNotCalled;
    [Test]
    procedure RemoveDuringNotifySkipsOwner;
    [Test]
    procedure AddDuringNotifyWaitsForNextChange;
    [Test]
    procedure FailingHandlerDoesNotStopOthers;
    [Test]
    procedure IgnoresMissingOwnerOrHandler;
  end;

implementation

uses
  System.SysUtils;

procedure TAtlasThemeListenersTests.SetUp;
begin
  FListeners := TAtlasThemeListeners.Create;
  FCalls := '';
end;

procedure TAtlasThemeListenersTests.TearDown;
begin
  FreeAndNil(FListeners);
  FCalls := '';
end;

procedure TAtlasThemeListenersTests.CallsInOrderOfSubscription;
var
  mA, mB: TObject;
begin
  mA := TObject.Create;
  mB := TObject.Create;
  try
    FListeners.Add(mA,
      procedure
      begin
        FCalls := FCalls + 'a';
      end);
    FListeners.Add(mB,
      procedure
      begin
        FCalls := FCalls + 'b';
      end);
    Assert.AreEqual(0, Integer(Length(FListeners.Notify)));
    Assert.AreEqual('ab', FCalls);
    Assert.AreEqual(2, FListeners.Count);
  finally
    mB.Free;
    mA.Free;
  end;
end;

procedure TAtlasThemeListenersTests.SecondAddReplacesHandler;
var
  mA: TObject;
begin
  mA := TObject.Create;
  try
    FListeners.Add(mA,
      procedure
      begin
        FCalls := FCalls + 'alt';
      end);
    FListeners.Add(mA,
      procedure
      begin
        FCalls := FCalls + 'neu';
      end);
    FListeners.Notify;
    Assert.AreEqual('neu', FCalls);
    Assert.AreEqual(1, FListeners.Count);
  finally
    mA.Free;
  end;
end;

procedure TAtlasThemeListenersTests.RemovedOwnerIsNotCalled;
var
  mA: TObject;
begin
  mA := TObject.Create;
  try
    FListeners.Add(mA,
      procedure
      begin
        FCalls := FCalls + 'a';
      end);
    FListeners.Remove(mA);
    // Unbekannte Besitzer werden übergangen.
    FListeners.Remove(mA);
    FListeners.Notify;
    Assert.AreEqual('', FCalls);
    Assert.IsFalse(FListeners.Contains(mA));
  finally
    mA.Free;
  end;
end;

procedure TAtlasThemeListenersTests.RemoveDuringNotifySkipsOwner;
var
  mA, mB: TObject;
begin
  mA := TObject.Create;
  mB := TObject.Create;
  try
    // a schließt beim Wechsel den Dialog b: b darf nicht mehr gerufen werden.
    FListeners.Add(mA,
      procedure
      begin
        FCalls := FCalls + 'a';
        FListeners.Remove(mB);
      end);
    FListeners.Add(mB,
      procedure
      begin
        FCalls := FCalls + 'b';
      end);
    FListeners.Notify;
    Assert.AreEqual('a', FCalls);
  finally
    mB.Free;
    mA.Free;
  end;
end;

procedure TAtlasThemeListenersTests.AddDuringNotifyWaitsForNextChange;
var
  mA, mB: TObject;
begin
  mA := TObject.Create;
  mB := TObject.Create;
  try
    FListeners.Add(mA,
      procedure
      begin
        FCalls := FCalls + 'a';
        FListeners.Add(mB,
          procedure
          begin
            FCalls := FCalls + 'b';
          end);
      end);
    FListeners.Notify;
    Assert.AreEqual('a', FCalls);
    FListeners.Notify;
    Assert.AreEqual('aab', FCalls);
  finally
    mB.Free;
    mA.Free;
  end;
end;

procedure TAtlasThemeListenersTests.FailingHandlerDoesNotStopOthers;
var
  mA, mB: TObject;
  mFailures: TArray<string>;
begin
  mA := TObject.Create;
  mB := TObject.Create;
  try
    FListeners.Add(mA,
      procedure
      begin
        raise EArgumentException.Create('kaputt');
      end);
    FListeners.Add(mB,
      procedure
      begin
        FCalls := FCalls + 'b';
      end);
    mFailures := FListeners.Notify;
    Assert.AreEqual('b', FCalls);
    Assert.AreEqual(1, Integer(Length(mFailures)));
    Assert.AreEqual('EArgumentException: kaputt', mFailures[0]);
  finally
    mB.Free;
    mA.Free;
  end;
end;

procedure TAtlasThemeListenersTests.IgnoresMissingOwnerOrHandler;
var
  mA: TObject;
begin
  mA := TObject.Create;
  try
    FListeners.Add(nil,
      procedure
      begin
        FCalls := FCalls + 'x';
      end);
    FListeners.Add(mA, nil);
    Assert.AreEqual(0, FListeners.Count);
    FListeners.Notify;
    Assert.AreEqual('', FCalls);
  finally
    mA.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasThemeListenersTests);

end.
