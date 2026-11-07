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
  [Category('Atlas.IDE.Bookmarks')]
  TAtlasBookmarkDialogTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
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
  [Category('Atlas.IDE.Bookmarks')]
  TAtlasBookmarksFrameTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
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
    /// <summary>Schnelle Lesezeichen (#1104): Spalte „Nr.“, Methode als Name, „nur diese Datei“,
    /// Strg+Umschalt+Zahl vergibt die Nummer.</summary>
    [Test]
    procedure QuickBookmarksInWindow;
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
  Atlas.Core.Bookmarks.Quick,
  Atlas.UI.Bookmarks.Dialog,
  Atlas.UI.Bookmarks.Frame;

const
  cProject = 'C:\Projekt\Projekt.dproj';
  cUnit1 = 'C:\Projekt\Kunde.pas';
  cUnit2 = 'C:\Projekt\Lager.pas';

function SampleText: string;
begin
  Result := string.Join(#13#10, ['unit Kunde;', '', 'interface', '', 'implementation', '',
    'procedure TKunde.Laden;', 'begin', '  Pruefen;', 'end;', '', 'end.']);
end;

function SampleList: TAtlasBookmarkList;
begin
  Result := TAtlasBookmarkList.Create(cProject);
  Result.Add(cUnit1, SampleText, 8, 'Prüfung', 0);
  Result.Add(cUnit2, SampleText, 0, 'Anfang', 0);
  Result.Add(cUnit1, SampleText, 6, 'Laden', 0);
  // Datei fehlt: nicht gefunden.
  Result.LoseFile(cUnit2);
end;

{ TAtlasBookmarkDialogTests }

procedure TAtlasBookmarkDialogTests.WarmUpFirstUse;
begin
  Setup;
  try
    ShowsSuggestionAndButtons;
  finally
    TearDown;
  end;
end;

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
  mDialog: TAtlasBookmarkDialog;
begin
  mDialog := TAtlasBookmarkDialog.CreateDialog(nil, 'Lesezeichen – Kunde.pas, Zeile 9', 'Laden: Pruefen;');
  try
    Assert.AreEqual('Lesezeichen – Kunde.pas, Zeile 9', mDialog.Caption);
    Assert.AreEqual('Name des Lesezeichens:', mDialog.Prompt.Caption);
    Assert.AreEqual('Laden: Pruefen;', mDialog.Edit.Text, 'Vorschlag');
    Assert.IsTrue(mDialog.Edit.AutoSelect, 'Vorschlag beim Öffnen markiert');
    Assert.IsTrue(mDialog.OkButton.Default, 'Enter setzt');
    Assert.IsTrue(mDialog.CancelButton.Cancel, 'Esc bricht ab');
    Assert.AreEqual('Setzen', mDialog.OkButton.Caption);
    Assert.IsTrue(mDialog.OkButton.Enabled);
    mDialog.Edit.Text := '  Prüfung  ';
    Assert.AreEqual('Prüfung', mDialog.BookmarkName);
    mDialog.OkButton.Click;
    Assert.AreEqual(Integer(mrOk), Integer(mDialog.ModalResult));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasBookmarkDialogTests.EmptyNameCannotBeSet;
var
  mDialog: TAtlasBookmarkDialog;
begin
  mDialog := TAtlasBookmarkDialog.CreateDialog(nil, 'Lesezeichen', 'Vorschlag');
  try
    mDialog.Edit.Text := '   ';
    Assert.IsFalse(mDialog.OkButton.Enabled, 'ohne Namen gesperrt');
    mDialog.OkButton.Click;
    Assert.AreEqual(Integer(mrNone), Integer(mDialog.ModalResult));
    mDialog.Edit.Text := 'A';
    Assert.IsTrue(mDialog.OkButton.Enabled);
    mDialog.CancelButton.Click;
    Assert.AreEqual(Integer(mrCancel), Integer(mDialog.ModalResult));
  finally
    mDialog.Free;
  end;
end;

{ TAtlasBookmarksFrameTests }

procedure TAtlasBookmarksFrameTests.WarmUpFirstUse;
begin
  Setup;
  try
    ShowsColumnsAndLostBookmarks;
  finally
    TearDown;
  end;
