unit Atlas.Common.Lsp.WorkspaceCheck.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspWorkspaceCheckTests = class
  public
    [Test]
    procedure RunHasBeginAndEnd;
    [Test]
    procedure NothingRunsBeforeWant;
    [Test]
    procedure UnchangedFilesKeepTheirIds;
    [Test]
    procedure ForcedStartChecksAll;
    [Test]
    procedure AffectedChecksFileAndDependents;
    [Test]
    procedure ChangedStampIsCheckedAgain;
    [Test]
    procedure PauseHoldsRun;
    [Test]
    procedure PauseLimitIsSafetyNet;
    [Test]
    procedure IndexBuildHoldsRun;
    [Test]
    procedure TypingInterruptsAndRequeues;
    [Test]
    procedure ForegroundDefersNextFile;
    [Test]
    procedure SlowFileFinishesAtEnd;
    [Test]
    procedure FailingFileIsSkipped;
    [Test]
    procedure OpenFilesAreLeftToEditor;
    [Test]
    procedure RemovedFilesDropReports;
    [Test]
    procedure RunAsJson;
    [Test]
    procedure DependentsOfFindsUsesAndIncludes;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.SyncObjs,
  System.Diagnostics,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.WorkspaceCheck;

const
  cFileA = 'C:\P\A.pas';
  cFileB = 'C:\P\B.pas';
  cFileC = 'C:\P\C.pas';
  cIdleMs = 5000;

type
  /// <summary>Projektprüfung mit drei Dateien; Diagnose meldet je Datei einen Befund mit ihrer Uri.</summary>
  TFixture = class
  public
    Check: TLspWorkspaceCheck;
    Files: TArray<string>;
    Stamp: Int64;
    // Datei -> Verhalten: '' normal, 'slow' bis Abbruch bzw. 300 ms, 'fail' Ausnahme.
    Behavior: TDictionary<string, string>;
    Open: string;
    Order: TStringList;
    Lines: TStringList;
    Lock: TObject;
    constructor Create;
    destructor Destroy; override;
    function Diagnose(const ADocument: ITextDocument; const ACancellation: IJsonRpcCancellationToken): TJSONArray;
    function Collect: TJSONArray;
    function Ids: TDictionary<string, string>;
    function Logged: string;
  end;

constructor TFixture.Create;
var
  mSelf: TFixture;
begin
  inherited Create;
  mSelf := Self;
  Files := TArray<string>.Create(cFileA, cFileB, cFileC);
  Stamp := 42;
  Behavior := TDictionary<string, string>.Create;
  Order := TStringList.Create;
  Lines := TStringList.Create;
  Lock := TObject.Create;
  Check := TLspWorkspaceCheck.Create(
    function: TArray<string>
    begin
      Result := mSelf.Files;
    end,
    function(const AFileName: string; out AStamp: Int64): Boolean
    begin
      AStamp := mSelf.Stamp;
      Result := True;
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := 'unit X; interface implementation end.';
      Result := True;
    end,
    function(const AUri: string): Boolean
    begin
      Result := (mSelf.Open <> '') and (AUri = TDocumentUris.FromPath(mSelf.Open));
    end,
    function(const ADocument: ITextDocument; const ACancellation: IJsonRpcCancellationToken): TJSONArray
    begin
      Result := mSelf.Diagnose(ADocument, ACancellation);
    end);
  Check.OnLog :=
    procedure(const AMessage: string)
    begin
      TMonitor.Enter(mSelf.Lock);
      try
        mSelf.Lines.Add(AMessage);
      finally
        TMonitor.Exit(mSelf.Lock);
      end;
    end;
  Check.FileLabel :=
    function(const AFileName: string): string
    begin
      Result := 'unit#' + ChangeFileExt(ExtractFileName(AFileName), '');
    end;
end;

destructor TFixture.Destroy;
begin
  Check.Free;
  Lock.Free;
  Lines.Free;
  Order.Free;
  Behavior.Free;
  Files := nil;
  inherited;
end;

function TFixture.Diagnose(const ADocument: ITextDocument;
  const ACancellation: IJsonRpcCancellationToken): TJSONArray;
var
  mFileName, mKind: string;
  mPair: TPair<string, string>;
  mClock: TStopwatch;
