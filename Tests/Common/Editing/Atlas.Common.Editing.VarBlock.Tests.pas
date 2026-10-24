unit Atlas.Common.Editing.VarBlock.Tests;

// var-Block pflegen (#644): Umwandeln in beide Richtungen, wann nicht
// umgewandelt wird (äußerer Block, try/except, Schleife, anonyme Methode),
// Aufräumen mit Kommentaren, Sortierung und Zusammenfassen. Jedes Ergebnis
// muss fehlerfrei parsen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TVarBlockTests = class
  public
    [Test]
    procedure SectionVariableBecomesInitializedInline;
    [Test]
    procedure InlineKeepsTypeWhenNotObvious;
    [Test]
    procedure InlineWithoutStartValueWhenExpressionReadsIt;
    [Test]
    procedure CommentsMoveToInline;
    [Test]
    procedure OuterBlockUseDeclaresInOuterBlock;
    [Test]
    procedure TryExceptUseDeclaresBeforeTry;
    [Test]
    procedure NoInlineInLoopWithoutStartValue;
    [Test]
    procedure NoInlineWhenCaptured;
    [Test]
    procedure NoInlineWithoutLanguageFeature;
    [Test]
    procedure InlineMovesToNewSection;
    [Test]
    procedure InlineWithoutTypeUsesLookup;
    [Test]
    procedure UninitializedInlineMovesWithComments;
    [Test]
    procedure NoSectionMoveWhenNameMeansSomethingElse;
    [Test]
    procedure CleanupRemovesSortsAndMerges;
    [Test]
    procedure CleanupSplitsWithoutMerge;
    [Test]
    procedure CleanupAlphabeticalKeepsComments;
    [Test]
    procedure CleanupRemovesWholeSection;
    [Test]
    procedure NoCleanupWhenTidy;
    [Test]
    procedure SortNames;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.VarBlock;

const
  LF = #10;

function Wrap(const ABody: string): string;
begin
  Result := 'unit U;' + LF + 'interface' + LF + 'implementation' + LF + ABody + LF + 'end.';
end;

/// <summary>Position des ersten Vorkommens von ANeedle in AText.</summary>
function At(const AText, ANeedle: string): TTextPosition;
var
  Offset, Index: Integer;
begin
  Offset := Pos(ANeedle, AText) - 1;
  Result := TTextPosition.Create(0, 0);
  for Index := 1 to Offset do
    if AText[Index] = LF then
    begin
      Inc(Result.Line);
      Result.Character := 0;
    end
    else
      Inc(Result.Character);
end;

/// <summary>Text nach der Aktion, deren Titel AKind enthält ('Inline', 'verschieben', 'aufr'); '' ohne.</summary>
function Run(const AText, ANeedle, AKind: string; const AOptions: TVarBlockOptions; out ATitle: string): string;
var
  Tree: TSyntaxTree;
  Action: TCodeAction;
begin
  Result := '';
  ATitle := '';
  Tree := TPascalParser.Parse(AText);
  try
    for Action in TVarBlock.Actions(AText, Tree, At(AText, ANeedle), AOptions) do
      if Pos(AKind, Action.Title) > 0 then
      begin
        ATitle := Action.Title;
        Result := TChangeSignature.ApplyEdits(AText, Action.Edits);
      end;
  finally
    Tree.Free;
  end;
end;

function Apply(const AText, ANeedle, AKind: string): string;
var
  Title: string;
begin
  Result := Run(AText, ANeedle, AKind, TVarBlockOptions.Default, Title);
end;

