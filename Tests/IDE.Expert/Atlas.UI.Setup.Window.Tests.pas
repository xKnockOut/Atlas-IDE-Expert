unit Atlas.UI.Setup.Window.Tests;

// Fenster „Atlas-Einrichtung“ (#625): Texte je Befund, ein Knopf je gelbem
// oder rotem Punkt, „Warum?“ erklärt im Fenster, die übrigen Knöpfe rufen
// OnFix, Unterzeilen je Projekt, Bericht und Einstieg „Probier es aus“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSetupWindowTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TextsFollowFindings;
    [Test]
    procedure ButtonOnlyForNonGreenPoints;
    [Test]
    procedure FixButtonCallsOnFix;
    [Test]
    procedure WhyExplainsInTheWindow;
    [Test]
    procedure ProjectsBecomeSubLines;
    [Test]
    procedure ReportLinesAndProgress;
    [Test]
    procedure ShowAtStartWithoutEcho;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Style.Palette,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Lines,
  Atlas.Core.Setup.Checklist,
  Atlas.UI.Strings,
  Atlas.UI.Setup.Window;

var
  Language: TAtlasLanguage;

function Input: TAtlasSetupInput;
var
  Workspace: TAtlasSetupWorkspace;
begin
  Result := Default(TAtlasSetupInput);
  Result.ServerFound := True;
  Result.Server.Phase := TAtlasServerPhase.Running;
  Result.Server.Version := '0.1.0';
  Result.PluginVersion := '0.1.0';
  Result.BdsVersion := '37.0';
  Result.Platform := 'Win64';
  Result.Projects := ['Kunden', 'Export'];
  Result.Status.Known := True;
  Result.Status.Units := 1569;
  Workspace.Name := 'Kunden';
  Workspace.Done := True;
  Workspace.LibraryCacheBytes := 0;
  Result.Status.Workspaces := [Workspace];
  Result.ErrorInsight := True;
  Result.AtlasProblems := True;
end;

procedure TAtlasSetupWindowTests.Setup;
begin
  Language := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasSetupWindowTests.TearDown;
begin
  TAtlasStrings.Language := Language;
end;

procedure TAtlasSetupWindowTests.TextsFollowFindings;
var
  Results: TArray<TAtlasSetupResult>;
begin
  Results := TAtlasSetupChecklist.Evaluate(Input);
  Assert.AreEqual('Server gefunden, gestartet, Version passt', TAtlasSetupWindow.ResultText(Results[0]));
  Assert.AreEqual('AtlasServer 0.1.0', TAtlasSetupWindow.DetailText(Results[0]));
  Assert.AreEqual('Delphi 13 (37.0) erkannt', TAtlasSetupWindow.ResultText(Results[1]));
  Assert.AreEqual('Plattform Win64', TAtlasSetupWindow.DetailText(Results[1]));
  Assert.AreEqual('Projektgruppe: 1 von 2 Projekten nicht im Index (Export)',
    TAtlasSetupWindow.ResultText(Results[2]));
  Assert.AreEqual('Bibliotheks-Cache fehlt, erster Start dauert länger', TAtlasSetupWindow.ResultText(Results[3]));
  Assert.AreEqual('Error Insight der IDE ist noch an (doppelte Meldungen)', TAtlasSetupWindow.ResultText(Results[4]));
  Assert.AreEqual('Tastenkürzel ohne Konflikt', TAtlasSetupWindow.ResultText(Results[5]));
  Assert.AreEqual('Server-Pfad wählen…', TAtlasSetupWindow.FixCaption(TAtlasSetupFix.ChooseServerPath));
  Assert.AreEqual('Index neu aufbauen', TAtlasSetupWindow.FixCaption(TAtlasSetupFix.RebuildIndex));
  Assert.AreEqual('Error Insight abschalten', TAtlasSetupWindow.FixCaption(TAtlasSetupFix.DisableErrorInsight));
  Assert.AreEqual('', TAtlasSetupWindow.FixCaption(TAtlasSetupFix.None));
end;

procedure TAtlasSetupWindowTests.ButtonOnlyForNonGreenPoints;
var
  Window: TAtlasSetupWindow;
  Results: TArray<TAtlasSetupResult>;
  Index: Integer;
begin
  Results := TAtlasSetupChecklist.Evaluate(Input);
  Window := TAtlasSetupWindow.CreateSetup(nil, TAtlasColors.Light);
  try
    Window.SetResults(Results);
    for Index := 0 to High(Results) do
      Assert.IsTrue((Results[Index].State <> TAtlasStatusState.Green) = Window.FixButtons[Index].Visible,
        'Knopf genau bei gelb oder rot: ' + IntToStr(Index));
    Assert.AreEqual('Jetzt aufbauen', Window.FixButtons[3].Caption);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SetupCopy), Window.CopyButton.Caption);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SetupRecheck), Window.RecheckButton.Caption);
  finally
    Window.Free;
  end;
end;

