unit Atlas.Core.Hover.Layout.Tests;

// Tests für den Satz des Hover-Tooltips ohne VCL (P-09). Die erwarteten Zahlen
// sind aus dem bisherigen Render (Atlas.UI.Hover.Tip vor P-09) mit denselben
// Messwerten nachgerechnet; so bleibt das Aussehen festgehalten.
// Messwerte: Breite je Zeichen UI 7, Editorschrift 8 (halbfett 9), klein 6;
// Zeilenhöhe UI 15, Editorschrift 16, klein UI 13, klein Editorschrift 12; 96 dpi.

interface

uses
  DUnitX.TestFramework,
  System.Types,
  Atlas.Core.Hover.Contract,
  Atlas.Core.Hover.History,
  Atlas.Core.Hover.Layout;

type
  [TestFixture]
  THoverLayoutTests = class
  private
    function Input(const AView: TAtlasHoverView; AWidth: Integer): TAtlasHoverInput;
    function Build(const AView: TAtlasHoverView; AWidth: Integer): TAtlasHoverLayout; overload;
    function Build(const AInput: TAtlasHoverInput): TAtlasHoverLayout; overload;
    function View(const ADeclaration: string): TAtlasHoverView;
    procedure CheckRect(const AExpected, AActual: TRect; const AWhat: string);
    function CountKind(const ALayout: TAtlasHoverLayout; AKind: TAtlasHoverItemKind): Integer;
    function FirstKind(const ALayout: TAtlasHoverLayout; AKind: TAtlasHoverItemKind): Integer;
  public
    [Test]
    procedure DeclarationOnlyHasOneTextLine;
    [Test]
    procedure LongDeclarationWrapsWithIndent;
    [Test]
    procedure ProblemsProduceBlockAndBar;
    [Test]
    procedure DebugValueProducesExpressionValueAndBar;
    [Test]
    procedure DebugValuePendingShowsPlaceholder;
    [Test]
    procedure DebugValueAboveDeclaration;
    [Test]
    procedure FailedDebugValueIsHidden;
    [Test]
    procedure UnavailableValueShowsCauseAndFixes;
    [Test]
    procedure UnavailableValuePendingAndChecked;
    [Test]
    procedure PathChipsProduceHits;
    [Test]
    procedure PinnedShowsActions;
    [Test]
    procedure AnchorMovesLastBandDown;
    [Test]
    procedure ChainProducesChipsAndHits;
    [Test]
    procedure HeightGrowsWithDocHeight;
    [Test]
    procedure HitAtFindsActionRect;
    [Test]
    procedure BuildIsDeterministic;
    /// <summary>#621: uses-Hinweise bringen ihre Aktionen als Klickflächen mit.</summary>
    [Test]
    procedure UsesProblemsOfferActions;
    /// <summary>#909: Fehler zuerst, Pille mit der Art, Herkunft mit Regel-ID bzw. Meldungsnummer.</summary>
    [Test]
    procedure FindingsShowPillAndRuleErrorsFirst;
    /// <summary>#1024: vom Build bestätigter Befund mit „Atlas + dcc“ und Code; ohne Code ohne „(wie …)“.
    /// </summary>
    [Test]
    procedure ConfirmedFindingShowsBothSources;
    /// <summary>#909: Aktionszeile nur an Regelbefunden und nur mit hover.problemActions.</summary>
    [Test]
    procedure RuleFindingsOfferActions;
    /// <summary>#909: Tab wandert reihum über die Aktionen unter den Befunden.</summary>
    [Test]
    procedure NextProblemHitCycles;
    /// <summary>#110: published-Mitglieder als Tabellen mit Schaltern.</summary>
    [Test]
    procedure PublishedMembersAsTables;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Wrap,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Hover.DebugValue;

type
  TFakeMeasure = class(TInterfacedObject, IAtlasHoverMeasure)
  private
    FDeclaration: string;
    function Cum: TArray<Integer>;
  public
    constructor Create(const ADeclaration: string);
    function TextWidth(const AFace: TAtlasHoverFace; const AText: string): Integer;
    function TextHeight(const AFace: TAtlasHoverFace): Integer;
    function BlockHeight(const AText: string; AWidth: Integer): Integer;
    function DeclarationWidth(AFrom, ATill: Integer): Integer;
    function DeclarationLines(AWidth, AIndent: Integer): TArray<TPoint>;
  end;

constructor TFakeMeasure.Create(const ADeclaration: string);
begin
  inherited Create;
  FDeclaration := ADeclaration;
end;

function TFakeMeasure.Cum: TArray<Integer>;
var
  Index: Integer;
begin
  Result := nil;
  SetLength(Result, Length(FDeclaration) + 1);
  for Index := 0 to Length(FDeclaration) do
    Result[Index] := 8 * Index;
end;

function TFakeMeasure.TextWidth(const AFace: TAtlasHoverFace; const AText: string): Integer;
begin
  case AFace.Font of
    TAtlasHoverFont.Ui:
      Result := 7 * Length(AText);
    TAtlasHoverFont.Mono:
      if AFace.Bold then
        Result := 9 * Length(AText)
      else
        Result := 8 * Length(AText);
  else
    Result := 6 * Length(AText);
  end;
end;

function TFakeMeasure.TextHeight(const AFace: TAtlasHoverFace): Integer;
begin
  case AFace.Font of
    TAtlasHoverFont.Ui:
      Result := 15;
    TAtlasHoverFont.Mono:
      Result := 16;
    TAtlasHoverFont.SmallUi:
      Result := 13;
  else
    Result := 12;
  end;
end;

function TFakeMeasure.BlockHeight(const AText: string; AWidth: Integer): Integer;
begin
  Result := 15 * ((7 * Length(AText) + AWidth - 1) div AWidth);
end;

