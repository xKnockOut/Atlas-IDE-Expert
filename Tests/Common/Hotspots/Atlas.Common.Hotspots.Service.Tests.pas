unit Atlas.Common.Hotspots.Service.Tests;

// Tests des Hotspot-Dienstes (#1354) mit einer Versionsverwaltung im
// Speicher (THotspotFakeVcs): Rangliste aus Änderungen und Komplexität,
// Zwischenspeicher je Stand, Umfang (Bibliothek, Ausschlüsse, Dateien,
// außerhalb der Arbeitskopie), Umbenennungen, Trend, Methodenebene über
// LineLog, Kopplung ohne uses-Kante, gleiche Werte für Git und SVN und die
// Zeitmessung mit 5000 Commits und 1000 Units.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Atlas.Common.Hotspots.Contract;

type
  /// <summary>Versionsverwaltung im Speicher: Commits neueste zuerst, LineLog liefert die Commits, die die Datei
  /// ändern, TextAt die hinterlegten Stände.</summary>
  THotspotFakeVcs = class(TInterfacedObject, IHotspotVcs)
  private
    FKind: THotspotVcsKind;
    FRoot: string;
    FHead: string;
    FCommits: TArray<THotspotCommit>;
    FPast: TDictionary<string, string>;
    FPastState: THotspotTextState;
    FLogs: Integer;
    FLineLogs: Integer;
    FTexts: TArray<string>;
    FLogError: string;
  public
    constructor Create(AKind: THotspotVcsKind; const ARoot: string);
    destructor Destroy; override;
    /// <summary>Commit vor den bisherigen (also älter); APaths relativ mit "/".</summary>
    procedure AddCommit(const ARevision, AAuthor: string; ADate: TDateTime; const APaths: TArray<string>); overload;
    procedure AddCommit(const ACommit: THotspotCommit); overload;
    /// <summary>Text von APath (Name in jenem Stand) im Stand vor dem Trend-Abstand.</summary>
    procedure SetPast(const APath, AText: string);
    function Kind: THotspotVcsKind;
    function Root: string;
    function Head: string;
    function Log(ASince: TDateTime; out ACommits: TArray<THotspotCommit>; out AError: string): Boolean;
    function LineLog(const AFileName: string; AFirstLine, ALastLine: Integer; ASince: TDateTime;
      out ACommits: TArray<THotspotLineCommit>): Boolean;
    function TextAt(const AFileName: string; ADate: TDateTime; out AText: string): THotspotTextState;
    property HeadValue: string read FHead write FHead;
    /// <summary>Ergebnis von TextAt für Dateien ohne hinterlegten Stand.</summary>
    property PastState: THotspotTextState read FPastState write FPastState;
    property Logs: Integer read FLogs;
    /// <summary>Nicht leer: Log scheitert mit diesem Text.</summary>
    property LogError: string read FLogError write FLogError;
    property LineLogs: Integer read FLineLogs;
    /// <summary>Pfade, nach denen TextAt gefragt wurde.</summary>
    property Texts: TArray<string> read FTexts;
  end;

  [TestFixture]
  THotspotServiceTests = class
  public
    [Test]
    procedure RanksChangedComplexUnits;
    [Test]
    procedure CachesUntilNextCommit;
    [Test]
    procedure ScopeSkipsLibraryExcludesAndOutside;
    [Test]
    procedure RenamedFileKeepsHistory;
    [Test]
    procedure TrendFromPastState;
    [Test]
    procedure MethodLevelReadsLineLogOfCandidates;
    [Test]
    procedure CouplingSkipsUsesEdges;
    [Test]
    procedure SvnGivesSameValuesAsGit;
    [Test]
    procedure RequestFromSettings;
    [Test]
    [Category('Benchmark')]
    procedure FiveThousandCommitsThousandUnits;
  end;

/// <summary>Unit AName mit einer Prozedur Run aus AIfs if-Anweisungen (kognitiv AIfs).</summary>
function HotspotUnitText(const AName: string; AIfs: Integer): string;
/// <summary>Festes "jetzt" der Tests (UTC).</summary>
function HotspotNow: TDateTime;

implementation

uses
  System.DateUtils,
  System.Diagnostics,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Hotspots.Analysis,
  Atlas.Common.Hotspots.Service,
  Atlas.Common.Architecture.UsesGraph.Tests;

