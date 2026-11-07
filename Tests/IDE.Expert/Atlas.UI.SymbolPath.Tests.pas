unit Atlas.UI.SymbolPath.Tests;

// Weg zwischen Symbolen (#1117), Oberfläche: gezeichnete Kette (Texte,
// Kantenarten, erschlossen, Auswahl, Sprung), Statuszeile, Eingabedialog
// (Prüfung, Vorschläge) und Ergebnisfenster (Kette statt Baum, Knopf „In
// Architekturkarte zeigen“).

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms;

type
  [TestFixture]
  [Category('Atlas.IDE.Analysis')]
  TAtlasSymbolPathUiTests = class
  private
    FForm: TForm;
    FOpened: string;
    FLine: Integer;
    FRoute: TArray<string>;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ChainShowsNodesAndSteps;
    [Test]
    procedure ChainSelectsAndOpens;
    [Test]
    procedure StatusTexts;
    [Test]
    procedure StepCaptionsFollowKind;
    [Test]
    procedure DialogValidatesAndSuggests;
    [Test]
    procedure ResultsFrameShowsChain;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Windows,
  Vcl.Controls,
  Atlas.UI.Strings,
  Atlas.UI.Analysis.Strings,
  Atlas.Core.SymbolPath.Model,
  Atlas.Core.SymbolPath.Model.Tests,
  Atlas.UI.SymbolPath.Chain,
  Atlas.UI.SymbolPath.Dialog,
  Atlas.UI.Results.Frame;

type
  /// <summary>Zugriff auf KeyDown und DblClick.</summary>
  TAtlasSymbolPathChainAccess = class(TAtlasSymbolPathChain);

function Sample: TAtlasSymbolPathAnswer;
begin
  TAtlasSymbolPathAnswer.Parse(SampleSymbolPathAnswer, Result);
end;

procedure TAtlasSymbolPathUiTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := 700;
  FForm.Height := 500;
end;

procedure TAtlasSymbolPathUiTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FOpened := '';
  FRoute := nil;
end;

procedure TAtlasSymbolPathUiTests.ChainShowsNodesAndSteps;
var
  mChain: TAtlasSymbolPathChain;
  mLines: TArray<string>;
begin
  mChain := TAtlasSymbolPathChain.Create(FForm);
  mChain.Parent := FForm;
  mChain.Width := 600;
  mChain.SetAnswer(Sample);
  mLines := mChain.Lines;
  Assert.AreEqual(7, Integer(Length(mLines)));
  Assert.AreEqual('1  TKundenForm · uKundenForm · uKundenForm.pas:5', mLines[0]);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeContains), mLines[1]);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeCalls) + ' · uKundenForm.pas:21', mLines[3]);
  // Erschlossene Kante mit Kennzeichen.
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeImplementedBy) + ' [' +
    TAtlasStrings.Text(TAtlasTextId.SymbolPathInferred) + '] · uKundenRepo.pas:8', mLines[5]);
  // Die Kette wächst mit ihrem Inhalt; Zeilen liegen untereinander.
  Assert.IsTrue(mChain.RowRect(6).Bottom <= mChain.Height);
  Assert.IsTrue(mChain.RowRect(1).Top >= mChain.RowRect(0).Bottom);
  mChain.PaintTo(FForm.Canvas.Handle, 0, 0);
end;

procedure TAtlasSymbolPathUiTests.ChainSelectsAndOpens;
var
  mChain: TAtlasSymbolPathChain;
  mKey: Word;
  mBounds: TRect;
