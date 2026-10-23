unit Atlas.Common.Editing.MoveMember.Tests;

// Tests für „Mitglied in Vorfahr oder Nachfahr verschieben“ (#675): Methode,
// Feld und Property nach oben und unten, Abhängigkeiten, Sichtbarkeit,
// abstrakte Variante, andere Nachfahren mit override, Namenskonflikte,
// Verbot bei Nutzung über den Vorfahr-Typ und Ziel in einer anderen Datei.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Editing.MoveMember;

type
  [TestFixture]
  TMoveMemberTests = class
  private
    FFiles: TMemberFiles;
    FText: string;
    FReason: string;
    function Up(const AMembers, AAbstract: array of string; AOverrideSiblings: Boolean;
      out APlan: TMoveMemberPlan): Boolean;
    function Down(const AMembers: array of string; AKeepAbstract: Boolean; const ATargets: array of string;
      out APlan: TMoveMemberPlan): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure PrepareFindsMember;
    [Test]
    procedure PullsUpFieldAndMethod;
    [Test]
    procedure PullUpNeedsDependencies;
    [Test]
    procedure PullsUpAbstract;
    [Test]
    procedure PullUpRejectsNameInTarget;
    [Test]
    procedure PullUpOverridesSiblings;
    [Test]
    procedure PullsUpPropertyWithField;
    [Test]
    procedure PullUpRaisesPrivateForOtherUnit;
    [Test]
    procedure PushesDownFieldAndMethod;
    [Test]
    procedure PushDownRejectsUseInAncestor;
    [Test]
    procedure PushDownRejectsForeignUse;
    [Test]
    procedure PushDownKeepsAbstract;
    [Test]
    procedure PushDownRaisesHiddenNeeds;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ClassLayout,
  Atlas.Common.Editing.MemberTransfer;

const
  FileU = 'C:\P\U.pas';
  FileB = 'C:\P\B.pas';
  Source =
    'unit U;'#10 +                                   // 0
    'interface'#10 +                                 // 1
    'type'#10 +                                      // 2
    '  TBase = class'#10 +                           // 3
    '  public'#10 +                                  // 4
    '    procedure Show;'#10 +                       // 5
    '  end;'#10 +                                    // 6
    '  TChild = class(TBase)'#10 +                   // 7
    '  private'#10 +                                 // 8
    '    FCount: Integer;'#10 +                      // 9
    '  public'#10 +                                  // 10
    '    procedure Step;'#10 +                       // 11
    '    procedure Run;'#10 +                        // 12
    '    property Count: Integer read FCount;'#10 +  // 13
    '  end;'#10 +                                    // 14
    '  TOther = class(TBase)'#10 +                   // 15
    '  public'#10 +                                  // 16
    '    procedure Run;'#10 +                        // 17
    '  end;'#10 +                                    // 18
    'implementation'#10#10 +
    'procedure TBase.Show;'#10'begin'#10'end;'#10#10 +
    'procedure TChild.Step;'#10'begin'#10'  FCount := FCount + 1;'#10'end;'#10#10 +
    'procedure TChild.Run;'#10'begin'#10'  Step;'#10'end;'#10#10 +
    'procedure TOther.Run;'#10'begin'#10'end;'#10#10 +
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

/// <summary>Ids der Mitglieder ANames der Klasse AClass in AText.</summary>
function Ids(const AText, AClass: string; const ANames: array of string): TArray<Integer>;
var
  Layout: TClassLayout;
  Tree: TSyntaxTree;
  Name: string;
begin
  Result := nil;
  Layout := TMemberTransfer.ParseLayout(AText, AClass, Tree);
  try
    for Name in ANames do
      Result := Result + [Layout.Find(Name)[0]];
  finally
    Layout.Free;
    Tree.Free;
  end;
end;

/// <summary>Zeilen der Klasse AClass in AText (Kopf bis end), ohne Einrückung, mit | verbunden.</summary>
function ClassText(const AText, AClass: string): string;
var
  Layout: TClassLayout;
  Tree: TSyntaxTree;
  Line: Integer;
begin
  Result := '';
  Layout := TMemberTransfer.ParseLayout(AText, AClass, Tree);
  if Layout = nil then
    Exit('?');
  try
    for Line := Layout.HeaderLine to Layout.EndLine do
      Result := Result + Trim(Layout.Lines[Line]) + '|';
  finally
    Layout.Free;
    Tree.Free;
  end;
