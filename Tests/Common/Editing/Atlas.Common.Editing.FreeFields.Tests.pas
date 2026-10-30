unit Atlas.Common.Editing.FreeFields.Tests;

// Tests für „Felder im Destruktor freigeben“ (#666): Erkennung, Ausnahmen,
// unklare Fälle, Freigabe im vorhandenen und im neuen Destruktor; Erzeugungen
// außerhalb von Klassen und class destructor (#971).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFreeFieldsTests = class
  public
    [Test]
    procedure CreatedAndNotFreedIsFound;
    [Test]
    procedure OwnerInterfaceAndFreedAreSilent;
    [Test]
    procedure RecordWithCreateIsSilent;
    [Test]
    procedure CreationInPrivateHelper;
    [Test]
    procedure PublicHelperIsNotFollowed;
    [Test]
    procedure ReturnedOrPassedIsUnclear;
    [Test]
    procedure WritablePropertyIsUnclear;
    [Test]
    procedure ObjectListIsNormalField;
    [Test]
    procedure MissingDestructorIsCreated;
    [Test]
    procedure GenericClassKeepsParameters;
    [Test]
    procedure NoPublicSectionGetsOne;
    [Test]
    procedure ExistingDestructorBeforeInherited;
    [Test]
    procedure ExistingDestructorWithoutInherited;
    [Test]
    procedure DeclaredDestructorGetsBody;
    [Test]
    procedure ReverseCreationOrder;
    [Test]
    procedure FreeAndNilStyle;
    [Test]
    procedure ActionsOnFieldAndClass;
    [Test]
    procedure InterfaceFieldTakesOverObject;
    [Test]
    procedure ComponentFieldAsOwner;
    [Test]
    procedure HandOverAndCastToInterface;
    [Test]
    procedure ObjectCreationOutsideClasses;
    [Test]
    procedure HandOverToOwningListIsSilent;
    [Test]
    procedure DynamicArrayIsNoObject;
    [Test]
    procedure ClassDestructorIsCreatedOrFilled;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.FreeFields;

function Analyze(const AText: string): TArray<TOwnedField>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TFreeFields.Analyze(Tree, AText, nil);
  finally
    Tree.Free;
  end;
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

/// <summary>Wendet die Edits (nicht überlappend, Zeilen mit #10) von hinten nach vorn an.</summary>
function Apply(const AText: string; const AEdits: TArray<TTextEdit>): string;
var
  Lines: TArray<string>;
  Offsets: TArray<Integer>;
  Order: TArray<Integer>;
  Index, Inner, Swap, Start, Stop: Integer;

  function OffsetOf(const APos: TTextPosition): Integer;
  begin
    Result := Offsets[APos.Line] + APos.Character;
  end;

