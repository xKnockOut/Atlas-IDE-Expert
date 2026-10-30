unit Atlas.Common.Rules.BulkFix.Tests;

// Tests für die Sammelkorrektur (#1352): Auswahl sicherer Korrekturen
// (Konfidenz, safeFix, Auswahl, andere Dateien), Reihenfolge und Konflikte
// überlappender Korrekturen, mehrere Durchgänge, Verwerfen bei neuen
// Syntaxfehlern, Zeilentabelle, Schreiben mit Zurücksetzen, Zusammenfassung
// und das Zusammenspiel mit den eingebauten Regeln.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TBulkFixTests = class
  public
    [Test]
    procedure OptionsReadAllAndRules;
    [Test]
    procedure SafeFixNeedsConfidence;
    [Test]
    procedure SafeFixNeedsCatalogFlag;
    [Test]
    procedure SafeFixRejectsChoiceAndOtherFiles;
    [Test]
    procedure SafeFixWithoutTextChangeIsNoFix;
    [Test]
    procedure AppliesBackToFront;
    [Test]
    procedure OverlappingFixWaitsForNextPass;
    [Test]
    procedure ConflictAfterLastPassIsCounted;
    [Test]
    procedure SkippedCountsOnlyFirstPass;
    [Test]
    procedure MediumConfidenceSkippedUnlessAllowed;
    [Test]
    procedure RejectsNewSyntaxErrors;
    [Test]
    procedure UnchangedTextIsNotChanged;
    [Test]
    procedure OverlapsTouchingAndSameStart;
    [Test]
    procedure LineMapAfterDeletedLine;
    [Test]
    procedure LineMapAfterInsertedLine;
    [Test]
    procedure LineMapFollowsSecondPass;
    [Test]
    procedure WriteAllRollsBackOnError;
    [Test]
    procedure WriteAllWritesOnlyChangedFiles;
    [Test]
    procedure SummaryListsRulesAndSkips;
    [Test]
    procedure DiffHasHeadersAndHunk;
    [Test]
    procedure MinConfidenceOnlyRaises;
    [Test]
    procedure RulesForSubsetAndAll;
    [Test]
    procedure SafeRulesComeFromCatalog;
    [Test]
    procedure SafeFixRulesExist;
    [Test]
    procedure BuiltinRedundantAssignedFree;
    [Test]
    procedure BuiltinDestroyAndResume;
    [Test]
    procedure BuiltinUnusedSuppression;
    [Test]
    procedure BuiltinUnsafeFixStays;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.BulkFix;

const
  cRule = 'x-rule';

function Options(AMin: TRuleConfidence): TBulkFixOptions;
begin
  Result := Default(TBulkFixOptions);
  Result.Rules := TArray<string>.Create(cRule);
  Result.MinConfidence := AMin;
  Result.SafeRules := TArray<string>.Create(cRule);
end;

function Finding(ALine, AStart, AEnd: Integer; const ANewText: string; AConfidence: TRuleConfidence;
  ASafe: Boolean): TRuleFinding;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := cRule;
  Result.Range := TTextRange.Create(ALine, AStart, ALine, AEnd);
  Result.Confidence := AConfidence;
  Result.Fixes := TArray<TRuleFix>.Create(TRuleFix.Create('Ersetzen',
    TArray<TRuleEdit>.Create(TRuleEdit.Create(Result.Range, ANewText)), ASafe));
end;

function NoErrors: TBulkFixSyntaxErrors;
begin
  Result :=
    function(const AText: string): Integer
    begin
      Result := 0;
    end;
end;

/// <summary>Jedes "XX" im Text wird zu "X" (Treffer überlappen sich bei "XXX").</summary>
function DoubleXCheck: TBulkFixCheck;
begin
  Result :=
    function(const AText: string; const ALines: TBulkFixLineMap): TArray<TRuleFinding>
    var
      mIndex: Integer;
    begin
      Result := nil;
      for mIndex := 1 to Length(AText) - 1 do
        if (AText[mIndex] = 'X') and (AText[mIndex + 1] = 'X') then
          Result := Result + [Finding(0, mIndex - 1, mIndex + 1, 'X', TRuleConfidence.High, True)];
    end;
