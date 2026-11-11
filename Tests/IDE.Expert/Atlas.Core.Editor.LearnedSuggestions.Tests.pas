unit Atlas.Core.Editor.LearnedSuggestions.Tests;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Plugin-Kern der gelernten Vorschläge (#1890): Argumente, Antworten, Schattentext, Lernzähler.
  /// </summary>
  [TestFixture]
  TAtlasLearnedSuggestionsTests = class
  public
    [Test]
    procedure BuildsArguments;
    [Test]
    procedure ReadsSuggestion;
    [Test]
    procedure RejectsInvalidSuggestions;
    [Test]
    procedure ReadsList;
    [Test]
    procedure GhostShowsBlockInOneLine;
    [Test]
    procedure GhostAcceptsWordByWord;
    [Test]
    procedure WrittenIndentCounts;
    [Test]
    procedure HintNamesThreePlaces;
    [Test]
    procedure RejectedPatternSinksAcceptedRises;
    [Test]
    procedure OffAndForget;
    [Test]
    procedure CountersPerGroup;
    [Test]
    procedure SavesAndLoadsCounters;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Editor.LearnedSuggestions,
  Atlas.Core.Editor.LearnedUsage;

const
  cAnswer = '{"id": "$s := tfoo.create => try / >$| / finally / >$s.free; / end;", "trigger": "$S := TFoo.Create", ' +
    '"count": 6, "total": 7, "share": 85, "team": false, "evidence": [{"uri": "file:///C:/P/A.pas", "line": 11}, ' +
    '{"uri": "file:///C:/P/B.pas", "line": 3}, {"uri": "file:///C:/P/C.pas", "line": 40}, ' +
    '{"uri": "file:///C:/P/D.pas", "line": 1}], "lines": ["  try", "    ", "  finally", "    X.Free;", "  end;"], ' +
    '"cursor": {"line": 8, "character": 4}}';

function Parsed(const AText: string): TJSONValue;
begin
  Result := TJSONObject.ParseJSONValue(AText);
end;

function SuggestionOf(const AText: string; ALine: Integer; out ASuggestion: TAtlasLearnedSuggestion): Boolean;
var
  mValue: TJSONValue;
begin
  mValue := Parsed(AText);
  try
    Result := TAtlasLearnedSuggestions.ReadSuggestion(mValue, ALine, ASuggestion);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasLearnedSuggestionsTests.BuildsArguments;
var
  mAdjust: TAtlasLearnedAdjust;
  mRequest: TAtlasLearnedRequest;
begin
  mAdjust.Id := 'a => b';
  mAdjust.By := -20;
  mRequest.Uri := 'file:///C:/P/U.pas';
  mRequest.Line := 7;
  mRequest.TabSize := 2;
  mRequest.InsertSpaces := True;
  mRequest.MinCount := 5;
  mRequest.MinShare := 70;
  mRequest.Adjust := [mAdjust];
  Assert.AreEqual('["file:///C:/P/U.pas",7,{"tabSize":2,"insertSpaces":true},' +
    '{"minCount":5,"minShare":70,"adjust":{"a => b":-20}}]',
    TAtlasLearnedSuggestions.SuggestArguments(mRequest));
  Assert.AreEqual('["file:///C:/P/U.pas"]', TAtlasLearnedSuggestions.ListArguments('file:///C:/P/U.pas'));
end;

procedure TAtlasLearnedSuggestionsTests.ReadsSuggestion;
var
  mSuggestion: TAtlasLearnedSuggestion;
begin
  Assert.IsTrue(SuggestionOf(cAnswer, 7, mSuggestion));
  Assert.AreEqual('$S := TFoo.Create', mSuggestion.Pattern.Trigger);
  Assert.AreEqual(6, mSuggestion.Pattern.Count);
  Assert.AreEqual(85, mSuggestion.Pattern.Share);
  Assert.AreEqual(5, Integer(Length(mSuggestion.Lines)));
  Assert.AreEqual(8, mSuggestion.CursorLine);
  Assert.AreEqual(4, mSuggestion.CursorCharacter);
  Assert.AreEqual(4, Integer(Length(mSuggestion.Pattern.Evidence)));
  Assert.AreEqual(11, mSuggestion.Pattern.Evidence[0].Line);
  Assert.AreEqual('A.pas', ExtractFileName(mSuggestion.Pattern.Evidence[0].FileName));
  Assert.AreEqual('  try'#13#10'    '#13#10'  finally'#13#10'    X.Free;'#13#10'  end;',
    TAtlasLearnedSuggestions.BlockText(mSuggestion, #13#10));
end;

procedure TAtlasLearnedSuggestionsTests.RejectsInvalidSuggestions;
var
  mSuggestion: TAtlasLearnedSuggestion;
begin
  Assert.IsFalse(SuggestionOf('null', 7, mSuggestion));
  Assert.IsFalse(SuggestionOf('{"id": "x", "lines": [], "cursor": {"line": 7, "character": 0}}', 7, mSuggestion));
  Assert.IsFalse(SuggestionOf('{"lines": ["a"], "cursor": {"line": 7, "character": 0}}', 7, mSuggestion),
    'ohne Kennung');
  Assert.IsFalse(SuggestionOf('{"id": "x", "lines": ["a"], "cursor": {"line": 9, "character": 0}}', 7, mSuggestion),
    'Schreibmarke außerhalb des Blocks');
end;

procedure TAtlasLearnedSuggestionsTests.ReadsList;
var
  mValue: TJSONValue;
  mList: TArray<TAtlasLearnedPattern>;
begin
  mValue := Parsed('[{"id": "a", "trigger": "$S.BeginUpdate", "text": "try … finally $S.EndUpdate; end;", ' +
    '"count": 9, "total": 9, "share": 100, "team": false, "evidence": []}, {"trigger": "kaputt"}, ' +
    '{"id": "b", "trigger": "Log.Enter", "text": "try … finally Log.Leave; end;", "team": true}]');
  try
    mList := TAtlasLearnedSuggestions.ReadList(mValue);
  finally
    mValue.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mList)));
  Assert.AreEqual('try … finally $S.EndUpdate; end;', mList[0].Text);
  Assert.AreEqual(100, mList[0].Share);
  Assert.IsTrue(mList[1].Team);
