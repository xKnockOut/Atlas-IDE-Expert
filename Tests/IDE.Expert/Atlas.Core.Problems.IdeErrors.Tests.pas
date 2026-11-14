unit Atlas.Core.Problems.IdeErrors.Tests;

// Tests für Fehler der IDE neben den Atlas-Befunden (#1819): Umrechnen der
// Werte aus Error Insight, Abgleich (gleiche Zeile, überlappender Bereich,
// gleiche Art), Quelle, Protokoll möglicher Fehlalarme ohne Namen, Speicher
// (nur WithIde, nicht ForFile) und Filter „Quelle“ des Fensters.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasIdeErrorsTests = class
  public
    [Test]
    procedure ConvertsIdeValuesToZeroBasedProblems;
    [Test]
    procedure SeverityFollowsLspAndUnknownIsError;
    [Test]
    procedure MatchesNeedSameLineOverlapAndKind;
    [Test]
    procedure MergeConfirmsAtlasAndKeepsOnlyUnmatchedIdeErrors;
    [Test]
    procedure EachIdeErrorConfirmsOnlyOneFinding;
    [Test]
    procedure CompilerMessagesAreNeverConfirmed;
    [Test]
    procedure OriginAndOriginText;
    [Test]
    procedure JournalLogsAtlasOnlyFalseAlarmsOnceWithoutNames;
    [Test]
    procedure StoreKeepsIdeErrorsOutOfForFile;
    [Test]
    procedure StoreDropsIdeErrorsInEditedLinesAndShiftsTheRest;
    [Test]
    procedure ClearIdeErrorsChangesTheStamp;
    [Test]
    procedure FindingsFilterBySource;
    /// <summary>Viele Befunde und Fehler der IDE: Abgleich nach jeder Prüfung im Hauptthread.</summary>
    [Test]
    [Category('Benchmark')]
    procedure MergeOfManyFindingsStaysFast;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.IdeErrors,
  Atlas.Core.Problems.Store,
  Atlas.Core.Problems.Findings;

const
  cFile = 'C:\P\Kunde.pas';
  cText = 'unit Kunde;'#10'a'#10'b'#10'c'#10'd'#10'e';

function Finding(ALine, AFrom, ATo: Integer; const ACode: string;
  ASeverity: TAtlasProblemSeverity): TAtlasProblem; overload;
begin
  Result := Default(TAtlasProblem);
  Result.StartLine := ALine;
  Result.StartCharacter := AFrom;
  Result.EndLine := ALine;
  Result.EndCharacter := ATo;
  Result.Code := ACode;
  Result.Source := TAtlasIdeErrors.cAtlasSource;
  Result.Message := 'Bezeichner Kundennummer nicht deklariert';
  Result.Severity := ASeverity;
end;

function Finding(ALine, AFrom, ATo: Integer; const ACode: string): TAtlasProblem; overload;
begin
  Result := Finding(ALine, AFrom, ATo, ACode, TAtlasProblemSeverity.Error);
end;

function IdeError(ALine, AFrom, ATo: Integer;
  ASeverity: TAtlasProblemSeverity): TAtlasProblem; overload;
begin
  Result := Default(TAtlasProblem);
  Result.StartLine := ALine;
  Result.StartCharacter := AFrom;
  Result.EndLine := ALine;
  Result.EndCharacter := ATo;
  Result.Source := TAtlasProblem.cIdeSource;
  Result.Message := 'Undeklarierter Bezeichner';
  Result.Severity := ASeverity;
end;

function IdeError(ALine, AFrom, ATo: Integer): TAtlasProblem; overload;
begin
  Result := IdeError(ALine, AFrom, ATo, TAtlasProblemSeverity.Error);
end;

function RawError(ALine, AFrom, AStopLine, ATo, ASeverity: Integer): TAtlasIdeError;
begin
  Result := Default(TAtlasIdeError);
  Result.Text := '  Undeklarierter Bezeichner: ''Foo''  ';
  Result.StartLine := ALine;
  Result.StartCharIndex := AFrom;
  Result.StopLine := AStopLine;
  Result.StopCharIndex := ATo;
  Result.Severity := ASeverity;
end;

procedure TAtlasIdeErrorsTests.ConvertsIdeValuesToZeroBasedProblems;
var
  mProblem: TAtlasProblem;
  mProblems: TArray<TAtlasProblem>;
