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
    procedure RecordInterfaceFieldTakesOverObject;
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
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := TFreeFields.Analyze(mTree, AText, nil);
  finally
    mTree.Free;
  end;
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

/// <summary>Wendet die Edits (nicht überlappend, Zeilen mit #10) von hinten nach vorn an.</summary>
function Apply(const AText: string; const AEdits: TArray<TTextEdit>): string;
var
  mLines: TArray<string>;
  mOffsets: TArray<Integer>;
  mOrder: TArray<Integer>;
  mIndex, mInner, mSwap, mStart, mStop: Integer;

  function OffsetOf(const APos: TTextPosition): Integer;
  begin
    Result := mOffsets[APos.Line] + APos.Character;
  end;

begin
  mLines := AText.Split([#10]);
  SetLength(mOffsets, Length(mLines) + 1);
  mOffsets[0] := 0;
  for mIndex := 0 to High(mLines) do
  begin
    mOffsets[mIndex + 1] := mOffsets[mIndex] + Length(mLines[mIndex]) + 1;
  end;
  SetLength(mOrder, Length(AEdits));
  for mIndex := 0 to High(mOrder) do
  begin
    mOrder[mIndex] := mIndex;
  end;
  for mIndex := 0 to High(mOrder) do
  begin
    for mInner := mIndex + 1 to High(mOrder) do
    begin
      if OffsetOf(AEdits[mOrder[mIndex]].Range.StartPos) < OffsetOf(AEdits[mOrder[mInner]].Range.StartPos) then
      begin
        mSwap := mOrder[mIndex];
        mOrder[mIndex] := mOrder[mInner];
        mOrder[mInner] := mSwap;
      end;
    end;
  end;
  Result := AText;
  for mIndex in mOrder do
  begin
    mStart := OffsetOf(AEdits[mIndex].Range.StartPos);
    mStop := OffsetOf(AEdits[mIndex].Range.EndPos);
    Result := Copy(Result, 1, mStart) + AEdits[mIndex].NewText + Copy(Result, mStop + 1, MaxInt);
  end;
end;

/// <summary>Alle nicht freigegebenen Felder freigeben; das Ergebnis parst und hat keinen Treffer mehr.</summary>
function FreeAll(const AText: string; AStyle: TFreeFieldsStyle): string;
var
  mTree: TSyntaxTree;
  mFields, mMissing: TArray<TOwnedField>;
  mField: TOwnedField;
  mEdits: TArray<TTextEdit>;
begin
  mTree := TPascalParser.Parse(AText);
  try
    mFields := TFreeFields.Analyze(mTree, AText, nil);
    mMissing := nil;
    for mField in mFields do
    begin
      if mField.State = TOwnedFieldState.NotFreed then
      begin
        mMissing := mMissing + [mField];
      end;
    end;
    Assert.IsTrue(TFreeFields.Edits(mTree, AText, mMissing, AStyle, mEdits), AText);
  finally
    mTree.Free;
  end;
  Result := Apply(AText, mEdits);
  Assert.IsTrue(Parses(Result), Result);
  Assert.AreEqual(0, Integer(Length(Analyze(Result))), Result);
end;

const
  cOrderList =
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
  mFields: TArray<TOwnedField>;
begin
  mFields := Analyze(cOrderList);
  Assert.AreEqual(2, Integer(Length(mFields)));
  Assert.AreEqual('FItems', mFields[0].Name);
  Assert.AreEqual('TOrderList', mFields[0].ClassName);
  Assert.AreEqual(3, mFields[0].ClassLine);
  Assert.AreEqual('TOrderList.Create', mFields[0].CreatedIn);
  Assert.AreEqual('TObjectList<TOrder>', mFields[0].CreatedType);
  Assert.AreEqual(5, mFields[0].Range.StartPos.Line);
  Assert.AreEqual(4, mFields[0].Range.StartPos.Character);
  Assert.AreEqual(10, mFields[0].Range.EndPos.Character);
  Assert.AreEqual(Ord(TOwnedFieldState.NotFreed), Ord(mFields[0].State));
  Assert.AreEqual('FIndex', mFields[1].Name);
  Assert.AreEqual(1, mFields[1].Order);
end;

procedure TFreeFieldsTests.OwnerInterfaceAndFreedAreSilent;
const
  cText =
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
  Assert.AreEqual(0, Integer(Length(Analyze(cText))));
end;

procedure TFreeFieldsTests.RecordWithCreateIsSilent;
const
  cText =
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
  mFields: TArray<TOwnedField>;
begin
  // Records schweigen; eine Komponente mit Owner nil gehört der Klasse.
  mFields := Analyze(cText);
  Assert.AreEqual(1, Integer(Length(mFields)));
  Assert.AreEqual('FNil', mFields[0].Name);
end;

procedure TFreeFieldsTests.InterfaceFieldTakesOverObject;
const
  cText =
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
  mFields: TArray<TOwnedField>;
begin
  // FLogImpl gehört der Referenzzählung von FLog, auch wenn es vorher zurückgegeben wird (#918);
  // TRegEx ist ein Record.
  mFields := Analyze(cText);
  Assert.AreEqual(1, Integer(Length(mFields)));
  Assert.AreEqual('FRest', mFields[0].Name);
  Assert.AreEqual(Ord(TOwnedFieldState.NotFreed), Ord(mFields[0].State));
end;

procedure TFreeFieldsTests.RecordInterfaceFieldTakesOverObject;
const
  cText =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TSystem = record'#10 +
    '    Log: ILog;'#10 +
    '    Name: TLog;'#10 +
    '  end;'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FSystem: TSystem;'#10 +
    '    FLogImpl: TLog;'#10 +
    '    FOther: TLog;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TFoo.Create;'#10 +
    'begin'#10 +
    '  FLogImpl := TLog.Create;'#10 +
    '  FOther := TLog.Create;'#10 +
    '  FSystem.Log := FLogImpl;'#10 +
    '  Self.FSystem.Name := FOther;'#10 +
    'end;'#10 +
    'end.';
var
  mFields: TArray<TOwnedField>;
begin
  // FSystem.Log ist ein Interface: dessen Referenzzählung gibt FLogImpl frei (#1519); FSystem.Name nicht.
  mFields := Analyze(cText);
  Assert.AreEqual(1, Integer(Length(mFields)));
  Assert.AreEqual('FOther', mFields[0].Name);
  Assert.AreEqual(Ord(TOwnedFieldState.Unclear), Ord(mFields[0].State));
end;

procedure TFreeFieldsTests.ComponentFieldAsOwner;
const
  cText =
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
  mFields: TArray<TOwnedField>;
begin
  // Komponentenfeld als Owner, bekannte VCL-Komponente, Vorfahr ohne Index mit Self (#918);
  // eine Klasse ohne Vorfahren ist sicher keine Komponente und bleibt trotz Self gemeldet.
  mFields := Analyze(cText);
  Assert.AreEqual(1, Integer(Length(mFields)));
  Assert.AreEqual('FHelper', mFields[0].Name);
end;

procedure TFreeFieldsTests.HandOverAndCastToInterface;
const
  cText =
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
  mFields: TArray<TOwnedField>;
begin
  // Typumwandlung in ein Interface-Feld: still; Add übergibt (unklar); Notify übergibt nicht;
  // eine Komponente mit Owner bleibt auch weitergereicht still (#918).
  mFields := Analyze(cText);
  Assert.AreEqual(2, Integer(Length(mFields)));
  Assert.AreEqual('FWatcher', mFields[0].Name);
  Assert.AreEqual(Ord(TOwnedFieldState.Unclear), Ord(mFields[0].State));
  Assert.AreEqual('wird in TFoo.Create an AEvents.Add übergeben', mFields[0].Reason);
  Assert.AreEqual('FTemp', mFields[1].Name);
  Assert.AreEqual(Ord(TOwnedFieldState.NotFreed), Ord(mFields[1].State));
end;

const
  cHandOverText =
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

procedure TFreeFieldsTests.HandOverToOwningListIsSilent;
var
  mFields: TArray<TOwnedField>;
begin
  // TEvents hält seine Teilnehmer in einer TObjectList, FOwning besitzt seine Elemente: beide übernehmen.
  // Eine mit False erzeugte Liste und eine Klasse ohne besitzende Liste bleiben unklar.
  mFields := Analyze(cHandOverText);
  Assert.AreEqual(2, Integer(Length(mFields)));
  Assert.AreEqual('FLoosely', mFields[0].Name);
  Assert.AreEqual(Ord(TOwnedFieldState.Unclear), Ord(mFields[0].State));
  Assert.AreEqual('wird in TFoo.Create an FLoose.Add übergeben', mFields[0].Reason);
  Assert.AreEqual('FPlainly', mFields[1].Name);
  Assert.AreEqual(Ord(TOwnedFieldState.Unclear), Ord(mFields[1].State));
end;

procedure TFreeFieldsTests.DynamicArrayIsNoObject;
const
  cText =
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
  Assert.AreEqual(0, Integer(Length(Analyze(cText))));
end;

procedure TFreeFieldsTests.CreationInPrivateHelper;
const
  cText =
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
  mFields: TArray<TOwnedField>;
begin
  mFields := Analyze(cText);
  Assert.AreEqual(2, Integer(Length(mFields)));
  Assert.AreEqual('TFoo.Init', mFields[0].CreatedIn);
  Assert.AreEqual('TFoo.InitMore', mFields[1].CreatedIn);
  FreeAll(cText, TFreeFieldsStyle.Free);
end;

procedure TFreeFieldsTests.PublicHelperIsNotFollowed;
const
  cText =
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
  Assert.AreEqual(0, Integer(Length(Analyze(cText))));
end;

procedure TFreeFieldsTests.ReturnedOrPassedIsUnclear;
const
  cText =
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
  mFields: TArray<TOwnedField>;
  mField: TOwnedField;
begin
  mFields := Analyze(cText);
  Assert.AreEqual(4, Integer(Length(mFields)));
  for mField in mFields do
  begin
    Assert.AreEqual(Ord(TOwnedFieldState.Unclear), Ord(mField.State), mField.Name);
  end;
  Assert.AreEqual('wird von TFoo.TakeA zurückgegeben', mFields[0].Reason);
  Assert.AreEqual('wird von TFoo.TakeB zurückgegeben', mFields[1].Reason);
  Assert.AreEqual('wird in TFoo.Hand an AOther.Items übergeben', mFields[2].Reason);
  Assert.AreEqual('wird in TFoo.SetD auch ohne Create zugewiesen', mFields[3].Reason);
end;

procedure TFreeFieldsTests.WritablePropertyIsUnclear;
const
  cText =
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
  mFields: TArray<TOwnedField>;
begin
  mFields := Analyze(cText);
  Assert.AreEqual(2, Integer(Length(mFields)));
  Assert.AreEqual(Ord(TOwnedFieldState.Unclear), Ord(mFields[0].State));
  Assert.AreEqual('kann über die Property A von außen gesetzt werden', mFields[0].Reason);
  // Nur lesbare Property und nil-Zuweisung lassen das Feld eigen.
  Assert.AreEqual(Ord(TOwnedFieldState.NotFreed), Ord(mFields[1].State));
end;

procedure TFreeFieldsTests.ObjectListIsNormalField;
var
  mFields: TArray<TOwnedField>;
begin
  // Mit OwnsObjects gibt die Liste ihre Elemente frei, sich selbst aber nicht.
  mFields := Analyze(cOrderList);
  Assert.AreEqual('TObjectList<TOrder>', mFields[0].TypeName);
  Assert.AreEqual(Ord(TOwnedFieldState.NotFreed), Ord(mFields[0].State));
end;

procedure TFreeFieldsTests.MissingDestructorIsCreated;
var
  mResult_: string;
begin
  mResult_ := FreeAll(cOrderList, TFreeFieldsStyle.Free);
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
    'end.', mResult_);
end;

procedure TFreeFieldsTests.GenericClassKeepsParameters;
const
  cText =
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
  mResult_: string;
begin
  mResult_ := FreeAll(cText, TFreeFieldsStyle.Free);
  Assert.IsTrue(mResult_.Contains('destructor TCache<T>.Destroy;'#10'begin'#10'  FItems.Free;'#10'  inherited;'),
    mResult_);
end;

procedure TFreeFieldsTests.NoPublicSectionGetsOne;
const
  cText =
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
  mResult_: string;
begin
  mResult_ := FreeAll(cText, TFreeFieldsStyle.Free);
  Assert.IsTrue(mResult_.Contains('    constructor Create;'#10'  public'#10'    destructor Destroy; override;'#10 +
    '  end;'), mResult_);
end;

procedure TFreeFieldsTests.ExistingDestructorBeforeInherited;
const
  cText =
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
  mResult_: string;
begin
  mResult_ := FreeAll(cText, TFreeFieldsStyle.Free);
  Assert.IsTrue(mResult_.Contains('  FB.Free;'#10'  FA.Free;'#10'  inherited Destroy;'), mResult_);
end;

procedure TFreeFieldsTests.ExistingDestructorWithoutInherited;
const
  cText =
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
  mResult_: string;
begin
  mResult_ := FreeAll(cText, TFreeFieldsStyle.Free);
  Assert.IsTrue(mResult_.Contains('destructor TFoo.Destroy;'#10'begin'#10'  FA.Free;'#10'end;'), mResult_);
end;

procedure TFreeFieldsTests.DeclaredDestructorGetsBody;
const
  cText =
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
  mResult_: string;
begin
  mResult_ := FreeAll(cText, TFreeFieldsStyle.Free);
  // Keine zweite Deklaration, nur der Rumpf.
  Assert.AreEqual(1, Integer(Length(mResult_.Split(['destructor Destroy;'])) - 1), mResult_);
  Assert.IsTrue(mResult_.Contains('destructor TFoo.Destroy;'#10'begin'#10'  FA.Free;'#10'  inherited;'#10'end;'),
    mResult_);
end;

procedure TFreeFieldsTests.ReverseCreationOrder;
const
  cText =
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
  mResult_: string;
begin
  mResult_ := FreeAll(cText, TFreeFieldsStyle.Free);
  Assert.IsTrue(mResult_.Contains('  FC.Free;'#10'  FB.Free;'#10'  FA.Free;'#10'  inherited;'), mResult_);
end;

procedure TFreeFieldsTests.FreeAndNilStyle;
var
  mResult_: string;
begin
  mResult_ := FreeAll(cOrderList, TFreeFieldsStyle.FreeAndNil);
  Assert.IsTrue(mResult_.Contains('  FreeAndNil(FIndex);'#10'  FreeAndNil(FItems);'#10'  inherited;'), mResult_);
  Assert.AreEqual(Ord(TFreeFieldsStyle.FreeAndNil), Ord(TFreeFields.StyleOf('freeAndNil')));
  Assert.AreEqual(Ord(TFreeFieldsStyle.Free), Ord(TFreeFields.StyleOf('free')));
end;

procedure TFreeFieldsTests.ActionsOnFieldAndClass;
var
  mTree: TSyntaxTree;
  mActions: TArray<TCodeAction>;
begin
  mTree := TPascalParser.Parse(cOrderList);
  try
    // Feldzeile: Feld und ganze Klasse.
    mActions := TFreeFields.Actions(mTree, cOrderList, nil, 5, TFreeFieldsStyle.Free, True);
    Assert.AreEqual(2, Integer(Length(mActions)));
    Assert.AreEqual('Im Destruktor freigeben', mActions[0].Title);
    Assert.AreEqual('Alle eigenen Objekte freigeben (2)', mActions[1].Title);
    Assert.IsTrue(Parses(Apply(cOrderList, mActions[0].Edits)));
    // Ohne Feldaktion (die Regel liefert sie) bleibt die für die Klasse.
    mActions := TFreeFields.Actions(mTree, cOrderList, nil, 5, TFreeFieldsStyle.Free, False);
    Assert.AreEqual(1, Integer(Length(mActions)));
    // Kopfzeile der Klasse.
    mActions := TFreeFields.Actions(mTree, cOrderList, nil, 3, TFreeFieldsStyle.Free, True);
    Assert.AreEqual(1, Integer(Length(mActions)));
    Assert.AreEqual('Alle eigenen Objekte freigeben (2)', mActions[0].Title);
    // Andere Zeile.
    mActions := TFreeFields.Actions(mTree, cOrderList, nil, 8, TFreeFieldsStyle.Free, True);
    Assert.AreEqual(0, Integer(Length(mActions)));
  finally
    mTree.Free;
  end;
end;

procedure TFreeFieldsTests.ObjectCreationOutsideClasses;
const
  cSource = 'unit U;'#10'interface'#10'implementation'#10'var'#10'  A: TListe;'#10'  B: TStopwatch;'#10 +
    '  C: TDatenmodul;'#10'initialization'#10'  A := TListe.Create;'#10'  B := TStopwatch.Create;'#10 +
    '  C := TDatenmodul.Create(Application);'#10'end.';
var
  mTree: TSyntaxTree;
  mSection: TSyntaxNode;
  mTypeName: string;
  mOwned: Boolean;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mSection := mTree.Root.FindChild(TSyntaxKind.InitializationSection);
    Assert.IsTrue(TFreeFields.ObjectCreation(mTree, cSource, nil, mSection[0][1], mTypeName, mOwned));
    Assert.AreEqual('TListe', mTypeName);
    Assert.IsFalse(mOwned);
    Assert.IsFalse(TFreeFields.ObjectCreation(mTree, cSource, nil, mSection[1][1], mTypeName, mOwned), 'Record');
    Assert.IsTrue(TFreeFields.ObjectCreation(mTree, cSource, nil, mSection[2][1], mTypeName, mOwned));
    Assert.IsTrue(mOwned, 'Owner Application');
    Assert.IsTrue(TFreeFields.IsObjectType(mTree, cSource, nil, 'TListe'));
    Assert.IsFalse(TFreeFields.IsObjectType(mTree, cSource, nil, 'IListe'));
    Assert.IsFalse(TFreeFields.IsObjectType(mTree, cSource, nil, 'TStopwatch'));
  finally
    mTree.Free;
  end;
end;

procedure TFreeFieldsTests.ClassDestructorIsCreatedOrFilled;
const
  cSource = 'unit U;'#10'interface'#10'type'#10'  TDienst<T> = class'#10'    class var FA: TListe;'#10 +
    '    class constructor Create;'#10'  end;'#10'implementation'#10'class constructor TDienst<T>.Create;'#10 +
    'begin'#10'  FA := TListe.Create;'#10'end;'#10'end.';
  cFilled = 'unit U;'#10'interface'#10'type'#10'  TDienst = class'#10'    class var FA: TListe;'#10 +
    '    class constructor Create;'#10'    class destructor Destroy;'#10'  end;'#10'implementation'#10 +
    'class constructor TDienst.Create;'#10'begin'#10'  FA := TListe.Create;'#10'end;'#10 +
    'class destructor TDienst.Destroy;'#10'begin'#10'  Protokolliere;'#10'end;'#10'end.';
var
  mTree: TSyntaxTree;
  mEdits: TArray<TTextEdit>;
  mDecl: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mDecl := mTree.Root.FindChild(TSyntaxKind.InterfaceSection)[0][0];
    Assert.IsTrue(TFreeFields.ClassDestructorEdits(mTree, cSource, mDecl, ['FreeAndNil(FA);'], mEdits));
    Assert.AreEqual('unit U;'#10'interface'#10'type'#10'  TDienst<T> = class'#10'    class var FA: TListe;'#10 +
      '    class constructor Create;'#10'    class destructor Destroy;'#10'  end;'#10'implementation'#10 +
      'class constructor TDienst<T>.Create;'#10'begin'#10'  FA := TListe.Create;'#10'end;'#10#10 +
      'class destructor TDienst<T>.Destroy;'#10'begin'#10'  FreeAndNil(FA);'#10'end;'#10'end.', Apply(cSource, mEdits));
    Assert.IsTrue(Parses(Apply(cSource, mEdits)));
  finally
    mTree.Free;
  end;
  mTree := TPascalParser.Parse(cFilled);
  try
    mDecl := mTree.Root.FindChild(TSyntaxKind.InterfaceSection)[0][0];
    Assert.IsTrue(TFreeFields.ClassDestructorEdits(mTree, cFilled, mDecl, ['FreeAndNil(FA);'], mEdits));
    Assert.AreEqual(1, Integer(Length(mEdits)));
    Assert.AreEqual(StringReplace(cFilled, '  Protokolliere;'#10, '  Protokolliere;'#10'  FreeAndNil(FA);'#10, []),
      Apply(cFilled, mEdits));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TFreeFieldsTests);

end.
