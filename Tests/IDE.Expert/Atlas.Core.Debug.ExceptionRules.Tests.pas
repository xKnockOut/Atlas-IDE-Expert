unit Atlas.Core.Debug.ExceptionRules.Tests;

// Tests der Exception-Regeln (#2549) ohne IDE: Muster „enthält“ mit `*`,
// reguläre Ausdrücke, ungültige Ausdrücke, umgedrehter Vergleich, Vorschlag
// aus einer Meldung, Reihenfolge, Ort, Ersetzen gleicher Bedingungen und
// JSON hin und zurück.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasExceptionRulesTests = class
  public
    [Test]
    procedure ContainsWithWildcards;
    [Test]
    procedure RegexIgnoresCase;
    [Test]
    procedure InvalidRegexNeverMatches;
    [Test]
    procedure NotMatchesTurnsAround;
    [Test]
    procedure WithoutMessageNoMessageRule;
    [Test]
    procedure SuggestReplacesNumbersAndQuotes;
    [Test]
    procedure FirstEnabledRuleWins;
    [Test]
    procedure MessageRulesOffWhenSwitchedOff;
    [Test]
    procedure LocationNarrowsRule;
    [Test]
    procedure PutReplacesSameCriteria;
    [Test]
    procedure PutKeepsSharedArray;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure ParseDropsBrokenRules;
    [Test]
    procedure OwnFrameGivesRoutineAndUnit;
    [Test]
    procedure PlaceRulesOnlyWhenWanted;
    [Test]
    procedure PersonalBeforeProject;
    [Test]
    procedure MoveChangesOrder;
    [Test]
    procedure HitsPerRule;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.ExceptionRules;

const
  cClass = 'EKonfigFehler';
  cUnknownKey = 'Schlüssel unbekannt: ''Farbe'' in Zeile 12';
  cAll = [TAtlasExceptionRuleKind.Message, TAtlasExceptionRuleKind.Place];

function Facts(const AMessage: string): TAtlasExceptionFacts;
begin
  Result := TAtlasExceptionFacts.Create(cClass, AMessage, '');
end;

function FactsAt(const ARoutine: string): TAtlasExceptionFacts;
begin
  Result := TAtlasExceptionFacts.Create(cClass, cUnknownKey, ARoutine);
end;

function Rule(const AMessage: string; AMatch: TAtlasMessageMatch;
  AAction: TAtlasExceptionAction): TAtlasExceptionRule;
begin
  Result := TAtlasExceptionRule.Create(cClass, AMessage, AMatch, AAction);
end;

{ TAtlasExceptionRulesTests }

procedure TAtlasExceptionRulesTests.ContainsWithWildcards;
begin
  Assert.IsTrue(TAtlasExceptionRules.MessageMatches('unbekannt', False, cUnknownKey), 'Teil der Meldung');
  Assert.IsTrue(TAtlasExceptionRules.MessageMatches('schlüssel*ZEILE', False, cUnknownKey), 'Teile in Reihenfolge');
  Assert.IsFalse(TAtlasExceptionRules.MessageMatches('Zeile*Schlüssel', False, cUnknownKey), 'falsche Reihenfolge');
  Assert.IsTrue(TAtlasExceptionRules.MessageMatches('Zeile 12?', False, 'Fehler in Zeile 12? Ja'),
    '? zählt als Zeichen');
  Assert.IsFalse(TAtlasExceptionRules.MessageMatches('Zeile 12?', False, 'Fehler in Zeile 123'));
  Assert.IsTrue(TAtlasExceptionRules.MessageMatches('', False, cUnknownKey), 'leeres Muster passt immer');
end;

procedure TAtlasExceptionRulesTests.RegexIgnoresCase;
begin
  Assert.IsTrue(TAtlasExceptionRules.MessageMatches('^schlüssel unbekannt: ''\w+''', True, cUnknownKey));
  Assert.IsFalse(TAtlasExceptionRules.MessageMatches('^unbekannt', True, cUnknownKey));
end;

procedure TAtlasExceptionRulesTests.InvalidRegexNeverMatches;
var
  mError: string;
begin
  Assert.IsFalse(TAtlasExceptionRules.MessageMatches('(offen', True, '(offen'));
  Assert.IsFalse(TAtlasExceptionRules.ValidPattern('(offen', True, mError));
  Assert.IsTrue(mError <> '', 'Grund genannt');
  Assert.IsTrue(TAtlasExceptionRules.ValidPattern('(offen', False, mError), 'ohne Ausdruck ist es Text');
  Assert.AreEqual('', mError);
  Assert.IsFalse(TAtlasExceptionRules.ValidPattern('  ', False, mError), 'leeres Muster');
end;

procedure TAtlasExceptionRulesTests.NotMatchesTurnsAround;
var
  mStopOnly: TAtlasExceptionRule;