function HotspotNow: TDateTime;
begin
  Result := EncodeDateTime(2026, 10, 29, 12, 0, 0, 0);
end;

function HotspotUnitText(const AName: string; AIfs: Integer): string;
var
  mIndex: Integer;
begin
  Result := 'unit ' + AName + ';'#10#10'interface'#10#10'procedure Run(A: Integer);'#10#10'implementation'#10#10 +
    'procedure Run(A: Integer);'#10'begin'#10;
  for mIndex := 1 to AIfs do
    Result := Result + '  if A > ' + IntToStr(mIndex) + ' then'#10'    A := A - 1;'#10;
  Result := Result + 'end;'#10#10'end.'#10;
end;

/// <summary>Pfad relativ zu C:\Projekt wie UsesUnit.</summary>
function PathOf(const AName: string): string;
begin
  Result := StringReplace(AName, '.', '/', [rfReplaceAll]) + '.pas';
end;

{ THotspotFakeVcs }

constructor THotspotFakeVcs.Create(AKind: THotspotVcsKind; const ARoot: string);
begin
  inherited Create;
  FKind := AKind;
  FRoot := ARoot;
  FHead := 'h1';
  FPast := TDictionary<string, string>.Create;
  FPastState := THotspotTextState.Missing;
end;

destructor THotspotFakeVcs.Destroy;
begin
  FPast.Free;
  inherited Destroy;
end;

procedure THotspotFakeVcs.AddCommit(const ARevision, AAuthor: string; ADate: TDateTime;
  const APaths: TArray<string>);
var
  mCommit: THotspotCommit;
  mPath: string;
  mAdded: Integer;
begin
  mCommit := Default(THotspotCommit);
  mCommit.Revision := ARevision;
  mCommit.Author := AAuthor;
  mCommit.Date := ADate;
  mCommit.Summary := 'Änderung ' + ARevision;
  // SVN kennt keine Zeilen im Log.
  mAdded := 3;
  if FKind = THotspotVcsKind.Svn then
    mAdded := -1;
  for mPath in APaths do
    mCommit.Files := mCommit.Files + [THotspotFileChange.Make(mPath, '', THotspotChangeKind.Modified, mAdded,
      mAdded)];
  AddCommit(mCommit);
end;

procedure THotspotFakeVcs.AddCommit(const ACommit: THotspotCommit);
begin
  FCommits := FCommits + [ACommit];
end;

procedure THotspotFakeVcs.SetPast(const APath, AText: string);
begin
  FPast.AddOrSetValue(LowerCase(APath), AText);
end;

function THotspotFakeVcs.Kind: THotspotVcsKind;
begin
  Result := FKind;
end;

function THotspotFakeVcs.Root: string;
begin
  Result := FRoot;
end;

function THotspotFakeVcs.Head: string;
begin
  Result := FHead;
end;

function THotspotFakeVcs.Log(ASince: TDateTime; out ACommits: TArray<THotspotCommit>; out AError: string): Boolean;
var
  mCommit: THotspotCommit;
begin
  Inc(FLogs);
  AError := FLogError;
  ACommits := nil;
  if FLogError <> '' then
    Exit(False);
  for mCommit in FCommits do
    if mCommit.Date >= ASince then
      ACommits := ACommits + [mCommit];
  Result := True;
end;

function THotspotFakeVcs.LineLog(const AFileName: string; AFirstLine, ALastLine: Integer; ASince: TDateTime;
  out ACommits: TArray<THotspotLineCommit>): Boolean;
var
  mCommit: THotspotCommit;
  mFile: THotspotFileChange;
  mLine: THotspotLineCommit;
  mPath: string;
