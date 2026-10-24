unit Atlas.Common.Editing.TypeAlias.Tests;

// Tests für „Typ-Alias einführen“ und „Alias auflösen“ (#681): Ziele und
// Namensvorschläge für Generics, dynamische Arrays und Methodenreferenzen,
// kein Ziel bei offenen Arrays und offenen generischen Parametern, Ersetzen
// an der Stelle, in der Unit und im Projekt, Vorwärtsdeklaration bei
// Selbstbezug, neuer type-Abschnitt vor var, Namenskonflikt, Auflösen samt
// Entfernen und Stellen, die einen Typnamen brauchen, X = type Y.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTypeAliasTests = class
  public
    [Test]
    procedure TargetsAndSuggestions;
    [Test]
    procedure NoTargetForOpenArraysAndDeclarations;
    [Test]
    procedure OpenGenericParamsAreRefused;
    [Test]
    procedure IntroduceReplacesInUnit;
    [Test]
    procedure IntroduceHereOnly;
    [Test]
    procedure SelfReferenceGetsForwardDeclaration;
    [Test]
    procedure NewTypeSectionBeforeVar;
    [Test]
    procedure TakenNameIsRefused;
    [Test]
    procedure IntroduceAcrossProject;
    [Test]
    procedure InlineReplacesAndRemoves;
    [Test]
    procedure InlineKeepsAliasWhereTypeNameNeeded;
    [Test]
    procedure InlineRefusesStrongAlias;
    [Test]
    procedure ScopeNames;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.TypeAlias;

const
  UnitKunden =
    'unit Kunden;'#10 +
    'interface'#10 +
    'uses System.Generics.Collections;'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '  end;'#10 +
    '  TVerwaltung = class'#10 +
    '  private'#10 +
    '    FGroups: TDictionary<string, TList<TKunde>>;'#10 +
    '    FAktive: TList<TKunde>;'#10 +
    '    FWerte: array of array of Double;'#10 +
    '    FAktion: reference to function(A: Integer): string;'#10 +
    '  public'#10 +
    '    procedure Summe(const A: array of Integer);'#10 +
    '    function Liste: TList<TKunde>;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TVerwaltung.Summe(const A: array of Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'function TVerwaltung.Liste: TList<TKunde>;'#10 +
    'var'#10 +
    '  L: System.Generics.Collections.TList<TKunde>;'#10 +
    'begin'#10 +
    '  Result := L;'#10 +
    'end;'#10 +
    'end.';

function PositionOf(const AText, AMarker: string; AOccurrence: Integer): TTextPosition;
var
  Index, Found, Line, LineStart: Integer;
begin
  Found := 0;
  Index := 0;
  repeat
    Index := PosEx(AMarker, AText, Index + 1);
    if Index = 0 then
      raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
    Inc(Found);
  until Found = AOccurrence;
  Line := 0;
  LineStart := 1;
  for Found := 1 to Index - 1 do
    if AText[Found] = #10 then
    begin
      Inc(Line);
      LineStart := Found + 1;
    end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

function EditsOf(const AResult: TTypeAliasResult; const AFileName: string): TArray<TTextEdit>;
var
  Item: TTypeAliasFileEdits;
begin
  Result := nil;
  for Item in AResult.Files do
    if SameText(Item.FileName, AFileName) then
      Exit(Item.Edits);
end;

/// <summary>Führt einen Alias an AMarker ein und liefert den neuen Text von AText.</summary>
function Introduce(const AText, AMarker, AName: string; AScope: TTypeAliasScope; out AResult: TTypeAliasResult;
  out AReason: string): string;
var
  Tree: TSyntaxTree;
begin
  Result := '';
  Tree := TPascalParser.Parse(AText);
  try
    if TTypeAlias.Introduce(TTypeAliasSource.Create('Kunden.pas', AText, Tree), nil, PositionOf(AText, AMarker, 1),
      AName, AScope, TTypeAliasLookup.FromTree, AResult, AReason) then
      Result := TChangeSignature.ApplyEdits(AText, EditsOf(AResult, 'Kunden.pas'));
  finally
    Tree.Free;
  end;
end;

function Count(const AText, APart: string): Integer;
var
  Index: Integer;
