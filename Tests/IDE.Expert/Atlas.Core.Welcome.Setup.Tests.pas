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
  [Category('Atlas.IDE.Welcome')]
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
  mDismissed: TAtlasSetupFacts;
begin
  Assert.IsTrue(TAtlasWelcomeSetup.ShowCard(True, Facts(False, False, False)), 'keine atlas.json');
  Assert.IsTrue(TAtlasWelcomeSetup.ShowCard(True, Facts(True, False, False)), 'Schritt offen');
  Assert.IsFalse(TAtlasWelcomeSetup.ShowCard(True, Facts(True, True, True)), 'vollständig eingerichtet');
  mDismissed := Facts(False, False, False);
  mDismissed.Setup.Dismissed := True;
  Assert.IsFalse(TAtlasWelcomeSetup.ShowCard(True, mDismissed), 'nicht mehr fragen');
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
  mSetup: TAtlasProjectSetup;
  mLines: TArray<TAtlasSetupLine>;
  mMore: Integer;
begin
  mSetup := TAtlasProjectSetup.Empty;
  mLines := TAtlasWelcomeSetup.Lines(mSetup, 6, mMore);
  Assert.AreEqual(0, Integer(Length(mLines)), 'ohne Prüfung keine Zeilen');
  mSetup.Checked := True;
  mSetup.MissingUnits := [Finding('Xml.Helpers', 'Src\Main.pas', 12, 2), Finding('Legacy', 'App.dpr', 4, 1)];
  mSetup.MissingUnitCount := 5;
  mSetup.UndefinedDefines := [Finding('USE_LOG', 'App.dpr', 3, 1)];
  mSetup.UndefinedDefineCount := 1;
  mLines := TAtlasWelcomeSetup.Lines(mSetup, 6, mMore);
  Assert.AreEqual(3, Integer(Length(mLines)));
  Assert.AreEqual<TAtlasSetupFindingKind>(TAtlasSetupFindingKind.MissingUnit, mLines[0].Kind);
  Assert.AreEqual('Xml.Helpers', mLines[0].Name, 'fehlende Unit mit Namen');
  Assert.AreEqual('Src\Main.pas', mLines[0].FileName);
  Assert.AreEqual(12, mLines[0].Line);
  Assert.AreEqual(2, Integer(mLines[0].Count));
  Assert.AreEqual<TAtlasSetupFindingKind>(TAtlasSetupFindingKind.UndefinedDefine, mLines[2].Kind);
  // Drei weitere Units stehen nur in der Zahl.
  Assert.AreEqual(3, mMore);
  mLines := TAtlasWelcomeSetup.Lines(mSetup, 2, mMore);
  Assert.AreEqual(2, Integer(Length(mLines)));
  Assert.AreEqual(4, mMore);
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
  mCard: TAtlasSetupCard;
begin
  mCard := TAtlasSetupCard.Empty;
  Assert.IsFalse(mCard.Visible);
  Assert.IsFalse(mCard.StepDone(TAtlasSetupStep.Found));
  mCard.Facts := Facts(True, False, False);
  mCard.ShowCard := True;
  Assert.IsTrue(mCard.Visible);
  Assert.IsTrue(mCard.StepDone(TAtlasSetupStep.Found));
  Assert.IsTrue(mCard.StepDone(TAtlasSetupStep.Config), 'Datei liegt neben der .dproj: Schritt 2 abgehakt');
  Assert.IsFalse(mCard.StepDone(TAtlasSetupStep.Baseline));
  mCard.ShowCard := False;
  mCard.ShowNew := True;
  Assert.IsTrue(mCard.Visible, 'nur Knöpfe');
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
  mPrevious, mSetup: TAtlasProjectSetup;
  mCheck: TAtlasPathCheckResult;
  mIndex: Integer;
  mStamp: TDateTime;
  mCard: TAtlasSetupCard;