end;

/// <summary>Wie DoubleXCheck, dazu in jedem Durchgang ein Treffer mit niedriger Konfidenz.</summary>
function DoubleXWithLowCheck: TBulkFixCheck;
var
  mDouble: TBulkFixCheck;
begin
  mDouble := DoubleXCheck();
  Result :=
    function(const AText: string; const ALines: TBulkFixLineMap): TArray<TRuleFinding>
    begin
      Result := mDouble(AText, ALines) + [Finding(0, 0, 0, 'y', TRuleConfidence.Low, True)];
    end;
end;

function FixedCheck(const AFindings: TArray<TRuleFinding>): TBulkFixCheck;
begin
  Result :=
    function(const AText: string; const ALines: TBulkFixLineMap): TArray<TRuleFinding>
    begin
      Result := AFindings;
    end;
end;

function Builtin(const AText: string; const ARules: TArray<string>): TBulkFixFile;
var
  mSettings: TServerSettings;
begin
  mSettings := TServerSettings.Default;
  Result := TBulkFix.Run('U.pas', AText, TBulkFixOptions.Create(ARules, mSettings.FixMinConfidence,
    TRuleCatalog.Shared.Entries), TBulkFix.CheckWith(TBulkFix.RulesFor(BuiltinRules, ARules), mSettings, 'U.pas',
    Default(TCheckProject), TCheckSource.Default), TBulkFix.SyntaxErrorsWith(TCheckSource.Default));
end;

function Remaining(const AText, ARule: string): Integer;
var
  mFinding: TRuleFinding;
begin
  Result := 0;
  for mFinding in TFileChecker.CheckText(BuiltinRules, TServerSettings.Default, 'U.pas', AText) do
    if SameText(mFinding.RuleId, ARule) then
      Inc(Result);
end;

const
  cUnitHead = 'unit U;'#13#10#13#10'interface'#13#10#13#10'uses'#13#10'  System.Classes;'#13#10#13#10 +
    'implementation'#13#10#13#10;

procedure TBulkFixTests.OptionsReadAllAndRules;
var
  mOptions: TBulkFixOptions;
begin
  mOptions := TBulkFixOptions.Create(TArray<string>.Create(' Redundant-Cast ', '', 'unused-uses'),
    TRuleConfidence.High, nil);
  Assert.IsFalse(mOptions.All);
  Assert.AreEqual('redundant-cast,unused-uses', string.Join(',', mOptions.Rules));
  Assert.IsTrue(mOptions.Wants('REDUNDANT-CAST'));
  Assert.IsFalse(mOptions.Wants('empty-except'));
  mOptions := TBulkFixOptions.Create(TArray<string>.Create('all'), TRuleConfidence.High, nil);
  Assert.IsTrue(mOptions.All);
  Assert.IsTrue(mOptions.Wants('empty-except'));
end;

procedure TBulkFixTests.SafeFixNeedsConfidence;
var
  mFix: TRuleFix;
  mSkip: TBulkFixSkip;
begin
  Assert.IsFalse(TBulkFix.SafeFixOf(Finding(0, 0, 1, 'a', TRuleConfidence.Medium, True),
    Options(TRuleConfidence.High), mFix, mSkip));
  Assert.AreEqual(Ord(TBulkFixSkip.Confidence), Ord(mSkip));
  Assert.IsTrue(TBulkFix.SafeFixOf(Finding(0, 0, 1, 'a', TRuleConfidence.Medium, True),
    Options(TRuleConfidence.Medium), mFix, mSkip));
  Assert.AreEqual('Ersetzen', mFix.Title);
end;

