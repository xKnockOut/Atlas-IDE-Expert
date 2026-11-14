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
  Atlas.Core.Hover.Texts;

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
    /// <summary>#526: Aktionen unter dem Wert als Links mit Klickfläche DebugAction.</summary>
    [Test]
    procedure DebugValueActionsAreLinks;
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
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Explanation,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Hover.Layout.TestSupport;

{ THoverLayoutTests }

function THoverLayoutTests.View(const ADeclaration: string): TAtlasHoverView;
var
  mData: TAtlasHoverData;
begin
  mData := Default(TAtlasHoverData);
  mData.Declaration := ADeclaration;
  Result := TAtlasHoverView.Create(mData);
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
  mItem: TAtlasHoverItem;
begin
  Result := 0;
  for mItem in ALayout.Items do
  begin
    if mItem.Kind = AKind then
    begin
      Inc(Result);
    end;
  end;
end;

function THoverLayoutTests.FirstKind(const ALayout: TAtlasHoverLayout; AKind: TAtlasHoverItemKind): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ALayout.Items) do
  begin
    if ALayout.Items[mIndex].Kind = AKind then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure THoverLayoutTests.DeclarationOnlyHasOneTextLine;
var
  mLayout: TAtlasHoverLayout;
begin
  mLayout := Build(View('x: Integer'), 300);
  Assert.AreEqual(1, Integer(Length(mLayout.Items)));
  Assert.AreEqual(0, Integer(Length(mLayout.Hits)));
  Assert.AreEqual<TAtlasHoverItemKind>(TAtlasHoverItemKind.Styled, mLayout.Items[0].Kind);
  CheckRect(Rect(11, 8, 289, 26), mLayout.Items[0].Rect, 'Deklaration');
  Assert.AreEqual(0, mLayout.Items[0].From);
  Assert.AreEqual(10, mLayout.Items[0].Till);
  Assert.AreEqual(32, mLayout.Height);
end;

procedure THoverLayoutTests.LongDeclarationWrapsWithIndent;
var
  mLayout: TAtlasHoverLayout;
begin
  mLayout := Build(View('procedure Foo(A: Integer; B: string)'), 200);
  Assert.AreEqual(2, CountKind(mLayout, TAtlasHoverItemKind.Styled));
  CheckRect(Rect(11, 8, 189, 26), mLayout.Items[0].Rect, 'Zeile 1');
  Assert.AreEqual(17, mLayout.Items[0].Till);
  CheckRect(Rect(27, 26, 189, 44), mLayout.Items[1].Rect, 'Zeile 2 eingerückt');
  Assert.AreEqual(17, mLayout.Items[1].From);
  Assert.AreEqual(36, mLayout.Items[1].Till);
  Assert.AreEqual(50, mLayout.Height);
end;

procedure THoverLayoutTests.ProblemsProduceBlockAndBar;
var
  mHoverView: TAtlasHoverView;
  mProblem: TAtlasProblem;
  mLayout: TAtlasHoverLayout;
  mBar: Integer;
  mColors: TAtlasColors;
begin
  mHoverView := View('');
  mProblem := Default(TAtlasProblem);
  mProblem.Message := 'x';
  mProblem.Severity := TAtlasProblemSeverity.Error;
  mHoverView.Problems := [mProblem];
  mLayout := Build(mHoverView, 300);
  Assert.AreEqual<TAtlasHoverItemKind>(TAtlasHoverItemKind.Block, mLayout.Items[0].Kind);
  CheckRect(Rect(20, 8, 289, 23), mLayout.Items[0].Rect, 'Meldung');
  Assert.AreEqual<TAtlasHoverItemKind>(TAtlasHoverItemKind.Text, mLayout.Items[1].Kind);
  Assert.AreEqual('Atlas', mLayout.Items[1].Text);
  Assert.AreEqual(20, mLayout.Items[1].Rect.Left);
  Assert.AreEqual(25, mLayout.Items[1].Rect.Top);
  mBar := FirstKind(mLayout, TAtlasHoverItemKind.RoundFill);
  Assert.IsTrue(mBar >= 0);
  CheckRect(Rect(11, 9, 14, 37), mLayout.Items[mBar].Rect, 'Farbbalken');
  mColors := TAtlasColors.Light;
  Assert.AreEqual(mColors.Error, mLayout.Items[mBar].Color);
  // Ohne Deklaration endet der Tooltip nach den Problemen.
  Assert.AreEqual(46, mLayout.Height);
end;

procedure THoverLayoutTests.DebugValueProducesExpressionValueAndBar;
var
  mHoverView: TAtlasHoverView;
  mLayout: TAtlasHoverLayout;
  mBar: Integer;
  mColors: TAtlasColors;
begin
  // #891: Ausdruck in der Editorschrift (halbfett, Akzent), darunter der Wert, links ein Akzentbalken.
  mHoverView := View('');
  mHoverView.DebugValue := TAtlasDebugValue.Evaluated('Count', '3');
  mLayout := Build(mHoverView, 300);
  mColors := TAtlasColors.Light;
  Assert.AreEqual<TAtlasHoverItemKind>(TAtlasHoverItemKind.Text, mLayout.Items[0].Kind);
  Assert.AreEqual('Count', mLayout.Items[0].Text);
  Assert.AreEqual<TAtlasHoverFont>(TAtlasHoverFont.Mono, mLayout.Items[0].Face.Font);
  Assert.IsTrue(mLayout.Items[0].Face.Bold);
  Assert.AreEqual(mColors.Accent, mLayout.Items[0].Color);
  Assert.AreEqual(20, mLayout.Items[0].Rect.Left);
  Assert.AreEqual(8, mLayout.Items[0].Rect.Top);
  Assert.AreEqual<TAtlasHoverItemKind>(TAtlasHoverItemKind.Block, mLayout.Items[1].Kind);
  Assert.AreEqual('3', mLayout.Items[1].Text);
  Assert.AreEqual(mColors.Text, mLayout.Items[1].Color);
  CheckRect(Rect(20, 27, 289, 42), mLayout.Items[1].Rect, 'Wert');
  mBar := FirstKind(mLayout, TAtlasHoverItemKind.RoundFill);
  Assert.IsTrue(mBar >= 0);
  CheckRect(Rect(11, 9, 14, 41), mLayout.Items[mBar].Rect, 'Akzentbalken');
  Assert.AreEqual(mColors.Accent, mLayout.Items[mBar].Color);
  // Ohne Deklaration und Probleme endet der Tooltip nach dem Wert.
  Assert.AreEqual(50, mLayout.Height);
