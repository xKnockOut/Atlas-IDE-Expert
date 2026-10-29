unit Atlas.UI.Vcs.WorkingCopies.Tests;

// Tabelle „Arbeitskopien“ (#1292): Texte je Spalte (eingerückt, „· fest“,
// „wird ermittelt …“, „auf Klick“, „prüft …“), Zeilen erst mit Fenster,
// zeilenweise Aktualisierung, Kontextmenü je Zeile und die Ereignisse an die
// IDE-Schicht; Git ohne „Server prüfen“.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  TAtlasWorkingCopiesDialogTests = class
  private
    FLanguage: TAtlasLanguage;
    FCalls: TArray<string>;
    procedure Checked(Sender: TObject);
    procedure Updated(Sender: TObject; AIndex: Integer; AIgnoreExternals: Boolean);
    procedure Pinned(Sender: TObject; AIndex: Integer);
    procedure Opened(Sender: TObject; AIndex: Integer);
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CellsPerColumn;
    /// <summary>Zeilen kommen mit dem Fenster; SetRow füllt eine Zeile nach; Knöpfe erst mit Liste.</summary>
    [Test]
    procedure RowsFillOneByOne;
    /// <summary>Kontextmenü: festschreiben nur mit bekannter Revision ohne feste; Ereignisse mit Zeile.</summary>
    [Test]
    procedure MenuAndEventsFollowRow;
    [Test]
    procedure GitHasNoServerCheck;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.WorkingCopies,
  Atlas.UI.Vcs.WorkingCopies;

const
  cRoot = 'C:\Projekte\Kasse';

function SvnList: TAtlasVcsWorkingCopyList;
var
  mRow: TAtlasVcsWorkingCopyRow;
begin
  Result := TAtlasVcsWorkingCopyList.Empty;
  Result.Kind := TAtlasVcsKind.Svn;
  Result.Root := cRoot;
  Result.Outcome := TAtlasVcsOutcome.Ok;
  mRow := TAtlasVcsWorkingCopyRow.Make(TAtlasVcsWorkingCopyKind.Main, cRoot, '');
  mRow.RepositoryPath := 'Kasse/branches/KASSE-42';
  mRow.Revision := '48231';
  mRow.Changed := 2;
  mRow.Loaded := True;
  Result.Rows := Result.Rows + [mRow];
  mRow := TAtlasVcsWorkingCopyRow.Make(TAtlasVcsWorkingCopyKind.External, cRoot, 'Packages/Basis');
  mRow.RepositoryPath := 'Packages/Basis/trunk';
  mRow.Depth := 1;
  mRow.Changed := 0;
  mRow.ExternalIndex := 0;
  Result.Rows := Result.Rows + [mRow];
  mRow := TAtlasVcsWorkingCopyRow.Make(TAtlasVcsWorkingCopyKind.External, cRoot, 'Packages/Kunden');
  mRow.RepositoryPath := 'Packages/Kunden/trunk';
  mRow.Depth := 1;
  mRow.Fixed := True;
  mRow.FixedRevision := '4711';
  mRow.Changed := 0;
  mRow.ExternalIndex := 1;
  Result.Rows := Result.Rows + [mRow];
end;

{ TAtlasWorkingCopiesDialogTests }

procedure TAtlasWorkingCopiesDialogTests.WarmUpFirstUse;
begin
  Setup;
  try
    RowsFillOneByOne;
  finally
    TearDown;
  end;
end;

procedure TAtlasWorkingCopiesDialogTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
  FCalls := nil;
end;

procedure TAtlasWorkingCopiesDialogTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
  FCalls := nil;
end;

procedure TAtlasWorkingCopiesDialogTests.Checked(Sender: TObject);
begin
  FCalls := FCalls + ['check'];
end;

procedure TAtlasWorkingCopiesDialogTests.Updated(Sender: TObject; AIndex: Integer; AIgnoreExternals: Boolean);
begin
  FCalls := FCalls + [Format('update %d %s', [AIndex, BoolToStr(AIgnoreExternals, True)])];
end;

procedure TAtlasWorkingCopiesDialogTests.Pinned(Sender: TObject; AIndex: Integer);
begin
  FCalls := FCalls + [Format('pin %d', [AIndex])];
end;

procedure TAtlasWorkingCopiesDialogTests.Opened(Sender: TObject; AIndex: Integer);
begin
  FCalls := FCalls + [Format('open %d', [AIndex])];
end;

procedure TAtlasWorkingCopiesDialogTests.CellsPerColumn;
var
  mList: TAtlasVcsWorkingCopyList;
  mCells: TArray<string>;
  mRow: TAtlasVcsWorkingCopyRow;
