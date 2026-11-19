unit Atlas.Common.History.Service.Tests;

// Tests der Symbolgeschichte (#2641) mit einer Versionsverwaltung im Speicher: Zeilengeschichte mit Issues,
// Umbenennen, Verschieben in eine andere Unit, ein ähnlicher fremder Rumpf, Grenzen (limit, Abbruch), Speicher je
// Stand, SVN ohne Verfolgen und das Finden einer Routine im Text.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.History.Contract;

type
  /// <summary>Versionsverwaltung im Speicher: Zeilengeschichte je Pfad und Stand, Dateien je Commit, Texte je Pfad,
  /// Stand und davor.</summary>
  TSymbolFakeVcs = class(TInterfacedObject, ISymbolHistoryVcs)
  private
    FKind: THotspotVcsKind;
    FHead: string;
    FLogs: TDictionary<string, TArray<TSymbolLineCommit>>;
    FFiles: TDictionary<string, TArray<THotspotFileChange>>;
    FTexts: TDictionary<string, string>;
    FLineLogs: Integer;
    FRanges: TList<string>;
  public
    constructor Create(AKind: THotspotVcsKind);
    destructor Destroy; override;
    procedure AddLog(const APath, ARevision: string; const ACommits: TArray<TSymbolLineCommit>);
    procedure AddFiles(const ARevision: string; const AFiles: TArray<THotspotFileChange>);
    procedure AddText(const APath, ARevision: string; ABefore: Boolean; const AText: string);
    function Kind: THotspotVcsKind;
    function Root: string;
    function Head: string;
    function LineLog(const APath, ARevision: string; AFirstLine, ALastLine, AMaxCount: Integer;
      out ACommits: TArray<TSymbolLineCommit>): Boolean;
    function CommitFiles(const ARevision: string; out AFiles: TArray<THotspotFileChange>): Boolean;
    function TextAt(const APath, ARevision: string; ABefore: Boolean; out AText: string): THotspotTextState;
    property HeadRevision: string read FHead write FHead;
    property LineLogs: Integer read FLineLogs;
    /// <summary>Abfragen von LineLog als "Pfad|Stand|von|bis".</summary>
    property Ranges: TList<string> read FRanges;
  end;

  [TestFixture]
  TSymbolHistoryServiceTests = class
  private
    FVcs: TSymbolFakeVcs;
    FVcsRef: ISymbolHistoryVcs;
    function Request(const ASymbol, APath: string; AFirst, ALast: Integer): TSymbolHistoryRequest;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure LineHistoryWithIssuesAndIntroduction;
    [Test]
    procedure FollowsRename;
    [Test]
    procedure FollowsMoveToOtherUnit;
    [Test]
    procedure ReorderWithinUnitIsAChange;
    [Test]
    procedure ForeignSimilarBodyIsNoPredecessor;
    [Test]
    procedure WithoutFollowMovesStopsAtIntroduction;
    [Test]
    procedure LimitStopsAndIsNamed;
    [Test]
    procedure CancelStopsBeforeVcs;
    [Test]
    procedure RemembersResultPerHead;
    [Test]
    procedure SvnDoesNotFollowMoves;
    [Test]
    procedure NoCommitsMeansNoHistory;
    [Test]
    procedure FindsRoutineLines;
  end;

/// <summary>Commit der Zeilengeschichte mit Unterschied APatch.</summary>
function LineCommit(const ARevision, AMessage: string; const APatch: TArray<string>): TSymbolLineCommit;
/// <summary>Unterschied, der Zeilen AFirst..AFirst+ACount-1 von APath anlegt.</summary>
function IntroPatch(const APath: string; AFirst, ACount: Integer): TArray<string>;
/// <summary>Unterschied, der eine Zeile von APath ändert.</summary>
function ChangePatch(const APath: string): TArray<string>;
/// <summary>Unit mit der Routine AName (Zeilen 4–15) und einer Schleife im Rumpf.</summary>
function UnitWith(const AUnit, AName: string): string;

implementation

uses
  System.DateUtils,
  Atlas.Common.History.Service;