begin
  // „Nur bei Meldungen wie dieser anhalten“: andere Meldungen setzen fort.
  mStopOnly := Rule('Schlüssel unbekannt', TAtlasMessageMatch.NotMatches, TAtlasExceptionAction.Log);
  Assert.IsFalse(mStopOnly.Matches(Facts(cUnknownKey)), 'passende Meldung hält an');
  Assert.IsTrue(mStopOnly.Matches(Facts('Datei fehlt')), 'andere Meldung läuft weiter');
  Assert.IsFalse(mStopOnly.Matches(TAtlasExceptionFacts.Create('EAndere', 'Datei fehlt', '')), 'andere Klasse');
end;

procedure TAtlasExceptionRulesTests.WithoutMessageNoMessageRule;
begin
  // Ohne gelesene Meldung lieber anhalten als verschlucken.
  Assert.IsFalse(Rule('x', TAtlasMessageMatch.NotMatches, TAtlasExceptionAction.Log).Matches(Facts('')));
  Assert.IsFalse(Rule('*', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Log).Matches(Facts('')));
  Assert.IsTrue(Rule('', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Log).Matches(Facts('')),
    'Regel ohne Meldung braucht keine');
end;

procedure TAtlasExceptionRulesTests.SuggestReplacesNumbersAndQuotes;
begin
  Assert.AreEqual('Schlüssel unbekannt: * in Zeile *', TAtlasExceptionRules.SuggestPattern(cUnknownKey));
  Assert.AreEqual('Zugriffsverletzung bei Adresse *', TAtlasExceptionRules.SuggestPattern(
    'Zugriffsverletzung bei Adresse 0040A1B2'));
  Assert.AreEqual('Wert *', TAtlasExceptionRules.SuggestPattern('Wert ''a''12'), 'Sterne zusammengefasst');
  Assert.AreEqual('Ohne Zahl', TAtlasExceptionRules.SuggestPattern(' Ohne Zahl '));
  Assert.AreEqual('Rest ''offen', TAtlasExceptionRules.SuggestPattern('Rest ''offen'), 'ohne schließendes Hochkomma');
end;

procedure TAtlasExceptionRulesTests.FirstEnabledRuleWins;
var
  mRules: TAtlasExceptionRuleList;
begin
  mRules := TAtlasExceptionRuleList.Create(
    Rule('Schlüssel', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Stop),
    Rule('unbekannt', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Log),
    Rule('', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Continue));
  Assert.AreEqual(0, TAtlasExceptionRules.FirstMatch(mRules, Facts(cUnknownKey), cAll));
  mRules[0].Enabled := False;
  Assert.AreEqual(1, TAtlasExceptionRules.FirstMatch(mRules, Facts(cUnknownKey), cAll), 'ausgeschaltete zählt nicht');
  Assert.AreEqual(2, TAtlasExceptionRules.FirstMatch(mRules, Facts('Datei fehlt'), cAll));
  Assert.AreEqual(-1, TAtlasExceptionRules.FirstMatch(mRules, TAtlasExceptionFacts.Create('EAndere', 'x', ''), cAll));
  Assert.AreEqual(-1, TAtlasExceptionRules.FirstMatch(nil, Facts(cUnknownKey), cAll), 'ohne Regeln');
end;

procedure TAtlasExceptionRulesTests.MessageRulesOffWhenSwitchedOff;
var
  mRules: TAtlasExceptionRuleList;
begin
  mRules := TAtlasExceptionRuleList.Create(
    Rule('Schlüssel', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Log),
    Rule('', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Stop));
  Assert.AreEqual(1, TAtlasExceptionRules.FirstMatch(mRules, Facts(cUnknownKey), [TAtlasExceptionRuleKind.Place]));
end;

procedure TAtlasExceptionRulesTests.LocationNarrowsRule;
var
  mRule: TAtlasExceptionRule;
begin
  mRule := Rule('Schlüssel', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Log);
  mRule.Location := 'Kunden.Import';
  Assert.IsTrue(mRule.Matches(FactsAt('Kunden.Import.TKundenImport.LeseZeile')));
  Assert.IsFalse(mRule.Matches(FactsAt('Lieferanten.TLieferant.Lies')), 'andere Unit');
  Assert.IsFalse(mRule.Matches(FactsAt('')), 'ohne eigenen Rahmen');
end;

procedure TAtlasExceptionRulesTests.PutReplacesSameCriteria;
var
  mRules: TAtlasExceptionRuleList;
