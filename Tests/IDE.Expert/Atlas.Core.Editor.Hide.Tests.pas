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
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Rules.Suppressions,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Editor.Hide,
  Atlas.Core.Settings.HiddenPlaces,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.TeamFile;

const
  Folder = 'C:\Repo\App';
  Unit1 = 'C:\Repo\App\Source\Kunde.pas';
  Code =
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
  Suppressions: TSuppressions;
begin
  Suppressions := TSuppressions.Create(TPascalLexer.Tokenize(AText));
  try
    Result := Suppressions.IsSuppressed(ARuleId, ALine);
  finally
    Suppressions.Free;
  end;
end;

procedure TAtlasHideTests.HereOnFindingWritesValidLineComment;
var
  Plan: TAtlasHidePlan;
  Refusal: TAtlasHideRefusal;
  Text: string;
begin
  // Befund „with“ in Zeile 6 (0-basiert).
  Assert.IsFalse(Suppressed(Code, 'no-with', 6));
  Assert.IsTrue(TAtlasHide.Plan(TAtlasHideTarget.Finding(Unit1, 6, 'no-with', '  with Daten do'),
    TAtlasHideScope.Here, Code, Folder, Plan, Refusal));
  Assert.IsTrue(Plan.Kind = TAtlasHideKind.LineComment);
  Assert.AreEqual(6, Plan.Insert.Line);
  Assert.AreEqual('  // lsp-ignore: no-with'#13#10, Plan.Insert.Text, 'eingerückt wie die Zeile, gleiche Zeilenenden');
  Text := Plan.Insert.ApplyTo(Code);
  // Gültig: Der Server unterdrückt die Regel in der Zeile darunter (jetzt 7) und nur dort.
  Assert.IsTrue(Suppressed(Text, 'no-with', 7));
  Assert.IsFalse(Suppressed(Text, 'no-with', 8));
  Assert.IsFalse(Suppressed(Text, 'andere-regel', 7));
end;

procedure TAtlasHideTests.HereExtendsExistingCommentBeforeReason;
var
  Text, Changed: string;
  Insert: TAtlasTextInsert;
begin
  Text := 'begin' + #10 + '  // lsp-ignore: a -- Altcode' + #10 + '  with X do Y;' + #10 + 'end;';
  Insert := TAtlasHide.SuppressLine(Text, 2, 'no-with');
  Assert.AreEqual(1, Insert.Line);
  Assert.AreEqual(', no-with', Insert.Text);
  Changed := Insert.ApplyTo(Text);
  Assert.Contains(Changed, '// lsp-ignore: a, no-with -- Altcode');
  Assert.IsTrue(Suppressed(Changed, 'no-with', 2));
  Assert.IsTrue(Suppressed(Changed, 'a', 2));
  // Leerer Kommentar ohne Kennung und Schreibweise ohne Leerzeichen.
  Text := 'begin' + #10 + '  //lsp-ignore:' + #10 + '  with X do Y;' + #10 + 'end;';
  Changed := TAtlasHide.SuppressLine(Text, 2, 'no-with').ApplyTo(Text);
  Assert.Contains(Changed, '//lsp-ignore: no-with' + #10);
  Assert.IsTrue(Suppressed(Changed, 'no-with', 2));
  // Ein Kommentar am Zeilenende darüber gilt für seine eigene Zeile: neue Zeile.
  Text := 'begin' + #10 + '  A; // lsp-ignore: a' + #10 + '  with X do Y;' + #10 + 'end;';
  Insert := TAtlasHide.SuppressLine(Text, 2, 'no-with');
  Assert.AreEqual(2, Insert.Line);
  Assert.AreEqual(0, Insert.Character);
  Assert.AreEqual('  // lsp-ignore: no-with'#10, Insert.Text);
  Assert.IsTrue(Suppressed(Insert.ApplyTo(Text), 'no-with', 3));
end;

procedure TAtlasHideTests.InFileOnFindingWritesValidFileComment;
var
  Plan: TAtlasHidePlan;
  Refusal: TAtlasHideRefusal;
  Text: string;
begin
  Assert.IsTrue(TAtlasHide.Plan(TAtlasHideTarget.Finding(Unit1, 6, 'no-with', '  with Daten do'),
    TAtlasHideScope.InFile, Code, Folder, Plan, Refusal));
  Assert.IsTrue(Plan.Kind = TAtlasHideKind.FileComment);
  Assert.AreEqual(0, Plan.Insert.Line);
  Text := Plan.Insert.ApplyTo(Code);
  Assert.IsTrue(Text.StartsWith('// lsp-ignore-file: no-with'#13#10'unit Kunde;'));
  Assert.IsTrue(Suppressed(Text, 'no-with', 7));
  Assert.IsTrue(Suppressed(Text, 'no-with', 1));
  // Ein vorhandener Dateikommentar wird ergänzt.
  Text := TAtlasHide.SuppressFile(Text, 'max-length').ApplyTo(Text);
  Assert.IsTrue(Text.StartsWith('// lsp-ignore-file: no-with, max-length'#13#10));
  Assert.IsTrue(Suppressed(Text, 'max-length', 5));
end;

procedure TAtlasHideTests.AlreadySuppressedIsRefused;
var
  Plan: TAtlasHidePlan;
  Refusal: TAtlasHideRefusal;
  Text: string;
begin
  Text := '  // lsp-ignore: *' + #13#10 + '  with X do Y;';
  Assert.IsFalse(TAtlasHide.Plan(TAtlasHideTarget.Finding(Unit1, 1, 'no-with', '  with X do Y;'),
    TAtlasHideScope.Here, Text, Folder, Plan, Refusal));
  Assert.IsTrue(Refusal = TAtlasHideRefusal.AlreadyHidden);
  Text := '// lsp-ignore-file: NO-WITH' + #13#10 + 'unit A;';
  Assert.IsFalse(TAtlasHide.Plan(TAtlasHideTarget.Finding(Unit1, 1, 'no-with', 'unit A;'),
    TAtlasHideScope.InFile, Text, Folder, Plan, Refusal));
  Assert.IsTrue(Refusal = TAtlasHideRefusal.AlreadyHidden);
end;

procedure TAtlasHideTests.HereAndInFileWriteTeamFileEntries;
var
  Plan: TAtlasHidePlan;
  Refusal: TAtlasHideRefusal;
  Target: TAtlasHideTarget;
begin
  Target := TAtlasHideTarget.Create(TAtlasDrawnElement.BlockEndLabels, Unit1, 8, ' TKunde.Speichern ');
  Assert.AreEqual('TKunde.Speichern', Target.Anchor);
  Assert.IsTrue(TAtlasHide.Plan(Target, TAtlasHideScope.Here, Code, Folder, Plan, Refusal));
  Assert.IsTrue(Plan.Kind = TAtlasHideKind.TeamFile);
  Assert.AreEqual('BlockEndLabels', Plan.Place.Setting);
  Assert.AreEqual('Source/Kunde.pas', Plan.Place.FileName);
  Assert.AreEqual('TKunde.Speichern', Plan.Place.Anchor);
  Assert.IsTrue(TAtlasHide.Plan(Target, TAtlasHideScope.InFile, Code, Folder, Plan, Refusal));
  Assert.IsTrue(Plan.Kind = TAtlasHideKind.TeamFile);
  Assert.IsTrue(Plan.Place.WholeFile);
  Assert.AreEqual('Source/Kunde.pas', Plan.Place.FileName);
end;

procedure TAtlasHideTests.FindingWithoutRuleUsesTeamFile;
var
  Plan: TAtlasHidePlan;
  Refusal: TAtlasHideRefusal;
begin
  // Compilermeldung: kein lsp-ignore möglich, Eintrag mit der Codezeile als Anker.
  Assert.IsTrue(TAtlasHide.Plan(TAtlasHideTarget.Finding(Unit1, 7, '', '    Schreiben;'), TAtlasHideScope.Here, Code,
    Folder, Plan, Refusal));
  Assert.IsTrue(Plan.Kind = TAtlasHideKind.TeamFile);
  Assert.AreEqual('Problems', Plan.Place.Setting);
  Assert.AreEqual('Schreiben;', Plan.Place.Anchor);
end;

procedure TAtlasHideTests.RefusesWithoutProjectOrScope;
var
  Plan: TAtlasHidePlan;
  Refusal: TAtlasHideRefusal;
begin
  Assert.IsFalse(TAtlasHide.Plan(TAtlasHideTarget.Create(TAtlasDrawnElement.InlayHints, Unit1, 3, 'F(1)'),
    TAtlasHideScope.Here, Code, '', Plan, Refusal));
  Assert.IsTrue(Refusal = TAtlasHideRefusal.NoProjectFolder);
  Assert.IsFalse(TAtlasHide.Plan(TAtlasHideTarget.Create(TAtlasDrawnElement.InlayHints, 'D:\Fremd\A.pas', 3, 'F(1)'),
    TAtlasHideScope.Here, Code, Folder, Plan, Refusal));
  Assert.IsTrue(Refusal = TAtlasHideRefusal.OutsideProject);
  Assert.IsFalse(TAtlasHide.Plan(TAtlasHideTarget.Create(TAtlasDrawnElement.PairColors, Unit1, 3, 'begin'),
    TAtlasHideScope.Here, Code, Folder, Plan, Refusal));
  Assert.IsTrue(Refusal = TAtlasHideRefusal.ScopeNotOffered);
  Assert.IsFalse(TAtlasHide.Plan(TAtlasHideTarget.Create(TAtlasDrawnElement.CompletionPreview, Unit1, 3, ''),
    TAtlasHideScope.InFile, Code, Folder, Plan, Refusal));
  Assert.IsTrue(Refusal = TAtlasHideRefusal.ScopeNotOffered);
  // Ohne Anker keine einzelne Stelle.
  Assert.IsFalse(TAtlasHide.Plan(TAtlasHideTarget.Create(TAtlasDrawnElement.Notes, Unit1, 3, '   '),
    TAtlasHideScope.Here, Code, Folder, Plan, Refusal));
  Assert.IsTrue(Refusal = TAtlasHideRefusal.ScopeNotOffered);
end;

procedure TAtlasHideTests.EverywhereSwitchesSettingOffAndBack;
var
  Plan: TAtlasHidePlan;
  Refusal: TAtlasHideRefusal;
  Settings: TAtlasPluginSettings;
  Old: string;
begin
  // Abnahme: „Überall ausblenden“ auf einer Blockende-Beschriftung setzt editor.blockEndLabels auf false.
  Assert.IsTrue(TAtlasHide.Plan(TAtlasHideTarget.Create(TAtlasDrawnElement.BlockEndLabels, Unit1, 8, 'TKunde'),
    TAtlasHideScope.Everywhere, Code, '', Plan, Refusal));
  Assert.IsTrue(Plan.Kind = TAtlasHideKind.Setting);
  Assert.AreEqual('BlockEndLabels', Plan.SettingKey);
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.BlockEndLabels);
  Assert.IsTrue(TAtlasHide.SwitchOff(Settings, Plan.SettingKey, Old));
  Assert.IsFalse(Settings.BlockEndLabels);
  Assert.IsFalse(TAtlasHide.IsOn(Settings, Plan.SettingKey));
  Assert.IsFalse(TAtlasHide.SwitchOff(Settings, Plan.SettingKey, Old), 'schon aus');
  Assert.IsTrue(TAtlasHide.Restore(Settings, 'BlockEndLabels', '1'));
  Assert.IsTrue(Settings.BlockEndLabels);
  // Textauswahl (Willkommensseite, „Neu in Atlas“): aus = "off", zurück auf den alten Wert.
  Assert.IsTrue(TAtlasHide.SwitchOff(Settings, 'WelcomePageWhatsNew', Old));
  Assert.AreEqual('afterUpdate', Old);
  Assert.AreEqual('off', Settings.WelcomePageWhatsNew);
  Assert.IsTrue(TAtlasHide.Restore(Settings, 'WelcomePageWhatsNew', Old));
  Assert.AreEqual('afterUpdate', Settings.WelcomePageWhatsNew);
  Assert.IsFalse(TAtlasHide.SwitchOff(Settings, 'GibtEsNicht', Old));
  Assert.IsFalse(TAtlasHide.Restore(Settings, 'GibtEsNicht', '1'));
end;

procedure TAtlasHideTests.InsertRevertsOnlyUnchangedText;
var
  Insert: TAtlasTextInsert;
  Text, Reverted: string;
begin
  Insert := TAtlasHide.SuppressLine(Code, 6, 'no-with');
  Text := Insert.ApplyTo(Code);
  Assert.IsTrue(Insert.RevertIn(Text, Reverted));
  Assert.AreEqual(Code, Reverted);
  Text := StringReplace(Text, 'lsp-ignore', 'lsp-IGNORE', []);
  Assert.IsFalse(Insert.RevertIn(Text, Reverted), 'inzwischen geändert');
  Assert.AreEqual(Text, Reverted);
end;

procedure TAtlasHideTests.TeamFileReadsAndChecksHidden;
var
  Team: TAtlasTeamSettings;
  Issue: TAtlasTeamIssue;
  Paths: string;
begin
  Team := TAtlasTeamFile.Parse('{"version": 1, "hidden": [' +
    '{"setting": "BlockEndLabels", "file": "Source/Kunde.pas", "anchor": "TKunde.Speichern"},' +
    '{"setting": "InlayHints", "file": "Source\\Kunde.pas"},' +
    '{"setting": "Notes", "file": "C:\\Fremd\\A.pas"},' +
    '{"setting": "Notes", "file": "../../Fremd/A.pas"},' +
    '{"file": "A.pas"},' +
    '{"setting": "Notes", "file": "A.pas", "zeile": 3},' +
    '"kein Objekt"]}', 'C:\Repo\App\.atlas', 'C:\Repo');
  Assert.IsTrue(Team.Valid);
  Assert.AreEqual(3, Integer(Length(Team.Hidden)));
  Assert.AreEqual('BlockEndLabels', Team.Hidden[0].Setting);
  Assert.AreEqual('TKunde.Speichern', Team.Hidden[0].Anchor);
  Assert.AreEqual('Source/Kunde.pas', Team.Hidden[1].FileName, 'Trenner "/"');
  Assert.IsTrue(Team.Hidden[1].WholeFile);
  Assert.AreEqual('A.pas', Team.Hidden[2].FileName);
  Paths := '';
  for Issue in Team.Issues do
    Paths := Paths + Issue.Path + '|';
  Assert.Contains(Paths, 'hidden[2].file');
  Assert.Contains(Paths, 'hidden[3].file');
  Assert.Contains(Paths, 'hidden[4]');
  Assert.Contains(Paths, 'hidden[5].zeile');
  Assert.Contains(Paths, 'hidden[6]');
  Assert.IsTrue(Team.HasValues);
  Team := TAtlasTeamFile.Parse('{"version": 1, "hidden": {}}', 'C:\Repo\App\.atlas', 'C:\Repo');
  Assert.AreEqual(0, Integer(Length(Team.Hidden)));
  Assert.AreEqual(1, Integer(Length(Team.Issues)));
end;

procedure TAtlasHideTests.AddAndRemoveKeepTheRestOfTheFile;
var
  Text, Changed: string;
  Place, Second: TAtlasHiddenPlace;
  Team: TAtlasTeamSettings;
begin
  // Neue Datei aus dem Gerüst: gültig, ohne Meldungen, Kommentare bleiben.
  Place := TAtlasHiddenPlace.Create('BlockEndLabels', 'Source\Kunde.pas', 'TKunde.Speichern');
  Changed := TAtlasHiddenPlaces.AddTo('', TAtlasTeamFile.Skeleton, Place);
  Team := TAtlasTeamFile.Parse(Changed, 'C:\Repo\App\.atlas', 'C:\Repo');
  Assert.IsTrue(Team.Valid);
  Assert.AreEqual(0, Integer(Length(Team.Issues)));
  Assert.AreEqual(1, Integer(Length(Team.Hidden)));
  Assert.AreEqual('Source/Kunde.pas', Team.Hidden[0].FileName);
  Assert.Contains(Changed, '// Projekteinstellungen von Atlas');
  // Vorhandene Datei: übrige Werte und Kommentare bleiben, doppelter Eintrag entfällt.
  Text := '{' + #13#10 + '  // Team' + #13#10 + '  "version": 1,' + #13#10 + '  "sqlTargets": ["TQ.SQL"]' + #13#10 +
    '}' + #13#10;
  Changed := TAtlasHiddenPlaces.AddTo(Text, TAtlasTeamFile.Skeleton, Place);
  Assert.AreEqual(Changed, TAtlasHiddenPlaces.AddTo(Changed, TAtlasTeamFile.Skeleton, Place), 'schon drin');
  Second := TAtlasHiddenPlace.Create('InlayHints', 'Source/Kunde.pas', '');
  Changed := TAtlasHiddenPlaces.AddTo(Changed, TAtlasTeamFile.Skeleton, Second);
  Assert.Contains(Changed, '// Team');
  Assert.Contains(Changed, '"sqlTargets": ["TQ.SQL"]');
  Team := TAtlasTeamFile.Parse(Changed, 'C:\Repo\App\.atlas', 'C:\Repo');
  Assert.AreEqual(0, Integer(Length(Team.Issues)));
  Assert.AreEqual(2, Integer(Length(Team.Hidden)));
  Assert.AreEqual(1, Integer(Length(Team.SqlTargets)));
  // Rückgängig: genau der Eintrag fällt weg.
  Changed := TAtlasHiddenPlaces.RemoveFrom(Changed, Place);
  Team := TAtlasTeamFile.Parse(Changed, 'C:\Repo\App\.atlas', 'C:\Repo');
  Assert.AreEqual(1, Integer(Length(Team.Hidden)));
  Assert.AreEqual('InlayHints', Team.Hidden[0].Setting);
  Changed := TAtlasHiddenPlaces.RemoveFrom(Changed, Second);
  Assert.AreEqual(0, Integer(Length(TAtlasHiddenPlaces.FromText(Changed))));
  Assert.AreEqual(Changed, TAtlasHiddenPlaces.RemoveFrom(Changed, Second), 'fehlt schon');
end;

procedure TAtlasHideTests.IndexAnswersHiddenQuickly;
var
  Index: TAtlasHiddenIndex;
begin
  Index := TAtlasHiddenIndex.Create([TAtlasHiddenPlace.Create('BlockEndLabels', 'Source/Kunde.pas', 'TKunde.Speichern'),
    TAtlasHiddenPlace.Create('InlayHints', 'source/kunde.pas', '')], Folder);
  try
    Assert.IsFalse(Index.IsEmpty);
    Assert.IsTrue(Index.Hidden('BlockEndLabels', Unit1, 'TKunde.Speichern'));
    Assert.IsFalse(Index.Hidden('BlockEndLabels', Unit1, 'TKunde.Laden'));
    Assert.IsFalse(Index.FileHidden('BlockEndLabels', Unit1));
    Assert.IsTrue(Index.FileHidden('inlayhints', Unit1));
    Assert.IsTrue(Index.Hidden('InlayHints', 'c:\repo\app\SOURCE\Kunde.pas', 'egal'));
    Assert.IsFalse(Index.Hidden('InlayHints', 'C:\Repo\App\Source\Andere.pas', ''));
    Assert.IsFalse(Index.Hidden('InlayHints', 'C:\Anderswo\Source\Kunde.pas', ''));
  finally
    Index.Free;
  end;
  Index := TAtlasHiddenIndex.Create([TAtlasHiddenPlace.Create('Notes', 'A.pas', '')], '');
  try
    Assert.IsTrue(Index.IsEmpty, 'ohne Ordner wirkt nichts');
  finally
    Index.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasHideTests);

end.