end;

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
  mHost: TForm;
  mFrame: TAtlasBookmarksFrame;
  mList: TAtlasBookmarkList;
begin
  mList := SampleList;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasBookmarksFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.SetBookmarks(mList, 'Projekt.dproj · lokal', mList.Bookmarks[2].Id);
    Assert.AreEqual(5, Integer(mFrame.List.Columns.Count), 'mit „Nr.“ (#1104)');
    Assert.AreEqual('Nr.', mFrame.List.Columns[TAtlasBookmarksFrame.cNumberColumn].Caption);
    Assert.AreEqual('', mFrame.List.Items[0].SubItems[3], 'benannte ohne Nummer: leer');
    Assert.AreEqual('Zeilenvorschau', mFrame.List.Columns[3].Caption);
    Assert.AreEqual(3, Integer(mFrame.List.Items.Count), 'Reihenfolge der Liste');
    Assert.AreEqual('Prüfung', mFrame.List.Items[0].Caption);
    Assert.AreEqual('Kunde.pas:9', mFrame.List.Items[0].SubItems[0]);
    Assert.AreEqual('TKunde.Laden', mFrame.List.Items[0].SubItems[1]);
    Assert.AreEqual('Pruefen;', mFrame.List.Items[0].SubItems[2]);
    Assert.AreEqual('nicht gefunden · unit Kunde;', mFrame.List.Items[1].SubItems[2]);
    Assert.AreEqual('Projekt.dproj · lokal', mFrame.PlaceLabel.Caption);
    Assert.IsFalse(mFrame.EmptyLabel.Visible);
    Assert.AreEqual(mList.Bookmarks[2].Id, mFrame.SelectedId, 'Auswahl nach Kennung');
    // Neu gefüllt ohne Kennung: Die Auswahl bleibt.
    mFrame.SetBookmarks(mList, 'x', '');
    Assert.AreEqual(mList.Bookmarks[2].Id, mFrame.SelectedId);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasBookmarksFrameTests.FilterNarrowsTheList;
var
  mHost: TForm;
  mFrame: TAtlasBookmarksFrame;
  mList: TAtlasBookmarkList;
  mOpened: string;
  mKey: Word;
begin
  mList := SampleList;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasBookmarksFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.OnOpen :=
      procedure(AId: string)
      begin
        mOpened := AId;
      end;
    mFrame.SetBookmarks(mList, '', '');
    Assert.AreEqual('Filtern: Name, Datei, Methode oder Zeile', mFrame.Filter.TextHint);
    mFrame.Filter.Text := 'kunde laden';
    Assert.AreEqual(2, Integer(mFrame.List.Items.Count), 'Datei und Methode zählen');
    mFrame.Filter.Text := 'lager';
    Assert.AreEqual(1, Integer(mFrame.List.Items.Count));
    Assert.AreEqual('Anfang', mFrame.List.Items[0].Caption);
    // Enter im Filterfeld springt zum ersten Treffer.
    mKey := VK_RETURN;
    mFrame.Filter.OnKeyDown(mFrame.Filter, mKey, []);
    Assert.AreEqual(mList.Bookmarks[1].Id, mOpened);
    mFrame.Filter.Text := 'gibtsnicht';
    Assert.AreEqual(0, Integer(mFrame.List.Items.Count));
    Assert.IsFalse(mFrame.EmptyLabel.Visible, 'Filter ohne Treffer ist kein leeres Projekt');
    mFrame.Filter.Text := '';
    Assert.AreEqual(3, Integer(mFrame.List.Items.Count));
  finally
    mHost.Free;
  end;
end;

procedure TAtlasBookmarksFrameTests.KeysOpenRenameAndDelete;
var
  mHost: TForm;
  mFrame: TAtlasBookmarksFrame;
  mList: TAtlasBookmarkList;
  mOpened, mDeleted: string;
  mKey: Word;
  mAllow: Boolean;
