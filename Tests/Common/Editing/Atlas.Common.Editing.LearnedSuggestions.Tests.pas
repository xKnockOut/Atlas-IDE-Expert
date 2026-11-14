unit Atlas.Common.Editing.LearnedSuggestions.Tests;

// Tests der gelernten Vorschläge (#1890): Schwellen (Anzahl, Anteil),
// Rangfolge (genauer Schlüssel vor allgemeinem), Lernzähler über Adjust,
// Muster aus atlas.json, Prüfung über Parser und Namen, Einrückung und
// Schreibmarke, Liste der Muster und ein Benchmark über das Referenzprojekt.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLearnedSuggestionsTests = class
  private
    FUnits: TArray<TUnitIndex>;
    procedure AddUnits(ACount: Integer; const ABody: string);
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TryFinallyAfterConstructor;
    [Test]
    procedure TooFewPlacesNoSuggestion;
    [Test]
    procedure ShareBelowThresholdNoSuggestion;
    [Test]
    procedure AdjustLowersAndRaises;
    [Test]
    procedure UnknownIdentifierRejected;
    [Test]
    procedure SyntaxErrorRejected;
    [Test]
    procedure ExistingTryNoSuggestion;
    [Test]
    procedure SpecificKeyBeforeGeneral;
    [Test]
    procedure TeamPatternWithoutProject;
    [Test]
    procedure WhileLoopAfterOpen;
    [Test]
    procedure TabsAndCursorWithoutBody;
    [Test]
    procedure LibraryUnitsIgnored;
    [Test]
    procedure ListSortedWithTeamFirst;
    [Test]
    [Category('Benchmark')]
    procedure GatherOverReferenceProject;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Diagnostics,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.Extractor.Patterns,
  Atlas.Common.Editing.LearnedSuggestions;

function UnitWith(const AName, ABody: string): string;
begin
  Result := 'unit ' + AName + ';'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 + ABody + 'end;'#10 +
    'end.';
end;

const
  cTryFree = '  X := TFoo.Create;'#10'  try'#10'    X.Add(1);'#10'  finally'#10'    X.Free;'#10'  end;'#10;
  cNoTry = '  X := TFoo.Create;'#10'  X.Add(1);'#10;

procedure TLearnedSuggestionsTests.TearDown;
begin
  FUnits := nil;
end;

procedure TLearnedSuggestionsTests.AddUnits(ACount: Integer; const ABody: string);
var
  mIndex, mNumber: Integer;
begin
  for mIndex := 1 to ACount do
  begin
    mNumber := Length(FUnits) + 1;
    FUnits := FUnits + [TIndexExtractor.ExtractText(UnitWith('U' + IntToStr(mNumber), ABody),
      'C:\P\U' + IntToStr(mNumber) + '.pas', nil, nil, False, True)];
  end;
end;

/// <summary>Bekannt sind nur die Namen in ANames.</summary>
function KnownOnly(const ANames: array of string): TLearnedNameCheck;
var
  mNames: TArray<string>;
  mIndex: Integer;
begin
  SetLength(mNames, Length(ANames));
  for mIndex := 0 to High(ANames) do
  begin
    mNames[mIndex] := ANames[mIndex];
  end;
  Result :=
    function(const AName: string): Boolean
    var
      mName: string;
    begin
      Result := False;
      for mName in mNames do
      begin
        Result := Result or SameText(mName, AName);
      end;
    end;
end;

/// <summary>Vorschlag für die Zeile ALine von AText.</summary>
function SuggestIn(const AText: string; ALine: Integer; const AUnits: TArray<TUnitIndex>;
  const AOptions: TLearnedOptions; const AKnown: TLearnedNameCheck; out ASuggestion: TLearnedSuggestion): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Result := TLearnedSuggestions.Suggest(mTree, AText, ALine, TLearnedProject.Create(AUnits, AKnown), AOptions,
      ASuggestion);
  finally
    mTree.Free;
  end;
end;

const
  // Zeile 5 ist die leere Zeile nach dem Auslöser.
  cDocument = 'unit D;'#10'interface'#10'implementation'#10'procedure Q;'#10'begin'#10'  Y := TBar.Create;'#10 +
    #10'end;'#10'end.';

