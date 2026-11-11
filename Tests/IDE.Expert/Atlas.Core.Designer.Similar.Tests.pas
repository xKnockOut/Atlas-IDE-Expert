unit Atlas.Core.Designer.Similar.Tests;

// Tests für „Gleiche Komponenten auswählen“ (#738): jede Art des Vergleichs,
// Nachfahren und gemeinsame Basisklasse, Bereich, nichtvisuelle Komponenten
// und das Erweitern der Auswahl.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasSimilarTests = class
  public
    [Test]
    procedure SameClassSkipsOtherClasses;
    [Test]
    procedure DescendantsFromCommonBase;
    [Test]
    procedure SameParentAndChildren;
    [Test]
    procedure SameValueAcrossPanels;
    [Test]
    procedure SameHandlerAnyEvent;
    [Test]
    procedure InvertInFormAndParent;
    [Test]
    procedure NonVisualReferenceIncludesNonVisual;
    [Test]
    procedure MergeReplacesOrExtends;
    [Test]
    procedure OfferedValuesSkipLayout;
    [Test]
    procedure NoReference;
  end;

implementation

uses
  Atlas.Core.Designer.Similar;

function Item(const AName: string; const AClasses: TArray<string>; const AParent: string;
  AVisual: Boolean = True): TAtlasSimilarItem;
begin
  Result := TAtlasSimilarItem.Create(AName, AClasses, AParent, AVisual);
end;

/// <summary>pnlAdresse mit edtName, edtOrt, mskPlz; pnlKnoepfe mit cmbLand und btnOk; dazu edtSuche auf dem
/// Formular und dsKunden, qryKunden nichtvisuell.</summary>
function Form: TArray<TAtlasSimilarItem>;
var
  mPanel, mEdit, mMask, mCombo, mButton, mSource, mQuery: TArray<string>;
begin
  mPanel := ['TPanel', 'TCustomPanel', 'TWinControl', 'TComponent'];
  mEdit := ['TEdit', 'TCustomEdit', 'TWinControl', 'TComponent'];
  mMask := ['TMaskEdit', 'TCustomMaskEdit', 'TCustomEdit', 'TWinControl', 'TComponent'];
  mCombo := ['TComboBox', 'TCustomComboBox', 'TWinControl', 'TComponent'];
  mButton := ['TButton', 'TButtonControl', 'TWinControl', 'TComponent'];
  mSource := ['TDataSource', 'TComponent'];
  mQuery := ['TFDQuery', 'TDataSet', 'TComponent'];
  Result := [Item('pnlAdresse', mPanel, ''), Item('edtName', mEdit, 'pnlAdresse'),
    Item('edtOrt', mEdit, 'pnlAdresse'), Item('mskPlz', mMask, 'pnlAdresse'), Item('pnlKnoepfe', mPanel, ''),
    Item('cmbLand', mCombo, 'pnlKnoepfe'), Item('btnOk', mButton, 'pnlKnoepfe'), Item('edtSuche', mEdit, ''),
    Item('dsKunden', mSource, '', False), Item('qryKunden', mQuery, '', False)];
  Result[1].Values := ['Font.Name = ''Tahoma''', 'TabOrder = 0'];
  Result[1].Handlers := ['EingabeChange'];
  Result[2].Values := ['TabOrder = 1'];
  Result[2].Handlers := ['EingabeChange'];
  Result[5].Values := ['Font.Name = ''Tahoma'''];
  Result[5].Handlers := ['EingabeChange', 'LandExit'];
  Result[7].Values := ['Font.Name = ''Segoe UI'''];
end;

function Names(const AItems: TArray<TAtlasSimilarItem>; const AHits: TArray<Integer>): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex in AHits do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + AItems[mIndex].Name;
  end;
end;

function Find(const AItems: TArray<TAtlasSimilarItem>; AKind: TAtlasSimilarKind; AReference: Integer;
  const AArgument: string = ''; AScope: TAtlasSimilarScope = TAtlasSimilarScope.Form): string;
begin
  Result := Names(AItems, TAtlasSimilar.Find(AItems, TAtlasSimilarQuery.Create(AKind, AReference, AScope,
    AArgument)));
end;

procedure TAtlasSimilarTests.SameClassSkipsOtherClasses;
var
  mItems: TArray<TAtlasSimilarItem>;
begin
  mItems := Form;
  Assert.AreEqual('edtName,edtOrt,edtSuche', Find(mItems, TAtlasSimilarKind.SameClass, 1));
  Assert.AreEqual('edtName,edtOrt', Find(mItems, TAtlasSimilarKind.SameClass, 1, '', TAtlasSimilarScope.Parent));
end;

procedure TAtlasSimilarTests.DescendantsFromCommonBase;
var
  mItems: TArray<TAtlasSimilarItem>;
begin
  mItems := Form;
  mItems[1].Selected := True;
  Assert.AreEqual('TEdit', TAtlasSimilar.CommonBase(mItems, 1), 'allein: die eigene Klasse');
  mItems[3].Selected := True;
  Assert.AreEqual('TCustomEdit', TAtlasSimilar.CommonBase(mItems, 1));
  Assert.AreEqual('edtName,edtOrt,mskPlz,edtSuche', Find(mItems, TAtlasSimilarKind.ClassAndDescendants, 1));
  mItems[5].Selected := True;
  Assert.AreEqual('TWinControl', TAtlasSimilar.CommonBase(mItems, 1));
end;

