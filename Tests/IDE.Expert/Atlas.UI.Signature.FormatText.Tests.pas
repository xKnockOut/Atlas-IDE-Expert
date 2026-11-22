unit Atlas.UI.Signature.FormatText.Tests;

// Tests der Zeile der Platzhalter im Parameter-Hint (#451) in beiden Sprachen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSignatureFormatTextTests = class
  public
    [Test]
    procedure Lines;
  end;

implementation

uses
  Atlas.Core.Signature.Contract,
  Atlas.Core.Signature.Format,
  Atlas.UI.Strings,
  Atlas.UI.Signature.FormatText;

procedure TAtlasSignatureFormatTextTests.Lines;
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
    Assert.AreEqual('Platzhalter 2 von 2 erwartet ganzzahlig', TAtlasSignatureFormatText.Line(mLine));
    mLine.Kind := TAtlasFormatLineKind.Problem;
    mLine.Problem := TAtlasFormatProblem.TooManyArguments;
    mLine.Argument := 2;
    Assert.AreEqual('Mehr Argumente als Platzhalter: Argument 3 wird nicht ausgegeben.',
      TAtlasSignatureFormatText.Line(mLine));
    mLine.Problem := TAtlasFormatProblem.TypeConflict;
    mLine.Argument := 1;
    mLine.PlaceholderText := '%d';
    mLine.ProblemKind := 'string';
    Assert.AreEqual('Platzhalter 2 (%d) erwartet ganzzahlig, Argument 2 ist ein String: EConvertError zur Laufzeit.',
      TAtlasSignatureFormatText.Line(mLine));
    TAtlasStrings.Language := TAtlasLanguage.English;
    mLine.Kind := TAtlasFormatLineKind.Placeholder;
    mLine.TypeChar := 's';
    Assert.AreEqual('Placeholder 2 of 2 expects string', TAtlasSignatureFormatText.Line(mLine));
    Assert.AreEqual('', TAtlasSignatureFormatText.Line(Default(TAtlasFormatLine)));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSignatureFormatTextTests);

end.
