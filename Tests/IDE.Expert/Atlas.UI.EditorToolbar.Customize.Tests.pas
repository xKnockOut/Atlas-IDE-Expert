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

procedure TAtlasToolbarCustomizeDialogTests.AvailableListsTheRest;
var
  Dialog: TAtlasToolbarCustomizeDialog;
  Available: TArray<string>;
begin
  Dialog := TAtlasToolbarCustomizeDialog.CreateDialog(nil, Commands,
    Config('Atlas.GotoInterface,Atlas.GotoImplementation,|,|,Atlas.NavBack,|'));
  try
    Assert.AreEqual('Atlas.GotoInterface,Atlas.GotoImplementation,|,Atlas.NavBack',
      TAtlasToolbarItems.Format(Dialog.Config.Items), 'beim Öffnen bereinigt');
    Assert.AreEqual('inBreadcrumbs', Dialog.Config.Position, 'Schreibweise der Einstellung');
    Available := Dialog.Available;
    Assert.AreEqual(3, Integer(Length(Available)));
    Assert.AreEqual('|', Available[0], 'Trennstrich zuerst');
    // Nach Beschriftung: „Code formatieren“ vor „Code-Aktionen“.
    Assert.AreEqual('Atlas.FormatCode', Available[1]);
    Assert.AreEqual('Atlas.CodeActions', Available[2]);
    Assert.AreEqual('Zurück', Dialog.CaptionOf('Atlas.NavBack'));
    Assert.AreEqual('Atlas.Unbekannt', Dialog.CaptionOf('Atlas.Unbekannt'));
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasToolbarCustomizeDialogTests.AddRemoveMove;
var
  Dialog: TAtlasToolbarCustomizeDialog;
begin
  Dialog := TAtlasToolbarCustomizeDialog.CreateDialog(nil, Commands, Config('Atlas.GotoInterface,Atlas.NavBack'));
  try
    // „Code-Aktionen“ (links Index 2) hinter Zurück.
    Assert.AreEqual(2, Dialog.AddItem(2, 2));
    Assert.AreEqual('Atlas.GotoInterface,Atlas.NavBack,Atlas.CodeActions',
      TAtlasToolbarItems.Format(Dialog.Config.Items));
    Assert.AreEqual(3, Integer(Length(Dialog.Available)), 'links verschwunden');
    // Trennstrich bleibt links und lässt sich mehrfach einfügen.
    Assert.AreEqual(1, Dialog.AddItem(0, 1));
    Assert.AreEqual('|', Dialog.Available[0]);
    Assert.AreEqual('Atlas.GotoInterface,|,Atlas.NavBack,Atlas.CodeActions',
      TAtlasToolbarItems.Format(Dialog.Config.Items));
    Assert.AreEqual(0, Dialog.MoveItem(1, -1));
    Assert.AreEqual('|,Atlas.GotoInterface,Atlas.NavBack,Atlas.CodeActions',
      TAtlasToolbarItems.Format(Dialog.Config.Items));
    Assert.IsTrue(Dialog.RemoveItem(3));
    Assert.IsFalse(Dialog.RemoveItem(9));
    Assert.AreEqual(4, Integer(Length(Dialog.Available)), 'Code-Aktionen wieder links');
    Assert.AreEqual(-1, Dialog.AddItem(7, 0), 'außerhalb');
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasToolbarCustomizeDialogTests.RestoreDefaultAndOptions;
var
  Dialog: TAtlasToolbarCustomizeDialog;
begin
  Dialog := TAtlasToolbarCustomizeDialog.CreateDialog(nil, Commands, Config(''));
  try
    Assert.AreEqual(0, Integer(Length(Dialog.Config.Items)), 'leere Leiste bleibt leer');
    Dialog.SetLabels(True);
    Dialog.SetPosition('aboveBreadcrumbs');
    Dialog.SetPosition('irgendwo');
    Assert.IsTrue(Dialog.Config.Labels);
    Assert.AreEqual('aboveBreadcrumbs', Dialog.Config.Position);
    Dialog.RestoreDefault;
    Assert.AreEqual(TAtlasToolbarItems.DefaultText, TAtlasToolbarItems.Format(Dialog.Config.Items));
    Assert.IsFalse(Dialog.Config.Labels);
    Assert.AreEqual('belowBreadcrumbs', Dialog.Config.Position);
  finally
    Dialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasToolbarCustomizeDialogTests);

end.
