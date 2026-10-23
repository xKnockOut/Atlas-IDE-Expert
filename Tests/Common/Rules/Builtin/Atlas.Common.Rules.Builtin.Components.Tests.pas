unit Atlas.Common.Rules.Builtin.Components.Tests;

// Tests für die Komponentenregeln (#55, Teil A) und missing-inherited (#919) sowie message-handler-without-inherited (#949).
// inherited-order (#1049): Destruktor mit Korrektur, Threads, Konstruktor mit geerbter Property, stille Fälle,
// Abschalten.
// inherited-wrong-method (#1050): Beispiel mit Korrektur, Argumente, Option allowed samt Parser, stille Fälle,
// Abschalten.
// getter-side-effect (#1052): Beispiel, Arten der Änderung, geerbte Felder, Lazy-Initialisierung mit Option
// allowLazyInit samt Parser, stille Fälle, Abschalten.
// equals-without-gethashcode (#1053): Beispiel mit Korrektur, Gegenrichtung, Vorfahren, Records als Schlüssel,
// Hashausdrücke, Abschalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TComponentRulesTests = class
  public
    [Test]
    procedure LoadedWithoutInheritedIsHigh;
    [Test]
    procedure PaintWithoutInheritedIsLow;
    [Test]
    procedure DestroyGetsInheritedAtEnd;
    [Test]
    procedure InheritedPresentIsSilent;
    [Test]
    procedure NonComponentIsSilent;
    [Test]
    procedure DefaultMismatchReplacesValue;
    [Test]
    procedure DefaultMatchingIsSilent;
    [Test]
    procedure SetterWithoutFreeNotificationReports;
    [Test]
    procedure FreeNotificationAndSubcomponentAreSilent;
    [Test]
    procedure SetterWithoutInvalidateReports;
    [Test]
    procedure SetterWithInvalidateOrUnpaintedFieldIsSilent;
    [Test]
    procedure FixedPixelsOncePerCall;
    [Test]
    procedure ScaledAndTrivialPixelsAreSilent;
    [Test]
    procedure HexColorReportsSystemColorSilent;
    /// <summary>Alle sechs Regeln in einem Lauf teilen das Komponentenmodell (Review P-03).</summary>
    [Test]
    procedure AllComponentRulesShareModelInOneRun;
    [Test]
    procedure MissingInheritedIssueExample;
    [Test]
    procedure MissingInheritedConstructor;
    [Test]
    procedure MissingInheritedSilentCases;
    [Test]
    procedure MissingInheritedComponentsNoDoubleReport;
    [Test]
    procedure MissingInheritedMethodsOptionOffAndExclude;
    [Test]
    procedure MessageHandlerIssueExample;
    [Test]
    procedure MessageHandlerSilentCases;
    [Test]
    procedure MessageHandlerConsequences;
    [Test]
    procedure MessageHandlerSwallowOffAndExclude;
  end;

  [TestFixture]
  TInheritedOrderTests = class
  public
    [Test]
    procedure DestructorIssueExampleWithFix;
    [Test]
    procedure DestructorSilentCases;
    [Test]
    procedure ConstructorAccessBeforeInherited;
    [Test]
    procedure ConstructorSilentCases;
    [Test]
    procedure OffAndExclude;
  end;

  [TestFixture]
  TInheritedWrongMethodTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure ArgumentsDecideFix;
    [Test]
    procedure SilentCases;
    [Test]
    procedure AllowedOption;
    [Test]
    procedure OffAndExclude;
  end;

  [TestFixture]
  TGetterSideEffectTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure KindsOfChange;
    [Test]
    procedure InheritedField;
    [Test]
    procedure LazyInitOption;
    [Test]
    procedure SilentCases;
    [Test]
    procedure OffAndExclude;
  end;

  [TestFixture]
  TEqualsWithoutGetHashCodeTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure GetHashCodeWithoutEquals;
    [Test]
    procedure AncestorsAndSilentCases;
    [Test]
    procedure FixNeedsEqualsBodyWithFields;
    [Test]
    procedure RecordKeys;
    [Test]
    procedure HashExpressions;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.Components,
  Atlas.Tests.RuleAssert;

const
  LowConfidence = '{"minConfidence": "low"}';

/// <summary>Unit mit TFoo = class(TCustomControl), den Mitgliedern AMembers und den
/// Implementierungen AImpl.</summary>
function ControlUnit(const AMembers, AImpl: string; const AHead: string = 'TFoo = class(TCustomControl)'): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  ' + AHead + #10 + AMembers + #10'  end;'#10 +
    'implementation'#10 + AImpl + #10'end.';
end;

