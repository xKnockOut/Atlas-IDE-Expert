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
  Guid = '{11111111-2222-3333-4444-555555555555}';
  Repository =
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
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
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
  Tree: TSyntaxTree;
  Reason: string;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Assert.IsTrue(TExtractInterface.Prepare(Tree, AText, ALine, NoLookup(), nil, Result, Reason), Reason);
  finally
    Tree.Free;
  end;
end;

function Ids(const AInfo: TExtractInterfaceInfo; const ANames: array of string): TArray<Integer>;
var
  Item: TExtractCandidate;
  Name: string;
begin
  Result := nil;
  for Name in ANames do
    for Item in AInfo.Candidates do
      if SameText(Item.Name, Name) and ((Item.Kind = TExtractCandidateKind.Method) or not ContainsText(Name, '(')) then
        Result := Result + [Item.Id];
end;

function DefaultIds(const AInfo: TExtractInterfaceInfo): TArray<Integer>;
var
  Item: TExtractCandidate;
begin
  Result := nil;
  for Item in AInfo.Candidates do
    if Item.Checked then
      Result := Result + [Item.Id];
end;

function TryPlan(const AText: string; ALine: Integer; const AMembers: TArray<Integer>; const AName: string;
  ASameUnit: Boolean; const ALookup: TClassAncestorsLookup; out APlan: TExtractInterfacePlan;
  out AReason: string): Boolean;
var
  Tree: TSyntaxTree;
  Request: TExtractInterfaceRequest;
begin
  Request := Default(TExtractInterfaceRequest);
  Request.Name := AName;
  Request.Members := AMembers;
  Request.Guid := Guid;
  Request.SameUnit := ASameUnit;
  Tree := TPascalParser.Parse(AText);
  try
    Result := TExtractInterface.Plan(Tree, AText, ALine, Request, ALookup,
      function(const AName: string): Boolean
      begin
        Result := SameText(AName, 'IVergeben');
      end, nil, APlan, AReason);
  finally
    Tree.Free;
  end;
end;

/// <summary>Plan in derselben Unit anwenden; das Ergebnis parst, und die Klasse hat jede Methode.</summary>
function Extract(const AText: string; ALine: Integer; const AMembers: TArray<Integer>;
  const ALookup: TClassAncestorsLookup; out APlan: TExtractInterfacePlan): string; overload;
var
  Reason, Method: string;
  Tree: TSyntaxTree;
  Layout: TClassLayout;
begin
  Assert.IsTrue(TryPlan(AText, ALine, AMembers, 'ICustomerRepository', True, ALookup, APlan, Reason), Reason);
  Result := TTextChanges.Apply(AText, APlan.Edits);
  Assert.IsTrue(Parses(Result), Result);
  Tree := TPascalParser.Parse(Result);
  try
    Layout := TClassLayout.Read(Tree, Result, TClassLayout.DeclNamed(Tree, APlan.ClassName));
    try
      for Method in APlan.Methods do
        Assert.IsTrue(Layout.Find(Method) <> nil, Method + ' fehlt: ' + Result);
    finally
      Layout.Free;
    end;
  finally
    Tree.Free;
  end;
end;

function Extract(const AText: string; ALine: Integer; const AMembers: TArray<Integer>): string; overload;
var
  Plan: TExtractInterfacePlan;
begin
  Result := Extract(AText, ALine, AMembers, NoLookup(), Plan);
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
  Data: TExtractInterfaceInfo;
  Item: TExtractCandidate;
  Checked, Disabled: string;
begin
  Data := Info(Repository, 3);
  Assert.AreEqual('ICustomerRepository', Data.SuggestedName);
  Checked := '';
  Disabled := '';
  for Item in Data.Candidates do
  begin
    if Item.Checked then
      Checked := Checked + Item.Name + ' ';
    if not Item.Enabled then
      Disabled := Disabled + Item.Name + ' ';
  end;
  // Vorgabe: public-Methoden; Properties wählbar, aber nicht gewählt; private Mitglieder nicht in der Liste.
  Assert.AreEqual('Find Find Save ', Checked);
  Assert.AreEqual('Create Destroy Default_ Convert ', Disabled);
  for Item in Data.Candidates do
    Assert.IsFalse(SameText(Item.Name, 'GetItem'), 'private');
  Assert.AreEqual(0, Integer(Length(Data.Notes)), 'ohne Vorfahr kein Hinweis');
end;

procedure TExtractInterfaceTests.SameUnit;
var
  Data: TExtractInterfaceInfo;
  Text: string;
