unit Atlas.UI.Commands.KeyMap.Tests;

// Fenster „Atlas – Tastenkürzel“ (#520): Befehlspalette mit Herkunft Atlas,
// doppelt belegte Kürzel rot mit Hinweis auf den Gewinner, Suche nach Taste
// und „Nur Konflikte“, Knöpfe und HTML-Export der gezeigten Zeilen; Spalte
// „Selten per Tastatur“ aus der Zählung der Tastenkürzel-Tipps (#600).
// Das Fenster ist ein Atlas-Dialog ohne eigene Farben (Thema der IDE), die
// Spalte „Hinweis“ füllt die übrige Breite.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasKeyMapWindowTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure PaletteKeyShowsOriginAtlas;
    [Test]
    procedure DoubledKeyIsRedWithWinner;
    [Test]
    procedure SearchByKeyAndOnlyConflicts;
    [Test]
    procedure ButtonsCallEvents;
    [Test]
    procedure ExportContainsShownRows;
    [Test]
    procedure FunctionCaptionsWithoutPunctuation;
    [Test]
    procedure RarelyByKeyboardColumn;
    [Test]
    procedure ThemedDialogWithFillingHintColumn;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Graphics,
  Vcl.Forms,
  Atlas.UI.Foundation.Dialog,
  Atlas.UI.Foundation.Theme,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.Core.Commands.KeyMap,
  Atlas.UI.Strings,
  Atlas.UI.Commands.KeyMap;

var
  Language: TAtlasLanguage;

function AtlasItem(AFunc: TAtlasKeyFunction; AKey: Word; const AText: string): TAtlasKeyItem;
begin
  Result := TAtlasKeyItem.Create(AKey, AText, TAtlasKeyMapWindow.FunctionCaption(AFunc),
    TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Atlas, TAtlasKeyMap.cAtlasName, TAtlasKeyMap.ContextOf(AFunc),
    TAtlasKeyMap.SourceOf(AFunc), 'Atlas.Key.' + IntToStr(Ord(AFunc)), Ord(AFunc)));
  Result.Func := AFunc;
end;

/// <summary>Befehlspalette, „Auswahl erweitern“ absichtlich auf derselben Taste wie die Palette, eine Aktion der
/// IDE und eine Belegung einer anderen Erweiterung.</summary>
function Sample: TArray<TAtlasKeyItem>;
var
  mOther: TAtlasKeyItem;
begin
  mOther := TAtlasKeyItem.Create($4053, 'Strg+S', 'Speichern', TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Ide,
    TAtlasKeyMap.cIdeName, TAtlasKeyContext.Global, TAtlasKeySource.Action, 'FileSaveCommand', 4));
  Result := [AtlasItem(TAtlasKeyFunction.Palette, $6050, 'Strg+Umschalt+P'),
    AtlasItem(TAtlasKeyFunction.ExpandSelection, $6050, 'Strg+Umschalt+P'), mOther,
    TAtlasKeyItem.Create($4044, 'Strg+D', 'Tastaturbelegung des Editors',
      TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Plugin, 'CnWizards_D120', TAtlasKeyContext.Editor,
      TAtlasKeySource.Binding, 'Editor.16452', 101))];
  TAtlasKeyMap.Analyze(Result);
end;

procedure TAtlasKeyMapWindowTests.WarmUpFirstUse;
begin
  Setup;
  try
    PaletteKeyShowsOriginAtlas;
  finally
    TearDown;
  end;
end;

procedure TAtlasKeyMapWindowTests.Setup;
begin
  Language := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasKeyMapWindowTests.TearDown;
begin
  TAtlasStrings.Language := Language;
end;

procedure TAtlasKeyMapWindowTests.PaletteKeyShowsOriginAtlas;
var
  mWindow: TAtlasKeyMapWindow;
  mCells: TArray<string>;
