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
  System.Generics.Collections,
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
  mCodes: TArray<string>;
begin
  mCodes := TAtlasBuildVerdicts.ParseCodes(' w1035;H2164, E2003 W1035 W12 x1035');
  Assert.AreEqual(2, Integer(Length(mCodes)));
  Assert.AreEqual('W1035', mCodes[0]);
  Assert.AreEqual('H2164', mCodes[1]);
  Assert.AreEqual('W1035, H2164', TAtlasBuildVerdicts.NormalizeCodes('w1035 h2164'));
  Assert.AreEqual('', TAtlasBuildVerdicts.NormalizeCodes(''));
end;

procedure TAtlasBuildVerdictTests.CountsWarningsAndHints;
var
  mVerdict: TAtlasBuildVerdict;
begin
  mVerdict := TAtlasBuildVerdicts.Evaluate([Msg('Hint', 'H2164 Variable X ist deklariert, aber nicht verwendet', 5),
    Msg('Info', 'Erfolg', 0)], nil, True, Settings(False, ''));
  Assert.AreEqual(0, mVerdict.Errors);
  Assert.AreEqual(0, mVerdict.Warnings);
  Assert.AreEqual(1, mVerdict.Hints);
  Assert.IsTrue(mVerdict.Effective);
  Assert.IsFalse(mVerdict.BaselineChecked);
end;

procedure TAtlasBuildVerdictTests.ZeroHintsRejectsBuild;
var
  mVerdict: TAtlasBuildVerdict;
begin
  mVerdict := TAtlasBuildVerdicts.Evaluate([Msg('Hint', 'H2164 X', 5)], nil, True, Settings(True, ''));
  Assert.IsFalse(mVerdict.Effective);
  Assert.AreEqual<TAtlasBuildVerdictReason>(TAtlasBuildVerdictReason.ZeroHints, mVerdict.Reason);
  mVerdict := TAtlasBuildVerdicts.Evaluate([Msg('Info', 'Erfolg', 0)], nil, True, Settings(True, ''));
  Assert.IsTrue(mVerdict.Effective, 'ohne Warnungen und Hinweise');
end;

procedure TAtlasBuildVerdictTests.WarningsAsErrorsOnlyListedCodes;
var
  mVerdict: TAtlasBuildVerdict;
begin
  mVerdict := TAtlasBuildVerdicts.Evaluate([Msg('Warning', 'W1036 Variable X ist vielleicht nicht initialisiert', 4),
    Msg('Warning', 'W1035 Ergebnis der Funktion F ist vielleicht undefiniert', 9)], nil, True,
    Settings(False, 'W1035'));
  Assert.AreEqual<TAtlasBuildVerdictReason>(TAtlasBuildVerdictReason.WarningsAsErrors, mVerdict.Reason);
  Assert.AreEqual(1, mVerdict.Promoted);
  Assert.AreEqual('W1035', mVerdict.PromotedCode);
  Assert.AreEqual(1, mVerdict.First, 'zeigt auf W1035');
  mVerdict := TAtlasBuildVerdicts.Evaluate([Msg('Warning', 'W1036 X', 4)], nil, True, Settings(False, 'W1035'));
  Assert.IsTrue(mVerdict.Effective, 'andere Warnungen nicht');
  Assert.AreEqual(1, mVerdict.Warnings);
end;

procedure TAtlasBuildVerdictTests.BaselinedMessagesDoNotCount;
var
  mMessages: TArray<TAtlasCompilerMessage>;
  mVerdict: TAtlasBuildVerdict;
