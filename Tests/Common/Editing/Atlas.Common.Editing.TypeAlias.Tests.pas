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
    procedure TitlesFromTextUnit;
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
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.TypeAlias,
  Atlas.Common.Editing.TypeAlias.Texts;

const
  cUnitKunden =
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
  mIndex, mFound, mLine, mLineStart: Integer;
begin
  mFound := 0;
  mIndex := 0;
  repeat
    mIndex := PosEx(AMarker, AText, mIndex + 1);
    if mIndex = 0 then
    begin
      raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
    end;
    Inc(mFound);
  until mFound = AOccurrence;
  mLine := 0;
  mLineStart := 1;
  for mFound := 1 to mIndex - 1 do
  begin
    if AText[mFound] = #10 then
    begin
      Inc(mLine);
      mLineStart := mFound + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

function EditsOf(const AResult: TTypeAliasResult; const AFileName: string): TArray<TTextEdit>;
var
  mItem: TTypeAliasFileEdits;
begin
  Result := nil;
  for mItem in AResult.Files do
  begin
    if SameText(mItem.FileName, AFileName) then
    begin
      Exit(mItem.Edits);
    end;
  end;
end;

/// <summary>Führt einen Alias an AMarker ein und liefert den neuen Text von AText.</summary>
function Introduce(const AText, AMarker, AName: string; AScope: TTypeAliasScope; out AResult: TTypeAliasResult;
  out AReason: string): string;
var
  mTree: TSyntaxTree;
begin
  Result := '';
  mTree := TPascalParser.Parse(AText);
  try
    if TTypeAlias.Introduce(TTypeAliasSource.Create('Kunden.pas', AText, mTree), nil,
      TTypeAliasRequest.Create(PositionOf(AText, AMarker, 1), AName, AScope, TTypeAliasLookup.FromTree), AResult,
      AReason) then
    begin
      Result := TChangeSignature.ApplyEdits(AText, EditsOf(AResult, 'Kunden.pas'));
    end;
  finally
    mTree.Free;
  end;
end;

function Count(const AText, APart: string): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  mIndex := PosEx(APart, AText, 1);
  while mIndex > 0 do
  begin
    Inc(Result);
    mIndex := PosEx(APart, AText, mIndex + 1);
  end;
end;

procedure TTypeAliasTests.TitlesFromTextUnit;
begin
  // Die Texte stehen in einer eigenen Unit (metric-unit-length); die Titel kommen weiter aus ihr.
  Assert.AreEqual(cTexts[TEditingTypeAliasText.IntroduceTypeAlias].Text, TTypeAlias.IntroduceTitle);
end;

procedure TTypeAliasTests.TargetsAndSuggestions;
var
  mTree: TSyntaxTree;
  mFound: TArray<TTypeAliasTarget>;
begin
  mTree := TPascalParser.Parse(cUnitKunden);
  try
    // Auf dem inneren TList: der äußere Ausdruck zuerst, dann der innere.
    mFound := TTypeAlias.Targets(cUnitKunden, mTree, 'Kunden.pas', PositionOf(cUnitKunden, 'TList<TKunde>>', 1),
      TTypeAliasLookup.FromTree);
    Assert.AreEqual(2, Integer(Length(mFound)));
    Assert.AreEqual('TDictionary<string, TList<TKunde>>', mFound[0].TypeText);
    Assert.AreEqual('TKundeGroups', mFound[0].Suggestion);
    Assert.AreEqual('TList<TKunde>', mFound[1].TypeText);
    Assert.AreEqual('TKundeList', mFound[1].Suggestion);
    Assert.AreEqual('', mFound[0].OpenParams);
    mFound := TTypeAlias.Targets(cUnitKunden, mTree, 'Kunden.pas', PositionOf(cUnitKunden, 'array of array', 1),
      TTypeAliasLookup.FromTree);
    Assert.AreEqual(1, Integer(Length(mFound)));
    Assert.AreEqual('array of array of Double', mFound[0].TypeText);
    Assert.AreEqual('TWerte', mFound[0].Suggestion);
    mFound := TTypeAlias.Targets(cUnitKunden, mTree, 'Kunden.pas', PositionOf(cUnitKunden, 'reference', 1),
      TTypeAliasLookup.FromTree);
    Assert.AreEqual(1, Integer(Length(mFound)));
    Assert.AreEqual('TAktionFunc', mFound[0].Suggestion);
    // Vergebene Namen bekommen eine Zahl.
    mFound := TTypeAlias.Targets(cUnitKunden, mTree, 'Kunden.pas', PositionOf(cUnitKunden, 'TList<TKunde>;', 1),
      TTypeAliasLookup.FromTree);
    Assert.AreEqual('TKundeAktive', mFound[0].Suggestion);
  finally
    mTree.Free;
  end;
