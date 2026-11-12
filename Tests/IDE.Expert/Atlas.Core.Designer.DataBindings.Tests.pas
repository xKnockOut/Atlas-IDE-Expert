unit Atlas.Core.Designer.DataBindings.Tests;

// Tests für die Brotkrumenleiste der Datenbindung (#610): Konstrukt der
// Auswahl über Formular und Datenmodul, ProviderName und MasterSource,
// Stufen mit Sammelglied und Liste, Befunde (Feld fehlt, DataField ohne
// DataSource), Auswahl ohne Verbindungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasDataBindingsTests = class
  public
    [Test]
    procedure ObjectsWithFields;
    [Test]
    procedure TrailOfControl;
    [Test]
    procedure TrailOfDataSource;
    [Test]
    procedure TrailOfConnection;
    [Test]
    procedure DetailOverMasterSource;
    [Test]
    procedure AcrossDataModule;
    [Test]
    procedure FieldMissing;
    [Test]
    procedure NoDataSource;
    [Test]
    procedure WithoutConnections;
    [Test]
    procedure UnknownSelection;
    [Test]
    procedure CycleDoesNotHang;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Designer.FormModel,
  Atlas.Core.Designer.DataBindings;

const
  cForm =
    'object frmKunden: TfrmKunden' + #13#10 +
    '  object edtName: TDBEdit' + #13#10 +
    '    DataField = ''KUNDE_NAME''' + #13#10 +
    '    DataSource = dsKunden' + #13#10 +
    '  end' + #13#10 +
    '  object edtOrt: TDBEdit' + #13#10 +
    '    DataField = ''KUNDE_ORTX''' + #13#10 +
    '    DataSource = dsKunden' + #13#10 +
    '  end' + #13#10 +
    '  object grdKunden: TDBGrid' + #13#10 +
    '    DataSource = dsKunden' + #13#10 +
    '  end' + #13#10 +
    '  object SchemaCombo: TDBLookupComboBox' + #13#10 +
    '    KeyField = ''ID''' + #13#10 +
    '    ListField = ''SCHEMA_NAME''' + #13#10 +
    '    ListSource = dmDaten.dsSchema' + #13#10 +
    '  end' + #13#10 +
    '  object grdAuftraege: TDBGrid' + #13#10 +
    '    DataSource = dsAuftraege' + #13#10 +
    '  end' + #13#10 +
    '  object edtFrei: TDBEdit' + #13#10 +
    '    DataField = ''FREI''' + #13#10 +
    '  end' + #13#10 +
    '  object btnOk: TButton' + #13#10 +
    '  end' + #13#10 +
    '  object SQLConnection1: TSQLConnection' + #13#10 +
    '  end' + #13#10 +
    '  object qryKunden: TSQLQuery' + #13#10 +
    '    SQLConnection = SQLConnection1' + #13#10 +
    '  end' + #13#10 +
    '  object dspKunden: TDataSetProvider' + #13#10 +
    '    DataSet = qryKunden' + #13#10 +
    '  end' + #13#10 +
    '  object cdsKunden: TClientDataSet' + #13#10 +
    '    ProviderName = ''dspKunden''' + #13#10 +
    '    object cdsKundenKUNDE_NAME: TStringField' + #13#10 +
    '      FieldName = ''KUNDE_NAME''' + #13#10 +
    '    end' + #13#10 +
    '    object cdsKundenKUNDE_ORT: TStringField' + #13#10 +
    '      FieldName = ''KUNDE_ORT''' + #13#10 +
    '    end' + #13#10 +
    '  end' + #13#10 +
    '  object dsKunden: TDataSource' + #13#10 +
    '    DataSet = cdsKunden' + #13#10 +
    '  end' + #13#10 +
    '  object cdsAuftraege: TClientDataSet' + #13#10 +
    '    MasterSource = dsKunden' + #13#10 +
    '  end' + #13#10 +
    '  object dsAuftraege: TDataSource' + #13#10 +
    '    DataSet = cdsAuftraege' + #13#10 +
    '  end' + #13#10 +
    'end';
  cModule =
    'object dmDaten: TdmDaten' + #13#10 +
    '  object Connection: TSQLConnection' + #13#10 +
    '  end' + #13#10 +
    '  object qrySchema: TSQLQuery' + #13#10 +
    '    SQLConnection = Connection' + #13#10 +
    '  end' + #13#10 +
    '  object dsSchema: TDataSource' + #13#10 +
    '    DataSet = qrySchema' + #13#10 +
    '  end' + #13#10 +
    'end';

