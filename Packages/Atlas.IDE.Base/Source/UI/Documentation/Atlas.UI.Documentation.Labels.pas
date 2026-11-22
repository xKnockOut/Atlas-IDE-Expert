unit Atlas.UI.Documentation.Labels;

// Überschriften der XMLDoc-Abschnitte in der Sprache der Oberfläche; eine Stelle für Hover und Detailpanel. Die
// Texte stehen in der gemeinsamen Tabelle (TAtlasStrings), die Grundtabelle in Atlas.Core.Documentation.Layout.

interface

uses
  Atlas.Core.Documentation.Layout;

type
  TAtlasDocLabelTexts = class
  public
    /// <summary>Beschriftungen in der aktuellen Sprache der Oberfläche.</summary>
    class function Current: TAtlasDocLabels; static;
  end;

implementation

uses
  Atlas.Plugin.Localization.Strings;

{ TAtlasDocLabelTexts }

class function TAtlasDocLabelTexts.Current: TAtlasDocLabels;
begin
  // Begründung (Rationale) steht nur in der Grundtabelle; die übrigen Beschriftungen kommen aus Texts.
  Result := TAtlasDocLabels.Current;
  Result.Params := TAtlasStrings.Text(TAtlasTextId.DocParams);
  Result.TypeParams := TAtlasStrings.Text(TAtlasTextId.DocTypeParams);
  Result.Returns := TAtlasStrings.Text(TAtlasTextId.DocReturns);
  Result.Value := TAtlasStrings.Text(TAtlasTextId.DocValue);
  Result.Exceptions := TAtlasStrings.Text(TAtlasTextId.DocExceptions);
  Result.Remarks := TAtlasStrings.Text(TAtlasTextId.DocRemarks);
  Result.Example := TAtlasStrings.Text(TAtlasTextId.DocExample);
  Result.SeeAlso := TAtlasStrings.Text(TAtlasTextId.DocSeeAlso);
  Result.Undocumented := TAtlasStrings.Text(TAtlasTextId.DocUndocumented);
  Result.More := TAtlasStrings.Text(TAtlasTextId.DocMore);
  Result.Less := TAtlasStrings.Text(TAtlasTextId.DocLess);
  Result.CountParam := TAtlasStrings.Text(TAtlasTextId.DocCountParam);
  Result.CountParams := TAtlasStrings.Text(TAtlasTextId.DocCountParams);
  Result.CountTypeParam := TAtlasStrings.Text(TAtlasTextId.DocCountTypeParam);
  Result.CountTypeParams := TAtlasStrings.Text(TAtlasTextId.DocCountTypeParams);
  Result.CountException := TAtlasStrings.Text(TAtlasTextId.DocCountException);
  Result.CountExceptions := TAtlasStrings.Text(TAtlasTextId.DocCountExceptions);
  Result.ItemReturns := TAtlasStrings.Text(TAtlasTextId.DocItemReturns);
  Result.ItemValue := TAtlasStrings.Text(TAtlasTextId.DocItemValue);
  Result.ItemRemarks := TAtlasStrings.Text(TAtlasTextId.DocItemRemarks);
  Result.ItemExample := TAtlasStrings.Text(TAtlasTextId.DocItemExample);
  Result.ItemSeeAlso := TAtlasStrings.Text(TAtlasTextId.DocItemSeeAlso);
end;

end.