function TFakeMeasure.DeclarationWidth(AFrom, ATill: Integer): Integer;
begin
  Result := 8 * (ATill - AFrom);
end;

function TFakeMeasure.DeclarationLines(AWidth, AIndent: Integer): TArray<TPoint>;
begin
  Result := TAtlasWrap.AtSpaces(FDeclaration, Cum, AWidth, AIndent);
end;

{ THoverLayoutTests }

function THoverLayoutTests.View(const ADeclaration: string): TAtlasHoverView;
var
  Data: TAtlasHoverData;
begin
  Data := Default(TAtlasHoverData);
  Data.Declaration := ADeclaration;
  Result := TAtlasHoverView.Create(Data);
end;

function THoverLayoutTests.Input(const AView: TAtlasHoverView; AWidth: Integer): TAtlasHoverInput;
begin
  Result := Default(TAtlasHoverInput);
  Result.View := AView;
  Result.Width := AWidth;
  Result.PPI := 96;
  Result.Colors := TAtlasColors.Light;
  Result.Texts.Pinned := 'pinned';
  Result.Texts.Inheritance := 'Vererbung';
  Result.Texts.TargetType := 'Ziel %s';
  Result.Texts.Navigate := 'Go';
  Result.Texts.Usages := 'Us';
  Result.Texts.UsagesCount := '%d Us';
  Result.Texts.Copy := 'Cp';
  Result.Texts.CopySelection := 'Sel';
  Result.Texts.Help := 'H';
  Result.Texts.KeyUsages := 'U';
  Result.Texts.KeyCopy := 'C';
  Result.Texts.SourceAtlas := 'Atlas';
  Result.Texts.SourceCompiler := 'dcc';
  Result.Texts.SourceInactive := 'inaktiv';
  Result.Texts.Stale := 'alt';
  Result.Texts.DebugPending := 'eval';
  Result.Texts.DebugExplaining := 'sucht';
  Result.Texts.DebugChecked := 'geprüft';
end;

function THoverLayoutTests.Build(const AInput: TAtlasHoverInput): TAtlasHoverLayout;
begin
  Result := TAtlasHoverLayout.Build(AInput, TFakeMeasure.Create(AInput.View.Data.Declaration));
end;

function THoverLayoutTests.Build(const AView: TAtlasHoverView; AWidth: Integer): TAtlasHoverLayout;
begin
  Result := Build(Input(AView, AWidth));
end;

procedure THoverLayoutTests.CheckRect(const AExpected, AActual: TRect; const AWhat: string);
begin
  Assert.AreEqual(AExpected.Left, AActual.Left, AWhat + ' links');
  Assert.AreEqual(AExpected.Top, AActual.Top, AWhat + ' oben');
  Assert.AreEqual(AExpected.Right, AActual.Right, AWhat + ' rechts');
  Assert.AreEqual(AExpected.Bottom, AActual.Bottom, AWhat + ' unten');
end;

function THoverLayoutTests.CountKind(const ALayout: TAtlasHoverLayout; AKind: TAtlasHoverItemKind): Integer;
var
  Item: TAtlasHoverItem;
begin
  Result := 0;
  for Item in ALayout.Items do
    if Item.Kind = AKind then
      Inc(Result);
end;

function THoverLayoutTests.FirstKind(const ALayout: TAtlasHoverLayout; AKind: TAtlasHoverItemKind): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ALayout.Items) do
    if ALayout.Items[Index].Kind = AKind then
      Exit(Index);
  Result := -1;
end;

procedure THoverLayoutTests.DeclarationOnlyHasOneTextLine;
var
  Layout: TAtlasHoverLayout;
begin
  Layout := Build(View('x: Integer'), 300);
  Assert.AreEqual(1, Integer(Length(Layout.Items)));
  Assert.AreEqual(0, Integer(Length(Layout.Hits)));
  Assert.IsTrue(Layout.Items[0].Kind = TAtlasHoverItemKind.Styled);
  CheckRect(Rect(11, 8, 289, 26), Layout.Items[0].Rect, 'Deklaration');
  Assert.AreEqual(0, Layout.Items[0].From);
  Assert.AreEqual(10, Layout.Items[0].Till);
  Assert.AreEqual(32, Layout.Height);
end;

procedure THoverLayoutTests.LongDeclarationWrapsWithIndent;
var
  Layout: TAtlasHoverLayout;
begin
  Layout := Build(View('procedure Foo(A: Integer; B: string)'), 200);
  Assert.AreEqual(2, CountKind(Layout, TAtlasHoverItemKind.Styled));
  CheckRect(Rect(11, 8, 189, 26), Layout.Items[0].Rect, 'Zeile 1');
  Assert.AreEqual(17, Layout.Items[0].Till);
  CheckRect(Rect(27, 26, 189, 44), Layout.Items[1].Rect, 'Zeile 2 eingerückt');
  Assert.AreEqual(17, Layout.Items[1].From);
  Assert.AreEqual(36, Layout.Items[1].Till);
  Assert.AreEqual(50, Layout.Height);
end;

procedure THoverLayoutTests.ProblemsProduceBlockAndBar;
var
  HoverView: TAtlasHoverView;
  Problem: TAtlasProblem;
  Layout: TAtlasHoverLayout;
  Bar: Integer;
  Colors: TAtlasColors;
