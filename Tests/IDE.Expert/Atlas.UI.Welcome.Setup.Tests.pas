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
  Saved: TAtlasLanguage;
  Card: TAtlasSetupCard;
begin
  Saved := TAtlasStrings.Language;
  try
    Card := SetupCard;
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('XmlInspector für Atlas einrichten', TAtlasWelcomeSetupFrame.TitleText(Card));
    Assert.AreEqual('Projekt gefunden, keine atlas.json',
      TAtlasWelcomeSetupFrame.StepCaption(TAtlasSetupStep.Found, Card, 0));
    Assert.AreEqual('atlas.json anlegen', TAtlasWelcomeSetupFrame.StepCaption(TAtlasSetupStep.Config, Card, 0));
    Assert.AreEqual('Baseline erzeugen', TAtlasWelcomeSetupFrame.StepCaption(TAtlasSetupStep.Baseline, Card, 0));
    Assert.AreEqual('Suchpfade und Defines prüfen',
      TAtlasWelcomeSetupFrame.StepCaption(TAtlasSetupStep.Paths, Card, 0));
    Assert.AreEqual('Bestehendes Projekt', TAtlasWelcomeSetupFrame.TemplateCaption(TAtlasSetupTemplate.Existing));
    Assert.AreEqual('Neues Projekt, streng', TAtlasWelcomeSetupFrame.TemplateCaption(TAtlasSetupTemplate.NewStrict));
    Assert.AreEqual('Altprojekt mit Baseline', TAtlasWelcomeSetupFrame.TemplateCaption(TAtlasSetupTemplate.Legacy));
    Assert.AreEqual('Starten', TAtlasWelcomeSetupFrame.ButtonCaption(TAtlasSetupButton.Baseline));
    Assert.AreEqual('Prüfen', TAtlasWelcomeSetupFrame.ButtonCaption(TAtlasSetupButton.Paths));
    Assert.AreEqual('Für dieses Projekt nicht mehr fragen',
      TAtlasWelcomeSetupFrame.ButtonCaption(TAtlasSetupButton.Dismiss));
    Assert.AreEqual('Testklasse', TAtlasWelcomeSetupFrame.ButtonCaption(TAtlasSetupButton.NewTest));
    Card.Facts.ConfigExists := True;
    Card.ConfigName := 'atlas.json';
    Assert.AreEqual('Projekt gefunden', TAtlasWelcomeSetupFrame.StepCaption(TAtlasSetupStep.Found, Card, 0));
    Assert.AreEqual('atlas.json vorhanden', TAtlasWelcomeSetupFrame.StepCaption(TAtlasSetupStep.Config, Card, 0));
    Card.ShowCard := False;
    Assert.AreEqual('Neu mit Atlas', TAtlasWelcomeSetupFrame.TitleText(Card));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Card.ShowCard := True;
    Assert.AreEqual('Set up XmlInspector for Atlas', TAtlasWelcomeSetupFrame.TitleText(Card));
    Assert.AreEqual('Test class', TAtlasWelcomeSetupFrame.ButtonCaption(TAtlasSetupButton.NewTest));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;
