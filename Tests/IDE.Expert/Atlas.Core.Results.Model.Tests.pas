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
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Results.Model;

procedure TAtlasResultsTests.GroupsByFileAndSortsByPosition;
var
  Groups: TArray<TAtlasResultGroup>;
begin
  Groups := TAtlasResults.Group([TAtlasResultEntry.Create('C:\P\Zahl.pas', 9, 1),
    TAtlasResultEntry.Create('C:\P\Kunde.pas', 5, 8), TAtlasResultEntry.Create('C:\P\Zahl.pas', 2, 4),
    TAtlasResultEntry.Create('c:\p\kunde.pas', 5, 2), TAtlasResultEntry.Create('C:\P\Kunde.dfm', 30, 6)]);
  Assert.AreEqual(3, Integer(Length(Groups)));
  // Nach Dateiname: Formular vor Unit, Groß-/Kleinschreibung egal.
  Assert.AreEqual('Kunde.dfm (1)', Groups[0].Caption);
  Assert.AreEqual('Kunde.pas (2)', Groups[1].Caption);
  Assert.AreEqual(2, Groups[1].Entries[0].Character);
  Assert.AreEqual(8, Groups[1].Entries[1].Character);
  Assert.AreEqual(2, Groups[2].Entries[0].Line);
  Assert.AreEqual(9, Groups[2].Entries[1].Line);
  Assert.AreEqual(0, Integer(Length(TAtlasResults.Group(nil))));
end;

procedure TAtlasResultsTests.FillsLineTextReadingEachFileOnce;
var
  Entries: TArray<TAtlasResultEntry>;
  Reads: Integer;
begin
  Reads := 0;
  Entries := [TAtlasResultEntry.Create('A.pas', 1, 2), TAtlasResultEntry.Create('A.pas', 2, 0),
    TAtlasResultEntry.Create('A.pas', 7, 0)];
  TAtlasResults.FillText(Entries,
    function(const AFileName: string): string
    begin
      Inc(Reads);
      Result := 'unit A;'#13#10'  Kunde.Laden;'#10#9'Kunde.Free;';
    end);
  Assert.AreEqual(1, Reads);
  Assert.AreEqual('Kunde.Laden;', Entries[0].Text);
  Assert.AreEqual('Kunde.Free;', Entries[1].Text);
  Assert.AreEqual('', Entries[2].Text, 'Zeile außerhalb der Datei');
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
  Edit: TLspWorkspaceEdit;
  Entries: TArray<TAtlasResultEntry>;
begin
  Edit := Default(TLspWorkspaceEdit);
  Edit.Files := [Default(TLspFileEdits)];
  Edit.Files[0].FileName := 'A.pas';
  // Zwei Stellen in derselben Zeile, eine weitere davor.
  Edit.Files[0].Edits := [TextEdit(2, 12, 17, 'Kunde'), TextEdit(2, 2, 7, 'Kunde'), TextEdit(1, 4, 9, 'Kunde')];
  Entries := TAtlasResults.RenamePreview(Edit,
    function(const AFileName: string): string
    begin
      Result := 'var'#13#10'    Leser: TLeser;'#13#10'  Leser := Leser.Next;';
    end);
  Assert.AreEqual(2, Integer(Length(Entries)), 'eine Zeile je geänderter Zeile');
  Assert.AreEqual(1, Entries[0].Line);
  Assert.AreEqual('Leser: TLeser;', Entries[0].Text);
  Assert.AreEqual('Kunde: TLeser;', Entries[0].Detail);
  Assert.AreEqual(2, Entries[1].Line);
  Assert.AreEqual(2, Entries[1].Character);
  Assert.AreEqual('Kunde := Kunde.Next;', Entries[1].Detail);
end;

procedure TAtlasResultsTests.PreviewsFileOperationsFirst;
var
  Edit: TLspWorkspaceEdit;
  Entries: TArray<TAtlasResultEntry>;
begin
  // #721: Umbenennen, Anlegen und Löschen einer Datei stehen vor den Zeilen.
  Edit := Default(TLspWorkspaceEdit);
  Edit.Operations := [Default(TLspFileOperation), Default(TLspFileOperation), Default(TLspFileOperation)];
  Edit.Operations[0].Kind := TLspFileOperationKind.Rename;
  Edit.Operations[0].FileName := 'C:\P\Alt.pas';
  Edit.Operations[0].NewFileName := 'C:\P\Neu.pas';
  Edit.Operations[1].Kind := TLspFileOperationKind.Create;
  Edit.Operations[1].FileName := 'C:\P\Mehr.pas';
  Edit.Operations[2].Kind := TLspFileOperationKind.Delete;
  Edit.Operations[2].FileName := 'C:\P\Weg.pas';
  Edit.Files := [Default(TLspFileEdits)];
  Edit.Files[0].FileName := 'C:\P\Neu.pas';
  Edit.Files[0].Edits := [TextEdit(0, 5, 8, 'Neu')];
  Entries := TAtlasResults.RenamePreview(Edit,
    function(const AFileName: string): string
    begin
      Result := 'unit Alt;';
    end);
  Assert.AreEqual(4, Integer(Length(Entries)));
  Assert.AreEqual('C:\P\Alt.pas', Entries[0].FileName);
  Assert.AreEqual('Alt.pas', Entries[0].Text);
  Assert.AreEqual('Neu.pas', Entries[0].Detail);
  Assert.AreEqual('', Entries[1].Text);
  Assert.AreEqual('Mehr.pas', Entries[1].Detail);
  Assert.AreEqual('Weg.pas', Entries[2].Text);
  Assert.AreEqual('', Entries[2].Detail);
  Assert.AreEqual('unit Neu;', Entries[3].Detail);
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
