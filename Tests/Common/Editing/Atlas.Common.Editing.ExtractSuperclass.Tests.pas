unit Atlas.Common.Editing.ExtractSuperclass.Tests;

// Tests für „Basisklasse herauslösen“ (#713): Namensvorschlag, Kandidaten mit
// Abhängigkeiten, verschieben und abstrakt deklarieren, fehlende
// Abhängigkeiten, Heben der Sichtbarkeit (dieselbe und eine andere Unit),
// Aufteilen von Konstruktor und Destruktor, Interfaces bleiben unten,
// Vorwärtsdeklaration, generische Klasse. Jedes Ergebnis parst.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TExtractSuperclassTests = class
  public
    [Test]
    procedure SuggestsName;
    [Test]
    procedure Candidates;
    [Test]
    procedure MovesFieldAndMethod;
    [Test]
    procedure AbstractMethodStaysBelow;
    [Test]
    procedure RejectsMissingDependency;
    [Test]
    procedure RaisesStrictPrivate;
    [Test]
    procedure RaisesPrivateForOtherUnit;
    [Test]
    procedure SplitsConstructorAndDestructor;
    [Test]
    procedure KeepsInterfacesBelow;
    [Test]
    procedure AddsForwardDeclaration;
    [Test]
    procedure GenericClass;
    [Test]
    procedure RelocatesRaisedAbstractOverride;
    [Test]
    procedure RejectsBadInput;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ClassLayout,
  Atlas.Common.Editing.ExtractSuperclass;

const
  Export_ =
    'unit U;'#10 +                                                  // 0
    'interface'#10 +                                                // 1
    'uses Classes;'#10 +                                            // 2
    'type'#10 +                                                     // 3
    '  TPdfExport = class(TComponent)'#10 +                         // 4
    '  private'#10 +                                                // 5
    '    FTitle: string;'#10 +                                      // 6
    '    FPages: TStringList;'#10 +                                 // 7
    '    FCompressed: Boolean;'#10 +                                // 8
    '    function GetTitle: string;'#10 +                           // 9
    '  public'#10 +                                                 // 10
    '    constructor Create(AOwner: TComponent); override;'#10 +    // 11
    '    destructor Destroy; override;'#10 +                        // 12
    '    procedure Run;'#10 +                                       // 13
    '    procedure WritePage(const AText: string);'#10 +            // 14
    '    property Title: string read GetTitle write FTitle;'#10 +   // 15
    '  end;'#10 +                                                   // 16
    'implementation'#10 +                                           // 17
    #10 +
    'constructor TPdfExport.Create(AOwner: TComponent);'#10 +
    'begin'#10 +
    '  inherited Create(AOwner);'#10 +
    '  FPages := TStringList.Create;'#10 +
    '  FCompressed := True;'#10 +
    'end;'#10 +
    #10 +
    'destructor TPdfExport.Destroy;'#10 +
    'begin'#10 +
    '  FPages.Free;'#10 +
    '  inherited;'#10 +
    'end;'#10 +
    #10 +
    'function TPdfExport.GetTitle: string;'#10 +
    'begin'#10 +
    '  Result := FTitle;'#10 +
    'end;'#10 +
    #10 +
    'procedure TPdfExport.Run;'#10 +
    'begin'#10 +
    '  WritePage(FTitle);'#10 +
    'end;'#10 +
    #10 +
    'procedure TPdfExport.WritePage(const AText: string);'#10 +
    'begin'#10 +
    '  FPages.Add(AText);'#10 +
    'end;'#10 +
    #10 +
    'end.'#10;

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

/// <summary>Index des Mitglieds AName in der Klasse auf Zeile ALine.</summary>
function IdOf(const AText: string; ALine: Integer; const AName: string): Integer;
var
  Tree: TSyntaxTree;
  Layout: TClassLayout;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Layout := TClassLayout.Read(Tree, AText, TExtractSuperclass.ClassAt(Tree, ALine));
    try
      Result := Layout.Find(AName)[0];
    finally
      Layout.Free;
    end;
  finally
    Tree.Free;
  end;
end;

function Request(const AText: string; ALine: Integer; const AName: string; const AMembers,
  AAbstract: array of string; ASameUnit: Boolean): TSuperclassRequest;
var
  Name: string;