begin
  Lines := AText.Split([#10]);
  SetLength(Offsets, Length(Lines) + 1);
  Offsets[0] := 0;
  for Index := 0 to High(Lines) do
    Offsets[Index + 1] := Offsets[Index] + Length(Lines[Index]) + 1;
  SetLength(Order, Length(AEdits));
  for Index := 0 to High(Order) do
    Order[Index] := Index;
  for Index := 0 to High(Order) do
    for Inner := Index + 1 to High(Order) do
      if OffsetOf(AEdits[Order[Index]].Range.StartPos) < OffsetOf(AEdits[Order[Inner]].Range.StartPos) then
      begin
        Swap := Order[Index];
        Order[Index] := Order[Inner];
        Order[Inner] := Swap;
      end;
  Result := AText;
  for Index in Order do
  begin
    Start := OffsetOf(AEdits[Index].Range.StartPos);
    Stop := OffsetOf(AEdits[Index].Range.EndPos);
    Result := Copy(Result, 1, Start) + AEdits[Index].NewText + Copy(Result, Stop + 1, MaxInt);
  end;
end;

/// <summary>Alle nicht freigegebenen Felder freigeben; das Ergebnis parst und hat keinen Treffer mehr.</summary>
function FreeAll(const AText: string; AStyle: TFreeFieldsStyle): string;
var
  Tree: TSyntaxTree;
  Fields, Missing: TArray<TOwnedField>;
  Field: TOwnedField;
  Edits: TArray<TTextEdit>;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Fields := TFreeFields.Analyze(Tree, AText, nil);
    Missing := nil;
    for Field in Fields do
      if Field.State = TOwnedFieldState.NotFreed then
        Missing := Missing + [Field];
    Assert.IsTrue(TFreeFields.Edits(Tree, AText, Missing, AStyle, Edits), AText);
  finally
    Tree.Free;
  end;
  Result := Apply(AText, Edits);
  Assert.IsTrue(Parses(Result), Result);
  Assert.AreEqual(0, Integer(Length(Analyze(Result))), Result);
end;

const
  OrderList =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TOrderList = class'#10 +
    '  private'#10 +
    '    FItems: TObjectList<TOrder>;'#10 +
    '    FIndex: TDictionary<Integer, TOrder>;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    procedure Clear;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TOrderList.Create;'#10 +
    'begin'#10 +
    '  inherited Create;'#10 +
    '  FItems := TObjectList<TOrder>.Create(True);'#10 +
    '  FIndex := TDictionary<Integer, TOrder>.Create;'#10 +
    'end;'#10 +
    'procedure TOrderList.Clear;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

procedure TFreeFieldsTests.CreatedAndNotFreedIsFound;
var
  Fields: TArray<TOwnedField>;
begin
  Fields := Analyze(OrderList);
  Assert.AreEqual(2, Integer(Length(Fields)));
  Assert.AreEqual('FItems', Fields[0].Name);
  Assert.AreEqual('TOrderList', Fields[0].ClassName);
  Assert.AreEqual(3, Fields[0].ClassLine);
  Assert.AreEqual('TOrderList.Create', Fields[0].CreatedIn);
  Assert.AreEqual('TObjectList<TOrder>', Fields[0].CreatedType);
  Assert.AreEqual(5, Fields[0].Range.StartPos.Line);
  Assert.AreEqual(4, Fields[0].Range.StartPos.Character);
  Assert.AreEqual(10, Fields[0].Range.EndPos.Character);
  Assert.AreEqual(Ord(TOwnedFieldState.NotFreed), Ord(Fields[0].State));
  Assert.AreEqual('FIndex', Fields[1].Name);
  Assert.AreEqual(1, Fields[1].Order);
end;

procedure TFreeFieldsTests.OwnerInterfaceAndFreedAreSilent;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TPanel2 = class(TCustomPanel)'#10 +
    '  end;'#10 +
    '  TView = class(TComponent)'#10 +
    '  private'#10 +
    '    FButton: TButton;'#10 +
    '    FPanel: TPanel2;'#10 +
    '    FLog: ILog;'#10 +
    '    FList, FOther: TStringList;'#10 +
    '    FLater: TStringList;'#10 +
    '  public'#10 +
    '    constructor Create(AOwner: TComponent); override;'#10 +
    '    destructor Destroy; override;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TView.Create(AOwner: TComponent);'#10 +
    'begin'#10 +
    '  inherited;'#10 +
    '  FButton := TButton.Create(Self);'#10 +
    '  FPanel := TPanel2.Create(FHost);'#10 +
    '  FLog := TFileLog.Create;'#10 +
    '  FList := TStringList.Create;'#10 +
    '  Self.FOther := TStringList.Create;'#10 +
    'end;'#10 +
    'destructor TView.Destroy;'#10 +
    'begin'#10 +
    '  FList.Free;'#10 +
    '  FreeAndNil(Self.FOther);'#10 +
    '  inherited;'#10 +
    'end;'#10 +
    'end.';
begin
  // TButton: Owner Self; TPanel2: TComponent-Nachfahr mit Owner; ILog: Interface; FList, FOther: freigegeben;
  // FLater: nicht erzeugt.
  Assert.AreEqual(0, Integer(Length(Analyze(Text))));
end;

procedure TFreeFieldsTests.RecordWithCreateIsSilent;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TPair = record'#10 +
    '    constructor Create(A: Integer);'#10 +
    '  end;'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FWatch: TStopwatch;'#10 +
    '    FPair: TPair;'#10 +
    '    FNil: TButton;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TFoo.Create;'#10 +
    'begin'#10 +
    '  FWatch := TStopwatch.Create;'#10 +
    '  FPair := TPair.Create(1);'#10 +
    '  FNil := TButton.Create(nil);'#10 +
    'end;'#10 +
    'end.';
var
  Fields: TArray<TOwnedField>;
begin
  // Records schweigen; eine Komponente mit Owner nil gehört der Klasse.
  Fields := Analyze(Text);
  Assert.AreEqual(1, Integer(Length(Fields)));
  Assert.AreEqual('FNil', Fields[0].Name);
end;

procedure TFreeFieldsTests.InterfaceFieldTakesOverObject;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FLog: ILog;'#10 +
    '    FLogImpl: TLog;'#10 +
    '    FCheck: TRegEx;'#10 +
    '    FRest: TLog;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    function Take: TLog;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TFoo.Create;'#10 +
    'begin'#10 +
    '  FLogImpl := TLog.Create;'#10 +
    '  FCheck := TRegEx.Create(''x'');'#10 +
    '  FRest := TLog.Create;'#10 +
    'end;'#10 +
    'function TFoo.Take: TLog;'#10 +
    'begin'#10 +
    '  Result := FLogImpl;'#10 +
    '  Self.FLog := FLogImpl;'#10 +
    'end;'#10 +
    'end.';
var
  Fields: TArray<TOwnedField>;
begin
  // FLogImpl gehört der Referenzzählung von FLog, auch wenn es vorher zurückgegeben wird (#918);
  // TRegEx ist ein Record.
  Fields := Analyze(Text);
  Assert.AreEqual(1, Integer(Length(Fields)));
  Assert.AreEqual('FRest', Fields[0].Name);
  Assert.AreEqual(Ord(TOwnedFieldState.NotFreed), Ord(Fields[0].State));
end;

procedure TFreeFieldsTests.ComponentFieldAsOwner;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TChoiceBox = class(TComboBox)'#10 +
    '  end;'#10 +
    '  THelper = class'#10 +
    '  end;'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FHost: TForm;'#10 +
    '    FBox: TCanvasBox;'#10 +
    '    FMenu: TPopupMenu;'#10 +
    '    FItem: TMenuItem;'#10 +
    '    FChoice: TChoiceBox;'#10 +
    '    FHelper: THelper;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    destructor Destroy; override;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TFoo.Create;'#10 +
    'begin'#10 +
    '  FHost := TForm.CreateNew(nil);'#10 +
    '  FBox := TCanvasBox.Create(FHost);'#10 +
    '  FItem := TMenuItem.Create(FMenu);'#10 +
    '  FChoice := TChoiceBox.Create(Self);'#10 +
    '  FHelper := THelper.Create(Self);'#10 +
    'end;'#10 +
    'destructor TFoo.Destroy;'#10 +
    'begin'#10 +
    '  FHost.Free;'#10 +
    '  FMenu.Free;'#10 +
    '  inherited;'#10 +
    'end;'#10 +
    'end.';
var
  Fields: TArray<TOwnedField>;
begin
  // Komponentenfeld als Owner, bekannte VCL-Komponente, Vorfahr ohne Index mit Self (#918);
  // eine Klasse ohne Vorfahren ist sicher keine Komponente und bleibt trotz Self gemeldet.
  Fields := Analyze(Text);
  Assert.AreEqual(1, Integer(Length(Fields)));
  Assert.AreEqual('FHelper', Fields[0].Name);
end;

procedure TFreeFieldsTests.HandOverAndCastToInterface;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FEnv: IEnvironment;'#10 +
    '    FEnvObject: TObject;'#10 +
    '    FWatcher: TWatcher;'#10 +
    '    FTemp: TWatcher;'#10 +
    '    FButton: TButton;'#10 +
    '  public'#10 +
    '    constructor Create(AEvents: TEvents);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TFoo.Create(AEvents: TEvents);'#10 +
    'begin'#10 +
    '  FEnvObject := TEnvironment.Create;'#10 +
    '  FEnv := TEnvironment(FEnvObject);'#10 +
    '  FWatcher := TWatcher.Create;'#10 +
    '  AEvents.Add(FWatcher);'#10 +
    '  FTemp := TWatcher.Create;'#10 +
    '  AEvents.Notify(FTemp);'#10 +
    '  FButton := TButton.Create(Self);'#10 +
    '  AEvents.Add(FButton);'#10 +
    'end;'#10 +
    'end.';
var
  Fields: TArray<TOwnedField>;
begin
  // Typumwandlung in ein Interface-Feld: still; Add übergibt (unklar); Notify übergibt nicht;
  // eine Komponente mit Owner bleibt auch weitergereicht still (#918).
  Fields := Analyze(Text);
  Assert.AreEqual(2, Integer(Length(Fields)));
  Assert.AreEqual('FWatcher', Fields[0].Name);
  Assert.AreEqual(Ord(TOwnedFieldState.Unclear), Ord(Fields[0].State));
  Assert.AreEqual('wird in TFoo.Create an AEvents.Add übergeben', Fields[0].Reason);
  Assert.AreEqual('FTemp', Fields[1].Name);
  Assert.AreEqual(Ord(TOwnedFieldState.NotFreed), Ord(Fields[1].State));
end;

procedure TFreeFieldsTests.HandOverToOwningListIsSilent;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TParticipant = class'#10 +
    '  end;'#10 +
    '  TEvents = class'#10 +
    '  private'#10 +
    '    FItems: TObjectList<TParticipant>;'#10 +
    '  public'#10 +
    '    procedure Add(AItem: TParticipant);'#10 +
    '  end;'#10 +
    '  TPlain = class'#10 +
    '  public'#10 +
    '    procedure Add(AItem: TParticipant);'#10 +
    '  end;'#10 +
    '  TFoo = class'#10 +
    '  private type'#10 +
    '    TWatcher = class(TParticipant)'#10 +
    '    end;'#10 +
    '  private'#10 +
    '    FEvents: TEvents;'#10 +
    '    FPlain: TPlain;'#10 +
    '    FOwning: TObjectList<TWatcher>;'#10 +
    '    FLoose: TObjectList<TWatcher>;'#10 +
    '    FWatcher, FListed, FLoosely, FPlainly: TWatcher;'#10 +
    '  public'#10 +
    '    constructor Create(AEvents: TEvents; APlain: TPlain);'#10 +
    '    destructor Destroy; override;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TFoo.Create(AEvents: TEvents; APlain: TPlain);'#10 +
    'begin'#10 +
    '  FEvents := AEvents;'#10 +
    '  FPlain := APlain;'#10 +
    '  FOwning := TObjectList<TWatcher>.Create;'#10 +
    '  FLoose := TObjectList<TWatcher>.Create(False);'#10 +
    '  FWatcher := TWatcher.Create;'#10 +
    '  FEvents.Add(FWatcher);'#10 +
    '  FListed := TWatcher.Create;'#10 +
    '  FOwning.Add(FListed);'#10 +
    '  FLoosely := TWatcher.Create;'#10 +
    '  FLoose.Add(FLoosely);'#10 +
    '  FPlainly := TWatcher.Create;'#10 +
    '  FPlain.Add(FPlainly);'#10 +
    'end;'#10 +
    'destructor TFoo.Destroy;'#10 +
    'begin'#10 +
    '  FOwning.Free;'#10 +
    '  FLoose.Free;'#10 +
    '  inherited;'#10 +
    'end;'#10 +
    'end.';
var
  Fields: TArray<TOwnedField>;
begin
  // TEvents hält seine Teilnehmer in einer TObjectList, FOwning besitzt seine Elemente: beide übernehmen.
  // Eine mit False erzeugte Liste und eine Klasse ohne besitzende Liste bleiben unklar.
  Fields := Analyze(Text);
  Assert.AreEqual(2, Integer(Length(Fields)));
  Assert.AreEqual('FLoosely', Fields[0].Name);
  Assert.AreEqual(Ord(TOwnedFieldState.Unclear), Ord(Fields[0].State));
  Assert.AreEqual('wird in TFoo.Create an FLoose.Add übergeben', Fields[0].Reason);
  Assert.AreEqual('FPlainly', Fields[1].Name);
  Assert.AreEqual(Ord(TOwnedFieldState.Unclear), Ord(Fields[1].State));
end;

procedure TFreeFieldsTests.DynamicArrayIsNoObject;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FNames: TArray<string>;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    function Names: TArray<string>;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TFoo.Create;'#10 +
    'begin'#10 +
    '  FNames := TArray<string>.Create(''a'', ''b'');'#10 +
    'end;'#10 +
    'function TFoo.Names: TArray<string>;'#10 +
    'begin'#10 +
    '  Result := FNames;'#10 +
    'end;'#10 +
    'end.';
begin
  // TArray<T> ist ein dynamisches Array: Referenzzählung, keine Freigabe.
  Assert.AreEqual(0, Integer(Length(Analyze(Text))));
end;

procedure TFreeFieldsTests.CreationInPrivateHelper;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  strict private'#10 +
    '    FA: TList;'#10 +
    '    FB: TList;'#10 +
    '    procedure Init;'#10 +
    '  private'#10 +
    '    procedure InitMore;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TFoo.Create;'#10 +
    'begin'#10 +
    '  inherited Create;'#10 +
    '  Init;'#10 +
    'end;'#10 +
    'procedure TFoo.Init;'#10 +
    'begin'#10 +
    '  FA := TList.Create;'#10 +
    '  Self.InitMore();'#10 +
    'end;'#10 +
    'procedure TFoo.InitMore;'#10 +
    'begin'#10 +
    '  FB := TList.Create;'#10 +
    'end;'#10 +
    'end.';
var
  Fields: TArray<TOwnedField>;
begin
  Fields := Analyze(Text);
  Assert.AreEqual(2, Integer(Length(Fields)));
  Assert.AreEqual('TFoo.Init', Fields[0].CreatedIn);
  Assert.AreEqual('TFoo.InitMore', Fields[1].CreatedIn);
  FreeAll(Text, TFreeFieldsStyle.Free);
end;

procedure TFreeFieldsTests.PublicHelperIsNotFollowed;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FA: TList;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    procedure Reset;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TFoo.Create;'#10 +
    'begin'#10 +
    '  Reset;'#10 +
    'end;'#10 +
    'procedure TFoo.Reset;'#10 +
    'begin'#10 +
    '  FA := TList.Create;'#10 +
    'end;'#10 +
    'end.';
begin
  Assert.AreEqual(0, Integer(Length(Analyze(Text))));
end;

procedure TFreeFieldsTests.ReturnedOrPassedIsUnclear;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FA, FB, FC, FD: TList;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    function TakeA: TList;'#10 +
    '    function TakeB: TList;'#10 +
    '    procedure Hand(AOther: TBar);'#10 +
    '    procedure SetD(AValue: TList);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TFoo.Create;'#10 +
    'begin'#10 +
    '  FA := TList.Create;'#10 +
    '  FB := TList.Create;'#10 +
    '  FC := TList.Create;'#10 +
    '  FD := TList.Create;'#10 +
    'end;'#10 +
    'function TFoo.TakeA: TList;'#10 +
    'begin'#10 +
    '  Result := FA;'#10 +
    'end;'#10 +
    'function TFoo.TakeB: TList;'#10 +
    'begin'#10 +
    '  Exit(Self.FB);'#10 +
    'end;'#10 +
    'procedure TFoo.Hand(AOther: TBar);'#10 +
    'begin'#10 +
    '  AOther.Items := FC;'#10 +
    'end;'#10 +
    'procedure TFoo.SetD(AValue: TList);'#10 +
    'begin'#10 +
    '  FD := AValue;'#10 +
    'end;'#10 +
    'end.';
var
  Fields: TArray<TOwnedField>;
  Field: TOwnedField;
begin
  Fields := Analyze(Text);
  Assert.AreEqual(4, Integer(Length(Fields)));
  for Field in Fields do
    Assert.AreEqual(Ord(TOwnedFieldState.Unclear), Ord(Field.State), Field.Name);
  Assert.AreEqual('wird von TFoo.TakeA zurückgegeben', Fields[0].Reason);
  Assert.AreEqual('wird von TFoo.TakeB zurückgegeben', Fields[1].Reason);
  Assert.AreEqual('wird in TFoo.Hand an AOther.Items übergeben', Fields[2].Reason);
  Assert.AreEqual('wird in TFoo.SetD auch ohne Create zugewiesen', Fields[3].Reason);
end;

procedure TFreeFieldsTests.WritablePropertyIsUnclear;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FA, FB: TList;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    property A: TList read FA write FA;'#10 +
    '    property B: TList read FB;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TFoo.Create;'#10 +
    'begin'#10 +
    '  FA := TList.Create;'#10 +
    '  FB := TList.Create;'#10 +
    '  FB := nil;'#10 +
    '  FB := TList.Create;'#10 +
    'end;'#10 +
    'end.';
var
  Fields: TArray<TOwnedField>;
begin
  Fields := Analyze(Text);
  Assert.AreEqual(2, Integer(Length(Fields)));
  Assert.AreEqual(Ord(TOwnedFieldState.Unclear), Ord(Fields[0].State));
  Assert.AreEqual('kann über die Property A von außen gesetzt werden', Fields[0].Reason);
  // Nur lesbare Property und nil-Zuweisung lassen das Feld eigen.
  Assert.AreEqual(Ord(TOwnedFieldState.NotFreed), Ord(Fields[1].State));
end;

procedure TFreeFieldsTests.ObjectListIsNormalField;
var
  Fields: TArray<TOwnedField>;
begin
  // Mit OwnsObjects gibt die Liste ihre Elemente frei, sich selbst aber nicht.
  Fields := Analyze(OrderList);
  Assert.AreEqual('TObjectList<TOrder>', Fields[0].TypeName);
  Assert.AreEqual(Ord(TOwnedFieldState.NotFreed), Ord(Fields[0].State));
end;

procedure TFreeFieldsTests.MissingDestructorIsCreated;
var
  Result_: string;
begin
  Result_ := FreeAll(OrderList, TFreeFieldsStyle.Free);
  Assert.AreEqual(
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TOrderList = class'#10 +
    '  private'#10 +
    '    FItems: TObjectList<TOrder>;'#10 +
    '    FIndex: TDictionary<Integer, TOrder>;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    destructor Destroy; override;'#10 +
    '    procedure Clear;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TOrderList.Create;'#10 +
    'begin'#10 +
    '  inherited Create;'#10 +
    '  FItems := TObjectList<TOrder>.Create(True);'#10 +
    '  FIndex := TDictionary<Integer, TOrder>.Create;'#10 +
    'end;'#10 +
    #10 +
    'destructor TOrderList.Destroy;'#10 +
    'begin'#10 +
    '  FIndex.Free;'#10 +
    '  FItems.Free;'#10 +
    '  inherited;'#10 +
    'end;'#10 +
    'procedure TOrderList.Clear;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.', Result_);
end;

procedure TFreeFieldsTests.GenericClassKeepsParameters;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TCache<T: class> = class'#10 +
    '  private'#10 +
    '    FItems: TList<T>;'#10 +
    '  public'#10 +
    '    constructor Create(ACapacity: Integer);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TCache<T>.Create(ACapacity: Integer);'#10 +
    'begin'#10 +
    '  FItems := TList<T>.Create;'#10 +
    'end;'#10 +
    'end.';
var
  Result_: string;
begin
  Result_ := FreeAll(Text, TFreeFieldsStyle.Free);
  Assert.IsTrue(Result_.Contains('destructor TCache<T>.Destroy;'#10'begin'#10'  FItems.Free;'#10'  inherited;'),
    Result_);
end;

procedure TFreeFieldsTests.NoPublicSectionGetsOne;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  protected'#10 +
    '    FA: TList;'#10 +
    '    constructor Create;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TFoo.Create;'#10 +
    'begin'#10 +
    '  FA := TList.Create;'#10 +
    'end;'#10 +
    'end.';
var
  Result_: string;
begin
  Result_ := FreeAll(Text, TFreeFieldsStyle.Free);
  Assert.IsTrue(Result_.Contains('    constructor Create;'#10'  public'#10'    destructor Destroy; override;'#10 +
    '  end;'), Result_);
end;

procedure TFreeFieldsTests.ExistingDestructorBeforeInherited;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FA, FB: TList;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    destructor Destroy; override;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TFoo.Create;'#10 +
    'begin'#10 +
    '  FA := TList.Create;'#10 +
    '  FB := TList.Create;'#10 +
    'end;'#10 +
    'destructor TFoo.Destroy;'#10 +
    'begin'#10 +
    '  FB.Free;'#10 +
    '  inherited Destroy;'#10 +
    'end;'#10 +
    'end.';
var
  Result_: string;
begin
  Result_ := FreeAll(Text, TFreeFieldsStyle.Free);
  Assert.IsTrue(Result_.Contains('  FB.Free;'#10'  FA.Free;'#10'  inherited Destroy;'), Result_);
end;

procedure TFreeFieldsTests.ExistingDestructorWithoutInherited;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FA: TList;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    destructor Destroy; override;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TFoo.Create;'#10 +
    'begin'#10 +
    '  FA := TList.Create;'#10 +
    'end;'#10 +
    'destructor TFoo.Destroy;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
var
  Result_: string;
begin
  Result_ := FreeAll(Text, TFreeFieldsStyle.Free);
  Assert.IsTrue(Result_.Contains('destructor TFoo.Destroy;'#10'begin'#10'  FA.Free;'#10'end;'), Result_);
end;

procedure TFreeFieldsTests.DeclaredDestructorGetsBody;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FA: TList;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    destructor Destroy; override;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TFoo.Create;'#10 +
    'begin'#10 +
    '  FA := TList.Create;'#10 +
    'end;'#10 +
    'end.';
var
  Result_: string;
begin
  Result_ := FreeAll(Text, TFreeFieldsStyle.Free);
  // Keine zweite Deklaration, nur der Rumpf.
  Assert.AreEqual(1, Integer(Length(Result_.Split(['destructor Destroy;'])) - 1), Result_);
  Assert.IsTrue(Result_.Contains('destructor TFoo.Destroy;'#10'begin'#10'  FA.Free;'#10'  inherited;'#10'end;'),
    Result_);
end;

procedure TFreeFieldsTests.ReverseCreationOrder;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FC, FA, FB: TList;'#10 +
    '    procedure Init;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TFoo.Create;'#10 +
    'begin'#10 +
    '  FA := TList.Create;'#10 +
    '  Init;'#10 +
    '  FC := TList.Create;'#10 +
    'end;'#10 +
    'procedure TFoo.Init;'#10 +
    'begin'#10 +
    '  FB := TList.Create;'#10 +
    'end;'#10 +
    'end.';
var
  Result_: string;
begin
  Result_ := FreeAll(Text, TFreeFieldsStyle.Free);
  Assert.IsTrue(Result_.Contains('  FC.Free;'#10'  FB.Free;'#10'  FA.Free;'#10'  inherited;'), Result_);
end;

procedure TFreeFieldsTests.FreeAndNilStyle;
var
  Result_: string;
begin
  Result_ := FreeAll(OrderList, TFreeFieldsStyle.FreeAndNil);
  Assert.IsTrue(Result_.Contains('  FreeAndNil(FIndex);'#10'  FreeAndNil(FItems);'#10'  inherited;'), Result_);
  Assert.AreEqual(Ord(TFreeFieldsStyle.FreeAndNil), Ord(TFreeFields.StyleOf('freeAndNil')));
  Assert.AreEqual(Ord(TFreeFieldsStyle.Free), Ord(TFreeFields.StyleOf('free')));
end;

procedure TFreeFieldsTests.ActionsOnFieldAndClass;
var
  Tree: TSyntaxTree;
  Actions: TArray<TCodeAction>;
begin
  Tree := TPascalParser.Parse(OrderList);
  try
    // Feldzeile: Feld und ganze Klasse.
    Actions := TFreeFields.Actions(Tree, OrderList, nil, 5, TFreeFieldsStyle.Free, True);
    Assert.AreEqual(2, Integer(Length(Actions)));
    Assert.AreEqual('Im Destruktor freigeben', Actions[0].Title);
    Assert.AreEqual('Alle eigenen Objekte freigeben (2)', Actions[1].Title);
    Assert.IsTrue(Parses(Apply(OrderList, Actions[0].Edits)));
    // Ohne Feldaktion (die Regel liefert sie) bleibt die für die Klasse.
    Actions := TFreeFields.Actions(Tree, OrderList, nil, 5, TFreeFieldsStyle.Free, False);
    Assert.AreEqual(1, Integer(Length(Actions)));
    // Kopfzeile der Klasse.
    Actions := TFreeFields.Actions(Tree, OrderList, nil, 3, TFreeFieldsStyle.Free, True);
    Assert.AreEqual(1, Integer(Length(Actions)));
    Assert.AreEqual('Alle eigenen Objekte freigeben (2)', Actions[0].Title);
    // Andere Zeile.
    Actions := TFreeFields.Actions(Tree, OrderList, nil, 8, TFreeFieldsStyle.Free, True);
    Assert.AreEqual(0, Integer(Length(Actions)));
  finally
    Tree.Free;
  end;
end;

procedure TFreeFieldsTests.ObjectCreationOutsideClasses;
const
  Source = 'unit U;'#10'interface'#10'implementation'#10'var'#10'  A: TListe;'#10'  B: TStopwatch;'#10 +
    '  C: TDatenmodul;'#10'initialization'#10'  A := TListe.Create;'#10'  B := TStopwatch.Create;'#10 +
    '  C := TDatenmodul.Create(Application);'#10'end.';
var
  Tree: TSyntaxTree;
  Section: TSyntaxNode;
  TypeName: string;
  Owned: Boolean;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Section := Tree.Root.FindChild(TSyntaxKind.InitializationSection);
    Assert.IsTrue(TFreeFields.ObjectCreation(Tree, Source, nil, Section[0][1], TypeName, Owned));
    Assert.AreEqual('TListe', TypeName);
    Assert.IsFalse(Owned);
    Assert.IsFalse(TFreeFields.ObjectCreation(Tree, Source, nil, Section[1][1], TypeName, Owned), 'Record');
    Assert.IsTrue(TFreeFields.ObjectCreation(Tree, Source, nil, Section[2][1], TypeName, Owned));
    Assert.IsTrue(Owned, 'Owner Application');
    Assert.IsTrue(TFreeFields.IsObjectType(Tree, Source, nil, 'TListe'));
    Assert.IsFalse(TFreeFields.IsObjectType(Tree, Source, nil, 'IListe'));
    Assert.IsFalse(TFreeFields.IsObjectType(Tree, Source, nil, 'TStopwatch'));
  finally
    Tree.Free;
  end;
end;

procedure TFreeFieldsTests.ClassDestructorIsCreatedOrFilled;
const
  Source = 'unit U;'#10'interface'#10'type'#10'  TDienst<T> = class'#10'    class var FA: TListe;'#10 +
    '    class constructor Create;'#10'  end;'#10'implementation'#10'class constructor TDienst<T>.Create;'#10 +
    'begin'#10'  FA := TListe.Create;'#10'end;'#10'end.';
  Filled = 'unit U;'#10'interface'#10'type'#10'  TDienst = class'#10'    class var FA: TListe;'#10 +
    '    class constructor Create;'#10'    class destructor Destroy;'#10'  end;'#10'implementation'#10 +
    'class constructor TDienst.Create;'#10'begin'#10'  FA := TListe.Create;'#10'end;'#10 +
    'class destructor TDienst.Destroy;'#10'begin'#10'  Protokolliere;'#10'end;'#10'end.';
var
  Tree: TSyntaxTree;
  Edits: TArray<TTextEdit>;
  Decl: TSyntaxNode;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Decl := Tree.Root.FindChild(TSyntaxKind.InterfaceSection)[0][0];
    Assert.IsTrue(TFreeFields.ClassDestructorEdits(Tree, Source, Decl, ['FreeAndNil(FA);'], Edits));
    Assert.AreEqual('unit U;'#10'interface'#10'type'#10'  TDienst<T> = class'#10'    class var FA: TListe;'#10 +
      '    class constructor Create;'#10'    class destructor Destroy;'#10'  end;'#10'implementation'#10 +
      'class constructor TDienst<T>.Create;'#10'begin'#10'  FA := TListe.Create;'#10'end;'#10#10 +
      'class destructor TDienst<T>.Destroy;'#10'begin'#10'  FreeAndNil(FA);'#10'end;'#10'end.', Apply(Source, Edits));
    Assert.IsTrue(Parses(Apply(Source, Edits)));
  finally
    Tree.Free;
  end;
  Tree := TPascalParser.Parse(Filled);
  try
    Decl := Tree.Root.FindChild(TSyntaxKind.InterfaceSection)[0][0];
    Assert.IsTrue(TFreeFields.ClassDestructorEdits(Tree, Filled, Decl, ['FreeAndNil(FA);'], Edits));
    Assert.AreEqual(1, Integer(Length(Edits)));
    Assert.AreEqual(StringReplace(Filled, '  Protokolliere;'#10, '  Protokolliere;'#10'  FreeAndNil(FA);'#10, []),
      Apply(Filled, Edits));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TFreeFieldsTests);

end.
