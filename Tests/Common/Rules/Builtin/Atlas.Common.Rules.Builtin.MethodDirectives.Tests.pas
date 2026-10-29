unit Atlas.Common.Rules.Builtin.MethodDirectives.Tests;

// Tests der Regel abstract-declaration-invalid (#998): abstract ohne virtual,
// Rumpf zu abstrakten Methoden, final, abstract sealed, static, bedingte
// Zweige, Korrekturen und Einstellungen; sealed mit offenen abstrakten
// Methoden (#1380, E2383, E2539, E2540 wie dcc in Cm.E2383, Cm.E2539,
// Cm.E2540).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMethodDirectiveRulesTests = class
  public
    [Test]
    procedure AbstractIssueExample;
    [Test]
    procedure ValidDirectivesAreSilent;
    [Test]
    procedure AbstractWithBody;
    [Test]
    procedure AbstractBodyWithOverloadOrBranchIsSilent;
    [Test]
    procedure FinalWithoutVirtual;
    [Test]
    procedure AbstractSealedClass;
    [Test]
    procedure SealedWithOwnAbstractMethod;
    [Test]
    procedure SealedInheritsAbstractMethod;
    [Test]
    procedure SealedImplementingAllIsSilent;
    [Test]
    procedure StaticOnInstanceOrVirtual;
    [Test]
    procedure Options;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.MethodDirectives,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit einer Klasse TForm aus AMembers; ABodies im implementation-Teil.</summary>
function Formen(const AMembers, ABodies: string): string;
begin
  Result := 'unit Formen;'#10'interface'#10'type'#10'  TForm = class'#10 + AMembers + '  end;'#10#10 +
    'implementation'#10#10 + ABodies + 'end.';
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TAbstractDeclarationInvalidRule.Create, ASource);
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TAbstractDeclarationInvalidRule.Create, ASource, AConfig, APath);
end;

function OnlyMessage(const ASource: string): string;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(ASource);
  Assert.AreEqual(1, Integer(Length(Found)), ASource);
  Result := Found[0].Message;
end;

procedure Silent(const ASource: string);
begin
  TRuleAssert.Silent(TAbstractDeclarationInvalidRule.Create, ASource);
end;