end;

procedure THoverLayoutTests.ReassignedLineInDescription;
var
  mHoverView: TAtlasHoverView;
  mLayout: TAtlasHoverLayout;
  mIndex: Integer;
begin
  mHoverView := View('Summe: Integer');
  mHoverView.Data.ReassignedTarget := 'locals';
  mHoverView.Data.ReassignedWrites := 2;
  mHoverView.Data.ReassignedLines := TArray<Integer>.Create(3, 9);
  mLayout := Build(mHoverView, 300);
  mIndex := FirstKind(mLayout, TAtlasHoverItemKind.Block);
  Assert.IsTrue(mIndex >= 0, 'Zeile unter der Linie');
  Assert.AreEqual('2 mal 4, 10', mLayout.Items[mIndex].Text);
  Assert.AreEqual(TAtlasColors.Light.Muted, mLayout.Items[mIndex].Color);
  // Ausgeblendet (Art nicht gewaehlt): keine Beschreibung.
  mHoverView.Data.ClearReassigned;
  mLayout := Build(mHoverView, 300);
  Assert.AreEqual(-1, FirstKind(mLayout, TAtlasHoverItemKind.Block));
end;

procedure THoverLayoutTests.DebugValuePendingShowsPlaceholder;
var
  mHoverView: TAtlasHoverView;
  mLayout: TAtlasHoverLayout;
  mColors: TAtlasColors;
begin
  mHoverView := View('');
  mHoverView.DebugValue := TAtlasDebugValue.Pending('FList.Count');
  mLayout := Build(mHoverView, 300);
  mColors := TAtlasColors.Light;
  Assert.AreEqual('FList.Count', mLayout.Items[0].Text);
  Assert.AreEqual<TAtlasHoverItemKind>(TAtlasHoverItemKind.Block, mLayout.Items[1].Kind);
  Assert.AreEqual('eval', mLayout.Items[1].Text);
  Assert.AreEqual(mColors.Muted, mLayout.Items[1].Color);
end;

procedure THoverLayoutTests.DebugValueAboveDeclaration;
var
  mHoverView: TAtlasHoverView;
  mLayout: TAtlasHoverLayout;
  mLine, mStyled: Integer;
begin
  mHoverView := View('var Count: Integer');
  mHoverView.DebugValue := TAtlasDebugValue.Evaluated('Count', '3');
  mLayout := Build(mHoverView, 300);
  // Trennlinie unter dem Wert, danach die Deklaration.
  mLine := FirstKind(mLayout, TAtlasHoverItemKind.Line);
  Assert.IsTrue(mLine >= 0);
  Assert.AreEqual(48, mLayout.Items[mLine].Rect.Top);
  mStyled := FirstKind(mLayout, TAtlasHoverItemKind.Styled);
  Assert.IsTrue(mStyled > mLine);
  Assert.IsTrue(mLayout.Items[mStyled].Rect.Top >= 56);
end;

procedure THoverLayoutTests.FailedDebugValueIsHidden;
var
  mHoverView: TAtlasHoverView;
  mLayout: TAtlasHoverLayout;
  mItem: TAtlasHoverItem;
begin
  // Fehler der Auswertung ohne Erklärung zeigt der Tooltip nicht (#840 erklärt nur „kein Zugriff“).
  mHoverView := View('var Count: Integer');
  mHoverView.DebugValue := TAtlasDebugValue.Failed('Count', 'E2003 Undeclared identifier');
  mLayout := Build(mHoverView, 300);
  for mItem in mLayout.Items do
  begin
    Assert.AreNotEqual('Count', mItem.Text, 'kein Abschnitt für den Wert');
  end;
  Assert.AreEqual(Integer(0), CountKind(mLayout, TAtlasHoverItemKind.RoundFill));
end;

function Unavailable(const AReason: string): TAtlasDebugValue;
begin
  Result := TAtlasDebugValue.Failed('Summe', 'Inaccessible value');
  Result.Note.Caption := 'kein Zugriff';
  Result.Note.Reason := AReason;
end;

procedure THoverLayoutTests.UnavailableValueShowsCauseAndFixes;
var
  mHoverView: TAtlasHoverView;
  mLayout: TAtlasHoverLayout;
  mColors: TAtlasColors;
  mHit: TAtlasHoverHit;
  mFixes: Integer;
begin
  // „kein Zugriff“ (#840): Kennzeichen in der Warnfarbe, Ursache, Herkunft, Korrekturen als Klickflächen.
  mHoverView := View('');
  mHoverView.DebugValue := Unavailable('O+');
  mHoverView.DebugValue.Note.Origin := '{$O+} in Kunden.pas, Zeile 12';
  mHoverView.DebugValue.Note.Fixes := [TAtlasDebugValueFix.Create(1, 'Routine'), TAtlasDebugValueFix.Create(2,
    'Unit')];
  mLayout := Build(mHoverView, 300);
  mColors := TAtlasColors.Light;
  Assert.AreEqual('Summe', mLayout.Items[0].Text);
  Assert.AreEqual('kein Zugriff', mLayout.Items[1].Text);
  Assert.AreEqual(mColors.Warn, mLayout.Items[1].Color);
  Assert.AreEqual('O+', mLayout.Items[2].Text);
  Assert.AreEqual('{$O+} in Kunden.pas, Zeile 12', mLayout.Items[3].Text);
  Assert.AreEqual(mColors.Muted, mLayout.Items[3].Color);
  mFixes := 0;
  for mHit in mLayout.Hits do
  begin
    if mHit.Kind = TAtlasHoverHitKind.DebugFix then
    begin
      Assert.AreEqual(mFixes, mHit.Index, 'Index in Note.Fixes');
      Inc(mFixes);
    end;
  end;
  Assert.AreEqual(2, mFixes);