procedure TAtlasSetupWindowTests.FixButtonCallsOnFix;
var
  Window: TAtlasSetupWindow;
  Fixed: TAtlasSetupFix;
  Copied, Rechecked: Integer;
begin
  Fixed := TAtlasSetupFix.None;
  Copied := 0;
  Rechecked := 0;
  Window := TAtlasSetupWindow.CreateSetup(nil, TAtlasColors.Dark);
  try
    Window.SetResults(TAtlasSetupChecklist.Evaluate(Input));
    Window.OnFix :=
      procedure(AResult: TAtlasSetupResult)
      begin
        Fixed := AResult.Fix;
      end;
    Window.OnCopy :=
      procedure
      begin
        Inc(Copied);
      end;
    Window.OnRecheck :=
      procedure
      begin
        Inc(Rechecked);
      end;
    Window.FixButtons[4].Click;
    Assert.AreEqual(Ord(TAtlasSetupFix.DisableErrorInsight), Ord(Fixed));
    Window.CopyButton.Click;
    Window.RecheckButton.Click;
    Assert.AreEqual(1, Copied);
    Assert.AreEqual(1, Rechecked);
  finally
    Window.Free;
  end;
end;

procedure TAtlasSetupWindowTests.WhyExplainsInTheWindow;
var
  Window: TAtlasSetupWindow;
  Data: TAtlasSetupInput;
  Called: Boolean;
  Height_: Integer;
begin
  Data := Input;
  Data.Platform := '';
  Called := False;
  Window := TAtlasSetupWindow.CreateSetup(nil, TAtlasColors.Light);
  try
    Window.SetResults(TAtlasSetupChecklist.Evaluate(Data));
    Window.OnFix :=
      procedure(AResult: TAtlasSetupResult)
      begin
        Called := True;
      end;
    Height_ := Window.ClientHeight;
    Assert.AreEqual('Warum?', Window.FixButtons[1].Caption);
    Window.FixButtons[1].Click;
    Assert.IsFalse(Called, '„Warum?“ erklärt nur');
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SetupWhyDelphiNoProject), Window.Note);
    Assert.IsTrue(Window.ClientHeight > Height_, 'Platz für die Erklärung');
  finally
    Window.Free;
  end;
end;

procedure TAtlasSetupWindowTests.ProjectsBecomeSubLines;
var
  Window: TAtlasSetupWindow;
  Data: TAtlasSetupInput;
  Height1: Integer;
begin
  Data := Input;
  Data.Projects := nil;
  Window := TAtlasSetupWindow.CreateSetup(nil, TAtlasColors.Light);
  try
    Data.Status.Workspaces := nil;
    Window.SetResults(TAtlasSetupChecklist.Evaluate(Data));
    Height1 := Window.ClientHeight;
    Window.SetResults(TAtlasSetupChecklist.Evaluate(Input));
    Assert.IsTrue(Window.ClientHeight > Height1, 'zwei Projektzeilen unter dem Index');
    Assert.AreEqual('Kunden: fertig', TAtlasSetupWindow.ProjectText(Window.Results[2].Projects[0]));
    Assert.AreEqual('Export: fehlt im Index', TAtlasSetupWindow.ProjectText(Window.Results[2].Projects[1]));
  finally
    Window.Free;
  end;
end;

procedure TAtlasSetupWindowTests.ReportLinesAndProgress;
var
  Results: TArray<TAtlasSetupResult>;
  Lines: TArray<TAtlasSetupReportLine>;
begin
  Results := TAtlasSetupChecklist.Evaluate(Input);
  Assert.AreEqual('3 von 6 erledigt', TAtlasSetupWindow.ProgressText(Results));
  Lines := TAtlasSetupWindow.ReportLines(Results);
  // Sechs Prüfungen und zwei Projekte.
  Assert.AreEqual(8, Integer(Length(Lines)));
  Assert.AreEqual('Server gefunden, gestartet, Version passt (AtlasServer 0.1.0)', Lines[0].Text);
  Assert.IsTrue(Lines[3].Indent);
  Assert.AreEqual('Kunden: fertig', Lines[3].Text);
end;

procedure TAtlasSetupWindowTests.ShowAtStartWithoutEcho;
var
  Window: TAtlasSetupWindow;
  Calls: Integer;
  Last: Boolean;
begin
  Calls := 0;
  Last := True;
  Window := TAtlasSetupWindow.CreateSetup(nil, TAtlasColors.Light);
  try
    Window.OnShowAtStart :=
      procedure(AValue: Boolean)
      begin
        Inc(Calls);
        Last := AValue;
      end;
    Window.SetShowAtStart(False);
    Assert.AreEqual(0, Calls, 'Setzen aus der IDE-Schicht meldet nichts zurück');
    Assert.IsFalse(Window.ShowAtStartBox.Checked);
    Window.ShowAtStartBox.Checked := True;
    Assert.AreEqual(1, Calls);
    Assert.IsTrue(Last);
    Window.SetTryKey('Strg+J');
    Assert.AreEqual('Strg+J', Window.TryKey);
  finally
    Window.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSetupWindowTests);

end.