begin
  mProblem := TAtlasIdeErrors.ToProblem(RawError(3, 4, 3, 7, 0));
  Assert.AreEqual(2, mProblem.StartLine, 'Zeile der IDE 1-basiert');
  Assert.AreEqual(4, mProblem.StartCharacter);
  Assert.AreEqual(2, mProblem.EndLine);
  Assert.AreEqual(7, mProblem.EndCharacter);
  Assert.AreEqual(TAtlasProblem.cIdeSource, mProblem.Source);
  Assert.IsTrue(mProblem.IsIde);
  Assert.AreEqual('Undeklarierter Bezeichner: ''Foo''', mProblem.Message, 'ohne Leerraum am Rand');
  // Unsinnige Werte: nichts vor Zeile 0, Ende nicht vor dem Anfang.
  mProblem := TAtlasIdeErrors.ToProblem(RawError(0, -2, 0, -5, 1));
  Assert.AreEqual(0, mProblem.StartLine);
  Assert.AreEqual(0, mProblem.StartCharacter);
  Assert.AreEqual(0, mProblem.EndLine);
  Assert.AreEqual(0, mProblem.EndCharacter);
  mProblem := TAtlasIdeErrors.ToProblem(RawError(5, 9, 5, 2, 1));
  Assert.AreEqual(9, mProblem.EndCharacter, 'Ende vor Anfang = leerer Bereich');
  mProblems := TAtlasIdeErrors.ToProblems([RawError(1, 0, 1, 1, 1), RawError(2, 0, 2, 1, 2)]);
  Assert.AreEqual(2, Integer(Length(mProblems)));
  Assert.AreEqual(1, mProblems[1].StartLine);
  Assert.AreEqual(0, Integer(Length(TAtlasIdeErrors.ToProblems(nil))));
end;

procedure TAtlasIdeErrorsTests.SeverityFollowsLspAndUnknownIsError;
begin
  Assert.AreEqual<TAtlasProblemSeverity>(TAtlasProblemSeverity.Error, TAtlasIdeErrors.SeverityOf(1));
  Assert.AreEqual<TAtlasProblemSeverity>(TAtlasProblemSeverity.Warning, TAtlasIdeErrors.SeverityOf(2));
  Assert.AreEqual<TAtlasProblemSeverity>(TAtlasProblemSeverity.Information, TAtlasIdeErrors.SeverityOf(3));
  Assert.AreEqual<TAtlasProblemSeverity>(TAtlasProblemSeverity.Hint, TAtlasIdeErrors.SeverityOf(4));
  Assert.AreEqual<TAtlasProblemSeverity>(TAtlasProblemSeverity.Error,
    TAtlasIdeErrors.SeverityOf(0), 'unbekannt = Fehler');
  Assert.AreEqual<TAtlasProblemSeverity>(TAtlasProblemSeverity.Error, TAtlasIdeErrors.SeverityOf(99));
end;

procedure TAtlasIdeErrorsTests.MatchesNeedSameLineOverlapAndKind;
var
  mAtlas: TAtlasProblem;
begin
  mAtlas := Finding(2, 4, 10, 'unresolved-identifier');
  Assert.IsTrue(TAtlasIdeErrors.Matches(mAtlas, IdeError(2, 8, 12)), 'überlappt');
  Assert.IsTrue(TAtlasIdeErrors.Matches(mAtlas, IdeError(2, 4, 4)), 'leerer Bereich am Anfang zählt als ein Zeichen');
  Assert.IsFalse(TAtlasIdeErrors.Matches(mAtlas, IdeError(2, 10, 14)), 'stößt nur an');
  Assert.IsFalse(TAtlasIdeErrors.Matches(mAtlas, IdeError(3, 4, 10)), 'andere Zeile');
  Assert.IsFalse(TAtlasIdeErrors.Matches(mAtlas, IdeError(2, 4, 10, TAtlasProblemSeverity.Warning)), 'andere Art');
  // Information und Hinweis sind eine Art (Info).
  mAtlas := Finding(2, 4, 10, 'x', TAtlasProblemSeverity.Hint);
  Assert.IsTrue(TAtlasIdeErrors.Matches(mAtlas, IdeError(2, 4, 10, TAtlasProblemSeverity.Information)));
end;

procedure TAtlasIdeErrorsTests.MergeConfirmsAtlasAndKeepsOnlyUnmatchedIdeErrors;
var
  mMerged: TArray<TAtlasProblem>;
