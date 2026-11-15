unit Atlas.Core.Editor.InlayPlan.Tests;

// Entscheidungen der Inlay-Hints (Atlas.Core.Editor.InlayPlan): Abruf, Marken einer Zeile, Arten und Ausblenden,
// Zeilenvergleich und klickbare Marken.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInlayHintsPlanTests = class
  public
    [Test]
    procedure SourcesArePascalFiles;
    [Test]
    procedure FetchWaitsForQuietAndRetry;
    [Test]
    procedure VisibleLinesFromTopRow;
    [Test]
    procedure StoredLineCollectsKindsInOrder;
    [Test]
    procedure StoredLineWithoutHints;
    [Test]
    procedure KeepShownDropsKindsThatAreOff;
    [Test]
    procedure KeepShownAsksHiddenPerKind;
    [Test]
    procedure SameLineIgnoresTabsAndTrailingBlanks;
    [Test]
    procedure ColumnsResolveTabs;
    [Test]
    procedure FontSizeOnePointSmaller;
    [Test]
    procedure OnlyPlainLeftClickCounts;
    [Test]
    procedure HitStillShownByKind;
  end;

  [TestFixture]
  TInlayPillHitsTests = class
  public
    [Test]
    procedure RememberReplacesSameLineAndKind;
    [Test]
    procedure RememberForgetsAllWhenFull;
    [Test]
    procedure FindNeedsFileTopRowPointAndShown;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Atlas.Core.InlayHints.Store,
  Atlas.Core.Editor.InlayPlan;

function H(ALine, ACharacter: Integer; const AName: string): TAtlasInlayHint;
begin
  Result := Default(TAtlasInlayHint);
  Result.Line := ALine;
  Result.Character := ACharacter;
  Result.Name := AName;
end;

function Texts: TAtlasInlayTexts;
begin
  Result.MethodWithoutSelf := 'no Self';
  Result.DefineFormat := 'defines %s';
end;

function Hit(const AFileName: string; ALine: Integer; AActions: Boolean): TAtlasInlayPillHit;
begin
  Result := Default(TAtlasInlayPillHit);
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.TopRow := 1;
  Result.Rect := TRect.Create(10, 20, 50, 36);
  Result.Actions := AActions;
end;

function Kinds(const AHints: TAtlasInlayLine): string;
var
  mRow: TAtlasInlayPillRow;
begin
  Result := '';
  for mRow in AHints.Rows do
  begin
    Result := Result + IntToStr(Ord(mRow.Kind)) + '=' + string.Join(',', mRow.Labels) + ';';
  end;
end;

/// <summary>Zeile 1 mit Include-Symbol, Zeile 2 mit Methode ohne Self und Endmarke.</summary>
procedure Fill(AStore: TAtlasInlayHintStore);
var
  mText: string;
  mHints: TArray<TAtlasInlayHint>;
begin
  mText := 'unit U;' + sLineBreak + '{$I JVCL.INC}' + sLineBreak + 'function TA.Mal(N: Integer): Integer;' +
    sLineBreak + 'end;';
  mHints := [H(1, 13, 'COMPLIB_VCL'), H(2, 37, 'x'), H(3, 4, 'TA.Mal')];
  mHints[0].DefineHint := True;
  mHints[1].MethodHint := True;
  mHints[2].EndLabel := True;
  AStore.SetText('A.pas', mText);
  AStore.Put('A.pas', mText, 0, 4, mHints);
end;

{ TInlayHintsPlanTests }

procedure TInlayHintsPlanTests.SourcesArePascalFiles;
begin
  Assert.IsTrue(TAtlasInlayPlan.IsSource('C:\P\Main.PAS'));
  Assert.IsTrue(TAtlasInlayPlan.IsSource('P.dpr'));
  Assert.IsTrue(TAtlasInlayPlan.IsSource('P.dpk'));
  Assert.IsTrue(TAtlasInlayPlan.IsSource('jedi.inc'));
  Assert.IsFalse(TAtlasInlayPlan.IsSource('Main.dfm'));
  Assert.IsFalse(TAtlasInlayPlan.IsSource('P.dproj'));
end;

