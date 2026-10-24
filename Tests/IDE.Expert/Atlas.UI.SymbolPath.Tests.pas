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
  Chain: TAtlasSymbolPathChain;
  Lines: TArray<string>;
begin
  Chain := TAtlasSymbolPathChain.Create(FForm);
  Chain.Parent := FForm;
  Chain.Width := 600;
  Chain.SetAnswer(Sample);
  Lines := Chain.Lines;
  Assert.AreEqual(7, Integer(Length(Lines)));
  Assert.AreEqual('1  TKundenForm · uKundenForm · uKundenForm.pas:5', Lines[0]);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeContains), Lines[1]);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeCalls) + ' · uKundenForm.pas:21', Lines[3]);
  // Erschlossene Kante mit Kennzeichen.
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeImplementedBy) + ' [' +
    TAtlasStrings.Text(TAtlasTextId.SymbolPathInferred) + '] · uKundenRepo.pas:8', Lines[5]);
  // Die Kette wächst mit ihrem Inhalt; Zeilen liegen untereinander.
  Assert.IsTrue(Chain.RowRect(6).Bottom <= Chain.Height);
  Assert.IsTrue(Chain.RowRect(1).Top >= Chain.RowRect(0).Bottom);
  Chain.PaintTo(FForm.Canvas.Handle, 0, 0);
end;

procedure TAtlasSymbolPathUiTests.ChainSelectsAndOpens;
var
  Chain: TAtlasSymbolPathChain;
  Key: Word;
  Bounds: TRect;
begin
  Chain := TAtlasSymbolPathChain.Create(FForm);
  Chain.Parent := FForm;
  Chain.Width := 600;
  Chain.OnOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      FOpened := AFileName;
      FLine := ALine;
    end;
  Chain.SetAnswer(Sample);
  Assert.AreEqual(0, Chain.Selected);
  // Treffer unter der Maus.
  Bounds := Chain.RowRect(3);
  Assert.AreEqual(3, Chain.RowAt(Bounds.Top + 1));
  Assert.AreEqual(-1, Chain.RowAt(Chain.Height + 10));
  Chain.Selected := 3;
  Key := VK_RETURN;
  TAtlasSymbolPathChainAccess(Chain).KeyDown(Key, []);
  Assert.AreEqual('C:\P\uKundenForm.pas', FOpened);
  Assert.AreEqual(20, FLine);
  Key := VK_DOWN;
  TAtlasSymbolPathChainAccess(Chain).KeyDown(Key, []);
  Assert.AreEqual(4, Chain.Selected);
  Key := VK_UP;
  TAtlasSymbolPathChainAccess(Chain).KeyDown(Key, []);
  TAtlasSymbolPathChainAccess(Chain).KeyDown(Key, []);
  Assert.AreEqual(2, Chain.Selected);
end;

procedure TAtlasSymbolPathUiTests.StatusTexts;
var
  Answer: TAtlasSymbolPathAnswer;
begin
  Answer := Sample;
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.SymbolPathFound, [3, 42, 7]),
    TAtlasSymbolPathChain.StatusText(Answer));
  Answer.Routes := Answer.Routes + [Answer.Routes[0]];
  Answer.MoreRoutes := True;
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.SymbolPathFoundMany, [3, 2, 42, 7]) +
    TAtlasStrings.Text(TAtlasTextId.SymbolPathMoreRoutes), TAtlasSymbolPathChain.StatusText(Answer));
  Answer.Status := TAtlasSymbolPathStatus.NoPath;
  Answer.Routes := nil;
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.SymbolPathNoPath, [8, 42]), TAtlasSymbolPathChain.StatusText(Answer));
  Answer.Status := TAtlasSymbolPathStatus.Aborted;
  Answer.AbortReason := 'Zeitlimit';
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.SymbolPathAborted, [3, 42, 'Zeitlimit']),
    TAtlasSymbolPathChain.StatusText(Answer));
  Answer.Status := TAtlasSymbolPathStatus.Ambiguous;
  Answer.Subject := 'Laden';
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.SymbolPathAmbiguous, ['Laden']),
    TAtlasSymbolPathChain.StatusText(Answer));
  Answer.Status := TAtlasSymbolPathStatus.NotFound;
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.SymbolPathNotFound, ['Laden']),
    TAtlasSymbolPathChain.StatusText(Answer));
end;

procedure TAtlasSymbolPathUiTests.StepCaptionsFollowKind;
var
  Step: TAtlasSymbolPathStep;
