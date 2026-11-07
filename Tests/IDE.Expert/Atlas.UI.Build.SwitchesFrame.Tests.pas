unit Atlas.UI.Build.SwitchesFrame.Tests;

// Fenster „Compiler-Schalter“ (#558), Oberfläche: Abschnitte mit Köpfen,
// Spalten mit Minuszeichen, Herkunft „gesetzt in Zeile 10“ bzw. Include-Datei
// und Projektoption, Kurzfassung der Abweichungen, Hinweis ohne Stand, Enter
// springt bzw. öffnet die Projektoptionen, Kopieren als Text.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings,
  Atlas.UI.Build.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Build')]
  TAtlasBuildSwitchesFrameTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    /// <summary>Einmal-Belegungen vorwegnehmen; sie gehören nicht in die Leckmessung.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure OriginTexts;
    [Test]
    procedure CellsWithMinusAndLongName;
    [Test]
    procedure LinesHaveSectionHeaders;
    [Test]
    procedure ShowsViewWithSummary;
    [Test]
    procedure MessageHidesList;
    [Test]
    procedure EnterJumpsOrOpensOptions;
    [Test]
    procedure CopiesAsText;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Vcl.Forms,
  Atlas.Core.Build.CompilerSwitches,
  Atlas.UI.Build.SwitchesFrame;

type
  /// <summary>Woher ein Schalter stammt: Art, Text, Datei und Zeile (0-basiert, -1 ohne).</summary>
  TSwitchOrigin = record
    Kind: TAtlasSwitchOriginKind;
    Text: string;
    FileName: string;
    Line: Integer;
  end;

function Origin(AKind: TAtlasSwitchOriginKind; const AText, AFile: string; ALine: Integer): TSwitchOrigin;
begin
  Result := Default(TSwitchOrigin);
  Result.Kind := AKind;
  Result.Text := AText;
  Result.FileName := AFile;
  Result.Line := ALine;
end;

function Row(ASection: TAtlasSwitchSection; const AName, AValue, AProject: string;
  const AOrigin: TSwitchOrigin): TAtlasSwitchRow;
begin
  Result := Default(TAtlasSwitchRow);
  Result.Section := ASection;
  Result.Name := AName;
  Result.Value := AValue;
  Result.ProjectValue := AProject;
  Result.Deviates := AValue <> AProject;
  Result.Kind := AOrigin.Kind;
  Result.OriginText := AOrigin.Text;
  Result.FileName := AOrigin.FileName;
  Result.Line := AOrigin.Line;
end;

function SampleView: TAtlasCompilerSwitchView;
var
  mRange: TAtlasSwitchRow;
begin
  Result := Default(TAtlasCompilerSwitchView);
  Result.HasProject := True;
  Result.Configuration := 'Debug';
  Result.Platform := 'Win64';
  Result.Summary := 'R'#$2212;
  mRange := Row(TAtlasSwitchSection.Switches, 'R', '-', '+', Origin(TAtlasSwitchOriginKind.Directive, '{$R-}',
    'C:\P\A.pas', 9));
  mRange.LongName := 'RANGECHECKS';
  Result.Rows := [mRange,
    Row(TAtlasSwitchSection.Switches, 'Q', '+', '+', Origin(TAtlasSwitchOriginKind.Project,
      'DCC_IntegerOverflowCheck', '', -1)),
    Row(TAtlasSwitchSection.Messages, 'HINTS', 'ON', 'ON', Origin(TAtlasSwitchOriginKind.Default, '', '', -1)),
    Row(TAtlasSwitchSection.Defines, 'DEBUG', '', '', Origin(TAtlasSwitchOriginKind.Project,
      'Konfiguration Debug (.dproj)', '', -1))];
end;

{ TAtlasBuildSwitchesFrameTests }

procedure TAtlasBuildSwitchesFrameTests.WarmUpFirstUse;
begin
  Setup;
  try
    ShowsViewWithSummary;
  finally
    TearDown;
  end;
end;

procedure TAtlasBuildSwitchesFrameTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasBuildSwitchesFrameTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasBuildSwitchesFrameTests.OriginTexts;
begin
  Assert.AreEqual('gesetzt in Zeile 10', TAtlasBuildSwitchesFrame.OriginText(Row(TAtlasSwitchSection.Switches,
    'R', '-', '+', Origin(TAtlasSwitchOriginKind.Directive, '{$R-}', 'C:\P\A.pas', 9))));
  Assert.AreEqual('gesetzt in Optionen.inc, Zeile 3', TAtlasBuildSwitchesFrame.OriginText(
    Row(TAtlasSwitchSection.Switches, 'Q', '-', '+', Origin(TAtlasSwitchOriginKind.Include, '{$Q-}',
    'C:\P\Optionen.inc', 2))));
  Assert.AreEqual('Projektoption DCC_Hints', TAtlasBuildSwitchesFrame.OriginText(
    Row(TAtlasSwitchSection.Messages, 'HINTS', 'OFF', 'OFF', Origin(TAtlasSwitchOriginKind.Project, 'DCC_Hints',
    '', -1))));
  Assert.AreEqual('Compiler-Vorgabe', TAtlasBuildSwitchesFrame.OriginText(
    Row(TAtlasSwitchSection.Switches, 'R', '-', '-', Origin(TAtlasSwitchOriginKind.Default, 'DCC_RangeChecking',
    '', -1))));
  Assert.AreEqual('Compiler-Vorgabe (Plattform Win64)', TAtlasBuildSwitchesFrame.OriginText(
    Row(TAtlasSwitchSection.Defines, 'WIN64', '', '', Origin(TAtlasSwitchOriginKind.Default,
    'Compiler-Vorgabe (Plattform Win64)', '', -1))));
