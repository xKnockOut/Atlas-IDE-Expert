unit Atlas.UI.Editor.Unwrap.Tests;

// Umschließung entfernen (#657), Fensterteil: Bezeichnungen der Einträge und
// Hinweise, Wahl über Tasten (nicht übernehmbare werden übersprungen) mit
// Meldung für die Vorschau, Kurzform bei nur einem Eintrag, Übernehmen und
// Abbrechen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasUnwrapWindowTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure CaptionsAndNotes;
    [Test]
    procedure KeysSkipUnavailableAndReport;
    [Test]
    procedure SingleEntryIsCompact;
    [Test]
    procedure AcceptAndCancel;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Style.Palette,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.Unwrap,
  Atlas.UI.Strings,
  Atlas.UI.Editor.Unwrap;

function Entry(const AKind, AVariant: string; AVariants: Integer; AAvailable: Boolean): TAtlasUnwrapEntry;
var
  mEdit: TLspTextEdit;
begin
  Result := Default(TAtlasUnwrapEntry);
  Result.Kind := AKind;
  Result.VariantKind := AVariant;
  Result.VariantCount := AVariants;
  Result.Line := 4;
  if AAvailable then
  begin
    mEdit := Default(TLspTextEdit);
    mEdit.NewText := 'X;';
    Result.Edits := [mEdit];
  end;
end;

function Sample: TArray<TAtlasUnwrapEntry>;
var
  mUnresolved: TAtlasUnwrapEntry;
begin
  mUnresolved := Entry('withDo', '', 0, False);
  mUnresolved.Note := 'withUnresolved';
  mUnresolved.NoteText := 'Caption';
  Result := [mUnresolved, Entry('tryFinally', 'keepFinally', 2, True), Entry('tryFinally', 'dropFinally', 2, True)];
end;

function NewWindow: TAtlasUnwrapWindow;
begin
  Result := TAtlasUnwrapWindow.Create(nil);
  Result.Colors := TAtlasColors.Light;
  Result.SetScaling(96, 1, 'Segoe UI', 9);
end;

procedure TAtlasUnwrapWindowTests.WarmUpFirstUse;
begin
  CaptionsAndNotes;
  // Auch das erste Zeigen eines Fensters samt Ereignis (Erstgebrauch der VCL).
  KeysSkipUnavailableAndReport;
end;

procedure TAtlasUnwrapWindowTests.CaptionsAndNotes;
var
  mItem: TAtlasUnwrapEntry;
begin
  TAtlasStrings.Language := TAtlasLanguage.German;
  Assert.AreEqual('try … finally … end – finally-Teil behalten',
    TAtlasUnwrapWindow.EntryCaption(Entry('tryFinally', 'keepFinally', 2, True)));
  Assert.AreEqual('try … finally … end – finally-Teil verwerfen',
    TAtlasUnwrapWindow.EntryCaption(Entry('tryFinally', 'dropFinally', 2, True)));
  Assert.AreEqual('if … then', TAtlasUnwrapWindow.EntryCaption(Entry('ifThen', 'then', 1, True)));
  Assert.AreEqual('if … then … else – else-Zweig behalten',
    TAtlasUnwrapWindow.EntryCaption(Entry('ifThen', 'else', 2, True)));
  Assert.AreEqual('begin … end', TAtlasUnwrapWindow.EntryCaption(Entry('beginEnd', 'body', 1, True)));
  Assert.AreEqual('{$IFDEF} … {$ENDIF} – {$ELSE}-Zweig behalten',
    TAtlasUnwrapWindow.EntryCaption(Entry('ifdef', 'else', 2, True)));
  mItem := Entry('ifdef', 'branch', 3, True);
  mItem.Branch := 1;
  Assert.AreEqual('{$IFDEF} … {$ENDIF} – 2. Zweig behalten', TAtlasUnwrapWindow.EntryCaption(mItem));
  mItem := Entry('forDo', 'body', 1, True);
  mItem.Note := 'loopVariable';
  mItem.NoteText := 'I';
  Assert.AreEqual('Bezüge auf die Schleifenvariable I bleiben stehen.', TAtlasUnwrapWindow.EntryNote(mItem));
  mItem.Note := 'multipleRaise';
  mItem.NoteText := '2';
  Assert.AreEqual('Achtung: Der except-Teil enthält 2 raise.', TAtlasUnwrapWindow.EntryNote(mItem));
  mItem.Note := '';
  Assert.AreEqual('', TAtlasUnwrapWindow.EntryNote(mItem));