procedure TLearnedSuggestionsTests.TryFinallyAfterConstructor;
var
  mSuggestion: TLearnedSuggestion;
begin
  AddUnits(5, cTryFree);
  Assert.IsTrue(SuggestIn(cDocument, 6, FUnits, TLearnedOptions.Default, KnownOnly(['Free']), mSuggestion));
  Assert.AreEqual('  try|    |  finally|    Y.Free;|  end;', string.Join('|', mSuggestion.Lines));
  Assert.AreEqual(1, mSuggestion.CursorLine);
  Assert.AreEqual(4, mSuggestion.CursorCharacter);
  Assert.AreEqual(5, mSuggestion.Pattern.Count);
  Assert.AreEqual(5, mSuggestion.Pattern.Total);
  Assert.AreEqual(100, mSuggestion.Pattern.Share);
  Assert.AreEqual(3, Integer(Length(mSuggestion.Pattern.Evidence)));
  Assert.AreEqual('C:\P\U1.pas', mSuggestion.Pattern.Evidence[0].FileName);
  Assert.AreEqual(5, mSuggestion.Pattern.Evidence[0].Line);
end;

procedure TLearnedSuggestionsTests.TooFewPlacesNoSuggestion;
var
  mSuggestion: TLearnedSuggestion;
begin
  AddUnits(2, cTryFree);
  Assert.IsFalse(SuggestIn(cDocument, 6, FUnits, TLearnedOptions.Default, KnownOnly(['Free']), mSuggestion));
end;

procedure TLearnedSuggestionsTests.ShareBelowThresholdNoSuggestion;
var
  mSuggestion: TLearnedSuggestion;
begin
  AddUnits(5, cTryFree);
  AddUnits(5, cNoTry);
  Assert.IsFalse(SuggestIn(cDocument, 6, FUnits, TLearnedOptions.Default, KnownOnly(['Free']), mSuggestion),
    '50 % unter 70 %');
end;

procedure TLearnedSuggestionsTests.AdjustLowersAndRaises;
var
  mSuggestion: TLearnedSuggestion;
  mOptions: TLearnedOptions;
  mId: string;
begin
  AddUnits(5, cTryFree);
  Assert.IsTrue(SuggestIn(cDocument, 6, FUnits, TLearnedOptions.Default, KnownOnly(['Free']), mSuggestion));
  mId := mSuggestion.Pattern.Id;
  mOptions := TLearnedOptions.Default;
  mOptions.AdjustIds := [mId];
  mOptions.AdjustBy := [-50];
  Assert.IsFalse(SuggestIn(cDocument, 6, FUnits, mOptions, KnownOnly(['Free']), mSuggestion), 'oft verworfen');
  AddUnits(5, cNoTry);
  mOptions.AdjustBy := [30];
  Assert.IsTrue(SuggestIn(cDocument, 6, FUnits, mOptions, KnownOnly(['Free']), mSuggestion), 'oft übernommen');
  Assert.AreEqual(50, mSuggestion.Pattern.Share);
end;

procedure TLearnedSuggestionsTests.UnknownIdentifierRejected;
var
  mSuggestion: TLearnedSuggestion;
begin
  AddUnits(5, cTryFree);
  Assert.IsFalse(SuggestIn(cDocument, 6, FUnits, TLearnedOptions.Default, KnownOnly([]), mSuggestion));
end;

procedure TLearnedSuggestionsTests.SyntaxErrorRejected;
var
  mSuggestion: TLearnedSuggestion;
  mOptions: TLearnedOptions;
  mTeam: TSuggestionPattern;
begin
  mTeam.After := '$S := $T.Create';
  mTeam.Insert := ['try', '  $|'];
  mOptions := TLearnedOptions.Default;
  mOptions.Team := [mTeam];
  Assert.IsFalse(SuggestIn(cDocument, 6, nil, mOptions, KnownOnly([]), mSuggestion));
end;

procedure TLearnedSuggestionsTests.ExistingTryNoSuggestion;
var
  mSuggestion: TLearnedSuggestion;
