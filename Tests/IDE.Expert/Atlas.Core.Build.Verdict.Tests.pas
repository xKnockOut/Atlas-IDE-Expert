unit Atlas.Core.Build.Verdict.Tests;

// Tests für die Schranke für Hinweise und Warnungen (#530): Zählung,
// Bewertung mit build.zeroHints und build.warningsAsErrors, Basislinie, die
// Frage an den Server (Run) samt Argumenten und Antwort.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasBuildVerdictTests = class
  public
    [Test]
    procedure ParsesWarningsAsErrorsCodes;
    /// <summary>Abnahme: ein Build mit H2164 zählt einen Hinweis und gilt ohne zeroHints als erfolgreich.</summary>
    [Test]
    procedure CountsWarningsAndHints;
    /// <summary>Abnahme: mit zeroHints gilt derselbe Build als gescheitert.</summary>
    [Test]
    procedure ZeroHintsRejectsBuild;
    /// <summary>Abnahme: W1035 in warningsAsErrors lässt einen Build mit dieser Warnung scheitern, andere nicht.
    /// </summary>
    [Test]
    procedure WarningsAsErrorsOnlyListedCodes;
    /// <summary>Abnahme: Eine Meldung in der Basislinie zählt nicht, eine neue schon.</summary>
    [Test]
    procedure BaselinedMessagesDoNotCount;
    [Test]
    procedure CompilerFailureWins;
    [Test]
    procedure FirstPointsToRelevantMessage;
    [Test]
    procedure RunAsksServerOnlyWhenNeeded;
    [Test]
    procedure RunCountsAllWithoutAnswer;
    [Test]
    procedure ArgumentsAndAnswer;
    [Test]
    procedure AddAnswer;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Verdict;

function Msg(const AKind, AText: string; ALine: Integer): TAtlasCompilerMessage;
begin
  Result := TAtlasCompilerMessages.FromIde(AKind, AText, 'C:\P\U.pas', ALine, 3);
end;

function Settings(AZeroHints: Boolean; const ACodes: string): TAtlasBuildVerdictSettings;
begin
  Result := TAtlasBuildVerdictSettings.Create(AZeroHints, ACodes);
end;

{ TAtlasBuildVerdictTests }

procedure TAtlasBuildVerdictTests.ParsesWarningsAsErrorsCodes;
var
  Codes: TArray<string>;
begin
  Codes := TAtlasBuildVerdicts.ParseCodes(' w1035;H2164, E2003 W1035 W12 x1035');
  Assert.AreEqual(2, Integer(Length(Codes)));
  Assert.AreEqual('W1035', Codes[0]);
  Assert.AreEqual('H2164', Codes[1]);
  Assert.AreEqual('W1035, H2164', TAtlasBuildVerdicts.NormalizeCodes('w1035 h2164'));
  Assert.AreEqual('', TAtlasBuildVerdicts.NormalizeCodes(''));
end;

procedure TAtlasBuildVerdictTests.CountsWarningsAndHints;
var
  Verdict: TAtlasBuildVerdict;
begin
  Verdict := TAtlasBuildVerdicts.Evaluate([Msg('Hint', 'H2164 Variable X ist deklariert, aber nicht verwendet', 5),
    Msg('Info', 'Erfolg', 0)], nil, True, Settings(False, ''));
  Assert.AreEqual(0, Verdict.Errors);
  Assert.AreEqual(0, Verdict.Warnings);
  Assert.AreEqual(1, Verdict.Hints);
  Assert.IsTrue(Verdict.Effective);
  Assert.IsFalse(Verdict.BaselineChecked);
end;

procedure TAtlasBuildVerdictTests.ZeroHintsRejectsBuild;
var
  Verdict: TAtlasBuildVerdict;
begin
  Verdict := TAtlasBuildVerdicts.Evaluate([Msg('Hint', 'H2164 X', 5)], nil, True, Settings(True, ''));
  Assert.IsFalse(Verdict.Effective);
  Assert.IsTrue(Verdict.Reason = TAtlasBuildVerdictReason.ZeroHints);
  Verdict := TAtlasBuildVerdicts.Evaluate([Msg('Info', 'Erfolg', 0)], nil, True, Settings(True, ''));
  Assert.IsTrue(Verdict.Effective, 'ohne Warnungen und Hinweise');
end;

procedure TAtlasBuildVerdictTests.WarningsAsErrorsOnlyListedCodes;
var
  Verdict: TAtlasBuildVerdict;
