unit Argus.Common.Rules.Builtin.Components.Tests;

// Tests für die Komponentenregeln (#55, Teil A).

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
  end;

implementation

uses
  System.SysUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Configuration.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Rules.Builtin.Components,
  Argus.Tests.RuleAssert;

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
    '  X := Width div 2;'#10'  Canvas.Font.Size := 10;'#10'  Canvas.Brush.Color := $00FF8000;'));
end;

procedure TComponentRulesTests.HexColorReportsSystemColorSilent;
begin
  TRuleAssert.Reports(TComponentHardcodedColorRule.Create, PaintUnit('  Canvas.Brush.Color := $00FF8000;'));
  TRuleAssert.Reports(TComponentHardcodedColorRule.Create, PaintUnit('  Canvas.Pen.Color := RGB(255, 128, 0);'));
  TRuleAssert.Silent(TComponentHardcodedColorRule.Create, PaintUnit('  Canvas.Brush.Color := clBtnFace;'));
end;

initialization
  TDUnitX.RegisterTestFixture(TComponentRulesTests);

end.
