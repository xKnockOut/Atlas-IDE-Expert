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
  end;

  [TestFixture]
  TAtlasNoteTipTests = class
  public
    [Test]
    procedure MeasuresWrappedText;
    [Test]
    procedure SeveralNotesOnOneLine;
    /// <summary>#623: Links unter dem Text machen den Tooltip höher; ohne Zeichnen gibt es kein Klickziel.</summary>
    [Test]
    procedure LinksAddLines;
    /// <summary>#1281: Der Bereich des Textes ist beim Zeichnen so hoch wie gemessen (vorher zwei Pixel zu
    /// wenig, die letzte Zeile wurde unten abgeschnitten).</summary>
    [Test]
    procedure BodyAreaHoldsMeasuredText;
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
  Atlas.UI.Notes.Tip,
  Atlas.UI.Results.Frame;

const
  Unit1 = 'C:\Projekt\Kunde.pas';
  Unit2 = 'C:\Projekt\Auftrag.pas';

function SampleLines: TArray<string>;
begin
  Result := ['unit Kunde;', '', 'interface', '', 'type', '  TKunde = class', '    procedure Laden;', '  end;',
    '', 'implementation', '', 'end.'];
end;

function SampleBook: TAtlasNoteBook;
var
  Stamp: TDateTime;
begin
  Stamp := EncodeDate(2026, 10, 15);
  Result := TAtlasNoteBook.Create('C:\Projekt\Projekt.dproj');
  Result.Add(Unit1, SampleLines, 6, 'Laden prüfen' + #10 + 'zweite Zeile', Stamp);
  Result.Add(Unit1, SampleLines, 5, 'Klasse aufteilen', Stamp);
  Result.Add(Unit2, SampleLines, 2, 'Weg damit', Stamp);
  // Datei fehlt: verwaist.
  Result.OrphanFile(Unit2);
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
  Dialog: TAtlasNoteDialog;
begin
  Dialog := TAtlasNoteDialog.CreateDialog(nil, 'Notiz – Kunde.pas, Zeile 7', 'Erste' + #10 + 'Zweite', False);
  try
    Assert.AreEqual('Notiz – Kunde.pas, Zeile 7', Dialog.Caption);
    Assert.AreEqual(2, Integer(Dialog.Memo.Lines.Count), 'mehrzeilig');
    Assert.IsTrue(Dialog.Memo.WantReturns, 'Enter beginnt eine neue Zeile');
    Assert.IsTrue(Dialog.CancelButton.Cancel, 'Esc bricht ab');
    Dialog.Memo.Lines.Text := '  Eins' + #13#10 + 'Zwei  ' + #13#10#13#10;
    Dialog.Accept;
    Assert.IsTrue(Dialog.Choice = TAtlasNoteChoice.Save);
    Assert.AreEqual('Eins' + #10 + 'Zwei', Dialog.NoteText);
  finally
    Dialog.Free;
  end;
  Assert.AreEqual('a' + #10 + 'b' + #10 + 'c', TAtlasNoteDialog.CleanText(' a' + #13#10 + 'b' + #13 + 'c ' + #10));
end;

procedure TAtlasNoteDialogTests.DeleteOnlyForExistingNote;
var
  Dialog: TAtlasNoteDialog;
begin
  Dialog := TAtlasNoteDialog.CreateDialog(nil, 'Neu', '', False);
  try
    Assert.IsFalse(Dialog.DeleteButton.Visible, 'neue Notiz ohne „Löschen“');
  finally
    Dialog.Free;
  end;
  Dialog := TAtlasNoteDialog.CreateDialog(nil, 'Alt', 'Text', True);
  try
    Assert.IsTrue(Dialog.DeleteButton.Visible);
    Assert.AreEqual('Löschen', Dialog.DeleteButton.Caption);
    Assert.AreEqual('Speichern', Dialog.SaveButton.Caption);
    Dialog.DeleteButton.Click;
    Assert.IsTrue(Dialog.Choice = TAtlasNoteChoice.Delete);
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasNoteDialogTests.EmptyTextDeletesOrCancels;
var
  Dialog: TAtlasNoteDialog;
begin
  Dialog := TAtlasNoteDialog.CreateDialog(nil, 'Alt', 'Text', True);
  try
    Dialog.Memo.Lines.Text := '   ';
    Dialog.SaveButton.Click;
    Assert.IsTrue(Dialog.Choice = TAtlasNoteChoice.Delete, 'leerer Text löscht die vorhandene Notiz');
  finally
    Dialog.Free;
  end;
  Dialog := TAtlasNoteDialog.CreateDialog(nil, 'Neu', '', False);
  try
    Dialog.SaveButton.Click;
    Assert.IsTrue(Dialog.Choice = TAtlasNoteChoice.Cancel, 'ohne Text keine neue Notiz');
    Dialog.CancelButton.Click;
    Assert.IsTrue(Dialog.Choice = TAtlasNoteChoice.Cancel);
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasNoteDialogTests.CtrlEnterSaves;
var
  Dialog: TAtlasNoteDialog;
  Key: Word;
  Ch: Char;
begin
  Dialog := TAtlasNoteDialog.CreateDialog(nil, 'Neu', '', False);
  try
    Dialog.Memo.Lines.Text := 'Merken';
    Key := VK_RETURN;
    Dialog.Memo.OnKeyDown(Dialog.Memo, Key, []);
    Assert.IsTrue(Dialog.Choice = TAtlasNoteChoice.Cancel, 'Enter allein speichert nicht');
    Assert.AreEqual(Integer(VK_RETURN), Integer(Key), 'Enter bleibt beim Textfeld');
    Dialog.Memo.OnKeyDown(Dialog.Memo, Key, [ssCtrl]);
    Assert.IsTrue(Dialog.Choice = TAtlasNoteChoice.Save);
    Assert.AreEqual(0, Integer(Key));
    Ch := #10;
    Dialog.Memo.OnKeyPress(Dialog.Memo, Ch);
    Assert.IsTrue(Ch = #0, 'kein Zeilenumbruch durch Strg+Enter');
  finally
    Dialog.Free;
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
  Host: TForm;
  Frame: TAtlasResultsFrame;
  Book: TAtlasNoteBook;
begin
  Book := SampleBook;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasResultsFrame.Create(Host);
    Frame.Parent := Host;
    Frame.ShowNotes('Notizen', Book.Groups);
    Assert.IsTrue(Frame.ShowsNotes);
    // Gruppe Kunde.pas mit zwei Notizen nach Zeile, dann „Verwaist (1)“.
    Assert.AreEqual(5, Integer(Frame.Tree.Items.Count));
    Assert.AreEqual('Kunde.pas (2)', Frame.Tree.Items[0].Text);
    Assert.AreEqual('6: Klasse aufteilen', Frame.Tree.Items[1].Text);
    Assert.AreEqual('7: Laden prüfen …', Frame.Tree.Items[2].Text, 'erste Zeile mit „…“');
    Assert.AreEqual('Verwaist (1)', Frame.Tree.Items[3].Text);
    Assert.AreEqual('Auftrag.pas, Zeile 3: Weg damit', Frame.Tree.Items[4].Text);
    Assert.IsTrue(Frame.Tree.Items[0].Expanded);
    // Auswahl nach Kennung.
    Frame.ShowNotes('Notizen', Book.Groups, Book.Notes[0].Id);
    Assert.AreEqual(Book.Notes[0].Id, Frame.SelectedNoteId);
    Assert.IsTrue(Frame.Tree.Selected = Frame.Tree.Items[2]);
  finally
    Host.Free;
  end;
end;

procedure TAtlasNotesListTests.MenuEditsDeletesAndOpens;
var
  Host: TForm;
  Frame: TAtlasResultsFrame;
  Book: TAtlasNoteBook;
  Edited, Deleted, Opened: string;
  OpenedLine: Integer;
  Key: Word;
begin
  Book := SampleBook;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasResultsFrame.Create(Host);
    Frame.Parent := Host;
    Frame.OnNoteEdit :=
      procedure(const AId: string)
      begin
        Edited := AId;
      end;
    Frame.OnNoteDelete :=
      procedure(const AId: string)
      begin
        Deleted := AId;
      end;
    Frame.OnOpen :=
      procedure(const AFileName: string; ALine, ACharacter: Integer)
      begin
        Opened := AFileName;
        OpenedLine := ALine;
      end;
    Frame.ShowNotes('Notizen', Book.Groups);
    // Gruppe gewählt: Einträge sichtbar, aber gesperrt; Änderungsbefehle (#721) unsichtbar.
    Frame.Menu.OnPopup(Frame.Menu);
    Assert.IsFalse(Frame.Menu.Items[0].Visible);
    Assert.IsTrue(Frame.Menu.Items[3].Visible);
    Assert.IsFalse(Frame.Menu.Items[3].Enabled);
    Assert.AreEqual('Notiz bearbeiten…', Frame.Menu.Items[3].Caption);
    Frame.Tree.Selected := Frame.Tree.Items[1];
    Frame.Menu.OnPopup(Frame.Menu);
    Assert.IsTrue(Frame.Menu.Items[3].Enabled);
    Assert.IsTrue(Frame.Menu.Items[4].Enabled);
    Frame.Menu.Items[3].Click;
    Assert.AreEqual(Book.Notes[1].Id, Edited);
    Frame.Menu.Items[4].Click;
    Assert.AreEqual(Book.Notes[1].Id, Deleted);
    // Entf löscht, Enter springt (0-basierte Zeile).
    Deleted := '';
    Frame.Tree.Selected := Frame.Tree.Items[2];
    Key := VK_DELETE;
    Frame.Tree.OnKeyDown(Frame.Tree, Key, []);
    Assert.AreEqual(Book.Notes[0].Id, Deleted);
    Key := VK_RETURN;
    Frame.Tree.OnKeyDown(Frame.Tree, Key, []);
    Assert.AreEqual(Unit1, Opened);
    Assert.AreEqual(6, OpenedLine);
    // Verwaiste Notiz springt zur zuletzt bekannten Zeile.
    Frame.Tree.Selected := Frame.Tree.Items[4];
    Frame.Tree.OnDblClick(Frame.Tree);
    Assert.AreEqual(Unit2, Opened);
    Assert.AreEqual(2, OpenedLine);
  finally
    Host.Free;
  end;
end;

procedure TAtlasNotesListTests.OtherListsHideNoteMenu;
var
  Host: TForm;
  Frame: TAtlasResultsFrame;
  Book: TAtlasNoteBook;
  Deleted: string;
  Key: Word;
begin
  Book := SampleBook;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasResultsFrame.Create(Host);
    Frame.Parent := Host;
    Deleted := '';
    Frame.OnNoteDelete :=
      procedure(const AId: string)
      begin
        Deleted := AId;
      end;
    Frame.ShowNotes('Notizen', Book.Groups);
    Frame.ShowEntries('Referenzen', nil);
    Assert.IsFalse(Frame.ShowsNotes);
    Frame.Menu.OnPopup(Frame.Menu);
    Assert.IsFalse(Frame.Menu.Items[3].Visible);
    Assert.IsFalse(Frame.Menu.Items[4].Visible);
    Key := VK_DELETE;
    Frame.Tree.OnKeyDown(Frame.Tree, Key, []);
    Assert.AreEqual('', Deleted, 'Entf nur in der Notizliste');
  finally
    Host.Free;
  end;
end;

{ TAtlasNoteTipTests }

procedure TAtlasNoteTipTests.MeasuresWrappedText;
var
  Tip: TAtlasNoteTip;
  One, Two, Long: TSize;
begin
  Tip := TAtlasNoteTip.Create(nil);
  try
    Tip.Colors := TAtlasColors.Light;
    Tip.SetScaling(96, 1, 'Segoe UI', 9);
    One := Tip.Measure('Notiz vom 15.10.2026', 'Eine Zeile');
    Two := Tip.Measure('Notiz vom 15.10.2026', 'Eine Zeile' + #10 + 'Noch eine');
    Assert.IsTrue(Two.cy > One.cy, 'zweite Zeile macht den Tooltip höher');
    Assert.AreEqual('Eine Zeile' + #13#10 + 'Noch eine', Tip.Text);
    Long := Tip.Measure('Notiz', StringOfChar('x', 20) + ' ' + StringOfChar('y', 400));
    Assert.IsTrue(Long.cx <= TAtlasNoteTip.MaxWidth + 2 * TAtlasNoteTip.Padding, 'Breite begrenzt');
  finally
    Tip.Free;
  end;
end;

procedure TAtlasNoteTipTests.LinksAddLines;
var
  Tip: TAtlasNoteTip;
  Plain, Linked: TSize;
begin
  Tip := TAtlasNoteTip.Create(nil);
  try
    Tip.Colors := TAtlasColors.Light;
    Tip.SetScaling(96, 1, 'Segoe UI', 9);
    Plain := Tip.Measure('Rekursion über 2 Methoden', 'Speichern → Pruefen → Speichern');
    Linked := Tip.Measure('Rekursion über 2 Methoden', 'Speichern → Pruefen → Speichern',
      ['TFoo.Speichern', 'TFoo.Pruefen']);
    Assert.IsTrue(Linked.cy > Plain.cy, 'zwei Zeilen mehr');
    Assert.AreEqual(2, Integer(Length(Tip.Links)));
    Assert.AreEqual(-1, Tip.LinkAt(1, 1), 'noch nicht gezeichnet');
    Tip.Measure('Notiz', 'Text');
    Assert.AreEqual(0, Integer(Length(Tip.Links)), 'ohne Links wieder leer');
  finally
    Tip.Free;
  end;
end;

procedure TAtlasNoteTipTests.BodyAreaHoldsMeasuredText;
var
  Tip: TAtlasNoteTip;
  Size: TSize;
  Ppi: Integer;
begin
  Tip := TAtlasNoteTip.Create(nil);
  try
    Tip.Colors := TAtlasColors.Light;
    for Ppi in TArray<Integer>.Create(96, 144, 192) do
    begin
      Tip.SetScaling(Ppi, 1, 'Segoe UI', 9);
      Size := Tip.Measure('Lesezeichen 1', 'Klick setzt ein Lesezeichen' + #10 + 'Zweite Zeile mit Unterlängen gpy');
      Assert.IsTrue(Tip.BodyArea(Size).Height >= Tip.BodyHeight, Format('Text passt bei %d dpi', [Ppi]));
      Assert.IsTrue(Tip.BodyArea(Size).Width > 0, Format('Breite bei %d dpi', [Ppi]));
    end;
  finally
    Tip.Free;
  end;
end;

procedure TAtlasNoteTipTests.SeveralNotesOnOneLine;
var
  Book: TAtlasNoteBook;
  Notes: TArray<TAtlasNote>;
begin
  // Der Tooltip zeigt alle nicht verwaisten Notizen der Zeile (AtLine); verwaiste haben kein Symbol.
  Book := SampleBook;
  Book.Add(Unit1, SampleLines, 6, 'Noch eine', EncodeDate(2026, 10, 15));
  Notes := Book.AtLine(Unit1, 6);
  Assert.AreEqual(2, Integer(Length(Notes)));
  Assert.AreEqual(0, Integer(Length(Book.AtLine(Unit2, 2))), 'verwaiste Notizen ohne Symbol');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNoteDialogTests);
  TDUnitX.RegisterTestFixture(TAtlasNotesListTests);
  TDUnitX.RegisterTestFixture(TAtlasNoteTipTests);

end.