begin
  // Laufwerksbuchstaben kommen aus der Uri klein zurück.
  mFileName := TDocumentUris.ToPath(ADocument.Uri);
  mKind := '';
  for mPair in Behavior do
    if SameText(mPair.Key, mFileName) then
      mKind := mPair.Value;
  if mKind = 'fail' then
    raise EArgumentException.Create('Unit kaputt');
  if mKind = 'slow' then
  begin
    mClock := TStopwatch.StartNew;
    while mClock.ElapsedMilliseconds < 300 do
    begin
      ACancellation.ThrowIfCancellationRequested;
      Sleep(5);
    end;
  end;
  TMonitor.Enter(Lock);
  try
    Order.Add(ExtractFileName(mFileName));
  finally
    TMonitor.Exit(Lock);
  end;
  Result := TJSONArray.Create;
  Result.AddElement(TJSONObject.Create.AddPair('message', ADocument.Uri));
end;

function TFixture.Collect: TJSONArray;
var
  mNone: TDictionary<string, string>;
begin
  mNone := TDictionary<string, string>.Create;
  try
    Result := Check.Collect(mNone, 100);
  finally
    mNone.Free;
  end;
end;

function TFixture.Ids: TDictionary<string, string>;
var
  mReports: TJSONArray;
  mReport: TJSONValue;
begin
  Result := TDictionary<string, string>.Create;
  mReports := Collect;
  try
    for mReport in mReports do
      Result.AddOrSetValue(mReport.GetValue<string>('uri'), mReport.GetValue<string>('resultId'));
  finally
    mReports.Free;
  end;
end;

function TFixture.Logged: string;
begin
  TMonitor.Enter(Lock);
  try
    Result := Lines.Text;
  finally
    TMonitor.Exit(Lock);
  end;
end;

function UriOf(AReport: TJSONValue): string;
begin
  Result := AReport.GetValue<string>('uri');
end;

procedure TLspWorkspaceCheckTests.RunHasBeginAndEnd;
var
  mFixture: TFixture;
  mRun: TWorkspaceCheckRun;
  mReports: TJSONArray;
begin
  mFixture := TFixture.Create;
  try
    mFixture.Check.Want;
    Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs), 'Lauf endet');
    mRun := mFixture.Check.Run;
    Assert.IsFalse(mRun.Active);
    Assert.AreEqual(1, mRun.Serial);
    Assert.AreEqual(3, mRun.Done);
    Assert.AreEqual(3, mRun.Total);
    Assert.AreEqual(3, mFixture.Check.Computed);
    mReports := mFixture.Collect;
    try
      Assert.AreEqual(3, Integer(mReports.Count));
      Assert.AreEqual('full', mReports.Items[0].GetValue<string>('kind'));
      Assert.AreEqual(1, Integer(mReports.Items[0].GetValue<TJSONArray>('items').Count));
    finally
      mReports.Free;
    end;
    Assert.Contains(mFixture.Logged, 'Projektprüfung fertig: 3 Units');
    // Danach ruht die Prüfung.
    Sleep(200);
    Assert.AreEqual(3, mFixture.Check.Computed);
  finally
    mFixture.Free;
  end;
end;

procedure TLspWorkspaceCheckTests.NothingRunsBeforeWant;
var
  mFixture: TFixture;
begin
  // Ohne Projektprüfung im Client (keine Anfrage workspace/diagnostic) kostet sie nichts.
  mFixture := TFixture.Create;
  try
    mFixture.Check.Start(True);
    mFixture.Check.Affected(TArray<string>.Create(cFileA), True);
    Sleep(200);
    Assert.AreEqual(0, mFixture.Check.Computed);
    Assert.AreEqual(0, mFixture.Check.Run.Serial);
  finally
    mFixture.Free;
  end;
end;

procedure TLspWorkspaceCheckTests.UnchangedFilesKeepTheirIds;
var
  mFixture: TFixture;
  mIds: TDictionary<string, string>;
  mReports: TJSONArray;
begin
  mFixture := TFixture.Create;
  try
    mFixture.Check.Want;
    Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
    mIds := mFixture.Ids;
    try
      mFixture.Check.Start(False);
      Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
      Assert.AreEqual(3, mFixture.Check.Computed, 'unverändert: nicht neu geprüft');
      Assert.AreEqual(3, mFixture.Check.Run.Done, 'zählen trotzdem als erledigt');
      mReports := mFixture.Check.Collect(mIds, 100);
      try
        Assert.AreEqual(0, Integer(mReports.Count), 'nichts Neues');
      finally
        mReports.Free;
      end;
    finally
      mIds.Free;
    end;
  finally
    mFixture.Free;
  end;
end;

procedure TLspWorkspaceCheckTests.ForcedStartChecksAll;
var
  mFixture: TFixture;
  mIds: TDictionary<string, string>;
  mReports: TJSONArray;
