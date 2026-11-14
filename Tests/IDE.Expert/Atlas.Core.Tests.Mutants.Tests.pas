unit Atlas.Core.Tests.Mutants.Tests;

// Tests der Mutanten im Plugin (#1460): Antwort des Servers lesen, Mutant auf
// Zeilen anwenden (eine und mehrere Zeilen, Entfernen, geänderter Text),
// Nummer in der Routine, Prüfsumme der Routine.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasMutantsTests = class
  public
    [Test]
    procedure ParsesServerAnswer;
    [Test]
    procedure RejectsOtherFormat;
    [Test]
    procedure AppliesInOneLine;
    [Test]
    procedure AppliesOverLines;
    [Test]
    procedure RemovalKeepsLineCount;
    [Test]
    procedure ChangedTextIsNotApplied;
    [Test]
    procedure IndexInRoutine;
    [Test]
    procedure RoutineBodyIgnoresIndent;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tests.Mutants;

const
  cAnswer = '{"format": 1, "file": "file:///C:/P/Preise.pas", "count": 3, "operators": {"boundary": 1}, ' +
    '"mutants": [' +
    '{"id": 1, "operator": "boundary", "routine": "Satz", "line": 6, "character": 13, "endLine": 6, ' +
    '"endCharacter": 15, "startOffset": 0, "endOffset": 0, "original": ">=", "replacement": ">", ' +
    '"description": ">= durch >"},' +
    '{"id": 2, "operator": "number", "routine": "Satz", "line": 7, "character": 15, "endLine": 7, ' +
    '"endCharacter": 17, "startOffset": 0, "endOffset": 0, "original": "10", "replacement": "11"},' +
    '{"id": 3, "operator": "arithmetic", "routine": "Doppelt", "line": 13, "character": 15, "endLine": 13, ' +
    '"endCharacter": 16, "original": "+", "replacement": "-"},' +
    '{"id": 4, "operator": "boundary", "routine": "Kaputt", "line": 0, "character": 0}], ' +
    '"uri": "file:///C:/P/Preise.pas", ' +
    '"routines": [{"name": "Satz", "line": 3, "endLine": 9}, {"name": "Doppelt", "line": 10, "endLine": 13}, ' +
    '{"name": ""}]}';

function SampleLines: TArray<string>;
begin
  Result := TArray<string>.Create('unit Preise;', 'interface', 'implementation',
    'function Satz(AMenge: Integer): Integer;', 'begin', '  if AMenge >= 100 then', '    Result := 10',
    '  else', '    Result := 0;', 'end;', 'function Doppelt(A: Integer): Integer;', 'begin',
    '  Result := A + A;', 'end;', 'end.');
end;

function Mutant(ALine, ACharacter, AEndLine, AEndCharacter: Integer; const AOriginal,
  AReplacement: string): TAtlasMutant;
begin
  Result := Default(TAtlasMutant);
  Result.Line := ALine;
  Result.Character := ACharacter;
  Result.EndLine := AEndLine;
  Result.EndCharacter := AEndCharacter;
  Result.Original := AOriginal;
  Result.Replacement := AReplacement;
end;

{ TAtlasMutantsTests }

procedure TAtlasMutantsTests.ParsesServerAnswer;
var
  mList: TAtlasMutantList;
  mRoutine: TAtlasMutantRoutine;
begin
  Assert.IsTrue(TAtlasMutants.Parse(cAnswer, mList));
  Assert.AreEqual('file:///C:/P/Preise.pas', mList.Uri);
  // Der vierte Eintrag hat keinen Bereich und fällt weg, ebenso die Routine ohne Namen.
  Assert.AreEqual(3, Integer(Length(mList.Mutants)));
  Assert.AreEqual('boundary', mList.Mutants[0].OperatorId);
  Assert.AreEqual('>= durch >', mList.Mutants[0].Description);
  Assert.AreEqual(2, Integer(Length(mList.Routines)));
  Assert.IsTrue(mList.RoutineOf('Doppelt', mRoutine));
  Assert.AreEqual(10, mRoutine.Line);
  Assert.AreEqual(13, mRoutine.EndLine);
  Assert.IsFalse(mList.RoutineOf('Fehlt', mRoutine));
  Assert.AreEqual(2, Integer(Length(mList.MutantsOf('Satz'))));
end;

procedure TAtlasMutantsTests.RejectsOtherFormat;
var
  mList: TAtlasMutantList;
begin
  Assert.IsFalse(TAtlasMutants.Parse('{"format": 2, "mutants": []}', mList));
  Assert.IsFalse(TAtlasMutants.Parse('kein JSON', mList));
  Assert.IsFalse(TAtlasMutants.Parse('[1]', mList));