begin
  Inc(FLineLogs);
  ACommits := nil;
  mPath := StringReplace(Copy(AFileName, Length(FRoot) + 2, MaxInt), '\', '/', [rfReplaceAll]);
  for mCommit in FCommits do
  begin
    if mCommit.Date < ASince then
      Continue;
    for mFile in mCommit.Files do
      if SameText(mFile.Path, mPath) then
      begin
        mLine := Default(THotspotLineCommit);
        mLine.Revision := mCommit.Revision;
        mLine.Author := mCommit.Author;
        mLine.Date := mCommit.Date;
        mLine.Summary := mCommit.Summary;
        mLine.Added := 1;
        mLine.Deleted := 1;
        ACommits := ACommits + [mLine];
        Break;
      end;
  end;
  Result := True;
end;

function THotspotFakeVcs.TextAt(const AFileName: string; ADate: TDateTime; out AText: string): THotspotTextState;
begin
  FTexts := FTexts + [AFileName];
  if FPast.TryGetValue(LowerCase(AFileName), AText) then
    Exit(THotspotTextState.Found);
  AText := '';
  Result := FPastState;
end;

{ Hilfen }

type
  /// <summary>Quelltexte je Datei für den Dienst.</summary>
  TTexts = class
  private
    FTexts: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Put(const AName: string; AIfs: Integer);
    function Read(const AFileName: string; out AText: string): Boolean;
  end;

constructor TTexts.Create;
begin
  inherited Create;
  FTexts := TDictionary<string, string>.Create;
end;

destructor TTexts.Destroy;
begin
  FTexts.Free;
  inherited Destroy;
end;

procedure TTexts.Put(const AName: string; AIfs: Integer);
begin
  FTexts.AddOrSetValue(LowerCase(UsesUnit(AName, nil, nil).FileName), HotspotUnitText(AName, AIfs));
end;

function TTexts.Read(const AFileName: string; out AText: string): Boolean;
begin
  Result := FTexts.TryGetValue(LowerCase(AFileName), AText);
end;

function NewService(const AIndex: ISymbolIndex; ATexts: TTexts): THotspotService;
begin
  Result := THotspotService.Create(AIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ATexts.Read(AFileName, AText);
    end);
end;

function NewRequest: THotspotRequest;
begin
  Result := THotspotRequest.FromSettings(TServerSettings.Default);
  Result.Title := 'Projekt';
  Result.Root := 'C:\Projekt';
end;

function Day(ADaysAgo: Integer): TDateTime;
begin
  Result := IncDay(HotspotNow, -ADaysAgo);
end;

function IndexOf(const AEntries: TArray<THotspotEntry>; const AUnit: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AEntries) do
    if SameText(AEntries[mIndex].UnitName, AUnit) then
      Exit(mIndex);
  Result := -1;
end;

{ THotspotServiceTests }

procedure THotspotServiceTests.RanksChangedComplexUnits;
var
  mIndex: ISymbolIndex;
  mTexts: TTexts;
  mService: THotspotService;
  mVcs: THotspotFakeVcs;
  mVcsRef: IHotspotVcs;
  mResult: THotspotResult;
  mExpected: Double;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('App.Kern', nil, nil));
  mIndex.AddUnit(UsesUnit('App.Klein', nil, nil));
  mIndex.AddUnit(UsesUnit('App.Ruhig', nil, nil));
  mTexts := TTexts.Create;
  mVcs := THotspotFakeVcs.Create(THotspotVcsKind.Git, 'C:\Projekt');
  mVcsRef := mVcs;
  mService := NewService(mIndex, mTexts);
  try
    mTexts.Put('App.Kern', 8);
    mTexts.Put('App.Klein', 1);
    mTexts.Put('App.Ruhig', 20);
    mVcs.AddCommit('c4', 'anna', Day(1), [PathOf('App.Kern'), PathOf('App.Klein')]);
    mVcs.AddCommit('c3', 'bernd', Day(10), [PathOf('App.Kern')]);
    mVcs.AddCommit('c2', 'anna', Day(20), [PathOf('App.Klein')]);
    mVcs.AddCommit('c1', 'anna', Day(30), [PathOf('App.Kern'), 'Doku/Liesmich.md']);
    // Älter als der Zeitraum (12 Monate).
    mVcs.AddCommit('c0', 'anna', Day(400), [PathOf('App.Ruhig')]);
    mResult := mService.Analyze(NewRequest, mVcsRef, HotspotNow);
    Assert.AreEqual(4, mResult.Commits);
    Assert.AreEqual(2, Integer(Length(mResult.Units)), 'App.Ruhig ohne Änderung im Zeitraum');
    Assert.AreEqual('App.Kern', mResult.Units[0].UnitName);
    Assert.AreEqual(3, mResult.Units[0].Changes.Changes, 'wie git log');
    Assert.AreEqual(2, Integer(Length(mResult.Units[0].Changes.Authors)));
    Assert.AreEqual(8, mResult.Units[0].Complexity);
    Assert.AreEqual(1.0, mResult.Units[0].Score, 1E-9);
    Assert.AreEqual('App/Kern.pas', mResult.Units[0].Path);
    Assert.AreEqual('App.Klein', mResult.Units[1].UnitName);
    Assert.AreEqual(2, mResult.Units[1].Changes.Changes);
    // Als Variable: Free Pascal rechnet konstante Ausdrücke sonst in einfacher Genauigkeit.
    mExpected := 2;
    mExpected := mExpected / 3 / 8;
    Assert.AreEqual(mExpected, mResult.Units[1].Score, 1E-9);
    Assert.IsTrue(mResult.Kind = THotspotVcsKind.Git);
    Assert.AreEqual('h1', mResult.Head);
    Assert.AreEqual(0, Integer(Length(mResult.Methods)), 'Unit-Ebene');
  finally
    mService.Free;
    mTexts.Free;
  end;