begin
  mChain := TAtlasSymbolPathChain.Create(FForm);
  mChain.Parent := FForm;
  mChain.Width := 600;
  mChain.OnOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      FOpened := AFileName;
      FLine := ALine;
    end;
  mChain.SetAnswer(Sample);
  Assert.AreEqual(0, mChain.Selected);
  // Treffer unter der Maus.
  mBounds := mChain.RowRect(3);
  Assert.AreEqual(3, mChain.RowAt(mBounds.Top + 1));
  Assert.AreEqual(-1, mChain.RowAt(mChain.Height + 10));
  mChain.Selected := 3;
  mKey := VK_RETURN;
  TAtlasSymbolPathChainAccess(mChain).KeyDown(mKey, []);
  Assert.AreEqual('C:\P\uKundenForm.pas', FOpened);
  Assert.AreEqual(20, FLine);
  mKey := VK_DOWN;
  TAtlasSymbolPathChainAccess(mChain).KeyDown(mKey, []);
  Assert.AreEqual(4, mChain.Selected);
  mKey := VK_UP;
  TAtlasSymbolPathChainAccess(mChain).KeyDown(mKey, []);
  // KeyDown setzt Key auf 0 (verarbeitet).
  mKey := VK_UP;
  TAtlasSymbolPathChainAccess(mChain).KeyDown(mKey, []);
  Assert.AreEqual(2, mChain.Selected);
end;

procedure TAtlasSymbolPathUiTests.StatusTexts;
var
  mAnswer: TAtlasSymbolPathAnswer;
begin
  mAnswer := Sample;
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.SymbolPathFound, [3, 42, 7]),
    TAtlasSymbolPathChain.StatusText(mAnswer));
  mAnswer.Routes := mAnswer.Routes + [mAnswer.Routes[0]];
  mAnswer.MoreRoutes := True;
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.SymbolPathFoundMany, [3, 2, 42, 7]) +
    TAtlasStrings.Text(TAtlasTextId.SymbolPathMoreRoutes), TAtlasSymbolPathChain.StatusText(mAnswer));
  mAnswer.Status := TAtlasSymbolPathStatus.NoPath;
  mAnswer.Routes := nil;
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.SymbolPathNoPath, [8, 42]), TAtlasSymbolPathChain.StatusText(mAnswer));
  mAnswer.Status := TAtlasSymbolPathStatus.Aborted;
  mAnswer.AbortReason := 'Zeitlimit';
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.SymbolPathAborted, [3, 42, 'Zeitlimit']),
    TAtlasSymbolPathChain.StatusText(mAnswer));
  mAnswer.Status := TAtlasSymbolPathStatus.Ambiguous;
  mAnswer.Subject := 'Laden';
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.SymbolPathAmbiguous, ['Laden']),
    TAtlasSymbolPathChain.StatusText(mAnswer));
  mAnswer.Status := TAtlasSymbolPathStatus.NotFound;
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.SymbolPathNotFound, ['Laden']),
    TAtlasSymbolPathChain.StatusText(mAnswer));
end;

procedure TAtlasSymbolPathUiTests.StepCaptionsFollowKind;
var
  mStep: TAtlasSymbolPathStep;
begin
  mStep := Default(TAtlasSymbolPathStep);
  mStep.Kind := 'uses';
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeUses), TAtlasSymbolPathChain.StepCaption(mStep));
  mStep.Implementation_ := True;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeUsesImpl), TAtlasSymbolPathChain.StepCaption(mStep));
  mStep := Default(TAtlasSymbolPathStep);
  mStep.Kind := 'implements';
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeImplements), TAtlasSymbolPathChain.StepCaption(mStep));
  mStep.Reverse := True;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeImplementedBy),
    TAtlasSymbolPathChain.StepCaption(mStep));
  mStep := Default(TAtlasSymbolPathStep);
  mStep.Kind := 'hasField';
  mStep.Caption := 'vom Typ';
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeOfType), TAtlasSymbolPathChain.StepCaption(mStep));
  mStep.Caption := 'hat Feld';
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeHasField), TAtlasSymbolPathChain.StepCaption(mStep));
  mStep.Kind := 'neu';
  mStep.Caption := 'vom Server';
  Assert.AreEqual('vom Server', TAtlasSymbolPathChain.StepCaption(mStep));
  Assert.AreEqual('', TAtlasSymbolPathChain.LocationText('', 3));
  Assert.AreEqual('Kunden.pas:4', TAtlasSymbolPathChain.LocationText('C:\P\Kunden.pas', 3));
end;

procedure TAtlasSymbolPathUiTests.DialogValidatesAndSuggests;
var
  mDialog: TAtlasSymbolPathDialog;
  mInput: TAtlasSymbolPathRequestInput;
