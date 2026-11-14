unit Atlas.Core.Editor.CommentContinuation.Tests;

// Tests für Kommentar beim Enter fortsetzen (#696): "//" und "///",
// Aufzählungen, Enter mitten im Text, Ende auf leerer Präfixzeile, Kommentar
// hinter Code und Blockkommentare mit und ohne Präfix. "|" markiert den Cursor
// (vor dem Aufruf in der neuen Zeile, danach dort, wo Atlas ihn hinsetzt).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCommentContinuationTests = class
  public
    [Test]
    procedure ContinuesLineComment;
    [Test]
    procedure ContinuesXmlDocWithoutLineComments;
    [Test]
    procedure LineCommentsOff;
    [Test]
    procedure SplitsInMidText;
    [Test]
    procedure EmptyPrefixEndsComment;
    [Test]
    procedure ContinuesBulletsAndNumbers;
    [Test]
    procedure IndentedSubItem;
    [Test]
    procedure EmptyBulletEndsList;
    [Test]
    procedure ListsOff;
    [Test]
    procedure NoContinuationAfterCode;
    [Test]
    procedure NotInsideString;
    [Test]
    procedure BlockCommentAlignsUnderText;
    [Test]
    procedure BlockCommentWithPrefix;
    [Test]
    procedure DirectiveIsNoComment;
    [Test]
    procedure ListItemMarkers;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Editor.CommentContinuation;

/// <summary>Enter in AText ("|" = Cursor in der neuen Zeile); Ergebnis mit "|" am neuen Cursor, '-' ohne
/// Änderung.</summary>
function Entered(const AText: string; const AOptions: TAtlasCommentOptions): string; overload;
var
  mLines, mNewLines: TArray<string>;
  mLine, mCharacter, mIndex: Integer;
  mEdit: TAtlasCommentEdit;