end;

procedure THotspotServiceTests.CachesUntilNextCommit;
var
  mIndex: ISymbolIndex;
  mTexts: TTexts;
  mService: THotspotService;
  mVcs: THotspotFakeVcs;
  mVcsRef: IHotspotVcs;
  mRequest: THotspotRequest;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('A', nil, nil));
  mTexts := TTexts.Create;
  mVcs := THotspotFakeVcs.Create(THotspotVcsKind.Git, 'C:\Projekt');
  mVcsRef := mVcs;
  mService := NewService(mIndex, mTexts);
  try
    mTexts.Put('A', 2);
    mVcs.AddCommit('c1', 'anna', Day(1), ['A.pas']);
    mRequest := NewRequest;
    mService.Analyze(mRequest, mVcsRef, HotspotNow);
    mService.Analyze(mRequest, mVcsRef, HotspotNow);
    Assert.AreEqual(1, mService.Computations, 'gleicher Stand');
    Assert.AreEqual(1, mService.HistoryReads);
    mRequest.Options.MinSharedCommits := 7;
    mService.Analyze(mRequest, mVcsRef, HotspotNow);
    Assert.AreEqual(2, mService.Computations, 'andere Anfrage');
    Assert.AreEqual(1, mService.HistoryReads, 'Verlauf bleibt');
    mIndex.AddUnit(UsesUnit('B', nil, nil));
    mService.Analyze(mRequest, mVcsRef, HotspotNow);
    Assert.AreEqual(3, mService.Computations, 'neue Index-Generation');
    Assert.AreEqual(1, mService.HistoryReads);
    mVcs.HeadValue := 'h2';
    mService.Analyze(mRequest, mVcsRef, HotspotNow);
    Assert.AreEqual(2, mService.HistoryReads, 'neuer Commit');
    Assert.AreEqual(4, mService.Computations);
    mVcs.HeadValue := '';
    mService.Analyze(mRequest, mVcsRef, HotspotNow);
    mService.Analyze(mRequest, mVcsRef, HotspotNow);
    Assert.AreEqual(4, mService.HistoryReads, 'ohne bekannten Stand jedes Mal');
  finally
    mService.Free;
    mTexts.Free;
  end;
end;

