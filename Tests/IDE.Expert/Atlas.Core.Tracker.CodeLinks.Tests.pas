unit Atlas.Core.Tracker.CodeLinks.Tests;

// Tests der Issue-Kennungen im Quelltext (#1265) ohne Editor und Netz: Muster
// aus dem Tracker, Kommentararten über mehrere Zeilen, Literale nur mit
// Commit-Präfix, Wortgrenzen (XATL-1, ATL-1a, #13#10), owner/repo#42 und ein
// Benchmark über 10 000 Zeilen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCodeLinksTests = class
  public
    /// <summary>Ohne Tracker, GitHub ohne owner/repo und YouTrack ohne Kürzel: keine Erkennung.</summary>
    [Test]
    procedure PatternNeedsConfiguredTracker;
    /// <summary>Abnahme: „// TODO ATL-123: …“ mit YouTrack-Projekt ATL wird erkannt.</summary>
    [Test]
    procedure TodoCommentWithYouTrackKey;
    [Test]
    procedure KeyIsCaseInsensitiveAndNormalized;
    /// <summary>Abnahme: Wortgrenzen XATL-1, ATL-1a, ATL_1, äATL-1.</summary>
    [Test]
    procedure WordBoundaries;
    [Test]
    procedure SeveralProjectsInOnePattern;
    /// <summary>Abnahme: ATL-123 im Code außerhalb von Kommentaren und Strings zählt nicht.</summary>
    [Test]
    procedure CodeOutsideCommentsIsIgnored;
    /// <summary>Kommentararten: //, { }, (* *), auch über mehrere Zeilen; Direktiven zählen nicht.</summary>
    [Test]
    procedure CommentKindsAcrossLines;
    /// <summary>Literale nur, wenn sie mit dem Commit-Präfix beginnen.</summary>
    [Test]
    procedure LiteralsOnlyWithCommitPrefix;
    /// <summary>Abnahme: #42 in einem GitHub-Projekt, owner/repo#42, Zeichenkonstanten nicht.</summary>
    [Test]
    procedure GitHubKeys;
    [Test]
    procedure GitHubForeignRepositoryTarget;
    [Test]
    procedure CommitMessageKeysAndDistinct;
    [Test]
    procedure MatchAtFindsKeyUnderCharacter;
    /// <summary>Erkennung über eine Unit mit 10 000 Zeilen.</summary>
    [Test]
    [Category('Benchmark')]
    procedure RecognitionOverLargeUnitIsFast;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.CodeLinks;

const
  cCommit = '{kennung} ';

function YouTrack(const AProject: string): TAtlasIssueKeyPattern;
begin
  Result := TAtlasIssueKeyPattern.ForTarget(TAtlasTrackerTarget.Create(TAtlasTrackerTarget.YouTrack,
    'https://firma.youtrack.cloud', AProject, ''));
end;

function GitHub: TAtlasIssueKeyPattern;
begin
  Result := TAtlasIssueKeyPattern.ForTarget(TAtlasTrackerTarget.Create(TAtlasTrackerTarget.GitHub, '',
    'xKnockOut/Atlas-IDE-Expert', ''));
end;

/// <summary>Kennungen einer Zeile im Code-Zustand, durch „|“ getrennt.</summary>
function Keys(const APattern: TAtlasIssueKeyPattern; const ALine: string): string;
var
  mMatch: TAtlasIssueKeyMatch;
begin
  Result := '';
  for mMatch in TAtlasCodeLinks.LineMatches(APattern, ALine, TAtlasCodeLinkState.Code, cCommit) do
    Result := Result + mMatch.Key + '|';
end;

/// <summary>Kennungen eines Textes in Zeilen: „Zeile:Kennung|“.</summary>
function LineKeys(const APattern: TAtlasIssueKeyPattern; const ALines: TArray<string>): string;
var
  mItem: TAtlasIssueKeyLineMatch;
begin
  Result := '';
  for mItem in TAtlasCodeLinks.Find(APattern, ALines, cCommit) do
    Result := Result + IntToStr(mItem.Line) + ':' + mItem.Match.Key + '|';
end;

