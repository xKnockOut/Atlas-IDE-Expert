unit Atlas.UI.Settings.Bindings.Tests;

// Bindung der Steuerelemente der Optionsseite an Plugin-Einstellungen (TAtlasSettingsBindings): Laden und Speichern
// je Art über einen Speicher mit Registry-Namen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSettingsBindingsTests = class
  public
    [Test]
    procedure CheckLoadsAndSaves;
    /// <summary>Zahlen bleiben Zahlen; ein Text, der keine Zahl ist, lässt den Wert stehen.</summary>
    [Test]
    procedure TextKeepsNumbers;
    [Test]
    procedure TextTrimsOnSave;
    [Test]
    procedure ShortcutAsNumber;
    /// <summary>Auswahl über die gespeicherten Werte; unbekannter Wert wählt den ersten Eintrag.</summary>
    [Test]
    procedure ChoiceByValue;
    [Test]
    procedure CountAndClear;
  end;

implementation

uses
  System.Classes,
  Vcl.StdCtrls,
  Vcl.Menus,
  Atlas.Core.Settings.History,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Bindings;

procedure TAtlasSettingsBindingsTests.CheckLoadsAndSaves;
var
  mBindings: TAtlasSettingsBindings;
  mStore: IAtlasMemorySettingsStore;
  mCheck: TCheckBox;
begin
  mBindings := TAtlasSettingsBindings.Create;
  mCheck := TCheckBox.Create(nil);
  try
    mBindings.Add('Peek', mCheck, sbkCheck, nil);
    mStore := TAtlasMemorySettingsStore.Create;
    mStore.WriteInteger('Peek', 1);
    mBindings.Load(mStore);
    Assert.IsTrue(mCheck.Checked);
    mCheck.Checked := False;
    mBindings.Save(mStore);
    Assert.AreEqual(0, mStore.ReadInteger('Peek', 1));
  finally
    mCheck.Free;
    mBindings.Free;
  end;
end;

procedure TAtlasSettingsBindingsTests.TextKeepsNumbers;
var
  mBindings: TAtlasSettingsBindings;
  mStore: IAtlasMemorySettingsStore;
  mEdit: TEdit;
begin
  mBindings := TAtlasSettingsBindings.Create;
  mEdit := TEdit.Create(nil);
  try
    mBindings.Add('PeekHeightLines', mEdit, sbkText, nil);
    mStore := TAtlasMemorySettingsStore.Create;
    mStore.WriteInteger('PeekHeightLines', 12);
    mBindings.Load(mStore);
    Assert.AreEqual('12', string(mEdit.Text));
    mEdit.Text := '20';
    mBindings.Save(mStore);
    Assert.AreEqual(20, mStore.ReadInteger('PeekHeightLines', 0));
    Assert.IsTrue(mStore.HasInteger('PeekHeightLines'), 'bleibt eine Zahl');
    mEdit.Text := 'zwanzig';
    mBindings.Save(mStore);
    Assert.AreEqual(20, mStore.ReadInteger('PeekHeightLines', 0), 'keine Zahl: alter Wert bleibt');
  finally
    mEdit.Free;
    mBindings.Free;
  end;
end;

procedure TAtlasSettingsBindingsTests.TextTrimsOnSave;
var
  mBindings: TAtlasSettingsBindings;
  mStore: IAtlasMemorySettingsStore;
  mEdit: TEdit;
begin
  mBindings := TAtlasSettingsBindings.Create;
  mEdit := TEdit.Create(nil);
  try
    mBindings.Add('EditorToolbarItems', mEdit, sbkText, nil);
    mStore := TAtlasMemorySettingsStore.Create;
    mStore.WriteString('EditorToolbarItems', 'a');
    mBindings.Load(mStore);
    Assert.AreEqual('a', string(mEdit.Text));
    mEdit.Text := '  b, c  ';
    mBindings.Save(mStore);
    Assert.AreEqual('b, c', mStore.ReadString('EditorToolbarItems', ''));
  finally
    mEdit.Free;
    mBindings.Free;
  end;
end;

procedure TAtlasSettingsBindingsTests.ShortcutAsNumber;
var
  mBindings: TAtlasSettingsBindings;
  mStore: IAtlasMemorySettingsStore;
  mEdit: TEdit;
begin
  mBindings := TAtlasSettingsBindings.Create;
  mEdit := TEdit.Create(nil);
  try
    mBindings.Add('ActionsKey', mEdit, sbkShortcut, nil);
    mStore := TAtlasMemorySettingsStore.Create;
    mStore.WriteInteger('ActionsKey', Integer(TextToShortCut('Ctrl+K')));
    mBindings.Load(mStore);
    Assert.AreEqual(ShortCutToText(TextToShortCut('Ctrl+K')), string(mEdit.Text));
    mEdit.Text := '';
    mBindings.Save(mStore);
    Assert.AreEqual(0, mStore.ReadInteger('ActionsKey', -1), 'leer = keine Taste');
  finally
    mEdit.Free;
    mBindings.Free;
  end;
end;

procedure TAtlasSettingsBindingsTests.ChoiceByValue;
var
  mBindings: TAtlasSettingsBindings;
  mStore: IAtlasMemorySettingsStore;
  mChoice: TAtlasChoiceBox;
begin
  mBindings := TAtlasSettingsBindings.Create;
  mChoice := TAtlasChoiceBox.Create(nil);
  try
    mChoice.SetChoices(['Rechts', 'Links']);
    mBindings.Add('MinimapSide', mChoice, sbkChoice, TArray<string>.Create('right', 'left'));
    mStore := TAtlasMemorySettingsStore.Create;
    mStore.WriteString('MinimapSide', 'LEFT');
    mBindings.Load(mStore);
    Assert.AreEqual(1, mChoice.Choice);
    mStore.WriteString('MinimapSide', 'oben');
    mBindings.Load(mStore);
    Assert.AreEqual(0, mChoice.Choice, 'unbekannt = erster Eintrag');
    mChoice.Choice := 1;
    mBindings.Save(mStore);
    Assert.AreEqual('left', mStore.ReadString('MinimapSide', ''));
  finally
    mChoice.Free;
    mBindings.Free;
  end;
end;

procedure TAtlasSettingsBindingsTests.CountAndClear;
var
  mBindings: TAtlasSettingsBindings;
  mCheck: TCheckBox;
begin
  mBindings := TAtlasSettingsBindings.Create;
  mCheck := TCheckBox.Create(nil);
  try
    mBindings.Add('Peek', mCheck, sbkCheck, nil);
    Assert.AreEqual(1, mBindings.Count);
    Assert.AreEqual('Peek', mBindings.Item(0).Name);
    Assert.AreSame(mCheck, mBindings.Item(0).Control);
    mBindings.Clear;
    Assert.AreEqual(0, mBindings.Count);
  finally
    mCheck.Free;
    mBindings.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsBindingsTests);

end.
