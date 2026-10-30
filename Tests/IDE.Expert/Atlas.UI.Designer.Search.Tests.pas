unit Atlas.UI.Designer.Search.Tests;

// Fenster „Komponenten suchen“ (#1442): Treffer und Zeilen folgen Suchwort,
// Art, Feldern und Gruppierung; die Auswahl überspringt Gruppenköpfe und
// bleibt beim Umschalten auf derselben Komponente; die klein Art zeigt flach
// alle Arten; Zum Ereignis nur mit belegtem Ereignis; Name kopieren landet in
// der Zwischenablage.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Designer.Components,
  Atlas.UI.Designer.Search;

type
  [TestFixture]
  TAtlasComponentSearchWindowTests = class
  private
    FWindow: TAtlasComponentSearchWindow;
    function Items: TArray<TAtlasDesignerItem>;
    function Open(ACompact: Boolean; const ACurrent: string): TAtlasComponentSearchWindow;
    function SelectedName: string;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen: Clipboard legt sein Objekt einmal an und gibt es erst am
    /// Programmende frei.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure HierarchyStartsOnFirstComponent;
    [Test]
    procedure PatternKindAndFields;
    [Test]
    procedure SelectionSkipsHeadersAndStays;
    [Test]
    procedure CompactIsFlat;
    [Test]
    procedure ActionsNeedWhatTheyUse;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Vcl.Clipbrd,
  Atlas.Core.Style.Palette;

function TAtlasComponentSearchWindowTests.Items: TArray<TAtlasDesignerItem>;
var
  mItem: TAtlasDesignerItem;
begin
  mItem := TAtlasDesignerItem.Create('pnlTop', 'TPanel', True);
  mItem.Container := True;
  mItem.Bounds := Rect(0, 0, 400, 40);
  Result := TArray<TAtlasDesignerItem>.Create(mItem);
  mItem := TAtlasDesignerItem.Create('btnOK', 'TButton', True);
  mItem.Caption := 'OK';
  mItem.ParentName := 'pnlTop';
  mItem.Bounds := Rect(300, 8, 375, 33);
  mItem.Events := TArray<string>.Create('OnClick = btnOKClick');
  Result := Result + [mItem];
  mItem := TAtlasDesignerItem.Create('edtName', 'TEdit', True);
  mItem.Bounds := Rect(10, 60, 200, 83);
  Result := Result + [mItem];
  mItem := TAtlasDesignerItem.Create('qryKunden', 'TFDQuery', False);
  Result := Result + [mItem];
end;

function TAtlasComponentSearchWindowTests.Open(ACompact: Boolean; const ACurrent: string): TAtlasComponentSearchWindow;
var
  mOptions: TAtlasComponentSearchOptions;
begin
  mOptions := Default(TAtlasComponentSearchOptions);
  mOptions.Compact := ACompact;
  mOptions.FormName := 'frmMain';
  mOptions.FormBounds := Rect(0, 0, 400, 300);
  mOptions.Kind := TAtlasDesignerKind.All;
  mOptions.Fields := [TAtlasDesignerField.Name, TAtlasDesignerField.Caption, TAtlasDesignerField.ClassName];
  mOptions.Grouping := TAtlasDesignerGrouping.Hierarchy;
  mOptions.Preview := True;
  mOptions.Current := ACurrent;
  FWindow.Free;
  FWindow := TAtlasComponentSearchWindow.CreateSearch(nil, mOptions, Items, TAtlasColors.Light);
  Result := FWindow;
end;

function TAtlasComponentSearchWindowTests.SelectedName: string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := FWindow.SelectedItem;
  if mIndex >= 0 then
    Result := Items[mIndex].Name;
end;

procedure TAtlasComponentSearchWindowTests.WarmUpFirstUse;
begin
  try
    ActionsNeedWhatTheyUse;
  finally
    TearDown;
  end;
end;

procedure TAtlasComponentSearchWindowTests.TearDown;
begin
  FreeAndNil(FWindow);
end;

procedure TAtlasComponentSearchWindowTests.HierarchyStartsOnFirstComponent;
var
  mRows: TArray<TAtlasDesignerRow>;