end;

procedure TMoveMemberTests.Setup;
begin
  FFiles := TMemberFiles.Create;
  FFiles.Add(FileU, Source);
end;

procedure TMoveMemberTests.TearDown;
begin
  FreeAndNil(FFiles);
  FText := '';
  FReason := '';
end;

function TMoveMemberTests.Up(const AMembers, AAbstract: array of string; AOverrideSiblings: Boolean;
  out APlan: TMoveMemberPlan): Boolean;
var
  Request: TMoveMemberRequest;
begin
  Request := Default(TMoveMemberRequest);
  Request.Members := Ids(FFiles.Text(FileU), 'TChild', AMembers);
  Request.Abstract := Ids(FFiles.Text(FileU), 'TChild', AAbstract);
  Request.Siblings := [TMemberClassRef.Create(FileU, 'TChild'), TMemberClassRef.Create(FileU, 'TOther')];
  Request.OverrideSiblings := AOverrideSiblings;
  Request.RaiseVisibility := TClassVisibility.Protected_;
  Result := TMoveMember.PullUp(FFiles, TMemberClassRef.Create(FileU, 'TChild'),
    TMemberClassRef.Create(FileU, 'TBase'), Request, APlan, FReason);
  FText := FFiles.Text(FileU);
end;

function TMoveMemberTests.Down(const AMembers: array of string; AKeepAbstract: Boolean;
  const ATargets: array of string; out APlan: TMoveMemberPlan): Boolean;
var
  Request: TMoveMemberRequest;
  Targets: TArray<TMemberClassRef>;
  Name: string;
begin
  Request := Default(TMoveMemberRequest);
  Request.Members := Ids(FFiles.Text(FileU), 'TBase', AMembers);
  Request.KeepAbstract := AKeepAbstract;
  Request.AllTargets := 2;
  Request.RaiseVisibility := TClassVisibility.Protected_;
  Targets := nil;
  for Name in ATargets do
    Targets := Targets + [TMemberClassRef.Create(FileU, Name)];
  Result := TMoveMember.PushDown(FFiles, TMemberClassRef.Create(FileU, 'TBase'), Targets, Request, APlan,
    FReason);
  FText := FFiles.Text(FileU);
end;

procedure TMoveMemberTests.PrepareFindsMember;
var
  Tree: TSyntaxTree;
  Info: TMoveMemberInfo;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Assert.IsTrue(TMoveMember.Prepare(Tree, Source, 11, Info, FReason), FReason);
    Assert.AreEqual('TChild', Info.ClassName);
    Assert.AreEqual('Step', Info.SelectedName);
    Assert.AreEqual('TBase', Info.Ancestor);
    Assert.AreEqual(4, Integer(Length(Info.Candidates)));
    Assert.IsFalse(TMoveMember.Prepare(Tree, Source, 7, Info, FReason), 'Kopfzeile');
    Assert.IsFalse(TMoveMember.Prepare(Tree, Source, 21, Info, FReason), 'implementation');
  finally
    Tree.Free;
  end;
end;

procedure TMoveMemberTests.PullsUpFieldAndMethod;
var
  Plan: TMoveMemberPlan;
