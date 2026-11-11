unit Atlas.Core.Designer.CodeLink.Tests;

// Tests für „Im Designer zeigen“ ohne IDE (#511): Bezeichnerkette unter dem
// Cursor, umschließende Methode und die Ziele im Formular (Feld,
// Feldnutzung, Handler, geteilter Handler, Ereignis des Formulars).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasDesignerLinkTests = class
  public
    [Test]
    procedure ChainUpToCursor;
    [Test]
    procedure ChainOutsideIdentifier;
    [Test]
    procedure MethodAroundLine;
    [Test]
    procedure FieldAndUsage;
    [Test]
    procedure SharedHandlerOffersBoth;
    [Test]
    procedure HandlerByEnclosingMethod;
    [Test]
    procedure NothingFound;
  end;

implementation

uses
  Atlas.Core.Designer.Components,
  Atlas.Core.Designer.CodeLink;

function Item(const AName, AClassName: string; const AEvents: TArray<string>): TAtlasDesignerItem;
begin
  Result := TAtlasDesignerItem.Create(AName, AClassName, True);
  Result.Events := AEvents;
end;

function Items: TArray<TAtlasDesignerItem>;
begin
  Result := TArray<TAtlasDesignerItem>.Create(
    Item('frmAuftrag', 'TfrmAuftrag', TArray<string>.Create('OnShow = FormShow')),
    Item('btnOk', 'TButton', TArray<string>.Create('OnClick = btnOkClick')),
    Item('btnSpeichern', 'TButton', TArray<string>.Create('OnClick = SpeichernClick', 'OnEnter = FeldEnter')),
    Item('mnuSpeichern', 'TMenuItem', TArray<string>.Create('OnClick = SpeichernClick')),
    Item('edtRabatt', 'TEdit', nil));
end;

procedure TAtlasDesignerLinkTests.ChainUpToCursor;
var
  mChain: TArray<string>;
begin
  // Cursor auf „btnOk“ in „Self.btnOk.Caption := 'x';“.
  mChain := TAtlasDesignerLink.ChainAt('  Self.btnOk.Caption := ''x'';', 8);
  Assert.AreEqual(2, Integer(Length(mChain)));
  Assert.AreEqual('Self', mChain[0]);
  Assert.AreEqual('btnOk', mChain[1]);
  mChain := TAtlasDesignerLink.ChainAt('  Self.btnOk.Caption := ''x'';', 15);
  Assert.AreEqual(3, Integer(Length(mChain)), 'auf Caption: ganze Kette');
  Assert.AreEqual('Caption', mChain[2]);
  mChain := TAtlasDesignerLink.ChainAt('  btnOk.Enabled', 7);
  Assert.AreEqual(1, Integer(Length(mChain)), 'direkt hinter dem Bezeichner');
  Assert.AreEqual('btnOk', mChain[0]);
end;

procedure TAtlasDesignerLinkTests.ChainOutsideIdentifier;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasDesignerLink.ChainAt('  x := 1 + 2;', 9))), 'Leerraum');
  Assert.AreEqual(0, Integer(Length(TAtlasDesignerLink.ChainAt('', 0))));
end;

procedure TAtlasDesignerLinkTests.MethodAroundLine;
var
  mLines: TArray<string>;
begin
  mLines := TArray<string>.Create(
    'implementation',
    '',
    'procedure TfrmAuftrag.btnOkClick(Sender: TObject);',
    'var',
    '  mText: string;',
    'begin',
    '  Close;',
    'end;',
    '',
    'class function TfrmAuftrag.Neu: TfrmAuftrag;',
    'begin',
    'end;',
    '',
    'procedure Hilfe;',
    'begin',
    'end;');
  Assert.AreEqual('btnOkClick', TAtlasDesignerLink.MethodAt(mLines, 6));
  Assert.AreEqual('btnOkClick', TAtlasDesignerLink.MethodAt(mLines, 2), 'im Kopf');
  Assert.AreEqual('Neu', TAtlasDesignerLink.MethodAt(mLines, 10), 'Klassenmethode');
  Assert.AreEqual('', TAtlasDesignerLink.MethodAt(mLines, 14), 'Routine ohne Klasse');
  Assert.AreEqual('', TAtlasDesignerLink.MethodAt(mLines, 0), 'vor jeder Methode');
end;

procedure TAtlasDesignerLinkTests.FieldAndUsage;
var
  mTargets: TArray<TAtlasDesignerTarget>;
begin
  mTargets := TAtlasDesignerLink.Targets(Items, TArray<string>.Create('btnOk'), '');
  Assert.AreEqual(1, Integer(Length(mTargets)));
  Assert.AreEqual('btnOk', mTargets[0].Component);
  Assert.AreEqual('', mTargets[0].Event, 'Feld: kein Ereignis');
  // Feldnutzung über das Formular-Objekt einer anderen Unit, mitten in einem Handler.
  mTargets := TAtlasDesignerLink.Targets(Items, TArray<string>.Create('frmAuftrag', 'EDTRABATT'), 'btnOkClick');
  Assert.AreEqual(1, Integer(Length(mTargets)));
  Assert.AreEqual('frmAuftrag', mTargets[0].Component, 'erster Teil, der eine Komponente benennt');
  mTargets := TAtlasDesignerLink.Targets(Items, TArray<string>.Create('Self', 'edtRabatt', 'Text'), 'btnOkClick');
  Assert.AreEqual('edtRabatt', mTargets[0].Component, 'Feld vor dem Handler');
end;

procedure TAtlasDesignerLinkTests.SharedHandlerOffersBoth;
var
  mTargets: TArray<TAtlasDesignerTarget>;
begin
  mTargets := TAtlasDesignerLink.Targets(Items, TArray<string>.Create('SpeichernClick'), '');
  Assert.AreEqual(2, Integer(Length(mTargets)), 'Button und Menüeintrag');
  Assert.AreEqual('btnSpeichern.OnClick', mTargets[0].Text);
  Assert.AreEqual('mnuSpeichern.OnClick', mTargets[1].Text);
end;

procedure TAtlasDesignerLinkTests.HandlerByEnclosingMethod;
var
  mTargets: TArray<TAtlasDesignerTarget>;
begin
  // Cursor auf „Close“ im Rumpf von btnOkClick.
  mTargets := TAtlasDesignerLink.Targets(Items, TArray<string>.Create('Close'), 'btnOkClick');
  Assert.AreEqual(1, Integer(Length(mTargets)));
  Assert.AreEqual('btnOk.OnClick', mTargets[0].Text);
  mTargets := TAtlasDesignerLink.Targets(Items, nil, 'FormShow');
  Assert.AreEqual('frmAuftrag.OnShow', mTargets[0].Text, 'Ereignis des Formulars');
  mTargets := TAtlasDesignerLink.Targets(Items, nil, 'FeldEnter');
  Assert.AreEqual('btnSpeichern.OnEnter', mTargets[0].Text);
end;

procedure TAtlasDesignerLinkTests.NothingFound;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasDesignerLink.Targets(Items, TArray<string>.Create('mText'), 'Hilfe'))));
  Assert.AreEqual(0, Integer(Length(TAtlasDesignerLink.Targets(nil, TArray<string>.Create('btnOk'), ''))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDesignerLinkTests);

end.