function Parses(const AText: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
  end;
end;

procedure TVarBlockTests.SectionVariableBecomesInitializedInline;
var
  Title, Changed: string;
begin
  Changed := Run(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  Count: Integer;' + LF +
    '  Name: string;' + LF +
    'begin' + LF +
    '  Name := ''x'';' + LF +
    '  Count := 0;' + LF +
    '  Writeln(Count, Name);' + LF +
    'end;'), 'Count:', 'Inline', TVarBlockOptions.Default, Title);
  Assert.AreEqual('In Inline-Variable umwandeln (var Count)', Title);
  Assert.AreEqual(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  Name: string;' + LF +
    'begin' + LF +
    '  Name := ''x'';' + LF +
    '  var Count := 0;' + LF +
    '  Writeln(Count, Name);' + LF +
    'end;'), Changed);
  Assert.IsTrue(Parses(Changed));
end;

procedure TVarBlockTests.InlineKeepsTypeWhenNotObvious;
var
  Changed: string;
begin
  // Von der Verwendung aus aufgerufen; einziger Eintrag: "var" fällt mit weg.
  Changed := Apply(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  Total: Int64;' + LF +
    'begin' + LF +
    '  Total := 0;' + LF +
    '  Writeln(Total);' + LF +
    'end;'), 'Total);', 'Inline');
  Assert.AreEqual(Wrap(
    'procedure P;' + LF +
    'begin' + LF +
    '  var Total: Int64 := 0;' + LF +
    '  Writeln(Total);' + LF +
    'end;'), Changed);
  Assert.IsTrue(Parses(Changed));
end;

procedure TVarBlockTests.InlineWithoutStartValueWhenExpressionReadsIt;
var
  Changed: string;
begin
  Changed := Apply(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  S: string;' + LF +
    'begin' + LF +
    '  Writeln(1);' + LF +
    '  S := S + ''a'';' + LF +
    'end;'), 'S:', 'Inline');
  Assert.AreEqual(Wrap(
    'procedure P;' + LF +
    'begin' + LF +
    '  Writeln(1);' + LF +
    '  var S: string;' + LF +
    '  S := S + ''a'';' + LF +
    'end;'), Changed);
  Assert.IsTrue(Parses(Changed));
end;

procedure TVarBlockTests.CommentsMoveToInline;
var
  Changed: string;
begin
  Changed := Apply(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  Name: string;' + LF +
    '  // Zaehler' + LF +
    '  { fuer die Liste }' + LF +
    '  I: Integer; // Anzahl' + LF +
    'begin' + LF +
    '  Name := '''';' + LF +
    '  I := 0;' + LF +
    '  Writeln(I, Name);' + LF +
    'end;'), 'I:', 'Inline');
  Assert.AreEqual(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  Name: string;' + LF +
    'begin' + LF +
    '  Name := '''';' + LF +
    '  // Zaehler' + LF +
    '  { fuer die Liste }' + LF +
    '  var I := 0; // Anzahl' + LF +
    '  Writeln(I, Name);' + LF +
    'end;'), Changed);
  Assert.IsTrue(Parses(Changed));
end;

procedure TVarBlockTests.OuterBlockUseDeclaresInOuterBlock;
var
  Changed: string;
begin
  // Erste Zuweisung im inneren Block, Verwendung danach außen: nicht in den inneren Block.
  Changed := Apply(Wrap(
    'procedure P(B: Boolean);' + LF +
    'var' + LF +
    '  I: Integer;' + LF +
    'begin' + LF +
    '  if B then' + LF +
    '  begin' + LF +
    '    I := 1;' + LF +
    '  end;' + LF +
    '  Writeln(I);' + LF +
    'end;'), 'I:', 'Inline');
  Assert.AreEqual(Wrap(
    'procedure P(B: Boolean);' + LF +
    'begin' + LF +
    '  var I: Integer;' + LF +
    '  if B then' + LF +
    '  begin' + LF +
    '    I := 1;' + LF +
    '  end;' + LF +
    '  Writeln(I);' + LF +
    'end;'), Changed);
  Assert.IsTrue(Parses(Changed));
  // Nur im inneren Block verwendet: dorthin.
  Changed := Apply(Wrap(
    'procedure P(B: Boolean);' + LF +
    'var' + LF +
    '  I: Integer;' + LF +
    'begin' + LF +
    '  if B then' + LF +
    '  begin' + LF +
    '    I := 1;' + LF +
    '    Writeln(I);' + LF +
    '  end;' + LF +
    'end;'), 'I:', 'Inline');
  Assert.AreEqual(Wrap(
    'procedure P(B: Boolean);' + LF +
    'begin' + LF +
    '  if B then' + LF +
    '  begin' + LF +
    '    var I := 1;' + LF +
    '    Writeln(I);' + LF +
    '  end;' + LF +
    'end;'), Changed);
  Assert.IsTrue(Parses(Changed));
