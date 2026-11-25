unit Atlas.Common.Rules.Builtin.Style.MethodOrder;

// Stilregel method-order (#1840), registriert mit den übrigen Stilregeln (RegisterStyleRules), Standard aus:
//   je Typ ein Befund am Typnamen im ersten Rumpf, wenn seine Rümpfe untereinander nicht in der Ordnung der
//   Option "placement" stehen (Vorgabe grouped wie editor.methodPlacement; off schaltet die Regel ab), und einer,
//   wenn classCompletion.typeComment nicht off ist und über den Rümpfen kein Typkommentar steht. Rümpfe, die beim
//   Ordnen stehen bleiben (Region, {$IF…}, geteilte Zeile), zählen nicht als falsch. Korrekturen: nur diesen Typ
//   ordnen wie der Befehl „Methodenrümpfe ordnen“ bzw. den Kommentar in der eingestellten Form einfügen. Prüfung
//   und Änderungen liefert Editing über TCheckRefactorings.Order (Host-Adapter Adapters.Checks.Refactorings); ohne
//   diesen Eintrag schweigt die Regel.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TMethodOrderRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Checks.Contract.Refactorings,
  Atlas.Common.Pascal.TreeHandles,
  Atlas.Common.Rules.Options,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TMethodOrderText = (Title, NotInOrder, ArrangeFix, CommentMissing, CommentFix, Declaration, Alphabetical,
    Grouped);

const
  cTexts: array[TMethodOrderText] of TAtlasText = (
    (De: 'Methodenrümpfe nicht in Klassenordnung'; En: 'Method bodies not in class order'),
    (De: 'Methodenrümpfe von %s stehen nicht in der Klassenordnung (%s)';
     En: 'Method bodies of %s are not in class order (%s)'),
    (De: 'Rümpfe von %s ordnen'; En: 'Arrange bodies of %s'),
    (De: 'Kommentar %s fehlt'; En: 'Comment %s is missing'),
    (De: 'Kommentar %s einfügen'; En: 'Insert comment %s'),
    (De: 'Deklarationsreihenfolge'; En: 'declaration order'),
    (De: 'alphabetisch'; En: 'alphabetical'),
    (De: 'gruppiert'; En: 'grouped'));

{$SCOPEDENUMS OFF}

/// <summary>Name der Ordnung APlacement (declaration, alphabetical, grouped) in der Meldung.</summary>
function PlacementText(const APlacement: string): string;
begin
  if SameText(APlacement, 'alphabetical') then
  begin
    Result := cTexts[TMethodOrderText.Alphabetical].Text;
  end
  else if SameText(APlacement, 'grouped') then
  begin
    Result := cTexts[TMethodOrderText.Grouped].Text;
  end
  else
  begin
    Result := cTexts[TMethodOrderText.Declaration].Text;
  end;
end;

/// <summary>Ordnung und Kommentarform aus der Option placement und classCompletion (#1834).</summary>
function RequestOf(const AContext: TRuleContext): TCheckMethodOrderRequest;
var
  mSettings: TClassCompletionSettings;
begin
  mSettings := AContext.ClassCompletion;
  if mSettings.TypeComment = '' then
  begin
    mSettings := TClassCompletionSettings.Default;
  end;
  Result := Default(TCheckMethodOrderRequest);
  Result.Placement := TRuleOptions.Text(AContext.Options, 'placement', 'grouped');
  Result.LifecycleFirst := mSettings.LifecycleFirst;
  Result.BlankLines := mSettings.BlankLines;
  Result.TypeComment := mSettings.TypeComment;
  Result.LineLength := AContext.Formatting.MaxLineLength;
end;

{ TMethodOrderRule }

function TMethodOrderRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('method-order', TRuleSeverity.Hint, cTexts[TMethodOrderText.Title].Text);
end;

procedure TMethodOrderRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mResult: TCheckMethodOrderReview;
  mReview: TCheckMethodTypeReview;
begin
  if (AContext.Tree = nil) or (AContext.Refactorings.Order = nil) then
  begin
    Exit;
  end;
  mResult := AContext.Refactorings.Order.Review(AContext.Text, TSyntaxTreeHandles.Wrap(AContext.Tree),
    RequestOf(AContext));
  for mReview in mResult.Types do
  begin
    if mReview.OrderEdits <> nil then
    begin
      AReport.Add(mReview.NameRange, cTexts[TMethodOrderText.NotInOrder].Fmt([mReview.TypeName,
        PlacementText(mResult.Placement)]), [TRuleFix.Create(cTexts[TMethodOrderText.ArrangeFix].Fmt(
        [mReview.TypeName]), mReview.OrderEdits)]);
    end;
    if mReview.CommentEdits <> nil then
    begin
      AReport.Add(mReview.NameRange, cTexts[TMethodOrderText.CommentMissing].Fmt([mReview.CommentText]),
        [TRuleFix.Create(cTexts[TMethodOrderText.CommentFix].Fmt([mReview.CommentText]), mReview.CommentEdits)]);
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Style.MethodOrder', cTexts);

end.
