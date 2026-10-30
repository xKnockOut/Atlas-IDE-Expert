unit Atlas.Common.Editing.CodeActions.Tests;

// Tests für Code-Aktionen ohne Protokoll (#42, #147).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCodeActionTests = class
  public
    [Test]
    procedure TryFinallyAfterCreate;
    [Test]
    procedure TryFinallyResultCompilesStructurally;
    [Test]
    procedure NoTryFinallyWhenAlreadyProtected;
    [Test]
    procedure ResultGetsTryExceptInsteadOfFree;
    [Test]
    procedure OrganizeImportsAsSourceAction;
    [Test]
    procedure MatchesRequestedKinds;
    [Test]
    procedure NoTryFinallyWithoutCreate;
    /// <summary>Felder (auch Self.F) bekommen keine Aktion; wem sie gehören, sieht man hier nicht (#42).</summary>
    [Test]
    procedure NoTryFinallyForFields;
    [Test]
    procedure NoTryFinallyWhenNothingFollows;
    /// <summary>Zurückgegeben, an eine Liste übergeben, mittendrin freigegeben, mit Owner oder Interface.</summary>
    [Test]
    procedure NoTryFinallyWhenObjectEscapes;
    [Test]
    procedure TryFinallyEnclosesSelectionOnly;
    [Test]
    procedure TryFinallyEndsWithInnerBlock;
    [Test]
    procedure TryFinallyFollowsFormatStyle;
    /// <summary>Lokale und Inline-Variable, mehrzeiliger Create-Aufruf, vorhandene Freigabe, Result.</summary>
    [Test]
    procedure TryFinallyMatchesGoldenFile;
    [Test]
    procedure SuppressLineInsertsCommentAbove;
    [Test]
    procedure SuppressLineExtendsExistingComment;
    /// <summary>Zeilen auch bei CR allein getrennt (TTextLines.SplitLines, D-03).</summary>
    [Test]
    procedure SuppressLineInCrOnlyText;
    [Test]
    procedure SuppressFileAtTop;
    [Test]
    procedure UnusedSuppressionReportedWithRemoval;
    [Test]
    procedure UsedSuppressionNotReported;
    [Test]
    procedure SuppressionForUnknownRuleNotReported;
    [Test]
    procedure SwapAssignmentsIsRewrite;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Editing.CodeActions,
  Atlas.Tests.RuleAssert;

type
  /// <summary>Meldet jeden Bezeichner "Marker".</summary>
  TMarkerRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

function TMarkerRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('marker', TRuleSeverity.Warning, 'Marker');
end;

procedure TMarkerRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Token: TPascalToken;
begin
  for Token in AContext.Tree.Tokens do
    if (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, 'Marker') then
      AReport.Add(TTextRange.Create(Token.StartPos, Token.EndPos), 'Marker gefunden');
end;