begin
  mList := SampleList;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasBookmarksFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.OnOpen :=
      procedure(AId: string)
      begin
        mOpened := AId;
      end;
    mFrame.OnDelete :=
      procedure(AId: string)
      begin
        mDeleted := AId;
      end;
    mFrame.SetBookmarks(mList, '', mList.Bookmarks[1].Id);
    mKey := VK_RETURN;
    mFrame.List.OnKeyDown(mFrame.List, mKey, []);
    Assert.AreEqual(mList.Bookmarks[1].Id, mOpened, 'Enter springt, auch zu einem nicht gefundenen');
    mKey := VK_DELETE;
    mFrame.List.OnKeyDown(mFrame.List, mKey, []);
    Assert.AreEqual(mList.Bookmarks[1].Id, mDeleted, 'Entf löscht');
    Assert.AreEqual(0, Integer(mKey));
    // Ein zweiter Klick startet keine Namensbearbeitung; nur F2 bzw. „Umbenennen“.
    mAllow := True;
    mFrame.List.OnEditing(mFrame.List, mFrame.List.Items[0], mAllow);
    Assert.IsFalse(mAllow);
    // Kontextmenü: Springen, Umbenennen, Löschen.
    mFrame.Menu.OnPopup(mFrame.Menu);
    Assert.AreEqual(3, Integer(mFrame.Menu.Items.Count));
    Assert.IsTrue(mFrame.Menu.Items[1].Enabled);
    Assert.AreEqual('Umbenennen', mFrame.Menu.Items[1].Caption);
    mOpened := '';
    mFrame.Menu.Items[0].Click;
    Assert.AreEqual(mList.Bookmarks[1].Id, mOpened);
    // Klick auf die freie Fläche springt nicht.
    mOpened := '';
    mFrame.List.OnMouseDown(mFrame.List, TMouseButton.mbLeft, [], 1, mFrame.List.ClientHeight - 1);
    mFrame.List.OnClick(mFrame.List);
    Assert.AreEqual('', mOpened);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasBookmarksFrameTests.RenameIgnoresEmptyName;
var
  mHost: TForm;
  mFrame: TAtlasBookmarksFrame;
  mList: TAtlasBookmarkList;
  mRenamedId, mRenamedTo, S: string;
begin
  mList := SampleList;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasBookmarksFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.OnRename :=
      procedure(AId, AName: string)
      begin
        mRenamedId := AId;
        mRenamedTo := AName;
      end;
    mFrame.SetBookmarks(mList, '', '');
    S := '  Neuer Name ';
    mFrame.List.OnEdited(mFrame.List, mFrame.List.Items[2], S);
    Assert.AreEqual(mList.Bookmarks[2].Id, mRenamedId);
    Assert.AreEqual('Neuer Name', mRenamedTo);
    Assert.AreEqual('Neuer Name', S);
    mRenamedId := '';
    S := '   ';
    mFrame.List.OnEdited(mFrame.List, mFrame.List.Items[0], S);
    Assert.AreEqual('', mRenamedId, 'leer bleibt beim alten Namen');
    Assert.AreEqual('Prüfung', S);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasBookmarksFrameTests.MovesWithKeysAndDrop;
var
  mHost: TForm;
  mFrame: TAtlasBookmarksFrame;
  mList: TAtlasBookmarkList;
  mMoved, mBefore: string;
  mKey: Word;
begin
  mList := SampleList;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasBookmarksFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.OnMove :=
      procedure(AId, ABeforeId: string)
      begin
        mMoved := AId;
        mBefore := ABeforeId;
      end;
    mFrame.SetBookmarks(mList, '', mList.Bookmarks[0].Id);
    // Strg+↓: hinter den nächsten, also vor den übernächsten.
    mKey := VK_DOWN;
    mFrame.List.OnKeyDown(mFrame.List, mKey, [ssCtrl]);
    Assert.AreEqual(mList.Bookmarks[0].Id, mMoved);
    Assert.AreEqual(mList.Bookmarks[2].Id, mBefore);
    // Strg+↑ ganz oben: nichts.
    mMoved := '';
    mKey := VK_UP;
    mFrame.List.OnKeyDown(mFrame.List, mKey, [ssCtrl]);
    Assert.AreEqual('', mMoved);
    // Unterstes nach unten: nichts; nach oben: vor das mittlere.
    mFrame.SetBookmarks(mList, '', mList.Bookmarks[2].Id);
    mKey := VK_DOWN;
    mFrame.List.OnKeyDown(mFrame.List, mKey, [ssCtrl]);
    Assert.AreEqual('', mMoved);
    mKey := VK_UP;
    mFrame.List.OnKeyDown(mFrame.List, mKey, [ssCtrl]);
    Assert.AreEqual(mList.Bookmarks[2].Id, mMoved);
    Assert.AreEqual(mList.Bookmarks[1].Id, mBefore);
    // Ziehen: Drop meldet Kennung und Ziel; auf sich selbst nichts.
    mFrame.Drop(mList.Bookmarks[1].Id, '');
    Assert.AreEqual(mList.Bookmarks[1].Id, mMoved);
    Assert.AreEqual('', mBefore);
    mMoved := '';
    mFrame.Drop(mList.Bookmarks[1].Id, mList.Bookmarks[1].Id);
    Assert.AreEqual('', mMoved);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasBookmarksFrameTests.EmptyListShowsHint;