begin
  Result := '-';
  mLines := AText.Split([#10]);
  mLine := -1;
  mCharacter := -1;
  for mIndex := 0 to High(mLines) do
  begin
    if Pos('|', mLines[mIndex]) > 0 then
    begin
      mLine := mIndex;
      mCharacter := Pos('|', mLines[mIndex]) - 1;
      mLines[mIndex] := StringReplace(mLines[mIndex], '|', '', []);
    end;
  end;
  if not TAtlasCommentContinuation.OnEnter(string.Join(#10, mLines), mLine, mCharacter, AOptions, mEdit) then
  begin
    Exit;
  end;
  mNewLines := Copy(mLines, 0, mEdit.StartLine) + mEdit.Lines + Copy(mLines, mEdit.StartLine + mEdit.OldCount, MaxInt);
  mNewLines[mEdit.CursorLine] := Copy(mNewLines[mEdit.CursorLine], 1, mEdit.CursorCharacter) + '|' +
    Copy(mNewLines[mEdit.CursorLine], mEdit.CursorCharacter + 1, MaxInt);
  Result := string.Join(#10, mNewLines);
end;

function Entered(const AText: string): string; overload;
begin
  Result := Entered(AText, TAtlasCommentOptions.Defaults);
end;

{ TAtlasCommentContinuationTests }

procedure TAtlasCommentContinuationTests.ContinuesLineComment;
begin
  Assert.AreEqual('  // Erste Zeile'#10'  // |'#10'  A;', Entered('  // Erste Zeile'#10'  |'#10'  A;'));
  // Abstand hinter "//" wie darüber, mindestens ein Leerzeichen.
  Assert.AreEqual('//   eingerückt'#10'//   |', Entered('//   eingerückt'#10'|'));
  Assert.AreEqual('//dicht'#10'// |', Entered('//dicht'#10'|'));
end;

procedure TAtlasCommentContinuationTests.ContinuesXmlDocWithoutLineComments;
var
  mOptions: TAtlasCommentOptions;
begin
  mOptions := TAtlasCommentOptions.Defaults;
  mOptions.LineComments := False;
  Assert.AreEqual('  /// <summary>Text'#10'  /// |', Entered('  /// <summary>Text'#10'  |', mOptions));
  // "////" ist kein XMLDoc.
  Assert.AreEqual('-', Entered('//// Trenner'#10'|', mOptions));
end;

procedure TAtlasCommentContinuationTests.LineCommentsOff;
var
  mOptions: TAtlasCommentOptions;
begin
  mOptions := TAtlasCommentOptions.Defaults;
  mOptions.LineComments := False;
  Assert.AreEqual('-', Entered('// Text'#10'|', mOptions));
end;

procedure TAtlasCommentContinuationTests.SplitsInMidText;
begin
  Assert.AreEqual('  // Erster Teil'#10'  // |zweiter Teil', Entered('  // Erster Teil'#10'  |zweiter Teil'));
end;

procedure TAtlasCommentContinuationTests.EmptyPrefixEndsComment;
begin
  Assert.AreEqual('  // Text'#10'  |'#10'A;', Entered('  // Text'#10'  // '#10'  |'#10'A;'));
  Assert.AreEqual('  |', Entered('  ///'#10'  |'));
end;

procedure TAtlasCommentContinuationTests.ContinuesBulletsAndNumbers;
begin
  Assert.AreEqual('// - eins'#10'// - |', Entered('// - eins'#10'|'));
  Assert.AreEqual('// * eins'#10'// * |', Entered('// * eins'#10'|'));
  Assert.AreEqual('// 1. eins'#10'// 2. |', Entered('// 1. eins'#10'|'));
  Assert.AreEqual('// 9) neun'#10'// 10) |', Entered('// 9) neun'#10'|'));
  Assert.AreEqual('/// 3.  drei'#10'/// 4.  |', Entered('/// 3.  drei'#10'|'));
end;

procedure TAtlasCommentContinuationTests.IndentedSubItem;
begin
  Assert.AreEqual('// - eins'#10'//   - Unterpunkt'#10'//   - |', Entered('// - eins'#10'//   - Unterpunkt'#10'|'));
end;

procedure TAtlasCommentContinuationTests.EmptyBulletEndsList;
begin
  Assert.AreEqual('// - eins'#10'// |', Entered('// - eins'#10'// - '#10'|'));
  Assert.AreEqual('// 1. eins'#10'// |', Entered('// 1. eins'#10'// 2.'#10'|'));
end;

procedure TAtlasCommentContinuationTests.ListsOff;
var
  mOptions: TAtlasCommentOptions;
begin
  mOptions := TAtlasCommentOptions.Defaults;
  mOptions.Lists := False;
  Assert.AreEqual('// 1. eins'#10'// |', Entered('// 1. eins'#10'|', mOptions));
  // Eine Jahreszahl ist keine Aufzählung.
  Assert.AreEqual('// 2026. Jahr'#10'// |', Entered('// 2026. Jahr'#10'|'));
end;

procedure TAtlasCommentContinuationTests.NoContinuationAfterCode;
begin
  Assert.AreEqual('-', Entered('  A := 1; // Kommentar'#10'  |'));
  Assert.AreEqual('-', Entered('  A;'#10'  |'));
end;

procedure TAtlasCommentContinuationTests.NotInsideString;
begin
  // Ein "{" im String öffnet keinen Kommentar.
  Assert.AreEqual('-', Entered('  S := ''{'';'#10'  |'));
  // "//" in einem offenen Blockkommentar ist kein Zeilenkommentar.
  Assert.AreEqual('{ Block'#10'  // kein Zeilenkommentar'#10'  |',
    Entered('{ Block'#10'  // kein Zeilenkommentar'#10'|'));
end;

procedure TAtlasCommentContinuationTests.BlockCommentAlignsUnderText;
begin
  Assert.AreEqual('  { Erste Zeile'#10'    |', Entered('  { Erste Zeile'#10'|'));
  Assert.AreEqual('  (* Erste'#10'     |', Entered('  (* Erste'#10'  |'));
  Assert.AreEqual('  {'#10'    |', Entered('  {'#10'|'));
  // Weitere Zeilen wie die Zeile darüber.
  Assert.AreEqual('{ a'#10'      b'#10'      |', Entered('{ a'#10'      b'#10'|'));
  // Schon richtig eingerückt: nichts zu tun.
  Assert.AreEqual('-', Entered('{ a'#10'  |'));
  // Geschlossener Kommentar: nichts.
  Assert.AreEqual('-', Entered('{ a }'#10'|'));
end;

procedure TAtlasCommentContinuationTests.BlockCommentWithPrefix;
var
  mOptions: TAtlasCommentOptions;
begin
  mOptions := TAtlasCommentOptions.Defaults;
  mOptions.BlockPrefix := ' * ';
  Assert.AreEqual('  (* Text'#10'   * |', Entered('  (* Text'#10'|', mOptions));
  Assert.AreEqual('  (* Text'#10'   * mehr'#10'   * |', Entered('  (* Text'#10'   * mehr'#10'  |', mOptions));
  Assert.AreEqual('  (* Text'#10'   |*)', Entered('  (* Text'#10'|*)', mOptions));
  Assert.AreEqual('  { Text'#10'  |}', Entered('  { Text'#10'    |}', mOptions));
end;

procedure TAtlasCommentContinuationTests.DirectiveIsNoComment;
begin
  Assert.AreEqual('-', Entered('{$IFDEF X}'#10'|'));
  Assert.AreEqual('{$R *.res}'#10'// a'#10'// |', Entered('{$R *.res}'#10'// a'#10'|'));
end;

procedure TAtlasCommentContinuationTests.ListItemMarkers;
var
  mMarker, mNext: string;
begin
  Assert.IsTrue(TAtlasCommentContinuation.ListItem('- Punkt', mMarker, mNext));
  Assert.AreEqual('- ', mMarker);
  Assert.AreEqual('- ', mNext);
  Assert.IsTrue(TAtlasCommentContinuation.ListItem('12) x', mMarker, mNext));
  Assert.AreEqual('12) ', mMarker);
  Assert.AreEqual('13) ', mNext);
  Assert.IsFalse(TAtlasCommentContinuation.ListItem('-x', mMarker, mNext));
  Assert.IsFalse(TAtlasCommentContinuation.ListItem('12345. x', mMarker, mNext));
  Assert.IsFalse(TAtlasCommentContinuation.ListItem('3.5 Prozent', mMarker, mNext));
  mMarker := '';
  mNext := '';
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCommentContinuationTests);

end.