begin
  Result := 0;
  Index := PosEx(APart, AText, 1);
  while Index > 0 do
  begin
    Inc(Result);
    Index := PosEx(APart, AText, Index + 1);
  end;
end;

procedure TTypeAliasTests.TargetsAndSuggestions;
var
  Tree: TSyntaxTree;
  Found: TArray<TTypeAliasTarget>;
begin
  Tree := TPascalParser.Parse(UnitKunden);
  try
    // Auf dem inneren TList: der äußere Ausdruck zuerst, dann der innere.
    Found := TTypeAlias.Targets(UnitKunden, Tree, 'Kunden.pas', PositionOf(UnitKunden, 'TList<TKunde>>', 1),
      TTypeAliasLookup.FromTree);
    Assert.AreEqual(2, Integer(Length(Found)));
    Assert.AreEqual('TDictionary<string, TList<TKunde>>', Found[0].TypeText);
    Assert.AreEqual('TKundeGroups', Found[0].Suggestion);
    Assert.AreEqual('TList<TKunde>', Found[1].TypeText);
    Assert.AreEqual('TKundeList', Found[1].Suggestion);
    Assert.AreEqual('', Found[0].OpenParams);
    Found := TTypeAlias.Targets(UnitKunden, Tree, 'Kunden.pas', PositionOf(UnitKunden, 'array of array', 1),
      TTypeAliasLookup.FromTree);
    Assert.AreEqual(1, Integer(Length(Found)));
    Assert.AreEqual('array of array of Double', Found[0].TypeText);
    Assert.AreEqual('TWerte', Found[0].Suggestion);
    Found := TTypeAlias.Targets(UnitKunden, Tree, 'Kunden.pas', PositionOf(UnitKunden, 'reference', 1),
      TTypeAliasLookup.FromTree);
    Assert.AreEqual(1, Integer(Length(Found)));
    Assert.AreEqual('TAktionFunc', Found[0].Suggestion);
    // Vergebene Namen bekommen eine Zahl.
    Found := TTypeAlias.Targets(UnitKunden, Tree, 'Kunden.pas', PositionOf(UnitKunden, 'TList<TKunde>;', 1),
      TTypeAliasLookup.FromTree);
    Assert.AreEqual('TKundeAktive', Found[0].Suggestion);
  finally
    Tree.Free;
  end;
end;

procedure TTypeAliasTests.NoTargetForOpenArraysAndDeclarations;
const
  Source = 'unit U;'#10'interface'#10'type'#10'  TListe = TArray<string>;'#10 +
    'procedure P(const A: array of Integer; B: Integer);'#10'implementation'#10 +
    'procedure P(const A: array of Integer; B: Integer); begin end;'#10'end.';
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Assert.AreEqual(0, Integer(Length(TTypeAlias.Targets(Source, Tree, 'U.pas', PositionOf(Source, 'TArray', 1),
      TTypeAliasLookup.FromTree))));
    Assert.AreEqual(0, Integer(Length(TTypeAlias.Targets(Source, Tree, 'U.pas', PositionOf(Source, 'array of', 1),
      TTypeAliasLookup.FromTree))));
    Assert.AreEqual(0, Integer(Length(TTypeAlias.Targets(Source, Tree, 'U.pas', PositionOf(Source, 'Integer)', 1),
      TTypeAliasLookup.FromTree))));
  finally
    Tree.Free;
  end;
end;

procedure TTypeAliasTests.OpenGenericParamsAreRefused;
const
  Source = 'unit U;'#10'interface'#10'type'#10'  TBox<T> = class'#10'    FListe: TList<T>;'#10 +
    '    FFest: TList<Integer>;'#10'  end;'#10'implementation'#10'end.';
