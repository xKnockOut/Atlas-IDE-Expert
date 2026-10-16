unit Atlas.Core.Welcome.Setup.Tests;

// Tests für die Einrichtungskarte der Willkommensseite (#759): wann Karte und
// Knöpfe „Neu mit Atlas“ erscheinen, Laufzeit, Zeilen der Pfadprüfung und
// Pfade relativ zum Projekt, unsichere Funde mit Makros und die
// Zusammenfassung einer Projektgruppe.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasWelcomeSetupTests = class
  public
    [Test]
    procedure CardOnlyWhileSetupIsOpen;
    [Test]
    procedure SettingsSwitchCardAndButtons;
    [Test]
    procedure CountsElapsedSeconds;
    [Test]
    procedure ListsFindingsUnitsFirst;
    [Test]
    procedure MakesPathsRelative;
    [Test]
    procedure CardStepsFollowFacts;
    /// <summary>Abnahme: Ein fehlender Suchpfad wird mit dem Unit-Namen gemeldet (Abschnitt "setup").</summary>
    [Test]
    procedure CheckedKeepsDismissAndLimits;
    /// <summary>Abnahme: Nach der Baseline sind die neuen Treffer 0.</summary>
    [Test]
    procedure BaselineClearsNewHits;
    /// <summary>Unbekanntes Makro: Funde unsicher, mit Makro in der Zeile; der Schritt gilt als erledigt.
    /// </summary>
    [Test]
    procedure UncertainFindingsNameTheMacro;
    [Test]
    procedure ListsMacrosShortly;
    /// <summary>Projektgruppe: Funde je Projekt, die Karte fasst sie zusammen.</summary>
    [Test]
    procedure CombinesGroupMembers;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Projects.Setup,
  Atlas.Core.Projects.PathCheck,
  Atlas.Core.Welcome.Setup;

function Facts(AConfig, ABaseline, AClean: Boolean): TAtlasSetupFacts;
begin
  Result := Default(TAtlasSetupFacts);
  Result.Project := 'C:\Projekte\XmlInspector\XmlInspector.dproj';
  Result.ConfigExists := AConfig;
  Result.BaselineExists := ABaseline;
  Result.Setup := TAtlasProjectSetup.Empty;
  Result.Setup.Checked := AClean;
end;

function Finding(const AName, AFile: string; ALine, ACount: Integer): TAtlasSetupFinding;
begin
  Result := Default(TAtlasSetupFinding);
  Result.Name := AName;
  Result.FileName := AFile;
  Result.Line := ALine;
  Result.Count := ACount;
end;

{ TAtlasWelcomeSetupTests }

procedure TAtlasWelcomeSetupTests.CardOnlyWhileSetupIsOpen;
var
  Dismissed: TAtlasSetupFacts;
begin
  Assert.IsTrue(TAtlasWelcomeSetup.ShowCard(True, Facts(False, False, False)), 'keine atlas.json');
  Assert.IsTrue(TAtlasWelcomeSetup.ShowCard(True, Facts(True, False, False)), 'Schritt offen');
  Assert.IsFalse(TAtlasWelcomeSetup.ShowCard(True, Facts(True, True, True)), 'vollständig eingerichtet');
  Dismissed := Facts(False, False, False);
  Dismissed.Setup.Dismissed := True;
  Assert.IsFalse(TAtlasWelcomeSetup.ShowCard(True, Dismissed), 'nicht mehr fragen');
end;

procedure TAtlasWelcomeSetupTests.SettingsSwitchCardAndButtons;
begin
  // projectSetup aus schaltet alles ab, newFromTemplate aus nur die Knöpfe.
  Assert.IsFalse(TAtlasWelcomeSetup.ShowCard(False, Facts(False, False, False)));
  Assert.IsFalse(TAtlasWelcomeSetup.ShowNew(False, True, True));
  Assert.IsFalse(TAtlasWelcomeSetup.ShowNew(True, False, True));
  Assert.IsTrue(TAtlasWelcomeSetup.ShowCard(True, Facts(False, False, False)));
  Assert.IsTrue(TAtlasWelcomeSetup.ShowNew(True, True, True));
  // Neue Dateien brauchen ein offenes Projekt.
  Assert.IsFalse(TAtlasWelcomeSetup.ShowNew(True, True, False));
