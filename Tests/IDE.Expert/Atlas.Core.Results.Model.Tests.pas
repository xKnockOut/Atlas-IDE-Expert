unit Atlas.Core.Results.Model.Tests;

// Tests für die Daten des Ergebnisfensters (#400).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasResultsTests = class
  public
    [Test]
    procedure GroupsByFileAndSortsByPosition;
    [Test]
    procedure FillsLineTextReadingEachFileOnce;
    [Test]
    procedure PreviewsRenamedLines;
    [Test]
    procedure PreviewsFileOperationsFirst;
    [Test]
    procedure MapsSymbolKindsToBadges;
    /// <summary>Treffersicherheit (#1119): Filter, Zähler und nicht geänderte Stellen in der Vorschau.</summary>
    [Test]
    procedure RatesEntriesAndPreviewsUnchanged;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Results.Model;

procedure TAtlasResultsTests.GroupsByFileAndSortsByPosition;
var
  mGroups: TArray<TAtlasResultGroup>;
begin
  mGroups := TAtlasResults.Group([TAtlasResultEntry.Create('C:\P\Zahl.pas', 9, 1),
    TAtlasResultEntry.Create('C:\P\Kunde.pas', 5, 8), TAtlasResultEntry.Create('C:\P\Zahl.pas', 2, 4),
    TAtlasResultEntry.Create('c:\p\kunde.pas', 5, 2), TAtlasResultEntry.Create('C:\P\Kunde.dfm', 30, 6)]);
  Assert.AreEqual(3, Integer(Length(mGroups)));
  // Nach Dateiname: Formular vor Unit, Groß-/Kleinschreibung egal.
  Assert.AreEqual('Kunde.dfm (1)', mGroups[0].Caption);
  Assert.AreEqual('Kunde.pas (2)', mGroups[1].Caption);
  Assert.AreEqual(2, mGroups[1].Entries[0].Character);
  Assert.AreEqual(8, mGroups[1].Entries[1].Character);
  Assert.AreEqual(2, mGroups[2].Entries[0].Line);
  Assert.AreEqual(9, mGroups[2].Entries[1].Line);
  Assert.AreEqual(0, Integer(Length(TAtlasResults.Group(nil))));
end;

procedure TAtlasResultsTests.FillsLineTextReadingEachFileOnce;
var
  mEntries: TArray<TAtlasResultEntry>;
  mReads: Integer;
begin
  mReads := 0;
  mEntries := [TAtlasResultEntry.Create('A.pas', 1, 2), TAtlasResultEntry.Create('A.pas', 2, 0),
    TAtlasResultEntry.Create('A.pas', 7, 0)];
  TAtlasResults.FillText(mEntries,
    function(const AFileName: string): string
    begin
      Inc(mReads);
      Result := 'unit A;'#13#10'  Kunde.Laden;'#10#9'Kunde.Free;';
    end);
  Assert.AreEqual(1, mReads);
  Assert.AreEqual('Kunde.Laden;', mEntries[0].Text);
  Assert.AreEqual('Kunde.Free;', mEntries[1].Text);
  Assert.AreEqual('', mEntries[2].Text, 'Zeile außerhalb der Datei');
end;

function TextEdit(ALine, AStart, AEnd: Integer; const ANewText: string): TLspTextEdit;
begin
  Result := Default(TLspTextEdit);
  Result.StartPos.Line := ALine;
  Result.StartPos.Character := AStart;
  Result.EndPos.Line := ALine;
  Result.EndPos.Character := AEnd;
  Result.NewText := ANewText;
end;

procedure TAtlasResultsTests.PreviewsRenamedLines;
var
  mEdit: TLspWorkspaceEdit;
  mEntries: TArray<TAtlasResultEntry>;
begin
  mEdit := Default(TLspWorkspaceEdit);
  mEdit.Files := [Default(TLspFileEdits)];
  mEdit.Files[0].FileName := 'A.pas';
  // Zwei Stellen in derselben Zeile, eine weitere davor.
  mEdit.Files[0].Edits := [TextEdit(2, 11, 16, 'Kunde'), TextEdit(2, 2, 7, 'Kunde'), TextEdit(1, 4, 9, 'Kunde')];
  mEntries := TAtlasResults.RenamePreview(mEdit,
    function(const AFileName: string): string
    begin
      Result := 'var'#13#10'    Leser: TLeser;'#13#10'  Leser := Leser.Next;';
    end);
  Assert.AreEqual(2, Integer(Length(mEntries)), 'eine Zeile je geänderter Zeile');
  Assert.AreEqual(1, mEntries[0].Line);
  Assert.AreEqual('Leser: TLeser;', mEntries[0].Text);
  Assert.AreEqual('Kunde: TLeser;', mEntries[0].Detail);
  Assert.AreEqual(2, mEntries[1].Line);
  Assert.AreEqual(2, mEntries[1].Character);
  Assert.AreEqual('Kunde := Kunde.Next;', mEntries[1].Detail);
end;

procedure TAtlasResultsTests.RatesEntriesAndPreviewsUnchanged;
var
  mEdit: TLspWorkspaceEdit;
  mEntries: TArray<TAtlasResultEntry>;
