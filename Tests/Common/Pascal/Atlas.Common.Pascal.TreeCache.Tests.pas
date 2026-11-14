unit Atlas.Common.Pascal.TreeCache.Tests;

// Tests für den gemeinsamen Syntaxbaum je Dokumentversion (#262).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSyntaxTreeCacheTests = class
  public
    [Test]
    procedure SameVersionParsesOnce;
    [Test]
    procedure NewVersionGetsNewTree;
    [Test]
    procedure ConcurrentRequestsShareOneParse;
    [Test]
    procedure TreeOutlivesDocument;
    [Test]
    procedure DerivedWithoutValueIsNotStored;
    [Test]
    procedure NoParserCallsOutsideCache;
    /// <summary>#1356: Zugriffe, Trefferquote und Speicher der lebenden Bäume für das Fenster „Atlas-Server“.
    /// </summary>
    [Test]
    procedure StatsCountHitsAndLiveBytes;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.TextDocument,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache;

const
  cSource = 'unit A;'#10'interface'#10'procedure P;'#10'implementation'#10'procedure P;'#10'begin'#10'end;'#10'end.';

var
  // Ergebnisse der Threads in ConcurrentRequestsShareOneParse.
  SharedTrees: array of TSyntaxTree;

function Worker(const ADocument: ITextDocument; AStart: TEvent; ASlot: Integer): TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    var
      Shared: ISharedSyntaxTree;
    begin
      AStart.WaitFor(5000);
      Shared := TSyntaxTreeCache.Get(ADocument);
      SharedTrees[ASlot] := Shared.Tree;
    end);
  Result.FreeOnTerminate := False;
end;

function NewDocument(AVersion: Integer; const AText: string): ITextDocument;
begin
  Result := TTextDocument.Create('file:///c:/a.pas', 'objectpascal', AVersion, AText);
end;

procedure TSyntaxTreeCacheTests.SameVersionParsesOnce;
var
  mDocument: ITextDocument;
  mBefore: Integer;
  mFirst, mSecond: ISharedSyntaxTree;
begin
  mDocument := NewDocument(1, cSource);
  mBefore := TSyntaxTreeCache.ParseCount;
  mFirst := TSyntaxTreeCache.Get(mDocument);
  mSecond := TSyntaxTreeCache.Get(mDocument);
  Assert.AreEqual(1, TSyntaxTreeCache.ParseCount - mBefore);
  Assert.AreSame(mFirst.Tree, mSecond.Tree);
  Assert.AreEqual('A', mFirst.Tree.Root.Name);
end;

procedure TSyntaxTreeCacheTests.StatsCountHitsAndLiveBytes;
var
  mDocument: ITextDocument;
  mBefore, mHeld, mAfter: TSyntaxTreeCacheStats;
  mFirst, mSecond: ISharedSyntaxTree;
begin
  mDocument := NewDocument(7, cSource);
  mBefore := TSyntaxTreeCache.Stats;
  mFirst := TSyntaxTreeCache.Get(mDocument);
  mSecond := TSyntaxTreeCache.Get(mDocument);
  mHeld := TSyntaxTreeCache.Stats;
  Assert.AreEqual<Int64>(2, mHeld.Lookups - mBefore.Lookups);
  Assert.AreEqual<Int64>(1, mHeld.Parses - mBefore.Parses);
  Assert.AreEqual(1, mHeld.Trees - mBefore.Trees);
  Assert.AreEqual<Int64>(TSyntaxTreeCache.EstimatedBytes(mFirst.Tree), mHeld.Bytes - mBefore.Bytes);
  Assert.IsTrue(TSyntaxTreeCache.EstimatedBytes(mFirst.Tree) > Length(cSource) * SizeOf(Char));
  mFirst := nil;
  mSecond := nil;
  mDocument := nil;
  mAfter := TSyntaxTreeCache.Stats;
  Assert.AreEqual(mBefore.Trees, mAfter.Trees, 'mit dem Dokument frei');
  Assert.AreEqual<Int64>(mBefore.Bytes, mAfter.Bytes);
  mHeld.Lookups := 4;
  mHeld.Parses := 1;
  Assert.AreEqual(75, mHeld.HitPercent);
  Assert.AreEqual(-1, Default(TSyntaxTreeCacheStats).HitPercent);
  Assert.AreEqual<Int64>(0, TSyntaxTreeCache.EstimatedBytes(nil));
end;

procedure TSyntaxTreeCacheTests.NewVersionGetsNewTree;
var
  mDocument, mChanged: ITextDocument;
  mOld, mNew: ISharedSyntaxTree;
begin
  mDocument := NewDocument(1, cSource);
  mOld := TSyntaxTreeCache.Get(mDocument);
  mChanged := mDocument.ApplyChanges([TTextChange.Full(StringReplace(cSource, 'unit A', 'unit B', []))], 2);
  mNew := TSyntaxTreeCache.Get(mChanged);
  Assert.AreNotSame(mOld.Tree, mNew.Tree);
  Assert.AreEqual('A', mOld.Tree.Root.Name);
  Assert.AreEqual('B', mNew.Tree.Root.Name);
end;

procedure TSyntaxTreeCacheTests.ConcurrentRequestsShareOneParse;
const
  cFeatures = 6;
