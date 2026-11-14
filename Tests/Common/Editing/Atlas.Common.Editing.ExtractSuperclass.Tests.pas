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
  Atlas.Common.Editing.MemberTransfer,
  Atlas.Common.Editing.ExtractSuperclass;

const
  cExport_ =
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
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := Length(mTree.Diagnostics) = 0;
  finally
    mTree.Free;
  end;
end;

/// <summary>Index des Mitglieds AName in der Klasse auf Zeile ALine.</summary>
function IdOf(const AText: string; ALine: Integer; const AName: string): Integer;
var
  mTree: TSyntaxTree;
  mLayout: TClassLayout;
begin
  mTree := TPascalParser.Parse(AText);
  try
    mLayout := TClassLayout.Read(mTree, AText, TExtractSuperclass.ClassAt(mTree, ALine));
    try
      Result := mLayout.Find(AName)[0];
    finally
      mLayout.Free;
    end;
  finally
    mTree.Free;
  end;
end;

function Request(const AText: string; ALine: Integer; const AName: string; const AMembers,
  AAbstract: array of string; ASameUnit: Boolean): TSuperclassRequest;
var
  mName: string;
begin
  Result := Default(TSuperclassRequest);
  Result.Name := AName;
  for mName in AMembers do
  begin
    Result.Members := Result.Members + [IdOf(AText, ALine, mName)];
  end;
  for mName in AAbstract do
  begin
    Result.Abstract := Result.Abstract + [IdOf(AText, ALine, mName)];
  end;
  Result.SameUnit := ASameUnit;
  Result.RaiseVisibility := TClassVisibility.Protected_;
end;