begin
  HoverView := View('');
  Problem := Default(TAtlasProblem);
  Problem.Message := 'x';
  Problem.Severity := TAtlasProblemSeverity.Error;
  HoverView.Problems := [Problem];
  Layout := Build(HoverView, 300);
  Assert.IsTrue(Layout.Items[0].Kind = TAtlasHoverItemKind.Block);
  CheckRect(Rect(20, 8, 289, 23), Layout.Items[0].Rect, 'Meldung');
  Assert.IsTrue(Layout.Items[1].Kind = TAtlasHoverItemKind.Text);
  Assert.AreEqual('Atlas', Layout.Items[1].Text);
  Assert.AreEqual(20, Layout.Items[1].Rect.Left);
  Assert.AreEqual(25, Layout.Items[1].Rect.Top);
  Bar := FirstKind(Layout, TAtlasHoverItemKind.RoundFill);
  Assert.IsTrue(Bar >= 0);
  CheckRect(Rect(11, 9, 14, 37), Layout.Items[Bar].Rect, 'Farbbalken');
  Colors := TAtlasColors.Light;
  Assert.AreEqual(Colors.Error, Layout.Items[Bar].Color);
  // Ohne Deklaration endet der Tooltip nach den Problemen.
  Assert.AreEqual(46, Layout.Height);
end;

procedure THoverLayoutTests.DebugValueProducesExpressionValueAndBar;
var
  HoverView: TAtlasHoverView;
  Layout: TAtlasHoverLayout;
  Bar: Integer;
  Colors: TAtlasColors;
begin
  // #891: Ausdruck in der Editorschrift (halbfett, Akzent), darunter der Wert, links ein Akzentbalken.
  HoverView := View('');
  HoverView.DebugValue := TAtlasDebugValue.Evaluated('Count', '3');
  Layout := Build(HoverView, 300);
  Colors := TAtlasColors.Light;
  Assert.IsTrue(Layout.Items[0].Kind = TAtlasHoverItemKind.Text);
  Assert.AreEqual('Count', Layout.Items[0].Text);
  Assert.IsTrue(Layout.Items[0].Face.Font = TAtlasHoverFont.Mono);
  Assert.IsTrue(Layout.Items[0].Face.Bold);
  Assert.AreEqual(Colors.Accent, Layout.Items[0].Color);
  Assert.AreEqual(20, Layout.Items[0].Rect.Left);
  Assert.AreEqual(8, Layout.Items[0].Rect.Top);
  Assert.IsTrue(Layout.Items[1].Kind = TAtlasHoverItemKind.Block);
  Assert.AreEqual('3', Layout.Items[1].Text);
  Assert.AreEqual(Colors.Text, Layout.Items[1].Color);
  CheckRect(Rect(20, 27, 289, 42), Layout.Items[1].Rect, 'Wert');
  Bar := FirstKind(Layout, TAtlasHoverItemKind.RoundFill);
  Assert.IsTrue(Bar >= 0);
  CheckRect(Rect(11, 9, 14, 41), Layout.Items[Bar].Rect, 'Akzentbalken');
  Assert.AreEqual(Colors.Accent, Layout.Items[Bar].Color);
  // Ohne Deklaration und Probleme endet der Tooltip nach dem Wert.
  Assert.AreEqual(50, Layout.Height);
end;

procedure THoverLayoutTests.DebugValuePendingShowsPlaceholder;
var
  HoverView: TAtlasHoverView;
  Layout: TAtlasHoverLayout;
  Colors: TAtlasColors;
begin
  HoverView := View('');
  HoverView.DebugValue := TAtlasDebugValue.Pending('FList.Count');
  Layout := Build(HoverView, 300);
  Colors := TAtlasColors.Light;
  Assert.AreEqual('FList.Count', Layout.Items[0].Text);
  Assert.IsTrue(Layout.Items[1].Kind = TAtlasHoverItemKind.Block);
  Assert.AreEqual('eval', Layout.Items[1].Text);
  Assert.AreEqual(Colors.Muted, Layout.Items[1].Color);
end;

procedure THoverLayoutTests.DebugValueAboveDeclaration;
var
  HoverView: TAtlasHoverView;
  Layout: TAtlasHoverLayout;
  Line, Styled: Integer;
begin
  HoverView := View('var Count: Integer');
  HoverView.DebugValue := TAtlasDebugValue.Evaluated('Count', '3');
  Layout := Build(HoverView, 300);
  // Trennlinie unter dem Wert, danach die Deklaration.
  Line := FirstKind(Layout, TAtlasHoverItemKind.Line);
  Assert.IsTrue(Line >= 0);
  Assert.AreEqual(48, Layout.Items[Line].Rect.Top);
  Styled := FirstKind(Layout, TAtlasHoverItemKind.Styled);
  Assert.IsTrue(Styled > Line);
  Assert.IsTrue(Layout.Items[Styled].Rect.Top >= 56);
end;

procedure THoverLayoutTests.FailedDebugValueIsHidden;
var
  HoverView: TAtlasHoverView;
  Layout: TAtlasHoverLayout;
  Item: TAtlasHoverItem;
begin
  // Fehler der Auswertung ohne Erklärung zeigt der Tooltip nicht (#840 erklärt nur „kein Zugriff“).
  HoverView := View('var Count: Integer');
  HoverView.DebugValue := TAtlasDebugValue.Failed('Count', 'E2003 Undeclared identifier');
  Layout := Build(HoverView, 300);
  for Item in Layout.Items do
    Assert.IsFalse(Item.Text = 'Count', 'kein Abschnitt für den Wert');
  Assert.AreEqual(Integer(0), CountKind(Layout, TAtlasHoverItemKind.RoundFill));
end;

function Unavailable(const AReason: string): TAtlasDebugValue;
begin
  Result := TAtlasDebugValue.Failed('Summe', 'Inaccessible value');
  Result.Note.Caption := 'kein Zugriff';
  Result.Note.Reason := AReason;
end;

procedure THoverLayoutTests.UnavailableValueShowsCauseAndFixes;
var
  HoverView: TAtlasHoverView;
  Layout: TAtlasHoverLayout;
  Colors: TAtlasColors;
  Hit: TAtlasHoverHit;
  Fixes: Integer;