var
  mDocument: ITextDocument;
  mText: string;
  mIndex, mBefore: Integer;
  mThreads: array[0..cFeatures - 1] of TThread;
  mStart: TEvent;
  mShared: ISharedSyntaxTree;
begin
  // Groß genug, dass alle Anfragen während des ersten Parse eintreffen.
  mText := 'unit A;'#10'interface'#10'implementation'#10;
  for mIndex := 1 to 3000 do
  begin
    mText := mText + Format('procedure P%d;'#10'begin'#10'  X := %d;'#10'end;'#10, [mIndex, mIndex]);
  end;
  mText := mText + 'end.';
  mDocument := NewDocument(1, mText);
  mBefore := TSyntaxTreeCache.ParseCount;
  SetLength(SharedTrees, cFeatures);
  mStart := TEvent.Create(nil, True, False, '');
  try
    for mIndex := 0 to cFeatures - 1 do
    begin
      mThreads[mIndex] := Worker(mDocument, mStart, mIndex);
      mThreads[mIndex].Start;
    end;
    mStart.SetEvent;
    for mIndex := 0 to cFeatures - 1 do
    begin
      mThreads[mIndex].WaitFor;
      mThreads[mIndex].Free;
    end;
  finally
    mStart.Free;
  end;
  Assert.AreEqual(1, TSyntaxTreeCache.ParseCount - mBefore);
  // Das Dokument hält den Baum; die Zeiger der Threads sind deshalb noch gültig.
  mShared := TSyntaxTreeCache.Get(mDocument);
  try
    for mIndex := 0 to cFeatures - 1 do
    begin
      Assert.AreSame(mShared.Tree, SharedTrees[mIndex]);
    end;
  finally
    // Unit-Variable: sonst bleibt das Array über den Test hinaus liegen (Leck-Monitor).
    SharedTrees := nil;
  end;
end;

procedure TSyntaxTreeCacheTests.TreeOutlivesDocument;
var
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
begin
  mDocument := NewDocument(1, cSource);
  mShared := TSyntaxTreeCache.Get(mDocument);
  mDocument := nil;
  // Das Feature hält den Baum noch, obwohl die Momentaufnahme schon frei ist.
  Assert.AreEqual('A', mShared.Tree.Root.Name);
end;

procedure TSyntaxTreeCacheTests.DerivedWithoutValueIsNotStored;
var
  mDocument: ITextDocument;
  mCalls: Integer;
begin
  mDocument := NewDocument(1, cSource);
  mCalls := 0;
  mDocument.Derived('probe', function: IInterface begin Inc(mCalls); Result := nil; end);
  mDocument.Derived('probe', function: IInterface begin Inc(mCalls); Result := TInterfacedObject.Create; end);
  mDocument.Derived('probe', function: IInterface begin Inc(mCalls); Result := nil; end);
  Assert.AreEqual(2, mCalls);
end;

/// <summary>Ordner über der Test-exe, der Packages enthält; '' ohne.</summary>
function SourceRoot: string;
var
  mDirectory: string;
begin
  Result := '';
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    if TDirectory.Exists(TPath.Combine(mDirectory, 'Packages')) then
    begin
      Exit(mDirectory);
    end;
    if ExtractFileDir(mDirectory) = mDirectory then
    begin
      Break;
    end;
    mDirectory := ExtractFileDir(mDirectory);
  end;
end;

/// <summary>Units unter ADirectory außer Parser und Cache, die TPascalParser.Parse aufrufen, je mit Leerzeichen
/// davor.</summary>
function ParserCallers(const ADirectory: string): string;
var
  mFileName, mName: string;
begin
  Result := '';
  for mFileName in TDirectory.GetFiles(ADirectory, '*.pas', TSearchOption.soAllDirectories) do
  begin
    mName := ExtractFileName(mFileName);
    if SameText(mName, 'Atlas.Common.Pascal.Parser.pas') or SameText(mName, 'Atlas.Common.Pascal.TreeCache.pas') then
    begin
      Continue;
    end;
    if Pos('TPascalParser.Parse', TFile.ReadAllText(mFileName, TEncoding.UTF8)) > 0 then
    begin
      Result := Result + ' ' + mName;
    end;
  end;
end;

procedure TSyntaxTreeCacheTests.NoParserCallsOutsideCache;
var
  mDirectory, mRoot: string;
  mOffenders: string;
  mFolders: TArray<string>;
begin
  // Wächter (#262): außerhalb des Caches ruft niemand den Parser direkt auf.
  mRoot := SourceRoot;
  if mRoot = '' then
  begin
    Assert.Pass('Quelltexte nicht gefunden; Prüfung übersprungen');
  end;
  mOffenders := '';
  mFolders := [TPath.Combine(mRoot, 'Packages'), TPath.Combine(mRoot, 'Application')];
  for mDirectory in mFolders do
  begin
    if TDirectory.Exists(mDirectory) then
    begin
      mOffenders := mOffenders + ParserCallers(mDirectory);
    end;
  end;
  Assert.AreEqual('', mOffenders, 'TPascalParser.Parse außerhalb des Caches');
end;

initialization
  TDUnitX.RegisterTestFixture(TSyntaxTreeCacheTests);

end.