begin
  mMerged := TAtlasIdeErrors.Merge([Finding(1, 0, 5, 'unresolved-identifier'), Finding(3, 0, 5, 'unresolved-type')],
    [IdeError(1, 2, 4), IdeError(2, 0, 1)]);
  Assert.AreEqual(3, Integer(Length(mMerged)));
  Assert.AreEqual('unresolved-identifier', mMerged[0].Code);
  Assert.IsTrue(mMerged[0].IdeConfirmed, 'von der IDE bestätigt');
  Assert.IsTrue(mMerged[1].IsIde, 'nur IDE, nach Position einsortiert');
  Assert.AreEqual(2, mMerged[1].StartLine);
  Assert.IsFalse(mMerged[2].IdeConfirmed, 'nur Atlas');
  // Ohne Fehler der IDE unverändert.
  mMerged := TAtlasIdeErrors.Merge([Finding(1, 0, 5, 'a')], nil);
  Assert.AreEqual(1, Integer(Length(mMerged)));
  Assert.IsFalse(mMerged[0].IdeConfirmed);
end;

procedure TAtlasIdeErrorsTests.EachIdeErrorConfirmsOnlyOneFinding;
var
  mMerged: TArray<TAtlasProblem>;
begin
  mMerged := TAtlasIdeErrors.Merge([Finding(1, 0, 5, 'a'), Finding(1, 2, 6, 'b')], [IdeError(1, 3, 4)]);
  Assert.AreEqual(2, Integer(Length(mMerged)));
  Assert.IsTrue(mMerged[0].IdeConfirmed);
  Assert.IsFalse(mMerged[1].IdeConfirmed, 'der eine Fehler der IDE ist schon vergeben');
end;

procedure TAtlasIdeErrorsTests.CompilerMessagesAreNeverConfirmed;
var
  mCompiler: TAtlasProblem;
  mMerged: TArray<TAtlasProblem>;
begin
  mCompiler := Finding(1, 0, 5, 'E2003');
  mCompiler.Source := TAtlasProblem.cCompilerSource;
  mMerged := TAtlasIdeErrors.Merge([mCompiler], [IdeError(1, 0, 5)]);
  Assert.AreEqual(2, Integer(Length(mMerged)));
  Assert.IsFalse(mMerged[0].IdeConfirmed or mMerged[1].IdeConfirmed);
  // Ein vom Build bestätigter Atlas-Befund zählt als Atlas.
  mCompiler.Source := TAtlasProblem.cConfirmedSource;
  mMerged := TAtlasIdeErrors.Merge([mCompiler], [IdeError(1, 0, 5)]);
  Assert.AreEqual(1, Integer(Length(mMerged)));
  Assert.IsTrue(mMerged[0].IdeConfirmed);
end;

procedure TAtlasIdeErrorsTests.OriginAndOriginText;
var
  mProblem: TAtlasProblem;
begin
  mProblem := Finding(1, 0, 1, 'a');
  Assert.AreEqual<TAtlasProblemOrigin>(TAtlasProblemOrigin.Atlas, TAtlasIdeErrors.OriginOf(mProblem));
  Assert.AreEqual('Atlas', TAtlasIdeErrors.OriginText(mProblem));
  mProblem.IdeConfirmed := True;
  Assert.AreEqual<TAtlasProblemOrigin>(TAtlasProblemOrigin.Both, TAtlasIdeErrors.OriginOf(mProblem));
  Assert.AreEqual('Atlas + IDE', TAtlasIdeErrors.OriginText(mProblem));
  mProblem := IdeError(1, 0, 1);
  Assert.AreEqual<TAtlasProblemOrigin>(TAtlasProblemOrigin.Ide, TAtlasIdeErrors.OriginOf(mProblem));
  Assert.AreEqual('IDE', TAtlasIdeErrors.OriginText(mProblem));
  mProblem.Source := 'DUnitX';
  Assert.AreEqual<TAtlasProblemOrigin>(TAtlasProblemOrigin.Other, TAtlasIdeErrors.OriginOf(mProblem));
  Assert.AreEqual('DUnitX', TAtlasIdeErrors.OriginText(mProblem));
end;

procedure TAtlasIdeErrorsTests.JournalLogsAtlasOnlyFalseAlarmsOnceWithoutNames;
var
  mJournal: TAtlasIdeErrorJournal;
  mConfirmed: TAtlasProblem;
  mLines: TArray<string>;