begin
  Step := Default(TAtlasSymbolPathStep);
  Step.Kind := 'uses';
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeUses), TAtlasSymbolPathChain.StepCaption(Step));
  Step.Implementation_ := True;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeUsesImpl), TAtlasSymbolPathChain.StepCaption(Step));
  Step := Default(TAtlasSymbolPathStep);
  Step.Kind := 'implements';
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeImplements), TAtlasSymbolPathChain.StepCaption(Step));
  Step.Reverse := True;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeImplementedBy),
    TAtlasSymbolPathChain.StepCaption(Step));
  Step := Default(TAtlasSymbolPathStep);
  Step.Kind := 'hasField';
  Step.Caption := 'vom Typ';
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeOfType), TAtlasSymbolPathChain.StepCaption(Step));
  Step.Caption := 'hat Feld';
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeHasField), TAtlasSymbolPathChain.StepCaption(Step));
  Step.Kind := 'neu';
  Step.Caption := 'vom Server';
  Assert.AreEqual('vom Server', TAtlasSymbolPathChain.StepCaption(Step));
  Assert.AreEqual('', TAtlasSymbolPathChain.LocationText('', 3));
  Assert.AreEqual('Kunden.pas:4', TAtlasSymbolPathChain.LocationText('C:\P\Kunden.pas', 3));
end;

procedure TAtlasSymbolPathUiTests.DialogValidatesAndSuggests;
var
  Dialog: TAtlasSymbolPathDialog;
  Input: TAtlasSymbolPathRequestInput;
begin
  Dialog := TAtlasSymbolPathDialog.CreateDialog(FForm,
    function(const APattern: string): TArray<string>
    begin
      Result := TArray<string>.Create(APattern + 'Form', APattern + 'Form', 'TKundenRepo.Laden');
    end);
  try
    // Ohne beide Angaben bleibt der Dialog offen und sagt, was fehlt.
    Assert.IsFalse(Dialog.Validate);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SymbolPathMissing), Dialog.MessageLabel.Caption);
    Input := Default(TAtlasSymbolPathRequestInput);
    Input.From := 'TKundenForm';
    Input.MaxSteps := 40;
    Dialog.Input := Input;
    Assert.IsFalse(Dialog.Validate);
    Assert.AreEqual(8, Dialog.Input.MaxSteps, 'außerhalb 1–16: Vorgabe');
    // Vorschläge ohne Doppelte, Übernahme ins Feld.
    Dialog.ToEdit.Text := 'TKunden';
    Dialog.Suggest(Dialog.ToEdit);
    Assert.IsTrue(Dialog.SuggestionList.Visible);
    Assert.AreEqual(2, Dialog.SuggestionList.Items.Count);
    Dialog.SuggestionList.ItemIndex := 1;
    Dialog.TakeSuggestion;
    Assert.AreEqual('TKundenRepo.Laden', Dialog.ToEdit.Text);
    Assert.IsFalse(Dialog.SuggestionList.Visible);
    Assert.IsTrue(Dialog.Validate);
    Dialog.AllCheck.Checked := True;
    Dialog.StepsEdit.Text := '5';
    Input := Dialog.Input;
    Assert.AreEqual('TKundenForm', Input.From);
    Assert.AreEqual('TKundenRepo.Laden', Input.To_);
    Assert.AreEqual(5, Input.MaxSteps);
    Assert.IsTrue(Input.All);
    // Leeres Feld: keine Vorschläge.
    Dialog.ToEdit.Text := '';
    Dialog.Suggest(Dialog.ToEdit);
    Assert.IsFalse(Dialog.SuggestionList.Visible);
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasSymbolPathUiTests.ResultsFrameShowsChain;
var
  Frame: TAtlasResultsFrame;
  Answer: TAtlasSymbolPathAnswer;
begin
  Frame := TAtlasResultsFrame.Create(FForm);
  Frame.Parent := FForm;
  Frame.Align := alClient;
  Frame.OnOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      FOpened := AFileName;
      FLine := ALine;
    end;
  Frame.OnShowRoute :=
    procedure(const AUnits: TArray<string>)
    begin
      FRoute := AUnits;
    end;
  Answer := Sample;
  Frame.ShowSymbolPath('Weg', Answer, True);
  Assert.IsTrue(Frame.ShowsPath);
  Assert.IsFalse(Frame.Tree.Visible);
  Assert.AreEqual(TAtlasSymbolPathChain.StatusText(Answer), Frame.PathStatus.Caption);
  Assert.IsTrue(Frame.PathMapButton.Visible);
  Frame.PathMapButton.Click;
  Assert.AreEqual('uKundenForm,uRepoIntf,uKundenRepo', string.Join(',', FRoute));
  // Doppelklick in der Kette geht an OnOpen des Ergebnisfensters.
  Frame.PathChain.Selected := 6;
  TAtlasSymbolPathChainAccess(Frame.PathChain).DblClick;
  Assert.AreEqual('C:\P\uKundenRepo.pas', FOpened);
  // Ohne Architekturübersicht kein Knopf; Hinweis ohne Kette.
  Frame.ShowSymbolPath('Weg', Answer, False);
  Assert.IsFalse(Frame.PathMapButton.Visible);
  Frame.ShowSymbolPathMessage('Weg', 'Suche …');
  Assert.AreEqual('Suche …', Frame.PathStatus.Caption);
  Assert.AreEqual(0, Integer(Length(Frame.PathChain.Rows)));
  // Andere Listen zeigen wieder den Baum.
  Frame.ShowEntries('Referenzen', nil);
  Assert.IsFalse(Frame.ShowsPath);
  Assert.IsTrue(Frame.Tree.Visible);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSymbolPathUiTests);

end.