end;

procedure TVarBlockTests.TryExceptUseDeclaresBeforeTry;
var
  Changed: string;
begin
  // Im try-Teil zugewiesen, im except gelesen: Die Deklaration darf nicht in den try-Teil.
  Changed := Apply(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  I: Integer;' + LF +
    'begin' + LF +
    '  try' + LF +
    '    I := 1;' + LF +
    '  except' + LF +
    '    Writeln(I);' + LF +
    '  end;' + LF +
    'end;'), 'I:', 'Inline');
  Assert.AreEqual(Wrap(
    'procedure P;' + LF +
    'begin' + LF +
    '  var I: Integer;' + LF +
    '  try' + LF +
    '    I := 1;' + LF +
    '  except' + LF +
    '    Writeln(I);' + LF +
    '  end;' + LF +
    'end;'), Changed);
  Assert.IsTrue(Parses(Changed));
  // Nur im try-Teil: dort hinein.
  Changed := Apply(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  I: Integer;' + LF +
    'begin' + LF +
    '  try' + LF +
    '    I := 1;' + LF +
    '    Writeln(I);' + LF +
    '  finally' + LF +
    '    Writeln(2);' + LF +
    '  end;' + LF +
    'end;'), 'I:', 'Inline');
  Assert.AreEqual(Wrap(
    'procedure P;' + LF +
    'begin' + LF +
    '  try' + LF +
    '    var I := 1;' + LF +
    '    Writeln(I);' + LF +
    '  finally' + LF +
    '    Writeln(2);' + LF +
    '  end;' + LF +
    'end;'), Changed);
  Assert.IsTrue(Parses(Changed));
end;

procedure TVarBlockTests.NoInlineInLoopWithoutStartValue;
begin
  // Inc(I) liest I: ohne Startwert begänne jeder Durchlauf mit einer neuen Variablen.
  Assert.AreEqual('', Apply(Wrap(
    'procedure P(B: Boolean);' + LF +
    'var' + LF +
    '  I: Integer;' + LF +
    'begin' + LF +
    '  while B do' + LF +
    '  begin' + LF +
    '    Inc(I);' + LF +
    '    Writeln(I);' + LF +
    '  end;' + LF +
    'end;'), 'I:', 'Inline'));
  // Mit Zuweisung am Anfang des Durchlaufs geht es.
  Assert.AreEqual(Wrap(
    'procedure P(B: Boolean);' + LF +
    'begin' + LF +
    '  while B do' + LF +
    '  begin' + LF +
    '    var I := 0;' + LF +
    '    Writeln(I);' + LF +
    '  end;' + LF +
    'end;'), Apply(Wrap(
    'procedure P(B: Boolean);' + LF +
    'var' + LF +
    '  I: Integer;' + LF +
    'begin' + LF +
    '  while B do' + LF +
    '  begin' + LF +
    '    I := 0;' + LF +
    '    Writeln(I);' + LF +
    '  end;' + LF +
    'end;'), 'I:', 'Inline'));
end;