procedure THotspotServiceTests.ScopeSkipsLibraryExcludesAndOutside;
var
  mIndex: ISymbolIndex;
  mTexts: TTexts;
  mService: THotspotService;
  mVcs: THotspotFakeVcs;
  mVcsRef: IHotspotVcs;
  mRequest: THotspotRequest;
  mResult: THotspotResult;
  mLibrary, mOutside: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('App.Main', nil, nil));
  mIndex.AddUnit(UsesUnit('App.Main.Tests', nil, nil));
  mIndex.AddUnit(UsesUnit('App.Data', nil, nil));
  mLibrary := UsesUnit('Lib.Fremd', nil, nil);
  mLibrary.Library_ := True;
  mIndex.AddUnit(mLibrary);
  mOutside := UsesUnit('Anders', nil, nil);
  mOutside.FileName := 'D:\Woanders\Anders.pas';
  mIndex.AddUnit(mOutside);
  mTexts := TTexts.Create;
  mVcs := THotspotFakeVcs.Create(THotspotVcsKind.Git, 'C:\Projekt');
  mVcsRef := mVcs;
  mService := NewService(mIndex, mTexts);
  try
    mTexts.Put('App.Main', 3);
    mTexts.Put('App.Main.Tests', 3);
    mTexts.Put('App.Data', 3);
    mTexts.Put('Lib.Fremd', 3);
    mVcs.AddCommit('c1', 'anna', Day(1), [PathOf('App.Main'), PathOf('App.Main.Tests'), PathOf('App.Data'),
      PathOf('Lib.Fremd'), 'Anders.pas']);
    mRequest := NewRequest;
    mRequest.Exclude := ['*.Tests'];
    mResult := mService.Analyze(mRequest, mVcsRef, HotspotNow);
    Assert.AreEqual(2, Integer(Length(mResult.Units)), 'keine Bibliothek, kein Ausschluss, nichts außerhalb');
    Assert.AreEqual(-1, IndexOf(mResult.Units, 'App.Main.Tests'));
    Assert.AreEqual(-1, IndexOf(mResult.Units, 'Lib.Fremd'));
    Assert.AreEqual(-1, IndexOf(mResult.Units, 'Anders'));
    mRequest.Files := [UsesUnit('App.Data', nil, nil).FileName];
    mResult := mService.Analyze(mRequest, mVcsRef, HotspotNow);
    Assert.AreEqual(1, Integer(Length(mResult.Units)), 'nur Dateien des Projekts');
    Assert.AreEqual('App.Data', mResult.Units[0].UnitName);
  finally
    mService.Free;
    mTexts.Free;
  end;
end;

procedure THotspotServiceTests.RenamedFileKeepsHistory;
var
  mIndex: ISymbolIndex;
  mTexts: TTexts;
  mService: THotspotService;
  mVcs: THotspotFakeVcs;
  mVcsRef: IHotspotVcs;
  mResult: THotspotResult;
  mCommit: THotspotCommit;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('App.Neu', nil, nil));
  mTexts := TTexts.Create;
  mVcs := THotspotFakeVcs.Create(THotspotVcsKind.Git, 'C:\Projekt');
  mVcsRef := mVcs;
  mService := NewService(mIndex, mTexts);
  try
    mTexts.Put('App.Neu', 6);
    mVcs.AddCommit('c3', 'anna', Day(5), [PathOf('App.Neu')]);
    mCommit := Default(THotspotCommit);
    mCommit.Revision := 'c2';
    mCommit.Author := 'anna';
    mCommit.Date := Day(50);
    mCommit.Files := [THotspotFileChange.Make(PathOf('App.Neu'), PathOf('App.Alt'), THotspotChangeKind.Renamed, 0, 0)];
    mVcs.AddCommit(mCommit);
    mVcs.AddCommit('c1', 'bernd', Day(150), [PathOf('App.Alt')]);
    // Vor drei Monaten hieß die Datei noch App/Alt.pas.
    mVcs.SetPast(PathOf('App.Alt'), HotspotUnitText('App.Alt', 2));
    mResult := mService.Analyze(NewRequest, mVcsRef, HotspotNow);
    Assert.AreEqual(1, Integer(Length(mResult.Units)));
    Assert.AreEqual(3, mResult.Units[0].Changes.Changes, 'Verlauf unter dem alten Namen zählt');
    Assert.AreEqual(2, Integer(Length(mResult.Units[0].Changes.Authors)));
    Assert.AreEqual(PathOf('App.Alt'), mVcs.Texts[0], 'Stand vor drei Monaten unter dem damaligen Namen');
    Assert.AreEqual(2, mResult.Units[0].PastComplexity);
    Assert.IsTrue(mResult.Units[0].Trend = THotspotTrend.Rising);
  finally
    mService.Free;
    mTexts.Free;
  end;
end;

