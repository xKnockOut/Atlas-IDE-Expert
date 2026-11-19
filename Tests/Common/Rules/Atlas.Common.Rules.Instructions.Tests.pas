unit Atlas.Common.Rules.Instructions.Tests;

// Tests für den Abschnitt der Anweisungsdatei für KI-Assistenten (#2615): Inhalt (Profil, Grenzwerte, Benennung,
// verbotene Symbole, Regeln mit Schweregrad Fehler, Pflichtprüfungen), englische Texte, Abschnitt neu anhängen und
// ersetzen ohne Änderung am übrigen Text, Stand aktuell/veraltet/fehlt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleInstructionsTests = class
  public
    [Test]
    procedure SectionNamesLimitsNamingAndForbiddenSymbols;
    [Test]
    procedure SectionInEnglish;
    [Test]
    procedure RuleOffIsLeftOut;
    [Test]
    procedure ApplyAppends;
    [Test]
    procedure ApplyReplacesOnlyTheSection;
    [Test]
    procedure OrphanBeginMarkerStaysOutside;
    [Test]
    procedure ChangedLimitChangesOneLine;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Instructions,
  Atlas.Common.Lsp.Instructions;

const
  cSettings = '{"profile": "strict", "rules": {"metric-method-length": {"severity": "warning", "max": 50}, ' +
    '"naming-prefix": "hint", "forbidden-symbol": {"severity": "error", "symbols": [{"name": ' +
    '"System.Classes.TThread.Queue", "firstArgument": ["nil"], "message": "Ohne Besitzer", "replacement": ' +
    '"TAtlasMainThread.Queue"}]}}, "assistants": {"instructions": {"checks": ["pwsh Tools/Check-Delphi12.ps1"]}, ' +
    '"protected": [{"path": "CHANGELOG.md", "reason": "Aus Fragmenten erzeugt", "use": "changelog.d"}]}}';

function Settings(const AJson: string): TServerSettings;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Result := TConfigurationParser.Parse(AJson, mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)), AJson);
end;

function SectionOf(const AJson: string): string;
begin
  Result := TLspInstructions.SectionFor(Settings(AJson), BuiltinRules);
end;

