unit Atlas.Common.Rules.Builtin.PropertyRedeclaration.Tests;

// Tests der Regel property-redeclaration-invalid (#1074) aus
// Rules.Builtin.Properties: property Caption; ohne Property im Vorfahren
// (E2147) samt Korrektur auf den ähnlichsten Namen, nicht erreichbare
// Property (E2233), Vorfahren aus dem Index und Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPropertyRedeclarationRulesTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure WithoutSuggestion;
    [Test]
    procedure InaccessibleProperty;
    [Test]
    procedure SilentCases;
    [Test]
    procedure AncestorFromIndex;
    [Test]
    procedure Options;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Properties,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit TCustomPanel (ABase) und TMeinPanel = class(TCustomPanel) (AOwn).</summary>
function Panels(const ABase, AOwn: string): string;
begin
  Result := 'unit Panels;'#10'interface'#10'type'#10'  TCustomPanel = class'#10 + ABase + '  end;'#10 +
    '  TMeinPanel = class(TCustomPanel)'#10 + AOwn + '  end;'#10'implementation'#10'end.';
end;

const
  Basis = '  private'#10'    FCaption: string;'#10'    FGeheim: Integer;'#10'    property Geheim: Integer read FGeheim;'#10 +
    '  protected'#10'    property Caption: string read FCaption write FCaption;'#10 +
    '    property Color: Integer read FGeheim;'#10;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TPropertyRedeclarationInvalidRule.Create, ASource);
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TPropertyRedeclarationInvalidRule.Create, ASource, AConfig, APath);
end;

function Join(const AFound: TArray<TRuleFinding>): string;
var
  Finding: TRuleFinding;
begin
  Result := '';
  for Finding in AFound do
    Result := Result + ' | ' + Finding.Message;
end;

function OnlyMessage(const ASource: string): string;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(ASource);
  Assert.AreEqual(1, Integer(Length(Found)), ASource + Join(Found));
  Result := Found[0].Message;
end;

procedure Silent(const ASource: string);
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(ASource);
  Assert.AreEqual(0, Integer(Length(Found)), ASource + Join(Found));
end;

/// <summary>Wendet Edits an, die jeweils innerhalb einer Zeile liegen (Zeilen aus #10), von hinten nach vorn.</summary>
function ApplyFix(const AText: string; const AFix: TRuleFix): string;
var
  Lines: TArray<string>;
  Index: Integer;
  Edit: TRuleEdit;
