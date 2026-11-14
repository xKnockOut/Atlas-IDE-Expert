unit Atlas.Common.Editing.RaiseVisibility.Tests;

// Tests für „Sichtbarkeit anheben“ und „Eigenschaft anlegen“ (#2108): Ziele je
// Sichtbarkeit, Verschieben samt Doku-Kommentar in einen neuen oder
// vorhandenen Abschnitt, leere Abschnitte, Feldgruppen, Überladungen, Name der
// Property und die Code-Aktionen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRaiseVisibilityTests = class
  private
    FTree: TObject;
    FText: string;
    /// <summary>Text nach der ersten Aktion für das Mitglied in Zeile ALine (bzw. AName), deren Titel ATitle
    /// enthält.</summary>
    function Applied(const AText: string; ALine: Integer; const AName, ATitle: string): string;
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TargetsFollowVisibility;
    [Test]
    procedure MovesFieldWithDocIntoNewSection;
    [Test]
    procedure RemovesEmptiedSection;
    [Test]
    procedure KeepsImplementation;
    [Test]
    procedure MovesOneNameOfFieldGroup;
    [Test]
    procedure MovesOnlyChosenOverload;
    [Test]
    procedure NamesPropertyAfterField;
    [Test]
    procedure CreatesReadOnlyAndWritableProperty;
    [Test]
    procedure ActionsOnDeclaration;
    [Test]
    procedure NoActionsOutsideClass;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.ClassLayout,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Editing.RaiseVisibility;

const
  Source =
    'unit U;'#10 +                                      // 0
    'interface'#10 +                                    // 1
    'type'#10 +                                         // 2
    '  TFoo = class'#10 +                               // 3
    '  strict private'#10 +                             // 4
    '    FHidden: Integer;'#10 +                        // 5
    '  private'#10 +                                    // 6
    '    /// <summary>Anzahl der Werte.</summary>'#10 + // 7
    '    FCount: Integer;'#10 +                         // 8
    '    FA, FB: string;'#10 +                          // 9
    '    procedure Add(AValue: Integer); overload;'#10 + // 10
    '    procedure Add(const AValue: string); overload;'#10 + // 11
    '  protected'#10 +                                  // 12
    '    procedure Step; virtual;'#10 +                 // 13
    '  public'#10 +                                     // 14
    '    procedure Run;'#10 +                           // 15
    '  published'#10 +                                  // 16
    '    property Count: Integer read FCount;'#10 +     // 17
    '  end;'#10 +                                       // 18
    #10 +                                               // 19
    '  TForm1 = class(TForm)'#10 +                      // 20
    '    Button1: TButton;'#10 +                        // 21
    '  private'#10 +                                    // 22
    '    procedure Helper;'#10 +                        // 23
    '  end;'#10 +                                       // 24
    'implementation'#10 +                               // 25
    #10 +
    'procedure TFoo.Add(AValue: Integer);'#10'begin'#10'  FCount := AValue;'#10'end;'#10#10 +
    'procedure TFoo.Add(const AValue: string);'#10'begin'#10'end;'#10#10 +
    'procedure TFoo.Step;'#10'begin'#10'end;'#10#10 +
    'procedure TFoo.Run;'#10'begin'#10'end;'#10#10 +
    'procedure TForm1.Helper;'#10'begin'#10'end;'#10#10 +
    'end.'#10;

  Small =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TBar = class'#10 +
    '  private'#10 +
    '    procedure Step;'#10 +                          // 5
    '  public'#10 +
    '    procedure Run;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TBar.Step;'#10'begin'#10'end;'#10 +
    'procedure TBar.Run;'#10'begin'#10'end;'#10 +
    'end.'#10;

