unit Atlas.Core.Debug.AsyncOrigin.Tests;

// Tests zur Herkunft eingereihter Methoden (#859): Finden der Aufrufstellen und Zuordnung über Adresse und
// Reihenfolge, ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugAsyncOriginTests = class
  public
    [Test]
    procedure FindsQueueWithAnonymousMethod;
    [Test]
    procedure FindsAllKinds;
    [Test]
    procedure IgnoresCommentsAndStrings;
    [Test]
    procedure IgnoresUnqualifiedCalls;
    [Test]
    procedure SiteAtPicksInnermost;
    [Test]
    procedure SiteOnLineMatchesCall;
    [Test]
    procedure OriginFrameNeedsAnonymousBody;
    [Test]
    procedure KeepsLastPerSite;
    [Test]
    procedure TakesOldestWithoutAddress;
    [Test]
    procedure TakesNewestWithSameAddress;
    [Test]
    procedure TwoSitesStaySeparate;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.AsyncOrigin;

const
  cUnit =
    'procedure TForm1.Button1Click(Sender: TObject);' + sLineBreak +  // 1
    'begin' + sLineBreak +                                             // 2
    '  TThread.Queue(nil,' + sLineBreak +                              // 3
    '    procedure' + sLineBreak +                                     // 4
    '    begin' + sLineBreak +                                         // 5
    '      Caption := ''fertig (1)'';' + sLineBreak +                  // 6
    '    end);' + sLineBreak +                                         // 7
    '  TTask.Run(procedure begin Work; end);' + sLineBreak +           // 8
    'end;';                                                            // 9

function Frames(const AHeader: string): TAtlasDebugFrames;
begin
  Result := [TAtlasDebugFrame.Create(AHeader, 'C:\P\Unit1.pas', 3)];
end;

{ TAtlasDebugAsyncOriginTests }

procedure TAtlasDebugAsyncOriginTests.FindsQueueWithAnonymousMethod;
var
  mSites: TAtlasAsyncSiteList;
begin
  mSites := TAtlasAsyncSites.Find('C:\P\Unit1.pas', cUnit);
  Assert.AreEqual(2, Integer(Length(mSites)));
  Assert.IsTrue(mSites[0].Kind = TAtlasAsyncKind.Queue);
  Assert.AreEqual(3, mSites[0].Line);
  Assert.AreEqual(7, mSites[0].EndLine, 'die Klammer in der Zeichenkette zählt nicht');
  Assert.IsTrue(mSites[1].Kind = TAtlasAsyncKind.TaskRun);
  Assert.AreEqual(8, mSites[1].Line);
  Assert.AreEqual(8, mSites[1].EndLine);
  Assert.AreEqual('C:\P\Unit1.pas', mSites[0].FileName);
  mSites := nil;
end;

procedure TAtlasDebugAsyncOriginTests.FindsAllKinds;
var
  mSites: TAtlasAsyncSiteList;
begin
  mSites := TAtlasAsyncSites.Find('U.pas',
    'TThread.Synchronize(nil, P); System.Classes.TThread.ForceQueue(nil, P);' + sLineBreak +
    'T := TTask.Create(P); tparallel.for(1, 10, Q); TThread . Queue (nil, P);');
  Assert.AreEqual(5, Integer(Length(mSites)));
  Assert.IsTrue(mSites[0].Kind = TAtlasAsyncKind.Synchronize);
  Assert.IsTrue(mSites[1].Kind = TAtlasAsyncKind.ForceQueue);
  Assert.IsTrue(mSites[2].Kind = TAtlasAsyncKind.TaskCreate);
  Assert.IsTrue(mSites[3].Kind = TAtlasAsyncKind.ParallelFor);
  Assert.IsTrue(mSites[4].Kind = TAtlasAsyncKind.Queue);
  Assert.AreEqual(2, mSites[4].Line);
  Assert.AreEqual('TParallel.For', TAtlasAsyncSites.KindName(TAtlasAsyncKind.ParallelFor));
  mSites := nil;
end;

procedure TAtlasDebugAsyncOriginTests.IgnoresCommentsAndStrings;
var
  mSites: TAtlasAsyncSiteList;
