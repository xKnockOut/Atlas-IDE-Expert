unit Atlas.Core.Editor.BlockComment.Tests;

// Blockkommentar umschalten (#703): Hin und zurück, Wahl der Form, Rückfall,
// Direktiven, Teilmarkierung, ohne Markierung (Anweisung, Zeile, Entfernen),
// Kommentarzeichen in eigenen Zeilen, Markierung danach.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Editor.BlockComment;

type
  [TestFixture]
  TAtlasBlockCommentTests = class
  private
    FLines: TArray<string>;
    FResult: TAtlasBlockCommentResult;
    function Toggle(ALine, AStart, AEndLine, AEnd: Integer): TAtlasBlockCommentResult; overload;
    function Toggle(ALine, AStart, AEndLine, AEnd: Integer;
      const AOptions: TAtlasBlockCommentOptions): TAtlasBlockCommentResult; overload;
    function Joined(const ALines: TArray<string>): string;
    function Selected(const AResult: TAtlasBlockCommentResult): string;
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure PartialSelectionInlineAndBack;
    [Test]
    procedure ChoosesFormByContent;
    [Test]
    procedure PreferredParens;
    [Test]
    procedure BothEndsFallBackOrRefuse;
    [Test]
    procedure DirectivesStayDirectives;
    [Test]
    procedure MultiLineAtEnds;
    [Test]
    procedure MultiLineOwnLines;
    [Test]
    procedure RemovesSurroundingComment;
    [Test]
    procedure WithoutSelectionStatement;
    [Test]
    procedure WithoutSelectionLine;
    [Test]
    procedure StatementRangeSpansBlocks;
    [Test]
    procedure IgnoresStringsWhenLexing;
    [Test]
    procedure SettingValues;
  end;

implementation

uses
  System.SysUtils;

function TAtlasBlockCommentTests.Toggle(ALine, AStart, AEndLine, AEnd: Integer): TAtlasBlockCommentResult;
begin
  Result := Toggle(ALine, AStart, AEndLine, AEnd, TAtlasBlockCommentOptions.Defaults);
end;

function TAtlasBlockCommentTests.Toggle(ALine, AStart, AEndLine, AEnd: Integer;
  const AOptions: TAtlasBlockCommentOptions): TAtlasBlockCommentResult;
begin
  Result := TAtlasBlockComment.Toggle(FLines, TLspTextPosition.Create(ALine, AStart),
    TLspTextPosition.Create(AEndLine, AEnd), AOptions);
end;

function TAtlasBlockCommentTests.Joined(const ALines: TArray<string>): string;
begin
  Result := string.Join('|', ALines);
end;

function TAtlasBlockCommentTests.Selected(const AResult: TAtlasBlockCommentResult): string;
var
  Line: Integer;
begin
  Result := '';
  if AResult.SelectionStart.Line = AResult.SelectionEnd.Line then
    Exit(Copy(AResult.Lines[AResult.SelectionStart.Line], AResult.SelectionStart.Character + 1,
      AResult.SelectionEnd.Character - AResult.SelectionStart.Character));
  Result := Copy(AResult.Lines[AResult.SelectionStart.Line], AResult.SelectionStart.Character + 1, MaxInt);
  for Line := AResult.SelectionStart.Line + 1 to AResult.SelectionEnd.Line - 1 do
    Result := Result + '|' + AResult.Lines[Line];
  Result := Result + '|' + Copy(AResult.Lines[AResult.SelectionEnd.Line], 1, AResult.SelectionEnd.Character);
end;

procedure TAtlasBlockCommentTests.TearDown;
begin
  FLines := nil;
  FResult := Default(TAtlasBlockCommentResult);
end;

procedure TAtlasBlockCommentTests.PartialSelectionInlineAndBack;
var
  Back: TAtlasBlockCommentResult;
begin
  FLines := ['  Foo(A, B, C);'];
  // "B, " markiert: Leerraum am Rand bleibt draußen.
  FResult := Toggle(0, 9, 0, 12);
  Assert.AreEqual(Ord(TAtlasBlockCommentKind.Added), Ord(FResult.Kind));
  Assert.AreEqual('  Foo(A, { B, } C);', Joined(FResult.Lines));
  Assert.AreEqual('B, } ', Selected(FResult), 'Markierung bleibt auf dem Text');
  FLines := FResult.Lines;
  Back := Toggle(FResult.SelectionStart.Line, FResult.SelectionStart.Character, FResult.SelectionEnd.Line,
    FResult.SelectionEnd.Character);
  Assert.AreEqual(Ord(TAtlasBlockCommentKind.Removed), Ord(Back.Kind));
  Assert.AreEqual('  Foo(A, B, C);', Joined(Back.Lines), 'hin und zurück');
  Assert.AreEqual('B, ', Selected(Back));
end;