function LineCommit(const ARevision, AMessage: string; const APatch: TArray<string>): TSymbolLineCommit;
begin
  Result.Revision := ARevision;
  Result.Author := 'anna';
  Result.Date := EncodeDateTime(2026, 11, 1, 12, 0, 0, 0);
  Result.Message := AMessage;
  Result.Patch := APatch;
end;

function IntroPatch(const APath: string; AFirst, ACount: Integer): TArray<string>;
var
  mIndex: Integer;
begin
  Result := TArray<string>.Create('diff --git a/' + APath + ' b/' + APath, '--- a/' + APath, '+++ b/' + APath,
    Format('@@ -0,0 +%d,%d @@', [AFirst, ACount]));
  for mIndex := 1 to ACount do
  begin
    Result := Result + ['+zeile'];
  end;
end;

function ChangePatch(const APath: string): TArray<string>;
begin
  Result := TArray<string>.Create('diff --git a/' + APath + ' b/' + APath, '--- a/' + APath, '+++ b/' + APath,
    '@@ -8,1 +8,2 @@', '-alt', '+neu', '+neu');
end;

function UnitWith(const AUnit, AName: string): string;
begin
  Result :=
    'unit ' + AUnit + ';'#10 +                    // 1
    'interface'#10 +                              // 2
    'implementation'#10 +                         // 3
    'procedure ' + AName + '(AWert: Integer);'#10 + // 4
    'var'#10 +                                    // 5
    '  mSumme: Integer;'#10 +                     // 6
    'begin'#10 +                                  // 7
    '  mSumme := 0;'#10 +                         // 8
    '  while AWert > 0 do'#10 +                   // 9
    '  begin'#10 +                                // 10
    '    mSumme := mSumme + AWert;'#10 +          // 11
    '    Dec(AWert);'#10 +                        // 12
    '  end;'#10 +                                 // 13
    '  Ausgabe(mSumme);'#10 +                     // 14
    'end;'#10 +                                   // 15
    'end.';
end;

/// <summary>Unit ohne Routinen.</summary>
function EmptyUnit(const AUnit: string): string;
begin
  Result := 'unit ' + AUnit + ';'#10'interface'#10'implementation'#10'end.';
end;

{ TSymbolFakeVcs }

constructor TSymbolFakeVcs.Create(AKind: THotspotVcsKind);
begin
  inherited Create;
  FKind := AKind;
  FHead := 'kopf1';
  FLogs := TDictionary<string, TArray<TSymbolLineCommit>>.Create;
  FFiles := TDictionary<string, TArray<THotspotFileChange>>.Create;
  FTexts := TDictionary<string, string>.Create;
  FRanges := TList<string>.Create;
end;

destructor TSymbolFakeVcs.Destroy;
begin
  FRanges.Free;
  FTexts.Free;
  FFiles.Free;
  FLogs.Free;
  inherited Destroy;
end;

procedure TSymbolFakeVcs.AddLog(const APath, ARevision: string; const ACommits: TArray<TSymbolLineCommit>);
begin
  FLogs.AddOrSetValue(APath + '|' + ARevision, ACommits);
end;

procedure TSymbolFakeVcs.AddFiles(const ARevision: string; const AFiles: TArray<THotspotFileChange>);
begin
  FFiles.AddOrSetValue(ARevision, AFiles);
end;

procedure TSymbolFakeVcs.AddText(const APath, ARevision: string; ABefore: Boolean; const AText: string);
begin
  FTexts.AddOrSetValue(APath + '|' + ARevision + '|' + BoolToStr(ABefore, True), AText);
end;

function TSymbolFakeVcs.Kind: THotspotVcsKind;
begin
  Result := FKind;
end;

function TSymbolFakeVcs.Root: string;
begin
  Result := 'C:\P';
end;

function TSymbolFakeVcs.Head: string;
begin
  Result := FHead;
end;

function TSymbolFakeVcs.LineLog(const APath, ARevision: string; AFirstLine, ALastLine, AMaxCount: Integer;
  out ACommits: TArray<TSymbolLineCommit>): Boolean;
var
  mAll: TArray<TSymbolLineCommit>;
begin
  Inc(FLineLogs);
  FRanges.Add(Format('%s|%s|%d|%d', [APath, ARevision, AFirstLine, ALastLine]));
  if not FLogs.TryGetValue(APath + '|' + ARevision, mAll) then
  begin
    mAll := nil;
  end;
  ACommits := Copy(mAll, 0, AMaxCount);
  Result := True;
