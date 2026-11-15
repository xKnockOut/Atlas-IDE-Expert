unit Atlas.Core.Tracker.AttachPlan.Tests;

// Tests von „An Issue anhängen …“ ohne IDE (#1967): ob es etwas zu senden gibt, Meldung nach dem Senden und
// anonymes Protokoll.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasAttachPlanTests = class
  public
    [Test]
    procedure WorkNeedsKeyAndContent;
    [Test]
    procedure ReportAfterFailure;
    [Test]
    procedure ReportAfterSuccess;
    [Test]
    procedure LogIsAnonymous;
  end;

implementation

uses
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.AttachPlan;

function Report(ASucceeded: Boolean; AError: TAtlasCiFetchError; AUploaded: Integer; ACommented,
  AFallback: Boolean): Integer;
begin
  Result := Ord(TAtlasAttachPlan.ReportOf(ASucceeded, AError, AUploaded, ACommented, AFallback));
end;

procedure TAtlasAttachPlanTests.WorkNeedsKeyAndContent;
begin
  Assert.IsTrue(TAtlasAttachPlan.HasWork('ATL-1', 1, ''));
  Assert.IsTrue(TAtlasAttachPlan.HasWork('ATL-1', 0, 'Notiz'));
  Assert.IsFalse(TAtlasAttachPlan.HasWork('ATL-1', 0, ''), 'nichts gewählt');
  Assert.IsFalse(TAtlasAttachPlan.HasWork('', 2, 'Notiz'), 'ohne Kennung');
end;

procedure TAtlasAttachPlanTests.ReportAfterFailure;
begin
  Assert.AreEqual(Integer(Ord(TAtlasAttachReport.Silent)), Report(False, TAtlasCiFetchError.Cancelled, 2, False,
    False), 'abgebrochen');
  Assert.AreEqual(Integer(Ord(TAtlasAttachReport.CommentFailed)), Report(False, TAtlasCiFetchError.Network, 2, False,
    False), 'Dateien oben, Kommentar gescheitert');
  Assert.AreEqual(Integer(Ord(TAtlasAttachReport.Failed)), Report(False, TAtlasCiFetchError.Unauthorized, 0, False,
    False));
end;

procedure TAtlasAttachPlanTests.ReportAfterSuccess;
begin
  Assert.AreEqual(Integer(Ord(TAtlasAttachReport.Fallback)), Report(True, TAtlasCiFetchError.None, 0, True, True),
    'GitHub');
  Assert.AreEqual(Integer(Ord(TAtlasAttachReport.DoneComment)), Report(True, TAtlasCiFetchError.None, 2, True,
    False));
  Assert.AreEqual(Integer(Ord(TAtlasAttachReport.Done)), Report(True, TAtlasCiFetchError.None, 2, False, False));
  Assert.AreEqual(Integer(Ord(TAtlasAttachReport.Commented)), Report(True, TAtlasCiFetchError.None, 0, True, False));
  Assert.AreEqual(Integer(Ord(TAtlasAttachReport.Nothing)), Report(True, TAtlasCiFetchError.None, 0, False, False));
end;

procedure TAtlasAttachPlanTests.LogIsAnonymous;
begin
  Assert.AreEqual('Anhängen: GitHub, 2 Dateien, gesendet', TAtlasAttachPlan.SentLog('GitHub', 2, True,
    TAtlasCiFetchError.None));
  Assert.AreEqual('Anhängen: YouTrack, 1 Dateien, nicht gesendet (' +
    TAtlasCiBuild.ErrorKey(TAtlasCiFetchError.Timeout) + ')', TAtlasAttachPlan.SentLog('YouTrack', 1, False,
    TAtlasCiFetchError.Timeout));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAttachPlanTests);

end.
