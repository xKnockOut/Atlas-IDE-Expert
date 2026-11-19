unit Atlas.Core.Debug.KnownErrors.Tests;

// Tests für die Seite des Debuggers bei bekannten Fehlern (#2460): Anfrage aus dem Halt (eigene Rahmen, Rückfall
// auf die Routine der Exception), Antwort des Trackers als Inhalt der Leiste, Knöpfe als Knöpfe des Vertrags und
// der Vertrag mit einem gefälschten Tracker.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugKnownErrorsTests = class
  public
    [Test]
    procedure ReportTakesOwnFramesTopFirst;
    [Test]
    procedure ReportFallsBackToExceptionRoutine;
    [Test]
    procedure BannerOnlyWhenDone;
    [Test]
    procedure ActionsAndKeys;
    [Test]
    procedure ContractWithFakeTracker;
  end;

implementation

uses
  Atlas.Core.KnownErrors.Contract,
  Atlas.IDE.Contracts.KnownErrors,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Exceptions,
  Atlas.Core.Debug.ExceptionBanner,
  Atlas.Core.Debug.KnownErrors;

type
  /// <summary>Tracker zum Schein: antwortet mit einem Treffer und merkt sich Anfrage und Knopf.</summary>
  TFakeKnownErrors = class(TInterfacedObject, IAtlasKnownErrors)
  public
    LastClass: string;
    LastAction: TAtlasKnownErrorAction;
    LastKey: string;
    Runs: Integer;
    function Lookup(const AReport: TAtlasDebugExceptionReport): TAtlasKnownErrorsResult;
    procedure Run(AAction: TAtlasKnownErrorAction; const AReport: TAtlasDebugExceptionReport; const AKey: string);
  end;

function TFakeKnownErrors.Lookup(const AReport: TAtlasDebugExceptionReport): TAtlasKnownErrorsResult;
var
  mError: TAtlasKnownError;
begin
  LastClass := AReport.ExceptionClass;
  Result := Default(TAtlasKnownErrorsResult);
  Result.State := TAtlasKnownErrorsState.Done;
  mError := Default(TAtlasKnownError);
  mError.Key := 'ATL-2210';
  mError.Title := 'Kasse stürzt beim Buchen ab';
  SetLength(Result.Errors, 1);
  Result.Errors[0] := mError;
  Result.CanComment := True;
end;

procedure TFakeKnownErrors.Run(AAction: TAtlasKnownErrorAction; const AReport: TAtlasDebugExceptionReport;
  const AKey: string);
begin
  LastAction := AAction;
  LastKey := AKey;
  Inc(Runs);
end;

function OwnFrame(const AHeader, AFileName: string; ALine: Integer): TAtlasDebugFrame;
begin
  Result := TAtlasDebugFrame.Create(AHeader, AFileName, ALine);
  Result.Own := True;
end;

function Error(const AKey: string; AResolved: Boolean): TAtlasKnownError;
begin
  Result := Default(TAtlasKnownError);
  Result.Key := AKey;
  Result.Resolved := AResolved;
end;

{ TAtlasDebugKnownErrorsTests }

procedure TAtlasDebugKnownErrorsTests.ReportTakesOwnFramesTopFirst;
var
  mException: TAtlasDebugException;
  mReport: TAtlasDebugExceptionReport;
begin
  mException := Default(TAtlasDebugException);
  mException.ExceptionClass := 'EAccessViolation';
  mException.Message := 'Access violation at address 0040A1B2';
  mException.Frames := [TAtlasDebugFrame.Create('Vcl.Controls.TControl.Perform', 'Vcl.Controls.pas', 0),
    OwnFrame('Kasse.TKasse.Buchen(Self=$02A3F2C0)', 'C:\Projekte\Kasse\Kasse.pas', 42),
    OwnFrame('Main.TMain.ButtonClick(Self=$02A3F2C0)', 'C:\Projekte\Kasse\Main.pas', 17)];
  mReport := TAtlasDebugKnownErrors.ReportOf(mException, 'C:\Projekte\Kasse\Kasse.dproj');
  Assert.AreEqual('C:\Projekte\Kasse\Kasse.dproj', mReport.Project);
  Assert.AreEqual('EAccessViolation', mReport.ExceptionClass);
  Assert.AreEqual(Integer(2), Integer(Length(mReport.OwnMethods)), 'RTL/VCL zählt nicht');
  Assert.AreEqual('Kasse.TKasse.Buchen', mReport.OwnMethods[0]);
  Assert.AreEqual('Main.TMain.ButtonClick', mReport.OwnMethods[1]);
  Assert.AreEqual('Kasse.TKasse.Buchen (Kasse.pas:42)', mReport.OwnFrames[0]);
  Assert.AreEqual('C:\Projekte\Kasse\Kasse.pas', mReport.FileName);
  Assert.AreEqual(42, mReport.Line);
  mException := Default(TAtlasDebugException);
  mReport := Default(TAtlasDebugExceptionReport);
end;

procedure TAtlasDebugKnownErrorsTests.ReportFallsBackToExceptionRoutine;
var
  mException: TAtlasDebugException;
  mReport: TAtlasDebugExceptionReport;
begin
  mException := Default(TAtlasDebugException);
  mException.ExceptionClass := 'EConvertError';
  mException.Routine := 'Kasse.TKasse.Lesen';
  mException.FileName := 'C:\Projekte\Kasse\Kasse.pas';
  mException.Line := 7;
  mException.Frames := [TAtlasDebugFrame.Create('System.SysUtils.StrToInt', 'System.SysUtils.pas', 0)];
  mReport := TAtlasDebugKnownErrors.ReportOf(mException, '');
  Assert.AreEqual(Integer(1), Integer(Length(mReport.OwnMethods)));
  Assert.AreEqual('Kasse.TKasse.Lesen', mReport.OwnMethods[0]);
  Assert.AreEqual('Kasse.TKasse.Lesen (Kasse.pas:7)', mReport.OwnFrames[0]);
  Assert.AreEqual(7, mReport.Line);
  mException.Routine := '';
  mReport := TAtlasDebugKnownErrors.ReportOf(mException, '');
  Assert.AreEqual(Integer(0), Integer(Length(mReport.OwnMethods)), 'ganz ohne Ort keine Methode');
  mException := Default(TAtlasDebugException);
  mReport := Default(TAtlasDebugExceptionReport);