begin
  Result := Default(TSuperclassRequest);
  Result.Name := AName;
  for Name in AMembers do
    Result.Members := Result.Members + [IdOf(AText, ALine, Name)];
  for Name in AAbstract do
    Result.Abstract := Result.Abstract + [IdOf(AText, ALine, Name)];
  Result.SameUnit := ASameUnit;
  Result.RaiseVisibility := TClassVisibility.Protected_;
end;

function Run(const AText: string; ALine: Integer; const ARequest: TSuperclassRequest; out APlan: TSuperclassPlan;
  out AReason: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TExtractSuperclass.Plan(Tree, AText, ALine, ARequest, nil, nil, APlan, AReason);
  finally
    Tree.Free;
  end;
end;

/// <summary>Text zwischen AFrom und ATo (ohne beide); '' ohne.</summary>
function Between(const AText, AFrom, ATo: string): string;
var
  Start, Stop: Integer;
begin
  Start := Pos(AFrom, AText);
  if Start = 0 then
    Exit('');
  Start := Start + Length(AFrom);
  Stop := PosEx(ATo, AText, Start);
  if Stop = 0 then
    Exit('');
  Result := Copy(AText, Start, Stop - Start);
end;

procedure TExtractSuperclassTests.SuggestsName;
begin
  Assert.AreEqual('TExportBase', TExtractSuperclass.SuggestName('TPdfExport', 'Base'));
  Assert.AreEqual('TCustomerBase', TExtractSuperclass.SuggestName('TCustomer', 'Base'));
  Assert.AreEqual('TCustomExport', TExtractSuperclass.SuggestName('TPdfExport', 'Custom'));
  Assert.AreEqual('TViewBase', TExtractSuperclass.SuggestName('THTMLView', 'Base'));
end;

procedure TExtractSuperclassTests.Candidates;
var
  Tree: TSyntaxTree;
  Info: TSuperclassInfo;
  Reason: string;
  Item: TSuperclassCandidate;
  Names: string;
begin
  Tree := TPascalParser.Parse(Export_);
  try
    Assert.IsTrue(TExtractSuperclass.Prepare(Tree, Export_, 4, 'Base',
      function(const AName: string): Boolean
      begin
        Result := SameText(AName, 'TExportBase');
      end, Info, Reason), Reason);
  finally
    Tree.Free;
  end;
  Assert.AreEqual('TPdfExport', Info.ClassName);
  // Vorschlag vergeben: der ganze Name.
  Assert.AreEqual('TPdfExportBase', Info.SuggestedName);
  Assert.AreEqual('TComponent', Info.Ancestor);
  Names := '';
  for Item in Info.Candidates do
    Names := Names + Item.Name + ' ';
  Assert.AreEqual('FTitle FPages FCompressed GetTitle Run WritePage Title ', Names);
  Assert.IsTrue(Info.Candidates[3].CanAbstract);
  // Run braucht WritePage und FTitle.
  Assert.AreEqual(2, Integer(Length(Info.Candidates[4].Needs)));
  Assert.AreEqual(1, Integer(Length(Info.Notes)));
end;

procedure TExtractSuperclassTests.MovesFieldAndMethod;
var
  Plan: TSuperclassPlan;
  Reason, Base: string;
begin
  Assert.IsTrue(Run(Export_, 4, Request(Export_, 4, 'TExportBase', ['FPages', 'WritePage'], [], True), Plan,
    Reason), Reason);
  Assert.IsTrue(Parses(Plan.Text), Plan.Text);
  Base := Between(Plan.Text, 'TExportBase = class(TComponent)', 'end;');
  Assert.IsTrue(ContainsStr(Base, '    FPages: TStringList;'), Base);
  Assert.IsTrue(ContainsStr(Base, '    procedure WritePage(const AText: string);'), Base);
  // In derselben Unit sieht die Klasse private Felder der Basisklasse.
  Assert.IsTrue(ContainsStr(Base, '  private'#10), Base);
  Assert.IsTrue(ContainsStr(Plan.Text, 'TPdfExport = class(TExportBase)'), Plan.Text);
  Assert.IsTrue(ContainsStr(Plan.Text, 'procedure TExportBase.WritePage(const AText: string);'), Plan.Text);
  Assert.IsFalse(ContainsStr(Plan.Text, 'procedure TPdfExport.WritePage'), Plan.Text);
  Assert.IsFalse(ContainsStr(Between(Plan.Text, 'TPdfExport = class', 'end;'), 'FPages'), Plan.Text);
  // Die Basisklasse steht direkt über der Klasse, ihre Rümpfe vor denen der Klasse.
  Assert.IsTrue(Pos('TExportBase = class', Plan.Text) < Pos('TPdfExport = class', Plan.Text));
  Assert.IsTrue(Pos('TExportBase.WritePage', Plan.Text) < Pos('TPdfExport.Create', Plan.Text));
  Assert.AreEqual(4, Plan.BaseLine);
  Assert.AreEqual(2, Integer(Length(Plan.Moved)));
end;

procedure TExtractSuperclassTests.AbstractMethodStaysBelow;
var
  Plan: TSuperclassPlan;
  Reason: string;
begin
  Assert.IsTrue(Run(Export_, 4, Request(Export_, 4, 'TExportBase', ['FTitle', 'Run', 'WritePage'], ['WritePage'],
    True), Plan, Reason), Reason);
  Assert.IsTrue(Parses(Plan.Text), Plan.Text);
  Assert.IsTrue(ContainsStr(Plan.Text, '    procedure WritePage(const AText: string); virtual; abstract;'),
    Plan.Text);
  Assert.IsTrue(ContainsStr(Plan.Text, '    procedure WritePage(const AText: string); override;'), Plan.Text);
  Assert.IsTrue(ContainsStr(Plan.Text, 'procedure TPdfExport.WritePage(const AText: string);'), Plan.Text);
  Assert.IsTrue(ContainsStr(Plan.Text, 'procedure TExportBase.Run;'), Plan.Text);
  Assert.AreEqual(1, Integer(Length(Plan.Abstracts)));
end;

procedure TExtractSuperclassTests.RejectsMissingDependency;
var
  Plan: TSuperclassPlan;
  Reason: string;
begin
  Assert.IsFalse(Run(Export_, 4, Request(Export_, 4, 'TExportBase', ['Run'], [], True), Plan, Reason));
  Assert.IsTrue(ContainsStr(Reason, 'Run braucht FTitle'), Reason);
  Assert.IsTrue(ContainsStr(Reason, 'Run braucht WritePage'), Reason);
  // Eine Property braucht ihre Zugriffe.
  Assert.IsFalse(Run(Export_, 4, Request(Export_, 4, 'TExportBase', ['Title', 'FTitle'], [], True), Plan, Reason));
  Assert.IsTrue(ContainsStr(Reason, 'Title braucht GetTitle'), Reason);
  // Abstrakt deklariert genügt.
  Assert.IsTrue(Run(Export_, 4, Request(Export_, 4, 'TExportBase', ['Title', 'FTitle', 'GetTitle'], ['GetTitle'],
    True), Plan, Reason), Reason);
end;

procedure TExtractSuperclassTests.RaisesStrictPrivate;
const
  Source =
    'unit U;'#10'interface'#10'type'#10 +
    '  TFoo = class'#10 +                 // 3
    '  strict private'#10 +
    '    FCount: Integer;'#10 +
    '    FName: string;'#10 +
    '  public'#10 +
    '    procedure Inc_;'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'procedure TFoo.Inc_;'#10'begin'#10'  FCount := FCount + 1;'#10'end;'#10#10'end.'#10;
var
  Plan: TSuperclassPlan;
  Reason, Base: string;
  Req: TSuperclassRequest;
begin
  Assert.IsTrue(Run(Source, 3, Request(Source, 3, 'TFooBase', ['FCount', 'FName'], [], True), Plan, Reason), Reason);
  Assert.IsTrue(Parses(Plan.Text), Plan.Text);
  Base := Between(Plan.Text, 'TFooBase = class', 'end;');
  Assert.IsTrue(ContainsStr(Base, '  strict private'#10'    FName: string;'), Base);
  Assert.IsTrue(ContainsStr(Base, '  protected'#10'    FCount: Integer;'), Base);
  Assert.AreEqual('FCount', string.Join(',', Plan.Raised));
  Assert.AreEqual(1, Integer(Length(Plan.Warnings)));
  Req := Request(Source, 3, 'TFooBase', ['FCount'], [], True);
  Req.RaiseVisibility := TClassVisibility.StrictProtected;
  Assert.IsTrue(Run(Source, 3, Req, Plan, Reason), Reason);
  Assert.IsTrue(ContainsStr(Plan.Text, '  strict protected'#10'    FCount: Integer;'), Plan.Text);
end;

procedure TExtractSuperclassTests.RaisesPrivateForOtherUnit;
var
  Plan: TSuperclassPlan;
  Reason, Base: string;
begin
  Assert.IsTrue(Run(Export_, 4, Request(Export_, 4, 'TExportBase', ['FPages', 'WritePage'], [], False), Plan,
    Reason), Reason);
  Base := Between(Plan.Text, 'TExportBase = class(TComponent)', 'end;');
  // FPages benutzt der bleibende Rumpf nicht mehr (Konstruktor und Destruktor aufgeteilt).
  Assert.IsTrue(ContainsStr(Base, '  private'#10'    FPages: TStringList;'), Base);
  Assert.AreEqual(0, Integer(Length(Plan.Raised)));
  Assert.IsTrue(Run(Export_, 4, Request(Export_, 4, 'TExportBase', ['FTitle'], [], False), Plan, Reason), Reason);
  Assert.IsTrue(ContainsStr(Plan.Text, '  protected'#10'    FTitle: string;'), Plan.Text);
end;

procedure TExtractSuperclassTests.SplitsConstructorAndDestructor;
var
  Plan: TSuperclassPlan;
  Reason, Text: string;
begin
  Assert.IsTrue(Run(Export_, 4, Request(Export_, 4, 'TExportBase', ['FPages', 'FCompressed'], [], True), Plan,
    Reason), Reason);
  Text := Plan.Text;
  Assert.IsTrue(Parses(Text), Text);
  Assert.IsTrue(ContainsStr(Text, '    constructor Create(AOwner: TComponent); override;'#10 +
    '    destructor Destroy; override;'#10'  end;'), Text);
  Assert.IsTrue(ContainsStr(Text, 'constructor TExportBase.Create(AOwner: TComponent);'#10'begin'#10 +
    '  inherited Create(AOwner);'#10'  FPages := TStringList.Create;'#10'  FCompressed := True;'#10'end;'), Text);
  Assert.IsTrue(ContainsStr(Text, 'destructor TExportBase.Destroy;'#10'begin'#10'  FPages.Free;'#10 +
    '  inherited;'#10'end;'), Text);
  Assert.IsTrue(ContainsStr(Text, 'constructor TPdfExport.Create(AOwner: TComponent);'#10'begin'#10 +
    '  inherited;'#10'end;'), Text);
  Assert.IsTrue(ContainsStr(Text, 'destructor TPdfExport.Destroy;'#10'begin'#10'  inherited;'#10'end;'), Text);
  Assert.AreEqual('Create,Destroy', string.Join(',', Plan.Split));
end;

procedure TExtractSuperclassTests.KeepsInterfacesBelow;
const
  Source =
    'unit U;'#10'interface'#10'type'#10 +
    '  TFoo = class(TInterfacedObject, IFoo, IBar)'#10 +   // 3
    '  public'#10 +
    '    procedure Run;'#10 +
    '  end;'#10 +
    '  TBaz = class(IFoo)'#10 +                            // 7
    '  public'#10 +
    '    procedure Run;'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'procedure TFoo.Run;'#10'begin'#10'end;'#10#10 +
    'procedure TBaz.Run;'#10'begin'#10'end;'#10#10'end.'#10;
var
  Plan: TSuperclassPlan;
  Reason: string;
begin
  Assert.IsTrue(Run(Source, 3, Request(Source, 3, 'TFooBase', ['Run'], [], True), Plan, Reason), Reason);
  Assert.IsTrue(ContainsStr(Plan.Text, 'TFooBase = class(TInterfacedObject)'), Plan.Text);
  Assert.IsTrue(ContainsStr(Plan.Text, 'TFoo = class(TFooBase, IFoo, IBar)'), Plan.Text);
  Assert.IsTrue(Run(Source, 7, Request(Source, 7, 'TBazBase', ['Run'], [], True), Plan, Reason), Reason);
  Assert.IsTrue(ContainsStr(Plan.Text, 'TBazBase = class'#10), Plan.Text);
  Assert.IsTrue(ContainsStr(Plan.Text, 'TBaz = class(TBazBase, IFoo)'), Plan.Text);
end;

procedure TExtractSuperclassTests.AddsForwardDeclaration;
const
  Source =
    'unit U;'#10'interface'#10'type'#10 +
    '  TNode = class'#10 +            // 3
    '  public'#10 +
    '    function Clone: TNode;'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'function TNode.Clone: TNode;'#10'begin'#10'  Result := nil;'#10'end;'#10#10'end.'#10;
var
  Plan: TSuperclassPlan;
  Reason: string;
begin
  Assert.IsTrue(Run(Source, 3, Request(Source, 3, 'TNodeBase', ['Clone'], [], True), Plan, Reason), Reason);
  Assert.IsTrue(Parses(Plan.Text), Plan.Text);
  Assert.IsTrue(ContainsStr(Plan.Text, 'type'#10'  TNode = class;'#10#10'  TNodeBase = class'#10), Plan.Text);
  Assert.AreEqual(5, Plan.BaseLine);
end;

procedure TExtractSuperclassTests.GenericClass;
const
  Source =
    'unit U;'#10'interface'#10'type'#10 +
    '  TBox<T: class> = class'#10 +    // 3
    '  private'#10 +
    '    FItem: T;'#10 +
    '  public'#10 +
    '    function Get: T;'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'function TBox<T>.Get: T;'#10'begin'#10'  Result := FItem;'#10'end;'#10#10'end.'#10;
var
  Plan: TSuperclassPlan;
  Reason: string;
begin
  Assert.IsTrue(Run(Source, 3, Request(Source, 3, 'TBoxBase', ['FItem', 'Get'], [], True), Plan, Reason), Reason);
  Assert.IsTrue(Parses(Plan.Text), Plan.Text);
  Assert.IsTrue(ContainsStr(Plan.Text, 'TBoxBase<T: class> = class'#10), Plan.Text);
  Assert.IsTrue(ContainsStr(Plan.Text, 'TBox<T: class> = class(TBoxBase<T>)'), Plan.Text);
  Assert.IsTrue(ContainsStr(Plan.Text, 'function TBoxBase<T>.Get: T;'), Plan.Text);
end;

procedure TExtractSuperclassTests.RelocatesRaisedAbstractOverride;
const
  Source =
    'unit U;'#10'interface'#10'type'#10 +
    '  TJob = class'#10 +             // 3
    '  private'#10 +
    '    procedure Step; virtual;'#10 +
    '  public'#10 +
    '    procedure Run;'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'procedure TJob.Step;'#10'begin'#10'end;'#10#10 +
    'procedure TJob.Run;'#10'begin'#10'  Step;'#10'end;'#10#10'end.'#10;
var
  Plan: TSuperclassPlan;
  Reason, Job: string;
begin
  Assert.IsTrue(Run(Source, 3, Request(Source, 3, 'TJobBase', ['Step', 'Run'], ['Step'], False), Plan, Reason),
    Reason);
  Assert.IsTrue(Parses(Plan.Text), Plan.Text);
  Assert.IsTrue(ContainsStr(Plan.Text, '  protected'#10'    procedure Step; virtual; abstract;'), Plan.Text);
  Job := Between(Plan.Text, 'TJob = class(TJobBase)', 'end;');
  // Gleiche Sichtbarkeit unten (sonst H2269).
  Assert.IsTrue(ContainsStr(Job, '  protected'#10'    procedure Step; override;'), Job);
  // Der leere private-Abschnitt fällt weg.
  Assert.IsFalse(ContainsStr(Job, 'private'), Job);
end;

procedure TExtractSuperclassTests.RejectsBadInput;
var
  Plan: TSuperclassPlan;
  Reason: string;
  Req: TSuperclassRequest;
begin
  Assert.IsFalse(Run(Export_, 4, Request(Export_, 4, '1Base', ['FTitle'], [], True), Plan, Reason));
  Assert.IsFalse(Run(Export_, 4, Request(Export_, 4, 'TPdfExport', ['FTitle'], [], True), Plan, Reason));
  Assert.IsFalse(Run(Export_, 4, Request(Export_, 4, 'TExportBase', [], [], True), Plan, Reason));
  Assert.IsFalse(Run(Export_, 4, Request(Export_, 4, 'TExportBase', ['FTitle'], ['FTitle'], True), Plan, Reason));
  Assert.IsTrue(ContainsStr(Reason, 'abstrakt'), Reason);
  Req := Request(Export_, 4, 'TExportBase', ['FTitle'], [], True);
  Req.Members := Req.Members + [IdOf(Export_, 4, 'Create')];
  Assert.IsFalse(Run(Export_, 4, Req, Plan, Reason));
  // Nicht auf der Kopfzeile.
  Assert.IsFalse(Run(Export_, 6, Request(Export_, 4, 'TExportBase', ['FTitle'], [], True), Plan, Reason));
end;

initialization
  TDUnitX.RegisterTestFixture(TExtractSuperclassTests);

end.