end;

procedure TAtlasLearnedSuggestionsTests.GhostShowsBlockInOneLine;
var
  mGhost: TAtlasGhostText;
begin
  mGhost := TAtlasGhostText.Create('  try'#13#10'    '#13#10'  finally'#13#10'    X.Free;'#13#10'  end;', 2);
  Assert.AreEqual('try … finally X.Free; end;', mGhost.Display);
  Assert.AreEqual('try'#13#10'    '#13#10'  finally'#13#10'    X.Free;'#13#10'  end;', mGhost.Rest);
  mGhost.Advance('try');
  Assert.AreEqual('… finally X.Free; end;', mGhost.Display, 'Rest ab dem Zeilenumbruch: nur der Rumpf als …');
end;

procedure TAtlasLearnedSuggestionsTests.GhostAcceptsWordByWord;
var
  mGhost: TAtlasGhostText;
  mWord: string;
begin
  mGhost := TAtlasGhostText.Create('  try'#10'  finally'#10'    X.Free;'#10'  end;', 2);
  mWord := mGhost.NextWord;
  Assert.AreEqual('try', mWord);
  mGhost.Advance(mWord);
  mWord := mGhost.NextWord;
  Assert.AreEqual(#10'  finally', mWord, 'Zeilenumbruch und Einrückung gehören zum nächsten Wort');
  mGhost.Advance(mWord);
  mGhost.Advance(mGhost.NextWord);
  Assert.AreEqual('.', mGhost.NextWord, 'Satzzeichen als eigenes Stück');
  mGhost.Advance('.');
  mGhost.Advance(mGhost.NextWord);
  Assert.AreEqual(';', mGhost.NextWord);
  mGhost.Advance(';');
  mGhost.Advance(mGhost.NextWord);
  Assert.AreEqual(';', mGhost.NextWord);
  Assert.IsFalse(mGhost.Finished);
  mGhost.Advance(';');
  Assert.IsTrue(mGhost.Finished);
  Assert.AreEqual('', mGhost.NextWord);
end;

procedure TAtlasLearnedSuggestionsTests.WrittenIndentCounts;
begin
  Assert.AreEqual(2, TAtlasLearnedSuggestions.Written('  try', '  '));
  Assert.AreEqual(0, TAtlasLearnedSuggestions.Written('  try', '    '), 'tiefer eingerückt: Zeile ersetzen');
  Assert.AreEqual(0, TAtlasLearnedSuggestions.Written('  try', ''));
end;

procedure TAtlasLearnedSuggestionsTests.HintNamesThreePlaces;
var
  mSuggestion: TAtlasLearnedSuggestion;
  mHint: string;
begin
  Assert.IsTrue(SuggestionOf(cAnswer, 7, mSuggestion));
  mHint := TAtlasLearnedSuggestions.HintText(mSuggestion.Pattern);
  Assert.Contains(mHint, 'A.pas:12');
  Assert.Contains(mHint, 'B.pas:4');
  Assert.Contains(mHint, 'C.pas:41');
  Assert.DoesNotContain(mHint, 'D.pas');
  Assert.Contains(mHint, '85');
  Assert.Contains(TAtlasLearnedSuggestions.StatusText(mSuggestion.Pattern), '6');
end;

procedure TAtlasLearnedSuggestionsTests.RejectedPatternSinksAcceptedRises;
var
  mUsage: TAtlasLearnedUsage;
  mIndex: Integer;
  mList: TArray<TAtlasLearnedAdjust>;
begin
  mUsage := TAtlasLearnedUsage.Create;
  try
    for mIndex := 1 to 5 do
    begin
      mUsage.Rejected('A');
    end;
    Assert.AreEqual(-50, mUsage.Adjust('a', True), 'fünfmal Esc: 100 % fallen unter 70 %');
    for mIndex := 1 to 10 do
    begin
      mUsage.Rejected('a');
    end;
    Assert.AreEqual(-TAtlasLearnedUsage.cRejectMax, mUsage.Adjust('a', True));
    for mIndex := 1 to 10 do
    begin
      mUsage.Accepted('b');
    end;
    Assert.AreEqual(TAtlasLearnedUsage.cAcceptMax, mUsage.Adjust('b', True));
    Assert.AreEqual(0, mUsage.Adjust('b', False), 'Lernen aus der Nutzung aus');
    mList := mUsage.AdjustList(True);
    Assert.AreEqual(2, Integer(Length(mList)));
    Assert.AreEqual(0, Integer(Length(mUsage.AdjustList(False))));
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasLearnedSuggestionsTests.OffAndForget;
var
  mUsage: TAtlasLearnedUsage;
  mAccepted, mRejected: Integer;
  mList: TArray<TAtlasLearnedAdjust>;
begin
  mUsage := TAtlasLearnedUsage.Create;
  try
    mUsage.Rejected('a');
    mUsage.SetOff('a', True);
    Assert.IsTrue(mUsage.IsOff('a'));
    Assert.AreEqual(TAtlasLearnedUsage.cOffPoints, mUsage.Adjust('a', False), 'abgeschaltet gilt immer');
    mList := mUsage.AdjustList(False);
    Assert.AreEqual(1, Integer(Length(mList)));
    Assert.AreEqual(TAtlasLearnedUsage.cOffPoints, mList[0].By);
    mUsage.Forget('a');
    mUsage.Counts('a', mAccepted, mRejected);
    Assert.AreEqual(0, mRejected);
    Assert.IsTrue(mUsage.IsOff('a'), 'Vergessen lässt den Schalter');
    mUsage.SetOff('a', False);
    Assert.AreEqual(0, mUsage.Count, 'ohne Zähler und Schalter kein Eintrag');
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasLearnedSuggestionsTests.CountersPerGroup;
var
  mUsage: TAtlasLearnedUsage;
begin
  mUsage := TAtlasLearnedUsage.Create;
  try
    mUsage.SetGroup('C:\P\Eins.groupproj');
    mUsage.Rejected('a');
    mUsage.SetGroup('C:\P\Zwei.groupproj');
    Assert.AreEqual(0, mUsage.Adjust('a', True));
    Assert.AreEqual(0, Integer(Length(mUsage.AdjustList(True))));
    mUsage.SetGroup('c:\p\eins.groupproj');
    Assert.AreEqual(-TAtlasLearnedUsage.cRejectPoints, mUsage.Adjust('a', True));
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasLearnedSuggestionsTests.SavesAndLoadsCounters;
var
  mUsage, mRead: TAtlasLearnedUsage;
  mAccepted, mRejected: Integer;
begin
  mUsage := TAtlasLearnedUsage.Create;
  mRead := TAtlasLearnedUsage.Create;
  try
    mUsage.SetGroup('C:\P\G.groupproj');
    mUsage.Accepted('a => b');
    mUsage.Rejected('c');
    mUsage.SetOff('c', True);
    Assert.IsTrue(mUsage.Changed);
    Assert.IsTrue(mRead.FromJson(mUsage.ToJson));
    Assert.IsFalse(mRead.Changed);
    mRead.SetGroup('C:\P\G.groupproj');
    mRead.Counts('a => b', mAccepted, mRejected);
    Assert.AreEqual(1, mAccepted);
    Assert.IsTrue(mRead.IsOff('c'));
    Assert.IsFalse(mRead.FromJson('[1, 2'));
    Assert.AreEqual(0, mRead.Count);
    Assert.IsFalse(mRead.FromJson('{"groups": 3}'));
  finally
    mRead.Free;
    mUsage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLearnedSuggestionsTests);

end.