end;

procedure TAtlasMutantsTests.AppliesInOneLine;
var
  mList: TAtlasMutantList;
  mMutated: TArray<string>;
begin
  Assert.IsTrue(TAtlasMutants.Parse(cAnswer, mList));
  Assert.IsTrue(TAtlasMutants.Apply(SampleLines, mList.Mutants[0], mMutated));
  Assert.AreEqual(Length(SampleLines), Length(mMutated));
  Assert.AreEqual('  if AMenge > 100 then', mMutated[5]);
  Assert.AreEqual('    Result := 10', mMutated[6]);
  Assert.IsTrue(TAtlasMutants.Apply(SampleLines, mList.Mutants[2], mMutated));
  Assert.AreEqual('  Result := A - A;', mMutated[12]);
end;

procedure TAtlasMutantsTests.AppliesOverLines;
var
  mMutated: TArray<string>;
begin
  // "10\r\n  else" über zwei Zeilen durch "11" ersetzt: aus zwei Zeilen wird eine.
  Assert.IsTrue(TAtlasMutants.Apply(SampleLines, Mutant(7, 15, 8, 7, '10'#13#10'  else', '11 else'), mMutated));
  Assert.AreEqual(Length(SampleLines) - 1, Integer(Length(mMutated)));
  Assert.AreEqual('    Result := 11 else', mMutated[6]);
  Assert.AreEqual('    Result := 0;', mMutated[7]);
  // Ersatz mit Zeilenende fügt eine Zeile ein.
  Assert.IsTrue(TAtlasMutants.Apply(SampleLines, Mutant(13, 3, 13, 19, 'Result := A + A;',
    'Result := A;'#13#10'  Exit;'), mMutated));
  Assert.AreEqual(Length(SampleLines) + 1, Integer(Length(mMutated)));
  Assert.AreEqual('  Exit;', mMutated[13]);
end;

procedure TAtlasMutantsTests.RemovalKeepsLineCount;
var
  mMutated: TArray<string>;
begin
  Assert.IsTrue(TAtlasMutants.Apply(SampleLines, Mutant(13, 1, 13, 19, '  Result := A + A;', ''), mMutated));
  Assert.AreEqual(Length(SampleLines), Length(mMutated));
  Assert.AreEqual('', mMutated[12]);
  Assert.AreEqual('end;', mMutated[13]);
end;

procedure TAtlasMutantsTests.ChangedTextIsNotApplied;
var
  mLines, mMutated: TArray<string>;
begin
  mLines := SampleLines;
  mLines[5] := '  if AMenge <= 100 then';
  Assert.IsFalse(TAtlasMutants.Apply(mLines, Mutant(6, 13, 6, 15, '>=', '>'), mMutated));
  Assert.AreEqual(0, Integer(Length(mMutated)));
  // Außerhalb der Zeilen.
  Assert.IsFalse(TAtlasMutants.Apply(mLines, Mutant(40, 1, 40, 2, 'x', 'y'), mMutated));
  Assert.IsFalse(TAtlasMutants.Apply(mLines, Mutant(6, 90, 6, 92, '>=', '>'), mMutated));
end;

procedure TAtlasMutantsTests.IndexInRoutine;
var
  mList: TAtlasMutantList;
begin
  Assert.IsTrue(TAtlasMutants.Parse(cAnswer, mList));
  Assert.AreEqual(0, mList.IndexInRoutine(0));
  Assert.AreEqual(1, mList.IndexInRoutine(1));
  Assert.AreEqual(0, mList.IndexInRoutine(2));
end;

procedure TAtlasMutantsTests.RoutineBodyIgnoresIndent;
var
  mList: TAtlasMutantList;
  mRoutine: TAtlasMutantRoutine;
  mLines: TArray<string>;
  mBody: string;
begin
  Assert.IsTrue(TAtlasMutants.Parse(cAnswer, mList));
  Assert.IsTrue(mList.RoutineOf('Satz', mRoutine));
  mLines := SampleLines;
  mBody := TAtlasMutants.RoutineBody(mLines, mRoutine);
  Assert.AreNotEqual('', mBody);
  mLines[6] := '        Result := 10 // Kommentar';
  Assert.AreEqual(mBody, TAtlasMutants.RoutineBody(mLines, mRoutine));
  mLines[6] := '    Result := 20';
  Assert.AreNotEqual(mBody, TAtlasMutants.RoutineBody(mLines, mRoutine));
  // Routine nicht mehr in den Zeilen.
  mRoutine.EndLine := 99;
  Assert.AreEqual('', TAtlasMutants.RoutineBody(mLines, mRoutine));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMutantsTests);

end.