begin
  mFixture := TFixture.Create;
  try
    mFixture.Check.Want;
    Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
    mIds := mFixture.Ids;
    try
      mFixture.Check.Start(True);
      Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
      Assert.AreEqual(6, mFixture.Check.Computed);
      Assert.AreEqual(2, mFixture.Check.Run.Serial, 'neuer Lauf');
      mReports := mFixture.Check.Collect(mIds, 100);
      try
        Assert.AreEqual(3, Integer(mReports.Count), 'neue Ids');
      finally
        mReports.Free;
      end;
    finally
      mIds.Free;
    end;
  finally
    mFixture.Free;
  end;
end;

procedure TLspWorkspaceCheckTests.AffectedChecksFileAndDependents;
var
  mFixture: TFixture;
  mIds: TDictionary<string, string>;
  mReports: TJSONArray;
  mUris: TStringList;
  mReport: TJSONValue;
begin
  mFixture := TFixture.Create;
  mUris := TStringList.Create;
  try
    mFixture.Check.Dependents :=
      function(const AFileName: string): TArray<string>
      begin
        Result := nil;
        // B hat A in uses; D gehört nicht zum Projekt.
        if SameText(AFileName, cFileA) then
          Result := TArray<string>.Create(cFileB, 'C:\Anderswo\D.pas');
      end;
    mFixture.Check.Want;
    Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
    mIds := mFixture.Ids;
    try
      mFixture.Check.Affected(TArray<string>.Create(cFileA), True);
      Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
      Assert.AreEqual(5, mFixture.Check.Computed, 'nur A und B');
      Assert.AreEqual(2, mFixture.Check.Run.Total);
      mReports := mFixture.Check.Collect(mIds, 100);
      try
        for mReport in mReports do
          mUris.Add(UriOf(mReport));
        mUris.Sort;
        Assert.AreEqual(2, mUris.Count);
        Assert.AreEqual(TDocumentUris.FromPath(cFileA), mUris[0]);
        Assert.AreEqual(TDocumentUris.FromPath(cFileB), mUris[1]);
      finally
        mReports.Free;
      end;
    finally
      mIds.Free;
    end;
    // Ohne Abhängige nur die Datei selbst (neue Compilermeldungen).
    mFixture.Check.Affected(TArray<string>.Create(cFileC), False);
    Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
    Assert.AreEqual(6, mFixture.Check.Computed);
  finally
    mUris.Free;
    mFixture.Free;
  end;
end;

procedure TLspWorkspaceCheckTests.ChangedStampIsCheckedAgain;
var
  mFixture: TFixture;
begin
  mFixture := TFixture.Create;
  try
    mFixture.Check.Want;
    Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
    mFixture.Stamp := 43;
    mFixture.Check.Start(False);
    Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
    Assert.AreEqual(6, mFixture.Check.Computed);
  finally
    mFixture.Free;
  end;
end;

procedure TLspWorkspaceCheckTests.PauseHoldsRun;
var
  mFixture: TFixture;
  mRun: TWorkspaceCheckRun;
begin
  mFixture := TFixture.Create;
  try
    mFixture.Check.Pause(TLspWorkspaceCheck.cPauseCompile, True);
    mFixture.Check.Want;
    Sleep(300);
    mRun := mFixture.Check.Run;
    Assert.AreEqual(0, mFixture.Check.Computed, 'nichts während des Kompilierens');
    Assert.IsTrue(mRun.Active);
    Assert.AreEqual(TLspWorkspaceCheck.cPauseCompile, mRun.Paused);
    mFixture.Check.Pause(TLspWorkspaceCheck.cPauseCompile, False);
    Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
    Assert.AreEqual(3, mFixture.Check.Computed);
    Assert.AreEqual('', mFixture.Check.Run.Paused);
  finally
    mFixture.Free;
  end;
end;

procedure TLspWorkspaceCheckTests.PauseLimitIsSafetyNet;
var
  mFixture: TFixture;
begin
  // Kommt das Ende des Kompilierens nie an, endet die Pause nach ihrer Frist.
  mFixture := TFixture.Create;
  try
    mFixture.Check.Pause(TLspWorkspaceCheck.cPauseCompile, True, 200);
    mFixture.Check.Want;
    Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
    Assert.AreEqual(3, mFixture.Check.Computed);
    Assert.Contains(mFixture.Logged, 'Sicherheitsnetz');
  finally
    mFixture.Free;
  end;
end;

procedure TLspWorkspaceCheckTests.IndexBuildHoldsRun;
var
  mFixture: TFixture;
  mBusy: Boolean;
