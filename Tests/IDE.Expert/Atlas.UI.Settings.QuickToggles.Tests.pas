unit Atlas.UI.Settings.QuickToggles.Tests;

// Fenster der Schnellschalter (#604): Seiten als Überschriften, Klick schaltet
// sofort (Fenster bleibt offen), Schalter mit Projektwert erst nach dem
// Schließen, Knopf „Alles aus“ bzw. „Alles wieder an“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasQuickToggleWindowTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure GroupsByPage;
    [Test]
    procedure ClickTogglesAndStaysOpen;
    /// <summary>Klick auf eine Überschrift klappt die Gruppe ein und wieder aus; geschaltet wird nichts.</summary>
    [Test]
    procedure HeaderCollapsesAndExpandsGroup;
    /// <summary>Erstes Öffnen nur mit der ersten Seite; Aufklappen schließt die anderen.</summary>
    [Test]
    procedure FirstOpenAndAccordion;
    [Test]
    procedure ProjectValueRunsAfterClosing;
    [Test]
    procedure AllOffButton;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.QuickToggles,
  Atlas.UI.Strings,
  Atlas.UI.Settings.QuickToggles;

const
  Catalog =
    '{"properties":{' +
    '"PairColors":{"type":"boolean","x-page":"Editor","x-quickToggle":true,"x-caption":"Klammerfarben"},' +
    '"HoverTooltip":{"type":"boolean","x-page":"Hints","x-quickToggle":true,"x-caption":"Hover"},' +
    '"PairGuides":{"type":"boolean","x-page":"Editor","x-quickToggle":true,"x-caption":"Blocklinien"}' +
    '}}';

function SampleItems: TArray<TAtlasQuickToggleItem>;
begin
  Result := TAtlasQuickToggles.Items(TAtlasQuickToggles.Build(Catalog, ''), TAtlasPluginSettings.Defaults,
    Default(TAtlasToggleSession), nil);
end;

procedure TAtlasQuickToggleWindowTests.WarmUpFirstUse;
begin
  GroupsByPage;
end;

procedure TAtlasQuickToggleWindowTests.GroupsByPage;
var
  Window: TAtlasQuickToggleWindow;
begin
  TAtlasQuickToggleWindow.ExpandAll;
  Window := TAtlasQuickToggleWindow.CreateToggles(nil, TAtlasColors.Light);
  try
    Window.SetItems(SampleItems, False);
    // Editor (Überschrift), Klammerfarben, Blocklinien, Hints (Überschrift), Hover.
    Assert.AreEqual(5, Window.RowCount);
    Assert.AreEqual('Editor', Window.RowText(0));
    Assert.AreEqual(-1, Window.RowItem(0));
    Assert.AreEqual('Klammerfarben', Window.RowText(1));
    Assert.AreEqual('Blocklinien', Window.RowText(2));
    Assert.AreEqual('Hints', Window.RowText(3));
    Assert.AreEqual(-1, Window.RowItem(3));
    Assert.AreEqual('Hover', Window.RowText(4));
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.QuickTogglesAllOff), Window.AllButton.Caption);
  finally
    Window.Free;
  end;
end;

procedure TAtlasQuickToggleWindowTests.ClickTogglesAndStaysOpen;
var
  Window: TAtlasQuickToggleWindow;
  Toggled: string;
  Count: Integer;
begin
  Toggled := '';
  Count := 0;
  TAtlasQuickToggleWindow.ExpandAll;
  Window := TAtlasQuickToggleWindow.CreateToggles(nil, TAtlasColors.Light);
  try
    Window.SetItems(SampleItems, False);
    Window.OnToggle :=
      procedure(AItem: TAtlasQuickToggleItem)
      begin
        Toggled := AItem.Toggle.Key;
        Inc(Count);
      end;
    Window.ClickRow(1);
    Assert.AreEqual(1, Count, 'sofort');
    Assert.AreEqual('PairColors', Toggled);
    Window.ClickRow(4);
    Assert.AreEqual(2, Count, 'Fenster bleibt offen');
    Assert.AreEqual('HoverTooltip', Toggled);
  finally
    Window.Free;
  end;
end;

procedure TAtlasQuickToggleWindowTests.ProjectValueRunsAfterClosing;
var
  Window: TAtlasQuickToggleWindow;
  Items: TArray<TAtlasQuickToggleItem>;
  Count: Integer;
