unit Atlas.Common.Editing.ExtractInterface.Tests;

// Tests für „Interface aus Klasse herauslösen“ (#664): Kandidaten und
// Vorgaben, Interface mit Überladungen, Standardwerten, Doku und Properties
// (auf Feld und auf Zugriffsmethoden), nicht wählbare generische Methode,
// Vorfahren TObject, TInterfacedObject, TComponent und unbekannt, Name
// ungültig oder vergeben, Ziel in derselben und in einer anderen Unit. Das
// Ergebnis parst, und die Klasse hat jede Methode des Interfaces.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TExtractInterfaceTests = class
  public
    [Test]
    procedure DefaultName;
    [Test]
    procedure Candidates;
    [Test]
    procedure SameUnit;
    [Test]
    procedure PropertyOnFieldGetsAccessors;
    [Test]
    procedure PropertyOnAccessorsTakesMethods;
    [Test]
    procedure AncestorTObject;
    [Test]
    procedure AncestorInterfaced;
    [Test]
    procedure AncestorWithoutInterface;
    [Test]
    procedure RejectsBadInput;
    [Test]
    procedure OtherUnit;
    [Test]
    procedure NewUnit;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Editing.ClassLayout,
  Atlas.Common.Editing.ExtractInterface;

const
  cGuid = '{11111111-2222-3333-4444-555555555555}';
  cRepository =
    'unit U;'#10 +                                                           // 0
    'interface'#10 +                                                         // 1
    'type'#10 +                                                              // 2
    '  TCustomerRepository = class'#10 +                                     // 3
    '  private'#10 +                                                         // 4
    '    FName: string;'#10 +                                                // 5
    '    FCount: Integer;'#10 +                                              // 6
    '    function GetItem(AIndex: Integer): string;'#10 +                    // 7
    '    procedure SetItem(AIndex: Integer; const AValue: string);'#10 +     // 8
    '  public'#10 +                                                          // 9
    '    constructor Create;'#10 +                                           // 10
    '    destructor Destroy; override;'#10 +                                 // 11
    '    /// Sucht einen Kunden.'#10 +                                       // 12
    '    function Find(const AId: Integer; ALimit: Integer = 10): string; overload; virtual;'#10 + // 13
    '    function Find(const AName: string): string; overload;'#10 +         // 14
    '    procedure Save(var AData: TBytes); stdcall;'#10 +                   // 15
    '    class function Default_: TCustomerRepository;'#10 +                 // 16
    '    function Convert<T>(const AValue: T): string;'#10 +                 // 17
    '    property Name: string read FName write FName;'#10 +                 // 18
    '    property Items[AIndex: Integer]: string read GetItem write SetItem; default;'#10 + // 19
    '  published'#10 +                                                       // 20
    '    property Count: Integer read FCount stored False;'#10 +             // 21
    '  end;'#10 +                                                            // 22
    'implementation'#10 +                                                    // 23
    #10 +                                                                    // 24
    'constructor TCustomerRepository.Create;'#10 +
    'begin'#10 +
    'end;'#10 +
    #10 +
    'destructor TCustomerRepository.Destroy;'#10 +
    'begin'#10 +
    '  inherited;'#10 +
    'end;'#10 +
    #10 +
    'function TCustomerRepository.GetItem(AIndex: Integer): string;'#10 +
    'begin'#10 +
    '  Result := IntToStr(AIndex);'#10 +
    'end;'#10 +
    #10 +
    'procedure TCustomerRepository.SetItem(AIndex: Integer; const AValue: string);'#10 +
    'begin'#10 +
    'end;'#10 +
    #10 +
    'function TCustomerRepository.Find(const AId: Integer; ALimit: Integer): string;'#10 +
    'begin'#10 +
    '  Result := '''';'#10 +
    'end;'#10 +
    #10 +
    'function TCustomerRepository.Find(const AName: string): string;'#10 +
    'begin'#10 +
    '  Result := AName;'#10 +
    'end;'#10 +
    #10 +
    'procedure TCustomerRepository.Save(var AData: TBytes);'#10 +
    'begin'#10 +
    'end;'#10 +
    #10 +
    'class function TCustomerRepository.Default_: TCustomerRepository;'#10 +
    'begin'#10 +
    '  Result := nil;'#10 +
    'end;'#10 +
    #10 +
    'function TCustomerRepository.Convert<T>(const AValue: T): string;'#10 +
    'begin'#10 +
    '  Result := '''';'#10 +
    'end;'#10 +
    #10 +
    'end.';

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