/// <summary>Schritt 1 erledigt, Vorlage „Bestehendes Projekt“, Knöpfe rechts neben ihren Schritten.</summary>
procedure AssertSetupStartLayout(const AFrame: TAtlasWelcomeSetupFrame);
begin
  // Schritt 1 erledigt, die anderen offen.
  Assert.AreEqual(string(#$2713), AFrame.StepMark(TAtlasSetupStep.Found).Caption);
  Assert.AreEqual(Integer(TAtlasWelcomeSetupFrame.DoneColor),
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
  Host: TForm;
  Fake: TFakeSetup;
  Source: IAtlasSetupSource;
  Frame: TAtlasWelcomeSetupFrame;
begin
  Fake := TFakeSetup.Create;
  Fake.Card_ := SetupCard;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeSetupFrame.Create(Host);
    Frame.Parent := Host;
    Frame.SetBounds(0, 0, 640, 300);
    Frame.Source := Source;
    AssertSetupStartLayout(Frame);
    // Abnahme: Nach „Anlegen“ ist Schritt 2 abgehakt; nach der Baseline Schritt 3 mit „neue Treffer: 0“.
    Fake.Card_.Facts.ConfigExists := True;
    Fake.Card_.ConfigName := 'atlas.json';
    Fake.Card_.Facts.BaselineExists := True;
    Fake.Card_.Baseline := TAtlasSetupRun.Done;
    Fake.Card_.BaselineTotal := 120;
    Fake.Card_.BaselineFiles := 14;
    Fake.Card_.BaselineNewHits := 0;
    Frame.UpdateContent;
    Assert.AreEqual(string(#$2713), Frame.StepMark(TAtlasSetupStep.Config).Caption);
    Assert.AreEqual(Integer(TAtlasWelcomeSetupFrame.DoneColor),
      Integer(Frame.StepText(TAtlasSetupStep.Config).Font.Color));
    Assert.IsFalse(Frame.TemplateBox.Visible);
    Assert.IsFalse(Frame.Button(TAtlasSetupButton.CreateConfig).Visible);
    Assert.AreEqual(string(#$2713), Frame.StepMark(TAtlasSetupStep.Baseline).Caption);
    Assert.IsFalse(Frame.Button(TAtlasSetupButton.Baseline).Visible);
    Assert.IsTrue(Frame.BaselineInfo.Visible);
    Assert.AreEqual(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupBaselineResult, [120, 14, 0]),
      Frame.BaselineInfo.Caption);
    Assert.Contains(Frame.BaselineInfo.Caption, ': 0');
    // Ohne geöffnetes Projekt heißen die Knöpfe „Projekt öffnen“.
    Fake.Card_.Facts.BaselineExists := False;
    Fake.Card_.Baseline := TAtlasSetupRun.Idle;
    Fake.Card_.ProjectOpen := False;
    Frame.UpdateContent;
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupOpenProject),
      Frame.Button(TAtlasSetupButton.Baseline).Caption);
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupOpenProject),
      Frame.Button(TAtlasSetupButton.Paths).Caption);
  finally
    Host.Free;
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
    TAtlasWelcomeSetupFrame.FindingCaption(mLine));
  mLine.Count := 3;
  Assert.AreEqual('Unit „Xml.Helpers“ nicht gefunden – Src\Main.pas, Zeile 12 (3×)',
    TAtlasWelcomeSetupFrame.FindingCaption(mLine));
  mLine.Kind := TAtlasSetupFindingKind.UndefinedDefine;
  mLine.Name := 'USE_XML';
  mLine.Count := 1;
  Assert.AreEqual('Define „USE_XML“ ohne Quelle – Src\Main.pas, Zeile 12',
    TAtlasWelcomeSetupFrame.FindingCaption(mLine));
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
  Saved: TAtlasLanguage;
  Host: TForm;
  Fake: TFakeSetup;
  Source: IAtlasSetupSource;
  Frame: TAtlasWelcomeSetupFrame;
begin
  Saved := TAtlasStrings.Language;
  Fake := TFakeSetup.Create;
  Fake.Card_ := SetupCardWithFindings;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    AssertSetupFindingCaptions;
    Frame := TAtlasWelcomeSetupFrame.Create(Host);
    Frame.Parent := Host;
    Frame.SetBounds(0, 0, 640, 300);
    Frame.Source := Source;
    // Schritt 4 offen, Zusammenfassung, höchstens MaxLines Funde, der Rest als „… und n weitere“.
    Assert.AreNotEqual(string(#$2713), Frame.StepMark(TAtlasSetupStep.Paths).Caption);
    Assert.IsTrue(Frame.PathsInfo.Visible);
    Assert.AreEqual('9 Units nicht gefunden, 1 Defines ohne Quelle (12 Dateien geprüft)', Frame.PathsInfo.Caption);
    Assert.IsTrue(Frame.Finding(0).Visible);
    Assert.Contains(Frame.Finding(0).Caption, 'Xml.Helpers');
    Assert.IsTrue(Frame.Finding(TAtlasWelcomeSetup.MaxLines - 1).Visible);
    Assert.IsTrue(Frame.MoreLabel.Visible);
    Assert.AreEqual('… und 4 weitere', Frame.MoreLabel.Caption);
    Assert.IsTrue(Frame.Button(TAtlasSetupButton.Options).Visible);
    Assert.IsTrue(Frame.Finding(0).Top > Frame.StepText(TAtlasSetupStep.Paths).Top);
    // Ein Klick auf den Fund öffnet die Projektoptionen.
    Frame.Finding(0).OnClick(Frame.Finding(0));
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(Fake.Calls)));
    Assert.AreEqual('options', Fake.Calls[0]);
    // Saubere Prüfung: Schritt 4 grün, keine Funde.
    Fake.Card_.Facts.Setup.MissingUnitCount := 0;
    Fake.Card_.Facts.Setup.UndefinedDefineCount := 0;
    Fake.Card_.Facts.Setup.MissingUnits := nil;
    Fake.Card_.Facts.Setup.UndefinedDefines := nil;
    Frame.UpdateContent;
    Assert.AreEqual(string(#$2713), Frame.StepMark(TAtlasSetupStep.Paths).Caption);
    Assert.IsFalse(Frame.Finding(0).Visible);
    Assert.IsFalse(Frame.PathsInfo.Visible);
    Assert.IsFalse(Frame.Button(TAtlasSetupButton.Options).Visible);
  finally
    Host.Free;
    TAtlasStrings.Language := Saved;
  end;
end;
procedure TAtlasWelcomeSetupFrameTests.UncertainAndGroupCaptions;
var
  Saved: TAtlasLanguage;
  Line: TAtlasSetupLine;
  Card: TAtlasSetupCard;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Line := Default(TAtlasSetupLine);
    Line.Kind := TAtlasSetupFindingKind.MissingUnit;
    Line.Name := 'Lib.Core';
    Line.FileName := 'App\App.dpr';
    Line.Line := 3;
    Line.Count := 1;
    Line.Uncertain := True;
    Line.Macros := '$(MYLIB)';
    Assert.AreEqual('Unit „Lib.Core“ nicht gefunden (unsicher, Suchpfad mit unbekanntem Makro $(MYLIB) ' +
      'übersprungen) – App\App.dpr, Zeile 3', TAtlasWelcomeSetupFrame.FindingCaption(Line));
    Line.Project := 'App';
    Line.Kind := TAtlasSetupFindingKind.UndefinedDefine;
    Line.Name := 'USE_LIB';
    Assert.AreEqual('App: Define „USE_LIB“ ohne Quelle (unsicher, Suchpfad mit unbekanntem Makro $(MYLIB) ' +
      'übersprungen) – App\App.dpr, Zeile 3', TAtlasWelcomeSetupFrame.FindingCaption(Line));
    Card := SetupCard;
    Card.GroupProjects := 3;
    Card.GroupChecked := 1;
    Card.Facts.Setup.MissingUnitCount := 2;
    Card.Facts.Setup.UncertainUnitCount := 1;
    Card.Facts.Setup.Files := 5;
    Card.Facts.Setup.SkippedMacros := ['MYLIB'];
    Assert.AreEqual('1 von 3 Projekten der Gruppe geprüft' + sLineBreak +
      '2 Units nicht gefunden, 0 Defines ohne Quelle (5 Dateien geprüft)' + sLineBreak +
      'Davon unsicher: 1 (Suchpfad mit unbekanntem Makro $(MYLIB) übersprungen)',
      TAtlasWelcomeSetupFrame.PathsCaption(Card));
    // Fehler gehen vor.
    Card.Paths := TAtlasSetupRun.Failed;
    Card.PathsError := 'kaputt';
    Assert.AreEqual('kaputt', TAtlasWelcomeSetupFrame.PathsCaption(Card));
    // Einzelprojekt ohne Prüfung: nichts.
    Assert.AreEqual('', TAtlasWelcomeSetupFrame.PathsCaption(SetupCard));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;
procedure TAtlasWelcomeSetupFrameTests.CardAndNewRowFollowCard;
var
  Host: TForm;
  Fake: TFakeSetup;
  Source: IAtlasSetupSource;
  Frame: TAtlasWelcomeSetupFrame;
  Step: TAtlasSetupStep;
  Full: Integer;
begin
  Fake := TFakeSetup.Create;
  Fake.Card_ := SetupCard;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeSetupFrame.Create(Host);
    Frame.Parent := Host;
    Frame.SetBounds(0, 0, 640, 300);
    Frame.Source := Source;
    Assert.IsTrue(Frame.NewRowLabel.Visible);
    Assert.IsTrue(Frame.Button(TAtlasSetupButton.NewUnit).Visible);
    Assert.IsTrue(Frame.Button(TAtlasSetupButton.NewForm).Visible);
    Assert.IsTrue(Frame.Button(TAtlasSetupButton.NewTest).Visible);
    Assert.IsTrue(Frame.NewRowLabel.Top > Frame.DismissLabel.Top, '„Neu mit Atlas“ unter der Karte');
    Assert.AreEqual(Frame.Button(TAtlasSetupButton.NewUnit).Top, Frame.Button(TAtlasSetupButton.NewTest).Top);
    Full := Frame.PreferredHeight;
    // Vollständig eingerichtet bzw. abgewählt: keine Karte, nur „Neu mit Atlas“.
    Fake.Card_.ShowCard := False;
    Frame.UpdateContent;
    for Step := Low(TAtlasSetupStep) to High(TAtlasSetupStep) do
    begin
      Assert.IsFalse(Frame.StepText(Step).Visible);
    end;
    Assert.IsFalse(Frame.TemplateBox.Visible);
    Assert.IsFalse(Frame.Button(TAtlasSetupButton.Baseline).Visible);
    Assert.IsFalse(Frame.DismissLabel.Visible);
    Assert.IsTrue(Frame.Button(TAtlasSetupButton.NewUnit).Visible);
    Assert.IsTrue(Frame.PreferredHeight < Full);
    // newFromTemplate aus: nur die Karte.
    Fake.Card_.ShowCard := True;
    Fake.Card_.ShowNew := False;
    Frame.UpdateContent;
    Assert.IsTrue(Frame.StepText(TAtlasSetupStep.Config).Visible);
    Assert.IsFalse(Frame.NewRowLabel.Visible);
    Assert.IsFalse(Frame.Button(TAtlasSetupButton.NewUnit).Visible);
    Assert.IsFalse(Frame.Button(TAtlasSetupButton.NewTest).Visible);
    // Schmal: Knöpfe brechen um, der Bereich wird höher.
    Full := Frame.PreferredHeight;
    Frame.Width := 200;
    Frame.UpdateContent;
    Assert.IsTrue(Frame.Button(TAtlasSetupButton.CreateConfig).Top > Frame.StepText(TAtlasSetupStep.Config).Top);
    Assert.IsTrue(Frame.PreferredHeight > Full);
  finally
    Host.Free;
  end;
end;
procedure TAtlasWelcomeSetupFrameTests.ClicksReachSource;
var
  Host: TForm;
  Fake: TFakeSetup;
  Source: IAtlasSetupSource;
  Frame: TAtlasWelcomeSetupFrame;
begin
  Fake := TFakeSetup.Create;
  Fake.Card_ := SetupCard;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeSetupFrame.Create(Host);
    Frame.Parent := Host;
    Frame.SetBounds(0, 0, 640, 300);
    // Ohne Quelle geht nichts.
    Frame.ClickButton(TAtlasSetupButton.CreateConfig);
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)));
    Frame.Source := Source;
    Frame.SelectTemplate(TAtlasSetupTemplate.Legacy);
    Frame.Button(TAtlasSetupButton.CreateConfig).Click;
    Frame.Button(TAtlasSetupButton.Baseline).Click;
    Frame.Button(TAtlasSetupButton.Paths).Click;
    Frame.DismissLabel.OnClick(Frame.DismissLabel);
    Frame.Button(TAtlasSetupButton.NewUnit).Click;
    Frame.Button(TAtlasSetupButton.NewForm).Click;
    Frame.Button(TAtlasSetupButton.NewTest).Click;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(7, Integer(Length(Fake.Calls)));
    Assert.AreEqual('config:legacy', Fake.Calls[0]);
    Assert.AreEqual('baseline', Fake.Calls[1]);
    Assert.AreEqual('paths', Fake.Calls[2]);
    Assert.AreEqual('dismiss', Fake.Calls[3]);
    Assert.AreEqual('new:unit', Fake.Calls[4]);
    Assert.AreEqual('new:form', Fake.Calls[5]);
    Assert.AreEqual('new:test', Fake.Calls[6]);
    // Projekt nicht offen: Baseline und Prüfung öffnen erst das Projekt.
    Fake.Calls := nil;
    Fake.Card_.ProjectOpen := False;
    Frame.UpdateContent;
    Frame.ClickButton(TAtlasSetupButton.Baseline);
    Frame.ClickButton(TAtlasSetupButton.Paths);
    CheckSynchronize;
    Assert.AreEqual(2, Integer(Length(Fake.Calls)));
    Assert.AreEqual('open', Fake.Calls[0]);
    Assert.AreEqual('open', Fake.Calls[1]);
    // Unsichtbare Knöpfe tun nichts: Schritt 2 erledigt, keine Karte.
    Fake.Calls := nil;
    Fake.Card_.Facts.ConfigExists := True;
    Fake.Card_.ShowCard := False;
    Frame.UpdateContent;
    Frame.ClickButton(TAtlasSetupButton.CreateConfig);
    Frame.ClickButton(TAtlasSetupButton.Dismiss);
    Frame.ClickButton(TAtlasSetupButton.Options);
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)));
  finally
    Host.Free;
  end;