end;

procedure THoverLayoutTests.DebugValueActionsAreLinks;
var
  mHoverView: TAtlasHoverView;
  mLayout: TAtlasHoverLayout;
  mHit: TAtlasHoverHit;
  mActions: Integer;
  mFound: Boolean;
  mItem: TAtlasHoverItem;
begin
  mHoverView := View('');
  mHoverView.DebugValue := TAtlasDebugValue.Evaluated('Summe', '42');
  mHoverView.DebugValue.Actions := [TAtlasDebugValueFix.Create(7, 'Anheften')];
  mLayout := Build(mHoverView, 300);
  mActions := 0;
  for mHit in mLayout.Hits do
  begin
    if mHit.Kind = TAtlasHoverHitKind.DebugAction then
    begin
      Assert.AreEqual(0, mHit.Index, 'Index in DebugValue.Actions');
      Inc(mActions);
    end;
  end;
  Assert.AreEqual(1, mActions);
  mFound := False;
  for mItem in mLayout.Items do
  begin
    mFound := mFound or (mItem.Text = 'Anheften');
  end;
  Assert.IsTrue(mFound, 'Beschriftung der Aktion');
  // Ohne Aktionen keine Klickfläche.
  mHoverView.DebugValue.Actions := nil;
  mLayout := Build(mHoverView, 300);
  for mHit in mLayout.Hits do
  begin
    Assert.AreNotEqual<TAtlasHoverHitKind>(TAtlasHoverHitKind.DebugAction, mHit.Kind);
  end;
end;

procedure THoverLayoutTests.UnavailableValuePendingAndChecked;
var
  mHoverView: TAtlasHoverView;
  mLayout: TAtlasHoverLayout;
  mHit: TAtlasHoverHit;
begin
  mHoverView := View('');
  mHoverView.DebugValue := Unavailable('');
  mHoverView.DebugValue.Note.Pending := True;
  mLayout := Build(mHoverView, 300);
  Assert.AreEqual('kein Zugriff', mLayout.Items[1].Text);
  Assert.AreEqual('sucht', mLayout.Items[2].Text, 'solange der Server antwortet');
  mHoverView.DebugValue := Unavailable('unbekannt');
  mHoverView.DebugValue.Note.Checked := ['Start', 'Schalter'];
  mLayout := Build(mHoverView, 300);
  Assert.AreEqual('unbekannt', mLayout.Items[2].Text);
  Assert.AreEqual('geprüft', mLayout.Items[3].Text);
  Assert.AreEqual('• Start', mLayout.Items[4].Text);
  Assert.AreEqual('• Schalter', mLayout.Items[5].Text);
  for mHit in mLayout.Hits do
  begin
    Assert.AreNotEqual<TAtlasHoverHitKind>(TAtlasHoverHitKind.DebugFix, mHit.Kind, 'ohne Korrekturen keine Klickfläche');
  end;
end;

procedure THoverLayoutTests.PathChipsProduceHits;
var
  mHoverView: TAtlasHoverView;
  mFirst, mSecond: TAtlasHoverPathItem;
  mLayout: TAtlasHoverLayout;
  mIndex: Integer;
  mFound: Boolean;
begin
  mHoverView := View('x');
  mHoverView.Pinned := True;
  mHoverView.CanGoBack := True;
  mFirst.Index := 0;
  mFirst.Caption := 'TA';
  mSecond.Index := -1;
  mSecond.Caption := 'TB';
  mHoverView.Path := [mFirst, mSecond];
  mLayout := Build(mHoverView, 300);
  Assert.AreEqual(2, Integer(Length(mLayout.Hits)));
  Assert.AreEqual<TAtlasHoverHitKind>(TAtlasHoverHitKind.Back, mLayout.Hits[0].Kind);
  CheckRect(Rect(8, 5, 30, 25), mLayout.Hits[0].Rect, 'Zurück');
  Assert.AreEqual<TAtlasHoverHitKind>(TAtlasHoverHitKind.Path, mLayout.Hits[1].Kind);
  Assert.AreEqual(0, mLayout.Hits[1].Index);
  CheckRect(Rect(36, 7, 52, 23), mLayout.Hits[1].Rect, 'Pfad TA');
  // „angeheftet“ rechtsbündig, weil Platz ist.
  mFound := False;
  for mIndex := 0 to High(mLayout.Items) do
  begin
    if mLayout.Items[mIndex].Text = 'pinned' then
    begin
      mFound := True;
      Assert.AreEqual(253, mLayout.Items[mIndex].Rect.Left);
      Assert.AreEqual(8, mLayout.Items[mIndex].Rect.Top);
    end;
  end;
  Assert.IsTrue(mFound);
  Assert.AreEqual(38, mLayout.Items[FirstKind(mLayout, TAtlasHoverItemKind.Styled)].Rect.Top);
  Assert.AreEqual(62, mLayout.Height);
end;

procedure THoverLayoutTests.PinnedShowsActions;
var
  mLayout: TAtlasHoverLayout;
  mIndex: Integer;
  mFound: Boolean;
