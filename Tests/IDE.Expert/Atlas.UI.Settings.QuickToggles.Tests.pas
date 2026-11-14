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
    /// <summary>Symbol rechts öffnet die Einstellung nach dem Schließen, ohne zu schalten.</summary>
    [Test]
    procedure OpenSettingRunsAfterClosing;
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
  Atlas.UI.Settings.Strings,
  Atlas.UI.Settings.QuickToggles;

const
  cCatalog =
    '{"properties":{' +
    '"PairColors":{"type":"boolean","x-page":"Editor","x-quickToggle":true,"x-caption":"Klammerfarben"},' +
    '"HoverTooltip":{"type":"boolean","x-page":"Hints","x-quickToggle":true,"x-caption":"Hover"},' +
    '"PairGuides":{"type":"boolean","x-page":"Editor","x-quickToggle":true,"x-caption":"Blocklinien"}' +
    '}}';

function SampleItems: TArray<TAtlasQuickToggleItem>;
begin
  Result := TAtlasQuickToggles.Items(TAtlasQuickToggles.Build(cCatalog, ''), TAtlasPluginSettings.Defaults,
    Default(TAtlasToggleSession), nil);
end;

procedure TAtlasQuickToggleWindowTests.WarmUpFirstUse;
begin
  GroupsByPage;
end;

procedure TAtlasQuickToggleWindowTests.GroupsByPage;
var
  mWindow: TAtlasQuickToggleWindow;
begin
  TAtlasQuickToggleRows.ExpandAll;
  mWindow := TAtlasQuickToggleWindow.CreateToggles(nil, TAtlasColors.Light);
  try
    mWindow.SetItems(SampleItems, False);
    // Editor (Überschrift), Klammerfarben, Blocklinien, Hints (Überschrift), Hover.
    Assert.AreEqual(5, mWindow.Rows.Count);
    Assert.AreEqual('Editor', mWindow.Rows.Text(0));
    Assert.AreEqual(-1, mWindow.Rows.Item(0));
    Assert.AreEqual('Klammerfarben', mWindow.Rows.Text(1));
    Assert.AreEqual('Blocklinien', mWindow.Rows.Text(2));
    Assert.AreEqual('Hints', mWindow.Rows.Text(3));
    Assert.AreEqual(-1, mWindow.Rows.Item(3));
    Assert.AreEqual('Hover', mWindow.Rows.Text(4));
    Assert.AreEqual(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.QuickTogglesAllOff), mWindow.AllButton.Caption);
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasQuickToggleWindowTests.ClickTogglesAndStaysOpen;
var
  mWindow: TAtlasQuickToggleWindow;
  mToggled: string;
  mCount: Integer;
begin
  mToggled := '';
  mCount := 0;
  TAtlasQuickToggleRows.ExpandAll;
  mWindow := TAtlasQuickToggleWindow.CreateToggles(nil, TAtlasColors.Light);
  try
    mWindow.SetItems(SampleItems, False);
    mWindow.OnToggle :=
      procedure(AItem: TAtlasQuickToggleItem)
      begin
        mToggled := AItem.Toggle.Key;
        Inc(mCount);
      end;
    mWindow.ClickRow(1);
    Assert.AreEqual(1, mCount, 'sofort');
    Assert.AreEqual('PairColors', mToggled);
    mWindow.ClickRow(4);
    Assert.AreEqual(2, mCount, 'Fenster bleibt offen');
    Assert.AreEqual('HoverTooltip', mToggled);
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasQuickToggleWindowTests.ProjectValueRunsAfterClosing;
var
  mWindow: TAtlasQuickToggleWindow;
  mItems: TArray<TAtlasQuickToggleItem>;
  mCount: Integer;
begin
  mCount := 0;
  mItems := SampleItems;
  mItems[0].Project := True;
  TAtlasQuickToggleRows.ExpandAll;
  mWindow := TAtlasQuickToggleWindow.CreateToggles(nil, TAtlasColors.Light);
  try
    mWindow.SetItems(mItems, False);
    mWindow.OnToggle :=
      procedure(AItem: TAtlasQuickToggleItem)
      begin
        Inc(mCount);
      end;
    mWindow.ClickRow(1);
    Assert.AreEqual(0, mCount, 'erst nach dem Schließen: die IDE fragt nach');
    // Schließt schon: weitere Klicks tun nichts.
    mWindow.ClickRow(2);
    CheckSynchronize;
    Application.ProcessMessages;
    Assert.AreEqual(1, mCount);
  finally
    Application.ProcessMessages;
  end;
end;

procedure TAtlasQuickToggleWindowTests.OpenSettingRunsAfterClosing;
var
  mWindow: TAtlasQuickToggleWindow;
  mOpened: string;
  mToggled: Integer;