function NoLookup: TClassAncestorsLookup;
begin
  Result :=
    function(const AClassName: string; out AAncestors: TArray<string>): Boolean
    begin
      AAncestors := nil;
      Result := False;
    end;
end;

function Info(const AText: string; ALine: Integer): TExtractInterfaceInfo;
var
  mTree: TSyntaxTree;
  mReason: string;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Assert.IsTrue(TExtractInterface.Prepare(TClassSource.Create(mTree, AText, ALine),
      TExtractInterfaceLookups.Create(NoLookup(), nil, nil), Result, mReason), mReason);
  finally
    mTree.Free;
  end;
end;

function Ids(const AInfo: TExtractInterfaceInfo; const ANames: array of string): TArray<Integer>;
var
  mItem: TExtractCandidate;
  mName: string;
begin
  Result := nil;
  for mName in ANames do
  begin
    for mItem in AInfo.Candidates do
    begin
      if SameText(mItem.Name, mName) and ((mItem.Kind = TExtractCandidateKind.Method) or not ContainsText(mName,
        '(')) then
      begin
        Result := Result + [mItem.Id];
      end;
    end;
  end;
end;

function DefaultIds(const AInfo: TExtractInterfaceInfo): TArray<Integer>;
var
  mItem: TExtractCandidate;
begin
  Result := nil;
  for mItem in AInfo.Candidates do
  begin
    if mItem.Checked then
    begin
      Result := Result + [mItem.Id];
    end;
  end;
end;

/// <summary>Anfrage für das Interface AName mit AMembers und der festen Guid.</summary>
function Wanted(const AMembers: TArray<Integer>; const AName: string; ASameUnit: Boolean): TExtractInterfaceRequest;
begin
  Result := Default(TExtractInterfaceRequest);
  Result.Name := AName;
  Result.Members := AMembers;
  Result.Guid := cGuid;
  Result.SameUnit := ASameUnit;
end;

