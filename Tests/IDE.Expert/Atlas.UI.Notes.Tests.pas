unit Atlas.UI.Notes.Tests;

// Persönliche Notizen (#545), Oberfläche: Eingabedialog (Speichern, Löschen,
// leerer Text, Strg+Enter), Liste im Ergebnisfenster (Gruppen je Datei,
// verwaiste Notizen am Ende, Kontextmenü, Entf, Sprung) und Tooltip.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Bookmarks')]
  TAtlasNoteDialogTests = class
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
    procedure SavesTrimmedTextWithLineFeeds;
    [Test]
    procedure DeleteOnlyForExistingNote;
    [Test]
    procedure EmptyTextDeletesOrCancels;
    [Test]
    procedure CtrlEnterSaves;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Bookmarks')]
  TAtlasNotesListTests = class
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
    procedure ShowsGroupsAndOrphans;
    [Test]
    procedure MenuEditsDeletesAndOpens;
    [Test]
    procedure OtherListsHideNoteMenu;
    /// <summary>#1455: Nach ReleaseItems erreicht die Liste das Modul nicht mehr (Regel 3).</summary>
    [Test]
    procedure ReleasedListHasNoActions;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Bookmarks')]
  TAtlasNoteLineTests = class
  public
    [Test]
    procedure SeveralNotesOnOneLine;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Windows,
  Vcl.Forms,
  Vcl.ComCtrls,
  Atlas.Core.Style.Palette,
  Atlas.Core.Notes.Store,
  Atlas.UI.Notes.Dialog,
  Atlas.UI.Notes.List,
  Atlas.UI.Results.Frame;

const
  cUnit1 = 'C:\Projekt\Kunde.pas';
  cUnit2 = 'C:\Projekt\Auftrag.pas';

function SampleLines: TArray<string>;
begin
  Result := ['unit Kunde;', '', 'interface', '', 'type', '  TKunde = class', '    procedure Laden;', '  end;',
    '', 'implementation', '', 'end.'];
end;

function SampleBook: TAtlasNoteBook;
var
  mStamp: TDateTime;
