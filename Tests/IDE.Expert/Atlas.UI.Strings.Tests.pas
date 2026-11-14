unit Atlas.UI.Strings.Tests;

// Tests für die Oberflächentexte (#446).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasStringsTests = class
  public
    [Test]
    procedure EveryTextExistsInBothLanguagesWithSamePlaceholders;
    [Test]
    procedure SwitchesLanguage;
    [Test]
    procedure ConfidenceLineForRuleFindings;
    [Test]
    procedure DocLabelsGerman;
    [Test]
    procedure TypeArgHeadingAndFooter;
    [Test]
    procedure UsesFooterAndCycle;
    [Test]
    procedure SignatureFormatLines;
    /// <summary>Abnahme #530: ein Hinweis H2164 zeigt „1 Hinweis“ in der Zusammenfassung.</summary>
    [Test]
    procedure BuildCountsSingularAndPlural;
  end;

/// <summary>Ein Text eines Moduls (#1455) in beiden Sprachen: nicht leer, gleiche Platzhalter in gleicher Folge.
/// AIndex ist die Ordnungszahl der Id für die Meldung.</summary>
procedure AssertTextPair(const AGerman, AEnglish: string; AIndex: Integer);

implementation

uses
  System.SysUtils,
  Atlas.Core.Documentation.Layout,
  Atlas.Core.Signature.Contract,
  Atlas.Core.Signature.Format,
  Atlas.UI.Strings,
  Atlas.UI.Completion.Strings;

function Placeholders(const AText: string): string;
var
  mIndex: Integer;
begin
  // %d und %s in Reihenfolge, z. B. "ds".
  Result := '';
  for mIndex := 1 to Length(AText) - 1 do
  begin
    if AText[mIndex] = '%' then
    begin
      Result := Result + AText[mIndex + 1];
    end;
  end;
end;

procedure AssertTextPair(const AGerman, AEnglish: string; AIndex: Integer);
begin
  Assert.IsTrue((AGerman <> '') and (AEnglish <> ''), AIndex.ToString);
  Assert.AreEqual(Placeholders(AGerman), Placeholders(AEnglish), AGerman + ' / ' + AEnglish);
end;

procedure TAtlasStringsTests.EveryTextExistsInBothLanguagesWithSamePlaceholders;
var
  mId: TAtlasTextId;
  mGerman, mEnglish: string;
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    for mId := Low(TAtlasTextId) to High(TAtlasTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      mEnglish := TAtlasStrings.Text(mId);
      Assert.IsTrue((mGerman <> '') and (mEnglish <> ''), Ord(mId).ToString);
      Assert.AreEqual(Placeholders(mGerman), Placeholders(mEnglish), mGerman + ' / ' + mEnglish);
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasStringsTests.ConfidenceLineForRuleFindings;
var
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Konfidenz: mittel', TAtlasStrings.Confidence('medium'));
    Assert.AreEqual('Konfidenz: hoch', TAtlasStrings.Confidence('high'));
    Assert.AreEqual('', TAtlasStrings.Confidence(''), 'Syntax- und Compilermeldungen ohne Konfidenz');
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Confidence: low', TAtlasStrings.Confidence('low'));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasStringsTests.BuildCountsSingularAndPlural;
var
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('1 Hinweis', TAtlasStrings.BuildCounts(0, 1));
    Assert.AreEqual('2 Warnungen, 1 Hinweis', TAtlasStrings.BuildCounts(2, 1));
    Assert.AreEqual('1 Warnung, 3 Hinweise', TAtlasStrings.BuildCounts(1, 3));
    Assert.AreEqual('', TAtlasStrings.BuildCounts(0, 0));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('2 warnings, 1 hint', TAtlasStrings.BuildCounts(2, 1));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasStringsTests.SwitchesLanguage;
var
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Enter übernehmen · Esc schließen',
      TAtlasCompletionStrings.Text(TAtlasCompletionTextId.FooterKeys));
    Assert.AreEqual('3 von 84', TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.CountOf, [3, 84]));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Enter to accept · Esc to close', TAtlasCompletionStrings.Text(TAtlasCompletionTextId.FooterKeys));
    Assert.AreEqual('3 of 84', TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.CountOf, [3, 84]));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasStringsTests.TypeArgHeadingAndFooter;