function TryPlan(const AText: string; ALine: Integer; const ARequest: TExtractInterfaceRequest;
  const ALookup: TClassAncestorsLookup; out APlan: TExtractInterfacePlan; out AReason: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := TExtractInterface.Plan(TClassSource.Create(mTree, AText, ALine), ARequest,
      TExtractInterfaceLookups.Create(ALookup,
      function(const AName: string): Boolean
      begin
        Result := SameText(AName, 'IVergeben');
      end, nil), APlan, AReason);
  finally
    mTree.Free;
  end;
end;

/// <summary>Plan in derselben Unit anwenden; das Ergebnis parst, und die Klasse hat jede Methode.</summary>
function Extract(const AText: string; ALine: Integer; const AMembers: TArray<Integer>;
  const ALookup: TClassAncestorsLookup; out APlan: TExtractInterfacePlan): string; overload;
var
  mReason, mMethod: string;
  mTree: TSyntaxTree;
  mLayout: TClassLayout;
begin
  Assert.IsTrue(TryPlan(AText, ALine, Wanted(AMembers, 'ICustomerRepository', True), ALookup, APlan, mReason), mReason);
  Result := TTextChanges.Apply(AText, APlan.Edits);
  Assert.IsTrue(Parses(Result), Result);
  mTree := TPascalParser.Parse(Result);
  try
    mLayout := TClassLayout.Read(mTree, Result, TClassLayout.DeclNamed(mTree, APlan.ClassName));
    try
      for mMethod in APlan.Methods do
      begin
        Assert.AreNotEqual(0, Integer(Length(mLayout.Find(mMethod))), mMethod + ' fehlt: ' + Result);
      end;
    finally
      mLayout.Free;
    end;
  finally
    mTree.Free;
  end;
end;

function Extract(const AText: string; ALine: Integer; const AMembers: TArray<Integer>): string; overload;
var
  mPlan: TExtractInterfacePlan;
begin
  Result := Extract(AText, ALine, AMembers, NoLookup(), mPlan);
end;

{ TExtractInterfaceTests }

procedure TExtractInterfaceTests.DefaultName;
begin
  Assert.AreEqual('ICustomerRepository', TExtractInterface.DefaultName('TCustomerRepository'));
  Assert.AreEqual('ITest', TExtractInterface.DefaultName('Test'));
  Assert.AreEqual('ITable', TExtractInterface.DefaultName('Table'));
end;

procedure TExtractInterfaceTests.Candidates;
var
  mData: TExtractInterfaceInfo;
  mItem: TExtractCandidate;
  mChecked, mDisabled: string;
begin
  mData := Info(cRepository, 3);
  Assert.AreEqual('ICustomerRepository', mData.SuggestedName);
  mChecked := '';
  mDisabled := '';
  for mItem in mData.Candidates do
  begin
    if mItem.Checked then
    begin
      mChecked := mChecked + mItem.Name + ' ';
    end;
    if not mItem.Enabled then
    begin
      mDisabled := mDisabled + mItem.Name + ' ';
    end;
  end;
  // Vorgabe: public-Methoden; Properties wählbar, aber nicht gewählt; private Mitglieder nicht in der Liste.
  Assert.AreEqual('Find Find Save ', mChecked);
  Assert.AreEqual('Create Destroy Default_ Convert ', mDisabled);
  for mItem in mData.Candidates do
  begin
    Assert.IsFalse(SameText(mItem.Name, 'GetItem'), 'private');
  end;
  Assert.AreEqual(0, Integer(Length(mData.Notes)), 'ohne Vorfahr kein Hinweis');
end;

procedure TExtractInterfaceTests.SameUnit;
var
  mData: TExtractInterfaceInfo;
  mText: string;
begin
  mData := Info(cRepository, 3);
  mText := Extract(cRepository, 3, DefaultIds(mData));
  Assert.IsTrue(mText.Contains(
    '  ICustomerRepository = interface'#10 +
    '    [''' + cGuid + ''']'#10 +
    '    /// Sucht einen Kunden.'#10 +
    '    function Find(const AId: Integer; ALimit: Integer = 10): string; overload;'#10 +
    '    function Find(const AName: string): string; overload;'#10 +
    '    procedure Save(var AData: TBytes); stdcall;'#10 +
    '  end;'#10 +
    #10 +
    '  TCustomerRepository = class(TInterfacedObject, ICustomerRepository)'#10), mText);
  Assert.IsFalse(mText.Contains('string; overload; virtual;'#10'    function Find(const AName: string): string; overload;'#10 +
    '    procedure Save(var AData: TBytes); stdcall;'#10'  end;'), 'virtual entfällt nur im Interface');
end;

procedure TExtractInterfaceTests.PropertyOnFieldGetsAccessors;
var
  mData: TExtractInterfaceInfo;
  mText: string;
begin
  mData := Info(cRepository, 3);
  mText := Extract(cRepository, 3, Ids(mData, ['Name', 'Count']));
  Assert.IsTrue(mText.Contains('    function GetName: string;'#10'    procedure SetName(const Value: string);'#10 +
    '    function GetCount: Integer;'#10'    property Name: string read GetName write SetName;'#10 +
    '    property Count: Integer read GetCount;'#10'  end;'), mText);
  // Die Klasse liest und schreibt das Feld über die neuen Methoden.
  Assert.IsTrue(mText.Contains('    property Name: string read GetName write SetName;'#10'    property Items'), mText);
  Assert.IsTrue(mText.Contains('    property Count: Integer read GetCount stored False;'), mText);
  Assert.IsTrue(mText.Contains('function TCustomerRepository.GetName: string;'#10'begin'#10'  Result := FName;'#10 +
    'end;'), mText);
  Assert.IsTrue(mText.Contains('procedure TCustomerRepository.SetName(const Value: string);'#10'begin'#10 +
    '  FName := Value;'#10'end;'), mText);
  Assert.IsFalse(mText.Contains('stored False;'#10'  end;'#10#10'  TCustomer'), 'stored nicht im Interface');
end;

procedure TExtractInterfaceTests.PropertyOnAccessorsTakesMethods;
var
  mData: TExtractInterfaceInfo;
  mText: string;
  mPlan: TExtractInterfacePlan;
begin
  mData := Info(cRepository, 3);
  mText := Extract(cRepository, 3, Ids(mData, ['Items']), NoLookup(), mPlan);
  Assert.IsTrue(mText.Contains(
    '    function GetItem(AIndex: Integer): string;'#10 +
    '    procedure SetItem(AIndex: Integer; const AValue: string);'#10 +
    '    property Items[AIndex: Integer]: string read GetItem write SetItem; default;'#10 +
    '  end;'), mText);
  Assert.AreEqual(2, Integer(Length(mPlan.Warnings)), 'private Zugriffsmethoden kommen mit');
end;

function Chain(const ANames: array of string): TClassAncestorsLookup;
var
  mPairs: TArray<string>;
  mIndex: Integer;
begin
  // Paare Klasse, Vorfahr.
  mPairs := nil;
  for mIndex := 0 to High(ANames) do
  begin
    mPairs := mPairs + [ANames[mIndex]];
  end;
  Result :=
    function(const AClassName: string; out AAncestors: TArray<string>): Boolean
    var
      Position: Integer;
    begin
      Position := 0;
      while Position < High(mPairs) do
      begin
        if SameText(mPairs[Position], AClassName) then
        begin
          AAncestors := [mPairs[Position + 1]];
          Exit(True);
        end;
        Inc(Position, 2);
      end;
      AAncestors := nil;
      Result := False;
    end;
end;

procedure TExtractInterfaceTests.AncestorTObject;
var
  mText: string;
begin
  mText := StringReplace(cRepository, '= class'#10, '= class(TObject)'#10, []);
  mText := Extract(mText, 3, Ids(Info(mText, 3), ['Save']));
  Assert.IsTrue(mText.Contains('TCustomerRepository = class(TInterfacedObject, ICustomerRepository)'), mText);
end;

procedure TExtractInterfaceTests.AncestorInterfaced;
var
  mText: string;
  mPlan: TExtractInterfacePlan;
begin
  mText := StringReplace(cRepository, '= class'#10, '= class(TInterfacedObject)'#10, []);
  mText := Extract(mText, 3, Ids(Info(mText, 3), ['Save']), NoLookup(), mPlan);
  Assert.IsTrue(mText.Contains('= class(TInterfacedObject, ICustomerRepository)'), mText);
  Assert.AreEqual(0, Integer(Length(mPlan.Warnings)));
  // TMyControl → TCustomControl → TWinControl → TControl → TComponent: implementiert IInterface.
  mText := StringReplace(cRepository, '= class'#10, '= class(TMyControl)'#10, []);
  mText := Extract(mText, 3, Ids(Info(mText, 3), ['Save']), Chain(['TMyControl', 'TCustomControl', 'TCustomControl',
    'TWinControl', 'TWinControl', 'TControl', 'TControl', 'TComponent']), mPlan);
  Assert.IsTrue(mText.Contains('= class(TMyControl, ICustomerRepository)'), mText);
  Assert.AreEqual(0, Integer(Length(mPlan.Warnings)));
  // Schon mit Interface: kein Hinweis.
  mText := StringReplace(cRepository, '= class'#10, '= class(TBase, IOther)'#10, []);
  mText := Extract(mText, 3, Ids(Info(mText, 3), ['Save']), NoLookup(), mPlan);
  Assert.IsTrue(mText.Contains('= class(TBase, IOther, ICustomerRepository)'), mText);
  Assert.AreEqual(0, Integer(Length(mPlan.Warnings)));
end;

procedure TExtractInterfaceTests.AncestorWithoutInterface;
var
  mText: string;
  mPlan: TExtractInterfacePlan;
  mData: TExtractInterfaceInfo;
begin
  mText := StringReplace(cRepository, '= class'#10, '= class(TPersistent)'#10, []);
  mText := Extract(mText, 3, Ids(Info(mText, 3), ['Save']), Chain(['TPersistent', 'TObject']), mPlan);
  Assert.IsTrue(mText.Contains('= class(TPersistent, ICustomerRepository)'), mText);
  Assert.AreEqual(1, Integer(Length(mPlan.Warnings)));
  Assert.IsTrue(mPlan.Warnings[0].Contains('_AddRef'), mPlan.Warnings[0]);
  // Unbekannter Vorfahr: Hinweis schon vorab.
  mText := StringReplace(cRepository, '= class'#10, '= class(TUnbekannt)'#10, []);
  mData := Info(mText, 3);
  Assert.AreEqual(1, Integer(Length(mData.Notes)));
  Assert.IsTrue(mData.Notes[0].Contains('nicht bekannt'), mData.Notes[0]);
end;

procedure TExtractInterfaceTests.RejectsBadInput;
var
  mPlan: TExtractInterfacePlan;
  mReason: string;
  mData: TExtractInterfaceInfo;
begin
  mData := Info(cRepository, 3);
  Assert.IsFalse(TryPlan(cRepository, 3, Wanted(DefaultIds(mData), '1Falsch', True), NoLookup(), mPlan, mReason));
  Assert.IsFalse(TryPlan(cRepository, 3, Wanted(DefaultIds(mData), 'IVergeben', True), NoLookup(), mPlan, mReason));
  Assert.IsTrue(mReason.Contains('vergeben'), mReason);
  Assert.IsFalse(TryPlan(cRepository, 3, Wanted(DefaultIds(mData), 'TCustomerRepository', True), NoLookup(), mPlan,
    mReason));
  Assert.IsFalse(TryPlan(cRepository, 3, Wanted(nil, 'IFoo', True), NoLookup(), mPlan, mReason));
  Assert.IsFalse(TryPlan(cRepository, 3, Wanted(Ids(mData, ['Convert']), 'IFoo', True), NoLookup(), mPlan, mReason));
  Assert.IsTrue(mReason.Contains('generisch'), mReason);
  Assert.IsFalse(TryPlan(cRepository, 4, Wanted(DefaultIds(mData), 'IFoo', True), NoLookup(), mPlan, mReason),
    'keine Kopfzeile');
end;

procedure TExtractInterfaceTests.OtherUnit;
const
  cTarget = 'unit Ziel;'#10'interface'#10'uses'#10'  System.SysUtils;'#10'implementation'#10'end.';
var
  mData: TExtractInterfaceInfo;
  mPlan: TExtractInterfacePlan;
  mReason, mText, mOrigin: string;
  mTree: TSyntaxTree;
  mEdit: TTextEdit;
begin
  mData := Info(cRepository, 3);
  Assert.IsTrue(TryPlan(cRepository, 3, Wanted(DefaultIds(mData), 'ICustomerRepository', False), NoLookup(), mPlan,
    mReason), mReason);
  mOrigin := TTextChanges.Apply(cRepository, mPlan.Edits);
  Assert.IsFalse(mOrigin.Contains('= interface'), 'nicht in der Unit der Klasse');
  Assert.IsTrue(mOrigin.Contains('class(TInterfacedObject, ICustomerRepository)'), mOrigin);
  Assert.IsTrue(mPlan.InInterface);
  Assert.AreEqual(3, Integer(Length(mPlan.TypeNames)), string.Join(',', mPlan.TypeNames));
  Assert.AreEqual('Integer', mPlan.TypeNames[0]);
  mTree := TPascalParser.Parse(cTarget);
  try
    Assert.IsTrue(TExtractInterface.InsertIntoUnit(mTree, cTarget, mPlan.Declaration, mEdit));
  finally
    mTree.Free;
  end;
  mText := TTextChanges.Apply(cTarget, [mEdit]);
  Assert.IsTrue(Parses(mText), mText);
  Assert.IsTrue(mText.Contains('type'#10'  ICustomerRepository = interface'#10), mText);
end;

procedure TExtractInterfaceTests.NewUnit;
var
  mData: TExtractInterfaceInfo;
  mPlan: TExtractInterfacePlan;
  mReason, mText: string;
begin
  mData := Info(cRepository, 3);
  Assert.IsTrue(TryPlan(cRepository, 3, Wanted(DefaultIds(mData), 'ICustomerRepository', False), NoLookup(), mPlan,
    mReason), mReason);
  mText := TExtractInterface.NewUnitText('CustomerRepositoryIntf', mPlan.Declaration, ['System.SysUtils'], #13#10);
  Assert.IsTrue(Parses(mText), mText);
  Assert.IsTrue(mText.StartsWith('unit CustomerRepositoryIntf;'#13#10#13#10'interface'#13#10#13#10'uses'#13#10 +
    '  System.SysUtils;'#13#10#13#10'type'#13#10'  ICustomerRepository = interface'#13#10), mText);
end;

initialization
  TDUnitX.RegisterTestFixture(TExtractInterfaceTests);

end.
