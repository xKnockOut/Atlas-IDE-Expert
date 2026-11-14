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
  cLF = #10;

function Wrap(const ABody: string): string;
begin
  Result := 'unit U;' + cLF + 'interface' + cLF + 'implementation' + cLF + ABody + cLF + 'end.';
end;

/// <summary>Position des ersten Vorkommens von ANeedle in AText.</summary>
function At(const AText, ANeedle: string): TTextPosition;
var
  mOffset, mIndex: Integer;
begin
  mOffset := Pos(ANeedle, AText) - 1;
  Result := TTextPosition.Create(0, 0);
  for mIndex := 1 to mOffset do
  begin
    if AText[mIndex] = cLF then
    begin
      Inc(Result.Line);
      Result.Character := 0;
    end
    else
    begin
      Inc(Result.Character);
    end;
  end;
end;

/// <summary>Text nach der Aktion, deren Titel AKind enthält ('Inline', 'verschieben', 'aufr'); '' ohne.</summary>
function Run(const AText, ANeedle, AKind: string; const AOptions: TVarBlockOptions; out ATitle: string): string;
var
  mTree: TSyntaxTree;
  mAction: TCodeAction;
begin
  Result := '';
  ATitle := '';
  mTree := TPascalParser.Parse(AText);
  try
    for mAction in TVarBlock.Actions(AText, mTree, At(AText, ANeedle), AOptions) do
    begin
      if Pos(AKind, mAction.Title) > 0 then
      begin
        ATitle := mAction.Title;
        Result := TChangeSignature.ApplyEdits(AText, mAction.Edits);
      end;
    end;
  finally
    mTree.Free;
  end;
end;

function Apply(const AText, ANeedle, AKind: string): string;
var
  mTitle: string;
begin
  Result := Run(AText, ANeedle, AKind, TVarBlockOptions.Default, mTitle);
end;

function Parses(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := Length(mTree.Diagnostics) = 0;
  finally
    mTree.Free;
  end;
end;

procedure TVarBlockTests.SectionVariableBecomesInitializedInline;
var
  mTitle, mChanged: string;
begin
  mChanged := Run(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  Count: Integer;' + cLF +
    '  Name: string;' + cLF +
    'begin' + cLF +
    '  Name := ''x'';' + cLF +
    '  Count := 0;' + cLF +
    '  Writeln(Count, Name);' + cLF +
    'end;'), 'Count:', 'Inline', TVarBlockOptions.Default, mTitle);
  Assert.AreEqual('In Inline-Variable umwandeln (var Count)', mTitle);
  Assert.AreEqual(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  Name: string;' + cLF +
    'begin' + cLF +
    '  Name := ''x'';' + cLF +
    '  var Count := 0;' + cLF +
    '  Writeln(Count, Name);' + cLF +
    'end;'), mChanged);
  Assert.IsTrue(Parses(mChanged));
end;

procedure TVarBlockTests.InlineKeepsTypeWhenNotObvious;
var
  mChanged: string;
begin
  // Von der Verwendung aus aufgerufen; einziger Eintrag: "var" fällt mit weg.
  mChanged := Apply(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  Total: Int64;' + cLF +
    'begin' + cLF +
    '  Total := 0;' + cLF +
    '  Writeln(Total);' + cLF +
    'end;'), 'Total);', 'Inline');
  Assert.AreEqual(Wrap(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  var Total: Int64 := 0;' + cLF +
    '  Writeln(Total);' + cLF +
    'end;'), mChanged);
  Assert.IsTrue(Parses(mChanged));
end;

procedure TVarBlockTests.InlineWithoutStartValueWhenExpressionReadsIt;
var
  mChanged: string;
begin
  mChanged := Apply(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  S: string;' + cLF +
    'begin' + cLF +
    '  Writeln(1);' + cLF +
    '  S := S + ''a'';' + cLF +
    'end;'), 'S:', 'Inline');
  Assert.AreEqual(Wrap(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  Writeln(1);' + cLF +
    '  var S: string;' + cLF +
    '  S := S + ''a'';' + cLF +
    'end;'), mChanged);
  Assert.IsTrue(Parses(mChanged));
end;

procedure TVarBlockTests.CommentsMoveToInline;
var
  mChanged: string;