begin
  mEntries := TArray<TAtlasResultEntry>.Create(TAtlasResultEntry.Create('A.pas', 1, 0),
    TAtlasResultEntry.Create('A.pas', 2, 0));
  mEntries[1].Confidence.Inferred := True;
  Assert.AreEqual(1, TAtlasResults.InferredCount(mEntries));
  Assert.AreEqual(1, Integer(Length(TAtlasResults.SureOnly(mEntries))));
  Assert.AreEqual(1, TAtlasResults.SureOnly(mEntries)[0].Line);
  mEdit := Default(TLspWorkspaceEdit);
  mEdit.Files := [Default(TLspFileEdits)];
  mEdit.Files[0].FileName := 'A.pas';
  mEdit.Files[0].Edits := [TextEdit(1, 4, 9, 'Kunde')];
  mEdit.Unchanged := [Default(TLspUnchangedPlace)];
  mEdit.Unchanged[0].FileName := 'A.pas';
  mEdit.Unchanged[0].Line := 2;
  mEdit.Unchanged[0].Character := 2;
  mEdit.Unchanged[0].Confidence.Inferred := True;
  mEdit.Unchanged[0].Confidence.Reason := 'interface';
  mEntries := TAtlasResults.RenamePreview(mEdit,
    function(const AFileName: string): string
    begin
      Result := 'var'#13#10'    Leser: TLeser;'#13#10'  I.Leser;';
    end);
  Assert.AreEqual(2, Integer(Length(mEntries)));
  Assert.IsFalse(mEntries[0].Confidence.Inferred);
  Assert.AreEqual('Kunde: TLeser;', mEntries[0].Detail);
  // Nicht geändert: ohne Vorschau, mit Zeilentext und Grund.
  Assert.IsTrue(mEntries[1].Confidence.Inferred);
  Assert.AreEqual('interface', mEntries[1].Confidence.Reason);
  Assert.AreEqual('I.Leser;', mEntries[1].Text);
  Assert.AreEqual('', mEntries[1].Detail);
end;

procedure TAtlasResultsTests.PreviewsFileOperationsFirst;
var
  mEdit: TLspWorkspaceEdit;
  mEntries: TArray<TAtlasResultEntry>;
begin
  // #721: Umbenennen, Anlegen und Löschen einer Datei stehen vor den Zeilen.
  mEdit := Default(TLspWorkspaceEdit);
  mEdit.Operations := [Default(TLspFileOperation), Default(TLspFileOperation), Default(TLspFileOperation)];
  mEdit.Operations[0].Kind := TLspFileOperationKind.Rename;
  mEdit.Operations[0].FileName := 'C:\P\Alt.pas';
  mEdit.Operations[0].NewFileName := 'C:\P\Neu.pas';
  mEdit.Operations[1].Kind := TLspFileOperationKind.Create;
  mEdit.Operations[1].FileName := 'C:\P\Mehr.pas';
  mEdit.Operations[2].Kind := TLspFileOperationKind.Delete;
  mEdit.Operations[2].FileName := 'C:\P\Weg.pas';
  mEdit.Files := [Default(TLspFileEdits)];
  mEdit.Files[0].FileName := 'C:\P\Neu.pas';
  mEdit.Files[0].Edits := [TextEdit(0, 5, 8, 'Neu')];
  mEntries := TAtlasResults.RenamePreview(mEdit,
    function(const AFileName: string): string
    begin
      Result := 'unit Alt;';
    end);
  Assert.AreEqual(4, Integer(Length(mEntries)));
  Assert.AreEqual('C:\P\Alt.pas', mEntries[0].FileName);
  Assert.AreEqual('Alt.pas', mEntries[0].Text);
  Assert.AreEqual('Neu.pas', mEntries[0].Detail);
  Assert.AreEqual('', mEntries[1].Text);
  Assert.AreEqual('Mehr.pas', mEntries[1].Detail);
  Assert.AreEqual('Weg.pas', mEntries[2].Text);
  Assert.AreEqual('', mEntries[2].Detail);
  Assert.AreEqual('unit Neu;', mEntries[3].Detail);
end;

procedure TAtlasResultsTests.MapsSymbolKindsToBadges;
begin
  Assert.AreEqual('ty', TAtlasResults.SymbolBadge(5), 'Klasse');
  Assert.AreEqual('fn', TAtlasResults.SymbolBadge(6), 'Methode');
  Assert.AreEqual('pr', TAtlasResults.SymbolBadge(7), 'Property');
  Assert.AreEqual('fd', TAtlasResults.SymbolBadge(8), 'Feld');
  Assert.AreEqual('un', TAtlasResults.SymbolBadge(2), 'Unit');
  Assert.AreEqual('kw', TAtlasResults.SymbolBadge(99));
  Assert.IsTrue(TAtlasResults.IsCallHierarchy(TAtlasHierarchyDirection.Outgoing));
  Assert.IsFalse(TAtlasResults.IsCallHierarchy(TAtlasHierarchyDirection.Subtypes));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasResultsTests);

end.