begin
  mDialog := TAtlasSymbolPathDialog.CreateDialog(FForm,
    function(const APattern: string): TArray<string>
    begin
      Result := TArray<string>.Create(APattern + 'Form', APattern + 'Form', 'TKundenRepo.Laden');
    end);
  try
    // Ohne beide Angaben bleibt der Dialog offen und sagt, was fehlt.
    Assert.IsFalse(mDialog.Validate);
    Assert.AreEqual(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SymbolPathMissing), mDialog.MessageLabel.Caption);
    mInput := Default(TAtlasSymbolPathRequestInput);
    mInput.From := 'TKundenForm';
    mInput.MaxSteps := 40;
    mDialog.Input := mInput;
    Assert.IsFalse(mDialog.Validate);
    Assert.AreEqual(8, mDialog.Input.MaxSteps, 'außerhalb 1–16: Vorgabe');
    // Vorschläge ohne Doppelte, Übernahme ins Feld.
    mDialog.ToEdit.Text := 'TKunden';
    mDialog.Suggest(mDialog.ToEdit);
    Assert.IsTrue(mDialog.SuggestionList.Visible);
    Assert.AreEqual(2, mDialog.SuggestionList.Items.Count);
    mDialog.SuggestionList.ItemIndex := 1;
    mDialog.TakeSuggestion;
    Assert.AreEqual('TKundenRepo.Laden', mDialog.ToEdit.Text);
    Assert.IsFalse(mDialog.SuggestionList.Visible);
    Assert.IsTrue(mDialog.Validate);
    mDialog.AllCheck.Checked := True;
    mDialog.StepsEdit.Text := '5';
    mInput := mDialog.Input;
    Assert.AreEqual('TKundenForm', mInput.From);
    Assert.AreEqual('TKundenRepo.Laden', mInput.To_);
    Assert.AreEqual(5, mInput.MaxSteps);
    Assert.IsTrue(mInput.All);
    // Leeres Feld: keine Vorschläge.
    mDialog.ToEdit.Text := '';
    mDialog.Suggest(mDialog.ToEdit);
    Assert.IsFalse(mDialog.SuggestionList.Visible);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasSymbolPathUiTests.ResultsFrameShowsChain;
var
  mFrame: TAtlasResultsFrame;
  mAnswer: TAtlasSymbolPathAnswer;
begin
  mFrame := TAtlasResultsFrame.Create(FForm);
  mFrame.Parent := FForm;
  mFrame.Align := alClient;
  mFrame.OnOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      FOpened := AFileName;
      FLine := ALine;
    end;
  mFrame.Path.OnShowRoute :=
    procedure(const AUnits: TArray<string>)
    begin
      FRoute := AUnits;
    end;
  mAnswer := Sample;
  mFrame.Path.Show('Weg', mAnswer, True);
  Assert.IsTrue(mFrame.Path.Shows);
  Assert.IsFalse(mFrame.Tree.Visible);
  Assert.AreEqual(TAtlasSymbolPathChain.StatusText(mAnswer), mFrame.Path.Status.Caption);
  Assert.IsTrue(mFrame.Path.MapButton.Visible);
  mFrame.Path.MapButton.Click;
  Assert.AreEqual('uKundenForm,uRepoIntf,uKundenRepo', string.Join(',', FRoute));
  // Doppelklick in der Kette geht an OnOpen des Ergebnisfensters.
  mFrame.Path.Chain.Selected := 6;
  TAtlasSymbolPathChainAccess(mFrame.Path.Chain).DblClick;
  Assert.AreEqual('C:\P\uKundenRepo.pas', FOpened);
  // Ohne Architekturübersicht kein Knopf; Hinweis ohne Kette.
  mFrame.Path.Show('Weg', mAnswer, False);
  Assert.IsFalse(mFrame.Path.MapButton.Visible);
  mFrame.Path.ShowText('Weg', 'Suche …');
  Assert.AreEqual('Suche …', mFrame.Path.Status.Caption);
  Assert.AreEqual(0, Integer(Length(mFrame.Path.Chain.Rows)));
  // Andere Listen zeigen wieder den Baum.
  mFrame.Entries.Show('Referenzen', nil);
  Assert.IsFalse(mFrame.Path.Shows);
  Assert.IsTrue(mFrame.Tree.Visible);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSymbolPathUiTests);

end.
