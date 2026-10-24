unit Atlas.UI.Debug.StepFilterFrame.Tests;

// Fenster „Schrittfilter“ (#850), Oberfläche: Grund eines Urteils, Treffer an
// Arten und Mustern erst nach dem Zählen, Zusammenfassung und Sitzungszeile,
// Muster hinzufügen, ersetzen und entfernen (ungültige und doppelte nicht),
// Schalter und Arten melden den ganzen Stand, SetOptions meldet nichts und baut
// die Liste nur bei neuen Mustern neu.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  TAtlasDebugStepFilterFrameTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure VerdictTexts;
    [Test]
    procedure HitsOnlyWhenCounted;
    [Test]
    procedure SummaryAndSession;
    [Test]
    procedure AddReplaceRemovePatterns;
    [Test]
    procedure ChecksReportWholeState;
    [Test]
    procedure SetOptionsKeepsListWhenUnchanged;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.Text.StepFilter,
  Atlas.Core.Debug.StepFilter,
  Atlas.UI.Debug.StepFilterFrame;

type
  TChangeLog = class
  public
    Count: Integer;
    Enabled: Boolean;
    Kinds: TStepFilterKinds;
    Patterns: TArray<string>;
  end;

function Counted: TAtlasStepCounts;
begin
  Result := Default(TAtlasStepCounts);
  Result.Files := 12;
  Result.Routines := 340;
  Result.Kinds[TStepFilterKind.Getters] := 41;
  Result.Kinds[TStepFilterKind.Trivial] := 17;
  Result.Patterns := TArray<Integer>.Create(3, 0);
end;

function Watch(ALog: TChangeLog): TAtlasStepFilterChange;
begin
  Result :=
    procedure(AEnabled: Boolean; AKinds: TStepFilterKinds; const APatterns: TArray<string>)
    begin
      Inc(ALog.Count);
      ALog.Enabled := AEnabled;
      ALog.Kinds := AKinds;
      ALog.Patterns := Copy(APatterns);
    end;
end;

{ TAtlasDebugStepFilterFrameTests }

procedure TAtlasDebugStepFilterFrameTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasDebugStepFilterFrameTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasDebugStepFilterFrameTests.VerdictTexts;
var
  mVerdict: TAtlasStepVerdict;
begin
  mVerdict := Default(TAtlasStepVerdict);
  Assert.AreEqual('', TAtlasDebugStepFilterFrame.VerdictText(mVerdict));
  mVerdict.Kind := TAtlasStepVerdictKind.Kind;
  mVerdict.FilterKind := TStepFilterKind.Getters;
  Assert.AreEqual('Getter von Eigenschaften (eine Anweisung)', TAtlasDebugStepFilterFrame.VerdictText(mVerdict));
  mVerdict.Kind := TAtlasStepVerdictKind.Pattern;
  mVerdict.Pattern := '*.Log*';
  Assert.AreEqual('Muster *.Log*', TAtlasDebugStepFilterFrame.VerdictText(mVerdict));
end;

procedure TAtlasDebugStepFilterFrameTests.HitsOnlyWhenCounted;
var
  mCounts: TAtlasStepCounts;
begin
  mCounts := Counted;
  Assert.AreEqual('Getter von Eigenschaften (eine Anweisung)',
    TAtlasDebugStepFilterFrame.KindCaption(TStepFilterKind.Getters, TAtlasStepCountsState.Counting, mCounts));
  Assert.AreEqual('Getter von Eigenschaften (eine Anweisung) – 41',
    TAtlasDebugStepFilterFrame.KindCaption(TStepFilterKind.Getters, TAtlasStepCountsState.Ready, mCounts));
  Assert.AreEqual('3', TAtlasDebugStepFilterFrame.PatternHits(0, TAtlasStepCountsState.Ready, mCounts));
  Assert.AreEqual('0', TAtlasDebugStepFilterFrame.PatternHits(1, TAtlasStepCountsState.Ready, mCounts));
  Assert.AreEqual('', TAtlasDebugStepFilterFrame.PatternHits(2, TAtlasStepCountsState.Ready, mCounts),
    'neues Muster, noch nicht gezählt');
  Assert.AreEqual('', TAtlasDebugStepFilterFrame.PatternHits(0, TAtlasStepCountsState.Unavailable, mCounts));
end;

procedure TAtlasDebugStepFilterFrameTests.SummaryAndSession;
var
  mCounts: TAtlasStepCounts;
begin
  mCounts := Counted;
  Assert.AreEqual('340 Routinen in 12 Dateien des Projekts',
    TAtlasDebugStepFilterFrame.SummaryText(TAtlasStepCountsState.Ready, mCounts));
  mCounts.Truncated := True;
  Assert.AreEqual('340 Routinen in 12 Dateien des Projekts (nur die ersten 12 Dateien)',
    TAtlasDebugStepFilterFrame.SummaryText(TAtlasStepCountsState.Ready, mCounts));
  Assert.AreEqual('Zähle im Index …', TAtlasDebugStepFilterFrame.SummaryText(TAtlasStepCountsState.Counting,
    mCounts));
  Assert.AreEqual('Treffer gibt es erst mit laufendem Server.',
    TAtlasDebugStepFilterFrame.SummaryText(TAtlasStepCountsState.Unavailable, mCounts));
  Assert.AreEqual('', TAtlasDebugStepFilterFrame.SummaryText(TAtlasStepCountsState.None, mCounts));
  Assert.AreEqual('In dieser Debug-Sitzung übersprungen: 0',
    TAtlasDebugStepFilterFrame.SessionText(True, 0, '', ''));
  Assert.AreEqual('In dieser Debug-Sitzung übersprungen: 3 · zuletzt Kunden.TKunde.GetName (Muster *.Get*)',
    TAtlasDebugStepFilterFrame.SessionText(True, 3, 'Kunden.TKunde.GetName', 'Muster *.Get*'));
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.StepFilterInactive),
    TAtlasDebugStepFilterFrame.SessionText(False, 3, 'Kunden.TKunde.GetName', 'Muster *.Get*'));
  mCounts.Patterns := nil;