begin
  // „kein Zugriff“ (#840): Kennzeichen in der Warnfarbe, Ursache, Herkunft, Korrekturen als Klickflächen.
  HoverView := View('');
  HoverView.DebugValue := Unavailable('O+');
  HoverView.DebugValue.Note.Origin := '{$O+} in Kunden.pas, Zeile 12';
  HoverView.DebugValue.Note.Fixes := [TAtlasDebugValueFix.Create(1, 'Routine'), TAtlasDebugValueFix.Create(2,
    'Unit')];
  Layout := Build(HoverView, 300);
  Colors := TAtlasColors.Light;
  Assert.AreEqual('Summe', Layout.Items[0].Text);
  Assert.AreEqual('kein Zugriff', Layout.Items[1].Text);
  Assert.AreEqual(Colors.Warn, Layout.Items[1].Color);
  Assert.AreEqual('O+', Layout.Items[2].Text);
  Assert.AreEqual('{$O+} in Kunden.pas, Zeile 12', Layout.Items[3].Text);
  Assert.AreEqual(Colors.Muted, Layout.Items[3].Color);
  Fixes := 0;
  for Hit in Layout.Hits do
    if Hit.Kind = TAtlasHoverHitKind.DebugFix then
    begin
      Assert.AreEqual(Fixes, Hit.Index, 'Index in Note.Fixes');
      Inc(Fixes);
    end;
  Assert.AreEqual(2, Fixes);
end;

procedure THoverLayoutTests.UnavailableValuePendingAndChecked;
var
  HoverView: TAtlasHoverView;
  Layout: TAtlasHoverLayout;
  Hit: TAtlasHoverHit;
begin
  HoverView := View('');
  HoverView.DebugValue := Unavailable('');
  HoverView.DebugValue.Note.Pending := True;
  Layout := Build(HoverView, 300);
  Assert.AreEqual('kein Zugriff', Layout.Items[1].Text);
  Assert.AreEqual('sucht', Layout.Items[2].Text, 'solange der Server antwortet');
  HoverView.DebugValue := Unavailable('unbekannt');
  HoverView.DebugValue.Note.Checked := ['Start', 'Schalter'];
  Layout := Build(HoverView, 300);
  Assert.AreEqual('unbekannt', Layout.Items[2].Text);
  Assert.AreEqual('geprüft', Layout.Items[3].Text);
  Assert.AreEqual('• Start', Layout.Items[4].Text);
  Assert.AreEqual('• Schalter', Layout.Items[5].Text);
  for Hit in Layout.Hits do
    Assert.IsFalse(Hit.Kind = TAtlasHoverHitKind.DebugFix, 'ohne Korrekturen keine Klickfläche');
end;

procedure THoverLayoutTests.PathChipsProduceHits;
var
  HoverView: TAtlasHoverView;
  First, Second: TAtlasHoverPathItem;
  Layout: TAtlasHoverLayout;
  Index: Integer;
  Found: Boolean;
begin
  HoverView := View('x');
  HoverView.Pinned := True;
  HoverView.CanGoBack := True;
  First.Index := 0;
  First.Caption := 'TA';
  Second.Index := -1;
  Second.Caption := 'TB';
  HoverView.Path := [First, Second];
  Layout := Build(HoverView, 300);
  Assert.AreEqual(2, Integer(Length(Layout.Hits)));
  Assert.IsTrue(Layout.Hits[0].Kind = TAtlasHoverHitKind.Back);
  CheckRect(Rect(8, 5, 30, 25), Layout.Hits[0].Rect, 'Zurück');
  Assert.IsTrue(Layout.Hits[1].Kind = TAtlasHoverHitKind.Path);
  Assert.AreEqual(0, Layout.Hits[1].Index);
  CheckRect(Rect(36, 7, 52, 23), Layout.Hits[1].Rect, 'Pfad TA');
  // „angeheftet“ rechtsbündig, weil Platz ist.
  Found := False;
  for Index := 0 to High(Layout.Items) do
    if Layout.Items[Index].Text = 'pinned' then
    begin
      Found := True;
      Assert.AreEqual(253, Layout.Items[Index].Rect.Left);
      Assert.AreEqual(8, Layout.Items[Index].Rect.Top);
    end;
  Assert.IsTrue(Found);
  Assert.AreEqual(38, Layout.Items[FirstKind(Layout, TAtlasHoverItemKind.Styled)].Rect.Top);
  Assert.AreEqual(62, Layout.Height);
end;

function ActionsView: TAtlasHoverView;
var
  Data: TAtlasHoverData;
begin
  Data := Default(TAtlasHoverData);
  Data.Declaration := 'x';
  Data.Location.Name := 'x';
  Data.Location.FileName := 'C:\a\U.pas';
  Data.Location.Line := 4;
  Result := TAtlasHoverView.Create(Data);
end;

procedure THoverLayoutTests.PinnedShowsActions;
var
  Layout: TAtlasHoverLayout;
  Index: Integer;
  Found: Boolean;
begin
  Layout := Build(ActionsView, 300);
  // Hilfe ohne DocWiki: keine Klickfläche.
  Assert.AreEqual(3, Integer(Length(Layout.Hits)));
  for Index := 0 to 2 do
  begin
    Assert.IsTrue(Layout.Hits[Index].Kind = TAtlasHoverHitKind.Action);
    Assert.AreEqual(Index, Layout.Hits[Index].Index);
  end;
  CheckRect(Rect(11, 60, 47, 73), Layout.Hits[0].Rect, 'Gehe zu');
  CheckRect(Rect(61, 60, 85, 73), Layout.Hits[1].Rect, 'Verwendungen');
  CheckRect(Rect(99, 60, 123, 73), Layout.Hits[2].Rect, 'Kopieren');
  // Fundort rechtsbündig in der Kopfzeile.
  Found := False;
  for Index := 0 to High(Layout.Items) do
    if Layout.Items[Index].Text = 'U.pas : 5' then
    begin
      Found := True;
      Assert.AreEqual(235, Layout.Items[Index].Rect.Left);
      Assert.AreEqual(10, Layout.Items[Index].Rect.Top);
    end;
  Assert.IsTrue(Found);
  // Randfläche mit Linie oben vor dem Inhalt.
  Assert.AreEqual(Layout.AnchorItem, FirstKind(Layout, TAtlasHoverItemKind.Fill));
  CheckRect(Rect(0, 54, 300, 79), Layout.Items[Layout.AnchorItem].Rect, 'Randfläche');
  Assert.AreEqual(79, Layout.Height);
