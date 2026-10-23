unit Atlas.Common.Rules.Builtin.Casts.Tests;

// Tests der Regeln für harte Typumwandlungen:
// unrelated-class-cast (#1129): Beispiel aus dem Issue mit Korrektur, Klammern
// nur vor einem Zugriff, verwandte Klassen, unbekannte Vorfahren, Interfaces,
// Zeiger, Klassenreferenzen, TObject als Quelle, Zugriffsklassen-Trick, Option
// allowTypes, Typen aus dem Index, bedingte Deklarationen, Abschalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUnrelatedClassCastTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure ParensOnlyBeforeAccess;
    [Test]
    procedure RelatedClassesAreSilent;
    [Test]
    procedure UnknownAncestorIsSilent;
    [Test]
    procedure InterfacesPointersAndClassReferencesAreSilent;
    [Test]
    procedure AccessorClassTrickIsSilent;
    [Test]
    procedure AllowTypesOption;
    [Test]
    procedure TypesFromIndex;
    [Test]
    procedure ConditionalDeclarationIsSilent;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Casts,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Tests.RuleAssert;

const
  // Klassen wie in der VCL, ohne Index in derselben Unit.
  cControls = 'type'#10'  TControl = class'#10'  public'#10'    Caption: string;'#10'  end;'#10 +
    '  TButton = class(TControl)'#10'  private'#10'    FDefault: Boolean;'#10'  end;'#10 +
    '  TEdit = class(TControl)'#10'  private'#10'    FText: string;'#10'  end;'#10;

/// <summary>Unit mit den Typen ATypes und der Methode Pruefen mit Deklarationen ADecls und Anweisungen ABody.
/// </summary>
function Source(const ATypes, ADecls, ABody: string): string;
begin
  Result := 'unit Formular;'#10'interface'#10'implementation'#10 + ATypes + 'procedure Pruefen(Sender: TObject);'#10 +
    'var'#10 + ADecls + 'begin'#10 + ABody + 'end;'#10'end.';
end;

function UnrelatedFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TUnrelatedClassCastRule.Create, ASource);
end;

function UnrelatedFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TUnrelatedClassCastRule.Create, ASource, AConfig, APath);
end;

/// <summary>Wendet die einzeiligen Edits einer Korrektur von hinten nach vorn an (Zeilen mit #10).</summary>
function Applied(const AText: string; const AFix: TRuleFix): string;
var
  mLines: TArray<string>;
  mIndex: Integer;
  mEdit: TRuleEdit;
  mLine: string;
