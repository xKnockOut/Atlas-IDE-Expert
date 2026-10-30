unit Atlas.Common.Rules.FormatOutput.Tests;

// Tests für die Ausgabe von --format-check und --format-write (#1358): Text,
// JSON, Diff, Zusammenfassung und Exit-Codes.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormatOutputTests = class
  public
    [Test]
    procedure TextShowsFirstDeviations;
    [Test]
    procedure TextNamesSyntaxErrorAndWrittenFiles;
    [Test]
    procedure JsonListsAllDeviations;
    [Test]
    procedure DiffIsUnified;
    [Test]
    procedure ExitCodes;
    [Test]
    procedure SummaryCountsFiles;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Editing.FormatCheck,
  Atlas.Common.Rules.Output,
  Atlas.Common.Rules.FormatOutput;

function FileOf(const APath, AText: string): TFormattedFile;
begin
  Result := TFormattedFile.Create(APath, TFormatCheck.Run(AText, TFormatStyle.Default, TFormatScope.All,
    Default(TPreprocessorOptions)));
end;

const
  cClean = 'procedure P;'#10'begin'#10'  A := 1;'#10'end;';
  cIndented = 'procedure P;'#10'begin'#10'   A := 1;'#10'end;';
  cBroken = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  if then;'#10'end;'#10'end.';

{ TFormatOutputTests }

procedure TFormatOutputTests.TextShowsFirstDeviations;
var
  mText, mBody: string;
  mIndex: Integer;
begin
  mBody := 'procedure P;'#10'begin';
  for mIndex := 1 to 7 do
    mBody := mBody + #10'   A := 1;';
  mBody := mBody + #10'end;';
  mText := TFormatOutput.Render([FileOf('a.pas', cClean), FileOf('Sub\b.pas', mBody)], TFormatOutputKind.Text, False);
  Assert.IsFalse(mText.Contains('a.pas'), mText);
  Assert.IsTrue(mText.Contains('Sub\b.pas: 7 Abweichungen'), mText);
  Assert.IsTrue(mText.Contains('  Zeile 3: Einrückung 3 statt 2'), mText);
  Assert.IsTrue(mText.Contains('  Zeile 7: Einrückung 3 statt 2'), mText);
  Assert.IsFalse(mText.Contains('Zeile 8:'), mText);
  Assert.IsTrue(mText.Contains('… und 2 weitere'), mText);
end;

procedure TFormatOutputTests.TextNamesSyntaxErrorAndWrittenFiles;
var
  mWritten: TFormattedFile;
  mText: string;
begin
  mWritten := FileOf('b.pas', cIndented);
  mWritten.Written := True;
  mText := TFormatOutput.Render([FileOf('a.pas', cBroken), mWritten], TFormatOutputKind.Text, True);
  Assert.IsTrue(mText.Contains('a.pas(6,'), mText);
  Assert.IsTrue(mText.Contains('Syntaxfehler, nicht formatiert'), mText);
  Assert.IsTrue(mText.Contains('b.pas: formatiert (1 Abweichungen)'), mText);
end;

procedure TFormatOutputTests.JsonListsAllDeviations;
var
  mJson: TJSONValue;
  mFiles, mDeviations: TJSONArray;
  mFirst, mSecond, mDeviation, mSyntax: TJSONObject;
  mText, mMode, mPath, mKind: string;
  mLine, mSyntaxLine, mCount, mChanged, mSyntaxErrors: Integer;
