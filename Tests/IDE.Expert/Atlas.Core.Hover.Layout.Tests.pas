unit Atlas.Core.Hover.Layout.Tests;

// Tests für den Satz des Hover-Tooltips ohne VCL. Die erwarteten Zahlen
// sind mit festen Messwerten nachgerechnet; so bleibt das Aussehen
// festgehalten.
// Messwerte: Breite je Zeichen UI 7, Editorschrift 8 (halbfett 9), klein 6;
// Zeilenhöhe UI 15, Editorschrift 16, klein UI 13, klein Editorschrift 12; 96 dpi.

interface

uses
  DUnitX.TestFramework,
  System.Types,
  Atlas.Core.Hover.Items,
  Atlas.Core.Hover.Layout,
  Atlas.Core.Hover.Layout.Contract,
  Atlas.Core.Hover.View,
  Atlas.Core.Hover.Texts,
  Atlas.Core.Hover.Layout.TestSupport;

type
  [TestFixture]
  THoverLayoutTests = class
  private
    /// <summary>Kurze Texte, an denen die Tests die Abschnitte erkennen.</summary>
    function Texts: TAtlasHoverTexts;
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
    procedure ReassignedLineInDescription;
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
    /// <summary>#54: Compilermeldung mit Katalogeintrag zeigt die Ursache und „Erklären“/„DocWiki“.</summary>
    [Test]
    procedure ExplainedMessagesShowCauseAndLinks;
    /// <summary>#1779: Fehlgeschlagener Test mit Werten bekommt „Vergleichen“ vor „Erklären“.</summary>
    [Test]
    procedure FailedTestOffersCompare;
    /// <summary>#909: Tab wandert reihum über die Aktionen unter den Befunden.</summary>
    [Test]
    procedure NextProblemHitCycles;
    /// <summary>#145: „Beispiel zeigen“ in der Aktionszeile klappt Beschreibung und Beispiel über ihr auf.</summary>
    [Test]
    procedure RuleExampleLinkTogglesExample;
    /// <summary>#896: Unit-Zyklus mit anklickbaren Units und „Graph zeigen“.</summary>
    [Test]
    procedure CycleUnitsAreLinks;
  end;

implementation

uses
  Atlas.Core.Hover.Contract,
  Atlas.Core.Hover.History,
  System.SysUtils,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Wrap,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Explanation,
  Atlas.Core.Hover.DebugValue;

{ THoverLayoutTests }

function THoverLayoutTests.View(const ADeclaration: string): TAtlasHoverView;
var
  Data: TAtlasHoverData;
begin
  Data := Default(TAtlasHoverData);
  Data.Declaration := ADeclaration;
  Result := TAtlasHoverView.Create(Data);
end;

function THoverLayoutTests.Texts: TAtlasHoverTexts;
begin
  Result := HoverTestTexts;
end;

function THoverLayoutTests.Input(const AView: TAtlasHoverView; AWidth: Integer): TAtlasHoverInput;
begin
  Result := HoverTestInput(AView, AWidth);
end;

function THoverLayoutTests.Build(const AInput: TAtlasHoverInput): TAtlasHoverLayout;
begin
  Result := BuildLayout(AInput);
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
  begin
    if Item.Kind = AKind then
    begin
      Inc(Result);
    end;
  end;
end;

function THoverLayoutTests.FirstKind(const ALayout: TAtlasHoverLayout; AKind: TAtlasHoverItemKind): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ALayout.Items) do
  begin
    if ALayout.Items[Index].Kind = AKind then
    begin
      Exit(Index);
    end;
  end;
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

procedure THoverLayoutTests.ReassignedLineInDescription;
var
  HoverView: TAtlasHoverView;
  Layout: TAtlasHoverLayout;
  Index: Integer;
