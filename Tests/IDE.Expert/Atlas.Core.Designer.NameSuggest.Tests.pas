unit Atlas.Core.Designer.NameSuggest.Tests;

// Tests für sprechende Komponentennamen (#608): Standardnamen, Präfixe (auch
// eigene und über Vorfahren), Wortbildung mit Umlauten, Handler als Quelle,
// Zuordnung von Labels, Reihenfolge der Quellen, Kollisionen, Handler beim
// Umbenennen und Stellen im Code ohne Zeichenketten und Kommentare.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasNameSuggestTests = class
  public
    [Test]
    procedure DefaultNames;
    [Test]
    procedure Prefixes;
    [Test]
    procedure Words;
    [Test]
    procedure HandlerWords;
    [Test]
    procedure LabelAssignment;
    [Test]
    procedure CaptionFirst;
    [Test]
    procedure LabelAndDataField;
    [Test]
    procedure Collisions;
    [Test]
    procedure NoSourceLeavesEmpty;
    [Test]
    procedure HandlerRename;
    [Test]
    procedure PlacesSkipStringsAndComments;
  end;

implementation

uses
  System.Types,
  System.SysUtils,
  Atlas.Core.Designer.NameSuggest;

function Input(const AName, AClassName, ACaption: string): TAtlasNameInput;
begin
  Result := Default(TAtlasNameInput);
  Result.Name := AName;
  Result.ClassChain := [AClassName, 'TWinControl', 'TControl'];
  Result.Caption := ACaption;
end;

function Options: TAtlasNameOptions;
begin
  Result := Default(TAtlasNameOptions);
  Result.Sources := TAtlasNameSuggest.ParseSources('caption, label, handler, dataField');
  Result.Umlauts := TAtlasUmlautRule.Replace;
end;

function NameLabel(const ACaption: string; ALeft, ATop, AWidth: Integer): TAtlasNameLabel;
begin
  Result := Default(TAtlasNameLabel);
  Result.Caption := ACaption;
  Result.Bounds := Bounds(ALeft, ATop, AWidth, 13);
  Result.ParentName := 'pnlMain';
end;

{ TAtlasNameSuggestTests }

procedure TAtlasNameSuggestTests.DefaultNames;
begin
  Assert.IsTrue(TAtlasNameSuggest.IsDefaultName('Button1', 'TButton'));
  Assert.IsTrue(TAtlasNameSuggest.IsDefaultName('edit12', 'TEdit'));
  Assert.IsFalse(TAtlasNameSuggest.IsDefaultName('Button', 'TButton'), 'ohne Ziffer');
  Assert.IsFalse(TAtlasNameSuggest.IsDefaultName('btnSpeichern', 'TButton'));
  Assert.IsFalse(TAtlasNameSuggest.IsDefaultName('Button1a', 'TButton'));
end;

procedure TAtlasNameSuggestTests.Prefixes;
begin
  Assert.AreEqual('btn', TAtlasNameSuggest.Prefix(['TButton', 'TButtonControl'], ''));
  Assert.AreEqual('edt', TAtlasNameSuggest.Prefix(['TMyEdit', 'TEdit', 'TCustomEdit'], ''), 'über den Vorfahren');
  Assert.AreEqual('cmd', TAtlasNameSuggest.Prefix(['TButton'], 'TButton = cmd'), 'eigene vor eingebauter');
  Assert.AreEqual('fan', TAtlasNameSuggest.Prefix(['TFancyThing', 'TComponent'], ''), 'unbekannt: drei Buchstaben');
end;

procedure TAtlasNameSuggestTests.Words;
begin
  Assert.AreEqual('Speichern', TAtlasNameSuggest.Word('&Speichern', TAtlasUmlautRule.Replace));
  Assert.AreEqual('Plz', TAtlasNameSuggest.Word('PLZ:', TAtlasUmlautRule.Replace));
  Assert.AreEqual('KundeSuchen', TAtlasNameSuggest.Word('Kunde suchen …', TAtlasUmlautRule.Replace));
  Assert.AreEqual('Groesse', TAtlasNameSuggest.Word('Größe', TAtlasUmlautRule.Replace));
  Assert.AreEqual('Gre', TAtlasNameSuggest.Word('Größe', TAtlasUmlautRule.Remove));
  Assert.AreEqual('KundeName', TAtlasNameSuggest.Word('KUNDE_NAME', TAtlasUmlautRule.Replace));
  Assert.AreEqual('EinSehrLanger', TAtlasNameSuggest.Word('Ein sehr langer Hinweis', TAtlasUmlautRule.Replace),
    'höchstens drei Wörter');
  Assert.AreEqual('', TAtlasNameSuggest.Word('…', TAtlasUmlautRule.Replace));
end;

procedure TAtlasNameSuggestTests.HandlerWords;
begin
  Assert.AreEqual('Export', TAtlasNameSuggest.HandlerWord('DoExport', 'Button1'));
  Assert.AreEqual('Export', TAtlasNameSuggest.HandlerWord('ExportClick', 'Button1'));
  Assert.AreEqual('', TAtlasNameSuggest.HandlerWord('Button1Click', 'Button1'), 'Standardname zählt nicht');
  Assert.AreEqual('Online', TAtlasNameSuggest.HandlerWord('Online', 'Button1'), '„On“ ohne Großbuchstaben bleibt');
end;