end;

procedure TAtlasWelcomeSetupTests.CountsElapsedSeconds;
begin
  Assert.AreEqual(12, TAtlasWelcomeSetup.Elapsed(1000, 13999));
  Assert.AreEqual(0, TAtlasWelcomeSetup.Elapsed(0, 5000), 'nicht gestartet');
  Assert.AreEqual(0, TAtlasWelcomeSetup.Elapsed(5000, 1000));
end;

procedure TAtlasWelcomeSetupTests.ListsFindingsUnitsFirst;
var
  Setup: TAtlasProjectSetup;
  Lines: TArray<TAtlasSetupLine>;
  More: Integer;
begin
  Setup := TAtlasProjectSetup.Empty;
  Lines := TAtlasWelcomeSetup.Lines(Setup, 6, More);
  Assert.AreEqual(0, Integer(Length(Lines)), 'ohne Prüfung keine Zeilen');
  Setup.Checked := True;
  Setup.MissingUnits := [Finding('Xml.Helpers', 'Src\Main.pas', 12, 2), Finding('Legacy', 'App.dpr', 4, 1)];
  Setup.MissingUnitCount := 5;
  Setup.UndefinedDefines := [Finding('USE_LOG', 'App.dpr', 3, 1)];
  Setup.UndefinedDefineCount := 1;
  Lines := TAtlasWelcomeSetup.Lines(Setup, 6, More);
  Assert.AreEqual(3, Integer(Length(Lines)));
  Assert.IsTrue(Lines[0].Kind = TAtlasSetupFindingKind.MissingUnit);
  Assert.AreEqual('Xml.Helpers', Lines[0].Name, 'fehlende Unit mit Namen');
  Assert.AreEqual('Src\Main.pas', Lines[0].FileName);
  Assert.AreEqual(12, Lines[0].Line);
  Assert.AreEqual(2, Lines[0].Count);
  Assert.IsTrue(Lines[2].Kind = TAtlasSetupFindingKind.UndefinedDefine);
  // Drei weitere Units stehen nur in der Zahl.
  Assert.AreEqual(3, More);
  Lines := TAtlasWelcomeSetup.Lines(Setup, 2, More);
  Assert.AreEqual(2, Integer(Length(Lines)));
  Assert.AreEqual(4, More);
end;

procedure TAtlasWelcomeSetupTests.MakesPathsRelative;
begin
  Assert.AreEqual('Src\Main.pas', TAtlasWelcomeSetup.Relative('C:\P\App.dproj', 'c:\p\Src\Main.pas'));
  Assert.AreEqual('D:\Lib\X.pas', TAtlasWelcomeSetup.Relative('C:\P\App.dproj', 'D:\Lib\X.pas'));
  Assert.AreEqual('X.pas', TAtlasWelcomeSetup.Relative('', 'X.pas'));
  Assert.AreEqual('XmlInspector', TAtlasWelcomeSetup.NameOf('C:\Projekte\XmlInspector\XmlInspector.dproj'));
  Assert.AreEqual('Alle', TAtlasWelcomeSetup.NameOf('C:\Projekte\Alle.groupproj'));
end;

procedure TAtlasWelcomeSetupTests.CardStepsFollowFacts;
var
  Card: TAtlasSetupCard;