end;

procedure THoverLayoutTests.AnchorMovesLastBandDown;
var
  Layout: TAtlasHoverLayout;
begin
  Layout := Build(ActionsView, 300);
  Layout.Anchor(200);
  Assert.AreEqual(181, Layout.Hits[0].Rect.Top);
  Assert.AreEqual(175, Layout.Items[Layout.AnchorItem].Rect.Top);
  // Wiederholbar, nie über die eigene Lage nach oben.
  Layout.Anchor(200);
  Assert.AreEqual(181, Layout.Hits[0].Rect.Top);
  Layout.Anchor(50);
  Assert.AreEqual(60, Layout.Hits[0].Rect.Top);
end;

procedure THoverLayoutTests.ChainProducesChipsAndHits;
var
  HoverView: TAtlasHoverView;
  First, Second: TAtlasHoverTypeRef;
  Layout: TAtlasHoverLayout;
begin
  HoverView := View('x');
  First := Default(TAtlasHoverTypeRef);
  First.Name := 'TA';
  Second := Default(TAtlasHoverTypeRef);
  Second.Name := 'TObject';
  HoverView.Data.Ancestors := [First, Second];
  Layout := Build(HoverView, 300);
  Assert.AreEqual(2, Integer(Length(Layout.Hits)));
  Assert.IsTrue(Layout.Hits[0].Kind = TAtlasHoverHitKind.Ancestor);
  CheckRect(Rect(11, 58, 39, 76), Layout.Hits[0].Rect, 'TA');
  Assert.AreEqual(1, Layout.Hits[1].Index);
  CheckRect(Rect(63, 58, 131, 76), Layout.Hits[1].Rect, 'TObject');
  Assert.AreEqual(2, CountKind(Layout, TAtlasHoverItemKind.Frame));
  // Ohne Fundort ist die Kette die letzte Randfläche.
  Assert.IsTrue(Layout.AnchorItem >= 0);
  Assert.AreEqual(84, Layout.Height);
end;

procedure THoverLayoutTests.HeightGrowsWithDocHeight;
var
  HoverInput: TAtlasHoverInput;
  Layout: TAtlasHoverLayout;
begin
  HoverInput := Input(View('x'), 300);
  HoverInput.HasDoc := True;
  HoverInput.DocHeight := 100;
  Layout := Build(HoverInput);
  Assert.AreEqual(11, Layout.DocLeft);
  Assert.AreEqual(39, Layout.DocTop);
  Assert.AreEqual(146, Layout.Height);
  HoverInput.DocHeight := 40;
  Assert.AreEqual(86, Build(HoverInput).Height);
end;

procedure THoverLayoutTests.HitAtFindsActionRect;
var
  Layout: TAtlasHoverLayout;
begin
  Layout := Build(ActionsView, 300);
  Assert.AreEqual(0, Layout.HitAt(Point(20, 65)));
  Assert.AreEqual(2, Layout.HitAt(Point(100, 60)));
  Assert.AreEqual(-1, Layout.HitAt(Point(5, 5)));
  Assert.IsTrue(Layout.IsHot(1, TAtlasHoverHitKind.Action, 1));
  Assert.IsFalse(Layout.IsHot(1, TAtlasHoverHitKind.Action, 0));
  Assert.IsFalse(Layout.IsHot(-1, TAtlasHoverHitKind.Action, 1));
end;

procedure THoverLayoutTests.BuildIsDeterministic;
var
  A, B: TAtlasHoverLayout;
  Index: Integer;
begin
  A := Build(ActionsView, 300);
  B := Build(ActionsView, 300);
  Assert.AreEqual(Integer(Length(A.Items)), Integer(Length(B.Items)));
  for Index := 0 to High(A.Items) do
  begin
    CheckRect(A.Items[Index].Rect, B.Items[Index].Rect, 'Baustein');
    Assert.AreEqual(A.Items[Index].Text, B.Items[Index].Text);
  end;
  Assert.AreEqual(A.Height, B.Height);
end;

procedure THoverLayoutTests.UsesProblemsOfferActions;

  function Codes(const ALayout: TAtlasHoverLayout): string;
  var
    Hit: TAtlasHoverHit;
    Problem: Integer;
    Action: TAtlasHoverProblemAction;
  begin
    Result := '';
    for Hit in ALayout.Hits do
      if Hit.Kind = TAtlasHoverHitKind.ProblemAction then
      begin
        TAtlasHoverLayout.DecodeProblemAction(Hit.Index, Problem, Action);
        Result := Result + IntToStr(Problem) + ':' + IntToStr(Ord(Action)) + '|';
      end;
  end;

var
  HoverView: TAtlasHoverView;
  Plain, Unused, Moved: TAtlasProblem;
  HoverInput: TAtlasHoverInput;
  Problem: Integer;
  Action: TAtlasHoverProblemAction;