function Lines(const AText: string): TArray<string>;
begin
  Result := AText.Split([#10]);
end;

{ TRuleInstructionsTests }

procedure TRuleInstructionsTests.SectionNamesLimitsNamingAndForbiddenSymbols;
var
  mText: string;
begin
  mText := SectionOf(cSettings);
  Assert.StartsWith(TRuleInstructions.cBeginMarker, mText);
  Assert.EndsWith(TRuleInstructions.cEndMarker, mText);
  Assert.AreEqual(0, Pos(#13, mText), 'Umbrüche als LF');
  Assert.Contains(mText, '## Prüfregeln (Profil `strict`, 0 Befunde Pflicht)');
  Assert.Contains(mText, 'höchstens 50 (`metric-method-length`)');
  Assert.Contains(mText, 'lokale Variablen `m`, Felder `F`, Parameter `A`, Konstanten `c` (`naming-prefix`)');
  Assert.Contains(mText, '- `System.Classes.TThread.Queue` mit erstem Argument `nil`: Ohne Besitzer, stattdessen ' +
    '`TAtlasMainThread.Queue`');
  Assert.Contains(mText, '### Regeln mit Schweregrad Fehler aus atlas.json');
  Assert.Contains(mText, '- `forbidden-symbol`: ');
  Assert.Contains(mText, '- `pwsh Tools/Check-Delphi12.ps1`');
  Assert.Contains(mText, '### Geschützte Dateien (nicht ändern)');
  Assert.Contains(mText, '- `CHANGELOG.md`: Aus Fragmenten erzeugt; stattdessen: changelog.d');
  Assert.Contains(mText, '`check_code`');
  Assert.Contains(mText, '`delphi://conventions`');
end;

procedure TRuleInstructionsTests.SectionInEnglish;
var
  mText: string;
begin
  mText := SectionOf('{"mcp": {"promptLanguage": "en"}, "rules": {"metric-method-length": {"severity": "hint", ' +
    '"max": 70}}}');
  Assert.Contains(mText, '## Code rules (profile `standard`, 0 findings required)');
  Assert.Contains(mText, 'at most 70 (`metric-method-length`)');
  Assert.IsFalse(mText.Contains('höchstens'), 'keine deutschen Texte');
end;

procedure TRuleInstructionsTests.RuleOffIsLeftOut;
var
  mText: string;
begin
  mText := SectionOf('{"rules": {"metric-method-length": "off", "naming-prefix": "off", "forbidden-symbol": "off"}}');
  Assert.IsFalse(mText.Contains('`metric-method-length`'), 'abgeschaltete Metrik');
  Assert.IsFalse(mText.Contains('`naming-prefix`'), 'abgeschaltete Benennung');
  Assert.IsFalse(mText.Contains('### Verbotene Symbole'), 'abgeschaltete Verbote');
  Assert.IsFalse(SectionOf('{}').Contains('`duplicate-case-label`'), 'Fehler-Regel ohne Eintrag in atlas.json');
  Assert.IsFalse(SectionOf('{}').Contains('### Geschützte Dateien'), 'ohne geschützte Dateien kein Block');
end;

procedure TRuleInstructionsTests.ApplyAppends;
const
  cSection = '<!-- atlas:begin x -->'#10'Inhalt'#10'<!-- atlas:end -->';
begin
  Assert.AreEqual(cSection + #10, TRuleInstructions.Apply('', cSection, #10));
  Assert.AreEqual('# Titel'#13#10'Text'#13#10#13#10'<!-- atlas:begin x -->'#13#10'Inhalt'#13#10'<!-- atlas:end -->' +
    #13#10, TRuleInstructions.Apply('# Titel'#13#10'Text', cSection, #13#10));
  Assert.AreEqual('Text'#10#10 + cSection + #10, TRuleInstructions.Apply('Text'#10, cSection, #10));
end;

procedure TRuleInstructionsTests.ApplyReplacesOnlyTheSection;
const
  cBefore = '# Regeln'#13#10'Von Hand  '#13#10;
  cAfter = #13#10'Nachsatz ohne Umbruch';
  cNew = '<!-- atlas:begin neu -->'#10'Neu'#10'<!-- atlas:end -->';
var
  mText, mResult: string;
begin
  mText := cBefore + '<!-- atlas:begin alt -->'#13#10'Alt'#13#10'<!-- atlas:end -->' + cAfter;
  mResult := TRuleInstructions.Apply(mText, cNew, #13#10);
  Assert.AreEqual(cBefore + '<!-- atlas:begin neu -->'#13#10'Neu'#13#10'<!-- atlas:end -->' + cAfter, mResult);
  Assert.AreEqual(cNew, TRuleInstructions.Extract(mResult));
  Assert.AreEqual(Ord(TInstructionsState.Current), Ord(TRuleInstructions.State(mResult, cNew)));
  Assert.AreEqual(Ord(TInstructionsState.Stale), Ord(TRuleInstructions.State(mText, cNew)));
  Assert.AreEqual(Ord(TInstructionsState.Missing), Ord(TRuleInstructions.State(cBefore, cNew)));
  Assert.AreEqual(mResult, TRuleInstructions.Apply(mResult, cNew, #13#10), 'zweimal ergibt dasselbe');
end;

procedure TRuleInstructionsTests.OrphanBeginMarkerStaysOutside;
const
  cOrphan = 'Beispiel: <!-- atlas:begin ohne Ende'#10#10;
  cSection = '<!-- atlas:begin -->'#10'A'#10'<!-- atlas:end -->';
var
  mResult: string;
begin
  mResult := TRuleInstructions.Apply(cOrphan + cSection + #10, '<!-- atlas:begin -->'#10'B'#10'<!-- atlas:end -->',
    #10);
  Assert.AreEqual(cOrphan + '<!-- atlas:begin -->'#10'B'#10'<!-- atlas:end -->'#10, mResult);
  Assert.AreEqual('', TRuleInstructions.Extract(cOrphan), 'ohne Schlussmarkierung kein Abschnitt');
end;

procedure TRuleInstructionsTests.ChangedLimitChangesOneLine;
var
  mOld, mNew: TArray<string>;
  mIndex, mChanged: Integer;
begin
  mOld := Lines(SectionOf('{"rules": {"metric-method-length": {"severity": "hint", "max": 60}}}'));
  mNew := Lines(SectionOf('{"rules": {"metric-method-length": {"severity": "hint", "max": 61}}}'));
  Assert.AreEqual(Integer(Length(mOld)), Integer(Length(mNew)));
  mChanged := 0;
  for mIndex := 0 to High(mOld) do
  begin
    if mOld[mIndex] <> mNew[mIndex] then
    begin
      Inc(mChanged);
      Assert.Contains(mNew[mIndex], 'höchstens 61');
    end;
  end;
  Assert.AreEqual(1, mChanged);
  mOld := nil;
  mNew := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleInstructionsTests);

end.