procedure THotspotServiceTests.TrendFromPastState;
var
  mIndex: ISymbolIndex;
  mTexts: TTexts;
  mService: THotspotService;
  mVcs: THotspotFakeVcs;
  mVcsRef: IHotspotVcs;
  mResult: THotspotResult;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('A', nil, nil));
  mIndex.AddUnit(UsesUnit('B', nil, nil));
  mIndex.AddUnit(UsesUnit('C', nil, nil));
  mTexts := TTexts.Create;
  mVcs := THotspotFakeVcs.Create(THotspotVcsKind.Git, 'C:\Projekt');
  mVcsRef := mVcs;
  mService := NewService(mIndex, mTexts);
  try
    mTexts.Put('A', 4);
    mTexts.Put('B', 4);
    mTexts.Put('C', 4);
    mVcs.AddCommit('c1', 'anna', Day(1), ['A.pas', 'B.pas', 'C.pas']);
    mVcs.SetPast('A.pas', HotspotUnitText('A', 8));
    mVcs.SetPast('B.pas', HotspotUnitText('B', 4));
    mVcs.PastState := THotspotTextState.Missing;
    mResult := mService.Analyze(NewRequest, mVcsRef, HotspotNow);
    Assert.IsTrue(mResult.Units[IndexOf(mResult.Units, 'A')].Trend = THotspotTrend.Falling);
    Assert.IsTrue(mResult.Units[IndexOf(mResult.Units, 'B')].Trend = THotspotTrend.Steady);
    Assert.IsTrue(mResult.Units[IndexOf(mResult.Units, 'C')].Trend = THotspotTrend.New, 'gab es damals nicht');
    Assert.AreEqual(-1, mResult.Units[IndexOf(mResult.Units, 'C')].PastComplexity);
    // Verlauf reicht nicht zurück (flacher Klon): unbekannt, nicht neu.
    mVcs.PastState := THotspotTextState.Unknown;
    mVcs.HeadValue := 'h2';
    mResult := mService.Analyze(NewRequest, mVcsRef, HotspotNow);
    Assert.IsTrue(mResult.Units[IndexOf(mResult.Units, 'C')].Trend = THotspotTrend.Unknown);
  finally
    mService.Free;
    mTexts.Free;
  end;
end;

procedure THotspotServiceTests.MethodLevelReadsLineLogOfCandidates;
var
  mIndex: ISymbolIndex;
  mTexts: TTexts;
  mService: THotspotService;
  mVcs: THotspotFakeVcs;
  mVcsRef: IHotspotVcs;
  mRequest: THotspotRequest;
  mResult: THotspotResult;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('A', nil, nil));
  mIndex.AddUnit(UsesUnit('B', nil, nil));
  mIndex.AddUnit(UsesUnit('C', nil, nil));
  mTexts := TTexts.Create;
  mVcs := THotspotFakeVcs.Create(THotspotVcsKind.Git, 'C:\Projekt');
  mVcsRef := mVcs;
  mService := NewService(mIndex, mTexts);
  try
    mTexts.Put('A', 5);
    mTexts.Put('B', 9);
    mTexts.Put('C', 1);
    mVcs.AddCommit('c3', 'anna', Day(1), ['A.pas', 'B.pas']);
    mVcs.AddCommit('c2', 'anna', Day(2), ['A.pas', 'C.pas']);
    mVcs.AddCommit('c1', 'anna', Day(3), ['A.pas']);
    mRequest := NewRequest;
    mRequest.Level := THotspotLevel.Methods;
    mRequest.Options.MethodCandidates := 2;
    mResult := mService.Analyze(mRequest, mVcsRef, HotspotNow);
    Assert.AreEqual(3, Integer(Length(mResult.Units)), 'Units stehen auch auf Methodenebene');
    Assert.AreEqual(2, mVcs.LineLogs, 'nur die obersten Kandidaten');
    Assert.AreEqual(2, Integer(Length(mResult.Methods)));
    Assert.AreEqual('A', mResult.Methods[0].UnitName, '3 Änderungen × 5');
    Assert.AreEqual('Run', mResult.Methods[0].Method);
    Assert.AreEqual(3, mResult.Methods[0].Changes.Changes);
    Assert.AreEqual(9, mResult.Methods[0].Line, 'Kopf der Prozedur im implementation-Teil');
    Assert.IsTrue(mResult.Methods[0].EndLine > mResult.Methods[0].Line);
    Assert.AreEqual('B', mResult.Methods[1].UnitName);
    mService.Analyze(mRequest, mVcsRef, HotspotNow);
    mIndex.AddUnit(UsesUnit('D', nil, nil));
    mService.Analyze(mRequest, mVcsRef, HotspotNow);
    Assert.AreEqual(2, mVcs.LineLogs, 'Methodenverlauf je Stand gemerkt');
  finally
    mService.Free;
    mTexts.Free;
  end;
end;

