unit Atlas.Core.Vcs.WorkingCopies.Tests;

// Arbeitskopien samt Externals und Submodulen (#1292): Sammeln aus
// svn:externals und svn status --xml (Fixture Tests\Data\Svn\
// status-externals.xml), geänderte Dateien je Arbeitskopie, Submodule aus
// git submodule status, Aufteilen der Änderungen auf die Ordner (Folders),
// vcs.externals.update, Festschreiben einer Zeile und „Neu auf dem Server“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasVcsWorkingCopiesTests = class
  public
    /// <summary>Wurzel, drei Externals aus svn:externals (Datei-External ohne Zeile), verschachteltes External
    /// nur aus dem Status; Reihenfolge, Einrückung, „fest“, geänderte Dateien je Arbeitskopie.</summary>
    [Test]
    procedure CollectsSvnExternalsWithChanges;
    [Test]
    procedure ParsesSubmoduleStatus;
    /// <summary>Änderungen der Wurzel je Arbeitskopie (tiefste gewinnt); svn status der Fixture über den
    /// Parser des Providers (Einträge item="external" sind keine Änderung); Folders ohne svn:externals.</summary>
    [Test]
    procedure SplitsChangesPerWorkingCopy;
    [Test]
    procedure ParsesUpdateSetting;
    /// <summary>Nur die eine Zeile im definierenden Ordner wird festgeschrieben; fest und unbekannt nicht.
    /// </summary>
    [Test]
    procedure PinsOneLine;
    /// <summary>Collect und CheckServer über eine Umsetzung mit festen Antworten.</summary>
    [Test]
    procedure CollectAndCheckServerThroughVcs;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Internals.SvnExternals,
  Atlas.Core.Vcs.Internals.SvnParser,
  Atlas.Core.Vcs.WorkingCopies;

const
  cRepository = 'https://svn.firma.local/repo';
  cDefinition = '# Packages'#10'^/Packages/Basis/trunk Packages/Basis'#10 +
    '^/Packages/Drucken/trunk Packages/Drucken'#10'-r 4711 ^/Packages/Kunden/trunk Packages/Kunden'#10 +
    '^/Vorlagen/trunk/Bon.txt Bon.txt'#10;

type
  /// <summary>SVN-Umsetzung mit festen Antworten für Collect und CheckServer.</summary>
  TFakeSvn = class(TInterfacedObject, IAtlasVersionControl, IAtlasVcsSvnWorkingCopy, IAtlasVcsSvnExternals)
  public
    StatusText: string;
    ExternalsText: string;
    Calls: TArray<string>;
    Commits: Integer;
    { IAtlasVersionControl }
    function Kind: TAtlasVcsKind;
    function WorkingCopy: TAtlasVcsWorkingCopy;
    function Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
    function Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    function FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
    function Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
    function ChangeMarker: string;
    { IAtlasVcsSvnWorkingCopy }
    function WorkingRevisions(out AText: string): TAtlasVcsOutcome; overload;
    function WorkingRevisions(const AFolder: string; out AText: string): TAtlasVcsOutcome; overload;
    function ExternalsXml(out AText: string): TAtlasVcsOutcome;
    function RepositoryRoot(out AUrl: string): TAtlasVcsOutcome;
    function ToolVersion(out AVersion: string): TAtlasVcsOutcome;
    { IAtlasVcsSvnExternals }
    function StatusXml(out AText: string): TAtlasVcsOutcome;
    function Update(AIgnoreExternals: Boolean): TAtlasVcsOutcome;
    function CommitsSince(const APath, ARevision: string; out ACount: Integer): TAtlasVcsOutcome;
    function SetExternals(const AOwner, AText: string): TAtlasVcsOutcome;
  end;

/// <summary>Wurzel der Arbeitskopie passend zum System (Pfade wie unter Windows bzw. Linux).</summary>
function Root: string;
begin
  if PathDelim = '\' then
    Result := 'C:\Projekte\Kasse'
  else
    Result := '/home/projekte/kasse';
end;

function Under(const ARelative: string): string;
begin
  Result := Root + PathDelim + StringReplace(ARelative, '/', PathDelim, [rfReplaceAll]);
end;