var
  Tree: TSyntaxTree;
  Found: TArray<TTypeAliasTarget>;
  Outcome: TTypeAliasResult;
  Reason: string;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Found := TTypeAlias.Targets(Source, Tree, 'U.pas', PositionOf(Source, 'TList<T>', 1), TTypeAliasLookup.FromTree);
    Assert.AreEqual(1, Integer(Length(Found)));
    Assert.AreEqual('T', Found[0].OpenParams);
    Assert.IsFalse(TTypeAlias.Introduce(TTypeAliasSource.Create('U.pas', Source, Tree), nil,
      PositionOf(Source, 'TList<T>', 1), 'TListe', TTypeAliasScope.InUnit, TTypeAliasLookup.FromTree, Outcome,
      Reason));
    Assert.IsTrue(Pos('generischen Parameter T', Reason) > 0, Reason);
    Found := TTypeAlias.Targets(Source, Tree, 'U.pas', PositionOf(Source, 'TList<Integer>', 1),
      TTypeAliasLookup.FromTree);
    Assert.AreEqual('', Found[0].OpenParams);
  finally
    Tree.Free;
  end;
end;

procedure TTypeAliasTests.IntroduceReplacesInUnit;
var
  Outcome: TTypeAliasResult;
  Reason, Text: string;