begin
  Card := TAtlasSetupCard.Empty;
  Assert.IsFalse(Card.Visible);
  Assert.IsFalse(Card.StepDone(TAtlasSetupStep.Found));
  Card.Facts := Facts(True, False, False);
  Card.ShowCard := True;
  Assert.IsTrue(Card.Visible);
  Assert.IsTrue(Card.StepDone(TAtlasSetupStep.Found));
  Assert.IsTrue(Card.StepDone(TAtlasSetupStep.Config), 'Datei liegt neben der .dproj: Schritt 2 abgehakt');
  Assert.IsFalse(Card.StepDone(TAtlasSetupStep.Baseline));
  Card.ShowCard := False;
  Card.ShowNew := True;
  Assert.IsTrue(Card.Visible, 'nur Knöpfe');
end;

function PathFinding(const AName, AFile: string; ALine, ACount: Integer): TAtlasPathFinding;
begin
  Result := Default(TAtlasPathFinding);
  Result.Name := AName;
  Result.FileName := AFile;
  Result.Line := ALine;
  Result.Count := ACount;
end;

procedure TAtlasWelcomeSetupTests.CheckedKeepsDismissAndLimits;
var
  Previous, Setup: TAtlasProjectSetup;
  Check: TAtlasPathCheckResult;
  Index: Integer;
  Stamp: TDateTime;
  Card: TAtlasSetupCard;
begin
  Previous := TAtlasProjectSetup.Empty;
  Previous.Known := True;
  Previous.Dismissed := True;
  Check := Default(TAtlasPathCheckResult);
  Check.Files := 7;
  Check.Unreadable := 1;
  Check.MissingUnits := [PathFinding('Xml.Helpers', 'C:\Projekte\XmlInspector\Src\Main.pas', 12, 3)];
  for Index := 1 to TAtlasProjectSetup.MaxFindings + 4 do
    Check.UndefinedDefines := Check.UndefinedDefines + [PathFinding('SYM' + IntToStr(Index),
      'D:\Fremd\Lib.pas', Index, 1)];
  Stamp := EncodeDate(2026, 10, 16);
  Setup := TAtlasWelcomeSetup.Checked(Previous, 'C:\Projekte\XmlInspector\XmlInspector.dproj', Check, Stamp);
  Assert.IsTrue(Setup.Dismissed, '„nicht mehr fragen“ bleibt');
  Assert.IsTrue(Setup.Checked);
  Assert.IsTrue(Setup.CheckedAt = Stamp);
  Assert.AreEqual(7, Setup.Files);
  Assert.AreEqual(1, Setup.Unreadable);
  Assert.AreEqual(1, Setup.MissingUnitCount);
  Assert.AreEqual(TAtlasProjectSetup.MaxFindings + 4, Setup.UndefinedDefineCount);
  Assert.AreEqual(TAtlasProjectSetup.MaxFindings, Integer(Length(Setup.UndefinedDefines)));
  Assert.AreEqual('Xml.Helpers', Setup.MissingUnits[0].Name);
  Assert.AreEqual('Src\Main.pas', Setup.MissingUnits[0].FileName, 'relativ zum Projekt');
  Assert.AreEqual('D:\Fremd\Lib.pas', Setup.UndefinedDefines[0].FileName, 'außerhalb bleibt der Pfad');
  Assert.AreEqual(3, Setup.MissingUnits[0].Count);
  Assert.IsFalse(Setup.PathsClean);
  // Schritt 4 bleibt offen; die Karte nennt die Unit.
  Card := TAtlasSetupCard.Empty;
  Card.Facts := Facts(True, True, False);
  Card.Facts.Setup := Setup;
  Assert.IsFalse(Card.StepDone(TAtlasSetupStep.Paths));
  // Saubere Prüfung: Schritt 4 erledigt.
  Setup := TAtlasWelcomeSetup.Checked(Setup, 'C:\Projekte\XmlInspector\XmlInspector.dproj',
    Default(TAtlasPathCheckResult), Stamp);
  Assert.IsTrue(Setup.PathsClean);
  Assert.AreEqual(0, Integer(Length(Setup.MissingUnits)));
  Card.Facts.Setup := Setup;
  Assert.IsTrue(Card.StepDone(TAtlasSetupStep.Paths));