begin
  HoverView := View('Summe: Integer');
  HoverView.Data.ReassignedTarget := 'locals';
  HoverView.Data.ReassignedWrites := 2;
  HoverView.Data.ReassignedLines := TArray<Integer>.Create(3, 9);
  Layout := Build(HoverView, 300);
  Index := FirstKind(Layout, TAtlasHoverItemKind.Block);
  Assert.IsTrue(Index >= 0, 'Zeile unter der Linie');
  Assert.AreEqual('2 mal 4, 10', Layout.Items[Index].Text);
  Assert.AreEqual(TAtlasColors.Light.Muted, Layout.Items[Index].Color);
  // Ausgeblendet (Art nicht gewaehlt): keine Beschreibung.
  HoverView.Data.ClearReassigned;
  Layout := Build(HoverView, 300);
  Assert.AreEqual(-1, FirstKind(Layout, TAtlasHoverItemKind.Block));
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
  begin
    Assert.IsFalse(Item.Text = 'Count', 'kein Abschnitt für den Wert');
  end;
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
  begin
    if Hit.Kind = TAtlasHoverHitKind.DebugFix then
    begin
      Assert.AreEqual(Fixes, Hit.Index, 'Index in Note.Fixes');
      Inc(Fixes);
    end;
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
  begin
    Assert.IsFalse(Hit.Kind = TAtlasHoverHitKind.DebugFix, 'ohne Korrekturen keine Klickfläche');
  end;
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
  begin
    if Layout.Items[Index].Text = 'pinned' then
    begin
      Found := True;
      Assert.AreEqual(253, Layout.Items[Index].Rect.Left);
      Assert.AreEqual(8, Layout.Items[Index].Rect.Top);
    end;
  end;
  Assert.IsTrue(Found);
  Assert.AreEqual(38, Layout.Items[FirstKind(Layout, TAtlasHoverItemKind.Styled)].Rect.Top);
  Assert.AreEqual(62, Layout.Height);
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
  begin
    if Layout.Items[Index].Text = 'U.pas : 5' then
    begin
      Found := True;
      Assert.AreEqual(235, Layout.Items[Index].Rect.Left);
      Assert.AreEqual(10, Layout.Items[Index].Rect.Top);
    end;
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
    begin
      if Hit.Kind = TAtlasHoverHitKind.ProblemAction then
      begin
        TAtlasHoverProblemActionCode.Decode(Hit.Index, Problem, Action);
        Result := Result + IntToStr(Problem) + ':' + IntToStr(Ord(Action)) + '|';
      end;
    end;
  end;

var
  HoverView: TAtlasHoverView;
  Plain, Unused, Moved: TAtlasProblem;
  HoverInput: TAtlasHoverInput;
  Problem: Integer;
  Action: TAtlasHoverProblemAction;
begin
  TAtlasHoverProblemActionCode.Decode(TAtlasHoverProblemActionCode.Encode(3,
    TAtlasHoverProblemAction.MoveUses), Problem, Action);
  Assert.AreEqual(3, Problem);
  Assert.IsTrue(Action = TAtlasHoverProblemAction.MoveUses);
  Plain := Default(TAtlasProblem);
  Plain.Message := 'x';
  Unused := Plain;
  Unused.Severity := TAtlasProblemSeverity.Hint;
  Unused.UsesUnit := 'Vcl.Grids';
  Unused.UsesState := TAtlasProblem.cUsesUnused;
  Unused.UsesUnusedCount := 1;
  Moved := Unused;
  Moved.UsesState := TAtlasProblem.cUsesImplementation;
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

procedure THoverLayoutTests.CycleUnitsAreLinks;

  function Related(const AMessage: string; ALine: Integer): TAtlasProblemRelated;
  begin
    Result.Uri := 'file:///c%3A/p/' + AMessage + '.pas';
    Result.Line := ALine;
    Result.Character := 2;
    Result.Message := AMessage;
  end;

  function Codes(const ALayout: TAtlasHoverLayout): string;
  var
    Hit: TAtlasHoverHit;
    Problem, Item: Integer;
    Action: TAtlasHoverProblemAction;
  begin
    Result := '';
    for Hit in ALayout.Hits do
    begin
      if Hit.Kind = TAtlasHoverHitKind.ProblemAction then
      begin
        TAtlasHoverProblemActionCode.Decode(Hit.Index, Problem, Action, Item);
        if Action in [TAtlasHoverProblemAction.Related, TAtlasHoverProblemAction.ShowGraph] then
        begin
          Result := Result + IntToStr(Problem) + ':' + IntToStr(Ord(Action)) + ':' + IntToStr(Item) + '|';
        end;
      end;
    end;
  end;

