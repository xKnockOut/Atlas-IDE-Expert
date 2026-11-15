unit Atlas.Core.Forms.PropertyValues.Tests;

// Tests für das Setzen von Eigenschaften eines offenen Formulars über RTTI (#309, #721, #1967): Pfade über
// Objekt-Eigenschaften, Werte je Art, Rückgängig auf den Vorgabewert, Prüfen vor dem Setzen.

interface

uses
  System.Classes,
  DUnitX.TestFramework;

type
  {$SCOPEDENUMS ON}
  TSampleKind = (First, Second, Third);
  {$SCOPEDENUMS OFF}
  TSampleKinds = set of TSampleKind;
  /// <summary>Ganzzahl mit Bezeichnern (wie TColor mit clRed).</summary>
  TSampleShade = type Integer;

  TSampleFont = class(TPersistent)
  private
    FName: string;
  published
    property Name: string read FName write FName;
  end;

  TSampleControl = class(TComponent)
  private
    FCaption: string;
    FCount: Integer;
    FShade: TSampleShade;
    FBig: Int64;
    FKind: TSampleKind;
    FKinds: TSampleKinds;
    FRatio: Double;
    FFont: TSampleFont;
    FEmpty: TSampleFont;
    FFixed: Integer;
    FOnChange: TNotifyEvent;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Caption: string read FCaption write FCaption;
    property Count: Integer read FCount write FCount default 3;
    property Shade: TSampleShade read FShade write FShade;
    property Big: Int64 read FBig write FBig;
    property Kind: TSampleKind read FKind write FKind default TSampleKind.Second;
    property Kinds: TSampleKinds read FKinds write FKinds;
    property Ratio: Double read FRatio write FRatio;
    property Font: TSampleFont read FFont write FFont;
    property Empty: TSampleFont read FEmpty write FEmpty;
    property Fixed: Integer read FFixed;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  [TestFixture]
  TAtlasFormPropertyValuesTests = class
  private
    FRoot: TComponent;
    FControl: TSampleControl;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ResolvesNestedPath;
    [Test]
    procedure RejectsUnresolvablePaths;
    [Test]
    procedure WritesEachKind;
    [Test]
    procedure IntegerAcceptsIdentifiers;
    [Test]
    procedure RejectsBadValues;
    [Test]
    procedure RemovedLineResetsToDefault;
    [Test]
    procedure CheckChangesNothingAndFindsRoot;
    [Test]
    procedure CheckNamesComponentInReason;
  end;

implementation

uses
  System.SysUtils,
  System.TypInfo,
  Atlas.Core.Forms.Changes,
  Atlas.Core.Forms.PropertyValues;

type
  /// <summary>Bezeichner in TIntToIdent: unter FPC AnsiString.</summary>
  TIdentText = {$IFDEF FPC}AnsiString{$ELSE}string{$ENDIF};

const
  cShades: array[0..1] of TIdentMapEntry = ((Value: 1; Name: 'shLight'), (Value: 2; Name: 'shDark'));

function ShadeToInt(const AIdent: TIdentText; var AInt: Longint): Boolean;
begin
  Result := IdentToInt(AIdent, AInt, cShades);
end;

function IntToShade(AInt: Longint; var AIdent: TIdentText): Boolean;
begin
  Result := IntToIdent(AInt, AIdent, cShades);
end;

function Change(const AComponent, APath, AValue: string): TAtlasFormPropertyChange;
begin
  Result := Default(TAtlasFormPropertyChange);
  Result.Component := AComponent;
  Result.PropertyPath := APath;
  Result.Value := AValue;
end;

function Removal(const AComponent, APath: string): TAtlasFormPropertyChange;
begin
  Result := Change(AComponent, APath, '');
  Result.Removed := True;
end;

/// <summary>Pfad an AControl auflösen und AValue setzen; '' oder der Grund.</summary>
function WriteTo(AControl: TObject; const AChange: TAtlasFormPropertyChange): string;
var
  mInstance: TObject;
  mProp: PPropInfo;
begin
  Result := TAtlasFormPropertyValues.Resolve(AControl, AChange.PropertyPath, mInstance, mProp);
  if Result = '' then
  begin
    Result := TAtlasFormPropertyValues.WriteValue(mInstance, mProp, AChange, False);
  end;
