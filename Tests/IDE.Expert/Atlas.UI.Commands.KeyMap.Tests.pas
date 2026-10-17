unit Atlas.UI.Commands.KeyMap.Tests;

// Fenster „Atlas – Tastenkürzel“ (#520): Befehlspalette mit Herkunft Atlas,
// doppelt belegte Kürzel rot mit Hinweis auf den Gewinner, Suche nach Taste
// und „Nur Konflikte“, Knöpfe und HTML-Export der gezeigten Zeilen; Spalte
// „Selten per Tastatur“ aus der Zählung der Tastenkürzel-Tipps (#600).

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
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Style.Palette,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.Core.Commands.KeyMap,
  Atlas.UI.Strings,
  Atlas.UI.Commands.KeyMap;

var
  Language: TAtlasLanguage;

function AtlasItem(AFunc: TAtlasKeyFunction; AKey: Word; const AText: string): TAtlasKeyItem;
begin
  Result := TAtlasKeyItem.Create(AKey, AText, TAtlasKeyMapWindow.FunctionCaption(AFunc), TAtlasKeyOrigin.Atlas,
    TAtlasKeyMap.AtlasName, TAtlasKeyMap.ContextOf(AFunc), TAtlasKeyMap.SourceOf(AFunc),
    'Atlas.Key.' + IntToStr(Ord(AFunc)), Ord(AFunc));
  Result.Func := AFunc;
end;

/// <summary>Befehlspalette, „Auswahl erweitern“ absichtlich auf derselben Taste wie die Palette, eine Aktion der
/// IDE und eine Belegung einer anderen Erweiterung.</summary>
function Sample: TArray<TAtlasKeyItem>;
var
  Other: TAtlasKeyItem;
begin
  Other := TAtlasKeyItem.Create($4053, 'Strg+S', 'Speichern', TAtlasKeyOrigin.Ide, TAtlasKeyMap.IdeName,
    TAtlasKeyContext.Global, TAtlasKeySource.Action, 'FileSaveCommand', 4);
  Result := [AtlasItem(TAtlasKeyFunction.Palette, $6050, 'Strg+Umschalt+P'),
    AtlasItem(TAtlasKeyFunction.ExpandSelection, $6050, 'Strg+Umschalt+P'), Other,
    TAtlasKeyItem.Create($4044, 'Strg+D', 'Tastaturbelegung des Editors', TAtlasKeyOrigin.Plugin, 'CnWizards_D120',
    TAtlasKeyContext.Editor, TAtlasKeySource.Binding, 'Editor.16452', 101)];
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
  Window: TAtlasKeyMapWindow;
  Cells: TArray<string>;
begin
  Window := TAtlasKeyMapWindow.CreateKeyMap(nil, TAtlasColors.Light);
  try
    Window.SetItems(Sample);
    Assert.AreEqual(4, Integer(Length(Window.Shown)));
    Assert.AreEqual(4, Integer(Window.List.Items.Count));
    Cells := TAtlasKeyMapWindow.Cells(Window.Items, 0);
    Assert.AreEqual('Strg+Umschalt+P', Cells[0]);
    Assert.AreEqual('Befehlspalette', Cells[1]);
    Assert.AreEqual('Atlas', Cells[2], 'Herkunft der Befehlspalette (#502)');
    Assert.AreEqual('Editor', Cells[3]);
    Assert.AreEqual('Erweiterung CnWizards_D120', TAtlasKeyMapWindow.OriginText(Window.Items[3]));
    Assert.AreEqual('IDE', TAtlasKeyMapWindow.OriginText(Window.Items[2]));
    Assert.AreEqual('global', TAtlasKeyMapWindow.ContextText(TAtlasKeyContext.Global));
    Assert.AreEqual('Willkommensseite', TAtlasKeyMapWindow.ContextText(TAtlasKeyContext.WelcomePage));
    Assert.AreEqual('4 Kürzel, 2 Konflikte', Window.SummaryLabel.Caption);
  finally
    Window.Free;
  end;