/// <summary>Datei aus Tests\Data\&lt;AFolder&gt;, gesucht ab dem Ordner des Testprogramms aufwärts.</summary>
function Fixture(const AFolder, AName: string): string;
var
  mDirectory, mFileName: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    mFileName := TPath.Combine(mDirectory, TPath.Combine('Tests', TPath.Combine('Data',
      TPath.Combine(AFolder, AName))));
    if TFile.Exists(mFileName) then
      Exit(TFile.ReadAllText(mFileName, TEncoding.UTF8));
    if ExtractFileDir(mDirectory) = mDirectory then
      Break;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  raise Exception.Create('Tests\Data\' + AFolder + '\' + AName + ' nicht gefunden');
end;

function Externals: TArray<TAtlasVcsSvnExternal>;
begin
  Result := TAtlasSvnExternals.ParseAll(TArray<TAtlasVcsSvnExternalDefinition>.Create(
    TAtlasVcsSvnExternalDefinition.Make('', cDefinition)), cRepository + '/Kasse/trunk', cRepository);
  // Bon.txt ist ein Datei-External (Collect erkennt das am Dateisystem).
  Result[3].IsFile := True;
end;

function Change(const APath: string; AKind: TAtlasVcsChangeKind): TAtlasVcsChange;
begin
  Result := Default(TAtlasVcsChange);
  Result.Path := APath;
  Result.Kind := AKind;
end;

{ TFakeSvn }

function TFakeSvn.Kind: TAtlasVcsKind;
begin
  Result := TAtlasVcsKind.Svn;
end;

function TFakeSvn.WorkingCopy: TAtlasVcsWorkingCopy;
begin
  Result := Default(TAtlasVcsWorkingCopy);
  Result.Kind := TAtlasVcsKind.Svn;
  Result.Root := Root;
end;

function TFakeSvn.Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
begin
  AHead := TAtlasVcsHead.Empty;
  AHead.Branch := 'Kasse/trunk';
  AHead.Revision := '48231';
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeSvn.Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeSvn.FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
begin
  AContent := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeSvn.Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
begin
  ALines := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeSvn.ChangeMarker: string;
begin
  Result := '';
end;

function TFakeSvn.WorkingRevisions(out AText: string): TAtlasVcsOutcome;
begin
  Result := WorkingRevisions('.', AText);
end;

function TFakeSvn.WorkingRevisions(const AFolder: string; out AText: string): TAtlasVcsOutcome;
begin
  Calls := Calls + ['svnversion ' + AFolder];
  AText := '48190:48211M';
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeSvn.ExternalsXml(out AText: string): TAtlasVcsOutcome;
begin
  AText := ExternalsText;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeSvn.RepositoryRoot(out AUrl: string): TAtlasVcsOutcome;
begin
  AUrl := cRepository;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeSvn.ToolVersion(out AVersion: string): TAtlasVcsOutcome;
begin
  AVersion := '1.14.3';
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeSvn.StatusXml(out AText: string): TAtlasVcsOutcome;
begin
  AText := StatusText;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeSvn.Update(AIgnoreExternals: Boolean): TAtlasVcsOutcome;
begin
  Calls := Calls + ['update ' + BoolToStr(AIgnoreExternals, True)];
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeSvn.CommitsSince(const APath, ARevision: string; out ACount: Integer): TAtlasVcsOutcome;
begin
  Calls := Calls + ['log ' + APath + ' ' + ARevision];
  ACount := Commits;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeSvn.SetExternals(const AOwner, AText: string): TAtlasVcsOutcome;
begin
  Calls := Calls + ['propset [' + AOwner + '] ' + AText];
  Result := TAtlasVcsOutcome.Ok;
end;

{ TAtlasVcsWorkingCopiesTests }

procedure TAtlasVcsWorkingCopiesTests.CollectsSvnExternalsWithChanges;
var
  mRows: TArray<TAtlasVcsWorkingCopyRow>;
begin
  mRows := TAtlasVcsWorkingCopies.FromSvn(Root, 'Kasse/trunk', '48231', Externals,
    Fixture('Svn', 'status-externals.xml'));
  Assert.AreEqual(5, Integer(Length(mRows)), 'Wurzel, Basis, Drucken, Drucken/Lib, Kunden; ohne Datei-External');
  Assert.AreEqual('', mRows[0].Path);
  Assert.AreEqual('Kasse', mRows[0].Caption('Kasse'));
  Assert.AreEqual('Kasse/trunk', mRows[0].RepositoryPath);
  Assert.AreEqual('48231', mRows[0].Revision);
  Assert.AreEqual(2, mRows[0].Changed, 'Kasse.dpr und die Eigenschaft der Wurzel, nicht Neu.txt');
  Assert.AreEqual('Packages/Basis', mRows[1].Path);
  Assert.AreEqual('Packages\Basis', mRows[1].Caption('Kasse'));
  Assert.AreEqual(1, mRows[1].Depth);
  Assert.AreEqual(0, mRows[1].Changed);
  Assert.AreEqual('Packages/Basis/trunk', mRows[1].RepositoryPath);
  Assert.AreEqual(0, mRows[1].ExternalIndex);
  Assert.IsFalse(mRows[1].Loaded, 'Revision kommt mit FillRevision');
  Assert.AreEqual('Packages/Drucken', mRows[2].Path);
  Assert.AreEqual(2, mRows[2].Changed);
  // Nur aus dem Status: External in einem External, eine Stufe tiefer, ohne Quelle.
  Assert.AreEqual('Packages/Drucken/Lib', mRows[3].Path);
  Assert.AreEqual(2, mRows[3].Depth);
  Assert.AreEqual(1, mRows[3].Changed, 'Konflikt zählt');
  Assert.AreEqual(-1, mRows[3].ExternalIndex);
  Assert.AreEqual('', mRows[3].RepositoryPath);
  Assert.AreEqual('Packages/Kunden', mRows[4].Path);
  Assert.IsTrue(mRows[4].Fixed);
  Assert.AreEqual('4711', mRows[4].FixedRevision);
  Assert.IsTrue(mRows[4].Kind = TAtlasVcsWorkingCopyKind.External);
  // Ohne Status: Zeilen aus svn:externals, Änderungen unbekannt.
  mRows := TAtlasVcsWorkingCopies.FromSvn(Root, 'Kasse/trunk', '48231', Externals, '');
  Assert.AreEqual(4, Integer(Length(mRows)));
  Assert.AreEqual(-1, mRows[1].Changed);
  Assert.AreEqual(4, Integer(Length(TAtlasVcsWorkingCopies.StatusExternals(Fixture('Svn',
    'status-externals.xml')))), 'drei in der Wurzel, eins in Drucken');
  mRows := nil;
end;

procedure TAtlasVcsWorkingCopiesTests.ParsesSubmoduleStatus;
var
  mRows: TArray<TAtlasVcsWorkingCopyRow>;
begin
  mRows := TAtlasVcsWorkingCopies.FromSubmodules(Root, 'main', '1a2b3c4',
    ' 0123456789abcdef0123456789abcdef01234567 Libs/Json (v1.2)'#10 +
    '+fedcba9876543210fedcba9876543210fedcba98 Libs/Zip'#13#10 +
    '-1111111111111111111111111111111111111111 Vendor/Alt'#10'kaputt'#10);
  Assert.AreEqual(4, Integer(Length(mRows)));
  Assert.AreEqual('main', mRows[0].RepositoryPath);
  Assert.AreEqual('Libs/Json', mRows[1].Path);
  Assert.AreEqual('0123456', mRows[1].Revision);
  Assert.IsTrue(mRows[1].Kind = TAtlasVcsWorkingCopyKind.Submodule);
  Assert.AreEqual(-1, mRows[1].Changed, 'kommt mit FillChanges');
  Assert.AreEqual('Libs/Zip', mRows[2].Path);
  Assert.AreEqual('Vendor/Alt', mRows[3].Path);
  Assert.AreEqual('', mRows[3].Revision, 'nicht ausgecheckt');
  Assert.AreEqual(1, Integer(Length(TAtlasVcsWorkingCopies.FromSubmodules(Root, 'main', '1a2b3c4', ''))));
  mRows := nil;
end;

procedure TAtlasVcsWorkingCopiesTests.SplitsChangesPerWorkingCopy;
var
  mRows: TArray<TAtlasVcsWorkingCopyRow>;
  mCounts: TArray<Integer>;
  mFake: TFakeSvn;
  mVcs: IAtlasVersionControl;
  mChanges: TArray<TAtlasVcsChange>;
begin
  mRows := TAtlasVcsWorkingCopies.FromSvn(Root, 'Kasse/trunk', '48231', Externals, '');
  mCounts := TAtlasVcsWorkingCopies.Split(TArray<TAtlasVcsChange>.Create(
    Change(Under('Kasse.dpr'), TAtlasVcsChangeKind.Modified),
    Change(Under('Packages/Drucken/Drucken.pas'), TAtlasVcsChangeKind.Modified),
    Change(Under('Packages/Drucken/Bon.pas'), TAtlasVcsChangeKind.Added),
    Change(Under('Packages/Drucken/Neu.pas'), TAtlasVcsChangeKind.Untracked),
    Change(Under('Packages/DruckenAlt/X.pas'), TAtlasVcsChangeKind.Modified)), mRows);
  Assert.AreEqual(4, Integer(Length(mCounts)));
  Assert.AreEqual(2, mCounts[0], 'Kasse.dpr und DruckenAlt (kein External)');
  Assert.AreEqual(0, mCounts[1]);
  Assert.AreEqual(3, mCounts[2], 'alle Arten, der Aufrufer filtert');
  // Wie im Plugin: svn status der Wurzel über den Parser des Providers, Ordner aus demselben Status.
  mFake := TFakeSvn.Create;
  mVcs := mFake;
  mFake.StatusText := Fixture('Svn', 'status-externals.xml');
  mRows := TAtlasVcsWorkingCopies.Folders(mVcs);
  Assert.AreEqual(5, Integer(Length(mRows)), 'Wurzel, Basis, Drucken, Drucken/Lib, Kunden');
  Assert.AreEqual('Packages/Drucken/Lib', mRows[3].Path);
  mChanges := TAtlasSvnParser.ParseStatus(mFake.StatusText, Root);
  mCounts := TAtlasVcsWorkingCopies.Split(mChanges, mRows);
  // Kasse.dpr, Neu.txt, Eigenschaft der Wurzel | Drucken.pas, Bon.pas | Json.pas.
  Assert.AreEqual(3, mCounts[0]);
  Assert.AreEqual(0, mCounts[1]);
  Assert.AreEqual(2, mCounts[2]);
  Assert.AreEqual(1, mCounts[3]);
  Assert.AreEqual(0, mCounts[4]);
  Assert.AreEqual(0, Integer(Length(TAtlasVcsWorkingCopies.Folders(nil))));
  mFake.StatusText := '';
  mRows := nil;
  mCounts := nil;
  mChanges := nil;
end;

procedure TAtlasVcsWorkingCopiesTests.ParsesUpdateSetting;
begin
  Assert.IsTrue(AtlasVcsExternalsUpdateOf('without') = TAtlasVcsExternalsUpdate.WithoutExternals);
  Assert.IsTrue(AtlasVcsExternalsUpdateOf('ASK') = TAtlasVcsExternalsUpdate.Ask);
  Assert.IsTrue(AtlasVcsExternalsUpdateOf('') = TAtlasVcsExternalsUpdate.WithExternals);
end;

procedure TAtlasVcsWorkingCopiesTests.PinsOneLine;
var
  mList: TAtlasVcsWorkingCopyList;
  mOwner, mText: string;
begin
  mList := TAtlasVcsWorkingCopyList.Empty;
  mList.Kind := TAtlasVcsKind.Svn;
  mList.Root := Root;
  mList.Definitions := TArray<TAtlasVcsSvnExternalDefinition>.Create(TAtlasVcsSvnExternalDefinition.Make('',
    cDefinition));
  mList.Externals := Externals;
  mList.Rows := TAtlasVcsWorkingCopies.FromSvn(Root, 'Kasse/trunk', '48231', mList.Externals, '');
  Assert.IsFalse(mList.Rows[1].CanPin, 'Revision noch unbekannt');
  mList.Rows[2].Revision := '48211';
  Assert.IsTrue(mList.Rows[2].CanPin);
  Assert.IsTrue(TAtlasVcsWorkingCopies.PinnedText(mList, 2, mOwner, mText));
  Assert.AreEqual('', mOwner);
  Assert.AreEqual('# Packages'#10'^/Packages/Basis/trunk Packages/Basis'#10 +
    '-r 48211 ^/Packages/Drucken/trunk Packages/Drucken'#10'-r 4711 ^/Packages/Kunden/trunk Packages/Kunden'#10 +
    '^/Vorlagen/trunk/Bon.txt Bon.txt'#10, mText);
  // Fest: nichts festzuschreiben; Wurzel ebenso.
  mList.Rows[3].Revision := '4711';
  Assert.IsFalse(TAtlasVcsWorkingCopies.PinnedText(mList, 3, mOwner, mText));
  Assert.IsFalse(TAtlasVcsWorkingCopies.PinnedText(mList, 0, mOwner, mText));
  Assert.IsFalse(TAtlasVcsWorkingCopies.PinnedText(mList, 9, mOwner, mText));
  Assert.IsTrue(TAtlasVcsWorkingCopies.Pin(mList, 3, nil) = TAtlasVcsOutcome.Failed);
  mList := TAtlasVcsWorkingCopyList.Empty;
  mText := '';
end;

procedure TAtlasVcsWorkingCopiesTests.CollectAndCheckServerThroughVcs;
var
  mFake: TFakeSvn;
  mVcs: IAtlasVersionControl;
  mSvn: IAtlasVcsSvnWorkingCopy;
  mExternals: IAtlasVcsSvnExternals;
  mList: TAtlasVcsWorkingCopyList;
begin
  mFake := TFakeSvn.Create;
  mVcs := mFake;
  mFake.StatusText := Fixture('Svn', 'status-externals.xml');
  mFake.ExternalsText := '<?xml version="1.0"?><properties><target path="' + Root +
    '"><property name="svn:externals">^/Packages/Basis/trunk Packages/Basis'#10 +
    '-r 4711 ^/Packages/Kunden/trunk Packages/Kunden'#10'</property></target></properties>';
  mList := TAtlasVcsWorkingCopies.Collect(mVcs);
  Assert.IsTrue(mList.Outcome = TAtlasVcsOutcome.Ok);
  Assert.IsTrue(mList.Several);
  // Basis und Kunden aus svn:externals, Drucken und Lib nur aus dem Status.
  Assert.AreEqual(5, Integer(Length(mList.Rows)));
  Assert.AreEqual('Packages/Basis/trunk', mList.Rows[1].RepositoryPath);
  Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'Revisionen erst mit FillRevision');
  Assert.IsTrue(Supports(mVcs, IAtlasVcsSvnWorkingCopy, mSvn));
  TAtlasVcsWorkingCopies.FillRevision(mList, 1, mSvn);
  Assert.AreEqual('48211', mList.Rows[1].Revision, 'höchste Revision');
  Assert.AreEqual('svnversion Packages/Basis', mFake.Calls[0]);
  TAtlasVcsWorkingCopies.FillRevision(mList, 1, mSvn);
  Assert.AreEqual(1, Integer(Length(mFake.Calls)), 'nur einmal');
  // Server prüfen: fest nach der festen Revision, sonst nach der Revision der Arbeitskopie; ohne Pfad nicht.
  Assert.IsTrue(Supports(mVcs, IAtlasVcsSvnExternals, mExternals));
  mFake.Commits := 3;
  Assert.IsTrue(TAtlasVcsWorkingCopies.CheckServer(mList, 4, mExternals) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(3, mList.Rows[4].Incoming);
  Assert.AreEqual('log Packages/Kunden/trunk 4711', mFake.Calls[1]);
  mFake.Commits := 0;
  TAtlasVcsWorkingCopies.CheckServer(mList, 1, mExternals);
  Assert.AreEqual('log Packages/Basis/trunk 48211', mFake.Calls[2]);
  Assert.AreEqual(0, mList.Rows[1].Incoming);
  Assert.IsTrue(TAtlasVcsWorkingCopies.CheckServer(mList, 3, mExternals) = TAtlasVcsOutcome.Failed);
  Assert.AreEqual(-1, mList.Rows[3].Incoming);
  // Festschreiben: propset im definierenden Ordner, kein Commit.
  Assert.IsTrue(TAtlasVcsWorkingCopies.Pin(mList, 1, mExternals) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('propset [] -r 48211 ^/Packages/Basis/trunk Packages/Basis'#10 +
    '-r 4711 ^/Packages/Kunden/trunk Packages/Kunden'#10, mFake.Calls[3]);
  Assert.AreEqual(4, Integer(Length(mFake.Calls)));
  Assert.IsTrue(TAtlasVcsWorkingCopies.Collect(nil).Outcome = TAtlasVcsOutcome.NoWorkingCopy);
  mFake.Calls := nil;
  mFake.StatusText := '';
  mFake.ExternalsText := '';
  mList := TAtlasVcsWorkingCopyList.Empty;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsWorkingCopiesTests);

end.