begin
  Count := 0;
  Items := SampleItems;
  Items[0].Project := True;
  TAtlasQuickToggleWindow.ExpandAll;
  Window := TAtlasQuickToggleWindow.CreateToggles(nil, TAtlasColors.Light);
  try
    Window.SetItems(Items, False);
    Window.OnToggle :=
      procedure(AItem: TAtlasQuickToggleItem)
      begin
        Inc(Count);
      end;
    Window.ClickRow(1);
    Assert.AreEqual(0, Count, 'erst nach dem Schließen: die IDE fragt nach');
    // Schließt schon: weitere Klicks tun nichts.
    Window.ClickRow(2);
    CheckSynchronize;
    Application.ProcessMessages;
    Assert.AreEqual(1, Count);
  finally
    Application.ProcessMessages;
  end;
end;

procedure TAtlasQuickToggleWindowTests.AllOffButton;
var
  Window: TAtlasQuickToggleWindow;
  Clicked: Integer;
begin
  Clicked := 0;
  Window := TAtlasQuickToggleWindow.CreateToggles(nil, TAtlasColors.Dark);
  try
    Window.OnAllOff :=
      procedure
      begin
        Inc(Clicked);
      end;
    Window.SetItems(SampleItems, False);
    Window.AllButton.Click;
    Assert.AreEqual(1, Clicked);
    Window.SetItems(SampleItems, True);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.QuickTogglesAllOn), Window.AllButton.Caption);
  finally
    Window.Free;
  end;
end;

procedure TAtlasQuickToggleWindowTests.HeaderCollapsesAndExpandsGroup;
var
  Window: TAtlasQuickToggleWindow;
  Count: Integer;
begin
  Count := 0;
  TAtlasQuickToggleWindow.ExpandAll;
  Window := TAtlasQuickToggleWindow.CreateToggles(nil, TAtlasColors.Light);
  try
    Window.SetItems(SampleItems, False);
    Window.OnToggle :=
      procedure(AItem: TAtlasQuickToggleItem)
      begin
        Inc(Count);
      end;
    Window.ClickRow(0);
    Assert.AreEqual(0, Count, 'Überschrift schaltet nichts');
    // Editor eingeklappt: Editor, Hints, Hover.
    Assert.AreEqual(3, Window.RowCount);
    Assert.AreEqual('Editor', Window.RowText(0));
    Assert.AreEqual('Hints', Window.RowText(1));
    Assert.AreEqual(0, Window.HotRow, 'Auswahl bleibt auf der Überschrift');
    // Neues Fenster öffnet wie zuletzt verlassen.
    Window.Free;
    Window := TAtlasQuickToggleWindow.CreateToggles(nil, TAtlasColors.Light);
    Window.SetItems(SampleItems, False);
    Assert.AreEqual(3, Window.RowCount);
    Window.ClickRow(0);
    // Akkordeon: Editor wieder offen, dafür Hints zu (Editor, Klammerfarben, Blocklinien, Hints).
    Assert.AreEqual(4, Window.RowCount, 'wieder ausgeklappt');
    Assert.AreEqual('Klammerfarben', Window.RowText(1));
    Assert.AreEqual('Hints', Window.RowText(3));
  finally
    Window.Free;
    TAtlasQuickToggleWindow.ExpandAll;
  end;
end;

procedure TAtlasQuickToggleWindowTests.FirstOpenAndAccordion;
var
  Window: TAtlasQuickToggleWindow;
begin
  TAtlasQuickToggleWindow.ResetCollapse;
  Window := TAtlasQuickToggleWindow.CreateToggles(nil, TAtlasColors.Light);
  try
    Window.SetItems(SampleItems, False);
    // Erstes Öffnen: nur die erste Seite offen (Editor, Klammerfarben, Blocklinien, Hints).
    Assert.AreEqual(4, Window.RowCount);
    Assert.AreEqual('Hints', Window.RowText(3));
    // Hints aufklappen schließt Editor: Editor, Hints, Hover.
    Window.ClickRow(3);
    Assert.AreEqual(3, Window.RowCount);
    Assert.AreEqual('Hover', Window.RowText(2));
  finally
    Window.Free;
    TAtlasQuickToggleWindow.ExpandAll;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasQuickToggleWindowTests);

end.