function All: TArray<TAtlasBindingObject>;
begin
  Result := TAtlasDataBindings.ObjectsOf('frmKunden', TAtlasFormModel.Parse(cForm)) +
    TAtlasDataBindings.ObjectsOf('dmDaten', TAtlasFormModel.Parse(cModule));
end;

function Heads(const ATrail: TAtlasBindingTrail): string;
var
  mCrumb: TAtlasBindingCrumb;
begin
  Result := '';
  for mCrumb in ATrail.Crumbs do
  begin
    if Result <> '' then
    begin
      Result := Result + ' > ';
    end;
    if mCrumb.Many then
    begin
      Result := Result + IntToStr(mCrumb.OnPath) + '*';
    end
    else
    begin
      Result := Result + mCrumb.Head.Caption;
    end;
  end;
end;

function Names(const ANodes: TArray<TAtlasBindingNode>): string;
var
  mNode: TAtlasBindingNode;
begin
  Result := '';
  for mNode in ANodes do
  begin
    Result := Result + mNode.Caption + ' ';
  end;
  Result := Result.Trim;
end;

procedure TAtlasDataBindingsTests.ObjectsWithFields;
var
  mObjects: TArray<TAtlasBindingObject>;
  mObject: TAtlasBindingObject;
  mFound: Boolean;
begin
  mObjects := TAtlasDataBindings.ObjectsOf('frmKunden', TAtlasFormModel.Parse(cForm));
  mFound := False;
  for mObject in mObjects do
  begin
    Assert.IsFalse(mObject.Name.StartsWith('cdsKundenKUNDE'), 'Felder sind keine Objekte');
    if mObject.Name = 'cdsKunden' then
    begin
      mFound := True;
      Assert.AreEqual('dspKunden', mObject.ProviderName);
      Assert.AreEqual('KUNDE_NAME;KUNDE_ORT', string.Join(';', mObject.Fields));
    end;
  end;
  Assert.IsTrue(mFound);
end;

procedure TAtlasDataBindingsTests.TrailOfControl;
var
  mTrail: TAtlasBindingTrail;
  mLast: TAtlasBindingCrumb;
begin
  mTrail := TAtlasDataBindings.Trail(All, 'frmKunden', 'edtName');
  Assert.AreEqual('SQLConnection1 > qryKunden > dspKunden > cdsKunden > dsKunden > edtName', Heads(mTrail));
  mLast := mTrail.Crumbs[High(mTrail.Crumbs)];
  Assert.IsTrue(mLast.Selected);
  Assert.AreEqual('KUNDE_NAME', mLast.Head.Field);
  // Stufe der Auswahl: alle Steuerelemente an dsKunden und das Detail-DataSet.
  Assert.AreEqual('edtName edtOrt grdKunden cdsAuftraege', Names(mLast.Members));
  Assert.AreEqual(11, mTrail.Size);
  Assert.IsFalse(mTrail.Crumbs[0].Selected);
end;

procedure TAtlasDataBindingsTests.TrailOfDataSource;
var
  mTrail: TAtlasBindingTrail;
begin
  mTrail := TAtlasDataBindings.Trail(All, 'frmKunden', 'dsKunden');
  Assert.AreEqual('SQLConnection1 > qryKunden > dspKunden > cdsKunden > dsKunden > 4* > dsAuftraege > grdAuftraege',
    Heads(mTrail));
  Assert.IsTrue(mTrail.Crumbs[4].Selected);
  Assert.IsTrue(mTrail.Crumbs[5].Many);
  Assert.AreEqual('', mTrail.Crumbs[5].CommonClass, 'Verbraucher verschiedener Klassen');
  Assert.AreEqual(4, Integer(Length(mTrail.Crumbs[5].Members)));
end;

procedure TAtlasDataBindingsTests.TrailOfConnection;
var
  mTrail: TAtlasBindingTrail;
begin
  mTrail := TAtlasDataBindings.Trail(All, 'frmKunden', 'SQLConnection1');
  Assert.AreEqual('SQLConnection1', mTrail.Crumbs[0].Head.Caption);
  Assert.IsTrue(mTrail.Crumbs[0].Selected);
  Assert.AreEqual(8, Integer(Length(mTrail.Crumbs)), 'alle Nachfolger bis grdAuftraege');
end;

procedure TAtlasDataBindingsTests.DetailOverMasterSource;
var
  mTrail: TAtlasBindingTrail;