end;
procedure TAtlasWelcomeSetupFrameTests.RunningStepShowsSeconds;
var
  Saved: TAtlasLanguage;
  Host: TForm;
  Fake: TFakeSetup;
  Source: IAtlasSetupSource;
  Frame: TAtlasWelcomeSetupFrame;
  Card: TAtlasSetupCard;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Card := SetupCard;
    Card.Baseline := TAtlasSetupRun.Running;
    Card.BaselineStarted := 1000;
    Assert.AreEqual('Baseline wird erzeugt … 12 s',
      TAtlasWelcomeSetupFrame.StepCaption(TAtlasSetupStep.Baseline, Card, 13500));
    Card.Paths := TAtlasSetupRun.Running;
    Card.PathsStarted := 1000;
    Assert.AreEqual('Suchpfade und Defines werden geprüft … 2 s',
      TAtlasWelcomeSetupFrame.StepCaption(TAtlasSetupStep.Paths, Card, 3000));
    Fake := TFakeSetup.Create;
    Fake.Card_ := Card;
    Fake.Card_.BaselineStarted := TThread.GetTickCount64;
    Fake.Card_.PathsStarted := TThread.GetTickCount64;
    Source := Fake;
    Host := TForm.CreateNew(nil);
    try
      Frame := TAtlasWelcomeSetupFrame.Create(Host);
      Frame.Parent := Host;
      Frame.SetBounds(0, 0, 640, 300);
      Frame.Source := Source;
      // Laufender Schritt: Knopf bleibt sichtbar, aber ausgegraut (kein zweiter Lauf).
      Assert.IsTrue(Frame.Button(TAtlasSetupButton.Baseline).Visible);
      Assert.IsFalse(Frame.Button(TAtlasSetupButton.Baseline).Enabled);
      Assert.IsFalse(Frame.Button(TAtlasSetupButton.Paths).Enabled);
      Assert.Contains(Frame.StepText(TAtlasSetupStep.Baseline).Caption, '0 s');
      Frame.ClickButton(TAtlasSetupButton.Baseline);
      CheckSynchronize;
      Assert.AreEqual(0, Integer(Length(Fake.Calls)));
      // Fehler: Grund unter dem Schritt.
      Fake.Card_.Baseline := TAtlasSetupRun.Failed;
      Fake.Card_.BaselineError := 'Server nicht bereit';
      Frame.UpdateContent;
      Assert.IsTrue(Frame.Button(TAtlasSetupButton.Baseline).Enabled);
      Assert.IsTrue(Frame.BaselineInfo.Visible);
      Assert.AreEqual('Server nicht bereit', Frame.BaselineInfo.Caption);
    finally
      Host.Free;
    end;
  finally
    TAtlasStrings.Language := Saved;
  end;
