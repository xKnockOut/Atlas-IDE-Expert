unit Atlas.Core.Assistants.LinkState.Tests;

// Assistenten-Kopplung (#2377): Entprellung der Auswahl und offene Vorschläge (jeder genau einmal entschieden,
// nach Namen schließen, beim Trennen alle ablehnen).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasLinkStateTests = class
  public
    [Test]
    procedure SelectionReportedAfterQuiet;
    [Test]
    procedure LatestKeepsLastFile;
    [Test]
    procedure DiffDecidedOnce;
    [Test]
    procedure DiffsClosedByName;
    [Test]
    procedure RejectAllAnswersEach;
    [Test]
    procedure PositionsCountLineBreaks;
    [Test]
    procedure RangeFromStartToEndText;
    [Test]
    procedure BreaksFollowFile;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Assistants.ContextState,
  Atlas.Core.Assistants.Contract.Link,
  Atlas.Core.Assistants.LinkState;

function Selection(const AFileName: string; ALine: Integer): TAtlasLinkSelection;
begin
  Result := Default(TAtlasLinkSelection);
  Result.Known := AFileName <> '';
  Result.FileName := AFileName;
  Result.Start := TAtlasLinkPosition.At(ALine, 0);
  Result.Stop := TAtlasLinkPosition.At(ALine, 4);
end;

function Request(const ATabName: string): TAtlasLinkDiffRequest;
begin
  Result := Default(TAtlasLinkDiffRequest);
  Result.TabName := ATabName;
end;

procedure TAtlasLinkStateTests.SelectionReportedAfterQuiet;
var
  mSelections: TAtlasLinkSelections;
  mQuiet: UInt64;
begin
  mQuiet := TAtlasContextPace.cQuietMs;
  mSelections := TAtlasLinkSelections.Create;
  try
    Assert.IsFalse(mSelections.Due(Selection('A.pas', 1), 0), 'erst vormerken');
    Assert.IsFalse(mSelections.Due(Selection('A.pas', 2), 100), 'Ziehen: neue Auswahl');
    Assert.IsTrue(mSelections.Due(Selection('A.pas', 2), 100 + mQuiet), 'nach Ruhe');
    Assert.IsFalse(mSelections.Due(Selection('A.pas', 2), 200 + 2 * mQuiet), 'gleich: nicht nochmal');
    mSelections.Forget;
    Assert.IsTrue(mSelections.Due(Selection('A.pas', 2), 1000 * mQuiet), 'nach dem Verbinden erneut');
    mSelections.Due(Selection('', 0), 2000 * mQuiet);
    Assert.IsFalse(mSelections.Due(Selection('', 0), 2001 * mQuiet), 'ohne Editor nichts');
  finally
    mSelections.Free;
  end;
end;

procedure TAtlasLinkStateTests.LatestKeepsLastFile;
var
  mSelections: TAtlasLinkSelections;
begin
  mSelections := TAtlasLinkSelections.Create;
  try
    Assert.IsFalse(mSelections.Latest.Known);
    mSelections.Due(Selection('A.pas', 3), 0);
    mSelections.Due(Selection('', 0), 10);
    Assert.IsTrue(mSelections.Latest.Known, 'Fokus weg: letzte Auswahl bleibt');
    Assert.AreEqual('A.pas', mSelections.Latest.FileName);
    Assert.AreEqual(3, mSelections.Latest.Start.Line);
  finally
    mSelections.Free;
  end;
end;

procedure TAtlasLinkStateTests.DiffDecidedOnce;
var
  mDiffs: TAtlasLinkDiffs;
  mId: Integer;
  mCalls: Integer;
  mAccepted: Boolean;
  mText: string;
  mDiff: TAtlasLinkDiff;
begin
  mCalls := 0;
  mAccepted := False;
  mDiffs := TAtlasLinkDiffs.Create;
  try
    mId := mDiffs.Add(1, Request('A'), 'alt',
      procedure(AAccepted: Boolean; const AText: string)
      begin
        Inc(mCalls);
        mAccepted := AAccepted;
        mText := AText;
      end);
    Assert.IsTrue(mDiffs.Find(mId, mDiff));
    Assert.AreEqual('alt', mDiff.OldText);
    Assert.IsTrue(mDiffs.Rebase(mId, 'geändert'));
    Assert.IsTrue(mDiffs.Find(mId, mDiff));
    Assert.AreEqual('geändert', mDiff.OldText, 'gegen den neuen Stand');
    Assert.IsTrue(mDiffs.Decide(mId, True, 'neu'));
    Assert.IsFalse(mDiffs.Decide(mId, False, ''), 'schon entschieden');
    Assert.AreEqual(1, mCalls);
    Assert.IsTrue(mAccepted);
    Assert.AreEqual('neu', mText);
    Assert.AreEqual(0, mDiffs.Count);
    Assert.IsFalse(mDiffs.Find(mId, mDiff));
    Assert.IsFalse(mDiffs.Rebase(mId, 'x'), 'entschieden: nichts mehr zu ändern');
  finally
    mDiffs.Free;
  end;
