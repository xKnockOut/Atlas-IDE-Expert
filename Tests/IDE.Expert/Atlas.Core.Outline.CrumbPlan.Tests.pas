unit Atlas.Core.Outline.CrumbPlan.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCrumbPlanTests = class
  public
    [Test]
    procedure PartsFollowSettings;
    [Test]
    procedure KeySameIgnoresCase;
    [Test]
    procedure KeyDiffersBySettingsAndStamp;
    [Test]
    procedure JumpUnitToFileStart;
    [Test]
    procedure JumpSectionToChosenPlace;
    [Test]
    procedure JumpSectionWithoutPlaceGoesNowhere;
    [Test]
    procedure JumpNodeToBodyOrDeclaration;
    [Test]
    procedure JumpUnknownNodeGoesNowhere;
    [Test]
    procedure PlaceCaptionIndentsAndMarks;
    [Test]
    procedure PlacePathByMarkAndGroup;
    [Test]
    procedure PlaceChoiceById;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Palette,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.Breadcrumbs,
  Atlas.Core.Outline.CrumbPlan;

function OffSettings: TAtlasPluginSettings;
begin
  Result := TAtlasPluginSettings.Defaults;
  Result.BreadcrumbsVisibility := False;
  Result.BreadcrumbsMemberBlocks := False;
  Result.BreadcrumbsVisibilityMark := False;
  Result.BreadcrumbsDeclarationBlocks := False;
  Result.BreadcrumbsConditionals := False;
  Result.BreadcrumbsRegions := False;
  Result.BreadcrumbsStatements := False;
  Result.BreadcrumbsOverloads := False;
  Result.BreadcrumbsShowUnit := False;
  Result.BreadcrumbsInterfaces := False;
end;

function Node(ANameLine, ANameCharacter, ABody, ADeclaration: Integer): TAtlasOutlineNode;
begin
  Result := Default(TAtlasOutlineNode);
  Result.NameLine := ANameLine;
  Result.NameCharacter := ANameCharacter;
  Result.Body := ABody;
  Result.Declaration := ADeclaration;
end;

function Place(ALine, ACharacter: Integer): TAtlasCrumbPlace;
begin
  Result := Default(TAtlasCrumbPlace);
  Result.Line := ALine;
  Result.Character := ACharacter;
end;

{ TAtlasCrumbPlanTests }

procedure TAtlasCrumbPlanTests.PartsFollowSettings;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := OffSettings;
  Assert.IsTrue(TAtlasCrumbPlan.Parts(mSettings) = []);
  mSettings.BreadcrumbsVisibility := True;
  mSettings.BreadcrumbsRegions := True;
  mSettings.BreadcrumbsOverloads := True;
  Assert.IsTrue(TAtlasCrumbPlan.Parts(mSettings) = [TAtlasCrumbPart.Visibility, TAtlasCrumbPart.Regions,
    TAtlasCrumbPart.Overloads]);
  mSettings := OffSettings;
  mSettings.BreadcrumbsMemberBlocks := True;
  mSettings.BreadcrumbsVisibilityMark := True;
  mSettings.BreadcrumbsDeclarationBlocks := True;
  mSettings.BreadcrumbsConditionals := True;
  mSettings.BreadcrumbsStatements := True;
  Assert.IsTrue(TAtlasCrumbPlan.Parts(mSettings) = [TAtlasCrumbPart.MemberBlocks, TAtlasCrumbPart.VisibilityMark,
    TAtlasCrumbPart.DeclarationBlocks, TAtlasCrumbPart.Conditionals, TAtlasCrumbPart.Statements]);
end;

procedure TAtlasCrumbPlanTests.KeySameIgnoresCase;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := OffSettings;
  Assert.IsTrue(TAtlasCrumbKey.Create('C:\Src\A.pas', 4, mSettings).Same(TAtlasCrumbKey.Create('c:\src\a.PAS', 4,
    mSettings)));
end;

procedure TAtlasCrumbPlanTests.KeyDiffersBySettingsAndStamp;
var
  mSettings, mOther: TAtlasPluginSettings;
  mKey: TAtlasCrumbKey;