procedure TAtlasNameSuggestTests.LabelAssignment;
var
  mLabels: TArray<TAtlasNameLabel>;
begin
  mLabels := [NameLabel('PLZ:', 8, 12, 30), NameLabel('Ort:', 8, 40, 30), NameLabel('Hinweis', 100, 60, 60)];
  // Rechts neben „PLZ:“ in derselben Zeile.
  Assert.AreEqual('PLZ:', TAtlasNameSuggest.LabelFor('Edit3', 'pnlMain', Bounds(60, 8, 120, 21), mLabels));
  // Direkt unter „Hinweis“.
  Assert.AreEqual('Hinweis', TAtlasNameSuggest.LabelFor('Memo1', 'pnlMain', Bounds(100, 78, 200, 60), mLabels));
  // Anderer Parent zählt nicht.
  Assert.AreEqual('', TAtlasNameSuggest.LabelFor('Edit3', 'pnlOther', Bounds(60, 8, 120, 21), mLabels));
  // FocusControl schlägt die Lage.
  mLabels[1].FocusControl := 'Edit3';
  Assert.AreEqual('Ort:', TAtlasNameSuggest.LabelFor('Edit3', 'pnlMain', Bounds(60, 8, 120, 21), mLabels));
end;

procedure TAtlasNameSuggestTests.CaptionFirst;
var
  mProposals: TArray<TAtlasNameProposal>;
begin
  mProposals := TAtlasNameSuggest.Propose([Input('Button1', 'TButton', 'Speichern')], Options, ['Button1']);
  Assert.AreEqual('btnSpeichern', mProposals[0].NewName);
  Assert.IsTrue(mProposals[0].Source = TAtlasNameSource.Caption);
  Assert.IsFalse(mProposals[0].Collision);
end;

procedure TAtlasNameSuggestTests.LabelAndDataField;
var
  mInputs: TArray<TAtlasNameInput>;
  mProposals: TArray<TAtlasNameProposal>;
begin
  mInputs := [Input('Edit3', 'TEdit', ''), Input('DBEdit1', 'TDBEdit', '')];
  mInputs[0].LabelText := 'PLZ:';
  mInputs[1].DataField := 'KUNDE_NAME';
  mProposals := TAtlasNameSuggest.Propose(mInputs, Options, ['Edit3', 'DBEdit1']);
  Assert.AreEqual('edtPlz', mProposals[0].NewName);
  Assert.IsTrue(mProposals[0].Source = TAtlasNameSource.LabelText);
  Assert.AreEqual('edtKundeName', mProposals[1].NewName);
  Assert.IsTrue(mProposals[1].Source = TAtlasNameSource.DataField);
end;

procedure TAtlasNameSuggestTests.Collisions;
var
  mProposals: TArray<TAtlasNameProposal>;
begin
  mProposals := TAtlasNameSuggest.Propose([Input('Button1', 'TButton', 'Speichern'),
    Input('Button2', 'TButton', 'Speichern')], Options, ['Button1', 'Button2', 'btnSpeichern']);
  Assert.AreEqual('btnSpeichern2', mProposals[0].NewName);
  Assert.IsTrue(mProposals[0].Collision);
  Assert.AreEqual('btnSpeichern3', mProposals[1].NewName, 'schon vergebene Vorschläge zählen mit');
end;

procedure TAtlasNameSuggestTests.NoSourceLeavesEmpty;
var
  mInputs: TArray<TAtlasNameInput>;
  mProposals: TArray<TAtlasNameProposal>;
begin
  mInputs := [Input('Button1', 'TButton', '')];
  mInputs[0].Handlers := ['Button1Click'];
  mProposals := TAtlasNameSuggest.Propose(mInputs, Options, ['Button1']);
  Assert.AreEqual('', mProposals[0].NewName);
  Assert.IsTrue(mProposals[0].Source = TAtlasNameSource.None);
  mInputs[0].Handlers := ['Button1Click', 'DoExport'];
  mProposals := TAtlasNameSuggest.Propose(mInputs, Options, ['Button1']);
  Assert.AreEqual('btnExport', mProposals[0].NewName, 'sprechender Handler');
end;

procedure TAtlasNameSuggestTests.HandlerRename;
begin
  Assert.AreEqual('btnSpeichernClick', TAtlasNameSuggest.HandlerName('Button1Click', 'Button1', 'btnSpeichern'));
  Assert.AreEqual('', TAtlasNameSuggest.HandlerName('SpeichernAusfuehren', 'Button1', 'btnSpeichern'));
  Assert.AreEqual('', TAtlasNameSuggest.HandlerName('Button1', 'Button1', 'btnSpeichern'), 'nur mit Ereignisteil');
end;

procedure TAtlasNameSuggestTests.PlacesSkipStringsAndComments;
var
  mPlaces: TArray<TAtlasNamePlace>;
begin
  mPlaces := TAtlasNameSuggest.Places('  Button1.Caption := ''Button1''; // Button1' + #13#10 +
    '  { Button1' + #13#10 + '  Button1 } (* Button1 *) Button10.Free; Self.button1.Free;', 'Button1');
  Assert.AreEqual(2, Integer(Length(mPlaces)));
  Assert.AreEqual(0, mPlaces[0].Line);
  Assert.AreEqual(2, mPlaces[0].Character);
  Assert.AreEqual(2, mPlaces[1].Line);
  Assert.AreEqual(46, mPlaces[1].Character);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNameSuggestTests);

end.
