unit Atlas.Common.Rules.Builtin.Style.MethodOrder;

// Stilregel method-order (#1840), registriert mit den übrigen Stilregeln (RegisterStyleRules), Standard aus:
//   je Typ ein Befund am Typnamen im ersten Rumpf, wenn seine Rümpfe untereinander nicht in der Ordnung der
//   Option "placement" stehen (Vorgabe grouped wie editor.methodPlacement; off schaltet die Regel ab), und einer,
//   wenn classCompletion.typeComment nicht off ist und über den Rümpfen kein Typkommentar steht. Rümpfe, die beim
//   Ordnen stehen bleiben (Region, {$IF…}, geteilte Zeile), zählen nicht als falsch. Korrekturen: nur diesen Typ
//   ordnen wie der Befehl „Methodenrümpfe ordnen“ bzw. den Kommentar in der eingestellten Form einfügen. Prüfung
//   und Änderungen liefert TMethodOrder.Review.

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
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.MethodOrder,
  Atlas.Common.Editing.TypeComments,
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

/// <summary>Name der Ordnung in der Meldung.</summary>
function PlacementText(APlacement: TMethodPlacement): string;
begin
  case APlacement of
    TMethodPlacement.Alphabetical:
      Result := cTexts[TMethodOrderText.Alphabetical].Text;
    TMethodPlacement.Grouped:
      Result := cTexts[TMethodOrderText.Grouped].Text;
  else
    Result := cTexts[TMethodOrderText.Declaration].Text;
  end;
end;

/// <summary>Ordnung und Kommentarform aus der Option placement und classCompletion (#1834).</summary>
function OptionsOf(const AContext: TRuleContext): TMethodOrderOptions;
var
  mSettings: TClassCompletionSettings;
begin
  mSettings := AContext.ClassCompletion;
  if mSettings.TypeComment = '' then
  begin
    mSettings := TClassCompletionSettings.Default;
  end;
  Result := TMethodOrderOptions.Create(TMethodOrder.PlacementOf(TRuleOptions.Text(AContext.Options, 'placement',
    TMethodOrder.PlacementName(TMethodPlacement.Grouped))));
  Result.LifecycleFirst := mSettings.LifecycleFirst;
  Result.TypeComment := TTypeComments.StyleOf(mSettings.TypeComment);
  Result.LineLength := AContext.Formatting.MaxLineLength;
end;

{ TMethodOrderRule }

function TMethodOrderRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('method-order', TRuleSeverity.Hint, cTexts[TMethodOrderText.Title].Text);
end;

procedure TMethodOrderRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mOptions: TMethodOrderOptions;
  mReview: TMethodTypeReview;
begin
  mOptions := OptionsOf(AContext);
  for mReview in TMethodOrder.Review(AContext.Tree, AContext.Text, mOptions) do
  begin
    if mReview.OrderEdits <> nil then
    begin
      AReport.Add(mReview.NameRange, cTexts[TMethodOrderText.NotInOrder].Fmt([mReview.TypeName,
        PlacementText(mOptions.Placement)]), [TRuleFix.Create(cTexts[TMethodOrderText.ArrangeFix].Fmt(
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
