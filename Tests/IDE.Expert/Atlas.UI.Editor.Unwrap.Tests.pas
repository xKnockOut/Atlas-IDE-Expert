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
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.Unwrap,
  Atlas.UI.Strings,
  Atlas.UI.Editor.Unwrap;

function Entry(const AKind, AVariant: string; AVariants: Integer; AAvailable: Boolean): TAtlasUnwrapEntry;
var
  Edit: TLspTextEdit;
begin
  Result := Default(TAtlasUnwrapEntry);
  Result.Kind := AKind;
  Result.VariantKind := AVariant;
  Result.VariantCount := AVariants;
  Result.Line := 4;
  if AAvailable then
  begin
    Edit := Default(TLspTextEdit);
    Edit.NewText := 'X;';
    Result.Edits := [Edit];
  end;
end;

function Sample: TArray<TAtlasUnwrapEntry>;
var
  Unresolved: TAtlasUnwrapEntry;
begin
  Unresolved := Entry('withDo', '', 0, False);
  Unresolved.Note := 'withUnresolved';
  Unresolved.NoteText := 'Caption';
  Result := [Unresolved, Entry('tryFinally', 'keepFinally', 2, True), Entry('tryFinally', 'dropFinally', 2, True)];
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
end;

procedure TAtlasUnwrapWindowTests.CaptionsAndNotes;
var
  Item: TAtlasUnwrapEntry;
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
  Item := Entry('ifdef', 'branch', 3, True);
  Item.Branch := 1;
  Assert.AreEqual('{$IFDEF} … {$ENDIF} – 2. Zweig behalten', TAtlasUnwrapWindow.EntryCaption(Item));
  Item := Entry('forDo', 'body', 1, True);
  Item.Note := 'loopVariable';
  Item.NoteText := 'I';
  Assert.AreEqual('Bezüge auf die Schleifenvariable I bleiben stehen.', TAtlasUnwrapWindow.EntryNote(Item));
  Item.Note := 'multipleRaise';
  Item.NoteText := '2';
  Assert.AreEqual('Achtung: Der except-Teil enthält 2 raise.', TAtlasUnwrapWindow.EntryNote(Item));
  Item.Note := '';
  Assert.AreEqual('', TAtlasUnwrapWindow.EntryNote(Item));
end;

procedure TAtlasUnwrapWindowTests.KeysSkipUnavailableAndReport;
var
  Window: TAtlasUnwrapWindow;
  Reported: Integer;
begin
  Reported := -1;
  Window := NewWindow;
  try
    Window.OnSelect :=
      procedure(AIndex: Integer)
      begin
        Reported := AIndex;
      end;
    Window.ShowFor(Sample, Point(100, 100));
    try
      Assert.IsFalse(Window.Compact);
      Assert.AreEqual(1, Window.Row, 'with ist nicht übernehmbar');
      Assert.AreEqual(1, Reported, 'Vorschau beim Öffnen');
      Assert.IsTrue(Window.MoveRow(1));
      Assert.AreEqual(2, Window.Row);
      Assert.AreEqual(2, Reported);
      Assert.IsTrue(Window.MoveRow(1));
      Assert.AreEqual(1, Window.Row, 'ringsum, ohne den with-Eintrag');
      Window.Select(0);
      Assert.AreEqual(1, Window.Row, 'nicht wählbar');
      Assert.IsFalse(Window.RowRect(2).IsEmpty);
      Assert.IsTrue(Window.RowRect(1).Top > Window.RowRect(0).Top, 'untereinander');
    finally
      Window.Dismiss;
    end;
  finally
    Window.Free;
  end;
end;

procedure TAtlasUnwrapWindowTests.SingleEntryIsCompact;
var
  Window: TAtlasUnwrapWindow;
begin
  TAtlasStrings.Language := TAtlasLanguage.German;
  Window := NewWindow;
  try
    Window.ShowFor([Entry('whileDo', 'body', 1, True)], Point(100, 100));
    try
      Assert.IsTrue(Window.Compact);
      Assert.AreEqual(0, Window.Row);
      Assert.AreEqual('Umschließung entfernen: while … do', Window.Caption);
      Assert.IsTrue(Window.RowRect(0).IsEmpty, 'ohne Liste');
    finally
      Window.Dismiss;
    end;
  finally
    Window.Free;
  end;
end;

procedure TAtlasUnwrapWindowTests.AcceptAndCancel;
var
  Window: TAtlasUnwrapWindow;
  Accepted, Cancelled: Integer;
begin
  Accepted := -1;
  Cancelled := 0;
  Window := NewWindow;
  try
    Window.OnAccept :=
      procedure(AIndex: Integer)
      begin
        Accepted := AIndex;
      end;
    Window.OnCancel :=
      procedure
      begin
        Inc(Cancelled);
      end;
    Window.ShowFor(Sample, Point(100, 100));
    Window.MoveRow(1);
    Window.Accept;
    Assert.AreEqual(2, Accepted);
    Assert.IsFalse(Window.IsShown);
    Window.ShowFor(Sample, Point(100, 100));
    Window.Cancel;
    Assert.AreEqual(1, Cancelled);
    Assert.IsFalse(Window.IsShown);
    // Nur nicht übernehmbare Einträge: Übernehmen tut nichts.
    Accepted := -1;
    Window.ShowFor([Sample[0]], Point(100, 100));
    Assert.AreEqual(-1, Window.Row);
    Window.Accept;
    Assert.AreEqual(-1, Accepted);
    Window.Dismiss;
  finally
    Window.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUnwrapWindowTests);

end.