procedure TAtlasCodeLinksTests.PatternNeedsConfiguredTracker;
begin
  Assert.IsFalse(TAtlasIssueKeyPattern.Empty.Active);
  Assert.IsFalse(TAtlasIssueKeyPattern.ForTarget(TAtlasTrackerTarget.Create('', '', '', '')).Active);
  Assert.IsFalse(YouTrack('').Active, 'YouTrack ohne Kürzel');
  Assert.IsFalse(TAtlasIssueKeyPattern.ForTarget(TAtlasTrackerTarget.Create(TAtlasTrackerTarget.GitHub,
    'https://github.com', '', '')).Active, 'GitHub ohne owner/repo');
  Assert.IsTrue(YouTrack('ATL').Active);
  Assert.IsTrue(GitHub.Active);
  Assert.AreEqual('', Keys(TAtlasIssueKeyPattern.Empty, '// TODO ATL-123 #42'));
  Assert.AreEqual('xknockout/atlas-ide-expert', GitHub.Repository);
end;

procedure TAtlasCodeLinksTests.TodoCommentWithYouTrackKey;
var
  mMatches: TArray<TAtlasIssueKeyMatch>;
  mLine: string;
begin
  mLine := '  Speichern; // TODO ATL-123: Sperre prüfen';
  mMatches := TAtlasCodeLinks.LineMatches(YouTrack('ATL'), mLine, TAtlasCodeLinkState.Code, cCommit);
  Assert.AreEqual(1, Integer(Length(mMatches)));
  Assert.AreEqual('ATL-123', mMatches[0].Key);
  Assert.AreEqual(123, mMatches[0].Number);
  Assert.AreEqual(Pos('ATL-123', mLine) - 1, mMatches[0].Character);
  Assert.AreEqual(7, mMatches[0].Length);
  Assert.IsTrue(mMatches[0].Place = TAtlasCodeLinkPlace.Comment);
  Assert.AreEqual('ATL-123', mMatches[0].IssueKey);
  Assert.AreEqual('ATL-7|', Keys(YouTrack('ATL'), '{ TODO ATL-7 }'));
end;

procedure TAtlasCodeLinksTests.KeyIsCaseInsensitiveAndNormalized;
begin
  Assert.AreEqual('ATL-5|ATL-12|', Keys(YouTrack('atl'), '// atl-5 und Atl-0012'));
  Assert.AreEqual('ATL-5|', Keys(YouTrack('ATL'), '// (ATL-5).'));
end;

procedure TAtlasCodeLinksTests.WordBoundaries;
begin
  Assert.AreEqual('', Keys(YouTrack('ATL'), '// XATL-1'));
  Assert.AreEqual('', Keys(YouTrack('ATL'), '// ATL-1a'));
  Assert.AreEqual('', Keys(YouTrack('ATL'), '// ATL_1 ATL- ATL-x'));
  Assert.AreEqual('', Keys(YouTrack('ATL'), '// äATL-1 ATL-1ä'));
  Assert.AreEqual('', Keys(YouTrack('ATL'), '// ATL-1234567890'), 'mehr als 9 Ziffern');
  Assert.AreEqual('', Keys(YouTrack('ATL'), '// ATL-0'), 'Nummer 0');
  Assert.AreEqual('ATL-1|ATL-2|', Keys(YouTrack('ATL'), '// „ATL-1“, ATL-2-Folge'));
  Assert.AreEqual('ATL-3|', Keys(YouTrack('ATL'), '//ATL-3'));
end;

procedure TAtlasCodeLinksTests.SeveralProjectsInOnePattern;
begin
  Assert.AreEqual(2, Integer(Length(YouTrack('ATL, KASSE').Projects)));
  Assert.AreEqual('ATL-1|KASSE-2|', Keys(YouTrack('ATL, KASSE'), '// ATL-1 KASSE-2 LAGER-3'));
  // Ungültige Kürzel fallen weg.
  Assert.AreEqual(1, Integer(Length(YouTrack('1X,ATL').Projects)));
end;

procedure TAtlasCodeLinksTests.CodeOutsideCommentsIsIgnored;
begin
  Assert.AreEqual('', Keys(YouTrack('ATL'), 'ATL := ATL-123;'));
  Assert.AreEqual('', Keys(YouTrack('ATL'), 'X := Y - ATL-1 + 2; '));
  Assert.AreEqual('ATL-2|', Keys(YouTrack('ATL'), 'X := ATL-1; // ATL-2'));
  Assert.AreEqual('', Keys(GitHub, 'S := #13#10 + #42;'));
end;

