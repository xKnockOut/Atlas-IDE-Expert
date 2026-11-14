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
    /// <summary>Zeilen auch bei CR allein getrennt (TTextLines.SplitLines).</summary>
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
  mToken: TPascalToken;
begin
  for mToken in AContext.Tree.Tokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Identifier) and SameText(mToken.Text, 'Marker') then
    begin
      AReport.Add(TTextRange.Create(mToken.StartPos, mToken.EndPos), 'Marker gefunden');
    end;
  end;
end;

const
  cLB = #13#10;
  cBody =
    'procedure P;' + cLB +
    'var' + cLB +
    '  L: TStringList;' + cLB +
    'begin' + cLB +
    '  L := TStringList.Create;' + cLB +
    '  L.Add(''x'');' + cLB +
    'end;';

  cTryFinallyBefore =
    'unit Atlas.Common.Editing.CodeActions.TryFinallyGolden;'#13#10 +
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
  mLines: TArray<string>;
  I, mOffset: Integer;
  function OffsetOf(const APos: TTextPosition): Integer;
  var
    L: Integer;
  begin
    Result := 0;
    for L := 0 to APos.Line - 1 do
    begin
      Inc(Result, Length(mLines[L]) + 1);
    end;
    Inc(Result, APos.Character);
  end;