begin
  mConfirmed := Finding(4, 0, 3, 'unresolved-type');
  mConfirmed.IdeConfirmed := True;
  mJournal := TAtlasIdeErrorJournal.Create;
  try
    mLines := mJournal.NewLines(cFile, [Finding(1, 0, 3, 'Unresolved-Identifier'), Finding(2, 0, 3, 'unused-variable'),
      mConfirmed, Finding(5, 0, 3, 'unresolved-type', TAtlasProblemSeverity.Warning)]);
    Assert.AreEqual(2, Integer(Length(mLines)));
    Assert.AreEqual('Error Insight: Atlas only, rule unresolved-identifier, error, line 2', mLines[0]);
    Assert.AreEqual('Error Insight: Atlas only, rule unresolved-type, warning, line 6', mLines[1]);
    Assert.IsFalse(mLines[0].Contains('Kunde'), 'kein Dateiname');
    Assert.IsFalse(mLines[0].Contains('Kundennummer'), 'kein Bezeichner aus der Meldung');
    // Dieselbe Stelle nur einmal, eine neue Stelle wieder.
    mLines := mJournal.NewLines(cFile, [Finding(1, 0, 3, 'unresolved-identifier'),
      Finding(3, 0, 3, 'unresolved-attribute')]);
    Assert.AreEqual(1, Integer(Length(mLines)));
    Assert.AreEqual('Error Insight: Atlas only, rule unresolved-attribute, error, line 4', mLines[0]);
    mJournal.Clear;
    Assert.AreEqual(1, Integer(Length(mJournal.NewLines(cFile, [Finding(1, 0, 3, 'unresolved-identifier')]))));
  finally
    mJournal.Free;
  end;
  mLines := nil;
end;

procedure TAtlasIdeErrorsTests.StoreKeepsIdeErrorsOutOfForFile;
var
  mStore: TAtlasProblemStore;
  mWith: TArray<TAtlasProblem>;
  mStamp: Integer;
begin
  mStore := TAtlasProblemStore.Create;
  try
    // Ohne Eintrag der Datei geschieht nichts.
    mStore.SetIdeErrors(cFile, [IdeError(1, 0, 1)]);
    Assert.IsFalse(mStore.Contains(cFile));
    mStore.Update(cFile, cText, True, [Finding(1, 0, 5, 'unresolved-identifier')], '1', True);
    mStamp := mStore.Stamp(cFile);
    mStore.SetIdeErrors(cFile, [IdeError(1, 2, 3), IdeError(3, 0, 1)]);
    Assert.AreNotEqual(mStamp, mStore.Stamp(cFile), 'neuer Stand für das Fenster');
    Assert.AreEqual(1, Integer(Length(mStore.ForFile(cFile))), 'keine Wellenlinie für Fehler der IDE');
    Assert.IsFalse(mStore.ForFile(cFile)[0].IdeConfirmed);
    mWith := mStore.WithIde(cFile);
    Assert.AreEqual(2, Integer(Length(mWith)));
    Assert.IsTrue(mWith[0].IdeConfirmed);
    Assert.IsTrue(mWith[1].IsIde);
    // Eine neue Antwort des Servers lässt die Fehler der IDE stehen.
    mStore.Update(cFile, cText, True, [Finding(1, 0, 5, 'unresolved-identifier')], '2', True);
    Assert.AreEqual(2, Integer(Length(mStore.IdeErrors(cFile))));
    mStore.SetIdeErrors(cFile, nil);
    Assert.AreEqual(1, Integer(Length(mStore.WithIde(cFile))));
  finally
    mStore.Free;
  end;
end;

procedure TAtlasIdeErrorsTests.StoreDropsIdeErrorsInEditedLinesAndShiftsTheRest;
var
  mStore: TAtlasProblemStore;
  mIde: TArray<TAtlasProblem>;