begin
  mSettings := OffSettings;
  mKey := TAtlasCrumbKey.Create('A.pas', 4, mSettings);
  Assert.IsFalse(mKey.Same(TAtlasCrumbKey.Create('A.pas', 5, mSettings)));
  Assert.IsFalse(mKey.Same(TAtlasCrumbKey.Create('B.pas', 4, mSettings)));
  mOther := OffSettings;
  mOther.BreadcrumbsShowUnit := True;
  Assert.IsFalse(mKey.Same(TAtlasCrumbKey.Create('A.pas', 4, mOther)));
  mOther := OffSettings;
  mOther.BreadcrumbsInterfaces := True;
  Assert.IsFalse(mKey.Same(TAtlasCrumbKey.Create('A.pas', 4, mOther)));
  mOther := OffSettings;
  mOther.BreadcrumbsStatements := True;
  Assert.IsFalse(mKey.Same(TAtlasCrumbKey.Create('A.pas', 4, mOther)));
end;

procedure TAtlasCrumbPlanTests.JumpUnitToFileStart;
var
  mCrumb: TAtlasCrumb;
begin
  mCrumb := Default(TAtlasCrumb);
  mCrumb.Node := -1;
  mCrumb.Badge.Kind := TAtlasBadgeKind.Unit_;
  Assert.AreEqual<TAtlasCrumbJumpKind>(TAtlasCrumbJumpKind.FileStart, TAtlasCrumbPlan.Jump(nil, mCrumb, False).Kind);
end;

procedure TAtlasCrumbPlanTests.JumpSectionToChosenPlace;
var
  mCrumb: TAtlasCrumb;
  mJump: TAtlasCrumbJump;
begin
  mCrumb := Default(TAtlasCrumb);
  mCrumb.Node := -1;
  mCrumb.Badge.Kind := TAtlasBadgeKind.Type_;
  mCrumb.Places := TArray<TAtlasCrumbPlace>.Create(Place(3, 2), Place(8, 4));
  mCrumb.Current := 1;
  mJump := TAtlasCrumbPlan.Jump(nil, mCrumb, True);
  Assert.AreEqual<TAtlasCrumbJumpKind>(TAtlasCrumbJumpKind.Place, mJump.Kind);
  Assert.AreEqual(8, mJump.Line);
  Assert.AreEqual(4, mJump.Character);
end;

procedure TAtlasCrumbPlanTests.JumpSectionWithoutPlaceGoesNowhere;
var
  mCrumb: TAtlasCrumb;
begin
  mCrumb := Default(TAtlasCrumb);
  mCrumb.Node := -1;
  mCrumb.Badge.Kind := TAtlasBadgeKind.Type_;
  mCrumb.Places := TArray<TAtlasCrumbPlace>.Create(Place(3, 2));
  mCrumb.Current := 1;
  Assert.AreEqual<TAtlasCrumbJumpKind>(TAtlasCrumbJumpKind.None, TAtlasCrumbPlan.Jump(nil, mCrumb, False).Kind);
  mCrumb.Current := -1;
  Assert.AreEqual<TAtlasCrumbJumpKind>(TAtlasCrumbJumpKind.None, TAtlasCrumbPlan.Jump(nil, mCrumb, False).Kind);
end;

procedure TAtlasCrumbPlanTests.JumpNodeToBodyOrDeclaration;
var
  mNodes: TAtlasOutlineNodes;
  mCrumb: TAtlasCrumb;
  mJump: TAtlasCrumbJump;
begin
  // Knoten 0: Deklaration mit Rumpf 1; Knoten 1: Rumpf mit Deklaration 0.
  mNodes := TAtlasOutlineNodes.Create(Node(5, 14, 1, -1), Node(40, 20, -1, 0));
  mCrumb := Default(TAtlasCrumb);
  mCrumb.Node := 0;
  mJump := TAtlasCrumbPlan.Jump(mNodes, mCrumb, False);
  Assert.AreEqual<TAtlasCrumbJumpKind>(TAtlasCrumbJumpKind.Place, mJump.Kind);
  Assert.AreEqual(40, mJump.Line);
  Assert.AreEqual(20, mJump.Character);
  mCrumb.Node := 1;
  mJump := TAtlasCrumbPlan.Jump(mNodes, mCrumb, True);
  Assert.AreEqual(5, mJump.Line);
  Assert.AreEqual(14, mJump.Character);
end;