end;

procedure TAtlasKeyMapWindowTests.DoubledKeyIsRedWithWinner;
var
  Items: TArray<TAtlasKeyItem>;
  Winner, Loser: Integer;
begin
  Items := Sample;
  Assert.IsTrue(Items[0].Conflict, 'absichtlich doppelt belegt: rot');
  Assert.IsTrue(Items[1].Conflict);
  Assert.IsFalse(Items[2].Conflict);
  Winner := Items[0].Winner;
  Assert.IsTrue((Winner = 0) or (Winner = 1));
  Loser := 1 - Winner;
  Assert.Contains(TAtlasKeyMapWindow.HintText(Items, Winner), 'gewinnt');
  Assert.Contains(TAtlasKeyMapWindow.HintText(Items, Loser), 'unterliegt');
  Assert.Contains(TAtlasKeyMapWindow.HintText(Items, Loser), Items[Winner].Command);
  Assert.Contains(TAtlasKeyMapWindow.HintText(Items, Loser), 'zuletzt angemeldete Tastaturbelegung');
  Assert.AreEqual('', TAtlasKeyMapWindow.HintText(Items, 2), 'ohne Konflikt kein Hinweis');
  Assert.AreEqual('', TAtlasKeyMapWindow.ReasonText(TAtlasKeyReason.None));
  Assert.Contains(TAtlasKeyMapWindow.ReasonText(TAtlasKeyReason.AtlasYields), 'überlässt');
end;

procedure TAtlasKeyMapWindowTests.SearchByKeyAndOnlyConflicts;
var
  Window: TAtlasKeyMapWindow;
begin
  Window := TAtlasKeyMapWindow.CreateKeyMap(nil, TAtlasColors.Dark);
  try
    Window.SetItems(Sample);
    Window.SetQuery('Strg+Umschalt+P');
    Assert.AreEqual(2, Integer(Length(Window.Shown)));
    Assert.AreEqual('2 von 4 Kürzeln, 2 Konflikte', Window.SummaryLabel.Caption);
    Window.SearchEdit.Text := 'Ctrl+S';
    Assert.AreEqual(1, Integer(Length(Window.Shown)), 'englisch, über OnChange');
    Assert.AreEqual(2, Window.Shown[0]);
    Window.SearchEdit.Text := 'cnwizards';
    Assert.AreEqual(1, Integer(Length(Window.Shown)), 'nach Herkunft');
    Window.SearchEdit.Text := '';
    Window.OnlyConflictsBox.Checked := True;
    Assert.AreEqual(2, Integer(Length(Window.Shown)), 'nur Konflikte');
    // Neue Belegungen behalten Suche und Filter.
    Window.SetItems(Sample);
    Assert.AreEqual(2, Integer(Length(Window.Shown)));
  finally
    Window.Free;
  end;
end;

procedure TAtlasKeyMapWindowTests.ButtonsCallEvents;
var
  Window: TAtlasKeyMapWindow;
  Exported, Settings, Refreshed: Integer;
begin
  Exported := 0;
  Settings := 0;
  Refreshed := 0;
  Window := TAtlasKeyMapWindow.CreateKeyMap(nil, TAtlasColors.Light);
  try
    Window.OnExport :=
      procedure
      begin
        Inc(Exported);
      end;
    Window.OnSettings :=
      procedure
      begin
        Inc(Settings);
      end;
    Window.OnRefresh :=
      procedure
      begin
        Inc(Refreshed);
      end;
    Window.ExportButton.Click;
    Window.SettingsButton.Click;
    Window.RefreshButton.Click;
    Window.RefreshButton.Click;
    Assert.AreEqual(1, Exported);
    Assert.AreEqual(1, Settings);
    Assert.AreEqual(2, Refreshed);
    Assert.AreEqual('Als HTML exportieren', Window.ExportButton.Caption);
    Assert.IsTrue(Window.CloseButton.Cancel);
  finally
    Window.Free;
  end;
