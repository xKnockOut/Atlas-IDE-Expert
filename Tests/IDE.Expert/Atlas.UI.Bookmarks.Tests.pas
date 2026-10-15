unit Atlas.UI.Bookmarks.Tests;

// Benannte Lesezeichen (#622), Oberfläche: Namensdialog (Vorschlag, leerer
// Name, Enter und Esc) und Seitenfenster (Spalten, „nicht gefunden“, Filter,
// Enter springt, F2 benennt um, Entf löscht, Umsortieren per Tasten und
// Ziehen, Hinweis ohne Lesezeichen, Speicherort).

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  TAtlasBookmarkDialogTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ShowsSuggestionAndButtons;
    [Test]
    procedure EmptyNameCannotBeSet;
  end;

  [TestFixture]
  TAtlasBookmarksFrameTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ShowsColumnsAndLostBookmarks;
    [Test]
    procedure FilterNarrowsTheList;
    [Test]
    procedure KeysOpenRenameAndDelete;
    [Test]
    procedure RenameIgnoresEmptyName;
    [Test]
    procedure MovesWithKeysAndDrop;
    [Test]
    procedure EmptyListShowsHint;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  Winapi.Windows,
  Vcl.Forms,
  Vcl.ComCtrls,
  Atlas.Core.Bookmarks.Store,
  Atlas.UI.Bookmarks.Dialog,
  Atlas.UI.Bookmarks.Frame;

const
  Project = 'C:\Projekt\Projekt.dproj';
  Unit1 = 'C:\Projekt\Kunde.pas';
  Unit2 = 'C:\Projekt\Lager.pas';

function SampleText: string;
begin
  Result := string.Join(#13#10, ['unit Kunde;', '', 'interface', '', 'implementation', '',
    'procedure TKunde.Laden;', 'begin', '  Pruefen;', 'end;', '', 'end.']);
end;

function SampleList: TAtlasBookmarkList;
begin
  Result := TAtlasBookmarkList.Create(Project);
  Result.Add(Unit1, SampleText, 8, 'Prüfung', 0);
  Result.Add(Unit2, SampleText, 0, 'Anfang', 0);
  Result.Add(Unit1, SampleText, 6, 'Laden', 0);
  // Datei fehlt: nicht gefunden.
  Result.LoseFile(Unit2);
end;

{ TAtlasBookmarkDialogTests }

procedure TAtlasBookmarkDialogTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasBookmarkDialogTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasBookmarkDialogTests.ShowsSuggestionAndButtons;
var
  Dialog: TAtlasBookmarkDialog;
begin
  Dialog := TAtlasBookmarkDialog.CreateDialog(nil, 'Lesezeichen – Kunde.pas, Zeile 9', 'Laden: Pruefen;');
  try
    Assert.AreEqual('Lesezeichen – Kunde.pas, Zeile 9', Dialog.Caption);
    Assert.AreEqual('Name des Lesezeichens:', Dialog.Prompt.Caption);
    Assert.AreEqual('Laden: Pruefen;', Dialog.Edit.Text, 'Vorschlag');
    Assert.IsTrue(Dialog.Edit.AutoSelect, 'Vorschlag beim Öffnen markiert');
    Assert.IsTrue(Dialog.OkButton.Default, 'Enter setzt');
    Assert.IsTrue(Dialog.CancelButton.Cancel, 'Esc bricht ab');
    Assert.AreEqual('Setzen', Dialog.OkButton.Caption);
    Assert.IsTrue(Dialog.OkButton.Enabled);
    Dialog.Edit.Text := '  Prüfung  ';
    Assert.AreEqual('Prüfung', Dialog.BookmarkName);
    Dialog.OkButton.Click;
    Assert.AreEqual(Integer(mrOk), Integer(Dialog.ModalResult));
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasBookmarkDialogTests.EmptyNameCannotBeSet;
var
  Dialog: TAtlasBookmarkDialog;
begin
  Dialog := TAtlasBookmarkDialog.CreateDialog(nil, 'Lesezeichen', 'Vorschlag');
  try
    Dialog.Edit.Text := '   ';
    Assert.IsFalse(Dialog.OkButton.Enabled, 'ohne Namen gesperrt');
    Dialog.OkButton.Click;
    Assert.AreEqual(Integer(mrNone), Integer(Dialog.ModalResult));
    Dialog.Edit.Text := 'A';
    Assert.IsTrue(Dialog.OkButton.Enabled);
    Dialog.CancelButton.Click;
    Assert.AreEqual(Integer(mrCancel), Integer(Dialog.ModalResult));
  finally
    Dialog.Free;
  end;
end;

{ TAtlasBookmarksFrameTests }

procedure TAtlasBookmarksFrameTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasBookmarksFrameTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasBookmarksFrameTests.ShowsColumnsAndLostBookmarks;
var
  Host: TForm;
  Frame: TAtlasBookmarksFrame;
  List: TAtlasBookmarkList;
