unit Atlas.UI.Outline.NavigationToolbar.Tests;

// Navigationsleiste der IDE ausblenden (editor.breadcrumbsHideIdeToolbar):
// Finden am Namen und am Klassennamen, Ausblenden über ein unsichtbares
// Panel (auch wenn die IDE Visible wieder setzt), Zurückhängen an die alte
// Stelle, Freigabe mit dem Fenster.

interface

uses
  DUnitX.TestFramework,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Atlas.UI.Outline.NavigationToolbar;

type
  [TestFixture]
  TAtlasNavigationToolbarTests = class
  private
    FForm: TForm;
    FHost: TPanel;
    FToolbar: TPanel;
    FTabs: TPanel;
    FEditor: TPanel;
    FHider: TAtlasNavigationToolbar;
  public
    /// <summary>Erstgebrauch der VCL (Fenster, Klassen) vor der Leckmessung.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FindsToolbarByName;
    [Test]
    procedure HidesEvenWhenIdeShowsItAgain;
    [Test]
    procedure RestoresAtTheOldPlace;
    [Test]
    procedure FormFreeWhileHidden;
  end;

implementation

type
  /// <summary>Wie die IDE-Klasse benannt: gefunden am Klassennamen.</summary>
  TEditorNavigationToolbarLike = class(TPanel);

procedure TAtlasNavigationToolbarTests.WarmUpFirstUse;
begin
  SetUp;
  try
    FindsToolbarByName;
  finally
    TearDown;
  end;
  SetUp;
  try
    RestoresAtTheOldPlace;
  finally
    TearDown;
  end;
end;

procedure TAtlasNavigationToolbarTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  // Ausrichtung und Showing brauchen Fenster mit Handles: Formular außerhalb
  // des Bildschirms zeigen.
  FForm.BorderStyle := bsNone;
  FForm.Position := poDesigned;
  FForm.Left := -10000;
  FForm.Top := -10000;
  FForm.Width := 800;
  FForm.Height := 400;
  FHost := TPanel.Create(FForm);
  FHost.Parent := FForm;
  FHost.Align := alClient;
  // Reihenfolge wie in der IDE: Reiter, Navigationsleiste, Editor.
  FTabs := TPanel.Create(FForm);
  FTabs.Parent := FHost;
  FTabs.Align := alTop;
  FTabs.Height := 24;
  FToolbar := TPanel.Create(FForm);
  FToolbar.Name := 'TEditorNavigationToolbar';
  FToolbar.Parent := FHost;
  FToolbar.Top := 100;
  FToolbar.Align := alTop;
  FToolbar.Height := 26;
  FEditor := TPanel.Create(FForm);
  FEditor.Parent := FHost;
  FEditor.Align := alClient;
  FForm.Show;
  FHider := TAtlasNavigationToolbar.Create(nil);
end;

procedure TAtlasNavigationToolbarTests.TearDown;
begin
  FHider.Free;
  FHider := nil;
  FForm.Free;
  FForm := nil;
  FHost := nil;
  FToolbar := nil;
  FTabs := nil;
  FEditor := nil;
end;

procedure TAtlasNavigationToolbarTests.FindsToolbarByName;
var
  Other: TWinControl;
begin
  Assert.IsTrue(TAtlasNavigationToolbar.Find(FForm) = FToolbar, 'am Namen');
  Assert.IsTrue(TAtlasNavigationToolbar.Find(FEditor) = nil, 'nicht unter dem Editor');
  Assert.IsTrue(TAtlasNavigationToolbar.Find(nil) = nil);
  FToolbar.Name := '';
  Assert.IsTrue(TAtlasNavigationToolbar.Find(FForm) = nil, 'ohne Namen');
  Other := TEditorNavigationToolbarLike.Create(FForm);
  Other.Parent := FEditor;
  Assert.IsTrue(TAtlasNavigationToolbar.Find(FForm) = Other, 'am Klassennamen');
end;

procedure TAtlasNavigationToolbarTests.HidesEvenWhenIdeShowsItAgain;
var
  EditorTop: Integer;
begin
  EditorTop := FEditor.Top;
  FHider.Apply(FForm, True);
  Assert.IsTrue(TAtlasNavigationToolbar.IsHidden(FToolbar));
  Assert.IsFalse(FToolbar.Showing);
  Assert.AreEqual(1, FHider.HiddenCount);
  Assert.AreEqual(EditorTop - 26, FEditor.Top, 'Editor rückt nach oben');
  // Die IDE setzt Visible bei neuem Reiter wieder.
  FToolbar.Visible := True;
  Assert.IsFalse(FToolbar.Showing, 'bleibt verborgen');
  // Zweimal ausblenden ändert nichts.
  FHider.Apply(FForm, True);
  Assert.AreEqual(1, FHider.HiddenCount);
end;

procedure TAtlasNavigationToolbarTests.RestoresAtTheOldPlace;
begin
  FHider.Apply(FForm, True);
  FHider.Apply(FForm, False);
  Assert.IsFalse(TAtlasNavigationToolbar.IsHidden(FToolbar));
  Assert.IsTrue(FToolbar.Parent = FHost);
  Assert.IsTrue(FToolbar.Showing);
  Assert.AreEqual(0, FHider.HiddenCount);
  Assert.IsTrue(FToolbar.Top >= FTabs.Top + FTabs.Height, 'unter den Reitern');
  Assert.IsTrue(FToolbar.Top + FToolbar.Height <= FEditor.Top, 'über dem Editor');
  // Wieder ausblenden und alle zurück (Einstellung aus, Entladen).
  FHider.Apply(FForm, True);
  FHider.RestoreAll;
  Assert.IsTrue(FToolbar.Parent = FHost);
  Assert.AreEqual(0, FHider.HiddenCount);
end;

procedure TAtlasNavigationToolbarTests.FormFreeWhileHidden;
begin
  FHider.Apply(FForm, True);
  // Das Fenster geht zu: Halter und Leiste gehen mit, die Liste vergisst den Halter.
  FForm.Free;
  FForm := nil;
  FHost := nil;
  FToolbar := nil;
  FTabs := nil;
  FEditor := nil;
  Assert.AreEqual(0, FHider.HiddenCount);
  FHider.RestoreAll;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNavigationToolbarTests);

end.