begin
  mWindow := TAtlasKeyMapWindow.CreateKeyMap(nil);
  try
    mWindow.SetItems(Sample);
    Assert.AreEqual(4, Integer(Length(mWindow.Shown)));
    Assert.AreEqual(4, Integer(mWindow.List.Items.Count));
    mCells := TAtlasKeyMapWindow.Cells(mWindow.Items, 0);
    Assert.AreEqual('Strg+Umschalt+P', mCells[0]);
    Assert.AreEqual('Befehlspalette', mCells[1]);
    Assert.AreEqual('Atlas', mCells[2], 'Herkunft der Befehlspalette (#502)');
    Assert.AreEqual('Editor', mCells[3]);
    Assert.AreEqual('Erweiterung CnWizards_D120', TAtlasKeyMapWindow.OriginText(mWindow.Items[3]));
    Assert.AreEqual('IDE', TAtlasKeyMapWindow.OriginText(mWindow.Items[2]));
    Assert.AreEqual('global', TAtlasKeyMapWindow.ContextText(TAtlasKeyContext.Global));
    Assert.AreEqual('Willkommensseite', TAtlasKeyMapWindow.ContextText(TAtlasKeyContext.WelcomePage));
    Assert.AreEqual('4 Kürzel, 2 Konflikte', mWindow.SummaryLabel.Caption);
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasKeyMapWindowTests.DoubledKeyIsRedWithWinner;
var
  mItems: TArray<TAtlasKeyItem>;
  mWinner, mLoser: Integer;
begin
  mItems := Sample;
  Assert.IsTrue(mItems[0].Conflict, 'absichtlich doppelt belegt: rot');
  Assert.IsTrue(mItems[1].Conflict);
  Assert.IsFalse(mItems[2].Conflict);
  mWinner := mItems[0].Winner;
  Assert.IsTrue((mWinner = 0) or (mWinner = 1));
  mLoser := 1 - mWinner;
  Assert.Contains(TAtlasKeyMapWindow.HintText(mItems, mWinner), 'gewinnt');
  Assert.Contains(TAtlasKeyMapWindow.HintText(mItems, mLoser), 'unterliegt');
  Assert.Contains(TAtlasKeyMapWindow.HintText(mItems, mLoser), mItems[mWinner].Command);
  Assert.Contains(TAtlasKeyMapWindow.HintText(mItems, mLoser), 'zuletzt angemeldete Tastaturbelegung');
  Assert.AreEqual('', TAtlasKeyMapWindow.HintText(mItems, 2), 'ohne Konflikt kein Hinweis');
  Assert.AreEqual('', TAtlasKeyMapWindow.ReasonText(TAtlasKeyReason.None));
  Assert.Contains(TAtlasKeyMapWindow.ReasonText(TAtlasKeyReason.AtlasYields), 'überlässt');
end;

procedure TAtlasKeyMapWindowTests.SearchByKeyAndOnlyConflicts;
var
  mWindow: TAtlasKeyMapWindow;
begin
  mWindow := TAtlasKeyMapWindow.CreateKeyMap(nil);
  try
    mWindow.SetItems(Sample);
    mWindow.SetQuery('Strg+Umschalt+P');
    Assert.AreEqual(2, Integer(Length(mWindow.Shown)));
    Assert.AreEqual('2 von 4 Kürzeln, 2 Konflikte', mWindow.SummaryLabel.Caption);
    mWindow.SearchEdit.Text := 'Ctrl+S';
    Assert.AreEqual(1, Integer(Length(mWindow.Shown)), 'englisch, über OnChange');
    Assert.AreEqual(2, mWindow.Shown[0]);
    mWindow.SearchEdit.Text := 'cnwizards';
    Assert.AreEqual(1, Integer(Length(mWindow.Shown)), 'nach Herkunft');
    mWindow.SearchEdit.Text := '';
    mWindow.OnlyConflictsBox.Checked := True;
    Assert.AreEqual(2, Integer(Length(mWindow.Shown)), 'nur Konflikte');
    // Neue Belegungen behalten Suche und Filter.
    mWindow.SetItems(Sample);
    Assert.AreEqual(2, Integer(Length(mWindow.Shown)));
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasKeyMapWindowTests.ButtonsCallEvents;
var
  mWindow: TAtlasKeyMapWindow;
  mExported, mSettings, mRefreshed: Integer;
begin
  mExported := 0;
  mSettings := 0;
  mRefreshed := 0;
  mWindow := TAtlasKeyMapWindow.CreateKeyMap(nil);
  try
    mWindow.OnExport :=
      procedure
      begin
        Inc(mExported);
      end;
    mWindow.OnSettings :=
      procedure
      begin
        Inc(mSettings);
      end;
    mWindow.OnRefresh :=
      procedure
      begin
        Inc(mRefreshed);
      end;
    mWindow.ExportButton.Click;
    mWindow.SettingsButton.Click;
    mWindow.RefreshButton.Click;
    mWindow.RefreshButton.Click;
    Assert.AreEqual(1, mExported);
    Assert.AreEqual(1, mSettings);
    Assert.AreEqual(2, mRefreshed);
    Assert.AreEqual('Als HTML exportieren', mWindow.ExportButton.Caption);
    Assert.IsTrue(mWindow.CloseButton.Cancel);
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasKeyMapWindowTests.ExportContainsShownRows;
var
  mWindow: TAtlasKeyMapWindow;
  mHtml: string;