end;

procedure TAtlasDebugKnownErrorsTests.BannerOnlyWhenDone;
var
  mResult: TAtlasKnownErrorsResult;
  mKnown: TAtlasDebugBannerKnown;
begin
  mResult := Default(TAtlasKnownErrorsResult);
  mResult.State := TAtlasKnownErrorsState.Busy;
  mResult.Errors := [Error('#7', False)];
  mResult.CanCreate := True;
  mKnown := TAtlasDebugBannerKnown.FromResult(mResult);
  Assert.IsFalse(mKnown.HasErrors, 'während der Suche nichts');
  Assert.IsFalse(mKnown.CanCreate);
  mResult.State := TAtlasKnownErrorsState.Done;
  mKnown := TAtlasDebugBannerKnown.FromResult(mResult);
  Assert.IsTrue(mKnown.HasErrors);
  Assert.IsTrue(mKnown.CanCreate);
  Assert.IsFalse(mKnown.FirstResolved);
  mResult.Errors := [Error('#8', True), Error('#7', False)];
  mKnown := TAtlasDebugBannerKnown.FromResult(mResult);
  Assert.IsTrue(mKnown.FirstResolved);
  mResult := Default(TAtlasKnownErrorsResult);
  mKnown := Default(TAtlasDebugBannerKnown);
end;

procedure TAtlasDebugKnownErrorsTests.ActionsAndKeys;
var
  mKnown: TAtlasDebugBannerKnown;
  mAction: TAtlasKnownErrorAction;
begin
  Assert.IsTrue(TAtlasDebugKnownErrors.ActionOf(TAtlasDebugBarAction.KnownComment, mAction));
  Assert.AreEqual(Ord(TAtlasKnownErrorAction.Comment), Ord(mAction));
  Assert.IsTrue(TAtlasDebugKnownErrors.ActionOf(TAtlasDebugBarAction.KnownReopen, mAction));
  Assert.AreEqual(Ord(TAtlasKnownErrorAction.Reopen), Ord(mAction));
  Assert.IsTrue(TAtlasDebugKnownErrors.ActionOf(TAtlasDebugBarAction.KnownNew, mAction));
  Assert.AreEqual(Ord(TAtlasKnownErrorAction.NewIssue), Ord(mAction));
  Assert.IsFalse(TAtlasDebugKnownErrors.ActionOf(TAtlasDebugBarAction.Copy, mAction), 'kein Knopf des Trackers');
  mKnown := Default(TAtlasDebugBannerKnown);
  Assert.AreEqual('', TAtlasDebugKnownErrors.KeyOf(TAtlasDebugBarAction.KnownOpen, mKnown), 'ohne Treffer');
  mKnown.Errors := [Error('ATL-1', False), Error('ATL-2', False)];
  Assert.AreEqual('ATL-1', TAtlasDebugKnownErrors.KeyOf(TAtlasDebugBarAction.KnownOpen, mKnown), 'bester Treffer');
  Assert.AreEqual('', TAtlasDebugKnownErrors.KeyOf(TAtlasDebugBarAction.KnownNew, mKnown));
  mKnown := Default(TAtlasDebugBannerKnown);
end;

procedure TAtlasDebugKnownErrorsTests.ContractWithFakeTracker;
var
  mFake: TFakeKnownErrors;
  mProvider: IAtlasKnownErrors;
  mReport: TAtlasDebugExceptionReport;
  mKnown: TAtlasDebugBannerKnown;
  mAction: TAtlasKnownErrorAction;
begin
  // Wie die IDE-Seite: Anfrage aus dem Halt, Antwort als Inhalt der Leiste, Knopf zurück an den Tracker.
  mFake := TFakeKnownErrors.Create;
  mProvider := mFake;
  mReport := Default(TAtlasDebugExceptionReport);
  mReport.ExceptionClass := 'EKasse';
  mKnown := TAtlasDebugBannerKnown.FromResult(mProvider.Lookup(mReport));
  Assert.AreEqual('EKasse', mFake.LastClass);
  Assert.AreEqual('ATL-2210', mKnown.Errors[0].Key);
  Assert.IsTrue(TAtlasDebugKnownErrors.ActionOf(TAtlasDebugBarAction.KnownComment, mAction));
  mProvider.Run(mAction, mReport, TAtlasDebugKnownErrors.KeyOf(TAtlasDebugBarAction.KnownComment, mKnown));
  Assert.AreEqual(1, mFake.Runs);
  Assert.AreEqual(Ord(TAtlasKnownErrorAction.Comment), Ord(mFake.LastAction));
  Assert.AreEqual('ATL-2210', mFake.LastKey);
  Assert.IsTrue(TAtlasDebugKnownErrors.ActionOf(TAtlasDebugBarAction.KnownNew, mAction));
  mProvider.Run(mAction, mReport, TAtlasDebugKnownErrors.KeyOf(TAtlasDebugBarAction.KnownNew, mKnown));
  Assert.AreEqual('', mFake.LastKey, 'Neues Issue ohne Kennung');
  mProvider := nil;
  mReport := Default(TAtlasDebugExceptionReport);
  mKnown := Default(TAtlasDebugBannerKnown);
end;

end.