procedure TAtlasBlockCommentTests.ChoosesFormByContent;
begin
  FLines := ['X := 1; { alt } Y := 2;'];
  FResult := Toggle(0, 0, 0, 23);
  Assert.AreEqual('(* X := 1; { alt } Y := 2; *)', Joined(FResult.Lines), 'enthält }');
  FLines := FResult.Lines;
  Assert.AreEqual('X := 1; { alt } Y := 2;', Joined(Toggle(0, 0, 0, 29).Lines), 'zurück');
  FLines := ['X := 1; (* alt *) Y := 2;'];
  Assert.AreEqual('{ X := 1; (* alt *) Y := 2; }', Joined(Toggle(0, 0, 0, 25).Lines), 'enthält *)');
end;

procedure TAtlasBlockCommentTests.PreferredParens;
var
  Options: TAtlasBlockCommentOptions;
begin
  Options := TAtlasBlockCommentOptions.Defaults;
  Options.Style := TAtlasBlockCommentStyle.Parens;
  FLines := ['Inc(I);'];
  FResult := Toggle(0, 0, 0, 7, Options);
  Assert.AreEqual('(* Inc(I); *)', Joined(FResult.Lines));
  FLines := ['Inc(I); (* x *)'];
  Assert.AreEqual('{ Inc(I); (* x *) }', Joined(Toggle(0, 0, 0, 15, Options).Lines), '*) erzwingt {}');
end;

procedure TAtlasBlockCommentTests.BothEndsFallBackOrRefuse;
var
  Options: TAtlasBlockCommentOptions;
begin
  FLines := ['  A := 1; { a }', '  B := 2; (* b *)'];
  FResult := Toggle(0, 2, 1, 17);
  Assert.AreEqual(Ord(TAtlasBlockCommentKind.LineComments), Ord(FResult.Kind));
  Assert.AreEqual('  // A := 1; { a }|  // B := 2; (* b *)', Joined(FResult.Lines));
  Assert.AreEqual('A := 1; { a }|  // B := 2; (* b *)', Selected(FResult));
  Options := TAtlasBlockCommentOptions.Defaults;
  Options.Fallback := TAtlasBlockCommentFallback.Refuse;
  FResult := Toggle(0, 2, 1, 17, Options);
  Assert.AreEqual(Ord(TAtlasBlockCommentKind.Refused), Ord(FResult.Kind));
  Assert.AreEqual(Joined(FLines), Joined(FResult.Lines), 'nichts geändert');
end;

procedure TAtlasBlockCommentTests.DirectivesStayDirectives;
begin
  FLines := ['{$IFDEF DEBUG}', 'Log;', '{$ENDIF}'];
  // Nur die Direktive markiert: // statt eines Kommentars, der wie eine Direktive aussähe.
  FResult := Toggle(0, 0, 0, 14);
  Assert.AreEqual(Ord(TAtlasBlockCommentKind.LineComments), Ord(FResult.Kind));
  Assert.AreEqual('// {$IFDEF DEBUG}|Log;|{$ENDIF}', Joined(FResult.Lines));
  // Cursor in einer Direktive: kein Kommentar zum Entfernen; die Zeile bekommt //.
  FResult := Toggle(2, 3, 2, 3);
  Assert.AreEqual('{$IFDEF DEBUG}|Log;|// {$ENDIF}', Joined(FResult.Lines));
  FLines := ['(*$R+*) X;'];
  FResult := Toggle(0, 0, 0, 7);
  Assert.AreEqual('// (*$R+*) X;', Joined(FResult.Lines));
  // Text, der mit $ beginnt, wird keine Direktive: das Leerzeichen trennt.
  FLines := ['S := $FF;'];
  FResult := Toggle(0, 5, 0, 8);
  Assert.AreEqual('S := { $FF };', Joined(FResult.Lines));
  // Direktive in der Markierung: wegen } die Form (* *).
  FLines := ['{$R *.res} X;'];
  FResult := Toggle(0, 0, 0, 13);
  Assert.AreEqual('(* {$R *.res} X; *)', Joined(FResult.Lines));
end;

procedure TAtlasBlockCommentTests.MultiLineAtEnds;
var
  Back: TAtlasBlockCommentResult;
begin
  FLines := ['begin', '  A := 1;', '  B := 2;', 'end;'];
  // Ganze Zeilen 1–2 markiert (bis zum Anfang von Zeile 3).
  FResult := Toggle(1, 0, 3, 0);
  Assert.AreEqual('begin|  { A := 1;|  B := 2; }|end;', Joined(FResult.Lines));
  Assert.AreEqual('  { A := 1;|  B := 2; }|', Selected(FResult));
  FLines := FResult.Lines;
  Back := Toggle(FResult.SelectionStart.Line, FResult.SelectionStart.Character, FResult.SelectionEnd.Line,
    FResult.SelectionEnd.Character);
  Assert.AreEqual('begin|  A := 1;|  B := 2;|end;', Joined(Back.Lines), 'hin und zurück');
  Assert.AreEqual('  A := 1;|  B := 2;|', Selected(Back));
