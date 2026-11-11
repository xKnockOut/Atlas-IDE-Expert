unit Atlas.Core.Designer.ExtractFrame.Tests;

// Tests für „Auswahl in Frame auslagern“ (#611) auf Fixture-DFM und -Unit:
// Container als Frame, Auswahl mit Verschiebung, mitwandernde und bleibende
// Handler, Zugriffe im Formular-Code, Felder des Formulars im Handler,
// Fehlerfälle und Namensvorschlag.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Designer.ExtractFrame;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasExtractFrameTests = class
  private
    function Options(const ANames: TArray<string>; AContainer: Boolean): TAtlasExtractOptions;
  public
    [Test]
    procedure ContainerAsFrame;
    [Test]
    procedure FormCodeAccess;
    [Test]
    procedure SelectionShifted;
    [Test]
    procedure HandlersKeptWithoutMove;
    [Test]
    procedure Errors;
    [Test]
    procedure SuggestNames;
  end;

implementation

uses
  System.SysUtils;

const
  cDfm =
    'object frmKunden: TfrmKunden' + #13#10 +
    '  Left = 0' + #13#10 +
    '  Top = 0' + #13#10 +
    '  Caption = ''Kunden''' + #13#10 +
    '  object pnlAdresse: TPanel' + #13#10 +
    '    Left = 10' + #13#10 +
    '    Top = 20' + #13#10 +
    '    Width = 300' + #13#10 +
    '    Height = 120' + #13#10 +
    '    TabOrder = 0' + #13#10 +
    '    object lblName: TLabel' + #13#10 +
    '      Left = 8' + #13#10 +
    '      Top = 8' + #13#10 +
    '      Width = 40' + #13#10 +
    '      Height = 13' + #13#10 +
    '      Caption = ''Name''' + #13#10 +
    '    end' + #13#10 +
    '    object edtName: TEdit' + #13#10 +
    '      Left = 60' + #13#10 +
    '      Top = 8' + #13#10 +
    '      Width = 200' + #13#10 +
    '      Height = 21' + #13#10 +
    '      TabOrder = 0' + #13#10 +
    '      OnChange = FeldChange' + #13#10 +
    '    end' + #13#10 +
    '    object edtPlz: TEdit' + #13#10 +
    '      Left = 60' + #13#10 +
    '      Top = 40' + #13#10 +
    '      Width = 80' + #13#10 +
    '      Height = 21' + #13#10 +
    '      TabOrder = 1' + #13#10 +
    '      OnChange = edtPlzChange' + #13#10 +
    '    end' + #13#10 +
    '  end' + #13#10 +
    '  object edtOrt: TEdit' + #13#10 +
    '    Left = 10' + #13#10 +
    '    Top = 150' + #13#10 +
    '    Width = 100' + #13#10 +
    '    Height = 21' + #13#10 +
    '    OnChange = FeldChange' + #13#10 +
    '  end' + #13#10 +
    '  object btnOk: TButton' + #13#10 +
    '    Left = 200' + #13#10 +
    '    Top = 150' + #13#10 +
    '    Width = 75' + #13#10 +
    '    Height = 25' + #13#10 +
    '    Caption = ''OK''' + #13#10 +
    '    OnClick = btnOkClick' + #13#10 +
    '  end' + #13#10 +
    'end' + #13#10;

  cUnit =
    'unit uKunden;' + #13#10 +
    '' + #13#10 +
    'interface' + #13#10 +
    '' + #13#10 +
    'uses' + #13#10 +
    '  System.Classes,' + #13#10 +
    '  Vcl.Controls,' + #13#10 +
    '  Vcl.StdCtrls,' + #13#10 +
    '  Vcl.ExtCtrls;' + #13#10 +
    '' + #13#10 +
    'type' + #13#10 +
    '  TfrmKunden = class(TForm)' + #13#10 +
    '    pnlAdresse: TPanel;' + #13#10 +
    '    lblName: TLabel;' + #13#10 +
    '    edtName: TEdit;' + #13#10 +
    '    edtPlz: TEdit;' + #13#10 +
    '    edtOrt: TEdit;' + #13#10 +
    '    btnOk: TButton;' + #13#10 +
    '    procedure FeldChange(Sender: TObject);' + #13#10 +
    '    procedure edtPlzChange(Sender: TObject);' + #13#10 +
    '    procedure btnOkClick(Sender: TObject);' + #13#10 +
    '  end;' + #13#10 +
    '' + #13#10 +
    'implementation' + #13#10 +
    '' + #13#10 +
    '{$R *.dfm}' + #13#10 +
    '' + #13#10 +
    'procedure TfrmKunden.FeldChange(Sender: TObject);' + #13#10 +
    'begin' + #13#10 +
    '  btnOk.Enabled := True;' + #13#10 +
    'end;' + #13#10 +
    '' + #13#10 +
    'procedure TfrmKunden.edtPlzChange(Sender: TObject);' + #13#10 +
    'begin' + #13#10 +
    '  edtPlz.Color := clWindow;' + #13#10 +
    '  btnOk.Enabled := True;' + #13#10 +
    'end;' + #13#10 +
    '' + #13#10 +
    'procedure TfrmKunden.btnOkClick(Sender: TObject);' + #13#10 +
    'begin' + #13#10 +
    '  edtName.Text := ''''; // edtName leeren' + #13#10 +
    '  ShowMessage(''edtName'');' + #13#10 +
    'end;' + #13#10 +
    '' + #13#10 +
    'end.' + #13#10;

function Has(const AList: TArray<string>; const AItem: string): Boolean;
var
  mItem: string;
begin
  for mItem in AList do
  begin
    if mItem = AItem then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasExtractFrameTests }

function TAtlasExtractFrameTests.Options(const ANames: TArray<string>; AContainer: Boolean): TAtlasExtractOptions;
begin
  Result := Default(TAtlasExtractOptions);
  Result.Names := ANames;
  Result.FrameClass := 'TfrmAdresse';
  Result.FrameUnit := 'uAdresseFrame';
  Result.InstanceName := 'frmAdresse';
  Result.MoveHandlers := True;
  Result.ContainerAsFrame := AContainer;
end;

procedure TAtlasExtractFrameTests.ContainerAsFrame;
var
  mResult: TAtlasExtractResult;
begin
  mResult := TAtlasExtractFrame.Run(cDfm, cUnit, 'TfrmKunden', Options(['pnlAdresse'], True));
  Assert.AreEqual('', mResult.Error);
  Assert.AreEqual(3, Integer(Length(mResult.Moved)));
  Assert.IsTrue(Has(mResult.Moved, 'edtPlz'));
  Assert.IsFalse(Has(mResult.Moved, 'pnlAdresse'));
  // edtPlzChange nutzt nur edtPlz und wandert; FeldChange nutzt auch edtOrt und bleibt.
  Assert.IsTrue(Has(mResult.MovedHandlers, 'edtPlzChange'));
  Assert.IsTrue(Has(mResult.KeptHandlers, 'FeldChange'));
  Assert.IsTrue(Has(mResult.Notes, 'kept|FeldChange'));
  Assert.IsTrue(Has(mResult.Notes, 'containerProps|pnlAdresse'));
  Assert.IsTrue(Has(mResult.Notes, 'formField|btnOk'));
  // Formular-DFM: Panel ersetzt durch inline, bleibender Handler über inherited.
  Assert.IsFalse(mResult.FormDfm.Contains('object pnlAdresse'));
  Assert.IsTrue(mResult.FormDfm.Contains('  inline frmAdresse: TfrmAdresse' + #13#10 + '    Left = 10' + #13#10 +
    '    Top = 20' + #13#10 + '    Width = 300' + #13#10 + '    Height = 120'));
  Assert.IsTrue(mResult.FormDfm.Contains('    inherited edtName: TEdit' + #13#10 + '      OnChange = FeldChange' +
    #13#10 + '    end'));
  Assert.IsFalse(mResult.FormDfm.Contains('edtPlzChange'));
  Assert.IsTrue(mResult.FormDfm.Contains('  object edtOrt: TEdit'));
  // Frame-DFM: Kinder mit unveränderter Lage, eine Ebene eingerückt.
  Assert.IsTrue(mResult.FrameDfm.StartsWith('object frmAdresse: TfrmAdresse'));
  Assert.IsTrue(mResult.FrameDfm.Contains('  object edtPlz: TEdit' + #13#10 + '    Left = 60' + #13#10 +
    '    Top = 40'));
  Assert.IsTrue(mResult.FrameDfm.Contains('    OnChange = edtPlzChange'));
  Assert.IsFalse(mResult.FrameDfm.Contains('FeldChange'));
  Assert.IsTrue(mResult.FrameDfm.Contains('  Width = 300'));
  // Frame-Unit
  Assert.IsTrue(mResult.FrameUnit.StartsWith('unit uAdresseFrame;'));
  Assert.IsTrue(mResult.FrameUnit.Contains('  TfrmAdresse = class(TFrame)' + #13#10 + '    lblName: TLabel;'));
  Assert.IsTrue(mResult.FrameUnit.Contains('    edtPlz: TEdit;' + #13#10 +
    '    procedure edtPlzChange(Sender: TObject);'));
  Assert.IsTrue(mResult.FrameUnit.Contains('procedure TfrmAdresse.edtPlzChange(Sender: TObject);'));
  Assert.IsTrue(mResult.FrameUnit.Contains('  Vcl.ExtCtrls,' + #13#10 + '  Vcl.Forms;'));
  Assert.IsFalse(mResult.FrameUnit.Contains('pnlAdresse'));
  Assert.IsFalse(mResult.FrameUnit.Contains('FeldChange'));
end;

procedure TAtlasExtractFrameTests.FormCodeAccess;
var
  mResult: TAtlasExtractResult;
begin
  mResult := TAtlasExtractFrame.Run(cDfm, cUnit, 'TfrmKunden', Options(['pnlAdresse'], True));
  Assert.IsTrue(mResult.FormUnit.Contains('  frmAdresse.edtName.Text := ''''; // edtName leeren'));
  Assert.IsTrue(mResult.FormUnit.Contains('  ShowMessage(''edtName'');'));
  Assert.IsTrue(mResult.FormUnit.Contains('  TfrmKunden = class(TForm)' + #13#10 +
    '    frmAdresse: TfrmAdresse;' + #13#10 + '    edtOrt: TEdit;'));
  Assert.IsFalse(mResult.FormUnit.Contains('pnlAdresse'));
  Assert.IsFalse(mResult.FormUnit.Contains('edtPlzChange'));
  Assert.IsTrue(mResult.FormUnit.Contains('procedure TfrmKunden.FeldChange(Sender: TObject);'));
  Assert.IsTrue(mResult.FormUnit.Contains('  Vcl.ExtCtrls,' + #13#10 + '  uAdresseFrame;'));
  // Keine doppelte Leerzeile, wo der Handler war.
  Assert.IsFalse(mResult.FormUnit.Contains('end;' + #13#10 + #13#10 + #13#10));
end;

procedure TAtlasExtractFrameTests.SelectionShifted;
var
  mResult: TAtlasExtractResult;
begin
  mResult := TAtlasExtractFrame.Run(cDfm, cUnit, 'TfrmKunden', Options(['edtName', 'edtPlz'], False));
  Assert.AreEqual('', mResult.Error);
  Assert.AreEqual(2, Integer(Length(mResult.Moved)));
  // Rechteck um beide: 60,8 bis 260,61.
  Assert.IsTrue(mResult.FrameDfm.Contains('  Width = 200' + #13#10 + '  Height = 53'));
  Assert.IsTrue(mResult.FrameDfm.Contains('  object edtName: TEdit' + #13#10 + '    Left = 0' + #13#10 +
    '    Top = 0'));
  Assert.IsTrue(mResult.FrameDfm.Contains('  object edtPlz: TEdit' + #13#10 + '    Left = 0' + #13#10 +
    '    Top = 32'));
  // Im Panel bleibt lblName, an Stelle von edtName steht der Frame.
  Assert.IsTrue(mResult.FormDfm.Contains('    inline frmAdresse: TfrmAdresse' + #13#10 + '      Left = 60' +
    #13#10 + '      Top = 8'));
  Assert.IsTrue(mResult.FormDfm.Contains('object pnlAdresse: TPanel'));
  Assert.IsTrue(mResult.FormDfm.Contains('object lblName: TLabel'));
  Assert.IsFalse(mResult.FormDfm.Contains('object edtPlz'));
  Assert.IsTrue(mResult.FormUnit.Contains('    pnlAdresse: TPanel;' + #13#10 + '    lblName: TLabel;' + #13#10 +
    '    frmAdresse: TfrmAdresse;'));
end;

procedure TAtlasExtractFrameTests.HandlersKeptWithoutMove;
var
  mOptions: TAtlasExtractOptions;
  mResult: TAtlasExtractResult;
begin
  mOptions := Options(['pnlAdresse'], True);
  mOptions.MoveHandlers := False;
  mResult := TAtlasExtractFrame.Run(cDfm, cUnit, 'TfrmKunden', mOptions);
  Assert.AreEqual(0, Integer(Length(mResult.MovedHandlers)));
  Assert.AreEqual(2, Integer(Length(mResult.KeptHandlers)));
  Assert.IsTrue(mResult.FormDfm.Contains('    inherited edtPlz: TEdit' + #13#10 +
    '      OnChange = edtPlzChange'));
  Assert.IsTrue(mResult.FormUnit.Contains('procedure TfrmKunden.edtPlzChange(Sender: TObject);'));
  Assert.IsFalse(mResult.FrameUnit.Contains('procedure'));
  Assert.IsFalse(mResult.FrameDfm.Contains('OnChange'));
end;

procedure TAtlasExtractFrameTests.Errors;
var
  mOptions: TAtlasExtractOptions;
begin
  Assert.AreEqual('nothing', TAtlasExtractFrame.Run(cDfm, cUnit, 'TfrmKunden', Options([], False)).Error);
  Assert.AreEqual('parents', TAtlasExtractFrame.Run(cDfm, cUnit, 'TfrmKunden', Options(['edtName', 'edtOrt'],
    False)).Error);
  Assert.AreEqual('notFound|edtGibtsNicht', TAtlasExtractFrame.Run(cDfm, cUnit, 'TfrmKunden',
    Options(['edtGibtsNicht'], False)).Error);
  mOptions := Options(['edtOrt'], False);
  mOptions.FrameClass := 'T frm';
  Assert.AreEqual('class', TAtlasExtractFrame.Run(cDfm, cUnit, 'TfrmKunden', mOptions).Error);
  mOptions := Options(['edtOrt'], False);
  mOptions.InstanceName := '';
  Assert.AreEqual('name', TAtlasExtractFrame.Run(cDfm, cUnit, 'TfrmKunden', mOptions).Error);
end;

procedure TAtlasExtractFrameTests.SuggestNames;
var
  mClass, mUnit, mInstance: string;
begin
  Assert.IsTrue(TAtlasExtractFrame.Suggest('pnlAdresse', mClass, mUnit, mInstance));
  Assert.AreEqual('TfrmAdresse', mClass);
  Assert.AreEqual('uAdresseFrame', mUnit);
  Assert.AreEqual('frmAdresse', mInstance);
  Assert.IsTrue(TAtlasExtractFrame.Suggest('kunde', mClass, mUnit, mInstance));
  Assert.AreEqual('TfrmKunde', mClass);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasExtractFrameTests);

end.