begin
  mRules := nil;
  Assert.IsTrue(TAtlasExceptionRules.Put(mRules, Rule('a*', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Log)));
  Assert.IsFalse(TAtlasExceptionRules.Put(mRules, Rule('a*', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Log)),
    'schon so');
  Assert.IsTrue(TAtlasExceptionRules.Put(mRules, Rule('a*', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Stop)),
    'andere Aktion ersetzt');
  Assert.AreEqual(1, Integer(Length(mRules)));
  Assert.AreEqual(Ord(TAtlasExceptionAction.Stop), Ord(mRules[0].Action));
  Assert.IsTrue(TAtlasExceptionRules.Put(mRules, Rule('a*', TAtlasMessageMatch.NotMatches,
    TAtlasExceptionAction.Log)), 'umgedreht ist eine eigene Regel');
  Assert.AreEqual(2, Integer(Length(mRules)));
  Assert.IsFalse(TAtlasExceptionRules.Put(mRules, TAtlasExceptionRule.Create(' ', 'a*', TAtlasMessageMatch.Matches,
    TAtlasExceptionAction.Log)), 'ohne Klasse');
end;

procedure TAtlasExceptionRulesTests.PutKeepsSharedArray;
var
  mOld, mNew: TAtlasExceptionRuleList;
begin
  mOld := TAtlasExceptionRuleList.Create(Rule('a*', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Log));
  mNew := mOld;
  TAtlasExceptionRules.Put(mNew, Rule('a*', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Stop));
  Assert.AreEqual(Ord(TAtlasExceptionAction.Log), Ord(mOld[0].Action), 'altes Array unverändert');
  Assert.AreEqual(Ord(TAtlasExceptionAction.Stop), Ord(mNew[0].Action));
end;

procedure TAtlasExceptionRulesTests.JsonRoundTrip;
var
  mRules, mRead: TAtlasExceptionRuleList;
  mJson: TJSONArray;
begin
  mRules := TAtlasExceptionRuleList.Create(
    Rule('Schlüssel unbekannt: *', TAtlasMessageMatch.NotMatches, TAtlasExceptionAction.Log),
    Rule('^Zeile \d+$', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Continue));
  mRules[1].Regex := True;
  mRules[1].Location := 'Kunden.*';
  mRules[1].Enabled := False;
  mJson := TAtlasExceptionRules.ToJson(mRules);
  try
    mRead := TAtlasExceptionRules.Parse(mJson);
  finally
    mJson.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mRead)));
  Assert.IsTrue(mRead[0].SameCriteria(mRules[0]));
  Assert.AreEqual(Ord(TAtlasMessageMatch.NotMatches), Ord(mRead[0].MessageMatch));
  Assert.AreEqual(Ord(TAtlasExceptionAction.Log), Ord(mRead[0].Action));
  Assert.IsTrue(mRead[0].Enabled);
  Assert.IsTrue(mRead[1].SameCriteria(mRules[1]));
  Assert.IsTrue(mRead[1].Regex);
  Assert.AreEqual('Kunden.*', mRead[1].Location);
  Assert.AreEqual(Ord(TAtlasExceptionAction.Continue), Ord(mRead[1].Action));
  Assert.IsFalse(mRead[1].Enabled);
  Assert.AreEqual('continue', TAtlasExceptionRules.ActionName(TAtlasExceptionAction.Continue));
end;

procedure TAtlasExceptionRulesTests.ParseDropsBrokenRules;
var
  mValue: TJSONValue;
  mRead: TAtlasExceptionRuleList;
begin
  mValue := TJSONObject.ParseJSONValue('[{"class": "", "message": "a"}, {"class": "E1", "message": "(", ' +
    '"regex": true}, 42, {"class": "E2", "message": "(", "action": "unbekannt"}]');
  try
    mRead := TAtlasExceptionRules.Parse(mValue);
  finally
    mValue.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mRead)));
  Assert.AreEqual('E2', mRead[0].ExceptionClass);
  Assert.AreEqual(Ord(TAtlasExceptionAction.Log), Ord(mRead[0].Action), 'unbekannte Aktion: vermerken');
  Assert.IsTrue(mRead[0].Enabled, 'ohne Feld eingeschaltet');
  Assert.AreEqual(0, Integer(Length(TAtlasExceptionRules.Parse(nil))));
end;

procedure TAtlasExceptionRulesTests.OwnFrameGivesRoutineAndUnit;
var
  mFrames: TAtlasDebugFrames;
  mOwn: TAtlasDebugFrame;
