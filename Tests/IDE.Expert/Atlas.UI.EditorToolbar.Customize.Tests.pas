unit Atlas.UI.EditorToolbar.Customize.Tests;

// Atlas-Editorleiste (#1101): Dialog „Leiste anpassen“. Links nur, was noch
// nicht in der Leiste steht (Trennstrich immer), hinzufügen, entfernen,
// verschieben, Standard wiederherstellen; Beschriftungen aus der Palette.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasToolbarCustomizeDialogTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen: Der erste Dialog im Prozess legt einmalig Speicher der VCL
    /// an, der sonst je nach Reihenfolge der Tests als Leck zählt.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure AvailableListsTheRest;
    [Test]
    procedure AddRemoveMove;
    [Test]
    procedure RestoreDefaultAndOptions;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.ToolbarItems,
  Atlas.UI.EditorToolbar.Customize;

function Commands: TArray<TAtlasToolbarCommandInfo>;
begin
  Result := [TAtlasToolbarCommandInfo.Create('Atlas.GotoInterface', 'Zum interface-Teil'),
    TAtlasToolbarCommandInfo.Create('Atlas.GotoImplementation', 'Zum implementation-Teil'),
    TAtlasToolbarCommandInfo.Create('Atlas.NavBack', 'Zurück'),
    TAtlasToolbarCommandInfo.Create('Atlas.FormatCode', 'Code formatieren'),
    TAtlasToolbarCommandInfo.Create('Atlas.CodeActions', 'Code-Aktionen')];
end;

function Config(const AItems: string): TAtlasToolbarConfig;
begin
  Result.Items := TAtlasToolbarItems.Parse(AItems);
  Result.Labels := False;
  Result.Position := 'inbreadcrumbs';
end;

procedure TAtlasToolbarCustomizeDialogTests.WarmUpFirstUse;
begin
  AvailableListsTheRest;
end;

procedure TAtlasToolbarCustomizeDialogTests.AvailableListsTheRest;
var
  mDialog: TAtlasToolbarCustomizeDialog;
  mAvailable: TArray<string>;
begin
  mDialog := TAtlasToolbarCustomizeDialog.CreateDialog(nil, Commands,
    Config('Atlas.GotoInterface,Atlas.GotoImplementation,|,|,Atlas.NavBack,|'));
  try
    Assert.AreEqual('Atlas.GotoInterface,Atlas.GotoImplementation,|,Atlas.NavBack',
      TAtlasToolbarItems.Format(mDialog.Config.Items), 'beim Öffnen bereinigt');
    Assert.AreEqual('inBreadcrumbs', mDialog.Config.Position, 'Schreibweise der Einstellung');
    mAvailable := mDialog.Available;
    Assert.AreEqual(3, Integer(Length(mAvailable)));
    Assert.AreEqual('|', mAvailable[0], 'Trennstrich zuerst');
    // Nach Beschriftung: „Code formatieren“ vor „Code-Aktionen“.
    Assert.AreEqual('Atlas.FormatCode', mAvailable[1]);
    Assert.AreEqual('Atlas.CodeActions', mAvailable[2]);
    Assert.AreEqual('Zurück', mDialog.CaptionOf('Atlas.NavBack'));
    Assert.AreEqual('Atlas.Unbekannt', mDialog.CaptionOf('Atlas.Unbekannt'));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasToolbarCustomizeDialogTests.AddRemoveMove;
var
  mDialog: TAtlasToolbarCustomizeDialog;
begin
  mDialog := TAtlasToolbarCustomizeDialog.CreateDialog(nil, Commands, Config('Atlas.GotoInterface,Atlas.NavBack'));
  try
    // „Code-Aktionen“ (links Index 2) hinter Zurück.
    Assert.AreEqual(2, mDialog.AddItem(2, 2));
    Assert.AreEqual('Atlas.GotoInterface,Atlas.NavBack,Atlas.CodeActions',
      TAtlasToolbarItems.Format(mDialog.Config.Items));
    Assert.AreEqual(3, Integer(Length(mDialog.Available)), 'links verschwunden');
    // Trennstrich bleibt links und lässt sich mehrfach einfügen.
    Assert.AreEqual(1, mDialog.AddItem(0, 1));
    Assert.AreEqual('|', mDialog.Available[0]);
    Assert.AreEqual('Atlas.GotoInterface,|,Atlas.NavBack,Atlas.CodeActions',
      TAtlasToolbarItems.Format(mDialog.Config.Items));
    Assert.AreEqual(0, mDialog.MoveItem(1, -1));
    Assert.AreEqual('|,Atlas.GotoInterface,Atlas.NavBack,Atlas.CodeActions',
      TAtlasToolbarItems.Format(mDialog.Config.Items));
    Assert.IsTrue(mDialog.RemoveItem(3));
    Assert.IsFalse(mDialog.RemoveItem(9));
    Assert.AreEqual(4, Integer(Length(mDialog.Available)), 'Code-Aktionen wieder links');
    Assert.AreEqual(-1, mDialog.AddItem(7, 0), 'außerhalb');
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasToolbarCustomizeDialogTests.RestoreDefaultAndOptions;
var
  mDialog: TAtlasToolbarCustomizeDialog;
begin
  mDialog := TAtlasToolbarCustomizeDialog.CreateDialog(nil, Commands, Config(''));
  try
    Assert.AreEqual(0, Integer(Length(mDialog.Config.Items)), 'leere Leiste bleibt leer');
    mDialog.SetLabels(True);
    mDialog.SetPosition('aboveBreadcrumbs');
    mDialog.SetPosition('irgendwo');
    Assert.IsTrue(mDialog.Config.Labels);
    Assert.AreEqual('aboveBreadcrumbs', mDialog.Config.Position);
    mDialog.RestoreDefault;
    Assert.AreEqual(TAtlasToolbarItems.DefaultText, TAtlasToolbarItems.Format(mDialog.Config.Items));
    Assert.IsFalse(mDialog.Config.Labels);
    Assert.AreEqual('belowBreadcrumbs', mDialog.Config.Position);
  finally
    mDialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasToolbarCustomizeDialogTests);

end.