end;

{ TSampleControl }

constructor TSampleControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCount := 3;
  FKind := TSampleKind.Second;
  FFont := TSampleFont.Create;
end;

destructor TSampleControl.Destroy;
begin
  FFont.Free;
  inherited Destroy;
end;

{ TAtlasFormPropertyValuesTests }

procedure TAtlasFormPropertyValuesTests.SetUp;
begin
  FRoot := TComponent.Create(nil);
  FRoot.Name := 'Form1';
  FControl := TSampleControl.Create(FRoot);
  FControl.Name := 'Button1';
end;

procedure TAtlasFormPropertyValuesTests.TearDown;
begin
  FControl := nil;
  FreeAndNil(FRoot);
end;

procedure TAtlasFormPropertyValuesTests.ResolvesNestedPath;
var
  mInstance: TObject;
  mProp: PPropInfo;
begin
  Assert.AreEqual('', TAtlasFormPropertyValues.Resolve(FControl, 'Font.Name', mInstance, mProp));
  Assert.AreSame(TObject(FControl.Font), mInstance);
  Assert.AreEqual('Name', string(mProp^.Name));
  Assert.AreEqual('', WriteTo(FControl, Change('Button1', 'Font.Name', '''Segoe UI''')));
  Assert.AreEqual('Segoe UI', FControl.Font.Name);
end;

procedure TAtlasFormPropertyValuesTests.RejectsUnresolvablePaths;
var
  mInstance: TObject;
  mProp: PPropInfo;
begin
  // Glied ist keine Objekt-Eigenschaft, Objekt nicht gesetzt, letzte Eigenschaft fehlt oder nur lesbar.
  Assert.Contains(TAtlasFormPropertyValues.Resolve(FControl, 'Caption.Name', mInstance, mProp), 'Caption');
  Assert.Contains(TAtlasFormPropertyValues.Resolve(FControl, 'Empty.Name', mInstance, mProp), 'Empty');
  Assert.Contains(TAtlasFormPropertyValues.Resolve(FControl, 'Missing', mInstance, mProp), 'Missing');
  Assert.Contains(TAtlasFormPropertyValues.Resolve(FControl, 'Fixed', mInstance, mProp), 'Fixed');
end;

procedure TAtlasFormPropertyValuesTests.WritesEachKind;
begin
  Assert.AreEqual('', WriteTo(FControl, Change('Button1', 'Caption', '''Hallo''')));
  Assert.AreEqual('', WriteTo(FControl, Change('Button1', 'Count', '42')));
  Assert.AreEqual('', WriteTo(FControl, Change('Button1', 'Big', '5000000000')));
  Assert.AreEqual('', WriteTo(FControl, Change('Button1', 'Kind', 'Third')));
  Assert.AreEqual('', WriteTo(FControl, Change('Button1', 'Kinds', '[First,Third]')));
  Assert.AreEqual('', WriteTo(FControl, Change('Button1', 'Ratio', '1.5')));
  Assert.AreEqual('Hallo', FControl.Caption);
  Assert.AreEqual(42, FControl.Count);
  Assert.AreEqual(Int64(5000000000), FControl.Big);
  Assert.AreEqual(Ord(TSampleKind.Third), Ord(FControl.Kind));
  Assert.IsTrue(TSampleKind.First in FControl.Kinds);
  Assert.IsFalse(TSampleKind.Second in FControl.Kinds);
  Assert.IsTrue(TSampleKind.Third in FControl.Kinds);
  Assert.AreEqual(Double(1.5), FControl.Ratio, 0.0001);
end;

procedure TAtlasFormPropertyValuesTests.IntegerAcceptsIdentifiers;
begin
  Assert.AreEqual('', WriteTo(FControl, Change('Button1', 'Shade', 'shDark')));
  Assert.AreEqual(2, Integer(FControl.Shade));
  Assert.AreNotEqual('', WriteTo(FControl, Change('Button1', 'Shade', 'shMissing')));
  Assert.AreEqual(2, Integer(FControl.Shade));
end;