begin
  mLines := AText.Split([#10]);
  for mIndex := High(AFix.Edits) downto 0 do
  begin
    mEdit := AFix.Edits[mIndex];
    Assert.AreEqual(mEdit.Range.StartPos.Line, mEdit.Range.EndPos.Line, 'nur einzeilige Edits');
    mLine := mLines[mEdit.Range.StartPos.Line];
    mLines[mEdit.Range.StartPos.Line] := Copy(mLine, 1, mEdit.Range.StartPos.Character) + mEdit.NewText +
      Copy(mLine, mEdit.Range.EndPos.Character + 1, MaxInt);
  end;
  Result := string.Join(#10, mLines);
end;

{ TUnrelatedClassCastTests }

procedure TUnrelatedClassCastTests.IssueExampleWithFix;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Source(cControls, '  mEdit: TEdit;'#10, '  mEdit := Sender as TEdit;'#10 +
    '  TButton(mEdit).Caption := ''OK'';'#10);
  mFound := UnrelatedFindings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(UnrelatedClassCastRuleId, mFound[0].RuleId);
  Assert.AreEqual('TEdit und TButton sind nicht verwandt: Die Umwandlung zeigt auf ein Objekt mit anderem Aufbau.',
    mFound[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFound[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFound[0].Confidence));
  Assert.AreEqual(21, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(16, mFound[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('In (mEdit as TButton) umwandeln', mFound[0].Fixes[0].Title);
  mFixed := Applied(mSource, mFound[0].Fixes[0]);
  Assert.IsTrue(Pos('  (mEdit as TButton).Caption := ''OK'';', mFixed) > 0, mFixed);
  Assert.AreEqual(0, Integer(Length(UnrelatedFindings(mFixed))));
end;

procedure TUnrelatedClassCastTests.ParensOnlyBeforeAccess;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := UnrelatedFindings(Source(cControls, '  mEdit: TEdit;'#10'  mButton: TButton;'#10,
    '  mButton := TButton(mEdit);'#10'  Pruefen(TButton((mEdit)));'#10));
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('mEdit as TButton', mFound[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual('mEdit as TButton', mFound[1].Fixes[0].Edits[0].NewText);
end;

procedure TUnrelatedClassCastTests.RelatedClassesAreSilent;
begin
  // Nach unten, nach oben, auf sich selbst und über mehrere Stufen.
  TRuleAssert.Silent(TUnrelatedClassCastRule.Create, Source(cControls +
    '  TBitBtn = class(TButton)'#10'  private'#10'    FGlyph: Integer;'#10'  end;'#10,
    '  mControl: TControl;'#10'  mButton: TButton;'#10'  mBit: TBitBtn;'#10,
    '  TButton(mControl).Caption := ''A'';'#10'  TControl(mButton).Caption := ''B'';'#10 +
    '  TButton(mButton).Caption := ''C'';'#10'  TBitBtn(mControl).Caption := ''D'';'#10 +
    '  TControl(mBit).Caption := ''E'';'#10'  TButton(Sender).Caption := ''F'';'#10));
end;

procedure TUnrelatedClassCastTests.UnknownAncestorIsSilent;
begin
  // TUnbekannt steht in keiner Unit: Die Kette ist offen, die Klassen könnten verwandt sein.
  TRuleAssert.Silent(TUnrelatedClassCastRule.Create, Source('type'#10'  TBasis = class(TUnbekannt)'#10'  end;'#10 +
    '  TAnders = class'#10'  end;'#10, '  mBasis: TBasis;'#10'  mAnders: TAnders;'#10,
    '  TAnders(mBasis).Free;'#10'  TBasis(mAnders).Free;'#10));
end;

procedure TUnrelatedClassCastTests.InterfacesPointersAndClassReferencesAreSilent;
begin
  TRuleAssert.Silent(TUnrelatedClassCastRule.Create, Source(cControls +
    '  IAnzeige = interface'#10'  end;'#10'  TControlClass = class of TControl;'#10'  TEditClass = class of TEdit;'#10,
    '  mAnzeige: IAnzeige;'#10'  mZeiger: Pointer;'#10'  mKlasse: TEditClass;'#10'  mObjekt: TObject;'#10 +
    '  mZahl: NativeInt;'#10,
    '  TButton(mAnzeige).Caption := ''A'';'#10'  TButton(mZeiger).Caption := ''B'';'#10 +
    '  TControlClass(mKlasse).Create;'#10'  TButton(mObjekt).Caption := ''C'';'#10 +
    '  TButton(mZahl).Caption := ''D'';'#10'  IAnzeige(mObjekt)._AddRef;'#10));
end;

procedure TUnrelatedClassCastTests.AccessorClassTrickIsSilent;
var
  mHack: string;
begin
  // Zugriffsklasse ohne Felder und neue virtuelle Methoden: gleicher Aufbau wie TControl.
  mHack := '  THackControl = class(TControl)'#10'  public'#10'    procedure Zeigen;'#10 +
    '    property Text: string read Caption;'#10'  end;'#10;
  TRuleAssert.Silent(TUnrelatedClassCastRule.Create, Source(cControls + mHack, '  mButton: TButton;'#10,
    '  THackControl(mButton).Zeigen;'#10));
  // Mit eigenem Feld bzw. neuer virtueller Methode ändert sich der Aufbau.
  TRuleAssert.Reports(TUnrelatedClassCastRule.Create, Source(cControls +
    '  THackControl = class(TControl)'#10'  private'#10'    FExtra: Integer;'#10'  end;'#10, '  mButton: TButton;'#10,
    '  THackControl(mButton).Free;'#10));
  TRuleAssert.Reports(TUnrelatedClassCastRule.Create, Source(cControls +
    '  THackControl = class(TControl)'#10'  public'#10'    procedure Zeigen; virtual;'#10'  end;'#10,
    '  mButton: TButton;'#10, '  THackControl(mButton).Zeigen;'#10));
end;

procedure TUnrelatedClassCastTests.AllowTypesOption;
var
  mSource: string;
begin
  mSource := Source(cControls, '  mEdit: TEdit;'#10, '  TButton(mEdit).Caption := ''OK'';'#10);
  Assert.AreEqual(0, Integer(Length(UnrelatedFindings(mSource,
    '{"rules": {"unrelated-class-cast": {"allowTypes": ["TEdit=TButton"]}}}', 'Formular.pas'))));
  Assert.AreEqual(0, Integer(Length(UnrelatedFindings(mSource,
    '{"rules": {"unrelated-class-cast": {"allowTypes": ["tbutton"]}}}', 'Formular.pas'))));
  // Paar in der anderen Richtung erlaubt diese Umwandlung nicht.
  Assert.AreEqual(1, Integer(Length(UnrelatedFindings(mSource,
    '{"rules": {"unrelated-class-cast": {"allowTypes": ["TButton=TEdit"]}}}', 'Formular.pas'))));
  Assert.IsTrue(TUnrelatedClassCastRule.Allowed(['Vcl.StdCtrls.TEdit = TButton'], 'TEdit', 'Vcl.StdCtrls.TButton'));
  Assert.IsFalse(TUnrelatedClassCastRule.Allowed(['TMemo'], 'TEdit', 'TButton'));
end;

procedure TUnrelatedClassCastTests.TypesFromIndex;
var
  mIndex: ISymbolIndex;
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10'type'#10'  TObject = class'#10 +
    '  end;'#10'implementation'#10'end.', 'C:\BDS\source\System.pas', nil));
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Steuerung;'#10'interface'#10 + cControls +
    '  TLabel = class(TUnbekannt)'#10'  end;'#10'implementation'#10'end.', 'C:\Projekt\Steuerung.pas', nil));
  mSource := 'unit Formular;'#10'interface'#10'uses Steuerung;'#10'implementation'#10 +
    'procedure Pruefen(AEdit: TEdit; ALabel: TLabel; AControl: TControl);'#10'begin'#10 +
    '  Steuerung.TButton(AEdit).Caption := ''A'';'#10'  TButton(ALabel).Caption := ''B'';'#10 +
    '  TEdit(AControl).Caption := ''C'';'#10'end;'#10'end.';
  mFound := TRuleAssert.IndexFindings(TUnrelatedClassCastRule.Create, mSource, mIndex, '', 'Formular.pas');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(6, mFound[0].Range.StartPos.Line);
  Assert.AreEqual('(AEdit as Steuerung.TButton)', mFound[0].Fixes[0].Edits[0].NewText);
end;

procedure TUnrelatedClassCastTests.ConditionalDeclarationIsSilent;
begin
  TRuleAssert.Silent(TUnrelatedClassCastRule.Create, Source(cControls,
    '{$IFDEF MITKNOPF}'#10'  mQuelle: TEdit;'#10'{$ELSE}'#10'  mQuelle: TButton;'#10'{$ENDIF}'#10,
    '  TButton(mQuelle).Caption := ''OK'';'#10));
end;

procedure TUnrelatedClassCastTests.OffAndExclude;
var
  mSource: string;
begin
  mSource := Source(cControls, '  mEdit: TEdit;'#10, '  TButton(mEdit).Caption := ''OK'';'#10);
  Assert.AreEqual(1, Integer(Length(UnrelatedFindings(mSource, '', 'Source/Formular.pas'))));
  Assert.AreEqual(0, Integer(Length(UnrelatedFindings(mSource, '{"rules": {"unrelated-class-cast": "off"}}',
    'Source/Formular.pas'))));
  Assert.AreEqual(0, Integer(Length(UnrelatedFindings(mSource, '{"rules": {"group:find-bugs": "off"}}',
    'Source/Formular.pas'))));
  Assert.AreEqual(0, Integer(Length(UnrelatedFindings(mSource,
    '{"rules": {"unrelated-class-cast": {"exclude": ["Source/*.pas"]}}}', 'Source/Formular.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TUnrelatedClassCastTests);

end.