begin
  mOpened := '';
  mToggled := 0;
  TAtlasQuickToggleRows.ExpandAll;
  mWindow := TAtlasQuickToggleWindow.CreateToggles(nil, TAtlasColors.Light);
  try
    mWindow.SetItems(SampleItems, False);
    mWindow.OnToggle :=
      procedure(AItem: TAtlasQuickToggleItem)
      begin
        Inc(mToggled);
      end;
    mWindow.OnOpenSetting :=
      procedure(AItem: TAtlasQuickToggleItem)
      begin
        mOpened := AItem.Toggle.Key;
      end;
    // Überschrift hat kein Symbol.
    mWindow.ClickOpen(0);
    Assert.AreEqual('', mOpened);
    // Tools › Optionen ist modal: erst nach dem Schließen, und geschaltet wird nichts.
    mWindow.ClickOpen(1);
    Assert.AreEqual('', mOpened, 'erst nach dem Schließen');
    CheckSynchronize;
    Application.ProcessMessages;
    Assert.AreEqual('PairColors', mOpened);
    Assert.AreEqual(0, mToggled);
  finally
    Application.ProcessMessages;
  end;
end;

procedure TAtlasQuickToggleWindowTests.AllOffButton;
var
  mWindow: TAtlasQuickToggleWindow;
  mClicked: Integer;
begin
  mClicked := 0;
  mWindow := TAtlasQuickToggleWindow.CreateToggles(nil, TAtlasColors.Dark);
  try
    mWindow.OnAllOff :=
      procedure
      begin
        Inc(mClicked);
      end;
    mWindow.SetItems(SampleItems, False);
    mWindow.AllButton.Click;
    Assert.AreEqual(1, mClicked);
    mWindow.SetItems(SampleItems, True);
    Assert.AreEqual(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.QuickTogglesAllOn), mWindow.AllButton.Caption);
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasQuickToggleWindowTests.HeaderCollapsesAndExpandsGroup;
var
  mWindow: TAtlasQuickToggleWindow;
  mCount: Integer;
begin
  mCount := 0;
  TAtlasQuickToggleRows.ExpandAll;
  mWindow := TAtlasQuickToggleWindow.CreateToggles(nil, TAtlasColors.Light);
  try
    mWindow.SetItems(SampleItems, False);
    mWindow.OnToggle :=
      procedure(AItem: TAtlasQuickToggleItem)
      begin
        Inc(mCount);
      end;
    mWindow.ClickRow(0);
    Assert.AreEqual(0, mCount, 'Überschrift schaltet nichts');
    // Editor eingeklappt: Editor, Hints, Hover.
    Assert.AreEqual(3, mWindow.Rows.Count);
    Assert.AreEqual('Editor', mWindow.Rows.Text(0));
    Assert.AreEqual('Hints', mWindow.Rows.Text(1));
    Assert.AreEqual(0, mWindow.HotRow, 'Auswahl bleibt auf der Überschrift');
    // Neues Fenster öffnet wie zuletzt verlassen.
    mWindow.Free;
    mWindow := TAtlasQuickToggleWindow.CreateToggles(nil, TAtlasColors.Light);
    mWindow.SetItems(SampleItems, False);
    Assert.AreEqual(3, mWindow.Rows.Count);
    mWindow.ClickRow(0);
    // Akkordeon: Editor wieder offen, dafür Hints zu (Editor, Klammerfarben, Blocklinien, Hints).
    Assert.AreEqual(4, mWindow.Rows.Count, 'wieder ausgeklappt');
    Assert.AreEqual('Klammerfarben', mWindow.Rows.Text(1));
    Assert.AreEqual('Hints', mWindow.Rows.Text(3));
  finally
    mWindow.Free;
    TAtlasQuickToggleRows.ExpandAll;
  end;
end;

procedure TAtlasQuickToggleWindowTests.FirstOpenAndAccordion;
var
  mWindow: TAtlasQuickToggleWindow;
begin
  TAtlasQuickToggleRows.ResetCollapse;
  mWindow := TAtlasQuickToggleWindow.CreateToggles(nil, TAtlasColors.Light);
  try
    mWindow.SetItems(SampleItems, False);
    // Erstes Öffnen: nur die erste Seite offen (Editor, Klammerfarben, Blocklinien, Hints).
    Assert.AreEqual(4, mWindow.Rows.Count);
    Assert.AreEqual('Hints', mWindow.Rows.Text(3));
    // Hints aufklappen schließt Editor: Editor, Hints, Hover.
    mWindow.ClickRow(3);
    Assert.AreEqual(3, mWindow.Rows.Count);
    Assert.AreEqual('Hover', mWindow.Rows.Text(2));
  finally
    mWindow.Free;
    TAtlasQuickToggleRows.ExpandAll;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasQuickToggleWindowTests);

end.