begin
  mChanged := Apply(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  Name: string;' + cLF +
    '  // Zaehler' + cLF +
    '  { fuer die Liste }' + cLF +
    '  I: Integer; // Anzahl' + cLF +
    'begin' + cLF +
    '  Name := '''';' + cLF +
    '  I := 0;' + cLF +
    '  Writeln(I, Name);' + cLF +
    'end;'), 'I:', 'Inline');
  Assert.AreEqual(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  Name: string;' + cLF +
    'begin' + cLF +
    '  Name := '''';' + cLF +
    '  // Zaehler' + cLF +
    '  { fuer die Liste }' + cLF +
    '  var I := 0; // Anzahl' + cLF +
    '  Writeln(I, Name);' + cLF +
    'end;'), mChanged);
  Assert.IsTrue(Parses(mChanged));
end;

procedure TVarBlockTests.OuterBlockUseDeclaresInOuterBlock;
var
  mChanged: string;
begin
  // Erste Zuweisung im inneren Block, Verwendung danach außen: nicht in den inneren Block.
  mChanged := Apply(Wrap(
    'procedure P(B: Boolean);' + cLF +
    'var' + cLF +
    '  I: Integer;' + cLF +
    'begin' + cLF +
    '  if B then' + cLF +
    '  begin' + cLF +
    '    I := 1;' + cLF +
    '  end;' + cLF +
    '  Writeln(I);' + cLF +
    'end;'), 'I:', 'Inline');
  Assert.AreEqual(Wrap(
    'procedure P(B: Boolean);' + cLF +
    'begin' + cLF +
    '  var I: Integer;' + cLF +
    '  if B then' + cLF +
    '  begin' + cLF +
    '    I := 1;' + cLF +
    '  end;' + cLF +
    '  Writeln(I);' + cLF +
    'end;'), mChanged);
  Assert.IsTrue(Parses(mChanged));
  // Nur im inneren Block verwendet: dorthin.
  mChanged := Apply(Wrap(
    'procedure P(B: Boolean);' + cLF +
    'var' + cLF +
    '  I: Integer;' + cLF +
    'begin' + cLF +
    '  if B then' + cLF +
    '  begin' + cLF +
    '    I := 1;' + cLF +
    '    Writeln(I);' + cLF +
    '  end;' + cLF +
    'end;'), 'I:', 'Inline');
  Assert.AreEqual(Wrap(
    'procedure P(B: Boolean);' + cLF +
    'begin' + cLF +
    '  if B then' + cLF +
    '  begin' + cLF +
    '    var I := 1;' + cLF +
    '    Writeln(I);' + cLF +
    '  end;' + cLF +
    'end;'), mChanged);
  Assert.IsTrue(Parses(mChanged));
end;

procedure TVarBlockTests.TryExceptUseDeclaresBeforeTry;
var
  mChanged: string;
begin
  // Im try-Teil zugewiesen, im except gelesen: Die Deklaration darf nicht in den try-Teil.
  mChanged := Apply(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  I: Integer;' + cLF +
    'begin' + cLF +
    '  try' + cLF +
    '    I := 1;' + cLF +
    '  except' + cLF +
    '    Writeln(I);' + cLF +
    '  end;' + cLF +
    'end;'), 'I:', 'Inline');
  Assert.AreEqual(Wrap(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  var I: Integer;' + cLF +
    '  try' + cLF +
    '    I := 1;' + cLF +
    '  except' + cLF +
    '    Writeln(I);' + cLF +
    '  end;' + cLF +
    'end;'), mChanged);
  Assert.IsTrue(Parses(mChanged));
  // Nur im try-Teil: dort hinein.
  mChanged := Apply(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  I: Integer;' + cLF +
    'begin' + cLF +
    '  try' + cLF +
    '    I := 1;' + cLF +
    '    Writeln(I);' + cLF +
    '  finally' + cLF +
    '    Writeln(2);' + cLF +
    '  end;' + cLF +
    'end;'), 'I:', 'Inline');
  Assert.AreEqual(Wrap(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  try' + cLF +
    '    var I := 1;' + cLF +
    '    Writeln(I);' + cLF +
    '  finally' + cLF +
    '    Writeln(2);' + cLF +
    '  end;' + cLF +
    'end;'), mChanged);
  Assert.IsTrue(Parses(mChanged));
end;

