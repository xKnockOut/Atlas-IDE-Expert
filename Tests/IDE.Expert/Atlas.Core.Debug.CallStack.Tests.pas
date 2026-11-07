unit Atlas.Core.Debug.CallStack.Tests;

// Tests des Aufrufstapels (#517): oberster Rahmen mit Quelltext, Routine aus
// den Kopfzeilen der IDE (Parameter, Adresse, Versatz).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugCallStackTests = class
  public
    [Test]
    procedure FirstWithSourceSkipsLibraryFrames;
    [Test]
    procedure FirstWithSourceWithoutSource;
    [Test]
    procedure RoutineWithoutParameters;
    [Test]
    procedure RoutineWithoutAddressAndOffset;
  end;

implementation

uses
  Atlas.Core.Debug.CallStack;

{ TAtlasDebugCallStackTests }

procedure TAtlasDebugCallStackTests.FirstWithSourceSkipsLibraryFrames;
var
  mFrames: TAtlasDebugFrames;
begin
  mFrames := [TAtlasDebugFrame.Create(':7714C3E2 KERNELBASE.RaiseException + 0x62', '', 0),
    TAtlasDebugFrame.Create('System._RaiseExcept', 'System.pas', 0),
    TAtlasDebugFrame.Create('Unit1.TForm1.Button1Click(Self=$02A3F2C0)', 'C:\P\Unit1.pas', 42)];
  Assert.AreEqual(2, TAtlasDebugCallStack.FirstWithSource(mFrames), 'Datei ohne Zeile zählt nicht');
  Assert.IsTrue(mFrames[2].HasSource);
  Assert.IsFalse(mFrames[1].HasSource);
  Assert.AreEqual(64, TAtlasDebugCallStack.cMaxFrames);
end;

procedure TAtlasDebugCallStackTests.FirstWithSourceWithoutSource;
var
  mFrames: TAtlasDebugFrames;
begin
  mFrames := nil;
  Assert.AreEqual(-1, TAtlasDebugCallStack.FirstWithSource(mFrames));
  mFrames := [TAtlasDebugFrame.Create(':00401000 Project1.exe', '', 0)];
  Assert.AreEqual(-1, TAtlasDebugCallStack.FirstWithSource(mFrames));
end;

procedure TAtlasDebugCallStackTests.RoutineWithoutParameters;
begin
  Assert.AreEqual('Unit1.TForm1.Button1Click',
    TAtlasDebugFrame.Create('Unit1.TForm1.Button1Click(Self=$02A3F2C0)', '', 0).Routine);
  Assert.AreEqual('Unit1.Laden', TAtlasDebugCallStack.RoutineOf('  Unit1.Laden  '));
  Assert.AreEqual('', TAtlasDebugCallStack.RoutineOf(''));
end;

procedure TAtlasDebugCallStackTests.RoutineWithoutAddressAndOffset;
begin
  Assert.AreEqual('KERNELBASE.RaiseException',
    TAtlasDebugCallStack.RoutineOf(':7714C3E2 KERNELBASE.RaiseException + 0x62'));
  Assert.AreEqual('System.SysUtils.StrToInt',
    TAtlasDebugCallStack.RoutineOf(':00405A1C System.SysUtils.StrToInt(''abc'') + $1C'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugCallStackTests);

end.