procedure TBulkFixTests.SafeFixNeedsCatalogFlag;
var
  mFix: TRuleFix;
  mSkip: TBulkFixSkip;
  mOptions: TBulkFixOptions;
begin
  mOptions := Options(TRuleConfidence.High);
  mOptions.SafeRules := nil;
  Assert.IsFalse(TBulkFix.SafeFixOf(Finding(0, 0, 1, 'a', TRuleConfidence.High, True), mOptions, mFix, mSkip));
  Assert.AreEqual(Ord(TBulkFixSkip.Unsafe), Ord(mSkip));
  // Die Korrektur selbst muss auch als sicher markiert sein.
  Assert.IsFalse(TBulkFix.SafeFixOf(Finding(0, 0, 1, 'a', TRuleConfidence.High, False),
    Options(TRuleConfidence.High), mFix, mSkip));
  Assert.AreEqual(Ord(TBulkFixSkip.Unsafe), Ord(mSkip));
end;

procedure TBulkFixTests.SafeFixRejectsChoiceAndOtherFiles;
var
  mFinding: TRuleFinding;
  mFix: TRuleFix;
  mSkip: TBulkFixSkip;
begin
  // Zwei Korrekturen: Auswahl, nie sicher.
  mFinding := Finding(0, 0, 1, 'a', TRuleConfidence.High, True);
  mFinding.Fixes := mFinding.Fixes + mFinding.Fixes;
  Assert.IsFalse(TBulkFix.SafeFixOf(mFinding, Options(TRuleConfidence.High), mFix, mSkip));
  Assert.AreEqual(Ord(TBulkFixSkip.Unsafe), Ord(mSkip));
  mFinding := Finding(0, 0, 1, 'a', TRuleConfidence.High, True);
  mFinding.Fixes[0].Alternative := True;
  Assert.IsFalse(TBulkFix.SafeFixOf(mFinding, Options(TRuleConfidence.High), mFix, mSkip));
  mFinding := Finding(0, 0, 1, 'a', TRuleConfidence.High, True);
  mFinding.Fixes[0].FileName := 'U.dfm';
  Assert.IsFalse(TBulkFix.SafeFixOf(mFinding, Options(TRuleConfidence.High), mFix, mSkip));
  mFinding := Finding(0, 0, 1, 'a', TRuleConfidence.High, True);
  SetLength(mFinding.Fixes[0].OtherFiles, 1);
  Assert.IsFalse(TBulkFix.SafeFixOf(mFinding, Options(TRuleConfidence.High), mFix, mSkip));
  Assert.AreEqual(Ord(TBulkFixSkip.Unsafe), Ord(mSkip));
end;

procedure TBulkFixTests.SafeFixWithoutTextChangeIsNoFix;
var
  mFinding: TRuleFinding;
  mFix: TRuleFix;
  mSkip: TBulkFixSkip;
begin
  mFinding := Finding(0, 0, 1, 'a', TRuleConfidence.High, True);
  mFinding.Fixes := TArray<TRuleFix>.Create(TRuleFix.Jump('Hin', TTextPosition.Create(0, 0)));
  Assert.IsFalse(TBulkFix.SafeFixOf(mFinding, Options(TRuleConfidence.High), mFix, mSkip));
  Assert.AreEqual(Ord(TBulkFixSkip.NoFix), Ord(mSkip));
  // Ein Sprung neben der einen Änderung macht sie nicht zur Auswahl.
  mFinding := Finding(0, 0, 1, 'a', TRuleConfidence.High, True);
  mFinding.Fixes := mFinding.Fixes + [TRuleFix.Jump('Hin', TTextPosition.Create(0, 0))];
  Assert.IsTrue(TBulkFix.SafeFixOf(mFinding, Options(TRuleConfidence.High), mFix, mSkip));
end;

procedure TBulkFixTests.AppliesBackToFront;
var
  mResult: TBulkFixFile;