var
  HoverView: TAtlasHoverView;
  Cycle, Plain: TAtlasProblem;
  HoverInput: TAtlasHoverInput;
  Layout: TAtlasHoverLayout;
  Item: TAtlasHoverItem;
  Texts, Problem, Index: Integer;
  Action: TAtlasHoverProblemAction;
begin
  TAtlasHoverProblemActionCode.Decode(TAtlasHoverProblemActionCode.Encode(2, TAtlasHoverProblemAction.Related, 3),
    Problem, Action, Index);
  Assert.AreEqual(2, Problem);
  Assert.AreEqual(3, Index);
  Assert.IsTrue(Action = TAtlasHoverProblemAction.Related);
  Plain := Default(TAtlasProblem);
  Plain.Message := 'x';
  Cycle := Default(TAtlasProblem);
  Cycle.Severity := TAtlasProblemSeverity.Error;
  Cycle.Source := 'Atlas';
  Cycle.Code := TAtlasProblem.cUsesCycleCode;
  Cycle.Message := 'Zirkuläre Unit-Referenz';
  Cycle.Related := [Related('uC', 3), Related('uA', 3), Related('uB', 3), Related('uC', 3)];
  HoverView := View('');
  HoverView.Problems := [Plain, Cycle];
  HoverInput := Input(HoverView, 600);
  HoverInput.Texts.ShowGraph := 'Graph zeigen';
  Layout := Build(HoverInput);
  // Jede Unit des Pfads ist ein Link mit ihrer Stelle, dahinter „Graph zeigen“.
  Assert.AreEqual('1:6:0|1:6:1|1:6:2|1:6:3|1:7:0|', Codes(Layout));
  Texts := 0;
  for Item in Layout.Items do
  begin
    if (Item.Kind = TAtlasHoverItemKind.Text) and (Item.Text = ' → ') then
    begin
      Inc(Texts);
    end;
  end;
  Assert.AreEqual(3, Texts, 'Pfeile zwischen den Units');
  // Ohne Text kein „Graph zeigen“; andere Regeln ohne Stellen haben keine solche Zeile.
  HoverInput.Texts.ShowGraph := '';
  Assert.AreEqual('1:6:0|1:6:1|1:6:2|1:6:3|', Codes(Build(HoverInput)));
  Cycle.Code := 'empty-except';
  Cycle.Related := nil;
  HoverView.Problems := [Plain, Cycle];
  HoverInput.View := HoverView;
  Assert.AreEqual('', Codes(Build(HoverInput)));
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
  begin
    if Hit.Kind = TAtlasHoverHitKind.ProblemAction then
    begin
      TAtlasHoverProblemActionCode.Decode(Hit.Index, Problem, Action);
      Result := Result + IntToStr(Problem) + ':' + IntToStr(Ord(Action)) + '|';
    end;
  end;
end;

function TextsOf(const ALayout: TAtlasHoverLayout; AKind: TAtlasHoverItemKind): string;
var
  Item: TAtlasHoverItem;
begin
  Result := '';
  for Item in ALayout.Items do
  begin
    if Item.Kind = AKind then
    begin
      Result := Result + Item.Text + '|';
    end;
  end;
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
  Order := HoverView.ProblemOrder;
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
  // Gemessen und gezeichnet mit derselben Schrift fester Größe; die Badge-Schrift hängt an der Kästchenhöhe.
  Assert.IsTrue(Layout.Items[Pill].Face.Font = TAtlasHoverFont.SmallUi, 'Schrift der Pille');
  Assert.AreEqual(15, Layout.Items[Pill].Rect.Height, 'eine Zeile kleine Schrift plus Rand');
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