begin
  mLayout := Build(ActionsView, 300);
  // Hilfe ohne DocWiki: keine Klickfläche.
  Assert.AreEqual(3, Integer(Length(mLayout.Hits)));
  for mIndex := 0 to 2 do
  begin
    Assert.AreEqual<TAtlasHoverHitKind>(TAtlasHoverHitKind.Action, mLayout.Hits[mIndex].Kind);
    Assert.AreEqual(mIndex, mLayout.Hits[mIndex].Index);
  end;
  CheckRect(Rect(11, 60, 47, 73), mLayout.Hits[0].Rect, 'Gehe zu');
  CheckRect(Rect(61, 60, 85, 73), mLayout.Hits[1].Rect, 'Verwendungen');
  CheckRect(Rect(99, 60, 123, 73), mLayout.Hits[2].Rect, 'Kopieren');
  // Fundort rechtsbündig in der Kopfzeile.
  mFound := False;
  for mIndex := 0 to High(mLayout.Items) do
  begin
    if mLayout.Items[mIndex].Text = 'U.pas : 5' then
    begin
      mFound := True;
      Assert.AreEqual(235, mLayout.Items[mIndex].Rect.Left);
      Assert.AreEqual(10, mLayout.Items[mIndex].Rect.Top);
    end;
  end;
  Assert.IsTrue(mFound);
  // Randfläche mit Linie oben vor dem Inhalt.
  Assert.AreEqual(mLayout.AnchorItem, FirstKind(mLayout, TAtlasHoverItemKind.Fill));
  CheckRect(Rect(0, 54, 300, 79), mLayout.Items[mLayout.AnchorItem].Rect, 'Randfläche');
  Assert.AreEqual(79, mLayout.Height);
end;

procedure THoverLayoutTests.AnchorMovesLastBandDown;
var
  mLayout: TAtlasHoverLayout;
begin
  mLayout := Build(ActionsView, 300);
  mLayout.Anchor(200);
  Assert.AreEqual(181, mLayout.Hits[0].Rect.Top);
  Assert.AreEqual(175, mLayout.Items[mLayout.AnchorItem].Rect.Top);
  // Wiederholbar, nie über die eigene Lage nach oben.
  mLayout.Anchor(200);
  Assert.AreEqual(181, mLayout.Hits[0].Rect.Top);
  mLayout.Anchor(50);
  Assert.AreEqual(60, mLayout.Hits[0].Rect.Top);
end;

procedure THoverLayoutTests.ChainProducesChipsAndHits;
var
  mHoverView: TAtlasHoverView;
  mFirst, mSecond: TAtlasHoverTypeRef;
  mLayout: TAtlasHoverLayout;
begin
  mHoverView := View('x');
  mFirst := Default(TAtlasHoverTypeRef);
  mFirst.Name := 'TA';
  mSecond := Default(TAtlasHoverTypeRef);
  mSecond.Name := 'TObject';
  mHoverView.Data.Ancestors := [mFirst, mSecond];
  mLayout := Build(mHoverView, 300);
  Assert.AreEqual(2, Integer(Length(mLayout.Hits)));
  Assert.AreEqual<TAtlasHoverHitKind>(TAtlasHoverHitKind.Ancestor, mLayout.Hits[0].Kind);
  CheckRect(Rect(11, 58, 39, 76), mLayout.Hits[0].Rect, 'TA');
  Assert.AreEqual(1, mLayout.Hits[1].Index);
  CheckRect(Rect(63, 58, 131, 76), mLayout.Hits[1].Rect, 'TObject');
  Assert.AreEqual(2, CountKind(mLayout, TAtlasHoverItemKind.Frame));
  // Ohne Fundort ist die Kette die letzte Randfläche.
  Assert.IsTrue(mLayout.AnchorItem >= 0);
  Assert.AreEqual(84, mLayout.Height);
end;

procedure THoverLayoutTests.HeightGrowsWithDocHeight;
var
  mHoverInput: TAtlasHoverInput;
  mLayout: TAtlasHoverLayout;
begin
  mHoverInput := Input(View('x'), 300);
  mHoverInput.HasDoc := True;
  mHoverInput.DocHeight := 100;
  mLayout := Build(mHoverInput);
  Assert.AreEqual(11, mLayout.DocLeft);
  Assert.AreEqual(39, mLayout.DocTop);
  Assert.AreEqual(146, mLayout.Height);
  mHoverInput.DocHeight := 40;
  Assert.AreEqual(86, Build(mHoverInput).Height);
end;

procedure THoverLayoutTests.HitAtFindsActionRect;
var
  mLayout: TAtlasHoverLayout;
begin
  mLayout := Build(ActionsView, 300);
  Assert.AreEqual(0, mLayout.HitAt(Point(20, 65)));
  Assert.AreEqual(2, mLayout.HitAt(Point(100, 60)));
  Assert.AreEqual(-1, mLayout.HitAt(Point(5, 5)));
  Assert.IsTrue(mLayout.IsHot(1, TAtlasHoverHitKind.Action, 1));
  Assert.IsFalse(mLayout.IsHot(1, TAtlasHoverHitKind.Action, 0));
  Assert.IsFalse(mLayout.IsHot(-1, TAtlasHoverHitKind.Action, 1));
end;

procedure THoverLayoutTests.BuildIsDeterministic;
var
  A, B: TAtlasHoverLayout;
  mIndex: Integer;
begin
  A := Build(ActionsView, 300);
  B := Build(ActionsView, 300);
  Assert.AreEqual(Integer(Length(A.Items)), Integer(Length(B.Items)));
  for mIndex := 0 to High(A.Items) do
  begin
    CheckRect(A.Items[mIndex].Rect, B.Items[mIndex].Rect, 'Baustein');
    Assert.AreEqual(A.Items[mIndex].Text, B.Items[mIndex].Text);
  end;
  Assert.AreEqual(A.Height, B.Height);
end;

procedure THoverLayoutTests.UsesProblemsOfferActions;

  function Codes(const ALayout: TAtlasHoverLayout): string;
  var
    mHit: TAtlasHoverHit;
    mProblem: Integer;
    mAction: TAtlasHoverProblemAction;
  begin
    Result := '';
    for mHit in ALayout.Hits do
    begin
      if mHit.Kind = TAtlasHoverHitKind.ProblemAction then
      begin
        TAtlasHoverProblemActionCode.Decode(mHit.Index, mProblem, mAction);
        Result := Result + IntToStr(mProblem) + ':' + IntToStr(Ord(mAction)) + '|';
      end;
    end;
  end;