begin
  List := SampleList;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasBookmarksFrame.Create(Host);
    Frame.Parent := Host;
    Frame.SetBookmarks(List, 'Projekt.dproj · lokal', List.Bookmarks[2].Id);
    Assert.AreEqual(4, Frame.List.Columns.Count);
    Assert.AreEqual('Zeilenvorschau', Frame.List.Columns[3].Caption);
    Assert.AreEqual(3, Frame.List.Items.Count, 'Reihenfolge der Liste');
    Assert.AreEqual('Prüfung', Frame.List.Items[0].Caption);
    Assert.AreEqual('Kunde.pas:9', Frame.List.Items[0].SubItems[0]);
    Assert.AreEqual('TKunde.Laden', Frame.List.Items[0].SubItems[1]);
    Assert.AreEqual('Pruefen;', Frame.List.Items[0].SubItems[2]);
    Assert.AreEqual('nicht gefunden · unit Kunde;', Frame.List.Items[1].SubItems[2]);
    Assert.AreEqual('Projekt.dproj · lokal', Frame.PlaceLabel.Caption);
    Assert.IsFalse(Frame.EmptyLabel.Visible);
    Assert.AreEqual(List.Bookmarks[2].Id, Frame.SelectedId, 'Auswahl nach Kennung');
    // Neu gefüllt ohne Kennung: Die Auswahl bleibt.
    Frame.SetBookmarks(List, 'x', '');
    Assert.AreEqual(List.Bookmarks[2].Id, Frame.SelectedId);
  finally
    Host.Free;
  end;
end;

procedure TAtlasBookmarksFrameTests.FilterNarrowsTheList;
var
  Host: TForm;
  Frame: TAtlasBookmarksFrame;
  List: TAtlasBookmarkList;
  Opened: string;
  Key: Word;
begin
  List := SampleList;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasBookmarksFrame.Create(Host);
    Frame.Parent := Host;
    Frame.OnOpen :=
      procedure(AId: string)
      begin
        Opened := AId;
      end;
    Frame.SetBookmarks(List, '', '');
    Assert.AreEqual('Filtern: Name, Datei, Methode oder Zeile', Frame.Filter.TextHint);
    Frame.Filter.Text := 'kunde laden';
    Assert.AreEqual(2, Frame.List.Items.Count, 'Datei und Methode zählen');
    Frame.Filter.Text := 'lager';
    Assert.AreEqual(1, Frame.List.Items.Count);
    Assert.AreEqual('Anfang', Frame.List.Items[0].Caption);
    // Enter im Filterfeld springt zum ersten Treffer.
    Key := VK_RETURN;
    Frame.Filter.OnKeyDown(Frame.Filter, Key, []);
    Assert.AreEqual(List.Bookmarks[1].Id, Opened);
    Frame.Filter.Text := 'gibtsnicht';
    Assert.AreEqual(0, Frame.List.Items.Count);
    Assert.IsFalse(Frame.EmptyLabel.Visible, 'Filter ohne Treffer ist kein leeres Projekt');
    Frame.Filter.Text := '';
    Assert.AreEqual(3, Frame.List.Items.Count);
  finally
    Host.Free;
  end;
end;

procedure TAtlasBookmarksFrameTests.KeysOpenRenameAndDelete;
var
  Host: TForm;
  Frame: TAtlasBookmarksFrame;
  List: TAtlasBookmarkList;
  Opened, Deleted: string;
  Key: Word;
  Allow: Boolean;
begin
  List := SampleList;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasBookmarksFrame.Create(Host);
    Frame.Parent := Host;
    Frame.OnOpen :=
      procedure(AId: string)
      begin
        Opened := AId;
      end;
    Frame.OnDelete :=
      procedure(AId: string)
      begin
        Deleted := AId;
      end;
    Frame.SetBookmarks(List, '', List.Bookmarks[1].Id);
    Key := VK_RETURN;
    Frame.List.OnKeyDown(Frame.List, Key, []);
    Assert.AreEqual(List.Bookmarks[1].Id, Opened, 'Enter springt, auch zu einem nicht gefundenen');
    Key := VK_DELETE;
    Frame.List.OnKeyDown(Frame.List, Key, []);
    Assert.AreEqual(List.Bookmarks[1].Id, Deleted, 'Entf löscht');
    Assert.AreEqual(0, Integer(Key));
    // Ein zweiter Klick startet keine Namensbearbeitung; nur F2 bzw. „Umbenennen“.
    Allow := True;
    Frame.List.OnEditing(Frame.List, Frame.List.Items[0], Allow);
    Assert.IsFalse(Allow);
    // Kontextmenü: Springen, Umbenennen, Löschen.
    Frame.Menu.OnPopup(Frame.Menu);
    Assert.AreEqual(3, Frame.Menu.Items.Count);
    Assert.IsTrue(Frame.Menu.Items[1].Enabled);
    Assert.AreEqual('Umbenennen', Frame.Menu.Items[1].Caption);
    Opened := '';
    Frame.Menu.Items[0].Click;
    Assert.AreEqual(List.Bookmarks[1].Id, Opened);
    // Klick auf die freie Fläche springt nicht.
    Opened := '';
    Frame.List.OnMouseDown(Frame.List, TMouseButton.mbLeft, [], 1, Frame.List.ClientHeight - 1);
    Frame.List.OnClick(Frame.List);
    Assert.AreEqual('', Opened);
  finally
    Host.Free;
  end;