begin
  mStore := TAtlasProblemStore.Create;
  try
    mStore.Update(cFile, cText, True, nil, '1', True);
    mStore.SetIdeErrors(cFile, [IdeError(0, 0, 1), IdeError(2, 0, 1), IdeError(4, 0, 1)]);
    // Zeile 2 ("b") geändert und eine Zeile davor eingefügt.
    mStore.Edit(cFile, 'unit Kunde;'#10'a'#10'neu'#10'bb'#10'c'#10'd'#10'e');
    mIde := mStore.IdeErrors(cFile);
    Assert.AreEqual(2, Integer(Length(mIde)), 'Fehler in der geänderten Stelle fallen weg');
    Assert.AreEqual(0, mIde[0].StartLine);
    Assert.AreEqual(5, mIde[1].StartLine, 'dahinter um die eingefügte Zeile verschoben');
  finally
    mStore.Free;
  end;
end;

procedure TAtlasIdeErrorsTests.ClearIdeErrorsChangesTheStamp;
var
  mStore: TAtlasProblemStore;
  mStamp, mVersion: Integer;
begin
  mStore := TAtlasProblemStore.Create;
  try
    mStore.Update(cFile, cText, True, nil, '1', True);
    mVersion := mStore.Version;
    mStore.ClearIdeErrors;
    Assert.AreEqual(mVersion, mStore.Version, 'ohne Fehler der IDE keine Änderung');
    mStore.SetIdeErrors(cFile, [IdeError(1, 0, 1)]);
    mStamp := mStore.Stamp(cFile);
    mStore.ClearIdeErrors;
    Assert.AreNotEqual(mStamp, mStore.Stamp(cFile));
    Assert.AreEqual(0, Integer(Length(mStore.IdeErrors(cFile))));
  finally
    mStore.Free;
  end;
end;

procedure TAtlasIdeErrorsTests.FindingsFilterBySource;
var
  mStore: TAtlasProblemStore;
  mFindings: TArray<TAtlasFinding>;
  mFilter: TAtlasFindingFilter;
  mCompiler: TAtlasProblem;
  mFinding: TAtlasFinding;
  mCounts: array[TAtlasProblemOrigin] of Integer;
begin
  mCompiler := Finding(5, 0, 1, 'E2010');
  mCompiler.Source := TAtlasProblem.cCompilerSource;
  mStore := TAtlasProblemStore.Create;
  try
    mStore.Update(cFile, cText, True, [Finding(1, 0, 5, 'unresolved-identifier'), Finding(3, 0, 5, 'b'), mCompiler],
      '1', True);
    mStore.SetIdeErrors(cFile, [IdeError(1, 2, 3), IdeError(2, 0, 1)]);
    mFindings := TAtlasFindings.FromStore(mStore, nil, nil);
    Assert.AreEqual(4, Integer(Length(mFindings)));
    FillChar(mCounts, SizeOf(mCounts), 0);
    for mFinding in mFindings do
    begin
      Inc(mCounts[TAtlasIdeErrors.OriginOf(mFinding.Problem)]);
    end;
    Assert.AreEqual(1, mCounts[TAtlasProblemOrigin.Both]);
    Assert.AreEqual(1, mCounts[TAtlasProblemOrigin.Atlas]);
    Assert.AreEqual(1, mCounts[TAtlasProblemOrigin.Ide]);
    Assert.AreEqual(1, mCounts[TAtlasProblemOrigin.Other]);
    mFilter := TAtlasFindingFilter.Create;
    mFilter.Compiler := True;
    Assert.AreEqual<TAtlasFindingOrigin>(TAtlasFindingOrigin.All, mFilter.Origin, 'Vorgabe: Atlas und IDE');
    for mFinding in mFindings do
    begin
      Assert.IsTrue(mFilter.Matches(mFinding));
    end;
    mFilter.Origin := TAtlasFindingOrigin.AtlasOnly;
    for mFinding in mFindings do
    begin
      Assert.AreEqual(TAtlasIdeErrors.OriginOf(mFinding.Problem) = TAtlasProblemOrigin.Atlas, mFilter.Matches(mFinding),
        mFinding.SourceText);
    end;
    mFilter.Origin := TAtlasFindingOrigin.IdeOnly;
    for mFinding in mFindings do
    begin
      Assert.AreEqual(mFinding.Problem.IsIde, mFilter.Matches(mFinding), mFinding.SourceText);
    end;
  finally
    mStore.Free;
  end;
  mFindings := nil;
end;

procedure TAtlasIdeErrorsTests.MergeOfManyFindingsStaysFast;
var
  mAtlas, mIde, mMerged: TArray<TAtlasProblem>;
  mIndex: Integer;
  mWatch: TStopwatch;
begin
  SetLength(mAtlas, 5000);
  for mIndex := 0 to High(mAtlas) do
  begin
    mAtlas[mIndex] := Finding(mIndex * 2, 0, 5, 'unresolved-identifier');
  end;
  SetLength(mIde, 500);
  for mIndex := 0 to High(mIde) do
  begin
    mIde[mIndex] := IdeError(mIndex * 4, 1, 2);
  end;
  mWatch := TStopwatch.StartNew;
  mMerged := TAtlasIdeErrors.Merge(mAtlas, mIde);
  mWatch.Stop;
  Assert.AreEqual(5000, Integer(Length(mMerged)), 'jeder Fehler der IDE bestätigt einen Befund');
  Assert.IsTrue(mWatch.ElapsedMilliseconds < 2000, Format('%d ms', [mWatch.ElapsedMilliseconds]));
  mAtlas := nil;
  mIde := nil;
  mMerged := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIdeErrorsTests);

end.