begin
  // Während des Indexaufbaus wären die Befunde voller nicht gefundener Units (#647).
  mFixture := TFixture.Create;
  try
    mBusy := True;
    mFixture.Check.Busy :=
      function: Boolean
      begin
        Result := mBusy;
      end;
    mFixture.Check.Want;
    Sleep(300);
    Assert.AreEqual(0, mFixture.Check.Computed);
    Assert.AreEqual(TLspWorkspaceCheck.cPauseIndex, mFixture.Check.Run.Paused);
    mBusy := False;
    Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
    Assert.AreEqual(3, mFixture.Check.Computed);
  finally
    mFixture.Free;
  end;
end;

procedure TLspWorkspaceCheckTests.TypingInterruptsAndRequeues;
var
  mFixture: TFixture;
  mClock: TStopwatch;
begin
  mFixture := TFixture.Create;
  try
    mFixture.Behavior.Add(cFileA, 'slow');
    mFixture.Check.TypingQuietMs := 300;
    mFixture.Check.Want;
    Sleep(100);
    // Mitten in A: A bricht ab und kommt wieder vorn hin; erst nach der Ruhezeit geht es weiter.
    mClock := TStopwatch.StartNew;
    mFixture.Check.Typed;
    Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
    Assert.IsTrue(mClock.ElapsedMilliseconds >= 250, IntToStr(mClock.ElapsedMilliseconds));
    Assert.AreEqual(3, mFixture.Check.Computed, 'A nur einmal gezählt');
    Assert.AreEqual('A.pas', mFixture.Order[0], 'A bleibt vorn');
  finally
    mFixture.Free;
  end;
end;

procedure TLspWorkspaceCheckTests.ForegroundDefersNextFile;
var
  mFixture: TFixture;
begin
  mFixture := TFixture.Create;
  try
    mFixture.Check.EnterForeground;
    mFixture.Check.Want;
    Sleep(300);
    Assert.AreEqual(0, mFixture.Check.Computed, 'textDocument/diagnostic geht vor');
    Assert.AreEqual('', mFixture.Check.Run.Paused, 'keine Pause in der Statusleiste');
    mFixture.Check.LeaveForeground;
    Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
    Assert.AreEqual(3, mFixture.Check.Computed);
  finally
    mFixture.Free;
  end;
end;

procedure TLspWorkspaceCheckTests.SlowFileFinishesAtEnd;
var
  mFixture: TFixture;
  mReports: TJSONArray;
begin
  // Über der Frist (#1220): ans Ende der Schlange, dann ohne Frist zu Ende.
  mFixture := TFixture.Create;
  try
    mFixture.Behavior.Add(cFileA, 'slow');
    mFixture.Check.FileLimitMs := 50;
    mFixture.Check.Want;
    Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
    Assert.AreEqual(3, mFixture.Check.Computed);
    Assert.AreEqual(3, mFixture.Order.Count);
    Assert.AreEqual('A.pas', mFixture.Order[2], 'A zuletzt');
    Assert.AreEqual(3, mFixture.Check.Run.Done);
    mReports := mFixture.Collect;
    try
      Assert.AreEqual(3, Integer(mReports.Count));
    finally
      mReports.Free;
    end;
  finally
    mFixture.Free;
  end;
end;

procedure TLspWorkspaceCheckTests.FailingFileIsSkipped;
var
  mFixture: TFixture;
  mReports: TJSONArray;
  mReport: TJSONValue;
  mEmpty: Integer;
begin
  // Früher scheiterte an einer kaputten Unit jede Anfrage, bis der Server starb (#1094).
  mFixture := TFixture.Create;
  try
    mFixture.Behavior.Add(cFileA, 'fail');
    mFixture.Check.Want;
    Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
    Assert.AreEqual(1, mFixture.Check.Skipped);
    Assert.AreEqual(1, mFixture.Check.Run.Skipped);
    mReports := mFixture.Collect;
    try
      Assert.AreEqual(3, Integer(mReports.Count));
      mEmpty := 0;
      for mReport in mReports do
        if mReport.GetValue<TJSONArray>('items').Count = 0 then
        begin
          Inc(mEmpty);
          Assert.AreEqual(TDocumentUris.FromPath(cFileA), UriOf(mReport));
        end;
      Assert.AreEqual(1, mEmpty);
    finally
      mReports.Free;
    end;
    Assert.Contains(mFixture.Logged, 'unit#A übersprungen (EArgumentException)');
    Assert.DoesNotContain(mFixture.Logged, 'A.pas');
  finally
    mFixture.Free;
  end;
