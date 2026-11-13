unit Atlas.Core.Debug.Restart.Tests;

// Tests für „Neu starten“ (#872): Schritte, Abbruch, Zeile der Leiste, Haltepunkte.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasRestartTests = class
  public
    /// <summary>Laufendes Programm mit Änderung: beenden, bauen, starten, zurück.</summary>
    [Test]
    procedure PlansAllSteps;
    /// <summary>Kein Programm, keine Änderung: nur starten und zurück.</summary>
    [Test]
    procedure SkipsStopAndBuild;
    /// <summary>Fehler beim Bauen bricht ab, Starten entfällt.</summary>
    [Test]
    procedure StopsOnFailure;
    /// <summary>Zeile mit Dauer und Zeichen.</summary>
    [Test]
    procedure WritesText;
    /// <summary>Beim Start an, jetzt aus: wieder einschalten.</summary>
    [Test]
    procedure FindsBreakpointsToReenable;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.Restart;

function Captions: TAtlasRestartCaptions;
begin
  Result[TAtlasRestartStep.Stop] := 'Beenden';
  Result[TAtlasRestartStep.Build] := 'Bauen';
  Result[TAtlasRestartStep.Start] := 'Starten';
  Result[TAtlasRestartStep.Return] := 'Zurück';
end;

procedure TAtlasRestartTests.PlansAllSteps;
var
  mRun: TAtlasRestartRun;
  mStep: TAtlasRestartStep;
begin
  mRun := TAtlasRestartRun.Create(True, True);
  try
    Assert.AreEqual(Integer(4), Integer(Length(mRun.Steps)));
    Assert.IsTrue(mRun.Advance(0, mStep));
    Assert.AreEqual(Ord(TAtlasRestartStep.Stop), Ord(mStep));
    Assert.IsTrue(mRun.Advance(100, mStep), 'Advance beendet den laufenden Schritt');
    Assert.AreEqual(Ord(TAtlasRestartStep.Build), Ord(mStep));
    Assert.AreEqual(Ord(TAtlasRestartState.Done), Ord(mRun.Steps[0].State));
    Assert.IsTrue(mRun.Advance(200, mStep));
    Assert.IsTrue(mRun.Advance(300, mStep));
    Assert.AreEqual(Ord(TAtlasRestartStep.Return), Ord(mStep));
    Assert.IsTrue(mRun.Running);
    mRun.Finish(True, 400);
    Assert.IsTrue(mRun.Done);
    Assert.IsFalse(mRun.Advance(500, mStep));
  finally
    mRun.Free;
  end;
end;

procedure TAtlasRestartTests.SkipsStopAndBuild;
var
  mRun: TAtlasRestartRun;
  mStep: TAtlasRestartStep;
begin
  mRun := TAtlasRestartRun.Create(False, False);
  try
    Assert.IsFalse(mRun.Has(TAtlasRestartStep.Stop));
    Assert.IsFalse(mRun.Has(TAtlasRestartStep.Build));
    Assert.IsTrue(mRun.Advance(0, mStep));
    Assert.AreEqual(Ord(TAtlasRestartStep.Start), Ord(mStep));
    Assert.AreEqual(Ord(TAtlasRestartStep.Start), Ord(mRun.Current));
  finally
    mRun.Free;
  end;
end;

procedure TAtlasRestartTests.StopsOnFailure;
var
  mRun: TAtlasRestartRun;
  mStep: TAtlasRestartStep;
begin
  mRun := TAtlasRestartRun.Create(False, True);
  try
    mRun.Advance(0, mStep);
    Assert.AreEqual(Ord(TAtlasRestartStep.Build), Ord(mStep));
    mRun.Finish(False, 50);
    Assert.IsTrue(mRun.Failed);
    Assert.IsFalse(mRun.Running);
    Assert.IsFalse(mRun.Advance(60, mStep), 'nach dem Fehler kein Start');
    Assert.AreEqual(Ord(TAtlasRestartState.Skipped), Ord(mRun.Steps[1].State));
  finally
    mRun.Free;
  end;
end;

procedure TAtlasRestartTests.WritesText;
var
  mRun: TAtlasRestartRun;
  mStep: TAtlasRestartStep;
  mFormat: TFormatSettings;
  mSeparator: Char;
begin
  mFormat := TFormatSettings.Create;
  mFormat.DecimalSeparator := ',';
  Assert.AreEqual('2,1 s', TAtlasRestartRun.SecondsText(2150, mFormat));
  mSeparator := FormatSettings.DecimalSeparator;
  mRun := TAtlasRestartRun.Create(True, True);
  try
    mRun.Advance(1000, mStep);
    mRun.Advance(1300, mStep);
    mRun.Finish(False, 3400);
    FormatSettings.DecimalSeparator := ',';
    Assert.AreEqual('Beenden 0,3 s OK · Bauen X', mRun.Text(Captions, 'OK', 'X'));
  finally
    FormatSettings.DecimalSeparator := mSeparator;
    mRun.Free;
  end;
  mRun := TAtlasRestartRun.Create(False, False);
  try
    mRun.Advance(0, mStep);
    Assert.AreEqual('Starten …', mRun.Text(Captions, 'OK', 'X'));
  finally
    mRun.Free;
  end;
end;

procedure TAtlasRestartTests.FindsBreakpointsToReenable;
var
  mKeys: TArray<string>;
begin
  Assert.AreEqual('C:\A.PAS:12', TAtlasRestartBreakpoints.KeyOf('c:\a.pas', 12));
  mKeys := TAtlasRestartBreakpoints.ToReenable(['A:1', 'B:2'], ['b:2', 'C:3']);
  Assert.AreEqual('b:2', string.Join(',', mKeys));
end;

end.