begin
  mSites := TAtlasAsyncSites.Find('U.pas',
    '// TThread.Queue(nil, P);' + sLineBreak +
    '{ TThread.Queue(nil, P); }' + sLineBreak +
    '(* TTask.Run(P); *)' + sLineBreak +
    'S := ''TThread.Queue(nil, P)'';' + sLineBreak +
    'TThread.Queue(nil, P);');
  Assert.AreEqual(1, Integer(Length(mSites)));
  Assert.AreEqual(5, mSites[0].Line);
  mSites := nil;
end;

procedure TAtlasDebugAsyncOriginTests.IgnoresUnqualifiedCalls;
var
  mSites: TAtlasAsyncSiteList;
begin
  mSites := TAtlasAsyncSites.Find('U.pas', 'Synchronize(Update); Queue(P); FTask.Run(P); MyTThread.Queue(nil, P);');
  Assert.AreEqual(0, Integer(Length(mSites)));
  mSites := nil;
end;

procedure TAtlasDebugAsyncOriginTests.SiteAtPicksInnermost;
var
  mSites: TAtlasAsyncSiteList;
begin
  mSites := TAtlasAsyncSites.Find('C:\P\Unit1.pas',
    'TTask.Run(procedure' + sLineBreak +
    '  begin' + sLineBreak +
    '    TThread.Queue(nil, procedure' + sLineBreak +
    '      begin' + sLineBreak +
    '      end);' + sLineBreak +
    '  end);');
  Assert.AreEqual(2, Integer(Length(mSites)));
  Assert.AreEqual(1, TAtlasAsyncSites.SiteAt(mSites, 'c:\p\unit1.pas', 4));
  Assert.AreEqual(0, TAtlasAsyncSites.SiteAt(mSites, 'C:\P\Unit1.pas', 2));
  Assert.AreEqual(-1, TAtlasAsyncSites.SiteAt(mSites, 'C:\P\Unit1.pas', 7));
  Assert.AreEqual(-1, TAtlasAsyncSites.SiteAt(mSites, 'C:\P\Unit2.pas', 4));
  mSites := nil;
end;

procedure TAtlasDebugAsyncOriginTests.SiteOnLineMatchesCall;
var
  mSites: TAtlasAsyncSiteList;
begin
  mSites := TAtlasAsyncSites.Find('C:\P\Unit1.pas', cUnit);
  Assert.AreEqual(0, TAtlasAsyncSites.SiteOnLine(mSites, 'C:\P\Unit1.pas', 3));
  Assert.AreEqual(1, TAtlasAsyncSites.SiteOnLine(mSites, 'C:\P\Unit1.pas', 8));
  Assert.AreEqual(-1, TAtlasAsyncSites.SiteOnLine(mSites, 'C:\P\Unit1.pas', 5), 'nur die Zeile des Aufrufs');
  mSites := nil;
end;

procedure TAtlasDebugAsyncOriginTests.OriginFrameNeedsAnonymousBody;
var
  mSites: TAtlasAsyncSiteList;
  mFrames: TAtlasDebugFrames;
  mSite: Integer;
begin
  mSites := TAtlasAsyncSites.Find('C:\P\Unit1.pas', cUnit);
  // Halt in einer gerufenen Routine, darunter die anonyme Methode, darunter CheckSynchronize.
  mFrames := [TAtlasDebugFrame.Create('Unit1.TForm1.Show', 'C:\P\Unit1.pas', 40),
    TAtlasDebugFrame.Create('Unit1.TForm1.Button1Click$0$Body', 'C:\P\Unit1.pas', 6),
    TAtlasDebugFrame.Create('System.Classes.CheckSynchronize', '', 0)];
  Assert.AreEqual(1, TAtlasAsyncSites.OriginFrame(mSites, mFrames, mSite));
  Assert.AreEqual(0, mSite);
  // Dieselbe Zeile in der einreihenden Methode selbst ist keine Herkunft.
  mFrames := [TAtlasDebugFrame.Create('Unit1.TForm1.Button1Click', 'C:\P\Unit1.pas', 3)];
  Assert.AreEqual(-1, TAtlasAsyncSites.OriginFrame(mSites, mFrames, mSite));
  Assert.AreEqual(-1, mSite);
  Assert.IsTrue(TAtlasAsyncSites.IsAnonymous('Unit1.TForm1.Button1Click$ActRec.$0$Body'));
  mSites := nil;
  mFrames := nil;