const
  LB = #13#10;
  Body =
    'procedure P;' + LB +
    'var' + LB +
    '  L: TStringList;' + LB +
    'begin' + LB +
    '  L := TStringList.Create;' + LB +
    '  L.Add(''x'');' + LB +
    'end;';

  TryFinallyBefore =
    'unit Atlas.Common.Editing.CodeActions.TryFinallyGolden; // lsp-ignore-file: unused-public-member -- Golden-Datei: Das Testprojekt übersetzt nur das Ergebnis der Aktion.'#13#10 +
    #13#10 +
    '// Golden-Datei für "try/finally ergänzen" (#42): genau das, was die Aktion'#13#10 +
    '// aus den Routinen ohne try erzeugt. Der Test wendet die Aktion auf jede'#13#10 +
    '// Create-Zeile an und vergleicht mit dieser Datei; dass das Ergebnis'#13#10 +
    '// übersetzt, zeigt der Delphi-Testlauf. Nicht von Hand ändern, sondern neu'#13#10 +
    '// erzeugen.'#13#10 +
    #13#10 +
    'interface'#13#10 +
    #13#10 +
    'uses'#13#10 +
    '  System.Classes,'#13#10 +
    '  System.SysUtils;'#13#10 +
    #13#10 +
    'type'#13#10 +
    '  TFeldHalter = class'#13#10 +
    '  private'#13#10 +
    '    FListe: TStringList;'#13#10 +
    '  public'#13#10 +
    '    procedure Fuelle;'#13#10 +
    '    procedure FuelleUeberSelf;'#13#10 +
    '  end;'#13#10 +
    #13#10 +
    'function Zeilen: Integer;'#13#10 +
    'function InlineZeilen: Integer;'#13#10 +
    'function Mehrzeilig: Integer;'#13#10 +
    'procedure Freigabe;'#13#10 +
    'function Liste: TStringList;'#13#10 +
    #13#10 +
    'implementation'#13#10 +
    #13#10 +
    'procedure TFeldHalter.Fuelle;'#13#10 +
    'begin'#13#10 +
    '  FListe := TStringList.Create;'#13#10 +
    '  FListe.Add(''Feld'');'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'procedure TFeldHalter.FuelleUeberSelf;'#13#10 +
    'begin'#13#10 +
    '  Self.FListe := TStringList.Create;'#13#10 +
    '  Self.FListe.Add(''Feld'');'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'function Zeilen: Integer;'#13#10 +
    'var'#13#10 +
    '  Text: TStringList;'#13#10 +
    'begin'#13#10 +
    '  Text := TStringList.Create;'#13#10 +
    '  Text.Add(''a'');'#13#10 +
    #13#10 +
    '  Result := Text.Count;'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'function InlineZeilen: Integer;'#13#10 +
    'begin'#13#10 +
    '  var Text := TStringList.Create;'#13#10 +
    '  Text.Add(''a'');'#13#10 +
    '  Result := Text.Count;'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'function Mehrzeilig: Integer;'#13#10 +
    'var'#13#10 +
    '  Text: TStringList;'#13#10 +
    'begin'#13#10 +
    '  Text := TStringList.Create('#13#10 +
    '    True);'#13#10 +
    '  Result := Text.Count;'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'procedure Freigabe;'#13#10 +
    'var'#13#10 +
    '  Text: TStringList;'#13#10 +
    'begin'#13#10 +
    '  Text := TStringList.Create;'#13#10 +
    '  Text.Add(''x'');'#13#10 +
    '  FreeAndNil(Text);'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'function Liste: TStringList;'#13#10 +
    'begin'#13#10 +
    '  Result := TStringList.Create;'#13#10 +
    '  Result.Add(''x'');'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'end.'#13#10;

function Apply(const AText: string; const AEdit: TRuleEdit): string;
var
  Lines: TArray<string>;
  I, Offset: Integer;
  function OffsetOf(const APos: TTextPosition): Integer;
  var
    L: Integer;
  begin
    Result := 0;
    for L := 0 to APos.Line - 1 do
      Inc(Result, Length(Lines[L]) + 1);
    Inc(Result, APos.Character);
  end;
