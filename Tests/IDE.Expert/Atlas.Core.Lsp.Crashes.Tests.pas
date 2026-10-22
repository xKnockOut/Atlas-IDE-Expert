unit Atlas.Core.Lsp.Crashes.Tests;

// Ende des Serverprozesses: Exit-Codes als Text, Protokollzeile und Anhalten
// nach zweimal derselben Ursache statt stillem Neustart in Schleife.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasServerCrashesTests = class
  public
    [Test]
    procedure DescribesKnownExitCodes;
    [Test]
    procedure RuntimeIsShortText;
    [Test]
    procedure LineNamesCauseRequestAndStderr;
    /// <summary>Zweimal derselbe Code innerhalb von WindowMinutes: anhalten; anderer Code oder später: weiter.
    /// </summary>
    [Test]
    procedure HoldsAfterSameCrashTwice;
    [Test]
    procedure ResetAllowsRestartAgain;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Lsp.Crashes;

procedure TAtlasServerCrashesTests.DescribesKnownExitCodes;
begin
  Assert.AreEqual('Stapelüberlauf (0xC00000FD)', TAtlasServerExits.Describe($C00000FD));
  Assert.AreEqual('Zugriffsverletzung (0xC0000005)', TAtlasServerExits.Describe($C0000005));
  Assert.AreEqual('ohne Fehler (Code 0)', TAtlasServerExits.Describe(0));
  Assert.AreEqual('Code 3', TAtlasServerExits.Describe(3));
  Assert.AreEqual('Ausnahme 0xC0001234', TAtlasServerExits.Describe($C0001234));
  Assert.IsTrue(TAtlasServerExits.Describe(TAtlasServerExits.Unknown).StartsWith('Exit-Code unbekannt'));
end;

procedure TAtlasServerCrashesTests.RuntimeIsShortText;
begin
  Assert.AreEqual('unter 1 s', TAtlasServerExits.Runtime(400));
  Assert.AreEqual('12 s', TAtlasServerExits.Runtime(12500));
  Assert.AreEqual('3 min 5 s', TAtlasServerExits.Runtime(185000));
  Assert.AreEqual('2 h 14 min', TAtlasServerExits.Runtime((2 * 3600 + 14 * 60 + 9) * Int64(1000)));
end;

procedure TAtlasServerCrashesTests.LineNamesCauseRequestAndStderr;
begin
  Assert.AreEqual('Server beendet: Stapelüberlauf (0xC00000FD) nach 3 min 5 s; letzte Anfrage textDocument/hover; ' +
    'offen: textDocument/hover, textDocument/documentSymbol; 4 Zeilen auf stderr (server-stderr.log)',
    TAtlasServerExits.Line($C00000FD, 185000, 'textDocument/hover',
    ['textDocument/hover', 'textDocument/documentSymbol'], 4));
  Assert.AreEqual('Server beendet: Code 3 nach 12 s; nichts auf stderr',
    TAtlasServerExits.Line(3, 12000, '', nil, 0));
end;

procedure TAtlasServerCrashesTests.HoldsAfterSameCrashTwice;
var
  Crashes: TAtlasServerCrashes;
  Clock: TDateTime;
  ClockFunc: TFunc<TDateTime>;
  Code: Cardinal;
begin
  Clock := EncodeDateTime(2026, 10, 22, 12, 0, 0, 0);
  ClockFunc :=
    function: TDateTime
    begin
      Result := Clock;
    end;
  Crashes := TAtlasServerCrashes.Create(ClockFunc);
  try
    Assert.IsFalse(Crashes.LastCode(Code), 'noch kein Absturz');
    Assert.IsTrue(Crashes.Crashed($C0000005), 'erster Absturz: neu starten');
    Clock := IncMinute(Clock, 2);
    Assert.IsTrue(Crashes.Crashed($C00000FD), 'andere Ursache: neu starten');
    Clock := IncMinute(Clock, TAtlasServerCrashes.WindowMinutes + 1);
    Assert.IsTrue(Crashes.Crashed($C00000FD), 'dieselbe Ursache, aber später: neu starten');
    Assert.IsFalse(Crashes.Held);
    Clock := IncMinute(Clock, 3);
    Assert.IsFalse(Crashes.Crashed($C00000FD), 'zweimal dieselbe Ursache in kurzer Zeit: anhalten');
    Assert.IsTrue(Crashes.Held);
    Assert.IsTrue(Crashes.LastCode(Code));
    Assert.AreEqual<Cardinal>($C00000FD, Code);
  finally
    Crashes.Free;
  end;
end;

procedure TAtlasServerCrashesTests.ResetAllowsRestartAgain;
var
  Crashes: TAtlasServerCrashes;
begin
  Crashes := TAtlasServerCrashes.Create(nil);
  try
    Crashes.Crashed(1);
    Assert.IsFalse(Crashes.Crashed(1));
    Assert.IsTrue(Crashes.Held);
    Crashes.Reset;
    Assert.IsFalse(Crashes.Held, 'Neustart von Hand');
    Assert.IsTrue(Crashes.Crashed(1), 'Zählung von vorn');
  finally
    Crashes.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasServerCrashesTests);

end.