procedure TInlayHintsPlanTests.FetchWaitsForQuietAndRetry;
begin
  Assert.IsTrue(TAtlasInlayPlan.FetchDue(True, False, TAtlasInlayPlan.cQuietMs, True, True));
  Assert.IsFalse(TAtlasInlayPlan.FetchDue(False, False, 1000, True, True), 'ohne Ansicht');
  Assert.IsFalse(TAtlasInlayPlan.FetchDue(True, True, 1000, True, True), 'eben geändert');
  Assert.IsFalse(TAtlasInlayPlan.FetchDue(True, False, TAtlasInlayPlan.cQuietMs - 1, True, True), 'Tipp-Pause');
  Assert.IsFalse(TAtlasInlayPlan.FetchDue(True, False, 1000, False, True), 'Wartezeit nach Fehler');
  Assert.IsFalse(TAtlasInlayPlan.FetchDue(True, False, 1000, True, False), 'Designer vorn');
end;

procedure TInlayHintsPlanTests.VisibleLinesFromTopRow;
var
  mFirst, mLast: Integer;
begin
  TAtlasInlayPlan.VisibleLines(11, 40, mFirst, mLast);
  Assert.AreEqual(10, mFirst);
  Assert.AreEqual(50, mLast);
end;

procedure TInlayHintsPlanTests.StoredLineCollectsKindsInOrder;
var
  mStore: TAtlasInlayHintStore;
  mHints: TAtlasInlayLine;
begin
  mStore := TAtlasInlayHintStore.Create;
  try
    Fill(mStore);
    Assert.IsTrue(TAtlasInlayPlan.StoredLine(mStore, 'A.pas', 1, Texts, mHints));
    Assert.AreEqual(1, mHints.Line);
    Assert.AreEqual(IntToStr(Ord(TAtlasInlayKind.Defines)) + '=defines COMPLIB_VCL;', Kinds(mHints));
    Assert.IsTrue(TAtlasInlayPlan.StoredLine(mStore, 'A.pas', 2, Texts, mHints));
    Assert.AreEqual(IntToStr(Ord(TAtlasInlayKind.Method)) + '=no Self;', Kinds(mHints));
    Assert.AreEqual(37, mHints.MethodCharacter);
    Assert.IsTrue(TAtlasInlayPlan.StoredLine(mStore, 'A.pas', 3, Texts, mHints));
    Assert.IsTrue(mHints.ShowEnd, 'Endmarke');
    Assert.AreEqual('TA.Mal', mHints.EndText);
  finally
    mStore.Free;
  end;
end;

procedure TInlayHintsPlanTests.StoredLineWithoutHints;
var
  mStore: TAtlasInlayHintStore;
  mHints: TAtlasInlayLine;
begin
  mStore := TAtlasInlayHintStore.Create;
  try
    Fill(mStore);
    Assert.IsFalse(TAtlasInlayPlan.StoredLine(mStore, 'A.pas', 0, Texts, mHints));
    Assert.AreEqual(0, Integer(Length(mHints.Rows)));
    Assert.IsFalse(TAtlasInlayPlan.StoredLine(mStore, 'B.pas', 1, Texts, mHints), 'andere Datei');
  finally
    mStore.Free;
  end;
end;

function TwoRows: TAtlasInlayLine;
begin
  Result := Default(TAtlasInlayLine);
  Result.Stored := 'X := Format(''%d'', [N]);';
  SetLength(Result.Rows, 2);
  Result.Rows[0].Kind := TAtlasInlayKind.Parameters;
  Result.Rows[0].Labels := TArray<string>.Create('Format:');
  Result.Rows[1].Kind := TAtlasInlayKind.InferredTypes;
  Result.Rows[1].Labels := TArray<string>.Create(': string');
  Result.ShowEnd := True;
  Result.EndText := 'TA.Mal';
end;

procedure TInlayHintsPlanTests.KeepShownDropsKindsThatAreOff;
var
  mHints: TAtlasInlayLine;
