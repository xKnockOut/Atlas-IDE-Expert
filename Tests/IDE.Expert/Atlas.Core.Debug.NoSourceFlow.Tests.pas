unit Atlas.Core.Debug.NoSourceFlow.Tests;

// Tests für die Entscheidungen der Hilfe „Kein Quelltext“ außerhalb von Ursache und Wegen (#869, #1967): geprüfter
// Halt, Rückkehr zum eigenen Code, ignorierte Stellen, Namen; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasNoSourceFlowTests = class
  public
    [Test]
    procedure WatchesUnlessJustMyCodePause;
    [Test]
    procedure ReturnsUntilOwnFrameOnTop;
    [Test]
    procedure IgnoredByUnitOrModule;
    [Test]
    procedure NamesFallBack;
  end;

implementation

uses
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.NoSource,
  Atlas.Core.Debug.NoSourceFlow;

function Frame(AOwn: Boolean): TAtlasDebugFrame;
begin
  Result := TAtlasDebugFrame.Create('Routine', '', 0);
  Result.Own := AOwn;
end;

function Facts(const AUnit, AModule: string): TAtlasNoSourceFacts;
begin
  Result := Default(TAtlasNoSourceFacts);
  Result.UnitName := AUnit;
  Result.Place.Module := AModule;
  Result.Place.Routine := 'RaiseException';
end;

{ TAtlasNoSourceFlowTests }

procedure TAtlasNoSourceFlowTests.WatchesUnlessJustMyCodePause;
begin
  Assert.IsFalse(TAtlasNoSourceFlow.Watches(False, True, False, False));
  Assert.IsFalse(TAtlasNoSourceFlow.Watches(True, False, True, True));
  Assert.IsTrue(TAtlasNoSourceFlow.Watches(True, True, True, True));
  Assert.IsTrue(TAtlasNoSourceFlow.Watches(True, False, False, True));
  Assert.IsTrue(TAtlasNoSourceFlow.Watches(True, False, True, False));
end;

procedure TAtlasNoSourceFlowTests.ReturnsUntilOwnFrameOnTop;
begin
  Assert.IsTrue(TAtlasNoSourceFlow.HasOwnFrame([Frame(False), Frame(True)]));
  Assert.IsFalse(TAtlasNoSourceFlow.HasOwnFrame([Frame(False)]));
  Assert.IsTrue(TAtlasNoSourceFlow.KeepsReturning([Frame(False), Frame(True)], 0, 20));
  Assert.IsFalse(TAtlasNoSourceFlow.KeepsReturning([Frame(True)], 0, 20));
  Assert.IsFalse(TAtlasNoSourceFlow.KeepsReturning([Frame(False), Frame(True)], 20, 20));
  Assert.IsFalse(TAtlasNoSourceFlow.KeepsReturning([Frame(False)], 0, 20));
  Assert.IsFalse(TAtlasNoSourceFlow.KeepsReturning(nil, 0, 20));
end;

procedure TAtlasNoSourceFlowTests.IgnoredByUnitOrModule;
begin
  Assert.IsTrue(TAtlasNoSourceFlow.Ignored(Facts('System.SysUtils', ''), 'System.SysUtils;Vcl.Forms'));
  Assert.IsTrue(TAtlasNoSourceFlow.Ignored(Facts('', 'KERNELBASE'), 'kernelbase'));
  Assert.IsFalse(TAtlasNoSourceFlow.Ignored(Facts('', ''), 'kernelbase'));
end;

procedure TAtlasNoSourceFlowTests.NamesFallBack;
begin
  Assert.AreEqual('Vcl.Forms', TAtlasNoSourceFlow.IgnoreName(Facts('Vcl.Forms', 'rtl290.bpl')));
  Assert.AreEqual('rtl290.bpl', TAtlasNoSourceFlow.IgnoreName(Facts('', 'rtl290.bpl')));
  Assert.AreEqual('', TAtlasNoSourceFlow.IgnoreName(Facts('', '')));
  Assert.AreEqual('Vcl.Forms.pas', TAtlasNoSourceFlow.SourceName(Facts('Vcl.Forms', '')));
  Assert.AreEqual('RaiseException', TAtlasNoSourceFlow.SourceName(Facts('', 'KERNELBASE')));
  Assert.AreEqual('unbekannt', TAtlasNoSourceFlow.OrUnknown('', 'unbekannt'));
  Assert.AreEqual('$76F3A2B0', TAtlasNoSourceFlow.OrUnknown('$76F3A2B0', 'unbekannt'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNoSourceFlowTests);

end.