procedure TVarBlockTests.NoInlineInLoopWithoutStartValue;
begin
  // Inc(I) liest I: ohne Startwert begänne jeder Durchlauf mit einer neuen Variablen.
  Assert.AreEqual('', Apply(Wrap(
    'procedure P(B: Boolean);' + cLF +
    'var' + cLF +
    '  I: Integer;' + cLF +
    'begin' + cLF +
    '  while B do' + cLF +
    '  begin' + cLF +
    '    Inc(I);' + cLF +
    '    Writeln(I);' + cLF +
    '  end;' + cLF +
    'end;'), 'I:', 'Inline'));
  // Mit Zuweisung am Anfang des Durchlaufs geht es.
  Assert.AreEqual(Wrap(
    'procedure P(B: Boolean);' + cLF +
    'begin' + cLF +
    '  while B do' + cLF +
    '  begin' + cLF +
    '    var I := 0;' + cLF +
    '    Writeln(I);' + cLF +
    '  end;' + cLF +
    'end;'), Apply(Wrap(
    'procedure P(B: Boolean);' + cLF +
    'var' + cLF +
    '  I: Integer;' + cLF +
    'begin' + cLF +
    '  while B do' + cLF +
    '  begin' + cLF +
    '    I := 0;' + cLF +
    '    Writeln(I);' + cLF +
    '  end;' + cLF +
    'end;'), 'I:', 'Inline'));
end;

procedure TVarBlockTests.NoInlineWhenCaptured;
begin
  Assert.AreEqual('', Apply(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  I: Integer;' + cLF +
    'begin' + cLF +
    '  I := 1;' + cLF +
    '  Run(procedure begin Writeln(I) end);' + cLF +
    'end;'), 'I:', 'Inline'));
  // Verschachtelte Routine
  Assert.AreEqual('', Apply(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  I: Integer;' + cLF +
    '  procedure Show;' + cLF +
    '  begin' + cLF +
    '    Writeln(I);' + cLF +
    '  end;' + cLF +
    'begin' + cLF +
    '  I := 1;' + cLF +
    '  Show;' + cLF +
    'end;'), 'I:', 'Inline'));
  // Bedingte Übersetzung
  Assert.AreEqual('', Apply(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  I: Integer;' + cLF +
    'begin' + cLF +
    '  I := 1;' + cLF +
    '  {$IFDEF DEBUG}' + cLF +
    '  Writeln(I);' + cLF +
    '  {$ENDIF}' + cLF +
    'end;'), 'I:', 'Inline'));
end;

procedure TVarBlockTests.NoInlineWithoutLanguageFeature;
var
  mOptions: TVarBlockOptions;
  mTitle: string;
begin
  mOptions := TVarBlockOptions.Default;
  mOptions.InlineVariables := False;
  Assert.AreEqual('', Run(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  I: Integer;' + cLF +
    'begin' + cLF +
    '  I := 1;' + cLF +
    '  Writeln(I);' + cLF +
    'end;'), 'I:', 'Inline', mOptions, mTitle));
end;

procedure TVarBlockTests.InlineMovesToNewSection;
var
  mTitle, mChanged: string;
begin
  mChanged := Run(Wrap(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  var Count: Integer := 0;' + cLF +
    '  Writeln(Count);' + cLF +
    'end;'), 'Count:', 'verschieben', TVarBlockOptions.Default, mTitle);
  Assert.AreEqual('In var-Block verschieben (Count)', mTitle);
  Assert.AreEqual(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  Count: Integer;' + cLF +
    'begin' + cLF +
    '  Count := 0;' + cLF +
    '  Writeln(Count);' + cLF +
    'end;'), mChanged);
  Assert.IsTrue(Parses(mChanged));
  // Hin und zurück ergibt wieder den Anfang (ohne offensichtlichen Typ).
  Assert.AreEqual(Wrap(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  var Count := 0;' + cLF +
    '  Writeln(Count);' + cLF +
    'end;'), Apply(mChanged, 'Count:', 'Inline'));
end;

procedure TVarBlockTests.InlineWithoutTypeUsesLookup;
var
  mOptions: TVarBlockOptions;
  mTitle, mSource, mChanged: string;