begin
  mTrail := TAtlasDataBindings.Trail(All, 'frmKunden', 'grdAuftraege');
  Assert.AreEqual(
    'SQLConnection1 > qryKunden > dspKunden > cdsKunden > dsKunden > cdsAuftraege > dsAuftraege > grdAuftraege',
    Heads(mTrail));
end;

procedure TAtlasDataBindingsTests.AcrossDataModule;
var
  mTrail: TAtlasBindingTrail;
begin
  mTrail := TAtlasDataBindings.Trail(All, 'frmKunden', 'SchemaCombo');
  Assert.AreEqual('dmDaten.Connection > dmDaten.qrySchema > dmDaten.dsSchema > SchemaCombo', Heads(mTrail));
  Assert.AreEqual('dmDaten', mTrail.Crumbs[2].Head.Module);
  Assert.AreEqual('dsSchema', mTrail.Crumbs[2].Head.Name);
  Assert.AreEqual('SCHEMA_NAME', mTrail.Crumbs[3].Head.Field);
end;

procedure TAtlasDataBindingsTests.FieldMissing;
var
  mTrail: TAtlasBindingTrail;
begin
  mTrail := TAtlasDataBindings.Trail(All, 'frmKunden', 'edtOrt');
  Assert.IsTrue(mTrail.Selected.Finding = TAtlasBindingFinding.FieldMissing);
  Assert.AreEqual('KUNDE_ORTX', mTrail.Selected.MissingField);
  Assert.AreEqual('cdsKunden', mTrail.Selected.DataSet);
  // Ohne persistente Felder (qrySchema) ist nichts bekannt.
  mTrail := TAtlasDataBindings.Trail(All, 'frmKunden', 'SchemaCombo');
  Assert.IsTrue(mTrail.Selected.Finding = TAtlasBindingFinding.None);
end;

procedure TAtlasDataBindingsTests.NoDataSource;
var
  mTrail: TAtlasBindingTrail;
begin
  mTrail := TAtlasDataBindings.Trail(All, 'frmKunden', 'edtFrei');
  Assert.IsTrue(mTrail.Selected.Finding = TAtlasBindingFinding.NoDataSource);
  Assert.AreEqual('FREI', mTrail.Selected.MissingField);
  Assert.AreEqual(1, mTrail.Size);
end;

procedure TAtlasDataBindingsTests.WithoutConnections;
var
  mTrail: TAtlasBindingTrail;
begin
  mTrail := TAtlasDataBindings.Trail(All, 'frmKunden', 'btnOk');
  Assert.AreEqual(1, mTrail.Size);
  Assert.AreEqual(1, Integer(Length(mTrail.Crumbs)));
  Assert.IsTrue(mTrail.Crumbs[0].Selected);
end;

procedure TAtlasDataBindingsTests.UnknownSelection;
var
  mTrail: TAtlasBindingTrail;
begin
  mTrail := TAtlasDataBindings.Trail(All, 'frmKunden', '');
  Assert.AreEqual(0, mTrail.Size);
  Assert.AreEqual(0, Integer(Length(mTrail.Crumbs)));
  mTrail := TAtlasDataBindings.Trail(All, 'frmKunden', 'frmKunden');
  Assert.AreEqual(0, mTrail.Size);
end;

procedure TAtlasDataBindingsTests.CycleDoesNotHang;
var
  mObjects: TArray<TAtlasBindingObject>;
  mTrail: TAtlasBindingTrail;
begin
  // Query mit Parametern aus der eigenen DataSource: Kreis qryA → dsA → qryA.
  mObjects := TAtlasDataBindings.ObjectsOf('frmA', TAtlasFormModel.Parse(
    'object frmA: TfrmA' + #13#10 +
    '  object qryA: TSQLQuery' + #13#10 +
    '    DataSource = dsA' + #13#10 +
    '  end' + #13#10 +
    '  object dsA: TDataSource' + #13#10 +
    '    DataSet = qryA' + #13#10 +
    '  end' + #13#10 +
    '  object edtA: TDBEdit' + #13#10 +
    '    DataSource = dsA' + #13#10 +
    '  end' + #13#10 +
    'end'));
  mTrail := TAtlasDataBindings.Trail(mObjects, 'frmA', 'edtA');
  Assert.AreEqual(3, mTrail.Size);
  Assert.IsTrue(mTrail.Crumbs[High(mTrail.Crumbs)].Selected);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDataBindingsTests);

end.