end;

procedure TAtlasUnwrapWindowTests.KeysSkipUnavailableAndReport;
var
  mWindow: TAtlasUnwrapWindow;
  mReported: Integer;
begin
  mReported := -1;
  mWindow := NewWindow;
  try
    mWindow.OnSelect :=
      procedure(AIndex: Integer)
      begin
        mReported := AIndex;
      end;
    mWindow.ShowFor(Sample, Point(100, 100));
    try
      Assert.IsFalse(mWindow.Compact);
      Assert.AreEqual(1, mWindow.Row, 'with ist nicht übernehmbar');
      Assert.AreEqual(1, mReported, 'Vorschau beim Öffnen');
      Assert.IsTrue(mWindow.MoveRow(1));
      Assert.AreEqual(2, mWindow.Row);
      Assert.AreEqual(2, mReported);
      Assert.IsTrue(mWindow.MoveRow(1));
      Assert.AreEqual(1, mWindow.Row, 'ringsum, ohne den with-Eintrag');
      mWindow.Select(0);
      Assert.AreEqual(1, mWindow.Row, 'nicht wählbar');
      Assert.IsFalse(mWindow.RowRect(2).IsEmpty);
      Assert.IsTrue(mWindow.RowRect(1).Top > mWindow.RowRect(0).Top, 'untereinander');
    finally
      mWindow.Dismiss;
    end;
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasUnwrapWindowTests.SingleEntryIsCompact;
var
  mWindow: TAtlasUnwrapWindow;
begin
  TAtlasStrings.Language := TAtlasLanguage.German;
  mWindow := NewWindow;
  try
    mWindow.ShowFor([Entry('whileDo', 'body', 1, True)], Point(100, 100));
    try
      Assert.IsTrue(mWindow.Compact);
      Assert.AreEqual(0, mWindow.Row);
      Assert.AreEqual('Umschließung entfernen: while … do', mWindow.Caption);
      Assert.IsTrue(mWindow.RowRect(0).IsEmpty, 'ohne Liste');
    finally
      mWindow.Dismiss;
    end;
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasUnwrapWindowTests.AcceptAndCancel;
var
  mWindow: TAtlasUnwrapWindow;
  mAccepted, mCancelled: Integer;
begin
  mAccepted := -1;
  mCancelled := 0;
  mWindow := NewWindow;
  try
    mWindow.OnAccept :=
      procedure(AIndex: Integer)
      begin
        mAccepted := AIndex;
      end;
    mWindow.OnCancel :=
      procedure
      begin
        Inc(mCancelled);
      end;
    mWindow.ShowFor(Sample, Point(100, 100));
    mWindow.MoveRow(1);
    mWindow.Accept;
    Assert.AreEqual(2, mAccepted);
    Assert.IsFalse(mWindow.IsShown);
    mWindow.ShowFor(Sample, Point(100, 100));
    mWindow.Cancel;
    Assert.AreEqual(1, mCancelled);
    Assert.IsFalse(mWindow.IsShown);
    // Nur nicht übernehmbare Einträge: Übernehmen tut nichts.
    mAccepted := -1;
    mWindow.ShowFor([Sample[0]], Point(100, 100));
    Assert.AreEqual(-1, mWindow.Row);
    mWindow.Accept;
    Assert.AreEqual(-1, mAccepted);
    mWindow.Dismiss;
  finally
    mWindow.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUnwrapWindowTests);

end.