var
  mHost: TForm;
  mFrame: TAtlasBookmarksFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasBookmarksFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.SetBookmarks(TAtlasBookmarkList.Create(cProject), 'Kein Projekt geöffnet.', '');
    Assert.IsTrue(mFrame.EmptyLabel.Visible);
    Assert.IsFalse(mFrame.List.Visible);
    // TCaption ist ein eigener Typ ohne String-Helfer.
    Assert.IsTrue(string(mFrame.EmptyLabel.Caption).StartsWith('Noch keine Lesezeichen'));
    Assert.AreEqual('', mFrame.SelectedId);
    mFrame.SetBookmarks(SampleList, '', '');
    Assert.IsFalse(mFrame.EmptyLabel.Visible);
    Assert.IsTrue(mFrame.List.Visible);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasBookmarksFrameTests.QuickBookmarksInWindow;
var
  mHost: TForm;
  mFrame: TAtlasBookmarksFrame;
  mList: TAtlasBookmarkList;
  mNumberedId: string;
  mNumberedTo: Integer;
  mKey: Word;
begin
  mList := SampleList;
  TAtlasQuickBookmarks.SetNumber(mList, cUnit1, SampleText, 8, 3, 0);
  TAtlasQuickBookmarks.Toggle(mList, cUnit2, SampleText, 0, 0);
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasBookmarksFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.OnNumber :=
      procedure(AId: string; ANumber: Integer)
      begin
        mNumberedId := AId;
        mNumberedTo := ANumber;
      end;
    mFrame.SetBookmarks(mList, '', mList.Bookmarks[3].Id);
    Assert.AreEqual(5, Integer(mFrame.List.Items.Count));
    Assert.AreEqual('Laden', mFrame.List.Items[3].Caption, 'ohne Namen die Methode');
    Assert.AreEqual('3', mFrame.List.Items[3].SubItems[3]);
    Assert.AreEqual(cAtlasQuickBookmarkDot, mFrame.List.Items[4].SubItems[3], 'unnummeriert');
    Assert.AreEqual('Lager.pas:1', mFrame.List.Items[4].Caption, 'außerhalb einer Methode Datei und Zeile');
    // Nur diese Datei: Kunde.pas.
    mFrame.SetCurrentFile(cUnit1);
    Assert.AreEqual(5, Integer(mFrame.List.Items.Count), 'Schalter aus: alle');
    mFrame.OnlyFileCheck.Checked := True;
    Assert.AreEqual(3, Integer(mFrame.List.Items.Count));
    mFrame.SetCurrentFile(cUnit2);
    Assert.AreEqual(2, Integer(mFrame.List.Items.Count));
    mFrame.OnlyFileCheck.Checked := False;
    // Strg+Umschalt+5 vergibt die Nummer.
    mFrame.SetBookmarks(mList, '', mList.Bookmarks[0].Id);
    mKey := Ord('5');
    mFrame.List.OnKeyDown(mFrame.List, mKey, [ssCtrl, ssShift]);
    Assert.AreEqual(mList.Bookmarks[0].Id, mNumberedId);
    Assert.AreEqual(5, mNumberedTo);
    Assert.AreEqual(0, Integer(mKey));
    mNumberedId := '';
    mKey := Ord('5');
    mFrame.List.OnKeyDown(mFrame.List, mKey, [ssCtrl]);
    Assert.AreEqual('', mNumberedId, 'nur mit Strg+Umschalt');
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBookmarkDialogTests);
  TDUnitX.RegisterTestFixture(TAtlasBookmarksFrameTests);

end.
