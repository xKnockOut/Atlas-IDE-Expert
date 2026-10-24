unit Atlas.UI.Build.SwitchesFrame.Tests;

// Fenster „Compiler-Schalter“ (#558), Oberfläche: Abschnitte mit Köpfen,
// Spalten mit Minuszeichen, Herkunft „gesetzt in Zeile 10“ bzw. Include-Datei
// und Projektoption, Kurzfassung der Abweichungen, Hinweis ohne Stand, Enter
// springt bzw. öffnet die Projektoptionen, Kopieren als Text.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  TAtlasBuildSwitchesFrameTests = class
  private
    FLanguage: TAtlasLanguage;
  public
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

function Row(ASection: TAtlasSwitchSection; const AName, AValue, AProject: string; AKind: TAtlasSwitchOriginKind;
  const AText, AFile: string; ALine: Integer): TAtlasSwitchRow;
begin
  Result := Default(TAtlasSwitchRow);
  Result.Section := ASection;
  Result.Name := AName;
  Result.Value := AValue;
  Result.ProjectValue := AProject;
  Result.Deviates := AValue <> AProject;
  Result.Kind := AKind;
  Result.OriginText := AText;
  Result.FileName := AFile;
  Result.Line := ALine;
end;

function SampleView: TAtlasCompilerSwitchView;
var
  Range: TAtlasSwitchRow;
begin
  Result := Default(TAtlasCompilerSwitchView);
  Result.HasProject := True;
  Result.Configuration := 'Debug';
  Result.Platform := 'Win64';
  Result.Summary := 'R'#$2212;
  Range := Row(TAtlasSwitchSection.Switches, 'R', '-', '+', TAtlasSwitchOriginKind.Directive, '{$R-}',
    'C:\P\A.pas', 9);
  Range.LongName := 'RANGECHECKS';
  Result.Rows := [Range,
    Row(TAtlasSwitchSection.Switches, 'Q', '+', '+', TAtlasSwitchOriginKind.Project, 'DCC_IntegerOverflowCheck',
      '', -1),
    Row(TAtlasSwitchSection.Messages, 'HINTS', 'ON', 'ON', TAtlasSwitchOriginKind.Default, '', '', -1),
    Row(TAtlasSwitchSection.Defines, 'DEBUG', '', '', TAtlasSwitchOriginKind.Project,
      'Konfiguration Debug (.dproj)', '', -1)];
end;

{ TAtlasBuildSwitchesFrameTests }

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
    'R', '-', '+', TAtlasSwitchOriginKind.Directive, '{$R-}', 'C:\P\A.pas', 9)));
  Assert.AreEqual('gesetzt in Optionen.inc, Zeile 3', TAtlasBuildSwitchesFrame.OriginText(
    Row(TAtlasSwitchSection.Switches, 'Q', '-', '+', TAtlasSwitchOriginKind.Include, '{$Q-}',
    'C:\P\Optionen.inc', 2)));
  Assert.AreEqual('Projektoption DCC_Hints', TAtlasBuildSwitchesFrame.OriginText(
    Row(TAtlasSwitchSection.Messages, 'HINTS', 'OFF', 'OFF', TAtlasSwitchOriginKind.Project, 'DCC_Hints', '', -1)));
  Assert.AreEqual('Compiler-Vorgabe', TAtlasBuildSwitchesFrame.OriginText(
    Row(TAtlasSwitchSection.Switches, 'R', '-', '-', TAtlasSwitchOriginKind.Default, 'DCC_RangeChecking', '', -1)));
  Assert.AreEqual('Compiler-Vorgabe (Plattform Win64)', TAtlasBuildSwitchesFrame.OriginText(
    Row(TAtlasSwitchSection.Defines, 'WIN64', '', '', TAtlasSwitchOriginKind.Default,
    'Compiler-Vorgabe (Plattform Win64)', '', -1)));
end;

procedure TAtlasBuildSwitchesFrameTests.CellsWithMinusAndLongName;
var
  Texts: TArray<string>;
