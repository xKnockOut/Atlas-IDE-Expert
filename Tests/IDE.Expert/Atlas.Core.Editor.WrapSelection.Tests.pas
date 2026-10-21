unit Atlas.Core.Editor.WrapSelection.Tests;

// Markierung beim Tippen umschließen (#672): jedes Zeichen, Hochkommas
// verdoppeln, Blockkommentar über ganze Zeilen und Ausweichen auf (* *),
// kein Umschließen in Strings, < nur hinter Typnamen, mehrere Bereiche.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Editor.WrapSelection;

type
  [TestFixture]
  TAtlasWrapSelectionTests = class
  private
    FResult: TAtlasWrapResult;
    function Wrap(const ALines: TArray<string>; ALine, AStart, AStop: Integer; AOpen: Char): Boolean; overload;
    function Wrap(const ALines: TArray<string>; ALine, AStart, AStop: Integer; AOpen: Char;
      const AChars: string): Boolean; overload;
    function Selection(AIndex: Integer): string;
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure WrapsWithBracketsAndKeepsSelection;
    [Test]
    procedure QuoteDoublesInnerQuotes;
    [Test]
    procedure NoQuoteWrapInStringOrOverLines;
    [Test]
    procedure BraceInline;
    [Test]
    procedure BraceOnWholeLines;
    [Test]
    procedure BraceFallsBackToParenStar;
    [Test]
    procedure AngleOnlyAfterTypeNameAndWhenConfigured;
    [Test]
    procedure OtherCharsAndEmptySelection;
    [Test]
    procedure SeveralRanges;
    [Test]
    procedure NormalizeChars;
  end;

implementation

uses
  System.SysUtils;

procedure TAtlasWrapSelectionTests.TearDown;
begin
  FResult := Default(TAtlasWrapResult);
end;

function TAtlasWrapSelectionTests.Wrap(const ALines: TArray<string>; ALine, AStart, AStop: Integer;
  AOpen: Char): Boolean;
begin
  Result := Wrap(ALines, ALine, AStart, AStop, AOpen, TAtlasWrapSelection.DefaultChars);
end;

function TAtlasWrapSelectionTests.Wrap(const ALines: TArray<string>; ALine, AStart, AStop: Integer; AOpen: Char;
  const AChars: string): Boolean;
begin
  Result := TAtlasWrapSelection.Wrap(ALines, TLspRange.Create(ALine, AStart, ALine, AStop), AOpen, AChars, FResult);
end;

function TAtlasWrapSelectionTests.Selection(AIndex: Integer): string;
var
  Range: TLspRange;
begin
  Range := FResult.Selections[AIndex];
  Result := Format('%d:%d-%d:%d', [Range.StartPos.Line, Range.StartPos.Character, Range.EndPos.Line,
    Range.EndPos.Character]);
end;

procedure TAtlasWrapSelectionTests.WrapsWithBracketsAndKeepsSelection;
var
  First: TAtlasWrapResult;
begin
  Assert.IsTrue(Wrap(['X := A + B;'], 0, 5, 10, '('));
  Assert.AreEqual('X := (A + B);', FResult.Lines[0]);
  Assert.AreEqual('0:6-0:11', Selection(0), 'Markierung auf dem alten Text');
  // Zweites Zeichen umschließt weiter (out leert FResult: eigene Kopie übergeben).
  First := FResult;
  Assert.IsTrue(TAtlasWrapSelection.Wrap(First.Lines, First.Selections[0], '(',
    TAtlasWrapSelection.DefaultChars, FResult));
  Assert.AreEqual('X := ((A + B));', FResult.Lines[0]);
  Assert.IsTrue(Wrap(['Werte'], 0, 0, 5, '['));
  Assert.AreEqual('[Werte]', FResult.Lines[0]);
  Assert.AreEqual('0:1-0:6', Selection(0));
  // Rückwärts markiert.
  Assert.IsTrue(TAtlasWrapSelection.Wrap(['A + B'], TLspRange.Create(0, 5, 0, 0), '(',
    TAtlasWrapSelection.DefaultChars, FResult));
  Assert.AreEqual('(A + B)', FResult.Lines[0]);
end;