begin
  Text := Introduce(UnitKunden, 'TList<TKunde>;', 'TKundenListe', TTypeAliasScope.InUnit, Outcome, Reason);
  Assert.AreEqual('', Reason);
  // Vor TVerwaltung, hinter TKunde; ersetzt in Feldern, im Ergebnis, im Typargument und bei qualifiziertem Namen.
  Assert.IsTrue(Pos('  end;'#10'  TKundenListe = TList<TKunde>;'#10'  TVerwaltung = class', Text) > 0, Text);
  Assert.AreEqual(5, Outcome.Places);
  Assert.IsTrue(Pos('FGroups: TDictionary<string, TKundenListe>;', Text) > 0, Text);
  Assert.IsTrue(Pos('FAktive: TKundenListe;', Text) > 0, Text);
  Assert.IsTrue(Pos('function Liste: TKundenListe;', Text) > 0, Text);
  Assert.IsTrue(Pos('L: TKundenListe;', Text) > 0, Text);
  Assert.AreEqual(1, Count(Text, 'TList<TKunde>'));
  Assert.IsTrue(Pos('zuweisungsverträglich', Outcome.Preview) > 0, Outcome.Preview);
end;

procedure TTypeAliasTests.IntroduceHereOnly;
var
  Outcome: TTypeAliasResult;
  Reason, Text: string;
begin
  Text := Introduce(UnitKunden, 'TList<TKunde>;', 'TKundenListe', TTypeAliasScope.Here, Outcome, Reason);
  Assert.AreEqual('', Reason);
  Assert.AreEqual(1, Outcome.Places);
  Assert.IsTrue(Pos('FAktive: TKundenListe;', Text) > 0, Text);
  Assert.AreEqual(5, Count(Text, 'TList<TKunde>'));
end;

procedure TTypeAliasTests.SelfReferenceGetsForwardDeclaration;
const
  Source = 'unit U;'#10'interface'#10'type'#10'  TKnoten = class'#10'    FKinder: TList<TKnoten>;'#10'  end;'#10 +
    'implementation'#10'end.';
var
  Outcome: TTypeAliasResult;
  Reason, Text: string;
begin
  Text := Introduce(Source, 'TList', 'TKnotenListe', TTypeAliasScope.InUnit, Outcome, Reason);
  Assert.AreEqual('', Reason);
  Assert.IsTrue(Pos('type'#10'  TKnoten = class;'#10'  TKnotenListe = TList<TKnoten>;'#10'  TKnoten = class'#10 +
    '    FKinder: TKnotenListe;', Text) > 0, Text);
  Assert.AreEqual(1, Integer(Length(Outcome.Warnings)));
end;

procedure TTypeAliasTests.NewTypeSectionBeforeVar;
const
  Source = 'unit U;'#10'interface'#10'implementation'#10'uses System.SysUtils;'#10'var'#10 +
    '  G: TArray<string>;'#10'  H: TArray<string>;'#10'end.';
var
  Outcome: TTypeAliasResult;
  Reason, Text: string;
  Tree: TSyntaxTree;
  Found: TArray<TTypeAliasTarget>;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Found := TTypeAlias.Targets(Source, Tree, 'U.pas', PositionOf(Source, 'TArray', 1), TTypeAliasLookup.FromTree);
    Assert.AreEqual('TStringArray', Found[0].Suggestion);
  finally
    Tree.Free;
  end;
  Text := Introduce(Source, 'TArray', 'TStringArray', TTypeAliasScope.InUnit, Outcome, Reason);
  Assert.AreEqual('', Reason);
  Assert.AreEqual('unit U;'#10'interface'#10'implementation'#10'uses System.SysUtils;'#10'type'#10 +
    '  TStringArray = TArray<string>;'#10#10'var'#10'  G: TStringArray;'#10'  H: TStringArray;'#10'end.', Text);
end;

procedure TTypeAliasTests.TakenNameIsRefused;
var
  Outcome: TTypeAliasResult;
  Reason: string;
begin
  Assert.AreEqual('', Introduce(UnitKunden, 'TList<TKunde>;', 'TKunde', TTypeAliasScope.InUnit, Outcome, Reason));
  Assert.IsTrue(Pos('schon vergeben', Reason) > 0, Reason);
  Assert.AreEqual('', Introduce(UnitKunden, 'TList<TKunde>;', 'begin', TTypeAliasScope.InUnit, Outcome, Reason));
  Assert.IsTrue(Pos('kein gültiger Bezeichner', Reason) > 0, Reason);
end;

procedure TTypeAliasTests.IntroduceAcrossProject;
const
  Nutzer = 'unit Nutzer;'#10'interface'#10'uses Kunden, System.Generics.Collections;'#10'var'#10 +
    '  X: TList<TKunde>;'#10'implementation'#10'end.';
  Fremd = 'unit Fremd;'#10'interface'#10'uses System.Generics.Collections;'#10'type'#10'  TKunde = class end;'#10 +
    'var'#10'  Y: TList<TKunde>;'#10'implementation'#10'end.';
var
  Tree, NutzerTree, FremdTree: TSyntaxTree;
  Outcome: TTypeAliasResult;
  Reason: string;
begin
  Tree := TPascalParser.Parse(UnitKunden);
  NutzerTree := TPascalParser.Parse(Nutzer);
  FremdTree := TPascalParser.Parse(Fremd);
  try
    Assert.IsTrue(TTypeAlias.Introduce(TTypeAliasSource.Create('Kunden.pas', UnitKunden, Tree),
      [TTypeAliasSource.Create('Nutzer.pas', Nutzer, NutzerTree), TTypeAliasSource.Create('Fremd.pas', Fremd,
      FremdTree)], PositionOf(UnitKunden, 'TList<TKunde>;', 1), 'TKundenListe', TTypeAliasScope.Project,
      TTypeAliasLookup.FromTree, Outcome, Reason), Reason);
    Assert.AreEqual(6, Outcome.Places);
    Assert.IsTrue(Pos('X: TKundenListe;', TChangeSignature.ApplyEdits(Nutzer, EditsOf(Outcome, 'Nutzer.pas'))) > 0);
    // Fremd bindet Kunden nicht ein und deklariert TKunde selbst.
    Assert.AreEqual(0, Integer(Length(EditsOf(Outcome, 'Fremd.pas'))));
    Assert.AreEqual(1, Integer(Length(Outcome.Warnings)));
  finally
    FremdTree.Free;
    NutzerTree.Free;
    Tree.Free;
  end;
end;

procedure TTypeAliasTests.InlineReplacesAndRemoves;
const
  Source = 'unit U;'#10'interface'#10'uses System.Generics.Collections;'#10'type'#10'  TKunde = class end;'#10 +
    '  TListe = TList<TKunde>;'#10'  TVerwaltung = class'#10'    FListe: TListe;'#10 +
    '    procedure Setze(const A: TListe);'#10'  end;'#10'implementation'#10 +
    'procedure TVerwaltung.Setze(const A: TListe);'#10'begin'#10'  FListe := TListe.Create;'#10'  FListe := U.TListe.Create;'#10'end;'#10'end.';
var
  Tree: TSyntaxTree;
  Outcome: TTypeAliasResult;
  Reason, Text: string;
  Offsets: TArray<Integer>;
  Index: Integer;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Offsets := nil;
    Index := PosEx('TListe', Source, 1);
    while Index > 0 do
    begin
      Offsets := Offsets + [Index - 1];
      Index := PosEx('TListe', Source, Index + 1);
    end;
    Assert.IsTrue(TTypeAlias.InlineAlias(TTypeAliasSource.Create('U.pas', Source, Tree, Offsets), nil,
      PositionOf(Source, 'TListe =', 1), TTypeAliasLookup.FromTree, Outcome, Reason), Reason);
    Text := TChangeSignature.ApplyEdits(Source, EditsOf(Outcome, 'U.pas'));
    Assert.AreEqual(5, Outcome.Places);
    Assert.AreEqual(0, Count(Text, 'TListe'));
    Assert.AreEqual(2, Count(Text, 'FListe := TList<TKunde>.Create;'));
    Assert.IsTrue(Pos('FListe: TList<TKunde>;', Text) > 0, Text);
    Assert.IsTrue(Pos('const A: TList<TKunde>', Text) > 0, Text);
    Assert.IsTrue(Pos('FListe := TList<TKunde>.Create;', Text) > 0, Text);
    Assert.IsTrue(Pos('  TKunde = class end;'#10'  TVerwaltung = class', Text) > 0, Text);
  finally
    Tree.Free;
  end;
end;

procedure TTypeAliasTests.InlineKeepsAliasWhereTypeNameNeeded;
const
  Source = 'unit U;'#10'interface'#10'type'#10'  TWerte = array of Double;'#10'var'#10'  W: TWerte;'#10 +
    'procedure P(const A: TWerte);'#10'implementation'#10'procedure P(const A: TWerte); begin end;'#10'end.';
var
  Tree: TSyntaxTree;
  Outcome: TTypeAliasResult;
  Reason, Text: string;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Assert.IsTrue(TTypeAlias.InlineAlias(TTypeAliasSource.Create('U.pas', Source, Tree,
      [PosEx('TWerte', Source, 1) - 1, PosEx('TWerte;', Source, 1) - 1, PosEx('TWerte)', Source, 1) - 1,
      PosEx('TWerte)', Source, PosEx('TWerte)', Source, 1) + 1) - 1]), nil, PositionOf(Source, 'TWerte =', 1),
      TTypeAliasLookup.FromTree, Outcome, Reason), Reason);
    Text := TChangeSignature.ApplyEdits(Source, EditsOf(Outcome, 'U.pas'));
    Assert.AreEqual(1, Outcome.Places);
    Assert.IsTrue(Pos('W: array of Double;', Text) > 0, Text);
    Assert.IsTrue(Pos('TWerte = array of Double;', Text) > 0, Text);
    Assert.AreEqual(1, Integer(Length(Outcome.Warnings)));
  finally
    Tree.Free;
  end;
end;

procedure TTypeAliasTests.InlineRefusesStrongAlias;
const
  Source = 'unit U;'#10'interface'#10'type'#10'  TNeu = type Integer;'#10'  TKlasse = class end;'#10 +
    'implementation'#10'end.';
var
  Tree: TSyntaxTree;
  Target: TInlineAliasTarget;
  Reason: string;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Assert.IsFalse(TTypeAlias.InlineTarget(Source, Tree, PositionOf(Source, 'TNeu', 1), Target, Reason));
    Assert.IsTrue(Pos('eigener Typ', Reason) > 0, Reason);
    Assert.IsFalse(TTypeAlias.InlineTarget(Source, Tree, PositionOf(Source, 'TKlasse', 1), Target, Reason));
    Assert.IsTrue(Pos('kein Alias', Reason) > 0, Reason);
  finally
    Tree.Free;
  end;
end;

procedure TTypeAliasTests.ScopeNames;
var
  Scope: TTypeAliasScope;
begin
  Assert.IsTrue(TTypeAlias.ScopeOf('project', Scope));
  Assert.IsTrue(Scope = TTypeAliasScope.Project);
  Assert.AreEqual('here', TTypeAlias.ScopeName(TTypeAliasScope.Here));
  Assert.AreEqual('unit', TTypeAlias.ScopeName(TTypeAliasScope.InUnit));
  Assert.IsFalse(TTypeAlias.ScopeOf('alles', Scope));
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeAliasTests);

end.
