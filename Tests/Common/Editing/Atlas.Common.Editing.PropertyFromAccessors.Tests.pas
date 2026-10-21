unit Atlas.Common.Editing.PropertyFromAccessors.Tests;

// Tests für „Property aus Getter und Setter“ (#682): Erkennung (nur Getter,
// Getter und Setter, indiziert, Boolean mit Is, eigener Präfix), read FX,
// Abschnitt, Verbergen, Angebot an Methode und Klasse, Einordnung und
// Umstellung von Aufrufen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPropertyFromAccessorsTests = class
  public
    [Test]
    procedure OnlyGetter;
    [Test]
    procedure GetterAndSetter;
    [Test]
    procedure IndexedProperty;
    [Test]
    procedure BooleanWithIs;
    [Test]
    procedure OwnPrefix;
    [Test]
    procedure TrivialGetterReadsField;
    [Test]
    procedure NotOffered;
    [Test]
    procedure MostVisibleSection;
    [Test]
    procedure PublishedOpensSection;
    [Test]
    procedure HidesAccessors;
    [Test]
    procedure OfferedOnMethodAndClass;
    [Test]
    procedure ClassGetsAllProperties;
    [Test]
    procedure ClassifiesUses;
    [Test]
    procedure RewritesCalls;
    [Test]
    procedure PluralNames;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.PropertyFromAccessors;

const
  Panel =
    'unit U;'#10 +                                          // 0
    'interface'#10 +                                        // 1
    'type'#10 +                                             // 2
    '  TPanel = class'#10 +                                 // 3
    '  private'#10 +                                        // 4
    '    FCaption: string;'#10 +                            // 5
    '  public'#10 +                                         // 6
    '    function GetCaption: string;'#10 +                 // 7
    '    procedure SetCaption(const AValue: string);'#10 + // 8
    '  end;'#10 +                                           // 9
    'implementation'#10 +                                   // 10
    'function TPanel.GetCaption: string;'#10 +              // 11
    'begin'#10 +                                            // 12
    '  Result := FCaption + ''!'';'#10 +                    // 13
    'end;'#10 +                                             // 14
    'procedure TPanel.SetCaption(const AValue: string);'#10 +
    'begin'#10 +
    '  FCaption := AValue;'#10 +
    'end;'#10 +
    'end.';