begin
  mPrevious := TAtlasProjectSetup.Empty;
  mPrevious.Known := True;
  mPrevious.Dismissed := True;
  mCheck := Default(TAtlasPathCheckResult);
  mCheck.Files := 7;
  mCheck.Unreadable := 1;
  mCheck.MissingUnits := [PathFinding('Xml.Helpers', 'C:\Projekte\XmlInspector\Src\Main.pas', 12, 3)];
  for mIndex := 1 to TAtlasProjectSetup.cMaxFindings + 4 do
  begin
    mCheck.UndefinedDefines := mCheck.UndefinedDefines + [PathFinding('SYM' + IntToStr(mIndex),
      'D:\Fremd\Lib.pas', mIndex, 1)];
  end;
  mStamp := EncodeDate(2026, 10, 16);
  mSetup := TAtlasWelcomeSetup.Checked(mPrevious, 'C:\Projekte\XmlInspector\XmlInspector.dproj', mCheck, mStamp);
  Assert.IsTrue(mSetup.Dismissed, '„nicht mehr fragen“ bleibt');
  Assert.IsTrue(mSetup.Checked);
  Assert.AreEqual<TDateTime>(mStamp, mSetup.CheckedAt);
  Assert.AreEqual(7, mSetup.Files);
  Assert.AreEqual(1, mSetup.Unreadable);
  Assert.AreEqual(1, mSetup.MissingUnitCount);
  Assert.AreEqual(TAtlasProjectSetup.cMaxFindings + 4, mSetup.UndefinedDefineCount);
  Assert.AreEqual(TAtlasProjectSetup.cMaxFindings, Integer(Length(mSetup.UndefinedDefines)));
  Assert.AreEqual('Xml.Helpers', mSetup.MissingUnits[0].Name);
  Assert.AreEqual('Src\Main.pas', mSetup.MissingUnits[0].FileName, 'relativ zum Projekt');
  Assert.AreEqual('D:\Fremd\Lib.pas', mSetup.UndefinedDefines[0].FileName, 'außerhalb bleibt der Pfad');
  Assert.AreEqual(3, Integer(mSetup.MissingUnits[0].Count));
  Assert.IsFalse(mSetup.PathsClean);
  // Schritt 4 bleibt offen; die Karte nennt die Unit.
  mCard := TAtlasSetupCard.Empty;
  mCard.Facts := Facts(True, True, False);
  mCard.Facts.Setup := mSetup;
  Assert.IsFalse(mCard.StepDone(TAtlasSetupStep.Paths));
  // Saubere Prüfung: Schritt 4 erledigt.
  mSetup := TAtlasWelcomeSetup.Checked(mSetup, 'C:\Projekte\XmlInspector\XmlInspector.dproj',
    Default(TAtlasPathCheckResult), mStamp);
  Assert.IsTrue(mSetup.PathsClean);
  Assert.AreEqual(0, Integer(Length(mSetup.MissingUnits)));
  mCard.Facts.Setup := mSetup;
  Assert.IsTrue(mCard.StepDone(TAtlasSetupStep.Paths));
end;

procedure TAtlasWelcomeSetupTests.BaselineClearsNewHits;
var
  mRules: TAtlasProjectRules;
  mStamp: TDateTime;
begin
  mRules := TAtlasProjectRules.Empty;
  mRules.Known := True;
  mRules.NewHits := 17;
  mStamp := EncodeDate(2026, 10, 16);
  TAtlasWelcomeSetup.BaselineWritten(mRules, mStamp);
  Assert.IsTrue(mRules.Known);
  Assert.AreEqual(0, mRules.NewHits);
  Assert.AreEqual<TDateTime>(mStamp, mRules.At);
  Assert.AreEqual(-1, TAtlasSetupCard.Empty.BaselineNewHits, 'ohne Zusammenfassung unbekannt');
end;

procedure TAtlasWelcomeSetupTests.UncertainFindingsNameTheMacro;
var
  mCheck: TAtlasPathCheckResult;
  mSetup: TAtlasProjectSetup;
  mLines: TArray<TAtlasSetupLine>;
  mMore: Integer;
  mMissing: TAtlasPathFinding;
begin
  mMissing := PathFinding('Lib.Core', 'C:\Projekte\App\App.dpr', 3, 1);
  mMissing.Uncertain := True;
  mCheck := Default(TAtlasPathCheckResult);
  mCheck.Files := 2;
  mCheck.MissingUnits := [mMissing];
  mCheck.SkippedMacros := ['MYLIB', 'TOOLS'];
  mSetup := TAtlasWelcomeSetup.Checked(TAtlasProjectSetup.Empty, 'C:\Projekte\App\App.dproj', mCheck, Now);
  Assert.AreEqual(1, mSetup.MissingUnitCount);
  Assert.AreEqual(1, mSetup.UncertainUnitCount);
  Assert.AreEqual('MYLIB|TOOLS', string.Join('|', mSetup.SkippedMacros));
  Assert.IsTrue(mSetup.MissingUnits[0].Uncertain);
  // Kein sicherer Fund: Schritt 4 erledigt.
  Assert.IsTrue(mSetup.PathsClean);
  mLines := TAtlasWelcomeSetup.Lines(mSetup, 6, mMore);
  Assert.AreEqual(1, Integer(Length(mLines)));
  Assert.IsTrue(mLines[0].Uncertain);
  Assert.AreEqual('$(MYLIB), $(TOOLS)', mLines[0].Macros);
  // Ein sicherer Fund dazu: Schritt offen, die sichere Zeile ohne Makro.
  mCheck.UndefinedDefines := [PathFinding('USE_X', 'C:\Projekte\App\App.dpr', 4, 1)];
  mSetup := TAtlasWelcomeSetup.Checked(mSetup, 'C:\Projekte\App\App.dproj', mCheck, Now);
  Assert.IsFalse(mSetup.PathsClean);
  mLines := TAtlasWelcomeSetup.Lines(mSetup, 6, mMore);
  Assert.IsFalse(mLines[1].Uncertain);
  Assert.AreEqual('', mLines[1].Macros);