procedure TAtlasCrumbPlanTests.JumpUnknownNodeGoesNowhere;
var
  mCrumb: TAtlasCrumb;
begin
  mCrumb := Default(TAtlasCrumb);
  mCrumb.Node := 3;
  Assert.AreEqual<TAtlasCrumbJumpKind>(TAtlasCrumbJumpKind.None, TAtlasCrumbPlan.Jump(nil, mCrumb, False).Kind);
end;

function MenuPlace(const AText, AGroup, AMark: string; ADepth, ACount: Integer): TAtlasCrumbPlace;
begin
  Result := Default(TAtlasCrumbPlace);
  Result.Text := AText;
  Result.Group := AGroup;
  Result.Mark := AMark;
  Result.Depth := ADepth;
  Result.Count := ACount;
end;

procedure TAtlasCrumbPlanTests.PlaceCaptionIndentsAndMarks;
begin
  Assert.AreEqual('Region', TAtlasCrumbPlan.PlaceCaption(MenuPlace('Region', '', '', 0, 0), 'Region', True));
  Assert.AreEqual('        Innen', TAtlasCrumbPlan.PlaceCaption(MenuPlace('Innen', '', '', 2, 0), 'Innen', False));
  Assert.AreEqual('+ public', TAtlasCrumbPlan.PlaceCaption(MenuPlace('public', '', '+', 0, 3), 'public', True));
  Assert.AreEqual('public', TAtlasCrumbPlan.PlaceCaption(MenuPlace('public', '', '+', 0, 3), 'public', False));
end;

procedure TAtlasCrumbPlanTests.PlacePathByMarkAndGroup;
begin
  Assert.AreEqual<TAtlasCrumbPlacePath>(TAtlasCrumbPlacePath.SectionOne,
    TAtlasCrumbPlan.PlacePath(MenuPlace('public', '', '+', 0, 1), True));
  Assert.AreEqual<TAtlasCrumbPlacePath>(TAtlasCrumbPlacePath.SectionCount,
    TAtlasCrumbPlan.PlacePath(MenuPlace('public', '', '+', 0, 4), True));
  Assert.AreEqual<TAtlasCrumbPlacePath>(TAtlasCrumbPlacePath.Group,
    TAtlasCrumbPlan.PlacePath(MenuPlace('public', 'interface', '+', 0, 4), False));
  Assert.AreEqual<TAtlasCrumbPlacePath>(TAtlasCrumbPlacePath.LineOnly,
    TAtlasCrumbPlan.PlacePath(MenuPlace('x', '', '', 0, 0), True));
end;

procedure TAtlasCrumbPlanTests.PlaceChoiceById;
var
  mChoice: TAtlasCrumbPlaceChoice;
begin
  mChoice := TAtlasCrumbPlan.PlaceChoice(TAtlasCrumbPlan.cAppendId + '2', 3);
  Assert.AreEqual<TAtlasCrumbPlaceAction>(TAtlasCrumbPlaceAction.Append, mChoice.Action);
  Assert.AreEqual(2, mChoice.Index);
  mChoice := TAtlasCrumbPlan.PlaceChoice(TAtlasCrumbPlan.cAppendId + 'x', 3);
  Assert.AreEqual(TAtlasCrumbPlan.cNoSection, mChoice.Index);
  mChoice := TAtlasCrumbPlan.PlaceChoice(TAtlasCrumbPlan.cCreateId + 'private', 3);
  Assert.AreEqual<TAtlasCrumbPlaceAction>(TAtlasCrumbPlaceAction.AddSection, mChoice.Action);
  Assert.AreEqual('private', mChoice.Keyword);
  mChoice := TAtlasCrumbPlan.PlaceChoice('1', 3);
  Assert.AreEqual<TAtlasCrumbPlaceAction>(TAtlasCrumbPlaceAction.Jump, mChoice.Action);
  Assert.AreEqual(1, mChoice.Index);
  Assert.AreEqual<TAtlasCrumbPlaceAction>(TAtlasCrumbPlaceAction.None, TAtlasCrumbPlan.PlaceChoice('3', 3).Action);
  Assert.AreEqual<TAtlasCrumbPlaceAction>(TAtlasCrumbPlaceAction.None, TAtlasCrumbPlan.PlaceChoice('', 3).Action);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCrumbPlanTests);

end.