procedure TAtlasWrapSelectionTests.QuoteDoublesInnerQuotes;
begin
  Assert.IsTrue(Wrap(['S := It''s;'], 0, 5, 9, ''''));
  Assert.AreEqual('S := ''It''''s'';', FResult.Lines[0]);
  Assert.AreEqual('0:6-0:11', Selection(0), 'Markierung auf It''''s');
  // Eine Markierung, die den ganzen String umfasst, beginnt nicht in ihm.
  Assert.IsTrue(Wrap(['''a'''], 0, 0, 3, ''''));
  Assert.AreEqual('''''''a''''''', FResult.Lines[0]);
end;

procedure TAtlasWrapSelectionTests.NoQuoteWrapInStringOrOverLines;
begin
  Assert.IsFalse(Wrap(['S := ''Kunde gespeichert'';'], 0, 12, 23, ''''), 'im String');
  Assert.AreEqual('S := ''Kunde gespeichert'';', FResult.Lines[0], 'Text bleibt');
  Assert.IsFalse(TAtlasWrapSelection.Wrap(['A', 'B'], TLspRange.Create(0, 0, 1, 1), '''',
    TAtlasWrapSelection.DefaultChars, FResult), 'mehrzeilig');
  // Andere Zeichen umschließen auch in Strings.
  Assert.IsTrue(Wrap(['S := ''Kunde gespeichert'';'], 0, 12, 23, '('));
end;

procedure TAtlasWrapSelectionTests.BraceInline;
begin
  Assert.IsTrue(Wrap(['Foo(A, B);'], 0, 7, 8, '{'));
  Assert.AreEqual('Foo(A, {B});', FResult.Lines[0]);
  Assert.AreEqual('0:8-0:9', Selection(0));
  Assert.IsFalse(Wrap(['$IFDEF X'], 0, 0, 3, '{'), 'Direktive');
end;

procedure TAtlasWrapSelectionTests.BraceOnWholeLines;
var
  Lines: TArray<string>;
begin
  Lines := ['begin', '    Foo;', '    Bar;', 'end;'];
  // Bis zum Ende der letzten Zeile.
  Assert.IsTrue(TAtlasWrapSelection.Wrap(Lines, TLspRange.Create(1, 0, 2, 8), '{',
    TAtlasWrapSelection.DefaultChars, FResult));
  Assert.AreEqual('begin|    {|    Foo;|    Bar;|    }|end;', string.Join('|', FResult.Lines));
  Assert.AreEqual('2:0-3:8', Selection(0));
  // Bis zum Anfang der nächsten Zeile, Anfang im Einzug.
  Assert.IsTrue(TAtlasWrapSelection.Wrap(Lines, TLspRange.Create(1, 4, 3, 0), '{',
    TAtlasWrapSelection.DefaultChars, FResult));
  Assert.AreEqual('begin|    {|    Foo;|    Bar;|    }|end;', string.Join('|', FResult.Lines));
  Assert.AreEqual('2:4-4:0', Selection(0));
end;

procedure TAtlasWrapSelectionTests.BraceFallsBackToParenStar;
begin
  Assert.IsTrue(TAtlasWrapSelection.Wrap(['  Foo; { alt }'], TLspRange.Create(0, 0, 0, 14), '{',
    TAtlasWrapSelection.DefaultChars, FResult));
  Assert.AreEqual('  (*|  Foo; { alt }|  *)', string.Join('|', FResult.Lines));
  Assert.IsTrue(Wrap(['A { x } B'], 0, 0, 9, '{'));
  Assert.AreEqual('(*|A { x } B|*)', string.Join('|', FResult.Lines), 'ganze Zeile ohne Einzug');
  Assert.IsTrue(Wrap(['X := A { x } + B;'], 0, 5, 16, '{'));
  Assert.AreEqual('X := (*A { x } + B*);', FResult.Lines[0]);
  Assert.IsFalse(Wrap(['A { x } (* y *) B'], 0, 0, 17, '{'), '} und *)');
end;

procedure TAtlasWrapSelectionTests.AngleOnlyAfterTypeNameAndWhenConfigured;
begin
  Assert.IsFalse(Wrap(['L: TListInteger;'], 0, 8, 15, '<'), '< nicht in den Zeichen');
  Assert.IsTrue(Wrap(['L: TListInteger;'], 0, 8, 15, '<', TAtlasWrapSelection.AllChars));
  Assert.AreEqual('L: TList<Integer>;', FResult.Lines[0]);
  Assert.AreEqual('0:9-0:16', Selection(0));
  Assert.IsFalse(Wrap(['if A B then'], 0, 5, 6, '<', TAtlasWrapSelection.AllChars), 'kein Typname davor');
  Assert.IsFalse(Wrap(['X := 1B;'], 0, 6, 7, '<', TAtlasWrapSelection.AllChars), 'Zahl davor');
  Assert.IsFalse(Wrap(['B'], 0, 0, 1, '<', TAtlasWrapSelection.AllChars), 'Zeilenanfang');
end;

procedure TAtlasWrapSelectionTests.OtherCharsAndEmptySelection;
begin
  Assert.IsFalse(Wrap(['A + B'], 0, 0, 5, 'x'));
  Assert.IsFalse(Wrap(['A + B'], 0, 0, 5, ')'));
  Assert.IsFalse(Wrap(['A + B'], 0, 0, 5, '[', '('), '[ abgewählt');
  Assert.IsFalse(Wrap(['A + B'], 0, 2, 2, '('), 'ohne Markierung tippt die IDE');
  Assert.AreEqual('A + B', FResult.Lines[0]);
end;

procedure TAtlasWrapSelectionTests.SeveralRanges;
var
  Ranges: TArray<TLspRange>;
begin
  // Zwei Marken in einer Zeile, eine ohne Markierung.
  Ranges := [TLspRange.Create(0, 4, 0, 5), TLspRange.Create(0, 0, 0, 1), TLspRange.Create(1, 2, 1, 2)];
  Assert.IsTrue(TAtlasWrapSelection.Wrap(['A + B', 'C D'], Ranges, '(', TAtlasWrapSelection.DefaultChars, FResult));
  Assert.AreEqual('(A) + (B)|C (D', string.Join('|', FResult.Lines));
  Assert.AreEqual('0:7-0:8', Selection(0));
  Assert.AreEqual('0:1-0:2', Selection(1));
  Assert.AreEqual('1:3-1:3', Selection(2));
  // Spaltenblock: je Zeile einzeln, Hochkommas je Zeile verdoppelt.
  Ranges := [TLspRange.Create(0, 2, 0, 5), TLspRange.Create(1, 2, 1, 5)];
  Assert.IsTrue(TAtlasWrapSelection.Wrap(['A abc', 'B d''e'], Ranges, '''', TAtlasWrapSelection.DefaultChars,
    FResult));
  Assert.AreEqual('A ''abc''|B ''d''''e''', string.Join('|', FResult.Lines));
  Assert.AreEqual('1:3-1:7', Selection(1));
  // Ein Bereich lässt sich nicht umschließen: nichts.
  Ranges := [TLspRange.Create(0, 0, 0, 1), TLspRange.Create(1, 7, 1, 8)];
  Assert.IsFalse(TAtlasWrapSelection.Wrap(['A', 'S := ''abc'';'], Ranges, '''', TAtlasWrapSelection.DefaultChars,
    FResult));
  // Überlappend: nichts.
  Ranges := [TLspRange.Create(0, 0, 0, 3), TLspRange.Create(0, 2, 0, 5)];
  Assert.IsFalse(TAtlasWrapSelection.Wrap(['A + B'], Ranges, '(', TAtlasWrapSelection.DefaultChars, FResult));
end;

procedure TAtlasWrapSelectionTests.NormalizeChars;
begin
  Assert.AreEqual('([{''', TAtlasWrapSelection.Normalize('([{''(x)'));
  Assert.AreEqual('<(', TAtlasWrapSelection.Normalize('<a('));
  Assert.AreEqual('', TAtlasWrapSelection.Normalize(''));
  Assert.IsTrue(TAtlasWrapSelection.Accepts('{', '([{'));
  Assert.IsFalse(TAtlasWrapSelection.Accepts('''', '([{'));
  Assert.AreEqual(')', TAtlasWrapSelection.CloserOf('('));
  Assert.AreEqual('>', TAtlasWrapSelection.CloserOf('<'));
end;

end.
