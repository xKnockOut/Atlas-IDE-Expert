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
  Source =
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
  Index, Start: Integer;
begin
  Result := nil;
  Start := 1;
  for Index := 1 to Length(AText) + 1 do
    if (Index > Length(AText)) or (AText[Index] = #10) then
    begin
      Result := Result + [Copy(AText, Start, Index - Start)];
      Start := Index + 1;
    end;
end;

function Joined(const ALines: TArray<string>): string;
var
  Line: string;
begin
  Result := '';
  for Line in ALines do
    Result := Result + Line + '|';
end;

function SkeletonAt(ALine: Integer): string;
begin
  Result := Joined(TDocComments.Skeleton(TDocComments.Signature(Lines(Format(Source, [''])), ALine), ''));
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
  Text: string;
  Tree: TSyntaxTree;
  Edit: TRuleEdit;
begin
  Text := Format(Source, ['///']);
  Tree := TPascalParser.Parse(Text);
  try
    Assert.IsTrue(TDocComments.AfterSlash(Text, Tree, TTextPosition.Create(5, 7), Edit));
    Assert.AreEqual(5, Edit.Range.StartPos.Line);
    Assert.AreEqual(7, Edit.Range.EndPos.Character);
    Assert.AreEqual('    /// <summary></summary>'#10'    /// <typeparam name="T"></typeparam>'#10 +
      '    /// <param name="A"></param>'#10'    /// <param name="B"></param>'#10'    /// <returns></returns>',
      Edit.NewText);
    // Unter "end;" steht keine Deklaration.
    Assert.IsFalse(TDocComments.AfterSlash(Text, Tree, TTextPosition.Create(10, 0), Edit));
  finally
    Tree.Free;
  end;
end;

procedure TDocCommentsTests.NothingWhenAlreadyDocumented;
var
  Text: string;
  Tree: TSyntaxTree;
  Edit: TRuleEdit;
begin
  Text := StringReplace(Format(Source, ['///']), '  public'#10, '  public'#10'    /// <summary>X</summary>'#10, []);
  Tree := TPascalParser.Parse(Text);
  try
    Assert.IsFalse(TDocComments.AfterSlash(Text, Tree, TTextPosition.Create(6, 7), Edit));
  finally
    Tree.Free;
  end;
end;

function ActionsAt(const AText: string; ALine: Integer): TArray<TCodeAction>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TDocComments.Actions(AText, Tree, ALine);
  finally
    Tree.Free;
  end;
end;

procedure TDocCommentsTests.ActionGeneratesComment;
var
  Found: TArray<TCodeAction>;
begin
  Found := ActionsAt(Format(Source, ['']), 8);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Dokumentationskommentar erzeugen', Found[0].Title);
  Assert.AreEqual('    /// <summary></summary>'#10'    /// <param name="AOwner"></param>'#10,
    Found[0].Edits[0].NewText);
  // Im Rumpf einer Routine und auf "end;" keine Aktion.
  Assert.AreEqual(0, Integer(Length(ActionsAt(Format(Source, ['']), 10))));
end;

procedure TDocCommentsTests.ActionAddsMissingParam;
var
  Text: string;
  Found: TArray<TCodeAction>;
begin
  Text := StringReplace(Format(Source, ['/// <summary>F</summary>']), '    function Foo',
    '    /// <param name="A">a</param>'#10'    function Foo', []);
  // Zeile 5 Summary, 6 param A, 7 Foo.
  Found := ActionsAt(Text, 7);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Fehlende <param> ergänzen', Found[0].Title);
  Assert.AreEqual(1, Integer(Length(Found[0].Edits)));
  Assert.AreEqual(7, Found[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual('    /// <param name="B"></param>'#10, Found[0].Edits[0].NewText);
  // Passt alles, gibt es keine Aktion.
  Text := StringReplace(Text, '<param name="A">a</param>', '<param name="A">a</param>'#10 +
    '    /// <param name="B">b</param>', []);
  Assert.AreEqual(0, Integer(Length(ActionsAt(Text, 8))));
end;

procedure TDocCommentsTests.ActionMarksStaleParam;
var
  Text: string;
  Found: TArray<TCodeAction>;
begin
  Text := StringReplace(Format(Source, ['/// <summary>F</summary>']), '    procedure Bar',
    '    /// <param name="Alt">a -- b</param>'#10'    procedure Bar', []);
  Found := ActionsAt(Text, 8);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Dokumentation an die Signatur anpassen', Found[0].Title);
  Assert.AreEqual(1, Integer(Length(Found[0].Edits)));
  // Nicht gelöscht, sondern markiert; die Beschreibung bleibt, "--" wird ersetzt.
  Assert.AreEqual('<!-- entfernt: Alt: a – b -->', Found[0].Edits[0].NewText);
  Assert.AreEqual(7, Found[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(8, Found[0].Edits[0].Range.StartPos.Character);
  Assert.AreEqual(7, Found[0].Edits[0].Range.EndPos.Line);
  Assert.AreEqual(Length('    /// <param name="Alt">a -- b</param>'), Found[0].Edits[0].Range.EndPos.Character);
  // Markierte Zeilen zählen nicht mehr als Parameter: danach passt alles.
  Text := StringReplace(Text, '<param name="Alt">a -- b</param>', '<!-- entfernt: Alt: a – b -->', []);
  Assert.AreEqual(0, Integer(Length(ActionsAt(Text, 8))));
  // Ohne Beschreibung nur der Name.
  Text := StringReplace(Text, '<!-- entfernt: Alt: a – b -->', '<param name="Alt"></param>', []);
  Assert.AreEqual('<!-- entfernt: Alt -->', ActionsAt(Text, 8)[0].Edits[0].NewText);
end;

procedure TDocCommentsTests.ActionMarksMultilineStaleParam;
var
  Text: string;
  Found: TArray<TCodeAction>;
begin
  Text := StringReplace(Format(Source, ['/// <summary>F</summary>']), '    procedure Bar',
    '    /// <param name="Alt">'#10'    ///   a'#10'    /// </param>'#10'    procedure Bar', []);
  // Zeilen 7 bis 9 Kommentar, 10 Bar.
  Found := ActionsAt(Text, 10);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(2, Integer(Length(Found[0].Edits)));
  Assert.AreEqual('<!-- entfernt: Alt:', Found[0].Edits[0].NewText);
  Assert.AreEqual(7, Found[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual('-->', Found[0].Edits[1].NewText);
  Assert.AreEqual(9, Found[0].Edits[1].Range.StartPos.Line);
  Assert.AreEqual(8, Found[0].Edits[1].Range.StartPos.Character);
end;

procedure TDocCommentsTests.ActionMarksRenamedParamAndAddsNew;
var
  Text: string;
  Found: TArray<TCodeAction>;
begin
  // Foo hat A und B; der Kommentar kennt noch "Alt" statt "A".
  Text := StringReplace(Format(Source, ['/// <summary>F</summary>']), '    function Foo',
    '    /// <param name="Alt">a</param>'#10'    /// <param name="B">b</param>'#10'    function Foo', []);
  Found := ActionsAt(Text, 8);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(2, Integer(Length(Found[0].Edits)));
  Assert.AreEqual('<!-- entfernt: Alt: a -->', Found[0].Edits[0].NewText);
  Assert.AreEqual(8, Found[0].Edits[1].Range.StartPos.Line);
  Assert.AreEqual('    /// <param name="A"></param>'#10, Found[0].Edits[1].NewText);
end;

const
  MethodSource =
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
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TDocComments.AfterSlash(AText, Tree, TTextPosition.Create(ALine, 3), AEdits);
  finally
    Tree.Free;
  end;
end;

procedure TDocCommentsTests.SlashAboveImplementationGoesToDeclaration;
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(SlashEdits(Format(MethodSource, ['', '///', 'procedure TFoo.Bar(A, B: Integer);']), 13, Edits));
  Assert.AreEqual(2, Integer(Length(Edits)));
  // Gerüst vor der Deklaration in der Klasse, mit deren Einrückung.
  Assert.AreEqual(9, Edits[0].Range.StartPos.Line);
  Assert.AreEqual(9, Edits[0].Range.EndPos.Line);
  Assert.AreEqual(0, Edits[0].Range.EndPos.Character);
  Assert.AreEqual('    /// <summary></summary>'#10'    /// <param name="A"></param>'#10 +
    '    /// <param name="B"></param>'#10, Edits[0].NewText);
  // Die Zeile mit "///" fällt weg.
  Assert.AreEqual(13, Edits[1].Range.StartPos.Line);
  Assert.AreEqual(14, Edits[1].Range.EndPos.Line);
  Assert.AreEqual(0, Edits[1].Range.EndPos.Character);
  Assert.AreEqual('', Edits[1].NewText);
end;

procedure TDocCommentsTests.SlashAboveImplementationFindsOverloadAndNested;
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(SlashEdits(Format(MethodSource, ['', '///', 'procedure TFoo.Bar(const S: string);']), 13, Edits));
  Assert.AreEqual(10, Edits[0].Range.StartPos.Line);
  Assert.AreEqual('    /// <summary></summary>'#10'    /// <param name="S"></param>'#10, Edits[0].NewText);
  Assert.IsTrue(SlashEdits(Format(MethodSource, ['', '///', 'function TFoo.TInner.Calc(ARate: Double): Currency;']),
    13, Edits));
  Assert.AreEqual(6, Edits[0].Range.StartPos.Line);
  Assert.AreEqual('      /// <summary></summary>'#10'      /// <param name="ARate"></param>'#10 +
    '      /// <returns></returns>'#10, Edits[0].NewText);
end;

procedure TDocCommentsTests.SlashAboveImplementationKeepsDocumentedAndFallsBack;
var
  Edits: TArray<TRuleEdit>;
begin
  // Die Deklaration hat schon einen Kommentar: "///" bleibt, wie getippt.
  Assert.IsFalse(SlashEdits(Format(MethodSource, ['    /// <summary>B</summary>'#10, '///',
    'procedure TFoo.Bar(A, B: Integer);']), 14, Edits));
  Assert.AreEqual(0, Integer(Length(Edits)));
  // Ohne Deklaration (freie Routine, unbekannte Klasse): Gerüst an Ort und Stelle.
  Assert.IsTrue(SlashEdits(Format(MethodSource, ['', '///', 'procedure Frei(X: Integer);']), 13, Edits));
  Assert.AreEqual(1, Integer(Length(Edits)));
  Assert.AreEqual(13, Edits[0].Range.StartPos.Line);
  Assert.AreEqual('/// <summary></summary>'#10'/// <param name="X"></param>', Edits[0].NewText);
  Assert.IsTrue(SlashEdits(Format(MethodSource, ['', '///', 'procedure TAnders.Bar(X: Integer);']), 13, Edits));
  Assert.AreEqual(1, Integer(Length(Edits)));
end;

procedure TDocCommentsTests.CommentGoesAboveAttributes;
var
  Text: string;
  Edits: TArray<TRuleEdit>;
  Found: TArray<TCodeAction>;
begin
  Text := Format(MethodSource, ['    [Test]'#10, '///', 'procedure TFoo.Bar(A, B: Integer);']);
  // Zeile 9 [Test], 10 Bar, 14 "///".
  Assert.IsTrue(SlashEdits(Text, 14, Edits));
  Assert.AreEqual(9, Edits[0].Range.StartPos.Line);
  Found := ActionsAt(Text, 10);
  Assert.AreEqual('Dokumentationskommentar erzeugen', Found[0].Title);
  Assert.AreEqual(9, Found[0].Edits[0].Range.StartPos.Line);
  // Kommentar über dem Attribut zählt als Kommentar der Deklaration.
  Text := Format(MethodSource, ['    /// <summary>B</summary>'#10'    [Test]'#10, '///',
    'procedure TFoo.Bar(A, B: Integer);']);
  Assert.IsFalse(SlashEdits(Text, 15, Edits));
  Found := ActionsAt(Text, 11);
  Assert.AreEqual('Fehlende <param> ergänzen', Found[0].Title);
end;

procedure TDocCommentsTests.AdjustBlockFromInsideComment;
var
  Text: string;
  Tree: TSyntaxTree;
  Action: TCodeAction;
begin
  Text := Format(MethodSource, ['    /// <summary>B</summary>'#10'    /// <param name="Alt">a</param>'#10, '', '']);
  // Zeilen 9 und 10 Kommentar, 11 Bar(A, B).
  Tree := TPascalParser.Parse(Text);
  try
    Assert.IsTrue(TDocComments.AdjustBlock(Text, Tree, 9, Action));
    Assert.AreEqual('Parameter abgleichen', Action.Title);
    Assert.AreEqual(2, Integer(Length(Action.Edits)));
    Assert.AreEqual('<!-- entfernt: Alt: a -->', Action.Edits[0].NewText);
    Assert.AreEqual('    /// <param name="A"></param>'#10'    /// <param name="B"></param>'#10, Action.Edits[1].NewText);
    Assert.IsTrue(TDocComments.AdjustBlock(Text, Tree, 10, Action));
    // Außerhalb des Blocks nichts.
    Assert.IsFalse(TDocComments.AdjustBlock(Text, Tree, 11, Action));
    Assert.IsFalse(TDocComments.AdjustBlock(Text, Tree, 8, Action));
  finally
    Tree.Free;
  end;
  // Passt der Block schon, gibt es nichts abzugleichen.
  Text := Format(MethodSource, ['    /// <summary>B</summary>'#10'    /// <param name="A">a</param>'#10 +
    '    /// <param name="B">b</param>'#10, '', '']);
  Tree := TPascalParser.Parse(Text);
  try
    Assert.IsFalse(TDocComments.AdjustBlock(Text, Tree, 9, Action));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDocCommentsTests);

end.