end;

function TSymbolFakeVcs.CommitFiles(const ARevision: string; out AFiles: TArray<THotspotFileChange>): Boolean;
var
  mFiles: TArray<THotspotFileChange>;
begin
  Result := FFiles.TryGetValue(ARevision, mFiles);
  AFiles := nil;
  if Result then
  begin
    AFiles := mFiles;
  end;
end;

function TSymbolFakeVcs.TextAt(const APath, ARevision: string; ABefore: Boolean; out AText: string):
  THotspotTextState;
var
  mText: string;
begin
  AText := '';
  if FTexts.TryGetValue(APath + '|' + ARevision + '|' + BoolToStr(ABefore, True), mText) then
  begin
    AText := mText;
    Exit(THotspotTextState.Found);
  end;
  Result := THotspotTextState.Missing;
end;

{ TSymbolHistoryServiceTests }

procedure TSymbolHistoryServiceTests.Setup;
begin
  FVcs := TSymbolFakeVcs.Create(THotspotVcsKind.Git);
  FVcsRef := FVcs;
end;

procedure TSymbolHistoryServiceTests.TearDown;
begin
  FVcs := nil;
  FVcsRef := nil;
end;

function TSymbolHistoryServiceTests.Request(const ASymbol, APath: string; AFirst,
  ALast: Integer): TSymbolHistoryRequest;
begin
  Result := Default(TSymbolHistoryRequest);
  Result.Symbol := ASymbol;
  Result.Path := APath;
  Result.FirstLine := AFirst;
  Result.LastLine := ALast;
  Result.IsRoutine := True;
  Result.Limit := 20;
  Result.FollowMoves := True;
end;

/// <summary>Neu (c3 geändert, c2 aus Alt umbenannt), Alt (c1 eingeführt).</summary>
procedure AddRename(AVcs: TSymbolFakeVcs);
begin
  AVcs.AddLog('A.pas', '', [LineCommit('c3', 'Summe schneller (#12)', ChangePatch('A.pas')),
    LineCommit('c2', 'ABC-7 Umbenannt', IntroPatch('A.pas', 4, 12))]);
  AVcs.AddFiles('c2', [THotspotFileChange.Make('A.pas', '', THotspotChangeKind.Modified, -1, -1)]);
  AVcs.AddText('A.pas', 'c2', False, UnitWith('A', 'TFoo.Neu'));
  AVcs.AddText('A.pas', 'c2', True, UnitWith('A', 'TFoo.Alt'));
  AVcs.AddLog('A.pas', 'c2^', [LineCommit('c1', 'Summe eingeführt (owner/repo#5)', IntroPatch('A.pas', 4, 12))]);
end;

procedure TSymbolHistoryServiceTests.LineHistoryWithIssuesAndIntroduction;
var
  mService: ISymbolHistoryService;
  mResult: TSymbolHistoryResult;
begin
  FVcs.AddLog('A.pas', '', [LineCommit('c3', 'Summe schneller (#12)', ChangePatch('A.pas')),
    LineCommit('c2', 'ABC-7 Eingeführt', IntroPatch('A.pas', 4, 12))]);
  mService := TSymbolHistoryService.Create;
  mResult := mService.Run(FVcsRef, Request('TFoo.Neu', 'A.pas', 4, 15));
  Assert.AreEqual(2, Integer(Length(mResult.Events)));
  Assert.AreEqual('A.pas||4|15', FVcs.Ranges[0]);
  Assert.AreEqual('A.pas', mResult.Events[0].Path);
  Assert.AreEqual<TSymbolEventKind>(TSymbolEventKind.Changed, mResult.Events[0].Kind);
  Assert.AreEqual(2, mResult.Events[0].Added);
  Assert.AreEqual(1, mResult.Events[0].Deleted);
  Assert.AreEqual('#12', string.Join(',', mResult.Events[0].Issues));
  Assert.AreEqual('Summe schneller (#12)', mResult.Events[0].Summary);
  Assert.AreEqual<TSymbolEventKind>(TSymbolEventKind.Introduced, mResult.Events[1].Kind);
  Assert.AreEqual('ABC-7', string.Join(',', mResult.Events[1].Issues));
  Assert.AreEqual<TSymbolHistoryStop>(TSymbolHistoryStop.None, mResult.Stop);
  Assert.AreEqual('kopf1', mResult.Head);
