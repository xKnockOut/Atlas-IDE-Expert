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
  cFileU = 'C:\P\U.pas';
  cFileB = 'C:\P\B.pas';
  cSource =
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
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := Length(mTree.Diagnostics) = 0;
  finally
    mTree.Free;
  end;
end;

/// <summary>Ids der Mitglieder ANames der Klasse AClass in AText.</summary>
function Ids(const AText, AClass: string; const ANames: array of string): TArray<Integer>;
var
  mLayout: TClassLayout;
  mTree: TSyntaxTree;
  mName: string;
begin
  Result := nil;
  mLayout := TMemberTransfer.ParseLayout(AText, AClass, mTree);
  try
    for mName in ANames do
    begin
      Result := Result + [mLayout.Find(mName)[0]];
    end;
  finally
    mLayout.Free;
    mTree.Free;
  end;
end;

/// <summary>Zeilen der Klasse AClass in AText (Kopf bis end), ohne Einrückung, mit | verbunden.</summary>
function ClassText(const AText, AClass: string): string;
var
  mLayout: TClassLayout;
  mTree: TSyntaxTree;
  mLine: Integer;
begin
  Result := '';
  mLayout := TMemberTransfer.ParseLayout(AText, AClass, mTree);
  if mLayout = nil then
  begin
    Exit('?');
  end;
  try
    for mLine := mLayout.HeaderLine to mLayout.EndLine do
    begin
      Result := Result + Trim(mLayout.Lines[mLine]) + '|';
    end;
  finally
    mLayout.Free;
    mTree.Free;
  end;
end;

procedure TMoveMemberTests.Setup;
begin
  FFiles := TMemberFiles.Create;
  FFiles.Add(cFileU, cSource);
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
  mRequest: TMoveMemberRequest;
begin
  mRequest := Default(TMoveMemberRequest);
  mRequest.Members := Ids(FFiles.Text(cFileU), 'TChild', AMembers);
  mRequest.Abstract := Ids(FFiles.Text(cFileU), 'TChild', AAbstract);
  mRequest.Siblings := [TMemberClassRef.Create(cFileU, 'TChild'), TMemberClassRef.Create(cFileU, 'TOther')];
  mRequest.OverrideSiblings := AOverrideSiblings;
  mRequest.RaiseVisibility := TClassVisibility.Protected_;
  Result := TMoveMember.PullUp(FFiles, TMemberClassRef.Create(cFileU, 'TChild'),
    TMemberClassRef.Create(cFileU, 'TBase'), mRequest, APlan, FReason);
  FText := FFiles.Text(cFileU);
end;

function TMoveMemberTests.Down(const AMembers: array of string; AKeepAbstract: Boolean;
  const ATargets: array of string; out APlan: TMoveMemberPlan): Boolean;
var
  mRequest: TMoveMemberRequest;
  mTargets: TArray<TMemberClassRef>;
  mName: string;
begin
  mRequest := Default(TMoveMemberRequest);
  mRequest.Members := Ids(FFiles.Text(cFileU), 'TBase', AMembers);
  mRequest.KeepAbstract := AKeepAbstract;
  mRequest.AllTargets := 2;
  mRequest.RaiseVisibility := TClassVisibility.Protected_;
  mTargets := nil;
  for mName in ATargets do
  begin
    mTargets := mTargets + [TMemberClassRef.Create(cFileU, mName)];
  end;
  Result := TMoveMember.PushDown(FFiles, TMemberClassRef.Create(cFileU, 'TBase'), mTargets, mRequest, APlan,
    FReason);
  FText := FFiles.Text(cFileU);
end;

procedure TMoveMemberTests.PrepareFindsMember;
var
  mTree: TSyntaxTree;
  mInfo: TMoveMemberInfo;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.IsTrue(TMoveMember.Prepare(mTree, cSource, 11, mInfo, FReason), FReason);
    Assert.AreEqual('TChild', mInfo.ClassName);
    Assert.AreEqual('Step', mInfo.SelectedName);
    Assert.AreEqual('TBase', mInfo.Ancestor);
    Assert.AreEqual(4, Integer(Length(mInfo.Candidates)));
    Assert.IsFalse(TMoveMember.Prepare(mTree, cSource, 7, mInfo, FReason), 'Kopfzeile');
    Assert.IsFalse(TMoveMember.Prepare(mTree, cSource, 21, mInfo, FReason), 'implementation');
  finally
    mTree.Free;
  end;
end;

procedure TMoveMemberTests.PullsUpFieldAndMethod;
var
  mPlan: TMoveMemberPlan;