begin
  mHints := TwoRows;
  Assert.IsTrue(TAtlasInlayPlan.KeepShown(mHints, [TAtlasInlayKind.InferredTypes], False, nil));
  Assert.AreEqual(1, Integer(Length(mHints.Rows)));
  Assert.AreEqual<TAtlasInlayKind>(TAtlasInlayKind.InferredTypes, mHints.Rows[0].Kind);
  Assert.IsFalse(mHints.ShowEnd, 'Beschriftungen aus');
  mHints := TwoRows;
  Assert.IsFalse(TAtlasInlayPlan.KeepShown(mHints, [], False, nil), 'alles aus');
  mHints := TwoRows;
  mHints.Rows := nil;
  Assert.IsTrue(TAtlasInlayPlan.KeepShown(mHints, [], True, nil), 'nur die Beschriftung');
end;

procedure TInlayHintsPlanTests.KeepShownAsksHiddenPerKind;
var
  mHints: TAtlasInlayLine;
  mAsked: string;
begin
  mHints := TwoRows;
  mAsked := '';
  Assert.IsTrue(TAtlasInlayPlan.KeepShown(mHints, [TAtlasInlayKind.Parameters, TAtlasInlayKind.InferredTypes],
    True,
    function(AKind: TAtlasInlayKind; const AText: string): Boolean
    begin
      mAsked := mAsked + AText + '|';
      Result := AKind = TAtlasInlayKind.Parameters;
    end));
  Assert.AreEqual(1, Integer(Length(mHints.Rows)), 'Parameternamen ausgeblendet');
  Assert.AreEqual<TAtlasInlayKind>(TAtlasInlayKind.InferredTypes, mHints.Rows[0].Kind);
  Assert.IsTrue(mHints.ShowEnd);
  // Pillen je Codezeile, Beschriftung je Text der Beschriftung.
  Assert.AreEqual('X := Format(''%d'', [N]);|X := Format(''%d'', [N]);|TA.Mal|', mAsked);
  mAsked := '';
end;