begin
  TAtlasHoverLayout.DecodeProblemAction(TAtlasHoverLayout.ProblemActionCode(3,
    TAtlasHoverProblemAction.MoveUses), Problem, Action);
  Assert.AreEqual(3, Problem);
  Assert.IsTrue(Action = TAtlasHoverProblemAction.MoveUses);
  Plain := Default(TAtlasProblem);
  Plain.Message := 'x';
  Unused := Plain;
  Unused.Severity := TAtlasProblemSeverity.Hint;
  Unused.UsesUnit := 'Vcl.Grids';
  Unused.UsesState := TAtlasProblem.UsesUnused;
  Unused.UsesUnusedCount := 1;
  Moved := Unused;
  Moved.UsesState := TAtlasProblem.UsesImplementation;
  HoverView := View('');
  HoverView.Problems := [Plain, Unused, Moved];
  HoverInput := Input(HoverView, 300);
  HoverInput.Texts.UsesRemove := 'Entfernen';
  HoverInput.Texts.UsesRemoveAll := 'Alle entfernen';
  HoverInput.Texts.UsesMove := 'Verschieben';
  // Ein ungenutzter Eintrag: nur „Entfernen“; der zweite Hinweis bietet „Verschieben“.
  Assert.AreEqual('1:0|2:2|', Codes(Build(HoverInput)));
  Unused.UsesUnusedCount := 2;
  HoverView.Problems := [Plain, Unused, Moved];
  HoverInput.View := HoverView;
  Assert.AreEqual('1:0|1:1|2:2|', Codes(Build(HoverInput)));
end;

function Finding(ASeverity: TAtlasProblemSeverity; const ASource, ACode, AMessage, AFix: string): TAtlasProblem;
begin
  Result := Default(TAtlasProblem);
  Result.Severity := ASeverity;
  Result.Source := ASource;
  Result.Code := ACode;
  Result.Message := AMessage;
  Result.FixTitle := AFix;
end;

function ActionCodes(const ALayout: TAtlasHoverLayout): string;
var
  Hit: TAtlasHoverHit;
  Problem: Integer;
  Action: TAtlasHoverProblemAction;
begin
  Result := '';
  for Hit in ALayout.Hits do
    if Hit.Kind = TAtlasHoverHitKind.ProblemAction then
    begin
      TAtlasHoverLayout.DecodeProblemAction(Hit.Index, Problem, Action);
      Result := Result + IntToStr(Problem) + ':' + IntToStr(Ord(Action)) + '|';
    end;
end;

function TextsOf(const ALayout: TAtlasHoverLayout; AKind: TAtlasHoverItemKind): string;
var
  Item: TAtlasHoverItem;
begin
  Result := '';
  for Item in ALayout.Items do
    if Item.Kind = AKind then
      Result := Result + Item.Text + '|';
end;

procedure THoverLayoutTests.FindingsShowPillAndRuleErrorsFirst;
var
  HoverView: TAtlasHoverView;
  HoverInput: TAtlasHoverInput;
  Layout: TAtlasHoverLayout;
  Order: TArray<Integer>;
  Pill: Integer;
  Colors: TAtlasColors;
begin
  HoverView := View('');
  HoverView.Problems := [Finding(TAtlasProblemSeverity.Hint, 'Atlas', 'magic-number', 'Zahl', ''),
    Finding(TAtlasProblemSeverity.Warning, 'dcc', 'W1036', 'Variable', ''),
    Finding(TAtlasProblemSeverity.Error, 'Atlas', 'use-after-free', 'Freigegeben', '')];
  Order := TAtlasHoverLayout.ProblemOrder(HoverView.Problems);
  Assert.AreEqual(3, Integer(Length(Order)));
  Assert.AreEqual(2, Order[0]);
  Assert.AreEqual(0, Order[1]);
  Assert.AreEqual(1, Order[2]);
  HoverInput := Input(HoverView, 300);
  HoverInput.Texts.KindError := 'Error';
  HoverInput.Texts.KindWarning := 'Warnung';
  HoverInput.Texts.KindInfo := 'Info';
  Layout := Build(HoverInput);
  // Pillen in der Reihenfolge des Hovers; hint zählt als Info.
  Assert.AreEqual('Error|Info|Warnung|', TextsOf(Layout, TAtlasHoverItemKind.CenterText));
  Assert.AreEqual('Freigegeben|Zahl|Variable|', TextsOf(Layout, TAtlasHoverItemKind.Block));
  Assert.AreEqual('Atlas · use-after-free|Atlas · magic-number|dcc · W1036|',
    TextsOf(Layout, TAtlasHoverItemKind.Text));
  // Pille in der Farbe der Art vor der Meldung, die Meldung rückt hinter sie.
  Colors := TAtlasColors.Light;
  Pill := FirstKind(Layout, TAtlasHoverItemKind.CenterText);
  Assert.AreEqual(Colors.Error, Layout.Items[Pill].Color);
  Assert.AreEqual(20, Layout.Items[Pill].Rect.Left);
  Assert.IsTrue(Layout.Items[FirstKind(Layout, TAtlasHoverItemKind.Block)].Rect.Left >=
    Layout.Items[Pill].Rect.Right + 6);
  // Ohne Aktionszeile keine Klickflächen.
  Assert.AreEqual('', ActionCodes(Layout));
  Assert.AreEqual(-1, Layout.FixProblem);
end;

procedure THoverLayoutTests.ConfirmedFindingShowsBothSources;
var
  HoverView: TAtlasHoverView;
  HoverInput: TAtlasHoverInput;
  Layout: TAtlasHoverLayout;
  Problem: TAtlasProblem;