/// <summary>Meldungen von AFound mit Zeile, eine je Zeile, in der Reihenfolge der Treffer.</summary>
function Listed(const AFound: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFound do
    Result := Result + IntToStr(mFinding.Range.StartPos.Line) + ': ' + mFinding.Message + #10;
end;

/// <summary>Offset von APosition in AText mit Zeilen aus #10.</summary>
function OffsetOf(const AText: string; const APosition: TTextPosition): Integer;
var
  Line, Index: Integer;
begin
  Line := 0;
  Index := 1;
  while (Line < APosition.Line) and (Index <= Length(AText)) do
  begin
    if AText[Index] = #10 then
      Inc(Line);
    Inc(Index);
  end;
  Result := Index + APosition.Character;
end;

/// <summary>Wendet die Edits einer Korrektur von hinten nach vorn an, auch über Zeilen.</summary>
function ApplyFix(const AText: string; const AFix: TRuleFix): string;
var
  Index, Start, Stop: Integer;
begin
  Result := AText;
  for Index := High(AFix.Edits) downto 0 do
  begin
    Start := OffsetOf(Result, AFix.Edits[Index].Range.StartPos);
    Stop := OffsetOf(Result, AFix.Edits[Index].Range.EndPos);
    Result := Copy(Result, 1, Start - 1) + AFix.Edits[Index].NewText + Copy(Result, Stop, MaxInt);
  end;
end;

{ TMethodDirectiveRulesTests }

procedure TMethodDirectiveRulesTests.AbstractIssueExample;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Formen('    function Flaeche: Double; abstract;'#10, '');
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('abstract nur zusammen mit virtual oder dynamic (wie E2167).', Found[0].Message);
  Assert.AreEqual(4, Found[0].Range.StartPos.Line);
  Assert.AreEqual(30, Found[0].Range.StartPos.Character);
  Assert.AreEqual(38, Found[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('"virtual;" vor abstract einfügen', Found[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('    function Flaeche: Double; virtual; abstract;'#10, Fixed) > 0, Fixed);
  Silent(Fixed);
end;

procedure TMethodDirectiveRulesTests.ValidDirectivesAreSilent;
begin
  Silent(Formen('    function Flaeche: Double; virtual; abstract;'#10 +
    '    procedure Zeichnen; dynamic; abstract;'#10'    procedure Laden; override; abstract;'#10 +
    '    procedure Speichern; override; final;'#10'    procedure Pruefen; virtual; final;'#10 +
    '    class function Neu: TForm; static;'#10'    class procedure Melden; virtual; abstract;'#10 +
    '    procedure WMPaint(var Message: TMessage); message WM_PAINT;'#10'    procedure Laufen;'#10,
    'procedure TForm.Speichern;'#10'begin'#10'end;'#10#10'procedure TForm.Laufen;'#10'begin'#10'end;'#10#10));
  // Records kennen keine virtuellen Methoden: class function … static ist dort die Regel.
  Silent('unit Formen;'#10'interface'#10'type'#10'  TPunkt = record'#10'    class function Null: TPunkt; static;'#10 +
    '  end;'#10'implementation'#10'end.');
  Silent('unit Formen;'#10'interface'#10'type'#10'  TForm = class abstract'#10'  end;'#10 +
    '  TKreis = class sealed(TForm)'#10'  end;'#10'implementation'#10'end.');
end;

procedure TMethodDirectiveRulesTests.AbstractWithBody;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Formen('    function Flaeche: Double; virtual; abstract;'#10'    procedure Zeichnen;'#10,
    'function TForm.Flaeche: Double;'#10'begin'#10'  Result := 0;'#10'end;'#10#10 +
    'procedure TForm.Zeichnen;'#10'begin'#10'end;'#10#10);
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('TForm.Flaeche ist abstract und darf keinen Rumpf haben (wie E2136).', Found[0].Message);
  Assert.AreEqual(10, Found[0].Range.StartPos.Line);
  Assert.AreEqual(15, Found[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Rumpf entfernen', Found[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.AreEqual(Formen('    function Flaeche: Double; virtual; abstract;'#10'    procedure Zeichnen;'#10,
    'procedure TForm.Zeichnen;'#10'begin'#10'end;'#10#10), Fixed);
  Silent(Fixed);
  // Generische Klasse: der Rumpf heißt TListe<T>.Leeren.
  Assert.AreEqual('TListe.Leeren ist abstract und darf keinen Rumpf haben (wie E2136).',
    OnlyMessage('unit Formen;'#10'interface'#10'type'#10'  TListe<T> = class'#10 +
    '    procedure Leeren; virtual; abstract;'#10'  end;'#10'implementation'#10 +
    'procedure TListe<T>.Leeren;'#10'begin'#10'end;'#10'end.'));
end;

procedure TMethodDirectiveRulesTests.AbstractBodyWithOverloadOrBranchIsSilent;
begin
  // Eine gleichnamige nicht abstrakte Überladung kann den Rumpf haben.
  Silent(Formen('    procedure Zeichnen; overload; virtual; abstract;'#10 +
    '    procedure Zeichnen(AFarbe: Integer); overload;'#10,
    'procedure TForm.Zeichnen(AFarbe: Integer);'#10'begin'#10'end;'#10#10));
  // abstract nur im anderen Zweig.
  Silent(Formen('  {$IFDEF ABSTRAKT}'#10'    procedure Zeichnen; virtual; abstract;'#10'  {$ELSE}'#10 +
    '    procedure Zeichnen; virtual;'#10'  {$ENDIF}'#10,
    '{$IFNDEF ABSTRAKT}'#10'procedure TForm.Zeichnen;'#10'begin'#10'end;'#10'{$ENDIF}'#10#10));
  // Ein Rumpf ohne Klassenpräfix gehört zu keiner Methode.
  Silent(Formen('    procedure Zeichnen; virtual; abstract;'#10, 'procedure Zeichnen;'#10'begin'#10'end;'#10#10));
end;

procedure TMethodDirectiveRulesTests.FinalWithoutVirtual;
begin
  Assert.AreEqual('final nur an virtuellen Methoden; Speichern ist nicht virtual, dynamic oder override ' +
    '(wie E2351).', OnlyMessage(Formen('    procedure Speichern; final;'#10, 'procedure TForm.Speichern;'#10 +
    'begin'#10'end;'#10#10)));
  Assert.AreEqual('Flaeche ist abstract und final zugleich; eine abstrakte Methode muss sich überschreiben ' +
    'lassen (wie E2371).', OnlyMessage(Formen('    function Flaeche: Double; virtual; abstract; final;'#10, '')));
end;

procedure TMethodDirectiveRulesTests.AbstractSealedClass;
var
  Found: TArray<TRuleFinding>;
begin
  // dcc meldet dazu E2540 an der Klasse (Cm.E2383).
  Found := Findings('unit Formen;'#10'interface'#10'type'#10'  TForm = class abstract sealed'#10'  end;'#10 +
    'implementation'#10'end.');
  Assert.AreEqual(2, Integer(Length(Found)), Listed(Found));
  Assert.AreEqual('TForm ist abstract und kann deshalb nicht sealed sein (wie E2540).', Found[0].Message);
  Assert.AreEqual(3, Found[0].Range.StartPos.Line);
  Assert.AreEqual(2, Found[0].Range.StartPos.Character);
  Assert.AreEqual('Eine Klasse ist entweder abstract oder sealed, nicht beides (wie E2383).', Found[1].Message);
  Assert.AreEqual(3, Found[1].Range.StartPos.Line);
  Assert.AreEqual(25, Found[1].Range.StartPos.Character);
  Found := Findings('unit Formen;'#10'interface'#10'type'#10'  TForm = class sealed abstract(TObject)'#10 +
    '  end;'#10'implementation'#10'end.');
  Assert.AreEqual('3: TForm ist abstract und kann deshalb nicht sealed sein (wie E2540).'#10 +
    '3: Eine Klasse ist entweder abstract oder sealed, nicht beides (wie E2383).'#10, Listed(Found));
end;

procedure TMethodDirectiveRulesTests.SealedWithOwnAbstractMethod;
begin
  // Cm.E2540: E2383 an der Methode, E2539 und E2540 an der Klasse.
  Assert.AreEqual('4: TKlasse ist sealed und implementiert die abstrakte Methode TKlasse.Machen nicht (wie E2539).'#10 +
    '4: TKlasse hat abstrakte Methoden und kann deshalb nicht sealed sein; kein Nachfahre könnte sie ' +
    'implementieren (wie E2540).'#10 +
    '6: Machen ist abstract, die Klasse TKlasse aber sealed; abstract und sealed schließen sich aus (wie E2383).'#10,
    Listed(Findings('unit Formen;'#10#10'interface'#10'type'#10'  TKlasse = class sealed'#10'  public'#10 +
    '    procedure Machen; virtual; abstract;'#10'  end;'#10'implementation'#10'end.')));
end;

procedure TMethodDirectiveRulesTests.SealedInheritsAbstractMethod;
begin
  // Cm.E2539: Die geerbte abstrakte Methode bleibt offen.
  Assert.AreEqual('8: TVersiegelt ist sealed und implementiert die abstrakte Methode TAbstrakt.Machen nicht ' +
    '(wie E2539).'#10 +
    '8: TVersiegelt hat abstrakte Methoden und kann deshalb nicht sealed sein; kein Nachfahre könnte sie ' +
    'implementieren (wie E2540).'#10,
    Listed(Findings('unit Formen;'#10'interface'#10'type'#10'  TAbstrakt = class'#10'  public'#10 +
    '    procedure Machen; virtual; abstract;'#10'    procedure Zeigen(A: Integer); virtual; abstract;'#10 +
    '  end;'#10'  TVersiegelt = class sealed(TAbstrakt)'#10'  public'#10 +
    '    procedure Zeigen(A: Integer); override;'#10'  end;'#10'implementation'#10#10 +
    'procedure TVersiegelt.Zeigen(A: Integer);'#10'begin'#10'end;'#10#10'end.')));
end;

procedure TMethodDirectiveRulesTests.SealedImplementingAllIsSilent;
begin
  Silent('unit Formen;'#10'interface'#10'type'#10'  TAbstrakt = class'#10'  public'#10 +
    '    procedure Machen; virtual; abstract;'#10'  end;'#10'  TMitte = class(TAbstrakt)'#10'  public'#10 +
    '    procedure Machen; override;'#10'  end;'#10'  TVersiegelt = class sealed(TMitte)'#10'  end;'#10 +
    '  TFrei = class sealed'#10'    procedure Laufen; virtual;'#10'  end;'#10'implementation'#10#10 +
    'procedure TMitte.Machen;'#10'begin'#10'end;'#10#10'procedure TFrei.Laufen;'#10'begin'#10'end;'#10#10'end.');
end;

procedure TMethodDirectiveRulesTests.StaticOnInstanceOrVirtual;
begin
  Assert.AreEqual('static nur an Klassenmethoden; Neu ist eine Instanzmethode (wie E2376).',
    OnlyMessage(Formen('    function Neu: TForm; static;'#10, '')));
  Assert.AreEqual('static nur an nicht virtuellen Klassenmethoden; Neu ist virtuell (wie E2376).',
    OnlyMessage(Formen('    class function Neu: TForm; virtual; static;'#10, '')));
end;

procedure TMethodDirectiveRulesTests.Options;
var
  Source: string;
begin
  Source := Formen('    function Flaeche: Double; abstract;'#10, '');
  Assert.AreEqual(1, Integer(Length(Findings(Source, '', 'Source/Formen.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"abstract-declaration-invalid": "off"}}',
    'Source/Formen.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"group:compiler": "off"}}', 'Source/Formen.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source,
    '{"rules": {"abstract-declaration-invalid": {"exclude": ["Source/*.pas"]}}}', 'Source/Formen.pas'))));
  Assert.AreEqual(1, Integer(Length(Findings(Source,
    '{"rules": {"abstract-declaration-invalid": {"exclude": ["Alt/*.pas"]}}}', 'Source/Formen.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TMethodDirectiveRulesTests);

end.
