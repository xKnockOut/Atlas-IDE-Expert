unit Atlas.Core.Outline.LoadGuard.Tests;

// Wächter des Gliederungsstands: Ohne Abfrage wirkt Entfernen und Leeren
// sofort; während einer Abfrage wird es vorgemerkt und nach der äußersten
// Abfrage zurückgegeben.
// lsp-ignore-file: lock-without-finally -- der Wächter ist keine Sperre; die Tests prüfen Enter und Leave einzeln

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasOutlineLoadGuardTests = class
  public
    [Test]
    procedure WithoutLoadEverythingIsImmediate;
    [Test]
    procedure RemoveDuringLoadIsDeferred;
    [Test]
    procedure ClearDuringLoadWinsOverKeys;
    [Test]
    procedure NestedLoadReturnsOnlyAtTheOutermost;
    [Test]
    procedure LeaveWithoutPendingReturnsFalse;
    [Test]
    procedure PendingIsResetAfterLeave;
  end;

implementation

uses
  Atlas.Core.Outline.LoadGuard;

{ TAtlasOutlineLoadGuardTests }

procedure TAtlasOutlineLoadGuardTests.WithoutLoadEverythingIsImmediate;
var
  mGuard: TAtlasOutlineLoadGuard;
begin
  mGuard := TAtlasOutlineLoadGuard.Create;
  try
    Assert.IsFalse(mGuard.Busy);
    Assert.IsTrue(mGuard.Remove('a.pas'));
    Assert.IsTrue(mGuard.ClearAll);
  finally
    mGuard.Free;
  end;
end;

procedure TAtlasOutlineLoadGuardTests.RemoveDuringLoadIsDeferred;
var
  mGuard: TAtlasOutlineLoadGuard;
  mClear: Boolean;
  mKeys: TArray<string>;
begin
  mGuard := TAtlasOutlineLoadGuard.Create;
  try
    mGuard.Enter;
    Assert.IsTrue(mGuard.Busy);
    Assert.IsFalse(mGuard.Remove('a.pas'));
    Assert.IsFalse(mGuard.Remove('b.pas'));
    Assert.IsFalse(mGuard.Remove('a.pas'));
    Assert.IsTrue(mGuard.Leave(mClear, mKeys));
    Assert.IsFalse(mClear);
    Assert.AreEqual(2, Integer(Length(mKeys)));
    Assert.AreEqual('a.pas', mKeys[0]);
    Assert.AreEqual('b.pas', mKeys[1]);
    Assert.IsFalse(mGuard.Busy);
  finally
    mGuard.Free;
  end;
end;

procedure TAtlasOutlineLoadGuardTests.ClearDuringLoadWinsOverKeys;
var
  mGuard: TAtlasOutlineLoadGuard;
  mClear: Boolean;
  mKeys: TArray<string>;
begin
  mGuard := TAtlasOutlineLoadGuard.Create;
  try
    mGuard.Enter;
    mGuard.Remove('a.pas');
    Assert.IsFalse(mGuard.ClearAll);
    mGuard.Remove('b.pas');
    Assert.IsTrue(mGuard.Leave(mClear, mKeys));
    Assert.IsTrue(mClear);
    Assert.AreEqual(0, Integer(Length(mKeys)));
  finally
    mGuard.Free;
  end;
end;

procedure TAtlasOutlineLoadGuardTests.NestedLoadReturnsOnlyAtTheOutermost;
var
  mGuard: TAtlasOutlineLoadGuard;
  mClear: Boolean;
  mKeys: TArray<string>;
begin
  mGuard := TAtlasOutlineLoadGuard.Create;
  try
    mGuard.Enter;
    mGuard.Enter;
    mGuard.ClearAll;
    Assert.IsFalse(mGuard.Leave(mClear, mKeys));
    Assert.IsFalse(mClear);
    Assert.IsTrue(mGuard.Busy);
    Assert.IsTrue(mGuard.Leave(mClear, mKeys));
    Assert.IsTrue(mClear);
  finally
    mGuard.Free;
  end;
end;

procedure TAtlasOutlineLoadGuardTests.LeaveWithoutPendingReturnsFalse;
var
  mGuard: TAtlasOutlineLoadGuard;
  mClear: Boolean;
  mKeys: TArray<string>;
begin
  mGuard := TAtlasOutlineLoadGuard.Create;
  try
    mGuard.Enter;
    Assert.IsFalse(mGuard.Leave(mClear, mKeys));
    Assert.IsFalse(mClear);
    Assert.AreEqual(0, Integer(Length(mKeys)));
    // Überzähliges Leave bleibt ohne Wirkung.
    Assert.IsFalse(mGuard.Leave(mClear, mKeys));
    Assert.IsFalse(mGuard.Busy);
  finally
    mGuard.Free;
  end;
end;

procedure TAtlasOutlineLoadGuardTests.PendingIsResetAfterLeave;
var
  mGuard: TAtlasOutlineLoadGuard;
  mClear: Boolean;
  mKeys: TArray<string>;
begin
  mGuard := TAtlasOutlineLoadGuard.Create;
  try
    mGuard.Enter;
    mGuard.ClearAll;
    mGuard.Leave(mClear, mKeys);
    mGuard.Enter;
    Assert.IsFalse(mGuard.Leave(mClear, mKeys));
    Assert.IsFalse(mClear);
  finally
    mGuard.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOutlineLoadGuardTests);

end.