function UnitText(const AClass, AImplementation: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10 + AClass + 'implementation'#10 + AImplementation + 'end.';
end;

function Find(const AText: string; const AOptions: TPropertyFromAccessorsOptions): TArray<TAccessorProperty>;
  overload;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TPropertyFromAccessors.Find(Tree, AText, AOptions);
  finally
    Tree.Free;
  end;
end;

function Find(const AText: string): TArray<TAccessorProperty>; overload;
begin
  Result := Find(AText, TPropertyFromAccessorsOptions.Default);
end;

function Parses(const AText: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
  end;
end;

/// <summary>Alle gefundenen Properties anlegen, AHidden verbergen; das Ergebnis parst und hat keine fehlenden
/// Properties mehr.</summary>
function Create_(const AText: string; const AHidden: TArray<string>;
  const AOptions: TPropertyFromAccessorsOptions): string; overload;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TChangeSignature.ApplyEdits(AText, TPropertyFromAccessors.Edits(Tree, AText,
      TPropertyFromAccessors.Find(Tree, AText, AOptions), AHidden, AOptions));
  finally
    Tree.Free;
  end;
  Assert.IsTrue(Parses(Result), Result);
  Assert.AreEqual(0, Integer(Length(Find(Result, AOptions))), Result);
end;

function Create_(const AText: string): string; overload;
begin
  Result := Create_(AText, nil, TPropertyFromAccessorsOptions.Default);
end;

procedure TPropertyFromAccessorsTests.OnlyGetter;
var
  Found: TArray<TAccessorProperty>;
  Source: string;
begin
  Source := UnitText('  TPanel = class'#10'  public'#10'    function GetCaption: string;'#10'  end;'#10, '');
  Found := Find(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Caption', Found[0].Name);
  Assert.IsFalse(Found[0].Setter.Exists);
  Assert.AreEqual('property Caption: string read GetCaption;', Found[0].Declaration);
  Assert.AreEqual(UnitText('  TPanel = class'#10'  public'#10'    function GetCaption: string;'#10 +
    '    property Caption: string read GetCaption;'#10'  end;'#10, ''), Create_(Source));
end;

procedure TPropertyFromAccessorsTests.GetterAndSetter;
var
  Found: TArray<TAccessorProperty>;
  Result_: string;
begin
  Found := Find(Panel);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('TPanel', Found[0].ClassName);
  Assert.AreEqual(3, Found[0].ClassLine);
  Assert.AreEqual(7, Found[0].Getter.NamePos.Line);
  Assert.AreEqual(13, Found[0].Getter.NamePos.Character);
  Assert.AreEqual(8, Found[0].Setter.NamePos.Line);
  // Der Getter liefert nicht nur das Feld: read GetCaption.
  Assert.AreEqual('property Caption: string read GetCaption write SetCaption;', Found[0].Declaration);
  Result_ := Create_(Panel);
  Assert.Contains(Result_, '    procedure SetCaption(const AValue: string);'#10 +
    '    property Caption: string read GetCaption write SetCaption;'#10'  end;');
end;

procedure TPropertyFromAccessorsTests.IndexedProperty;
var
  Found: TArray<TAccessorProperty>;
begin
  Found := Find(UnitText('  TList = class'#10'  public'#10'    function GetItem(AIndex: Integer): TObject;'#10 +
    '    procedure SetItem(AIndex: Integer; const AValue: TObject);'#10'  end;'#10, ''));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('property Items[AIndex: Integer]: TObject read GetItem write SetItem;', Found[0].Declaration);
  // Ohne Getter: Indexparameter aus dem Setter.
  Found := Find(UnitText('  TList = class'#10'  public'#10 +
    '    procedure SetEntry(const AName: string; AValue: Integer);'#10'  end;'#10, ''));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('property Entries[const AName: string]: Integer write SetEntry;', Found[0].Declaration);
  // Indexparameter, die nicht passen: nur der Getter.
  Found := Find(UnitText('  TList = class'#10'  public'#10'    function GetItem(AIndex: Integer): TObject;'#10 +
    '    procedure SetItem(const AName: string; const AValue: TObject);'#10'  end;'#10, ''));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('property Items[AIndex: Integer]: TObject read GetItem;', Found[0].Declaration);
end;

procedure TPropertyFromAccessorsTests.BooleanWithIs;
var
  Found: TArray<TAccessorProperty>;
begin
  Found := Find(UnitText('  TList = class'#10'  public'#10'    function IsEmpty: Boolean;'#10 +
    '    function HasName: string;'#10'    function IsVisible: Boolean;'#10 +
    '    procedure SetVisible(AValue: Boolean);'#10'  end;'#10, ''));
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('property Empty: Boolean read IsEmpty;', Found[0].Declaration);
  Assert.AreEqual('property Visible: Boolean read IsVisible write SetVisible;', Found[1].Declaration);
end;

procedure TPropertyFromAccessorsTests.OwnPrefix;
var
  Options: TPropertyFromAccessorsOptions;
  Found: TArray<TAccessorProperty>;
  Source: string;
begin
  Source := UnitText('  TFile = class'#10'  public'#10'    function ReadSize: Int64;'#10 +
    '    procedure WriteSize(AValue: Int64);'#10'    function GetName: string;'#10'  end;'#10, '');
  Options := TPropertyFromAccessorsOptions.Default;
  Options.Prefixes := ['Read', 'Write'];
  Found := Find(Source, Options);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('property Size: Int64 read ReadSize write WriteSize;', Found[0].Declaration);
  // Ohne Get in der Liste bleibt GetName unbeachtet; mit den Standardpräfixen nur GetName.
  Found := Find(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Name', Found[0].Name);
end;

procedure TPropertyFromAccessorsTests.TrivialGetterReadsField;
var
  Found: TArray<TAccessorProperty>;
begin
  Found := Find(StringReplace(Panel, 'FCaption + ''!''', 'FCaption', []));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('FCaption', Found[0].ReadField);
  Assert.AreEqual('property Caption: string read FCaption write SetCaption;', Found[0].Declaration);
  // Feld mit anderem Typ: read GetCaption.
  Found := Find(StringReplace(StringReplace(Panel, 'FCaption + ''!''', 'FCaption', []), 'FCaption: string',
    'FCaption: TCaption', []));
  Assert.AreEqual('', Found[0].ReadField);
end;

procedure TPropertyFromAccessorsTests.NotOffered;
begin
  // Property vorhanden, Zugriffsmethode schon benutzt, Klassenmethode, var-Setter, Standardwert, überladen.
  Assert.AreEqual(0, Integer(Length(Find(UnitText('  TA = class'#10'  public'#10'    function GetCaption: string;'#10 +
    '    property Caption: string read FCaption;'#10'  end;'#10, '')))));
  Assert.AreEqual(0, Integer(Length(Find(UnitText('  TA = class'#10'  public'#10'    function GetCaption: string;'#10 +
    '    property Text: string read GetCaption;'#10'  end;'#10, '')))));
  Assert.AreEqual(0, Integer(Length(Find(UnitText('  TA = class'#10'  public'#10 +
    '    class function GetCount: Integer;'#10'    procedure SetName(var AValue: string);'#10 +
    '    function GetSize(A: Integer = 1): Integer;'#10'    function GetLine(A: Integer): string; overload;'#10 +
    '    function GetLine(const A: string): string; overload;'#10'    function Getaway: Integer;'#10 +
    '    procedure SetUp;'#10'  end;'#10, '')))));
end;

procedure TPropertyFromAccessorsTests.MostVisibleSection;
var
  Source, Result_: string;
  Options: TPropertyFromAccessorsOptions;
begin
  Source := UnitText('  TA = class'#10'  protected'#10'    function GetCaption: string;'#10'  public'#10 +
    '    procedure SetCaption(const AValue: string);'#10'    procedure Run;'#10'  end;'#10, '');
  Result_ := Create_(Source);
  Assert.AreEqual(UnitText('  TA = class'#10'  protected'#10'    function GetCaption: string;'#10'  public'#10 +
    '    procedure SetCaption(const AValue: string);'#10'    procedure Run;'#10 +
    '    property Caption: string read GetCaption write SetCaption;'#10'  end;'#10, ''), Result_);
  // Mindestens public, der public-Abschnitt steht aber vor dem Getter: neuer Abschnitt vor "end".
  Source := UnitText('  TA = class'#10'  public'#10'    procedure Run;'#10'  private'#10 +
    '    function GetCaption: string;'#10'  end;'#10, '');
  Options := TPropertyFromAccessorsOptions.Default;
  Options.Section := TPropertySectionChoice.Public_;
  Assert.AreEqual(UnitText('  TA = class'#10'  public'#10'    procedure Run;'#10'  private'#10 +
    '    function GetCaption: string;'#10'  public'#10'    property Caption: string read GetCaption;'#10'  end;'#10,
    ''), Create_(Source, nil, Options));
  // Sonst bleibt sie im Abschnitt des Getters.
  Assert.Contains(Create_(Source), '    function GetCaption: string;'#10'    property Caption: string read GetCaption;');
end;

procedure TPropertyFromAccessorsTests.PublishedOpensSection;
var
  Options: TPropertyFromAccessorsOptions;
begin
  Options := TPropertyFromAccessorsOptions.Default;
  Options.Section := TPropertySectionChoice.Published_;
  Assert.AreEqual(UnitText('  TA = class'#10'  private'#10'    function GetCaption: string;'#10 +
    '    function GetSize: Integer;'#10'  published'#10'    property Caption: string read GetCaption;'#10 +
    '    property Size: Integer read GetSize;'#10'  end;'#10, ''),
    Create_(UnitText('  TA = class'#10'  private'#10'    function GetCaption: string;'#10 +
    '    function GetSize: Integer;'#10'  end;'#10, ''), nil, Options));
  Options.Section := TPropertySectionChoice.Public_;
  Assert.Contains(Create_(UnitText('  TA = class'#10'  private'#10'    function GetCaption: string;'#10 +
    '  end;'#10, ''), nil, Options), '  public'#10'    property Caption: string read GetCaption;'#10'  end;');
end;

procedure TPropertyFromAccessorsTests.HidesAccessors;
var
  Options: TPropertyFromAccessorsOptions;
begin
  Options := TPropertyFromAccessorsOptions.Default;
  Options.Hiding := TAccessorHiding.Private_;
  // Mit private-Abschnitt davor: die Methoden wandern dorthin.
  Assert.AreEqual(UnitText('  TPanel = class'#10'  private'#10'    FCaption: string;'#10 +
    '    function GetCaption: string;'#10'    procedure SetCaption(const AValue: string);'#10'  public'#10 +
    '    procedure Run;'#10'    property Caption: string read GetCaption write SetCaption;'#10'  end;'#10, ''),
    Create_(UnitText('  TPanel = class'#10'  private'#10'    FCaption: string;'#10'  public'#10 +
    '    function GetCaption: string;'#10'    procedure SetCaption(const AValue: string);'#10'    procedure Run;'#10 +
    '  end;'#10, ''), ['GetCaption', 'SetCaption'], Options));
  // Ohne: eigener Abschnitt vor der Property; nur freigegebene Methoden wandern, virtuelle nie.
  Assert.AreEqual(UnitText('  TPanel = class'#10'  public'#10'    procedure SetCaption(const AValue: string); virtual;'#10 +
    '  private'#10'    function GetCaption: string;'#10'  public'#10 +
    '    property Caption: string read GetCaption write SetCaption;'#10'  end;'#10, ''),
    Create_(UnitText('  TPanel = class'#10'  public'#10'    function GetCaption: string;'#10 +
    '    procedure SetCaption(const AValue: string); virtual;'#10'  end;'#10, ''), ['GetCaption', 'SetCaption'],
    Options));
end;

procedure TPropertyFromAccessorsTests.OfferedOnMethodAndClass;
var
  Tree: TSyntaxTree;
  Whole: Boolean;
  Found: TArray<TAccessorProperty>;
begin
  Tree := TPascalParser.Parse(Panel);
  try
    Found := TPropertyFromAccessors.At(Tree, Panel, 8, TPropertyFromAccessorsOptions.Default, Whole);
    Assert.AreEqual(1, Integer(Length(Found)));
    Assert.IsFalse(Whole);
    Found := TPropertyFromAccessors.At(Tree, Panel, 3, TPropertyFromAccessorsOptions.Default, Whole);
    Assert.AreEqual(1, Integer(Length(Found)));
    Assert.IsTrue(Whole);
    Assert.AreEqual(0, Integer(Length(TPropertyFromAccessors.At(Tree, Panel, 5, TPropertyFromAccessorsOptions.Default,
      Whole))));
  finally
    Tree.Free;
  end;
end;

procedure TPropertyFromAccessorsTests.ClassGetsAllProperties;
var
  Source: string;
begin
  Source := UnitText('  TA = class'#10'  public'#10'    function GetCaption: string;'#10'    function IsEmpty: Boolean;'#10 +
    '  end;'#10'  TB = class(TA)'#10'  protected'#10'    function GetSize: Integer;'#10'  end;'#10, '');
  Assert.AreEqual(UnitText('  TA = class'#10'  public'#10'    function GetCaption: string;'#10 +
    '    function IsEmpty: Boolean;'#10'    property Caption: string read GetCaption;'#10 +
    '    property Empty: Boolean read IsEmpty;'#10'  end;'#10'  TB = class(TA)'#10'  protected'#10 +
    '    function GetSize: Integer;'#10'    property Size: Integer read GetSize;'#10'  end;'#10, ''), Create_(Source));
end;

/// <summary>Index des ersten Bezeichners AName ab Zeile ALine.</summary>
function TokenOf(ATree: TSyntaxTree; const AName: string; ALine: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ATree.Tokens) do
    if (ATree.Tokens[Index].StartPos.Line >= ALine) and SameText(ATree.Tokens[Index].Text, AName) then
      Exit(Index);
  Result := -1;
end;

const
  Uses_ =
    'unit V;'#10 +                                       // 0
    'interface'#10 +                                     // 1
    'implementation'#10 +                                // 2
    'procedure Run(P: TPanel; L: TList);'#10 +           // 3
    'var'#10 +                                           // 4
    '  S: string;'#10 +                                  // 5
    'begin'#10 +                                         // 6
    '  P.SetCaption(''Bereit'');'#10 +                   // 7
    '  S := P.GetCaption;'#10 +                          // 8
    '  Show(P.GetCaption, 1);'#10 +                      // 9
    '  Hook(@P.GetCaption);'#10 +                        // 10
    '  P.OnChange := P.SetCaption;'#10 +                 // 11
    '  if P.GetCaption = '''' then'#10 +                 // 12
    '    L.SetItem(L.Count - 1, P.GetCaption());'#10 +   // 13
    '  S := L.GetItem(2) + S;'#10 +                      // 14
    '  inherited SetCaption(S);'#10 +                    // 15
    '  S := Copy(P.SetCaption(S), 1);'#10 +              // 16
    '  P.GetCaption;'#10 +                               // 17
    '  Lists[0].Owner.SetCaption(S)'#10 +                // 18
    'end;'#10 +
    'end.';

procedure TPropertyFromAccessorsTests.ClassifiesUses;
var
  Tree: TSyntaxTree;
  Argument: Integer;

  function UseAt(const AName: string; ALine: Integer; AGetter: Boolean): TAccessorUse;
  begin
    Result := TPropertyFromAccessors.UseOf(Tree.Tokens, TokenOf(Tree, AName, ALine), AGetter);
  end;

begin
  Tree := TPascalParser.Parse(Uses_);
  try
    Assert.AreEqual(Ord(TAccessorUse.Call), Ord(UseAt('SetCaption', 7, False)));
    Assert.AreEqual(Ord(TAccessorUse.Unclear), Ord(UseAt('GetCaption', 8, True)));
    Assert.AreEqual('S', Tree.Tokens[TPropertyFromAccessors.UnclearTarget(Tree.Tokens, TokenOf(Tree, 'GetCaption', 8),
      Argument)].Text);
    Assert.AreEqual(-1, Argument);
    Assert.AreEqual(Ord(TAccessorUse.Unclear), Ord(UseAt('GetCaption', 9, True)));
    Assert.AreEqual('Show', Tree.Tokens[TPropertyFromAccessors.UnclearTarget(Tree.Tokens,
      TokenOf(Tree, 'GetCaption', 9), Argument)].Text);
    Assert.AreEqual(0, Argument);
    Assert.AreEqual(Ord(TAccessorUse.Pointer_), Ord(UseAt('GetCaption', 10, True)));
    Assert.AreEqual(Ord(TAccessorUse.Pointer_), Ord(UseAt('SetCaption', 11, False)));
    Assert.AreEqual(Ord(TAccessorUse.Call), Ord(UseAt('GetCaption', 12, True)));
    Assert.AreEqual(Ord(TAccessorUse.Call), Ord(UseAt('SetItem', 13, False)));
    Assert.AreEqual(Ord(TAccessorUse.Call), Ord(UseAt('GetCaption', 13, True)));
    Assert.AreEqual(Ord(TAccessorUse.Call), Ord(UseAt('GetItem', 14, True)));
    Assert.AreEqual(Ord(TAccessorUse.Keep), Ord(UseAt('SetCaption', 15, False)));
    Assert.AreEqual(Ord(TAccessorUse.Keep), Ord(UseAt('SetCaption', 16, False)));
    Assert.AreEqual(Ord(TAccessorUse.Keep), Ord(UseAt('GetCaption', 17, True)));
    Assert.AreEqual(Ord(TAccessorUse.Call), Ord(UseAt('SetCaption', 18, False)));
  finally
    Tree.Free;
  end;
end;

procedure TPropertyFromAccessorsTests.RewritesCalls;
var
  Tree: TSyntaxTree;
  Caption, Items: TAccessorProperty;
  Edits, Added: TArray<TTextEdit>;

  procedure Add(const AName: string; ALine: Integer; const AProperty: TAccessorProperty; AGetter: Boolean);
  begin
    Assert.IsTrue(TPropertyFromAccessors.CallEdit(Tree.Tokens, TokenOf(Tree, AName, ALine), AProperty, AGetter,
      Added), AName);
    Edits := Edits + Added;
  end;

begin
  Caption := Default(TAccessorProperty);
  Caption.Name := 'Caption';
  Items := Default(TAccessorProperty);
  Items.Name := 'Items';
  Items.IndexCount := 1;
  Edits := nil;
  Tree := TPascalParser.Parse(Uses_);
  try
    Add('SetCaption', 7, Caption, False);
    Add('GetCaption', 8, Caption, True);
    Add('SetItem', 13, Items, False);
    Add('GetCaption', 13, Caption, True);
    Add('GetItem', 14, Items, True);
    Add('SetCaption', 18, Caption, False);
    // Falsche Zahl Argumente: keine Umstellung.
    Assert.IsFalse(TPropertyFromAccessors.CallEdit(Tree.Tokens, TokenOf(Tree, 'GetItem', 14), Caption, True,
      Added));
  finally
    Tree.Free;
  end;
  Assert.Contains(TChangeSignature.ApplyEdits(Uses_, Edits), '  P.Caption := ''Bereit'';'#10'  S := P.Caption;'#10);
  Assert.Contains(TChangeSignature.ApplyEdits(Uses_, Edits), '    L.Items[L.Count - 1] := P.Caption;'#10 +
    '  S := L.Items[2] + S;'#10);
  Assert.Contains(TChangeSignature.ApplyEdits(Uses_, Edits), '  Lists[0].Owner.Caption := S'#10);
end;

procedure TPropertyFromAccessorsTests.PluralNames;
begin
  Assert.AreEqual('Items', TPropertyFromAccessors.Plural('Item'));
  Assert.AreEqual('Entries', TPropertyFromAccessors.Plural('Entry'));
  Assert.AreEqual('Keys', TPropertyFromAccessors.Plural('Key'));
  Assert.AreEqual('Boxes', TPropertyFromAccessors.Plural('Box'));
  Assert.AreEqual('Matches', TPropertyFromAccessors.Plural('Match'));
end;

initialization
  TDUnitX.RegisterTestFixture(TPropertyFromAccessorsTests);

end.