begin
  Assert.IsTrue(Up(['FCount', 'Step'], [], False, Plan), FReason);
  Assert.IsTrue(Parses(FText), FText);
  // In derselben Unit bleibt private private.
  Assert.AreEqual('TBase = class|private|FCount: Integer;|public|procedure Show;|procedure Step;|end;|',
    ClassText(FText, 'TBase'));
  Assert.AreEqual('TChild = class(TBase)|public|procedure Run;|property Count: Integer read FCount;|end;|',
    ClassText(FText, 'TChild'));
  Assert.IsTrue(ContainsStr(FText, 'procedure TBase.Step;'#10'begin'#10'  FCount := FCount + 1;'), FText);
  Assert.IsFalse(ContainsStr(FText, 'TChild.Step'), FText);
  Assert.AreEqual(2, Integer(Length(Plan.Moved)));
end;

procedure TMoveMemberTests.PullUpNeedsDependencies;
var
  Plan: TMoveMemberPlan;
begin
  Assert.IsFalse(Up(['Step'], [], False, Plan));
  Assert.IsTrue(ContainsStr(FReason, 'Step braucht FCount'), FReason);
  Assert.AreEqual(Source, FText);
end;

procedure TMoveMemberTests.PullsUpAbstract;
var
  Plan: TMoveMemberPlan;
begin
  // Run benutzt Step, wandert aber nur abstrakt.
  Assert.IsTrue(Up(['Run'], ['Run'], False, Plan), FReason);
  Assert.IsTrue(Parses(FText), FText);
  Assert.AreEqual('TBase = class|public|procedure Show;|procedure Run; virtual; abstract;|end;|',
    ClassText(FText, 'TBase'));
  Assert.IsTrue(ContainsStr(ClassText(FText, 'TChild'), '|procedure Run; override;|'), FText);
  Assert.IsTrue(ContainsStr(FText, 'procedure TChild.Run;'), FText);
  Assert.AreEqual('Run', Plan.Abstracts[0]);
  // TOther.Run passt, wird aber ohne die Wahl nicht override.
  Assert.AreEqual(1, Integer(Length(Plan.Warnings)));
  Assert.IsTrue(ContainsStr(Plan.Warnings[0], 'TOther.Run verdeckt'), Plan.Warnings[0]);
end;

procedure TMoveMemberTests.PullUpRejectsNameInTarget;
var
  Plan: TMoveMemberPlan;
begin
  FFiles.Put(FileU, StringReplace(Source, '    procedure Show;', '    procedure Run;', []));
  Assert.IsFalse(Up(['Run'], ['Run'], False, Plan));
  Assert.IsTrue(ContainsStr(FReason, 'TBase hat schon ein Mitglied Run'), FReason);
end;

procedure TMoveMemberTests.PullUpOverridesSiblings;
var
  Plan: TMoveMemberPlan;
begin
  Assert.IsTrue(Up(['FCount', 'Step', 'Run'], [], True, Plan), FReason);
  Assert.IsTrue(Parses(FText), FText);
  Assert.IsTrue(ContainsStr(ClassText(FText, 'TBase'), '|procedure Run; virtual;|'), FText);
  Assert.AreEqual('TOther = class(TBase)|public|procedure Run; override;|end;|', ClassText(FText, 'TOther'));
  Assert.AreEqual('TOther.Run', Plan.Overridden[0]);
  Assert.IsTrue(ContainsStr(FText, 'procedure TBase.Run;'), FText);
  Assert.IsTrue(ContainsStr(FText, 'procedure TOther.Run;'), FText);
end;

procedure TMoveMemberTests.PullsUpPropertyWithField;
var
  Plan: TMoveMemberPlan;
begin
  Assert.IsFalse(Up(['Count'], [], False, Plan));
  Assert.IsTrue(ContainsStr(FReason, 'Count braucht FCount'), FReason);
  Assert.IsTrue(Up(['FCount', 'Count'], [], False, Plan), FReason);
  Assert.IsTrue(Parses(FText), FText);
  Assert.AreEqual('TBase = class|private|FCount: Integer;|public|procedure Show;|' +
    'property Count: Integer read FCount;|end;|', ClassText(FText, 'TBase'));
end;

procedure TMoveMemberTests.PullUpRaisesPrivateForOtherUnit;
const
  UnitB =
    'unit B;'#10'interface'#10'type'#10 +
    '  TBase = class'#10 +
    '  public'#10 +
    '    procedure Show;'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'procedure TBase.Show;'#10'begin'#10'end;'#10#10 +
    'end.'#10;
  UnitU =
    'unit U;'#10'interface'#10'uses'#10'  B;'#10'type'#10 +
    '  TChild = class(TBase)'#10 +
    '  private'#10 +
    '    FCount: Integer;'#10 +
    '  public'#10 +
    '    procedure Step;'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'procedure TChild.Step;'#10'begin'#10'  FCount := FCount + 1;'#10'end;'#10#10 +
    'end.'#10;
var
  Request: TMoveMemberRequest;
  Plan: TMoveMemberPlan;
begin
  FFiles.Put(FileU, UnitU);
  FFiles.Add(FileB, UnitB);
  Request := Default(TMoveMemberRequest);
  Request.Members := Ids(UnitU, 'TChild', ['FCount']);
  Request.RaiseVisibility := TClassVisibility.StrictProtected;
  Assert.IsTrue(TMoveMember.PullUp(FFiles, TMemberClassRef.Create(FileU, 'TChild'),
    TMemberClassRef.Create(FileB, 'TBase'), Request, Plan, FReason), FReason);
  Assert.AreEqual('TBase = class|strict protected|FCount: Integer;|public|procedure Show;|end;|',
    ClassText(FFiles.Text(FileB), 'TBase'));
  Assert.AreEqual('TChild = class(TBase)|public|procedure Step;|end;|', ClassText(FFiles.Text(FileU), 'TChild'));
  Assert.AreEqual('FCount', Plan.Raised[0]);
  Assert.IsTrue(Parses(FFiles.Text(FileB)), FFiles.Text(FileB));
end;

procedure TMoveMemberTests.PushesDownFieldAndMethod;
const
  Base =
    'unit U;'#10'interface'#10'type'#10 +
    '  TBase = class'#10 +
    '  private'#10 +
    '    FData: string;'#10 +
    '  public'#10 +
    '    procedure Load;'#10 +
    '    procedure Show;'#10 +
    '  end;'#10 +
    '  TChild = class(TBase)'#10 +
    '  public'#10 +
    '    procedure Run;'#10 +
    '  end;'#10 +
    '  TOther = class(TBase)'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'procedure TBase.Load;'#10'begin'#10'  FData := ''x'';'#10'end;'#10#10 +
    'procedure TBase.Show;'#10'begin'#10'end;'#10#10 +
    'procedure TChild.Run;'#10'begin'#10'  Load;'#10'end;'#10#10 +
    'end.'#10;
var
  Plan: TMoveMemberPlan;
begin
  FFiles.Put(FileU, Base);
  Assert.IsTrue(Down(['FData', 'Load'], False, ['TChild'], Plan), FReason);
  Assert.IsTrue(Parses(FText), FText);
  Assert.AreEqual('TBase = class|public|procedure Show;|end;|', ClassText(FText, 'TBase'));
  Assert.AreEqual('TChild = class(TBase)|private|FData: string;|public|procedure Run;|procedure Load;|end;|',
    ClassText(FText, 'TChild'));
  Assert.IsTrue(ContainsStr(FText, 'procedure TChild.Load;'#10'begin'#10'  FData := ''x'';'), FText);
  Assert.IsFalse(ContainsStr(FText, 'TBase.Load'), FText);
end;

procedure TMoveMemberTests.PushDownRejectsUseInAncestor;
const
  Base =
    'unit U;'#10'interface'#10'type'#10 +
    '  TBase = class'#10 +
    '  public'#10 +
    '    procedure Load;'#10 +
    '    procedure Show;'#10 +
    '  end;'#10 +
    '  TChild = class(TBase)'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'procedure TBase.Load;'#10'begin'#10'end;'#10#10 +
    'procedure TBase.Show;'#10'begin'#10'  Load;'#10'end;'#10#10 +
    'end.'#10;
var
  Plan: TMoveMemberPlan;
begin
  FFiles.Put(FileU, Base);
  Assert.IsFalse(Down(['Load'], False, ['TChild'], Plan));
  Assert.IsTrue(ContainsStr(FReason, 'Load wird in TBase weiter benutzt (Show)'), FReason);
  // Abstrakt im Vorfahren lassen: geht.
  Assert.IsTrue(Down(['Load'], True, ['TChild'], Plan), FReason);
  Assert.IsTrue(Parses(FText), FText);
  Assert.AreEqual('TBase = class|public|procedure Load; virtual; abstract;|procedure Show;|end;|',
    ClassText(FText, 'TBase'));
  // Ohne Abschnitt: in den ersten, unbenannten.
  Assert.AreEqual('TChild = class(TBase)|procedure Load; override;|end;|', ClassText(FText, 'TChild'));
  Assert.IsTrue(ContainsStr(FText, 'procedure TChild.Load;'), FText);
  Assert.IsFalse(ContainsStr(FText, 'procedure TBase.Load;'), FText);
end;

procedure TMoveMemberTests.PushDownRejectsForeignUse;
const
  Base =
    'unit U;'#10'interface'#10'type'#10 +
    '  TBase = class'#10 +
    '  public'#10 +
    '    procedure Load;'#10 +
    '  end;'#10 +
    '  TChild = class(TBase)'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'procedure TBase.Load;'#10'begin'#10'end;'#10#10 +
    'end.'#10;
var
  Request: TMoveMemberRequest;
  Plan: TMoveMemberPlan;
begin
  FFiles.Put(FileU, Base);
  Request := Default(TMoveMemberRequest);
  Request.Members := Ids(Base, 'TBase', ['Load']);
  Request.Usages := [TMemberUsage.Create(Request.Members[0], 'Main.pas:12')];
  Assert.IsFalse(TMoveMember.PushDown(FFiles, TMemberClassRef.Create(FileU, 'TBase'),
    [TMemberClassRef.Create(FileU, 'TChild')], Request, Plan, FReason));
  Assert.IsTrue(ContainsStr(FReason, 'außerhalb der Nachfahren über TBase benutzt: Main.pas:12'), FReason);
  Assert.AreEqual(Base, FFiles.Text(FileU));
end;

procedure TMoveMemberTests.PushDownKeepsAbstract;
const
  Base =
    'unit U;'#10'interface'#10'type'#10 +
    '  TBase = class'#10 +
    '  public'#10 +
    '    /// <summary>Laedt.</summary>'#10 +
    '    procedure Load; overload;'#10 +
    '  end;'#10 +
    '  TChild = class(TBase)'#10 +
    '  end;'#10 +
    '  TOther = class(TBase)'#10 +
    '  public'#10 +
    '    procedure Load; overload; override;'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'procedure TBase.Load;'#10'begin'#10'end;'#10#10 +
    'procedure TOther.Load;'#10'begin'#10'end;'#10#10 +
    'end.'#10;
var
  Plan: TMoveMemberPlan;
begin
  FFiles.Put(FileU, Base);
  Assert.IsTrue(Down(['Load'], True, ['TChild', 'TOther'], Plan), FReason);
  Assert.IsTrue(Parses(FText), FText);
  Assert.AreEqual('TBase = class|public|/// <summary>Laedt.</summary>|procedure Load; overload; virtual; abstract;|' +
    'end;|', ClassText(FText, 'TBase'));
  Assert.AreEqual('TChild = class(TBase)|/// <summary>Laedt.</summary>|procedure Load; overload; override;|' +
    'end;|', ClassText(FText, 'TChild'));
  // TOther überschreibt schon: bleibt.
  Assert.AreEqual('TOther = class(TBase)|public|procedure Load; overload; override;|end;|',
    ClassText(FText, 'TOther'));
  Assert.IsTrue(ContainsStr(FText, 'procedure TChild.Load;'), FText);
  Assert.AreEqual(0, Integer(Length(Plan.Warnings)));
  // Nur ein Nachfahr von zweien: Hinweis.
  FFiles.Put(FileU, Base);
  Assert.IsTrue(Down(['Load'], True, ['TChild'], Plan), FReason);
  Assert.AreEqual(1, Integer(Length(Plan.Warnings)));
end;

procedure TMoveMemberTests.PushDownRaisesHiddenNeeds;
const
  Base =
    'unit U;'#10'interface'#10'type'#10 +
    '  TBase = class'#10 +
    '  strict private'#10 +
    '    FSecret: Integer;'#10 +
    '  public'#10 +
    '    procedure Load;'#10 +
    '  end;'#10 +
    '  TChild = class(TBase)'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'procedure TBase.Load;'#10'begin'#10'  FSecret := 1;'#10'end;'#10#10 +
    'end.'#10;
var
  Plan: TMoveMemberPlan;
begin
  FFiles.Put(FileU, Base);
  Assert.IsTrue(Down(['Load'], False, ['TChild'], Plan), FReason);
  Assert.IsTrue(Parses(FText), FText);
  Assert.AreEqual('TBase = class|protected|FSecret: Integer;|end;|', ClassText(FText, 'TBase'));
  Assert.AreEqual('FSecret', Plan.Raised[0]);
end;

initialization
  TDUnitX.RegisterTestFixture(TMoveMemberTests);

end.