procedure TVarBlockTests.NoInlineWhenCaptured;
begin
  Assert.AreEqual('', Apply(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  I: Integer;' + LF +
    'begin' + LF +
    '  I := 1;' + LF +
    '  Run(procedure begin Writeln(I) end);' + LF +
    'end;'), 'I:', 'Inline'));
  // Verschachtelte Routine
  Assert.AreEqual('', Apply(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  I: Integer;' + LF +
    '  procedure Show;' + LF +
    '  begin' + LF +
    '    Writeln(I);' + LF +
    '  end;' + LF +
    'begin' + LF +
    '  I := 1;' + LF +
    '  Show;' + LF +
    'end;'), 'I:', 'Inline'));
  // Bedingte Übersetzung
  Assert.AreEqual('', Apply(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  I: Integer;' + LF +
    'begin' + LF +
    '  I := 1;' + LF +
    '  {$IFDEF DEBUG}' + LF +
    '  Writeln(I);' + LF +
    '  {$ENDIF}' + LF +
    'end;'), 'I:', 'Inline'));
end;

procedure TVarBlockTests.NoInlineWithoutLanguageFeature;
var
  Options: TVarBlockOptions;
  Title: string;
begin
  Options := TVarBlockOptions.Default;
  Options.InlineVariables := False;
  Assert.AreEqual('', Run(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  I: Integer;' + LF +
    'begin' + LF +
    '  I := 1;' + LF +
    '  Writeln(I);' + LF +
    'end;'), 'I:', 'Inline', Options, Title));
end;

procedure TVarBlockTests.InlineMovesToNewSection;
var
  Title, Changed: string;
begin
  Changed := Run(Wrap(
    'procedure P;' + LF +
    'begin' + LF +
    '  var Count: Integer := 0;' + LF +
    '  Writeln(Count);' + LF +
    'end;'), 'Count:', 'verschieben', TVarBlockOptions.Default, Title);
  Assert.AreEqual('In var-Block verschieben (Count)', Title);
  Assert.AreEqual(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  Count: Integer;' + LF +
    'begin' + LF +
    '  Count := 0;' + LF +
    '  Writeln(Count);' + LF +
    'end;'), Changed);
  Assert.IsTrue(Parses(Changed));
  // Hin und zurück ergibt wieder den Anfang (ohne offensichtlichen Typ).
  Assert.AreEqual(Wrap(
    'procedure P;' + LF +
    'begin' + LF +
    '  var Count := 0;' + LF +
    '  Writeln(Count);' + LF +
    'end;'), Apply(Changed, 'Count:', 'Inline'));
end;

procedure TVarBlockTests.InlineWithoutTypeUsesLookup;
var
  Options: TVarBlockOptions;
  Title, Source, Changed: string;
begin
  Source := Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  A: Integer;' + LF +
    'begin' + LF +
    '  A := 1;' + LF +
    '  var Liste := TStringList.Create;' + LF +
    '  Writeln(A, Liste.Count);' + LF +
    'end;');
  // Ohne Typermittlung keine Aktion.
  Assert.AreEqual('', Apply(Source, 'Liste :=', 'verschieben'));
  Options := TVarBlockOptions.Default;
  Options.Types :=
    function(ADecl: TSyntaxNode; out AType: string; out AEdits: TArray<TTextEdit>): Boolean
    begin
      AType := 'TStringList';
      AEdits := nil;
      Result := True;
    end;
  Changed := Run(Source, 'Liste :=', 'verschieben', Options, Title);
  Assert.AreEqual(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  A: Integer;' + LF +
    '  Liste: TStringList;' + LF +
    'begin' + LF +
    '  A := 1;' + LF +
    '  Liste := TStringList.Create;' + LF +
    '  Writeln(A, Liste.Count);' + LF +
    'end;'), Changed);
  Assert.IsTrue(Parses(Changed));
end;

procedure TVarBlockTests.UninitializedInlineMovesWithComments;
var
  Changed: string;