var
  mHoverView: TAtlasHoverView;
  mPlain, mUnused, mMoved: TAtlasProblem;
  mHoverInput: TAtlasHoverInput;
  mProblem: Integer;
  mAction: TAtlasHoverProblemAction;
begin
  TAtlasHoverProblemActionCode.Decode(TAtlasHoverProblemActionCode.Encode(3,
    TAtlasHoverProblemAction.MoveUses), mProblem, mAction);
  Assert.AreEqual(3, mProblem);
  Assert.AreEqual<TAtlasHoverProblemAction>(TAtlasHoverProblemAction.MoveUses, mAction);
  mPlain := Default(TAtlasProblem);
  mPlain.Message := 'x';
  mUnused := mPlain;
  mUnused.Severity := TAtlasProblemSeverity.Hint;
  mUnused.UsesUnit := 'Vcl.Grids';
  mUnused.UsesState := TAtlasProblem.cUsesUnused;
  mUnused.UsesUnusedCount := 1;
  mMoved := mUnused;
  mMoved.UsesState := TAtlasProblem.cUsesImplementation;
  mHoverView := View('');
  mHoverView.Problems := [mPlain, mUnused, mMoved];
  mHoverInput := Input(mHoverView, 300);
  mHoverInput.Texts.UsesRemove := 'Entfernen';
  mHoverInput.Texts.UsesRemoveAll := 'Alle entfernen';
  mHoverInput.Texts.UsesMove := 'Verschieben';
  // Ein ungenutzter Eintrag: nur „Entfernen“; der zweite Hinweis bietet „Verschieben“.
  Assert.AreEqual('1:0|2:2|', Codes(Build(mHoverInput)));
  mUnused.UsesUnusedCount := 2;
  mHoverView.Problems := [mPlain, mUnused, mMoved];
  mHoverInput.View := mHoverView;
  Assert.AreEqual('1:0|1:1|2:2|', Codes(Build(mHoverInput)));
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
    mHit: TAtlasHoverHit;
    mProblem, mItem: Integer;
    mAction: TAtlasHoverProblemAction;
  begin
    Result := '';
    for mHit in ALayout.Hits do
    begin
      if mHit.Kind = TAtlasHoverHitKind.ProblemAction then
      begin
        TAtlasHoverProblemActionCode.Decode(mHit.Index, mProblem, mAction, mItem);
        if mAction in [TAtlasHoverProblemAction.Related, TAtlasHoverProblemAction.ShowGraph] then
        begin
          Result := Result + IntToStr(mProblem) + ':' + IntToStr(Ord(mAction)) + ':' + IntToStr(mItem) + '|';
        end;
      end;
    end;
  end;

var
  mHoverView: TAtlasHoverView;
  mCycle, mPlain: TAtlasProblem;
  mHoverInput: TAtlasHoverInput;
  mLayout: TAtlasHoverLayout;
  mItem: TAtlasHoverItem;
  mTexts, mProblem, mIndex: Integer;
  mAction: TAtlasHoverProblemAction;
begin
  TAtlasHoverProblemActionCode.Decode(TAtlasHoverProblemActionCode.Encode(2, TAtlasHoverProblemAction.Related, 3),
    mProblem, mAction, mIndex);
  Assert.AreEqual(2, mProblem);
  Assert.AreEqual(3, mIndex);
  Assert.AreEqual<TAtlasHoverProblemAction>(TAtlasHoverProblemAction.Related, mAction);
  mPlain := Default(TAtlasProblem);
  mPlain.Message := 'x';
  mCycle := Default(TAtlasProblem);
  mCycle.Severity := TAtlasProblemSeverity.Error;
  mCycle.Source := 'Atlas';
  mCycle.Code := TAtlasProblem.cUsesCycleCode;
  mCycle.Message := 'Zirkuläre Unit-Referenz';
  mCycle.Related := [Related('uC', 3), Related('uA', 3), Related('uB', 3), Related('uC', 3)];
  mHoverView := View('');
  mHoverView.Problems := [mPlain, mCycle];
  mHoverInput := Input(mHoverView, 600);
  mHoverInput.Texts.ShowGraph := 'Graph zeigen';
  mLayout := Build(mHoverInput);
  // Jede Unit des Pfads ist ein Link mit ihrer Stelle, dahinter „Graph zeigen“.
  Assert.AreEqual('1:6:0|1:6:1|1:6:2|1:6:3|1:7:0|', Codes(mLayout));
  mTexts := 0;
  for mItem in mLayout.Items do
  begin
    if (mItem.Kind = TAtlasHoverItemKind.Text) and (mItem.Text = ' → ') then
    begin
      Inc(mTexts);
    end;
  end;
  Assert.AreEqual(3, mTexts, 'Pfeile zwischen den Units');
  // Ohne Text kein „Graph zeigen“; andere Regeln ohne Stellen haben keine solche Zeile.
  mHoverInput.Texts.ShowGraph := '';
  Assert.AreEqual('1:6:0|1:6:1|1:6:2|1:6:3|', Codes(Build(mHoverInput)));
  mCycle.Code := 'empty-except';
  mCycle.Related := nil;
  mHoverView.Problems := [mPlain, mCycle];
  mHoverInput.View := mHoverView;
  Assert.AreEqual('', Codes(Build(mHoverInput)));
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
  mHit: TAtlasHoverHit;
  mProblem: Integer;
  mAction: TAtlasHoverProblemAction;
begin
  Result := '';
  for mHit in ALayout.Hits do
  begin
    if mHit.Kind = TAtlasHoverHitKind.ProblemAction then
    begin
      TAtlasHoverProblemActionCode.Decode(mHit.Index, mProblem, mAction);
      Result := Result + IntToStr(mProblem) + ':' + IntToStr(Ord(mAction)) + '|';
    end;
  end;