procedure THoverLayoutTests.ExplainedMessagesShowCauseAndLinks;
var
  HoverView: TAtlasHoverView;
  HoverInput: TAtlasHoverInput;
  Layout: TAtlasHoverLayout;
  Explanations: TArray<TAtlasHoverExplanation>;
begin
  HoverView := View('');
  HoverView.Problems := [Finding(TAtlasProblemSeverity.Error, 'dcc', 'E2003', 'Unbekannt', ''),
    Finding(TAtlasProblemSeverity.Warning, 'Atlas', 'empty-routine', 'Leer', '')];
  HoverInput := Input(HoverView, 460);
  HoverInput.Texts.Suppress := 'Unterdrücken';
  HoverInput.Texts.Configure := 'Einstellen';
  HoverInput.Texts.Explain := 'Erklären';
  HoverInput.Texts.DocWiki := 'DocWiki';
  HoverInput.Texts.Cause := 'Typische Ursache: %s';
  HoverInput.ProblemActions := True;
  // Ohne Erklärungen (hover.explainMessages aus): keine Ursache, keine Links an der Meldung.
  Layout := Build(HoverInput);
  Assert.AreEqual('1:4|1:5|', ActionCodes(Layout));
  SetLength(Explanations, 2);
  Explanations[0] := Default(TAtlasHoverExplanation);
  Explanations[0].Known := True;
  Explanations[0].Cause := 'Unit fehlt in uses';
  Explanations[0].DocWiki := 'https://docwiki.embarcadero.com/RADStudio/Athens/e/index.php?search=E2003';
  Explanations[1] := Default(TAtlasHoverExplanation);
  Explanations[1].Known := True;
  HoverView.Explanations := Explanations;
  HoverInput.View := HoverView;
  Layout := Build(HoverInput);
  // Meldung: Erklären (8) und DocWiki (9); Regel: unterdrücken, einstellen, erklären.
  Assert.AreEqual('0:8|0:9|1:4|1:5|1:8|', ActionCodes(Layout));
  // Die Ursache ist ein umbrochener Absatz (Block), keine einzelne Textzeile.
  Assert.IsTrue(Pos('Typische Ursache: Unit fehlt in uses|', TextsOf(Layout, TAtlasHoverItemKind.Block)) > 0,
    TextsOf(Layout, TAtlasHoverItemKind.Block));
end;

procedure THoverLayoutTests.FailedTestOffersCompare;
var
  HoverView: TAtlasHoverView;
  HoverInput: TAtlasHoverInput;
  Layout: TAtlasHoverLayout;
  Explanations: TArray<TAtlasHoverExplanation>;
begin
  HoverView := View('');
  HoverView.Problems := [Finding(TAtlasProblemSeverity.Error, 'DUnitX', '', 'Expected 3 but got 0', '')];
  HoverInput := Input(HoverView, 460);
  HoverInput.Texts.Explain := 'Erklären';
  HoverInput.Texts.Compare := 'Vergleichen';
  HoverInput.ProblemActions := True;
  // Ohne Werte (kein Modul Tests, tests.compare aus): keine Links.
  Layout := Build(HoverInput);
  Assert.AreEqual('', ActionCodes(Layout));
  HoverView.Comparisons := [True];
  HoverInput.View := HoverView;
  Layout := Build(HoverInput);
  // Compare ist die Aktion 11.
  Assert.AreEqual('0:11|', ActionCodes(Layout));
  Assert.IsTrue(Pos('Vergleichen', TextsOf(Layout, TAtlasHoverItemKind.Text)) > 0,
    TextsOf(Layout, TAtlasHoverItemKind.Text));
  SetLength(Explanations, 1);
  Explanations[0] := Default(TAtlasHoverExplanation);
  Explanations[0].Known := True;
  HoverView.Explanations := Explanations;
  HoverInput.View := HoverView;
  Layout := Build(HoverInput);
  Assert.AreEqual('0:11|0:8|', ActionCodes(Layout));
  // Mehr Werte als Probleme oder ein negativer Index zählen nicht.
  Assert.IsFalse(HoverView.CanCompare(1));
  Assert.IsFalse(HoverView.CanCompare(-1));
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