end;

procedure TAtlasWelcomeSetupTests.BaselineClearsNewHits;
var
  Rules: TAtlasProjectRules;
  Stamp: TDateTime;
begin
  Rules := TAtlasProjectRules.Empty;
  Rules.Known := True;
  Rules.NewHits := 17;
  Stamp := EncodeDate(2026, 10, 16);
  TAtlasWelcomeSetup.BaselineWritten(Rules, Stamp);
  Assert.IsTrue(Rules.Known);
  Assert.AreEqual(0, Rules.NewHits);
  Assert.IsTrue(Rules.At = Stamp);
  Assert.AreEqual(-1, TAtlasSetupCard.Empty.BaselineNewHits, 'ohne Zusammenfassung unbekannt');
end;

procedure TAtlasWelcomeSetupTests.UncertainFindingsNameTheMacro;
var
  Check: TAtlasPathCheckResult;
  Setup: TAtlasProjectSetup;
  Lines: TArray<TAtlasSetupLine>;
  More: Integer;
  Missing: TAtlasPathFinding;
begin
  Missing := PathFinding('Lib.Core', 'C:\Projekte\App\App.dpr', 3, 1);
  Missing.Uncertain := True;
  Check := Default(TAtlasPathCheckResult);
  Check.Files := 2;
  Check.MissingUnits := [Missing];
  Check.SkippedMacros := ['MYLIB', 'TOOLS'];
  Setup := TAtlasWelcomeSetup.Checked(TAtlasProjectSetup.Empty, 'C:\Projekte\App\App.dproj', Check, Now);
  Assert.AreEqual(1, Setup.MissingUnitCount);
  Assert.AreEqual(1, Setup.UncertainUnitCount);
  Assert.AreEqual('MYLIB|TOOLS', string.Join('|', Setup.SkippedMacros));
  Assert.IsTrue(Setup.MissingUnits[0].Uncertain);
  // Kein sicherer Fund: Schritt 4 erledigt.
  Assert.IsTrue(Setup.PathsClean);
  Lines := TAtlasWelcomeSetup.Lines(Setup, 6, More);
  Assert.AreEqual(1, Integer(Length(Lines)));
  Assert.IsTrue(Lines[0].Uncertain);
  Assert.AreEqual('$(MYLIB), $(TOOLS)', Lines[0].Macros);
  // Ein sicherer Fund dazu: Schritt offen, die sichere Zeile ohne Makro.
  Check.UndefinedDefines := [PathFinding('USE_X', 'C:\Projekte\App\App.dpr', 4, 1)];
  Setup := TAtlasWelcomeSetup.Checked(Setup, 'C:\Projekte\App\App.dproj', Check, Now);
  Assert.IsFalse(Setup.PathsClean);
  Lines := TAtlasWelcomeSetup.Lines(Setup, 6, More);
  Assert.IsFalse(Lines[1].Uncertain);
  Assert.AreEqual('', Lines[1].Macros);
end;

procedure TAtlasWelcomeSetupTests.ListsMacrosShortly;
begin
  Assert.AreEqual('', TAtlasWelcomeSetup.MacroList(nil));
  Assert.AreEqual('$(A)', TAtlasWelcomeSetup.MacroList(['A']));
  Assert.AreEqual('$(A), $(B), $(C), …', TAtlasWelcomeSetup.MacroList(['A', 'B', 'C', 'D']));
end;

procedure TAtlasWelcomeSetupTests.CombinesGroupMembers;
var
  Group, Combined: TAtlasProjectSetup;
  App, Lib: TAtlasSetupMember;
  Checked, More: Integer;
  Lines: TArray<TAtlasSetupLine>;
