unit Atlas.Core.Designer.Usages.Tests;

// Tests für „Verwendungen im Code“ ohne IDE (#750): Art des Zugriffs (liest,
// schreibt, übergibt, Ereignis), Felddeklaration, Handler aus der DFM und
// Suchbereich.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasDesignerUsagesTests = class
  public
    [Test]
    procedure KindOfAccess;
    [Test]
    procedure FindsFieldDeclaration;
    [Test]
    procedure FindsHandler;
    [Test]
    procedure ScopeFilters;
    [Test]
    procedure SortsByComponentFileLine;
  end;

implementation

uses
  Atlas.Core.Designer.Usages;

function KindOf(const ALine: string): TAtlasUsageKind;
begin
  Result := TAtlasDesignerUsages.KindAt(ALine, Pos('edtRabatt', ALine) - 1);
end;

function UnitLines: TArray<string>;
begin
  Result := TArray<string>.Create(
    'type',
    '  TfrmAuftragAlt = class(TForm)',
    '    edtRabatt: TEdit;',
    '  end;',
    '  TfrmAuftrag = class;',
    '  TfrmAuftrag = class (TForm)',
    '    lblRabatt, edtRabatt: TEdit;',
    '    procedure edtRabattChange(Sender: TObject);',
    '  private',
    '    FRabatt: Integer;',
    '  end;',
    '',
    'implementation',
    '',
    'procedure TfrmAuftrag.edtRabattChangeAlt;',
    'begin end;',
    'procedure TfrmAuftrag.edtRabattChange(Sender: TObject);',
    'begin end;');
end;

{ TAtlasDesignerUsagesTests }