end;

procedure TSymbolHistoryServiceTests.FollowsRename;
var
  mService: ISymbolHistoryService;
  mResult: TSymbolHistoryResult;
begin
  AddRename(FVcs);
  mService := TSymbolHistoryService.Create;
  mResult := mService.Run(FVcsRef, Request('TFoo.Neu', 'A.pas', 4, 15));
  Assert.AreEqual(3, Integer(Length(mResult.Events)));
  Assert.AreEqual<TSymbolEventKind>(TSymbolEventKind.Renamed, mResult.Events[1].Kind, 'c2 umbenannt');
  Assert.AreEqual('TFoo.Alt', mResult.Events[1].FromSymbol);
  Assert.AreEqual('A.pas', mResult.Events[1].FromPath);
  Assert.IsTrue(mResult.Events[1].Similarity > 0.99);
  Assert.AreEqual<TSymbolEventKind>(TSymbolEventKind.Introduced, mResult.Events[2].Kind, 'c1 eingeführt');
  Assert.AreEqual('TFoo.Alt', mResult.Events[2].Symbol);
  Assert.AreEqual('owner/repo#5', string.Join(',', mResult.Events[2].Issues));
  Assert.AreEqual('A.pas|c2^|4|15', FVcs.Ranges[1], 'Suche geht beim Vorgänger im Stand davor weiter');
  Assert.AreEqual<TSymbolHistoryStop>(TSymbolHistoryStop.None, mResult.Stop);
end;

procedure TSymbolHistoryServiceTests.FollowsMoveToOtherUnit;
var
  mService: ISymbolHistoryService;
  mResult: TSymbolHistoryResult;
begin
  FVcs.AddLog('A.pas', '', [LineCommit('c2', 'Verschoben', IntroPatch('A.pas', 4, 12))]);
  FVcs.AddFiles('c2', [THotspotFileChange.Make('A.pas', '', THotspotChangeKind.Modified, -1, -1),
    THotspotFileChange.Make('B.pas', '', THotspotChangeKind.Modified, -1, -1)]);
  FVcs.AddText('A.pas', 'c2', False, UnitWith('A', 'TFoo.Rechne'));
  FVcs.AddText('A.pas', 'c2', True, EmptyUnit('A'));
  FVcs.AddText('B.pas', 'c2', False, EmptyUnit('B'));
  FVcs.AddText('B.pas', 'c2', True, UnitWith('B', 'TFoo.Rechne'));
  FVcs.AddLog('B.pas', 'c2^', [LineCommit('c1', 'Eingeführt', IntroPatch('B.pas', 4, 12))]);
  mService := TSymbolHistoryService.Create;
  mResult := mService.Run(FVcsRef, Request('TFoo.Rechne', 'A.pas', 4, 15));
  Assert.AreEqual(2, Integer(Length(mResult.Events)));
  Assert.AreEqual<TSymbolEventKind>(TSymbolEventKind.Moved, mResult.Events[0].Kind);
  Assert.AreEqual('B.pas', mResult.Events[0].FromPath);
  Assert.AreEqual('TFoo.Rechne', mResult.Events[0].FromSymbol);
  Assert.AreEqual('B.pas', mResult.Events[1].Path);
  Assert.AreEqual<TSymbolEventKind>(TSymbolEventKind.Introduced, mResult.Events[1].Kind);
end;

procedure TSymbolHistoryServiceTests.ReorderWithinUnitIsAChange;
var
  mService: ISymbolHistoryService;
  mResult: TSymbolHistoryResult;
