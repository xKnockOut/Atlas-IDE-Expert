unit Atlas.Core.Editor.Hide.Tests;

// Ausblenden am Element (#628): „Nur hier“, „In dieser Datei“ und „Überall“
// als Kernlogik. Unterdrückungskommentare werden mit dem Lexer und
// TSuppressions des Servers (#147) geprüft; Einträge in .atlas mit dem Leser
// der Projektdatei (#486).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasHideTests = class
  private
    function Suppressed(const AText, ARuleId: string; ALine: Integer): Boolean;
  public
    [Test]
    procedure HereOnFindingWritesValidLineComment;
    [Test]
    procedure HereExtendsExistingCommentBeforeReason;
    [Test]
    procedure InFileOnFindingWritesValidFileComment;
    [Test]
    procedure AlreadySuppressedIsRefused;
    [Test]
    procedure HereAndInFileWriteTeamFileEntries;
    [Test]
    procedure FindingWithoutRuleUsesTeamFile;
    [Test]
    procedure RefusesWithoutProjectOrScope;
    [Test]
    procedure EverywhereSwitchesSettingOffAndBack;
    [Test]
    procedure InsertRevertsOnlyUnchangedText;
    [Test]
    procedure TeamFileReadsAndChecksHidden;
    [Test]
    procedure AddAndRemoveKeepTheRestOfTheFile;
    [Test]
    procedure IndexAnswersHiddenQuickly;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Rules.Suppressions,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Editor.Hide,
  Atlas.Core.Settings.HiddenPlaces,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.TeamFile;

const
  cFolder = 'C:\Repo\App';
  cUnit1 = 'C:\Repo\App\Source\Kunde.pas';
  cCode =
    'unit Kunde;' + #13#10 +
    #13#10 +
    'implementation' + #13#10 +
    #13#10 +
    'procedure TKunde.Speichern;' + #13#10 +
    'begin' + #13#10 +
    '  with Daten do' + #13#10 +
    '    Schreiben;' + #13#10 +
    'end;' + #13#10 +
    #13#10 +
    'end.' + #13#10;

function TAtlasHideTests.Suppressed(const AText, ARuleId: string; ALine: Integer): Boolean;
var
  mSuppressions: TSuppressions;
begin
  mSuppressions := TSuppressions.Create(TPascalLexer.Tokenize(AText));
  try
    Result := mSuppressions.IsSuppressed(ARuleId, ALine);
  finally
    mSuppressions.Free;
  end;
end;

procedure TAtlasHideTests.HereOnFindingWritesValidLineComment;
var
  mPlan: TAtlasHidePlan;
  mRefusal: TAtlasHideRefusal;
  mText: string;
