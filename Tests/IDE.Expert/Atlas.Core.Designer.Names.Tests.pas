unit Atlas.Core.Designer.Names.Tests;

// Tests für die gemeinsamen Namenshelfer der Designer-Werkzeuge: Suche ohne
// Groß-/Kleinschreibung, Suche in Einträgen über den Namen, Komponenten in
// Listen, Bezeichner und Einrückung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasDesignerNamesTests = class
  public
    [Test]
    procedure IndexOfIgnoresCase;
    [Test]
    procedure ContainsOnEmptyList;
    [Test]
    procedure IndexOfNameUsesGetter;
    [Test]
    procedure ComponentsByInstance;
    [Test]
    procedure IdentifierRules;
    [Test]
    procedure EventAssignmentNeedsOnAndIdentifiers;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Designer.Names;

type
  TNamed = record
    Name: string;
    Tag: Integer;
  end;

function Named(const AName: string; ATag: Integer): TNamed;
begin
  Result.Name := AName;
  Result.Tag := ATag;
end;

function NameOf(AItem: TNamed): string;
begin
  Result := AItem.Name;
end;

{ TAtlasDesignerNamesTests }

procedure TAtlasDesignerNamesTests.IndexOfIgnoresCase;
var
  mNames: TArray<string>;
begin
  mNames := TArray<string>.Create('edtName', 'btnOk', 'BTNOK');
  Assert.AreEqual(1, TAtlasDesignerNames.IndexOf(mNames, 'btnok'), 'erster Treffer');
  Assert.AreEqual(-1, TAtlasDesignerNames.IndexOf(mNames, 'btnCancel'));
  Assert.IsTrue(TAtlasDesignerNames.Contains(mNames, 'EDTNAME'));
  Assert.IsFalse(TAtlasDesignerNames.Contains(mNames, 'edt'), 'nur ganze Namen');
end;

procedure TAtlasDesignerNamesTests.ContainsOnEmptyList;
begin
  Assert.IsFalse(TAtlasDesignerNames.Contains(nil, ''));
  Assert.AreEqual(-1, TAtlasDesignerNames.IndexOf(nil, 'edtName'));
end;

procedure TAtlasDesignerNamesTests.IndexOfNameUsesGetter;
var
  mItems: TArray<TNamed>;
begin
  mItems := TArray<TNamed>.Create(Named('pnlTop', 1), Named('edtName', 2), Named('EDTNAME', 3));
  Assert.AreEqual(1, TAtlasDesignerNames.IndexOfName<TNamed>(mItems, 'edtname', NameOf));
  Assert.AreEqual(-1, TAtlasDesignerNames.IndexOfName<TNamed>(mItems, 'btnOk', NameOf));
  Assert.AreEqual(-1, TAtlasDesignerNames.IndexOfName<TNamed>(nil, 'pnlTop', NameOf), 'leere Liste');
end;

procedure TAtlasDesignerNamesTests.ComponentsByInstance;
var
  mOwner, mFirst, mSecond, mOther: TComponent;
  mList: TArray<TComponent>;
  mNames: TArray<string>;
begin
  mOwner := TComponent.Create(nil);
  try
    mFirst := TComponent.Create(mOwner);
    mFirst.Name := 'edtName';
    mSecond := TComponent.Create(mOwner);
    mSecond.Name := 'btnOk';
    mOther := TComponent.Create(mOwner);
    mList := TArray<TComponent>.Create(mFirst, mSecond);
    Assert.IsTrue(TAtlasDesignerNames.ContainsComponent(mList, mSecond));
    Assert.IsFalse(TAtlasDesignerNames.ContainsComponent(mList, mOther));
    Assert.IsFalse(TAtlasDesignerNames.ContainsComponent(mList, nil));
    mNames := TAtlasDesignerNames.NamesOf(mList);
    Assert.AreEqual(Integer(2), Integer(Length(mNames)));
    Assert.AreEqual('edtName', mNames[0]);
    Assert.AreEqual('btnOk', mNames[1]);
    Assert.AreEqual(Integer(0), Integer(Length(TAtlasDesignerNames.NamesOf(nil))), 'leere Liste');
  finally
    mOwner.Free;
  end;
end;

procedure TAtlasDesignerNamesTests.IdentifierRules;
begin
  Assert.IsTrue(TAtlasDesignerNames.IsIdentifier('edtName'));
  Assert.IsTrue(TAtlasDesignerNames.IsIdentifier('_Feld2'));
  Assert.IsFalse(TAtlasDesignerNames.IsIdentifier(''), 'leer');
  Assert.IsFalse(TAtlasDesignerNames.IsIdentifier('2Feld'), 'Ziffer vorn');
  Assert.IsFalse(TAtlasDesignerNames.IsIdentifier('Font.Name'), 'Punkt');
  Assert.IsFalse(TAtlasDesignerNames.IsIdentifier('Größe'), 'Umlaut');
end;

procedure TAtlasDesignerNamesTests.EventAssignmentNeedsOnAndIdentifiers;
begin
  Assert.IsTrue(TAtlasDesignerNames.IsEventAssignment('OnClick', 'btnOkClick'));
  Assert.IsFalse(TAtlasDesignerNames.IsEventAssignment('On', 'btnOkClick'), 'nur On');
  Assert.IsFalse(TAtlasDesignerNames.IsEventAssignment('Online', 'True'), 'klein nach On');
  Assert.IsFalse(TAtlasDesignerNames.IsEventAssignment('Caption', 'Ok'), 'keine Ereignis-Eigenschaft');
  Assert.IsFalse(TAtlasDesignerNames.IsEventAssignment('OnClick', 'Frame1.Click'), 'Wert kein Bezeichner');
  Assert.IsFalse(TAtlasDesignerNames.IsEventAssignment('OnClick.X', 'btnOkClick'), 'Pfad mit Punkt');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDesignerNamesTests);

end.