begin
  mList := SvnList;
  mCells := TAtlasWorkingCopiesDialog.Cells(TAtlasVcsKind.Svn, mList.Rows[0], 'Kasse', False);
  Assert.AreEqual(Integer(TAtlasWorkingCopiesDialog.ColumnCount), Integer(Length(mCells)));
  Assert.AreEqual('Kasse', mCells[0]);
  Assert.AreEqual('^/Kasse/branches/KASSE-42', mCells[1]);
  Assert.AreEqual('r48231', mCells[2]);
  Assert.AreEqual('2', mCells[3]);
  Assert.AreEqual('auf Klick', mCells[4], 'nie von selbst');
  // External: eingerückt, Revision noch offen.
  mCells := TAtlasWorkingCopiesDialog.Cells(TAtlasVcsKind.Svn, mList.Rows[1], 'Kasse', False);
  Assert.AreEqual(#$2514' Packages\Basis', mCells[0]);
  Assert.AreEqual('wird ermittelt …', mCells[2]);
  Assert.AreEqual('prüft …', TAtlasWorkingCopiesDialog.Cells(TAtlasVcsKind.Svn, mList.Rows[1], 'Kasse', True)[4]);
  // Fest: Revision mit Zusatz; Neu auf dem Server als Zahl.
  mRow := mList.Rows[2];
  mRow.Loaded := True;
  mRow.Revision := '4711';
  mRow.Incoming := 3;
  mCells := TAtlasWorkingCopiesDialog.Cells(TAtlasVcsKind.Svn, mRow, 'Kasse', False);
  Assert.AreEqual('r4711 · fest', mCells[2]);
  Assert.AreEqual('3', mCells[4]);
  // Tiefer verschachtelt, fremdes Repository, Fehler beim Prüfen.
  mRow.Depth := 2;
  mRow.Url := 'https://svn.lieferant.de/k/trunk';
  mRow.Incoming := -1;
  mRow.Outcome := TAtlasVcsOutcome.LoginNeeded;
  mCells := TAtlasWorkingCopiesDialog.Cells(TAtlasVcsKind.Svn, mRow, 'Kasse', False);
  Assert.AreEqual('    '#$2514' Packages\Kunden', mCells[0]);
  Assert.AreEqual('anderes Repository: https://svn.lieferant.de/k/trunk', mCells[1]);
  Assert.AreEqual(AtlasVcsOutcomeName(TAtlasVcsOutcome.LoginNeeded), mCells[4]);
  mList := TAtlasVcsWorkingCopyList.Empty;
  mRow := Default(TAtlasVcsWorkingCopyRow);
  mCells := nil;
end;

procedure TAtlasWorkingCopiesDialogTests.RowsFillOneByOne;
var
  mDialog: TAtlasWorkingCopiesDialog;
  mList: TAtlasVcsWorkingCopyList;
  mRow: TAtlasVcsWorkingCopyRow;
begin
  mDialog := TAtlasWorkingCopiesDialog.CreateDialog(nil, 'Kasse');
  try
    Assert.AreEqual('Arbeitskopien – Kasse', mDialog.Caption);
    Assert.IsFalse(mDialog.UpdateAllButton.Enabled, 'ohne Liste');
    mDialog.HandleNeeded;
    mDialog.View.HandleNeeded;
    Assert.AreEqual(1, mDialog.View.Items.Count, 'wird ermittelt …');
    mList := SvnList;
    mDialog.SetList(mList);
    Assert.AreEqual(3, mDialog.View.Items.Count);
    Assert.AreEqual('wird ermittelt …', mDialog.View.Items[1].SubItems[1]);
    Assert.IsTrue(mDialog.UpdateAllButton.Enabled);
    Assert.AreEqual('Nur Kasse aktualisieren', mDialog.UpdateOnlyButton.Caption);
    Assert.IsTrue(mDialog.CheckButton.Visible);
    mRow := mList.Rows[1];
    mRow.Loaded := True;
    mRow.Revision := '48190';
    mDialog.SetRow(1, mRow);
    Assert.AreEqual('r48190', mDialog.View.Items[1].SubItems[1]);
    Assert.AreEqual('48190', mDialog.List.Rows[1].Revision);
    mDialog.SetChecking(1, True);
    Assert.AreEqual('prüft …', mDialog.View.Items[1].SubItems[3]);
    mDialog.SetBusy(True);
    Assert.IsFalse(mDialog.CheckButton.Enabled);
    mDialog.SetBusy(False);
    Assert.IsTrue(mDialog.CheckButton.Enabled);
  finally
    mDialog.Free;
  end;
  mList := TAtlasVcsWorkingCopyList.Empty;
  mRow := Default(TAtlasVcsWorkingCopyRow);
end;

procedure TAtlasWorkingCopiesDialogTests.MenuAndEventsFollowRow;
var
  mDialog: TAtlasWorkingCopiesDialog;
  mList: TAtlasVcsWorkingCopyList;
begin
  mDialog := TAtlasWorkingCopiesDialog.CreateDialog(nil, 'Kasse');
  try
    mDialog.OnCheckServer := Checked;
    mDialog.OnUpdate := Updated;
    mDialog.OnPin := Pinned;
    mDialog.OnOpenFolder := Opened;
    mDialog.HandleNeeded;
    mDialog.View.HandleNeeded;
    mList := SvnList;
    mList.Rows[1].Loaded := True;
    mList.Rows[1].Revision := '48190';
    mDialog.SetList(mList);
    // Basis: Revision bekannt, ohne feste Revision.
    mDialog.View.Items[1].Selected := True;
    mDialog.Menu.OnPopup(mDialog.Menu);
    Assert.IsTrue(mDialog.PinItem.Enabled);
    Assert.IsTrue(mDialog.UpdateOnlyItem.Visible);
    mDialog.PinItem.Click;
    mDialog.UpdateItem.Click;
    mDialog.UpdateOnlyItem.Click;
    mDialog.OpenItem.Click;
    // Kunden: fest, nichts festzuschreiben.
    mDialog.View.Items[2].Selected := True;
    mDialog.Menu.OnPopup(mDialog.Menu);
    Assert.IsFalse(mDialog.PinItem.Enabled);
    mDialog.CheckButton.Click;
    mDialog.UpdateAllButton.Click;
    mDialog.UpdateOnlyButton.Click;
    Assert.AreEqual(7, Integer(Length(FCalls)));
    Assert.AreEqual('pin 1', FCalls[0]);
    Assert.AreEqual('update 1 False', FCalls[1]);
    Assert.AreEqual('update 1 True', FCalls[2]);
    Assert.AreEqual('open 1', FCalls[3]);
    Assert.AreEqual('check', FCalls[4]);
    Assert.AreEqual('update 0 False', FCalls[5], 'samt Externals');
    Assert.AreEqual('update 0 True', FCalls[6], 'nur das Projekt');
    // Während eines Laufs keine weiteren.
    mDialog.SetBusy(True);
    mDialog.CheckButton.Click;
    mDialog.Menu.OnPopup(mDialog.Menu);
    Assert.IsFalse(mDialog.UpdateItem.Enabled);
    Assert.AreEqual(7, Integer(Length(FCalls)));
  finally
    mDialog.Free;
  end;
  mList := TAtlasVcsWorkingCopyList.Empty;
end;

procedure TAtlasWorkingCopiesDialogTests.GitHasNoServerCheck;
var
  mDialog: TAtlasWorkingCopiesDialog;
  mList: TAtlasVcsWorkingCopyList;
  mRow: TAtlasVcsWorkingCopyRow;
begin
  mList := TAtlasVcsWorkingCopyList.Empty;
  mList.Kind := TAtlasVcsKind.Git;
  mList.Root := cRoot;
  mList.Outcome := TAtlasVcsOutcome.Ok;
  mRow := TAtlasVcsWorkingCopyRow.Make(TAtlasVcsWorkingCopyKind.Main, cRoot, '');
  mRow.RepositoryPath := 'main';
  mRow.Revision := '1a2b3c4';
  mRow.Loaded := True;
  mList.Rows := [mRow];
  mRow := TAtlasVcsWorkingCopyRow.Make(TAtlasVcsWorkingCopyKind.Submodule, cRoot, 'Libs/Json');
  mRow.Revision := '9f8e7d6';
  mRow.Loaded := True;
  mRow.Depth := 1;
  mList.Rows := mList.Rows + [mRow];
  Assert.AreEqual('main', TAtlasWorkingCopiesDialog.Cells(TAtlasVcsKind.Git, mList.Rows[0], 'Kasse', False)[1]);
  Assert.AreEqual('9f8e7d6', TAtlasWorkingCopiesDialog.Cells(TAtlasVcsKind.Git, mRow, 'Kasse', False)[2]);
  Assert.AreEqual('', TAtlasWorkingCopiesDialog.Cells(TAtlasVcsKind.Git, mRow, 'Kasse', False)[4]);
  mDialog := TAtlasWorkingCopiesDialog.CreateDialog(nil, 'Kasse');
  try
    mDialog.HandleNeeded;
    mDialog.SetList(mList);
    Assert.IsFalse(mDialog.CheckButton.Visible);
    Assert.IsFalse(mDialog.UpdateOnlyButton.Visible);
    Assert.AreEqual('Pull', StringReplace(mDialog.UpdateAllButton.Caption, '&', '', [rfReplaceAll]));
  finally
    mDialog.Free;
  end;
  mList := TAtlasVcsWorkingCopyList.Empty;
  mRow := Default(TAtlasVcsWorkingCopyRow);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWorkingCopiesDialogTests);

end.