begin
  Lines := AText.Split([#10]);
  for Index := High(AFix.Edits) downto 0 do
  begin
    Edit := AFix.Edits[Index];
    Lines[Edit.Range.StartPos.Line] := Copy(Lines[Edit.Range.StartPos.Line], 1, Edit.Range.StartPos.Character) +
      Edit.NewText + Copy(Lines[Edit.Range.StartPos.Line], Edit.Range.EndPos.Character + 1, MaxInt);
  end;
  Result := string.Join(#10, Lines);
end;

{ TPropertyRedeclarationRulesTests }

procedure TPropertyRedeclarationRulesTests.IssueExample;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Panels(Basis, '  published'#10'    property Captoin;'#10);
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)), Join(Found));
  Assert.AreEqual('TCustomPanel hat keine Property Captoin; gemeint ist Caption (wie E2147).', Found[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Found[0].Confidence));
  Assert.AreEqual(14, Found[0].Range.StartPos.Line);
  Assert.AreEqual(13, Found[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Caption verwenden', Found[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.AreEqual(Panels(Basis, '  published'#10'    property Caption;'#10), Fixed);
  Silent(Fixed);
end;

procedure TPropertyRedeclarationRulesTests.WithoutSuggestion;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Panels(Basis, '  published'#10'    property Beschriftung default 0;'#10));
  Assert.AreEqual(1, Integer(Length(Found)), Join(Found));
  Assert.AreEqual('TCustomPanel hat keine Property Beschriftung (wie E2147).', Found[0].Message);
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  // Ohne Vorfahr: TObject hat keine Properties.
  Assert.AreEqual('TObject hat keine Property Caption (wie E2147).', OnlyMessage('unit Panels;'#10'interface'#10 +
    'type'#10'  TPanel = class'#10'  published'#10'    property Caption;'#10'  end;'#10'implementation'#10'end.'));
end;

procedure TPropertyRedeclarationRulesTests.InaccessibleProperty;
var
  Index: ISymbolIndex;
  Found: TArray<TRuleFinding>;
begin
  // private einer anderen Unit sieht der Nachfahre nicht, strict private nie.
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Basis;'#10'interface'#10'type'#10'  TFern = class'#10 +
    '  private'#10'    FWert: Integer;'#10'    property Wert: Integer read FWert;'#10'  strict private'#10 +
    '    property Streng: Integer read FWert;'#10'  protected'#10'    property Offen: Integer read FWert;'#10 +
    '  end;'#10'implementation'#10'end.', 'C:\Projekt\Basis.pas', nil));
  Found := TRuleAssert.IndexFindings(TPropertyRedeclarationInvalidRule.Create, 'unit Panels;'#10'interface'#10 +
    'uses'#10'  Basis;'#10'type'#10'  TNah = class(TFern)'#10'  public'#10'    property Wert;'#10 +
    '    property Streng;'#10'    property Offen;'#10'  end;'#10'implementation'#10'end.', Index, '', '');
  Assert.AreEqual(2, Integer(Length(Found)), Join(Found));
  Assert.AreEqual('Die Property Wert von TFern ist hier nicht erreichbar (wie E2233).', Found[0].Message);
  Assert.AreEqual('Die Property Streng von TFern ist hier nicht erreichbar (wie E2233).', Found[1].Message);
  // private derselben Unit ist erreichbar.
  Silent(Panels(Basis, '  public'#10'    property Geheim;'#10));
end;

procedure TPropertyRedeclarationRulesTests.SilentCases;
begin
  // Vorhandene Properties (auch mit default), Properties mit Typ, unbekannter Vorfahr, Feld gleichen Namens.
  Silent(Panels(Basis, '  published'#10'    property Caption;'#10'    property Color default 0;'#10 +
    '    property Neu: Integer read FNeu;'#10));
  Silent('unit Panels;'#10'interface'#10'type'#10'  TMeinPanel = class(TFremd)'#10'  published'#10 +
    '    property Captoin;'#10'  end;'#10'implementation'#10'end.');
  Silent(Panels('  protected'#10'    Hoehe: Integer;'#10, '  published'#10'    property Hoehe;'#10));
  // Die Property steht nur in einem inaktiven Zweig des Vorfahren.
  Silent(Panels('  {$IFDEF ALT}'#10'  protected'#10'    property Breite: Integer read FB;'#10'  {$ENDIF}'#10,
    '  published'#10'    property Breite;'#10));
end;

procedure TPropertyRedeclarationRulesTests.AncestorFromIndex;
var
  Index: ISymbolIndex;
  Found: TArray<TRuleFinding>;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Steuer;'#10'interface'#10'type'#10'  TControl = class'#10 +
    '  protected'#10'    property Caption: string read FCaption;'#10'    property Align: Integer read FAlign;'#10 +
    '  end;'#10'  TCustomPanel = class(TControl)'#10'  end;'#10'implementation'#10'end.',
    'C:\Projekt\Steuer.pas', nil));
  Found := TRuleAssert.IndexFindings(TPropertyRedeclarationInvalidRule.Create, 'unit Panels;'#10'interface'#10 +
    'uses'#10'  Steuer;'#10'type'#10'  TMeinPanel = class(TCustomPanel)'#10'  published'#10 +
    '    property Caption;'#10'    property Aling;'#10'  end;'#10'implementation'#10'end.', Index, '', '');
  Assert.AreEqual(1, Integer(Length(Found)), Join(Found));
  Assert.AreEqual('TCustomPanel hat keine Property Aling; gemeint ist Align (wie E2147).', Found[0].Message);
end;

procedure TPropertyRedeclarationRulesTests.Options;
var
  Source: string;
begin
  Source := Panels(Basis, '  published'#10'    property Captoin;'#10);
  Assert.AreEqual(1, Integer(Length(Findings(Source, '', 'Source/Panels.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"property-redeclaration-invalid": "off"}}',
    'Source/Panels.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"group:compiler": "off"}}', 'Source/Panels.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source,
    '{"rules": {"property-redeclaration-invalid": {"exclude": ["Source/*.pas"]}}}', 'Source/Panels.pas'))));
  Assert.AreEqual(1, Integer(Length(Findings(Source,
    '{"rules": {"property-redeclaration-invalid": {"exclude": ["Alt/*.pas"]}}}', 'Source/Panels.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TPropertyRedeclarationRulesTests);

end.