procedure THotspotServiceTests.CouplingSkipsUsesEdges;
var
  mIndex: ISymbolIndex;
  mTexts: TTexts;
  mService: THotspotService;
  mVcs: THotspotFakeVcs;
  mVcsRef: IHotspotVcs;
  mResult: THotspotResult;
  mDay: Integer;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('Kunde', nil, nil));
  mIndex.AddUnit(UsesUnit('Rechnung', nil, nil));
  mIndex.AddUnit(UsesUnit('Form', ['Kunde'], nil));
  mTexts := TTexts.Create;
  mVcs := THotspotFakeVcs.Create(THotspotVcsKind.Git, 'C:\Projekt');
  mVcsRef := mVcs;
  mService := NewService(mIndex, mTexts);
  try
    mTexts.Put('Kunde', 2);
    mTexts.Put('Rechnung', 2);
    mTexts.Put('Form', 2);
    for mDay := 1 to 6 do
      mVcs.AddCommit('c' + IntToStr(mDay), 'anna', Day(mDay), ['Kunde.pas', 'Rechnung.pas', 'Form.pas', 'Form.dfm']);
    mResult := mService.Analyze(NewRequest, mVcsRef, HotspotNow);
    // Kunde–Form hat eine uses-Kante; Form.pas/Form.dfm ist dieselbe Unit.
    Assert.AreEqual(2, Integer(Length(mResult.Coupling)));
    Assert.AreEqual('Form', mResult.Coupling[0].First.UnitName);
    Assert.AreEqual('Rechnung', mResult.Coupling[0].Second.UnitName);
    Assert.AreEqual('Kunde', mResult.Coupling[1].First.UnitName);
    Assert.AreEqual('Rechnung', mResult.Coupling[1].Second.UnitName);
    Assert.AreEqual(6, mResult.Coupling[1].Shared);
  finally
    mService.Free;
    mTexts.Free;
  end;
end;

procedure THotspotServiceTests.SvnGivesSameValuesAsGit;
var
  mIndex: ISymbolIndex;
  mTexts: TTexts;
  mService: THotspotService;
  mKind: THotspotVcsKind;
  mVcs: THotspotFakeVcs;
  mVcsRef: IHotspotVcs;
  mResults: array[0..1] of THotspotResult;
  mSlot, mEntry, mDay: Integer;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('A', nil, nil));
  mIndex.AddUnit(UsesUnit('B', nil, nil));
  mIndex.AddUnit(UsesUnit('C', nil, nil));
  mTexts := TTexts.Create;
  mService := NewService(mIndex, mTexts);
  try
    mTexts.Put('A', 3);
    mTexts.Put('B', 7);
    mTexts.Put('C', 2);
    mSlot := 0;
    for mKind in [THotspotVcsKind.Git, THotspotVcsKind.Svn] do
    begin
      // Gleich aufgebautes Repository: dieselben Commits, SVN ohne Zeilenzahlen.
      mVcs := THotspotFakeVcs.Create(mKind, 'C:\Projekt');
      mVcsRef := mVcs;
      for mDay := 1 to 6 do
        mVcs.AddCommit(IntToStr(100 - mDay), 'anna', Day(mDay), ['A.pas', 'C.pas']);
      mVcs.AddCommit('90', 'bernd', Day(9), ['B.pas']);
      mVcs.AddCommit('80', 'anna', Day(20), ['B.pas', 'A.pas']);
      mResults[mSlot] := mService.Analyze(NewRequest, mVcsRef, HotspotNow);
      Inc(mSlot);
    end;
    Assert.AreEqual(Integer(Length(mResults[0].Units)), Integer(Length(mResults[1].Units)));
    for mEntry := 0 to High(mResults[0].Units) do
    begin
      Assert.AreEqual(mResults[0].Units[mEntry].UnitName, mResults[1].Units[mEntry].UnitName);
      Assert.AreEqual(mResults[0].Units[mEntry].Changes.Changes, mResults[1].Units[mEntry].Changes.Changes);
      Assert.AreEqual(Integer(Length(mResults[0].Units[mEntry].Changes.Authors)),
        Integer(Length(mResults[1].Units[mEntry].Changes.Authors)));
      Assert.AreEqual(mResults[0].Units[mEntry].Complexity, mResults[1].Units[mEntry].Complexity);
      Assert.AreEqual(mResults[0].Units[mEntry].Score, mResults[1].Units[mEntry].Score, 1E-12);
    end;
    Assert.AreEqual(Integer(Length(mResults[0].Coupling)), Integer(Length(mResults[1].Coupling)));
    Assert.AreEqual(1, Integer(Length(mResults[1].Coupling)), 'A–C');
    Assert.AreEqual(mResults[0].Coupling[0].Shared, mResults[1].Coupling[0].Shared);
    Assert.AreEqual(-1, mResults[1].Units[0].Changes.Added, 'svn log kennt keine Zeilen');
  finally
    mService.Free;
    mTexts.Free;
  end;