procedure TAtlasCodeLinksTests.CommentKindsAcrossLines;
var
  mLines: TArray<string>;
  mStates: TArray<TAtlasCodeLinkState>;
begin
  mLines := TArray<string>.Create(
    'X := 1; { Anfang ATL-1',
    '  Mitte ATL-2',
    '  Ende ATL-3 } Y := ATL-4;',
    '(* ATL-5',
    '  ATL-6 *) Z := 2; // ATL-7',
    '{$IFDEF ATL-8} W := 1; {$ENDIF}',
    '(*$HINTS OFF ATL-9*) { ATL-10 }',
    '{$DEFINE',
    '  ATL-11 } V := ''// ATL-12''; { ATL-13 }');
  mStates := TAtlasCodeLinks.States(mLines);
  Assert.IsTrue(mStates[0] = TAtlasCodeLinkState.Code);
  Assert.IsTrue(mStates[1] = TAtlasCodeLinkState.BraceComment);
  Assert.IsTrue(mStates[2] = TAtlasCodeLinkState.BraceComment);
  Assert.IsTrue(mStates[3] = TAtlasCodeLinkState.Code);
  Assert.IsTrue(mStates[4] = TAtlasCodeLinkState.ParenComment);
  Assert.IsTrue(mStates[8] = TAtlasCodeLinkState.BraceDirective);
  Assert.AreEqual('0:ATL-1|1:ATL-2|2:ATL-3|3:ATL-5|4:ATL-6|4:ATL-7|6:ATL-10|8:ATL-13|',
    LineKeys(YouTrack('ATL'), mLines));
end;

procedure TAtlasCodeLinksTests.LiteralsOnlyWithCommitPrefix;
var
  mMatches: TArray<TAtlasIssueKeyMatch>;