begin
  mResult := TBulkFix.Run('U.pas', 'aaa bbb ccc', Options(TRuleConfidence.High), FixedCheck(
    TArray<TRuleFinding>.Create(Finding(0, 0, 3, 'A', TRuleConfidence.High, True),
    Finding(0, 8, 11, 'CCCC', TRuleConfidence.High, True), Finding(0, 4, 7, 'B', TRuleConfidence.High, True))),
    NoErrors());
  Assert.AreEqual('A B CCCC', mResult.NewText);
  Assert.IsTrue(mResult.Changed);
  Assert.AreEqual(3, mResult.FixCount);
  Assert.AreEqual(1, mResult.Passes);
  Assert.AreEqual(cRule, mResult.Applied[0].RuleId);
end;

procedure TBulkFixTests.OverlappingFixWaitsForNextPass;
var
  mResult: TBulkFixFile;
begin
  // "XXXX": XX an 0, 1, 2; von hinten genommen wird 2, 0 passt daneben, 1 überlappt und wartet.
  mResult := TBulkFix.Run('U.pas', 'XXXX', Options(TRuleConfidence.High), DoubleXCheck(), NoErrors());
  Assert.AreEqual('X', mResult.NewText);
  Assert.AreEqual(2, mResult.Passes);
  Assert.AreEqual(3, mResult.FixCount);
  Assert.AreEqual(0, mResult.Skipped[TBulkFixSkip.Conflict]);
end;

procedure TBulkFixTests.ConflictAfterLastPassIsCounted;
var
  mResult: TBulkFixFile;
begin
  // Dieselben überlappenden Treffer in jedem Durchgang: einer wird genommen, einer wartet bis zum Ende.
  mResult := TBulkFix.Run('U.pas', 'abcd', Options(TRuleConfidence.High), FixedCheck(
    TArray<TRuleFinding>.Create(Finding(0, 0, 2, 'ab', TRuleConfidence.High, True),
    Finding(0, 1, 3, 'bc', TRuleConfidence.High, True))), NoErrors());
  Assert.AreEqual(TBulkFix.MaxPasses, mResult.Passes);
  Assert.AreEqual(1, mResult.Skipped[TBulkFixSkip.Conflict]);
  Assert.IsFalse(mResult.Changed);
end;

procedure TBulkFixTests.SkippedCountsOnlyFirstPass;
var
  mResult: TBulkFixFile;
begin
  mResult := TBulkFix.Run('U.pas', 'XXX', Options(TRuleConfidence.High), DoubleXWithLowCheck(), NoErrors());
  Assert.AreEqual('X', mResult.NewText);
  Assert.AreEqual(2, mResult.Passes);
  Assert.AreEqual(1, mResult.Skipped[TBulkFixSkip.Confidence]);
end;

procedure TBulkFixTests.MediumConfidenceSkippedUnlessAllowed;
var
  mFindings: TArray<TRuleFinding>;
  mResult: TBulkFixFile;
begin
  mFindings := TArray<TRuleFinding>.Create(Finding(0, 0, 1, 'A', TRuleConfidence.Medium, True),
    Finding(0, 2, 3, 'B', TRuleConfidence.High, True));
  mResult := TBulkFix.Run('U.pas', 'a b', Options(TRuleConfidence.High), FixedCheck(mFindings), NoErrors());
  Assert.AreEqual('a B', mResult.NewText);
  Assert.AreEqual(1, mResult.Skipped[TBulkFixSkip.Confidence]);
  mResult := TBulkFix.Run('U.pas', 'a b', Options(TRuleConfidence.Medium), FixedCheck(mFindings), NoErrors());
  Assert.AreEqual('A B', mResult.NewText);
  Assert.AreEqual(0, mResult.Skipped[TBulkFixSkip.Confidence]);
end;

procedure TBulkFixTests.RejectsNewSyntaxErrors;
var
  mResult: TBulkFixFile;