function Parses(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Result := (mTree <> nil) and (mTree.Root <> nil);
  finally
    mTree.Free;
  end;
end;

/// <summary>Layout der Klasse AName in AText; ATree gibt der Aufrufer frei.</summary>
function LayoutOf(const AText, AName: string; out ATree: TSyntaxTree): TClassLayout;
begin
  ATree := TSyntaxTreeCache.Parse(AText);
  Result := TClassLayout.Read(ATree, AText, TClassLayout.DeclNamed(ATree, AName));
end;

procedure TRaiseVisibilityTests.TearDown;
begin
  FreeAndNil(FTree);
  FText := '';
end;

function TRaiseVisibilityTests.Applied(const AText: string; ALine: Integer; const AName, ATitle: string): string;
var
  mTree: TSyntaxTree;
  mAction: TCodeAction;
begin
  Result := '';
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    for mAction in TRaiseVisibility.Actions(AText, mTree, TTextPosition.Create(ALine, 6), AName, True) do
    begin
      if ContainsStr(mAction.Title, ATitle) then
      begin
        Exit(TTextChanges.Apply(AText, mAction.Edits));
      end;
    end;
  finally
    mTree.Free;
  end;
  Assert.Fail('Aktion fehlt: ' + ATitle);
end;

procedure TRaiseVisibilityTests.TargetsFollowVisibility;
var
  mTree: TSyntaxTree;
  mLayout: TClassLayout;
  mTargets: TArray<TClassVisibility>;
begin
  mLayout := LayoutOf(Source, 'TFoo', mTree);
  try
    mTargets := TRaiseVisibility.Targets(mLayout, mLayout.Find('FHidden')[0]);
    Assert.AreEqual(2, Integer(Length(mTargets)), 'strict private');
    Assert.AreEqual<TClassVisibility>(TClassVisibility.Protected_, mTargets[0]);
    Assert.AreEqual<TClassVisibility>(TClassVisibility.Public_, mTargets[1]);
    mTargets := TRaiseVisibility.Targets(mLayout, mLayout.Find('Step')[0]);
    Assert.AreEqual(1, Integer(Length(mTargets)), 'protected');
    Assert.AreEqual<TClassVisibility>(TClassVisibility.Public_, mTargets[0]);
    Assert.AreEqual(0, Integer(Length(TRaiseVisibility.Targets(mLayout, mLayout.Find('Run')[0]))), 'public');
    Assert.AreEqual(0, Integer(Length(TRaiseVisibility.Targets(mLayout, mLayout.Find('Count')[0]))), 'published');
  finally
    mLayout.Free;
    mTree.Free;
  end;
  mLayout := LayoutOf(Source, 'TForm1', mTree);
  try
    Assert.AreEqual(0, Integer(Length(TRaiseVisibility.Targets(mLayout, mLayout.Find('Button1')[0]))),
      'Formularfeld');
    Assert.AreEqual(2, Integer(Length(TRaiseVisibility.Targets(mLayout, mLayout.Find('Helper')[0]))));
  finally
    mLayout.Free;
    mTree.Free;
  end;
end;

procedure TRaiseVisibilityTests.MovesFieldWithDocIntoNewSection;
begin
  FText := Applied(Source, 8, '', 'auf public');
  Assert.IsTrue(Parses(FText), FText);
  // Der Doku-Kommentar wandert mit, public bekommt das Feld vor seinen Methoden.
  Assert.IsTrue(ContainsStr(FText, '  public'#10'    /// <summary>Anzahl der Werte.</summary>'#10 +
    '    FCount: Integer;'#10'    procedure Run;'#10), FText);
  Assert.IsFalse(ContainsStr(FText, '  private'#10'    /// <summary>'), FText);
  FText := Applied(Source, 5, '', 'auf protected');
  // strict private fällt weg, FHidden steht als Feld vor den Methoden von protected.
  Assert.IsFalse(ContainsStr(FText, 'strict private'), FText);
  Assert.IsTrue(ContainsStr(FText, '  protected'#10'    FHidden: Integer;'#10'    procedure Step; virtual;'#10), FText);
end;

procedure TRaiseVisibilityTests.RemovesEmptiedSection;
begin
  FText := Applied(Small, 5, '', 'auf public');
  Assert.IsTrue(Parses(FText), FText);
  Assert.IsTrue(ContainsStr(FText, '  TBar = class'#10'  public'#10'    procedure Run;'#10'    procedure Step;'#10 +
    '  end;'), FText);
  FText := Applied(Small, 5, '', 'auf protected');
  // Neuer Abschnitt protected vor public.
  Assert.IsTrue(ContainsStr(FText, '  TBar = class'#10'  protected'#10'    procedure Step;'#10'  public'#10), FText);
end;

procedure TRaiseVisibilityTests.KeepsImplementation;
begin
  FText := Applied(Source, 10, '', 'auf protected');
  Assert.AreEqual(Copy(Source, Pos('implementation', Source), MaxInt), Copy(FText, Pos('implementation', FText),
    MaxInt));
end;

procedure TRaiseVisibilityTests.MovesOneNameOfFieldGroup;
begin
  FText := Applied(Source, 9, 'FB', 'auf protected');
  Assert.IsTrue(Parses(FText), FText);
  Assert.IsTrue(ContainsStr(FText, '    FA: string;'#10), FText);
  Assert.IsTrue(ContainsStr(FText, '  protected'#10'    FB: string;'#10), FText);
end;

procedure TRaiseVisibilityTests.MovesOnlyChosenOverload;
begin
  FText := Applied(Source, 11, '', 'auf public');
  Assert.IsTrue(Parses(FText), FText);
  Assert.IsTrue(ContainsStr(FText, '  private'#10'    /// <summary>Anzahl der Werte.</summary>'#10 +
    '    FCount: Integer;'#10'    FA, FB: string;'#10'    procedure Add(AValue: Integer); overload;'#10 +
    '  protected'#10), FText);
  Assert.IsTrue(ContainsStr(FText, '    procedure Run;'#10'    procedure Add(const AValue: string); overload;'#10),
    FText);
end;

procedure TRaiseVisibilityTests.NamesPropertyAfterField;
var
  mTree: TSyntaxTree;
  mLayout: TClassLayout;
begin
  mLayout := LayoutOf(Source, 'TFoo', mTree);
  try
    Assert.AreEqual('Hidden', TRaiseVisibility.PropertyName(mLayout, mLayout.Find('FHidden')[0]));
    Assert.AreEqual('', TRaiseVisibility.PropertyName(mLayout, mLayout.Find('FCount')[0]), 'Count gibt es schon');
    Assert.AreEqual('B', TRaiseVisibility.PropertyName(mLayout, mLayout.Find('FB')[0]));
    Assert.AreEqual('', TRaiseVisibility.PropertyName(mLayout, mLayout.Find('Step')[0]), 'Methode');
  finally
    mLayout.Free;
    mTree.Free;
  end;
  mLayout := LayoutOf(Source, 'TForm1', mTree);
  try
    Assert.AreEqual('', TRaiseVisibility.PropertyName(mLayout, mLayout.Find('Button1')[0]), 'ohne F-Präfix');
  finally
    mLayout.Free;
    mTree.Free;
  end;
end;

procedure TRaiseVisibilityTests.CreatesReadOnlyAndWritableProperty;
begin
  FText := Applied(Source, 5, '', '(nur lesen)');
  Assert.IsTrue(Parses(FText), FText);
  Assert.IsTrue(ContainsStr(FText, '    procedure Run;'#10'    property Hidden: Integer read FHidden;'#10'  published'),
    FText);
  Assert.IsTrue(ContainsStr(FText, '  strict private'#10'    FHidden: Integer;'#10), 'Feld bleibt: ' + FText);
  FText := Applied(Source, 5, '', '(lesen und schreiben)');
  Assert.IsTrue(ContainsStr(FText, '    property Hidden: Integer read FHidden write FHidden;'#10), FText);
end;

procedure TRaiseVisibilityTests.ActionsOnDeclaration;
var
  mTree: TSyntaxTree;
  mActions: TArray<TCodeAction>;
begin
  mTree := TSyntaxTreeCache.Parse(Source);
  FTree := mTree;
  mActions := TRaiseVisibility.Actions(Source, mTree, TTextPosition.Create(5, 6), '', True);
  Assert.AreEqual(4, Integer(Length(mActions)));
  Assert.AreEqual('Eigenschaft Hidden in TFoo anlegen (nur lesen)', mActions[0].Title);
  Assert.AreEqual(cCreatePropertyTag, mActions[1].Tag);
  Assert.AreEqual('Sichtbarkeit von FHidden auf protected anheben', mActions[2].Title);
  Assert.AreEqual(cRaiseVisibilityTag, mActions[3].Tag);
  Assert.AreEqual(cRewriteKind, mActions[3].Kind);
  // Ohne Properties nur das Anheben; Wort an der Cursorstelle wählt in der Feldgruppe.
  mActions := TRaiseVisibility.Actions(Source, mTree, TTextPosition.Create(9, 9), '', False);
  Assert.AreEqual(2, Integer(Length(mActions)));
  Assert.AreEqual('Sichtbarkeit von FB auf protected anheben', mActions[0].Title);
  Assert.AreEqual(0, Integer(Length(TRaiseVisibility.Actions(Source, mTree, TTextPosition.Create(17, 6), '',
    True))), 'published');
  mActions := nil;
end;

procedure TRaiseVisibilityTests.NoActionsOutsideClass;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(Source);
  FTree := mTree;
  Assert.AreEqual(0, Integer(Length(TRaiseVisibility.Actions(Source, mTree, TTextPosition.Create(0, 2), '', True))));
  Assert.AreEqual(0, Integer(Length(TRaiseVisibility.Actions(Source, mTree, TTextPosition.Create(28, 2), '',
    True))), 'Rumpf');
  Assert.AreEqual(0, Integer(Length(TRaiseVisibility.Actions(Source, mTree, TTextPosition.Create(5, 6), 'FNone',
    True))), 'unbekannter Name');
end;

initialization
  TDUnitX.RegisterTestFixture(TRaiseVisibilityTests);

end.