begin
  Problem := Finding(TAtlasProblemSeverity.Error, 'Atlas', 'argument-count-mismatch',
    'Suchen erwartet 1 Argumente (wie E2035).', '');
  Problem.Confirmed := True;
  Problem.ConfirmedCode := 'E2035';
  HoverView := View('');
  HoverView.Problems := [Problem];
  HoverInput := Input(HoverView, 460);
  HoverInput.Texts.Confirmed := 'vom Compiler bestätigt';
  HoverInput.Texts.ConfirmedCode := 'vom Compiler bestätigt (%s)';
  Layout := Build(HoverInput);
  Assert.AreEqual('Suchen erwartet 1 Argumente (wie E2035).|', TextsOf(Layout, TAtlasHoverItemKind.Block));
  Assert.AreEqual('Atlas + dcc · argument-count-mismatch · vom Compiler bestätigt (E2035)|',
    TextsOf(Layout, TAtlasHoverItemKind.Text));
  HoverInput.HideCompilerCode := True;
  Layout := Build(HoverInput);
  Assert.AreEqual('Suchen erwartet 1 Argumente.|', TextsOf(Layout, TAtlasHoverItemKind.Block));
  Assert.AreEqual('Atlas + dcc · argument-count-mismatch · vom Compiler bestätigt|',
    TextsOf(Layout, TAtlasHoverItemKind.Text));
end;

procedure THoverLayoutTests.RuleFindingsOfferActions;
var
  HoverView: TAtlasHoverView;
  HoverInput: TAtlasHoverInput;
  Layout: TAtlasHoverLayout;
begin
  HoverView := View('');
  HoverView.Problems := [Finding(TAtlasProblemSeverity.Warning, 'Atlas', 'empty-routine', 'Leer', ''),
    Finding(TAtlasProblemSeverity.Error, 'dcc', 'E2003', 'Unbekannt', ''),
    Finding(TAtlasProblemSeverity.Error, 'Atlas', '', 'Syntax', ''),
    Finding(TAtlasProblemSeverity.Error, 'Atlas', 'loop-off-by-one', 'Zu weit', 'Count - 1 verwenden')];
  HoverInput := Input(HoverView, 460);
  HoverInput.Texts.Suppress := 'Unterdrücken';
  HoverInput.Texts.Configure := 'Einstellen';
  HoverInput.ProblemActions := True;
  Layout := Build(HoverInput);
  // Fehler zuerst: Problem 3 mit Korrektur (Fix = 3), unterdrücken (4) und einstellen (5); dcc und
  // Syntaxfehler ohne Aktionen; dann die Warnung ohne Korrektur.
  Assert.AreEqual('3:3|3:4|3:5|0:4|0:5|', ActionCodes(Layout));
  Assert.AreEqual(3, Layout.FixProblem);
  Assert.IsTrue(Pos('Alt+Enter: |Count - 1 verwenden|', TextsOf(Layout, TAtlasHoverItemKind.Text)) > 0);
  HoverInput.ProblemActions := False;
  Layout := Build(HoverInput);
  Assert.AreEqual('', ActionCodes(Layout));
  Assert.AreEqual(-1, Layout.FixProblem);
  // Zusatz der Regel als eigene Zeile unter Herkunft und Regel (#1102).
  Assert.AreEqual(0, Pos('Durchsucht', TextsOf(Layout, TAtlasHoverItemKind.Text)));
  HoverView.Problems[0].Details := 'Durchsucht: 3 Dateien der Projektgruppe';
  HoverInput.View := HoverView;
  Layout := Build(HoverInput);
  Assert.IsTrue(Pos('Atlas · empty-routine|Durchsucht: 3 Dateien der Projektgruppe|',
    TextsOf(Layout, TAtlasHoverItemKind.Text)) > 0, TextsOf(Layout, TAtlasHoverItemKind.Text));
end;

procedure THoverLayoutTests.NextProblemHitCycles;
var
  HoverView: TAtlasHoverView;
  HoverInput: TAtlasHoverInput;
  Layout: TAtlasHoverLayout;
  First, Second, Last: Integer;
begin
  HoverView := View('procedure Foo');
  HoverView.Problems := [Finding(TAtlasProblemSeverity.Warning, 'Atlas', 'empty-routine', 'Leer', '')];
  HoverInput := Input(HoverView, 460);
  HoverInput.Texts.Suppress := 'Unterdrücken';
  HoverInput.Texts.Configure := 'Einstellen';
  Layout := Build(HoverInput);
  Assert.AreEqual(-1, Layout.NextProblemHit(-1, True));
  HoverInput.ProblemActions := True;
  Layout := Build(HoverInput);
  First := Layout.NextProblemHit(-1, True);
  Assert.IsTrue(First >= 0);
  Second := Layout.NextProblemHit(First, True);
  Assert.IsTrue(Second > First);
  Assert.IsTrue(Layout.Hits[Second].Kind = TAtlasHoverHitKind.ProblemAction);
  // Reihum: nach der letzten wieder die erste, rückwärts von vorn die letzte.
  Assert.AreEqual(First, Layout.NextProblemHit(Second, True));
  Last := Layout.NextProblemHit(-1, False);
  Assert.AreEqual(Second, Last);
  Assert.AreEqual(First, Layout.NextProblemHit(Last, False));
end;

function Member(const AName, AType, ADeclaring: string; AKind: TAtlasHoverDefaultKind;
  const AValue: string): TAtlasHoverMember;
begin
  Result := Default(TAtlasHoverMember);
  Result.Name := AName;
  Result.TypeName := AType;
  Result.DeclaringClass := ADeclaring;
  Result.DefaultKind := AKind;
  Result.DefaultValue := AValue;
end;

function EventMember(const AName, AType, ADeclaring: string): TAtlasHoverMember;
begin
  Result := Member(AName, AType, ADeclaring, hdNone, '');
  Result.IsEvent := True;
end;

procedure THoverLayoutTests.PublishedMembersAsTables;
var
  HoverView: TAtlasHoverView;
  HoverInput: TAtlasHoverInput;
  Layout: TAtlasHoverLayout;
  Hint: TAtlasHoverMember;

  function Codes: string;
  var
    Hit: TAtlasHoverHit;
  begin
    Result := '';
    for Hit in Layout.Hits do
      if Hit.Kind = TAtlasHoverHitKind.Published then
        Result := Result + IntToStr(Hit.Index);
  end;

  function HasText(const AText: string): Boolean;
  var
    Item: TAtlasHoverItem;
  begin
    for Item in Layout.Items do
      if Item.Text = AText then
        Exit(True);
    Result := False;
  end;