begin
  mStamp := EncodeDate(2026, 10, 15);
  Result := TAtlasNoteBook.Create('C:\Projekt\Projekt.dproj');
  Result.Add(cUnit1, SampleLines, 6, 'Laden prüfen' + #10 + 'zweite Zeile', mStamp);
  Result.Add(cUnit1, SampleLines, 5, 'Klasse aufteilen', mStamp);
  Result.Add(cUnit2, SampleLines, 2, 'Weg damit', mStamp);
  // Datei fehlt: verwaist.
  Result.OrphanFile(cUnit2);
end;

{ TAtlasNoteDialogTests }

procedure TAtlasNoteDialogTests.WarmUpFirstUse;
begin
  Setup;
  try
    SavesTrimmedTextWithLineFeeds;
  finally
    TearDown;
  end;
end;

procedure TAtlasNoteDialogTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasNoteDialogTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasNoteDialogTests.SavesTrimmedTextWithLineFeeds;
var
  mDialog: TAtlasNoteDialog;
begin
  mDialog := TAtlasNoteDialog.CreateDialog(nil, 'Notiz – Kunde.pas, Zeile 7', 'Erste' + #10 + 'Zweite', False);
  try
    Assert.AreEqual('Notiz – Kunde.pas, Zeile 7', mDialog.Caption);
    Assert.AreEqual(2, Integer(mDialog.Memo.Lines.Count), 'mehrzeilig');
    Assert.IsTrue(mDialog.Memo.WantReturns, 'Enter beginnt eine neue Zeile');
    Assert.IsTrue(mDialog.CancelButton.Cancel, 'Esc bricht ab');
    mDialog.Memo.Lines.Text := '  Eins' + #13#10 + 'Zwei  ' + #13#10#13#10;
    mDialog.Accept;
    Assert.IsTrue(mDialog.Choice = TAtlasNoteChoice.Save);
    Assert.AreEqual('Eins' + #10 + 'Zwei', mDialog.NoteText);
  finally
    mDialog.Free;
  end;
  Assert.AreEqual('a' + #10 + 'b' + #10 + 'c', TAtlasNoteDialog.CleanText(' a' + #13#10 + 'b' + #13 + 'c ' + #10));
end;

procedure TAtlasNoteDialogTests.DeleteOnlyForExistingNote;
var
  mDialog: TAtlasNoteDialog;
begin
  mDialog := TAtlasNoteDialog.CreateDialog(nil, 'Neu', '', False);
  try
    Assert.IsFalse(mDialog.DeleteButton.Visible, 'neue Notiz ohne „Löschen“');
  finally
    mDialog.Free;
  end;
  mDialog := TAtlasNoteDialog.CreateDialog(nil, 'Alt', 'Text', True);
  try
    Assert.IsTrue(mDialog.DeleteButton.Visible);
    Assert.AreEqual('Löschen', mDialog.DeleteButton.Caption);
    Assert.AreEqual('Speichern', mDialog.SaveButton.Caption);
    mDialog.DeleteButton.Click;
    Assert.IsTrue(mDialog.Choice = TAtlasNoteChoice.Delete);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasNoteDialogTests.EmptyTextDeletesOrCancels;
var
  mDialog: TAtlasNoteDialog;
begin
  mDialog := TAtlasNoteDialog.CreateDialog(nil, 'Alt', 'Text', True);
  try
    mDialog.Memo.Lines.Text := '   ';
    mDialog.SaveButton.Click;
    Assert.IsTrue(mDialog.Choice = TAtlasNoteChoice.Delete, 'leerer Text löscht die vorhandene Notiz');
  finally
    mDialog.Free;
  end;
  mDialog := TAtlasNoteDialog.CreateDialog(nil, 'Neu', '', False);
  try
    mDialog.SaveButton.Click;
    Assert.IsTrue(mDialog.Choice = TAtlasNoteChoice.Cancel, 'ohne Text keine neue Notiz');
    mDialog.CancelButton.Click;
    Assert.IsTrue(mDialog.Choice = TAtlasNoteChoice.Cancel);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasNoteDialogTests.CtrlEnterSaves;
var
  mDialog: TAtlasNoteDialog;
  mKey: Word;
  mCh: Char;
begin
  mDialog := TAtlasNoteDialog.CreateDialog(nil, 'Neu', '', False);
  try
    mDialog.Memo.Lines.Text := 'Merken';
    mKey := VK_RETURN;
    mDialog.Memo.OnKeyDown(mDialog.Memo, mKey, []);
    Assert.IsTrue(mDialog.Choice = TAtlasNoteChoice.Cancel, 'Enter allein speichert nicht');
    Assert.AreEqual(Integer(VK_RETURN), Integer(mKey), 'Enter bleibt beim Textfeld');
    mDialog.Memo.OnKeyDown(mDialog.Memo, mKey, [ssCtrl]);
    Assert.IsTrue(mDialog.Choice = TAtlasNoteChoice.Save);
    Assert.AreEqual(0, Integer(mKey));
    mCh := #10;
    mDialog.Memo.OnKeyPress(mDialog.Memo, mCh);
    Assert.IsTrue(mCh = #0, 'kein Zeilenumbruch durch Strg+Enter');
  finally
    mDialog.Free;
  end;
end;

{ TAtlasNotesListTests }

procedure TAtlasNotesListTests.WarmUpFirstUse;
begin
  Setup;
  try
    ShowsGroupsAndOrphans;
  finally
    TearDown;
  end;
end;

procedure TAtlasNotesListTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasNotesListTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasNotesListTests.ShowsGroupsAndOrphans;
var
  mHost: TForm;
  mFrame: TAtlasResultsFrame;
  mBook: TAtlasNoteBook;
begin
  mBook := SampleBook;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasResultsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Items.Show(TAtlasNotesList.Build('Notizen', mBook.Groups, '', nil, nil));
    Assert.IsTrue(mFrame.Items.ShowsItemsOf(TAtlasNotesList.cOwner));
    Assert.IsFalse(mFrame.Items.ShowsItemsOf('andere'));
    // Gruppe Kunde.pas mit zwei Notizen nach Zeile, dann „Verwaist (1)“.
    Assert.AreEqual(5, Integer(mFrame.Tree.Items.Count));
    Assert.AreEqual('Kunde.pas (2)', mFrame.Tree.Items[0].Text);
    Assert.AreEqual('6: Klasse aufteilen', mFrame.Tree.Items[1].Text);
    Assert.AreEqual('7: Laden prüfen …', mFrame.Tree.Items[2].Text, 'erste Zeile mit „…“');
    Assert.AreEqual('Verwaist (1)', mFrame.Tree.Items[3].Text);
    Assert.AreEqual('Auftrag.pas, Zeile 3: Weg damit', mFrame.Tree.Items[4].Text);
    Assert.IsTrue(mFrame.Tree.Items[0].Expanded);
    // Auswahl nach Kennung.
    mFrame.Items.Show(TAtlasNotesList.Build('Notizen', mBook.Groups, mBook.Notes[0].Id, nil, nil));
    Assert.AreEqual(mBook.Notes[0].Id, mFrame.Items.SelectedId);
    Assert.IsTrue(mFrame.Tree.Selected = mFrame.Tree.Items[2]);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasNotesListTests.MenuEditsDeletesAndOpens;
var
  mHost: TForm;
  mFrame: TAtlasResultsFrame;
  mBook: TAtlasNoteBook;
  mEdited, mDeleted, mOpened: string;
  mOpenedLine: Integer;
  mKey: Word;
begin
  mBook := SampleBook;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasResultsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.OnOpen :=
      procedure(const AFileName: string; ALine, ACharacter: Integer)
      begin
        mOpened := AFileName;
        mOpenedLine := ALine;
      end;
    mFrame.Items.Show(TAtlasNotesList.Build('Notizen', mBook.Groups, '',
      procedure(const AId: string)
      begin
        mEdited := AId;
      end,
      procedure(const AId: string)
      begin
        mDeleted := AId;
      end));
    // Gruppe gewählt: Einträge sichtbar, aber gesperrt; Änderungsbefehle (#721) unsichtbar.
    mFrame.Menu.OnPopup(mFrame.Menu);
    Assert.IsFalse(mFrame.Menu.Items[0].Visible);
    Assert.IsTrue(mFrame.Menu.Items[3].Visible);
    Assert.IsFalse(mFrame.Menu.Items[3].Enabled);
    Assert.AreEqual('Notiz bearbeiten…', mFrame.Menu.Items[3].Caption);
    mFrame.Tree.Selected := mFrame.Tree.Items[1];
    mFrame.Menu.OnPopup(mFrame.Menu);
    Assert.IsTrue(mFrame.Menu.Items[3].Enabled);
    Assert.IsTrue(mFrame.Menu.Items[4].Enabled);
    mFrame.Menu.Items[3].Click;
    Assert.AreEqual(mBook.Notes[1].Id, mEdited);
    mFrame.Menu.Items[4].Click;
    Assert.AreEqual(mBook.Notes[1].Id, mDeleted);
    // Entf löscht, Enter springt (0-basierte Zeile).
    mDeleted := '';
    mFrame.Tree.Selected := mFrame.Tree.Items[2];
    mKey := VK_DELETE;
    mFrame.Tree.OnKeyDown(mFrame.Tree, mKey, []);
    Assert.AreEqual(mBook.Notes[0].Id, mDeleted);
    mKey := VK_RETURN;
    mFrame.Tree.OnKeyDown(mFrame.Tree, mKey, []);
    Assert.AreEqual(cUnit1, mOpened);
    Assert.AreEqual(6, mOpenedLine);
    // Verwaiste Notiz springt zur zuletzt bekannten Zeile.
    mFrame.Tree.Selected := mFrame.Tree.Items[4];
    mFrame.Tree.OnDblClick(mFrame.Tree);
    Assert.AreEqual(cUnit2, mOpened);
    Assert.AreEqual(2, mOpenedLine);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasNotesListTests.OtherListsHideNoteMenu;
var
  mHost: TForm;
  mFrame: TAtlasResultsFrame;
  mBook: TAtlasNoteBook;
  mDeleted: string;
  mKey: Word;
begin
  mBook := SampleBook;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasResultsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mDeleted := '';
    mFrame.Items.Show(TAtlasNotesList.Build('Notizen', mBook.Groups, '', nil,
      procedure(const AId: string)
      begin
        mDeleted := AId;
      end));
    mFrame.Entries.Show('Referenzen', nil);
    Assert.IsFalse(mFrame.Items.ShowsItemsOf(TAtlasNotesList.cOwner));
    mFrame.Menu.OnPopup(mFrame.Menu);
    Assert.IsFalse(mFrame.Menu.Items[3].Visible);
    Assert.IsFalse(mFrame.Menu.Items[4].Visible);
    mKey := VK_DELETE;
    mFrame.Tree.OnKeyDown(mFrame.Tree, mKey, []);
    Assert.AreEqual('', mDeleted, 'Entf nur in der Notizliste');
  finally
    mHost.Free;
  end;
end;

procedure TAtlasNotesListTests.ReleasedListHasNoActions;
var
  mHost: TForm;
  mFrame: TAtlasResultsFrame;
  mBook: TAtlasNoteBook;
  mDeleted: string;
  mKey: Word;
begin
  mBook := SampleBook;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasResultsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mDeleted := '';
    mFrame.Items.Show(TAtlasNotesList.Build('Notizen', mBook.Groups, '', nil,
      procedure(const AId: string)
      begin
        mDeleted := AId;
      end));
    mFrame.Items.Release('andere');
    mFrame.Tree.Selected := mFrame.Tree.Items[1];
    mFrame.Menu.OnPopup(mFrame.Menu);
    Assert.IsTrue(mFrame.Menu.Items[4].Visible, 'fremder Besitzer gibt nichts frei');
    mFrame.Items.Release(TAtlasNotesList.cOwner);
    Assert.IsTrue(mFrame.Items.ShowsItemsOf(TAtlasNotesList.cOwner), 'Liste bleibt sichtbar');
    mFrame.Menu.OnPopup(mFrame.Menu);
    Assert.IsFalse(mFrame.Menu.Items[4].Visible, 'Löschen weg');
    mKey := VK_DELETE;
    mFrame.Tree.OnKeyDown(mFrame.Tree, mKey, []);
    Assert.AreEqual('', mDeleted);
  finally
    mHost.Free;
  end;
end;

{ TAtlasNoteLineTests }

procedure TAtlasNoteLineTests.SeveralNotesOnOneLine;
var
  mBook: TAtlasNoteBook;
  mNotes: TArray<TAtlasNote>;
begin
  // Der Tooltip zeigt alle nicht verwaisten Notizen der Zeile (AtLine); verwaiste haben kein Symbol.
  mBook := SampleBook;
  mBook.Add(cUnit1, SampleLines, 6, 'Noch eine', EncodeDate(2026, 10, 15));
  mNotes := mBook.AtLine(cUnit1, 6);
  Assert.AreEqual(2, Integer(Length(mNotes)));
  Assert.AreEqual(0, Integer(Length(mBook.AtLine(cUnit2, 2))), 'verwaiste Notizen ohne Symbol');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNoteDialogTests);
  TDUnitX.RegisterTestFixture(TAtlasNotesListTests);
  TDUnitX.RegisterTestFixture(TAtlasNoteLineTests);

end.