end;

procedure TAtlasDebugAsyncOriginTests.KeepsLastPerSite;
var
  mOrigins: TAtlasAsyncOrigins;
  mEntry: TAtlasAsyncEntry;
  mIndex: Integer;
begin
  mOrigins := Default(TAtlasAsyncOrigins);
  mOrigins.MaxPerSite := 3;
  for mIndex := 1 to 5 do
  begin
    mOrigins.Add(0, Cardinal(mIndex), 0, Frames('Step' + IntToStr(mIndex)));
  end;
  mOrigins.Add(1, 99, 0, Frames('Other'));
  Assert.AreEqual(4, mOrigins.Count);
  Assert.IsTrue(mOrigins.Take(0, 0, mEntry));
  Assert.AreEqual(Cardinal(3), mEntry.ThreadId, 'die beiden ältesten sind herausgefallen');
  mOrigins.Clear;
  Assert.AreEqual(0, mOrigins.Count);
  mEntry := Default(TAtlasAsyncEntry);
end;

procedure TAtlasDebugAsyncOriginTests.TakesOldestWithoutAddress;
var
  mOrigins: TAtlasAsyncOrigins;
  mEntry: TAtlasAsyncEntry;
begin
  mOrigins := Default(TAtlasAsyncOrigins);
  mOrigins.MaxPerSite := 20;
  mOrigins.Add(0, 1, 0, Frames('First'));
  mOrigins.Add(0, 2, 0, Frames('Second'));
  Assert.IsTrue(mOrigins.Take(0, 0, mEntry));
  Assert.AreEqual(Cardinal(1), mEntry.ThreadId);
  Assert.IsTrue(mOrigins.Take(0, 0, mEntry));
  Assert.AreEqual(Cardinal(2), mEntry.ThreadId);
  Assert.IsTrue(mEntry.Sequence > 1);
  Assert.IsFalse(mOrigins.Take(0, 0, mEntry));
  mOrigins.Clear;
  mEntry := Default(TAtlasAsyncEntry);
end;

procedure TAtlasDebugAsyncOriginTests.TakesNewestWithSameAddress;
var
  mOrigins: TAtlasAsyncOrigins;
  mEntry: TAtlasAsyncEntry;
begin
  // Dieselbe Adresse zweimal (Speicher wiederverwendet): die jüngste Einreihung gilt.
  mOrigins := Default(TAtlasAsyncOrigins);
  mOrigins.MaxPerSite := 20;
  mOrigins.Add(0, 1, $1000, Frames('Old'));
  mOrigins.Add(0, 2, $2000, Frames('Other'));
  mOrigins.Add(0, 3, $1000, Frames('New'));
  Assert.IsTrue(mOrigins.Take(0, $1000, mEntry));
  Assert.AreEqual(Cardinal(3), mEntry.ThreadId);
  Assert.AreEqual('New', mEntry.Frames[0].Header);
  Assert.IsTrue(mOrigins.Take(0, $2000, mEntry));
  Assert.AreEqual(Cardinal(2), mEntry.ThreadId);
  // Unbekannte Adresse: die älteste offene.
  Assert.IsTrue(mOrigins.Take(0, $3000, mEntry));
  Assert.AreEqual(Cardinal(1), mEntry.ThreadId);
  mOrigins.Clear;
  mEntry := Default(TAtlasAsyncEntry);
end;

procedure TAtlasDebugAsyncOriginTests.TwoSitesStaySeparate;
var
  mOrigins: TAtlasAsyncOrigins;
  mEntry: TAtlasAsyncEntry;
begin
  mOrigins := Default(TAtlasAsyncOrigins);
  mOrigins.MaxPerSite := 20;
  mOrigins.Add(0, 1, 0, Frames('A'));
  mOrigins.Add(1, 2, 0, Frames('B'));
  Assert.IsTrue(mOrigins.Take(1, 0, mEntry));
  Assert.AreEqual(Cardinal(2), mEntry.ThreadId);
  Assert.AreEqual(1, mEntry.Site);
  Assert.IsTrue(mOrigins.Take(0, 0, mEntry));
  Assert.AreEqual(Cardinal(1), mEntry.ThreadId);
  mOrigins.Clear;
  mEntry := Default(TAtlasAsyncEntry);
end;

end.