begin
  Data := Info(Repository, 3);
  Text := Extract(Repository, 3, DefaultIds(Data));
  Assert.IsTrue(Text.Contains(
    '  ICustomerRepository = interface'#10 +
    '    [''' + Guid + ''']'#10 +
    '    /// Sucht einen Kunden.'#10 +
    '    function Find(const AId: Integer; ALimit: Integer = 10): string; overload;'#10 +
    '    function Find(const AName: string): string; overload;'#10 +
    '    procedure Save(var AData: TBytes); stdcall;'#10 +
    '  end;'#10 +
    #10 +
    '  TCustomerRepository = class(TInterfacedObject, ICustomerRepository)'#10), Text);
  Assert.IsFalse(Text.Contains('string; overload; virtual;'#10'    function Find(const AName: string): string; overload;'#10 +
    '    procedure Save(var AData: TBytes); stdcall;'#10'  end;'), 'virtual entfällt nur im Interface');
end;

procedure TExtractInterfaceTests.PropertyOnFieldGetsAccessors;
var
  Data: TExtractInterfaceInfo;
  Text: string;
begin
  Data := Info(Repository, 3);
  Text := Extract(Repository, 3, Ids(Data, ['Name', 'Count']));
  Assert.IsTrue(Text.Contains('    function GetName: string;'#10'    procedure SetName(const Value: string);'#10 +
    '    function GetCount: Integer;'#10'    property Name: string read GetName write SetName;'#10 +
    '    property Count: Integer read GetCount;'#10'  end;'), Text);
  // Die Klasse liest und schreibt das Feld über die neuen Methoden.
  Assert.IsTrue(Text.Contains('    property Name: string read GetName write SetName;'#10'    property Items'), Text);
  Assert.IsTrue(Text.Contains('    property Count: Integer read GetCount stored False;'), Text);
  Assert.IsTrue(Text.Contains('function TCustomerRepository.GetName: string;'#10'begin'#10'  Result := FName;'#10 +
    'end;'), Text);
  Assert.IsTrue(Text.Contains('procedure TCustomerRepository.SetName(const Value: string);'#10'begin'#10 +
    '  FName := Value;'#10'end;'), Text);
  Assert.IsFalse(Text.Contains('stored False;'#10'  end;'#10#10'  TCustomer'), 'stored nicht im Interface');
end;

procedure TExtractInterfaceTests.PropertyOnAccessorsTakesMethods;
var
  Data: TExtractInterfaceInfo;
  Text: string;
  Plan: TExtractInterfacePlan;
begin
  Data := Info(Repository, 3);
  Text := Extract(Repository, 3, Ids(Data, ['Items']), NoLookup(), Plan);
  Assert.IsTrue(Text.Contains(
    '    function GetItem(AIndex: Integer): string;'#10 +
    '    procedure SetItem(AIndex: Integer; const AValue: string);'#10 +
    '    property Items[AIndex: Integer]: string read GetItem write SetItem; default;'#10 +
    '  end;'), Text);
  Assert.AreEqual(2, Integer(Length(Plan.Warnings)), 'private Zugriffsmethoden kommen mit');
end;

function Chain(const ANames: array of string): TClassAncestorsLookup;
var
  Pairs: TArray<string>;
  Index: Integer;
begin
  // Paare Klasse, Vorfahr.
  Pairs := nil;
  for Index := 0 to High(ANames) do
    Pairs := Pairs + [ANames[Index]];
  Result :=
    function(const AClassName: string; out AAncestors: TArray<string>): Boolean
    var
      Position: Integer;
    begin
      Position := 0;
      while Position < High(Pairs) do
      begin
        if SameText(Pairs[Position], AClassName) then
        begin
          AAncestors := [Pairs[Position + 1]];
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
  Text: string;
begin
  Text := StringReplace(Repository, '= class'#10, '= class(TObject)'#10, []);
  Text := Extract(Text, 3, Ids(Info(Text, 3), ['Save']));
  Assert.IsTrue(Text.Contains('TCustomerRepository = class(TInterfacedObject, ICustomerRepository)'), Text);
end;

procedure TExtractInterfaceTests.AncestorInterfaced;
var
  Text: string;
  Plan: TExtractInterfacePlan;
begin
  Text := StringReplace(Repository, '= class'#10, '= class(TInterfacedObject)'#10, []);
  Text := Extract(Text, 3, Ids(Info(Text, 3), ['Save']), NoLookup(), Plan);
  Assert.IsTrue(Text.Contains('= class(TInterfacedObject, ICustomerRepository)'), Text);
  Assert.AreEqual(0, Integer(Length(Plan.Warnings)));
  // TMyControl → TCustomControl → TWinControl → TControl → TComponent: implementiert IInterface.
  Text := StringReplace(Repository, '= class'#10, '= class(TMyControl)'#10, []);
  Text := Extract(Text, 3, Ids(Info(Text, 3), ['Save']), Chain(['TMyControl', 'TCustomControl', 'TCustomControl',
    'TWinControl', 'TWinControl', 'TControl', 'TControl', 'TComponent']), Plan);
  Assert.IsTrue(Text.Contains('= class(TMyControl, ICustomerRepository)'), Text);
  Assert.AreEqual(0, Integer(Length(Plan.Warnings)));
  // Schon mit Interface: kein Hinweis.
  Text := StringReplace(Repository, '= class'#10, '= class(TBase, IOther)'#10, []);
  Text := Extract(Text, 3, Ids(Info(Text, 3), ['Save']), NoLookup(), Plan);
  Assert.IsTrue(Text.Contains('= class(TBase, IOther, ICustomerRepository)'), Text);
  Assert.AreEqual(0, Integer(Length(Plan.Warnings)));
end;

procedure TExtractInterfaceTests.AncestorWithoutInterface;
var
  Text: string;
  Plan: TExtractInterfacePlan;
  Data: TExtractInterfaceInfo;
begin
  Text := StringReplace(Repository, '= class'#10, '= class(TPersistent)'#10, []);
  Text := Extract(Text, 3, Ids(Info(Text, 3), ['Save']), Chain(['TPersistent', 'TObject']), Plan);
  Assert.IsTrue(Text.Contains('= class(TPersistent, ICustomerRepository)'), Text);
  Assert.AreEqual(1, Integer(Length(Plan.Warnings)));
  Assert.IsTrue(Plan.Warnings[0].Contains('_AddRef'), Plan.Warnings[0]);
  // Unbekannter Vorfahr: Hinweis schon vorab.
  Text := StringReplace(Repository, '= class'#10, '= class(TUnbekannt)'#10, []);
  Data := Info(Text, 3);
  Assert.AreEqual(1, Integer(Length(Data.Notes)));
  Assert.IsTrue(Data.Notes[0].Contains('nicht bekannt'), Data.Notes[0]);
end;

procedure TExtractInterfaceTests.RejectsBadInput;
var
  Plan: TExtractInterfacePlan;
  Reason: string;
  Data: TExtractInterfaceInfo;
begin
  Data := Info(Repository, 3);
  Assert.IsFalse(TryPlan(Repository, 3, DefaultIds(Data), '1Falsch', True, NoLookup(), Plan, Reason));
  Assert.IsFalse(TryPlan(Repository, 3, DefaultIds(Data), 'IVergeben', True, NoLookup(), Plan, Reason));
  Assert.IsTrue(Reason.Contains('vergeben'), Reason);
  Assert.IsFalse(TryPlan(Repository, 3, DefaultIds(Data), 'TCustomerRepository', True, NoLookup(), Plan, Reason));
  Assert.IsFalse(TryPlan(Repository, 3, nil, 'IFoo', True, NoLookup(), Plan, Reason));
  Assert.IsFalse(TryPlan(Repository, 3, Ids(Data, ['Convert']), 'IFoo', True, NoLookup(), Plan, Reason));
  Assert.IsTrue(Reason.Contains('generisch'), Reason);
  Assert.IsFalse(TryPlan(Repository, 4, DefaultIds(Data), 'IFoo', True, NoLookup(), Plan, Reason), 'keine Kopfzeile');
end;

procedure TExtractInterfaceTests.OtherUnit;
const
  Target = 'unit Ziel;'#10'interface'#10'uses'#10'  System.SysUtils;'#10'implementation'#10'end.';
var
  Data: TExtractInterfaceInfo;
  Plan: TExtractInterfacePlan;
  Reason, Text, Origin: string;
  Tree: TSyntaxTree;
  Edit: TTextEdit;
begin
  Data := Info(Repository, 3);
  Assert.IsTrue(TryPlan(Repository, 3, DefaultIds(Data), 'ICustomerRepository', False, NoLookup(), Plan, Reason),
    Reason);
  Origin := TTextChanges.Apply(Repository, Plan.Edits);
  Assert.IsFalse(Origin.Contains('= interface'), 'nicht in der Unit der Klasse');
  Assert.IsTrue(Origin.Contains('class(TInterfacedObject, ICustomerRepository)'), Origin);
  Assert.IsTrue(Plan.InInterface);
  Assert.AreEqual(3, Integer(Length(Plan.TypeNames)), string.Join(',', Plan.TypeNames));
  Assert.AreEqual('Integer', Plan.TypeNames[0]);
  Tree := TPascalParser.Parse(Target);
  try
    Assert.IsTrue(TExtractInterface.InsertIntoUnit(Tree, Target, Plan.Declaration, Edit));
  finally
    Tree.Free;
  end;
  Text := TTextChanges.Apply(Target, [Edit]);
  Assert.IsTrue(Parses(Text), Text);
  Assert.IsTrue(Text.Contains('type'#10'  ICustomerRepository = interface'#10), Text);
end;

procedure TExtractInterfaceTests.NewUnit;
var
  Data: TExtractInterfaceInfo;
  Plan: TExtractInterfacePlan;
  Reason, Text: string;
begin
  Data := Info(Repository, 3);
  Assert.IsTrue(TryPlan(Repository, 3, DefaultIds(Data), 'ICustomerRepository', False, NoLookup(), Plan, Reason),
    Reason);
  Text := TExtractInterface.NewUnitText('CustomerRepositoryIntf', Plan.Declaration, ['System.SysUtils'], #13#10);
  Assert.IsTrue(Parses(Text), Text);
  Assert.IsTrue(Text.StartsWith('unit CustomerRepositoryIntf;'#13#10#13#10'interface'#13#10#13#10'uses'#13#10 +
    '  System.SysUtils;'#13#10#13#10'type'#13#10'  ICustomerRepository = interface'#13#10), Text);
end;

initialization
  TDUnitX.RegisterTestFixture(TExtractInterfaceTests);

end.