end;

procedure TAtlasWelcomeSetupTests.ListsMacrosShortly;
begin
  Assert.AreEqual('', TAtlasWelcomeSetup.MacroList(nil));
  Assert.AreEqual('$(A)', TAtlasWelcomeSetup.MacroList(['A']));
  Assert.AreEqual('$(A), $(B), $(C), …', TAtlasWelcomeSetup.MacroList(['A', 'B', 'C', 'D']));
end;

procedure TAtlasWelcomeSetupTests.CombinesGroupMembers;
var
  mGroup, mCombined: TAtlasProjectSetup;
  mApp, mLib: TAtlasSetupMember;
  mChecked, mMore: Integer;
  mLines: TArray<TAtlasSetupLine>;
begin
  Assert.IsTrue(TAtlasWelcomeSetup.IsGroup('C:\G\Alle.GROUPPROJ'));
  Assert.IsFalse(TAtlasWelcomeSetup.IsGroup('C:\G\App.dproj'));
  mGroup := TAtlasProjectSetup.Empty;
  mGroup.Known := True;
  mGroup.Dismissed := True;
  mApp.Project := 'C:\G\App\App.dproj';
  mApp.Setup := TAtlasProjectSetup.Empty;
  mApp.Setup.Checked := True;
  mApp.Setup.CheckedAt := EncodeDate(2026, 10, 15);
  mApp.Setup.Files := 4;
  mApp.Setup.MissingUnitCount := 1;
  mApp.Setup.MissingUnits := [Finding('Helpers', 'Src\Main.pas', 7, 1)];
  mLib.Project := 'C:\G\Lib\Lib.dproj';
  mLib.Setup := TAtlasProjectSetup.Empty;
  // Lib noch nicht geprüft: Schritt offen, Funde von App schon in der Karte.
  mCombined := TAtlasWelcomeSetup.Combined('C:\G\Alle.groupproj', mGroup, [mApp, mLib], mChecked);
  Assert.AreEqual(1, mChecked);
  Assert.IsTrue(mCombined.Dismissed, '„nicht mehr fragen“ der Gruppe');
  Assert.IsFalse(mCombined.Checked);
  Assert.IsFalse(mCombined.PathsClean);
  mLines := TAtlasWelcomeSetup.Lines(mCombined, 6, mMore);
  Assert.AreEqual(1, Integer(Length(mLines)));
  Assert.AreEqual('App', mLines[0].Project);
  Assert.AreEqual('App\Src\Main.pas', mLines[0].FileName, 'relativ zur Gruppe');
  // Beide geprüft: Zahlen summiert, Makros ohne Doppelte, jüngster Zeitpunkt.
  mLib.Setup.Checked := True;
  mLib.Setup.CheckedAt := EncodeDate(2026, 10, 16);
  mLib.Setup.Files := 3;
  mLib.Setup.UndefinedDefineCount := 2;
  mLib.Setup.UncertainDefineCount := 2;
  mLib.Setup.UndefinedDefines := [Finding('USE_X', 'Lib.pas', 2, 1)];
  mLib.Setup.UndefinedDefines[0].Uncertain := True;
  mLib.Setup.SkippedMacros := ['MYLIB'];
  mApp.Setup.SkippedMacros := ['mylib', 'TOOLS'];
  mCombined := TAtlasWelcomeSetup.Combined('C:\G\Alle.groupproj', mGroup, [mApp, mLib], mChecked);
  Assert.AreEqual(2, mChecked);
  Assert.IsTrue(mCombined.Checked);
  Assert.AreEqual<TDateTime>(EncodeDate(2026, 10, 16), mCombined.CheckedAt);
  Assert.AreEqual(7, mCombined.Files);
  Assert.AreEqual(1, mCombined.MissingUnitCount);
  Assert.AreEqual(2, mCombined.UndefinedDefineCount);
  Assert.AreEqual(2, mCombined.UncertainDefineCount);
  Assert.AreEqual('mylib|TOOLS', string.Join('|', mCombined.SkippedMacros));
  Assert.AreEqual('Lib\Lib.pas', mCombined.UndefinedDefines[0].FileName);
  Assert.AreEqual('Lib', mCombined.UndefinedDefines[0].Project);
  Assert.IsFalse(mCombined.PathsClean, 'App hat einen sicheren Fund');
  // Ohne den sicheren Fund in App: erledigt.
  mApp.Setup.MissingUnitCount := 0;
  mApp.Setup.MissingUnits := nil;
  mCombined := TAtlasWelcomeSetup.Combined('C:\G\Alle.groupproj', mGroup, [mApp, mLib], mChecked);
  Assert.IsTrue(mCombined.PathsClean);
  // Eine Gruppe ohne Projekte gilt nie als geprüft.
  mCombined := TAtlasWelcomeSetup.Combined('C:\G\Alle.groupproj', mGroup, nil, mChecked);
  Assert.IsFalse(mCombined.Checked);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeSetupTests);

end.