end;

procedure TAtlasBuildSwitchesFrameTests.CellsWithMinusAndLongName;
var
  mTexts: TArray<string>;
begin
  mTexts := TAtlasBuildSwitchesFrame.Cells(SampleView.Rows[0]);
  Assert.AreEqual(4, Integer(Length(mTexts)));
  Assert.AreEqual('R (RANGECHECKS)', mTexts[0]);
  Assert.AreEqual(string(#$2212), mTexts[1]);
  Assert.AreEqual('+', mTexts[2]);
  Assert.AreEqual('gesetzt in Zeile 10', mTexts[3]);
  mTexts := TAtlasBuildSwitchesFrame.Cells(SampleView.Rows[3]);
  Assert.AreEqual('', mTexts[1], 'Symbole ohne Wert');
  Assert.AreEqual('Konfiguration Debug (.dproj)', mTexts[3]);
end;

procedure TAtlasBuildSwitchesFrameTests.LinesHaveSectionHeaders;
var
  mLines: TAtlasSwitchLines;
begin
  mLines := TAtlasBuildSwitchesFrame.Lines(SampleView);
  // Schalter-Kopf, R, Q, Meldungen-Kopf, HINTS, Symbole-Kopf, DEBUG; kein Ziel ohne Zeilen.
  Assert.AreEqual(7, Integer(Length(mLines)));
  Assert.IsTrue(mLines[0].Header);
  Assert.AreEqual(0, mLines[1].Row);
  Assert.IsTrue(mLines[3].Header);
  Assert.IsTrue(mLines[3].Section = TAtlasSwitchSection.Messages);
  Assert.AreEqual(3, mLines[6].Row);
end;

procedure TAtlasBuildSwitchesFrameTests.ShowsViewWithSummary;
var
  mHost: TForm;
  mFrame: TAtlasBuildSwitchesFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasBuildSwitchesFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mFrame.SetView(SampleView, 'C:\P\A.pas', 19);
    Assert.AreEqual(4, Integer(mFrame.List.Columns.Count));
    Assert.AreEqual('Herkunft', mFrame.List.Columns[3].Caption);
    Assert.AreEqual(7, Integer(mFrame.List.Items.Count));
    Assert.AreEqual('Schalter', mFrame.List.Items[0].Caption);
    Assert.AreEqual('  R (RANGECHECKS)', mFrame.List.Items[1].Caption);
    Assert.AreEqual('gesetzt in Zeile 10', mFrame.List.Items[1].SubItems[2]);
    Assert.AreEqual('A.pas, Zeile 20', mFrame.WhereLabel.Caption);
    Assert.AreEqual('Abweichend von der .dproj: R'#$2212, mFrame.SummaryLabel.Caption);
    Assert.IsFalse(mFrame.EmptyLabel.Visible);
    Assert.IsTrue(mFrame.List.Visible);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasBuildSwitchesFrameTests.MessageHidesList;
var
  mHost: TForm;
  mFrame: TAtlasBuildSwitchesFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasBuildSwitchesFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    Assert.IsTrue(mFrame.EmptyLabel.Visible, 'ohne Stand der Hinweis');
    mFrame.SetView(SampleView, 'C:\P\A.pas', 19);
    mFrame.SetMessage(TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesNoServer));
    Assert.IsTrue(mFrame.EmptyLabel.Visible);
    Assert.IsFalse(mFrame.List.Visible);
    Assert.AreEqual('Der Atlas-Server läuft nicht.', mFrame.EmptyLabel.Caption);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasBuildSwitchesFrameTests.EnterJumpsOrOpensOptions;
var
  mHost: TForm;
  mFrame: TAtlasBuildSwitchesFrame;
  mJumped: string;
  mOptions: Integer;
  mKey: Word;
begin
  mJumped := '';
  mOptions := 0;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasBuildSwitchesFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mFrame.OnJump :=
      procedure(ARow: TAtlasSwitchRow)
      begin
        mJumped := ARow.FileName + ':' + IntToStr(ARow.Line);
      end;
    mFrame.OnOptions :=
      procedure
      begin
        Inc(mOptions);
      end;
    mFrame.SetView(SampleView, 'C:\P\A.pas', 19);
    mFrame.List.Items[0].Selected := True;
    mKey := VK_RETURN;
    mFrame.List.OnKeyDown(mFrame.List, mKey, []);
    Assert.AreEqual('', mJumped, 'Kopf tut nichts');
    mFrame.List.Items[1].Selected := True;
    mKey := VK_RETURN;
    mFrame.List.OnKeyDown(mFrame.List, mKey, []);
    Assert.AreEqual('C:\P\A.pas:9', mJumped);
    mFrame.List.Items[2].Selected := True;
    mFrame.ExecuteSelected;
    Assert.AreEqual(1, mOptions, 'Projektoption öffnet die Projektoptionen');
    mFrame.List.Items[4].Selected := True;
    mFrame.ExecuteSelected;
    Assert.AreEqual(1, mOptions, 'Compiler-Vorgabe tut nichts');
  finally
    mHost.Free;
  end;
  mJumped := '';
end;

procedure TAtlasBuildSwitchesFrameTests.CopiesAsText;
var
  mText: string;
begin
  mText := TAtlasBuildSwitchesFrame.AsText(SampleView);
  Assert.IsTrue(mText.StartsWith('Schalter' + sLineBreak + '  R (RANGECHECKS)'#9#$2212#9'+'#9'gesetzt in Zeile 10'),
    mText);
  Assert.IsTrue(mText.Contains('Bedingte Symbole'));
end;

end.
