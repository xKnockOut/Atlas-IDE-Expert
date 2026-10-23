unit Atlas.Core.Signature.Format.Tests;

// Tests der Platzhalter im Parameter-Hint ohne Fenster (#451): Hint-Zeile zum Eintrag am Cursor und Farben im
// Editor.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSignatureFormatTests = class
  public
    [Test]
    procedure LineNamesPlaceholderOfActiveArgument;
    [Test]
    procedure LineForWidthAndUnusedArguments;
    [Test]
    procedure ProblemComesFirst;
    [Test]
    procedure MarksPairPlaceholderAndArgument;
    [Test]
    procedure MarksRepeatAfterSixAndSkipEmpty;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Signature.Contract,
  Atlas.Core.Signature.Format;

function Range(ALine, AStart, AStop: Integer): TAtlasFormatRange;
begin
  Result.StartLine := ALine;
  Result.StartCharacter := AStart;
  Result.EndLine := ALine;
  Result.EndCharacter := AStop;
end;

function Placeholder(const AText: string; AType: Char; AArgument: Integer): TAtlasFormatPlaceholder;
begin
  Result := Default(TAtlasFormatPlaceholder);
  Result.Text := AText;
  Result.TypeChar := AType;
  Result.Valid := True;
  Result.Argument := AArgument;
  Result.WidthArgument := -1;
  Result.PrecisionArgument := -1;
end;

/// <summary>Format('%s hat %d Zeilen', [FileName, Count]) in Zeile 3.</summary>
function Sample: TAtlasSignatureFormat;
begin
  Result := Default(TAtlasSignatureFormat);
  Result.Found := True;
  Result.ArgumentCount := 2;
  Result.ActiveArgument := 1;
  Result.ProblemPlaceholder := -1;
  Result.ProblemArgument := -1;
  Result.Placeholders := [Placeholder('%s', 's', 0), Placeholder('%d', 'd', 1)];
  Result.Placeholders[0].HasRange := True;
  Result.Placeholders[0].Range := Range(3, 15, 17);
  Result.Placeholders[1].HasRange := True;
  Result.Placeholders[1].Range := Range(3, 22, 24);
  Result.Arguments := [Range(3, 35, 43), Range(3, 45, 50)];
end;

procedure TAtlasSignatureFormatTests.LineNamesPlaceholderOfActiveArgument;
var
  mLine: TAtlasFormatLine;
begin
  mLine := TAtlasSignatureFormats.Line(Sample, 1);
  Assert.AreEqual(Ord(TAtlasFormatLineKind.Placeholder), Ord(mLine.Kind));
  Assert.AreEqual(1, mLine.Placeholder);
  Assert.AreEqual(2, mLine.Count);
  Assert.AreEqual('d', mLine.TypeChar);
  Assert.IsFalse(mLine.IsError);
  // Außerhalb der Liste und ohne Formatroutine: nichts.
  Assert.AreEqual(Ord(TAtlasFormatLineKind.None), Ord(TAtlasSignatureFormats.Line(Sample, -1).Kind));
  Assert.AreEqual(Ord(TAtlasFormatLineKind.None),
    Ord(TAtlasSignatureFormats.Line(Default(TAtlasSignatureFormat), 0).Kind));
end;

procedure TAtlasSignatureFormatTests.LineForWidthAndUnusedArguments;
var
  mFormat: TAtlasSignatureFormat;
  mLine: TAtlasFormatLine;
begin
  // '%*d': Breite aus Argument 0, Wert aus Argument 1.
  mFormat := Sample;
  mFormat.Placeholders := [Placeholder('%*d', 'd', 1)];
  mFormat.Placeholders[0].WidthArgument := 0;
  mLine := TAtlasSignatureFormats.Line(mFormat, 0);
  Assert.AreEqual(Ord(TAtlasFormatLineKind.Width), Ord(mLine.Kind));
  Assert.AreEqual('*', mLine.TypeChar);
  Assert.AreEqual(Ord(TAtlasFormatLineKind.Placeholder), Ord(TAtlasSignatureFormats.Line(mFormat, 1).Kind));
  // Dritter Eintrag ohne Platzhalter.
  mLine := TAtlasSignatureFormats.Line(Sample, 2);
  Assert.AreEqual(Ord(TAtlasFormatLineKind.Unused), Ord(mLine.Kind));
  Assert.IsTrue(mLine.IsError);
  // Bei Index "*" ist die Zuordnung unbekannt: keine Aussage.
  mFormat := Sample;
  mFormat.ArgumentCount := -1;
  Assert.AreEqual(Ord(TAtlasFormatLineKind.None), Ord(TAtlasSignatureFormats.Line(mFormat, 5).Kind));