end;

procedure TAtlasKeyMapWindowTests.ExportContainsShownRows;
var
  Window: TAtlasKeyMapWindow;
  Html: string;
begin
  Window := TAtlasKeyMapWindow.CreateKeyMap(nil, TAtlasColors.Light);
  try
    Window.SetItems(Sample);
    Html := Window.ExportHtml('15.10.2026 12:00');
    Assert.Contains(Html, '<html lang="de">');
    Assert.Contains(Html, 'Atlas – Tastenkürzel');
    Assert.Contains(Html, 'Stand: 15.10.2026 12:00 · 4 Kürzel, 2 Konflikte');
    Assert.Contains(Html, '<tr class="conflict"><td class="key">Strg+Umschalt+P</td><td>Befehlspalette</td>');
    Assert.Contains(Html, '<td class="key">Strg+S</td><td>Speichern</td>');
    Assert.Contains(Html, 'Drucken');
    Window.SetQuery('Strg+S');
    Html := Window.ExportHtml('heute');
    Assert.DoesNotContain(Html, 'Befehlspalette', False, 'nur die gezeigten Zeilen');
    Assert.Contains(Html, 'Filter: Strg+S');
  finally
    Window.Free;
  end;
end;

procedure TAtlasKeyMapWindowTests.RarelyByKeyboardColumn;
var
  Items: TArray<TAtlasKeyItem>;
  Headers, Cells: TArray<string>;
begin
  Headers := TAtlasKeyMapWindow.Headers;
  Assert.AreEqual(6, Integer(Length(Headers)));
  Assert.AreEqual('Selten per Tastatur', Headers[4]);
  Assert.AreEqual('Hinweis', Headers[5], 'Hinweis bleibt die letzte, breite Spalte');
  Items := Sample;
  // Ohne Zählung leer.
  Cells := TAtlasKeyMapWindow.Cells(Items, 0);
  Assert.AreEqual(6, Integer(Length(Cells)));
  Assert.AreEqual('', Cells[4]);
  // Fünfmal per Maus, nie über das Kürzel: selten per Tastatur.
  Items[0].MouseUses := 5;
  Items[0].KeyUses := 0;
  Assert.IsTrue(Items[0].RarelyByKeyboard);
  Assert.AreEqual('5× Maus, 0× Tastatur', TAtlasKeyMapWindow.Cells(Items, 0)[4]);
  // Meist über das Kürzel: nicht selten.
  Items[0].MouseUses := 1;
  Items[0].KeyUses := 3;
  Assert.IsFalse(Items[0].RarelyByKeyboard);
  Assert.AreEqual('', TAtlasKeyMapWindow.Cells(Items, 0)[4]);
  // Zu wenige Aufrufe für ein Urteil.
  Items[0].MouseUses := 2;
  Items[0].KeyUses := 0;
  Assert.IsFalse(Items[0].RarelyByKeyboard);
end;

procedure TAtlasKeyMapWindowTests.FunctionCaptionsWithoutPunctuation;
var
  Func, Other: TAtlasKeyFunction;
  Caption: string;
begin
  for Func := Low(TAtlasKeyFunction) to High(TAtlasKeyFunction) do
  begin
    Caption := TAtlasKeyMapWindow.FunctionCaption(Func);
    Assert.AreNotEqual('', Caption);
    Assert.IsFalse(Caption.EndsWith(':') or Caption.EndsWith('…'), Caption);
    // Jede Funktion hat ihren eigenen Namen: Eine neue Funktion ohne eigenen Zweig fiele hier auf.
    for Other := Low(TAtlasKeyFunction) to High(TAtlasKeyFunction) do
      if Other <> Func then
        Assert.AreNotEqual(Caption, TAtlasKeyMapWindow.FunctionCaption(Other), Caption);
  end;
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
