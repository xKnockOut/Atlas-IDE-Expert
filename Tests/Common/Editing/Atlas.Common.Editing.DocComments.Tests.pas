unit Atlas.Common.Editing.DocComments.Tests;

// Tests für das Gerüst von Dokumentationskommentaren (#88).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDocCommentsTests = class
  public
    [Test]
    procedure FunctionWithGenericsAndParams;
    [Test]
    procedure ProcedureAndConstructor;
    [Test]
    procedure PropertyAndTypeOnlySummary;
    [Test]
    procedure AfterThirdSlash;
    [Test]
    procedure NothingWhenAlreadyDocumented;
    [Test]
    procedure ActionGeneratesComment;
    [Test]
    procedure ActionAddsMissingParam;
    [Test]
    procedure ActionMarksStaleParam;
    [Test]
    procedure ActionMarksMultilineStaleParam;
    [Test]
    procedure ActionMarksRenamedParamAndAddsNew;
    /// <summary>"///" über TFoo.Bar im implementation-Teil: Gerüst an der Deklaration, "///" weg.</summary>
    [Test]
    procedure SlashAboveImplementationGoesToDeclaration;
    /// <summary>Überladungen nach Parameternamen; geschachtelte Klassen über den ganzen Pfad.</summary>
    [Test]
    procedure SlashAboveImplementationFindsOverloadAndNested;
    /// <summary>Deklaration schon dokumentiert oder unbekannt: nichts bzw. Gerüst an Ort und Stelle.</summary>
    [Test]
    procedure SlashAboveImplementationKeepsDocumentedAndFallsBack;
    /// <summary>Gerüst und Aktionen stehen über den Attributen der Deklaration.</summary>
    [Test]
    procedure CommentGoesAboveAttributes;
    /// <summary>„Parameter abgleichen“ auf jeder Zeile des Blocks; ohne Abweichung nichts.</summary>
    [Test]
    procedure AdjustBlockFromInsideComment;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.DocComments;

const
  cSource =
    'unit U;'#10 +                                                               // 0
    'interface'#10 +                                                             // 1
    'type'#10 +                                                                  // 2
    '  TFoo = class'#10 +                                                        // 3
    '  public'#10 +                                                              // 4
    '    %s'#10 +                                                                // 5
    '    function Foo<T>(const A: Integer; out B: string): Boolean;'#10 +        // 6
    '    procedure Bar;'#10 +                                                    // 7
    '    constructor Create(AOwner: TComponent);'#10 +                           // 8
    '    property Name: string read FName;'#10 +                                 // 9
    '  end;'#10 +                                                                // 10
    'implementation'#10 +                                                        // 11
    'end.';

function Lines(const AText: string): TArray<string>;
var
  mIndex, mStart: Integer;