begin
  HoverView := ActionsView;
  HoverView.Data.Location.Name := 'TKnopf';
  Hint := Member('Hint', 'string', 'TControl', hdNone, '');
  Hint.Stored := 'False';
  HoverView.Data.Members := [Member('Cancel', 'Boolean', 'TKnopf', hdImplicit, 'False'),
    Member('Default', 'Boolean', 'TKnopf', hdImplicit, 'False'),
    Member('Cursor', 'TCursor', 'TControl', hdExplicit, 'crDefault'),
    Member('Height', 'Integer', 'TControl', hdNoDefault, ''), Hint,
    Member('Left', 'Integer', 'TControl', hdNone, ''), Member('Top', 'Integer', 'TControl', hdNone, ''),
    Member('Width', 'Integer', 'TControl', hdNone, ''),
    EventMember('OnClick', 'TNotifyEvent', 'TControl'), EventMember('OnEnter', 'TNotifyEvent', 'TWinControl'),
    EventMember('OnKeyDown', 'TKeyEvent', 'TWinControl'), EventMember('OnExit', 'TNotifyEvent', 'TWinControl'),
    EventMember('OnRueckmeldung', 'TMeinRueckruf', 'TKnopf')];
  HoverView.Data.DefaultProperty := 'Controls[Index: Integer]: TControl';
  HoverInput := Input(HoverView, 460);
  HoverInput.Texts.PublishedSummary := 'published: %d Properties · %d Ereignisse';
  HoverInput.Texts.PublishedInherited := 'geerbte';
  HoverInput.Texts.PublishedOnlyDefaults := 'nur mit default';
  HoverInput.Texts.PublishedProperties := 'Properties';
  HoverInput.Texts.PublishedEvents := 'Ereignisse';
  HoverInput.Texts.PublishedName := 'Name';
  HoverInput.Texts.PublishedImplicit := 'implizit';
  HoverInput.Texts.PublishedMoreProperties := '+ %d weitere Properties';
  HoverInput.Texts.PublishedMoreEvents := '+ %d weitere Ereignisse';
  HoverInput.Texts.PublishedArrayProperty := 'Array-Property';
  HoverInput.Texts.PublishedDefaultProperty := 'Standard-Property';
  HoverInput.Texts.PublishedCopyList := 'Liste';
  Layout := Build(HoverInput);
  // Schalter, Abschnitte, „+ 1 weitere Properties“ (8 > 7), „+ 1 weitere Ereignisse“ (5 > 4).
  Assert.AreEqual('012435', Codes);
  Assert.IsTrue(HasText('published: 8 Properties · 5 Ereignisse'));
  Assert.IsTrue(HasText('PROPERTIES ▾'));
  Assert.IsTrue(HasText('implizit'));
  Assert.IsTrue(HasText('crDefault'));
  Assert.IsTrue(HasText('nodefault'));
  Assert.IsTrue(HasText('stored False'));
  Assert.IsTrue(HasText('+ 1 weitere Properties'));
  Assert.IsFalse(HasText('Width'), 'achte Zeile erst nach dem Klick');
  Assert.IsTrue(HasText('Controls[Index: Integer]'));
  Assert.IsTrue(HasText('Standard-Property'));
  Assert.IsTrue(HasText('Liste'), 'Strg+C kopiert die Liste');
  // Ereignis am Methodenzeiger-Typ erkannt: kenntlich, wenn der Typname es nicht verrät.
  Assert.IsFalse(HasText('(of object)'), 'OnRueckmeldung steht erst hinter „+ 1 weitere“');
  HoverView.Toggle(TAtlasHoverPublishedToggle.MoreProperties);
  HoverView.Toggle(TAtlasHoverPublishedToggle.MoreEvents);
  HoverInput.View := HoverView;
  Layout := Build(HoverInput);
  Assert.IsTrue(HasText('Width'));
  Assert.IsTrue(HasText('(of object)'));
  Assert.AreEqual('0123', Codes);
  // Ohne geerbte: nur die zwei eigenen Properties und das eigene Ereignis.
  HoverView.Toggle(TAtlasHoverPublishedToggle.ShowInherited);
  HoverInput.View := HoverView;
  Layout := Build(HoverInput);
  Assert.IsTrue(HasText('Cancel'));
  Assert.IsFalse(HasText('Cursor'));
  Assert.IsFalse(HasText('OnClick'));
  Assert.IsTrue(HasText('OnRueckmeldung'));
  // Zugeklappt: nur der Titel.
  HoverView.Toggle(TAtlasHoverPublishedToggle.ShowInherited);
  HoverView.Toggle(TAtlasHoverPublishedToggle.Properties);
  HoverInput.View := HoverView;
  Layout := Build(HoverInput);
  Assert.IsTrue(HasText('PROPERTIES ▸'));
  Assert.IsFalse(HasText('Cancel'));
  Assert.IsTrue(HasText('OnClick'));
  // Nur mit default: Cancel, Default, Cursor.
  HoverView.Toggle(TAtlasHoverPublishedToggle.Properties);
  HoverView.Toggle(TAtlasHoverPublishedToggle.OnlyDefaults);
  HoverInput.View := HoverView;
  Layout := Build(HoverInput);
  Assert.IsTrue(HasText('Cursor'));
  Assert.IsFalse(HasText('Height'));
  Assert.IsFalse(HasText('Hint'));
  // Ohne Mitglieder kein Abschnitt.
  Layout := Build(ActionsView, 460);
  Assert.AreEqual('', Codes);
end;

initialization
  TDUnitX.RegisterTestFixture(THoverLayoutTests);

end.