begin
  Verdict := TAtlasBuildVerdicts.Evaluate([Msg('Warning', 'W1036 Variable X ist vielleicht nicht initialisiert', 4),
    Msg('Warning', 'W1035 Ergebnis der Funktion F ist vielleicht undefiniert', 9)], nil, True,
    Settings(False, 'W1035'));
  Assert.IsTrue(Verdict.Reason = TAtlasBuildVerdictReason.WarningsAsErrors);
  Assert.AreEqual(1, Verdict.Promoted);
  Assert.AreEqual('W1035', Verdict.PromotedCode);
  Assert.AreEqual(1, Verdict.First, 'zeigt auf W1035');
  Verdict := TAtlasBuildVerdicts.Evaluate([Msg('Warning', 'W1036 X', 4)], nil, True, Settings(False, 'W1035'));
  Assert.IsTrue(Verdict.Effective, 'andere Warnungen nicht');
  Assert.AreEqual(1, Verdict.Warnings);
end;

procedure TAtlasBuildVerdictTests.BaselinedMessagesDoNotCount;
var
  Messages: TArray<TAtlasCompilerMessage>;
  Verdict: TAtlasBuildVerdict;
begin
  Messages := [Msg('Hint', 'H2164 X', 5), Msg('Hint', 'H2164 Y', 8)];
  Verdict := TAtlasBuildVerdicts.Evaluate(Messages, TArray<Boolean>.Create(True, False), True, Settings(True, ''));
  Assert.IsTrue(Verdict.BaselineChecked);
  Assert.AreEqual(1, Verdict.Baselined);
  Assert.AreEqual(1, Verdict.Hints, 'die neue Meldung zählt');
  Assert.IsFalse(Verdict.Effective);
  Assert.AreEqual(1, Verdict.First);
  Verdict := TAtlasBuildVerdicts.Evaluate([Messages[0]], TArray<Boolean>.Create(True), True, Settings(True, ''));
  Assert.IsTrue(Verdict.Effective, 'nur die bekannte Meldung');
  Assert.AreEqual(0, Verdict.Hints);
  // Auch warningsAsErrors gilt nur für gezählte Meldungen.
  Verdict := TAtlasBuildVerdicts.Evaluate([Messages[0]], TArray<Boolean>.Create(True), True,
    Settings(False, 'H2164'));
  Assert.IsTrue(Verdict.Effective);
end;

procedure TAtlasBuildVerdictTests.CompilerFailureWins;
var
  Verdict: TAtlasBuildVerdict;
begin
  Verdict := TAtlasBuildVerdicts.Evaluate([Msg('Error', 'E2003 Undeklarierter Bezeichner: X', 7)], nil, False,
    Settings(True, 'W1035'));
  Assert.IsTrue(Verdict.Reason = TAtlasBuildVerdictReason.CompilerFailed);
  Assert.AreEqual(1, Verdict.Errors);
  Verdict := TAtlasBuildVerdicts.Evaluate(nil, nil, False, Settings(False, ''));
  Assert.IsTrue(Verdict.Reason = TAtlasBuildVerdictReason.CompilerFailed, 'ohne Meldung, z. B. Linker');
  Assert.AreEqual(-1, Verdict.First);
end;

procedure TAtlasBuildVerdictTests.FirstPointsToRelevantMessage;
var
  Messages: TArray<TAtlasCompilerMessage>;
  Verdict: TAtlasBuildVerdict;
begin
  Messages := [Msg('Hint', 'H2164 X', 5), Msg('Error', 'E2003 X', 7)];
  Messages[0].FileName := '';
  Verdict := TAtlasBuildVerdicts.Evaluate(Messages, nil, False, Settings(False, ''));
  Assert.AreEqual(1, Verdict.First, 'Fehler zuerst');
  Verdict := TAtlasBuildVerdicts.Evaluate([Messages[0]], nil, True, Settings(True, ''));
  Assert.AreEqual(-1, Verdict.First, 'ohne Datei kein Ziel');
end;

procedure TAtlasBuildVerdictTests.RunAsksServerOnlyWhenNeeded;
var
  Asked: Integer;
  Got: TAtlasBuildVerdict;
  Classify: TAtlasBuildClassify;