end;

procedure TAtlasBlockCommentTests.MultiLineOwnLines;
var
  Options: TAtlasBlockCommentOptions;
  Back: TAtlasBlockCommentResult;
begin
  Options := TAtlasBlockCommentOptions.Defaults;
  Options.OwnLines := True;
  FLines := ['begin', '  A := 1;', '  B := 2;', 'end;'];
  FResult := Toggle(1, 0, 3, 0, Options);
  Assert.AreEqual('begin|  {|  A := 1;|  B := 2;|  }|end;', Joined(FResult.Lines));
  Assert.AreEqual('  A := 1;|  B := 2;|', Selected(FResult), 'Markierung auf den Zeilen dazwischen');
  FLines := FResult.Lines;
  Back := Toggle(FResult.SelectionStart.Line, FResult.SelectionStart.Character, FResult.SelectionEnd.Line,
    FResult.SelectionEnd.Character, Options);
  Assert.AreEqual(Ord(TAtlasBlockCommentKind.Removed), Ord(Back.Kind));
  Assert.AreEqual('begin|  A := 1;|  B := 2;|end;', Joined(Back.Lines), 'hin und zurück');
  Assert.AreEqual('  A := 1;|  B := 2;|', Selected(Back));
  // Einzeilig bleibt es inline.
  FLines := ['  A := 1;'];
  Assert.AreEqual('  { A := 1; }', Joined(Toggle(0, 2, 0, 9, Options).Lines));
end;

procedure TAtlasBlockCommentTests.RemovesSurroundingComment;
begin
  FLines := ['A; (* B; C; *) D;'];
  // Cursor im Kommentar ohne Markierung.
  FResult := Toggle(0, 8, 0, 8);
  Assert.AreEqual(Ord(TAtlasBlockCommentKind.Removed), Ord(FResult.Kind));
  Assert.AreEqual('A; B; C; D;', Joined(FResult.Lines));
  Assert.AreEqual(5, FResult.SelectionStart.Character, 'Cursor wandert mit');
  // Markierung ganz im Kommentar.
  FLines := ['{', '  Alt;', '}', 'Neu;'];
  FResult := Toggle(1, 2, 1, 6);
  Assert.AreEqual('  Alt;|Neu;', Joined(FResult.Lines));
  // Kommentar ohne Leerzeichen innen.
  FLines := ['{X}Y'];
  Assert.AreEqual('XY', Joined(Toggle(0, 1, 0, 1).Lines));
  FLines := ['{ }'];
  Assert.AreEqual('', Joined(Toggle(0, 1, 0, 1).Lines));
end;

procedure TAtlasBlockCommentTests.WithoutSelectionStatement;
var
  Back: TAtlasBlockCommentResult;
begin
  FLines := ['begin', '  ShowMessage(''a;'' +', '    Name);', '  Exit;', 'end;'];
  FResult := Toggle(2, 6, 2, 6);
  Assert.AreEqual(Ord(TAtlasBlockCommentKind.Added), Ord(FResult.Kind));
  Assert.AreEqual('begin|  { ShowMessage(''a;'' +|    Name); }|  Exit;|end;', Joined(FResult.Lines),
    'die ganze Anweisung, ; im String zählt nicht');
  Assert.AreEqual(6, FResult.SelectionStart.Character, 'Cursor in der zweiten Zeile bleibt');
  Assert.AreEqual(FResult.SelectionStart.Character, FResult.SelectionEnd.Character, 'ohne Markierung');
  FLines := FResult.Lines;
  Back := Toggle(2, 6, 2, 6);
  Assert.AreEqual('begin|  ShowMessage(''a;'' +|    Name);|  Exit;|end;', Joined(Back.Lines), 'zurück');
  // Hinter dem Semikolon: die Anweisung davor.
  FLines := ['  Exit;'];
  Assert.AreEqual('  { Exit; }', Joined(Toggle(0, 7, 0, 7).Lines));
  // Leere Zeile: nichts.
  FLines := ['', 'A;'];
  Assert.AreEqual(Ord(TAtlasBlockCommentKind.None), Ord(Toggle(0, 0, 0, 0).Kind));
end;

procedure TAtlasBlockCommentTests.WithoutSelectionLine;
var
  Options: TAtlasBlockCommentOptions;
begin
  Options := TAtlasBlockCommentOptions.Defaults;
  Options.Scope := TAtlasBlockCommentScope.Line;
  FLines := ['  ShowMessage(''a'' +', '    Name);'];
  Assert.AreEqual('  { ShowMessage(''a'' + }|    Name);', Joined(Toggle(0, 4, 0, 4, Options).Lines));