begin
  mMessages := [Msg('Hint', 'H2164 X', 5), Msg('Hint', 'H2164 Y', 8)];
  mVerdict := TAtlasBuildVerdicts.Evaluate(mMessages, TArray<Boolean>.Create(True, False), True, Settings(True, ''));
  Assert.IsTrue(mVerdict.BaselineChecked);
  Assert.AreEqual(1, mVerdict.Baselined);
  Assert.AreEqual(1, mVerdict.Hints, 'die neue Meldung zählt');
  Assert.IsFalse(mVerdict.Effective);
  Assert.AreEqual(1, mVerdict.First);
  mVerdict := TAtlasBuildVerdicts.Evaluate([mMessages[0]], TArray<Boolean>.Create(True), True, Settings(True, ''));
  Assert.IsTrue(mVerdict.Effective, 'nur die bekannte Meldung');
  Assert.AreEqual(0, mVerdict.Hints);
  // Auch warningsAsErrors gilt nur für gezählte Meldungen.
  mVerdict := TAtlasBuildVerdicts.Evaluate([mMessages[0]], TArray<Boolean>.Create(True), True,
    Settings(False, 'H2164'));
  Assert.IsTrue(mVerdict.Effective);
end;

procedure TAtlasBuildVerdictTests.CompilerFailureWins;
var
  mVerdict: TAtlasBuildVerdict;
begin
  mVerdict := TAtlasBuildVerdicts.Evaluate([Msg('Error', 'E2003 Undeklarierter Bezeichner: X', 7)], nil, False,
    Settings(True, 'W1035'));
  Assert.AreEqual<TAtlasBuildVerdictReason>(TAtlasBuildVerdictReason.CompilerFailed, mVerdict.Reason);
  Assert.AreEqual(1, mVerdict.Errors);
  mVerdict := TAtlasBuildVerdicts.Evaluate(nil, nil, False, Settings(False, ''));
  Assert.AreEqual<TAtlasBuildVerdictReason>(TAtlasBuildVerdictReason.CompilerFailed,
    mVerdict.Reason, 'ohne Meldung, z. B. Linker');
  Assert.AreEqual(-1, mVerdict.First);
end;

procedure TAtlasBuildVerdictTests.FirstPointsToRelevantMessage;
var
  mMessages: TArray<TAtlasCompilerMessage>;
  mVerdict: TAtlasBuildVerdict;
begin
  mMessages := [Msg('Hint', 'H2164 X', 5), Msg('Error', 'E2003 X', 7)];
  mMessages[0].FileName := '';
  mVerdict := TAtlasBuildVerdicts.Evaluate(mMessages, nil, False, Settings(False, ''));
  Assert.AreEqual(1, mVerdict.First, 'Fehler zuerst');
  mVerdict := TAtlasBuildVerdicts.Evaluate([mMessages[0]], nil, True, Settings(True, ''));
  Assert.AreEqual(-1, mVerdict.First, 'ohne Datei kein Ziel');
end;

procedure TAtlasBuildVerdictTests.RunAsksServerOnlyWhenNeeded;
var
  mAsked: Integer;
  mGot: TAtlasBuildVerdict;
  mClassify: TAtlasBuildClassify;
begin
  mAsked := 0;
  mClassify :=
    function(const AMessages: TArray<TAtlasCompilerMessage>; const ADone: TAtlasBuildBaselined): Boolean
    begin
      Inc(mAsked);
      ADone(TArray<Boolean>.Create(True));
      Result := True;
    end;
  TAtlasBuildVerdicts.Run([Msg('Info', 'Erfolg', 0)], True, Settings(True, ''), mClassify,
    procedure(const AVerdict: TAtlasBuildVerdict)
    begin
      mGot := AVerdict;
    end);
  Assert.AreEqual(0, mAsked, 'nichts zu fragen');
  Assert.IsTrue(mGot.Effective);
  TAtlasBuildVerdicts.Run([Msg('Hint', 'H2164 X', 5)], True, Settings(True, ''), mClassify,
    procedure(const AVerdict: TAtlasBuildVerdict)
    begin
      mGot := AVerdict;
    end);
  Assert.AreEqual(1, mAsked);
  Assert.AreEqual(1, mGot.Baselined);
  Assert.IsTrue(mGot.Effective);
  mClassify := nil;
end;

procedure TAtlasBuildVerdictTests.RunCountsAllWithoutAnswer;
var
  mCalls: Integer;
  mGot: TAtlasBuildVerdict;
