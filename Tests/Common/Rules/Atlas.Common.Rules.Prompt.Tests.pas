unit Atlas.Common.Rules.Prompt.Tests;

// Tests für den Auftrag an einen KI-Assistenten (#158, #2570): ein Befund mit Ausschnitt ±8 Zeilen und
// Schlusszeile, sichere Korrektur mit fix_findings, weitere Stellen, mehrere Befunde nach Datei mit
// zusammengelegten Ausschnitten, Obergrenze, Compilermeldung und englische Texte.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFindingPromptTests = class
  public
    [Test]
    procedure OneFindingHasContextAndCheckLine;
    [Test]
    procedure SafeFixRuleNamesFixFindings;
    [Test]
    procedure RelatedLocationsAreListed;
    [Test]
    procedure ManyGroupsByFileAndMergesSnippets;
    [Test]
    procedure ManyExplainsEachRuleOnce;
    [Test]
    procedure ManyRespectsLimit;
    [Test]
    procedure CompilerMessageHasNoConfidenceAndNoFix;
    [Test]
    procedure EnglishTexts;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Prompt,
  Atlas.Common.Localization.Texts;

/// <summary>Text mit ACount Zeilen "z1" bis "zN".</summary>
function Numbered(ACount: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 1 to ACount do
  begin
    Result := Result + 'z' + IntToStr(mIndex) + #13#10;
  end;
end;

function Finding(const ARuleId: string; ALine: Integer): TRuleFinding;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := ARuleId;
  Result.Range := TTextRange.Create(ALine, 2, ALine, 6);
  Result.Message := 'Meldung ' + ARuleId;
  Result.Severity := TRuleSeverity.Warning;
  Result.Confidence := TRuleConfidence.High;
end;

function Item(const AFileName: string; const AFinding: TRuleFinding): TFindingPromptItem;
begin
  Result := TFindingPromptItem.Create(AFinding, AFileName, Numbered(40));
end;

function Occurrences(const AText, APart: string): Integer;
var
  mPos: Integer;
begin
  Result := 0;
  mPos := Pos(APart, AText);
  while mPos > 0 do
  begin
    Inc(Result);
    mPos := Pos(APart, AText, mPos + Length(APart));
  end;
end;

/// <summary>Erste Regel des Katalogs mit sicherer Korrektur.</summary>
function SafeRule(ACatalog: TRuleCatalog): TRuleCatalogEntry;
var
  mEntry: TRuleCatalogEntry;
begin
  for mEntry in ACatalog.Entries do
  begin
    if mEntry.SafeFix then
    begin
      Exit(mEntry);
    end;
  end;
  Result := Default(TRuleCatalogEntry);
end;

{ TFindingPromptTests }

procedure TFindingPromptTests.OneFindingHasContextAndCheckLine;
var
  mText: string;
begin
  mText := TFindingPrompt.Markdown(Finding('test-regel', 10), 'U.pas', Numbered(40), nil);
  Assert.Contains(mText, '## Befund test-regel');
  Assert.Contains(mText, '>   11 | z11');
  Assert.Contains(mText, '     3 | z3');
  Assert.Contains(mText, '    19 | z19');
  Assert.IsFalse(mText.Contains('   2 | z2' + #13#10), 'nur ±8 Zeilen');
  Assert.IsFalse(mText.Contains('| z20'), 'nur ±8 Zeilen');
  Assert.Contains(mText, 'Prüfen mit: `check_code` (file: `U.pas`)');
  Assert.IsFalse(mText.Contains('fix_findings'), 'ohne Katalog keine Korrektur');
end;

procedure TFindingPromptTests.SafeFixRuleNamesFixFindings;
var
  mCatalog: TRuleCatalog;
  mEntry: TRuleCatalogEntry;
  mText: string;
begin
  mCatalog := TFindingPrompt.GermanCatalog;
  try
    mEntry := SafeRule(mCatalog);
    Assert.AreNotEqual('', mEntry.Id, 'Katalog hat Regeln mit safeFix');
    mText := TFindingPrompt.Markdown(Finding(mEntry.Id, 3), 'Src/U.pas', Numbered(10), mCatalog);
  finally
    mCatalog.Free;
  end;
  Assert.Contains(mText, 'Korrigieren mit: `fix_findings` (rules: ["' + mEntry.Id + '"], file: `Src/U.pas`)');
  Assert.Contains(mText, '### Regel');
end;

procedure TFindingPromptTests.RelatedLocationsAreListed;
var
  mFinding: TRuleFinding;
  mRelated: TRuleRelated;
  mText: string;
begin
  mFinding := Finding('uses-cycle', 1);
  mRelated := Default(TRuleRelated);
  mRelated.FileName := 'B.pas';
  mRelated.Range := TTextRange.Create(6, 2, 6, 3);
  mRelated.Message := 'uses A';
  mFinding.Related := TArray<TRuleRelated>.Create(mRelated);
  mText := TFindingPrompt.Markdown(mFinding, 'A.pas', Numbered(5), nil);
  Assert.Contains(mText, '- Weitere Stellen:');
  Assert.Contains(mText, '  - `B.pas`, Zeile 7: uses A');
end;

procedure TFindingPromptTests.ManyGroupsByFileAndMergesSnippets;
var
  mText: string;
begin
  mText := TFindingPrompt.Many(TArray<TFindingPromptItem>.Create(Item('A.pas', Finding('test-b', 8)),
    Item('B.pas', Finding('test-a', 2)), Item('A.pas', Finding('test-a', 5))), nil, 3, 20);
  Assert.StartsWith('# 3 Befunde in 2 Dateien beheben', mText);
  Assert.AreEqual(1, Occurrences(mText, '## Datei `A.pas`'));
  Assert.AreEqual(1, Occurrences(mText, '## Datei `B.pas`'));
  Assert.IsTrue(Pos('## Datei `A.pas`', mText) < Pos('## Datei `B.pas`', mText), 'Dateien in Reihenfolge');
  Assert.IsTrue(Pos('Zeile 6, Spalte 3', mText) < Pos('Zeile 9, Spalte 3', mText), 'nach Zeile sortiert');
  // Zeilen 6 und 9 mit ±3: ein Ausschnitt 3..12, jede Zeile einmal.
  Assert.AreEqual(2, Occurrences(mText, '### Code'));
  Assert.AreEqual(1, Occurrences(mText, '>    6 | z6'));
  Assert.AreEqual(1, Occurrences(mText, '>    9 | z9'));
  Assert.AreEqual(1, Occurrences(mText, '     7 | z7'));
  Assert.AreEqual(1, Occurrences(mText, 'Prüfen mit: `check_code` (file: `A.pas`)'));
  Assert.AreEqual(1, Occurrences(mText, 'Prüfen mit: `check_code` (file: `B.pas`)'));
end;

procedure TFindingPromptTests.ManyExplainsEachRuleOnce;
var
  mCatalog: TRuleCatalog;
  mEntry: TRuleCatalogEntry;
  mText: string;
begin
  mCatalog := TFindingPrompt.GermanCatalog;
  try
    Assert.IsTrue(mCatalog.TryFind('empty-except', mEntry));
    mText := TFindingPrompt.Many(TArray<TFindingPromptItem>.Create(Item('A.pas', Finding('empty-except', 2)),
      Item('A.pas', Finding('empty-except', 30))), mCatalog, 2, 20);
  finally
    mCatalog.Free;
  end;
  Assert.Contains(mText, '## Regeln');
  Assert.AreEqual(1, Occurrences(mText, mEntry.Description));
  // Zwei getrennte Ausschnitte mit Trennzeile.
  Assert.AreEqual(1, Occurrences(mText, '       …'));
end;

procedure TFindingPromptTests.ManyRespectsLimit;
var
  mItems: TArray<TFindingPromptItem>;
  mIndex: Integer;
  mText: string;
begin
  mItems := nil;
  for mIndex := 0 to 4 do
  begin
    mItems := mItems + [Item('A.pas', Finding('test-a', mIndex * 5))];
  end;
  mText := TFindingPrompt.Many(mItems, nil, 1, 2);
  Assert.StartsWith('# 5 Befunde in 1 Dateien beheben', mText);
  Assert.Contains(mText, 'Weitere 3 Befunde sind hier nicht aufgeführt');
  Assert.AreEqual(2, Occurrences(mText, '### Befund test-a'));
end;

procedure TFindingPromptTests.CompilerMessageHasNoConfidenceAndNoFix;
var
  mItem: TFindingPromptItem;
  mCatalog: TRuleCatalog;
  mText: string;
begin
  mItem := Item('U.pas', Finding('E2003', 4));
  mItem.Compiler := True;
  mCatalog := TFindingPrompt.GermanCatalog;
  try
    mText := TFindingPrompt.OneFinding(mItem, mCatalog, 2);
  finally
    mCatalog.Free;
  end;
  Assert.StartsWith('## Compilermeldung E2003', mText);
  Assert.Contains(mText, 'Meldung: Meldung E2003');
  Assert.Contains(mText, '>    5 | z5');
  Assert.IsFalse(mText.Contains('Konfidenz'), 'Compilermeldungen ohne Konfidenz');
  Assert.Contains(mText, 'Prüfen mit: `check_code` (file: `U.pas`)');
  Assert.IsFalse(mText.Contains('fix_findings'), 'Compilermeldungen ohne Sammelkorrektur');
end;

procedure TFindingPromptTests.EnglishTexts;
var
  mText: string;
begin
  TAtlasLocale.Use(TTextLanguage.English);
  try
    mText := TFindingPrompt.Many(TArray<TFindingPromptItem>.Create(Item('A.pas', Finding('test-a', 1)),
      Item('A.pas', Finding('test-b', 3))), nil, 1, 20);
  finally
    TAtlasLocale.Use(TTextLanguage.German);
  end;
  Assert.StartsWith('# Fix 2 findings in 1 files', mText);
  Assert.Contains(mText, '## File `A.pas`');
  Assert.Contains(mText, '- Line 2, column 3');
  Assert.Contains(mText, 'Check with: `check_code` (file: `A.pas`)');
end;

initialization
  TDUnitX.RegisterTestFixture(TFindingPromptTests);

end.