begin
  mText := TFormatOutput.Render([FileOf('a.pas', cClean), FileOf('Sub\b.pas', cIndented), FileOf('c.pas', cBroken)],
    TFormatOutputKind.Json, False);
  mJson := TJSONObject.ParseJSONValue(mText);
  try
    Assert.IsTrue(mJson is TJSONObject, mText);
    mMode := TJSONObject(mJson).GetValue<string>('mode');
    Assert.AreEqual('check', mMode);
    mFiles := TJSONObject(mJson).GetValue<TJSONArray>('files');
    Assert.AreEqual(2, mFiles.Count);
    mFirst := mFiles.Items[0] as TJSONObject;
    mSecond := mFiles.Items[1] as TJSONObject;
    mPath := mFirst.GetValue<string>('path');
    Assert.AreEqual('Sub/b.pas', mPath);
    mDeviations := mFirst.GetValue<TJSONArray>('deviations');
    mDeviation := mDeviations.Items[0] as TJSONObject;
    mLine := mDeviation.GetValue<Integer>('line');
    mKind := mDeviation.GetValue<string>('kind');
    Assert.AreEqual(3, mLine);
    Assert.AreEqual('indent', mKind);
    mSyntax := mSecond.GetValue<TJSONObject>('syntaxError');
    mSyntaxLine := mSyntax.GetValue<Integer>('line');
    Assert.AreEqual(6, mSyntaxLine);
    mCount := TJSONObject(mJson).GetValue<Integer>('summary.files');
    mChanged := TJSONObject(mJson).GetValue<Integer>('summary.changed');
    mSyntaxErrors := TJSONObject(mJson).GetValue<Integer>('summary.syntaxErrors');
    Assert.AreEqual(3, mCount);
    Assert.AreEqual(1, mChanged);
    Assert.AreEqual(1, mSyntaxErrors);
  finally
    mJson.Free;
  end;
end;

procedure TFormatOutputTests.DiffIsUnified;
var
  mText: string;
begin
  mText := TFormatOutput.Render([FileOf('a.pas', cClean), FileOf('Sub\b.pas', cIndented)], TFormatOutputKind.Diff,
    False);
  Assert.AreEqual('--- a/Sub/b.pas'#10'+++ b/Sub/b.pas'#10'@@ -1,4 +1,4 @@'#10' procedure P;'#10' begin'#10 +
    '-   A := 1;'#10'+  A := 1;'#10' end;'#10, mText);
  // Ein Umbruch am Ende beider Texte ist keine eigene Zeile.
  mText := TFormatOutput.Render([FileOf('c.pas', cIndented + #10)], TFormatOutputKind.Diff, False);
  Assert.IsTrue(mText.EndsWith(' end;'#10), mText);
end;

procedure TFormatOutputTests.ExitCodes;
var
  mFailed: TFormattedFile;
begin
  Assert.AreEqual(TFindingsOutput.ExitClean, TFormatOutput.ExitCode([FileOf('a.pas', cClean)], False));
  Assert.AreEqual(TFindingsOutput.ExitFindings, TFormatOutput.ExitCode([FileOf('a.pas', cClean),
    FileOf('b.pas', cIndented)], False));
  // Beim Schreiben ist eine Abweichung erledigt, ein Syntaxfehler nicht.
  Assert.AreEqual(TFindingsOutput.ExitClean, TFormatOutput.ExitCode([FileOf('b.pas', cIndented)], True));
  Assert.AreEqual(TFindingsOutput.ExitFindings, TFormatOutput.ExitCode([FileOf('c.pas', cBroken)], True));
  Assert.AreEqual(TFindingsOutput.ExitFindings, TFormatOutput.ExitCode([FileOf('c.pas', cBroken)], False));
  mFailed := FileOf('b.pas', cIndented);
  mFailed.Error := 'gesperrt';
  Assert.AreEqual(TFindingsOutput.ExitFailure, TFormatOutput.ExitCode([mFailed], True));
end;

procedure TFormatOutputTests.SummaryCountsFiles;
begin
  Assert.AreEqual('Formatierung: 1 von 3 Dateien weichen ab, 1 mit Syntaxfehlern nicht formatiert',
    TFormatOutput.Summary([FileOf('a.pas', cClean), FileOf('b.pas', cIndented), FileOf('c.pas', cBroken)], False));
  Assert.AreEqual('Formatierung: 0 von 1 Dateien geschrieben',
    TFormatOutput.Summary([FileOf('b.pas', cIndented)], True));
end;

initialization
  TDUnitX.RegisterTestFixture(TFormatOutputTests);

end.