end;

procedure TTypeAliasTests.NoTargetForOpenArraysAndDeclarations;
const
  cSource = 'unit U;'#10'interface'#10'type'#10'  TListe = TArray<string>;'#10 +
    'procedure P(const A: array of Integer; B: Integer);'#10'implementation'#10 +
    'procedure P(const A: array of Integer; B: Integer); begin end;'#10'end.';
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.AreEqual(0, Integer(Length(TTypeAlias.Targets(cSource, mTree, 'U.pas', PositionOf(cSource, 'TArray', 1),
      TTypeAliasLookup.FromTree))));
    Assert.AreEqual(0, Integer(Length(TTypeAlias.Targets(cSource, mTree, 'U.pas', PositionOf(cSource, 'array of', 1),
      TTypeAliasLookup.FromTree))));
    Assert.AreEqual(0, Integer(Length(TTypeAlias.Targets(cSource, mTree, 'U.pas', PositionOf(cSource, 'Integer)', 1),
      TTypeAliasLookup.FromTree))));
  finally
    mTree.Free;
  end;
end;

procedure TTypeAliasTests.OpenGenericParamsAreRefused;
const
  cSource = 'unit U;'#10'interface'#10'type'#10'  TBox<T> = class'#10'    FListe: TList<T>;'#10 +
    '    FFest: TList<Integer>;'#10'  end;'#10'implementation'#10'end.';
var
  mTree: TSyntaxTree;
  mFound: TArray<TTypeAliasTarget>;
  mOutcome: TTypeAliasResult;
  mReason: string;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mFound := TTypeAlias.Targets(cSource, mTree, 'U.pas', PositionOf(cSource, 'TList<T>', 1), TTypeAliasLookup.FromTree);
    Assert.AreEqual(1, Integer(Length(mFound)));
    Assert.AreEqual('T', mFound[0].OpenParams);
    Assert.IsFalse(TTypeAlias.Introduce(TTypeAliasSource.Create('U.pas', cSource, mTree), nil,
      TTypeAliasRequest.Create(PositionOf(cSource, 'TList<T>', 1), 'TListe', TTypeAliasScope.InUnit,
      TTypeAliasLookup.FromTree), mOutcome, mReason));
    Assert.IsTrue(Pos('generischen Parameter T', mReason) > 0, mReason);
    mFound := TTypeAlias.Targets(cSource, mTree, 'U.pas', PositionOf(cSource, 'TList<Integer>', 1),
      TTypeAliasLookup.FromTree);
    Assert.AreEqual('', mFound[0].OpenParams);
  finally
    mTree.Free;
  end;
end;

procedure TTypeAliasTests.IntroduceReplacesInUnit;
var
  mOutcome: TTypeAliasResult;
  mReason, mText: string;