procedure TAtlasSimilarTests.SameParentAndChildren;
var
  mItems: TArray<TAtlasSimilarItem>;
begin
  mItems := Form;
  Assert.AreEqual('edtName,edtOrt,mskPlz', Find(mItems, TAtlasSimilarKind.SameParent, 2));
  Assert.AreEqual('cmbLand,btnOk', Find(mItems, TAtlasSimilarKind.Children, 4));
  Assert.AreEqual('cmbLand,btnOk', Find(mItems, TAtlasSimilarKind.Children, 4, '', TAtlasSimilarScope.Parent),
    'Kinder liegen im Bezug, nicht neben ihm');
  mItems[4].ParentName := 'pnlAdresse';
  Assert.AreEqual('edtName,edtOrt,mskPlz,pnlKnoepfe,cmbLand,btnOk', Find(mItems, TAtlasSimilarKind.AllChildren, 0));
  Assert.AreEqual('edtName,edtOrt,mskPlz,pnlKnoepfe', Find(mItems, TAtlasSimilarKind.Children, 0));
end;

procedure TAtlasSimilarTests.SameValueAcrossPanels;
var
  mItems: TArray<TAtlasSimilarItem>;
begin
  mItems := Form;
  Assert.AreEqual('edtName,cmbLand', Find(mItems, TAtlasSimilarKind.SameValue, 1, 'Font.Name = ''Tahoma'''));
  Assert.AreEqual('edtName', Find(mItems, TAtlasSimilarKind.SameValue, 1, 'Font.Name = ''Tahoma''',
    TAtlasSimilarScope.Parent));
  Assert.AreEqual('', Find(mItems, TAtlasSimilarKind.SameValue, 1, 'Font.Name = ''Arial'''));
end;

procedure TAtlasSimilarTests.SameHandlerAnyEvent;
var
  mItems: TArray<TAtlasSimilarItem>;
begin
  mItems := Form;
  Assert.AreEqual('edtName,edtOrt,cmbLand', Find(mItems, TAtlasSimilarKind.SameHandler, 1, 'eingabechange'));
  Assert.AreEqual('cmbLand', Find(mItems, TAtlasSimilarKind.SameHandler, 5, 'LandExit'));
end;

procedure TAtlasSimilarTests.InvertInFormAndParent;
var
  mItems: TArray<TAtlasSimilarItem>;
begin
  mItems := Form;
  mItems[1].Selected := True;
  mItems[2].Selected := True;
  Assert.AreEqual('pnlAdresse,mskPlz,pnlKnoepfe,cmbLand,btnOk,edtSuche', Find(mItems, TAtlasSimilarKind.Invert, 1));
  Assert.AreEqual('mskPlz', Find(mItems, TAtlasSimilarKind.Invert, 1, '', TAtlasSimilarScope.Parent));
end;

procedure TAtlasSimilarTests.NonVisualReferenceIncludesNonVisual;
var
  mItems: TArray<TAtlasSimilarItem>;
begin
  mItems := Form;
  mItems[8].Selected := True;
  Assert.AreEqual('dsKunden', Find(mItems, TAtlasSimilarKind.SameClass, 8));
  Assert.AreEqual('pnlAdresse,edtName,edtOrt,mskPlz,pnlKnoepfe,cmbLand,btnOk,edtSuche,qryKunden',
    Find(mItems, TAtlasSimilarKind.Invert, 8));
  mItems[9].Selected := True;
  Assert.AreEqual('TComponent', TAtlasSimilar.CommonBase(mItems, 8));
  Assert.AreEqual('pnlAdresse,edtName,edtOrt,mskPlz,pnlKnoepfe,cmbLand,btnOk,edtSuche,dsKunden,qryKunden',
    Find(mItems, TAtlasSimilarKind.ClassAndDescendants, 8), 'nichtvisueller Bezug: auch Steuerelemente');
end;

procedure TAtlasSimilarTests.MergeReplacesOrExtends;
var
  mItems: TArray<TAtlasSimilarItem>;
begin
  mItems := Form;
  mItems[6].Selected := True;
  Assert.AreEqual('edtName,edtOrt', Names(mItems, TAtlasSimilar.Merge(mItems, [2, 1], False)));
  Assert.AreEqual('edtName,edtOrt,btnOk', Names(mItems, TAtlasSimilar.Merge(mItems, [2, 1, 99], True)));
  Assert.AreEqual(6, TAtlasSimilar.Reference(mItems));
end;

procedure TAtlasSimilarTests.OfferedValuesSkipLayout;
var
  mItem: TAtlasSimilarItem;
  mValues: TArray<string>;
begin
  mItem := Item('edtName', ['TEdit'], '');
  mItem.Values := ['Left = 8', 'Font.Name = ''Tahoma''', 'TabOrder = 0', 'Color = clInfoBk', 'Width = 121'];
  mValues := TAtlasSimilar.OfferedValues(mItem);
  Assert.AreEqual(2, Integer(Length(mValues)));
  Assert.AreEqual('Font.Name = ''Tahoma''', mValues[0]);
  Assert.AreEqual('Color = clInfoBk', mValues[1]);
end;

procedure TAtlasSimilarTests.NoReference;
var
  mItems: TArray<TAtlasSimilarItem>;
begin
  mItems := Form;
  Assert.AreEqual(-1, TAtlasSimilar.Reference(mItems));
  Assert.AreEqual('', Find(mItems, TAtlasSimilarKind.SameClass, -1));
  Assert.AreEqual('', TAtlasSimilar.CommonBase(mItems, 42));
end;

end.