end;

procedure TAtlasLinkStateTests.DiffsClosedByName;
var
  mDiffs: TAtlasLinkDiffs;
  mFirst: Integer;
  mThird: Integer;
begin
  mDiffs := TAtlasLinkDiffs.Create;
  try
    mFirst := mDiffs.Add(1, Request('A'), '', nil);
    mDiffs.Add(2, Request('B'), '', nil);
    mThird := mDiffs.Add(1, Request('A'), '', nil);
    Assert.AreEqual(2, Integer(Length(mDiffs.IdsNamed('A'))));
    Assert.AreEqual(mFirst, mDiffs.IdsNamed('A')[0]);
    Assert.AreEqual(mThird, mDiffs.IdsNamed('A')[1]);
    Assert.AreEqual(0, Integer(Length(mDiffs.IdsNamed('C'))));
    Assert.AreEqual(3, Integer(Length(mDiffs.Ids)));
    Assert.AreEqual(2, Integer(Length(mDiffs.IdsOf(1))), 'je Verbindung');
    Assert.AreEqual(1, Integer(Length(mDiffs.IdsOf(2))));
    Assert.AreEqual(0, Integer(Length(mDiffs.IdsOf(3))));
  finally
    mDiffs.Free;
  end;
end;

procedure TAtlasLinkStateTests.RejectAllAnswersEach;
var
  mDiffs: TAtlasLinkDiffs;
  mRejected: Integer;
  mDone: TAtlasLinkDiffDone;
begin
  mRejected := 0;
  mDone :=
    procedure(AAccepted: Boolean; const AText: string)
    begin
      if not AAccepted then
      begin
        Inc(mRejected);
      end;
    end;
  mDiffs := TAtlasLinkDiffs.Create;
  try
    mDiffs.Add(1, Request('A'), '', mDone);
    mDiffs.Add(1, Request('B'), '', mDone);
    Assert.AreEqual(2, mDiffs.RejectAll);
    Assert.AreEqual(2, mRejected);
    Assert.AreEqual(0, mDiffs.Count);
    Assert.AreEqual(0, mDiffs.RejectAll);
  finally
    mDiffs.Free;
  end;
  mDone := nil;
end;

procedure TAtlasLinkStateTests.PositionsCountLineBreaks;
var
  mPosition: TAtlasLinkPosition;
begin
  Assert.AreEqual(1, TAtlasLinkText.LineCount(''));
  Assert.AreEqual(3, TAtlasLinkText.LineCount('a'#13#10'b'#10'c'));
  Assert.AreEqual(2, TAtlasLinkText.LineCount('a'#13#10));
  mPosition := TAtlasLinkText.PositionOf('ab'#13#10'cd', 5);
  Assert.AreEqual(1, mPosition.Line);
  Assert.AreEqual(1, mPosition.Character);
  mPosition := TAtlasLinkText.PositionOf('ab'#13#10'cd', 4);
  Assert.AreEqual(1, mPosition.Line, 'direkt nach CRLF');
  Assert.AreEqual(0, mPosition.Character);
end;

procedure TAtlasLinkStateTests.RangeFromStartToEndText;
const
  cText = 'unit A;'#13#10'begin'#13#10'  Result := 1;'#13#10'end.';
var
  mRange: TAtlasLinkRange;
begin
  mRange := TAtlasLinkText.FindRange(cText, 'begin', 'end', False);
  Assert.IsTrue(mRange.Found);
  Assert.AreEqual(1, mRange.Start.Line);
  Assert.AreEqual(0, mRange.Start.Character);
  Assert.AreEqual(3, mRange.Stop.Line);
  Assert.AreEqual(3, mRange.Stop.Character, 'hinter endText');
  mRange := TAtlasLinkText.FindRange(cText, 'Result', '', True);
  Assert.AreEqual(2, mRange.Start.Line);
  Assert.AreEqual(2, mRange.Start.Character);
  Assert.AreEqual(2, mRange.Stop.Line);
  Assert.AreEqual(14, mRange.Stop.Character, 'bis zum Zeilenende');
  Assert.IsFalse(TAtlasLinkText.FindRange(cText, 'fehlt', '', False).Found);
  Assert.IsFalse(TAtlasLinkText.FindRange(cText, '', 'end', False).Found);
end;

procedure TAtlasLinkStateTests.BreaksFollowFile;
begin
  Assert.AreEqual('a'#13#10'b', TAtlasLinkText.MatchBreaks('x'#13#10'y', 'a'#10'b'), 'Datei mit CRLF');
  Assert.AreEqual('a'#10'b', TAtlasLinkText.MatchBreaks('x'#10'y', 'a'#10'b'), 'Datei mit LF');
  Assert.AreEqual('a'#13#10'b'#10'c', TAtlasLinkText.MatchBreaks('x'#13#10'y', 'a'#13#10'b'#10'c'),
    'gemischt: unverändert');
  Assert.AreEqual('a'#10'b', TAtlasLinkText.MatchBreaks('', 'a'#10'b'), 'neue Datei');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLinkStateTests);

end.