end;

procedure TAtlasDebugStepFilterFrameTests.AddReplaceRemovePatterns;
var
  mHost: TForm;
  mFrame: TAtlasDebugStepFilterFrame;
  mLog: TChangeLog;
begin
  mLog := TChangeLog.Create;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugStepFilterFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mFrame.SetOptions(True, [TStepFilterKind.Getters], TArray<string>.Create('*.Log*'));
    mFrame.OnChange := Watch(mLog);
    Assert.AreEqual(1, mFrame.Patterns.Items.Count);

    mFrame.PatternEdit.Text := '  TBasisForm.*  ';
    Assert.IsTrue(mFrame.AddButtonControl.Enabled);
    Assert.IsTrue(mFrame.AddPattern);
    Assert.AreEqual(1, mLog.Count);
    Assert.AreEqual('*.Log*;TBasisForm.*', TStepFilterNames.PatternsText(mLog.Patterns));
    Assert.AreEqual('', mFrame.PatternEdit.Text, 'Feld leer für das nächste');
    Assert.AreEqual(2, mFrame.Patterns.Items.Count);

    mFrame.PatternEdit.Text := '*.log*';
    Assert.IsFalse(mFrame.AddButtonControl.Enabled, 'doppelt ohne Groß-/Kleinschreibung');
    Assert.IsFalse(mFrame.AddPattern);
    mFrame.PatternEdit.Text := 'a b';
    Assert.IsFalse(mFrame.AddPattern, 'Leerraum ist ungültig');
    Assert.AreEqual(1, mLog.Count);

    Assert.IsFalse(mFrame.ReplacePattern(1, '*.Log*'), 'würde doppelt');
    Assert.IsFalse(mFrame.ReplacePattern(1, '*.'), 'nur Platzhalter');
    Assert.IsTrue(mFrame.ReplacePattern(1, ' Fremd.* '));
    Assert.AreEqual(2, mLog.Count);
    Assert.AreEqual('*.Log*;Fremd.*', TStepFilterNames.PatternsText(mLog.Patterns));

    Assert.IsFalse(mFrame.RemoveSelected, 'ohne Auswahl');
    mFrame.Patterns.Items[0].Selected := True;
    Assert.IsTrue(mFrame.RemoveButtonControl.Enabled);
    Assert.IsTrue(mFrame.RemoveSelected);
    Assert.AreEqual(3, mLog.Count);
    Assert.AreEqual('Fremd.*', TStepFilterNames.PatternsText(mLog.Patterns));
    Assert.AreEqual(1, mFrame.Patterns.Items.Count);
    Assert.IsTrue(mFrame.Patterns.Items[0].Selected, 'Auswahl bleibt an der Stelle');
    Assert.IsTrue(mLog.Enabled);
    Assert.IsTrue(mLog.Kinds = [TStepFilterKind.Getters]);
  finally
    mHost.Free;
    mLog.Patterns := nil;
    mLog.Free;
  end;
end;

procedure TAtlasDebugStepFilterFrameTests.ChecksReportWholeState;
var
  mHost: TForm;
  mFrame: TAtlasDebugStepFilterFrame;
  mLog: TChangeLog;
begin
  mLog := TChangeLog.Create;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugStepFilterFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mFrame.OnChange := Watch(mLog);
    mFrame.SetOptions(False, [TStepFilterKind.Trivial], TArray<string>.Create('*.Log*'));
    Assert.AreEqual(0, mLog.Count, 'SetOptions meldet nichts');
    mFrame.EnabledCheck.Checked := True;
    Assert.AreEqual(1, mLog.Count);
    Assert.IsTrue(mLog.Enabled);
    Assert.IsTrue(mLog.Kinds = [TStepFilterKind.Trivial]);
    Assert.AreEqual('*.Log*', TStepFilterNames.PatternsText(mLog.Patterns));
  finally
    mHost.Free;
    mLog.Patterns := nil;
    mLog.Free;
  end;
end;

procedure TAtlasDebugStepFilterFrameTests.SetOptionsKeepsListWhenUnchanged;
var
  mHost: TForm;
  mFrame: TAtlasDebugStepFilterFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugStepFilterFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mFrame.SetOptions(True, [], TArray<string>.Create('A.*', 'B.*'));
    mFrame.Patterns.Items[1].Selected := True;
    mFrame.SetOptions(False, [TStepFilterKind.Setters], TArray<string>.Create('A.*', 'B.*'));
    Assert.IsTrue(mFrame.Patterns.Items[1].Selected, 'gleiche Muster: Liste bleibt samt Auswahl');
    mFrame.SetCounts(Counted);
    Assert.AreEqual('3', mFrame.Patterns.Items[0].SubItems[0]);
    Assert.AreEqual(TAtlasStepCountsState.Ready, mFrame.CountsState);
    mFrame.SetOptions(False, [], TArray<string>.Create('C.*'));
    Assert.AreEqual(1, mFrame.Patterns.Items.Count);
    Assert.AreEqual('C.*', mFrame.Patterns.Items[0].Caption);
    mFrame.SetNoCounts;
    Assert.AreEqual('', mFrame.Patterns.Items[0].SubItems[0]);
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugStepFilterFrameTests);

end.
