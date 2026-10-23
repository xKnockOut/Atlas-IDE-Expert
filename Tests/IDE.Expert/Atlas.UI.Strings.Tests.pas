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
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Documentation.Layout,
  Atlas.Core.Signature.Contract,
  Atlas.Core.Signature.Format,
  Atlas.UI.Strings;

function Placeholders(const AText: string): string;
var
  Index: Integer;
begin
  // %d und %s in Reihenfolge, z. B. "ds".
  Result := '';
  for Index := 1 to Length(AText) - 1 do
    if AText[Index] = '%' then
      Result := Result + AText[Index + 1];
end;

procedure TAtlasStringsTests.EveryTextExistsInBothLanguagesWithSamePlaceholders;
var
  Id: TAtlasTextId;
  German, English: string;
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    for Id := Low(TAtlasTextId) to High(TAtlasTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      German := TAtlasStrings.Text(Id);
      TAtlasStrings.Language := TAtlasLanguage.English;
      English := TAtlasStrings.Text(Id);
      Assert.IsTrue((German <> '') and (English <> ''), Ord(Id).ToString);
      Assert.AreEqual(Placeholders(German), Placeholders(English), German + ' / ' + English);
    end;
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasStringsTests.ConfidenceLineForRuleFindings;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Konfidenz: mittel', TAtlasStrings.Confidence('medium'));
    Assert.AreEqual('Konfidenz: hoch', TAtlasStrings.Confidence('high'));
    Assert.AreEqual('', TAtlasStrings.Confidence(''), 'Syntax- und Compilermeldungen ohne Konfidenz');
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Confidence: low', TAtlasStrings.Confidence('low'));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasStringsTests.SwitchesLanguage;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Enter übernehmen · Esc schließen', TAtlasStrings.Text(TAtlasTextId.FooterKeys));
    Assert.AreEqual('3 von 84', TAtlasStrings.Fmt(TAtlasTextId.CountOf, [3, 84]));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Enter to accept · Esc to close', TAtlasStrings.Text(TAtlasTextId.FooterKeys));
    Assert.AreEqual('3 of 84', TAtlasStrings.Fmt(TAtlasTextId.CountOf, [3, 84]));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasStringsTests.TypeArgHeadingAndFooter;
var
  Saved: TAtlasLanguage;
begin
  // Typargumente (#450).
  Saved := TAtlasStrings.Language;
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
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasStringsTests.UsesFooterAndCycle;
var
  Saved: TAtlasLanguage;
begin
  // uses-Abschnitt (#469): Fußzeile zu schon eingebundenen Units, Zirkelbezug im Detailpanel.
  Saved := TAtlasStrings.Language;
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
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasStringsTests.DocLabelsGerman;
var
  Saved: TAtlasLanguage;
  Labels, Expected: TAtlasDocLabels;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Labels := TAtlasStrings.DocLabels;
    Expected := TAtlasDocLabels.German;
    Assert.AreEqual(Expected.Params, Labels.Params);
    Assert.AreEqual(Expected.TypeParams, Labels.TypeParams);
    Assert.AreEqual(Expected.Returns, Labels.Returns);
    Assert.AreEqual(Expected.Value, Labels.Value);
    Assert.AreEqual(Expected.Exceptions, Labels.Exceptions);
    Assert.AreEqual(Expected.Remarks, Labels.Remarks);
    Assert.AreEqual(Expected.Example, Labels.Example);
    Assert.AreEqual(Expected.SeeAlso, Labels.SeeAlso);
    Assert.AreEqual(Expected.Undocumented, Labels.Undocumented);
    Assert.AreEqual(Expected.More, Labels.More);
    Assert.AreEqual(Expected.Less, Labels.Less);
    Assert.AreEqual(Expected.CountParam, Labels.CountParam);
    Assert.AreEqual(Expected.CountParams, Labels.CountParams);
    Assert.AreEqual(Expected.CountTypeParam, Labels.CountTypeParam);
    Assert.AreEqual(Expected.CountTypeParams, Labels.CountTypeParams);
    Assert.AreEqual(Expected.CountException, Labels.CountException);
    Assert.AreEqual(Expected.CountExceptions, Labels.CountExceptions);
    Assert.AreEqual(Expected.ItemReturns, Labels.ItemReturns);
    Assert.AreEqual(Expected.ItemValue, Labels.ItemValue);
    Assert.AreEqual(Expected.ItemRemarks, Labels.ItemRemarks);
    Assert.AreEqual(Expected.ItemExample, Labels.ItemExample);
    Assert.AreEqual(Expected.ItemSeeAlso, Labels.ItemSeeAlso);
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasStringsTests.SignatureFormatLines;
var
  Saved: TAtlasLanguage;
  Line: TAtlasFormatLine;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    // Akzeptanz #451: Platzhalter 2 als ganzzahlig.
    Line := Default(TAtlasFormatLine);
    Line.Kind := TAtlasFormatLineKind.Placeholder;
    Line.Placeholder := 1;
    Line.Count := 2;
    Line.TypeChar := 'd';
    Assert.AreEqual('Platzhalter 2 von 2 erwartet ganzzahlig', TAtlasStrings.SignatureFormatLine(Line));
    Line.Kind := TAtlasFormatLineKind.Problem;
    Line.Problem := TAtlasFormatProblem.TooManyArguments;
    Line.Argument := 2;
    Assert.AreEqual('Mehr Argumente als Platzhalter: Argument 3 wird nicht ausgegeben.',
      TAtlasStrings.SignatureFormatLine(Line));
    Line.Problem := TAtlasFormatProblem.TypeConflict;
    Line.Argument := 1;
    Line.PlaceholderText := '%d';
    Line.ProblemKind := 'string';
    Assert.AreEqual('Platzhalter 2 (%d) erwartet ganzzahlig, Argument 2 ist ein String: EConvertError zur Laufzeit.',
      TAtlasStrings.SignatureFormatLine(Line));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Line.Kind := TAtlasFormatLineKind.Placeholder;
    Line.TypeChar := 's';
    Assert.AreEqual('Placeholder 2 of 2 expects string', TAtlasStrings.SignatureFormatLine(Line));
    Assert.AreEqual('', TAtlasStrings.SignatureFormatLine(Default(TAtlasFormatLine)));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStringsTests);

end.