begin
  mSource := Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  A: Integer;' + cLF +
    'begin' + cLF +
    '  A := 1;' + cLF +
    '  var Liste := TStringList.Create;' + cLF +
    '  Writeln(A, Liste.Count);' + cLF +
    'end;');
  // Ohne Typermittlung keine Aktion.
  Assert.AreEqual('', Apply(mSource, 'Liste :=', 'verschieben'));
  mOptions := TVarBlockOptions.Default;
  mOptions.Types :=
    function(ADecl: TSyntaxNode; out AType: string; out AEdits: TArray<TTextEdit>): Boolean
    begin
      AType := 'TStringList';
      AEdits := nil;
      Result := True;
    end;
  mChanged := Run(mSource, 'Liste :=', 'verschieben', mOptions, mTitle);
  Assert.AreEqual(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  A: Integer;' + cLF +
    '  Liste: TStringList;' + cLF +
    'begin' + cLF +
    '  A := 1;' + cLF +
    '  Liste := TStringList.Create;' + cLF +
    '  Writeln(A, Liste.Count);' + cLF +
    'end;'), mChanged);
  Assert.IsTrue(Parses(mChanged));
end;

procedure TVarBlockTests.UninitializedInlineMovesWithComments;
var
  mChanged: string;
begin
  mChanged := Apply(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  A: Integer;' + cLF +
    'begin' + cLF +
    '  A := 1;' + cLF +
    '  // Puffer' + cLF +
    '  var S: string; // fuer Text' + cLF +
    '  S := IntToStr(A);' + cLF +
    'end;'), 'S:', 'verschieben');
  Assert.AreEqual(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  A: Integer;' + cLF +
    '  // Puffer' + cLF +
    '  S: string; // fuer Text' + cLF +
    'begin' + cLF +
    '  A := 1;' + cLF +
    '  S := IntToStr(A);' + cLF +
    'end;'), mChanged);
  Assert.IsTrue(Parses(mChanged));
end;