begin
  mOwn := TAtlasDebugFrame.Create('Kunden.Import.TKundenImport.LeseZeile(Self=$1)', 'C:\Src\Kunden.Import.pas', 42);
  mOwn.Own := True;
  mFrames := TAtlasDebugFrames.Create(TAtlasDebugFrame.Create('System.SysUtils.ConvertError', '', 0), mOwn);
  Assert.AreEqual('Kunden.Import.TKundenImport.LeseZeile', TAtlasExceptionRules.OwnRoutine(mFrames));
  Assert.AreEqual('Kunden.Import', TAtlasExceptionRules.OwnUnit(mFrames));
  Assert.AreEqual('', TAtlasExceptionRules.OwnRoutine(nil), 'ohne Stapel');
  Assert.AreEqual('', TAtlasExceptionRules.OwnUnit(nil));
  Assert.AreEqual('Kunden.Import', TAtlasExceptionRules.UnitOfFile('Src/Kunden.Import.pas'));
  Assert.AreEqual('', TAtlasExceptionRules.UnitOfFile(''));
end;

procedure TAtlasExceptionRulesTests.PlaceRulesOnlyWhenWanted;
var
  mRules: TAtlasExceptionRuleList;
  mPlace: TAtlasExceptionRule;
begin
  // EConvertError in Bericht.Druck weiterlaufen lassen, in Kunde.Import halten.
  mPlace := TAtlasExceptionRule.Create('EConvertError', '', TAtlasMessageMatch.Matches,
    TAtlasExceptionAction.Continue);
  mPlace.Location := 'Bericht.Druck.*';
  mRules := TAtlasExceptionRuleList.Create(mPlace);
  Assert.AreEqual(Ord(TAtlasExceptionRuleKind.Place), Ord(mPlace.Kind));
  Assert.IsTrue(TAtlasExceptionRules.Kinds(True, True) = cAll);
  Assert.IsTrue(TAtlasExceptionRules.Kinds(False, False) = []);
  Assert.AreEqual(0, TAtlasExceptionRules.FirstMatch(mRules, TAtlasExceptionFacts.Create('EConvertError', 'x',
    'Bericht.Druck.TDruck.Zeile'), cAll));
  Assert.AreEqual(-1, TAtlasExceptionRules.FirstMatch(mRules, TAtlasExceptionFacts.Create('EConvertError', 'x',
    'Kunde.Import.TImport.Lies'), cAll));
  Assert.AreEqual(-1, TAtlasExceptionRules.FirstMatch(mRules, TAtlasExceptionFacts.Create('EConvertError', 'x',
    'Bericht.Druck.TDruck.Zeile'), [TAtlasExceptionRuleKind.Message]), 'debug.exceptionRules aus');
end;

procedure TAtlasExceptionRulesTests.PersonalBeforeProject;
var
  mAll: TAtlasExceptionRuleList;
begin
  mAll := TAtlasExceptionRules.Combined(
    TAtlasExceptionRuleList.Create(Rule('', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Stop)),
    TAtlasExceptionRuleList.Create(Rule('', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Continue)));
  Assert.AreEqual(2, Integer(Length(mAll)));
  Assert.AreEqual(Ord(TAtlasExceptionRuleOrigin.Personal), Ord(mAll[0].Origin));
  Assert.AreEqual(Ord(TAtlasExceptionRuleOrigin.Project), Ord(mAll[1].Origin));
  Assert.AreEqual(0, TAtlasExceptionRules.FirstMatch(mAll, Facts('x'), cAll), 'persönliche Regel zuerst');
  Assert.AreNotEqual(mAll[0].Key, mAll[1].Key, 'Herkunft gehört zum Schlüssel');
end;

procedure TAtlasExceptionRulesTests.MoveChangesOrder;
var
  mRules, mOld: TAtlasExceptionRuleList;
begin
  mRules := TAtlasExceptionRuleList.Create(Rule('a', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Log),
    Rule('b', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Log),
    Rule('c', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Log));
  mOld := mRules;
  Assert.IsTrue(TAtlasExceptionRules.MoveRule(mRules, 2, -2));
  Assert.AreEqual('c', mRules[0].Message);
  Assert.AreEqual('a', mRules[1].Message);
  Assert.AreEqual('a', mOld[0].Message, 'geteiltes Array unverändert');
  Assert.IsFalse(TAtlasExceptionRules.MoveRule(mRules, 0, -1), 'über den Anfang');
  Assert.IsFalse(TAtlasExceptionRules.MoveRule(mRules, 2, 1), 'über das Ende');
  Assert.IsFalse(TAtlasExceptionRules.MoveRule(mRules, 1, 0));
end;

procedure TAtlasExceptionRulesTests.HitsPerRule;
var
  mHits: TAtlasExceptionRuleHits;
begin
  mHits := Default(TAtlasExceptionRuleHits);
  mHits.Add('a');
  mHits.Add('b');
  mHits.Add('a');
  Assert.AreEqual(2, mHits.CountOf('a'));
  Assert.AreEqual(1, mHits.CountOf('b'));
  Assert.AreEqual(0, mHits.CountOf('c'));
  mHits.Clear;
  Assert.AreEqual(0, mHits.CountOf('a'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasExceptionRulesTests);

end.
