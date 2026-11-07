unit Atlas.Core.Debug.ExceptionBanner.Tests;

// Tests für die Exception-Leiste (#783): Ersetzen oder Rückfall je nach
// Einstellung, IDE-Version und erkanntem Dialog, still fortsetzen nach Klasse
// oder Ort, Kürzung des Aufrufstapels auf die erste eigene Zeile und der
// Knopf „Nur an dieser Stelle ignorieren“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugExceptionBannerTests = class
  public
    [Test]
    procedure KnownVersionsAreDelphi12And13;
    [Test]
    procedure ModeReplacesOnlyKnownDialog;
    [Test]
    procedure AutoContinueByClassOrLocation;
    [Test]
    procedure InfoCutsStackToFirstOwnLine;
    [Test]
    procedure InfoWithoutJustMyCodeShowsTopSource;
    [Test]
    procedure InfoWithoutSourceOffersNoLocation;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Exceptions,
  Atlas.Core.Debug.ExceptionDialog,
  Atlas.Core.Debug.ExceptionBanner;

function Frame(const AHeader, AFile: string; ALine: Integer; AOwn: Boolean): TAtlasDebugFrame;
begin
  Result := TAtlasDebugFrame.Create(AHeader, AFile, ALine);
  Result.Own := AOwn;
end;