begin
  AddUnits(5, cTryFree);
  Assert.IsFalse(SuggestIn('unit D;'#10'interface'#10'implementation'#10'procedure Q;'#10'begin'#10 +
    '  Y := TBar.Create;'#10#10'  try'#10'  finally'#10'    Y.Free;'#10'  end;'#10'end;'#10'end.', 6, FUnits,
    TLearnedOptions.Default, KnownOnly(['Free']), mSuggestion));
end;

procedure TLearnedSuggestionsTests.SpecificKeyBeforeGeneral;
var
  mSuggestion: TLearnedSuggestion;
begin
  AddUnits(5, cTryFree);
  AddUnits(5, '  X := TBar.Create;'#10'  try'#10'  finally'#10'    FreeAndNil(X);'#10'  end;'#10);
  Assert.IsTrue(SuggestIn(cDocument, 6, FUnits, TLearnedOptions.Default, KnownOnly(['FreeAndNil', 'Free']),
    mSuggestion));
  Assert.AreEqual('    FreeAndNil(Y);', mSuggestion.Lines[3]);
  Assert.AreEqual('$S := TBar.Create', mSuggestion.Pattern.Trigger);
end;

procedure TLearnedSuggestionsTests.TeamPatternWithoutProject;
var
  mSuggestion: TLearnedSuggestion;
  mOptions: TLearnedOptions;
  mTeam: TSuggestionPattern;
begin
  mTeam.After := 'Log.Enter';
  mTeam.Insert := ['try', '  $|', 'finally', '  Log.Leave;', 'end;'];
  mOptions := TLearnedOptions.Default;
  mOptions.Team := [mTeam];
  Assert.IsTrue(SuggestIn('unit D;'#10'interface'#10'implementation'#10'procedure Q;'#10'begin'#10 +
    '  Log.Enter(''Q'');'#10#10'end;'#10'end.', 6, nil, mOptions, KnownOnly(['Leave']), mSuggestion));
  Assert.IsTrue(mSuggestion.Pattern.Team);
  Assert.AreEqual('  try|    |  finally|    Log.Leave;|  end;', string.Join('|', mSuggestion.Lines));
  mOptions.AdjustIds := [mSuggestion.Pattern.Id];
  mOptions.AdjustBy := [-40];
  Assert.IsFalse(SuggestIn('unit D;'#10'interface'#10'implementation'#10'procedure Q;'#10'begin'#10 +
    '  Log.Enter(''Q'');'#10#10'end;'#10'end.', 6, nil, mOptions, KnownOnly(['Leave']), mSuggestion),
    'abgewählt bzw. oft verworfen');
end;

procedure TLearnedSuggestionsTests.WhileLoopAfterOpen;
var
  mSuggestion: TLearnedSuggestion;
begin
  AddUnits(5, '  Q.Open;'#10'  while not Q.Eof do'#10'  begin'#10'    Q.Next;'#10'  end;'#10);
  Assert.IsTrue(SuggestIn('unit D;'#10'interface'#10'implementation'#10'procedure Q;'#10'begin'#10 +
    '  Tabelle.Open;'#10#10'end;'#10'end.', 6, FUnits, TLearnedOptions.Default, KnownOnly(['Eof', 'Next']),
    mSuggestion));
  Assert.AreEqual('  while not Tabelle.Eof do|  begin|    |    Tabelle.Next;|  end;', string.Join('|',
    mSuggestion.Lines));
  Assert.AreEqual(2, mSuggestion.CursorLine);
end;

procedure TLearnedSuggestionsTests.TabsAndCursorWithoutBody;
var
  mSuggestion: TLearnedSuggestion;
  mOptions: TLearnedOptions;
  mTrigger: TFollowTrigger;
begin
  mOptions := TLearnedOptions.Default;
  mOptions.UseTabs := True;
  mTrigger := Default(TFollowTrigger);
  mTrigger.Subject := 'X';
  Assert.IsTrue(TLearnedSuggestions.Render('try'#10'>$|'#10'finally'#10'>$S.Free;'#10'end;', mTrigger, #9, mOptions,
    mSuggestion));
  Assert.AreEqual(#9#9'X.Free;', mSuggestion.Lines[3]);
  Assert.IsTrue(TLearnedSuggestions.Render('$S.Done;', mTrigger, '', mOptions, mSuggestion));
  Assert.AreEqual(0, mSuggestion.CursorLine);
  Assert.AreEqual(7, mSuggestion.CursorCharacter, 'ohne Rumpf ans Ende');
  mTrigger.Subject := '';
  Assert.IsFalse(TLearnedSuggestions.Render('$S.Done;', mTrigger, '', mOptions, mSuggestion), 'Subjekt fehlt');
end;

procedure TLearnedSuggestionsTests.LibraryUnitsIgnored;
var
  mSuggestion: TLearnedSuggestion;
  mIndex: Integer;
begin
  AddUnits(5, cTryFree);
  for mIndex := 0 to High(FUnits) do
  begin
    FUnits[mIndex].Library_ := True;
  end;
  Assert.IsFalse(SuggestIn(cDocument, 6, FUnits, TLearnedOptions.Default, KnownOnly(['Free']), mSuggestion));
end;

procedure TLearnedSuggestionsTests.ListSortedWithTeamFirst;
var
  mList: TArray<TLearnedPattern>;
  mOptions: TLearnedOptions;
  mTeam: TSuggestionPattern;
begin
  AddUnits(2, '  L.BeginUpdate;'#10'  try'#10'  finally'#10'    L.EndUpdate;'#10'  end;'#10);
  AddUnits(3, cTryFree);
  AddUnits(1, '  Q.Open;'#10'  while not Q.Eof do begin'#10'    Q.Next;'#10'  end;'#10);
  mTeam.After := 'Log.Enter';
  mTeam.Insert := ['try', '  $|', 'finally', '  Log.Leave;', 'end;'];
  mOptions := TLearnedOptions.Default;
  mOptions.Team := [mTeam];
  mList := TLearnedSuggestions.List(FUnits, mOptions);
  // Team, dann TFoo.Create und $T.Create (je 3), BeginUpdate (2); Open nur einmal: nicht gelistet.
  Assert.AreEqual(4, Integer(Length(mList)));
  Assert.IsTrue(mList[0].Team);
  Assert.AreEqual(3, mList[1].Count);
  Assert.AreEqual(3, mList[2].Count);
  Assert.AreEqual('$S.BeginUpdate', mList[3].Trigger);
end;

/// <summary>Ordner des Referenzprojekts, gesucht von der Test-EXE aufwärts; '' ohne.</summary>
function ReferenceFolder: string;
var
  mDirectory: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    Result := TPath.Combine(mDirectory, TPath.Combine('Tests', 'Referenzprojekt'));
    if TDirectory.Exists(Result) then
    begin
      Exit;
    end;
    if ExtractFileDir(mDirectory) = mDirectory then
    begin
      Break;
    end;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  Result := '';
end;

procedure TLearnedSuggestionsTests.GatherOverReferenceProject;
var
  mRoot, mFile: string;
  mWatch: TStopwatch;
  mPatterns: TArray<TLearnedPattern>;
  mGather: Int64;
begin
  mRoot := ReferenceFolder;
  if mRoot = '' then
  begin
    Assert.Pass('Referenzprojekt nicht gefunden');
  end;
  for mFile in TDirectory.GetFiles(mRoot, '*.pas', TSearchOption.soAllDirectories) do
  begin
    FUnits := FUnits + [TIndexExtractor.ExtractText(TFile.ReadAllText(mFile), mFile, nil, nil, False, True)];
  end;
  Assert.IsTrue(Length(FUnits) > 0, 'keine Units im Referenzprojekt');
  // Je Anfrage sammelt der Server die Muster eines Auslösers über alle Units; das muss im Takt des Tippens gehen.
  mWatch := TStopwatch.StartNew;
  mPatterns := TLearnedSuggestions.Gather(FUnits, ['$S := $T.Create']);
  mGather := mWatch.ElapsedMilliseconds;
  Assert.IsTrue(mGather < 50, Format('%d ms für %d Units', [mGather, Length(FUnits)]));
  mPatterns := TLearnedSuggestions.Gather(FUnits, nil);
  Assert.IsTrue(Length(mPatterns) >= 0);
end;

initialization
  TDUnitX.RegisterTestFixture(TLearnedSuggestionsTests);

end.