end;

procedure TLspWorkspaceCheckTests.OpenFilesAreLeftToEditor;
var
  mFixture: TFixture;
  mReports: TJSONArray;
  mReport: TJSONValue;
begin
  mFixture := TFixture.Create;
  try
    mFixture.Open := cFileB;
    mFixture.Check.Want;
    Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
    Assert.AreEqual(2, mFixture.Check.Computed);
    Assert.AreEqual(3, mFixture.Check.Run.Done, 'zählt als erledigt');
    mReports := mFixture.Collect;
    try
      Assert.AreEqual(2, Integer(mReports.Count));
      for mReport in mReports do
        Assert.AreNotEqual(TDocumentUris.FromPath(cFileB), UriOf(mReport));
    finally
      mReports.Free;
    end;
  finally
    mFixture.Free;
  end;
end;

procedure TLspWorkspaceCheckTests.RemovedFilesDropReports;
var
  mFixture: TFixture;
  mReports: TJSONArray;
begin
  mFixture := TFixture.Create;
  try
    mFixture.Check.Want;
    Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
    mFixture.Files := TArray<string>.Create(cFileA);
    mFixture.Check.Start(False);
    Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
    mReports := mFixture.Collect;
    try
      Assert.AreEqual(1, Integer(mReports.Count));
      Assert.AreEqual(TDocumentUris.FromPath(cFileA), UriOf(mReports.Items[0]));
    finally
      mReports.Free;
    end;
    // Nicht mehr im Projekt: Affected stellt sie nicht ein.
    mFixture.Check.Affected(TArray<string>.Create(cFileB), False);
    Assert.IsTrue(mFixture.Check.WaitIdle(cIdleMs));
    Assert.AreEqual(3, mFixture.Check.Computed);
  finally
    mFixture.Free;
  end;
end;

procedure TLspWorkspaceCheckTests.RunAsJson;
var
  mRun, mOther: TWorkspaceCheckRun;
  mJson: TJSONObject;
begin
  mRun := Default(TWorkspaceCheckRun);
  mRun.Serial := 2;
  mRun.Active := True;
  mRun.Done := 4;
  mRun.Total := 9;
  mRun.Paused := 'compile';
  mJson := mRun.ToJson;
  try
    Assert.AreEqual(2, mJson.GetValue<Integer>('serial'));
    Assert.IsTrue(mJson.GetValue<Boolean>('active'));
    Assert.AreEqual(4, mJson.GetValue<Integer>('done'));
    Assert.AreEqual(9, mJson.GetValue<Integer>('total'));
    Assert.AreEqual('compile', mJson.GetValue<string>('paused'));
  finally
    mJson.Free;
  end;
  mOther := mRun;
  mOther.Done := 5;
  Assert.IsFalse(mRun.StateDiffers(mOther), 'bloßer Fortschritt');
  mOther.Paused := '';
  Assert.IsTrue(mRun.StateDiffers(mOther));
end;

procedure TLspWorkspaceCheckTests.DependentsOfFindsUsesAndIncludes;
var
  mUnits: TArray<TUnitIndex>;
  mFound: TArray<string>;
begin
  SetLength(mUnits, 4);
  mUnits[0].UnitName := 'A';
  mUnits[0].FileName := cFileA;
  mUnits[1].UnitName := 'B';
  mUnits[1].FileName := cFileB;
  mUnits[1].ImplementationUses := TArray<string>.Create('SysUtils', 'a');
  mUnits[1].Includes := TArray<string>.Create('C:\P\Defs.inc');
  mUnits[2].UnitName := 'C';
  mUnits[2].FileName := cFileC;
  mUnits[2].InterfaceUses := TArray<string>.Create('B');
  // Bibliotheks-Units gehören nicht zum Projekt.
  mUnits[3].UnitName := 'Lib';
  mUnits[3].FileName := 'C:\Lib\Lib.pas';
  mUnits[3].InterfaceUses := TArray<string>.Create('A');
  mUnits[3].Library_ := True;
  mFound := TLspWorkspaceCheck.DependentsOf(mUnits, cFileA);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(cFileB, mFound[0]);
  mFound := TLspWorkspaceCheck.DependentsOf(mUnits, 'C:\P\Defs.inc');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(cFileB, mFound[0]);
  mFound := TLspWorkspaceCheck.DependentsOf(mUnits, cFileC);
  Assert.AreEqual(0, Integer(Length(mFound)));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspWorkspaceCheckTests);

end.