end;

procedure TAtlasBlockCommentTests.StatementRangeSpansBlocks;
var
  StartPos, EndPos: TLspTextPosition;
begin
  FLines := ['  if A then', '  begin', '    B;', '  end', '  else', '    C;', '  D;'];
  Assert.IsTrue(TAtlasBlockComment.StatementRange(FLines, TLspTextPosition.Create(0, 3), StartPos, EndPos));
  Assert.AreEqual(0, StartPos.Line);
  Assert.AreEqual(2, StartPos.Character);
  Assert.AreEqual(5, EndPos.Line, 'if … else C; als eine Anweisung');
  Assert.AreEqual(6, EndPos.Character);
  // In begin … end: nur die Anweisung dort.
  Assert.IsTrue(TAtlasBlockComment.StatementRange(FLines, TLspTextPosition.Create(2, 4), StartPos, EndPos));
  Assert.AreEqual(2, StartPos.Line);
  Assert.AreEqual(4, StartPos.Character);
  Assert.AreEqual(2, EndPos.Line);
  Assert.AreEqual(6, EndPos.Character);
  // Nach else: nur der Zweig.
  Assert.IsTrue(TAtlasBlockComment.StatementRange(FLines, TLspTextPosition.Create(5, 4), StartPos, EndPos));
  Assert.AreEqual(5, StartPos.Line);
  Assert.AreEqual(4, StartPos.Character);
  // Deklaration mit array of: ganz.
  FLines := ['var', '  A: array of Integer;'];
  Assert.IsTrue(TAtlasBlockComment.StatementRange(FLines, TLspTextPosition.Create(1, 18), StartPos, EndPos));
  Assert.AreEqual(2, StartPos.Character);
  Assert.AreEqual(22, EndPos.Character);
  // Letzte Anweisung vor end ohne Semikolon.
  FLines := ['begin', '  X := 1', 'end;'];
  Assert.IsTrue(TAtlasBlockComment.StatementRange(FLines, TLspTextPosition.Create(1, 2), StartPos, EndPos));
  Assert.AreEqual(1, EndPos.Line);
  Assert.AreEqual(8, EndPos.Character);
end;

procedure TAtlasBlockCommentTests.IgnoresStringsWhenLexing;
var
  Spans: TArray<TAtlasCommentSpan>;
begin
  FLines := ['S := ''{ kein Kommentar }'' + ''it''''s''; // Rest', '{ a', 'b } (* c *) {$X}'];
  Spans := TAtlasBlockComment.Spans(FLines);
  Assert.AreEqual(6, Integer(Length(Spans)));
  Assert.AreEqual(Ord(TAtlasCommentSpanKind.StringLiteral), Ord(Spans[0].Kind));
  Assert.AreEqual(Ord(TAtlasCommentSpanKind.StringLiteral), Ord(Spans[1].Kind));
  Assert.AreEqual(35, Spans[1].EndPos.Character, 'doppeltes Hochkomma im String');
  Assert.AreEqual(Ord(TAtlasCommentSpanKind.LineComment), Ord(Spans[2].Kind));
  Assert.AreEqual(Ord(TAtlasCommentSpanKind.BraceComment), Ord(Spans[3].Kind));
  Assert.AreEqual(2, Spans[3].EndPos.Line);
  Assert.AreEqual(3, Spans[3].EndPos.Character);
  Assert.AreEqual(Ord(TAtlasCommentSpanKind.ParenComment), Ord(Spans[4].Kind));
  Assert.AreEqual(Ord(TAtlasCommentSpanKind.Directive), Ord(Spans[5].Kind));
end;

procedure TAtlasBlockCommentTests.SettingValues;
begin
  Assert.AreEqual(Ord(TAtlasBlockCommentStyle.Parens), Ord(TAtlasBlockComment.StyleOf('parens')));
  Assert.AreEqual(Ord(TAtlasBlockCommentStyle.Braces), Ord(TAtlasBlockComment.StyleOf('braces')));
  Assert.AreEqual(Ord(TAtlasBlockCommentStyle.Braces), Ord(TAtlasBlockComment.StyleOf('x')));
  Assert.AreEqual(Ord(TAtlasBlockCommentFallback.Refuse), Ord(TAtlasBlockComment.FallbackOf('refuse')));
  Assert.AreEqual(Ord(TAtlasBlockCommentFallback.LineComments), Ord(TAtlasBlockComment.FallbackOf('lineComments')));
  Assert.AreEqual(Ord(TAtlasBlockCommentScope.Line), Ord(TAtlasBlockComment.ScopeOf('line')));
  Assert.AreEqual(Ord(TAtlasBlockCommentScope.Statement), Ord(TAtlasBlockComment.ScopeOf('statement')));
end;

end.