function FirstProblemHit(const ALayout: TAtlasHoverLayout): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to High(ALayout.Hits) do
  begin
    if ALayout.Hits[Index].Kind = TAtlasHoverHitKind.ProblemAction then
    begin
      Exit(Index);
    end;
  end;
end;

procedure THoverLayoutTests.RuleExampleLinkTogglesExample;
var
  HoverView: TAtlasHoverView;
  HoverInput: TAtlasHoverInput;
  Closed, Opened: TAtlasHoverLayout;
  Example: TAtlasRuleExplanation;
  FillCount: Integer;
begin
  HoverView := View('');
  HoverView.Problems := [Finding(TAtlasProblemSeverity.Warning, 'Atlas', 'empty-except', 'Leer', '')];
  HoverInput := Input(HoverView, 460);
  HoverInput.Texts.Suppress := 'Unterdrücken';
  HoverInput.Texts.Configure := 'Einstellen';
  HoverInput.Texts.ShowExample := 'Zeigen';
  HoverInput.Texts.HideExample := 'Ausblenden';
  HoverInput.Texts.ExampleBad := 'Falsch:';
  HoverInput.Texts.ExampleGood := 'Richtig:';

  HoverInput.ProblemActions := True;
  // Ohne hover.ruleExamples wie bisher: unterdrücken (4) und einstellen (5).
  Assert.AreEqual('0:4|0:5|', ActionCodes(Build(HoverInput)));
  HoverInput.RuleExamples := True;
  Closed := Build(HoverInput);
  Assert.AreEqual('0:4|0:5|0:10|', ActionCodes(Closed));
  Assert.IsTrue(Pos('|Zeigen|', TextsOf(Closed, TAtlasHoverItemKind.Text)) > 0, TextsOf(Closed,
    TAtlasHoverItemKind.Text));
  Assert.AreEqual(0, Pos('Falsch:', TextsOf(Closed, TAtlasHoverItemKind.Text)));
  // Aufgeklappt: Beschreibung, falsch und richtig über der Aktionszeile, der Link heißt „Ausblenden“.
  Example := Default(TAtlasRuleExplanation);
  Example.Id := 'empty-except';
  Example.Description := 'Verschluckt jede Ausnahme.';
  Example.Bad := 'try' + #10 + '  Save;' + #10 + 'except' + #10 + 'end;' + #10;
  Example.Good := 'Log(E.Message);';
  HoverView.Examples := [Example];
  HoverInput.View := HoverView;
  Opened := Build(HoverInput);
  Assert.AreEqual('0:4|0:5|0:10|', ActionCodes(Opened));
  Assert.IsTrue(Pos('Falsch:|try|  Save;|except|end;|Richtig:|Log(E.Message);|Unterdrücken|Einstellen|Ausblenden|',
    TextsOf(Opened, TAtlasHoverItemKind.Text)) > 0, TextsOf(Opened, TAtlasHoverItemKind.Text));
  Assert.IsTrue(Pos('Verschluckt jede Ausnahme.', TextsOf(Opened, TAtlasHoverItemKind.Block)) > 0);
  // Je Beispiel eine Fläche und ein Randstrich.
  FillCount := CountKind(Opened, TAtlasHoverItemKind.Fill) - CountKind(Closed, TAtlasHoverItemKind.Fill);
  Assert.AreEqual(4, FillCount);
  Assert.IsTrue(Opened.Height > Closed.Height);
  Assert.IsTrue(Opened.Hits[FirstProblemHit(Opened)].Rect.Top > Closed.Hits[FirstProblemHit(Closed)].Rect.Top);
  // Tab-Markierung bleibt beim Aufklappen auf derselben Klickfläche.
  Assert.AreEqual(FirstProblemHit(Closed), FirstProblemHit(Opened));
  // Ohne Aktionszeile kein Beispiel.
  HoverInput.ProblemActions := False;
  Assert.AreEqual(0, Pos('Verschluckt', TextsOf(Build(HoverInput), TAtlasHoverItemKind.Block)));
end;

initialization
  TDUnitX.RegisterTestFixture(THoverLayoutTests);

end.