begin
  mLines := AText.Split([#10]);
  mOffset := OffsetOf(AEdit.Range.StartPos);
  I := OffsetOf(AEdit.Range.EndPos);
  Result := Copy(AText, 1, mOffset) + AEdit.NewText + Copy(AText, I + 1, MaxInt);
end;

/// <summary>Anzahl der Syntaxfehler in AText.</summary>
function SyntaxErrors(const AText: string): Integer;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := Length(mTree.Diagnostics);
  finally
    mTree.Free;
  end;
end;

/// <summary>Datei unter Tests/ ab dem Programmordner bzw. dem aktuellen Ordner aufwärts; '' ohne.</summary>
function TestsFile(const ARelative: string): string;
var
  mStarts: TArray<string>;
  mStart, mDirectory: string;
begin
  mStarts := [ExtractFileDir(ParamStr(0)), GetCurrentDir];
  for mStart in mStarts do
  begin
    mDirectory := mStart;
    while mDirectory <> '' do
    begin
      Result := TPath.Combine(mDirectory, TPath.Combine('Tests', ARelative));
      if TFile.Exists(Result) then
      begin
        Exit;
      end;
      if ExtractFileDir(mDirectory) = mDirectory then
      begin
        Break;
      end;
      mDirectory := ExtractFileDir(mDirectory);
    end;
  end;
  Result := '';
end;

/// <summary>try/finally mit Stil AStyle für ARange; AText bleibt bei False unverändert.</summary>
function TryWith(const AText: string; const ARange: TTextRange; const AStyle: TFormatStyle;
  out ANewText: string): Boolean;
var
  mTree: TSyntaxTree;
  mAction: TCodeAction;
begin
  ANewText := AText;
  mTree := TPascalParser.Parse(AText);
  try
    Result := TCodeActions.TryFinally(AText, mTree, ARange, AStyle, mAction);
  finally
    mTree.Free;
  end;
  if Result then
  begin
    ANewText := Apply(AText, mAction.Edits[0]);
  end;
end;

{ TCodeActionTests }

procedure TCodeActionTests.TryFinallyAfterCreate;
var
  mAction: TCodeAction;
begin
  Assert.IsTrue(TCodeActions.TryFinally(cBody, 4, mAction));
  Assert.AreEqual(cRewriteKind, mAction.Kind);
  Assert.AreEqual(1, Integer(Length(mAction.Edits)));
  Assert.AreEqual(4, mAction.Edits[0].Range.StartPos.Line);
  Assert.AreEqual(Integer(Length('  L := TStringList.Create;')), mAction.Edits[0].Range.StartPos.Character);
end;

procedure TCodeActionTests.TryFinallyResultCompilesStructurally;
var
  mAction: TCodeAction;
  mNewText: string;
begin
  Assert.IsTrue(TCodeActions.TryFinally(cBody, 4, mAction));
  mNewText := Apply(cBody, mAction.Edits[0]);
  // Die folgenden Anweisungen stehen im try, der Block bleibt nicht leer.
  Assert.AreEqual(
    'procedure P;' + cLB + 'var' + cLB + '  L: TStringList;' + cLB + 'begin' + cLB +
    '  L := TStringList.Create;' + cLB + '  try' + cLB + '    L.Add(''x'');' + cLB + '  finally' + cLB + '    L.Free;' + cLB +
    '  end;' + cLB + 'end;', mNewText);
  Assert.AreEqual(0, SyntaxErrors(mNewText));
end;

procedure TCodeActionTests.ResultGetsTryExceptInsteadOfFree;
var
  mAction: TCodeAction;
  mText, mNewText: string;
begin
  // Ein Rückgabewert darf nicht im finally freigegeben werden, nur im Fehlerfall.
  mText := 'function F: TList;' + cLB + 'begin' + cLB + '  Result := TList.Create;' + cLB + '  Result.Add(nil);' + cLB +
    'end;';
  Assert.IsTrue(TCodeActions.TryFinally(mText, 2, mAction));
  mNewText := Apply(mText, mAction.Edits[0]);
  Assert.AreEqual('function F: TList;' + cLB + 'begin' + cLB + '  Result := TList.Create;' + cLB + '  try' + cLB +
    '    Result.Add(nil);' + cLB + '  except' + cLB + '    Result.Free;' + cLB + '    raise;' + cLB + '  end;' + cLB + 'end;',
    mNewText);
  Assert.AreEqual(0, Pos('finally', mNewText));
  Assert.AreEqual(0, SyntaxErrors(mNewText));
end;

procedure TCodeActionTests.OrganizeImportsAsSourceAction;
var
  mAction: TCodeAction;
begin
  Assert.IsTrue(TCodeActions.OrganizeImports('unit A;' + cLB + 'interface' + cLB + 'uses B, B;' + cLB +
    'implementation' + cLB + 'end.', False, mAction));
  Assert.AreEqual(cOrganizeImportsKind, mAction.Kind);
  Assert.AreEqual('B', mAction.Edits[0].NewText);
  Assert.IsFalse(TCodeActions.OrganizeImports('unit A;' + cLB + 'interface' + cLB + 'uses B, C;' + cLB +
    'implementation' + cLB + 'end.', True, mAction));
end;

procedure TCodeActionTests.MatchesRequestedKinds;
begin
  Assert.IsTrue(TCodeActions.KindRequested(cFixAllKind, nil));
  Assert.IsTrue(TCodeActions.KindRequested(cFixAllKind, ['source']));
  Assert.IsTrue(TCodeActions.KindRequested(cOrganizeImportsKind, ['source.organizeImports']));
  Assert.IsFalse(TCodeActions.KindRequested(cFixAllKind, ['source.organizeImports']));
  Assert.IsFalse(TCodeActions.KindRequested(cQuickFixKind, ['source']));
  Assert.IsFalse(TCodeActions.KindRequested('sourceX', ['source']));
end;

procedure TCodeActionTests.NoTryFinallyWhenAlreadyProtected;
var
  mAction: TCodeAction;
begin
  Assert.IsFalse(TCodeActions.TryFinally('procedure P;' + cLB + 'var' + cLB + '  L: T;' + cLB + 'begin' + cLB +
    '  L := T.Create;' + cLB + cLB + '  try' + cLB + '    L.Run;' + cLB + '  finally' + cLB + '    L.Free;' + cLB + '  end;' + cLB +
    'end;', 4, mAction));
end;

procedure TCodeActionTests.NoTryFinallyWithoutCreate;
var
  mAction: TCodeAction;
begin
  Assert.IsFalse(TCodeActions.TryFinally(cBody, 5, mAction));
  Assert.IsFalse(TCodeActions.TryFinally(cBody, 2, mAction));
end;

procedure TCodeActionTests.NoTryFinallyForFields;
var
  mAction: TCodeAction;
begin
  Assert.IsFalse(TCodeActions.TryFinally('procedure TA.P;' + cLB + 'begin' + cLB + '  FList := TList.Create;' + cLB +
    '  FList.Add(nil);' + cLB + 'end;', 2, mAction));
  Assert.IsFalse(TCodeActions.TryFinally('procedure TA.P;' + cLB + 'begin' + cLB + '  Self.FList := TList.Create;' + cLB +
    '  FList.Add(nil);' + cLB + 'end;', 2, mAction));
  // Gleicher Name wie ein Feld, aber lokal deklariert: Aktion.
  Assert.IsTrue(TCodeActions.TryFinally('procedure TA.P;' + cLB + 'var' + cLB + '  FList: TList;' + cLB + 'begin' + cLB +
    '  FList := TList.Create;' + cLB + '  FList.Add(nil);' + cLB + 'end;', 4, mAction));
end;

procedure TCodeActionTests.NoTryFinallyWhenNothingFollows;
var
  mAction: TCodeAction;
begin
  Assert.IsFalse(TCodeActions.TryFinally('procedure P;' + cLB + 'var' + cLB + '  L: TList;' + cLB + 'begin' + cLB +
    '  L := TList.Create;' + cLB + 'end;', 4, mAction));
  // Nur die Freigabe folgt: Der try-Block bliebe leer.
  Assert.IsFalse(TCodeActions.TryFinally('procedure P;' + cLB + 'var' + cLB + '  L: TList;' + cLB + 'begin' + cLB +
    '  L := TList.Create;' + cLB + '  L.Free;' + cLB + 'end;', 4, mAction));
  // Einzelne Anweisung hinter then: kein Platz für try.
  Assert.IsFalse(TCodeActions.TryFinally('procedure P(B: Boolean);' + cLB + 'var' + cLB + '  L: TList;' + cLB + 'begin' +
    cLB + '  if B then' + cLB + '    L := TList.Create;' + cLB + '  L.Add(nil);' + cLB + 'end;', 5, mAction));
end;

procedure TCodeActionTests.NoTryFinallyWhenObjectEscapes;
const
  cHead = 'procedure P(AOwner: TComponent; AItems: TList);' + cLB + 'var' + cLB + '  L: TList;' + cLB + '  I: IInterface;' +
    cLB + 'begin' + cLB;
var
  mAction: TCodeAction;
begin
  Assert.IsTrue(TCodeActions.TryFinally(cHead + '  L := TList.Create;' + cLB + '  L.Add(nil);' + cLB + 'end;', 5, mAction));
  Assert.IsFalse(TCodeActions.TryFinally(cHead + '  L := TList.Create;' + cLB + '  AItems.Add(L);' + cLB + 'end;', 5,
    mAction));
  Assert.IsFalse(TCodeActions.TryFinally(cHead + '  L := TList.Create;' + cLB + '  FKeep := L;' + cLB + 'end;', 5, mAction));
  Assert.IsFalse(TCodeActions.TryFinally(cHead + '  L := TList.Create;' + cLB + '  L.Free;' + cLB + '  L.Add(nil);' + cLB +
    'end;', 5, mAction));
  Assert.IsFalse(TCodeActions.TryFinally(cHead + '  L := TList.Create(AOwner);' + cLB + '  L.Add(nil);' + cLB + 'end;', 5,
    mAction));
  Assert.IsFalse(TCodeActions.TryFinally(cHead + '  I := TInterfacedObject.Create;' + cLB + '  I._AddRef;' + cLB +
    'end;', 5, mAction));
end;

procedure TCodeActionTests.TryFinallyEnclosesSelectionOnly;
const
  cText = 'procedure P;' + cLB + 'var' + cLB + '  L: TList;' + cLB + 'begin' + cLB + '  L := TList.Create;' + cLB +
    '  L.Add(nil);' + cLB + '  L.Add(nil);' + cLB + '  Done;' + cLB + 'end;';
var
  mNewText: string;
begin
  // Auswahl von der Create-Zeile bis in die zweite Add-Zeile: Done bleibt hinter dem try.
  Assert.IsTrue(TryWith(cText, TTextRange.Create(4, 2, 6, 5), TFormatStyle.Default, mNewText));
  Assert.AreEqual('procedure P;' + cLB + 'var' + cLB + '  L: TList;' + cLB + 'begin' + cLB + '  L := TList.Create;' + cLB +
    '  try' + cLB + '    L.Add(nil);' + cLB + '    L.Add(nil);' + cLB + '  finally' + cLB + '    L.Free;' + cLB + '  end;' +
    cLB + '  Done;' + cLB + 'end;', mNewText);
  // Auswahl bis zum Anfang der Zeile von Done: Die Zeile zählt nicht mit.
  Assert.IsTrue(TryWith(cText, TTextRange.Create(4, 0, 7, 0), TFormatStyle.Default, mNewText));
  Assert.IsTrue(Pos('  end;' + cLB + '  Done;', mNewText) > 0, mNewText);
end;

procedure TCodeActionTests.TryFinallyEndsWithInnerBlock;
const
  cText = 'procedure P(B: Boolean);' + cLB + 'var' + cLB + '  L: TList;' + cLB + 'begin' + cLB + '  if B then' + cLB +
    '  begin' + cLB + '    L := TList.Create;' + cLB + '    L.Add(nil);' + cLB + '  end;' + cLB + '  Done;' + cLB + 'end;';
var
  mNewText: string;
begin
  Assert.IsTrue(TryWith(cText, TTextRange.Create(6, 0, 6, 0), TFormatStyle.Default, mNewText));
  Assert.AreEqual('procedure P(B: Boolean);' + cLB + 'var' + cLB + '  L: TList;' + cLB + 'begin' + cLB + '  if B then' + cLB +
    '  begin' + cLB + '    L := TList.Create;' + cLB + '    try' + cLB + '      L.Add(nil);' + cLB + '    finally' + cLB +
    '      L.Free;' + cLB + '    end;' + cLB + '  end;' + cLB + '  Done;' + cLB + 'end;', mNewText);
  Assert.AreEqual(0, SyntaxErrors(mNewText));
end;

procedure TCodeActionTests.TryFinallyFollowsFormatStyle;
const
  cText = 'procedure P;' + cLB + 'var' + cLB + '    L: TList;' + cLB + 'begin' + cLB + '    L := TList.Create;' + cLB +
    '    L.Add(nil);' + cLB + 'end;';
var
  mStyle: TFormatStyle;
  mNewText: string;
begin
  mStyle := TFormatStyle.Default;
  mStyle.IndentSize := 4;
  Assert.IsTrue(TryWith(cText, TTextRange.Create(4, 0, 4, 0), mStyle, mNewText));
  Assert.IsTrue(Pos('    try' + cLB + '        L.Add(nil);' + cLB + '    finally' + cLB + '        L.Free;' + cLB +
    '    end;', mNewText) > 0, mNewText);
  mStyle.UseTabs := True;
  Assert.IsTrue(TryWith(cText, TTextRange.Create(4, 0, 4, 0), mStyle, mNewText));
  Assert.IsTrue(Pos('    try' + cLB + #9'    L.Add(nil);' + cLB + '    finally' + cLB + '    '#9'L.Free;', mNewText) > 0,
    mNewText);
end;

procedure TCodeActionTests.TryFinallyMatchesGoldenFile;
const
  // Zeilen mit Create, von unten nach oben, damit die Zeilennummern darüber gelten.
  cLines: array[0..6] of Integer = (80, 73, 64, 55, 47, 39, 33);
  cExpected: array[0..6] of Boolean = (True, True, True, True, True, False, False);
var
  mFileName, mGolden, mText: string;
  mIndex: Integer;
  mAction: TCodeAction;
begin
  mFileName := TestsFile(TPath.Combine('Common', TPath.Combine('Editing',
    'Atlas.Common.Editing.CodeActions.TryFinallyGolden.pas')));
  Assert.AreNotEqual('', mFileName, 'Golden-Datei nicht gefunden');
  mGolden := TFile.ReadAllText(mFileName, TEncoding.UTF8);
  if (mGolden <> '') and (mGolden[1] = #$FEFF) then
  begin
    Delete(mGolden, 1, 1);
  end;
  mText := cTryFinallyBefore;
  for mIndex := 0 to High(cLines) do
  begin
    Assert.AreEqual(cExpected[mIndex], TCodeActions.TryFinally(mText, cLines[mIndex], mAction),
      IntToStr(cLines[mIndex]));
    if cExpected[mIndex] then
    begin
      mText := Apply(mText, mAction.Edits[0]);
    end;
  end;
  Assert.AreEqual(mGolden, mText);
  Assert.AreEqual(0, SyntaxErrors(mText));
end;

procedure TCodeActionTests.SuppressLineInsertsCommentAbove;
var
  mEdit: TRuleEdit;
begin
  mEdit := TCodeActions.SuppressLine(cBody, 5, 'marker');
  Assert.AreEqual(5, mEdit.Range.StartPos.Line);
  Assert.AreEqual(0, mEdit.Range.StartPos.Character);
  Assert.AreEqual('  // lsp-ignore: marker' + cLB, mEdit.NewText);
end;

procedure TCodeActionTests.SuppressLineExtendsExistingComment;
var
  mEdit: TRuleEdit;
begin
  mEdit := TCodeActions.SuppressLine('begin' + cLB + '  // lsp-ignore: a' + cLB + '  X;' + cLB + 'end;', 2, 'b');
  Assert.AreEqual(1, mEdit.Range.StartPos.Line);
  Assert.AreEqual(Integer(Length('  // lsp-ignore: a')), mEdit.Range.StartPos.Character);
  Assert.AreEqual(', b', mEdit.NewText);
end;

procedure TCodeActionTests.SuppressLineInCrOnlyText;
var
  mEdit: TRuleEdit;
begin
  mEdit := TCodeActions.SuppressLine('begin'#13'  // lsp-ignore: a'#13'  X;'#13'end;', 2, 'b');
  Assert.AreEqual(1, mEdit.Range.StartPos.Line);
  Assert.AreEqual(Integer(Length('  // lsp-ignore: a')), mEdit.Range.StartPos.Character);
  Assert.AreEqual(', b', mEdit.NewText);
end;

procedure TCodeActionTests.SuppressFileAtTop;
var
  mEdit: TRuleEdit;
begin
  mEdit := TCodeActions.SuppressFile('unit U;' + #10, 'marker');
  Assert.AreEqual(0, mEdit.Range.StartPos.Line);
  Assert.AreEqual('// lsp-ignore-file: marker' + #10, mEdit.NewText);
end;

procedure TCodeActionTests.UnusedSuppressionReportedWithRemoval;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TMarkerRule.Create,
    'unit U; interface implementation' + cLB + '  // lsp-ignore: marker' + cLB + 'var X: Integer;' + cLB + 'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cUnusedSuppressionRuleId, mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  // Eigene Zeile: Die ganze Zeile entfällt.
  Assert.AreEqual(1, mFindings[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(0, mFindings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.AreEqual(2, mFindings[0].Fixes[0].Edits[0].Range.EndPos.Line);
  // Ungenutzte Unterdrückungen zu entfernen ist sicher und läuft über source.fixAll (#182).
  Assert.IsTrue(mFindings[0].Fixes[0].Safe);
end;

procedure TCodeActionTests.UsedSuppressionNotReported;
begin
  TRuleAssert.Silent(TMarkerRule.Create,
    'unit U; interface implementation' + cLB + '  // lsp-ignore: marker' + cLB + 'var Marker: Integer;' + cLB + 'end.');
end;

procedure TCodeActionTests.SuppressionForUnknownRuleNotReported;
begin
  // Kennung einer Regel, die hier nicht lief: keine unused-suppression (unbekannte Kennungen siehe #41).
  TRuleAssert.Silent(TMarkerRule.Create,
    'unit U; interface implementation' + cLB + 'var X: Integer; // lsp-ignore: empty-except' + cLB + 'end.');
end;

procedure TCodeActionTests.SwapAssignmentsIsRewrite;
var
  mAction: TCodeAction;
begin
  Assert.IsTrue(TCodeActions.SwapAssignments('  A := B;', TTextRange.Create(0, 0, 0, 0), nil, mAction));
  Assert.AreEqual(cRewriteKind, mAction.Kind);
  Assert.AreEqual('  B := A;', mAction.Edits[0].NewText);
  Assert.IsFalse(TCodeActions.SwapAssignments('  A := F(B);', TTextRange.Create(0, 0, 0, 0), nil, mAction));
end;

initialization
  TDUnitX.RegisterTestFixture(TCodeActionTests);

end.