begin
  // Befund „with“ in Zeile 6 (0-basiert).
  Assert.IsFalse(Suppressed(cCode, 'no-with', 6));
  Assert.IsTrue(TAtlasHide.Plan(TAtlasHideTarget.Finding(cUnit1, 6, 'no-with', '  with Daten do'),
    TAtlasHideScope.Here, cCode, cFolder, mPlan, mRefusal));
  Assert.AreEqual<TAtlasHideKind>(TAtlasHideKind.LineComment, mPlan.Kind);
  Assert.AreEqual(6, mPlan.Insert.Line);
  Assert.AreEqual('  // lsp-ignore: no-with'#13#10, mPlan.Insert.Text, 'eingerückt wie die Zeile, gleiche Zeilenenden');
  mText := mPlan.Insert.ApplyTo(cCode);
  // Gültig: Der Server unterdrückt die Regel in der Zeile darunter (jetzt 7) und nur dort.
  Assert.IsTrue(Suppressed(mText, 'no-with', 7));
  Assert.IsFalse(Suppressed(mText, 'no-with', 8));
  Assert.IsFalse(Suppressed(mText, 'andere-regel', 7));
end;

procedure TAtlasHideTests.HereExtendsExistingCommentBeforeReason;
var
  mText, mChanged: string;
  mInsert: TAtlasTextInsert;
begin
  mText := 'begin' + #10 + '  // lsp-ignore: a -- Altcode' + #10 + '  with X do Y;' + #10 + 'end;';
  mInsert := TAtlasHide.SuppressLine(mText, 2, 'no-with');
  Assert.AreEqual(1, mInsert.Line);
  Assert.AreEqual(', no-with', mInsert.Text);
  mChanged := mInsert.ApplyTo(mText);
  Assert.Contains(mChanged, '// lsp-ignore: a, no-with -- Altcode');
  Assert.IsTrue(Suppressed(mChanged, 'no-with', 2));
  Assert.IsTrue(Suppressed(mChanged, 'a', 2));
  // Leerer Kommentar ohne Kennung und Schreibweise ohne Leerzeichen.
  mText := 'begin' + #10 + '  //lsp-ignore:' + #10 + '  with X do Y;' + #10 + 'end;';
  mChanged := TAtlasHide.SuppressLine(mText, 2, 'no-with').ApplyTo(mText);
  Assert.Contains(mChanged, '//lsp-ignore: no-with' + #10);
  Assert.IsTrue(Suppressed(mChanged, 'no-with', 2));
  // Ein Kommentar am Zeilenende darüber gilt für seine eigene Zeile: neue Zeile.
  mText := 'begin' + #10 + '  A; // lsp-ignore: a' + #10 + '  with X do Y;' + #10 + 'end;';
  mInsert := TAtlasHide.SuppressLine(mText, 2, 'no-with');
  Assert.AreEqual(2, mInsert.Line);
  Assert.AreEqual(0, mInsert.Character);
  Assert.AreEqual('  // lsp-ignore: no-with'#10, mInsert.Text);
  Assert.IsTrue(Suppressed(mInsert.ApplyTo(mText), 'no-with', 3));
end;

procedure TAtlasHideTests.InFileOnFindingWritesValidFileComment;
var
  mPlan: TAtlasHidePlan;
  mRefusal: TAtlasHideRefusal;
  mText: string;
begin
  Assert.IsTrue(TAtlasHide.Plan(TAtlasHideTarget.Finding(cUnit1, 6, 'no-with', '  with Daten do'),
    TAtlasHideScope.InFile, cCode, cFolder, mPlan, mRefusal));
  Assert.AreEqual<TAtlasHideKind>(TAtlasHideKind.FileComment, mPlan.Kind);
  Assert.AreEqual(0, mPlan.Insert.Line);
  mText := mPlan.Insert.ApplyTo(cCode);
  Assert.IsTrue(mText.StartsWith('// lsp-ignore-file: no-with'#13#10'unit Kunde;'));
  Assert.IsTrue(Suppressed(mText, 'no-with', 7));
  Assert.IsTrue(Suppressed(mText, 'no-with', 1));
  // Ein vorhandener Dateikommentar wird ergänzt.
  mText := TAtlasHide.SuppressFile(mText, 'max-length').ApplyTo(mText);
  Assert.IsTrue(mText.StartsWith('// lsp-ignore-file: no-with, max-length'#13#10));
  Assert.IsTrue(Suppressed(mText, 'max-length', 5));
end;

procedure TAtlasHideTests.AlreadySuppressedIsRefused;
var
  mPlan: TAtlasHidePlan;
  mRefusal: TAtlasHideRefusal;
  mText: string;
begin
  mText := '  // lsp-ignore: *' + #13#10 + '  with X do Y;';
  Assert.IsFalse(TAtlasHide.Plan(TAtlasHideTarget.Finding(cUnit1, 1, 'no-with', '  with X do Y;'),
    TAtlasHideScope.Here, mText, cFolder, mPlan, mRefusal));
  Assert.AreEqual<TAtlasHideRefusal>(TAtlasHideRefusal.AlreadyHidden, mRefusal);
  mText := '// lsp-ignore-file: NO-WITH' + #13#10 + 'unit A;';
  Assert.IsFalse(TAtlasHide.Plan(TAtlasHideTarget.Finding(cUnit1, 1, 'no-with', 'unit A;'),
    TAtlasHideScope.InFile, mText, cFolder, mPlan, mRefusal));
  Assert.AreEqual<TAtlasHideRefusal>(TAtlasHideRefusal.AlreadyHidden, mRefusal);
end;

procedure TAtlasHideTests.HereAndInFileWriteTeamFileEntries;
var
  mPlan: TAtlasHidePlan;
  mRefusal: TAtlasHideRefusal;
  mTarget: TAtlasHideTarget;
begin
  mTarget := TAtlasHideTarget.Create(TAtlasDrawnElement.BlockEndLabels, cUnit1, 8, ' TKunde.Speichern ');
  Assert.AreEqual('TKunde.Speichern', mTarget.Anchor);
  Assert.IsTrue(TAtlasHide.Plan(mTarget, TAtlasHideScope.Here, cCode, cFolder, mPlan, mRefusal));
  Assert.AreEqual<TAtlasHideKind>(TAtlasHideKind.TeamFile, mPlan.Kind);
  Assert.AreEqual('BlockEndLabels', mPlan.Place.Setting);
  Assert.AreEqual('Source/Kunde.pas', mPlan.Place.FileName);
  Assert.AreEqual('TKunde.Speichern', mPlan.Place.Anchor);
  Assert.IsTrue(TAtlasHide.Plan(mTarget, TAtlasHideScope.InFile, cCode, cFolder, mPlan, mRefusal));
  Assert.AreEqual<TAtlasHideKind>(TAtlasHideKind.TeamFile, mPlan.Kind);
  Assert.IsTrue(mPlan.Place.WholeFile);
  Assert.AreEqual('Source/Kunde.pas', mPlan.Place.FileName);
end;

procedure TAtlasHideTests.FindingWithoutRuleUsesTeamFile;
var
  mPlan: TAtlasHidePlan;
  mRefusal: TAtlasHideRefusal;
begin
  // Compilermeldung: kein lsp-ignore möglich, Eintrag mit der Codezeile als Anker.
  Assert.IsTrue(TAtlasHide.Plan(TAtlasHideTarget.Finding(cUnit1, 7, '', '    Schreiben;'), TAtlasHideScope.Here, cCode,
    cFolder, mPlan, mRefusal));
  Assert.AreEqual<TAtlasHideKind>(TAtlasHideKind.TeamFile, mPlan.Kind);
  Assert.AreEqual('Problems', mPlan.Place.Setting);
  Assert.AreEqual('Schreiben;', mPlan.Place.Anchor);
end;

procedure TAtlasHideTests.RefusesWithoutProjectOrScope;
var
  mPlan: TAtlasHidePlan;
  mRefusal: TAtlasHideRefusal;
begin
  Assert.IsFalse(TAtlasHide.Plan(TAtlasHideTarget.Create(TAtlasDrawnElement.InlayHints, cUnit1, 3, 'F(1)'),
    TAtlasHideScope.Here, cCode, '', mPlan, mRefusal));
  Assert.AreEqual<TAtlasHideRefusal>(TAtlasHideRefusal.NoProjectFolder, mRefusal);
  Assert.IsFalse(TAtlasHide.Plan(TAtlasHideTarget.Create(TAtlasDrawnElement.InlayHints, 'D:\Fremd\A.pas', 3, 'F(1)'),
    TAtlasHideScope.Here, cCode, cFolder, mPlan, mRefusal));
  Assert.AreEqual<TAtlasHideRefusal>(TAtlasHideRefusal.OutsideProject, mRefusal);
  Assert.IsFalse(TAtlasHide.Plan(TAtlasHideTarget.Create(TAtlasDrawnElement.PairColors, cUnit1, 3, 'begin'),
    TAtlasHideScope.Here, cCode, cFolder, mPlan, mRefusal));
  Assert.AreEqual<TAtlasHideRefusal>(TAtlasHideRefusal.ScopeNotOffered, mRefusal);
  Assert.IsFalse(TAtlasHide.Plan(TAtlasHideTarget.Create(TAtlasDrawnElement.CompletionPreview, cUnit1, 3, ''),
    TAtlasHideScope.InFile, cCode, cFolder, mPlan, mRefusal));
  Assert.AreEqual<TAtlasHideRefusal>(TAtlasHideRefusal.ScopeNotOffered, mRefusal);
  // Ohne Anker keine einzelne Stelle.
  Assert.IsFalse(TAtlasHide.Plan(TAtlasHideTarget.Create(TAtlasDrawnElement.Notes, cUnit1, 3, '   '),
    TAtlasHideScope.Here, cCode, cFolder, mPlan, mRefusal));
  Assert.AreEqual<TAtlasHideRefusal>(TAtlasHideRefusal.ScopeNotOffered, mRefusal);
end;

procedure TAtlasHideTests.EverywhereSwitchesSettingOffAndBack;
var
  mPlan: TAtlasHidePlan;
  mRefusal: TAtlasHideRefusal;
  mSettings: TAtlasPluginSettings;
  mOld: string;
begin
  // Abnahme: „Überall ausblenden“ auf einer Blockende-Beschriftung setzt editor.blockEndLabels auf false.
  Assert.IsTrue(TAtlasHide.Plan(TAtlasHideTarget.Create(TAtlasDrawnElement.BlockEndLabels, cUnit1, 8, 'TKunde'),
    TAtlasHideScope.Everywhere, cCode, '', mPlan, mRefusal));
  Assert.AreEqual<TAtlasHideKind>(TAtlasHideKind.Setting, mPlan.Kind);
  Assert.AreEqual('BlockEndLabels', mPlan.SettingKey);
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.BlockEndLabels);
  Assert.IsTrue(TAtlasHide.SwitchOff(mSettings, mPlan.SettingKey, mOld));
  Assert.IsFalse(mSettings.BlockEndLabels);
  Assert.IsFalse(TAtlasHide.IsOn(mSettings, mPlan.SettingKey));
  Assert.IsFalse(TAtlasHide.SwitchOff(mSettings, mPlan.SettingKey, mOld), 'schon aus');
  Assert.IsTrue(TAtlasHide.Restore(mSettings, 'BlockEndLabels', '1'));
  Assert.IsTrue(mSettings.BlockEndLabels);
  // Textauswahl (Willkommensseite, „Neu in Atlas“): aus = "off", zurück auf den alten Wert.
  Assert.IsTrue(TAtlasHide.SwitchOff(mSettings, 'WelcomePageWhatsNew', mOld));
  Assert.AreEqual('afterUpdate', mOld);
  Assert.AreEqual('off', mSettings.WelcomePageWhatsNew);
  Assert.IsTrue(TAtlasHide.Restore(mSettings, 'WelcomePageWhatsNew', mOld));
  Assert.AreEqual('afterUpdate', mSettings.WelcomePageWhatsNew);
  // Fehlertext am Zeilenende (#509): „Überall“ stellt den Modus auf aus, Rückgängig auf den alten.
  Assert.IsTrue(TAtlasHide.Plan(TAtlasHideTarget.Create(TAtlasDrawnElement.InlineDiagnostics, cUnit1, 8, 'X := 1;'),
    TAtlasHideScope.Everywhere, cCode, '', mPlan, mRefusal));
  Assert.AreEqual('InlineDiagnostics', mPlan.SettingKey);
  mSettings.InlineDiagnostics := 'all';
  Assert.IsTrue(TAtlasHide.SwitchOff(mSettings, mPlan.SettingKey, mOld));
  Assert.AreEqual('all', mOld);
  Assert.AreEqual('off', mSettings.InlineDiagnostics);
  Assert.IsTrue(TAtlasHide.Restore(mSettings, mPlan.SettingKey, mOld));
  Assert.AreEqual('all', mSettings.InlineDiagnostics);
  Assert.IsFalse(TAtlasHide.SwitchOff(mSettings, 'GibtEsNicht', mOld));
  Assert.IsFalse(TAtlasHide.Restore(mSettings, 'GibtEsNicht', '1'));
end;

procedure TAtlasHideTests.InsertRevertsOnlyUnchangedText;
var
  mInsert: TAtlasTextInsert;
  mText, mReverted: string;
begin
  mInsert := TAtlasHide.SuppressLine(cCode, 6, 'no-with');
  mText := mInsert.ApplyTo(cCode);
  Assert.IsTrue(mInsert.RevertIn(mText, mReverted));
  Assert.AreEqual(cCode, mReverted);
  mText := StringReplace(mText, 'lsp-ignore', 'lsp-IGNORE', []);
  Assert.IsFalse(mInsert.RevertIn(mText, mReverted), 'inzwischen geändert');
  Assert.AreEqual(mText, mReverted);
end;

procedure TAtlasHideTests.TeamFileReadsAndChecksHidden;
var
  mTeam: TAtlasTeamSettings;
  mIssue: TAtlasTeamIssue;
  mPaths: string;
begin
  mTeam := TAtlasTeamFile.Parse('{"version": 1, "hidden": [' +
    '{"setting": "BlockEndLabels", "file": "Source/Kunde.pas", "anchor": "TKunde.Speichern"},' +
    '{"setting": "InlayHints", "file": "Source\\Kunde.pas"},' +
    '{"setting": "Notes", "file": "C:\\Fremd\\A.pas"},' +
    '{"setting": "Notes", "file": "../../Fremd/A.pas"},' +
    '{"file": "A.pas"},' +
    '{"setting": "Notes", "file": "A.pas", "zeile": 3},' +
    '"kein Objekt"]}', 'C:\Repo\App\.atlas', 'C:\Repo');
  Assert.IsTrue(mTeam.Valid);
  Assert.AreEqual(3, Integer(Length(mTeam.Hidden)));
  Assert.AreEqual('BlockEndLabels', mTeam.Hidden[0].Setting);
  Assert.AreEqual('TKunde.Speichern', mTeam.Hidden[0].Anchor);
  Assert.AreEqual('Source/Kunde.pas', mTeam.Hidden[1].FileName, 'Trenner "/"');
  Assert.IsTrue(mTeam.Hidden[1].WholeFile);
  Assert.AreEqual('A.pas', mTeam.Hidden[2].FileName);
  mPaths := '';
  for mIssue in mTeam.Issues do
  begin
    mPaths := mPaths + mIssue.Path + '|';
  end;
  Assert.Contains(mPaths, 'hidden[2].file');
  Assert.Contains(mPaths, 'hidden[3].file');
  Assert.Contains(mPaths, 'hidden[4]');
  Assert.Contains(mPaths, 'hidden[5].zeile');
  Assert.Contains(mPaths, 'hidden[6]');
  Assert.IsTrue(mTeam.HasValues);
  mTeam := TAtlasTeamFile.Parse('{"version": 1, "hidden": {}}', 'C:\Repo\App\.atlas', 'C:\Repo');
  Assert.AreEqual(0, Integer(Length(mTeam.Hidden)));
  Assert.AreEqual(1, Integer(Length(mTeam.Issues)));
end;

procedure TAtlasHideTests.AddAndRemoveKeepTheRestOfTheFile;
var
  mText, mChanged: string;
  mPlace, mSecond: TAtlasHiddenPlace;
  mTeam: TAtlasTeamSettings;
begin
  // Neue Datei aus dem Gerüst: gültig, ohne Meldungen, Kommentare bleiben.
  mPlace := TAtlasHiddenPlace.Create('BlockEndLabels', 'Source\Kunde.pas', 'TKunde.Speichern');
  mChanged := TAtlasHiddenPlaces.AddTo('', TAtlasTeamFile.Skeleton, mPlace);
  mTeam := TAtlasTeamFile.Parse(mChanged, 'C:\Repo\App\.atlas', 'C:\Repo');
  Assert.IsTrue(mTeam.Valid);
  Assert.AreEqual(0, Integer(Length(mTeam.Issues)));
  Assert.AreEqual(1, Integer(Length(mTeam.Hidden)));
  Assert.AreEqual('Source/Kunde.pas', mTeam.Hidden[0].FileName);
  Assert.Contains(mChanged, '// Projekteinstellungen von Atlas');
  // Vorhandene Datei: übrige Werte und Kommentare bleiben, doppelter Eintrag entfällt.
  mText := '{' + #13#10 + '  // Team' + #13#10 + '  "version": 1,' + #13#10 + '  "sqlTargets": ["TQ.SQL"]' + #13#10 +
    '}' + #13#10;
  mChanged := TAtlasHiddenPlaces.AddTo(mText, TAtlasTeamFile.Skeleton, mPlace);
  Assert.AreEqual(mChanged, TAtlasHiddenPlaces.AddTo(mChanged, TAtlasTeamFile.Skeleton, mPlace), 'schon drin');
  mSecond := TAtlasHiddenPlace.Create('InlayHints', 'Source/Kunde.pas', '');
  mChanged := TAtlasHiddenPlaces.AddTo(mChanged, TAtlasTeamFile.Skeleton, mSecond);
  Assert.Contains(mChanged, '// Team');
  Assert.Contains(mChanged, '"sqlTargets": ["TQ.SQL"]');
  mTeam := TAtlasTeamFile.Parse(mChanged, 'C:\Repo\App\.atlas', 'C:\Repo');
  Assert.AreEqual(0, Integer(Length(mTeam.Issues)));
  Assert.AreEqual(2, Integer(Length(mTeam.Hidden)));
  Assert.AreEqual(1, Integer(Length(mTeam.SqlTargets)));
  // Rückgängig: genau der Eintrag fällt weg.
  mChanged := TAtlasHiddenPlaces.RemoveFrom(mChanged, mPlace);
  mTeam := TAtlasTeamFile.Parse(mChanged, 'C:\Repo\App\.atlas', 'C:\Repo');
  Assert.AreEqual(1, Integer(Length(mTeam.Hidden)));
  Assert.AreEqual('InlayHints', mTeam.Hidden[0].Setting);
  mChanged := TAtlasHiddenPlaces.RemoveFrom(mChanged, mSecond);
  Assert.AreEqual(0, Integer(Length(TAtlasHiddenPlaces.FromText(mChanged))));
  Assert.AreEqual(mChanged, TAtlasHiddenPlaces.RemoveFrom(mChanged, mSecond), 'fehlt schon');
end;

procedure TAtlasHideTests.IndexAnswersHiddenQuickly;
var
  mIndex: TAtlasHiddenIndex;
begin
  mIndex := TAtlasHiddenIndex.Create([TAtlasHiddenPlace.Create('BlockEndLabels', 'Source/Kunde.pas', 'TKunde.Speichern'),
    TAtlasHiddenPlace.Create('InlayHints', 'source/kunde.pas', '')], cFolder);
  try
    Assert.IsFalse(mIndex.IsEmpty);
    Assert.IsTrue(mIndex.Hidden('BlockEndLabels', cUnit1, 'TKunde.Speichern'));
    Assert.IsFalse(mIndex.Hidden('BlockEndLabels', cUnit1, 'TKunde.Laden'));
    Assert.IsFalse(mIndex.FileHidden('BlockEndLabels', cUnit1));
    Assert.IsTrue(mIndex.FileHidden('inlayhints', cUnit1));
    Assert.IsTrue(mIndex.Hidden('InlayHints', 'c:\repo\app\SOURCE\Kunde.pas', 'egal'));
    Assert.IsFalse(mIndex.Hidden('InlayHints', 'C:\Repo\App\Source\Andere.pas', ''));
    Assert.IsFalse(mIndex.Hidden('InlayHints', 'C:\Anderswo\Source\Kunde.pas', ''));
  finally
    mIndex.Free;
  end;
  mIndex := TAtlasHiddenIndex.Create([TAtlasHiddenPlace.Create('Notes', 'A.pas', '')], '');
  try
    Assert.IsTrue(mIndex.IsEmpty, 'ohne Ordner wirkt nichts');
  finally
    mIndex.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasHideTests);

end.