end;

function TextsOf(const ALayout: TAtlasHoverLayout; AKind: TAtlasHoverItemKind): string;
var
  mItem: TAtlasHoverItem;
begin
  Result := '';
  for mItem in ALayout.Items do
  begin
    if mItem.Kind = AKind then
    begin
      Result := Result + mItem.Text + '|';
    end;
  end;
end;

procedure THoverLayoutTests.FindingsShowPillAndRuleErrorsFirst;
var
  mHoverView: TAtlasHoverView;
  mHoverInput: TAtlasHoverInput;
  mLayout: TAtlasHoverLayout;
  mOrder: TArray<Integer>;
  mPill: Integer;
  mColors: TAtlasColors;
begin
  mHoverView := View('');
  mHoverView.Problems := [Finding(TAtlasProblemSeverity.Hint, 'Atlas', 'magic-number', 'Zahl', ''),
    Finding(TAtlasProblemSeverity.Warning, 'dcc', 'W1036', 'Variable', ''),
    Finding(TAtlasProblemSeverity.Error, 'Atlas', 'use-after-free', 'Freigegeben', '')];
  mOrder := mHoverView.ProblemOrder;
  Assert.AreEqual(3, Integer(Length(mOrder)));
  Assert.AreEqual(2, mOrder[0]);
  Assert.AreEqual(0, mOrder[1]);
  Assert.AreEqual(1, mOrder[2]);
  mHoverInput := Input(mHoverView, 300);
  mHoverInput.Texts.KindError := 'Error';
  mHoverInput.Texts.KindWarning := 'Warnung';
  mHoverInput.Texts.KindInfo := 'Info';
  mLayout := Build(mHoverInput);
  // Pillen in der Reihenfolge des Hovers; hint zählt als Info.
  Assert.AreEqual('Error|Info|Warnung|', TextsOf(mLayout, TAtlasHoverItemKind.CenterText));
  Assert.AreEqual('Freigegeben|Zahl|Variable|', TextsOf(mLayout, TAtlasHoverItemKind.Block));
  Assert.AreEqual('Atlas · use-after-free|Atlas · magic-number|dcc · W1036|',
    TextsOf(mLayout, TAtlasHoverItemKind.Text));
  // Pille in der Farbe der Art vor der Meldung, die Meldung rückt hinter sie.
  mColors := TAtlasColors.Light;
  mPill := FirstKind(mLayout, TAtlasHoverItemKind.CenterText);
  Assert.AreEqual(mColors.Error, mLayout.Items[mPill].Color);
  Assert.AreEqual(20, mLayout.Items[mPill].Rect.Left);
  // Gemessen und gezeichnet mit derselben Schrift fester Größe; die Badge-Schrift hängt an der Kästchenhöhe.
  Assert.AreEqual<TAtlasHoverFont>(TAtlasHoverFont.SmallUi, mLayout.Items[mPill].Face.Font, 'Schrift der Pille');
  Assert.AreEqual(15, mLayout.Items[mPill].Rect.Height, 'eine Zeile kleine Schrift plus Rand');
  Assert.IsTrue(mLayout.Items[FirstKind(mLayout, TAtlasHoverItemKind.Block)].Rect.Left >=
    mLayout.Items[mPill].Rect.Right + 6);
  // Ohne Aktionszeile keine Klickflächen.
  Assert.AreEqual('', ActionCodes(mLayout));
  Assert.AreEqual(-1, mLayout.FixProblem);
end;

procedure THoverLayoutTests.ConfirmedFindingShowsBothSources;
var
  mHoverView: TAtlasHoverView;
  mHoverInput: TAtlasHoverInput;
  mLayout: TAtlasHoverLayout;
  mProblem: TAtlasProblem;
begin
  mProblem := Finding(TAtlasProblemSeverity.Error, 'Atlas', 'argument-count-mismatch',
    'Suchen erwartet 1 Argumente (wie E2035).', '');
  mProblem.Confirmed := True;
  mProblem.ConfirmedCode := 'E2035';
  mHoverView := View('');
  mHoverView.Problems := [mProblem];
  mHoverInput := Input(mHoverView, 460);
  mHoverInput.Texts.Confirmed := 'vom Compiler bestätigt';
  mHoverInput.Texts.ConfirmedCode := 'vom Compiler bestätigt (%s)';
  mLayout := Build(mHoverInput);
  Assert.AreEqual('Suchen erwartet 1 Argumente (wie E2035).|', TextsOf(mLayout, TAtlasHoverItemKind.Block));
  Assert.AreEqual('Atlas + dcc · argument-count-mismatch · vom Compiler bestätigt (E2035)|',
    TextsOf(mLayout, TAtlasHoverItemKind.Text));
  mHoverInput.HideCompilerCode := True;
  mLayout := Build(mHoverInput);
  Assert.AreEqual('Suchen erwartet 1 Argumente.|', TextsOf(mLayout, TAtlasHoverItemKind.Block));
  Assert.AreEqual('Atlas + dcc · argument-count-mismatch · vom Compiler bestätigt|',
    TextsOf(mLayout, TAtlasHoverItemKind.Text));
end;

procedure THoverLayoutTests.RuleFindingsOfferActions;
var
  mHoverView: TAtlasHoverView;
  mHoverInput: TAtlasHoverInput;
  mLayout: TAtlasHoverLayout;
