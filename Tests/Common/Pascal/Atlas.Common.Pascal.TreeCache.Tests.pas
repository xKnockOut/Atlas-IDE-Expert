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
  Source = 'unit A;'#10'interface'#10'procedure P;'#10'implementation'#10'procedure P;'#10'begin'#10'end;'#10'end.';

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

function NewDocument(AVersion: Integer = 1; const AText: string = Source): ITextDocument;
begin
  Result := TTextDocument.Create('file:///c:/a.pas', 'objectpascal', AVersion, AText);
end;

procedure TSyntaxTreeCacheTests.SameVersionParsesOnce;
var
  Document: ITextDocument;
  Before: Integer;
  First, Second: ISharedSyntaxTree;
begin
  Document := NewDocument;
  Before := TSyntaxTreeCache.ParseCount;
  First := TSyntaxTreeCache.Get(Document);
  Second := TSyntaxTreeCache.Get(Document);
  Assert.AreEqual(1, TSyntaxTreeCache.ParseCount - Before);
  Assert.IsTrue(First.Tree = Second.Tree);
  Assert.AreEqual('A', First.Tree.Root.Name);
end;

procedure TSyntaxTreeCacheTests.StatsCountHitsAndLiveBytes;
var
  mDocument: ITextDocument;
  mBefore, mHeld, mAfter: TSyntaxTreeCacheStats;
  mFirst, mSecond: ISharedSyntaxTree;
begin
  mDocument := NewDocument(7);
  mBefore := TSyntaxTreeCache.Stats;
  mFirst := TSyntaxTreeCache.Get(mDocument);
  mSecond := TSyntaxTreeCache.Get(mDocument);
  mHeld := TSyntaxTreeCache.Stats;
  Assert.AreEqual<Int64>(2, mHeld.Lookups - mBefore.Lookups);
  Assert.AreEqual<Int64>(1, mHeld.Parses - mBefore.Parses);
  Assert.AreEqual(1, mHeld.Trees - mBefore.Trees);
  Assert.AreEqual<Int64>(TSyntaxTreeCache.EstimatedBytes(mFirst.Tree), mHeld.Bytes - mBefore.Bytes);
  Assert.IsTrue(TSyntaxTreeCache.EstimatedBytes(mFirst.Tree) > Length(Source) * SizeOf(Char));
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
  Document, Changed: ITextDocument;
  Old, New: ISharedSyntaxTree;
begin
  Document := NewDocument;
  Old := TSyntaxTreeCache.Get(Document);
  Changed := Document.ApplyChanges([TTextChange.Full(StringReplace(Source, 'unit A', 'unit B', []))], 2);
  New := TSyntaxTreeCache.Get(Changed);
  Assert.IsFalse(Old.Tree = New.Tree);
  Assert.AreEqual('A', Old.Tree.Root.Name);
  Assert.AreEqual('B', New.Tree.Root.Name);
end;

procedure TSyntaxTreeCacheTests.ConcurrentRequestsShareOneParse;
const
  Features = 6;
var
  Document: ITextDocument;
  Text: string;
  Index, Before: Integer;
  Threads: array[0..Features - 1] of TThread;
  Start: TEvent;
  Shared: ISharedSyntaxTree;
begin
  // Groß genug, dass alle Anfragen während des ersten Parse eintreffen.
  Text := 'unit A;'#10'interface'#10'implementation'#10;
  for Index := 1 to 3000 do
    Text := Text + Format('procedure P%d;'#10'begin'#10'  X := %d;'#10'end;'#10, [Index, Index]);
  Text := Text + 'end.';
  Document := NewDocument(1, Text);
  Before := TSyntaxTreeCache.ParseCount;
  SetLength(SharedTrees, Features);
  Start := TEvent.Create(nil, True, False, '');
  try
    for Index := 0 to Features - 1 do
    begin
      Threads[Index] := Worker(Document, Start, Index);
      Threads[Index].Start;
    end;
    Start.SetEvent;
    for Index := 0 to Features - 1 do
    begin
      Threads[Index].WaitFor;
      Threads[Index].Free;
    end;
  finally
    Start.Free;
  end;
  Assert.AreEqual(1, TSyntaxTreeCache.ParseCount - Before);
  // Das Dokument hält den Baum; die Zeiger der Threads sind deshalb noch gültig.
  Shared := TSyntaxTreeCache.Get(Document);
  try
    for Index := 0 to Features - 1 do
      Assert.IsTrue(SharedTrees[Index] = Shared.Tree);
  finally
    // Unit-Variable: sonst bleibt das Array über den Test hinaus liegen (Leck-Monitor).
    SharedTrees := nil;
  end;
end;

procedure TSyntaxTreeCacheTests.TreeOutlivesDocument;
var
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
begin
  Document := NewDocument;
  Shared := TSyntaxTreeCache.Get(Document);
  Document := nil;
  // Das Feature hält den Baum noch, obwohl die Momentaufnahme schon frei ist.
  Assert.AreEqual('A', Shared.Tree.Root.Name);
end;

procedure TSyntaxTreeCacheTests.DerivedWithoutValueIsNotStored;
var
  Document: ITextDocument;
  Calls: Integer;
begin
  Document := NewDocument;
  Calls := 0;
  Document.Derived('probe', function: IInterface begin Inc(Calls); Result := nil; end);
  Document.Derived('probe', function: IInterface begin Inc(Calls); Result := TInterfacedObject.Create; end);
  Document.Derived('probe', function: IInterface begin Inc(Calls); Result := nil; end);
  Assert.AreEqual(2, Calls);
end;

procedure TSyntaxTreeCacheTests.NoParserCallsOutsideCache;
var
  Directory, Root, FileName, Name: string;
  Offenders: string;
  Folders: TArray<string>;
begin
  // Wächter (#262): außerhalb des Caches ruft niemand den Parser direkt auf.
  Root := '';
  Directory := ExtractFileDir(ParamStr(0));
  while Directory <> '' do
  begin
    if TDirectory.Exists(TPath.Combine(Directory, 'Packages')) then
    begin
      Root := Directory;
      Break;
    end;
    if ExtractFileDir(Directory) = Directory then
      Break;
    Directory := ExtractFileDir(Directory);
  end;
  if Root = '' then
    Assert.Pass('Quelltexte nicht gefunden; Prüfung übersprungen');
  Offenders := '';
  Folders := [TPath.Combine(Root, 'Packages'), TPath.Combine(Root, 'Application')];
  for Directory in Folders do
    if TDirectory.Exists(Directory) then
      for FileName in TDirectory.GetFiles(Directory, '*.pas', TSearchOption.soAllDirectories) do
      begin
        Name := ExtractFileName(FileName);
        if SameText(Name, 'Atlas.Common.Pascal.Parser.pas') or SameText(Name, 'Atlas.Common.Pascal.TreeCache.pas') then
          Continue;
        if Pos('TPascalParser.Parse', TFile.ReadAllText(FileName)) > 0 then
          Offenders := Offenders + ' ' + Name;
      end;
  Assert.AreEqual('', Offenders, 'TPascalParser.Parse außerhalb des Caches');
end;

initialization
  TDUnitX.RegisterTestFixture(TSyntaxTreeCacheTests);

end.