var
  mSaved: TAtlasLanguage;
begin
  // Typargumente (#450).
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('T: class · nur Klassen', TAtlasStrings.TypeArgHeading('T', 'class', 'classes'));
    Assert.AreEqual('T: record · nur Records und Grundtypen', TAtlasStrings.TypeArgHeading('T', 'record', 'values'));
    Assert.AreEqual('T: class, constructor · nur Klassen mit parameterlosem Konstruktor',
      TAtlasStrings.TypeArgHeading('T', 'class, constructor', 'constructible'));
    Assert.AreEqual('T: IVergleich · nur Typen, die IVergleich implementieren',
      TAtlasStrings.TypeArgHeading('T', 'IVergleich', 'implements:IVergleich'));
    Assert.AreEqual('T: TBasis · nur Typen, die von TBasis abgeleitet sind',
      TAtlasStrings.TypeArgHeading('T', 'TBasis', 'descends:TBasis'));
    Assert.AreEqual('Typargument V', TAtlasStrings.TypeArgHeading('V', '', ''));
    Assert.AreEqual('Ausgeblendet: Records, Aufzählungen, Grundtypen',
      TAtlasStrings.TypeArgHidden('records,enums,basic'));
    Assert.AreEqual('', TAtlasStrings.TypeArgHidden(''));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('T: class · classes only', TAtlasStrings.TypeArgHeading('T', 'class', 'classes'));
    Assert.AreEqual('Hidden: interfaces', TAtlasStrings.TypeArgHidden('interfaces'));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasStringsTests.UsesFooterAndCycle;
var
  mSaved: TAtlasLanguage;
begin
  // uses-Abschnitt (#469): Fußzeile zu schon eingebundenen Units, Zirkelbezug im Detailpanel.
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('', TAtlasStrings.UsesHidden(nil));
    Assert.AreEqual('System.SysUtils ist schon eingebunden und fehlt hier',
      TAtlasStrings.UsesHidden(['System.SysUtils']));
    Assert.AreEqual('System.SysUtils, System.Classes sind schon eingebunden und fehlen hier',
      TAtlasStrings.UsesHidden(['System.SysUtils', 'System.Classes']));
    Assert.AreEqual('A, B und 2 weitere sind schon eingebunden und fehlen hier',
      TAtlasStrings.UsesHidden(['A', 'B', 'C', 'D']));
    Assert.AreEqual('uGeneratorBeleg bindet diese Unit im interface-Teil ein',
      TAtlasStrings.UsesCycle('uGeneratorBeleg → Haupt'));
    Assert.AreEqual('uMitte bindet diese Unit über uZwei, uDrei im interface-Teil ein',
      TAtlasStrings.UsesCycle('uMitte → uZwei → uDrei → Haupt'));
    Assert.AreEqual('', TAtlasStrings.UsesCycle(''));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('A is already used and not listed', TAtlasStrings.UsesHidden(['A']));
    Assert.AreEqual('uA uses this unit in its interface section', TAtlasStrings.UsesCycle('uA → Haupt'));
    // Nach "inherited " (#482): ausgelassene abstrakte Vorfahrmethoden.
    Assert.AreEqual('TBasis.Zeichnen is abstract and not listed', TAtlasStrings.InheritedAbstract(['TBasis.Zeichnen']));
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('', TAtlasStrings.InheritedAbstract(nil));
    Assert.AreEqual('TBasis.Zeichnen ist abstrakt und fehlt', TAtlasStrings.InheritedAbstract(['TBasis.Zeichnen']));
    Assert.AreEqual('Abstrakte Vorfahrmethoden fehlen: A.X, A.Y, B.Z, …',
      TAtlasStrings.InheritedAbstract(['A.X', 'A.Y', 'B.Z', 'B.W']));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasStringsTests.DocLabelsGerman;