end;
procedure TAtlasWelcomeSetupFrameTests.PreviewShowsContent;
var
  Saved: TAtlasLanguage;
  Dialog: TAtlasSetupPreviewDialog;
  Text: string;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Text := StringReplace(TAtlasProjectSetups.BuiltIn(TAtlasSetupTemplate.Existing), #10, sLineBreak,
      [rfReplaceAll]);
    Dialog := TAtlasSetupPreviewDialog.CreateDialog(nil, 'atlas.json', 'XmlInspector.dproj', 'Bestehendes Projekt',
      Text);
    try
      Assert.AreEqual('atlas.json anlegen', Dialog.Caption);
      Assert.AreEqual('Atlas legt atlas.json neben XmlInspector.dproj an (Vorlage „Bestehendes Projekt“). Inhalt:',
        Dialog.Intro.Caption);
      Assert.Contains(Dialog.Content.Text, '"profile": "standard"');
      Assert.IsTrue(Dialog.Content.ReadOnly);
      Assert.IsTrue(Dialog.CreateButton.Default);
      Assert.IsTrue(Dialog.CancelButton.Cancel, 'Esc schreibt nichts');
      Assert.AreEqual(Integer(mrOk), Integer(Dialog.CreateButton.ModalResult));
      Assert.AreEqual(Integer(mrCancel), Integer(Dialog.CancelButton.ModalResult));
    finally
      Dialog.Free;
    end;
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeSetupFrameTests);

end.
