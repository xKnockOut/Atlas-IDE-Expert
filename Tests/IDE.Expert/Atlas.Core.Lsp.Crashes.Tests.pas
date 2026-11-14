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
    /// <summary>Mit englischer Oberfläche englische Namen, Codes unverändert (#1458).</summary>
    [Test]
    procedure DescribesExitCodesInEnglish;
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
  Atlas.Core.Localization.Language,
  Atlas.Core.Lsp.Crashes;

procedure TAtlasServerCrashesTests.DescribesKnownExitCodes;
begin
  Assert.AreEqual('Stapelüberlauf (0xC00000FD)', TAtlasServerExits.Describe($C00000FD));
  Assert.AreEqual('Zugriffsverletzung (0xC0000005)', TAtlasServerExits.Describe($C0000005));
  Assert.AreEqual('ohne Fehler (Code 0)', TAtlasServerExits.Describe(0));
  Assert.AreEqual('Code 3', TAtlasServerExits.Describe(3));
  Assert.AreEqual('Ausnahme 0xC0001234', TAtlasServerExits.Describe($C0001234));
  Assert.IsTrue(TAtlasServerExits.Describe(TAtlasServerExits.cUnknown).StartsWith('Exit-Code unbekannt'));
end;

procedure TAtlasServerCrashesTests.DescribesExitCodesInEnglish;
var
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasTextLanguage.Current;
  TAtlasTextLanguage.Current := TAtlasLanguage.English;
  try
    Assert.AreEqual('stack overflow (0xC00000FD)', TAtlasServerExits.Describe($C00000FD));
    Assert.AreEqual('without error (code 0)', TAtlasServerExits.Describe(0));
    Assert.AreEqual('Exception 0xC0001234', TAtlasServerExits.Describe($C0001234));
  finally
    TAtlasTextLanguage.Current := mSaved;
  end;
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
  mCrashes: TAtlasServerCrashes;
  mClock: TDateTime;
  mClockFunc: TFunc<TDateTime>;
  mCode: Cardinal;
begin
  mClock := EncodeDateTime(2026, 10, 22, 12, 0, 0, 0);
  mClockFunc :=
    function: TDateTime
    begin
      Result := mClock;
    end;
  mCrashes := TAtlasServerCrashes.Create(mClockFunc);
  try
    Assert.IsFalse(mCrashes.LastCode(mCode), 'noch kein Absturz');
    Assert.IsTrue(mCrashes.Crashed($C0000005), 'erster Absturz: neu starten');
    mClock := IncMinute(mClock, 2);
    Assert.IsTrue(mCrashes.Crashed($C00000FD), 'andere Ursache: neu starten');
    mClock := IncMinute(mClock, TAtlasServerCrashes.cWindowMinutes + 1);
    Assert.IsTrue(mCrashes.Crashed($C00000FD), 'dieselbe Ursache, aber später: neu starten');
    Assert.IsFalse(mCrashes.Held);
    mClock := IncMinute(mClock, 3);
    Assert.IsFalse(mCrashes.Crashed($C00000FD), 'zweimal dieselbe Ursache in kurzer Zeit: anhalten');
    Assert.IsTrue(mCrashes.Held);
    Assert.IsTrue(mCrashes.LastCode(mCode));
    Assert.AreEqual<Cardinal>($C00000FD, mCode);
  finally
    mCrashes.Free;
  end;
end;

procedure TAtlasServerCrashesTests.ResetAllowsRestartAgain;
var
  mCrashes: TAtlasServerCrashes;
begin
  mCrashes := TAtlasServerCrashes.Create(nil);
  try
    mCrashes.Crashed(1);
    Assert.IsFalse(mCrashes.Crashed(1));
    Assert.IsTrue(mCrashes.Held);
    mCrashes.Reset;
    Assert.IsFalse(mCrashes.Held, 'Neustart von Hand');
    Assert.IsTrue(mCrashes.Crashed(1), 'Zählung von vorn');
  finally
    mCrashes.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasServerCrashesTests);

end.