end;

procedure THotspotServiceTests.RequestFromSettings;
var
  mSettings: TServerSettings;
  mRequest, mOther: THotspotRequest;
begin
  mSettings := TServerSettings.Default;
  Assert.IsTrue(mSettings.HotspotsEnabled);
  Assert.AreEqual(12, mSettings.HotspotsMonths);
  Assert.AreEqual(5, mSettings.HotspotsCouplingMinCommits);
  mSettings.HotspotsMonths := 6;
  mSettings.HotspotsCouplingMinCommits := 9;
  mSettings.ArchitectureExclude := ['Tests/**'];
  mRequest := THotspotRequest.FromSettings(mSettings);
  Assert.AreEqual(6, mRequest.Options.Months);
  Assert.AreEqual(9, mRequest.Options.MinSharedCommits);
  Assert.AreEqual('Tests/**', mRequest.Exclude[0]);
  Assert.AreNotEqual(mRequest.Key, THotspotRequest.FromSettings(TServerSettings.Default).Key);
  mRequest.Files := ['C:\B.pas', 'C:\A.pas'];
  mOther := mRequest;
  mOther.Files := ['c:\a.pas', 'C:\B.pas'];
  Assert.AreEqual(mRequest.Key, mOther.Key, 'Reihenfolge und Schreibweise der Dateien egal');
end;

procedure THotspotServiceTests.FiveThousandCommitsThousandUnits;
var
  mIndex: ISymbolIndex;
  mTexts: TTexts;
  mService: THotspotService;
  mVcs: THotspotFakeVcs;
  mVcsRef: IHotspotVcs;
  mRequest: THotspotRequest;
  mResult: THotspotResult;
  mUnit, mCommit: Integer;
  mName: string;
  mPaths: TArray<string>;
  mWatch: TStopwatch;
begin
  mIndex := TSymbolIndex.Create;
  mTexts := TTexts.Create;
  mVcs := THotspotFakeVcs.Create(THotspotVcsKind.Git, 'C:\Projekt');
  mVcsRef := mVcs;
  mService := NewService(mIndex, mTexts);
  try
    for mUnit := 0 to 999 do
    begin
      mName := 'App.Teil' + IntToStr(mUnit div 50) + '.Unit' + IntToStr(mUnit);
      if mUnit mod 10 = 0 then
        mIndex.AddUnit(UsesUnit(mName, ['App.Teil0.Unit0'], nil))
      else
        mIndex.AddUnit(UsesUnit(mName, nil, nil));
      mTexts.Put(mName, 1 + mUnit mod 15);
    end;
    // 5000 Commits über ein Jahr mit je 1–8 Dateien.
    for mCommit := 0 to 4999 do
    begin
      mPaths := nil;
      for mUnit := 0 to mCommit mod 8 do
        mPaths := mPaths + [PathOf('App.Teil' + IntToStr(((mCommit * 7 + mUnit * 13) mod 1000) div 50) + '.Unit' +
          IntToStr((mCommit * 7 + mUnit * 13) mod 1000))];
      mVcs.AddCommit(IntToStr(5000 - mCommit), 'autor' + IntToStr(mCommit mod 9),
        IncMinute(HotspotNow, -mCommit * 100), mPaths);
    end;
    mRequest := NewRequest;
    mRequest.Level := THotspotLevel.Methods;
    mWatch := TStopwatch.StartNew;
    mResult := mService.Analyze(mRequest, mVcsRef, HotspotNow);
    mWatch.Stop;
    Assert.AreEqual(5000, mResult.Commits);
    Assert.IsTrue(Length(mResult.Units) > 900);
    Assert.AreEqual(50, Integer(Length(mResult.Methods)));
    Assert.IsTrue(mWatch.ElapsedMilliseconds < 30000, Format('%d ms', [mWatch.ElapsedMilliseconds]));
  finally
    mService.Free;
    mTexts.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(THotspotServiceTests);

end.