begin
  mMatches := TAtlasCodeLinks.LineMatches(YouTrack('ATL'), 'Msg := ''ATL-12 Sperre behoben'';',
    TAtlasCodeLinkState.Code, cCommit);
  Assert.AreEqual(1, Integer(Length(mMatches)));
  Assert.IsTrue(mMatches[0].Place = TAtlasCodeLinkPlace.Literal);
  Assert.AreEqual('', Keys(YouTrack('ATL'), 'Msg := ''Siehe ATL-12'';'), 'Literal ohne Präfix');
  // Ohne Commit-Muster nie in Literalen.
  Assert.AreEqual(0, Integer(Length(TAtlasCodeLinks.LineMatches(YouTrack('ATL'), 'Msg := ''ATL-12 x'';',
    TAtlasCodeLinkState.Code, ''))));
  // Muster mit eckigen Klammern und Kurztitel.
  Assert.AreEqual('[ATL-12]', TAtlasCodeLinks.CommitPrefix('[{kennung}] {kurztitel}', mMatches[0]));
  Assert.IsTrue(TAtlasCodeLinks.LiteralAllowed('[ATL-12] Sperre', '[{kennung}] {kurztitel}', mMatches[0]));
  Assert.IsFalse(TAtlasCodeLinks.LiteralAllowed('ATL-12 Sperre', '[{kennung}] {kurztitel}', mMatches[0]));
  // Ein Präfix ohne Kennung sagt nichts.
  Assert.IsFalse(TAtlasCodeLinks.LiteralAllowed('Fix ATL-12', 'Fix ', mMatches[0]));
  // Doppelte Hochkommas im Literal und ein Kommentar dahinter.
  Assert.AreEqual('ATL-12|ATL-13|', Keys(YouTrack('ATL'), 'S := ''ATL-12 Kunde''''s Satz''; // ATL-13'));
end;

procedure TAtlasCodeLinksTests.GitHubKeys;
begin
  Assert.AreEqual('#42|', Keys(GitHub, '// TODO #42: prüfen'));
  Assert.AreEqual('#42|', Keys(GitHub, '{#42}'));
  Assert.AreEqual('#42|', Keys(GitHub, '//#42'));
  Assert.AreEqual('', Keys(GitHub, '// Zeilenende #13#10'));
  Assert.AreEqual('', Keys(GitHub, '// &#123; C#7 Nr#3 #$1F #0 #12a'));
  Assert.AreEqual('#7|', Keys(GitHub, '// xKnockOut/Atlas-IDE-Expert#7'), 'eigenes Repository');
  Assert.AreEqual('octo/lib.core#9|', Keys(GitHub, '// siehe octo/lib.core#9'));
  Assert.AreEqual('', Keys(GitHub, '// https://x/octo/lib#9'), 'Pfad einer Adresse');
  // #42 ohne Tracker nicht.
  Assert.AreEqual('', Keys(YouTrack('ATL'), '// #42'));
end;

procedure TAtlasCodeLinksTests.GitHubForeignRepositoryTarget;
var
  mMatches: TArray<TAtlasIssueKeyMatch>;
  mTarget, mIssueTarget: TAtlasTrackerTarget;
begin
  mTarget := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.GitHub, '', 'xKnockOut/Atlas-IDE-Expert', '');
  mMatches := TAtlasCodeLinks.FindKeys(GitHub, 'Fix octo/Lib#9 und #10');
  Assert.AreEqual(2, Integer(Length(mMatches)));
  Assert.AreEqual('octo/lib', mMatches[0].Repository);
  Assert.AreEqual('#9', mMatches[0].IssueKey);
  mIssueTarget := mMatches[0].IssueTarget(mTarget);
  Assert.AreEqual('octo/lib', mIssueTarget.Project);
  Assert.AreEqual(mTarget.Url, mIssueTarget.Url);
  Assert.AreEqual('', mMatches[1].Repository);
  Assert.AreEqual('xKnockOut/Atlas-IDE-Expert', mMatches[1].IssueTarget(mTarget).Project);
end;

procedure TAtlasCodeLinksTests.CommitMessageKeysAndDistinct;
var
  mMatches: TArray<TAtlasIssueKeyMatch>;
begin
  mMatches := TAtlasCodeLinks.FindKeys(YouTrack('ATL'), 'ATL-97 Sperre (auch atl-98, ATL-97)');
  Assert.AreEqual(3, Integer(Length(mMatches)));
  mMatches := TAtlasCodeLinks.DistinctKeys(mMatches);
  Assert.AreEqual(2, Integer(Length(mMatches)));
  Assert.AreEqual('ATL-97', mMatches[0].Key);
  Assert.AreEqual('ATL-98', mMatches[1].Key);
end;

procedure TAtlasCodeLinksTests.MatchAtFindsKeyUnderCharacter;
var
  mMatches: TArray<TAtlasIssueKeyMatch>;
begin
  mMatches := TAtlasCodeLinks.FindKeys(YouTrack('ATL'), '// ATL-1 ATL-22');
  Assert.AreEqual(-1, TAtlasCodeLinks.MatchAt(mMatches, 2));
  Assert.AreEqual(0, TAtlasCodeLinks.MatchAt(mMatches, 3));
  Assert.AreEqual(0, TAtlasCodeLinks.MatchAt(mMatches, 7));
  Assert.AreEqual(-1, TAtlasCodeLinks.MatchAt(mMatches, 8));
  Assert.AreEqual(1, TAtlasCodeLinks.MatchAt(mMatches, 14));
end;

procedure TAtlasCodeLinksTests.RecognitionOverLargeUnitIsFast;
var
  mLines: TArray<string>;
  mIndex: Integer;
  mWatch: TStopwatch;
  mFound: TArray<TAtlasIssueKeyLineMatch>;
begin
  SetLength(mLines, 10000);
  for mIndex := 0 to High(mLines) do
    case mIndex mod 5 of
      0:
        mLines[mIndex] := Format('  Kunde.Speichern(%d); // TODO ATL-%d: prüfen', [mIndex, mIndex + 1]);
      1:
        mLines[mIndex] := '  { mehrzeilig';
      2:
        mLines[mIndex] := '    ohne Kennung }';
      3:
        mLines[mIndex] := '  S := ''Text mit ATL-5 ohne Präfix'' + IntToStr(X - Y);';
    else
      mLines[mIndex] := '  if (A > B) and (C < D) then Inc(Zaehler);';
    end;
  mWatch := TStopwatch.StartNew;
  mFound := TAtlasCodeLinks.Find(YouTrack('ATL'), mLines, cCommit);
  mWatch.Stop;
  Assert.AreEqual(2000, Integer(Length(mFound)));
  Assert.IsTrue(mWatch.ElapsedMilliseconds < 500, 'Dauer ' + IntToStr(mWatch.ElapsedMilliseconds) + ' ms');
  mLines := nil;
  mFound := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCodeLinksTests);

end.
