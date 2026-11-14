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
    /// <summary>At liest nur die Klasse, die die Zeile enthält: Treffer in der zweiten Klasse, nichts außerhalb.
    /// </summary>
    [Test]
    procedure AtFindsOnlyClassAtLine;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.PropertyFromAccessors;

const
  cPanel =
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
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := TPropertyFromAccessors.Find(mTree, AText, AOptions);
  finally
    mTree.Free;
  end;
end;

function Find(const AText: string): TArray<TAccessorProperty>; overload;
begin
  Result := Find(AText, TPropertyFromAccessorsOptions.Default);
end;

function Parses(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := Length(mTree.Diagnostics) = 0;
  finally
    mTree.Free;
  end;
end;

/// <summary>Alle gefundenen Properties anlegen, AHidden verbergen; das Ergebnis parst und hat keine fehlenden
/// Properties mehr.</summary>
function Create_(const AText: string; const AHidden: TArray<string>;
  const AOptions: TPropertyFromAccessorsOptions): string; overload;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := TChangeSignature.ApplyEdits(AText, TPropertyFromAccessors.Edits(mTree, AText,
      TPropertyFromAccessors.Find(mTree, AText, AOptions), AHidden, AOptions));
  finally
    mTree.Free;
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
  mFound: TArray<TAccessorProperty>;
  mSource: string;
begin
  mSource := UnitText('  TPanel = class'#10'  public'#10'    function GetCaption: string;'#10'  end;'#10, '');
  mFound := Find(mSource);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Caption', mFound[0].Name);
  Assert.IsFalse(mFound[0].Setter.Exists);
  Assert.AreEqual('property Caption: string read GetCaption;', mFound[0].Declaration);
  Assert.AreEqual(UnitText('  TPanel = class'#10'  public'#10'    function GetCaption: string;'#10 +
    '    property Caption: string read GetCaption;'#10'  end;'#10, ''), Create_(mSource));
end;

procedure TPropertyFromAccessorsTests.GetterAndSetter;
var
  mFound: TArray<TAccessorProperty>;
  mResult_: string;
begin
  mFound := Find(cPanel);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('TPanel', mFound[0].ClassName);
  Assert.AreEqual(3, mFound[0].ClassLine);
  Assert.AreEqual(7, mFound[0].Getter.NamePos.Line);
  Assert.AreEqual(13, mFound[0].Getter.NamePos.Character);
  Assert.AreEqual(8, mFound[0].Setter.NamePos.Line);
  // Der Getter liefert nicht nur das Feld: read GetCaption.
  Assert.AreEqual('property Caption: string read GetCaption write SetCaption;', mFound[0].Declaration);
  mResult_ := Create_(cPanel);
  Assert.Contains(mResult_, '    procedure SetCaption(const AValue: string);'#10 +
    '    property Caption: string read GetCaption write SetCaption;'#10'  end;');
end;

procedure TPropertyFromAccessorsTests.IndexedProperty;
var
  mFound: TArray<TAccessorProperty>;
begin
  mFound := Find(UnitText('  TList = class'#10'  public'#10'    function GetItem(AIndex: Integer): TObject;'#10 +
    '    procedure SetItem(AIndex: Integer; const AValue: TObject);'#10'  end;'#10, ''));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('property Items[AIndex: Integer]: TObject read GetItem write SetItem;', mFound[0].Declaration);
  // Ohne Getter: Indexparameter aus dem Setter.
  mFound := Find(UnitText('  TList = class'#10'  public'#10 +
    '    procedure SetEntry(const AName: string; AValue: Integer);'#10'  end;'#10, ''));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('property Entries[const AName: string]: Integer write SetEntry;', mFound[0].Declaration);
  // Indexparameter, die nicht passen: nur der Getter.
  mFound := Find(UnitText('  TList = class'#10'  public'#10'    function GetItem(AIndex: Integer): TObject;'#10 +
    '    procedure SetItem(const AName: string; const AValue: TObject);'#10'  end;'#10, ''));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('property Items[AIndex: Integer]: TObject read GetItem;', mFound[0].Declaration);
end;

procedure TPropertyFromAccessorsTests.BooleanWithIs;
var
  mFound: TArray<TAccessorProperty>;
begin
  mFound := Find(UnitText('  TList = class'#10'  public'#10'    function IsEmpty: Boolean;'#10 +
    '    function HasName: string;'#10'    function IsVisible: Boolean;'#10 +
    '    procedure SetVisible(AValue: Boolean);'#10'  end;'#10, ''));
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('property Empty: Boolean read IsEmpty;', mFound[0].Declaration);
  Assert.AreEqual('property Visible: Boolean read IsVisible write SetVisible;', mFound[1].Declaration);
end;

procedure TPropertyFromAccessorsTests.OwnPrefix;
var
  mOptions: TPropertyFromAccessorsOptions;
  mFound: TArray<TAccessorProperty>;
  mSource: string;
begin
  mSource := UnitText('  TFile = class'#10'  public'#10'    function ReadSize: Int64;'#10 +
    '    procedure WriteSize(AValue: Int64);'#10'    function GetName: string;'#10'  end;'#10, '');
  mOptions := TPropertyFromAccessorsOptions.Default;
  mOptions.Prefixes := ['Read', 'Write'];
  mFound := Find(mSource, mOptions);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('property Size: Int64 read ReadSize write WriteSize;', mFound[0].Declaration);
  // Ohne Get in der Liste bleibt GetName unbeachtet; mit den Standardpräfixen nur GetName.
  mFound := Find(mSource);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Name', mFound[0].Name);
end;

procedure TPropertyFromAccessorsTests.TrivialGetterReadsField;
var
  mFound: TArray<TAccessorProperty>;
begin
  mFound := Find(StringReplace(cPanel, 'FCaption + ''!''', 'FCaption', []));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('FCaption', mFound[0].ReadField);
  Assert.AreEqual('property Caption: string read FCaption write SetCaption;', mFound[0].Declaration);
  // Feld mit anderem Typ: read GetCaption.
  mFound := Find(StringReplace(StringReplace(cPanel, 'FCaption + ''!''', 'FCaption', []), 'FCaption: string',
    'FCaption: TCaption', []));
  Assert.AreEqual('', mFound[0].ReadField);
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
  mSource, mResult_: string;
  mOptions: TPropertyFromAccessorsOptions;
begin
  mSource := UnitText('  TA = class'#10'  protected'#10'    function GetCaption: string;'#10'  public'#10 +
    '    procedure SetCaption(const AValue: string);'#10'    procedure Run;'#10'  end;'#10, '');
  mResult_ := Create_(mSource);
  Assert.AreEqual(UnitText('  TA = class'#10'  protected'#10'    function GetCaption: string;'#10'  public'#10 +
    '    procedure SetCaption(const AValue: string);'#10'    procedure Run;'#10 +
    '    property Caption: string read GetCaption write SetCaption;'#10'  end;'#10, ''), mResult_);
  // Mindestens public, der public-Abschnitt steht aber vor dem Getter: neuer Abschnitt vor "end".
  mSource := UnitText('  TA = class'#10'  public'#10'    procedure Run;'#10'  private'#10 +
    '    function GetCaption: string;'#10'  end;'#10, '');
  mOptions := TPropertyFromAccessorsOptions.Default;
  mOptions.Section := TPropertySectionChoice.Public_;
  Assert.AreEqual(UnitText('  TA = class'#10'  public'#10'    procedure Run;'#10'  private'#10 +
    '    function GetCaption: string;'#10'  public'#10'    property Caption: string read GetCaption;'#10'  end;'#10,
    ''), Create_(mSource, nil, mOptions));
  // Sonst bleibt sie im Abschnitt des Getters.
  Assert.Contains(Create_(mSource), '    function GetCaption: string;'#10'    property Caption: string read GetCaption;');
end;

procedure TPropertyFromAccessorsTests.PublishedOpensSection;
var
  mOptions: TPropertyFromAccessorsOptions;
begin
  mOptions := TPropertyFromAccessorsOptions.Default;
  mOptions.Section := TPropertySectionChoice.Published_;
  Assert.AreEqual(UnitText('  TA = class'#10'  private'#10'    function GetCaption: string;'#10 +
    '    function GetSize: Integer;'#10'  published'#10'    property Caption: string read GetCaption;'#10 +
    '    property Size: Integer read GetSize;'#10'  end;'#10, ''),
    Create_(UnitText('  TA = class'#10'  private'#10'    function GetCaption: string;'#10 +
    '    function GetSize: Integer;'#10'  end;'#10, ''), nil, mOptions));
  mOptions.Section := TPropertySectionChoice.Public_;
  Assert.Contains(Create_(UnitText('  TA = class'#10'  private'#10'    function GetCaption: string;'#10 +
    '  end;'#10, ''), nil, mOptions), '  public'#10'    property Caption: string read GetCaption;'#10'  end;');
end;

procedure TPropertyFromAccessorsTests.HidesAccessors;
var
  mOptions: TPropertyFromAccessorsOptions;
begin
  mOptions := TPropertyFromAccessorsOptions.Default;
  mOptions.Hiding := TAccessorHiding.Private_;
  // Mit private-Abschnitt davor: die Methoden wandern dorthin.
  Assert.AreEqual(UnitText('  TPanel = class'#10'  private'#10'    FCaption: string;'#10 +
    '    function GetCaption: string;'#10'    procedure SetCaption(const AValue: string);'#10'  public'#10 +
    '    procedure Run;'#10'    property Caption: string read GetCaption write SetCaption;'#10'  end;'#10, ''),
    Create_(UnitText('  TPanel = class'#10'  private'#10'    FCaption: string;'#10'  public'#10 +
    '    function GetCaption: string;'#10'    procedure SetCaption(const AValue: string);'#10'    procedure Run;'#10 +
    '  end;'#10, ''), ['GetCaption', 'SetCaption'], mOptions));
  // Ohne: eigener Abschnitt vor der Property; nur freigegebene Methoden wandern, virtuelle nie.
  Assert.AreEqual(UnitText('  TPanel = class'#10'  public'#10'    procedure SetCaption(const AValue: string); virtual;'#10 +
    '  private'#10'    function GetCaption: string;'#10'  public'#10 +
    '    property Caption: string read GetCaption write SetCaption;'#10'  end;'#10, ''),
    Create_(UnitText('  TPanel = class'#10'  public'#10'    function GetCaption: string;'#10 +
    '    procedure SetCaption(const AValue: string); virtual;'#10'  end;'#10, ''), ['GetCaption', 'SetCaption'],
    mOptions));
end;

procedure TPropertyFromAccessorsTests.OfferedOnMethodAndClass;
var
  mTree: TSyntaxTree;
  mWhole: Boolean;
  mFound: TArray<TAccessorProperty>;
begin
  mTree := TPascalParser.Parse(cPanel);
  try
    mFound := TPropertyFromAccessors.At(mTree, cPanel, 8, TPropertyFromAccessorsOptions.Default, mWhole);
    Assert.AreEqual(1, Integer(Length(mFound)));
    Assert.IsFalse(mWhole);
    mFound := TPropertyFromAccessors.At(mTree, cPanel, 3, TPropertyFromAccessorsOptions.Default, mWhole);
    Assert.AreEqual(1, Integer(Length(mFound)));
    Assert.IsTrue(mWhole);
    Assert.AreEqual(0, Integer(Length(TPropertyFromAccessors.At(mTree, cPanel, 5, TPropertyFromAccessorsOptions.Default,
      mWhole))));
  finally
    mTree.Free;
  end;
end;

procedure TPropertyFromAccessorsTests.ClassGetsAllProperties;
var
  mSource: string;
begin
  mSource := UnitText('  TA = class'#10'  public'#10'    function GetCaption: string;'#10'    function IsEmpty: Boolean;'#10 +
    '  end;'#10'  TB = class(TA)'#10'  protected'#10'    function GetSize: Integer;'#10'  end;'#10, '');
  Assert.AreEqual(UnitText('  TA = class'#10'  public'#10'    function GetCaption: string;'#10 +
    '    function IsEmpty: Boolean;'#10'    property Caption: string read GetCaption;'#10 +
    '    property Empty: Boolean read IsEmpty;'#10'  end;'#10'  TB = class(TA)'#10'  protected'#10 +
    '    function GetSize: Integer;'#10'    property Size: Integer read GetSize;'#10'  end;'#10, ''), Create_(mSource));
end;

/// <summary>Index des ersten Bezeichners AName ab Zeile ALine.</summary>
function TokenOf(ATree: TSyntaxTree; const AName: string; ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATree.Tokens) do
  begin
    if (ATree.Tokens[mIndex].StartPos.Line >= ALine) and SameText(ATree.Tokens[mIndex].Text, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

const
  cUses_ =
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
  mTree: TSyntaxTree;
  mArgument: Integer;

  function UseAt(const AName: string; ALine: Integer; AGetter: Boolean): TAccessorUse;
  begin
    Result := TPropertyFromAccessors.UseOf(mTree.Tokens, TokenOf(mTree, AName, ALine), AGetter);
  end;

begin
  mTree := TPascalParser.Parse(cUses_);
  try
    Assert.AreEqual(Ord(TAccessorUse.Call), Ord(UseAt('SetCaption', 7, False)));
    Assert.AreEqual(Ord(TAccessorUse.Unclear), Ord(UseAt('GetCaption', 8, True)));
    Assert.AreEqual('S', mTree.Tokens[TPropertyFromAccessors.UnclearTarget(mTree.Tokens, TokenOf(mTree, 'GetCaption', 8),
      mArgument)].Text);
    Assert.AreEqual(-1, mArgument);
    Assert.AreEqual(Ord(TAccessorUse.Unclear), Ord(UseAt('GetCaption', 9, True)));
    Assert.AreEqual('Show', mTree.Tokens[TPropertyFromAccessors.UnclearTarget(mTree.Tokens,
      TokenOf(mTree, 'GetCaption', 9), mArgument)].Text);
    Assert.AreEqual(0, mArgument);
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
    mTree.Free;
  end;
end;

procedure TPropertyFromAccessorsTests.RewritesCalls;
var
  mTree: TSyntaxTree;
  mCaption, mItems: TAccessorProperty;
  mEdits, mAdded: TArray<TTextEdit>;

  procedure Add(const AName: string; ALine: Integer; const AProperty: TAccessorProperty; AGetter: Boolean);
  begin
    Assert.IsTrue(TPropertyFromAccessors.CallEdit(mTree.Tokens, TokenOf(mTree, AName, ALine), AProperty, AGetter,
      mAdded), AName);
    mEdits := mEdits + mAdded;
  end;

begin
  mCaption := Default(TAccessorProperty);
  mCaption.Name := 'Caption';
  mItems := Default(TAccessorProperty);
  mItems.Name := 'Items';
  mItems.IndexCount := 1;
  mEdits := nil;
  mTree := TPascalParser.Parse(cUses_);
  try
    Add('SetCaption', 7, mCaption, False);
    Add('GetCaption', 8, mCaption, True);
    Add('SetItem', 13, mItems, False);
    Add('GetCaption', 13, mCaption, True);
    Add('GetItem', 14, mItems, True);
    Add('SetCaption', 18, mCaption, False);
    // Falsche Zahl Argumente: keine Umstellung.
    Assert.IsFalse(TPropertyFromAccessors.CallEdit(mTree.Tokens, TokenOf(mTree, 'GetItem', 14), mCaption, True,
      mAdded));
  finally
    mTree.Free;
  end;
  Assert.Contains(TChangeSignature.ApplyEdits(cUses_, mEdits), '  P.Caption := ''Bereit'';'#10'  S := P.Caption;'#10);
  Assert.Contains(TChangeSignature.ApplyEdits(cUses_, mEdits), '    L.Items[L.Count - 1] := P.Caption;'#10 +
    '  S := L.Items[2] + S;'#10);
  Assert.Contains(TChangeSignature.ApplyEdits(cUses_, mEdits), '  Lists[0].Owner.Caption := S'#10);
end;

procedure TPropertyFromAccessorsTests.PluralNames;
begin
  Assert.AreEqual('Items', TPropertyFromAccessors.Plural('Item'));
  Assert.AreEqual('Entries', TPropertyFromAccessors.Plural('Entry'));
  Assert.AreEqual('Keys', TPropertyFromAccessors.Plural('Key'));
  Assert.AreEqual('Boxes', TPropertyFromAccessors.Plural('Box'));
  Assert.AreEqual('Matches', TPropertyFromAccessors.Plural('Match'));
end;

procedure TPropertyFromAccessorsTests.AtFindsOnlyClassAtLine;
var
  mSource: string;
  mTree: TSyntaxTree;
  mWhole: Boolean;
  mFound: TArray<TAccessorProperty>;
begin
  mSource := UnitText(
    '  TA = class'#10 +                          // 3
    '  public'#10 +                              // 4
    '    function GetName: string;'#10 +         // 5
    '  end;'#10 +                                // 6
    '  TB = class'#10 +                          // 7
    '  public'#10 +                              // 8
    '    function GetTitle: string;'#10 +        // 9
    '  end;'#10,                                 // 10
    'function TA.GetName: string; begin Result := ''''; end;'#10 +
    'function TB.GetTitle: string; begin Result := ''''; end;'#10);
  mTree := TPascalParser.Parse(mSource);
  try
    mFound := TPropertyFromAccessors.At(mTree, mSource, 9, TPropertyFromAccessorsOptions.Default, mWhole);
    Assert.AreEqual(1, Integer(Length(mFound)));
    Assert.AreEqual('Title', mFound[0].Name);
    mFound := TPropertyFromAccessors.At(mTree, mSource, 7, TPropertyFromAccessorsOptions.Default, mWhole);
    Assert.AreEqual(1, Integer(Length(mFound)));
    Assert.IsTrue(mWhole);
    Assert.AreEqual('TB', mFound[0].ClassName);
    Assert.AreEqual(0, Integer(Length(TPropertyFromAccessors.At(mTree, mSource, 12,
      TPropertyFromAccessorsOptions.Default, mWhole))));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPropertyFromAccessorsTests);

end.