begin
  mWindow := TAtlasKeyMapWindow.CreateKeyMap(nil);
  try
    mWindow.SetItems(Sample);
    mHtml := mWindow.ExportHtml('15.10.2026 12:00');
    Assert.Contains(mHtml, '<html lang="de">');
    Assert.Contains(mHtml, 'Atlas – Tastenkürzel');
    Assert.Contains(mHtml, 'Stand: 15.10.2026 12:00 · 4 Kürzel, 2 Konflikte');
    Assert.Contains(mHtml, '<tr class="conflict"><td class="key">Strg+Umschalt+P</td><td>Befehlspalette</td>');
    Assert.Contains(mHtml, '<td class="key">Strg+S</td><td>Speichern</td>');
    Assert.Contains(mHtml, 'Drucken');
    mWindow.SetQuery('Strg+S');
    mHtml := mWindow.ExportHtml('heute');
    Assert.DoesNotContain(mHtml, 'Befehlspalette', False, 'nur die gezeigten Zeilen');
    Assert.Contains(mHtml, 'Filter: Strg+S');
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasKeyMapWindowTests.RarelyByKeyboardColumn;
var
  mItems: TArray<TAtlasKeyItem>;
  mHeaders, mCells: TArray<string>;
begin
  mHeaders := TAtlasKeyMapWindow.Headers;
  Assert.AreEqual(6, Integer(Length(mHeaders)));
  Assert.AreEqual('Selten per Tastatur', mHeaders[4]);
  Assert.AreEqual('Hinweis', mHeaders[5], 'Hinweis bleibt die letzte, breite Spalte');
  mItems := Sample;
  // Ohne Zählung leer.
  mCells := TAtlasKeyMapWindow.Cells(mItems, 0);
  Assert.AreEqual(6, Integer(Length(mCells)));
  Assert.AreEqual('', mCells[4]);
  // Fünfmal per Maus, nie über das Kürzel: selten per Tastatur.
  mItems[0].MouseUses := 5;
  mItems[0].KeyUses := 0;
  Assert.IsTrue(mItems[0].RarelyByKeyboard);
  Assert.AreEqual('5× Maus, 0× Tastatur', TAtlasKeyMapWindow.Cells(mItems, 0)[4]);
  // Meist über das Kürzel: nicht selten.
  mItems[0].MouseUses := 1;
  mItems[0].KeyUses := 3;
  Assert.IsFalse(mItems[0].RarelyByKeyboard);
  Assert.AreEqual('', TAtlasKeyMapWindow.Cells(mItems, 0)[4]);
  // Zu wenige Aufrufe für ein Urteil.
  mItems[0].MouseUses := 2;
  mItems[0].KeyUses := 0;
  Assert.IsFalse(mItems[0].RarelyByKeyboard);
end;

procedure TAtlasKeyMapWindowTests.ThemedDialogWithFillingHintColumn;
var
  mWindow: TAtlasKeyMapWindow;
  mFixed, mIndex: Integer;
begin
  mWindow := TAtlasKeyMapWindow.CreateKeyMap(nil);
  try
    Assert.IsTrue(mWindow is TAtlasDialog, 'Thema über den Atlas-Dialog');
    Assert.IsTrue(TAtlasUiTheme.Subscribed(mWindow), 'folgt dem Themenwechsel');
    Assert.AreEqual(Integer(clBtnFace), Integer(mWindow.Color), 'keine eigene Fensterfarbe');
    Assert.AreEqual(Integer(clWindow), Integer(mWindow.List.Color), 'keine eigene Listenfarbe');
    Assert.AreEqual<TFormBorderStyle>(bsSizeable, mWindow.BorderStyle, 'Größe ziehbar');
    mWindow.SetItems(Sample);
    mFixed := 0;
    for mIndex := 0 to mWindow.List.Columns.Count - 2 do
    begin
      Inc(mFixed, mWindow.List.Columns[mIndex].Width);
    end;
    Assert.AreEqual(mWindow.List.ClientWidth - mFixed, Integer(mWindow.List.Columns[5].Width),
      'Hinweis nimmt die übrige Breite');
    mWindow.Width := mWindow.Width + mWindow.ScaleValue(200);
    Assert.AreEqual(mWindow.List.ClientWidth - mFixed, Integer(mWindow.List.Columns[5].Width), 'wächst mit');
  finally
    mWindow.Free;
  end;
end;