begin
  Assert.IsTrue(TAtlasWelcomeSetup.IsGroup('C:\G\Alle.GROUPPROJ'));
  Assert.IsFalse(TAtlasWelcomeSetup.IsGroup('C:\G\App.dproj'));
  Group := TAtlasProjectSetup.Empty;
  Group.Known := True;
  Group.Dismissed := True;
  App.Project := 'C:\G\App\App.dproj';
  App.Setup := TAtlasProjectSetup.Empty;
  App.Setup.Checked := True;
  App.Setup.CheckedAt := EncodeDate(2026, 10, 15);
  App.Setup.Files := 4;
  App.Setup.MissingUnitCount := 1;
  App.Setup.MissingUnits := [Finding('Helpers', 'Src\Main.pas', 7, 1)];
  Lib.Project := 'C:\G\Lib\Lib.dproj';
  Lib.Setup := TAtlasProjectSetup.Empty;
  // Lib noch nicht geprüft: Schritt offen, Funde von App schon in der Karte.
  Combined := TAtlasWelcomeSetup.Combined('C:\G\Alle.groupproj', Group, [App, Lib], Checked);
  Assert.AreEqual(1, Checked);
  Assert.IsTrue(Combined.Dismissed, '„nicht mehr fragen“ der Gruppe');
  Assert.IsFalse(Combined.Checked);
  Assert.IsFalse(Combined.PathsClean);
  Lines := TAtlasWelcomeSetup.Lines(Combined, 6, More);
  Assert.AreEqual(1, Integer(Length(Lines)));
  Assert.AreEqual('App', Lines[0].Project);
  Assert.AreEqual('App\Src\Main.pas', Lines[0].FileName, 'relativ zur Gruppe');
  // Beide geprüft: Zahlen summiert, Makros ohne Doppelte, jüngster Zeitpunkt.
  Lib.Setup.Checked := True;
  Lib.Setup.CheckedAt := EncodeDate(2026, 10, 16);
  Lib.Setup.Files := 3;
  Lib.Setup.UndefinedDefineCount := 2;
  Lib.Setup.UncertainDefineCount := 2;
  Lib.Setup.UndefinedDefines := [Finding('USE_X', 'Lib.pas', 2, 1)];
  Lib.Setup.UndefinedDefines[0].Uncertain := True;
  Lib.Setup.SkippedMacros := ['MYLIB'];
  App.Setup.SkippedMacros := ['mylib', 'TOOLS'];
  Combined := TAtlasWelcomeSetup.Combined('C:\G\Alle.groupproj', Group, [App, Lib], Checked);
  Assert.AreEqual(2, Checked);
  Assert.IsTrue(Combined.Checked);
  Assert.IsTrue(Combined.CheckedAt = EncodeDate(2026, 10, 16));
  Assert.AreEqual(7, Combined.Files);
  Assert.AreEqual(1, Combined.MissingUnitCount);
  Assert.AreEqual(2, Combined.UndefinedDefineCount);
  Assert.AreEqual(2, Combined.UncertainDefineCount);
  Assert.AreEqual('mylib|TOOLS', string.Join('|', Combined.SkippedMacros));
  Assert.AreEqual('Lib\Lib.pas', Combined.UndefinedDefines[0].FileName);
  Assert.AreEqual('Lib', Combined.UndefinedDefines[0].Project);
  Assert.IsFalse(Combined.PathsClean, 'App hat einen sicheren Fund');
  // Ohne den sicheren Fund in App: erledigt.
  App.Setup.MissingUnitCount := 0;
  App.Setup.MissingUnits := nil;
  Combined := TAtlasWelcomeSetup.Combined('C:\G\Alle.groupproj', Group, [App, Lib], Checked);
  Assert.IsTrue(Combined.PathsClean);
  // Eine Gruppe ohne Projekte gilt nie als geprüft.
  Combined := TAtlasWelcomeSetup.Combined('C:\G\Alle.groupproj', Group, nil, Checked);
  Assert.IsFalse(Combined.Checked);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeSetupTests);

end.
