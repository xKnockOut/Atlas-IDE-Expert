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
  Guard: TAtlasOutlineLoadGuard;
begin
  Guard := TAtlasOutlineLoadGuard.Create;
  try
    Assert.IsFalse(Guard.Busy);
    Assert.IsTrue(Guard.Remove('a.pas'));
    Assert.IsTrue(Guard.ClearAll);
  finally
    Guard.Free;
  end;
end;

procedure TAtlasOutlineLoadGuardTests.RemoveDuringLoadIsDeferred;
var
  Guard: TAtlasOutlineLoadGuard;
  Clear: Boolean;
  Keys: TArray<string>;
begin
  Guard := TAtlasOutlineLoadGuard.Create;
  try
    Guard.Enter;
    Assert.IsTrue(Guard.Busy);
    Assert.IsFalse(Guard.Remove('a.pas'));
    Assert.IsFalse(Guard.Remove('b.pas'));
    Assert.IsFalse(Guard.Remove('a.pas'));
    Assert.IsTrue(Guard.Leave(Clear, Keys));
    Assert.IsFalse(Clear);
    Assert.AreEqual(2, Integer(Length(Keys)));
    Assert.AreEqual('a.pas', Keys[0]);
    Assert.AreEqual('b.pas', Keys[1]);
    Assert.IsFalse(Guard.Busy);
  finally
    Guard.Free;
  end;
end;

procedure TAtlasOutlineLoadGuardTests.ClearDuringLoadWinsOverKeys;
var
  Guard: TAtlasOutlineLoadGuard;
  Clear: Boolean;
  Keys: TArray<string>;
begin
  Guard := TAtlasOutlineLoadGuard.Create;
  try
    Guard.Enter;
    Guard.Remove('a.pas');
    Assert.IsFalse(Guard.ClearAll);
    Guard.Remove('b.pas');
    Assert.IsTrue(Guard.Leave(Clear, Keys));
    Assert.IsTrue(Clear);
    Assert.AreEqual(0, Integer(Length(Keys)));
  finally
    Guard.Free;
  end;
end;

procedure TAtlasOutlineLoadGuardTests.NestedLoadReturnsOnlyAtTheOutermost;
var
  Guard: TAtlasOutlineLoadGuard;
  Clear: Boolean;
  Keys: TArray<string>;
begin
  Guard := TAtlasOutlineLoadGuard.Create;
  try
    Guard.Enter;
    Guard.Enter;
    Guard.ClearAll;
    Assert.IsFalse(Guard.Leave(Clear, Keys));
    Assert.IsFalse(Clear);
    Assert.IsTrue(Guard.Busy);
    Assert.IsTrue(Guard.Leave(Clear, Keys));
    Assert.IsTrue(Clear);
  finally
    Guard.Free;
  end;
end;

procedure TAtlasOutlineLoadGuardTests.LeaveWithoutPendingReturnsFalse;
var
  Guard: TAtlasOutlineLoadGuard;
  Clear: Boolean;
  Keys: TArray<string>;
begin
  Guard := TAtlasOutlineLoadGuard.Create;
  try
    Guard.Enter;
    Assert.IsFalse(Guard.Leave(Clear, Keys));
    Assert.IsFalse(Clear);
    Assert.AreEqual(0, Integer(Length(Keys)));
    // Überzähliges Leave bleibt ohne Wirkung.
    Assert.IsFalse(Guard.Leave(Clear, Keys));
    Assert.IsFalse(Guard.Busy);
  finally
    Guard.Free;
  end;
end;

procedure TAtlasOutlineLoadGuardTests.PendingIsResetAfterLeave;
var
  Guard: TAtlasOutlineLoadGuard;
  Clear: Boolean;
  Keys: TArray<string>;
begin
  Guard := TAtlasOutlineLoadGuard.Create;
  try
    Guard.Enter;
    Guard.ClearAll;
    Guard.Leave(Clear, Keys);
    Guard.Enter;
    Assert.IsFalse(Guard.Leave(Clear, Keys));
    Assert.IsFalse(Clear);
  finally
    Guard.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOutlineLoadGuardTests);

end.