begin
  mText := Introduce(cUnitKunden, 'TList<TKunde>;', 'TKundenListe', TTypeAliasScope.InUnit, mOutcome, mReason);
  Assert.AreEqual('', mReason);
  // Vor TVerwaltung, hinter TKunde; ersetzt in Feldern, im Ergebnis, im Typargument und bei qualifiziertem Namen.
  Assert.IsTrue(Pos('  end;'#10'  TKundenListe = TList<TKunde>;'#10'  TVerwaltung = class', mText) > 0, mText);
  Assert.AreEqual(5, mOutcome.Places);
  Assert.IsTrue(Pos('FGroups: TDictionary<string, TKundenListe>;', mText) > 0, mText);
  Assert.IsTrue(Pos('FAktive: TKundenListe;', mText) > 0, mText);
  Assert.IsTrue(Pos('function Liste: TKundenListe;', mText) > 0, mText);
  Assert.IsTrue(Pos('L: TKundenListe;', mText) > 0, mText);
  Assert.AreEqual(1, Count(mText, 'TList<TKunde>'));
  Assert.IsTrue(Pos('zuweisungsverträglich', mOutcome.Preview) > 0, mOutcome.Preview);
end;

procedure TTypeAliasTests.IntroduceHereOnly;
var
  mOutcome: TTypeAliasResult;
  mReason, mText: string;
begin
  mText := Introduce(cUnitKunden, 'TList<TKunde>;', 'TKundenListe', TTypeAliasScope.Here, mOutcome, mReason);
  Assert.AreEqual('', mReason);
  Assert.AreEqual(1, mOutcome.Places);
  Assert.IsTrue(Pos('FAktive: TKundenListe;', mText) > 0, mText);
  Assert.AreEqual(5, Count(mText, 'TList<TKunde>'));
end;

procedure TTypeAliasTests.SelfReferenceGetsForwardDeclaration;
const
  cSource = 'unit U;'#10'interface'#10'type'#10'  TKnoten = class'#10'    FKinder: TList<TKnoten>;'#10'  end;'#10 +
    'implementation'#10'end.';
var
  mOutcome: TTypeAliasResult;
  mReason, mText: string;
begin
  mText := Introduce(cSource, 'TList', 'TKnotenListe', TTypeAliasScope.InUnit, mOutcome, mReason);
  Assert.AreEqual('', mReason);
  Assert.IsTrue(Pos('type'#10'  TKnoten = class;'#10'  TKnotenListe = TList<TKnoten>;'#10'  TKnoten = class'#10 +
    '    FKinder: TKnotenListe;', mText) > 0, mText);
  Assert.AreEqual(1, Integer(Length(mOutcome.Warnings)));
end;

procedure TTypeAliasTests.NewTypeSectionBeforeVar;
const
  cSource = 'unit U;'#10'interface'#10'implementation'#10'uses System.SysUtils;'#10'var'#10 +
    '  G: TArray<string>;'#10'  H: TArray<string>;'#10'end.';
var
  mOutcome: TTypeAliasResult;
  mReason, mText: string;
  mTree: TSyntaxTree;
  mFound: TArray<TTypeAliasTarget>;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mFound := TTypeAlias.Targets(cSource, mTree, 'U.pas', PositionOf(cSource, 'TArray', 1), TTypeAliasLookup.FromTree);
    Assert.AreEqual('TStringArray', mFound[0].Suggestion);
  finally
    mTree.Free;
  end;
  mText := Introduce(cSource, 'TArray', 'TStringArray', TTypeAliasScope.InUnit, mOutcome, mReason);
  Assert.AreEqual('', mReason);
  Assert.AreEqual('unit U;'#10'interface'#10'implementation'#10'uses System.SysUtils;'#10'type'#10 +
    '  TStringArray = TArray<string>;'#10#10'var'#10'  G: TStringArray;'#10'  H: TStringArray;'#10'end.', mText);
end;

procedure TTypeAliasTests.TakenNameIsRefused;
var
  mOutcome: TTypeAliasResult;
  mReason: string;
begin
  Assert.AreEqual('', Introduce(cUnitKunden, 'TList<TKunde>;', 'TKunde', TTypeAliasScope.InUnit, mOutcome, mReason));
  Assert.IsTrue(Pos('schon vergeben', mReason) > 0, mReason);
  Assert.AreEqual('', Introduce(cUnitKunden, 'TList<TKunde>;', 'begin', TTypeAliasScope.InUnit, mOutcome, mReason));
  Assert.IsTrue(Pos('kein gültiger Bezeichner', mReason) > 0, mReason);
end;

procedure TTypeAliasTests.IntroduceAcrossProject;
const
  cNutzer = 'unit Nutzer;'#10'interface'#10'uses Kunden, System.Generics.Collections;'#10'var'#10 +
    '  X: TList<TKunde>;'#10'implementation'#10'end.';
  cFremd = 'unit Fremd;'#10'interface'#10'uses System.Generics.Collections;'#10'type'#10'  TKunde = class end;'#10 +
    'var'#10'  Y: TList<TKunde>;'#10'implementation'#10'end.';
var
  mTree, mNutzerTree, mFremdTree: TSyntaxTree;
  mOutcome: TTypeAliasResult;
  mReason: string;
begin
  mTree := TPascalParser.Parse(cUnitKunden);
  mNutzerTree := TPascalParser.Parse(cNutzer);
  mFremdTree := TPascalParser.Parse(cFremd);
  try
    Assert.IsTrue(TTypeAlias.Introduce(TTypeAliasSource.Create('Kunden.pas', cUnitKunden, mTree),
      [TTypeAliasSource.Create('Nutzer.pas', cNutzer, mNutzerTree), TTypeAliasSource.Create('Fremd.pas', cFremd,
      mFremdTree)], TTypeAliasRequest.Create(PositionOf(cUnitKunden, 'TList<TKunde>;', 1), 'TKundenListe',
      TTypeAliasScope.Project, TTypeAliasLookup.FromTree), mOutcome, mReason), mReason);
    Assert.AreEqual(6, mOutcome.Places);
    Assert.IsTrue(Pos('X: TKundenListe;', TChangeSignature.ApplyEdits(cNutzer, EditsOf(mOutcome, 'Nutzer.pas'))) > 0);
    // Fremd bindet Kunden nicht ein und deklariert TKunde selbst.
    Assert.AreEqual(0, Integer(Length(EditsOf(mOutcome, 'Fremd.pas'))));
    Assert.AreEqual(1, Integer(Length(mOutcome.Warnings)));
  finally
    mFremdTree.Free;
    mNutzerTree.Free;
    mTree.Free;
  end;
end;

procedure TTypeAliasTests.InlineReplacesAndRemoves;
const
  cSource = 'unit U;'#10'interface'#10'uses System.Generics.Collections;'#10'type'#10'  TKunde = class end;'#10 +
    '  TListe = TList<TKunde>;'#10'  TVerwaltung = class'#10'    FListe: TListe;'#10 +
    '    procedure Setze(const A: TListe);'#10'  end;'#10'implementation'#10 +
    'procedure TVerwaltung.Setze(const A: TListe);'#10'begin'#10'  FListe := TListe.Create;'#10'  FListe := U.TListe.Create;'#10'end;'#10'end.';
var
  mTree: TSyntaxTree;
  mOutcome: TTypeAliasResult;
  mReason, mText: string;
  mOffsets: TArray<Integer>;
  mIndex: Integer;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mOffsets := nil;
    mIndex := PosEx('TListe', cSource, 1);
    while mIndex > 0 do
    begin
      mOffsets := mOffsets + [mIndex - 1];
      mIndex := PosEx('TListe', cSource, mIndex + 1);
    end;
    Assert.IsTrue(TTypeAlias.InlineAlias(TTypeAliasSource.Create('U.pas', cSource, mTree, mOffsets), nil,
      PositionOf(cSource, 'TListe =', 1), TTypeAliasLookup.FromTree, mOutcome, mReason), mReason);
    mText := TChangeSignature.ApplyEdits(cSource, EditsOf(mOutcome, 'U.pas'));
    Assert.AreEqual(5, mOutcome.Places);
    Assert.AreEqual(0, Count(mText, 'TListe'));
    Assert.AreEqual(2, Count(mText, 'FListe := TList<TKunde>.Create;'));
    Assert.IsTrue(Pos('FListe: TList<TKunde>;', mText) > 0, mText);
    Assert.IsTrue(Pos('const A: TList<TKunde>', mText) > 0, mText);
    Assert.IsTrue(Pos('FListe := TList<TKunde>.Create;', mText) > 0, mText);
    Assert.IsTrue(Pos('  TKunde = class end;'#10'  TVerwaltung = class', mText) > 0, mText);
  finally
    mTree.Free;
  end;
end;

procedure TTypeAliasTests.InlineKeepsAliasWhereTypeNameNeeded;
const
  cSource = 'unit U;'#10'interface'#10'type'#10'  TWerte = array of Double;'#10'var'#10'  W: TWerte;'#10 +
    'procedure P(const A: TWerte);'#10'implementation'#10'procedure P(const A: TWerte); begin end;'#10'end.';
var
  mTree: TSyntaxTree;
  mOutcome: TTypeAliasResult;
  mReason, mText: string;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.IsTrue(TTypeAlias.InlineAlias(TTypeAliasSource.Create('U.pas', cSource, mTree,
      [PosEx('TWerte', cSource, 1) - 1, PosEx('TWerte;', cSource, 1) - 1, PosEx('TWerte)', cSource, 1) - 1,
      PosEx('TWerte)', cSource, PosEx('TWerte)', cSource, 1) + 1) - 1]), nil, PositionOf(cSource, 'TWerte =', 1),
      TTypeAliasLookup.FromTree, mOutcome, mReason), mReason);
    mText := TChangeSignature.ApplyEdits(cSource, EditsOf(mOutcome, 'U.pas'));
    Assert.AreEqual(1, mOutcome.Places);
    Assert.IsTrue(Pos('W: array of Double;', mText) > 0, mText);
    Assert.IsTrue(Pos('TWerte = array of Double;', mText) > 0, mText);
    Assert.AreEqual(1, Integer(Length(mOutcome.Warnings)));
  finally
    mTree.Free;
  end;
end;

procedure TTypeAliasTests.InlineRefusesStrongAlias;
const
  cSource = 'unit U;'#10'interface'#10'type'#10'  TNeu = type Integer;'#10'  TKlasse = class end;'#10 +
    'implementation'#10'end.';
var
  mTree: TSyntaxTree;
  mTarget: TInlineAliasTarget;
  mReason: string;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.IsFalse(TTypeAlias.InlineTarget(cSource, mTree, PositionOf(cSource, 'TNeu', 1), mTarget, mReason));
    Assert.IsTrue(Pos('eigener Typ', mReason) > 0, mReason);
    Assert.IsFalse(TTypeAlias.InlineTarget(cSource, mTree, PositionOf(cSource, 'TKlasse', 1), mTarget, mReason));
    Assert.IsTrue(Pos('kein Alias', mReason) > 0, mReason);
  finally
    mTree.Free;
  end;
end;

procedure TTypeAliasTests.ScopeNames;
var
  mScope: TTypeAliasScope;
begin
  Assert.IsTrue(TTypeAlias.ScopeOf('project', mScope));
  Assert.AreEqual<TTypeAliasScope>(TTypeAliasScope.Project, mScope);
  Assert.AreEqual('here', TTypeAlias.ScopeName(TTypeAliasScope.Here));
  Assert.AreEqual('unit', TTypeAlias.ScopeName(TTypeAliasScope.InUnit));
  Assert.IsFalse(TTypeAlias.ScopeOf('alles', mScope));
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeAliasTests);

end.