begin
  Lines := AText.Split([#10]);
  Offset := OffsetOf(AEdit.Range.StartPos);
  I := OffsetOf(AEdit.Range.EndPos);
  Result := Copy(AText, 1, Offset) + AEdit.NewText + Copy(AText, I + 1, MaxInt);
end;

/// <summary>Anzahl der Syntaxfehler in AText.</summary>
function SyntaxErrors(const AText: string): Integer;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Length(Tree.Diagnostics);
  finally
    Tree.Free;
  end;
end;

/// <summary>Datei unter Tests/ ab dem Programmordner bzw. dem aktuellen Ordner aufwärts; '' ohne.</summary>
function TestsFile(const ARelative: string): string;
var
  Starts: TArray<string>;
  Start, Directory: string;
begin
  Starts := [ExtractFileDir(ParamStr(0)), GetCurrentDir];
  for Start in Starts do
  begin
    Directory := Start;
    while Directory <> '' do
    begin
      Result := TPath.Combine(Directory, TPath.Combine('Tests', ARelative));
      if TFile.Exists(Result) then
        Exit;
      if ExtractFileDir(Directory) = Directory then
        Break;
      Directory := ExtractFileDir(Directory);
    end;
  end;
  Result := '';
end;

/// <summary>try/finally mit Stil AStyle für ARange; AText bleibt bei False unverändert.</summary>
function TryWith(const AText: string; const ARange: TTextRange; const AStyle: TFormatStyle;
  out ANewText: string): Boolean;
var
  Tree: TSyntaxTree;
  Action: TCodeAction;
begin
  ANewText := AText;
  Tree := TPascalParser.Parse(AText);
  try
    Result := TCodeActions.TryFinally(AText, Tree, ARange, AStyle, Action);
  finally
    Tree.Free;
  end;
  if Result then
    ANewText := Apply(AText, Action.Edits[0]);
end;

{ TCodeActionTests }

procedure TCodeActionTests.TryFinallyAfterCreate;
var
  Action: TCodeAction;
begin
  Assert.IsTrue(TCodeActions.TryFinally(Body, 4, Action));
  Assert.AreEqual(RewriteKind, Action.Kind);
  Assert.AreEqual(1, Integer(Length(Action.Edits)));
  Assert.AreEqual(4, Action.Edits[0].Range.StartPos.Line);
  Assert.AreEqual(Integer(Length('  L := TStringList.Create;')), Action.Edits[0].Range.StartPos.Character);
end;

procedure TCodeActionTests.TryFinallyResultCompilesStructurally;
var
  Action: TCodeAction;
  NewText: string;
begin
  Assert.IsTrue(TCodeActions.TryFinally(Body, 4, Action));
  NewText := Apply(Body, Action.Edits[0]);
  // Die folgenden Anweisungen stehen im try, der Block bleibt nicht leer.
  Assert.AreEqual(
    'procedure P;' + LB + 'var' + LB + '  L: TStringList;' + LB + 'begin' + LB +
    '  L := TStringList.Create;' + LB + '  try' + LB + '    L.Add(''x'');' + LB + '  finally' + LB + '    L.Free;' + LB +
    '  end;' + LB + 'end;', NewText);
  Assert.AreEqual(0, SyntaxErrors(NewText));
end;

procedure TCodeActionTests.ResultGetsTryExceptInsteadOfFree;
var
  Action: TCodeAction;
  Text, NewText: string;
begin
  // Ein Rückgabewert darf nicht im finally freigegeben werden, nur im Fehlerfall.
  Text := 'function F: TList;' + LB + 'begin' + LB + '  Result := TList.Create;' + LB + '  Result.Add(nil);' + LB +
    'end;';
  Assert.IsTrue(TCodeActions.TryFinally(Text, 2, Action));
  NewText := Apply(Text, Action.Edits[0]);
  Assert.AreEqual('function F: TList;' + LB + 'begin' + LB + '  Result := TList.Create;' + LB + '  try' + LB +
    '    Result.Add(nil);' + LB + '  except' + LB + '    Result.Free;' + LB + '    raise;' + LB + '  end;' + LB + 'end;',
    NewText);
  Assert.AreEqual(0, Pos('finally', NewText));
  Assert.AreEqual(0, SyntaxErrors(NewText));
end;

procedure TCodeActionTests.OrganizeImportsAsSourceAction;
var
  Action: TCodeAction;
begin
  Assert.IsTrue(TCodeActions.OrganizeImports('unit A;' + LB + 'interface' + LB + 'uses B, B;' + LB +
    'implementation' + LB + 'end.', False, Action));
  Assert.AreEqual(OrganizeImportsKind, Action.Kind);
  Assert.AreEqual('B', Action.Edits[0].NewText);
  Assert.IsFalse(TCodeActions.OrganizeImports('unit A;' + LB + 'interface' + LB + 'uses B, C;' + LB +
    'implementation' + LB + 'end.', True, Action));
end;

procedure TCodeActionTests.MatchesRequestedKinds;
begin
  Assert.IsTrue(TCodeActions.KindRequested(FixAllKind, nil));
  Assert.IsTrue(TCodeActions.KindRequested(FixAllKind, ['source']));
  Assert.IsTrue(TCodeActions.KindRequested(OrganizeImportsKind, ['source.organizeImports']));
  Assert.IsFalse(TCodeActions.KindRequested(FixAllKind, ['source.organizeImports']));
  Assert.IsFalse(TCodeActions.KindRequested(QuickFixKind, ['source']));
  Assert.IsFalse(TCodeActions.KindRequested('sourceX', ['source']));
end;

procedure TCodeActionTests.NoTryFinallyWhenAlreadyProtected;
var
  Action: TCodeAction;
begin
  Assert.IsFalse(TCodeActions.TryFinally('procedure P;' + LB + 'var' + LB + '  L: T;' + LB + 'begin' + LB +
    '  L := T.Create;' + LB + LB + '  try' + LB + '    L.Run;' + LB + '  finally' + LB + '    L.Free;' + LB + '  end;' + LB +
    'end;', 4, Action));
end;

procedure TCodeActionTests.NoTryFinallyWithoutCreate;
var
  Action: TCodeAction;
begin
  Assert.IsFalse(TCodeActions.TryFinally(Body, 5, Action));
  Assert.IsFalse(TCodeActions.TryFinally(Body, 2, Action));
end;

procedure TCodeActionTests.NoTryFinallyForFields;
var
  Action: TCodeAction;
begin
  Assert.IsFalse(TCodeActions.TryFinally('procedure TA.P;' + LB + 'begin' + LB + '  FList := TList.Create;' + LB +
    '  FList.Add(nil);' + LB + 'end;', 2, Action));
  Assert.IsFalse(TCodeActions.TryFinally('procedure TA.P;' + LB + 'begin' + LB + '  Self.FList := TList.Create;' + LB +
    '  FList.Add(nil);' + LB + 'end;', 2, Action));
  // Gleicher Name wie ein Feld, aber lokal deklariert: Aktion.
  Assert.IsTrue(TCodeActions.TryFinally('procedure TA.P;' + LB + 'var' + LB + '  FList: TList;' + LB + 'begin' + LB +
    '  FList := TList.Create;' + LB + '  FList.Add(nil);' + LB + 'end;', 4, Action));
end;

procedure TCodeActionTests.NoTryFinallyWhenNothingFollows;
var
  Action: TCodeAction;
begin
  Assert.IsFalse(TCodeActions.TryFinally('procedure P;' + LB + 'var' + LB + '  L: TList;' + LB + 'begin' + LB +
    '  L := TList.Create;' + LB + 'end;', 4, Action));
  // Nur die Freigabe folgt: Der try-Block bliebe leer.
  Assert.IsFalse(TCodeActions.TryFinally('procedure P;' + LB + 'var' + LB + '  L: TList;' + LB + 'begin' + LB +
    '  L := TList.Create;' + LB + '  L.Free;' + LB + 'end;', 4, Action));
  // Einzelne Anweisung hinter then: kein Platz für try.
  Assert.IsFalse(TCodeActions.TryFinally('procedure P(B: Boolean);' + LB + 'var' + LB + '  L: TList;' + LB + 'begin' +
    LB + '  if B then' + LB + '    L := TList.Create;' + LB + '  L.Add(nil);' + LB + 'end;', 5, Action));
end;

procedure TCodeActionTests.NoTryFinallyWhenObjectEscapes;
const
  Head = 'procedure P(AOwner: TComponent; AItems: TList);' + LB + 'var' + LB + '  L: TList;' + LB + '  I: IInterface;' +
    LB + 'begin' + LB;
var
  Action: TCodeAction;
begin
  Assert.IsTrue(TCodeActions.TryFinally(Head + '  L := TList.Create;' + LB + '  L.Add(nil);' + LB + 'end;', 5, Action));
  Assert.IsFalse(TCodeActions.TryFinally(Head + '  L := TList.Create;' + LB + '  AItems.Add(L);' + LB + 'end;', 5,
    Action));
  Assert.IsFalse(TCodeActions.TryFinally(Head + '  L := TList.Create;' + LB + '  FKeep := L;' + LB + 'end;', 5, Action));
  Assert.IsFalse(TCodeActions.TryFinally(Head + '  L := TList.Create;' + LB + '  L.Free;' + LB + '  L.Add(nil);' + LB +
    'end;', 5, Action));
  Assert.IsFalse(TCodeActions.TryFinally(Head + '  L := TList.Create(AOwner);' + LB + '  L.Add(nil);' + LB + 'end;', 5,
    Action));
  Assert.IsFalse(TCodeActions.TryFinally(Head + '  I := TInterfacedObject.Create;' + LB + '  I._AddRef;' + LB +
    'end;', 5, Action));
end;

procedure TCodeActionTests.TryFinallyEnclosesSelectionOnly;
const
  Text = 'procedure P;' + LB + 'var' + LB + '  L: TList;' + LB + 'begin' + LB + '  L := TList.Create;' + LB +
    '  L.Add(nil);' + LB + '  L.Add(nil);' + LB + '  Done;' + LB + 'end;';
var
  NewText: string;
begin
  // Auswahl von der Create-Zeile bis in die zweite Add-Zeile: Done bleibt hinter dem try.
  Assert.IsTrue(TryWith(Text, TTextRange.Create(4, 2, 6, 5), TFormatStyle.Default, NewText));
  Assert.AreEqual('procedure P;' + LB + 'var' + LB + '  L: TList;' + LB + 'begin' + LB + '  L := TList.Create;' + LB +
    '  try' + LB + '    L.Add(nil);' + LB + '    L.Add(nil);' + LB + '  finally' + LB + '    L.Free;' + LB + '  end;' +
    LB + '  Done;' + LB + 'end;', NewText);
  // Auswahl bis zum Anfang der Zeile von Done: Die Zeile zählt nicht mit.
  Assert.IsTrue(TryWith(Text, TTextRange.Create(4, 0, 7, 0), TFormatStyle.Default, NewText));
  Assert.IsTrue(Pos('  end;' + LB + '  Done;', NewText) > 0, NewText);
end;

procedure TCodeActionTests.TryFinallyEndsWithInnerBlock;
const
  Text = 'procedure P(B: Boolean);' + LB + 'var' + LB + '  L: TList;' + LB + 'begin' + LB + '  if B then' + LB +
    '  begin' + LB + '    L := TList.Create;' + LB + '    L.Add(nil);' + LB + '  end;' + LB + '  Done;' + LB + 'end;';
var
  NewText: string;
begin
  Assert.IsTrue(TryWith(Text, TTextRange.Create(6, 0, 6, 0), TFormatStyle.Default, NewText));
  Assert.AreEqual('procedure P(B: Boolean);' + LB + 'var' + LB + '  L: TList;' + LB + 'begin' + LB + '  if B then' + LB +
    '  begin' + LB + '    L := TList.Create;' + LB + '    try' + LB + '      L.Add(nil);' + LB + '    finally' + LB +
    '      L.Free;' + LB + '    end;' + LB + '  end;' + LB + '  Done;' + LB + 'end;', NewText);
  Assert.AreEqual(0, SyntaxErrors(NewText));
end;

procedure TCodeActionTests.TryFinallyFollowsFormatStyle;
const
  Text = 'procedure P;' + LB + 'var' + LB + '    L: TList;' + LB + 'begin' + LB + '    L := TList.Create;' + LB +
    '    L.Add(nil);' + LB + 'end;';
var
  Style: TFormatStyle;
  NewText: string;
begin
  Style := TFormatStyle.Default;
  Style.IndentSize := 4;
  Assert.IsTrue(TryWith(Text, TTextRange.Create(4, 0, 4, 0), Style, NewText));
  Assert.IsTrue(Pos('    try' + LB + '        L.Add(nil);' + LB + '    finally' + LB + '        L.Free;' + LB +
    '    end;', NewText) > 0, NewText);
  Style.UseTabs := True;
  Assert.IsTrue(TryWith(Text, TTextRange.Create(4, 0, 4, 0), Style, NewText));
  Assert.IsTrue(Pos('    try' + LB + #9'    L.Add(nil);' + LB + '    finally' + LB + '    '#9'L.Free;', NewText) > 0,
    NewText);
end;

procedure TCodeActionTests.TryFinallyMatchesGoldenFile;
const
  // Zeilen mit Create, von unten nach oben, damit die Zeilennummern darüber gelten.
  Lines: array[0..6] of Integer = (80, 73, 64, 55, 47, 39, 33);
  Expected: array[0..6] of Boolean = (True, True, True, True, True, False, False);
var
  FileName, Golden, Text: string;
  Index: Integer;
  Action: TCodeAction;
begin
  FileName := TestsFile(TPath.Combine('Common', TPath.Combine('Editing',
    'Atlas.Common.Editing.CodeActions.TryFinallyGolden.pas')));
  Assert.IsTrue(FileName <> '', 'Golden-Datei nicht gefunden');
  Golden := TFile.ReadAllText(FileName, TEncoding.UTF8);
  if (Golden <> '') and (Golden[1] = #$FEFF) then
    Delete(Golden, 1, 1);
  Text := TryFinallyBefore;
  for Index := 0 to High(Lines) do
  begin
    Assert.AreEqual(Expected[Index], TCodeActions.TryFinally(Text, Lines[Index], Action), IntToStr(Lines[Index]));
    if Expected[Index] then
      Text := Apply(Text, Action.Edits[0]);
  end;
  Assert.AreEqual(Golden, Text);
  Assert.AreEqual(0, SyntaxErrors(Text));
end;

procedure TCodeActionTests.SuppressLineInsertsCommentAbove;
var
  Edit: TRuleEdit;
begin
  Edit := TCodeActions.SuppressLine(Body, 5, 'marker');
  Assert.AreEqual(5, Edit.Range.StartPos.Line);
  Assert.AreEqual(0, Edit.Range.StartPos.Character);
  Assert.AreEqual('  // lsp-ignore: marker' + LB, Edit.NewText);
end;

procedure TCodeActionTests.SuppressLineExtendsExistingComment;
var
  Edit: TRuleEdit;
begin
  Edit := TCodeActions.SuppressLine('begin' + LB + '  // lsp-ignore: a' + LB + '  X;' + LB + 'end;', 2, 'b');
  Assert.AreEqual(1, Edit.Range.StartPos.Line);
  Assert.AreEqual(Integer(Length('  // lsp-ignore: a')), Edit.Range.StartPos.Character);
  Assert.AreEqual(', b', Edit.NewText);
end;

procedure TCodeActionTests.SuppressLineInCrOnlyText;
var
  Edit: TRuleEdit;
begin
  Edit := TCodeActions.SuppressLine('begin'#13'  // lsp-ignore: a'#13'  X;'#13'end;', 2, 'b');
  Assert.AreEqual(1, Edit.Range.StartPos.Line);
  Assert.AreEqual(Integer(Length('  // lsp-ignore: a')), Edit.Range.StartPos.Character);
  Assert.AreEqual(', b', Edit.NewText);
end;

procedure TCodeActionTests.SuppressFileAtTop;
var
  Edit: TRuleEdit;
begin
  Edit := TCodeActions.SuppressFile('unit U;' + #10, 'marker');
  Assert.AreEqual(0, Edit.Range.StartPos.Line);
  Assert.AreEqual('// lsp-ignore-file: marker' + #10, Edit.NewText);
end;

procedure TCodeActionTests.UnusedSuppressionReportedWithRemoval;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TMarkerRule.Create,
    'unit U; interface implementation' + LB + '  // lsp-ignore: marker' + LB + 'var X: Integer;' + LB + 'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(UnusedSuppressionRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  // Eigene Zeile: Die ganze Zeile entfällt.
  Assert.AreEqual(1, Findings[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(0, Findings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.AreEqual(2, Findings[0].Fixes[0].Edits[0].Range.EndPos.Line);
  // Ungenutzte Unterdrückungen zu entfernen ist sicher und läuft über source.fixAll (#182).
  Assert.IsTrue(Findings[0].Fixes[0].Safe);
end;

procedure TCodeActionTests.UsedSuppressionNotReported;
begin
  TRuleAssert.Silent(TMarkerRule.Create,
    'unit U; interface implementation' + LB + '  // lsp-ignore: marker' + LB + 'var Marker: Integer;' + LB + 'end.');
end;

procedure TCodeActionTests.SuppressionForUnknownRuleNotReported;
begin
  // Kennung einer Regel, die hier nicht lief: keine unused-suppression (unbekannte Kennungen siehe #41).
  TRuleAssert.Silent(TMarkerRule.Create,
    'unit U; interface implementation' + LB + 'var X: Integer; // lsp-ignore: empty-except' + LB + 'end.');
end;

procedure TCodeActionTests.SwapAssignmentsIsRewrite;
var
  Action: TCodeAction;
begin
  Assert.IsTrue(TCodeActions.SwapAssignments('  A := B;', TTextRange.Create(0, 0, 0, 0), nil, Action));
  Assert.AreEqual(RewriteKind, Action.Kind);
  Assert.AreEqual('  B := A;', Action.Edits[0].NewText);
  Assert.IsFalse(TCodeActions.SwapAssignments('  A := F(B);', TTextRange.Create(0, 0, 0, 0), nil, Action));
end;

initialization
  TDUnitX.RegisterTestFixture(TCodeActionTests);

end.