/// <summary>Jede Funktion hat eine eigene, nicht leere Beschriftung ohne Doppelpunkt oder Auslassung.</summary>
procedure AssertCaptionsPlainAndUnique;
var
  mFunc, mOther: TAtlasKeyFunction;
  mCaption: string;
begin
  for mFunc := Low(TAtlasKeyFunction) to High(TAtlasKeyFunction) do
  begin
    mCaption := TAtlasKeyMapWindow.FunctionCaption(mFunc);
    Assert.AreNotEqual('', mCaption);
    Assert.IsFalse(mCaption.EndsWith(':') or mCaption.EndsWith('…'), mCaption);
    // Jede Funktion hat ihren eigenen Namen: Eine neue Funktion ohne eigenen Zweig fiele hier auf.
    for mOther := Low(TAtlasKeyFunction) to High(TAtlasKeyFunction) do
    begin
      if mOther <> mFunc then
      begin
        Assert.AreNotEqual(mCaption, TAtlasKeyMapWindow.FunctionCaption(mOther), mCaption);
      end;
    end;
  end;
end;

procedure TAtlasKeyMapWindowTests.FunctionCaptionsWithoutPunctuation;
begin
  AssertCaptionsPlainAndUnique;
  Assert.AreEqual('Deklaration/Implementierung wechseln',
    TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.MethodToggleUp));
  Assert.AreEqual('Zwischen Unit und Testunit wechseln',
    TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.TestUnit));
  Assert.AreEqual('Units suchen', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.UnitSearch));
  Assert.AreEqual('Lesezeichen setzen', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.Bookmark));
  Assert.AreEqual('Erzeugen', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.GenerateMenu));
  Assert.AreEqual('Benachrichtigungen', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.Notifications));
  Assert.AreEqual('Element ausblenden', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.HideElement));
  Assert.AreEqual('Nächster Befund', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.NextProblem));
  Assert.AreEqual('Vorheriger Befund', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.PreviousProblem));
  Assert.AreEqual('Schnell öffnen', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.QuickOpen));
  Assert.AreEqual('Letzte Bearbeitungsstelle', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.LastEdit));
  Assert.AreEqual('Definition einblenden', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.PeekDefinition));
  Assert.AreEqual('Referenzen einblenden', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.PeekReferences));
  Assert.AreEqual('Brotkrumenleiste', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.Breadcrumbs));
  Assert.AreEqual('Zum Gegenstück springen', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.JumpToMatch));
  Assert.AreEqual('Bis zum Gegenstück markieren',
    TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.JumpToMatchSelect));
  Assert.AreEqual('Nächste Änderung', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.NextChange));
  Assert.AreEqual('Vorherige Änderung', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.PreviousChange));
  Assert.AreEqual('Zeilen nach oben verschieben', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.MoveLinesUp));
  Assert.AreEqual('Anweisung vervollständigen',
    TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.CompleteStatement));
  Assert.AreEqual('Formatieren', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.FormatCode));
  Assert.AreEqual('Blockkommentar umschalten',
    TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.ToggleBlockComment));
  Assert.AreEqual('Neue Zeile darunter', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.NewLineBelow));
  Assert.AreEqual('Neue Zeile darüber', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.NewLineAbove));
  Assert.AreEqual('Umschließung entfernen', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.Unwrap));
  Assert.AreEqual('Typ des Ausdrucks', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.ExpressionType));
  Assert.AreEqual('Fenster „Atlas-Prüfung“', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.ProblemsWindow));
  Assert.AreEqual('Zum interface-Teil', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.SectionInterface));
  Assert.AreEqual('Zum implementation-Teil', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.SectionImplementation));
  Assert.AreEqual('Lesezeichen 1–9 setzen', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.QuickBookmarkSet));
  Assert.AreEqual('Zu Lesezeichen 1–9 springen',
    TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.QuickBookmarkJump));
  Assert.AreEqual('Nächstes Lesezeichen', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.NextBookmark));
  Assert.AreEqual('Zeilen darunter duplizieren',
    TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.DuplicateLinesDown));
  // #764: Schnellaktionen der Willkommensseite.
  Assert.AreEqual('Schnellaktion „Öffnen und bauen“',
    TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.WelcomeQuickBuild));
  Assert.AreEqual('Schnellaktion „Tests“', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.WelcomeQuickTests));
  Assert.AreEqual('Code-Aktionen', TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.CodeActions));
  Assert.AreEqual('Suchfeld der Willkommensseite',
    TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.WelcomeSearch));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasKeyMapWindowTests);

end.