begin
  Open(False, '');
  mRows := FWindow.Rows;
  Assert.AreEqual(4, Integer(Length(FWindow.Hits)), 'ohne Suchwort alle');
  Assert.IsTrue(mRows[0].Header, 'erste Zeile ist ein Kopf');
  Assert.IsFalse(FWindow.SelectedItem < 0, 'eine Komponente gewählt');
  Assert.IsTrue(FWindow.PreviewVisible, 'groß mit Vorschau');
  Open(False, 'edtName');
  Assert.AreEqual('edtName', SelectedName, 'Auswahl im Designer zuerst gewählt');
end;

procedure TAtlasComponentSearchWindowTests.PatternKindAndFields;
begin
  Open(False, '');
  FWindow.SetPattern('ok');
  Assert.AreEqual(1, Integer(Length(FWindow.Hits)));
  Assert.AreEqual('btnOK', SelectedName);
  FWindow.SetFields([TAtlasDesignerField.ClassName]);
  Assert.AreEqual(0, Integer(Length(FWindow.Hits)), 'nur Klasse: kein Treffer für ok');
  FWindow.SetFields([]);
  Assert.IsTrue(FWindow.Fields = [TAtlasDesignerField.ClassName], 'ein Feld bleibt gewählt');
  FWindow.SetFields([TAtlasDesignerField.Name]);
  FWindow.SetPattern('');
  FWindow.SetKind(TAtlasDesignerKind.NonVisual);
  Assert.AreEqual(1, Integer(Length(FWindow.Hits)), 'nur nichtvisuelle');
  Assert.AreEqual('qryKunden', SelectedName);
  FWindow.SetKind(TAtlasDesignerKind.Containers);
  Assert.AreEqual('pnlTop', SelectedName);
end;

procedure TAtlasComponentSearchWindowTests.SelectionSkipsHeadersAndStays;
var
  mSeen: TArray<string>;
  mIndex: Integer;
begin
  Open(False, '');
  mSeen := TArray<string>.Create(SelectedName);
  for mIndex := 1 to 6 do
  begin
    FWindow.MoveSelection(1);
    if SelectedName <> mSeen[High(mSeen)] then
      mSeen := mSeen + [SelectedName];
  end;
  Assert.AreEqual(4, Integer(Length(mSeen)), 'alle vier, Köpfe übersprungen, am Ende stehen bleiben');
  FWindow.MoveSelection(-100);
  Assert.AreEqual(mSeen[0], SelectedName, 'oben stehen bleiben');
  FWindow.MoveSelection(2);
  Assert.AreEqual(mSeen[2], SelectedName);
  FWindow.SetGrouping(TAtlasDesignerGrouping.ClassName);
  Assert.AreEqual(mSeen[2], SelectedName, 'Gruppierung wechseln behält die Komponente');
  FWindow.SetGrouping(TAtlasDesignerGrouping.Flat);
  Assert.AreEqual(4, Integer(Length(FWindow.Rows)), 'flach ohne Köpfe');
  Assert.AreEqual(mSeen[2], SelectedName);
end;

procedure TAtlasComponentSearchWindowTests.CompactIsFlat;
var
  mRow: TAtlasDesignerRow;
begin
  Open(True, '');
  Assert.IsTrue(FWindow.Grouping = TAtlasDesignerGrouping.Flat, 'klein: flach');
  Assert.IsTrue(FWindow.Kind = TAtlasDesignerKind.All, 'klein: alle Arten');
  Assert.IsFalse(FWindow.PreviewVisible, 'klein: ohne Vorschau');
  for mRow in FWindow.Rows do
    Assert.IsFalse(mRow.Header);
  FWindow.SetPattern('btn');
  Assert.AreEqual('btnOK', SelectedName);
end;

procedure TAtlasComponentSearchWindowTests.ActionsNeedWhatTheyUse;
var
  mCalls: Integer;
begin
  Open(False, 'edtName');
  mCalls := 0;
  FWindow.OnAction :=
    procedure(AAction: TAtlasComponentSearchAction; const AItem: TAtlasDesignerItem)
    begin
      Inc(mCalls);
    end;
  // Zum Ereignis ohne belegtes Ereignis: nichts (auch nicht später in der Warteschlange).
  FWindow.Run(TAtlasComponentSearchAction.Event);
  Assert.AreEqual(0, mCalls);
  FWindow.Run(TAtlasComponentSearchAction.CopyName);
  Assert.AreEqual('edtName', Clipboard.AsText, 'Name in der Zwischenablage');
  Assert.AreEqual(0, mCalls, 'Kopieren erledigt das Fenster selbst');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasComponentSearchWindowTests);

end.