procedure TAtlasFormPropertyValuesTests.RejectsBadValues;
begin
  Assert.Contains(WriteTo(FControl, Change('Button1', 'Caption', 'Hallo')), 'Caption');
  Assert.Contains(WriteTo(FControl, Change('Button1', 'Count', 'viele')), 'viele');
  Assert.Contains(WriteTo(FControl, Change('Button1', 'Big', 'x')), 'Big');
  Assert.Contains(WriteTo(FControl, Change('Button1', 'Kind', 'Fourth')), 'Fourth');
  Assert.Contains(WriteTo(FControl, Change('Button1', 'Kinds', '[Fourth]')), 'Kinds');
  Assert.Contains(WriteTo(FControl, Change('Button1', 'Ratio', '1,5')), 'Ratio');
  // Ereignisse gehen über die Ereignis-Zuordnungen, nicht als Eigenschaft.
  Assert.Contains(WriteTo(FControl, Change('Button1', 'OnChange', 'Button1Change')), 'OnChange');
  Assert.AreEqual('', FControl.Caption);
  Assert.AreEqual(3, FControl.Count);
end;

procedure TAtlasFormPropertyValuesTests.RemovedLineResetsToDefault;
begin
  FControl.Caption := 'Hallo';
  FControl.Count := 9;
  FControl.Kind := TSampleKind.First;
  Assert.AreEqual('', WriteTo(FControl, Removal('Button1', 'Caption')));
  Assert.AreEqual('', WriteTo(FControl, Removal('Button1', 'Count')));
  Assert.AreEqual('', WriteTo(FControl, Removal('Button1', 'Kind')));
  Assert.AreEqual('', FControl.Caption);
  Assert.AreEqual(3, FControl.Count);
  Assert.AreEqual(Ord(TSampleKind.Second), Ord(FControl.Kind));
  // Ohne default-Angabe kein Vorgabewert.
  Assert.Contains(WriteTo(FControl, Removal('Button1', 'Ratio')), 'Ratio');
  Assert.Contains(WriteTo(FControl, Removal('Button1', 'Shade')), 'Shade');
end;

procedure TAtlasFormPropertyValuesTests.CheckChangesNothingAndFindsRoot;
var
  mChanges: TArray<TAtlasFormPropertyChange>;
  mTargets: TArray<TObject>;
  mProps: TArray<PPropInfo>;
begin
  mChanges := TArray<TAtlasFormPropertyChange>.Create(Change('Button1', 'Count', '7'),
    Change('Button1', 'Font.Name', '''Arial'''));
  Assert.AreEqual('', TAtlasFormPropertyValues.Check(FRoot, mChanges, mTargets, mProps));
  Assert.AreEqual(2, Integer(Length(mTargets)));
  Assert.AreSame(TObject(FControl.Font), mTargets[1]);
  // Nur geprüft.
  Assert.AreEqual(3, FControl.Count);
  TAtlasFormPropertyValues.Apply(mTargets, mProps, mChanges);
  Assert.AreEqual(7, FControl.Count);
  Assert.AreEqual('Arial', FControl.Font.Name);
  Assert.AreSame(FRoot, TAtlasFormPropertyValues.ComponentOf(FRoot, ''));
  Assert.AreSame(TComponent(FControl), TAtlasFormPropertyValues.ComponentOf(FRoot, 'Button1'));
  Assert.IsNull(TAtlasFormPropertyValues.ComponentOf(FRoot, 'Button2'));
end;

procedure TAtlasFormPropertyValuesTests.CheckNamesComponentInReason;
var
  mTargets: TArray<TObject>;
  mProps: TArray<PPropInfo>;
begin
  // Eine falsche Änderung: nichts gesetzt, auch nicht die richtige davor.
  Assert.StartsWith('Button1: ', TAtlasFormPropertyValues.Check(FRoot,
    TArray<TAtlasFormPropertyChange>.Create(Change('Button1', 'Count', '7'), Change('Button1', 'Count', 'x')),
    mTargets, mProps));
  Assert.AreEqual(3, FControl.Count);
  Assert.Contains(TAtlasFormPropertyValues.Check(FRoot,
    TArray<TAtlasFormPropertyChange>.Create(Change('Button2', 'Count', '7')), mTargets, mProps), 'Button2');
  Assert.AreEqual(0, Integer(Length(mTargets)));
end;

initialization
  RegisterIntegerConsts(TypeInfo(TSampleShade), ShadeToInt, IntToShade);

end.