begin
  mCalls := 0;
  // Kein Server: Classify fragt nicht, Run bewertet sofort.
  TAtlasBuildVerdicts.Run([Msg('Hint', 'H2164 X', 5)], True, Settings(True, ''),
    function(const AMessages: TArray<TAtlasCompilerMessage>; const ADone: TAtlasBuildBaselined): Boolean
    begin
      Result := False;
    end,
    procedure(const AVerdict: TAtlasBuildVerdict)
    begin
      Inc(mCalls);
      mGot := AVerdict;
    end);
  Assert.AreEqual(1, mCalls);
  Assert.AreEqual(1, mGot.Hints);
  Assert.IsFalse(mGot.Effective);
  // Antwort unbrauchbar (nil): alles zählt.
  TAtlasBuildVerdicts.Run([Msg('Hint', 'H2164 X', 5)], True, Settings(True, ''),
    function(const AMessages: TArray<TAtlasCompilerMessage>; const ADone: TAtlasBuildBaselined): Boolean
    begin
      ADone(nil);
      Result := True;
    end,
    procedure(const AVerdict: TAtlasBuildVerdict)
    begin
      Inc(mCalls);
      mGot := AVerdict;
    end);
  Assert.AreEqual(2, mCalls, 'genau einmal je Lauf');
  Assert.AreEqual(1, mGot.Hints);
end;

procedure TAtlasBuildVerdictTests.ArgumentsAndAnswer;
var
  mAnswer, mArguments: TJSONValue;
  mItem: TJSONObject;
  mBaselined: TArray<Boolean>;
begin
  mArguments := TJSONObject.ParseJSONValue(TAtlasBuildVerdicts.Arguments('file:///C:/P/P.dproj',
    [Msg('Hint', 'H2164 X', 5)]));
  try
    Assert.IsTrue(mArguments is TJSONArray);
    Assert.AreEqual('file:///C:/P/P.dproj', TJSONArray(mArguments).Items[0].Value);
    mItem := TJSONObject(TJSONArray(TJSONArray(mArguments).Items[1]).Items[0]);
    Assert.AreEqual('C:\P\U.pas', mItem.GetValue('file').Value);
    Assert.AreEqual(5, mItem.GetValue<Integer>('line', 0));
    Assert.AreEqual('H2164', mItem.GetValue('code').Value);
  finally
    mArguments.Free;
  end;
  mAnswer := TJSONObject.ParseJSONValue('{"format": 1, "baseline": "valid", "baselined": [0, 2, 7]}');
  try
    mBaselined := TAtlasBuildVerdicts.BaselinedOf(mAnswer, 3);
  finally
    mAnswer.Free;
  end;
  Assert.AreEqual(3, Integer(Length(mBaselined)));
  Assert.IsTrue(mBaselined[0]);
  Assert.IsFalse(mBaselined[1]);
  Assert.IsTrue(mBaselined[2]);
  Assert.AreEqual(0, Integer(Length(TAtlasBuildVerdicts.BaselinedOf(nil, 3))), 'keine Antwort');
end;

procedure TAtlasBuildVerdictTests.AddAnswer;
var
  mAnswer: TJSONValue;
  mAdded: TAtlasCompilerBaselineAdd;
begin
  mAnswer := TJSONObject.ParseJSONValue('{"format": 1, "file": "C:\\P\\atlas-baseline.json", "previous": "none", ' +
    '"total": 3, "files": 2, "added": 3, "removed": 0, "unchanged": 0, "skipped": 1}');
  try
    Assert.IsTrue(TAtlasCompilerBaselineAdd.FromServer(mAnswer, mAdded));
  finally
    mAnswer.Free;
  end;
  Assert.AreEqual('C:\P\atlas-baseline.json', mAdded.FileName);
  Assert.AreEqual(3, mAdded.Total);
  Assert.AreEqual(1, mAdded.Skipped);
  Assert.IsFalse(TAtlasCompilerBaselineAdd.FromServer(nil, mAdded));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBuildVerdictTests);

end.