begin
  Result := nil;
  mStart := 1;
  for mIndex := 1 to Length(AText) + 1 do
  begin
    if (mIndex > Length(AText)) or (AText[mIndex] = #10) then
    begin
      Result := Result + [Copy(AText, mStart, mIndex - mStart)];
      mStart := mIndex + 1;
    end;
  end;
end;

function Joined(const ALines: TArray<string>): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in ALines do
  begin
    Result := Result + mLine + '|';
  end;
end;

function SkeletonAt(ALine: Integer): string;
begin
  Result := Joined(TDocComments.Skeleton(TDocComments.Signature(Lines(Format(cSource, [''])), ALine), ''));
end;

procedure TDocCommentsTests.FunctionWithGenericsAndParams;
begin
  Assert.AreEqual('/// <summary></summary>|/// <typeparam name="T"></typeparam>|/// <param name="A"></param>|' +
    '/// <param name="B"></param>|/// <returns></returns>|', SkeletonAt(6));
end;

procedure TDocCommentsTests.ProcedureAndConstructor;
begin
  Assert.AreEqual('/// <summary></summary>|', SkeletonAt(7));
  Assert.AreEqual('/// <summary></summary>|/// <param name="AOwner"></param>|', SkeletonAt(8));
end;

procedure TDocCommentsTests.PropertyAndTypeOnlySummary;
begin
  Assert.AreEqual('/// <summary></summary>|', SkeletonAt(9));
  Assert.AreEqual('/// <summary></summary>|', SkeletonAt(3));
end;

procedure TDocCommentsTests.AfterThirdSlash;
var
  mText: string;
  mTree: TSyntaxTree;
  mEdit: TRuleEdit;
begin
  mText := Format(cSource, ['///']);
  mTree := TPascalParser.Parse(mText);
  try
    Assert.IsTrue(TDocComments.AfterSlash(mText, mTree, TTextPosition.Create(5, 7), mEdit));
    Assert.AreEqual(5, mEdit.Range.StartPos.Line);
    Assert.AreEqual(7, mEdit.Range.EndPos.Character);
    Assert.AreEqual('    /// <summary></summary>'#10'    /// <typeparam name="T"></typeparam>'#10 +
      '    /// <param name="A"></param>'#10'    /// <param name="B"></param>'#10'    /// <returns></returns>',
      mEdit.NewText);
    // Unter "end;" steht keine Deklaration.
    Assert.IsFalse(TDocComments.AfterSlash(mText, mTree, TTextPosition.Create(10, 0), mEdit));
  finally
    mTree.Free;
  end;
end;

procedure TDocCommentsTests.NothingWhenAlreadyDocumented;
var
  mText: string;
  mTree: TSyntaxTree;
  mEdit: TRuleEdit;
begin
  mText := StringReplace(Format(cSource, ['///']), '  public'#10, '  public'#10'    /// <summary>X</summary>'#10, []);
  mTree := TPascalParser.Parse(mText);
  try
    Assert.IsFalse(TDocComments.AfterSlash(mText, mTree, TTextPosition.Create(6, 7), mEdit));
  finally
    mTree.Free;
  end;
end;

function ActionsAt(const AText: string; ALine: Integer): TArray<TCodeAction>;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := TDocComments.Actions(AText, mTree, ALine);
  finally
    mTree.Free;
  end;
end;

procedure TDocCommentsTests.ActionGeneratesComment;
var
  mFound: TArray<TCodeAction>;
begin
  mFound := ActionsAt(Format(cSource, ['']), 8);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Dokumentationskommentar erzeugen', mFound[0].Title);
  Assert.AreEqual('    /// <summary></summary>'#10'    /// <param name="AOwner"></param>'#10,
    mFound[0].Edits[0].NewText);
  // Im Rumpf einer Routine und auf "end;" keine Aktion.
  Assert.AreEqual(0, Integer(Length(ActionsAt(Format(cSource, ['']), 10))));
end;

procedure TDocCommentsTests.ActionAddsMissingParam;
var
  mText: string;
  mFound: TArray<TCodeAction>;
begin
  mText := StringReplace(Format(cSource, ['/// <summary>F</summary>']), '    function Foo',
    '    /// <param name="A">a</param>'#10'    function Foo', []);
  // Zeile 5 Summary, 6 param A, 7 Foo.
  mFound := ActionsAt(mText, 7);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Fehlende <param> ergänzen', mFound[0].Title);
  Assert.AreEqual(1, Integer(Length(mFound[0].Edits)));
  Assert.AreEqual(7, mFound[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual('    /// <param name="B"></param>'#10, mFound[0].Edits[0].NewText);
  // Passt alles, gibt es keine Aktion.
  mText := StringReplace(mText, '<param name="A">a</param>', '<param name="A">a</param>'#10 +
    '    /// <param name="B">b</param>', []);
  Assert.AreEqual(0, Integer(Length(ActionsAt(mText, 8))));
end;

procedure TDocCommentsTests.ActionMarksStaleParam;
var
  mText: string;
  mFound: TArray<TCodeAction>;
begin
  mText := StringReplace(Format(cSource, ['/// <summary>F</summary>']), '    procedure Bar',
    '    /// <param name="Alt">a -- b</param>'#10'    procedure Bar', []);
  mFound := ActionsAt(mText, 8);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Dokumentation an die Signatur anpassen', mFound[0].Title);
  Assert.AreEqual(1, Integer(Length(mFound[0].Edits)));
  // Nicht gelöscht, sondern markiert; die Beschreibung bleibt, "--" wird ersetzt.
  Assert.AreEqual('<!-- entfernt: Alt: a – b -->', mFound[0].Edits[0].NewText);
  Assert.AreEqual(7, mFound[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(8, mFound[0].Edits[0].Range.StartPos.Character);
  Assert.AreEqual(7, mFound[0].Edits[0].Range.EndPos.Line);
  Assert.AreEqual(Length('    /// <param name="Alt">a -- b</param>'), mFound[0].Edits[0].Range.EndPos.Character);
  // Markierte Zeilen zählen nicht mehr als Parameter: danach passt alles.
  mText := StringReplace(mText, '<param name="Alt">a -- b</param>', '<!-- entfernt: Alt: a – b -->', []);
  Assert.AreEqual(0, Integer(Length(ActionsAt(mText, 8))));
  // Ohne Beschreibung nur der Name.
  mText := StringReplace(mText, '<!-- entfernt: Alt: a – b -->', '<param name="Alt"></param>', []);
  Assert.AreEqual('<!-- entfernt: Alt -->', ActionsAt(mText, 8)[0].Edits[0].NewText);
end;

procedure TDocCommentsTests.ActionMarksMultilineStaleParam;
var
  mText: string;
  mFound: TArray<TCodeAction>;
begin
  mText := StringReplace(Format(cSource, ['/// <summary>F</summary>']), '    procedure Bar',
    '    /// <param name="Alt">'#10'    ///   a'#10'    /// </param>'#10'    procedure Bar', []);
  // Zeilen 7 bis 9 Kommentar, 10 Bar.
  mFound := ActionsAt(mText, 10);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(2, Integer(Length(mFound[0].Edits)));
  Assert.AreEqual('<!-- entfernt: Alt:', mFound[0].Edits[0].NewText);
  Assert.AreEqual(7, mFound[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual('-->', mFound[0].Edits[1].NewText);
  Assert.AreEqual(9, mFound[0].Edits[1].Range.StartPos.Line);
  Assert.AreEqual(8, mFound[0].Edits[1].Range.StartPos.Character);
end;

procedure TDocCommentsTests.ActionMarksRenamedParamAndAddsNew;
var
  mText: string;
  mFound: TArray<TCodeAction>;
begin
  // Foo hat A und B; der Kommentar kennt noch "Alt" statt "A".
  mText := StringReplace(Format(cSource, ['/// <summary>F</summary>']), '    function Foo',
    '    /// <param name="Alt">a</param>'#10'    /// <param name="B">b</param>'#10'    function Foo', []);
  mFound := ActionsAt(mText, 8);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(2, Integer(Length(mFound[0].Edits)));
  Assert.AreEqual('<!-- entfernt: Alt: a -->', mFound[0].Edits[0].NewText);
  Assert.AreEqual(8, mFound[0].Edits[1].Range.StartPos.Line);
  Assert.AreEqual('    /// <param name="A"></param>'#10, mFound[0].Edits[1].NewText);
end;

const
  cMethodSource =
    'unit U;'#10 +                                                               // 0
    'interface'#10 +                                                             // 1
    'type'#10 +                                                                  // 2
    '  TFoo = class'#10 +                                                        // 3
    '  public type'#10 +                                                         // 4
    '    TInner = class'#10 +                                                    // 5
    '      function Calc(ARate: Double): Currency;'#10 +                         // 6
    '    end;'#10 +                                                              // 7
    '  public'#10 +                                                              // 8
    '%s' +                                                                       // 9 ...
    '    procedure Bar(A, B: Integer); overload;'#10 +                           // 9
    '    procedure Bar(const S: string); overload;'#10 +                         // 10
    '  end;'#10 +                                                                // 11
    'implementation'#10 +                                                        // 12
    '%s'#10 +                                                                    // 13
    '%s'#10 +                                                                    // 14
    'begin'#10 +
    'end;'#10 +
    'end.';

function SlashEdits(const AText: string; ALine: Integer; out AEdits: TArray<TRuleEdit>): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := TDocComments.AfterSlash(AText, mTree, TTextPosition.Create(ALine, 3), AEdits);
  finally
    mTree.Free;
  end;
end;

procedure TDocCommentsTests.SlashAboveImplementationGoesToDeclaration;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(SlashEdits(Format(cMethodSource, ['', '///', 'procedure TFoo.Bar(A, B: Integer);']), 13, mEdits));
  Assert.AreEqual(2, Integer(Length(mEdits)));
  // Gerüst vor der Deklaration in der Klasse, mit deren Einrückung.
  Assert.AreEqual(9, mEdits[0].Range.StartPos.Line);
  Assert.AreEqual(9, mEdits[0].Range.EndPos.Line);
  Assert.AreEqual(0, mEdits[0].Range.EndPos.Character);
  Assert.AreEqual('    /// <summary></summary>'#10'    /// <param name="A"></param>'#10 +
    '    /// <param name="B"></param>'#10, mEdits[0].NewText);
  // Die Zeile mit "///" fällt weg.
  Assert.AreEqual(13, mEdits[1].Range.StartPos.Line);
  Assert.AreEqual(14, mEdits[1].Range.EndPos.Line);
  Assert.AreEqual(0, mEdits[1].Range.EndPos.Character);
  Assert.AreEqual('', mEdits[1].NewText);
end;

procedure TDocCommentsTests.SlashAboveImplementationFindsOverloadAndNested;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(SlashEdits(Format(cMethodSource, ['', '///', 'procedure TFoo.Bar(const S: string);']), 13, mEdits));
  Assert.AreEqual(10, mEdits[0].Range.StartPos.Line);
  Assert.AreEqual('    /// <summary></summary>'#10'    /// <param name="S"></param>'#10, mEdits[0].NewText);
  Assert.IsTrue(SlashEdits(Format(cMethodSource, ['', '///', 'function TFoo.TInner.Calc(ARate: Double): Currency;']),
    13, mEdits));
  Assert.AreEqual(6, mEdits[0].Range.StartPos.Line);
  Assert.AreEqual('      /// <summary></summary>'#10'      /// <param name="ARate"></param>'#10 +
    '      /// <returns></returns>'#10, mEdits[0].NewText);
end;

procedure TDocCommentsTests.SlashAboveImplementationKeepsDocumentedAndFallsBack;
var
  mEdits: TArray<TRuleEdit>;
begin
  // Die Deklaration hat schon einen Kommentar: "///" bleibt, wie getippt.
  Assert.IsFalse(SlashEdits(Format(cMethodSource, ['    /// <summary>B</summary>'#10, '///',
    'procedure TFoo.Bar(A, B: Integer);']), 14, mEdits));
  Assert.AreEqual(0, Integer(Length(mEdits)));
  // Ohne Deklaration (freie Routine, unbekannte Klasse): Gerüst an Ort und Stelle.
  Assert.IsTrue(SlashEdits(Format(cMethodSource, ['', '///', 'procedure Frei(X: Integer);']), 13, mEdits));
  Assert.AreEqual(1, Integer(Length(mEdits)));
  Assert.AreEqual(13, mEdits[0].Range.StartPos.Line);
  Assert.AreEqual('/// <summary></summary>'#10'/// <param name="X"></param>', mEdits[0].NewText);
  Assert.IsTrue(SlashEdits(Format(cMethodSource, ['', '///', 'procedure TAnders.Bar(X: Integer);']), 13, mEdits));
  Assert.AreEqual(1, Integer(Length(mEdits)));
end;

procedure TDocCommentsTests.CommentGoesAboveAttributes;
var
  mText: string;
  mEdits: TArray<TRuleEdit>;
  mFound: TArray<TCodeAction>;
begin
  mText := Format(cMethodSource, ['    [Test]'#10, '///', 'procedure TFoo.Bar(A, B: Integer);']);
  // Zeile 9 [Test], 10 Bar, 14 "///".
  Assert.IsTrue(SlashEdits(mText, 14, mEdits));
  Assert.AreEqual(9, mEdits[0].Range.StartPos.Line);
  mFound := ActionsAt(mText, 10);
  Assert.AreEqual('Dokumentationskommentar erzeugen', mFound[0].Title);
  Assert.AreEqual(9, mFound[0].Edits[0].Range.StartPos.Line);
  // Kommentar über dem Attribut zählt als Kommentar der Deklaration.
  mText := Format(cMethodSource, ['    /// <summary>B</summary>'#10'    [Test]'#10, '///',
    'procedure TFoo.Bar(A, B: Integer);']);
  Assert.IsFalse(SlashEdits(mText, 15, mEdits));
  mFound := ActionsAt(mText, 11);
  Assert.AreEqual('Fehlende <param> ergänzen', mFound[0].Title);
end;

procedure TDocCommentsTests.AdjustBlockFromInsideComment;
var
  mText: string;
  mTree: TSyntaxTree;
  mAction: TCodeAction;
begin
  mText := Format(cMethodSource, ['    /// <summary>B</summary>'#10'    /// <param name="Alt">a</param>'#10, '', '']);
  // Zeilen 9 und 10 Kommentar, 11 Bar(A, B).
  mTree := TPascalParser.Parse(mText);
  try
    Assert.IsTrue(TDocComments.AdjustBlock(mText, mTree, 9, mAction));
    Assert.AreEqual('Parameter abgleichen', mAction.Title);
    Assert.AreEqual(2, Integer(Length(mAction.Edits)));
    Assert.AreEqual('<!-- entfernt: Alt: a -->', mAction.Edits[0].NewText);
    Assert.AreEqual('    /// <param name="A"></param>'#10'    /// <param name="B"></param>'#10,
      mAction.Edits[1].NewText);
    Assert.IsTrue(TDocComments.AdjustBlock(mText, mTree, 10, mAction));
    // Außerhalb des Blocks nichts.
    Assert.IsFalse(TDocComments.AdjustBlock(mText, mTree, 11, mAction));
    Assert.IsFalse(TDocComments.AdjustBlock(mText, mTree, 8, mAction));
  finally
    mTree.Free;
  end;
  // Passt der Block schon, gibt es nichts abzugleichen.
  mText := Format(cMethodSource, ['    /// <summary>B</summary>'#10'    /// <param name="A">a</param>'#10 +
    '    /// <param name="B">b</param>'#10, '', '']);
  mTree := TPascalParser.Parse(mText);
  try
    Assert.IsFalse(TDocComments.AdjustBlock(mText, mTree, 9, mAction));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDocCommentsTests);

end.