begin
  mResult := TBulkFix.Run('U.pas', 'a!b', Options(TRuleConfidence.High), FixedCheck(
    TArray<TRuleFinding>.Create(Finding(0, 0, 1, '!', TRuleConfidence.High, True))),
    function(const AText: string): Integer
    var
      mChar: Char;
    begin
      Result := 0;
      for mChar in AText do
        if mChar = '!' then
          Inc(Result);
    end);
  Assert.IsTrue(mResult.Rejected);
  Assert.IsFalse(mResult.Changed);
  Assert.AreEqual('a!b', mResult.NewText);
  Assert.Contains(TBulkFix.Summary(TArray<TBulkFixFile>.Create(mResult), False, #10), 'Verworfen');
end;

procedure TBulkFixTests.UnchangedTextIsNotChanged;
var
  mResult: TBulkFixFile;
begin
  mResult := TBulkFix.Run('U.pas', 'abc', Options(TRuleConfidence.High), FixedCheck(nil), NoErrors());
  Assert.IsFalse(mResult.Changed);
  Assert.AreEqual(0, mResult.Passes);
  Assert.AreEqual('', TBulkFix.Diff('U.pas', mResult));
end;

procedure TBulkFixTests.OverlapsTouchingAndSameStart;
begin
  Assert.IsFalse(TBulkFix.Overlaps(TTextRange.Create(0, 0, 0, 2), TTextRange.Create(0, 2, 0, 4)));
  Assert.IsTrue(TBulkFix.Overlaps(TTextRange.Create(0, 0, 0, 3), TTextRange.Create(0, 2, 0, 4)));
  Assert.IsTrue(TBulkFix.Overlaps(TTextRange.Create(0, 2, 0, 2), TTextRange.Create(0, 2, 0, 2)));
  Assert.IsTrue(TBulkFix.Overlaps(TTextRange.Create(1, 0, 3, 0), TTextRange.Create(2, 5, 2, 6)));
end;

procedure TBulkFixTests.LineMapAfterDeletedLine;
var
  mMap: TBulkFixLineMap;
begin
  mMap := TBulkFixLineMap.Identity.After(4, TArray<TTextEdit>.Create(TTextEdit.Create(
    TTextRange.Create(1, 0, 2, 0), '')));
  Assert.AreEqual(0, mMap.Original(0));
  Assert.AreEqual(2, mMap.Original(1));
  Assert.AreEqual(3, mMap.Original(2));
end;

procedure TBulkFixTests.LineMapAfterInsertedLine;
var
  mMap: TBulkFixLineMap;
begin
  mMap := TBulkFixLineMap.Identity.After(4, TArray<TTextEdit>.Create(TTextEdit.Create(
    TTextRange.Create(1, 0, 1, 0), 'neu'#10)));
  Assert.AreEqual(0, mMap.Original(0));
  Assert.AreEqual(1, mMap.Original(1));
  Assert.AreEqual(1, mMap.Original(2));
  Assert.AreEqual(2, mMap.Original(3));
  Assert.AreEqual(3, mMap.Original(4));
end;

procedure TBulkFixTests.LineMapFollowsSecondPass;
var
  mSeen: TList<Integer>;
  mResult: TBulkFixFile;
begin
  // Zweiter Durchgang: Zeile 2 des geänderten Texts ist Zeile 3 des Ausgangstexts.
  mSeen := TList<Integer>.Create;
  try
    mResult := TBulkFix.Run('U.pas', 'weg'#10'a'#10'XXX'#10'b', Options(TRuleConfidence.High),
      function(const AText: string; const ALines: TBulkFixLineMap): TArray<TRuleFinding>
      var
        mLines: TArray<string>;
        mLine, mIndex: Integer;
      begin
        Result := nil;
        mLines := AText.Split([#10]);
        for mLine := 0 to High(mLines) do
        begin
          if mLines[mLine] = 'weg' then
          begin
            Result := Result + [Finding(mLine, 0, 0, '', TRuleConfidence.High, True)];
            Result[High(Result)].Fixes[0].Edits[0].Range := TTextRange.Create(mLine, 0, mLine + 1, 0);
            Continue;
          end;
          for mIndex := 1 to Length(mLines[mLine]) - 1 do
            if (mLines[mLine][mIndex] = 'X') and (mLines[mLine][mIndex + 1] = 'X') then
            begin
              mSeen.Add(ALines.Original(mLine));
              Result := Result + [Finding(mLine, mIndex - 1, mIndex + 1, 'X', TRuleConfidence.High, True)];
            end;
        end;
      end, NoErrors());
    Assert.AreEqual('a'#10'X'#10'b', mResult.NewText);
    Assert.IsTrue(mSeen.Count >= 3);
    Assert.AreEqual(2, mSeen[mSeen.Count - 1], 'Treffer im zweiten Durchgang auf Zeile 2 des Ausgangstexts');
    Assert.AreEqual(2, mResult.Lines.Original(1));
  finally
    mSeen.Free;
  end;
end;

procedure TBulkFixTests.WriteAllRollsBackOnError;
var
  mLog: TList<string>;
  mFiles: TArray<TBulkFixFile>;
  mFile: TBulkFixFile;
begin
  mFiles := nil;
  mFile := Default(TBulkFixFile);
  mFile.FileName := 'A.pas';
  mFile.OldText := 'alt A';
  mFile.NewText := 'neu A';
  mFiles := mFiles + [mFile];
  mFile.FileName := 'B.pas';
  mFile.OldText := 'alt B';
  mFile.NewText := 'neu B';
  mFiles := mFiles + [mFile];
  mLog := TList<string>.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        TBulkFix.WriteAll(mFiles,
          procedure(const AFileName, AText: string)
          begin
            if AFileName = 'B.pas' then
              raise EInOutError.Create('gesperrt');
            mLog.Add(AFileName + '=' + AText);
          end);
      end, EBulkFixWrite);
    Assert.AreEqual('A.pas=neu A|A.pas=alt A', string.Join('|', mLog.ToArray));
  finally
    mLog.Free;
  end;
end;

procedure TBulkFixTests.WriteAllWritesOnlyChangedFiles;
var
  mFiles: TArray<TBulkFixFile>;
  mFile: TBulkFixFile;
  mNames: string;
begin
  mFile := Default(TBulkFixFile);
  mFile.FileName := 'Gleich.pas';
  mFile.OldText := 'x';
  mFile.NewText := 'x';
  mFiles := TArray<TBulkFixFile>.Create(mFile);
  mFile.FileName := 'Verworfen.pas';
  mFile.NewText := 'y';
  mFile.Rejected := True;
  mFiles := mFiles + [mFile];
  mFile.FileName := 'Neu.pas';
  mFile.Rejected := False;
  mFiles := mFiles + [mFile];
  mNames := '';
  Assert.AreEqual(1, TBulkFix.WriteAll(mFiles,
    procedure(const AFileName, AText: string)
    begin
      mNames := mNames + AFileName;
    end));
  Assert.AreEqual('Neu.pas', mNames);
end;

procedure TBulkFixTests.SummaryListsRulesAndSkips;
var
  mFile: TBulkFixFile;
  mText: string;
begin
  mFile := Default(TBulkFixFile);
  mFile.FileName := 'U.pas';
  mFile.OldText := 'a';
  mFile.NewText := 'b';
  SetLength(mFile.Applied, 2);
  mFile.Applied[0].RuleId := 'unused-uses';
  mFile.Applied[0].Count := 2;
  mFile.Applied[1].RuleId := 'redundant-cast';
  mFile.Applied[1].Count := 1;
  mFile.Skipped[TBulkFixSkip.Confidence] := 4;
  mFile.Skipped[TBulkFixSkip.Unsafe] := 1;
  mText := TBulkFix.Summary(TArray<TBulkFixFile>.Create(mFile), True, '|');
  Assert.AreEqual('Vorschau: 3 Korrekturen in 1 Dateien, nichts geschrieben|  redundant-cast: 1|  unused-uses: 2|' +
    'Übersprungen: 4 mit zu niedriger Konfidenz, 1 unsicher, 0 Konflikt, 0 ohne Korrektur', mText);
  Assert.StartsWith('3 Korrekturen in 1 Dateien geschrieben',
    TBulkFix.Summary(TArray<TBulkFixFile>.Create(mFile), False, '|'));
end;

procedure TBulkFixTests.DiffHasHeadersAndHunk;
var
  mFile: TBulkFixFile;
  mDiff: string;
begin
  mFile := Default(TBulkFixFile);
  mFile.OldText := 'a'#13#10'b'#13#10'c';
  mFile.NewText := 'a'#13#10'B'#13#10'c';
  mDiff := TBulkFix.Diff('Source/U.pas', mFile);
  Assert.StartsWith('--- a/Source/U.pas' + sLineBreak + '+++ b/Source/U.pas' + sLineBreak + '@@ -1,3 +1,3 @@',
    mDiff);
  Assert.IsTrue(Pos(sLineBreak + '-b' + sLineBreak + '+B' + sLineBreak, mDiff) > 0, mDiff);
end;

procedure TBulkFixTests.MinConfidenceOnlyRaises;
var
  mConfidence: TRuleConfidence;
  mError: string;
begin
  Assert.IsTrue(TBulkFix.MinConfidenceOf(TRuleConfidence.High, '', mConfidence, mError));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mConfidence));
  Assert.IsFalse(TBulkFix.MinConfidenceOf(TRuleConfidence.High, 'medium', mConfidence, mError));
  Assert.IsTrue(Pos('fix.minConfidence', mError) > 0, mError);
  Assert.IsTrue(TBulkFix.MinConfidenceOf(TRuleConfidence.Medium, 'high', mConfidence, mError));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mConfidence));
  Assert.IsFalse(TBulkFix.MinConfidenceOf(TRuleConfidence.Medium, 'low', mConfidence, mError));
  Assert.IsFalse(TBulkFix.MinConfidenceOf(TRuleConfidence.Medium, 'sicher', mConfidence, mError));
end;

procedure TBulkFixTests.RulesForSubsetAndAll;
var
  mAll, mRules: TArray<IRule>;
begin
  mAll := BuiltinRules;
  mRules := TBulkFix.RulesFor(mAll, TArray<string>.Create('redundant-cast'));
  Assert.AreEqual(1, Integer(Length(mRules)));
  Assert.AreEqual('redundant-cast', mRules[0].Descriptor.Id);
  Assert.AreEqual(Integer(Length(mAll)), Integer(Length(TBulkFix.RulesFor(mAll, TArray<string>.Create('all')))));
  // syntax entsteht im Checker, unused-suppression in der Engine: dafür alle Regeln.
  Assert.AreEqual(Integer(Length(mAll)), Integer(Length(TBulkFix.RulesFor(mAll,
    TArray<string>.Create('unused-suppression')))));
end;

procedure TBulkFixTests.SafeRulesComeFromCatalog;
var
  mSafe: TArray<string>;
begin
  mSafe := TBulkFix.SafeRulesOf(TRuleCatalog.Shared.Entries);
  Assert.IsTrue(IndexText('redundant-cast', mSafe) >= 0);
  Assert.IsTrue(IndexText('unused-uses', mSafe) >= 0);
  Assert.IsFalse(IndexText('empty-except', mSafe) >= 0);
end;

procedure TBulkFixTests.SafeFixRulesExist;
var
  mEntry: TRuleCatalogEntry;
  mRule: IRule;
  mKnown: Boolean;
begin
  // safeFix nur bei Regeln, die es gibt (eingebaut, im Checker oder in der Engine).
  for mEntry in TRuleCatalog.Shared.Entries do
    if mEntry.SafeFix then
    begin
      mKnown := MatchText(mEntry.Id, ['syntax', 'unused-suppression', 'unknown-rule-id']);
      for mRule in BuiltinRules do
        if SameText(mRule.Descriptor.Id, mEntry.Id) then
          mKnown := True;
      Assert.IsTrue(mKnown, mEntry.Id);
    end;
end;

procedure TBulkFixTests.BuiltinRedundantAssignedFree;
var
  mText: string;
  mResult: TBulkFixFile;
begin
  mText := cUnitHead + 'procedure Weg(AList: TStringList);'#13#10'begin'#13#10'  if Assigned(AList) then'#13#10 +
    '    AList.Free;'#13#10'end;'#13#10#13#10'end.'#13#10;
  mResult := Builtin(mText, TArray<string>.Create('redundant-assigned-free'));
  Assert.AreEqual(1, mResult.FixCount, mResult.NewText);
  Assert.AreEqual(0, Remaining(mResult.NewText, 'redundant-assigned-free'), mResult.NewText);
  Assert.IsTrue(Pos('AList.Free;', mResult.NewText) > 0, mResult.NewText);
  Assert.IsFalse(Pos('Assigned', mResult.NewText) > 0, mResult.NewText);
end;

procedure TBulkFixTests.BuiltinDestroyAndResume;
var
  mText: string;
  mResult: TBulkFixFile;
begin
  mText := cUnitHead + 'procedure Weg(AList: TStringList; AThread: TThread);'#13#10'begin'#13#10 +
    '  AThread.Resume;'#13#10'  AList.Destroy;'#13#10'end;'#13#10#13#10'end.'#13#10;
  mResult := Builtin(mText, TArray<string>.Create('destroy-called-directly', 'thread-resume-suspend'));
  Assert.AreEqual(2, mResult.FixCount, mResult.NewText);
  Assert.IsTrue(Pos('AThread.Start;', mResult.NewText) > 0, mResult.NewText);
  Assert.IsTrue(Pos('AList.Free;', mResult.NewText) > 0, mResult.NewText);
  Assert.AreEqual(0, Remaining(mResult.NewText, 'destroy-called-directly'));
  Assert.AreEqual(0, Remaining(mResult.NewText, 'thread-resume-suspend'));
end;

procedure TBulkFixTests.BuiltinUnusedSuppression;
var
  mText: string;
  mResult: TBulkFixFile;
begin
  mText := cUnitHead + 'procedure Tu;'#13#10'var'#13#10'  X: Integer;'#13#10'begin'#13#10 +
    '  X := 1; // lsp-ignore: empty-except'#13#10'  if X = 1 then'#13#10'    X := 2;'#13#10'end;'#13#10#13#10 +
    'end.'#13#10;
  mResult := Builtin(mText, TArray<string>.Create('unused-suppression'));
  Assert.AreEqual(1, mResult.FixCount, mResult.NewText);
  Assert.IsFalse(Pos('lsp-ignore', mResult.NewText) > 0, mResult.NewText);
  Assert.AreEqual(0, Remaining(mResult.NewText, 'unused-suppression'));
end;

procedure TBulkFixTests.BuiltinUnsafeFixStays;
var
  mText: string;
  mResult: TBulkFixFile;
begin
  // empty-except hat keine sichere Korrektur und steht nicht mit safeFix im Katalog.
  mText := cUnitHead + 'procedure Tu;'#13#10'begin'#13#10'  try'#13#10'    Tu;'#13#10'  except'#13#10'  end;'#13#10 +
    'end;'#13#10#13#10'end.'#13#10;
  mResult := Builtin(mText, TArray<string>.Create('empty-except'));
  Assert.IsFalse(mResult.Changed);
  Assert.AreEqual(0, mResult.FixCount);
end;

initialization
  TDUnitX.RegisterTestFixture(TBulkFixTests);

end.