procedure TInlayHintsPlanTests.SameLineIgnoresTabsAndTrailingBlanks;
begin
  Assert.IsTrue(TAtlasInlayPlan.SameLine(#9'F(1);  ', '  F(1);', 2));
  Assert.IsFalse(TAtlasInlayPlan.SameLine(#9'F(1);', '  F(2);', 2));
  Assert.IsFalse(TAtlasInlayPlan.SameLine(#9'F(1);', ' F(1);', 2), 'andere Einrückung');
end;

procedure TInlayHintsPlanTests.ColumnsResolveTabs;
begin
  Assert.AreEqual(1, TAtlasInlayPlan.ColumnOf('F(1);', 0, 4));
  Assert.AreEqual(6, TAtlasInlayPlan.ColumnOf(#9'F;', 1, 4) + 1);
  Assert.AreEqual(1, TAtlasInlayPlan.ColumnOf('F', -3, 4), 'vor der Zeile');
  // Zwei Zeichen hinter dem letzten Zeichen, Leerzeichen am Ende zählen nicht.
  Assert.AreEqual(8, TAtlasInlayPlan.TailColumn('F(1);   ', 4));
end;

procedure TInlayHintsPlanTests.FontSizeOnePointSmaller;
begin
  Assert.AreEqual(9, TAtlasInlayPlan.FontSize(10));
  Assert.AreEqual(6, TAtlasInlayPlan.FontSize(6));
end;

procedure TInlayHintsPlanTests.OnlyPlainLeftClickCounts;
begin
  Assert.IsTrue(TAtlasInlayPlan.CountsAsClick(True, []));
  Assert.IsTrue(TAtlasInlayPlan.CountsAsClick(True, [ssLeft]), 'Maustaste im Zustand');
  Assert.IsFalse(TAtlasInlayPlan.CountsAsClick(False, []), 'rechts');
  Assert.IsFalse(TAtlasInlayPlan.CountsAsClick(True, [ssCtrl]), 'Strg');
  Assert.IsFalse(TAtlasInlayPlan.CountsAsClick(True, [ssShift]), 'Umschalt');
  Assert.IsFalse(TAtlasInlayPlan.CountsAsClick(True, [ssAlt]), 'Alt');
end;

procedure TInlayHintsPlanTests.HitStillShownByKind;
var
  mHit: TAtlasInlayPillHit;
begin
  mHit := Hit('A.pas', 2, False);
  Assert.IsTrue(TAtlasInlayPlan.HitStillShown(mHit, True, False, False, -1), 'Blockende an');
  Assert.IsFalse(TAtlasInlayPlan.HitStillShown(mHit, False, True, True, 0), 'Blockende aus');
  mHit := Hit('A.pas', 2, True);
  mHit.TargetCharacter := 37;
  Assert.IsTrue(TAtlasInlayPlan.HitStillShown(mHit, False, True, True, 37));
  Assert.IsFalse(TAtlasInlayPlan.HitStillShown(mHit, True, False, True, 37), 'Art aus');
  Assert.IsFalse(TAtlasInlayPlan.HitStillShown(mHit, True, True, False, 37), 'nicht mehr im Speicher');
  Assert.IsFalse(TAtlasInlayPlan.HitStillShown(mHit, True, True, True, 30), 'Kopf geändert');
end;

{ TInlayPillHitsTests }

procedure TInlayPillHitsTests.RememberReplacesSameLineAndKind;
var
  mHits: TAtlasInlayPillHits;
  mFound: TAtlasInlayPillHit;
  mReplaced: TAtlasInlayPillHit;
begin
  mHits := Default(TAtlasInlayPillHits);
  mHits.Remember(Hit('A.pas', 2, False));
  mHits.Remember(Hit('A.pas', 2, True));
  mReplaced := Hit('a.PAS', 2, False);
  mReplaced.TargetLine := 7;
  mHits.Remember(mReplaced);
  Assert.AreEqual(2, mHits.Count);
  Assert.IsTrue(mHits.Find('A.pas', 1, Point(20, 25),
    function(const AHit: TAtlasInlayPillHit): Boolean
    begin
      Result := not AHit.Actions;
    end, mFound));
  Assert.AreEqual(7, mFound.TargetLine);
  mHits.Clear;
  Assert.AreEqual(0, mHits.Count);
end;

procedure TInlayPillHitsTests.RememberForgetsAllWhenFull;
var
  mHits: TAtlasInlayPillHits;
  mIndex: Integer;
begin
  mHits := Default(TAtlasInlayPillHits);
  for mIndex := 1 to TAtlasInlayPillHits.cMaxHits do
  begin
    mHits.Remember(Hit('A.pas', mIndex, False));
  end;
  Assert.AreEqual(TAtlasInlayPillHits.cMaxHits, mHits.Count);
  mHits.Remember(Hit('A.pas', 0, False));
  Assert.AreEqual(1, mHits.Count);
  mHits.Clear;
end;

procedure TInlayPillHitsTests.FindNeedsFileTopRowPointAndShown;
var
  mHits: TAtlasInlayPillHits;
  mFound: TAtlasInlayPillHit;
  mShown: TAtlasInlayHitShownFunc;
begin
  mHits := Default(TAtlasInlayPillHits);
  mHits.Remember(Hit('A.pas', 2, False));
  mShown :=
    function(const AHit: TAtlasInlayPillHit): Boolean
    begin
      Result := True;
    end;
  Assert.IsTrue(mHits.Find('A.pas', 1, Point(10, 20), mShown, mFound));
  Assert.IsFalse(mHits.Find('B.pas', 1, Point(10, 20), mShown, mFound), 'andere Datei');
  Assert.AreEqual(0, mFound.Line);
  Assert.IsFalse(mHits.Find('A.pas', 2, Point(10, 20), mShown, mFound), 'gescrollt');
  Assert.IsFalse(mHits.Find('A.pas', 1, Point(50, 20), mShown, mFound), 'rechter Rand');
  Assert.IsFalse(mHits.Find('A.pas', 1, Point(10, 20),
    function(const AHit: TAtlasInlayPillHit): Boolean
    begin
      Result := False;
    end, mFound), 'Art aus');
  mShown := nil;
  mHits.Clear;
end;

initialization
  TDUnitX.RegisterTestFixture(TInlayHintsPlanTests);
  TDUnitX.RegisterTestFixture(TInlayPillHitsTests);

end.