var
  mSaved: TAtlasLanguage;
  mLabels, mExpected: TAtlasDocLabels;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mLabels := TAtlasStrings.DocLabels;
    mExpected := TAtlasDocLabels.German;
    Assert.AreEqual(mExpected.Params, mLabels.Params);
    Assert.AreEqual(mExpected.TypeParams, mLabels.TypeParams);
    Assert.AreEqual(mExpected.Returns, mLabels.Returns);
    Assert.AreEqual(mExpected.Value, mLabels.Value);
    Assert.AreEqual(mExpected.Exceptions, mLabels.Exceptions);
    Assert.AreEqual(mExpected.Remarks, mLabels.Remarks);
    Assert.AreEqual(mExpected.Example, mLabels.Example);
    Assert.AreEqual(mExpected.SeeAlso, mLabels.SeeAlso);
    Assert.AreEqual(mExpected.Undocumented, mLabels.Undocumented);
    Assert.AreEqual(mExpected.More, mLabels.More);
    Assert.AreEqual(mExpected.Less, mLabels.Less);
    Assert.AreEqual(mExpected.CountParam, mLabels.CountParam);
    Assert.AreEqual(mExpected.CountParams, mLabels.CountParams);
    Assert.AreEqual(mExpected.CountTypeParam, mLabels.CountTypeParam);
    Assert.AreEqual(mExpected.CountTypeParams, mLabels.CountTypeParams);
    Assert.AreEqual(mExpected.CountException, mLabels.CountException);
    Assert.AreEqual(mExpected.CountExceptions, mLabels.CountExceptions);
    Assert.AreEqual(mExpected.ItemReturns, mLabels.ItemReturns);
    Assert.AreEqual(mExpected.ItemValue, mLabels.ItemValue);
    Assert.AreEqual(mExpected.ItemRemarks, mLabels.ItemRemarks);
    Assert.AreEqual(mExpected.ItemExample, mLabels.ItemExample);
    Assert.AreEqual(mExpected.ItemSeeAlso, mLabels.ItemSeeAlso);
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasStringsTests.SignatureFormatLines;
var
  mSaved: TAtlasLanguage;
  mLine: TAtlasFormatLine;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    // Akzeptanz #451: Platzhalter 2 als ganzzahlig.
    mLine := Default(TAtlasFormatLine);
    mLine.Kind := TAtlasFormatLineKind.Placeholder;
    mLine.Placeholder := 1;
    mLine.Count := 2;
    mLine.TypeChar := 'd';
    Assert.AreEqual('Platzhalter 2 von 2 erwartet ganzzahlig', TAtlasStrings.SignatureFormatLine(mLine));
    mLine.Kind := TAtlasFormatLineKind.Problem;
    mLine.Problem := TAtlasFormatProblem.TooManyArguments;
    mLine.Argument := 2;
    Assert.AreEqual('Mehr Argumente als Platzhalter: Argument 3 wird nicht ausgegeben.',
      TAtlasStrings.SignatureFormatLine(mLine));
    mLine.Problem := TAtlasFormatProblem.TypeConflict;
    mLine.Argument := 1;
    mLine.PlaceholderText := '%d';
    mLine.ProblemKind := 'string';
    Assert.AreEqual('Platzhalter 2 (%d) erwartet ganzzahlig, Argument 2 ist ein String: EConvertError zur Laufzeit.',
      TAtlasStrings.SignatureFormatLine(mLine));
    TAtlasStrings.Language := TAtlasLanguage.English;
    mLine.Kind := TAtlasFormatLineKind.Placeholder;
    mLine.TypeChar := 's';
    Assert.AreEqual('Placeholder 2 of 2 expects string', TAtlasStrings.SignatureFormatLine(mLine));
    Assert.AreEqual('', TAtlasStrings.SignatureFormatLine(Default(TAtlasFormatLine)));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStringsTests);

end.