procedure TVarBlockTests.NoSectionMoveWhenNameMeansSomethingElse;
begin
  // Vor der Deklaration meint I etwas anderes (globale Variable).
  Assert.AreEqual('', Apply(Wrap(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  Writeln(I);' + cLF +
    '  var I: Integer := 0;' + cLF +
    '  Writeln(I);' + cLF +
    'end;'), 'I: Integer', 'verschieben'));
  // Gleichnamige Inline-Variable in einem anderen Block
  Assert.AreEqual('', Apply(Wrap(
    'procedure P(B: Boolean);' + cLF +
    'begin' + cLF +
    '  if B then' + cLF +
    '  begin' + cLF +
    '    var I: Integer := 0;' + cLF +
    '    Writeln(I);' + cLF +
    '  end' + cLF +
    '  else' + cLF +
    '  begin' + cLF +
    '    var I: string := '''';' + cLF +
    '    Writeln(I);' + cLF +
    '  end;' + cLF +
    'end;'), 'I: Integer', 'verschieben'));
  // Ohne Startwert in einer Schleife
  Assert.AreEqual('', Apply(Wrap(
    'procedure P(B: Boolean);' + cLF +
    'begin' + cLF +
    '  while B do' + cLF +
    '  begin' + cLF +
    '    var S: string;' + cLF +
    '    S := S + ''a'';' + cLF +
    '  end;' + cLF +
    'end;'), 'S:', 'verschieben'));
  // Capture in einer anonymen Methode
  Assert.AreEqual('', Apply(Wrap(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  var I: Integer := 0;' + cLF +
    '  Run(procedure begin Writeln(I) end);' + cLF +
    'end;'), 'I:', 'verschieben'));
end;

procedure TVarBlockTests.CleanupRemovesSortsAndMerges;
var
  mTitle, mChanged: string;
begin
  mChanged := Run(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  B: string;' + cLF +
    '  Unused: Integer;' + cLF +
    '  C: Integer;' + cLF +
    '  A: Integer;' + cLF +
    '  // Liste' + cLF +
    '  L: TStringList; // Puffer' + cLF +
    'begin' + cLF +
    '  A := 1;' + cLF +
    '  C := 2;' + cLF +
    '  L := nil;' + cLF +
    '  B := '''';' + cLF +
    'end;'), 'var', 'aufr', TVarBlockOptions.Default, mTitle);
  Assert.AreEqual('var-Block aufr', Copy(mTitle, 1, 14));
  Assert.IsTrue(Pos('(ungenutzt: Unused)', mTitle) > 0);
  Assert.AreEqual(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  A, C: Integer;' + cLF +
    '  // Liste' + cLF +
    '  L: TStringList; // Puffer' + cLF +
    '  B: string;' + cLF +
    'begin' + cLF +
    '  A := 1;' + cLF +
    '  C := 2;' + cLF +
    '  L := nil;' + cLF +
    '  B := '''';' + cLF +
    'end;'), mChanged);
  Assert.IsTrue(Parses(mChanged));
end;

procedure TVarBlockTests.CleanupSplitsWithoutMerge;
var
  mOptions: TVarBlockOptions;
  mTitle, mChanged: string;
begin
  mOptions := TVarBlockOptions.Default;
  mOptions.Merge := False;
  mOptions.Sort := TVarBlockSort.None;
  mChanged := Run(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  I, J: Integer;' + cLF +
    '  A, B: array of Integer;' + cLF +
    'begin' + cLF +
    '  J := 1;' + cLF +
    '  I := J;' + cLF +
    '  A := B;' + cLF +
    'end;'), 'I,', 'aufr', mOptions, mTitle);
  // Typen ohne Namen bleiben zusammen (sonst wären A und B nicht mehr zuweisungsverträglich).
  Assert.AreEqual(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  I: Integer;' + cLF +
    '  J: Integer;' + cLF +
    '  A, B: array of Integer;' + cLF +
    'begin' + cLF +
    '  J := 1;' + cLF +
    '  I := J;' + cLF +
    '  A := B;' + cLF +
    'end;'), mChanged);
  Assert.IsTrue(Parses(mChanged));
end;

procedure TVarBlockTests.CleanupAlphabeticalKeepsComments;
var
  mOptions: TVarBlockOptions;
  mTitle, mChanged: string;
begin
  mOptions := TVarBlockOptions.Default;
  mOptions.Sort := TVarBlockSort.Alpha;
  mChanged := Run(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  { Zaehler' + cLF +
    '    zweite Zeile }' + cLF +
    '  Zahl: Integer;' + cLF +
    '' + cLF +
    '  Text: string;' + cLF +
    '  Anzahl: Integer; // Menge' + cLF +
    'begin' + cLF +
    '  Zahl := 1;' + cLF +
    '  Text := '''';' + cLF +
    '  Anzahl := Zahl;' + cLF +
    'end;'), 'Text:', 'aufr', mOptions, mTitle);
  Assert.AreEqual(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  Anzahl: Integer; // Menge' + cLF +
    '  Text: string;' + cLF +
    '  { Zaehler' + cLF +
    '    zweite Zeile }' + cLF +
    '  Zahl: Integer;' + cLF +
    'begin' + cLF +
    '  Zahl := 1;' + cLF +
    '  Text := '''';' + cLF +
    '  Anzahl := Zahl;' + cLF +
    'end;'), mChanged);
  Assert.IsTrue(Parses(mChanged));
end;

procedure TVarBlockTests.CleanupRemovesWholeSection;
var
  mChanged: string;
begin
  mChanged := Apply(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  // alt' + cLF +
    '  I, J: Integer;' + cLF +
    'begin' + cLF +
    '  Writeln(1);' + cLF +
    'end;'), 'var', 'aufr');
  Assert.AreEqual(Wrap(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  Writeln(1);' + cLF +
    'end;'), mChanged);
  Assert.IsTrue(Parses(mChanged));
end;

procedure TVarBlockTests.NoCleanupWhenTidy;
begin
  Assert.AreEqual('', Apply(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  I, J: Integer;' + cLF +
    '  S: string;' + cLF +
    'begin' + cLF +
    '  I := 1;' + cLF +
    '  J := I;' + cLF +
    '  S := '''';' + cLF +
    'end;'), 'var', 'aufr'));
  // Mit Direktive im Abschnitt kein Aufräumen.
  Assert.AreEqual('', Apply(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  S: string;' + cLF +
    '  {$IFDEF DEBUG}' + cLF +
    '  I: Integer;' + cLF +
    '  {$ENDIF}' + cLF +
    'begin' + cLF +
    '  S := '''';' + cLF +
    'end;'), 'var', 'aufr'));
end;

procedure TVarBlockTests.SortNames;
begin
  Assert.AreEqual<TVarBlockSort>(TVarBlockSort.Alpha, TVarBlock.SortOf('alpha'));
  Assert.AreEqual<TVarBlockSort>(TVarBlockSort.None, TVarBlock.SortOf('NONE'));
  Assert.AreEqual<TVarBlockSort>(TVarBlockSort.Usage, TVarBlock.SortOf('usage'));
  Assert.AreEqual<TVarBlockSort>(TVarBlockSort.Usage, TVarBlock.SortOf('quer'));
  Assert.AreEqual('alpha', TVarBlock.cSortNames[TVarBlockSort.Alpha]);
end;

initialization
  TDUnitX.RegisterTestFixture(TVarBlockTests);

end.