begin
  Assert.IsTrue(Up(['FCount', 'Step'], [], False, mPlan), FReason);
  Assert.IsTrue(Parses(FText), FText);
  // In derselben Unit bleibt private private.
  Assert.AreEqual('TBase = class|private|FCount: Integer;|public|procedure Show;|procedure Step;|end;|',
    ClassText(FText, 'TBase'));
  Assert.AreEqual('TChild = class(TBase)|public|procedure Run;|property Count: Integer read FCount;|end;|',
    ClassText(FText, 'TChild'));
  Assert.IsTrue(ContainsStr(FText, 'procedure TBase.Step;'#10'begin'#10'  FCount := FCount + 1;'), FText);
  Assert.IsFalse(ContainsStr(FText, 'TChild.Step'), FText);
  Assert.AreEqual(2, Integer(Length(mPlan.Moved)));
end;

procedure TMoveMemberTests.PullUpNeedsDependencies;
var
  mPlan: TMoveMemberPlan;
begin
  Assert.IsFalse(Up(['Step'], [], False, mPlan));
  Assert.IsTrue(ContainsStr(FReason, 'Step braucht FCount'), FReason);
  Assert.AreEqual(cSource, FText);
end;

procedure TMoveMemberTests.PullsUpAbstract;
var
  mPlan: TMoveMemberPlan;
begin
  // Run benutzt Step, wandert aber nur abstrakt.
  Assert.IsTrue(Up(['Run'], ['Run'], False, mPlan), FReason);
  Assert.IsTrue(Parses(FText), FText);
  Assert.AreEqual('TBase = class|public|procedure Show;|procedure Run; virtual; abstract;|end;|',
    ClassText(FText, 'TBase'));
  Assert.IsTrue(ContainsStr(ClassText(FText, 'TChild'), '|procedure Run; override;|'), FText);
  Assert.IsTrue(ContainsStr(FText, 'procedure TChild.Run;'), FText);
  Assert.AreEqual('Run', mPlan.Abstracts[0]);
  // TOther.Run passt, wird aber ohne die Wahl nicht override.
  Assert.AreEqual(1, Integer(Length(mPlan.Warnings)));
  Assert.IsTrue(ContainsStr(mPlan.Warnings[0], 'TOther.Run verdeckt'), mPlan.Warnings[0]);
end;

procedure TMoveMemberTests.PullUpRejectsNameInTarget;
var
  mPlan: TMoveMemberPlan;
begin
  FFiles.Put(cFileU, StringReplace(cSource, '    procedure Show;', '    procedure Run;', []));
  Assert.IsFalse(Up(['Run'], ['Run'], False, mPlan));
  Assert.IsTrue(ContainsStr(FReason, 'TBase hat schon ein Mitglied Run'), FReason);
end;

procedure TMoveMemberTests.PullUpOverridesSiblings;
var
  mPlan: TMoveMemberPlan;
begin
  Assert.IsTrue(Up(['FCount', 'Step', 'Run'], [], True, mPlan), FReason);
  Assert.IsTrue(Parses(FText), FText);
  Assert.IsTrue(ContainsStr(ClassText(FText, 'TBase'), '|procedure Run; virtual;|'), FText);
  Assert.AreEqual('TOther = class(TBase)|public|procedure Run; override;|end;|', ClassText(FText, 'TOther'));
  Assert.AreEqual('TOther.Run', mPlan.Overridden[0]);
  Assert.IsTrue(ContainsStr(FText, 'procedure TBase.Run;'), FText);
  Assert.IsTrue(ContainsStr(FText, 'procedure TOther.Run;'), FText);
end;

procedure TMoveMemberTests.PullsUpPropertyWithField;
var
  mPlan: TMoveMemberPlan;
begin
  Assert.IsFalse(Up(['Count'], [], False, mPlan));
  Assert.IsTrue(ContainsStr(FReason, 'Count braucht FCount'), FReason);
  Assert.IsTrue(Up(['FCount', 'Count'], [], False, mPlan), FReason);
  Assert.IsTrue(Parses(FText), FText);
  Assert.AreEqual('TBase = class|private|FCount: Integer;|public|procedure Show;|' +
    'property Count: Integer read FCount;|end;|', ClassText(FText, 'TBase'));
end;

procedure TMoveMemberTests.PullUpRaisesPrivateForOtherUnit;
const
  cUnitB =
    'unit B;'#10'interface'#10'type'#10 +
    '  TBase = class'#10 +
    '  public'#10 +
    '    procedure Show;'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'procedure TBase.Show;'#10'begin'#10'end;'#10#10 +
    'end.'#10;
  cUnitU =
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
  mRequest: TMoveMemberRequest;
  mPlan: TMoveMemberPlan;
begin
  FFiles.Put(cFileU, cUnitU);
  FFiles.Add(cFileB, cUnitB);
  mRequest := Default(TMoveMemberRequest);
  mRequest.Members := Ids(cUnitU, 'TChild', ['FCount']);
  mRequest.RaiseVisibility := TClassVisibility.StrictProtected;
  Assert.IsTrue(TMoveMember.PullUp(FFiles, TMemberClassRef.Create(cFileU, 'TChild'),
    TMemberClassRef.Create(cFileB, 'TBase'), mRequest, mPlan, FReason), FReason);
  Assert.AreEqual('TBase = class|strict protected|FCount: Integer;|public|procedure Show;|end;|',
    ClassText(FFiles.Text(cFileB), 'TBase'));
  Assert.AreEqual('TChild = class(TBase)|public|procedure Step;|end;|', ClassText(FFiles.Text(cFileU), 'TChild'));
  Assert.AreEqual('FCount', mPlan.Raised[0]);
  Assert.IsTrue(Parses(FFiles.Text(cFileB)), FFiles.Text(cFileB));
end;

procedure TMoveMemberTests.PushesDownFieldAndMethod;
const
  cBase =
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
  mPlan: TMoveMemberPlan;
begin
  FFiles.Put(cFileU, cBase);
  Assert.IsTrue(Down(['FData', 'Load'], False, ['TChild'], mPlan), FReason);
  Assert.IsTrue(Parses(FText), FText);
  Assert.AreEqual('TBase = class|public|procedure Show;|end;|', ClassText(FText, 'TBase'));
  Assert.AreEqual('TChild = class(TBase)|private|FData: string;|public|procedure Run;|procedure Load;|end;|',
    ClassText(FText, 'TChild'));
  Assert.IsTrue(ContainsStr(FText, 'procedure TChild.Load;'#10'begin'#10'  FData := ''x'';'), FText);
  Assert.IsFalse(ContainsStr(FText, 'TBase.Load'), FText);
end;

procedure TMoveMemberTests.PushDownRejectsUseInAncestor;
const
  cBase =
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
  mPlan: TMoveMemberPlan;
begin
  FFiles.Put(cFileU, cBase);
  Assert.IsFalse(Down(['Load'], False, ['TChild'], mPlan));
  Assert.IsTrue(ContainsStr(FReason, 'Load wird in TBase weiter benutzt (Show)'), FReason);
  // Abstrakt im Vorfahren lassen: geht.
  Assert.IsTrue(Down(['Load'], True, ['TChild'], mPlan), FReason);
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
  cBase =
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
  mRequest: TMoveMemberRequest;
  mPlan: TMoveMemberPlan;
begin
  FFiles.Put(cFileU, cBase);
  mRequest := Default(TMoveMemberRequest);
  mRequest.Members := Ids(cBase, 'TBase', ['Load']);
  mRequest.Usages := [TMemberUsage.Create(mRequest.Members[0], 'Main.pas:12')];
  Assert.IsFalse(TMoveMember.PushDown(FFiles, TMemberClassRef.Create(cFileU, 'TBase'),
    [TMemberClassRef.Create(cFileU, 'TChild')], mRequest, mPlan, FReason));
  Assert.IsTrue(ContainsStr(FReason, 'außerhalb der Nachfahren über TBase benutzt: Main.pas:12'), FReason);
  Assert.AreEqual(cBase, FFiles.Text(cFileU));
end;

procedure TMoveMemberTests.PushDownKeepsAbstract;
const
  cBase =
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
  mPlan: TMoveMemberPlan;
begin
  FFiles.Put(cFileU, cBase);
  Assert.IsTrue(Down(['Load'], True, ['TChild', 'TOther'], mPlan), FReason);
  Assert.IsTrue(Parses(FText), FText);
  Assert.AreEqual('TBase = class|public|/// <summary>Laedt.</summary>|procedure Load; overload; virtual; abstract;|' +
    'end;|', ClassText(FText, 'TBase'));
  Assert.AreEqual('TChild = class(TBase)|/// <summary>Laedt.</summary>|procedure Load; overload; override;|' +
    'end;|', ClassText(FText, 'TChild'));
  // TOther überschreibt schon: bleibt.
  Assert.AreEqual('TOther = class(TBase)|public|procedure Load; overload; override;|end;|',
    ClassText(FText, 'TOther'));
  Assert.IsTrue(ContainsStr(FText, 'procedure TChild.Load;'), FText);
  Assert.AreEqual(0, Integer(Length(mPlan.Warnings)));
  // Nur ein Nachfahr von zweien: Hinweis.
  FFiles.Put(cFileU, cBase);
  Assert.IsTrue(Down(['Load'], True, ['TChild'], mPlan), FReason);
  Assert.AreEqual(1, Integer(Length(mPlan.Warnings)));
end;

procedure TMoveMemberTests.PushDownRaisesHiddenNeeds;
const
  cBase =
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
  mPlan: TMoveMemberPlan;
begin
  FFiles.Put(cFileU, cBase);
  Assert.IsTrue(Down(['Load'], False, ['TChild'], mPlan), FReason);
  Assert.IsTrue(Parses(FText), FText);
  Assert.AreEqual('TBase = class|protected|FSecret: Integer;|end;|', ClassText(FText, 'TBase'));
  Assert.AreEqual('FSecret', mPlan.Raised[0]);
end;

initialization
  TDUnitX.RegisterTestFixture(TMoveMemberTests);

end.