procedure TAtlasDesignerUsagesTests.KindOfAccess;
begin
  Assert.AreEqual(Ord(TAtlasUsageKind.Writes), Ord(KindOf('  edtRabatt.Text := ''0'';')), 'FormShow');
  Assert.AreEqual(Ord(TAtlasUsageKind.Writes), Ord(KindOf('  Self.edtRabatt.Font.Style:=[];')));
  Assert.AreEqual(Ord(TAtlasUsageKind.Writes), Ord(KindOf('  edtRabatt := nil;')), 'die Komponente selbst');
  Assert.AreEqual(Ord(TAtlasUsageKind.Reads), Ord(KindOf('  Result := StrToFloat(edtRabatt.Text) / 100;')),
    'Berechnen');
  Assert.AreEqual(Ord(TAtlasUsageKind.Reads), Ord(KindOf('  if edtRabatt.Text = '''' then')), 'Vergleich');
  Assert.AreEqual(Ord(TAtlasUsageKind.Reads), Ord(KindOf('  edtRabatt.SetFocus;')), 'Methode');
  Assert.AreEqual(Ord(TAtlasUsageKind.Reads), Ord(KindOf('  x := edtRabatt.Lines[0];')));
  Assert.AreEqual(Ord(TAtlasUsageKind.Passes), Ord(KindOf('  FelderSperren([edtRabatt, edtNr]);')),
    'FelderSperren');
  Assert.AreEqual(Ord(TAtlasUsageKind.Passes), Ord(KindOf('  if Sender = edtRabatt then')), 'Sender');
  Assert.AreEqual(Ord(TAtlasUsageKind.Passes), Ord(KindOf('  with edtRabatt do')), 'with');
  Assert.AreEqual(Ord(TAtlasUsageKind.Passes), Ord(KindOf('  mEdit := edtRabatt;')), 'rechte Seite');
  Assert.AreEqual(Ord(TAtlasUsageKind.Event), Ord(KindOf('  edtRabatt.OnChange := RabattGeaendert;')),
    'Handler');
  Assert.AreEqual(Ord(TAtlasUsageKind.Writes), Ord(KindOf('  edtRabatt.Once := 1;')), 'kein Ereignis');
  Assert.AreEqual(Ord(TAtlasUsageKind.Writes), Ord(KindOf('  edtRabatt.Items[2] := ''x'';')), 'Index');
end;

procedure TAtlasDesignerUsagesTests.FindsFieldDeclaration;
var
  mCharacter: Integer;
begin
  Assert.AreEqual(6, TAtlasDesignerUsages.FieldLine(UnitLines, 'TfrmAuftrag', 'edtRabatt', mCharacter),
    'nicht in TfrmAuftragAlt, nicht in der Vorwärtsdeklaration');
  Assert.AreEqual(15, mCharacter, 'hinter „lblRabatt, “');
  Assert.AreEqual(6, TAtlasDesignerUsages.FieldLine(UnitLines, 'tfrmauftrag', 'LBLRABATT', mCharacter));
  Assert.AreEqual(4, mCharacter);
  Assert.AreEqual(2, TAtlasDesignerUsages.FieldLine(UnitLines, 'TfrmAuftragAlt', 'edtRabatt', mCharacter));
  Assert.AreEqual(-1, TAtlasDesignerUsages.FieldLine(UnitLines, 'TfrmAuftrag', 'FRabatt2', mCharacter));
  Assert.AreEqual(-1, mCharacter);
  Assert.AreEqual(-1, TAtlasDesignerUsages.FieldLine(UnitLines, 'TfrmFehlt', 'edtRabatt', mCharacter));
end;

procedure TAtlasDesignerUsagesTests.FindsHandler;
begin
  Assert.AreEqual(16, TAtlasDesignerUsages.HandlerLine(UnitLines, 'TfrmAuftrag', 'edtRabattChange'),
    'nicht edtRabattChangeAlt');
  Assert.AreEqual(14, TAtlasDesignerUsages.HandlerLine(UnitLines, 'tfrmauftrag', 'EDTRABATTCHANGEALT'));
  Assert.AreEqual(-1, TAtlasDesignerUsages.HandlerLine(UnitLines, 'TfrmAuftrag', 'FormShow'));
end;

procedure TAtlasDesignerUsagesTests.ScopeFilters;
const
  cForm = 'C:\P\Auftrag.pas';
  cOther = 'C:\P\Lager.pas';
  cForeign = 'C:\Q\Fremd.pas';
var
  mProject: TArray<string>;
begin
  mProject := [cForm, cOther];
  Assert.IsTrue(TAtlasDesignerUsages.InScope(TAtlasUsageScope.UnitOnly, 'c:\p\auftrag.pas', cForm, mProject));
  Assert.IsFalse(TAtlasDesignerUsages.InScope(TAtlasUsageScope.UnitOnly, cOther, cForm, mProject),
    'frmAuftrag.edtRabatt aus einer anderen Unit nur ab „project“');
  Assert.IsTrue(TAtlasDesignerUsages.InScope(TAtlasUsageScope.Project, cOther, cForm, mProject));
  Assert.IsFalse(TAtlasDesignerUsages.InScope(TAtlasUsageScope.Project, cForeign, cForm, mProject));
  Assert.IsTrue(TAtlasDesignerUsages.InScope(TAtlasUsageScope.ProjectGroup, cForeign, cForm, mProject));
end;

procedure TAtlasDesignerUsagesTests.SortsByComponentFileLine;
var
  mUsages: TArray<TAtlasUsage>;
begin
  SetLength(mUsages, 3);
  mUsages[0].Component := 'edtRabatt';
  mUsages[0].FileName := 'b.pas';
  mUsages[0].Line := 1;
  mUsages[1].Component := 'edtNr';
  mUsages[1].FileName := 'b.pas';
  mUsages[1].Line := 9;
  mUsages[2].Component := 'edtRabatt';
  mUsages[2].FileName := 'a.pas';
  mUsages[2].Line := 5;
  mUsages := TAtlasDesignerUsages.Sorted(mUsages);
  Assert.AreEqual('edtNr', mUsages[0].Component);
  Assert.AreEqual('a.pas', mUsages[1].FileName);
  Assert.AreEqual(1, mUsages[2].Line);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDesignerUsagesTests);

end.