function Run(const AText: string; ALine: Integer; const ARequest: TSuperclassRequest; out APlan: TSuperclassPlan;
  out AReason: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := TExtractSuperclass.Plan(TClassSource.Create(mTree, AText, ALine), ARequest, nil, nil, APlan, AReason);
  finally
    mTree.Free;
  end;
end;

/// <summary>Text zwischen AFrom und ATo (ohne beide); '' ohne.</summary>
function Between(const AText, AFrom, ATo: string): string;
var
  mStart, mStop: Integer;
begin
  mStart := Pos(AFrom, AText);
  if mStart = 0 then
  begin
    Exit('');
  end;
  mStart := mStart + Length(AFrom);
  mStop := PosEx(ATo, AText, mStart);
  if mStop = 0 then
  begin
    Exit('');
  end;
  Result := Copy(AText, mStart, mStop - mStart);
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
  mTree: TSyntaxTree;
  mInfo: TSuperclassInfo;
  mReason: string;
  mItem: TTransferCandidate;
  mNames: string;
begin
  mTree := TPascalParser.Parse(cExport_);
  try
    Assert.IsTrue(TExtractSuperclass.Prepare(TClassSource.Create(mTree, cExport_, 4), 'Base',
      function(const AName: string): Boolean
      begin
        Result := SameText(AName, 'TExportBase');
      end, mInfo, mReason), mReason);
  finally
    mTree.Free;
  end;
  Assert.AreEqual('TPdfExport', mInfo.ClassName);
  // Vorschlag vergeben: der ganze Name.
  Assert.AreEqual('TPdfExportBase', mInfo.SuggestedName);
  Assert.AreEqual('TComponent', mInfo.Ancestor);
  mNames := '';
  for mItem in mInfo.Candidates do
  begin
    mNames := mNames + mItem.Name + ' ';
  end;
  Assert.AreEqual('FTitle FPages FCompressed GetTitle Run WritePage Title ', mNames);
  Assert.IsTrue(mInfo.Candidates[3].CanAbstract);
  // Run braucht WritePage und FTitle.
  Assert.AreEqual(2, Integer(Length(mInfo.Candidates[4].Needs)));
  Assert.AreEqual(1, Integer(Length(mInfo.Notes)));
end;

procedure TExtractSuperclassTests.MovesFieldAndMethod;
var
  mPlan: TSuperclassPlan;
  mReason, mBase: string;
begin
  Assert.IsTrue(Run(cExport_, 4, Request(cExport_, 4, 'TExportBase', ['FPages', 'WritePage'], [], True), mPlan,
    mReason), mReason);
  Assert.IsTrue(Parses(mPlan.Text), mPlan.Text);
  mBase := Between(mPlan.Text, 'TExportBase = class(TComponent)', 'end;');
  Assert.IsTrue(ContainsStr(mBase, '    FPages: TStringList;'), mBase);
  Assert.IsTrue(ContainsStr(mBase, '    procedure WritePage(const AText: string);'), mBase);
  // In derselben Unit sieht die Klasse private Felder der Basisklasse.
  Assert.IsTrue(ContainsStr(mBase, '  private'#10), mBase);
  Assert.IsTrue(ContainsStr(mPlan.Text, 'TPdfExport = class(TExportBase)'), mPlan.Text);
  Assert.IsTrue(ContainsStr(mPlan.Text, 'procedure TExportBase.WritePage(const AText: string);'), mPlan.Text);
  Assert.IsFalse(ContainsStr(mPlan.Text, 'procedure TPdfExport.WritePage'), mPlan.Text);
  Assert.IsFalse(ContainsStr(Between(mPlan.Text, 'TPdfExport = class', 'end;'), 'FPages'), mPlan.Text);
  // Die Basisklasse steht direkt über der Klasse, ihre Rümpfe vor denen der Klasse.
  Assert.IsTrue(Pos('TExportBase = class', mPlan.Text) < Pos('TPdfExport = class', mPlan.Text));
  Assert.IsTrue(Pos('TExportBase.WritePage', mPlan.Text) < Pos('TPdfExport.Create', mPlan.Text));
  Assert.AreEqual(4, mPlan.BaseLine);
  Assert.AreEqual(2, Integer(Length(mPlan.Moved)));
end;

procedure TExtractSuperclassTests.AbstractMethodStaysBelow;
var
  mPlan: TSuperclassPlan;
  mReason: string;
begin
  Assert.IsTrue(Run(cExport_, 4, Request(cExport_, 4, 'TExportBase', ['FTitle', 'Run', 'WritePage'], ['WritePage'],
    True), mPlan, mReason), mReason);
  Assert.IsTrue(Parses(mPlan.Text), mPlan.Text);
  Assert.IsTrue(ContainsStr(mPlan.Text, '    procedure WritePage(const AText: string); virtual; abstract;'),
    mPlan.Text);
  Assert.IsTrue(ContainsStr(mPlan.Text, '    procedure WritePage(const AText: string); override;'), mPlan.Text);
  Assert.IsTrue(ContainsStr(mPlan.Text, 'procedure TPdfExport.WritePage(const AText: string);'), mPlan.Text);
  Assert.IsTrue(ContainsStr(mPlan.Text, 'procedure TExportBase.Run;'), mPlan.Text);
  Assert.AreEqual(1, Integer(Length(mPlan.Abstracts)));
end;

procedure TExtractSuperclassTests.RejectsMissingDependency;
var
  mPlan: TSuperclassPlan;
  mReason: string;
begin
  Assert.IsFalse(Run(cExport_, 4, Request(cExport_, 4, 'TExportBase', ['Run'], [], True), mPlan, mReason));
  Assert.IsTrue(ContainsStr(mReason, 'Run braucht FTitle'), mReason);
  Assert.IsTrue(ContainsStr(mReason, 'Run braucht WritePage'), mReason);
  // Eine Property braucht ihre Zugriffe.
  Assert.IsFalse(Run(cExport_, 4, Request(cExport_, 4, 'TExportBase', ['Title', 'FTitle'], [], True), mPlan, mReason));
  Assert.IsTrue(ContainsStr(mReason, 'Title braucht GetTitle'), mReason);
  // Abstrakt deklariert genügt.
  Assert.IsTrue(Run(cExport_, 4, Request(cExport_, 4, 'TExportBase', ['Title', 'FTitle', 'GetTitle'], ['GetTitle'],
    True), mPlan, mReason), mReason);
end;

procedure TExtractSuperclassTests.RaisesStrictPrivate;
const
  cSource =
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
  mPlan: TSuperclassPlan;
  mReason, mBase: string;
  mReq: TSuperclassRequest;
begin
  Assert.IsTrue(Run(cSource, 3, Request(cSource, 3, 'TFooBase', ['FCount', 'FName'], [], True), mPlan, mReason), mReason);
  Assert.IsTrue(Parses(mPlan.Text), mPlan.Text);
  mBase := Between(mPlan.Text, 'TFooBase = class', 'end;');
  Assert.IsTrue(ContainsStr(mBase, '  strict private'#10'    FName: string;'), mBase);
  Assert.IsTrue(ContainsStr(mBase, '  protected'#10'    FCount: Integer;'), mBase);
  Assert.AreEqual('FCount', string.Join(',', mPlan.Raised));
  Assert.AreEqual(1, Integer(Length(mPlan.Warnings)));
  mReq := Request(cSource, 3, 'TFooBase', ['FCount'], [], True);
  mReq.RaiseVisibility := TClassVisibility.StrictProtected;
  Assert.IsTrue(Run(cSource, 3, mReq, mPlan, mReason), mReason);
  Assert.IsTrue(ContainsStr(mPlan.Text, '  strict protected'#10'    FCount: Integer;'), mPlan.Text);
end;

procedure TExtractSuperclassTests.RaisesPrivateForOtherUnit;
var
  mPlan: TSuperclassPlan;
  mReason, mBase: string;
begin
  Assert.IsTrue(Run(cExport_, 4, Request(cExport_, 4, 'TExportBase', ['FPages', 'WritePage'], [], False), mPlan,
    mReason), mReason);
  mBase := Between(mPlan.Text, 'TExportBase = class(TComponent)', 'end;');
  // FPages benutzt der bleibende Rumpf nicht mehr (Konstruktor und Destruktor aufgeteilt).
  Assert.IsTrue(ContainsStr(mBase, '  private'#10'    FPages: TStringList;'), mBase);
  Assert.AreEqual(0, Integer(Length(mPlan.Raised)));
  Assert.IsTrue(Run(cExport_, 4, Request(cExport_, 4, 'TExportBase', ['FTitle'], [], False), mPlan, mReason), mReason);
  Assert.IsTrue(ContainsStr(mPlan.Text, '  protected'#10'    FTitle: string;'), mPlan.Text);
end;

procedure TExtractSuperclassTests.SplitsConstructorAndDestructor;
var
  mPlan: TSuperclassPlan;
  mReason, mText: string;
begin
  Assert.IsTrue(Run(cExport_, 4, Request(cExport_, 4, 'TExportBase', ['FPages', 'FCompressed'], [], True), mPlan,
    mReason), mReason);
  mText := mPlan.Text;
  Assert.IsTrue(Parses(mText), mText);
  Assert.IsTrue(ContainsStr(mText, '    constructor Create(AOwner: TComponent); override;'#10 +
    '    destructor Destroy; override;'#10'  end;'), mText);
  Assert.IsTrue(ContainsStr(mText, 'constructor TExportBase.Create(AOwner: TComponent);'#10'begin'#10 +
    '  inherited Create(AOwner);'#10'  FPages := TStringList.Create;'#10'  FCompressed := True;'#10'end;'), mText);
  Assert.IsTrue(ContainsStr(mText, 'destructor TExportBase.Destroy;'#10'begin'#10'  FPages.Free;'#10 +
    '  inherited;'#10'end;'), mText);
  Assert.IsTrue(ContainsStr(mText, 'constructor TPdfExport.Create(AOwner: TComponent);'#10'begin'#10 +
    '  inherited;'#10'end;'), mText);
  Assert.IsTrue(ContainsStr(mText, 'destructor TPdfExport.Destroy;'#10'begin'#10'  inherited;'#10'end;'), mText);
  Assert.AreEqual('Create,Destroy', string.Join(',', mPlan.Split));
end;

procedure TExtractSuperclassTests.KeepsInterfacesBelow;
const
  cSource =
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
  mPlan: TSuperclassPlan;
  mReason: string;
begin
  Assert.IsTrue(Run(cSource, 3, Request(cSource, 3, 'TFooBase', ['Run'], [], True), mPlan, mReason), mReason);
  Assert.IsTrue(ContainsStr(mPlan.Text, 'TFooBase = class(TInterfacedObject)'), mPlan.Text);
  Assert.IsTrue(ContainsStr(mPlan.Text, 'TFoo = class(TFooBase, IFoo, IBar)'), mPlan.Text);
  Assert.IsTrue(Run(cSource, 7, Request(cSource, 7, 'TBazBase', ['Run'], [], True), mPlan, mReason), mReason);
  Assert.IsTrue(ContainsStr(mPlan.Text, 'TBazBase = class'#10), mPlan.Text);
  Assert.IsTrue(ContainsStr(mPlan.Text, 'TBaz = class(TBazBase, IFoo)'), mPlan.Text);
end;

procedure TExtractSuperclassTests.AddsForwardDeclaration;
const
  cSource =
    'unit U;'#10'interface'#10'type'#10 +
    '  TNode = class'#10 +            // 3
    '  public'#10 +
    '    function Clone: TNode;'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'function TNode.Clone: TNode;'#10'begin'#10'  Result := nil;'#10'end;'#10#10'end.'#10;
var
  mPlan: TSuperclassPlan;
  mReason: string;
begin
  Assert.IsTrue(Run(cSource, 3, Request(cSource, 3, 'TNodeBase', ['Clone'], [], True), mPlan, mReason), mReason);
  Assert.IsTrue(Parses(mPlan.Text), mPlan.Text);
  Assert.IsTrue(ContainsStr(mPlan.Text, 'type'#10'  TNode = class;'#10#10'  TNodeBase = class'#10), mPlan.Text);
  Assert.AreEqual(5, mPlan.BaseLine);
end;

procedure TExtractSuperclassTests.GenericClass;
const
  cSource =
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
  mPlan: TSuperclassPlan;
  mReason: string;
begin
  Assert.IsTrue(Run(cSource, 3, Request(cSource, 3, 'TBoxBase', ['FItem', 'Get'], [], True), mPlan, mReason), mReason);
  Assert.IsTrue(Parses(mPlan.Text), mPlan.Text);
  Assert.IsTrue(ContainsStr(mPlan.Text, 'TBoxBase<T: class> = class'#10), mPlan.Text);
  Assert.IsTrue(ContainsStr(mPlan.Text, 'TBox<T: class> = class(TBoxBase<T>)'), mPlan.Text);
  Assert.IsTrue(ContainsStr(mPlan.Text, 'function TBoxBase<T>.Get: T;'), mPlan.Text);
end;

procedure TExtractSuperclassTests.RelocatesRaisedAbstractOverride;
const
  cSource =
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
  mPlan: TSuperclassPlan;
  mReason, mJob: string;
begin
  Assert.IsTrue(Run(cSource, 3, Request(cSource, 3, 'TJobBase', ['Step', 'Run'], ['Step'], False), mPlan, mReason),
    mReason);
  Assert.IsTrue(Parses(mPlan.Text), mPlan.Text);
  Assert.IsTrue(ContainsStr(mPlan.Text, '  protected'#10'    procedure Step; virtual; abstract;'), mPlan.Text);
  mJob := Between(mPlan.Text, 'TJob = class(TJobBase)', 'end;');
  // Gleiche Sichtbarkeit unten (sonst H2269).
  Assert.IsTrue(ContainsStr(mJob, '  protected'#10'    procedure Step; override;'), mJob);
  // Der leere private-Abschnitt fällt weg.
  Assert.IsFalse(ContainsStr(mJob, 'private'), mJob);
end;

procedure TExtractSuperclassTests.RejectsBadInput;
var
  mPlan: TSuperclassPlan;
  mReason: string;
  mReq: TSuperclassRequest;
begin
  Assert.IsFalse(Run(cExport_, 4, Request(cExport_, 4, '1Base', ['FTitle'], [], True), mPlan, mReason));
  Assert.IsFalse(Run(cExport_, 4, Request(cExport_, 4, 'TPdfExport', ['FTitle'], [], True), mPlan, mReason));
  Assert.IsFalse(Run(cExport_, 4, Request(cExport_, 4, 'TExportBase', [], [], True), mPlan, mReason));
  Assert.IsFalse(Run(cExport_, 4, Request(cExport_, 4, 'TExportBase', ['FTitle'], ['FTitle'], True), mPlan, mReason));
  Assert.IsTrue(ContainsStr(mReason, 'abstrakt'), mReason);
  mReq := Request(cExport_, 4, 'TExportBase', ['FTitle'], [], True);
  mReq.Members := mReq.Members + [IdOf(cExport_, 4, 'Create')];
  Assert.IsFalse(Run(cExport_, 4, mReq, mPlan, mReason));
  // Nicht auf der Kopfzeile.
  Assert.IsFalse(Run(cExport_, 6, Request(cExport_, 4, 'TExportBase', ['FTitle'], [], True), mPlan, mReason));
end;

initialization
  TDUnitX.RegisterTestFixture(TExtractSuperclassTests);

end.