begin
  mHoverView := View('');
  mHoverView.Problems := [Finding(TAtlasProblemSeverity.Warning, 'Atlas', 'empty-routine', 'Leer', ''),
    Finding(TAtlasProblemSeverity.Error, 'dcc', 'E2003', 'Unbekannt', ''),
    Finding(TAtlasProblemSeverity.Error, 'Atlas', '', 'Syntax', ''),
    Finding(TAtlasProblemSeverity.Error, 'Atlas', 'loop-off-by-one', 'Zu weit', 'Count - 1 verwenden')];
  mHoverInput := Input(mHoverView, 460);
  mHoverInput.Texts.Suppress := 'Unterdrücken';
  mHoverInput.Texts.Configure := 'Einstellen';
  mHoverInput.ProblemActions := True;
  mLayout := Build(mHoverInput);
  // Fehler zuerst: Problem 3 mit Korrektur (Fix = 3), unterdrücken (4) und einstellen (5); dcc und
  // Syntaxfehler ohne Aktionen; dann die Warnung ohne Korrektur.
  Assert.AreEqual('3:3|3:4|3:5|0:4|0:5|', ActionCodes(mLayout));
  Assert.AreEqual(3, mLayout.FixProblem);
  Assert.IsTrue(Pos('Alt+Enter: |Count - 1 verwenden|', TextsOf(mLayout, TAtlasHoverItemKind.Text)) > 0);
  mHoverInput.ProblemActions := False;
  mLayout := Build(mHoverInput);
  Assert.AreEqual('', ActionCodes(mLayout));
  Assert.AreEqual(-1, mLayout.FixProblem);
  // Zusatz der Regel als eigene Zeile unter Herkunft und Regel (#1102).
  Assert.AreEqual(0, Pos('Durchsucht', TextsOf(mLayout, TAtlasHoverItemKind.Text)));
  mHoverView.Problems[0].Details := 'Durchsucht: 3 Dateien der Projektgruppe';
  mHoverInput.View := mHoverView;
  mLayout := Build(mHoverInput);
  Assert.IsTrue(Pos('Atlas · empty-routine|Durchsucht: 3 Dateien der Projektgruppe|',
    TextsOf(mLayout, TAtlasHoverItemKind.Text)) > 0, TextsOf(mLayout, TAtlasHoverItemKind.Text));
end;

procedure THoverLayoutTests.ExplainedMessagesShowCauseAndLinks;
var
  mHoverView: TAtlasHoverView;
  mHoverInput: TAtlasHoverInput;
  mLayout: TAtlasHoverLayout;
  mExplanations: TArray<TAtlasHoverExplanation>;
begin
  mHoverView := View('');
  mHoverView.Problems := [Finding(TAtlasProblemSeverity.Error, 'dcc', 'E2003', 'Unbekannt', ''),
    Finding(TAtlasProblemSeverity.Warning, 'Atlas', 'empty-routine', 'Leer', '')];
  mHoverInput := Input(mHoverView, 460);
  mHoverInput.Texts.Suppress := 'Unterdrücken';
  mHoverInput.Texts.Configure := 'Einstellen';
  mHoverInput.Texts.Explain := 'Erklären';
  mHoverInput.Texts.DocWiki := 'DocWiki';
  mHoverInput.Texts.Cause := 'Typische Ursache: %s';
  mHoverInput.ProblemActions := True;
  // Ohne Erklärungen (hover.explainMessages aus): keine Ursache, keine Links an der Meldung.
  mLayout := Build(mHoverInput);
  Assert.AreEqual('1:4|1:5|', ActionCodes(mLayout));
  SetLength(mExplanations, 2);
  mExplanations[0] := Default(TAtlasHoverExplanation);
  mExplanations[0].Known := True;
  mExplanations[0].Cause := 'Unit fehlt in uses';
  mExplanations[0].DocWiki := 'https://docwiki.embarcadero.com/RADStudio/Athens/e/index.php?search=E2003';
  mExplanations[1] := Default(TAtlasHoverExplanation);
  mExplanations[1].Known := True;
  mHoverView.Explanations := mExplanations;
  mHoverInput.View := mHoverView;
  mLayout := Build(mHoverInput);
  // Meldung: Erklären (8) und DocWiki (9); Regel: unterdrücken, einstellen, erklären.
  Assert.AreEqual('0:8|0:9|1:4|1:5|1:8|', ActionCodes(mLayout));
  // Die Ursache ist ein umbrochener Absatz (Block), keine einzelne Textzeile.
  Assert.IsTrue(Pos('Typische Ursache: Unit fehlt in uses|', TextsOf(mLayout, TAtlasHoverItemKind.Block)) > 0,
    TextsOf(mLayout, TAtlasHoverItemKind.Block));
end;

procedure THoverLayoutTests.FailedTestOffersCompare;
var
  mHoverView: TAtlasHoverView;
  mHoverInput: TAtlasHoverInput;
  mLayout: TAtlasHoverLayout;
  mExplanations: TArray<TAtlasHoverExplanation>;
begin
  mHoverView := View('');
  mHoverView.Problems := [Finding(TAtlasProblemSeverity.Error, 'DUnitX', '', 'Expected 3 but got 0', '')];
  mHoverInput := Input(mHoverView, 460);
  mHoverInput.Texts.Explain := 'Erklären';
  mHoverInput.Texts.Compare := 'Vergleichen';
  mHoverInput.ProblemActions := True;
  // Ohne Werte (kein Modul Tests, tests.compare aus): keine Links.
  mLayout := Build(mHoverInput);
  Assert.AreEqual('', ActionCodes(mLayout));
  mHoverView.Comparisons := [True];
  mHoverInput.View := mHoverView;
  mLayout := Build(mHoverInput);
  // Compare ist die Aktion 11.
  Assert.AreEqual('0:11|', ActionCodes(mLayout));
  Assert.IsTrue(Pos('Vergleichen', TextsOf(mLayout, TAtlasHoverItemKind.Text)) > 0,
    TextsOf(mLayout, TAtlasHoverItemKind.Text));
  SetLength(mExplanations, 1);
  mExplanations[0] := Default(TAtlasHoverExplanation);
  mExplanations[0].Known := True;
  mHoverView.Explanations := mExplanations;
  mHoverInput.View := mHoverView;
  mLayout := Build(mHoverInput);
  Assert.AreEqual('0:11|0:8|', ActionCodes(mLayout));
  // Mehr Werte als Probleme oder ein negativer Index zählen nicht.
  Assert.IsFalse(mHoverView.CanCompare(1));
  Assert.IsFalse(mHoverView.CanCompare(-1));