begin
  // c2 rückt die Routine in A.pas nach unten: git log -L sieht eingefügte Zeilen, die Routine gab es schon.
  FVcs.AddLog('A.pas', '', [LineCommit('c2', 'Methodenordnung', IntroPatch('A.pas', 4, 12))]);
  FVcs.AddFiles('c2', [THotspotFileChange.Make('A.pas', '', THotspotChangeKind.Modified, -1, -1)]);
  FVcs.AddText('A.pas', 'c2', False, UnitWith('A', 'TFoo.Neu'));
  FVcs.AddText('A.pas', 'c2', True, UnitWith('A', 'TFoo.Neu').Replace('implementation'#10,
    'implementation'#10'procedure Davor;'#10'begin'#10'end;'#10));
  FVcs.AddLog('A.pas', 'c2^', [LineCommit('c1', 'Eingeführt', IntroPatch('A.pas', 7, 12))]);
  mService := TSymbolHistoryService.Create;
  mResult := mService.Run(FVcsRef, Request('TFoo.Neu', 'A.pas', 4, 15));
  Assert.AreEqual(2, Integer(Length(mResult.Events)));
  Assert.AreEqual<TSymbolEventKind>(TSymbolEventKind.Changed, mResult.Events[0].Kind, 'nur gerückt');
  Assert.AreEqual('', mResult.Events[0].FromSymbol);
  Assert.AreEqual('A.pas|c2^|7|18', FVcs.Ranges[1]);
  Assert.AreEqual<TSymbolEventKind>(TSymbolEventKind.Introduced, mResult.Events[1].Kind);
end;

procedure TSymbolHistoryServiceTests.ForeignSimilarBodyIsNoPredecessor;
var
  mService: ISymbolHistoryService;
  mResult: TSymbolHistoryResult;
  mOld: string;
begin
  FVcs.AddLog('A.pas', '', [LineCommit('c2', 'Neu', IntroPatch('A.pas', 4, 12))]);
  FVcs.AddFiles('c2', [THotspotFileChange.Make('A.pas', '', THotspotChangeKind.Modified, -1, -1)]);
  FVcs.AddText('A.pas', 'c2', False, UnitWith('A', 'TFoo.Neu'));
  // Gleicher Anfang, aber eine Anweisung mehr in der Schleife und ein anderer Abschluss: fremd.
  mOld := UnitWith('A', 'TFoo.Anders').Replace('    Dec(AWert);', '    Dec(AWert);'#10'    Pruefe(mSumme, 1);')
    .Replace('  Ausgabe(mSumme);', '  if mSumme > 10 then'#10'    Melde(mSumme);');
  FVcs.AddText('A.pas', 'c2', True, mOld);
  mService := TSymbolHistoryService.Create;
  mResult := mService.Run(FVcsRef, Request('TFoo.Neu', 'A.pas', 4, 15));
  Assert.AreEqual(1, Integer(Length(mResult.Events)));
  Assert.AreEqual<TSymbolEventKind>(TSymbolEventKind.Introduced, mResult.Events[0].Kind);
  Assert.AreEqual(1, FVcs.LineLogs);
end;

procedure TSymbolHistoryServiceTests.WithoutFollowMovesStopsAtIntroduction;
var
  mService: ISymbolHistoryService;
  mResult: TSymbolHistoryResult;
  mRequest: TSymbolHistoryRequest;
begin
  AddRename(FVcs);
  mRequest := Request('TFoo.Neu', 'A.pas', 4, 15);
  mRequest.FollowMoves := False;
  mService := TSymbolHistoryService.Create;
  mResult := mService.Run(FVcsRef, mRequest);
  Assert.AreEqual(2, Integer(Length(mResult.Events)));
  Assert.AreEqual<TSymbolEventKind>(TSymbolEventKind.Introduced, mResult.Events[1].Kind);
  Assert.IsFalse(mResult.FollowedMoves);
end;

procedure TSymbolHistoryServiceTests.LimitStopsAndIsNamed;
var
  mService: ISymbolHistoryService;
  mResult: TSymbolHistoryResult;
  mRequest: TSymbolHistoryRequest;
begin
  FVcs.AddLog('A.pas', '', [LineCommit('c3', 'a', ChangePatch('A.pas')), LineCommit('c2', 'b', ChangePatch('A.pas')),
    LineCommit('c1', 'c', IntroPatch('A.pas', 4, 12))]);
  mRequest := Request('TFoo.Neu', 'A.pas', 4, 15);
  mRequest.Limit := 2;
  mService := TSymbolHistoryService.Create;
  mResult := mService.Run(FVcsRef, mRequest);
  Assert.AreEqual(2, Integer(Length(mResult.Events)));
  Assert.AreEqual<TSymbolHistoryStop>(TSymbolHistoryStop.Limit, mResult.Stop);
end;

procedure TSymbolHistoryServiceTests.CancelStopsBeforeVcs;
var
  mService: ISymbolHistoryService;
  mResult: TSymbolHistoryResult;
  mRequest: TSymbolHistoryRequest;
begin
  AddRename(FVcs);
  mRequest := Request('TFoo.Neu', 'A.pas', 4, 15);
  mRequest.Cancelled :=
    function: Boolean
    begin
      Result := True;
    end;
  mService := TSymbolHistoryService.Create;
  mResult := mService.Run(FVcsRef, mRequest);
  Assert.AreEqual(0, mService.CachedCount, 'abgebrochene Läufe nicht merken');
  Assert.AreEqual<TSymbolHistoryStop>(TSymbolHistoryStop.Cancelled, mResult.Stop);
  Assert.AreEqual(0, FVcs.LineLogs);
end;

procedure TSymbolHistoryServiceTests.RemembersResultPerHead;
var
  mService: ISymbolHistoryService;
  mResult: TSymbolHistoryResult;
begin
  AddRename(FVcs);
  mService := TSymbolHistoryService.Create;
  mResult := mService.Run(FVcsRef, Request('TFoo.Neu', 'A.pas', 4, 15));
  Assert.IsFalse(mResult.Cached);
  mResult := mService.Run(FVcsRef, Request('TFoo.Neu', 'A.pas', 4, 15));
  Assert.IsTrue(mResult.Cached);
  Assert.AreEqual(2, FVcs.LineLogs, 'zweiter Aufruf aus dem Speicher');
  FVcs.HeadRevision := 'kopf2';
  mResult := mService.Run(FVcsRef, Request('TFoo.Neu', 'A.pas', 4, 15));
  Assert.IsFalse(mResult.Cached, 'neuer Stand rechnet neu');
  Assert.AreEqual(1, mService.CachedCount);
end;

procedure TSymbolHistoryServiceTests.SvnDoesNotFollowMoves;
var
  mService: ISymbolHistoryService;
  mResult: TSymbolHistoryResult;
  mSvn: TSymbolFakeVcs;
  mSvnRef: ISymbolHistoryVcs;
begin
  mSvn := TSymbolFakeVcs.Create(THotspotVcsKind.Svn);
  mSvnRef := mSvn;
  AddRename(mSvn);
  mService := TSymbolHistoryService.Create;
  mResult := mService.Run(mSvnRef, Request('TFoo.Neu', 'A.pas', 4, 15));
  Assert.IsFalse(mResult.FollowedMoves);
  Assert.AreEqual(2, Integer(Length(mResult.Events)));
  Assert.AreEqual(1, mSvn.LineLogs);
end;

procedure TSymbolHistoryServiceTests.NoCommitsMeansNoHistory;
var
  mService: ISymbolHistoryService;
  mResult: TSymbolHistoryResult;
begin
  mService := TSymbolHistoryService.Create;
  mResult := mService.Run(FVcsRef, Request('TFoo.Neu', 'A.pas', 4, 15));
  Assert.AreEqual(0, Integer(Length(mResult.Events)));
  Assert.AreEqual<TSymbolHistoryStop>(TSymbolHistoryStop.NoHistory, mResult.Stop);
end;

procedure TSymbolHistoryServiceTests.FindsRoutineLines;
var
  mFirst, mLast: Integer;
  mText: string;
begin
  Assert.IsTrue(TSymbolHistoryService.FindRoutine(UnitWith('A', 'TFoo.Neu'), 'tfoo.neu', mFirst, mLast));
  Assert.AreEqual(4, mFirst);
  Assert.AreEqual(15, mLast);
  mText := UnitWith('A', 'TListe<T>.Neu');
  Assert.IsTrue(TSymbolHistoryService.FindRoutine(mText, 'TListe.Neu', mFirst, mLast), 'ohne Typparameter');
  Assert.IsFalse(TSymbolHistoryService.FindRoutine(mText, 'TListe.Alt', mFirst, mLast));
end;

initialization
  TDUnitX.RegisterTestFixture(TSymbolHistoryServiceTests);

end.