begin
  Texts := TAtlasBuildSwitchesFrame.Cells(SampleView.Rows[0]);
  Assert.AreEqual(4, Integer(Length(Texts)));
  Assert.AreEqual('R (RANGECHECKS)', Texts[0]);
  Assert.AreEqual(string(#$2212), Texts[1]);
  Assert.AreEqual('+', Texts[2]);
  Assert.AreEqual('gesetzt in Zeile 10', Texts[3]);
  Texts := TAtlasBuildSwitchesFrame.Cells(SampleView.Rows[3]);
  Assert.AreEqual('', Texts[1], 'Symbole ohne Wert');
  Assert.AreEqual('Konfiguration Debug (.dproj)', Texts[3]);
end;

procedure TAtlasBuildSwitchesFrameTests.LinesHaveSectionHeaders;
var
  Lines: TAtlasSwitchLines;
begin
  Lines := TAtlasBuildSwitchesFrame.Lines(SampleView);
  // Schalter-Kopf, R, Q, Meldungen-Kopf, HINTS, Symbole-Kopf, DEBUG; kein Ziel ohne Zeilen.
  Assert.AreEqual(7, Integer(Length(Lines)));
  Assert.IsTrue(Lines[0].Header);
  Assert.AreEqual(0, Lines[1].Row);
  Assert.IsTrue(Lines[3].Header);
  Assert.IsTrue(Lines[3].Section = TAtlasSwitchSection.Messages);
  Assert.AreEqual(3, Lines[6].Row);
end;

procedure TAtlasBuildSwitchesFrameTests.ShowsViewWithSummary;
var
  Host: TForm;
  Frame: TAtlasBuildSwitchesFrame;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasBuildSwitchesFrame.Create(Host);
    Frame.Parent := Host;
    Frame.HandleNeeded;
    Frame.SetView(SampleView, 'C:\P\A.pas', 19);
    Assert.AreEqual(4, Integer(Frame.List.Columns.Count));
    Assert.AreEqual('Herkunft', Frame.List.Columns[3].Caption);
    Assert.AreEqual(7, Integer(Frame.List.Items.Count));
    Assert.AreEqual('Schalter', Frame.List.Items[0].Caption);
    Assert.AreEqual('  R (RANGECHECKS)', Frame.List.Items[1].Caption);
    Assert.AreEqual('gesetzt in Zeile 10', Frame.List.Items[1].SubItems[2]);
    Assert.AreEqual('A.pas, Zeile 20', Frame.WhereLabel.Caption);
    Assert.AreEqual('Abweichend von der .dproj: R'#$2212, Frame.SummaryLabel.Caption);
    Assert.IsFalse(Frame.EmptyLabel.Visible);
    Assert.IsTrue(Frame.List.Visible);
  finally
    Host.Free;
  end;
end;

procedure TAtlasBuildSwitchesFrameTests.MessageHidesList;
var
  Host: TForm;
  Frame: TAtlasBuildSwitchesFrame;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasBuildSwitchesFrame.Create(Host);
    Frame.Parent := Host;
    Frame.HandleNeeded;
    Assert.IsTrue(Frame.EmptyLabel.Visible, 'ohne Stand der Hinweis');
    Frame.SetView(SampleView, 'C:\P\A.pas', 19);
    Frame.SetMessage(TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesNoServer));
    Assert.IsTrue(Frame.EmptyLabel.Visible);
    Assert.IsFalse(Frame.List.Visible);
    Assert.AreEqual('Der Atlas-Server läuft nicht.', Frame.EmptyLabel.Caption);
  finally
    Host.Free;
  end;
end;

procedure TAtlasBuildSwitchesFrameTests.EnterJumpsOrOpensOptions;
var
  Host: TForm;
  Frame: TAtlasBuildSwitchesFrame;
  Jumped: string;
  Options: Integer;
  Key: Word;
begin
  Jumped := '';
  Options := 0;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasBuildSwitchesFrame.Create(Host);
    Frame.Parent := Host;
    Frame.HandleNeeded;
    Frame.OnJump :=
      procedure(ARow: TAtlasSwitchRow)
      begin
        Jumped := ARow.FileName + ':' + IntToStr(ARow.Line);
      end;
    Frame.OnOptions :=
      procedure
      begin
        Inc(Options);
      end;
    Frame.SetView(SampleView, 'C:\P\A.pas', 19);
    Frame.List.Items[0].Selected := True;
    Key := VK_RETURN;
    Frame.List.OnKeyDown(Frame.List, Key, []);
    Assert.AreEqual('', Jumped, 'Kopf tut nichts');
    Frame.List.Items[1].Selected := True;
    Key := VK_RETURN;
    Frame.List.OnKeyDown(Frame.List, Key, []);
    Assert.AreEqual('C:\P\A.pas:9', Jumped);
    Frame.List.Items[2].Selected := True;
    Frame.ExecuteSelected;
    Assert.AreEqual(1, Options, 'Projektoption öffnet die Projektoptionen');
    Frame.List.Items[4].Selected := True;
    Frame.ExecuteSelected;
    Assert.AreEqual(1, Options, 'Compiler-Vorgabe tut nichts');
  finally
    Host.Free;
  end;
  Jumped := '';
end;

procedure TAtlasBuildSwitchesFrameTests.CopiesAsText;
var
  Text: string;
begin
  Text := TAtlasBuildSwitchesFrame.AsText(SampleView);
  Assert.IsTrue(Text.StartsWith('Schalter' + sLineBreak + '  R (RANGECHECKS)'#9#$2212#9'+'#9'gesetzt in Zeile 10'),
    Text);
  Assert.IsTrue(Text.Contains('Bedingte Symbole'));
end;

end.