begin
  Asked := 0;
  Classify :=
    function(const AMessages: TArray<TAtlasCompilerMessage>; const ADone: TAtlasBuildBaselined): Boolean
    begin
      Inc(Asked);
      ADone(TArray<Boolean>.Create(True));
      Result := True;
    end;
  TAtlasBuildVerdicts.Run([Msg('Info', 'Erfolg', 0)], True, Settings(True, ''), Classify,
    procedure(const AVerdict: TAtlasBuildVerdict)
    begin
      Got := AVerdict;
    end);
  Assert.AreEqual(0, Asked, 'nichts zu fragen');
  Assert.IsTrue(Got.Effective);
  TAtlasBuildVerdicts.Run([Msg('Hint', 'H2164 X', 5)], True, Settings(True, ''), Classify,
    procedure(const AVerdict: TAtlasBuildVerdict)
    begin
      Got := AVerdict;
    end);
  Assert.AreEqual(1, Asked);
  Assert.AreEqual(1, Got.Baselined);
  Assert.IsTrue(Got.Effective);
  Classify := nil;
end;

procedure TAtlasBuildVerdictTests.RunCountsAllWithoutAnswer;
var
  Calls: Integer;
  Got: TAtlasBuildVerdict;
begin
  Calls := 0;
  // Kein Server: Classify fragt nicht, Run bewertet sofort.
  TAtlasBuildVerdicts.Run([Msg('Hint', 'H2164 X', 5)], True, Settings(True, ''),
    function(const AMessages: TArray<TAtlasCompilerMessage>; const ADone: TAtlasBuildBaselined): Boolean
    begin
      Result := False;
    end,
    procedure(const AVerdict: TAtlasBuildVerdict)
    begin
      Inc(Calls);
      Got := AVerdict;
    end);
  Assert.AreEqual(1, Calls);
  Assert.AreEqual(1, Got.Hints);
  Assert.IsFalse(Got.Effective);
  // Antwort unbrauchbar (nil): alles zählt.
  TAtlasBuildVerdicts.Run([Msg('Hint', 'H2164 X', 5)], True, Settings(True, ''),
    function(const AMessages: TArray<TAtlasCompilerMessage>; const ADone: TAtlasBuildBaselined): Boolean
    begin
      ADone(nil);
      Result := True;
    end,
    procedure(const AVerdict: TAtlasBuildVerdict)
    begin
      Inc(Calls);
      Got := AVerdict;
    end);
  Assert.AreEqual(2, Calls, 'genau einmal je Lauf');
  Assert.AreEqual(1, Got.Hints);
end;

procedure TAtlasBuildVerdictTests.ArgumentsAndAnswer;
var
  Answer, Arguments: TJSONValue;
  Item: TJSONObject;
  Baselined: TArray<Boolean>;
begin
  Arguments := TJSONObject.ParseJSONValue(TAtlasBuildVerdicts.Arguments('file:///C:/P/P.dproj',
    [Msg('Hint', 'H2164 X', 5)]));
  try
    Assert.IsTrue(Arguments is TJSONArray);
    Assert.AreEqual('file:///C:/P/P.dproj', TJSONArray(Arguments).Items[0].Value);
    Item := TJSONObject(TJSONArray(TJSONArray(Arguments).Items[1]).Items[0]);
    Assert.AreEqual('C:\P\U.pas', Item.GetValue('file').Value);
    Assert.AreEqual(5, Item.GetValue<Integer>('line', 0));
    Assert.AreEqual('H2164', Item.GetValue('code').Value);
  finally
    Arguments.Free;
  end;
  Answer := TJSONObject.ParseJSONValue('{"format": 1, "baseline": "valid", "baselined": [0, 2, 7]}');
  try
    Baselined := TAtlasBuildVerdicts.BaselinedOf(Answer, 3);
  finally
    Answer.Free;
  end;
  Assert.AreEqual(3, Integer(Length(Baselined)));
  Assert.IsTrue(Baselined[0]);
  Assert.IsFalse(Baselined[1]);
  Assert.IsTrue(Baselined[2]);
  Assert.AreEqual(0, Integer(Length(TAtlasBuildVerdicts.BaselinedOf(nil, 3))), 'keine Antwort');
end;

procedure TAtlasBuildVerdictTests.AddAnswer;
var
  Answer: TJSONValue;
  Added: TAtlasCompilerBaselineAdd;
begin
  Answer := TJSONObject.ParseJSONValue('{"format": 1, "file": "C:\\P\\atlas-baseline.json", "previous": "none", ' +
    '"total": 3, "files": 2, "added": 3, "removed": 0, "unchanged": 0, "skipped": 1}');
  try
    Assert.IsTrue(TAtlasCompilerBaselineAdd.FromServer(Answer, Added));
  finally
    Answer.Free;
  end;
  Assert.AreEqual('C:\P\atlas-baseline.json', Added.FileName);
  Assert.AreEqual(3, Added.Total);
  Assert.AreEqual(1, Added.Skipped);
  Assert.IsFalse(TAtlasCompilerBaselineAdd.FromServer(nil, Added));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBuildVerdictTests);

end.