/// <summary>Wendet die Änderungen der ersten Korrektur an (Zeilen mit #10).</summary>
function ApplyFix(const AText: string; const AFix: TRuleFix): string;
var
  Index: Integer;
  Edit: TRuleEdit;

  function OffsetOf(const APosition: TTextPosition): Integer;
  var
    Line, Position: Integer;
  begin
    Position := 0;
    for Line := 1 to APosition.Line do
      Position := Pos(#10, AText, Position + 1);
    Result := Position + APosition.Character;
  end;

begin
  Result := AText;
  for Index := High(AFix.Edits) downto 0 do
  begin
    Edit := AFix.Edits[Index];
    Result := Copy(Result, 1, OffsetOf(Edit.Range.StartPos)) + Edit.NewText +
      Copy(Result, OffsetOf(Edit.Range.EndPos) + 1, MaxInt);
  end;
end;

procedure TComponentRulesTests.LoadedWithoutInheritedIsHigh;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := ControlUnit('  protected'#10'    procedure Loaded; override;',
    'procedure TFoo.Loaded;'#10'begin'#10'  Layout;'#10'end;');
  Findings := TRuleAssert.Findings(TComponentMissingInheritedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(8, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(ControlUnit('  protected'#10'    procedure Loaded; override;',
    'procedure TFoo.Loaded;'#10'begin'#10'  inherited;'#10'  Layout;'#10'end;'), ApplyFix(Source, Findings[0].Fixes[0]));
end;

procedure TComponentRulesTests.PaintWithoutInheritedIsLow;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := ControlUnit('  protected'#10'    procedure Paint; override;',
    'procedure TFoo.Paint;'#10'begin'#10'  Draw;'#10'end;');
  // Unter der Vorgabe minConfidence medium fällt der Treffer weg.
  TRuleAssert.Silent(TComponentMissingInheritedRule.Create, Source);
  Findings := TRuleAssert.Findings(TComponentMissingInheritedRule.Create, Source, LowConfidence);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(Findings[0].Confidence));
end;

procedure TComponentRulesTests.DestroyGetsInheritedAtEnd;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := ControlUnit('  public'#10'    destructor Destroy; override;',
    'destructor TFoo.Destroy;'#10'begin'#10'  FList.Free'#10'end;');
  Findings := TRuleAssert.Findings(TComponentMissingInheritedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(ControlUnit('  public'#10'    destructor Destroy; override;',
    'destructor TFoo.Destroy;'#10'begin'#10'  FList.Free;'#10'  inherited;'#10'end;'),
    ApplyFix(Source, Findings[0].Fixes[0]));
end;

procedure TComponentRulesTests.InheritedPresentIsSilent;
begin
  TRuleAssert.Silent(TComponentMissingInheritedRule.Create, ControlUnit(
    '  protected'#10'    procedure Notification(AComponent: TComponent; Operation: TOperation); override;',
    'procedure TFoo.Notification(AComponent: TComponent; Operation: TOperation);'#10'begin'#10 +
    '  inherited Notification(AComponent, Operation);'#10'end;'));
  // Ohne override (eigene, neue Methode) keine Aussage.
  TRuleAssert.Silent(TComponentMissingInheritedRule.Create, ControlUnit('  protected'#10'    procedure Loaded;',
    'procedure TFoo.Loaded;'#10'begin'#10'end;'));
end;

procedure TComponentRulesTests.NonComponentIsSilent;
begin
  TRuleAssert.Silent(TComponentMissingInheritedRule.Create, ControlUnit('  protected'#10'    procedure Loaded; override;',
    'procedure TFoo.Loaded;'#10'begin'#10'end;', 'TFoo = class(TUnbekannt)'));
end;

const
  SizeMembers = '  private'#10'    FSize: Integer;'#10'  public'#10'    constructor Create(AOwner: TComponent); override;'#10 +
    '  published'#10'    property Size: Integer read FSize write FSize default 5;';

procedure TComponentRulesTests.DefaultMismatchReplacesValue;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := ControlUnit(SizeMembers, 'constructor TFoo.Create(AOwner: TComponent);'#10'begin'#10 +
    '  inherited Create(AOwner);'#10'  FSize := 10;'#10'end;');
  Findings := TRuleAssert.Findings(TComponentDefaultMismatchRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('10', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(9, Findings[0].Range.StartPos.Line);
end;

procedure TComponentRulesTests.DefaultMatchingIsSilent;
begin
  TRuleAssert.Silent(TComponentDefaultMismatchRule.Create, ControlUnit(SizeMembers,
    'constructor TFoo.Create(AOwner: TComponent);'#10'begin'#10'  inherited Create(AOwner);'#10'  Self.FSize := $5;'#10'end;'));
  // Wert aus einer Berechnung: keine Aussage.
  TRuleAssert.Silent(TComponentDefaultMismatchRule.Create, ControlUnit(SizeMembers,
    'constructor TFoo.Create(AOwner: TComponent);'#10'begin'#10'  inherited Create(AOwner);'#10 +
    '  FSize := Basis + 1;'#10'end;'));
end;

const
  LinkMembers = '  private'#10'    FLink: TControl;'#10'    procedure SetLink(const Value: TControl);'#10 +
    '  published'#10'    property Link: TControl read FLink write SetLink;';

procedure TComponentRulesTests.SetterWithoutFreeNotificationReports;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := ControlUnit(LinkMembers, 'procedure TFoo.SetLink(const Value: TControl);'#10'begin'#10 +
    '  FLink := Value;'#10'end;');
  Findings := TRuleAssert.Findings(TComponentMissingFreeNotificationRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual(ControlUnit(LinkMembers, 'procedure TFoo.SetLink(const Value: TControl);'#10'begin'#10 +
    '  FLink := Value;'#10'  if Value <> nil then Value.FreeNotification(Self);'#10'end;'),
    ApplyFix(Source, Findings[0].Fixes[0]));
end;

procedure TComponentRulesTests.FreeNotificationAndSubcomponentAreSilent;
begin
  TRuleAssert.Silent(TComponentMissingFreeNotificationRule.Create, ControlUnit(LinkMembers,
    'procedure TFoo.SetLink(const Value: TControl);'#10'begin'#10'  FLink := Value;'#10 +
    '  if Value <> nil then Value.FreeNotification(Self);'#10'end;'));
  TRuleAssert.Silent(TComponentMissingFreeNotificationRule.Create, ControlUnit(LinkMembers,
    'constructor TFoo.Create(AOwner: TComponent);'#10'begin'#10'  inherited Create(AOwner);'#10 +
    '  FLink := TControl.Create(Self);'#10'end;'#10'procedure TFoo.SetLink(const Value: TControl);'#10'begin'#10 +
    '  FLink.Assign(Value);'#10'end;'));
  // Kein Komponententyp
  TRuleAssert.Silent(TComponentMissingFreeNotificationRule.Create, ControlUnit(SizeMembers, ''));
end;

const
  ColorMembers = '  private'#10'    FFill: TColor;'#10'    procedure SetFill(const Value: TColor);'#10 +
    '  protected'#10'    procedure Paint; override;'#10'  published'#10 +
    '    property Fill: TColor read FFill write SetFill;';
  PaintFill = 'procedure TFoo.Paint;'#10'begin'#10'  inherited;'#10'  Canvas.Brush.Color := FFill;'#10'end;'#10;

procedure TComponentRulesTests.SetterWithoutInvalidateReports;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := ControlUnit(ColorMembers, PaintFill + 'procedure TFoo.SetFill(const Value: TColor);'#10'begin'#10 +
    '  FFill := Value;'#10'end;');
  Findings := TRuleAssert.Findings(TComponentSetterWithoutInvalidateRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual('Invalidate;', Trim(Findings[0].Fixes[0].Edits[0].NewText));
end;

procedure TComponentRulesTests.SetterWithInvalidateOrUnpaintedFieldIsSilent;
begin
  TRuleAssert.Silent(TComponentSetterWithoutInvalidateRule.Create, ControlUnit(ColorMembers, PaintFill +
    'procedure TFoo.SetFill(const Value: TColor);'#10'begin'#10'  if FFill <> Value then'#10'  begin'#10 +
    '    FFill := Value;'#10'    Invalidate;'#10'  end;'#10'end;'));
  // Paint liest das Feld nicht.
  TRuleAssert.Silent(TComponentSetterWithoutInvalidateRule.Create, ControlUnit(ColorMembers,
    'procedure TFoo.Paint;'#10'begin'#10'  inherited;'#10'end;'#10 +
    'procedure TFoo.SetFill(const Value: TColor);'#10'begin'#10'  FFill := Value;'#10'end;'));
end;

const
  PaintMembers = '  protected'#10'    procedure Paint; override;';

function PaintUnit(const ABody: string): string;
begin
  Result := ControlUnit(PaintMembers, 'procedure TFoo.Paint;'#10'begin'#10'  inherited;'#10 + ABody + #10'end;');
end;

procedure TComponentRulesTests.FixedPixelsOncePerCall;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := PaintUnit('  Canvas.FillRect(Rect(0, 0, 16, 16));');
  Findings := TRuleAssert.Findings(TComponentFixedPixelsRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual(PaintUnit('  Canvas.FillRect(Rect(0, 0, ScaleValue(16), ScaleValue(16)));'),
    ApplyFix(Source, Findings[0].Fixes[0]));
end;

procedure TComponentRulesTests.ScaledAndTrivialPixelsAreSilent;
begin
  TRuleAssert.Silent(TComponentFixedPixelsRule.Create, PaintUnit(
    '  Canvas.Pen.Width := 1;'#10'  Canvas.FillRect(Rect(0, 0, ScaleValue(16), MulDiv(16, CurrentPPI, 96)));'#10 +
    '  X := Width div 2;'#10'  Canvas.Font.Size := 10;'#10'  Canvas.Brush.Color := $00FF8000;'#10 +
    // Eigene Skalierhelfer (#647).
    '  Canvas.FillRect(Rect(Scale(3), 0, ScaleDpi(16), Self.Scale(16)));'));
end;

procedure TComponentRulesTests.HexColorReportsSystemColorSilent;
begin
  TRuleAssert.Reports(TComponentHardcodedColorRule.Create, PaintUnit('  Canvas.Brush.Color := $00FF8000;'));
  TRuleAssert.Reports(TComponentHardcodedColorRule.Create, PaintUnit('  Canvas.Pen.Color := RGB(255, 128, 0);'));
  TRuleAssert.Silent(TComponentHardcodedColorRule.Create, PaintUnit('  Canvas.Brush.Color := clBtnFace;'));
  TRuleAssert.Reports(TComponentHardcodedColorRule.Create, PaintUnit('  Canvas.Pen.Color := TColor($00FF8000);'));
  // Farben des Themas, nur in TColor umgewandelt bzw. gemischt (#1109).
  TRuleAssert.Silent(TComponentHardcodedColorRule.Create, PaintUnit('  Canvas.Brush.Color := TColor(FColors.Surface);'#10 +
    '  Canvas.Pen.Color := RGB(R, G, B);'));
end;

procedure TComponentRulesTests.AllComponentRulesShareModelInOneRun;
var
  Source: string;
  Count: Integer;
begin
  Source := ControlUnit(SizeMembers + #10 + LinkMembers + #10 +
    '  protected'#10'    procedure Loaded; override;'#10'    procedure Paint; override;',
    'constructor TFoo.Create(AOwner: TComponent);'#10'begin'#10'  inherited Create(AOwner);'#10 +
    '  FSize := 10;'#10'end;'#10 +
    'procedure TFoo.SetLink(const Value: TControl);'#10'begin'#10'  FLink := Value;'#10'end;'#10 +
    'procedure TFoo.Loaded;'#10'begin'#10'  Layout;'#10'end;'#10 +
    'procedure TFoo.Paint;'#10'begin'#10'  inherited;'#10'  Canvas.FillRect(Rect(0, 0, 16, 16));'#10 +
    '  Canvas.Brush.Color := $00FF8000;'#10'end;');
  Count := TRuleAssert.SameAsSeparateRuns([TComponentMissingInheritedRule.Create,
    TComponentDefaultMismatchRule.Create, TComponentMissingFreeNotificationRule.Create,
    TComponentSetterWithoutInvalidateRule.Create, TComponentFixedPixelsRule.Create,
    TComponentHardcodedColorRule.Create], Source, LowConfidence);
  Assert.IsTrue(Count >= 5, 'Treffer mehrerer Regeln: ' + IntToStr(Count));
end;

const
  ExportUnit = 'unit U;'#10'interface'#10'type'#10'  TBasisExport = class'#10'  public'#10 +
    '    constructor Create;'#10'    destructor Destroy; override;'#10'  end;'#10 +
    '  TExport = class(TBasisExport)'#10'  public'#10'    destructor Destroy; override;'#10'  end;'#10 +
    'implementation'#10'constructor TBasisExport.Create;'#10'begin'#10'end;'#10 +
    'destructor TBasisExport.Destroy;'#10'begin'#10'  inherited;'#10'end;'#10 +
    'destructor TExport.Destroy;'#10'begin'#10'  FDatei.Free;'#10'end;'#10'end.';

procedure TComponentRulesTests.MissingInheritedIssueExample;
var
  Findings: TArray<TRuleFinding>;
  Fixed: string;
begin
  Findings := TRuleAssert.Findings(TMissingInheritedRule.Create, ExportUnit);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Destroy ruft inherited nicht auf; die Felder von TBasisExport werden nie freigegeben.',
    Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('"inherited;" einfügen', Findings[0].Fixes[0].Title);
  Fixed := ApplyFix(ExportUnit, Findings[0].Fixes[0]);
  Assert.IsTrue(Fixed.Contains('destructor TExport.Destroy;'#10'begin'#10'  FDatei.Free;'#10'  inherited;'#10'end;'),
    Fixed);
  TRuleAssert.Silent(TMissingInheritedRule.Create, Fixed);
end;

procedure TComponentRulesTests.MissingInheritedConstructor;
const
  Head = 'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10'  public'#10'    constructor Create;'#10 +
    '  end;'#10'  TKind = class(TBasis)'#10'  public'#10;
  Impl = 'implementation'#10'constructor TBasis.Create;'#10'begin'#10'end;'#10;
var
  Findings: TArray<TRuleFinding>;
  Source: string;
begin
  Source := Head + '    constructor Create;'#10'  end;'#10 + Impl +
    'constructor TKind.Create;'#10'begin'#10'  FWert := 1;'#10'end;'#10'end.';
  Findings := TRuleAssert.Findings(TMissingInheritedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Create ruft inherited nicht auf; die Felder von TBasis werden nie angelegt.', Findings[0].Message);
  Assert.IsTrue(ApplyFix(Source, Findings[0].Fixes[0]).Contains(
    'constructor TKind.Create;'#10'begin'#10'  inherited;'#10'  FWert := 1;'), ApplyFix(Source, Findings[0].Fixes[0]));
  // Eigener Konstruktor mit Parametern: inherited Create ohne Argumente.
  Source := Head + '    constructor Create(AWert: Integer);'#10'  end;'#10 + Impl +
    'constructor TKind.Create(AWert: Integer);'#10'begin'#10'  FWert := AWert;'#10'end;'#10'end.';
  Findings := TRuleAssert.Findings(TMissingInheritedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('"inherited Create;" einfügen', Findings[0].Fixes[0].Title);
  // Ruft einen anderen eigenen Konstruktor: still.
  TRuleAssert.Silent(TMissingInheritedRule.Create, Head + '    constructor Create;'#10 +
    '    constructor CreateLeer;'#10'  end;'#10 + Impl +
    'constructor TKind.Create;'#10'begin'#10'  inherited;'#10'end;'#10 +
    'constructor TKind.CreateLeer;'#10'begin'#10'  Create;'#10'  FListe := TStringList.Create;'#10'end;'#10'end.');
  // AfterConstruction ohne inherited.
  Findings := TRuleAssert.Findings(TMissingInheritedRule.Create, Head +
    '    procedure AfterConstruction; override;'#10'  end;'#10 + Impl +
    'procedure TKind.AfterConstruction;'#10'begin'#10'  Laden;'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('AfterConstruction ruft inherited nicht auf; die Arbeit von TBasis nach dem Erzeugen entfällt.',
    Findings[0].Message);
end;

procedure TComponentRulesTests.MissingInheritedSilentCases;
begin
  // Vorfahr TObject: nichts aufzurufen.
  TRuleAssert.Silent(TMissingInheritedRule.Create, 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10 +
    '  public'#10'    constructor Create;'#10'    destructor Destroy; override;'#10'  end;'#10'implementation'#10 +
    'constructor TFoo.Create;'#10'begin'#10'  FX := 1;'#10'end;'#10 +
    'destructor TFoo.Destroy;'#10'begin'#10'  FX := 0;'#10'end;'#10'end.');
  // Vorfahr ohne eigenen Konstruktor: der Konstruktor ist still.
  TRuleAssert.Silent(TMissingInheritedRule.Create, 'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10 +
    '  end;'#10'  TKind = class(TBasis)'#10'  public'#10'    constructor Create;'#10'  end;'#10'implementation'#10 +
    'constructor TKind.Create;'#10'begin'#10'  FX := 1;'#10'end;'#10'end.');
  // Destroy ohne override meldet destroy-without-override, nicht diese Regel.
  TRuleAssert.Silent(TMissingInheritedRule.Create, StringReplace(ExportUnit,
    '  TExport = class(TBasisExport)'#10'  public'#10'    destructor Destroy; override;',
    '  TExport = class(TBasisExport)'#10'  public'#10'    destructor Destroy;', []));
  // Formular ohne DFM: CreateNew ruft selbst inherited Create (#1109).
  TRuleAssert.Silent(TMissingInheritedRule.Create, 'unit U;'#10'interface'#10'uses Vcl.Forms;'#10'type'#10 +
    '  TMaske = class(TForm)'#10'  public'#10'    constructor CreateMaske(AOwner: TComponent);'#10'  end;'#10 +
    'implementation'#10'constructor TMaske.CreateMaske(AOwner: TComponent);'#10'begin'#10'  CreateNew(AOwner);'#10 +
    '  Caption := ''x'';'#10'end;'#10'end.');
end;

procedure TComponentRulesTests.MissingInheritedComponentsNoDoubleReport;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := ControlUnit('  public'#10'    constructor Create(AOwner: TComponent); override;'#10 +
    '    destructor Destroy; override;',
    'constructor TFoo.Create(AOwner: TComponent);'#10'begin'#10'  FSize := 10;'#10'end;'#10 +
    'destructor TFoo.Destroy;'#10'begin'#10'  FLink := nil;'#10'end;');
  Findings := TRuleAssert.Findings(TMissingInheritedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)), 'Destroy meldet component-missing-inherited');
  Assert.AreEqual('Create ruft inherited nicht auf; die Felder von TCustomControl werden nie angelegt.',
    Findings[0].Message);
  Assert.AreEqual('"inherited;" einfügen', Findings[0].Fixes[0].Title, 'override reicht AOwner weiter');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TComponentMissingInheritedRule.Create, Source))));
end;

procedure TComponentRulesTests.MissingInheritedMethodsOptionOffAndExclude;
var
  Issues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMissingInheritedRule.Create, ExportUnit,
    '{"rules": {"missing-inherited": {"methods": ["Create"]}}}', 'U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMissingInheritedRule.Create, ExportUnit,
    '{"rules": {"missing-inherited": {"methods": ["Destroy"]}}}', 'U.pas'))));
  Assert.AreEqual(4, Integer(Length(TMissingInheritedRule.DefaultMethods)));
  TConfigurationParser.Parse('{"rules": {"missing-inherited": {"methods": "Destroy"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"methods" muss eine Liste von Texten sein', Issues[0].Message);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMissingInheritedRule.Create, ExportUnit,
    '{"rules": {"missing-inherited": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMissingInheritedRule.Create, ExportUnit,
    '{"rules": {"missing-inherited": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMissingInheritedRule.Create, ExportUnit,
    '{"rules": {"missing-inherited": {"exclude": ["Alt/*.pas"]}}}', 'Neu/U.pas'))));
end;

function Haupt(const AMessage, ABody: string): string;
begin
  Result :=
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Winapi.Messages, Vcl.Forms;'#10 +
    'type'#10 +
    '  TfrmHaupt = class(TForm)'#10 +
    '  private'#10 +
    '    procedure WMSize(var Msg: TWMSize); message ' + AMessage + ';'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TfrmHaupt.WMSize(var Msg: TWMSize);'#10 +
    'begin'#10 +
    ABody +
    'end;'#10 +
    'end.';
end;

procedure TComponentRulesTests.MessageHandlerIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
  Tree: TSyntaxTree;
begin
  Source := Haupt('WM_SIZE', '  AnordnungAnpassen;'#10);
  Findings := TRuleAssert.Findings(TMessageHandlerWithoutInheritedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('message-handler-without-inherited', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual('WMSize ruft inherited nicht auf; die VCL passt Ausrichtung und Anker nicht mehr an.',
    Findings[0].Message);
  Assert.AreEqual(9, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(20, Findings[0].Range.StartPos.Character);
  Assert.AreEqual('"inherited;" am Anfang einfügen', Findings[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(Haupt('WM_SIZE', '  inherited;'#10'  AnordnungAnpassen;'#10), Fixed);
  Tree := TPascalParser.Parse(Fixed);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
  finally
    Tree.Free;
  end;
  TRuleAssert.Silent(TMessageHandlerWithoutInheritedRule.Create, Fixed);
end;

procedure TComponentRulesTests.MessageHandlerSilentCases;
begin
  TRuleAssert.Silent(TMessageHandlerWithoutInheritedRule.Create,
    Haupt('WM_SIZE', '  AnordnungAnpassen;'#10'  inherited WMSize(Msg);'#10));
  TRuleAssert.Silent(TMessageHandlerWithoutInheritedRule.Create,
    Haupt('WM_SIZE', '  DefaultHandler(Msg);'#10));
  TRuleAssert.Silent(TMessageHandlerWithoutInheritedRule.Create,
    Haupt('WM_SIZE', '  Msg.Result := DefWindowProc(Handle, Msg.Msg, 0, 0);'#10));
  // Vorgabe von swallow: WM_ERASEBKGND.
  TRuleAssert.Silent(TMessageHandlerWithoutInheritedRule.Create, Haupt('WM_ERASEBKGND', '  Zeichnen;'#10));
  // Der Handler beantwortet die Nachricht selbst.
  TRuleAssert.Silent(TMessageHandlerWithoutInheritedRule.Create, Haupt('WM_MOUSEACTIVATE',
    '  Msg.Result := MA_NOACTIVATE;'#10));
  // Ohne Vorfahr behandelt TObject nichts.
  TRuleAssert.Silent(TMessageHandlerWithoutInheritedRule.Create, StringReplace(Haupt('WM_SIZE',
    '  AnordnungAnpassen;'#10), 'TfrmHaupt = class(TForm)', 'TfrmHaupt = class', []));
  // Ohne message keine Meldung.
  TRuleAssert.Silent(TMessageHandlerWithoutInheritedRule.Create, StringReplace(Haupt('WM_SIZE',
    '  AnordnungAnpassen;'#10), ' message WM_SIZE;', ';', []));
end;

procedure TComponentRulesTests.MessageHandlerConsequences;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TMessageHandlerWithoutInheritedRule.Create, Haupt('WM_CLOSE', '  Speichern;'#10));
  Assert.AreEqual('WMSize ruft inherited nicht auf; das Fenster schließt nicht mehr.', Findings[0].Message);
  Findings := TRuleAssert.Findings(TMessageHandlerWithoutInheritedRule.Create,
    Haupt('Winapi.Messages.WM_PAINT', '  Zeichnen;'#10));
  Assert.AreEqual('WMSize ruft inherited nicht auf; die VCL zeichnet das Steuerelement nicht mehr.',
    Findings[0].Message);
  Assert.AreEqual('die Standardbehandlung der VCL entfällt',
    TMessageHandlerWithoutInheritedRule.Consequence('CM_TEXTCHANGED'));
  Assert.AreEqual('die Standardbehandlung von Windows bzw. der VCL entfällt',
    TMessageHandlerWithoutInheritedRule.Consequence('WM_USER_FERTIG'));
  Assert.AreEqual('Mausereignisse wie OnClick und OnMouseDown entfallen',
    TMessageHandlerWithoutInheritedRule.Consequence('WM_LBUTTONDOWN'));
end;

procedure TComponentRulesTests.MessageHandlerSwallowOffAndExclude;
var
  Source: string;
  Issues: TArray<TConfigurationIssue>;
begin
  Source := Haupt('WM_SIZE', '  AnordnungAnpassen;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMessageHandlerWithoutInheritedRule.Create, Source,
    '{"rules": {"message-handler-without-inherited": {"swallow": ["WM_SIZE"]}}}'))));
  // Eigene Liste ersetzt die Vorgabe: WM_ERASEBKGND wird dann gemeldet.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMessageHandlerWithoutInheritedRule.Create,
    Haupt('WM_ERASEBKGND', '  Zeichnen;'#10),
    '{"rules": {"message-handler-without-inherited": {"swallow": ["WM_SIZE"]}}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMessageHandlerWithoutInheritedRule.Create, Source,
    '{"rules": {"message-handler-without-inherited": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMessageHandlerWithoutInheritedRule.Create, Source,
    '{"rules": {"message-handler-without-inherited": {"exclude": ["Source/*.pas"]}}}', 'Source/Haupt.pas'))));
  TConfigurationParser.Parse('{"rules": {"message-handler-without-inherited": {"swallow": "WM_SIZE"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;

{ TInheritedOrderTests }

/// <summary>TExport erbt von TBasisExport (Property Name); ACtor und ADtor sind die Rümpfe.</summary>
function Exporte(const AParent, ACtor, ADtor: string): string;
begin
  Result := 'unit Exporte;'#10'interface'#10'type'#10'  TBasisExport = class'#10'  private'#10 +
    '    FName: string;'#10'  public'#10'    constructor Create(const AName: string);'#10 +
    '    destructor Destroy; override;'#10'    property Name: string read FName write FName;'#10'  end;'#10 +
    '  TExport = class(' + AParent + ')'#10'  private'#10'    FDatei, FPuffer: TObject;'#10'  public'#10 +
    '    constructor Create;'#10'    destructor Destroy; override;'#10'  end;'#10'implementation'#10 +
    'constructor TBasisExport.Create(const AName: string);'#10'begin'#10'end;'#10 +
    'destructor TBasisExport.Destroy;'#10'begin'#10'  inherited;'#10'end;'#10 +
    'constructor TExport.Create;'#10'begin'#10 + ACtor + 'end;'#10 +
    'destructor TExport.Destroy;'#10'begin'#10 + ADtor + 'end;'#10'end.';
end;

procedure TInheritedOrderTests.DestructorIssueExampleWithFix;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Exporte('TBasisExport', '  inherited Create(''x'');'#10, '  inherited;'#10'  FDatei.Free;'#10);
  Findings := TRuleAssert.Findings(TInheritedOrderRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('inherited-order', Findings[0].RuleId);
  Assert.AreEqual('inherited vor dem Freigeben der eigenen Felder; der Vorfahr kann noch auf FDatei zugreifen.',
    Findings[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual(32, Findings[0].Range.StartPos.Line);
  Assert.AreEqual('inherited an das Ende des Destruktors verschieben', Findings[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(Exporte('TBasisExport', '  inherited Create(''x'');'#10, '  FDatei.Free;'#10'  inherited;'#10), Fixed);
  TRuleAssert.Silent(TInheritedOrderRule.Create, Fixed);
  // FreeAndNil, Self. und inherited Destroy ebenso.
  TRuleAssert.Reports(TInheritedOrderRule.Create, Exporte('TBasisExport', '',
    '  inherited Destroy;'#10'  if True then'#10'    FreeAndNil(Self.FPuffer);'#10));
end;

procedure TInheritedOrderTests.DestructorSilentCases;
begin
  // Richtige Reihenfolge, fremde Objekte, inherited in try/finally.
  TRuleAssert.Silent(TInheritedOrderRule.Create, Exporte('TBasisExport', '', '  FDatei.Free;'#10'  inherited;'#10));
  TRuleAssert.Silent(TInheritedOrderRule.Create, Exporte('TBasisExport', '', '  inherited;'#10'  Protokoll.Free;'#10));
  TRuleAssert.Silent(TInheritedOrderRule.Create, Exporte('TBasisExport', '',
    '  try'#10'    FDatei.Free;'#10'  finally'#10'    inherited;'#10'  end;'#10));
  // Threads warten in Destroy auf das Ende von Execute: dort gehört inherited an den Anfang.
  TRuleAssert.Silent(TInheritedOrderRule.Create, Exporte('TThread', '', '  inherited;'#10'  FDatei.Free;'#10));
end;

procedure TInheritedOrderTests.ConstructorAccessBeforeInherited;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Exporte('TBasisExport', '  Name := ''Export'';'#10'  inherited Create(''x'');'#10, '  inherited;'#10);
  Findings := TRuleAssert.Findings(TInheritedOrderRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Create greift vor inherited auf Name aus TBasisExport zu; der Vorfahr ist noch nicht angelegt.',
    Findings[0].Message);
  Assert.AreEqual(28, Findings[0].Range.StartPos.Line);
  Assert.AreEqual('inherited an den Anfang des Konstruktors verschieben', Findings[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(Exporte('TBasisExport', '  inherited Create(''x'');'#10'  Name := ''Export'';'#10, '  inherited;'#10),
    Fixed);
  TRuleAssert.Silent(TInheritedOrderRule.Create, Fixed);
  // Self.FName ebenso; inherited Create mit vorher gesetzter lokaler Variable: ohne Korrektur.
  Findings := TRuleAssert.Findings(TInheritedOrderRule.Create, StringReplace(Exporte('TBasisExport',
    '  Text := Self.FName;'#10'  inherited Create(Text);'#10, ''), 'constructor TExport.Create;'#10'begin',
    'constructor TExport.Create;'#10'var'#10'  Text: string;'#10'begin', []));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TInheritedOrderTests.ConstructorSilentCases;
begin
  // Eigene Felder vor inherited setzen ist üblich und erlaubt.
  TRuleAssert.Silent(TInheritedOrderRule.Create, Exporte('TBasisExport',
    '  FDatei := nil;'#10'  inherited Create(''x'');'#10'  Name := ''Export'';'#10, ''));
  // Parameter, lokale Variablen und unbekannte Vorfahren.
  TRuleAssert.Silent(TInheritedOrderRule.Create, Exporte('TUnbekannt',
    '  Name := ''Export'';'#10'  inherited Create(''x'');'#10, ''));
  TRuleAssert.Silent(TInheritedOrderRule.Create, StringReplace(Exporte('TBasisExport',
    '  Name := ''Export'';'#10'  inherited Create(Name);'#10, ''), 'constructor TExport.Create;'#10'begin',
    'constructor TExport.Create;'#10'var'#10'  Name: string;'#10'begin', []));
end;

procedure TInheritedOrderTests.OffAndExclude;
var
  Source: string;
begin
  Source := Exporte('TBasisExport', '', '  inherited;'#10'  FDatei.Free;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInheritedOrderRule.Create, Source,
    '{"rules": {"inherited-order": "off"}}', 'Source/Exporte.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInheritedOrderRule.Create, Source,
    '{"rules": {"inherited-order": {"exclude": ["Source/*.pas"]}}}', 'Source/Exporte.pas'))));
end;

{ TInheritedWrongMethodTests }

/// <summary>TKundenForm überschreibt Speichern und Laden von TBasisForm; ADecl ergänzt die Klasse.</summary>
function Kundenform(const ABody, ADecl, AMore: string): string;
begin
  Result := 'unit Kundenform;'#10'interface'#10'type'#10'  TBasisForm = class'#10'  public'#10 +
    '    procedure Speichern; virtual;'#10'    procedure Laden; virtual;'#10 +
    '    procedure Schreiben(const AName: string); virtual;'#10'  end;'#10 +
    '  TKundenForm = class(TBasisForm)'#10'  public'#10'    procedure Speichern; override;'#10 +
    '    procedure Laden; override;'#10 + ADecl + '  end;'#10'implementation'#10 +
    'procedure TKundenForm.Speichern;'#10'begin'#10 + ABody + 'end;'#10 +
    'procedure TKundenForm.Laden;'#10'begin'#10'  inherited;'#10'end;'#10 + AMore + 'end.';
end;

procedure TInheritedWrongMethodTests.IssueExampleWithFix;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Kundenform('  inherited Laden;'#10'  Protokollieren;'#10, '', '');
  Findings := TRuleAssert.Findings(TInheritedWrongMethodRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('inherited-wrong-method', Findings[0].RuleId);
  Assert.AreEqual('Speichern ruft inherited Laden auf; gemeint ist vermutlich inherited Speichern.',
    Findings[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(17, Findings[0].Range.StartPos.Line);
  Assert.AreEqual('inherited Speichern aufrufen', Findings[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(Kundenform('  inherited Speichern;'#10'  Protokollieren;'#10, '', ''), Fixed);
  TRuleAssert.Silent(TInheritedWrongMethodRule.Create, Fixed);
end;

procedure TInheritedWrongMethodTests.ArgumentsDecideFix;
var
  Findings: TArray<TRuleFinding>;
begin
  // Andere Zahl an Argumenten als Parameter: Meldung ohne Korrektur.
  Findings := TRuleAssert.Findings(TInheritedWrongMethodRule.Create,
    Kundenform('  inherited Schreiben(''x'');'#10, '', ''));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Gleiche Zahl: Korrektur behält die Argumente.
  Findings := TRuleAssert.Findings(TInheritedWrongMethodRule.Create, Kundenform('  inherited;'#10,
    '    procedure Schreiben(const AName: string); override;'#10,
    'procedure TKundenForm.Schreiben(const AName: string);'#10'begin'#10'  inherited Laden;'#10 +
    '  inherited Speichern();'#10'end;'#10));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual(0, Integer(Length(Findings[1].Fixes)));
end;

procedure TInheritedWrongMethodTests.SilentCases;
begin
  // Ruft auch sich selbst geerbt auf: der zweite Aufruf ist gewollt.
  TRuleAssert.Silent(TInheritedWrongMethodRule.Create, Kundenform('  inherited;'#10'  inherited Laden;'#10, '', ''));
  // Property über inherited ohne Klammern, nicht überschriebene Methode, Konstruktoren.
  TRuleAssert.Silent(TInheritedWrongMethodRule.Create, Kundenform('  inherited;'#10'  X := inherited Caption;'#10,
    '', ''));
  TRuleAssert.Silent(TInheritedWrongMethodRule.Create, Kundenform('  inherited;'#10,
    '    procedure Neu;'#10'    constructor Create;'#10, 'procedure TKundenForm.Neu;'#10'begin'#10 +
    '  inherited Laden;'#10'end;'#10'constructor TKundenForm.Create;'#10'begin'#10'  inherited CreateNew(nil);'#10 +
    'end;'#10));
end;

procedure TInheritedWrongMethodTests.AllowedOption;
var
  Source: string;
  Issues: TArray<TConfigurationIssue>;
begin
  Source := Kundenform('  inherited Laden;'#10, '', '');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInheritedWrongMethodRule.Create, Source,
    '{"rules": {"inherited-wrong-method": {"allowed": ["Speichern>Laden"]}}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInheritedWrongMethodRule.Create, Source,
    '{"rules": {"inherited-wrong-method": {"allowed": ["Speich*>*"]}}}'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TInheritedWrongMethodRule.Create, Source,
    '{"rules": {"inherited-wrong-method": {"allowed": ["Laden>Speichern"]}}}'))));
  Assert.IsTrue(TInheritedWrongMethodRule.Allowed(['Speichern > Laden'], 'Speichern', 'Laden'));
  Assert.IsFalse(TInheritedWrongMethodRule.Allowed(['Speichern'], 'Speichern', 'Laden'));
  // Der Parser verlangt hier Texte, bei magic-number weiter Zahlen.
  TConfigurationParser.Parse('{"rules": {"inherited-wrong-method": {"allowed": [1]}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"allowed" muss eine Liste von Texten sein', Issues[0].Message);
  TConfigurationParser.Parse('{"rules": {"inherited-wrong-method": {"allowed": ["A>B"]}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  TConfigurationParser.Parse('{"rules": {"magic-number": {"allowed": ["A>B"]}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;

procedure TInheritedWrongMethodTests.OffAndExclude;
var
  Source: string;
begin
  Source := Kundenform('  inherited Laden;'#10, '', '');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInheritedWrongMethodRule.Create, Source,
    '{"rules": {"inherited-wrong-method": "off"}}', 'Source/Kundenform.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInheritedWrongMethodRule.Create, Source,
    '{"rules": {"inherited-wrong-method": {"exclude": ["Source/*.pas"]}}}', 'Source/Kundenform.pas'))));
end;

{ TGetterSideEffectTests }

/// <summary>TZaehler mit Getter GetWert (Rumpf ABody, Variablen AVars) und GetListe (Rumpf AListe).</summary>
function Zaehler(const ABody, AVars, AListe: string): string;
begin
  Result := 'unit Zaehler;'#10'interface'#10'type'#10'  TZaehler = class'#10'  private'#10 +
    '    FWert, FAbrufe: Integer;'#10'    FListe: TList;'#10'    function GetWert: Integer;'#10 +
    '    function GetListe: TList;'#10'  public'#10'    property Wert: Integer read GetWert;'#10 +
    '    property Liste: TList read GetListe;'#10'  end;'#10'implementation'#10 +
    'function TZaehler.GetWert: Integer;'#10 + AVars + 'begin'#10 + ABody + 'end;'#10 +
    'function TZaehler.GetListe: TList;'#10'begin'#10 + AListe + 'end;'#10'end.';
end;

function GetterFindings(const ASource: string; const AConfig: string = ''): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TGetterSideEffectRule.Create, ASource, AConfig);
end;

procedure TGetterSideEffectTests.IssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := GetterFindings(Zaehler('  Inc(FAbrufe);'#10'  Result := FWert;'#10, '', '  Result := FListe;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('getter-side-effect', Findings[0].RuleId);
  Assert.AreEqual('Der Getter GetWert verändert FAbrufe; schon das Anzeigen im Debugger ändert den Zustand.',
    Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual(16, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(6, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Die korrigierte Form ist still.
  TRuleAssert.Silent(TGetterSideEffectRule.Create, Zaehler('  Result := FWert;'#10, '', '  Result := FListe;'#10));
end;

procedure TGetterSideEffectTests.KindsOfChange;
var
  Findings: TArray<TRuleFinding>;
begin
  // Zuweisung (auch über Self.), Dec, neu angelegtes Objekt an eine Methode eines Felds; je Feld eine Meldung.
  Findings := GetterFindings(Zaehler('  Self.FWert := FWert + 1;'#10'  Dec(FAbrufe);'#10'  Dec(FAbrufe);'#10 +
    '  Result := FWert;'#10, '', '  FListe.Add(TObject.Create);'#10'  Result := FListe;'#10));
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual('Der Getter GetWert verändert FWert; schon das Anzeigen im Debugger ändert den Zustand.',
    Findings[0].Message);
  Assert.AreEqual(16, Findings[0].Range.StartPos.Line);
  Assert.AreEqual('Der Getter GetWert verändert FAbrufe; schon das Anzeigen im Debugger ändert den Zustand.',
    Findings[1].Message);
  Assert.AreEqual('Der Getter GetListe verändert FListe; schon das Anzeigen im Debugger ändert den Zustand.',
    Findings[2].Message);
  // Ein if ohne Prüfung des Zugewiesenen ist keine Lazy-Initialisierung.
  Assert.AreEqual(1, Integer(Length(GetterFindings(Zaehler('  if FWert > 0 then'#10'    Inc(FAbrufe);'#10 +
    '  Result := FWert;'#10, '', '  Result := FListe;'#10)))));
end;

procedure TGetterSideEffectTests.InheritedField;
var
  Source: string;
begin
  Source := StringReplace(Zaehler('  Inc(FZugriffe);'#10'  Result := FWert;'#10, '', '  Result := FListe;'#10),
    '  TZaehler = class'#10, '  TBasis = class'#10'  protected'#10'    FZugriffe: Integer;'#10'  end;'#10 +
    '  TZaehler = class(TBasis)'#10, []);
  Assert.AreEqual('Der Getter GetWert verändert FZugriffe; schon das Anzeigen im Debugger ändert den Zustand.',
    GetterFindings(Source)[0].Message);
end;

procedure TGetterSideEffectTests.LazyInitOption;
var
  Plain, Assigned_, ViaResult: string;
  Issues: TArray<TConfigurationIssue>;
begin
  Plain := Zaehler('  Result := FWert;'#10, '', '  if FListe = nil then'#10'    FListe := TList.Create;'#10 +
    '  Result := FListe;'#10);
  Assigned_ := Zaehler('  Result := FWert;'#10, '', '  if not Assigned(FListe) then'#10'  begin'#10 +
    '    FListe := TList.Create;'#10'    FListe.Add(TObject.Create);'#10'  end;'#10'  Result := FListe;'#10);
  ViaResult := Zaehler('  Result := FWert;'#10, '', '  Result := FListe;'#10'  if Result = nil then'#10 +
    '  begin'#10'    Result := TList.Create;'#10'    FListe := Result;'#10'  end;'#10);
  TRuleAssert.Silent(TGetterSideEffectRule.Create, Plain);
  TRuleAssert.Silent(TGetterSideEffectRule.Create, Assigned_);
  TRuleAssert.Silent(TGetterSideEffectRule.Create, ViaResult);
  // Zwischenspeicher mit Merker: if FAbrufe = 0 then begin FWert := …; FAbrufe := 1; end.
  TRuleAssert.Silent(TGetterSideEffectRule.Create, Zaehler('  if FAbrufe = 0 then'#10'  begin'#10 +
    '    FWert := 42;'#10'    FAbrufe := 1;'#10'  end;'#10'  Result := FWert;'#10, '', '  Result := FListe;'#10));
  // Mit allowLazyInit = false wird auch sie gemeldet.
  Assert.AreEqual(1, Integer(Length(GetterFindings(Plain,
    '{"rules": {"getter-side-effect": {"allowLazyInit": false}}}'))));
  Assert.AreEqual(1, Integer(Length(GetterFindings(Assigned_,
    '{"rules": {"getter-side-effect": {"allowLazyInit": false}}}'))));
  Assert.AreEqual(1, Integer(Length(GetterFindings(ViaResult,
    '{"rules": {"getter-side-effect": {"allowLazyInit": false}}}'))));
  TConfigurationParser.Parse('{"rules": {"getter-side-effect": {"allowLazyInit": "ja"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"allowLazyInit" muss true oder false sein', Issues[0].Message);
  TConfigurationParser.Parse('{"rules": {"getter-side-effect": {"allowLazyInit": false}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
end;

procedure TGetterSideEffectTests.SilentCases;
begin
  // Lokale Variable mit Feldnamen, Result, Methoden ohne Property, anonyme Methoden.
  TRuleAssert.Silent(TGetterSideEffectRule.Create, Zaehler('  FAbrufe := 1;'#10'  Result := FAbrufe;'#10,
    'var'#10'  FAbrufe: Integer;'#10, '  Result := FListe;'#10));
  TRuleAssert.Silent(TGetterSideEffectRule.Create, StringReplace(Zaehler('  Result := FWert;'#10, '',
    '  Result := FListe;'#10), 'end;'#10'end.', 'end;'#10'procedure TZaehler.Zaehlen;'#10'begin'#10 +
    '  Inc(FAbrufe);'#10'end;'#10'end.', []));
  TRuleAssert.Silent(TGetterSideEffectRule.Create, Zaehler('  Ausfuehren(procedure begin Inc(FAbrufe); end);'#10 +
    '  Result := FWert;'#10, '', '  Result := FListe;'#10));
  // Methode eines Felds mit Argument, das nichts anlegt.
  TRuleAssert.Silent(TGetterSideEffectRule.Create, Zaehler('  Result := FListe.IndexOf(nil);'#10, '',
    '  Result := FListe;'#10));
end;

procedure TGetterSideEffectTests.OffAndExclude;
var
  Source: string;
begin
  Source := Zaehler('  Inc(FAbrufe);'#10'  Result := FWert;'#10, '', '  Result := FListe;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TGetterSideEffectRule.Create, Source,
    '{"rules": {"getter-side-effect": "off"}}', 'Source/Zaehler.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TGetterSideEffectRule.Create, Source,
    '{"rules": {"getter-side-effect": {"exclude": ["Source/*.pas"]}}}', 'Source/Zaehler.pas'))));
end;

{ TEqualsWithoutGetHashCodeTests }

/// <summary>TKundenNr überschreibt Equals über FNummer und FName; AMembers ergänzt die Klasse, AMore die
/// Implementierung, AParent den Vorfahren ('' = keiner).</summary>
function KundenNr(const AMembers, AMore, AParent: string): string;
var
  Parent: string;
begin
  Parent := '';
  if AParent <> '' then
    Parent := '(' + AParent + ')';
  Result := 'unit Kunden;'#10'interface'#10'uses'#10'  System.SysUtils;'#10'type'#10 +
    '  TKundenNr = class' + Parent + #10'  private'#10'    FNummer: Integer;'#10'    FName: string;'#10'  public'#10 +
    '    function Equals(Obj: TObject): Boolean; override;'#10 + AMembers + '  end;'#10'implementation'#10 +
    'function TKundenNr.Equals(Obj: TObject): Boolean;'#10'begin'#10 +
    '  Result := (Obj is TKundenNr) and (TKundenNr(Obj).FNummer = FNummer) and SameText(TKundenNr(Obj).FName, FName);'#10 +
    'end;'#10 + AMore + 'end.';
end;

function HashFindings(const ASource: string; const AConfig: string = ''; const APath: string = ''):
  TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TEqualsWithoutGetHashCodeRule.Create, ASource, AConfig, APath);
end;

procedure TEqualsWithoutGetHashCodeTests.IssueExampleWithFix;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := KundenNr('', '', '');
  Findings := HashFindings(Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('equals-without-gethashcode', Findings[0].RuleId);
  Assert.AreEqual('Equals ist überschrieben, GetHashCode nicht; als Schlüssel in TDictionary finden sich gleiche ' +
    'Objekte nicht.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(10, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('GetHashCode mit FNummer, FName überschreiben (THashBobJenkins)', Findings[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.IsTrue(Pos('    function Equals(Obj: TObject): Boolean; override;'#10 +
    '    function GetHashCode: Integer; override;'#10'  end;', Fixed) > 0, Fixed);
  Assert.IsTrue(Pos('end;'#10#10'function TKundenNr.GetHashCode: Integer;'#10'begin'#10 +
    '  Result := THashBobJenkins.GetHashValue(FNummer, SizeOf(FNummer), 0);'#10 +
    '  Result := THashBobJenkins.GetHashValue(LowerCase(FName), Result);'#10'end;'#10'end.', Fixed) > 0, Fixed);
  Assert.IsTrue(Pos('System.Hash', Fixed) > 0, Fixed);
  TRuleAssert.Silent(TEqualsWithoutGetHashCodeRule.Create, Fixed);
end;

procedure TEqualsWithoutGetHashCodeTests.GetHashCodeWithoutEquals;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := StringReplace(KundenNr('', '', ''), 'function Equals(Obj: TObject): Boolean; override;',
    'function GetHashCode: Integer; override;', []);
  Findings := HashFindings(Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('GetHashCode ist überschrieben, Equals nicht; als Schlüssel in TDictionary gelten gleiche ' +
    'Objekte weiter als verschieden.', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TEqualsWithoutGetHashCodeTests.AncestorsAndSilentCases;
var
  Basis: string;
begin
  // Beides überschrieben.
  TRuleAssert.Silent(TEqualsWithoutGetHashCodeRule.Create, KundenNr('    function GetHashCode: Integer; override;'#10,
    'function TKundenNr.GetHashCode: Integer;'#10'begin'#10'  Result := FNummer;'#10'end;'#10, ''));
  // Ein Vorfahr der Datei überschreibt beides; ein unbekannter Vorfahr gibt keine Aussage.
  Basis := StringReplace(KundenNr('', '', 'TBasis'), '  TKundenNr = class(TBasis)',
    '  TBasis = class'#10'  public'#10'    function Equals(Obj: TObject): Boolean; override;'#10 +
    '    function GetHashCode: Integer; override;'#10'  end;'#10 +
    '  TKundenNr = class(TBasis)', []);
  TRuleAssert.Silent(TEqualsWithoutGetHashCodeRule.Create, Basis);
  TRuleAssert.Silent(TEqualsWithoutGetHashCodeRule.Create, KundenNr('', '', 'TUnbekannt'));
  // Eigenes Equals ohne override ist nicht TObject.Equals.
  TRuleAssert.Silent(TEqualsWithoutGetHashCodeRule.Create, StringReplace(KundenNr('', '', ''),
    'function Equals(Obj: TObject): Boolean; override;', 'function Equals(Obj: TObject): Boolean; reintroduce;', []));
end;

procedure TEqualsWithoutGetHashCodeTests.FixNeedsEqualsBodyWithFields;
var
  Findings: TArray<TRuleFinding>;
begin
  // Equals vergleicht keine eigenen Felder: Meldung ohne Korrektur.
  Findings := HashFindings(StringReplace(KundenNr('', '', ''),
    '(Obj is TKundenNr) and (TKundenNr(Obj).FNummer = FNummer) and SameText(TKundenNr(Obj).FName, FName)',
    'Obj = Self', []));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

/// <summary>Record TSchluessel mit AFields und class operator Equal (AOperator = False: ohne), Schlüssel in ACode.</summary>
function Schluessel(const AFields, ACode: string; AOperator: Boolean): string;
var
  Operator_: string;
begin
  Operator_ := '';
  if AOperator then
    Operator_ := '    class operator Equal(const A, B: TSchluessel): Boolean;'#10;
  Result := 'unit Schluessel;'#10'interface'#10'uses'#10'  System.Generics.Collections;'#10'type'#10 +
    '  TSchluessel = record'#10 + AFields + Operator_ + '  end;'#10'implementation'#10'procedure Zaehlen;'#10 +
    'var'#10'  D: TDictionary<TSchluessel, Integer>;'#10'begin'#10 + ACode + 'end;'#10'end.';
end;

procedure TEqualsWithoutGetHashCodeTests.RecordKeys;
var
  Findings: TArray<TRuleFinding>;
const
  Fields = '    Name: string;'#10'    Nr: Integer;'#10;
begin
  Findings := HashFindings(Schluessel(Fields, '  D := TDictionary<TSchluessel, Integer>.Create;'#10, True));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TSchluessel hat class operator Equal, TDictionary vergleicht Schlüssel ohne Comparer aber Byte ' +
    'für Byte; gleiche Schlüssel finden sich nicht.', Findings[0].Message);
  Assert.AreEqual(15, Findings[0].Range.StartPos.Line);
  // Kapazität und Mengen sind kein Comparer.
  Assert.AreEqual(2, Integer(Length(HashFindings(Schluessel(Fields,
    '  THashSet<TSchluessel>.Create(10).Free;'#10'  D := TObjectDictionary<TSchluessel, Integer>.Create([]);'#10,
    True)))));
  // Mit Comparer, ohne Operator, nur Ganzzahlfelder (Byte-Vergleich passt), Schlüssel nicht als erster Typ.
  TRuleAssert.Silent(TEqualsWithoutGetHashCodeRule.Create, Schluessel(Fields,
    '  D := TDictionary<TSchluessel, Integer>.Create(TSchluesselComparer.Create);'#10, True));
  TRuleAssert.Silent(TEqualsWithoutGetHashCodeRule.Create, Schluessel(Fields,
    '  D := TDictionary<TSchluessel, Integer>.Create;'#10, False));
  TRuleAssert.Silent(TEqualsWithoutGetHashCodeRule.Create, Schluessel('    Nr, Teil: Integer;'#10,
    '  D := TDictionary<TSchluessel, Integer>.Create;'#10, True));
  TRuleAssert.Silent(TEqualsWithoutGetHashCodeRule.Create, Schluessel(Fields,
    '  TDictionary<Integer, TSchluessel>.Create.Free;'#10, True));
end;

procedure TEqualsWithoutGetHashCodeTests.HashExpressions;
begin
  Assert.AreEqual('THashBobJenkins.GetHashValue(FNr, SizeOf(FNr), 0)',
    TEqualsWithoutGetHashCodeRule.HashExpression('FNr', 'Integer', '', '0'));
  Assert.AreEqual('THashBobJenkins.GetHashValue(FName, Result)',
    TEqualsWithoutGetHashCodeRule.HashExpression('FName', 'string', 'SameStr', 'Result'));
  Assert.AreEqual('THashBobJenkins.GetHashValue(AnsiLowerCase(FName), 0)',
    TEqualsWithoutGetHashCodeRule.HashExpression('FName', 'UnicodeString', 'AnsiSameText', '0'));
end;

procedure TEqualsWithoutGetHashCodeTests.OffAndExclude;
var
  Source: string;
begin
  Source := KundenNr('', '', '');
  Assert.AreEqual(0, Integer(Length(HashFindings(Source, '{"rules": {"equals-without-gethashcode": "off"}}',
    'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(HashFindings(Source,
    '{"rules": {"equals-without-gethashcode": {"exclude": ["Source/*.pas"]}}}', 'Source/Kunden.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TComponentRulesTests);
  TDUnitX.RegisterTestFixture(TInheritedOrderTests);
  TDUnitX.RegisterTestFixture(TInheritedWrongMethodTests);
  TDUnitX.RegisterTestFixture(TGetterSideEffectTests);
  TDUnitX.RegisterTestFixture(TEqualsWithoutGetHashCodeTests);

end.