end;

procedure THoverLayoutTests.NextProblemHitCycles;
var
  mHoverView: TAtlasHoverView;
  mHoverInput: TAtlasHoverInput;
  mLayout: TAtlasHoverLayout;
  mFirst, mSecond, mLast: Integer;
begin
  mHoverView := View('procedure Foo');
  mHoverView.Problems := [Finding(TAtlasProblemSeverity.Warning, 'Atlas', 'empty-routine', 'Leer', '')];
  mHoverInput := Input(mHoverView, 460);
  mHoverInput.Texts.Suppress := 'Unterdrücken';
  mHoverInput.Texts.Configure := 'Einstellen';
  mLayout := Build(mHoverInput);
  Assert.AreEqual(-1, mLayout.NextProblemHit(-1, True));
  mHoverInput.ProblemActions := True;
  mLayout := Build(mHoverInput);
  mFirst := mLayout.NextProblemHit(-1, True);
  Assert.IsTrue(mFirst >= 0);
  mSecond := mLayout.NextProblemHit(mFirst, True);
  Assert.IsTrue(mSecond > mFirst);
  Assert.AreEqual<TAtlasHoverHitKind>(TAtlasHoverHitKind.ProblemAction, mLayout.Hits[mSecond].Kind);
  // Reihum: nach der letzten wieder die erste, rückwärts von vorn die letzte.
  Assert.AreEqual(mFirst, mLayout.NextProblemHit(mSecond, True));
  mLast := mLayout.NextProblemHit(-1, False);
  Assert.AreEqual(mSecond, mLast);
  Assert.AreEqual(mFirst, mLayout.NextProblemHit(mLast, False));
end;

function FirstProblemHit(const ALayout: TAtlasHoverLayout): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ALayout.Hits) do
  begin
    if ALayout.Hits[mIndex].Kind = TAtlasHoverHitKind.ProblemAction then
    begin
      Exit(mIndex);
    end;
  end;
end;

procedure THoverLayoutTests.RuleExampleLinkTogglesExample;
var
  mHoverView: TAtlasHoverView;
  mHoverInput: TAtlasHoverInput;
  mClosed, mOpened: TAtlasHoverLayout;
  mExample: TAtlasRuleExplanation;
  mFillCount: Integer;
begin
  mHoverView := View('');
  mHoverView.Problems := [Finding(TAtlasProblemSeverity.Warning, 'Atlas', 'empty-except', 'Leer', '')];
  mHoverInput := Input(mHoverView, 460);
  mHoverInput.Texts.Suppress := 'Unterdrücken';
  mHoverInput.Texts.Configure := 'Einstellen';
  mHoverInput.Texts.ShowExample := 'Zeigen';
  mHoverInput.Texts.HideExample := 'Ausblenden';
  mHoverInput.Texts.ExampleBad := 'Falsch:';
  mHoverInput.Texts.ExampleGood := 'Richtig:';

  mHoverInput.ProblemActions := True;
  // Ohne hover.ruleExamples wie bisher: unterdrücken (4) und einstellen (5).
  Assert.AreEqual('0:4|0:5|', ActionCodes(Build(mHoverInput)));
  mHoverInput.RuleExamples := True;
  mClosed := Build(mHoverInput);
  Assert.AreEqual('0:4|0:5|0:10|', ActionCodes(mClosed));
  Assert.IsTrue(Pos('|Zeigen|', TextsOf(mClosed, TAtlasHoverItemKind.Text)) > 0, TextsOf(mClosed,
    TAtlasHoverItemKind.Text));
  Assert.AreEqual(0, Pos('Falsch:', TextsOf(mClosed, TAtlasHoverItemKind.Text)));
  // Aufgeklappt: Beschreibung, falsch und richtig über der Aktionszeile, der Link heißt „Ausblenden“.
  mExample := Default(TAtlasRuleExplanation);
  mExample.Id := 'empty-except';
  mExample.Description := 'Verschluckt jede Ausnahme.';
  mExample.Bad := 'try' + #10 + '  Save;' + #10 + 'except' + #10 + 'end;' + #10;
  mExample.Good := 'Log(E.Message);';
  mHoverView.Examples := [mExample];
  mHoverInput.View := mHoverView;
  mOpened := Build(mHoverInput);
  Assert.AreEqual('0:4|0:5|0:10|', ActionCodes(mOpened));
  Assert.IsTrue(Pos('Falsch:|try|  Save;|except|end;|Richtig:|Log(E.Message);|Unterdrücken|Einstellen|Ausblenden|',
    TextsOf(mOpened, TAtlasHoverItemKind.Text)) > 0, TextsOf(mOpened, TAtlasHoverItemKind.Text));
  Assert.IsTrue(Pos('Verschluckt jede Ausnahme.', TextsOf(mOpened, TAtlasHoverItemKind.Block)) > 0);
  // Je Beispiel eine Fläche und ein Randstrich.
  mFillCount := CountKind(mOpened, TAtlasHoverItemKind.Fill) - CountKind(mClosed, TAtlasHoverItemKind.Fill);
  Assert.AreEqual(4, mFillCount);
  Assert.IsTrue(mOpened.Height > mClosed.Height);
  Assert.IsTrue(mOpened.Hits[FirstProblemHit(mOpened)].Rect.Top > mClosed.Hits[FirstProblemHit(mClosed)].Rect.Top);
  // Tab-Markierung bleibt beim Aufklappen auf derselben Klickfläche.
  Assert.AreEqual(FirstProblemHit(mClosed), FirstProblemHit(mOpened));
  // Ohne Aktionszeile kein Beispiel.
  mHoverInput.ProblemActions := False;
  Assert.AreEqual(0, Pos('Verschluckt', TextsOf(Build(mHoverInput), TAtlasHoverItemKind.Block)));
end;

initialization
  TDUnitX.RegisterTestFixture(THoverLayoutTests);

end.
