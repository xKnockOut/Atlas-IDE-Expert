unit Atlas.UI.Welcome.Setup.Tests;

// Tests der Einrichtungskarte der Willkommensseite.

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Bereich „&lt;Projekt&gt; für Atlas einrichten“ (#759).</summary>
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeSetupFrameTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure TextsFollowLanguage;
    /// <summary>Mockup #ws7: erledigte Schritte grün mit ✓ und ohne Knöpfe, offene mit Knopf.</summary>
    [Test]
    procedure StepsShowMarksAndButtons;
    /// <summary>Abnahme: Ein fehlender Suchpfad wird mit dem Unit-Namen gemeldet.</summary>
    [Test]
    procedure FindingNamesUnit;
    /// <summary>Unsichere Funde nennen das Makro; bei einer Gruppe das Projekt und den Stand der Prüfung.
    /// </summary>
    [Test]
    procedure UncertainAndGroupCaptions;
    /// <summary>Abnahme: Ohne Karte nur „Neu mit Atlas“; ohne beides nichts; ohne Projekt keine Knöpfe.</summary>
    [Test]
    procedure CardAndNewRowFollowCard;
    [Test]
    procedure ClicksReachSource;
    [Test]
    procedure RunningStepShowsSeconds;
    /// <summary>Vorschau zeigt den Inhalt vor dem Anlegen; Esc schreibt nichts.</summary>
    [Test]
    procedure PreviewShowsContent;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Strings,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Projects.Setup,
  Atlas.Core.Generate.FileTemplates,
  Atlas.Core.Welcome.Setup,
  Atlas.UI.Welcome.Setup,
  Atlas.UI.Welcome.SetupPreview;


type
  /// <summary>Quelle des Bereichs „Projekt für Atlas einrichten“ für die Tests; merkt sich die Aufrufe.</summary>
  TFakeSetup = class(TInterfacedObject, IAtlasSetupSource)
  public
    Card_: TAtlasSetupCard;
    Calls: TArray<string>;
    function Card: TAtlasSetupCard;
    procedure CreateConfig(ATemplate: TAtlasSetupTemplate);
    procedure StartBaseline;
    procedure CheckPaths;
    procedure OpenOptions;
    procedure OpenProject;
    procedure Dismiss;
    procedure NewFile(AKind: TAtlasNewFileKind);
  end;

{ TFakeSetup }

function TFakeSetup.Card: TAtlasSetupCard;
begin
  Result := Card_;
end;
procedure TFakeSetup.CreateConfig(ATemplate: TAtlasSetupTemplate);
begin
  Calls := Calls + ['config:' + TAtlasProjectSetups.TemplateId(ATemplate)];
end;
procedure TFakeSetup.StartBaseline;
begin
  Calls := Calls + ['baseline'];
end;
procedure TFakeSetup.CheckPaths;
begin
  Calls := Calls + ['paths'];
end;
procedure TFakeSetup.OpenOptions;
begin
  Calls := Calls + ['options'];
end;
procedure TFakeSetup.OpenProject;
begin
  Calls := Calls + ['open'];
end;
procedure TFakeSetup.Dismiss;
begin
  Calls := Calls + ['dismiss'];
end;
procedure TFakeSetup.NewFile(AKind: TAtlasNewFileKind);
begin
  Calls := Calls + ['new:' + TAtlasFileTemplates.KindWord(AKind)];
end;
/// <summary>Karte für XmlInspector: Projekt offen, keine atlas.json, keine Baseline, nicht geprüft.</summary>
function SetupCard: TAtlasSetupCard;
begin
  Result := TAtlasSetupCard.Empty;
  Result.Project := 'C:\Src\XmlInspector\XmlInspector.dproj';
  Result.ProjectName := 'XmlInspector';
  Result.ProjectOpen := True;
  Result.Facts.Project := Result.Project;
  Result.ShowCard := True;
  Result.ShowNew := True;
end;
function SetupFinding(const AName, AFileName: string; ALine, ACount: Integer): TAtlasSetupFinding;
begin
  Result := Default(TAtlasSetupFinding);
  Result.Name := AName;
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Count := ACount;
end;
{ TAtlasWelcomeSetupFrameTests }

procedure TAtlasWelcomeSetupFrameTests.WarmUpFirstUse;
begin
  PreviewShowsContent;
end;
procedure TAtlasWelcomeSetupFrameTests.TextsFollowLanguage;
var
  mSaved: TAtlasLanguage;
  mCard: TAtlasSetupCard;
begin
  mSaved := TAtlasStrings.Language;
  try
    mCard := SetupCard;
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('XmlInspector für Atlas einrichten', TAtlasSetupTexts.TitleText(mCard));
    Assert.AreEqual('Projekt gefunden, keine atlas.json',
      TAtlasSetupTexts.StepCaption(TAtlasSetupStep.Found, mCard, 0));
    Assert.AreEqual('atlas.json anlegen', TAtlasSetupTexts.StepCaption(TAtlasSetupStep.Config, mCard, 0));
    Assert.AreEqual('Baseline erzeugen', TAtlasSetupTexts.StepCaption(TAtlasSetupStep.Baseline, mCard, 0));
    Assert.AreEqual('Suchpfade und Defines prüfen',
      TAtlasSetupTexts.StepCaption(TAtlasSetupStep.Paths, mCard, 0));
    Assert.AreEqual('Bestehendes Projekt', TAtlasSetupTexts.TemplateCaption(TAtlasSetupTemplate.Existing));
    Assert.AreEqual('Neues Projekt, streng', TAtlasSetupTexts.TemplateCaption(TAtlasSetupTemplate.NewStrict));
    Assert.AreEqual('Altprojekt mit Baseline', TAtlasSetupTexts.TemplateCaption(TAtlasSetupTemplate.Legacy));
    Assert.AreEqual('Starten', TAtlasSetupTexts.ButtonCaption(TAtlasSetupButton.Baseline));
    Assert.AreEqual('Prüfen', TAtlasSetupTexts.ButtonCaption(TAtlasSetupButton.Paths));
    Assert.AreEqual('Für dieses Projekt nicht mehr fragen',
      TAtlasSetupTexts.ButtonCaption(TAtlasSetupButton.Dismiss));
    Assert.AreEqual('Testklasse', TAtlasSetupTexts.ButtonCaption(TAtlasSetupButton.NewTest));
    mCard.Facts.ConfigExists := True;
    mCard.ConfigName := 'atlas.json';
    Assert.AreEqual('Projekt gefunden', TAtlasSetupTexts.StepCaption(TAtlasSetupStep.Found, mCard, 0));
    Assert.AreEqual('atlas.json vorhanden', TAtlasSetupTexts.StepCaption(TAtlasSetupStep.Config, mCard, 0));
    mCard.ShowCard := False;
    Assert.AreEqual('Neu mit Atlas', TAtlasSetupTexts.TitleText(mCard));
    TAtlasStrings.Language := TAtlasLanguage.English;
    mCard.ShowCard := True;
    Assert.AreEqual('Set up XmlInspector for Atlas', TAtlasSetupTexts.TitleText(mCard));
    Assert.AreEqual('Test class', TAtlasSetupTexts.ButtonCaption(TAtlasSetupButton.NewTest));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;
/// <summary>Schritt 1 erledigt, Vorlage „Bestehendes Projekt“, Knöpfe rechts neben ihren Schritten.</summary>
procedure AssertSetupStartLayout(const AFrame: TAtlasWelcomeSetupFrame);
begin
  // Schritt 1 erledigt, die anderen offen.
  Assert.AreEqual(string(#$2713), AFrame.StepMark(TAtlasSetupStep.Found).Caption);
  Assert.AreEqual(Integer(TAtlasWelcomeSetupFrame.cDoneColor),
    Integer(AFrame.StepText(TAtlasSetupStep.Found).Font.Color));
  Assert.AreNotEqual(string(#$2713), AFrame.StepMark(TAtlasSetupStep.Config).Caption);
  Assert.IsTrue(AFrame.TemplateBox.Visible);
  Assert.IsTrue(AFrame.Button(TAtlasSetupButton.CreateConfig).Visible);
  Assert.IsTrue(AFrame.Button(TAtlasSetupButton.Baseline).Visible);
  Assert.IsTrue(AFrame.Button(TAtlasSetupButton.Paths).Visible);
  Assert.IsTrue(AFrame.DismissLabel.Visible);
  Assert.IsFalse(AFrame.Button(TAtlasSetupButton.Options).Visible, 'ohne Funde keine Projektoptionen');
  // Vorgabe der Vorlage: Bestehendes Projekt.
  Assert.IsTrue(AFrame.SelectedTemplate = TAtlasSetupTemplate.Existing);
  Assert.AreEqual(3, Integer(AFrame.TemplateBox.Items.Count));
  Assert.AreEqual(Integer(Ord(TAtlasSetupTemplate.Existing)), AFrame.TemplateBox.ItemIndex);
  // Knöpfe rechts neben dem Text ihres Schritts, Schritte untereinander.
  Assert.IsTrue(AFrame.Button(TAtlasSetupButton.CreateConfig).Left > AFrame.TemplateBox.Left);
  Assert.IsTrue(AFrame.TemplateBox.Left > AFrame.StepText(TAtlasSetupStep.Config).Left);
  Assert.IsTrue(AFrame.StepText(TAtlasSetupStep.Baseline).Top > AFrame.StepText(TAtlasSetupStep.Config).Top);
  Assert.IsTrue(AFrame.StepText(TAtlasSetupStep.Paths).Top > AFrame.StepText(TAtlasSetupStep.Baseline).Top);
  Assert.IsTrue(AFrame.DismissLabel.Top > AFrame.StepText(TAtlasSetupStep.Paths).Top);
end;
procedure TAtlasWelcomeSetupFrameTests.StepsShowMarksAndButtons;
var
  mHost: TForm;
  mFake: TFakeSetup;
  mSource: IAtlasSetupSource;
  mFrame: TAtlasWelcomeSetupFrame;
begin
  mFake := TFakeSetup.Create;
  mFake.Card_ := SetupCard;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasWelcomeSetupFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.SetBounds(0, 0, 640, 300);
    mFrame.Source := mSource;
    AssertSetupStartLayout(mFrame);
    // Abnahme: Nach „Anlegen“ ist Schritt 2 abgehakt; nach der Baseline Schritt 3 mit „neue Treffer: 0“.
    mFake.Card_.Facts.ConfigExists := True;
    mFake.Card_.ConfigName := 'atlas.json';
    mFake.Card_.Facts.BaselineExists := True;
    mFake.Card_.Baseline := TAtlasSetupRun.Done;
    mFake.Card_.BaselineTotal := 120;
    mFake.Card_.BaselineFiles := 14;
    mFake.Card_.BaselineNewHits := 0;
    mFrame.UpdateContent;
    Assert.AreEqual(string(#$2713), mFrame.StepMark(TAtlasSetupStep.Config).Caption);
    Assert.AreEqual(Integer(TAtlasWelcomeSetupFrame.cDoneColor),
      Integer(mFrame.StepText(TAtlasSetupStep.Config).Font.Color));
    Assert.IsFalse(mFrame.TemplateBox.Visible);
    Assert.IsFalse(mFrame.Button(TAtlasSetupButton.CreateConfig).Visible);
    Assert.AreEqual(string(#$2713), mFrame.StepMark(TAtlasSetupStep.Baseline).Caption);
    Assert.IsFalse(mFrame.Button(TAtlasSetupButton.Baseline).Visible);
    Assert.IsTrue(mFrame.BaselineInfo.Visible);
    Assert.AreEqual(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupBaselineResult, [120, 14, 0]),
      mFrame.BaselineInfo.Caption);
    Assert.Contains(mFrame.BaselineInfo.Caption, ': 0');
    // Ohne geöffnetes Projekt heißen die Knöpfe „Projekt öffnen“.
    mFake.Card_.Facts.BaselineExists := False;
    mFake.Card_.Baseline := TAtlasSetupRun.Idle;
    mFake.Card_.ProjectOpen := False;
    mFrame.UpdateContent;
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupOpenProject),
      mFrame.Button(TAtlasSetupButton.Baseline).Caption);
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupOpenProject),
      mFrame.Button(TAtlasSetupButton.Paths).Caption);
  finally
    mHost.Free;
  end;
end;
/// <summary>Beschriftung eines Fundes: fehlende Unit mit und ohne Anzahl, Define ohne Quelle.</summary>
procedure AssertSetupFindingCaptions;
var
  mLine: TAtlasSetupLine;
begin
  mLine := Default(TAtlasSetupLine);
  mLine.Kind := TAtlasSetupFindingKind.MissingUnit;
  mLine.Name := 'Xml.Helpers';
  mLine.FileName := 'Src\Main.pas';
  mLine.Line := 12;
  mLine.Count := 1;
  Assert.AreEqual('Unit „Xml.Helpers“ nicht gefunden – Src\Main.pas, Zeile 12',
    TAtlasSetupTexts.FindingCaption(mLine));
  mLine.Count := 3;
  Assert.AreEqual('Unit „Xml.Helpers“ nicht gefunden – Src\Main.pas, Zeile 12 (3×)',
    TAtlasSetupTexts.FindingCaption(mLine));
  mLine.Kind := TAtlasSetupFindingKind.UndefinedDefine;
  mLine.Name := 'USE_XML';
  mLine.Count := 1;
  Assert.AreEqual('Define „USE_XML“ ohne Quelle – Src\Main.pas, Zeile 12',
    TAtlasSetupTexts.FindingCaption(mLine));
end;
/// <summary>Einrichtungskarte mit 9 fehlenden Units und einem Define ohne Quelle.</summary>
function SetupCardWithFindings: TAtlasSetupCard;
var
  mIndex: Integer;
begin
  Result := SetupCard;
  Result.Facts.Setup.Known := True;
  Result.Facts.Setup.Checked := True;
  Result.Facts.Setup.Files := 12;
  Result.Facts.Setup.MissingUnitCount := 9;
  Result.Facts.Setup.UndefinedDefineCount := 1;
  Result.Facts.Setup.MissingUnits := [SetupFinding('Xml.Helpers', 'Src\Main.pas', 12, 3)];
  for mIndex := 2 to 9 do
  begin
    Result.Facts.Setup.MissingUnits := Result.Facts.Setup.MissingUnits +
      [SetupFinding('Unit' + IntToStr(mIndex), 'Src\Main.pas', 12 + mIndex, 1)];
  end;
  Result.Facts.Setup.UndefinedDefines := [SetupFinding('USE_XML', 'Src\Main.pas', 3, 1)];
  Result.Paths := TAtlasSetupRun.Done;
end;
procedure TAtlasWelcomeSetupFrameTests.FindingNamesUnit;
var
  mSaved: TAtlasLanguage;
  mHost: TForm;
  mFake: TFakeSetup;
  mSource: IAtlasSetupSource;
  mFrame: TAtlasWelcomeSetupFrame;
begin
  mSaved := TAtlasStrings.Language;
  mFake := TFakeSetup.Create;
  mFake.Card_ := SetupCardWithFindings;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    AssertSetupFindingCaptions;
    mFrame := TAtlasWelcomeSetupFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.SetBounds(0, 0, 640, 300);
    mFrame.Source := mSource;
    // Schritt 4 offen, Zusammenfassung, höchstens MaxLines Funde, der Rest als „… und n weitere“.
    Assert.AreNotEqual(string(#$2713), mFrame.StepMark(TAtlasSetupStep.Paths).Caption);
    Assert.IsTrue(mFrame.PathsInfo.Visible);
    Assert.AreEqual('9 Units nicht gefunden, 1 Defines ohne Quelle (12 Dateien geprüft)', mFrame.PathsInfo.Caption);
    Assert.IsTrue(mFrame.Finding(0).Visible);
    Assert.Contains(mFrame.Finding(0).Caption, 'Xml.Helpers');
    Assert.IsTrue(mFrame.Finding(TAtlasWelcomeSetup.cMaxLines - 1).Visible);
    Assert.IsTrue(mFrame.MoreLabel.Visible);
    Assert.AreEqual('… und 4 weitere', mFrame.MoreLabel.Caption);
    Assert.IsTrue(mFrame.Button(TAtlasSetupButton.Options).Visible);
    Assert.IsTrue(mFrame.Finding(0).Top > mFrame.StepText(TAtlasSetupStep.Paths).Top);
    // Ein Klick auf den Fund öffnet die Projektoptionen.
    mFrame.Finding(0).OnClick(mFrame.Finding(0));
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(mFake.Calls)));
    Assert.AreEqual('options', mFake.Calls[0]);
    // Saubere Prüfung: Schritt 4 grün, keine Funde.
    mFake.Card_.Facts.Setup.MissingUnitCount := 0;
    mFake.Card_.Facts.Setup.UndefinedDefineCount := 0;
    mFake.Card_.Facts.Setup.MissingUnits := nil;
    mFake.Card_.Facts.Setup.UndefinedDefines := nil;
    mFrame.UpdateContent;
    Assert.AreEqual(string(#$2713), mFrame.StepMark(TAtlasSetupStep.Paths).Caption);
    Assert.IsFalse(mFrame.Finding(0).Visible);
    Assert.IsFalse(mFrame.PathsInfo.Visible);
    Assert.IsFalse(mFrame.Button(TAtlasSetupButton.Options).Visible);
  finally
    mHost.Free;
    TAtlasStrings.Language := mSaved;
  end;
end;
procedure TAtlasWelcomeSetupFrameTests.UncertainAndGroupCaptions;
var
  mSaved: TAtlasLanguage;
  mLine: TAtlasSetupLine;
  mCard: TAtlasSetupCard;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mLine := Default(TAtlasSetupLine);
    mLine.Kind := TAtlasSetupFindingKind.MissingUnit;
    mLine.Name := 'Lib.Core';
    mLine.FileName := 'App\App.dpr';
    mLine.Line := 3;
    mLine.Count := 1;
    mLine.Uncertain := True;
    mLine.Macros := '$(MYLIB)';
    Assert.AreEqual('Unit „Lib.Core“ nicht gefunden (unsicher, Suchpfad mit unbekanntem Makro $(MYLIB) ' +
      'übersprungen) – App\App.dpr, Zeile 3', TAtlasSetupTexts.FindingCaption(mLine));
    mLine.Project := 'App';
    mLine.Kind := TAtlasSetupFindingKind.UndefinedDefine;
    mLine.Name := 'USE_LIB';
    Assert.AreEqual('App: Define „USE_LIB“ ohne Quelle (unsicher, Suchpfad mit unbekanntem Makro $(MYLIB) ' +
      'übersprungen) – App\App.dpr, Zeile 3', TAtlasSetupTexts.FindingCaption(mLine));
    mCard := SetupCard;
    mCard.GroupProjects := 3;
    mCard.GroupChecked := 1;
    mCard.Facts.Setup.MissingUnitCount := 2;
    mCard.Facts.Setup.UncertainUnitCount := 1;
    mCard.Facts.Setup.Files := 5;
    mCard.Facts.Setup.SkippedMacros := ['MYLIB'];
    Assert.AreEqual('1 von 3 Projekten der Gruppe geprüft' + sLineBreak +
      '2 Units nicht gefunden, 0 Defines ohne Quelle (5 Dateien geprüft)' + sLineBreak +
      'Davon unsicher: 1 (Suchpfad mit unbekanntem Makro $(MYLIB) übersprungen)',
      TAtlasSetupTexts.PathsCaption(mCard));
    // Fehler gehen vor.
    mCard.Paths := TAtlasSetupRun.Failed;
    mCard.PathsError := 'kaputt';
    Assert.AreEqual('kaputt', TAtlasSetupTexts.PathsCaption(mCard));
    // Einzelprojekt ohne Prüfung: nichts.
    Assert.AreEqual('', TAtlasSetupTexts.PathsCaption(SetupCard));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;
procedure TAtlasWelcomeSetupFrameTests.CardAndNewRowFollowCard;
var
  mHost: TForm;
  mFake: TFakeSetup;
  mSource: IAtlasSetupSource;
  mFrame: TAtlasWelcomeSetupFrame;
  mStep: TAtlasSetupStep;
  mFull: Integer;
begin
  mFake := TFakeSetup.Create;
  mFake.Card_ := SetupCard;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasWelcomeSetupFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.SetBounds(0, 0, 640, 300);
    mFrame.Source := mSource;
    Assert.IsTrue(mFrame.NewRowLabel.Visible);
    Assert.IsTrue(mFrame.Button(TAtlasSetupButton.NewUnit).Visible);
    Assert.IsTrue(mFrame.Button(TAtlasSetupButton.NewForm).Visible);
    Assert.IsTrue(mFrame.Button(TAtlasSetupButton.NewTest).Visible);
    Assert.IsTrue(mFrame.NewRowLabel.Top > mFrame.DismissLabel.Top, '„Neu mit Atlas“ unter der Karte');
    Assert.AreEqual(mFrame.Button(TAtlasSetupButton.NewUnit).Top, mFrame.Button(TAtlasSetupButton.NewTest).Top);
    mFull := mFrame.PreferredHeight;
    // Vollständig eingerichtet bzw. abgewählt: keine Karte, nur „Neu mit Atlas“.
    mFake.Card_.ShowCard := False;
    mFrame.UpdateContent;
    for mStep := Low(TAtlasSetupStep) to High(TAtlasSetupStep) do
    begin
      Assert.IsFalse(mFrame.StepText(mStep).Visible);
    end;
    Assert.IsFalse(mFrame.TemplateBox.Visible);
    Assert.IsFalse(mFrame.Button(TAtlasSetupButton.Baseline).Visible);
    Assert.IsFalse(mFrame.DismissLabel.Visible);
    Assert.IsTrue(mFrame.Button(TAtlasSetupButton.NewUnit).Visible);
    Assert.IsTrue(mFrame.PreferredHeight < mFull);
    // newFromTemplate aus: nur die Karte.
    mFake.Card_.ShowCard := True;
    mFake.Card_.ShowNew := False;
    mFrame.UpdateContent;
    Assert.IsTrue(mFrame.StepText(TAtlasSetupStep.Config).Visible);
    Assert.IsFalse(mFrame.NewRowLabel.Visible);
    Assert.IsFalse(mFrame.Button(TAtlasSetupButton.NewUnit).Visible);
    Assert.IsFalse(mFrame.Button(TAtlasSetupButton.NewTest).Visible);
    // Schmal: Knöpfe brechen um, der Bereich wird höher.
    mFull := mFrame.PreferredHeight;
    mFrame.Width := 200;
    mFrame.UpdateContent;
    Assert.IsTrue(mFrame.Button(TAtlasSetupButton.CreateConfig).Top > mFrame.StepText(TAtlasSetupStep.Config).Top);
    Assert.IsTrue(mFrame.PreferredHeight > mFull);
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeSetupFrameTests.ClicksReachSource;
var
  mHost: TForm;
  mFake: TFakeSetup;
  mSource: IAtlasSetupSource;
  mFrame: TAtlasWelcomeSetupFrame;
begin
  mFake := TFakeSetup.Create;
  mFake.Card_ := SetupCard;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasWelcomeSetupFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.SetBounds(0, 0, 640, 300);
    // Ohne Quelle geht nichts.
    mFrame.ClickButton(TAtlasSetupButton.CreateConfig);
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(mFake.Calls)));
    mFrame.Source := mSource;
    mFrame.SelectTemplate(TAtlasSetupTemplate.Legacy);
    mFrame.Button(TAtlasSetupButton.CreateConfig).Click;
    mFrame.Button(TAtlasSetupButton.Baseline).Click;
    mFrame.Button(TAtlasSetupButton.Paths).Click;
    mFrame.DismissLabel.OnClick(mFrame.DismissLabel);
    mFrame.Button(TAtlasSetupButton.NewUnit).Click;
    mFrame.Button(TAtlasSetupButton.NewForm).Click;
    mFrame.Button(TAtlasSetupButton.NewTest).Click;
    Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(7, Integer(Length(mFake.Calls)));
    Assert.AreEqual('config:legacy', mFake.Calls[0]);
    Assert.AreEqual('baseline', mFake.Calls[1]);
    Assert.AreEqual('paths', mFake.Calls[2]);
    Assert.AreEqual('dismiss', mFake.Calls[3]);
    Assert.AreEqual('new:unit', mFake.Calls[4]);
    Assert.AreEqual('new:form', mFake.Calls[5]);
    Assert.AreEqual('new:test', mFake.Calls[6]);
    // Projekt nicht offen: Baseline und Prüfung öffnen erst das Projekt.
    mFake.Calls := nil;
    mFake.Card_.ProjectOpen := False;
    mFrame.UpdateContent;
    mFrame.ClickButton(TAtlasSetupButton.Baseline);
    mFrame.ClickButton(TAtlasSetupButton.Paths);
    CheckSynchronize;
    Assert.AreEqual(2, Integer(Length(mFake.Calls)));
    Assert.AreEqual('open', mFake.Calls[0]);
    Assert.AreEqual('open', mFake.Calls[1]);
    // Unsichtbare Knöpfe tun nichts: Schritt 2 erledigt, keine Karte.
    mFake.Calls := nil;
    mFake.Card_.Facts.ConfigExists := True;
    mFake.Card_.ShowCard := False;
    mFrame.UpdateContent;
    mFrame.ClickButton(TAtlasSetupButton.CreateConfig);
    mFrame.ClickButton(TAtlasSetupButton.Dismiss);
    mFrame.ClickButton(TAtlasSetupButton.Options);
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(mFake.Calls)));
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeSetupFrameTests.RunningStepShowsSeconds;
var
  mSaved: TAtlasLanguage;
  mHost: TForm;
  mFake: TFakeSetup;
  mSource: IAtlasSetupSource;
  mFrame: TAtlasWelcomeSetupFrame;
  mCard: TAtlasSetupCard;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mCard := SetupCard;
    mCard.Baseline := TAtlasSetupRun.Running;
    mCard.BaselineStarted := 1000;
    Assert.AreEqual('Baseline wird erzeugt … 12 s',
      TAtlasSetupTexts.StepCaption(TAtlasSetupStep.Baseline, mCard, 13500));
    mCard.Paths := TAtlasSetupRun.Running;
    mCard.PathsStarted := 1000;
    Assert.AreEqual('Suchpfade und Defines werden geprüft … 2 s',
      TAtlasSetupTexts.StepCaption(TAtlasSetupStep.Paths, mCard, 3000));
    mFake := TFakeSetup.Create;
    mFake.Card_ := mCard;
    mFake.Card_.BaselineStarted := TThread.GetTickCount64;
    mFake.Card_.PathsStarted := TThread.GetTickCount64;
    mSource := mFake;
    mHost := TForm.CreateNew(nil);
    try
      mFrame := TAtlasWelcomeSetupFrame.Create(mHost);
      mFrame.Parent := mHost;
      mFrame.SetBounds(0, 0, 640, 300);
      mFrame.Source := mSource;
      // Laufender Schritt: Knopf bleibt sichtbar, aber ausgegraut (kein zweiter Lauf).
      Assert.IsTrue(mFrame.Button(TAtlasSetupButton.Baseline).Visible);
      Assert.IsFalse(mFrame.Button(TAtlasSetupButton.Baseline).Enabled);
      Assert.IsFalse(mFrame.Button(TAtlasSetupButton.Paths).Enabled);
      Assert.Contains(mFrame.StepText(TAtlasSetupStep.Baseline).Caption, '0 s');
      mFrame.ClickButton(TAtlasSetupButton.Baseline);
      CheckSynchronize;
      Assert.AreEqual(0, Integer(Length(mFake.Calls)));
      // Fehler: Grund unter dem Schritt.
      mFake.Card_.Baseline := TAtlasSetupRun.Failed;
      mFake.Card_.BaselineError := 'Server nicht bereit';
      mFrame.UpdateContent;
      Assert.IsTrue(mFrame.Button(TAtlasSetupButton.Baseline).Enabled);
      Assert.IsTrue(mFrame.BaselineInfo.Visible);
      Assert.AreEqual('Server nicht bereit', mFrame.BaselineInfo.Caption);
    finally
      mHost.Free;
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;
procedure TAtlasWelcomeSetupFrameTests.PreviewShowsContent;
var
  mSaved: TAtlasLanguage;
  mDialog: TAtlasSetupPreviewDialog;
  mText: string;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mText := StringReplace(TAtlasProjectSetups.BuiltIn(TAtlasSetupTemplate.Existing), #10, sLineBreak,
      [rfReplaceAll]);
    mDialog := TAtlasSetupPreviewDialog.CreateDialog(nil, 'atlas.json', 'XmlInspector.dproj', 'Bestehendes Projekt',
      mText);
    try
      Assert.AreEqual('atlas.json anlegen', mDialog.Caption);
      Assert.AreEqual('Atlas legt atlas.json neben XmlInspector.dproj an (Vorlage „Bestehendes Projekt“). Inhalt:',
        mDialog.Intro.Caption);
      Assert.Contains(mDialog.Content.Text, '"profile": "standard"');
      Assert.IsTrue(mDialog.Content.ReadOnly);
      Assert.IsTrue(mDialog.CreateButton.Default);
      Assert.IsTrue(mDialog.CancelButton.Cancel, 'Esc schreibt nichts');
      Assert.AreEqual(Integer(mrOk), Integer(mDialog.CreateButton.ModalResult));
      Assert.AreEqual(Integer(mrCancel), Integer(mDialog.CancelButton.ModalResult));
    finally
      mDialog.Free;
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeSetupFrameTests);

end.