begin
  Changed := Apply(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  A: Integer;' + LF +
    'begin' + LF +
    '  A := 1;' + LF +
    '  // Puffer' + LF +
    '  var S: string; // fuer Text' + LF +
    '  S := IntToStr(A);' + LF +
    'end;'), 'S:', 'verschieben');
  Assert.AreEqual(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  A: Integer;' + LF +
    '  // Puffer' + LF +
    '  S: string; // fuer Text' + LF +
    'begin' + LF +
    '  A := 1;' + LF +
    '  S := IntToStr(A);' + LF +
    'end;'), Changed);
  Assert.IsTrue(Parses(Changed));
end;

procedure TVarBlockTests.NoSectionMoveWhenNameMeansSomethingElse;
begin
  // Vor der Deklaration meint I etwas anderes (globale Variable).
  Assert.AreEqual('', Apply(Wrap(
    'procedure P;' + LF +
    'begin' + LF +
    '  Writeln(I);' + LF +
    '  var I: Integer := 0;' + LF +
    '  Writeln(I);' + LF +
    'end;'), 'I: Integer', 'verschieben'));
  // Gleichnamige Inline-Variable in einem anderen Block
  Assert.AreEqual('', Apply(Wrap(
    'procedure P(B: Boolean);' + LF +
    'begin' + LF +
    '  if B then' + LF +
    '  begin' + LF +
    '    var I: Integer := 0;' + LF +
    '    Writeln(I);' + LF +
    '  end' + LF +
    '  else' + LF +
    '  begin' + LF +
    '    var I: string := '''';' + LF +
    '    Writeln(I);' + LF +
    '  end;' + LF +
    'end;'), 'I: Integer', 'verschieben'));
  // Ohne Startwert in einer Schleife
  Assert.AreEqual('', Apply(Wrap(
    'procedure P(B: Boolean);' + LF +
    'begin' + LF +
    '  while B do' + LF +
    '  begin' + LF +
    '    var S: string;' + LF +
    '    S := S + ''a'';' + LF +
    '  end;' + LF +
    'end;'), 'S:', 'verschieben'));
  // Capture in einer anonymen Methode
  Assert.AreEqual('', Apply(Wrap(
    'procedure P;' + LF +
    'begin' + LF +
    '  var I: Integer := 0;' + LF +
    '  Run(procedure begin Writeln(I) end);' + LF +
    'end;'), 'I:', 'verschieben'));
end;

procedure TVarBlockTests.CleanupRemovesSortsAndMerges;
var
  Title, Changed: string;
begin
  Changed := Run(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  B: string;' + LF +
    '  Unused: Integer;' + LF +
    '  C: Integer;' + LF +
    '  A: Integer;' + LF +
    '  // Liste' + LF +
    '  L: TStringList; // Puffer' + LF +
    'begin' + LF +
    '  A := 1;' + LF +
    '  C := 2;' + LF +
    '  L := nil;' + LF +
    '  B := '''';' + LF +
    'end;'), 'var', 'aufr', TVarBlockOptions.Default, Title);
  Assert.AreEqual('var-Block aufr', Copy(Title, 1, 14));
  Assert.IsTrue(Pos('(ungenutzt: Unused)', Title) > 0);
  Assert.AreEqual(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  A, C: Integer;' + LF +
    '  // Liste' + LF +
    '  L: TStringList; // Puffer' + LF +
    '  B: string;' + LF +
    'begin' + LF +
    '  A := 1;' + LF +
    '  C := 2;' + LF +
    '  L := nil;' + LF +
    '  B := '''';' + LF +
    'end;'), Changed);
  Assert.IsTrue(Parses(Changed));
end;

procedure TVarBlockTests.CleanupSplitsWithoutMerge;
var
  Options: TVarBlockOptions;
  Title, Changed: string;
begin
  Options := TVarBlockOptions.Default;
  Options.Merge := False;
  Options.Sort := TVarBlockSort.None;
  Changed := Run(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  I, J: Integer;' + LF +
    '  A, B: array of Integer;' + LF +
    'begin' + LF +
    '  J := 1;' + LF +
    '  I := J;' + LF +
    '  A := B;' + LF +
    'end;'), 'I,', 'aufr', Options, Title);
  // Typen ohne Namen bleiben zusammen (sonst wären A und B nicht mehr zuweisungsverträglich).
  Assert.AreEqual(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  I: Integer;' + LF +
    '  J: Integer;' + LF +
    '  A, B: array of Integer;' + LF +
    'begin' + LF +
    '  J := 1;' + LF +
    '  I := J;' + LF +
    '  A := B;' + LF +
    'end;'), Changed);
  Assert.IsTrue(Parses(Changed));
end;

procedure TVarBlockTests.CleanupAlphabeticalKeepsComments;
var
  Options: TVarBlockOptions;
  Title, Changed: string;
begin
  Options := TVarBlockOptions.Default;
  Options.Sort := TVarBlockSort.Alpha;
  Changed := Run(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  { Zaehler' + LF +
    '    zweite Zeile }' + LF +
    '  Zahl: Integer;' + LF +
    '' + LF +
    '  Text: string;' + LF +
    '  Anzahl: Integer; // Menge' + LF +
    'begin' + LF +
    '  Zahl := 1;' + LF +
    '  Text := '''';' + LF +
    '  Anzahl := Zahl;' + LF +
    'end;'), 'Text:', 'aufr', Options, Title);
  Assert.AreEqual(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  Anzahl: Integer; // Menge' + LF +
    '  Text: string;' + LF +
    '  { Zaehler' + LF +
    '    zweite Zeile }' + LF +
    '  Zahl: Integer;' + LF +
    'begin' + LF +
    '  Zahl := 1;' + LF +
    '  Text := '''';' + LF +
    '  Anzahl := Zahl;' + LF +
    'end;'), Changed);
  Assert.IsTrue(Parses(Changed));
end;

procedure TVarBlockTests.CleanupRemovesWholeSection;
var
  Changed: string;
begin
  Changed := Apply(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  // alt' + LF +
    '  I, J: Integer;' + LF +
    'begin' + LF +
    '  Writeln(1);' + LF +
    'end;'), 'var', 'aufr');
  Assert.AreEqual(Wrap(
    'procedure P;' + LF +
    'begin' + LF +
    '  Writeln(1);' + LF +
    'end;'), Changed);
  Assert.IsTrue(Parses(Changed));
end;

procedure TVarBlockTests.NoCleanupWhenTidy;
begin
  Assert.AreEqual('', Apply(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  I, J: Integer;' + LF +
    '  S: string;' + LF +
    'begin' + LF +
    '  I := 1;' + LF +
    '  J := I;' + LF +
    '  S := '''';' + LF +
    'end;'), 'var', 'aufr'));
  // Mit Direktive im Abschnitt kein Aufräumen.
  Assert.AreEqual('', Apply(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  S: string;' + LF +
    '  {$IFDEF DEBUG}' + LF +
    '  I: Integer;' + LF +
    '  {$ENDIF}' + LF +
    'begin' + LF +
    '  S := '''';' + LF +
    'end;'), 'var', 'aufr'));
end;

procedure TVarBlockTests.SortNames;
begin
  Assert.IsTrue(TVarBlock.SortOf('alpha') = TVarBlockSort.Alpha);
  Assert.IsTrue(TVarBlock.SortOf('NONE') = TVarBlockSort.None);
  Assert.IsTrue(TVarBlock.SortOf('usage') = TVarBlockSort.Usage);
  Assert.IsTrue(TVarBlock.SortOf('quer') = TVarBlockSort.Usage);
  Assert.AreEqual('alpha', TVarBlock.SortNames[TVarBlockSort.Alpha]);
end;

initialization
  TDUnitX.RegisterTestFixture(TVarBlockTests);

end.