end;

procedure TAtlasSignatureFormatTests.ProblemComesFirst;
var
  mFormat: TAtlasSignatureFormat;
  mLine: TAtlasFormatLine;
begin
  mFormat := Sample;
  mFormat.Problem := TAtlasFormatProblem.TypeConflict;
  mFormat.ProblemPlaceholder := 1;
  mFormat.ProblemArgument := 1;
  mFormat.ProblemKind := 'string';
  mLine := TAtlasSignatureFormats.Line(mFormat, 0);
  Assert.AreEqual(Ord(TAtlasFormatLineKind.Problem), Ord(mLine.Kind));
  Assert.AreEqual(1, mLine.Placeholder);
  Assert.AreEqual(1, mLine.Argument);
  Assert.AreEqual('d', mLine.TypeChar);
  Assert.AreEqual('%d', mLine.PlaceholderText);
  Assert.AreEqual('string', mLine.ProblemKind);
  Assert.IsTrue(mLine.IsError);
  // Auch außerhalb der Liste.
  Assert.AreEqual(Ord(TAtlasFormatLineKind.Problem), Ord(TAtlasSignatureFormats.Line(mFormat, -1).Kind));
end;

procedure TAtlasSignatureFormatTests.MarksPairPlaceholderAndArgument;
var
  mMarks: TArray<TAtlasFormatMark>;
begin
  mMarks := TAtlasSignatureFormats.Marks(Sample);
  Assert.AreEqual(4, Integer(Length(mMarks)));
  // Sortiert: %s, %d, FileName, Count; %s und FileName teilen Farbe 0.
  Assert.AreEqual(15, mMarks[0].Start);
  Assert.AreEqual(0, mMarks[0].Slot);
  Assert.AreEqual(22, mMarks[1].Start);
  Assert.AreEqual(1, mMarks[1].Slot);
  Assert.AreEqual(35, mMarks[2].Start);
  Assert.AreEqual(43, mMarks[2].Stop);
  Assert.AreEqual(0, mMarks[2].Slot);
  Assert.AreEqual(1, mMarks[3].Slot);
  Assert.AreEqual(0, Integer(Length(TAtlasSignatureFormats.Marks(Default(TAtlasSignatureFormat)))));
end;

procedure TAtlasSignatureFormatTests.MarksRepeatAfterSixAndSkipEmpty;
var
  mFormat: TAtlasSignatureFormat;
  mMarks: TArray<TAtlasFormatMark>;
  mIndex: Integer;
begin
  mFormat := Default(TAtlasSignatureFormat);
  mFormat.Found := True;
  mFormat.ArgumentCount := 7;
  for mIndex := 0 to 6 do
  begin
    mFormat.Placeholders := mFormat.Placeholders + [Placeholder('%d', 'd', mIndex)];
    mFormat.Arguments := mFormat.Arguments + [Range(1, mIndex * 3, mIndex * 3 + 1)];
  end;
  // Leerer letzter Eintrag (gerade getippt) und mehrzeiliger Eintrag bekommen keine Farbe.
  mFormat.Arguments[6] := Range(1, 18, 18);
  mFormat.Arguments[5].EndLine := 2;
  mMarks := TAtlasSignatureFormats.Marks(mFormat);
  Assert.AreEqual(5, Integer(Length(mMarks)));
  mFormat.Arguments[6] := Range(1, 18, 19);
  mMarks := TAtlasSignatureFormats.Marks(mFormat);
  Assert.AreEqual(0, mMarks[High(mMarks)].Slot, 'Farbe 7 = Farbe 1');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSignatureFormatTests);

end.