end;

procedure TAtlasBookmarksFrameTests.RenameIgnoresEmptyName;
var
  Host: TForm;
  Frame: TAtlasBookmarksFrame;
  List: TAtlasBookmarkList;
  RenamedId, RenamedTo, S: string;
begin
  List := SampleList;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasBookmarksFrame.Create(Host);
    Frame.Parent := Host;
    Frame.OnRename :=
      procedure(AId, AName: string)
      begin
        RenamedId := AId;
        RenamedTo := AName;
      end;
    Frame.SetBookmarks(List, '', '');
    S := '  Neuer Name ';
    Frame.List.OnEdited(Frame.List, Frame.List.Items[2], S);
    Assert.AreEqual(List.Bookmarks[2].Id, RenamedId);
    Assert.AreEqual('Neuer Name', RenamedTo);
    Assert.AreEqual('Neuer Name', S);
    RenamedId := '';
    S := '   ';
    Frame.List.OnEdited(Frame.List, Frame.List.Items[0], S);
    Assert.AreEqual('', RenamedId, 'leer bleibt beim alten Namen');
    Assert.AreEqual('Prüfung', S);
  finally
    Host.Free;
  end;
end;

procedure TAtlasBookmarksFrameTests.MovesWithKeysAndDrop;
var
  Host: TForm;
  Frame: TAtlasBookmarksFrame;
  List: TAtlasBookmarkList;
  Moved, Before: string;
  Key: Word;
begin
  List := SampleList;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasBookmarksFrame.Create(Host);
    Frame.Parent := Host;
    Frame.OnMove :=
      procedure(AId, ABeforeId: string)
      begin
        Moved := AId;
        Before := ABeforeId;
      end;
    Frame.SetBookmarks(List, '', List.Bookmarks[0].Id);
    // Strg+↓: hinter den nächsten, also vor den übernächsten.
    Key := VK_DOWN;
    Frame.List.OnKeyDown(Frame.List, Key, [ssCtrl]);
    Assert.AreEqual(List.Bookmarks[0].Id, Moved);
    Assert.AreEqual(List.Bookmarks[2].Id, Before);
    // Strg+↑ ganz oben: nichts.
    Moved := '';
    Key := VK_UP;
    Frame.List.OnKeyDown(Frame.List, Key, [ssCtrl]);
    Assert.AreEqual('', Moved);
    // Unterstes nach unten: nichts; nach oben: vor das mittlere.
    Frame.SetBookmarks(List, '', List.Bookmarks[2].Id);
    Key := VK_DOWN;
    Frame.List.OnKeyDown(Frame.List, Key, [ssCtrl]);
    Assert.AreEqual('', Moved);
    Key := VK_UP;
    Frame.List.OnKeyDown(Frame.List, Key, [ssCtrl]);
    Assert.AreEqual(List.Bookmarks[2].Id, Moved);
    Assert.AreEqual(List.Bookmarks[1].Id, Before);
    // Ziehen: Drop meldet Kennung und Ziel; auf sich selbst nichts.
    Frame.Drop(List.Bookmarks[1].Id, '');
    Assert.AreEqual(List.Bookmarks[1].Id, Moved);
    Assert.AreEqual('', Before);
    Moved := '';
    Frame.Drop(List.Bookmarks[1].Id, List.Bookmarks[1].Id);
    Assert.AreEqual('', Moved);
  finally
    Host.Free;
  end;
end;

procedure TAtlasBookmarksFrameTests.EmptyListShowsHint;
var
  Host: TForm;
  Frame: TAtlasBookmarksFrame;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasBookmarksFrame.Create(Host);
    Frame.Parent := Host;
    Frame.SetBookmarks(TAtlasBookmarkList.Create(Project), 'Kein Projekt geöffnet.', '');
    Assert.IsTrue(Frame.EmptyLabel.Visible);
    Assert.IsFalse(Frame.List.Visible);
    Assert.IsTrue(Frame.EmptyLabel.Caption.StartsWith('Noch keine Lesezeichen'));
    Assert.AreEqual('', Frame.SelectedId);
    Frame.SetBookmarks(SampleList, '', '');
    Assert.IsFalse(Frame.EmptyLabel.Visible);
    Assert.IsTrue(Frame.List.Visible);
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBookmarkDialogTests);
  TDUnitX.RegisterTestFixture(TAtlasBookmarksFrameTests);

end.