/// <summary>StrToFloat('x') in Button1Click: RTL ohne und mit Quelltext über dem eigenen Code.</summary>
function SampleException: TAtlasDebugException;
begin
  Result := TAtlasDebugException.Create(EncodeDate(2026, 10, 23), 'EConvertError', '''x'' ist kein gültiger Wert',
    4711, '').At('C:\BDS\source\rtl\sys\System.SysUtils.pas', 9012, 'System.SysUtils.StrToFloat');
  Result.Count := 3;
  Result.Frames := TArray<TAtlasDebugFrame>.Create(
    Frame(':7714C3E2 KERNELBASE.RaiseException + 0x62', '', 0, False),
    Frame('System.SysUtils.ConvertErrorFmt(...)', 'C:\BDS\source\rtl\sys\System.SysUtils.pas', 9010, False),
    Frame('System.SysUtils.StrToFloat(''x'')', 'C:\BDS\source\rtl\sys\System.SysUtils.pas', 9012, False),
    Frame('Unit1.TForm1.Button1Click(Self=$02A3F2C0)', 'C:\Projekte\Demo\Unit1.pas', 42, True),
    Frame('Project1.Project1', 'C:\Projekte\Demo\Project1.dpr', 18, True));
end;

function Scan(ABreak, AContinue: Integer): TAtlasDebugDialogScan;
begin
  Result := Default(TAtlasDebugDialogScan);
  Result.ExceptionClass := 'EConvertError';
  Result.BreakIndex := ABreak;
  Result.ContinueIndex := AContinue;
end;

{ TAtlasDebugExceptionBannerTests }

procedure TAtlasDebugExceptionBannerTests.KnownVersionsAreDelphi12And13;
begin
  Assert.IsTrue(TAtlasDebugBannerRules.KnownIdeVersion(36.0));
  Assert.IsTrue(TAtlasDebugBannerRules.KnownIdeVersion(37.0));
  Assert.IsFalse(TAtlasDebugBannerRules.KnownIdeVersion(35.0), 'Delphi 11');
  Assert.IsFalse(TAtlasDebugBannerRules.KnownIdeVersion(38.0), 'noch unbekannt');
end;

procedure TAtlasDebugExceptionBannerTests.ModeReplacesOnlyKnownDialog;
var
  mDialog: TAtlasDebugDialogScan;
begin
  mDialog := Scan(0, 1);
  Assert.AreEqual(Ord(TAtlasDebugBannerMode.Off), Ord(TAtlasDebugBannerRules.Mode(False, True, False, mDialog)));
  Assert.AreEqual(Ord(TAtlasDebugBannerMode.Replace), Ord(TAtlasDebugBannerRules.Mode(True, True, False, mDialog)));
  Assert.AreEqual(Ord(TAtlasDebugBannerMode.Additional), Ord(TAtlasDebugBannerRules.Mode(True, False, False, mDialog)),
    'unbekannte IDE-Version: Dialog bleibt');
  Assert.AreEqual(Ord(TAtlasDebugBannerMode.Additional), Ord(TAtlasDebugBannerRules.Mode(True, True, True, mDialog)),
    'IDE-Dialog für die Sitzung verlangt');
  Assert.AreEqual(Ord(TAtlasDebugBannerMode.Additional), Ord(TAtlasDebugBannerRules.Mode(True, True, False,
    Scan(-1, 1))), 'ohne Knopf „Anhalten“');
  Assert.AreEqual(Ord(TAtlasDebugBannerMode.Additional), Ord(TAtlasDebugBannerRules.Mode(True, True, False,
    Default(TAtlasDebugDialogScan))), 'kein Dialog erkannt');
end;

procedure TAtlasDebugExceptionBannerTests.AutoContinueByClassOrLocation;
begin
  Assert.AreEqual(Ord(TAtlasDebugAutoContinue.None), Ord(TAtlasDebugBannerRules.AutoContinue(False, False, True)));
  Assert.AreEqual(Ord(TAtlasDebugAutoContinue.ByClass), Ord(TAtlasDebugBannerRules.AutoContinue(True, True, True)),
    'Klasse vor Ort');
  Assert.AreEqual(Ord(TAtlasDebugAutoContinue.ByLocation),
    Ord(TAtlasDebugBannerRules.AutoContinue(False, True, True)));
  Assert.AreEqual(Ord(TAtlasDebugAutoContinue.None), Ord(TAtlasDebugBannerRules.AutoContinue(False, True, False)),
    'Orte nur mit debug.exceptionBanner.ignoreAtLocation');
end;

procedure TAtlasDebugExceptionBannerTests.InfoCutsStackToFirstOwnLine;
var
  mInfo: TAtlasDebugBannerInfo;
begin
  mInfo := TAtlasDebugBannerRules.Info(SampleException, True, 'C:\Projekte\Demo\Project1.dproj', 'Hauptthread', True);
  Assert.AreEqual('EConvertError', mInfo.ExceptionClass);
  Assert.AreEqual('''x'' ist kein gültiger Wert', mInfo.Message);
  Assert.AreEqual('Hauptthread 4711', mInfo.ThreadText);
  Assert.AreEqual(3, mInfo.Count);
  Assert.AreEqual(3, mInfo.FrameIndex);
  Assert.AreEqual(3, mInfo.Hidden, 'drei Ebenen über dem eigenen Code');
  Assert.AreEqual('Unit1.TForm1.Button1Click', mInfo.Routine);
  Assert.AreEqual('C:\Projekte\Demo\Unit1.pas', mInfo.FileName);
  Assert.AreEqual(42, mInfo.Line);
  Assert.AreEqual('Unit1.pas:42', mInfo.LocationText);
  Assert.IsTrue(mInfo.CanIgnoreLocation);
  Assert.IsFalse(TAtlasDebugBannerRules.Info(SampleException, True, 'C:\P.dproj', '', False).CanIgnoreLocation,
    'Knopf ausgeschaltet');
  Assert.IsFalse(TAtlasDebugBannerRules.Info(SampleException, True, '', '', True).CanIgnoreLocation,
    'ohne Projekt');
end;

procedure TAtlasDebugExceptionBannerTests.InfoWithoutJustMyCodeShowsTopSource;
var
  mInfo: TAtlasDebugBannerInfo;
begin
  mInfo := TAtlasDebugBannerRules.Info(SampleException, False, 'C:\P.dproj', '', True);
  Assert.AreEqual(1, mInfo.FrameIndex);
  Assert.AreEqual(1, mInfo.Hidden, 'nur der Rahmen ohne Quelltext');
  Assert.AreEqual(9010, mInfo.Line);
end;

procedure TAtlasDebugExceptionBannerTests.InfoWithoutSourceOffersNoLocation;
var
  mException: TAtlasDebugException;
  mInfo: TAtlasDebugBannerInfo;
begin
  mException := TAtlasDebugException.Create(Now, 'EAccessViolation', '', 1, 'Worker');
  mException.Frames := TArray<TAtlasDebugFrame>.Create(Frame(':0040A1B2 Demo.Worker', '', 0, False));
  mInfo := TAtlasDebugBannerRules.Info(mException, True, 'C:\P.dproj', 'Hauptthread', True);
  Assert.AreEqual(-1, mInfo.FrameIndex);
  Assert.AreEqual(0, mInfo.Hidden);
  Assert.AreEqual('Demo.Worker', mInfo.Routine, 'Adresse entfällt');
  Assert.AreEqual('Worker (1)', mInfo.ThreadText);
  Assert.AreEqual(1, mInfo.Count, 'mindestens einmal');
  Assert.AreEqual('', mInfo.LocationText);
  Assert.IsFalse(mInfo.CanIgnoreLocation);
end;

end.
