unit Atlas.Core.Debug.AssistantControl.Tests;

// Tests für die Debug-Steuerung durch KI-Assistenten (#1874) ohne IDE: Startparameter mit und ohne Test, Rahmen für
// den Vertrag, Ort des Halts und Grund des Halts.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugAssistantControlTests = class
  public
    [Test]
    procedure KeepsProjectParametersWithoutOwn;
    [Test]
    procedure OwnArgumentsReplaceProjectParameters;
    /// <summary>Akzeptanzkriterium: mit test läuft nur dieser DUnitX-Test, ohne Warten am Ende.</summary>
    [Test]
    procedure TestAddsRunAndExitBehavior;
    [Test]
    procedure NeedsParametersOnlyForArgumentsOrTest;
    [Test]
    procedure FramesAreCutAtMax;
    [Test]
    procedure LocationIsFirstFrameWithSource;
    [Test]
    procedure LocationFailsWithoutSource;
    [Test]
    procedure StopReasonPrefersException;
  end;

implementation

uses
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.AssistantControl,
  Atlas.Core.DebugControl.Types;

function LaunchOf(const AArguments, ATest: string): TAtlasDebugControlLaunch;
begin
  Result := Default(TAtlasDebugControlLaunch);
  Result.Arguments := AArguments;
  Result.Test := ATest;
end;

function ThreeFrames: TAtlasDebugFrames;
begin
  Result := nil;
  SetLength(Result, 3);
  Result[0] := TAtlasDebugFrame.Create('System.@RaiseExcept', '', 0);
  Result[1] := TAtlasDebugFrame.Create('Main.TForm1.Button1Click(...)', 'C:\P\Main.pas', 42);
  Result[1].Own := True;
  Result[2] := TAtlasDebugFrame.Create('Vcl.Controls.TControl.Click', 'C:\RTL\Vcl.Controls.pas', 7);
end;

{ TAtlasDebugAssistantControlTests }

procedure TAtlasDebugAssistantControlTests.KeepsProjectParametersWithoutOwn;
begin
  Assert.AreEqual('-a -b', TAtlasDebugAssistantControl.Parameters(' -a -b ', LaunchOf('', '')));
end;

procedure TAtlasDebugAssistantControlTests.OwnArgumentsReplaceProjectParameters;
begin
  Assert.AreEqual('--x', TAtlasDebugAssistantControl.Parameters('-a', LaunchOf('--x', '')));
end;

procedure TAtlasDebugAssistantControlTests.TestAddsRunAndExitBehavior;
begin
  Assert.AreEqual('-a --run:Unit.Fixture.Method --exitbehavior:Continue',
    TAtlasDebugAssistantControl.Parameters('-a', LaunchOf('', 'Unit.Fixture.Method')));
  Assert.AreEqual('--run:A.B.C --exitbehavior:Continue',
    TAtlasDebugAssistantControl.Parameters('', LaunchOf('', ' A.B.C ')));
end;

procedure TAtlasDebugAssistantControlTests.NeedsParametersOnlyForArgumentsOrTest;
begin
  Assert.IsFalse(TAtlasDebugAssistantControl.NeedsParameters(LaunchOf(' ', '')));
  Assert.IsTrue(TAtlasDebugAssistantControl.NeedsParameters(LaunchOf('-a', '')));
  Assert.IsTrue(TAtlasDebugAssistantControl.NeedsParameters(LaunchOf('', 'A.B.C')));
end;

procedure TAtlasDebugAssistantControlTests.FramesAreCutAtMax;
var
  mFrames: TArray<TAtlasDebugControlFrame>;
begin
  mFrames := TAtlasDebugAssistantControl.Frames(ThreeFrames, 2);
  Assert.AreEqual(2, Integer(Length(mFrames)));
  Assert.AreEqual('C:\P\Main.pas', mFrames[1].FileName);
  Assert.AreEqual(42, mFrames[1].Line);
  Assert.IsTrue(mFrames[1].Own);
  Assert.AreEqual(0, Integer(Length(TAtlasDebugAssistantControl.Frames(ThreeFrames, 0))));
end;

procedure TAtlasDebugAssistantControlTests.LocationIsFirstFrameWithSource;
var
  mFileName: string;
  mLine: Integer;
begin
  Assert.IsTrue(TAtlasDebugAssistantControl.Location(ThreeFrames, mFileName, mLine));
  Assert.AreEqual('C:\P\Main.pas', mFileName);
  Assert.AreEqual(42, mLine);
end;

procedure TAtlasDebugAssistantControlTests.LocationFailsWithoutSource;
var
  mFrames: TAtlasDebugFrames;
  mFileName: string;
  mLine: Integer;
begin
  mFrames := Copy(ThreeFrames, 0, 1);
  Assert.IsFalse(TAtlasDebugAssistantControl.Location(mFrames, mFileName, mLine));
  Assert.AreEqual('', mFileName);
  Assert.AreEqual(0, mLine);
end;

procedure TAtlasDebugAssistantControlTests.StopReasonPrefersException;
begin
  Assert.AreEqual('exception', TAtlasDebugAssistantControl.cStopNames[TAtlasDebugAssistantControl.StopOf(True, True,
    True)]);
  Assert.AreEqual('breakpoint', TAtlasDebugAssistantControl.cStopNames[TAtlasDebugAssistantControl.StopOf(False,
    True, True)]);
  Assert.AreEqual('step', TAtlasDebugAssistantControl.cStopNames[TAtlasDebugAssistantControl.StopOf(False, False,
    True)]);
  Assert.AreEqual('pause', TAtlasDebugAssistantControl.cStopNames[TAtlasDebugAssistantControl.StopOf(False, False,
    False)]);
end;

end.
